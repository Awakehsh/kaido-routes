#if canImport(CoreLocation)
  import Foundation
  import KaidoDomain
  import KaidoNavigation
  import KaidoRouting
  import Testing

  /// The deterministic 1 Hz gate for every bundled foreground release. It
  /// drives the Core Location adapters, the release-bound entry gate, the
  /// App's tunnel hooks and the `NavigationSession` exactly as the App does,
  /// under seeded GPS error. It proves deterministic behaviour under these
  /// noise models only; it is not field evidence.
  @Suite("1 Hz live-navigation replay gate")
  struct LiveNavigationReplayGateTests {
    static let releaseFiles = [
      "c1-inner-shibakoen-to-shiodome-product-release.json",
      "c2-inner-oujiminami-itabashihoncho-product-release.json",
      "wangan-westbound-chidoricho-daikoku-pa-product-release.json",
      "daikoku-yokohama-wangankanpachi-daikoku-pa-product-release.json",
      "scenic-harumi-daikoku-pa-product-release.json",
    ]

    /// Seconds without a usable fix before the App may call the position
    /// weak; the gate requires fresh open-sky fixes never to get there.
    static let staleFixSeconds = 10
    static let maximumUnadmittedSeconds = 75
    /// The slowest bundled finish in replay is the Bayshore run's arrival
    /// inside Daikoku PA, 16 s when a GPS burst coincides with it.
    static let maximumCompletionDelaySeconds = 30
    static let maximumDeviationDetectionMeters = 1_000.0

    @Test(
      "every bundled release drives from entrance to completion",
      arguments: releaseFiles, Array(UInt64(1)...10)
    )
    func drivesEveryRelease(file: String, seed: UInt64) async throws {
      let gate = try replayGate(file)
      let run = try await gate.run(legs: gate.plannedLegs(), seed: seed)
      let summary = gateLine(file: file, seed: seed, run: run)
      print(summary)
      expectCompletes(run, summary: summary)
      #expect(run.falseRouteRecoveryCount == 0, "\(summary)")
      #expect(
        Set(run.lateOrMissingCueMovementIndexes())
          .isSubset(of: gate.structurallyUnconfirmableMovementIndexes()),
        "\(summary)"
      )
      #expect(run.longestLostSeconds < Self.staleFixSeconds, "\(summary)")
      #expect(
        run.longestUnadmittedSeconds <= Self.maximumUnadmittedSeconds,
        "\(summary)"
      )
    }

    /// Error that holds its offset for tens of seconds must not move the
    /// plan or end it; error larger than the receiver reports may cost
    /// guidance, but must still never commit an occurrence the car is not on
    /// or complete a journey it has not finished.
    @Test(
      "harder GPS error never commits a wrong occurrence",
      arguments: releaseFiles, [UInt64(1), 2]
    )
    func holdsUnderHarderNoise(file: String, seed: UInt64) async throws {
      let gate = try replayGate(file)
      let multipath = try await gate.run(
        legs: gate.plannedLegs(),
        seed: seed,
        noise: .multipath
      )
      let multipathSummary = gateLine(file: file, seed: seed, run: multipath, label: "MULTIPATH")
      print(multipathSummary)
      expectCompletes(multipath, summary: multipathSummary)
      #expect(multipath.falseRouteRecoveryCount == 0, "\(multipathSummary)")

      let underReported = try await gate.run(
        legs: gate.plannedLegs(),
        seed: seed,
        noise: .underReported
      )
      let underReportedSummary = gateLine(
        file: file,
        seed: seed,
        run: underReported,
        label: "UNDER2X"
      )
      print(underReportedSummary)
      #expect(underReported.wrongCommitCount() == 0, "\(underReportedSummary)")
      #expect(!underReported.completedEarly(), "\(underReportedSummary)")
    }

    @Test(
      "a tunnel outage keeps progress and the cues after it",
      arguments: releaseFiles, [ReplayGateTunnelOutage.noFixes, .coarseFixes]
    )
    func survivesTunnelOutage(file: String, outage: ReplayGateTunnelOutage) async throws {
      let gate = try replayGate(file)
      let run = try await gate.run(
        legs: gate.plannedLegs(),
        seed: 1,
        tunnelOutage: outage
      )
      let summary = gateLine(file: file, seed: 1, run: run, label: "TUNNEL-\(outage)")
      print(summary)
      expectCompletes(run, summary: summary)
      #expect(run.falseRouteRecoveryCount == 0, "\(summary)")
      #expect(
        Set(run.lateOrMissingCueMovementIndexes()).isSubset(
          of: gate.structurallyUnconfirmableMovementIndexes()
            .union(gate.coveredCueWindowMovementIndexes())
        ),
        "\(summary)"
      )
      #expect(run.longestLostSeconds < Self.staleFixSeconds, "\(summary)")
    }

    /// Cues withheld because geometry cannot confirm the planned branch
    /// before the decision, and cues whose whole window lies under cover.
    /// Pinned so a change that widens either fails here.
    @Test("withheld and covered cues are pinned")
    func withheldCuesArePinned() throws {
      var unconfirmable: [String: [Int]] = [:]
      var covered: [String: [Int]] = [:]
      for file in Self.releaseFiles {
        let gate = try replayGate(file)
        unconfirmable[file] = gate.structurallyUnconfirmableMovementIndexes().sorted()
        covered[file] = gate.coveredCueWindowMovementIndexes().sorted()
      }
      #expect(
        unconfirmable == [
          "c1-inner-shibakoen-to-shiodome-product-release.json": [],
          "c2-inner-oujiminami-itabashihoncho-product-release.json": [],
          "wangan-westbound-chidoricho-daikoku-pa-product-release.json": [],
          "daikoku-yokohama-wangankanpachi-daikoku-pa-product-release.json": [158],
          "scenic-harumi-daikoku-pa-product-release.json": [],
        ]
      )
      #expect(
        covered == [
          "c1-inner-shibakoen-to-shiodome-product-release.json": [],
          "c2-inner-oujiminami-itabashihoncho-product-release.json": [234, 343],
          "wangan-westbound-chidoricho-daikoku-pa-product-release.json": [285],
          "daikoku-yokohama-wangankanpachi-daikoku-pa-product-release.json": [31],
          "scenic-harumi-daikoku-pa-product-release.json": [],
        ]
      )
    }

    @Test("a surface street under the entrance never enters the route", arguments: releaseFiles)
    func surfaceStreetNeverEnters(file: String) async throws {
      let gate = try replayGate(file)
      for seed: UInt64 in [3, 4] {
        let run = try await gate.run(legs: gate.surfaceStreetLegs(), seed: seed)
        #expect(run.entryRecord == nil, "\(file) seed=\(seed)")
      }
    }

    /// A street that follows the ramp and route head within GPS error can
    /// confirm entry: geometry cannot tell it from the expressway. Once it
    /// turns away, nothing it does may move the plan, speak a cue or end
    /// the journey.
    @Test(
      "a street following the route head never drives the plan once it turns away",
      arguments: releaseFiles, [0.0, 8.0, -15.0]
    )
    func parallelStreetStopsAtTheTurn(file: String, offsetMeters: Double) async throws {
      let gate = try replayGate(file)
      let run = try await gate.run(
        legs: gate.parallelStreetLegs(offsetMeters: offsetMeters),
        seed: 3
      )
      let away = run.records.filter {
        ($0.truth.offPlanDistanceMeters ?? 0) >= 150
      }
      print(
        "PARALLEL \(file) offset=\(offsetMeters) entry=\(run.entryRecord.map { String($0.second) } ?? "none") final=\(run.records.last.map { "\($0.phase.rawValue)@\($0.currentOccurrenceIndex.map(String.init) ?? "-")" } ?? "-")"
      )
      #expect(!away.isEmpty)
      #expect(Set(away.map(\.currentOccurrenceIndex)).count <= 1, "\(file) offset=\(offsetMeters)")
      #expect(away.allSatisfy { $0.emittedMovementOccurrenceIDs.isEmpty }, "\(file) offset=\(offsetMeters)")
      #expect(!run.reachedCompletion, "\(file) offset=\(offsetMeters)")
    }

    /// Divergent junctions where the review measured the taken and planned
    /// branches running 7–11 m apart for 100–600 m.
    static let wrongBranchCases: [(file: String, movementIndex: Int)] = [
      ("c1-inner-shibakoen-to-shiodome-product-release.json", 283),
      ("c1-inner-shibakoen-to-shiodome-product-release.json", 487),
      ("c2-inner-oujiminami-itabashihoncho-product-release.json", 234),
      ("wangan-westbound-chidoricho-daikoku-pa-product-release.json", 130),
    ]

    @Test(
      "a wrong junction branch is detected and never advances the plan",
      arguments: 0..<4, [UInt64(7), 8]
    )
    func wrongBranchIsDetected(caseIndex: Int, seed: UInt64) async throws {
      let (file, movementIndex) = Self.wrongBranchCases[caseIndex]
      let gate = try replayGate(file)
      let alternatives = gate.alternativeEdgeIDs(atMovementIndex: movementIndex)
      #expect(!alternatives.isEmpty)
      let released = gate.release.navigation.bundle.runtimePolicy
        .recoveryCandidates
      for alternative in alternatives {
        let run = try await gate.run(
          legs: gate.wrongBranchLegs(
            movementIndex: movementIndex,
            alternativeEdgeID: alternative
          ),
          seed: seed
        )
        let summary = branchLine(
          file: file,
          movementIndex: movementIndex,
          alternative: alternative,
          seed: seed,
          run: run
        )
        print(summary)
        expectLeavesThePlan(run, movementIndex: movementIndex, summary: summary)
        let last = try #require(run.records.last)
        #expect(last.phase == .routeRecovery, "\(summary)")
        // Only a released, reviewed detour may become active; anything else
        // is the unavailable-recovery state with no invented maneuver.
        let hasReleasedDetour = released.contains {
          $0.triggerDirectedEdgeID == alternative
        }
        #expect(
          last.recoveryStatus == (hasReleasedDetour ? .active : .unavailable),
          "\(summary)"
        )
      }
    }

    /// Driving on past the exit is a deviation like any other: it must never
    /// finish the journey at the exit it missed. Driving on past the
    /// destination PA's entry ramp ends the drive there: the PA was not
    /// entered, and nothing on that road leads back to it.
    @Test(
      "missing the final exit never completes; passing the destination PA ends the drive",
      arguments: releaseFiles, [UInt64(1), 2]
    )
    func missedFinalExitNeverCompletes(file: String, seed: UInt64) async throws {
      let gate = try replayGate(file)
      let movementIndex = gate.finalDivergenceIndex
      let alternatives = gate.alternativeEdgeIDs(atMovementIndex: movementIndex)
      #expect(!alternatives.isEmpty, "\(file)")
      for alternative in alternatives {
        let run = try await gate.run(
          legs: gate.wrongBranchLegs(
            movementIndex: movementIndex,
            alternativeEdgeID: alternative,
            branchMeters: 1_500
          ),
          seed: seed
        )
        let summary =
          branchLine(
            file: file,
            movementIndex: movementIndex,
            alternative: alternative,
            seed: seed,
            run: run
          )
          + " endedAfter=\(run.completedAfterOffPlanMeters.map { String(Int($0)) } ?? "never")"
        print("MISSED-FINAL " + summary)
        #expect(run.entryRecord != nil, "\(summary)")
        #expect(run.offPlanCommitCount(movementIndex: movementIndex) == 0, "\(summary)")
        #expect(run.offPlanPromptCount(movementIndex: movementIndex) == 0, "\(summary)")
        if gate.finalStopStartIndex == nil {
          expectLeavesThePlan(run, movementIndex: movementIndex, summary: summary)
          #expect(!run.reachedCompletion, "\(summary)")
        } else {
          #expect(
            run.records.last?.phaseTrigger == "DESTINATION_PARKING_AREA_NOT_ENTERED",
            "\(summary)"
          )
          #expect(
            !run.records.contains { $0.recoveryStatus == .unavailable },
            "\(summary)"
          )
          #expect(
            (run.completedAfterOffPlanMeters ?? .infinity)
              <= Self.maximumDeviationDetectionMeters,
            "\(summary)"
          )
        }
      }
    }

    /// Under accuracy reported at half the real error, these drives ended as
    /// "PA not entered" before the evidence checks: on the PA's own road
    /// beside the road past it (scenic seeds 2 and 11), and in the first lap,
    /// passing near that road (loop seed 14).
    @Test(
      "a car on its way into the PA never ends the drive as not entered",
      arguments: zip(
        [
          "scenic-harumi-daikoku-pa-product-release.json",
          "scenic-harumi-daikoku-pa-product-release.json",
          "daikoku-yokohama-wangankanpachi-daikoku-pa-product-release.json",
        ],
        [UInt64(2), 11, 14]
      )
    )
    func enteringThePAIsNeverEndedAsNotEntered(
      file: String,
      seed: UInt64
    ) async throws {
      let gate = try replayGate(file)
      let run = try await gate.run(
        legs: gate.plannedLegs(),
        seed: seed,
        noise: .underReported
      )
      let summary = gateLine(file: file, seed: seed, run: run, label: "UNDER2X")
      print(summary)
      expectCompletes(run, summary: summary)
    }

    private func expectCompletes(_ run: ReplayGateRun, summary: String) {
      #expect(run.entryRecord != nil, "\(summary)")
      #expect(run.wrongCommitCount() == 0, "\(summary)")
      #expect(run.reachedCompletion, "\(summary)")
      #expect(!run.completedEarly(), "\(summary)")
      #expect(
        (run.completionDelaySeconds ?? .max) <= Self.maximumCompletionDelaySeconds,
        "\(summary)"
      )
      if run.gate.finalStopStartIndex != nil {
        #expect(
          run.records.last?.phaseTrigger == "PARKING_AREA_DESTINATION_REACHED",
          "\(summary)"
        )
      }
    }

    private func expectLeavesThePlan(
      _ run: ReplayGateRun,
      movementIndex: Int,
      summary: String
    ) {
      #expect(run.entryRecord != nil, "\(summary)")
      #expect(run.offPlanCommitCount(movementIndex: movementIndex) == 0, "\(summary)")
      #expect(run.offPlanPromptCount(movementIndex: movementIndex) == 0, "\(summary)")
      #expect(
        (run.deviationDetectedAfterOffPlanMeters ?? .infinity)
          <= Self.maximumDeviationDetectionMeters,
        "\(summary)"
      )
    }
  }

  func gateLine(
    file: String,
    seed: UInt64,
    run: ReplayGateRun,
    label: String = "GATE"
  ) -> String {
    var parts = ["\(label) \(file) seed=\(seed)"]
    parts.append("entry=\(run.entryRecord.map { String($0.second) } ?? "none")")
    parts.append("completed=\(run.reachedCompletion)")
    parts.append("early=\(run.completedEarly())")
    parts.append("delay=\(run.completionDelaySeconds.map { String($0) } ?? "-")")
    parts.append("wrong=\(run.wrongCommitCount())")
    parts.append("falseRecovery=\(run.falseRouteRecoveryCount)")
    parts.append("lateCues=\(run.lateOrMissingCueMovementIndexes())")
    parts.append("minLead=\(run.minimumCueLeadMeters().map { String(Int($0)) } ?? "-")")
    parts.append("rawBelowHigh=\(String(format: "%.2f", run.rawBelowHighFraction))")
    parts.append("admitted=\(String(format: "%.2f", run.admittedFraction))")
    parts.append("unadmittedRun=\(run.longestUnadmittedSeconds)")
    parts.append("lostRun=\(run.longestLostSeconds)")
    parts.append("fixes=\(run.records.count)/\(run.truthCount)")
    return parts.joined(separator: " ")
  }

  func branchLine(
    file: String,
    movementIndex: Int,
    alternative: String,
    seed: UInt64,
    run: ReplayGateRun
  ) -> String {
    var parts = ["BRANCH \(file) m=\(movementIndex) alt=\(alternative) seed=\(seed)"]
    parts.append("entry=\(run.entryRecord.map { String($0.second) } ?? "none")")
    parts.append("offPlanCommits=\(run.offPlanCommitCount(movementIndex: movementIndex))")
    parts.append("offPlanPrompts=\(run.offPlanPromptCount(movementIndex: movementIndex))")
    parts.append(
      "detectedAfter=\(run.deviationDetectedAfterOffPlanMeters.map { String(Int($0)) } ?? "never")"
    )
    if let last = run.records.last {
      parts.append("final=\(last.phase.rawValue)/\(last.recoveryStatus.rawValue)")
    }
    return parts.joined(separator: " ")
  }

  func replayGate(_ file: String) throws -> LiveNavigationReplayGate {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let release = try KaidoProductReleaseArtifactCodec.decode(
      Data(
        contentsOf:
          root
          .appendingPathComponent("data/product/releases")
          .appendingPathComponent(file)
      )
    )
    return LiveNavigationReplayGate(
      release: release,
      database: try replayGateDatabase()
    )
  }

  private let replayGateDatabaseCache = ReplayGateDatabaseCache()

  private final class ReplayGateDatabaseCache: @unchecked Sendable {
    private let lock = NSLock()
    private var database: ShutoNetworkDatabase?

    func load() throws -> ShutoNetworkDatabase {
      lock.lock()
      defer { lock.unlock() }
      if let database { return database }
      let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
      let loaded = try JSONDecoder().decode(
        ShutoNetworkDatabase.self,
        from: Data(
          contentsOf:
            root
            .appendingPathComponent(
              "data/route-atlas/osm-derived/shuto-whole-network-20260804.json"
            )
        )
      )
      database = loaded
      return loaded
    }
  }

  func replayGateDatabase() throws -> ShutoNetworkDatabase {
    try replayGateDatabaseCache.load()
  }
#endif
