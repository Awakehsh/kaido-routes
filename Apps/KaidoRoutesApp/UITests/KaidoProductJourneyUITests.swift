import XCTest

@MainActor
final class KaidoProductJourneyUITests: XCTestCase {
  func testDefaultLaunchIsConciseAndExcludesInternalEvidenceUI() {
    continueAfterFailure = false
    let app = launchDefaultJourney()

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
      "topology"
    )
    XCTAssertTrue(element("product-routes-recommendation", in: app).exists)
    XCTAssertTrue(element("product-routes-create", in: app).exists)
    XCTAssertTrue(element("product-routes-saved", in: app).exists)

    XCTAssertFalse(app.staticTexts["根据当前位置"].exists)
    XCTAssertFalse(app.staticTexts["今天想跑哪条路线？"].exists)
    XCTAssertFalse(
      app.staticTexts["先选路线。我们再安排合适的方向入口。"].exists
    )
    XCTAssertFalse(app.staticTexts["K7 证据"].exists)
    XCTAssertFalse(app.staticTexts["PRODUCT RELEASE"].exists)
    XCTAssertFalse(app.staticTexts["SNAPSHOT"].exists)
  }

  func testMapProjectionStaysSharedThroughRoutesPlanReviewAndDrive()
    throws
  {
    continueAfterFailure = false
    let app = launchDefaultJourney()

    let routesMap = element("product-map-routes", in: app)
    XCTAssertTrue(routesMap.waitForExistence(timeout: 5))
    element("product-map-projection-geographic", in: app).tap()
    XCTAssertEqual(routesMap.value as? String, "geographic")

    reveal(
      "product-route-option-preview.synthetic.product-release.v1",
      in: app
    ).tap()

    let planMap = element("product-map-plan", in: app)
    XCTAssertTrue(planMap.waitForExistence(timeout: 5))
    XCTAssertEqual(planMap.value as? String, "geographic")

    element("product-map-projection-topology", in: app).tap()
    XCTAssertEqual(planMap.value as? String, "topology")
    XCTAssertTrue(element("product-topology-map", in: app).exists)
    XCTAssertTrue(
      element("product-topology-repeated-occurrences", in: app).exists
    )

    authorDemoRoute(in: app)

    let action = element("product-journey-primary-action", in: app)
    XCTAssertTrue(action.isEnabled)
    action.tap()

    XCTAssertEqual(
      element("product-journey-stage", in: app).value as? String,
      "REVIEW"
    )
    let reviewMap = element("product-map-review", in: app)
    XCTAssertTrue(reviewMap.waitForExistence(timeout: 5))
    XCTAssertEqual(reviewMap.value as? String, "topology")

    XCTAssertTrue(action.isEnabled)
    action.tap()

    let driveMap = element("product-map-drive", in: app)
    XCTAssertTrue(driveMap.waitForExistence(timeout: 5))
    XCTAssertEqual(driveMap.value as? String, "topology")
    XCTAssertFalse(
      element("product-topology-position-marker", in: app).exists
    )
    XCTAssertTrue(
      element("product-topology-position-estimated", in: app).exists
        || element("product-topology-position-unavailable", in: app).exists
    )

    let start = reveal("product-drive-start-rehearsal", in: app)
    XCTAssertTrue(start.isEnabled)
    start.tap()

    let marker = element("product-topology-position-marker", in: app)
    XCTAssertTrue(marker.waitForExistence(timeout: 5))

    element("product-map-projection-geographic", in: app).tap()
    XCTAssertEqual(driveMap.value as? String, "geographic")
    XCTAssertTrue(element("product-geographic-map", in: app).exists)

    element("product-map-projection-topology", in: app).tap()
    XCTAssertEqual(driveMap.value as? String, "topology")
    XCTAssertTrue(marker.waitForExistence(timeout: 2))

    let screenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    screenshot.name = "Shared topology projection with exact route position"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  func testReviewPreviewKeepsNavigationFailClosedWithoutRawCodes() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-PRODUCT-JOURNEY-REVIEW-PREVIEW",
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
    ]
    app.launch()

    let stage = element("product-journey-stage", in: app)
    XCTAssertTrue(stage.waitForExistence(timeout: 5))
    XCTAssertEqual(stage.value as? String, "REVIEW")
    XCTAssertTrue(element("product-review-summary", in: app).exists)

    let action = element("product-journey-primary-action", in: app)
    XCTAssertFalse(action.isEnabled)
    XCTAssertEqual(action.value as? String, "BLOCKED")
    XCTAssertFalse(
      app.staticTexts["ROUTE_RELEASE_AUTHORITY_UNAVAILABLE"].exists
    )
    XCTAssertFalse(app.staticTexts["SYNTHETIC_TEST_ONLY"].exists)
  }

  func testSettingsKeepInterfaceAndGuidanceVoiceIndependent() {
    continueAfterFailure = false
    let app = launchDefaultJourney()

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
    XCTAssertEqual(
      element("product-journey-interface-language", in: app)
        .value as? String,
      "en"
    )
  }

  func testInternalEvidenceWorkbenchRequiresIntentionalLaunchArgument() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-INTERNAL-REVIEW-HOME",
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
    ]
    app.launch()

    XCTAssertTrue(
      app.buttons["K7 证据"].waitForExistence(timeout: 5)
    )
    XCTAssertTrue(app.staticTexts["REVIEW"].exists)
    XCTAssertFalse(element("product-routes-origin", in: app).exists)
  }

  private func launchDefaultJourney() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = [
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
    ]
    app.launch()
    return app
  }

  private func authorDemoRoute(in app: XCUIApplication) {
    reveal("released-route-choice-test.choice.loop", in: app).tap()
    reveal("released-route-choice-test.choice.loop", in: app).tap()
    reveal("released-route-choice-test.choice.exit", in: app).tap()
    reveal("released-route-compile", in: app).tap()
    reveal("released-vehicle-class-STANDARD", in: app).tap()
    app.swipeUp()
    reveal("released-payment-method-ETC", in: app).tap()
    XCTAssertTrue(
      element("released-route-review-ready", in: app)
        .waitForExistence(timeout: 3)
    )
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
    for _ in 0..<10 where !target.isHittable {
      app.swipeUp()
    }
    XCTAssertTrue(target.isHittable, "\(identifier) did not become visible")
    return target
  }
}
