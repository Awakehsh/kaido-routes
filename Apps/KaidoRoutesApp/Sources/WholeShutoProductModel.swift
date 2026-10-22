import Combine
import CoreLocation
import Foundation
import KaidoAppleAdapters
import KaidoDomain
import KaidoNavigation
import KaidoPresentation
import KaidoRouting
import Synchronization

enum WholeShutoJourneyPhase:
  String, Codable, Equatable, Sendable
{
  case planning = "PLANNING"
  case review = "REVIEW"
  case surfaceAccess = "SURFACE_ACCESS"
  case entryTransition = "ENTRY_TRANSITION"
  case expressway = "EXPRESSWAY"
  case exitTransition = "EXIT_TRANSITION"
  case surfaceEgress = "SURFACE_EGRESS"
  case completed = "COMPLETED"
}

private enum WholeShutoJourneyNotice: String {
  case started, enteredExpressway, positionLost, positionRecovered
  case rerouting, rejoined, exiting, resting, resumed, arrived, lapNotAdded
  case nearDestination, leftRouteRerouting, leftRouteEnded

  func text(locale: KaidoReleaseLocale) -> String {
    let words: (String, String, String)
    switch self {
    case .started:
      words = (
        "ナビを開始します。位置情報を確認しています。", "导航已开始，正在确认位置。", "Navigation started. Acquiring your position."
      )
    case .enteredExpressway:
      words = ("高速道路のルート案内を開始します。", "已进入高速路线导航。", "Expressway route guidance started.")
    case .positionLost:
      words = (
        "位置情報が不確かです。自動で再取得しています。", "定位暂不稳定，正在自动恢复。",
        "Position is uncertain. Reacquiring automatically."
      )
    case .positionRecovered: words = ("位置情報が復帰しました。", "定位已恢复。", "Position restored.")
    case .rerouting: words = ("ルートを再確認しています。", "正在重新确认路线。", "Rechecking the route.")
    case .rejoined: words = ("選択したルートに復帰しました。", "已回到所选路线。", "Rejoined the selected route.")
    case .exiting: words = ("出口ルートの案内を開始します。", "开始出口路线导航。", "Exit route guidance started.")
    case .resting: words = ("ナビを一時停止しました。", "导航已暂停。", "Navigation paused.")
    case .resumed:
      words = (
        "ナビを再開します。位置情報を確認しています。", "导航已恢复，正在确认位置。", "Navigation resumed. Acquiring your position."
      )
    case .arrived: words = ("ルートの走行が完了しました。", "本次路线已完成。", "Your route is complete.")
    case .lapNotAdded: words = ("周回を追加できませんでした。", "未能增加一圈。", "The lap could not be added.")
    case .nearDestination:
      words = ("目的地周辺です。案内を終了します。", "已在目的地附近，导航结束。", "You're near your destination. Guidance has ended.")
    case .leftRouteRerouting:
      words = ("ルートを外れました。新しいルートで案内します。", "已偏离路线，重新规划路线。", "You've left the route. Rerouting.")
    case .leftRouteEnded:
      words = ("ルートを外れました。案内を終了します。", "已偏离路线，导航结束。", "You've left the route. Guidance has ended.")
    }
    switch locale {
    case .japanese: return words.0
    case .simplifiedChinese: return words.1
    case .english: return words.2
    }
  }
}

extension WholeShutoProductModel: ForegroundNavigationLocationConsuming {
  var foregroundNavigationRuntimeIdentity: KaidoProductRuntimeIdentity {
    guard let activeLiveAdmission else {
      preconditionFailure(
        "Foreground location identity requested without live admission"
      )
    }
    return activeLiveAdmission.core.release.runtimeIdentity
  }

  var canConsumeForegroundNavigationLocations: Bool {
    isLiveDrive
      && isPlaying
      && activeLiveAdmission != nil
      && liveDriveSession != nil
      && liveObservationAdapter != nil
      && phase != .planning
      && phase != .review
      && phase != .completed
  }

  func consumeForegroundNavigationLocations(
    _ locations: [CLLocation],
    receivedAt: Date
  ) async {
    guard canConsumeForegroundNavigationLocations,
      var adapter = liveObservationAdapter
    else {
      return
    }
    let results = adapter.adapt(locations, receivedAt: receivedAt)
    liveObservationAdapter = adapter
    let generation = playbackGeneration
    for result in results {
      guard playbackGeneration == generation else { return }
      switch result {
      case .accepted(let envelope):
        await consumeLiveObservationForTesting(envelope)
      case .rejected(let rejection):
        speechCoordinator?.invalidateGuidance(keepingNotices: true)
        liveLocationState = .degraded
        liveLocationIssueCode = rejection.reason.rawValue
        matcherConfidence = .low
      }
    }
  }
}

enum WholeShutoMapMode:
  String, CaseIterable, Codable, Equatable, Sendable
{
  case geographic = "GEOGRAPHIC"
  case network = "NETWORK"
}

enum WholeShutoRouteSelectionSource:
  String, Codable, Equatable, Sendable
{
  case recommended = "RECOMMENDED"
  case custom = "CUSTOM"
  case circuit = "CIRCUIT"
}

enum WholeShutoDriveMode: String, Codable, Equatable, Sendable {
  case simulation = "SIMULATION"
  case live = "LIVE"
}

/// Where the driver's "I am already on the expressway" declaration stands.
///
/// Sensors cannot separate an elevated carriageway from the surface road
/// under it, so a drive started mid-route can never match the reviewed entry
/// ramp and would otherwise wait for it forever. The declaration is offered
/// only while the matcher's own estimate holds one plan occurrence on
/// consecutive fixes — where the car plausibly is on the route — and the
/// declaration is the driver's; the position stays the matcher's.
enum WholeShutoRouteJoinState: String, Equatable, Sendable {
  case unavailable = "UNAVAILABLE"
  case offered = "OFFERED"
  case resolving = "RESOLVING"
  case unresolved = "UNRESOLVED"
}

enum WholeShutoLiveLocationState: String, Equatable, Sendable {
  case inactive = "INACTIVE"
  case resumeRequired = "RESUME_REQUIRED"
  /// The driver stopped on purpose — a PA break, a call, a photo. The session
  /// and its occurrence survive; only the sensor and the voice go quiet.
  case resting = "RESTING"
  case awaitingAuthorization = "AWAITING_AUTHORIZATION"
  case acquiring = "ACQUIRING"
  case available = "AVAILABLE"
  case degraded = "DEGRADED"
  case stale = "STALE"
  case permissionDenied = "DENIED"
  case failed = "FAILED"
}

struct WholeShutoPlace: Codable, Equatable, Sendable {
  let title: String
  let coordinate: ShutoCoordinate
  var parkingAreaID: String? = nil
}

struct WholeShutoSurfaceRoute: Codable, Equatable, Sendable {
  let coordinates: [ShutoCoordinate]
  let distanceMeters: Double
  let expectedTravelTimeSeconds: Double
  let instructions: [String]
  let steps: [WholeShutoSurfaceRouteStep]?
  let guidanceLanguageCode: String?
  let hasHighways: Bool?
  let hasTolls: Bool?

  init(
    coordinates: [ShutoCoordinate],
    distanceMeters: Double,
    expectedTravelTimeSeconds: Double,
    instructions: [String],
    steps: [WholeShutoSurfaceRouteStep]? = nil,
    guidanceLanguageCode: String? = nil,
    hasHighways: Bool? = nil,
    hasTolls: Bool? = nil
  ) {
    self.coordinates = coordinates
    self.distanceMeters = distanceMeters
    self.expectedTravelTimeSeconds = expectedTravelTimeSeconds
    self.instructions = instructions
    self.steps = steps
    self.guidanceLanguageCode = guidanceLanguageCode
    self.hasHighways = hasHighways
    self.hasTolls = hasTolls
  }
}

struct WholeShutoSurfaceRouteStep: Codable, Equatable, Sendable {
  let instruction: String
  let distanceMeters: Double
}

struct WholeShutoRouteChoiceMetrics: Equatable, Sendable {
  let totalDistanceMeters: Double
  let expectedTravelTimeSeconds: Double
}

struct WholeShutoRouteProgressGeometry: Equatable, Sendable {
  let traveledCoordinates: [ShutoCoordinate]
  let remainingCoordinates: [ShutoCoordinate]
}

struct WholeShutoJunctionPrompt: Equatable, Identifiable, Sendable {
  let movementID: String
  let nameJA: String
  let incomingRouteID: String
  let outgoingRouteID: String
  let outgoingDirectionJA: String
  let branchSide: ShutoJunctionBranchSide
  let japaneseSignText: String
  let routeShields: [String]
  let laneGuidanceState: ShutoJunctionLaneGuidanceState
  let localizedJunctionNames: [KaidoReleaseLocale: String]
  let localizedContent: [KaidoReleaseLocale: LocalizedGuidanceContent]
  let checkedAt: String
  let coordinate: ShutoCoordinate
  let incomingOccurrenceID: String
  let outgoingOccurrenceID: String
  let progressFraction: Double

  var id: String {
    "\(movementID)|\(outgoingOccurrenceID)"
  }
}

enum WholeShutoPositionState: String, Equatable, Sendable {
  case unavailable = "UNAVAILABLE"
  case surfacePreview = "SURFACE_PREVIEW"
  case surfaceRoutePending = "SURFACE_ROUTE_PENDING"
  case boundaryTransition = "BOUNDARY_TRANSITION"
  case networkPreview = "NETWORK_PREVIEW"
  case networkDegraded = "NETWORK_DEGRADED"
  /// The driver parked and asked the drive to wait. Not a degraded position:
  /// there is no position because none was requested.
  case resting = "RESTING"
  case tunnelEstimated = "TUNNEL_ESTIMATED"
  case routeInterrupted = "ROUTE_INTERRUPTED"
  /// Off the plan just past its exit, where the street the exit leads to
  /// runs beside the road it leaves: neither taken nor missed yet.
  case confirmingExit = "CONFIRMING_EXIT"
  case completed = "COMPLETED"
}

enum WholeShutoJourneyEnding: String, Codable, CaseIterable {
  case returnToOrigin
  case exit
  case destination
}

struct WholeShutoParkingStopSelection: Codable, Equatable, Sendable {
  let baseRoutePlan: RoutePlan
  let parkingAreaIDs: [String]
}

struct WholeShutoJourneyCheckpoint: Codable, Equatable, Sendable {
  static let currentSchemaVersion = "2.0"

  let schemaVersion: String
  let networkSnapshotID: String
  let originQuery: String
  let destinationQuery: String
  let origin: WholeShutoPlace
  let destination: WholeShutoPlace
  let entryFacilityID: String
  let exitFacilityID: String?
  let routePlan: RoutePlan
  let preference: ShutoRoutePreference
  let routeSelectionSource: WholeShutoRouteSelectionSource
  let driveMode: WholeShutoDriveMode
  let phase: WholeShutoJourneyPhase
  let progressFraction: Double
  let runtimeOccurrenceID: String?
  let runtimeFractionAlongOccurrence: Double?
  let consumedGuidancePromptIDs: [String]?
  let mapMode: WholeShutoMapMode
  let accessRoute: WholeShutoSurfaceRoute?
  let egressRoute: WholeShutoSurfaceRoute?
  let circuitID: String?
  let circuitLaps: Int?
  let runtimeAssetIdentity: ShutoRuntimeAssetIdentity?
  let liveNavigationCheckpoint: NavigationSessionCheckpoint?
  var driveRecord: WholeShutoDriveRecord? = nil
  var journeyEnding: WholeShutoJourneyEnding? = nil
  var parkingStops: WholeShutoParkingStopSelection? = nil
  var joinedOccurrenceID: String? = nil
  var declaredEntryFacilityID: String? = nil
}

@MainActor
protocol WholeShutoJourneyCheckpointStoring: AnyObject {
  func load() throws -> WholeShutoJourneyCheckpoint?
  func save(_ checkpoint: WholeShutoJourneyCheckpoint) throws
  /// Saves without holding the main actor while the checkpoint is encoded
  /// and written, in the same order as every other save and remove.
  func saveInBackground(_ checkpoint: WholeShutoJourneyCheckpoint) async throws
  func remove() throws
}

extension WholeShutoJourneyCheckpointStoring {
  func saveInBackground(_ checkpoint: WholeShutoJourneyCheckpoint) async throws {
    try save(checkpoint)
  }
}

/// One atomically replaced file in Application Support. A checkpoint carries
/// the whole RoutePlan, about 1.8 MB for nine C2 laps, which is too large for
/// a UserDefaults value.
///
/// Every load, save and remove runs on one serial queue, so they apply in
/// the order they were asked for and the last one wins. The synchronous calls
/// wait for anything queued before them; `saveInBackground` lets the live
/// drive's periodic checkpoint encode and write without holding the main
/// actor. A write cut short by suspension resumes with the process, and one
/// cut short by termination leaves the previous file whole, because the
/// replacement is atomic.
@MainActor
final class WholeShutoFileCheckpointStore:
  WholeShutoJourneyCheckpointStoring
{
  static let defaultFileURL = URL.applicationSupportDirectory
    .appendingPathComponent("KaidoRoutes", isDirectory: true)
    .appendingPathComponent("whole-shuto-journey-checkpoint.json")

  private let fileURL: URL
  private let queue = DispatchQueue(label: "app.kaidoroutes.journey-checkpoint")

  init(fileURL: URL = defaultFileURL) {
    self.fileURL = fileURL
  }

  func load() throws -> WholeShutoJourneyCheckpoint? {
    let fileURL = fileURL
    return try queue.sync {
      guard FileManager.default.fileExists(atPath: fileURL.path) else {
        return nil
      }
      return try JSONDecoder().decode(
        WholeShutoJourneyCheckpoint.self,
        from: Data(contentsOf: fileURL)
      )
    }
  }

  func save(_ checkpoint: WholeShutoJourneyCheckpoint) throws {
    let fileURL = fileURL
    try queue.sync { try Self.write(checkpoint, to: fileURL) }
  }

  func saveInBackground(_ checkpoint: WholeShutoJourneyCheckpoint) async throws {
    let fileURL = fileURL
    let queue = queue
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, any Error>) in
      queue.async {
        continuation.resume(
          with: Result { try Self.write(checkpoint, to: fileURL) }
        )
      }
    }
  }

  func remove() throws {
    let fileURL = fileURL
    try queue.sync {
      guard FileManager.default.fileExists(atPath: fileURL.path) else {
        return
      }
      try FileManager.default.removeItem(at: fileURL)
    }
  }

  private nonisolated static func write(
    _ checkpoint: WholeShutoJourneyCheckpoint,
    to fileURL: URL
  ) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try JSONEncoder().encode(checkpoint).write(to: fileURL, options: .atomic)
  }
}

enum WholeShutoProductError: Error, Equatable {
  case bundledNetworkMissing
  case bundledNetworkInvalid
  case locationUnavailable
  case destinationUnavailable
  case noExpresswayRoute
}

private enum WholeShutoSavedRouteResolutionError: Error {
  case networkSnapshotMismatch
  case invalidTemplateMetadata
  case invalidRoutePlan
}

private struct WholeShutoResolvedSavedRoute {
  let route: ShutoPlannedRoute
  let selectionSource: WholeShutoRouteSelectionSource
  let circuit: ShutoCircuitDefinition?
  let circuitLaps: Int?
  let templateParameters: [String: String]
  let parkingStops: WholeShutoParkingStopSelection?
}

enum WholeShutoNetworkCatalog {
  /// Starts decoding the bundled network on a background thread. The app
  /// calls this first, so the decode overlaps UIKit and SwiftUI setting the
  /// scene up instead of following them on the main thread.
  static func startLaunchDecode() {
    _ = launchDecode
  }

  /// The bundled network decoded by `startLaunchDecode`, waiting for that
  /// decode if it is still running.
  static func launchBundled() throws -> ShutoNetworkDatabase {
    try launchDecode.value()
  }

  private static let launchDecode = BackgroundNetworkDecode { try bundled() }

  /// Decodes the bundled network without validating it: every consumer
  /// builds a `ShutoRoutePlanner` or a runtime `NetworkContext`, and each of
  /// those validates the database it is given.
  static func bundled(bundle: Bundle = .main) throws -> ShutoNetworkDatabase {
    guard
      let url = bundle.url(
        forResource: "shuto-whole-network-20260804",
        withExtension: "json"
      )
    else {
      throw WholeShutoProductError.bundledNetworkMissing
    }
    do {
      return try JSONDecoder().decode(
        ShutoNetworkDatabase.self,
        from: Data(contentsOf: url)
      )
    } catch {
      throw WholeShutoProductError.bundledNetworkInvalid
    }
  }
}

/// One decode started on a background queue, whose result any thread can
/// wait for.
private final class BackgroundNetworkDecode: Sendable {
  private let finished = DispatchGroup()
  private let result = Mutex<Result<ShutoNetworkDatabase, any Error>?>(nil)

  init(_ decode: @escaping @Sendable () throws -> ShutoNetworkDatabase) {
    finished.enter()
    DispatchQueue.global(qos: .userInteractive).async { [self] in
      let decoded = Result { try decode() }
      result.withLock { $0 = decoded }
      finished.leave()
    }
  }

  func value() throws -> ShutoNetworkDatabase {
    finished.wait()
    return try result.withLock { $0! }.get()
  }
}

@MainActor
final class WholeShutoProductModel: ObservableObject {
  private struct TunnelEstimateAnchor {
    let routePlanID: String
    let occurrenceID: String
    let receivedAtMilliseconds: Int
    let routeDistanceMeters: Double
    let safetyLimitRouteDistanceMeters: Double
    let speedMetersPerSecond: Double
    let speedAccuracyMetersPerSecond: Double?
  }

  static let simulationReferenceSpeedMetersPerSecond = 15.0
  static let simulationPlaybackSpeed: NavigationDriveSimulationSpeed =
    .twentyTimes

  static let previewOrigin = WholeShutoPlace(
    title: "東京駅",
    coordinate: ShutoCoordinate(
      latitude: 35.681236,
      longitude: 139.767125
    )
  )
  static let previewDestination = WholeShutoPlace(
    title: "横浜中華街",
    coordinate: ShutoCoordinate(
      latitude: 35.443708,
      longitude: 139.646794
    )
  )

  @Published var originQuery: String
  @Published var destinationQuery: String
  @Published var preference: ShutoRoutePreference = .recommended
  @Published var mapMode: WholeShutoMapMode = .network
  @Published private(set) var phase: WholeShutoJourneyPhase = .planning {
    didSet {
      guard phase != oldValue else { return }
      syncMapModeToPhase()
    }
  }
  @Published private(set) var origin: WholeShutoPlace?
  @Published private(set) var journeyEnding: WholeShutoJourneyEnding = .destination
  @Published private(set) var destination: WholeShutoPlace?
  @Published private(set) var recommendations: [ShutoRouteRecommendation] = []
  @Published private(set) var selectedRecommendationIndex = 0
  @Published private(set) var customRecommendation: ShutoRouteRecommendation?
  @Published private(set) var routeChoiceMetricsByRoutePlanID:
    [String: WholeShutoRouteChoiceMetrics] = [:]
  @Published private(set) var isCustomRouteSelected = false
  @Published private(set) var customEntryFacilityID: String? {
    didSet { refreshReachableExitCandidates() }
  }
  /// Exits the route editor may offer after its current entrance: a selected
  /// route experience's own forward-ranked exits, or every exit some directed
  /// all-Shuto path reaches for an exact custom pairing. Recomputed whenever
  /// the entrance changes, so the editor never lists a pairing the planner
  /// would refuse.
  @Published private(set) var reachableExitCandidates:
    [ShutoNetworkDatabase.Facility] = []
  @Published private(set) var customExitFacilityID: String? {
    didSet { refreshEntryCandidatesReachingExit() }
  }
  /// The mirror for a driver who fixes the exit first: entrances some
  /// directed all-Shuto path leads from to the current exit, other than the
  /// exit's own toll point. An experience's direction-valid entrances all
  /// reach the same exits once its course completes, so there it rules out
  /// only the entrances sharing that toll point.
  private var entryCandidatesReachingExit:
    [ShutoNetworkDatabase.Facility] = []
  @Published private(set) var customPreference: ShutoRoutePreference =
    .recommended
  @Published private(set) var customDraftRoute: ShutoPlannedRoute?
  @Published private(set) var selectedCircuit: ShutoCircuitDefinition?
  @Published private(set) var circuitEntranceCandidates: [ShutoNetworkDatabase.Facility] = []
  @Published private(set) var circuitEntryFacilityID: String?
  @Published private(set) var circuitExitFacilityID: String?
  @Published private(set) var circuitPairingBand: ShutoTariffBand?
  @Published private(set) var circuitEntranceDistanceMeters: Double?
  @Published private(set) var circuitEntranceWasOverridden = false
  /// The exit is the driver's to fix as well: every exit the experience
  /// reaches after its resolved entrance, in driving order, each priced as a
  /// pairing with that entrance. The recommendation stays known so choosing
  /// it again returns to the derived pairing.
  @Published private(set) var circuitExitCandidates:
    [ShutoNetworkDatabase.Facility] = []
  @Published private(set) var circuitTariffBandsByExitFacilityID:
    [String: ShutoTariffBand] = [:]
  @Published private(set) var circuitRecommendedExitFacilityID: String?
  @Published private(set) var circuitExitWasOverridden = false
  @Published private(set) var circuitPreviewsByID: [String: WholeShutoCircuitPreview] =
    [:]
  @Published private(set) var isResolvingCircuitPairing = false
  @Published private(set) var circuitLaps = 1
  @Published private(set) var parkingStopSelection: WholeShutoParkingStopSelection?
  @Published private(set) var circuitRecommendation: ShutoRouteRecommendation?
  @Published private(set) var isCircuitRouteSelected = false
  @Published private(set) var circuitTariffBandsByFacilityID: [String: ShutoTariffBand] = [:]
  @Published private(set) var accessRoute: WholeShutoSurfaceRoute?
  @Published private(set) var egressRoute: WholeShutoSurfaceRoute?
  @Published private(set) var progressFraction = 0.0
  @Published private(set) var isPlaying = false
  /// True only after the selected exact route has produced a validated
  /// foreground product runtime and the user has started live navigation.
  @Published private(set) var isLiveDrive = false
  @Published private(set) var liveLocationState: WholeShutoLiveLocationState = .inactive
  @Published private(set) var routeJoinState: WholeShutoRouteJoinState =
    .unavailable
  /// What this drive did. A record, never a target — see the safety invariant
  /// in AGENTS.md. The driver can switch it off.
  @Published private(set) var driveRecord = WholeShutoDriveRecord()
  @Published private(set) var driveHistoryIssue: String?
  let driveHistoryStore: any DriveHistoryStoring
  /// Whole laps still ahead of the car, so the drive can offer to drop one.
  @Published private(set) var remainingWholeLapsAhead = 0
  @Published private(set) var isChangingLaps = false
  @Published private(set) var showsDriveRecord: Bool
  @Published private(set) var surfaceRoutePreference: WholeShutoSurfaceRoutePreference
  @Published private(set) var liveLocationIssueCode: String?
  @Published private(set) var failureCode: String?
  @Published private(set) var checkpointIssueCode: String?
  @Published private(set) var isPlanning = false
  @Published private(set) var isUpdatingSurfaceRoute = false
  @Published private(set) var isReroutingSurfaceRoute = false
  @Published private(set) var isPreparingLiveNavigation = false
  @Published private(set) var isStartingLiveNavigation = false
  @Published private(set) var restoredFromCheckpoint = false
  @Published private(set) var matcherConfidence: MatcherConfidence?
  @Published private(set) var runtimeOccurrenceID: String?
  @Published private(set) var runtimeJourneyPhase: JourneyPhase?
  @Published private(set) var runtimeRecoveryStatus: RecoveryState.Status?
  /// The cue entry evidence made due before entry was confirmed: shown on
  /// the banner, never spoken.
  @Published private(set) var entryStretchGuidanceFrame: GuidanceFrame?
  /// The session cannot yet tell a car that took the exit from one that
  /// missed it: see `NavigationSessionUpdate.isConfirmingPlannedExit`.
  @Published private(set) var runtimeIsConfirmingPlannedExit = false
  @Published private(set) var runtimeRecoveryTargetOccurrenceID: String?
  @Published private(set) var runtimeRecoveryDirectedEdgeID: String?
  @Published private(set) var presentationProjection: NavigationPresentationProjection?
  @Published private(set) var speechStatus: GuidanceSpeechCoordinatorStatus = .idle
  @Published private(set) var speechMode: GuidanceSpeechMode = .full
  private var audibleSpeechMode: GuidanceSpeechMode = .full
  @Published private(set) var speechVolume: GuidanceSpeechVolume = .loud
  static let speechModeDefaultsKey = "app.kaidoroutes.guidance.mode"
  @Published private(set) var tunnelEstimatedProgressFraction: Double?
  @Published private(set) var tunnelEstimateUncertaintyMeters: Double?
  /// Fresh expressway fixes keep arriving but none has been admitted for a
  /// few seconds, so the marker stands where the car was last placed. Only
  /// the marker's appearance reads this: the fixes are not stale, so no text
  /// or voice calls the position weak.
  @Published private(set) var isHoldingLivePosition = false

  let database: ShutoNetworkDatabase
  let planner: ShutoRoutePlanner

  private let locationProvider: any C2NavigationCurrentLocationProviding
  private let placeResolver: any C2NavigationPlaceResolving
  private let checkpointStore: (any WholeShutoJourneyCheckpointStoring)?
  private let surfaceRouteResolver: any WholeShutoSurfaceRouteResolving
  private let routeChoiceEvaluator: WholeShutoSurfaceRouteChoiceEvaluator
  private let speechOutput: any GuidanceSpeechOutput
  private let languageSelectionProvider: () -> NavigationLanguageSelection
  private let liveJourneyAdmissions: [WholeShutoLiveJourneyAdmission]
  private let liveJourneyAdmissionResolver: WholeShutoLiveJourneyAdmissionResolver?
  private let liveLocationSourceEvidenceProvider: any CoreLocationSourceEvidenceProviding
  private let liveLocationSource: (any ForegroundNavigationLocationSource)?
  private let waysByID: [Int64: ShutoNetworkDatabase.Way]
  private var playbackTask: Task<Void, Never>?
  private var playbackGeneration = 0
  private var surfaceRouteTask: Task<Void, Never>?
  private var surfaceRerouteTask: Task<Void, Never>?
  private var surfaceRerouteRequestID: UUID?
  private var consecutiveSurfaceOffRouteObservations = 0
  private var consecutivePastEntranceObservations = 0
  private var lastSurfaceRerouteAttemptAtMilliseconds: Int?
  private var liveAdmissionTask: Task<Void, Never>?
  private var liveAdmissionRequestID: UUID?
  private var liveRuntimeAssetsTask: Task<Void, Never>?
  private var liveRuntimeAssetsRequestID: UUID?
  private var preparedLiveRuntimeAssets: ShutoPlannedRouteRuntimeAssets?
  private var preparedLiveRuntime: KaidoProductNavigationRuntime?
  private var junctionPromptCacheRoutePlan: RoutePlan?
  private var junctionPromptCache: [WholeShutoJunctionPrompt] = []
  private var circuitThumbnailTask: Task<Void, Never>?
  private var resolvedLiveAdmission: WholeShutoLiveJourneyAdmission?
  private var liveAdmissionResolutionIssueCode: String?
  private var circuitTariffTask: Task<Void, Never>?
  private var circuitPairingOriginCoordinate: ShutoCoordinate?
  private var startsCircuitJourneyAfterPairing = false
  private var surfaceRouteRequestID: UUID?
  private var routeChoiceSurfaceRoutesByRoutePlanID: [String: WholeShutoRouteChoiceSurfaceRoutes] =
    [:]
  private var runtimeAssets: ShutoPlannedRouteRuntimeAssets?
  private var driveSimulator: NavigationDriveSimulator?
  /// The reviewed movement a junction preview is staged at. Denser
  /// corridor coverage means other prompts precede it on the same route,
  /// so both the static inset and the deterministic preview stepping must
  /// target this movement rather than whichever prompt comes first.
  private(set) var junctionPreviewMovementID: String?
  private var liveDriveSession: ShutoLiveDriveSession? {
    didSet {
      // A lap swap waits on the session it replaces; any other change of
      // session ends it.
      if let pendingLapSwap, pendingLapSwap.replacing !== liveDriveSession {
        self.pendingLapSwap = nil
        isChangingLaps = false
      }
    }
  }
  private var pendingLapSwap: PendingLapSwap?
  private var liveEntryTransitionAdapter: CoreLocationEntryTransitionAdapter?
  private var liveSurfaceEgressAdapter: CoreLocationSurfaceEgressAdapter?
  private var liveNavigationCheckpoint: NavigationSessionCheckpoint?
  private var pendingLiveNavigationCheckpoint: NavigationSessionCheckpoint?
  private var activeLiveAdmission: WholeShutoLiveJourneyAdmission?
  private var liveObservationAdapter: CoreLocationObservationAdapter?
  private var foregroundLiveLocationController: ForegroundNavigationLocationController?
  private var liveLocationSubscriptions: Set<AnyCancellable> = []
  private var runtimeCoordinate: ShutoCoordinate?
  private var runtimeFractionAlongOccurrence: Double?
  private var speechCoordinator: GuidanceSpeechCoordinator?
  private var consumedGuidancePromptIDs: Set<String> = []
  /// When the entrance announcement was spoken, and for which movement.
  private var entranceAnnouncement: (movementOccurrenceID: String, atMilliseconds: Int)?
  /// How soon after the entrance announcement the same decision's own cue
  /// would only repeat it.
  static let entranceAnnouncementRepeatMilliseconds = 10_000
  private var surfaceSpeechGeneration = 0
  private var noticeSequence = 0
  private var pendingNotice: GuidanceSpeechCommand?
  private var positionLossAnnounced = false
  private var positionLossAnnouncedAtMilliseconds: Int?
  private var isStaticJunctionPreview = false
  private var selectedOriginTitle: String?
  private var selectedDestinationTitle: String?
  private var selectedSavedRouteTemplateParameters: [String: String]?
  private var trackMapCacheKey: String?
  private var trackMapCacheLayout: RouteTrackMapLayout?
  private var trackMapCacheSpans: [WholeShutoTrackMapSpan] = []
  private var liveLocationStartedAtMilliseconds: Int?
  /// A second matcher session over the same release-bound corridor, fed
  /// every fix before strict-route entry as an on-route position. Its
  /// estimates decide only whether the declaration is offered; nothing it
  /// sees reaches the navigation session or the ramp admission.
  private var liveRouteJoinObserver: CoreLocationEntryTransitionAdapter?
  private var routeJoinOffer: RouteJoinOffer?
  /// The plan occurrence a driver-declared join landed on. Ramp admission
  /// proves the planned entrance; a declared join proves only this place, so
  /// until the driver names the entrance it stays unconfirmed and no tariff
  /// band is quoted for it.
  @Published private(set) var joinedOccurrenceID: String?
  /// The entrance the driver named after a declared join.
  @Published private(set) var declaredEntryFacilityID: String?
  private var enteredThroughRamp = false
  private var driveRecordArrived = false
  private let driveRecordPreferenceStore: UserDefaults
  static let showsDriveRecordDefaultsKey = "app.kaidoroutes.drive-record.shown"
  static let surfaceRoutePreferenceDefaultsKey =
    "app.kaidoroutes.surface-route.preference"
  private var lastLiveObservationAtMilliseconds: Int?
  /// The last fix that placed the car somewhere the drive can use. Stale
  /// positioning — label and voice — is measured from this, never from a
  /// single weak or ambiguous fix.
  private var lastUsableLiveObservationAtMilliseconds: Int?
  private var lastAdmittedLiveFixAtMilliseconds: Int?
  static let livePositionHoldingMilliseconds = 5_000
  @Published private var liveVehicleCourseDegrees: Double?
  @Published private var liveVehicleSpeedMetersPerSecond: Double?
  private var lastLiveCheckpointPersistedAtMilliseconds: Int?
  /// Counts every checkpoint save and remove asked of the store, so a
  /// background save can tell whether a later write superseded it.
  private var checkpointWriteGeneration = 0
  private var liveLocationFreshnessTask: Task<Void, Never>?
  private var tunnelEstimateAnchor: TunnelEstimateAnchor?
  private var liveMatcherWasInTunnel = false
  private let nowMillisecondsProvider: () -> Int

  static let liveLocationStaleAfterMilliseconds = 10_000
  /// Walking pace: GPS speed noise on a parked car stays well under it.
  static let restMaximumSpeedMetersPerSecond = 1.0
  /// A second loss inside this window stays silent, and so does its recovery.
  static let positionLossAnnouncementCooldownMilliseconds = 60_000
  static let tunnelEstimateRefreshMilliseconds = 1_000
  static let liveCheckpointPersistenceIntervalMilliseconds = 5_000
  static let surfaceRerouteRequiredOffRouteObservations = 2
  static let surfaceRerouteCooldownMilliseconds = 15_000
  static let surfaceSpeechPreannounceDistanceMeters = 250.0
  static let surfaceEntryTransitionRadiusMeters = 80.0
  /// A ramp entry resolves within seconds. Waiting this long means the entry
  /// the plan expects is not the one the car is on, so the offer appears.
  static let surfaceRouteReroutingCode = "SURFACE_ROUTE_REROUTING"
  static let routeJoinUnresolvedCode = "ROUTE_JOIN_POSITION_UNRESOLVED"
  static let lapChangeUnavailableCode = "WHOLE_SHUTO_LAP_CHANGE_UNAVAILABLE"
  static let surfaceRouteRerouteUnavailableCode =
    "SURFACE_ROUTE_REROUTE_UNAVAILABLE"
  private static let checkpointLoadFailedCode =
    "WHOLE_SHUTO_CHECKPOINT_LOAD_FAILED"
  private static let checkpointSchemaUnsupportedCode =
    "WHOLE_SHUTO_CHECKPOINT_SCHEMA_UNSUPPORTED"
  private static let checkpointNetworkMismatchCode =
    "WHOLE_SHUTO_CHECKPOINT_NETWORK_MISMATCH"
  private static let checkpointPhaseInvalidCode =
    "WHOLE_SHUTO_CHECKPOINT_PHASE_INVALID"
  private static let checkpointRouteInvalidCode =
    "WHOLE_SHUTO_CHECKPOINT_ROUTE_INVALID"
  private static let checkpointRuntimeInvalidCode =
    "WHOLE_SHUTO_CHECKPOINT_RUNTIME_INVALID"
  private static let checkpointSaveFailedCode =
    "WHOLE_SHUTO_CHECKPOINT_SAVE_FAILED"
  private static let checkpointRemoveFailedCode =
    "WHOLE_SHUTO_CHECKPOINT_REMOVE_FAILED"

  init(
    database: ShutoNetworkDatabase? = nil,
    originQuery: String = "",
    destinationQuery: String = "",
    locationProvider: any C2NavigationCurrentLocationProviding =
      C2CoreLocationProvider(),
    placeResolver: any C2NavigationPlaceResolving =
      C2MapKitPlaceResolver(),
    surfaceRouteResolver: any WholeShutoSurfaceRouteResolving =
      WholeShutoMapKitSurfaceRouteResolver(),
    checkpointStore: (any WholeShutoJourneyCheckpointStoring)? =
      WholeShutoFileCheckpointStore(),
    speechOutput: (any GuidanceSpeechOutput)? = nil,
    liveJourneyAdmissions: [WholeShutoLiveJourneyAdmission] = [],
    liveJourneyAdmissionResolver:
      WholeShutoLiveJourneyAdmissionResolver? = nil,
    liveLocationSourceEvidenceProvider:
      any CoreLocationSourceEvidenceProviding =
      SystemCoreLocationSourceEvidenceProvider(),
    liveLocationSource: (any ForegroundNavigationLocationSource)? = nil,
    nowMillisecondsProvider: @escaping () -> Int = {
      Int((Date().timeIntervalSince1970 * 1_000).rounded())
    },
    languageSelectionProvider:
      @escaping () -> NavigationLanguageSelection = {
        WholeShutoProductModel.storedLanguageSelection()
      },
    driveRecordPreferenceStore: UserDefaults = .standard,
    driveHistoryStore: (any DriveHistoryStoring)? = nil
  ) {
    let resolvedDatabase: ShutoNetworkDatabase
    do {
      resolvedDatabase = try database ?? WholeShutoNetworkCatalog.bundled()
      planner = try ShutoRoutePlanner(database: resolvedDatabase)
    } catch {
      preconditionFailure("Invalid bundled whole-Shuto network: \(error)")
    }
    self.database = resolvedDatabase
    self.originQuery = originQuery
    self.destinationQuery = destinationQuery
    self.locationProvider = locationProvider
    self.placeResolver = placeResolver
    self.surfaceRouteResolver = surfaceRouteResolver
    routeChoiceEvaluator = WholeShutoSurfaceRouteChoiceEvaluator(
      resolver: surfaceRouteResolver
    )
    self.checkpointStore = checkpointStore
    self.speechOutput =
      speechOutput ?? AppGuidanceSpeechOutputFactory.make()
    self.liveJourneyAdmissions = liveJourneyAdmissions
    self.liveJourneyAdmissionResolver = liveJourneyAdmissionResolver
    self.liveLocationSourceEvidenceProvider =
      liveLocationSourceEvidenceProvider
    self.liveLocationSource = liveLocationSource
    self.nowMillisecondsProvider = nowMillisecondsProvider
    self.languageSelectionProvider = languageSelectionProvider
    self.driveRecordPreferenceStore = driveRecordPreferenceStore
    self.driveHistoryStore = driveHistoryStore ?? FileDriveHistoryStore.defaultStore()
    let storedSpeechMode = driveRecordPreferenceStore.string(forKey: Self.speechModeDefaultsKey)
      .flatMap(GuidanceSpeechMode.init(rawValue:)) ?? .full
    speechMode = storedSpeechMode
    if storedSpeechMode != .muted { audibleSpeechMode = storedSpeechMode }
    speechVolume = GuidanceSpeechVolume.stored(in: driveRecordPreferenceStore)
    // Shown unless the driver has said otherwise.
    showsDriveRecord =
      driveRecordPreferenceStore.object(
        forKey: Self.showsDriveRecordDefaultsKey
      ) as? Bool ?? true
    surfaceRoutePreference =
      driveRecordPreferenceStore.string(
        forKey: Self.surfaceRoutePreferenceDefaultsKey
      ).flatMap(WholeShutoSurfaceRoutePreference.init(rawValue:))
      ?? .preferHighways
    waysByID = Dictionary(
      uniqueKeysWithValues: resolvedDatabase.ways.map {
        ($0.wayID, $0)
      }
    )
    restoreCheckpointIfAvailable()
    resolveCircuitThumbnails()
    if let selectedRoute {
      prepareLiveNavigationAdmission(for: selectedRoute)
    }
  }

  /// One representative shape per catalog card, computed once off the main
  /// actor from a reviewed deterministic entrance so the card can show the
  /// route's silhouette before any selection.
  private nonisolated static let thumbnailEntranceByCircuitID: [String: String] = [
    "shuto.circuit.c1-inner": "shuto.ic.c1.takaracho",
    "shuto.circuit.c1-outer": "shuto.ic.c1.kyoubashi",
    "shuto.circuit.c2-inner-bayshore": "shuto.ic.c2.hatsudaiminami",
    "shuto.circuit.wangan-daikoku-run": "shuto.ic.b.shinkiba",
    "shuto.circuit.daikoku-yokohama-loop": "shuto.ic.b.higashiogishima",
    "shuto.circuit.scenic-grand-tour": "shuto.ic.10.harumi",
  ]

  private func resolveCircuitThumbnails() {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("-HOLD-CIRCUIT-PREVIEWS") { return }
    #endif
    let planner = planner
    let database = database
    circuitThumbnailTask?.cancel()
    // The cards are the first screen's content, not deferrable housekeeping:
    // at utility priority a saturated CPU held them back for 50 s.
    circuitThumbnailTask = Task.detached(priority: .userInitiated) { [weak self] in
      let resolved = Self.circuitPreviews(planner: planner, database: database)
      guard !Task.isCancelled else { return }
      await MainActor.run { [weak self] in
        self?.circuitPreviewsByID = resolved
        self?.circuitThumbnailTask = nil
      }
    }
  }

  /// The catalog card previews: one shape, distance and junction count per
  /// bundled circuit, planned from its reviewed deterministic entrance. It
  /// stops early when the calling task is cancelled.
  nonisolated static func circuitPreviews(
    planner: ShutoRoutePlanner,
    database: ShutoNetworkDatabase
  ) -> [String: WholeShutoCircuitPreview] {
    var previews: [String: WholeShutoCircuitPreview] = [:]
    for circuit in ShutoCircuitDefinition.bundled {
      guard !Task.isCancelled else { break }
      guard
        let entranceID =
          Self.thumbnailEntranceByCircuitID[circuit.circuitID],
        let exit = try? planner.circuitExitCandidates(
          for: circuit,
          afterEntering: entranceID
        ).first,
        let route = try? planner.planCircuit(
          circuit: circuit,
          entryFacilityID: entranceID,
          exitFacilityID: circuit.defaultDestinationParkingAreaID == nil ? exit.facilityID : nil,
          laps: 1
        ),
        let layout = RouteTrackMapLayout.make(
          routeCoordinates: route.coordinates.map {
            RouteTrackMapLayout.GeoPoint(
              latitude: $0.latitude,
              longitude: $0.longitude
            )
          },
          facilities: []
        )
      else { continue }
      let points = layout.trackPoints
      let stride = max(1, points.count / 64)
      var sampled: [CGPoint] = []
      for index in Swift.stride(
        from: 0,
        to: points.count,
        by: stride
      ) {
        sampled.append(
          CGPoint(
            x: points[index].x / RouteTrackMapLayout.designWidth,
            y: points[index].y / RouteTrackMapLayout.designHeight
          )
        )
      }
      if let last = points.last {
        sampled.append(
          CGPoint(
            x: last.x / RouteTrackMapLayout.designWidth,
            y: last.y / RouteTrackMapLayout.designHeight
          )
        )
      }
      previews[circuit.circuitID] = WholeShutoCircuitPreview(
        points: sampled, distanceMeters: route.distanceMeters,
        junctionCount: ShutoJunctionGuidanceCompiler.compile(
          database: database, route: route,
          releasedContext: planner.releasedMovementContext
        ).count,
        routeIDsInOrder: route.routeIDsInOrder
      )
    }
    return previews
  }

  deinit {
    playbackTask?.cancel()
    surfaceRouteTask?.cancel()
    surfaceRerouteTask?.cancel()
    liveAdmissionTask?.cancel()
    liveRuntimeAssetsTask?.cancel()
    circuitThumbnailTask?.cancel()
    circuitTariffTask?.cancel()
    liveLocationFreshnessTask?.cancel()
  }

  var selectedRecommendation: ShutoRouteRecommendation? {
    if isCircuitRouteSelected {
      return circuitRecommendation
    }
    if isCustomRouteSelected {
      return customRecommendation
    }
    return recommendations.indices.contains(selectedRecommendationIndex)
      ? recommendations[selectedRecommendationIndex]
      : nil
  }

  var endsAtParkingArea: Bool { selectedRoute?.destinationParkingArea != nil }

  /// The drive ended near its destination PA: the car went on past the PA's
  /// entry ramp instead of into it, closed or missed.
  @Published private(set) var endedNearDestination = false

  /// The car left the expressway where the plan does not. Ordinary-road
  /// guidance has taken over, or the drive ended there.
  @Published private(set) var leftRouteAtUnplannedExit = false
  /// The drive ended where the car left the route, away from its destination.
  @Published private(set) var endedOffRoute = false

  var requiresSurfaceEgress: Bool { journeyEnding != .exit && !endsAtParkingArea }

  var selectedRoute: ShutoPlannedRoute? {
    selectedRecommendation?.route
  }

  static let liveNavigationReleaseRequiredCode =
    "WHOLE_SHUTO_NAVIGATION_RELEASE_REQUIRED"
  static let liveNavigationReleaseAmbiguousCode =
    WholeShutoRouteReleaseAuthority.ambiguousReleaseCode
  static let liveNavigationPreparingCode =
    "WHOLE_SHUTO_NAVIGATION_PREPARING"
  static let surfaceRoutePreparingCode = "SURFACE_ROUTE_PREPARING"
  static let liveNavigationRuntimeInvalidCode =
    "WHOLE_SHUTO_NAVIGATION_RUNTIME_INVALID"

  /// A route can start only when one complete, externally constructed release
  /// admission matches the full selected RoutePlan value.
  var canStartLiveNavigation: Bool {
    !isStartingLiveNavigation
      && accessRoute != nil
      && (!requiresSurfaceEgress || egressRoute != nil)
      && !isUpdatingSurfaceRoute
      && matchingLiveAdmissions.count == 1
      && matchingLiveRuntimeAssets != nil
      && matchingPreparedLiveRuntime != nil
      && junctionPromptCacheRoutePlan == selectedRoute?.routePlan
  }

  var liveNavigationBlockerCode: String? {
    if isStartingLiveNavigation {
      return Self.liveNavigationPreparingCode
    }
    if isUpdatingSurfaceRoute {
      return Self.surfaceRoutePreparingCode
    }
    if accessRoute == nil || (requiresSurfaceEgress && egressRoute == nil) {
      return "SURFACE_ROUTE_UNAVAILABLE"
    }
    let count = matchingLiveAdmissions.count
    if count == 1,
      matchingLiveRuntimeAssets != nil,
      matchingPreparedLiveRuntime != nil,
      junctionPromptCacheRoutePlan == selectedRoute?.routePlan
    {
      return nil
    }
    if count > 1 { return Self.liveNavigationReleaseAmbiguousCode }
    if isPreparingLiveNavigation {
      return Self.liveNavigationPreparingCode
    }
    return liveAdmissionResolutionIssueCode
      ?? Self.liveNavigationReleaseRequiredCode
  }

  private var matchingLiveAdmissions: [WholeShutoLiveJourneyAdmission] {
    guard let routePlan = selectedRoute?.routePlan else { return [] }
    let bundled = liveJourneyAdmissions.filter {
      $0.core.selectedRoutePlan == routePlan
    }
    guard bundled.isEmpty,
      resolvedLiveAdmission?.core.selectedRoutePlan == routePlan,
      let resolvedLiveAdmission
    else {
      return bundled
    }
    return [resolvedLiveAdmission]
  }

  private var matchingLiveRuntimeAssets: ShutoPlannedRouteRuntimeAssets? {
    guard let routePlan = selectedRoute?.routePlan,
      matchingLiveAdmissions.count == 1,
      let admission = matchingLiveAdmissions.first
    else {
      return nil
    }
    if let runtimeAssets = admission.runtimeAssets {
      return runtimeAssets.routePlan == routePlan ? runtimeAssets : nil
    }
    guard preparedLiveRuntimeAssets?.routePlan == routePlan else {
      return nil
    }
    return preparedLiveRuntimeAssets
  }

  private var matchingPreparedLiveRuntime: KaidoProductNavigationRuntime? {
    guard let routePlan = selectedRoute?.routePlan,
      matchingLiveAdmissions.count == 1,
      let admission = matchingLiveAdmissions.first,
      let runtime = preparedLiveRuntime,
      runtime.release.navigation.bundle.routePlan == routePlan,
      runtime.runtimeIdentity == admission.core.release.runtimeIdentity,
      runtime.journeyPlan == admission.core.journeyPlan
    else {
      return nil
    }
    return runtime
  }

  private func prepareLiveNavigationAdmission(
    for route: ShutoPlannedRoute
  ) {
    liveAdmissionTask?.cancel()
    liveAdmissionTask = nil
    liveAdmissionRequestID = nil
    resolvedLiveAdmission = nil
    liveAdmissionResolutionIssueCode = nil
    liveRuntimeAssetsTask?.cancel()
    liveRuntimeAssetsTask = nil
    liveRuntimeAssetsRequestID = nil
    preparedLiveRuntimeAssets = nil
    preparedLiveRuntime = nil
    junctionPromptCacheRoutePlan = nil
    junctionPromptCache = []
    isPreparingLiveNavigation = false

    let bundled = liveJourneyAdmissions.filter {
      $0.core.selectedRoutePlan == route.routePlan
    }
    if bundled.count == 1 {
      prepareLiveRuntime(for: route, admission: bundled[0])
      return
    }
    guard bundled.isEmpty, let liveJourneyAdmissionResolver else {
      return
    }

    let requestID = UUID()
    liveAdmissionRequestID = requestID
    isPreparingLiveNavigation = true
    let work = Task.detached(priority: .userInitiated) {
      liveJourneyAdmissionResolver(route)
    }
    liveAdmissionTask = Task { [weak self] in
      let resolution = await withTaskCancellationHandler {
        await work.value
      } onCancel: {
        work.cancel()
      }
      guard !Task.isCancelled, let self,
        self.liveAdmissionRequestID == requestID,
        self.selectedRoute == route
      else {
        return
      }
      switch resolution {
      case .available(let admission)
      where admission.core.selectedRoutePlan == route.routePlan:
        self.resolvedLiveAdmission = admission
        self.liveAdmissionResolutionIssueCode = nil
        self.liveAdmissionRequestID = nil
        self.liveAdmissionTask = nil
        self.prepareLiveRuntime(for: route, admission: admission)
        return
      case .available:
        self.resolvedLiveAdmission = nil
        self.liveAdmissionResolutionIssueCode =
          Self.liveNavigationRuntimeInvalidCode
      case .unavailable(let issueCode):
        self.resolvedLiveAdmission = nil
        self.liveAdmissionResolutionIssueCode = issueCode
      }
      self.isPreparingLiveNavigation = false
      self.liveAdmissionRequestID = nil
      self.liveAdmissionTask = nil
    }
  }

  private func prepareLiveRuntime(
    for route: ShutoPlannedRoute,
    admission: WholeShutoLiveJourneyAdmission
  ) {
    let requestID = UUID()
    let database = database
    let releasedContext = planner.releasedMovementContext
    liveRuntimeAssetsRequestID = requestID
    isPreparingLiveNavigation = true
    let work = Task.detached(priority: .userInitiated) {
      () -> (
        ShutoPlannedRouteRuntimeAssets,
        KaidoProductNavigationRuntime,
        [WholeShutoJunctionPrompt]
      )? in
      do {
        let assets =
          try admission.runtimeAssets
          ?? ShutoPlannedRouteRuntimeCompiler.compile(
            database: database,
            route: route
          )
        guard assets.routePlan == admission.core.selectedRoutePlan else {
          return nil
        }
        let runtime = try admission.core.makeRuntime()
        let prompts = Self.compileJunctionPrompts(
          database: database,
          route: route,
          releasedContext: releasedContext
        )
        return (assets, runtime, prompts)
      } catch {
        return nil
      }
    }
    liveRuntimeAssetsTask = Task { [weak self] in
      let prepared = await withTaskCancellationHandler {
        await work.value
      } onCancel: {
        work.cancel()
      }
      guard !Task.isCancelled,
        let self,
        self.liveRuntimeAssetsRequestID == requestID,
        self.selectedRoute == route
      else {
        return
      }
      self.preparedLiveRuntimeAssets = prepared?.0
      self.preparedLiveRuntime = prepared?.1
      self.junctionPromptCache = prepared?.2 ?? []
      self.junctionPromptCacheRoutePlan = prepared == nil ? nil : route.routePlan
      if prepared == nil {
        self.liveAdmissionResolutionIssueCode =
          Self.liveNavigationRuntimeInvalidCode
      }
      self.isPreparingLiveNavigation = false
      self.liveRuntimeAssetsRequestID = nil
      self.liveRuntimeAssetsTask = nil
    }
  }

  /// The normal-car ETC rule payable today in Japan, so a revision the
  /// operator has dated takes over on its day without a release.
  var activeTariffEvidence: ShutoTariffEvidence {
    .etcNormalCar(effectiveOn: Self.jstCalendarDay(nowMillisecondsProvider()))
  }

  private static let jstDayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  static func jstCalendarDay(_ milliseconds: Int) -> String {
    jstDayFormatter.string(
      from: Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    )
  }

  var selectedTariffBand: ShutoTariffBand? {
    guard let route = selectedRoute, let exit = route.exitFacility else { return nil }
    if joinedOccurrenceID != nil {
      // The Shuto tariff is priced between toll points, so without a known
      // entrance there is no band to quote — only the cap.
      guard let declaredEntryFacilityID else { return nil }
      return try? planner.tariffBand(
        entryFacilityID: declaredEntryFacilityID,
        exitFacilityID: exit.facilityID,
        evidence: activeTariffEvidence
      )
    }
    if isCircuitRouteSelected, let circuitPairingBand { return circuitPairingBand }
    return try? planner.tariffBand(entryFacilityID: route.entryFacility.facilityID, exitFacilityID: exit.facilityID, evidence: activeTariffEvidence)
  }

  /// True while a declared join stands for the entrance and the driver has
  /// not named it.
  var entryIsUnconfirmed: Bool {
    joinedOccurrenceID != nil && declaredEntryFacilityID == nil
  }

  /// The entrance this drive can vouch for: the planned one after ramp
  /// entry, the declared one after a join, nothing while unconfirmed.
  var driveEntryFacility: ShutoNetworkDatabase.Facility? {
    if joinedOccurrenceID != nil {
      return facility(id: declaredEntryFacilityID)
    }
    return selectedRoute?.entryFacility
  }

  /// Entrances the drive could have used before the join: the ones whose
  /// entry ramp lands on a plan edge ahead of the joined occurrence, nearest
  /// behind the join first. The planned entrance is always among them.
  var declarableEntryCandidates: [ShutoNetworkDatabase.Facility] {
    guard let joinedOccurrenceID, let route = selectedRoute,
      let joinedIndex = route.routePlan.occurrence(id: joinedOccurrenceID)?.index
    else { return [] }
    var indexByEdgeID: [String: Int] = [:]
    for (index, edge) in route.edges.prefix(joinedIndex).enumerated() {
      indexByEdgeID[edge.edgeID] = index
    }
    return database.directionalFacilities
      .compactMap { facility -> (ShutoNetworkDatabase.Facility, Int)? in
        guard facility.canEnter,
          let index = facility.entryEdgeCandidates
            .compactMap({ indexByEdgeID[$0.edgeID] }).max()
        else { return nil }
        return (facility, index)
      }
      .sorted {
        if $0.1 != $1.1 { return $0.1 > $1.1 }
        return $0.0.facilityID < $1.0.facilityID
      }
      .map(\.0)
  }

  /// Names the entrance the driver used after a declared join. Re-saves the
  /// drive record when it already ended, so the history stops reading
  /// "entrance unconfirmed".
  func declareEntry(facilityID: String) {
    guard
      declarableEntryCandidates.contains(where: { $0.facilityID == facilityID })
    else { return }
    declaredEntryFacilityID = facilityID
    if driveRecord.endedAtMilliseconds != nil {
      saveDriveHistoryEntry()
    }
    persistCheckpoint()
  }

  /// The Japanese name the drive record carries for its entrance.
  private var driveEntryNameJA: String {
    driveEntryFacility?.nameJA ?? "入口未確認"
  }

  private func recordExpresswayEntry(from snapshot: NavigationSnapshot) {
    guard joinedOccurrenceID == nil, !enteredThroughRamp else { return }
    if snapshot.lastPhaseTransitionTrigger == "DRIVER_DECLARED_ROUTE_JOIN" {
      joinedOccurrenceID = snapshot.currentOccurrenceID
    } else {
      enteredThroughRamp = true
    }
  }

  private func resetDriveEntry() {
    joinedOccurrenceID = nil
    declaredEntryFacilityID = nil
    enteredThroughRamp = false
    driveRecordArrived = false
    endedNearDestination = false
    leftRouteAtUnplannedExit = false
    endedOffRoute = false
  }

  var activeSurfaceInstruction: String? {
    activeSurfaceStep?.instruction
  }

  /// The settings model owns the first-launch defaults, so an unset language
  /// resolves here exactly as the interface does.
  static func storedLanguageSelection() -> NavigationLanguageSelection {
    let settings = KaidoLanguageSettingsModel()
    return NavigationLanguageSelection(
      interfaceLocale: settings.interfaceLocale,
      guidanceVoiceLocale: settings.guidanceVoiceLocale
    )
  }

  func surfaceInstruction(in locale: KaidoReleaseLocale) -> String? {
    guard let original = activeSurfaceInstruction else { return nil }
    return SurfaceGuidancePresentation.instruction(
      original, sourceLanguageCode: activeSurfaceRoute?.guidanceLanguageCode, locale: locale
    ).text
  }

  var activeSurfaceInstructionRemainingMeters: Double? {
    activeSurfaceStepProgress?.remainingMeters
  }

  private var activeSurfaceRoute: WholeShutoSurfaceRoute? {
    switch phase {
    case .surfaceAccess:
      accessRoute
    case .surfaceEgress:
      egressRoute
    default:
      nil
    }
  }

  private var activeSurfaceStep: WholeShutoSurfaceRouteStep? {
    activeSurfaceStepProgress?.step
  }

  private var activeSurfaceStepProgress:
    (
      index: Int,
      step: WholeShutoSurfaceRouteStep,
      steps: [WholeShutoSurfaceRouteStep],
      remainingMeters: Double
    )?
  {
    guard let route = activeSurfaceRoute,
      let steps = route.steps?.filter({
        !$0.instruction.isEmpty && $0.distanceMeters > 0
      }),
      !steps.isEmpty
    else {
      return nil
    }
    let total = steps.reduce(0) { $0 + $1.distanceMeters }
    guard total > 0 else { return nil }
    let traveled = min(total, max(0, progressFraction) * total)
    var cursor = 0.0
    for (index, step) in steps.enumerated() {
      let end = cursor + step.distanceMeters
      if traveled <= end {
        return (
          index: index,
          step: step,
          steps: steps,
          remainingMeters: max(0, end - traveled)
        )
      }
      cursor = end
    }
    guard let step = steps.last else { return nil }
    return (
      index: steps.count - 1,
      step: step,
      steps: steps,
      remainingMeters: 0
    )
  }

  var savedRouteTemplateParameters: [String: String] {
    guard let route = selectedRoute else { return [:] }
    if let selectedSavedRouteTemplateParameters {
      return selectedSavedRouteTemplateParameters
    }
    let source =
      isCircuitRouteSelected
      ? "CIRCUIT" : isCustomRouteSelected ? "CUSTOM" : "RECOMMENDATION"
    var parameters = [
      "source": source,
      "preference": route.preference.rawValue,
    ]
    if isCircuitRouteSelected, let selectedCircuit {
      parameters["circuit_id"] = selectedCircuit.circuitID
      parameters["laps"] = String(circuitLaps)
    }
    if let parkingStopSelection,
      let data = try? JSONEncoder().encode(parkingStopSelection),
      let encoded = String(data: data, encoding: .utf8) {
      parameters["parking_stops"] = encoded
    }
    return parameters
  }

  /// Validates the complete saved RoutePlan against the bundled current
  /// snapshot. This is candidate integrity only; it never selects or mints a
  /// product release.
  func savedRouteAvailability(
    _ record: SavedRouteRecord
  ) -> SavedRouteLibraryAvailability {
    guard
      record.document.routePlan.networkSnapshotID
        == database.networkSnapshotID
    else {
      return .unavailable
    }
    do {
      _ = try resolveSavedRoute(record)
      return .currentSnapshot(database.networkSnapshotID)
    } catch {
      return .invalid("SAVED_ROUTE_CURRENT_SNAPSHOT_INVALID")
    }
  }

  /// Opens an exact saved route and resolves
  /// fresh provider surface legs around it. The embedded RoutePlan remains
  /// unchanged, including repeated circuit occurrences.
  @discardableResult
  func openSavedRoute(
    _ record: SavedRouteRecord,
    origin requestedOrigin: ShutoCoordinate?
  ) -> Bool {
    guard let originCoordinate = requestedOrigin ?? origin?.coordinate else {
      failureCode = "LOCATION_UNAVAILABLE"
      return false
    }
    let resolved: WholeShutoResolvedSavedRoute
    do {
      resolved = try resolveSavedRoute(record)
    } catch WholeShutoSavedRouteResolutionError.networkSnapshotMismatch {
      failureCode = "SAVED_ROUTE_NETWORK_SNAPSHOT_MISMATCH"
      return false
    } catch {
      failureCode = "SAVED_ROUTE_CURRENT_SNAPSHOT_INVALID"
      return false
    }
    let route = resolved.route

    if phase != .planning { reset() }
    cancelSurfaceRouteResolution()
    clearRouteChoiceEvaluation()
    clearCustomRouteSelection()
    clearCircuitRouteSelection()
    clearCircuitPlanningDraft()

    let originPlace = WholeShutoPlace(
      title: currentLocationTitle,
      coordinate: originCoordinate
    )
    journeyEnding = route.destinationParkingArea != nil ? .destination : (resolved.circuit?.kind == .loop ? .returnToOrigin : .exit)
    let destinationPlace = journeyEnding == .returnToOrigin
      ? originPlace : routeDestination(for: route)
    originQuery = originPlace.title
    destinationQuery = destinationPlace.title
    origin = originPlace
    destination = destinationPlace
    selectedDestinationTitle = destinationPlace.title
    recommendations = []
    selectedRecommendationIndex = 0

    let accessDistance = Self.distance(
      originCoordinate,
      route.coordinates.first ?? route.entryFacility.coordinate
    )
    let egressDistance = Self.distance(
      route.destinationCoordinate,
      destinationPlace.coordinate
    )
    let recommendation = ShutoRouteRecommendation(
      route: route,
      surfaceAccessDistanceMeters: accessDistance,
      surfaceEgressDistanceMeters: egressDistance,
      totalScoreMeters: route.distanceMeters + accessDistance + egressDistance
    )
    switch resolved.selectionSource {
    case .recommended:
      recommendations = [recommendation]
    case .custom:
      customRecommendation = recommendation
      isCustomRouteSelected = true
      customEntryFacilityID = route.entryFacility.facilityID
      customExitFacilityID = route.exitFacility?.facilityID
      customPreference = route.preference
      customDraftRoute = route
    case .circuit:
      guard let circuit = resolved.circuit,
        let laps = resolved.circuitLaps
      else {
        failureCode = "SAVED_ROUTE_CURRENT_SNAPSHOT_INVALID"
        return false
      }
      selectedCircuit = circuit
      circuitLaps = laps
      circuitEntranceCandidates = [route.entryFacility]
      circuitEntryFacilityID = route.entryFacility.facilityID
      circuitExitFacilityID = route.exitFacility?.facilityID
      circuitPairingBand = route.exitFacility.flatMap { exit in
        try? planner.tariffBand(entryFacilityID: route.entryFacility.facilityID, exitFacilityID: exit.facilityID, evidence: activeTariffEvidence)
      }
      circuitEntranceDistanceMeters = accessDistance
      circuitTariffBandsByFacilityID =
        circuitPairingBand.map {
          [route.entryFacility.facilityID: $0]
        } ?? [:]
      circuitRecommendation = recommendation
      isCircuitRouteSelected = true
    }
    parkingStopSelection = resolved.parkingStops
    selectedSavedRouteTemplateParameters =
      resolved.templateParameters.isEmpty
      ? nil : resolved.templateParameters
    preference = route.preference
    phase = .review
    progressFraction = 0
    isPlaying = false
    restoredFromCheckpoint = false
    failureCode = nil
    resolveSurfaceRoutes(
      for: recommendation,
      origin: originPlace,
      destination: destinationPlace
    )
    return true
  }

  func routeChoiceMetrics(
    at recommendationIndex: Int
  ) -> WholeShutoRouteChoiceMetrics? {
    guard recommendations.indices.contains(recommendationIndex) else {
      return nil
    }
    return routeChoiceMetricsByRoutePlanID[
      recommendations[recommendationIndex].route.routePlan.id
    ]
  }

  var customRouteChoiceMetrics: WholeShutoRouteChoiceMetrics? {
    guard
      isCustomRouteSelected,
      let recommendation = customRecommendation,
      let accessRoute,
      let egressRoute
    else {
      return nil
    }
    return Self.routeChoiceMetrics(
      for: recommendation.route,
      accessRoute: accessRoute,
      egressRoute: egressRoute
    )
  }

  var hasSelectedDestinationPreview: Bool {
    phase == .planning
      && destination != nil
      && selectedDestinationTitle == destinationQuery
  }

  var hasSelectedOriginPreview: Bool {
    phase == .planning
      && origin != nil
      && selectedOriginTitle == originQuery
  }

  /// The route experience the editor is refining: the review phase opens the
  /// editor over a selected circuit and keeps it. Nil while authoring an
  /// exact custom pairing, and for an experience that ends inside a PA: its
  /// identity is that ending, so choosing an exit there authors an explicit
  /// entrance/exit route instead.
  private var editedCircuit: ShutoCircuitDefinition? {
    phase == .review && isCircuitRouteSelected
      && selectedRoute?.destinationParkingArea == nil
      ? selectedCircuit : nil
  }

  var editsSelectedCircuit: Bool { editedCircuit != nil }

  /// Entrances that pair with the current exit, so whichever end the driver
  /// fixes first constrains the other.
  var customEntryCandidates: [ShutoNetworkDatabase.Facility] {
    customEntryPartition.pairable
  }

  /// Entrances a search may still surface while an exit is chosen. Choosing
  /// one clears that exit rather than drafting a pairing the planner refuses.
  var customEntryCandidatesNotReachingExit: [ShutoNetworkDatabase.Facility] {
    customEntryPartition.unpairable
  }

  var customExitCandidates: [ShutoNetworkDatabase.Facility] {
    customExitPartition.pairable
  }

  var customExitCandidatesNotReachableFromEntry:
    [ShutoNetworkDatabase.Facility]
  {
    customExitPartition.unpairable
  }

  private var customEntryPartition:
    (pairable: [ShutoNetworkDatabase.Facility], unpairable: [ShutoNetworkDatabase.Facility])
  {
    let ranked =
      editedCircuit != nil
      ? pinningSelection(
        circuitEntranceCandidates,
        selectedFacilityID: customEntryFacilityID
      )
      : rankedCustomFacilities(
        from: origin?.coordinate,
        selectedFacilityID: customEntryFacilityID,
        isEligible: \.canEnter
      )
    guard customExitFacilityID != nil else { return (ranked, []) }
    let reaching = Set(entryCandidatesReachingExit.map(\.facilityID))
    return (
      ranked.filter { reaching.contains($0.facilityID) },
      ranked.filter { !reaching.contains($0.facilityID) }
    )
  }

  private var customExitPartition:
    (pairable: [ShutoNetworkDatabase.Facility], unpairable: [ShutoNetworkDatabase.Facility])
  {
    if editedCircuit != nil {
      return (
        pinningSelection(
          reachableExitCandidates,
          selectedFacilityID: customExitFacilityID
        ),
        []
      )
    }
    let ranked = rankedCustomFacilities(
      // A home-authored custom route is a round trip. Its destination is
      // intentionally committed only when the draft is applied, so the
      // origin is also the correct reference for nearby exits while editing.
      from: destination?.coordinate ?? origin?.coordinate,
      selectedFacilityID: customExitFacilityID,
      isEligible: \.canExit
    )
    guard customEntryFacilityID != nil else { return (ranked, []) }
    let reachable = Set(reachableExitCandidates.map(\.facilityID))
    return (
      ranked.filter { reachable.contains($0.facilityID) },
      ranked.filter { !reachable.contains($0.facilityID) }
    )
  }

  var customEntryFacility: ShutoNetworkDatabase.Facility? {
    facility(id: customEntryFacilityID)
  }

  var customExitFacility: ShutoNetworkDatabase.Facility? {
    facility(id: customExitFacilityID)
  }

  var canApplyCustomRoute: Bool {
    // Starting from the home catalog also needs an origin for the round
    // trip; the review-phase editor already has one.
    customDraftRoute != nil && (phase == .review || origin != nil)
  }

  var usesCurrentLocationOrigin: Bool {
    Self.isCurrentLocationQuery(originQuery)
  }

  /// Whole-route track map layout, computed once per exact route plan in
  /// the fixed design space; the view scales it uniformly.
  var trackMapLayout: RouteTrackMapLayout? {
    resolveTrackMap()?.layout
  }

  var trackMapSpans: [WholeShutoTrackMapSpan] {
    resolveTrackMap()?.spans ?? []
  }

  private func resolveTrackMap() -> (
    layout: RouteTrackMapLayout, spans: [WholeShutoTrackMapSpan]
  )? {
    guard let route = selectedRoute else { return nil }
    if trackMapCacheKey == route.routePlan.id,
      let layout = trackMapCacheLayout
    {
      return (layout, trackMapCacheSpans)
    }
    let memberRouteIDs = Set(route.routeIDsInOrder)
    var facilities: [RouteTrackMapLayout.FacilityInput] = []
    for facility in database.directionalFacilities
    where memberRouteIDs.contains(facility.routeID) {
      facilities.append(
        RouteTrackMapLayout.FacilityInput(
          id: facility.facilityID,
          nameJA: facility.nameJA,
          kind: .interchange,
          coordinate: RouteTrackMapLayout.GeoPoint(
            latitude: facility.coordinate.latitude,
            longitude: facility.coordinate.longitude
          )
        )
      )
    }
    for junction in database.junctions {
      guard let coordinate = junction.coordinate else { continue }
      facilities.append(
        RouteTrackMapLayout.FacilityInput(
          id: junction.junctionID,
          nameJA: junction.nameJA,
          kind: .junction,
          coordinate: RouteTrackMapLayout.GeoPoint(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
          )
        )
      )
    }
    for parkingArea in database.parkingAreas
    where memberRouteIDs.contains(parkingArea.routeID ?? "") {
      facilities.append(
        RouteTrackMapLayout.FacilityInput(
          id: parkingArea.parkingAreaID,
          nameJA: parkingArea.nameJA,
          kind: .parkingArea,
          coordinate: RouteTrackMapLayout.GeoPoint(
            latitude: parkingArea.coordinate.latitude,
            longitude: parkingArea.coordinate.longitude
          )
        )
      )
    }
    guard
      let layout = RouteTrackMapLayout.make(
        routeCoordinates: route.coordinates.map {
          RouteTrackMapLayout.GeoPoint(
            latitude: $0.latitude,
            longitude: $0.longitude
          )
        },
        facilities: facilities
      )
    else {
      return nil
    }
    var spans: [WholeShutoTrackMapSpan] = []
    let totalMeters = route.distanceMeters
    var cursorMeters = 0.0
    var currentID: String?
    var spanStart = 0.0
    for edge in route.edges {
      let ids = Set(edge.routeMemberships.map(\.routeID))
      let id = ids.contains("B") && !ids.contains("C2") ? "B" : "MAIN"
      if id != currentID {
        if let current = currentID {
          spans.append(
            WholeShutoTrackMapSpan(
              routeID: current,
              startFraction: spanStart,
              endFraction: cursorMeters / totalMeters
            )
          )
        }
        currentID = id
        spanStart = cursorMeters / totalMeters
      }
      cursorMeters += edge.lengthMeters
    }
    if let current = currentID {
      spans.append(
        WholeShutoTrackMapSpan(
          routeID: current,
          startFraction: spanStart,
          endFraction: 1
        )
      )
    }
    trackMapCacheKey = route.routePlan.id
    trackMapCacheLayout = layout
    trackMapCacheSpans = spans
    return (layout, spans)
  }

  var junctionPrompts: [WholeShutoJunctionPrompt] {
    guard let route = selectedRoute else { return [] }
    if junctionPromptCacheRoutePlan == route.routePlan {
      return junctionPromptCache
    }
    guard !isPreparingLiveNavigation else { return [] }
    let prompts = Self.compileJunctionPrompts(
      database: database,
      route: route,
      releasedContext: planner.releasedMovementContext
    )
    junctionPromptCacheRoutePlan = route.routePlan
    junctionPromptCache = prompts
    return prompts
  }

  /// The released context must come from the same database. Without it the
  /// compiler re-indexes the whole network at every route edge, which takes
  /// seconds on a long route.
  private nonisolated static func compileJunctionPrompts(
    database: ShutoNetworkDatabase,
    route: ShutoPlannedRoute,
    releasedContext: ShutoJunctionMovementCatalog.ReleasedContext
  ) -> [WholeShutoJunctionPrompt] {
    ShutoJunctionGuidanceCompiler.compile(
      database: database,
      route: route,
      releasedContext: releasedContext
    ).map { match in
      let definition = match.definition
      return WholeShutoJunctionPrompt(
        movementID: definition.id,
        nameJA: match.junctionNameJA,
        incomingRouteID: definition.incomingRouteID,
        outgoingRouteID: definition.outgoingRouteID,
        outgoingDirectionJA: definition.outgoingDirectionJA,
        branchSide: definition.branchSide,
        japaneseSignText: definition.japaneseSignText,
        routeShields: definition.routeShields,
        laneGuidanceState: definition.laneGuidanceState,
        localizedJunctionNames: definition.localizedJunctionNames,
        localizedContent: definition.localizedContent,
        checkedAt: definition.checkedAt,
        coordinate: match.coordinate,
        incomingOccurrenceID: match.incomingOccurrenceID,
        outgoingOccurrenceID: match.outgoingOccurrenceID,
        progressFraction: match.progressFraction
      )
    }
  }

  /// The prompt eligible for the route-bound junction inset. The inset
  /// draws a branch, so it belongs to a reviewed left or right movement
  /// only; a mainline continuation speaks and shows its card without
  /// implying a diagram the evidence does not support.
  var activeJunctionInsetPrompt: WholeShutoJunctionPrompt? {
    guard hasCurrentGuidancePosition, let prompt = activeJunctionPrompt,
      prompt.branchSide == .left || prompt.branchSide == .right
    else {
      return nil
    }
    return prompt
  }

  var activeJunctionPrompt: WholeShutoJunctionPrompt? {
    guard phase == .expressway else { return nil }
    if isStaticJunctionPreview {
      // The preview is staged at one exact reviewed movement. Denser
      // corridor coverage means earlier prompts exist on the same route,
      // so select the staged movement rather than whichever comes first.
      guard let junctionPreviewMovementID else {
        return junctionPrompts.first
      }
      return junctionPrompts.first {
        $0.movementID == junctionPreviewMovementID
      }
    }
    guard let surface = presentationProjection?.iPhone else {
      return nil
    }
    return junctionPrompts.first {
      $0.outgoingOccurrenceID == surface.nextMovementOccurrenceID
    }
  }

  var hasCompletedActiveGuidancePrompt: Bool {
    guard let promptID = presentationProjection?.voice.promptID else {
      return false
    }
    return speechCoordinator?.completedIdentities.contains { $0.promptID == promptID } == true
  }

  var hasCurrentGuidancePosition: Bool {
    guard isLiveDrive else { return true }
    switch positionState {
    case .surfacePreview, .boundaryTransition, .networkPreview, .completed:
      return true
    case .tunnelEstimated:
      return liveLocationState == .available
    case .unavailable, .surfaceRoutePending, .networkDegraded, .resting, .routeInterrupted,
      .confirmingExit:
      return false
    }
  }

  var positionState: WholeShutoPositionState {
    if isLiveDrive, liveLocationState == .resting {
      return .resting
    }
    if isLiveDrive,
      phase == .surfaceAccess || phase == .surfaceEgress,
      liveLocationIssueCode == "SURFACE_ROUTE_GEOMETRY_UNAVAILABLE"
        || liveLocationIssueCode == "SURFACE_ROUTE_OFF_ROUTE"
        || liveLocationIssueCode == Self.surfaceRouteReroutingCode
        || liveLocationIssueCode == Self.surfaceRouteRerouteUnavailableCode
    {
      return .surfaceRoutePending
    }
    if isLiveDrive,
      phase != .planning,
      phase != .review,
      phase != .completed,
      liveLocationState != .available
    {
      if phase == .expressway,
        tunnelEstimatedProgressFraction != nil
      {
        return .tunnelEstimated
      }
      return .networkDegraded
    }
    switch phase {
    case .planning, .review:
      return .unavailable
    case .surfaceAccess, .surfaceEgress:
      return .surfacePreview
    case .entryTransition, .exitTransition:
      return .boundaryTransition
    case .expressway:
      if runtimeJourneyPhase == .routeRecovery {
        return runtimeIsConfirmingPlannedExit ? .confirmingExit : .routeInterrupted
      }
      // The last admitted position stands until the stale-fix path says
      // otherwise; one unadmitted fix is not a weak position.
      guard runtimeOccurrenceID != nil else {
        return .networkDegraded
      }
      guard let edge = activeExpresswayEdge,
        let way = waysByID[edge.wayID]
      else {
        return .networkPreview
      }
      return way.tags["tunnel"] == "yes"
        || way.tags["covered"] == "yes"
        ? .tunnelEstimated
        : .networkPreview
    case .completed:
      return .completed
    }
  }

  var activeRouteID: String? {
    activeExpresswayEdge.flatMap(primaryRouteID)
  }

  var currentCoordinate: ShutoCoordinate? {
    switch phase {
    case .planning, .review:
      return origin?.coordinate
    case .surfaceAccess:
      if isLiveDrive, let runtimeCoordinate {
        return runtimeCoordinate
      }
      return interpolatedCoordinate(
        in: accessRoute?.coordinates ?? [],
        fraction: progressFraction
      )
    case .entryTransition:
      if isLiveDrive, let runtimeCoordinate {
        return runtimeCoordinate
      }
      return selectedRoute?.coordinates.first
    case .expressway:
      if let tunnelEstimatedProgressFraction {
        return estimatedExpresswayPosition(
          at: tunnelEstimatedProgressFraction
        )?.coordinate
      }
      return runtimeCoordinate
        ?? interpolatedCoordinate(
          in: selectedRoute?.coordinates ?? [],
          fraction: progressFraction
        )
    case .exitTransition:
      if isLiveDrive, let runtimeCoordinate {
        return runtimeCoordinate
      }
      return selectedRoute?.coordinates.last
    case .surfaceEgress:
      if isLiveDrive, let runtimeCoordinate {
        return runtimeCoordinate
      }
      return interpolatedCoordinate(
        in: egressRoute?.coordinates ?? [],
        fraction: progressFraction
      )
    case .completed:
      if endedNearDestination || endedOffRoute, let runtimeCoordinate {
        return runtimeCoordinate
      }
      return destination?.coordinate
    }
  }

  var remainingJourneyDistanceMeters: Double? {
    guard let route = selectedRoute else { return nil }
    let accessDistance = accessRoute?.distanceMeters ?? 0
    let egressDistance = egressRoute?.distanceMeters ?? 0
    switch phase {
    case .planning, .review:
      return accessDistance + route.distanceMeters + egressDistance
    case .surfaceAccess:
      return accessDistance * remainingProgress
        + route.distanceMeters + egressDistance
    case .entryTransition:
      return route.distanceMeters + egressDistance
    case .expressway:
      return route.distanceMeters * remainingProgress + egressDistance
    case .exitTransition:
      return egressDistance
    case .surfaceEgress:
      return egressDistance * remainingProgress
    case .completed:
      return 0
    }
  }

  var plannedJourneyDistanceMeters: Double? {
    guard let route = selectedRoute else { return nil }
    return (accessRoute?.distanceMeters ?? 0)
      + route.distanceMeters
      + (egressRoute?.distanceMeters ?? 0)
  }

  var plannedPreviewDurationSeconds: Double? {
    guard
      let route = selectedRoute,
      let accessRoute,
      !requiresSurfaceEgress || egressRoute != nil
    else {
      return nil
    }
    return accessRoute.expectedTravelTimeSeconds
      + route.distanceMeters
      / Self.simulationReferenceSpeedMetersPerSecond
      + (egressRoute?.expectedTravelTimeSeconds ?? 0)
  }

  var remainingPreviewDurationSeconds: Double? {
    guard
      let route = selectedRoute,
      let accessRoute,
      !requiresSurfaceEgress || egressRoute != nil
    else {
      return nil
    }
    let expresswayDuration =
      route.distanceMeters
      / Self.simulationReferenceSpeedMetersPerSecond
    switch phase {
    case .planning, .review:
      return accessRoute.expectedTravelTimeSeconds
        + expresswayDuration
        + (egressRoute?.expectedTravelTimeSeconds ?? 0)
    case .surfaceAccess:
      return accessRoute.expectedTravelTimeSeconds * remainingProgress
        + expresswayDuration
        + (egressRoute?.expectedTravelTimeSeconds ?? 0)
    case .entryTransition:
      return expresswayDuration
        + (egressRoute?.expectedTravelTimeSeconds ?? 0)
    case .expressway:
      return expresswayDuration * remainingProgress
        + (egressRoute?.expectedTravelTimeSeconds ?? 0)
    case .exitTransition:
      return (egressRoute?.expectedTravelTimeSeconds ?? 0)
    case .surfaceEgress:
      return (egressRoute?.expectedTravelTimeSeconds ?? 0) * remainingProgress
    case .completed:
      return 0
    }
  }

  var journeyProgressFraction: Double {
    guard
      let plannedDistance = plannedJourneyDistanceMeters,
      let remainingDistance = remainingJourneyDistanceMeters,
      plannedDistance > 0
    else {
      return phase == .completed ? 1 : 0
    }
    return min(
      1,
      max(0, (plannedDistance - remainingDistance) / plannedDistance)
    )
  }

  var isJourneyReadyForPreview: Bool {
    phase == .review
      && selectedRoute != nil
      && accessRoute != nil
      && (!requiresSurfaceEgress || egressRoute != nil)
      && !isUpdatingSurfaceRoute
  }

  var entryStretchJunctionPrompt: WholeShutoJunctionPrompt? {
    guard phase == .entryTransition, let frame = entryStretchGuidanceFrame else { return nil }
    return junctionPrompts.first { $0.outgoingOccurrenceID == frame.movementOccurrenceID }
  }

  var nextReviewedJunctionPrompt: WholeShutoJunctionPrompt? {
    guard
      phase == .surfaceAccess || phase == .entryTransition
        || phase == .expressway
    else {
      return nil
    }
    if let activeJunctionPrompt {
      return activeJunctionPrompt
    }
    let currentExpresswayProgress =
      phase == .expressway ? progressFraction : 0
    return junctionPrompts.first {
      $0.progressFraction > currentExpresswayProgress
    }
  }

  var distanceToNextReviewedJunctionMeters: Double? {
    guard
      let route = selectedRoute,
      let prompt = nextReviewedJunctionPrompt
    else {
      return nil
    }
    let routeDistance =
      route.distanceMeters
      * max(
        0,
        prompt.progressFraction
          - (phase == .expressway ? progressFraction : 0)
      )
    if phase == .surfaceAccess {
      return (accessRoute?.distanceMeters ?? 0) * remainingProgress
        + routeDistance
    }
    return routeDistance
  }

  var routeProgressGeometry: WholeShutoRouteProgressGeometry? {
    guard let route = selectedRoute, !route.coordinates.isEmpty else {
      return nil
    }
    switch phase {
    case .planning, .review, .surfaceAccess, .entryTransition:
      return WholeShutoRouteProgressGeometry(
        traveledCoordinates: [route.coordinates[0]],
        remainingCoordinates: route.coordinates
      )
    case .expressway:
      if let tunnelEstimatedProgressFraction,
        let estimated = estimatedExpresswayPosition(
          at: tunnelEstimatedProgressFraction
        )
      {
        return Self.split(
          route.coordinates,
          afterVertexAt: estimated.edgeIndex,
          segmentFraction: estimated.edgeFraction
        )
      }
      if let runtimeOccurrenceID,
        let occurrence = route.routePlan.occurrence(
          id: runtimeOccurrenceID
        ),
        let fraction = runtimeFractionAlongOccurrence
      {
        return Self.split(
          route.coordinates,
          afterVertexAt: occurrence.index,
          segmentFraction: fraction
        )
      }
      return Self.split(
        route.coordinates,
        distanceFraction: progressFraction
      )
    case .exitTransition, .surfaceEgress, .completed:
      return WholeShutoRouteProgressGeometry(
        traveledCoordinates: route.coordinates,
        remainingCoordinates: [route.coordinates.last!]
      )
    }
  }

  var activeRecoveryRouteCoordinates: [ShutoCoordinate] {
    guard
      isLiveDrive,
      runtimeRecoveryStatus == .active,
      let targetOccurrenceID = runtimeRecoveryTargetOccurrenceID,
      let bundle = activeLiveAdmission?.core.release.navigation.bundle,
      let candidate = releasedRecoveryCandidate(
        targetOccurrenceID: targetOccurrenceID,
        containing: runtimeRecoveryDirectedEdgeID
      )
    else {
      return []
    }
    let firstVisibleIndex =
      runtimeRecoveryDirectedEdgeID.flatMap {
        candidate.recoveryOccurrenceIDs.firstIndex(of: $0)
      } ?? candidate.recoveryOccurrenceIDs.startIndex
    let edgesByID = Dictionary(
      uniqueKeysWithValues: bundle.matcherCorridor.edges.map { ($0.id, $0) }
    )
    var result: [ShutoCoordinate] = []
    if let runtimeCoordinate {
      result.append(runtimeCoordinate)
    }
    for (offset, edgeID) in candidate.recoveryOccurrenceIDs[firstVisibleIndex...]
      .enumerated()
    {
      guard let edge = edgesByID[edgeID] else { return [] }
      let visibleCoordinates =
        offset == 0 && runtimeRecoveryDirectedEdgeID != nil
        ? edge.coordinates.dropFirst()
        : edge.coordinates[...]
      for coordinate in visibleCoordinates {
        let value = ShutoCoordinate(
          latitude: coordinate.latitude,
          longitude: coordinate.longitude
        )
        if result.last != value {
          result.append(value)
        }
      }
    }
    return result
  }

  var vehicleHeadingDegrees: Double? {
    guard isLiveDrive else { return navigationHeadingDegrees }
    guard isPlaying, liveLocationState == .available else { return nil }
    switch positionState {
    case .surfacePreview, .surfaceRoutePending, .boundaryTransition, .networkPreview:
      return liveVehicleCourseDegrees
    default:
      return nil
    }
  }

  var navigationHeadingDegrees: Double? {
    switch positionState {
    case .surfacePreview, .surfaceRoutePending, .boundaryTransition,
      .networkPreview:
      break
    case .unavailable, .networkDegraded, .tunnelEstimated,
      .routeInterrupted, .confirmingExit, .completed, .resting:
      return nil
    }
    if isLiveDrive, phase == .surfaceAccess || phase == .surfaceEgress {
      return vehicleHeadingDegrees
    }
    guard let current = currentCoordinate else { return nil }
    let target: ShutoCoordinate?
    switch phase {
    case .surfaceAccess:
      target = lookAheadCoordinate(
        in: accessRoute?.coordinates ?? [],
        fraction: progressFraction
      )
    case .entryTransition:
      target = lookAheadCoordinate(
        in: selectedRoute?.coordinates ?? [],
        fraction: 0
      )
    case .expressway:
      target = routeProgressGeometry?.remainingCoordinates.dropFirst().first
    case .exitTransition:
      target = lookAheadCoordinate(
        in: egressRoute?.coordinates ?? [],
        fraction: 0
      )
    case .surfaceEgress:
      target = lookAheadCoordinate(
        in: egressRoute?.coordinates ?? [],
        fraction: progressFraction
      )
    case .planning, .review, .completed:
      target = nil
    }
    guard let target, Self.distance(current, target) > 1 else {
      return nil
    }
    return Self.bearing(from: current, to: target)
  }

  var navigationCameraDistanceMeters: Double {
    switch phase {
    case .surfaceAccess, .surfaceEgress:
      return 2_400
    case .entryTransition, .exitTransition:
      return 2_000
    case .expressway:
      return 3_600
    case .planning, .review, .completed:
      return 13_000
    }
  }

  var canFinishLiveExpressway: Bool {
    guard isLiveDrive,
      isPlaying,
      phase == .expressway,
      runtimeJourneyPhase == .strictRoute,
      liveLocationState == .available,
      runtimeOccurrenceID != nil,
      let route = selectedRoute
    else {
      return false
    }
    return route.distanceMeters * (1 - progressFraction) <= 150
  }

  private func recordLapProgress(
    occurrenceID: String?,
    atMilliseconds milliseconds: Int
  ) {
    guard showsDriveRecord, let occurrenceID,
      let route = selectedRoute,
      !route.lapBoundaryOccurrenceIndices.isEmpty,
      let occurrence = route.routePlan.occurrence(id: occurrenceID)
    else {
      return
    }
    driveRecord.observe(
      occurrenceIndex: occurrence.index,
      boundaries: route.lapBoundaryOccurrenceIndices,
      atMilliseconds: milliseconds
    )
  }

  /// Drops the lap the driver decided not to run.
  ///
  /// The App asks; the released lap boundaries in the navigation runtime
  /// decide where the drive lands, so this can never jump somewhere the
  /// release did not describe.
  @discardableResult
  func dropOneLap() async -> Bool {
    guard isLiveDrive, !isChangingLaps,
      phase == .expressway,
      remainingWholeLapsAhead > 0,
      let session = liveDriveSession
    else {
      return false
    }
    isChangingLaps = true
    defer { isChangingLaps = false }
    guard let occurrenceID = await session.skipOneLap() else { return false }
    await applySkippedLaps(at: occurrenceID, session: session)
    return true
  }

  var canFinishCurrentLap: Bool {
    isLiveDrive && !isChangingLaps && phase == .expressway
      && runtimeJourneyPhase == .strictRoute && selectedCircuit?.kind == .loop
      && remainingWholeLapsAhead > 0
  }

  @discardableResult
  func finishCurrentLap() async -> Bool {
    guard canFinishCurrentLap, let session = liveDriveSession else { return false }
    isChangingLaps = true
    defer { isChangingLaps = false }
    do {
      guard let occurrenceID = try await session.skipRemainingLaps() else { return false }
      await applySkippedLaps(at: occurrenceID, session: session)
      return true
    } catch {
      failureCode = "LAP_CHANGE_UNAVAILABLE"
      return false
    }
  }

  private func applySkippedLaps(at occurrenceID: String, session: ShutoLiveDriveSession) async {
    speechCoordinator?.invalidateGuidance(keepingNotices: true)
    presentationProjection = nil
    clearTunnelEstimate()
    runtimeOccurrenceID = occurrenceID
    if let route = selectedRoute,
      let index = route.routePlan.occurrence(id: occurrenceID)?.index,
      route.edges.indices.contains(index), route.distanceMeters > 0
    {
      driveRecord.skipPlannedLap(toOccurrenceIndex: index, boundaries: route.lapBoundaryOccurrenceIndices)
      let traveled = route.edges.prefix(index).reduce(0) { $0 + $1.lengthMeters }
        + route.edges[index].lengthMeters * (runtimeFractionAlongOccurrence ?? 0)
      progressFraction = min(1, max(0, traveled / route.distanceMeters))
    }
    await refreshRemainingLaps(from: session)
    await captureAndPersistLiveCheckpoint(from: session, force: true)
  }

  /// Adds a lap to a loop the driver wants to keep running.
  ///
  /// A lap the plan does not contain cannot be conjured: `RoutePlan` is
  /// immutable and hash-bound, and its occurrences are laid down one lap at a
  /// time. So this plans the route again with one more lap and builds its own
  /// release. The new plan repeats the current one up to where the car is, so
  /// its session starts on the strict route at that same occurrence, carrying
  /// what was driven, skipped and spoken.
  ///
  /// The current drive keeps running and guiding throughout. The swap waits
  /// until the new session has placed the car itself, and is dropped if the
  /// drive leaves the road the two plans share first. Returns whether the
  /// swap is under way.
  @discardableResult
  func addOneLap() async -> Bool {
    guard isLiveDrive, !isChangingLaps,
      phase == .expressway,
      runtimeJourneyPhase == .strictRoute,
      let circuit = selectedCircuit,
      circuit.kind == .loop,
      let route = selectedRoute,
      let admissionResolver = liveJourneyAdmissionResolver,
      let previousRecommendation = circuitRecommendation,
      let entryFacilityID = circuitEntryFacilityID,
      ShutoCircuitDefinition.loopLapRange.contains(circuitLaps + 1)
    else {
      return false
    }
    isChangingLaps = true

    let laps = circuitLaps + 1
    let database = database
    let planner = planner
    let preference = route.preference
    let stopIDs = parkingStopSelection?.parkingAreaIDs ?? []
    let prepared = await Task.detached(priority: .userInitiated) {
      () -> (
        ShutoPlannedRoute,
        WholeShutoLiveJourneyAdmission,
        ShutoPlannedRouteRuntimeAssets,
        [WholeShutoJunctionPrompt],
        ShutoPlannedRoute
      )? in
      do {
        let base = try planner.planCircuit(
          circuit: circuit,
          entryFacilityID: entryFacilityID,
          exitFacilityID: route.exitFacility?.facilityID,
          destinationParkingAreaID: route.destinationParkingArea?.parkingAreaID,
          laps: laps,
          preference: preference
        )
        let extended = try planner.addingParkingStops(stopIDs, to: base)
        guard case .available(let admission) = admissionResolver(extended)
        else {
          return nil
        }
        let assets =
          try admission.runtimeAssets
          ?? ShutoPlannedRouteRuntimeCompiler.compile(
            database: database,
            route: extended
          )
        guard assets.routePlan == admission.core.selectedRoutePlan else {
          return nil
        }
        let prompts = Self.compileJunctionPrompts(
          database: database,
          route: extended,
          releasedContext: planner.releasedMovementContext
        )
        return (extended, admission, assets, prompts, base)
      } catch {
        return nil
      }
    }.value

    // The drive kept moving while that was built. Only prepare the swap if
    // it is still the same drive on the same route.
    guard let prepared,
      isLiveDrive,
      phase == .expressway,
      selectedRoute == route,
      circuitLaps == laps - 1,
      let session = liveDriveSession,
      let currentAdmission = activeLiveAdmission
    else {
      isChangingLaps = false
      if prepared == nil {
        failureCode = Self.lapChangeUnavailableCode
      }
      return false
    }

    do {
      let checkpoint = try await session.makeCheckpoint(
        savedAtMilliseconds: nowMillisecondsProvider()
      )
      let carried = try checkpoint.carried(
        from: currentAdmission.core.release,
        onto: prepared.1.core.release,
        journeyPlan: prepared.1.core.journeyPlan
      )
      let newSession = try ShutoLiveDriveSession(
        runtime: try prepared.1.core.makeRuntime(checkpoint: carried)
      )
      _ = await newSession.start()
      guard liveDriveSession === session else {
        isChangingLaps = false
        return false
      }
      let currentOccurrences = route.routePlan.occurrences
      let newOccurrences = prepared.0.routePlan.occurrences
      pendingLapSwap = PendingLapSwap(
        replacing: session,
        session: newSession,
        route: prepared.0,
        baseRoute: prepared.4,
        admission: prepared.1,
        assets: prepared.2,
        prompts: prepared.3,
        laps: laps,
        parkingStopIDs: stopIDs,
        recommendation: ShutoRouteRecommendation(
          route: prepared.0,
          surfaceAccessDistanceMeters: previousRecommendation
            .surfaceAccessDistanceMeters,
          surfaceEgressDistanceMeters: previousRecommendation
            .surfaceEgressDistanceMeters,
          totalScoreMeters: previousRecommendation.totalScoreMeters
        ),
        entryAdapter: try CoreLocationEntryTransitionAdapter(
          context: newSession.entryTransitionAdmissionContext
        ),
        egressAdapter: try newSession.surfaceEgressAdmissionContext.map {
          try CoreLocationSurfaceEgressAdapter(context: $0)
        },
        observationAdapter: try CoreLocationObservationAdapter(
          sessionID: prepared.1.core.release.releaseID,
          simulatedLocationPolicy: .reject,
          carPlayConnectionContext: .disconnected,
          sourceEvidenceProvider: liveLocationSourceEvidenceProvider
        ),
        sharedOccurrenceCount: zip(currentOccurrences, newOccurrences)
          .prefix { $0 == $1 }.count
      )
      return true
    } catch {
      isChangingLaps = false
      failureCode = Self.lapChangeUnavailableCode
      return false
    }
  }

  /// A lap added mid-drive, waiting for its own session to place the car on
  /// the plan the current drive shares with it.
  private struct PendingLapSwap {
    let replacing: ShutoLiveDriveSession
    let session: ShutoLiveDriveSession
    let route: ShutoPlannedRoute
    let baseRoute: ShutoPlannedRoute
    let admission: WholeShutoLiveJourneyAdmission
    let assets: ShutoPlannedRouteRuntimeAssets
    let prompts: [WholeShutoJunctionPrompt]
    let laps: Int
    let parkingStopIDs: [String]
    let recommendation: ShutoRouteRecommendation
    let entryAdapter: CoreLocationEntryTransitionAdapter
    let egressAdapter: CoreLocationSurfaceEgressAdapter?
    let observationAdapter: CoreLocationObservationAdapter
    /// Leading occurrences the two plans have in common. Past them the car
    /// is on a road only the current plan drives.
    let sharedOccurrenceCount: Int
  }

  /// Feeds a pending lap swap the fix the current drive just took, and moves
  /// the drive onto it once its session has placed the car. The swap is
  /// dropped once the current drive leaves the shared road or the strict
  /// route. Returns whether the drive moved onto the new lap count.
  private func advanceLapSwap(
    _ pending: PendingLapSwap,
    with observation: RouteMatcherObservation,
    driving snapshot: NavigationSnapshot
  ) async -> Bool {
    guard snapshot.journeyPhase == .strictRoute else {
      // Off the strict route the drive's own notice is what the driver
      // needs; the lap is moot and speaking it would cut that notice off.
      dropLapSwap(spoken: false)
      return false
    }
    guard (snapshot.currentOccurrenceIndex ?? 0) < pending.sharedOccurrenceCount
    else {
      dropLapSwap(spoken: true)
      return false
    }
    do {
      let update = try await pending.session.observe(observation)
      guard pendingLapSwap?.session === pending.session,
        liveDriveSession === pending.replacing,
        update.navigationSnapshot.journeyPhase == .strictRoute,
        update.navigationSnapshot.signalReacquisitionStatus == .confirmed
      else {
        return false
      }
      try configureSpeech(for: pending.route.routePlan.id)
      circuitRecommendation = pending.recommendation
      parkingStopSelection =
        pending.parkingStopIDs.isEmpty
        ? nil
        : .init(
          baseRoutePlan: pending.baseRoute.routePlan,
          parkingAreaIDs: pending.parkingStopIDs
        )
      selectedSavedRouteTemplateParameters = nil
      circuitLaps = pending.laps
      runtimeAssets = pending.assets
      liveEntryTransitionAdapter = pending.entryAdapter
      liveSurfaceEgressAdapter = pending.egressAdapter
      liveObservationAdapter = pending.observationAdapter
      activeLiveAdmission = pending.admission
      junctionPromptCache = pending.prompts
      junctionPromptCacheRoutePlan = pending.route.routePlan
      // The drive record is the journey's, not the plan's: the laps already
      // driven stay on it across the swap, and so do the cues already given.
      liveDriveSession = pending.session
      liveMatcherWasInTunnel = false
      clearTunnelEstimate()
      presentationProjection = nil
      failureCode = nil
      applyNavigationUpdate(update)
      await refreshRemainingLaps(from: pending.session)
      await captureAndPersistLiveCheckpoint(from: pending.session, force: true)
      persistCheckpoint()
      return true
    } catch {
      dropLapSwap(spoken: true)
      return false
    }
  }

  /// The driver was already told the lap is being added and may not be
  /// looking at the screen, so a lap that is not added after all is spoken
  /// unless the drive has more pressing news of its own.
  private func dropLapSwap(spoken: Bool) {
    pendingLapSwap = nil
    isChangingLaps = false
    failureCode = Self.lapChangeUnavailableCode
    if spoken { announceJourneyNotice(.lapNotAdded) }
  }

  private func refreshRemainingLaps(from session: ShutoLiveDriveSession) async {
    remainingWholeLapsAhead = await session.remainingWholeLapsAhead()
  }

  func setShowsDriveRecord(_ shown: Bool) {
    driveRecordPreferenceStore.set(shown, forKey: Self.showsDriveRecordDefaultsKey)
    guard shown != showsDriveRecord else { return }
    showsDriveRecord = shown
    driveRecord = WholeShutoDriveRecord(
      startedAtMilliseconds: shown && isLiveDrive ? nowMillisecondsProvider() : nil
    )
  }

  func setSurfaceRoutePreference(
    _ preference: WholeShutoSurfaceRoutePreference
  ) {
    driveRecordPreferenceStore.set(
      preference.rawValue,
      forKey: Self.surfaceRoutePreferenceDefaultsKey
    )
    guard preference != surfaceRoutePreference else { return }
    surfaceRoutePreference = preference
    // The preference only decides which entrances a circuit may use;
    // connecting legs always stay on ordinary roads.
    if phase == .planning, selectedCircuit != nil {
      resolveCircuitPairing(
        entranceOverride: nil,
        exitOverride: circuitExitWasOverridden ? circuitExitFacilityID : nil
      )
    }
  }

  /// Accepts the driver's word that the car is already on the selected route.
  ///
  /// The declaration only opens the join admission for a bounded window. If
  /// the matcher never settles on one exact plan occurrence, the window
  /// closes and the drive says so rather than joining somewhere unproven.
  @discardableResult
  func declareAlreadyOnRoute() async -> Bool {
    guard isLiveDrive,
      phase == .surfaceAccess || phase == .entryTransition,
      routeJoinState == .offered || routeJoinState == .unresolved,
      let session = liveDriveSession
    else {
      return false
    }
    let declared = await session.declareAlreadyOnRoute(
      atMilliseconds: nowMillisecondsProvider()
    )
    guard declared else { return false }
    if phase == .surfaceAccess {
      // The car is on the expressway, not on the ordinary-road approach, so
      // the surface leg ends here and the join takes the next fixes.
      cancelSurfaceReroute()
      speechCoordinator?.stopProviderSurface()
      phase = .entryTransition
      progressFraction = 0
    }
    routeJoinState = .resolving
    liveLocationIssueCode = nil
    return true
  }

  /// Feeds one fix to the observer as an on-route position and shows or
  /// withdraws the declaration accordingly. A declaration under way keeps
  /// the fix for the join itself.
  private func observeRouteJoinPlausibility(
    _ envelope: CoreLocationObservationEnvelope,
    session: ShutoLiveDriveSession
  ) {
    guard routeJoinState != .resolving else { return }
    if liveRouteJoinObserver == nil, let routePlan = selectedRoute?.routePlan {
      liveRouteJoinObserver = try? CoreLocationEntryTransitionAdapter(
        context: session.entryTransitionAdmissionContext
      )
      routeJoinOffer = RouteJoinOffer(routePlan: routePlan)
    }
    guard var observer = liveRouteJoinObserver,
      var offer = routeJoinOffer,
      let evidence = try? observer.adaptRouteJoin(envelope)
    else { return }
    liveRouteJoinObserver = observer
    let plausible = offer.observe(evidence)
    routeJoinOffer = offer
    switch routeJoinState {
    case .unavailable, .unresolved:
      if plausible { routeJoinState = .offered }
    case .offered:
      if !plausible { routeJoinState = .unavailable }
    case .resolving:
      break
    }
  }

  private func resetRouteJoinOffer() {
    routeJoinOffer = nil
    liveRouteJoinObserver = nil
    routeJoinState = .unavailable
  }

  /// Rest stops Core Location, and only touch or Siri brings the drive back,
  /// so a fresh fix that knows the car is moving refuses it. A car parked
  /// under a PA roof often reports an unknown speed or no fix at all, and
  /// neither is evidence of movement.
  var canRestLiveJourney: Bool {
    guard isLiveDrive, isPlaying, phase != .completed,
      liveDriveSession != nil
    else { return false }
    guard liveLocationState != .stale,
      let speed = liveVehicleSpeedMetersPerSecond, speed >= 0
    else { return true }
    return speed <= Self.restMaximumSpeedMetersPerSecond
  }

  /// Puts the live drive down for a break without ending it.
  ///
  /// A car parked at a PA leaves the route corridor, so a drive left running
  /// there reports a degraded position and a recovery search for a stop the
  /// driver chose. Resting instead releases Core Location and the voice, keeps
  /// the session and its occurrence exactly where they are, and hands the
  /// return to `resumeLiveJourney`, which the backgrounded drive already uses.
  @discardableResult
  func restLiveJourney() async -> Bool {
    guard canRestLiveJourney, let liveDriveSession else {
      return false
    }
    cancelSurfaceReroute()
    driveRecord.interruptSamples()
    invalidatePlaybackTask()
    isPlaying = false
    speechCoordinator?.stop()
    liveLocationState = .resting
    liveLocationIssueCode = nil
    liveLocationFreshnessTask?.cancel()
    liveLocationFreshnessTask = nil
    await foregroundLiveLocationController?.stop()
    speechCoordinator?.resume()
    announceJourneyNotice(.resting)
    await captureAndPersistLiveCheckpoint(from: liveDriveSession, force: true)
    return true
  }

  @discardableResult
  func finishLiveExpressway() async -> Bool {
    guard canFinishLiveExpressway, let session = liveDriveSession else {
      return false
    }
    let snapshot = await session.finishAtRouteEnd()
    guard snapshot.journeyPhase == .exitTransition,
      snapshot.egress.status == .active
    else {
      failureCode = "WHOLE_SHUTO_EXIT_HANDOFF_UNCONFIRMED"
      return false
    }
    applyLiveActorSnapshot(snapshot)
    await continueAfterExpresswayExit(using: session)
    return true
  }

  func usePreviewPlaces() {
    journeyEnding = .destination
    selectedDestinationTitle = nil
    origin = Self.previewOrigin
    destination = Self.previewDestination
    originQuery = Self.previewOrigin.title
    destinationQuery = Self.previewDestination.title
  }

  func selectDestinationPreview(_ place: WholeShutoPlace) {
    guard phase == .planning else { return }
    destination = place
    destinationQuery = place.title
    selectedDestinationTitle = place.title
    // A chosen destination is geographic context: show its pin on the
    // geographic map instead of the network diagram.
    mapMode = .geographic
  }

  func selectOriginPreview(_ place: WholeShutoPlace) {
    guard phase == .planning else { return }
    origin = place
    originQuery = place.title
    selectedOriginTitle = place.title
  }

  @discardableResult
  func resolveTypedOriginPreview() async -> Bool {
    guard phase == .planning, !usesCurrentLocationOrigin else { return false }
    do {
      let resolved = try await placeResolver.resolve(
        query: originQuery,
        near: nil
      )
      selectOriginPreview(
        WholeShutoPlace(
          title: resolved.title,
          coordinate: ShutoCoordinate(
            latitude: resolved.coordinate.latitude,
            longitude: resolved.coordinate.longitude
          )
        )
      )
      failureCode = nil
      return true
    } catch {
      failureCode = "LOCATION_UNAVAILABLE"
      return false
    }
  }

  func selectCurrentOrigin(_ coordinate: ShutoCoordinate) {
    guard phase == .planning, usesCurrentLocationOrigin else { return }
    selectedOriginTitle = nil
    origin = WholeShutoPlace(
      title: currentLocationTitle,
      coordinate: coordinate
    )
  }

  func clearDestinationPreview() {
    guard phase == .planning else { return }
    destination = nil
    selectedDestinationTitle = nil
  }

  func clearOriginPreview() {
    guard phase == .planning else { return }
    selectedOriginTitle = nil
    if !usesCurrentLocationOrigin {
      origin = nil
    }
  }

  /// Launch-argument journey fixtures for the automated suites and
  /// internal review. They compile into Debug builds only, so no shipped
  /// binary can reach a preview journey or its playback.
  #if DEBUG
    func preparePreviewJourney(startsNavigation: Bool = false) {
      cancelSurfaceRouteResolution()
      clearRouteChoiceEvaluation()
      clearCustomRouteSelection()
      usePreviewPlaces()
      do {
        recommendations = try planner.recommend(
          from: Self.previewOrigin.coordinate,
          to: Self.previewDestination.coordinate,
          preference: preference
        )
        guard let selectedRecommendation else {
          failureCode = "NO_SHUTO_ROUTE"
          return
        }
        accessRoute = Self.previewSurfaceRoute(
          from: Self.previewOrigin.coordinate,
          to: selectedRecommendation.route.entryFacility.coordinate
        )
        egressRoute = Self.previewSurfaceRoute(
          from: selectedRecommendation.route.destinationCoordinate,
          to: Self.previewDestination.coordinate
        )
        phase = .review
        prepareLiveNavigationAdmission(for: selectedRecommendation.route)
        persistCheckpoint()
        if startsNavigation {
          startNavigationSimulation()
        }
      } catch {
        failureCode = Self.failureCode(error)
      }
    }

    func prepareCompletedJourneyPreview() {
      preparePreviewJourney()
      guard phase == .review else { return }
      invalidatePlaybackTask()
      speechCoordinator?.stop()
      speechCoordinator = nil
      phase = .completed
      progressFraction = 1
      isPlaying = false
      matcherConfidence = nil
      runtimeOccurrenceID = nil
      runtimeJourneyPhase = nil
      runtimeRecoveryStatus = nil
      runtimeRecoveryTargetOccurrenceID = nil
      runtimeRecoveryDirectedEdgeID = nil
      runtimeCoordinate = destination?.coordinate
      runtimeFractionAlongOccurrence = nil
      presentationProjection = nil
      speechStatus = .stopped
      consumedGuidancePromptIDs = []
      entranceAnnouncement = nil
      isStaticJunctionPreview = false
      junctionPreviewMovementID = nil
      restoredFromCheckpoint = false
      mapMode = .geographic
      removeCheckpoint()
    }

    func prepareJunctionPreview(startsNavigation: Bool = false) {
      prepareJunctionPreview(
        entryFacilityID: "shuto.ic.b.rinkaihukutoshin",
        exitFacilityID: "shuto.ic.c2.hatsudaiminami",
        expectedMovementID:
          "shuto.jct.oi.b-westbound-to-c2-outer",
        startsNavigation: startsNavigation
      )
    }

    func prepareKasaiJunctionPreview(
      startsNavigation: Bool = false
    ) {
      prepareJunctionPreview(
        entryFacilityID: "shuto.ic.b.urayasu",
        exitFacilityID: "shuto.ic.c2.funaboribashi",
        expectedMovementID:
          "shuto.jct.kasai.b-westbound-to-c2-inner",
        startsNavigation: startsNavigation
      )
    }

    func prepareShinonomeEastboundJunctionPreview(
      startsNavigation: Bool = false
    ) {
      prepareJunctionPreview(
        entryFacilityID: "shuto.ic.b.ooi",
        exitFacilityID: "shuto.ic.10.harumi",
        expectedMovementID:
          "shuto.jct.shinonome.b-eastbound-to-10-inbound",
        startsNavigation: startsNavigation
      )
    }

    func prepareShinonomeWestboundJunctionPreview(
      startsNavigation: Bool = false
    ) {
      prepareJunctionPreview(
        entryFacilityID: "shuto.ic.b.shinkiba",
        exitFacilityID: "shuto.ic.10.harumi",
        expectedMovementID:
          "shuto.jct.shinonome.b-westbound-to-10-inbound",
        startsNavigation: startsNavigation
      )
    }

    func prepareTatsumiEastboundJunctionPreview(
      startsNavigation: Bool = false
    ) {
      prepareJunctionPreview(
        entryFacilityID: "shuto.ic.b.ariake",
        exitFacilityID: "shuto.ic.9.fukudumi",
        expectedMovementID:
          "shuto.jct.tatsumi.b-eastbound-to-9-inbound",
        startsNavigation: startsNavigation
      )
    }

    func prepareTatsumiWestboundJunctionPreview(
      startsNavigation: Bool = false
    ) {
      prepareJunctionPreview(
        entryFacilityID: "shuto.ic.b.urayasu",
        exitFacilityID: "shuto.ic.9.fukudumi",
        expectedMovementID:
          "shuto.jct.tatsumi.b-westbound-to-9-inbound",
        startsNavigation: startsNavigation
      )
    }

    private func prepareJunctionPreview(
      entryFacilityID: String,
      exitFacilityID: String,
      expectedMovementID: String,
      startsNavigation: Bool
    ) {
      cancelSurfaceRouteResolution()
      clearRouteChoiceEvaluation()
      clearCustomRouteSelection()
      do {
        let route = try planner.plan(
          entryFacilityID: entryFacilityID,
          exitFacilityID: exitFacilityID
        )
        let previewOrigin = WholeShutoPlace(
          title: route.entryFacility.nameJA,
          coordinate: route.entryFacility.coordinate
        )
        let previewDestination = WholeShutoPlace(
          title: route.destinationNameJA,
          coordinate: route.destinationCoordinate
        )
        originQuery = previewOrigin.title
        destinationQuery = previewDestination.title
        origin = previewOrigin
        destination = previewDestination
        recommendations = [
          ShutoRouteRecommendation(
            route: route,
            surfaceAccessDistanceMeters: 0,
            surfaceEgressDistanceMeters: 0,
            totalScoreMeters: route.distanceMeters
          )
        ]
        selectedRecommendationIndex = 0
        accessRoute = Self.previewSurfaceRoute(
          from: previewOrigin.coordinate,
          to: route.entryFacility.coordinate
        )
        egressRoute = Self.previewSurfaceRoute(
          from: route.destinationCoordinate,
          to: previewDestination.coordinate
        )
        guard
          let prompt = junctionPrompts.first(where: {
            $0.movementID == expectedMovementID
          })
        else {
          failureCode = "NO_RELEASED_JUNCTION_GUIDANCE"
          return
        }
        junctionPreviewMovementID = expectedMovementID
        if startsNavigation {
          phase = .review
          startNavigationSimulation(autoplay: false)
          return
        }
        isStaticJunctionPreview = true
        phase = .expressway
        progressFraction = max(0, prompt.progressFraction - 0.012)
        isPlaying = false
        mapMode = .geographic
      } catch {
        failureCode = "NO_RELEASED_JUNCTION_GUIDANCE"
      }
    }
  #endif

  func planJourney() {
    guard !isPlanning else { return }
    journeyEnding = .destination
    cancelSurfaceRouteResolution()
    clearRouteChoiceEvaluation()
    accessRoute = nil
    egressRoute = nil
    isPlanning = true
    failureCode = nil
    Task {
      defer { isPlanning = false }
      do {
        let resolvedOrigin = try await resolveOrigin()
        let resolvedDestination = try await resolveDestination(
          near: resolvedOrigin.coordinate
        )
        let routes: [ShutoRouteRecommendation]
        if let parkingID = resolvedDestination.parkingAreaID {
          routes = planner.recommend(from: resolvedOrigin.coordinate, destinationParkingAreaID: parkingID, preference: preference)
        } else {
          routes = try planner.recommend(from: resolvedOrigin.coordinate, to: resolvedDestination.coordinate, preference: preference)
        }
        guard !routes.isEmpty else {
          throw WholeShutoProductError.noExpresswayRoute
        }
        let evaluation: WholeShutoRouteChoiceEvaluation
        if resolvedDestination.parkingAreaID != nil {
          evaluation = .init(recommendations: routes, surfaceRoutesByRoutePlanID: [:], usesComparableProviderMetrics: false)
        } else {
          evaluation = await routeChoiceEvaluator.evaluate(
          recommendations: routes,
          origin: resolvedOrigin.coordinate,
          destination: resolvedDestination.coordinate
        )
        }
        origin = resolvedOrigin
        destination = resolvedDestination
        recommendations = evaluation.recommendations
        routeChoiceSurfaceRoutesByRoutePlanID =
          evaluation.surfaceRoutesByRoutePlanID
        routeChoiceMetricsByRoutePlanID =
          evaluation.usesComparableProviderMetrics
          ? Self.routeChoiceMetrics(
            recommendations: evaluation.recommendations,
            surfaceRoutesByRoutePlanID:
              evaluation.surfaceRoutesByRoutePlanID
          )
          : [:]
        selectedRecommendationIndex = 0
        clearCustomRouteSelection()
        clearCircuitRouteSelection()
        clearCircuitPlanningDraft()
        phase = .review
        progressFraction = 0
        if !applyCachedSurfaceRoutes(for: evaluation.recommendations[0]) {
          resolveSurfaceRoutes(
            for: evaluation.recommendations[0],
            origin: resolvedOrigin,
            destination: resolvedDestination
          )
        }
        persistCheckpoint()
      } catch {
        failureCode = Self.failureCode(error)
      }
    }
  }

  func selectRecommendation(at index: Int) {
    guard recommendations.indices.contains(index) else { return }
    selectedRecommendationIndex = index
    isCustomRouteSelected = false
    clearCircuitRouteSelection()
    guard let origin, let destination,
      let recommendation = selectedRecommendation
    else {
      return
    }
    preference = recommendation.route.preference
    if journeyEnding == .exit {
      selectJourneyEnding(.exit)
      return
    }
    if applyCachedSurfaceRoutes(for: recommendation) {
      persistCheckpoint()
      return
    }
    resolveSurfaceRoutes(
      for: recommendation,
      origin: origin,
      destination: destination
    )
  }

  var bundledCircuits: [ShutoCircuitDefinition] {
    ShutoCircuitDefinition.bundled
  }

  var circuitEntryFacility: ShutoNetworkDatabase.Facility? {
    facility(id: circuitEntryFacilityID)
  }

  var circuitExitFacility: ShutoNetworkDatabase.Facility? {
    facility(id: circuitExitFacilityID)
  }

  var circuitDestinationNameJA: String? {
    if let parkingID = selectedCircuit?.defaultDestinationParkingAreaID {
      return database.parkingAreas.first { $0.parkingAreaID == parkingID }?.nameJA
    }
    return circuitExitFacility?.nameJA
  }

  var canStartCircuitJourney: Bool {
    phase == .planning
      && !isResolvingCircuitPairing
      && selectedCircuit != nil
      && circuitEntryFacilityID != nil
      && (circuitExitFacilityID != nil || selectedCircuit?.defaultDestinationParkingAreaID != nil)
      && origin != nil
  }

  func selectCircuit(_ circuit: ShutoCircuitDefinition) {
    guard phase == .planning else { return }
    selectedCircuit = circuit
    journeyEnding = circuit.defaultDestinationParkingAreaID != nil ? .destination : (circuit.kind == .loop ? .returnToOrigin : .exit)
    circuitLaps = 1
    circuitEntranceCandidates = []
    circuitEntryFacilityID = nil
    circuitExitFacilityID = nil
    circuitPairingBand = nil
    circuitEntranceDistanceMeters = nil
    circuitEntranceWasOverridden = false
    circuitTariffBandsByFacilityID = [:]
    circuitExitCandidates = []
    circuitTariffBandsByExitFacilityID = [:]
    circuitRecommendedExitFacilityID = nil
    circuitExitWasOverridden = false
    if origin != nil {
      resolveCircuitPairing(entranceOverride: nil, exitOverride: nil)
    }
  }

  func clearCircuitDraft() {
    guard phase == .planning else { return }
    clearCircuitPlanningDraft()
  }

  private func clearCircuitPlanningDraft() {
    circuitTariffTask?.cancel()
    circuitTariffTask = nil
    selectedCircuit = nil
    circuitEntranceCandidates = []
    circuitEntryFacilityID = nil
    circuitExitFacilityID = nil
    circuitPairingBand = nil
    circuitEntranceDistanceMeters = nil
    circuitEntranceWasOverridden = false
    circuitExitCandidates = []
    circuitTariffBandsByExitFacilityID = [:]
    circuitRecommendedExitFacilityID = nil
    circuitExitWasOverridden = false
    isResolvingCircuitPairing = false
    startsCircuitJourneyAfterPairing = false
    circuitLaps = 1
    circuitTariffBandsByFacilityID = [:]
    circuitPairingOriginCoordinate = nil
  }

  /// Starts immediately when the derived pairing is ready; otherwise starts
  /// as soon as the in-flight pairing resolution lands. Used by the flow
  /// where the location fix arrives after the start action.
  func startCircuitJourneyWhenPaired() {
    if canStartCircuitJourney {
      startCircuitJourney()
      return
    }
    guard phase == .planning, selectedCircuit != nil, origin != nil
    else { return }
    startsCircuitJourneyAfterPairing = true
  }

  func selectCircuitEntrance(facilityID: String) {
    guard
      circuitEntranceCandidates.contains(
        where: { $0.facilityID == facilityID }
      )
    else { return }
    circuitEntranceWasOverridden = true
    resolveCircuitPairing(
      entranceOverride: facilityID,
      exitOverride: circuitExitWasOverridden ? circuitExitFacilityID : nil
    )
  }

  /// Fixes the exit of the drafted experience. Choosing the recommended
  /// exit again returns to the derived pairing.
  func selectCircuitExit(facilityID: String) {
    guard
      circuitExitCandidates.contains(where: { $0.facilityID == facilityID })
    else { return }
    resolveCircuitPairing(
      entranceOverride:
        circuitEntranceWasOverridden ? circuitEntryFacilityID : nil,
      exitOverride: facilityID
    )
  }

  func selectCircuitLaps(_ laps: Int) {
    guard selectedCircuit?.kind == .loop,
      ShutoCircuitDefinition.loopLapRange.contains(laps)
    else {
      return
    }
    circuitLaps = laps
  }

  func refreshCircuitEntrances() {
    guard phase == .planning, selectedCircuit != nil, let origin else { return }
    // A pairing for this origin that is resolved, or still resolving, stands.
    // A circuit card tap with a measured location asks again for the origin
    // the selection just used, and restarting the in-flight derivation would
    // not stop its planner work: the tap would pay for it twice.
    if let previous = circuitPairingOriginCoordinate,
      Self.distance(previous, origin.coordinate) < 50,
      isResolvingCircuitPairing
        || (circuitEntryFacilityID != nil
          && (circuitExitFacilityID != nil
            || selectedCircuit?.defaultDestinationParkingAreaID != nil))
    {
      return
    }
    resolveCircuitPairing(
      entranceOverride:
        circuitEntranceWasOverridden ? circuitEntryFacilityID : nil,
      exitOverride: circuitExitWasOverridden ? circuitExitFacilityID : nil
    )
  }

  /// Derives the entrance/exit pairing off the main actor: the nearest
  /// reachable entrance (or the driver's override), the tariff-best exit
  /// (or the driver's override, priced as that pairing), the per-alternative
  /// bands, and the priced exit list. A loop that returns to the origin
  /// takes entrance and exit together by the door-to-door drive instead.
  /// Until resolution completes the start action stays unavailable and the
  /// interface shows nothing rather than inventing a pairing or an amount.
  private func resolveCircuitPairing(
    entranceOverride: String?,
    exitOverride: String?
  ) {
    circuitTariffTask?.cancel()
    guard let circuit = selectedCircuit else { return }
    isResolvingCircuitPairing = true
    let planner = planner
    let originCoordinate = origin?.coordinate
    let tariffEvidence = activeTariffEvidence
    let includeConnectingEntrances = surfaceRoutePreference == .preferHighways
    let choosesExit = circuit.defaultDestinationParkingAreaID == nil
    let returnsToOrigin = choosesExit && circuit.kind == .loop && journeyEnding == .returnToOrigin
    circuitPairingOriginCoordinate = originCoordinate
    circuitTariffTask = Task.detached(priority: .userInitiated) {
      [weak self] in
      let returnTrips = returnsToOrigin
        ? originCoordinate.map {
          planner.returnTripCircuitPairings(
            for: circuit,
            origin: $0,
            includeConnectingEntrances: includeConnectingEntrances,
            evidence: tariffEvidence
          )
        }
        : nil
      let candidates =
        returnTrips?.map(\.entrance)
        ?? planner.circuitEntranceCandidates(
          for: circuit,
          origin: originCoordinate,
          includeConnectingEntrances: includeConnectingEntrances
        )
      let overriddenEntranceID =
        candidates.contains(where: { $0.facilityID == entranceOverride })
        ? entranceOverride
        : nil
      let entranceID =
        overriddenEntranceID
        ?? candidates.first?.facilityID
      let recommended = entranceID.flatMap { entranceID in
        returnTrips?.first { $0.entrance.facilityID == entranceID }
          ?? (try? planner.recommendedCircuitPairing(
            for: circuit,
            entranceFacilityID: entranceID,
            origin: originCoordinate,
            evidence: tariffEvidence
          ))
      }
      let exits: [ShutoNetworkDatabase.Facility] =
        choosesExit
        ? entranceID.flatMap {
          try? planner.circuitExitCandidates(for: circuit, afterEntering: $0)
        } ?? []
        : []
      if Task.isCancelled { return }
      let exitBands =
        entranceID.map {
          planner.tariffBands(
            entryFacilityID: $0,
            exitFacilityIDs: exits.map(\.facilityID),
            evidence: tariffEvidence
          )
        } ?? [:]
      let overriddenExit = exits.first {
        $0.facilityID == exitOverride
          && $0.facilityID != recommended?.exit.facilityID
      }
      let pairing: ShutoCircuitPairing?
      if let recommended, let overriddenExit {
        pairing = ShutoCircuitPairing(
          entrance: recommended.entrance,
          exit: overriddenExit,
          tariffBand: exitBands[overriddenExit.facilityID],
          entranceDistanceMeters: recommended.entranceDistanceMeters
        )
      } else {
        pairing = recommended
      }
      var bands: [String: ShutoTariffBand] = [:]
      for candidate in candidates.prefix(3) {
        if Task.isCancelled { return }
        if candidate.facilityID == pairing?.entrance.facilityID {
          bands[candidate.facilityID] = pairing?.tariffBand
          continue
        }
        if let overriddenExit {
          bands[candidate.facilityID] = try? planner.tariffBand(
            entryFacilityID: candidate.facilityID,
            exitFacilityID: overriddenExit.facilityID,
            evidence: tariffEvidence
          )
          continue
        }
        if let returnTrips {
          bands[candidate.facilityID] =
            returnTrips.first { $0.entrance.facilityID == candidate.facilityID }?.tariffBand
          continue
        }
        bands[candidate.facilityID] =
          (try? planner.recommendedCircuitPairing(
            for: circuit,
            entranceFacilityID: candidate.facilityID,
            origin: originCoordinate,
            evidence: tariffEvidence
          ))?.tariffBand
      }
      let resolvedPairing = pairing
      let resolvedBands = bands.compactMapValues { $0 }
      let resolvedCandidates = candidates
      let resolvedExits = exits
      let resolvedExitBands = exitBands
      let recommendedExitID = choosesExit ? recommended?.exit.facilityID : nil
      let exitWasOverridden = overriddenExit != nil
      await MainActor.run { [weak self] in
        guard let self, !Task.isCancelled,
          self.phase == .planning,
          self.selectedCircuit?.circuitID == circuit.circuitID
        else { return }
        self.circuitEntranceCandidates = resolvedCandidates
        self.circuitEntryFacilityID =
          resolvedPairing?.entrance.facilityID
        self.circuitExitFacilityID = choosesExit ? resolvedPairing?.exit.facilityID : nil
        self.circuitPairingBand = choosesExit ? resolvedPairing?.tariffBand : nil
        self.circuitEntranceDistanceMeters =
          resolvedPairing?.entranceDistanceMeters
        self.circuitTariffBandsByFacilityID = choosesExit ? resolvedBands : [:]
        self.circuitExitCandidates = resolvedExits
        self.circuitTariffBandsByExitFacilityID = resolvedExitBands
        self.circuitRecommendedExitFacilityID = recommendedExitID
        self.circuitExitWasOverridden = exitWasOverridden
        self.isResolvingCircuitPairing = false
        if self.startsCircuitJourneyAfterPairing {
          self.startsCircuitJourneyAfterPairing = false
          if self.canStartCircuitJourney {
            self.startCircuitJourney()
          }
        }
      }
    }
  }

  /// Fixes the chosen course before resolving its access and optional onward leg.
  @discardableResult
  func startCircuitJourney() -> Bool {
    guard
      phase == .planning,
      let circuit = selectedCircuit,
      let entryFacilityID = circuitEntryFacilityID,
      let origin
    else {
      return false
    }
    do {
      let route = try planner.planCircuit(
        circuit: circuit,
        entryFacilityID: entryFacilityID,
        exitFacilityID: circuit.defaultDestinationParkingAreaID != nil && journeyEnding != .exit ? nil : circuitExitFacilityID,
        laps: circuit.kind == .loop ? circuitLaps : 1
      )
      circuitTariffTask?.cancel()
      circuitTariffTask = nil
      cancelSurfaceRouteResolution()
      clearRouteChoiceEvaluation()
      clearCustomRouteSelection()
      recommendations = []
      selectedRecommendationIndex = 0
      let journeyDestination = route.destinationParkingArea != nil || journeyEnding == .exit
        ? routeDestination(for: route) : origin
      destination = journeyDestination
      destinationQuery = journeyDestination.title
      selectedDestinationTitle = journeyDestination.title
      let accessDistance = Self.distance(
        origin.coordinate,
        route.coordinates.first ?? route.entryFacility.coordinate
      )
      let egressDistance = Self.distance(
        route.destinationCoordinate,
        journeyDestination.coordinate
      )
      let recommendation = ShutoRouteRecommendation(
        route: route,
        surfaceAccessDistanceMeters: accessDistance,
        surfaceEgressDistanceMeters: egressDistance,
        totalScoreMeters:
          route.distanceMeters + accessDistance + egressDistance
      )
      if route.destinationParkingArea != nil { circuitPairingBand = nil }
      circuitExitFacilityID = route.exitFacility?.facilityID
      circuitRecommendation = recommendation
      isCircuitRouteSelected = true
      preference = route.preference
      phase = .review
      failureCode = nil
      resolveSurfaceRoutes(
        for: recommendation,
        origin: origin,
        destination: journeyDestination
      )
      return true
    } catch {
      failureCode = Self.failureCode(error)
      return false
    }
  }

  private func clearCircuitRouteSelection() {
    circuitRecommendation = nil
    isCircuitRouteSelected = false
    selectedSavedRouteTemplateParameters = nil
    parkingStopSelection = nil
  }

  func prepareCustomRouteDraft() {
    switch phase {
    case .review:
      guard let route = selectedRoute else { return }
      let draft = customRecommendation?.route ?? route
      if let circuit = editedCircuit, circuitEntranceCandidates.count <= 1 {
        resolveCircuitEntranceCandidatesForEditor(circuit)
      }
      customEntryFacilityID = draft.entryFacility.facilityID
      customExitFacilityID = draft.exitFacility?.facilityID
      customPreference = draft.preference
      refreshCustomRouteDraft()
    case .planning:
      // The advanced home entry drafts from the driver's surroundings:
      // nearest enterable facility in, nearest differently named exit out.
      let reference = origin?.coordinate
      let facilities = database.directionalFacilities.filter {
        $0.operationalStatus == "AVAILABLE"
      }
      func nearest(
        _ candidates: [ShutoNetworkDatabase.Facility]
      ) -> ShutoNetworkDatabase.Facility? {
        guard let reference else {
          return candidates.min { $0.facilityID < $1.facilityID }
        }
        return candidates.min {
          Self.distance(reference, $0.coordinate)
            < Self.distance(reference, $1.coordinate)
        }
      }
      guard
        let entry = nearest(facilities.filter(\.canEnter))
      else { return }
      customEntryFacilityID = entry.facilityID
      let exit = nearest(
        reachableExitCandidates.filter {
          $0.operationalStatus == "AVAILABLE"
            && !ShutoRoutePlanner.sharesTollPoint($0, entry)
        }
      )
      customExitFacilityID = exit?.facilityID
      customPreference = .recommended
      refreshCustomRouteDraft()
    default:
      return
    }
  }

  func selectCustomEntry(facilityID: String) {
    guard let facility = facility(id: facilityID),
      facility.canEnter,
      facility.operationalStatus == "AVAILABLE",
      editedCircuit == nil
        || circuitEntranceCandidates.contains(where: {
          $0.facilityID == facilityID
        })
    else { return }
    customEntryFacilityID = facilityID
    // The pair is always plannable or half-chosen, never silently
    // substituted: an exit this entrance cannot reach is cleared for the
    // driver to choose again among the exits it does reach.
    if let exitID = customExitFacilityID,
      !reachableExitCandidates.contains(where: { $0.facilityID == exitID })
    {
      customExitFacilityID = nil
    }
    refreshCustomRouteDraft()
  }

  func selectCustomExit(facilityID: String) {
    guard let facility = facility(id: facilityID),
      facility.canExit,
      facility.operationalStatus == "AVAILABLE",
      editedCircuit == nil
        || reachableExitCandidates.contains(where: {
          $0.facilityID == facilityID
        })
    else { return }
    customExitFacilityID = facilityID
    if let entryID = customEntryFacilityID, editedCircuit == nil,
      !entryCandidatesReachingExit.contains(where: { $0.facilityID == entryID })
    {
      customEntryFacilityID = nil
    }
    refreshCustomRouteDraft()
  }

  func selectCustomPreference(_ preference: ShutoRoutePreference) {
    customPreference = preference
    refreshCustomRouteDraft()
  }

  @discardableResult
  func applyCustomRoute() -> Bool {
    guard let origin, let base = customDraftRoute else { return false }
    let stopIDs = parkingStopSelection?.parkingAreaIDs ?? []
    let route: ShutoPlannedRoute
    do { route = try planner.addingParkingStops(stopIDs, to: base) }
    catch { failureCode = "PARKING_STOP_UNAVAILABLE"; return false }
    let destination: WholeShutoPlace
    switch phase {
    case .review:
      guard let existing = self.destination else { return false }
      if existing.parkingAreaID != nil && route.destinationParkingArea == nil {
        journeyEnding = .exit
      }
      destination = journeyEnding == .exit ? routeDestination(for: route) : existing
    case .planning:
      journeyEnding = .exit
      destination = routeDestination(for: route)
      cancelSurfaceRouteResolution()
      clearRouteChoiceEvaluation()
      recommendations = []
      selectedRecommendationIndex = 0
      phase = .review
    default:
      return false
    }
    self.destination = destination
    destinationQuery = destination.title
    selectedDestinationTitle = destination.title
    let accessDistance = Self.distance(
      origin.coordinate,
      route.coordinates.first ?? route.entryFacility.coordinate
    )
    let egressDistance = Self.distance(
      route.destinationCoordinate,
      destination.coordinate
    )
    let recommendation = ShutoRouteRecommendation(
      route: route,
      surfaceAccessDistanceMeters: accessDistance,
      surfaceEgressDistanceMeters: egressDistance,
      totalScoreMeters: route.distanceMeters + accessDistance + egressDistance
    )
    if editedCircuit != nil {
      // The draft is the same experience with another pairing, so the
      // circuit, its lap count, and its saved-route identity stay selected.
      circuitEntryFacilityID = route.entryFacility.facilityID
      circuitExitFacilityID = route.exitFacility?.facilityID
      circuitPairingBand = route.exitFacility.flatMap { exit in
        try? planner.tariffBand(
          entryFacilityID: route.entryFacility.facilityID,
          exitFacilityID: exit.facilityID,
          evidence: activeTariffEvidence
        )
      }
      circuitEntranceDistanceMeters = accessDistance
      if let band = circuitPairingBand {
        circuitTariffBandsByFacilityID[route.entryFacility.facilityID] = band
      }
      circuitEntranceWasOverridden = true
      circuitExitWasOverridden = route.exitFacility != nil
      circuitRecommendation = recommendation
      selectedSavedRouteTemplateParameters = nil
    } else {
      customRecommendation = recommendation
      isCustomRouteSelected = true
      clearCircuitRouteSelection()
    }
    parkingStopSelection = stopIDs.isEmpty ? nil : .init(baseRoutePlan: base.routePlan, parkingAreaIDs: stopIDs)
    preference = route.preference
    failureCode = nil
    resolveSurfaceRoutes(
      for: recommendation,
      origin: origin,
      destination: destination
    )
    return true
  }

  /// A restored circuit knows only its own entrance. The editor needs the
  /// experience's full direction-valid list, resolved off the main actor
  /// exactly as the planning-time pairing resolves it.
  private func resolveCircuitEntranceCandidatesForEditor(
    _ circuit: ShutoCircuitDefinition
  ) {
    let planner = planner
    let originCoordinate = origin?.coordinate
    let tariffEvidence = activeTariffEvidence
    let returnsToOrigin =
      circuit.defaultDestinationParkingAreaID == nil && circuit.kind == .loop
      && journeyEnding == .returnToOrigin
    circuitTariffTask?.cancel()
    circuitTariffTask = Task.detached(priority: .userInitiated) {
      [weak self] in
      let candidates =
        returnsToOrigin
        ? originCoordinate.map {
          planner.returnTripCircuitPairings(
            for: circuit,
            origin: $0,
            evidence: tariffEvidence
          ).map(\.entrance)
        } ?? []
        : planner.circuitEntranceCandidates(
          for: circuit,
          origin: originCoordinate
        )
      await MainActor.run { [weak self] in
        guard let self, !Task.isCancelled,
          self.phase == .review,
          self.selectedCircuit?.circuitID == circuit.circuitID
        else { return }
        self.circuitEntranceCandidates = candidates
      }
    }
  }

  private func routeDestination(for route: ShutoPlannedRoute) -> WholeShutoPlace {
    WholeShutoPlace(
      title: route.destinationNameJA,
      coordinate: route.destinationCoordinate,
      parkingAreaID: route.destinationParkingArea?.parkingAreaID
    )
  }

  func selectJourneyEnding(
    _ ending: WholeShutoJourneyEnding,
    destination place: WholeShutoPlace? = nil
  ) {
    guard phase == .review, let origin, let recommendation = selectedRecommendation else { return }
    let target: WholeShutoPlace
    switch ending {
    case .returnToOrigin: target = origin
    case .exit: target = routeDestination(for: recommendation.route)
    case .destination:
      guard let place else { return }
      target = place
    }
    journeyEnding = ending
    destination = target
    destinationQuery = target.title
    selectedDestinationTitle = target.title
    clearRouteChoiceEvaluation()
    resolveSurfaceRoutes(for: recommendation, origin: origin, destination: target)
    persistCheckpoint()
  }

  func selectJourneyParkingDestination(_ parkingID: String) async throws {
    guard phase == .review, let previous = selectedRoute, let origin else { throw ShutoNetworkError.routeUnavailable }
    let planner = planner
    let circuit = isCircuitRouteSelected ? selectedCircuit : nil
    let laps = circuitLaps
    let route = try await Task.detached(priority: .userInitiated) {
      if let circuit {
        return try planner.planCircuit(circuit: circuit, entryFacilityID: previous.entryFacility.facilityID, destinationParkingAreaID: parkingID, laps: laps, preference: previous.preference)
      }
      return try planner.plan(entryFacilityID: previous.entryFacility.facilityID, destinationParkingAreaID: parkingID, preference: previous.preference)
    }.value
    guard phase == .review, selectedRoute == previous else { return }
    let access = Self.distance(origin.coordinate, route.coordinates.first ?? route.entryFacility.coordinate)
    let recommendation = ShutoRouteRecommendation(route: route, surfaceAccessDistanceMeters: access, surfaceEgressDistanceMeters: 0, totalScoreMeters: route.distanceMeters + access)
    if circuit != nil {
      circuitRecommendation = recommendation
      circuitExitFacilityID = nil
      circuitPairingBand = nil
    } else {
      recommendations = []
      selectedRecommendationIndex = 0
      customRecommendation = recommendation
      isCustomRouteSelected = true
      customDraftRoute = route
      customEntryFacilityID = route.entryFacility.facilityID
      customExitFacilityID = nil
    }
    parkingStopSelection = nil
    selectedSavedRouteTemplateParameters = nil
    journeyEnding = .destination
    let place = routeDestination(for: route)
    destination = place
    destinationQuery = place.title
    selectedDestinationTitle = place.title
    clearRouteChoiceEvaluation()
    resolveSurfaceRoutes(for: recommendation, origin: origin, destination: place)
    persistCheckpoint()
  }

  func prepareExitForOnwardJourney() async throws {
    guard endsAtParkingArea else { return }
    let candidates = try await journeyExitCandidates()
    guard let exit = candidates.first else { throw ShutoNetworkError.routeUnavailable }
    try await selectJourneyExit(exit.facilityID)
  }

  func journeyExitCandidates() async throws -> [ShutoNetworkDatabase.Facility] {
    guard let route = selectedRoute else { return [] }
    let planner = planner
    let circuit = isCircuitRouteSelected ? selectedCircuit : nil
    let facilities = database.directionalFacilities
    return try await Task.detached(priority: .userInitiated) {
      if let circuit {
        return try planner.circuitExitCandidates(
          for: circuit, afterEntering: route.entryFacility.facilityID
        )
      }
      // Only exits the entrance reaches, nearest to where the route ends now
      // (the PA for a PA-ended route), so the default ending stays local.
      let end = route.destinationCoordinate
      return planner.exitCandidates(
        facilities.filter { $0.canExit && $0.operationalStatus == "AVAILABLE" },
        reachableAfterEntering: route.entryFacility.facilityID
      )
      .map { ($0, Self.distance($0.coordinate, end)) }
      .sorted {
        if $0.1 != $1.1 { return $0.1 < $1.1 }
        return $0.0.facilityID < $1.0.facilityID
      }
      .map(\.0)
    }.value
  }

  func selectJourneyExit(_ facilityID: String) async throws {
    guard phase == .review, let previous = selectedRoute else { return }
    if previous.exitFacility?.facilityID == facilityID {
      selectJourneyEnding(.exit)
      return
    }
    let planner = planner
    let circuit = isCircuitRouteSelected ? selectedCircuit : nil
    let laps = circuitLaps
    let stopIDs = parkingStopSelection?.parkingAreaIDs ?? []
    let base = try await Task.detached(priority: .userInitiated) {
      if let circuit {
        return try planner.planCircuit(
          circuit: circuit, entryFacilityID: previous.entryFacility.facilityID,
          exitFacilityID: facilityID, laps: circuit.kind == .loop ? laps : 1
        )
      }
      return try planner.plan(
        entryFacilityID: previous.entryFacility.facilityID,
        exitFacilityID: facilityID, preference: previous.preference
      )
    }.value
    let route = try planner.addingParkingStops(stopIDs, to: base)
    guard phase == .review, selectedRoute == previous, let origin else { return }
    let accessDistance = Self.distance(origin.coordinate, route.coordinates.first ?? route.entryFacility.coordinate)
    let recommendation = ShutoRouteRecommendation(
      route: route, surfaceAccessDistanceMeters: accessDistance,
      surfaceEgressDistanceMeters: 0, totalScoreMeters: route.distanceMeters + accessDistance
    )
    if circuit != nil {
      circuitRecommendation = recommendation
      circuitExitFacilityID = facilityID
      circuitPairingBand = try? planner.tariffBand(
        entryFacilityID: route.entryFacility.facilityID,
        exitFacilityID: facilityID, evidence: activeTariffEvidence
      )
    } else {
      customRecommendation = recommendation
      isCustomRouteSelected = true
    }
    parkingStopSelection = stopIDs.isEmpty ? nil : .init(baseRoutePlan: base.routePlan, parkingAreaIDs: stopIDs)
    selectedSavedRouteTemplateParameters = nil
    selectJourneyEnding(.exit)
  }

  func resolveJourneyDestination(_ query: String) async throws -> WholeShutoPlace {
    guard phase == .review, let origin else {
      throw WholeShutoProductError.locationUnavailable
    }
    let place = try await placeResolver.resolve(
      query: query,
      near: .init(latitude: origin.coordinate.latitude, longitude: origin.coordinate.longitude)
    )
    return WholeShutoPlace(
      title: place.title,
      coordinate: .init(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
    )
  }

  func retrySurfaceRoutes() {
    guard
      phase == .review,
      let recommendation = selectedRecommendation,
      let origin,
      let destination
    else {
      return
    }
    resolveSurfaceRoutes(
      for: recommendation,
      origin: origin,
      destination: destination
    )
  }

  private func resolveSurfaceRoutes(
    for recommendation: ShutoRouteRecommendation,
    origin: WholeShutoPlace,
    destination: WholeShutoPlace
  ) {
    prepareLiveNavigationAdmission(for: recommendation.route)
    cancelSurfaceRouteResolution()
    accessRoute = nil
    egressRoute = nil
    isUpdatingSurfaceRoute = true
    failureCode = nil

    let requestID = UUID()
    let routePlanID = recommendation.route.routePlan.id
    // Surface legs target the plan's own directional ramp mouths: a full
    // IC's opposite-direction ramps can sit hundreds of meters apart, so
    // the IC representative point is not the navigation target. A ramp
    // mouth sits on the expressway approach structure, though, and the
    // surface provider cannot always terminate a leg there — those legs
    // fall back to the facility's representative point rather than
    // failing the journey.
    let entry =
      recommendation.route.coordinates.first
      ?? recommendation.route.entryFacility.coordinate
    let entryFallback = recommendation.route.entryFacility.coordinate
    let exit =
      recommendation.route.coordinates.last
      ?? recommendation.route.destinationCoordinate
    let exitFallback = recommendation.route.destinationCoordinate
    let resolver = surfaceRouteResolver
    let endsAtExit = !requiresSurfaceEgress
    surfaceRouteRequestID = requestID
    surfaceRouteTask = Task { [weak self] in
      func leg(
        from start: ShutoCoordinate,
        to target: ShutoCoordinate,
        fallback: (from: ShutoCoordinate, to: ShutoCoordinate)
      ) async -> WholeShutoSurfaceRoute? {
        if let resolved = await resolver.route(from: start, to: target) {
          return resolved
        }
        guard !Task.isCancelled,
          fallback.from != start || fallback.to != target
        else { return nil }
        return await resolver.route(from: fallback.from, to: fallback.to)
      }
      async let access = leg(
        from: origin.coordinate,
        to: entry,
        fallback: (origin.coordinate, entryFallback)
      )
      async let egress: WholeShutoSurfaceRoute? = endsAtExit ? nil : leg(
        from: exit,
        to: destination.coordinate,
        fallback: (exitFallback, destination.coordinate)
      )
      let resolvedRoutes = await (access, egress)

      guard
        !Task.isCancelled,
        let self,
        self.surfaceRouteRequestID == requestID,
        self.selectedRoute?.routePlan.id == routePlanID
      else {
        return
      }
      self.accessRoute = resolvedRoutes.0
      self.egressRoute = resolvedRoutes.1
      if let access = resolvedRoutes.0, let egress = resolvedRoutes.1 {
        let routes = WholeShutoRouteChoiceSurfaceRoutes(
          access: access,
          egress: egress
        )
        self.routeChoiceSurfaceRoutesByRoutePlanID[routePlanID] = routes
        self.routeChoiceMetricsByRoutePlanID[routePlanID] =
          Self.routeChoiceMetrics(
            for: recommendation.route,
            accessRoute: access,
            egressRoute: egress
          )
      }
      self.isUpdatingSurfaceRoute = false
      self.failureCode =
        resolvedRoutes.0 == nil || (!endsAtExit && resolvedRoutes.1 == nil)
        ? "SURFACE_ROUTE_UNAVAILABLE" : nil
      self.surfaceRouteRequestID = nil
      self.surfaceRouteTask = nil
      self.persistCheckpoint()
    }
  }

  private func cancelSurfaceRouteResolution() {
    surfaceRouteTask?.cancel()
    surfaceRouteTask = nil
    surfaceRouteRequestID = nil
    isUpdatingSurfaceRoute = false
  }

  @discardableResult
  private func applyCachedSurfaceRoutes(
    for recommendation: ShutoRouteRecommendation
  ) -> Bool {
    guard
      let routes = routeChoiceSurfaceRoutesByRoutePlanID[
        recommendation.route.routePlan.id
      ]
    else {
      return false
    }
    prepareLiveNavigationAdmission(for: recommendation.route)
    cancelSurfaceRouteResolution()
    accessRoute = routes.access
    egressRoute = routes.egress
    failureCode = nil
    return true
  }

  private func clearRouteChoiceEvaluation() {
    routeChoiceSurfaceRoutesByRoutePlanID = [:]
    routeChoiceMetricsByRoutePlanID = [:]
  }

  /// Deterministic route playback for the automated suites and internal
  /// review. It compiles into Debug builds only: a shipped binary has no
  /// code path that drives the journey from anything but Core Location.
  #if DEBUG
    func startNavigationSimulation(autoplay: Bool = true) {
      guard phase == .review, let route = selectedRoute else { return }
      guard isJourneyReadyForPreview else {
        if !isUpdatingSurfaceRoute {
          failureCode = "SURFACE_ROUTE_UNAVAILABLE"
        }
        return
      }
      do {
        let assets = try ShutoPlannedRouteRuntimeCompiler.compile(
          database: database,
          route: route
        )
        runtimeAssets = assets
        driveSimulator = try NavigationDriveSimulator(
          route: route,
          runtimeAssets: assets,
          configuration: NavigationDriveSimulationConfiguration(
            sampleFractions: route.destinationParkingArea == nil ? [0.15, 0.5, 0.85] : [0.15, 0.5, 0.95],
            maximumSampleSpacingMeters: 30,
            timing: .routeSpeed,
            horizontalAccuracyMeters: 2,
            speedMetersPerSecond:
              Self.simulationReferenceSpeedMetersPerSecond
          ),
          speed: Self.simulationPlaybackSpeed
        )
        liveDriveSession = nil
        liveEntryTransitionAdapter = nil
        liveSurfaceEgressAdapter = nil
        liveNavigationCheckpoint = nil
        isLiveDrive = false
        liveLocationState = .inactive
        liveLocationIssueCode = nil
        liveLocationFreshnessTask?.cancel()
        liveLocationFreshnessTask = nil
        try configureSpeech(for: route.routePlan.id)
      } catch {
        failureCode = "WHOLE_SHUTO_RUNTIME_COMPILATION_FAILED"
        return
      }
      failureCode = nil
      phase = accessRoute == nil ? .entryTransition : .surfaceAccess
      progressFraction = 0
      isPlaying = autoplay
      matcherConfidence = nil
      runtimeOccurrenceID = nil
      runtimeJourneyPhase = nil
      runtimeRecoveryStatus = nil
      runtimeRecoveryTargetOccurrenceID = nil
      runtimeRecoveryDirectedEdgeID = nil
      runtimeCoordinate = nil
      runtimeFractionAlongOccurrence = nil
      presentationProjection = nil
      consumedGuidancePromptIDs = []
      entranceAnnouncement = nil
      isStaticJunctionPreview = false
      restoredFromCheckpoint = false
      mapMode = .geographic
      persistCheckpoint()
      if autoplay {
        startPlaybackLoop()
      }
    }
  #endif

  /// Creates the speech output and prepares it for the guidance voice ahead
  /// of the first cue, so starting a drive does not wait on the audio server.
  func prewarmSpeechOutput() {
    (speechOutput as? LazyAVSpeechGuidanceOutput)?.prewarm(
      languageCode: languageSelectionProvider().guidanceVoiceLocale.speechLanguageCode
    )
  }

  /// Starts only after one exact release-bound journey has constructed every
  /// actor and adapter. Core Location is attached last.
  @discardableResult
  func startLiveJourney() async -> Bool {
    guard !isStartingLiveNavigation,
      phase == .review,
      let route = selectedRoute
    else {
      return false
    }
    guard !isUpdatingSurfaceRoute else {
      failureCode = Self.surfaceRoutePreparingCode
      return false
    }
    guard isJourneyReadyForPreview else {
      failureCode = "SURFACE_ROUTE_UNAVAILABLE"
      return false
    }
    let providerAccessRoute = accessRoute
    let providerEgressRoute = egressRoute
    liveLocationFreshnessTask?.cancel()
    liveDriveSession = nil
    liveEntryTransitionAdapter = nil
    liveSurfaceEgressAdapter = nil
    liveNavigationCheckpoint = nil
    pendingLiveNavigationCheckpoint = nil
    activeLiveAdmission = nil
    liveObservationAdapter = nil
    foregroundLiveLocationController = nil
    liveLocationSubscriptions.removeAll()
    isLiveDrive = false
    liveLocationState = .inactive
    liveLocationIssueCode = nil
    liveLocationStartedAtMilliseconds = nil
    lastLiveObservationAtMilliseconds = nil
    lastUsableLiveObservationAtMilliseconds = nil
    lastAdmittedLiveFixAtMilliseconds = nil
    isHoldingLivePosition = false
    liveVehicleCourseDegrees = nil
    liveVehicleSpeedMetersPerSecond = nil
    lastLiveCheckpointPersistedAtMilliseconds = nil
    resetDriveEntry()
    cancelSurfaceReroute()
    guard matchingLiveAdmissions.count == 1,
      let admission = matchingLiveAdmissions.first,
      let preparedRuntimeAssets = matchingLiveRuntimeAssets,
      let preparedRuntime = matchingPreparedLiveRuntime,
      junctionPromptCacheRoutePlan == route.routePlan
    else {
      failureCode = liveNavigationBlockerCode
      return false
    }
    isStartingLiveNavigation = true
    defer { isStartingLiveNavigation = false }

    do {
      let prepared = try await Task.detached(priority: .userInitiated) {
        let session = try ShutoLiveDriveSession(runtime: preparedRuntime)
        return (preparedRuntimeAssets, session)
      }.value
      let assets = prepared.0
      let session = prepared.1
      guard phase == .review,
        selectedRoute == route,
        matchingLiveAdmissions.count == 1,
        matchingLiveAdmissions.first?.core.release.runtimeIdentity
          == admission.core.release.runtimeIdentity
      else {
        return false
      }
      guard assets.routePlan == admission.core.selectedRoutePlan else {
        failureCode = Self.liveNavigationRuntimeInvalidCode
        return false
      }
      let entryAdapter = try CoreLocationEntryTransitionAdapter(
        context: session.entryTransitionAdmissionContext
      )
      let egressAdapter = try session.surfaceEgressAdmissionContext.map {
        try CoreLocationSurfaceEgressAdapter(context: $0)
      }
      let observationAdapter = try CoreLocationObservationAdapter(
        sessionID: admission.core.release.releaseID,
        simulatedLocationPolicy: .reject,
        carPlayConnectionContext: .disconnected,
        sourceEvidenceProvider: liveLocationSourceEvidenceProvider
      )

      runtimeAssets = assets
      driveSimulator = nil
      liveDriveSession = session
      liveEntryTransitionAdapter = entryAdapter
      liveSurfaceEgressAdapter = egressAdapter
      liveObservationAdapter = observationAdapter
      activeLiveAdmission = admission
      accessRoute = admission.accessRoute ?? providerAccessRoute
      egressRoute = admission.egressRoute ?? providerEgressRoute
      try configureSpeech(for: route.routePlan.id)

      let controller = try ForegroundNavigationLocationController(
        authority: .releasedProduct(
          admission.core.foregroundLiveInputAuthority
        ),
        consumer: self,
        source: liveLocationSource
      )
      observeLiveLocationController(controller)
      foregroundLiveLocationController = controller
      preparedLiveRuntime = nil

      isLiveDrive = true
      isPlaying = true
      restoredFromCheckpoint = false
      phase =
        accessRoute == nil ? .entryTransition : .surfaceAccess
      progressFraction = 0
      matcherConfidence = .low
      runtimeOccurrenceID = nil
      runtimeJourneyPhase = nil
      runtimeRecoveryStatus = nil
      runtimeRecoveryTargetOccurrenceID = nil
      runtimeRecoveryDirectedEdgeID = nil
      runtimeCoordinate = nil
      runtimeFractionAlongOccurrence = nil
      liveMatcherWasInTunnel = false
      resetRouteJoinOffer()
      driveRecord = WholeShutoDriveRecord(
        startedAtMilliseconds: showsDriveRecord ? nowMillisecondsProvider() : nil
      )
      driveHistoryIssue = nil
      remainingWholeLapsAhead = 0
      clearTunnelEstimate()
      presentationProjection = nil
      consumedGuidancePromptIDs = []
      entranceAnnouncement = nil
      surfaceSpeechGeneration = 0
      isStaticJunctionPreview = false
      liveLocationState = .acquiring
      liveLocationIssueCode = nil
      liveLocationStartedAtMilliseconds = nowMillisecondsProvider()
      lastLiveObservationAtMilliseconds = nil
      lastUsableLiveObservationAtMilliseconds = nil
      lastAdmittedLiveFixAtMilliseconds = nil
      isHoldingLivePosition = false
      liveVehicleCourseDegrees = nil
      liveVehicleSpeedMetersPerSecond = nil
      positionLossAnnounced = false
      positionLossAnnouncedAtMilliseconds = nil
      failureCode = nil

      let initialSnapshot = await session.start()
      if phase == .surfaceAccess {
        runtimeJourneyPhase = initialSnapshot.journeyPhase
        runtimeRecoveryStatus = initialSnapshot.recovery.status
        runtimeRecoveryTargetOccurrenceID =
          initialSnapshot.recovery.chosenRejoinOccurrenceID
      } else {
        applyLiveActorSnapshot(initialSnapshot)
      }
      scheduleLiveSurfaceSpeech(forceCurrentStep: true)
      if phase == .entryTransition { announceJourneyNotice(.started) }
      scheduleLiveLocationFreshnessCheck()
      await captureAndPersistLiveCheckpoint(from: session, force: true)
      controller.start()
      return true
    } catch {
      liveDriveSession = nil
      liveEntryTransitionAdapter = nil
      liveSurfaceEgressAdapter = nil
      liveObservationAdapter = nil
      activeLiveAdmission = nil
      foregroundLiveLocationController = nil
      liveLocationSubscriptions.removeAll()
      isLiveDrive = false
      isPlaying = false
      liveLocationState = .failed
      liveLocationIssueCode = Self.liveNavigationRuntimeInvalidCode
      failureCode = Self.liveNavigationRuntimeInvalidCode
      return false
    }
  }

  private func observeLiveLocationController(
    _ controller: ForegroundNavigationLocationController
  ) {
    liveLocationSubscriptions.removeAll()
    controller.$state
      .sink { [weak self] state in
        self?.consumeForegroundLiveLocationState(state)
      }
      .store(in: &liveLocationSubscriptions)
    controller.$lastTransientFailureCode
      .compactMap { $0 }
      .sink { [weak self] code in
        guard self?.isLiveDrive == true else { return }
        self?.liveLocationState = .degraded
        self?.liveLocationIssueCode = code
        self?.matcherConfidence = .low
      }
      .store(in: &liveLocationSubscriptions)
  }

  func consumeLiveObservationForTesting(
    _ envelope: CoreLocationObservationEnvelope
  ) async {
    guard isLiveDrive, isPlaying, let session = liveDriveSession else {
      return
    }
    // Rest and reset advance the playback generation and a lap swap replaces
    // the session. A fix whose actor call outlives either is dropped, not
    // written over the state that replaced it.
    let generation = playbackGeneration
    func isCurrent() -> Bool {
      playbackGeneration == generation && liveDriveSession === session
    }
    let observation = envelope.observation
    // Horizontal accuracy is an input to the surface corridor width, never a
    // reason to call the position lost: an on-route fix at 50 m accuracy under
    // an elevated road is still the car's position.
    if phase == .surfaceAccess || phase == .surfaceEgress {
      guard observation.receivedAtMilliseconds - observation.observedAtMilliseconds < 10_000
      else {
        liveLocationState = .degraded
        liveLocationIssueCode = "CORE_LOCATION_SURFACE_FIX_UNCERTAIN"
        matcherConfidence = .low
        speechCoordinator?.invalidateGuidance(keepingNotices: true)
        return
      }
    }
    let coordinate = ShutoCoordinate(
      latitude: observation.coordinate.latitude,
      longitude: observation.coordinate.longitude
    )
    // Expressway presentation uses only route-resolved matcher projection.
    // A raw weak or ambiguous GPS fix must not displace the last accepted
    // route position on stacked roads or in a tunnel.
    if phase != .expressway {
      runtimeCoordinate = coordinate
    }
    lastLiveObservationAtMilliseconds = observation.receivedAtMilliseconds
    liveVehicleCourseDegrees = NavigationDirectionPresentation.vehicleCourse(from: observation)
    liveVehicleSpeedMetersPerSecond = observation.speedMetersPerSecond
    liveLocationStartedAtMilliseconds =
      liveLocationStartedAtMilliseconds
      ?? observation.receivedAtMilliseconds
    // On the expressway only a fix the matcher placed on a corridor road
    // keeps the position live; that is decided after the session sees it.
    if phase != .expressway {
      markLiveFixUsable(atMilliseconds: observation.receivedAtMilliseconds)
    }
    if showsDriveRecord {
      driveRecord.observe(
        speedMetersPerSecond: observation.speedMetersPerSecond,
        atMilliseconds: observation.receivedAtMilliseconds
      )
    }
    if phase == .surfaceAccess || phase == .entryTransition {
      observeRouteJoinPlausibility(envelope, session: session)
    }

    do {
      switch phase {
      case .surfaceAccess:
        // Every fix also goes to the ramp admission: the car can reach the
        // entrance before the provider's leg ends there, and the admission's
        // own route-head test refuses a street that only passes it.
        guard var adapter = liveEntryTransitionAdapter else {
          throw WholeShutoProductError.noExpresswayRoute
        }
        let evidence = try adapter.adapt(envelope)
        liveEntryTransitionAdapter = adapter
        updateLiveSurfaceProgress(
          coordinate: coordinate,
          horizontalAccuracyMeters:
            observation.horizontalAccuracyMeters,
          route: accessRoute,
          completesJourney: false,
          // On a corridor road the car has left the ordinary-road leg for the
          // expressway; a highway-avoiding reroute would only send it back.
          reroutesOffRoute: evidence.confidence == .lost
        )
        let isNearEntrance = isNearSurfaceRouteEnd(
          coordinate: coordinate,
          horizontalAccuracyMeters:
            observation.horizontalAccuracyMeters,
          route: accessRoute,
          thresholdMeters: Self.surfaceEntryTransitionRadiusMeters
        )
        if isNearEntrance {
          cancelSurfaceReroute()
        }
        consecutivePastEntranceObservations = 0
        let update = try await session.observeEntryTransitionEvidence(
          evidence
        )
        guard isCurrent() else { return }
        if isNearEntrance
          || update.navigationSnapshot.journeyPhase == .strictRoute
        {
          matcherConfidence = evidence.confidence
        }
        if update.navigationSnapshot.journeyPhase == .strictRoute
          || isNearSurfaceRouteEnd(
            coordinate: coordinate,
            horizontalAccuracyMeters:
              observation.horizontalAccuracyMeters,
            route: accessRoute,
            thresholdMeters: 60
          )
        {
          applyLiveActorSnapshot(update.navigationSnapshot)
        }
        // A rejected ramp admission only says the car is not on the ramp yet.
        // The surface polyline still owns the position, so the state stays
        // available and the driver keeps the approach guidance.
      case .entryTransition:
        guard var adapter = liveEntryTransitionAdapter else {
          throw WholeShutoProductError.noExpresswayRoute
        }
        // One fix feeds one matcher step. While the driver's declaration
        // stands the ramp admission has nothing left to prove — it can only
        // reject an on-route edge — so the join path takes the observation
        // instead of both paths racing the same matcher.
        if routeJoinState == .resolving {
          let evidence = try adapter.adaptRouteJoin(envelope)
          liveEntryTransitionAdapter = adapter
          let update = try await session.observeRouteJoinEvidence(evidence)
          guard isCurrent() else { return }
          matcherConfidence = evidence.confidence
          applyLiveActorSnapshot(update.navigationSnapshot)
          if update.status == .joined {
            routeJoinState = .unavailable
            liveLocationIssueCode = nil
          } else if update.rejectionReason == .declarationExpired {
            routeJoinState = .unresolved
            liveLocationState = .degraded
            liveLocationIssueCode = Self.routeJoinUnresolvedCode
          }
          break
        }
        let evidence = try adapter.adapt(envelope)
        liveEntryTransitionAdapter = adapter
        let update = try await session.observeEntryTransitionEvidence(
          evidence
        )
        guard isCurrent() else { return }
        matcherConfidence = evidence.confidence
        entryStretchGuidanceFrame = update.entryStretchGuidanceFrame
        applyLiveActorSnapshot(update.navigationSnapshot)
        // A fix that does not yet prove the ramp is not a weak position:
        // only the stale-fix path may say that.
        if let rejection = update.rejectionReason {
          liveLocationIssueCode = rejection.rawValue
        }
        resumeSurfaceAccessIfEntrancePassed(
          evidence: evidence,
          coordinate: coordinate,
          horizontalAccuracyMeters: observation.horizontalAccuracyMeters,
          journeyPhase: update.navigationSnapshot.journeyPhase
        )
      case .expressway:
        let update = try await session.observe(observation)
        guard isCurrent() else { return }
        applyNavigationUpdate(update)
        if phase == .completed { return }
        // Off the plan the car has left the corridor by definition: a fresh
        // fix there is still a usable one, not a lost position.
        if update.matcherEstimate.confidence == .lost,
          update.navigationSnapshot.journeyPhase != .routeRecovery
        {
          evaluateLiveLocationFreshness(
            atMilliseconds: observation.receivedAtMilliseconds
          )
        } else {
          markLiveFixUsable(atMilliseconds: observation.receivedAtMilliseconds)
        }
        updateLivePositionHolding(
          from: update,
          atMilliseconds: observation.receivedAtMilliseconds
        )
        if let pendingLapSwap,
          await advanceLapSwap(
            pendingLapSwap,
            with: observation,
            driving: update.navigationSnapshot
          )
        {
          return
        }
        if update.navigationSnapshot.journeyPhase == .surfaceEgress,
          update.navigationSnapshot.lastPhaseTransitionTrigger == "UNPLANNED_EXIT"
        {
          handOverAfterUnplannedExit(
            at: coordinate,
            attemptedAtMilliseconds: observation.receivedAtMilliseconds
          )
          break
        }
        // The session recognises the exit from where the car went.
        if update.navigationSnapshot.journeyPhase == .exitTransition {
          applyLiveActorSnapshot(update.navigationSnapshot)
          await continueAfterExpresswayExit(using: session)
          break
        }
        await synchronizeLiveTunnelState(
          from: update.matcherEstimate,
          session: session
        )
        guard isCurrent() else { return }
        if update.navigationSnapshot.journeyPhase == .strictRoute,
          update.admittedConfidence == .high
        {
          refreshTunnelEstimateAnchor(from: envelope)
        } else if update.navigationSnapshot.journeyPhase == .strictRoute {
          updateTunnelEstimate(
            atMilliseconds: observation.receivedAtMilliseconds
          )
          scheduleTunnelEstimateRefreshIfNeeded(
            atMilliseconds: observation.receivedAtMilliseconds
          )
        } else {
          clearTunnelEstimate()
        }
      case .exitTransition:
        guard var adapter = liveSurfaceEgressAdapter else {
          throw WholeShutoProductError.noExpresswayRoute
        }
        let evidence = try adapter.adapt(envelope)
        liveSurfaceEgressAdapter = adapter
        let update = await session.observeSurfaceEgressHandoffEvidence(
          evidence
        )
        guard isCurrent() else { return }
        matcherConfidence = evidence.confidence
        applyLiveActorSnapshot(update.navigationSnapshot)
        if let rejection = update.rejectionReason {
          liveLocationState = .degraded
          liveLocationIssueCode = rejection.rawValue
        }
        if update.navigationSnapshot.journeyPhase == .surfaceEgress {
          if updateLiveSurfaceProgress(
            coordinate: coordinate,
            horizontalAccuracyMeters:
              observation.horizontalAccuracyMeters,
            route: egressRoute,
            completesJourney: true
          ) {
            applyLiveActorSnapshot(
              await session.completeAtExitHandoff()
            )
          }
        }
      case .surfaceEgress:
        if updateLiveSurfaceProgress(
          coordinate: coordinate,
          horizontalAccuracyMeters:
            observation.horizontalAccuracyMeters,
          route: egressRoute,
          completesJourney: true
        ) {
          // After an unplanned exit the session's part is over; the surface
          // arrival alone ends the drive.
          if leftRouteAtUnplannedExit {
            completeLiveJourney()
          } else {
            applyLiveActorSnapshot(
              await session.completeAtExitHandoff()
            )
          }
        }
      case .planning, .review, .completed:
        return
      }
      guard isCurrent() else { return }
      if phase != .completed {
        if liveLocationState == .available, positionLossAnnounced {
          positionLossAnnounced = false
          announceJourneyNotice(.positionRecovered)
        }
        flushJourneyNotice()
        await captureAndPersistLiveCheckpoint(from: session)
      }
    } catch {
      guard isCurrent() else { return }
      clearTunnelEstimate()
      liveLocationState = .degraded
      liveLocationIssueCode = "WHOLE_SHUTO_OBSERVATION_PIPELINE_FAILED"
      failureCode = "WHOLE_SHUTO_OBSERVATION_PIPELINE_FAILED"
    }
  }

  private func consumeForegroundLiveLocationState(
    _ state: ForegroundNavigationLocationState
  ) {
    guard isLiveDrive else {
      liveLocationState = .inactive
      liveLocationIssueCode = nil
      return
    }
    switch state {
    case .idle, .stopped:
      clearTunnelEstimate()
      if liveLocationState != .resumeRequired,
        liveLocationState != .resting
      {
        liveLocationState = .inactive
        liveLocationIssueCode = nil
      }
      liveLocationFreshnessTask?.cancel()
      liveLocationFreshnessTask = nil
    case .awaitingAuthorization:
      liveLocationState = .awaitingAuthorization
      liveLocationIssueCode = nil
      liveLocationStartedAtMilliseconds = nowMillisecondsProvider()
      scheduleLiveLocationFreshnessCheck()
    case .running:
      if lastLiveObservationAtMilliseconds == nil {
        liveLocationState = .acquiring
        liveLocationIssueCode = nil
      }
      liveLocationStartedAtMilliseconds =
        liveLocationStartedAtMilliseconds ?? nowMillisecondsProvider()
      scheduleLiveLocationFreshnessCheck()
    case .sceneInactive:
      clearTunnelEstimate()
      liveLocationState = .resumeRequired
      liveLocationIssueCode = "LIVE_RESUME_REQUIRED"
      liveLocationFreshnessTask?.cancel()
      liveLocationFreshnessTask = nil
    case .permissionDenied:
      clearTunnelEstimate()
      liveLocationState = .permissionDenied
      liveLocationIssueCode = "CORE_LOCATION_PERMISSION_DENIED"
      isPlaying = false
      matcherConfidence = .low
      speechCoordinator?.stop()
      liveLocationFreshnessTask?.cancel()
      liveLocationFreshnessTask = nil
      persistCheckpoint()
    case .releaseBlocked(let reason):
      clearTunnelEstimate()
      liveLocationState = .failed
      liveLocationIssueCode = reason.rawValue
      failureCode = Self.liveNavigationRuntimeInvalidCode
      isPlaying = false
    case .runtimeUnavailable:
      clearTunnelEstimate()
      if !isPlaying {
        liveLocationState = .resumeRequired
        liveLocationIssueCode = "LIVE_RESUME_REQUIRED"
      } else {
        liveLocationState = .failed
        liveLocationIssueCode = "LIVE_RUNTIME_UNAVAILABLE"
        failureCode = Self.liveNavigationRuntimeInvalidCode
        isPlaying = false
      }
    case .failed(let code):
      clearTunnelEstimate()
      liveLocationState = .failed
      liveLocationIssueCode = code
      isPlaying = false
      matcherConfidence = .low
      speechCoordinator?.stop()
      liveLocationFreshnessTask?.cancel()
      liveLocationFreshnessTask = nil
      persistCheckpoint()
    }
  }

  @discardableResult
  func resumeLiveJourney() async -> Bool {
    if liveDriveSession == nil, pendingLiveNavigationCheckpoint != nil {
      await liveAdmissionTask?.value
      await liveRuntimeAssetsTask?.value
      return await restoreLiveJourneyFromCheckpoint()
    }
    guard isLiveDrive,
      phase != .planning,
      phase != .review,
      phase != .completed,
      liveDriveSession != nil
    else {
      return false
    }
    isPlaying = true
    restoredFromCheckpoint = false
    liveLocationState = .acquiring
    liveLocationIssueCode = nil
    liveLocationStartedAtMilliseconds = nowMillisecondsProvider()
    lastLiveObservationAtMilliseconds = nil
    lastUsableLiveObservationAtMilliseconds = nil
    lastAdmittedLiveFixAtMilliseconds = nil
    isHoldingLivePosition = false
    liveVehicleCourseDegrees = nil
    liveVehicleSpeedMetersPerSecond = nil
    matcherConfidence = .low
    clearTunnelEstimate()
    scheduleLiveLocationFreshnessCheck()
    speechCoordinator?.resume()
    foregroundLiveLocationController?.refreshRuntimeAvailability()
    foregroundLiveLocationController?.start()
    // Location starts only from an active scene. A Siri resume that runs
    // before the app is in front leaves the drive waiting for Resume, and
    // says so instead of reporting a drive nothing is feeding.
    switch foregroundLiveLocationController?.state {
    case .running, .awaitingAuthorization:
      break
    default:
      isPlaying = false
      liveLocationFreshnessTask?.cancel()
      liveLocationFreshnessTask = nil
      if liveLocationState == .acquiring {
        liveLocationState = .resumeRequired
        liveLocationIssueCode = "LIVE_RESUME_REQUIRED"
      }
      return false
    }
    announceJourneyNotice(.resumed)
    persistCheckpoint()
    return true
  }

  private func restoreLiveJourneyFromCheckpoint() async -> Bool {
    guard
      let route = selectedRoute,
      let checkpoint = pendingLiveNavigationCheckpoint,
      matchingLiveAdmissions.count == 1,
      let admission = matchingLiveAdmissions.first,
      let assets = matchingLiveRuntimeAssets,
      junctionPromptCacheRoutePlan == route.routePlan
    else {
      failureCode = liveNavigationBlockerCode
      return false
    }
    do {
      let runtime = try admission.core.makeRuntime(checkpoint: checkpoint)
      let session = try ShutoLiveDriveSession(runtime: runtime)
      let entryAdapter = try CoreLocationEntryTransitionAdapter(
        context: session.entryTransitionAdmissionContext
      )
      let egressAdapter = try session.surfaceEgressAdmissionContext.map {
        try CoreLocationSurfaceEgressAdapter(context: $0)
      }
      let observationAdapter = try CoreLocationObservationAdapter(
        sessionID: admission.core.release.releaseID,
        simulatedLocationPolicy: .reject,
        carPlayConnectionContext: .disconnected,
        sourceEvidenceProvider: liveLocationSourceEvidenceProvider
      )
      runtimeAssets = assets
      liveDriveSession = session
      liveEntryTransitionAdapter = entryAdapter
      liveSurfaceEgressAdapter = egressAdapter
      liveObservationAdapter = observationAdapter
      activeLiveAdmission = admission
      resetRouteJoinOffer()
      try configureSpeech(for: route.routePlan.id)
      let controller = try ForegroundNavigationLocationController(
        authority: .releasedProduct(
          admission.core.foregroundLiveInputAuthority
        ),
        consumer: self,
        source: liveLocationSource
      )
      observeLiveLocationController(controller)
      foregroundLiveLocationController = controller
      pendingLiveNavigationCheckpoint = nil
      liveNavigationCheckpoint = checkpoint
      isLiveDrive = true
      isPlaying = true
      restoredFromCheckpoint = true
      liveLocationState = .acquiring
      liveLocationIssueCode = nil
      liveLocationStartedAtMilliseconds = nowMillisecondsProvider()
      lastLiveObservationAtMilliseconds = nil
      lastUsableLiveObservationAtMilliseconds = nil
      lastAdmittedLiveFixAtMilliseconds = nil
      isHoldingLivePosition = false
      liveVehicleCourseDegrees = nil
      liveVehicleSpeedMetersPerSecond = nil
      matcherConfidence = .low
      clearTunnelEstimate()
      speechCoordinator?.resume()
      let snapshot = await session.start()
      applyLiveActorSnapshot(snapshot)
      announceJourneyNotice(.resumed)
      scheduleLiveLocationFreshnessCheck()
      await captureAndPersistLiveCheckpoint(from: session, force: true)
      controller.start()
      failureCode = nil
      return true
    } catch {
      failureCode = Self.checkpointRuntimeInvalidCode
      liveLocationState = .resumeRequired
      liveLocationIssueCode = Self.checkpointRuntimeInvalidCode
      return false
    }
  }

  private func applyLiveActorSnapshot(
    _ snapshot: NavigationSnapshot
  ) {
    runtimeJourneyPhase = snapshot.journeyPhase
    runtimeRecoveryStatus = snapshot.recovery.status
    if snapshot.journeyPhase != .entryTransition {
      entryStretchGuidanceFrame = nil
    }
    if snapshot.journeyPhase != .routeRecovery {
      runtimeIsConfirmingPlannedExit = false
    }
    runtimeRecoveryTargetOccurrenceID =
      snapshot.recovery.chosenRejoinOccurrenceID
    if snapshot.recovery.status != .active {
      runtimeRecoveryDirectedEdgeID = nil
    }
    switch snapshot.journeyPhase {
    case .planning, .approachToEntry:
      break
    case .entryTransition:
      if phase == .surfaceAccess {
        cancelSurfaceReroute()
        speechCoordinator?.stopProviderSurface()
        phase = .entryTransition
        progressFraction = 0
        announceEntrance()
      }
    case .strictRoute:
      if phase == .surfaceAccess || phase == .entryTransition {
        cancelSurfaceReroute()
        speechCoordinator?.stopProviderSurface()
        resetRouteJoinOffer()
        recordExpresswayEntry(from: snapshot)
        phase = .expressway
        progressFraction = 0
        announceJourneyNotice(.enteredExpressway)
      }
    case .routeRecovery:
      resetRouteJoinOffer()
      phase = .expressway
    case .exitTransition:
      guard snapshot.egress.status == .active else { return }
      speechCoordinator?.invalidateGuidance()
      clearTunnelEstimate()
      phase = .exitTransition
      progressFraction = 0
      presentationProjection = nil
      announceJourneyNotice(.exiting)
    case .surfaceEgress:
      speechCoordinator?.invalidateGuidance()
      clearTunnelEstimate()
      phase = .surfaceEgress
      progressFraction = 0
      presentationProjection = nil
      scheduleLiveSurfaceSpeech(forceCurrentStep: true)
    case .completed:
      completeLiveJourney()
    }
  }

  @discardableResult
  private func updateLiveSurfaceProgress(
    coordinate: ShutoCoordinate,
    horizontalAccuracyMeters: Double,
    route: WholeShutoSurfaceRoute?,
    completesJourney: Bool,
    reroutesOffRoute: Bool = true
  ) -> Bool {
    guard let route,
      let measurement = Self.surfaceRouteMeasurement(
        coordinate,
        along: route.coordinates
      )
    else {
      guard noteSurfaceOffRouteObservation() else { return false }
      speechCoordinator?.invalidateGuidance(keepingNotices: true)
      liveLocationState = .degraded
      if !isReroutingSurfaceRoute {
        liveLocationIssueCode = "SURFACE_ROUTE_GEOMETRY_UNAVAILABLE"
      }
      if reroutesOffRoute {
        beginSurfaceRerouteIfDue(
          from: coordinate,
          observedAtMilliseconds:
            lastLiveObservationAtMilliseconds ?? nowMillisecondsProvider()
        )
      }
      return false
    }
    let maximumLateralDistance = min(
      100,
      max(30, horizontalAccuracyMeters * 3)
    )
    guard
      measurement.lateralDistanceMeters
        <= maximumLateralDistance
    else {
      guard noteSurfaceOffRouteObservation() else { return false }
      speechCoordinator?.invalidateGuidance(keepingNotices: true)
      liveLocationState = .degraded
      if !isReroutingSurfaceRoute {
        liveLocationIssueCode = "SURFACE_ROUTE_OFF_ROUTE"
      }
      if reroutesOffRoute {
        beginSurfaceRerouteIfDue(
          from: coordinate,
          observedAtMilliseconds:
            lastLiveObservationAtMilliseconds ?? nowMillisecondsProvider()
        )
      }
      return false
    }
    consecutiveSurfaceOffRouteObservations = 0
    progressFraction = max(
      progressFraction,
      measurement.fractionAlongRoute
    )
    scheduleLiveSurfaceSpeech(forceCurrentStep: false)
    guard completesJourney,
      progressFraction >= 0.995,
      let destination = route.coordinates.last,
      Self.distance(coordinate, destination)
        <= max(30, horizontalAccuracyMeters * 2)
    else {
      return false
    }
    return true
  }

  /// The approach road and the ramp share their first metres, so the drive
  /// hands over to the entrance before the ramp has proved anything. A car
  /// that then goes on past it, off every corridor road and away from the
  /// end of its ordinary-road leg, did not enter: the leg resumes, and its
  /// off-route reroute brings the entrance back ahead.
  private func resumeSurfaceAccessIfEntrancePassed(
    evidence: EntryTransitionEvidence,
    coordinate: ShutoCoordinate,
    horizontalAccuracyMeters: Double,
    journeyPhase: JourneyPhase
  ) {
    guard accessRoute != nil,
      journeyPhase == .entryTransition,
      evidence.confidence == .lost,
      !isNearSurfaceRouteEnd(
        coordinate: coordinate,
        horizontalAccuracyMeters: horizontalAccuracyMeters,
        route: accessRoute,
        thresholdMeters: Self.surfaceEntryTransitionRadiusMeters
      )
    else {
      consecutivePastEntranceObservations = 0
      return
    }
    consecutivePastEntranceObservations += 1
    guard consecutivePastEntranceObservations
      >= Self.surfaceRerouteRequiredOffRouteObservations
    else { return }
    consecutivePastEntranceObservations = 0
    phase = .surfaceAccess
    progressFraction = 0
    matcherConfidence = nil
    liveLocationIssueCode = nil
    scheduleLiveSurfaceSpeech(forceCurrentStep: true)
  }

  private func isNearSurfaceRouteEnd(
    coordinate: ShutoCoordinate,
    horizontalAccuracyMeters: Double,
    route: WholeShutoSurfaceRoute?,
    thresholdMeters: Double
  ) -> Bool {
    guard let destination = route?.coordinates.last else { return false }
    return Self.distance(coordinate, destination)
      <= max(thresholdMeters, horizontalAccuracyMeters * 2)
  }

  private func completeLiveJourney(notice: WholeShutoJourneyNotice = .arrived) {
    finishDriveRecord(arrived: notice == .arrived)
    cancelSurfaceReroute()
    stopForegroundLiveLocationController()
    phase = .completed
    progressFraction = 1
    isPlaying = false
    liveLocationState = .inactive
    liveLocationIssueCode = nil
    liveLocationFreshnessTask?.cancel()
    liveLocationFreshnessTask = nil
    speechCoordinator?.stop()
    removeCheckpoint()
    speechCoordinator?.resume()
    announceJourneyNotice(notice)
  }

  private func finishDriveRecord(arrived: Bool) {
    guard isLiveDrive, showsDriveRecord, driveRecord.endedAtMilliseconds == nil
    else { return }
    driveRecord.finish(atMilliseconds: nowMillisecondsProvider())
    driveRecordArrived = arrived
    saveDriveHistoryEntry()
  }

  private func saveDriveHistoryEntry() {
    guard let route = selectedRoute else { return }
    guard let entry = DriveHistoryEntry(
      record: driveRecord, routePlan: route.routePlan,
      routeName: route.routeIDsInOrder.joined(separator: " · ") + " · "
        + driveEntryNameJA + " → " + route.destinationNameJA,
      templateParameters: savedRouteTemplateParameters,
      arrived: driveRecordArrived,
      endedNearDestination: endedNearDestination
    ) else { return }
    do {
      try driveHistoryStore.save(entry)
      driveHistoryIssue = nil
    } catch {
      driveHistoryIssue = "DRIVE_HISTORY_SAVE_FAILED"
    }
  }

  /// The session saw the car leave the expressway where the plan does not.
  /// A journey that goes on beyond the expressway, back to its origin or to
  /// a searched place, continues on ordinary roads from where the car is. An
  /// exit-only or PA-ended journey has nowhere beyond the exit to go, so the
  /// drive ends there: near the destination when it is close to it.
  private func handOverAfterUnplannedExit(
    at coordinate: ShutoCoordinate,
    attemptedAtMilliseconds: Int
  ) {
    leftRouteAtUnplannedExit = true
    clearTunnelEstimate()
    presentationProjection = nil
    runtimeOccurrenceID = nil
    isHoldingLivePosition = false
    guard requiresSurfaceEgress, destination != nil else {
      let isNearDestination = selectedRoute.map {
        Self.distance(coordinate, $0.destinationCoordinate)
          <= Self.unplannedExitNearDestinationMeters
      } ?? false
      endedNearDestination = isNearDestination
      endedOffRoute = !isNearDestination
      runtimeCoordinate = coordinate
      completeLiveJourney(notice: isNearDestination ? .nearDestination : .leftRouteEnded)
      return
    }
    phase = .surfaceEgress
    progressFraction = 0
    egressRoute = nil
    beginSurfaceReroute(
      from: coordinate,
      phase: .surfaceEgress,
      attemptedAtMilliseconds: attemptedAtMilliseconds,
      notice: .leftRouteRerouting
    )
  }

  static let unplannedExitNearDestinationMeters = 1_000.0

  private func continueAfterExpresswayExit(
    using session: ShutoLiveDriveSession
  ) async {
    guard liveSurfaceEgressAdapter == nil else { return }
    if egressRoute != nil {
      speechCoordinator?.invalidateGuidance()
      phase = .surfaceEgress
      progressFraction = 0
      presentationProjection = nil
      scheduleLiveSurfaceSpeech(forceCurrentStep: true)
    } else {
      applyLiveActorSnapshot(await session.completeAtExitHandoff())
    }
  }

  func resumePlayback() {
    // A live drive follows the vehicle, not a transport; there is nothing
    // to pause or step.
    guard !isLiveDrive else { return }
    guard phase != .planning, phase != .review, phase != .completed else {
      return
    }
    guard !isPlaying else { return }
    isPlaying = true
    invalidatePlaybackTask()
    let generation = playbackGeneration
    playbackTask = Task { [weak self] in
      guard let self else { return }
      guard await restoreObservationReplayIfNeeded() else { return }
      guard
        !Task.isCancelled,
        isPlaying,
        playbackGeneration == generation
      else {
        return
      }
      speechCoordinator?.resume()
      restoredFromCheckpoint = false
      persistCheckpoint()
      startPlaybackLoop()
    }
  }

  /// Stops playback only after any actor-owned observation already in flight
  /// has published its matching UI state. Returning from this method is the
  /// pause boundary used by transport controls, lifecycle checkpointing, and
  /// the end-preview confirmation.
  @discardableResult
  func pausePlayback() async -> Bool {
    guard !isLiveDrive else { return false }
    let wasPlaying = isPlaying
    let task = playbackTask
    guard wasPlaying || task != nil else { return false }

    isPlaying = false
    playbackTask = nil
    task?.cancel()
    if let task {
      await task.value
    }
    if let driveSimulator {
      _ = await driveSimulator.pause()
    }
    playbackGeneration &+= 1
    speechCoordinator?.stop()
    persistCheckpoint()
    return wasPlaying
  }

  func advanceSimulation() {
    guard !isLiveDrive else { return }
    guard phase != .planning, phase != .review, phase != .completed else {
      return
    }
    if phase == .entryTransition || phase == .expressway {
      speechCoordinator?.resume()
      Task {
        await stepObservationReplay()
      }
      return
    }
    tick()
  }

  /// Awaits the surface routing and live-runtime preparation already in
  /// flight, including preparation one of them starts on completion, so a
  /// test asserts their outcome rather than a wall-clock budget.
  func awaitLiveNavigationPreparationForTesting() async {
    var awaited: [Task<Void, Never>] = []
    while let task = [surfaceRouteTask, liveAdmissionTask, liveRuntimeAssetsTask]
      .compactMap({ $0 })
      .first(where: { !awaited.contains($0) })
    {
      await task.value
      awaited.append(task)
    }
  }

  func advanceSimulationForTesting() async {
    guard phase != .planning, phase != .review, phase != .completed else {
      return
    }
    if phase == .entryTransition || phase == .expressway {
      speechCoordinator?.resume()
      guard await restoreObservationReplayIfNeeded() else { return }
      restoredFromCheckpoint = false
      await stepObservationReplay()
    } else {
      tick()
    }
  }

  /// Stages a navigation preview at its exact reviewed junction using the
  /// simulator's real matcher/session reducer. Intermediate trace events stay
  /// inside the simulator actor so map and guidance views publish only the
  /// target actor-owned emission.
  @discardableResult
  func advanceSimulationToJunctionPreview() async -> Bool {
    guard
      !isLiveDrive,
      let junctionPreviewMovementID,
      let prompt = junctionPrompts.first(where: {
        $0.movementID == junctionPreviewMovementID
      }),
      let driveSimulator
    else {
      failureCode = "WHOLE_SHUTO_JUNCTION_PREVIEW_UNAVAILABLE"
      return false
    }

    _ = await pausePlayback()
    phase = .entryTransition
    progressFraction = 0
    presentationProjection = nil
    speechCoordinator?.resume()

    do {
      guard
        let result =
          try await driveSimulator
          .advancePausedUntilGuidanceEmission(
            movementOccurrenceID: prompt.outgoingOccurrenceID
          )
      else {
        failureCode = "WHOLE_SHUTO_JUNCTION_PREVIEW_UNAVAILABLE"
        return false
      }
      applyObservationReplayResult(result)
      guard
        phase == .expressway,
        activeJunctionPrompt?.movementID == junctionPreviewMovementID
      else {
        failureCode = "WHOLE_SHUTO_JUNCTION_PREVIEW_UNAVAILABLE"
        return false
      }
      failureCode = nil
      persistCheckpoint()
      return true
    } catch {
      failureCode = "WHOLE_SHUTO_OBSERVATION_PIPELINE_FAILED"
      return false
    }
  }

  func reset() {
    finishDriveRecord(arrived: false)
    stopForegroundLiveLocationController()
    driveRecord = WholeShutoDriveRecord()
    remainingWholeLapsAhead = 0
    resetRouteJoinOffer()
    resetDriveEntry()
    invalidatePlaybackTask()
    cancelSurfaceRouteResolution()
    cancelSurfaceReroute()
    liveAdmissionTask?.cancel()
    liveAdmissionTask = nil
    liveAdmissionRequestID = nil
    resolvedLiveAdmission = nil
    liveAdmissionResolutionIssueCode = nil
    liveRuntimeAssetsTask?.cancel()
    liveRuntimeAssetsTask = nil
    liveRuntimeAssetsRequestID = nil
    preparedLiveRuntimeAssets = nil
    preparedLiveRuntime = nil
    junctionPromptCacheRoutePlan = nil
    junctionPromptCache = []
    isPreparingLiveNavigation = false
    speechCoordinator?.stop()
    speechCoordinator = nil
    phase = .planning
    journeyEnding = .destination
    origin = nil
    destination = nil
    selectedDestinationTitle = nil
    recommendations = []
    selectedRecommendationIndex = 0
    clearRouteChoiceEvaluation()
    clearCustomRouteSelection()
    clearCircuitRouteSelection()
    clearCircuitPlanningDraft()
    accessRoute = nil
    egressRoute = nil
    progressFraction = 0
    isPlaying = false
    failureCode = nil
    mapMode = .network
    matcherConfidence = nil
    runtimeOccurrenceID = nil
    runtimeJourneyPhase = nil
    runtimeRecoveryStatus = nil
    runtimeRecoveryTargetOccurrenceID = nil
    runtimeRecoveryDirectedEdgeID = nil
    runtimeCoordinate = nil
    runtimeFractionAlongOccurrence = nil
    liveMatcherWasInTunnel = false
    clearTunnelEstimate()
    presentationProjection = nil
    speechStatus = .idle
    consumedGuidancePromptIDs = []
    surfaceSpeechGeneration = 0
    pendingNotice = nil
    positionLossAnnounced = false
    positionLossAnnouncedAtMilliseconds = nil
    runtimeAssets = nil
    driveSimulator = nil
    liveDriveSession = nil
    liveEntryTransitionAdapter = nil
    liveSurfaceEgressAdapter = nil
    liveNavigationCheckpoint = nil
    pendingLiveNavigationCheckpoint = nil
    activeLiveAdmission = nil
    liveObservationAdapter = nil
    isLiveDrive = false
    liveLocationState = .inactive
    liveLocationIssueCode = nil
    liveLocationStartedAtMilliseconds = nil
    lastLiveObservationAtMilliseconds = nil
    lastUsableLiveObservationAtMilliseconds = nil
    lastAdmittedLiveFixAtMilliseconds = nil
    isHoldingLivePosition = false
    liveVehicleCourseDegrees = nil
    liveVehicleSpeedMetersPerSecond = nil
    lastLiveCheckpointPersistedAtMilliseconds = nil
    lastSurfaceRerouteAttemptAtMilliseconds = nil
    liveLocationFreshnessTask?.cancel()
    liveLocationFreshnessTask = nil
    isStaticJunctionPreview = false
    junctionPreviewMovementID = nil
    restoredFromCheckpoint = false
    removeCheckpoint()
  }

  func handleScenePhase(
    _ scenePhase: ProductNavigationRuntimeScenePhase
  ) async {
    let liveLocationController = foregroundLiveLocationController
    await liveLocationController?.handleScenePhase(scenePhase)
    switch scenePhase {
    case .active:
      if !isLiveDrive || isPlaying {
        speechCoordinator?.resume()
      }
    case .inactive, .background:
      if isLiveDrive {
        if liveLocationController?
          .maintainsActiveNavigationAcrossSceneChanges == true
        {
          if let liveDriveSession {
            await captureAndPersistLiveCheckpoint(
              from: liveDriveSession,
              force: true
            )
          }
          return
        }
        cancelSurfaceReroute()
        invalidatePlaybackTask()
        isPlaying = false
        speechCoordinator?.stop()
        liveLocationState = .resumeRequired
        liveLocationIssueCode = "LIVE_RESUME_REQUIRED"
        liveLocationFreshnessTask?.cancel()
        liveLocationFreshnessTask = nil
        if let liveDriveSession {
          await captureAndPersistLiveCheckpoint(
            from: liveDriveSession,
            force: true
          )
        }
      } else {
        _ = await pausePlayback()
        persistCheckpoint()
      }
    }
  }

  private func stopForegroundLiveLocationController() {
    guard let controller = foregroundLiveLocationController else { return }
    foregroundLiveLocationController = nil
    liveLocationSubscriptions.removeAll()
    Task {
      await controller.stop()
    }
  }

  /// Counts one fix that did not land on the surface leg, and answers
  /// whether the car is off the route rather than momentarily mismeasured.
  ///
  /// A single fix cannot answer that. Beside a tower or under an elevated
  /// road one fix lands a hundred metres sideways and the next is back on
  /// the line. Acting on the first one wiped the instruction and the
  /// distance and left the header reading "waiting to join the route" while
  /// the car was driving exactly the leg it had been told to. The reroute
  /// already waited for `surfaceRerouteRequiredOffRouteObservations`
  /// consecutive fixes before believing it; the header now waits for the
  /// same evidence, so the driver keeps the current step until the route
  /// really is lost.
  private func noteSurfaceOffRouteObservation() -> Bool {
    guard
      isLiveDrive,
      isPlaying,
      phase == .surfaceAccess || phase == .surfaceEgress
    else {
      return false
    }
    consecutiveSurfaceOffRouteObservations += 1
    return consecutiveSurfaceOffRouteObservations
      >= Self.surfaceRerouteRequiredOffRouteObservations
  }

  private func beginSurfaceRerouteIfDue(
    from coordinate: ShutoCoordinate,
    observedAtMilliseconds: Int
  ) {
    guard
      surfaceRerouteTask == nil,
      lastSurfaceRerouteAttemptAtMilliseconds.map({
        observedAtMilliseconds - $0
          >= Self.surfaceRerouteCooldownMilliseconds
      }) ?? true
    else {
      return
    }
    beginSurfaceReroute(
      from: coordinate,
      phase: phase,
      attemptedAtMilliseconds: observedAtMilliseconds
    )
  }

  private func beginSurfaceReroute(
    from coordinate: ShutoCoordinate,
    phase requestedPhase: WholeShutoJourneyPhase,
    attemptedAtMilliseconds: Int,
    notice: WholeShutoJourneyNotice = .rerouting
  ) {
    guard
      let selectedRoute,
      requestedPhase == .surfaceAccess || requestedPhase == .surfaceEgress
    else {
      return
    }
    let destination: ShutoCoordinate
    let fallbackDestination: ShutoCoordinate?
    switch requestedPhase {
    case .surfaceAccess:
      destination =
        selectedRoute.coordinates.first
        ?? selectedRoute.entryFacility.coordinate
      fallbackDestination = selectedRoute.entryFacility.coordinate
    case .surfaceEgress:
      guard let journeyDestination = self.destination?.coordinate else {
        return
      }
      destination = journeyDestination
      fallbackDestination = nil
    default:
      return
    }

    let requestID = UUID()
    let routePlanID = selectedRoute.routePlan.id
    let resolver = surfaceRouteResolver
    consecutiveSurfaceOffRouteObservations = 0
    lastSurfaceRerouteAttemptAtMilliseconds = attemptedAtMilliseconds
    surfaceRerouteRequestID = requestID
    isReroutingSurfaceRoute = true
    liveLocationState = .degraded
    liveLocationIssueCode = Self.surfaceRouteReroutingCode
    speechCoordinator?.invalidateGuidance()
    announceJourneyNotice(notice)
    surfaceRerouteTask = Task { [weak self] in
      var resolved = await resolver.route(from: coordinate, to: destination)
      if resolved == nil,
        !Task.isCancelled,
        let fallbackDestination,
        fallbackDestination != destination
      {
        resolved = await resolver.route(from: coordinate, to: fallbackDestination)
      }
      guard
        !Task.isCancelled,
        let self,
        self.surfaceRerouteRequestID == requestID
      else {
        return
      }
      self.surfaceRerouteTask = nil
      self.surfaceRerouteRequestID = nil
      self.isReroutingSurfaceRoute = false
      guard
        self.isLiveDrive,
        self.isPlaying,
        self.phase == requestedPhase,
        self.selectedRoute?.routePlan.id == routePlanID
      else {
        return
      }
      guard let resolved, Self.isUsableSurfaceRoute(resolved) else {
        self.liveLocationState = .degraded
        self.liveLocationIssueCode = Self.surfaceRouteRerouteUnavailableCode
        self.persistCheckpoint()
        return
      }
      switch requestedPhase {
      case .surfaceAccess:
        self.accessRoute = resolved
      case .surfaceEgress:
        self.egressRoute = resolved
      default:
        return
      }
      self.progressFraction = 0
      self.speechCoordinator?.stopProviderSurface()
      self.surfaceSpeechGeneration += 1
      self.liveLocationState = .available
      self.liveLocationIssueCode = nil
      self.scheduleLiveSurfaceSpeech(forceCurrentStep: true)
      self.persistCheckpoint()
    }
  }

  private static func isUsableSurfaceRoute(
    _ route: WholeShutoSurfaceRoute
  ) -> Bool {
    route.coordinates.count >= 2
      && route.distanceMeters.isFinite
      && route.distanceMeters >= 0
      && route.expectedTravelTimeSeconds.isFinite
      && route.expectedTravelTimeSeconds >= 0
      && route.coordinates.allSatisfy {
        $0.latitude.isFinite && $0.longitude.isFinite
      }
  }

  private func cancelSurfaceReroute() {
    surfaceRerouteTask?.cancel()
    surfaceRerouteTask = nil
    surfaceRerouteRequestID = nil
    consecutiveSurfaceOffRouteObservations = 0
    isReroutingSurfaceRoute = false
  }

  private func startPlaybackLoop() {
    invalidatePlaybackTask()
    if phase == .entryTransition || phase == .expressway {
      startObservationReplayLoop()
      return
    }
    let generation = playbackGeneration
    playbackTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(420))
        guard
          !Task.isCancelled,
          let self,
          isPlaying,
          playbackGeneration == generation
        else {
          return
        }
        tick()
      }
    }
  }

  private func invalidatePlaybackTask() {
    playbackGeneration &+= 1
    playbackTask?.cancel()
    playbackTask = nil
  }

  /// Each phase has a natural primary presentation: the self-drawn network
  /// diagram and track map carry planning, review, and the expressway body;
  /// the geographic map carries every leg that runs on ordinary streets.
  /// Explicit assignments after a phase change (previews, checkpoint restore)
  /// still override this baseline.
  private func syncMapModeToPhase() {
    switch phase {
    case .planning, .review, .expressway:
      mapMode = .network
    case .surfaceAccess, .entryTransition, .exitTransition,
      .surfaceEgress, .completed:
      mapMode = .geographic
    }
  }

  private func tick() {
    let increment: Double
    switch phase {
    case .surfaceAccess, .surfaceEgress:
      increment = 0.04
    case .exitTransition:
      increment = 0.25
    case .entryTransition, .expressway:
      return
    case .planning, .review, .completed:
      return
    }
    progressFraction = min(1, progressFraction + increment)
    // Like observation replay, a surface step is saved on pause or background.
    guard progressFraction >= 1 else { return }
    progressFraction = 0
    switch phase {
    case .surfaceAccess:
      phase = .entryTransition
    case .entryTransition:
      phase = .expressway
    case .expressway:
      phase = .exitTransition
    case .exitTransition:
      phase = egressRoute == nil ? .completed : .surfaceEgress
    case .surfaceEgress:
      phase = .completed
      isPlaying = false
      invalidatePlaybackTask()
      speechCoordinator?.stop()
    case .planning, .review, .completed:
      break
    }
    if phase == .completed {
      removeCheckpoint()
    } else {
      persistCheckpoint()
      if phase == .entryTransition || phase == .expressway,
        isPlaying
      {
        startObservationReplayLoop()
      }
    }
  }

  private func startObservationReplayLoop() {
    guard
      phase == .entryTransition || phase == .expressway,
      let driveSimulator
    else {
      isPlaying = false
      failureCode = "WHOLE_SHUTO_RUNTIME_MISSING"
      return
    }
    invalidatePlaybackTask()
    let generation = playbackGeneration
    playbackTask = Task { [weak self] in
      _ = await driveSimulator.play()
      while !Task.isCancelled {
        let delay =
          await driveSimulator.delayBeforeNextEventMilliseconds() ?? 0
        if delay > 0 {
          try? await Task.sleep(for: .milliseconds(delay))
        }
        guard !Task.isCancelled else { return }
        do {
          guard
            let result = try await driveSimulator.advanceIfPlaying()
          else {
            break
          }
          guard
            let self,
            playbackGeneration == generation
          else {
            return
          }
          applyObservationReplayResult(result)
          if result.status.state == .completed {
            completeExpresswayObservationReplay()
            return
          }
        } catch {
          guard
            let self,
            playbackGeneration == generation
          else {
            return
          }
          isPlaying = false
          failureCode = "WHOLE_SHUTO_OBSERVATION_PIPELINE_FAILED"
          return
        }
      }
    }
  }

  private func stepObservationReplay() async {
    guard
      phase == .entryTransition || phase == .expressway,
      let driveSimulator
    else {
      failureCode = "WHOLE_SHUTO_RUNTIME_MISSING"
      return
    }
    do {
      guard let result = try await driveSimulator.step() else {
        completeExpresswayObservationReplay()
        return
      }
      applyObservationReplayResult(result)
      if result.status.state == .completed {
        completeExpresswayObservationReplay()
      }
    } catch {
      isPlaying = false
      failureCode = "WHOLE_SHUTO_OBSERVATION_PIPELINE_FAILED"
    }
  }

  private func applyObservationReplayResult(
    _ result: NavigationDriveSimulationStepResult
  ) {
    guard let update = result.navigationUpdate else { return }
    applyNavigationUpdate(update)
  }

  /// Applies actor-owned progress and guidance for labeled replay. A future
  /// release-backed live composition may reuse this projection only after its
  /// provenance-bearing observations pass the release admission boundary.
  /// No step writes the checkpoint: replay saves when it pauses or the app
  /// leaves the foreground, and a live drive on its own five-second cadence.
  private func applyNavigationUpdate(_ update: NavigationSessionUpdate) {
    let wasRecovering = runtimeRecoveryStatus == .active
    if activeGuidanceCueIsObsolete(after: update) {
      speechCoordinator?.invalidateGuidance(keepingNotices: true)
    }
    // Only the session's admitted confidence moves the position, distance
    // and heading; a raw matcher result below HIGH is routine at 1 Hz.
    matcherConfidence = MatcherConfidence(
      rawValue: update.admittedConfidence.rawValue
    )
    runtimeJourneyPhase = update.navigationSnapshot.journeyPhase
    runtimeRecoveryStatus = update.navigationSnapshot.recovery.status
    runtimeIsConfirmingPlannedExit = update.isConfirmingPlannedExit
    if isLiveDrive, wasRecovering, update.navigationSnapshot.journeyPhase == .strictRoute {
      announceJourneyNotice(.rejoined)
    } else if isLiveDrive, !wasRecovering, runtimeRecoveryStatus == .active {
      announceJourneyNotice(.rerouting)
    }
    runtimeRecoveryTargetOccurrenceID =
      update.navigationSnapshot.recovery.chosenRejoinOccurrenceID
    if update.navigationSnapshot.journeyPhase == .completed, endsAtParkingArea {
      endedNearDestination =
        update.navigationSnapshot.lastPhaseTransitionTrigger
        == "DESTINATION_PARKING_AREA_NOT_ENTERED"
      if let progress = runtimeAssets?.project(update.matcherEstimate) {
        recordLapProgress(occurrenceID: progress.occurrenceID, atMilliseconds: update.matcherEstimate.estimatedAtMilliseconds)
      }
      if !endedNearDestination {
        runtimeCoordinate = selectedRoute?.destinationCoordinate
      }
      runtimeOccurrenceID = nil
      presentationProjection = nil
      clearTunnelEstimate()
      invalidatePlaybackTask()
      completeLiveJourney(
        notice: endedNearDestination ? .nearDestination : .arrived
      )
      return
    }
    publishPresentationAndScheduleSpeech(from: update)
    if update.navigationSnapshot.journeyPhase == .routeRecovery {
      clearTunnelEstimate()
      if isLiveDrive,
        update.navigationSnapshot.recovery.status == .active
      {
        updateReleasedRecoveryPosition(from: update.matcherEstimate)
        return
      }
      runtimeRecoveryDirectedEdgeID = nil
      return
    }
    runtimeRecoveryDirectedEdgeID = nil
    if phase == .entryTransition {
      guard update.navigationSnapshot.journeyPhase == .strictRoute else {
        return
      }
      resetRouteJoinOffer()
      recordExpresswayEntry(from: update.navigationSnapshot)
      phase = .expressway
      progressFraction = 0
    }
    guard phase == .expressway else { return }
    guard update.admittedConfidence == .high,
      let progress = runtimeAssets?.project(
        update.matcherEstimate
      ),
      progress.routeProgressFraction >= progressFraction
    else {
      return
    }
    progressFraction = progress.routeProgressFraction
    runtimeOccurrenceID = progress.occurrenceID
    recordLapProgress(
      occurrenceID: progress.occurrenceID,
      atMilliseconds: update.matcherEstimate.estimatedAtMilliseconds
    )
    if let liveDriveSession {
      Task { await refreshRemainingLaps(from: liveDriveSession) }
    }
    runtimeFractionAlongOccurrence =
      progress.fractionAlongOccurrence
    runtimeCoordinate = progress.coordinate
  }

  /// A coarse fix under an elevated road leaves guidance progress unresolved,
  /// not wrong, and the engine emits each prompt once: cutting the cue off
  /// there loses it for good. Only a phase change, a skipped movement, or the
  /// car leaving the cue's approach withdraws it.
  private func activeGuidanceCueIsObsolete(
    after update: NavigationSessionUpdate
  ) -> Bool {
    guard let identity = speechCoordinator?.scheduler.activeCommand?.identity
    else { return false }
    let snapshot = update.navigationSnapshot
    guard snapshot.journeyPhase == runtimeJourneyPhase,
      let assets = runtimeAssets,
      let definition = assets.releasedGuidance.first(where: {
        $0.anchor.promptID == identity.promptID
      }),
      let anchor = assets.routePlan.occurrence(id: identity.anchorOccurrenceID),
      let movement = assets.routePlan.occurrence(
        id: definition.frameTemplate.movementOccurrenceID
      ),
      !snapshot.skippedOccurrenceIDs.contains(movement.id),
      let current = snapshot.currentOccurrenceIndex
    else { return true }
    // The same window GuidanceFramePlanner applies a definition in.
    return !(anchor.index <= current
      && (current < movement.index || current == anchor.index))
  }

  private func configureSpeech(for routePlanID: String) throws {
    speechCoordinator?.stop()
    pendingNotice = nil
    // The position-loss cooldown belongs to the drive, not the plan: a lap
    // swap reconfigures speech mid-drive and must not reopen it.
    let coordinator = try GuidanceSpeechCoordinator(
      expectedRoutePlanID: routePlanID,
      output: speechOutput
    )
    coordinator.statusDidChange = { [weak self, weak coordinator] status in
      guard let self else { return }
      if case .speaking(let identity) = status,
        coordinator?.scheduler.activeCommand?.identity == identity
      {
        self.consumedGuidancePromptIDs.insert(identity.promptID)
        if self.isLiveDrive { self.persistCheckpoint() }
      }
      self.speechStatus = status
    }
    speechCoordinator = coordinator
    coordinator.setMode(speechMode)
    speechStatus = .idle
  }

  func setSpeechMode(_ mode: GuidanceSpeechMode) {
    speechMode = mode
    driveRecordPreferenceStore.set(mode.rawValue, forKey: Self.speechModeDefaultsKey)
    speechCoordinator?.setMode(mode)
    if mode == .muted {
      // A notice held back while muted would be spoken as news on unmute.
      pendingNotice = nil
    } else {
      audibleSpeechMode = mode
    }
  }

  /// Returns to the voice the driver chose before muting, not a default.
  func unmuteSpeech() {
    guard speechMode == .muted else { return }
    setSpeechMode(audibleSpeechMode)
  }

  func setSpeechVolume(_ volume: GuidanceSpeechVolume) {
    speechVolume = volume
    driveRecordPreferenceStore.set(volume.rawValue, forKey: GuidanceSpeechVolume.preferenceKey)
  }

  var canRepeatGuidance: Bool {
    guard isPlaying, speechMode != .muted, let speechCoordinator else { return false }
    if isLiveDrive, liveLocationState != .available { return false }
    switch phase {
    case .surfaceAccess, .surfaceEgress:
      guard positionState == .surfacePreview,
        let progress = activeSurfaceStepProgress,
        let command = surfaceSpeechCommand(at: progress.index)
      else { return false }
      return speechCoordinator.startedIdentities.contains(command.identity)
    case .expressway:
      guard hasCurrentGuidancePosition,
        let projection = presentationProjection,
        projection.voice.distanceMeters > 0
      else { return false }
      return speechCoordinator.startedIdentities.contains(
        GuidanceSpeechIdentity(
          promptID: projection.voice.promptID,
          anchorID: projection.iPhone.guidanceAnchorID,
          anchorOccurrenceID: projection.iPhone.guidanceAnchorOccurrenceID
        )
      )
    default: return false
    }
  }

  @discardableResult
  func repeatGuidance() -> Bool {
    guard canRepeatGuidance, let speechCoordinator else { return false }
    let status: GuidanceSpeechCoordinatorStatus
    if phase == .expressway, let projection = presentationProjection {
      status = speechCoordinator.repeatCurrent(projection)
    } else if let progress = activeSurfaceStepProgress,
      let command = surfaceSpeechCommand(at: progress.index)
    {
      status = speechCoordinator.repeatCurrentSurface(command)
    } else { return false }
    switch status {
    case .idle, .scheduled, .speaking: return true
    default: return false
    }
  }

  var currentInstructionForRepeat: String? {
    guard canRepeatGuidance else { return nil }
    if phase == .expressway { return presentationProjection?.voice.synthesisText }
    guard let progress = activeSurfaceStepProgress else { return nil }
    return surfaceSpeechCommand(at: progress.index)?.synthesisText
  }

  var liveSessionIdentity: ObjectIdentifier? {
    liveDriveSession.map(ObjectIdentifier.init)
  }

  private func announceJourneyNotice(_ notice: WholeShutoJourneyNotice) {
    guard isLiveDrive, speechMode != .muted,
      let routePlanID = selectedRoute?.routePlan.id
    else { return }
    noticeSequence += 1
    let id = "journey.\(notice.rawValue).\(noticeSequence)"
    let locale = languageSelectionProvider().guidanceVoiceLocale
    pendingNotice = GuidanceSpeechCommand(
      identity: GuidanceSpeechIdentity(
        promptID: id, anchorID: "JOURNEY_STATUS", anchorOccurrenceID: id),
      routePlanID: routePlanID, languageCode: locale.speechLanguageCode,
      spokenText: notice.text(locale: locale)
    )
    flushJourneyNotice()
  }

  /// Where the route runs straight on from the ramp, the first decision can
  /// come before entry is confirmed, and its own cue is not spoken there.
  /// Coming to the entrance, the plan says it once: a statement of what lies
  /// ahead on the plan, not of where the car is.
  private func announceEntrance() {
    guard isLiveDrive, speechMode != .muted,
      let guidance = liveDriveSession?.entranceAnnouncementGuidance,
      let route = selectedRoute
    else { return }
    let locale = languageSelectionProvider().guidanceVoiceLocale
    guard let text = Self.entranceAnnouncementText(guidance, entranceNameJA: route.entryFacility.nameJA, locale: locale)
    else { return }
    noticeSequence += 1
    let id = "journey.entrance.\(noticeSequence)"
    pendingNotice = GuidanceSpeechCommand(
      identity: GuidanceSpeechIdentity(promptID: id, anchorID: "JOURNEY_STATUS", anchorOccurrenceID: id),
      routePlanID: route.routePlan.id, languageCode: locale.speechLanguageCode,
      spokenText: text
    )
    entranceAnnouncement = (guidance.frameTemplate.movementOccurrenceID, nowMillisecondsProvider())
    flushJourneyNotice()
  }

  /// 「豊洲入口です。その先、東雲JCTで横浜方面です」, chained the way a cue names
  /// the sign after it; Chinese and English go on with the decision's own
  /// released instruction.
  static func entranceAnnouncementText(
    _ guidance: ReleasedGuidanceDefinition,
    entranceNameJA: String,
    locale: KaidoReleaseLocale
  ) -> String? {
    let template = guidance.frameTemplate
    guard let spoken = template.presentationSource.localizedContent[locale]?.spokenText else { return nil }
    switch locale {
    case .japanese:
      return "\(entranceNameJA)入口です。その先、\(template.decisionPointNameJapanese)で"
        + "\(template.presentationSource.japaneseSignText)方面です"
    case .simplifiedChinese:
      return "\(entranceNameJA) 入口。随后\(spoken)"
    case .english:
      guard spoken.hasPrefix("At ") else { return nil }
      return "Expressway entrance. Then at " + spoken.dropFirst("At ".count)
    }
  }

  private func flushJourneyNotice() {
    guard let command = pendingNotice, let speechCoordinator else { return }
    if speechCoordinator.startedIdentities.contains(command.identity) {
      pendingNotice = nil
      return
    }
    _ = speechCoordinator.submitNotice(command)
  }

  private func scheduleLiveSurfaceSpeech(forceCurrentStep: Bool) {
    guard isLiveDrive, isPlaying,
      let progress = activeSurfaceStepProgress,
      let current = surfaceSpeechCommand(at: progress.index),
      let speechCoordinator
    else { return }
    let command: GuidanceSpeechCommand
    if !forceCurrentStep,
      speechCoordinator.startedIdentities.contains(current.identity),
      progress.remainingMeters <= Self.surfaceSpeechPreannounceDistanceMeters,
      let next = surfaceSpeechCommand(at: progress.index + 1)
    {
      command = next
    } else {
      command = current
    }
    _ = speechCoordinator.submitProviderSurface(command)
  }

  private func surfaceSpeechCommand(at index: Int) -> GuidanceSpeechCommand? {
    guard let route = activeSurfaceRoute,
      let progress = activeSurfaceStepProgress,
      progress.steps.indices.contains(index),
      let routePlanID = selectedRoute?.routePlan.id
    else { return nil }
    let originalInstruction = progress.steps[index].instruction
    let instruction = originalInstruction
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !instruction.isEmpty else { return nil }
    let localized = SurfaceGuidancePresentation.instruction(
      originalInstruction, sourceLanguageCode: route.guidanceLanguageCode,
      locale: languageSelectionProvider().guidanceVoiceLocale
    )
    let id = "provider.surface.\(phase.rawValue.lowercased()).\(surfaceSpeechGeneration).\(index)"
    return GuidanceSpeechCommand(
      identity: GuidanceSpeechIdentity(
        promptID: id, anchorID: "PROVIDER_SURFACE_STEP", anchorOccurrenceID: id
      ),
      routePlanID: routePlanID, languageCode: localized.languageCode, spokenText: localized.text
    )
  }

  private func publishPresentationAndScheduleSpeech(
    from update: NavigationSessionUpdate
  ) {
    guard
      phase == .entryTransition || phase == .expressway,
      let frame = update.navigationSnapshot.activeGuidanceFrame
    else {
      presentationProjection = nil
      return
    }
    do {
      let retry =
        update.guidanceProgressState == .resolved
        && update.navigationSnapshot.guidancePlanningStatus == .frameUpdated
        && update.navigationSnapshot.lastGuidancePromptID == frame.promptID
        && !consumedGuidancePromptIDs.contains(frame.promptID)
      let emission =
        update.guidancePromptEmission
        ?? (retry
          ? GuidancePromptEmission(
            promptID: frame.promptID, anchorID: frame.anchorID,
            anchorOccurrenceID: frame.anchorOccurrenceID
          ) : nil)
      let projection = try NavigationPresentationProjector.project(
        NavigationPresentationRequest(
          snapshot: update.navigationSnapshot,
          networkSnapshotID: database.networkSnapshotID,
          guidanceFrame: frame,
          promptEmission: emission,
          languages: languageSelectionProvider(),
          passageEvidence: .noKnownConflictRealtimeUnconfirmed,
          drivingContext: PresentationDrivingContext(
            isVehicleMoving: true,
            isInsideDecisionZone: true
          )
        )
      )
      presentationProjection = projection
      guard let emission else {
        return
      }
      if let entranceAnnouncement,
        frame.movementOccurrenceID == entranceAnnouncement.movementOccurrenceID,
        nowMillisecondsProvider() - entranceAnnouncement.atMilliseconds
          <= Self.entranceAnnouncementRepeatMilliseconds
      {
        consumedGuidancePromptIDs.insert(emission.promptID)
        return
      }
      guard
        !consumedGuidancePromptIDs.contains(emission.promptID)
      else {
        speechStatus = .suppressed(.duplicate)
        return
      }
      guard let speechCoordinator else {
        speechStatus = .invalidProjection
        return
      }
      _ = speechCoordinator.submit(projection)
    } catch {
      presentationProjection = nil
      if update.guidancePromptEmission != nil {
        speechStatus = .invalidProjection
      }
    }
  }

  private func completeExpresswayObservationReplay() {
    if endsAtParkingArea {
      if phase != .completed { isPlaying = false; failureCode = "PARKING_AREA_ARRIVAL_UNCONFIRMED" }
      return
    }
    guard phase == .expressway else {
      isPlaying = false
      failureCode = "WHOLE_SHUTO_ENTRY_TRANSITION_UNCONFIRMED"
      return
    }
    guard
      matcherConfidence == .high,
      runtimeJourneyPhase == .strictRoute,
      runtimeOccurrenceID
        == selectedRoute?.routePlan.occurrences.last?.id
    else {
      isPlaying = false
      failureCode = "WHOLE_SHUTO_EXIT_HANDOFF_UNCONFIRMED"
      return
    }
    progressFraction = 0
    phase = .exitTransition
    matcherConfidence = nil
    runtimeJourneyPhase = nil
    runtimeRecoveryStatus = nil
    runtimeRecoveryTargetOccurrenceID = nil
    runtimeRecoveryDirectedEdgeID = nil
    runtimeOccurrenceID = nil
    runtimeFractionAlongOccurrence = nil
    runtimeCoordinate = selectedRoute?.coordinates.last
    presentationProjection = nil
    persistCheckpoint()
    if isPlaying {
      startPlaybackLoop()
    }
  }

  private var activeExpresswayEdge: ShutoNetworkDatabase.Edge? {
    guard let route = selectedRoute, !route.edges.isEmpty else {
      return nil
    }
    if let runtimeOccurrenceID,
      let occurrence = route.routePlan.occurrence(
        id: runtimeOccurrenceID
      ),
      route.edges.indices.contains(occurrence.index)
    {
      return route.edges[occurrence.index]
    }
    let target =
      route.distanceMeters
      * min(1, max(0, progressFraction))
    var traversed = 0.0
    for edge in route.edges {
      if traversed + edge.lengthMeters >= target {
        return edge
      }
      traversed += edge.lengthMeters
    }
    return route.edges.last
  }

  private func restoreCheckpointIfAvailable() {
    guard let checkpointStore else { return }
    let checkpoint: WholeShutoJourneyCheckpoint
    do {
      guard let loaded = try checkpointStore.load() else { return }
      checkpoint = loaded
    } catch {
      discardCheckpointDuringRestore()
      return
    }
    guard
      checkpoint.schemaVersion
        == WholeShutoJourneyCheckpoint.currentSchemaVersion
    else {
      discardCheckpointDuringRestore()
      return
    }
    guard checkpoint.networkSnapshotID == database.networkSnapshotID else {
      discardCheckpointDuringRestore()
      return
    }
    guard checkpoint.phase != .planning,
      checkpoint.phase != .review,
      checkpoint.phase != .completed
    else {
      discardCheckpointDuringRestore()
      return
    }
    var restoredCircuit: ShutoCircuitDefinition?
    var route: ShutoPlannedRoute
    do {
      if checkpoint.routeSelectionSource == .circuit {
        guard
          let circuit = ShutoCircuitDefinition.bundled.first(
            where: { $0.circuitID == checkpoint.circuitID }
          ),
          let laps = checkpoint.circuitLaps
        else {
          throw WholeShutoSavedRouteResolutionError.invalidTemplateMetadata
        }
        restoredCircuit = circuit
        route = try planner.planCircuit(
          reproducing: checkpoint.parkingStops?.baseRoutePlan ?? checkpoint.routePlan,
          circuit: circuit,
          laps: laps,
          preference: checkpoint.preference
        )
      } else {
        guard checkpoint.circuitID == nil,
          checkpoint.circuitLaps == nil
        else {
          throw WholeShutoSavedRouteResolutionError.invalidTemplateMetadata
        }
        route = try planner.restore(
          routePlan: checkpoint.parkingStops?.baseRoutePlan ?? checkpoint.routePlan,
          preference: checkpoint.preference
        )
      }
      if let stops = checkpoint.parkingStops {
        guard stops.baseRoutePlan == route.routePlan else { throw ShutoNetworkError.routeUnavailable }
        route = try planner.addingParkingStops(stops.parkingAreaIDs, to: route)
      }
      guard route.routePlan == checkpoint.routePlan else {
        throw WholeShutoSavedRouteResolutionError.invalidRoutePlan
      }
    } catch {
      discardCheckpointDuringRestore()
      return
    }
    let accessDistance = checkpoint.accessRoute?.distanceMeters ?? 0
    let egressDistance = checkpoint.egressRoute?.distanceMeters ?? 0
    originQuery = checkpoint.originQuery
    destinationQuery = checkpoint.destinationQuery
    origin = checkpoint.origin
    destination = checkpoint.destination
    journeyEnding = checkpoint.journeyEnding
      ?? (checkpoint.destination.coordinate == checkpoint.origin.coordinate
        ? .returnToOrigin : .destination)
    preference = checkpoint.preference
    let restoredRecommendation = ShutoRouteRecommendation(
      route: route,
      surfaceAccessDistanceMeters: accessDistance,
      surfaceEgressDistanceMeters: egressDistance,
      totalScoreMeters:
        route.distanceMeters + accessDistance + egressDistance
    )
    switch checkpoint.routeSelectionSource {
    case .custom:
      recommendations =
        (try? planner.recommend(
          from: checkpoint.origin.coordinate,
          to: checkpoint.destination.coordinate
        )) ?? []
      customRecommendation = restoredRecommendation
      isCustomRouteSelected = true
      customEntryFacilityID = route.entryFacility.facilityID
      customExitFacilityID = route.exitFacility?.facilityID
      customPreference = route.preference
      customDraftRoute = route
    case .circuit:
      recommendations = []
      clearCustomRouteSelection()
      selectedCircuit = restoredCircuit
      circuitLaps = checkpoint.circuitLaps ?? 1
      circuitEntryFacilityID = route.entryFacility.facilityID
      circuitExitFacilityID = route.exitFacility?.facilityID
      circuitPairingBand = route.exitFacility.flatMap { exit in
        try? planner.tariffBand(entryFacilityID: route.entryFacility.facilityID, exitFacilityID: exit.facilityID, evidence: activeTariffEvidence)
      }
      circuitRecommendation = restoredRecommendation
      isCircuitRouteSelected = true
    case .recommended:
      recommendations = [restoredRecommendation]
      clearCustomRouteSelection()
    }
    selectedRecommendationIndex = 0
    parkingStopSelection = checkpoint.parkingStops
    accessRoute = checkpoint.accessRoute
    egressRoute = checkpoint.egressRoute
    phase = checkpoint.phase
    progressFraction = min(1, max(0, checkpoint.progressFraction))
    mapMode = checkpoint.mapMode
    isPlaying = false
    restoredFromCheckpoint = true
    consumedGuidancePromptIDs = Set(
      checkpoint.consumedGuidancePromptIDs ?? []
    )
    if checkpoint.driveMode == .live {
      guard let navigationCheckpoint = checkpoint.liveNavigationCheckpoint else {
        reset()
        return
      }
      runtimeAssets = nil
      driveSimulator = nil
      liveDriveSession = nil
      liveEntryTransitionAdapter = nil
      liveSurfaceEgressAdapter = nil
      liveNavigationCheckpoint = navigationCheckpoint
      pendingLiveNavigationCheckpoint = navigationCheckpoint
      isLiveDrive = true
      liveLocationState = .resumeRequired
      if showsDriveRecord {
        driveRecord = checkpoint.driveRecord
          ?? WholeShutoDriveRecord(startedAtMilliseconds: nowMillisecondsProvider())
      }
      joinedOccurrenceID = checkpoint.joinedOccurrenceID
      declaredEntryFacilityID = checkpoint.declaredEntryFacilityID
      liveLocationIssueCode = "LIVE_RESUME_REQUIRED"
      matcherConfidence = .low
      runtimeOccurrenceID = checkpoint.runtimeOccurrenceID
      runtimeJourneyPhase = navigationCheckpoint.state.journeyPhase
      leftRouteAtUnplannedExit =
        navigationCheckpoint.state.lastPhaseTransitionTrigger == "UNPLANNED_EXIT"
      runtimeRecoveryStatus = navigationCheckpoint.state.recovery.status
      runtimeRecoveryTargetOccurrenceID =
        navigationCheckpoint.state.recovery.chosenRejoinOccurrenceID
      runtimeRecoveryDirectedEdgeID = nil
      runtimeCoordinate = nil
      runtimeFractionAlongOccurrence =
        checkpoint.runtimeFractionAlongOccurrence
      failureCode = nil
      return
    }
    do {
      let needsRuntime =
        checkpoint.phase == .entryTransition
        || checkpoint.phase == .expressway
      guard needsRuntime else { return }
      let assets = try ShutoPlannedRouteRuntimeCompiler.compile(
        database: database,
        route: route
      )
      guard checkpoint.runtimeAssetIdentity == assets.runtimeAssetIdentity else {
        throw WholeShutoProductError.noExpresswayRoute
      }
      runtimeAssets = assets
      try configureSpeech(for: route.routePlan.id)

      liveDriveSession = nil
      liveEntryTransitionAdapter = nil
      liveSurfaceEgressAdapter = nil
      liveNavigationCheckpoint = nil
      isLiveDrive = false
      liveLocationState = .inactive
      driveSimulator = try NavigationDriveSimulator(
        route: route,
        runtimeAssets: assets,
        configuration: NavigationDriveSimulationConfiguration(
          sampleFractions: route.destinationParkingArea == nil ? [0.15, 0.5, 0.85] : [0.15, 0.5, 0.95],
          maximumSampleSpacingMeters: 30,
          timing: .routeSpeed,
          horizontalAccuracyMeters: 2,
          speedMetersPerSecond:
            Self.simulationReferenceSpeedMetersPerSecond
        ),
        speed: Self.simulationPlaybackSpeed
      )
      if checkpoint.phase == .entryTransition {
        guard
          checkpoint.runtimeOccurrenceID == nil,
          checkpoint.runtimeFractionAlongOccurrence == nil,
          progressFraction == 0
        else {
          throw WholeShutoProductError.noExpresswayRoute
        }
      } else {
        guard checkpoint.phase == .expressway else { return }
        try restoreRuntimePositionOrThrow(
          occurrenceID: checkpoint.runtimeOccurrenceID,
          fraction: checkpoint.runtimeFractionAlongOccurrence,
          route: route
        )
      }
    } catch {
      speechCoordinator?.stop()
      speechCoordinator = nil
      runtimeAssets = nil
      driveSimulator = nil
      liveDriveSession = nil
      liveEntryTransitionAdapter = nil
      liveSurfaceEgressAdapter = nil
      liveNavigationCheckpoint = nil
      isLiveDrive = false
      liveLocationState = .inactive
      liveLocationIssueCode = nil
      phase = .review
      progressFraction = 0
      mapMode = .network
      matcherConfidence = nil
      runtimeOccurrenceID = nil
      runtimeJourneyPhase = nil
      runtimeRecoveryStatus = nil
      runtimeRecoveryTargetOccurrenceID = nil
      runtimeRecoveryDirectedEdgeID = nil
      runtimeCoordinate = nil
      runtimeFractionAlongOccurrence = nil
      failureCode = nil
      discardCheckpointDuringRestore()
    }
  }

  private func persistCheckpoint() {
    guard let checkpoint = currentCheckpoint(), let checkpointStore else {
      return
    }
    checkpointWriteGeneration &+= 1
    do {
      try checkpointStore.save(checkpoint)
      checkpointIssueCode = nil
    } catch {
      rejectCheckpoint(Self.checkpointSaveFailedCode)
    }
  }

  /// Saves off the main actor. The outcome is applied only when no later
  /// save or remove was asked for meanwhile: a later write supersedes this
  /// one in the file, so its failure must not remove the newer checkpoint.
  /// - Returns: whether the store holds what this call asked for: the
  ///   checkpoint was written and nothing superseded it, or there was none to
  ///   write and no checkpoint issue stands.
  private func persistCheckpointInBackground() async -> Bool {
    guard let checkpoint = currentCheckpoint(), let checkpointStore else {
      return checkpointIssueCode == nil
    }
    checkpointWriteGeneration &+= 1
    let generation = checkpointWriteGeneration
    do {
      try await checkpointStore.saveInBackground(checkpoint)
      guard generation == checkpointWriteGeneration else { return false }
      checkpointIssueCode = nil
      return true
    } catch {
      guard generation == checkpointWriteGeneration else { return false }
      rejectCheckpoint(Self.checkpointSaveFailedCode)
      return false
    }
  }

  private func currentCheckpoint() -> WholeShutoJourneyCheckpoint? {
    guard let origin, let destination, let route = selectedRoute,
      phase != .planning, phase != .completed
    else {
      return nil
    }
    return WholeShutoJourneyCheckpoint(
      schemaVersion: WholeShutoJourneyCheckpoint.currentSchemaVersion,
      networkSnapshotID: database.networkSnapshotID,
      originQuery: originQuery,
      destinationQuery: destinationQuery,
      origin: origin,
      destination: destination,
      entryFacilityID: route.entryFacility.facilityID,
      exitFacilityID: route.exitFacility?.facilityID,
      routePlan: route.routePlan,
      preference: route.preference,
      routeSelectionSource:
        isCircuitRouteSelected
        ? .circuit
        : isCustomRouteSelected ? .custom : .recommended,
      driveMode: isLiveDrive ? .live : .simulation,
      phase: phase,
      progressFraction: progressFraction,
      runtimeOccurrenceID: runtimeOccurrenceID,
      runtimeFractionAlongOccurrence:
        runtimeFractionAlongOccurrence,
      consumedGuidancePromptIDs:
        consumedGuidancePromptIDs.sorted(),
      mapMode: mapMode,
      accessRoute: accessRoute,
      egressRoute: egressRoute,
      circuitID:
        isCircuitRouteSelected ? selectedCircuit?.circuitID : nil,
      circuitLaps: isCircuitRouteSelected ? circuitLaps : nil,
      runtimeAssetIdentity:
        phase == .entryTransition || phase == .expressway
        ? runtimeAssets?.runtimeAssetIdentity : nil,
      liveNavigationCheckpoint:
        isLiveDrive ? liveNavigationCheckpoint : nil,
      driveRecord: isLiveDrive && showsDriveRecord ? driveRecord : nil,
      journeyEnding: journeyEnding,
      parkingStops: parkingStopSelection,
      joinedOccurrenceID: joinedOccurrenceID,
      declaredEntryFacilityID: declaredEntryFacilityID
    )
  }

  private func rejectCheckpoint(_ issueCode: String) {
    checkpointWriteGeneration &+= 1
    guard let checkpointStore else {
      checkpointIssueCode = issueCode
      return
    }
    do {
      try checkpointStore.remove()
      checkpointIssueCode = issueCode
    } catch {
      checkpointIssueCode = Self.checkpointRemoveFailedCode
    }
  }

  private func discardCheckpointDuringRestore() {
    checkpointWriteGeneration &+= 1
    guard let checkpointStore else { return }
    do {
      try checkpointStore.remove()
      checkpointIssueCode = nil
    } catch {
      checkpointIssueCode = Self.checkpointRemoveFailedCode
    }
  }

  private func removeCheckpoint() {
    checkpointWriteGeneration &+= 1
    guard let checkpointStore else { return }
    do {
      try checkpointStore.remove()
      checkpointIssueCode = nil
    } catch {
      checkpointIssueCode = Self.checkpointRemoveFailedCode
    }
  }

  private func captureAndPersistLiveCheckpoint(
    from session: ShutoLiveDriveSession,
    force: Bool = false
  ) async {
    let savedAtMilliseconds = nowMillisecondsProvider()
    if !force,
      let lastSaved = lastLiveCheckpointPersistedAtMilliseconds,
      savedAtMilliseconds - lastSaved
        < Self.liveCheckpointPersistenceIntervalMilliseconds
    {
      return
    }
    do {
      let checkpoint = try await session.makeCheckpoint(
        savedAtMilliseconds: savedAtMilliseconds
      )
      // An ended or swapped drive must not be written back as resumable.
      guard liveDriveSession === session else { return }
      liveNavigationCheckpoint = checkpoint
      if await persistCheckpointInBackground() {
        lastLiveCheckpointPersistedAtMilliseconds = savedAtMilliseconds
      }
    } catch {
      failureCode = Self.checkpointRuntimeInvalidCode
      checkpointIssueCode = Self.checkpointRuntimeInvalidCode
    }
  }

  /// Evaluated on each expressway fix; fixes arrive at about 1 Hz, so the
  /// marker changes within a second of the threshold without a timer.
  private func updateLivePositionHolding(
    from update: NavigationSessionUpdate,
    atMilliseconds milliseconds: Int
  ) {
    guard update.navigationSnapshot.journeyPhase == .strictRoute else {
      lastAdmittedLiveFixAtMilliseconds = nil
      isHoldingLivePosition = false
      return
    }
    let admitted = update.admittedConfidence == .high
    if admitted || lastAdmittedLiveFixAtMilliseconds == nil {
      lastAdmittedLiveFixAtMilliseconds = milliseconds
    }
    isHoldingLivePosition =
      !admitted
      && milliseconds - (lastAdmittedLiveFixAtMilliseconds ?? milliseconds)
        >= Self.livePositionHoldingMilliseconds
  }

  private func markLiveFixUsable(atMilliseconds milliseconds: Int) {
    lastUsableLiveObservationAtMilliseconds = milliseconds
    liveLocationIssueCode = nil
    liveLocationState = .available
    scheduleLiveLocationFreshnessCheck()
  }

  private func scheduleLiveLocationFreshnessCheck(
    afterMilliseconds: Int = WholeShutoProductModel.liveLocationStaleAfterMilliseconds
  ) {
    liveLocationFreshnessTask?.cancel()
    guard isLiveDrive, isPlaying else { return }
    liveLocationFreshnessTask = Task { [weak self] in
      try? await Task.sleep(
        for: .milliseconds(afterMilliseconds)
      )
      guard !Task.isCancelled, let self else { return }
      self.evaluateLiveLocationFreshness(
        atMilliseconds: self.nowMillisecondsProvider()
      )
    }
  }

  func evaluateLiveLocationFreshness(
    atMilliseconds nowMilliseconds: Int
  ) {
    guard isLiveDrive, isPlaying else { return }
    let reference =
      lastUsableLiveObservationAtMilliseconds
      ?? liveLocationStartedAtMilliseconds
    guard let reference,
      nowMilliseconds - reference
        >= Self.liveLocationStaleAfterMilliseconds
    else {
      if liveLocationState == .degraded, tunnelEstimateAnchor != nil {
        updateTunnelEstimate(atMilliseconds: nowMilliseconds)
        scheduleTunnelEstimateRefreshIfNeeded(atMilliseconds: nowMilliseconds)
        return
      }
      scheduleLiveLocationFreshnessCheck(
        afterMilliseconds: Self.liveLocationStaleAfterMilliseconds
          - max(0, reference.map { nowMilliseconds - $0 } ?? 0)
      )
      return
    }
    liveLocationState = .stale
    speechCoordinator?.invalidateGuidance(keepingNotices: true)
    let cooledDown = positionLossAnnouncedAtMilliseconds.map {
      nowMilliseconds - $0 >= Self.positionLossAnnouncementCooldownMilliseconds
    } ?? true
    if !positionLossAnnounced, cooledDown {
      positionLossAnnounced = true
      positionLossAnnouncedAtMilliseconds = nowMilliseconds
      announceJourneyNotice(.positionLost)
    }
    liveLocationIssueCode =
      lastLiveObservationAtMilliseconds.map {
        nowMilliseconds - $0 < Self.liveLocationStaleAfterMilliseconds
      } == true
      ? "LIVE_NO_FIX_ON_ROUTE" : "CORE_LOCATION_NO_RECENT_FIX"
    matcherConfidence = .low
    updateTunnelEstimate(atMilliseconds: nowMilliseconds)
    scheduleTunnelEstimateRefreshIfNeeded(
      atMilliseconds: nowMilliseconds
    )
  }

  private func refreshTunnelEstimateAnchor(
    from envelope: CoreLocationObservationEnvelope
  ) {
    clearTunnelEstimate()
    guard
      phase == .expressway,
      let route = selectedRoute,
      let occurrenceID = runtimeOccurrenceID,
      let occurrence = route.routePlan.occurrence(id: occurrenceID),
      route.edges.indices.contains(occurrence.index),
      let fraction = runtimeFractionAlongOccurrence,
      fraction.isFinite,
      (0...1).contains(fraction),
      let way = waysByID[route.edges[occurrence.index].wayID],
      way.tags["tunnel"] == "yes" || way.tags["covered"] == "yes",
      let speed = envelope.observation.speedMetersPerSecond,
      speed.isFinite,
      speed > 0
    else {
      return
    }

    let distanceBeforeOccurrence = route.edges.prefix(occurrence.index)
      .reduce(0) { $0 + $1.lengthMeters }
    let routeDistance =
      distanceBeforeOccurrence
      + route.edges[occurrence.index].lengthMeters * fraction
    let nextDecisionIndex = route.routePlan.occurrences
      .first {
        $0.index > occurrence.index
          && $0.kind == .junctionMovement
      }?.index
    let safetyLimit =
      nextDecisionIndex.map {
        route.edges.prefix($0).reduce(0) { $0 + $1.lengthMeters }
      } ?? route.distanceMeters

    tunnelEstimateAnchor = TunnelEstimateAnchor(
      routePlanID: route.routePlan.id,
      occurrenceID: occurrenceID,
      receivedAtMilliseconds:
        envelope.observation.receivedAtMilliseconds,
      routeDistanceMeters: routeDistance,
      safetyLimitRouteDistanceMeters: max(routeDistance, safetyLimit),
      speedMetersPerSecond: speed,
      speedAccuracyMetersPerSecond:
        envelope.observation.speedAccuracyMetersPerSecond
    )
  }

  private func synchronizeLiveTunnelState(
    from estimate: MatcherEstimate,
    session: ShutoLiveDriveSession
  ) async {
    guard
      let route = selectedRoute,
      let occurrenceID = estimate.occurrenceID,
      let occurrence = route.routePlan.occurrence(id: occurrenceID),
      route.edges.indices.contains(occurrence.index),
      let way = waysByID[route.edges[occurrence.index].wayID]
    else { return }
    let isInTunnel = way.tags["tunnel"] == "yes"
      || way.tags["covered"] == "yes"
    if isInTunnel, !liveMatcherWasInTunnel {
      _ = await session.enterTunnel()
      liveMatcherWasInTunnel = true
    } else if !isInTunnel, liveMatcherWasInTunnel {
      _ = await session.exitTunnel()
      liveMatcherWasInTunnel = false
    }
  }

  private func updateTunnelEstimate(atMilliseconds nowMilliseconds: Int) {
    guard
      let anchor = tunnelEstimateAnchor,
      let route = selectedRoute,
      route.routePlan.id == anchor.routePlanID,
      runtimeOccurrenceID == anchor.occurrenceID,
      nowMilliseconds >= anchor.receivedAtMilliseconds,
      let estimate = TunnelPositionEstimator.estimate(
        anchorRouteDistanceMeters: anchor.routeDistanceMeters,
        routeDistanceMeters: route.distanceMeters,
        safetyLimitRouteDistanceMeters:
          anchor.safetyLimitRouteDistanceMeters,
        speedMetersPerSecond: anchor.speedMetersPerSecond,
        speedAccuracyMetersPerSecond:
          anchor.speedAccuracyMetersPerSecond,
        elapsedMilliseconds:
          nowMilliseconds - anchor.receivedAtMilliseconds
      )
    else {
      tunnelEstimatedProgressFraction = nil
      tunnelEstimateUncertaintyMeters = nil
      return
    }
    tunnelEstimatedProgressFraction = min(
      1,
      max(progressFraction, estimate.routeDistanceMeters / route.distanceMeters)
    )
    tunnelEstimateUncertaintyMeters = estimate.uncertaintyRadiusMeters
  }

  private func scheduleTunnelEstimateRefreshIfNeeded(
    atMilliseconds nowMilliseconds: Int
  ) {
    guard
      tunnelEstimatedProgressFraction != nil,
      let anchor = tunnelEstimateAnchor,
      nowMilliseconds >= anchor.receivedAtMilliseconds,
      Double(nowMilliseconds - anchor.receivedAtMilliseconds) / 1_000
        < TunnelPositionEstimator.maximumHorizonSeconds
    else {
      return
    }
    scheduleLiveLocationFreshnessCheck(
      afterMilliseconds: Self.tunnelEstimateRefreshMilliseconds
    )
  }

  private func clearTunnelEstimate() {
    tunnelEstimateAnchor = nil
    tunnelEstimatedProgressFraction = nil
    tunnelEstimateUncertaintyMeters = nil
  }

  private func releasedRecoveryCandidate(
    targetOccurrenceID: String,
    containing directedEdgeID: String?
  ) -> RecoveryCandidate? {
    guard
      let policy = activeLiveAdmission?.core.release.navigation.bundle
        .runtimePolicy
    else {
      return nil
    }
    let candidates = policy.recoveryCandidates.filter {
      $0.isReleased && $0.targetOccurrenceID == targetOccurrenceID
    }
    let matchingCandidates: [RecoveryCandidate]
    if let directedEdgeID {
      matchingCandidates = candidates.filter {
        $0.recoveryOccurrenceIDs.contains(directedEdgeID)
      }
    } else {
      matchingCandidates = candidates
    }
    return matchingCandidates.count == 1 ? matchingCandidates[0] : nil
  }

  /// Presentation only: the released detour is drawn from where the matcher
  /// places the car on it. Off the plan every neighbouring branch segment
  /// counts against the raw confidence, so it is not gated on raw HIGH.
  private func updateReleasedRecoveryPosition(
    from estimate: MatcherEstimate
  ) {
    guard
      estimate.confidence != .lost,
      estimate.occurrenceID == nil,
      let directedEdgeID = estimate.directedEdgeID,
      let targetOccurrenceID = runtimeRecoveryTargetOccurrenceID,
      releasedRecoveryCandidate(
        targetOccurrenceID: targetOccurrenceID,
        containing: directedEdgeID
      ) != nil,
      let edge = activeLiveAdmission?.core.release.navigation.bundle
        .matcherCorridor.edges.first(where: { $0.id == directedEdgeID }),
      let fraction = estimate.fractionAlongEdge,
      let coordinate = Self.interpolateMatcherEdge(
        edge,
        fraction: fraction
      )
    else {
      return
    }
    runtimeRecoveryDirectedEdgeID = directedEdgeID
    runtimeCoordinate = coordinate
  }

  private static func interpolateMatcherEdge(
    _ edge: RouteMatcherDirectedEdge,
    fraction: Double
  ) -> ShutoCoordinate? {
    guard edge.coordinates.count >= 2, fraction.isFinite else {
      return nil
    }
    let coordinates = edge.coordinates.map {
      ShutoCoordinate(
        latitude: $0.latitude,
        longitude: $0.longitude
      )
    }
    let lengths = zip(coordinates, coordinates.dropFirst()).map {
      distance($0, $1)
    }
    let total = lengths.reduce(0, +)
    guard total > 0 else { return coordinates.first }
    let target = total * min(1, max(0, fraction))
    var traversed = 0.0
    for index in lengths.indices {
      let length = lengths[index]
      if traversed + length >= target || index == lengths.indices.last {
        let localFraction =
          length > 0
          ? min(1, max(0, (target - traversed) / length))
          : 0
        let start = coordinates[index]
        let end = coordinates[index + 1]
        return ShutoCoordinate(
          latitude: start.latitude
            + (end.latitude - start.latitude) * localFraction,
          longitude: start.longitude
            + (end.longitude - start.longitude) * localFraction
        )
      }
      traversed += length
    }
    return coordinates.last
  }

  private func estimatedExpresswayPosition(
    at routeProgressFraction: Double
  ) -> (
    edgeIndex: Int,
    edgeFraction: Double,
    coordinate: ShutoCoordinate
  )? {
    guard
      let route = selectedRoute,
      !route.edges.isEmpty,
      route.coordinates.count == route.edges.count + 1,
      route.distanceMeters > 0
    else {
      return nil
    }
    let target =
      route.distanceMeters
      * min(1, max(0, routeProgressFraction))
    var traversed = 0.0
    for index in route.edges.indices {
      let edgeLength = route.edges[index].lengthMeters
      if traversed + edgeLength >= target || index == route.edges.indices.last {
        let fraction =
          edgeLength > 0
          ? min(1, max(0, (target - traversed) / edgeLength))
          : 0
        let start = route.coordinates[index]
        let end = route.coordinates[index + 1]
        return (
          edgeIndex: index,
          edgeFraction: fraction,
          coordinate: ShutoCoordinate(
            latitude: start.latitude
              + (end.latitude - start.latitude) * fraction,
            longitude: start.longitude
              + (end.longitude - start.longitude) * fraction
          )
        )
      }
      traversed += edgeLength
    }
    return nil
  }

  private struct SurfaceRouteMeasurement {
    let fractionAlongRoute: Double
    let lateralDistanceMeters: Double
  }

  private static func surfaceRouteMeasurement(
    _ point: ShutoCoordinate,
    along coordinates: [ShutoCoordinate]
  ) -> SurfaceRouteMeasurement? {
    guard coordinates.count >= 2 else { return nil }
    let lengths = zip(coordinates, coordinates.dropFirst()).map {
      distance($0, $1)
    }
    let total = lengths.reduce(0, +)
    guard total > 0 else { return nil }
    var traversed = 0.0
    var best: SurfaceRouteMeasurement?
    for index in lengths.indices {
      let start = coordinates[index]
      let end = coordinates[index + 1]
      let referenceLatitude =
        (start.latitude + end.latitude + point.latitude) / 3
      let latitudeScale = 6_371_000.0 * .pi / 180
      let longitudeScale =
        latitudeScale * cos(referenceLatitude * .pi / 180)
      let segmentX =
        (end.longitude - start.longitude) * longitudeScale
      let segmentY =
        (end.latitude - start.latitude) * latitudeScale
      let pointX =
        (point.longitude - start.longitude) * longitudeScale
      let pointY =
        (point.latitude - start.latitude) * latitudeScale
      let squaredLength = segmentX * segmentX + segmentY * segmentY
      let localFraction =
        squaredLength > 0
        ? min(
          1,
          max(
            0,
            (pointX * segmentX + pointY * segmentY)
              / squaredLength
          )
        ) : 0
      let lateral = hypot(
        pointX - segmentX * localFraction,
        pointY - segmentY * localFraction
      )
      let measurement = SurfaceRouteMeasurement(
        fractionAlongRoute:
          min(1, max(0, (traversed + lengths[index] * localFraction) / total)),
        lateralDistanceMeters: lateral
      )
      if best.map({ lateral < $0.lateralDistanceMeters }) != false {
        best = measurement
      }
      traversed += lengths[index]
    }
    return best
  }

  private func restoreRuntimePositionOrThrow(
    occurrenceID: String?,
    fraction: Double?,
    route: ShutoPlannedRoute
  ) throws {
    if occurrenceID == nil, fraction == nil {
      return
    }
    guard
      let occurrenceID,
      let occurrence = route.routePlan.occurrence(id: occurrenceID),
      route.edges.indices.contains(occurrence.index),
      let fraction,
      fraction.isFinite,
      (0...1).contains(fraction)
    else {
      throw WholeShutoProductError.noExpresswayRoute
    }
    runtimeOccurrenceID = occurrenceID
    runtimeFractionAlongOccurrence = fraction
    let start = route.coordinates[occurrence.index]
    let end = route.coordinates[occurrence.index + 1]
    runtimeCoordinate = ShutoCoordinate(
      latitude: start.latitude
        + (end.latitude - start.latitude) * fraction,
      longitude: start.longitude
        + (end.longitude - start.longitude) * fraction
    )
  }

  private func restoreObservationReplayIfNeeded() async -> Bool {
    guard phase == .expressway, restoredFromCheckpoint,
      let runtimeOccurrenceID, let driveSimulator
    else {
      return true
    }
    do {
      _ = try await driveSimulator.restore(
        at: runtimeOccurrenceID
      )
      return true
    } catch {
      isPlaying = false
      failureCode = Self.checkpointRuntimeInvalidCode
      rejectCheckpoint(Self.checkpointRuntimeInvalidCode)
      return false
    }
  }

  private var currentLocationTitle: String {
    switch languageSelectionProvider().interfaceLocale {
    case .japanese:
      "現在地"
    case .simplifiedChinese:
      "当前位置"
    case .english:
      "Current location"
    }
  }

  private func resolveOrigin() async throws -> WholeShutoPlace {
    let normalized = originQuery.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    if selectedOriginTitle == normalized, let origin {
      return origin
    }
    if Self.isCurrentLocationQuery(originQuery) {
      if let origin {
        return origin
      }
      do {
        let coordinate = try await locationProvider.currentCoordinate()
        return WholeShutoPlace(
          title: currentLocationTitle,
          coordinate: ShutoCoordinate(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
          )
        )
      } catch {
        throw WholeShutoProductError.locationUnavailable
      }
    }
    let place = try await placeResolver.resolve(
      query: originQuery,
      near: nil
    )
    return WholeShutoPlace(
      title: place.title,
      coordinate: ShutoCoordinate(
        latitude: place.coordinate.latitude,
        longitude: place.coordinate.longitude
      )
    )
  }

  private func resolveDestination(
    near origin: ShutoCoordinate
  ) async throws -> WholeShutoPlace {
    let normalized = destinationQuery.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !normalized.isEmpty else {
      throw WholeShutoProductError.destinationUnavailable
    }
    if selectedDestinationTitle == normalized, let destination {
      return destination
    }
    let place = try await placeResolver.resolve(
      query: normalized,
      near: .init(
        latitude: origin.latitude,
        longitude: origin.longitude
      )
    )
    return WholeShutoPlace(
      title: place.title,
      coordinate: ShutoCoordinate(
        latitude: place.coordinate.latitude,
        longitude: place.coordinate.longitude
      )
    )
  }

  private static func isCurrentLocationQuery(_ query: String) -> Bool {
    C2NavigationDemoModel.currentLocationTokens.contains(
      query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    )
  }

  private func refreshCustomRouteDraft() {
    guard
      let entryFacilityID = customEntryFacilityID,
      let exitFacilityID = customExitFacilityID,
      entryFacilityID != exitFacilityID
    else {
      customDraftRoute = nil
      return
    }
    if let circuit = editedCircuit {
      customDraftRoute = try? planner.planCircuit(
        circuit: circuit,
        entryFacilityID: entryFacilityID,
        exitFacilityID: exitFacilityID,
        laps: circuit.kind == .loop ? circuitLaps : 1,
        preference: customPreference
      )
      return
    }
    customDraftRoute = try? planner.plan(
      entryFacilityID: entryFacilityID,
      exitFacilityID: exitFacilityID,
      preference: customPreference
    )
  }

  private func refreshReachableExitCandidates() {
    guard let entryFacilityID = customEntryFacilityID else {
      reachableExitCandidates = []
      return
    }
    if let circuit = editedCircuit {
      reachableExitCandidates =
        (try? planner.circuitExitCandidates(
          for: circuit,
          afterEntering: entryFacilityID
        )) ?? []
      return
    }
    reachableExitCandidates = planner.exitCandidates(
      database.directionalFacilities,
      reachableAfterEntering: entryFacilityID
    )
  }

  private func refreshEntryCandidatesReachingExit() {
    guard let exitFacilityID = customExitFacilityID else {
      entryCandidatesReachingExit = []
      return
    }
    entryCandidatesReachingExit = planner.entryCandidates(
      database.directionalFacilities,
      reaching: exitFacilityID
    )
  }

  private func clearCustomRouteSelection() {
    customRecommendation = nil
    isCustomRouteSelected = false
    customEntryFacilityID = nil
    customExitFacilityID = nil
    customPreference = .recommended
    customDraftRoute = nil
    selectedSavedRouteTemplateParameters = nil
    parkingStopSelection = nil
  }

  private func facility(
    id: String?
  ) -> ShutoNetworkDatabase.Facility? {
    guard let id else { return nil }
    return database.directionalFacilities.first {
      $0.facilityID == id
    }
  }

  private func resolveSavedRoute(
    _ record: SavedRouteRecord
  ) throws -> WholeShutoResolvedSavedRoute {
    do {
      try SharedRouteCodec.validate(record.document)
    } catch {
      throw WholeShutoSavedRouteResolutionError.invalidRoutePlan
    }
    let routePlan = record.document.routePlan
    guard routePlan.networkSnapshotID == database.networkSnapshotID else {
      throw WholeShutoSavedRouteResolutionError.networkSnapshotMismatch
    }
    let templateParameters = record.document.templateParameters
    let routePreference: ShutoRoutePreference
    if let preferenceValue = templateParameters["preference"] {
      guard
        let preference = ShutoRoutePreference(
          rawValue: preferenceValue
        )
      else {
        throw WholeShutoSavedRouteResolutionError.invalidTemplateMetadata
      }
      routePreference = preference
    } else {
      routePreference =
        ShutoRoutePreference.allCases.first(where: {
          routePlan.id.hasSuffix(".\($0.rawValue.lowercased())")
        }) ?? .recommended
    }
    let selectionSource: WholeShutoRouteSelectionSource
    if let sourceValue = templateParameters["source"] {
      guard
        let source = Self.savedRouteSelectionSource(
          sourceValue
        )
      else {
        throw WholeShutoSavedRouteResolutionError.invalidTemplateMetadata
      }
      selectionSource = source
    } else {
      // A source-less schema-1.0 document remains a valid exact saved plan,
      // but it cannot claim circuit or recommendation provenance.
      selectionSource = .custom
    }

    let parkingStops = try templateParameters["parking_stops"].map {
      try JSONDecoder().decode(WholeShutoParkingStopSelection.self, from: Data($0.utf8))
    }
    do {
      let route: ShutoPlannedRoute
      let circuit: ShutoCircuitDefinition?
      let circuitLaps: Int?
      switch selectionSource {
      case .circuit:
        guard
          let circuitID = templateParameters["circuit_id"],
          let resolvedCircuit = ShutoCircuitDefinition.bundled.first(where: {
            $0.circuitID == circuitID
          }),
          let lapsValue = templateParameters["laps"],
          let laps = Int(lapsValue)
        else {
          throw WholeShutoSavedRouteResolutionError.invalidTemplateMetadata
        }
        let planned = try planner.planCircuit(
          reproducing: parkingStops?.baseRoutePlan ?? routePlan,
          circuit: resolvedCircuit,
          laps: laps,
          preference: routePreference
        )
        guard planned.routePlan == (parkingStops?.baseRoutePlan ?? routePlan) else {
          throw WholeShutoSavedRouteResolutionError.invalidTemplateMetadata
        }
        route = try planner.addingParkingStops(parkingStops?.parkingAreaIDs ?? [], to: planned)
        circuit = resolvedCircuit
        circuitLaps = laps
      case .custom, .recommended:
        guard templateParameters["circuit_id"] == nil,
          templateParameters["laps"] == nil
        else {
          throw WholeShutoSavedRouteResolutionError.invalidTemplateMetadata
        }
        let base = try planner.restore(
          routePlan: parkingStops?.baseRoutePlan ?? routePlan,
          preference: routePreference
        )
        route = try planner.addingParkingStops(parkingStops?.parkingAreaIDs ?? [], to: base)
        circuit = nil
        circuitLaps = nil
      }
      guard route.routePlan == routePlan else { throw ShutoNetworkError.routeUnavailable }
      _ = try ShutoPlannedRouteRuntimeCompiler.compile(
        database: database,
        route: route
      )
      return WholeShutoResolvedSavedRoute(
        route: route,
        selectionSource: selectionSource,
        circuit: circuit,
        circuitLaps: circuitLaps,
        templateParameters: templateParameters,
        parkingStops: parkingStops
      )
    } catch {
      if let resolutionError = error
        as? WholeShutoSavedRouteResolutionError
      {
        throw resolutionError
      }
      throw WholeShutoSavedRouteResolutionError.invalidRoutePlan
    }
  }

  private static func savedRouteSelectionSource(
    _ value: String
  ) -> WholeShutoRouteSelectionSource? {
    switch value {
    case "RECOMMENDATION":
      .recommended
    case "CUSTOM":
      .custom
    case "CIRCUIT":
      .circuit
    default:
      nil
    }
  }

  private func rankedCustomFacilities(
    from coordinate: ShutoCoordinate?,
    selectedFacilityID: String?,
    isEligible: KeyPath<ShutoNetworkDatabase.Facility, Bool>
  ) -> [ShutoNetworkDatabase.Facility] {
    guard let coordinate else { return [] }
    let ranked = database.directionalFacilities
      .filter {
        $0[keyPath: isEligible]
          && $0.operationalStatus == "AVAILABLE"
      }
      .sorted {
        let leftDistance = Self.distance(coordinate, $0.coordinate)
        let rightDistance = Self.distance(coordinate, $1.coordinate)
        if leftDistance != rightDistance {
          return leftDistance < rightDistance
        }
        return $0.facilityID < $1.facilityID
      }
    return pinningSelection(ranked, selectedFacilityID: selectedFacilityID)
  }

  private func pinningSelection(
    _ candidates: [ShutoNetworkDatabase.Facility],
    selectedFacilityID: String?
  ) -> [ShutoNetworkDatabase.Facility] {
    guard let selectedFacilityID,
      let selected = candidates.first(where: {
        $0.facilityID == selectedFacilityID
      })
    else {
      return candidates
    }
    return [selected]
      + candidates.filter { $0.facilityID != selectedFacilityID }
  }

  private func primaryRouteID(
    _ edge: ShutoNetworkDatabase.Edge
  ) -> String? {
    edge.routeMemberships.first?.routeID
  }

  private func interpolatedCoordinate(
    in coordinates: [ShutoCoordinate],
    fraction: Double
  ) -> ShutoCoordinate? {
    guard let first = coordinates.first else { return nil }
    guard coordinates.count > 1 else { return first }
    let measured = zip(coordinates, coordinates.dropFirst()).map {
      Self.distance($0, $1)
    }
    let total = measured.reduce(0, +)
    guard total > 0 else { return first }
    let target = total * min(1, max(0, fraction))
    var traversed = 0.0
    for index in measured.indices {
      let segment = measured[index]
      if traversed + segment >= target {
        let local = segment == 0 ? 0 : (target - traversed) / segment
        let before = coordinates[index]
        let after = coordinates[index + 1]
        return ShutoCoordinate(
          latitude:
            before.latitude + (after.latitude - before.latitude) * local,
          longitude:
            before.longitude
            + (after.longitude - before.longitude) * local
        )
      }
      traversed += segment
    }
    return coordinates.last
  }

  private var remainingProgress: Double {
    1 - min(1, max(0, progressFraction))
  }

  private func lookAheadCoordinate(
    in coordinates: [ShutoCoordinate],
    fraction: Double
  ) -> ShutoCoordinate? {
    Self.split(coordinates, distanceFraction: min(1, max(0, fraction)))
      .remainingCoordinates.dropFirst().first
  }

  private static func split(
    _ coordinates: [ShutoCoordinate],
    distanceFraction: Double
  ) -> WholeShutoRouteProgressGeometry {
    guard let first = coordinates.first else {
      return WholeShutoRouteProgressGeometry(
        traveledCoordinates: [],
        remainingCoordinates: []
      )
    }
    guard coordinates.count > 1 else {
      return WholeShutoRouteProgressGeometry(
        traveledCoordinates: [first],
        remainingCoordinates: [first]
      )
    }
    let clamped = min(1, max(0, distanceFraction))
    if clamped == 0 {
      return WholeShutoRouteProgressGeometry(
        traveledCoordinates: [first],
        remainingCoordinates: coordinates
      )
    }
    if clamped == 1 {
      return WholeShutoRouteProgressGeometry(
        traveledCoordinates: coordinates,
        remainingCoordinates: [coordinates.last!]
      )
    }
    let segmentDistances = zip(
      coordinates,
      coordinates.dropFirst()
    ).map(distance)
    let target = segmentDistances.reduce(0, +) * clamped
    var traversed = 0.0
    for index in segmentDistances.indices {
      let segmentDistance = segmentDistances[index]
      if traversed + segmentDistance >= target {
        let fraction =
          segmentDistance == 0
          ? 0 : (target - traversed) / segmentDistance
        return split(
          coordinates,
          afterVertexAt: index,
          segmentFraction: fraction
        )
      }
      traversed += segmentDistance
    }
    return WholeShutoRouteProgressGeometry(
      traveledCoordinates: coordinates,
      remainingCoordinates: [coordinates.last!]
    )
  }

  private static func split(
    _ coordinates: [ShutoCoordinate],
    afterVertexAt index: Int,
    segmentFraction: Double
  ) -> WholeShutoRouteProgressGeometry {
    guard
      coordinates.indices.contains(index),
      coordinates.indices.contains(index + 1)
    else {
      return WholeShutoRouteProgressGeometry(
        traveledCoordinates: coordinates,
        remainingCoordinates: coordinates.last.map { [$0] } ?? []
      )
    }
    let fraction = min(1, max(0, segmentFraction))
    let before = coordinates[index]
    let after = coordinates[index + 1]
    let splitCoordinate = ShutoCoordinate(
      latitude:
        before.latitude + (after.latitude - before.latitude) * fraction,
      longitude:
        before.longitude + (after.longitude - before.longitude) * fraction
    )
    var traveled = Array(coordinates[...index])
    if traveled.last != splitCoordinate {
      traveled.append(splitCoordinate)
    }
    var remaining = [splitCoordinate]
    if splitCoordinate == after {
      remaining = Array(coordinates[(index + 1)...])
    } else {
      remaining.append(contentsOf: coordinates[(index + 1)...])
    }
    return WholeShutoRouteProgressGeometry(
      traveledCoordinates: traveled,
      remainingCoordinates: remaining
    )
  }

  private static func bearing(
    from origin: ShutoCoordinate,
    to destination: ShutoCoordinate
  ) -> Double {
    let originLatitude = origin.latitude * .pi / 180
    let destinationLatitude = destination.latitude * .pi / 180
    let longitudeDelta =
      (destination.longitude - origin.longitude) * .pi / 180
    let y = sin(longitudeDelta) * cos(destinationLatitude)
    let x =
      cos(originLatitude) * sin(destinationLatitude)
      - sin(originLatitude) * cos(destinationLatitude)
      * cos(longitudeDelta)
    return (atan2(y, x) * 180 / .pi + 360)
      .truncatingRemainder(dividingBy: 360)
  }

  private static func previewSurfaceRoute(
    from origin: ShutoCoordinate,
    to destination: ShutoCoordinate
  ) -> WholeShutoSurfaceRoute {
    let distance = Self.distance(origin, destination)
    return WholeShutoSurfaceRoute(
      coordinates: [origin, destination],
      distanceMeters: distance,
      expectedTravelTimeSeconds: distance / 8.3,
      instructions: []
    )
  }

  private static func routeChoiceMetrics(
    recommendations: [ShutoRouteRecommendation],
    surfaceRoutesByRoutePlanID: [String: WholeShutoRouteChoiceSurfaceRoutes]
  ) -> [String: WholeShutoRouteChoiceMetrics] {
    Dictionary(
      uniqueKeysWithValues: recommendations.compactMap { recommendation in
        let routePlanID = recommendation.route.routePlan.id
        guard
          let routes = surfaceRoutesByRoutePlanID[routePlanID]
        else {
          return nil
        }
        return (
          routePlanID,
          routeChoiceMetrics(
            for: recommendation.route,
            accessRoute: routes.access,
            egressRoute: routes.egress
          )
        )
      }
    )
  }

  private static func routeChoiceMetrics(
    for route: ShutoPlannedRoute,
    accessRoute: WholeShutoSurfaceRoute,
    egressRoute: WholeShutoSurfaceRoute
  ) -> WholeShutoRouteChoiceMetrics {
    WholeShutoRouteChoiceMetrics(
      totalDistanceMeters:
        accessRoute.distanceMeters
        + route.distanceMeters
        + egressRoute.distanceMeters,
      expectedTravelTimeSeconds:
        accessRoute.expectedTravelTimeSeconds
        + route.distanceMeters
        / simulationReferenceSpeedMetersPerSecond
        + egressRoute.expectedTravelTimeSeconds
    )
  }

  private nonisolated static func distance(
    _ first: ShutoCoordinate,
    _ second: ShutoCoordinate
  ) -> Double {
    CLLocation(
      latitude: first.latitude,
      longitude: first.longitude
    ).distance(
      from: CLLocation(
        latitude: second.latitude,
        longitude: second.longitude
      )
    )
  }

  private static func failureCode(_ error: Error) -> String {
    switch error {
    case WholeShutoProductError.locationUnavailable:
      return "LOCATION_UNAVAILABLE"
    case WholeShutoProductError.destinationUnavailable:
      return "DESTINATION_REQUIRED"
    case WholeShutoProductError.noExpresswayRoute:
      return "NO_SHUTO_ROUTE"
    default:
      return "PLACE_OR_ROUTE_UNAVAILABLE"
    }
  }
}
