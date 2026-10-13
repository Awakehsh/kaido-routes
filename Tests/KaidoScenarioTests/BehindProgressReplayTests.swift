#if canImport(CoreLocation)
  import Foundation
  import KaidoNavigation
  import Testing

  /// C2 inner Oujiminami→Itabashihoncho passes its own entrance ramp again
  /// near its end, 0.2 m beside the mainline. Under accuracy reported at half
  /// the real error a fix there once matched the ramp the drive started on,
  /// a road behind admitted progress, and the next fix off every road made
  /// two off-plan fixes: the drive announced rerouting on the planned road
  /// for 162 s and passed its final junction without a cue.
  @Suite("1 Hz off-plan evidence behind progress")
  struct BehindProgressReplayTests {
    @Test(
      "a ramp behind progress that no road leads back onto is no deviation",
      arguments: [("c2-inner-oujiminami-itabashihoncho-product-release.json", UInt64(6))]
    )
    func rampBehindProgressIsNoDeviation(file: String, seed: UInt64) async throws {
      let gate = try replayGate(file)
      let run = try await gate.run(
        legs: gate.plannedLegs(),
        seed: seed,
        noise: .underReported
      )
      let summary = gateLine(file: file, seed: seed, run: run, label: "UNDER2X")
      print(summary)
      #expect(run.falseRouteRecoveryCount == 0, "\(summary)")
    }
  }
#endif
