#if canImport(CoreLocation)
  import Foundation
  import KaidoNavigation
  import KaidoRouting
  import Testing

  /// The corridor follows a branch only until it is clear of the plan. A car
  /// the matcher never placed on the branch, gone on past that point onto
  /// another expressway, matches no road at all; only its distance from the
  /// plan, beyond what its receiver errs, shows it left.
  @Suite("1 Hz departures past the corridor's end")
  struct CorridorEndDepartureReplayTests {
    /// On main this drive never said it had left. The corridor road nearest
    /// the car there is a released detour's, and the car is not on it.
    @Test("leaving onto another expressway is seen, with no rejoin offered")
    func departureOntoAnotherExpressway() async throws {
      let gate = try Self.gate(.c1Outer, "shuto.ic.5.hitotsubashi", "shuto.ic.5.nishikanda")
      let run = try await gate.run(
        legs: gate.wrongBranchLegs(movementIndex: 868, alternativeEdgeID: "osm.44804206.0.forward"),
        seed: 6,
        noise: .urban
      )
      let summary = branchLine(
        file: "c1 outer hitotsubashi", movementIndex: 868,
        alternative: "osm.44804206.0.forward", seed: 6, run: run
      )
      print("CORRIDOR-END " + summary)
      #expect(!run.reachedCompletion, "\(summary)")
      #expect(run.deviationDetectedAfterOffPlanMeters != nil, "\(summary)")
      #expect(run.records.contains { $0.recoveryStatus == .unavailable }, "\(summary)")
      #expect(!run.records.contains { $0.recoveryStatus == .active }, "\(summary)")
    }

    /// Past Daikoku PA's entry the car is soon beyond the corridor too. The
    /// road it took decides nothing there: missing the entry ends the drive.
    @Test("driving on past the destination PA beyond the corridor ends the drive")
    func pastTheDestinationParkingArea() async throws {
      let gate = try Self.gate(.daikokuYokohamaLoop, "shuto.ic.1-ueno.honcho", nil)
      let movementIndex = gate.finalDivergenceIndex
      let run = try await gate.run(
        legs: gate.wrongBranchLegs(
          movementIndex: movementIndex, alternativeEdgeID: "osm.32592487.0.forward",
          branchMeters: 1_500
        ),
        seed: 4,
        noise: .underReported
      )
      let summary = branchLine(
        file: "daikoku ueno-honcho", movementIndex: movementIndex,
        alternative: "osm.32592487.0.forward", seed: 4, run: run
      )
      print("CORRIDOR-END " + summary)
      #expect(run.records.last?.phaseTrigger == "DESTINATION_PARKING_AREA_NOT_ENTERED", "\(summary)")
    }

    private static func gate(
      _ circuit: ShutoCircuitDefinition, _ entry: String, _ exit: String?
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
