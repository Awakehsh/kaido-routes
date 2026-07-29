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
    XCTAssertEqual(
      demo.value as? String,
      "DEMO_NOT_NAVIGATION;route;junction=hidden"
    )
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
      "entrance=1;junction=13;interchange=20;parking=1;exit=1"
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
        "product-topology-landmark-interchange-"
          + "demo.c2.interchange.nakanochojabashi",
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

    let routeScreenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    routeScreenshot.name = "C2 plus B completed route map demo"
    routeScreenshot.lifetime = .keepAlways
    add(routeScreenshot)

    element("c2-demo-mode-facilities", in: app).tap()
    XCTAssertEqual(
      demo.value as? String,
      "DEMO_NOT_NAVIGATION;facilities;junction=hidden"
    )
    XCTAssertTrue(app.staticTexts["中野長者橋 IC · 入口"].exists)
    XCTAssertTrue(
      app.staticTexts["大井 PA（西行 · 本路线不进入）"].exists
    )

    let facilitiesScreenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    facilitiesScreenshot.name = "C2 directional IC and PA layer"
    facilitiesScreenshot.lifetime = .keepAlways
    add(facilitiesScreenshot)

    element("c2-demo-show-kasai-junction", in: app).tap()
    XCTAssertEqual(
      demo.value as? String,
      "DEMO_NOT_NAVIGATION;facilities;junction=visible"
    )
    let inset = element("product-junction-inset", in: app)
    XCTAssertTrue(inset.waitForExistence(timeout: 3))
    XCTAssertTrue(
      (inset.value as? String)?.contains(
        "demo.c2.kasai.outer-to-b-west"
      ) == true
    )
    XCTAssertTrue((inset.value as? String)?.contains("9  横浜") == true)

    let junctionScreenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    junctionScreenshot.name = "C2 Kasai transient junction inset"
    junctionScreenshot.lifetime = .keepAlways
    add(junctionScreenshot)
  }

  private func element(
    _ identifier: String,
    in app: XCUIApplication
  ) -> XCUIElement {
    app.descendants(matching: .any)[identifier]
  }
}
