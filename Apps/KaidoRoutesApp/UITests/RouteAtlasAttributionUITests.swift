import XCTest

@MainActor
final class RouteAtlasAttributionUITests: XCTestCase {
  func testK7MapDoesNotRepeatSourceAndLicenceLinks() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-ROUTE-ATLAS-ATTRIBUTION-PREVIEW",
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
    ]
    app.launchSilently()

    XCTAssertTrue(
      app.descendants(matching: .any)["route-atlas-attribution-preview"]
        .waitForExistence(timeout: 5)
    )
    XCTAssertFalse(
      app.descendants(matching: .any)["route-atlas-attribution-strip"]
        .exists
    )
    XCTAssertFalse(
      app.descendants(matching: .any)["route-atlas-attribution-source"]
        .exists
    )
    XCTAssertFalse(
      app.descendants(matching: .any)["route-atlas-attribution-licence"]
        .exists
    )
  }
}
