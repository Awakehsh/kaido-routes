#if canImport(CoreLocation)
  import Foundation
  import KaidoNavigation
  import Testing

  /// C1 inner Shibakoen→Shiodome and C2 inner Oujiminami→Itabashihoncho
  /// drive the road beside their entrance again near their end. These drives
  /// once matched the approach onto that later pass: the route head was never
  /// confirmed, or was confirmed 49 minutes late with the final junction cue
  /// of the first pass, and a driver's "already on the expressway" joined the
  /// plan 55 km ahead of the car.
  @Suite("1 Hz entry on a road the plan drives twice")
  struct EntryPassReplayTests {
    /// The longest unadmitted stretch the gate allows on the expressway.
    static let maximumEntryLatencySeconds = 75
    /// Far less than the distance between two passes of one road on a loop.
    static let passToleranceMeters = 1_500.0

    @Test(
      "the entrance is confirmed on the pass the car is on",
      arguments: [
        ("c1-inner-shibakoen-to-shiodome-product-release.json", "MULTIPATH", UInt64(19)),
        ("c1-inner-shibakoen-to-shiodome-product-release.json", "UNDER2X", 4),
        ("c2-inner-oujiminami-itabashihoncho-product-release.json", "UNDER2X", 1),
        ("c2-inner-oujiminami-itabashihoncho-product-release.json", "UNDER2X", 10),
        ("c2-inner-oujiminami-itabashihoncho-product-release.json", "UNDER2X", 11),
        ("c2-inner-oujiminami-itabashihoncho-product-release.json", "UNDER2X", 13),
        ("c2-inner-oujiminami-itabashihoncho-product-release.json", "UNDER2X", 18),
        ("c2-inner-oujiminami-itabashihoncho-product-release.json", "UNDER2X", 20),
        ("c2-inner-oujiminami-itabashihoncho-product-release.json", "UNDER2X", 21),
      ]
    )
    func entersOnThePassTheCarIsOn(file: String, noise: String, seed: UInt64) async throws {
      let gate = try replayGate(file)
      let run = try await gate.run(
        legs: gate.plannedLegs(),
        seed: seed,
        noise: Self.noise(noise)
      )
      let summary = Self.line(gateLine(file: file, seed: seed, run: run, label: noise), run)
      print(summary)
      #expect(
        (run.entryLatencySeconds ?? .max) <= Self.maximumEntryLatencySeconds,
        "\(summary)"
      )
      #expect(
        abs(run.entryCommitOffsetMeters ?? .infinity) <= Self.passToleranceMeters,
        "\(summary)"
      )
      #expect(run.misplacedCueCount() == 0, "\(summary)")
    }

    @Test(
      "a driver's join lands on the pass the car is on",
      arguments: [
        ("c1-inner-shibakoen-to-shiodome-product-release.json", "MULTIPATH", UInt64(19)),
        ("c2-inner-oujiminami-itabashihoncho-product-release.json", "UNDER2X", 10),
        ("daikoku-yokohama-wangankanpachi-daikoku-pa-product-release.json", "URBAN", 1),
      ]
    )
    func joinsOnThePassTheCarIsOn(file: String, noise: String, seed: UInt64) async throws {
      let gate = try replayGate(file)
      let run = try await gate.run(
        legs: gate.plannedLegs(),
        seed: seed,
        noise: Self.noise(noise),
        driverJoin: ReplayGateDriverJoin(declaredAtSecond: 140)
      )
      let summary = Self.line(gateLine(file: file, seed: seed, run: run, label: "JOIN-\(noise)"), run)
      print(summary)
      let joined = try #require(run.entryRecord, "\(summary)")
      #expect(joined.second - 140 <= 45, "\(summary)")
      #expect(
        abs(run.entryCommitOffsetMeters ?? .infinity) <= Self.passToleranceMeters,
        "\(summary)"
      )
      #expect(run.wrongCommitCount() == 0, "\(summary)")
      #expect(run.behindCommitCount() == 0, "\(summary)")
      #expect(run.misplacedCueCount() == 0, "\(summary)")
    }

    /// The reach rule decides between passes: a later pass is moved back to
    /// the earliest only once the car can have driven there.
    @Test("an earlier pass is chosen only once the car can have reached it")
    func earlierPassNeedsReach() throws {
      let gate = try replayGate("c2-inner-oujiminami-itabashihoncho-product-release.json")
      let corridor = gate.release.navigation.bundle.matcherCorridor
      let occurrences = corridor.occurrences.sorted { $0.index < $1.index }
      let passes = Dictionary(grouping: occurrences, by: \.directedEdgeID)
        .values.filter { $0.count == 2 }
        .min { $0[0].index < $1[0].index }
      let pair = try #require(passes)
      let (earlier, later) = (pair[0], pair[1])
      let reach = RoutePassReach(corridor: corridor)
      let estimate = MatcherEstimate(
        observationID: nil,
        estimatedAtMilliseconds: 0,
        directedEdgeID: later.directedEdgeID,
        occurrenceID: later.id,
        candidateEdgeIDs: [later.directedEdgeID],
        confidence: .medium,
        distanceMeters: 1
      )
      let earlierStart = gate.routeStartDistances[earlier.index]
      let reachedAt = Int((earlierStart - 100) / 40 * 1_000) + 1
      #expect(earlierStart > 100)
      #expect(reach.earlierPass(of: estimate, elapsedMilliseconds: reachedAt - 1_000) == nil)
      #expect(reach.earlierPass(of: estimate, elapsedMilliseconds: reachedAt) == earlier.id)
      let onEarlier = MatcherEstimate(
        observationID: nil,
        estimatedAtMilliseconds: 0,
        directedEdgeID: earlier.directedEdgeID,
        occurrenceID: earlier.id,
        candidateEdgeIDs: [earlier.directedEdgeID],
        confidence: .medium,
        distanceMeters: 1
      )
      #expect(reach.earlierPass(of: onEarlier, elapsedMilliseconds: reachedAt) == nil)
    }

    private static func noise(_ label: String) -> ReplayGateNoiseModel {
      switch label {
      case "MULTIPATH": return .multipath
      case "UNDER2X": return .underReported
      default: return .urban
      }
    }

    private static func line(_ gateLine: String, _ run: ReplayGateRun) -> String {
      gateLine
        + " entryLatency=\(run.entryLatencySeconds.map(String.init) ?? "-")"
        + " entryOffset=\(run.entryCommitOffsetMeters.map { String(Int($0)) } ?? "-")"
        + " behindCommits=\(run.behindCommitCount())"
        + " misplacedCues=\(run.misplacedCueCount())"
    }
  }
#endif
