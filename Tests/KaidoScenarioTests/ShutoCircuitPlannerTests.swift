import Foundation
import KaidoRouting
import Testing

@Suite("Shuto circuit planner")
struct ShutoCircuitPlannerTests {
  @Test("C2 inner circuit with Bayshore closes and repeats laps distinctly")
  func plansC2InnerCircuitWithTwoLaps() throws {
    let planner = try ShutoRoutePlanner(database: loadDatabase())

    let oneLap = try planner.planCircuit(
      circuit: .c2InnerWithBayshore,
      entryFacilityID: "shuto.ic.c2.hatsudaiminami",
      exitFacilityID: "shuto.ic.c2.tomigaya",
      laps: 1
    )
    let twoLaps = try planner.planCircuit(
      circuit: .c2InnerWithBayshore,
      entryFacilityID: "shuto.ic.c2.hatsudaiminami",
      exitFacilityID: "shuto.ic.c2.tomigaya",
      laps: 2
    )

    // One C2+Bayshore inner loop measures ~56 km on the bundled snapshot.
    #expect(oneLap.distanceMeters > 50_000)
    #expect(oneLap.distanceMeters < 70_000)
    #expect(twoLaps.distanceMeters > oneLap.distanceMeters * 1.7)

    #expect(assertContinuity(twoLaps.edges))
    #expect(twoLaps.routeIDsInOrder.contains("C2"))
    #expect(twoLaps.routeIDsInOrder.contains("B"))
    #expect(
      twoLaps.routePlan.entryFacilityID == "shuto.ic.c2.hatsudaiminami"
    )
    #expect(twoLaps.routePlan.exitFacilityID == "shuto.ic.c2.tomigaya")
    #expect(twoLaps.coordinates.count == twoLaps.edges.count + 1)

    // Repeated laps preserve occurrence identity: IDs and indexes stay
    // unique while the underlying edges repeat.
    let occurrences = twoLaps.routePlan.occurrences
    #expect(occurrences.count == twoLaps.edges.count)
    #expect(Set(occurrences.map(\.id)).count == occurrences.count)
    #expect(occurrences.map(\.index) == Array(occurrences.indices))
    let edgeCounts = Dictionary(
      grouping: twoLaps.edges.map(\.edgeID),
      by: { $0 }
    ).mapValues(\.count)
    #expect(edgeCounts.values.contains(2))
  }

  @Test("C1 inner circuit closes as a single-route loop")
  func plansC1InnerCircuit() throws {
    let planner = try ShutoRoutePlanner(database: loadDatabase())

    let exits = try planner.circuitExitCandidates(
      for: .c1Inner,
      afterEntering: "shuto.ic.c1.takaracho"
    )
    let firstExit = try #require(exits.first)
    let route = try planner.planCircuit(
      circuit: .c1Inner,
      entryFacilityID: "shuto.ic.c1.takaracho",
      exitFacilityID: firstExit.facilityID,
      laps: 1
    )

    // The C1 loop measures ~15 km; the top-ranked exit adds a short tail.
    #expect(route.distanceMeters > 12_000)
    #expect(route.distanceMeters < 25_000)
    #expect(assertContinuity(route.edges))
    #expect(route.routeIDsInOrder.first == "C1")
    #expect(route.routeIDsInOrder.contains("C1"))
    #expect(!route.routeIDsInOrder.contains("B"))
  }

  @Test("exit candidates rank by forward travel, not geodesic nearness")
  func ranksExitsByForwardTravel() throws {
    let planner = try ShutoRoutePlanner(database: loadDatabase())

    let exits = try planner.circuitExitCandidates(
      for: .c2InnerWithBayshore,
      afterEntering: "shuto.ic.c2.hatsudaiminami"
    )

    // Tomigaya is the first inner-loop exit after Hatsudai-minami; the
    // wider list may continue onto reachable radial exits, but every entry
    // must remain an actual exit facility.
    #expect(exits.first?.facilityID == "shuto.ic.c2.tomigaya")
    #expect(exits.allSatisfy { $0.canExit })
  }

  @Test("entrance candidates are direction-valid and nearest-first")
  func ranksDirectionValidEntrances() throws {
    let planner = try ShutoRoutePlanner(database: loadDatabase())

    // Near Hatsudai on the west side of the C2 loop.
    let origin = ShutoCoordinate(latitude: 35.6798, longitude: 139.6862)
    let candidates = planner.circuitEntranceCandidates(
      for: .c2InnerWithBayshore,
      origin: origin
    )

    #expect(!candidates.isEmpty)
    // The nearest legal start is the Hatsudai radial entrance, which joins
    // the inner loop through the all-directions Nishi-Shinjuku JCT; the
    // loop's own Hatsudai-minami ramp ranks right behind it.
    #expect(candidates.first?.facilityID == "shuto.ic.4.hatsudai")
    #expect(
      candidates.contains {
        $0.facilityID == "shuto.ic.c2.hatsudaiminami"
      }
    )
    #expect(candidates.allSatisfy { $0.canEnter })
  }

  @Test("a wrong-direction entrance is rejected, not silently accepted")
  func rejectsWrongDirectionEntrance() throws {
    let planner = try ShutoRoutePlanner(database: loadDatabase())

    // Nakano-Chojabashi only has an outer-loop entrance.
    #expect(throws: ShutoNetworkError.facilityUnavailable) {
      _ = try planner.planCircuit(
        circuit: .c2InnerWithBayshore,
        entryFacilityID: "shuto.ic.c2.nakanochoujabashi",
        exitFacilityID: "shuto.ic.c2.tomigaya",
        laps: 1
      )
    }
  }

  @Test("lap count is bounded")
  func rejectsInvalidLapCount() throws {
    let planner = try ShutoRoutePlanner(database: loadDatabase())

    #expect(throws: ShutoCircuitError.invalidLapCount) {
      _ = try planner.planCircuit(
        circuit: .c2InnerWithBayshore,
        entryFacilityID: "shuto.ic.c2.hatsudaiminami",
        exitFacilityID: "shuto.ic.c2.tomigaya",
        laps: 0
      )
    }
  }

  @Test("the Wangan Daikoku run tours westbound onto the Daikoku exit")
  func plansWanganDaikokuRun() throws {
    let planner = try ShutoRoutePlanner(database: loadDatabase())

    // Tokyo waterfront origin near Ariake.
    let origin = ShutoCoordinate(latitude: 35.636, longitude: 139.792)
    let entrances = planner.circuitEntranceCandidates(
      for: .wanganDaikokuRun,
      origin: origin
    )
    #expect(!entrances.isEmpty)
    // Every offered entrance joins the westbound carriageway and can still
    // reach Daikoku; Yokohama-side westbound entrances past Daikoku (Sankeien,
    // Sugita) head away from the course and never appear.
    #expect(
      entrances.allSatisfy {
        $0.entranceDirections.contains("西行き")
          && $0.facilityID != "shuto.ic.b.sankeien"
          && $0.facilityID != "shuto.ic.b.sugita"
          && $0.facilityID != "shuto.ic.b.daikokufutou"
      }
    )

    let pairing = try planner.recommendedCircuitPairing(
      for: .wanganDaikokuRun,
      origin: origin,
      evidence: .etcNormalCarActive
    )
    #expect(pairing.exit.facilityID == "shuto.ic.b.daikokufutou")

    let route = try planner.planCircuit(
      circuit: .wanganDaikokuRun,
      entryFacilityID: pairing.entrance.facilityID,
      exitFacilityID: pairing.exit.facilityID,
      laps: 1
    )
    // Ariake to Daikoku along the Bayshore measures roughly 25 km.
    #expect(route.distanceMeters > 15_000)
    #expect(route.distanceMeters < 45_000)
    #expect(assertContinuity(route.edges))
    #expect(route.routeIDsInOrder == ["B"])

    // A tour is one reviewed pass; laps are a loop concept.
    #expect(throws: ShutoCircuitError.invalidLapCount) {
      _ = try planner.planCircuit(
        circuit: .wanganDaikokuRun,
        entryFacilityID: pairing.entrance.facilityID,
        exitFacilityID: pairing.exit.facilityID,
        laps: 2
      )
    }
  }

  @Test("the Daikoku Yokohama loop closes in the supported direction")
  func plansDaikokuYokohamaLoop() throws {
    let planner = try ShutoRoutePlanner(database: loadDatabase())

    // Origin at Daikoku PA itself.
    let origin = ShutoCoordinate(latitude: 35.4614, longitude: 139.6862)
    let entrances = planner.circuitEntranceCandidates(
      for: .daikokuYokohamaLoop,
      origin: origin
    )
    // The Daikoku-Futo westbound entrance heads away from the cycle toward
    // the Honmoku dead end; the closure gate must exclude it even though it
    // is geodesically nearest.
    #expect(
      entrances.allSatisfy { $0.facilityID != "shuto.ic.b.daikokufutou" }
    )

    let pairing = try planner.recommendedCircuitPairing(
      for: .daikokuYokohamaLoop,
      origin: origin,
      evidence: .etcNormalCarActive
    )
    // The Daikoku Line entrance right beside the PA is on the cycle and
    // geodesically nearest; the same-named Bayshore exit is never paired,
    // so the fare-best exit is Namamugi just off the cycle — the quoted
    // band never changes with lap count.
    #expect(pairing.entrance.facilityID == "shuto.ic.k5.daikokufutou")
    let entranceDistance = try #require(pairing.entranceDistanceMeters)
    #expect(
      ShutoEntranceAccessTier.classify(
        distanceMeters: entranceDistance
      ) == .nearby
    )
    #expect(pairing.exit.nameJA != pairing.entrance.nameJA)
    let band = try #require(pairing.tariffBand)
    #expect(band.quotedYen <= 500)

    let twoLaps = try planner.planCircuit(
      circuit: .daikokuYokohamaLoop,
      entryFacilityID: pairing.entrance.facilityID,
      exitFacilityID: pairing.exit.facilityID,
      laps: 2
    )
    // One cycle measures ~31 km; two laps repeat it as distinct
    // occurrences before the exit tail.
    #expect(twoLaps.distanceMeters > 55_000)
    #expect(twoLaps.distanceMeters < 100_000)
    #expect(assertContinuity(twoLaps.edges))
    let traversed = Set(twoLaps.routeIDsInOrder)
    #expect(traversed.isSuperset(of: ["B", "K1", "K5", "K6"]))
    let edgeCounts = Dictionary(
      grouping: twoLaps.edges.map(\.edgeID),
      by: { $0 }
    ).mapValues(\.count)
    #expect(edgeCounts.values.contains(2))
  }

  @Test("the scenic tour passes its anchors in course order to Daikoku PA")
  func plansScenicGrandTour() throws {
    let planner = try ShutoRoutePlanner(database: loadDatabase())

    // Origin near the Harumi entrance.
    let origin = ShutoCoordinate(latitude: 35.655, longitude: 139.784)
    let pairing = try planner.recommendedCircuitPairing(
      for: .scenicGrandTour,
      origin: origin,
      evidence: .etcNormalCarActive
    )
    #expect(pairing.entrance.facilityID == "shuto.ic.10.harumi")
    #expect(pairing.exit.facilityID == "shuto.ic.b.daikokufutou")

    let route = try planner.planCircuit(
      circuit: .scenicGrandTour,
      entryFacilityID: pairing.entrance.facilityID,
      exitFacilityID: pairing.exit.facilityID,
      laps: 1
    )
    // Harumi past Haneda and Minato Mirai to Daikoku measures ~41 km.
    #expect(route.distanceMeters > 30_000)
    #expect(route.distanceMeters < 55_000)
    #expect(assertContinuity(route.edges))
    let traversed = Set(route.routeIDsInOrder)
    #expect(traversed.isSuperset(of: ["10", "B", "1_HANEDA", "K1", "K3"]))
  }

  @Test("a radial entrance pairs to the honest cheapest loop excursion")
  func plansShinjukuC1Excursion() throws {
    let planner = try ShutoRoutePlanner(database: loadDatabase())

    // Shinjuku station area: the radial entrance joins C1 for laps. The
    // folklore Yoyogi pairing is NOT the answer — the operator fare search
    // (checked 2026-08-04) prices Shinjuku to Yoyogi at ¥860 because the
    // return radial is only reachable through a full circuit, so the
    // honest cheapest exit is an onward C1 exit in the mid bands.
    let origin = ShutoCoordinate(latitude: 35.6896, longitude: 139.7006)
    let pairing = try planner.recommendedCircuitPairing(
      for: .c1Inner,
      origin: origin,
      evidence: .etcNormalCarActive
    )
    #expect(pairing.entrance.facilityID == "shuto.ic.4.shinjuku")
    #expect(pairing.exit.nameJA != pairing.entrance.nameJA)
    let band = try #require(pairing.tariffBand)
    #expect(band.quotedYen < 700)

    let route = try planner.planCircuit(
      circuit: .c1Inner,
      entryFacilityID: pairing.entrance.facilityID,
      exitFacilityID: pairing.exit.facilityID,
      laps: 2
    )
    #expect(assertContinuity(route.edges))
    let traversed = Set(route.routeIDsInOrder)
    #expect(traversed.isSuperset(of: ["4", "C1"]))
    // Radial approach + two C1 laps + exit tail.
    #expect(route.distanceMeters > 30_000)
    #expect(route.distanceMeters < 60_000)
  }

  @Test("a distant origin fails closed instead of a long surface leg")
  func rejectsOutOfRangeOrigin() throws {
    let planner = try ShutoRoutePlanner(database: loadDatabase())
    // Tachikawa sits ~20 km from the nearest C2 entrance: beyond the outer
    // access radius, the pairing fails closed with the factual distance
    // instead of recommending a long ordinary-road leg.
    let origin = ShutoCoordinate(latitude: 35.6979, longitude: 139.4139)
    #expect {
      try planner.recommendedCircuitPairing(
        for: .c2InnerWithBayshore,
        origin: origin,
        evidence: .etcNormalCarActive
      )
    } throws: { error in
      guard
        case ShutoCircuitError.entranceOutOfRange(let nearest) = error
      else { return false }
      return nearest > ShutoEntranceAccessTier.outerRadiusMeters
    }
  }

  @Test("entrance access tiers split at 8 and 16 kilometers")
  func classifiesEntranceAccessTiers() {
    #expect(
      ShutoEntranceAccessTier.classify(distanceMeters: 7_999) == .nearby
    )
    #expect(
      ShutoEntranceAccessTier.classify(distanceMeters: 8_001) == .far
    )
    #expect(
      ShutoEntranceAccessTier.classify(distanceMeters: 16_001)
        == .outOfRange
    )
  }

  private func assertContinuity(
    _ edges: [ShutoNetworkDatabase.Edge]
  ) -> Bool {
    zip(edges, edges.dropFirst()).allSatisfy {
      $0.toNodeID == $1.fromNodeID
    }
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
      .appendingPathComponent("shuto-whole-network-20260804.json")
    return try JSONDecoder().decode(
      ShutoNetworkDatabase.self,
      from: Data(contentsOf: url)
    )
  }
}
