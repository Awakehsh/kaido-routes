import XCTest

@MainActor
final class KaidoProductJourneyUITests: XCTestCase {
  func testDefaultLaunchPresentsOrderedRouteFirstJourney() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()

    let shell = element("product-journey-scroll", in: app)
    XCTAssertTrue(shell.waitForExistence(timeout: 5))

    let stage = element("product-journey-stage", in: app)
    XCTAssertEqual(stage.value as? String, "ATLAS")
    XCTAssertEqual(
      element("product-journey-step-atlas", in: app).value as? String,
      "CURRENT"
    )
    XCTAssertEqual(
      element("product-journey-step-navigation", in: app).value as? String,
      "LOCKED"
    )
    let k7Mode = element("product-journey-atlas-k7Evidence", in: app)
    XCTAssertTrue(k7Mode.isEnabled)
    k7Mode.tap()
    XCTAssertTrue(k7Mode.isSelected)
    XCTAssertEqual(
      reveal("product-journey-release-catalog", in: app).value as? String,
      "0 RELEASED ROAD · 1 DEMO"
    )

    let action = element("product-journey-primary-action", in: app)
    XCTAssertTrue(action.isEnabled)
    XCTAssertEqual(action.value as? String, "AVAILABLE")
    action.tap()

    XCTAssertEqual(stage.value as? String, "AUTHORING")
    XCTAssertEqual(action.value as? String, "BLOCKED")
    XCTAssertFalse(
      element("product-journey-step-atlas", in: app).isSelected
    )
    XCTAssertTrue(
      element("product-journey-step-authoring", in: app).isSelected
    )
    XCTAssertTrue(
      element("route-editor-current-decision", in: app)
        .waitForExistence(timeout: 3)
    )
  }

  func testReviewPreviewShowsTruthfulNavigationReleaseBlocker() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-PRODUCT-JOURNEY-REVIEW-PREVIEW"]
    app.launch()

    let stage = element("product-journey-stage", in: app)
    XCTAssertTrue(stage.waitForExistence(timeout: 5))
    XCTAssertEqual(stage.value as? String, "REVIEW")

    let blocker = reveal(
      "product-journey-navigation-blocker",
      in: app
    )
    XCTAssertEqual(
      blocker.value as? String,
      "ROUTE_RELEASE_AUTHORITY_UNAVAILABLE"
    )

    let action = element("product-journey-primary-action", in: app)
    XCTAssertFalse(action.isEnabled)
    XCTAssertEqual(action.value as? String, "BLOCKED")

    let screenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    screenshot.name = "Route-first product journey review gate"
    screenshot.lifetime = .keepAlways
    add(screenshot)
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
    XCTAssertTrue(target.waitForExistence(timeout: 2))
    for _ in 0..<8 where !target.isHittable {
      app.swipeUp()
    }
    XCTAssertTrue(target.isHittable, "\(identifier) did not become visible")
    return target
  }
}
