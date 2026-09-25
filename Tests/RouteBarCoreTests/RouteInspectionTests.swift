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
    XCTAssertTrue(route.isExplicitStaticHostRoute(for: "203.0.113.10"))
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
