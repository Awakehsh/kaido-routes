import CoreLocation
import Foundation
import KaidoAppleAdapters
import KaidoDomain
import KaidoPresentation
import KaidoRouting

/// One way to the chosen place, as the route list shows it. The driver
/// compares time, distance and roads; who guides it is not shown.
struct DestinationRouteOption: Equatable, Identifiable {
  enum Source: Equatable {
    /// The provider guides the whole drive.
    case provider(WholeShutoSurfaceRoute)
    /// A Kaido Shuto route, continuing into the parked review.
    case kaido(recommendationIndex: Int)
  }

  enum Roads: Equatable {
    case provider(usesExpressway: Bool, name: String?)
    case kaido(routeIDs: [String], entryNameJA: String, exitNameJA: String)
  }

  let id: String
  let source: Source
  /// Nil when only part of the drive could be timed.
  let travelSeconds: Double?
  let distanceMeters: Double?
  let roads: Roads
  let coordinates: [ShutoCoordinate]
}

struct DestinationRouteChoice: Equatable {
  let destination: WholeShutoPlace
  let options: [DestinationRouteOption]
  let recommendations: [ShutoRouteRecommendation]
  let surfaceRoutesByRoutePlanID: [String: WholeShutoRouteChoiceSurfaceRoutes]
  let usesComparableProviderMetrics: Bool
  var selectedIndex = 0

  var selectedOption: DestinationRouteOption { options[selectedIndex] }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.destination == rhs.destination && lhs.options == rhs.options
      && lhs.selectedIndex == rhs.selectedIndex
  }
}

/// A drive the map provider guides end to end. It has no Kaido `RoutePlan`
/// and no release: the route, its steps and every reroute are the
/// provider's. It shares the surface legs' rules: two off-route fixes before
/// anything changes, a 15 s reroute cooldown, accuracy only widening the
/// corridor, and a spoken position notice only for a fix stale for 10 s, at
/// most once a minute.
@MainActor
final class ProviderGuidedDriveModel: ObservableObject {
  enum Phase: Equatable { case driving, arrived }

  @Published private(set) var phase: Phase = .driving
  @Published private(set) var route: WholeShutoSurfaceRoute
  @Published private(set) var progressFraction = 0.0
  @Published private(set) var currentCoordinate: ShutoCoordinate?
  @Published private(set) var isOffRoute = false
  @Published private(set) var isRerouting = false
  @Published private(set) var isLocationDenied = false
  @Published private(set) var isPositionStale = false

  let destination: WholeShutoPlace

  static let offRouteObservationsBeforeReroute = 2
  static let rerouteCooldownSeconds = 15.0
  static let staleFixSeconds = 10.0
  static let positionNoticeCooldownSeconds = 60.0
  static let preannounceDistanceMeters = 250.0
  /// A car this close to the place has arrived wherever the line ends: the
  /// provider's route often stops on a road beside or past the entrance.
  static let nearDestinationMeters = 50.0
  /// Arrival ends tracking for good, so a coarse fix may widen its radius
  /// only this far; a 1 km fix at the start must not end the drive.
  static let arrivalRadiusCapMeters = 100.0

  private let resolver: any WholeShutoSurfaceRouteResolving
  private let source: any ForegroundNavigationLocationSource
  private let speech: GuidanceSpeechCoordinator?
  private let voiceLocale: () -> KaidoReleaseLocale
  private let now: () -> Date
  private let driveID: String
  private var routeGeneration = 0
  private var noticeSequence = 0
  private var consecutiveOffRouteObservations = 0
  private var lastRerouteAt: Date?
  private var lastFixAt: Date?
  private var lastPositionNoticeAt: Date?
  private var freshnessTask: Task<Void, Never>?

  init(
    route: WholeShutoSurfaceRoute,
    destination: WholeShutoPlace,
    resolver: any WholeShutoSurfaceRouteResolving,
    source: any ForegroundNavigationLocationSource,
    speechOutput: (any GuidanceSpeechOutput)?,
    speechMode: GuidanceSpeechMode,
    voiceLocale: @escaping () -> KaidoReleaseLocale,
    now: @escaping () -> Date = Date.init
  ) {
    self.route = route
    self.destination = destination
    self.resolver = resolver
    self.source = source
    self.voiceLocale = voiceLocale
    self.now = now
    let driveID = "provider-drive.\(UUID().uuidString)"
    self.driveID = driveID
    speech = speechOutput.flatMap {
      try? GuidanceSpeechCoordinator(expectedRoutePlanID: driveID, output: $0)
    }
    speech?.setMode(speechMode)
  }

  var stepProgress: WholeShutoSurfaceStepProgress? {
    route.stepProgress(atFraction: progressFraction)
  }

  var remainingMeters: Double {
    max(0, route.distanceMeters * (1 - progressFraction))
  }

  var remainingSeconds: Double {
    max(0, route.expectedTravelTimeSeconds * (1 - progressFraction))
  }

  func start() {
    source.delegate = self
    lastFixAt = now()
    switch source.authorizationStatus {
    case .notDetermined:
      source.requestWhenInUseAuthorization()
    case .denied, .restricted:
      isLocationDenied = true
    default:
      beginUpdating()
    }
    scheduleStepSpeech(forceCurrentStep: true)
    freshnessTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        self?.evaluateFixFreshness()
      }
    }
  }

  func end() {
    stopTracking()
    speech?.stop()
  }

  private func stopTracking() {
    freshnessTask?.cancel()
    freshnessTask = nil
    source.setBackgroundNavigationEnabled(false)
    source.stopUpdatingLocation()
  }

  func setSpeechMode(_ mode: GuidanceSpeechMode) {
    speech?.setMode(mode)
  }

  func observe(
    _ coordinate: ShutoCoordinate,
    horizontalAccuracyMeters: Double,
    at timestamp: Date
  ) {
    guard phase == .driving else { return }
    currentCoordinate = coordinate
    lastFixAt = timestamp
    isPositionStale = false
    if WholeShutoProductModel.distance(coordinate, destination.coordinate)
      <= Self.arrivalRadius(Self.nearDestinationMeters, horizontalAccuracyMeters)
    {
      arrive()
      return
    }
    let corridor = min(100, max(30, horizontalAccuracyMeters * 3))
    guard
      let measurement = WholeShutoProductModel.surfaceRouteMeasurement(
        coordinate, along: route.coordinates),
      measurement.lateralDistanceMeters <= corridor
    else {
      noteOffRoute(at: coordinate, timestamp: timestamp)
      return
    }
    consecutiveOffRouteObservations = 0
    isOffRoute = false
    progressFraction = max(progressFraction, measurement.fractionAlongRoute)
    if progressFraction >= 0.995, let end = route.coordinates.last,
      WholeShutoProductModel.distance(coordinate, end)
        <= Self.arrivalRadius(30, horizontalAccuracyMeters)
    {
      arrive()
      return
    }
    scheduleStepSpeech(forceCurrentStep: false)
  }

  private static func arrivalRadius(_ floor: Double, _ horizontalAccuracyMeters: Double) -> Double {
    min(arrivalRadiusCapMeters, max(floor, horizontalAccuracyMeters * 2))
  }

  private func beginUpdating() {
    isLocationDenied = false
    source.setBackgroundNavigationEnabled(true)
    source.startUpdatingLocation()
  }

  private func noteOffRoute(at coordinate: ShutoCoordinate, timestamp: Date) {
    consecutiveOffRouteObservations += 1
    // One sideways fix beside a tower is a mismeasurement, not a lost route.
    guard consecutiveOffRouteObservations >= Self.offRouteObservationsBeforeReroute else { return }
    isOffRoute = true
    speech?.invalidateGuidance(keepingNotices: true)
    guard !isRerouting,
      lastRerouteAt.map({ timestamp.timeIntervalSince($0) >= Self.rerouteCooldownSeconds }) ?? true
    else { return }
    isRerouting = true
    lastRerouteAt = timestamp
    let roadKind = route.hasHighways
    Task { [weak self] in
      guard let self else { return }
      let routes = await self.resolver.providerRoutes(
        from: coordinate, to: self.destination.coordinate)
      self.isRerouting = false
      guard self.phase == .driving,
        let replacement = routes.first(where: { $0.hasHighways == roadKind }) ?? routes.first
      else { return }
      self.route = replacement
      self.progressFraction = 0
      self.routeGeneration += 1
      self.consecutiveOffRouteObservations = 0
      self.isOffRoute = false
      self.announce(.leftRouteRerouting)
      self.scheduleStepSpeech(forceCurrentStep: true)
    }
  }

  private func arrive() {
    phase = .arrived
    progressFraction = 1
    // Speech outlives tracking so the arrival is still said; Done ends it.
    stopTracking()
    announce(.nearDestination)
  }

  func evaluateFixFreshness() {
    guard phase == .driving, !isLocationDenied, let lastFixAt else { return }
    let current = now()
    guard current.timeIntervalSince(lastFixAt) >= Self.staleFixSeconds else { return }
    isPositionStale = true
    guard lastPositionNoticeAt.map({ current.timeIntervalSince($0) >= Self.positionNoticeCooldownSeconds })
        ?? true
    else { return }
    lastPositionNoticeAt = current
    announce(.positionLost)
  }

  private func scheduleStepSpeech(forceCurrentStep: Bool) {
    guard let speech, let progress = stepProgress,
      let current = stepCommand(at: progress.index, in: progress)
    else { return }
    var command = current
    if !forceCurrentStep,
      speech.startedIdentities.contains(current.identity),
      progress.remainingMeters <= Self.preannounceDistanceMeters,
      let next = stepCommand(at: progress.index + 1, in: progress)
    {
      command = next
    }
    _ = speech.submitProviderSurface(command)
  }

  private func stepCommand(
    at index: Int, in progress: WholeShutoSurfaceStepProgress
  ) -> GuidanceSpeechCommand? {
    guard progress.steps.indices.contains(index) else { return nil }
    let original = progress.steps[index].instruction
    guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    let localized = SurfaceGuidancePresentation.instruction(
      original, sourceLanguageCode: route.guidanceLanguageCode, locale: voiceLocale())
    let id = "provider.drive.\(routeGeneration).\(index)"
    return GuidanceSpeechCommand(
      identity: GuidanceSpeechIdentity(
        promptID: id, anchorID: "PROVIDER_SURFACE_STEP", anchorOccurrenceID: id),
      routePlanID: driveID, languageCode: localized.languageCode, spokenText: localized.text)
  }

  private func announce(_ notice: WholeShutoJourneyNotice) {
    guard let speech else { return }
    noticeSequence += 1
    let id = "journey.\(notice.rawValue).\(noticeSequence)"
    let locale = voiceLocale()
    _ = speech.submitNotice(
      GuidanceSpeechCommand(
        identity: GuidanceSpeechIdentity(
          promptID: id, anchorID: "JOURNEY_STATUS", anchorOccurrenceID: id),
        routePlanID: driveID, languageCode: locale.speechLanguageCode,
        spokenText: notice.text(locale: locale)))
  }
}

extension ProviderGuidedDriveModel: ForegroundNavigationLocationSourceDelegate {
  func foregroundNavigationLocationSourceDidChangeAuthorization(
    _ source: any ForegroundNavigationLocationSource
  ) {
    switch source.authorizationStatus {
    case .authorizedWhenInUse, .authorizedAlways:
      guard phase == .driving else { return }
      beginUpdating()
    case .denied, .restricted:
      isLocationDenied = true
    default:
      break
    }
  }

  func foregroundNavigationLocationSource(
    _ source: any ForegroundNavigationLocationSource,
    didDeliver locations: [CLLocation],
    receivedAt: Date
  ) {
    // A fix that was already stale when it arrived (a cached first fix, a
    // late batch) would move progress or end the drive from where the car
    // was; drop it and let the freshness check own the gap.
    for location in locations
    where location.horizontalAccuracy >= 0
      && receivedAt.timeIntervalSince(location.timestamp) < Self.staleFixSeconds
    {
      observe(
        ShutoCoordinate(
          latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
        horizontalAccuracyMeters: location.horizontalAccuracy,
        at: location.timestamp)
    }
  }

  func foregroundNavigationLocationSource(
    _ source: any ForegroundNavigationLocationSource,
    didFailWithCode code: String,
    isTransient: Bool
  ) {
    // A failed fix is a missing fix: the freshness check owns the notice.
  }
}
