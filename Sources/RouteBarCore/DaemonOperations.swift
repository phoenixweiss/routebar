import Foundation

public struct RouteBarDaemonOperationSummary: Sendable, Equatable {
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

public struct RouteBarDaemonOperationError: LocalizedError, Equatable {
  public let message: String

  public var errorDescription: String? { message }
}

public protocol RouteBarRouteReconciliationRunning: Sendable {
  func apply(routePlan: RoutePlan) throws -> ReconciliationResult
  func cleanup() throws -> ReconciliationResult
}

public struct SystemRouteBarRouteReconciliationRunner: RouteBarRouteReconciliationRunning {
  public static let stateURL = URL(fileURLWithPath: "/var/db/routebar/state.json")

  public init() {}

  public func apply(routePlan: RoutePlan) throws -> ReconciliationResult {
    try service.apply(routePlan: routePlan)
  }

  public func cleanup() throws -> ReconciliationResult {
    try service.cleanup()
  }

  private var service: RouteReconciliationService {
    RouteReconciliationService(
      stateStore: FileRouteStateStore(url: Self.stateURL)
    )
  }
}

public actor RouteBarDaemonOperationService {
  private let configurationService: RouteBarDaemonConfigurationService
  private let reconciliationRunner: any RouteBarRouteReconciliationRunning
  private var operationInProgress = false

  public init(
    configurationService: RouteBarDaemonConfigurationService,
    reconciliationRunner: any RouteBarRouteReconciliationRunning =
      SystemRouteBarRouteReconciliationRunner()
  ) {
    self.configurationService = configurationService
    self.reconciliationRunner = reconciliationRunner
  }

  public func configure(clientUID: UInt32, profileID: String) async throws
    -> RouteBarDaemonSettings
  {
    try beginOperation()
    defer { endOperation() }
    return try await configurationService.configure(
      clientUID: clientUID,
      profileID: profileID
    )
  }

  public func reconcile(clientUID: UInt32) async throws -> RouteBarDaemonOperationSummary {
    try beginOperation()
    defer { endOperation() }
    _ = try await configurationService.requireOwner(clientUID)
    let summary = try await reconcileConfiguredRoutes()
    if summary.conflictCount == 0 {
      try await configurationService.setAutomaticReconciliationEnabled(true)
    }
    return summary
  }

  public func reconcileAutomatically() async throws -> RouteBarDaemonOperationSummary? {
    guard !operationInProgress else { return nil }
    operationInProgress = true
    defer { endOperation() }
    guard let settings = try await configurationService.settings(),
      settings.automaticReconciliationEnabled
    else { return nil }
    return try await reconcileConfiguredRoutes()
  }

  public func cleanup(clientUID: UInt32) async throws -> RouteBarDaemonOperationSummary {
    try beginOperation()
    defer { endOperation() }
    _ = try await configurationService.requireOwner(clientUID)
    try await configurationService.setAutomaticReconciliationEnabled(false)
    let result = try reconciliationRunner.cleanup()
    return Self.summary(result)
  }

  private func reconcileConfiguredRoutes() async throws -> RouteBarDaemonOperationSummary {
    let routePlan = try await configurationService.routePlan()
    return Self.summary(try reconciliationRunner.apply(routePlan: routePlan))
  }

  private func beginOperation() throws {
    guard !operationInProgress else {
      throw RouteBarDaemonOperationError(
        message: "another route operation is already in progress"
      )
    }
    operationInProgress = true
  }

  private func endOperation() {
    operationInProgress = false
  }

  private static func summary(_ result: ReconciliationResult) -> RouteBarDaemonOperationSummary {
    RouteBarDaemonOperationSummary(
      changedRouteCount: result.plan.actions.count,
      activeRouteCount: result.state.routes.count,
      conflictCount: result.plan.conflicts.count
    )
  }
}
