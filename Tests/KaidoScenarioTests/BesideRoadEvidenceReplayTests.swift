#if canImport(CoreLocation)
  import Foundation
  import KaidoNavigation
  import KaidoRouting
  import Testing

  /// Junction links and mainlines run a few metres beside the plan for
  /// hundreds of metres. A receiver that reports half its error scatters
  /// fixes onto them as readily as onto the plan, so off-plan evidence needs
  /// the fix nearer the other road than the plan, and a road the car may
  /// have taken stays in the evidence's reach until two plan matches in a
  /// row leave it. Admission still leaves it behind on one.
  @Suite("1 Hz roads beside the plan")
  struct BesideRoadEvidenceReplayTests {
    /// Wangan westbound through Ariake, Tatsumi and Tokai JCTs: main raised
    /// 71 s of recovery here from fixes scattered onto the link lanes.
    @Test("scatter onto a junction link beside the plan raises no recovery")
    func scatterBesideThePlan() async throws {
      let gate = try replayGate("wangan-westbound-chidoricho-daikoku-pa-product-release.json")
      let run = try await gate.run(legs: gate.plannedLegs(), seed: 22, noise: .underReported)
      let summary = gateLine(file: "wangan westbound", seed: 22, run: run, label: "BESIDE-UNDER2X")
      print(summary)
      #expect(run.reachedCompletion, "\(summary)")
      #expect(run.falseRouteRecoveryCount == 0, "\(summary)")
    }

    /// Nishi-Shinjuku JCT: the Route 4 link runs 4-11 m from C2 for 880 m.
    /// One plan match on the far side used to leave the link behind while
    /// the car was on it, and the drive never said it had left.
    @Test("taking the Route 4 link at Nishi-Shinjuku is seen")
    func nishiShinjukuLink() async throws {
      let gate = try replayGate("c2-inner-oujiminami-itabashihoncho-product-release.json")
      let run = try await gate.run(
        legs: gate.wrongBranchLegs(
          movementIndex: 234, alternativeEdgeID: "osm.28127106.0.forward"
        ),
        seed: 23,
        noise: .underReported
      )
      let summary = gateLine(file: "c2 nishi-shinjuku", seed: 23, run: run, label: "ROUTE4-UNDER2X")
      print(summary)
      #expect(!run.reachedCompletion, "\(summary)")
      #expect(run.deviationDetectedAfterOffPlanMeters != nil, "\(summary)")
    }

    /// Hakozaki's approach has junction links on every side. Holding them as
    /// rivals at the entry gate kept this drive from ever being admitted.
    @Test("a missed exit after Hakozaki's entry is still seen")
    func hakozakiEntry() async throws {
      let gate = try Self.gate(.c1Inner, "shuto.ic.6-mukojima.hakozaki", "shuto.ic.c1.kandabashi")
      let movementIndex = gate.finalDivergenceIndex
      let run = try await gate.run(
        legs: gate.wrongBranchLegs(
          movementIndex: movementIndex, alternativeEdgeID: "osm.44805845.38.forward",
          branchMeters: 1_500
        ),
        seed: 37,
        noise: .multipath
      )
      let summary = gateLine(file: "hakozaki kandabashi", seed: 37, run: run, label: "MISSED-EXIT-MULTIPATH")
      print(summary)
      #expect(!run.reachedCompletion, "\(summary)")
      #expect(run.deviationDetectedAfterOffPlanMeters != nil, "\(summary)")
    }

    /// Hamacho to Mukojima passes Hakozaki and Ryogoku JCTs. Holding their
    /// links as rivals for admission, not only for evidence, held this
    /// drive's progress for 80 s against 39 s.
    @Test("a road held for evidence does not hold admission")
    func admissionBesideJunctionLinks() async throws {
      let gate = try Self.gate(
        .c1Inner, "shuto.ic.6-mukojima.hamacho", "shuto.ic.6-mukojima.mukoujima"
      )
      let run = try await gate.run(legs: gate.plannedLegs(), seed: 30, noise: .urban)
      let summary = gateLine(file: "hamacho mukojima", seed: 30, run: run, label: "ADMISSION-URBAN")
      print(summary)
      #expect(run.reachedCompletion, "\(summary)")
      #expect(run.longestUnadmittedSeconds <= 45, "\(summary)")
    }

    /// Past the exit, Shikahamabashi's missed branch curves: fixes on it ran
    /// 27 deg off the chord of the segment nearest them, so the course check
    /// threw them away and saw the miss 33 s after it, against 14 s before
    /// the check. Judged along the road around the fix, it sees it at 14 s.
    @Test("a missed exit onto a curving branch is seen as early as before the course check")
    func missedExitOntoACurvingBranch() async throws {
      let gate = try Self.gate(.c1Outer, "shuto.ic.s1.shikahamabashi", "shuto.ic.c1.kandabashi")
      let run = try await gate.run(
        legs: gate.wrongBranchLegs(
          movementIndex: gate.finalDivergenceIndex,
          alternativeEdgeID: "osm.24039781.0.forward",
          branchMeters: 1_500
        ),
        seed: 16,
        noise: .underReported
      )
      let summary = gateLine(file: "shikahamabashi kandabashi", seed: 16, run: run, label: "CURVING-BRANCH-UNDER2X")
      print(summary)
      let left = try #require(run.records.first { $0.truth.offPlanDistanceMeters != nil })
      let seen = try #require(
        run.records.first { $0.truth.offPlanDistanceMeters != nil && $0.phase == .routeRecovery }
      )
      #expect(seen.second - left.second <= 19, "\(summary)")
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
  }
#endif
