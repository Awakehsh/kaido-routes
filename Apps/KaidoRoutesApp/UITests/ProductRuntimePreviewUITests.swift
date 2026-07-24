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
}
