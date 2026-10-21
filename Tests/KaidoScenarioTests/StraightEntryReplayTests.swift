#if canImport(CoreLocation)
  import Foundation
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
    static let hatagaya = Site(
      name: "c2 hatagaya-tomigaya", circuit: .c2InnerWithBayshore,
      entry: "shuto.ic.4.hatagaya", exit: "shuto.ic.c2.tomigaya"
    )
  }
#endif
