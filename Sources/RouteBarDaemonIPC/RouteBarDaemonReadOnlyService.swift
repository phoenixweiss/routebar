import Foundation

public enum RouteBarDaemonServiceError: Error, LocalizedError, Equatable {
  case operationUnavailableInReadOnlyService

  public var errorDescription: String? {
    switch self {
    case .operationUnavailableInReadOnlyService:
      "This daemon endpoint is read-only"
    }
  }
}

public struct RouteBarDaemonReadOnlyHandler: Sendable {
  private let helperVersion: String

  public init(helperVersion: String) {
    self.helperVersion = helperVersion
  }

  public func response(for request: RouteBarDaemonRequest) throws -> RouteBarDaemonResponse {
    switch request {
    case .version:
      return .version(RouteBarDaemonVersion(helperVersion: helperVersion))
    case .status:
      return .status(
        RouteBarDaemonStatus(
          helperVersion: helperVersion,
          configuredProfileID: nil
        )
      )
    case .configure, .reconcile, .cleanup:
      throw RouteBarDaemonServiceError.operationUnavailableInReadOnlyService
    }
  }
}

public final class RouteBarDaemonXPCService: NSObject, RouteBarDaemonXPCServiceProtocol,
  @unchecked Sendable
{
  private let handler: RouteBarDaemonReadOnlyHandler

  public init(handler: RouteBarDaemonReadOnlyHandler) {
    self.handler = handler
  }

  public func perform(
    _ requestData: Data,
    withReply reply: @escaping (Data?, NSError?) -> Void
  ) {
    do {
      let request = try RouteBarDaemonWireCodec.decodeRequest(from: requestData)
      let response = try handler.response(for: request)
      reply(try RouteBarDaemonWireCodec.encode(response), nil)
    } catch {
      reply(nil, serviceError(error))
    }
  }

  private func serviceError(_ error: Error) -> NSError {
    let description = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    return NSError(
      domain: "io.github.phoenixweiss.routebar.daemon",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: description]
    )
  }
}

public final class RouteBarDaemonXPCListenerDelegate: NSObject, NSXPCListenerDelegate,
  @unchecked Sendable
{
  private let handler: RouteBarDaemonReadOnlyHandler
  private let clientAuthenticator: any RouteBarDaemonClientAuthenticating

  public init(
    handler: RouteBarDaemonReadOnlyHandler,
    clientAuthenticator: any RouteBarDaemonClientAuthenticating
  ) {
    self.handler = handler
    self.clientAuthenticator = clientAuthenticator
  }

  public func listener(
    _ listener: NSXPCListener,
    shouldAcceptNewConnection connection: NSXPCConnection
  ) -> Bool {
    guard clientAuthenticator.authenticate(connection) else { return false }
    connection.exportedInterface = NSXPCInterface(
      with: RouteBarDaemonXPCServiceProtocol.self
    )
    connection.exportedObject = RouteBarDaemonXPCService(handler: handler)
    connection.resume()
    return true
  }
}

public protocol RouteBarDaemonClientAuthenticating: Sendable {
  func authenticate(_ connection: NSXPCConnection) -> Bool
}

public struct RouteBarDaemonCodeSigningAuthenticator: RouteBarDaemonClientAuthenticating {
  private let requirement: String

  public init(requirement: String) throws {
    try RouteBarCodeSigningRequirement.validate(requirement)
    self.requirement = requirement
  }

  public func authenticate(_ connection: NSXPCConnection) -> Bool {
    guard connection.effectiveUserIdentifier != 0 else { return false }
    connection.setCodeSigningRequirement(requirement)
    return true
  }
}
