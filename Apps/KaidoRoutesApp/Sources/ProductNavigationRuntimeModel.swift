import Combine
import CoreLocation
import Foundation
import KaidoAppleAdapters
import KaidoDomain
import KaidoNavigation
import KaidoPresentation

/// Activation and input state shared by synthetic proof and released-road use.
enum ProductNavigationRuntimeActivation: Equatable, Sendable {
  case validating
  case ready
  case ended
  case failed(String)

  var label: String {
    switch self {
    case .validating:
      "VALIDATING"
    case .ready:
      "RUNTIME READY"
    case .ended:
      "RUNTIME ENDED"
    case .failed:
      "BLOCKED"
    }
  }
}

enum ProductNavigationRuntimeInputState: Equatable, Sendable {
  case disconnected
  case adapterRejected(String)
  case entryUpdated(
    status: EntryTransitionAdmissionStatus,
    rejection: EntryTransitionEvidenceRejectionReason?
  )
  case matcherUpdated(
    confidence: MatcherConfidence,
    guidance: NavigationSessionGuidanceProgressState
  )
  case pipelineRejected(String)

  var label: String {
    switch self {
    case .disconnected:
      "INPUT DISCONNECTED"
    case .adapterRejected:
      "ADAPTER REJECTED"
    case .entryUpdated(let status, _):
      "ENTRY · \(status.rawValue)"
    case .matcherUpdated(let confidence, _):
      "MATCHER · \(confidence.rawValue)"
    case .pipelineRejected:
      "PIPELINE BLOCKED"
    }
  }

  var detail: String {
    switch self {
    case .disconnected:
      "No CLLocationManager is attached to this preview."
    case .adapterRejected(let reason):
      reason
    case .entryUpdated(_, let rejection):
      rejection?.rawValue ?? "RELEASE_BOUND_ENTRY_EVIDENCE"
    case .matcherUpdated(_, let guidance):
      guidance.rawValue
    case .pipelineRejected(let reason):
      reason
    }
  }
}

enum ProductNavigationRuntimeScenePhase: Equatable, Sendable {
  case active
  case inactive
  case background
}

enum ProductNavigationRuntimeLifecycleState: Equatable, Sendable {
  case foreground
  case restoredReacquisitionRequired
  case inactiveCheckpointed
  case backgroundCheckpointed
  case inactiveUnpersisted
  case backgroundUnpersisted
  case checkpointFailed(String)
  case checkpointRejected(String)
}

enum ProductNavigationRuntimePresentationState: Equatable, Sendable {
  case awaitingGuidanceFrame
  case ready
  case blocked(String)

  var label: String {
    switch self {
    case .awaitingGuidanceFrame:
      "WAITING FOR ACTOR FRAME"
    case .ready:
      "ACTOR FRAME READY"
    case .blocked:
      "PROJECTION BLOCKED"
    }
  }

  var detail: String {
    switch self {
    case .awaitingGuidanceFrame:
      "SwiftUI has no guidance semantics until the actor publishes an active frame."
    case .ready:
      "Phone, CarPlay, and voice values came from one atomic NavigationSession update."
    case .blocked(let code):
      code
    }
  }
}

enum ProductNavigationRuntimeModelError: Error, Equatable, Sendable {
  case invalidReleasedEntryRole
  case releasedAuthorityMissing
}

enum ProductNavigationRuntimeSimulationPreset: String, CaseIterable, Sendable {
  case clean = "CLEAN"
  case gpsDrift = "GPS_DRIFT"
  case signalGap = "SIGNAL_GAP"
  case poorAccuracy = "POOR_ACCURACY"
}

@MainActor
final class ProductNavigationRuntimeModel: ObservableObject {
  @Published private(set) var activation: ProductNavigationRuntimeActivation =
    .validating
  @Published private(set) var snapshot: NavigationSnapshot?
  @Published private(set) var inputState: ProductNavigationRuntimeInputState =
    .disconnected
  @Published private(set) var speechStatus: GuidanceSpeechCoordinatorStatus =
    .idle
  @Published private(set) var speechVoiceProfile: GuidanceSpeechVoiceProfile?
  @Published private(set) var lifecycleState: ProductNavigationRuntimeLifecycleState = .foreground
  @Published private(set) var presentationProjection: NavigationPresentationProjection?
  @Published private(set) var presentationState: ProductNavigationRuntimePresentationState =
    .awaitingGuidanceFrame
  @Published private(set) var topologyPositionEvidence: ProductTopologyPositionEvidence?
  @Published private(set) var isDeterministicPreviewTraceRunning = false
  @Published private(set) var simulationStatus: NavigationDriveSimulationStatus?
  @Published private(set) var simulationPreset: ProductNavigationRuntimeSimulationPreset = .clean
  @Published private(set) var simulationFailureCode: String?

  let syntheticFixture: SyntheticProductRuntimeFixture?
  lazy var foregroundNavigationLocationController: ForegroundNavigationLocationController = {
    do {
      return try ForegroundNavigationLocationController(
        authority: foregroundNavigationLocationAuthority,
        consumer: self
      )
    } catch {
      preconditionFailure(
        "Invalid product runtime location authority: \(error)"
      )
    }
  }()

  private let runtime: KaidoProductNavigationRuntime
  private let release: KaidoProductRelease
  private let admittedLiveInputAuthority: KaidoForegroundLiveInputAuthority?
  private var observationAdapter: CoreLocationObservationAdapter
  private var entryTransitionAdapter: CoreLocationEntryTransitionAdapter
  private let speechCoordinator: GuidanceSpeechCoordinator
  private let languageSelectionProvider: () -> NavigationLanguageSelection
  private let checkpointStore: (any NavigationSessionCheckpointStoring)?
  private var driveSimulator: NavigationDriveSimulator?
  private var scenePhase: ProductNavigationRuntimeScenePhase = .active
  private var lifecycleOperationID = 0
  private var simulationPlaybackGeneration = 0

  convenience init(
    fixture: SyntheticProductRuntimeFixture,
    sourceEvidenceProvider: any CoreLocationSourceEvidenceProviding =
      SystemCoreLocationSourceEvidenceProvider(),
    speechOutput: (any GuidanceSpeechOutput)? = nil,
    languageSelectionProvider: @escaping () -> NavigationLanguageSelection = {
      NavigationLanguageSelection(
        interfaceLocale: .simplifiedChinese,
        guidanceVoiceLocale: .japanese
      )
    },
    checkpoint: NavigationSessionCheckpoint? = nil,
    checkpointStore: (
      any NavigationSessionCheckpointStoring
    )? = nil,
    checkpointLoadFailureCode: String? = nil
  ) throws {
    try self.init(
      release: fixture.release,
      syntheticFixture: fixture,
      admittedLiveInputAuthority: nil,
      observationSessionID: "synthetic-product-runtime-preview",
      sourceEvidenceProvider: sourceEvidenceProvider,
      speechOutput: speechOutput,
      languageSelectionProvider: languageSelectionProvider,
      checkpoint: checkpoint,
      checkpointStore: checkpointStore,
      checkpointLoadFailureCode: checkpointLoadFailureCode
    )
  }

  private init(
    release: KaidoProductRelease,
    syntheticFixture: SyntheticProductRuntimeFixture?,
    admittedLiveInputAuthority: KaidoForegroundLiveInputAuthority?,
    observationSessionID: String,
    sourceEvidenceProvider: any CoreLocationSourceEvidenceProviding,
    speechOutput: (any GuidanceSpeechOutput)?,
    languageSelectionProvider: @escaping () -> NavigationLanguageSelection,
    checkpoint: NavigationSessionCheckpoint?,
    checkpointStore: (any NavigationSessionCheckpointStoring)?,
    checkpointLoadFailureCode: String?
  ) throws {
    self.release = release
    self.syntheticFixture = syntheticFixture
    self.admittedLiveInputAuthority = admittedLiveInputAuthority
    self.checkpointStore = checkpointStore
    self.languageSelectionProvider = languageSelectionProvider
    let restoredRuntime: KaidoProductNavigationRuntime
    var checkpointFailureCode = checkpointLoadFailureCode
    if let checkpoint {
      do {
        restoredRuntime = try KaidoProductNavigationRuntime(
          release: release,
          checkpoint: checkpoint
        )
      } catch {
        restoredRuntime = try KaidoProductNavigationRuntime(
          release: release
        )
        checkpointFailureCode = Self.checkpointErrorCode(error)
      }
    } else {
      restoredRuntime = try KaidoProductNavigationRuntime(
        release: release
      )
    }
    runtime = restoredRuntime
    observationAdapter = try CoreLocationObservationAdapter(
      sessionID: observationSessionID,
      simulatedLocationPolicy: .reject,
      carPlayConnectionContext: .disconnected,
      sourceEvidenceProvider: sourceEvidenceProvider
    )
    entryTransitionAdapter = try CoreLocationEntryTransitionAdapter(
      context: runtime.entryTransitionAdmissionContext
    )
    let resolvedSpeechOutput = speechOutput ?? AVSpeechGuidanceOutput()
    speechCoordinator = try GuidanceSpeechCoordinator(
      expectedRoutePlanID: runtime.routePlanID,
      output: resolvedSpeechOutput
    )
    speechVoiceProfile = resolvedSpeechOutput.selectedVoiceProfile
    speechCoordinator.statusDidChange = { [weak self] status in
      self?.speechStatus = status
      self?.speechVoiceProfile = self?.speechCoordinator.selectedVoiceProfile
    }
    if let checkpointFailureCode {
      activation = .failed("CHECKPOINT_REJECTED")
      lifecycleState = .checkpointRejected(checkpointFailureCode)
      presentationState = .blocked(checkpointFailureCode)
    }
    driveSimulator = try NavigationDriveSimulator(
      release: release,
      configuration: Self.simulationConfiguration(
        preset: .clean,
        release: release
      ),
      speed: .realtime
    )
  }

  convenience init(
    bundle: Bundle = .main,
    sourceEvidenceProvider: any CoreLocationSourceEvidenceProviding =
      SystemCoreLocationSourceEvidenceProvider(),
    speechOutput: (any GuidanceSpeechOutput)? = nil,
    languageSelectionProvider: @escaping () -> NavigationLanguageSelection = {
      NavigationLanguageSelection(
        interfaceLocale: .simplifiedChinese,
        guidanceVoiceLocale: .japanese
      )
    },
    checkpointStore: (
      any NavigationSessionCheckpointStoring
    )? = nil
  ) throws {
    let checkpoint: NavigationSessionCheckpoint?
    let checkpointLoadFailureCode: String?
    do {
      checkpoint = try checkpointStore?.load()
      checkpointLoadFailureCode = nil
    } catch {
      checkpoint = nil
      checkpointLoadFailureCode = Self.checkpointErrorCode(error)
    }
    try self.init(
      fixture: SyntheticProductRuntimeFixture.bundled(in: bundle),
      sourceEvidenceProvider: sourceEvidenceProvider,
      speechOutput: speechOutput,
      languageSelectionProvider: languageSelectionProvider,
      checkpoint: checkpoint,
      checkpointStore: checkpointStore,
      checkpointLoadFailureCode: checkpointLoadFailureCode
    )
  }

  convenience init(
    releasedEntry: BundledProductReleaseEntry,
    sourceEvidenceProvider: any CoreLocationSourceEvidenceProviding =
      SystemCoreLocationSourceEvidenceProvider(),
    speechOutput: (any GuidanceSpeechOutput)? = nil,
    languageSelectionProvider: @escaping () -> NavigationLanguageSelection,
    checkpointStore: (any NavigationSessionCheckpointStoring)? = nil
  ) throws {
    guard releasedEntry.descriptor.role == .foregroundNavigation else {
      throw ProductNavigationRuntimeModelError.invalidReleasedEntryRole
    }
    guard
      let authority = releasedEntry.release.foregroundLiveInputAuthority
    else {
      throw ProductNavigationRuntimeModelError.releasedAuthorityMissing
    }
    let checkpoint: NavigationSessionCheckpoint?
    let checkpointLoadFailureCode: String?
    do {
      checkpoint = try checkpointStore?.load()
      checkpointLoadFailureCode = nil
    } catch {
      checkpoint = nil
      checkpointLoadFailureCode = Self.checkpointErrorCode(error)
    }
    try self.init(
      release: releasedEntry.release,
      syntheticFixture: nil,
      admittedLiveInputAuthority: authority,
      observationSessionID: releasedEntry.release.releaseID,
      sourceEvidenceProvider: sourceEvidenceProvider,
      speechOutput: speechOutput,
      languageSelectionProvider: languageSelectionProvider,
      checkpoint: checkpoint,
      checkpointStore: checkpointStore,
      checkpointLoadFailureCode: checkpointLoadFailureCode
    )
  }

  var productReleaseID: String {
    runtime.productReleaseID
  }

  var navigationReleaseID: String {
    runtime.navigationReleaseID
  }

  var routePlanID: String {
    runtime.routePlanID
  }

  var networkSnapshotID: String {
    runtime.networkSnapshotID
  }

  var routeOccurrenceCount: Int {
    release.navigation.bundle.routePlan.occurrences.count
  }

  var routeAtlasOverlayPresentation: ReleasedRouteAtlasOverlayPresentation {
    do {
      return .ready(
        projection: try RouteAtlasJourneyProjector.project(
          release: release.routeAtlas,
          navigationSnapshot: snapshot
        ),
        isRealRoadAuthority: isRealRoadAuthority
      )
    } catch {
      return .blocked(releasedRouteAtlasOverlayErrorCode(error))
    }
  }

  var geographicMapPresentation: ProductGeographicMapPresentation? {
    ProductGeographicMapPresentation.make(
      corridor: release.navigation.bundle.matcherCorridor,
      evidence: topologyPositionEvidence
    )
  }

  var topologyFacilityPresentation: ProductTopologyFacilityPresentation? {
    ProductTopologyFacilityPresentation.make(release: release)
  }

  var corridorEdgeCount: Int {
    runtime.entryTransitionAdmissionContext.matcherCorridor.edges.count
  }

  var entryTransitionEdgeCount: Int {
    runtime.entryTransitionAdmissionContext.entryTransition.directedEdgeIDs.count
  }

  var isRealRoadAuthority: Bool {
    admittedLiveInputAuthority != nil
  }

  var foregroundNavigationLocationAuthority: ForegroundNavigationLocationAuthority {
    if let admittedLiveInputAuthority {
      return .releasedProduct(admittedLiveInputAuthority)
    }
    return .blocked(
      identity: foregroundNavigationRuntimeIdentity,
      reason: .syntheticTestOnly
    )
  }

  var canRunDeterministicPreviewTrace: Bool {
    syntheticFixture != nil
      && activation == .ready
      && snapshot?.journeyPhase == .planning
      && acceptsLiveInput
      && !isDeterministicPreviewTraceRunning
  }

  var canPlayNavigationSimulation: Bool {
    guard activation == .ready, let simulationStatus else { return false }
    return simulationStatus.state == .ready
      || simulationStatus.state == .paused
  }

  var canPauseNavigationSimulation: Bool {
    simulationStatus?.state == .playing
  }

  var canStepNavigationSimulation: Bool {
    guard activation == .ready, let simulationStatus else { return false }
    return simulationStatus.state != .playing
      && simulationStatus.state != .completed
  }

  var canResetNavigationSimulation: Bool {
    activation == .ready && driveSimulator != nil
  }

  var lifecycleStatusLabel: String {
    switch lifecycleState {
    case .foreground:
      "FOREGROUND"
    case .restoredReacquisitionRequired:
      "RESTORED · REACQUIRE"
    case .inactiveCheckpointed:
      "INACTIVE · SAVED"
    case .backgroundCheckpointed:
      "BACKGROUND · SAVED"
    case .inactiveUnpersisted:
      "INACTIVE · MEMORY ONLY"
    case .backgroundUnpersisted:
      "BACKGROUND · MEMORY ONLY"
    case .checkpointFailed:
      "SAVE BLOCKED"
    case .checkpointRejected:
      "RESTORE BLOCKED"
    }
  }

  var lifecycleStatusDetail: String {
    switch lifecycleState {
    case .foreground:
      "Scene is active; only fresh admitted input may update the actor."
    case .restoredReacquisitionRequired:
      "Progress and prompt ledger restored; measured position requires a fresh evidence window."
    case .inactiveCheckpointed:
      "Speech stopped and coordinate-free state saved atomically."
    case .backgroundCheckpointed:
      "Termination-safe checkpoint saved; background location is not enabled."
    case .inactiveUnpersisted:
      "Speech stopped; this deterministic preview has no checkpoint store."
    case .backgroundUnpersisted:
      "Speech stopped; this deterministic preview keeps no process state."
    case .checkpointFailed(let code), .checkpointRejected(let code):
      code
    }
  }

  var speechStatusLabel: String {
    switch speechStatus {
    case .idle:
      "IDLE"
    case .scheduled:
      "SCHEDULED"
    case .speaking:
      "SPEAKING"
    case .suppressed(let reason):
      "SUPPRESSED · \(reason.rawValue)"
    case .interrupted:
      "INTERRUPTED"
    case .stopped:
      "STOPPED"
    case .failed(let code):
      "BLOCKED · \(code.rawValue)"
    case .invalidProjection:
      "BLOCKED · INVALID PROJECTION"
    }
  }

  var speechStatusDetail: String {
    switch speechStatus {
    case .idle:
      "No transient guidance emission is active."
    case .scheduled(let identity), .speaking(let identity):
      "\(identity.promptID) · \(identity.anchorOccurrenceID)"
    case .suppressed(.notAuthorized):
      "A persistent guidance frame cannot authorize speech."
    case .suppressed(.duplicate):
      "The occurrence-scoped prompt was already consumed."
    case .suppressed(.interrupted):
      "The interrupted prompt was dropped without catch-up replay."
    case .suppressed(.stopped), .stopped:
      "The route speech lifecycle is stopped."
    case .interrupted:
      "Current speech was cancelled; interruption end will not replay it."
    case .failed(let code):
      code.rawValue
    case .invalidProjection:
      "Prompt, anchor, occurrence, or RoutePlan identity did not match."
    }
  }

  func activate() async {
    guard activation == .validating else { return }
    let started = await runtime.session.start()
    guard started.activeRoutePlanID == routePlanID else {
      activation = .failed("INITIAL_RUNTIME_SNAPSHOT_IDENTITY_DRIFT")
      snapshot = nil
      presentationState = .blocked("INITIAL_RUNTIME_SNAPSHOT_IDENTITY_DRIFT")
      return
    }
    if runtime.origin == .fresh {
      guard
        started.currentOccurrenceID
          == release.navigation.bundle.routePlan.occurrences.first?.id,
        started.journeyPhase == .planning,
        !started.strictRouteAutoCommitAllowed
      else {
        activation = .failed("INITIAL_RUNTIME_SNAPSHOT_IDENTITY_DRIFT")
        snapshot = nil
        presentationState = .blocked("INITIAL_RUNTIME_SNAPSHOT_IDENTITY_DRIFT")
        return
      }
      lifecycleState = .foreground
    } else {
      guard
        started.carPlayConnectionState == .disconnected,
        started.presentationSurface == .iPhone,
        started.locationConfidence == .lost
      else {
        activation = .failed("RESTORED_RUNTIME_TRANSIENT_STATE_DRIFT")
        snapshot = nil
        presentationState = .blocked("RESTORED_RUNTIME_TRANSIENT_STATE_DRIFT")
        return
      }
      lifecycleState =
        started.signalReacquisitionStatus == .pending
        ? .restoredReacquisitionRequired
        : .foreground
    }
    snapshot = started
    activation = .ready
    if let driveSimulator {
      simulationStatus = await driveSimulator.status
    }
    if scenePhase != .active {
      await handleScenePhase(scenePhase)
    }
  }

  func handleScenePhase(
    _ phase: ProductNavigationRuntimeScenePhase
  ) async {
    await handleScenePhase(
      phase,
      atMilliseconds: Self.currentTimeMilliseconds()
    )
  }

  func handleScenePhase(
    _ phase: ProductNavigationRuntimeScenePhase,
    atMilliseconds: Int
  ) async {
    scenePhase = phase
    lifecycleOperationID += 1
    let operationID = lifecycleOperationID
    guard activation == .ready else { return }
    switch phase {
    case .active:
      speechCoordinator.resume()
      if snapshot?.signalReacquisitionStatus == .pending {
        lifecycleState = .restoredReacquisitionRequired
      } else {
        lifecycleState = .foreground
      }
    case .inactive, .background:
      speechCoordinator.stop()
      guard let checkpointStore else {
        lifecycleState =
          phase == .inactive
          ? .inactiveUnpersisted
          : .backgroundUnpersisted
        return
      }
      do {
        if snapshot?.journeyPhase == .completed {
          try checkpointStore.remove()
        } else {
          let checkpoint = try await runtime.makeCheckpoint(
            savedAtMilliseconds: atMilliseconds
          )
          try checkpointStore.save(checkpoint)
        }
        if operationID == lifecycleOperationID {
          lifecycleState =
            phase == .inactive
            ? .inactiveCheckpointed
            : .backgroundCheckpointed
        }
      } catch {
        if operationID == lifecycleOperationID {
          lifecycleState = .checkpointFailed(
            Self.checkpointErrorCode(error)
          )
        }
      }
    }
  }

  func terminate() async -> Bool {
    await foregroundNavigationLocationController.stop()
    speechCoordinator.stop()
    if snapshot?.journeyPhase == .exitTransition {
      snapshot = await runtime.session.completeAtExitHandoff()
    }
    do {
      try checkpointStore?.remove()
    } catch {
      activation = .failed(Self.checkpointErrorCode(error))
      lifecycleState = .checkpointFailed(
        Self.checkpointErrorCode(error)
      )
      return false
    }
    activation = .ended
    snapshot = nil
    inputState = .disconnected
    presentationProjection = nil
    presentationState = .awaitingGuidanceFrame
    topologyPositionEvidence = nil
    return true
  }

  /// Connects an explicit foreground Core Location callback to the admitted
  /// product runtime. The model stores only actor output, never the locations.
  func process(
    _ locations: [CLLocation],
    receivedAt: Date = Date()
  ) async {
    guard activation == .ready else {
      inputState = .pipelineRejected("RUNTIME_NOT_READY")
      return
    }
    guard acceptsLiveInput else {
      inputState = .pipelineRejected("SCENE_NOT_ACTIVE")
      return
    }

    for result in observationAdapter.adapt(
      locations,
      receivedAt: receivedAt
    ) {
      switch result {
      case .rejected(let rejection):
        inputState = .adapterRejected(rejection.reason.rawValue)
      case .accepted(let envelope):
        await process(envelope)
      }
    }
  }

  /// Exercises the exact adapter-to-actor-to-presentation path with synthetic
  /// coordinates. This is an internal preview action and never attaches a
  /// CLLocationManager or grants real-road authority.
  func runDeterministicPreviewTrace() async {
    guard syntheticFixture != nil, canRunDeterministicPreviewTrace else {
      inputState = .pipelineRejected("SYNTHETIC_TRACE_REQUIRES_FRESH_PLANNING")
      return
    }
    isDeterministicPreviewTraceRunning = true
    defer {
      isDeterministicPreviewTraceRunning = false
    }
    for (longitude, timestamp) in [
      (139.75925, 1_000.0),
      (139.75975, 1_001.0),
      (139.76025, 1_002.0),
    ] {
      await process(
        [Self.previewLocation(longitude: longitude, timestamp: timestamp)],
        receivedAt: Date(timeIntervalSince1970: timestamp)
      )
    }
  }

  func playNavigationSimulation() async {
    guard let driveSimulator, canPlayNavigationSimulation else { return }
    simulationPlaybackGeneration += 1
    let generation = simulationPlaybackGeneration
    simulationFailureCode = nil
    simulationStatus = await driveSimulator.play()

    do {
      while generation == simulationPlaybackGeneration,
        await driveSimulator.status.state == .playing
      {
        let delay = await driveSimulator.delayBeforeNextEventMilliseconds() ?? 0
        if delay > 0 {
          try await Task.sleep(
            for: .milliseconds(delay)
          )
        }
        guard generation == simulationPlaybackGeneration,
          let result = try await driveSimulator.advanceIfPlaying()
        else {
          break
        }
        applySimulationResult(result)
      }
      simulationStatus = await driveSimulator.status
    } catch is CancellationError {
      simulationStatus = await driveSimulator.pause()
    } catch {
      simulationFailureCode = Self.errorCode(error)
      simulationStatus = await driveSimulator.pause()
      inputState = .pipelineRejected(
        simulationFailureCode ?? "SIMULATION_FAILED"
      )
    }
  }

  func pauseNavigationSimulation() async {
    guard let driveSimulator else { return }
    simulationPlaybackGeneration += 1
    simulationStatus = await driveSimulator.pause()
  }

  func stepNavigationSimulation() async {
    guard let driveSimulator, canStepNavigationSimulation else { return }
    simulationPlaybackGeneration += 1
    simulationFailureCode = nil
    do {
      if let result = try await driveSimulator.step() {
        applySimulationResult(result)
      }
      simulationStatus = await driveSimulator.status
    } catch {
      simulationFailureCode = Self.errorCode(error)
      inputState = .pipelineRejected(
        simulationFailureCode ?? "SIMULATION_FAILED"
      )
    }
  }

  func resetNavigationSimulation() async {
    guard let driveSimulator else { return }
    simulationPlaybackGeneration += 1
    speechCoordinator.stop()
    do {
      simulationStatus = try await driveSimulator.reset()
      snapshot = await driveSimulator.navigationSnapshot
      inputState = .disconnected
      presentationProjection = nil
      presentationState = .awaitingGuidanceFrame
      topologyPositionEvidence = nil
      simulationFailureCode = nil
    } catch {
      simulationFailureCode = Self.errorCode(error)
      inputState = .pipelineRejected(
        simulationFailureCode ?? "SIMULATION_RESET_FAILED"
      )
    }
  }

  func setNavigationSimulationSpeed(
    _ speed: NavigationDriveSimulationSpeed
  ) async {
    guard let driveSimulator else { return }
    simulationStatus = await driveSimulator.setSpeed(speed)
  }

  func selectNavigationSimulationPreset(
    _ preset: ProductNavigationRuntimeSimulationPreset
  ) async {
    guard syntheticFixture != nil else { return }
    simulationPlaybackGeneration += 1
    speechCoordinator.stop()
    do {
      let simulator = try NavigationDriveSimulator(
        release: release,
        configuration: Self.simulationConfiguration(
          preset: preset,
          release: release
        ),
        speed: simulationStatus?.speed ?? .fiveTimes
      )
      driveSimulator = simulator
      simulationPreset = preset
      simulationStatus = try await simulator.reset()
      snapshot = await simulator.navigationSnapshot
      inputState = .disconnected
      presentationProjection = nil
      presentationState = .awaitingGuidanceFrame
      topologyPositionEvidence = nil
      simulationFailureCode = nil
    } catch {
      simulationFailureCode = Self.errorCode(error)
      inputState = .pipelineRejected(
        simulationFailureCode ?? "SIMULATION_PRESET_FAILED"
      )
    }
  }

  /// Test helper that advances without wall-clock delays. Event timestamps and
  /// matcher behavior are identical to interactive playback.
  func runNavigationSimulationToEnd() async {
    guard let driveSimulator else { return }
    simulationPlaybackGeneration += 1
    simulationFailureCode = nil
    do {
      for result in try await driveSimulator.runToEnd() {
        applySimulationResult(result)
      }
      simulationStatus = await driveSimulator.status
    } catch {
      simulationFailureCode = Self.errorCode(error)
      inputState = .pipelineRejected(
        simulationFailureCode ?? "SIMULATION_FAILED"
      )
    }
  }

  private func process(_ envelope: CoreLocationObservationEnvelope) async {
    guard let snapshot else {
      inputState = .pipelineRejected("RUNTIME_SNAPSHOT_MISSING")
      return
    }

    do {
      switch snapshot.journeyPhase {
      case .planning, .approachToEntry, .entryTransition:
        let evidence = try entryTransitionAdapter.adapt(envelope)
        let update = try await runtime.session.observeEntryTransitionEvidence(
          evidence
        )
        self.snapshot = update.navigationSnapshot
        inputState = .entryUpdated(
          status: update.status,
          rejection: update.rejectionReason
        )
      case .strictRoute, .routeRecovery, .exitTransition, .surfaceEgress:
        let update = try await runtime.session.observe(envelope.observation)
        self.snapshot = update.navigationSnapshot
        updateTopologyPositionEvidence(from: update)
        if lifecycleState == .restoredReacquisitionRequired,
          update.navigationSnapshot.signalReacquisitionStatus == .confirmed
        {
          lifecycleState = .foreground
        }
        inputState = .matcherUpdated(
          confidence: update.matcherEstimate.confidence,
          guidance: update.guidanceProgressState
        )
        publishPresentationAndScheduleSpeech(from: update)
      case .completed:
        inputState = .pipelineRejected("JOURNEY_ALREADY_COMPLETED")
      }
    } catch {
      inputState = .pipelineRejected(Self.errorCode(error))
    }
  }

  private func publishPresentationAndScheduleSpeech(
    from update: NavigationSessionUpdate
  ) {
    guard let frame = update.navigationSnapshot.activeGuidanceFrame else {
      presentationProjection = nil
      presentationState = .awaitingGuidanceFrame
      return
    }
    do {
      let projection = try NavigationPresentationProjector.project(
        NavigationPresentationRequest(
          snapshot: update.navigationSnapshot,
          networkSnapshotID: runtime.networkSnapshotID,
          guidanceFrame: frame,
          promptEmission: update.guidancePromptEmission,
          languages: languageSelectionProvider(),
          passageEvidence: .noKnownConflictRealtimeUnconfirmed,
          drivingContext: PresentationDrivingContext(
            isVehicleMoving: true,
            isInsideDecisionZone: true
          )
        )
      )
      presentationProjection = projection
      presentationState = .ready
      if update.guidancePromptEmission != nil {
        speechStatus = speechCoordinator.submit(projection)
        speechVoiceProfile = speechCoordinator.selectedVoiceProfile
      }
    } catch {
      presentationProjection = nil
      presentationState = .blocked(Self.errorCode(error))
      if update.guidancePromptEmission != nil {
        speechStatus = .invalidProjection
      }
    }
  }

  private func applySimulationResult(
    _ result: NavigationDriveSimulationStepResult
  ) {
    snapshot = result.navigationSnapshot
    simulationStatus = result.status
    if let update = result.navigationUpdate {
      updateTopologyPositionEvidence(from: update)
      inputState = .matcherUpdated(
        confidence: update.matcherEstimate.confidence,
        guidance: update.guidanceProgressState
      )
      publishPresentationAndScheduleSpeech(from: update)
    } else if result.navigationSnapshot.activeGuidanceFrame == nil {
      presentationProjection = nil
      presentationState = .awaitingGuidanceFrame
    }
  }

  private func updateTopologyPositionEvidence(
    from update: NavigationSessionUpdate
  ) {
    topologyPositionEvidence = ProductTopologyPositionEvidence.admitted(
      estimate: update.matcherEstimate,
      snapshot: update.navigationSnapshot,
      routePlan: release.navigation.bundle.routePlan
    )
  }

  private var acceptsLiveInput: Bool {
    switch lifecycleState {
    case .foreground, .restoredReacquisitionRequired:
      true
    case .inactiveCheckpointed, .backgroundCheckpointed,
      .inactiveUnpersisted, .backgroundUnpersisted,
      .checkpointFailed, .checkpointRejected:
      false
    }
  }

  private static func currentTimeMilliseconds() -> Int {
    Int((Date().timeIntervalSince1970 * 1_000).rounded())
  }

  private static func previewLocation(
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

  private static func simulationConfiguration(
    preset: ProductNavigationRuntimeSimulationPreset,
    release: KaidoProductRelease
  ) -> NavigationDriveSimulationConfiguration {
    let occurrences = release.navigation.bundle.matcherCorridor.occurrences
    guard
      let target = occurrences.dropFirst().dropLast().first
        ?? occurrences.first
    else {
      return NavigationDriveSimulationConfiguration()
    }
    let anomaly: NavigationDriveSimulationAnomaly?
    switch preset {
    case .clean:
      anomaly = nil
    case .gpsDrift:
      anomaly = NavigationDriveSimulationAnomaly(
        occurrenceID: target.id,
        sampleIndex: 1,
        kind: .coordinateOffsetMeters(north: 45, east: 45)
      )
    case .signalGap:
      anomaly = NavigationDriveSimulationAnomaly(
        occurrenceID: target.id,
        sampleIndex: 1,
        kind: .signalGapBeforeMilliseconds(15_000)
      )
    case .poorAccuracy:
      anomaly = NavigationDriveSimulationAnomaly(
        occurrenceID: target.id,
        sampleIndex: 1,
        kind: .horizontalAccuracyMeters(80)
      )
    }
    return NavigationDriveSimulationConfiguration(
      sampleFractions: [0.15, 0.5, 0.85, 0.94],
      anomalies: [anomaly].compactMap { $0 },
      completesAtExitHandoff: true
    )
  }

  private static func errorCode(_ error: Error) -> String {
    String(describing: error).uppercased()
  }

  private static func checkpointErrorCode(_ error: Error) -> String {
    if let error = error as? NavigationSessionCheckpointStoreError {
      return error.code
    }
    if case NavigationSessionCheckpointError.invalid(let issues) = error {
      return issues.map(\.code).sorted().joined(separator: "+")
    }
    if error is DecodingError {
      return "CHECKPOINT_DECODE_FAILED"
    }
    return "CHECKPOINT_OPERATION_FAILED"
  }
}

extension ProductNavigationRuntimeModel: ForegroundNavigationLocationConsuming {
  var foregroundNavigationRuntimeIdentity: KaidoProductRuntimeIdentity {
    runtime.runtimeIdentity
  }

  var canConsumeForegroundNavigationLocations: Bool {
    isRealRoadAuthority && activation == .ready && acceptsLiveInput
  }

  func consumeForegroundNavigationLocations(
    _ locations: [CLLocation],
    receivedAt: Date
  ) async {
    await process(locations, receivedAt: receivedAt)
  }
}

typealias SyntheticProductRuntimeModel = ProductNavigationRuntimeModel
