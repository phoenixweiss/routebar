import Foundation
import XCTest

@testable import RouteBarCore

final class RoutePlannerTests: XCTestCase {
  func testBuildsDeduplicatedReadOnlyHostRoutePlan() throws {
    let configuration = try loadValidConfiguration()
    let discovery = FakeDiscovery(
      value: .init(ssid: "Example Wi-Fi", physicalInterface: "en0", physicalGateway: "192.0.2.1")
    )
    let resolver = FakeResolver(values: [
      "portal.example.org": ["203.0.113.10", "203.0.113.20"]
    ])

    let plan = try RoutePlanner(discovery: discovery, resolver: resolver)
      .plan(configuration: configuration)

    XCTAssertEqual(plan.profile.id, "home")
    XCTAssertFalse(plan.profileWasForced)
    XCTAssertEqual(plan.routeGroups.count, 1)
    XCTAssertEqual(
      plan.routeGroups[0].targets,
      [
        .init(address: "203.0.113.10", sources: ["fixed address", "portal.example.org"]),
        .init(address: "203.0.113.20", sources: ["portal.example.org"]),
      ]
    )
    XCTAssertEqual(plan.checkOnlyGroups.map(\.id), ["mail"])
  }

  func testForcedProfileAllowsPlanWhenSSIDIsUnavailable() throws {
    let configuration = try loadValidConfiguration()
    let discovery = FakeDiscovery(
      value: .init(ssid: nil, physicalInterface: "en0", physicalGateway: "192.0.2.1")
    )
    let resolver = FakeResolver(values: ["portal.example.org": ["203.0.113.20"]])

    let plan = try RoutePlanner(discovery: discovery, resolver: resolver)
      .plan(configuration: configuration, forcedProfileID: "home")

    XCTAssertTrue(plan.profileWasForced)
  }

  func testNoMatchingProfileFailsClosed() throws {
    let configuration = try loadValidConfiguration()
    let discovery = FakeDiscovery(
      value: .init(ssid: "Other Wi-Fi", physicalInterface: "en0", physicalGateway: "192.0.2.1")
    )

    XCTAssertThrowsError(
      try RoutePlanner(discovery: discovery, resolver: FakeResolver(values: [:]))
        .plan(configuration: configuration)
    ) { error in
      XCTAssertEqual(
        (error as? RoutePlanningError)?.message, "no profile matches the current Wi-Fi network")
    }
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

private struct FakeDiscovery: NetworkDiscovering {
  let value: NetworkSnapshot

  func snapshot() throws -> NetworkSnapshot { value }
}

private struct FakeResolver: DNSResolving {
  let values: [String: [String]]

  func resolveIPv4(hostname: String) throws -> [String] {
    guard let value = values[hostname] else {
      throw DNSResolutionError(message: "missing test value for \(hostname)")
    }
    return value
  }
}
