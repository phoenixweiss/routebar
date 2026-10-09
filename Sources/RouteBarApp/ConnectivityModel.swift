import Foundation
import RouteBarCore

enum ConnectivityTarget: Sendable, Equatable {
  case endpoint(Endpoint)
  case https(HTTPSCheck)

  var title: String {
    switch self {
    case .endpoint(let endpoint): endpoint.name
    case .https(let check): URLComponents(string: check.url)?.host ?? "HTTPS check"
    }
  }

  var detail: String {
    switch self {
    case .endpoint(let endpoint):
      let transport =
        endpoint.protocol == .startTLSSMTP
        ? "SMTP STARTTLS" : endpoint.protocol.rawValue.uppercased()
      return "\(transport) · \(endpoint.host):\(endpoint.port)"
    case .https: return "HTTPS · HEAD"
    }
  }
}

struct ConnectivityJob: Sendable, Equatable, Identifiable {
  enum SelectionError: Error { case unknownProfile }
  let id: String
  let groupName: String
  let target: ConnectivityTarget

  static func selected(configuration: RouteBarConfiguration, profileID: String) throws -> [Self] {
    guard let profile = configuration.profiles.first(where: { $0.id == profileID }) else {
      throw SelectionError.unknownProfile
    }
    return profile.groups.flatMap { id in
      guard let group = configuration.groups.first(where: { $0.id == id }) else { return [Self]() }
      let endpoints = group.mode == .checkOnly ? group.endpoints : []
      return endpoints.enumerated().map { index, endpoint in
        Self(id: "\(id):endpoint:\(index)", groupName: group.name, target: .endpoint(endpoint))
      }
        + group.checks.enumerated().map { index, check in
          Self(id: "\(id):https:\(index)", groupName: group.name, target: .https(check))
        }
    }
  }
}

struct ConnectivityResult: Sendable, Equatable {
  let outcome: String
  let statusCode: Int?

  init(outcome: String, statusCode: Int? = nil) {
    self.outcome = outcome
    self.statusCode = statusCode
  }

  var isSuccessful: Bool { outcome == "reachable" }

  var summary: String {
    let label: String
    switch outcome {
    case "reachable": label = "Reachable"
    case "dns-failure": label = "DNS failed"
    case "refused": label = "Connection refused"
    case "unreachable", "connection-failure": label = "Connection failed"
    case "timeout": label = "Timed out"
    case "certificate-failure": label = "Certificate error"
    case "tls-handshake-failure": label = "TLS handshake failed"
    case "starttls-not-supported": label = "STARTTLS unavailable"
    case "starttls-rejected": label = "STARTTLS rejected"
    case "smtp-protocol-failure": label = "Invalid SMTP response"
    case "http-protocol-failure": label = "Invalid HTTP response"
    case "unexpected-http-status": label = "Unexpected status"
    case "authentication-required": label = "Authentication required"
    case "invalid-check", "invalid-endpoint": label = "Invalid configuration"
    default: label = "Check failed"
    }
    return statusCode.map { "\(label) · HTTP \($0)" } ?? label
  }
}

protocol ConnectivityRunning: Sendable {
  func check(_ target: ConnectivityTarget) async -> ConnectivityResult
}

struct SystemConnectivityRunner: ConnectivityRunning {
  func check(_ target: ConnectivityTarget) async -> ConnectivityResult {
    await Task.detached(priority: .utility) {
      switch target {
      case .endpoint(let endpoint):
        let outcome: String
        switch endpoint.protocol {
        case .tcp: outcome = TCPProbe().check(endpoint).rawValue
        case .tls: outcome = TLSProbe().check(endpoint).rawValue
        case .startTLSSMTP: outcome = SMTPStartTLSProbe().check(endpoint).rawValue
        }
        return ConnectivityResult(outcome: outcome)
      case .https(let check):
        let result = HTTPSProbe().check(check)
        return ConnectivityResult(outcome: result.outcome.rawValue, statusCode: result.statusCode)
      }
    }.value
  }
}

/// Local UI state only: no route planner, helper calls, timers or window activation.
@MainActor
final class ConnectivityModel: ObservableObject {
  @Published private(set) var jobs: [ConnectivityJob] = []
  @Published private(set) var results: [String: ConnectivityResult] = [:]
  @Published private(set) var isChecking = false
  @Published private(set) var currentJobID: String?
  @Published private(set) var checkedAt: Date?
  @Published private(set) var isStale = false
  @Published private(set) var configurationUnavailable = false

  private let runner: any ConnectivityRunning
  private var context: Context?
  private var revision = 0
  private var preparationRevision = 0

  private struct Context: Equatable {
    let configURL: URL
    let profileID: String
    let network: NetworkSnapshot
    let jobs: [ConnectivityJob]
  }

  init(runner: any ConnectivityRunning = SystemConnectivityRunner()) {
    self.runner = runner
  }

  func prepare(configURL: URL, profileID: String, network: NetworkSnapshot) async {
    preparationRevision += 1
    let request = preparationRevision
    let selected = await Task.detached(priority: .utility) {
      try? ConnectivityJob.selected(
        configuration: ConfigurationLoader.load(from: configURL), profileID: profileID)
    }.value
    guard request == preparationRevision else { return }
    guard let selected else {
      invalidate()
      return
    }
    update(configURL: configURL, profileID: profileID, network: network, jobs: selected)
  }

  func update(configURL: URL, profileID: String, network: NetworkSnapshot, jobs: [ConnectivityJob])
  {
    let newContext = Context(
      configURL: configURL, profileID: profileID, network: network, jobs: jobs)
    guard context != newContext else { return }
    revision += 1
    context = newContext
    configurationUnavailable = false
    let previousJobs = self.jobs
    self.jobs = jobs
    isStale = checkedAt != nil || !results.isEmpty
    results = results.filter { key, _ in
      guard let job = jobs.first(where: { $0.id == key }) else { return false }
      return previousJobs.contains(job)
    }
  }

  func invalidate() {
    preparationRevision += 1
    revision += 1
    context = nil
    configurationUnavailable = true
    isStale = checkedAt != nil || !results.isEmpty
  }

  func run() async {
    guard !isChecking, context != nil, !jobs.isEmpty, !configurationUnavailable else { return }
    let requestedRevision = revision
    let selected = jobs
    isChecking = true
    results = [:]
    checkedAt = nil
    isStale = false
    defer {
      isChecking = false
      currentJobID = nil
    }
    for job in selected {
      guard revision == requestedRevision, !Task.isCancelled else {
        isStale = true
        return
      }
      currentJobID = job.id
      let result = await runner.check(job.target)
      guard revision == requestedRevision, !Task.isCancelled else {
        isStale = true
        return
      }
      results[job.id] = result
    }
    checkedAt = Date()
  }
}
