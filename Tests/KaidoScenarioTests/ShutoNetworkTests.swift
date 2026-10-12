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
    // The 2026-10-12 facility review adds the 東銀座 exit the catalog missed.
    #expect(database.directionalFacilities.count == 152)
    #expect(database.junctions.count == 39)
    #expect(
      database.junctions.allSatisfy {
        $0.officialDetailReference.hasPrefix("https://www.shutoko.jp/")
          && $0.officialDetailSHA256.count == 64
      }
    )
    #expect(database.parkingAreas.count == 19)
    // The 2026-10-12 topology review restores 15 carriageway edges and
    // removes 15 out-of-service and 20 surface-crossing edges.
    #expect(database.edges.count == 24_553)
    #expect(database.parkingAreas.allSatisfy { $0.isDrivable })
    let edgesByID = Dictionary(uniqueKeysWithValues: database.edges.map { ($0.edgeID, $0) })
    for parkingArea in database.parkingAreas {
      var cursor = try #require(parkingArea.accessNodeID)
      for edgeID in try #require(parkingArea.interiorEdgeIDs) {
        let edge = try #require(edgesByID[edgeID])
        #expect(edge.fromNodeID == cursor)
        #expect(edge.kind == "PARKING")
        #expect(edge.routeMemberships.isEmpty)
        cursor = edge.toNodeID
      }
      #expect(cursor == parkingArea.returnNodeID)
    }
    let daikokuPA = try #require(
      database.parkingAreas.first { $0.parkingAreaID == "shuto.pa.daikoku" }
    )
    #expect(daikokuPA.isDrivable)
    #expect(daikokuPA.interiorEdgeIDs?.count == 24)
    #expect(
      database.edges
        .filter { $0.kind == "PARKING" }
        .allSatisfy { $0.routeMemberships.isEmpty }
    )
    let komatsugawa = try #require(
      database.junctions.first {
        $0.junctionID == "shuto.jct.jct_komatsugawa"
      }
    )
    #expect(komatsugawa.osmNodeIDs.contains(370_270_524))
    #expect(komatsugawa.osmNodeIDs.contains(600_726_158))
    #expect(!komatsugawa.osmNodeIDs.contains(31_337_397))
    // Every available facility with a ramp is matched; the one available
    // facility without a ramp of its own is the 横浜港北 twin listed under
    // 横浜北西線, whose ramps belong to 横浜北線 and bind that twin instead.
    let availableFacilities = database.directionalFacilities.filter {
      $0.operationalStatus == "AVAILABLE"
    }
    #expect(
      availableFacilities
        .filter { $0.canEnter || $0.canExit }
        .allSatisfy { $0.geometryMatchState == "CANDIDATE_MATCHED" }
    )
    #expect(
      availableFacilities
        .filter { !$0.canEnter && !$0.canExit }
        .map(\.facilityID)
        == ["shuto.ic.k7-yokohama-hokusei.yokohamakohoku"]
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
    let patch = try #require(database.sources.facilityCandidatePatch)
    #expect(patch.reviewID == "shuto-facility-candidate-patch-20261012")
    #expect(patch.checkedAt == "2026-10-12")
    #expect(patch.patchedFacilityCount == 148)
    #expect(
      database.sources.facilityCandidateReview
        .entryBoundaryRebindingCount == 2
    )
    #expect(
      database.sources.facilityCandidateReview
        .entryCandidateReplacementCount == 1
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
        routeEdges: route.edges,
        decisionIndex: index - 1
      )?.id ?? edge.edgeID
    }
    #expect(route.routePlan.occurrences.map(\.entityID) == expectedOccurrenceEntities)
  }

  @Test("no facility binds a ramp the 2026-10-18 C1 closures shut")
  func unbindsTheClosedC1Ramps() throws {
    let database = try loadDatabase()
    let facilities = Dictionary(
      uniqueKeysWithValues: database.directionalFacilities.map {
        ($0.facilityID, $0)
      }
    )
    let shintomicho = try #require(facilities["shuto.ic.c1.shintomicho"])
    #expect(shintomicho.operationalStatus == "UNAVAILABLE")
    #expect(!shintomicho.canExit)
    let ginza = try #require(facilities["shuto.ic.c1.ginza"])
    #expect(ginza.entranceDirections == ["外回り"])
    #expect(ginza.exitDirections == ["内回り", "外回り"])
    #expect(ginza.canEnter && ginza.canExit)
    // 新富町出口 (osm way 760760233) was also a nearby exit candidate of
    // 宝町, 京橋 and 銀座; 4848936 is the 内回り 銀座入口.
    let closedWayIDs: Set<Int64> = [760_760_233, 4_848_936]
    let edgesByID = Dictionary(
      uniqueKeysWithValues: database.edges.map { ($0.edgeID, $0) }
    )
    let bound = database.directionalFacilities.flatMap {
      $0.entryEdgeCandidates + $0.exitEdgeCandidates
    }
    #expect(
      !bound.contains {
        closedWayIDs.contains(edgesByID[$0.edgeID]?.wayID ?? 0)
      }
    )
  }

  @Test("the repaired carriageways and ramps plan the operator's roads")
  func plansOverTheRepairedTopology() throws {
    let database = try loadDatabase()
    let planner = try ShutoRoutePlanner(database: database)

    // Route 1 Haneda southbound runs through the renewed
    // Higashi-Shinagawa section instead of stopping there, about 10 km
    // from 汐留 to 平和島. The old graph started on 銀座's ramp and went
    // around via the Daiba Line, the Bayshore and K1 for 50.7 km.
    let haneda = try planner.plan(
      entryFacilityID: "shuto.ic.c1.shiodome",
      exitFacilityID: "shuto.ic.1-haneda.heiwajima"
    )
    #expect(haneda.distanceMeters < 12_000)
    #expect(haneda.routeIDsInOrder == ["C1", "1_HANEDA"])
    #expect(haneda.edges.contains { $0.edgeID == "osm.1051964009.0.forward" })

    // 一ツ橋 ends on its own exit ramp, not 西神田's 655 m away. Its exit
    // serves 上り only, so from C1 the fare path turns back beyond 熊野町;
    // the 東池袋 surface U-turn that once shortened it to 14 km is cut.
    let hitotsubashi = try planner.plan(
      entryFacilityID: "shuto.ic.c1.kandabashi",
      exitFacilityID: "shuto.ic.5.hitotsubashi"
    )
    #expect(hitotsubashi.edges.last?.edgeID == "osm.203035370.3.forward")
    #expect(!hitotsubashi.edges.contains { $0.edgeID == "osm.390426203.0.forward" })
    #expect(hitotsubashi.distanceMeters > 25_000)

    // K3 is entered from the Bayshore westbound at Honmoku JCT again.
    #expect(
      database.edges.contains {
        $0.edgeID == "osm.32403531.0.forward"
          && $0.fromNodeID == 255_525_019
          && $0.routeMemberships.map(\.routeID) == ["K3"]
      }
    )

    let ohashi = try #require(
      database.junctions.first { $0.junctionID == "shuto.jct.jct_ohashi" }
    )
    #expect(ohashi.osmNodeIDs == [927_641_089, 3_387_909_707, 3_387_909_708, 7_549_622_953])
    let ohashiCoordinate = try #require(ohashi.coordinate)
    #expect(abs(ohashiCoordinate.latitude - 35.6512) < 0.001)
    #expect(abs(ohashiCoordinate.longitude - 139.6889) < 0.001)

    let higashiGinza = try #require(
      database.directionalFacilities.first {
        $0.facilityID == "shuto.ic.c1.higashiginza"
      }
    )
    #expect(higashiGinza.exitDirections == ["外回り"])
    #expect(higashiGinza.entranceDirections.isEmpty)
    #expect(
      higashiGinza.exitEdgeCandidates.map(\.edgeID) == ["osm.203301443.0.forward"]
    )
  }

  @Test("Kiba entry follows the reviewed Route 9 inbound ramp")
  func plansKibaInboundWithoutSouthboundDetour() throws {
    let database = try loadDatabase()
    let kiba = try #require(
      database.directionalFacilities.first {
        $0.facilityID == "shuto.ic.9.kiba"
      }
    )
    #expect(kiba.entryEdgeCandidates.count == 1)
    #expect(
      kiba.entryEdgeCandidates.first?.edgeID
        == "osm.382676575.2.forward"
    )
    #expect(kiba.entryEdgeCandidates.first?.distanceMeters == 62.107)

    let route = try ShutoRoutePlanner(database: database).plan(
      entryFacilityID: "shuto.ic.9.kiba",
      exitFacilityID: "shuto.ic.c1.ginza"
    )

    #expect(route.edges.first?.edgeID == "osm.382676575.2.forward")
    #expect(route.edges.count == 171)
    #expect(route.routeIDsInOrder.starts(with: ["9"]))
    #expect(route.routeIDsInOrder.contains("6_MUKOJIMA"))
    #expect(route.routeIDsInOrder.contains("C1"))
    #expect(!route.edges.contains { $0.edgeID == "osm.4857854.0.forward" })
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
        $0.route.entryFacility.canEnter && ($0.route.exitFacility?.canExit == true)
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

    // A bare RoutePlan carries no lap marks, so restore rebuilds the same road
    // without them. Everything that is road identity still round-trips.
    #expect(restored.describesSameRoad(as: planned))
    #expect(restored.lapBoundaryOccurrenceIndices.isEmpty)
    #expect(!planned.lapBoundaryOccurrenceIndices.isEmpty)
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
    let url =
      repositoryRoot
      .appendingPathComponent("data")
      .appendingPathComponent("route-atlas")
      .appendingPathComponent("osm-derived")
      .appendingPathComponent("shuto-whole-network-20260804.json")
    return try Data(contentsOf: url)
  }
}
