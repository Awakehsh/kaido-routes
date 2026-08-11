import CoreLocation
import Foundation
import KaidoAppleAdapters
import KaidoDomain
import KaidoNavigation
import SwiftUI

/// Foreground location for a live whole-Shuto drive.
///
/// Only when-in-use authorization is ever requested and background updates
/// stay off, so the drive is honestly foreground-scoped. Device fixes become
/// domain observations through the shared adapter, which keeps invalid,
/// stale, and (in shipped builds) simulated fixes out rather than letting
/// them reach the matcher.
@MainActor
final class WholeShutoLiveLocationController: NSObject, ObservableObject {
  enum State: Equatable {
    case idle
    case awaitingAuthorization
    case running
    case permissionDenied
    case stopped
    case failed(String)
  }

  @Published private(set) var state: State = .idle
  @Published private(set) var lastRejectionReason: String?

  /// Delivered on the main actor in fix order. The envelope is retained so
  /// release-bound entry and egress adapters can reject simulated evidence.
  var onObservation: ((CoreLocationObservationEnvelope) -> Void)?
  var onStateChange: ((State, String?) -> Void)?

  private let manager = CLLocationManager()
  private var adapter: CoreLocationObservationAdapter?
  private var sessionID: String?
  private var startRequested = false

  override init() {
    super.init()
    manager.delegate = self
    manager.activityType = .automotiveNavigation
    manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    manager.distanceFilter = kCLDistanceFilterNone
    manager.pausesLocationUpdatesAutomatically = false
    manager.allowsBackgroundLocationUpdates = false
    manager.showsBackgroundLocationIndicator = false
  }

  var isRunning: Bool { state == .running }

  /// Starts a drive. `sessionID` scopes the minted observation IDs to one
  /// exact route plan so two drives can never interleave identifiers.
  func start(sessionID: String) {
    guard state != .running else { return }
    self.sessionID = sessionID
    lastRejectionReason = nil
    do {
      adapter = try CoreLocationObservationAdapter(
        sessionID: sessionID,
        // A shipped drive refuses spoofed fixes; simulator and device
        // rehearsals need them, so only Debug builds accept them.
        simulatedLocationPolicy: {
          #if DEBUG
            .allowForTesting
          #else
            .reject
          #endif
        }()
      )
    } catch {
      publish(.failed("OBSERVATION_ADAPTER_UNAVAILABLE"))
      return
    }
    startRequested = true
    switch manager.authorizationStatus {
    case .notDetermined:
      publish(.awaitingAuthorization)
      manager.requestWhenInUseAuthorization()
    case .restricted, .denied:
      publish(.permissionDenied)
    case .authorizedWhenInUse, .authorizedAlways:
      beginUpdates()
    @unknown default:
      publish(.failed("CORE_LOCATION_UNKNOWN_AUTHORIZATION"))
    }
  }

  func stop() {
    startRequested = false
    manager.stopUpdatingLocation()
    adapter = nil
    sessionID = nil
    if state != .permissionDenied {
      publish(.stopped)
    }
  }

  private func beginUpdates() {
    guard startRequested else { return }
    manager.startUpdatingLocation()
    publish(.running)
  }

  private func publish(
    _ state: State,
    rejectionReason: String? = nil
  ) {
    self.state = state
    lastRejectionReason = rejectionReason
    onStateChange?(state, rejectionReason)
  }
}

extension WholeShutoLiveLocationController: CLLocationManagerDelegate {
  nonisolated func locationManagerDidChangeAuthorization(
    _ manager: CLLocationManager
  ) {
    let status = manager.authorizationStatus
    Task { @MainActor in
      switch status {
      case .authorizedWhenInUse, .authorizedAlways:
        if self.startRequested { self.beginUpdates() }
      case .denied, .restricted:
        self.publish(.permissionDenied)
      case .notDetermined:
        break
      @unknown default:
        break
      }
    }
  }

  nonisolated func locationManager(
    _ manager: CLLocationManager,
    didUpdateLocations locations: [CLLocation]
  ) {
    let receivedAt = Date()
    Task { @MainActor in
      guard self.state == .running, var adapter = self.adapter else {
        return
      }
      let results = adapter.adapt(locations, receivedAt: receivedAt)
      self.adapter = adapter
      for result in results {
        switch result {
        case .accepted(let envelope):
          self.lastRejectionReason = nil
          self.onObservation?(envelope)
        case .rejected(let rejection):
          self.publish(
            .running,
            rejectionReason: rejection.reason.rawValue
          )
        }
      }
    }
  }

  nonisolated func locationManager(
    _ manager: CLLocationManager,
    didFailWithError error: Error
  ) {
    let code = (error as? CLError)?.code
    Task { @MainActor in
      // A momentary unknown location is normal in tunnels and urban
      // canyons; it degrades confidence rather than ending the drive.
      guard code != .locationUnknown else {
        self.publish(
          .running,
          rejectionReason: "CORE_LOCATION_LOCATION_UNKNOWN"
        )
        return
      }
      self.publish(.failed(
        code.map { "CORE_LOCATION_\($0.rawValue)" }
          ?? "CORE_LOCATION_FAILURE"
      ))
      self.manager.stopUpdatingLocation()
    }
  }
}
