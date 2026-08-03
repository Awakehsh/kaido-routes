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

    // Tomigaya is the first inner-loop exit after Hatsudai-minami.
    #expect(exits.first?.facilityID == "shuto.ic.c2.tomigaya")
    #expect(
      exits.allSatisfy {
        $0.exitDirections.contains("内回り") && $0.canExit
      }
    )
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
    #expect(candidates.first?.facilityID == "shuto.ic.c2.hatsudaiminami")
    #expect(
      candidates.allSatisfy {
        $0.entranceDirections.contains("内回り") && $0.canEnter
      }
    )
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
      .appendingPathComponent("shuto-whole-network-20260728.json")
    return try JSONDecoder().decode(
      ShutoNetworkDatabase.self,
      from: Data(contentsOf: url)
    )
  }
}
