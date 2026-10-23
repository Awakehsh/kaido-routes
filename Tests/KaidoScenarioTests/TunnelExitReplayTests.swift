#if canImport(CoreLocation)
  import Foundation
  import KaidoNavigation
  import KaidoRouting
  import Testing

  /// Kasumigaseki, Nishi-Ikebukuro and Hatsudai-minami leave in tunnels. A car
  /// that drove on past them came out with reacquisition pending, which only
  /// the plan confirms, so the drive never said it had left; and the first
  /// fixes after a portal are the worst, so a drive that kept to the plan must
  /// not read them as leaving it.
  @Suite("1 Hz exits in tunnels")
  struct TunnelExitReplayTests {
    @Test(
      "driving on past an exit in a tunnel is seen, and taking it is not",
      arguments: [
        (ShutoCircuitDefinition.c1Inner, "shuto.ic.4.gaien", "shuto.ic.c1.kasumigaseki", UInt64(1)),
        (.c2InnerWithBayshore, "shuto.ic.5.itabashihoncho", "shuto.ic.c2.nishiikebukuro", 5),
        (.c1Inner, "shuto.ic.c2.tomigaya", "shuto.ic.c2.hatsudaiminami", 6),
      ]
    )
    func exitInATunnel(
      circuit: ShutoCircuitDefinition, entry: String, exit: String, seed: UInt64
    ) async throws {
      let gate = try Self.gate(circuit, entry, exit, laps: 1)
      let planned = try await gate.run(legs: gate.plannedLegs(), seed: seed, noise: .urban)
      let plannedSummary = gateLine(file: exit, seed: seed, run: planned, label: "ROUTE-END-URBAN")
      print(plannedSummary)
      #expect(planned.reachedCompletion, "\(plannedSummary)")
      #expect(planned.falseRouteRecoveryCount == 0, "\(plannedSummary)")
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
        let summary = gateLine(file: exit, seed: seed, run: run, label: "MISSED-EXIT-URBAN")
        print(summary)
        #expect(!run.reachedCompletion, "\(summary)")
        #expect(run.deviationDetectedAfterOffPlanMeters != nil, "\(summary)")
      }
    }

    /// A lap of C2 drives the whole Yamate Tunnel, past Ohashi, Nishi-Shinjuku
    /// and Kumanocho JCTs and the exits inside it, with junction branches
    /// beside the plan at every portal.
    @Test(
      "a lap through the Yamate Tunnel raises no recovery",
      arguments: [("URBAN", UInt64(1)), ("URBAN", 2), ("MULTIPATH", 1), ("MULTIPATH", 2)]
    )
    func yamateTunnelLap(noise: String, seed: UInt64) async throws {
      let gate = try Self.gate(
        .c2InnerWithBayshore, "shuto.ic.c2.oujiminami", "shuto.ic.5.itabashihoncho", laps: 1
      )
      // C2 through Nishi-Shinjuku JCT, inside the tunnel, either way.
      let throughNishiShinjuku: Set<String> = [
        "osm.190617333.53.forward", "osm.190617333.54.forward",
        "osm.863812380.3.forward", "osm.863812381.0.forward",
      ]
      #expect(gate.routeEdgeIDs.contains(where: throughNishiShinjuku.contains))
      let run = try await gate.run(
        legs: gate.plannedLegs(), seed: seed, noise: noise == "URBAN" ? .urban : .multipath
      )
      let summary = gateLine(file: "c2 lap", seed: seed, run: run, label: "C2-LAP-\(noise)")
      print(summary)
      #expect(run.reachedCompletion, "\(summary)")
      #expect(run.falseRouteRecoveryCount == 0, "\(summary)")
    }

    private static func gate(
      _ circuit: ShutoCircuitDefinition, _ entry: String, _ exit: String, laps: Int
    ) throws -> LiveNavigationReplayGate {
      let database = try replayGateDatabase()
      let route = try ShutoRoutePlanner(database: database).planCircuit(
        circuit: circuit, entryFacilityID: entry, exitFacilityID: exit, laps: laps
      )
      let release = try ShutoCircuitProductReleaseBuilder.buildPlannedRouteRelease(
        context: try ShutoPlannedRouteRuntimeCompiler.NetworkContext(database: database),
        route: route
      )
      return LiveNavigationReplayGate(release: release, database: database)
    }
  }
#endif
