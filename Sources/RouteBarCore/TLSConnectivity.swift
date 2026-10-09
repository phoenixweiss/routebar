import Foundation
import Network
import Security

public enum TLSOutcome: String, Sendable, Equatable {
  case reachable
  case dnsFailure = "dns-failure"
  case refused
  case unreachable
  case timeout
  case certificateFailure = "certificate-failure"
  case handshakeFailure = "tls-handshake-failure"
  case failed
  case invalidEndpoint = "invalid-endpoint"

  static func classify(_ error: NWError) -> TLSOutcome {
    if case .tls = error { return .handshakeFailure }
    return TLSOutcome(rawValue: TCPOutcome.classify(error).rawValue) ?? .failed
  }
}

public protocol TLSProbing {
  func check(_ endpoint: Endpoint) -> TLSOutcome
}

/// Blocking transport probe; call off the UI thread. Production always uses
/// system trust and hostname validation, without credentials or application data.
public struct TLSProbe: TLSProbing {
  private let trustEvaluator: TLSTrustEvaluator
  private let pathSelector: any ConnectivityPathSelecting

  public init() {
    trustEvaluator = TLSTrustEvaluator()
    pathSelector = SystemConnectivityPathSelector()
  }

  // Isolated tests can trust an ephemeral CA without touching any keychain.
  init(
    testAnchors: [SecCertificate],
    pathSelector: any ConnectivityPathSelecting = SystemConnectivityPathSelector()
  ) {
    trustEvaluator = TLSTrustEvaluator(testAnchors: testAnchors)
    self.pathSelector = pathSelector
  }

  public func check(_ endpoint: Endpoint) -> TLSOutcome {
    guard endpoint.protocol == .tls, !endpoint.host.isEmpty,
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
    case .failed(let outcome): return TLSOutcome(rawValue: outcome.rawValue) ?? .failed
    }
    guard deadline.remaining > 0 else { return .timeout }
    let completion = ConnectivityCompletion<TLSOutcome>()
    let queue = DispatchQueue(label: "routebar.tls-probe")
    let hostname = endpoint.host
    let options = makeTLSOptions(hostname: hostname, evaluator: trustEvaluator, queue: queue) {
      completion.finish(.certificateFailure)
    }

    let connection = path.connection(
      port: port, parameters: NWParameters(tls: options, tcp: NWProtocolTCP.Options()))
    connection.stateUpdateHandler = { state in
      switch state {
      case .ready: completion.finish(.reachable)
      case .waiting(let error), .failed(let error): completion.finish(TLSOutcome.classify(error))
      default: break
      }
    }
    connection.start(queue: queue)
    defer { connection.cancel() }
    return completion.wait(timeout: deadline.remaining, timeoutOutcome: .timeout)
  }
}

func makeTLSOptions(
  hostname: String, evaluator: TLSTrustEvaluator, queue: DispatchQueue,
  onCertificateFailure: @escaping @Sendable () -> Void
) -> NWProtocolTLS.Options {
  let options = NWProtocolTLS.Options()
  sec_protocol_options_set_tls_server_name(options.securityProtocolOptions, hostname)
  sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, .TLSv12)
  sec_protocol_options_set_verify_block(
    options.securityProtocolOptions,
    { _, trust, finish in
      let trusted = evaluator.evaluate(
        sec_trust_copy_ref(trust).takeRetainedValue(), hostname: hostname)
      if !trusted { onCertificateFailure() }
      finish(trusted)
    }, queue)
  return options
}

/// Immutable anchors are test-only. SecTrust instances are evaluated only on
/// their individual probe queues; no shared mutable trust state exists.
final class TLSTrustEvaluator: @unchecked Sendable {
  private let testAnchors: [SecCertificate]?

  init(testAnchors: [SecCertificate]? = nil) { self.testAnchors = testAnchors }

  func evaluate(_ trust: SecTrust, hostname: String) -> Bool {
    guard
      SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, hostname as CFString)) == errSecSuccess,
      SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess
    else { return false }
    if let testAnchors {
      guard SecTrustSetAnchorCertificates(trust, testAnchors as CFArray) == errSecSuccess,
        SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess
      else { return false }
    }
    return SecTrustEvaluateWithError(trust, nil)
  }
}

public struct TLSCheckResult: Sendable, Equatable {
  public let groupID: String
  public let endpoint: Endpoint
  public let outcome: TLSOutcome
}

public struct TLSCheckService {
  private let probe: any TLSProbing

  public init(probe: any TLSProbing = TLSProbe()) { self.probe = probe }

  public func check(configuration: RouteBarConfiguration, profileID: String) throws
    -> [TLSCheckResult]
  {
    guard let profile = configuration.profiles.first(where: { $0.id == profileID }) else {
      throw ConfigurationValidationError(message: "Unknown profile: \(profileID)")
    }
    return profile.groups.flatMap { id in
      guard let group = configuration.groups.first(where: { $0.id == id }), group.mode == .checkOnly
      else { return [TLSCheckResult]() }
      return group.endpoints.filter { $0.protocol == .tls }.map {
        TLSCheckResult(groupID: id, endpoint: $0, outcome: probe.check($0))
      }
    }
  }
}
