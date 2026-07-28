import XCTest

@MainActor
final class PhysicalAudioQualificationUITests: XCTestCase {
  func testInstalledVoicesCompleteThroughTheVoicePromptOutputRoute() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-PHYSICAL-AUDIO-QUALIFICATION"]
    app.launch()

    let status = app.descendants(matching: .any)[
      "physical-audio-qualification-status"
    ]
    XCTAssertTrue(status.waitForExistence(timeout: 5))
    XCTAssertEqual(status.value as? String, "READY")

    let start = app.buttons["physical-audio-qualification-start"]
    XCTAssertTrue(start.isEnabled)
    start.tap()

    let passed = NSPredicate(
      format: "value BEGINSWITH %@",
      "PASSED ·"
    )
    expectation(for: passed, evaluatedWith: status)
    waitForExpectations(timeout: 45)

    let value = status.value as? String ?? ""
    XCTAssertTrue(value.contains("ja-JP:"))
    XCTAssertTrue(value.contains("zh-CN:"))
    XCTAssertTrue(value.contains("en-US:"))
    XCTAssertFalse(value.contains("BLOCKED"))
  }
}
