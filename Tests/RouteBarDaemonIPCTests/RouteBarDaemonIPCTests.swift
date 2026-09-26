import Foundation
import Security
import XCTest

@testable import RouteBarDaemonIPC

final class RouteBarDaemonIPCTests: XCTestCase {
  func testFoundationAcceptsTheXPCServiceProtocol() {
    _ = NSXPCInterface(with: RouteBarDaemonXPCServiceProtocol.self)
  }

  func testWireCodecRoundTripsEveryRequest() throws {
    let requests: [RouteBarDaemonRequest] = [
      .version,
      .status,
      .configure(profileID: "work"),
      .reconcile,
      .cleanup,
    ]

    for request in requests {
      let data = try RouteBarDaemonWireCodec.encode(request)
      XCTAssertEqual(try RouteBarDaemonWireCodec.decodeRequest(from: data), request)
    }
  }

  func testWireCodecRoundTripsEveryResponse() throws {
    let result = RouteBarDaemonOperationResult(
      changedRouteCount: 1,
      activeRouteCount: 2,
      conflictCount: 0
    )
    let responses: [RouteBarDaemonResponse] = [
      .version(RouteBarDaemonVersion(helperVersion: "1.0.0")),
      .status(
        RouteBarDaemonStatus(
          helperVersion: "1.0.0",
          configuredProfileID: "work"
        )
      ),
      .configured(profileID: "work"),
      .reconciled(result),
      .cleanedUp(result),
    ]

    for response in responses {
      let data = try RouteBarDaemonWireCodec.encode(response)
      XCTAssertEqual(try RouteBarDaemonWireCodec.decodeResponse(from: data), response)
    }
  }

  func testWireCodecRejectsUnsupportedProtocolVersion() throws {
    let encoded = try RouteBarDaemonWireCodec.encode(RouteBarDaemonRequest.status)
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object["protocolVersion"] = RouteBarDaemonProtocolVersion.current + 1
    let incompatible = try JSONSerialization.data(withJSONObject: object)

    XCTAssertThrowsError(try RouteBarDaemonWireCodec.decodeRequest(from: incompatible)) {
      XCTAssertEqual(
        $0 as? RouteBarDaemonWireCodecError,
        .unsupportedProtocolVersion(
          received: RouteBarDaemonProtocolVersion.current + 1,
          supported: RouteBarDaemonProtocolVersion.current
        )
      )
    }
  }

  func testClientUsesOnlyTypedRequests() async throws {
    let routeResult = RouteBarDaemonOperationResult(
      changedRouteCount: 1,
      activeRouteCount: 1,
      conflictCount: 0
    )
    let transport = FakeDaemonTransport(
      responses: [
        .version(RouteBarDaemonVersion(helperVersion: "1.0.0")),
        .status(
          RouteBarDaemonStatus(
            helperVersion: "1.0.0",
            configuredProfileID: nil
          )
        ),
        .configured(profileID: "work"),
        .reconciled(routeResult),
        .cleanedUp(routeResult),
      ]
    )
    let client = RouteBarDaemonClient(transport: transport)

    _ = try await client.version()
    _ = try await client.status()
    _ = try await client.configure(profileID: "work")
    _ = try await client.reconcile()
    _ = try await client.cleanup()

    let requests = await transport.requests
    XCTAssertEqual(
      requests,
      [.version, .status, .configure(profileID: "work"), .reconcile, .cleanup]
    )
  }

  func testClientRejectsResponseForAnotherOperation() async throws {
    let transport = FakeDaemonTransport(
      responses: [.version(RouteBarDaemonVersion(helperVersion: "1.0.0"))]
    )
    let client = RouteBarDaemonClient(transport: transport)

    do {
      _ = try await client.status()
      XCTFail("Expected the client to reject the response")
    } catch {
      XCTAssertEqual(error as? RouteBarDaemonClientError, .unexpectedResponse)
    }
  }

  func testClientRejectsConfigurationForAnotherProfile() async throws {
    let transport = FakeDaemonTransport(
      responses: [.configured(profileID: "home")]
    )
    let client = RouteBarDaemonClient(transport: transport)

    do {
      _ = try await client.configure(profileID: "work")
      XCTFail("Expected the client to reject the profile mismatch")
    } catch {
      XCTAssertEqual(error as? RouteBarDaemonClientError, .unexpectedResponse)
    }
  }

  func testReadOnlyHandlerReturnsVersionAndUnconfiguredStatus() throws {
    let handler = RouteBarDaemonReadOnlyHandler(helperVersion: "1.2.3")

    XCTAssertEqual(
      try handler.response(for: .version),
      .version(RouteBarDaemonVersion(helperVersion: "1.2.3"))
    )
    XCTAssertEqual(
      try handler.response(for: .status),
      .status(
        RouteBarDaemonStatus(
          helperVersion: "1.2.3",
          configuredProfileID: nil
        )
      )
    )
  }

  func testReadOnlyHandlerRejectsEveryMutatingRequest() {
    let handler = RouteBarDaemonReadOnlyHandler(helperVersion: "1.2.3")
    let requests: [RouteBarDaemonRequest] = [
      .configure(profileID: "work"),
      .reconcile,
      .cleanup,
    ]

    for request in requests {
      XCTAssertThrowsError(try handler.response(for: request)) {
        XCTAssertEqual(
          $0 as? RouteBarDaemonServiceError,
          .operationUnavailableInReadOnlyService
        )
      }
    }
  }

  func testRealXPCTransportReadsVersionAndStatusFromAnonymousListener() async throws {
    let listener = NSXPCListener.anonymous()
    let delegate = RouteBarDaemonXPCListenerDelegate(
      handler: RouteBarDaemonReadOnlyHandler(helperVersion: "1.2.3"),
      clientAuthenticator: AcceptingClientAuthenticator()
    )
    listener.delegate = delegate
    listener.resume()
    defer { listener.invalidate() }

    let client = RouteBarDaemonClient(
      transport: RouteBarDaemonXPCTransport(listenerEndpoint: listener.endpoint)
    )

    let version = try await client.version()
    let status = try await client.status()

    XCTAssertEqual(version, RouteBarDaemonVersion(helperVersion: "1.2.3"))
    XCTAssertEqual(
      status,
      RouteBarDaemonStatus(
        helperVersion: "1.2.3",
        configuredProfileID: nil
      )
    )
  }

  func testRealXPCTransportCannotInvokeMutation() async throws {
    let listener = NSXPCListener.anonymous()
    let delegate = RouteBarDaemonXPCListenerDelegate(
      handler: RouteBarDaemonReadOnlyHandler(helperVersion: "1.2.3"),
      clientAuthenticator: AcceptingClientAuthenticator()
    )
    listener.delegate = delegate
    listener.resume()
    defer { listener.invalidate() }

    let transport = RouteBarDaemonXPCTransport(listenerEndpoint: listener.endpoint)

    do {
      _ = try await transport.send(.reconcile)
      XCTFail("Expected the read-only service to reject reconciliation")
    } catch let error as RouteBarDaemonXPCTransportError {
      guard case .remoteFailure(_, let message) = error else {
        return XCTFail("Expected a remote service error, got \(error)")
      }
      XCTAssertEqual(message, "This daemon endpoint is read-only")
    }
  }

  func testRealXPCTransportTimesOutWhenTheServiceDoesNotReply() async throws {
    let listener = NSXPCListener.anonymous()
    let delegate = NoReplyXPCListenerDelegate()
    listener.delegate = delegate
    listener.resume()
    defer { listener.invalidate() }

    let transport = RouteBarDaemonXPCTransport(
      listenerEndpoint: listener.endpoint,
      timeout: 0.05
    )

    do {
      _ = try await transport.send(.version)
      XCTFail("Expected the request to time out")
    } catch {
      XCTAssertEqual(
        error as? RouteBarDaemonXPCTransportError,
        .requestTimedOut
      )
    }
  }

  func testCodeSigningRequirementFindsAnEnclosingApplication() throws {
    let executableURL = URL(
      fileURLWithPath: "/Applications/RouteBar.app/Contents/Resources/routebar-daemon"
    )

    XCTAssertEqual(
      try RouteBarCodeSigningRequirement.enclosingApplicationURL(
        forExecutableURL: executableURL
      ).path,
      "/Applications/RouteBar.app"
    )
  }

  func testCodeSigningRequirementFailsClosedOutsideAnApplication() {
    XCTAssertThrowsError(
      try RouteBarCodeSigningRequirement.enclosingApplicationURL(
        forExecutableURL: URL(fileURLWithPath: "/usr/local/bin/routebar-daemon")
      )
    ) {
      XCTAssertEqual(
        $0 as? RouteBarCodeSigningRequirementError,
        .applicationBundleNotFound
      )
    }
  }

  func testCodeSigningRequirementRejectsInvalidSyntax() {
    XCTAssertThrowsError(
      try RouteBarDaemonCodeSigningAuthenticator(requirement: "not a requirement")
    )
  }

  func testListenerRejectsConnectionWhenAuthenticatorRejectsClient() async throws {
    let listener = NSXPCListener.anonymous()
    let delegate = RouteBarDaemonXPCListenerDelegate(
      handler: RouteBarDaemonReadOnlyHandler(helperVersion: "1.2.3"),
      clientAuthenticator: RejectingClientAuthenticator()
    )
    listener.delegate = delegate
    listener.resume()
    defer { listener.invalidate() }

    let transport = RouteBarDaemonXPCTransport(
      listenerEndpoint: listener.endpoint,
      timeout: 0.2
    )

    do {
      _ = try await transport.send(.version)
      XCTFail("Expected the listener to reject the client")
    } catch {
      XCTAssertNotNil(error as? RouteBarDaemonXPCTransportError)
    }
  }

  func testCodeSigningAuthenticatorAcceptsTheMatchingPeer() async throws {
    let requirement = try RouteBarCodeSigningRequirement.designatedRequirement(
      forCodeAt: currentProcessCodeURL()
    )
    let listener = NSXPCListener.anonymous()
    let delegate = RouteBarDaemonXPCListenerDelegate(
      handler: RouteBarDaemonReadOnlyHandler(helperVersion: "1.2.3"),
      clientAuthenticator: try RouteBarDaemonCodeSigningAuthenticator(
        requirement: requirement
      )
    )
    listener.delegate = delegate
    listener.resume()
    defer { listener.invalidate() }

    let client = RouteBarDaemonClient(
      transport: RouteBarDaemonXPCTransport(
        listenerEndpoint: listener.endpoint,
        timeout: 0.5
      )
    )

    let version = try await client.version()
    XCTAssertEqual(version, RouteBarDaemonVersion(helperVersion: "1.2.3"))
  }

  func testCodeSigningAuthenticatorRejectsAnotherIdentity() async throws {
    let listener = NSXPCListener.anonymous()
    let delegate = RouteBarDaemonXPCListenerDelegate(
      handler: RouteBarDaemonReadOnlyHandler(helperVersion: "1.2.3"),
      clientAuthenticator: try RouteBarDaemonCodeSigningAuthenticator(
        requirement: "identifier \"io.github.phoenixweiss.routebar.untrusted-test\""
      )
    )
    listener.delegate = delegate
    listener.resume()
    defer { listener.invalidate() }

    let transport = RouteBarDaemonXPCTransport(
      listenerEndpoint: listener.endpoint,
      timeout: 0.5
    )

    do {
      _ = try await transport.send(.version)
      XCTFail("Expected the code-signing requirement to reject another identity")
    } catch {
      XCTAssertNotNil(error as? RouteBarDaemonXPCTransportError)
    }
  }

  private func currentProcessCodeURL() throws -> URL {
    var code: SecCode?
    XCTAssertEqual(SecCodeCopySelf([], &code), errSecSuccess)
    let unwrappedCode = try XCTUnwrap(code)
    var staticCode: SecStaticCode?
    XCTAssertEqual(
      SecCodeCopyStaticCode(unwrappedCode, [], &staticCode),
      errSecSuccess
    )
    var url: CFURL?
    XCTAssertEqual(
      SecCodeCopyPath(try XCTUnwrap(staticCode), [], &url),
      errSecSuccess
    )
    return try XCTUnwrap(url as URL?)
  }
}

private actor FakeDaemonTransport: RouteBarDaemonTransport {
  private(set) var requests: [RouteBarDaemonRequest] = []
  private var responses: [RouteBarDaemonResponse]

  init(responses: [RouteBarDaemonResponse]) {
    self.responses = responses
  }

  func send(_ request: RouteBarDaemonRequest) async throws -> RouteBarDaemonResponse {
    requests.append(request)
    return responses.removeFirst()
  }
}

private struct AcceptingClientAuthenticator: RouteBarDaemonClientAuthenticating {
  func authenticate(_ connection: NSXPCConnection) -> Bool { true }
}

private struct RejectingClientAuthenticator: RouteBarDaemonClientAuthenticating {
  func authenticate(_ connection: NSXPCConnection) -> Bool { false }
}

private final class NoReplyXPCService: NSObject, RouteBarDaemonXPCServiceProtocol {
  func perform(
    _ requestData: Data,
    withReply reply: @escaping (Data?, NSError?) -> Void
  ) {}
}

private final class NoReplyXPCListenerDelegate: NSObject, NSXPCListenerDelegate {
  func listener(
    _ listener: NSXPCListener,
    shouldAcceptNewConnection connection: NSXPCConnection
  ) -> Bool {
    connection.exportedInterface = NSXPCInterface(
      with: RouteBarDaemonXPCServiceProtocol.self
    )
    connection.exportedObject = NoReplyXPCService()
    connection.resume()
    return true
  }
}
