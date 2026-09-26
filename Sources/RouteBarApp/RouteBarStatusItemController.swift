import AppKit
import SwiftUI

@MainActor
final class RouteBarStatusItemController: NSObject {
  private let model: RouteBarAppModel
  private let popover = NSPopover()
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

  init(model: RouteBarAppModel) {
    self.model = model
    super.init()

    popover.behavior = .transient
    popover.animates = true
    popover.contentSize = NSSize(width: 360, height: 178)
    popover.contentViewController = NSHostingController(
      rootView: RouteBarMenuView(model: model) { [weak self] in
        self?.closePopover()
      })

    guard let button = statusItem.button else { return }
    button.image = menuBarImage()
    button.imagePosition = .imageOnly
    button.toolTip = "RouteBar"
    button.target = self
    button.action = #selector(togglePopover(_:))
  }

  @objc private func togglePopover(_ sender: Any?) {
    guard let button = statusItem.button else { return }

    if popover.isShown {
      closePopover()
    } else {
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      Task { await model.refresh() }
    }
  }

  private func closePopover() {
    popover.performClose(nil)
  }

  private func menuBarImage() -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
      NSColor.black.setStroke()

      let circle = NSBezierPath(ovalIn: NSRect(x: 2.25, y: 2.25, width: 13.5, height: 13.5))
      circle.lineWidth = 1.3
      circle.stroke()

      for points in [
        [
          NSPoint(x: 0.75, y: 4.5), NSPoint(x: 7.5, y: 4.5), NSPoint(x: 11, y: 9),
          NSPoint(x: 17.25, y: 9),
        ],
        [
          NSPoint(x: 0.75, y: 9), NSPoint(x: 7.25, y: 9), NSPoint(x: 10.75, y: 13.5),
          NSPoint(x: 17.25, y: 13.5),
        ],
        [
          NSPoint(x: 0.75, y: 13.5), NSPoint(x: 7.5, y: 13.5), NSPoint(x: 11, y: 4.5),
          NSPoint(x: 17.25, y: 4.5),
        ],
      ] {
        let route = NSBezierPath()
        route.move(to: points[0])
        route.line(to: points[1])
        route.curve(to: points[3], controlPoint1: points[1], controlPoint2: points[2])
        route.lineWidth = 1.5
        route.lineCapStyle = .round
        route.lineJoinStyle = .round
        route.stroke()
      }

      return true
    }
    image.isTemplate = true
    return image
  }
}
