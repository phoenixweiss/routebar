import Foundation
import Network
import XCTest

@testable import RouteBarCore

final class HTTPSConnectivityTests: XCTestCase {
  func testMalformedHeadersHaveTheirOwnOutcome() throws {
    let context = LocalHTTPContext(reply: "HTTP/1.1 200 OK\r\nInvalid header\r\n\r\n")
    let server = try LocalTLSServer(connectionHandler: context.accept)
    defer { server.stop() }
    XCTAssertEqual(
      HTTPSProbe(testAnchors: [server.ca]).check(check(server)).outcome, .protocolFailure)
  }

  func testEncodedPathAndQueryCannotBecomeRequestHeaders() throws {
    let context = LocalHTTPContext(reply: "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
    let server = try LocalTLSServer(connectionHandler: context.accept)
    defer { server.stop() }
    let target = "/some%20path?q=a%0D%0AInjected%3A%20x"
    let check = HTTPSCheck(
      url: "https://localhost:\(server.port)\(target)", expectedStatuses: [200])
    XCTAssertEqual(HTTPSProbe(testAnchors: [server.ca]).check(check).outcome, .reachable)
    let request = try XCTUnwrap(context.requests.first)
    XCTAssertTrue(request.hasPrefix("HEAD \(target) HTTP/1.1\r\n"))
    XCTAssertTrue(request.contains("\r\nHost: localhost:\(server.port)\r\n"))
    XCTAssertFalse(request.contains("\r\nInjected:"))
  }

  func testExpectedAndUnexpectedStatusesWithoutWaitingForBody() throws {
    let context = LocalHTTPContext(reply: "HTTP/1.1 200 OK\r\nContent-Length: 1000000\r\n\r\n")
    let server = try LocalTLSServer(connectionHandler: context.accept)
    defer { server.stop() }
    let probe = HTTPSProbe(testAnchors: [server.ca])
    XCTAssertEqual(
      probe.check(check(server)), HTTPSProbeResult(outcome: .reachable, statusCode: 200))
    XCTAssertEqual(
      probe.check(check(server, statuses: [204])),
      HTTPSProbeResult(outcome: .unexpectedStatus, statusCode: 200))
    XCTAssertEqual(context.requests.count, 2)
    XCTAssertTrue(context.requests.allSatisfy { $0.hasPrefix("HEAD /health HTTP/1.1\r\n") })
    XCTAssertTrue(
      context.requests.allSatisfy {
        !$0.lowercased().contains("authorization:") && !$0.lowercased().contains("cookie:")
      })
  }

  func testRedirectIsReportedAndNeverFollowed() throws {
    let targetContext = LocalHTTPContext(reply: "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
    let target = try LocalTLSServer(connectionHandler: targetContext.accept)
    defer { target.stop() }
    let context = LocalHTTPContext(
      reply:
        "HTTP/1.1 302 Found\r\nLocation: https://localhost:\(target.port)/target\r\nContent-Length: 0\r\n\r\n"
    )
    let server = try LocalTLSServer(connectionHandler: context.accept)
    defer { server.stop() }
    XCTAssertEqual(
      HTTPSProbe(testAnchors: [server.ca, target.ca]).check(check(server, statuses: [302])),
      HTTPSProbeResult(outcome: .reachable, statusCode: 302))
    XCTAssertEqual(context.requests.count, 1)
    XCTAssertTrue(targetContext.requests.isEmpty)
  }

  func testUnsupportedHEADDoesNotTriggerGETFallback() throws {
    let context = LocalHTTPContext(
      reply: "HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\n\r\n")
    let server = try LocalTLSServer(connectionHandler: context.accept)
    defer { server.stop() }
    XCTAssertEqual(
      HTTPSProbe(testAnchors: [server.ca]).check(check(server)),
      HTTPSProbeResult(outcome: .unexpectedStatus, statusCode: 405))
    XCTAssertEqual(context.requests.count, 1)
    XCTAssertTrue(context.requests[0].hasPrefix("HEAD "))
  }

  func testAuthenticationIsNotAttemptedAnd401CanBeExpected() throws {
    let context = LocalHTTPContext(
      reply:
        "HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic realm=\"Local\"\r\nContent-Length: 0\r\n\r\n"
    )
    let server = try LocalTLSServer(connectionHandler: context.accept)
    defer { server.stop() }
    XCTAssertEqual(
      HTTPSProbe(testAnchors: [server.ca]).check(check(server, statuses: [401])),
      HTTPSProbeResult(outcome: .reachable, statusCode: 401))
    XCTAssertEqual(context.requests.count, 1)
    XCTAssertFalse(context.requests.joined().lowercased().contains("authorization:"))
  }

  func testCookiesAreNotReusedBetweenChecks() throws {
    let context = LocalHTTPContext(
      reply:
        "HTTP/1.1 200 OK\r\nSet-Cookie: sample=fictional; Secure; Path=/\r\nContent-Length: 0\r\n\r\n"
    )
    let server = try LocalTLSServer(connectionHandler: context.accept)
    defer { server.stop() }
    let probe = HTTPSProbe(testAnchors: [server.ca])
    for _ in 0..<2 { XCTAssertEqual(probe.check(check(server)).outcome, .reachable) }
    XCTAssertEqual(context.requests.count, 2)
    XCTAssertFalse(context.requests.joined().lowercased().contains("cookie:"))
  }

  func testCertificateFailuresAndHostnameMismatch() throws {
    for kind in 0..<3 {
      let context = LocalHTTPContext(reply: "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
      let server = try LocalTLSServer(expired: kind == 1, connectionHandler: context.accept)
      defer { server.stop() }
      let probe = kind == 0 ? HTTPSProbe() : HTTPSProbe(testAnchors: [server.ca])
      XCTAssertEqual(
        probe.check(check(server, host: kind == 2 ? "127.0.0.1" : "localhost")).outcome,
        .certificateFailure)
      XCTAssertTrue(context.requests.isEmpty)
    }
  }

  func testDeadlineWhileWaitingForHeaders() throws {
    let context = LocalHTTPContext(reply: nil)
    let server = try LocalTLSServer(connectionHandler: context.accept)
    defer { server.stop() }
    let start = Date()
    XCTAssertEqual(
      HTTPSProbe(testAnchors: [server.ca]).check(check(server, timeout: 0.2)).outcome, .timeout)
    XCTAssertLessThan(Date().timeIntervalSince(start), 2)
  }

  func testInvalidChecksAndErrorClassification() {
    for url in [
      "http://localhost/", "https://user:password@localhost/", "https://localhost/#fragment",
    ] {
      XCTAssertEqual(
        HTTPSProbe().check(HTTPSCheck(url: url, expectedStatuses: [200])).outcome, .invalidCheck)
    }
    XCTAssertEqual(
      HTTPSProbe().check(
        HTTPSCheck(url: "https://localhost/", expectedStatuses: [200], timeoutSeconds: .nan)
      ).outcome, .invalidCheck)
    XCTAssertEqual(HTTPSOutcome.classify(URLError(.dnsLookupFailed)), .dnsFailure)
    XCTAssertEqual(HTTPSOutcome.classify(URLError(.cannotConnectToHost)), .connectionFailure)
    XCTAssertEqual(HTTPSOutcome.classify(URLError(.secureConnectionFailed)), .handshakeFailure)
  }

  func testServiceKeepsHTTPStatusSeparateAndChecksOnlySelectedGroups() throws {
    let config = try ConfigurationLoader.load(source: validConfiguration)
    let probe = RecordingHTTPSProbe()
    let results = try HTTPSCheckService(probe: probe).check(
      configuration: config, profileID: "home")
    XCTAssertEqual(results.map(\.groupID), ["work"])
    XCTAssertEqual(results.map(\.result.statusCode), [503])
    XCTAssertThrowsError(
      try HTTPSCheckService(probe: probe).check(configuration: config, profileID: "missing"))
    XCTAssertEqual(probe.checks.count, 1)
    let only = try ConfigurationLoader.load(source: httpsOnlyConfiguration)
    XCTAssertEqual(
      try HTTPSCheckService(probe: probe).check(configuration: only, profileID: "home").map(
        \.groupID), ["status"])
  }

  private func check(
    _ server: LocalTLSServer, statuses: [Int] = [200], host: String = "localhost",
    timeout: Double = 3
  ) -> HTTPSCheck {
    HTTPSCheck(
      url: "https://\(host):\(server.port)/health", expectedStatuses: statuses,
      timeoutSeconds: timeout)
  }
}

private final class RecordingHTTPSProbe: HTTPSProbing {
  var checks: [HTTPSCheck] = []
  func check(_ check: HTTPSCheck) -> HTTPSProbeResult {
    checks.append(check)
    return HTTPSProbeResult(outcome: .unexpectedStatus, statusCode: 503)
  }
}

private final class LocalHTTPContext: @unchecked Sendable {
  let reply: String?
  private let lock = NSLock()
  private var recorded: [String] = []
  var requests: [String] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }
  init(reply: String?) { self.reply = reply }
  func accept(_ connection: NWConnection) { receive(connection, accumulated: Data()) }
  private func receive(_ connection: NWConnection, accumulated: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) {
      data, _, complete, error in
      var request = accumulated
      if let data { request.append(data) }
      if request.range(of: Data("\r\n\r\n".utf8)) != nil {
        self.lock.lock()
        self.recorded.append(String(decoding: request, as: UTF8.self))
        self.lock.unlock()
        if let reply = self.reply {
          connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in })
        }
      } else if !complete && error == nil && request.count < 16_384 {
        self.receive(connection, accumulated: request)
      } else {
        connection.cancel()
      }
    }
  }
}
