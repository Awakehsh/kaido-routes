import XCTest

@MainActor
final class KRU03CorridorUITests: XCTestCase {
  func testFreehandGestureRequiresExplicitReviewedCandidate() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-KR-U03-CORRIDOR-PREVIEW"]
    app.launch()

    let panel = app.descendants(matching: .any)["kr-u03-editor-panel"]
    XCTAssertTrue(panel.waitForExistence(timeout: 5))

    let drawPad = app.buttons["corridor-draw-pad"]
    XCTAssertTrue(drawPad.waitForExistence(timeout: 2))
    drawPad.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.65))
      .press(
        forDuration: 0.1,
        thenDragTo: drawPad.coordinate(
          withNormalizedOffset: CGVector(dx: 0.8, dy: 0.85)
        )
      )

    let resolution = app.descendants(matching: .any)["corridor-resolution-card"]
    XCTAssertTrue(resolution.waitForExistence(timeout: 2))
    XCTAssertEqual(resolution.value as? String, "RESOLUTION_REQUIRED")
    XCTAssertFalse(app.buttons["route-editor-compile"].isEnabled)

    let firstCandidate = app.buttons["corridor-candidate-0"]
    XCTAssertTrue(firstCandidate.waitForExistence(timeout: 2))
    firstCandidate.tap()

    let receipt = app.descendants(matching: .any)["corridor-resolution-selected"]
    XCTAssertTrue(receipt.waitForExistence(timeout: 2))
    XCTAssertTrue(receipt.label.contains("preview.synthetic.choice.enter-loop"))
    XCTAssertEqual(
      app.descendants(matching: .any)["route-editor-current-decision"].value
        as? String,
      "preview.synthetic.decision.loop"
    )
    XCTAssertFalse(app.buttons["route-editor-compile"].isEnabled)
  }
}
