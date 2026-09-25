import Foundation

public struct RoutePlan: Sendable, Equatable {
  public let profile: Profile
  public let network: NetworkSnapshot
  public let routeGroups: [RouteGroupPlan]
  public let checkOnlyGroups: [Group]
  public let profileWasForced: Bool

  public init(
    profile: Profile,
    network: NetworkSnapshot,
    routeGroups: [RouteGroupPlan],
    checkOnlyGroups: [Group],
    profileWasForced: Bool
  ) {
    self.profile = profile
    self.network = network
    self.routeGroups = routeGroups
    self.checkOnlyGroups = checkOnlyGroups
    self.profileWasForced = profileWasForced
  }
}

public struct RouteGroupPlan: Sendable, Equatable {
  public let id: String
  public let name: String
  public let targets: [RouteTarget]

  public init(id: String, name: String, targets: [RouteTarget]) {
    self.id = id
    self.name = name
    self.targets = targets
  }
}

public struct RouteTarget: Sendable, Equatable {
  public let address: String
  public let sources: [String]

  public init(address: String, sources: [String]) {
    self.address = address
    self.sources = sources
  }
}

public struct RoutePlanningError: LocalizedError, Equatable {
  public let message: String

  public var errorDescription: String? { message }
}

public struct RoutePlanner {
  private let discovery: NetworkDiscovering
  private let resolver: DNSResolving

  public init(
    discovery: NetworkDiscovering = SystemNetworkDiscovery(),
    resolver: DNSResolving = SystemDNSResolver()
  ) {
    self.discovery = discovery
    self.resolver = resolver
  }

  public func plan(
    configuration: RouteBarConfiguration,
    forcedProfileID: String? = nil
  ) throws -> RoutePlan {
    let network = try discovery.snapshot()
    let profile = try selectProfile(
      from: configuration.profiles,
      ssid: network.ssid,
      forcedProfileID: forcedProfileID
    )
    let groupsByID = Dictionary(uniqueKeysWithValues: configuration.groups.map { ($0.id, $0) })
    let selectedGroups = profile.groups.compactMap { groupsByID[$0] }

    var routeGroups = [RouteGroupPlan]()
    var checkOnlyGroups = [Group]()

    for group in selectedGroups {
      switch group.mode {
      case .checkOnly:
        checkOnlyGroups.append(group)
      case .bypassVPN:
        var sourcesByAddress = [String: Set<String>]()
        for address in group.addresses {
          sourcesByAddress[address, default: []].insert("fixed address")
        }
        for domain in group.domains {
          for address in try resolver.resolveIPv4(hostname: domain) {
            sourcesByAddress[address, default: []].insert(domain)
          }
        }
        let targets = sourcesByAddress.map { address, sources in
          RouteTarget(address: address, sources: sources.sorted())
        }.sorted {
          ipv4Components($0.address).lexicographicallyPrecedes(ipv4Components($1.address))
        }
        routeGroups.append(RouteGroupPlan(id: group.id, name: group.name, targets: targets))
      }
    }

    return RoutePlan(
      profile: profile,
      network: network,
      routeGroups: routeGroups,
      checkOnlyGroups: checkOnlyGroups,
      profileWasForced: forcedProfileID != nil
    )
  }

  private func selectProfile(
    from profiles: [Profile],
    ssid: String?,
    forcedProfileID: String?
  ) throws -> Profile {
    if let forcedProfileID {
      guard let profile = profiles.first(where: { $0.id == forcedProfileID }) else {
        throw RoutePlanningError(message: "unknown profile \(forcedProfileID)")
      }
      return profile
    }

    guard let ssid, !ssid.isEmpty else {
      throw RoutePlanningError(
        message:
          "Wi-Fi name is unavailable; grant location access or use --profile for a read-only plan"
      )
    }
    let matches = profiles.filter { $0.match.ssids.contains(ssid) }
    guard matches.count == 1, let profile = matches.first else {
      if matches.isEmpty {
        throw RoutePlanningError(message: "no profile matches the current Wi-Fi network")
      }
      throw RoutePlanningError(message: "multiple profiles match the current Wi-Fi network")
    }
    return profile
  }

  private func ipv4Components(_ address: String) -> [Int] {
    address.split(separator: ".").compactMap { Int($0) }
  }
}
