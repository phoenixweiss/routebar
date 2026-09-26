import Foundation

public protocol RouteBarDaemonTransport: Sendable {
  func send(_ request: RouteBarDaemonRequest) async throws -> RouteBarDaemonResponse
}

public enum RouteBarDaemonClientError: Error, LocalizedError, Equatable {
  case unexpectedResponse

  public var errorDescription: String? {
    switch self {
    case .unexpectedResponse:
      "The daemon returned an unexpected response"
    }
  }
}

public struct RouteBarDaemonClient: Sendable {
  private let transport: any RouteBarDaemonTransport

  public init(transport: any RouteBarDaemonTransport) {
    self.transport = transport
  }

  public func version() async throws -> RouteBarDaemonVersion {
    guard case .version(let version) = try await transport.send(.version) else {
      throw RouteBarDaemonClientError.unexpectedResponse
    }
    return version
  }

  public func status() async throws -> RouteBarDaemonStatus {
    guard case .status(let status) = try await transport.send(.status) else {
      throw RouteBarDaemonClientError.unexpectedResponse
    }
    return status
  }

  public func configure(profileID: String) async throws -> String {
    guard
      case .configured(let configuredProfileID) = try await transport.send(
        .configure(profileID: profileID)
      ),
      configuredProfileID == profileID
    else {
      throw RouteBarDaemonClientError.unexpectedResponse
    }
    return configuredProfileID
  }

  public func reconcile() async throws -> RouteBarDaemonOperationResult {
    guard case .reconciled(let result) = try await transport.send(.reconcile) else {
      throw RouteBarDaemonClientError.unexpectedResponse
    }
    return result
  }

  public func cleanup() async throws -> RouteBarDaemonOperationResult {
    guard case .cleanedUp(let result) = try await transport.send(.cleanup) else {
      throw RouteBarDaemonClientError.unexpectedResponse
    }
    return result
  }
}
