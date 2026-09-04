import XCTest

@testable import KaidoRoutesApp

final class WholeShutoDriveRecordTests: XCTestCase {
  func testSpeedRecordIsTimeWeightedAndBoundedByRealSamples() {
    var record = WholeShutoDriveRecord()
    XCTAssertNil(record.averageSpeedMetersPerSecond)
    XCTAssertFalse(record.hasSpeedRecord)

    // Ten seconds at 20 m/s, then ten at 10 m/s: the trapezoid over each
    // interval averages 15 m/s across the twenty seconds.
    record.observe(speedMetersPerSecond: 20, atMilliseconds: 0)
    record.observe(speedMetersPerSecond: 20, atMilliseconds: 10_000)
    record.observe(speedMetersPerSecond: 10, atMilliseconds: 15_000)
    record.observe(speedMetersPerSecond: 10, atMilliseconds: 20_000)

    XCTAssertEqual(record.maximumSpeedMetersPerSecond, 20)
    XCTAssertEqual(record.minimumSpeedMetersPerSecond, 10)
    XCTAssertEqual(
      try XCTUnwrap(record.averageSpeedMetersPerSecond),
      16.25,
      accuracy: 0.001
    )
    XCTAssertTrue(record.hasSpeedRecord)
  }

  func testUnknownSpeedIsAbsentEvidenceNotAStop() {
    var record = WholeShutoDriveRecord()
    record.observe(speedMetersPerSecond: 25, atMilliseconds: 0)
    record.observe(speedMetersPerSecond: -1, atMilliseconds: 1_000)
    record.observe(speedMetersPerSecond: nil, atMilliseconds: 2_000)
    record.observe(speedMetersPerSecond: 25, atMilliseconds: 3_000)

    // Core Location reporting a negative speed means it does not know. That
    // must not become a 0 km/h minimum, and it must not be integrated.
    XCTAssertEqual(record.minimumSpeedMetersPerSecond, 25)
    XCTAssertEqual(record.maximumSpeedMetersPerSecond, 25)
    XCTAssertNil(record.averageSpeedMetersPerSecond)
  }

  func testALongGapOpensANewSegmentInsteadOfHoldingTheLastSpeed() {
    var record = WholeShutoDriveRecord()
    record.observe(speedMetersPerSecond: 30, atMilliseconds: 0)
    // A tunnel, a rest, or a backgrounded app: the car did not hold 30 m/s
    // for the whole minute, so the interval is not integrated.
    record.observe(speedMetersPerSecond: 30, atMilliseconds: 60_000)
    XCTAssertNil(record.averageSpeedMetersPerSecond)

    record.observe(speedMetersPerSecond: 30, atMilliseconds: 62_000)
    XCTAssertEqual(
      try XCTUnwrap(record.averageSpeedMetersPerSecond),
      30,
      accuracy: 0.001
    )
  }

  func testLapsCloseOnBoundaryCrossingsAndTheLastLapDoesNotReopen() {
    // Two laps over a plan whose ring spans occurrences 5..<15 and 15..<25.
    let boundaries = [5, 15, 25]
    var record = WholeShutoDriveRecord()

    record.observe(occurrenceIndex: 2, boundaries: boundaries, atMilliseconds: 0)
    XCTAssertNil(record.currentLapNumber)
    XCTAssertTrue(record.completedLaps.isEmpty)

    record.observe(occurrenceIndex: 5, boundaries: boundaries, atMilliseconds: 1_000)
    XCTAssertEqual(record.currentLapNumber, 1)
    XCTAssertTrue(record.completedLaps.isEmpty)

    record.observe(occurrenceIndex: 12, boundaries: boundaries, atMilliseconds: 300_000)
    XCTAssertEqual(record.currentLapNumber, 1)

    record.observe(occurrenceIndex: 16, boundaries: boundaries, atMilliseconds: 601_000)
    XCTAssertEqual(record.currentLapNumber, 2)
    XCTAssertEqual(record.completedLaps.count, 1)
    XCTAssertEqual(record.completedLaps[0].lapNumber, 1)
    XCTAssertEqual(record.completedLaps[0].durationMilliseconds, 600_000)

    // Crossing the final boundary closes lap 2 and opens nothing: the exit
    // tail is not a lap.
    record.observe(occurrenceIndex: 25, boundaries: boundaries, atMilliseconds: 1_200_000)
    XCTAssertNil(record.currentLapNumber)
    XCTAssertEqual(record.completedLaps.count, 2)
    XCTAssertEqual(record.completedLaps[1].lapNumber, 2)
    XCTAssertEqual(record.completedLaps[1].durationMilliseconds, 599_000)

    record.observe(occurrenceIndex: 30, boundaries: boundaries, atMilliseconds: 1_300_000)
    XCTAssertEqual(record.completedLaps.count, 2)
  }

  func testASingleFixCanCloseSeveralBoundariesAtOnce() {
    // A tunnel or a dropped signal can leave the matcher's next resolved
    // occurrence well past a lap boundary. Every crossed lap still closes.
    let boundaries = [0, 10, 20]
    var record = WholeShutoDriveRecord()
    record.observe(occurrenceIndex: 0, boundaries: boundaries, atMilliseconds: 0)
    record.observe(occurrenceIndex: 22, boundaries: boundaries, atMilliseconds: 900_000)

    XCTAssertEqual(record.completedLaps.count, 2)
    XCTAssertNil(record.currentLapNumber)
  }

  func testARouteWithoutLapsRecordsNone() {
    var record = WholeShutoDriveRecord()
    record.observe(occurrenceIndex: 4, boundaries: [], atMilliseconds: 0)
    record.observe(occurrenceIndex: 9, boundaries: [3], atMilliseconds: 1_000)

    XCTAssertFalse(record.hasLapRecord)
    XCTAssertTrue(record.completedLaps.isEmpty)
    XCTAssertNil(record.currentLapNumber)
  }
}
