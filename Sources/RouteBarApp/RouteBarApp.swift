import AppKit
import SwiftUI

@main
struct RouteBarApp: App {
  @NSApplicationDelegateAdaptor(RouteBarAppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      EmptyView()
    }
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
    if !CommandLine.arguments.contains("--background") {
      controller.showStatusWindow()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    pollingTask?.cancel()
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    RouteBarApplicationController.shared.showStatusWindow()
    return true
  }
}

@MainActor
final class RouteBarApplicationController: NSObject, NSWindowDelegate {
  static let shared = RouteBarApplicationController()

  let model = RouteBarAppModel()
  private var statusWindowController: NSWindowController?

  func showStatusWindow() {
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
    NSApplication.shared.activate(ignoringOtherApps: true)
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
