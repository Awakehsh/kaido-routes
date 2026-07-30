import Combine
import CoreLocation
import Foundation
import KaidoAppleAdapters
import KaidoDomain
import KaidoNavigation
import KaidoPresentation
import KaidoRouting
@preconcurrency import MapKit

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

enum WholeShutoMapMode:
  String, CaseIterable, Codable, Equatable, Sendable
{
  case geographic = "GEOGRAPHIC"
  case network = "NETWORK"
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
  static let currentSchemaVersion = "1.3"

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
  let phase: WholeShutoJourneyPhase
  let progressFraction: Double
  let runtimeOccurrenceID: String?
  let runtimeFractionAlongOccurrence: Double?
  let consumedGuidancePromptIDs: [String]?
  let mapMode: WholeShutoMapMode
  let accessRoute: WholeShutoSurfaceRoute?
  let egressRoute: WholeShutoSurfaceRoute?
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

enum WholeShutoNetworkCatalog {
  static func bundled(bundle: Bundle = .main) throws -> ShutoNetworkDatabase {
    guard
      let url = bundle.url(
        forResource: "shuto-whole-network-20260728",
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
  @Published private(set) var phase: WholeShutoJourneyPhase = .planning
  @Published private(set) var origin: WholeShutoPlace?
  @Published private(set) var destination: WholeShutoPlace?
  @Published private(set) var recommendations: [ShutoRouteRecommendation] = []
  @Published private(set) var selectedRecommendationIndex = 0
  @Published private(set) var accessRoute: WholeShutoSurfaceRoute?
  @Published private(set) var egressRoute: WholeShutoSurfaceRoute?
  @Published private(set) var progressFraction = 0.0
  @Published private(set) var isPlaying = false
  @Published private(set) var failureCode: String?
  @Published private(set) var isPlanning = false
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
  private let speechOutput: any GuidanceSpeechOutput
  private let languageSelectionProvider: () -> NavigationLanguageSelection
  private let waysByID: [Int64: ShutoNetworkDatabase.Way]
  private var playbackTask: Task<Void, Never>?
  private var runtimeAssets: ShutoPlannedRouteRuntimeAssets?
  private var driveSimulator: NavigationDriveSimulator?
  private var runtimeCoordinate: ShutoCoordinate?
  private var runtimeFractionAlongOccurrence: Double?
  private var speechCoordinator: GuidanceSpeechCoordinator?
  private var consumedGuidancePromptIDs: Set<String> = []
  private var isStaticJunctionPreview = false

  init(
    database: ShutoNetworkDatabase? = nil,
    originQuery: String = "",
    destinationQuery: String = "",
    locationProvider: any C2NavigationCurrentLocationProviding =
      C2CoreLocationProvider(),
    placeResolver: any C2NavigationPlaceResolving =
      C2MapKitPlaceResolver(),
    checkpointStore: (any WholeShutoJourneyCheckpointStoring)? =
      WholeShutoUserDefaultsCheckpointStore(),
    speechOutput: (any GuidanceSpeechOutput)? = nil,
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
    self.checkpointStore = checkpointStore
    self.speechOutput = speechOutput ?? AVSpeechGuidanceOutput()
    self.languageSelectionProvider = languageSelectionProvider
    waysByID = Dictionary(
      uniqueKeysWithValues: resolvedDatabase.ways.map {
        ($0.wayID, $0)
      }
    )
    restoreCheckpointIfAvailable()
  }

  deinit {
    playbackTask?.cancel()
  }

  var selectedRecommendation: ShutoRouteRecommendation? {
    recommendations.indices.contains(selectedRecommendationIndex)
      ? recommendations[selectedRecommendationIndex]
      : nil
  }

  var selectedRoute: ShutoPlannedRoute? {
    selectedRecommendation?.route
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

  var activeJunctionPrompt: WholeShutoJunctionPrompt? {
    guard phase == .expressway else { return nil }
    if isStaticJunctionPreview {
      return junctionPrompts.first
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
      return interpolatedCoordinate(
        in: accessRoute?.coordinates ?? [],
        fraction: progressFraction
      )
    case .entryTransition:
      return selectedRoute?.coordinates.first
    case .expressway:
      return runtimeCoordinate
        ?? interpolatedCoordinate(
          in: selectedRoute?.coordinates ?? [],
          fraction: progressFraction
        )
    case .exitTransition:
      return selectedRoute?.coordinates.last
    case .surfaceEgress:
      return interpolatedCoordinate(
        in: egressRoute?.coordinates ?? [],
        fraction: progressFraction
      )
    case .completed:
      return destination?.coordinate
    }
  }

  func usePreviewPlaces() {
    origin = Self.previewOrigin
    destination = Self.previewDestination
    originQuery = Self.previewOrigin.title
    destinationQuery = Self.previewDestination.title
  }

  func preparePreviewJourney(startsNavigation: Bool = false) {
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
      persistCheckpoint()
      if startsNavigation {
        startNavigationSimulation()
      }
    } catch {
      failureCode = Self.failureCode(error)
    }
  }

  func prepareJunctionPreview(startsNavigation: Bool = false) {
    do {
      let route = try planner.plan(
        entryFacilityID: "shuto.ic.b.rinkaihukutoshin",
        exitFacilityID: "shuto.ic.c2.hatsudaiminami"
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
      guard let prompt = junctionPrompts.first else {
        failureCode = "NO_RELEASED_JUNCTION_GUIDANCE"
        return
      }
      if startsNavigation {
        phase = .review
        startNavigationSimulation()
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
        origin = resolvedOrigin
        destination = resolvedDestination
        recommendations = routes
        selectedRecommendationIndex = 0
        phase = .review
        progressFraction = 0
        async let access = Self.surfaceRoute(
          from: resolvedOrigin.coordinate,
          to: routes[0].route.entryFacility.coordinate
        )
        async let egress = Self.surfaceRoute(
          from: routes[0].route.exitFacility.coordinate,
          to: resolvedDestination.coordinate
        )
        accessRoute = await access
        egressRoute = await egress
        persistCheckpoint()
      } catch {
        failureCode = Self.failureCode(error)
      }
    }
  }

  func selectRecommendation(at index: Int) {
    guard recommendations.indices.contains(index) else { return }
    selectedRecommendationIndex = index
    guard let origin, let destination,
      let recommendation = selectedRecommendation
    else {
      return
    }
    Task {
      async let access = Self.surfaceRoute(
        from: origin.coordinate,
        to: recommendation.route.entryFacility.coordinate
      )
      async let egress = Self.surfaceRoute(
        from: recommendation.route.exitFacility.coordinate,
        to: destination.coordinate
      )
      accessRoute = await access
      egressRoute = await egress
      persistCheckpoint()
    }
  }

  func startNavigationSimulation() {
    guard phase == .review, let route = selectedRoute else { return }
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
          horizontalAccuracyMeters: 2
        ),
        speed: .twentyTimes
      )
      try configureSpeech(for: route.routePlan.id)
    } catch {
      failureCode = "WHOLE_SHUTO_RUNTIME_COMPILATION_FAILED"
      return
    }
    phase = accessRoute == nil ? .entryTransition : .surfaceAccess
    progressFraction = 0
    isPlaying = true
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
    persistCheckpoint()
    startPlaybackLoop()
  }

  func togglePlayback() {
    guard phase != .planning, phase != .review, phase != .completed else {
      return
    }
    isPlaying.toggle()
    if isPlaying {
      Task {
        guard await restoreObservationReplayIfNeeded() else {
          return
        }
        speechCoordinator?.resume()
        restoredFromCheckpoint = false
        persistCheckpoint()
        startPlaybackLoop()
      }
    } else {
      playbackTask?.cancel()
      playbackTask = nil
      speechCoordinator?.stop()
    }
  }

  func advanceSimulation() {
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

  func reset() {
    playbackTask?.cancel()
    playbackTask = nil
    speechCoordinator?.stop()
    speechCoordinator = nil
    phase = .planning
    origin = nil
    destination = nil
    recommendations = []
    selectedRecommendationIndex = 0
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
    isStaticJunctionPreview = false
    restoredFromCheckpoint = false
    try? checkpointStore?.remove()
  }

  func handleScenePhase(
    _ scenePhase: ProductNavigationRuntimeScenePhase
  ) {
    switch scenePhase {
    case .active:
      speechCoordinator?.resume()
    case .inactive, .background:
      playbackTask?.cancel()
      playbackTask = nil
      isPlaying = false
      speechCoordinator?.stop()
      persistCheckpoint()
    }
  }

  private func startPlaybackLoop() {
    playbackTask?.cancel()
    if phase == .entryTransition || phase == .expressway {
      startObservationReplayLoop()
      return
    }
    playbackTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(420))
        guard !Task.isCancelled else { return }
        self?.tick()
      }
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
      playbackTask?.cancel()
      playbackTask = nil
      speechCoordinator?.stop()
    case .planning, .review, .completed:
      break
    }
    if phase == .completed {
      try? checkpointStore?.remove()
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
    playbackTask?.cancel()
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
          self?.applyObservationReplayResult(result)
          if result.status.state == .completed {
            self?.completeExpresswayObservationReplay()
            return
          }
        } catch {
          self?.isPlaying = false
          self?.failureCode = "WHOLE_SHUTO_OBSERVATION_PIPELINE_FAILED"
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
    matcherConfidence = update.matcherEstimate.confidence
    runtimeJourneyPhase = update.navigationSnapshot.journeyPhase
    runtimeRecoveryStatus = update.navigationSnapshot.recovery.status
    publishPresentationAndScheduleSpeech(from: update)
    if update.navigationSnapshot.journeyPhase == .routeRecovery {
      isPlaying = false
      playbackTask?.cancel()
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
    guard let checkpointStore,
      let checkpoint = try? checkpointStore.load(),
      checkpoint.schemaVersion
        == WholeShutoJourneyCheckpoint.currentSchemaVersion,
      checkpoint.networkSnapshotID == database.networkSnapshotID,
      checkpoint.phase != .planning,
      checkpoint.phase != .completed,
      let route = try? planner.plan(
        entryFacilityID: checkpoint.entryFacilityID,
        exitFacilityID: checkpoint.exitFacilityID,
        preference: checkpoint.preference
      ),
      route.routePlan == checkpoint.routePlan
    else {
      return
    }
    let accessDistance = checkpoint.accessRoute?.distanceMeters ?? 0
    let egressDistance = checkpoint.egressRoute?.distanceMeters ?? 0
    originQuery = checkpoint.originQuery
    destinationQuery = checkpoint.destinationQuery
    origin = checkpoint.origin
    destination = checkpoint.destination
    preference = checkpoint.preference
    recommendations = [
      ShutoRouteRecommendation(
        route: route,
        surfaceAccessDistanceMeters: accessDistance,
        surfaceEgressDistanceMeters: egressDistance,
        totalScoreMeters:
          route.distanceMeters + accessDistance + egressDistance
      )
    ]
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
    if checkpoint.phase == .entryTransition
      || checkpoint.phase == .expressway
    {
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
            horizontalAccuracyMeters: 2
          ),
          speed: .twentyTimes
        )
        try configureSpeech(for: route.routePlan.id)
        if checkpoint.phase == .entryTransition {
          guard
            checkpoint.runtimeOccurrenceID == nil,
            checkpoint.runtimeFractionAlongOccurrence == nil,
            progressFraction == 0
          else {
            throw WholeShutoProductError.noExpresswayRoute
          }
        } else {
          guard
            let occurrenceID = checkpoint.runtimeOccurrenceID,
            let occurrence = route.routePlan.occurrence(
              id: occurrenceID
            ),
            route.edges.indices.contains(occurrence.index),
            let fraction =
              checkpoint.runtimeFractionAlongOccurrence,
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
      } catch {
        speechCoordinator?.stop()
        speechCoordinator = nil
        runtimeAssets = nil
        driveSimulator = nil
        failureCode = "WHOLE_SHUTO_CHECKPOINT_RUNTIME_INVALID"
      }
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
      preference: preference,
      phase: phase,
      progressFraction: progressFraction,
      runtimeOccurrenceID: runtimeOccurrenceID,
      runtimeFractionAlongOccurrence:
        runtimeFractionAlongOccurrence,
      consumedGuidancePromptIDs:
        consumedGuidancePromptIDs.sorted(),
      mapMode: mapMode,
      accessRoute: accessRoute,
      egressRoute: egressRoute
    )
    try? checkpointStore?.save(checkpoint)
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
      failureCode = "WHOLE_SHUTO_CHECKPOINT_RUNTIME_INVALID"
      return false
    }
  }

  private func resolveOrigin() async throws -> WholeShutoPlace {
    if Self.isCurrentLocationQuery(originQuery) {
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

  private static func surfaceRoute(
    from origin: ShutoCoordinate,
    to destination: ShutoCoordinate
  ) async -> WholeShutoSurfaceRoute? {
    let request = MKDirections.Request()
    request.source = mapItem(origin)
    request.destination = mapItem(destination)
    request.transportType = .automobile
    request.requestsAlternateRoutes = false
    request.highwayPreference = .avoid
    request.tollPreference = .avoid
    do {
      guard
        let route = try await MKDirections(request: request)
          .calculate().routes.first
      else {
        return nil
      }
      let points = route.polyline.points()
      return WholeShutoSurfaceRoute(
        coordinates: (0..<route.polyline.pointCount).map {
          let coordinate = points[$0].coordinate
          return ShutoCoordinate(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
          )
        },
        distanceMeters: route.distance,
        expectedTravelTimeSeconds: route.expectedTravelTime,
        instructions: route.steps.map(\.instructions).filter {
          !$0.isEmpty
        }
      )
    } catch {
      return nil
    }
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

  private static func mapItem(
    _ coordinate: ShutoCoordinate
  ) -> MKMapItem {
    let location = CLLocation(
      latitude: coordinate.latitude,
      longitude: coordinate.longitude
    )
    if #available(iOS 26.0, *) {
      return MKMapItem(location: location, address: nil)
    }
    return MKMapItem(
      placemark: MKPlacemark(
        coordinate: CLLocationCoordinate2D(
          latitude: coordinate.latitude,
          longitude: coordinate.longitude
        )
      )
    )
  }

  private static func distance(
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
