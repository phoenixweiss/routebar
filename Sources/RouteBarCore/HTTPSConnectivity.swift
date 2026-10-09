import Foundation
import Network
import Security

public enum HTTPSOutcome: String, Sendable, Equatable {
  case reachable
  case unexpectedStatus = "unexpected-http-status"
  case dnsFailure = "dns-failure"
  case connectionFailure = "connection-failure"
  case timeout
  case certificateFailure = "certificate-failure"
  case handshakeFailure = "tls-handshake-failure"
  case authenticationRequired = "authentication-required"
  case protocolFailure = "http-protocol-failure"
  case failed
  case invalidCheck = "invalid-check"

  static func classify(_ error: Error) -> HTTPSOutcome {
    let error = error as NSError
    guard error.domain == NSURLErrorDomain else { return .failed }
    switch URLError.Code(rawValue: error.code) {
    case .timedOut: return .timeout
    case .cannotFindHost, .dnsLookupFailed: return .dnsFailure
    case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
      return .connectionFailure
    case .serverCertificateHasBadDate, .serverCertificateUntrusted,
      .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
      return .certificateFailure
    case .secureConnectionFailed: return .handshakeFailure
    case .userAuthenticationRequired, .clientCertificateRequired: return .authenticationRequired
    default: return .failed
    }
  }
}

public struct HTTPSProbeResult: Sendable, Equatable {
  public let outcome: HTTPSOutcome
  public let statusCode: Int?
  public init(outcome: HTTPSOutcome, statusCode: Int? = nil) {
    self.outcome = outcome
    self.statusCode = statusCode
  }
}

public protocol HTTPSProbing {
  func check(_ check: HTTPSCheck) -> HTTPSProbeResult
}

/// Blocking, off-main-thread HEAD probe using current system routing. Stops at
/// response headers: no body storage, redirects, cookies or authentication.
public struct HTTPSProbe: HTTPSProbing {
  private let evaluator: TLSTrustEvaluator
  private let pathSelector: any ConnectivityPathSelecting
  public init() {
    evaluator = TLSTrustEvaluator()
    pathSelector = SystemConnectivityPathSelector()
  }
  init(
    testAnchors: [SecCertificate],
    pathSelector: any ConnectivityPathSelecting = SystemConnectivityPathSelector()
  ) {
    evaluator = TLSTrustEvaluator(testAnchors: testAnchors)
    self.pathSelector = pathSelector
  }

  public func check(_ check: HTTPSCheck) -> HTTPSProbeResult {
    guard let url = ConfigurationValidator.safeHTTPSURL(check.url),
      check.timeoutSeconds.isFinite, (0.1...30).contains(check.timeoutSeconds),
      !check.expectedStatuses.isEmpty,
      check.expectedStatuses.allSatisfy({ (100...599).contains($0) }),
      Set(check.expectedStatuses).count == check.expectedStatuses.count
    else { return HTTPSProbeResult(outcome: .invalidCheck) }

    guard let urlHost = url.host,
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let port = NWEndpoint.Port(rawValue: UInt16(url.port ?? 443))
    else { return HTTPSProbeResult(outcome: .invalidCheck) }
    let hostname =
      urlHost.hasPrefix("[") && urlHost.hasSuffix("]")
      ? String(urlHost.dropFirst().dropLast()) : urlHost
    let deadline = ConnectivityDeadline(timeout: check.timeoutSeconds)
    let path: ConnectivityPath
    switch pathSelector.select(
      host: hostname, port: Int(port.rawValue), timeout: deadline.remaining)
    {
    case .selected(let selected): path = selected
    case .failed(let outcome):
      return HTTPSProbeResult(outcome: Self.transportOutcome(outcome.rawValue))
    }
    guard deadline.remaining > 0 else { return HTTPSProbeResult(outcome: .timeout) }
    let completion = ConnectivityCompletion<HTTPSProbeResult>()
    let queue = DispatchQueue(label: "routebar.https-probe")
    let tls = makeTLSOptions(hostname: hostname, evaluator: evaluator, queue: queue) {
      completion.finish(HTTPSProbeResult(outcome: .certificateFailure))
    }
    sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, "http/1.1")
    let connection = path.connection(
      port: port, parameters: NWParameters(tls: tls, tcp: NWProtocolTCP.Options()))
    let authority = hostname.contains(":") && !hostname.hasPrefix("[") ? "[\(hostname)]" : hostname
    let hostHeader = port.rawValue == 443 ? authority : "\(authority):\(port.rawValue)"
    let requestPath = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
    let target = requestPath + (components.percentEncodedQuery.map { "?\($0)" } ?? "")
    // Only URL-derived, encoded target data may enter the fixed request headers.
    guard hostHeader.utf8.allSatisfy({ (33...126).contains($0) }),
      target.utf8.allSatisfy({ (33...126).contains($0) }), target.utf8.count <= 8192
    else {
      return HTTPSProbeResult(outcome: .invalidCheck)
    }
    let request = Data(
      "HEAD \(target) HTTP/1.1\r\nHost: \(hostHeader)\r\nConnection: close\r\n\r\n".utf8)
    let receiver = HTTPSHeaderReceiver(check: check, completion: completion)
    connection.stateUpdateHandler = { state in
      switch state {
      case .ready:
        connection.send(
          content: request,
          completion: .contentProcessed { error in
            if let error {
              completion.finish(
                HTTPSProbeResult(
                  outcome: Self.transportOutcome(TLSOutcome.classify(error).rawValue)))
            } else {
              receiver.receive(connection)
            }
          })
      case .waiting(let error), .failed(let error):
        completion.finish(
          HTTPSProbeResult(outcome: Self.transportOutcome(TLSOutcome.classify(error).rawValue)))
      default: break
      }
    }
    connection.start(queue: queue)
    defer {
      connection.stateUpdateHandler = nil
      connection.cancel()
    }
    return completion.wait(
      timeout: deadline.remaining, timeoutOutcome: HTTPSProbeResult(outcome: .timeout))
  }

  private static func transportOutcome(_ rawValue: String) -> HTTPSOutcome {
    if ["refused", "unreachable"].contains(rawValue) { return .connectionFailure }
    return HTTPSOutcome(rawValue: rawValue) ?? .failed
  }
}

/// HEAD needs only a bounded HTTP/1.x header block. There is no body parser,
/// redirect handling, cookie jar, authentication or response-text logging.
struct HTTPSHeaderParser {
  private var buffer = Data()
  private var headerBytes = 0
  private var interimResponses = 0

  mutating func append(_ data: Data) -> Result<Int, HTTPSHeaderError>? {
    buffer.append(data)
    while let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
      let block = buffer[..<end.lowerBound]
      headerBytes += block.count + 4
      guard headerBytes <= 16_384,
        let status = parse(block)
      else { return .failure(.invalidResponse) }
      buffer.removeSubrange(..<end.upperBound)
      if (100...199).contains(status), status != 101 {
        interimResponses += 1
        guard interimResponses <= 8 else { return .failure(.invalidResponse) }
        continue
      }
      return .success(status)
    }
    return headerBytes + buffer.count > 16_384 ? .failure(.invalidResponse) : nil
  }

  private func parse(_ block: Data.SubSequence) -> Int? {
    let lines = String(decoding: block, as: UTF8.self).components(separatedBy: "\r\n")
    guard lines.allSatisfy({ !$0.contains("\r") && !$0.contains("\n") }),
      let line = lines.first, line.utf8.count <= 1024
    else { return nil }
    let fields = line.split(separator: " ", omittingEmptySubsequences: false)
    guard fields.count >= 2, ["HTTP/1.0", "HTTP/1.1"].contains(String(fields[0])),
      fields[1].utf8.count == 3, fields[1].utf8.allSatisfy({ (48...57).contains($0) }),
      let status = Int(fields[1]), (100...599).contains(status),
      block.allSatisfy({ $0 == 13 || $0 == 10 || $0 == 9 || $0 >= 32 && $0 != 127 })
    else { return nil }
    for header in lines.dropFirst() {
      guard let colon = header.firstIndex(of: ":"), colon != header.startIndex,
        header[..<colon].utf8.allSatisfy({
          (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
            || Array("!#$%&'*+-.^_`|~".utf8).contains($0)
        })
      else { return nil }
    }
    return status
  }
}

enum HTTPSHeaderError: Error { case invalidResponse }

private final class HTTPSHeaderReceiver: @unchecked Sendable {
  private let check: HTTPSCheck
  private let completion: ConnectivityCompletion<HTTPSProbeResult>
  // Accessed exclusively on this connection's serial queue.
  private var parser = HTTPSHeaderParser()
  init(check: HTTPSCheck, completion: ConnectivityCompletion<HTTPSProbeResult>) {
    self.check = check
    self.completion = completion
  }
  func receive(_ connection: NWConnection) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, closed, error in
      if let data, let parsed = self.parser.append(data) {
        switch parsed {
        case .success(let status):
          self.completion.finish(
            HTTPSProbeResult(
              outcome: self.check.expectedStatuses.contains(status)
                ? .reachable : .unexpectedStatus,
              statusCode: status))
        case .failure: self.completion.finish(HTTPSProbeResult(outcome: .protocolFailure))
        }
      } else if let error {
        let raw = TLSOutcome.classify(error).rawValue
        self.completion.finish(
          HTTPSProbeResult(
            outcome: ["refused", "unreachable"].contains(raw)
              ? .connectionFailure : HTTPSOutcome(rawValue: raw) ?? .failed))
      } else if closed {
        self.completion.finish(HTTPSProbeResult(outcome: .protocolFailure))
      } else {
        self.receive(connection)
      }
    }
  }
}

public struct HTTPSCheckResult: Sendable, Equatable {
  public let groupID: String
  public let check: HTTPSCheck
  public let result: HTTPSProbeResult
}

public struct HTTPSCheckService {
  private let probe: any HTTPSProbing
  public init(probe: any HTTPSProbing = HTTPSProbe()) { self.probe = probe }
  public func check(configuration: RouteBarConfiguration, profileID: String) throws
    -> [HTTPSCheckResult]
  {
    guard let profile = configuration.profiles.first(where: { $0.id == profileID }) else {
      throw ConfigurationValidationError(message: "Unknown profile: \(profileID)")
    }
    return profile.groups.flatMap { id in
      guard let group = configuration.groups.first(where: { $0.id == id }) else {
        return [HTTPSCheckResult]()
      }
      return group.checks.map { HTTPSCheckResult(groupID: id, check: $0, result: probe.check($0)) }
    }
  }
}
