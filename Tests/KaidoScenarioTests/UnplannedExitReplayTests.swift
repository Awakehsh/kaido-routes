#if canImport(CoreLocation)
  import Foundation
  import KaidoDomain
  import KaidoNavigation
  import KaidoRouting
  import Testing

  /// A car that leaves the expressway where the plan does not is handed over
  /// to ordinary-road guidance: the session ends the expressway portion with
  /// UNPLANNED_EXIT once fixes are far from every road of the plan.
  @Suite("1 Hz unplanned-exit replay")
  struct UnplannedExitReplayTests {
    @Test(
      "leaving at an exit the plan does not take hands the drive over",
      arguments: [
        "c1-inner-shibakoen-to-shiodome-product-release.json",
        "c2-inner-oujiminami-itabashihoncho-product-release.json",
        "wangan-westbound-chidoricho-daikoku-pa-product-release.json",
      ],
      [UInt64(1), 2]
    )
    func leavingAtAnUnplannedExitHandsOver(file: String, seed: UInt64) async throws {
      let gate = try replayGate(file)
      let (movementIndex, alternative) = try #require(
        try Self.exitBranch(gate, before: gate.finalDivergenceIndex)
      )
      let run = try await gate.run(
        legs: gate.unplannedExitLegs(movementIndex: movementIndex, alternativeEdgeID: alternative),
        seed: seed
      )
      let summary = Self.line(file: file, seed: seed, run: run)
      print(summary)
      #expect(run.handedOver, "\(summary)")
      #expect(!run.reachedCompletion, "\(summary)")
      #expect(run.wrongCommitCount() == 0, "\(summary)")
    }

    /// A fix past the planned exit can be both the exit's own evidence and
    /// clear of every expressway road. These drives took their exit and once
    /// heard "left the route" on the fix that completes it.
    @Test(
      "taking the planned exit completes it, never hands over",
      arguments: [("daikoku-loop-lap-one-stop:1", "URBAN", UInt64(29)), ("c2-inner-oujiminami-itabashihoncho-product-release.json", "UNDER2X", 37)]
    )
    func plannedExitCompletes(fixture: String, noise: String, seed: UInt64) async throws {
      let gate =
        fixture == "daikoku-loop-lap-one-stop:1"
        ? try Self.daikokuLoopWithLapOneStop(laps: 1) : try replayGate(fixture)
      let run = try await gate.run(
        legs: gate.plannedLegs(),
        seed: seed,
        noise: noise == "UNDER2X" ? .underReported : .urban
      )
      let summary = Self.line(file: fixture, seed: seed, run: run)
      print(summary)
      #expect(run.reachedCompletion, "\(summary)")
      #expect(run.records.last?.phaseTrigger == "USER_CONFIRMED_EXIT_HANDOFF_COMPLETED", "\(summary)")
    }

    /// The lap-1 Daikoku PA stop's approach diverted down the road to the
    /// Daikoku-futou exit: that road leaves the expressway.
    @Test("a PA stop's approach diverted off the expressway hands the drive over", arguments: [UInt64(1), 2])
    func divertedStopApproachHandsOver(seed: UInt64) async throws {
      let gate = try Self.daikokuLoopWithLapOneStop()
      let plan = gate.release.navigation.bundle.routePlan
      let firstVisit = try #require(plan.occurrences.first { $0.kind == .paVisit }?.index)
      let movementIndex = try #require(
        (1...firstVisit).last { !gate.alternativeEdgeIDs(atMovementIndex: $0).isEmpty }
      )
      let alternative = try #require(gate.alternativeEdgeIDs(atMovementIndex: movementIndex).first)
      let run = try await gate.run(
        legs: gate.unplannedExitLegs(movementIndex: movementIndex, alternativeEdgeID: alternative),
        seed: seed
      )
      let summary = Self.line(file: "daikoku-loop-lap-one-stop", seed: seed, run: run)
      print(summary)
      #expect(run.handedOver, "\(summary)")
      #expect(run.wrongCommitCount() == 0, "\(summary)")
    }

    /// The under-reported destination misses that, before the handover, ended
    /// in ROUTE INTERRUPTED or froze in strict route after the car had left
    /// at Daikoku-futou. Each must now end near the destination or hand over.
    @Test(
      "a car that passed its destination PA and left the expressway never sits frozen",
      arguments: [
        ("wangan-westbound-chidoricho-daikoku-pa-product-release.json", [UInt64(2), 3, 7, 9, 16, 17]),
        ("daikoku-yokohama-wangankanpachi-daikoku-pa-product-release.json", [UInt64(9), 16, 17, 18, 20]),
        ("scenic-harumi-daikoku-pa-product-release.json", [UInt64(2), 9, 10, 13, 15, 19, 20]),
      ]
    )
    func passedDestinationNeverSitsFrozen(file: String, seeds: [UInt64]) async throws {
      let gate = try replayGate(file)
      let movementIndex = gate.finalDivergenceIndex
      let alternative = try #require(gate.alternativeEdgeIDs(atMovementIndex: movementIndex).first)
      for seed in seeds {
        let run = try await gate.run(
          legs: gate.unplannedExitLegs(movementIndex: movementIndex, alternativeEdgeID: alternative),
          seed: seed,
          noise: .underReported
        )
        let summary = Self.line(file: file, seed: seed, run: run)
        print(summary)
        #expect(run.reachedCompletion || run.handedOver, "\(summary)")
      }
    }

    /// Three laps of the Daikoku loop from Wangan-Kanpachi to Haneda with the
    /// Daikoku PA stop, which the planner places in the first lap.
    static func daikokuLoopWithLapOneStop(laps: Int = 3) throws -> LiveNavigationReplayGate {
      let database = try replayGateDatabase()
      let planner = try ShutoRoutePlanner(database: database)
      let base = try planner.planCircuit(
        circuit: .daikokuYokohamaLoop,
        entryFacilityID: "shuto.ic.b.wangankanpachi",
        exitFacilityID: "shuto.ic.1-haneda.haneda",
        laps: laps
      )
      let route = try planner.addingParkingStops(["shuto.pa.daikoku"], to: base)
      let release = try ShutoCircuitProductReleaseBuilder.buildPlannedRouteRelease(
        context: try ShutoPlannedRouteRuntimeCompiler.NetworkContext(database: database),
        route: route
      )
      return LiveNavigationReplayGate(release: release, database: database)
    }

    static func line(file: String, seed: UInt64, run: ReplayGateRun) -> String {
      let last = run.records.last
      let end = run.records.first { $0.phaseTrigger == "UNPLANNED_EXIT" } ?? last
      let left = run.records.first { $0.truth.offPlanDistanceMeters != nil }
      let surface = run.records.first {
        if case .egress = $0.truth.kind { return true } else { return false }
      }
      // Time and distance driven from `start` to the handover, or to the end
      // of the run without one.
      func since(_ start: ReplayGateFixRecord?) -> String {
        guard let start, let end else { return "-" }
        guard end.second >= start.second else { return "before" }
        let meters = run.records.filter { $0.second >= start.second && $0.second < end.second }
          .reduce(0) { $0 + $1.truth.speedMetersPerSecond }
        return "\(end.second - start.second)s/\(Int(meters))m"
      }
      return "UNPLANNED-EXIT \(file) seed=\(seed) handedOver=\(run.handedOver) completed=\(run.reachedCompletion)"
        + " trigger=\(last?.phaseTrigger ?? "-") final=\(last.map { "\($0.phase)/\($0.recoveryStatus)" } ?? "-")"
        + " afterLeaving=\(since(left)) onSurface=\(since(surface)) wrong=\(run.wrongCommitCount())"
    }

    /// The last choice of road before `limit` whose other road leads,
    /// without a further choice, to an exit facility.
    static func exitBranch(
      _ gate: LiveNavigationReplayGate,
      before limit: Int
    ) throws -> (Int, String)? {
      let database = try replayGateDatabase()
      let exitEdges = Set(
        database.directionalFacilities.filter(\.canExit).flatMap { $0.exitEdgeCandidates.map(\.edgeID) }
      )
      let outgoing = Dictionary(grouping: database.edges, by: \.fromNodeID)
      let edges = Dictionary(uniqueKeysWithValues: database.edges.map { ($0.edgeID, $0) })
      func leadsToExit(_ edgeID: String) -> Bool {
        guard var edge = edges[edgeID] else { return false }
        var meters = 0.0
        while meters < 1_500 {
          if exitEdges.contains(edge.edgeID) { return true }
          let next = (outgoing[edge.toNodeID] ?? []).filter { $0.toNodeID != edge.fromNodeID }
          guard next.count == 1 else { return false }
          edge = next[0]
          meters += edge.lengthMeters
        }
        return false
      }
      for index in stride(from: limit - 1, through: 1, by: -1) {
        if let alternative = gate.alternativeEdgeIDs(atMovementIndex: index).first(where: leadsToExit) {
          return (index, alternative)
        }
      }
      return nil
    }
  }
#endif
