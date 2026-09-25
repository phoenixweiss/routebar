import AppKit
import SwiftUI

@main
struct RouteBarApp: App {
  @NSApplicationDelegateAdaptor(RouteBarAppDelegate.self) private var appDelegate
  @StateObject private var model = RouteBarApplicationController.shared.model

  var body: some Scene {
    MenuBarExtra {
      RouteBarMenuView(model: model)
    } label: {
      RouteBarMenuBarSymbol()
        .task {
          await model.startPolling()
        }
    }
    .menuBarExtraStyle(.window)
  }
}

@MainActor
final class RouteBarAppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    RouteBarApplicationController.shared.applyDockVisibility()
    if !CommandLine.arguments.contains("--background") {
      RouteBarApplicationController.shared.showStatusWindow()
    }
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
        contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
      )
      window.title = "RouteBar"
      window.contentViewController = NSHostingController(rootView: content)
      window.isReleasedWhenClosed = false
      window.minSize = NSSize(width: 380, height: 420)
      window.setContentSize(NSSize(width: 460, height: 560))
      window.setFrameAutosaveName("RouteBarStatusWindowV2")
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
