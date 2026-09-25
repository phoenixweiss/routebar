import Foundation

public struct ReconciliationError: LocalizedError, Equatable {
  public let message: String

  public var errorDescription: String? { message }
}

public struct ReconciliationResult: Sendable, Equatable {
  public let plan: ReconciliationPlan
  public let state: RouteState

  public init(plan: ReconciliationPlan, state: RouteState) {
    self.plan = plan
    self.state = state
  }
}

public struct AdoptionResult: Sendable, Equatable {
  public let adopted: [OwnedRoute]
  public let conflicts: [RouteConflict]
  public let state: RouteState

  public init(adopted: [OwnedRoute], conflicts: [RouteConflict], state: RouteState) {
    self.adopted = adopted
    self.conflicts = conflicts
    self.state = state
  }
}

public struct RouteReconciliationService {
  private let inspector: RouteInspecting
  private let mutator: RouteMutating
  private let stateStore: RouteStateStoring

  public init(
    inspector: RouteInspecting = SystemRouteInspector(),
    mutator: RouteMutating = SystemRouteMutator(),
    stateStore: RouteStateStoring
  ) {
    self.inspector = inspector
    self.mutator = mutator
    self.stateStore = stateStore
  }

  public func plan(routePlan: RoutePlan) throws -> ReconciliationResult {
    let desired = ReconciliationPlanner.desiredRoutes(from: routePlan)
    let state = try stateStore.load()
    let observed = try inspect(addresses: Set(desired.map(\.address) + state.routes.map(\.address)))
    let plan = ReconciliationPlanner.makePlan(
      desired: desired,
      network: routePlan.network,
      state: state,
      observed: observed
    )
    return ReconciliationResult(plan: plan, state: state)
  }

  public func adoptExisting(routePlan: RoutePlan) throws -> AdoptionResult {
    var state = try stateStore.load()
    let ownedAddresses = Set(state.routes.map(\.address))
    let desired = ReconciliationPlanner.desiredRoutes(from: routePlan)
      .filter { !ownedAddresses.contains($0.address) }
    let observed = try inspect(addresses: Set(desired.map(\.address)))
    let adoption = ReconciliationPlanner.adoptableRoutes(
      desired: desired,
      network: routePlan.network,
      observed: observed
    )
    guard adoption.conflicts.isEmpty else {
      return AdoptionResult(adopted: [], conflicts: adoption.conflicts, state: state)
    }

    var routesByAddress = Dictionary(uniqueKeysWithValues: state.routes.map { ($0.address, $0) })
    var adopted = [OwnedRoute]()
    for route in adoption.routes where routesByAddress[route.address] == nil {
      routesByAddress[route.address] = route
      adopted.append(route)
    }
    state = RouteState(routes: Array(routesByAddress.values))
    try stateStore.save(state)
    return AdoptionResult(adopted: adopted, conflicts: [], state: state)
  }

  public func apply(routePlan: RoutePlan) throws -> ReconciliationResult {
    let result = try plan(routePlan: routePlan)
    guard result.plan.conflicts.isEmpty else {
      throw ReconciliationError(
        message: "refusing to apply a plan with \(result.plan.conflicts.count) route conflict(s)"
      )
    }

    var state = result.state
    for action in result.plan.actions {
      switch action.kind {
      case .add:
        guard let gateway = action.newGateway, let interface = action.interface else {
          throw ReconciliationError(message: "incomplete add action for \(action.address)")
        }
        state = replacing(
          state,
          with: OwnedRoute(
            address: action.address,
            gateway: gateway,
            interface: interface,
            sources: action.sources
          ))
        try stateStore.save(state)
        try mutator.addHostRoute(address: action.address, gateway: gateway)
        try verifyOwnedRoute(address: action.address, gateway: gateway, interface: interface)

      case .replace:
        guard let oldGateway = action.oldGateway,
          let newGateway = action.newGateway,
          let interface = action.interface
        else {
          throw ReconciliationError(message: "incomplete replace action for \(action.address)")
        }
        try mutator.deleteHostRoute(address: action.address, gateway: oldGateway)
        state = replacing(
          state,
          with: OwnedRoute(
            address: action.address,
            gateway: newGateway,
            interface: interface,
            sources: action.sources
          ))
        try stateStore.save(state)
        try mutator.addHostRoute(address: action.address, gateway: newGateway)
        try verifyOwnedRoute(address: action.address, gateway: newGateway, interface: interface)

      case .remove:
        guard let oldGateway = action.oldGateway else {
          throw ReconciliationError(message: "incomplete remove action for \(action.address)")
        }
        try mutator.deleteHostRoute(address: action.address, gateway: oldGateway)
        state = removing(state, address: action.address)
        try stateStore.save(state)

      case .forgetMissing:
        state = removing(state, address: action.address)
        try stateStore.save(state)
      }
    }
    return ReconciliationResult(plan: result.plan, state: state)
  }

  public func cleanupPlan() throws -> ReconciliationResult {
    let state = try stateStore.load()
    let observed = try inspect(addresses: Set(state.routes.map(\.address)))
    let plan = ReconciliationPlanner.cleanupPlan(state: state, observed: observed)
    return ReconciliationResult(plan: plan, state: state)
  }

  public func cleanup() throws -> ReconciliationResult {
    let result = try cleanupPlan()
    guard result.plan.conflicts.isEmpty else {
      throw ReconciliationError(
        message: "refusing to clean up with \(result.plan.conflicts.count) route conflict(s)"
      )
    }

    var state = result.state
    for action in result.plan.actions {
      switch action.kind {
      case .remove:
        guard let oldGateway = action.oldGateway else {
          throw ReconciliationError(message: "incomplete remove action for \(action.address)")
        }
        try mutator.deleteHostRoute(address: action.address, gateway: oldGateway)
        state = removing(state, address: action.address)
        try stateStore.save(state)

      case .forgetMissing:
        state = removing(state, address: action.address)
        try stateStore.save(state)

      case .add, .replace:
        throw ReconciliationError(message: "unexpected cleanup action for \(action.address)")
      }
    }
    return ReconciliationResult(plan: result.plan, state: state)
  }

  private func inspect(addresses: Set<String>) throws -> [String: ObservedRoute] {
    var observations = [String: ObservedRoute]()
    for address in addresses.sorted() {
      observations[address] = try inspector.route(to: address)
    }
    return observations
  }

  private func verifyOwnedRoute(address: String, gateway: String, interface: String) throws {
    let observation = try inspector.route(to: address)
    guard observation.isExplicitStaticHostRoute(for: address),
      observation.gateway == gateway,
      observation.interface == interface
    else {
      throw ReconciliationError(message: "route verification failed for \(address)")
    }
  }

  private func replacing(_ state: RouteState, with route: OwnedRoute) -> RouteState {
    RouteState(routes: state.routes.filter { $0.address != route.address } + [route])
  }

  private func removing(_ state: RouteState, address: String) -> RouteState {
    RouteState(routes: state.routes.filter { $0.address != address })
  }
}
