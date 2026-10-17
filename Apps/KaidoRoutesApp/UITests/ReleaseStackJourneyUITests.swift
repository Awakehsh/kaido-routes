import XCTest

/// Drives the Release app from the home through route choice, review, the
/// start of a live drive and its end, on the real path: Release ignores the
/// launch arguments the Debug journeys use. The `iPhone Release stack` CI job
/// runs it against a build linked with the iPhone's main-thread stack size
/// and reads the stack's high-water mark at the end.
@MainActor
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
    let startCircuit = element("whole-shuto-start-circuit", in: app)
    tap(circuit, until: startCircuit, step: "route card")
    waitUntilEnabled(startCircuit)
    assertRunning(app, after: "route choice")

    let startLiveDrive = app.buttons["whole-shuto-start-live-drive"]
    tap(startCircuit, until: startLiveDrive, step: "use this route")
    waitUntilEnabled(startLiveDrive)
    assertRunning(app, after: "review")

    let endJourney = element("whole-shuto-end-journey", in: app)
    tap(startLiveDrive, until: endJourney, step: "start live drive")
    assertRunning(app, after: "start of the live drive")

    // The confirmation's destructive action carries the same label as the
    // button that asks for it, in whatever language the simulator runs.
    let endLabel = endJourney.label
    let confirmation = app.alerts.firstMatch
    tap(endJourney, until: confirmation, step: "end drive")
    tap(
      confirmation.buttons[endLabel],
      until: element("whole-shuto-planning-dock", in: app),
      step: "confirm end")
    assertRunning(app, after: "end of the drive")

    // The job reads the stack's high-water mark from outside once this
    // activity starts. The mark only grows, so one reading here covers every
    // screen before it; vmmap suspends the app while it reads, which is why
    // it waits for this idle hold instead of sampling throughout. A reading
    // took 16-93 s on CI, so the hold ends when the job posts that it is done;
    // the timeout only fails a job that never does.
    let read = XCTestExpectation(description: "the job read the main-thread stack")
    read.assertForOverFulfill = false
    let center = CFNotificationCenterGetDarwinNotifyCenter()
    let observer = Unmanaged.passUnretained(read).toOpaque()
    CFNotificationCenterAddObserver(
      center, observer,
      { _, observer, _, _, _ in
        guard let observer else { return }
        Unmanaged<XCTestExpectation>.fromOpaque(observer).takeUnretainedValue().fulfill()
      },
      Self.stackReadNotification as CFString, nil, .deliverImmediately)
    defer { CFNotificationCenterRemoveEveryObserver(center, observer) }
    XCTContext.runActivity(named: "Hold the last screen for the stack reading") { _ in
      XCTAssertEqual(
        XCTWaiter.wait(for: [read], timeout: 180), .completed,
        "the job did not signal that it read the main-thread stack")
    }
  }

  /// Posted by the `iPhone Release stack` job, inside the simulator, once it
  /// has read the main-thread stack.
  private static let stackReadNotification = "app.kaidoroutes.release-stack.read"

  /// Taps `control` and waits for the element the tap opens, tapping again
  /// while `control` is still on screen and hittable. On a starved CI runner a
  /// synthesized tap can land on a still screen and do nothing: in run
  /// 39033273128 the C1 card was tapped at the frame it still had, after the
  /// app took 21 s to answer the element query, and the screen stayed on the
  /// catalog. A tap that took effect has replaced or covered `control`, so it
  /// is never repeated, and a control that never responds still fails after
  /// the last attempt.
  ///
  /// This is a fallback for XCUITest's event delivery, not for the app: every
  /// retap is attached as a screenshot and printed as a `RELEASE-JOURNEY-RETAP`
  /// line, which the CI job copies into its summary, so a rising retap rate is
  /// seen rather than absorbed.
  private func tap(
    _ control: XCUIElement, until opened: XCUIElement, step: String, attempts: Int = 3
  ) {
    for attempt in 1...attempts {
      if attempt > 1 {
        guard control.exists, control.isHittable else { break }
        let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screen.name = "Retap \(step), attempt \(attempt)"
        screen.lifetime = .keepAlways
        add(screen)
        print("RELEASE-JOURNEY-RETAP step=\(step) attempt=\(attempt)")
      }
      control.tap()
      allowLocationIfAsked()
      if opened.waitForExistence(timeout: 15) { return }
    }
    XCTFail("\(opened) did not appear after tapping \(control)")
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
