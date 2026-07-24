import Combine
import CoreLocation
import Foundation
import KaidoAppleAdapters
import KaidoDomain
import KaidoNavigation
import KaidoPresentation

enum SyntheticProductRuntimeActivation: Equatable, Sendable {
  case validating
  case ready
  case failed(String)

  var label: String {
    switch self {
    case .validating:
      "VALIDATING"
    case .ready:
      "RUNTIME READY"
    case .failed:
      "BLOCKED"
    }
  }
}

enum SyntheticProductRuntimeInputState: Equatable, Sendable {
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

@MainActor
final class SyntheticProductRuntimeModel: ObservableObject {
  @Published private(set) var activation: SyntheticProductRuntimeActivation =
    .validating
  @Published private(set) var snapshot: NavigationSnapshot?
  @Published private(set) var inputState: SyntheticProductRuntimeInputState =
    .disconnected
  @Published private(set) var speechStatus: GuidanceSpeechCoordinatorStatus =
    .idle

  let fixture: SyntheticProductRuntimeFixture

  private let runtime: KaidoProductNavigationRuntime
  private var observationAdapter: CoreLocationObservationAdapter
  private var entryTransitionAdapter: CoreLocationEntryTransitionAdapter
  private let speechCoordinator: GuidanceSpeechCoordinator

  init(
    fixture: SyntheticProductRuntimeFixture,
    sourceEvidenceProvider: any CoreLocationSourceEvidenceProviding =
      SystemCoreLocationSourceEvidenceProvider(),
    speechOutput: (any GuidanceSpeechOutput)? = nil
  ) throws {
    self.fixture = fixture
    runtime = try KaidoProductNavigationRuntime(release: fixture.release)
    observationAdapter = try CoreLocationObservationAdapter(
      sessionID: "synthetic-product-runtime-preview",
      simulatedLocationPolicy: .reject,
      carPlayConnectionContext: .disconnected,
      sourceEvidenceProvider: sourceEvidenceProvider
    )
    entryTransitionAdapter = try CoreLocationEntryTransitionAdapter(
      context: runtime.entryTransitionAdmissionContext
    )
    speechCoordinator = try GuidanceSpeechCoordinator(
      expectedRoutePlanID: runtime.routePlanID,
      output: speechOutput ?? AVSpeechGuidanceOutput()
    )
    speechCoordinator.statusDidChange = { [weak self] status in
      self?.speechStatus = status
    }
  }

  convenience init(
    bundle: Bundle = .main,
    sourceEvidenceProvider: any CoreLocationSourceEvidenceProviding =
      SystemCoreLocationSourceEvidenceProvider(),
    speechOutput: (any GuidanceSpeechOutput)? = nil
  ) throws {
    try self.init(
      fixture: SyntheticProductRuntimeFixture.bundled(in: bundle),
      sourceEvidenceProvider: sourceEvidenceProvider,
      speechOutput: speechOutput
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
    fixture.release.navigation.bundle.routePlan.occurrences.count
  }

  var corridorEdgeCount: Int {
    runtime.entryTransitionAdmissionContext.matcherCorridor.edges.count
  }

  var entryTransitionEdgeCount: Int {
    runtime.entryTransitionAdmissionContext.entryTransition.directedEdgeIDs.count
  }

  var isRealRoadAuthority: Bool {
    false
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
    guard
      started.activeRoutePlanID == routePlanID,
      started.currentOccurrenceID
        == fixture.release.navigation.bundle.routePlan.occurrences.first?.id,
      started.journeyPhase == .planning,
      !started.strictRouteAutoCommitAllowed
    else {
      activation = .failed("INITIAL_RUNTIME_SNAPSHOT_IDENTITY_DRIFT")
      snapshot = nil
      return
    }
    snapshot = started
    activation = .ready
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
        inputState = .matcherUpdated(
          confidence: update.matcherEstimate.confidence,
          guidance: update.guidanceProgressState
        )
        scheduleSpeech(from: update)
      case .completed:
        inputState = .pipelineRejected("JOURNEY_ALREADY_COMPLETED")
      }
    } catch {
      inputState = .pipelineRejected(Self.errorCode(error))
    }
  }

  private func scheduleSpeech(from update: NavigationSessionUpdate) {
    guard
      let frame = update.navigationSnapshot.activeGuidanceFrame,
      let emission = update.guidancePromptEmission
    else {
      return
    }
    do {
      let projection = try NavigationPresentationProjector.project(
        NavigationPresentationRequest(
          snapshot: update.navigationSnapshot,
          networkSnapshotID: runtime.networkSnapshotID,
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
      speechStatus = speechCoordinator.submit(projection)
    } catch {
      speechStatus = .invalidProjection
    }
  }

  private static func errorCode(_ error: Error) -> String {
    String(describing: error).uppercased()
  }
}
