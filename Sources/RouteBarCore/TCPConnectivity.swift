import Foundation
import Network

public enum TCPOutcome: String, Sendable, Equatable {
  case reachable
  case dnsFailure = "dns-failure"
  case refused
  case unreachable
  case timeout
  case failed
  case invalidEndpoint = "invalid-endpoint"

  static func classify(_ error: NWError) -> TCPOutcome {
    switch error {
    case .dns: return .dnsFailure
    case .posix(let code):
      switch code {
      case .ECONNREFUSED: return .refused
      case .ETIMEDOUT: return .timeout
      case .ENETUNREACH, .EHOSTUNREACH, .ENETDOWN, .EHOSTDOWN: return .unreachable
      default: return .failed
      }
    default: return .failed
    }
  }
}

public protocol TCPProbing {
  func check(_ endpoint: Endpoint) -> TCPOutcome
}

/// Opens and closes a TCP connection without sending application data.
/// DNS resolution and connection establishment share one bounded deadline.
public struct TCPProbe: TCPProbing {
  private let pathSelector: any ConnectivityPathSelecting
  public init() { pathSelector = SystemConnectivityPathSelector() }
  init(pathSelector: any ConnectivityPathSelecting) { self.pathSelector = pathSelector }

  public func check(_ endpoint: Endpoint) -> TCPOutcome {
    guard !endpoint.host.isEmpty,
      (1...65_535).contains(endpoint.port),
      endpoint.timeoutSeconds.isFinite,
      (0.1...30).contains(endpoint.timeoutSeconds),
      let port = NWEndpoint.Port(rawValue: UInt16(endpoint.port))
    else { return .invalidEndpoint }

    let deadline = ConnectivityDeadline(timeout: endpoint.timeoutSeconds)
    let path: ConnectivityPath
    switch pathSelector.select(
      host: endpoint.host, port: endpoint.port, timeout: deadline.remaining)
    {
    case .selected(let selected): path = selected
    case .failed(let outcome): return outcome
    }
    guard deadline.remaining > 0 else { return .timeout }
    let connection = path.connection(port: port, parameters: .tcp)
    let completion = TCPCompletion()
    connection.stateUpdateHandler = { state in
      switch state {
      case .ready: completion.finish(.reachable)
      case .failed(let error), .waiting(let error): completion.finish(TCPOutcome.classify(error))
      default: break
      }
    }
    connection.start(queue: DispatchQueue(label: "routebar.tcp-probe"))
    defer { connection.cancel() }
    return completion.wait(timeout: deadline.remaining)
  }
}

/// Serializes the terminal callback with the deadline; late callbacks cannot
/// replace a completed result or leave an unbounded wait behind.
typealias TCPCompletion = ConnectivityCompletion<TCPOutcome>

extension ConnectivityCompletion where Outcome == TCPOutcome {
  func wait(timeout: Double) -> TCPOutcome { wait(timeout: timeout, timeoutOutcome: .timeout) }
}

final class ConnectivityCompletion<Outcome: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private let semaphore = DispatchSemaphore(value: 0)
  private var outcome: Outcome?

  func finish(_ value: Outcome) {
    lock.lock()
    guard outcome == nil else {
      lock.unlock()
      return
    }
    outcome = value
    lock.unlock()
    semaphore.signal()
  }

  func wait(timeout: Double, timeoutOutcome: Outcome) -> Outcome {
    _ = semaphore.wait(timeout: .now() + timeout)
    lock.lock()
    defer { lock.unlock() }
    if let outcome { return outcome }
    outcome = timeoutOutcome
    return timeoutOutcome
  }
}

public struct TCPCheckResult: Sendable, Equatable {
  public let groupID: String
  public let endpoint: Endpoint
  public let outcome: TCPOutcome
}

public struct TCPCheckService {
  private let probe: any TCPProbing

  public init(probe: any TCPProbing = TCPProbe()) { self.probe = probe }

  /// Explicit profile selection avoids coupling transport checks to route
  /// planning, gateway discovery or route mutations.
  public func check(configuration: RouteBarConfiguration, profileID: String) throws
    -> [TCPCheckResult]
  {
    guard let profile = configuration.profiles.first(where: { $0.id == profileID }) else {
      throw ConfigurationValidationError(message: "Unknown profile: \(profileID)")
    }
    return profile.groups.flatMap { id in
      guard let group = configuration.groups.first(where: { $0.id == id }),
        group.mode == .checkOnly
      else { return [TCPCheckResult]() }
      return group.endpoints.map {
        TCPCheckResult(groupID: id, endpoint: $0, outcome: probe.check($0))
      }
    }
  }
}
