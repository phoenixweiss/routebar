import Darwin
import Foundation
import Network
import XCTest

@testable import RouteBarCore

final class TCPConnectivityTests: XCTestCase {
  func testConnectsToLocalServerWithoutSendingApplicationData() throws {
    let listener = try NWListener(using: .tcp, on: .any)
    let ready = expectation(description: "Listener ready")
    let closed = expectation(description: "Client closes without data")
    listener.stateUpdateHandler = { state in
      if case .ready = state { ready.fulfill() }
    }
    listener.newConnectionHandler = { connection in
      connection.start(queue: DispatchQueue(label: "routebar.test.accept"))
      connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) {
        data, _, _, _ in
        XCTAssertTrue(data == nil || data?.isEmpty == true)
        closed.fulfill()
        connection.cancel()
      }
    }
    listener.start(queue: DispatchQueue(label: "routebar.test.listener"))
    defer { listener.cancel() }
    wait(for: [ready], timeout: 3)
    let port = try XCTUnwrap(listener.port)
    let endpoint = Endpoint(
      name: "Local", host: "127.0.0.1", port: Int(port.rawValue), protocol: .tcp)
    XCTAssertEqual(TCPProbe().check(endpoint), .reachable)
    wait(for: [closed], timeout: 3)
  }

  func testRefusedConnectionToClosedLocalPort() throws {
    // Reserve an ephemeral port, then close it before attempting the probe.
    let socketFD = socket(AF_INET, SOCK_STREAM, 0)
    XCTAssertGreaterThanOrEqual(socketFD, 0)
    guard socketFD >= 0 else { return }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bound == 0 else {
      close(socketFD)
      XCTFail("bind failed")
      return
    }
    var size = socklen_t(MemoryLayout<sockaddr_in>.size)
    let resolved = withUnsafeMutablePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socketFD, $0, &size) }
    }
    close(socketFD)
    XCTAssertEqual(resolved, 0)
    let endpoint = Endpoint(
      name: "Closed", host: "127.0.0.1", port: Int(UInt16(bigEndian: address.sin_port)),
      protocol: .tcp)
    XCTAssertEqual(TCPProbe().check(endpoint), .refused)
  }

  func testDeadlineIsBoundedAndLateCallbackCannotReplaceTimeout() {
    let completion = TCPCompletion()
    let start = Date()
    XCTAssertEqual(completion.wait(timeout: 0.02), .timeout)
    XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    completion.finish(.reachable)
    XCTAssertEqual(completion.wait(timeout: 0), .timeout)
  }

  func testFirstTerminalResultWins() {
    let completion = TCPCompletion()
    completion.finish(.refused)
    completion.finish(.reachable)
    XCTAssertEqual(completion.wait(timeout: 1), .refused)
  }

  func testErrorCategories() {
    XCTAssertEqual(TCPOutcome.classify(.dns(-65538)), .dnsFailure)
    XCTAssertEqual(TCPOutcome.classify(.posix(.ECONNREFUSED)), .refused)
    XCTAssertEqual(TCPOutcome.classify(.posix(.ENETUNREACH)), .unreachable)
    XCTAssertEqual(TCPOutcome.classify(.posix(.ETIMEDOUT)), .timeout)
    XCTAssertEqual(TCPOutcome.classify(.posix(.EINVAL)), .failed)
  }

  func testInvalidEndpointDoesNotAttemptConnection() {
    for timeout in [0, -1, .infinity, .nan, 31] {
      XCTAssertEqual(
        TCPProbe().check(
          Endpoint(
            name: "Invalid", host: "localhost", port: 80, protocol: .tcp,
            timeoutSeconds: timeout)), .invalidEndpoint)
    }
    XCTAssertEqual(
      TCPProbe().check(Endpoint(name: "Invalid", host: "localhost", port: 65536, protocol: .tcp)),
      .invalidEndpoint)
  }

  func testOnlySelectedCheckOnlyEndpointsAreProbed() throws {
    let configuration = try ConfigurationLoader.load(source: validConfiguration)
    let probe = RecordingProbe()
    let results = try TCPCheckService(probe: probe).check(
      configuration: configuration, profileID: "home")
    XCTAssertEqual(probe.endpoints.map(\.name), ["IMAP"])
    XCTAssertEqual(results.map(\.groupID), ["mail"])
    XCTAssertEqual(results.map(\.outcome), [.refused])
    XCTAssertThrowsError(
      try TCPCheckService(probe: probe).check(configuration: configuration, profileID: "missing"))
    XCTAssertEqual(probe.endpoints.count, 1)
  }
}

private final class RecordingProbe: TCPProbing {
  var endpoints: [Endpoint] = []
  func check(_ endpoint: Endpoint) -> TCPOutcome {
    endpoints.append(endpoint)
    return .refused
  }
}
