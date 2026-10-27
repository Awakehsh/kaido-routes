#if canImport(CoreLocation)
  import Foundation
  import KaidoNavigation
  import KaidoRouting
  import Testing

  /// Where a fork just behind the car leaves the plan by a road that runs on
  /// beside it, admission waits for the roads to part, but the car has come
  /// as far on either road: presentation draws it on the plan meanwhile, and
  /// once the drive leaves the plan, no longer.
  @Suite("1 Hz drawn position beside the plan")
  struct DrawnPositionReplayTests {
    /// C1 inner past Shiodome on the third lap: the Shiodome exit ramp runs
    /// 0.3-16 m beside the plan from its root, and admission held progress
    /// for about 20 s while every fix matched the car's own occurrence.
    @Test("the car is drawn along the plan beside the Shiodome exit ramp")
    func besideTheShiodomeExitRamp() async throws {
      let gate = try NavigationStress.fixture("loop:c1-inner-s1:3").gate
      let run = try await gate.run(legs: gate.plannedLegs(), seed: 3, noise: .urban)
      let summary = gateLine(file: "c1 inner shiodome", seed: 3, run: run, label: "DRAWN-URBAN")
      print(summary + " undrawnRun=\(run.longestUndrawnSeconds)")
      let beside = run.records.filter { record in
        guard record.phase == .strictRoute, record.observedCoordinate != nil,
          case .occurrence(let index) = record.truth.kind
        else { return false }
        return Self.shiodomeRampStretch.contains(index)
      }
      let heldDrawn = beside.filter { $0.engineConfidence != .high && $0.drawsPosition }
      #expect(run.reachedCompletion, "\(summary)")
      #expect(heldDrawn.count >= Self.minimumHeldDrawnFixes, "\(summary) heldDrawn=\(heldDrawn.count)")
      #expect(
        run.longestUndrawnSeconds < run.longestUnadmittedSeconds,
        "\(summary) undrawnRun=\(run.longestUndrawnSeconds)"
      )
    }

    /// Lap 3's occurrences from the Shiodome exit ramp's root to where C1 goes
    /// under cover.
    static let shiodomeRampStretch = 915...921
    static let minimumHeldDrawnFixes = 10
  }
#endif
