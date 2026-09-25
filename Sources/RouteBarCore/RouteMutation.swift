import Foundation

public struct RouteMutationError: LocalizedError, Equatable {
  public let message: String

  public var errorDescription: String? { message }
}

public protocol RouteMutating {
  func addHostRoute(address: String, gateway: String) throws
  func deleteHostRoute(address: String, gateway: String) throws
}

public struct SystemRouteMutator: RouteMutating {
  public init() {}

  public func addHostRoute(address: String, gateway: String) throws {
    try mutate("add", address: address, gateway: gateway)
  }

  public func deleteHostRoute(address: String, gateway: String) throws {
    try mutate("delete", address: address, gateway: gateway)
  }

  private func mutate(_ operation: String, address: String, gateway: String) throws {
    let result = try FixedCommand.run(
      "/sbin/route",
      arguments: ["-n", operation, "-host", address, gateway]
    )
    guard result.status == 0 else {
      let detail = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
      throw RouteMutationError(
        message: "route \(operation) failed for \(address) via \(gateway)"
          + (detail.isEmpty ? "" : ": \(detail)")
      )
    }
  }
}
