import AppKit
import Foundation
import RouteBarCore
import RouteBarDaemonIPC

enum RouteBarAppState {
  case loading
  case selectingProfile(RouteBarProfileSelectionState)
  case ready(RouteStatusSnapshot, configURL: URL)
  case failed(RouteBarAppFailure)
}

struct RouteBarProfileSelectionState {
  let configURL: URL
  let daemon: DaemonRuntimeStatus
  let checkedAt: Date
}

struct RouteBarAppFailure {
  let message: String
  let configURL: URL
  let daemon: DaemonRuntimeStatus
  let checkedAt: Date
}

private enum RouteBarAppLoadResult: Sendable {
  case ready(
    RouteStatusSnapshot,
    configURL: URL,
    bundledDaemon: BundledDaemonServiceStatus,
    installedDaemon: InstalledDaemonInstallation,
    profiles: [RouteBarProfileOption],
    selectedProfileID: String?
  )
  case selectingProfile(
    configURL: URL,
    daemon: DaemonRuntimeStatus,
    bundledDaemon: BundledDaemonServiceStatus,
    installedDaemon: InstalledDaemonInstallation,
    profiles: [RouteBarProfileOption],
    checkedAt: Date
  )
  case failed(
    String,
    configURL: URL,
    daemon: DaemonRuntimeStatus,
    bundledDaemon: BundledDaemonServiceStatus,
    installedDaemon: InstalledDaemonInstallation,
    profiles: [RouteBarProfileOption],
    selectedProfileID: String?,
    checkedAt: Date
  )

  var bundledDaemonStatus: BundledDaemonServiceStatus {
    switch self {
    case .ready(_, _, let status, _, _, _): status
    case .selectingProfile(_, _, let status, _, _, _): status
    case .failed(_, _, _, let status, _, _, _, _): status
    }
  }

  var installedDaemon: InstalledDaemonInstallation {
    switch self {
    case .ready(_, _, _, let installation, _, _): installation
    case .selectingProfile(_, _, _, let installation, _, _): installation
    case .failed(_, _, _, _, let installation, _, _, _): installation
    }
  }
}

private enum BundledDaemonRegistrationAttempt: Sendable {
  case completed(BundledDaemonServiceStatus)
  case failed(String)
}

private enum BundledDaemonRemovalAttempt: Sendable {
  case completed(BundledDaemonServiceStatus)
  case failed(String)
}

private enum LaunchAtLoginAttempt: Sendable {
  case completed(LaunchAtLoginStatus)
  case failed(String)
}

@MainActor
final class RouteBarAppModel: ObservableObject {
  @Published private(set) var state: RouteBarAppState = .loading
  @Published private(set) var isRefreshing = false
  @Published private(set) var bundledDaemonStatus: BundledDaemonServiceStatus = .checking
  @Published private(set) var bundledDaemonConnectionStatus: BundledDaemonConnectionStatus =
    .notApplicable
  @Published private(set) var bundledDaemonRegistrationState: BundledDaemonRegistrationState =
    .idle
  @Published private(set) var bundledDaemonRemovalState: BundledDaemonRemovalState = .idle
  @Published private(set) var bundledDaemonUpdateState: BundledDaemonUpdateState = .idle
  @Published private(set) var bundledDaemonConfigurationState: BundledDaemonConfigurationState =
    .idle
  @Published private(set) var configuredProfileID: String? = nil
  @Published private(set) var automaticReconciliationEnabled = false
  @Published private(set) var reconciliationDiagnostics: BundledDaemonReconciliationDiagnostics =
    .unknown
  @Published private(set) var bundledDaemonReconciliationState: BundledDaemonReconciliationState =
    .idle
  @Published private(set) var configurationReloadState: BundledDaemonConfigurationReloadState =
    .idle
  @Published private(set) var launchAtLoginStatus: LaunchAtLoginStatus = .checking
  @Published private(set) var launchAtLoginMutationState: LaunchAtLoginMutationState = .idle
  @Published private(set) var installedDaemon: InstalledDaemonInstallation = .notInstalled
  @Published private(set) var profileOptions: [RouteBarProfileOption] = []
  @Published private(set) var selectedProfileID: String? = nil
  @Published var showInDock: Bool {
    didSet {
      UserDefaults.standard.set(showInDock, forKey: Self.showInDockKey)
      RouteBarApplicationController.shared.applyDockVisibility()
    }
  }

  private var pollingStarted = false
  private let installedDaemonInspector: any InstalledDaemonInspecting
  private let bundledDaemonInspector: any BundledDaemonServiceStatusInspecting
  private let bundledDaemonRegistrar: any BundledDaemonServiceRegistering
  private let bundledDaemonReadOnlyInspector: any BundledDaemonReadOnlyInspecting
  private let bundledDaemonConfigurer: any BundledDaemonConfiguring
  private let bundledDaemonReconciler: any BundledDaemonReconciling
  private let launchAtLoginManager: any LaunchAtLoginManaging
  private let appVersion: String
  private static let showInDockKey = "showInDock"

  init(
    installedDaemonInspector: any InstalledDaemonInspecting = SystemInstalledDaemonInspector(),
    bundledDaemonInspector: any BundledDaemonServiceStatusInspecting =
      SystemBundledDaemonServiceStatusInspector(),
    bundledDaemonRegistrar: any BundledDaemonServiceRegistering =
      SystemBundledDaemonServiceRegistrar(),
    bundledDaemonReadOnlyInspector: any BundledDaemonReadOnlyInspecting =
      SystemBundledDaemonReadOnlyInspector(),
    bundledDaemonConfigurer: any BundledDaemonConfiguring =
      SystemBundledDaemonConfigurer(),
    bundledDaemonReconciler: any BundledDaemonReconciling =
      SystemBundledDaemonReconciler(),
    launchAtLoginManager: any LaunchAtLoginManaging = SystemLaunchAtLoginManager(),
    appVersion: String = RouteBarAppVersion.current
  ) {
    self.installedDaemonInspector = installedDaemonInspector
    self.bundledDaemonInspector = bundledDaemonInspector
    self.bundledDaemonRegistrar = bundledDaemonRegistrar
    self.bundledDaemonReadOnlyInspector = bundledDaemonReadOnlyInspector
    self.bundledDaemonConfigurer = bundledDaemonConfigurer
    self.bundledDaemonReconciler = bundledDaemonReconciler
    self.launchAtLoginManager = launchAtLoginManager
    self.appVersion = appVersion
    if UserDefaults.standard.object(forKey: Self.showInDockKey) == nil {
      showInDock = true
    } else {
      showInDock = UserDefaults.standard.bool(forKey: Self.showInDockKey)
    }
  }

  #if DEBUG
    init(
      previewState: RouteBarAppState,
      installedDaemon: InstalledDaemonInstallation = .notInstalled,
      bundledDaemonStatus: BundledDaemonServiceStatus,
      bundledDaemonConnectionStatus: BundledDaemonConnectionStatus = .notApplicable,
      profileOptions: [RouteBarProfileOption] = [],
      selectedProfileID: String? = nil,
      bundledDaemonRegistrationResult: Result<BundledDaemonServiceStatus, Error>? = nil,
      bundledDaemonUnregistrationResult: Result<BundledDaemonServiceStatus, Error>? = nil,
      configuredProfileID: String? = nil,
      bundledDaemonConfigurationResult: Result<String, Error>? = nil,
      automaticReconciliationEnabled: Bool = false,
      reconciliationDiagnostics: BundledDaemonReconciliationDiagnostics = .unknown,
      bundledDaemonReconciliationResult: Result<RouteBarDaemonOperationResult, Error>? = nil,
      bundledDaemonCleanupResult: Result<RouteBarDaemonOperationResult, Error>? = nil,
      configurationReloadState: BundledDaemonConfigurationReloadState = .idle,
      launchAtLoginStatus: LaunchAtLoginStatus = .disabled,
      launchAtLoginMutationResult: Result<LaunchAtLoginStatus, Error>? = nil,
      bundledDaemonReadOnlyResult: Result<BundledDaemonReadOnlyReport, Error>? = nil,
      appVersion: String = "unknown",
      showInDock: Bool
    ) {
      installedDaemonInspector = FixedInstalledDaemonInspector(value: installedDaemon)
      bundledDaemonInspector = FixedBundledDaemonServiceStatusInspector(
        value: bundledDaemonStatus
      )
      bundledDaemonReadOnlyInspector = FixedBundledDaemonReadOnlyInspector(
        result: bundledDaemonReadOnlyResult
          ?? .success(
            BundledDaemonReadOnlyReport(
              helperVersion: "unknown",
              configuredProfileID: configuredProfileID,
              automaticReconciliationEnabled: automaticReconciliationEnabled
            )
          )
      )
      bundledDaemonRegistrar = FixedBundledDaemonServiceRegistrar(
        registrationResult: bundledDaemonRegistrationResult ?? .success(bundledDaemonStatus),
        unregistrationResult: bundledDaemonUnregistrationResult ?? .success(.notRegistered)
      )
      bundledDaemonConfigurer = FixedBundledDaemonConfigurer(
        result: bundledDaemonConfigurationResult ?? .success(selectedProfileID ?? "")
      )
      bundledDaemonReconciler = FixedBundledDaemonReconciler(
        reconciliationResult: bundledDaemonReconciliationResult
          ?? .success(
            RouteBarDaemonOperationResult(
              changedRouteCount: 0,
              activeRouteCount: 0,
              conflictCount: 0
            )
          ),
        cleanupResult: bundledDaemonCleanupResult
          ?? .success(
            RouteBarDaemonOperationResult(
              changedRouteCount: 0,
              activeRouteCount: 0,
              conflictCount: 0
            )
          )
      )
      launchAtLoginManager = FixedLaunchAtLoginManager(
        status: launchAtLoginStatus,
        mutationResult: launchAtLoginMutationResult ?? .success(launchAtLoginStatus)
      )
      self.appVersion = appVersion
      self.showInDock = showInDock
      state = previewState
      self.installedDaemon = installedDaemon
      self.bundledDaemonStatus = bundledDaemonStatus
      self.bundledDaemonConnectionStatus = bundledDaemonConnectionStatus
      self.profileOptions = profileOptions
      self.selectedProfileID = selectedProfileID
      self.configuredProfileID = configuredProfileID
      self.automaticReconciliationEnabled = automaticReconciliationEnabled
      self.reconciliationDiagnostics = reconciliationDiagnostics
      self.configurationReloadState = configurationReloadState
      self.launchAtLoginStatus = launchAtLoginStatus
    }
  #endif

  func startPolling() async {
    guard !pollingStarted else { return }
    pollingStarted = true

    while !Task.isCancelled {
      await refresh()
      do {
        try await Task.sleep(for: .seconds(15))
      } catch {
        return
      }
    }
  }

  func refresh() async {
    guard !isRefreshing, !bundledDaemonUpdateState.isInProgress,
      !configurationReloadState.isInProgress
    else { return }
    isRefreshing = true
    let installedDaemonInspector = installedDaemonInspector
    let bundledDaemonInspector = bundledDaemonInspector
    let bundledDaemonReadOnlyInspector = bundledDaemonReadOnlyInspector
    let appVersion = appVersion
    let requestedProfileID = selectedProfileID
    let launchAtLoginStatus = launchAtLoginManager.status()
    let result = await Task.detached(priority: .userInitiated) {
      Self.loadStatus(
        installedDaemonInspector: installedDaemonInspector,
        bundledDaemonInspector: bundledDaemonInspector,
        selectedProfileID: requestedProfileID
      )
    }.value
    let bundledDaemonReport: BundledDaemonReadOnlyReport?
    if result.bundledDaemonStatus == .enabled {
      bundledDaemonReport = try? await bundledDaemonReadOnlyInspector.inspect()
    } else {
      bundledDaemonReport = nil
    }
    let connectionStatus = BundledDaemonConnectionStatus.resolve(
      serviceStatus: result.bundledDaemonStatus,
      appVersion: appVersion,
      report: bundledDaemonReport
    )
    bundledDaemonConnectionStatus = connectionStatus
    configuredProfileID = bundledDaemonReport?.configuredProfileID
    automaticReconciliationEnabled =
      bundledDaemonReport?.automaticReconciliationEnabled ?? false
    reconciliationDiagnostics = bundledDaemonReport?.reconciliationDiagnostics ?? .unknown
    self.launchAtLoginStatus = launchAtLoginStatus
    synchronizeUpdateState(
      serviceStatus: result.bundledDaemonStatus,
      connectionStatus: connectionStatus
    )
    if configuredProfileID == selectedProfileID, configuredProfileID != nil {
      bundledDaemonConfigurationState = .configured
    } else if bundledDaemonConfigurationState == .configured {
      bundledDaemonConfigurationState = .idle
    }
    installedDaemon = result.installedDaemon
    synchronizeRegistrationState(with: result.bundledDaemonStatus)

    switch result {
    case .ready(
      let snapshot,
      let configURL,
      let bundledDaemon,
      _,
      let profiles,
      let profileID
    ):
      bundledDaemonStatus = bundledDaemon
      profileOptions = profiles
      selectedProfileID = profileID
      state = .ready(snapshot, configURL: configURL)
    case .selectingProfile(
      let configURL,
      let daemon,
      let bundledDaemon,
      _,
      let profiles,
      let checkedAt
    ):
      bundledDaemonStatus = bundledDaemon
      profileOptions = profiles
      selectedProfileID = nil
      state = .selectingProfile(
        RouteBarProfileSelectionState(
          configURL: configURL,
          daemon: daemon,
          checkedAt: checkedAt
        )
      )
    case .failed(
      let message,
      let configURL,
      let daemon,
      let bundledDaemon,
      _,
      let profiles,
      let profileID,
      let checkedAt
    ):
      bundledDaemonStatus = bundledDaemon
      profileOptions = profiles
      selectedProfileID = profileID
      state = .failed(
        RouteBarAppFailure(
          message: message,
          configURL: configURL,
          daemon: daemon,
          checkedAt: checkedAt
        ))
    }
    isRefreshing = false
  }

  func selectProfile(_ profileID: String) {
    guard profileOptions.contains(where: { $0.id == profileID }) else { return }
    guard selectedProfileID != profileID else { return }
    selectedProfileID = profileID
    configurationReloadState = .idle
    Task { await refresh() }
  }

  func enableBundledDaemon() async {
    guard installedDaemon == .notInstalled,
      bundledDaemonStatus == .notRegistered,
      selectedProfileID != nil,
      bundledDaemonRegistrationState != .registering
    else { return }

    bundledDaemonRegistrationState = .registering
    let registrar = bundledDaemonRegistrar
    let attempt = await Task.detached(priority: .userInitiated) {
      do {
        return BundledDaemonRegistrationAttempt.completed(try registrar.register())
      } catch {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return BundledDaemonRegistrationAttempt.failed(message)
      }
    }.value

    switch attempt {
    case .completed(.enabled):
      bundledDaemonRegistrationState = .enabled
      await refresh()
    case .completed(.requiresApproval):
      bundledDaemonRegistrationState = .awaitingApproval
      bundledDaemonStatus = .requiresApproval
      installedDaemon = .bundled
    case .completed(.notRegistered):
      bundledDaemonRegistrationState = .failed(
        "macOS did not register the built-in service. No routes were changed."
      )
    case .completed(.notFound):
      bundledDaemonRegistrationState = .failed(
        "This RouteBar build does not include the built-in service."
      )
    case .completed(.checking), .completed(.unknown):
      bundledDaemonRegistrationState = .failed(
        "macOS did not return a usable service state. No routes were changed."
      )
    case .failed(let message):
      bundledDaemonRegistrationState = .failed(message)
    }
  }

  func openLoginItemsSettings() {
    bundledDaemonRegistrar.openSystemSettings()
  }

  func configureBundledDaemon() async {
    guard bundledDaemonStatus == .enabled,
      case .connected = bundledDaemonConnectionStatus,
      let selectedProfileID,
      bundledDaemonConfigurationState != .configuring,
      !configurationReloadState.isInProgress
    else { return }

    configurationReloadState = .idle
    bundledDaemonConfigurationState = .configuring
    do {
      let configuredProfileID = try await bundledDaemonConfigurer.configure(
        profileID: selectedProfileID
      )
      guard configuredProfileID == selectedProfileID else {
        bundledDaemonConfigurationState = .failed(
          "The built-in service confirmed another profile. No routes were changed."
        )
        return
      }
      self.configuredProfileID = configuredProfileID
      automaticReconciliationEnabled = false
      bundledDaemonConfigurationState = .configured
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      bundledDaemonConfigurationState = .failed(message)
    }
  }

  func applyConfiguredRoutes() async {
    guard bundledDaemonStatus == .enabled,
      case .connected = bundledDaemonConnectionStatus,
      configuredProfileID == selectedProfileID,
      configuredProfileID != nil,
      !automaticReconciliationEnabled,
      bundledDaemonReconciliationState != .applying,
      !configurationReloadState.isInProgress
    else { return }

    configurationReloadState = .idle
    bundledDaemonReconciliationState = .applying
    do {
      let result = try await bundledDaemonReconciler.reconcile()
      guard result.conflictCount == 0 else {
        bundledDaemonReconciliationState = .failed(
          "RouteBar found \(result.conflictCount) route conflict(s) and stopped."
        )
        return
      }
      await refresh()
      automaticReconciliationEnabled = true
      bundledDaemonReconciliationState = .active(result)
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      bundledDaemonReconciliationState = .failed(message)
    }
  }

  func reloadConfiguration() async {
    guard bundledDaemonStatus == .enabled,
      case .connected = bundledDaemonConnectionStatus,
      configuredProfileID == selectedProfileID,
      configuredProfileID != nil,
      automaticReconciliationEnabled,
      !isRefreshing,
      !bundledDaemonUpdateState.isInProgress,
      !bundledDaemonRemovalState.isInProgress,
      bundledDaemonReconciliationState != .applying,
      !configurationReloadState.isInProgress
    else { return }

    configurationReloadState = .reloading
    do {
      let result = try await bundledDaemonReconciler.reconcile()
      let completedAt = Date()
      guard result.conflictCount == 0 else {
        configurationReloadState = .rejected(
          "RouteBar found \(result.conflictCount) route conflict(s) and stopped.",
          at: completedAt
        )
        await refresh()
        return
      }
      configurationReloadState = .applied(result, at: completedAt)
      await refresh()
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      configurationReloadState = .rejected(message, at: Date())
      await refresh()
    }
  }

  func disableBundledDaemon() async {
    guard bundledDaemonStatus == .enabled,
      case .connected = bundledDaemonConnectionStatus,
      !bundledDaemonRemovalState.isInProgress,
      !configurationReloadState.isInProgress
    else { return }

    bundledDaemonRemovalState = .cleaningRoutes
    do {
      let cleanup = try await bundledDaemonReconciler.cleanup()
      guard cleanup.activeRouteCount == 0, cleanup.conflictCount == 0 else {
        bundledDaemonRemovalState = .failed(
          "RouteBar could not confirm that its routes were removed. The service remains enabled."
        )
        return
      }
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      bundledDaemonRemovalState = .failed(
        "Route cleanup failed: \(message). The service remains enabled."
      )
      return
    }

    bundledDaemonRemovalState = .unregistering
    let registrar = bundledDaemonRegistrar
    let attempt = await Task.detached(priority: .userInitiated) {
      do {
        return BundledDaemonRemovalAttempt.completed(try registrar.unregister())
      } catch {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return BundledDaemonRemovalAttempt.failed(message)
      }
    }.value

    switch attempt {
    case .completed(.notRegistered):
      await refresh()
      automaticReconciliationEnabled = false
      configuredProfileID = nil
      configurationReloadState = .idle
      bundledDaemonStatus = .notRegistered
      bundledDaemonConnectionStatus = .notApplicable
      bundledDaemonRegistrationState = .idle
      installedDaemon = .notInstalled
      bundledDaemonRemovalState = .idle
    case .completed:
      bundledDaemonRemovalState = .failed(
        "macOS did not confirm that the built-in service was disabled. Its routes remain removed."
      )
    case .failed(let message):
      bundledDaemonRemovalState = .failed(
        "The routes were removed, but the service could not be disabled: \(message)"
      )
    }
  }

  func updateBundledDaemon() async {
    guard bundledDaemonStatus == .enabled,
      case .versionMismatch = bundledDaemonConnectionStatus,
      !bundledDaemonUpdateState.isInProgress,
      !bundledDaemonRemovalState.isInProgress,
      !configurationReloadState.isInProgress,
      !isRefreshing
    else { return }

    configurationReloadState = .idle
    bundledDaemonUpdateState = .unregistering
    let registrar = bundledDaemonRegistrar
    let unregistration = await Task.detached(priority: .userInitiated) {
      do {
        return BundledDaemonRemovalAttempt.completed(try registrar.unregister())
      } catch {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return BundledDaemonRemovalAttempt.failed(message)
      }
    }.value

    switch unregistration {
    case .completed(.notRegistered):
      bundledDaemonStatus = .notRegistered
      bundledDaemonConnectionStatus = .notApplicable
    case .completed:
      bundledDaemonUpdateState = .failed(
        "macOS did not stop the previous built-in service. Existing routes and settings were left unchanged."
      )
      return
    case .failed(let message):
      bundledDaemonUpdateState = .failed(
        "The previous built-in service could not be stopped: \(message)"
      )
      return
    }

    bundledDaemonUpdateState = .registering
    let registration = await Task.detached(priority: .userInitiated) {
      do {
        return BundledDaemonRegistrationAttempt.completed(try registrar.register())
      } catch {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return BundledDaemonRegistrationAttempt.failed(message)
      }
    }.value

    switch registration {
    case .completed(.enabled):
      bundledDaemonStatus = .enabled
      installedDaemon = .bundled
      bundledDaemonUpdateState = .waitingForService
      guard let report = await waitForUpdatedBundledDaemon() else {
        bundledDaemonConnectionStatus = .unavailable
        bundledDaemonUpdateState = .failed(
          "The service restarted, but the bundled version did not become available. Existing routes and settings were preserved."
        )
        return
      }
      configuredProfileID = report.configuredProfileID
      automaticReconciliationEnabled = report.automaticReconciliationEnabled
      bundledDaemonConnectionStatus = .connected(helperVersion: report.helperVersion)
      bundledDaemonUpdateState = .completed
    case .completed(.requiresApproval):
      bundledDaemonStatus = .requiresApproval
      installedDaemon = .bundled
      bundledDaemonConnectionStatus = .notApplicable
      bundledDaemonUpdateState = .awaitingApproval
    case .completed(let status):
      bundledDaemonStatus = status
      installedDaemon = .notInstalled
      bundledDaemonConnectionStatus = .notApplicable
      bundledDaemonUpdateState = .failed(
        "The previous service stopped, but macOS did not enable the helper bundled with this app. Routes and settings were preserved, but automatic reconciliation is paused."
      )
    case .failed(let message):
      bundledDaemonStatus = bundledDaemonInspector.status()
      if bundledDaemonStatus != .enabled && bundledDaemonStatus != .requiresApproval {
        installedDaemon = .notInstalled
        bundledDaemonConnectionStatus = .notApplicable
      }
      bundledDaemonUpdateState = .failed(
        "The previous service stopped, but the bundled helper could not be enabled: \(message). Routes and settings were preserved, but automatic reconciliation may be paused."
      )
    }
  }

  func setLaunchAtLoginEnabled(_ enabled: Bool) async {
    guard launchAtLoginMutationState != .updating,
      enabled != launchAtLoginStatus.isRegistered
    else { return }

    launchAtLoginMutationState = .updating
    let manager = launchAtLoginManager
    let attempt = await Task.detached(priority: .userInitiated) {
      do {
        return LaunchAtLoginAttempt.completed(try manager.setEnabled(enabled))
      } catch {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return LaunchAtLoginAttempt.failed(message)
      }
    }.value

    switch attempt {
    case .completed(let status):
      launchAtLoginStatus = status
      if enabled, status == .disabled || status == .unavailable {
        launchAtLoginMutationState = .failed(
          "macOS did not enable launch at login."
        )
      } else if !enabled, status.isRegistered || status == .unavailable {
        launchAtLoginMutationState = .failed(
          "macOS did not disable launch at login."
        )
      } else {
        launchAtLoginMutationState = .idle
      }
    case .failed(let message):
      launchAtLoginMutationState = .failed(message)
      launchAtLoginStatus = manager.status()
    }
  }

  func openLaunchAtLoginSettings() {
    launchAtLoginManager.openSystemSettings()
  }

  func openConfiguration() {
    NSWorkspace.shared.open(configurationURL)
  }

  func revealConfiguration() {
    NSWorkspace.shared.activateFileViewerSelecting([configurationURL])
  }

  func showStatusWindow() {
    RouteBarApplicationController.shared.showStatusWindow()
  }

  func quit() {
    NSApplication.shared.terminate(nil)
  }

  private var configurationURL: URL {
    switch state {
    case .ready(_, let configURL): configURL
    case .selectingProfile(let selection): selection.configURL
    case .failed(let failure): failure.configURL
    case .loading: ConfigurationLoader.defaultURL
    }
  }

  private func waitForUpdatedBundledDaemon() async -> BundledDaemonReadOnlyReport? {
    for attempt in 0..<20 {
      if let report = try? await bundledDaemonReadOnlyInspector.inspect(),
        report.helperVersion == appVersion
      {
        return report
      }
      guard attempt < 19 else { break }
      do {
        try await Task.sleep(for: .milliseconds(250))
      } catch {
        return nil
      }
    }
    return nil
  }

  private func synchronizeRegistrationState(with status: BundledDaemonServiceStatus) {
    switch status {
    case .enabled:
      bundledDaemonRegistrationState = .enabled
    case .requiresApproval:
      bundledDaemonRegistrationState = .awaitingApproval
    case .notRegistered:
      switch bundledDaemonRegistrationState {
      case .enabled, .awaitingApproval:
        bundledDaemonRegistrationState = .idle
      case .idle, .registering, .failed:
        break
      }
    case .checking, .notFound, .unknown:
      break
    }
  }

  private func synchronizeUpdateState(
    serviceStatus: BundledDaemonServiceStatus,
    connectionStatus: BundledDaemonConnectionStatus
  ) {
    guard bundledDaemonUpdateState == .awaitingApproval else { return }
    guard serviceStatus == .enabled else { return }
    switch connectionStatus {
    case .connected(let helperVersion) where helperVersion == appVersion:
      bundledDaemonUpdateState = .completed
    case .versionMismatch:
      bundledDaemonUpdateState = .failed(
        "macOS enabled the service, but its version still does not match the app."
      )
    case .unavailable:
      bundledDaemonUpdateState = .failed(
        "macOS enabled the service, but RouteBar could not reach it."
      )
    case .notApplicable, .connected:
      break
    }
  }

  nonisolated private static func loadStatus(
    installedDaemonInspector: any InstalledDaemonInspecting,
    bundledDaemonInspector: any BundledDaemonServiceStatusInspecting,
    selectedProfileID: String?
  ) -> RouteBarAppLoadResult {
    let checkedAt = Date()
    let daemon = SystemDaemonRuntimeInspector().status()
    let bundledDaemon = bundledDaemonInspector.status()
    let installedDaemon = InstalledDaemonPreflight.resolve(
      plistInstallation: installedDaemonInspector.inspect(),
      bundledServiceStatus: bundledDaemon
    )
    if installedDaemon == .unknown {
      return .failed(
        InstalledDaemonInspectionError.unrecognizedConfiguration.localizedDescription,
        configURL: ConfigurationLoader.defaultURL,
        daemon: daemon,
        bundledDaemon: bundledDaemon,
        installedDaemon: installedDaemon,
        profiles: [],
        selectedProfileID: nil,
        checkedAt: checkedAt
      )
    }
    let installedSettings: InstalledDaemonConfiguration?
    if case .legacy(let configuration) = installedDaemon {
      installedSettings = configuration
    } else {
      installedSettings = nil
    }
    let configURL = installedSettings?.configURL ?? ConfigurationLoader.defaultURL

    let configuration: RouteBarConfiguration
    do {
      configuration = try ConfigurationLoader.load(from: configURL)
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      return .failed(
        message,
        configURL: configURL,
        daemon: daemon,
        bundledDaemon: bundledDaemon,
        installedDaemon: installedDaemon,
        profiles: [],
        selectedProfileID: nil,
        checkedAt: checkedAt
      )
    }

    let profileOptions =
      installedSettings == nil
      ? configuration.profiles.map(RouteBarProfileOption.init)
      : []
    let forcedProfileID: String?
    if let installedSettings {
      forcedProfileID = installedSettings.profileID
    } else {
      switch FirstRunProfileSelection.resolve(
        profiles: profileOptions,
        selectedProfileID: selectedProfileID
      ) {
      case .selected(let profileID):
        forcedProfileID = profileID
      case .requiresSelection:
        return .selectingProfile(
          configURL: configURL,
          daemon: daemon,
          bundledDaemon: bundledDaemon,
          installedDaemon: installedDaemon,
          profiles: profileOptions,
          checkedAt: checkedAt
        )
      }
    }

    do {
      let plan = try RoutePlanner().plan(
        configuration: configuration,
        forcedProfileID: forcedProfileID
      )
      let snapshot = try RouteStatusService(
        daemonInspector: FixedDaemonRuntimeInspector(value: daemon)
      ).snapshot(routePlan: plan, checkedAt: checkedAt)
      return .ready(
        snapshot,
        configURL: configURL,
        bundledDaemon: bundledDaemon,
        installedDaemon: installedDaemon,
        profiles: profileOptions,
        selectedProfileID: installedSettings == nil ? forcedProfileID : nil
      )
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      return .failed(
        message,
        configURL: configURL,
        daemon: daemon,
        bundledDaemon: bundledDaemon,
        installedDaemon: installedDaemon,
        profiles: profileOptions,
        selectedProfileID: installedSettings == nil ? forcedProfileID : nil,
        checkedAt: checkedAt
      )
    }
  }

}

private struct FixedDaemonRuntimeInspector: DaemonRuntimeInspecting {
  let value: DaemonRuntimeStatus

  func status() -> DaemonRuntimeStatus { value }
}

#if DEBUG
  private struct FixedInstalledDaemonInspector: InstalledDaemonInspecting {
    let value: InstalledDaemonInstallation

    func inspect() -> InstalledDaemonInstallation { value }
  }

  private struct FixedBundledDaemonServiceStatusInspector:
    BundledDaemonServiceStatusInspecting
  {
    let value: BundledDaemonServiceStatus

    func status() -> BundledDaemonServiceStatus { value }
  }

  private struct FixedBundledDaemonServiceRegistrar: BundledDaemonServiceRegistering {
    let registrationResult: Result<BundledDaemonServiceStatus, Error>
    let unregistrationResult: Result<BundledDaemonServiceStatus, Error>

    func register() throws -> BundledDaemonServiceStatus {
      try registrationResult.get()
    }

    func unregister() throws -> BundledDaemonServiceStatus {
      try unregistrationResult.get()
    }

    func openSystemSettings() {}
  }

  private struct FixedBundledDaemonReadOnlyInspector: BundledDaemonReadOnlyInspecting {
    let result: Result<BundledDaemonReadOnlyReport, Error>

    func inspect() async throws -> BundledDaemonReadOnlyReport {
      try result.get()
    }
  }

  private struct FixedBundledDaemonConfigurer: BundledDaemonConfiguring {
    let result: Result<String, Error>

    func configure(profileID: String) async throws -> String {
      try result.get()
    }
  }

  private struct FixedBundledDaemonReconciler: BundledDaemonReconciling {
    let reconciliationResult: Result<RouteBarDaemonOperationResult, Error>
    let cleanupResult: Result<RouteBarDaemonOperationResult, Error>

    func reconcile() async throws -> RouteBarDaemonOperationResult {
      try reconciliationResult.get()
    }

    func cleanup() async throws -> RouteBarDaemonOperationResult {
      try cleanupResult.get()
    }
  }

  private struct FixedLaunchAtLoginManager: LaunchAtLoginManaging {
    let statusValue: LaunchAtLoginStatus
    let mutationResult: Result<LaunchAtLoginStatus, Error>

    init(
      status: LaunchAtLoginStatus,
      mutationResult: Result<LaunchAtLoginStatus, Error>
    ) {
      statusValue = status
      self.mutationResult = mutationResult
    }

    func status() -> LaunchAtLoginStatus { statusValue }

    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
      try mutationResult.get()
    }

    func openSystemSettings() {}
  }
#endif
