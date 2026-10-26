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
      try await expectStopSkipped(noise: "URBAN", seed: seed)
    }

    /// The road the stop replaced is driven again on the next lap, outside
    /// the passes the matcher weighs while the car is still on the first:
    /// these fixes matched it as an off-plan road too unsure to skip the stop
    /// on, and the stop was recorded as visited.
    @Test(
      "passing a stop by on a road the next lap drives still skips it",
      arguments: [("URBAN", UInt64(4)), ("URBAN", 39), ("MULTIPATH", 23)]
    )
    func passingAStopOnTheNextLapsRoadSkipsIt(noise: String, seed: UInt64) async throws {
      try await expectStopSkipped(noise: noise, seed: seed)
    }

    private func expectStopSkipped(noise: String, seed: UInt64) async throws {
      let fixture = try StopFixture.daikokuLoopWithLapOneStop()
      let run = try await fixture.gate.run(
        legs: fixture.bypassLegs(),
        seed: seed,
        noise: noise == "MULTIPATH" ? .multipath : .urban
      )
      let summary = gateLine(
        file: "daikoku-loop-lap-one-stop", seed: seed, run: run,
        label: noise == "URBAN" ? "STOP-BYPASS" : "STOP-BYPASS-\(noise)"
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

    /// Daikoku PA as a first-lap stop, passed by, then the car leaves the
    /// expressway further on: the stop is skipped and the drive hands over.
    @Test("passing a mid-route PA and leaving the expressway is a skip and a handover")
    func passingAWaypointPAThenLeaving() async throws {
      let fixture = try StopFixture.daikokuLoopWithLapOneStop()
      let gate = fixture.gate
      // The first branch after the stop that leaves the expressway: its path
      // ends where the network does and the car drives on along the street.
      func leavesTheExpressway(_ index: Int, _ alternative: String) -> Bool {
        let legs = gate.wrongBranchLegs(
          movementIndex: index, alternativeEdgeID: alternative, branchMeters: 1_500
        )
        guard let last = legs.last, case .offPlan(let road) = last.kind else { return false }
        return road.hasPrefix("street past")
      }
      var exit: (movement: Int, alternative: String)?
      for index in fixture.stopIndices.upperBound..<gate.routeEdgeIDs.count where exit == nil {
        if let alternative = gate.alternativeEdgeIDs(atMovementIndex: index)
          .first(where: { leavesTheExpressway(index, $0) })
        {
          exit = (index, alternative)
        }
      }
      let (movement, alternative) = try #require(exit)
      let branch = gate.wrongBranchLegs(movementIndex: movement, alternativeEdgeID: alternative, branchMeters: 1_500)
      let lastPlanned = try #require(branch.lastIndex { if case .occurrence = $0.kind { true } else { false } })
      let legs = fixture.bypassLegs().prefix { leg in
        if case .occurrence(let index) = leg.kind { return index < movement }
        return true
      } + branch[(lastPlanned + 1)...]
      let run = try await gate.run(legs: Array(legs), seed: 1, noise: .urban)
      let summary = gateLine(file: "daikoku-loop-lap-one-stop", seed: 1, run: run, label: "WAYPOINT-PA-EXIT")
      print(summary)
      let snapshot = try #require(run.finalSnapshot)
      #expect(fixture.stopOccurrenceIDs.allSatisfy(Set(snapshot.skippedOccurrenceIDs).contains), "\(summary)")
      #expect(run.records.last?.phaseTrigger == "UNPLANNED_EXIT", "\(summary)")
      #expect(!run.reachedCompletion, "\(summary)")
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

  extension ParkingStopBypassReplayTests {
    /// Main caught a car turning into the stop's PA again on the next lap
    /// within 28 s in every replay; a window that left the PA's road out of
    /// the competing roads took up to 38 s.
    static let maximumReentryDetectionSeconds = 30

    @Test(
      "turning into the stop's PA again on the next lap is caught",
      arguments: [("URBAN", UInt64(12)), ("MULTIPATH", 5)]
    )
    func reenteringTheStopIsCaught(noise: String, seed: UInt64) async throws {
      let fixture = try StopFixture.daikokuLoopWithLapOneStop()
      let run = try await fixture.gate.run(
        legs: fixture.reentryLegs(),
        seed: seed,
        noise: noise == "MULTIPATH" ? .multipath : .urban
      )
      let summary = gateLine(
        file: "daikoku-loop-lap-one-stop", seed: seed, run: run, label: "STOP-REENTRY-\(noise)"
      )
      print(summary)
      let left = try #require(run.records.first { $0.truth.offPlanDistanceMeters != nil })
      let detected = try #require(
        run.records.first { $0.second >= left.second && $0.phase == .routeRecovery },
        "\(summary)"
      )
      #expect(detected.second - left.second <= Self.maximumReentryDetectionSeconds, "\(summary)")
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

    /// The planned drive with the next lap's pass of the road the stop
    /// replaced driven along the stop's own path instead.
    func reentryLegs() -> [ReplayGateLeg] {
      let ids = gate.routeEdgeIDs
      let bypassIDs = bypass.map(\.edgeID)
      let start = (stopIndices.upperBound..<(ids.count - bypassIDs.count)).first {
        Array(ids[$0..<($0 + bypassIDs.count)]) == bypassIDs
      }!
      let replaced = start..<(start + bypassIDs.count)
      let planned = gate.plannedLegs()
      let stopLegs: [ReplayGateLeg] = planned.compactMap { leg in
        guard case .occurrence(let index) = leg.kind, stopIndices.contains(index) else {
          return nil
        }
        return ReplayGateLeg(
          kind: .offPlan(ids[index]),
          coordinates: leg.coordinates,
          speedMetersPerSecond: leg.speedMetersPerSecond,
          dwellSeconds: leg.dwellSeconds
        )
      }
      var legs: [ReplayGateLeg] = []
      for leg in planned {
        if case .occurrence(let index) = leg.kind, replaced.contains(index) {
          if index == replaced.lowerBound { legs += stopLegs }
          continue
        }
        legs.append(leg)
      }
      return legs
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
