#if canImport(CoreLocation)
  import Foundation
  import KaidoDomain
  import KaidoNavigation
  import KaidoRouting
  import Testing

  /// Movements the car reaches too soon for their own cue. At Namamugi JCT
  /// (K5 inbound) the second fork follows the first by 250 m, inside its
  /// 300 m commit distance, and the two roads run side by side until it
  /// splits, so its cue never played; the first fork's cue now names it.
  /// Entering at Nishikanda, Takebashi JCT comes 200 m after the ramp and its
  /// cue was due only on the occurrence just before it.
  @Suite("1 Hz cues for movements reached too soon")
  struct ShortApproachCueReplayTests {
    @Test("the second Namamugi fork is announced with the first", arguments: Array(UInt64(1)...3))
    func namamugiForksAreAnnounced(seed: UInt64) async throws {
      let file = "daikoku-yokohama-wangankanpachi-daikoku-pa-product-release.json"
      let gate = try replayGate(file)
      let chained = gate.release.navigation.bundle.releasedGuidance.filter {
        $0.anchor.anchorID == "COMMIT"
          && $0.frameTemplate.decisionPointNameJapanese == "生麦JCT"
          && $0.frameTemplate.presentationSource.localizedContent[.japanese]?
            .spokenText.hasSuffix("。その先、羽田方面です") == true
      }
      #expect(chained.count == 1)
      let run = try await gate.run(legs: gate.plannedLegs(), seed: seed, noise: .urban)
      let summary = gateLine(file: file, seed: seed, run: run, label: "CHAINED-URBAN")
      print(summary)
      #expect(run.lateOrMissingCueMovementIndexes().isEmpty, "\(summary)")
    }

    @Test("a movement right after the entrance is cued from entry", arguments: Array(UInt64(1)...3))
    func firstMovementAfterEntryIsCued(seed: UInt64) async throws {
      let database = try replayGateDatabase()
      let route = try ShutoRoutePlanner(database: database).planCircuit(
        circuit: .c1Inner,
        entryFacilityID: "shuto.ic.5.nishikanda",
        exitFacilityID: "shuto.ic.c1.kasumigaseki",
        laps: 1
      )
      let release = try ShutoCircuitProductReleaseBuilder.buildPlannedRouteRelease(
        context: try ShutoPlannedRouteRuntimeCompiler.NetworkContext(database: database),
        route: route
      )
      let gate = LiveNavigationReplayGate(release: release, database: database)
      let run = try await gate.run(legs: gate.plannedLegs(), seed: seed, noise: .urban)
      let summary = gateLine(file: "c1-inner nishikanda-kasumigaseki", seed: seed, run: run, label: "ENTRY-URBAN")
      print(summary)
      #expect(run.lateOrMissingCueMovementIndexes().isEmpty, "\(summary)")
    }
  }
#endif
