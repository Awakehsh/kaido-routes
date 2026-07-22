import KaidoSurfaceRouting
import Testing

@Test("OSM way-point path translates every fully annotated route segment")
func osmWayPointPathTranslatesExactSegments() throws {
  let evidence = try OSMWayPointPathTranslator(graph: makeWayPointGraph()).translate(
    makeWayPointRequest()
  )

  #expect(evidence.networkSnapshotID == wayPointSnapshotID)
  #expect(evidence.providerDatasetID == wayPointDatasetID)
  #expect(evidence.directedEdgeIDs == ["test.edge.1", "test.edge.2"])
}

@Test("OSM way-point path resolves a partial first provider segment")
func osmWayPointPathResolvesPartialStart() throws {
  let partialCoordinates = [
    SurfaceCoordinate(latitude: 35, longitude: 139.0005),
    wayPointCoordinates[1],
    wayPointCoordinates[2],
  ]
  let evidence = try OSMWayPointPathTranslator(graph: makeWayPointGraph()).translate(
    OSMWayPointPathTranslationRequest(
      providerDatasetID: wayPointDatasetID,
      routeCoordinates: partialCoordinates,
      segmentIdentities: makeWayPointIdentities()
    )
  )

  #expect(evidence.directedEdgeIDs == ["test.edge.1", "test.edge.2"])
}

@Test("OSM way-point path rejects import or response simplification")
func osmWayPointPathRejectsMissingIntermediateNode() {
  let simplified = OSMWayPointPathTranslationRequest(
    providerDatasetID: wayPointDatasetID,
    routeCoordinates: [wayPointCoordinates[0], wayPointCoordinates[2]],
    segmentIdentities: [
      OSMWayPointPathSegmentIdentity(providerDirectedEdgeKey: 20, osmWayID: 42)
    ]
  )

  #expect(throws: OSMWayPointPathTranslationError.missingPath(index: 0)) {
    try OSMWayPointPathTranslator(graph: makeWayPointGraph()).translate(simplified)
  }
}

@Test("OSM way-point path rejects parallel same-way ambiguity")
func osmWayPointPathRejectsParallelWayEdge() {
  let base = makeWayPointGraph()
  let duplicate = makeWayPointEdge(
    id: "test.edge.1.parallel",
    from: 1,
    to: 2,
    coordinateIndex: 0,
    segmentIndex: 0
  )
  let graph = SurfaceRoadGraphSnapshot(
    networkSnapshotID: base.networkSnapshotID,
    provenance: base.provenance,
    edges: base.edges + [duplicate]
  )

  #expect(throws: OSMWayPointPathTranslationError.ambiguousPath(index: 0)) {
    try OSMWayPointPathTranslator(graph: graph).translate(makeWayPointRequest())
  }
}

@Test("OSM way-point path rejects identity drift and noncontiguous provider keys")
func osmWayPointPathRejectsIdentityDrift() {
  #expect(
    throws: OSMWayPointPathTranslationError.datasetMismatch(
      expected: wayPointDatasetID,
      received: "drifting-dataset"
    )
  ) {
    try OSMWayPointPathTranslator(graph: makeWayPointGraph()).translate(
      makeWayPointRequest(datasetID: "drifting-dataset")
    )
  }

  let coordinates =
    wayPointCoordinates + [
      SurfaceCoordinate(latitude: 35, longitude: 139.003)
    ]
  let graph = SurfaceRoadGraphSnapshot(
    networkSnapshotID: wayPointSnapshotID,
    provenance: wayPointProvenance,
    edges: makeWayPointGraph().edges + [
      makeWayPointEdge(
        id: "test.edge.3",
        from: 3,
        to: 4,
        coordinateIndex: 2,
        segmentIndex: 2,
        coordinates: coordinates
      )
    ]
  )
  let repeatedKeyRequest = OSMWayPointPathTranslationRequest(
    providerDatasetID: wayPointDatasetID,
    routeCoordinates: coordinates,
    segmentIdentities: [
      OSMWayPointPathSegmentIdentity(providerDirectedEdgeKey: 20, osmWayID: 42),
      OSMWayPointPathSegmentIdentity(providerDirectedEdgeKey: 22, osmWayID: 42),
      OSMWayPointPathSegmentIdentity(providerDirectedEdgeKey: 20, osmWayID: 42),
    ]
  )

  #expect(throws: OSMWayPointPathTranslationError.repeatedProviderEdgeKey(20)) {
    try OSMWayPointPathTranslator(graph: graph).translate(repeatedKeyRequest)
  }
}

private let wayPointDatasetID = "test.dataset.graphhopper.20260721"
private let wayPointSnapshotID = "test.snapshot.graphhopper-way-point-v1"
private let wayPointCoordinates = [
  SurfaceCoordinate(latitude: 35, longitude: 139),
  SurfaceCoordinate(latitude: 35, longitude: 139.001),
  SurfaceCoordinate(latitude: 35, longitude: 139.002),
]
private let wayPointProvenance = SurfaceRoadGraphProvenance(
  source: "Synthetic",
  sourceSnapshotAt: "2026-07-21T19:03:43Z",
  sourceDatasetID: wayPointDatasetID,
  sourceURI: "https://example.invalid/osm-way-point-path",
  licence: "TEST-ONLY",
  attribution: "Synthetic test data"
)

private func makeWayPointRequest(
  datasetID: String = wayPointDatasetID
) -> OSMWayPointPathTranslationRequest {
  OSMWayPointPathTranslationRequest(
    providerDatasetID: datasetID,
    routeCoordinates: wayPointCoordinates,
    segmentIdentities: makeWayPointIdentities()
  )
}

private func makeWayPointIdentities() -> [OSMWayPointPathSegmentIdentity] {
  [
    OSMWayPointPathSegmentIdentity(providerDirectedEdgeKey: 20, osmWayID: 42),
    OSMWayPointPathSegmentIdentity(providerDirectedEdgeKey: 20, osmWayID: 42),
  ]
}

private func makeWayPointGraph() -> SurfaceRoadGraphSnapshot {
  SurfaceRoadGraphSnapshot(
    networkSnapshotID: wayPointSnapshotID,
    provenance: wayPointProvenance,
    edges: [
      makeWayPointEdge(
        id: "test.edge.1",
        from: 1,
        to: 2,
        coordinateIndex: 0,
        segmentIndex: 0
      ),
      makeWayPointEdge(
        id: "test.edge.2",
        from: 2,
        to: 3,
        coordinateIndex: 1,
        segmentIndex: 1
      ),
    ]
  )
}

private func makeWayPointEdge(
  id: String,
  from: Int64,
  to: Int64,
  coordinateIndex: Int,
  segmentIndex: Int,
  coordinates: [SurfaceCoordinate] = wayPointCoordinates
) -> SurfaceRoadEdge {
  SurfaceRoadEdge(
    id: id,
    fromNodeID: "osm.node.\(from)",
    toNodeID: "osm.node.\(to)",
    kind: .ordinaryRoad,
    coordinates: Array(coordinates[coordinateIndex...(coordinateIndex + 1)]),
    sourceOSMWayID: 42,
    sourceOSMSegmentIndex: segmentIndex,
    sourceOSMDirection: .forward
  )
}
