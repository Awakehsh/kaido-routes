import KaidoAppleAdapters
import KaidoDomain
import KaidoPresentation
import XCTest

@testable import KaidoRoutesApp

@MainActor
final class WholeShutoProductModelTests: XCTestCase {
  func testJunctionPromptsRequireAnExactReviewedMovement() {
    let model = WholeShutoProductModel(checkpointStore: nil)

    model.preparePreviewJourney()

    XCTAssertTrue(model.junctionPrompts.isEmpty)

    model.prepareJunctionPreview()

    let prompt = try? XCTUnwrap(model.junctionPrompts.only)
    XCTAssertEqual(
      prompt?.movementID,
      "shuto.jct.oi.b-westbound-to-c2-outer"
    )
    XCTAssertEqual(prompt?.nameJA, "大井JCT")
    XCTAssertEqual(prompt?.incomingRouteID, "B")
    XCTAssertEqual(prompt?.outgoingRouteID, "C2")
    XCTAssertEqual(prompt?.outgoingDirectionJA, "外回り")
    XCTAssertEqual(prompt?.branchSide, .left)
    XCTAssertEqual(prompt?.japaneseSignText, "東名・中央道")
    XCTAssertEqual(prompt?.routeShields, ["C2", "3", "E1", "E20"])
    XCTAssertEqual(prompt?.laneGuidanceState, .notReleased)
    XCTAssertEqual(prompt?.localizedJunctionNames[.japanese], "大井JCT")
    XCTAssertEqual(
      prompt?.localizedJunctionNames[.simplifiedChinese],
      "大井 JCT"
    )
    XCTAssertEqual(prompt?.localizedJunctionNames[.english], "Oi JCT")
    XCTAssertEqual(
      prompt?.localizedContent[.japanese]?.displayText,
      "左方向へ分岐し、C2 外回りへ"
    )
    XCTAssertEqual(
      prompt?.localizedContent[.simplifiedChinese]?.displayText,
      "向左分岔，驶入 C2 外环"
    )
    XCTAssertEqual(
      prompt?.localizedContent[.english]?.displayText,
      "Branch left for the C2 Outer Loop"
    )
    XCTAssertTrue(
      prompt?.localizedContent.values.allSatisfy {
        $0.preservedJapaneseSignText == "東名・中央道"
      } == true
    )
    XCTAssertEqual(prompt?.checkedAt, "2026-07-29")
    XCTAssertEqual(model.activeJunctionPrompt, prompt)
    XCTAssertNil(model.failureCode)
  }

  func testKasaiJunctionPromptRequiresTheExactReviewedMovement() {
    let model = WholeShutoProductModel(checkpointStore: nil)

    model.prepareKasaiJunctionPreview()

    let prompt = try? XCTUnwrap(model.junctionPrompts.only)
    XCTAssertEqual(
      prompt?.movementID,
      "shuto.jct.kasai.b-westbound-to-c2-inner"
    )
    XCTAssertEqual(prompt?.nameJA, "葛西JCT")
    XCTAssertEqual(prompt?.incomingRouteID, "B")
    XCTAssertEqual(prompt?.outgoingRouteID, "C2")
    XCTAssertEqual(prompt?.outgoingDirectionJA, "内回り")
    XCTAssertEqual(prompt?.branchSide, .left)
    XCTAssertEqual(prompt?.japaneseSignText, "東北道・常磐道")
    XCTAssertEqual(prompt?.routeShields, ["C2", "E4", "E6", "6"])
    XCTAssertEqual(prompt?.laneGuidanceState, .notReleased)
    XCTAssertEqual(
      prompt?.localizedContent[.japanese]?.displayText,
      "左方向へ分岐し、C2 内回りへ"
    )
    XCTAssertEqual(
      prompt?.localizedContent[.simplifiedChinese]?.displayText,
      "向左分岔，驶入 C2 内环"
    )
    XCTAssertEqual(
      prompt?.localizedContent[.english]?.displayText,
      "Branch left for the C2 Inner Loop"
    )
    XCTAssertEqual(prompt?.checkedAt, "2026-07-30")
    XCTAssertEqual(model.activeJunctionPrompt, prompt)
    XCTAssertNil(model.failureCode)
  }

  func testTatsumiJunctionPromptsPreserveEachApproachSign() {
    let cases:
      [(
        isEastbound: Bool,
        movementID: String,
        signText: String,
        routeShields: [String]
      )] = [
        (
          true,
          "shuto.jct.tatsumi.b-eastbound-to-9-inbound",
          "箱崎",
          ["9", "6"]
        ),
        (
          false,
          "shuto.jct.tatsumi.b-westbound-to-9-inbound",
          "箱崎・銀座",
          ["9", "C1"]
        ),
      ]

    for testCase in cases {
      let model = WholeShutoProductModel(checkpointStore: nil)
      if testCase.isEastbound {
        model.prepareTatsumiEastboundJunctionPreview()
      } else {
        model.prepareTatsumiWestboundJunctionPreview()
      }

      let prompt = try? XCTUnwrap(model.junctionPrompts.only)
      XCTAssertEqual(prompt?.movementID, testCase.movementID)
      XCTAssertEqual(prompt?.nameJA, "辰巳JCT")
      XCTAssertEqual(prompt?.outgoingRouteID, "9")
      XCTAssertEqual(prompt?.outgoingDirectionJA, "上り")
      XCTAssertEqual(prompt?.branchSide, .left)
      XCTAssertEqual(prompt?.japaneseSignText, testCase.signText)
      XCTAssertEqual(prompt?.routeShields, testCase.routeShields)
      XCTAssertEqual(prompt?.laneGuidanceState, .notReleased)
      XCTAssertEqual(
        prompt?.localizedContent[.japanese]?.displayText,
        "左方向へ分岐し、9号深川線 上りへ"
      )
      XCTAssertEqual(
        prompt?.localizedContent[.simplifiedChinese]?.displayText,
        "向左分岔，驶入 9 号深川线上行方向"
      )
      XCTAssertEqual(
        prompt?.localizedContent[.english]?.displayText,
        "Branch left for Route 9 inbound"
      )
      XCTAssertTrue(
        prompt?.localizedContent.values.allSatisfy {
          $0.preservedJapaneseSignText == testCase.signText
        } == true
      )
      XCTAssertEqual(prompt?.checkedAt, "2026-07-30")
      XCTAssertEqual(model.activeJunctionPrompt, prompt)
      XCTAssertNil(model.failureCode)
    }
  }

  func testShinonomeJunctionPromptsPreserveEachApproachBranchAndSign() {
    let cases:
      [(
        isEastbound: Bool,
        movementID: String,
        isLeftBranch: Bool,
        signText: String,
        localizedInstruction: String
      )] = [
        (
          true,
          "shuto.jct.shinonome.b-eastbound-to-10-inbound",
          true,
          "豊洲",
          "向左分岔，驶入 10 号晴海线上行方向"
        ),
        (
          false,
          "shuto.jct.shinonome.b-westbound-to-10-inbound",
          false,
          "晴海",
          "向右分岔，驶入 10 号晴海线上行方向"
        ),
      ]

    for testCase in cases {
      let model = WholeShutoProductModel(checkpointStore: nil)
      if testCase.isEastbound {
        model.prepareShinonomeEastboundJunctionPreview()
      } else {
        model.prepareShinonomeWestboundJunctionPreview()
      }

      let prompt = try? XCTUnwrap(model.junctionPrompts.only)
      XCTAssertEqual(prompt?.movementID, testCase.movementID)
      XCTAssertEqual(prompt?.nameJA, "東雲JCT")
      XCTAssertEqual(prompt?.outgoingRouteID, "10")
      XCTAssertEqual(prompt?.outgoingDirectionJA, "上り")
      XCTAssertEqual(
        prompt?.branchSide,
        testCase.isLeftBranch ? .left : .right
      )
      XCTAssertEqual(prompt?.japaneseSignText, testCase.signText)
      XCTAssertEqual(prompt?.routeShields, ["10"])
      XCTAssertEqual(prompt?.laneGuidanceState, .notReleased)
      XCTAssertEqual(
        prompt?.localizedContent[.simplifiedChinese]?.displayText,
        testCase.localizedInstruction
      )
      XCTAssertTrue(
        prompt?.localizedContent.values.allSatisfy {
          $0.preservedJapaneseSignText == testCase.signText
        } == true
      )
      XCTAssertEqual(prompt?.checkedAt, "2026-07-30")
      XCTAssertEqual(model.activeJunctionPrompt, prompt)
      XCTAssertNil(model.failureCode)
    }
  }

  func testActiveJourneyRestoresPausedOnTheSameNetworkSnapshot()
    async throws
  {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: store)
    model.preparePreviewJourney()
    let originalRoute = try XCTUnwrap(model.selectedRoute)

    model.startNavigationSimulation()
    model.togglePlayback()
    await advance(model, until: { $0.phase == .expressway })
    for _ in 0..<3 {
      await model.advanceSimulationForTesting()
    }
    let savedProgress = model.progressFraction
    let savedCoordinate = model.currentCoordinate

    let restored = WholeShutoProductModel(
      database: model.database,
      checkpointStore: store
    )

    XCTAssertEqual(restored.phase, .expressway)
    XCTAssertEqual(restored.progressFraction, savedProgress)
    XCTAssertEqual(
      restored.runtimeOccurrenceID,
      model.runtimeOccurrenceID
    )
    XCTAssertEqual(
      restored.selectedRoute?.entryFacility.facilityID,
      originalRoute.entryFacility.facilityID
    )
    XCTAssertEqual(
      restored.selectedRoute?.exitFacility.facilityID,
      originalRoute.exitFacility.facilityID
    )
    XCTAssertTrue(restored.restoredFromCheckpoint)
    XCTAssertFalse(restored.isPlaying)

    await restored.advanceSimulationForTesting()
    XCTAssertGreaterThanOrEqual(
      restored.progressFraction,
      savedProgress
    )
    XCTAssertEqual(restored.currentCoordinate, savedCoordinate)
  }

  func testEntryCheckpointBeforeFirstObservationRestoresRuntime()
    async
  {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: store)
    model.preparePreviewJourney()
    model.startNavigationSimulation()
    model.togglePlayback()
    await advance(model, until: { $0.phase == .entryTransition })

    XCTAssertEqual(model.progressFraction, 0)
    XCTAssertNil(model.runtimeOccurrenceID)

    let restored = WholeShutoProductModel(
      database: model.database,
      checkpointStore: store
    )

    XCTAssertEqual(restored.phase, .entryTransition)
    XCTAssertTrue(restored.restoredFromCheckpoint)
    XCTAssertNil(restored.failureCode)

    await restored.advanceSimulationForTesting()

    XCTAssertEqual(restored.matcherConfidence, .high)
    XCTAssertEqual(restored.phase, .entryTransition)
    XCTAssertNil(restored.runtimeOccurrenceID)

    await advance(restored, until: { $0.phase == .expressway })

    XCTAssertNotNil(restored.runtimeOccurrenceID)
    XCTAssertGreaterThan(restored.progressFraction, 0)
  }

  func testCheckpointRoutePlanDriftDoesNotRestore() throws {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: store)
    model.preparePreviewJourney()
    model.startNavigationSimulation()
    model.togglePlayback()

    let checkpoint = try XCTUnwrap(store.checkpoint)
    let originalPlan = checkpoint.routePlan
    var occurrences = originalPlan.occurrences
    let first = try XCTUnwrap(occurrences.first)
    occurrences[0] = RouteOccurrence(
      id: first.id,
      index: first.index,
      kind: first.kind,
      entityID: "\(first.entityID).drifted",
      parkingAreaID: first.parkingAreaID,
      tollDomainID: first.tollDomainID,
      isOptional: first.isOptional
    )
    store.checkpoint = checkpoint.replacingRoutePlan(
      RoutePlan(
        id: originalPlan.id,
        networkSnapshotID: originalPlan.networkSnapshotID,
        entryFacilityID: originalPlan.entryFacilityID,
        exitFacilityID: originalPlan.exitFacilityID,
        recoveryPolicy: originalPlan.recoveryPolicy,
        actualDistanceKM: originalPlan.actualDistanceKM,
        occurrences: occurrences
      )
    )

    let restored = WholeShutoProductModel(
      database: model.database,
      checkpointStore: store
    )

    XCTAssertEqual(restored.phase, .planning)
    XCTAssertNil(restored.selectedRoute)
    XCTAssertFalse(restored.restoredFromCheckpoint)
  }

  func testExpresswayPreviewExplicitlyReportsTunnelEstimation() async {
    let model = WholeShutoProductModel(checkpointStore: nil)
    model.preparePreviewJourney()
    model.startNavigationSimulation()
    model.togglePlayback()

    await advance(
      model,
      until: {
        $0.phase == .expressway
          && $0.positionState == .tunnelEstimated
      },
      maximumTicks: 180
    )

    XCTAssertEqual(model.positionState, .tunnelEstimated)
  }

  func testEntryTransitionRequiresOrderedObservationsBeforeExpressway()
    async
  {
    let model = WholeShutoProductModel(checkpointStore: nil)
    model.preparePreviewJourney()
    model.startNavigationSimulation()
    model.togglePlayback()

    await advance(model, until: { $0.phase == .entryTransition })

    XCTAssertEqual(model.progressFraction, 0)
    XCTAssertNil(model.runtimeOccurrenceID)
    XCTAssertEqual(model.positionState, .boundaryTransition)

    for _ in 0..<3 {
      await model.advanceSimulationForTesting()
    }

    XCTAssertEqual(model.matcherConfidence, .high)
    XCTAssertEqual(model.phase, .entryTransition)
    XCTAssertNil(model.runtimeOccurrenceID)

    await model.advanceSimulationForTesting()

    XCTAssertEqual(model.phase, .expressway)
    XCTAssertNotNil(model.runtimeOccurrenceID)
    XCTAssertGreaterThan(model.progressFraction, 0)
  }

  func testReviewedJunctionSpeechIsActorOwnedAndNotRepeatedAfterRestore()
    async throws
  {
    let store = WholeShutoMemoryCheckpointStore()
    let initialOutput = WholeShutoRecordingSpeechOutput()
    let model = WholeShutoProductModel(
      checkpointStore: store,
      speechOutput: initialOutput,
      languageSelectionProvider: Self.testLanguages
    )
    model.prepareJunctionPreview(startsNavigation: true)
    model.togglePlayback()

    await advance(
      model,
      until: { _ in !initialOutput.commands.isEmpty },
      maximumTicks: 1_000
    )

    let command = try XCTUnwrap(initialOutput.commands.only)
    XCTAssertEqual(command.languageCode, "ja-JP")
    XCTAssertTrue(command.spokenText.contains("大井ジャンクション"))
    XCTAssertTrue(command.synthesisText.contains("シーツー"))
    XCTAssertEqual(
      model.presentationProjection?.iPhone.maneuver,
      .branchLeft
    )
    XCTAssertEqual(
      model.presentationProjection?.iPhone.lanePreparation,
      GuidanceLanePreparation.none
    )
    XCTAssertEqual(
      model.activeJunctionPrompt?.movementID,
      "shuto.jct.oi.b-westbound-to-c2-outer"
    )

    model.handleScenePhase(.background)

    let restoredOutput = WholeShutoRecordingSpeechOutput()
    let restored = WholeShutoProductModel(
      database: model.database,
      checkpointStore: store,
      speechOutput: restoredOutput,
      languageSelectionProvider: Self.testLanguages
    )
    XCTAssertEqual(restored.phase, .expressway)

    await advance(
      restored,
      until: {
        $0.speechStatus == .suppressed(.duplicate)
      },
      maximumTicks: 80
    )

    XCTAssertTrue(restoredOutput.commands.isEmpty)
    XCTAssertEqual(restored.speechStatus, .suppressed(.duplicate))
  }

  func testKasaiJunctionSpeechIsActorOwned() async throws {
    let output = WholeShutoRecordingSpeechOutput()
    let model = WholeShutoProductModel(
      checkpointStore: nil,
      speechOutput: output,
      languageSelectionProvider: Self.testLanguages
    )
    model.prepareKasaiJunctionPreview(startsNavigation: true)
    model.togglePlayback()

    await advance(
      model,
      until: { _ in !output.commands.isEmpty },
      maximumTicks: 1_000
    )

    let command = try XCTUnwrap(output.commands.only)
    XCTAssertEqual(command.languageCode, "ja-JP")
    XCTAssertTrue(command.spokenText.contains("葛西ジャンクション"))
    XCTAssertTrue(command.synthesisText.contains("シーツー"))
    XCTAssertEqual(
      model.presentationProjection?.iPhone.maneuver,
      .branchLeft
    )
    XCTAssertEqual(
      model.presentationProjection?.iPhone.lanePreparation,
      GuidanceLanePreparation.none
    )
    XCTAssertEqual(
      model.presentationProjection?.iPhone.japaneseSignText,
      "東北道・常磐道"
    )
    XCTAssertEqual(
      model.activeJunctionPrompt?.movementID,
      "shuto.jct.kasai.b-westbound-to-c2-inner"
    )
  }

  func testTatsumiJunctionSpeechIsActorOwned() async throws {
    let output = WholeShutoRecordingSpeechOutput()
    let model = WholeShutoProductModel(
      checkpointStore: nil,
      speechOutput: output,
      languageSelectionProvider: Self.testLanguages
    )
    model.prepareTatsumiEastboundJunctionPreview(
      startsNavigation: true
    )
    model.togglePlayback()

    await advance(
      model,
      until: { _ in !output.commands.isEmpty },
      maximumTicks: 1_000
    )

    let command = try XCTUnwrap(output.commands.only)
    XCTAssertEqual(command.languageCode, "ja-JP")
    XCTAssertTrue(command.spokenText.contains("辰巳ジャンクション"))
    XCTAssertTrue(
      command.synthesisText.contains("きゅうごうふかがわせん")
    )
    XCTAssertEqual(
      model.presentationProjection?.iPhone.maneuver,
      .branchLeft
    )
    XCTAssertEqual(
      model.presentationProjection?.iPhone.lanePreparation,
      GuidanceLanePreparation.none
    )
    XCTAssertEqual(
      model.presentationProjection?.iPhone.japaneseSignText,
      "箱崎"
    )
    XCTAssertEqual(
      model.activeJunctionPrompt?.movementID,
      "shuto.jct.tatsumi.b-eastbound-to-9-inbound"
    )
  }

  func testShinonomeRightBranchSpeechIsActorOwned() async throws {
    let output = WholeShutoRecordingSpeechOutput()
    let model = WholeShutoProductModel(
      checkpointStore: nil,
      speechOutput: output,
      languageSelectionProvider: Self.testLanguages
    )
    model.prepareShinonomeWestboundJunctionPreview(
      startsNavigation: true
    )
    model.togglePlayback()

    await advance(
      model,
      until: { _ in !output.commands.isEmpty },
      maximumTicks: 1_000
    )

    let command = try XCTUnwrap(output.commands.only)
    XCTAssertEqual(command.languageCode, "ja-JP")
    XCTAssertTrue(command.spokenText.contains("東雲ジャンクション"))
    XCTAssertTrue(
      command.synthesisText.contains("じゅうごうはるみせん")
    )
    XCTAssertEqual(
      model.presentationProjection?.iPhone.maneuver,
      .branchRight
    )
    XCTAssertEqual(
      model.presentationProjection?.iPhone.lanePreparation,
      GuidanceLanePreparation.none
    )
    XCTAssertEqual(
      model.presentationProjection?.iPhone.japaneseSignText,
      "晴海"
    )
    XCTAssertEqual(
      model.activeJunctionPrompt?.movementID,
      "shuto.jct.shinonome.b-westbound-to-10-inbound"
    )
  }

  func testReviewedJunctionKeepsInterfaceAndVoiceLanguagesIndependent()
    async throws
  {
    let output = WholeShutoRecordingSpeechOutput()
    let languages = NavigationLanguageSelection(
      interfaceLocale: .english,
      guidanceVoiceLocale: .simplifiedChinese
    )
    let model = WholeShutoProductModel(
      checkpointStore: nil,
      speechOutput: output,
      languageSelectionProvider: { languages }
    )
    model.prepareJunctionPreview(startsNavigation: true)
    model.togglePlayback()

    await advance(
      model,
      until: { _ in !output.commands.isEmpty },
      maximumTicks: 1_000
    )

    let projection = try XCTUnwrap(model.presentationProjection)
    let command = try XCTUnwrap(output.commands.only)
    XCTAssertEqual(projection.interfaceLocale, .english)
    XCTAssertEqual(projection.iPhone.localizedDecisionPointName, "Oi JCT")
    XCTAssertEqual(
      projection.iPhone.localizedDisplayText,
      "Branch left for the C2 Outer Loop"
    )
    XCTAssertEqual(projection.iPhone.japaneseSignText, "東名・中央道")
    XCTAssertEqual(projection.carPlay.japaneseSignText, "東名・中央道")
    XCTAssertEqual(projection.voice.locale, .simplifiedChinese)
    XCTAssertEqual(projection.voice.spokenText, "在大井枢纽向左分岔，驶入 C2 外环")
    XCTAssertEqual(command.languageCode, "zh-CN")
    XCTAssertEqual(command.spokenText, projection.voice.spokenText)
    XCTAssertTrue(command.synthesisText.contains("C 二"))
  }

  private func advance(
    _ model: WholeShutoProductModel,
    until predicate: (WholeShutoProductModel) -> Bool,
    maximumTicks: Int = 80,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    for _ in 0..<maximumTicks {
      if predicate(model) {
        return
      }
      await model.advanceSimulationForTesting()
    }
    XCTFail(
      "Whole-Shuto simulation did not reach the expected state",
      file: file,
      line: line
    )
  }

  private static func testLanguages() -> NavigationLanguageSelection {
    NavigationLanguageSelection(
      interfaceLocale: .simplifiedChinese,
      guidanceVoiceLocale: .japanese
    )
  }
}

private extension Collection {
  var only: Element? {
    count == 1 ? first : nil
  }
}

@MainActor
private final class WholeShutoMemoryCheckpointStore:
  WholeShutoJourneyCheckpointStoring
{
  var checkpoint: WholeShutoJourneyCheckpoint?

  func load() throws -> WholeShutoJourneyCheckpoint? {
    checkpoint
  }

  func save(_ checkpoint: WholeShutoJourneyCheckpoint) throws {
    self.checkpoint = checkpoint
  }

  func remove() throws {
    checkpoint = nil
  }
}

private extension WholeShutoJourneyCheckpoint {
  func replacingRoutePlan(_ routePlan: RoutePlan) -> Self {
    WholeShutoJourneyCheckpoint(
      schemaVersion: schemaVersion,
      networkSnapshotID: networkSnapshotID,
      originQuery: originQuery,
      destinationQuery: destinationQuery,
      origin: origin,
      destination: destination,
      entryFacilityID: entryFacilityID,
      exitFacilityID: exitFacilityID,
      routePlan: routePlan,
      preference: preference,
      phase: phase,
      progressFraction: progressFraction,
      runtimeOccurrenceID: runtimeOccurrenceID,
      runtimeFractionAlongOccurrence: runtimeFractionAlongOccurrence,
      consumedGuidancePromptIDs: consumedGuidancePromptIDs,
      mapMode: mapMode,
      accessRoute: accessRoute,
      egressRoute: egressRoute
    )
  }
}

@MainActor
private final class WholeShutoRecordingSpeechOutput:
  GuidanceSpeechOutput
{
  var eventHandler: ((GuidanceSpeechOutputEvent) -> Void)?
  var selectedVoiceProfile: GuidanceSpeechVoiceProfile?
  private(set) var commands: [GuidanceSpeechCommand] = []

  func speak(_ command: GuidanceSpeechCommand) {
    commands.append(command)
    eventHandler?(.didStart(command.identity))
  }

  func stop() {}
}
