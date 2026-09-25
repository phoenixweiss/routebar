import XCTest

@testable import RouteBarCore

final class RouteStatusTests: XCTestCase {
  func testReportsOnlyRoutesThroughCurrentPhysicalGatewayAsActive() throws {
    let plan = RoutePlan(
      profile: Profile(
        id: "home",
        name: "Home",
        match: ProfileMatch(ssids: ["Example Wi-Fi"]),
        groups: ["services"]
      ),
      network: NetworkSnapshot(
        ssid: "Example Wi-Fi",
        physicalInterface: "en0",
        physicalGateway: "192.0.2.1",
        vpnInterfaces: ["utun4"]
      ),
      routeGroups: [
        RouteGroupPlan(
          id: "services",
          name: "Services",
          targets: [
            RouteTarget(address: "203.0.113.10", sources: ["first.example.org"]),
            RouteTarget(address: "203.0.113.20", sources: ["second.example.org"]),
          ]
        )
      ],
      checkOnlyGroups: [],
      profileWasForced: true
    )
    let inspector = StatusRouteInspector(routes: [
      "203.0.113.10": observed(address: "203.0.113.10", gateway: "192.0.2.1"),
      "203.0.113.20": observed(address: "203.0.113.20", gateway: "198.51.100.1"),
    ])
    let daemon = StatusDaemonInspector(
      value: DaemonRuntimeStatus(installed: true, loaded: true, runs: 3, lastExitCode: 0)
    )

    let snapshot = try RouteStatusService(
      routeInspector: inspector,
      daemonInspector: daemon
    ).snapshot(routePlan: plan)

    XCTAssertEqual(snapshot.routeCount, 2)
    XCTAssertEqual(snapshot.activeCount, 1)
    XCTAssertFalse(snapshot.allRoutesActive)
    XCTAssertEqual(snapshot.groups.first?.targets.map(\.isActive), [true, false])
  }

  private func observed(address: String, gateway: String) -> ObservedRoute {
    ObservedRoute(
      destination: address,
      gateway: gateway,
      interface: "en0",
      flags: ["UP", "GATEWAY", "HOST", "STATIC"]
    )
  }
}

private struct StatusRouteInspector: RouteInspecting {
  let routes: [String: ObservedRoute]

  func route(to address: String) throws -> ObservedRoute {
    guard let route = routes[address] else {
      throw RouteInspectionError(message: "missing route")
    }
    return route
  }
}

private struct StatusDaemonInspector: DaemonRuntimeInspecting {
  let value: DaemonRuntimeStatus

  func status() -> DaemonRuntimeStatus { value }
}
