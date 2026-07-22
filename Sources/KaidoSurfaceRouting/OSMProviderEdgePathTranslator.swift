import Foundation

public struct OSMProviderEdgeIdentity: Codable, Equatable, Sendable {
  public let providerEdgeID: String
  public let osmWayID: Int64
  public let beginOSMNodeID: Int64
  public let endOSMNodeID: Int64
  public let isForward: Bool

  public init(
    providerEdgeID: String,
    osmWayID: Int64,
    beginOSMNodeID: Int64,
    endOSMNodeID: Int64,
    isForward: Bool
  ) {
    self.providerEdgeID = providerEdgeID
    self.osmWayID = osmWayID
    self.beginOSMNodeID = beginOSMNodeID
    self.endOSMNodeID = endOSMNodeID
    self.isForward = isForward
  }
}

public struct OSMTranslatedProviderEdge: Equatable, Sendable {
  public let providerEdgeID: String
  public let directedEdgeIDs: [String]

  public init(providerEdgeID: String, directedEdgeIDs: [String]) {
    self.providerEdgeID = providerEdgeID
    self.directedEdgeIDs = directedEdgeIDs
  }
}

public enum OSMProviderEdgePathTranslationError: Error, Equatable, Sendable {
  case invalidGraph
  case datasetMismatch(expected: String?, received: String)
  case invalidIdentity(index: Int)
  case missingPath(index: Int)
  case ambiguousPath(index: Int)
}

/// Expands provider graph-edge identity onto exact Kaido directed edges.
///
/// Unlike a selected route translation, a map-matching trace may revisit the
/// same provider and Kaido edges. This translator preserves those repetitions;
/// callers bind individual observations to the translated provider-edge path.
public struct OSMProviderEdgePathTranslator: Sendable {
  public let graph: SurfaceRoadGraphSnapshot
  private let edgesByWayAndDirection: [WayDirection: [SurfaceRoadEdge]]

  public init(graph: SurfaceRoadGraphSnapshot) {
    self.graph = graph
    self.edgesByWayAndDirection = Dictionary(
      grouping: graph.edges.compactMap { edge in
        guard let wayID = edge.sourceOSMWayID,
          let direction = edge.sourceOSMDirection,
          edge.sourceOSMSegmentIndex != nil
        else { return nil }
        return IndexedEdge(
          key: WayDirection(wayID: wayID, direction: direction),
          edge: edge
        )
      },
      by: \IndexedEdge.key
    )
    .mapValues { $0.map(\.edge) }
  }

  public func translate(
    providerDatasetID: String,
    identities: [OSMProviderEdgeIdentity]
  ) throws -> [OSMTranslatedProviderEdge] {
    guard !graph.networkSnapshotID.isEmpty, !graph.edges.isEmpty,
      !edgesByWayAndDirection.isEmpty
    else {
      throw OSMProviderEdgePathTranslationError.invalidGraph
    }
    guard !providerDatasetID.isEmpty,
      providerDatasetID == graph.provenance?.sourceDatasetID
    else {
      throw OSMProviderEdgePathTranslationError.datasetMismatch(
        expected: graph.provenance?.sourceDatasetID,
        received: providerDatasetID
      )
    }
    return try identities.enumerated().map { index, identity in
      guard !identity.providerEdgeID.isEmpty, identity.osmWayID > 0,
        identity.beginOSMNodeID > 0, identity.endOSMNodeID > 0,
        identity.beginOSMNodeID != identity.endOSMNodeID
      else {
        throw OSMProviderEdgePathTranslationError.invalidIdentity(index: index)
      }
      let paths = exactPaths(for: identity)
      guard !paths.isEmpty else {
        throw OSMProviderEdgePathTranslationError.missingPath(index: index)
      }
      guard paths.count == 1 else {
        throw OSMProviderEdgePathTranslationError.ambiguousPath(index: index)
      }
      return OSMTranslatedProviderEdge(
        providerEdgeID: identity.providerEdgeID,
        directedEdgeIDs: paths[0].map(\.id)
      )
    }
  }

  private func exactPaths(for identity: OSMProviderEdgeIdentity) -> [[SurfaceRoadEdge]] {
    let direction: OSMWayDirection = identity.isForward ? .forward : .reverse
    guard
      let candidateEdges = edgesByWayAndDirection[
        WayDirection(wayID: identity.osmWayID, direction: direction)
      ]
    else { return [] }
    let outgoing = Dictionary(grouping: candidateEdges, by: \SurfaceRoadEdge.fromNodeID)
      .mapValues { edges in
        edges.sorted {
          ($0.sourceOSMSegmentIndex ?? -1, $0.id)
            < ($1.sourceOSMSegmentIndex ?? -1, $1.id)
        }
      }
    let startNodeID = "osm.node.\(identity.beginOSMNodeID)"
    let endNodeID = "osm.node.\(identity.endOSMNodeID)"
    var results: [[SurfaceRoadEdge]] = []

    func walk(nodeID: String, path: [SurfaceRoadEdge], visitedEdgeIDs: Set<String>) {
      guard results.count < 2 else { return }
      if nodeID == endNodeID {
        if !path.isEmpty { results.append(path) }
        return
      }
      for edge in outgoing[nodeID] ?? [] where !visitedEdgeIDs.contains(edge.id) {
        var visited = visitedEdgeIDs
        visited.insert(edge.id)
        walk(nodeID: edge.toNodeID, path: path + [edge], visitedEdgeIDs: visited)
      }
    }

    walk(nodeID: startNodeID, path: [], visitedEdgeIDs: [])
    return results
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
