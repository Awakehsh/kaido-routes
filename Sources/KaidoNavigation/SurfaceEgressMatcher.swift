import Foundation

/// One immutable occurrence in a compiled ordinary-road egress path.
public struct SurfaceEgressMatcherOccurrence: Equatable, Sendable {
  public let id: String
  public let index: Int
  public let directedEdgeID: String
  public let coordinates: [MatcherCoordinate]

  package init(
    id: String,
    index: Int,
    directedEdgeID: String,
    coordinates: [MatcherCoordinate]
  ) {
    self.id = id
    self.index = index
    self.directedEdgeID = directedEdgeID
    self.coordinates = coordinates
  }
}

/// Exact graph geometry retained from one compiler-admitted surface route.
///
/// This corridor is separate from the Shuto `RouteMatcherCorridor`. Repeated
/// directed edges remain separate ordered occurrences.
public struct SurfaceEgressMatcherCorridor: Equatable, Sendable {
  public let id: String
  public let networkSnapshotID: String
  public let routePlanID: String
  public let providerDatasetID: String
  public let candidateID: String
  public let egressOptionID: String
  public let exitFacilityID: String
  public let occurrences: [SurfaceEgressMatcherOccurrence]

  package init(
    id: String,
    networkSnapshotID: String,
    routePlanID: String,
    providerDatasetID: String,
    candidateID: String,
    egressOptionID: String,
    exitFacilityID: String,
    occurrences: [SurfaceEgressMatcherOccurrence]
  ) {
    self.id = id
    self.networkSnapshotID = networkSnapshotID
    self.routePlanID = routePlanID
    self.providerDatasetID = providerDatasetID
    self.candidateID = candidateID
    self.egressOptionID = egressOptionID
    self.exitFacilityID = exitFacilityID
    self.occurrences = occurrences
  }

  public var validationIssues: [String] {
    var issues: [String] = []
    let identities = [
      id, networkSnapshotID, routePlanID, providerDatasetID, candidateID,
      egressOptionID, exitFacilityID,
    ]
    if identities.contains(where: {
      $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }) {
      issues.append("surface egress corridor identity is invalid")
    }
    if occurrences.isEmpty {
      issues.append("surface egress corridor occurrences are empty")
    }
    let occurrenceIDs = occurrences.map(\.id)
    if Set(occurrenceIDs).count != occurrenceIDs.count {
      issues.append("surface egress occurrence IDs are not unique")
    }
    if occurrences.map(\.index) != Array(0..<occurrences.count) {
      issues.append("surface egress occurrence indexes are not ordered")
    }
    var geometryByEdgeID: [String: [MatcherCoordinate]] = [:]
    for occurrence in occurrences {
      if occurrence.id.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty
        || occurrence.directedEdgeID.trimmingCharacters(
          in: .whitespacesAndNewlines
        ).isEmpty
        || occurrence.coordinates.count < 2
        || !occurrence.coordinates.allSatisfy(\.isValid)
        || occurrenceLengthMeters(occurrence) <= 0
      {
        issues.append(
          "surface egress occurrence \(occurrence.index) has invalid geometry"
        )
      }
      if let priorGeometry = geometryByEdgeID[occurrence.directedEdgeID],
        priorGeometry != occurrence.coordinates
      {
        issues.append(
          "surface egress repeated edge geometry is inconsistent"
        )
      } else {
        geometryByEdgeID[occurrence.directedEdgeID] =
          occurrence.coordinates
      }
    }
    return Array(Set(issues)).sorted()
  }
}

public struct SurfaceEgressMatcherConfiguration: Codable, Equatable, Sendable {
  public let minimumCandidateRadiusMeters: Double
  public let maximumCandidateRadiusMeters: Double
  public let accuracyRadiusMultiplier: Double
  public let ambiguityMarginMeters: Double
  public let maximumHighHorizontalAccuracyMeters: Double
  public let staleObservationThresholdMilliseconds: Int
  public let observationGapThresholdMilliseconds: Int
  public let minimumFractionBeforeNextOccurrence: Double
  public let progressRegressionTolerance: Double

  public init(
    minimumCandidateRadiusMeters: Double = 10,
    maximumCandidateRadiusMeters: Double = 80,
    accuracyRadiusMultiplier: Double = 3,
    ambiguityMarginMeters: Double = 3,
    maximumHighHorizontalAccuracyMeters: Double = 20,
    staleObservationThresholdMilliseconds: Int = 10_000,
    observationGapThresholdMilliseconds: Int = 10_000,
    minimumFractionBeforeNextOccurrence: Double = 0.75,
    progressRegressionTolerance: Double = 0.02
  ) {
    self.minimumCandidateRadiusMeters = minimumCandidateRadiusMeters
    self.maximumCandidateRadiusMeters = maximumCandidateRadiusMeters
    self.accuracyRadiusMultiplier = accuracyRadiusMultiplier
    self.ambiguityMarginMeters = ambiguityMarginMeters
    self.maximumHighHorizontalAccuracyMeters =
      maximumHighHorizontalAccuracyMeters
    self.staleObservationThresholdMilliseconds =
      staleObservationThresholdMilliseconds
    self.observationGapThresholdMilliseconds =
      observationGapThresholdMilliseconds
    self.minimumFractionBeforeNextOccurrence =
      minimumFractionBeforeNextOccurrence
    self.progressRegressionTolerance = progressRegressionTolerance
  }

  var isValid: Bool {
    minimumCandidateRadiusMeters.isFinite
      && minimumCandidateRadiusMeters > 0
      && maximumCandidateRadiusMeters.isFinite
      && maximumCandidateRadiusMeters >= minimumCandidateRadiusMeters
      && accuracyRadiusMultiplier.isFinite
      && accuracyRadiusMultiplier > 0
      && ambiguityMarginMeters.isFinite
      && ambiguityMarginMeters >= 0
      && maximumHighHorizontalAccuracyMeters.isFinite
      && maximumHighHorizontalAccuracyMeters > 0
      && staleObservationThresholdMilliseconds >= 0
      && observationGapThresholdMilliseconds >= 0
      && minimumFractionBeforeNextOccurrence.isFinite
      && (0...1).contains(minimumFractionBeforeNextOccurrence)
      && progressRegressionTolerance.isFinite
      && progressRegressionTolerance >= 0
  }

  private enum CodingKeys: String, CodingKey {
    case minimumCandidateRadiusMeters = "minimum_candidate_radius_meters"
    case maximumCandidateRadiusMeters = "maximum_candidate_radius_meters"
    case accuracyRadiusMultiplier = "accuracy_radius_multiplier"
    case ambiguityMarginMeters = "ambiguity_margin_meters"
    case maximumHighHorizontalAccuracyMeters =
      "maximum_high_horizontal_accuracy_meters"
    case staleObservationThresholdMilliseconds =
      "stale_observation_threshold_ms"
    case observationGapThresholdMilliseconds =
      "observation_gap_threshold_ms"
    case minimumFractionBeforeNextOccurrence =
      "minimum_fraction_before_next_occurrence"
    case progressRegressionTolerance = "progress_regression_tolerance"
  }
}

public enum SurfaceEgressMatcherError: Error, Equatable, Sendable {
  case invalidConfiguration
  case invalidCorridor([String])
  case invalidObservation
}

public struct SurfaceEgressMatcherEstimate: Codable, Equatable, Sendable {
  public let observationID: String?
  public let estimatedAtMilliseconds: Int
  public let corridorID: String
  public let directedEdgeID: String?
  public let occurrenceID: String?
  public let occurrenceIndex: Int?
  public let candidateEdgeIDs: [String]
  public let candidateOccurrenceIDs: [String]
  public let confidence: MatcherConfidence
  public let lateralDistanceMeters: Double?
  public let fractionAlongEdge: Double?

  package init(
    observationID: String?,
    estimatedAtMilliseconds: Int,
    corridorID: String,
    directedEdgeID: String?,
    occurrenceID: String?,
    occurrenceIndex: Int?,
    candidateEdgeIDs: [String],
    candidateOccurrenceIDs: [String],
    confidence: MatcherConfidence,
    lateralDistanceMeters: Double?,
    fractionAlongEdge: Double?
  ) {
    self.observationID = observationID
    self.estimatedAtMilliseconds = estimatedAtMilliseconds
    self.corridorID = corridorID
    self.directedEdgeID = directedEdgeID
    self.occurrenceID = occurrenceID
    self.occurrenceIndex = occurrenceIndex
    self.candidateEdgeIDs = candidateEdgeIDs
    self.candidateOccurrenceIDs = candidateOccurrenceIDs
    self.confidence = confidence
    self.lateralDistanceMeters = lateralDistanceMeters
    self.fractionAlongEdge = fractionAlongEdge
  }

  private enum CodingKeys: String, CodingKey {
    case observationID = "observation_id"
    case estimatedAtMilliseconds = "estimated_at_ms"
    case corridorID = "corridor_id"
    case directedEdgeID = "directed_edge_id"
    case occurrenceID = "occurrence_id"
    case occurrenceIndex = "occurrence_index"
    case candidateEdgeIDs = "candidate_edge_ids"
    case candidateOccurrenceIDs = "candidate_occurrence_ids"
    case confidence
    case lateralDistanceMeters = "lateral_distance_meters"
    case fractionAlongEdge = "fraction_along_edge"
  }
}

public struct SurfaceEgressMatcherDiagnostics: Equatable, Sendable {
  public let occurrenceCount: Int
  public let lastQueriedOccurrenceCount: Int
  public let acceptedObservationCount: Int
  public let currentOccurrenceID: String?
}

/// Incremental matcher for one compiler-admitted ordinary-road egress path.
///
/// The first observation is pinned to occurrence zero. Later observations may
/// remain on the current occurrence or advance by one only after sufficient
/// along-edge progress. Stale, ambiguous, gapped, or regressing evidence never
/// mutates accepted progress and cannot become HIGH.
public struct SurfaceEgressMatcherSession: Sendable {
  public static let algorithmID =
    "surface-egress-occurrence-matcher-prototype-v1"

  public let corridor: SurfaceEgressMatcherCorridor
  public let configuration: SurfaceEgressMatcherConfiguration

  private var currentOccurrenceIndex: Int?
  private var currentFractionAlongEdge: Double?
  private var lastAcceptedObservedAtMilliseconds: Int?
  private var lastReceivedAtMilliseconds: Int?
  private var acceptedObservationCount = 0
  private var lastQueriedOccurrenceCount = 0

  public init(
    corridor: SurfaceEgressMatcherCorridor,
    configuration: SurfaceEgressMatcherConfiguration = .init()
  ) throws {
    let issues = corridor.validationIssues
    guard issues.isEmpty else {
      throw SurfaceEgressMatcherError.invalidCorridor(issues)
    }
    guard configuration.isValid else {
      throw SurfaceEgressMatcherError.invalidConfiguration
    }
    self.corridor = corridor
    self.configuration = configuration
  }

  public var diagnostics: SurfaceEgressMatcherDiagnostics {
    SurfaceEgressMatcherDiagnostics(
      occurrenceCount: corridor.occurrences.count,
      lastQueriedOccurrenceCount: lastQueriedOccurrenceCount,
      acceptedObservationCount: acceptedObservationCount,
      currentOccurrenceID: currentOccurrenceIndex.map {
        corridor.occurrences[$0].id
      }
    )
  }

  public mutating func reset() {
    currentOccurrenceIndex = nil
    currentFractionAlongEdge = nil
    lastAcceptedObservedAtMilliseconds = nil
    lastReceivedAtMilliseconds = nil
    acceptedObservationCount = 0
    lastQueriedOccurrenceCount = 0
  }

  public mutating func observe(
    _ observation: RouteMatcherObservation
  ) throws -> SurfaceEgressMatcherEstimate {
    guard valid(observation) else {
      throw SurfaceEgressMatcherError.invalidObservation
    }
    if let lastReceivedAtMilliseconds,
      observation.receivedAtMilliseconds < lastReceivedAtMilliseconds
    {
      throw SurfaceEgressMatcherError.invalidObservation
    }
    lastReceivedAtMilliseconds = observation.receivedAtMilliseconds

    let (age, ageOverflow) =
      observation.receivedAtMilliseconds.subtractingReportingOverflow(
        observation.observedAtMilliseconds
      )
    guard !ageOverflow else {
      throw SurfaceEgressMatcherError.invalidObservation
    }
    let stale =
      age >= configuration.staleObservationThresholdMilliseconds
      || lastAcceptedObservedAtMilliseconds.map {
        observation.observedAtMilliseconds <= $0
      } == true
    let gap =
      lastAcceptedObservedAtMilliseconds.map {
        let (elapsed, overflow) =
          observation.observedAtMilliseconds.subtractingReportingOverflow($0)
        return overflow
          || elapsed
            >= configuration.observationGapThresholdMilliseconds
      } == true

    let allowedIndexes = allowedOccurrenceIndexes()
    let radius = min(
      configuration.maximumCandidateRadiusMeters,
      max(
        configuration.minimumCandidateRadiusMeters,
        observation.horizontalAccuracyMeters
          * configuration.accuracyRadiusMultiplier
      )
    )
    let measurements = allowedIndexes.compactMap { index in
      measurement(
        point: observation.coordinate,
        occurrence: corridor.occurrences[index]
      )
    }.filter { $0.distanceMeters <= radius }
      .sorted {
        if $0.distanceMeters == $1.distanceMeters {
          return $0.occurrence.index < $1.occurrence.index
        }
        return $0.distanceMeters < $1.distanceMeters
      }
    lastQueriedOccurrenceCount = measurements.count

    guard let best = measurements.first else {
      return estimate(
        observation: observation,
        selected: nil,
        candidates: [],
        confidence: .lost
      )
    }
    let plausible = measurements.filter {
      $0.distanceMeters - best.distanceMeters
        <= configuration.ambiguityMarginMeters
    }
    guard plausible.count == 1 else {
      return estimate(
        observation: observation,
        selected: nil,
        candidates: plausible,
        confidence: .low
      )
    }

    let regresses =
      currentOccurrenceIndex == best.occurrence.index
      && currentFractionAlongEdge.map {
        best.fractionAlongEdge
          + configuration.progressRegressionTolerance < $0
      } == true
    let advancesTooEarly =
      currentOccurrenceIndex.map {
        best.occurrence.index == $0 + 1
      } == true
      && currentFractionAlongEdge.map {
        $0 < configuration.minimumFractionBeforeNextOccurrence
      } != false
    let confidence: MatcherConfidence
    if stale || gap || regresses || advancesTooEarly {
      confidence = .low
    } else if observation.horizontalAccuracyMeters
      <= configuration.maximumHighHorizontalAccuracyMeters
    {
      confidence = .high
    } else {
      confidence = .medium
    }

    if !stale && !gap && !regresses && !advancesTooEarly {
      currentOccurrenceIndex = best.occurrence.index
      currentFractionAlongEdge = best.fractionAlongEdge
      lastAcceptedObservedAtMilliseconds =
        observation.observedAtMilliseconds
      acceptedObservationCount += 1
    }
    return estimate(
      observation: observation,
      selected: best,
      candidates: plausible,
      confidence: confidence
    )
  }

  private func allowedOccurrenceIndexes() -> [Int] {
    guard let currentOccurrenceIndex else { return [0] }
    var indexes = [currentOccurrenceIndex]
    if currentOccurrenceIndex + 1 < corridor.occurrences.count {
      indexes.append(currentOccurrenceIndex + 1)
    }
    return indexes
  }

  private func valid(_ observation: RouteMatcherObservation) -> Bool {
    let (_, ageOverflow) =
      observation.receivedAtMilliseconds.subtractingReportingOverflow(
        observation.observedAtMilliseconds
      )
    return observation.coordinate.isValid
      && observation.horizontalAccuracyMeters.isFinite
      && observation.horizontalAccuracyMeters > 0
      && observation.receivedAtMilliseconds
        >= observation.observedAtMilliseconds
      && !ageOverflow
      && observation.courseDegrees.map {
        $0.isFinite && (0..<360).contains($0)
      } != false
      && observation.speedMetersPerSecond.map {
        $0.isFinite && $0 >= 0
      } != false
  }

  private func estimate(
    observation: RouteMatcherObservation,
    selected: SurfaceEgressOccurrenceMeasurement?,
    candidates: [SurfaceEgressOccurrenceMeasurement],
    confidence: MatcherConfidence
  ) -> SurfaceEgressMatcherEstimate {
    SurfaceEgressMatcherEstimate(
      observationID: observation.id,
      estimatedAtMilliseconds: observation.observedAtMilliseconds,
      corridorID: corridor.id,
      directedEdgeID: selected?.occurrence.directedEdgeID,
      occurrenceID: selected?.occurrence.id,
      occurrenceIndex: selected?.occurrence.index,
      candidateEdgeIDs: candidates.map(\.occurrence.directedEdgeID)
        .uniqued().sorted(),
      candidateOccurrenceIDs: candidates.map(\.occurrence.id),
      confidence: confidence,
      lateralDistanceMeters: selected?.distanceMeters,
      fractionAlongEdge: selected?.fractionAlongEdge
    )
  }
}

private struct SurfaceEgressOccurrenceMeasurement {
  let occurrence: SurfaceEgressMatcherOccurrence
  let distanceMeters: Double
  let fractionAlongEdge: Double
}

private func measurement(
  point: MatcherCoordinate,
  occurrence: SurfaceEgressMatcherOccurrence
) -> SurfaceEgressOccurrenceMeasurement? {
  let lengths = zip(
    occurrence.coordinates,
    occurrence.coordinates.dropFirst()
  ).map(matcherCoordinateDistanceMeters)
  let total = lengths.reduce(0, +)
  guard total > 0 else { return nil }

  var traversed = 0.0
  var bestDistance = Double.infinity
  var bestAlong = 0.0
  for (segmentIndex, pair) in zip(
    occurrence.coordinates,
    occurrence.coordinates.dropFirst()
  ).enumerated() {
    let projection = project(point: point, start: pair.0, end: pair.1)
    if projection.distanceMeters < bestDistance {
      bestDistance = projection.distanceMeters
      bestAlong =
        traversed + lengths[segmentIndex] * projection.fraction
    }
    traversed += lengths[segmentIndex]
  }
  return SurfaceEgressOccurrenceMeasurement(
    occurrence: occurrence,
    distanceMeters: bestDistance,
    fractionAlongEdge: min(1, max(0, bestAlong / total))
  )
}

private func project(
  point: MatcherCoordinate,
  start: MatcherCoordinate,
  end: MatcherCoordinate
) -> (distanceMeters: Double, fraction: Double) {
  let earthRadiusMeters = 6_371_000.0
  let referenceLatitude =
    (start.latitude + end.latitude + point.latitude) / 3
  let latitudeScale = earthRadiusMeters * .pi / 180
  let longitudeScale =
    latitudeScale * cos(referenceLatitude * .pi / 180)
  let segmentX = (end.longitude - start.longitude) * longitudeScale
  let segmentY = (end.latitude - start.latitude) * latitudeScale
  let pointX = (point.longitude - start.longitude) * longitudeScale
  let pointY = (point.latitude - start.latitude) * latitudeScale
  let squaredLength = segmentX * segmentX + segmentY * segmentY
  let fraction =
    squaredLength > 0
    ? min(
      1,
      max(
        0,
        (pointX * segmentX + pointY * segmentY) / squaredLength
      )
    ) : 0
  return (
    hypot(
      pointX - segmentX * fraction,
      pointY - segmentY * fraction
    ),
    fraction
  )
}

private func occurrenceLengthMeters(
  _ occurrence: SurfaceEgressMatcherOccurrence
) -> Double {
  zip(
    occurrence.coordinates,
    occurrence.coordinates.dropFirst()
  ).reduce(0) {
    $0 + matcherCoordinateDistanceMeters($1.0, $1.1)
  }
}

extension Array where Element: Hashable {
  fileprivate func uniqued() -> [Element] {
    var seen: Set<Element> = []
    return filter { seen.insert($0).inserted }
  }
}
