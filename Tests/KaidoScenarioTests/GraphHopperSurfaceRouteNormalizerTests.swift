import Foundation
import KaidoSurfaceRouting
import Testing

@Test("GraphHopper response normalizes complete timestamp-bound path details")
func graphHopperResponseNormalizesPathDetails() throws {
  let normalized = try makeGraphHopperNormalizer().normalize(
    infoResponseData: makeGraphHopperInfoResponse(),
    routeResponseData: makeGraphHopperRouteResponse(),
    candidateID: "test.candidate.graphhopper"
  )

  #expect(normalized.candidateWithoutSelectedPathEvidence.coordinates == graphHopperCoordinates)
  #expect(normalized.candidateWithoutSelectedPathEvidence.distanceMeters == 200)
  #expect(normalized.candidateWithoutSelectedPathEvidence.expectedTravelTimeSeconds == 20)
  #expect(normalized.candidateWithoutSelectedPathEvidence.selectedPathEvidence == nil)
  #expect(normalized.translationRequest.providerDatasetID == graphHopperDatasetID)
  #expect(
    normalized.translationRequest.segmentIdentities == [
      OSMWayPointPathSegmentIdentity(providerDirectedEdgeKey: 20, osmWayID: 42),
      OSMWayPointPathSegmentIdentity(providerDirectedEdgeKey: 20, osmWayID: 42),
    ]
  )
}

@Test("GraphHopper normalized path translates through the shared hard gates")
func graphHopperResponseToHardGateChain() async throws {
  let graph = makeGraphHopperGraph()
  let normalized = try makeGraphHopperNormalizer().normalize(
    infoResponseData: makeGraphHopperInfoResponse(),
    routeResponseData: makeGraphHopperRouteResponse(),
    candidateID: "test.candidate.graphhopper"
  )
  let candidate = try normalized.translatedCandidate(graph: graph)
  let fixture = makeGraphHopperFixture()
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
    expectedProviderID: graphHopperProviderID
  )

  #expect(candidate.selectedPathEvidence?.directedEdgeIDs == ["test.gh.edge.1", "test.gh.edge.2"])
  #expect(inspection.geometryBindingIsUnambiguous == true)
  #expect(evaluation.isAccepted)
}

@Test("GraphHopper normalization rejects build version and capability drift")
func graphHopperNormalizationRejectsBuildDrift() {
  #expect(
    throws: GraphHopperSurfaceRouteNormalizationError.providerVersionMismatch(
      expected: graphHopperVersion,
      received: "12.0"
    )
  ) {
    try makeGraphHopperNormalizer().normalize(
      infoResponseData: makeGraphHopperInfoResponse(version: "12.0"),
      routeResponseData: makeGraphHopperRouteResponse(),
      candidateID: "test.candidate.graphhopper"
    )
  }
  #expect(
    throws: GraphHopperSurfaceRouteNormalizationError.encodedValueUnavailable("osm_way_id")
  ) {
    try makeGraphHopperNormalizer().normalize(
      infoResponseData: makeGraphHopperInfoResponse(encodedValueNames: [
        "country", "road_class", "toll",
      ]),
      routeResponseData: makeGraphHopperRouteResponse(),
      candidateID: "test.candidate.graphhopper"
    )
  }
}

@Test("GraphHopper normalization rejects epoch and drifting road timestamps")
func graphHopperNormalizationRejectsTimestampDrift() {
  #expect(
    throws: GraphHopperSurfaceRouteNormalizationError.invalidDataTimestamp(
      "1970-01-01T00:00:00Z"
    )
  ) {
    try makeGraphHopperNormalizer().normalize(
      infoResponseData: makeGraphHopperInfoResponse(timestamp: "1970-01-01T00:00:00Z"),
      routeResponseData: makeGraphHopperRouteResponse(),
      candidateID: "test.candidate.graphhopper"
    )
  }
  #expect(
    throws: GraphHopperSurfaceRouteNormalizationError.dataTimestampMismatch(
      expected: graphHopperTimestamp,
      received: "2026-07-21T19:03:44Z"
    )
  ) {
    try makeGraphHopperNormalizer().normalize(
      infoResponseData: makeGraphHopperInfoResponse(),
      routeResponseData: makeGraphHopperRouteResponse(timestamp: "2026-07-21T19:03:44Z"),
      candidateID: "test.candidate.graphhopper"
    )
  }
}

@Test("GraphHopper normalization rejects path-detail gaps and non-Japan segments")
func graphHopperNormalizationRejectsInvalidDetails() {
  #expect(
    throws: GraphHopperSurfaceRouteNormalizationError.invalidPathDetail(name: "edge_key")
  ) {
    try makeGraphHopperNormalizer().normalize(
      infoResponseData: makeGraphHopperInfoResponse(),
      routeResponseData: makeGraphHopperRouteResponse(
        edgeKeyDetails: [[0, 1, 20]]
      ),
      candidateID: "test.candidate.graphhopper"
    )
  }
  #expect(
    throws: GraphHopperSurfaceRouteNormalizationError.unsupportedCountry(
      segmentIndex: 0,
      received: "USA"
    )
  ) {
    try makeGraphHopperNormalizer().normalize(
      infoResponseData: makeGraphHopperInfoResponse(),
      routeResponseData: makeGraphHopperRouteResponse(
        countryDetails: [[0, 2, "USA"]]
      ),
      candidateID: "test.candidate.graphhopper"
    )
  }
}

@Test("Bounded GraphHopper provider verifies info then translates one route")
func graphHopperProviderExecutesBoundedProtocol() async throws {
  let transport = StubGraphHopperTransport(
    responses: [
      GraphHopperHTTPResponse(statusCode: 200, body: makeGraphHopperInfoResponse()),
      GraphHopperHTTPResponse(statusCode: 200, body: makeGraphHopperRouteResponse()),
    ]
  )
  let provider = try makeGraphHopperProvider(transport: transport)
  let request = try makeGraphHopperFixture().makeRequest(originID: "test.origin.same-side")

  let response = await provider.routes(for: request)
  guard case .success(let candidates) = response else {
    Issue.record("Expected one translated GraphHopper candidate")
    return
  }
  let requests = await transport.recordedRequests()
  let routeRequest = requests[1]

  #expect(candidates.count == 1)
  #expect(
    candidates[0].selectedPathEvidence?.directedEdgeIDs == [
      "test.gh.edge.1", "test.gh.edge.2",
    ])
  #expect(requests.map(\.path) == ["/info", "/route"])
  #expect(
    routeRequest.queryItems.filter { $0.name == "point" }.map(\.value) == [
      "35.0,139.0", "35.0,139.002",
    ])
  #expect(
    routeRequest.queryItems.filter { $0.name == "heading" }.map(\.value) == [
      "NaN", "90.0",
    ])
  #expect(
    routeRequest.queryItems.filter { $0.name == "details" }.map(\.value) == [
      "edge_key", "osm_way_id", "country", "toll", "road_class",
    ])
  #expect(routeRequest.queryItems.contains(.init(name: "way_point_max_distance", value: "0")))
  #expect(routeRequest.queryItems.contains(.init(name: "profile", value: "car_surface")))
}

@Test("Bounded GraphHopper provider rejects terminal OSM way drift")
func graphHopperProviderRejectsTerminalWayDrift() async throws {
  let transport = StubGraphHopperTransport(
    responses: [
      GraphHopperHTTPResponse(statusCode: 200, body: makeGraphHopperInfoResponse()),
      GraphHopperHTTPResponse(
        statusCode: 200,
        body: makeGraphHopperRouteResponse(osmWayDetails: [[0, 2, 99]])
      ),
    ]
  )
  let provider = try makeGraphHopperProvider(transport: transport)
  let request = try makeGraphHopperFixture().makeRequest(originID: "test.origin.same-side")

  let response = await provider.routes(for: request)
  guard case .failure(let failure) = response else {
    Issue.record("Expected terminal OSM way drift to fail closed")
    return
  }

  #expect(failure.kind == .server)
  #expect(failure.providerErrorCode == "TERMINAL_OSM_WAY_REJECTED")
  #expect(await transport.recordedRequests().count == 2)
}

@Test("Bounded GraphHopper provider discloses no route")
func graphHopperProviderDisclosesNoRoute() async throws {
  let noRoute = try JSONSerialization.data(
    withJSONObject: ["message": "Connection between locations not found"],
    options: [.sortedKeys]
  )
  let transport = StubGraphHopperTransport(
    responses: [
      GraphHopperHTTPResponse(statusCode: 200, body: makeGraphHopperInfoResponse()),
      GraphHopperHTTPResponse(statusCode: 400, body: noRoute),
    ]
  )
  let provider = try makeGraphHopperProvider(transport: transport)
  let request = try makeGraphHopperFixture().makeRequest(originID: "test.origin.same-side")

  let response = await provider.routes(for: request)
  guard case .failure(let failure) = response else {
    Issue.record("Expected an explicit GraphHopper no-route failure")
    return
  }

  #expect(failure.kind == .noRoute)
  #expect(failure.providerErrorCode == "GRAPH_HOPPER_NO_ROUTE")
}

private let graphHopperProviderID = "test.graphhopper.local"
private let graphHopperDatasetID = "test.dataset.graphhopper.20260721"
private let graphHopperSnapshotID = "test.snapshot.graphhopper-normalizer-v1"
private let graphHopperVersion = "11.0"
private let graphHopperTimestamp = "2026-07-21T19:03:43Z"
private let graphHopperCoordinates = [
  SurfaceCoordinate(latitude: 35, longitude: 139),
  SurfaceCoordinate(latitude: 35, longitude: 139.001),
  SurfaceCoordinate(latitude: 35, longitude: 139.002),
]

private func makeGraphHopperNormalizer() -> GraphHopperSurfaceRouteNormalizer {
  GraphHopperSurfaceRouteNormalizer(
    providerID: graphHopperProviderID,
    providerDatasetID: graphHopperDatasetID,
    expectedProviderVersion: graphHopperVersion,
    expectedRoadDataTimestamp: graphHopperTimestamp,
    expectedProfileName: "car_surface"
  )
}

private func makeGraphHopperProvider(
  transport: any GraphHopperHTTPTransport
) throws -> GraphHopperSurfaceRouteProvider {
  try GraphHopperSurfaceRouteProvider(
    graph: makeGraphHopperGraph(),
    manifest: makeGraphHopperProviderManifest(),
    configuration: GraphHopperSurfaceProviderConfiguration(
      candidateProviderID: graphHopperProviderID,
      adapterVersion: "test.1",
      dataReviewStatus: .derivedFixtureReviewed,
      manifestValidationProfile: .structural,
      approachBindings: [
        GraphHopperApproachIdentityBinding(
          anchorID: "test.anchor.graphhopper",
          directedSurfaceEdgeID: "test.gh.edge.2",
          terminalOSMWayID: 42
        )
      ]
    ),
    transport: transport
  )
}

private func makeGraphHopperProviderManifest() -> SurfaceRoutingBuildManifest {
  let sha256 = String(repeating: "d", count: 64)
  return SurfaceRoutingBuildManifest(
    id: "test.manifest.graphhopper-provider",
    createdAt: "2026-07-22T10:00:00Z",
    intendedUse: .labOnly,
    networkSnapshotID: graphHopperSnapshotID,
    providerDatasetID: graphHopperDatasetID,
    engineBuild: SurfaceRoutingEngineBuild(
      id: "test.build.graphhopper",
      providerID: "graphhopper",
      providerVersion: graphHopperVersion,
      containerImage: "eclipse-temurin:25-jre",
      containerDigest: "sha256:\(sha256)"
    ),
    sources: [
      SurfaceRoutingBuildSource(
        id: "test.source.graphhopper",
        roles: [.roadNetwork],
        snapshotAt: graphHopperTimestamp,
        uri: "https://example.invalid/graphhopper.osm.pbf",
        sha256: sha256,
        byteCount: 100,
        licence: "TEST-ONLY",
        attribution: "Synthetic test data"
      )
    ],
    artifacts: [
      makeGraphHopperArtifact(id: "config", role: .providerConfiguration),
      makeGraphHopperArtifact(id: "jar", role: .engineBinary),
      makeGraphHopperArtifact(id: "cache", role: .routingTiles),
      makeGraphHopperArtifact(id: "graph", role: .kaidoDirectedGraph),
    ],
    capabilities: SurfaceRoutingBuildCapabilities(
      includesAdministrativeData: false,
      includesTimeZoneData: false,
      keepsAllOSMNodeIDs: false,
      selectedPathIdentity: .osmWayPointPairs
    ),
    adminVerifications: [],
    releaseBlockers: ["Synthetic test build."]
  )
}

private func makeGraphHopperArtifact(
  id: String,
  role: SurfaceRoutingBuildArtifactRole
) -> SurfaceRoutingBuildArtifact {
  SurfaceRoutingBuildArtifact(
    id: "test.artifact.graphhopper.\(id)",
    role: role,
    relativePath: "artifacts/\(id).bin",
    format: "test",
    sha256: String(repeating: "d", count: 64),
    byteCount: 100
  )
}

private func makeGraphHopperInfoResponse(
  version: String = graphHopperVersion,
  timestamp: String = graphHopperTimestamp,
  encodedValueNames: [String] = ["country", "osm_way_id", "road_class", "toll"]
) -> Data {
  let encodedValues = Dictionary(uniqueKeysWithValues: encodedValueNames.map { ($0, ["test"]) })
  let object: [String: Any] = [
    "profiles": [["name": "car_surface"]],
    "version": version,
    "encoded_values": encodedValues,
    "data_date": timestamp,
  ]
  return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func makeGraphHopperRouteResponse(
  timestamp: String = graphHopperTimestamp,
  edgeKeyDetails: [[Any]] = [[0, 2, 20]],
  osmWayDetails: [[Any]] = [[0, 2, 42]],
  countryDetails: [[Any]] = [[0, 2, "JPN"]]
) -> Data {
  let object: [String: Any] = [
    "info": ["road_data_timestamp": timestamp],
    "paths": [
      [
        "distance": 200.0,
        "time": 20_000.0,
        "points_encoded": false,
        "points": [
          "type": "LineString",
          "coordinates": graphHopperCoordinates.map { [$0.longitude, $0.latitude] },
        ],
        "instructions": [
          [
            "text": "公園通りまで進む",
            "distance": 200.0,
            "time": 20_000.0,
            "interval": [0, 2],
            "street_name": "公園通り",
            "street_ref": "副12",
          ],
          [
            "text": "目標達成",
            "distance": 0.0,
            "time": 0.0,
            "interval": [2, 2],
            "street_name": "",
          ],
        ],
        "details": [
          "edge_key": edgeKeyDetails,
          "osm_way_id": osmWayDetails,
          "country": countryDetails,
        ],
      ]
    ],
  ]
  return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func makeGraphHopperGraph() -> SurfaceRoadGraphSnapshot {
  SurfaceRoadGraphSnapshot(
    networkSnapshotID: graphHopperSnapshotID,
    provenance: SurfaceRoadGraphProvenance(
      source: "Synthetic",
      sourceSnapshotAt: graphHopperTimestamp,
      sourceDatasetID: graphHopperDatasetID,
      sourceURI: "https://example.invalid/graphhopper-normalizer",
      licence: "TEST-ONLY",
      attribution: "Synthetic test data"
    ),
    edges: [
      makeGraphHopperEdge(id: "test.gh.edge.1", from: 1, to: 2, coordinateIndex: 0),
      makeGraphHopperEdge(id: "test.gh.edge.2", from: 2, to: 3, coordinateIndex: 1),
    ]
  )
}

private func makeGraphHopperEdge(
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
    coordinates: Array(graphHopperCoordinates[coordinateIndex...(coordinateIndex + 1)]),
    sourceOSMWayID: 42,
    sourceOSMSegmentIndex: coordinateIndex,
    sourceOSMDirection: .forward
  )
}

private func makeGraphHopperFixture() -> EntranceProbeFixture {
  EntranceProbeFixture(
    schemaVersion: "1.0",
    id: "test.fixture.graphhopper-normalizer",
    networkSnapshotID: graphHopperSnapshotID,
    evidence: ProbeEvidence(
      classification: .synthetic,
      checkedAt: "2026-07-22T10:00:00Z",
      sources: [],
      limitations: [],
      releaseBlockers: ["Synthetic test fixture."]
    ),
    entrance: ProbeEntranceFacility(
      facilityID: "test.entrance.graphhopper",
      accessComplexID: "test.access.graphhopper",
      targetCarriagewayID: "test.carriageway.graphhopper",
      targetDirection: "EAST"
    ),
    approachAnchor: DirectedApproachAnchor(
      id: "test.anchor.graphhopper",
      coordinate: graphHopperCoordinates[2],
      directedSurfaceEdgeID: "test.gh.edge.2",
      expectedBearingDegrees: 90,
      bearingToleranceDegrees: 10,
      maxTerminalDistanceMeters: 10
    ),
    entryTransition: ProbeEntryTransition(
      directedEdgeIDs: ["test.transition.graphhopper"],
      firstRouteOccurrenceID: "test.join.graphhopper"
    ),
    journeyCompatibility: ProbeJourneyCompatibility(
      allowedJoinOccurrenceIDs: ["test.join.graphhopper"],
      finishPolicies: [.fixedExit],
      compatibleExitFacilityIDs: ["test.exit.graphhopper"]
    ),
    prohibitions: ProbeProhibitions(
      forbiddenEarlyExpresswayEdgeIDs: [],
      forbiddenTollDomainIDs: ["test.external-toll"]
    ),
    origins: [
      ProbeOrigin(
        id: "test.origin.same-side",
        kind: .sameSide,
        coordinate: graphHopperCoordinates[0],
        notes: "Synthetic GraphHopper route origin."
      )
    ]
  )
}

private actor StubGraphHopperTransport: GraphHopperHTTPTransport {
  private var responses: [GraphHopperHTTPResponse]
  private var requests: [GraphHopperHTTPRequest] = []

  init(responses: [GraphHopperHTTPResponse]) {
    self.responses = responses
  }

  func get(_ request: GraphHopperHTTPRequest) async throws -> GraphHopperHTTPResponse {
    requests.append(request)
    guard !responses.isEmpty else {
      throw GraphHopperHTTPTransportFailure.invalidResponse
    }
    return responses.removeFirst()
  }

  func recordedRequests() -> [GraphHopperHTTPRequest] {
    requests
  }
}
