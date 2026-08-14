import Foundation
import KaidoDomain
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
    #expect(yaesu.officialDirectionsJA == ["北行き", "南行き"])
    #expect(
      database.routes.first { $0.routeID == "C1" }?
        .officialDirectionsJA == ["内回り", "外回り"]
    )
    #expect(
      database.routes.first { $0.routeID == "3" }?
        .officialDirectionsJA == ["上り", "下り"]
    )
  }

  @Test("decoder preserves whole-network bounds, limitations, and source licence")
  func preservesReleaseMetadata() throws {
    let database = try loadDatabase()

    #expect(database.bounds.minimumLatitude == 35.15)
    #expect(database.bounds.maximumLatitude == 36.15)
    #expect(database.bounds.minimumLongitude == 139.1)
    #expect(database.bounds.maximumLongitude == 140.35)
    #expect(database.limitations.count == 3)
    #expect(
      database.limitations.contains {
        $0.contains("not operator-authored lane or vertical-road authority")
      }
    )
    #expect(
      database.sources.officialCatalog.catalogID
        == "kaido.shuto.official-facts.2026-07-29"
    )
    #expect(
      database.sources.facilityCandidateReview.reviewID
        == "shuto-facility-candidate-review-20260815"
    )
    #expect(
      database.sources.facilityCandidateReview.checkedAt == "2026-08-15"
    )
    #expect(
      database.sources.facilityCandidateReview
        .entryBoundaryRebindingCount == 2
    )
    #expect(database.sources.osm.attribution == "© OpenStreetMap contributors")
    #expect(database.sources.osm.licence == "ODbL-1.0")
    #expect(
      database.sources.osm.licenceURI
        == "https://opendatacommons.org/licenses/odbl/1-0/"
    )
    #expect(
      database.sources.osm.sourceURI
        == "https://download.geofabrik.de/asia/japan/kanto-260804.osm.pbf"
    )

    let roundTripped = try JSONDecoder().decode(
      ShutoNetworkDatabase.self,
      from: JSONEncoder().encode(database)
    )
    #expect(roundTripped.bounds == database.bounds)
    #expect(roundTripped.limitations == database.limitations)
    #expect(roundTripped.sources == database.sources)
  }

  @Test("invalid OSM licence metadata fails closed")
  func rejectsInvalidOSMLicenceMetadata() throws {
    var document = try #require(
      JSONSerialization.jsonObject(with: loadDatabaseData())
        as? [String: Any]
    )
    var sources = try #require(document["sources"] as? [String: Any])
    var osm = try #require(sources["osm"] as? [String: Any])
    osm["licence"] = "UNKNOWN"
    sources["osm"] = osm
    document["sources"] = sources
    let database = try JSONDecoder().decode(
      ShutoNetworkDatabase.self,
      from: JSONSerialization.data(withJSONObject: document)
    )

    #expect(throws: ShutoNetworkError.invalidSourceMetadata) {
      try database.validate()
    }
  }

  @Test("invalid OSM licence URI metadata fails closed")
  func rejectsInvalidOSMLicenceURIMetadata() throws {
    var document = try #require(
      JSONSerialization.jsonObject(with: loadDatabaseData())
        as? [String: Any]
    )
    var sources = try #require(document["sources"] as? [String: Any])
    var osm = try #require(sources["osm"] as? [String: Any])
    osm["licence_uri"] = "https://example.com/not-the-odbl"
    sources["osm"] = osm
    document["sources"] = sources
    let database = try JSONDecoder().decode(
      ShutoNetworkDatabase.self,
      from: JSONSerialization.data(withJSONObject: document)
    )

    #expect(throws: ShutoNetworkError.invalidSourceMetadata) {
      try database.validate()
    }
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
    let expectedOccurrenceEntities = route.edges.enumerated().map { index, edge in
      guard index > 0 else { return edge.edgeID }
      return ShutoJunctionMovementCatalog.releasedDefinition(
        database: database,
        incoming: route.edges[index - 1],
        outgoing: edge
      )?.id ?? edge.edgeID
    }
    #expect(route.routePlan.occurrences.map(\.entityID) == expectedOccurrenceEntities)
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

  @Test("saved route restores the exact ordered plan")
  func restoresExactSavedRoute() throws {
    let planner = try ShutoRoutePlanner(database: loadDatabase())
    let planned = try planner.plan(
      entryFacilityID: "shuto.ic.3.shibuya",
      exitFacilityID: "shuto.ic.k1.minatomirai"
    )

    let restored = try planner.restore(routePlan: planned.routePlan)

    #expect(restored == planned)
  }

  @Test("saved circuit restores repeated occurrences without deduplication")
  func restoresRepeatedCircuitOccurrences() throws {
    let planner = try ShutoRoutePlanner(database: loadDatabase())
    let exitFacility = try #require(
      planner.circuitExitCandidates(
        for: .c1Inner,
        afterEntering: "shuto.ic.c1.takaracho"
      ).first
    )
    let planned = try planner.planCircuit(
      circuit: .c1Inner,
      entryFacilityID: "shuto.ic.c1.takaracho",
      exitFacilityID: exitFacility.facilityID,
      laps: 2
    )

    let restored = try planner.restore(routePlan: planned.routePlan)

    #expect(restored == planned)
    #expect(Set(restored.edges.map(\.edgeID)).count < restored.edges.count)
  }

  @Test("saved route restore fails closed on snapshot or occurrence drift")
  func rejectsSavedRouteIdentityDrift() throws {
    let planner = try ShutoRoutePlanner(database: loadDatabase())
    let planned = try planner.plan(
      entryFacilityID: "shuto.ic.3.shibuya",
      exitFacilityID: "shuto.ic.k1.minatomirai"
    )
    let snapshotDrift = RoutePlan(
      id: planned.routePlan.id,
      networkSnapshotID: "superseded-snapshot",
      entryFacilityID: planned.routePlan.entryFacilityID,
      exitFacilityID: planned.routePlan.exitFacilityID,
      recoveryPolicy: planned.routePlan.recoveryPolicy,
      actualDistanceKM: planned.routePlan.actualDistanceKM,
      occurrences: planned.routePlan.occurrences
    )
    var occurrences = planned.routePlan.occurrences
    let original = occurrences[0]
    occurrences[0] = RouteOccurrence(
      id: original.id,
      index: original.index,
      kind: original.kind,
      entityID: "unknown-edge",
      parkingAreaID: original.parkingAreaID,
      tollDomainID: original.tollDomainID,
      isOptional: original.isOptional
    )
    let occurrenceDrift = RoutePlan(
      id: planned.routePlan.id,
      networkSnapshotID: planned.routePlan.networkSnapshotID,
      entryFacilityID: planned.routePlan.entryFacilityID,
      exitFacilityID: planned.routePlan.exitFacilityID,
      recoveryPolicy: planned.routePlan.recoveryPolicy,
      actualDistanceKM: planned.routePlan.actualDistanceKM,
      occurrences: occurrences
    )

    #expect(throws: ShutoNetworkError.routeUnavailable) {
      try planner.restore(routePlan: snapshotDrift)
    }
    #expect(throws: ShutoNetworkError.routeUnavailable) {
      try planner.restore(routePlan: occurrenceDrift)
    }
  }

  private func loadDatabase() throws -> ShutoNetworkDatabase {
    try JSONDecoder().decode(
      ShutoNetworkDatabase.self,
      from: loadDatabaseData()
    )
  }

  private func loadDatabaseData() throws -> Data {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let url = repositoryRoot
      .appendingPathComponent("data")
      .appendingPathComponent("route-atlas")
      .appendingPathComponent("osm-derived")
      .appendingPathComponent("shuto-whole-network-20260804.json")
    return try Data(contentsOf: url)
  }
}
