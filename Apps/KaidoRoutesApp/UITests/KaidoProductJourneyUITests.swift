import XCTest

@MainActor
final class KaidoProductJourneyUITests: XCTestCase {
  func testDefaultLaunchShowsTheReleasedK7RouteOnARealMap() {
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
    XCTAssertEqual(
      element("product-map-routes", in: app).value as? String,
      "geographic"
    )

    let map = element("product-geographic-map", in: app)
    XCTAssertTrue(map.waitForExistence(timeout: 5))
    XCTAssertTrue(
      (map.value as? String)?.contains("195 coordinates") == true
    )
    XCTAssertTrue(
      element("product-geographic-route-start", in: app).exists
    )
    XCTAssertTrue(
      element("product-geographic-route-finish", in: app).exists
    )

    XCTAssertFalse(app.staticTexts["K7 证据"].exists)
    XCTAssertFalse(app.staticTexts["PRODUCT RELEASE"].exists)
    XCTAssertFalse(app.staticTexts["SNAPSHOT"].exists)

    element("product-map-projection-topology", in: app).tap()
    XCTAssertEqual(
      element("product-map-routes", in: app).value as? String,
      "topology"
    )
    XCTAssertTrue(
      element("product-topology-map", in: app)
        .waitForExistence(timeout: 3)
    )
    XCTAssertEqual(
      element("product-topology-route-shield", in: app).label,
      "K7"
    )
    XCTAssertEqual(
      element("product-topology-facility-summary", in: app).value
        as? String,
      "entrance=1;junction=2;interchange=0;parking=0;exit=1"
    )
    XCTAssertTrue(
      element(
        "product-topology-landmark-entrance-"
          + "shutoko.entrance.yokohama-aoba.k7-northwest.up",
        in: app
      ).exists
    )
    XCTAssertTrue(
      element(
        "product-topology-landmark-exit-"
          + "shutoko.exit.yokohama-kohoku.k7-northwest.up",
        in: app
      ).exists
    )

    let topologyScreenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    topologyScreenshot.name = "Released K7 topology facility overview"
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
