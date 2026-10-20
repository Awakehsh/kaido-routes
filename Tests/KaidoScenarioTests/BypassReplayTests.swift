#if canImport(CoreLocation)
  import Foundation
  import KaidoNavigation
  import KaidoRouting
  import Testing

  /// A way off the plan that comes back to it after as long a drive as the
  /// plan takes is no rival to the car's place beside it; a detour that
  /// comes back further on is.
  @Suite("1 Hz bypasses and detours beside the plan")
  struct BypassReplayTests {
    /// Route 6 out through Hakozaki JCT: the rotary link beside the
    /// carriageway rejoins it within a metre of the carriageway's length,
    /// and no longer holds the car's progress beside it.
    @Test("a bypass beside the plan no longer holds progress")
    func bypassDoesNotHoldProgress() async throws {
      let gate = try Self.gate(.c1Inner, "shuto.ic.7.ichinoe", "shuto.ic.7.komatsugawa")
      let run = try await gate.run(legs: gate.plannedLegs(), seed: 1, noise: .urban)
      let summary = gateLine(file: "c1-inner ichinoe-komatsugawa", seed: 1, run: run, label: "BYPASS-URBAN")
      print(summary)
      #expect(run.longestUnadmittedSeconds <= 53, "\(summary)")
      #expect(run.reachedCompletion, "\(summary)")
    }

    /// Route 4 inbound at Nishi-Shinjuku JCT: the branch the plan does not
    /// take comes back to the plan, but 139 m longer than the plan between.
    /// A car that takes it has left the plan, and the session says so.
    @Test("a detour that rejoins further on is still a wrong branch")
    func detourIsAWrongBranch() async throws {
      let gate = try Self.gate(.c2InnerWithBayshore, "shuto.ic.4.hatagaya", "shuto.ic.c2.tomigaya")
      let movementIndex = 125
      #expect(gate.alternativeEdgeIDs(atMovementIndex: movementIndex).contains("osm.331922702.0.forward"))
      let run = try await gate.run(
        legs: gate.wrongBranchLegs(
          movementIndex: movementIndex, alternativeEdgeID: "osm.331922702.0.forward", branchMeters: 400
        ),
        seed: 1,
        noise: .urban
      )
      let summary = gateLine(file: "c2 hatagaya-tomigaya", seed: 1, run: run, label: "DETOUR-URBAN")
      print(summary)
      #expect(run.records.contains { $0.phase == .routeRecovery }, "\(summary)")
      #expect(run.offPlanCommitCount(movementIndex: movementIndex) == 0, "\(summary)")
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
