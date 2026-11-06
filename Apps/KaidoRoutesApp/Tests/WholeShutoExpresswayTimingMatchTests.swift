import KaidoRouting
import XCTest

@testable import KaidoRoutesApp

final class WholeShutoExpresswayTimingMatchTests: XCTestCase {
  // About 2.2 km due east along one latitude.
  private let path = (0...20).map {
    ShutoCoordinate(latitude: 35.65, longitude: 139.75 + Double($0) * 0.0012)
  }
  private let pathDistance = 2_170.0

  func testAcceptsTheSamePathOnTheExpressway() {
    XCTAssertTrue(
      WholeShutoExpresswayTimingMatch.accepts(
        candidate: path, candidateDistanceMeters: pathDistance,
        usesExpressway: true, path: path, pathDistanceMeters: pathDistance))
  }

  func testRejectsTheStreetUnderTheViaduct() {
    XCTAssertFalse(
      WholeShutoExpresswayTimingMatch.accepts(
        candidate: path, candidateDistanceMeters: pathDistance,
        usesExpressway: false, path: path, pathDistanceMeters: pathDistance))
  }

  func testRejectsAParallelRoadBeyondTheDeviationBound() {
    // 0.001° of latitude is about 111 m.
    let parallel = path.map {
      ShutoCoordinate(latitude: $0.latitude + 0.001, longitude: $0.longitude)
    }
    XCTAssertFalse(
      WholeShutoExpresswayTimingMatch.accepts(
        candidate: parallel, candidateDistanceMeters: pathDistance,
        usesExpressway: true, path: path, pathDistanceMeters: pathDistance))
  }

  func testRejectsADetourOutsideTheDistanceTolerance() {
    XCTAssertFalse(
      WholeShutoExpresswayTimingMatch.accepts(
        candidate: path, candidateDistanceMeters: pathDistance * 1.2,
        usesExpressway: true, path: path, pathDistanceMeters: pathDistance))
  }

  func testRejectsARouteThatCoversOnlyPartOfThePath() {
    XCTAssertFalse(
      WholeShutoExpresswayTimingMatch.accepts(
        candidate: Array(path.prefix(10)), candidateDistanceMeters: pathDistance,
        usesExpressway: true, path: path, pathDistanceMeters: pathDistance))
  }
}
