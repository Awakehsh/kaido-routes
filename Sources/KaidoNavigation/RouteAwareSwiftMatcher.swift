import Foundation

public struct RouteAwareSwiftMatcherConfiguration: Equatable, Sendable {
  public let minimumCandidateRadiusMeters: Double
  public let maximumCandidateRadiusMeters: Double
  public let accuracyRadiusMultiplier: Double
  public let headingSigmaDegrees: Double
  public let minimumHighScoreMargin: Double
  public let indistinguishableDistanceMeters: Double

  public init(
    minimumCandidateRadiusMeters: Double = 10,
    maximumCandidateRadiusMeters: Double = 100,
    accuracyRadiusMultiplier: Double = 3,
    headingSigmaDegrees: Double = 45,
    minimumHighScoreMargin: Double = 2,
    indistinguishableDistanceMeters: Double = 0.5
  ) {
    self.minimumCandidateRadiusMeters = minimumCandidateRadiusMeters
    self.maximumCandidateRadiusMeters = maximumCandidateRadiusMeters
    self.accuracyRadiusMultiplier = accuracyRadiusMultiplier
    self.headingSigmaDegrees = headingSigmaDegrees
    self.minimumHighScoreMargin = minimumHighScoreMargin
    self.indistinguishableDistanceMeters = indistinguishableDistanceMeters
  }
}

public enum RouteAwareSwiftMatcherError: Error, Equatable, Sendable {
  case invalidConfiguration
  case invalidFixture([String])
  case invalidCorridor([String])
  case invalidObservation
  case missingInitialOccurrence(String)
}

public struct RouteMatcherDirectedEdge: Equatable, Sendable {
  public let id: String
  public let coordinates: [MatcherCoordinate]
  public let successorEdgeIDs: Set<String>

  public init(
    id: String,
    coordinates: [MatcherCoordinate],
    successorEdgeIDs: Set<String> = []
  ) {
    self.id = id
    self.coordinates = coordinates
    self.successorEdgeIDs = successorEdgeIDs
  }

  public var lengthMeters: Double {
    zip(coordinates, coordinates.dropFirst()).reduce(0) {
      $0 + matcherCoordinateDistanceMeters($1.0, $1.1)
    }
  }
}

public struct RouteMatcherOccurrence: Equatable, Sendable {
  public let id: String
  public let index: Int
  public let directedEdgeID: String

  public init(id: String, index: Int, directedEdgeID: String) {
    self.id = id
    self.index = index
    self.directedEdgeID = directedEdgeID
  }
}

/// A version-bound, route-local road corridor for one navigation session.
///
/// Include the compiled route edges plus nearby legal deviation/rejoin edges.
/// Successors must come from the same directed graph snapshot; the matcher does
/// not infer production topology from provider prose or road names.
public struct RouteMatcherCorridor: Equatable, Sendable {
  public let id: String
  public let networkSnapshotID: String
  public let routePlanID: String
  public let edges: [RouteMatcherDirectedEdge]
  public let occurrences: [RouteMatcherOccurrence]

  public init(
    id: String,
    networkSnapshotID: String,
    routePlanID: String,
    edges: [RouteMatcherDirectedEdge],
    occurrences: [RouteMatcherOccurrence]
  ) {
    self.id = id
    self.networkSnapshotID = networkSnapshotID
    self.routePlanID = routePlanID
    self.edges = edges
    self.occurrences = occurrences
  }

  public var validationIssues: [String] {
    var issues: [String] = []
    if id.isEmpty { issues.append("corridor id is empty") }
    if networkSnapshotID.isEmpty { issues.append("network snapshot id is empty") }
    if routePlanID.isEmpty { issues.append("route plan id is empty") }
    if edges.isEmpty { issues.append("corridor edges are empty") }
    let edgeIDs = edges.map(\.id)
    let edgeIDSet = Set(edgeIDs)
    if edgeIDSet.count != edgeIDs.count { issues.append("corridor edge IDs are not unique") }
    for edge in edges {
      if edge.id.isEmpty || edge.coordinates.count < 2
        || !edge.coordinates.allSatisfy(\.isValid)
      {
        issues.append("edge \(edge.id) has invalid geometry")
      }
      if !edge.successorEdgeIDs.isSubset(of: edgeIDSet) {
        issues.append("edge \(edge.id) has an unknown successor")
      }
    }
    let occurrenceIDs = occurrences.map(\.id)
    if occurrences.isEmpty { issues.append("corridor occurrences are empty") }
    if Set(occurrenceIDs).count != occurrenceIDs.count {
      issues.append("corridor occurrence IDs are not unique")
    }
    if occurrences.map(\.index).sorted() != Array(0..<occurrences.count) {
      issues.append("corridor occurrence indexes must be contiguous from zero")
    }
    for occurrence in occurrences {
      if occurrence.id.isEmpty || !edgeIDSet.contains(occurrence.directedEdgeID) {
        issues.append("occurrence \(occurrence.id) references an unknown edge")
      }
    }
    return Array(Set(issues)).sorted()
  }
}

public struct RouteMatcherObservation: Equatable, Sendable {
  public let id: String?
  public let observedAtMilliseconds: Int
  public let receivedAtMilliseconds: Int
  public let coordinate: MatcherCoordinate
  public let horizontalAccuracyMeters: Double
  public let courseDegrees: Double?
  public let speedMetersPerSecond: Double?
  public let source: MatcherLocationSource

  public init(
    id: String? = nil,
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

  fileprivate var isValid: Bool {
    coordinate.isValid && horizontalAccuracyMeters.isFinite
      && horizontalAccuracyMeters > 0
      && receivedAtMilliseconds >= observedAtMilliseconds
      && courseDegrees.map { $0.isFinite && (0..<360).contains($0) } != false
      && speedMetersPerSecond.map { $0.isFinite && $0 >= 0 } != false
  }
}

public struct RouteMatcherSessionConfiguration: Equatable, Sendable {
  public let ambiguityMarginMeters: Double
  public let staleObservationThresholdMilliseconds: Int
  public let observationGapThresholdMilliseconds: Int
  public let spatialCellSizeMeters: Double
  public let maximumActiveStates: Int
  public let scoreBeamWidth: Double

  public init(
    ambiguityMarginMeters: Double = 3,
    staleObservationThresholdMilliseconds: Int = 10_000,
    observationGapThresholdMilliseconds: Int = 10_000,
    spatialCellSizeMeters: Double = 100,
    maximumActiveStates: Int = 64,
    scoreBeamWidth: Double = 30
  ) {
    self.ambiguityMarginMeters = ambiguityMarginMeters
    self.staleObservationThresholdMilliseconds = staleObservationThresholdMilliseconds
    self.observationGapThresholdMilliseconds = observationGapThresholdMilliseconds
    self.spatialCellSizeMeters = spatialCellSizeMeters
    self.maximumActiveStates = maximumActiveStates
    self.scoreBeamWidth = scoreBeamWidth
  }

  fileprivate var isValid: Bool {
    ambiguityMarginMeters.isFinite && ambiguityMarginMeters >= 0
      && staleObservationThresholdMilliseconds >= 0
      && observationGapThresholdMilliseconds >= 0
      && spatialCellSizeMeters.isFinite && spatialCellSizeMeters > 0
      && maximumActiveStates > 0
      && scoreBeamWidth.isFinite && scoreBeamWidth >= 0
  }
}

public struct RouteMatcherSessionDiagnostics: Equatable, Sendable {
  public let indexedEdgeCount: Int
  public let lastQueriedEdgeCount: Int
  public let activeStateCount: Int
  public let acceptedObservationCount: Int
}

/// Online Viterbi prototype whose hidden state includes RoutePlan occurrence.
///
/// This implementation consumes observations in receive order. Geometry creates
/// edge candidates, while legal forward occurrence order and along-edge progress
/// constrain state transitions. Confidence is deliberately conservative and is
/// not production-calibrated; ambiguous, stale, and first post-gap observations
/// can never become HIGH.
public struct RouteAwareSwiftMatcher: Sendable {
  public static let algorithmID = "route-aware-swift-hmm-prototype-v1"

  public let configuration: RouteAwareSwiftMatcherConfiguration

  public init(configuration: RouteAwareSwiftMatcherConfiguration = .init()) throws {
    guard configuration.minimumCandidateRadiusMeters.isFinite,
      configuration.maximumCandidateRadiusMeters.isFinite,
      configuration.accuracyRadiusMultiplier.isFinite,
      configuration.headingSigmaDegrees.isFinite,
      configuration.minimumHighScoreMargin.isFinite,
      configuration.indistinguishableDistanceMeters.isFinite,
      configuration.minimumCandidateRadiusMeters > 0,
      configuration.maximumCandidateRadiusMeters
        >= configuration.minimumCandidateRadiusMeters,
      configuration.accuracyRadiusMultiplier > 0,
      configuration.headingSigmaDegrees > 0,
      configuration.minimumHighScoreMargin >= 0,
      configuration.indistinguishableDistanceMeters >= 0
    else {
      throw RouteAwareSwiftMatcherError.invalidConfiguration
    }
    self.configuration = configuration
  }

  public func run(fixture: MatcherReplayFixture) throws -> MatcherReplayReport {
    let estimates = try estimates(fixture: fixture)
    return try MatcherReplayEvaluator.evaluate(
      fixture: fixture,
      algorithmID: Self.algorithmID,
      estimates: estimates
    )
  }

  public func estimates(fixture: MatcherReplayFixture) throws -> [MatcherEstimate] {
    let issues = fixture.validationIssues
    guard issues.isEmpty else {
      throw RouteAwareSwiftMatcherError.invalidFixture(issues)
    }
    let corridor = fixture.routeMatcherCorridor
    let sessionConfiguration = RouteMatcherSessionConfiguration(
      ambiguityMarginMeters: fixture.configuration.ambiguityMarginMeters,
      staleObservationThresholdMilliseconds: fixture.configuration
        .staleObservationThresholdMilliseconds,
      observationGapThresholdMilliseconds: fixture.configuration
        .observationGapThresholdMilliseconds
    )
    var session = try makeSession(
      corridor: corridor,
      sessionConfiguration: sessionConfiguration,
      initialOccurrenceID: fixture.initialOccurrenceID
    )
    return try fixture.observations.map {
      try session.observe(RouteMatcherObservation(replayObservation: $0))
    }
  }

  public func makeSession(
    corridor: RouteMatcherCorridor,
    sessionConfiguration: RouteMatcherSessionConfiguration = .init(),
    initialOccurrenceID: String? = nil
  ) throws -> RouteMatcherSession {
    try RouteMatcherSession(
      corridor: corridor,
      matcherConfiguration: configuration,
      sessionConfiguration: sessionConfiguration,
      initialOccurrenceID: initialOccurrenceID
    )
  }
}

/// Incremental, observation-driven matcher state for one active RoutePlan.
///
/// The owner must call `observe` in receive order. Stale observations can
/// produce LOW diagnostics but never mutate the accepted path. `reset` clears
/// temporal evidence without changing the corridor or initial occurrence.
public struct RouteMatcherSession: Sendable {
  public let corridorID: String
  public let networkSnapshotID: String
  public private(set) var initialOccurrenceID: String?

  private let model: MatcherModel
  private let matcherConfiguration: RouteAwareSwiftMatcherConfiguration
  private let sessionConfiguration: RouteMatcherSessionConfiguration
  private var initialOccurrenceIndex: Int?
  private var paths: [StateKey: PathState] = [:]
  private var lastAcceptedObservation: RouteMatcherObservation?
  private var lastReceivedAtMilliseconds: Int?
  private var acceptedObservationCount = 0
  private var lastQueriedEdgeCount = 0

  fileprivate init(
    corridor: RouteMatcherCorridor,
    matcherConfiguration: RouteAwareSwiftMatcherConfiguration,
    sessionConfiguration: RouteMatcherSessionConfiguration,
    initialOccurrenceID: String?
  ) throws {
    let issues = corridor.validationIssues
    guard issues.isEmpty else { throw RouteAwareSwiftMatcherError.invalidCorridor(issues) }
    guard sessionConfiguration.isValid else {
      throw RouteAwareSwiftMatcherError.invalidConfiguration
    }
    let model = MatcherModel(
      corridor: corridor,
      spatialCellSizeMeters: sessionConfiguration.spatialCellSizeMeters
    )
    let initialOccurrenceIndex = try model.occurrenceIndex(id: initialOccurrenceID)
    self.corridorID = corridor.id
    self.networkSnapshotID = corridor.networkSnapshotID
    self.initialOccurrenceID = initialOccurrenceID
    self.model = model
    self.matcherConfiguration = matcherConfiguration
    self.sessionConfiguration = sessionConfiguration
    self.initialOccurrenceIndex = initialOccurrenceIndex
  }

  public var diagnostics: RouteMatcherSessionDiagnostics {
    RouteMatcherSessionDiagnostics(
      indexedEdgeCount: model.edges.count,
      lastQueriedEdgeCount: lastQueriedEdgeCount,
      activeStateCount: paths.count,
      acceptedObservationCount: acceptedObservationCount
    )
  }

  public mutating func reset() {
    paths = [:]
    lastAcceptedObservation = nil
    lastReceivedAtMilliseconds = nil
    acceptedObservationCount = 0
    lastQueriedEdgeCount = 0
  }

  public mutating func restart(at initialOccurrenceID: String?) throws {
    initialOccurrenceIndex = try model.occurrenceIndex(id: initialOccurrenceID)
    self.initialOccurrenceID = initialOccurrenceID
    reset()
  }

  public mutating func observe(_ observation: RouteMatcherObservation) throws
    -> MatcherEstimate
  {
    guard observation.isValid else {
      throw RouteAwareSwiftMatcherError.invalidObservation
    }
    if let lastReceivedAtMilliseconds,
      observation.receivedAtMilliseconds < lastReceivedAtMilliseconds
    {
      throw RouteAwareSwiftMatcherError.invalidObservation
    }
    lastReceivedAtMilliseconds = observation.receivedAtMilliseconds
    let measuredEdges = model.measurements(
      near: observation,
      matcherConfiguration: matcherConfiguration,
      sessionConfiguration: sessionConfiguration
    )
    lastQueriedEdgeCount = measuredEdges.count
    let candidates = model.candidates(
      measuredEdges: measuredEdges,
      observation: observation,
      configuration: matcherConfiguration
    )
    let isStale = isStaleObservation(observation)

    guard !candidates.isEmpty else {
      return lostEstimate(observation: observation, candidateEdgeIDs: [])
    }

    if isStale {
      let selected: PathState?
      if let previous = bestPath(in: paths),
        let current = candidates.first(where: { $0.state.key == previous.state.key })
      {
        selected = PathState(
          state: previous.state,
          score: previous.score,
          measurement: current.measurement,
          observation: observation
        )
      } else if paths.isEmpty,
        let initial = candidates.max(by: {
          model.initialScore(for: $0.state, initialOccurrenceIndex: initialOccurrenceIndex)
            + $0.emissionScore
            < model.initialScore(
              for: $1.state,
              initialOccurrenceIndex: initialOccurrenceIndex
            ) + $1.emissionScore
        })
      {
        selected = PathState(
          state: initial.state,
          score: model.initialScore(
            for: initial.state,
            initialOccurrenceIndex: initialOccurrenceIndex
          ) + initial.emissionScore,
          measurement: initial.measurement,
          observation: observation
        )
      } else {
        selected = nil
      }
      guard let selected else {
        return lostEstimate(
          observation: observation,
          candidateEdgeIDs: candidates.map(\.state.edgeID).uniqued().sorted()
        )
      }
      return makeEstimate(
        observation: observation,
        selected: selected,
        paths: [selected.state.key: selected],
        measuredEdges: measuredEdges,
        forceLow: true
      )
    }

    let nextPaths: [StateKey: PathState]
    if paths.isEmpty {
      nextPaths = Dictionary(
        uniqueKeysWithValues: candidates.map { candidate in
          let score =
            model.initialScore(
              for: candidate.state,
              initialOccurrenceIndex: initialOccurrenceIndex
            ) + candidate.emissionScore
          return (
            candidate.state.key,
            PathState(
              state: candidate.state,
              score: score,
              measurement: candidate.measurement,
              observation: observation
            )
          )
        }
      )
    } else {
      nextPaths = Dictionary(
        uniqueKeysWithValues: candidates.map { candidate in
          let bestTransition =
            paths.values.map { previous in
              previous.score
                + model.transitionScore(
                  from: previous,
                  to: candidate,
                  observation: observation,
                  gapThresholdMilliseconds: sessionConfiguration
                    .observationGapThresholdMilliseconds
                )
            }.max() ?? negativeInfinityScore
          return (
            candidate.state.key,
            PathState(
              state: candidate.state,
              score: bestTransition + candidate.emissionScore,
              measurement: candidate.measurement,
              observation: observation
            )
          )
        }
      )
    }
    let proposedPaths = prunedPaths(nextPaths)
    guard let selected = bestPath(in: proposedPaths) else {
      return lostEstimate(
        observation: observation,
        candidateEdgeIDs: candidates.map(\.state.edgeID).uniqued().sorted()
      )
    }
    paths = proposedPaths
    let hasObservationGap =
      lastAcceptedObservation.map {
        observation.observedAtMilliseconds - $0.observedAtMilliseconds
          >= sessionConfiguration.observationGapThresholdMilliseconds
      } ?? false
    let estimate = makeEstimate(
      observation: observation,
      selected: selected,
      paths: paths,
      measuredEdges: measuredEdges,
      forceLow: hasObservationGap
    )
    lastAcceptedObservation = observation
    acceptedObservationCount += 1
    return estimate
  }

  private func isStaleObservation(_ observation: RouteMatcherObservation) -> Bool {
    if observation.receivedAtMilliseconds - observation.observedAtMilliseconds
      >= sessionConfiguration.staleObservationThresholdMilliseconds
    {
      return true
    }
    if let lastAcceptedObservation,
      observation.observedAtMilliseconds <= lastAcceptedObservation.observedAtMilliseconds
    {
      return true
    }
    return false
  }

  private func prunedPaths(_ unpruned: [StateKey: PathState]) -> [StateKey: PathState] {
    let ranked = unpruned.values
      .filter { $0.score > negativeInfinityScore / 2 }
      .sorted(by: pathRanksBefore)
    guard let bestScore = ranked.first?.score else { return [:] }
    return Dictionary(
      uniqueKeysWithValues:
        ranked
        .prefix { $0.score >= bestScore - sessionConfiguration.scoreBeamWidth }
        .prefix(sessionConfiguration.maximumActiveStates)
        .map {
          (
            $0.state.key,
            PathState(
              state: $0.state,
              score: $0.score - bestScore,
              measurement: $0.measurement,
              observation: $0.observation
            )
          )
        }
    )
  }

  private func makeEstimate(
    observation: RouteMatcherObservation,
    selected: PathState,
    paths: [StateKey: PathState],
    measuredEdges: [String: EdgeMeasurement],
    forceLow: Bool
  ) -> MatcherEstimate {
    let bestMeasuredDistance = measuredEdges.values.map(\.distanceMeters).min() ?? .infinity
    let geometryAllowance = max(
      sessionConfiguration.ambiguityMarginMeters,
      min(observation.horizontalAccuracyMeters, 25)
    )
    var candidateEdgeIDs = measuredEdges.compactMap { edgeID, measurement in
      measurement.distanceMeters <= bestMeasuredDistance + geometryAllowance ? edgeID : nil
    }
    candidateEdgeIDs.append(selected.state.edgeID)
    candidateEdgeIDs = candidateEdgeIDs.uniqued().sorted()

    let candidateDistances = candidateEdgeIDs.compactMap { measuredEdges[$0]?.distanceMeters }
      .sorted()
    let indistinguishableGeometry =
      candidateDistances.count > 1
      && candidateDistances[1] - candidateDistances[0]
        <= matcherConfiguration.indistinguishableDistanceMeters
    let directedEdgeID = indistinguishableGeometry ? nil : selected.state.edgeID
    let rankedScores = paths.values.map(\.score).sorted(by: >)
    let scoreMargin =
      rankedScores.count > 1
      ? rankedScores[0] - rankedScores[1]
      : .infinity

    let confidence: MatcherConfidence
    if forceLow || indistinguishableGeometry || candidateEdgeIDs.count > 1
      || observation.horizontalAccuracyMeters >= 15
    {
      confidence = .low
    } else if selected.measurement.distanceMeters
      <= max(3, observation.horizontalAccuracyMeters),
      scoreMargin >= matcherConfiguration.minimumHighScoreMargin
    {
      confidence = .high
    } else {
      confidence = .medium
    }

    return MatcherEstimate(
      observationID: observation.id,
      estimatedAtMilliseconds: observation.observedAtMilliseconds,
      directedEdgeID: directedEdgeID,
      occurrenceID: selected.state.occurrenceID,
      candidateEdgeIDs: candidateEdgeIDs,
      confidence: confidence,
      distanceMeters: selected.measurement.distanceMeters,
      fractionAlongEdge: selected.measurement.fractionAlong
    )
  }

  private func lostEstimate(
    observation: RouteMatcherObservation,
    candidateEdgeIDs: [String]
  ) -> MatcherEstimate {
    MatcherEstimate(
      observationID: observation.id,
      estimatedAtMilliseconds: observation.observedAtMilliseconds,
      directedEdgeID: nil,
      occurrenceID: nil,
      candidateEdgeIDs: candidateEdgeIDs,
      confidence: .lost,
      distanceMeters: nil,
      fractionAlongEdge: nil
    )
  }
}

private struct MatcherModel: Sendable {
  let edges: [String: MeasuredRouteEdge]
  let statesByEdgeID: [String: [MatcherState]]
  let routeStatesByIndex: [Int: MatcherState]
  let occurrenceIndexesByID: [String: Int]
  let spatialIndex: CorridorSpatialIndex

  init(corridor: RouteMatcherCorridor, spatialCellSizeMeters: Double) {
    self.edges = Dictionary(
      uniqueKeysWithValues: corridor.edges.map { ($0.id, MeasuredRouteEdge(edge: $0)) }
    )
    let occurrencesByEdgeID = Dictionary(grouping: corridor.occurrences, by: \.directedEdgeID)
    let routeStates = corridor.occurrences.map { occurrence in
      MatcherState(
        edgeID: occurrence.directedEdgeID,
        occurrenceID: occurrence.id,
        occurrenceIndex: occurrence.index
      )
    }
    self.routeStatesByIndex = Dictionary(
      uniqueKeysWithValues: routeStates.map { ($0.occurrenceIndex!, $0) }
    )
    var states = routeStates
    states.append(
      contentsOf: corridor.edges.compactMap { edge in
        guard occurrencesByEdgeID[edge.id] == nil else { return nil }
        return MatcherState(edgeID: edge.id, occurrenceID: nil, occurrenceIndex: nil)
      }
    )
    self.statesByEdgeID = Dictionary(grouping: states, by: \.edgeID)
    self.occurrenceIndexesByID = Dictionary(
      uniqueKeysWithValues: corridor.occurrences.map { ($0.id, $0.index) }
    )
    self.spatialIndex = CorridorSpatialIndex(
      edges: corridor.edges,
      cellSizeMeters: spatialCellSizeMeters
    )
  }

  func occurrenceIndex(id: String?) throws -> Int? {
    guard let id else { return nil }
    guard let index = occurrenceIndexesByID[id] else {
      throw RouteAwareSwiftMatcherError.missingInitialOccurrence(id)
    }
    return index
  }

  func measurements(
    near observation: RouteMatcherObservation,
    matcherConfiguration: RouteAwareSwiftMatcherConfiguration,
    sessionConfiguration: RouteMatcherSessionConfiguration
  ) -> [String: EdgeMeasurement] {
    let candidateRadius = min(
      matcherConfiguration.maximumCandidateRadiusMeters,
      max(
        matcherConfiguration.minimumCandidateRadiusMeters,
        observation.horizontalAccuracyMeters
          * matcherConfiguration.accuracyRadiusMultiplier
      )
    )
    let ambiguityAllowance = max(
      sessionConfiguration.ambiguityMarginMeters,
      min(observation.horizontalAccuracyMeters, 25)
    )
    let edgeIDs = spatialIndex.edgeIDs(
      near: observation.coordinate,
      radiusMeters: candidateRadius + ambiguityAllowance
    )
    return Dictionary(
      uniqueKeysWithValues: edgeIDs.compactMap { edgeID in
        edges[edgeID].map { (edgeID, $0.measure(observation.coordinate)) }
      }
    )
  }

  func candidates(
    measuredEdges: [String: EdgeMeasurement],
    observation: RouteMatcherObservation,
    configuration: RouteAwareSwiftMatcherConfiguration
  ) -> [StateCandidate] {
    let radius = min(
      configuration.maximumCandidateRadiusMeters,
      max(
        configuration.minimumCandidateRadiusMeters,
        observation.horizontalAccuracyMeters * configuration.accuracyRadiusMultiplier
      )
    )
    return measuredEdges.keys.sorted().flatMap { edgeID -> [StateCandidate] in
      guard let measurement = measuredEdges[edgeID], measurement.distanceMeters <= radius
      else { return [] }
      return (statesByEdgeID[edgeID] ?? []).map { state in
        let sigma = max(4, observation.horizontalAccuracyMeters)
        let distanceScore = -0.5 * pow(measurement.distanceMeters / sigma, 2)
        let headingScore: Double
        if let course = observation.courseDegrees,
          (observation.speedMetersPerSecond ?? 0) >= 2
        {
          let delta = angularDifferenceDegrees(course, measurement.bearingDegrees)
          headingScore = -0.5 * pow(delta / configuration.headingSigmaDegrees, 2)
        } else {
          headingScore = 0
        }
        return StateCandidate(
          state: state,
          measurement: measurement,
          emissionScore: distanceScore + headingScore
        )
      }
    }
  }

  func initialScore(for state: MatcherState, initialOccurrenceIndex: Int?) -> Double {
    guard let initialOccurrenceIndex else {
      return state.occurrenceIndex == nil ? -2 : 0
    }
    guard let occurrenceIndex = state.occurrenceIndex else { return -4 }
    if occurrenceIndex == initialOccurrenceIndex { return 0 }
    if occurrenceIndex > initialOccurrenceIndex {
      return -8 - Double(occurrenceIndex - initialOccurrenceIndex) * 2
    }
    return negativeInfinityScore
  }

  func transitionScore(
    from previous: PathState,
    to candidate: StateCandidate,
    observation: RouteMatcherObservation,
    gapThresholdMilliseconds: Int
  ) -> Double {
    let elapsed =
      observation.observedAtMilliseconds
      - previous.observation.observedAtMilliseconds
    guard elapsed > 0 else { return negativeInfinityScore }
    if previous.state.key == candidate.state.key {
      let regression = previous.measurement.fractionAlong - candidate.measurement.fractionAlong
      guard regression <= 0.12 else { return -8 }
      let distance =
        max(
          0,
          candidate.measurement.fractionAlong - previous.measurement.fractionAlong
        ) * (edges[candidate.state.edgeID]?.lengthMeters ?? 0)
      return travelConsistencyScore(
        networkDistanceMeters: distance,
        previous: previous,
        observation: observation
      )
    }

    if let previousIndex = previous.state.occurrenceIndex,
      let candidateIndex = candidate.state.occurrenceIndex
    {
      guard candidateIndex >= previousIndex else { return negativeInfinityScore }
      if candidateIndex == previousIndex + 1 {
        if previous.state.edgeID == candidate.state.edgeID {
          let reset =
            previous.measurement.fractionAlong
            - candidate.measurement.fractionAlong > 0.12
          guard reset else { return -12 }
        }
        guard
          let previousEdge = edges[previous.state.edgeID],
          let candidateEdge = edges[candidate.state.edgeID]
        else { return negativeInfinityScore }
        let distance =
          (1 - previous.measurement.fractionAlong) * previousEdge.lengthMeters
          + candidate.measurement.fractionAlong * candidateEdge.lengthMeters
        return 0.5
          + travelConsistencyScore(
            networkDistanceMeters: distance,
            previous: previous,
            observation: observation
          )
      }
      if candidateIndex > previousIndex + 1,
        elapsed >= gapThresholdMilliseconds
      {
        guard
          let previousEdge = edges[previous.state.edgeID],
          let candidateEdge = edges[candidate.state.edgeID]
        else { return negativeInfinityScore }
        let intermediateDistance = ((previousIndex + 1)..<candidateIndex).reduce(0.0) {
          partial, index in
          guard let state = routeStatesByIndex[index], let edge = edges[state.edgeID] else {
            return partial
          }
          return partial + edge.lengthMeters
        }
        let distance =
          (1 - previous.measurement.fractionAlong) * previousEdge.lengthMeters
          + intermediateDistance
          + candidate.measurement.fractionAlong * candidateEdge.lengthMeters
        return -2 - Double(candidateIndex - previousIndex - 1)
          + travelConsistencyScore(
            networkDistanceMeters: distance,
            previous: previous,
            observation: observation
          )
      }
      return -14
    }

    let connected = edgesConnected(previous.state.edgeID, candidate.state.edgeID)
    if previous.state.occurrenceIndex != nil, candidate.state.occurrenceIndex == nil {
      return connected ? -2 : -12
    }
    if previous.state.occurrenceIndex == nil, candidate.state.occurrenceIndex != nil {
      return connected ? -2 : -12
    }
    return connected ? -1.5 : -12
  }

  private func edgesConnected(_ lhsID: String, _ rhsID: String) -> Bool {
    edges[lhsID]?.successorEdgeIDs.contains(rhsID) == true
  }

  private func travelConsistencyScore(
    networkDistanceMeters: Double,
    previous: PathState,
    observation: RouteMatcherObservation
  ) -> Double {
    let elapsedSeconds =
      Double(
        observation.observedAtMilliseconds - previous.observation.observedAtMilliseconds
      ) / 1_000
    guard elapsedSeconds > 0 else { return negativeInfinityScore }
    let previousSpeed =
      previous.observation.speedMetersPerSecond
      ?? observation.speedMetersPerSecond
      ?? 0
    let currentSpeed = observation.speedMetersPerSecond ?? previousSpeed
    let expectedDistance = (previousSpeed + currentSpeed) / 2 * elapsedSeconds
    guard expectedDistance > 0 else { return 0 }
    let tolerance = max(
      10,
      observation.horizontalAccuracyMeters * 2,
      expectedDistance * 0.75
    )
    return -abs(networkDistanceMeters - expectedDistance) / tolerance
  }
}

private struct StateKey: Hashable, Sendable {
  let edgeID: String
  let occurrenceID: String?
}

private struct MatcherState: Sendable {
  let edgeID: String
  let occurrenceID: String?
  let occurrenceIndex: Int?

  var key: StateKey {
    StateKey(edgeID: edgeID, occurrenceID: occurrenceID)
  }
}

private struct StateCandidate: Sendable {
  let state: MatcherState
  let measurement: EdgeMeasurement
  let emissionScore: Double
}

private struct PathState: Sendable {
  let state: MatcherState
  let score: Double
  let measurement: EdgeMeasurement
  let observation: RouteMatcherObservation
}

private struct EdgeMeasurement: Sendable {
  let distanceMeters: Double
  let fractionAlong: Double
  let bearingDegrees: Double
}

private struct MeasuredRouteEdge: Sendable {
  let coordinates: [MatcherCoordinate]
  let successorEdgeIDs: Set<String>
  let segmentLengths: [Double]
  let lengthMeters: Double

  init(edge: RouteMatcherDirectedEdge) {
    self.coordinates = edge.coordinates
    self.successorEdgeIDs = edge.successorEdgeIDs
    self.segmentLengths = zip(edge.coordinates, edge.coordinates.dropFirst()).map {
      matcherCoordinateDistanceMeters($0, $1)
    }
    self.lengthMeters = segmentLengths.reduce(0, +)
  }

  func measure(_ point: MatcherCoordinate) -> EdgeMeasurement {
    var bestDistance = Double.infinity
    var bestFraction = 0.0
    var bestBearing = 0.0
    var traversed = 0.0
    for (index, pair) in zip(coordinates, coordinates.dropFirst()).enumerated() {
      let projection = project(point: point, start: pair.0, end: pair.1)
      if projection.distanceMeters < bestDistance {
        bestDistance = projection.distanceMeters
        let along = traversed + segmentLengths[index] * projection.segmentFraction
        bestFraction = lengthMeters > 0 ? along / lengthMeters : 0
        bestBearing = projection.bearingDegrees
      }
      traversed += segmentLengths[index]
    }
    return EdgeMeasurement(
      distanceMeters: bestDistance,
      fractionAlong: bestFraction,
      bearingDegrees: bestBearing
    )
  }
}

private struct CorridorSpatialIndex: Sendable {
  private let cellSizeMeters: Double
  private let longitudeScale: Double
  private let cells: [SpatialCell: Set<String>]

  init(edges: [RouteMatcherDirectedEdge], cellSizeMeters: Double) {
    self.cellSizeMeters = cellSizeMeters
    let coordinates = edges.flatMap(\.coordinates)
    let referenceLatitude =
      coordinates.map(\.latitude).reduce(0, +) / Double(max(1, coordinates.count))
    let longitudeScale = max(0.01, cos(referenceLatitude * .pi / 180))
    self.longitudeScale = longitudeScale
    let coordinateCell: (MatcherCoordinate) -> SpatialCell = { coordinate in
      let latitudeMeters = coordinate.latitude * matcherMetersPerDegree
      let longitudeMeters = coordinate.longitude * matcherMetersPerDegree * longitudeScale
      return SpatialCell(
        x: Int(floor(longitudeMeters / cellSizeMeters)),
        y: Int(floor(latitudeMeters / cellSizeMeters))
      )
    }
    var cells: [SpatialCell: Set<String>] = [:]
    for edge in edges {
      for (start, end) in zip(edge.coordinates, edge.coordinates.dropFirst()) {
        let startCell = coordinateCell(start)
        let endCell = coordinateCell(end)
        for x in min(startCell.x, endCell.x)...max(startCell.x, endCell.x) {
          for y in min(startCell.y, endCell.y)...max(startCell.y, endCell.y) {
            cells[SpatialCell(x: x, y: y), default: []].insert(edge.id)
          }
        }
      }
    }
    self.cells = cells
  }

  func edgeIDs(near coordinate: MatcherCoordinate, radiusMeters: Double) -> [String] {
    let center = cell(for: coordinate)
    let span = max(1, Int(ceil(radiusMeters / cellSizeMeters)))
    var edgeIDs: Set<String> = []
    for x in (center.x - span)...(center.x + span) {
      for y in (center.y - span)...(center.y + span) {
        edgeIDs.formUnion(cells[SpatialCell(x: x, y: y)] ?? [])
      }
    }
    return edgeIDs.sorted()
  }

  private func cell(for coordinate: MatcherCoordinate) -> SpatialCell {
    let latitudeMeters = coordinate.latitude * matcherMetersPerDegree
    let longitudeMeters = coordinate.longitude * matcherMetersPerDegree * longitudeScale
    return SpatialCell(
      x: Int(floor(longitudeMeters / cellSizeMeters)),
      y: Int(floor(latitudeMeters / cellSizeMeters))
    )
  }
}

private struct SpatialCell: Hashable, Sendable {
  let x: Int
  let y: Int
}

private struct SegmentProjection {
  let distanceMeters: Double
  let segmentFraction: Double
  let bearingDegrees: Double
}

private func project(
  point: MatcherCoordinate,
  start: MatcherCoordinate,
  end: MatcherCoordinate
) -> SegmentProjection {
  let referenceLatitude = (start.latitude + end.latitude + point.latitude) / 3
  let latitudeScale = matcherEarthRadiusMeters * .pi / 180
  let longitudeScale = latitudeScale * cos(referenceLatitude * .pi / 180)
  let segmentX = (end.longitude - start.longitude) * longitudeScale
  let segmentY = (end.latitude - start.latitude) * latitudeScale
  let pointX = (point.longitude - start.longitude) * longitudeScale
  let pointY = (point.latitude - start.latitude) * latitudeScale
  let squaredLength = segmentX * segmentX + segmentY * segmentY
  let fraction =
    squaredLength > 0
    ? min(1, max(0, (pointX * segmentX + pointY * segmentY) / squaredLength))
    : 0
  let deltaX = pointX - segmentX * fraction
  let deltaY = pointY - segmentY * fraction
  let bearing = atan2(segmentX, segmentY) * 180 / .pi
  return SegmentProjection(
    distanceMeters: hypot(deltaX, deltaY),
    segmentFraction: fraction,
    bearingDegrees: bearing >= 0 ? bearing : bearing + 360
  )
}

private func angularDifferenceDegrees(_ lhs: Double, _ rhs: Double) -> Double {
  let difference = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
  return min(difference, 360 - difference)
}

func matcherCoordinateDistanceMeters(
  _ lhs: MatcherCoordinate,
  _ rhs: MatcherCoordinate
) -> Double {
  let latitude1 = lhs.latitude * .pi / 180
  let latitude2 = rhs.latitude * .pi / 180
  let deltaLatitude = latitude2 - latitude1
  let deltaLongitude = (rhs.longitude - lhs.longitude) * .pi / 180
  let value =
    sin(deltaLatitude / 2) * sin(deltaLatitude / 2)
    + cos(latitude1) * cos(latitude2)
    * sin(deltaLongitude / 2) * sin(deltaLongitude / 2)
  return 2 * matcherEarthRadiusMeters * atan2(sqrt(value), sqrt(max(0, 1 - value)))
}

extension MatcherReplayFixture {
  fileprivate var routeMatcherCorridor: RouteMatcherCorridor {
    let replayEdges = edges
    let corridorEdges = replayEdges.map { edge in
      let successors = Set<String>(
        replayEdges.compactMap { candidate in
          guard edge.id != candidate.id,
            let last = edge.coordinates.last,
            let first = candidate.coordinates.first,
            matcherCoordinateDistanceMeters(last, first) <= 3
          else { return nil }
          return candidate.id
        }
      )
      return RouteMatcherDirectedEdge(
        id: edge.id,
        coordinates: edge.coordinates,
        successorEdgeIDs: successors
      )
    }
    return RouteMatcherCorridor(
      id: fixtureID,
      networkSnapshotID: networkSnapshotID,
      routePlanID: fixtureID,
      edges: corridorEdges,
      occurrences: routeOccurrences.map {
        RouteMatcherOccurrence(
          id: $0.occurrenceID,
          index: $0.index,
          directedEdgeID: $0.directedEdgeID
        )
      }
    )
  }
}

extension RouteMatcherObservation {
  fileprivate init(replayObservation: MatcherReplayObservation) {
    self.init(
      id: replayObservation.id,
      observedAtMilliseconds: replayObservation.observedAtMilliseconds,
      receivedAtMilliseconds: replayObservation.receivedAtMilliseconds,
      coordinate: replayObservation.coordinate,
      horizontalAccuracyMeters: replayObservation.horizontalAccuracyMeters,
      courseDegrees: replayObservation.courseDegrees,
      speedMetersPerSecond: replayObservation.speedMetersPerSecond,
      source: replayObservation.source
    )
  }
}

private func pathRanksBefore(_ lhs: PathState, _ rhs: PathState) -> Bool {
  if abs(lhs.score - rhs.score) >= 0.000_001 { return lhs.score > rhs.score }
  return (lhs.state.occurrenceIndex ?? Int.max, lhs.state.edgeID)
    < (rhs.state.occurrenceIndex ?? Int.max, rhs.state.edgeID)
}

private func bestPath(in paths: [StateKey: PathState]) -> PathState? {
  paths.values.sorted(by: pathRanksBefore).first
}

private let negativeInfinityScore = -1_000_000_000.0
private let matcherEarthRadiusMeters = 6_371_000.0
private let matcherMetersPerDegree = matcherEarthRadiusMeters * .pi / 180

extension Sequence where Element: Hashable {
  fileprivate func uniqued() -> [Element] {
    var seen: Set<Element> = []
    return filter { seen.insert($0).inserted }
  }
}
