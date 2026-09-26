import AppKit
import RouteBarCore
import SwiftUI
import XCTest

@testable import RouteBarApp

final class RouteBarStatusViewRenderingTests: XCTestCase {
  @MainActor
  func testFirstRunStatusRendersAtSupportedWindowSizes() throws {
    let snapshot = sampleSnapshot()
    let sampleProfile = snapshot.profile
    let model = RouteBarAppModel(
      previewState: .ready(snapshot, configURL: URL(fileURLWithPath: "/tmp/config.yaml")),
      bundledDaemonStatus: .notRegistered,
      profileOptions: [
        RouteBarProfileOption(profile: sampleProfile),
        RouteBarProfileOption(
          profile: Profile(
            id: "travel",
            name: "Travel profile",
            match: ProfileMatch(ssids: ["Travel Wi-Fi"]),
            groups: ["services"]
          )
        ),
      ],
      selectedProfileID: "sample",
      showInDock: true
    )

    try assertRenders(
      RouteBarStatusView(model: model),
      outputPrefix: "routebar-plan"
    )
  }

  @MainActor
  func testBundledDaemonVersionMismatchRendersAtSupportedWindowSizes() throws {
    let snapshot = sampleSnapshot()
    let model = RouteBarAppModel(
      previewState: .ready(snapshot, configURL: URL(fileURLWithPath: "/tmp/config.yaml")),
      bundledDaemonStatus: .enabled,
      bundledDaemonConnectionStatus: .versionMismatch(
        appVersion: "1.2.3",
        helperVersion: "1.2.2"
      ),
      showInDock: true
    )

    try assertRenders(
      RouteBarStatusView(model: model),
      outputPrefix: "routebar-version-mismatch"
    )
  }

  @MainActor
  func testProfileSelectionRendersAtSupportedWindowSizes() throws {
    let daemon = DaemonRuntimeStatus(installed: false, loaded: false)
    let model = RouteBarAppModel(
      previewState: .selectingProfile(
        RouteBarProfileSelectionState(
          configURL: URL(fileURLWithPath: "/tmp/config.yaml"),
          daemon: daemon,
          checkedAt: Date()
        )
      ),
      bundledDaemonStatus: .notRegistered,
      profileOptions: [
        option(id: "home", name: "Home profile"),
        option(id: "work", name: "Work profile"),
      ],
      selectedProfileID: nil,
      showInDock: true
    )

    try assertRenders(
      RouteBarStatusView(model: model),
      outputPrefix: "routebar-profile-selection"
    )
  }

  @MainActor
  func testLegacyDaemonMigrationPreflightRendersAtSupportedWindowSizes() throws {
    let configuration = InstalledDaemonConfiguration(
      configURL: URL(fileURLWithPath: "/tmp/config.yaml"),
      profileID: "sample"
    )
    let model = RouteBarAppModel(
      previewState: .ready(
        sampleSnapshot(
          daemon: DaemonRuntimeStatus(
            installed: true,
            loaded: true,
            runs: 42,
            lastExitCode: 0,
            intervalSeconds: 30
          )
        ),
        configURL: configuration.configURL
      ),
      installedDaemon: .legacy(configuration),
      bundledDaemonStatus: .notRegistered,
      showInDock: true
    )

    try assertRenders(
      RouteBarStatusView(model: model),
      outputPrefix: "routebar-legacy-migration"
    )
  }

  @MainActor
  func testUnknownDaemonMigrationBlockRendersAtSupportedWindowSizes() throws {
    let daemon = DaemonRuntimeStatus(installed: true, loaded: false)
    let model = RouteBarAppModel(
      previewState: .failed(
        RouteBarAppFailure(
          message: InstalledDaemonInspectionError.unrecognizedConfiguration.localizedDescription,
          configURL: URL(fileURLWithPath: "/tmp/config.yaml"),
          daemon: daemon,
          checkedAt: Date()
        )
      ),
      installedDaemon: .unknown,
      bundledDaemonStatus: .unknown,
      showInDock: true
    )

    try assertRenders(
      RouteBarStatusView(model: model),
      outputPrefix: "routebar-unknown-daemon"
    )
  }

  @MainActor
  private func assertRenders<Content: View>(
    _ content: Content,
    outputPrefix: String
  ) throws {
    for size in [NSSize(width: 510, height: 660), NSSize(width: 470, height: 560)] {
      let png = try render(content, at: size)
      XCTAssertGreaterThan(png.count, 10_000)

      if let directory = ProcessInfo.processInfo.environment["ROUTEBAR_STATUS_PREVIEW_DIR"] {
        let name = "\(outputPrefix)-\(Int(size.width))x\(Int(size.height)).png"
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
      }
    }
  }

  @MainActor
  private func render<Content: View>(_ content: Content, at size: NSSize) throws -> Data {
    let hostingView = NSHostingView(rootView: content)
    hostingView.frame = NSRect(origin: .zero, size: size)
    hostingView.layoutSubtreeIfNeeded()

    let representation = try XCTUnwrap(
      hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
    )
    hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
    return try XCTUnwrap(representation.representation(using: .png, properties: [:]))
  }

  private func option(id: String, name: String) -> RouteBarProfileOption {
    RouteBarProfileOption(
      profile: Profile(
        id: id,
        name: name,
        match: ProfileMatch(ssids: ["Sample Wi-Fi"]),
        groups: ["services"]
      )
    )
  }

  private func sampleSnapshot(
    daemon: DaemonRuntimeStatus = DaemonRuntimeStatus(installed: false, loaded: false)
  ) -> RouteStatusSnapshot {
    RouteStatusSnapshot(
      profile: Profile(
        id: "sample",
        name: "Sample profile",
        match: ProfileMatch(ssids: ["Sample Wi-Fi"]),
        groups: ["services"]
      ),
      network: NetworkSnapshot(
        ssid: "Sample Wi-Fi",
        physicalInterface: "en0",
        physicalGateway: "192.0.2.1",
        vpnInterfaces: ["utun4"]
      ),
      groups: [
        RouteGroupStatus(
          groupID: "services",
          name: "Example services",
          targets: [
            RouteTargetStatus(
              address: "192.0.2.10",
              sources: ["service.example"],
              isActive: false,
              observedGateway: nil,
              observedInterface: nil
            ),
            RouteTargetStatus(
              address: "192.0.2.11",
              sources: ["service.example"],
              isActive: false,
              observedGateway: nil,
              observedInterface: nil
            ),
          ]
        )
      ],
      daemon: daemon,
      checkedAt: Date()
    )
  }
}
