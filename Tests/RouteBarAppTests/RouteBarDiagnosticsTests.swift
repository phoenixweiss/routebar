import Foundation
import RouteBarCore
import XCTest

@testable import RouteBarApp

final class RouteBarDiagnosticsTests: XCTestCase {
  func testRedactedReportContainsUsefulStateWithoutSensitiveNetworkData() {
    let snapshot = RouteStatusSnapshot(
      profile: Profile(
        id: "secret-office",
        name: "Secret Office",
        match: ProfileMatch(ssids: ["Private Wi-Fi"]),
        groups: ["private-services"]
      ),
      network: NetworkSnapshot(
        ssid: "Private Wi-Fi",
        physicalInterface: "en0",
        physicalGateway: "192.0.2.1",
        vpnInterfaces: ["utun4"]
      ),
      groups: [
        RouteGroupStatus(
          groupID: "private-services",
          name: "Private services",
          targets: [
            RouteTargetStatus(
              address: "192.0.2.10",
              sources: ["secret.example"],
              isActive: true,
              observedGateway: "192.0.2.1",
              observedInterface: "en0"
            )
          ]
        )
      ],
      daemon: DaemonRuntimeStatus(
        installed: true,
        loaded: true,
        runs: 42,
        lastExitCode: 0,
        intervalSeconds: 30
      ),
      checkedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let diagnostics = RouteBarDiagnostics(
      generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
      appVersion: "1.2.3",
      systemVersion: "macOS 26.0",
      architecture: "Apple silicon",
      state: .ready(
        snapshot,
        configURL: URL(fileURLWithPath: "/Users/private/.config/routebar/config.yaml")
      ),
      installedDaemon: .legacy(
        InstalledDaemonConfiguration(
          configURL: URL(fileURLWithPath: "/Users/private/.config/routebar/config.yaml"),
          profileID: "secret-office"
        )
      ),
      bundledDaemonStatus: .enabled,
      bundledDaemonConnectionStatus: .unavailable,
      reconciliationDiagnostics: BundledDaemonReconciliationDiagnostics(
        lastError: "secret.example at 192.0.2.10 failed",
        configurationRequiresReload: true
      )
    )

    let report = diagnostics.redactedReport
    XCTAssertTrue(report.contains("RouteBar: v1.2.3"))
    XCTAssertTrue(report.contains("Physical interface: en0"))
    XCTAssertTrue(report.contains("Physical gateway: Detected"))
    XCTAssertTrue(report.contains("VPN: Detected (1)"))
    XCTAssertTrue(report.contains("Host routes: 1 of 1 active"))
    XCTAssertTrue(report.contains("Service mode: Legacy"))
    XCTAssertTrue(report.contains("Built-in service: Not enabled"))
    XCTAssertTrue(report.contains("Helper version: Not running"))
    XCTAssertTrue(report.contains("Last reconciliation: Failed"))

    for sensitiveValue in [
      "secret.example",
      "192.0.2.1",
      "192.0.2.10",
      "Private Wi-Fi",
      "Secret Office",
      "secret-office",
      "private-services",
      "utun4",
      "/Users/private",
    ] {
      XCTAssertFalse(report.contains(sensitiveValue), "Leaked \(sensitiveValue)")
    }
  }

  func testUnavailableStateDoesNotInventNetworkDetails() {
    let diagnostics = RouteBarDiagnostics(
      appVersion: "1.2.3",
      systemVersion: "macOS 26.0",
      architecture: "Apple silicon",
      state: .loading,
      installedDaemon: .notInstalled,
      bundledDaemonStatus: .checking,
      bundledDaemonConnectionStatus: .notApplicable,
      reconciliationDiagnostics: .unknown
    )

    XCTAssertTrue(diagnostics.redactedReport.contains("Physical interface: Unavailable"))
    XCTAssertTrue(diagnostics.redactedReport.contains("Physical gateway: Unavailable"))
    XCTAssertTrue(diagnostics.redactedReport.contains("Host routes: Unavailable"))
  }
}
