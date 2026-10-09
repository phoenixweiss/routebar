import XCTest

@testable import RouteBarCore

final class ReconciliationServiceTests: XCTestCase {
  func testDNSFailureRemovesOnlyObsoleteOwnedRouteWhileAddingHealthyRoute() throws {
    let stale = "203.0.113.99"
    let healthy = "203.0.113.10"
    let foreign = "203.0.113.88"
    let routeSystem = FakeRouteSystem(routes: [
      stale: observed(address: stale, gateway: "198.51.100.1"),
      foreign: observed(address: foreign, gateway: "198.51.100.1"),
    ])
    let store = MemoryRouteStateStore(
      state: RouteState(routes: [
        OwnedRoute(
          address: stale, gateway: "198.51.100.1", interface: "en0", sources: ["failed.example.org"]
        )
      ]))
    let base = routePlan(address: healthy)
    let partial = RoutePlan(
      profile: base.profile, network: base.network,
      routeGroups: [
        RouteGroupPlan(
          id: "web", name: "Web", targets: base.routeGroups[0].targets,
          unresolvedDomains: ["failed.example.org"])
      ], checkOnlyGroups: [], profileWasForced: true)
    let service = RouteReconciliationService(
      inspector: routeSystem, mutator: routeSystem, stateStore: store)
    let result = try service.apply(routePlan: partial)
    XCTAssertEqual(Set(result.state.routes.map(\.address)), [healthy])
    XCTAssertNotNil(routeSystem.routes[foreign])
    XCTAssertFalse(routeSystem.mutations.contains { $0.contains(foreign) })
    XCTAssertTrue(routeSystem.mutations.contains("delete \(stale) via 198.51.100.1"))
    XCTAssertTrue(routeSystem.mutations.contains("add \(healthy) via 192.0.2.1"))
  }
  func testApplyReplacesRouteAndPersistsNewOwnership() throws {
    let address = "203.0.113.10"
    let oldRoute = OwnedRoute(
      address: address,
      gateway: "198.51.100.1",
      interface: "en0",
      sources: ["portal.example.org"]
    )
    let routeSystem = FakeRouteSystem(routes: [
      address: observed(address: address, gateway: oldRoute.gateway)
    ])
    let stateStore = MemoryRouteStateStore(state: RouteState(routes: [oldRoute]))
    let service = RouteReconciliationService(
      inspector: routeSystem,
      mutator: routeSystem,
      stateStore: stateStore
    )

    let result = try service.apply(routePlan: routePlan(address: address))

    XCTAssertEqual(
      routeSystem.mutations,
      ["delete \(address) via 198.51.100.1", "add \(address) via 192.0.2.1"]
    )
    XCTAssertEqual(result.state.routes.first?.gateway, "192.0.2.1")
    XCTAssertEqual(stateStore.state, result.state)
  }

  func testApplyReplacesRouteWhenPhysicalAddressChangesBehindSameGateway() throws {
    let address = "203.0.113.10"
    let owned = OwnedRoute(
      address: address,
      gateway: "192.0.2.1",
      interface: "en0",
      sources: ["portal.example.org"]
    )
    let routeSystem = FakeRouteSystem(routes: [
      address: observed(
        address: address,
        gateway: owned.gateway,
        interfaceAddress: "192.0.2.33"
      )
    ])
    let stateStore = MemoryRouteStateStore(state: RouteState(routes: [owned]))
    let service = RouteReconciliationService(
      inspector: routeSystem,
      mutator: routeSystem,
      stateStore: stateStore
    )

    let result = try service.apply(routePlan: routePlan(address: address))

    XCTAssertEqual(
      routeSystem.mutations,
      ["delete \(address) via 192.0.2.1", "add \(address) via 192.0.2.1"]
    )
    XCTAssertEqual(routeSystem.routes[address]?.interfaceAddress, "192.0.2.44")
    XCTAssertEqual(stateStore.state, result.state)
  }

  func testApplyDoesNotMutateWhenAConflictExists() {
    let address = "203.0.113.10"
    let routeSystem = FakeRouteSystem(routes: [
      address: observed(address: address, gateway: "198.51.100.1")
    ])
    let stateStore = MemoryRouteStateStore(state: RouteState())
    let service = RouteReconciliationService(
      inspector: routeSystem,
      mutator: routeSystem,
      stateStore: stateStore
    )

    XCTAssertThrowsError(try service.apply(routePlan: routePlan(address: address)))
    XCTAssertTrue(routeSystem.mutations.isEmpty)
    XCTAssertTrue(stateStore.state.routes.isEmpty)
  }

  func testCleanupRemovesOnlyRouteThatStillMatchesOwnedState() throws {
    let address = "203.0.113.10"
    let owned = OwnedRoute(
      address: address,
      gateway: "192.0.2.1",
      interface: "en0",
      sources: ["portal.example.org"]
    )
    let routeSystem = FakeRouteSystem(routes: [
      address: observed(
        address: address,
        gateway: owned.gateway,
        interfaceAddress: "192.0.2.33"
      )
    ])
    let stateStore = MemoryRouteStateStore(state: RouteState(routes: [owned]))
    let service = RouteReconciliationService(
      inspector: routeSystem,
      mutator: routeSystem,
      stateStore: stateStore
    )

    let result = try service.cleanup()

    XCTAssertEqual(routeSystem.mutations, ["delete \(address) via 192.0.2.1"])
    XCTAssertTrue(result.state.routes.isEmpty)
  }

  func testCleanupRefusesRouteThatNoLongerMatchesOwnedState() {
    let address = "203.0.113.10"
    let owned = OwnedRoute(
      address: address,
      gateway: "192.0.2.1",
      interface: "en0",
      sources: ["portal.example.org"]
    )
    let routeSystem = FakeRouteSystem(routes: [
      address: observed(address: address, gateway: "198.51.100.1")
    ])
    let stateStore = MemoryRouteStateStore(state: RouteState(routes: [owned]))
    let service = RouteReconciliationService(
      inspector: routeSystem,
      mutator: routeSystem,
      stateStore: stateStore
    )

    XCTAssertThrowsError(try service.cleanup())
    XCTAssertTrue(routeSystem.mutations.isEmpty)
    XCTAssertEqual(stateStore.state.routes, [owned])
  }

  func testAdoptionLeavesPreviouslyOwnedRouteForReconciliation() throws {
    let address = "203.0.113.10"
    let owned = OwnedRoute(
      address: address,
      gateway: "198.51.100.1",
      interface: "en0",
      sources: ["portal.example.org"]
    )
    let routeSystem = FakeRouteSystem(routes: [
      address: observed(address: address, gateway: owned.gateway)
    ])
    let stateStore = MemoryRouteStateStore(state: RouteState(routes: [owned]))
    let service = RouteReconciliationService(
      inspector: routeSystem,
      mutator: routeSystem,
      stateStore: stateStore
    )

    let result = try service.adoptExisting(routePlan: routePlan(address: address))

    XCTAssertTrue(result.conflicts.isEmpty)
    XCTAssertTrue(result.adopted.isEmpty)
    XCTAssertEqual(result.state.routes, [owned])
  }

  private func routePlan(address: String) -> RoutePlan {
    RoutePlan(
      profile: Profile(
        id: "default",
        name: "Default",
        match: ProfileMatch(ssids: ["Example Wi-Fi"]),
        groups: ["services"]
      ),
      network: NetworkSnapshot(
        ssid: nil,
        physicalInterface: "en0",
        physicalGateway: "192.0.2.1",
        physicalAddress: "192.0.2.44"
      ),
      routeGroups: [
        RouteGroupPlan(
          id: "services",
          name: "Services",
          targets: [RouteTarget(address: address, sources: ["portal.example.org"])]
        )
      ],
      checkOnlyGroups: [],
      profileWasForced: true
    )
  }

  private func observed(
    address: String,
    gateway: String,
    interfaceAddress: String = "192.0.2.44"
  ) -> ObservedRoute {
    ObservedRoute(
      destination: address,
      gateway: gateway,
      interface: "en0",
      interfaceAddress: interfaceAddress,
      flags: ["UP", "GATEWAY", "HOST", "STATIC"]
    )
  }
}

private final class MemoryRouteStateStore: RouteStateStoring {
  var state: RouteState

  init(state: RouteState) {
    self.state = state
  }

  func load() throws -> RouteState { state }

  func save(_ state: RouteState) throws {
    self.state = state
  }
}

private final class FakeRouteSystem: RouteInspecting, RouteMutating {
  var routes: [String: ObservedRoute]
  var mutations = [String]()
  let physicalAddress: String

  init(routes: [String: ObservedRoute], physicalAddress: String = "192.0.2.44") {
    self.routes = routes
    self.physicalAddress = physicalAddress
  }

  func route(to address: String) throws -> ObservedRoute {
    routes[address]
      ?? ObservedRoute(
        destination: "default",
        gateway: "192.0.2.1",
        interface: "en0",
        flags: ["UP", "GATEWAY", "STATIC"]
      )
  }

  func addHostRoute(address: String, gateway: String) throws {
    mutations.append("add \(address) via \(gateway)")
    routes[address] = ObservedRoute(
      destination: address,
      gateway: gateway,
      interface: "en0",
      interfaceAddress: physicalAddress,
      flags: ["UP", "GATEWAY", "HOST", "STATIC"]
    )
  }

  func deleteHostRoute(address: String, gateway: String) throws {
    mutations.append("delete \(address) via \(gateway)")
    routes[address] = nil
  }
}
