import Foundation
import KaidoDomain
import KaidoNavigation
import KaidoRouting
import Testing

@Test("Dropping a lap moves exactly one lap forward and skips what it passed")
func skipOneLapMovesExactlyOneLapForward() {
  var engine = lapEngine()
  engine.enterStrictRoute(
    firstOccurrenceID: "lap.occurrence.2",
    trigger: "TEST_ENTER"
  )
  #expect(engine.snapshot.currentOccurrenceIndex == 2)
  // Three laps of four occurrences each, starting at index 0.
  #expect(engine.snapshot.journeyPhase == .strictRoute)

  let target = engine.skipOneLap(trigger: "DRIVER_DROPPED_ONE_LAP")
  #expect(target == "lap.occurrence.6")
  #expect(engine.snapshot.currentOccurrenceID == "lap.occurrence.6")
  #expect(
    engine.snapshot.lastPhaseTransitionTrigger == "DRIVER_DROPPED_ONE_LAP"
  )
  // The lap between where the drive was and where it landed was not driven.
  #expect(
    engine.snapshot.skippedOccurrenceIDs == [
      "lap.occurrence.3",
      "lap.occurrence.4",
      "lap.occurrence.5",
    ]
  )
  #expect(!engine.snapshot.completedOccurrenceIDs.contains("lap.occurrence.3"))
}

@Test("The last lap has nothing left to drop")
func skipOneLapRefusesOnTheFinalLap() {
  var engine = lapEngine()
  engine.enterStrictRoute(
    firstOccurrenceID: "lap.occurrence.9",
    trigger: "TEST_ENTER"
  )
  // Occurrence 9 is inside the third and final lap.
  #expect(engine.skipOneLap(trigger: "DRIVER_DROPPED_ONE_LAP") == nil)
  #expect(engine.snapshot.currentOccurrenceID == "lap.occurrence.9")
  #expect(engine.snapshot.skippedOccurrenceIDs.isEmpty)

  // Two drops from the first lap exhaust a three-lap route.
  var second = lapEngine()
  second.enterStrictRoute(
    firstOccurrenceID: "lap.occurrence.1",
    trigger: "TEST_ENTER"
  )
  #expect(second.skipOneLap(trigger: "T") == "lap.occurrence.5")
  #expect(second.skipOneLap(trigger: "T") == "lap.occurrence.9")
  #expect(second.skipOneLap(trigger: "T") == nil)
}

@Test("A route without released lap boundaries can never drop a lap")
func skipOneLapRefusesWithoutReleasedBoundaries() {
  var engine = NavigationEngine(
    configuration: NavigationConfiguration(routePlan: lapRoutePlan()),
    initialSnapshot: NavigationSnapshot(journeyPhase: .planning)
  )
  engine.enterStrictRoute(
    firstOccurrenceID: "lap.occurrence.2",
    trigger: "TEST_ENTER"
  )
  #expect(engine.skipOneLap(trigger: "DRIVER_DROPPED_ONE_LAP") == nil)
  #expect(engine.snapshot.currentOccurrenceID == "lap.occurrence.2")
}

@Test("A lap cannot be dropped before the strict route is entered")
func skipOneLapRefusesOutsideStrictRoute() {
  var engine = lapEngine()
  #expect(engine.snapshot.journeyPhase == .planning)
  #expect(engine.skipOneLap(trigger: "DRIVER_DROPPED_ONE_LAP") == nil)
}

@Test("A release refuses lap marks that do not resolve, order, or pair up")
func releaseBundleValidatesLapBoundaries() throws {
  let fixture = navigationReleaseBundleFixture()
  func buildsWith(_ boundaries: [String]) -> Bool {
    let policy = ReleasedNavigationRuntimePolicy(
      id: fixture.runtimePolicy.id,
      networkSnapshotID: fixture.runtimePolicy.networkSnapshotID,
      routePlanID: fixture.runtimePolicy.routePlanID,
      entryTransition: fixture.runtimePolicy.entryTransition,
      recoveryCandidates: fixture.runtimePolicy.recoveryCandidates,
      egressOptions: fixture.runtimePolicy.egressOptions,
      lapBoundaryOccurrenceIDs: boundaries
    )
    return
      (try? NavigationReleaseBundle(
        networkSnapshot: fixture.networkSnapshot,
        routePlan: fixture.routePlan,
        editorCatalog: fixture.editorCatalog,
        editorPresentationCatalog: fixture.editorPresentationCatalog,
        runtimePolicy: policy,
        matcherCorridor: fixture.matcherCorridor,
        decisionZones: fixture.decisionZones,
        releasedGuidance: fixture.releasedGuidance,
        junctionViews: fixture.junctionViews
      )) != nil
  }

  // A route without laps carries no marks at all.
  #expect(buildsWith([]))
  #expect(
    buildsWith(["test.occurrence.entry", "test.occurrence.loop-edge-1"])
  )
  // A single mark bounds nothing.
  #expect(!buildsWith(["test.occurrence.entry"]))
  // A mark the plan does not contain would let the core jump off the route.
  #expect(!buildsWith(["test.occurrence.entry", "test.occurrence.absent"]))
  #expect(
    !buildsWith(["test.occurrence.loop-edge-1", "test.occurrence.entry"])
  )
  #expect(!buildsWith(["test.occurrence.entry", "test.occurrence.entry"]))
}

@Test("A policy without lap structure encodes no lap key at all")
func runtimePolicyOmitsAbsentLapStructure() throws {
  let encoder = JSONEncoder()
  let withoutLaps = try String(
    decoding: encoder.encode(lapRuntimePolicy(boundaries: [])),
    as: UTF8.self
  )
  #expect(!withoutLaps.contains("lap_boundary_occurrence_ids"))

  let withLaps = try encoder.encode(
    lapRuntimePolicy(boundaries: ["lap.occurrence.0", "lap.occurrence.4"])
  )
  #expect(
    String(decoding: withLaps, as: UTF8.self)
      .contains("lap_boundary_occurrence_ids")
  )
  let decoded = try JSONDecoder().decode(
    ReleasedNavigationRuntimePolicy.self,
    from: withLaps
  )
  #expect(
    decoded.lapBoundaryOccurrenceIDs == [
      "lap.occurrence.0",
      "lap.occurrence.4",
    ]
  )
}

/// Three laps of four occurrences, laid out from index 0 with a two-occurrence
/// tail: boundaries at 0, 4, 8 and the tail beginning at 12.
private func lapRoutePlan() -> RoutePlan {
  RoutePlan(
    id: "test.plan.lap",
    networkSnapshotID: "test.snapshot.lap",
    entryFacilityID: "test.entrance.lap",
    exitFacilityID: "test.exit.lap",
    recoveryPolicy: .strict,
    actualDistanceKM: 40,
    occurrences: (0..<14).map { index in
      RouteOccurrence(
        id: "lap.occurrence.\(index)",
        index: index,
        kind: .edge,
        entityID: "lap.edge.\(index % 4)"
      )
    }
  )
}

private func lapRuntimePolicy(
  boundaries: [String]
) -> ReleasedNavigationRuntimePolicy {
  ReleasedNavigationRuntimePolicy(
    id: "test.runtime-policy.lap",
    networkSnapshotID: "test.snapshot.lap",
    routePlanID: "test.plan.lap",
    entryTransition: EntryTransition(
      facilityID: "test.entrance.lap",
      directedEdgeIDs: ["test.edge.surface", "test.edge.ramp"],
      firstRouteOccurrenceID: "lap.occurrence.0"
    ),
    recoveryCandidates: [],
    egressOptions: [
      EgressOption(
        id: "test.egress.lap",
        firstEligibleOccurrenceID: "lap.occurrence.13",
        exitFacilityID: "test.exit.lap",
        egressOccurrenceIDs: ["test.edge.exit"],
        isReleased: true
      )
    ],
    lapBoundaryOccurrenceIDs: boundaries
  )
}

private func lapEngine() -> NavigationEngine {
  NavigationEngine(
    configuration: NavigationConfiguration(
      routePlan: lapRoutePlan(),
      lapBoundaryOccurrenceIDs: [
        "lap.occurrence.0",
        "lap.occurrence.4",
        "lap.occurrence.8",
        "lap.occurrence.12",
      ]
    ),
    initialSnapshot: NavigationSnapshot(journeyPhase: .planning)
  )
}
