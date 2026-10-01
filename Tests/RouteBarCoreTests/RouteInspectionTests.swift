import XCTest

@testable import RouteBarCore

final class RouteInspectionTests: XCTestCase {
  func testParsesExplicitStaticHostRoute() throws {
    let output = """
         route to: 203.0.113.10
      destination: 203.0.113.10
          gateway: 192.0.2.1
        interface: en0
            flags: <UP,GATEWAY,HOST,STATIC>
      """

    let route = try RouteGetParser.parse(output)

    XCTAssertEqual(route.destination, "203.0.113.10")
    XCTAssertEqual(route.gateway, "192.0.2.1")
    XCTAssertEqual(route.interface, "en0")
    XCTAssertNil(route.interfaceAddress)
    XCTAssertTrue(route.isExplicitStaticHostRoute(for: "203.0.113.10"))
  }

  func testParsesInterfaceAddressFromVerboseRouteOutput() throws {
    let output = """
         route to: 203.0.113.10
      destination: 203.0.113.10
          gateway: 192.0.2.1
        interface: en0
            flags: <UP,GATEWAY,HOST,STATIC>
       recvpipe  sendpipe  ssthresh  rtt,msec    rttvar  hopcount      mtu     expire
             0         0         0         0         0         0      1500         0
        sockaddrs: <DST,GATEWAY,IFP,IFA>
       203.0.113.10 192.0.2.1 index: 11 en0: 192.0.2.44
      """

    let route = try RouteGetParser.parse(output)

    XCTAssertEqual(route.interfaceAddress, "192.0.2.44")
  }

  func testDefaultRouteIsNotMistakenForExplicitHostRoute() throws {
    let output = """
         route to: 203.0.113.10
      destination: default
          gateway: 192.0.2.1
        interface: en0
            flags: <UP,GATEWAY,DONE,STATIC,PRCLONING,GLOBAL>
      """

    let route = try RouteGetParser.parse(output)

    XCTAssertFalse(route.isExplicitStaticHostRoute(for: "203.0.113.10"))
  }
}
