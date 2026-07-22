import Foundation
import KaidoAppleAdapters
import KaidoNavigation
import KaidoSurfaceRouting
import Testing

@Test("Valhalla Meili oracle sends bounded map_snap and evaluates translated edges")
func valhallaMatcherReplayOracleExecutesBoundedProtocol() async throws {
  let transport = MatcherReplayValhallaTransport(
    response: ValhallaHTTPResponse(statusCode: 200, body: makeMatcherReplayResponse())
  )
  let oracle = try ValhallaMatcherReplayOracle(
    graph: makeMatcherReplayGraph(),
    manifest: makeMatcherReplayManifest(),
    transport: transport
  )

  let report = try await oracle.run(fixture: makeMatcherReplayFixture())
  let request = try #require(await transport.recordedRequest())
  let json = try #require(
    JSONSerialization.jsonObject(with: request.body) as? [String: Any]
  )

  #expect(request.action == .traceAttributes)
  #expect(json["shape_match"] as? String == "map_snap")
  #expect(json["costing"] as? String == "auto")
  let shape = try #require(json["shape"] as? [[String: Any]])
  #expect(shape.map { ($0["time"] as? NSNumber)?.doubleValue } == [0, 1])
  let traceOptions = try #require(json["trace_options"] as? [String: Any])
  #expect((traceOptions["gps_accuracy"] as? NSNumber)?.doubleValue == 8)
  #expect((traceOptions["search_radius"] as? NSNumber)?.doubleValue == 11)
  #expect((traceOptions["interpolation_distance"] as? NSNumber)?.doubleValue == 0)
  let filters = try #require(json["filters"] as? [String: Any])
  let attributes = try #require(filters["attributes"] as? [String])
  #expect(attributes.contains("edge.begin_osm_node_id"))
  #expect(attributes.contains("edge.end_osm_node_id"))
  #expect(attributes.contains("matched.distance_from_trace_point"))

  #expect(report.algorithmID == "valhalla-meili-map-snap-v1")
  #expect(report.metrics.edgeTop1CorrectCount == 2)
  #expect(report.metrics.occurrenceTruthCount == 2)
  #expect(report.metrics.occurrenceCorrectCount == 0)
  #expect(report.safetyFailures == [.routeOccurrenceUnavailable])
  #expect(report.expectedSafetyFailures == nil)
  #expect(report.expectationMatched == nil)
  #expect(report.estimates.allSatisfy { $0.confidence == .low })
}

@Test("Valhalla Meili oracle refuses reordered observation time")
func valhallaMatcherReplayOracleRejectsReorderedTime() async throws {
  let transport = MatcherReplayValhallaTransport(
    response: ValhallaHTTPResponse(statusCode: 200, body: makeMatcherReplayResponse())
  )
  let oracle = try ValhallaMatcherReplayOracle(
    graph: makeMatcherReplayGraph(),
    manifest: makeMatcherReplayManifest(),
    transport: transport
  )
  let fixture = makeMatcherReplayFixture(
    observations: [
      makeMatcherObservation(id: "observation.late-first", observedAt: 1_000, receivedAt: 1_000),
      makeMatcherObservation(id: "observation.older-later", observedAt: 0, receivedAt: 2_000),
    ],
    intervals: [
      MatcherGroundTruthInterval(
        startMilliseconds: 0,
        endMilliseconds: 0,
        directedEdgeID: "test.edge.1-2",
        occurrenceID: "test.occurrence.1-2",
        classification: .onRoute
      ),
      MatcherGroundTruthInterval(
        startMilliseconds: 1_000,
        endMilliseconds: 1_000,
        directedEdgeID: "test.edge.2-3",
        occurrenceID: "test.occurrence.2-3",
        classification: .onRoute
      ),
    ]
  )

  do {
    _ = try await oracle.run(fixture: fixture)
    Issue.record("Expected reordered observation time to be rejected")
  } catch {
    #expect(error as? ValhallaMatcherReplayOracleError == .nonIncreasingObservationTime)
  }
  #expect(await transport.recordedRequest() == nil)
}

@Test("Valhalla Meili oracle requires retained OSM node identity")
func valhallaMatcherReplayOracleRequiresOSMNodes() {
  let transport = MatcherReplayValhallaTransport(
    response: ValhallaHTTPResponse(statusCode: 200, body: makeMatcherReplayResponse())
  )

  #expect(throws: ValhallaMatcherReplayOracleError.missingOSMNodeIdentity) {
    try ValhallaMatcherReplayOracle(
      graph: makeMatcherReplayGraph(),
      manifest: makeMatcherReplayManifest(keepsAllOSMNodeIDs: false),
      transport: transport
    )
  }
}

private actor MatcherReplayValhallaTransport: ValhallaHTTPTransport {
  struct Request: Equatable, Sendable {
    let action: ValhallaServiceAction
    let body: Data
  }

  private let response: ValhallaHTTPResponse
  private var request: Request?

  init(response: ValhallaHTTPResponse) {
    self.response = response
  }

  func post(
    action: ValhallaServiceAction,
    jsonBody: Data
  ) async throws -> ValhallaHTTPResponse {
    request = Request(action: action, body: jsonBody)
    return response
  }

  func recordedRequest() -> Request? {
    request
  }
}

private let matcherReplayDatasetID = "2026072101"
private let matcherReplaySnapshotID = "test.snapshot.matcher-oracle"

private func makeMatcherReplayFixture(
  observations: [MatcherReplayObservation]? = nil,
  intervals: [MatcherGroundTruthInterval]? = nil
) -> MatcherReplayFixture {
  MatcherReplayFixture(
    fixtureID: "synthetic.matcher.oracle",
    networkSnapshotID: matcherReplaySnapshotID,
    evidenceClassification: "SYNTHETIC",
    edges: [
      MatcherReplayEdge(
        id: "test.edge.1-2",
        coordinates: [
          MatcherCoordinate(latitude: 35, longitude: 139),
          MatcherCoordinate(latitude: 35, longitude: 139.0005),
        ]
      ),
      MatcherReplayEdge(
        id: "test.edge.2-3",
        coordinates: [
          MatcherCoordinate(latitude: 35, longitude: 139.0005),
          MatcherCoordinate(latitude: 35, longitude: 139.001),
        ]
      ),
    ],
    routeOccurrences: [
      MatcherRouteOccurrenceBinding(
        occurrenceID: "test.occurrence.1-2",
        index: 0,
        directedEdgeID: "test.edge.1-2"
      ),
      MatcherRouteOccurrenceBinding(
        occurrenceID: "test.occurrence.2-3",
        index: 1,
        directedEdgeID: "test.edge.2-3"
      ),
    ],
    initialOccurrenceID: "test.occurrence.1-2",
    observations: observations ?? [
      makeMatcherObservation(id: "observation.0", observedAt: 0, receivedAt: 0),
      makeMatcherObservation(id: "observation.1", observedAt: 1_000, receivedAt: 1_000),
    ],
    groundTruthIntervals: intervals ?? [
      MatcherGroundTruthInterval(
        startMilliseconds: 0,
        endMilliseconds: 0,
        directedEdgeID: "test.edge.1-2",
        occurrenceID: "test.occurrence.1-2",
        classification: .onRoute
      ),
      MatcherGroundTruthInterval(
        startMilliseconds: 1_000,
        endMilliseconds: 1_000,
        directedEdgeID: "test.edge.2-3",
        occurrenceID: "test.occurrence.2-3",
        classification: .onRoute
      ),
    ],
    expectedNegativeControlFailures: []
  )
}

private func makeMatcherObservation(
  id: String,
  observedAt: Int,
  receivedAt: Int
) -> MatcherReplayObservation {
  MatcherReplayObservation(
    id: id,
    observedAtMilliseconds: observedAt,
    receivedAtMilliseconds: receivedAt,
    coordinate: MatcherCoordinate(
      latitude: 35,
      longitude: observedAt == 0 ? 139.00025 : 139.00075
    ),
    horizontalAccuracyMeters: observedAt == 0 ? 5 : 8,
    courseDegrees: 90,
    speedMetersPerSecond: 12,
    source: .phone
  )
}

private func makeMatcherReplayGraph() -> SurfaceRoadGraphSnapshot {
  SurfaceRoadGraphSnapshot(
    networkSnapshotID: matcherReplaySnapshotID,
    provenance: SurfaceRoadGraphProvenance(
      source: "SYNTHETIC",
      sourceSnapshotAt: "2026-07-23T00:00:00Z",
      sourceDatasetID: matcherReplayDatasetID,
      sourceURI: "https://example.invalid/matcher-oracle",
      licence: "CC0-1.0",
      attribution: "Synthetic matcher oracle graph"
    ),
    edges: [
      SurfaceRoadEdge(
        id: "test.edge.1-2",
        fromNodeID: "osm.node.1",
        toNodeID: "osm.node.2",
        kind: .expressway,
        coordinates: [
          SurfaceCoordinate(latitude: 35, longitude: 139),
          SurfaceCoordinate(latitude: 35, longitude: 139.0005),
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
          SurfaceCoordinate(latitude: 35, longitude: 139.0005),
          SurfaceCoordinate(latitude: 35, longitude: 139.001),
        ],
        sourceOSMWayID: 42,
        sourceOSMSegmentIndex: 1,
        sourceOSMDirection: .forward
      ),
    ]
  )
}

private func makeMatcherReplayManifest(
  keepsAllOSMNodeIDs: Bool = true
) -> SurfaceRoutingBuildManifest {
  let sha256 = String(repeating: "b", count: 64)
  return SurfaceRoutingBuildManifest(
    id: "test.manifest.matcher-oracle",
    createdAt: "2026-07-23T00:00:00Z",
    intendedUse: .labOnly,
    networkSnapshotID: matcherReplaySnapshotID,
    providerDatasetID: matcherReplayDatasetID,
    engineBuild: SurfaceRoutingEngineBuild(
      id: "test.build.matcher-oracle",
      providerID: "valhalla",
      providerVersion: "3.8.2",
      containerImage: "ghcr.io/valhalla/valhalla:3.8.2",
      containerDigest: "sha256:\(sha256)"
    ),
    sources: [
      SurfaceRoutingBuildSource(
        id: "test.source.matcher-oracle",
        roles: [.roadNetwork],
        snapshotAt: "2026-07-23T00:00:00Z",
        uri: "https://example.invalid/matcher-oracle.osm.pbf",
        sha256: sha256,
        byteCount: 100,
        licence: "CC0-1.0",
        attribution: "Synthetic matcher oracle source"
      )
    ],
    artifacts: [
      SurfaceRoutingBuildArtifact(
        id: "test.artifact.matcher-oracle-tiles",
        role: .routingTiles,
        relativePath: "artifacts/tiles.tar",
        format: "tar",
        sha256: sha256,
        byteCount: 100
      ),
      SurfaceRoutingBuildArtifact(
        id: "test.artifact.matcher-oracle-graph",
        role: .kaidoDirectedGraph,
        relativePath: "artifacts/graph.json",
        format: "json",
        sha256: sha256,
        byteCount: 100
      ),
    ],
    capabilities: SurfaceRoutingBuildCapabilities(
      includesAdministrativeData: false,
      includesTimeZoneData: false,
      keepsAllOSMNodeIDs: keepsAllOSMNodeIDs,
      selectedPathIdentity: keepsAllOSMNodeIDs ? nil : .osmWayPointPairs
    ),
    adminVerifications: [],
    releaseBlockers: ["Synthetic test build."]
  )
}

private func makeMatcherReplayResponse() -> Data {
  Data(
    """
    {
      "osm_changeset": 2026072101,
      "edges": [
        { "id": 9001, "way_id": 42, "node_id": 1, "forward": true, "end_node": { "node_id": 3 } }
      ],
      "matched_points": [
        { "lat": 35.0, "lon": 139.00025, "type": "matched", "edge_index": 0, "distance_along_edge": 0.25, "distance_from_trace_point": 1.0 },
        { "lat": 35.0, "lon": 139.00075, "type": "matched", "edge_index": 0, "distance_along_edge": 0.75, "distance_from_trace_point": 1.0 }
      ]
    }
    """.utf8
  )
}
