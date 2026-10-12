#if canImport(CoreLocation)
  import Foundation
  import KaidoDomain
  import KaidoNavigation
  import KaidoRouting
  import Testing

  /// The deterministic 1 Hz gate for every bundled foreground release. It
  /// drives the Core Location adapters, the release-bound entry gate and the
  /// `NavigationSession` exactly as the App does, under seeded GPS error. It
  /// proves deterministic behaviour under that noise model only; it is not
  /// field evidence.
  @Suite("1 Hz live-navigation replay gate")
  struct LiveNavigationReplayGateTests {
    static let releaseFiles = [
      "c1-inner-shibakoen-to-shiodome-product-release.json",
      "c2-inner-oujiminami-shikahamabashi-product-release.json",
      "wangan-westbound-chidoricho-daikoku-pa-product-release.json",
      "daikoku-yokohama-wangankanpachi-daikoku-pa-product-release.json",
      "scenic-harumi-daikoku-pa-product-release.json",
    ]

    /// Seconds without a usable fix before the App may call the position
    /// weak; the gate requires fresh fixes never to get there.
    static let staleFixSeconds = 10
    static let maximumUnadmittedSeconds = 75
    static let maximumCompletionDelaySeconds = 15
    static let maximumDeviationDetectionMeters = 1_000.0

    @Test("every bundled release drives from entrance to completion", arguments: releaseFiles)
    func drivesEveryRelease(file: String) async throws {
      let gate = try replayGate(file)
      let unconfirmable = gate.structurallyUnconfirmableMovementIndexes()
      for seed: UInt64 in [1, 2] {
        let run = try await gate.run(legs: gate.plannedLegs(), seed: seed)
        let summary = gateLine(file: file, seed: seed, run: run)
        print(summary)
        #expect(run.entryRecord != nil, "\(summary)")
        #expect(run.wrongCommitCount() == 0, "\(summary)")
        #expect(run.reachedCompletion, "\(summary)")
        if let delay = run.completionDelaySeconds {
          #expect(delay <= Self.maximumCompletionDelaySeconds, "\(summary)")
        }
        #expect(
          Set(run.lateOrMissingCueMovementIndexes()).isSubset(of: unconfirmable),
          "\(summary) unconfirmable=\(unconfirmable.sorted())"
        )
        #expect(run.longestLostSeconds < Self.staleFixSeconds, "\(summary)")
        #expect(
          run.longestUnadmittedSeconds <= Self.maximumUnadmittedSeconds,
          "\(summary)"
        )
      }
    }

    /// Cues withheld because geometry cannot confirm the planned branch
    /// before the decision. Pinned so a change that widens them fails here.
    @Test("only the Namamugi second split is geometrically unconfirmable")
    func unconfirmableCuesArePinned() throws {
      var found: [String: [Int]] = [:]
      for file in Self.releaseFiles {
        found[file] = try replayGate(file)
          .structurallyUnconfirmableMovementIndexes().sorted()
      }
      #expect(
        found == [
          "c1-inner-shibakoen-to-shiodome-product-release.json": [],
          "c2-inner-oujiminami-shikahamabashi-product-release.json": [],
          "wangan-westbound-chidoricho-daikoku-pa-product-release.json": [],
          "daikoku-yokohama-wangankanpachi-daikoku-pa-product-release.json": [158],
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

    /// Divergent junctions where the review measured the taken and planned
    /// branches running 7–11 m apart for 100–600 m.
    static let wrongBranchCases: [(file: String, movementIndex: Int)] = [
      ("c1-inner-shibakoen-to-shiodome-product-release.json", 283),
      ("c1-inner-shibakoen-to-shiodome-product-release.json", 487),
      ("c2-inner-oujiminami-shikahamabashi-product-release.json", 234),
      ("wangan-westbound-chidoricho-daikoku-pa-product-release.json", 130),
    ]

    @Test("a wrong junction branch is detected and never advances the plan", arguments: 0..<4)
    func wrongBranchIsDetected(caseIndex: Int) async throws {
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
          seed: 7
        )
        let summary = branchLine(
          file: file,
          movementIndex: movementIndex,
          alternative: alternative,
          run: run
        )
        print(summary)
        #expect(run.entryRecord != nil, "\(summary)")
        #expect(run.offPlanCommitCount(movementIndex: movementIndex) == 0, "\(summary)")
        #expect(run.offPlanPromptCount(movementIndex: movementIndex) == 0, "\(summary)")
        let detected = try #require(
          run.deviationDetectedAfterOffPlanMeters,
          "\(summary)"
        )
        #expect(detected <= Self.maximumDeviationDetectionMeters, "\(summary)")
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
  }

  func gateLine(file: String, seed: UInt64, run: ReplayGateRun) -> String {
    var parts = ["GATE \(file) seed=\(seed)"]
    parts.append("entry=\(run.entryRecord.map { String($0.second) } ?? "none")")
    parts.append("completed=\(run.reachedCompletion)")
    parts.append("delay=\(run.completionDelaySeconds.map { String($0) } ?? "-")")
    parts.append("wrong=\(run.wrongCommitCount())")
    parts.append("lateCues=\(run.lateOrMissingCueMovementIndexes())")
    parts.append("minLead=\(run.minimumCueLeadMeters().map { String(Int($0)) } ?? "-")")
    parts.append("rawBelowHigh=\(String(format: "%.2f", run.rawBelowHighFraction))")
    parts.append("rawRun=\(run.longestRawBelowHighRunSeconds)")
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
    run: ReplayGateRun
  ) -> String {
    var parts = ["BRANCH \(file) m=\(movementIndex) alt=\(alternative)"]
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
