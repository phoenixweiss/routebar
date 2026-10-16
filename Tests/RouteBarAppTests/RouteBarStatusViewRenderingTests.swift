import AppKit
import CoreText
import RouteBarCore
import RouteBarDaemonIPC
import SwiftUI
import XCTest

@testable import RouteBarApp

private struct RenderingConnectivityRunner: ConnectivityRunning {
  func check(_ target: ConnectivityTarget) async -> ConnectivityResult {
    switch target {
    case .https: ConnectivityResult(outcome: "unexpected-http-status", statusCode: 503)
    case .endpoint(let endpoint):
      ConnectivityResult(outcome: endpoint.protocol == .tls ? "certificate-failure" : "reachable")
    }
  }
}

final class RouteBarStatusViewRenderingTests: XCTestCase {
  @MainActor
  func testWarningHeaderBackgroundCoversFullWindowWidth() throws {
    let base = sampleSnapshot(routesActive: true)
    let snapshot = RouteStatusSnapshot(
      profile: base.profile, network: base.network,
      groups: [
        RouteGroupStatus(
          groupID: "web", name: "Example services",
          targets: (1...32).map { index in
            RouteTargetStatus(
              address: "192.0.2.\(index)", sources: ["service-\(index).example.org"],
              isActive: index != 32, observedGateway: "192.0.2.1", observedInterface: "en0")
          })
      ], daemon: base.daemon, checkedAt: base.checkedAt)
    let model = RouteBarAppModel(
      previewState: .ready(snapshot, configURL: URL(fileURLWithPath: "/tmp/example.yaml")),
      installedDaemon: .legacy(
        InstalledDaemonConfiguration(
          configURL: URL(fileURLWithPath: "/tmp/example.yaml"), profileID: "home")),
      bundledDaemonStatus: .notRegistered, showInDock: false)
    for width in [470.0, 510.0, 680.0] {
      for theme in [NSAppearance.Name.aqua, .darkAqua] {
        let scheme: ColorScheme = theme == .darkAqua ? .dark : .light
        let png = try render(
          RouteBarStatusView(model: model).statusHeaderContent(colorScheme: scheme)
            .frame(width: width, height: 120, alignment: .top)
            .background(Color(nsColor: .magenta)).environment(\.colorScheme, scheme),
          at: NSSize(width: width, height: 120), appearance: theme)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png))
        let scale = Double(bitmap.pixelsWide) / width
        // A contrasting parent exposes uncovered margins even without a live NSWindow.
        let y = Int(5 * scale)
        let left = try XCTUnwrap(
          bitmap.colorAt(x: bitmap.pixelsWide / 2, y: y)?.usingColorSpace(.deviceRGB))
        let right = try XCTUnwrap(
          bitmap.colorAt(x: bitmap.pixelsWide - Int(3 * scale), y: y)?.usingColorSpace(.deviceRGB))
        XCTAssertEqual(left.redComponent, right.redComponent, accuracy: 0.01, "\(width), \(scheme)")
        XCTAssertEqual(
          left.greenComponent, right.greenComponent, accuracy: 0.01, "\(width), \(scheme)")
        XCTAssertEqual(
          left.blueComponent, right.blueComponent, accuracy: 0.01, "\(width), \(scheme)")
      }
    }
    try assertRenders(
      RouteBarStatusView(model: model), outputPrefix: "routebar-warning-header",
      sizes: [
        NSSize(width: 470, height: 660), NSSize(width: 510, height: 660),
        NSSize(width: 680, height: 660),
      ])
  }

  @MainActor
  func testLargeRouteGroupRendersAsCompactSummary() throws {
    let base = sampleSnapshot(routesActive: true)
    let snapshot = RouteStatusSnapshot(
      profile: base.profile, network: base.network,
      groups: [
        RouteGroupStatus(
          groupID: "projects", name: "Example projects",
          targets: (1...24).map { index in
            RouteTargetStatus(
              address: "192.0.2.\(index)", sources: ["project-\(index).example.org"],
              isActive: true, observedGateway: "192.0.2.1", observedInterface: "en0")
          })
      ], daemon: base.daemon, checkedAt: base.checkedAt)
    let model = RouteBarAppModel(
      previewState: .ready(snapshot, configURL: URL(fileURLWithPath: "/tmp/example.yaml")),
      bundledDaemonStatus: .notRegistered, showInDock: false)
    try assertRenders(
      RouteBarStatusView(model: model), outputPrefix: "routebar-compact-24-destinations",
      sizes: [NSSize(width: 470, height: 560), NSSize(width: 510, height: 900)])
    try assertRenders(
      RouteBarStatusView(model: model, expandedRouteGroups: ["projects"]),
      outputPrefix: "routebar-expanded-24-destinations",
      sizes: [NSSize(width: 470, height: 560), NSSize(width: 510, height: 1100)])
  }

  @MainActor
  func testRulesEditorRendersSavedAndExternalConflictStates() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("config.yaml")
    try editorFixture.write(to: url, atomically: true, encoding: .utf8)
    let model = RulesEditorModel(
      url: url, store: RulesFileStore(backupDirectory: directory.appendingPathComponent("backups")))
    await model.load()
    let view = RulesEditorView(
      model: model, serviceNote: "Rules application is not confirmed.",
      onSaved: { "Rules application is not confirmed." })
    let sizes = [NSSize(width: 720, height: 570), NSSize(width: 820, height: 640)]
    model.name = "Saved group"
    let saved = await model.save()
    XCTAssertTrue(saved)
    try assertRenders(view, outputPrefix: "routebar-rules-saved", sizes: sizes)
    model.name = "Unsaved draft"
    let external = try String(contentsOf: url, encoding: .utf8) + "# external edit\n"
    try external.write(to: url, atomically: true, encoding: .utf8)
    let overwritten = await model.save()
    XCTAssertFalse(overwritten)
    try assertRenders(view, outputPrefix: "routebar-rules-conflict", sizes: sizes)
  }

  @MainActor
  func testRulesEditorRendersExistingNewAndInvalidDrafts() throws {
    let model = RulesEditorModel(
      url: URL(fileURLWithPath: "/tmp/example.yaml"), previewSource: editorFixture)
    let view = RulesEditorView(
      model: model, serviceNote: "Saved and applied are separate states.",
      onSaved: { "Not applied in preview." })
    let sizes = [NSSize(width: 720, height: 570), NSSize(width: 820, height: 640)]
    for scheme in [ColorScheme.light, .dark] {
      let themedView = view.environment(\.colorScheme, scheme)
        .background(scheme == .dark ? Color(nsColor: .windowBackgroundColor) : Color.white)
      let appearance: NSAppearance.Name = scheme == .dark ? .darkAqua : .aqua
      model.discard()
      try assertRenders(
        themedView, outputPrefix: "routebar-rules-existing-\(scheme)", sizes: sizes,
        appearance: appearance)
      model.domainInput = "long-service-name.example.org"
      try assertRenders(
        themedView, outputPrefix: "routebar-rules-input-\(scheme)", sizes: sizes,
        appearance: appearance)
      model.addDomain()
      model.editDomain("long-service-name.example.org")
      try assertRenders(
        themedView, outputPrefix: "routebar-rules-edit-\(scheme)", sizes: sizes,
        appearance: appearance)
      model.newGroup()
      try assertRenders(
        themedView, outputPrefix: "routebar-rules-new-\(scheme)", sizes: sizes,
        appearance: appearance)
      model.domainInput = "*.example.org"
      model.addDomain()
      try assertRenders(
        themedView, outputPrefix: "routebar-rules-error-\(scheme)", sizes: sizes,
        appearance: appearance)
      let hosts =
        ["a-very-long-service-name-for-wrapping-in-a-narrow-editor.example.org"]
        + (1...20).map { "service-\($0).example.org" }
      let denseSource =
        editorFixture.replacingOccurrences(
          of: "domains: [example.org]", with: "domains: [\(hosts.joined(separator: ", "))]")
          + """
          \n  - id: library
              name: Library services
              mode: bypass-vpn
              domains: [library.example.org]
            - id: projects
              name: Проекты и инструменты
              mode: bypass-vpn
              domains: [projects.example.org]
          """
      let denseModel = RulesEditorModel(
        url: URL(fileURLWithPath: "/tmp/example.yaml"), previewSource: denseSource)
      XCTAssertEqual(denseModel.groups.count, 3)
      XCTAssertEqual(denseModel.domains.count, 21)
      try assertRenders(
        RulesEditorView(
          model: denseModel,
          serviceNote:
            "The service reads saved rules every 30 seconds. Check route status after saving; this editor does not confirm application.",
          onSaved: { "Not applied in preview." }
        ).environment(\.colorScheme, scheme)
          .background(scheme == .dark ? Color(nsColor: .windowBackgroundColor) : Color.white),
        outputPrefix: "routebar-rules-dense-\(scheme)", sizes: sizes, appearance: appearance)
    }
  }
  @MainActor
  func testUnresolvedDomainsRenderWithoutReportingHealthyStatus() throws {
    let base = sampleSnapshot(routesActive: true)
    let snapshot = RouteStatusSnapshot(
      profile: base.profile, network: base.network,
      groups: base.groups.map { group in
        RouteGroupStatus(
          groupID: group.groupID, name: group.name, targets: group.targets,
          unresolvedDomains: ["unavailable-service-with-a-long-name.example.org"])
      }, daemon: base.daemon, checkedAt: base.checkedAt)
    XCTAssertFalse(snapshot.allRoutesActive)
    let model = RouteBarAppModel(
      previewState: .ready(snapshot, configURL: URL(fileURLWithPath: "/tmp/example.yaml")),
      bundledDaemonStatus: .notRegistered, showInDock: false)
    try assertRenders(
      RouteBarStatusView(model: model), outputPrefix: "routebar-dns-warning",
      sizes: [NSSize(width: 470, height: 1000), NSSize(width: 510, height: 1000)])
  }
  @MainActor
  func testConnectivityStatesRenderAtSupportedWidths() async throws {
    let configuration = try ConfigurationLoader.load(source: sampleConfiguration)
    let jobs = try ConnectivityJob.selected(configuration: configuration, profileID: "home")
    let connectivity = ConnectivityModel(runner: RenderingConnectivityRunner())
    let snapshot = sampleSnapshot(routesActive: true)
    connectivity.update(
      configURL: URL(fileURLWithPath: "/tmp/example.yaml"), profileID: "home",
      network: snapshot.network, jobs: jobs)
    let sizes = [NSSize(width: 410, height: 620), NSSize(width: 450, height: 620)]
    try assertRenders(
      ConnectivityView(model: ConnectivityModel(), check: {}).padding(20),
      outputPrefix: "routebar-connectivity-empty", sizes: sizes)
    try assertRenders(
      ConnectivityView(model: connectivity, check: {}).padding(20),
      outputPrefix: "routebar-connectivity-unchecked", sizes: sizes)
    await connectivity.run()
    try assertRenders(
      ConnectivityView(model: connectivity, check: {}).padding(20),
      outputPrefix: "routebar-connectivity-results", sizes: sizes)
    connectivity.invalidate()
    try assertRenders(
      ConnectivityView(model: connectivity, check: {}).padding(20),
      outputPrefix: "routebar-connectivity-stale", sizes: sizes)

    let pausedRunner = PausedConnectivityRunner()
    let checking = ConnectivityModel(runner: pausedRunner)
    checking.update(
      configURL: URL(fileURLWithPath: "/tmp/example.yaml"), profileID: "home",
      network: snapshot.network, jobs: jobs)
    let running = Task { await checking.run() }
    await pausedRunner.waitForStart()
    try assertRenders(
      ConnectivityView(model: checking, check: {}).padding(20),
      outputPrefix: "routebar-connectivity-checking", sizes: sizes)
    checking.invalidate()
    await pausedRunner.finish()
    await running.value

    let model = RouteBarAppModel(
      previewState: .ready(snapshot, configURL: URL(fileURLWithPath: "/tmp/example.yaml")),
      installedDaemon: .legacy(
        InstalledDaemonConfiguration(
          configURL: URL(fileURLWithPath: "/tmp/example.yaml"), profileID: "sample")),
      bundledDaemonStatus: .notRegistered, showInDock: true)
    model.connectivity.update(
      configURL: URL(fileURLWithPath: "/tmp/example.yaml"), profileID: "home",
      network: snapshot.network, jobs: jobs)
    try assertRenders(
      RouteBarStatusView(model: model), outputPrefix: "routebar-connectivity-window",
      sizes: [NSSize(width: 470, height: 560), NSSize(width: 510, height: 1200)])
  }

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
  func testPendingApprovalRendersAtSupportedWindowSizes() throws {
    let model = RouteBarAppModel(
      previewState: .ready(
        sampleSnapshot(),
        configURL: URL(fileURLWithPath: "/tmp/config.yaml")
      ),
      installedDaemon: .bundled,
      bundledDaemonStatus: .requiresApproval,
      profileOptions: [option(id: "sample", name: "Sample profile")],
      selectedProfileID: "sample",
      showInDock: true
    )

    try assertRenders(
      RouteBarStatusView(model: model),
      outputPrefix: "routebar-pending-approval"
    )
  }

  @MainActor
  func testReadyToConfigureRendersAtSupportedWindowSizes() throws {
    let model = RouteBarAppModel(
      previewState: .ready(
        sampleSnapshot(),
        configURL: URL(fileURLWithPath: "/tmp/config.yaml")
      ),
      installedDaemon: .bundled,
      bundledDaemonStatus: .enabled,
      bundledDaemonConnectionStatus: .connected(helperVersion: "1.2.3"),
      profileOptions: [option(id: "sample", name: "Sample profile")],
      selectedProfileID: "sample",
      configuredProfileID: nil,
      showInDock: true
    )

    try assertRenders(
      RouteBarStatusView(model: model),
      outputPrefix: "routebar-ready-to-configure"
    )
  }

  @MainActor
  func testReadyToApplyRendersAtSupportedWindowSizes() throws {
    let model = RouteBarAppModel(
      previewState: .ready(
        sampleSnapshot(),
        configURL: URL(fileURLWithPath: "/tmp/config.yaml")
      ),
      installedDaemon: .bundled,
      bundledDaemonStatus: .enabled,
      bundledDaemonConnectionStatus: .connected(helperVersion: "1.2.3"),
      profileOptions: [option(id: "sample", name: "Sample profile")],
      selectedProfileID: "sample",
      configuredProfileID: "sample",
      automaticReconciliationEnabled: false,
      showInDock: true
    )

    try assertRenders(
      RouteBarStatusView(model: model),
      outputPrefix: "routebar-ready-to-apply"
    )
  }

  @MainActor
  func testActiveBundledDaemonRendersAtSupportedWindowSizes() throws {
    let model = RouteBarAppModel(
      previewState: .ready(
        sampleSnapshot(
          daemon: DaemonRuntimeStatus(
            installed: true,
            loaded: true,
            runs: 42,
            lastExitCode: 0,
            intervalSeconds: 30
          ),
          routesActive: true
        ),
        configURL: URL(fileURLWithPath: "/tmp/config.yaml")
      ),
      installedDaemon: .bundled,
      bundledDaemonStatus: .enabled,
      bundledDaemonConnectionStatus: .connected(helperVersion: "1.2.3"),
      profileOptions: [option(id: "sample", name: "Sample profile")],
      selectedProfileID: "sample",
      configuredProfileID: "sample",
      automaticReconciliationEnabled: true,
      configurationReloadState: .applied(
        RouteBarDaemonOperationResult(
          changedRouteCount: 1,
          activeRouteCount: 2,
          conflictCount: 0
        ),
        at: Date()
      ),
      launchAtLoginStatus: .enabled,
      showInDock: true
    )

    try assertRenders(
      RouteBarStatusView(model: model),
      outputPrefix: "routebar-active-bundled-daemon",
      sizes: [
        NSSize(width: 510, height: 660),
        NSSize(width: 470, height: 560),
        NSSize(width: 510, height: 900),
      ]
    )
  }

  @MainActor
  func testRejectedConfigurationRendersAtSupportedWindowSizes() throws {
    let model = RouteBarAppModel(
      previewState: .ready(
        sampleSnapshot(
          daemon: DaemonRuntimeStatus(
            installed: true,
            loaded: true,
            runs: 42,
            lastExitCode: 0,
            intervalSeconds: 30
          ),
          routesActive: true
        ),
        configURL: URL(fileURLWithPath: "/tmp/config.yaml")
      ),
      installedDaemon: .bundled,
      bundledDaemonStatus: .enabled,
      bundledDaemonConnectionStatus: .connected(helperVersion: "1.2.3"),
      profileOptions: [option(id: "sample", name: "Sample profile")],
      selectedProfileID: "sample",
      configuredProfileID: "sample",
      automaticReconciliationEnabled: true,
      configurationReloadState: .rejected(
        "The YAML configuration contains an unknown field.",
        at: Date()
      ),
      launchAtLoginStatus: .enabled,
      showInDock: true
    )

    try assertRenders(
      RouteBarStatusView(model: model),
      outputPrefix: "routebar-rejected-configuration",
      sizes: [
        NSSize(width: 510, height: 660),
        NSSize(width: 470, height: 560),
        NSSize(width: 510, height: 900),
      ]
    )
  }

  @MainActor
  func testChangedConfigurationDiagnosticsRenderAtSupportedWindowSizes() throws {
    let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let model = RouteBarAppModel(
      previewState: .ready(
        sampleSnapshot(
          daemon: DaemonRuntimeStatus(
            installed: true,
            loaded: true,
            runs: 42,
            lastExitCode: 0,
            intervalSeconds: 30
          ),
          routesActive: true
        ),
        configURL: URL(fileURLWithPath: "/tmp/config.yaml")
      ),
      installedDaemon: .bundled,
      bundledDaemonStatus: .enabled,
      bundledDaemonConnectionStatus: .connected(helperVersion: "1.2.3"),
      profileOptions: [option(id: "sample", name: "Sample profile")],
      selectedProfileID: "sample",
      configuredProfileID: "sample",
      automaticReconciliationEnabled: true,
      reconciliationDiagnostics: BundledDaemonReconciliationDiagnostics(
        lastAttemptAt: checkedAt,
        lastSuccessfulAt: checkedAt,
        lastResult: RouteBarDaemonOperationResult(
          changedRouteCount: 0,
          activeRouteCount: 2,
          conflictCount: 0
        ),
        configurationRequiresReload: true
      ),
      launchAtLoginStatus: .enabled,
      showInDock: true
    )

    try assertRenders(
      RouteBarStatusView(model: model),
      outputPrefix: "routebar-configuration-changed",
      sizes: [
        NSSize(width: 510, height: 660),
        NSSize(width: 470, height: 560),
        NSSize(width: 510, height: 900),
      ]
    )
  }

  @MainActor
  func testLaunchAtLoginApprovalRendersAtSupportedWindowSizes() throws {
    let model = RouteBarAppModel(
      previewState: .ready(
        sampleSnapshot(),
        configURL: URL(fileURLWithPath: "/tmp/config.yaml")
      ),
      bundledDaemonStatus: .notRegistered,
      launchAtLoginStatus: .requiresApproval,
      showInDock: true
    )

    try assertRenders(
      RouteBarStatusView(model: model),
      outputPrefix: "routebar-login-approval"
    )
  }

  @MainActor
  func testDiagnosticsScreenRendersAtSupportedWindowSizes() throws {
    let diagnostics = RouteBarDiagnostics(
      generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
      appVersion: "1.2.3",
      systemVersion: "macOS 26.0",
      architecture: "Apple silicon",
      state: .ready(
        sampleSnapshot(
          daemon: DaemonRuntimeStatus(
            installed: true,
            loaded: true,
            runs: 42,
            lastExitCode: 0,
            intervalSeconds: 30
          ),
          routesActive: true
        ),
        configURL: URL(fileURLWithPath: "/tmp/config.yaml")
      ),
      installedDaemon: .legacy(
        InstalledDaemonConfiguration(
          configURL: URL(fileURLWithPath: "/tmp/config.yaml"),
          profileID: "sample"
        )
      ),
      bundledDaemonStatus: .notRegistered,
      bundledDaemonConnectionStatus: .notApplicable,
      reconciliationDiagnostics: .unknown
    )

    try assertRenders(
      RouteBarDiagnosticsView(diagnostics: diagnostics),
      outputPrefix: "routebar-diagnostics",
      sizes: [
        NSSize(width: 480, height: 560),
        NSSize(width: 440, height: 500),
      ]
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
    outputPrefix: String,
    sizes: [NSSize] = [NSSize(width: 510, height: 660), NSSize(width: 470, height: 560)],
    appearance: NSAppearance.Name? = nil
  ) throws {
    let appearances = appearance.map { [$0] } ?? [.aqua, .darkAqua]
    for size in sizes {
      for theme in appearances {
        let scheme: ColorScheme = theme == .darkAqua ? .dark : .light
        let png = try render(
          content.environment(\.colorScheme, scheme), at: size, appearance: theme)
        XCTAssertGreaterThan(png.count, 10_000)

        if let directory = ProcessInfo.processInfo.environment["ROUTEBAR_STATUS_PREVIEW_DIR"] {
          let themedPrefix = appearance == nil ? "\(outputPrefix)-\(scheme)" : outputPrefix
          let name = "\(themedPrefix)-\(Int(size.width))x\(Int(size.height)).png"
          try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
        }
      }
    }
  }

  @MainActor
  private func render<Content: View>(
    _ content: Content, at size: NSSize, appearance: NSAppearance.Name? = nil
  ) throws -> Data {
    let fontURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Support/Fonts/Manrope-Variable.ttf")
    CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
    let hostingView = NSHostingView(
      rootView: content.background(Color(nsColor: .windowBackgroundColor)))
    if let appearance { hostingView.appearance = NSAppearance(named: appearance) }
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
    daemon: DaemonRuntimeStatus = DaemonRuntimeStatus(installed: false, loaded: false),
    routesActive: Bool = false
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
        physicalAddress: "192.0.2.44",
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
              isActive: routesActive,
              observedGateway: routesActive ? "192.0.2.1" : nil,
              observedInterface: routesActive ? "en0" : nil
            ),
            RouteTargetStatus(
              address: "192.0.2.11",
              sources: ["service.example"],
              isActive: routesActive,
              observedGateway: routesActive ? "192.0.2.1" : nil,
              observedInterface: routesActive ? "en0" : nil
            ),
          ]
        )
      ],
      daemon: daemon,
      checkedAt: Date()
    )
  }
}
