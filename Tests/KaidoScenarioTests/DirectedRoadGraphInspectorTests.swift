import KaidoSurfaceRouting
import Testing

@Test("Directed graph inspector binds a legal synthetic surface approach")
func directedGraphInspectorAcceptsLegalApproach() async throws {
  let fixture = makeInspectorFixture()
  let request = try fixture.makeRequest(originID: "test.origin.same-side")
  let candidate = makeInspectorCandidate(request: request)
  let inspector = DirectedRoadGraphInspector(graph: makeInspectorGraph())

  let inspection = await inspector.inspect(
    candidate: candidate,
    request: request,
    fixture: fixture
  )
  let result = SurfaceHardGateEvaluator.evaluate(
    candidate: candidate,
    request: request,
    fixture: fixture,
    inspection: inspection,
    expectedProviderID: "test.provider"
  )

  #expect(inspection.anchorBinding?.directedSurfaceEdgeID == "test.edge.approach")
  #expect(inspection.geometryBindingIsUnambiguous == true)
  #expect(inspection.expresswayEdgeIDsBeforeEntry == [])
  #expect(inspection.crossedTollDomainIDs == [])
  #expect(result.disposition == .accepted)
}

@Test("Directed graph inspector reports early expressway and external toll crossings")
func directedGraphInspectorReportsForbiddenCrossings() async throws {
  let fixture = makeInspectorFixture()
  let request = try fixture.makeRequest(originID: "test.origin.same-side")
  let candidate = makeInspectorCandidate(request: request)
  let graph = makeInspectorGraph(
    initialKind: .expressway,
    initialEdgeID: "test.edge.forbidden-expressway",
    initialTollDomainID: "test.toll.external"
  )
  let inspection = await DirectedRoadGraphInspector(graph: graph).inspect(
    candidate: candidate,
    request: request,
    fixture: fixture
  )
  let result = SurfaceHardGateEvaluator.evaluate(
    candidate: candidate,
    request: request,
    fixture: fixture,
    inspection: inspection,
    expectedProviderID: "test.provider"
  )
  let statuses = Dictionary(uniqueKeysWithValues: result.hardGates.map { ($0.gate, $0.status) })

  #expect(inspection.expresswayEdgeIDsBeforeEntry == ["test.edge.forbidden-expressway"])
  #expect(inspection.crossedTollDomainIDs == ["test.toll.external"])
  #expect(statuses[.noEarlyExpressway] == .fail)
  #expect(statuses[.allowedTollDomain] == .fail)
  #expect(result.disposition == .rejected)
}

@Test("Parallel same-direction graph edges remain ambiguous")
func directedGraphInspectorRejectsAmbiguousParallelEdges() async throws {
  let fixture = makeInspectorFixture()
  let request = try fixture.makeRequest(originID: "test.origin.same-side")
  let candidate = makeInspectorCandidate(request: request)
  var edges = makeInspectorGraph().edges
  edges.append(
    SurfaceRoadEdge(
      id: "test.edge.parallel",
      fromNodeID: "test.node.parallel-from",
      toNodeID: "test.node.parallel-to",
      kind: .ordinaryRoad,
      coordinates: [inspectorMiddle, inspectorAnchor]
    )
  )
  let inspector = DirectedRoadGraphInspector(
    graph: SurfaceRoadGraphSnapshot(
      networkSnapshotID: fixture.networkSnapshotID,
      edges: edges
    )
  )

  let inspection = await inspector.inspect(
    candidate: candidate,
    request: request,
    fixture: fixture
  )

  #expect(inspection.anchorBinding?.directedSurfaceEdgeID == "test.edge.approach")
  #expect(inspection.geometryBindingIsUnambiguous == false)
}

@Test("Terminal heading selects the actual directed edge instead of reverse geometry")
func directedGraphInspectorRejectsReverseApproach() async throws {
  let fixture = makeInspectorFixture()
  let request = try fixture.makeRequest(originID: "test.origin.same-side")
  let candidate = makeInspectorCandidate(request: request)
  let graph = SurfaceRoadGraphSnapshot(
    networkSnapshotID: fixture.networkSnapshotID,
    edges: [
      SurfaceRoadEdge(
        id: "test.edge.surface-initial",
        fromNodeID: "test.node.origin",
        toNodeID: "test.node.middle",
        kind: .ordinaryRoad,
        coordinates: [inspectorOrigin, inspectorMiddle]
      ),
      SurfaceRoadEdge(
        id: "test.edge.approach",
        fromNodeID: "test.node.anchor",
        toNodeID: "test.node.middle-reverse",
        kind: .ordinaryRoad,
        coordinates: [inspectorAnchor, inspectorMiddle]
      ),
      SurfaceRoadEdge(
        id: "test.edge.wrong-direction",
        fromNodeID: "test.node.middle",
        toNodeID: "test.node.anchor",
        kind: .ordinaryRoad,
        coordinates: [inspectorMiddle, inspectorAnchor]
      ),
    ]
  )
  let inspection = await DirectedRoadGraphInspector(graph: graph).inspect(
    candidate: candidate,
    request: request,
    fixture: fixture
  )
  let result = SurfaceHardGateEvaluator.evaluate(
    candidate: candidate,
    request: request,
    fixture: fixture,
    inspection: inspection,
    expectedProviderID: "test.provider"
  )
  let directedGate = result.hardGates.first { $0.gate == .correctDirectedApproach }

  #expect(inspection.anchorBinding?.directedSurfaceEdgeID == "test.edge.wrong-direction")
  #expect(inspection.geometryBindingIsUnambiguous == true)
  #expect(directedGate?.status == .fail)
  #expect(directedGate?.reasonCodes.contains("APPROACH_EDGE_MISMATCH") == true)
}

@Test("Skipped connector edges remain visible to hard gates")
func directedGraphInspectorReportsSkippedConnector() async throws {
  let fixture = makeInspectorFixture()
  let request = try fixture.makeRequest(originID: "test.origin.same-side")
  let candidate = makeInspectorCandidate(request: request)
  let graph = SurfaceRoadGraphSnapshot(
    networkSnapshotID: fixture.networkSnapshotID,
    edges: [
      SurfaceRoadEdge(
        id: "test.edge.surface-initial",
        fromNodeID: "test.node.origin",
        toNodeID: "test.node.middle",
        kind: .ordinaryRoad,
        coordinates: [inspectorOrigin, inspectorMiddle]
      ),
      SurfaceRoadEdge(
        id: "test.edge.forbidden-expressway",
        fromNodeID: "test.node.middle",
        toNodeID: "test.node.detour-return",
        kind: .expressway,
        coordinates: [
          SurfaceCoordinate(latitude: 35.01, longitude: 139.0005),
          SurfaceCoordinate(latitude: 35.01, longitude: 139.0006),
        ],
        tollDomainID: "test.toll.external"
      ),
      SurfaceRoadEdge(
        id: "test.edge.approach",
        fromNodeID: "test.node.detour-return",
        toNodeID: "test.node.anchor",
        kind: .ordinaryRoad,
        coordinates: [inspectorMiddle, inspectorAnchor]
      ),
    ]
  )

  let inspection = await DirectedRoadGraphInspector(graph: graph).inspect(
    candidate: candidate,
    request: request,
    fixture: fixture
  )

  #expect(inspection.geometryBindingIsUnambiguous == false)
  #expect(inspection.expresswayEdgeIDsBeforeEntry == ["test.edge.forbidden-expressway"])
  #expect(inspection.crossedTollDomainIDs == ["test.toll.external"])
}

@Test("Inspector fails closed when fixture and graph snapshots differ")
func directedGraphInspectorRejectsSnapshotMismatch() async throws {
  let fixture = makeInspectorFixture()
  let request = try fixture.makeRequest(originID: "test.origin.same-side")
  let candidate = makeInspectorCandidate(request: request)
  let wrongSnapshot = SurfaceRoadGraphSnapshot(
    networkSnapshotID: "test.snapshot.other",
    edges: makeInspectorGraph().edges
  )

  let inspection = await DirectedRoadGraphInspector(graph: wrongSnapshot).inspect(
    candidate: candidate,
    request: request,
    fixture: fixture
  )

  #expect(inspection.anchorBinding == nil)
  #expect(inspection.geometryBindingIsUnambiguous == false)
  #expect(inspection.expresswayEdgeIDsBeforeEntry == nil)
  #expect(inspection.crossedTollDomainIDs == nil)
}

private let inspectorOrigin = SurfaceCoordinate(latitude: 35, longitude: 139)
private let inspectorMiddle = SurfaceCoordinate(latitude: 35, longitude: 139.0005)
private let inspectorAnchor = SurfaceCoordinate(latitude: 35, longitude: 139.001)

private func makeInspectorGraph(
  initialKind: SurfaceRoadEdgeKind = .ordinaryRoad,
  initialEdgeID: String = "test.edge.surface-initial",
  initialTollDomainID: String? = nil
) -> SurfaceRoadGraphSnapshot {
  SurfaceRoadGraphSnapshot(
    networkSnapshotID: "test.snapshot.inspector-v1",
    edges: [
      SurfaceRoadEdge(
        id: initialEdgeID,
        fromNodeID: "test.node.origin",
        toNodeID: "test.node.middle",
        kind: initialKind,
        coordinates: [inspectorOrigin, inspectorMiddle],
        tollDomainID: initialTollDomainID
      ),
      SurfaceRoadEdge(
        id: "test.edge.approach",
        fromNodeID: "test.node.middle",
        toNodeID: "test.node.anchor",
        kind: .ordinaryRoad,
        coordinates: [inspectorMiddle, inspectorAnchor]
      ),
    ]
  )
}

private func makeInspectorCandidate(request: SurfaceRouteRequest) -> SurfaceRouteCandidate {
  SurfaceRouteCandidate(
    id: "test.candidate.inspector",
    providerID: "test.provider",
    coordinates: [inspectorOrigin, inspectorMiddle, inspectorAnchor],
    steps: [],
    distanceMeters: 92,
    expectedTravelTimeSeconds: 20,
    hasHighways: false,
    hasTolls: false
  )
}

private func makeInspectorFixture() -> EntranceProbeFixture {
  EntranceProbeFixture(
    schemaVersion: "1.0",
    id: "test.fixture.inspector",
    networkSnapshotID: "test.snapshot.inspector-v1",
    evidence: ProbeEvidence(
      classification: .synthetic,
      checkedAt: "2026-07-22",
      sources: [],
      limitations: ["Synthetic graph only."],
      releaseBlockers: ["Replace with reviewed real evidence."]
    ),
    entrance: ProbeEntranceFacility(
      facilityID: "test.entry.inspector",
      accessComplexID: "test.access-complex.inspector",
      targetCarriagewayID: "test.carriageway.inspector",
      targetDirection: "INNER"
    ),
    approachAnchor: DirectedApproachAnchor(
      id: "test.anchor.inspector",
      coordinate: inspectorAnchor,
      directedSurfaceEdgeID: "test.edge.approach",
      expectedBearingDegrees: 90,
      bearingToleranceDegrees: 20,
      maxTerminalDistanceMeters: 10
    ),
    entryTransition: ProbeEntryTransition(
      directedEdgeIDs: ["test.edge.entry-transition"],
      firstRouteOccurrenceID: "test.occurrence.join"
    ),
    journeyCompatibility: ProbeJourneyCompatibility(
      allowedJoinOccurrenceIDs: ["test.occurrence.join"],
      finishPolicies: [.fixedExit],
      compatibleExitFacilityIDs: ["test.exit.inspector"]
    ),
    prohibitions: ProbeProhibitions(
      forbiddenEarlyExpresswayEdgeIDs: ["test.edge.forbidden-expressway"],
      forbiddenTollDomainIDs: ["test.toll.external"]
    ),
    origins: [
      ProbeOrigin(
        id: "test.origin.same-side",
        kind: .sameSide,
        coordinate: inspectorOrigin,
        notes: "Aligned synthetic origin."
      ),
      ProbeOrigin(
        id: "test.origin.cross-direction",
        kind: .crossDirection,
        coordinate: inspectorOrigin,
        notes: "Synthetic schema coverage only."
      ),
      ProbeOrigin(
        id: "test.origin.nearest-incompatible",
        kind: .nearestIncompatible,
        coordinate: inspectorOrigin,
        notes: "Synthetic schema coverage only."
      ),
    ]
  )
}
