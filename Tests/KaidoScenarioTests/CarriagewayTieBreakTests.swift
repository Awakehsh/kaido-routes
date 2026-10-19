#if canImport(CoreLocation)
  import Foundation
  import KaidoDomain
  import KaidoRouting
  import Testing

  /// A link beside a carriageway that rejoins it, within a few metres of the
  /// carriageway's own length, once won the circuit search: at Hakozaki JCT the
  /// outbound Route 6 plan took the rotary link, 0.8 m shorter, and at Shibaura JCT
  /// the Route 11 approach took a 0.1 m shorter link. Neither link carries
  /// released guidance, so a driver who stays on the carriageway looked off
  /// the plan.
  @Suite("Circuit plans stay on the carriageway on near-ties")
  struct CarriagewayTieBreakTests {
    @Test(
      "a link a few metres shorter than the carriageway it rejoins is not planned",
      arguments: [
        // Hakozaki JCT: Route 7 Ichinoe, C1 inner, back out Route 6 to Komatsugawa.
        Case(
          circuit: .c1Inner, entry: "shuto.ic.7.ichinoe", exit: "shuto.ic.7.komatsugawa",
          link: "osm.766719786.0.forward", carriageway: "osm.44805853.0.forward"
        ),
        // Shibaura JCT: Route 11 Daiba, C1 inner, to Shiodome.
        Case(
          circuit: .c1Inner, entry: "shuto.ic.11.daiba", exit: "shuto.ic.c1.shiodome",
          link: "osm.4848740.0.forward", carriageway: "osm.316305910.20.forward"
        ),
      ]
    )
    func staysOnTheCarriageway(_ tie: Case) throws {
      let route = try planner().planCircuit(
        circuit: tie.circuit, entryFacilityID: tie.entry, exitFacilityID: tie.exit, laps: 1
      )
      let edgeIDs = route.edges.map(\.edgeID)
      #expect(!edgeIDs.contains(tie.link))
      #expect(edgeIDs.contains(tie.carriageway))
    }

    /// A route saved before the tie-break took the Shibaura JCT link. Saved routes
    /// and restored drives re-plan their circuit and must reproduce the stored
    /// plan exactly, or they no longer open.
    @Test("a plan stored before the tie-break still reproduces exactly")
    func storedPlanReproduces() throws {
      let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(
          "docs/testing/fixtures/saved-route-daiba-shiodome-before-carriageway-tie-break.json"
        )
      let stored = try SharedRouteCodec.decode(Data(contentsOf: url)).routePlan
      let planner = try planner()
      let current = try planner.planCircuit(
        circuit: .c1Inner, entryFacilityID: stored.entryFacilityID,
        exitFacilityID: stored.exitFacilityID, laps: 1
      )
      #expect(current.routePlan != stored)
      let reproduced = try planner.planCircuit(reproducing: stored, circuit: .c1Inner, laps: 1)
      #expect(reproduced.routePlan == stored)
      #expect(reproduced.lapBoundaryOccurrenceIndices.count == 2)
      #expect(try planner.planCircuit(reproducing: current.routePlan, circuit: .c1Inner, laps: 1) == current)
    }

    struct Case: Sendable, CustomTestStringConvertible {
      let circuit: ShutoCircuitDefinition
      let entry: String
      let exit: String
      let link: String
      let carriageway: String
      var testDescription: String { "\(entry) -> \(exit)" }
    }

    private func planner() throws -> ShutoRoutePlanner {
      try ShutoRoutePlanner(database: replayGateDatabase())
    }
  }
#endif
