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

    /// Fixes scattered beyond their reported error, off both an exit ramp and
    /// the road it runs a few metres beside, read the same whichever the car
    /// is on: past Kasumigaseki, Angyo and Yotsugi the drive ended on the road
    /// it had driven on past the exit, and on the ramp it ended early. Past
    /// Kasumigaseki, Angyo, Tomigaya and Fukuzumi it also ended hundreds of
    /// metres on, on fixes scattered 20–45 m off that road.
    @Test(
      "scatter beside the exit ends neither a missed exit nor the ramp early",
      arguments: [
        (ShutoCircuitDefinition.c1Inner, "shuto.ic.5.nishikanda", "shuto.ic.c1.kasumigaseki", UInt64(37)),
        (.c1Inner, "shuto.ic.s1.araijuku", "shuto.ic.s1.angyou", 13),
        (.c2InnerWithBayshore, "shuto.ic.7.ichinoe", "shuto.ic.c2.yotsugi", 13),
        (.c1Inner, "shuto.ic.4.gaien", "shuto.ic.c1.kasumigaseki", 37),
        (.c2InnerWithBayshore, "shuto.ic.s1.shingou", "shuto.ic.s1.angyou", 63),
        (.c2InnerWithBayshore, "shuto.ic.4.hatagaya", "shuto.ic.c2.tomigaya", 109),
        (.c2InnerWithBayshore, "shuto.ic.9.kiba", "shuto.ic.9.fukudumi", 51),
        (.daikokuYokohamaLoop, "shuto.ic.s1.araijuku", "shuto.ic.s1.angyou", 81),
      ]
    )
    func scatterBesideTheExit(
      circuit: ShutoCircuitDefinition, entry: String, exit: String, seed: UInt64
    ) async throws {
      let database = try replayGateDatabase()
      let route = try ShutoRoutePlanner(database: database).planCircuit(
        circuit: circuit, entryFacilityID: entry, exitFacilityID: exit, laps: 1
      )
      let release = try ShutoCircuitProductReleaseBuilder.buildPlannedRouteRelease(
        context: try ShutoPlannedRouteRuntimeCompiler.NetworkContext(database: database),
        route: route
      )
      let gate = LiveNavigationReplayGate(release: release, database: database)
      let planned = try await gate.run(legs: gate.plannedLegs(), seed: seed, noise: .underReported)
      let plannedSummary = gateLine(file: exit, seed: seed, run: planned, label: "ROUTE-END-UNDER2X")
      print(plannedSummary)
      #expect(planned.reachedCompletion, "\(plannedSummary)")
      #expect(!planned.completedEarly(), "\(plannedSummary)")
      let movementIndex = gate.finalDivergenceIndex
      for alternative in gate.alternativeEdgeIDs(atMovementIndex: movementIndex) {
        let missed = try await gate.run(
          legs: gate.wrongBranchLegs(
            movementIndex: movementIndex, alternativeEdgeID: alternative, branchMeters: 1_500
          ),
          seed: seed,
          noise: .underReported
        )
        let summary = gateLine(file: exit, seed: seed, run: missed, label: "MISSED-EXIT-UNDER2X")
        print(summary)
        #expect(!missed.reachedCompletion, "\(summary)")
      }
    }

    /// Angyo's exit ramp runs beside Route S1, and progress ran down it to
    /// the end of the plan while the car drove on along S1. The road the plan
    /// left was then not one the car could be on, so the drive never said it
    /// had missed the exit.
    @Test(
      "driving on past Angyo is seen",
      arguments: [ShutoCircuitDefinition.c1Inner, .c1Outer]
    )
    func missedAngyoIsSeen(circuit: ShutoCircuitDefinition) async throws {
      let database = try replayGateDatabase()
      let route = try ShutoRoutePlanner(database: database).planCircuit(
        circuit: circuit, entryFacilityID: "shuto.ic.s1.araijuku",
        exitFacilityID: "shuto.ic.s1.angyou", laps: 1
      )
      let release = try ShutoCircuitProductReleaseBuilder.buildPlannedRouteRelease(
        context: try ShutoPlannedRouteRuntimeCompiler.NetworkContext(database: database),
        route: route
      )
      let gate = LiveNavigationReplayGate(release: release, database: database)
      #expect(
        gate.alternativeEdgeIDs(atMovementIndex: gate.finalDivergenceIndex)
          .contains("osm.438367202.58.forward")
      )
      let missed = try await gate.run(
        legs: gate.wrongBranchLegs(
          movementIndex: gate.finalDivergenceIndex,
          alternativeEdgeID: "osm.438367202.58.forward",
          branchMeters: 1_500
        ),
        seed: 13,
        noise: .underReported
      )
      let summary = gateLine(file: "angyou", seed: 13, run: missed, label: "MISSED-EXIT-UNDER2X")
      print(summary)
      #expect(!missed.reachedCompletion, "\(summary)")
      #expect(missed.deviationDetectedAfterOffPlanMeters != nil, "\(summary)")
    }

    /// Mukojima's exit ends beside Route 6, the road the plan leaves at its
    /// last choice, and its street leaves at right angles; Takaracho's street
    /// runs on 25-40 degrees off C1. Fixes off those streets stay nearer the
    /// expressway than the exit, so the drive ended only 100 m out or not at
    /// all; scattered onto Route 6 at Mukojima's ramp end, they once read as
    /// the car driving on along it.
    @Test(
      "a drive off an exit whose street leaves beside the expressway completes",
      arguments: [
        (ShutoCircuitDefinition.c1Outer, "shuto.ic.6-mukojima.hakozaki", "shuto.ic.6-mukojima.mukoujima", "URBAN", UInt64(2)),
        (.c1Outer, "shuto.ic.6-mukojima.hakozaki", "shuto.ic.6-mukojima.mukoujima", "UNDER2X", 11),
        (.c1Outer, "shuto.ic.b.shinkiba", "shuto.ic.c1.takaracho", "UNDER2X", 9),
      ]
    )
    func streetBesideTheExpresswayCompletes(
      circuit: ShutoCircuitDefinition, entry: String, exit: String, noise: String, seed: UInt64
    ) async throws {
      let gate = try Self.gate(circuit, entry, exit)
      let run = try await gate.run(
        legs: gate.plannedLegs(), seed: seed, noise: noise == "URBAN" ? .urban : .underReported
      )
      let summary = gateLine(file: exit, seed: seed, run: run, label: "ROUTE-END-\(noise)")
      print(summary)
      #expect(run.reachedCompletion, "\(summary)")
      #expect((run.completionDelaySeconds ?? .max) <= Self.maximumCompletionDelaySeconds, "\(summary)")
      #expect(run.falseRouteRecoveryCount == 0, "\(summary)")
    }

    /// Tonomachi's ramp curves away from K6, and fixes 100 m down its street
    /// lay a metre nearer a bend than the ramp's end. Read as beside the exit,
    /// each one restarted the exit evidence, and the drive went 79 s
    /// unadmitted.
    @Test("fixes past a curved exit's end do not read as beside it")
    func pastACurvedExit() async throws {
      let gate = try Self.gate(.c2InnerWithBayshore, "shuto.ic.k6.daishi", "shuto.ic.k6.tonomachi")
      let run = try await gate.run(legs: gate.plannedLegs(), seed: 29, noise: .underReported)
      let summary = gateLine(file: "tonomachi", seed: 29, run: run, label: "ROUTE-END-UNDER2X")
      print(summary)
      #expect(run.reachedCompletion, "\(summary)")
      #expect(run.longestUnadmittedSeconds <= 75, "\(summary)")
    }

    private static func gate(
      _ circuit: ShutoCircuitDefinition, _ entry: String, _ exit: String
    ) throws -> LiveNavigationReplayGate {
      let database = try replayGateDatabase()
      let route = try ShutoRoutePlanner(database: database).planCircuit(
        circuit: circuit, entryFacilityID: entry, exitFacilityID: exit, laps: 1
      )
      let release = try ShutoCircuitProductReleaseBuilder.buildPlannedRouteRelease(
        context: try ShutoPlannedRouteRuntimeCompiler.NetworkContext(database: database),
        route: route
      )
      return LiveNavigationReplayGate(release: release, database: database)
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

    /// The Route 4 down exit at Gaien continues as ramp past the plan's last
    /// edge, and the fixes there run coarse (30–60 m). They denied the
    /// planned exit its own evidence until the car was off the expressway,
    /// where the unplanned-exit rule took the drive first.
    @Test(
      "a drive whose exit fixes turn coarse still completes at its planned exit",
      arguments: [
        // The final lap ends where Route 4 down branches off, so these
        // drives' first lap counts carry the geometry the seeds were found on.
        ("c1-inner", 3, "URBAN", UInt64(11)),
        ("c1-inner", 3, "MULTIPATH", 26),
        ("c1-inner", 2, "UNDER2X", 39),
        ("c1-outer", 3, "URBAN", 11),
        // One lap that ends at that branch.
        ("c1-inner", 1, "URBAN", 38),
        ("c1-inner", 1, "MULTIPATH", 37),
        ("c1-outer", 1, "URBAN", 38),
        ("c1-outer", 1, "MULTIPATH", 37),
      ]
    )
    func coarseFixesAtTheExitStillComplete(
      loop: String,
      laps: Int,
      noise: String,
      seed: UInt64
    ) async throws {
      let gate = try Self.gaienGate(loop, laps: laps)
      let run = try await gate.run(legs: gate.plannedLegs(), seed: seed, noise: Self.noise(noise))
      let summary = gateLine(file: "\(loop)-yoyogi-gaien:\(laps)", seed: seed, run: run, label: "ROUTE-END-\(noise)")
      print(summary)
      #expect(run.reachedCompletion, "\(summary)")
      #expect(!run.completedEarly(), "\(summary)")
      #expect(
        (run.completionDelaySeconds ?? .max) <= Self.maximumCompletionDelaySeconds,
        "\(summary)"
      )
    }

    /// Yoyogi to Gaien round C1: Route 4 up onto the loop and back down it.
    private static func gaienGate(_ loop: String, laps: Int) throws -> LiveNavigationReplayGate {
      let database = try replayGateDatabase()
      let planner = try ShutoRoutePlanner(database: database)
      let route = try planner.planCircuit(
        circuit: loop == "c1-inner" ? .c1Inner : .c1Outer,
        entryFacilityID: "shuto.ic.4.yoyogi",
        exitFacilityID: "shuto.ic.4.gaien",
        laps: laps
      )
      let release = try ShutoCircuitProductReleaseBuilder.buildPlannedRouteRelease(
        context: try ShutoPlannedRouteRuntimeCompiler.NetworkContext(database: database),
        route: route
      )
      return LiveNavigationReplayGate(release: release, database: database)
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

    /// A drive in along a radial route, around C1 and back out to an exit on
    /// the same radial: the other carriageway's exit, which the drive passed
    /// on the way in, ends tens of metres from this one. It counted as a road
    /// the car could be on instead of the exit, so nothing past the exit was
    /// ever clear of it and every drive was handed over as an unplanned exit.
    @Test(
      "a drive back out a radial completes beside the other carriageway's exit",
      arguments: [UInt64(1), 2]
    )
    func radialReturnCompletes(seed: UInt64) async throws {
      let gate = try Self.radialReturnGate()
      let run = try await gate.run(legs: gate.plannedLegs(), seed: seed, noise: .urban)
      let summary = gateLine(file: "c1-inner yokohamakohoku-shinyokohama", seed: seed, run: run, label: "ROUTE-END-URBAN")
      print(summary)
      #expect(run.reachedCompletion, "\(summary)")
      #expect(!run.completedEarly(), "\(summary)")
    }

    /// Missing that exit and driving on along the radial never completes.
    @Test("missing the exit back out a radial never completes", arguments: [UInt64(1), 2])
    func radialReturnMissedExitNeverCompletes(seed: UInt64) async throws {
      let gate = try Self.radialReturnGate()
      let movementIndex = gate.finalDivergenceIndex
      let alternatives = gate.alternativeEdgeIDs(atMovementIndex: movementIndex)
      #expect(!alternatives.isEmpty)
      for alternative in alternatives {
        let run = try await gate.run(
          legs: gate.wrongBranchLegs(
            movementIndex: movementIndex, alternativeEdgeID: alternative, branchMeters: 1_500
          ),
          seed: seed,
          noise: .urban
        )
        let summary = gateLine(file: "c1-inner yokohamakohoku-shinyokohama", seed: seed, run: run, label: "MISSED-EXIT-URBAN")
        print(summary)
        #expect(!run.reachedCompletion, "\(summary)")
      }
    }

    /// Yokohama North Route from Yokohama-Kohoku, C1 inner, back to
    /// Shin-Yokohama.
    private static func radialReturnGate() throws -> LiveNavigationReplayGate {
      let database = try replayGateDatabase()
      let route = try ShutoRoutePlanner(database: database).planCircuit(
        circuit: .c1Inner,
        entryFacilityID: "shuto.ic.k7-yokohama-kita.yokohamakohoku",
        exitFacilityID: "shuto.ic.k7-yokohama-kita.shinyokohama",
        laps: 1
      )
      let release = try ShutoCircuitProductReleaseBuilder.buildPlannedRouteRelease(
        context: try ShutoPlannedRouteRuntimeCompiler.NetworkContext(database: database),
        route: route
      )
      return LiveNavigationReplayGate(release: release, database: database)
    }

    /// Exits whose street runs on beside or under the road they leave, and
    /// an exit that leaves by two ramps. Off the expressway, the car was
    /// nearer that road, or the other ramp, than the exit, and every drive
    /// was handed over as an unplanned exit.
    @Test(
      "a drive off at an exit beside the road it leaves completes",
      arguments: [
        (Self.shintoshin, UInt64(1)), (Self.shintoshin, UInt64(2)),
        (Self.senjuShinbashi, UInt64(1)), (Self.senjuShinbashi, UInt64(2)),
        (Self.eifuku, UInt64(1)), (Self.eifuku, UInt64(2)),
        (Self.mukoujima, UInt64(2)), (Self.mukoujima, UInt64(4)),
        (Self.senjuShinbashiFromGotanda, UInt64(1)), (Self.senjuShinbashiFromGotanda, UInt64(2)),
      ]
    )
    func parallelEgressCompletes(site: Site, seed: UInt64) async throws {
      let gate = try site.gate()
      let run = try await gate.run(legs: gate.plannedLegs(), seed: seed, noise: .urban)
      let summary = gateLine(file: site.name, seed: seed, run: run, label: "ROUTE-END-URBAN")
      print(summary)
      #expect(run.reachedCompletion, "\(summary)")
      #expect(!run.completedEarly(), "\(summary)")
    }

    /// Driving on past each of those exits never completes the drive.
    @Test(
      "missing an exit beside the road it leaves never completes",
      arguments: [
        Self.shintoshin, Self.senjuShinbashi, Self.eifuku, Self.mukoujima,
        Self.senjuShinbashiFromGotanda,
      ]
    )
    func parallelEgressMissedExitNeverCompletes(site: Site) async throws {
      let gate = try site.gate()
      let movementIndex = gate.finalDivergenceIndex
      let alternatives = gate.alternativeEdgeIDs(atMovementIndex: movementIndex)
      #expect(!alternatives.isEmpty)
      for alternative in alternatives {
        let run = try await gate.run(
          legs: gate.wrongBranchLegs(
            movementIndex: movementIndex, alternativeEdgeID: alternative, branchMeters: 1_500
          ),
          seed: 1,
          noise: .urban
        )
        let summary = gateLine(file: site.name, seed: 1, run: run, label: "MISSED-EXIT-URBAN")
        print(summary)
        #expect(!run.reachedCompletion, "\(summary)")
      }
    }

    /// Past the exit at Senju-Shinbashi the street runs beside C2, and fixes
    /// on it read as C2: the session goes into recovery although the car took
    /// the exit. Near the exit it reports that it cannot yet tell, then
    /// completes; the drive never shows as interrupted.
    @Test("off the plan beside the exit it took, the drive is confirming the exit, then completes")
    func takenExitBesideTheRoadItLeavesIsConfirmed() async throws {
      let gate = try Self.senjuShinbashi.gate()
      let run = try await gate.run(legs: gate.plannedLegs(), seed: 1, noise: .urban)
      let summary = gateLine(file: Self.senjuShinbashi.name, seed: 1, run: run, label: "ROUTE-END-URBAN")
      print(summary)
      let recovery = run.records.filter { $0.phase == .routeRecovery }
      #expect(!recovery.isEmpty, "\(summary)")
      #expect(recovery.allSatisfy { $0.isConfirmingPlannedExit }, "\(summary)")
      #expect(run.reachedCompletion, "\(summary)")
    }

    /// Missing that exit and driving on along C2: the same recovery starts,
    /// confirming the exit while the car is near it, and stands once the car
    /// is past. Recovery comes at the second it did before the confirming
    /// state existed, so no notice moves.
    @Test("missing the exit beside the road it leaves is confirming, then interrupted")
    func missedExitBesideTheRoadItLeavesIsInterrupted() async throws {
      let gate = try Self.senjuShinbashi.gate()
      let movementIndex = gate.finalDivergenceIndex
      let alternative = try #require(gate.alternativeEdgeIDs(atMovementIndex: movementIndex).first)
      let run = try await gate.run(
        legs: gate.wrongBranchLegs(
          movementIndex: movementIndex, alternativeEdgeID: alternative, branchMeters: 1_500
        ),
        seed: 1,
        noise: .urban
      )
      let summary = gateLine(file: Self.senjuShinbashi.name, seed: 1, run: run, label: "MISSED-EXIT-URBAN")
      print(summary)
      let recovery = run.records.filter { $0.phase == .routeRecovery }
      let firstInterrupted = recovery.first { !$0.isConfirmingPlannedExit }
      #expect(recovery.first?.isConfirmingPlannedExit == true, "\(summary)")
      #expect(firstInterrupted != nil, "\(summary)")
      #expect(recovery.first?.second == Self.senjuShinbashiMissedRecoverySecond, "\(summary)")
      #expect(!run.records.contains { $0.phase == .surfaceEgress }, "\(summary)")
      #expect(!run.reachedCompletion, "\(summary)")
    }

    /// The second the missed-exit drive above enters recovery, measured on
    /// main before the confirming state; within its 1.5 km it reaches no
    /// other exit, so it never hands over.
    static let senjuShinbashiMissedRecoverySecond = 3188

    /// From Kiba to Takaracho a road the corridor stops following leads on,
    /// within 3 km, to the planned exit's own ramp: reaching it is leaving by
    /// the planned exit, so it does not compete with it.
    @Test("an exit a road beyond the corridor also leads to still completes")
    func exitReachedBeyondTheCorridorCompletes() async throws {
      let gate = try Self.takaracho.gate()
      let run = try await gate.run(legs: gate.plannedLegs(), seed: 9, noise: .underReported)
      let summary = gateLine(file: Self.takaracho.name, seed: 9, run: run, label: "ROUTE-END-UNDER2X")
      print(summary)
      #expect(run.reachedCompletion, "\(summary)")
    }

    static let takaracho = Site(
      name: "c1-outer kiba-takaracho", circuit: .c1Outer,
      entry: "shuto.ic.9.kiba", exit: "shuto.ic.c1.takaracho"
    )

    struct Site: Sendable, CustomTestStringConvertible {
      let name: String
      let circuit: ShutoCircuitDefinition
      let entry: String
      let exit: String
      var testDescription: String { name }

      func gate() throws -> LiveNavigationReplayGate {
        let database = try replayGateDatabase()
        let route = try ShutoRoutePlanner(database: database).planCircuit(
          circuit: circuit, entryFacilityID: entry, exitFacilityID: exit, laps: 1
        )
        let release = try ShutoCircuitProductReleaseBuilder.buildPlannedRouteRelease(
          context: try ShutoPlannedRouteRuntimeCompiler.NetworkContext(database: database),
          route: route
        )
        return LiveNavigationReplayGate(release: release, database: database)
      }
    }

    /// Saitama Shintoshin Route to Shintoshin, whose exit leaves by two ramps.
    static let shintoshin = Site(
      name: "c2 saitamaminuma-shintoshin", circuit: .c2InnerWithBayshore,
      entry: "shuto.ic.s2.saitamaminuma", exit: "shuto.ic.s2.shintoshin"
    )
    /// C2 at Senju-Shinbashi: the street runs beside C2.
    static let senjuShinbashi = Site(
      name: "c2 kahei-senjushinbashi", circuit: .c2InnerWithBayshore,
      entry: "shuto.ic.6-misato.kahei", exit: "shuto.ic.c2.senjushinbashi"
    )
    /// The same exit from C2 Gotanda: this corridor stops following C2
    /// 328 m past the exit, nearer the street than the exit is, but the
    /// network carries C2 on from there, so it is no way off the expressway.
    static let senjuShinbashiFromGotanda = Site(
      name: "c1-outer gotanda-senjushinbashi", circuit: .c1Outer,
      entry: "shuto.ic.c2.gotanda", exit: "shuto.ic.c2.senjushinbashi"
    )
    /// Route 4 at Eifuku: the street runs under Route 4.
    static let eifuku = Site(
      name: "c1-inner takaido-eifuku", circuit: .c1Inner,
      entry: "shuto.ic.4.takaido", exit: "shuto.ic.4.eifuku"
    )
    /// Route 6 at Mukojima: the street runs beside Route 6.
    static let mukoujima = Site(
      name: "c1-inner tsutsumidori-mukoujima", circuit: .c1Inner,
      entry: "shuto.ic.6-mukojima.tsutsumidori", exit: "shuto.ic.6-mukojima.mukoujima"
    )

    private static func noise(_ label: String) -> ReplayGateNoiseModel {
      switch label {
      case "MULTIPATH": return .multipath
      case "UNDER2X": return .underReported
      default: return .urban
      }
    }
  }
#endif
