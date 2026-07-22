import Foundation

public enum ValhallaMapMatchType: String, Codable, Sendable {
  case matched
  case interpolated
  case unmatched
}

public struct ValhallaNormalizedMatchedPoint: Equatable, Sendable {
  public let observationID: String
  public let matchType: ValhallaMapMatchType
  public let directedEdgeID: String?
  public let candidateDirectedEdgeIDs: [String]
  public let distanceFromTracePointMeters: Double?
  public let beginsDiscontinuity: Bool
  public let endsDiscontinuity: Bool

  public init(
    observationID: String,
    matchType: ValhallaMapMatchType,
    directedEdgeID: String?,
    candidateDirectedEdgeIDs: [String],
    distanceFromTracePointMeters: Double?,
    beginsDiscontinuity: Bool,
    endsDiscontinuity: Bool
  ) {
    self.observationID = observationID
    self.matchType = matchType
    self.directedEdgeID = directedEdgeID
    self.candidateDirectedEdgeIDs = candidateDirectedEdgeIDs
    self.distanceFromTracePointMeters = distanceFromTracePointMeters
    self.beginsDiscontinuity = beginsDiscontinuity
    self.endsDiscontinuity = endsDiscontinuity
  }
}

public struct ValhallaNormalizedMapMatch: Equatable, Sendable {
  public let providerDatasetID: String
  public let points: [ValhallaNormalizedMatchedPoint]

  public init(providerDatasetID: String, points: [ValhallaNormalizedMatchedPoint]) {
    self.providerDatasetID = providerDatasetID
    self.points = points
  }
}

public enum ValhallaMapMatchNormalizationError: Error, Equatable, Sendable {
  case invalidGraph
  case invalidIdentity
  case invalidResponse
  case providerDatasetMismatch(expected: String, received: String)
  case observationCountMismatch(expected: Int, received: Int)
  case invalidProviderEdge(index: Int)
  case invalidMatchedPoint(index: Int)
  case translatedEdgeMissing(String)
}

/// Normalizes `trace_attributes` with `shape_match=map_snap`.
///
/// Valhalla match types do not contain calibrated confidence and provider edge
/// IDs are not Kaido IDs. This boundary translates exact OSM identity first and
/// leaves confidence and occurrence inference to the caller.
public struct ValhallaMapMatchNormalizer: Sendable {
  public let graph: SurfaceRoadGraphSnapshot
  public let expectedProviderDatasetID: String
  public let boundaryToleranceMeters: Double

  public init(
    graph: SurfaceRoadGraphSnapshot,
    expectedProviderDatasetID: String,
    boundaryToleranceMeters: Double = 0.5
  ) {
    self.graph = graph
    self.expectedProviderDatasetID = expectedProviderDatasetID
    self.boundaryToleranceMeters = boundaryToleranceMeters
  }

  public func normalize(
    responseData: Data,
    observationIDs: [String]
  ) throws -> ValhallaNormalizedMapMatch {
    guard !expectedProviderDatasetID.isEmpty, boundaryToleranceMeters >= 0,
      !observationIDs.isEmpty, Set(observationIDs).count == observationIDs.count
    else {
      throw ValhallaMapMatchNormalizationError.invalidIdentity
    }
    let response: Response
    do {
      response = try JSONDecoder().decode(Response.self, from: responseData)
    } catch {
      throw ValhallaMapMatchNormalizationError.invalidResponse
    }
    let receivedDatasetID = String(response.osmChangeset)
    guard receivedDatasetID == expectedProviderDatasetID else {
      throw ValhallaMapMatchNormalizationError.providerDatasetMismatch(
        expected: expectedProviderDatasetID,
        received: receivedDatasetID
      )
    }
    guard response.matchedPoints.count == observationIDs.count else {
      throw ValhallaMapMatchNormalizationError.observationCountMismatch(
        expected: observationIDs.count,
        received: response.matchedPoints.count
      )
    }

    let identities = try response.edges.enumerated().map { index, edge in
      guard let wayID = Int64(exactly: edge.wayID),
        let beginNodeID = Int64(exactly: edge.beginOSMNodeID),
        let endNodeID = Int64(exactly: edge.endNode.nodeID),
        wayID > 0, beginNodeID > 0, endNodeID > 0
      else {
        throw ValhallaMapMatchNormalizationError.invalidProviderEdge(index: index)
      }
      return OSMProviderEdgeIdentity(
        providerEdgeID: String(edge.id),
        osmWayID: wayID,
        beginOSMNodeID: beginNodeID,
        endOSMNodeID: endNodeID,
        isForward: edge.forward
      )
    }
    let translated = try OSMProviderEdgePathTranslator(graph: graph).translate(
      providerDatasetID: receivedDatasetID,
      identities: identities
    )
    let graphEdgeIDs = graph.edges.map(\.id)
    guard Set(graphEdgeIDs).count == graphEdgeIDs.count else {
      throw ValhallaMapMatchNormalizationError.invalidGraph
    }
    let graphEdgesByID = Dictionary(uniqueKeysWithValues: graph.edges.map { ($0.id, $0) })

    let points = try response.matchedPoints.enumerated().map { index, point in
      guard point.coordinate.isValid else {
        throw ValhallaMapMatchNormalizationError.invalidMatchedPoint(index: index)
      }
      if point.type == .unmatched {
        guard point.edgeIndex == nil, point.distanceAlongEdge == nil,
          point.distanceFromTracePoint == nil
        else {
          throw ValhallaMapMatchNormalizationError.invalidMatchedPoint(index: index)
        }
        return ValhallaNormalizedMatchedPoint(
          observationID: observationIDs[index],
          matchType: point.type,
          directedEdgeID: nil,
          candidateDirectedEdgeIDs: [],
          distanceFromTracePointMeters: nil,
          beginsDiscontinuity: point.beginsDiscontinuity ?? false,
          endsDiscontinuity: point.endsDiscontinuity ?? false
        )
      }
      guard let edgeIndex = point.edgeIndex,
        translated.indices.contains(edgeIndex),
        let distanceAlongEdge = point.distanceAlongEdge,
        (0...1).contains(distanceAlongEdge),
        let distanceFromTracePoint = point.distanceFromTracePoint,
        distanceFromTracePoint.isFinite, distanceFromTracePoint >= 0
      else {
        throw ValhallaMapMatchNormalizationError.invalidMatchedPoint(index: index)
      }
      let candidateIDs = try candidates(
        translatedEdgeIDs: translated[edgeIndex].directedEdgeIDs,
        distanceAlongEdge: distanceAlongEdge,
        graphEdgesByID: graphEdgesByID
      )
      return ValhallaNormalizedMatchedPoint(
        observationID: observationIDs[index],
        matchType: point.type,
        directedEdgeID: candidateIDs.count == 1 ? candidateIDs[0] : nil,
        candidateDirectedEdgeIDs: candidateIDs,
        distanceFromTracePointMeters: distanceFromTracePoint,
        beginsDiscontinuity: point.beginsDiscontinuity ?? false,
        endsDiscontinuity: point.endsDiscontinuity ?? false
      )
    }
    return ValhallaNormalizedMapMatch(
      providerDatasetID: receivedDatasetID,
      points: points
    )
  }

  private func candidates(
    translatedEdgeIDs: [String],
    distanceAlongEdge: Double,
    graphEdgesByID: [String: SurfaceRoadEdge]
  ) throws -> [String] {
    let edges = try translatedEdgeIDs.map { edgeID in
      guard let edge = graphEdgesByID[edgeID] else {
        throw ValhallaMapMatchNormalizationError.translatedEdgeMissing(edgeID)
      }
      return edge
    }
    let lengths = edges.map(edgeLengthMeters)
    let totalLength = lengths.reduce(0, +)
    guard totalLength.isFinite, totalLength > 0 else {
      throw ValhallaMapMatchNormalizationError.invalidResponse
    }
    let target = distanceAlongEdge * totalLength
    var start = 0.0
    var candidates: [String] = []
    for (edge, length) in zip(edges, lengths) {
      let end = start + length
      if target >= start - boundaryToleranceMeters
        && target <= end + boundaryToleranceMeters
      {
        candidates.append(edge.id)
      }
      start = end
    }
    guard !candidates.isEmpty else {
      throw ValhallaMapMatchNormalizationError.invalidResponse
    }
    return candidates
  }
}

private struct Response: Decodable {
  let osmChangeset: UInt64
  let edges: [ResponseEdge]
  let matchedPoints: [ResponseMatchedPoint]

  private enum CodingKeys: String, CodingKey {
    case osmChangeset = "osm_changeset"
    case edges
    case matchedPoints = "matched_points"
  }
}

private struct ResponseEdge: Decodable {
  let id: UInt64
  let wayID: UInt64
  let beginOSMNodeID: UInt64
  let forward: Bool
  let endNode: ResponseEndNode

  private enum CodingKeys: String, CodingKey {
    case id
    case wayID = "way_id"
    case beginOSMNodeID = "node_id"
    case forward
    case endNode = "end_node"
  }
}

private struct ResponseEndNode: Decodable {
  let nodeID: UInt64

  private enum CodingKeys: String, CodingKey {
    case nodeID = "node_id"
  }
}

private struct ResponseMatchedPoint: Decodable {
  let coordinate: SurfaceCoordinate
  let type: ValhallaMapMatchType
  let edgeIndex: Int?
  let beginsDiscontinuity: Bool?
  let endsDiscontinuity: Bool?
  let distanceAlongEdge: Double?
  let distanceFromTracePoint: Double?

  private enum CodingKeys: String, CodingKey {
    case latitude = "lat"
    case longitude = "lon"
    case type
    case edgeIndex = "edge_index"
    case beginsDiscontinuity = "begin_route_discontinuity"
    case endsDiscontinuity = "end_route_discontinuity"
    case distanceAlongEdge = "distance_along_edge"
    case distanceFromTracePoint = "distance_from_trace_point"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    coordinate = SurfaceCoordinate(
      latitude: try container.decode(Double.self, forKey: .latitude),
      longitude: try container.decode(Double.self, forKey: .longitude)
    )
    type = try container.decode(ValhallaMapMatchType.self, forKey: .type)
    edgeIndex = try container.decodeIfPresent(Int.self, forKey: .edgeIndex)
    beginsDiscontinuity = try container.decodeIfPresent(Bool.self, forKey: .beginsDiscontinuity)
    endsDiscontinuity = try container.decodeIfPresent(Bool.self, forKey: .endsDiscontinuity)
    distanceAlongEdge = try container.decodeIfPresent(Double.self, forKey: .distanceAlongEdge)
    distanceFromTracePoint = try container.decodeIfPresent(
      Double.self,
      forKey: .distanceFromTracePoint
    )
  }
}

private let mapMatchEarthRadiusMeters = 6_371_000.0

private func edgeLengthMeters(_ edge: SurfaceRoadEdge) -> Double {
  zip(edge.coordinates, edge.coordinates.dropFirst()).reduce(0) { partial, pair in
    partial + coordinateDistanceMeters(pair.0, pair.1)
  }
}

private func coordinateDistanceMeters(
  _ lhs: SurfaceCoordinate,
  _ rhs: SurfaceCoordinate
) -> Double {
  let latitude1 = lhs.latitude * .pi / 180
  let latitude2 = rhs.latitude * .pi / 180
  let deltaLatitude = latitude2 - latitude1
  let deltaLongitude = (rhs.longitude - lhs.longitude) * .pi / 180
  let value =
    sin(deltaLatitude / 2) * sin(deltaLatitude / 2)
    + cos(latitude1) * cos(latitude2)
    * sin(deltaLongitude / 2) * sin(deltaLongitude / 2)
  return 2 * mapMatchEarthRadiusMeters * atan2(sqrt(value), sqrt(max(0, 1 - value)))
}
