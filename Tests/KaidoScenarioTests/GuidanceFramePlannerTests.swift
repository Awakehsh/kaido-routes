import KaidoDomain
import KaidoNavigation
import Testing

@Test("Released distance anchors advance without replaying or regressing guidance")
func releasedGuidanceAdvancesMonotonically() throws {
  var engine = makeGuidanceEngine()

  #expect(engine.observeGuidanceProgress(progress(distance: 2_500, at: 1_000)) == nil)
  #expect(engine.snapshot.guidancePlanningStatus == .waitingForAnchor)
  #expect(engine.snapshot.activeGuidanceFrame?.stage == .preview)

  let previewEmission = engine.observeGuidanceProgress(progress(distance: 1_900, at: 2_000))
  let preview = try #require(previewEmission)
  #expect(preview.promptID == "test.prompt.preview")
  #expect(engine.snapshot.guidancePlanningStatus == .promptEmitted)
  #expect(engine.snapshot.activeGuidanceFrame?.anchorOccurrenceID == "test.edge.before-jct")
  #expect(engine.snapshot.activeGuidanceFrame?.decisionZoneID == "test.zone.jct")

  #expect(engine.observeGuidanceProgress(progress(distance: 1_800, at: 3_000)) == nil)
  #expect(engine.snapshot.guidancePlanningStatus == .frameUpdated)
  #expect(engine.snapshot.activeGuidanceFrame?.distanceMeters == 1_800)

  let prepareEmission = engine.observeGuidanceProgress(progress(distance: 700, at: 4_000))
  let prepare = try #require(prepareEmission)
  #expect(prepare.promptID == "test.prompt.prepare")
  #expect(engine.snapshot.activeGuidanceFrame?.stage == .prepare)

  let commitEmission = engine.observeGuidanceProgress(progress(distance: 100, at: 5_000))
  let commit = try #require(commitEmission)
  #expect(commit.promptID == "test.prompt.commit")
  #expect(engine.snapshot.activeGuidanceFrame?.stage == .commit)

  #expect(engine.observeGuidanceProgress(progress(distance: 300, at: 6_000)) == nil)
  #expect(engine.snapshot.activeGuidanceFrame?.stage == .commit)
  #expect(
    engine.snapshot.emittedGuidancePromptIDs
      == ["test.prompt.preview", "test.prompt.prepare", "test.prompt.commit"]
  )
}

@Test("A late first fix emits only the most actionable anchor")
func releasedGuidanceSkipsStaleCatchUpPrompts() throws {
  var engine = makeGuidanceEngine()

  let promptEmission = engine.observeGuidanceProgress(progress(distance: 100, at: 1_000))
  let emission = try #require(promptEmission)

  #expect(emission.promptID == "test.prompt.commit")
  #expect(engine.snapshot.activeGuidanceFrame?.stage == .commit)
  #expect(engine.snapshot.emittedGuidancePromptIDs == ["test.prompt.commit"])
}

@Test("Stale or unresolved progress cannot mutate the active guidance frame")
func releasedGuidanceRequiresFreshResolvedEvidence() {
  var engine = makeGuidanceEngine()
  _ = engine.observeGuidanceProgress(progress(distance: 1_900, at: 2_000))

  #expect(engine.observeGuidanceProgress(progress(distance: 700, at: 2_000)) == nil)
  #expect(engine.snapshot.guidancePlanningStatus == .staleObservation)
  #expect(engine.snapshot.activeGuidanceFrame?.distanceMeters == 1_900)

  engine.observeLocation(
    LocationObservation(
      expectedOccurrenceID: "test.edge.before-jct",
      candidateOccurrenceIDs: ["test.edge.before-jct"],
      candidateResolution: .ambiguous,
      reportedConfidence: .high
    )
  )
  #expect(engine.observeGuidanceProgress(progress(distance: 700, at: 3_000)) == nil)
  #expect(engine.snapshot.guidancePlanningStatus == .insufficientRouteEvidence)
  #expect(engine.snapshot.activeGuidanceFrame?.distanceMeters == 1_900)
}

@Test("A released frame must target a forward junction movement")
func releasedGuidanceRejectsInvalidRouteBinding() {
  let routePlan = guidanceRoutePlan()
  var snapshot = guidanceSnapshot()
  snapshot.routeCandidateResolution = .resolved
  let invalid = makeDefinition(
    anchorID: "PREPARE",
    promptID: "test.prompt.invalid",
    stage: .prepare,
    triggerDistanceMeters: 800,
    movementOccurrenceID: "test.edge.before-jct"
  )

  let result = GuidanceFramePlanner.plan(
    snapshot: snapshot,
    routePlan: routePlan,
    definitions: [invalid],
    observation: progress(distance: 700, at: 1_000)
  )

  #expect(result.status == .invalidDefinition)
  #expect(result.frame == nil)
  #expect(result.promptEmission == nil)
}

@Test("Restoring the prompt ledger cannot replay voice and occurrence advance clears the frame")
func releasedGuidanceRestoresWithoutReplay() {
  var engine = makeGuidanceEngine()
  _ = engine.observeGuidanceProgress(progress(distance: 1_900, at: 1_000))

  var restored = NavigationEngine(
    configuration: makeGuidanceConfiguration(),
    initialSnapshot: engine.snapshot
  )
  #expect(
    restored.observeGuidanceProgress(progress(distance: 1_800, at: 2_000)) == nil
  )
  #expect(restored.snapshot.guidancePlanningStatus == .frameUpdated)
  #expect(restored.snapshot.emittedGuidancePromptIDs == ["test.prompt.preview"])

  restored.observeLocation(
    LocationObservation(
      expectedOccurrenceID: "test.movement.at-jct",
      candidateOccurrenceIDs: ["test.movement.at-jct"],
      candidateResolution: .resolved,
      reportedConfidence: .high
    )
  )
  #expect(restored.snapshot.currentOccurrenceID == "test.movement.at-jct")
  #expect(restored.snapshot.activeGuidanceFrame == nil)
  #expect(restored.snapshot.guidancePlanningStatus == .inactive)
}

private func makeGuidanceEngine() -> NavigationEngine {
  var snapshot = guidanceSnapshot()
  snapshot.routeCandidateResolution = .resolved
  return NavigationEngine(
    configuration: makeGuidanceConfiguration(),
    initialSnapshot: snapshot
  )
}

private func makeGuidanceConfiguration() -> NavigationConfiguration {
  NavigationConfiguration(
    routePlan: guidanceRoutePlan(),
    releasedGuidance: [
      makeDefinition(
        anchorID: "PREVIEW",
        promptID: "test.prompt.preview",
        stage: .preview,
        triggerDistanceMeters: 2_000
      ),
      makeDefinition(
        anchorID: "PREPARE",
        promptID: "test.prompt.prepare",
        stage: .prepare,
        triggerDistanceMeters: 800
      ),
      makeDefinition(
        anchorID: "COMMIT",
        promptID: "test.prompt.commit",
        stage: .commit,
        triggerDistanceMeters: 250
      ),
    ]
  )
}

private func guidanceSnapshot() -> NavigationSnapshot {
  NavigationSnapshot(
    journeyPhase: .strictRoute,
    activeRoutePlanID: "test.plan.guidance",
    currentOccurrenceID: "test.edge.before-jct",
    locationConfidence: .high
  )
}

private func guidanceRoutePlan() -> RoutePlan {
  RoutePlan(
    id: "test.plan.guidance",
    networkSnapshotID: "test.snapshot.guidance",
    entryFacilityID: "test.entry",
    exitFacilityID: "test.exit",
    recoveryPolicy: .strict,
    occurrences: [
      RouteOccurrence(
        id: "test.edge.before-jct",
        index: 0,
        kind: .edge,
        entityID: "test.edge.entity"
      ),
      RouteOccurrence(
        id: "test.movement.at-jct",
        index: 1,
        kind: .junctionMovement,
        entityID: "test.movement.entity"
      ),
    ]
  )
}

private func progress(distance: Double, at milliseconds: Int) -> GuidanceProgressObservation {
  GuidanceProgressObservation(
    occurrenceID: "test.edge.before-jct",
    distanceToDecisionPointMeters: distance,
    observedAtMilliseconds: milliseconds
  )
}

private func makeDefinition(
  anchorID: String,
  promptID: String,
  stage: GuidancePromptStage,
  triggerDistanceMeters: Double,
  movementOccurrenceID: String = "test.movement.at-jct"
) -> ReleasedGuidanceDefinition {
  ReleasedGuidanceDefinition(
    anchor: GuidanceAnchorDefinition(
      occurrenceID: "test.edge.before-jct",
      anchorID: anchorID,
      promptID: promptID
    ),
    triggerDistanceMeters: triggerDistanceMeters,
    frameTemplate: GuidanceFrameTemplate(
      movementOccurrenceID: movementOccurrenceID,
      decisionZoneID: "test.zone.jct",
      stage: stage,
      decisionPointNameJapanese: "テストJCT",
      localizedDecisionPointNames: [
        .japanese: "テストJCT",
        .simplifiedChinese: "测试 JCT",
        .english: "Test JCT",
      ],
      maneuver: .keepLeft,
      lanePreparation: .useLeftLanes,
      presentationSource: GuidancePresentationSource(
        routeShields: ["B"],
        japaneseSignText: "B 湾岸線・横浜方面",
        localizedContent: guidanceLocalizedContent()
      )
    )
  )
}

private func guidanceLocalizedContent() -> [KaidoReleaseLocale: LocalizedGuidanceContent] {
  [
    .japanese: LocalizedGuidanceContent(
      displayText: "左側を進み B 湾岸線へ",
      spokenText: "左側を進み、B 湾岸線へ進んでください",
      spokenForms: ["B": "ビー"],
      preservedJapaneseSignText: "B 湾岸線・横浜方面"
    ),
    .simplifiedChinese: LocalizedGuidanceContent(
      displayText: "保持左侧，驶入 B 湾岸线",
      spokenText: "保持左侧，驶入 B 湾岸线",
      spokenForms: ["B": "B 路线"],
      preservedJapaneseSignText: "B 湾岸線・横浜方面"
    ),
    .english: LocalizedGuidanceContent(
      displayText: "Keep left for Route B",
      spokenText: "Keep left for Route B",
      spokenForms: ["B": "Route B"],
      preservedJapaneseSignText: "B 湾岸線・横浜方面"
    ),
  ]
}
