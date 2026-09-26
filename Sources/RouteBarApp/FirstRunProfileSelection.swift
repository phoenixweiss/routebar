import RouteBarCore

struct RouteBarProfileOption: Sendable, Equatable, Identifiable {
  let id: String
  let name: String

  init(profile: Profile) {
    id = profile.id
    name = profile.name
  }
}

enum FirstRunProfileSelection: Sendable, Equatable {
  case selected(String)
  case requiresSelection

  static func resolve(
    profiles: [RouteBarProfileOption],
    selectedProfileID: String?
  ) -> FirstRunProfileSelection {
    if let selectedProfileID,
      profiles.contains(where: { $0.id == selectedProfileID })
    {
      return .selected(selectedProfileID)
    }
    if profiles.count == 1, let profile = profiles.first {
      return .selected(profile.id)
    }
    return .requiresSelection
  }
}
