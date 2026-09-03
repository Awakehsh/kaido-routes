import XCTest

@MainActor
final class ProductRuntimePreviewUITests: XCTestCase {
  func testRouteAtlasOverlayKeepsRepeatedOccurrencesSeparate() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-PRODUCT-RUNTIME-PREVIEW"]
    app.launchSilently()

    let activation = element("product-runtime-activation", in: app)
    XCTAssertTrue(activation.waitForExistence(timeout: 5))
    XCTAssertEqual(activation.value as? String, "RUNTIME READY")

    let overlay = reveal("released-route-atlas-overlay", in: app)
    let value = overlay.value as? String ?? ""
    XCTAssertTrue(
      value.contains("test.occurrence.entry:CURRENT:1/3")
    )
    XCTAssertTrue(
      value.contains("test.occurrence.loop-edge-1:FUTURE:2/3")
    )
    XCTAssertTrue(
      value.contains("test.occurrence.loop-edge-2:FUTURE:3/3")
    )
    XCTAssertTrue(
      element("released-route-atlas-repetition", in: app).exists
    )
    XCTAssertTrue(
      element("released-route-atlas-attribution", in: app).exists
    )

    let screenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    screenshot.name = "Occurrence-aware Route Atlas overlay"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  func testJointReleaseStartsPlanningWithStrictEntryLocked() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-PRODUCT-RUNTIME-PREVIEW"]
    app.launchSilently()

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

    let safety = element("product-runtime-safety", in: app)
    for _ in 0..<12 where !safety.exists {
      app.swipeUp()
    }
    XCTAssertTrue(safety.exists)

    let lifecycle = app.descendants(matching: .any)[
      "product-runtime-lifecycle"
    ]
    XCTAssertTrue(lifecycle.waitForExistence(timeout: 2))
    XCTAssertEqual(lifecycle.value as? String, "FOREGROUND")

    let liveLocation = reveal("product-runtime-live-location", in: app)
    XCTAssertEqual(
      liveLocation.value as? String,
      "LIVE LOCATION BLOCKED"
    )
    XCTAssertFalse(
      element("product-runtime-start-live-location", in: app).isEnabled
    )
    XCTAssertEqual(app.alerts.count, 0)

    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = "Synthetic live location authority blocked"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  func testSyntheticTraceRendersTheActorOwnedPhoneProjection() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-PRODUCT-RUNTIME-PREVIEW"]
    app.launchSilently()

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

    let speech = reveal("product-runtime-speech", in: app)
    let speechValue = speech.value as? String ?? ""
    XCTAssertTrue(speechValue.contains("ja-JP"), speechValue)
    XCTAssertTrue(
      ["DEFAULT", "ENHANCED", "PREMIUM"].contains {
        speechValue.contains($0)
      }
    )

    _ = reveal("product-runtime-driving-guidance", in: app)
    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = "Actor-owned product runtime driving surface"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  func testFullRouteSimulationCanStepAndReset() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-PRODUCT-RUNTIME-PREVIEW"]
    app.launchSilently()

    let activation = element("product-runtime-activation", in: app)
    XCTAssertTrue(activation.waitForExistence(timeout: 5))
    XCTAssertEqual(activation.value as? String, "RUNTIME READY")

    let simulation = element("product-runtime-simulation", in: app)
    XCTAssertTrue(simulation.waitForExistence(timeout: 2))
    XCTAssertEqual(simulation.value as? String, "READY")

    let step = reveal("product-runtime-simulation-step", in: app)
    XCTAssertTrue(step.isEnabled)
    step.tap()

    let paused = NSPredicate(format: "value == %@", "PAUSED")
    expectation(for: paused, evaluatedWith: simulation)
    waitForExpectations(timeout: 5)
    XCTAssertTrue(
      (element("product-runtime-snapshot", in: app).value as? String)?
        .contains("STRICT_ROUTE") == true
    )

    let reset = reveal("product-runtime-simulation-reset", in: app)
    XCTAssertTrue(reset.isEnabled)
    reset.tap()

    let ready = NSPredicate(format: "value == %@", "READY")
    expectation(for: ready, evaluatedWith: simulation)
    waitForExpectations(timeout: 5)
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
    for _ in 0..<12 where !target.isHittable {
      app.swipeDown()
    }
    XCTAssertTrue(target.isHittable, "\(identifier) did not become visible")
    return target
  }
}
