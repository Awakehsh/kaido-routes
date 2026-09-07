import Foundation
import KaidoAppleAdapters
import KaidoDomain
import KaidoNavigation
import KaidoPresentation
import KaidoRouting
import Testing

@MainActor
private final class RecoverySpeechOutput: GuidanceSpeechOutput {
  var eventHandler: ((GuidanceSpeechOutputEvent) -> Void)?
  var fail = false
  var emitsStart = true
  var recoveryAllowed = false
  var speakAttempts = 0
  var commands: [GuidanceSpeechCommand] = []
  func speak(_ command: GuidanceSpeechCommand) throws {
    speakAttempts += 1
    if fail { throw GuidanceSpeechOutputError.audioSessionActivationFailed }
    commands.append(command)
    if emitsStart { eventHandler?(.didStart(command.identity)) }
  }
  func stop() {}
  func recoverAfterInterruption() throws -> Bool {
    guard recoveryAllowed else { return false }
    eventHandler?(.interruptionEnded)
    return true
  }
  func finish(_ identity: GuidanceSpeechIdentity) { eventHandler?(.didFinish(identity)) }
}

@MainActor @Test func speechRecoveryMissingCompletionReleasesLaterSurfaceStep() throws {
  let output = RecoverySpeechOutput()
  var now: TimeInterval = 0
  let coordinator = try GuidanceSpeechCoordinator(
    expectedRoutePlanID: "test.plan.speech", output: output, now: { now })
  _ = coordinator.submitProviderSurface(surfaceSpeechCommand(promptID: "surface.0"))
  for index in 1...100 {
    #expect(
      coordinator.submitProviderSurface(surfaceSpeechCommand(promptID: "surface.\(index)"))
        == .suppressed(.notAuthorized))
  }
  #expect(output.commands.count == 1)
  now = 31
  let fresh = surfaceSpeechCommand(promptID: "surface.fresh")
  #expect(coordinator.submitProviderSurface(fresh) == .speaking(fresh.identity))
  #expect(output.commands.count == 2)
  #expect(!coordinator.completedIdentities.contains(output.commands[0].identity))
}

@MainActor @Test func speechRecoveryRetriesUnstartedSurfaceAndExpresswayPrompts() throws {
  var now: TimeInterval = 0
  let surfaceOutput = RecoverySpeechOutput()
  surfaceOutput.fail = true
  let surface = try GuidanceSpeechCoordinator(
    expectedRoutePlanID: "test.plan.speech", output: surfaceOutput, now: { now })
  let command = surfaceSpeechCommand(promptID: "surface.0")
  #expect(surface.submitProviderSurface(command) == .failed(.audioSessionActivationFailed))
  surfaceOutput.fail = false
  now += 3
  #expect(surface.submitProviderSurface(command) == .speaking(command.identity))
  #expect(surfaceOutput.commands.count == 1)

  let expresswayOutput = RecoverySpeechOutput()
  expresswayOutput.fail = true
  let expressway = try GuidanceSpeechCoordinator(
    expectedRoutePlanID: "test.plan.speech", output: expresswayOutput, now: { now })
  let projection = try speechProjection(promptID: "junction.0", anchorOccurrenceID: "anchor.0")
  #expect(expressway.submit(projection) == .failed(.audioSessionActivationFailed))
  expresswayOutput.fail = false
  now += 3
  guard case .speaking = expressway.submit(projection) else {
    Issue.record("Expected fresh authorized retry")
    return
  }
  #expect(expresswayOutput.commands.count == 1)
}

@MainActor @Test func speechRecoveryEgressCanPlayAfterExpresswayFinishes() throws {
  let output = RecoverySpeechOutput()
  let coordinator = try GuidanceSpeechCoordinator(
    expectedRoutePlanID: "test.plan.speech", output: output)
  _ = coordinator.submit(
    try speechProjection(promptID: "junction.last", anchorOccurrenceID: "anchor.last"))
  let command = surfaceSpeechCommand(promptID: "surface.egress.0")
  #expect(coordinator.submitProviderSurface(command) == .suppressed(.notAuthorized))
  output.finish(try #require(output.commands.first).identity)
  #expect(coordinator.submitProviderSurface(command) == .speaking(command.identity))
  #expect(output.commands.count == 2)
}

@Test func speechRecoveryJunctionSurvivesSkippedAnchor() async throws {
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()
  let database = try JSONDecoder().decode(
    ShutoNetworkDatabase.self,
    from: Data(
      contentsOf: root.appendingPathComponent(
        "data/route-atlas/osm-derived/shuto-whole-network-20260804.json")))
  let route = try ShutoRoutePlanner(database: database).plan(
    entryFacilityID: "shuto.ic.b.ooi", exitFacilityID: "shuto.ic.9.fukudumi")
  let assets = try ShutoPlannedRouteRuntimeCompiler.compile(database: database, route: route)
  let guidance = try #require(
    assets.releasedGuidance.first { $0.anchor.promptID.contains("tatsumi") })
  let anchor = try #require(route.routePlan.occurrence(id: guidance.anchor.occurrenceID))
  let movement = try #require(
    route.routePlan.occurrence(id: guidance.frameTemplate.movementOccurrenceID))
  let simulator = try NavigationDriveSimulator(
    route: route, runtimeAssets: assets,
    configuration: .init(maximumSampleSpacingMeters: 30, horizontalAccuracyMeters: 2))
  let trace = await simulator.trace
  let truth = Dictionary(uniqueKeysWithValues: trace.sampleTruth.map { ($0.observationID, $0) })
  var counts: [Int] = []
  for skip in [false, true] {
    let session = try NavigationSession(
      navigationConfiguration: NavigationConfiguration(
        routePlan: route.routePlan, releasedGuidance: assets.releasedGuidance),
      matcherCorridor: assets.matcherCorridor, decisionZones: assets.decisionZones,
      initialNavigationSnapshot: NavigationSnapshot(
        journeyPhase: .strictRoute, activeRoutePlanID: route.routePlan.id,
        currentOccurrenceID: route.routePlan.occurrences.first?.id),
      initialMatcherOccurrenceID: route.routePlan.occurrences.first?.id)
    _ = await session.start()
    var count = 0
    var resolvedAfterAnchorBeforeMovement = false
    for event in trace.events {
      guard case .matcherObservation(let observation) = event.action else { continue }
      if skip, let id = observation.id, truth[id]?.occurrenceID == anchor.id { continue }
      let update = try await session.observe(observation)
      if let emission = update.guidancePromptEmission, emission.promptID == guidance.anchor.promptID
      {
        count += 1
        let projection = try NavigationPresentationProjector.project(
          NavigationPresentationRequest(
            snapshot: update.navigationSnapshot, networkSnapshotID: database.networkSnapshotID,
            guidanceFrame: try #require(update.navigationSnapshot.activeGuidanceFrame),
            promptEmission: emission,
            languages: NavigationLanguageSelection(
              interfaceLocale: .japanese, guidanceVoiceLocale: .japanese),
            passageEvidence: .noKnownConflictRealtimeUnconfirmed,
            drivingContext: PresentationDrivingContext(
              isVehicleMoving: true, isInsideDecisionZone: true)))
        #expect(projection.voice.shouldSpeak)
      }
      if update.matcherEstimate.confidence == .high,
        let id = update.matcherEstimate.occurrenceID,
        let index = route.routePlan.occurrence(id: id)?.index,
        index > anchor.index, index < movement.index
      {
        resolvedAfterAnchorBeforeMovement = true
      }
    }
    counts.append(count)
    #expect(resolvedAfterAnchorBeforeMovement)
  }
  #expect(counts == [1, 1])
}

@MainActor @Test func speechRecoveryActivationAttemptsAreBounded() throws {
  var now: TimeInterval = 0
  let output = RecoverySpeechOutput()
  output.fail = true
  let coordinator = try GuidanceSpeechCoordinator(
    expectedRoutePlanID: "test.plan.speech", output: output, now: { now })
  let command = surfaceSpeechCommand(promptID: "surface.retry")
  for _ in 0..<3 {
    #expect(coordinator.submitProviderSurface(command) == .failed(.audioSessionActivationFailed))
    now += 3
  }
  output.fail = false
  #expect(coordinator.submitProviderSurface(command) == .failed(.retryLimitReached))
  #expect(output.speakAttempts == 3)
  output.eventHandler?(.interruptionBegan)
  output.eventHandler?(.interruptionEnded)
  #expect(coordinator.submitProviderSurface(command) == .speaking(command.identity))
}

@MainActor @Test func speechRecoveryUnstartedTimeoutCanRetryCurrentInstruction() throws {
  var now: TimeInterval = 0
  let output = RecoverySpeechOutput()
  output.emitsStart = false
  let coordinator = try GuidanceSpeechCoordinator(
    expectedRoutePlanID: "test.plan.speech", output: output, now: { now })
  let command = surfaceSpeechCommand(promptID: "surface.unstarted")
  #expect(coordinator.submitProviderSurface(command) == .scheduled(command.identity))
  now = 31
  output.emitsStart = true
  #expect(coordinator.submitProviderSurface(command) == .speaking(command.identity))
  #expect(output.commands.count == 2)
}

@MainActor @Test func speechRecoveryDoesNotNeedAnEndNotificationWhenActivationSucceeds() throws {
  var now: TimeInterval = 0
  let output = RecoverySpeechOutput()
  let coordinator = try GuidanceSpeechCoordinator(
    expectedRoutePlanID: "test.plan.speech", output: output, now: { now })
  output.eventHandler?(.interruptionBegan)
  let command = surfaceSpeechCommand(promptID: "surface.after-interruption")
  #expect(coordinator.submitProviderSurface(command) == .interrupted)
  #expect(output.commands.isEmpty)
  now = 3
  output.recoveryAllowed = true
  #expect(coordinator.submitProviderSurface(command) == .speaking(command.identity))
}

@MainActor @Test func speechRecoveryNoticesYieldToCurrentManeuvers() throws {
  let output = RecoverySpeechOutput()
  let coordinator = try GuidanceSpeechCoordinator(
    expectedRoutePlanID: "test.plan.speech", output: output)
  let notice = GuidanceSpeechCommand(
    identity: GuidanceSpeechIdentity(
      promptID: "status", anchorID: "JOURNEY_STATUS", anchorOccurrenceID: "status"),
    routePlanID: "test.plan.speech", languageCode: "en-US", spokenText: "Position restored")
  #expect(coordinator.submitNotice(notice) == .speaking(notice.identity))
  let command = surfaceSpeechCommand(promptID: "surface.current")
  #expect(coordinator.submitProviderSurface(command) == .speaking(command.identity))
  output.finish(notice.identity)
  #expect(coordinator.status == .speaking(command.identity))
  #expect(!coordinator.completedIdentities.contains(notice.identity))
}

@MainActor @Test func speechRecoveryInterruptionCannotUndoExplicitStop() throws {
  let output = RecoverySpeechOutput()
  let coordinator = try GuidanceSpeechCoordinator(
    expectedRoutePlanID: "test.plan.speech", output: output)
  coordinator.stop()
  output.eventHandler?(.interruptionBegan)
  output.eventHandler?(.interruptionEnded)
  let command = surfaceSpeechCommand(promptID: "surface.stopped")
  #expect(coordinator.submitProviderSurface(command) == .suppressed(.stopped))
  #expect(output.commands.isEmpty)
}

private func surfaceSpeechCommand(
  routePlanID: String = "test.plan.speech",
  promptID: String
) -> GuidanceSpeechCommand {
  GuidanceSpeechCommand(
    identity: GuidanceSpeechIdentity(
      promptID: promptID,
      anchorID: "PROVIDER_SURFACE_STEP",
      anchorOccurrenceID: promptID
    ),
    routePlanID: routePlanID,
    languageCode: "ja-JP",
    spokenText: "次の交差点を左折です"
  )
}

private func speechProjection(
  routePlanID: String = "test.plan.speech",
  promptID: String,
  anchorOccurrenceID: String,
  emitsPrompt: Bool = true,
  guidanceVoiceLocale: KaidoReleaseLocale = .japanese
) throws -> NavigationPresentationProjection {
  let sign = "B 湾岸線・横浜方面"
  let source = GuidancePresentationSource(
    routeShields: ["B"],
    japaneseSignText: sign,
    localizedContent: [
      .japanese: LocalizedGuidanceContent(
        displayText: "左側を進む",
        spokenText: "B 湾岸線へ",
        spokenForms: ["B": "ビー", "湾岸線": "わんがんせん"],
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
  let frame = GuidanceFrame(
    promptID: promptID,
    anchorID: "PREPARE",
    anchorOccurrenceID: anchorOccurrenceID,
    movementOccurrenceID: "test.occurrence.movement",
    decisionZoneID: "test.zone.speech",
    stage: .prepare,
    distanceMeters: 500,
    decisionPointNameJapanese: "テストJCT",
    localizedDecisionPointNames: [
      .japanese: "テストJCT",
      .simplifiedChinese: "测试 JCT",
      .english: "Test JCT",
    ],
    maneuver: .keepLeft,
    lanePreparation: .useLeftLanes,
    presentationSource: source
  )
  var snapshot = NavigationSnapshot(
    journeyPhase: .strictRoute,
    activeRoutePlanID: routePlanID,
    currentOccurrenceID: anchorOccurrenceID,
    locationConfidence: .high
  )
  let emission: GuidancePromptEmission?
  if emitsPrompt {
    snapshot.emittedGuidancePromptIDs = [promptID]
    snapshot.lastGuidancePromptID = promptID
    emission = GuidancePromptEmission(
      promptID: promptID,
      anchorID: frame.anchorID,
      anchorOccurrenceID: anchorOccurrenceID
    )
  } else {
    emission = nil
  }
  return try NavigationPresentationProjector.project(
    NavigationPresentationRequest(
      snapshot: snapshot,
      networkSnapshotID: "test.snapshot.speech",
      guidanceFrame: frame,
      promptEmission: emission,
      languages: NavigationLanguageSelection(
        interfaceLocale: .simplifiedChinese,
        guidanceVoiceLocale: guidanceVoiceLocale
      ),
      passageEvidence: .noKnownConflictRealtimeUnconfirmed,
      drivingContext: PresentationDrivingContext(
        isVehicleMoving: true,
        isInsideDecisionZone: true
      )
    )
  )
}
