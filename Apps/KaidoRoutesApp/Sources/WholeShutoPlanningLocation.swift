import Combine
import CoreLocation
import Foundation
import KaidoRouting

enum WholeShutoPlanningLocationState: Equatable {
  case idle
  case permissionRequired
  case locating
  case measured
  case denied
  case unavailable
}

struct WholeShutoPlanningLocationSnapshot: Equatable {
  let coordinate: ShutoCoordinate
  let horizontalAccuracyMeters: Double
  let courseDegrees: Double?
  let measuredAt: Date
}

@MainActor
final class WholeShutoPlanningLocationController:
  NSObject,
  ObservableObject,
  @preconcurrency CLLocationManagerDelegate
{
  @Published private(set) var state: WholeShutoPlanningLocationState = .idle
  @Published private(set) var snapshot: WholeShutoPlanningLocationSnapshot?

  private let manager: CLLocationManager
  private var wantsLocation = false
  private var isForeground = true

  init(manager: CLLocationManager = CLLocationManager()) {
    self.manager = manager
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBest
    manager.distanceFilter = 5
    updateAuthorizationState()
  }

  func requestCurrentLocation() {
    wantsLocation = true
    updateAuthorizationState()
    switch manager.authorizationStatus {
    case .notDetermined:
      state = .permissionRequired
      manager.requestWhenInUseAuthorization()
    case .authorizedAlways, .authorizedWhenInUse:
      startIfEligible()
    case .denied, .restricted:
      state = .denied
    @unknown default:
      state = .unavailable
    }
  }

  func setForeground(_ foreground: Bool) {
    isForeground = foreground
    if foreground {
      updateAuthorizationState()
      startIfEligible()
    } else {
      manager.stopUpdatingLocation()
    }
  }

  func stop() {
    wantsLocation = false
    manager.stopUpdatingLocation()
    updateAuthorizationState()
  }

  func locationManagerDidChangeAuthorization(_: CLLocationManager) {
    updateAuthorizationState()
    startIfEligible()
  }

  func locationManager(
    _: CLLocationManager,
    didUpdateLocations locations: [CLLocation]
  ) {
    guard
      let location = locations.last(where: {
        $0.horizontalAccuracy >= 0
          && $0.coordinate.latitude.isFinite
          && $0.coordinate.longitude.isFinite
      })
    else {
      state = .unavailable
      return
    }
    snapshot = WholeShutoPlanningLocationSnapshot(
      coordinate: ShutoCoordinate(
        latitude: location.coordinate.latitude,
        longitude: location.coordinate.longitude
      ),
      horizontalAccuracyMeters: location.horizontalAccuracy,
      courseDegrees:
        location.course >= 0 && location.course < 360
        ? location.course : nil,
      measuredAt: location.timestamp
    )
    state = .measured
  }

  func locationManager(_: CLLocationManager, didFailWithError _: Error) {
    state = snapshot == nil ? .unavailable : .measured
  }

  private func updateAuthorizationState() {
    switch manager.authorizationStatus {
    case .notDetermined:
      state = .permissionRequired
    case .authorizedAlways, .authorizedWhenInUse:
      state = snapshot == nil ? (wantsLocation ? .locating : .idle) : .measured
    case .denied, .restricted:
      state = .denied
    @unknown default:
      state = .unavailable
    }
  }

  private func startIfEligible() {
    guard wantsLocation, isForeground else { return }
    switch manager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse:
      state = snapshot == nil ? .locating : .measured
      manager.startUpdatingLocation()
    case .notDetermined, .denied, .restricted:
      break
    @unknown default:
      state = .unavailable
    }
  }
}
