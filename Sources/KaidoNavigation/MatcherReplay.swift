import Foundation

extension MatcherReplayFixture {
  public var validationIssues: [String] {
    var issues: [String] = []

    if schemaVersion != "1.0" { issues.append("unsupported schema_version") }
    if fixtureID.isEmpty { issues.append("fixture_id is empty") }
    if networkSnapshotID.isEmpty { issues.append("network_snapshot_id is empty") }
    if evidenceClassification != "SYNTHETIC" {
      issues.append("tracked replay fixtures must be SYNTHETIC")
    }
    if configuration.ambiguityMarginMeters < 0
      || configuration.staleObservationThresholdMilliseconds < 0
      || configuration.observationGapThresholdMilliseconds < 0
    {
      issues.append("configuration values must be nonnegative")
    }

    let edgeIDs = edges.map(\.id)
    if edges.isEmpty { issues.append("edges are empty") }
    if Set(edgeIDs).count != edgeIDs.count { issues.append("edge IDs are not unique") }
    for edge in edges {
      if edge.id.isEmpty || edge.coordinates.count < 2
        || !edge.coordinates.allSatisfy(\.isValid)
      {
        issues.append("edge \(edge.id) has invalid geometry")
      }
    }

    let occurrenceIDs = routeOccurrences.map(\.occurrenceID)
    let occurrenceIndexes = routeOccurrences.map(\.index)
    if Set(occurrenceIDs).count != occurrenceIDs.count {
      issues.append("occurrence IDs are not unique")
    }
    if occurrenceIndexes.sorted() != Array(0..<routeOccurrences.count) {
      issues.append("occurrence indexes must be contiguous from zero")
    }
    for occurrence in routeOccurrences where !edgeIDs.contains(occurrence.directedEdgeID) {
      issues.append("occurrence \(occurrence.occurrenceID) references an unknown edge")
    }
    if let initialOccurrenceID, !occurrenceIDs.contains(initialOccurrenceID) {
      issues.append("initial occurrence is unknown")
    }

    let observationIDs = observations.map(\.id)
    if observations.isEmpty { issues.append("observations are empty") }
    if Set(observationIDs).count != observationIDs.count {
      issues.append("observation IDs are not unique")
    }
    let receivedTimestamps = observations.map(\.receivedAtMilliseconds)
    if receivedTimestamps != receivedTimestamps.sorted() {
      issues.append("observations must be ordered by received_at_ms")
    }
    for observation in observations {
      if observation.id.isEmpty || !observation.coordinate.isValid
        || !observation.horizontalAccuracyMeters.isFinite
        || observation.horizontalAccuracyMeters <= 0
        || observation.receivedAtMilliseconds < observation.observedAtMilliseconds
      {
        issues.append("observation \(observation.id) is invalid")
      }
      if let course = observation.courseDegrees,
        !course.isFinite || !(0..<360).contains(course)
      {
        issues.append("observation \(observation.id) has invalid course")
      }
      if let speed = observation.speedMetersPerSecond,
        !speed.isFinite || speed < 0
      {
        issues.append("observation \(observation.id) has invalid speed")
      }
    }

    var occurrencesByID: [String: MatcherRouteOccurrenceBinding] = [:]
    for occurrence in routeOccurrences where occurrencesByID[occurrence.occurrenceID] == nil {
      occurrencesByID[occurrence.occurrenceID] = occurrence
    }
    for interval in groundTruthIntervals {
      if interval.startMilliseconds > interval.endMilliseconds {
        issues.append("ground-truth interval has reversed time")
      }
      if !edgeIDs.contains(interval.directedEdgeID) {
        issues.append("ground-truth interval references an unknown edge")
      }
      if interval.classification == .onRoute, interval.occurrenceID == nil {
        issues.append("ON_ROUTE ground truth requires an occurrence")
      }
      if interval.classification == .deviation, interval.occurrenceID != nil {
        issues.append("DEVIATION ground truth must not claim a route occurrence")
      }
      if let occurrenceID = interval.occurrenceID {
        guard let occurrence = occurrencesByID[occurrenceID] else {
          issues.append("ground-truth interval references an unknown occurrence")
          continue
        }
        if occurrence.directedEdgeID != interval.directedEdgeID {
          issues.append("ground-truth occurrence and edge disagree")
        }
      }
    }
    let sortedIntervals = groundTruthIntervals.sorted {
      if $0.startMilliseconds == $1.startMilliseconds {
        return $0.endMilliseconds < $1.endMilliseconds
      }
      return $0.startMilliseconds < $1.startMilliseconds
    }
    for pair in zip(sortedIntervals, sortedIntervals.dropFirst())
    where pair.0.endMilliseconds >= pair.1.startMilliseconds {
      issues.append("ground-truth intervals overlap")
    }
    for observation in observations {
      let matches = groundTruthIntervals.filter {
        $0.contains(observation.observedAtMilliseconds)
      }
      if matches.count != 1 {
        issues.append("observation \(observation.id) must have exactly one truth interval")
      }
    }

    let decisionIDs = branchDecisions.map(\.id)
    if Set(decisionIDs).count != decisionIDs.count {
      issues.append("branch decision IDs are not unique")
    }
    for decision in branchDecisions {
      if !edgeIDs.contains(decision.plannedOutgoingEdgeID)
        || !edgeIDs.contains(decision.actualOutgoingEdgeID)
      {
        issues.append("branch decision \(decision.id) references an unknown edge")
      }
      if let actualOccurrenceID = decision.actualOccurrenceID {
        guard let occurrence = occurrencesByID[actualOccurrenceID] else {
          issues.append("branch decision \(decision.id) references an unknown occurrence")
          continue
        }
        if occurrence.directedEdgeID != decision.actualOutgoingEdgeID {
          issues.append("branch decision \(decision.id) occurrence and edge disagree")
        }
      }
    }

    if Set(expectedNegativeControlFailures).count
      != expectedNegativeControlFailures.count
    {
      issues.append("expected negative-control failures are not unique")
    }
    return Array(Set(issues)).sorted()
  }
}

/// Deliberately weak geometry-only baseline.
///
/// It ignores heading, graph transitions, route occurrences, observation age,
/// and source. The replay corpus keeps this implementation as a negative control
/// so a sophisticated matcher cannot appear useful merely by beating no baseline.
public struct NearestEdgeNegativeControl: Sendable {
  public static let algorithmID = "nearest-directed-edge-negative-control-v1"

  public init() {}

  public func run(fixture: MatcherReplayFixture) throws -> MatcherReplayReport {
    let issues = fixture.validationIssues
    guard issues.isEmpty else { throw MatcherReplayError.invalidFixture(issues) }

    let measuredEdges = fixture.edges.map(MeasuredMatcherEdge.init)
    let estimates = fixture.observations.map { observation in
      estimate(observation: observation, edges: measuredEdges, fixture: fixture)
    }
    return try MatcherReplayEvaluator.evaluate(
      fixture: fixture,
      algorithmID: Self.algorithmID,
      estimates: estimates,
      expectedSafetyFailures: fixture.expectedNegativeControlFailures
    )
  }

  private func estimate(
    observation: MatcherReplayObservation,
    edges: [MeasuredMatcherEdge],
    fixture: MatcherReplayFixture
  ) -> MatcherEstimate {
    let ranked =
      edges
      .map { edge in
        (edge.id, edge.distanceMeters(to: observation.coordinate))
      }
      .sorted {
        if abs($0.1 - $1.1) < 0.000_001 { return $0.0 < $1.0 }
        return $0.1 < $1.1
      }
    guard let best = ranked.first else {
      return MatcherEstimate(
        observationID: observation.id,
        estimatedAtMilliseconds: observation.observedAtMilliseconds,
        directedEdgeID: nil,
        occurrenceID: nil,
        candidateEdgeIDs: [],
        confidence: .lost,
        distanceMeters: nil
      )
    }

    let candidateEdgeIDs =
      ranked
      .filter { $0.1 <= best.1 + fixture.configuration.ambiguityMarginMeters }
      .map(\.0)
      .sorted()
    let confidence: MatcherConfidence
    if best.1 <= max(3, observation.horizontalAccuracyMeters) {
      confidence = .high
    } else if best.1 <= observation.horizontalAccuracyMeters * 2 {
      confidence = .medium
    } else {
      confidence = .low
    }
    return MatcherEstimate(
      observationID: observation.id,
      estimatedAtMilliseconds: observation.observedAtMilliseconds,
      directedEdgeID: best.0,
      occurrenceID: nil,
      candidateEdgeIDs: candidateEdgeIDs,
      confidence: confidence,
      distanceMeters: best.1
    )
  }
}

public enum MatcherReplayEvaluator {
  public static func evaluate(
    fixture: MatcherReplayFixture,
    algorithmID: String,
    estimates: [MatcherEstimate],
    expectedSafetyFailures: [MatcherSafetyFailure]? = nil
  ) throws -> MatcherReplayReport {
    let issues = fixture.validationIssues
    guard issues.isEmpty else { throw MatcherReplayError.invalidFixture(issues) }

    var estimatesByObservationID: [String: MatcherEstimate] = [:]
    for estimate in estimates {
      guard let observationID = estimate.observationID else { continue }
      guard estimatesByObservationID[observationID] == nil else {
        throw MatcherReplayError.duplicateEstimate(observationID)
      }
      estimatesByObservationID[observationID] = estimate
    }

    var failures: Set<MatcherSafetyFailure> = []
    var edgeTop1CorrectCount = 0
    var occurrenceTruthCount = 0
    var occurrenceCorrectCount = 0

    for observation in fixture.observations {
      guard let estimate = estimatesByObservationID[observation.id] else {
        throw MatcherReplayError.missingEstimate(observation.id)
      }
      let truth = fixture.groundTruthIntervals.first {
        $0.contains(observation.observedAtMilliseconds)
      }!
      if estimate.directedEdgeID == truth.directedEdgeID {
        edgeTop1CorrectCount += 1
      } else if estimate.confidence == .high {
        failures.insert(.falseHighConfidenceEdgeMatch)
      }
      if let occurrenceID = truth.occurrenceID {
        occurrenceTruthCount += 1
        if estimate.occurrenceID == occurrenceID {
          occurrenceCorrectCount += 1
        } else if estimate.occurrenceID == nil {
          failures.insert(.routeOccurrenceUnavailable)
        }
      }
      if estimate.candidateEdgeIDs.count > 1, estimate.confidence == .high {
        failures.insert(.highConfidenceAmbiguity)
      }
      if observation.receivedAtMilliseconds - observation.observedAtMilliseconds
        >= fixture.configuration.staleObservationThresholdMilliseconds,
        estimate.confidence == .high
      {
        failures.insert(.highConfidenceStaleObservation)
      }
    }

    for decision in fixture.branchDecisions {
      let postDecisionObservation = fixture.observations
        .filter { observation in
          guard observation.observedAtMilliseconds >= decision.atMilliseconds else {
            return false
          }
          return fixture.groundTruthIntervals.contains { interval in
            interval.contains(observation.observedAtMilliseconds)
              && interval.directedEdgeID == decision.actualOutgoingEdgeID
          }
        }
        .min { $0.observedAtMilliseconds < $1.observedAtMilliseconds }
      if let postDecisionObservation,
        let estimate = estimatesByObservationID[postDecisionObservation.id],
        estimate.confidence == .high,
        estimate.directedEdgeID != decision.actualOutgoingEdgeID
      {
        failures.insert(.falseHighConfidenceBranchCommit)
      }
    }

    let occurrenceIndexes = Dictionary(
      uniqueKeysWithValues: fixture.routeOccurrences.map { ($0.occurrenceID, $0.index) }
    )
    var lastOccurrenceIndex = fixture.initialOccurrenceID.flatMap { occurrenceIndexes[$0] }
    for observation in fixture.observations {
      guard let occurrenceID = estimatesByObservationID[observation.id]?.occurrenceID,
        let occurrenceIndex = occurrenceIndexes[occurrenceID]
      else { continue }
      if let lastOccurrenceIndex, occurrenceIndex < lastOccurrenceIndex {
        failures.insert(.backwardOccurrenceJump)
      }
      lastOccurrenceIndex = max(lastOccurrenceIndex ?? occurrenceIndex, occurrenceIndex)
    }

    let orderedObservationTimes = fixture.observations
      .map(\.observedAtMilliseconds)
      .sorted()
    let observationGaps = zip(orderedObservationTimes, orderedObservationTimes.dropFirst())
      .map { $1 - $0 }
      .filter { $0 >= fixture.configuration.observationGapThresholdMilliseconds }

    for estimate in estimates where estimate.observationID == nil && estimate.confidence == .high {
      let commitsInsideGap = zip(orderedObservationTimes, orderedObservationTimes.dropFirst())
        .contains { before, after in
          guard after - before >= fixture.configuration.observationGapThresholdMilliseconds,
            before < estimate.estimatedAtMilliseconds,
            estimate.estimatedAtMilliseconds < after
          else { return false }
          return fixture.branchDecisions.contains {
            before < $0.atMilliseconds && $0.atMilliseconds < after
          }
        }
      if commitsInsideGap { failures.insert(.branchCommitDuringObservationGap) }
    }

    let sortedFailures = failures.sorted { $0.rawValue < $1.rawValue }
    let sortedExpectedFailures = expectedSafetyFailures?.sorted {
      $0.rawValue < $1.rawValue
    }
    return MatcherReplayReport(
      fixtureID: fixture.fixtureID,
      algorithmID: algorithmID,
      estimates: estimates,
      metrics: MatcherReplayMetrics(
        observationCount: fixture.observations.count,
        edgeTop1CorrectCount: edgeTop1CorrectCount,
        occurrenceTruthCount: occurrenceTruthCount,
        occurrenceCorrectCount: occurrenceCorrectCount,
        observationGapDurationsMilliseconds: observationGaps
      ),
      safetyFailures: sortedFailures,
      expectedSafetyFailures: sortedExpectedFailures,
      expectationMatched: sortedExpectedFailures.map { sortedFailures == $0 }
    )
  }
}

private struct MeasuredMatcherEdge: Sendable {
  let id: String
  let coordinates: [MatcherCoordinate]

  init(edge: MatcherReplayEdge) {
    self.id = edge.id
    self.coordinates = edge.coordinates
  }

  func distanceMeters(to point: MatcherCoordinate) -> Double {
    zip(coordinates, coordinates.dropFirst())
      .map { pointToSegmentDistance(point: point, segmentStart: $0, segmentEnd: $1) }
      .min() ?? .infinity
  }
}

private let matcherEarthRadiusMeters = 6_371_000.0

private func pointToSegmentDistance(
  point: MatcherCoordinate,
  segmentStart: MatcherCoordinate,
  segmentEnd: MatcherCoordinate
) -> Double {
  let referenceLatitude =
    (point.latitude + segmentStart.latitude + segmentEnd.latitude) / 3
  let longitudeScale = cos(referenceLatitude * .pi / 180)
  func projected(_ coordinate: MatcherCoordinate) -> (x: Double, y: Double) {
    (
      x: coordinate.longitude * .pi / 180 * matcherEarthRadiusMeters * longitudeScale,
      y: coordinate.latitude * .pi / 180 * matcherEarthRadiusMeters
    )
  }
  let projectedPoint = projected(point)
  let projectedStart = projected(segmentStart)
  let projectedEnd = projected(segmentEnd)
  let deltaX = projectedEnd.x - projectedStart.x
  let deltaY = projectedEnd.y - projectedStart.y
  let lengthSquared = deltaX * deltaX + deltaY * deltaY
  guard lengthSquared > 0 else {
    return hypot(projectedPoint.x - projectedStart.x, projectedPoint.y - projectedStart.y)
  }
  let unboundedFraction =
    ((projectedPoint.x - projectedStart.x) * deltaX
      + (projectedPoint.y - projectedStart.y) * deltaY) / lengthSquared
  let fraction = min(1, max(0, unboundedFraction))
  let nearestX = projectedStart.x + fraction * deltaX
  let nearestY = projectedStart.y + fraction * deltaY
  return hypot(projectedPoint.x - nearestX, projectedPoint.y - nearestY)
}
