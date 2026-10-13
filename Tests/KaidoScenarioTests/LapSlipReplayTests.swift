#if canImport(CoreLocation)
  import Foundation
  import KaidoDomain
  import KaidoNavigation
  import KaidoRouting
  import Testing

  /// A loop drives the same roads every lap, so every pass of a road is a
  /// matcher candidate. Under accuracy reported at half the real error the
  /// matcher once slipped onto the previous lap's pass and the session never
  /// moved it back: admitted progress stood still for up to 19 minutes.
  @Suite("1 Hz repeated-road replay")
  struct LapSlipReplayTests {
    @Test(
      "a loop drive under under-reported accuracy never loses its lap",
      arguments: zip(
        ["lap-one-stop", "lap-one-stop", "daikoku-yokohama-wangankanpachi-daikoku-pa-product-release.json"],
        [UInt64(3), 5, 14]
      )
    )
    func loopKeepsItsLap(fixture: String, seed: UInt64) async throws {
      let gate =
        fixture == "lap-one-stop"
        ? try Self.daikokuLoopWithLapOneStop()
        : try replayGate(fixture)
      let run = try await gate.run(legs: gate.plannedLegs(), seed: seed, noise: .underReported)
      let summary = gateLine(file: fixture, seed: seed, run: run, label: "LAP-SLIP")
      print(summary)
      #expect(run.reachedCompletion, "\(summary)")
      #expect(!run.completedEarly(), "\(summary)")
      #expect(run.wrongCommitCount() == 0, "\(summary)")
      #expect(
        run.longestUnadmittedSeconds <= LiveNavigationReplayGateTests.maximumUnadmittedSeconds,
        "\(summary)"
      )
    }

    /// Three laps of the Daikoku loop from Wangan-Kanpachi to Haneda with the
    /// Daikoku PA stop, which the planner places in the first lap.
    static func daikokuLoopWithLapOneStop() throws -> LiveNavigationReplayGate {
      let database = try replayGateDatabase()
      let planner = try ShutoRoutePlanner(database: database)
      let base = try planner.planCircuit(
        circuit: .daikokuYokohamaLoop,
        entryFacilityID: "shuto.ic.b.wangankanpachi",
        exitFacilityID: "shuto.ic.1-haneda.haneda",
        laps: 3
      )
      let route = try planner.addingParkingStops(["shuto.pa.daikoku"], to: base)
      let release = try ShutoCircuitProductReleaseBuilder.buildPlannedRouteRelease(
        context: try ShutoPlannedRouteRuntimeCompiler.NetworkContext(database: database),
        route: route
      )
      return LiveNavigationReplayGate(release: release, database: database)
    }
  }
#endif
