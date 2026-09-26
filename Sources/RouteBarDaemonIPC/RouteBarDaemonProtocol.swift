import Foundation

public enum RouteBarDaemonProtocolVersion {
  public static let current = 3
}

public enum RouteBarDaemonRequest: Codable, Sendable, Equatable {
  case version
  case status
  case configure(profileID: String)
  case reconcile
  case cleanup
}

public struct RouteBarDaemonVersion: Codable, Sendable, Equatable {
  public let helperVersion: String
  public let protocolVersion: Int

  public init(
    helperVersion: String,
    protocolVersion: Int = RouteBarDaemonProtocolVersion.current
  ) {
    self.helperVersion = helperVersion
    self.protocolVersion = protocolVersion
  }
}

public struct RouteBarDaemonStatus: Codable, Sendable, Equatable {
  public let helperVersion: String
  public let configuredProfileID: String?
  public let automaticReconciliationEnabled: Bool
  public let lastReconciliationAttemptAt: Date?
  public let lastSuccessfulReconciliationAt: Date?
  public let lastReconciliationResult: RouteBarDaemonOperationResult?
  public let lastError: String?
  public let configurationRequiresReload: Bool?

  public init(
    helperVersion: String,
    configuredProfileID: String?,
    automaticReconciliationEnabled: Bool = false,
    lastReconciliationAttemptAt: Date? = nil,
    lastSuccessfulReconciliationAt: Date? = nil,
    lastReconciliationResult: RouteBarDaemonOperationResult? = nil,
    lastError: String? = nil,
    configurationRequiresReload: Bool? = nil
  ) {
    self.helperVersion = helperVersion
    self.configuredProfileID = configuredProfileID
    self.automaticReconciliationEnabled = automaticReconciliationEnabled
    self.lastReconciliationAttemptAt = lastReconciliationAttemptAt
    self.lastSuccessfulReconciliationAt = lastSuccessfulReconciliationAt
    self.lastReconciliationResult = lastReconciliationResult
    self.lastError = lastError
    self.configurationRequiresReload = configurationRequiresReload
  }
}

public struct RouteBarDaemonOperationResult: Codable, Sendable, Equatable {
  public let changedRouteCount: Int
  public let activeRouteCount: Int
  public let conflictCount: Int

  public init(
    changedRouteCount: Int,
    activeRouteCount: Int,
    conflictCount: Int
  ) {
    self.changedRouteCount = changedRouteCount
    self.activeRouteCount = activeRouteCount
    self.conflictCount = conflictCount
  }
}

public enum RouteBarDaemonResponse: Codable, Sendable, Equatable {
  case version(RouteBarDaemonVersion)
  case status(RouteBarDaemonStatus)
  case configured(profileID: String)
  case reconciled(RouteBarDaemonOperationResult)
  case cleanedUp(RouteBarDaemonOperationResult)
}

@objc(RouteBarDaemonXPCServiceProtocol)
public protocol RouteBarDaemonXPCServiceProtocol {
  func perform(
    _ requestData: Data,
    withReply reply: @escaping (Data?, NSError?) -> Void
  )
}
