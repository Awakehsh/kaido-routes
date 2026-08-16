import Combine
import CoreLocation
import Foundation
import KaidoNavigation

enum ForegroundNavigationLocationBlockReason: String, Equatable, Sendable {
  case syntheticTestOnly = "SYNTHETIC_TEST_ONLY"
  case releasedProductUnavailable = "RELEASED_PRODUCT_UNAVAILABLE"
}

enum ForegroundNavigationLocationAuthority: Equatable, Sendable {
  case blocked(
    identity: KaidoProductRuntimeIdentity,
    reason: ForegroundNavigationLocationBlockReason
  )
  case releasedProduct(KaidoForegroundLiveInputAuthority)

  var identity: KaidoProductRuntimeIdentity {
    switch self {
    case .blocked(let identity, _):
      identity
    case .releasedProduct(let authority):
      authority.runtimeIdentity
    }
  }
}

enum ForegroundNavigationLocationControllerError: Error, Equatable {
  case invalidRuntimeIdentity
  case runtimeIdentityMismatch
}

enum ForegroundNavigationLocationState: Equatable, Sendable {
  case releaseBlocked(ForegroundNavigationLocationBlockReason)
  case runtimeUnavailable
  case idle
  case awaitingAuthorization
  case running
  case stopped
  case sceneInactive
  case permissionDenied
  case failed(String)

  var label: String {
    switch self {
    case .releaseBlocked:
      "LIVE LOCATION BLOCKED"
    case .runtimeUnavailable:
      "RUNTIME UNAVAILABLE"
    case .idle:
      "LIVE LOCATION IDLE"
    case .awaitingAuthorization:
      "AWAITING LOCATION AUTHORIZATION"
    case .running:
      "NAVIGATION LOCATION RUNNING"
    case .stopped:
      "NAVIGATION LOCATION STOPPED"
    case .sceneInactive:
      "LOCATION IDLE · SCENE INACTIVE"
    case .permissionDenied:
      "LOCATION PERMISSION DENIED"
    case .failed:
      "LOCATION PIPELINE BLOCKED"
    }
  }

  var detail: String {
    switch self {
    case .releaseBlocked(let reason):
      reason.rawValue
    case .runtimeUnavailable:
      "The release-bound actor is not ready to accept foreground input."
    case .idle:
      "Location starts only after an explicit user action."
    case .awaitingAuthorization:
      "Waiting for When In Use authorization; no updates have started."
    case .running:
      "Foreground-started When In Use updates feed the exact release-bound actor in callback order and continue during active background navigation."
    case .stopped:
      "Updates remain stopped until another explicit user action."
    case .sceneInactive:
      "No active navigation session is using location while the scene is inactive."
    case .permissionDenied:
      "Core Location is denied or restricted; no route progress is accepted."
    case .failed(let code):
      code
    }
  }
}

@MainActor
protocol ForegroundNavigationLocationConsuming: AnyObject {
  var foregroundNavigationRuntimeIdentity: KaidoProductRuntimeIdentity {
    get
  }
  var canConsumeForegroundNavigationLocations: Bool { get }

  func consumeForegroundNavigationLocations(
    _ locations: [CLLocation],
    receivedAt: Date
  ) async
}

@MainActor
protocol ForegroundNavigationLocationSourceDelegate: AnyObject {
  func foregroundNavigationLocationSourceDidChangeAuthorization(
    _ source: any ForegroundNavigationLocationSource
  )

  func foregroundNavigationLocationSource(
    _ source: any ForegroundNavigationLocationSource,
    didDeliver locations: [CLLocation],
    receivedAt: Date
  )

  func foregroundNavigationLocationSource(
    _ source: any ForegroundNavigationLocationSource,
    didFailWithCode code: String,
    isTransient: Bool
  )
}

@MainActor
protocol ForegroundNavigationLocationSource: AnyObject {
  var delegate: (any ForegroundNavigationLocationSourceDelegate)? { get set }
  var authorizationStatus: CLAuthorizationStatus { get }
  var accuracyAuthorization: CLAccuracyAuthorization { get }
  var supportsBackgroundNavigation: Bool { get }

  func requestWhenInUseAuthorization()
  func setBackgroundNavigationEnabled(_ enabled: Bool)
  func startUpdatingLocation()
  func stopUpdatingLocation()
}

@MainActor
final class CoreLocationForegroundNavigationSource: NSObject,
  ForegroundNavigationLocationSource,
  @preconcurrency CLLocationManagerDelegate
{
  weak var delegate: (any ForegroundNavigationLocationSourceDelegate)?

  private let locationManager: CLLocationManager
  let supportsBackgroundNavigation: Bool

  init(
    locationManager: CLLocationManager = CLLocationManager(),
    backgroundModes: [String] =
      Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes")
      as? [String] ?? []
  ) {
    self.locationManager = locationManager
    supportsBackgroundNavigation = backgroundModes.contains("location")
    super.init()
    locationManager.delegate = self
    locationManager.activityType = .automotiveNavigation
    locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    locationManager.distanceFilter = kCLDistanceFilterNone
    locationManager.pausesLocationUpdatesAutomatically = false
    locationManager.allowsBackgroundLocationUpdates = false
    locationManager.showsBackgroundLocationIndicator = false
  }

  var authorizationStatus: CLAuthorizationStatus {
    locationManager.authorizationStatus
  }

  var accuracyAuthorization: CLAccuracyAuthorization {
    locationManager.accuracyAuthorization
  }

  func requestWhenInUseAuthorization() {
    locationManager.requestWhenInUseAuthorization()
  }

  func setBackgroundNavigationEnabled(_ enabled: Bool) {
    guard supportsBackgroundNavigation else {
      locationManager.allowsBackgroundLocationUpdates = false
      locationManager.showsBackgroundLocationIndicator = false
      return
    }
    locationManager.allowsBackgroundLocationUpdates = enabled
    locationManager.showsBackgroundLocationIndicator = enabled
  }

  func startUpdatingLocation() {
    locationManager.startUpdatingLocation()
  }

  func stopUpdatingLocation() {
    locationManager.stopUpdatingLocation()
  }

  func locationManagerDidChangeAuthorization(_: CLLocationManager) {
    delegate?.foregroundNavigationLocationSourceDidChangeAuthorization(self)
  }

  func locationManager(
    _: CLLocationManager,
    didUpdateLocations locations: [CLLocation]
  ) {
    delegate?.foregroundNavigationLocationSource(
      self,
      didDeliver: locations,
      receivedAt: Date()
    )
  }

  func locationManager(_: CLLocationManager, didFailWithError error: Error) {
    if let coreLocationError = error as? CLError,
      coreLocationError.code == .locationUnknown
    {
      delegate?.foregroundNavigationLocationSource(
        self,
        didFailWithCode: "CORE_LOCATION_LOCATION_UNKNOWN",
        isTransient: true
      )
      return
    }
    let code: String
    if let coreLocationError = error as? CLError {
      code = "CORE_LOCATION_\(coreLocationError.code.rawValue)"
    } else {
      code = "CORE_LOCATION_FAILURE"
    }
    delegate?.foregroundNavigationLocationSource(
      self,
      didFailWithCode: code,
      isTransient: false
    )
  }
}

@MainActor
final class ForegroundNavigationLocationController: ObservableObject {
  @Published private(set) var state: ForegroundNavigationLocationState
  @Published private(set) var lastTransientFailureCode: String?

  let authority: ForegroundNavigationLocationAuthority

  private static let maximumPendingBatchCount = 8

  private weak var consumer: (any ForegroundNavigationLocationConsuming)?
  private let source: (any ForegroundNavigationLocationSource)?
  private var scenePhase: ProductNavigationRuntimeScenePhase = .active
  private var startRequested = false
  private var pendingAuthorizationStart = false
  private var pendingBatches: [LocationBatch] = []
  private var drainTask: Task<Void, Never>?
  private var stateOperationID = 0

  init(
    authority: ForegroundNavigationLocationAuthority,
    consumer: any ForegroundNavigationLocationConsuming,
    source: (any ForegroundNavigationLocationSource)? = nil
  ) throws {
    guard
      authority.identity.isComplete,
      consumer.foregroundNavigationRuntimeIdentity.isComplete
    else {
      throw ForegroundNavigationLocationControllerError.invalidRuntimeIdentity
    }
    guard authority.identity == consumer.foregroundNavigationRuntimeIdentity else {
      throw ForegroundNavigationLocationControllerError.runtimeIdentityMismatch
    }
    self.authority = authority
    self.consumer = consumer
    switch authority {
    case .blocked(_, let reason):
      self.source = nil
      state = .releaseBlocked(reason)
    case .releasedProduct:
      let admittedSource = source ?? CoreLocationForegroundNavigationSource()
      self.source = admittedSource
      if !admittedSource.supportsBackgroundNavigation {
        state = .failed("BACKGROUND_LOCATION_MODE_MISSING")
      } else {
        state =
          consumer.canConsumeForegroundNavigationLocations
          ? .idle
          : .runtimeUnavailable
      }
    }
    self.source?.delegate = self
  }

  var canStart: Bool {
    guard
      case .releasedProduct = authority,
      scenePhase == .active,
      consumer?.canConsumeForegroundNavigationLocations == true
    else {
      return false
    }
    return switch state {
    case .idle, .stopped:
      true
    case .releaseBlocked, .runtimeUnavailable, .awaitingAuthorization,
      .running, .sceneInactive, .permissionDenied, .failed:
      false
    }
  }

  var canStop: Bool {
    state == .awaitingAuthorization || state == .running
  }

  var maintainsActiveNavigationAcrossSceneChanges: Bool {
    state == .running || (startRequested && pendingAuthorizationStart)
  }

  var authorizationLabel: String {
    guard let source else { return "NOT REQUESTED" }
    return switch source.authorizationStatus {
    case .notDetermined:
      "NOT DETERMINED"
    case .restricted:
      "RESTRICTED"
    case .denied:
      "DENIED"
    case .authorizedAlways:
      "AUTHORIZED ALWAYS"
    case .authorizedWhenInUse:
      "AUTHORIZED IN USE"
    @unknown default:
      "UNKNOWN"
    }
  }

  var accuracyAuthorizationLabel: String {
    guard let source else { return "NOT REQUESTED" }
    return switch source.accuracyAuthorization {
    case .fullAccuracy:
      "FULL ACCURACY"
    case .reducedAccuracy:
      "REDUCED ACCURACY"
    @unknown default:
      "UNKNOWN ACCURACY"
    }
  }

  func refreshRuntimeAvailability() {
    guard case .releasedProduct = authority else { return }
    guard source?.supportsBackgroundNavigation == true else {
      state = .failed("BACKGROUND_LOCATION_MODE_MISSING")
      return
    }
    if state == .running, startRequested {
      return
    }
    guard scenePhase == .active else {
      state = .sceneInactive
      return
    }
    guard consumer?.canConsumeForegroundNavigationLocations == true else {
      state = .runtimeUnavailable
      return
    }
    if state == .runtimeUnavailable || state == .sceneInactive {
      state = .idle
    }
  }

  func start() {
    refreshRuntimeAvailability()
    guard canStart, let source else { return }
    lastTransientFailureCode = nil
    startRequested = true
    switch source.authorizationStatus {
    case .notDetermined:
      pendingAuthorizationStart = true
      state = .awaitingAuthorization
      source.requestWhenInUseAuthorization()
    case .authorizedAlways, .authorizedWhenInUse:
      beginUpdates()
    case .denied, .restricted:
      startRequested = false
      state = .permissionDenied
    @unknown default:
      failAndStop("UNKNOWN_AUTHORIZATION_STATUS")
    }
  }

  func stop() async {
    guard canStop else { return }
    stateOperationID += 1
    let operationID = stateOperationID
    await quiesceLocationSource()
    guard operationID == stateOperationID else { return }
    state = .stopped
  }

  func handleScenePhase(
    _ phase: ProductNavigationRuntimeScenePhase
  ) async {
    scenePhase = phase
    if state == .running, startRequested {
      return
    }
    stateOperationID += 1
    let operationID = stateOperationID
    switch authority {
    case .blocked(_, let reason):
      state = .releaseBlocked(reason)
    case .releasedProduct:
      if pendingAuthorizationStart {
        switch phase {
        case .active:
          switch source?.authorizationStatus {
          case .authorizedAlways, .authorizedWhenInUse:
            pendingAuthorizationStart = false
            beginUpdates()
          case .denied, .restricted:
            pendingAuthorizationStart = false
            startRequested = false
            state = .permissionDenied
          case .notDetermined:
            state = .awaitingAuthorization
          case nil:
            failAndStop("LOCATION_SOURCE_MISSING")
          @unknown default:
            failAndStop("UNKNOWN_AUTHORIZATION_STATUS")
          }
        case .inactive, .background:
          source?.setBackgroundNavigationEnabled(false)
          source?.stopUpdatingLocation()
          state = .sceneInactive
        }
        return
      }
      await quiesceLocationSource()
      guard operationID == stateOperationID else { return }
      switch phase {
      case .active:
        state = activeStoppedState
      case .inactive, .background:
        state = .sceneInactive
      }
    }
  }

  private func beginUpdates() {
    guard
      startRequested,
      scenePhase == .active,
      consumer?.canConsumeForegroundNavigationLocations == true,
      let source,
      source.supportsBackgroundNavigation
    else {
      failAndStop("LOCATION_START_PRECONDITION_DRIFT")
      return
    }
    if state != .running {
      source.setBackgroundNavigationEnabled(true)
      state = .running
      source.startUpdatingLocation()
    }
  }

  private func quiesceLocationSource() async {
    startRequested = false
    pendingAuthorizationStart = false
    source?.setBackgroundNavigationEnabled(false)
    source?.stopUpdatingLocation()
    pendingBatches.removeAll(keepingCapacity: true)
    let task = drainTask
    task?.cancel()
    await task?.value
    drainTask = nil
  }

  private func enqueue(
    locations: [CLLocation],
    receivedAt: Date
  ) {
    guard state == .running, !locations.isEmpty else {
      return
    }
    guard consumer?.canConsumeForegroundNavigationLocations == true else {
      failAndStop("RUNTIME_STOPPED_ACCEPTING_LOCATION")
      return
    }
    guard pendingBatches.count < Self.maximumPendingBatchCount else {
      failAndStop("LOCATION_CALLBACK_BACKLOG_EXCEEDED")
      return
    }
    pendingBatches.append(
      LocationBatch(locations: locations, receivedAt: receivedAt)
    )
    guard drainTask == nil else { return }
    drainTask = Task { [weak self] in
      await self?.drain()
    }
  }

  private func drain() async {
    defer {
      drainTask = nil
      if state == .running, !pendingBatches.isEmpty {
        drainTask = Task { [weak self] in
          await self?.drain()
        }
      }
    }
    while !Task.isCancelled,
      state == .running,
      !pendingBatches.isEmpty
    {
      guard let consumer, consumer.canConsumeForegroundNavigationLocations else {
        failAndStop("RUNTIME_STOPPED_ACCEPTING_LOCATION")
        return
      }
      let batch = pendingBatches.removeFirst()
      await consumer.consumeForegroundNavigationLocations(
        batch.locations,
        receivedAt: batch.receivedAt
      )
    }
  }

  private func failAndStop(_ code: String) {
    stateOperationID += 1
    startRequested = false
    pendingAuthorizationStart = false
    source?.setBackgroundNavigationEnabled(false)
    source?.stopUpdatingLocation()
    pendingBatches.removeAll(keepingCapacity: true)
    drainTask?.cancel()
    state = .failed(code)
  }

  private var activeStoppedState: ForegroundNavigationLocationState {
    guard consumer?.canConsumeForegroundNavigationLocations == true else {
      return .runtimeUnavailable
    }
    guard let source else {
      return .failed("LOCATION_SOURCE_MISSING")
    }
    switch source.authorizationStatus {
    case .denied, .restricted:
      return .permissionDenied
    case .notDetermined, .authorizedAlways, .authorizedWhenInUse:
      return .idle
    @unknown default:
      return .failed("UNKNOWN_AUTHORIZATION_STATUS")
    }
  }

  private struct LocationBatch {
    let locations: [CLLocation]
    let receivedAt: Date
  }
}

extension ForegroundNavigationLocationController:
  ForegroundNavigationLocationSourceDelegate
{
  func foregroundNavigationLocationSourceDidChangeAuthorization(
    _ source: any ForegroundNavigationLocationSource
  ) {
    switch source.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse:
      if pendingAuthorizationStart, scenePhase != .active {
        state = .sceneInactive
        return
      }
      pendingAuthorizationStart = false
      if startRequested {
        beginUpdates()
      } else if state == .permissionDenied, scenePhase == .active {
        state = .stopped
      }
    case .denied, .restricted:
      stateOperationID += 1
      startRequested = false
      pendingAuthorizationStart = false
      source.setBackgroundNavigationEnabled(false)
      source.stopUpdatingLocation()
      pendingBatches.removeAll(keepingCapacity: true)
      drainTask?.cancel()
      state = .permissionDenied
    case .notDetermined:
      if startRequested {
        state = .awaitingAuthorization
      }
    @unknown default:
      failAndStop("UNKNOWN_AUTHORIZATION_STATUS")
    }
  }

  func foregroundNavigationLocationSource(
    _: any ForegroundNavigationLocationSource,
    didDeliver locations: [CLLocation],
    receivedAt: Date
  ) {
    enqueue(locations: locations, receivedAt: receivedAt)
  }

  func foregroundNavigationLocationSource(
    _: any ForegroundNavigationLocationSource,
    didFailWithCode code: String,
    isTransient: Bool
  ) {
    if isTransient {
      lastTransientFailureCode = code
    } else {
      failAndStop(code)
    }
  }
}
