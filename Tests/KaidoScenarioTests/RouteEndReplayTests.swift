#if canImport(CoreLocation)
  import Foundation
  import KaidoNavigation
  import KaidoRouting
  import Testing

  /// The exit ramps at C1 Shiodome and C2 Itabashihoncho run within a few
  /// metres of the road they leave for their whole length, and past
  /// Shiodome that road is the plan's own first pass. These drives once froze
  /// before the exit and never ended, ended on the first pass two kilometres
  /// before the end, or ended at an exit the car had driven past.
  @Suite("1 Hz route end at an exit beside the road it leaves")
  struct RouteEndReplayTests {
    static let maximumCompletionDelaySeconds = 30

    @Test(
      "a drive that takes its exit completes once past it",
      arguments: [
        // The Itabashihoncho ramp beside the Route 5 mainline: progress froze
        // 500 m before the end with no egress.
        ("c2-inner-oujiminami-itabashihoncho-product-release.json", "URBAN", UInt64(15)),
        ("c2-inner-oujiminami-itabashihoncho-product-release.json", "MULTIPATH", 6),
        ("c2-inner-oujiminami-itabashihoncho-product-release.json", "MULTIPATH", 11),
        ("c2-inner-oujiminami-itabashihoncho-product-release.json", "MULTIPATH", 18),
        // The Shiodome ramp read as the covered first pass beside it, which
        // left reacquisition pending for the rest of the drive.
        ("c1-inner-shibakoen-to-shiodome-product-release.json", "UNDER2X", 1),
        ("c1-inner-shibakoen-to-shiodome-product-release.json", "UNDER2X", 6),
        // Admitted progress stops before the Shiodome ramp; the drive ended
        // on the ramp, or with a matcher limited to nearby passes, never.
        ("c1-inner-shibakoen-to-shiodome-product-release.json", "URBAN", 34),
        ("c1-inner-shibakoen-to-shiodome-product-release.json", "MULTIPATH", 18),
      ]
    )
    func completesPastTheExit(file: String, noise: String, seed: UInt64) async throws {
      let gate = try replayGate(file)
      let run = try await gate.run(legs: gate.plannedLegs(), seed: seed, noise: Self.noise(noise))
      let summary = gateLine(file: file, seed: seed, run: run, label: "ROUTE-END-\(noise)")
      print(summary)
      #expect(run.reachedCompletion, "\(summary)")
      #expect(!run.completedEarly(), "\(summary)")
      #expect(
        (run.completionDelaySeconds ?? .max) <= Self.maximumCompletionDelaySeconds,
        "\(summary)"
      )
    }

    /// Driving on past Shiodome follows the plan's own first pass beside
    /// the ramp; the drive ended there as if the car had taken the exit.
    @Test(
      "driving past the exit never completes the drive",
      arguments: [
        ("c1-inner-shibakoen-to-shiodome-product-release.json", "URBAN", UInt64(11)),
        ("c1-inner-shibakoen-to-shiodome-product-release.json", "URBAN", 13),
        ("c1-inner-shibakoen-to-shiodome-product-release.json", "MULTIPATH", 15),
        ("c1-inner-shibakoen-to-shiodome-product-release.json", "MULTIPATH", 17),
      ]
    )
    func missedExitNeverCompletes(file: String, noise: String, seed: UInt64) async throws {
      let gate = try replayGate(file)
      let movementIndex = gate.finalDivergenceIndex
      let alternatives = gate.alternativeEdgeIDs(atMovementIndex: movementIndex)
      #expect(!alternatives.isEmpty)
      for alternative in alternatives {
        let run = try await gate.run(
          legs: gate.wrongBranchLegs(
            movementIndex: movementIndex,
            alternativeEdgeID: alternative,
            branchMeters: 1_500
          ),
          seed: seed,
          noise: Self.noise(noise)
        )
        let summary = gateLine(file: file, seed: seed, run: run, label: "MISSED-EXIT-\(noise)")
        print(summary)
        #expect(!run.reachedCompletion, "\(summary)")
      }
    }

    /// On the last of three laps the car drives on past Shiodome along the
    /// C1 mainline and recovery starts; fixes scattered off the mainline by
    /// twice the error they report then lay clear of it by four times that
    /// error, and the drive ended as if the car had taken the exit.
    @Test("driving past the exit in recovery never completes the drive")
    func missedExitInRecoveryNeverCompletes() async throws {
      let gate = try Self.threeLapGate()
      let movementIndex = gate.finalDivergenceIndex
      let alternatives = gate.alternativeEdgeIDs(atMovementIndex: movementIndex)
      #expect(!alternatives.isEmpty)
      for alternative in alternatives {
        let run = try await gate.run(
          legs: gate.wrongBranchLegs(
            movementIndex: movementIndex,
            alternativeEdgeID: alternative,
            branchMeters: 1_500
          ),
          seed: 7,
          noise: .underReported
        )
        let summary = gateLine(file: "c1-inner:3", seed: 7, run: run, label: "MISSED-EXIT-UNDER2X")
        print(summary)
        #expect(!run.reachedCompletion, "\(summary)")
      }
    }

    /// Three laps of C1 inner from Shibakoen to Shiodome.
    private static func threeLapGate() throws -> LiveNavigationReplayGate {
      let database = try replayGateDatabase()
      let route = try ShutoRoutePlanner(database: database).planCircuit(
        circuit: .c1Inner,
        entryFacilityID: "shuto.ic.c1.shibakouen",
        exitFacilityID: "shuto.ic.c1.shiodome",
        laps: 3
      )
      let release = try ShutoCircuitProductReleaseBuilder.buildPlannedRouteRelease(
        context: try ShutoPlannedRouteRuntimeCompiler.NetworkContext(database: database),
        route: route
      )
      return LiveNavigationReplayGate(release: release, database: database)
    }

    /// The first pass of C1 inner from Shibakoen runs beside the Shiodome
    /// exit ramp two minutes into the drive; the matcher placing it on the
    /// ramp ended the drive there.
    @Test("passing the exit early in the drive never ends it")
    func earlyPassBesideTheExitNeverEnds() async throws {
      let file = "c1-inner-shibakoen-to-shiodome-product-release.json"
      let gate = try replayGate(file)
      let run = try await gate.run(legs: gate.plannedLegs(), seed: 32, noise: .underReported)
      let summary = gateLine(file: file, seed: 32, run: run, label: "ROUTE-END-UNDER2X")
      print(summary)
      #expect(!run.completedEarly(), "\(summary)")
    }

    /// On the last lap the matcher can still hold the car on an earlier
    /// lap's pass of the same road when it takes the exit, so neither
    /// progress nor the matcher's placement reaches the exit side. These
    /// drives were handed over as having left the route at an unplanned exit.
    @Test(
      "a loop whose matcher is laps behind at the exit still completes there",
      arguments: [("c1-inner", "URBAN", UInt64(3)), ("c1-outer", "UNDER2X", 38)]
    )
    func lapsBehindAtTheExitCompletes(loop: String, noise: String, seed: UInt64) async throws {
      let gate = try Self.threeLapGate(loop)
      let run = try await gate.run(legs: gate.plannedLegs(), seed: seed, noise: Self.noise(noise))
      let summary = gateLine(file: "\(loop):3", seed: seed, run: run, label: "ROUTE-END-\(noise)")
      print(summary)
      #expect(run.reachedCompletion, "\(summary)")
      #expect(!run.completedEarly(), "\(summary)")
      #expect(run.records.last?.phaseTrigger == "USER_CONFIRMED_EXIT_HANDOFF_COMPLETED", "\(summary)")
      #expect(
        (run.completionDelaySeconds ?? .max) <= Self.maximumCompletionDelaySeconds,
        "\(summary)"
      )
    }

    @Test(
      "a first-pass placement beside the exit never starts a false recovery",
      arguments: ["bundled", "c1-inner:3"]
    )
    func firstPassBesideTheExitNeverRecovers(fixture: String) async throws {
      let gate = fixture == "bundled"
        ? try replayGate("c1-inner-shibakoen-to-shiodome-product-release.json")
        : try Self.threeLapGate("c1-inner")
      let run = try await gate.run(legs: gate.plannedLegs(), seed: 27, noise: .underReported)
      let summary = gateLine(file: fixture, seed: 27, run: run, label: "ROUTE-END-UNDER2X")
      print(summary)
      #expect(run.falseRouteRecoveryCount == 0, "\(summary)")
      #expect(run.reachedCompletion, "\(summary)")
      #expect(!run.completedEarly(), "\(summary)")
    }

    /// Three laps of C1 inner from Shibakoen to Shiodome, or of C1 outer
    /// from its first C1 entrance to the exit the planner recommends.
    private static func threeLapGate(_ loop: String) throws -> LiveNavigationReplayGate {
      let database = try replayGateDatabase()
      let planner = try ShutoRoutePlanner(database: database)
      let route: ShutoPlannedRoute
      if loop == "c1-inner" {
        route = try planner.planCircuit(
          circuit: .c1Inner,
          entryFacilityID: "shuto.ic.c1.shibakouen",
          exitFacilityID: "shuto.ic.c1.shiodome",
          laps: 3
        )
      } else {
        let entry = try #require(
          planner.circuitEntranceCandidates(for: .c1Outer).first { $0.routeID == "C1" }
        ).facilityID
        let exit = try planner.recommendedCircuitPairing(
          for: .c1Outer, entranceFacilityID: entry, evidence: .etcNormalCarFrom2026October
        ).exit.facilityID
        route = try planner.planCircuit(
          circuit: .c1Outer, entryFacilityID: entry, exitFacilityID: exit, laps: 3
        )
      }
      let release = try ShutoCircuitProductReleaseBuilder.buildPlannedRouteRelease(
        context: try ShutoPlannedRouteRuntimeCompiler.NetworkContext(database: database),
        route: route
      )
      return LiveNavigationReplayGate(release: release, database: database)
    }

    private static func noise(_ label: String) -> ReplayGateNoiseModel {
      switch label {
      case "MULTIPATH": return .multipath
      case "UNDER2X": return .underReported
      default: return .urban
      }
    }
  }
#endif
