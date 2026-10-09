import Foundation
import Network
import XCTest

@testable import RouteBarCore

final class ConnectivityPathTests: XCTestCase {
  func testKernelSelectsLoopbackSourceWithoutSendingData() {
    let selector = SystemConnectivityPathSelector()
    XCTAssertEqual(
      selector.select(host: "127.0.0.1", port: 443, timeout: 1),
      .selected(
        ConnectivityPath(remoteAddress: "127.0.0.1", localAddress: "127.0.0.1")))
  }

  func testConnectionUsesSelectedSourceAndNoRequiredInterface() {
    for address in ["192.0.2.10", "192.0.2.20"] {
      let connection = ConnectivityPath(remoteAddress: "198.51.100.1", localAddress: address)
        .connection(port: 443, parameters: .tcp)
      XCTAssertEqual(
        connection.parameters.requiredLocalEndpoint, .hostPort(host: .init(address), port: .any))
      XCTAssertNil(connection.parameters.requiredInterface)
      XCTAssertEqual(
        connection.parameters.requiredInterfaceType, NWParameters.tcp.requiredInterfaceType)
      XCTAssertEqual(connection.endpoint, .hostPort(host: "198.51.100.1", port: 443))
    }
  }

  func testEachProbeReselectsPathAndDoesNotReuseOldLocalAddress() {
    let selector = RecordingPathSelector()
    let probe = TCPProbe(pathSelector: selector)
    let endpoint = Endpoint(name: "Example", host: "mail.example.org", port: 443, protocol: .tcp)
    for _ in 0..<2 { XCTAssertEqual(probe.check(endpoint), .dnsFailure) }
    XCTAssertEqual(selector.hosts, ["mail.example.org", "mail.example.org"])
    XCTAssertEqual(selector.ports, [443, 443])
  }

  func testSameDestinationUsesNewKernelSourceAfterNetworkChange() {
    let routing = ChangingRouting()
    let selector = SystemConnectivityPathSelector { _, _ in routing.path() }
    XCTAssertEqual(
      selector.select(host: "service.example.org", port: 443, timeout: 1),
      .selected(
        ConnectivityPath(remoteAddress: "198.51.100.1", localAddress: "192.0.2.10")))
    routing.changeSource()
    XCTAssertEqual(
      selector.select(host: "service.example.org", port: 443, timeout: 1),
      .selected(
        ConnectivityPath(remoteAddress: "198.51.100.1", localAddress: "192.0.2.20")))
  }

  func testAllProtocolsReportPathErrorsBeforeOpeningConnection() {
    let selector = RecordingPathSelector()
    XCTAssertEqual(
      TLSProbe(testAnchors: [], pathSelector: selector).check(
        Endpoint(name: "TLS", host: "mail.example.org", port: 993, protocol: .tls)), .dnsFailure)
    XCTAssertEqual(
      SMTPStartTLSProbe(testAnchors: [], pathSelector: selector).check(
        Endpoint(name: "SMTP", host: "mail.example.org", port: 587, protocol: .startTLSSMTP)),
      .dnsFailure)
    XCTAssertEqual(
      HTTPSProbe(testAnchors: [], pathSelector: selector).check(
        HTTPSCheck(url: "https://status.example.org/", expectedStatuses: [200])
      ).outcome, .dnsFailure)
    XCTAssertEqual(selector.hosts.count, 3)
  }

  func testDNSAndSourceSelectionShareDeadlineAndLateResultIsIgnored() {
    let selector = SystemConnectivityPathSelector { _, _ in
      Thread.sleep(forTimeInterval: 0.2)
      return .selected(ConnectivityPath(remoteAddress: "127.0.0.1", localAddress: "127.0.0.1"))
    }
    let start = Date()
    XCTAssertEqual(
      selector.select(host: "example.invalid", port: 443, timeout: 0.02), .failed(.timeout))
    XCTAssertLessThan(Date().timeIntervalSince(start), 0.15)
    XCTAssertEqual(
      selector.select(host: "example.invalid", port: 443, timeout: 0), .failed(.timeout))
  }
}

private final class ChangingRouting: @unchecked Sendable {
  private let lock = NSLock()
  private var address = "192.0.2.10"
  func changeSource() { lock.withLock { address = "192.0.2.20" } }
  func path() -> ConnectivityPathResult {
    lock.withLock {
      .selected(ConnectivityPath(remoteAddress: "198.51.100.1", localAddress: address))
    }
  }
}

private final class RecordingPathSelector: ConnectivityPathSelecting, @unchecked Sendable {
  private let lock = NSLock()
  private var requests: [(String, Int)] = []
  var hosts: [String] { lock.withLock { requests.map(\.0) } }
  var ports: [Int] { lock.withLock { requests.map(\.1) } }
  func select(host: String, port: Int, timeout: Double) -> ConnectivityPathResult {
    lock.withLock { requests.append((host, port)) }
    return .failed(.dnsFailure)
  }
}
