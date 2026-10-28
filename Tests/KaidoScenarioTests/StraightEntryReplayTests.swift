#if canImport(CoreLocation)
  import Foundation
  import KaidoDomain
  import KaidoNavigation
  import KaidoRouting
  import Testing

  /// Entrances whose route runs straight on from the ramp: entry waits for
  /// the route to leave that straight line, and a decision can come first.
  /// Its cue is shown, not spoken, until entry is confirmed: a car on a
  /// street along the same line looks the same and must hear nothing.
  @Suite("1 Hz straight entries")
  struct StraightEntryReplayTests {
    /// From Toyosu the route stays within 14 m of the straight line for
    /// 1.1 km, past the Shinonome JCT fork at the sixth occurrence.
    @Test("the first fork past a straight entry is shown before the car reaches it", arguments: Array(UInt64(1)...3))
    func firstForkIsShown(seed: UInt64) async throws {
      let gate = try Self.toyosu.gate()
      let movementID = gate.release.navigation.bundle.routePlan.occurrences[5].id
      let run = try await gate.run(legs: gate.plannedLegs(), seed: seed, noise: .urban)
      let summary = gateLine(file: Self.toyosu.name, seed: seed, run: run, label: "STRAIGHT-ENTRY-URBAN")
      print(summary)
      let shown = run.records.first { $0.entryStretchMovementOccurrenceID == movementID }
      let reached = run.records.first {
        if case .occurrence(let index) = $0.truth.kind { return index >= 5 }
        return false
      }
      #expect(shown != nil, "\(summary)")
      #expect((shown?.second ?? .max) < (reached?.second ?? .min), "\(summary)")
      #expect(run.reachedCompletion, "\(summary)")
    }

    /// Driving on past the ramp along the straight line, at every noise
    /// profile: nothing is spoken before entry is confirmed. (Under-reported
    /// fixes at Toyosu seed 10 confirm entry on that line, as they do without
    /// the shown cue; the strict-route cue that follows is entry's own.)
    @Test(
      "a car that drove past the ramp hears no cue before entry is confirmed",
      arguments: [Self.toyosu, Self.hatagaya]
    )
    func passedRampHearsNothing(site: Site) async throws {
      let gate = try site.gate()
      for noise in [ReplayGateNoiseModel.urban, .multipath, .underReported] {
        for seed in UInt64(1)...40 {
          let run = try await gate.run(legs: gate.passedRampLegs(meters: 1_500), seed: seed, noise: noise)
          let entry = run.entryRecord?.second ?? .max
          #expect(
            run.records.allSatisfy { $0.emittedMovementOccurrenceIDs.isEmpty || $0.second >= entry },
            "\(site.name) seed \(seed)"
          )
        }
      }
    }

    /// Only an entrance whose first decision comes before entry can be
    /// confirmed carries an entrance announcement, and from Toyosu it is the
    /// Shinonome JCT fork.
    @Test("the entrance announcement names the decision reached before entry")
    func entranceAnnouncementScope() async throws {
      let toyosu = try Self.toyosu.gate()
      let announced = try Self.announcement(toyosu)
      #expect(announced?.frameTemplate.decisionPointNameJapanese == "東雲JCT")
      #expect(announced?.anchor.anchorID == "COMMIT")
      for site in [Self.nishikanda, Self.daiba] {
        #expect(try Self.announcement(try site.gate()) == nil, "\(site.name)")
      }
    }

    /// From Kukounishi the plan's first fork comes just as the route head
    /// clears the straight line, so the ordered fixes before it have not yet
    /// moved the odds. A car that takes the other road there runs beside the
    /// head and is held LOW on it: it is entered, then seen leaving, instead
    /// of never told.
    @Test("a car that leaves at the first fork past a straight entry is entered, then seen leaving")
    func leavesAtTheFirstFork() async throws {
      let gate = try Self.kukounishi.gate()
      let alternative = "osm.561915732.0.forward"
      let run = try await gate.run(
        legs: gate.wrongBranchLegs(movementIndex: 7, alternativeEdgeID: alternative),
        seed: 12,
        noise: .urban
      )
      let summary = branchLine(
        file: Self.kukounishi.name, movementIndex: 7, alternative: alternative, seed: 12, run: run
      )
      print("FIRST-FORK " + summary)
      #expect(run.entryRecord != nil, "\(summary)")
      #expect(run.deviationDetectedAfterOffPlanMeters != nil, "\(summary)")
      #expect(!run.reachedCompletion, "\(summary)")
    }

    private static func announcement(
      _ gate: LiveNavigationReplayGate
    ) throws -> ReleasedGuidanceDefinition? {
      let runtime = try KaidoProductNavigationRuntime(
        release: gate.release,
        journeyPlan: JourneyPlanCompiler.expresswayOnly(release: gate.release),
        expresswayRoads: []
      )
      return try ShutoLiveDriveSession(runtime: runtime).entranceAnnouncementGuidance
    }

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

    static let toyosu = Site(
      name: "c1-inner toyosu-shiodome", circuit: .c1Inner,
      entry: "shuto.ic.10.toyosu", exit: "shuto.ic.c1.shiodome"
    )
    static let nishikanda = Site(
      name: "c1-inner nishikanda-kasumigaseki", circuit: .c1Inner,
      entry: "shuto.ic.5.nishikanda", exit: "shuto.ic.c1.kasumigaseki"
    )
    static let daiba = Site(
      name: "c1-inner daiba-shiodome", circuit: .c1Inner,
      entry: "shuto.ic.11.daiba", exit: "shuto.ic.c1.shiodome"
    )
    static let kukounishi = Site(
      name: "c2 kukounishi-toyosu", circuit: .c2InnerWithBayshore,
      entry: "shuto.ic.1-haneda.kukounishi", exit: "shuto.ic.10.toyosu"
    )
    static let hatagaya = Site(
      name: "c2 hatagaya-tomigaya", circuit: .c2InnerWithBayshore,
      entry: "shuto.ic.4.hatagaya", exit: "shuto.ic.c2.tomigaya"
    )
  }
#endif
