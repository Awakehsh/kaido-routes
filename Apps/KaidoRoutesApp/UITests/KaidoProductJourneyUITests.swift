import XCTest

@MainActor
final class KaidoProductJourneyUITests: XCTestCase {
  func testDefaultLaunchMakesC2MapPrimaryAndKeepsK7AsAnOrdinaryRoute() {
    continueAfterFailure = false
    let app = launchProduct()

    XCTAssertTrue(
      element("product-routes-origin", in: app)
        .waitForExistence(timeout: 5)
    )
    XCTAssertEqual(
      element("product-journey-stage", in: app).value as? String,
      "ATLAS"
    )
    XCTAssertTrue(
      reveal("product-routes-c2-overview", in: app)
        .waitForExistence(timeout: 5)
    )
    XCTAssertTrue(
      element("product-routes-c2-map", in: app).exists
    )
    XCTAssertTrue(
      element("product-routes-c2-map-route", in: app).isSelected
    )

    XCTAssertFalse(app.staticTexts["K7 证据"].exists)
    XCTAssertFalse(app.staticTexts["PRODUCT RELEASE"].exists)
    XCTAssertFalse(app.staticTexts["SNAPSHOT"].exists)

    reveal("product-routes-c2-map-facilities", in: app).tap()
    XCTAssertTrue(
      element("product-routes-c2-map", in: app)
        .waitForExistence(timeout: 3)
    )
    XCTAssertTrue(
      element("product-routes-c2-map-facilities", in: app).isSelected
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
        "product-topology-landmark-exit-"
          + "demo.c2.exit.hatsudai-minami.outer",
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

    let releaseID = "shutoko.product.k7-aoba-to-kohoku.2026-07-27"
    XCTAssertTrue(
      reveal("product-route-option-\(releaseID)", in: app).exists
    )

    let topologyScreenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    topologyScreenshot.name = "C2 primary route and ordinary K7 catalog entry"
    topologyScreenshot.lifetime = .keepAlways
    add(topologyScreenshot)
  }

  func testReleasedK7RouteAutomaticallySimulatesAcrossTheMap() {
    continueAfterFailure = false
    let app = launchProduct()
    let releaseID = "shutoko.product.k7-aoba-to-kohoku.2026-07-27"

    reveal("product-route-option-\(releaseID)", in: app).tap()
    XCTAssertTrue(
      element("product-geographic-map", in: app)
        .waitForExistence(timeout: 5)
    )

    reveal(
      "released-route-choice-shutoko.choice.kohoku.k7-up-to-shared-exit-corridor",
      in: app
    ).tap()
    reveal(
      "released-route-choice-shutoko.choice.kohoku.shared-corridor-to-exit",
      in: app
    ).tap()
    reveal("released-route-compile", in: app).tap()

    let journeyAction = element(
      "product-journey-primary-action",
      in: app
    )
    XCTAssertTrue(journeyAction.isEnabled)
    journeyAction.tap()
    XCTAssertEqual(
      element("product-journey-stage", in: app).value as? String,
      "REVIEW"
    )
    XCTAssertTrue(journeyAction.isEnabled)
    journeyAction.tap()

    XCTAssertTrue(
      element("product-drive-surface", in: app)
        .waitForExistence(timeout: 5)
    )
    XCTAssertEqual(
      element("product-map-drive", in: app).value as? String,
      "geographic"
    )

    let simulation = reveal("product-drive-simulation", in: app)
    let start = reveal("product-drive-start-simulation", in: app)
    XCTAssertTrue(start.isEnabled)
    start.tap()

    let junctionInset = element("product-junction-inset", in: app)
    XCTAssertTrue(
      junctionInset.waitForExistence(timeout: 12),
      "The K7 DecisionZone did not present a junction inset"
    )
    XCTAssertTrue(
      (junctionInset.value as? String)?.contains(
        "shutoko.decision-zone.kohoku.k7-up-shared-branch.v1"
      ) == true
    )
    waitForJunctionInsetAnimation()

    let junctionScreenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    junctionScreenshot.name = "Released K7 transient junction inset"
    junctionScreenshot.lifetime = .keepAlways
    add(junctionScreenshot)

    XCTAssertTrue(
      element("product-geographic-position-marker", in: app)
        .waitForExistence(timeout: 8)
    )
    XCTAssertTrue(
      waitForValuePrefix(
        "COMPLETED",
        on: simulation,
        timeout: 25
      )
    )
    XCTAssertEqual(
      element("product-drive-progress", in: app).value as? String,
      "5 of 5"
    )

    let screenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    screenshot.name = "Released K7 MapKit route simulation"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  func testHomeContinuesRestoredC2JourneyOnlyAfterExplicitResume() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-PRODUCT-JOURNEY-C2-RESTORE-PREVIEW",
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
    ]
    app.launch()

    let route = reveal("product-route-option-c2-complete", in: app)
    XCTAssertEqual(route.value as? String, "RESTORABLE")
    route.tap()

    let navigation = element("c2-full-navigation", in: app)
    XCTAssertTrue(navigation.waitForExistence(timeout: 5))
    XCTAssertEqual(navigation.value as? String, "EXPRESSWAY")
    XCTAssertEqual(
      element("c2-navigation-suspended", in: app).value as? String,
      "APP_INACTIVE"
    )

    app.buttons["c2-navigation-play-pause"].tap()

    XCTAssertFalse(
      element("c2-navigation-suspended", in: app).exists
    )
  }

  func testSettingsKeepInterfaceAndGuidanceVoiceIndependent() {
    continueAfterFailure = false
    let app = launchProduct()

    element("product-journey-settings", in: app).tap()
    XCTAssertTrue(
      element("product-settings", in: app)
        .waitForExistence(timeout: 3)
    )

    let japaneseVoice = element(
      "product-settings-guidance-voice-ja-JP",
      in: app
    )
    XCTAssertTrue(japaneseVoice.isSelected)

    let englishInterface = element(
      "product-journey-interface-language-en",
      in: app
    )
    englishInterface.tap()

    XCTAssertTrue(englishInterface.isSelected)
    XCTAssertTrue(japaneseVoice.isSelected)
  }

  private func launchProduct() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = [
      "-RESET-NAVIGATION-CHECKPOINT",
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
      "-app.kaidoroutes.map-projection.v2",
      "geographic",
    ]
    app.launch()
    return app
  }

  private func element(
    _ identifier: String,
    in app: XCUIApplication
  ) -> XCUIElement {
    app.descendants(matching: .any)[identifier]
  }

  private func reveal(
    _ identifier: String,
    in app: XCUIApplication
  ) -> XCUIElement {
    let target = element(identifier, in: app)
    XCTAssertTrue(
      target.waitForExistence(timeout: 3),
      "\(identifier) did not exist"
    )
    for _ in 0..<12 where !target.isHittable {
      app.swipeUp()
    }
    XCTAssertTrue(target.isHittable, "\(identifier) did not become visible")
    return target
  }

  private func waitForValuePrefix(
    _ prefix: String,
    on element: XCUIElement,
    timeout: TimeInterval
  ) -> Bool {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(
        format: "value BEGINSWITH %@",
        prefix
      ),
      object: element
    )
    return XCTWaiter.wait(
      for: [expectation],
      timeout: timeout
    ) == .completed
  }

  private func waitForJunctionInsetAnimation() {
    let expectation = XCTestExpectation(
      description: "Junction inset animation settled"
    )
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
      expectation.fulfill()
    }
    XCTAssertEqual(
      XCTWaiter.wait(for: [expectation], timeout: 1),
      .completed
    )
  }
}
