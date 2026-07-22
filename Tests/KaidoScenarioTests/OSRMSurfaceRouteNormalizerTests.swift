import Foundation
import KaidoSurfaceRouting
import Testing

@Test("OSRM response normalizes dataset-bound ordered node identity")
func osrmResponseNormalizesToNodePathIdentity() throws {
  let normalized = try makeOSRMNormalizer().normalize(
    routeResponseData: makeOSRMRouteResponse(),
    candidateID: "test.candidate.osrm"
  )

  #expect(normalized.candidateWithoutSelectedPathEvidence.coordinates == osrmCoordinates)
  #expect(normalized.candidateWithoutSelectedPathEvidence.distanceMeters == 200)
  #expect(normalized.candidateWithoutSelectedPathEvidence.selectedPathEvidence == nil)
  #expect(normalized.translationRequest.providerDatasetID == osrmDatasetID)
  #expect(normalized.translationRequest.orderedOSMNodeIDs == [1, 2, 3])
  #expect(normalized.candidateWithoutSelectedPathEvidence.steps[0].instruction == "depart")
}

@Test("OSRM normalization rejects missing, drifting, or right-driving build identity")
func osrmNormalizationRejectsBuildDrift() {
  #expect(throws: OSRMSurfaceRouteNormalizationError.missingProviderDataset) {
    try makeOSRMNormalizer().normalize(
      routeResponseData: makeOSRMRouteResponse(datasetID: nil),
      candidateID: "test.candidate.osrm"
    )
  }
  #expect(
    throws: OSRMSurfaceRouteNormalizationError.providerDatasetMismatch(
      expected: osrmDatasetID,
      received: "2026072102"
    )
  ) {
    try makeOSRMNormalizer().normalize(
      routeResponseData: makeOSRMRouteResponse(datasetID: "2026072102"),
      candidateID: "test.candidate.osrm"
    )
  }
  #expect(
    throws: OSRMSurfaceRouteNormalizationError.unsupportedDrivingSide(
      stepIndex: 0,
      received: "right"
    )
  ) {
    try makeOSRMNormalizer().normalize(
      routeResponseData: makeOSRMRouteResponse(drivingSide: "right"),
      candidateID: "test.candidate.osrm"
    )
  }
}

@Test("OSRM response through node translation and hard gates is deterministic")
func osrmResponseToHardGateChain() async throws {
  let graph = makeOSRMGraph()
  let fixture = makeOSRMFixture()
  let normalized = try makeOSRMNormalizer().normalize(
    routeResponseData: makeOSRMRouteResponse(),
    candidateID: "test.candidate.osrm"
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
    expectedProviderID: osrmProviderID
  )

  #expect(candidate.selectedPathEvidence?.directedEdgeIDs == ["test.edge.1", "test.edge.2"])
  #expect(inspection.geometryBindingIsUnambiguous == true)
  #expect(inspection.unmatchedSampleCount == 0)
  #expect(evaluation.isAccepted)
  #expect(evaluation.hardGates.allSatisfy { $0.status == .pass })
}

@Test("Bounded OSRM provider requests full node annotations and translates them")
func osrmProviderExecutesBoundedProtocol() async throws {
  let transport = StubOSRMTransport(
    responses: [OSRMHTTPResponse(statusCode: 200, body: makeOSRMRouteResponse())]
  )
  let provider = try makeOSRMProvider(transport: transport)
  let request = try makeOSRMFixture().makeRequest(originID: "test.origin.same-side")

  let response = await provider.routes(for: request)
  guard case .success(let candidates) = response else {
    Issue.record("Expected one translated OSRM candidate")
    return
  }
  let requests = await transport.recordedRequests()
  let query = Dictionary(uniqueKeysWithValues: requests[0].queryItems.map { ($0.name, $0.value) })

  #expect(candidates.count == 1)
  #expect(candidates[0].providerID == osrmProviderID)
  #expect(candidates[0].selectedPathEvidence?.directedEdgeIDs == ["test.edge.1", "test.edge.2"])
  #expect(requests.count == 1)
  #expect(requests[0].path == "/route/v1/driving/139.0,35.0;139.002,35.0")
  #expect(query["alternatives"] == "false")
  #expect(query["steps"] == "true")
  #expect(query["annotations"] == "nodes")
  #expect(query["geometries"] == "geojson")
  #expect(query["overview"] == "full")
  #expect(query["bearings"] == ";90,10")
  #expect(query["exclude"] == "motorway")
}

@Test("Bounded OSRM provider discloses no route")
func osrmProviderDisclosesNoRoute() async throws {
  let body = try JSONSerialization.data(
    withJSONObject: ["code": "NoRoute", "message": "No route found"],
    options: [.sortedKeys]
  )
  let transport = StubOSRMTransport(
    responses: [OSRMHTTPResponse(statusCode: 200, body: body)]
  )
  let provider = try makeOSRMProvider(transport: transport)
  let request = try makeOSRMFixture().makeRequest(originID: "test.origin.same-side")

  let response = await provider.routes(for: request)
  guard case .failure(let failure) = response else {
    Issue.record("Expected an explicit OSRM no-route failure")
    return
  }

  #expect(failure.kind == .noRoute)
  #expect(failure.providerErrorCode == "NoRoute")
  #expect(await transport.recordedRequests().count == 1)
}

@Test("Bounded OSRM provider rejects a drifting terminal OSM node")
func osrmProviderRejectsTerminalNodeDrift() async throws {
  let transport = StubOSRMTransport(
    responses: [
      OSRMHTTPResponse(
        statusCode: 200,
        body: makeOSRMRouteResponse(orderedOSMNodeIDs: [1, 2, 4])
      )
    ]
  )
  let provider = try makeOSRMProvider(transport: transport)
  let request = try makeOSRMFixture().makeRequest(originID: "test.origin.same-side")

  let response = await provider.routes(for: request)
  guard case .failure(let failure) = response else {
    Issue.record("Expected terminal OSM node drift to fail closed")
    return
  }

  #expect(failure.kind == .server)
  #expect(failure.providerErrorCode == "TERMINAL_OSM_NODE_REJECTED")
  #expect(await transport.recordedRequests().count == 1)
}

private let osrmProviderID = "test.osrm.local"
private let osrmDatasetID = "2026072101"
private let osrmSnapshotID = "test.snapshot.osrm-normalizer-v1"
private let osrmCoordinates = [
  SurfaceCoordinate(latitude: 35, longitude: 139),
  SurfaceCoordinate(latitude: 35, longitude: 139.001),
  SurfaceCoordinate(latitude: 35, longitude: 139.002),
]

private func makeOSRMNormalizer() -> OSRMSurfaceRouteNormalizer {
  OSRMSurfaceRouteNormalizer(
    providerID: osrmProviderID,
    expectedProviderDatasetID: osrmDatasetID
  )
}

private func makeOSRMRouteResponse(
  datasetID: String? = osrmDatasetID,
  drivingSide: String = "left",
  orderedOSMNodeIDs: [Int64] = [1, 2, 3]
) -> Data {
  var object: [String: Any] = [
    "code": "Ok",
    "routes": [
      [
        "distance": 200.0,
        "duration": 20.0,
        "geometry": [
          "type": "LineString",
          "coordinates": osrmCoordinates.map { [$0.longitude, $0.latitude] },
        ],
        "legs": [
          [
            "annotation": ["nodes": orderedOSMNodeIDs],
            "steps": [
              [
                "distance": 200.0,
                "duration": 20.0,
                "name": "Synthetic Road",
                "ref": "T1",
                "driving_side": drivingSide,
                "maneuver": ["type": "depart"],
              ],
              [
                "distance": 0.0,
                "duration": 0.0,
                "name": "Synthetic Road",
                "ref": "T1",
                "driving_side": drivingSide,
                "maneuver": ["type": "arrive"],
              ],
            ],
          ]
        ],
      ]
    ],
  ]
  if let datasetID {
    object["data_version"] = datasetID
  }
  return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func makeOSRMProvider(
  transport: any OSRMHTTPTransport
) throws -> OSRMSurfaceRouteProvider {
  try OSRMSurfaceRouteProvider(
    graph: makeOSRMGraph(),
    manifest: makeOSRMProviderManifest(),
    configuration: OSRMSurfaceProviderConfiguration(
      candidateProviderID: osrmProviderID,
      adapterVersion: "test.1",
      dataReviewStatus: .derivedFixtureReviewed,
      manifestValidationProfile: .structural,
      approachBindings: [
        OSRMApproachIdentityBinding(
          anchorID: "test.anchor.entry",
          directedSurfaceEdgeID: "test.edge.2",
          terminalOSMNodeID: 3
        )
      ]
    ),
    transport: transport
  )
}

private func makeOSRMProviderManifest() -> SurfaceRoutingBuildManifest {
  let sha256 = String(repeating: "c", count: 64)
  return SurfaceRoutingBuildManifest(
    id: "test.manifest.osrm-provider",
    createdAt: "2026-07-22T10:00:00Z",
    intendedUse: .labOnly,
    networkSnapshotID: osrmSnapshotID,
    providerDatasetID: osrmDatasetID,
    engineBuild: SurfaceRoutingEngineBuild(
      id: "test.build.osrm",
      providerID: "osrm",
      providerVersion: "26.7.3",
      containerImage: "ghcr.io/project-osrm/osrm-backend:26.7.3",
      containerDigest: "sha256:\(sha256)"
    ),
    sources: [
      SurfaceRoutingBuildSource(
        id: "test.source.osrm",
        roles: [.roadNetwork],
        snapshotAt: "2026-07-21T19:03:43Z",
        uri: "https://example.invalid/osrm.osm.pbf",
        sha256: sha256,
        byteCount: 100,
        licence: "TEST-ONLY",
        attribution: "Synthetic test data"
      )
    ],
    artifacts: [
      SurfaceRoutingBuildArtifact(
        id: "test.artifact.osrm",
        role: .routingTiles,
        relativePath: "artifacts/osrm",
        format: "osrm-mld",
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

private func makeOSRMGraph() -> SurfaceRoadGraphSnapshot {
  SurfaceRoadGraphSnapshot(
    networkSnapshotID: osrmSnapshotID,
    provenance: SurfaceRoadGraphProvenance(
      source: "Synthetic",
      sourceSnapshotAt: "2026-07-21T19:03:43Z",
      sourceDatasetID: osrmDatasetID,
      sourceURI: "https://example.invalid/osrm-normalizer",
      licence: "TEST-ONLY",
      attribution: "Synthetic test data"
    ),
    edges: [
      makeOSRMEdge(id: "test.edge.1", from: 1, to: 2, coordinateIndex: 0),
      makeOSRMEdge(id: "test.edge.2", from: 2, to: 3, coordinateIndex: 1),
    ]
  )
}

private func makeOSRMEdge(
  id: String,
  from: Int64,
  to: Int64,
  coordinateIndex: Int
) -> SurfaceRoadEdge {
  SurfaceRoadEdge(
    id: id,
    fromNodeID: "osm.node.\(from)",
    toNodeID: "osm.node.\(to)",
    kind: .ordinaryRoad,
    coordinates: Array(osrmCoordinates[coordinateIndex...(coordinateIndex + 1)]),
    sourceOSMWayID: Int64(coordinateIndex + 42),
    sourceOSMSegmentIndex: 0,
    sourceOSMDirection: .forward
  )
}

private func makeOSRMFixture() -> EntranceProbeFixture {
  EntranceProbeFixture(
    schemaVersion: "1.0",
    id: "test.fixture.osrm-normalizer",
    networkSnapshotID: osrmSnapshotID,
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
      coordinate: osrmCoordinates[2],
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
        coordinate: osrmCoordinates[0],
        notes: "Synthetic OSRM route origin."
      )
    ]
  )
}

private actor StubOSRMTransport: OSRMHTTPTransport {
  private var responses: [OSRMHTTPResponse]
  private var requests: [OSRMHTTPRequest] = []

  init(responses: [OSRMHTTPResponse]) {
    self.responses = responses
  }

  func get(_ request: OSRMHTTPRequest) async throws -> OSRMHTTPResponse {
    requests.append(request)
    guard !responses.isEmpty else {
      throw OSRMHTTPTransportFailure.invalidResponse
    }
    return responses.removeFirst()
  }

  func recordedRequests() -> [OSRMHTTPRequest] {
    requests
  }
}
