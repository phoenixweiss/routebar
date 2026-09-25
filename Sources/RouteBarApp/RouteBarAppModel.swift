import AppKit
import Foundation
import RouteBarCore

enum RouteBarAppState {
  case loading
  case ready(RouteStatusSnapshot, configURL: URL)
  case failed(RouteBarAppFailure)
}

struct RouteBarAppFailure {
  let message: String
  let configURL: URL
  let daemon: DaemonRuntimeStatus
  let checkedAt: Date
}

private enum RouteBarAppLoadResult: Sendable {
  case ready(RouteStatusSnapshot, configURL: URL)
  case failed(String, configURL: URL, daemon: DaemonRuntimeStatus, checkedAt: Date)
}

@MainActor
final class RouteBarAppModel: ObservableObject {
  @Published private(set) var state: RouteBarAppState = .loading
  @Published private(set) var isRefreshing = false
  @Published var showInDock: Bool {
    didSet {
      UserDefaults.standard.set(showInDock, forKey: Self.showInDockKey)
      RouteBarApplicationController.shared.applyDockVisibility()
    }
  }

  private var pollingStarted = false
  private static let showInDockKey = "showInDock"

  init() {
    if UserDefaults.standard.object(forKey: Self.showInDockKey) == nil {
      showInDock = true
    } else {
      showInDock = UserDefaults.standard.bool(forKey: Self.showInDockKey)
    }
  }

  var menuBarSymbol: String {
    switch state {
    case .loading:
      "arrow.triangle.2.circlepath"
    case .ready(let snapshot, _):
      Self.isHealthy(snapshot) ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
    case .failed:
      "xmark.octagon.fill"
    }
  }

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
    let result = await Task.detached(priority: .userInitiated) {
      Self.loadStatus()
    }.value

    switch result {
    case .ready(let snapshot, let configURL):
      state = .ready(snapshot, configURL: configURL)
    case .failed(let message, let configURL, let daemon, let checkedAt):
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
    case .failed(let failure): failure.configURL
    case .loading: ConfigurationLoader.defaultURL
    }
  }

  nonisolated private static func loadStatus() -> RouteBarAppLoadResult {
    let checkedAt = Date()
    let daemon = SystemDaemonRuntimeInspector().status()
    let installedSettings = try? InstalledDaemonConfigurationLoader.load()
    let configURL = installedSettings?.configURL ?? ConfigurationLoader.defaultURL

    do {
      let configuration = try ConfigurationLoader.load(from: configURL)
      let plan = try RoutePlanner().plan(
        configuration: configuration,
        forcedProfileID: installedSettings?.profileID
      )
      let snapshot = try RouteStatusService(
        daemonInspector: FixedDaemonRuntimeInspector(value: daemon)
      ).snapshot(routePlan: plan, checkedAt: checkedAt)
      return .ready(snapshot, configURL: configURL)
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      return .failed(message, configURL: configURL, daemon: daemon, checkedAt: checkedAt)
    }
  }

  private static func isHealthy(_ snapshot: RouteStatusSnapshot) -> Bool {
    snapshot.allRoutesActive
      && snapshot.daemon.installed
      && snapshot.daemon.loaded
      && snapshot.daemon.lastExitCode == 0
  }
}

private struct FixedDaemonRuntimeInspector: DaemonRuntimeInspecting {
  let value: DaemonRuntimeStatus

  func status() -> DaemonRuntimeStatus { value }
}
