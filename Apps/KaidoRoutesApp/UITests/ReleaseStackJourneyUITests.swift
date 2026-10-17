import XCTest

/// Drives the Release app from the home through route choice, review, the
/// start of a live drive and its end, on the real path: Release ignores the
/// launch arguments the Debug journeys use. The `iPhone Release stack` CI job
/// runs it against a build linked with the iPhone's main-thread stack size
/// and samples the stack's high-water mark while it runs.
final class ReleaseStackJourneyUITests: XCTestCase {
  func testHomeRouteReviewStartAndEnd() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()

    XCTAssertTrue(element("whole-shuto-product", in: app).waitForExistence(timeout: 30))
    allowLocationIfAsked()
    assertRunning(app, after: "home")

    let circuit = element("whole-shuto-circuit-option-shuto.circuit.c1-inner", in: app)
    XCTAssertTrue(circuit.waitForExistence(timeout: 30))
    circuit.tap()
    allowLocationIfAsked()
    let startCircuit = element("whole-shuto-start-circuit", in: app)
    XCTAssertTrue(startCircuit.waitForExistence(timeout: 10))
    waitUntilEnabled(startCircuit)
    assertRunning(app, after: "route choice")

    startCircuit.tap()
    XCTAssertTrue(element("whole-shuto-journey-review", in: app).waitForExistence(timeout: 15))
    let startLiveDrive = app.buttons["whole-shuto-start-live-drive"]
    XCTAssertTrue(startLiveDrive.waitForExistence(timeout: 10))
    waitUntilEnabled(startLiveDrive)
    assertRunning(app, after: "review")

    startLiveDrive.tap()
    allowLocationIfAsked()
    XCTAssertTrue(startLiveDrive.waitForNonExistence(timeout: 15))
    let endJourney = element("whole-shuto-end-journey", in: app)
    XCTAssertTrue(endJourney.waitForExistence(timeout: 15))
    assertRunning(app, after: "start of the live drive")

    endJourney.tap()
    let confirmation = app.alerts.firstMatch
    XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
    // The destructive "end" action is the alert's second button.
    confirmation.buttons.element(boundBy: 1).tap()
    XCTAssertTrue(endJourney.waitForNonExistence(timeout: 15))
    assertRunning(app, after: "end of the drive")
  }

  /// A fresh simulator asks for location the first time the app wants it.
  private func allowLocationIfAsked() {
    let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
    // Allow once, allow while using, don't allow.
    if alert.waitForExistence(timeout: 3) { alert.buttons.element(boundBy: 1).tap() }
  }

  private func waitUntilEnabled(_ element: XCUIElement) {
    let enabled = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "isEnabled == true"), object: element)
    XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 30), .completed)
  }

  private func assertRunning(_ app: XCUIApplication, after step: String) {
    XCTAssertEqual(app.state, .runningForeground, "the app is not running after \(step)")
  }

  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }
}
