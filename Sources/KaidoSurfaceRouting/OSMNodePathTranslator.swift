import Foundation

/// Provider-neutral input for translating an ordered OSM node path.
///
/// OSRM can populate this from `annotations=nodes`. The node sequence is path
/// identity only when every consecutive pair resolves to exactly one directed
/// edge in the snapshot-bound Kaido graph.
public struct OSMNodePathTranslationRequest: Codable, Equatable, Sendable {
  public let providerDatasetID: String
  public let routeCoordinates: [SurfaceCoordinate]
  public let orderedOSMNodeIDs: [Int64]

  public init(
    providerDatasetID: String,
    routeCoordinates: [SurfaceCoordinate],
    orderedOSMNodeIDs: [Int64]
  ) {
    self.providerDatasetID = providerDatasetID
    self.routeCoordinates = routeCoordinates
    self.orderedOSMNodeIDs = orderedOSMNodeIDs
  }

  private enum CodingKeys: String, CodingKey {
    case providerDatasetID = "provider_dataset_id"
    case routeCoordinates = "route_coordinates"
    case orderedOSMNodeIDs = "ordered_osm_node_ids"
  }
}

public struct OSMNodePathTranslatorConfiguration: Codable, Equatable, Sendable {
  public let maximumNodeCount: Int

  public init(maximumNodeCount: Int = 50_000) {
    self.maximumNodeCount = maximumNodeCount
  }

  fileprivate var isValid: Bool {
    maximumNodeCount >= 2
  }

  private enum CodingKeys: String, CodingKey {
    case maximumNodeCount = "maximum_node_count"
  }
}

public enum OSMNodePathTranslationError: Error, Equatable, Sendable {
  case invalidGraph
  case invalidConfiguration
  case datasetMismatch(expected: String?, received: String)
  case invalidRouteGeometry
  case invalidNodePath
  case excessiveNodeCount(received: Int, maximum: Int)
  case missingPath(index: Int)
  case ambiguousPath(index: Int)
  case discontinuousPath
  case repeatedDirectedEdge
}

extension OSMNodePathTranslationError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .invalidGraph:
      "the Kaido graph is empty or lacks exact OSM node-pair identity"
    case .invalidConfiguration:
      "the OSM node-path translator configuration is invalid"
    case .datasetMismatch(let expected, let received):
      "provider dataset \(received) does not match graph dataset \(expected ?? "<missing>")"
    case .invalidRouteGeometry:
      "the provider route geometry is invalid"
    case .invalidNodePath:
      "the provider OSM node path is missing or invalid"
    case .excessiveNodeCount(let received, let maximum):
      "provider node path contains \(received) nodes, exceeding maximum \(maximum)"
    case .missingPath(let index):
      "provider node pair \(index) has no exact Kaido directed edge"
    case .ambiguousPath(let index):
      "provider node pair \(index) maps to multiple Kaido directed edges"
    case .discontinuousPath:
      "translated Kaido edges are not directly continuous"
    case .repeatedDirectedEdge:
      "translated Kaido path repeats a directed edge"
    }
  }
}

/// Translates one provider-selected ordered OSM node sequence.
///
/// A node pair is weaker than Valhalla's way-and-direction identity, so this
/// translator never guesses among parallel edges. Missing, ambiguous,
/// discontinuous, repeated, or cross-dataset paths fail closed. The directed
/// graph inspector separately binds the returned route geometry to the exact
/// translated edge sequence.
public struct OSMNodePathTranslator: Sendable {
  public let graph: SurfaceRoadGraphSnapshot
  public let configuration: OSMNodePathTranslatorConfiguration
  private let edgesByNodePair: [OSMNodePair: [SurfaceRoadEdge]]

  public init(
    graph: SurfaceRoadGraphSnapshot,
    configuration: OSMNodePathTranslatorConfiguration = .init()
  ) {
    self.graph = graph
    self.configuration = configuration
    let indexedEdges: [IndexedNodePairEdge] = graph.edges.compactMap { edge in
      guard let fromNodeID = parseOSMNodeID(edge.fromNodeID),
        let toNodeID = parseOSMNodeID(edge.toNodeID)
      else { return nil }
      return IndexedNodePairEdge(
        pair: OSMNodePair(from: fromNodeID, to: toNodeID),
        edge: edge
      )
    }
    self.edgesByNodePair = Dictionary(grouping: indexedEdges, by: \.pair)
      .mapValues { $0.map(\.edge).sorted { $0.id < $1.id } }
  }

  public func translate(
    _ request: OSMNodePathTranslationRequest
  ) throws -> SurfaceSelectedPathEvidence {
    guard !graph.networkSnapshotID.isEmpty, !graph.edges.isEmpty,
      !edgesByNodePair.isEmpty
    else {
      throw OSMNodePathTranslationError.invalidGraph
    }
    guard configuration.isValid else {
      throw OSMNodePathTranslationError.invalidConfiguration
    }
    guard !request.providerDatasetID.isEmpty,
      request.providerDatasetID == graph.provenance?.sourceDatasetID
    else {
      throw OSMNodePathTranslationError.datasetMismatch(
        expected: graph.provenance?.sourceDatasetID,
        received: request.providerDatasetID
      )
    }
    guard request.routeCoordinates.count >= 2,
      request.routeCoordinates.allSatisfy(\.isValid)
    else {
      throw OSMNodePathTranslationError.invalidRouteGeometry
    }
    guard request.orderedOSMNodeIDs.count >= 2,
      request.orderedOSMNodeIDs.allSatisfy({ $0 > 0 }),
      zip(request.orderedOSMNodeIDs, request.orderedOSMNodeIDs.dropFirst())
        .allSatisfy({ $0 != $1 })
    else {
      throw OSMNodePathTranslationError.invalidNodePath
    }
    guard request.orderedOSMNodeIDs.count <= configuration.maximumNodeCount else {
      throw OSMNodePathTranslationError.excessiveNodeCount(
        received: request.orderedOSMNodeIDs.count,
        maximum: configuration.maximumNodeCount
      )
    }

    var selectedEdges: [SurfaceRoadEdge] = []
    for (index, pair) in zip(
      request.orderedOSMNodeIDs,
      request.orderedOSMNodeIDs.dropFirst()
    ).enumerated() {
      let candidates = edgesByNodePair[OSMNodePair(from: pair.0, to: pair.1)] ?? []
      guard !candidates.isEmpty else {
        throw OSMNodePathTranslationError.missingPath(index: index)
      }
      guard candidates.count == 1 else {
        throw OSMNodePathTranslationError.ambiguousPath(index: index)
      }
      selectedEdges.append(candidates[0])
    }

    guard
      zip(selectedEdges, selectedEdges.dropFirst()).allSatisfy({ pair in
        pair.0.toNodeID == pair.1.fromNodeID
      })
    else {
      throw OSMNodePathTranslationError.discontinuousPath
    }
    let selectedEdgeIDs = selectedEdges.map(\.id)
    guard Set(selectedEdgeIDs).count == selectedEdgeIDs.count else {
      throw OSMNodePathTranslationError.repeatedDirectedEdge
    }

    return SurfaceSelectedPathEvidence(
      networkSnapshotID: graph.networkSnapshotID,
      providerDatasetID: request.providerDatasetID,
      directedEdgeIDs: selectedEdgeIDs
    )
  }
}

private struct OSMNodePair: Hashable {
  let from: Int64
  let to: Int64
}

private struct IndexedNodePairEdge {
  let pair: OSMNodePair
  let edge: SurfaceRoadEdge
}

private func parseOSMNodeID(_ value: String) -> Int64? {
  let prefix = "osm.node."
  guard value.hasPrefix(prefix),
    let nodeID = Int64(value.dropFirst(prefix.count)), nodeID > 0
  else { return nil }
  return nodeID
}
