import XCTest

@MainActor
final class C2RouteMapDemoUITests: XCTestCase {
  func testCompleteNavigationAcceptsAnyOriginAndDestination() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-C2-FULL-NAVIGATION-DEMO"]
    app.launchSilently()

    let navigation = element("c2-full-navigation", in: app)
    XCTAssertTrue(navigation.waitForExistence(timeout: 5))
    XCTAssertEqual(navigation.value as? String, "PLANNING")

    let origin = app.textFields["c2-navigation-origin"]
    let destination = app.textFields["c2-navigation-destination"]
    XCTAssertEqual(origin.value as? String, "東京都庁")
    XCTAssertEqual(destination.value as? String, "東京駅")

    let start = element("c2-navigation-start", in: app)
    XCTAssertEqual(start.value as? String, "AVAILABLE")
    start.tap()

    let reviewPredicate = NSPredicate(format: "value == 'REVIEW'")
    let review = expectation(
      for: reviewPredicate,
      evaluatedWith: navigation
    )
    wait(for: [review], timeout: 5)
    XCTAssertTrue(
      element("c2-navigation-review", in: app).exists
    )
    XCTAssertEqual(start.value as? String, "AVAILABLE")
    start.tap()

    let activePredicate = NSPredicate(
      format:
        "value != 'PLANNING' AND value != 'ROUTING' "
        + "AND value != 'REVIEW' AND value != 'FAILED'"
    )
    let active = expectation(
      for: activePredicate,
      evaluatedWith: navigation
    )
    wait(for: [active], timeout: 5)
    XCTAssertTrue(
      element("c2-navigation-progress", in: app).exists
    )

    let screenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    screenshot.name = "C2 complete navigation from arbitrary endpoints"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  func testKeyboardRouteActionStopsAtParkedReview() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-C2-FULL-NAVIGATION-DEMO"]
    app.launchSilently()

    let navigation = element("c2-full-navigation", in: app)
    XCTAssertTrue(navigation.waitForExistence(timeout: 5))

    let destination = app.textFields["c2-navigation-destination"]
    destination.tap()
    destination.typeText("\n")

    let reviewPredicate = NSPredicate(format: "value == 'REVIEW'")
    let review = expectation(
      for: reviewPredicate,
      evaluatedWith: navigation
    )
    wait(for: [review], timeout: 5)
    XCTAssertTrue(element("c2-navigation-review", in: app).exists)
    XCTAssertFalse(
      element("c2-navigation-progress", in: app).exists
    )
  }

  func testVerifiedKasaiAndOiJunctionInsetsAppearAutomatically() {
    continueAfterFailure = false

    let kasaiApp = XCUIApplication()
    kasaiApp.launchArguments = [
      "-C2-NAVIGATION-KASAI-PREVIEW",
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
    ]
    kasaiApp.launchSilently()
    let kasaiInset = element("product-junction-inset", in: kasaiApp)
    XCTAssertTrue(kasaiInset.waitForExistence(timeout: 5))
    XCTAssertTrue(
      (kasaiInset.value as? String)?.contains(
        "demo.c2.kasai.outer-to-b-west"
      ) == true
    )
    XCTAssertTrue(
      (kasaiInset.value as? String)?.contains("9  横浜") == true
    )

    let kasaiScreenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    kasaiScreenshot.name = "C2 automatic Kasai right-branch inset"
    kasaiScreenshot.lifetime = .keepAlways
    add(kasaiScreenshot)
    kasaiApp.terminate()

    let oiApp = XCUIApplication()
    oiApp.launchArguments = [
      "-C2-NAVIGATION-OI-PREVIEW",
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
    ]
    oiApp.launchSilently()
    let oiInset = element("product-junction-inset", in: oiApp)
    XCTAssertTrue(oiInset.waitForExistence(timeout: 5))
    XCTAssertTrue(
      (oiInset.value as? String)?.contains(
        "demo.c2.oi.b-west-to-c2-outer"
      ) == true
    )
    XCTAssertTrue(
      oiInset.label.contains("500 m")
    )
    XCTAssertTrue(
      (oiInset.value as? String)?.contains(
        "中央環状線（外回り）"
      ) == true
    )
    XCTAssertTrue(
      (element("c2-navigation-guidance", in: oiApp).value as? String)?
        .contains("大井 JCT 左分岔") == true
    )

    let oiScreenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    oiScreenshot.name = "C2 automatic Oi left-branch tunnel inset"
    oiScreenshot.lifetime = .keepAlways
    add(oiScreenshot)
  }

  func testExitHandoffReturnsToSurfaceNavigation() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-C2-NAVIGATION-EGRESS-PREVIEW"]
    app.launchSilently()

    let navigation = element("c2-full-navigation", in: app)
    XCTAssertTrue(navigation.waitForExistence(timeout: 5))
    XCTAssertEqual(navigation.value as? String, "SURFACE_EGRESS")
    XCTAssertTrue(
      element("c2-navigation-surface-map", in: app).exists
    )
    XCTAssertTrue(
      (element("c2-navigation-guidance", in: app).value as? String)?
        .contains("SURFACE_EGRESS") == true
    )
  }

  func testCompletedC2CircuitDemoShowsItsWholeRouteStructure() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-C2-ROUTE-MAP-DEMO",
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
    ]
    app.launchSilently()

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
