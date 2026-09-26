import Foundation
import RouteBarDaemonIPC

enum BundledDaemonConnectionStatus: Sendable, Equatable {
  case notApplicable
  case connected(helperVersion: String)
  case versionMismatch(appVersion: String, helperVersion: String)
  case unavailable

  static func resolve(
    serviceStatus: BundledDaemonServiceStatus,
    appVersion: String,
    report: BundledDaemonReadOnlyReport?
  ) -> BundledDaemonConnectionStatus {
    guard serviceStatus == .enabled else { return .notApplicable }
    guard let report else { return .unavailable }
    guard appVersion != "unknown", report.helperVersion != "unknown" else {
      return .connected(helperVersion: report.helperVersion)
    }
    guard appVersion == report.helperVersion else {
      return .versionMismatch(
        appVersion: appVersion,
        helperVersion: report.helperVersion
      )
    }
    return .connected(helperVersion: report.helperVersion)
  }
}

struct BundledDaemonReadOnlyReport: Sendable, Equatable {
  let helperVersion: String
  let configuredProfileID: String?
  let automaticReconciliationEnabled: Bool

  init(
    helperVersion: String,
    configuredProfileID: String?,
    automaticReconciliationEnabled: Bool = false
  ) {
    self.helperVersion = helperVersion
    self.configuredProfileID = configuredProfileID
    self.automaticReconciliationEnabled = automaticReconciliationEnabled
  }
}

protocol BundledDaemonReadOnlyInspecting: Sendable {
  func inspect() async throws -> BundledDaemonReadOnlyReport
}

protocol BundledDaemonConfiguring: Sendable {
  func configure(profileID: String) async throws -> String
}

protocol BundledDaemonReconciling: Sendable {
  func reconcile() async throws -> RouteBarDaemonOperationResult
  func cleanup() async throws -> RouteBarDaemonOperationResult
}

enum BundledDaemonReadOnlyInspectorError: Error, LocalizedError, Equatable {
  case inconsistentVersion

  var errorDescription: String? {
    switch self {
    case .inconsistentVersion:
      "The daemon returned inconsistent version information"
    }
  }
}

struct SystemBundledDaemonReadOnlyInspector: BundledDaemonReadOnlyInspecting {
  private let client: RouteBarDaemonClient

  init(
    transport: any RouteBarDaemonTransport = RouteBarDaemonXPCTransport()
  ) {
    client = RouteBarDaemonClient(transport: transport)
  }

  func inspect() async throws -> BundledDaemonReadOnlyReport {
    async let versionRequest = client.version()
    async let statusRequest = client.status()
    let (version, status) = try await (versionRequest, statusRequest)
    guard version.helperVersion == status.helperVersion else {
      throw BundledDaemonReadOnlyInspectorError.inconsistentVersion
    }
    return BundledDaemonReadOnlyReport(
      helperVersion: version.helperVersion,
      configuredProfileID: status.configuredProfileID,
      automaticReconciliationEnabled: status.automaticReconciliationEnabled
    )
  }
}

struct SystemBundledDaemonReconciler: BundledDaemonReconciling {
  private let client: RouteBarDaemonClient

  init(
    transport: any RouteBarDaemonTransport = RouteBarDaemonXPCTransport()
  ) {
    client = RouteBarDaemonClient(transport: transport)
  }

  func reconcile() async throws -> RouteBarDaemonOperationResult {
    try await client.reconcile()
  }

  func cleanup() async throws -> RouteBarDaemonOperationResult {
    try await client.cleanup()
  }
}

struct SystemBundledDaemonConfigurer: BundledDaemonConfiguring {
  private let client: RouteBarDaemonClient

  init(
    transport: any RouteBarDaemonTransport = RouteBarDaemonXPCTransport()
  ) {
    client = RouteBarDaemonClient(transport: transport)
  }

  func configure(profileID: String) async throws -> String {
    try await client.configure(profileID: profileID)
  }
}

enum BundledDaemonConfigurationState: Sendable, Equatable {
  case idle
  case configuring
  case configured
  case failed(String)
}

enum BundledDaemonReconciliationState: Sendable, Equatable {
  case idle
  case applying
  case active(RouteBarDaemonOperationResult)
  case failed(String)
}

enum BundledDaemonConfigurationReloadState: Sendable, Equatable {
  case idle
  case reloading
  case applied(RouteBarDaemonOperationResult, at: Date)
  case rejected(String, at: Date)

  var isInProgress: Bool {
    if case .reloading = self {
      return true
    }
    return false
  }
}

enum RouteBarAppVersion {
  static var current: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "unknown"
  }
}
