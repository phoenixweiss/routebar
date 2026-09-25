import Foundation
import Yams

public struct RouteBarConfiguration: Decodable, Sendable, Equatable {
  public let version: Int
  public let profiles: [Profile]
  public let groups: [Group]

  enum CodingKeys: String, CodingKey {
    case version
    case profiles
    case groups
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownKeys(in: decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
    let container = try decoder.container(keyedBy: CodingKeys.self)
    version = try container.decode(Int.self, forKey: .version)
    profiles = try container.decode([Profile].self, forKey: .profiles)
    groups = try container.decode([Group].self, forKey: .groups)
  }
}

extension RouteBarConfiguration.CodingKeys: CaseIterable {}

public struct Profile: Decodable, Sendable, Equatable {
  public let id: String
  public let name: String
  public let match: ProfileMatch
  public let groups: [String]

  enum CodingKeys: String, CodingKey, CaseIterable {
    case id
    case name
    case match
    case groups
  }

  public init(id: String, name: String, match: ProfileMatch, groups: [String]) {
    self.id = id
    self.name = name
    self.match = match
    self.groups = groups
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownKeys(in: decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    match = try container.decode(ProfileMatch.self, forKey: .match)
    groups = try container.decode([String].self, forKey: .groups)
  }
}

public struct ProfileMatch: Decodable, Sendable, Equatable {
  public let ssids: [String]

  enum CodingKeys: String, CodingKey, CaseIterable {
    case ssids
  }

  public init(ssids: [String]) {
    self.ssids = ssids
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownKeys(in: decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
    let container = try decoder.container(keyedBy: CodingKeys.self)
    ssids = try container.decode([String].self, forKey: .ssids)
  }
}

public struct Group: Decodable, Sendable, Equatable {
  public let id: String
  public let name: String
  public let mode: GroupMode
  public let domains: [String]
  public let addresses: [String]
  public let checks: [HTTPSCheck]
  public let endpoints: [Endpoint]
  let suppliedFields: Set<String>

  enum CodingKeys: String, CodingKey, CaseIterable {
    case id
    case name
    case mode
    case domains
    case addresses
    case checks
    case endpoints
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownKeys(in: decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
    let container = try decoder.container(keyedBy: CodingKeys.self)
    suppliedFields = Set(container.allKeys.map(\.rawValue))
    id = try container.decode(String.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    mode = try container.decode(GroupMode.self, forKey: .mode)
    domains = try container.decodeIfPresent([String].self, forKey: .domains) ?? []
    addresses = try container.decodeIfPresent([String].self, forKey: .addresses) ?? []
    checks = try container.decodeIfPresent([HTTPSCheck].self, forKey: .checks) ?? []
    endpoints = try container.decodeIfPresent([Endpoint].self, forKey: .endpoints) ?? []
  }
}

public enum GroupMode: String, Decodable, Sendable, Equatable {
  case bypassVPN = "bypass-vpn"
  case checkOnly = "check-only"
}

public struct HTTPSCheck: Decodable, Sendable, Equatable {
  public let type: CheckType
  public let url: String
  public let expectedStatuses: [Int]

  enum CodingKeys: String, CodingKey, CaseIterable {
    case type
    case url
    case expectedStatuses = "expected_statuses"
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownKeys(in: decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
    let container = try decoder.container(keyedBy: CodingKeys.self)
    type = try container.decode(CheckType.self, forKey: .type)
    url = try container.decode(String.self, forKey: .url)
    expectedStatuses = try container.decode([Int].self, forKey: .expectedStatuses)
  }
}

public enum CheckType: String, Decodable, Sendable, Equatable {
  case https
}

public struct Endpoint: Decodable, Sendable, Equatable {
  public let name: String
  public let host: String
  public let port: Int
  public let `protocol`: EndpointProtocol

  enum CodingKeys: String, CodingKey, CaseIterable {
    case name
    case host
    case port
    case `protocol`
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownKeys(in: decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decode(String.self, forKey: .name)
    host = try container.decode(String.self, forKey: .host)
    port = try container.decode(Int.self, forKey: .port)
    `protocol` = try container.decode(EndpointProtocol.self, forKey: .protocol)
  }
}

public enum EndpointProtocol: String, Decodable, Sendable, Equatable {
  case tls
  case startTLSSMTP = "starttls-smtp"
}

public enum ConfigurationLoader {
  public static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/routebar/config.yaml")

  public static func load(from url: URL = defaultURL) throws -> RouteBarConfiguration {
    let source = try String(contentsOf: url, encoding: .utf8)
    let configuration: RouteBarConfiguration
    do {
      configuration = try YAMLDecoder().decode(RouteBarConfiguration.self, from: source)
    } catch let error as DecodingError {
      throw ConfigurationDecodingError(error)
    }
    try ConfigurationValidator.validate(configuration)
    return configuration
  }
}

public struct ConfigurationDecodingError: LocalizedError {
  public let message: String

  public var errorDescription: String? { message }

  init(_ error: DecodingError) {
    switch error {
    case .dataCorrupted(let context):
      message = Self.describe(context.debugDescription, at: context.codingPath)
    case .keyNotFound(let key, let context):
      message = Self.describe("Missing required field: \(key.stringValue)", at: context.codingPath)
    case .typeMismatch(let type, let context):
      message = Self.describe(
        "Expected \(type): \(context.debugDescription)", at: context.codingPath)
    case .valueNotFound(let type, let context):
      message = Self.describe("Missing \(type) value", at: context.codingPath)
    @unknown default:
      message = "Could not decode the configuration"
    }
  }

  private static func describe(_ reason: String, at codingPath: [CodingKey]) -> String {
    let path = codingPath.reduce("") { partial, key in
      if let index = key.intValue {
        return "\(partial)[\(index)]"
      }
      return partial.isEmpty ? key.stringValue : "\(partial).\(key.stringValue)"
    }
    return path.isEmpty ? reason : "\(path): \(reason)"
  }
}
