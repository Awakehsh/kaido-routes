import KaidoDomain
import KaidoPresentation
import Testing

@Test("Phone, CarPlay, and voice project one navigation truth with independent languages")
func presentationSurfacesShareNavigationTruth() throws {
  var snapshot = NavigationSnapshot(
    journeyPhase: .strictRoute,
    activeRoutePlanID: "test.plan.c1",
    currentOccurrenceID: "test.occurrence.c1.4",
    locationConfidence: .high
  )
  snapshot.presentationSurface = .carPlay
  snapshot.carPlayConnectionState = .connected

  let projection = try NavigationPresentationProjector.project(
    makePresentationRequest(
      snapshot: snapshot,
      nextMovementOccurrenceID: "test.occurrence.edobashi",
      interfaceLocale: .simplifiedChinese,
      voiceLocale: .english
    )
  )

  #expect(projection.interfaceLocale == .simplifiedChinese)
  #expect(projection.voice.locale == .english)
  #expect(projection.voice.spokenText == "Keep left for Route B toward Yokohama")
  #expect(projection.voice.promptID == "test.prompt.prepare")
  #expect(projection.voice.stage == .prepare)
  #expect(projection.voice.distanceMeters == 800)
  #expect(projection.voice.maneuver == .keepLeft)
  #expect(!projection.voice.shouldSpeak)
  #expect(projection.iPhone.currentOccurrenceID == projection.carPlay.currentOccurrenceID)
  #expect(
    projection.iPhone.nextMovementOccurrenceID
      == projection.carPlay.nextMovementOccurrenceID
  )
  #expect(projection.iPhone.japaneseSignText == "B 湾岸線・横浜方面")
  #expect(projection.carPlay.japaneseSignText == "B 湾岸線・横浜方面")
  #expect(projection.iPhone.localizedDisplayText == "保持左侧，跟随 B 湾岸线・横滨方向")
  #expect(projection.iPhone.decisionPointNameJapanese == "辰巳JCT")
  #expect(projection.iPhone.localizedDecisionPointName == "辰巳 JCT")
  #expect(projection.iPhone.guidanceAnchorOccurrenceID == "test.occurrence.c1.4")
  #expect(projection.iPhone.decisionZoneID == "test.zone.tatsumi")
  #expect(projection.iPhone.lanePreparation == .useLeftLanes)
  #expect(!projection.iPhone.isPrimarySurface)
  #expect(projection.carPlay.isPrimarySurface)
}

@Test("Voice speaks only for a matching one-shot prompt emission")
func voiceRequiresMatchingPromptEmission() throws {
  let frame = validGuidanceFrame()
  let emission = GuidancePromptEmission(
    promptID: frame.promptID,
    anchorID: frame.anchorID,
    anchorOccurrenceID: frame.anchorOccurrenceID
  )
  var snapshot = NavigationSnapshot()
  snapshot.emittedGuidancePromptIDs = [frame.promptID]
  snapshot.lastGuidancePromptID = frame.promptID
  let projection = try NavigationPresentationProjector.project(
    makePresentationRequest(
      snapshot: snapshot,
      guidanceFrame: frame,
      promptEmission: emission
    )
  )
  #expect(projection.voice.shouldSpeak)

  #expect(throws: NavigationPresentationProjectionError.promptEmissionMismatch) {
    try NavigationPresentationProjector.project(
      makePresentationRequest(
        snapshot: snapshot,
        guidanceFrame: frame,
        promptEmission: GuidancePromptEmission(
          promptID: "test.prompt.other",
          anchorID: frame.anchorID,
          anchorOccurrenceID: frame.anchorOccurrenceID
        )
      )
    )
  }
}

@Test("Guidance frame rejects missing identity, invalid distance, and localized JCT drift")
func guidanceFrameFailsClosed() {
  let snapshot = NavigationSnapshot()
  #expect(throws: NavigationPresentationProjectionError.missingPromptID) {
    try NavigationPresentationProjector.project(
      makePresentationRequest(
        snapshot: snapshot,
        guidanceFrame: validGuidanceFrame(promptID: "")
      )
    )
  }
  #expect(throws: NavigationPresentationProjectionError.invalidDistanceMeters) {
    try NavigationPresentationProjector.project(
      makePresentationRequest(
        snapshot: snapshot,
        guidanceFrame: validGuidanceFrame(distanceMeters: .infinity)
      )
    )
  }
  #expect(
    throws: NavigationPresentationProjectionError.decisionPointJapaneseNameMismatch
  ) {
    try NavigationPresentationProjector.project(
      makePresentationRequest(
        snapshot: snapshot,
        guidanceFrame: validGuidanceFrame(
          localizedDecisionPointNames: [
            .japanese: "translated replacement",
            .simplifiedChinese: "辰巳 JCT",
            .english: "Tatsumi JCT",
          ]
        )
      )
    )
  }
}

@Test("Every release locale must preserve one exact Japanese sign target")
func presentationRequiresCompleteSignPreservingLocales() {
  let snapshot = NavigationSnapshot()
  var missingEnglish = validLocalizedContent()
  missingEnglish.removeValue(forKey: .english)
  let missingRequest = makePresentationRequest(
    snapshot: snapshot,
    localizedContent: missingEnglish
  )
  #expect(
    throws: NavigationPresentationProjectionError.missingLocale(.english)
  ) {
    try NavigationPresentationProjector.project(missingRequest)
  }

  var mismatched = validLocalizedContent()
  mismatched[.simplifiedChinese] = LocalizedGuidanceContent(
    displayText: "保持左侧",
    spokenText: "保持左侧",
    spokenForms: ["B": "B 路线"],
    preservedJapaneseSignText: "translated replacement"
  )
  let mismatchRequest = makePresentationRequest(
    snapshot: snapshot,
    localizedContent: mismatched
  )
  #expect(
    throws: NavigationPresentationProjectionError.japaneseSignTextMismatch(
      .simplifiedChinese
    )
  ) {
    try NavigationPresentationProjector.project(mismatchRequest)
  }
}

@Test("Low-confidence and ambiguous positions never render as measured")
func presentationDistinguishesEstimatedAndUnresolvedPosition() throws {
  let lowSnapshot = NavigationSnapshot(locationConfidence: .low)
  let estimated = try NavigationPresentationProjector.project(
    makePresentationRequest(snapshot: lowSnapshot)
  )
  #expect(estimated.iPhone.marker == .estimated)

  var ambiguousSnapshot = NavigationSnapshot(locationConfidence: .high)
  ambiguousSnapshot.routeCandidateResolution = .ambiguous
  let unresolved = try NavigationPresentationProjector.project(
    makePresentationRequest(snapshot: ambiguousSnapshot)
  )
  #expect(unresolved.iPhone.marker == .unresolved)
}

@Test("Only confirmed passage evidence may use a positive open-road color")
func presentationKeepsUnconfirmedRoadStatusNeutral() {
  let knownClosed = NavigationPresentationProjector.passagePresentation(for: .knownClosed)
  let planned = NavigationPresentationProjector.passagePresentation(for: .plannedConflict)
  let unconfirmed = NavigationPresentationProjector.passagePresentation(
    for: .noKnownConflictRealtimeUnconfirmed
  )
  let confirmed = NavigationPresentationProjector.passagePresentation(
    for: .realtimeConfirmedPassable
  )

  #expect(knownClosed.tone == .blocked)
  #expect(planned.tone == .warning)
  #expect(unconfirmed.tone == .unconfirmed)
  #expect(!knownClosed.usesPositiveOpenColor)
  #expect(!planned.usesPositiveOpenColor)
  #expect(!unconfirmed.usesPositiveOpenColor)
  #expect(confirmed.tone == .confirmedPassable)
  #expect(confirmed.usesPositiveOpenColor)
}

@Test("Route editing is parked-only and never requires phone touch while moving")
func presentationLocksEditingDuringAnActiveDrive() throws {
  let parkedPlanning = try NavigationPresentationProjector.project(
    makePresentationRequest(snapshot: NavigationSnapshot())
  )
  #expect(parkedPlanning.iPhone.routeEditingAvailability == .availableWhileParked)

  let parkedActive = try NavigationPresentationProjector.project(
    makePresentationRequest(
      snapshot: NavigationSnapshot(journeyPhase: .strictRoute)
    )
  )
  #expect(parkedActive.iPhone.routeEditingAvailability == .lockedForActiveDrive)

  let movingDecisionZone = try NavigationPresentationProjector.project(
    makePresentationRequest(
      snapshot: NavigationSnapshot(journeyPhase: .strictRoute),
      drivingContext: PresentationDrivingContext(
        isVehicleMoving: true,
        isInsideDecisionZone: true
      )
    )
  )
  #expect(
    movingDecisionZone.iPhone.routeEditingAvailability == .unavailableInDecisionZone
  )
  #expect(
    movingDecisionZone.carPlay.routeEditingAvailability == .unavailableInDecisionZone
  )
  #expect(!movingDecisionZone.iPhone.requiresPhoneTouchWhileMoving)
  #expect(!movingDecisionZone.carPlay.requiresPhoneTouchWhileMoving)
}

@Test("Finish drive names the selected exit before branch guidance on both surfaces")
func presentationNamesFinishExitFirst() throws {
  var snapshot = NavigationSnapshot(journeyPhase: .strictRoute)
  snapshot.finishConfirmationExitFacilityID = "test.exit.shibakoen"
  let facilityNames = [
    "test.exit.shibakoen": LocalizedFacilityName(
      values: [
        .japanese: "芝公園出口",
        .simplifiedChinese: "芝公园出口",
        .english: "Shibakoen Exit",
      ]
    )
  ]
  let projection = try NavigationPresentationProjector.project(
    makePresentationRequest(
      snapshot: snapshot,
      interfaceLocale: .simplifiedChinese,
      facilityNames: facilityNames
    )
  )

  #expect(projection.iPhone.finishDrive?.exitFacilityID == "test.exit.shibakoen")
  #expect(projection.iPhone.finishDrive?.localizedExitName == "芝公园出口")
  #expect(projection.carPlay.finishDrive == projection.iPhone.finishDrive)
  #expect(projection.voice.spokenText == "B 湾岸線、横浜方面へ")
  #expect(projection.iPhone.finishDrive?.announcementPriority == .beforeBranchGuidance)
}

@Test("Finish drive fails closed when the selected locale has no exit name")
func presentationRejectsMissingFinishExitName() {
  var snapshot = NavigationSnapshot(journeyPhase: .strictRoute)
  snapshot.finishConfirmationExitFacilityID = "test.exit.shibakoen"
  let request = makePresentationRequest(
    snapshot: snapshot,
    facilityNames: [
      "test.exit.shibakoen": LocalizedFacilityName(
        values: [.japanese: "芝公園出口"]
      )
    ]
  )
  #expect(
    throws: NavigationPresentationProjectionError.missingExitName(
      "test.exit.shibakoen",
      .simplifiedChinese
    )
  ) {
    try NavigationPresentationProjector.project(request)
  }
}

@Test("Presentation rejects CarPlay ownership that contradicts connection state")
func presentationRejectsInconsistentSurfaceState() {
  var snapshot = NavigationSnapshot()
  snapshot.presentationSurface = .carPlay
  snapshot.carPlayConnectionState = .disconnected
  #expect(throws: NavigationPresentationProjectionError.inconsistentSurfaceState) {
    try NavigationPresentationProjector.project(
      makePresentationRequest(snapshot: snapshot)
    )
  }
}

@Test("A released junction view projects identically to phone and CarPlay")
func presentationProjectsReviewedJunctionView() throws {
  let junctionView = validJunctionView()
  let projection = try NavigationPresentationProjector.project(
    makePresentationRequest(
      snapshot: NavigationSnapshot(),
      networkSnapshotID: junctionView.networkSnapshotID,
      guidanceFrame: validGuidanceFrame(junctionView: junctionView)
    )
  )

  #expect(projection.iPhone.junctionView == junctionView)
  #expect(projection.carPlay.junctionView == junctionView)
  #expect(projection.carPlay.junctionView?.laneLayout.preferredLaneIndices == [0])
  #expect(
    projection.carPlay.junctionView?.paths.first(where: { $0.role == .selected })?.id
      == "test.path.selected"
  )
}

@Test("Junction views fail closed on snapshot, evidence, and sign drift")
func presentationRejectsInvalidJunctionView() {
  let valid = validJunctionView()
  #expect(
    throws: NavigationPresentationProjectionError.junctionViewNetworkSnapshotMismatch
  ) {
    try NavigationPresentationProjector.project(
      makePresentationRequest(
        snapshot: NavigationSnapshot(),
        networkSnapshotID: "test.snapshot.other",
        guidanceFrame: validGuidanceFrame(junctionView: valid)
      )
    )
  }

  let unreleased = validJunctionView(evidenceState: .officialChecked)
  #expect(
    throws: NavigationPresentationProjectionError.invalidJunctionView(
      .unreleasedEvidence
    )
  ) {
    try NavigationPresentationProjector.project(
      makePresentationRequest(
        snapshot: NavigationSnapshot(),
        networkSnapshotID: unreleased.networkSnapshotID,
        guidanceFrame: validGuidanceFrame(junctionView: unreleased)
      )
    )
  }

  let changedSign = validJunctionView(japaneseSignText: "translated replacement")
  #expect(
    throws: NavigationPresentationProjectionError.junctionViewJapaneseSignMismatch
  ) {
    try NavigationPresentationProjector.project(
      makePresentationRequest(
        snapshot: NavigationSnapshot(),
        networkSnapshotID: changedSign.networkSnapshotID,
        guidanceFrame: validGuidanceFrame(junctionView: changedSign)
      )
    )
  }

  let disconnected = validJunctionView(selectedPathStartX: 0.4)
  #expect(
    throws: NavigationPresentationProjectionError.invalidJunctionView(
      .disconnectedPathGeometry("test.path.selected")
    )
  ) {
    try NavigationPresentationProjector.project(
      makePresentationRequest(
        snapshot: NavigationSnapshot(),
        networkSnapshotID: disconnected.networkSnapshotID,
        guidanceFrame: validGuidanceFrame(junctionView: disconnected)
      )
    )
  }
}

@Test("Pre-drive review keeps actual distance, tariff distance, toll, and road evidence separate")
func preDriveReviewKeepsMetricsSeparate() throws {
  let review = try PreDriveReviewProjector.project(
    PreDriveReviewRequest(
      actualDistanceKM: 72.4,
      tariffDistanceKM: 14.2,
      estimatedAmountYen: 630,
      tollEvidenceStatus: .estimated,
      passageEvidence: .noKnownConflictRealtimeUnconfirmed
    )
  )

  #expect(review.actualDistanceKM == 72.4)
  #expect(review.tariffDistanceKM == 14.2)
  #expect(review.estimatedAmountYen == 630)
  #expect(review.tollEvidenceStatus == .estimated)
  #expect(review.passage.tone == .unconfirmed)
  #expect(!review.passage.usesPositiveOpenColor)
}

@Test("Pre-drive review rejects impossible scalar values")
func preDriveReviewRejectsInvalidScalars() {
  #expect(throws: PreDriveReviewProjectionError.invalidActualDistance) {
    try PreDriveReviewProjector.project(
      PreDriveReviewRequest(
        actualDistanceKM: 0,
        tariffDistanceKM: 14.2,
        estimatedAmountYen: 630,
        tollEvidenceStatus: .estimated,
        passageEvidence: .noKnownConflictRealtimeUnconfirmed
      )
    )
  }
  #expect(throws: PreDriveReviewProjectionError.invalidTariffDistance) {
    try PreDriveReviewProjector.project(
      PreDriveReviewRequest(
        actualDistanceKM: 72.4,
        tariffDistanceKM: -.infinity,
        estimatedAmountYen: nil,
        tollEvidenceStatus: .unknown,
        passageEvidence: .knownClosed
      )
    )
  }
}

private func makePresentationRequest(
  snapshot: NavigationSnapshot,
  networkSnapshotID: String? = nil,
  nextMovementOccurrenceID: String? = nil,
  interfaceLocale: KaidoReleaseLocale = .simplifiedChinese,
  voiceLocale: KaidoReleaseLocale = .japanese,
  localizedContent: [KaidoReleaseLocale: LocalizedGuidanceContent] =
    validLocalizedContent(),
  drivingContext: PresentationDrivingContext = PresentationDrivingContext(
    isVehicleMoving: false,
    isInsideDecisionZone: false
  ),
  facilityNames: [String: LocalizedFacilityName] = [:],
  guidanceFrame: GuidanceFrame? = nil,
  promptEmission: GuidancePromptEmission? = nil
) -> NavigationPresentationRequest {
  NavigationPresentationRequest(
    snapshot: snapshot,
    networkSnapshotID: networkSnapshotID,
    guidanceFrame: guidanceFrame
      ?? validGuidanceFrame(
        anchorOccurrenceID: snapshot.currentOccurrenceID ?? "test.occurrence.anchor",
        movementOccurrenceID: nextMovementOccurrenceID ?? "test.occurrence.next",
        localizedContent: localizedContent
      ),
    promptEmission: promptEmission,
    languages: NavigationLanguageSelection(
      interfaceLocale: interfaceLocale,
      guidanceVoiceLocale: voiceLocale
    ),
    passageEvidence: .noKnownConflictRealtimeUnconfirmed,
    drivingContext: drivingContext,
    facilityNames: facilityNames
  )
}

private func validGuidanceFrame(
  promptID: String = "test.prompt.prepare",
  anchorOccurrenceID: String = "test.occurrence.anchor",
  movementOccurrenceID: String = "test.occurrence.next",
  distanceMeters: Double = 800,
  localizedDecisionPointNames: [KaidoReleaseLocale: String] = [
    .japanese: "辰巳JCT",
    .simplifiedChinese: "辰巳 JCT",
    .english: "Tatsumi JCT",
  ],
  localizedContent: [KaidoReleaseLocale: LocalizedGuidanceContent] =
    validLocalizedContent(),
  junctionView: JunctionViewDefinition? = nil
) -> GuidanceFrame {
  GuidanceFrame(
    promptID: promptID,
    anchorID: "PREPARE",
    anchorOccurrenceID: anchorOccurrenceID,
    movementOccurrenceID: movementOccurrenceID,
    decisionZoneID: "test.zone.tatsumi",
    stage: .prepare,
    distanceMeters: distanceMeters,
    decisionPointNameJapanese: "辰巳JCT",
    localizedDecisionPointNames: localizedDecisionPointNames,
    maneuver: .keepLeft,
    lanePreparation: .useLeftLanes,
    presentationSource: GuidancePresentationSource(
      routeShields: ["B"],
      japaneseSignText: "B 湾岸線・横浜方面",
      localizedContent: localizedContent,
      junctionView: junctionView
    )
  )
}

private func validJunctionView(
  evidenceState: JunctionViewEvidenceState = .released,
  japaneseSignText: String = "B 湾岸線・横浜方面",
  selectedPathStartX: Double = 0.5
) -> JunctionViewDefinition {
  JunctionViewDefinition(
    id: "test.junction-view",
    networkSnapshotID: "test.snapshot.junction-view",
    movementOccurrenceID: "test.occurrence.next",
    paths: [
      JunctionViewPath(
        id: "test.path.approach",
        role: .approach,
        points: [
          JunctionViewPoint(x: 0.5, y: 1),
          JunctionViewPoint(x: 0.5, y: 0.5),
        ]
      ),
      JunctionViewPath(
        id: "test.path.selected",
        role: .selected,
        points: [
          JunctionViewPoint(x: selectedPathStartX, y: 0.5),
          JunctionViewPoint(x: 0.2, y: 0),
        ]
      ),
      JunctionViewPath(
        id: "test.path.alternative",
        role: .alternative,
        points: [
          JunctionViewPoint(x: 0.5, y: 0.5),
          JunctionViewPoint(x: 0.8, y: 0),
        ]
      ),
    ],
    laneLayout: JunctionViewLaneLayout(
      laneCount: 3,
      allowedLaneIndices: [0, 1],
      preferredLaneIndices: [0]
    ),
    japaneseSignText: japaneseSignText,
    routeShields: ["B"],
    evidence: JunctionViewEvidence(
      state: evidenceState,
      checkedAt: "2026-07-23",
      sourceReferenceIDs: ["test.source.junction"]
    )
  )
}

private func validLocalizedContent() -> [KaidoReleaseLocale: LocalizedGuidanceContent] {
  [
    .japanese: LocalizedGuidanceContent(
      displayText: "左側を進み、B 湾岸線・横浜方面へ",
      spokenText: "B 湾岸線、横浜方面へ",
      spokenForms: ["B": "ビー", "湾岸線": "わんがんせん"],
      preservedJapaneseSignText: "B 湾岸線・横浜方面"
    ),
    .simplifiedChinese: LocalizedGuidanceContent(
      displayText: "保持左侧，跟随 B 湾岸线・横滨方向",
      spokenText: "保持左侧，跟随 B 湾岸线，横滨方向",
      spokenForms: ["B": "B 路线", "湾岸線": "湾岸线"],
      preservedJapaneseSignText: "B 湾岸線・横浜方面"
    ),
    .english: LocalizedGuidanceContent(
      displayText: "Keep left for Route B toward Yokohama",
      spokenText: "Keep left for Route B toward Yokohama",
      spokenForms: ["B": "Route B", "湾岸線": "Bayshore Route"],
      preservedJapaneseSignText: "B 湾岸線・横浜方面"
    ),
  ]
}
