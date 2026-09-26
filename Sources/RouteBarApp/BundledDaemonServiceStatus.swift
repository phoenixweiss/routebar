import RouteBarCore
import ServiceManagement

enum BundledDaemonServiceStatus: Sendable, Equatable {
  case checking
  case notRegistered
  case enabled
  case requiresApproval
  case notFound
  case unknown

  init(_ status: SMAppService.Status) {
    switch status {
    case .notRegistered:
      self = .notRegistered
    case .enabled:
      self = .enabled
    case .requiresApproval:
      self = .requiresApproval
    case .notFound:
      self = .notFound
    @unknown default:
      self = .unknown
    }
  }
}

protocol BundledDaemonServiceStatusInspecting: Sendable {
  func status() -> BundledDaemonServiceStatus
}

struct SystemBundledDaemonServiceStatusInspector: BundledDaemonServiceStatusInspecting {
  static let plistName = "io.github.phoenixweiss.routebar.plist"

  func status() -> BundledDaemonServiceStatus {
    BundledDaemonServiceStatus(
      SMAppService.daemon(plistName: Self.plistName).status
    )
  }
}

enum InstalledDaemonPreflight {
  static func resolve(
    plistInstallation: InstalledDaemonInstallation,
    bundledServiceStatus: BundledDaemonServiceStatus
  ) -> InstalledDaemonInstallation {
    guard plistInstallation == .notInstalled else { return plistInstallation }
    switch bundledServiceStatus {
    case .enabled, .requiresApproval:
      return .bundled
    case .checking, .notRegistered, .notFound, .unknown:
      return .notInstalled
    }
  }
}
