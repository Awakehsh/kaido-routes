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
  case missingInitialOccurrence(String)
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
    let model = try MatcherModel(fixture: fixture)
    var paths: [StateKey: PathState] = [:]
    var lastAcceptedObservation: MatcherReplayObservation?
    var estimates: [MatcherEstimate] = []

    for observation in fixture.observations {
      let measuredEdges = model.edges.mapValues { $0.measure(observation.coordinate) }
      let candidates = model.candidates(
        measuredEdges: measuredEdges,
        observation: observation,
        configuration: configuration
      )
      let isStale = isStaleObservation(
        observation,
        after: lastAcceptedObservation,
        thresholdMilliseconds: fixture.configuration.staleObservationThresholdMilliseconds
      )

      if candidates.isEmpty {
        estimates.append(
          MatcherEstimate(
            observationID: observation.id,
            estimatedAtMilliseconds: observation.observedAtMilliseconds,
            directedEdgeID: nil,
            occurrenceID: nil,
            candidateEdgeIDs: [],
            confidence: .lost,
            distanceMeters: nil
          )
        )
        continue
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
            model.initialScore(for: $0.state) + $0.emissionScore
              < model.initialScore(for: $1.state) + $1.emissionScore
          })
        {
          selected = PathState(
            state: initial.state,
            score: model.initialScore(for: initial.state) + initial.emissionScore,
            measurement: initial.measurement,
            observation: observation
          )
        } else {
          selected = nil
        }
        guard let selected else {
          estimates.append(
            MatcherEstimate(
              observationID: observation.id,
              estimatedAtMilliseconds: observation.observedAtMilliseconds,
              directedEdgeID: nil,
              occurrenceID: nil,
              candidateEdgeIDs: candidates.map(\.state.edgeID).uniqued().sorted(),
              confidence: .lost,
              distanceMeters: nil
            )
          )
          continue
        }
        let transientPaths = [selected.state.key: selected]
        estimates.append(
          makeEstimate(
            observation: observation,
            selected: selected,
            paths: transientPaths,
            candidates: candidates,
            measuredEdges: measuredEdges,
            fixture: fixture,
            forceLow: true
          )
        )
        continue
      }

      let nextPaths: [StateKey: PathState]
      if paths.isEmpty {
        nextPaths = Dictionary(
          uniqueKeysWithValues: candidates.map { candidate in
            let score = model.initialScore(for: candidate.state) + candidate.emissionScore
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
                    gapThresholdMilliseconds: fixture.configuration
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
      paths = nextPaths.filter { $0.value.score > negativeInfinityScore / 2 }
      guard let selected = bestPath(in: paths) else {
        estimates.append(
          MatcherEstimate(
            observationID: observation.id,
            estimatedAtMilliseconds: observation.observedAtMilliseconds,
            directedEdgeID: nil,
            occurrenceID: nil,
            candidateEdgeIDs: candidates.map(\.state.edgeID).uniqued().sorted(),
            confidence: .lost,
            distanceMeters: nil
          )
        )
        continue
      }
      let hasObservationGap =
        lastAcceptedObservation.map {
          observation.observedAtMilliseconds - $0.observedAtMilliseconds
            >= fixture.configuration.observationGapThresholdMilliseconds
        } ?? false
      estimates.append(
        makeEstimate(
          observation: observation,
          selected: selected,
          paths: paths,
          candidates: candidates,
          measuredEdges: measuredEdges,
          fixture: fixture,
          forceLow: hasObservationGap
        )
      )
      lastAcceptedObservation = observation
    }
    return estimates
  }

  private func isStaleObservation(
    _ observation: MatcherReplayObservation,
    after previous: MatcherReplayObservation?,
    thresholdMilliseconds: Int
  ) -> Bool {
    if observation.receivedAtMilliseconds - observation.observedAtMilliseconds
      >= thresholdMilliseconds
    {
      return true
    }
    if let previous,
      observation.observedAtMilliseconds <= previous.observedAtMilliseconds
    {
      return true
    }
    return false
  }

  private func makeEstimate(
    observation: MatcherReplayObservation,
    selected: PathState,
    paths: [StateKey: PathState],
    candidates: [StateCandidate],
    measuredEdges: [String: EdgeMeasurement],
    fixture: MatcherReplayFixture,
    forceLow: Bool
  ) -> MatcherEstimate {
    let bestMeasuredDistance = measuredEdges.values.map(\.distanceMeters).min() ?? .infinity
    let geometryAllowance = max(
      fixture.configuration.ambiguityMarginMeters,
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
        <= configuration.indistinguishableDistanceMeters
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
      scoreMargin >= configuration.minimumHighScoreMargin
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
      distanceMeters: selected.measurement.distanceMeters
    )
  }
}

private struct MatcherModel: Sendable {
  let edges: [String: MeasuredRouteEdge]
  let states: [MatcherState]
  let routeStatesByIndex: [Int: MatcherState]
  let initialOccurrenceIndex: Int?

  init(fixture: MatcherReplayFixture) throws {
    self.edges = Dictionary(
      uniqueKeysWithValues: fixture.edges.map { ($0.id, MeasuredRouteEdge(edge: $0)) }
    )
    let occurrencesByEdgeID = Dictionary(grouping: fixture.routeOccurrences, by: \.directedEdgeID)
    let routeStates = fixture.routeOccurrences.map { occurrence in
      MatcherState(
        edgeID: occurrence.directedEdgeID,
        occurrenceID: occurrence.occurrenceID,
        occurrenceIndex: occurrence.index
      )
    }
    self.routeStatesByIndex = Dictionary(
      uniqueKeysWithValues: routeStates.map { ($0.occurrenceIndex!, $0) }
    )
    var states = routeStates
    states.append(
      contentsOf: fixture.edges.compactMap { edge in
        guard occurrencesByEdgeID[edge.id] == nil else { return nil }
        return MatcherState(edgeID: edge.id, occurrenceID: nil, occurrenceIndex: nil)
      }
    )
    self.states = states
    if let initialOccurrenceID = fixture.initialOccurrenceID {
      guard
        let index = fixture.routeOccurrences.first(where: {
          $0.occurrenceID == initialOccurrenceID
        })?.index
      else {
        throw RouteAwareSwiftMatcherError.missingInitialOccurrence(initialOccurrenceID)
      }
      self.initialOccurrenceIndex = index
    } else {
      self.initialOccurrenceIndex = nil
    }
  }

  func candidates(
    measuredEdges: [String: EdgeMeasurement],
    observation: MatcherReplayObservation,
    configuration: RouteAwareSwiftMatcherConfiguration
  ) -> [StateCandidate] {
    let radius = min(
      configuration.maximumCandidateRadiusMeters,
      max(
        configuration.minimumCandidateRadiusMeters,
        observation.horizontalAccuracyMeters * configuration.accuracyRadiusMultiplier
      )
    )
    return states.compactMap { state in
      guard let measurement = measuredEdges[state.edgeID], measurement.distanceMeters <= radius
      else { return nil }
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

  func initialScore(for state: MatcherState) -> Double {
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
    observation: MatcherReplayObservation,
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
    guard let lhs = edges[lhsID], let rhs = edges[rhsID] else { return false }
    return matcherCoordinateDistanceMeters(lhs.coordinates.last!, rhs.coordinates.first!) <= 3
  }

  private func travelConsistencyScore(
    networkDistanceMeters: Double,
    previous: PathState,
    observation: MatcherReplayObservation
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
  let observation: MatcherReplayObservation
}

private struct EdgeMeasurement: Sendable {
  let distanceMeters: Double
  let fractionAlong: Double
  let bearingDegrees: Double
}

private struct MeasuredRouteEdge: Sendable {
  let coordinates: [MatcherCoordinate]
  let segmentLengths: [Double]
  let lengthMeters: Double

  init(edge: MatcherReplayEdge) {
    self.coordinates = edge.coordinates
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

private func matcherCoordinateDistanceMeters(
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

private func bestPath(in paths: [StateKey: PathState]) -> PathState? {
  paths.values.max {
    if abs($0.score - $1.score) < 0.000_001 {
      return ($0.state.occurrenceIndex ?? Int.max, $0.state.edgeID)
        > ($1.state.occurrenceIndex ?? Int.max, $1.state.edgeID)
    }
    return $0.score < $1.score
  }
}

private let negativeInfinityScore = -1_000_000_000.0
private let matcherEarthRadiusMeters = 6_371_000.0

extension Sequence where Element: Hashable {
  fileprivate func uniqued() -> [Element] {
    var seen: Set<Element> = []
    return filter { seen.insert($0).inserted }
  }
}
