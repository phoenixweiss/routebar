import Dispatch
import Foundation

public enum RouteBarDaemonXPCTransportError: Error, LocalizedError, Equatable {
  case connectionInterrupted
  case connectionInvalidated
  case requestTimedOut
  case invalidRemoteProxy
  case invalidReply
  case remoteFailure(code: Int, message: String)

  public var errorDescription: String? {
    switch self {
    case .connectionInterrupted:
      "The daemon connection was interrupted"
    case .connectionInvalidated:
      "The daemon connection is unavailable"
    case .requestTimedOut:
      "The daemon did not respond in time"
    case .invalidRemoteProxy:
      "The daemon connection does not expose the expected interface"
    case .invalidReply:
      "The daemon returned an invalid reply"
    case .remoteFailure(_, let message):
      message
    }
  }
}

public final class RouteBarDaemonXPCTransport: RouteBarDaemonTransport, @unchecked Sendable {
  public static let machServiceName = "io.github.phoenixweiss.routebar"

  private enum Destination {
    case machService(String)
    case listenerEndpoint(NSXPCListenerEndpoint)
  }

  private let destination: Destination
  private let timeout: TimeInterval

  public init(
    machServiceName: String = RouteBarDaemonXPCTransport.machServiceName,
    timeout: TimeInterval = 2
  ) {
    destination = .machService(machServiceName)
    self.timeout = timeout
  }

  public init(listenerEndpoint: NSXPCListenerEndpoint, timeout: TimeInterval = 2) {
    destination = .listenerEndpoint(listenerEndpoint)
    self.timeout = timeout
  }

  public func send(_ request: RouteBarDaemonRequest) async throws -> RouteBarDaemonResponse {
    let requestData = try RouteBarDaemonWireCodec.encode(request)
    let connection = makeConnection()
    let connectionBox = RouteBarXPCConnectionBox(connection)
    connection.remoteObjectInterface = NSXPCInterface(
      with: RouteBarDaemonXPCServiceProtocol.self
    )

    return try await withCheckedThrowingContinuation { continuation in
      let reply = RouteBarDaemonXPCReply(continuation: continuation)
      connection.interruptionHandler = {
        reply.finish(.failure(RouteBarDaemonXPCTransportError.connectionInterrupted))
      }
      connection.invalidationHandler = {
        reply.finish(.failure(RouteBarDaemonXPCTransportError.connectionInvalidated))
      }
      DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
        if reply.finish(.failure(RouteBarDaemonXPCTransportError.requestTimedOut)) {
          connectionBox.connection.invalidate()
        }
      }
      connection.resume()

      let proxy = connection.remoteObjectProxyWithErrorHandler { error in
        if reply.finish(
          .failure(
            RouteBarDaemonXPCTransportError.remoteFailure(
              code: error._code,
              message: error.localizedDescription
            )
          )
        ) {
          connection.invalidate()
        }
      }
      guard let service = proxy as? RouteBarDaemonXPCServiceProtocol else {
        reply.finish(.failure(RouteBarDaemonXPCTransportError.invalidRemoteProxy))
        connection.invalidate()
        return
      }

      service.perform(requestData) { responseData, error in
        defer { connection.invalidate() }
        if let error {
          reply.finish(
            .failure(
              RouteBarDaemonXPCTransportError.remoteFailure(
                code: error.code,
                message: error.localizedDescription
              )
            )
          )
          return
        }
        guard let responseData else {
          reply.finish(.failure(RouteBarDaemonXPCTransportError.invalidReply))
          return
        }
        do {
          reply.finish(
            .success(try RouteBarDaemonWireCodec.decodeResponse(from: responseData))
          )
        } catch {
          reply.finish(.failure(error))
        }
      }
    }
  }

  private func makeConnection() -> NSXPCConnection {
    switch destination {
    case .machService(let name):
      NSXPCConnection(machServiceName: name, options: .privileged)
    case .listenerEndpoint(let endpoint):
      NSXPCConnection(listenerEndpoint: endpoint)
    }
  }
}

private final class RouteBarDaemonXPCReply: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<RouteBarDaemonResponse, Error>?

  init(continuation: CheckedContinuation<RouteBarDaemonResponse, Error>) {
    self.continuation = continuation
  }

  @discardableResult
  func finish(_ result: Result<RouteBarDaemonResponse, Error>) -> Bool {
    lock.lock()
    guard let continuation else {
      lock.unlock()
      return false
    }
    self.continuation = nil
    lock.unlock()
    continuation.resume(with: result)
    return true
  }
}

private final class RouteBarXPCConnectionBox: @unchecked Sendable {
  let connection: NSXPCConnection

  init(_ connection: NSXPCConnection) {
    self.connection = connection
  }
}
