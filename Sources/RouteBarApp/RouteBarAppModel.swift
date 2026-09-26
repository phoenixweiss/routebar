import AppKit
import Foundation
import RouteBarCore

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

@MainActor
final class RouteBarAppModel: ObservableObject {
  @Published private(set) var state: RouteBarAppState = .loading
  @Published private(set) var isRefreshing = false
  @Published private(set) var bundledDaemonStatus: BundledDaemonServiceStatus = .checking
  @Published private(set) var bundledDaemonConnectionStatus: BundledDaemonConnectionStatus =
    .notApplicable
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
  private let bundledDaemonReadOnlyInspector: any BundledDaemonReadOnlyInspecting
  private let appVersion: String
  private static let showInDockKey = "showInDock"

  init(
    installedDaemonInspector: any InstalledDaemonInspecting = SystemInstalledDaemonInspector(),
    bundledDaemonInspector: any BundledDaemonServiceStatusInspecting =
      SystemBundledDaemonServiceStatusInspector(),
    bundledDaemonReadOnlyInspector: any BundledDaemonReadOnlyInspecting =
      SystemBundledDaemonReadOnlyInspector(),
    appVersion: String = RouteBarAppVersion.current
  ) {
    self.installedDaemonInspector = installedDaemonInspector
    self.bundledDaemonInspector = bundledDaemonInspector
    self.bundledDaemonReadOnlyInspector = bundledDaemonReadOnlyInspector
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
      showInDock: Bool
    ) {
      installedDaemonInspector = FixedInstalledDaemonInspector(value: installedDaemon)
      bundledDaemonInspector = FixedBundledDaemonServiceStatusInspector(
        value: bundledDaemonStatus
      )
      bundledDaemonReadOnlyInspector = FixedBundledDaemonReadOnlyInspector(
        result: .success(
          BundledDaemonReadOnlyReport(
            helperVersion: "unknown",
            configuredProfileID: nil
          )
        )
      )
      appVersion = "unknown"
      self.showInDock = showInDock
      state = previewState
      self.installedDaemon = installedDaemon
      self.bundledDaemonStatus = bundledDaemonStatus
      self.bundledDaemonConnectionStatus = bundledDaemonConnectionStatus
      self.profileOptions = profileOptions
      self.selectedProfileID = selectedProfileID
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
    guard !isRefreshing else { return }
    isRefreshing = true
    let installedDaemonInspector = installedDaemonInspector
    let bundledDaemonInspector = bundledDaemonInspector
    let bundledDaemonReadOnlyInspector = bundledDaemonReadOnlyInspector
    let appVersion = appVersion
    let requestedProfileID = selectedProfileID
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
    installedDaemon = result.installedDaemon

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
    Task { await refresh() }
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

  private struct FixedBundledDaemonReadOnlyInspector: BundledDaemonReadOnlyInspecting {
    let result: Result<BundledDaemonReadOnlyReport, Error>

    func inspect() async throws -> BundledDaemonReadOnlyReport {
      try result.get()
    }
  }
#endif
