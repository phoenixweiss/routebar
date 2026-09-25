import Foundation

public struct RouteTargetStatus: Sendable, Equatable, Identifiable {
  public var id: String { address }

  public let address: String
  public let sources: [String]
  public let isActive: Bool
  public let observedGateway: String?
  public let observedInterface: String?

  public init(
    address: String,
    sources: [String],
    isActive: Bool,
    observedGateway: String?,
    observedInterface: String?
  ) {
    self.address = address
    self.sources = sources
    self.isActive = isActive
    self.observedGateway = observedGateway
    self.observedInterface = observedInterface
  }
}

public struct RouteGroupStatus: Sendable, Equatable, Identifiable {
  public var id: String { groupID }
  public var activeCount: Int { targets.filter(\.isActive).count }

  public let groupID: String
  public let name: String
  public let targets: [RouteTargetStatus]

  public init(groupID: String, name: String, targets: [RouteTargetStatus]) {
    self.groupID = groupID
    self.name = name
    self.targets = targets
  }
}

public struct RouteStatusSnapshot: Sendable, Equatable {
  public var routeCount: Int { groups.reduce(0) { $0 + $1.targets.count } }
  public var activeCount: Int { groups.reduce(0) { $0 + $1.activeCount } }
  public var allRoutesActive: Bool { routeCount > 0 && routeCount == activeCount }

  public let profile: Profile
  public let network: NetworkSnapshot
  public let groups: [RouteGroupStatus]
  public let daemon: DaemonRuntimeStatus
  public let checkedAt: Date

  public init(
    profile: Profile,
    network: NetworkSnapshot,
    groups: [RouteGroupStatus],
    daemon: DaemonRuntimeStatus,
    checkedAt: Date
  ) {
    self.profile = profile
    self.network = network
    self.groups = groups
    self.daemon = daemon
    self.checkedAt = checkedAt
  }
}

public struct RouteStatusService {
  private let routeInspector: RouteInspecting
  private let daemonInspector: DaemonRuntimeInspecting

  public init(
    routeInspector: RouteInspecting = SystemRouteInspector(),
    daemonInspector: DaemonRuntimeInspecting = SystemDaemonRuntimeInspector()
  ) {
    self.routeInspector = routeInspector
    self.daemonInspector = daemonInspector
  }

  public func snapshot(routePlan: RoutePlan, checkedAt: Date = Date()) throws
    -> RouteStatusSnapshot
  {
    let addresses = Set(routePlan.routeGroups.flatMap { $0.targets.map(\.address) })
    var observed = [String: ObservedRoute]()
    for address in addresses.sorted() {
      observed[address] = try routeInspector.route(to: address)
    }

    let groups = routePlan.routeGroups.map { group in
      RouteGroupStatus(
        groupID: group.id,
        name: group.name,
        targets: group.targets.map { target in
          let route = observed[target.address]
          return RouteTargetStatus(
            address: target.address,
            sources: target.sources,
            isActive: route?.isExplicitStaticHostRoute(for: target.address) == true
              && route?.gateway == routePlan.network.physicalGateway
              && route?.interface == routePlan.network.physicalInterface,
            observedGateway: route?.gateway,
            observedInterface: route?.interface
          )
        }
      )
    }

    return RouteStatusSnapshot(
      profile: routePlan.profile,
      network: routePlan.network,
      groups: groups,
      daemon: daemonInspector.status(),
      checkedAt: checkedAt
    )
  }
}
