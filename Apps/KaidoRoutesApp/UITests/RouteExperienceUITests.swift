import XCTest

@MainActor
final class RouteExperienceUITests: XCTestCase {
  func testDayAndNightCatalogExposeRouteReferences() throws {
    for appearance in ["day", "night"] {
      let app = XCUIApplication()
      app.launchArguments = [
        "-RESET-NAVIGATION-CHECKPOINT",
        "-app.kaidoroutes.language.interface", "en",
        "-app.kaidoroutes.map.appearance", appearance,
      ]
      app.launchSilently()
      let metrics = app.descendants(matching: .any)
        .matching(identifier: "whole-shuto-circuit-metrics-shuto.circuit.c1-inner").firstMatch
      XCTAssertTrue(metrics.waitForExistence(timeout: 15))
      XCTAssertTrue(metrics.label.contains("min"))
      XCTAssertTrue(app.staticTexts["Shuto reference · excludes access roads and live traffic"].exists)
      let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
      screenshot.name = "Route catalog - \(appearance)"
      screenshot.lifetime = .keepAlways
      add(screenshot)
      app.terminate()
    }
  }
}
