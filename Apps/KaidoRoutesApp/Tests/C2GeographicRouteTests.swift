import XCTest

@testable import KaidoRoutesApp

final class C2GeographicRouteTests: XCTestCase {
  func testBundledRoutePreservesReviewedDirectionalSegments() throws {
    let route = try C2GeographicRoute.bundled()

    XCTAssertEqual(route.schemaVersion, "1.0")
    XCTAssertEqual(
      route.databaseID,
      "kaido.c2-b-geographic-route.2026-07-29"
    )
    XCTAssertEqual(
      route.segments.map(\.routeShield),
      ["C2", "C2→B", "B", "C2"]
    )
    XCTAssertEqual(
      route.segments.map(\.checkpointNodeIDs),
      [
        [
          919_617_341, 263_988_109, 309_609_006, 370_270_206,
          370_270_524, 31_330_124,
        ],
        [31_330_124, 31_330_101],
        [31_330_101, 31_300_491, 31_288_811, 6_534_476_215],
        [6_534_476_215, 3_387_909_708, 13_359_168_654],
      ]
    )
    XCTAssertTrue(route.segments[1].wayIDs.contains(574_211_697))
    XCTAssertEqual(route.licence.identifier, "ODbL-1.0")
    XCTAssertEqual(
      route.licence.attribution,
      "© OpenStreetMap contributors"
    )
  }

  func testGeographicRouteStaysBoundToOfficialFacilityPoints() throws {
    let route = try C2GeographicRoute.bundled()

    XCTAssertLessThanOrEqual(
      route.operatorFacilities.entrance.osmBoundaryDistanceMeters,
      25
    )
    XCTAssertLessThanOrEqual(
      route.operatorFacilities.exit.osmBoundaryDistanceMeters,
      25
    )
    XCTAssertEqual(
      route.operatorFacilities.entrance.coordinate.latitude,
      C2NavigationDemoModel.tomigayaEntranceCoordinate.latitude,
      accuracy: 0.000000001
    )
    XCTAssertEqual(
      route.operatorFacilities.exit.coordinate.longitude,
      C2NavigationDemoModel.hatsudaiMinamiExitCoordinate.longitude,
      accuracy: 0.000000001
    )
    XCTAssertEqual(route.totalDistanceMeters, 57_376.201, accuracy: 0.001)
  }

  func testProgressCoordinateMovesAcrossTheWholeRoute() throws {
    let route = try C2GeographicRoute.bundled()

    let start = try XCTUnwrap(route.coordinate(at: 0))
    let middle = try XCTUnwrap(route.coordinate(at: 0.5))
    let finish = try XCTUnwrap(route.coordinate(at: 1))

    XCTAssertNotEqual(start, middle)
    XCTAssertNotEqual(middle, finish)
    XCTAssertEqual(
      start,
      route.segments.first?.coordinates.first
    )
    XCTAssertEqual(
      finish,
      route.segments.last?.coordinates.last
    )
  }
}
