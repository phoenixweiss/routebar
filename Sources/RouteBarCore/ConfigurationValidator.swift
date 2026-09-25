import Darwin
import Foundation

public struct ConfigurationValidationError: LocalizedError, Equatable {
  public let message: String

  public var errorDescription: String? { message }
}

public enum ConfigurationValidator {
  private static let identifierPattern = try! NSRegularExpression(
    pattern: #"^[a-z0-9][a-z0-9-]*$"#
  )
  private static let hostnameLabelPattern = try! NSRegularExpression(
    pattern: #"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$"#
  )

  public static func validate(_ configuration: RouteBarConfiguration) throws {
    try require(configuration.version == 1, "version must be 1")
    try require(!configuration.profiles.isEmpty, "profiles must not be empty")
    try require(!configuration.groups.isEmpty, "groups must not be empty")

    try requireUnique(configuration.profiles.map(\.id), label: "profile id")
    try requireUnique(configuration.groups.map(\.id), label: "group id")

    for profile in configuration.profiles {
      try validateIdentifier(profile.id, at: "profile \(profile.id)")
      try validateNonEmpty(profile.name, at: "profile \(profile.id).name")
      try require(
        !profile.match.ssids.isEmpty, "profile \(profile.id).match.ssids must not be empty")
      try validateStringList(profile.match.ssids, at: "profile \(profile.id).match.ssids")
      try require(!profile.groups.isEmpty, "profile \(profile.id).groups must not be empty")
      try validateStringList(profile.groups, at: "profile \(profile.id).groups")
    }

    let groupIDs = Set(configuration.groups.map(\.id))
    for profile in configuration.profiles {
      for groupID in profile.groups where !groupIDs.contains(groupID) {
        throw error("profile \(profile.id) references unknown group \(groupID)")
      }
    }

    for group in configuration.groups {
      try validateGroup(group)
    }
  }

  private static func validateGroup(_ group: Group) throws {
    try validateIdentifier(group.id, at: "group \(group.id)")
    try validateNonEmpty(group.name, at: "group \(group.id).name")

    switch group.mode {
    case .bypassVPN:
      try require(
        !group.suppliedFields.contains("endpoints"),
        "bypass group \(group.id) must not contain endpoints"
      )
      try require(
        !group.domains.isEmpty || !group.addresses.isEmpty,
        "bypass group \(group.id) must contain at least one domain or address"
      )
      try validateStringList(group.domains, at: "group \(group.id).domains", allowEmpty: true)
      try validateStringList(group.addresses, at: "group \(group.id).addresses", allowEmpty: true)
      for domain in group.domains {
        try validateHostname(domain, at: "group \(group.id).domains")
      }
      for address in group.addresses {
        try require(
          isIPv4(address), "group \(group.id).addresses contains invalid IPv4 address \(address)")
      }
      for check in group.checks {
        try validateCheck(check, groupID: group.id)
      }

    case .checkOnly:
      try require(
        !group.suppliedFields.contains("domains"),
        "check-only group \(group.id) must not contain domains"
      )
      try require(
        !group.suppliedFields.contains("addresses"),
        "check-only group \(group.id) must not contain addresses"
      )
      try require(
        !group.suppliedFields.contains("checks"),
        "check-only group \(group.id) must not contain route checks"
      )
      try require(
        !group.endpoints.isEmpty, "check-only group \(group.id).endpoints must not be empty")
      for endpoint in group.endpoints {
        try validateNonEmpty(endpoint.name, at: "group \(group.id).endpoint.name")
        try validateHostname(endpoint.host, at: "group \(group.id).endpoint.host")
        try require(
          (1...65_535).contains(endpoint.port),
          "group \(group.id).endpoint.port must be between 1 and 65535"
        )
      }
    }
  }

  private static func validateCheck(_ check: HTTPSCheck, groupID: String) throws {
    guard let components = URLComponents(string: check.url),
      components.scheme?.lowercased() == "https",
      components.host != nil
    else {
      throw error("group \(groupID) check URL must use HTTPS")
    }
    try require(
      !check.expectedStatuses.isEmpty,
      "group \(groupID) check expected_statuses must not be empty"
    )
    try requireUnique(check.expectedStatuses, label: "group \(groupID) expected status")
    for status in check.expectedStatuses {
      try require(
        (100...599).contains(status),
        "group \(groupID) expected status must be between 100 and 599"
      )
    }
  }

  private static func validateIdentifier(_ value: String, at location: String) throws {
    try validateNonEmpty(value, at: location)
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    try require(
      identifierPattern.firstMatch(in: value, range: range) != nil,
      "\(location) must use lowercase letters, digits, and hyphens"
    )
  }

  private static func validateHostname(_ hostname: String, at location: String) throws {
    try validateNonEmpty(hostname, at: location)
    let normalized = hostname.hasSuffix(".") ? String(hostname.dropLast()) : hostname
    let labels = normalized.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    let valid =
      normalized.utf8.count <= 253
      && labels.allSatisfy { label in
        let range = NSRange(label.startIndex..<label.endIndex, in: label)
        return hostnameLabelPattern.firstMatch(in: label, range: range) != nil
      }
    try require(valid, "\(location) contains invalid hostname \(hostname)")
  }

  private static func validateStringList(
    _ values: [String],
    at location: String,
    allowEmpty: Bool = false
  ) throws {
    if !allowEmpty {
      try require(!values.isEmpty, "\(location) must not be empty")
    }
    for value in values {
      try validateNonEmpty(value, at: location)
    }
    try requireUnique(values, label: location)
  }

  private static func validateNonEmpty(_ value: String, at location: String) throws {
    try require(!value.isEmpty, "\(location) must not be empty")
    try require(
      value == value.trimmingCharacters(in: .whitespacesAndNewlines),
      "\(location) must not have leading or trailing whitespace"
    )
  }

  private static func isIPv4(_ value: String) -> Bool {
    var address = in_addr()
    return value.withCString { inet_pton(AF_INET, $0, &address) } == 1
  }

  private static func requireUnique<T: Hashable>(_ values: [T], label: String) throws {
    var seen = Set<T>()
    for value in values where !seen.insert(value).inserted {
      throw error("duplicate \(label): \(value)")
    }
  }

  private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw error(message) }
  }

  private static func error(_ message: String) -> ConfigurationValidationError {
    ConfigurationValidationError(message: message)
  }
}
