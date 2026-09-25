import XCTest

@testable import RouteBarCore

final class NetworkDiscoveryTests: XCTestCase {
  func testSelectsPhysicalGatewayInsteadOfVPNOrBridge() throws {
    let output = """
      Routing tables

      Internet:
      Destination        Gateway            Flags               Netif Expire
      default            link#21            UCSg                utun4
      default            192.0.2.1          UGScIg                en0
      default            link#20            UCSIg           bridge100      !
      """

    let gateway = try RouteTableParser.physicalDefaultGateway(from: output)
    let vpnInterfaces = try RouteTableParser.vpnDefaultInterfaces(from: output)

    XCTAssertEqual(gateway, .init(address: "192.0.2.1", interface: "en0"))
    XCTAssertEqual(vpnInterfaces, ["utun4"])
  }

  func testRejectsAmbiguousPhysicalGateways() {
    let output = """
      Destination Gateway Flags Netif Expire
      default 192.0.2.1 UGScIg en0
      default 198.51.100.1 UGScIg en5
      """

    XCTAssertThrowsError(try RouteTableParser.physicalDefaultGateway(from: output)) { error in
      XCTAssertTrue(error.localizedDescription.contains("multiple physical"))
    }
  }

  func testRejectsVPNOnlyRouteTable() {
    let output = """
      Destination Gateway Flags Netif Expire
      default link#21 UCSg utun4
      """

    XCTAssertThrowsError(try RouteTableParser.physicalDefaultGateway(from: output)) { error in
      XCTAssertTrue(error.localizedDescription.contains("could not find a physical"))
    }
  }
}
