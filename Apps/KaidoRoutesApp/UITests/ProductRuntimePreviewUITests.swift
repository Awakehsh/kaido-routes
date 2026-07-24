import XCTest

@MainActor
final class ProductRuntimePreviewUITests: XCTestCase {
  func testJointReleaseStartsPlanningWithStrictEntryLocked() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-PRODUCT-RUNTIME-PREVIEW"]
    app.launch()

    let panel = app.descendants(matching: .any)[
      "synthetic-product-runtime-panel"
    ]
    XCTAssertTrue(panel.waitForExistence(timeout: 5))

    let activation = app.descendants(matching: .any)[
      "product-runtime-activation"
    ]
    XCTAssertTrue(activation.waitForExistence(timeout: 2))
    XCTAssertEqual(activation.value as? String, "RUNTIME READY")

    let snapshot = app.descendants(matching: .any)[
      "product-runtime-snapshot"
    ]
    XCTAssertTrue(snapshot.waitForExistence(timeout: 2))
    XCTAssertTrue((snapshot.value as? String)?.contains("PLANNING") == true)
    XCTAssertTrue((snapshot.value as? String)?.contains("LOCKED") == true)

    let input = app.descendants(matching: .any)["product-runtime-input"]
    XCTAssertEqual(input.value as? String, "INPUT DISCONNECTED")

    let speech = app.descendants(matching: .any)[
      "product-runtime-speech"
    ]
    XCTAssertTrue(speech.waitForExistence(timeout: 2))
    XCTAssertEqual(speech.value as? String, "IDLE")

    XCTAssertTrue(
      app.descendants(matching: .any)["product-runtime-safety"].exists
    )

    let lifecycle = app.descendants(matching: .any)[
      "product-runtime-lifecycle"
    ]
    XCTAssertTrue(lifecycle.waitForExistence(timeout: 2))
    XCTAssertEqual(lifecycle.value as? String, "FOREGROUND")
  }

  func testSyntheticTraceRendersTheActorOwnedPhoneProjection() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-PRODUCT-RUNTIME-PREVIEW"]
    app.launch()

    let activation = element("product-runtime-activation", in: app)
    XCTAssertTrue(activation.waitForExistence(timeout: 5))
    XCTAssertEqual(activation.value as? String, "RUNTIME READY")

    let runTrace = reveal("product-runtime-run-trace", in: app)
    XCTAssertTrue(runTrace.isEnabled)
    runTrace.tap()

    let surface = element("product-runtime-driving-surface", in: app)
    XCTAssertTrue(surface.waitForExistence(timeout: 5))
    let identity = surface.value as? String ?? ""
    XCTAssertTrue(identity.contains("test.occurrence.entry"))
    XCTAssertTrue(identity.contains("test.occurrence.loop-movement-1"))
    XCTAssertTrue(identity.contains("test.prompt.loop-1"))
    XCTAssertTrue(identity.contains("VOICE_EVENT"))

    let presentationState = element(
      "product-runtime-presentation-state",
      in: app
    )
    XCTAssertEqual(
      presentationState.value as? String,
      "ACTOR FRAME READY"
    )
    XCTAssertFalse(runTrace.isEnabled)

    let input = element("product-runtime-input", in: app)
    XCTAssertEqual(input.value as? String, "MATCHER · HIGH")
    XCTAssertEqual(
      element("product-runtime-driving-passage", in: app).value as? String,
      "NO_KNOWN_CONFLICT_REALTIME_UNCONFIRMED"
    )

    _ = reveal("product-runtime-driving-guidance", in: app)
    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = "Actor-owned product runtime driving surface"
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
