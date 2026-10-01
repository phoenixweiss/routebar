import Foundation
import RouteBarCore
import ServiceManagement
import XCTest

@testable import RouteBarApp

final class LaunchAtLoginServiceTests: XCTestCase {
  func testMapsEveryKnownServiceStatus() {
    XCTAssertEqual(LaunchAtLoginStatus(.notRegistered), .disabled)
    XCTAssertEqual(LaunchAtLoginStatus(.enabled), .enabled)
    XCTAssertEqual(LaunchAtLoginStatus(.requiresApproval), .requiresApproval)
    XCTAssertEqual(LaunchAtLoginStatus(.notFound), .unavailable)
  }

  @MainActor
  func testEnablesAndDisablesLaunchAtLogin() async {
    let enabledModel = makeModel(
      status: .disabled,
      mutationResult: .success(.enabled)
    )
    await enabledModel.setLaunchAtLoginEnabled(true)
    XCTAssertEqual(enabledModel.launchAtLoginStatus, .enabled)
    XCTAssertEqual(enabledModel.launchAtLoginMutationState, .idle)

    let disabledModel = makeModel(
      status: .enabled,
      mutationResult: .success(.disabled)
    )
    await disabledModel.setLaunchAtLoginEnabled(false)
    XCTAssertEqual(disabledModel.launchAtLoginStatus, .disabled)
    XCTAssertEqual(disabledModel.launchAtLoginMutationState, .idle)
  }

  @MainActor
  func testKeepsApprovalStateVisible() async {
    let model = makeModel(
      status: .disabled,
      mutationResult: .success(.requiresApproval)
    )

    await model.setLaunchAtLoginEnabled(true)

    XCTAssertEqual(model.launchAtLoginStatus, .requiresApproval)
    XCTAssertEqual(model.launchAtLoginMutationState, .idle)
  }

  @MainActor
  func testReportsMutationFailure() async {
    let model = makeModel(
      status: .disabled,
      mutationResult: .failure(LaunchAtLoginTestFailure())
    )

    await model.setLaunchAtLoginEnabled(true)

    XCTAssertEqual(model.launchAtLoginStatus, .disabled)
    XCTAssertEqual(
      model.launchAtLoginMutationState,
      .failed("Launch at login test failure")
    )
  }

  @MainActor
  private func makeModel(
    status: LaunchAtLoginStatus,
    mutationResult: Result<LaunchAtLoginStatus, Error>
  ) -> RouteBarAppModel {
    RouteBarAppModel(
      previewState: .ready(
        RouteStatusSnapshot(
          profile: Profile(
            id: "sample",
            name: "Sample profile",
            match: ProfileMatch(ssids: ["Sample Wi-Fi"]),
            groups: []
          ),
          network: NetworkSnapshot(
            ssid: "Sample Wi-Fi",
            physicalInterface: "en0",
            physicalGateway: "192.0.2.1",
            physicalAddress: "192.0.2.44",
            vpnInterfaces: []
          ),
          groups: [],
          daemon: DaemonRuntimeStatus(installed: false, loaded: false),
          checkedAt: Date()
        ),
        configURL: URL(fileURLWithPath: "/tmp/config.yaml")
      ),
      bundledDaemonStatus: .notRegistered,
      launchAtLoginStatus: status,
      launchAtLoginMutationResult: mutationResult,
      showInDock: true
    )
  }
}

private struct LaunchAtLoginTestFailure: LocalizedError {
  var errorDescription: String? { "Launch at login test failure" }
}
