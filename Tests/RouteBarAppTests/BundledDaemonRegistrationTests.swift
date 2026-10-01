import Foundation
import RouteBarCore
import RouteBarDaemonIPC
import XCTest

@testable import RouteBarApp

final class BundledDaemonRegistrationTests: XCTestCase {
  @MainActor
  func testRegistrationCanPauseForSystemApproval() async {
    let model = makeModel(
      installedDaemon: .notInstalled,
      registrationResult: .success(.requiresApproval)
    )

    await model.enableBundledDaemon()

    XCTAssertEqual(model.bundledDaemonRegistrationState, .awaitingApproval)
    XCTAssertEqual(model.bundledDaemonStatus, .requiresApproval)
    XCTAssertEqual(model.installedDaemon, .bundled)
  }

  @MainActor
  func testRegistrationReportsAnUnusableResultWithoutChangingInstallationState() async {
    let model = makeModel(
      installedDaemon: .notInstalled,
      registrationResult: .success(.notRegistered)
    )

    await model.enableBundledDaemon()

    guard case .failed(let message) = model.bundledDaemonRegistrationState else {
      return XCTFail("Expected registration failure")
    }
    XCTAssertTrue(message.contains("No routes were changed"))
    XCTAssertEqual(model.bundledDaemonStatus, .notRegistered)
    XCTAssertEqual(model.installedDaemon, .notInstalled)
  }

  @MainActor
  func testRegistrationIsBlockedWhileLegacyDaemonExists() async {
    let legacyConfiguration = InstalledDaemonConfiguration(
      configURL: URL(fileURLWithPath: "/tmp/config.yaml"),
      profileID: "sample"
    )
    let model = makeModel(
      installedDaemon: .legacy(legacyConfiguration),
      registrationResult: .success(.requiresApproval)
    )

    await model.enableBundledDaemon()

    XCTAssertEqual(model.bundledDaemonRegistrationState, .idle)
    XCTAssertEqual(model.bundledDaemonStatus, .notRegistered)
    XCTAssertEqual(model.installedDaemon, .legacy(legacyConfiguration))
  }

  @MainActor
  func testConfigurationSavesTheSelectedProfileWithoutApplyingRoutes() async {
    let model = makeConfiguredServiceModel(
      configurationResult: .success("sample")
    )

    await model.configureBundledDaemon()

    XCTAssertEqual(model.configuredProfileID, "sample")
    XCTAssertEqual(model.bundledDaemonConfigurationState, .configured)
  }

  @MainActor
  func testConfigurationFailureLeavesTheProfileUnconfigured() async {
    let model = makeConfiguredServiceModel(
      configurationResult: .failure(TestFailure())
    )

    await model.configureBundledDaemon()

    XCTAssertNil(model.configuredProfileID)
    XCTAssertEqual(model.bundledDaemonConfigurationState, .failed("Test failure"))
  }

  @MainActor
  func testFirstReconciliationRequiresConfiguredProfileAndEnablesAutomation() async {
    let result = RouteBarDaemonOperationResult(
      changedRouteCount: 2,
      activeRouteCount: 2,
      conflictCount: 0
    )
    let model = makeConfiguredServiceModel(
      configurationResult: .success("sample"),
      configuredProfileID: "sample",
      reconciliationResult: .success(result)
    )

    await model.applyConfiguredRoutes()

    XCTAssertTrue(model.automaticReconciliationEnabled)
    XCTAssertEqual(model.bundledDaemonReconciliationState, .active(result))
  }

  @MainActor
  func testFailedReconciliationDoesNotEnableAutomation() async {
    let model = makeConfiguredServiceModel(
      configurationResult: .success("sample"),
      configuredProfileID: "sample",
      reconciliationResult: .failure(TestFailure())
    )

    await model.applyConfiguredRoutes()

    XCTAssertFalse(model.automaticReconciliationEnabled)
    XCTAssertEqual(model.bundledDaemonReconciliationState, .failed("Test failure"))
  }

  @MainActor
  func testReloadConfigurationReconcilesImmediatelyAndReportsAppliedRoutes() async {
    let result = RouteBarDaemonOperationResult(
      changedRouteCount: 1,
      activeRouteCount: 3,
      conflictCount: 0
    )
    let model = makeConfiguredServiceModel(
      configurationResult: .success("sample"),
      configuredProfileID: "sample",
      automaticReconciliationEnabled: true,
      reconciliationResult: .success(result)
    )

    await model.reloadConfiguration()

    guard case .applied(let observedResult, _) = model.configurationReloadState else {
      return XCTFail("Expected the configuration to be applied")
    }
    XCTAssertEqual(observedResult, result)
    XCTAssertTrue(model.automaticReconciliationEnabled)
  }

  @MainActor
  func testReloadConfigurationReportsRejectedConfigurationWithoutDisablingAutomation() async {
    let model = makeConfiguredServiceModel(
      configurationResult: .success("sample"),
      configuredProfileID: "sample",
      automaticReconciliationEnabled: true,
      reconciliationResult: .failure(TestFailure())
    )

    await model.reloadConfiguration()

    guard case .rejected(let message, _) = model.configurationReloadState else {
      return XCTFail("Expected the configuration to be rejected")
    }
    XCTAssertEqual(message, "Test failure")
    XCTAssertTrue(model.automaticReconciliationEnabled)
  }

  @MainActor
  func testReloadConfigurationIsUnavailableBeforeAutomaticRoutingStarts() async {
    let model = makeConfiguredServiceModel(
      configurationResult: .success("sample"),
      configuredProfileID: "sample",
      automaticReconciliationEnabled: false
    )

    await model.reloadConfiguration()

    XCTAssertEqual(model.configurationReloadState, .idle)
  }

  @MainActor
  func testDisablingCleansRoutesBeforeUnregisteringTheService() async {
    let cleanup = RouteBarDaemonOperationResult(
      changedRouteCount: 2,
      activeRouteCount: 0,
      conflictCount: 0
    )
    let model = makeConfiguredServiceModel(
      configurationResult: .success("sample"),
      configuredProfileID: "sample",
      automaticReconciliationEnabled: true,
      cleanupResult: .success(cleanup),
      unregistrationResult: .success(.notRegistered)
    )

    await model.disableBundledDaemon()

    XCTAssertEqual(model.bundledDaemonStatus, .notRegistered)
    XCTAssertEqual(model.installedDaemon, .notInstalled)
    XCTAssertFalse(model.automaticReconciliationEnabled)
    XCTAssertNil(model.configuredProfileID)
    XCTAssertEqual(model.bundledDaemonRemovalState, .idle)
  }

  @MainActor
  func testCleanupFailureLeavesTheServiceEnabled() async {
    let model = makeConfiguredServiceModel(
      configurationResult: .success("sample"),
      configuredProfileID: "sample",
      automaticReconciliationEnabled: true,
      cleanupResult: .failure(TestFailure()),
      unregistrationResult: .success(.notRegistered)
    )

    await model.disableBundledDaemon()

    XCTAssertEqual(model.bundledDaemonStatus, .enabled)
    XCTAssertEqual(model.installedDaemon, .bundled)
    XCTAssertTrue(model.automaticReconciliationEnabled)
    guard case .failed(let message) = model.bundledDaemonRemovalState else {
      return XCTFail("Expected removal failure")
    }
    XCTAssertTrue(message.contains("service remains enabled"))
  }

  @MainActor
  func testUnregistrationFailureReportsRoutesAsRemoved() async {
    let cleanup = RouteBarDaemonOperationResult(
      changedRouteCount: 2,
      activeRouteCount: 0,
      conflictCount: 0
    )
    let model = makeConfiguredServiceModel(
      configurationResult: .success("sample"),
      configuredProfileID: "sample",
      automaticReconciliationEnabled: true,
      cleanupResult: .success(cleanup),
      unregistrationResult: .failure(TestFailure())
    )

    await model.disableBundledDaemon()

    XCTAssertEqual(model.bundledDaemonStatus, .enabled)
    guard case .failed(let message) = model.bundledDaemonRemovalState else {
      return XCTFail("Expected removal failure")
    }
    XCTAssertTrue(message.contains("routes were removed"))
  }

  @MainActor
  func testVersionMismatchUpdatePreservesConfigurationAndRestartsMatchingService() async {
    let report = BundledDaemonReadOnlyReport(
      helperVersion: "1.2.4",
      configuredProfileID: "sample",
      automaticReconciliationEnabled: true
    )
    let model = makeConfiguredServiceModel(
      configurationResult: .success("sample"),
      configuredProfileID: "sample",
      automaticReconciliationEnabled: true,
      connectionStatus: .versionMismatch(appVersion: "1.2.4", helperVersion: "1.2.3"),
      registrationResult: .success(.enabled),
      unregistrationResult: .success(.notRegistered),
      readOnlyResult: .success(report),
      appVersion: "1.2.4"
    )

    await model.updateBundledDaemon()

    XCTAssertEqual(model.bundledDaemonUpdateState, .completed)
    XCTAssertEqual(model.bundledDaemonStatus, .enabled)
    XCTAssertEqual(model.bundledDaemonConnectionStatus, .connected(helperVersion: "1.2.4"))
    XCTAssertEqual(model.configuredProfileID, "sample")
    XCTAssertTrue(model.automaticReconciliationEnabled)
  }

  @MainActor
  func testVersionMismatchUpdateCanPauseForApprovalAfterStoppingOldService() async {
    let model = makeConfiguredServiceModel(
      configurationResult: .success("sample"),
      configuredProfileID: "sample",
      automaticReconciliationEnabled: true,
      connectionStatus: .versionMismatch(appVersion: "1.2.4", helperVersion: "1.2.3"),
      registrationResult: .success(.requiresApproval),
      unregistrationResult: .success(.notRegistered),
      appVersion: "1.2.4"
    )

    await model.updateBundledDaemon()

    XCTAssertEqual(model.bundledDaemonUpdateState, .awaitingApproval)
    XCTAssertEqual(model.bundledDaemonStatus, .requiresApproval)
    XCTAssertEqual(model.installedDaemon, .bundled)
    XCTAssertEqual(model.configuredProfileID, "sample")
    XCTAssertTrue(model.automaticReconciliationEnabled)
  }

  @MainActor
  func testVersionMismatchUpdateStopsWhenOldServiceCannotBeUnregistered() async {
    let model = makeConfiguredServiceModel(
      configurationResult: .success("sample"),
      configuredProfileID: "sample",
      automaticReconciliationEnabled: true,
      connectionStatus: .versionMismatch(appVersion: "1.2.4", helperVersion: "1.2.3"),
      registrationResult: .success(.enabled),
      unregistrationResult: .failure(TestFailure()),
      appVersion: "1.2.4"
    )

    await model.updateBundledDaemon()

    XCTAssertEqual(
      model.bundledDaemonConnectionStatus,
      .versionMismatch(appVersion: "1.2.4", helperVersion: "1.2.3")
    )
    guard case .failed(let message) = model.bundledDaemonUpdateState else {
      return XCTFail("Expected update failure")
    }
    XCTAssertTrue(message.contains("could not be stopped"))
  }

  @MainActor
  private func makeModel(
    installedDaemon: InstalledDaemonInstallation,
    registrationResult: Result<BundledDaemonServiceStatus, Error>
  ) -> RouteBarAppModel {
    RouteBarAppModel(
      previewState: .ready(
        sampleSnapshot(),
        configURL: URL(fileURLWithPath: "/tmp/config.yaml")
      ),
      installedDaemon: installedDaemon,
      bundledDaemonStatus: .notRegistered,
      profileOptions: [
        RouteBarProfileOption(
          profile: Profile(
            id: "sample",
            name: "Sample profile",
            match: ProfileMatch(ssids: ["Sample Wi-Fi"]),
            groups: ["services"]
          )
        )
      ],
      selectedProfileID: "sample",
      bundledDaemonRegistrationResult: registrationResult,
      showInDock: true
    )
  }

  @MainActor
  private func makeConfiguredServiceModel(
    configurationResult: Result<String, Error>,
    configuredProfileID: String? = nil,
    automaticReconciliationEnabled: Bool = false,
    reconciliationResult: Result<RouteBarDaemonOperationResult, Error>? = nil,
    cleanupResult: Result<RouteBarDaemonOperationResult, Error>? = nil,
    connectionStatus: BundledDaemonConnectionStatus = .connected(helperVersion: "1.2.3"),
    registrationResult: Result<BundledDaemonServiceStatus, Error>? = nil,
    unregistrationResult: Result<BundledDaemonServiceStatus, Error>? = nil,
    readOnlyResult: Result<BundledDaemonReadOnlyReport, Error>? = nil,
    appVersion: String = "unknown"
  ) -> RouteBarAppModel {
    RouteBarAppModel(
      previewState: .ready(
        sampleSnapshot(),
        configURL: URL(fileURLWithPath: "/tmp/config.yaml")
      ),
      installedDaemon: .bundled,
      bundledDaemonStatus: .enabled,
      bundledDaemonConnectionStatus: connectionStatus,
      profileOptions: [
        RouteBarProfileOption(
          profile: Profile(
            id: "sample",
            name: "Sample profile",
            match: ProfileMatch(ssids: ["Sample Wi-Fi"]),
            groups: ["services"]
          )
        )
      ],
      selectedProfileID: "sample",
      bundledDaemonRegistrationResult: registrationResult,
      bundledDaemonUnregistrationResult: unregistrationResult,
      configuredProfileID: configuredProfileID,
      bundledDaemonConfigurationResult: configurationResult,
      automaticReconciliationEnabled: automaticReconciliationEnabled,
      bundledDaemonReconciliationResult: reconciliationResult,
      bundledDaemonCleanupResult: cleanupResult,
      bundledDaemonReadOnlyResult: readOnlyResult,
      appVersion: appVersion,
      showInDock: true
    )
  }

  private func sampleSnapshot() -> RouteStatusSnapshot {
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
      groups: [],
      daemon: DaemonRuntimeStatus(installed: false, loaded: false),
      checkedAt: Date()
    )
  }
}

private struct TestFailure: LocalizedError {
  var errorDescription: String? { "Test failure" }
}
