import Foundation

public struct OwnedRoute: Codable, Sendable, Equatable {
  public let address: String
  public let gateway: String
  public let interface: String
  public let sources: [String]

  public init(address: String, gateway: String, interface: String, sources: [String]) {
    self.address = address
    self.gateway = gateway
    self.interface = interface
    self.sources = sources
  }
}

public struct RouteState: Codable, Sendable, Equatable {
  public static let currentVersion = 1

  public let version: Int
  public var routes: [OwnedRoute]

  public init(version: Int = currentVersion, routes: [OwnedRoute] = []) {
    self.version = version
    self.routes = routes.sorted {
      $0.address.localizedStandardCompare($1.address) == .orderedAscending
    }
  }
}

public struct RouteStateError: LocalizedError, Equatable {
  public let message: String

  public var errorDescription: String? { message }
}

public protocol RouteStateStoring {
  func load() throws -> RouteState
  func save(_ state: RouteState) throws
}

public struct FileRouteStateStore: RouteStateStoring {
  public let url: URL

  public init(url: URL) {
    self.url = url
  }

  public func load() throws -> RouteState {
    guard FileManager.default.fileExists(atPath: url.path) else { return RouteState() }
    let data = try Data(contentsOf: url)
    let state = try JSONDecoder().decode(RouteState.self, from: data)
    guard state.version == RouteState.currentVersion else {
      throw RouteStateError(message: "unsupported route state version: \(state.version)")
    }
    return state
  }

  public func save(_ state: RouteState) throws {
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var data = try encoder.encode(state)
    data.append(0x0A)
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
}
