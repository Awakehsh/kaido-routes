import XCTest

@MainActor
final class KaidoProductJourneyUITests: XCTestCase {
  func testDefaultLaunchPresentsOrderedRouteFirstJourney() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
    ]
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
    app.launchArguments = [
      "-PRODUCT-JOURNEY-REVIEW-PREVIEW",
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
    ]
    app.launch()

    let stage = element("product-journey-stage", in: app)
    XCTAssertTrue(stage.waitForExistence(timeout: 5))
    XCTAssertEqual(stage.value as? String, "REVIEW")

    let voiceCheck = reveal(
      "product-journey-voice-check",
      in: app
    )
    XCTAssertTrue(voiceCheck.exists)
    XCTAssertTrue(
      element("voice-check-profile-menu", in: app).exists
    )
    XCTAssertTrue(
      element("voice-check-status", in: app).exists
    )
    XCTAssertTrue(
      element("voice-check-audition", in: app).isEnabled
    )
    XCTAssertTrue(
      element("voice-check-language-ja-JP", in: app).isSelected
    )
    XCTAssertEqual(
      element("voice-check-sample", in: app).value as? String,
      "左側を進み、ビー わんがんせん、横浜方面へ。"
    )

    let chineseVoice = element(
      "voice-check-language-zh-Hans",
      in: app
    )
    chineseVoice.tap()
    XCTAssertTrue(chineseVoice.isSelected)
    XCTAssertEqual(
      element("voice-check-sample", in: app).value as? String,
      "保持左侧，跟随 B 路线 湾岸线，横滨方向。"
    )

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

  func testInterfaceLanguageSwitchesWithoutChangingGuidanceVoice() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-PRODUCT-JOURNEY-REVIEW-PREVIEW",
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
    ]
    app.launch()

    let header = element("product-journey-header", in: app)
    XCTAssertTrue(header.waitForExistence(timeout: 5))
    XCTAssertEqual(
      header.label,
      "Kaido Routes。先选路，再出发。当前步骤行前确认。"
    )

    let english = element(
      "product-journey-interface-language-en",
      in: app
    )
    XCTAssertTrue(english.exists)
    english.tap()

    XCTAssertTrue(english.isSelected)
    XCTAssertEqual(
      header.label,
      "Kaido Routes. Choose the route, then drive. Current step: Pre-drive review."
    )
    XCTAssertEqual(
      element("product-journey-interface-language", in: app).value as? String,
      "en"
    )

    let voiceCheck = reveal("product-journey-voice-check", in: app)
    XCTAssertTrue(voiceCheck.exists)
    XCTAssertTrue(
      element("voice-check-language-ja-JP", in: app).isSelected
    )
    XCTAssertEqual(
      element("voice-check-sample", in: app).value as? String,
      "左側を進み、ビー わんがんせん、横浜方面へ。"
    )
  }

  func testSavedRouteLifecycleRemainsLocalAndReleaseGated() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-SAVED-ROUTE-LIBRARY-PREVIEW",
      "-app.kaidoroutes.language.interface",
      "en",
    ]
    app.launch()

    let stage = element("product-journey-stage", in: app)
    XCTAssertTrue(stage.waitForExistence(timeout: 5))
    XCTAssertEqual(stage.value as? String, "REVIEW")

    _ = reveal("saved-route-save-panel", in: app)
    let name = element("saved-route-name", in: app)
    name.tap()
    name.typeText("Night loop")
    let returnKey = app.keyboards.buttons["return"]
    XCTAssertTrue(returnKey.exists)
    returnKey.tap()

    let save = reveal("saved-route-save", in: app)
    XCTAssertTrue(save.isEnabled)
    save.tap()
    XCTAssertTrue(
      element("saved-route-save-success", in: app)
        .waitForExistence(timeout: 5)
    )

    element("product-journey-back", in: app).tap()
    XCTAssertEqual(stage.value as? String, "AUTHORING")
    element("product-journey-step-atlas", in: app).tap()
    XCTAssertEqual(stage.value as? String, "ATLAS")

    let library = reveal("saved-route-library", in: app)
    XCTAssertTrue((library.value as? String)?.hasPrefix("1 RECORDS") == true)
    let savedName = app.staticTexts["Night loop"]
    XCTAssertTrue(savedName.exists)
    for _ in 0..<8 where !savedName.isHittable {
      app.swipeUp()
    }
    XCTAssertTrue(savedName.isHittable)
    let open = app.buttons["Open in parked editor"]
    XCTAssertTrue(open.exists)
    XCTAssertFalse(open.isEnabled)
    XCTAssertTrue(app.staticTexts["REVIEW REQUIRED"].exists)

    let screenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    screenshot.name = "Saved route remains release-gated"
    screenshot.lifetime = .keepAlways
    add(screenshot)

    XCTAssertTrue(
      element("saved-route-import", in: app).exists
    )
    XCTAssertTrue(app.buttons["Export"].exists)
    let rename = app.buttons["Rename"]
    XCTAssertTrue(rename.exists)
    rename.tap()

    let renameAlert = app.alerts["Rename route"]
    XCTAssertTrue(renameAlert.waitForExistence(timeout: 2))
    let renameField = renameAlert.textFields.firstMatch
    XCTAssertTrue(renameField.exists)
    renameField.tap()
    renameField.typeText(
      String(
        repeating: XCUIKeyboardKey.delete.rawValue,
        count: 32
      )
    )
    renameField.typeText("Renamed night loop")
    renameAlert.buttons["Save"].tap()

    let renamed = app.staticTexts["Renamed night loop"]
    XCTAssertTrue(renamed.waitForExistence(timeout: 2))
    XCTAssertFalse(app.staticTexts["Night loop"].exists)
    XCTAssertTrue(app.staticTexts["REVIEW REQUIRED"].exists)

    let renamedScreenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    renamedScreenshot.name =
      "Renamed route preserves release gate"
    renamedScreenshot.lifetime = .keepAlways
    add(renamedScreenshot)

    app.buttons["Delete"].tap()
    let confirmation = app.sheets.firstMatch
    XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
    confirmation.buttons["Delete"].tap()

    XCTAssertTrue(
      element("saved-route-library-empty", in: app)
        .waitForExistence(timeout: 2)
    )
    XCTAssertFalse(renamed.exists)
    XCTAssertTrue(
      (library.value as? String)?.hasPrefix("0 RECORDS")
        == true
    )
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
