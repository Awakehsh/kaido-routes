#if canImport(CoreLocation)
  import Foundation
  import KaidoDomain
  import KaidoNavigation
  import KaidoRouting
  import Testing

  /// Lap changes asked for mid-drive on laps that differ: the Daikoku PA stop
  /// makes the first lap of a three-lap Daikoku loop longer than the others,
  /// and a loop that ends in Daikoku PA ends its last lap there. Each drive
  /// runs at 1 Hz through the same pipeline as the replay gate.
  @Suite("Lap changes on unequal laps, replayed at 1 Hz")
  struct LapChangeReplayTests {
    @Test("dropping a lap after a PA stop lands on the same road one lap on")
    func droppingALapAfterAPAStop() async throws {
      let fixture = try LapFixture.withPAStop()
      try await expectLapChange(.dropOneLap, toLap: fixture.stopLap + 1, fixture: fixture)
    }

    @Test("finishing the current lap after a PA stop lands on the same road in the last lap")
    func finishingTheLapAfterAPAStop() async throws {
      let fixture = try LapFixture.withPAStop()
      try await expectLapChange(
        .finishCurrentLap,
        toLap: fixture.laps.count - 1,
        fixture: fixture
      )
    }

    @Test("finishing the current lap on a loop that ends in its PA arrives at the PA")
    func finishingTheLapOnALoopEndingAtAPA() async throws {
      let fixture = try LapFixture.endingAtPA()
      try await expectLapChange(
        .finishCurrentLap,
        toLap: fixture.laps.count - 1,
        fixture: fixture
      )
    }

    @Test("a lap is not dropped from inside a PA stop the next lap does not make")
    func noLapIsDroppedFromInsideAPAStop() async throws {
      let fixture = try LapFixture.withPAStop()
      let plan = fixture.gate.release.navigation.bundle.routePlan
      let insideStop = try #require(
        plan.occurrences.first {
          fixture.laps[fixture.stopLap].contains($0.index) && $0.kind == .paVisit
        }
      )
      let run = try await fixture.gate.run(
        legs: fixture.gate.plannedLegs(),
        seed: 5,
        lapChange: ReplayGateLapChange(
          action: .dropOneLap,
          afterOccurrenceIndex: insideStop.index
        )
      )
      let outcome = try #require(run.lapChangeOutcome)
      let asked = try #require(
        plan.occurrences.first { $0.index == outcome.fromOccurrenceIndex }
      )
      // Admitted progress may already have left the PA when the driver asks;
      // only a request made inside it must be refused.
      if asked.kind == .paVisit {
        #expect(outcome.landedOccurrenceID == nil)
      }
      #expect(run.wrongCommitCount() == 0)
    }

    private func expectLapChange(
      _ action: ReplayGateLapChange.Action,
      toLap targetLap: Int,
      fixture: LapFixture
    ) async throws {
      let gate = fixture.gate
      let plan = gate.release.navigation.bundle.routePlan
      let from = fixture.askAfterOccurrenceIndex
      let to = try #require(
        sameRoadOccurrenceIndex(as: from, in: fixture.laps[targetLap], plan: plan, laps: fixture.laps)
      )
      // The car drives on along the road it is on; from that road on its
      // position is the target lap's, the occurrences the driver dropped
      // are never driven.
      for seed: UInt64 in [1, 2] {
        let run = try await gate.run(
          legs: gate.plannedLegs(skippingAfter: from - 1, through: to - 1),
          seed: seed,
          lapChange: ReplayGateLapChange(action: action, afterOccurrenceIndex: from)
        )
        let summary = gateLine(file: plan.id, seed: seed, run: run, label: "LAPS-\(action)")
        print(summary)
        let outcome = try #require(run.lapChangeOutcome, "\(summary)")
        let landedID = try #require(outcome.landedOccurrenceID, "\(summary)")
        let landed = try #require(plan.occurrence(id: landedID))
        let asked = try #require(plan.occurrences.first { $0.index == outcome.fromOccurrenceIndex })
        // The car stays on the road it is on; only the plan moves a lap on.
        #expect(landed.entityID == asked.entityID, "\(summary)")
        #expect(fixture.laps[targetLap].contains(landed.index), "\(summary)")
        #expect(
          landed.index
            == sameRoadOccurrenceIndex(
              as: asked.index,
              in: fixture.laps[targetLap],
              plan: plan,
              laps: fixture.laps
            ),
          "\(summary)"
        )
        #expect(run.entryRecord != nil, "\(summary)")
        #expect(run.wrongCommitCount() == 0, "\(summary)")
        #expect(run.falseRouteRecoveryCount == 0, "\(summary)")
        #expect(run.reachedCompletion, "\(summary)")
        #expect(!run.completedEarly(), "\(summary)")
      }
    }

    /// The occurrence in `lap` on the same road as `index`, by the same rank
    /// among that road's occurrences in its own lap.
    private func sameRoadOccurrenceIndex(
      as index: Int,
      in lap: Range<Int>,
      plan: RoutePlan,
      laps: [Range<Int>]
    ) -> Int? {
      guard let current = plan.occurrences.first(where: { $0.index == index }),
        let ownLap = laps.first(where: { $0.contains(index) })
      else { return nil }
      let rank = plan.occurrences.count {
        ownLap.contains($0.index) && $0.index < index && $0.entityID == current.entityID
      }
      let sameRoad = plan.occurrences.filter {
        lap.contains($0.index) && $0.entityID == current.entityID
      }
      return sameRoad.indices.contains(rank) ? sameRoad[rank].index : nil
    }
  }

  private struct LapFixture {
    let gate: LiveNavigationReplayGate
    let laps: [Range<Int>]
    /// The lap the PA stop sits in.
    let stopLap: Int
    let askAfterOccurrenceIndex: Int

    /// Three laps of the Daikoku loop from Wangan-Kanpachi to Haneda with the
    /// Daikoku PA stop, which the planner places in the first lap.
    static func withPAStop() throws -> LapFixture {
      let database = try replayGateDatabase()
      let planner = try ShutoRoutePlanner(database: database)
      let base = try planner.planCircuit(
        circuit: .daikokuYokohamaLoop,
        entryFacilityID: "shuto.ic.b.wangankanpachi",
        exitFacilityID: "shuto.ic.1-haneda.haneda",
        laps: 3
      )
      let stop = try #require(
        planner.parkingStopOptions(for: base).first { $0.id == "shuto.pa.daikoku" }
      )
      let route = try planner.addingParkingStops([stop.id], to: base)
      let gate = try onDemandGate(route: route, database: database)
      let laps = lapRanges(route)
      let stopLap = try #require(laps.firstIndex { $0.contains(stop.departureIndex) })
      // Back on the loop after the stop's own access, interior and return.
      let afterStop =
        stop.departureIndex
        + route.edges.count - base.edges.count + (stop.returnIndex - stop.departureIndex)
        + 20
      #expect(laps[stopLap].contains(afterStop))
      // The stop makes this lap longer than the next one.
      #expect(laps[stopLap].count > laps[stopLap + 1].count)
      return LapFixture(
        gate: gate,
        laps: laps,
        stopLap: stopLap,
        askAfterOccurrenceIndex: afterStop
      )
    }

    /// Three laps of the Daikoku loop that end in Daikoku PA.
    static func endingAtPA() throws -> LapFixture {
      let database = try replayGateDatabase()
      let planner = try ShutoRoutePlanner(database: database)
      let route = try planner.planCircuit(
        circuit: .daikokuYokohamaLoop,
        entryFacilityID: "shuto.ic.b.wangankanpachi",
        destinationParkingAreaID: "shuto.pa.daikoku",
        laps: 3
      )
      let laps = lapRanges(route)
      return LapFixture(
        gate: try onDemandGate(route: route, database: database),
        laps: laps,
        stopLap: 0,
        askAfterOccurrenceIndex: laps[0].lowerBound + laps[0].count / 2
      )
    }

    private static func onDemandGate(
      route: ShutoPlannedRoute,
      database: ShutoNetworkDatabase
    ) throws -> LiveNavigationReplayGate {
      let release = try ShutoCircuitProductReleaseBuilder.buildPlannedRouteRelease(
        context: try ShutoPlannedRouteRuntimeCompiler.NetworkContext(database: database),
        route: route
      )
      return LiveNavigationReplayGate(release: release, database: database)
    }

    private static func lapRanges(_ route: ShutoPlannedRoute) -> [Range<Int>] {
      let boundaries = route.lapBoundaryOccurrenceIndices
      return zip(boundaries, boundaries.dropFirst()).map { $0..<$1 }
    }
  }
#endif
