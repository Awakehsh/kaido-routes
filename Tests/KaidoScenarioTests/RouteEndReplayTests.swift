#if canImport(CoreLocation)
  import Foundation
  import KaidoNavigation
  import Testing

  /// The exit ramps at C1 Shiodome and C2 Itabashihoncho run within a few
  /// metres of the road they leave for their whole length, and past
  /// Shiodome that road is the plan's own first pass. These drives once froze
  /// before the exit and never ended, ended on the first pass two kilometres
  /// before the end, or ended at an exit the car had driven past.
  @Suite("1 Hz route end at an exit beside the road it leaves")
  struct RouteEndReplayTests {
    static let maximumCompletionDelaySeconds = 30

    @Test(
      "a drive that takes its exit completes once past it",
      arguments: [
        // The Itabashihoncho ramp beside the Route 5 mainline: progress froze
        // 500 m before the end with no egress.
        ("c2-inner-oujiminami-itabashihoncho-product-release.json", "URBAN", UInt64(15)),
        ("c2-inner-oujiminami-itabashihoncho-product-release.json", "MULTIPATH", 6),
        ("c2-inner-oujiminami-itabashihoncho-product-release.json", "MULTIPATH", 11),
        ("c2-inner-oujiminami-itabashihoncho-product-release.json", "MULTIPATH", 18),
        // The Shiodome ramp read as the covered first pass beside it, which
        // left reacquisition pending for the rest of the drive.
        ("c1-inner-shibakoen-to-shiodome-product-release.json", "UNDER2X", 1),
        ("c1-inner-shibakoen-to-shiodome-product-release.json", "UNDER2X", 6),
        // Admitted progress stops before the Shiodome ramp; the drive ended
        // on the ramp, or with a matcher limited to nearby passes, never.
        ("c1-inner-shibakoen-to-shiodome-product-release.json", "URBAN", 34),
        ("c1-inner-shibakoen-to-shiodome-product-release.json", "MULTIPATH", 18),
      ]
    )
    func completesPastTheExit(file: String, noise: String, seed: UInt64) async throws {
      let gate = try replayGate(file)
      let run = try await gate.run(legs: gate.plannedLegs(), seed: seed, noise: Self.noise(noise))
      let summary = gateLine(file: file, seed: seed, run: run, label: "ROUTE-END-\(noise)")
      print(summary)
      #expect(run.reachedCompletion, "\(summary)")
      #expect(!run.completedEarly(), "\(summary)")
      #expect(
        (run.completionDelaySeconds ?? .max) <= Self.maximumCompletionDelaySeconds,
        "\(summary)"
      )
    }

    /// Driving on past Shiodome follows the plan's own first pass beside
    /// the ramp; the drive ended there as if the car had taken the exit.
    @Test(
      "driving past the exit never completes the drive",
      arguments: [
        ("c1-inner-shibakoen-to-shiodome-product-release.json", "URBAN", UInt64(11)),
        ("c1-inner-shibakoen-to-shiodome-product-release.json", "URBAN", 13),
        ("c1-inner-shibakoen-to-shiodome-product-release.json", "MULTIPATH", 15),
        ("c1-inner-shibakoen-to-shiodome-product-release.json", "MULTIPATH", 17),
      ]
    )
    func missedExitNeverCompletes(file: String, noise: String, seed: UInt64) async throws {
      let gate = try replayGate(file)
      let movementIndex = gate.finalDivergenceIndex
      let alternatives = gate.alternativeEdgeIDs(atMovementIndex: movementIndex)
      #expect(!alternatives.isEmpty)
      for alternative in alternatives {
        let run = try await gate.run(
          legs: gate.wrongBranchLegs(
            movementIndex: movementIndex,
            alternativeEdgeID: alternative,
            branchMeters: 1_500
          ),
          seed: seed,
          noise: Self.noise(noise)
        )
        let summary = gateLine(file: file, seed: seed, run: run, label: "MISSED-EXIT-\(noise)")
        print(summary)
        #expect(!run.reachedCompletion, "\(summary)")
      }
    }

    /// The first pass of C1 inner from Shibakoen runs beside the Shiodome
    /// exit ramp two minutes into the drive; the matcher placing it on the
    /// ramp ended the drive there.
    @Test("passing the exit early in the drive never ends it")
    func earlyPassBesideTheExitNeverEnds() async throws {
      let file = "c1-inner-shibakoen-to-shiodome-product-release.json"
      let gate = try replayGate(file)
      let run = try await gate.run(legs: gate.plannedLegs(), seed: 32, noise: .underReported)
      let summary = gateLine(file: file, seed: 32, run: run, label: "ROUTE-END-UNDER2X")
      print(summary)
      #expect(!run.completedEarly(), "\(summary)")
    }

    private static func noise(_ label: String) -> ReplayGateNoiseModel {
      switch label {
      case "MULTIPATH": return .multipath
      case "UNDER2X": return .underReported
      default: return .urban
      }
    }
  }
#endif
