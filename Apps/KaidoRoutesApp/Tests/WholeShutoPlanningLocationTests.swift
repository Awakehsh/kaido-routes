import CoreLocation
import XCTest

@testable import KaidoRoutesApp

@MainActor
final class WholeShutoPlanningLocationTests: XCTestCase {
  func testASettledFixStopsUpdatesUntilTheDriverAsksAgain() {
    let manager = RecordingPlanningLocationManager()
    let controller = WholeShutoPlanningLocationController(manager: manager)

    controller.requestCurrentLocation()
    XCTAssertEqual(manager.startCount, 1)

    controller.locationManager(manager, didUpdateLocations: [fix(accuracy: 1_000)])
    XCTAssertEqual(controller.state, .measured)
    XCTAssertEqual(manager.stopCount, 0, "A coarse fix keeps refining")

    controller.locationManager(manager, didUpdateLocations: [fix(accuracy: 8)])
    XCTAssertEqual(controller.state, .measured)
    XCTAssertEqual(controller.snapshot?.horizontalAccuracyMeters, 8)
    XCTAssertEqual(manager.stopCount, 1)

    controller.requestCurrentLocation()
    XCTAssertEqual(manager.startCount, 2)
    controller.locationManager(manager, didUpdateLocations: [fix(accuracy: 5)])
    XCTAssertEqual(manager.stopCount, 2)

    controller.setForeground(false)
    controller.setForeground(true)
    XCTAssertEqual(manager.startCount, 3)
    XCTAssertEqual(controller.state, .measured)
  }

  private func fix(accuracy: CLLocationAccuracy) -> CLLocation {
    CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: 35.6586, longitude: 139.7454),
      altitude: 0,
      horizontalAccuracy: accuracy,
      verticalAccuracy: -1,
      timestamp: Date()
    )
  }
}

private final class RecordingPlanningLocationManager: CLLocationManager {
  var startCount = 0
  var stopCount = 0

  override var authorizationStatus: CLAuthorizationStatus { .authorizedWhenInUse }
  override func startUpdatingLocation() { startCount += 1 }
  override func stopUpdatingLocation() { stopCount += 1 }
}
