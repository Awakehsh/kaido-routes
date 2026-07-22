import Foundation
import KaidoSurfaceRouting
import Testing

@Test("Valhalla map match translates provider edges and preserves boundary ambiguity")
func valhallaMapMatchNormalizesExactOSMIdentity() throws {
  let normalizer = ValhallaMapMatchNormalizer(
    graph: makeMapMatchGraph(),
    expectedProviderDatasetID: mapMatchDatasetID
  )
  let response = Data(
    """
    {
      "osm_changeset": 2026072101,
      "edges": [
        {
          "id": 9001,
          "way_id": 42,
          "node_id": 1,
          "forward": true,
          "end_node": { "node_id": 3 }
        }
      ],
      "matched_points": [
        { "lat": 35.0, "lon": 139.00025, "type": "matched", "edge_index": 0, "distance_along_edge": 0.25, "distance_from_trace_point": 1.2 },
        { "lat": 35.0, "lon": 139.0005, "type": "interpolated", "edge_index": 0, "distance_along_edge": 0.5, "distance_from_trace_point": 2.0 },
        { "lat": 35.0, "lon": 139.00075, "type": "matched", "edge_index": 0, "distance_along_edge": 0.75, "distance_from_trace_point": 0.8, "end_route_discontinuity": true },
        { "lat": 35.001, "lon": 139.001, "type": "unmatched", "begin_route_discontinuity": true }
      ]
    }
    """.utf8
  )

  let result = try normalizer.normalize(
    responseData: response,
    observationIDs: ["observation.0", "observation.1", "observation.2", "observation.3"]
  )

  #expect(result.providerDatasetID == mapMatchDatasetID)
  #expect(result.points[0].directedEdgeID == "test.edge.1-2")
  #expect(result.points[0].candidateDirectedEdgeIDs == ["test.edge.1-2"])
  #expect(result.points[1].directedEdgeID == nil)
  #expect(
    result.points[1].candidateDirectedEdgeIDs == [
      "test.edge.1-2", "test.edge.2-3",
    ])
  #expect(result.points[1].matchType == .interpolated)
  #expect(result.points[2].directedEdgeID == "test.edge.2-3")
  #expect(result.points[2].endsDiscontinuity)
  #expect(result.points[3].matchType == .unmatched)
  #expect(result.points[3].candidateDirectedEdgeIDs.isEmpty)
  #expect(result.points[3].beginsDiscontinuity)
}

@Test("Provider edge translation preserves repeated traversal")
func providerEdgeTranslationPreservesRepeatedTraversal() throws {
  let identity = OSMProviderEdgeIdentity(
    providerEdgeID: "provider.edge.9001",
    osmWayID: 42,
    beginOSMNodeID: 1,
    endOSMNodeID: 3,
    isForward: true
  )
  let translated = try OSMProviderEdgePathTranslator(graph: makeMapMatchGraph()).translate(
    providerDatasetID: mapMatchDatasetID,
    identities: [identity, identity]
  )

  #expect(translated.count == 2)
  #expect(translated[0].directedEdgeIDs == ["test.edge.1-2", "test.edge.2-3"])
  #expect(translated[1].directedEdgeIDs == translated[0].directedEdgeIDs)
}

@Test("Provider edge translation rejects parallel same-way paths")
func providerEdgeTranslationRejectsAmbiguousPath() {
  var edges = makeMapMatchGraph().edges
  edges.append(
    SurfaceRoadEdge(
      id: "test.edge.1-4",
      fromNodeID: "osm.node.1",
      toNodeID: "osm.node.4",
      kind: .expressway,
      coordinates: [
        SurfaceCoordinate(latitude: 35.0, longitude: 139.0),
        SurfaceCoordinate(latitude: 35.0001, longitude: 139.0005),
      ],
      sourceOSMWayID: 42,
      sourceOSMSegmentIndex: 2,
      sourceOSMDirection: .forward
    ))
  edges.append(
    SurfaceRoadEdge(
      id: "test.edge.4-3",
      fromNodeID: "osm.node.4",
      toNodeID: "osm.node.3",
      kind: .expressway,
      coordinates: [
        SurfaceCoordinate(latitude: 35.0001, longitude: 139.0005),
        SurfaceCoordinate(latitude: 35.0, longitude: 139.001),
      ],
      sourceOSMWayID: 42,
      sourceOSMSegmentIndex: 3,
      sourceOSMDirection: .forward
    ))
  let graph = SurfaceRoadGraphSnapshot(
    networkSnapshotID: mapMatchSnapshotID,
    provenance: makeMapMatchProvenance(),
    edges: edges
  )

  #expect(throws: OSMProviderEdgePathTranslationError.ambiguousPath(index: 0)) {
    try OSMProviderEdgePathTranslator(graph: graph).translate(
      providerDatasetID: mapMatchDatasetID,
      identities: [
        OSMProviderEdgeIdentity(
          providerEdgeID: "provider.edge.9001",
          osmWayID: 42,
          beginOSMNodeID: 1,
          endOSMNodeID: 3,
          isForward: true
        )
      ]
    )
  }
}

@Test("Valhalla map match rejects dataset and observation-count drift")
func valhallaMapMatchRejectsResponseDrift() {
  let normalizer = ValhallaMapMatchNormalizer(
    graph: makeMapMatchGraph(),
    expectedProviderDatasetID: mapMatchDatasetID
  )
  let wrongDataset = Data(
    """
    {"osm_changeset": 7, "edges": [], "matched_points": []}
    """.utf8
  )
  #expect(
    throws: ValhallaMapMatchNormalizationError.providerDatasetMismatch(
      expected: mapMatchDatasetID,
      received: "7"
    )
  ) {
    try normalizer.normalize(responseData: wrongDataset, observationIDs: ["observation.0"])
  }

  let wrongCount = Data(
    """
    {"osm_changeset": 2026072101, "edges": [], "matched_points": []}
    """.utf8
  )
  #expect(
    throws: ValhallaMapMatchNormalizationError.observationCountMismatch(
      expected: 1,
      received: 0
    )
  ) {
    try normalizer.normalize(responseData: wrongCount, observationIDs: ["observation.0"])
  }
}

private let mapMatchDatasetID = "2026072101"
private let mapMatchSnapshotID = "test.snapshot.map-match"

private func makeMapMatchGraph() -> SurfaceRoadGraphSnapshot {
  SurfaceRoadGraphSnapshot(
    networkSnapshotID: mapMatchSnapshotID,
    provenance: makeMapMatchProvenance(),
    edges: [
      SurfaceRoadEdge(
        id: "test.edge.1-2",
        fromNodeID: "osm.node.1",
        toNodeID: "osm.node.2",
        kind: .expressway,
        coordinates: [
          SurfaceCoordinate(latitude: 35.0, longitude: 139.0),
          SurfaceCoordinate(latitude: 35.0, longitude: 139.0005),
        ],
        sourceOSMWayID: 42,
        sourceOSMSegmentIndex: 0,
        sourceOSMDirection: .forward
      ),
      SurfaceRoadEdge(
        id: "test.edge.2-3",
        fromNodeID: "osm.node.2",
        toNodeID: "osm.node.3",
        kind: .expressway,
        coordinates: [
          SurfaceCoordinate(latitude: 35.0, longitude: 139.0005),
          SurfaceCoordinate(latitude: 35.0, longitude: 139.001),
        ],
        sourceOSMWayID: 42,
        sourceOSMSegmentIndex: 1,
        sourceOSMDirection: .forward
      ),
    ]
  )
}

private func makeMapMatchProvenance() -> SurfaceRoadGraphProvenance {
  SurfaceRoadGraphProvenance(
    source: "SYNTHETIC",
    sourceSnapshotAt: "2026-07-23T00:00:00Z",
    sourceDatasetID: mapMatchDatasetID,
    sourceURI: "https://example.invalid/synthetic-map-match",
    licence: "CC0-1.0",
    attribution: "Synthetic test graph"
  )
}
