import XCTest

@MainActor
final class ProviderGuidedDriveUITests: XCTestCase {
  func testPlaceListsEveryWayAndAProviderRouteDrivesWithoutReview() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-WHOLE-SHUTO-SEARCH-PREVIEW", "-WHOLE-SHUTO-PROVIDER-ROUTES",
      "-app.kaidoroutes.language.interface", "zh-Hans",
    ]
    app.launchSilently()

    let toggle = app.descendants(matching: .any)["whole-shuto-destination-toggle"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 8))
    toggle.tap()
    let field = app.textFields["whole-shuto-destination-search"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("东京塔")
    let place = app.buttons["whole-shuto-place-suggestion-preview.tokyo-tower"]
    XCTAssertTrue(place.waitForExistence(timeout: 5))
    place.tap()

    // The provider's own route and Kaido's routes share one list, fastest
    // first, without saying who guides which.
    let provider = app.buttons["destination-route-option-0"]
    XCTAssertTrue(provider.waitForExistence(timeout: 15))
    XCTAssertTrue(provider.label.contains("国道15号"), provider.label)
    XCTAssertTrue(app.buttons["destination-route-option-1"].exists)
    XCTAssertFalse(app.staticTexts["普通导航"].exists)
    let list = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    list.name = "Destination route list"
    list.lifetime = .keepAlways
    add(list)

    app.buttons["destination-route-go"].tap()
    let instruction = app.staticTexts["provider-drive-instruction"]
    XCTAssertTrue(instruction.waitForExistence(timeout: 8))
    XCTAssertFalse(app.descendants(matching: .any)["whole-shuto-journey-review"].exists)
    let drive = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    drive.name = "Provider-guided drive"
    drive.lifetime = .keepAlways
    add(drive)

    app.buttons["provider-drive-end"].tap()
    XCTAssertTrue(toggle.waitForExistence(timeout: 5))
    XCTAssertFalse(app.descendants(matching: .any)["provider-drive"].exists)
  }
}
