import XCTest

@testable import RouteBarApp

final class RouteBarWindowPresentationTests: XCTestCase {
  func testForegroundLaunchActivatesTheApplication() {
    XCTAssertEqual(
      RouteBarWindowPresentationRequest.foregroundLaunch.presentation,
      .activateApplication
    )
  }

  func testExplicitUserActionActivatesTheApplication() {
    XCTAssertEqual(
      RouteBarWindowPresentationRequest.explicitUserAction.presentation,
      .activateApplication
    )
  }

  func testBackgroundLaunchDoesNotPresentTheWindow() {
    XCTAssertNil(RouteBarWindowPresentationRequest.backgroundLaunch.presentation)
  }

  func testInactiveDockReopenDoesNotPresentTheWindow() {
    XCTAssertNil(
      RouteBarWindowPresentationRequest.dockReopen(
        applicationIsActive: false,
        hasVisibleWindows: false
      ).presentation
    )
  }

  func testDockReopenDoesNotPresentAnotherWindowWhenOneIsVisible() {
    XCTAssertNil(
      RouteBarWindowPresentationRequest.dockReopen(
        applicationIsActive: true,
        hasVisibleWindows: true
      ).presentation
    )
  }

  func testActiveDockReopenPresentsWithoutAnotherActivation() {
    XCTAssertEqual(
      RouteBarWindowPresentationRequest.dockReopen(
        applicationIsActive: true,
        hasVisibleWindows: false
      ).presentation,
      .keepApplicationState
    )
  }
}
