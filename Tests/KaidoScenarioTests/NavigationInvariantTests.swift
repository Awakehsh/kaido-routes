import KaidoDomain
import KaidoNavigation
import Testing

@Test("Occurrence progress never moves backward")
func occurrenceProgressNeverMovesBackward() {
  let routePlan = testRoutePlan()
  let initial = NavigationSnapshot(
    journeyPhase: .strictRoute,
    activeRoutePlanID: routePlan.id,
    currentOccurrenceID: "second",
    locationConfidence: .high
  )
  var engine = NavigationEngine(
    configuration: NavigationConfiguration(routePlan: routePlan),
    initialSnapshot: initial
  )

  engine.observeLocation(
    LocationObservation(
      expectedOccurrenceID: "first",
      reportedConfidence: .high
    ))

  #expect(engine.snapshot.currentOccurrenceID == "second")
  #expect(engine.snapshot.currentOccurrenceIndex == 1)
}

@Test("Entry transition requires ordered edge continuity")
func entryTransitionRequiresOrderedContinuity() {
  let routePlan = testRoutePlan()
  let transition = EntryTransition(
    facilityID: "test.entry",
    directedEdgeIDs: ["surface", "ramp", "merge"],
    firstRouteOccurrenceID: "first"
  )
  var engine = NavigationEngine(
    configuration: NavigationConfiguration(
      routePlan: routePlan,
      entryTransition: transition
    ),
    initialSnapshot: NavigationSnapshot(journeyPhase: .approachToEntry)
  )

  engine.observeLocation(
    LocationObservation(
      directedEdgeID: "merge",
      reportedConfidence: .high,
      headingMatches: true,
      forwardContinuity: true,
      reachableOccurrenceIDs: ["first"]
    ))
  #expect(engine.snapshot.journeyPhase == .approachToEntry)

  engine.observeLocation(
    LocationObservation(
      directedEdgeID: "surface",
      reportedConfidence: .high,
      headingMatches: true
    ))
  engine.observeLocation(
    LocationObservation(
      directedEdgeID: "ramp",
      reportedConfidence: .high,
      headingMatches: true,
      forwardContinuity: true
    ))
  engine.observeLocation(
    LocationObservation(
      directedEdgeID: "merge",
      reportedConfidence: .high,
      headingMatches: true,
      forwardContinuity: true,
      reachableOccurrenceIDs: ["first"]
    ))

  #expect(engine.snapshot.journeyPhase == .strictRoute)
  #expect(engine.snapshot.currentOccurrenceID == "first")
}

private func testRoutePlan() -> RoutePlan {
  RoutePlan(
    id: "test.plan",
    entryFacilityID: "test.entry",
    exitFacilityID: "test.exit",
    recoveryPolicy: .safeRejoin,
    occurrences: [
      RouteOccurrence(id: "first", index: 0, kind: .edge, entityID: "test.edge.first"),
      RouteOccurrence(id: "second", index: 1, kind: .edge, entityID: "test.edge.second"),
    ]
  )
}
