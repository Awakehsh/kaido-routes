import XCTest

@testable import KaidoRoutesApp

final class RouteAtlasAttributionTests: XCTestCase {
  func testBundledCatalogCoversEveryAtlasWithNativeVisibleLinks() throws {
    let catalog = try RouteAtlasAttributionCatalog.bundled()

    XCTAssertEqual(
      catalog.catalogID,
      "kaido.route-atlas-attribution.2026-07-24"
    )
    for mode in RouteAtlasMode.allCases {
      let attribution = catalog.attribution(for: mode)
      XCTAssertEqual(attribution.mode, mode)
      XCTAssertEqual(attribution.resourceName, mode.resourceName)
      XCTAssertEqual(
        attribution.sourceAccessibilityIdentifier,
        "route-atlas-attribution-source"
      )
      XCTAssertEqual(
        attribution.licenceAccessibilityIdentifier,
        "route-atlas-attribution-licence"
      )
    }

    let k7 = catalog.attribution(for: .k7Evidence)
    XCTAssertEqual(k7.attribution, "© OpenStreetMap contributors")
    XCTAssertEqual(
      k7.sourceURL.absoluteString,
      "https://www.openstreetmap.org/copyright"
    )
    XCTAssertEqual(k7.licenceIdentifier, "ODbL-1.0")
    XCTAssertEqual(
      k7.licenceURL.absoluteString,
      "https://opendatacommons.org/licenses/odbl/1-0/"
    )
  }

  func testK7LicenceURLDriftFailsClosed() throws {
    let resourceURL = try XCTUnwrap(
      Bundle.main.url(
        forResource: RouteAtlasAttributionCatalog.resourceName,
        withExtension: "json"
      )
    )
    var document = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: resourceURL))
        as? [String: Any]
    )
    var entries = try XCTUnwrap(document["entries"] as? [[String: Any]])
    let index = try XCTUnwrap(
      entries.firstIndex { $0["mode_id"] as? String == "k7Evidence" }
    )
    entries[index]["licence_url"] = "https://example.invalid/licence"
    document["entries"] = entries

    XCTAssertThrowsError(
      try RouteAtlasAttributionCatalog.decode(
        JSONSerialization.data(withJSONObject: document)
      )
    ) { error in
      guard
        case .invalidCatalog(let issues) =
          error as? RouteAtlasAttributionCatalogError
      else {
        XCTFail("Expected invalid-catalog error, got \(error)")
        return
      }
      XCTAssertTrue(
        issues.contains("attribution evidence drift for k7Evidence")
      )
    }
  }
}
