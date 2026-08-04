import Foundation
import KaidoRouting
import Testing

@Suite("Whole Shuto network")
struct ShutoNetworkTests {
  @Test("bundled database covers every official route and usable IC")
  func validatesWholeNetworkCoverage() throws {
    let database = try loadDatabase()

    try database.validate()
    #expect(database.routes.count == 26)
    #expect(database.directionalFacilities.count == 151)
    #expect(database.junctions.count == 39)
    #expect(
      database.junctions.allSatisfy {
        $0.officialDetailReference.hasPrefix("https://www.shutoko.jp/")
          && $0.officialDetailSHA256.count == 64
      }
    )
    #expect(database.parkingAreas.count == 19)
    #expect(database.edges.count == 24_299)
    #expect(
      database.directionalFacilities
        .filter { $0.operationalStatus == "AVAILABLE" }
        .allSatisfy { $0.geometryMatchState == "CANDIDATE_MATCHED" }
    )
    let yaesu = try #require(
      database.routes.first { $0.routeID == "Y" }
    )
    #expect(yaesu.operationalStatus == "LONG_TERM_CLOSED")
  }

  @Test("planner crosses the network without mutating directional facilities")
  func plansCrossNetworkRoute() throws {
    let database = try loadDatabase()
    let planner = try ShutoRoutePlanner(database: database)

    let route = try planner.plan(
      entryFacilityID: "shuto.ic.3.shibuya",
      exitFacilityID: "shuto.ic.k1.minatomirai"
    )

    #expect(route.routePlan.entryFacilityID == "shuto.ic.3.shibuya")
    #expect(route.routePlan.exitFacilityID == "shuto.ic.k1.minatomirai")
    #expect(route.edges.count > 50)
    #expect(route.coordinates.count == route.edges.count + 1)
    #expect(route.distanceMeters > 20_000)
    #expect(route.routeIDsInOrder.contains("3"))
    #expect(route.routeIDsInOrder.contains("K1"))
    #expect(
      route.routePlan.occurrences.map(\.entityID)
        == route.edges.map(\.edgeID)
    )
  }

  @Test("arbitrary places produce ranked entry and exit recommendations")
  func recommendsFacilitiesForArbitraryPlaces() throws {
    let database = try loadDatabase()
    let planner = try ShutoRoutePlanner(database: database)

    let recommendations = try planner.recommend(
      from: ShutoCoordinate(
        latitude: 35.681236,
        longitude: 139.767125
      ),
      to: ShutoCoordinate(
        latitude: 35.443708,
        longitude: 139.646794
      )
    )

    #expect(!recommendations.isEmpty)
    #expect(recommendations.count <= 3)
    #expect(
      recommendations.allSatisfy {
        $0.route.entryFacility.canEnter && $0.route.exitFacility.canExit
      }
    )
    #expect(
      recommendations.map(\.totalScoreMeters)
        == recommendations.map(\.totalScoreMeters).sorted()
    )
  }

  private func loadDatabase() throws -> ShutoNetworkDatabase {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let url = repositoryRoot
      .appendingPathComponent("data")
      .appendingPathComponent("route-atlas")
      .appendingPathComponent("osm-derived")
      .appendingPathComponent("shuto-whole-network-20260803.json")
    return try JSONDecoder().decode(
      ShutoNetworkDatabase.self,
      from: Data(contentsOf: url)
    )
  }
}
