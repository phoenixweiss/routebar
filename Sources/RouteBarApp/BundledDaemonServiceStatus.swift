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

protocol BundledDaemonServiceRegistering: Sendable {
  func register() throws -> BundledDaemonServiceStatus
  func unregister() throws -> BundledDaemonServiceStatus
  func openSystemSettings()
}

struct SystemBundledDaemonServiceStatusInspector: BundledDaemonServiceStatusInspecting {
  static let plistName = "io.github.phoenixweiss.routebar.plist"

  func status() -> BundledDaemonServiceStatus {
    BundledDaemonServiceStatus(
      SMAppService.daemon(plistName: Self.plistName).status
    )
  }
}

struct SystemBundledDaemonServiceRegistrar: BundledDaemonServiceRegistering {
  func register() throws -> BundledDaemonServiceStatus {
    let service = SMAppService.daemon(
      plistName: SystemBundledDaemonServiceStatusInspector.plistName
    )
    do {
      try service.register()
    } catch {
      let observedStatus = BundledDaemonServiceStatus(service.status)
      if observedStatus == .requiresApproval || observedStatus == .enabled {
        return observedStatus
      }
      throw error
    }
    return BundledDaemonServiceStatus(service.status)
  }

  func unregister() throws -> BundledDaemonServiceStatus {
    let service = SMAppService.daemon(
      plistName: SystemBundledDaemonServiceStatusInspector.plistName
    )
    do {
      try service.unregister()
    } catch {
      let observedStatus = BundledDaemonServiceStatus(service.status)
      if observedStatus == .notRegistered {
        return observedStatus
      }
      throw error
    }
    return BundledDaemonServiceStatus(service.status)
  }

  func openSystemSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }
}

enum BundledDaemonRegistrationState: Sendable, Equatable {
  case idle
  case registering
  case awaitingApproval
  case enabled
  case failed(String)
}

enum BundledDaemonRemovalState: Sendable, Equatable {
  case idle
  case cleaningRoutes
  case unregistering
  case failed(String)

  var isInProgress: Bool {
    switch self {
    case .cleaningRoutes, .unregistering:
      true
    case .idle, .failed:
      false
    }
  }
}

enum BundledDaemonUpdateState: Sendable, Equatable {
  case idle
  case unregistering
  case registering
  case waitingForService
  case awaitingApproval
  case completed
  case failed(String)

  var isInProgress: Bool {
    switch self {
    case .unregistering, .registering, .waitingForService:
      true
    case .idle, .awaitingApproval, .completed, .failed:
      false
    }
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
