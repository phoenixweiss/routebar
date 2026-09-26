import ServiceManagement

enum LaunchAtLoginStatus: Sendable, Equatable {
  case checking
  case disabled
  case enabled
  case requiresApproval
  case unavailable

  init(_ status: SMAppService.Status) {
    switch status {
    case .notRegistered:
      self = .disabled
    case .enabled:
      self = .enabled
    case .requiresApproval:
      self = .requiresApproval
    case .notFound:
      self = .unavailable
    @unknown default:
      self = .unavailable
    }
  }

  var isRegistered: Bool {
    self == .enabled || self == .requiresApproval
  }
}

enum LaunchAtLoginMutationState: Sendable, Equatable {
  case idle
  case updating
  case failed(String)
}

protocol LaunchAtLoginManaging: Sendable {
  func status() -> LaunchAtLoginStatus
  func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus
  func openSystemSettings()
}

struct SystemLaunchAtLoginManager: LaunchAtLoginManaging {
  static let plistName = "io.github.phoenixweiss.routebar.login.plist"

  func status() -> LaunchAtLoginStatus {
    LaunchAtLoginStatus(service.status)
  }

  func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
    let currentStatus = status()
    if enabled, currentStatus.isRegistered {
      return currentStatus
    }
    if !enabled, currentStatus == .disabled {
      return currentStatus
    }

    do {
      if enabled {
        try service.register()
      } else {
        try service.unregister()
      }
    } catch {
      let observedStatus = status()
      if enabled, observedStatus.isRegistered {
        return observedStatus
      }
      if !enabled, observedStatus == .disabled {
        return observedStatus
      }
      throw error
    }
    return status()
  }

  func openSystemSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }

  private var service: SMAppService {
    SMAppService.agent(plistName: Self.plistName)
  }
}
