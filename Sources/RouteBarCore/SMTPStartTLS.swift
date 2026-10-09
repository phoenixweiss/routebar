import Foundation
import Network
import Security

public enum SMTPStartTLSOutcome: String, Sendable, Equatable {
  case reachable
  case dnsFailure = "dns-failure"
  case refused
  case unreachable
  case timeout
  case certificateFailure = "certificate-failure"
  case handshakeFailure = "tls-handshake-failure"
  case unsupported = "starttls-not-supported"
  case rejected = "starttls-rejected"
  case protocolFailure = "smtp-protocol-failure"
  case failed
  case invalidEndpoint = "invalid-endpoint"
}

public protocol SMTPStartTLSProbing {
  func check(_ endpoint: Endpoint) -> SMTPStartTLSOutcome
}

/// Blocking, off-main-thread check. Only EHLO and STARTTLS are sent before the
/// verified TLS handshake; no AUTH, message or further SMTP commands are sent.
public struct SMTPStartTLSProbe: SMTPStartTLSProbing {
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

  public func check(_ endpoint: Endpoint) -> SMTPStartTLSOutcome {
    guard endpoint.protocol == .startTLSSMTP, !endpoint.host.isEmpty,
      (1...65_535).contains(endpoint.port), endpoint.timeoutSeconds.isFinite,
      (0.1...30).contains(endpoint.timeoutSeconds),
      let port = NWEndpoint.Port(rawValue: UInt16(endpoint.port))
    else { return .invalidEndpoint }
    let deadline = ConnectivityDeadline(timeout: endpoint.timeoutSeconds)
    let path: ConnectivityPath
    switch pathSelector.select(
      host: endpoint.host, port: endpoint.port, timeout: deadline.remaining)
    {
    case .selected(let selected): path = selected
    case .failed(let outcome): return SMTPStartTLSOutcome(rawValue: outcome.rawValue) ?? .failed
    }
    guard deadline.remaining > 0 else { return .timeout }
    let completion = ConnectivityCompletion<SMTPStartTLSOutcome>()
    let queue = DispatchQueue(label: "routebar.smtp-starttls")
    let tls = makeTLSOptions(hostname: endpoint.host, evaluator: evaluator, queue: queue) {
      completion.finish(.certificateFailure)
    }
    let options = NWProtocolFramer.Options(definition: SMTPStartTLSFramer.definition)
    options["context"] = SMTPStartTLSContext(tls: tls, completion: completion)
    let parameters = NWParameters.tcp
    parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
    let connection = path.connection(port: port, parameters: parameters)
    connection.stateUpdateHandler = { state in
      switch state {
      case .ready: completion.finish(.reachable)
      case .waiting(let error), .failed(let error):
        completion.finish(
          SMTPStartTLSOutcome(rawValue: TLSOutcome.classify(error).rawValue) ?? .failed)
      default: break
      }
    }
    connection.start(queue: queue)
    defer { connection.cancel() }
    return completion.wait(timeout: deadline.remaining, timeoutOutcome: .timeout)
  }
}

/// Incremental reply state, with bounded line and reply lengths. SMTP server
/// text never becomes a command and is never logged or persisted.
struct SMTPStartTLSHandshake {
  enum Action: Equatable {
    case wait
    case sendEHLO
    case sendSTARTTLS
    case upgrade
    case fail(SMTPStartTLSOutcome)
  }
  private enum Stage { case greeting, ehlo, startTLS, done }
  private var stage: Stage = .greeting
  private var replyCode: Int?
  private var lineCount = 0
  private var replyBytes = 0
  private var advertisesSTARTTLS = false

  mutating func receive(line: Data) -> Action {
    guard stage != .done, line.count <= 512, line.count >= 5,
      line.suffix(2) == Data([13, 10])
    else { return .fail(.protocolFailure) }
    let bytes = Array(line.dropLast(2))
    guard bytes.allSatisfy({ $0 >= 32 && $0 <= 126 }),
      bytes.prefix(3).allSatisfy({ (48...57).contains($0) }),
      bytes.count == 3 || bytes[3] == 32 || bytes[3] == 45,
      let code = Int(String(decoding: bytes.prefix(3), as: UTF8.self)), (200...599).contains(code)
    else { return .fail(.protocolFailure) }
    if let replyCode, replyCode != code { return .fail(.protocolFailure) }
    replyCode = code
    lineCount += 1
    replyBytes += line.count
    guard lineCount <= 64, replyBytes <= 16_384 else { return .fail(.protocolFailure) }
    if stage == .ehlo && lineCount > 1,
      String(decoding: bytes.dropFirst(4), as: UTF8.self).uppercased() == "STARTTLS"
    {
      advertisesSTARTTLS = true
    }
    if bytes.count > 3 && bytes[3] == 45 { return .wait }
    replyCode = nil
    lineCount = 0
    replyBytes = 0
    switch stage {
    case .greeting:
      guard code == 220 else { return .fail(.protocolFailure) }
      stage = .ehlo
      return .sendEHLO
    case .ehlo:
      guard code == 250 else { return .fail(.protocolFailure) }
      guard advertisesSTARTTLS else { return .fail(.unsupported) }
      stage = .startTLS
      return .sendSTARTTLS
    case .startTLS:
      guard code == 220 else { return .fail(.rejected) }
      stage = .done
      return .upgrade
    case .done: return .fail(.protocolFailure)
    }
  }
}

private final class SMTPStartTLSContext: @unchecked Sendable {
  let tls: NWProtocolTLS.Options
  let completion: ConnectivityCompletion<SMTPStartTLSOutcome>
  init(tls: NWProtocolTLS.Options, completion: ConnectivityCompletion<SMTPStartTLSOutcome>) {
    self.tls = tls
    self.completion = completion
  }
}

private final class SMTPStartTLSFramer: NWProtocolFramerImplementation {
  static let label = "RouteBar SMTP STARTTLS"
  static let definition = NWProtocolFramer.Definition(implementation: SMTPStartTLSFramer.self)
  private let context: SMTPStartTLSContext?
  private var handshake = SMTPStartTLSHandshake()
  private var finished = false
  private var pendingLine = Data()

  init(framer: NWProtocolFramer.Instance) {
    context = framer.options["context"] as? SMTPStartTLSContext
  }
  func start(framer: NWProtocolFramer.Instance) -> NWProtocolFramer.StartResult { .willMarkReady }

  func handleInput(framer: NWProtocolFramer.Instance) -> Int {
    while !finished {
      var line: Data?
      var invalid = false
      var consumed = 0
      _ = framer.parseInput(minimumIncompleteLength: 1, maximumLength: 512 - pendingLine.count) {
        buffer, complete in
        guard let buffer, !buffer.isEmpty else {
          invalid = complete
          return 0
        }
        for index in 0..<buffer.count {
          pendingLine.append(buffer[index])
          consumed = index + 1
          if pendingLine.count >= 2 && pendingLine.suffix(2) == Data([13, 10]) {
            line = pendingLine
            pendingLine.removeAll(keepingCapacity: true)
            return consumed
          }
        }
        invalid = pendingLine.count >= 512 || complete
        return consumed
      }
      if invalid {
        fail(.protocolFailure, framer: framer)
        return 0
      }
      guard let line else {
        if consumed > 0 { continue }
        return 1
      }
      switch handshake.receive(line: line) {
      case .wait: continue
      case .sendEHLO: framer.writeOutput(data: Data("EHLO routebar.invalid\r\n".utf8))
      case .sendSTARTTLS: framer.writeOutput(data: Data("STARTTLS\r\n".utf8))
      case .fail(let outcome): fail(outcome, framer: framer)
      case .upgrade:
        guard let context else {
          fail(.failed, framer: framer)
          return 0
        }
        do {
          try framer.prependApplicationProtocol(options: context.tls)
          finished = true
          framer.passThroughInput()
          framer.passThroughOutput()
          framer.markReady()
        } catch { fail(.handshakeFailure, framer: framer) }
      }
    }
    return 0
  }

  private func fail(_ outcome: SMTPStartTLSOutcome, framer: NWProtocolFramer.Instance) {
    finished = true
    context?.completion.finish(outcome)
    framer.markFailed(error: .posix(.EPROTO))
  }
  func handleOutput(
    framer: NWProtocolFramer.Instance, message: NWProtocolFramer.Message,
    messageLength: Int, isComplete: Bool
  ) { framer.markFailed(error: .posix(.EPROTO)) }
  func wakeup(framer: NWProtocolFramer.Instance) {}
  func stop(framer: NWProtocolFramer.Instance) -> Bool { true }
  func cleanup(framer: NWProtocolFramer.Instance) {}
}

public struct SMTPStartTLSCheckResult: Sendable, Equatable {
  public let groupID: String
  public let endpoint: Endpoint
  public let outcome: SMTPStartTLSOutcome
}

public struct SMTPStartTLSCheckService {
  private let probe: any SMTPStartTLSProbing
  public init(probe: any SMTPStartTLSProbing = SMTPStartTLSProbe()) { self.probe = probe }
  public func check(configuration: RouteBarConfiguration, profileID: String) throws
    -> [SMTPStartTLSCheckResult]
  {
    guard let profile = configuration.profiles.first(where: { $0.id == profileID }) else {
      throw ConfigurationValidationError(message: "Unknown profile: \(profileID)")
    }
    return profile.groups.flatMap { id in
      guard let group = configuration.groups.first(where: { $0.id == id }), group.mode == .checkOnly
      else { return [SMTPStartTLSCheckResult]() }
      return group.endpoints.filter { $0.protocol == .startTLSSMTP }.map {
        SMTPStartTLSCheckResult(groupID: id, endpoint: $0, outcome: probe.check($0))
      }
    }
  }
}
