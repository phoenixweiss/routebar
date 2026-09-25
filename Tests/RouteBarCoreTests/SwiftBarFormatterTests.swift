import Foundation
import XCTest

@testable import RouteBarCore

final class SwiftBarFormatterTests: XCTestCase {
  func testSuccessHasCompactHeaderAndGroupedDetails() throws {
    let configuration = try loadValidConfiguration()
    let profile = configuration.profiles[0]
    let mail = configuration.groups.first { $0.id == "mail" }!
    let plan = RoutePlan(
      profile: profile,
      network: .init(
        ssid: "Example Wi-Fi",
        physicalInterface: "en0",
        physicalGateway: "192.0.2.1",
        vpnInterfaces: ["utun4"]
      ),
      routeGroups: [
        .init(
          id: "work",
          name: "Work services",
          targets: [.init(address: "203.0.113.10", sources: ["portal.example.org"])]
        )
      ],
      checkOnlyGroups: [mail],
      profileWasForced: false
    )

    let output = SwiftBarFormatter.success(
      plan,
      configURL: URL(fileURLWithPath: "/tmp/config with spaces.yaml")
    )

    XCTAssertTrue(output.hasPrefix("RouteBar · 1 | sfimage=network\n---\n"))
    XCTAssertTrue(output.contains("Planned host routes | badge=1"))
    XCTAssertTrue(output.contains("--Work services | badge=1"))
    XCTAssertTrue(output.contains("----203.0.113.10/32"))
    XCTAssertTrue(output.contains("Connectivity checks"))
    XCTAssertTrue(output.contains("file:///tmp/config%20with%20spaces.yaml"))
  }

  func testFailureEscapesPluginMarkupFromMessage() {
    let output = SwiftBarFormatter.failure(
      "bad | field\nsecond line",
      configURL: URL(fileURLWithPath: "/tmp/config.yaml")
    )

    XCTAssertTrue(output.contains("bad ¦ field second line | length=100"))
  }

  private func loadValidConfiguration() throws -> RouteBarConfiguration {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("config.yaml")
    try validConfiguration.write(to: url, atomically: true, encoding: .utf8)
    return try ConfigurationLoader.load(from: url)
  }
}
