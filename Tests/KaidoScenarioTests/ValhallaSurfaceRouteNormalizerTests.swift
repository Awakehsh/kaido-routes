import Foundation
import KaidoSurfaceRouting
import Testing

@Test("Valhalla route and edge_walk responses normalize into exact OSM path identity")
func valhallaResponsesNormalizeToOSMIdentity() throws {
  let normalized = try makeValhallaNormalizer().normalize(
    routeResponseData: makeValhallaRouteResponse(),
    traceAttributesResponseData: makeValhallaTraceResponse(),
    candidateID: "test.candidate.valhalla",
    terminalOSMNodeID: 3
  )

  #expect(normalized.candidateWithoutSelectedPathEvidence.coordinates == valhallaCoordinates)
  #expect(normalized.candidateWithoutSelectedPathEvidence.distanceMeters == 200)
  #expect(normalized.candidateWithoutSelectedPathEvidence.selectedPathEvidence == nil)
  #expect(normalized.translationRequest.providerDatasetID == valhallaDatasetID)
  #expect(normalized.translationRequest.terminalOSMNodeID == 3)
  #expect(normalized.translationRequest.edgeReferences.count == 2)
  #expect(normalized.translationRequest.edgeReferences[0].osmWayID == 42)
  #expect(normalized.translationRequest.edgeReferences[1].beginOSMNodeID == 2)
}

@Test("Valhalla normalization fails closed on response or dataset drift")
func valhallaNormalizationRejectsDrift() {
  #expect(
    throws: ValhallaSurfaceRouteNormalizationError.providerDatasetMismatch(
      expected: valhallaDatasetID,
      received: "2026072102"
    )
  ) {
    try makeValhallaNormalizer().normalize(
      routeResponseData: makeValhallaRouteResponse(),
      traceAttributesResponseData: makeValhallaTraceResponse(datasetID: 2_026_072_102),
      candidateID: "test.candidate.valhalla",
      terminalOSMNodeID: 3
    )
  }

  #expect(throws: ValhallaSurfaceRouteNormalizationError.traceShapeMismatch) {
    try makeValhallaNormalizer().normalize(
      routeResponseData: makeValhallaRouteResponse(),
      traceAttributesResponseData: makeValhallaTraceResponse(shape: "??"),
      candidateID: "test.candidate.valhalla",
      terminalOSMNodeID: 3
    )
  }
}

@Test("Valhalla response through translation and hard gates is deterministic")
func valhallaResponseToHardGateChain() async throws {
  let graph = makeValhallaGraph()
  let fixture = makeValhallaFixture()
  let normalized = try makeValhallaNormalizer().normalize(
    routeResponseData: makeValhallaRouteResponse(),
    traceAttributesResponseData: makeValhallaTraceResponse(),
    candidateID: "test.candidate.valhalla",
    terminalOSMNodeID: 3
  )
  let candidate = try normalized.translatedCandidate(graph: graph)
  let request = try fixture.makeRequest(originID: "test.origin.same-side")
  let inspection = await DirectedRoadGraphInspector(graph: graph).inspect(
    candidate: candidate,
    request: request,
    fixture: fixture
  )
  let evaluation = SurfaceHardGateEvaluator.evaluate(
    candidate: candidate,
    request: request,
    fixture: fixture,
    inspection: inspection,
    expectedProviderID: valhallaProviderID
  )

  #expect(candidate.selectedPathEvidence?.directedEdgeIDs == ["test.edge.1", "test.edge.2"])
  #expect(inspection.geometryBindingIsUnambiguous == true)
  #expect(inspection.unmatchedSampleCount == 0)
  #expect(evaluation.isAccepted)
  #expect(evaluation.hardGates.allSatisfy { $0.status == .pass })
}

@Test("Bounded Valhalla provider performs route then exact edge_walk translation")
func valhallaProviderExecutesBoundedProtocol() async throws {
  let transport = StubValhallaTransport(
    responses: [
      ValhallaHTTPResponse(statusCode: 200, body: makeValhallaRouteResponse()),
      ValhallaHTTPResponse(statusCode: 200, body: makeValhallaTraceResponse()),
    ]
  )
  let provider = try makeValhallaProvider(transport: transport)
  let request = try makeValhallaFixture().makeRequest(originID: "test.origin.same-side")

  let response = await provider.routes(for: request)
  guard case .success(let candidates) = response else {
    Issue.record("Expected one translated Valhalla candidate")
    return
  }
  let requests = await transport.recordedRequests()

  #expect(candidates.count == 1)
  #expect(candidates[0].providerID == valhallaProviderID)
  #expect(candidates[0].selectedPathEvidence?.directedEdgeIDs == ["test.edge.1", "test.edge.2"])
  #expect(requests.map(\.action) == [.route, .traceAttributes])

  let routeJSON = try #require(
    JSONSerialization.jsonObject(with: requests[0].body) as? [String: Any]
  )
  #expect(routeJSON["units"] as? String == "kilometers")
  #expect(routeJSON["language"] as? String == "ja-JP")
  #expect(routeJSON["directions_options"] == nil)
  #expect(routeJSON["alternates"] as? Int == 0)
  let costingOptions = try #require(routeJSON["costing_options"] as? [String: Any])
  let auto = try #require(costingOptions["auto"] as? [String: Any])
  #expect(auto["use_highways"] as? Double == 0)
  #expect(auto["use_tolls"] as? Double == 0)

  let traceJSON = try #require(
    JSONSerialization.jsonObject(with: requests[1].body) as? [String: Any]
  )
  #expect(traceJSON["shape_match"] as? String == "edge_walk")
  #expect(traceJSON["encoded_polyline"] as? String == encodeValhallaPolyline6(valhallaCoordinates))
}

@Test("Bounded Valhalla provider discloses a no-route response")
func valhallaProviderDisclosesNoRoute() async throws {
  let errorBody = try JSONSerialization.data(
    withJSONObject: ["error_code": 442, "error": "No path could be found for input"],
    options: [.sortedKeys]
  )
  let transport = StubValhallaTransport(
    responses: [ValhallaHTTPResponse(statusCode: 400, body: errorBody)]
  )
  let provider = try makeValhallaProvider(transport: transport)
  let request = try makeValhallaFixture().makeRequest(originID: "test.origin.same-side")

  let response = await provider.routes(for: request)
  guard case .failure(let failure) = response else {
    Issue.record("Expected an explicit provider failure")
    return
  }

  #expect(failure.kind == .noRoute)
  #expect(failure.providerErrorCode == "442")
  #expect(await transport.recordedRequests().count == 1)
}

private let valhallaProviderID = "test.valhalla.local"
private let valhallaDatasetID = "2026072101"
private let valhallaSnapshotID = "test.snapshot.valhalla-normalizer-v1"
private let valhallaCoordinates = [
  SurfaceCoordinate(latitude: 35, longitude: 139),
  SurfaceCoordinate(latitude: 35, longitude: 139.001),
  SurfaceCoordinate(latitude: 35, longitude: 139.002),
]

private func makeValhallaNormalizer() -> ValhallaSurfaceRouteNormalizer {
  ValhallaSurfaceRouteNormalizer(
    providerID: valhallaProviderID,
    expectedProviderDatasetID: valhallaDatasetID
  )
}

private func makeValhallaProvider(
  transport: any ValhallaHTTPTransport
) throws -> ValhallaSurfaceRouteProvider {
  try ValhallaSurfaceRouteProvider(
    graph: makeValhallaGraph(),
    manifest: makeValhallaProviderManifest(),
    configuration: ValhallaSurfaceProviderConfiguration(
      candidateProviderID: valhallaProviderID,
      adapterVersion: "test.1",
      dataReviewStatus: .derivedFixtureReviewed,
      manifestValidationProfile: .structural,
      approachBindings: [
        ValhallaApproachIdentityBinding(
          anchorID: "test.anchor.entry",
          directedSurfaceEdgeID: "test.edge.2",
          terminalOSMNodeID: 3
        )
      ]
    ),
    transport: transport
  )
}

private func makeValhallaProviderManifest() -> SurfaceRoutingBuildManifest {
  let sha256 = String(repeating: "b", count: 64)
  return SurfaceRoutingBuildManifest(
    id: "test.manifest.valhalla-provider",
    createdAt: "2026-07-22T10:00:00Z",
    intendedUse: .labOnly,
    networkSnapshotID: valhallaSnapshotID,
    providerDatasetID: valhallaDatasetID,
    engineBuild: SurfaceRoutingEngineBuild(
      id: "test.build.valhalla",
      providerID: "valhalla",
      providerVersion: "3.8.2",
      containerImage: "ghcr.io/valhalla/valhalla:3.8.2",
      containerDigest: "sha256:\(sha256)"
    ),
    sources: [
      SurfaceRoutingBuildSource(
        id: "test.source.valhalla",
        roles: [.roadNetwork],
        snapshotAt: "2026-07-21T19:03:43Z",
        uri: "https://example.invalid/valhalla.osm.pbf",
        sha256: sha256,
        byteCount: 100,
        licence: "TEST-ONLY",
        attribution: "Synthetic test data"
      )
    ],
    artifacts: [
      SurfaceRoutingBuildArtifact(
        id: "test.artifact.valhalla",
        role: .routingTiles,
        relativePath: "artifacts/tiles.tar",
        format: "test",
        sha256: sha256,
        byteCount: 100
      ),
      SurfaceRoutingBuildArtifact(
        id: "test.artifact.kaido-graph",
        role: .kaidoDirectedGraph,
        relativePath: "artifacts/kaido-graph.json",
        format: "json",
        sha256: sha256,
        byteCount: 100
      ),
    ],
    capabilities: SurfaceRoutingBuildCapabilities(
      includesAdministrativeData: false,
      includesTimeZoneData: false,
      keepsAllOSMNodeIDs: true
    ),
    adminVerifications: [],
    releaseBlockers: ["Synthetic test build."]
  )
}

private func makeValhallaRouteResponse() -> Data {
  let object: [String: Any] = [
    "trip": [
      "status": 0,
      "units": "kilometers",
      "legs": [
        [
          "shape": encodeValhallaPolyline6(valhallaCoordinates),
          "maneuvers": [
            ["instruction": "Continue on the synthetic road.", "length": 0.2],
            ["instruction": "Arrive at the synthetic anchor.", "length": 0.0],
          ],
        ]
      ],
      "summary": [
        "length": 0.2,
        "time": 20.0,
        "has_highway": false,
        "has_toll": false,
      ],
    ]
  ]
  return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func makeValhallaTraceResponse(
  datasetID: UInt64 = 2_026_072_101,
  shape: String? = nil
) -> Data {
  let object: [String: Any] = [
    "osm_changeset": datasetID,
    "shape": shape ?? encodeValhallaPolyline6(valhallaCoordinates),
    "units": "kilometers",
    "edges": [
      [
        "id": 100,
        "way_id": 42,
        "node_id": 1,
        "forward": true,
        "begin_shape_index": 0,
        "end_shape_index": 1,
      ],
      [
        "id": 101,
        "way_id": 43,
        "node_id": 2,
        "forward": true,
        "begin_shape_index": 1,
        "end_shape_index": 2,
      ],
    ],
  ]
  return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func makeValhallaGraph() -> SurfaceRoadGraphSnapshot {
  SurfaceRoadGraphSnapshot(
    networkSnapshotID: valhallaSnapshotID,
    provenance: SurfaceRoadGraphProvenance(
      source: "Synthetic",
      sourceSnapshotAt: "2026-07-21T19:03:43Z",
      sourceDatasetID: valhallaDatasetID,
      sourceURI: "https://example.invalid/valhalla-normalizer",
      licence: "TEST-ONLY",
      attribution: "Synthetic test data"
    ),
    edges: [
      makeValhallaEdge(
        id: "test.edge.1",
        fromNode: 1,
        toNode: 2,
        coordinateIndex: 0,
        wayID: 42
      ),
      makeValhallaEdge(
        id: "test.edge.2",
        fromNode: 2,
        toNode: 3,
        coordinateIndex: 1,
        wayID: 43
      ),
    ]
  )
}

private func makeValhallaEdge(
  id: String,
  fromNode: Int64,
  toNode: Int64,
  coordinateIndex: Int,
  wayID: Int64
) -> SurfaceRoadEdge {
  SurfaceRoadEdge(
    id: id,
    fromNodeID: "osm.node.\(fromNode)",
    toNodeID: "osm.node.\(toNode)",
    kind: .ordinaryRoad,
    coordinates: [
      valhallaCoordinates[coordinateIndex],
      valhallaCoordinates[coordinateIndex + 1],
    ],
    sourceOSMWayID: wayID,
    sourceOSMSegmentIndex: 0,
    sourceOSMDirection: .forward
  )
}

private func makeValhallaFixture() -> EntranceProbeFixture {
  EntranceProbeFixture(
    schemaVersion: "1.0",
    id: "test.fixture.valhalla-normalizer",
    networkSnapshotID: valhallaSnapshotID,
    evidence: ProbeEvidence(
      classification: .synthetic,
      checkedAt: "2026-07-22T10:00:00Z",
      sources: [],
      limitations: [],
      releaseBlockers: []
    ),
    entrance: ProbeEntranceFacility(
      facilityID: "test.facility.entry",
      accessComplexID: "test.access.entry",
      targetCarriagewayID: "test.carriageway.entry",
      targetDirection: "EAST"
    ),
    approachAnchor: DirectedApproachAnchor(
      id: "test.anchor.entry",
      coordinate: valhallaCoordinates[2],
      directedSurfaceEdgeID: "test.edge.2",
      expectedBearingDegrees: 90,
      bearingToleranceDegrees: 10,
      maxTerminalDistanceMeters: 2
    ),
    entryTransition: ProbeEntryTransition(
      directedEdgeIDs: ["test.edge.entry"],
      firstRouteOccurrenceID: "test.occurrence.entry"
    ),
    journeyCompatibility: ProbeJourneyCompatibility(
      allowedJoinOccurrenceIDs: ["test.occurrence.entry"],
      finishPolicies: [.fixedExit],
      compatibleExitFacilityIDs: ["test.facility.exit"]
    ),
    prohibitions: ProbeProhibitions(
      forbiddenEarlyExpresswayEdgeIDs: [],
      forbiddenTollDomainIDs: []
    ),
    origins: [
      ProbeOrigin(
        id: "test.origin.same-side",
        kind: .sameSide,
        coordinate: valhallaCoordinates[0],
        notes: "Synthetic route normalization origin."
      )
    ]
  )
}

private func encodeValhallaPolyline6(_ coordinates: [SurfaceCoordinate]) -> String {
  var previousLatitude: Int64 = 0
  var previousLongitude: Int64 = 0
  var encoded = ""
  for coordinate in coordinates {
    let latitude = Int64((coordinate.latitude * 1_000_000).rounded())
    let longitude = Int64((coordinate.longitude * 1_000_000).rounded())
    encoded += encodePolylineDelta(latitude - previousLatitude)
    encoded += encodePolylineDelta(longitude - previousLongitude)
    previousLatitude = latitude
    previousLongitude = longitude
  }
  return encoded
}

private func encodePolylineDelta(_ delta: Int64) -> String {
  var value = UInt64(bitPattern: delta < 0 ? ~(delta << 1) : delta << 1)
  var result = ""
  while value >= 0x20 {
    result.unicodeScalars.append(UnicodeScalar(Int((0x20 | (value & 0x1f)) + 63))!)
    value >>= 5
  }
  result.unicodeScalars.append(UnicodeScalar(Int(value + 63))!)
  return result
}

private actor StubValhallaTransport: ValhallaHTTPTransport {
  struct RecordedRequest: Sendable {
    let action: ValhallaServiceAction
    let body: Data
  }

  private var responses: [ValhallaHTTPResponse]
  private var requests: [RecordedRequest] = []

  init(responses: [ValhallaHTTPResponse]) {
    self.responses = responses
  }

  func post(
    action: ValhallaServiceAction,
    jsonBody: Data
  ) async throws -> ValhallaHTTPResponse {
    requests.append(RecordedRequest(action: action, body: jsonBody))
    guard !responses.isEmpty else {
      throw ValhallaHTTPTransportFailure.invalidResponse
    }
    return responses.removeFirst()
  }

  func recordedRequests() -> [RecordedRequest] {
    requests
  }
}
