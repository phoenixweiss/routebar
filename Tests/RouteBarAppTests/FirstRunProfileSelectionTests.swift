import RouteBarCore
import XCTest

@testable import RouteBarApp

final class FirstRunProfileSelectionTests: XCTestCase {
  func testKeepsAValidInMemorySelection() {
    XCTAssertEqual(
      FirstRunProfileSelection.resolve(
        profiles: [option("home"), option("work")],
        selectedProfileID: "work"
      ),
      .selected("work")
    )
  }

  func testSelectsTheOnlyProfileWithoutAmbiguity() {
    XCTAssertEqual(
      FirstRunProfileSelection.resolve(
        profiles: [option("home")],
        selectedProfileID: nil
      ),
      .selected("home")
    )
  }

  func testRequiresAChoiceWhenMultipleProfilesExist() {
    XCTAssertEqual(
      FirstRunProfileSelection.resolve(
        profiles: [option("home"), option("work")],
        selectedProfileID: nil
      ),
      .requiresSelection
    )
  }

  func testRejectsASelectionRemovedFromTheConfiguration() {
    XCTAssertEqual(
      FirstRunProfileSelection.resolve(
        profiles: [option("home"), option("work")],
        selectedProfileID: "removed"
      ),
      .requiresSelection
    )
  }

  private func option(_ id: String) -> RouteBarProfileOption {
    RouteBarProfileOption(
      profile: Profile(
        id: id,
        name: id.capitalized,
        match: ProfileMatch(ssids: ["Sample Wi-Fi"]),
        groups: ["services"]
      )
    )
  }
}
