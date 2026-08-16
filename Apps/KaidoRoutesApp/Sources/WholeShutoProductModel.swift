import Combine
import CoreLocation
import Foundation
import KaidoAppleAdapters
import KaidoDomain
import KaidoNavigation
import KaidoPresentation
import KaidoRouting

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
    for result in results {
      switch result {
      case .accepted(let envelope):
        await consumeLiveObservationForTesting(envelope)
      case .rejected(let rejection):
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

enum WholeShutoLiveLocationState: String, Equatable, Sendable {
  case inactive = "INACTIVE"
  case resumeRequired = "RESUME_REQUIRED"
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
}

struct WholeShutoSurfaceRoute: Codable, Equatable, Sendable {
  let coordinates: [ShutoCoordinate]
  let distanceMeters: Double
  let expectedTravelTimeSeconds: Double
  let instructions: [String]
  let steps: [WholeShutoSurfaceRouteStep]?

  init(
    coordinates: [ShutoCoordinate],
    distanceMeters: Double,
    expectedTravelTimeSeconds: Double,
    instructions: [String],
    steps: [WholeShutoSurfaceRouteStep]? = nil
  ) {
    self.coordinates = coordinates
    self.distanceMeters = distanceMeters
    self.expectedTravelTimeSeconds = expectedTravelTimeSeconds
    self.instructions = instructions
    self.steps = steps
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
  case boundaryTransition = "BOUNDARY_TRANSITION"
  case networkPreview = "NETWORK_PREVIEW"
  case networkDegraded = "NETWORK_DEGRADED"
  case tunnelEstimated = "TUNNEL_ESTIMATED"
  case routeInterrupted = "ROUTE_INTERRUPTED"
  case completed = "COMPLETED"
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
  let exitFacilityID: String
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
}

@MainActor
protocol WholeShutoJourneyCheckpointStoring: AnyObject {
  func load() throws -> WholeShutoJourneyCheckpoint?
  func save(_ checkpoint: WholeShutoJourneyCheckpoint) throws
  func remove() throws
}

@MainActor
final class WholeShutoUserDefaultsCheckpointStore:
  WholeShutoJourneyCheckpointStoring
{
  static let key = "app.kaidoroutes.whole-shuto.journey-checkpoint"

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func load() throws -> WholeShutoJourneyCheckpoint? {
    guard let data = defaults.data(forKey: Self.key) else {
      return nil
    }
    return try JSONDecoder().decode(
      WholeShutoJourneyCheckpoint.self,
      from: data
    )
  }

  func save(_ checkpoint: WholeShutoJourneyCheckpoint) throws {
    defaults.set(
      try JSONEncoder().encode(checkpoint),
      forKey: Self.key
    )
  }

  func remove() throws {
    defaults.removeObject(forKey: Self.key)
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
}

enum WholeShutoNetworkCatalog {
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
      let database = try JSONDecoder().decode(
        ShutoNetworkDatabase.self,
        from: Data(contentsOf: url)
      )
      try database.validate()
      return database
    } catch {
      throw WholeShutoProductError.bundledNetworkInvalid
    }
  }
}

@MainActor
final class WholeShutoProductModel: ObservableObject {
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
  @Published private(set) var destination: WholeShutoPlace?
  @Published private(set) var recommendations: [ShutoRouteRecommendation] = []
  @Published private(set) var selectedRecommendationIndex = 0
  @Published private(set) var customRecommendation: ShutoRouteRecommendation?
  @Published private(set) var routeChoiceMetricsByRoutePlanID:
    [String: WholeShutoRouteChoiceMetrics] = [:]
  @Published private(set) var isCustomRouteSelected = false
  @Published private(set) var customEntryFacilityID: String?
  @Published private(set) var customExitFacilityID: String?
  @Published private(set) var customPreference: ShutoRoutePreference =
    .recommended
  @Published private(set) var customDraftRoute: ShutoPlannedRoute?
  @Published private(set) var selectedCircuit: ShutoCircuitDefinition?
  @Published private(set) var circuitEntranceCandidates: [ShutoNetworkDatabase.Facility] = []
  @Published private(set) var circuitEntryFacilityID: String?
  @Published private(set) var circuitExitFacilityID: String?
  @Published private(set) var circuitPairingBand: ShutoTariffBand?
  @Published private(set) var circuitEntranceDistanceMeters: Double?
  @Published private(set) var circuitThumbnailsByID: [String: [CGPoint]] =
    [:]
  @Published private(set) var isResolvingCircuitPairing = false
  @Published private(set) var circuitLaps = 1
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
  @Published private(set) var liveLocationIssueCode: String?
  @Published private(set) var failureCode: String?
  @Published private(set) var checkpointIssueCode: String?
  @Published private(set) var isPlanning = false
  @Published private(set) var isUpdatingSurfaceRoute = false
  @Published private(set) var isReroutingSurfaceRoute = false
  @Published private(set) var isPreparingLiveNavigation = false
  @Published private(set) var restoredFromCheckpoint = false
  @Published private(set) var matcherConfidence: MatcherConfidence?
  @Published private(set) var runtimeOccurrenceID: String?
  @Published private(set) var runtimeJourneyPhase: JourneyPhase?
  @Published private(set) var runtimeRecoveryStatus: RecoveryState.Status?
  @Published private(set) var presentationProjection: NavigationPresentationProjection?
  @Published private(set) var speechStatus: GuidanceSpeechCoordinatorStatus = .idle

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
  private var lastSurfaceRerouteAttemptAtMilliseconds: Int?
  private var liveAdmissionTask: Task<Void, Never>?
  private var liveAdmissionRequestID: UUID?
  private var resolvedLiveAdmission: WholeShutoLiveJourneyAdmission?
  private var liveAdmissionResolutionIssueCode: String?
  private var circuitTariffTask: Task<Void, Never>?
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
  private var liveDriveSession: ShutoLiveDriveSession?
  private var liveEntryTransitionAdapter: CoreLocationEntryTransitionAdapter?
  private var liveSurfaceEgressAdapter: CoreLocationSurfaceEgressAdapter?
  private var liveNavigationCheckpoint: NavigationSessionCheckpoint?
  private var activeLiveAdmission: WholeShutoLiveJourneyAdmission?
  private var liveObservationAdapter: CoreLocationObservationAdapter?
  private var foregroundLiveLocationController: ForegroundNavigationLocationController?
  private var liveLocationSubscriptions: Set<AnyCancellable> = []
  private var runtimeCoordinate: ShutoCoordinate?
  private var runtimeFractionAlongOccurrence: Double?
  private var speechCoordinator: GuidanceSpeechCoordinator?
  private var consumedGuidancePromptIDs: Set<String> = []
  private var isStaticJunctionPreview = false
  private var selectedDestinationTitle: String?
  private var selectedSavedRouteTemplateParameters: [String: String]?
  private var trackMapCacheKey: String?
  private var trackMapCacheLayout: RouteTrackMapLayout?
  private var trackMapCacheSpans: [WholeShutoTrackMapSpan] = []
  private var liveLocationStartedAtMilliseconds: Int?
  private var lastLiveObservationAtMilliseconds: Int?
  private var liveLocationFreshnessTask: Task<Void, Never>?
  private let nowMillisecondsProvider: () -> Int

  static let liveLocationStaleAfterMilliseconds = 10_000
  static let surfaceRerouteRequiredOffRouteObservations = 2
  static let surfaceRerouteCooldownMilliseconds = 15_000
  static let surfaceRouteReroutingCode = "SURFACE_ROUTE_REROUTING"
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
      WholeShutoUserDefaultsCheckpointStore(),
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
        let settings = UserDefaultsKaidoLanguagePreferenceStore()
        return NavigationLanguageSelection(
          interfaceLocale:
            settings.interfaceLocale() ?? .simplifiedChinese,
          guidanceVoiceLocale:
            settings.guidanceVoiceLocale() ?? .japanese
        )
      }
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
    self.speechOutput = speechOutput ?? AVSpeechGuidanceOutput()
    self.liveJourneyAdmissions = liveJourneyAdmissions
    self.liveJourneyAdmissionResolver = liveJourneyAdmissionResolver
    self.liveLocationSourceEvidenceProvider =
      liveLocationSourceEvidenceProvider
    self.liveLocationSource = liveLocationSource
    self.nowMillisecondsProvider = nowMillisecondsProvider
    self.languageSelectionProvider = languageSelectionProvider
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

  /// Exact catalog routes whose reviewed junction set is complete enough to
  /// author a foreground release directly from the bundled network.
  private nonisolated static let onDemandNavigationPairingByCircuitID:
    [String: (entranceID: String, exitID: String)] = [
      "shuto.circuit.c1-outer": (
        entranceID: "shuto.ic.c1.kyoubashi",
        exitID: "shuto.ic.c1.shintomicho"
      )
    ]

  private func resolveCircuitThumbnails() {
    let planner = planner
    Task.detached(priority: .utility) { [weak self] in
      var thumbnails: [String: [CGPoint]] = [:]
      for circuit in ShutoCircuitDefinition.bundled {
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
            exitFacilityID: exit.facilityID,
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
        thumbnails[circuit.circuitID] = sampled
      }
      let resolved = thumbnails
      await MainActor.run { [weak self] in
        self?.circuitThumbnailsByID = resolved
      }
    }
  }

  deinit {
    playbackTask?.cancel()
    surfaceRouteTask?.cancel()
    surfaceRerouteTask?.cancel()
    liveAdmissionTask?.cancel()
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

  var selectedRoute: ShutoPlannedRoute? {
    selectedRecommendation?.route
  }

  static let liveNavigationReleaseRequiredCode =
    "WHOLE_SHUTO_NAVIGATION_RELEASE_REQUIRED"
  static let liveNavigationReleaseAmbiguousCode =
    "WHOLE_SHUTO_NAVIGATION_RELEASE_AMBIGUOUS"
  static let liveNavigationPreparingCode =
    "WHOLE_SHUTO_NAVIGATION_PREPARING"
  static let liveNavigationRuntimeInvalidCode =
    "WHOLE_SHUTO_NAVIGATION_RUNTIME_INVALID"

  /// A route can start only when one complete, externally constructed release
  /// admission matches the full selected RoutePlan value.
  var canStartLiveNavigation: Bool {
    matchingLiveAdmissions.count == 1
  }

  var liveNavigationBlockerCode: String? {
    let count = matchingLiveAdmissions.count
    if count == 1 { return nil }
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

  private func prepareLiveNavigationAdmission(
    for route: ShutoPlannedRoute
  ) {
    liveAdmissionTask?.cancel()
    liveAdmissionTask = nil
    liveAdmissionRequestID = nil
    resolvedLiveAdmission = nil
    liveAdmissionResolutionIssueCode = nil
    isPreparingLiveNavigation = false

    let bundled = liveJourneyAdmissions.filter {
      $0.core.selectedRoutePlan == route.routePlan
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
      let resolution = await work.value
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

  var selectedTariffBand: ShutoTariffBand? {
    if isCircuitRouteSelected, let circuitPairingBand {
      return circuitPairingBand
    }
    guard let route = selectedRoute else { return nil }
    return try? planner.tariffBand(
      entryFacilityID: route.entryFacility.facilityID,
      exitFacilityID: route.exitFacility.facilityID,
      evidence: .etcNormalCarActive
    )
  }

  var activeSurfaceInstruction: String? {
    activeSurfaceStep?.instruction
  }

  var activeSurfaceInstructionRemainingMeters: Double? {
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
    for step in steps {
      let end = cursor + step.distanceMeters
      if traveled <= end {
        return max(0, end - traveled)
      }
      cursor = end
    }
    return 0
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
    guard let route = activeSurfaceRoute,
      let steps = route.steps?.filter({
        !$0.instruction.isEmpty && $0.distanceMeters > 0
      }),
      !steps.isEmpty
    else {
      return nil
    }
    let total = steps.reduce(0) { $0 + $1.distanceMeters }
    guard total > 0 else { return steps.first }
    let traveled = min(total, max(0, progressFraction) * total)
    var cursor = 0.0
    for step in steps {
      cursor += step.distanceMeters
      if traveled <= cursor { return step }
    }
    return steps.last
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

  /// Opens an exact saved route from the parked planning state and resolves
  /// fresh provider surface legs around it. The embedded RoutePlan remains
  /// unchanged, including repeated circuit occurrences.
  @discardableResult
  func openSavedRoute(
    _ record: SavedRouteRecord,
    origin requestedOrigin: ShutoCoordinate?
  ) -> Bool {
    guard phase == .planning else {
      failureCode = "SAVED_ROUTE_OPEN_REQUIRES_PARKED_PLANNING"
      return false
    }
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

    cancelSurfaceRouteResolution()
    clearRouteChoiceEvaluation()
    clearCustomRouteSelection()
    clearCircuitRouteSelection()
    clearCircuitPlanningDraft()

    let originPlace = WholeShutoPlace(
      title: "現在地",
      coordinate: originCoordinate
    )
    let destinationPlace = WholeShutoPlace(
      title: route.exitFacility.nameJA,
      coordinate: route.exitFacility.coordinate
    )
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
      route.coordinates.last ?? route.exitFacility.coordinate,
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
      customExitFacilityID = route.exitFacility.facilityID
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
      circuitExitFacilityID = route.exitFacility.facilityID
      circuitPairingBand = try? planner.tariffBand(
        entryFacilityID: route.entryFacility.facilityID,
        exitFacilityID: route.exitFacility.facilityID,
        evidence: .etcNormalCarActive
      )
      circuitEntranceDistanceMeters = accessDistance
      circuitTariffBandsByFacilityID =
        circuitPairingBand.map {
          [route.entryFacility.facilityID: $0]
        } ?? [:]
      circuitRecommendation = recommendation
      isCircuitRouteSelected = true
    }
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

  var customEntryCandidates: [ShutoNetworkDatabase.Facility] {
    rankedCustomFacilities(
      from: origin?.coordinate,
      selectedFacilityID: customEntryFacilityID,
      isEligible: \.canEnter
    )
  }

  var customExitCandidates: [ShutoNetworkDatabase.Facility] {
    rankedCustomFacilities(
      from: destination?.coordinate,
      selectedFacilityID: customExitFacilityID,
      isEligible: \.canExit
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
    return ShutoJunctionGuidanceCompiler.compile(
      database: database,
      route: route
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
    guard let prompt = activeJunctionPrompt,
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
      $0.incomingOccurrenceID
        == surface.guidanceAnchorOccurrenceID
        && $0.outgoingOccurrenceID
          == surface.nextMovementOccurrenceID
    }
  }

  var hasConsumedActiveGuidancePrompt: Bool {
    guard let promptID = presentationProjection?.voice.promptID else {
      return false
    }
    return consumedGuidancePromptIDs.contains(promptID)
  }

  var positionState: WholeShutoPositionState {
    if isLiveDrive,
      phase != .planning,
      phase != .review,
      phase != .completed,
      liveLocationState != .available
    {
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
        return .routeInterrupted
      }
      guard matcherConfidence == .high, runtimeOccurrenceID != nil else {
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
      let egressRoute
    else {
      return nil
    }
    return accessRoute.expectedTravelTimeSeconds
      + route.distanceMeters
      / Self.simulationReferenceSpeedMetersPerSecond
      + egressRoute.expectedTravelTimeSeconds
  }

  var remainingPreviewDurationSeconds: Double? {
    guard
      let route = selectedRoute,
      let accessRoute,
      let egressRoute
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
        + egressRoute.expectedTravelTimeSeconds
    case .surfaceAccess:
      return accessRoute.expectedTravelTimeSeconds * remainingProgress
        + expresswayDuration
        + egressRoute.expectedTravelTimeSeconds
    case .entryTransition:
      return expresswayDuration
        + egressRoute.expectedTravelTimeSeconds
    case .expressway:
      return expresswayDuration * remainingProgress
        + egressRoute.expectedTravelTimeSeconds
    case .exitTransition:
      return egressRoute.expectedTravelTimeSeconds
    case .surfaceEgress:
      return egressRoute.expectedTravelTimeSeconds * remainingProgress
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
      && egressRoute != nil
      && !isUpdatingSurfaceRoute
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

  var navigationHeadingDegrees: Double? {
    switch positionState {
    case .surfacePreview, .boundaryTransition, .networkPreview:
      break
    case .unavailable, .networkDegraded, .tunnelEstimated,
      .routeInterrupted, .completed:
      return nil
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

  func usePreviewPlaces() {
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

  func selectCurrentOrigin(_ coordinate: ShutoCoordinate) {
    guard phase == .planning, usesCurrentLocationOrigin else { return }
    origin = WholeShutoPlace(
      title: "現在地",
      coordinate: coordinate
    )
  }

  func clearDestinationPreview() {
    guard phase == .planning else { return }
    destination = nil
    selectedDestinationTitle = nil
  }

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
        from: selectedRecommendation.route.exitFacility.coordinate,
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
    runtimeCoordinate = destination?.coordinate
    runtimeFractionAlongOccurrence = nil
    presentationProjection = nil
    speechStatus = .stopped
    consumedGuidancePromptIDs = []
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
        title: route.exitFacility.nameJA,
        coordinate: route.exitFacility.coordinate
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
        from: route.exitFacility.coordinate,
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

  func planJourney() {
    guard !isPlanning else { return }
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
        let routes = try planner.recommend(
          from: resolvedOrigin.coordinate,
          to: resolvedDestination.coordinate,
          preference: preference
        )
        guard !routes.isEmpty else {
          throw WholeShutoProductError.noExpresswayRoute
        }
        let evaluation = await routeChoiceEvaluator.evaluate(
          recommendations: routes,
          origin: resolvedOrigin.coordinate,
          destination: resolvedDestination.coordinate
        )
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

  var canStartCircuitJourney: Bool {
    phase == .planning
      && selectedCircuit != nil
      && circuitEntryFacilityID != nil
      && circuitExitFacilityID != nil
      && origin != nil
  }

  func selectCircuit(_ circuit: ShutoCircuitDefinition) {
    guard phase == .planning else { return }
    selectedCircuit = circuit
    circuitLaps = 1
    circuitEntranceCandidates = []
    circuitEntryFacilityID = nil
    circuitExitFacilityID = nil
    circuitPairingBand = nil
    circuitEntranceDistanceMeters = nil
    circuitTariffBandsByFacilityID = [:]
    resolveCircuitPairing(
      entranceOverride: releasedEntranceFacilityID(for: circuit)
    )
  }

  private func releasedEntranceFacilityID(
    for circuit: ShutoCircuitDefinition
  ) -> String? {
    releasedRoutePlan(for: circuit)?.entryFacilityID
  }

  private func releasedRoutePlan(
    for circuit: ShutoCircuitDefinition
  ) -> RoutePlan? {
    liveJourneyAdmissions.lazy.map(\.core.selectedRoutePlan).first {
      $0.id.hasPrefix("\(circuit.circuitID).")
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
    isResolvingCircuitPairing = false
    startsCircuitJourneyAfterPairing = false
    circuitLaps = 1
    circuitTariffBandsByFacilityID = [:]
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
    resolveCircuitPairing(entranceOverride: facilityID)
  }

  func selectCircuitLaps(_ laps: Int) {
    guard selectedCircuit?.kind == .loop, (1...3).contains(laps) else {
      return
    }
    circuitLaps = laps
  }

  func refreshCircuitEntrances() {
    guard let selectedCircuit else { return }
    resolveCircuitPairing(
      entranceOverride: circuitEntryFacilityID
        ?? releasedEntranceFacilityID(for: selectedCircuit)
    )
  }

  /// Derives the recommended entrance/exit pairing off the main actor: the
  /// nearest reachable entrance (or the driver's override), the tariff-best
  /// exit, and the per-alternative bands. Until resolution completes the
  /// start action stays unavailable and the interface shows nothing rather
  /// than inventing a pairing or an amount.
  private func resolveCircuitPairing(entranceOverride: String?) {
    circuitTariffTask?.cancel()
    guard let circuit = selectedCircuit else { return }
    isResolvingCircuitPairing = true
    let planner = planner
    let originCoordinate = origin?.coordinate
    let requestedLaps = circuitLaps
    let admissionResolver = liveJourneyAdmissionResolver
    let onDemandNavigationPairing =
      Self.onDemandNavigationPairingByCircuitID[circuit.circuitID]
    let releasedRoutePlan = releasedRoutePlan(for: circuit)
    let releasedEntranceID = releasedRoutePlan?.entryFacilityID
    let releasedEntrance = releasedEntranceID.flatMap { facilityID in
      database.directionalFacilities.first {
        $0.facilityID == facilityID
      }
    }
    circuitTariffTask = Task.detached(priority: .userInitiated) {
      [weak self] in
      let ranked = planner.circuitEntranceCandidates(
        for: circuit,
        origin: originCoordinate
      )
      // A released expressway-only route remains plannable before the driver
      // reaches Tokyo. Its ordinary-road approach is still preview-only, and
      // live matching cannot enter the route before the released ramp.
      let pinnedEntrance =
        entranceOverride == releasedEntranceID
        ? releasedEntrance : nil
      let candidates =
        pinnedEntrance.map { entrance in
          [entrance]
            + ranked.filter {
              $0.facilityID != entrance.facilityID
            }
        } ?? ranked
      let overriddenEntranceID =
        candidates.contains(where: { $0.facilityID == entranceOverride })
        ? entranceOverride
        : nil
      let navigationReadyPairing =
        Self.navigationReadyPairing(
          circuit: circuit,
          requestedLaps: requestedLaps,
          originCoordinate: originCoordinate,
          candidates: candidates,
          entranceOverride: overriddenEntranceID,
          onDemandPairing: onDemandNavigationPairing,
          planner: planner,
          admissionResolver: admissionResolver
        )
      let entranceID =
        overriddenEntranceID
        ?? navigationReadyPairing?.entrance.facilityID
        ?? candidates.first?.facilityID
      var pairing = navigationReadyPairing
      var releasedPairingBand: ShutoTariffBand?
      if let entranceID {
        let isReleasedEntrance = entranceID == pinnedEntrance?.facilityID
        if pairing == nil {
          pairing = try? planner.recommendedCircuitPairing(
            for: circuit,
            entranceFacilityID: entranceID,
            origin: isReleasedEntrance ? nil : originCoordinate,
            evidence: .etcNormalCarActive
          )
        }
        if isReleasedEntrance, let releasedRoutePlan {
          releasedPairingBand = try? planner.tariffBand(
            entryFacilityID: releasedRoutePlan.entryFacilityID,
            exitFacilityID: releasedRoutePlan.exitFacilityID,
            evidence: .etcNormalCarActive
          )
        }
      }
      var bands: [String: ShutoTariffBand] = [:]
      for candidate in candidates.prefix(3) {
        if Task.isCancelled { return }
        if candidate.facilityID == pairing?.entrance.facilityID {
          bands[candidate.facilityID] =
            releasedPairingBand ?? pairing?.tariffBand
          continue
        }
        bands[candidate.facilityID] =
          (try? planner.recommendedCircuitPairing(
            for: circuit,
            entranceFacilityID: candidate.facilityID,
            origin: originCoordinate,
            evidence: .etcNormalCarActive
          ))?.tariffBand
      }
      let resolvedPairing = pairing
      let resolvedReleasedRoutePlan =
        pairing?.entrance.facilityID == releasedRoutePlan?.entryFacilityID
        ? releasedRoutePlan : nil
      let resolvedBands = bands.compactMapValues { $0 }
      let resolvedCandidates = candidates
      await MainActor.run { [weak self] in
        guard let self, !Task.isCancelled,
          self.selectedCircuit?.circuitID == circuit.circuitID
        else { return }
        self.circuitEntranceCandidates = resolvedCandidates
        self.circuitEntryFacilityID =
          resolvedPairing?.entrance.facilityID
        self.circuitExitFacilityID =
          resolvedReleasedRoutePlan?.exitFacilityID
          ?? resolvedPairing?.exit.facilityID
        self.circuitPairingBand =
          resolvedReleasedRoutePlan == nil
          ? resolvedPairing?.tariffBand : releasedPairingBand
        self.circuitEntranceDistanceMeters =
          resolvedPairing?.entranceDistanceMeters
        self.circuitTariffBandsByFacilityID = resolvedBands
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

  private nonisolated static func navigationReadyPairing(
    circuit: ShutoCircuitDefinition,
    requestedLaps: Int,
    originCoordinate: ShutoCoordinate?,
    candidates: [ShutoNetworkDatabase.Facility],
    entranceOverride: String?,
    onDemandPairing: (entranceID: String, exitID: String)?,
    planner: ShutoRoutePlanner,
    admissionResolver: WholeShutoLiveJourneyAdmissionResolver?
  ) -> ShutoCircuitPairing? {
    guard entranceOverride == nil,
      let onDemandPairing,
      let admissionResolver,
      let entrance = candidates.first(where: {
        $0.facilityID == onDemandPairing.entranceID
      }),
      let exits = try? planner.circuitExitCandidates(
        for: circuit,
        afterEntering: entrance.facilityID
      ),
      let exit = exits.first(where: {
        $0.facilityID == onDemandPairing.exitID
      }),
      let route = try? planner.planCircuit(
        circuit: circuit,
        entryFacilityID: entrance.facilityID,
        exitFacilityID: exit.facilityID,
        laps: requestedLaps
      ),
      case .available = admissionResolver(route)
    else { return nil }
    return ShutoCircuitPairing(
      entrance: entrance,
      exit: exit,
      tariffBand: try? planner.tariffBand(
        entryFacilityID: entrance.facilityID,
        exitFacilityID: exit.facilityID,
        evidence: .etcNormalCarActive
      ),
      entranceDistanceMeters: originCoordinate.map {
        distance($0, entrance.coordinate)
      }
    )
  }

  /// Starts the circuit journey as a round trip: the origin doubles as the
  /// destination, the exit is the derived pairing's exit, and the usual
  /// fail-closed surface-leg flow follows.
  @discardableResult
  func startCircuitJourney() -> Bool {
    guard
      phase == .planning,
      let circuit = selectedCircuit,
      let entryFacilityID = circuitEntryFacilityID,
      let exitFacilityID = circuitExitFacilityID,
      let origin
    else {
      return false
    }
    do {
      let route = try planner.planCircuit(
        circuit: circuit,
        entryFacilityID: entryFacilityID,
        exitFacilityID: exitFacilityID,
        laps: circuit.kind == .loop ? circuitLaps : 1
      )
      cancelSurfaceRouteResolution()
      clearRouteChoiceEvaluation()
      clearCustomRouteSelection()
      recommendations = []
      selectedRecommendationIndex = 0
      let roundTripDestination = origin
      destination = roundTripDestination
      destinationQuery = roundTripDestination.title
      selectedDestinationTitle = roundTripDestination.title
      let accessDistance = Self.distance(
        origin.coordinate,
        route.coordinates.first ?? route.entryFacility.coordinate
      )
      let egressDistance = Self.distance(
        route.coordinates.last ?? route.exitFacility.coordinate,
        roundTripDestination.coordinate
      )
      let recommendation = ShutoRouteRecommendation(
        route: route,
        surfaceAccessDistanceMeters: accessDistance,
        surfaceEgressDistanceMeters: egressDistance,
        totalScoreMeters:
          route.distanceMeters + accessDistance + egressDistance
      )
      circuitRecommendation = recommendation
      isCircuitRouteSelected = true
      preference = route.preference
      phase = .review
      failureCode = nil
      resolveSurfaceRoutes(
        for: recommendation,
        origin: origin,
        destination: roundTripDestination
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
  }

  func prepareCustomRouteDraft() {
    switch phase {
    case .review:
      guard let route = selectedRoute else { return }
      let draft = customRecommendation?.route ?? route
      customEntryFacilityID = draft.entryFacility.facilityID
      customExitFacilityID = draft.exitFacility.facilityID
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
      let exit = nearest(
        facilities.filter { $0.canExit && $0.nameJA != entry.nameJA }
      )
      customEntryFacilityID = entry.facilityID
      customExitFacilityID = exit?.facilityID
      customPreference = .recommended
      refreshCustomRouteDraft()
    default:
      return
    }
  }

  func selectCustomEntry(facilityID: String) {
    guard facility(id: facilityID)?.canEnter == true else { return }
    customEntryFacilityID = facilityID
    refreshCustomRouteDraft()
  }

  func selectCustomExit(facilityID: String) {
    guard facility(id: facilityID)?.canExit == true else { return }
    customExitFacilityID = facilityID
    refreshCustomRouteDraft()
  }

  func selectCustomPreference(_ preference: ShutoRoutePreference) {
    customPreference = preference
    refreshCustomRouteDraft()
  }

  @discardableResult
  func applyCustomRoute() -> Bool {
    guard let origin, let route = customDraftRoute else { return false }
    let destination: WholeShutoPlace
    switch phase {
    case .review:
      guard let existing = self.destination else { return false }
      destination = existing
    case .planning:
      // Exact custom routes started from the home catalog are round
      // trips, matching the circuit journeys they sit beside.
      destination = origin
      self.destination = destination
      destinationQuery = destination.title
      selectedDestinationTitle = destination.title
      cancelSurfaceRouteResolution()
      clearRouteChoiceEvaluation()
      recommendations = []
      selectedRecommendationIndex = 0
      phase = .review
    default:
      return false
    }
    let accessDistance = Self.distance(
      origin.coordinate,
      route.coordinates.first ?? route.entryFacility.coordinate
    )
    let egressDistance = Self.distance(
      route.coordinates.last ?? route.exitFacility.coordinate,
      destination.coordinate
    )
    let recommendation = ShutoRouteRecommendation(
      route: route,
      surfaceAccessDistanceMeters: accessDistance,
      surfaceEgressDistanceMeters: egressDistance,
      totalScoreMeters: route.distanceMeters + accessDistance + egressDistance
    )
    customRecommendation = recommendation
    isCustomRouteSelected = true
    clearCircuitRouteSelection()
    preference = route.preference
    failureCode = nil
    resolveSurfaceRoutes(
      for: recommendation,
      origin: origin,
      destination: destination
    )
    return true
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
      ?? recommendation.route.exitFacility.coordinate
    let exitFallback = recommendation.route.exitFacility.coordinate
    let resolver = surfaceRouteResolver
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
        return await resolver.route(
          from: fallback.from,
          to: fallback.to
        )
      }
      async let access = leg(
        from: origin.coordinate,
        to: entry,
        fallback: (origin.coordinate, entryFallback)
      )
      async let egress = leg(
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
      self.isUpdatingSurfaceRoute = false
      self.failureCode =
        resolvedRoutes.0 == nil || resolvedRoutes.1 == nil
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
          sampleFractions: [0.15, 0.5, 0.85],
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
    runtimeCoordinate = nil
    runtimeFractionAlongOccurrence = nil
    presentationProjection = nil
    consumedGuidancePromptIDs = []
    isStaticJunctionPreview = false
    restoredFromCheckpoint = false
    mapMode = .geographic
    persistCheckpoint()
    if autoplay {
      startPlaybackLoop()
    }
  }

  /// Starts only after one exact release-bound journey has constructed every
  /// actor and adapter. Core Location is attached last.
  @discardableResult
  func startLiveJourney() async -> Bool {
    guard phase == .review, let route = selectedRoute else { return false }
    let providerAccessRoute = accessRoute
    let providerEgressRoute = egressRoute
    liveLocationFreshnessTask?.cancel()
    liveDriveSession = nil
    liveEntryTransitionAdapter = nil
    liveSurfaceEgressAdapter = nil
    liveNavigationCheckpoint = nil
    activeLiveAdmission = nil
    liveObservationAdapter = nil
    foregroundLiveLocationController = nil
    liveLocationSubscriptions.removeAll()
    isLiveDrive = false
    liveLocationState = .inactive
    liveLocationIssueCode = nil
    liveLocationStartedAtMilliseconds = nil
    lastLiveObservationAtMilliseconds = nil
    cancelSurfaceReroute()
    guard matchingLiveAdmissions.count == 1,
      let admission = matchingLiveAdmissions.first
    else {
      failureCode = liveNavigationBlockerCode
      return false
    }

    do {
      let assets = try ShutoPlannedRouteRuntimeCompiler.compile(
        database: database,
        route: route
      )
      guard assets.routePlan == admission.core.selectedRoutePlan else {
        failureCode = Self.liveNavigationRuntimeInvalidCode
        return false
      }
      let runtime = try admission.core.makeRuntime()
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
      runtimeCoordinate = nil
      runtimeFractionAlongOccurrence = nil
      presentationProjection = nil
      consumedGuidancePromptIDs = []
      isStaticJunctionPreview = false
      liveLocationState = .acquiring
      liveLocationIssueCode = nil
      liveLocationStartedAtMilliseconds = nowMillisecondsProvider()
      lastLiveObservationAtMilliseconds = nil
      failureCode = nil

      let initialSnapshot = await session.start()
      if phase == .surfaceAccess {
        runtimeJourneyPhase = initialSnapshot.journeyPhase
        runtimeRecoveryStatus = initialSnapshot.recovery.status
      } else {
        applyLiveActorSnapshot(initialSnapshot)
      }
      scheduleLiveLocationFreshnessCheck()
      persistCheckpoint()
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
    let observation = envelope.observation
    let coordinate = ShutoCoordinate(
      latitude: observation.coordinate.latitude,
      longitude: observation.coordinate.longitude
    )
    runtimeCoordinate = coordinate
    lastLiveObservationAtMilliseconds = observation.receivedAtMilliseconds
    liveLocationStartedAtMilliseconds =
      liveLocationStartedAtMilliseconds
      ?? observation.receivedAtMilliseconds
    liveLocationIssueCode = nil
    liveLocationState = .available
    scheduleLiveLocationFreshnessCheck()

    do {
      switch phase {
      case .surfaceAccess:
        updateLiveSurfaceProgress(
          coordinate: coordinate,
          horizontalAccuracyMeters:
            observation.horizontalAccuracyMeters,
          route: accessRoute,
          completesJourney: false
        )
        guard
          isNearSurfaceRouteEnd(
            coordinate: coordinate,
            horizontalAccuracyMeters:
              observation.horizontalAccuracyMeters,
            route: accessRoute,
            thresholdMeters: 350
          )
        else {
          break
        }
        guard var adapter = liveEntryTransitionAdapter else {
          throw WholeShutoProductError.noExpresswayRoute
        }
        let evidence = try adapter.adapt(envelope)
        liveEntryTransitionAdapter = adapter
        let update = try await session.observeEntryTransitionEvidence(
          evidence
        )
        matcherConfidence = evidence.confidence
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
        if let rejection = update.rejectionReason {
          liveLocationState = .degraded
          liveLocationIssueCode = rejection.rawValue
        }
      case .entryTransition:
        guard var adapter = liveEntryTransitionAdapter else {
          throw WholeShutoProductError.noExpresswayRoute
        }
        let evidence = try adapter.adapt(envelope)
        liveEntryTransitionAdapter = adapter
        let update = try await session.observeEntryTransitionEvidence(
          evidence
        )
        matcherConfidence = evidence.confidence
        applyLiveActorSnapshot(update.navigationSnapshot)
        if let rejection = update.rejectionReason {
          liveLocationState = .degraded
          liveLocationIssueCode = rejection.rawValue
        }
      case .expressway:
        let update = try await session.observe(observation)
        applyNavigationUpdate(update)
        liveLocationState =
          update.matcherEstimate.confidence == .high
          ? .available : .degraded
        if update.matcherEstimate.confidence != .high {
          liveLocationIssueCode =
            "LIVE_MATCHER_CONFIDENCE_"
            + update.matcherEstimate.confidence.rawValue
        }
        if update.navigationSnapshot.journeyPhase == .strictRoute,
          update.navigationSnapshot.currentOccurrenceID
            == selectedRoute?.routePlan.occurrences.last?.id,
          runtimeOccurrenceID
            == selectedRoute?.routePlan.occurrences.last?.id,
          progressFraction >= 0.999
        {
          let snapshot = await session.finishDrive()
          applyLiveActorSnapshot(snapshot)
          if liveSurfaceEgressAdapter == nil {
            if egressRoute != nil {
              phase = .surfaceEgress
              progressFraction = 0
              presentationProjection = nil
            } else {
              applyLiveActorSnapshot(
                await session.completeAtExitHandoff()
              )
            }
          }
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
          applyLiveActorSnapshot(
            await session.completeAtExitHandoff()
          )
        }
      case .planning, .review, .completed:
        return
      }
      if phase != .completed {
        await captureAndPersistLiveCheckpoint(from: session)
      }
    } catch {
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
      if liveLocationState != .resumeRequired {
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
      liveLocationState = .resumeRequired
      liveLocationIssueCode = "LIVE_RESUME_REQUIRED"
      liveLocationFreshnessTask?.cancel()
      liveLocationFreshnessTask = nil
    case .permissionDenied:
      liveLocationState = .permissionDenied
      liveLocationIssueCode = "CORE_LOCATION_PERMISSION_DENIED"
      isPlaying = false
      matcherConfidence = .low
      speechCoordinator?.stop()
      liveLocationFreshnessTask?.cancel()
      liveLocationFreshnessTask = nil
      persistCheckpoint()
    case .releaseBlocked(let reason):
      liveLocationState = .failed
      liveLocationIssueCode = reason.rawValue
      failureCode = Self.liveNavigationRuntimeInvalidCode
      isPlaying = false
    case .runtimeUnavailable:
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
  func resumeLiveJourney() -> Bool {
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
    matcherConfidence = .low
    scheduleLiveLocationFreshnessCheck()
    speechCoordinator?.resume()
    foregroundLiveLocationController?.refreshRuntimeAvailability()
    foregroundLiveLocationController?.start()
    persistCheckpoint()
    return true
  }

  private func applyLiveActorSnapshot(
    _ snapshot: NavigationSnapshot
  ) {
    runtimeJourneyPhase = snapshot.journeyPhase
    runtimeRecoveryStatus = snapshot.recovery.status
    switch snapshot.journeyPhase {
    case .planning, .approachToEntry:
      break
    case .entryTransition:
      if phase == .surfaceAccess {
        cancelSurfaceReroute()
        phase = .entryTransition
        progressFraction = 0
      }
    case .strictRoute:
      if phase == .surfaceAccess || phase == .entryTransition {
        cancelSurfaceReroute()
        phase = .expressway
        progressFraction = 0
      }
    case .routeRecovery:
      phase = .expressway
      isPlaying = false
    case .exitTransition:
      guard snapshot.egress.status == .active else { return }
      phase = .exitTransition
      progressFraction = 0
      presentationProjection = nil
    case .surfaceEgress:
      phase = .surfaceEgress
      progressFraction = 0
      presentationProjection = nil
    case .completed:
      completeLiveJourney()
    }
  }

  @discardableResult
  private func updateLiveSurfaceProgress(
    coordinate: ShutoCoordinate,
    horizontalAccuracyMeters: Double,
    route: WholeShutoSurfaceRoute?,
    completesJourney: Bool
  ) -> Bool {
    guard let route,
      let measurement = Self.surfaceRouteMeasurement(
        coordinate,
        along: route.coordinates
      )
    else {
      recordSurfaceOffRouteObservation(
        coordinate: coordinate,
        observedAtMilliseconds:
          lastLiveObservationAtMilliseconds ?? nowMillisecondsProvider()
      )
      liveLocationState = .degraded
      if !isReroutingSurfaceRoute {
        liveLocationIssueCode = "SURFACE_ROUTE_GEOMETRY_UNAVAILABLE"
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
      recordSurfaceOffRouteObservation(
        coordinate: coordinate,
        observedAtMilliseconds:
          lastLiveObservationAtMilliseconds ?? nowMillisecondsProvider()
      )
      liveLocationState = .degraded
      if !isReroutingSurfaceRoute {
        liveLocationIssueCode = "SURFACE_ROUTE_OFF_ROUTE"
      }
      return false
    }
    consecutiveSurfaceOffRouteObservations = 0
    progressFraction = max(
      progressFraction,
      measurement.fractionAlongRoute
    )
    guard completesJourney,
      progressFraction >= 0.995,
      let destination = route.coordinates.last,
      Self.distance(coordinate, destination)
        <= max(30, horizontalAccuracyMeters * 2)
    else {
      persistCheckpoint()
      return false
    }
    return true
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

  private func completeLiveJourney() {
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

  func advanceSimulationForTesting() async {
    guard phase != .planning, phase != .review, phase != .completed else {
      return
    }
    if phase == .entryTransition || phase == .expressway {
      speechCoordinator?.resume()
      guard await restoreObservationReplayIfNeeded() else { return }
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
    stopForegroundLiveLocationController()
    invalidatePlaybackTask()
    cancelSurfaceRouteResolution()
    cancelSurfaceReroute()
    liveAdmissionTask?.cancel()
    liveAdmissionTask = nil
    liveAdmissionRequestID = nil
    resolvedLiveAdmission = nil
    liveAdmissionResolutionIssueCode = nil
    isPreparingLiveNavigation = false
    speechCoordinator?.stop()
    speechCoordinator = nil
    phase = .planning
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
    runtimeCoordinate = nil
    runtimeFractionAlongOccurrence = nil
    presentationProjection = nil
    speechStatus = .idle
    consumedGuidancePromptIDs = []
    runtimeAssets = nil
    driveSimulator = nil
    liveDriveSession = nil
    liveEntryTransitionAdapter = nil
    liveSurfaceEgressAdapter = nil
    liveNavigationCheckpoint = nil
    activeLiveAdmission = nil
    liveObservationAdapter = nil
    isLiveDrive = false
    liveLocationState = .inactive
    liveLocationIssueCode = nil
    liveLocationStartedAtMilliseconds = nil
    lastLiveObservationAtMilliseconds = nil
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
              from: liveDriveSession
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
            from: liveDriveSession
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

  private func recordSurfaceOffRouteObservation(
    coordinate: ShutoCoordinate,
    observedAtMilliseconds: Int
  ) {
    guard
      isLiveDrive,
      isPlaying,
      phase == .surfaceAccess || phase == .surfaceEgress
    else {
      return
    }
    consecutiveSurfaceOffRouteObservations += 1
    guard
      consecutiveSurfaceOffRouteObservations
        >= Self.surfaceRerouteRequiredOffRouteObservations,
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
    attemptedAtMilliseconds: Int
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
    surfaceRerouteTask = Task { [weak self] in
      var resolved = await resolver.route(
        from: coordinate,
        to: destination
      )
      if resolved == nil,
        !Task.isCancelled,
        let fallbackDestination,
        fallbackDestination != destination
      {
        resolved = await resolver.route(
          from: coordinate,
          to: fallbackDestination
        )
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
      self.liveLocationState = .available
      self.liveLocationIssueCode = nil
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
    guard progressFraction >= 1 else {
      persistCheckpoint()
      return
    }
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
  private func applyNavigationUpdate(_ update: NavigationSessionUpdate) {
    matcherConfidence = update.matcherEstimate.confidence
    runtimeJourneyPhase = update.navigationSnapshot.journeyPhase
    runtimeRecoveryStatus = update.navigationSnapshot.recovery.status
    publishPresentationAndScheduleSpeech(from: update)
    if update.navigationSnapshot.journeyPhase == .routeRecovery {
      isPlaying = false
      invalidatePlaybackTask()
      return
    }
    if phase == .entryTransition {
      guard update.navigationSnapshot.journeyPhase == .strictRoute else {
        persistCheckpoint()
        return
      }
      phase = .expressway
      progressFraction = 0
    }
    guard phase == .expressway else { return }
    guard
      let progress = runtimeAssets?.project(
        update.matcherEstimate
      ),
      progress.routeProgressFraction >= progressFraction
    else {
      return
    }
    progressFraction = progress.routeProgressFraction
    runtimeOccurrenceID = progress.occurrenceID
    runtimeFractionAlongOccurrence =
      progress.fractionAlongOccurrence
    runtimeCoordinate = progress.coordinate
    persistCheckpoint()
  }

  private func configureSpeech(for routePlanID: String) throws {
    speechCoordinator?.stop()
    let coordinator = try GuidanceSpeechCoordinator(
      expectedRoutePlanID: routePlanID,
      output: speechOutput
    )
    coordinator.statusDidChange = { [weak self] status in
      self?.speechStatus = status
    }
    speechCoordinator = coordinator
    speechStatus = .idle
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
      let projection = try NavigationPresentationProjector.project(
        NavigationPresentationRequest(
          snapshot: update.navigationSnapshot,
          networkSnapshotID: database.networkSnapshotID,
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
      guard let emission = update.guidancePromptEmission else {
        return
      }
      guard
        consumedGuidancePromptIDs.insert(emission.promptID).inserted
      else {
        speechStatus = .suppressed(.duplicate)
        return
      }
      guard let speechCoordinator else {
        speechStatus = .invalidProjection
        return
      }
      speechStatus = speechCoordinator.submit(projection)
    } catch {
      presentationProjection = nil
      if update.guidancePromptEmission != nil {
        speechStatus = .invalidProjection
      }
    }
  }

  private func completeExpresswayObservationReplay() {
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
      rejectCheckpoint(Self.checkpointLoadFailedCode)
      return
    }
    guard
      checkpoint.schemaVersion
        == WholeShutoJourneyCheckpoint.currentSchemaVersion
    else {
      rejectCheckpoint(Self.checkpointSchemaUnsupportedCode)
      return
    }
    guard checkpoint.networkSnapshotID == database.networkSnapshotID else {
      rejectCheckpoint(Self.checkpointNetworkMismatchCode)
      return
    }
    guard checkpoint.phase != .planning,
      checkpoint.phase != .completed
    else {
      rejectCheckpoint(Self.checkpointPhaseInvalidCode)
      return
    }
    var restoredCircuit: ShutoCircuitDefinition?
    let route: ShutoPlannedRoute
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
          circuit: circuit,
          entryFacilityID: checkpoint.entryFacilityID,
          exitFacilityID: checkpoint.exitFacilityID,
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
          routePlan: checkpoint.routePlan,
          preference: checkpoint.preference
        )
      }
      guard route.routePlan == checkpoint.routePlan else {
        throw WholeShutoSavedRouteResolutionError.invalidRoutePlan
      }
    } catch {
      rejectCheckpoint(Self.checkpointRouteInvalidCode)
      return
    }
    let accessDistance = checkpoint.accessRoute?.distanceMeters ?? 0
    let egressDistance = checkpoint.egressRoute?.distanceMeters ?? 0
    originQuery = checkpoint.originQuery
    destinationQuery = checkpoint.destinationQuery
    origin = checkpoint.origin
    destination = checkpoint.destination
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
      customExitFacilityID = route.exitFacility.facilityID
      customPreference = route.preference
      customDraftRoute = route
    case .circuit:
      recommendations = []
      clearCustomRouteSelection()
      selectedCircuit = restoredCircuit
      circuitLaps = checkpoint.circuitLaps ?? 1
      circuitEntryFacilityID = route.entryFacility.facilityID
      circuitExitFacilityID = route.exitFacility.facilityID
      circuitPairingBand = try? planner.tariffBand(
        entryFacilityID: route.entryFacility.facilityID,
        exitFacilityID: route.exitFacility.facilityID,
        evidence: .etcNormalCarActive
      )
      circuitRecommendation = restoredRecommendation
      isCircuitRouteSelected = true
    case .recommended:
      recommendations = [restoredRecommendation]
      clearCustomRouteSelection()
    }
    selectedRecommendationIndex = 0
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
      phase = .review
      progressFraction = 0
      mapMode = .network
      runtimeAssets = nil
      driveSimulator = nil
      liveDriveSession = nil
      liveEntryTransitionAdapter = nil
      liveSurfaceEgressAdapter = nil
      liveNavigationCheckpoint = nil
      isLiveDrive = false
      liveLocationState = .inactive
      liveLocationIssueCode = Self.liveNavigationReleaseRequiredCode
      matcherConfidence = nil
      runtimeOccurrenceID = nil
      runtimeJourneyPhase = nil
      runtimeRecoveryStatus = nil
      runtimeCoordinate = nil
      runtimeFractionAlongOccurrence = nil
      failureCode = Self.liveNavigationReleaseRequiredCode
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
          sampleFractions: [0.15, 0.5, 0.85],
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
      runtimeCoordinate = nil
      runtimeFractionAlongOccurrence = nil
      failureCode = Self.checkpointRuntimeInvalidCode
      rejectCheckpoint(Self.checkpointRuntimeInvalidCode)
    }
  }

  private func persistCheckpoint() {
    guard let origin, let destination, let route = selectedRoute,
      phase != .planning, phase != .completed
    else {
      return
    }
    let checkpoint = WholeShutoJourneyCheckpoint(
      schemaVersion: WholeShutoJourneyCheckpoint.currentSchemaVersion,
      networkSnapshotID: database.networkSnapshotID,
      originQuery: originQuery,
      destinationQuery: destinationQuery,
      origin: origin,
      destination: destination,
      entryFacilityID: route.entryFacility.facilityID,
      exitFacilityID: route.exitFacility.facilityID,
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
        isLiveDrive ? liveNavigationCheckpoint : nil
    )
    guard let checkpointStore else { return }
    do {
      try checkpointStore.save(checkpoint)
      checkpointIssueCode = nil
    } catch {
      rejectCheckpoint(Self.checkpointSaveFailedCode)
    }
  }

  private func rejectCheckpoint(_ issueCode: String) {
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

  private func removeCheckpoint() {
    guard let checkpointStore else { return }
    do {
      try checkpointStore.remove()
      checkpointIssueCode = nil
    } catch {
      checkpointIssueCode = Self.checkpointRemoveFailedCode
    }
  }

  private func captureAndPersistLiveCheckpoint(
    from session: ShutoLiveDriveSession
  ) async {
    do {
      liveNavigationCheckpoint = try await session.makeCheckpoint(
        savedAtMilliseconds: nowMillisecondsProvider()
      )
      persistCheckpoint()
    } catch {
      failureCode = Self.checkpointRuntimeInvalidCode
      checkpointIssueCode = Self.checkpointRuntimeInvalidCode
    }
  }

  private func scheduleLiveLocationFreshnessCheck() {
    liveLocationFreshnessTask?.cancel()
    guard isLiveDrive, isPlaying else { return }
    liveLocationFreshnessTask = Task { [weak self] in
      try? await Task.sleep(
        for: .milliseconds(Self.liveLocationStaleAfterMilliseconds)
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
      lastLiveObservationAtMilliseconds
      ?? liveLocationStartedAtMilliseconds
    guard let reference,
      nowMilliseconds - reference
        >= Self.liveLocationStaleAfterMilliseconds
    else {
      scheduleLiveLocationFreshnessCheck()
      return
    }
    liveLocationState = .stale
    liveLocationIssueCode = "CORE_LOCATION_NO_RECENT_FIX"
    matcherConfidence = .low
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

  private func resolveOrigin() async throws -> WholeShutoPlace {
    if Self.isCurrentLocationQuery(originQuery) {
      if let origin {
        return origin
      }
      do {
        let coordinate = try await locationProvider.currentCoordinate()
        return WholeShutoPlace(
          title: "現在地",
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
    customDraftRoute = try? planner.plan(
      entryFacilityID: entryFacilityID,
      exitFacilityID: exitFacilityID,
      preference: customPreference
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
          circuit: resolvedCircuit,
          entryFacilityID: routePlan.entryFacilityID,
          exitFacilityID: routePlan.exitFacilityID,
          laps: laps,
          preference: routePreference
        )
        guard planned.routePlan == routePlan else {
          throw WholeShutoSavedRouteResolutionError.invalidTemplateMetadata
        }
        route = planned
        circuit = resolvedCircuit
        circuitLaps = laps
      case .custom, .recommended:
        guard templateParameters["circuit_id"] == nil,
          templateParameters["laps"] == nil
        else {
          throw WholeShutoSavedRouteResolutionError.invalidTemplateMetadata
        }
        route = try planner.restore(
          routePlan: routePlan,
          preference: routePreference
        )
        circuit = nil
        circuitLaps = nil
      }
      _ = try ShutoPlannedRouteRuntimeCompiler.compile(
        database: database,
        route: route
      )
      return WholeShutoResolvedSavedRoute(
        route: route,
        selectionSource: selectionSource,
        circuit: circuit,
        circuitLaps: circuitLaps,
        templateParameters: templateParameters
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
      .filter { $0[keyPath: isEligible] }
      .sorted {
        let leftDistance = Self.distance(coordinate, $0.coordinate)
        let rightDistance = Self.distance(coordinate, $1.coordinate)
        if leftDistance != rightDistance {
          return leftDistance < rightDistance
        }
        return $0.facilityID < $1.facilityID
      }
    var result = Array(ranked.prefix(8))
    if let selectedFacilityID,
      !result.contains(where: { $0.facilityID == selectedFacilityID }),
      let selected = ranked.first(where: {
        $0.facilityID == selectedFacilityID
      })
    {
      result.append(selected)
    }
    return result
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
    interpolatedCoordinate(
      in: coordinates,
      fraction: min(1, max(0, fraction) + 0.025)
    )
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
