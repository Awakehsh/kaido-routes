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

@Test("Finishing the current lap skips every later lap and retains the exit tail")
func finishCurrentLapKeepsCurrentPositionAndExitTail() {
  var engine = lapEngine()
  engine.enterStrictRoute(firstOccurrenceID: "lap.occurrence.2", trigger: "TEST_ENTER")
  #expect(engine.skipRemainingLaps(trigger: "DRIVER_FINISHING_CURRENT_LAP") == "lap.occurrence.10")
  #expect(engine.snapshot.journeyPhase == .strictRoute)
  #expect(engine.snapshot.skippedOccurrenceIDs == (3...9).map { "lap.occurrence.\($0)" })
  #expect(!engine.snapshot.completedOccurrenceIDs.contains("lap.occurrence.6"))
  #expect(engine.snapshot.pendingOccurrenceIDs.contains("lap.occurrence.13"))
  #expect(engine.skipRemainingLaps(trigger: "DRIVER_FINISHING_CURRENT_LAP") == nil)
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

@Test("A lap change after a PA stop lands on the same road, not at the same offset")
func lapChangesFollowTheRoadAcrossUnequalLaps() {
  // The PA stop makes the first lap two occurrences longer: an offset of one
  // first-lap length from index 4 would land on lap.edge.0 of the third lap,
  // and the same offset into the last lap would land in the exit tail.
  var dropping = unequalLapEngine(at: "unequal.occurrence.4")
  #expect(dropping.skipOneLap(trigger: "DRIVER_DROPPED_ONE_LAP") == "unequal.occurrence.8")
  #expect(dropping.snapshot.skippedOccurrenceIDs == (5...7).map { "unequal.occurrence.\($0)" })

  var finishing = unequalLapEngine(at: "unequal.occurrence.4")
  #expect(
    finishing.skipRemainingLaps(trigger: "DRIVER_FINISHING_CURRENT_LAP")
      == "unequal.occurrence.12"
  )
  #expect(finishing.snapshot.journeyPhase == .strictRoute)

  // From the second lap the laps match again.
  var later = unequalLapEngine(at: "unequal.occurrence.7")
  #expect(later.skipOneLap(trigger: "T") == "unequal.occurrence.11")
}

@Test("No lap is dropped from inside a PA stop the next lap does not make")
func lapChangesRefuseFromInsideAStopOnlyThisLapMakes() {
  var engine = unequalLapEngine(at: "unequal.occurrence.2")
  #expect(engine.skipOneLap(trigger: "DRIVER_DROPPED_ONE_LAP") == nil)
  #expect(engine.skipRemainingLaps(trigger: "DRIVER_FINISHING_CURRENT_LAP") == nil)
  #expect(engine.snapshot.currentOccurrenceID == "unequal.occurrence.2")
  #expect(engine.snapshot.skippedOccurrenceIDs.isEmpty)
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

/// Three laps where the first carries a two-occurrence PA stop in place of
/// nothing — lap.edge.0, lap.edge.1, the stop, lap.edge.2, lap.edge.3 — then
/// two plain laps of four and a two-occurrence exit tail. Boundaries at 0, 6,
/// 10 and the tail beginning at 14.
private func unequalLapEngine(at occurrenceID: String) -> NavigationEngine {
  let entities = [
    "lap.edge.0", "lap.edge.1", "pa.stop.0", "pa.stop.1", "lap.edge.2", "lap.edge.3",
    "lap.edge.0", "lap.edge.1", "lap.edge.2", "lap.edge.3",
    "lap.edge.0", "lap.edge.1", "lap.edge.2", "lap.edge.3",
    "tail.edge.0", "tail.edge.1",
  ]
  let plan = RoutePlan(
    id: "test.plan.unequal-laps",
    networkSnapshotID: "test.snapshot.lap",
    entryFacilityID: "test.entrance.lap",
    exitFacilityID: "test.exit.lap",
    recoveryPolicy: .strict,
    actualDistanceKM: 40,
    occurrences: entities.enumerated().map { index, entity in
      RouteOccurrence(
        id: "unequal.occurrence.\(index)",
        index: index,
        kind: entity.hasPrefix("pa.") ? .paVisit : .edge,
        entityID: entity,
        parkingAreaID: entity.hasPrefix("pa.") ? "test.pa" : nil
      )
    }
  )
  var engine = NavigationEngine(
    configuration: NavigationConfiguration(
      routePlan: plan,
      lapBoundaryOccurrenceIDs: [0, 6, 10, 14].map { "unequal.occurrence.\($0)" }
    ),
    initialSnapshot: NavigationSnapshot(journeyPhase: .planning)
  )
  engine.enterStrictRoute(firstOccurrenceID: occurrenceID, trigger: "TEST_ENTER")
  return engine
}
