import KaidoSurfaceRouting
import Testing

@Test("OSM path identity expands one provider edge and trims its partial start")
func osmPathTranslatorExpandsAndTrimsProviderEdge() throws {
  let graph = makeTranslationGraph(includeStackedExpressway: true)
  let request = OSMSelectedPathTranslationRequest(
    providerDatasetID: translationDatasetID,
    terminalOSMNodeID: 4,
    routeCoordinates: [
      SurfaceCoordinate(latitude: 35, longitude: 139.0015),
      translationCoordinates[2],
      translationCoordinates[3],
    ],
    edgeReferences: [
      OSMPathEdgeReference(
        providerEdgeID: "valhalla.edge.42",
        osmWayID: 42,
        beginOSMNodeID: 1,
        isForward: true,
        sourcePercentAlong: 0.5
      )
    ]
  )

  let evidence = try OSMSelectedPathTranslator(graph: graph).translate(request)

  #expect(evidence.networkSnapshotID == translationSnapshotID)
  #expect(evidence.providerDatasetID == translationDatasetID)
  #expect(
    evidence.directedEdgeIDs == [
      "osm.way.42.segment.1.forward",
      "osm.way.42.segment.2.forward",
    ]
  )
  #expect(!evidence.directedEdgeIDs.contains("osm.way.99.segment.1.forward"))
}

@Test("OSM path identity preserves reverse digitized direction")
func osmPathTranslatorPreservesReverseDirection() throws {
  let request = OSMSelectedPathTranslationRequest(
    providerDatasetID: translationDatasetID,
    terminalOSMNodeID: 1,
    routeCoordinates: translationCoordinates.reversed(),
    edgeReferences: [
      OSMPathEdgeReference(
        providerEdgeID: "valhalla.edge.42.reverse",
        osmWayID: 42,
        beginOSMNodeID: 4,
        isForward: false
      )
    ]
  )

  let evidence = try OSMSelectedPathTranslator(graph: makeTranslationGraph()).translate(request)

  #expect(
    evidence.directedEdgeIDs == [
      "osm.way.42.segment.2.reverse",
      "osm.way.42.segment.1.reverse",
      "osm.way.42.segment.0.reverse",
    ]
  )
}

@Test("Consecutive provider edges derive exact shared-node boundaries")
func osmPathTranslatorExpandsConsecutiveProviderEdges() throws {
  let terminal = SurfaceCoordinate(latitude: 35, longitude: 139.004)
  var edges = makeTranslationGraph().edges
  edges.append(
    translationEdge(
      id: "osm.way.43.segment.0.forward",
      fromNode: 4,
      toNode: 5,
      fromCoordinate: translationCoordinates[3],
      toCoordinate: terminal,
      segmentIndex: 0,
      direction: .forward,
      wayID: 43
    )
  )
  let graph = SurfaceRoadGraphSnapshot(
    networkSnapshotID: translationSnapshotID,
    provenance: translationProvenance,
    edges: edges
  )
  let request = OSMSelectedPathTranslationRequest(
    providerDatasetID: translationDatasetID,
    terminalOSMNodeID: 5,
    routeCoordinates: translationCoordinates + [terminal],
    edgeReferences: [
      OSMPathEdgeReference(
        providerEdgeID: "valhalla.edge.42",
        osmWayID: 42,
        beginOSMNodeID: 1,
        isForward: true
      ),
      OSMPathEdgeReference(
        providerEdgeID: "valhalla.edge.43",
        osmWayID: 43,
        beginOSMNodeID: 4,
        isForward: true
      ),
    ]
  )

  let evidence = try OSMSelectedPathTranslator(graph: graph).translate(request)

  #expect(
    evidence.directedEdgeIDs == [
      "osm.way.42.segment.0.forward",
      "osm.way.42.segment.1.forward",
      "osm.way.42.segment.2.forward",
      "osm.way.43.segment.0.forward",
    ]
  )
}

@Test("OSM path translation fails closed across datasets or missing node identity")
func osmPathTranslatorRejectsInvalidIdentity() throws {
  let translator = OSMSelectedPathTranslator(graph: makeTranslationGraph())
  let wrongDataset = makeTranslationRequest(providerDatasetID: "test.dataset.other")
  let missingNode = makeTranslationRequest(beginOSMNodeID: 999)

  #expect(throws: OSMSelectedPathTranslationError.self) {
    try translator.translate(wrongDataset)
  }
  #expect(throws: OSMSelectedPathTranslationError.self) {
    try translator.translate(missingNode)
  }
}

@Test("OSM path translation rejects ambiguous source metadata")
func osmPathTranslatorRejectsAmbiguousMetadata() throws {
  var edges = makeTranslationGraph().edges
  edges.append(
    translationEdge(
      id: "osm.way.42.segment.100.forward",
      fromNode: 1,
      toNode: 4,
      fromCoordinate: translationCoordinates[0],
      toCoordinate: translationCoordinates[3],
      segmentIndex: 100,
      direction: .forward
    )
  )
  let graph = SurfaceRoadGraphSnapshot(
    networkSnapshotID: translationSnapshotID,
    provenance: translationProvenance,
    edges: edges
  )

  #expect(throws: OSMSelectedPathTranslationError.ambiguousPath(index: 0)) {
    try OSMSelectedPathTranslator(graph: graph).translate(makeTranslationRequest())
  }
}

private let translationSnapshotID = "test.snapshot.osm-translation-v1"
private let translationDatasetID = "test.dataset.20260721"
private let translationCoordinates = [
  SurfaceCoordinate(latitude: 35, longitude: 139),
  SurfaceCoordinate(latitude: 35, longitude: 139.001),
  SurfaceCoordinate(latitude: 35, longitude: 139.002),
  SurfaceCoordinate(latitude: 35, longitude: 139.003),
]
private let translationProvenance = SurfaceRoadGraphProvenance(
  source: "Synthetic",
  sourceSnapshotAt: "2026-07-21T19:03:43Z",
  sourceDatasetID: translationDatasetID,
  sourceURI: "https://example.invalid/osm-translation",
  licence: "TEST-ONLY",
  attribution: "Synthetic test data"
)

private func makeTranslationRequest(
  providerDatasetID: String = translationDatasetID,
  beginOSMNodeID: Int64 = 1
) -> OSMSelectedPathTranslationRequest {
  OSMSelectedPathTranslationRequest(
    providerDatasetID: providerDatasetID,
    terminalOSMNodeID: 4,
    routeCoordinates: translationCoordinates,
    edgeReferences: [
      OSMPathEdgeReference(
        providerEdgeID: "valhalla.edge.42",
        osmWayID: 42,
        beginOSMNodeID: beginOSMNodeID,
        isForward: true
      )
    ]
  )
}

private func makeTranslationGraph(
  includeStackedExpressway: Bool = false
) -> SurfaceRoadGraphSnapshot {
  var edges: [SurfaceRoadEdge] = []
  for index in 0..<3 {
    edges.append(
      translationEdge(
        id: "osm.way.42.segment.\(index).forward",
        fromNode: Int64(index + 1),
        toNode: Int64(index + 2),
        fromCoordinate: translationCoordinates[index],
        toCoordinate: translationCoordinates[index + 1],
        segmentIndex: index,
        direction: .forward
      )
    )
    edges.append(
      translationEdge(
        id: "osm.way.42.segment.\(index).reverse",
        fromNode: Int64(index + 2),
        toNode: Int64(index + 1),
        fromCoordinate: translationCoordinates[index + 1],
        toCoordinate: translationCoordinates[index],
        segmentIndex: index,
        direction: .reverse
      )
    )
    if includeStackedExpressway {
      edges.append(
        SurfaceRoadEdge(
          id: "osm.way.99.segment.\(index).forward",
          fromNodeID: "osm.node.\(index + 101)",
          toNodeID: "osm.node.\(index + 102)",
          kind: .expressway,
          coordinates: [translationCoordinates[index], translationCoordinates[index + 1]],
          tollDomainID: "test.toll.external",
          sourceOSMWayID: 99,
          sourceOSMSegmentIndex: index,
          sourceOSMDirection: .forward
        )
      )
    }
  }
  return SurfaceRoadGraphSnapshot(
    networkSnapshotID: translationSnapshotID,
    provenance: translationProvenance,
    edges: edges
  )
}

private func translationEdge(
  id: String,
  fromNode: Int64,
  toNode: Int64,
  fromCoordinate: SurfaceCoordinate,
  toCoordinate: SurfaceCoordinate,
  segmentIndex: Int,
  direction: OSMWayDirection,
  wayID: Int64 = 42
) -> SurfaceRoadEdge {
  SurfaceRoadEdge(
    id: id,
    fromNodeID: "osm.node.\(fromNode)",
    toNodeID: "osm.node.\(toNode)",
    kind: .ordinaryRoad,
    coordinates: [fromCoordinate, toCoordinate],
    sourceOSMWayID: wayID,
    sourceOSMSegmentIndex: segmentIndex,
    sourceOSMDirection: direction
  )
}
