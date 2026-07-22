import KaidoSurfaceRouting
import Testing

@Test("A complete surface-routing build manifest binds to one Kaido graph")
func releaseBuildManifestPassesValidation() {
  let report = SurfaceRoutingBuildManifestValidator.validate(
    makeBuildManifest(),
    graph: makeBuildManifestGraph(),
    profile: .releaseCandidate
  )

  #expect(report.isValid)
  #expect(report.issues.isEmpty)
}

@Test("A lab build remains structurally honest but cannot pass the release profile")
func labBuildManifestCannotPassReleaseValidation() {
  let manifest = makeBuildManifest(
    intendedUse: .labOnly,
    sources: [makeBuildSource(id: "road", roles: [.roadNetwork])],
    artifacts: [
      makeBuildArtifact(id: "tiles", role: .routingTiles),
      makeBuildArtifact(id: "graph", role: .kaidoDirectedGraph),
    ],
    capabilities: SurfaceRoutingBuildCapabilities(
      includesAdministrativeData: false,
      includesTimeZoneData: false,
      keepsAllOSMNodeIDs: true
    ),
    adminVerifications: [],
    releaseBlockers: ["Complete Japanese administrative context is absent."]
  )

  let structural = SurfaceRoutingBuildManifestValidator.validate(
    manifest,
    graph: makeBuildManifestGraph(),
    profile: .structural
  )
  let release = SurfaceRoutingBuildManifestValidator.validate(
    manifest,
    graph: makeBuildManifestGraph(),
    profile: .releaseCandidate
  )

  #expect(structural.isValid)
  #expect(!release.isValid)
  #expect(release.issues.contains { $0.code == .wrongIntendedUse })
  #expect(release.issues.contains { $0.code == .missingSourceRole })
  #expect(release.issues.contains { $0.code == .missingArtifactRole })
  #expect(release.issues.contains { $0.code == .missingCapability })
  #expect(release.issues.contains { $0.code == .missingTokyoLeftDrivingVerification })
  #expect(release.issues.contains { $0.code == .releaseBlocker })
}

@Test("Manifest validation rejects cross-snapshot identity and malformed build records")
func buildManifestRejectsInvalidIdentityAndRecords() {
  let badSource = SurfaceRoutingBuildSource(
    id: "road",
    roles: [.roadNetwork, .roadNetwork],
    snapshotAt: "2026-07-21",
    uri: "",
    sha256: "not-a-checksum",
    byteCount: 0,
    licence: "",
    attribution: ""
  )
  let badArtifact = SurfaceRoutingBuildArtifact(
    id: "tiles",
    role: .routingTiles,
    relativePath: "../tiles.tar",
    format: "",
    sha256: "bad",
    byteCount: -1
  )
  let manifest = makeBuildManifest(
    networkSnapshotID: "other.snapshot",
    providerDatasetID: "other.dataset",
    sources: [badSource, badSource],
    artifacts: [badArtifact, badArtifact],
    capabilities: SurfaceRoutingBuildCapabilities(
      includesAdministrativeData: false,
      includesTimeZoneData: false,
      keepsAllOSMNodeIDs: false
    )
  )

  let report = SurfaceRoutingBuildManifestValidator.validate(
    manifest,
    graph: makeBuildManifestGraph(),
    profile: .structural
  )
  let codes = Set(report.issues.map(\.code))

  #expect(!report.isValid)
  #expect(codes.contains(.graphSnapshotMismatch))
  #expect(codes.contains(.providerDatasetMismatch))
  #expect(codes.contains(.duplicateSourceID))
  #expect(codes.contains(.duplicateArtifactID))
  #expect(codes.contains(.duplicateArtifactRole))
  #expect(codes.contains(.invalidSource))
  #expect(codes.contains(.invalidArtifact))
  #expect(codes.contains(.invalidTimestamp))
  #expect(codes.contains(.invalidChecksum))
  #expect(codes.contains(.invalidByteCount))
  #expect(codes.contains(.invalidRelativePath))
  #expect(codes.contains(.missingArtifactRole))
  #expect(codes.contains(.missingCapability))
}

@Test("A way point-pair identity build need not claim retained OSM nodes")
func wayPointIdentityBuildPassesStructuralValidation() {
  let manifest = makeBuildManifest(
    intendedUse: .labOnly,
    sources: [makeBuildSource(id: "road", roles: [.roadNetwork])],
    artifacts: [
      makeBuildArtifact(id: "tiles", role: .routingTiles),
      makeBuildArtifact(id: "graph", role: .kaidoDirectedGraph),
    ],
    capabilities: SurfaceRoutingBuildCapabilities(
      includesAdministrativeData: false,
      includesTimeZoneData: false,
      keepsAllOSMNodeIDs: false,
      selectedPathIdentity: .osmWayPointPairs
    ),
    adminVerifications: [],
    releaseBlockers: ["Synthetic point-pair identity build."]
  )

  let report = SurfaceRoutingBuildManifestValidator.validate(
    manifest,
    graph: makeBuildManifestGraph(),
    profile: .structural
  )

  #expect(report.isValid)
}

private let buildManifestSnapshotID = "test.snapshot.surface-build-v1"
private let buildManifestDatasetID = "2026072101"
private let validSHA256 = String(repeating: "a", count: 64)

private func makeBuildManifest(
  intendedUse: SurfaceRoutingBuildIntendedUse = .releaseCandidate,
  networkSnapshotID: String = buildManifestSnapshotID,
  providerDatasetID: String = buildManifestDatasetID,
  sources: [SurfaceRoutingBuildSource]? = nil,
  artifacts: [SurfaceRoutingBuildArtifact]? = nil,
  capabilities: SurfaceRoutingBuildCapabilities = SurfaceRoutingBuildCapabilities(
    includesAdministrativeData: true,
    includesTimeZoneData: true,
    keepsAllOSMNodeIDs: true
  ),
  adminVerifications: [SurfaceRoutingAdminVerification]? = nil,
  releaseBlockers: [String] = []
) -> SurfaceRoutingBuildManifest {
  SurfaceRoutingBuildManifest(
    id: "test.valhalla.20260721",
    createdAt: "2026-07-22T10:00:00Z",
    intendedUse: intendedUse,
    networkSnapshotID: networkSnapshotID,
    providerDatasetID: providerDatasetID,
    engineBuild: SurfaceRoutingEngineBuild(
      id: "valhalla-3.8.2-test",
      providerID: "valhalla",
      providerVersion: "3.8.2",
      containerImage: "ghcr.io/valhalla/valhalla:3.8.2",
      containerDigest: "sha256:\(validSHA256)"
    ),
    sources: sources ?? [
      makeBuildSource(id: "kanto", roles: [.roadNetwork]),
      makeBuildSource(id: "japan", roles: [.administration, .timeZone]),
    ],
    artifacts: artifacts
      ?? SurfaceRoutingBuildArtifactRole.allCases.enumerated().map {
        makeBuildArtifact(id: "artifact-\($0.offset)", role: $0.element)
      },
    capabilities: capabilities,
    adminVerifications: adminVerifications ?? [
      SurfaceRoutingAdminVerification(
        id: "tokyo-left-driving",
        coordinate: SurfaceCoordinate(latitude: 35.6895, longitude: 139.6917),
        expectedRegionCode: "JP-13",
        observedCountryCode: "JP",
        observedStateCode: "13",
        driveOnRight: false,
        checkedAt: "2026-07-22T10:01:00Z",
        evidenceSHA256: validSHA256
      )
    ],
    releaseBlockers: releaseBlockers
  )
}

private func makeBuildSource(
  id: String,
  roles: [SurfaceRoutingBuildSourceRole]
) -> SurfaceRoutingBuildSource {
  SurfaceRoutingBuildSource(
    id: id,
    roles: roles,
    snapshotAt: "2026-07-21T19:03:43Z",
    uri: "https://example.invalid/\(id).osm.pbf",
    sha256: validSHA256,
    byteCount: 100,
    licence: "ODbL-1.0",
    attribution: "OpenStreetMap contributors"
  )
}

private func makeBuildArtifact(
  id: String,
  role: SurfaceRoutingBuildArtifactRole
) -> SurfaceRoutingBuildArtifact {
  SurfaceRoutingBuildArtifact(
    id: id,
    role: role,
    relativePath: "artifacts/\(id).bin",
    format: "test",
    sha256: validSHA256,
    byteCount: 100
  )
}

private func makeBuildManifestGraph() -> SurfaceRoadGraphSnapshot {
  SurfaceRoadGraphSnapshot(
    networkSnapshotID: buildManifestSnapshotID,
    provenance: SurfaceRoadGraphProvenance(
      source: "Synthetic",
      sourceSnapshotAt: "2026-07-21T19:03:43Z",
      sourceDatasetID: buildManifestDatasetID,
      sourceURI: "https://example.invalid/graph",
      licence: "TEST-ONLY",
      attribution: "Synthetic test data"
    ),
    edges: [
      SurfaceRoadEdge(
        id: "edge.1",
        fromNodeID: "node.1",
        toNodeID: "node.2",
        kind: .ordinaryRoad,
        coordinates: [
          SurfaceCoordinate(latitude: 35.68, longitude: 139.69),
          SurfaceCoordinate(latitude: 35.69, longitude: 139.70),
        ]
      )
    ]
  )
}
