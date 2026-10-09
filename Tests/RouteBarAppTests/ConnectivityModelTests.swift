import Foundation
import RouteBarCore
import XCTest

@testable import RouteBarApp

final class ConnectivityModelTests: XCTestCase {
  @MainActor
  func testPreparationDoesNotRunChecksAndManualRunReportsEachResult() async throws {
    let runner = RecordingConnectivityRunner()
    let model = ConnectivityModel(runner: runner)
    let jobs = try sampleJobs()
    model.update(configURL: configURL, profileID: "home", network: network(), jobs: jobs)
    let before = await runner.count
    XCTAssertEqual(before, 0)
    XCTAssertNil(model.checkedAt)
    XCTAssertEqual(jobs.count, 5)
    await model.run()
    let after = await runner.count
    XCTAssertEqual(after, 5)
    XCTAssertEqual(model.results.count, 5)
    XCTAssertFalse(model.isChecking)
    XCTAssertNotNil(model.checkedAt)
    XCTAssertEqual(model.results[jobs.last!.id]?.summary, "Unexpected status · HTTP 503")
    XCTAssertEqual(model.results[jobs[1].id]?.summary, "Certificate error")
  }

  @MainActor
  func testRefreshKeepsResultsButNetworkOrTargetChangesMakeThemStale() async throws {
    let model = ConnectivityModel(runner: RecordingConnectivityRunner())
    let jobs = try sampleJobs()
    model.update(configURL: configURL, profileID: "home", network: network(), jobs: jobs)
    await model.run()
    model.update(configURL: configURL, profileID: "home", network: network(), jobs: jobs)
    XCTAssertFalse(model.isStale)
    model.update(
      configURL: configURL, profileID: "home", network: network(gateway: "192.0.2.2"), jobs: jobs)
    XCTAssertTrue(model.isStale)
    XCTAssertEqual(model.results.count, 5)
    let replacement = ConnectivityJob(
      id: jobs[0].id, groupName: "Mail",
      target: .endpoint(
        Endpoint(name: "New endpoint", host: "new.example.org", port: 443, protocol: .tls)))
    model.update(configURL: configURL, profileID: "home", network: network(), jobs: [replacement])
    XCTAssertTrue(model.results.isEmpty)
    await model.run()
    XCTAssertFalse(model.isStale)
    XCTAssertEqual(model.results.count, 1)
  }

  @MainActor
  func testLateResultAfterProfileChangeIsDiscardedAndDuplicateRunIsIgnored() async throws {
    let runner = PausedConnectivityRunner()
    let model = ConnectivityModel(runner: runner)
    let jobs = try sampleJobs()
    model.update(configURL: configURL, profileID: "home", network: network(), jobs: jobs)
    let run = Task { await model.run() }
    await runner.waitForStart()
    XCTAssertTrue(model.isChecking)
    XCTAssertEqual(model.currentJobID, jobs[0].id)
    await model.run()
    model.invalidate()
    model.update(configURL: configURL, profileID: "travel", network: network(), jobs: [jobs.last!])
    await runner.finish()
    await run.value
    XCTAssertTrue(model.results.isEmpty)
    XCTAssertTrue(model.isStale)
    XCTAssertNil(model.checkedAt)
    XCTAssertFalse(model.isChecking)
    let count = await runner.count
    XCTAssertEqual(count, 1)
  }

  @MainActor
  func testInvalidConfigurationDisablesChecksWithoutRequests() async {
    let runner = RecordingConnectivityRunner()
    let model = ConnectivityModel(runner: runner)
    await model.prepare(
      configURL: URL(fileURLWithPath: "/nonexistent/routebar-test.yaml"), profileID: "home",
      network: network())
    await model.run()
    XCTAssertTrue(model.configurationUnavailable)
    let count = await runner.count
    XCTAssertEqual(count, 0)
  }

  func testSelectionAndHTTPSDisplayDoNotExposeQueryOrPath() throws {
    let configuration = try ConfigurationLoader.load(source: sampleConfiguration)
    XCTAssertThrowsError(
      try ConnectivityJob.selected(configuration: configuration, profileID: "missing"))
    let jobs = try ConnectivityJob.selected(configuration: configuration, profileID: "home")
    XCTAssertEqual(jobs.last?.target.title, "status.example.org")
    XCTAssertEqual(jobs.last?.target.detail, "HTTPS · HEAD")
  }

  private let configURL = URL(fileURLWithPath: "/tmp/routebar-example.yaml")

  private func network(gateway: String = "192.0.2.1") -> NetworkSnapshot {
    NetworkSnapshot(
      ssid: "Example Wi-Fi", physicalInterface: "en0", physicalGateway: gateway,
      physicalAddress: "192.0.2.44", vpnInterfaces: ["utun4"])
  }

  private func sampleJobs() throws -> [ConnectivityJob] {
    try ConnectivityJob.selected(
      configuration: ConfigurationLoader.load(source: sampleConfiguration), profileID: "home")
  }
}

private actor RecordingConnectivityRunner: ConnectivityRunning {
  private(set) var count = 0
  func check(_ target: ConnectivityTarget) async -> ConnectivityResult {
    count += 1
    switch target {
    case .endpoint(let endpoint):
      return ConnectivityResult(
        outcome: endpoint.protocol == .tls ? "certificate-failure" : "reachable")
    case .https: return ConnectivityResult(outcome: "unexpected-http-status", statusCode: 503)
    }
  }
}

actor PausedConnectivityRunner: ConnectivityRunning {
  private(set) var count = 0
  private var completion: CheckedContinuation<ConnectivityResult, Never>?
  private var started: CheckedContinuation<Void, Never>?
  func check(_ target: ConnectivityTarget) async -> ConnectivityResult {
    count += 1
    return await withCheckedContinuation { continuation in
      completion = continuation
      started?.resume()
      started = nil
    }
  }
  func waitForStart() async {
    if count > 0 { return }
    await withCheckedContinuation { started = $0 }
  }
  func finish() {
    completion?.resume(returning: ConnectivityResult(outcome: "reachable"))
    completion = nil
  }
}

let sampleConfiguration = """
  version: 1
  profiles:
    - id: home
      name: Example profile
      match: { ssids: [Example Wi-Fi] }
      groups: [mail, web]
  groups:
    - id: mail
      name: Example mail services
      mode: check-only
      endpoints:
        - { name: TCP, host: mail.example.org, port: 25, protocol: tcp }
        - { name: Implicit TLS, host: mail.example.org, port: 993, protocol: tls }
        - { name: SMTP STARTTLS, host: mail.example.org, port: 587, protocol: starttls-smtp }
      checks:
        - { type: https, url: 'https://mail.example.org/health', expected_statuses: [200] }
    - id: web
      name: Example web services
      mode: bypass-vpn
      domains: [status.example.org]
      checks:
        - { type: https, url: 'https://status.example.org/health?sample=value', expected_statuses: [200] }
  """
