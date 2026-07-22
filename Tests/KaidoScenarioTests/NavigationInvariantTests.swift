import KaidoDomain
import KaidoNavigation
import KaidoRouting
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

@Test("A runtime closure activates a released rejoin to the current route plan")
func runtimeClosureActivatesReleasedRecovery() {
  let routePlan = RoutePlan(
    id: "test.plan.runtime-closure",
    networkSnapshotID: "test.snapshot.navigation",
    entryFacilityID: "test.entry",
    exitFacilityID: "test.exit",
    recoveryPolicy: .safeRejoin,
    occurrences: [
      RouteOccurrence(id: "current", index: 0, kind: .edge, entityID: "test.edge.current"),
      RouteOccurrence(
        id: "blocked",
        index: 1,
        kind: .junctionMovement,
        entityID: "test.movement.blocked"
      ),
      RouteOccurrence(id: "rejoin", index: 2, kind: .edge, entityID: "test.edge.rejoin"),
    ]
  )
  var engine = NavigationEngine(
    configuration: NavigationConfiguration(
      routePlan: routePlan,
      recoveryCandidates: [
        RecoveryCandidate(
          targetOccurrenceID: "blocked",
          recoveryOccurrenceIDs: ["test.recovery.still-hits-closure"],
          isReleased: true,
          staysInAllowedTollDomain: true
        ),
        RecoveryCandidate(
          targetOccurrenceID: "rejoin",
          recoveryOccurrenceIDs: ["test.recovery.bypass"],
          isReleased: true,
          staysInAllowedTollDomain: true
        ),
      ]
    ),
    initialSnapshot: NavigationSnapshot(
      journeyPhase: .strictRoute,
      currentOccurrenceID: "current",
      locationConfidence: .high
    )
  )

  engine.updateRestriction(subjectID: "test.movement.blocked", state: "KNOWN_CLOSED")

  #expect(engine.snapshot.journeyPhase == .routeRecovery)
  #expect(engine.snapshot.recovery.status == .active)
  #expect(engine.snapshot.recovery.objective == "REJOIN_ACTIVE_ROUTE_PLAN")
  #expect(engine.snapshot.recovery.routePlanID == routePlan.id)
  #expect(engine.snapshot.recovery.chosenRejoinOccurrenceID == "rejoin")
  #expect(engine.snapshot.recovery.destinationRerouteUsed == false)
  #expect(engine.snapshot.prohibitedGuidanceActions.contains("ABRUPT_LANE_CHANGE_OR_REVERSAL"))
  #expect(engine.snapshot.requiresRouteEditingWhileMoving == false)
}

@Test("CarPlay disconnect preserves shared navigation progress and prompt ledger")
func carPlayDisconnectPreservesSharedNavigationState() {
  let routePlan = RoutePlan(
    id: "test.plan.carplay-handoff",
    networkSnapshotID: "test.snapshot.navigation",
    entryFacilityID: "test.entry",
    exitFacilityID: "test.exit",
    recoveryPolicy: .safeRejoin,
    occurrences: [
      RouteOccurrence(id: "first", index: 0, kind: .edge, entityID: "test.edge.first"),
      RouteOccurrence(id: "second", index: 1, kind: .edge, entityID: "test.edge.second"),
    ]
  )
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

  engine.start()
  engine.reachGuidanceAnchor(occurrenceID: "first", anchorID: "PREPARE")
  engine.connectCarPlay()
  engine.observeLocation(
    LocationObservation(
      expectedOccurrenceID: "second",
      reportedConfidence: .high
    ))
  engine.disconnectCarPlay()

  #expect(engine.snapshot.presentationSurface == .iPhone)
  #expect(engine.snapshot.carPlayConnectionState == .disconnected)
  #expect(engine.snapshot.activeRoutePlanID == routePlan.id)
  #expect(engine.snapshot.currentOccurrenceID == "second")
  #expect(engine.snapshot.journeyPhase == .strictRoute)
  #expect(engine.snapshot.emittedGuidancePromptIDs == ["prompt.first.prepare"])
  #expect(engine.snapshot.requiresPhoneTouchWhileMoving == false)

  engine.reachGuidanceAnchor(occurrenceID: "second", anchorID: "PREPARE")
  #expect(
    engine.snapshot.emittedGuidancePromptIDs
      == ["prompt.first.prepare", "prompt.second.prepare"])
}

private func testRoutePlan() -> RoutePlan {
  RoutePlan(
    id: "test.plan",
    networkSnapshotID: "test.snapshot.navigation",
    entryFacilityID: "test.entry",
    exitFacilityID: "test.exit",
    recoveryPolicy: .safeRejoin,
    occurrences: [
      RouteOccurrence(id: "first", index: 0, kind: .edge, entityID: "test.edge.first"),
      RouteOccurrence(id: "second", index: 1, kind: .edge, entityID: "test.edge.second"),
    ]
  )
}
