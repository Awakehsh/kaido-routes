#if canImport(CoreLocation)
  import Foundation
  import KaidoNavigation
  import KaidoRouting
  import Testing

  /// Drives that go out along a radial route to a loop and come back the same
  /// way. On stacked or adjacent carriageways the drive's other pass of the
  /// road runs a few metres from the car in the opposite direction; the
  /// matcher counted it as a rival and held progress for minutes, so turn
  /// cues on the way back came late or never. On the C2 Ohashi spiral the
  /// plan's own later pass lies beside the car; a match there once committed
  /// progress 400 m ahead of it.
  @Suite("1 Hz drives out along a radial route and back")
  struct RadialReturnReplayTests {
    @Test(
      "the drive back keeps admitted progress and cues every turn on time",
      arguments: [
        // Kawaguchi Route from Shingou, C1 inner, back to Angyou: progress
        // held 200 s on C2 and Route 5 between Itabashi/Kumanocho and Kohoku.
        (Self.c1InnerFromShingou, "URBAN", UInt64(1)),
        (Self.c1InnerFromShingou, "MULTIPATH", 11),
        // Route 7 from Komatsugawa, C2 inner and the Bayshore, back to
        // Ichinoe: progress held 245 s on the C2 deck past Itabashi.
        (Self.c2FromKomatsugawa, "URBAN", 1),
        // Route 2 from Togoshi, C2 inner and the Bayshore, back to Ebara:
        // progress held 130 s around Tanimachi and Ichinohashi.
        (Self.c2FromTogoshi, "URBAN", 1),
      ]
    )
    func drivesBack(fixture: Fixture, noise: String, seed: UInt64) async throws {
      let gate = try fixture.gate()
      let run = try await gate.run(legs: gate.plannedLegs(), seed: seed, noise: Self.noise(noise))
      let summary = gateLine(file: fixture.name, seed: seed, run: run, label: "RADIAL-\(noise)")
      print(summary)
      #expect(
        run.longestUnadmittedSeconds <= LiveNavigationReplayGateTests.maximumUnadmittedSeconds,
        "\(summary)"
      )
      #expect(run.lateOrMissingCueMovementIndexes().isEmpty, "\(summary)")
      #expect(run.wrongCommitCount() == 0, "\(summary)")
      #expect(run.reachedCompletion, "\(summary)")
    }

    /// Route 4 from Shinjuku, C2 inner and the Bayshore, back over the Ohashi
    /// spiral to Yoyogi: the matcher jumped to the spiral's later pass and,
    /// once nothing else held the match below MEDIUM, committed it.
    @Test("the spiral's later pass beside the car never takes progress")
    func spiralLaterPassNeverCommits() async throws {
      let fixture = Self.c2FromShinjuku
      let gate = try fixture.gate()
      let run = try await gate.run(legs: gate.plannedLegs(), seed: 1, noise: .urban)
      let summary = gateLine(file: fixture.name, seed: 1, run: run, label: "RADIAL-URBAN")
      print(summary)
      #expect(run.wrongCommitCount() == 0, "\(summary)")
      #expect(run.reachedCompletion, "\(summary)")
    }

    struct Fixture: Sendable, CustomTestStringConvertible {
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

    static let c1InnerFromShingou = Fixture(
      name: "c1-inner shingou-angyou", circuit: .c1Inner,
      entry: "shuto.ic.s1.shingou", exit: "shuto.ic.s1.angyou"
    )
    static let c2FromKomatsugawa = Fixture(
      name: "c2 komatsugawa-ichinoe", circuit: .c2InnerWithBayshore,
      entry: "shuto.ic.7.komatsugawa", exit: "shuto.ic.7.ichinoe"
    )
    static let c2FromTogoshi = Fixture(
      name: "c2 togoshi-ebara", circuit: .c2InnerWithBayshore,
      entry: "shuto.ic.2.togoshi", exit: "shuto.ic.2.ebara"
    )
    static let c2FromShinjuku = Fixture(
      name: "c2 shinjuku-yoyogi", circuit: .c2InnerWithBayshore,
      entry: "shuto.ic.4.shinjuku", exit: "shuto.ic.4.yoyogi"
    )

    private static func noise(_ label: String) -> ReplayGateNoiseModel {
      switch label {
      case "MULTIPATH": return .multipath
      case "UNDER2X": return .underReported
      default: return .urban
      }
    }
  }
#endif
