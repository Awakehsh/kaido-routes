import XCTest

@MainActor
final class RouteAtlasAttributionUITests: XCTestCase {
  func testK7AttributionIsVisibleBesideMapWithSourceAndLicenceLinks() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-ROUTE-ATLAS-ATTRIBUTION-PREVIEW"]
    app.launch()

    let strip = app.descendants(matching: .any)[
      "route-atlas-attribution-strip"
    ]
    XCTAssertTrue(strip.waitForExistence(timeout: 5))
    XCTAssertEqual(
      strip.value as? String,
      "ALWAYS_VISIBLE · ADJACENT_TO_MAP · NATIVE_LINKS"
    )

    let source = app.descendants(matching: .any)[
      "route-atlas-attribution-source"
    ]
    XCTAssertTrue(source.waitForExistence(timeout: 2))
    XCTAssertTrue(source.isHittable)
    XCTAssertEqual(
      source.label,
      "地图数据来源，© OpenStreetMap contributors"
    )

    let licence = app.descendants(matching: .any)[
      "route-atlas-attribution-licence"
    ]
    XCTAssertTrue(licence.waitForExistence(timeout: 2))
    XCTAssertTrue(licence.isHittable)
    XCTAssertEqual(licence.label, "数据许可证，ODbL-1.0")
  }
}
