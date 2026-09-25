import Foundation

public struct ObservedRoute: Sendable, Equatable {
  public let destination: String
  public let gateway: String?
  public let interface: String?
  public let flags: Set<String>

  public init(
    destination: String,
    gateway: String?,
    interface: String?,
    flags: Set<String>
  ) {
    self.destination = destination
    self.gateway = gateway
    self.interface = interface
    self.flags = flags
  }

  public func isExplicitStaticHostRoute(for address: String) -> Bool {
    destination == address && flags.contains("HOST") && flags.contains("STATIC")
  }
}

public struct RouteInspectionError: LocalizedError, Equatable {
  public let message: String

  public var errorDescription: String? { message }
}

public protocol RouteInspecting {
  func route(to address: String) throws -> ObservedRoute
}

public enum RouteGetParser {
  public static func parse(_ output: String) throws -> ObservedRoute {
    var values = [String: String]()
    for line in output.split(whereSeparator: \.isNewline) {
      let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts.count == 2 else { continue }
      values[String(parts[0]).trimmingCharacters(in: .whitespaces)] =
        String(parts[1]).trimmingCharacters(in: .whitespaces)
    }

    guard let destination = values["destination"] else {
      throw RouteInspectionError(message: "route output does not contain a destination")
    }
    let flags = Set(
      values["flags", default: ""]
        .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    )
    return ObservedRoute(
      destination: destination,
      gateway: values["gateway"],
      interface: values["interface"],
      flags: flags
    )
  }
}

public struct SystemRouteInspector: RouteInspecting {
  public init() {}

  public func route(to address: String) throws -> ObservedRoute {
    let result = try FixedCommand.run("/sbin/route", arguments: ["-n", "get", address])
    guard result.status == 0 else {
      throw RouteInspectionError(message: "could not inspect route to \(address)")
    }
    return try RouteGetParser.parse(result.standardOutput)
  }
}
