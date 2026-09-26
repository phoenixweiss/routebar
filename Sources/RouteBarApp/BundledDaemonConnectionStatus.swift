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
}

protocol BundledDaemonReadOnlyInspecting: Sendable {
  func inspect() async throws -> BundledDaemonReadOnlyReport
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
      configuredProfileID: status.configuredProfileID
    )
  }
}

enum RouteBarAppVersion {
  static var current: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "unknown"
  }
}
