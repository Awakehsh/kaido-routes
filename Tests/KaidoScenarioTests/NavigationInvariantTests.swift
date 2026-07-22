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

@Test("Post-tunnel reacquisition restarts when the evidence window is too old")
func postTunnelReacquisitionRequiresATimelyWindow() {
  let routePlan = testRoutePlan()
  var engine = NavigationEngine(
    configuration: NavigationConfiguration(routePlan: routePlan),
    initialSnapshot: NavigationSnapshot(
      journeyPhase: .strictRoute,
      currentOccurrenceID: "first",
      locationConfidence: .high
    )
  )

  engine.enterTunnel()
  engine.observeLocation(
    LocationObservation(
      observedAtMilliseconds: 1_000,
      horizontalAccuracyMeters: -1
    ))
  engine.exitTunnel()
  engine.observeLocation(
    LocationObservation(
      candidateOccurrenceIDs: ["second"],
      observedAtMilliseconds: 2_000,
      reportedConfidence: .high
    ))
  engine.observeLocation(
    LocationObservation(
      candidateOccurrenceIDs: ["second"],
      observedAtMilliseconds: 8_000,
      reportedConfidence: .high
    ))

  #expect(engine.snapshot.signalReacquisitionStatus == .pending)
  #expect(engine.snapshot.currentOccurrenceID == "first")

  engine.observeLocation(
    LocationObservation(
      candidateOccurrenceIDs: ["second"],
      observedAtMilliseconds: 9_000,
      reportedConfidence: .high
    ))

  #expect(engine.snapshot.signalReacquisitionStatus == .confirmed)
  #expect(engine.snapshot.currentOccurrenceID == "second")
}

@Test("Resolved route-candidate evidence must identify exactly one occurrence")
func resolvedCandidateEvidenceRequiresOneOccurrence() {
  let routePlan = testRoutePlan()
  var engine = NavigationEngine(
    configuration: NavigationConfiguration(routePlan: routePlan),
    initialSnapshot: NavigationSnapshot(
      journeyPhase: .strictRoute,
      currentOccurrenceID: "first",
      locationConfidence: .high
    )
  )

  engine.observeLocation(
    LocationObservation(
      matchedOccurrenceID: "second",
      candidateOccurrenceIDs: ["first", "second"],
      candidateResolution: .resolved,
      observedAtMilliseconds: 1_000,
      reportedConfidence: .high
    ))

  #expect(engine.snapshot.currentOccurrenceID == "first")
  #expect(engine.snapshot.markerStyle == "UNRESOLVED")
  #expect(engine.snapshot.ambiguityReason == "ROUTE_CANDIDATE_EVIDENCE_INCONSISTENT")

  engine.observeLocation(
    LocationObservation(
      matchedOccurrenceID: "second",
      candidateOccurrenceIDs: ["second"],
      candidateResolution: .resolved,
      observedAtMilliseconds: 2_000,
      reportedConfidence: .high
    ))

  #expect(engine.snapshot.currentOccurrenceID == "second")
  #expect(engine.snapshot.ambiguityReason == nil)
}

@Test("Guidance prompts emit once for each occurrence anchor")
func guidancePromptsEmitOncePerOccurrenceAnchor() {
  let routePlan = testRoutePlan()
  var engine = NavigationEngine(
    configuration: NavigationConfiguration(
      routePlan: routePlan,
      guidanceAnchors: [
        GuidanceAnchorDefinition(
          occurrenceID: "first",
          anchorID: "PREPARE",
          promptID: "prompt.first.prepare"
        ),
        GuidanceAnchorDefinition(
          occurrenceID: "second",
          anchorID: "PREPARE",
          promptID: "prompt.second.prepare"
        ),
      ]
    ),
    initialSnapshot: NavigationSnapshot(
      journeyPhase: .strictRoute,
      currentOccurrenceID: "first",
      locationConfidence: .high
    )
  )

  engine.reachGuidanceAnchor(occurrenceID: "first", anchorID: "PREPARE")
  engine.reachGuidanceAnchor(occurrenceID: "first", anchorID: "PREPARE")
  #expect(engine.snapshot.guidanceAnchorStatus == .duplicateSuppressed)
  #expect(engine.snapshot.emittedGuidancePromptIDs == ["prompt.first.prepare"])

  engine.observeLocation(
    LocationObservation(
      expectedOccurrenceID: "second",
      reportedConfidence: .high
    ))
  engine.reachGuidanceAnchor(occurrenceID: "first", anchorID: "PREPARE")
  #expect(engine.snapshot.guidanceAnchorStatus == .notCurrentOccurrence)

  engine.reachGuidanceAnchor(occurrenceID: "second", anchorID: "PREPARE")
  #expect(engine.snapshot.guidanceAnchorStatus == .emitted)
  #expect(
    engine.snapshot.emittedGuidancePromptIDs == [
      "prompt.first.prepare", "prompt.second.prepare",
    ])

  var restoredSnapshot = engine.snapshot
  restoredSnapshot.currentOccurrenceID = "second"
  var restoredEngine = NavigationEngine(
    configuration: NavigationConfiguration(
      routePlan: routePlan,
      guidanceAnchors: [
        GuidanceAnchorDefinition(
          occurrenceID: "second",
          anchorID: "PREPARE",
          promptID: "prompt.second.prepare"
        )
      ]
    ),
    initialSnapshot: restoredSnapshot
  )
  restoredEngine.reachGuidanceAnchor(occurrenceID: "second", anchorID: "PREPARE")
  #expect(restoredEngine.snapshot.guidanceAnchorStatus == .duplicateSuppressed)
  #expect(restoredEngine.snapshot.emittedGuidancePromptIDs.count == 2)
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
