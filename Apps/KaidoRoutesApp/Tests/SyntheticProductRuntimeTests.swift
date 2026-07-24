import CoreLocation
import Foundation
import KaidoAppleAdapters
import KaidoDomain
import KaidoNavigation
import KaidoPresentation
import XCTest

@testable import KaidoRoutesApp

final class SyntheticProductRuntimeTests: XCTestCase {
  func testBundledArtifactBuildsOnlySyntheticJointReleaseRuntime() throws {
    let fixture = try SyntheticProductRuntimeFixture.bundled()
    let runtime = try KaidoProductNavigationRuntime(release: fixture.release)

    XCTAssertEqual(
      fixture.release.releaseID,
      SyntheticProductRuntimeFixture.expectedProductReleaseID
    )
    XCTAssertEqual(
      runtime.navigationReleaseID,
      "test.navigation-release.release-bundle.v1"
    )
    XCTAssertEqual(
      runtime.routePlanID,
      fixture.release.routeAtlas.routePlan.id
    )
    XCTAssertEqual(
      runtime.networkSnapshotID,
      fixture.release.routeAtlas.networkSnapshot.id
    )
    XCTAssertGreaterThan(fixture.encodedByteCount, 0)
    XCTAssertEqual(
      fixture.release.runtimeUse,
      .syntheticTestOnlyDisabled
    )
    XCTAssertNil(fixture.release.foregroundLiveInputAuthority)
    XCTAssertTrue(
      fixture.release.navigation.sourceRegistry.references.allSatisfy {
        $0.licenceIdentifier == "SYNTHETIC_TEST_ONLY"
      }
    )
    XCTAssertTrue(
      fixture.release.routeAtlas.sourceRegistry.references.allSatisfy {
        $0.licenceIdentifier == "SYNTHETIC_TEST_ONLY"
      }
    )
  }

  func testFixtureRejectsAProductIdentityMutationBeforeRuntimeAdmission() throws {
    let url = try XCTUnwrap(
      Bundle.main.url(
        forResource: SyntheticProductRuntimeFixture.resourceName,
        withExtension: "json"
      )
    )
    let artifact = try JSONDecoder().decode(
      KaidoProductReleaseArtifact.self,
      from: Data(contentsOf: url)
    )
    let mutated = KaidoProductReleaseArtifact(
      releaseID: "release-without-synthetic-preview-identity",
      releasedAt: artifact.releasedAt,
      runtimeUse: artifact.runtimeUse,
      navigationRelease: artifact.navigationRelease,
      routeAtlasRelease: artifact.routeAtlasRelease
    )
    let data = try JSONEncoder().encode(mutated)

    XCTAssertThrowsError(try SyntheticProductRuntimeFixture.decode(data)) {
      XCTAssertEqual(
        $0 as? SyntheticProductRuntimeFixtureError,
        .unexpectedReleaseIdentity
      )
    }
  }

  func testFixtureRejectsLiveInputRuntimeUse() throws {
    let url = try XCTUnwrap(
      Bundle.main.url(
        forResource: SyntheticProductRuntimeFixture.resourceName,
        withExtension: "json"
      )
    )
    var root = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: url))
        as? [String: Any]
    )
    root["runtime_use"] = [
      "evidence_scope": "SYNTHETIC_TEST_ONLY",
      "live_input_policy": "FOREGROUND_WHEN_IN_USE",
    ]
    let data = try JSONSerialization.data(withJSONObject: root)

    XCTAssertThrowsError(try SyntheticProductRuntimeFixture.decode(data)) {
      XCTAssertEqual(
        $0 as? SyntheticProductRuntimeFixtureError,
        .unexpectedRuntimeUse
      )
    }
  }

  func testFixtureRejectsASourceThatLosesSyntheticClassification() throws {
    let url = try XCTUnwrap(
      Bundle.main.url(
        forResource: SyntheticProductRuntimeFixture.resourceName,
        withExtension: "json"
      )
    )
    var root = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: url))
        as? [String: Any]
    )
    var navigationRelease = try XCTUnwrap(
      root["navigation_release"] as? [String: Any]
    )
    var sourceRegistry = try XCTUnwrap(
      navigationRelease["source_registry"] as? [String: Any]
    )
    var references = try XCTUnwrap(
      sourceRegistry["references"] as? [[String: Any]]
    )
    references[0]["licence_identifier"] = "UNCLASSIFIED"
    sourceRegistry["references"] = references
    navigationRelease["source_registry"] = sourceRegistry
    root["navigation_release"] = navigationRelease
    let data = try JSONSerialization.data(withJSONObject: root)

    XCTAssertThrowsError(try SyntheticProductRuntimeFixture.decode(data)) {
      XCTAssertEqual(
        $0 as? SyntheticProductRuntimeFixtureError,
        .nonSyntheticSource
      )
    }
  }

  @MainActor
  func testForegroundPipelinePublishesActorSnapshotsAtomically() async throws {
    let speechOutput = RecordingGuidanceSpeechOutput()
    let model = try SyntheticProductRuntimeModel(
      fixture: SyntheticProductRuntimeFixture.bundled(),
      sourceEvidenceProvider: FixedSourceEvidenceProvider(isSimulated: false),
      speechOutput: speechOutput
    )
    await model.activate()

    XCTAssertEqual(model.activation, .ready)
    XCTAssertEqual(model.snapshot?.journeyPhase, .planning)
    XCTAssertFalse(try XCTUnwrap(model.snapshot).strictRouteAutoCommitAllowed)
    XCTAssertFalse(model.isRealRoadAuthority)
    XCTAssertEqual(
      model.foregroundNavigationLocationAuthority,
      .blocked(
        identity: model.foregroundNavigationRuntimeIdentity,
        reason: .syntheticTestOnly
      )
    )
    XCTAssertFalse(model.canConsumeForegroundNavigationLocations)
    XCTAssertEqual(
      model.foregroundNavigationLocationController.state,
      .releaseBlocked(.syntheticTestOnly)
    )
    XCTAssertNil(model.presentationProjection)
    XCTAssertEqual(model.presentationState, .awaitingGuidanceFrame)

    await model.process(
      [makeLocation(longitude: 139.75925, timestamp: 1_000)],
      receivedAt: Date(timeIntervalSince1970: 1_000)
    )
    XCTAssertEqual(model.snapshot?.journeyPhase, .entryTransition)
    XCTAssertEqual(
      model.inputState,
      .entryUpdated(status: .observing, rejection: nil)
    )

    await model.process(
      [makeLocation(longitude: 139.75975, timestamp: 1_001)],
      receivedAt: Date(timeIntervalSince1970: 1_001)
    )
    XCTAssertEqual(model.snapshot?.journeyPhase, .strictRoute)
    XCTAssertTrue(try XCTUnwrap(model.snapshot).strictRouteAutoCommitAllowed)
    XCTAssertNil(model.presentationProjection)
    XCTAssertEqual(
      model.inputState,
      .entryUpdated(status: .strictRouteEntered, rejection: nil)
    )

    await model.process(
      [makeLocation(longitude: 139.76025, timestamp: 1_002)],
      receivedAt: Date(timeIntervalSince1970: 1_002)
    )
    guard case .matcherUpdated(let confidence, _) = model.inputState else {
      XCTFail("Expected an atomic matcher update, got \(model.inputState)")
      return
    }
    XCTAssertEqual(confidence, .high)
    XCTAssertEqual(model.snapshot?.journeyPhase, .strictRoute)
    let projection = try XCTUnwrap(model.presentationProjection)
    XCTAssertEqual(model.presentationState, .ready)
    XCTAssertEqual(projection.iPhone.routePlanID, model.routePlanID)
    XCTAssertEqual(
      projection.iPhone.currentOccurrenceID,
      model.snapshot?.currentOccurrenceID
    )
    XCTAssertEqual(
      projection.carPlay.currentOccurrenceID,
      projection.iPhone.currentOccurrenceID
    )
    XCTAssertEqual(
      projection.carPlay.nextMovementOccurrenceID,
      projection.iPhone.nextMovementOccurrenceID
    )
    XCTAssertEqual(
      projection.iPhone.guidancePromptID,
      "test.prompt.loop-1"
    )
    XCTAssertTrue(projection.voice.shouldSpeak)
    XCTAssertEqual(
      projection.iPhone.passage.evidence,
      .noKnownConflictRealtimeUnconfirmed
    )
    XCTAssertFalse(projection.iPhone.passage.usesPositiveOpenColor)
    XCTAssertEqual(speechOutput.commands.count, 1)
    let speech = try XCTUnwrap(speechOutput.commands.first)
    XCTAssertEqual(speech.routePlanID, model.routePlanID)
    XCTAssertEqual(speech.languageCode, "ja-JP")
    XCTAssertEqual(speech.spokenText, "左側を進んでください")
    XCTAssertEqual(speech.identity.promptID, "test.prompt.loop-1")
    XCTAssertEqual(
      model.speechStatus,
      .speaking(speech.identity)
    )

    speechOutput.beginInterruption()
    XCTAssertEqual(model.speechStatus, .interrupted)
    speechOutput.endInterruption()
    XCTAssertEqual(model.speechStatus, .idle)

    await model.process(
      [makeLocation(longitude: 139.76025, timestamp: 1_003)],
      receivedAt: Date(timeIntervalSince1970: 1_003)
    )
    XCTAssertEqual(speechOutput.commands.count, 1)
    XCTAssertFalse(
      try XCTUnwrap(model.presentationProjection).voice.shouldSpeak
    )
    XCTAssertEqual(
      model.presentationProjection?.iPhone.guidancePromptID,
      "test.prompt.loop-1"
    )
  }

  @MainActor
  func testDeterministicPreviewTracePublishesActorOwnedPhoneProjection() async throws {
    let speechOutput = RecordingGuidanceSpeechOutput()
    let model = try SyntheticProductRuntimeModel(
      fixture: SyntheticProductRuntimeFixture.bundled(),
      sourceEvidenceProvider: FixedSourceEvidenceProvider(isSimulated: false),
      speechOutput: speechOutput
    )
    await model.activate()

    XCTAssertTrue(model.canRunDeterministicPreviewTrace)
    await model.runDeterministicPreviewTrace()

    XCTAssertEqual(model.snapshot?.journeyPhase, .strictRoute)
    XCTAssertFalse(model.canRunDeterministicPreviewTrace)
    XCTAssertEqual(model.presentationState, .ready)
    let projection = try XCTUnwrap(model.presentationProjection)
    XCTAssertTrue(projection.iPhone.isPrimarySurface)
    XCTAssertFalse(projection.carPlay.isPrimarySurface)
    XCTAssertEqual(
      projection.iPhone.currentOccurrenceID,
      projection.carPlay.currentOccurrenceID
    )
    XCTAssertEqual(
      projection.iPhone.nextMovementOccurrenceID,
      projection.carPlay.nextMovementOccurrenceID
    )
    XCTAssertEqual(speechOutput.commands.count, 1)

    await model.runDeterministicPreviewTrace()
    XCTAssertEqual(
      model.inputState,
      .pipelineRejected("SYNTHETIC_TRACE_REQUIRES_FRESH_PLANNING")
    )
    XCTAssertEqual(speechOutput.commands.count, 1)
  }

  @MainActor
  func testLanguageSelectionProviderControlsOneAtomicProjection() async throws {
    let speechOutput = RecordingGuidanceSpeechOutput()
    let model = try SyntheticProductRuntimeModel(
      fixture: SyntheticProductRuntimeFixture.bundled(),
      sourceEvidenceProvider: FixedSourceEvidenceProvider(isSimulated: false),
      speechOutput: speechOutput,
      languageSelectionProvider: {
        NavigationLanguageSelection(
          interfaceLocale: .english,
          guidanceVoiceLocale: .simplifiedChinese
        )
      }
    )
    await model.activate()

    await model.runDeterministicPreviewTrace()

    let projection = try XCTUnwrap(model.presentationProjection)
    XCTAssertEqual(projection.interfaceLocale, .english)
    XCTAssertEqual(projection.voice.locale, .simplifiedChinese)
    XCTAssertEqual(projection.iPhone.localizedDisplayText, "Keep left")
    let command = try XCTUnwrap(speechOutput.commands.first)
    XCTAssertEqual(command.languageCode, "zh-CN")
    XCTAssertEqual(command.spokenText, "请保持左侧")
  }

  @MainActor
  func testUnavailableInstalledVoiceBlocksWithoutRetryingThePrompt() async throws {
    let speechOutput = FailingGuidanceSpeechOutput()
    let model = try SyntheticProductRuntimeModel(
      fixture: SyntheticProductRuntimeFixture.bundled(),
      sourceEvidenceProvider: FixedSourceEvidenceProvider(isSimulated: false),
      speechOutput: speechOutput
    )
    await model.activate()

    for (longitude, timestamp) in [
      (139.75925, 1_000.0),
      (139.75975, 1_001.0),
      (139.76025, 1_002.0),
      (139.76025, 1_003.0),
    ] {
      await model.process(
        [makeLocation(longitude: longitude, timestamp: timestamp)],
        receivedAt: Date(timeIntervalSince1970: timestamp)
      )
    }

    XCTAssertEqual(model.speechStatus, .failed(.voiceUnavailable))
    XCTAssertEqual(speechOutput.attemptCount, 1)
  }

  @MainActor
  func testBackgroundCheckpointRestoresWithoutPositionOrPromptReplay() async throws {
    let store = MemoryNavigationCheckpointStore()
    let initialSpeechOutput = RecordingGuidanceSpeechOutput()
    let initial = try SyntheticProductRuntimeModel(
      fixture: SyntheticProductRuntimeFixture.bundled(),
      sourceEvidenceProvider: FixedSourceEvidenceProvider(isSimulated: false),
      speechOutput: initialSpeechOutput,
      checkpointStore: store
    )
    await initial.activate()
    for (longitude, timestamp) in [
      (139.75925, 1_000.0),
      (139.75975, 1_001.0),
      (139.76025, 1_002.0),
    ] {
      await initial.process(
        [makeLocation(longitude: longitude, timestamp: timestamp)],
        receivedAt: Date(timeIntervalSince1970: timestamp)
      )
    }
    XCTAssertEqual(initialSpeechOutput.commands.count, 1)

    await initial.handleScenePhase(
      .background,
      atMilliseconds: 1_100_000
    )
    XCTAssertEqual(initial.lifecycleState, .backgroundCheckpointed)
    XCTAssertEqual(initial.speechStatus, .stopped)
    let checkpoint = try XCTUnwrap(store.checkpoint)
    XCTAssertEqual(
      checkpoint.state.emittedGuidancePromptIDs,
      ["test.prompt.loop-1"]
    )

    let restoredSpeechOutput = RecordingGuidanceSpeechOutput()
    let restored = try SyntheticProductRuntimeModel(
      fixture: SyntheticProductRuntimeFixture.bundled(),
      sourceEvidenceProvider: FixedSourceEvidenceProvider(isSimulated: false),
      speechOutput: restoredSpeechOutput,
      checkpoint: checkpoint,
      checkpointStore: store
    )
    await restored.activate()

    XCTAssertEqual(restored.activation, .ready)
    XCTAssertEqual(
      restored.lifecycleState,
      .restoredReacquisitionRequired
    )
    XCTAssertEqual(restored.snapshot?.journeyPhase, .strictRoute)
    XCTAssertEqual(restored.snapshot?.locationConfidence, .lost)
    XCTAssertNil(restored.presentationProjection)
    XCTAssertEqual(restored.presentationState, .awaitingGuidanceFrame)
    XCTAssertEqual(
      restored.snapshot?.signalReacquisitionStatus,
      .pending
    )
    XCTAssertEqual(
      restored.snapshot?.emittedGuidancePromptIDs,
      ["test.prompt.loop-1"]
    )
    XCTAssertTrue(restoredSpeechOutput.commands.isEmpty)

    await restored.process(
      [makeLocation(longitude: 139.76025, timestamp: 1_101)],
      receivedAt: Date(timeIntervalSince1970: 1_101)
    )
    guard
      case .matcherUpdated(let confidence, let guidance) =
        restored.inputState
    else {
      XCTFail("Expected restoration matcher fence")
      return
    }
    XCTAssertEqual(confidence, .low)
    XCTAssertEqual(guidance, .insufficientMatcherEvidence)
    XCTAssertEqual(
      restored.snapshot?.currentOccurrenceID,
      checkpoint.state.currentOccurrenceID
    )
    XCTAssertTrue(restoredSpeechOutput.commands.isEmpty)

    await restored.process(
      [makeLocation(longitude: 139.76035, timestamp: 1_102)],
      receivedAt: Date(timeIntervalSince1970: 1_102)
    )
    XCTAssertEqual(restored.lifecycleState, .foreground)
    XCTAssertEqual(
      restored.snapshot?.signalReacquisitionStatus,
      .confirmed
    )
    XCTAssertTrue(restoredSpeechOutput.commands.isEmpty)
  }

  @MainActor
  func testCheckpointLoadFailureBlocksRuntimeActivation() async throws {
    let directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
      try? FileManager.default.removeItem(at: directoryURL)
    }
    let store = try FileNavigationSessionCheckpointStore(
      directoryURL: directoryURL
    )
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    try Data("{\"schema_version\":".utf8).write(to: store.fileURL)

    let model = try SyntheticProductRuntimeModel(
      sourceEvidenceProvider: FixedSourceEvidenceProvider(
        isSimulated: false
      ),
      speechOutput: RecordingGuidanceSpeechOutput(),
      checkpointStore: store
    )

    XCTAssertEqual(
      model.activation,
      .failed("CHECKPOINT_REJECTED")
    )
    XCTAssertEqual(
      model.lifecycleState,
      .checkpointRejected("CHECKPOINT_DECODE_FAILED")
    )
    XCTAssertEqual(
      model.presentationState,
      .blocked("CHECKPOINT_DECODE_FAILED")
    )

    await model.activate()
    XCTAssertEqual(
      model.activation,
      .failed("CHECKPOINT_REJECTED")
    )
    XCTAssertNil(model.snapshot)
  }

  @MainActor
  func testSoftwareSimulationIsRejectedBeforeEntryAdmission() async throws {
    let model = try SyntheticProductRuntimeModel(
      fixture: SyntheticProductRuntimeFixture.bundled(),
      sourceEvidenceProvider: FixedSourceEvidenceProvider(isSimulated: true)
    )
    await model.activate()

    await model.process(
      [makeLocation(longitude: 139.75925, timestamp: 1_000)],
      receivedAt: Date(timeIntervalSince1970: 1_000)
    )

    XCTAssertEqual(
      model.inputState,
      .adapterRejected(
        CoreLocationObservationRejectionReason.simulatedLocationRejected.rawValue
      )
    )
    XCTAssertEqual(model.snapshot?.journeyPhase, .planning)
    XCTAssertFalse(try XCTUnwrap(model.snapshot).strictRouteAutoCommitAllowed)
  }

  private func makeLocation(
    longitude: Double,
    timestamp: TimeInterval
  ) -> CLLocation {
    CLLocation(
      coordinate: CLLocationCoordinate2D(
        latitude: 35.68,
        longitude: longitude
      ),
      altitude: 0,
      horizontalAccuracy: 5,
      verticalAccuracy: 5,
      course: 90,
      courseAccuracy: 2,
      speed: 10,
      speedAccuracy: 1,
      timestamp: Date(timeIntervalSince1970: timestamp)
    )
  }

  private struct FixedSourceEvidenceProvider:
    CoreLocationSourceEvidenceProviding
  {
    let isSimulated: Bool

    func evidence(for _: CLLocation) -> CoreLocationSourceEvidence {
      CoreLocationSourceEvidence(
        deliverySource: .deviceOrUndisclosed,
        sourceInformationAvailable: true,
        isSimulatedBySoftware: isSimulated
      )
    }
  }

  @MainActor
  private final class RecordingGuidanceSpeechOutput:
    GuidanceSpeechOutput
  {
    var eventHandler: ((GuidanceSpeechOutputEvent) -> Void)?
    private(set) var commands: [GuidanceSpeechCommand] = []

    func speak(_ command: GuidanceSpeechCommand) {
      commands.append(command)
      eventHandler?(.didStart(command.identity))
    }

    func stop() {
      guard let identity = commands.last?.identity else { return }
      eventHandler?(.didCancel(identity))
    }

    func beginInterruption() {
      eventHandler?(.interruptionBegan)
    }

    func endInterruption() {
      eventHandler?(.interruptionEnded)
    }
  }

  @MainActor
  private final class FailingGuidanceSpeechOutput:
    GuidanceSpeechOutput
  {
    var eventHandler: ((GuidanceSpeechOutputEvent) -> Void)?
    private(set) var attemptCount = 0

    func speak(_ command: GuidanceSpeechCommand) throws {
      attemptCount += 1
      throw GuidanceSpeechOutputError.voiceUnavailable(
        command.languageCode
      )
    }

    func stop() {}
  }

  @MainActor
  private final class MemoryNavigationCheckpointStore:
    NavigationSessionCheckpointStoring
  {
    var checkpoint: NavigationSessionCheckpoint?

    func load() throws -> NavigationSessionCheckpoint? {
      checkpoint
    }

    func save(_ checkpoint: NavigationSessionCheckpoint) throws {
      self.checkpoint = checkpoint
    }

    func remove() throws {
      checkpoint = nil
    }
  }

}
