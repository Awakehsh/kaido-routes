import Combine
import CoreLocation
import Foundation
import KaidoAppleAdapters
import KaidoSurfaceRouting
@preconcurrency import MapKit

enum C2NavigationDemoPhase: String, Equatable, Sendable {
  case planning = "PLANNING"
  case routing = "ROUTING"
  case surfaceAccess = "SURFACE_ACCESS"
  case entryTransition = "ENTRY_TRANSITION"
  case expressway = "EXPRESSWAY"
  case exitTransition = "EXIT_TRANSITION"
  case surfaceEgress = "SURFACE_EGRESS"
  case completed = "COMPLETED"
  case failed = "FAILED"
}

enum C2NavigationDemoHighwayInstruction: Equatable, Sendable {
  case continueC2
  case kasaiRight
  case continueB
  case oiLeft
  case tunnelC2
  case hatsudaiExit
}

struct C2NavigationResolvedPlace: Equatable, Sendable {
  let title: String
  let coordinate: SurfaceCoordinate
}

enum C2NavigationDemoError: Error, Equatable {
  case locationUnavailable
  case locationPermissionDenied
  case placeNotFound
  case surfaceRouteUnavailable
  case anotherLocationRequestIsActive
}

@MainActor
protocol C2NavigationCurrentLocationProviding: AnyObject {
  func currentCoordinate() async throws -> SurfaceCoordinate
}

@MainActor
protocol C2NavigationPlaceResolving: AnyObject {
  func resolve(
    query: String,
    near coordinate: SurfaceCoordinate?
  ) async throws -> C2NavigationResolvedPlace
}

@MainActor
final class C2CoreLocationProvider: NSObject,
  C2NavigationCurrentLocationProviding,
  @preconcurrency CLLocationManagerDelegate
{
  private let manager: CLLocationManager
  private var continuation: CheckedContinuation<SurfaceCoordinate, any Error>?

  init(manager: CLLocationManager = CLLocationManager()) {
    self.manager = manager
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBest
  }

  func currentCoordinate() async throws -> SurfaceCoordinate {
    if let location = manager.location,
      location.horizontalAccuracy >= 0
    {
      return SurfaceCoordinate(
        latitude: location.coordinate.latitude,
        longitude: location.coordinate.longitude
      )
    }
    guard continuation == nil else {
      throw C2NavigationDemoError.anotherLocationRequestIsActive
    }
    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      requestLocationIfAuthorized()
    }
  }

  func locationManagerDidChangeAuthorization(_: CLLocationManager) {
    requestLocationIfAuthorized()
  }

  func locationManager(
    _: CLLocationManager,
    didUpdateLocations locations: [CLLocation]
  ) {
    guard
      let location = locations.last(where: {
        $0.horizontalAccuracy >= 0
      })
    else {
      complete(throwing: C2NavigationDemoError.locationUnavailable)
      return
    }
    complete(
      returning: SurfaceCoordinate(
        latitude: location.coordinate.latitude,
        longitude: location.coordinate.longitude
      )
    )
  }

  func locationManager(_: CLLocationManager, didFailWithError _: Error) {
    complete(throwing: C2NavigationDemoError.locationUnavailable)
  }

  private func requestLocationIfAuthorized() {
    guard continuation != nil else { return }
    switch manager.authorizationStatus {
    case .notDetermined:
      manager.requestWhenInUseAuthorization()
    case .authorizedAlways, .authorizedWhenInUse:
      manager.requestLocation()
    case .denied, .restricted:
      complete(throwing: C2NavigationDemoError.locationPermissionDenied)
    @unknown default:
      complete(throwing: C2NavigationDemoError.locationUnavailable)
    }
  }

  private func complete(returning coordinate: SurfaceCoordinate) {
    let continuation = continuation
    self.continuation = nil
    continuation?.resume(returning: coordinate)
  }

  private func complete(throwing error: any Error) {
    let continuation = continuation
    self.continuation = nil
    continuation?.resume(throwing: error)
  }
}

@MainActor
final class C2MapKitPlaceResolver: C2NavigationPlaceResolving {
  func resolve(
    query: String,
    near coordinate: SurfaceCoordinate?
  ) async throws -> C2NavigationResolvedPlace {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
      throw C2NavigationDemoError.placeNotFound
    }
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = normalized
    request.resultTypes = [.address, .pointOfInterest]
    if let coordinate {
      request.region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(
          latitude: coordinate.latitude,
          longitude: coordinate.longitude
        ),
        latitudinalMeters: 80_000,
        longitudinalMeters: 80_000
      )
    }
    let response = try await MKLocalSearch(request: request).start()
    guard let item = response.mapItems.first else {
      throw C2NavigationDemoError.placeNotFound
    }
    let coordinate: CLLocationCoordinate2D
    if #available(iOS 26.0, *) {
      coordinate = item.location.coordinate
    } else {
      coordinate = item.placemark.coordinate
    }
    return C2NavigationResolvedPlace(
      title: item.name ?? normalized,
      coordinate: SurfaceCoordinate(
        latitude: coordinate.latitude,
        longitude: coordinate.longitude
      )
    )
  }
}

@MainActor
final class C2NavigationDemoModel: ObservableObject {
  static let currentLocationTokens = [
    "",
    "当前位置",
    "現在地",
    "current location",
  ]

  @Published var originQuery: String
  @Published var destinationQuery: String
  @Published private(set) var phase: C2NavigationDemoPhase
  @Published private(set) var origin: C2NavigationResolvedPlace?
  @Published private(set) var destination: C2NavigationResolvedPlace?
  @Published private(set) var accessRoute: SurfaceRouteCandidate?
  @Published private(set) var egressRoute: SurfaceRouteCandidate?
  @Published private(set) var surfaceProgressFraction = 0.0
  @Published private(set) var surfaceStepIndex = 0
  @Published private(set) var expresswayOccurrenceIndex = 0
  @Published private(set) var expresswayOccurrenceFraction = 0.0
  @Published private(set) var isPlaying = false
  @Published private(set) var failureCode: String?

  private let locationProvider: any C2NavigationCurrentLocationProviding
  private let placeResolver: any C2NavigationPlaceResolving
  private let surfaceProvider: any SurfaceRouteProvider
  private let playbackInterval: Duration
  private var playbackTask: Task<Void, Never>?
  private var transitionTick = 0

  init(
    originQuery: String = "当前位置",
    destinationQuery: String = "",
    phase: C2NavigationDemoPhase = .planning,
    locationProvider: any C2NavigationCurrentLocationProviding =
      C2CoreLocationProvider(),
    placeResolver: any C2NavigationPlaceResolving =
      C2MapKitPlaceResolver(),
    surfaceProvider: any SurfaceRouteProvider =
      MapKitSurfaceRouteProvider(),
    playbackInterval: Duration = .milliseconds(450)
  ) {
    self.originQuery = originQuery
    self.destinationQuery = destinationQuery
    self.phase = phase
    self.locationProvider = locationProvider
    self.placeResolver = placeResolver
    self.surfaceProvider = surfaceProvider
    self.playbackInterval = playbackInterval
  }

  deinit {
    playbackTask?.cancel()
  }

  var canStart: Bool {
    let destination = destinationQuery.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    return !destination.isEmpty
      && (phase == .planning || phase == .failed)
  }

  var activeSurfaceRoute: SurfaceRouteCandidate? {
    switch phase {
    case .surfaceAccess, .entryTransition:
      accessRoute
    case .exitTransition, .surfaceEgress, .completed:
      egressRoute
    case .planning, .routing, .expressway, .failed:
      nil
    }
  }

  var currentSurfaceStep: SurfaceRouteStep? {
    let steps = activeSurfaceRoute?.steps ?? []
    guard !steps.isEmpty else { return nil }
    return steps[min(surfaceStepIndex, steps.count - 1)]
  }

  var highwayInstruction: C2NavigationDemoHighwayInstruction {
    switch expresswayOccurrenceIndex {
    case 9:
      .kasaiRight
    case 10...12:
      .continueB
    case 13:
      .oiLeft
    case 14:
      .tunnelC2
    case 15:
      .hatsudaiExit
    default:
      .continueC2
    }
  }

  var isTunnelPositionEstimated: Bool {
    phase == .expressway
      && (13...15).contains(expresswayOccurrenceIndex)
  }

  var junctionInset: ProductJunctionInsetPresentation? {
    guard phase == .expressway else { return nil }
    switch expresswayOccurrenceIndex {
    case 9:
      return C2CompletedRouteDemo.kasaiJunctionInset
    case 13:
      return C2CompletedRouteDemo.oiJunctionInset
    default:
      return nil
    }
  }

  var topologyPresentation: ProductTopologyMapPresentation {
    guard phase == .expressway else {
      return C2CompletedRouteDemo.presentation
    }
    return C2CompletedRouteDemo.navigationPresentation(
      currentOccurrenceIndex: expresswayOccurrenceIndex,
      fraction: expresswayOccurrenceFraction,
      positionIsEstimated: isTunnelPositionEstimated
    )
  }

  var journeyProgressFraction: Double {
    switch phase {
    case .planning, .routing, .failed:
      0
    case .surfaceAccess:
      0.18 * surfaceProgressFraction
    case .entryTransition:
      0.2
    case .expressway:
      0.2
        + 0.6
        * ((Double(expresswayOccurrenceIndex)
          + expresswayOccurrenceFraction)
          / Double(C2CompletedRouteDemo.occurrenceCount))
    case .exitTransition:
      0.82
    case .surfaceEgress:
      0.82 + 0.18 * surfaceProgressFraction
    case .completed:
      1
    }
  }

  func startNavigation() async {
    guard canStart else { return }
    stopPlayback()
    phase = .routing
    failureCode = nil
    do {
      let resolvedOrigin = try await resolveOrigin()
      let resolvedDestination = try await placeResolver.resolve(
        query: destinationQuery,
        near: resolvedOrigin.coordinate
      )
      async let accessResponse = surfaceProvider.routes(
        for: Self.accessRequest(from: resolvedOrigin.coordinate)
      )
      async let egressResponse = surfaceProvider.routes(
        for: Self.egressRequest(to: resolvedDestination.coordinate)
      )
      guard
        let accessCandidate = Self.acceptedSurfaceCandidate(
          from: await accessResponse
        ),
        let egressCandidate = Self.acceptedSurfaceCandidate(
          from: await egressResponse
        )
      else {
        throw C2NavigationDemoError.surfaceRouteUnavailable
      }
      origin = resolvedOrigin
      destination = resolvedDestination
      accessRoute = accessCandidate
      egressRoute = egressCandidate
      phase = .surfaceAccess
      surfaceProgressFraction = 0
      surfaceStepIndex = 0
      expresswayOccurrenceIndex = 0
      expresswayOccurrenceFraction = 0
      transitionTick = 0
      resume()
    } catch {
      phase = .failed
      failureCode = Self.errorCode(error)
    }
  }

  func pause() {
    guard isPlaying else { return }
    stopPlayback()
  }

  func resume() {
    guard phase != .planning,
      phase != .routing,
      phase != .completed,
      phase != .failed,
      !isPlaying
    else {
      return
    }
    isPlaying = true
    playbackTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: playbackInterval)
        } catch {
          return
        }
        guard !Task.isCancelled else { return }
        advanceOneTick()
        if phase == .completed || phase == .failed {
          stopPlayback()
          return
        }
      }
    }
  }

  func replay() {
    guard accessRoute != nil, egressRoute != nil else { return }
    stopPlayback()
    phase = .surfaceAccess
    surfaceProgressFraction = 0
    surfaceStepIndex = 0
    expresswayOccurrenceIndex = 0
    expresswayOccurrenceFraction = 0
    transitionTick = 0
    resume()
  }

  func reset() {
    stopPlayback()
    phase = .planning
    accessRoute = nil
    egressRoute = nil
    origin = nil
    destination = nil
    surfaceProgressFraction = 0
    surfaceStepIndex = 0
    expresswayOccurrenceIndex = 0
    expresswayOccurrenceFraction = 0
    failureCode = nil
    transitionTick = 0
  }

  func advanceOneTickForTesting() {
    advanceOneTick()
  }

  private func advanceOneTick() {
    switch phase {
    case .surfaceAccess:
      advanceSurfaceRoute(nextPhase: .entryTransition)
    case .entryTransition:
      transitionTick += 1
      if transitionTick >= 2 {
        phase = .expressway
        transitionTick = 0
        surfaceProgressFraction = 0
        surfaceStepIndex = 0
      }
    case .expressway:
      expresswayOccurrenceFraction += 0.25
      if expresswayOccurrenceFraction >= 1 {
        expresswayOccurrenceFraction = 0
        expresswayOccurrenceIndex += 1
        if expresswayOccurrenceIndex >= C2CompletedRouteDemo.occurrenceCount {
          expresswayOccurrenceIndex =
            C2CompletedRouteDemo.occurrenceCount - 1
          expresswayOccurrenceFraction = 1
          phase = .exitTransition
          transitionTick = 0
        }
      }
    case .exitTransition:
      transitionTick += 1
      if transitionTick >= 2 {
        phase = .surfaceEgress
        transitionTick = 0
        surfaceProgressFraction = 0
        surfaceStepIndex = 0
      }
    case .surfaceEgress:
      advanceSurfaceRoute(nextPhase: .completed)
    case .planning, .routing, .completed, .failed:
      break
    }
  }

  private func advanceSurfaceRoute(
    nextPhase: C2NavigationDemoPhase
  ) {
    surfaceProgressFraction = min(1, surfaceProgressFraction + 0.12)
    let stepCount = max(1, activeSurfaceRoute?.steps.count ?? 1)
    surfaceStepIndex = min(
      stepCount - 1,
      Int((surfaceProgressFraction * Double(stepCount)).rounded(.down))
    )
    if surfaceProgressFraction >= 1 {
      phase = nextPhase
      transitionTick = 0
      if nextPhase == .completed {
        surfaceProgressFraction = 1
      }
    }
  }

  private func stopPlayback() {
    playbackTask?.cancel()
    playbackTask = nil
    isPlaying = false
  }

  private func resolveOrigin() async throws -> C2NavigationResolvedPlace {
    let normalized = originQuery.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    if Self.currentLocationTokens.contains(where: {
      $0.caseInsensitiveCompare(normalized) == .orderedSame
    }) {
      return C2NavigationResolvedPlace(
        title: normalized.isEmpty ? "当前位置" : normalized,
        coordinate: try await locationProvider.currentCoordinate()
      )
    }
    return try await placeResolver.resolve(query: normalized, near: nil)
  }

  private static func accessRequest(
    from origin: SurfaceCoordinate
  ) -> SurfaceRouteRequest {
    SurfaceRouteRequest(
      id: "demo.c2.surface-access",
      originID: "user-selected-origin",
      origin: origin,
      entranceFacilityID: "shutoko.entrance.tomigaya.c2.outer",
      selectedJoinOccurrenceID: "demo.c2.occurrence.0",
      destinationAnchor: DirectedApproachAnchor(
        id: "operator.tomigaya.facility-point",
        coordinate: tomigayaEntranceCoordinate,
        directedSurfaceEdgeID: "provider-only.tomigaya-approach",
        expectedBearingDegrees: 0,
        bearingToleranceDegrees: 180,
        maxTerminalDistanceMeters: 80
      ),
      preferences: SurfaceRoutePreferences(
        avoidHighways: true,
        avoidTolls: true,
        requestAlternatives: true
      )
    )
  }

  private static func egressRequest(
    to destination: SurfaceCoordinate
  ) -> SurfaceRouteRequest {
    SurfaceRouteRequest(
      id: "demo.c2.surface-egress",
      originID: "operator.hatsudai-minami.facility-point",
      origin: hatsudaiMinamiExitCoordinate,
      entranceFacilityID: "user-selected-destination",
      selectedJoinOccurrenceID: "demo.c2.surface-egress",
      destinationAnchor: DirectedApproachAnchor(
        id: "user-selected-destination",
        coordinate: destination,
        directedSurfaceEdgeID: "provider-only.destination",
        expectedBearingDegrees: 0,
        bearingToleranceDegrees: 180,
        maxTerminalDistanceMeters: 120
      ),
      preferences: SurfaceRoutePreferences(
        avoidHighways: true,
        avoidTolls: true,
        requestAlternatives: true
      )
    )
  }

  private static func acceptedSurfaceCandidate(
    from response: SurfaceProviderResponse
  ) -> SurfaceRouteCandidate? {
    guard case .success(let candidates) = response else { return nil }
    let surfaceOnly = candidates.filter {
      $0.hasHighways != true && $0.hasTolls != true
    }
    return surfaceOnly.min {
      if $0.expectedTravelTimeSeconds == $1.expectedTravelTimeSeconds {
        return $0.distanceMeters < $1.distanceMeters
      }
      return $0.expectedTravelTimeSeconds < $1.expectedTravelTimeSeconds
    }
  }

  private static func errorCode(_ error: any Error) -> String {
    if let error = error as? C2NavigationDemoError {
      switch error {
      case .locationUnavailable:
        return "CURRENT_LOCATION_UNAVAILABLE"
      case .locationPermissionDenied:
        return "CURRENT_LOCATION_PERMISSION_DENIED"
      case .placeNotFound:
        return "PLACE_NOT_FOUND"
      case .surfaceRouteUnavailable:
        return "SURFACE_ROUTE_UNAVAILABLE"
      case .anotherLocationRequestIsActive:
        return "LOCATION_REQUEST_ALREADY_ACTIVE"
      }
    }
    let nsError = error as NSError
    return "\(nsError.domain).\(nsError.code)"
  }

  /// Current operator facility point, checked 2026-07-29:
  /// https://www.shutoko.jp/use/network/map/route-c2/tomigaya/
  nonisolated static let tomigayaEntranceCoordinate = SurfaceCoordinate(
    latitude: 35.66378171,
    longitude: 139.6877503
  )

  /// Current operator facility point, checked 2026-07-29:
  /// https://www.shutoko.jp/use/network/map/route-c2/hatsudaiminami/
  nonisolated static let hatsudaiMinamiExitCoordinate = SurfaceCoordinate(
    latitude: 35.67511257,
    longitude: 139.6878147
  )
}

@MainActor
extension C2NavigationDemoModel {
  static func preview(
    phase requestedPhase: C2NavigationDemoPhase = .planning,
    expresswayOccurrenceIndex: Int = 0
  ) -> C2NavigationDemoModel {
    let model = C2NavigationDemoModel(
      originQuery: "東京都庁",
      destinationQuery: "東京駅",
      locationProvider: C2PreviewLocationProvider(),
      placeResolver: C2PreviewPlaceResolver(),
      surfaceProvider: C2PreviewSurfaceRouteProvider(),
      playbackInterval: .milliseconds(90)
    )
    model.origin = C2NavigationResolvedPlace(
      title: "東京都庁",
      coordinate: C2PreviewLocationProvider.coordinate
    )
    model.destination = C2NavigationResolvedPlace(
      title: "東京駅",
      coordinate: C2PreviewPlaceResolver.destinationCoordinate
    )
    model.accessRoute = C2PreviewSurfaceRouteProvider.accessCandidate
    model.egressRoute = C2PreviewSurfaceRouteProvider.egressCandidate
    model.phase = requestedPhase
    if requestedPhase == .expressway {
      model.expresswayOccurrenceIndex = min(
        C2CompletedRouteDemo.occurrenceCount - 1,
        max(0, expresswayOccurrenceIndex)
      )
      model.expresswayOccurrenceFraction = 0.5
    } else if requestedPhase == .surfaceEgress {
      model.surfaceProgressFraction = 0.45
      model.surfaceStepIndex = 1
    } else if requestedPhase == .completed {
      model.surfaceProgressFraction = 1
      model.surfaceStepIndex =
        max(0, C2PreviewSurfaceRouteProvider.egressCandidate.steps.count - 1)
    }
    return model
  }
}

@MainActor
private final class C2PreviewLocationProvider:
  C2NavigationCurrentLocationProviding
{
  nonisolated static let coordinate = SurfaceCoordinate(
    latitude: 35.6896,
    longitude: 139.6917
  )

  func currentCoordinate() async throws -> SurfaceCoordinate {
    Self.coordinate
  }
}

@MainActor
private final class C2PreviewPlaceResolver:
  C2NavigationPlaceResolving
{
  nonisolated static let destinationCoordinate = SurfaceCoordinate(
    latitude: 35.6812,
    longitude: 139.7671
  )

  func resolve(
    query: String,
    near _: SurfaceCoordinate?
  ) async throws -> C2NavigationResolvedPlace {
    if query.localizedCaseInsensitiveContains("東京")
      || query.localizedCaseInsensitiveContains("Tokyo")
    {
      return C2NavigationResolvedPlace(
        title: query,
        coordinate: Self.destinationCoordinate
      )
    }
    return C2NavigationResolvedPlace(
      title: query,
      coordinate: Self.destinationCoordinate
    )
  }
}

private struct C2PreviewSurfaceRouteProvider: SurfaceRouteProvider {
  let metadata = SurfaceRouteProviderMetadata(
    id: "preview.c2.surface",
    adapterVersion: "1.0.0",
    providerVersion: "preview",
    dataReviewStatus: .derivedFixtureReviewed
  )

  func routes(
    for request: SurfaceRouteRequest
  ) async -> SurfaceProviderResponse {
    if request.id == "demo.c2.surface-access" {
      return .success([Self.accessCandidate])
    }
    if request.id == "demo.c2.surface-egress" {
      return .success([Self.egressCandidate])
    }
    return .failure(
      SurfaceProviderFailure(
        kind: .invalidRequest,
        providerErrorCode: "UNKNOWN_PREVIEW_REQUEST"
      )
    )
  }

  static let accessCandidate = SurfaceRouteCandidate(
    id: "preview.c2.surface-access.0",
    providerID: "preview.c2.surface",
    coordinates: [
      C2PreviewLocationProvider.coordinate,
      SurfaceCoordinate(latitude: 35.6828, longitude: 139.6995),
      SurfaceCoordinate(latitude: 35.6717, longitude: 139.6914),
      C2NavigationDemoModel.tomigayaEntranceCoordinate,
    ],
    steps: [
      SurfaceRouteStep(
        id: "preview.access.0",
        instruction: "沿地面道路向富ヶ谷入口行驶",
        distanceMeters: 1_600
      ),
      SurfaceRouteStep(
        id: "preview.access.1",
        instruction: "跟随道路标志前往 C2 外回り",
        distanceMeters: 620
      ),
      SurfaceRouteStep(
        id: "preview.access.2",
        instruction: "进入富ヶ谷 ETC 专用入口",
        distanceMeters: 180
      ),
    ],
    distanceMeters: 2_400,
    expectedTravelTimeSeconds: 540,
    hasHighways: false,
    hasTolls: false
  )

  static let egressCandidate = SurfaceRouteCandidate(
    id: "preview.c2.surface-egress.0",
    providerID: "preview.c2.surface",
    coordinates: [
      C2NavigationDemoModel.hatsudaiMinamiExitCoordinate,
      SurfaceCoordinate(latitude: 35.6777, longitude: 139.7046),
      SurfaceCoordinate(latitude: 35.6808, longitude: 139.7338),
      C2PreviewPlaceResolver.destinationCoordinate,
    ],
    steps: [
      SurfaceRouteStep(
        id: "preview.egress.0",
        instruction: "驶离初台南出口，进入地面道路",
        distanceMeters: 700
      ),
      SurfaceRouteStep(
        id: "preview.egress.1",
        instruction: "继续前往最终目的地",
        distanceMeters: 4_100
      ),
      SurfaceRouteStep(
        id: "preview.egress.2",
        instruction: "目的地在前方",
        distanceMeters: 120
      ),
    ],
    distanceMeters: 4_920,
    expectedTravelTimeSeconds: 980,
    hasHighways: false,
    hasTolls: false
  )
}
