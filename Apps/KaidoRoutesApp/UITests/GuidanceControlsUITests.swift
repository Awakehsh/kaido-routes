import XCTest

@MainActor
final class GuidanceControlsUITests: XCTestCase {
  func testParkedVoiceSettingsExposeVolumeAndSilentAudition() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-RESET-NAVIGATION-CHECKPOINT",
      "-app.kaidoroutes.language.interface", "en",
      "-app.kaidoroutes.guidance.mode", "FULL",
    ]
    app.launchSilently()
    let settings = element("whole-shuto-settings", in: app)
    XCTAssertTrue(settings.waitForExistence(timeout: 10))
    settings.tap()
    element("whole-shuto-voice-settings", in: app).tap()
    XCTAssertTrue(element("whole-shuto-speech-mode", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(element("whole-shuto-speech-volume", in: app).exists)
    XCTAssertTrue(element("whole-shuto-installed-voice", in: app).exists)
    element("whole-shuto-voice-audition", in: app).tap()
    XCTAssertTrue(element("whole-shuto-voice-audition-complete", in: app).waitForExistence(timeout: 5))
  }

  func testNavigationAudioMenuMutesWithoutLeavingTheDrive() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-WHOLE-SHUTO-KASAI-JUNCTION-NAVIGATION-PREVIEW",
      "-app.kaidoroutes.language.interface", "en",
      "-app.kaidoroutes.guidance.mode", "FULL",
    ]
    app.launchSilently()
    let voice = element("whole-shuto-guidance-speech", in: app)
    XCTAssertTrue(voice.waitForExistence(timeout: 10))
    voice.tap()
    app.buttons["Muted"].tap()
    XCTAssertTrue((voice.value as? String ?? "").contains("Muted"))
    XCTAssertTrue(element("whole-shuto-guidance-card", in: app).exists)
    voice.tap()
    XCTAssertFalse(app.buttons["Repeat current direction"].isEnabled)
    app.buttons["Full guidance"].tap()
    XCTAssertTrue((voice.value as? String ?? "").contains("Full guidance"))
  }

  func testNavigationMenuAllowsSavedRoutesAndHistoryWithoutParkingPrompt() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-WHOLE-SHUTO-KASAI-JUNCTION-NAVIGATION-PREVIEW",
      "-app.kaidoroutes.language.interface", "en",
    ]
    app.launchSilently()
    let menu = element("whole-shuto-menu", in: app)
    XCTAssertTrue(menu.waitForExistence(timeout: 10))
    XCTAssertTrue(element("whole-shuto-settings", in: app).isEnabled)
    menu.tap()
    app.buttons["Saved routes"].tap()
    XCTAssertTrue(element("whole-shuto-saved-route-sheet", in: app).waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Route saved. Review it when parked."].exists)
    element("whole-shuto-saved-routes-close", in: app).tap()
    XCTAssertTrue(element("whole-shuto-guidance-card", in: app).waitForExistence(timeout: 5))
    menu.tap()
    app.buttons["Drive history"].tap()
    XCTAssertTrue(app.navigationBars["Drive history"].waitForExistence(timeout: 5))
    app.buttons["Done"].tap()
    XCTAssertTrue(element("whole-shuto-guidance-card", in: app).waitForExistence(timeout: 5))
  }

  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }
}
