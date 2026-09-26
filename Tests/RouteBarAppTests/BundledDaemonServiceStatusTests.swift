import Foundation
import RouteBarCore
import ServiceManagement
import XCTest

@testable import RouteBarApp

final class BundledDaemonServiceStatusTests: XCTestCase {
  func testMapsEveryKnownServiceStatus() {
    XCTAssertEqual(BundledDaemonServiceStatus(.notRegistered), .notRegistered)
    XCTAssertEqual(BundledDaemonServiceStatus(.enabled), .enabled)
    XCTAssertEqual(BundledDaemonServiceStatus(.requiresApproval), .requiresApproval)
    XCTAssertEqual(BundledDaemonServiceStatus(.notFound), .notFound)
  }

  func testInspectorUsesTheBundledDaemonPlistName() {
    XCTAssertEqual(
      SystemBundledDaemonServiceStatusInspector.plistName,
      "io.github.phoenixweiss.routebar.plist"
    )
  }

  func testPreflightUsesEnabledServiceAsBundledInstallationEvidence() {
    XCTAssertEqual(
      InstalledDaemonPreflight.resolve(
        plistInstallation: .notInstalled,
        bundledServiceStatus: .enabled
      ),
      .bundled
    )
  }

  func testPreflightUsesPendingApprovalAsBundledInstallationEvidence() {
    XCTAssertEqual(
      InstalledDaemonPreflight.resolve(
        plistInstallation: .notInstalled,
        bundledServiceStatus: .requiresApproval
      ),
      .bundled
    )
  }

  func testPreflightNeverMasksLegacyOrUnknownPlist() {
    let legacy = InstalledDaemonInstallation.legacy(
      InstalledDaemonConfiguration(
        configURL: URL(fileURLWithPath: "/tmp/config.yaml"),
        profileID: "work"
      )
    )

    XCTAssertEqual(
      InstalledDaemonPreflight.resolve(
        plistInstallation: legacy,
        bundledServiceStatus: .enabled
      ),
      legacy
    )
    XCTAssertEqual(
      InstalledDaemonPreflight.resolve(
        plistInstallation: .unknown,
        bundledServiceStatus: .enabled
      ),
      .unknown
    )
  }
}
