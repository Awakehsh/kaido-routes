import Foundation

/// What the drive did, accumulated from the fixes the drive already consumes.
///
/// This is a record and only a record. It reports what happened and never
/// compares it: no target, no goal, no previous drive, no other driver, and
/// nothing that reads as an invitation to go faster. The driver can switch the
/// whole thing off.
struct WholeShutoDriveRecord: Equatable, Sendable {
  /// One completed lap of a loop circuit.
  struct LapSplit: Equatable, Sendable, Identifiable {
    let lapNumber: Int
    let durationMilliseconds: Int

    var id: Int { lapNumber }
  }

  /// A fix arriving more than this long after the last one opens a new
  /// segment rather than extending the old one. A tunnel, a rest, or a
  /// backgrounded app must not be integrated as if the car held its last
  /// speed throughout.
  static let maximumSampleGapMilliseconds = 10_000

  private(set) var maximumSpeedMetersPerSecond: Double?
  private(set) var minimumSpeedMetersPerSecond: Double?
  private(set) var completedLaps: [LapSplit] = []
  private(set) var currentLapNumber: Int?

  private var speedTimeIntegral = 0.0
  private var integratedMilliseconds = 0
  private var lastSampleAtMilliseconds: Int?
  private var lastSpeedMetersPerSecond: Double?
  private var currentLapStartedAtMilliseconds: Int?
  private var crossedBoundaryIndex = -1

  /// Time-weighted so a burst of fixes in slow traffic cannot outvote a long
  /// steady stretch. Absent until two fixes have bounded an interval.
  var averageSpeedMetersPerSecond: Double? {
    guard integratedMilliseconds > 0 else { return nil }
    return speedTimeIntegral / (Double(integratedMilliseconds) / 1_000)
  }

  var hasSpeedRecord: Bool { maximumSpeedMetersPerSecond != nil }

  var hasLapRecord: Bool {
    !completedLaps.isEmpty || currentLapNumber != nil
  }

  /// Records one fix. A negative speed is Core Location saying it does not
  /// know, which is absent evidence rather than a stop.
  mutating func observe(
    speedMetersPerSecond: Double?,
    atMilliseconds milliseconds: Int
  ) {
    guard let speed = speedMetersPerSecond,
      speed.isFinite,
      speed >= 0
    else {
      lastSampleAtMilliseconds = nil
      lastSpeedMetersPerSecond = nil
      return
    }

    maximumSpeedMetersPerSecond = max(maximumSpeedMetersPerSecond ?? speed, speed)
    minimumSpeedMetersPerSecond = min(minimumSpeedMetersPerSecond ?? speed, speed)

    defer {
      lastSampleAtMilliseconds = milliseconds
      lastSpeedMetersPerSecond = speed
    }
    guard let previousAt = lastSampleAtMilliseconds,
      let previousSpeed = lastSpeedMetersPerSecond
    else {
      return
    }
    let gap = milliseconds - previousAt
    guard gap > 0, gap <= Self.maximumSampleGapMilliseconds else { return }
    // Trapezoid over the interval: the car did not teleport between fixes.
    speedTimeIntegral +=
      (previousSpeed + speed) / 2 * (Double(gap) / 1_000)
    integratedMilliseconds += gap
  }

  /// Advances the lap ledger from the plan occurrence the matcher resolved.
  ///
  /// `boundaries` is `ShutoPlannedRoute.lapBoundaryOccurrenceIndices`: `n`
  /// laps carry `n + 1` marks, so crossing the last one closes the final lap
  /// without opening another.
  mutating func observe(
    occurrenceIndex: Int,
    boundaries: [Int],
    atMilliseconds milliseconds: Int
  ) {
    guard boundaries.count >= 2 else { return }
    while crossedBoundaryIndex + 1 < boundaries.count,
      occurrenceIndex >= boundaries[crossedBoundaryIndex + 1]
    {
      crossedBoundaryIndex += 1
      if let lapNumber = currentLapNumber,
        let startedAt = currentLapStartedAtMilliseconds
      {
        completedLaps.append(
          LapSplit(
            lapNumber: lapNumber,
            durationMilliseconds: max(0, milliseconds - startedAt)
          )
        )
      }
      if crossedBoundaryIndex < boundaries.count - 1 {
        currentLapNumber = crossedBoundaryIndex + 1
        currentLapStartedAtMilliseconds = milliseconds
      } else {
        currentLapNumber = nil
        currentLapStartedAtMilliseconds = nil
      }
    }
  }
}
