import RouteBarDaemonIPC
import XCTest

@testable import RouteBarApp

final class BundledDaemonConnectionStatusTests: XCTestCase {
  func testConnectionStatusIsNotApplicableUntilTheServiceIsEnabled() {
    XCTAssertEqual(
      BundledDaemonConnectionStatus.resolve(
        serviceStatus: .notRegistered,
        appVersion: "1.2.3",
        report: BundledDaemonReadOnlyReport(
          helperVersion: "1.2.3",
          configuredProfileID: nil
        )
      ),
      .notApplicable
    )
  }

  func testEnabledServiceMustRespond() {
    XCTAssertEqual(
      BundledDaemonConnectionStatus.resolve(
        serviceStatus: .enabled,
        appVersion: "1.2.3",
        report: nil
      ),
      .unavailable
    )
  }

  func testMatchingVersionsAreConnected() {
    XCTAssertEqual(
      BundledDaemonConnectionStatus.resolve(
        serviceStatus: .enabled,
        appVersion: "1.2.3",
        report: BundledDaemonReadOnlyReport(
          helperVersion: "1.2.3",
          configuredProfileID: nil
        )
      ),
      .connected(helperVersion: "1.2.3")
    )
  }

  func testDifferentVersionsAreReportedAsAMismatch() {
    XCTAssertEqual(
      BundledDaemonConnectionStatus.resolve(
        serviceStatus: .enabled,
        appVersion: "1.2.3",
        report: BundledDaemonReadOnlyReport(
          helperVersion: "1.2.2",
          configuredProfileID: nil
        )
      ),
      .versionMismatch(appVersion: "1.2.3", helperVersion: "1.2.2")
    )
  }

  func testInspectorReadsBothVersionAndStatus() async throws {
    let attemptedAt = Date(timeIntervalSince1970: 1_700_000_010)
    let successfulAt = Date(timeIntervalSince1970: 1_700_000_000)
    let result = RouteBarDaemonOperationResult(
      changedRouteCount: 1,
      activeRouteCount: 2,
      conflictCount: 0
    )
    let transport = AppFakeDaemonTransport(
      responses: [
        .version(RouteBarDaemonVersion(helperVersion: "1.2.3")),
        .status(
          RouteBarDaemonStatus(
            helperVersion: "1.2.3",
            configuredProfileID: "work",
            automaticReconciliationEnabled: true,
            lastReconciliationAttemptAt: attemptedAt,
            lastSuccessfulReconciliationAt: successfulAt,
            lastReconciliationResult: result,
            configurationRequiresReload: true
          )
        ),
      ]
    )
    let inspector = SystemBundledDaemonReadOnlyInspector(transport: transport)

    let report = try await inspector.inspect()
    let requests = await transport.requests

    XCTAssertEqual(
      report,
      BundledDaemonReadOnlyReport(
        helperVersion: "1.2.3",
        configuredProfileID: "work",
        automaticReconciliationEnabled: true,
        reconciliationDiagnostics: BundledDaemonReconciliationDiagnostics(
          lastAttemptAt: attemptedAt,
          lastSuccessfulAt: successfulAt,
          lastResult: result,
          configurationRequiresReload: true
        )
      )
    )
    XCTAssertEqual(requests.count, 2)
    XCTAssertTrue(requests.contains(.version))
    XCTAssertTrue(requests.contains(.status))
  }

  func testInspectorRejectsInconsistentVersionInformation() async throws {
    let transport = AppFakeDaemonTransport(
      responses: [
        .version(RouteBarDaemonVersion(helperVersion: "1.2.3")),
        .status(
          RouteBarDaemonStatus(
            helperVersion: "1.2.2",
            configuredProfileID: nil
          )
        ),
      ]
    )
    let inspector = SystemBundledDaemonReadOnlyInspector(transport: transport)

    do {
      _ = try await inspector.inspect()
      XCTFail("Expected inconsistent versions to be rejected")
    } catch {
      XCTAssertEqual(
        error as? BundledDaemonReadOnlyInspectorError,
        .inconsistentVersion
      )
    }
  }
}

private actor AppFakeDaemonTransport: RouteBarDaemonTransport {
  private(set) var requests: [RouteBarDaemonRequest] = []
  private var responses: [RouteBarDaemonResponse]

  init(responses: [RouteBarDaemonResponse]) {
    self.responses = responses
  }

  func send(_ request: RouteBarDaemonRequest) async throws -> RouteBarDaemonResponse {
    requests.append(request)
    let index = responses.firstIndex { response in
      switch (request, response) {
      case (.version, .version), (.status, .status): true
      default: false
      }
    }
    return responses.remove(at: index ?? responses.startIndex)
  }
}
