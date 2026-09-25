import XCTest

@testable import RouteBarCore

final class ReconciliationTests: XCTestCase {
  private let network = NetworkSnapshot(
    ssid: nil,
    physicalInterface: "en0",
    physicalGateway: "192.0.2.1"
  )

  func testAddsDesiredAddressWhenOnlyDefaultRouteExists() {
    let plan = ReconciliationPlanner.makePlan(
      desired: [.init(address: "203.0.113.10", sources: ["portal.example.org"])],
      network: network,
      state: RouteState(),
      observed: ["203.0.113.10": defaultRoute()]
    )

    XCTAssertEqual(
      plan.actions,
      [
        .init(
          kind: .add,
          address: "203.0.113.10",
          newGateway: "192.0.2.1",
          interface: "en0",
          sources: ["portal.example.org"]
        )
      ]
    )
    XCTAssertTrue(plan.conflicts.isEmpty)
  }

  func testReplacesOwnedRouteAfterPhysicalGatewayChanges() {
    let owned = OwnedRoute(
      address: "203.0.113.10",
      gateway: "198.51.100.1",
      interface: "en0",
      sources: ["portal.example.org"]
    )
    let plan = ReconciliationPlanner.makePlan(
      desired: [.init(address: owned.address, sources: owned.sources)],
      network: network,
      state: RouteState(routes: [owned]),
      observed: [owned.address: staticRoute(address: owned.address, gateway: owned.gateway)]
    )

    XCTAssertEqual(plan.actions.map(\.kind), [.replace])
    XCTAssertEqual(plan.actions.first?.oldGateway, "198.51.100.1")
    XCTAssertEqual(plan.actions.first?.newGateway, "192.0.2.1")
    XCTAssertTrue(plan.conflicts.isEmpty)
  }

  func testRemovesOwnedAddressNoLongerReturnedByDNS() {
    let owned = OwnedRoute(
      address: "203.0.113.10",
      gateway: "192.0.2.1",
      interface: "en0",
      sources: ["portal.example.org"]
    )
    let plan = ReconciliationPlanner.makePlan(
      desired: [],
      network: network,
      state: RouteState(routes: [owned]),
      observed: [owned.address: staticRoute(address: owned.address, gateway: owned.gateway)]
    )

    XCTAssertEqual(plan.actions.map(\.kind), [.remove])
    XCTAssertTrue(plan.conflicts.isEmpty)
  }

  func testRefusesUnownedStaticHostRoute() {
    let address = "203.0.113.10"
    let plan = ReconciliationPlanner.makePlan(
      desired: [.init(address: address, sources: ["portal.example.org"])],
      network: network,
      state: RouteState(),
      observed: [address: staticRoute(address: address, gateway: "198.51.100.1")]
    )

    XCTAssertTrue(plan.actions.isEmpty)
    XCTAssertEqual(plan.conflicts.count, 1)
  }

  func testAdoptsOnlyExactRoutesThroughCurrentPhysicalGateway() {
    let desired = [
      DesiredRoute(address: "203.0.113.10", sources: ["first.example.org"]),
      DesiredRoute(address: "203.0.113.20", sources: ["second.example.org"]),
    ]
    let adoption = ReconciliationPlanner.adoptableRoutes(
      desired: desired,
      network: network,
      observed: [
        "203.0.113.10": staticRoute(address: "203.0.113.10", gateway: "192.0.2.1"),
        "203.0.113.20": staticRoute(address: "203.0.113.20", gateway: "198.51.100.1"),
      ]
    )

    XCTAssertEqual(adoption.routes.map(\.address), ["203.0.113.10"])
    XCTAssertEqual(adoption.conflicts.map(\.address), ["203.0.113.20"])
  }

  private func defaultRoute() -> ObservedRoute {
    ObservedRoute(
      destination: "default",
      gateway: "192.0.2.1",
      interface: "en0",
      flags: ["UP", "GATEWAY", "STATIC"]
    )
  }

  private func staticRoute(address: String, gateway: String) -> ObservedRoute {
    ObservedRoute(
      destination: address,
      gateway: gateway,
      interface: "en0",
      flags: ["UP", "GATEWAY", "HOST", "STATIC"]
    )
  }
}
