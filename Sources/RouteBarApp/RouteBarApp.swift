import AppKit
import Darwin
import SwiftUI

@main
struct RouteBarApp {
  @MainActor
  static func main() {
    if CommandLine.arguments.contains("--register-login-item") {
      do {
        _ = try SystemLaunchAtLoginManager().setEnabled(true)
        exit(EXIT_SUCCESS)
      } catch {
        fputs(
          "RouteBar could not register launch at login: \(error.localizedDescription)\n",
          stderr
        )
        exit(EXIT_FAILURE)
      }
    }

    if CommandLine.arguments.contains("--unregister-login-item") {
      do {
        _ = try SystemLaunchAtLoginManager().setEnabled(false)
        exit(EXIT_SUCCESS)
      } catch {
        fputs(
          "RouteBar could not unregister launch at login: \(error.localizedDescription)\n",
          stderr
        )
        exit(EXIT_FAILURE)
      }
    }

    let application = NSApplication.shared
    let delegate = RouteBarAppDelegate()
    application.delegate = delegate
    application.run()
  }
}

@MainActor
final class RouteBarAppDelegate: NSObject, NSApplicationDelegate {
  private var statusItemController: RouteBarStatusItemController?
  private var pollingTask: Task<Void, Never>?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let controller = RouteBarApplicationController.shared
    statusItemController = RouteBarStatusItemController(model: controller.model)
    pollingTask = Task { await controller.model.startPolling() }
    controller.applyDockVisibility()
    let request: RouteBarWindowPresentationRequest =
      CommandLine.arguments.contains("--background") ? .backgroundLaunch : .foregroundLaunch
    controller.handleStatusWindowRequest(request)
  }

  func applicationWillTerminate(_ notification: Notification) {
    pollingTask?.cancel()
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    RouteBarApplicationController.shared.handleStatusWindowRequest(
      .dockReopen(applicationIsActive: sender.isActive, hasVisibleWindows: flag)
    )
    return false
  }
}

@MainActor
final class RouteBarApplicationController: NSObject, NSWindowDelegate {
  static let shared = RouteBarApplicationController()

  let model = RouteBarAppModel()
  private var statusWindowController: NSWindowController?

  func handleStatusWindowRequest(_ request: RouteBarWindowPresentationRequest) {
    guard let presentation = request.presentation else { return }

    if statusWindowController == nil {
      let content = RouteBarStatusView(model: model)
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 510, height: 660),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
      )
      window.title = "RouteBar"
      window.contentViewController = NSHostingController(rootView: content)
      window.isReleasedWhenClosed = false
      window.minSize = NSSize(width: 470, height: 560)
      window.setContentSize(NSSize(width: 510, height: 660))
      window.setFrameAutosaveName("RouteBarStatusWindowV4")
      window.center()
      window.delegate = self
      statusWindowController = NSWindowController(window: window)
    }

    applyDockVisibility()
    if presentation == .activateApplication {
      NSApplication.shared.activate(ignoringOtherApps: true)
    }
    statusWindowController?.showWindow(nil)
    statusWindowController?.window?.makeKeyAndOrderFront(nil)
    Task { await model.refresh() }
  }

  func applyDockVisibility() {
    let policy: NSApplication.ActivationPolicy = model.showInDock ? .regular : .accessory
    NSApplication.shared.setActivationPolicy(policy)
  }

  func windowWillClose(_ notification: Notification) {
    statusWindowController?.window?.orderOut(nil)
  }
}
