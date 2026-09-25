import Foundation

public struct DesiredRoute: Sendable, Equatable {
  public let address: String
  public let sources: [String]

  public init(address: String, sources: [String]) {
    self.address = address
    self.sources = sources
  }
}

public enum RouteActionKind: String, Sendable, Equatable {
  case add
  case replace
  case remove
  case forgetMissing = "forget-missing"
}

public struct RouteAction: Sendable, Equatable {
  public let kind: RouteActionKind
  public let address: String
  public let oldGateway: String?
  public let newGateway: String?
  public let interface: String?
  public let sources: [String]

  public init(
    kind: RouteActionKind,
    address: String,
    oldGateway: String? = nil,
    newGateway: String? = nil,
    interface: String? = nil,
    sources: [String] = []
  ) {
    self.kind = kind
    self.address = address
    self.oldGateway = oldGateway
    self.newGateway = newGateway
    self.interface = interface
    self.sources = sources
  }
}

public struct RouteConflict: Sendable, Equatable {
  public let address: String
  public let reason: String

  public init(address: String, reason: String) {
    self.address = address
    self.reason = reason
  }
}

public struct ReconciliationPlan: Sendable, Equatable {
  public let actions: [RouteAction]
  public let conflicts: [RouteConflict]
  public let unchangedCount: Int

  public init(actions: [RouteAction], conflicts: [RouteConflict], unchangedCount: Int) {
    self.actions = actions
    self.conflicts = conflicts
    self.unchangedCount = unchangedCount
  }
}

public enum ReconciliationPlanner {
  public static func desiredRoutes(from plan: RoutePlan) -> [DesiredRoute] {
    var sourcesByAddress = [String: Set<String>]()
    for group in plan.routeGroups {
      for target in group.targets {
        sourcesByAddress[target.address, default: []].formUnion(target.sources)
      }
    }
    return sourcesByAddress.map { address, sources in
      DesiredRoute(address: address, sources: sources.sorted())
    }.sorted { ipv4Components($0.address).lexicographicallyPrecedes(ipv4Components($1.address)) }
  }

  public static func makePlan(
    desired: [DesiredRoute],
    network: NetworkSnapshot,
    state: RouteState,
    observed: [String: ObservedRoute]
  ) -> ReconciliationPlan {
    let desiredByAddress = Dictionary(uniqueKeysWithValues: desired.map { ($0.address, $0) })
    let ownedByAddress = Dictionary(uniqueKeysWithValues: state.routes.map { ($0.address, $0) })
    var actions = [RouteAction]()
    var conflicts = [RouteConflict]()
    var unchangedCount = 0

    for route in desired {
      let current = observed[route.address]
      let owned = ownedByAddress[route.address]

      if let owned {
        if matches(
          current,
          address: route.address,
          gateway: network.physicalGateway,
          interface: network.physicalInterface
        ) {
          unchangedCount += 1
        } else if matches(
          current,
          address: route.address,
          gateway: owned.gateway,
          interface: owned.interface
        ) {
          actions.append(
            RouteAction(
              kind: .replace,
              address: route.address,
              oldGateway: owned.gateway,
              newGateway: network.physicalGateway,
              interface: network.physicalInterface,
              sources: route.sources
            ))
        } else if current?.isExplicitStaticHostRoute(for: route.address) == true {
          conflicts.append(
            RouteConflict(
              address: route.address,
              reason: "the current static host route no longer matches RouteBar-owned state"
            ))
        } else {
          actions.append(
            RouteAction(
              kind: .add,
              address: route.address,
              newGateway: network.physicalGateway,
              interface: network.physicalInterface,
              sources: route.sources
            ))
        }
      } else if current?.isExplicitStaticHostRoute(for: route.address) == true {
        conflicts.append(
          RouteConflict(
            address: route.address,
            reason: "an unowned static host route already exists"
          ))
      } else {
        actions.append(
          RouteAction(
            kind: .add,
            address: route.address,
            newGateway: network.physicalGateway,
            interface: network.physicalInterface,
            sources: route.sources
          ))
      }
    }

    for owned in state.routes where desiredByAddress[owned.address] == nil {
      let current = observed[owned.address]
      if matches(
        current,
        address: owned.address,
        gateway: owned.gateway,
        interface: owned.interface
      ) {
        actions.append(
          RouteAction(
            kind: .remove,
            address: owned.address,
            oldGateway: owned.gateway,
            interface: owned.interface
          ))
      } else if current?.isExplicitStaticHostRoute(for: owned.address) == true {
        conflicts.append(
          RouteConflict(
            address: owned.address,
            reason: "the stale address now has a static route not matching RouteBar-owned state"
          ))
      } else {
        actions.append(
          RouteAction(
            kind: .forgetMissing,
            address: owned.address,
            oldGateway: owned.gateway,
            interface: owned.interface
          ))
      }
    }

    return ReconciliationPlan(
      actions: actions.sorted(by: actionLessThan),
      conflicts: conflicts.sorted { $0.address < $1.address },
      unchangedCount: unchangedCount
    )
  }

  public static func adoptableRoutes(
    desired: [DesiredRoute],
    network: NetworkSnapshot,
    observed: [String: ObservedRoute]
  ) -> (routes: [OwnedRoute], conflicts: [RouteConflict]) {
    var routes = [OwnedRoute]()
    var conflicts = [RouteConflict]()

    for route in desired {
      guard let current = observed[route.address],
        current.isExplicitStaticHostRoute(for: route.address)
      else { continue }

      if matches(
        current,
        address: route.address,
        gateway: network.physicalGateway,
        interface: network.physicalInterface
      ) {
        routes.append(
          OwnedRoute(
            address: route.address,
            gateway: network.physicalGateway,
            interface: network.physicalInterface,
            sources: route.sources
          ))
      } else {
        conflicts.append(
          RouteConflict(
            address: route.address,
            reason: "existing static host route does not use the current physical gateway"
          ))
      }
    }

    return (
      routes.sorted { $0.address < $1.address },
      conflicts.sorted { $0.address < $1.address }
    )
  }

  public static func cleanupPlan(
    state: RouteState,
    observed: [String: ObservedRoute]
  ) -> ReconciliationPlan {
    var actions = [RouteAction]()
    var conflicts = [RouteConflict]()

    for owned in state.routes {
      let current = observed[owned.address]
      if matches(
        current,
        address: owned.address,
        gateway: owned.gateway,
        interface: owned.interface
      ) {
        actions.append(
          RouteAction(
            kind: .remove,
            address: owned.address,
            oldGateway: owned.gateway,
            interface: owned.interface
          ))
      } else if current?.isExplicitStaticHostRoute(for: owned.address) == true {
        conflicts.append(
          RouteConflict(
            address: owned.address,
            reason: "the current static host route no longer matches RouteBar-owned state"
          ))
      } else {
        actions.append(
          RouteAction(
            kind: .forgetMissing,
            address: owned.address,
            oldGateway: owned.gateway,
            interface: owned.interface
          ))
      }
    }

    return ReconciliationPlan(
      actions: actions.sorted(by: actionLessThan),
      conflicts: conflicts.sorted { $0.address < $1.address },
      unchangedCount: 0
    )
  }

  private static func matches(
    _ observed: ObservedRoute?,
    address: String,
    gateway: String,
    interface: String
  ) -> Bool {
    guard let observed else { return false }
    return observed.isExplicitStaticHostRoute(for: address)
      && observed.gateway == gateway
      && observed.interface == interface
  }

  private static func actionLessThan(_ left: RouteAction, _ right: RouteAction) -> Bool {
    let order: [RouteActionKind: Int] = [.add: 0, .replace: 1, .remove: 2, .forgetMissing: 3]
    if order[left.kind] != order[right.kind] {
      return order[left.kind, default: 99] < order[right.kind, default: 99]
    }
    return ipv4Components(left.address).lexicographicallyPrecedes(ipv4Components(right.address))
  }

  private static func ipv4Components(_ address: String) -> [Int] {
    address.split(separator: ".").compactMap { Int($0) }
  }
}
