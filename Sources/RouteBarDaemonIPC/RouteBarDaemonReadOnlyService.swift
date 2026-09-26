import Foundation
import RouteBarCore

public enum RouteBarDaemonServiceError: Error, LocalizedError, Equatable {
  case operationUnavailableInReadOnlyService

  public var errorDescription: String? {
    switch self {
    case .operationUnavailableInReadOnlyService:
      "This daemon endpoint is read-only"
    }
  }
}

public protocol RouteBarDaemonRequestHandling: Sendable {
  func response(for request: RouteBarDaemonRequest) async throws -> RouteBarDaemonResponse
}

public struct RouteBarDaemonReadOnlyHandler: RouteBarDaemonRequestHandling {
  private let helperVersion: String

  public init(helperVersion: String) {
    self.helperVersion = helperVersion
  }

  public func response(for request: RouteBarDaemonRequest) async throws
    -> RouteBarDaemonResponse
  {
    switch request {
    case .version:
      return .version(RouteBarDaemonVersion(helperVersion: helperVersion))
    case .status:
      return .status(
        RouteBarDaemonStatus(
          helperVersion: helperVersion,
          configuredProfileID: nil,
          automaticReconciliationEnabled: false
        )
      )
    case .configure, .reconcile, .cleanup:
      throw RouteBarDaemonServiceError.operationUnavailableInReadOnlyService
    }
  }
}

public struct RouteBarDaemonConfiguredHandler: RouteBarDaemonRequestHandling {
  private let helperVersion: String
  private let clientUID: UInt32
  private let configurationService: RouteBarDaemonConfigurationService
  private let operationService: RouteBarDaemonOperationService

  public init(
    helperVersion: String,
    clientUID: UInt32,
    configurationService: RouteBarDaemonConfigurationService,
    operationService: RouteBarDaemonOperationService? = nil
  ) {
    self.helperVersion = helperVersion
    self.clientUID = clientUID
    self.configurationService = configurationService
    self.operationService =
      operationService
      ?? RouteBarDaemonOperationService(
        configurationService: configurationService
      )
  }

  public func response(for request: RouteBarDaemonRequest) async throws
    -> RouteBarDaemonResponse
  {
    switch request {
    case .version:
      return .version(RouteBarDaemonVersion(helperVersion: helperVersion))
    case .status:
      let settings = try await configurationService.settings()
      let diagnostics = await operationService.diagnostics()
      return .status(
        RouteBarDaemonStatus(
          helperVersion: helperVersion,
          configuredProfileID: settings?.profileID,
          automaticReconciliationEnabled:
            settings?.automaticReconciliationEnabled ?? false,
          lastReconciliationAttemptAt: diagnostics.lastAttemptAt,
          lastSuccessfulReconciliationAt: diagnostics.lastSuccessfulAt,
          lastReconciliationResult: diagnostics.lastResult.map(Self.response),
          lastError: diagnostics.lastError,
          configurationRequiresReload: diagnostics.configurationRequiresReload
        )
      )
    case .configure(let profileID):
      let settings = try await operationService.configure(
        clientUID: clientUID,
        profileID: profileID
      )
      return .configured(profileID: settings.profileID)
    case .reconcile:
      return .reconciled(
        Self.response(
          try await operationService.reconcile(clientUID: clientUID)
        )
      )
    case .cleanup:
      return .cleanedUp(
        Self.response(
          try await operationService.cleanup(clientUID: clientUID)
        )
      )
    }
  }

  private static func response(
    _ summary: RouteBarDaemonOperationSummary
  ) -> RouteBarDaemonOperationResult {
    RouteBarDaemonOperationResult(
      changedRouteCount: summary.changedRouteCount,
      activeRouteCount: summary.activeRouteCount,
      conflictCount: summary.conflictCount
    )
  }
}

public final class RouteBarDaemonXPCService: NSObject, RouteBarDaemonXPCServiceProtocol,
  @unchecked Sendable
{
  private let handler: any RouteBarDaemonRequestHandling

  public init(handler: any RouteBarDaemonRequestHandling) {
    self.handler = handler
  }

  public func perform(
    _ requestData: Data,
    withReply reply: @escaping (Data?, NSError?) -> Void
  ) {
    let replyBox = RouteBarDaemonXPCServiceReply(reply)
    let handler = handler
    Task {
      do {
        let request = try RouteBarDaemonWireCodec.decodeRequest(from: requestData)
        let response = try await handler.response(for: request)
        replyBox.call(try RouteBarDaemonWireCodec.encode(response), nil)
      } catch {
        replyBox.call(nil, Self.serviceError(error))
      }
    }
  }

  private static func serviceError(_ error: Error) -> NSError {
    let description = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    return NSError(
      domain: "io.github.phoenixweiss.routebar.daemon",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: description]
    )
  }
}

private final class RouteBarDaemonXPCServiceReply: @unchecked Sendable {
  private let reply: (Data?, NSError?) -> Void

  init(_ reply: @escaping (Data?, NSError?) -> Void) {
    self.reply = reply
  }

  func call(_ data: Data?, _ error: NSError?) {
    reply(data, error)
  }
}

public final class RouteBarDaemonXPCListenerDelegate: NSObject, NSXPCListenerDelegate,
  @unchecked Sendable
{
  private let handlerFactory: @Sendable (UInt32) -> any RouteBarDaemonRequestHandling
  private let clientAuthenticator: any RouteBarDaemonClientAuthenticating

  public init(
    handler: any RouteBarDaemonRequestHandling,
    clientAuthenticator: any RouteBarDaemonClientAuthenticating
  ) {
    handlerFactory = { _ in handler }
    self.clientAuthenticator = clientAuthenticator
  }

  public init(
    handlerFactory: @escaping @Sendable (UInt32) -> any RouteBarDaemonRequestHandling,
    clientAuthenticator: any RouteBarDaemonClientAuthenticating
  ) {
    self.handlerFactory = handlerFactory
    self.clientAuthenticator = clientAuthenticator
  }

  public func listener(
    _ listener: NSXPCListener,
    shouldAcceptNewConnection connection: NSXPCConnection
  ) -> Bool {
    guard clientAuthenticator.authenticate(connection) else { return false }
    let handler = handlerFactory(UInt32(connection.effectiveUserIdentifier))
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
