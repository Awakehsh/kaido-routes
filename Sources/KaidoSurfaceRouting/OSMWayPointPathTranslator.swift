import Foundation

/// One provider route-point interval with directional provider identity and
/// source OSM way identity.
///
/// GraphHopper can populate this from aligned `edge_key` and `osm_way_id` path
/// details when both import-time and response-time geometry simplification are
/// disabled. The provider edge key is intentionally not treated as an OSM ID.
public struct OSMWayPointPathSegmentIdentity: Codable, Equatable, Sendable {
  public let providerDirectedEdgeKey: Int64
  public let osmWayID: Int64

  public init(providerDirectedEdgeKey: Int64, osmWayID: Int64) {
    self.providerDirectedEdgeKey = providerDirectedEdgeKey
    self.osmWayID = osmWayID
  }

  private enum CodingKeys: String, CodingKey {
    case providerDirectedEdgeKey = "provider_directed_edge_key"
    case osmWayID = "osm_way_id"
  }
}

/// Provider-neutral input for translating fully annotated route point pairs.
public struct OSMWayPointPathTranslationRequest: Codable, Equatable, Sendable {
  public let providerDatasetID: String
  public let routeCoordinates: [SurfaceCoordinate]
  public let segmentIdentities: [OSMWayPointPathSegmentIdentity]

  public init(
    providerDatasetID: String,
    routeCoordinates: [SurfaceCoordinate],
    segmentIdentities: [OSMWayPointPathSegmentIdentity]
  ) {
    self.providerDatasetID = providerDatasetID
    self.routeCoordinates = routeCoordinates
    self.segmentIdentities = segmentIdentities
  }

  private enum CodingKeys: String, CodingKey {
    case providerDatasetID = "provider_dataset_id"
    case routeCoordinates = "route_coordinates"
    case segmentIdentities = "segment_identities"
  }
}

public struct OSMWayPointPathTranslatorConfiguration: Codable, Equatable, Sendable {
  public let maximumProjectionDistanceMeters: Double
  public let maximumHeadingDifferenceDegrees: Double
  public let minimumProgressMeters: Double
  public let maximumSegmentCount: Int

  public init(
    maximumProjectionDistanceMeters: Double = 2.5,
    maximumHeadingDifferenceDegrees: Double = 45,
    minimumProgressMeters: Double = 0.01,
    maximumSegmentCount: Int = 50_000
  ) {
    self.maximumProjectionDistanceMeters = maximumProjectionDistanceMeters
    self.maximumHeadingDifferenceDegrees = maximumHeadingDifferenceDegrees
    self.minimumProgressMeters = minimumProgressMeters
    self.maximumSegmentCount = maximumSegmentCount
  }

  fileprivate var isValid: Bool {
    maximumProjectionDistanceMeters.isFinite && maximumProjectionDistanceMeters > 0
      && maximumHeadingDifferenceDegrees.isFinite
      && (0...180).contains(maximumHeadingDifferenceDegrees)
      && minimumProgressMeters.isFinite && minimumProgressMeters > 0
      && maximumSegmentCount > 0
  }

  private enum CodingKeys: String, CodingKey {
    case maximumProjectionDistanceMeters = "maximum_projection_distance_meters"
    case maximumHeadingDifferenceDegrees = "maximum_heading_difference_degrees"
    case minimumProgressMeters = "minimum_progress_meters"
    case maximumSegmentCount = "maximum_segment_count"
  }
}

public enum OSMWayPointPathTranslationError: Error, Equatable, Sendable {
  case invalidGraph
  case invalidConfiguration
  case datasetMismatch(expected: String?, received: String)
  case invalidRouteGeometry
  case invalidSegmentCount(received: Int, expected: Int)
  case excessiveSegmentCount(received: Int, maximum: Int)
  case invalidSegmentIdentity(index: Int)
  case inconsistentProviderEdgeKey(Int64)
  case repeatedProviderEdgeKey(Int64)
  case missingPath(index: Int)
  case ambiguousPath(index: Int)
  case discontinuousPath
  case repeatedDirectedEdge
}

extension OSMWayPointPathTranslationError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .invalidGraph:
      "the Kaido graph is empty or lacks directional OSM way identity"
    case .invalidConfiguration:
      "the OSM way-point path translator configuration is invalid"
    case .datasetMismatch(let expected, let received):
      "provider dataset \(received) does not match graph dataset \(expected ?? "<missing>")"
    case .invalidRouteGeometry:
      "the provider route geometry is invalid"
    case .invalidSegmentCount(let received, let expected):
      "provider supplied \(received) segment identities for \(expected) route point pairs"
    case .excessiveSegmentCount(let received, let maximum):
      "provider route contains \(received) segments, exceeding maximum \(maximum)"
    case .invalidSegmentIdentity(let index):
      "provider segment identity \(index) is invalid"
    case .inconsistentProviderEdgeKey(let edgeKey):
      "provider edge key \(edgeKey) changes OSM way identity"
    case .repeatedProviderEdgeKey(let edgeKey):
      "provider edge key \(edgeKey) reappears after another edge"
    case .missingPath(let index):
      "provider point pair \(index) has no exact Kaido directed edge"
    case .ambiguousPath(let index):
      "provider point pair \(index) maps to multiple Kaido directed edges"
    case .discontinuousPath:
      "translated Kaido edges are not directly continuous"
    case .repeatedDirectedEdge:
      "translated Kaido path repeats a directed edge"
    }
  }
}

/// Translates a provider's complete OSM-way-annotated point path.
///
/// This is stricter than matching an opaque polyline. Every consecutive route
/// point pair must carry one directional provider edge key and one OSM way ID,
/// then bind to exactly one directed edge in the snapshot-bound Kaido graph.
/// Missing import geometry, simplified responses, parallel ambiguity, and
/// cross-dataset paths fail closed.
public struct OSMWayPointPathTranslator: Sendable {
  public let graph: SurfaceRoadGraphSnapshot
  public let configuration: OSMWayPointPathTranslatorConfiguration
  private let edgesByWayID: [Int64: [SurfaceRoadEdge]]

  public init(
    graph: SurfaceRoadGraphSnapshot,
    configuration: OSMWayPointPathTranslatorConfiguration = .init()
  ) {
    self.graph = graph
    self.configuration = configuration
    self.edgesByWayID = Dictionary(
      grouping: graph.edges.compactMap { edge in
        guard let wayID = edge.sourceOSMWayID,
          edge.sourceOSMSegmentIndex != nil,
          edge.sourceOSMDirection != nil
        else { return nil }
        return IndexedWayPointEdge(wayID: wayID, edge: edge)
      },
      by: \IndexedWayPointEdge.wayID
    )
    .mapValues { indexedEdges in
      indexedEdges.map(\.edge).sorted { $0.id < $1.id }
    }
  }

  public func translate(
    _ request: OSMWayPointPathTranslationRequest
  ) throws -> SurfaceSelectedPathEvidence {
    guard !graph.networkSnapshotID.isEmpty, !graph.edges.isEmpty,
      !edgesByWayID.isEmpty
    else {
      throw OSMWayPointPathTranslationError.invalidGraph
    }
    guard configuration.isValid else {
      throw OSMWayPointPathTranslationError.invalidConfiguration
    }
    guard !request.providerDatasetID.isEmpty,
      request.providerDatasetID == graph.provenance?.sourceDatasetID
    else {
      throw OSMWayPointPathTranslationError.datasetMismatch(
        expected: graph.provenance?.sourceDatasetID,
        received: request.providerDatasetID
      )
    }
    guard request.routeCoordinates.count >= 2,
      request.routeCoordinates.allSatisfy(\.isValid)
    else {
      throw OSMWayPointPathTranslationError.invalidRouteGeometry
    }
    let expectedSegmentCount = request.routeCoordinates.count - 1
    guard request.segmentIdentities.count == expectedSegmentCount else {
      throw OSMWayPointPathTranslationError.invalidSegmentCount(
        received: request.segmentIdentities.count,
        expected: expectedSegmentCount
      )
    }
    guard expectedSegmentCount <= configuration.maximumSegmentCount else {
      throw OSMWayPointPathTranslationError.excessiveSegmentCount(
        received: expectedSegmentCount,
        maximum: configuration.maximumSegmentCount
      )
    }

    var wayIDByProviderEdgeKey: [Int64: Int64] = [:]
    var closedProviderEdgeKeys: Set<Int64> = []
    var previousProviderEdgeKey: Int64?
    var selectedEdges: [SurfaceRoadEdge] = []

    for index in 0..<expectedSegmentCount {
      let identity = request.segmentIdentities[index]
      guard identity.providerDirectedEdgeKey >= 0, identity.osmWayID > 0 else {
        throw OSMWayPointPathTranslationError.invalidSegmentIdentity(index: index)
      }
      if let boundWayID = wayIDByProviderEdgeKey[identity.providerDirectedEdgeKey],
        boundWayID != identity.osmWayID
      {
        throw OSMWayPointPathTranslationError.inconsistentProviderEdgeKey(
          identity.providerDirectedEdgeKey
        )
      }
      wayIDByProviderEdgeKey[identity.providerDirectedEdgeKey] = identity.osmWayID
      if previousProviderEdgeKey != identity.providerDirectedEdgeKey {
        if closedProviderEdgeKeys.contains(identity.providerDirectedEdgeKey) {
          throw OSMWayPointPathTranslationError.repeatedProviderEdgeKey(
            identity.providerDirectedEdgeKey
          )
        }
        if let previousProviderEdgeKey {
          closedProviderEdgeKeys.insert(previousProviderEdgeKey)
        }
        previousProviderEdgeKey = identity.providerDirectedEdgeKey
      }

      let start = request.routeCoordinates[index]
      let end = request.routeCoordinates[index + 1]
      guard wayPointDistanceMeters(from: start, to: end) > configuration.minimumProgressMeters
      else {
        throw OSMWayPointPathTranslationError.invalidRouteGeometry
      }
      let candidates = (edgesByWayID[identity.osmWayID] ?? []).filter { edge in
        segment(from: start, to: end, bindsTo: edge)
      }
      guard !candidates.isEmpty else {
        throw OSMWayPointPathTranslationError.missingPath(index: index)
      }
      guard candidates.count == 1 else {
        throw OSMWayPointPathTranslationError.ambiguousPath(index: index)
      }
      if selectedEdges.last?.id != candidates[0].id {
        selectedEdges.append(candidates[0])
      }
    }

    guard !selectedEdges.isEmpty,
      zip(selectedEdges, selectedEdges.dropFirst()).allSatisfy({ pair in
        pair.0.toNodeID == pair.1.fromNodeID
      })
    else {
      throw OSMWayPointPathTranslationError.discontinuousPath
    }
    let selectedEdgeIDs = selectedEdges.map(\.id)
    guard Set(selectedEdgeIDs).count == selectedEdgeIDs.count else {
      throw OSMWayPointPathTranslationError.repeatedDirectedEdge
    }

    return SurfaceSelectedPathEvidence(
      networkSnapshotID: graph.networkSnapshotID,
      providerDatasetID: request.providerDatasetID,
      directedEdgeIDs: selectedEdgeIDs
    )
  }

  private func segment(
    from start: SurfaceCoordinate,
    to end: SurfaceCoordinate,
    bindsTo edge: SurfaceRoadEdge
  ) -> Bool {
    guard let startProjection = wayPointProjection(of: start, onto: edge),
      let endProjection = wayPointProjection(of: end, onto: edge),
      startProjection.distanceMeters <= configuration.maximumProjectionDistanceMeters,
      endProjection.distanceMeters <= configuration.maximumProjectionDistanceMeters,
      endProjection.alongEdgeDistanceMeters - startProjection.alongEdgeDistanceMeters
        > configuration.minimumProgressMeters
    else { return false }

    let routeHeading = wayPointBearingDegrees(from: start, to: end)
    return wayPointAngularDifference(
      routeHeading,
      startProjection.segmentHeadingDegrees
    ) <= configuration.maximumHeadingDifferenceDegrees
      && wayPointAngularDifference(
        routeHeading,
        endProjection.segmentHeadingDegrees
      ) <= configuration.maximumHeadingDifferenceDegrees
  }
}

private struct IndexedWayPointEdge: Sendable {
  let wayID: Int64
  let edge: SurfaceRoadEdge
}

private struct WayPointProjection: Sendable {
  let distanceMeters: Double
  let alongEdgeDistanceMeters: Double
  let segmentHeadingDegrees: Double
}

private func wayPointProjection(
  of coordinate: SurfaceCoordinate,
  onto edge: SurfaceRoadEdge
) -> WayPointProjection? {
  guard edge.coordinates.count >= 2 else { return nil }
  var cumulativeDistance = 0.0
  var best: WayPointProjection?

  for (start, end) in zip(edge.coordinates, edge.coordinates.dropFirst()) {
    let segmentLength = wayPointDistanceMeters(from: start, to: end)
    defer { cumulativeDistance += segmentLength }
    guard segmentLength > 0 else { continue }
    let projection = wayPointProject(coordinate, ontoSegmentFrom: start, to: end)
    let candidate = WayPointProjection(
      distanceMeters: projection.distanceMeters,
      alongEdgeDistanceMeters: cumulativeDistance + projection.fraction * segmentLength,
      segmentHeadingDegrees: wayPointBearingDegrees(from: start, to: end)
    )
    if best == nil || candidate.distanceMeters < best!.distanceMeters {
      best = candidate
    }
  }
  return best
}

private func wayPointProject(
  _ point: SurfaceCoordinate,
  ontoSegmentFrom start: SurfaceCoordinate,
  to end: SurfaceCoordinate
) -> (distanceMeters: Double, fraction: Double) {
  let referenceLatitude = wayPointRadians((point.latitude + start.latitude + end.latitude) / 3)
  let startX =
    wayPointRadians(start.longitude - point.longitude) * cos(referenceLatitude)
    * wayPointEarthRadiusMeters
  let startY = wayPointRadians(start.latitude - point.latitude) * wayPointEarthRadiusMeters
  let endX =
    wayPointRadians(end.longitude - point.longitude) * cos(referenceLatitude)
    * wayPointEarthRadiusMeters
  let endY = wayPointRadians(end.latitude - point.latitude) * wayPointEarthRadiusMeters
  let deltaX = endX - startX
  let deltaY = endY - startY
  let lengthSquared = deltaX * deltaX + deltaY * deltaY
  let fraction =
    lengthSquared == 0
    ? 0 : min(1, max(0, -(startX * deltaX + startY * deltaY) / lengthSquared))
  return (
    hypot(startX + deltaX * fraction, startY + deltaY * fraction),
    fraction
  )
}

private func wayPointDistanceMeters(
  from first: SurfaceCoordinate,
  to second: SurfaceCoordinate
) -> Double {
  let latitudeDelta = wayPointRadians(second.latitude - first.latitude)
  let longitudeDelta = wayPointRadians(second.longitude - first.longitude)
  let firstLatitude = wayPointRadians(first.latitude)
  let secondLatitude = wayPointRadians(second.latitude)
  let value =
    sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
    + cos(firstLatitude) * cos(secondLatitude)
    * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
  return wayPointEarthRadiusMeters * 2
    * atan2(sqrt(value), sqrt(max(0, 1 - value)))
}

private func wayPointBearingDegrees(
  from first: SurfaceCoordinate,
  to second: SurfaceCoordinate
) -> Double {
  let firstLatitude = wayPointRadians(first.latitude)
  let secondLatitude = wayPointRadians(second.latitude)
  let longitudeDelta = wayPointRadians(second.longitude - first.longitude)
  let y = sin(longitudeDelta) * cos(secondLatitude)
  let x =
    cos(firstLatitude) * sin(secondLatitude)
    - sin(firstLatitude) * cos(secondLatitude) * cos(longitudeDelta)
  return wayPointNormalizedDegrees(atan2(y, x) * 180 / .pi)
}

private func wayPointAngularDifference(_ first: Double, _ second: Double) -> Double {
  let difference = abs(wayPointNormalizedDegrees(first) - wayPointNormalizedDegrees(second))
  return min(difference, 360 - difference)
}

private func wayPointRadians(_ degrees: Double) -> Double {
  degrees * .pi / 180
}

private func wayPointNormalizedDegrees(_ degrees: Double) -> Double {
  let value = degrees.truncatingRemainder(dividingBy: 360)
  return value >= 0 ? value : value + 360
}

private let wayPointEarthRadiusMeters = 6_371_000.0
