import KaidoSurfaceRouting
import Testing

@Test("OSM node path translates every unique directed node pair")
func osmNodePathTranslatorMapsUniquePairs() throws {
  let evidence = try OSMNodePathTranslator(graph: makeNodePathGraph()).translate(
    makeNodePathRequest()
  )

  #expect(evidence.networkSnapshotID == nodePathSnapshotID)
  #expect(evidence.providerDatasetID == nodePathDatasetID)
  #expect(evidence.directedEdgeIDs == ["test.edge.1", "test.edge.2"])
}

@Test("OSM node path preserves reverse direction")
func osmNodePathTranslatorPreservesDirection() throws {
  let evidence = try OSMNodePathTranslator(graph: makeNodePathGraph()).translate(
    OSMNodePathTranslationRequest(
      providerDatasetID: nodePathDatasetID,
      routeCoordinates: nodePathCoordinates.reversed(),
      orderedOSMNodeIDs: [3, 2, 1]
    )
  )

  #expect(evidence.directedEdgeIDs == ["test.edge.2.reverse", "test.edge.1.reverse"])
}

@Test("OSM node path rejects dataset drift and missing pairs")
func osmNodePathTranslatorRejectsDriftAndMissingPairs() {
  let translator = OSMNodePathTranslator(graph: makeNodePathGraph())
  #expect(throws: OSMNodePathTranslationError.self) {
    try translator.translate(makeNodePathRequest(datasetID: "test.dataset.other"))
  }
  #expect(throws: OSMNodePathTranslationError.missingPath(index: 1)) {
    try translator.translate(makeNodePathRequest(nodeIDs: [1, 2, 99]))
  }
}

@Test("OSM node path rejects parallel edges instead of guessing a way")
func osmNodePathTranslatorRejectsAmbiguousPairs() {
  var edges = makeNodePathGraph().edges
  edges.append(
    SurfaceRoadEdge(
      id: "test.edge.parallel",
      fromNodeID: "osm.node.1",
      toNodeID: "osm.node.2",
      kind: .ordinaryRoad,
      coordinates: Array(nodePathCoordinates[0...1]),
      sourceOSMWayID: 99,
      sourceOSMSegmentIndex: 0,
      sourceOSMDirection: .forward
    )
  )
  let graph = SurfaceRoadGraphSnapshot(
    networkSnapshotID: nodePathSnapshotID,
    provenance: nodePathProvenance,
    edges: edges
  )

  #expect(throws: OSMNodePathTranslationError.ambiguousPath(index: 0)) {
    try OSMNodePathTranslator(graph: graph).translate(makeNodePathRequest())
  }
}

@Test("OSM node path rejects repeated directed edges and oversized input")
func osmNodePathTranslatorRejectsLoopsAndOversizedInput() {
  let translator = OSMNodePathTranslator(graph: makeNodePathGraph())
  #expect(throws: OSMNodePathTranslationError.repeatedDirectedEdge) {
    try translator.translate(makeNodePathRequest(nodeIDs: [1, 2, 1, 2, 3]))
  }

  let bounded = OSMNodePathTranslator(
    graph: makeNodePathGraph(),
    configuration: OSMNodePathTranslatorConfiguration(maximumNodeCount: 2)
  )
  #expect(
    throws: OSMNodePathTranslationError.excessiveNodeCount(received: 3, maximum: 2)
  ) {
    try bounded.translate(makeNodePathRequest())
  }
}

private let nodePathSnapshotID = "test.snapshot.osm-node-path-v1"
private let nodePathDatasetID = "test.dataset.20260721"
private let nodePathCoordinates = [
  SurfaceCoordinate(latitude: 35, longitude: 139),
  SurfaceCoordinate(latitude: 35, longitude: 139.001),
  SurfaceCoordinate(latitude: 35, longitude: 139.002),
]
private let nodePathProvenance = SurfaceRoadGraphProvenance(
  source: "Synthetic",
  sourceSnapshotAt: "2026-07-21T19:03:43Z",
  sourceDatasetID: nodePathDatasetID,
  sourceURI: "https://example.invalid/osm-node-path",
  licence: "TEST-ONLY",
  attribution: "Synthetic test data"
)

private func makeNodePathRequest(
  datasetID: String = nodePathDatasetID,
  nodeIDs: [Int64] = [1, 2, 3]
) -> OSMNodePathTranslationRequest {
  OSMNodePathTranslationRequest(
    providerDatasetID: datasetID,
    routeCoordinates: nodePathCoordinates,
    orderedOSMNodeIDs: nodeIDs
  )
}

private func makeNodePathGraph() -> SurfaceRoadGraphSnapshot {
  SurfaceRoadGraphSnapshot(
    networkSnapshotID: nodePathSnapshotID,
    provenance: nodePathProvenance,
    edges: [
      makeNodePathEdge(id: "test.edge.1", from: 1, to: 2, coordinateIndex: 0),
      makeNodePathEdge(id: "test.edge.2", from: 2, to: 3, coordinateIndex: 1),
      makeNodePathEdge(
        id: "test.edge.1.reverse",
        from: 2,
        to: 1,
        coordinateIndex: 0,
        reverseCoordinates: true
      ),
      makeNodePathEdge(
        id: "test.edge.2.reverse",
        from: 3,
        to: 2,
        coordinateIndex: 1,
        reverseCoordinates: true
      ),
    ]
  )
}

private func makeNodePathEdge(
  id: String,
  from: Int64,
  to: Int64,
  coordinateIndex: Int,
  reverseCoordinates: Bool = false
) -> SurfaceRoadEdge {
  let coordinates = Array(nodePathCoordinates[coordinateIndex...(coordinateIndex + 1)])
  return SurfaceRoadEdge(
    id: id,
    fromNodeID: "osm.node.\(from)",
    toNodeID: "osm.node.\(to)",
    kind: .ordinaryRoad,
    coordinates: reverseCoordinates ? coordinates.reversed() : coordinates,
    sourceOSMWayID: Int64(coordinateIndex + 42),
    sourceOSMSegmentIndex: 0,
    sourceOSMDirection: reverseCoordinates ? .reverse : .forward
  )
}
