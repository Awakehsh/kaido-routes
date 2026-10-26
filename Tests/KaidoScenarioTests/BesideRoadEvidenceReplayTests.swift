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

    /// Ariake JCT: Route 11 leaves the Bayshore stacked above it, 1-9 m off,
    /// for 370 m, and coarse fixes follow. No fix on it was evidence before
    /// the car was past the corridor's end, and beyond it only a run already
    /// under way counted: the drive never saw the car leave. The car the
    /// matcher last placed on Route 11, now 100 m from every road of the plan
    /// it can be on, has left along it.
    @Test("a branch stacked on the plan is seen once its fixes leave the corridor")
    func stackedBranchPastTheCorridor() async throws {
      let gate = try replayGate("scenic-harumi-daikoku-pa-product-release.json")
      let alternative = "osm.23169048.0.forward"
      #expect(gate.alternativeEdgeIDs(atMovementIndex: 39).contains(alternative))
      let run = try await gate.run(
        legs: gate.wrongBranchLegs(movementIndex: 39, alternativeEdgeID: alternative),
        seed: 39,
        noise: .underReported
      )
      let summary = gateLine(file: "scenic ariake", seed: 39, run: run, label: "ROUTE11-UNDER2X")
      print(summary)
      let left = try #require(run.records.first { $0.truth.offPlanDistanceMeters != nil })
      let seen = try #require(
        run.records.first {
          $0.truth.offPlanDistanceMeters != nil
            && ($0.phase == .routeRecovery || $0.phase == .surfaceEgress)
        },
        "\(summary)"
      )
      #expect(seen.second - left.second <= 45, "\(summary)")
    }

    /// A receiver that reports half its error leaves the corridor on the plan
    /// as well: a fix outside three times its reported accuracy matches no
    /// road, just after another was scattered onto a road beside the plan.
    /// Clear of the plan by that much, such a fix raised 6 s of recovery
    /// here; 100 m from every road of the plan, none does.
    @Test("a LOST fix scattered off the plan does not start a deviation")
    func lostFixBesideThePlan() async throws {
      let gate = try Self.gate(.c1Outer, "shuto.ic.c1.kyoubashi", "shuto.ic.c1.ginza")
      let run = try await gate.run(legs: gate.plannedLegs(), seed: 1, noise: .underReported)
      let summary = gateLine(file: "kyoubashi ginza", seed: 1, run: run, label: "LOST-SCATTER-UNDER2X")
      print(summary)
      #expect(run.reachedCompletion, "\(summary)")
      #expect(run.falseRouteRecoveryCount == 0, "\(summary)")
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
