#if canImport(CoreLocation)
  import Foundation
  import KaidoDomain
  import KaidoNavigation
  import KaidoRouting
  import Testing

  /// A mid-route PA stop replaces a stretch of the road the route would
  /// otherwise drive. A car that stays on that road has passed the stop by.
  @Suite("1 Hz PA stop bypass replay")
  struct ParkingStopBypassReplayTests {
    @Test(
      "passing a mid-route PA stop skips it silently and the drive goes on",
      arguments: [UInt64(1), 2]
    )
    func passingAStopSkipsIt(seed: UInt64) async throws {
      let fixture = try StopFixture.daikokuLoopWithLapOneStop()
      let run = try await fixture.gate.run(legs: fixture.bypassLegs(), seed: seed)
      let summary = gateLine(
        file: "daikoku-loop-lap-one-stop", seed: seed, run: run, label: "STOP-BYPASS"
      )
      print(summary)
      #expect(run.reachedCompletion, "\(summary)")
      #expect(!run.completedEarly(), "\(summary)")
      #expect(run.wrongCommitCount() == 0, "\(summary)")
      #expect(run.falseRouteRecoveryCount == 0, "\(summary)")
      #expect(
        !run.records.contains { $0.phase == .routeRecovery || $0.recoveryStatus != .inactive },
        "\(summary)"
      )
      #expect(
        run.longestUnadmittedSeconds <= LiveNavigationReplayGateTests.maximumUnadmittedSeconds,
        "\(summary)"
      )
      let snapshot = try #require(run.finalSnapshot)
      let skipped = Set(snapshot.skippedOccurrenceIDs)
      let completed = Set(snapshot.completedOccurrenceIDs)
      #expect(fixture.stopOccurrenceIDs.allSatisfy(skipped.contains), "\(summary)")
      #expect(fixture.stopOccurrenceIDs.allSatisfy { !completed.contains($0) }, "\(summary)")
    }

    @Test("making a mid-route PA stop still visits it", arguments: [UInt64(1), 2])
    func makingAStopVisitsIt(seed: UInt64) async throws {
      let fixture = try StopFixture.daikokuLoopWithLapOneStop()
      let run = try await fixture.gate.run(legs: fixture.gate.plannedLegs(), seed: seed)
      let summary = gateLine(
        file: "daikoku-loop-lap-one-stop", seed: seed, run: run, label: "STOP-MADE"
      )
      print(summary)
      #expect(run.reachedCompletion, "\(summary)")
      #expect(run.wrongCommitCount() == 0, "\(summary)")
      #expect(run.falseRouteRecoveryCount == 0, "\(summary)")
      let snapshot = try #require(run.finalSnapshot)
      #expect(
        !fixture.stopOccurrenceIDs.contains(where: Set(snapshot.skippedOccurrenceIDs).contains),
        "\(summary)"
      )
    }
  }

  private struct StopFixture {
    let gate: LiveNavigationReplayGate
    let database: ShutoNetworkDatabase
    /// The stop's own path in the plan: approach, PA interior and return.
    let stopIndices: Range<Int>
    /// The road the stop replaced.
    let bypass: [ShutoNetworkDatabase.Edge]

    var stopOccurrenceIDs: [String] {
      gate.release.navigation.bundle.routePlan.occurrences
        .filter { stopIndices.contains($0.index) }
        .map(\.id)
    }

    /// Three laps of the Daikoku loop from Wangan-Kanpachi to Haneda with the
    /// Daikoku PA stop, which the planner places in the first lap.
    static func daikokuLoopWithLapOneStop() throws -> StopFixture {
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
      let release = try ShutoCircuitProductReleaseBuilder.buildPlannedRouteRelease(
        context: try ShutoPlannedRouteRuntimeCompiler.NetworkContext(database: database),
        route: route
      )
      let stopLength =
        route.edges.count - base.edges.count + stop.returnIndex - stop.departureIndex
      return StopFixture(
        gate: LiveNavigationReplayGate(release: release, database: database),
        database: database,
        stopIndices: stop.departureIndex..<(stop.departureIndex + stopLength),
        bypass: Array(base.edges[stop.departureIndex..<stop.returnIndex])
      )
    }

    /// The planned drive with the stop's own path replaced by the road it
    /// replaced.
    func bypassLegs() -> [ReplayGateLeg] {
      let nodes = Dictionary(uniqueKeysWithValues: database.nodes.map { ($0.nodeID, $0) })
      let bypassLegs = bypass.map { edge in
        ReplayGateLeg(
          kind: .offPlan(edge.edgeID),
          coordinates: [edge.fromNodeID, edge.toNodeID].map {
            MatcherCoordinate(latitude: nodes[$0]!.latitude, longitude: nodes[$0]!.longitude)
          },
          speedMetersPerSecond: LiveNavigationReplayGate.mainlineSpeed
        )
      }
      var legs: [ReplayGateLeg] = []
      for leg in gate.plannedLegs() {
        if case .occurrence(let index) = leg.kind, stopIndices.contains(index) {
          if index == stopIndices.lowerBound { legs += bypassLegs }
          continue
        }
        legs.append(leg)
      }
      return legs
    }
  }
#endif
