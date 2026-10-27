#if canImport(CoreLocation)
  import Foundation
  import KaidoNavigation
  import KaidoRouting
  import Testing

  /// A fork can lead straight onto a road the plan drives only later. A car
  /// that takes it is on the plan again there; the passes it left out are
  /// skipped, as a passed-by waypoint's are, and the drive goes on to its exit.
  @Suite("1 Hz shortcut onto a later pass")
  struct LaterPassShortcutReplayTests {
    /// Shinonome JCT: Route 10 leaves the Bayshore for Toyosu, where this
    /// drive comes back by C2. Taking it held progress at the fork until the
    /// drive left at its own exit as an unplanned one.
    @Test("a shortcut onto Route 10 at Shinonome JCT ends at its own exit")
    func shinonomeShortcut() async throws {
      let gate = try NavigationStress.fixture("via:c2:shuto.ic.c1.shiodome:shuto.ic.10.toyosu:1").gate
      let fork = try #require(
        NavigationStress.forkMovement(
          gate,
          spec: "fork=osm.888066406.1.forward/osm.23169038.0.forward/osm.40636701.0.forward"
        )
      )
      let shortcut = try #require(
        gate.shortcutLegs(movementIndex: fork.movementIndex, alternativeEdgeID: fork.alternative)
      )
      let run = try await gate.run(legs: shortcut.legs, seed: 1, noise: .urban)
      let summary = gateLine(file: "shiodome toyosu", seed: 1, run: run, label: "SHORTCUT-URBAN")
      print(summary)
      #expect(run.reachedCompletion, "\(summary)")
      #expect(!run.completedEarly(), "\(summary)")
      #expect(!run.handedOver, "\(summary)")
    }

    /// Shiodome JCT: the exit link off C1 is this drive's last road, after a
    /// lap of C1 inner from Shibakoen. A car that takes it at once leaves the
    /// expressway with progress still at the fork, by the planned exit all
    /// the same; it was handed over as having left at an unplanned one.
    @Test("a shortcut onto the planned exit itself ends the drive there")
    func shortcutOntoThePlannedExit() async throws {
      let gate = try replayGate("c1-inner-shibakoen-to-shiodome-product-release.json")
      let fork = try #require(
        NavigationStress.forkMovement(
          gate,
          spec: "fork=osm.45021970.28.forward/osm.316213226.0.forward/osm.24402125.0.forward"
        )
      )
      let shortcut = try #require(
        gate.shortcutLegs(movementIndex: fork.movementIndex, alternativeEdgeID: fork.alternative)
      )
      let run = try await gate.run(legs: shortcut.legs, seed: 7, noise: .urban)
      let summary = gateLine(file: "shibakoen shiodome", seed: 7, run: run, label: "EXIT-SHORTCUT-URBAN")
      print(summary)
      #expect(run.reachedCompletion, "\(summary)")
      #expect(!run.handedOver, "\(summary)")
    }

    /// Tatsumi JCT: Route 9, a pass this drive makes 56 km later, runs 13 m
    /// beside the Bayshore. Fixes from a receiver that reports half its error
    /// land on it while the car stays on the Bayshore; with the deviation
    /// margin as evidence the drive jumped there.
    @Test("fixes scattered onto a later pass beside the plan do not jump the drive")
    func noJumpOntoLaterPassBeside() async throws {
      let gate = try NavigationStress.fixture(
        "via:c2:shuto.ic.1-haneda.heiwajima:shuto.ic.1-haneda.suzugamori:1"
      ).gate
      let run = try await gate.run(legs: gate.plannedLegs(), seed: 15, noise: .underReported)
      let summary = gateLine(file: "heiwajima suzugamori", seed: 15, run: run, label: "LATER-BESIDE-UNDER2X")
      print(summary)
      #expect(run.reachedCompletion, "\(summary)")
      #expect(run.wrongCommitCount() == 0, "\(summary)")
    }

    /// Tatsumi JCT the other way: Route 9 is this drive's last stretch to
    /// Edagawa. A car that takes it from the Bayshore and then drives on past
    /// the Edagawa exit is on the plan until that exit, and has missed it.
    @Test("driving past the exit after a shortcut onto its last stretch is seen")
    func missedExitAfterShortcut() async throws {
      let gate = try NavigationStress.fixture("via:c2:shuto.ic.10.toyosu:shuto.ic.9.edagawa:1").gate
      let fork = try #require(
        NavigationStress.forkMovement(
          gate,
          spec: "fork=osm.44882718.3.forward/osm.678761503.0.forward/osm.4854234.0.forward"
        )
      )
      let run = try await gate.run(
        legs: gate.wrongBranchLegs(
          movementIndex: fork.movementIndex, alternativeEdgeID: fork.alternative,
          branchMeters: 6_000
        ),
        seed: 1,
        noise: .underReported
      )
      let summary = gateLine(file: "toyosu edagawa", seed: 1, run: run, label: "SHORTCUT-MISSED-EXIT-UNDER2X")
      print(summary)
      let reanchored = try #require(
        run.records.first { ($0.currentOccurrenceIndex ?? 0) > fork.movementIndex + 1_000 },
        "\(summary)"
      )
      #expect(
        run.records.contains { $0.second > reanchored.second && $0.phase == .routeRecovery },
        "\(summary)"
      )
      #expect(!run.reachedCompletion, "\(summary)")
    }
  }
#endif
