import KaidoNavigation
import XCTest

@testable import KaidoRoutesApp

final class NavigationDirectionPresentationTests: XCTestCase {
  @MainActor
  func testUnitTestHostUsesSilentNavigationOutput() {
    XCTAssertTrue(AppGuidanceSpeechOutputFactory.isSilent)
  }

  func testProviderTurnTextSelectsTheSameDirectionInSupportedLanguages() {
    let cases: [(String, SurfaceManeuver)] = [
      ("稍向左转，朝 Hatchobori 方向进入", .slightLeft),
      ("左折して八重洲通りに入る", .left),
      ("Turn right onto Left Street", .right),
      ("Keep left at the fork", .slightLeft),
      ("右方向へ進む", .slightRight),
      ("右轉進入八重洲通", .right),
      ("Continue straight", .straight),
      ("Uターンしてください", .uTurn),
      ("Turn left, then turn right", .left),
      ("Continue onto Left Street", .unknown),
      ("Arrive on the right", .unknown),
      ("Turn leftwood avenue", .unknown),
      ("", .unknown),
    ]
    for (text, maneuver) in cases {
      XCTAssertEqual(SurfaceManeuver.from(instruction: text), maneuver, text)
    }
  }

  func testFollowingAnyCardinalDirectionKeepsTheVehiclePointingForward() {
    for bearing in [0.0, 90, 180, 270] {
      for pitch in [0.0, 45, 60] {
        XCTAssertEqual(
          NavigationDirectionPresentation.screenAngle(
            bearing: bearing, cameraHeading: bearing, cameraPitch: pitch
          ), 0, accuracy: 0.001
        )
      }
    }
  }

  func testBrowsingRotationAndNorthCrossingPreserveTheVehicleDirection() {
    XCTAssertEqual(
      NavigationDirectionPresentation.screenAngle(
        bearing: 90, cameraHeading: 0, cameraPitch: 0
      ), 90, accuracy: 0.001
    )
    XCTAssertEqual(
      NavigationDirectionPresentation.screenAngle(
        bearing: 0, cameraHeading: 90, cameraPitch: 45
      ), -90, accuracy: 0.001
    )
    XCTAssertEqual(
      NavigationDirectionPresentation.screenAngle(
        bearing: 1, cameraHeading: 359, cameraPitch: 0
      ), 2, accuracy: 0.001
    )
    XCTAssertEqual(
      NavigationDirectionPresentation.screenAngle(
        bearing: 359, cameraHeading: 1, cameraPitch: 0
      ), -2, accuracy: 0.001
    )
  }

  func testStationaryUncertainAndStaleFixesDoNotClaimVehicleDirection() {
    func course(speed: Double = 10, accuracy: Double? = 5, age: Int = 0) -> Double? {
      NavigationDirectionPresentation.vehicleCourse(
        from: RouteMatcherObservation(
          observedAtMilliseconds: 1_000,
          receivedAtMilliseconds: 1_000 + age,
          coordinate: MatcherCoordinate(latitude: 35.68, longitude: 139.76),
          horizontalAccuracyMeters: 5,
          courseDegrees: 270,
          courseAccuracyDegrees: accuracy,
          speedMetersPerSecond: speed,
          source: .phone
        )
      )
    }
    XCTAssertEqual(course(), 270)
    XCTAssertNil(course(speed: 0))
    XCTAssertNil(course(speed: 1))
    XCTAssertNil(course(accuracy: nil))
    XCTAssertNil(course(accuracy: 60))
    XCTAssertNil(course(age: 10_000))
    XCTAssertNil(course(age: -1))
  }
}
