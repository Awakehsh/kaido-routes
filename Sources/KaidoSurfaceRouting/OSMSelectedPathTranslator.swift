import Foundation

/// One provider graph edge identified against its source OSM way.
///
/// A provider adapter must retain the beginning OSM node and digitized
/// direction. A way ID by itself is not directional and cannot distinguish a
/// subset when the provider splits one OSM way into several graph edges.
public struct OSMPathEdgeReference: Codable, Equatable, Sendable {
  public let providerEdgeID: String
  public let osmWayID: Int64
  public let beginOSMNodeID: Int64
  public let isForward: Bool
  public let sourcePercentAlong: Double
  public let targetPercentAlong: Double

  public init(
    providerEdgeID: String,
    osmWayID: Int64,
    beginOSMNodeID: Int64,
    isForward: Bool,
    sourcePercentAlong: Double = 0,
    targetPercentAlong: Double = 1
  ) {
    self.providerEdgeID = providerEdgeID
    self.osmWayID = osmWayID
    self.beginOSMNodeID = beginOSMNodeID
    self.isForward = isForward
    self.sourcePercentAlong = sourcePercentAlong
    self.targetPercentAlong = targetPercentAlong
  }

  private enum CodingKeys: String, CodingKey {
    case providerEdgeID = "provider_edge_id"
    case osmWayID = "osm_way_id"
    case beginOSMNodeID = "begin_osm_node_id"
    case isForward = "is_forward"
    case sourcePercentAlong = "source_percent_along"
    case targetPercentAlong = "target_percent_along"
  }
}

/// Provider-neutral input for translating an OSM-backed selected route.
///
/// Valhalla can populate this from `trace_attributes` by requesting `edge.id`,
/// `edge.way_id`, `edge.forward`, `edge.begin_osm_node_id`, and `edge.length`.
/// The final node is supplied by the reviewed Kaido approach anchor because a
/// trace edge exposes its beginning node, while the next trace edge normally
/// supplies the preceding edge's end node.
public struct OSMSelectedPathTranslationRequest: Codable, Equatable, Sendable {
  public let providerDatasetID: String
  public let terminalOSMNodeID: Int64
  public let routeCoordinates: [SurfaceCoordinate]
  public let edgeReferences: [OSMPathEdgeReference]

  public init(
    providerDatasetID: String,
    terminalOSMNodeID: Int64,
    routeCoordinates: [SurfaceCoordinate],
    edgeReferences: [OSMPathEdgeReference]
  ) {
    self.providerDatasetID = providerDatasetID
    self.terminalOSMNodeID = terminalOSMNodeID
    self.routeCoordinates = routeCoordinates
    self.edgeReferences = edgeReferences
  }

  private enum CodingKeys: String, CodingKey {
    case providerDatasetID = "provider_dataset_id"
    case terminalOSMNodeID = "terminal_osm_node_id"
    case routeCoordinates = "route_coordinates"
    case edgeReferences = "edge_references"
  }
}

public struct OSMSelectedPathTranslatorConfiguration: Codable, Equatable, Sendable {
  public let maximumEndpointDistanceMeters: Double
  public let maximumEndpointHeadingDifferenceDegrees: Double
  public let maximumPercentAlongDifference: Double

  public init(
    maximumEndpointDistanceMeters: Double = 20,
    maximumEndpointHeadingDifferenceDegrees: Double = 70,
    maximumPercentAlongDifference: Double = 0.03
  ) {
    self.maximumEndpointDistanceMeters = maximumEndpointDistanceMeters
    self.maximumEndpointHeadingDifferenceDegrees = maximumEndpointHeadingDifferenceDegrees
    self.maximumPercentAlongDifference = maximumPercentAlongDifference
  }

  fileprivate var isValid: Bool {
    maximumEndpointDistanceMeters > 0
      && (0...180).contains(maximumEndpointHeadingDifferenceDegrees)
      && (0...1).contains(maximumPercentAlongDifference)
  }

  private enum CodingKeys: String, CodingKey {
    case maximumEndpointDistanceMeters = "maximum_endpoint_distance_meters"
    case maximumEndpointHeadingDifferenceDegrees =
      "maximum_endpoint_heading_difference_degrees"
    case maximumPercentAlongDifference = "maximum_percent_along_difference"
  }
}

public enum OSMSelectedPathTranslationError: Error, Equatable, Sendable {
  case invalidGraph
  case invalidConfiguration
  case datasetMismatch(expected: String?, received: String)
  case invalidRouteGeometry
  case invalidReference(index: Int)
  case missingPath(index: Int)
  case ambiguousPath(index: Int)
  case unresolvedStart
  case unresolvedTerminal
  case discontinuousPath
  case repeatedDirectedEdge
}

extension OSMSelectedPathTranslationError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .invalidGraph:
      "the Kaido graph is empty or lacks OSM edge provenance"
    case .invalidConfiguration:
      "the OSM selected-path translator configuration is invalid"
    case .datasetMismatch(let expected, let received):
      "provider dataset \(received) does not match graph dataset \(expected ?? "<missing>")"
    case .invalidRouteGeometry:
      "the provider route geometry is invalid"
    case .invalidReference(let index):
      "provider edge reference \(index) is invalid"
    case .missingPath(let index):
      "provider edge reference \(index) has no exact Kaido path"
    case .ambiguousPath(let index):
      "provider edge reference \(index) maps to multiple Kaido paths"
    case .unresolvedStart:
      "the provider route start does not resolve on the first selected edge"
    case .unresolvedTerminal:
      "the provider route terminal does not resolve on the final selected edge"
    case .discontinuousPath:
      "translated Kaido edges are not directly continuous"
    case .repeatedDirectedEdge:
      "translated Kaido path repeats a directed edge"
    }
  }
}

/// Translates provider-selected OSM edge identity onto one exact Kaido graph.
///
/// The translator does not rematch an opaque polyline. It expands every
/// provider edge between explicit OSM nodes, then uses the provider geometry
/// only to trim the partially traversed first and last graph edges. Any missing,
/// ambiguous, discontinuous, or cross-dataset identity fails closed.
public struct OSMSelectedPathTranslator: Sendable {
  public let graph: SurfaceRoadGraphSnapshot
  public let configuration: OSMSelectedPathTranslatorConfiguration
  private let edgesByWayAndDirection: [WayDirection: [SurfaceRoadEdge]]

  public init(
    graph: SurfaceRoadGraphSnapshot,
    configuration: OSMSelectedPathTranslatorConfiguration = .init()
  ) {
    self.graph = graph
    self.configuration = configuration
    self.edgesByWayAndDirection = Dictionary(
      grouping: graph.edges.compactMap { edge in
        guard let wayID = edge.sourceOSMWayID,
          let direction = edge.sourceOSMDirection,
          edge.sourceOSMSegmentIndex != nil
        else { return nil }
        return IndexedEdge(key: WayDirection(wayID: wayID, direction: direction), edge: edge)
      },
      by: \IndexedEdge.key
    )
    .mapValues { $0.map(\.edge) }
  }

  public func translate(
    _ request: OSMSelectedPathTranslationRequest
  ) throws -> SurfaceSelectedPathEvidence {
    guard !graph.networkSnapshotID.isEmpty, !graph.edges.isEmpty,
      !edgesByWayAndDirection.isEmpty
    else {
      throw OSMSelectedPathTranslationError.invalidGraph
    }
    guard configuration.isValid else {
      throw OSMSelectedPathTranslationError.invalidConfiguration
    }
    guard !request.providerDatasetID.isEmpty,
      request.providerDatasetID == graph.provenance?.sourceDatasetID
    else {
      throw OSMSelectedPathTranslationError.datasetMismatch(
        expected: graph.provenance?.sourceDatasetID,
        received: request.providerDatasetID
      )
    }
    guard request.routeCoordinates.count >= 2,
      request.routeCoordinates.allSatisfy(\.isValid),
      let initialHeading = firstHeading(in: request.routeCoordinates),
      let terminalHeading = lastHeading(in: request.routeCoordinates),
      !request.edgeReferences.isEmpty
    else {
      throw OSMSelectedPathTranslationError.invalidRouteGeometry
    }

    var expandedPaths: [[SurfaceRoadEdge]] = []
    for (index, reference) in request.edgeReferences.enumerated() {
      try validate(reference: reference, at: index, count: request.edgeReferences.count)
      let endNodeID =
        index + 1 < request.edgeReferences.count
        ? request.edgeReferences[index + 1].beginOSMNodeID
        : request.terminalOSMNodeID
      let paths = exactPaths(
        for: reference,
        fromNodeID: osmNodeID(reference.beginOSMNodeID),
        toNodeID: osmNodeID(endNodeID)
      )
      guard !paths.isEmpty else {
        throw OSMSelectedPathTranslationError.missingPath(index: index)
      }
      guard paths.count == 1 else {
        throw OSMSelectedPathTranslationError.ambiguousPath(index: index)
      }
      expandedPaths.append(paths[0])
    }

    guard let firstPath = expandedPaths.first,
      let lastPath = expandedPaths.last,
      let startIndex = endpointEdgeIndex(
        coordinate: request.routeCoordinates[0],
        headingDegrees: initialHeading,
        expectedPercentAlong: request.edgeReferences[0].sourcePercentAlong,
        role: .start,
        in: firstPath
      )
    else {
      throw OSMSelectedPathTranslationError.unresolvedStart
    }
    guard
      let terminalIndex = endpointEdgeIndex(
        coordinate: request.routeCoordinates[request.routeCoordinates.count - 1],
        headingDegrees: terminalHeading,
        expectedPercentAlong: request.edgeReferences[request.edgeReferences.count - 1]
          .targetPercentAlong,
        role: .terminal,
        in: lastPath
      )
    else {
      throw OSMSelectedPathTranslationError.unresolvedTerminal
    }

    let startOffset = startIndex
    let terminalOffset = expandedPaths.dropLast().reduce(0) { $0 + $1.count } + terminalIndex
    let expandedEdges = expandedPaths.flatMap { $0 }
    guard startOffset <= terminalOffset else {
      throw OSMSelectedPathTranslationError.discontinuousPath
    }
    let selectedEdges = Array(expandedEdges[startOffset...terminalOffset])
    guard
      zip(selectedEdges, selectedEdges.dropFirst()).allSatisfy({ pair in
        pair.0.toNodeID == pair.1.fromNodeID
      })
    else {
      throw OSMSelectedPathTranslationError.discontinuousPath
    }
    let selectedEdgeIDs = selectedEdges.map(\.id)
    guard Set(selectedEdgeIDs).count == selectedEdgeIDs.count else {
      throw OSMSelectedPathTranslationError.repeatedDirectedEdge
    }

    return SurfaceSelectedPathEvidence(
      networkSnapshotID: graph.networkSnapshotID,
      providerDatasetID: request.providerDatasetID,
      directedEdgeIDs: selectedEdgeIDs
    )
  }

  private func validate(
    reference: OSMPathEdgeReference,
    at index: Int,
    count: Int
  ) throws {
    let percentagesAreValid =
      (0...1).contains(reference.sourcePercentAlong)
      && (0...1).contains(reference.targetPercentAlong)
      && reference.sourcePercentAlong < reference.targetPercentAlong
    let interiorStartsAtBeginning = index == 0 || reference.sourcePercentAlong == 0
    let interiorEndsAtEnd = index == count - 1 || reference.targetPercentAlong == 1
    guard !reference.providerEdgeID.isEmpty, reference.osmWayID > 0,
      reference.beginOSMNodeID > 0, percentagesAreValid,
      interiorStartsAtBeginning, interiorEndsAtEnd
    else {
      throw OSMSelectedPathTranslationError.invalidReference(index: index)
    }
  }

  private func exactPaths(
    for reference: OSMPathEdgeReference,
    fromNodeID: String,
    toNodeID: String
  ) -> [[SurfaceRoadEdge]] {
    let direction: OSMWayDirection = reference.isForward ? .forward : .reverse
    guard
      let candidateEdges = edgesByWayAndDirection[
        WayDirection(wayID: reference.osmWayID, direction: direction)
      ]
    else { return [] }

    let outgoing = Dictionary(grouping: candidateEdges, by: \SurfaceRoadEdge.fromNodeID)
      .mapValues { edges in
        edges.sorted {
          ($0.sourceOSMSegmentIndex ?? -1, $0.id)
            < ($1.sourceOSMSegmentIndex ?? -1, $1.id)
        }
      }
    var results: [[SurfaceRoadEdge]] = []

    func walk(nodeID: String, path: [SurfaceRoadEdge], visitedEdgeIDs: Set<String>) {
      guard results.count < 2 else { return }
      if nodeID == toNodeID {
        if !path.isEmpty { results.append(path) }
        return
      }
      for edge in outgoing[nodeID] ?? [] where !visitedEdgeIDs.contains(edge.id) {
        var visited = visitedEdgeIDs
        visited.insert(edge.id)
        walk(nodeID: edge.toNodeID, path: path + [edge], visitedEdgeIDs: visited)
      }
    }

    walk(nodeID: fromNodeID, path: [], visitedEdgeIDs: [])
    return results
  }

  private func endpointEdgeIndex(
    coordinate: SurfaceCoordinate,
    headingDegrees: Double,
    expectedPercentAlong: Double,
    role: EndpointRole,
    in edges: [SurfaceRoadEdge]
  ) -> Int? {
    let lengths = edges.map(edgeLengthMeters)
    let totalLength = lengths.reduce(0, +)
    guard totalLength > 0 else { return nil }
    var cumulativeLength = 0.0
    var matches: [EndpointMatch] = []

    for (index, edge) in edges.enumerated() {
      let length = lengths[index]
      defer { cumulativeLength += length }
      guard let projection = closestProjection(of: coordinate, onto: edge), length > 0 else {
        continue
      }
      let directionDifference = angularDifference(
        headingDegrees,
        projection.segmentHeadingDegrees
      )
      let percentAlong = (cumulativeLength + projection.alongEdgeDistanceMeters) / totalLength
      let percentDifference = abs(percentAlong - expectedPercentAlong)
      let percentTolerance = max(
        configuration.maximumPercentAlongDifference,
        configuration.maximumEndpointDistanceMeters / totalLength
      )
      guard projection.distanceMeters <= configuration.maximumEndpointDistanceMeters,
        directionDifference <= configuration.maximumEndpointHeadingDifferenceDegrees,
        percentDifference <= percentTolerance
      else { continue }

      let endpointPenalty: Double
      switch role {
      case .start:
        endpointPenalty = projection.fractionAlongEdge >= 0.999 ? 5 : 0
      case .terminal:
        endpointPenalty = projection.fractionAlongEdge <= 0.001 ? 5 : 0
      }
      matches.append(
        EndpointMatch(
          edgeIndex: index,
          score: projection.distanceMeters + directionDifference * 0.05
            + percentDifference * 10 + endpointPenalty
        )
      )
    }

    let sorted = matches.sorted {
      $0.score == $1.score ? $0.edgeIndex < $1.edgeIndex : $0.score < $1.score
    }
    guard let best = sorted.first else { return nil }
    if sorted.count > 1, sorted[1].score - best.score < 0.1 { return nil }
    return best.edgeIndex
  }
}

private struct WayDirection: Hashable, Sendable {
  let wayID: Int64
  let direction: OSMWayDirection
}

private struct IndexedEdge: Sendable {
  let key: WayDirection
  let edge: SurfaceRoadEdge
}

private enum EndpointRole: Sendable {
  case start
  case terminal
}

private struct EndpointMatch: Sendable {
  let edgeIndex: Int
  let score: Double
}

private struct EdgeCoordinateProjection: Sendable {
  let distanceMeters: Double
  let alongEdgeDistanceMeters: Double
  let fractionAlongEdge: Double
  let segmentHeadingDegrees: Double
}

private func osmNodeID(_ value: Int64) -> String {
  "osm.node.\(value)"
}

private func edgeLengthMeters(_ edge: SurfaceRoadEdge) -> Double {
  zip(edge.coordinates, edge.coordinates.dropFirst()).reduce(0) { result, pair in
    result + distanceMeters(from: pair.0, to: pair.1)
  }
}

private func closestProjection(
  of coordinate: SurfaceCoordinate,
  onto edge: SurfaceRoadEdge
) -> EdgeCoordinateProjection? {
  var cumulativeLength = 0.0
  var best: EdgeCoordinateProjection?
  let totalLength = edgeLengthMeters(edge)
  guard totalLength > 0 else { return nil }

  for (start, end) in zip(edge.coordinates, edge.coordinates.dropFirst()) {
    let segmentLength = distanceMeters(from: start, to: end)
    guard segmentLength > 0 else { continue }
    let projection = project(coordinate, ontoSegmentFrom: start, to: end)
    let candidate = EdgeCoordinateProjection(
      distanceMeters: projection.distanceMeters,
      alongEdgeDistanceMeters: cumulativeLength + projection.fraction * segmentLength,
      fractionAlongEdge: (cumulativeLength + projection.fraction * segmentLength) / totalLength,
      segmentHeadingDegrees: bearingDegrees(from: start, to: end)
    )
    if best == nil || candidate.distanceMeters < best!.distanceMeters {
      best = candidate
    }
    cumulativeLength += segmentLength
  }
  return best
}

private func firstHeading(in coordinates: [SurfaceCoordinate]) -> Double? {
  for pair in zip(coordinates, coordinates.dropFirst())
  where distanceMeters(from: pair.0, to: pair.1) > 0 {
    return bearingDegrees(from: pair.0, to: pair.1)
  }
  return nil
}

private func lastHeading(in coordinates: [SurfaceCoordinate]) -> Double? {
  for index in stride(from: coordinates.count - 1, to: 0, by: -1) {
    let start = coordinates[index - 1]
    let end = coordinates[index]
    if distanceMeters(from: start, to: end) > 0 {
      return bearingDegrees(from: start, to: end)
    }
  }
  return nil
}

private func distanceMeters(
  from start: SurfaceCoordinate,
  to end: SurfaceCoordinate
) -> Double {
  let earthRadiusMeters = 6_371_000.0
  let latitude1 = start.latitude * .pi / 180
  let latitude2 = end.latitude * .pi / 180
  let deltaLatitude = (end.latitude - start.latitude) * .pi / 180
  let deltaLongitude = (end.longitude - start.longitude) * .pi / 180
  let a =
    sin(deltaLatitude / 2) * sin(deltaLatitude / 2)
    + cos(latitude1) * cos(latitude2)
    * sin(deltaLongitude / 2) * sin(deltaLongitude / 2)
  return earthRadiusMeters * 2 * atan2(sqrt(a), sqrt(1 - a))
}

private func bearingDegrees(
  from start: SurfaceCoordinate,
  to end: SurfaceCoordinate
) -> Double {
  let latitude1 = start.latitude * .pi / 180
  let latitude2 = end.latitude * .pi / 180
  let deltaLongitude = (end.longitude - start.longitude) * .pi / 180
  let y = sin(deltaLongitude) * cos(latitude2)
  let x =
    cos(latitude1) * sin(latitude2)
    - sin(latitude1) * cos(latitude2) * cos(deltaLongitude)
  return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
}

private func angularDifference(_ lhs: Double, _ rhs: Double) -> Double {
  let difference = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
  return min(difference, 360 - difference)
}

private func project(
  _ point: SurfaceCoordinate,
  ontoSegmentFrom start: SurfaceCoordinate,
  to end: SurfaceCoordinate
) -> (distanceMeters: Double, fraction: Double) {
  let latitudeScale = 111_132.0
  let longitudeScale = 111_320.0 * cos(point.latitude * .pi / 180)
  let startX = (start.longitude - point.longitude) * longitudeScale
  let startY = (start.latitude - point.latitude) * latitudeScale
  let endX = (end.longitude - point.longitude) * longitudeScale
  let endY = (end.latitude - point.latitude) * latitudeScale
  let deltaX = endX - startX
  let deltaY = endY - startY
  let squaredLength = deltaX * deltaX + deltaY * deltaY
  guard squaredLength > 0 else {
    return (hypot(startX, startY), 0)
  }
  let rawFraction = -(startX * deltaX + startY * deltaY) / squaredLength
  let fraction = min(1, max(0, rawFraction))
  return (hypot(startX + fraction * deltaX, startY + fraction * deltaY), fraction)
}
