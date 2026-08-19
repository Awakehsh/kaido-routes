import KaidoDomain
import KaidoNavigation
import KaidoRouting
import Testing

@Test("NavigationSession serializes matcher progress through guidance emission")
func navigationSessionBridgesMatcherToGuidance() async throws {
  let fixture = navigationSessionFixture()
  let session = try NavigationSession(
    navigationConfiguration: fixture.configuration,
    matcherCorridor: fixture.corridor,
    decisionZones: [fixture.decisionZone],
    initialNavigationSnapshot: fixture.initialSnapshot,
    initialMatcherOccurrenceID: "test.occurrence.approach"
  )
  _ = await session.start()

  let first = try await session.observe(
    matcherObservation(longitude: 139.7605, observedAt: 1_000)
  )
  let second = try await session.observe(
    matcherObservation(longitude: 139.7607, observedAt: 2_000)
  )

  #expect(first.matcherEstimate.confidence == .high)
  #expect(first.guidanceProgressState == .resolved)
  #expect(first.guidanceProgressObservation?.distanceToDecisionPointMeters ?? 0 > 30)
  #expect(first.guidancePromptEmission?.promptID == "test.prompt.prepare")
  #expect(first.navigationSnapshot.activeGuidanceFrame?.decisionZoneID == "test.zone")
  #expect(second.guidanceProgressState == .resolved)
  #expect(second.guidancePromptEmission == nil)
  #expect(
    (second.guidanceProgressObservation?.distanceToDecisionPointMeters ?? .infinity)
      < (first.guidanceProgressObservation?.distanceToDecisionPointMeters ?? 0)
  )
  #expect(second.navigationSnapshot.emittedGuidancePromptIDs == ["test.prompt.prepare"])
}

@Test("NavigationSession rejects cross-RoutePlan runtime composition")
func navigationSessionRejectsMismatchedComposition() {
  let fixture = navigationSessionFixture(corridorRoutePlanID: "test.plan.other")

  do {
    _ = try NavigationSession(
      navigationConfiguration: fixture.configuration,
      matcherCorridor: fixture.corridor,
      decisionZones: [fixture.decisionZone],
      initialNavigationSnapshot: fixture.initialSnapshot
    )
    Issue.record("Expected a mismatched RoutePlan composition to fail")
  } catch NavigationSessionConfigurationError.invalid(let issues) {
    #expect(issues.contains("matcher corridor RoutePlan ID does not match"))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Matcher restart cannot rewind actor-owned navigation state")
func navigationSessionRestartDoesNotRewind() async throws {
  let fixture = navigationSessionFixture()
  let session = try NavigationSession(
    navigationConfiguration: fixture.configuration,
    matcherCorridor: fixture.corridor,
    decisionZones: [fixture.decisionZone],
    initialNavigationSnapshot: fixture.initialSnapshot,
    initialMatcherOccurrenceID: "test.occurrence.approach"
  )
  _ = await session.start()
  _ = try await session.observe(
    matcherObservation(longitude: 139.7605, observedAt: 1_000)
  )
  let movement = try await session.observe(
    matcherObservation(longitude: 139.7611, observedAt: 4_000)
  )
  #expect(movement.navigationSnapshot.currentOccurrenceID == "test.occurrence.movement")

  let afterRestart = try await session.restartMatcher(at: "test.occurrence.approach")
  #expect(afterRestart.currentOccurrenceID == "test.occurrence.movement")
  let carPlay = await session.connectCarPlay()
  let phone = await session.disconnectCarPlay()
  #expect(carPlay.presentationSurface == .carPlay)
  #expect(phone.presentationSurface == .iPhone)
  #expect(phone.currentOccurrenceID == "test.occurrence.movement")
}

@Test("A HIGH off-plan matcher commit activates route-first recovery")
func navigationSessionTurnsOffPlanCommitIntoRecovery() async throws {
  let routePlan = RoutePlan(
    id: "test.plan.session-recovery",
    networkSnapshotID: "test.snapshot.session-recovery",
    entryFacilityID: "test.entrance",
    exitFacilityID: "test.exit",
    recoveryPolicy: .safeRejoin,
    occurrences: [
      RouteOccurrence(
        id: "test.occurrence.approach",
        index: 0,
        kind: .edge,
        entityID: "test.edge.approach"
      ),
      RouteOccurrence(
        id: "test.occurrence.planned-movement",
        index: 1,
        kind: .junctionMovement,
        entityID: "test.edge.planned-movement"
      ),
      RouteOccurrence(
        id: "test.occurrence.rejoin",
        index: 2,
        kind: .edge,
        entityID: "test.edge.rejoin"
      ),
    ]
  )
  let corridor = RouteMatcherCorridor(
    id: "test.corridor.session-recovery",
    networkSnapshotID: routePlan.networkSnapshotID,
    routePlanID: routePlan.id,
    edges: [
      RouteMatcherDirectedEdge(
        id: "test.edge.approach",
        coordinates: [
          MatcherCoordinate(latitude: 35.68, longitude: 139.76),
          MatcherCoordinate(latitude: 35.68, longitude: 139.761),
        ],
        successorEdgeIDs: [
          "test.edge.planned-movement",
          "test.edge.wrong-branch",
        ]
      ),
      RouteMatcherDirectedEdge(
        id: "test.edge.planned-movement",
        coordinates: [
          MatcherCoordinate(latitude: 35.68, longitude: 139.761),
          MatcherCoordinate(latitude: 35.68, longitude: 139.762),
        ],
        successorEdgeIDs: ["test.edge.rejoin"]
      ),
      RouteMatcherDirectedEdge(
        id: "test.edge.rejoin",
        coordinates: [
          MatcherCoordinate(latitude: 35.68, longitude: 139.762),
          MatcherCoordinate(latitude: 35.68, longitude: 139.763),
        ]
      ),
      RouteMatcherDirectedEdge(
        id: "test.edge.wrong-branch",
        coordinates: [
          MatcherCoordinate(latitude: 35.68, longitude: 139.761),
          MatcherCoordinate(latitude: 35.681, longitude: 139.761),
        ],
        successorEdgeIDs: ["test.edge.recovery-continuation"]
      ),
      RouteMatcherDirectedEdge(
        id: "test.edge.recovery-continuation",
        coordinates: [
          MatcherCoordinate(latitude: 35.681, longitude: 139.761),
          MatcherCoordinate(latitude: 35.68, longitude: 139.762),
        ],
        successorEdgeIDs: ["test.edge.rejoin"]
      ),
    ],
    occurrences: [
      RouteMatcherOccurrence(
        id: "test.occurrence.approach",
        index: 0,
        directedEdgeID: "test.edge.approach"
      ),
      RouteMatcherOccurrence(
        id: "test.occurrence.planned-movement",
        index: 1,
        directedEdgeID: "test.edge.planned-movement"
      ),
      RouteMatcherOccurrence(
        id: "test.occurrence.rejoin",
        index: 2,
        directedEdgeID: "test.edge.rejoin"
      ),
    ]
  )
  let navigationConfiguration = NavigationConfiguration(
    routePlan: routePlan,
    recoveryCandidates: [
      RecoveryCandidate(
        divergenceOccurrenceID: "test.occurrence.approach",
        triggerDirectedEdgeID: "test.edge.wrong-branch",
        targetOccurrenceID: "test.occurrence.rejoin",
        recoveryOccurrenceIDs: [
          "test.edge.wrong-branch",
          "test.edge.recovery-continuation",
        ],
        isReleased: true,
        staysInAllowedTollDomain: true
      )
    ]
  )
  let initialSnapshot = NavigationSnapshot(
    journeyPhase: .strictRoute,
    activeRoutePlanID: routePlan.id,
    currentOccurrenceID: "test.occurrence.approach",
    locationConfidence: .high
  )
  let session = try NavigationSession(
    navigationConfiguration: navigationConfiguration,
    matcherCorridor: corridor,
    decisionZones: [],
    initialNavigationSnapshot: initialSnapshot,
    initialMatcherOccurrenceID: "test.occurrence.approach"
  )
  _ = await session.start()
  _ = try await session.observe(
    RouteMatcherObservation(
      id: "test.recovery.approach",
      observedAtMilliseconds: 1_000,
      receivedAtMilliseconds: 1_000,
      coordinate: MatcherCoordinate(
        latitude: 35.68,
        longitude: 139.7605
      ),
      horizontalAccuracyMeters: 2,
      courseDegrees: 90,
      speedMetersPerSecond: 15,
      source: .phone
    )
  )
  let deviation = try await session.observe(
    RouteMatcherObservation(
      id: "test.recovery.wrong-branch",
      observedAtMilliseconds: 2_000,
      receivedAtMilliseconds: 2_000,
      coordinate: MatcherCoordinate(
        latitude: 35.6808,
        longitude: 139.761
      ),
      horizontalAccuracyMeters: 2,
      courseDegrees: 0,
      speedMetersPerSecond: 15,
      source: .phone
    )
  )

  #expect(deviation.matcherEstimate.confidence == .high)
  #expect(deviation.matcherEstimate.directedEdgeID == "test.edge.wrong-branch")
  #expect(deviation.matcherEstimate.occurrenceID == nil)
  #expect(deviation.navigationSnapshot.journeyPhase == .routeRecovery)
  #expect(deviation.navigationSnapshot.currentOccurrenceID == "test.occurrence.approach")
  #expect(deviation.navigationSnapshot.activeRoutePlanID == routePlan.id)
  #expect(deviation.navigationSnapshot.recovery.status == .active)
  #expect(
    deviation.navigationSnapshot.recovery.chosenRejoinOccurrenceID
      == "test.occurrence.rejoin"
  )
  #expect(deviation.navigationSnapshot.recovery.destinationRerouteUsed == false)

  let continuing = try await session.observe(
    RouteMatcherObservation(
      id: "test.recovery.continuation",
      observedAtMilliseconds: 3_000,
      receivedAtMilliseconds: 3_000,
      coordinate: MatcherCoordinate(
        latitude: 35.6805,
        longitude: 139.7615
      ),
      horizontalAccuracyMeters: 2,
      courseDegrees: 141,
      speedMetersPerSecond: 15,
      source: .phone
    )
  )
  #expect(
    continuing.matcherEstimate.directedEdgeID
      == "test.edge.recovery-continuation"
  )
  #expect(continuing.navigationSnapshot.recovery.status == .active)

  let rejoined = try await session.observe(
    RouteMatcherObservation(
      id: "test.recovery.rejoin",
      observedAtMilliseconds: 4_000,
      receivedAtMilliseconds: 4_000,
      coordinate: MatcherCoordinate(
        latitude: 35.68,
        longitude: 139.7625
      ),
      horizontalAccuracyMeters: 2,
      courseDegrees: 90,
      speedMetersPerSecond: 15,
      source: .phone
    )
  )
  #expect(rejoined.matcherEstimate.occurrenceID == "test.occurrence.rejoin")
  #expect(rejoined.navigationSnapshot.journeyPhase == .strictRoute)
  #expect(rejoined.navigationSnapshot.recovery.status == .inactive)
  #expect(
    rejoined.navigationSnapshot.skippedOccurrenceIDs
      == ["test.occurrence.planned-movement"]
  )

  let delayedEvidenceSession = try NavigationSession(
    navigationConfiguration: navigationConfiguration,
    matcherCorridor: corridor,
    decisionZones: [],
    initialNavigationSnapshot: initialSnapshot,
    initialMatcherOccurrenceID: "test.occurrence.approach"
  )
  _ = await delayedEvidenceSession.start()
  _ = try await delayedEvidenceSession.observe(
    RouteMatcherObservation(
      id: "test.recovery.delayed-evidence.approach",
      observedAtMilliseconds: 1_000,
      receivedAtMilliseconds: 1_000,
      coordinate: MatcherCoordinate(
        latitude: 35.68,
        longitude: 139.7605
      ),
      horizontalAccuracyMeters: 2,
      courseDegrees: 90,
      speedMetersPerSecond: 15,
      source: .phone
    )
  )
  let delayedEvidence = try await delayedEvidenceSession.observe(
    RouteMatcherObservation(
      id: "test.recovery.delayed-evidence.continuation",
      observedAtMilliseconds: 2_000,
      receivedAtMilliseconds: 2_000,
      coordinate: MatcherCoordinate(
        latitude: 35.6805,
        longitude: 139.7615
      ),
      horizontalAccuracyMeters: 2,
      courseDegrees: 141,
      speedMetersPerSecond: 15,
      source: .phone
    )
  )
  #expect(
    delayedEvidence.matcherEstimate.directedEdgeID
      == "test.edge.recovery-continuation"
  )
  #expect(delayedEvidence.navigationSnapshot.journeyPhase == .routeRecovery)
  #expect(delayedEvidence.navigationSnapshot.recovery.status == .active)
  #expect(
    delayedEvidence.navigationSnapshot.recovery.chosenRejoinOccurrenceID
      == "test.occurrence.rejoin"
  )
}

struct NavigationSessionFixture {
  let configuration: NavigationConfiguration
  let corridor: RouteMatcherCorridor
  let decisionZone: DecisionZoneProgressDefinition
  let initialSnapshot: NavigationSnapshot
}

func navigationSessionFixture(
  corridorRoutePlanID: String = "test.plan.session"
) -> NavigationSessionFixture {
  let routePlan = RoutePlan(
    id: "test.plan.session",
    networkSnapshotID: "test.snapshot.session",
    entryFacilityID: "test.entrance",
    exitFacilityID: "test.exit",
    recoveryPolicy: .strict,
    occurrences: [
      RouteOccurrence(
        id: "test.occurrence.approach",
        index: 0,
        kind: .edge,
        entityID: "test.edge.approach"
      ),
      RouteOccurrence(
        id: "test.occurrence.movement",
        index: 1,
        kind: .junctionMovement,
        entityID: "test.movement"
      ),
    ]
  )
  let approachEdge = RouteMatcherDirectedEdge(
    id: "test.edge.approach",
    coordinates: [
      MatcherCoordinate(latitude: 35.68, longitude: 139.76),
      MatcherCoordinate(latitude: 35.68, longitude: 139.761),
    ],
    successorEdgeIDs: ["test.edge.movement"]
  )
  let movementEdge = RouteMatcherDirectedEdge(
    id: "test.edge.movement",
    coordinates: [
      MatcherCoordinate(latitude: 35.68, longitude: 139.761),
      MatcherCoordinate(latitude: 35.68, longitude: 139.7612),
    ]
  )
  let corridor = RouteMatcherCorridor(
    id: "test.corridor.session",
    networkSnapshotID: routePlan.networkSnapshotID,
    routePlanID: corridorRoutePlanID,
    edges: [approachEdge, movementEdge],
    occurrences: [
      RouteMatcherOccurrence(
        id: "test.occurrence.approach",
        index: 0,
        directedEdgeID: approachEdge.id
      ),
      RouteMatcherOccurrence(
        id: "test.occurrence.movement",
        index: 1,
        directedEdgeID: movementEdge.id
      ),
    ]
  )
  let decisionZone = DecisionZoneProgressDefinition(
    id: "test.zone",
    networkSnapshotID: routePlan.networkSnapshotID,
    routePlanID: routePlan.id,
    movementOccurrenceID: "test.occurrence.movement",
    entryOffsetMeters: 0
  )
  let guidance = ReleasedGuidanceDefinition(
    anchor: GuidanceAnchorDefinition(
      occurrenceID: "test.occurrence.approach",
      anchorID: "PREPARE",
      promptID: "test.prompt.prepare"
    ),
    triggerDistanceMeters: 100,
    frameTemplate: GuidanceFrameTemplate(
      movementOccurrenceID: "test.occurrence.movement",
      decisionZoneID: decisionZone.id,
      stage: .prepare,
      decisionPointNameJapanese: "テストJCT",
      localizedDecisionPointNames: [
        .japanese: "テストJCT",
        .simplifiedChinese: "测试 JCT",
        .english: "Test JCT",
      ],
      maneuver: .keepLeft,
      lanePreparation: .useLeftLanes,
      presentationSource: guidancePresentationSource()
    )
  )
  return NavigationSessionFixture(
    configuration: NavigationConfiguration(
      routePlan: routePlan,
      releasedGuidance: [guidance]
    ),
    corridor: corridor,
    decisionZone: decisionZone,
    initialSnapshot: NavigationSnapshot(
      journeyPhase: .strictRoute,
      activeRoutePlanID: routePlan.id,
      currentOccurrenceID: "test.occurrence.approach",
      locationConfidence: .high
    )
  )
}

private func matcherObservation(
  longitude: Double,
  observedAt: Int
) -> RouteMatcherObservation {
  RouteMatcherObservation(
    observedAtMilliseconds: observedAt,
    receivedAtMilliseconds: observedAt,
    coordinate: MatcherCoordinate(latitude: 35.68, longitude: longitude),
    horizontalAccuracyMeters: 3,
    courseDegrees: 90,
    speedMetersPerSecond: 20,
    source: .phone
  )
}

private func guidancePresentationSource() -> GuidancePresentationSource {
  let sign = "B 湾岸線・横浜方面"
  return GuidancePresentationSource(
    routeShields: ["B"],
    japaneseSignText: sign,
    localizedContent: [
      .japanese: LocalizedGuidanceContent(
        displayText: "左側を進む",
        spokenText: "左側を進んでください",
        spokenForms: ["B": "ビー"],
        preservedJapaneseSignText: sign
      ),
      .simplifiedChinese: LocalizedGuidanceContent(
        displayText: "保持左侧",
        spokenText: "请保持左侧",
        spokenForms: ["B": "B 路线"],
        preservedJapaneseSignText: sign
      ),
      .english: LocalizedGuidanceContent(
        displayText: "Keep left",
        spokenText: "Keep left",
        spokenForms: ["B": "Route B"],
        preservedJapaneseSignText: sign
      ),
    ]
  )
}
