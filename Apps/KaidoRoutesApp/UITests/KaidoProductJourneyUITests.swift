import XCTest

@MainActor
final class KaidoProductJourneyUITests: XCTestCase {
  func testDefaultLaunchMakesWholeShutoMapTheProduct() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-RESET-NAVIGATION-CHECKPOINT"]
    app.launch()

    XCTAssertTrue(
      element("whole-shuto-product", in: app)
        .waitForExistence(timeout: 5)
    )
    XCTAssertEqual(
      element("whole-shuto-product", in: app).value as? String,
      "PLANNING"
    )
    XCTAssertTrue(
      element("whole-shuto-network-map", in: app).exists
    )
    XCTAssertTrue(
      app.staticTexts["首都高全网导航"].exists
    )

    let topologyScreenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    topologyScreenshot.name = "Whole Shuto default product map"
    topologyScreenshot.lifetime = .keepAlways
    add(topologyScreenshot)
  }

  func testWholeShutoRouteAndJunctionPreviewAreMapFirst() {
    continueAfterFailure = false
    let routeApp = XCUIApplication()
    routeApp.launchArguments = ["-WHOLE-SHUTO-ROUTE-PREVIEW"]
    routeApp.launch()

    let product = element("whole-shuto-product", in: routeApp)
    XCTAssertTrue(product.waitForExistence(timeout: 5))
    XCTAssertEqual(product.value as? String, "REVIEW")
    XCTAssertTrue(element("whole-shuto-network-map", in: routeApp).exists)
    XCTAssertTrue(
      element("whole-shuto-start-simulation", in: routeApp).exists
    )
    routeApp.terminate()

    let junctionApp = XCUIApplication()
    junctionApp.launchArguments = ["-WHOLE-SHUTO-JUNCTION-PREVIEW"]
    junctionApp.launch()
    XCTAssertTrue(
      element("whole-shuto-geographic-map", in: junctionApp)
        .waitForExistence(timeout: 5)
    )
    let junctionInset = element(
      "whole-shuto-junction-inset",
      in: junctionApp
    )
    XCTAssertTrue(junctionInset.waitForExistence(timeout: 5))
    XCTAssertTrue(junctionInset.label.contains("大井JCT"))
    XCTAssertTrue(junctionInset.label.contains("左分岔"))
    XCTAssertTrue(junctionInset.label.contains("東名・中央道"))
    XCTAssertTrue(junctionInset.label.contains("车道编号尚未发布"))
    XCTAssertEqual(
      element("whole-shuto-guidance-speech", in: junctionApp).value
        as? String,
      "等待已审核提示"
    )
    junctionApp.terminate()

    let navigationApp = XCUIApplication()
    navigationApp.launchArguments = [
      "-WHOLE-SHUTO-JUNCTION-NAVIGATION-PREVIEW"
    ]
    navigationApp.launch()
    let actorJunctionInset = element(
      "whole-shuto-junction-inset",
      in: navigationApp
    )
    XCTAssertTrue(actorJunctionInset.waitForExistence(timeout: 10))
    XCTAssertTrue(actorJunctionInset.label.contains("大井JCT"))
    let speech = element(
      "whole-shuto-guidance-speech",
      in: navigationApp
    )
    XCTAssertTrue(speech.exists)
    XCTAssertTrue(
      ["已安排", "播报中", "已播报"].contains(
        speech.value as? String ?? ""
      )
    )
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
      "-LEGACY-PRODUCT-JOURNEY",
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
