import Foundation
import XCTest

@testable import RouteBarCore

final class DaemonOperationsTests: XCTestCase {
  func testReconciliationStartsOnlyAfterExplicitClientRequest() async throws {
    let fixture = try OperationFixture()
    defer { fixture.remove() }
    let configurationService = fixture.configurationService()
    _ = try await configurationService.configure(clientUID: 501, profileID: "work")
    let runner = FakeReconciliationRunner()
    let service = RouteBarDaemonOperationService(
      configurationService: configurationService,
      reconciliationRunner: runner
    )

    let skipped = try await service.reconcileAutomatically()
    XCTAssertNil(skipped)
    XCTAssertEqual(runner.applyCount, 0)

    let first = try await service.reconcile(clientUID: 501)
    XCTAssertEqual(
      first,
      RouteBarDaemonOperationSummary(
        changedRouteCount: 1,
        activeRouteCount: 1,
        conflictCount: 0
      )
    )
    XCTAssertEqual(runner.applyCount, 1)
    let enabledSettings = try await configurationService.settings()
    XCTAssertEqual(enabledSettings?.automaticReconciliationEnabled, true)

    _ = try await service.reconcileAutomatically()
    XCTAssertEqual(runner.applyCount, 2)
  }

  func testCleanupDisablesFutureAutomaticReconciliation() async throws {
    let fixture = try OperationFixture()
    defer { fixture.remove() }
    let configurationService = fixture.configurationService()
    _ = try await configurationService.configure(clientUID: 501, profileID: "work")
    let runner = FakeReconciliationRunner()
    let service = RouteBarDaemonOperationService(
      configurationService: configurationService,
      reconciliationRunner: runner
    )
    _ = try await service.reconcile(clientUID: 501)

    let cleanup = try await service.cleanup(clientUID: 501)

    XCTAssertEqual(cleanup.activeRouteCount, 0)
    XCTAssertEqual(runner.cleanupCount, 1)
    let disabledSettings = try await configurationService.settings()
    XCTAssertEqual(disabledSettings?.automaticReconciliationEnabled, false)
    let skipped = try await service.reconcileAutomatically()
    XCTAssertNil(skipped)
  }

  func testDiagnosticsTrackSuccessfulReconciliationAndConfigurationChanges() async throws {
    let fixture = try OperationFixture()
    defer { fixture.remove() }
    let configurationService = fixture.configurationService()
    _ = try await configurationService.configure(clientUID: 501, profileID: "work")
    let service = RouteBarDaemonOperationService(
      configurationService: configurationService,
      reconciliationRunner: FakeReconciliationRunner()
    )

    let initial = await service.diagnostics()
    XCTAssertNil(initial.lastAttemptAt)
    XCTAssertNil(initial.configurationRequiresReload)

    let result = try await service.reconcile(clientUID: 501)
    let reconciled = await service.diagnostics()
    XCTAssertNotNil(reconciled.lastAttemptAt)
    XCTAssertNotNil(reconciled.lastSuccessfulAt)
    XCTAssertEqual(reconciled.lastResult, result)
    XCTAssertNil(reconciled.lastError)
    XCTAssertEqual(reconciled.configurationRequiresReload, false)

    try fixture.touchConfiguration()
    let changed = await service.diagnostics()
    XCTAssertEqual(changed.configurationRequiresReload, true)

    _ = try await service.reconcileAutomatically()
    let reapplied = await service.diagnostics()
    XCTAssertEqual(reapplied.configurationRequiresReload, false)
  }

  func testDiagnosticsKeepTheLastSuccessWhenAChangedConfigurationFails() async throws {
    let fixture = try OperationFixture()
    defer { fixture.remove() }
    let configurationService = fixture.configurationService()
    _ = try await configurationService.configure(clientUID: 501, profileID: "work")
    let service = RouteBarDaemonOperationService(
      configurationService: configurationService,
      reconciliationRunner: FakeReconciliationRunner()
    )
    _ = try await service.reconcile(clientUID: 501)
    let successfulAt = await service.diagnostics().lastSuccessfulAt

    try fixture.breakConfiguration()
    await assertThrowsErrorAsync {
      _ = try await service.reconcileAutomatically()
    }

    let failed = await service.diagnostics()
    XCTAssertEqual(failed.lastSuccessfulAt, successfulAt)
    XCTAssertNil(failed.lastResult)
    XCTAssertNotNil(failed.lastError)
    XCTAssertEqual(failed.configurationRequiresReload, true)
  }

  func testConflictDoesNotEnableAutomaticReconciliation() async throws {
    let fixture = try OperationFixture()
    defer { fixture.remove() }
    let configurationService = fixture.configurationService()
    _ = try await configurationService.configure(clientUID: 501, profileID: "work")
    let service = RouteBarDaemonOperationService(
      configurationService: configurationService,
      reconciliationRunner: ConflictingReconciliationRunner()
    )

    let result = try await service.reconcile(clientUID: 501)

    XCTAssertEqual(result.conflictCount, 1)
    let settings = try await configurationService.settings()
    XCTAssertEqual(settings?.automaticReconciliationEnabled, false)
    let automaticResult = try await service.reconcileAutomatically()
    XCTAssertNil(automaticResult)

    let diagnostics = await service.diagnostics()
    XCTAssertNotNil(diagnostics.lastAttemptAt)
    XCTAssertNil(diagnostics.lastSuccessfulAt)
    XCTAssertEqual(diagnostics.lastResult?.conflictCount, 1)
    XCTAssertNotNil(diagnostics.lastError)
  }

  func testAnotherUserCannotReconcileOrCleanup() async throws {
    let fixture = try OperationFixture()
    defer { fixture.remove() }
    let configurationService = fixture.configurationService()
    _ = try await configurationService.configure(clientUID: 501, profileID: "work")
    let runner = FakeReconciliationRunner()
    let service = RouteBarDaemonOperationService(
      configurationService: configurationService,
      reconciliationRunner: runner
    )

    await assertThrowsErrorAsync {
      _ = try await service.reconcile(clientUID: 502)
    }
    await assertThrowsErrorAsync {
      _ = try await service.cleanup(clientUID: 502)
    }
    XCTAssertEqual(runner.applyCount, 0)
    XCTAssertEqual(runner.cleanupCount, 0)
  }

  func testCleanupFailsClosedWhileReconciliationIsPreparing() async throws {
    let fixture = try OperationFixture()
    defer { fixture.remove() }
    let planner = BlockingRoutePlanner()
    let configurationService = fixture.configurationService(routePlanner: planner)
    _ = try await configurationService.configure(clientUID: 501, profileID: "work")
    let service = RouteBarDaemonOperationService(
      configurationService: configurationService,
      reconciliationRunner: FakeReconciliationRunner()
    )

    let reconciliation = Task {
      try await service.reconcile(clientUID: 501)
    }
    XCTAssertEqual(planner.entered.wait(timeout: .now() + 1), .success)

    do {
      _ = try await service.cleanup(clientUID: 501)
      XCTFail("Expected cleanup to fail while reconciliation is in progress")
    } catch {
      XCTAssertEqual(
        error as? RouteBarDaemonOperationError,
        RouteBarDaemonOperationError(
          message: "another route operation is already in progress"
        )
      )
    }

    planner.release.signal()
    _ = try await reconciliation.value
  }

  func testConfigurationFailsClosedWhileReconciliationIsPreparing() async throws {
    let fixture = try OperationFixture()
    defer { fixture.remove() }
    let planner = BlockingRoutePlanner()
    let configurationService = fixture.configurationService(routePlanner: planner)
    _ = try await configurationService.configure(clientUID: 501, profileID: "work")
    let service = RouteBarDaemonOperationService(
      configurationService: configurationService,
      reconciliationRunner: FakeReconciliationRunner()
    )

    let reconciliation = Task {
      try await service.reconcile(clientUID: 501)
    }
    XCTAssertEqual(planner.entered.wait(timeout: .now() + 1), .success)

    do {
      _ = try await service.configure(clientUID: 501, profileID: "travel")
      XCTFail("Expected configuration to fail while reconciliation is in progress")
    } catch {
      XCTAssertEqual(
        error as? RouteBarDaemonOperationError,
        RouteBarDaemonOperationError(
          message: "another route operation is already in progress"
        )
      )
    }

    planner.release.signal()
    _ = try await reconciliation.value
    let settings = try await configurationService.settings()
    XCTAssertEqual(settings?.profileID, "work")
  }
}

private struct OperationFixture {
  let rootURL: URL
  let homeURL: URL
  let configURL: URL
  let store: FileRouteBarDaemonSettingsStore

  init() throws {
    rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("routebar-daemon-operations-\(UUID().uuidString)", isDirectory: true)
    homeURL = rootURL.appendingPathComponent("home", isDirectory: true)
    store = FileRouteBarDaemonSettingsStore(
      url: rootURL.appendingPathComponent("state/settings.json")
    )
    configURL = homeURL.appendingPathComponent(
      ".config/routebar/config.yaml",
      isDirectory: false
    )
    try FileManager.default.createDirectory(
      at: configURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Self.configuration.write(to: configURL, atomically: true, encoding: .utf8)
  }

  func configurationService(
    routePlanner: any RoutePlanning = FixedRoutePlanner()
  ) -> RouteBarDaemonConfigurationService {
    RouteBarDaemonConfigurationService(
      settingsStore: store,
      homeResolver: OperationHomeResolver(homeURL: homeURL),
      routePlanner: routePlanner
    )
  }

  func remove() {
    try? FileManager.default.removeItem(at: rootURL)
  }

  func touchConfiguration() throws {
    let source = try String(contentsOf: configURL, encoding: .utf8)
    try (source + "\n# Edited outside RouteBar\n").write(
      to: configURL,
      atomically: true,
      encoding: .utf8
    )
  }

  func breakConfiguration() throws {
    try "version: [not valid".write(to: configURL, atomically: true, encoding: .utf8)
  }

  private static let configuration = """
    version: 1
    profiles:
      - id: work
        name: Work
        match:
          ssids: [Office]
        groups: [services]
      - id: travel
        name: Travel
        match:
          ssids: [Hotel]
        groups: [services]
    groups:
      - id: services
        name: Services
        mode: bypass-vpn
        addresses: [192.0.2.10]
    """
}

private struct OperationHomeResolver: UserHomeDirectoryResolving {
  let homeURL: URL

  func homeDirectory(for uid: UInt32) throws -> URL { homeURL }
}

private struct FixedRoutePlanner: RoutePlanning {
  func plan(
    configuration: RouteBarConfiguration,
    forcedProfileID: String?
  ) throws -> RoutePlan {
    RoutePlan(
      profile: configuration.profiles[0],
      network: NetworkSnapshot(
        ssid: "Office",
        physicalInterface: "en0",
        physicalGateway: "192.0.2.1",
        physicalAddress: "192.0.2.44",
        vpnInterfaces: ["utun4"]
      ),
      routeGroups: [
        RouteGroupPlan(
          id: "services",
          name: "Services",
          targets: [
            RouteTarget(address: "192.0.2.10", sources: ["fixed address"])
          ]
        )
      ],
      checkOnlyGroups: [],
      profileWasForced: true
    )
  }
}

private final class BlockingRoutePlanner: RoutePlanning, @unchecked Sendable {
  let entered = DispatchSemaphore(value: 0)
  let release = DispatchSemaphore(value: 0)

  func plan(
    configuration: RouteBarConfiguration,
    forcedProfileID: String?
  ) throws -> RoutePlan {
    entered.signal()
    release.wait()
    return try FixedRoutePlanner().plan(
      configuration: configuration,
      forcedProfileID: forcedProfileID
    )
  }
}

private struct ConflictingReconciliationRunner: RouteBarRouteReconciliationRunning {
  func apply(routePlan: RoutePlan) throws -> ReconciliationResult {
    ReconciliationResult(
      plan: ReconciliationPlan(
        actions: [],
        conflicts: [
          RouteConflict(
            address: "192.0.2.10",
            reason: "an unowned host route already exists"
          )
        ],
        unchangedCount: 0
      ),
      state: RouteState()
    )
  }

  func cleanup() throws -> ReconciliationResult {
    ReconciliationResult(
      plan: ReconciliationPlan(actions: [], conflicts: [], unchangedCount: 0),
      state: RouteState()
    )
  }
}

private final class FakeReconciliationRunner: RouteBarRouteReconciliationRunning,
  @unchecked Sendable
{
  private let lock = NSLock()
  private var applyCalls = 0
  private var cleanupCalls = 0

  var applyCount: Int { lock.withLock { applyCalls } }
  var cleanupCount: Int { lock.withLock { cleanupCalls } }

  func apply(routePlan: RoutePlan) throws -> ReconciliationResult {
    lock.withLock { applyCalls += 1 }
    return ReconciliationResult(
      plan: ReconciliationPlan(
        actions: [
          RouteAction(
            kind: .add,
            address: "192.0.2.10",
            newGateway: "192.0.2.1",
            interface: "en0"
          )
        ],
        conflicts: [],
        unchangedCount: 0
      ),
      state: RouteState(
        routes: [
          OwnedRoute(
            address: "192.0.2.10",
            gateway: "192.0.2.1",
            interface: "en0",
            sources: ["fixed address"]
          )
        ]
      )
    )
  }

  func cleanup() throws -> ReconciliationResult {
    lock.withLock { cleanupCalls += 1 }
    return ReconciliationResult(
      plan: ReconciliationPlan(
        actions: [
          RouteAction(
            kind: .remove,
            address: "192.0.2.10",
            oldGateway: "192.0.2.1",
            interface: "en0"
          )
        ],
        conflicts: [],
        unchangedCount: 0
      ),
      state: RouteState()
    )
  }
}

private func assertThrowsErrorAsync(
  _ expression: () async throws -> Void,
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    try await expression()
    XCTFail("Expected an error", file: file, line: line)
  } catch {}
}
