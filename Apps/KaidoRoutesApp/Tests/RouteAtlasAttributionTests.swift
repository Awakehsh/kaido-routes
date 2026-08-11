import KaidoRouting
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

  func testWholeShutoAttributionComesFromExactBundledMetadata() throws {
    let attribution = try WholeShutoAttribution(
      database: WholeShutoNetworkCatalog.bundled()
    )

    XCTAssertEqual(
      attribution.resourceName,
      "shuto-whole-network-20260804"
    )
    XCTAssertEqual(
      attribution.databaseID,
      "kaido.shuto.whole-network.2026-08-04"
    )
    XCTAssertEqual(
      attribution.networkSnapshotID,
      "shuto-official-2026-07-29-osm-2026-08-04"
    )
    XCTAssertEqual(attribution.attribution, "© OpenStreetMap contributors")
    XCTAssertEqual(
      attribution.sourceURL.absoluteString,
      "https://www.openstreetmap.org/copyright"
    )
    XCTAssertEqual(attribution.licenceIdentifier, "ODbL-1.0")
    XCTAssertEqual(
      attribution.licenceURL.absoluteString,
      "https://opendatacommons.org/licenses/odbl/1-0/"
    )
    XCTAssertEqual(
      attribution.sourceAccessibilityIdentifier,
      "route-atlas-attribution-source"
    )
    XCTAssertEqual(
      attribution.licenceAccessibilityIdentifier,
      "route-atlas-attribution-licence"
    )
    XCTAssertFalse(attribution.navigationAuthority)
  }

  func testWholeShutoAttributionRejectsNetworkIdentityDrift() throws {
    let resourceURL = try XCTUnwrap(
      Bundle.main.url(
        forResource: WholeShutoAttribution.resourceName,
        withExtension: "json"
      )
    )
    var document = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: resourceURL))
        as? [String: Any]
    )
    document["database_id"] = "kaido.shuto.unreviewed"
    let database = try JSONDecoder().decode(
      ShutoNetworkDatabase.self,
      from: JSONSerialization.data(withJSONObject: document)
    )

    XCTAssertThrowsError(try WholeShutoAttribution(database: database)) {
      error in
      XCTAssertEqual(
        error as? WholeShutoAttributionError,
        .identityDrift(["database identity drift"])
      )
    }
  }
}
