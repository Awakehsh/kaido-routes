import Foundation

public struct MatcherCoordinate: Codable, Equatable, Sendable {
  public let latitude: Double
  public let longitude: Double

  public init(latitude: Double, longitude: Double) {
    self.latitude = latitude
    self.longitude = longitude
  }

  public var isValid: Bool {
    latitude.isFinite && longitude.isFinite
      && (-90...90).contains(latitude) && (-180...180).contains(longitude)
  }
}

public enum MatcherLocationSource: String, Codable, Hashable, Sendable {
  /// Replay and calibration cohort for an iPhone-delivered observation.
  ///
  /// These values are not hardware-source proof. In particular, Core Location
  /// can report that a fix came from an external accessory, but public CarPlay
  /// APIs do not distinguish wired from wireless location transport. Apple
  /// adapters must preserve that raw evidence separately from this cohort.
  case phone = "PHONE"
  case wiredCarPlay = "WIRED_CARPLAY"
  case wirelessCarPlay = "WIRELESS_CARPLAY"
  case accessory = "ACCESSORY"
}

public enum MatcherConfidence: String, Codable, Hashable, Sendable {
  case lost = "LOST"
  case low = "LOW"
  case medium = "MEDIUM"
  case high = "HIGH"
}

public enum MatcherTruthClassification: String, Codable, Sendable {
  case onRoute = "ON_ROUTE"
  case deviation = "DEVIATION"
}

public enum MatcherSafetyFailure: String, Codable, CaseIterable, Sendable {
  case falseHighConfidenceEdgeMatch = "FALSE_HIGH_CONFIDENCE_EDGE_MATCH"
  case falseHighConfidenceBranchCommit = "FALSE_HIGH_CONFIDENCE_BRANCH_COMMIT"
  case highConfidenceAmbiguity = "HIGH_CONFIDENCE_AMBIGUITY"
  case highConfidenceStaleObservation = "HIGH_CONFIDENCE_STALE_OBSERVATION"
  case routeOccurrenceUnavailable = "ROUTE_OCCURRENCE_UNAVAILABLE"
  case backwardOccurrenceJump = "BACKWARD_OCCURRENCE_JUMP"
  case branchCommitDuringObservationGap = "BRANCH_COMMIT_DURING_OBSERVATION_GAP"
}

public struct MatcherReplayEdge: Codable, Equatable, Sendable {
  public let id: String
  public let coordinates: [MatcherCoordinate]

  public init(id: String, coordinates: [MatcherCoordinate]) {
    self.id = id
    self.coordinates = coordinates
  }

  private enum CodingKeys: String, CodingKey {
    case id = "directed_edge_id"
    case coordinates
  }
}

public struct MatcherRouteOccurrenceBinding: Codable, Equatable, Sendable {
  public let occurrenceID: String
  public let index: Int
  public let directedEdgeID: String

  public init(occurrenceID: String, index: Int, directedEdgeID: String) {
    self.occurrenceID = occurrenceID
    self.index = index
    self.directedEdgeID = directedEdgeID
  }

  private enum CodingKeys: String, CodingKey {
    case occurrenceID = "occurrence_id"
    case index
    case directedEdgeID = "directed_edge_id"
  }
}

public struct MatcherReplayObservation: Codable, Equatable, Sendable {
  public let id: String
  public let observedAtMilliseconds: Int
  public let receivedAtMilliseconds: Int
  public let coordinate: MatcherCoordinate
  public let horizontalAccuracyMeters: Double
  public let courseDegrees: Double?
  public let speedMetersPerSecond: Double?
  public let source: MatcherLocationSource

  public init(
    id: String,
    observedAtMilliseconds: Int,
    receivedAtMilliseconds: Int,
    coordinate: MatcherCoordinate,
    horizontalAccuracyMeters: Double,
    courseDegrees: Double? = nil,
    speedMetersPerSecond: Double? = nil,
    source: MatcherLocationSource
  ) {
    self.id = id
    self.observedAtMilliseconds = observedAtMilliseconds
    self.receivedAtMilliseconds = receivedAtMilliseconds
    self.coordinate = coordinate
    self.horizontalAccuracyMeters = horizontalAccuracyMeters
    self.courseDegrees = courseDegrees
    self.speedMetersPerSecond = speedMetersPerSecond
    self.source = source
  }

  private enum CodingKeys: String, CodingKey {
    case id = "observation_id"
    case observedAtMilliseconds = "observed_at_ms"
    case receivedAtMilliseconds = "received_at_ms"
    case coordinate
    case horizontalAccuracyMeters = "horizontal_accuracy_meters"
    case courseDegrees = "course_degrees"
    case speedMetersPerSecond = "speed_meters_per_second"
    case source
  }
}

public struct MatcherGroundTruthInterval: Codable, Equatable, Sendable {
  public let startMilliseconds: Int
  public let endMilliseconds: Int
  public let directedEdgeID: String
  public let occurrenceID: String?
  public let classification: MatcherTruthClassification

  public init(
    startMilliseconds: Int,
    endMilliseconds: Int,
    directedEdgeID: String,
    occurrenceID: String?,
    classification: MatcherTruthClassification
  ) {
    self.startMilliseconds = startMilliseconds
    self.endMilliseconds = endMilliseconds
    self.directedEdgeID = directedEdgeID
    self.occurrenceID = occurrenceID
    self.classification = classification
  }

  public func contains(_ timestamp: Int) -> Bool {
    startMilliseconds <= timestamp && timestamp <= endMilliseconds
  }

  private enum CodingKeys: String, CodingKey {
    case startMilliseconds = "start_ms"
    case endMilliseconds = "end_ms"
    case directedEdgeID = "directed_edge_id"
    case occurrenceID = "occurrence_id"
    case classification
  }
}

public struct MatcherBranchDecision: Codable, Equatable, Sendable {
  public let id: String
  public let atMilliseconds: Int
  public let plannedOutgoingEdgeID: String
  public let actualOutgoingEdgeID: String
  public let actualOccurrenceID: String?

  public init(
    id: String,
    atMilliseconds: Int,
    plannedOutgoingEdgeID: String,
    actualOutgoingEdgeID: String,
    actualOccurrenceID: String?
  ) {
    self.id = id
    self.atMilliseconds = atMilliseconds
    self.plannedOutgoingEdgeID = plannedOutgoingEdgeID
    self.actualOutgoingEdgeID = actualOutgoingEdgeID
    self.actualOccurrenceID = actualOccurrenceID
  }

  private enum CodingKeys: String, CodingKey {
    case id = "decision_id"
    case atMilliseconds = "at_ms"
    case plannedOutgoingEdgeID = "planned_outgoing_edge_id"
    case actualOutgoingEdgeID = "actual_outgoing_edge_id"
    case actualOccurrenceID = "actual_occurrence_id"
  }
}

public struct MatcherReplayConfiguration: Codable, Equatable, Sendable {
  public let ambiguityMarginMeters: Double
  public let staleObservationThresholdMilliseconds: Int
  public let observationGapThresholdMilliseconds: Int

  public init(
    ambiguityMarginMeters: Double = 3,
    staleObservationThresholdMilliseconds: Int = 10_000,
    observationGapThresholdMilliseconds: Int = 10_000
  ) {
    self.ambiguityMarginMeters = ambiguityMarginMeters
    self.staleObservationThresholdMilliseconds = staleObservationThresholdMilliseconds
    self.observationGapThresholdMilliseconds = observationGapThresholdMilliseconds
  }

  private enum CodingKeys: String, CodingKey {
    case ambiguityMarginMeters = "ambiguity_margin_meters"
    case staleObservationThresholdMilliseconds = "stale_observation_threshold_ms"
    case observationGapThresholdMilliseconds = "observation_gap_threshold_ms"
  }
}

public struct MatcherReplayFixture: Codable, Equatable, Sendable {
  public let schemaVersion: String
  public let fixtureID: String
  public let networkSnapshotID: String
  public let evidenceClassification: String
  public let configuration: MatcherReplayConfiguration
  public let edges: [MatcherReplayEdge]
  public let routeOccurrences: [MatcherRouteOccurrenceBinding]
  public let initialOccurrenceID: String?
  public let observations: [MatcherReplayObservation]
  public let groundTruthIntervals: [MatcherGroundTruthInterval]
  public let branchDecisions: [MatcherBranchDecision]
  public let expectedNegativeControlFailures: [MatcherSafetyFailure]

  public init(
    schemaVersion: String = "1.0",
    fixtureID: String,
    networkSnapshotID: String,
    evidenceClassification: String,
    configuration: MatcherReplayConfiguration = .init(),
    edges: [MatcherReplayEdge],
    routeOccurrences: [MatcherRouteOccurrenceBinding],
    initialOccurrenceID: String? = nil,
    observations: [MatcherReplayObservation],
    groundTruthIntervals: [MatcherGroundTruthInterval],
    branchDecisions: [MatcherBranchDecision] = [],
    expectedNegativeControlFailures: [MatcherSafetyFailure]
  ) {
    self.schemaVersion = schemaVersion
    self.fixtureID = fixtureID
    self.networkSnapshotID = networkSnapshotID
    self.evidenceClassification = evidenceClassification
    self.configuration = configuration
    self.edges = edges
    self.routeOccurrences = routeOccurrences
    self.initialOccurrenceID = initialOccurrenceID
    self.observations = observations
    self.groundTruthIntervals = groundTruthIntervals
    self.branchDecisions = branchDecisions
    self.expectedNegativeControlFailures = expectedNegativeControlFailures
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case fixtureID = "fixture_id"
    case networkSnapshotID = "network_snapshot_id"
    case evidenceClassification = "evidence_classification"
    case configuration
    case edges
    case routeOccurrences = "route_occurrences"
    case initialOccurrenceID = "initial_occurrence_id"
    case observations
    case groundTruthIntervals = "ground_truth_intervals"
    case branchDecisions = "branch_decisions"
    case expectedNegativeControlFailures = "expected_negative_control_failures"
  }
}

public struct MatcherEstimate: Codable, Equatable, Sendable {
  public let observationID: String?
  public let estimatedAtMilliseconds: Int
  public let directedEdgeID: String?
  public let occurrenceID: String?
  public let candidateEdgeIDs: [String]
  public let confidence: MatcherConfidence
  public let distanceMeters: Double?
  public let fractionAlongEdge: Double?

  public init(
    observationID: String?,
    estimatedAtMilliseconds: Int,
    directedEdgeID: String?,
    occurrenceID: String?,
    candidateEdgeIDs: [String],
    confidence: MatcherConfidence,
    distanceMeters: Double?,
    fractionAlongEdge: Double? = nil
  ) {
    self.observationID = observationID
    self.estimatedAtMilliseconds = estimatedAtMilliseconds
    self.directedEdgeID = directedEdgeID
    self.occurrenceID = occurrenceID
    self.candidateEdgeIDs = candidateEdgeIDs
    self.confidence = confidence
    self.distanceMeters = distanceMeters
    self.fractionAlongEdge = fractionAlongEdge
  }
}

public struct MatcherReplayMetrics: Codable, Equatable, Sendable {
  public let observationCount: Int
  public let edgeTop1CorrectCount: Int
  public let occurrenceTruthCount: Int
  public let occurrenceCorrectCount: Int
  public let observationGapDurationsMilliseconds: [Int]

  public init(
    observationCount: Int,
    edgeTop1CorrectCount: Int,
    occurrenceTruthCount: Int,
    occurrenceCorrectCount: Int,
    observationGapDurationsMilliseconds: [Int]
  ) {
    self.observationCount = observationCount
    self.edgeTop1CorrectCount = edgeTop1CorrectCount
    self.occurrenceTruthCount = occurrenceTruthCount
    self.occurrenceCorrectCount = occurrenceCorrectCount
    self.observationGapDurationsMilliseconds = observationGapDurationsMilliseconds
  }
}

public struct MatcherReplayReport: Codable, Equatable, Sendable {
  public let fixtureID: String
  public let algorithmID: String
  public let estimates: [MatcherEstimate]
  public let metrics: MatcherReplayMetrics
  public let safetyFailures: [MatcherSafetyFailure]
  public let expectedSafetyFailures: [MatcherSafetyFailure]?
  public let expectationMatched: Bool?

  public init(
    fixtureID: String,
    algorithmID: String,
    estimates: [MatcherEstimate],
    metrics: MatcherReplayMetrics,
    safetyFailures: [MatcherSafetyFailure],
    expectedSafetyFailures: [MatcherSafetyFailure]? = nil,
    expectationMatched: Bool? = nil
  ) {
    self.fixtureID = fixtureID
    self.algorithmID = algorithmID
    self.estimates = estimates
    self.metrics = metrics
    self.safetyFailures = safetyFailures
    self.expectedSafetyFailures = expectedSafetyFailures
    self.expectationMatched = expectationMatched
  }
}

public enum MatcherReplayError: Error, Equatable, CustomStringConvertible, Sendable {
  case invalidFixture([String])
  case missingEstimate(String)
  case duplicateEstimate(String)

  public var description: String {
    switch self {
    case .invalidFixture(let issues):
      "invalid matcher replay fixture: \(issues.joined(separator: "; "))"
    case .missingEstimate(let observationID):
      "missing estimate for observation \(observationID)"
    case .duplicateEstimate(let observationID):
      "duplicate estimate for observation \(observationID)"
    }
  }
}
