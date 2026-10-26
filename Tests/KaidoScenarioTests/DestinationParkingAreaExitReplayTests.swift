#if canImport(CoreLocation)
  import Foundation
  import KaidoDomain
  import KaidoNavigation
  import KaidoRouting
  import Testing

  /// A drive that ends in Daikoku PA forks from the PA's entry ramp onto a road
  /// that runs 2-13 m beside the ramp for 150 m, off Daikoku JCT. A car that
  /// drives past the PA leaves the expressway there; one that leaves earlier
  /// can still come back to it.
  @Suite("1 Hz exits around a destination PA")
  struct DestinationParkingAreaExitReplayTests {
    /// Fixes along the road past the PA matched the ramp beside it and held
    /// progress short of the fork; the drive handed over to surface guidance
    /// toward a PA the street cannot reach.
    @Test(
      "driving past the destination PA and off the expressway ends the drive there",
      arguments: [
        ("shuto.ic.k7-yokohama-kita.kishiyanamamugi", ShutoCircuitDefinition.daikokuYokohamaLoop, "UNDER2X", UInt64(6)),
        ("shuto.ic.b.chidoricho", .scenicGrandTour, "MULTIPATH", 36),
      ]
    )
    func pastTheDestinationPA(
      entry: String, circuit: ShutoCircuitDefinition, noise: String, seed: UInt64
    ) async throws {
      let gate = try Self.gate(circuit, entry)
      let run = try await gate.run(
        legs: gate.wrongBranchLegs(
          movementIndex: gate.finalDivergenceIndex,
          alternativeEdgeID: "osm.32592487.0.forward",
          branchMeters: 1_500
        ),
        seed: seed,
        noise: Self.noise(noise)
      )
      let summary = gateLine(file: entry, seed: seed, run: run, label: "PAST-PA-\(noise)")
      print(summary)
      #expect(run.records.last?.phaseTrigger == "DESTINATION_PARKING_AREA_NOT_ENTERED", "\(summary)")
    }

    /// Kishiyanamamugi's route leaves the expressway at movement 871, before
    /// its last choice of road at 932: the car can still reach Daikoku PA.
    @Test("an exit before the last choice of road short of the destination PA hands over")
    func exitBeforeTheLastChoice() async throws {
      let gate = try Self.gate(.daikokuYokohamaLoop, "shuto.ic.k7-yokohama-kita.kishiyanamamugi")
      let run = try await gate.run(
        legs: gate.wrongBranchLegs(movementIndex: 871, alternativeEdgeID: "osm.5365200.0.forward"),
        seed: 1,
        noise: .urban
      )
      let summary = gateLine(file: "kishiyanamamugi", seed: 1, run: run, label: "EXIT-BEFORE-LAST-CHOICE-URBAN")
      print(summary)
      #expect(run.records.last?.phase == .surfaceEgress, "\(summary)")
      #expect(run.records.last?.phaseTrigger == "UNPLANNED_EXIT", "\(summary)")
      #expect(!run.reachedCompletion, "\(summary)")
    }

    private static func gate(
      _ circuit: ShutoCircuitDefinition, _ entry: String
    ) throws -> LiveNavigationReplayGate {
      let database = try replayGateDatabase()
      let route = try ShutoRoutePlanner(database: database).planCircuit(
        circuit: circuit, entryFacilityID: entry, exitFacilityID: nil, laps: 1
      )
      let release = try ShutoCircuitProductReleaseBuilder.buildPlannedRouteRelease(
        context: try ShutoPlannedRouteRuntimeCompiler.NetworkContext(database: database),
        route: route
      )
      return LiveNavigationReplayGate(release: release, database: database)
    }

    private static func noise(_ name: String) -> ReplayGateNoiseModel {
      switch name {
      case "MULTIPATH": .multipath
      case "UNDER2X": .underReported
      default: .urban
      }
    }
  }
#endif
