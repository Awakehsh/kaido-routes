import Foundation
import KaidoDomain
import KaidoRouting
import Testing

@Suite("Shuto circuit planner")
struct ShutoCircuitPlannerTests {
  @Test("reviewed PA paths are traversed in full or reject unsupported external entrances", arguments: ["heiwajima-inbound", "heiwajima-outbound", "yoga", "eifuku", "yoyogi", "shimura", "minami-ikebukuro", "hakozaki", "komagata", "kahei", "yashio", "tatsumi-1", "tatsumi-2", "shibaura", "ichikawa", "oi-westbound", "oi-eastbound", "daikoku", "kawaguchi"])
  func plansEveryReviewedParkingArea(name: String) throws {
    let database = try loadDatabase()
    let planner = try ShutoRoutePlanner(database: database)
    let parkingArea = try #require(database.parkingAreas.first {
      $0.parkingAreaID == "shuto.pa.\(name)"
    })
    let routeID = try #require(parkingArea.routeID)
    let direction = parkingArea.directionJA ?? (routeID == "B" ? "西行き" : "上り")
    var entrances = [routeID: direction]
    var exits = [routeID: direction]
    if name == "tatsumi-1" { entrances = ["B": "東行き"] }
    if name == "tatsumi-2" { entrances = ["B": "西行き"] }
    if name == "kahei" { entrances = ["6_MUKOJIMA": "下り"] }
    if name == "shibaura" { exits = ["C1": "内回り"] }
    let members = Set(entrances.keys).union(exits.keys).union([routeID])
      .union(name == "daikoku" ? ["K5"] : [])
    let circuit = ShutoCircuitDefinition(
      circuitID: "test.parking.\(name)", displayNameJA: parkingArea.nameJA,
      kind: .tour, memberRouteIDs: members,
      entranceDirectionsByRouteID: entrances, exitDirectionsByRouteID: exits,
      anchors: [.parkingArea(parkingArea.parkingAreaID)]
    )
    if name == "yoga" || name == "ichikawa" {
      // Both PAs precede the first supported inbound Shuto entrance;
      // reaching them requires the connecting expressway outside this graph.
      #expect(planner.circuitEntranceCandidates(for: circuit).isEmpty)
      #expect(throws: ShutoNetworkError.facilityUnavailable) {
        _ = try planner.recommendedCircuitPairing(
          for: circuit, origin: parkingArea.coordinate, evidence: .etcNormalCarUntil2026September
        )
      }
      return
    }
    let pairing = try planner.recommendedCircuitPairing(
      for: circuit, origin: parkingArea.coordinate, evidence: .etcNormalCarUntil2026September
    )
    let route = try planner.planCircuit(
      circuit: circuit, entryFacilityID: pairing.entrance.facilityID,
      exitFacilityID: pairing.exit.facilityID, laps: 1
    )
    #expect(assertContinuity(route.edges))
    let visits = route.routePlan.occurrences.filter { $0.kind == .paVisit }
    #expect(visits.count == parkingArea.interiorEdgeIDs?.count)
    #expect(visits.allSatisfy { $0.parkingAreaID == parkingArea.parkingAreaID })
    let parkingEdges = route.edges.filter { $0.kind == "PARKING" }.map(\.edgeID)
    #expect(parkingEdges == parkingArea.interiorEdgeIDs)
    #expect(route.routeIDsInOrder.allSatisfy { !$0.isEmpty })
  }

  @Test("a PA stop is completed on each lap without becoming a route shortcut")
  func repeatsParkingStopOnEachLap() throws {
    let database = try loadDatabase()
    let planner = try ShutoRoutePlanner(database: database)
    let original = ShutoCircuitDefinition.daikokuYokohamaLoop
    let circuit = ShutoCircuitDefinition(
      circuitID: "test.parking-loop", displayNameJA: original.displayNameJA,
      kind: .loop, memberRouteIDs: original.memberRouteIDs,
      entranceDirectionsByRouteID: original.entranceDirectionsByRouteID,
      exitDirectionsByRouteID: original.exitDirectionsByRouteID,
      anchors: original.anchors + [.parkingArea("shuto.pa.daikoku")]
    )
    #expect(!planner.circuitEntranceCandidates(for: circuit).isEmpty)
    let one = try planner.planCircuit(
      circuit: circuit, entryFacilityID: "shuto.ic.b.wangankanpachi",
      exitFacilityID: "shuto.ic.b.daikokufutou", laps: 1
    )
    let two = try planner.planCircuit(
      circuit: circuit, entryFacilityID: "shuto.ic.b.wangankanpachi",
      exitFacilityID: "shuto.ic.b.daikokufutou", laps: 2
    )
    #expect(assertContinuity(two.edges))
    #expect(two.routePlan.occurrences.filter { $0.kind == .paVisit }.count
      == one.routePlan.occurrences.filter { $0.kind == .paVisit }.count * 2)
    #expect(Set(two.routePlan.occurrences.map(\.id)).count == two.routePlan.occurrences.count)
  }

  @Test("route catalog names and landmarks cover every interface language")
  func localizesBundledRouteCatalog() {
    for circuit in ShutoCircuitDefinition.bundled {
      for locale in KaidoReleaseLocale.allCases {
        #expect(!circuit.displayName(for: locale).isEmpty)
        #expect(
          circuit.landmarkNames(for: locale).count
            == circuit.landmarkNamesJA.count
        )
      }
    }

    #expect(
      ShutoCircuitDefinition.c1Inner.displayName(
        for: .simplifiedChinese
      ) == "都心环状线 内环"
    )
    #expect(
      ShutoCircuitDefinition.c1Outer.displayName(
        for: .simplifiedChinese
      ) == "都心环状线 外环"
    )
    #expect(
      ShutoCircuitDefinition.scenicGrandTour.displayName(
        for: .english
      ) == "Yokohama Scenic Tour"
    )
  }

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

    // n laps carry n + 1 boundaries, so every lap has both an end and a
    // start and a per-lap split reads directly against the plan's occurrences.
    #expect(oneLap.lapBoundaryOccurrenceIndices.count == 2)
    #expect(twoLaps.lapBoundaryOccurrenceIndices.count == 3)
    let bounds = twoLaps.lapBoundaryOccurrenceIndices
    #expect(bounds == bounds.sorted())
    #expect(Set(bounds).count == bounds.count)
    #expect(bounds.allSatisfy { $0 <= twoLaps.routePlan.occurrences.count })
    // Both laps drive the same ring, so they start on the same edge.
    #expect(twoLaps.edges[bounds[0]].edgeID == twoLaps.edges[bounds[1]].edgeID)
    // Adding a lap adds exactly one ring's worth of edges, and that is the
    // span of each recorded lap.
    #expect(twoLaps.edges.count - oneLap.edges.count == bounds[1] - bounds[0])
    #expect(bounds[2] - bounds[1] == bounds[1] - bounds[0])
    #expect(oneLap.lapBoundaryOccurrenceIndices[0] == bounds[0])

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

  @Test("C1 outer circuit closes as a single-route loop")
  func plansC1OuterCircuit() throws {
    let planner = try ShutoRoutePlanner(database: loadDatabase())
    let route = try planner.planCircuit(
      circuit: .c1Outer,
      entryFacilityID: "shuto.ic.c1.kyoubashi",
      exitFacilityID: "shuto.ic.c1.shintomicho",
      laps: 1
    )

    #expect(route.distanceMeters > 12_000)
    #expect(route.distanceMeters < 25_000)
    #expect(assertContinuity(route.edges))
    #expect(route.routeIDsInOrder.first == "C1")
    #expect(route.routeIDsInOrder.allSatisfy { $0 == "C1" })
    #expect(route.routePlan.entryFacilityID == "shuto.ic.c1.kyoubashi")
    #expect(route.routePlan.exitFacilityID == "shuto.ic.c1.shintomicho")
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
    let range = ShutoCircuitDefinition.loopLapRange

    #expect(throws: ShutoCircuitError.invalidLapCount) {
      _ = try planner.planCircuit(
        circuit: .c2InnerWithBayshore,
        entryFacilityID: "shuto.ic.c2.hatsudaiminami",
        exitFacilityID: "shuto.ic.c2.tomigaya",
        laps: range.lowerBound - 1
      )
    }
    #expect(throws: ShutoCircuitError.invalidLapCount) {
      _ = try planner.planCircuit(
        circuit: .c2InnerWithBayshore,
        entryFacilityID: "shuto.ic.c2.hatsudaiminami",
        exitFacilityID: "shuto.ic.c2.tomigaya",
        laps: range.upperBound + 1
      )
    }

    let maxLaps = try planner.planCircuit(
      circuit: .c2InnerWithBayshore,
      entryFacilityID: "shuto.ic.c2.hatsudaiminami",
      exitFacilityID: "shuto.ic.c2.tomigaya",
      laps: range.upperBound
    )
    #expect(
      Set(maxLaps.routePlan.occurrences.map(\.id)).count
        == maxLaps.routePlan.occurrences.count
    )
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
        ($0.routeID != "B" || $0.entranceDirections.contains("西行き"))
          && $0.facilityID != "shuto.ic.b.sankeien"
          && $0.facilityID != "shuto.ic.b.sugita"
          && $0.facilityID != "shuto.ic.b.daikokufutou"
      }
    )

    let pairing = try planner.recommendedCircuitPairing(
      for: .wanganDaikokuRun,
      origin: origin,
      evidence: .etcNormalCarUntil2026September
    )
    #expect(pairing.exit.facilityID == "shuto.ic.b.daikokufutou")

    let route = try planner.planCircuit(
      circuit: .wanganDaikokuRun,
      entryFacilityID: pairing.entrance.facilityID,
      exitFacilityID: pairing.exit.facilityID,
      laps: 1
    )
    // Ariake to Daikoku along the Bayshore measures roughly 25 km, plus the
    // Daikoku interchange loop the parking area sits inside.
    #expect(route.distanceMeters > 15_000)
    #expect(route.distanceMeters < 45_000)
    #expect(assertContinuity(route.edges))
    // The run leaves the Bayshore for the Daikoku Line to reach the parking
    // area, then comes back to it for the Daikoku-Futo exit.
    #expect(Array(route.routeIDsInOrder.suffix(3)) == ["B", "K5", "B"])

    // The parking area is the point of the run: it is driven, not passed.
    let parkingVisits = route.routePlan.occurrences.filter {
      $0.kind == .paVisit
    }
    #expect(!parkingVisits.isEmpty)
    #expect(parkingVisits.allSatisfy { $0.parkingAreaID == "shuto.pa.daikoku" })
    // Driving the parking area is inside the toll domain — the driver has
    // not exited — so the pairing the tariff is quoted for is untouched.
    #expect(parkingVisits.allSatisfy { $0.tollDomainID == "shuto.toll-domain" })
    #expect(route.exitFacility?.facilityID == "shuto.ic.b.daikokufutou")
    // The visit is a contiguous run of occurrences, not scattered edges.
    let visitIndices = parkingVisits.map(\.index)
    #expect(zip(visitIndices, visitIndices.dropFirst()).allSatisfy { $0 + 1 == $1 })

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

  @Test("a tour can join from the nearest connecting expressway entrance")
  func tourAcceptsNearbyConnectingEntrance() throws {
    let database = try loadDatabase()
    let planner = try ShutoRoutePlanner(database: database)
    let harumi = try #require(database.directionalFacilities.first {
      $0.facilityID == "shuto.ic.10.harumi"
    })
    let pairing = try planner.recommendedCircuitPairing(
      for: .wanganDaikokuRun,
      origin: harumi.coordinate,
      evidence: .etcNormalCarUntil2026September
    )
    #expect(pairing.entrance.facilityID == harumi.facilityID)
    let route = try planner.planCircuit(
      circuit: .wanganDaikokuRun,
      entryFacilityID: pairing.entrance.facilityID,
      exitFacilityID: pairing.exit.facilityID,
      laps: 1
    )
    #expect(route.routeIDsInOrder == ["10", "B", "K5", "B"])
    #expect(assertContinuity(route.edges))
    #expect(route.routePlan.occurrences.contains {
      $0.parkingAreaID == "shuto.pa.daikoku" && $0.kind == .paVisit
    })
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
      evidence: .etcNormalCarUntil2026September
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
      evidence: .etcNormalCarUntil2026September
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
    let parkingArea = try #require(loadDatabase().parkingAreas.first {
      $0.parkingAreaID == "shuto.pa.daikoku"
    })
    #expect(route.routePlan.occurrences.filter {
      $0.parkingAreaID == parkingArea.parkingAreaID && $0.kind == .paVisit
    }.count == parkingArea.interiorEdgeIDs?.count)
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
      evidence: .etcNormalCarUntil2026September
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

  @Test("a distant origin retains a direction-valid surface access candidate")
  func retainsDistantOriginCandidate() throws {
    let planner = try ShutoRoutePlanner(database: loadDatabase())
    // Tachikawa sits beyond the old 16 km cap. The exact C2 route remains
    // selectable; the surface provider, not geodesic distance, decides whether
    // the ordinary-road access leg can be driven.
    let origin = ShutoCoordinate(latitude: 35.6979, longitude: 139.4139)
    let pairing = try planner.recommendedCircuitPairing(
      for: .c2InnerWithBayshore,
      origin: origin,
      evidence: .etcNormalCarUntil2026September
    )
    let distance = try #require(pairing.entranceDistanceMeters)
    #expect(distance > ShutoEntranceAccessTier.outerRadiusMeters)
    #expect(pairing.entrance.canEnter)
    #expect(pairing.exit.canExit)
    #expect(
      planner.circuitEntranceCandidates(
        for: .c1Outer,
        origin: origin
      ).contains { $0.routeID == "C1" }
    )
  }

  @Test("entrance access tiers keep longer surface access explicit")
  func classifiesEntranceAccessTiers() {
    #expect(
      ShutoEntranceAccessTier.classify(distanceMeters: 7_999) == .nearby
    )
    #expect(
      ShutoEntranceAccessTier.classify(distanceMeters: 8_001) == .far
    )
    #expect(
      ShutoEntranceAccessTier.classify(distanceMeters: 16_001)
        == .extended
    )
  }

  private func assertContinuity(
    _ edges: [ShutoNetworkDatabase.Edge]
  ) -> Bool {
    zip(edges, edges.dropFirst()).allSatisfy {
      $0.toNodeID == $1.fromNodeID
    }
  }

  @Test("reachable exits are exactly the exits the planner can pair with an entrance")
  func reachableExitsAgreeWithPlanning() throws {
    let database = try loadDatabase()
    let planner = try ShutoRoutePlanner(database: database)
    let exits = database.directionalFacilities.filter(\.canExit)
    let entrances = database.directionalFacilities.filter(\.canEnter)
    let sampledEntrances = stride(from: 0, to: entrances.count, by: 34)
      .map { entrances[$0] }
    let sampledExits = stride(from: 0, to: exits.count, by: 5)
      .map { exits[$0] }
    #expect(sampledEntrances.count >= 4 && sampledExits.count >= 25)
    for entrance in sampledEntrances {
      let reachable = Set(
        planner.exitCandidates(
          exits,
          reachableAfterEntering: entrance.facilityID
        ).map(\.facilityID)
      )
      #expect(!reachable.isEmpty, Comment(rawValue: entrance.facilityID))
      for exit in sampledExits where exit.facilityID != entrance.facilityID {
        let plans =
          (try? planner.plan(
            entryFacilityID: entrance.facilityID,
            exitFacilityID: exit.facilityID
          )) != nil
        #expect(
          plans == reachable.contains(exit.facilityID),
          Comment(rawValue: "\(entrance.facilityID) -> \(exit.facilityID)")
        )
      }
    }
    #expect(
      planner.exitCandidates(exits, reachableAfterEntering: "shuto.ic.missing")
        .isEmpty
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
      .appendingPathComponent("shuto-whole-network-20260804.json")
    return try JSONDecoder().decode(
      ShutoNetworkDatabase.self,
      from: Data(contentsOf: url)
    )
  }
}
