import KaidoAppleAdapters
import KaidoDomain
import KaidoPresentation
import Testing

@Test("Speech scheduler admits one exact occurrence prompt and ignores stale completion")
func speechSchedulerAdmitsOccurrencePromptOnce() throws {
  var scheduler = try GuidanceSpeechScheduler(
    expectedRoutePlanID: "test.plan.speech"
  )
  let first = try speechProjection(
    promptID: "test.prompt.lap-1",
    anchorOccurrenceID: "test.occurrence.lap-1"
  )
  let firstResult = try scheduler.submit(first)
  guard case .speak(let firstCommand, replacing: nil) = firstResult else {
    Issue.record("Expected first speech command, got \(firstResult)")
    return
  }

  let duplicateResult = try scheduler.submit(first)
  #expect(duplicateResult == .suppressed(.duplicate))
  #expect(scheduler.activeCommand == firstCommand)

  let second = try speechProjection(
    promptID: "test.prompt.lap-2",
    anchorOccurrenceID: "test.occurrence.lap-2"
  )
  let secondResult = try scheduler.submit(second)
  guard
    case .speak(let secondCommand, replacing: let replaced) = secondResult
  else {
    Issue.record("Expected replacement speech command, got \(secondResult)")
    return
  }
  #expect(replaced == firstCommand.identity)
  let staleCompletionAccepted = scheduler.didFinish(firstCommand.identity)
  #expect(!staleCompletionAccepted)
  #expect(scheduler.activeCommand == secondCommand)
  let currentCompletionAccepted = scheduler.didFinish(
    secondCommand.identity
  )
  #expect(currentCompletionAccepted)
  #expect(scheduler.state == .idle)
  #expect(scheduler.consumedIdentities.count == 2)
}

@Test("Persistent guidance without a transient emission never gains speech authority")
func speechSchedulerRequiresTransientEmission() throws {
  var scheduler = try GuidanceSpeechScheduler(
    expectedRoutePlanID: "test.plan.speech"
  )
  let projection = try speechProjection(
    promptID: "test.prompt.no-emission",
    anchorOccurrenceID: "test.occurrence.no-emission",
    emitsPrompt: false
  )

  let result = try scheduler.submit(projection)
  #expect(result == .suppressed(.notAuthorized))
  #expect(scheduler.consumedIdentities.isEmpty)
  #expect(scheduler.activeCommand == nil)
  #expect(scheduler.state == .idle)
}

@Test("Audio interruption drops current and interrupted prompts without catch-up replay")
func speechSchedulerDoesNotReplayAfterInterruption() throws {
  var scheduler = try GuidanceSpeechScheduler(
    expectedRoutePlanID: "test.plan.speech"
  )
  let first = try speechProjection(
    promptID: "test.prompt.before-call",
    anchorOccurrenceID: "test.occurrence.before-call"
  )
  guard case .speak(let firstCommand, replacing: nil) = try scheduler.submit(first) else {
    Issue.record("Expected initial speech")
    return
  }

  let interruptedIdentity = scheduler.interruptionBegan()
  #expect(interruptedIdentity == firstCommand.identity)
  #expect(scheduler.state == .interrupted)
  #expect(scheduler.activeCommand == nil)

  let during = try speechProjection(
    promptID: "test.prompt.during-call",
    anchorOccurrenceID: "test.occurrence.during-call"
  )
  let interruptedResult = try scheduler.submit(during)
  #expect(interruptedResult == .suppressed(.interrupted))
  scheduler.interruptionEnded()
  #expect(scheduler.state == .idle)
  #expect(scheduler.activeCommand == nil)
  let replayResult = try scheduler.submit(during)
  #expect(replayResult == .suppressed(.duplicate))

  let after = try speechProjection(
    promptID: "test.prompt.after-call",
    anchorOccurrenceID: "test.occurrence.after-call"
  )
  guard case .speak(let afterCommand, replacing: nil) = try scheduler.submit(after) else {
    Issue.record("Expected a fresh post-interruption prompt")
    return
  }
  #expect(afterCommand.identity.promptID == "test.prompt.after-call")
}

@Test("Speech scheduler stays bound to one exact RoutePlan")
func speechSchedulerRejectsRoutePlanDrift() throws {
  var scheduler = try GuidanceSpeechScheduler(
    expectedRoutePlanID: "test.plan.expected"
  )
  let projection = try speechProjection(
    routePlanID: "test.plan.other",
    promptID: "test.prompt.other-route",
    anchorOccurrenceID: "test.occurrence.other-route"
  )

  #expect(throws: GuidanceSpeechSchedulerError.routePlanMismatch) {
    try scheduler.submit(projection)
  }
  #expect(scheduler.consumedIdentities.isEmpty)
}

@Test("Speech scheduler resumes after lifecycle stop without replaying consumed prompts")
func speechSchedulerResumesWithoutReplay() throws {
  var scheduler = try GuidanceSpeechScheduler(
    expectedRoutePlanID: "test.plan.speech"
  )
  let beforeBackground = try speechProjection(
    promptID: "test.prompt.before-background",
    anchorOccurrenceID: "test.occurrence.before-background"
  )
  guard
    case .speak = try scheduler.submit(beforeBackground)
  else {
    Issue.record("Expected pre-background prompt")
    return
  }

  _ = scheduler.stop()
  scheduler.resume()
  #expect(scheduler.state == .idle)
  #expect(
    try scheduler.submit(beforeBackground)
      == .suppressed(.duplicate)
  )

  let afterForeground = try speechProjection(
    promptID: "test.prompt.after-foreground",
    anchorOccurrenceID: "test.occurrence.after-foreground"
  )
  guard
    case .speak(let command, replacing: nil) =
      try scheduler.submit(afterForeground)
  else {
    Issue.record("Expected fresh post-foreground prompt")
    return
  }
  #expect(command.identity.promptID == "test.prompt.after-foreground")
}

@MainActor
@Test("Speech coordinator stops replaced output and ignores its stale callback")
func speechCoordinatorStopsReplacedOutput() throws {
  let output = RecordingSpeechOutput()
  let coordinator = try GuidanceSpeechCoordinator(
    expectedRoutePlanID: "test.plan.speech",
    output: output
  )
  let firstProjection = try speechProjection(
    promptID: "test.prompt.first",
    anchorOccurrenceID: "test.occurrence.first"
  )
  guard
    case .speaking(let firstIdentity) = coordinator.submit(
      firstProjection
    )
  else {
    Issue.record("Expected first prompt to start speaking")
    return
  }

  let secondProjection = try speechProjection(
    promptID: "test.prompt.second",
    anchorOccurrenceID: "test.occurrence.second"
  )
  guard
    case .speaking(let secondIdentity) = coordinator.submit(
      secondProjection
    )
  else {
    Issue.record("Expected replacement prompt to start speaking")
    return
  }

  #expect(output.stopCount == 1)
  #expect(output.commands.map(\.identity) == [firstIdentity, secondIdentity])
  output.finish(firstIdentity)
  #expect(coordinator.status == .speaking(secondIdentity))
  #expect(coordinator.scheduler.activeCommand?.identity == secondIdentity)
}

private func speechProjection(
  routePlanID: String = "test.plan.speech",
  promptID: String,
  anchorOccurrenceID: String,
  emitsPrompt: Bool = true
) throws -> NavigationPresentationProjection {
  let sign = "B 湾岸線・横浜方面"
  let source = GuidancePresentationSource(
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
        guidanceVoiceLocale: .japanese
      ),
      passageEvidence: .noKnownConflictRealtimeUnconfirmed,
      drivingContext: PresentationDrivingContext(
        isVehicleMoving: true,
        isInsideDecisionZone: true
      )
    )
  )
}

@MainActor
private final class RecordingSpeechOutput: GuidanceSpeechOutput {
  var eventHandler: ((GuidanceSpeechOutputEvent) -> Void)?
  private(set) var commands: [GuidanceSpeechCommand] = []
  private(set) var stopCount = 0
  private var activeIdentity: GuidanceSpeechIdentity?

  func speak(_ command: GuidanceSpeechCommand) {
    commands.append(command)
    activeIdentity = command.identity
    eventHandler?(.didStart(command.identity))
  }

  func stop() {
    stopCount += 1
    guard let activeIdentity else { return }
    self.activeIdentity = nil
    eventHandler?(.didCancel(activeIdentity))
  }

  func finish(_ identity: GuidanceSpeechIdentity) {
    eventHandler?(.didFinish(identity))
  }
}
