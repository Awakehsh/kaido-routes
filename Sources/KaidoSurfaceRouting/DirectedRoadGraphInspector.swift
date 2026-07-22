import Foundation

public enum SurfaceRoadEdgeKind: String, Codable, Sendable {
  case ordinaryRoad = "ORDINARY_ROAD"
  case entryTransition = "ENTRY_TRANSITION"
  case expressway = "EXPRESSWAY"
}

public struct SurfaceRoadEdge: Codable, Equatable, Sendable {
  public let id: String
  public let fromNodeID: String
  public let toNodeID: String
  public let kind: SurfaceRoadEdgeKind
  public let coordinates: [SurfaceCoordinate]
  public let tollDomainID: String?

  public init(
    id: String,
    fromNodeID: String,
    toNodeID: String,
    kind: SurfaceRoadEdgeKind,
    coordinates: [SurfaceCoordinate],
    tollDomainID: String? = nil
  ) {
    self.id = id
    self.fromNodeID = fromNodeID
    self.toNodeID = toNodeID
    self.kind = kind
    self.coordinates = coordinates
    self.tollDomainID = tollDomainID
  }

  private enum CodingKeys: String, CodingKey {
    case id = "edge_id"
    case fromNodeID = "from_node_id"
    case toNodeID = "to_node_id"
    case kind
    case coordinates
    case tollDomainID = "toll_domain_id"
  }
}

public struct SurfaceRoadGraphSnapshot: Codable, Equatable, Sendable {
  public let networkSnapshotID: String
  public let edges: [SurfaceRoadEdge]

  public init(networkSnapshotID: String, edges: [SurfaceRoadEdge]) {
    self.networkSnapshotID = networkSnapshotID
    self.edges = edges
  }

  fileprivate var isStructurallyValid: Bool {
    guard !networkSnapshotID.isEmpty, !edges.isEmpty else { return false }
    guard Set(edges.map(\.id)).count == edges.count else { return false }
    return edges.allSatisfy { edge in
      !edge.id.isEmpty && !edge.fromNodeID.isEmpty && !edge.toNodeID.isEmpty
        && edge.coordinates.count >= 2
        && edge.coordinates.allSatisfy(\.isValid)
    }
  }

  private enum CodingKeys: String, CodingKey {
    case networkSnapshotID = "network_snapshot_id"
    case edges
  }
}

public struct DirectedRoadGraphInspectorConfiguration: Codable, Equatable, Sendable {
  public let sampleIntervalMeters: Double
  public let maximumMatchDistanceMeters: Double
  public let maximumHeadingDifferenceDegrees: Double
  public let headingPenaltyMeters: Double
  public let ambiguityMarginMeters: Double
  public let maximumSkippedEdgeHops: Int

  public init(
    sampleIntervalMeters: Double = 12,
    maximumMatchDistanceMeters: Double = 20,
    maximumHeadingDifferenceDegrees: Double = 55,
    headingPenaltyMeters: Double = 5,
    ambiguityMarginMeters: Double = 3,
    maximumSkippedEdgeHops: Int = 8
  ) {
    self.sampleIntervalMeters = sampleIntervalMeters
    self.maximumMatchDistanceMeters = maximumMatchDistanceMeters
    self.maximumHeadingDifferenceDegrees = maximumHeadingDifferenceDegrees
    self.headingPenaltyMeters = headingPenaltyMeters
    self.ambiguityMarginMeters = ambiguityMarginMeters
    self.maximumSkippedEdgeHops = maximumSkippedEdgeHops
  }

  fileprivate var isValid: Bool {
    sampleIntervalMeters > 0 && maximumMatchDistanceMeters > 0
      && (0...180).contains(maximumHeadingDifferenceDegrees)
      && headingPenaltyMeters >= 0 && ambiguityMarginMeters >= 0
      && maximumSkippedEdgeHops >= 0
  }

  private enum CodingKeys: String, CodingKey {
    case sampleIntervalMeters = "sample_interval_meters"
    case maximumMatchDistanceMeters = "maximum_match_distance_meters"
    case maximumHeadingDifferenceDegrees = "maximum_heading_difference_degrees"
    case headingPenaltyMeters = "heading_penalty_meters"
    case ambiguityMarginMeters = "ambiguity_margin_meters"
    case maximumSkippedEdgeHops = "maximum_skipped_edge_hops"
  }
}

/// Binds provider geometry to a small, versioned, directed road graph.
///
/// This is an offline feasibility inspector, not the live Shuto map matcher. It
/// deliberately fails closed when graph coverage, direction, or topology is
/// unresolved.
public struct DirectedRoadGraphInspector: SurfaceCandidateInspector {
  public let graph: SurfaceRoadGraphSnapshot
  public let configuration: DirectedRoadGraphInspectorConfiguration

  public init(
    graph: SurfaceRoadGraphSnapshot,
    configuration: DirectedRoadGraphInspectorConfiguration = .init()
  ) {
    self.graph = graph
    self.configuration = configuration
  }

  public func inspect(
    candidate: SurfaceRouteCandidate,
    request: SurfaceRouteRequest,
    fixture: EntranceProbeFixture
  ) async -> SurfaceCandidateInspection {
    guard graph.networkSnapshotID == fixture.networkSnapshotID,
      graph.isStructurallyValid,
      configuration.isValid,
      candidate.coordinates.count >= 2,
      candidate.coordinates.allSatisfy(\.isValid),
      let samples = routeSamples(for: candidate.coordinates),
      let terminalHeading = samples.last?.headingDegrees
    else {
      return failedInspection()
    }

    var matchedEdges: [SurfaceRoadEdge] = []
    var geometryIsUnambiguous = true

    for sample in samples {
      let matches = edgeMatches(at: sample.coordinate, headingDegrees: sample.headingDegrees)
      guard let best = matches.first else {
        geometryIsUnambiguous = false
        continue
      }

      if isAmbiguous(best: best, matches: matches) {
        geometryIsUnambiguous = false
      }
      matchedEdges.append(best.edge)
    }

    if matchedEdges.count != samples.count {
      geometryIsUnambiguous = false
    }

    let terminalCoordinate = candidate.coordinates[candidate.coordinates.count - 1]
    let terminalMatches = edgeMatches(
      at: terminalCoordinate,
      headingDegrees: terminalHeading
    )
    let terminalMatch = preferredTerminalMatch(
      matches: terminalMatches,
      expectedEdgeID: request.destinationAnchor.directedSurfaceEdgeID
    )

    if let terminalMatch, isAmbiguous(best: terminalMatch, matches: terminalMatches) {
      geometryIsUnambiguous = false
    }

    if matchedEdges.count == samples.count, let terminalMatch {
      matchedEdges[matchedEdges.count - 1] = terminalMatch.edge
    }

    let anchorBinding = terminalMatch.map { match in
      AnchorBindingObservation(
        anchorID: request.destinationAnchor.id,
        directedSurfaceEdgeID: match.edge.id,
        terminalDistanceMeters: distanceMeters(
          from: terminalCoordinate,
          to: request.destinationAnchor.coordinate
        ),
        terminalBearingDegrees: terminalHeading
      )
    }

    let matchedSequence = collapseAdjacentDuplicates(in: matchedEdges)
    let resolvedEdges = resolveContinuousPath(matchedSequence)
    if resolvedEdges == nil {
      geometryIsUnambiguous = false
    }
    let inspectedEdges = resolvedEdges ?? matchedSequence
    return SurfaceCandidateInspection(
      anchorBinding: anchorBinding,
      geometryBindingIsUnambiguous: geometryIsUnambiguous && anchorBinding != nil,
      expresswayEdgeIDsBeforeEntry: uniqueIDs(
        inspectedEdges.filter { $0.kind != .ordinaryRoad }.map(\.id)
      ),
      crossedTollDomainIDs: uniqueIDs(inspectedEdges.compactMap(\.tollDomainID))
    )
  }

  private func failedInspection() -> SurfaceCandidateInspection {
    SurfaceCandidateInspection(
      anchorBinding: nil,
      geometryBindingIsUnambiguous: false,
      expresswayEdgeIDsBeforeEntry: nil,
      crossedTollDomainIDs: nil
    )
  }

  private func routeSamples(for coordinates: [SurfaceCoordinate]) -> [RouteSample]? {
    var result: [RouteSample] = []

    for index in 0..<(coordinates.count - 1) {
      let start = coordinates[index]
      let end = coordinates[index + 1]
      let segmentLength = distanceMeters(from: start, to: end)
      guard segmentLength > 0 else { continue }

      let heading = bearingDegrees(from: start, to: end)
      let divisions = max(1, Int(ceil(segmentLength / configuration.sampleIntervalMeters)))
      if result.isEmpty {
        result.append(RouteSample(coordinate: start, headingDegrees: heading))
      }
      for division in 1...divisions {
        result.append(
          RouteSample(
            coordinate: interpolate(
              from: start,
              to: end,
              fraction: Double(division) / Double(divisions)
            ),
            headingDegrees: heading
          )
        )
      }
    }

    return result.isEmpty ? nil : result
  }

  private func edgeMatches(
    at coordinate: SurfaceCoordinate,
    headingDegrees: Double
  ) -> [EdgeMatch] {
    graph.edges.compactMap { edge in
      var bestProjection: EdgeProjection?
      for index in 0..<(edge.coordinates.count - 1) {
        let start = edge.coordinates[index]
        let end = edge.coordinates[index + 1]
        let projection = project(coordinate, ontoSegmentFrom: start, to: end)
        let headingDifference = angularDifference(
          headingDegrees,
          bearingDegrees(from: start, to: end)
        )
        guard projection.distanceMeters <= configuration.maximumMatchDistanceMeters,
          headingDifference <= configuration.maximumHeadingDifferenceDegrees
        else { continue }

        let candidate = EdgeProjection(
          distanceMeters: projection.distanceMeters,
          headingDifferenceDegrees: headingDifference
        )
        if bestProjection == nil
          || candidate.score(configuration: configuration)
            < bestProjection!.score(configuration: configuration)
        {
          bestProjection = candidate
        }
      }

      guard let bestProjection else { return nil }
      return EdgeMatch(
        edge: edge,
        distanceMeters: bestProjection.distanceMeters,
        headingDifferenceDegrees: bestProjection.headingDifferenceDegrees,
        score: bestProjection.score(configuration: configuration)
      )
    }
    .sorted { lhs, rhs in
      if lhs.score != rhs.score { return lhs.score < rhs.score }
      if lhs.distanceMeters != rhs.distanceMeters {
        return lhs.distanceMeters < rhs.distanceMeters
      }
      if lhs.headingDifferenceDegrees != rhs.headingDifferenceDegrees {
        return lhs.headingDifferenceDegrees < rhs.headingDifferenceDegrees
      }
      return lhs.edge.id < rhs.edge.id
    }
  }

  private func preferredTerminalMatch(
    matches: [EdgeMatch],
    expectedEdgeID: String
  ) -> EdgeMatch? {
    guard let best = matches.first else { return nil }
    guard let expected = matches.first(where: { $0.edge.id == expectedEdgeID }) else {
      return best
    }
    return expected.score <= best.score + configuration.ambiguityMarginMeters
      ? expected : best
  }

  private func isAmbiguous(best: EdgeMatch, matches: [EdgeMatch]) -> Bool {
    matches.contains { alternative in
      alternative.edge.id != best.edge.id
        && alternative.score <= best.score + configuration.ambiguityMarginMeters
        && !edgesFormOneDirectedPath(best.edge, alternative.edge)
    }
  }

  private func edgesFormOneDirectedPath(_ lhs: SurfaceRoadEdge, _ rhs: SurfaceRoadEdge) -> Bool {
    lhs.toNodeID == rhs.fromNodeID || rhs.toNodeID == lhs.fromNodeID
  }

  private func resolveContinuousPath(_ edges: [SurfaceRoadEdge]) -> [SurfaceRoadEdge]? {
    guard let first = edges.first else { return nil }
    var result = [first]

    for target in edges.dropFirst() {
      guard let source = result.last,
        let connectors = connectorEdges(from: source, to: target)
      else { return nil }

      for connector in connectors where result.last?.id != connector.id {
        result.append(connector)
      }
      if result.last?.id != target.id {
        result.append(target)
      }
    }
    return result
  }

  private func connectorEdges(
    from source: SurfaceRoadEdge,
    to target: SurfaceRoadEdge
  ) -> [SurfaceRoadEdge]? {
    if source.id == target.id || source.toNodeID == target.fromNodeID { return [] }

    let outgoing = Dictionary(grouping: graph.edges, by: \.fromNodeID).mapValues {
      $0.sorted { $0.id < $1.id }
    }
    var queue: [(nodeID: String, path: [SurfaceRoadEdge])] = [(source.toNodeID, [])]
    var visited: Set<String> = [source.toNodeID]
    var cursor = 0

    while cursor < queue.count {
      let state = queue[cursor]
      cursor += 1
      if state.nodeID == target.fromNodeID { return state.path }
      guard state.path.count < configuration.maximumSkippedEdgeHops else { continue }

      for edge in outgoing[state.nodeID, default: []] {
        if edge.id == target.id { return state.path }
        let path = state.path + [edge]
        if edge.toNodeID == target.fromNodeID { return path }
        if visited.insert(edge.toNodeID).inserted {
          queue.append((edge.toNodeID, path))
        }
      }
    }
    return nil
  }

  private func collapseAdjacentDuplicates(in edges: [SurfaceRoadEdge]) -> [SurfaceRoadEdge] {
    edges.reduce(into: []) { result, edge in
      if result.last?.id != edge.id { result.append(edge) }
    }
  }

  private func uniqueIDs(_ ids: [String]) -> [String] {
    var seen: Set<String> = []
    return ids.filter { seen.insert($0).inserted }
  }
}

private struct RouteSample {
  let coordinate: SurfaceCoordinate
  let headingDegrees: Double
}

private struct EdgeMatch {
  let edge: SurfaceRoadEdge
  let distanceMeters: Double
  let headingDifferenceDegrees: Double
  let score: Double
}

private struct EdgeProjection {
  let distanceMeters: Double
  let headingDifferenceDegrees: Double

  func score(configuration: DirectedRoadGraphInspectorConfiguration) -> Double {
    distanceMeters
      + headingDifferenceDegrees / max(1, configuration.maximumHeadingDifferenceDegrees)
      * configuration.headingPenaltyMeters
  }
}

private let earthRadiusMeters = 6_371_000.0

private func distanceMeters(from start: SurfaceCoordinate, to end: SurfaceCoordinate) -> Double {
  let startLatitude = radians(start.latitude)
  let endLatitude = radians(end.latitude)
  let latitudeDelta = endLatitude - startLatitude
  let longitudeDelta = radians(end.longitude - start.longitude)
  let haversine =
    sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
    + cos(startLatitude) * cos(endLatitude)
    * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
  return earthRadiusMeters * 2 * atan2(sqrt(haversine), sqrt(max(0, 1 - haversine)))
}

private func bearingDegrees(from start: SurfaceCoordinate, to end: SurfaceCoordinate) -> Double {
  let startLatitude = radians(start.latitude)
  let endLatitude = radians(end.latitude)
  let longitudeDelta = radians(end.longitude - start.longitude)
  let y = sin(longitudeDelta) * cos(endLatitude)
  let x =
    cos(startLatitude) * sin(endLatitude)
    - sin(startLatitude) * cos(endLatitude) * cos(longitudeDelta)
  return normalizedDegrees(degrees(atan2(y, x)))
}

private func angularDifference(_ lhs: Double, _ rhs: Double) -> Double {
  let difference = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
  return min(difference, 360 - difference)
}

private func interpolate(
  from start: SurfaceCoordinate,
  to end: SurfaceCoordinate,
  fraction: Double
) -> SurfaceCoordinate {
  SurfaceCoordinate(
    latitude: start.latitude + (end.latitude - start.latitude) * fraction,
    longitude: start.longitude + (end.longitude - start.longitude) * fraction
  )
}

private func project(
  _ point: SurfaceCoordinate,
  ontoSegmentFrom start: SurfaceCoordinate,
  to end: SurfaceCoordinate
) -> (distanceMeters: Double, fraction: Double) {
  let referenceLatitude = radians((point.latitude + start.latitude + end.latitude) / 3)
  let startX =
    radians(start.longitude - point.longitude) * cos(referenceLatitude)
    * earthRadiusMeters
  let startY = radians(start.latitude - point.latitude) * earthRadiusMeters
  let endX =
    radians(end.longitude - point.longitude) * cos(referenceLatitude)
    * earthRadiusMeters
  let endY = radians(end.latitude - point.latitude) * earthRadiusMeters
  let deltaX = endX - startX
  let deltaY = endY - startY
  let lengthSquared = deltaX * deltaX + deltaY * deltaY
  let fraction: Double
  if lengthSquared == 0 {
    fraction = 0
  } else {
    fraction = min(1, max(0, -(startX * deltaX + startY * deltaY) / lengthSquared))
  }
  let projectedX = startX + deltaX * fraction
  let projectedY = startY + deltaY * fraction
  return (sqrt(projectedX * projectedX + projectedY * projectedY), fraction)
}

private func radians(_ degrees: Double) -> Double {
  degrees * .pi / 180
}

private func degrees(_ radians: Double) -> Double {
  radians * 180 / .pi
}

private func normalizedDegrees(_ degrees: Double) -> Double {
  let value = degrees.truncatingRemainder(dividingBy: 360)
  return value >= 0 ? value : value + 360
}
