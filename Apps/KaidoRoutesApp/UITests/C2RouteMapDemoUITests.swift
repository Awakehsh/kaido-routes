import XCTest

@MainActor
final class C2RouteMapDemoUITests: XCTestCase {
  func testCompletedC2CircuitDemoShowsItsWholeRouteStructure() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-C2-ROUTE-MAP-DEMO"]
    app.launch()

    let demo = element("c2-completed-route-demo", in: app)
    XCTAssertTrue(demo.waitForExistence(timeout: 5))
    XCTAssertEqual(demo.value as? String, "DEMO_NOT_NAVIGATION")
    XCTAssertEqual(
      element("product-topology-route-shield", in: app).label,
      "C2"
    )
    XCTAssertEqual(
      element("product-topology-route-shield-B", in: app).label,
      "B"
    )
    XCTAssertEqual(
      element("product-topology-facility-summary", in: app).value
        as? String,
      "entrance=1;junction=13;parking=1;exit=1"
    )
    XCTAssertTrue(
      element(
        "product-topology-landmark-entrance-"
          + "demo.c2.entrance.tomigaya.outer",
        in: app
      ).exists
    )
    XCTAssertTrue(
      element(
        "product-topology-landmark-parkingArea-"
          + "demo.c2.pa.oi-westbound",
        in: app
      ).exists
    )
    XCTAssertTrue(
      element(
        "product-topology-landmark-exit-"
          + "demo.c2.exit.hatsudai-minami.outer",
        in: app
      ).exists
    )

    let screenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    screenshot.name = "C2 plus B completed route map demo"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  private func element(
    _ identifier: String,
    in app: XCUIApplication
  ) -> XCUIElement {
    app.descendants(matching: .any)[identifier]
  }
}
