#if canImport(CoreLocation)
  import Foundation
  import KaidoDomain
  import KaidoNavigation
  import KaidoRouting
  import Testing

  /// C1 inner Shibakoen→Shiodome leaves the loop at 汐留, where the exit ramp
  /// runs down beside the C1 mainline the drive began on. A fix there cannot
  /// tell the two apart until the ramp turns away at the bottom.
  @Suite("1 Hz final exit beside a road the plan already drove")
  struct FinalExitReplayTests {
    static let file = "c1-inner-shibakoen-to-shiodome-product-release.json"

    /// With the mainline holding the exit's progress back, these drives went
    /// 37–46 s unadmitted down the ramp; main admits it within 18–23 s.
    @Test(
      "the exit ramp is admitted while the car drives down it",
      arguments: [("URBAN", UInt64(5)), ("URBAN", 12), ("MULTIPATH", 3), ("MULTIPATH", 11)]
    )
    func admitsTheExitRamp(noise: String, seed: UInt64) async throws {
      let gate = try replayGate(Self.file)
      let run = try await gate.run(
        legs: gate.plannedLegs(),
        seed: seed,
        noise: noise == "MULTIPATH" ? .multipath : .urban
      )
      let summary = gateLine(file: Self.file, seed: seed, run: run, label: noise)
      print(summary)
      #expect(run.reachedCompletion, "\(summary)")
      #expect(!run.completedEarly(), "\(summary)")
      #expect(run.wrongCommitCount() == 0, "\(summary)")
      // Past the route end the drive waits on completion, which
      // RouteEndReplayTests bounds; this pin is about the ramp.
      #expect(run.longestUnadmittedSecondsBeforeEgress <= 30, "\(summary)")
    }

    /// Main completed these drives at the exit the car had driven past.
    @Test(
      "driving on past the final exit never completes the drive",
      arguments: [
        ("URBAN", UInt64(11)), ("URBAN", 13), ("URBAN", 19), ("URBAN", 23),
        ("MULTIPATH", 15), ("MULTIPATH", 23),
      ]
    )
    func missedExitNeverCompletes(noise: String, seed: UInt64) async throws {
      let gate = try replayGate(Self.file)
      let movementIndex = gate.finalDivergenceIndex
      for alternative in gate.alternativeEdgeIDs(atMovementIndex: movementIndex) {
        let run = try await gate.run(
          legs: gate.wrongBranchLegs(
            movementIndex: movementIndex,
            alternativeEdgeID: alternative,
            branchMeters: 1_500
          ),
          seed: seed,
          noise: noise == "MULTIPATH" ? .multipath : .urban
        )
        let summary =
          branchLine(
            file: Self.file,
            movementIndex: movementIndex,
            alternative: alternative,
            seed: seed,
            run: run
          ) + " \(noise)"
        print("MISSED-FINAL " + summary)
        #expect(!run.reachedCompletion, "\(summary)")
        #expect(run.offPlanPromptCount(movementIndex: movementIndex) == 0, "\(summary)")
        #expect(
          (run.deviationDetectedAfterOffPlanMeters ?? .infinity)
            <= LiveNavigationReplayGateTests.maximumDeviationDetectionMeters,
          "\(summary)"
        )
      }
    }

    /// One lap of the C1 outer loop. Its entrance ramp runs beside the
    /// mainline the lap ends on, and its exit beside the mainline it began
    /// on: roads only a lap leads back to, which once held both ends of the
    /// drive unadmitted for 30–35 s.
    @Test(
      "a C1 outer lap is admitted at both ends",
      arguments: [("URBAN", UInt64(5)), ("URBAN", 28), ("MULTIPATH", 28)]
    )
    func admitsBothEndsOfTheOuterLap(noise: String, seed: UInt64) async throws {
      let gate = try Self.outerLap()
      let run = try await gate.run(
        legs: gate.plannedLegs(),
        seed: seed,
        noise: noise == "MULTIPATH" ? .multipath : .urban
      )
      let summary = gateLine(file: "c1-outer-lap", seed: seed, run: run, label: noise)
      print(summary)
      #expect(run.reachedCompletion, "\(summary)")
      #expect(run.wrongCommitCount() == 0, "\(summary)")
      #expect(run.longestUnadmittedSeconds <= 25, "\(summary)")
    }

    /// Admitted progress ran down the exit ahead of a car that had missed
    /// it, until the road the car was on no longer counted as one it could
    /// be on, and the drive never left the plan.
    @Test("driving on past the C1 outer lap's exit is caught", arguments: [UInt64(11)])
    func missedOuterExitIsCaught(seed: UInt64) async throws {
      let gate = try Self.outerLap()
      let movementIndex = gate.finalDivergenceIndex
      for alternative in gate.alternativeEdgeIDs(atMovementIndex: movementIndex) {
        let run = try await gate.run(
          legs: gate.wrongBranchLegs(
            movementIndex: movementIndex,
            alternativeEdgeID: alternative,
            branchMeters: 1_500
          ),
          seed: seed,
          noise: .multipath
        )
        let summary = branchLine(
          file: "c1-outer-lap",
          movementIndex: movementIndex,
          alternative: alternative,
          seed: seed,
          run: run
        )
        print("MISSED-FINAL " + summary)
        #expect(!run.reachedCompletion, "\(summary)")
        #expect(
          (run.deviationDetectedAfterOffPlanMeters ?? .infinity)
            <= LiveNavigationReplayGateTests.maximumDeviationDetectionMeters,
          "\(summary)"
        )
      }
    }

    private static func outerLap() throws -> LiveNavigationReplayGate {
      let database = try replayGateDatabase()
      let planner = try ShutoRoutePlanner(database: database)
      let entry = try #require(
        planner.circuitEntranceCandidates(for: .c1Outer).first { $0.routeID == "C1" }
      )
      let pairing = try planner.recommendedCircuitPairing(
        for: .c1Outer,
        entranceFacilityID: entry.facilityID,
        evidence: .etcNormalCarFrom2026October
      )
      let route = try planner.planCircuit(
        circuit: .c1Outer,
        entryFacilityID: entry.facilityID,
        exitFacilityID: pairing.exit.facilityID,
        laps: 1
      )
      let release = try ShutoCircuitProductReleaseBuilder.buildPlannedRouteRelease(
        context: try ShutoPlannedRouteRuntimeCompiler.NetworkContext(database: database),
        route: route
      )
      return LiveNavigationReplayGate(release: release, database: database)
    }
  }
#endif
