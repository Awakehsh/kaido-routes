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

public struct RouteMatcherDirectedEdge: Codable, Equatable, Sendable {
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

  private enum CodingKeys: String, CodingKey {
    case id = "directed_edge_id"
    case coordinates
    case successorEdgeIDs = "successor_edge_ids"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    coordinates = try container.decode([MatcherCoordinate].self, forKey: .coordinates)
    successorEdgeIDs = Set(
      try container.decodeIfPresent([String].self, forKey: .successorEdgeIDs) ?? []
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(coordinates, forKey: .coordinates)
    try container.encode(successorEdgeIDs.sorted(), forKey: .successorEdgeIDs)
  }

  public var lengthMeters: Double {
    zip(coordinates, coordinates.dropFirst()).reduce(0) {
      $0 + matcherCoordinateDistanceMeters($1.0, $1.1)
    }
  }
}

public struct RouteMatcherOccurrence: Codable, Equatable, Sendable {
  public let id: String
  public let index: Int
  public let directedEdgeID: String

  public init(id: String, index: Int, directedEdgeID: String) {
    self.id = id
    self.index = index
    self.directedEdgeID = directedEdgeID
  }

  private enum CodingKeys: String, CodingKey {
    case id = "occurrence_id"
    case index
    case directedEdgeID = "directed_edge_id"
  }
}

/// A version-bound, route-local road corridor for one navigation session.
///
/// Include the compiled route edges plus nearby legal deviation/rejoin edges.
/// Successors must come from the same directed graph snapshot; the matcher does
/// not infer production topology from provider prose or road names.
public struct RouteMatcherCorridor: Codable, Equatable, Sendable {
  public static let longitudinalCandidateOccurrenceWindow = 12
  public let id: String
  public let networkSnapshotID: String
  public let routePlanID: String
  public let edges: [RouteMatcherDirectedEdge]
  public let occurrences: [RouteMatcherOccurrence]
  /// The corridor's ramps of the plan's exit facility. A facility can leave
  /// the expressway by more than one ramp; a car that left the corridor
  /// along any of them left at the planned exit. Corridors authored before
  /// this was recorded carry none.
  public let exitRampEdgeIDs: Set<String>

  public init(
    id: String,
    networkSnapshotID: String,
    routePlanID: String,
    edges: [RouteMatcherDirectedEdge],
    occurrences: [RouteMatcherOccurrence],
    exitRampEdgeIDs: Set<String> = []
  ) {
    self.id = id
    self.networkSnapshotID = networkSnapshotID
    self.routePlanID = routePlanID
    self.edges = edges
    self.occurrences = occurrences
    self.exitRampEdgeIDs = exitRampEdgeIDs
  }

  private enum CodingKeys: String, CodingKey {
    case id = "corridor_id"
    case networkSnapshotID = "network_snapshot_id"
    case routePlanID = "route_plan_id"
    case edges
    case occurrences
    case exitRampEdgeIDs = "exit_ramp_edge_ids"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    networkSnapshotID = try container.decode(String.self, forKey: .networkSnapshotID)
    routePlanID = try container.decode(String.self, forKey: .routePlanID)
    edges = try container.decode([RouteMatcherDirectedEdge].self, forKey: .edges)
    occurrences = try container.decode([RouteMatcherOccurrence].self, forKey: .occurrences)
    exitRampEdgeIDs = Set(
      try container.decodeIfPresent([String].self, forKey: .exitRampEdgeIDs) ?? []
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(networkSnapshotID, forKey: .networkSnapshotID)
    try container.encode(routePlanID, forKey: .routePlanID)
    try container.encode(edges, forKey: .edges)
    try container.encode(occurrences, forKey: .occurrences)
    if !exitRampEdgeIDs.isEmpty {
      try container.encode(exitRampEdgeIDs.sorted(), forKey: .exitRampEdgeIDs)
    }
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
    if !exitRampEdgeIDs.isSubset(of: edgeIDSet) {
      issues.append("an exit ramp is not a corridor edge")
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
  public let courseAccuracyDegrees: Double?
  public let speedMetersPerSecond: Double?
  public let speedAccuracyMetersPerSecond: Double?
  public let source: MatcherLocationSource

  public init(
    id: String? = nil,
    observedAtMilliseconds: Int,
    receivedAtMilliseconds: Int,
    coordinate: MatcherCoordinate,
    horizontalAccuracyMeters: Double,
    courseDegrees: Double? = nil,
    courseAccuracyDegrees: Double? = nil,
    speedMetersPerSecond: Double? = nil,
    speedAccuracyMetersPerSecond: Double? = nil,
    source: MatcherLocationSource
  ) {
    self.id = id
    self.observedAtMilliseconds = observedAtMilliseconds
    self.receivedAtMilliseconds = receivedAtMilliseconds
    self.coordinate = coordinate
    self.horizontalAccuracyMeters = horizontalAccuracyMeters
    self.courseDegrees = courseDegrees
    self.courseAccuracyDegrees = courseAccuracyDegrees
    self.speedMetersPerSecond = speedMetersPerSecond
    self.speedAccuracyMetersPerSecond = speedAccuracyMetersPerSecond
    self.source = source
  }

  fileprivate var isValid: Bool {
    let (_, ageOverflow) =
      receivedAtMilliseconds.subtractingReportingOverflow(observedAtMilliseconds)
    return coordinate.isValid && horizontalAccuracyMeters.isFinite
      && horizontalAccuracyMeters > 0
      && receivedAtMilliseconds >= observedAtMilliseconds
      && !ageOverflow
      && courseDegrees.map { $0.isFinite && (0..<360).contains($0) } != false
      && courseAccuracyDegrees.map { $0.isFinite && $0 >= 0 } != false
      && speedMetersPerSecond.map { $0.isFinite && $0 >= 0 } != false
      && speedAccuracyMetersPerSecond.map {
        $0.isFinite && $0 >= 0
      } != false
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

/// One matcher step plus the corridor context the estimate alone cannot carry.
///
/// An off-plan road counts only where the car could actually be on it: on a
/// branch the plan diverges onto at or after the last occurrence where the
/// car was matched clear of every such branch. A stacked road it never left
/// the plan for, or a ramp merging into the plan, is geometry, not a place
/// the car can have driven to.
public struct RouteMatcherObservationResult: Equatable, Sendable {
  public let estimate: MatcherEstimate
  /// Reachable off-plan corridor edges inside this fix's candidate radius
  /// that agree with its course. While one exists, an on-plan estimate is not
  /// separated from a road the car may be on, however large its score margin.
  public let competingOffPlanEdgeIDs: [String]
  /// The estimate selected an off-plan edge the car can have reached by
  /// leaving the plan.
  public let isOnReachableOffPlanEdge: Bool
  /// Distance from the fix to every corridor edge inside the query radius.
  /// An edge absent here is farther than the radius.
  public let edgeDistancesMeters: [String: Double]
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
  private var lastMeasuredEdges: [String: EdgeMeasurement] = [:]
  private var lastSeparatedOccurrenceIndex: Int?
  private var lastOnPlanOccurrenceIndex: Int?
  /// The passes of the plan the car can be on, as set by the session from
  /// admitted progress and reach. A road whose every pass lies outside it is
  /// matched as an off-plan road. Nil admits every pass.
  public var occurrenceWindow: ClosedRange<Int>?
  /// The off-plan road the matcher last placed the car on with confidence,
  /// one it can have left the plan for, and when.
  private var offPlanPlacement: (edgeID: String, observedAtMilliseconds: Int)?

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
    lastMeasuredEdges = [:]
    lastSeparatedOccurrenceIndex = nil
    lastOnPlanOccurrenceIndex = nil
    offPlanPlacement = nil
  }

  public mutating func restart(at initialOccurrenceID: String?) throws {
    initialOccurrenceIndex = try model.occurrenceIndex(id: initialOccurrenceID)
    self.initialOccurrenceID = initialOccurrenceID
    reset()
  }

  public mutating func observe(_ observation: RouteMatcherObservation) throws
    -> MatcherEstimate
  {
    try observeWithContext(observation).estimate
  }

  public mutating func observeWithContext(
    _ observation: RouteMatcherObservation
  ) throws -> RouteMatcherObservationResult {
    let estimate = try estimate(for: observation)
    let model = model
    let selectedIndex = estimate.occurrenceID.flatMap {
      try? model.occurrenceIndex(id: $0)
    }
    let upper =
      selectedIndex
      ?? lastOnPlanOccurrenceIndex.map {
        $0 + RouteMatcherCorridor.longitudinalCandidateOccurrenceWindow
      }
    let lower = lastSeparatedOccurrenceIndex
    let window = occurrenceWindow
    let isReachable = { (edgeID: String) in
      if let window, model.isPassOutsideWindow(edgeID, window: window) {
        // Progress along the final exit can run ahead of a car that missed
        // it; the road it leaves there stays one the car can be on.
        let from = model.finalExitIndex.map {
          window.upperBound > $0 ? min(window.lowerBound, $0) : window.lowerBound
        } ?? window.lowerBound
        return model.passIsReachable(edgeID, from: from, through: upper)
      }
      return model.branchIsReachable(edgeID, from: lower, through: upper)
    }
    // From the occurrence the plan leaves at its final exit, the road it
    // leaves there is one it has already driven, and runs beside the exit as
    // far as the corridor goes. A car that missed the exit is on it, and
    // still raises deviation evidence there; it holds back the final
    // occurrence, which completes the drive, but not the exit's own progress,
    // nor that occurrence's, which a car drives whichever way it goes.
    let isOnFinalExit =
      window != nil
      && selectedIndex.map { index in
        model.finalExitIndex.map { index >= $0 } == true && index < model.finalOccurrenceIndex
      } == true
    var competing = model.offPlanEdgeIDs(
      within: lastMeasuredEdges,
      observation: observation,
      matchedDistanceMeters: estimate.distanceMeters,
      matcherConfiguration: matcherConfiguration,
      sessionConfiguration: sessionConfiguration,
      window: window
    ).filter { edgeID in
      edgeID != estimate.directedEdgeID && isReachable(edgeID)
        && !(isOnFinalExit && model.isDrivenBeforeFinalExit(edgeID))
        && !(selectedIndex.map { model.isBypass(edgeID, beside: $0) } ?? false)
    }
    // A match on the plan right after the car was placed on an off-plan road
    // it could have left the plan for is a jump between roads unless that
    // road leads there in the distance the car can have driven since: while
    // a road it leads to is still near the fix, the car may be on it.
    if estimate.occurrenceID == nil, estimate.confidence == .high || estimate.confidence == .medium,
      let edgeID = estimate.directedEdgeID, isReachable(edgeID)
    {
      offPlanPlacement = (edgeID, observation.observedAtMilliseconds)
    } else if let selectedIndex, let placement = offPlanPlacement,
      estimate.confidence != .lost
    {
      let elapsed = observation.observedAtMilliseconds - placement.observedAtMilliseconds
      let roads = model.roadsAhead(
        of: placement.edgeID,
        withinMeters: Double(elapsed) / 1_000
          * NavigationSession.maximumPlausibleSpeedMetersPerSecond
          + NavigationSession.reachMarginMeters
      )
      let nearby = roads.filter { lastMeasuredEdges[$0] != nil }
      let rejoins =
        roads.contains(model.routeStatesByIndex[selectedIndex]?.edgeID ?? "")
        || nearby.contains { !model.isOffPlan($0) && !model.isPassOutsideWindow($0, window: window) }
      if elapsed > Self.offPlanPlacementMilliseconds || rejoins || nearby.isEmpty {
        offPlanPlacement = nil
      } else if let road = nearby.min() {
        competing.append(road)
      }
    }
    if let selectedIndex, estimate.confidence != .lost {
      lastOnPlanOccurrenceIndex = selectedIndex
      if estimate.confidence == .high || estimate.confidence == .medium,
        competing.isEmpty
      {
        lastSeparatedOccurrenceIndex = selectedIndex
      }
    }
    return RouteMatcherObservationResult(
      estimate: estimate,
      competingOffPlanEdgeIDs: competing,
      isOnReachableOffPlanEdge: estimate.occurrenceID == nil
        && estimate.confidence != .lost
        && estimate.directedEdgeID.map(isReachable) == true,
      edgeDistancesMeters: lastMeasuredEdges.mapValues(\.distanceMeters)
    )
  }

  /// How long a confident placement on an off-plan road outweighs the plan
  /// matches beside it.
  static let offPlanPlacementMilliseconds = 30_000

  private mutating func estimate(
    for observation: RouteMatcherObservation
  ) throws -> MatcherEstimate {
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
    lastMeasuredEdges = measuredEdges
    let candidates = model.candidates(
      measuredEdges: measuredEdges,
      observation: observation,
      configuration: matcherConfiguration,
      window: occurrenceWindow
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
                  lastOnPlanOccurrenceIndex: lastOnPlanOccurrenceIndex
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
    // A drive out along a radial and back passes its own other carriageway,
    // stacked over this one or beside it: that pass of the plan runs against
    // the car's course and is no rival to where it is driving. Neither is a
    // junction's link for the other direction beside a place on the plan
    // that runs with the course, as near as the heading score allows. Any
    // other placement keeps it as a rival: without that clutter a noisy fix
    // reads the off-plan branch the car did not take (Route 4 at
    // Nishi-Shinjuku JCT), or a later pass of the plan at an angle to its
    // course (K6 at Daishi, C2 at Hatsudai-minami), as MEDIUM.
    let course =
      (observation.speedMetersPerSecond ?? 0) >= 2 ? observation.courseDegrees : nil
    let headingTolerance = max(
      MatcherModel.offPlanHeadingToleranceDegrees,
      observation.courseAccuracyDegrees ?? 0
    )
    let placedWithCourse =
      selected.state.occurrenceIndex != nil
      && course.map {
        angularDifferenceDegrees($0, selected.measurement.bearingDegrees)
          <= max(matcherConfiguration.headingSigmaDegrees, observation.courseAccuracyDegrees ?? 0)
      } == true
    var candidateEdgeIDs = measuredEdges.compactMap { edgeID, measurement -> String? in
      guard measurement.distanceMeters <= bestMeasuredDistance + geometryAllowance else {
        return nil
      }
      if let course, !model.isOffPlan(edgeID) || placedWithCourse,
        angularDifferenceDegrees(course, measurement.bearingDegrees) > headingTolerance
      {
        return nil
      }
      return edgeID
    }
    // A road of the plan matched outside the window is where the car has
    // come since its last place on the plan; an off-plan road it cannot have
    // reached from there is no rival to it either.
    let reachedIndex =
      selected.state.occurrenceIndex
      ?? (model.isOffPlan(selected.state.edgeID)
        ? nil
        : lastOnPlanOccurrenceIndex.map {
          $0 + RouteMatcherCorridor.longitudinalCandidateOccurrenceWindow
        })
    if let reachedIndex {
      candidateEdgeIDs.removeAll {
        model.isOffPlan($0)
          && !model.branchIsReachable(
            $0,
            from: lastSeparatedOccurrenceIndex,
            through: reachedIndex
          )
      }
    }
    candidateEdgeIDs.append(selected.state.edgeID)
    candidateEdgeIDs = candidateEdgeIDs.uniqued().sorted()

    // A bypass beside the place on the plan brings the car back to it
    // where the plan would have: on it or on the plan, the car is there.
    let independentCandidateEdgeIDs = candidateEdgeIDs.filter { edgeID in
      edgeID == selected.state.edgeID
        || !model.isNearbyRouteEdge(
          edgeID,
          selectedState: selected.state
        )
          && !(selected.state.occurrenceIndex.map { model.isBypass(edgeID, beside: $0) } ?? false)
    }

    let candidateDistances = independentCandidateEdgeIDs.compactMap {
      measuredEdges[$0]?.distanceMeters
    }
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
    if forceLow || indistinguishableGeometry
      || independentCandidateEdgeIDs.count > 1
      || observation.horizontalAccuracyMeters >= 30
    {
      confidence = .low
    } else if selected.measurement.distanceMeters
      <= max(3, observation.horizontalAccuracyMeters),
      candidateEdgeIDs.count == 1,
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
  /// For each off-plan edge, the RoutePlan occurrences from whose end it is
  /// reachable through off-plan edges only.
  let branchRootOccurrenceIndexes: [String: [Int]]
  /// For each road of the plan, the occurrences from whose end the car can
  /// leave the plan and drive onto it within `passDepartureMeters`.
  let departureRootOccurrenceIndexes: [String: [Int]]
  /// The last occurrence at which the plan leaves for good a road it has
  /// already driven: on a loop, its final exit.
  let finalExitIndex: Int?
  /// Route length before each occurrence index, plus the total at the end.
  let routeDistanceBeforeIndex: [Double]
  /// For each off-plan edge on a bypass — a way off the plan that rejoins it
  /// as long as the plan between, give or take `bypassToleranceMeters` — the
  /// occurrences the bypass runs beside. On one, the car comes back to the
  /// plan where it would have been on the plan.
  let bypassSpans: [String: [ClosedRange<Int>]]

  /// The longest way off the plan counted as a bypass.
  static let bypassMeters = 1_000.0
  /// How much longer or shorter than the plan between a bypass can be. A
  /// detour that rejoins further on — a loop ramp, a PA's lanes — differs by
  /// far more.
  static let bypassToleranceMeters = 20.0

  /// How far from where it leaves the plan the car can be on a road the plan
  /// drives on another pass: past a PA stop's bypass and a missed exit until
  /// deviation evidence, short of the lap a loop needs to come back round.
  static let passDepartureMeters = 3_000.0

  var finalOccurrenceIndex: Int { routeStatesByIndex.count - 1 }

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
    var distances = [0.0]
    for state in routeStates.sorted(by: { $0.occurrenceIndex! < $1.occurrenceIndex! }) {
      let length = edges[state.edgeID]?.lengthMeters ?? 0
      distances.append(distances[distances.count - 1] + length)
    }
    routeDistanceBeforeIndex = distances
    var roots: [String: Set<Int>] = [:]
    for (edgeID, routeOccurrences) in occurrencesByEdgeID {
      let indexes = routeOccurrences.map(\.index)
      var queue = (edges[edgeID]?.successorEdgeIDs ?? [])
        .filter { occurrencesByEdgeID[$0] == nil }
        .sorted()
      var seen = Set(queue)
      while let offPlanEdgeID = queue.popLast() {
        roots[offPlanEdgeID, default: []].formUnion(indexes)
        for next in edges[offPlanEdgeID]?.successorEdgeIDs ?? []
        where occurrencesByEdgeID[next] == nil && seen.insert(next).inserted {
          queue.append(next)
        }
      }
    }
    self.branchRootOccurrenceIndexes = roots.mapValues { $0.sorted() }
    let departureRoots = Self.departureRoots(
      occurrences: corridor.occurrences.sorted { $0.index < $1.index },
      edges: edges,
      planEdgeIDs: Set(occurrencesByEdgeID.keys)
    )
    self.departureRootOccurrenceIndexes = departureRoots
    self.bypassSpans = Self.bypassSpans(
      occurrences: corridor.occurrences.sorted { $0.index < $1.index },
      edges: edges,
      occurrencesByEdgeID: occurrencesByEdgeID,
      routeDistanceBeforeIndex: distances
    )
    self.finalExitIndex = departureRoots.compactMap { edgeID, roots -> Int? in
      guard let lastPass = occurrencesByEdgeID[edgeID]?.map(\.index).max() else { return nil }
      return roots.last { $0 > lastPass }
    }.max()
  }

  /// Walks off the plan from each occurrence, up to `bypassMeters`, and keeps
  /// the ways that reach a later occurrence after as long a drive as the plan
  /// takes there.
  private static func bypassSpans(
    occurrences: [RouteMatcherOccurrence],
    edges: [String: MeasuredRouteEdge],
    occurrencesByEdgeID: [String: [RouteMatcherOccurrence]],
    routeDistanceBeforeIndex: [Double]
  ) -> [String: [ClosedRange<Int>]] {
    var spans: [String: [ClosedRange<Int>]] = [:]
    for (position, occurrence) in occurrences.enumerated().dropLast() {
      let next = occurrences[position + 1].directedEdgeID
      let leftAt = routeDistanceBeforeIndex[occurrence.index + 1]
      var meters: [String: Double] = [:]
      var previous: [String: String] = [:]
      var queue = (edges[occurrence.directedEdgeID]?.successorEdgeIDs ?? [])
        .filter { $0 != next && occurrencesByEdgeID[$0] == nil }.sorted()
      for start in queue { meters[start] = 0 }
      var head = 0
      while head < queue.count {
        let current = queue[head]
        head += 1
        let reached = meters[current]! + (edges[current]?.lengthMeters ?? 0)
        guard reached <= bypassMeters else { continue }
        for successor in edges[current]?.successorEdgeIDs ?? [] {
          if let rejoins = occurrencesByEdgeID[successor] {
            let rejoin = rejoins.map(\.index).filter { $0 > occurrence.index }.min {
              abs(routeDistanceBeforeIndex[$0] - leftAt - reached)
                < abs(routeDistanceBeforeIndex[$1] - leftAt - reached)
            }
            guard let rejoin,
              abs(routeDistanceBeforeIndex[rejoin] - leftAt - reached) <= bypassToleranceMeters
            else { continue }
            var edgeID: String? = current
            while let id = edgeID {
              spans[id, default: []].append(occurrence.index...rejoin)
              edgeID = previous[id]
            }
          } else if meters[successor].map({ reached < $0 }) ?? true {
            meters[successor] = reached
            previous[successor] = current
            queue.append(successor)
          }
        }
      }
    }
    return spans
  }

  /// Whether the off-plan edge is on a bypass beside occurrence `index`.
  func isBypass(_ edgeID: String, beside index: Int) -> Bool {
    bypassSpans[edgeID]?.contains { $0.contains(index) } == true
  }

  /// Walks the network from every place the plan can be left: each
  /// occurrence's successors other than the next occurrence's road. The
  /// final occurrence is where the plan ends, not a place it is left.
  private static func departureRoots(
    occurrences: [RouteMatcherOccurrence],
    edges: [String: MeasuredRouteEdge],
    planEdgeIDs: Set<String>
  ) -> [String: [Int]] {
    var departures: [[String]: [Int]] = [:]
    for (position, occurrence) in occurrences.enumerated().dropLast() {
      let next = occurrences[position + 1].directedEdgeID
      departures[[occurrence.directedEdgeID, next], default: []].append(occurrence.index)
    }
    var roots: [String: Set<Int>] = [:]
    for (pair, indexes) in departures {
      var meters: [String: Double] = [:]
      var queue = (edges[pair[0]]?.successorEdgeIDs ?? []).filter { $0 != pair[1] }.sorted()
      for start in queue { meters[start] = 0 }
      var position = 0
      while position < queue.count {
        let current = queue[position]
        position += 1
        let reached = meters[current]! + (edges[current]?.lengthMeters ?? 0)
        guard reached <= passDepartureMeters else { continue }
        for successor in edges[current]?.successorEdgeIDs ?? []
        where meters[successor].map({ reached < $0 }) ?? true {
          meters[successor] = reached
          queue.append(successor)
        }
      }
      for edgeID in meters.keys where planEdgeIDs.contains(edgeID) {
        roots[edgeID, default: []].formUnion(indexes)
      }
    }
    return roots.mapValues { $0.sorted() }
  }

  func isOffPlan(_ edgeID: String) -> Bool {
    statesByEdgeID[edgeID]?.allSatisfy { $0.occurrenceIndex == nil } == true
  }

  /// Until a fix has placed the car on the plan clear of every reachable
  /// branch (`lower` is nil), nothing anchors where it came from, so every
  /// off-plan road may be where it is. After that, only branches that leave
  /// the plan at or after that occurrence can. A road reached only past the
  /// final occurrence is where the plan ends, not a choice it competes with.
  func branchIsReachable(_ edgeID: String, from lower: Int?, through upper: Int?)
    -> Bool
  {
    if branchRootOccurrenceIndexes[edgeID] == [routeStatesByIndex.count - 1] {
      return false
    }
    guard let lower else { return true }
    return branchRootOccurrenceIndexes[edgeID]?.contains { root in
      root >= lower && upper.map { root <= $0 } != false
    } == true
  }

  /// A road of the plan, outside the window, the car can have left the plan
  /// for between `lower` and `upper`: missing a loop's exit carries it onto
  /// the lap it already drove, and passing a PA stop by onto the road the
  /// next lap takes. A road beside the plan that only another lap leads to
  /// is not one it can be on.
  func passIsReachable(_ edgeID: String, from lower: Int, through upper: Int?) -> Bool {
    departureRootOccurrenceIndexes[edgeID]?.contains { root in
      root >= lower && upper.map { root <= $0 } != false
    } == true
  }

  /// The edge and every road the car can have driven onto from it within
  /// the distance, counted from the edge's end: the car may be anywhere
  /// along the edge itself.
  func roadsAhead(of edgeID: String, withinMeters limit: Double) -> Set<String> {
    var queue = (edges[edgeID]?.successorEdgeIDs ?? []).sorted()
    var meters = Dictionary(uniqueKeysWithValues: queue.map { ($0, 0.0) })
    meters[edgeID] = 0
    var position = 0
    while position < queue.count {
      let current = queue[position]
      position += 1
      let reached = meters[current]! + (edges[current]?.lengthMeters ?? 0)
      guard reached <= limit else { continue }
      for successor in edges[current]?.successorEdgeIDs ?? []
      where meters[successor].map({ reached < $0 }) ?? true {
        meters[successor] = reached
        queue.append(successor)
      }
    }
    return Set(meters.keys)
  }

  /// A road the plan drove before its final exit and does not drive again.
  func isDrivenBeforeFinalExit(_ edgeID: String) -> Bool {
    guard let finalExitIndex else { return false }
    let passes = (statesByEdgeID[edgeID] ?? []).compactMap(\.occurrenceIndex)
    return !passes.isEmpty && passes.allSatisfy { $0 < finalExitIndex }
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

  /// The states an edge can be matched as: its passes inside the window, or,
  /// when every pass lies outside it, the edge as an off-plan road.
  func states(of edgeID: String, window: ClosedRange<Int>?) -> [MatcherState] {
    let states = statesByEdgeID[edgeID] ?? []
    guard let window else { return states }
    let inside = states.filter { $0.occurrenceIndex.map(window.contains) ?? true }
    return inside.isEmpty && !states.isEmpty
      ? [MatcherState(edgeID: edgeID, occurrenceID: nil, occurrenceIndex: nil)]
      : inside
  }

  /// A road of the plan whose every pass lies outside the window.
  func isPassOutsideWindow(_ edgeID: String, window: ClosedRange<Int>?) -> Bool {
    guard let window, let states = statesByEdgeID[edgeID],
      states.contains(where: { $0.occurrenceIndex != nil })
    else { return false }
    return states.allSatisfy { $0.occurrenceIndex.map { !window.contains($0) } ?? true }
  }

  func candidates(
    measuredEdges: [String: EdgeMeasurement],
    observation: RouteMatcherObservation,
    configuration: RouteAwareSwiftMatcherConfiguration,
    window: ClosedRange<Int>?
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
      return states(of: edgeID, window: window).map { state in
        let sigma = max(4, observation.horizontalAccuracyMeters)
        let distanceScore = -0.5 * pow(measurement.distanceMeters / sigma, 2)
        let headingScore: Double
        if let course = observation.courseDegrees,
          (observation.speedMetersPerSecond ?? 0) >= 2
        {
          let delta = angularDifferenceDegrees(course, measurement.bearingDegrees)
          let headingSigma = max(
            configuration.headingSigmaDegrees,
            observation.courseAccuracyDegrees ?? 0
          )
          headingScore = -0.5 * pow(delta / headingSigma, 2)
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

  /// Off-plan edges inside the candidate radius that are not clearly farther
  /// from the fix than the matched edge: within twice the ambiguity
  /// allowance the fix's reported accuracy grants. A precise fix on a ramp
  /// is separated from the mainline beside it; a 10 m fix is not.
  func offPlanEdgeIDs(
    within measuredEdges: [String: EdgeMeasurement],
    observation: RouteMatcherObservation,
    matchedDistanceMeters: Double?,
    matcherConfiguration: RouteAwareSwiftMatcherConfiguration,
    sessionConfiguration: RouteMatcherSessionConfiguration,
    window: ClosedRange<Int>?
  ) -> [String] {
    let candidateRadius = min(
      matcherConfiguration.maximumCandidateRadiusMeters,
      max(
        matcherConfiguration.minimumCandidateRadiusMeters,
        observation.horizontalAccuracyMeters
          * matcherConfiguration.accuracyRadiusMultiplier
      )
    )
    let allowance = max(
      sessionConfiguration.ambiguityMarginMeters,
      min(observation.horizontalAccuracyMeters, 25)
    )
    let radius = min(
      candidateRadius,
      (matchedDistanceMeters ?? candidateRadius) + 2 * allowance
    )
    let course =
      (observation.speedMetersPerSecond ?? 0) >= 2
      ? observation.courseDegrees : nil
    let headingTolerance = max(
      Self.offPlanHeadingToleranceDegrees,
      observation.courseAccuracyDegrees ?? 0
    )
    return measuredEdges.compactMap { edgeID, measurement in
      guard measurement.distanceMeters <= radius,
        isOffPlan(edgeID) || isPassOutsideWindow(edgeID, window: window),
        course.map({
          angularDifferenceDegrees($0, measurement.bearingDegrees)
            <= headingTolerance
        }) ?? true
      else { return nil }
      return edgeID
    }.sorted()
  }

  /// A road crossing or opposing the car's course is not a competing
  /// hypothesis for where it is driving.
  static let offPlanHeadingToleranceDegrees = 60.0

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
    lastOnPlanOccurrenceIndex: Int?
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
      if candidateIndex > previousIndex + 1 {
        guard
          let previousEdge = edges[previous.state.edgeID],
          let candidateEdge = edges[candidate.state.edgeID]
        else { return negativeInfinityScore }
        let intermediateDistance =
          routeDistanceBeforeIndex[candidateIndex]
          - routeDistanceBeforeIndex[previousIndex + 1]
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
    if previous.state.occurrenceIndex == nil, let candidateIndex = candidate.state.occurrenceIndex {
      // A road of the plan matched off it because every pass lay outside the
      // window is that later pass, not a detour: joining the plan there skips
      // to it from where the car was last on the plan, and costs that skip.
      if !isOffPlan(previous.state.edgeID), let lastOnPlanOccurrenceIndex,
        candidateIndex > lastOnPlanOccurrenceIndex + 1
      {
        return (connected ? -2 : -12) - Double(candidateIndex - lastOnPlanOccurrenceIndex - 1)
      }
      return connected ? -2 : -12
    }
    return connected ? -1.5 : -12
  }

  private func edgesConnected(_ lhsID: String, _ rhsID: String) -> Bool {
    edges[lhsID]?.successorEdgeIDs.contains(rhsID) == true
  }

  func isNearbyRouteEdge(
    _ edgeID: String,
    selectedState: MatcherState
  ) -> Bool {
    // A road of the plan matched outside the window is judged as its own
    // passes are: the next stretch of the same road is no rival to it.
    let selectedIndexes =
      selectedState.occurrenceIndex.map { [$0] }
      ?? (statesByEdgeID[selectedState.edgeID] ?? []).compactMap(\.occurrenceIndex)
    guard !selectedIndexes.isEmpty else { return edgeID == selectedState.edgeID }
    return selectedIndexes.contains { selectedIndex in
      let lower = max(
        0,
        selectedIndex - RouteMatcherCorridor.longitudinalCandidateOccurrenceWindow
      )
      let upper = min(
        routeStatesByIndex.count - 1,
        selectedIndex + RouteMatcherCorridor.longitudinalCandidateOccurrenceWindow
      )
      return (lower...upper).contains {
        routeStatesByIndex[$0]?.edgeID == edgeID
      }
    }
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
    let previousSpeedAccuracy =
      previous.observation.speedAccuracyMetersPerSecond
      ?? observation.speedAccuracyMetersPerSecond
      ?? 0
    let currentSpeedAccuracy =
      observation.speedAccuracyMetersPerSecond
      ?? previousSpeedAccuracy
    let speedUncertaintyDistance =
      (previousSpeedAccuracy + currentSpeedAccuracy) / 2
      * elapsedSeconds
    let tolerance = max(
      10,
      observation.horizontalAccuracyMeters * 2,
      expectedDistance * 0.75,
      speedUncertaintyDistance * 2
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
      courseAccuracyDegrees: replayObservation.courseAccuracyDegrees,
      speedMetersPerSecond: replayObservation.speedMetersPerSecond,
      speedAccuracyMetersPerSecond:
        replayObservation.speedAccuracyMetersPerSecond,
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
