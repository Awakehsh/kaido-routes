#if canImport(CoreLocation)
  import Foundation
  import KaidoDomain
  import KaidoNavigation
  import KaidoRouting
  import Testing

  /// At 西新宿JCT the branch the plan does not take runs beside C2 for
  /// several hundred metres. Under accuracy reported at half its real error,
  /// a car on that branch was matched off the plan, then onto the plan's own
  /// pass beside it: progress ran on along C2, and the drive either rejoined
  /// the plan it had left or never noticed it had left.
  @Suite("1 Hz wrong branch on a later lap of a loop")
  struct LaterLapBranchReplayTests {
    @Test(
      "a later lap's wrong branch at 西新宿 never advances the plan",
      arguments: [(2, 2, UInt64(2)), (2, 2, 40), (3, 3, 2), (3, 3, 10)]
    )
    func laterLapBranchNeverAdvances(laps: Int, lap: Int, seed: UInt64) async throws {
      let (gate, lapRange) = try Self.c2Loop(laps: laps, lap: lap)
      let movementIndex = try #require(try Self.nishiShinjukuMovement(gate: gate, in: lapRange))
      for alternative in gate.alternativeEdgeIDs(atMovementIndex: movementIndex) {
        let run = try await gate.run(
          legs: gate.wrongBranchLegs(movementIndex: movementIndex, alternativeEdgeID: alternative),
          seed: seed,
          noise: .underReported
        )
        let summary =
          branchLine(
            file: "c2-loop-\(laps)",
            movementIndex: movementIndex,
            alternative: alternative,
            seed: seed,
            run: run
          ) + " lap=\(lap)"
        print("LATER-LAP " + summary)
        #expect(run.offPlanCommitCount(movementIndex: movementIndex) == 0, "\(summary)")
        #expect(run.records.last?.phase == .routeRecovery, "\(summary)")
      }
    }

    /// The bundled C2 release's reviewed junction, found again in the lap.
    private static func nishiShinjukuMovement(
      gate: LiveNavigationReplayGate,
      in lapRange: Range<Int>
    ) throws -> Int? {
      let bundled = try replayGate("c2-inner-oujiminami-itabashihoncho-product-release.json")
      let incoming = bundled.routeEdgeIDs[233]
      let planned = bundled.routeEdgeIDs[234]
      let ids = gate.routeEdgeIDs
      return lapRange.first { $0 > 0 && ids[$0 - 1] == incoming && ids[$0] == planned }
    }

    private static func c2Loop(laps: Int, lap: Int) throws -> (LiveNavigationReplayGate, Range<Int>) {
      let database = try replayGateDatabase()
      let planner = try ShutoRoutePlanner(database: database)
      let route = try planner.planCircuit(
        circuit: .c2InnerWithBayshore,
        entryFacilityID: "shuto.ic.c2.oujiminami",
        exitFacilityID: "shuto.ic.5.itabashihoncho",
        laps: laps
      )
      let release = try ShutoCircuitProductReleaseBuilder.buildPlannedRouteRelease(
        context: try ShutoPlannedRouteRuntimeCompiler.NetworkContext(database: database),
        route: route
      )
      let boundaries = route.lapBoundaryOccurrenceIndices
      let lapRange = boundaries[lap - 1]..<boundaries[lap]
      return (LiveNavigationReplayGate(release: release, database: database), lapRange)
    }
  }
#endif
