import Foundation
import KaidoDomain
import KaidoNavigation
import Testing

@Test("Route Atlas release preserves repeated occurrences on one schematic segment")
func routeAtlasReleaseAcceptsCoherentRepeatedOccurrences() throws {
  let fixture = routeAtlasFixture()
  let release = try RouteAtlasRelease(
    networkSnapshot: fixture.networkSnapshot,
    routePlan: fixture.routePlan,
    sourceRegistry: fixture.sourceRegistry,
    topologySlice: fixture.topologySlice,
    definition: fixture.definition
  )

  #expect(release.definition.segments.count == 2)
  #expect(release.definition.occurrenceBindings.count == 3)
  #expect(
    release.definition.occurrenceBindings
      .filter { $0.segmentID == "test.segment.loop" }
      .map(\.occurrenceID)
      == ["test.occurrence.loop-1", "test.occurrence.loop-2"]
  )
}

@Test("Real K7 candidate remains blocked only by unreleased evidence")
func realK7RouteAtlasCandidateRemainsBlocked() throws {
  let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let artifactURL =
    repositoryRoot
    .appendingPathComponent("data/route-atlas/candidates", isDirectory: true)
    .appendingPathComponent(
      "k7-northwest-up-aoba-to-kohoku-candidate.json"
    )
  let artifact = try JSONDecoder().decode(
    RouteAtlasReleaseArtifact.self,
    from: Data(contentsOf: artifactURL)
  )

  do {
    _ = try RouteAtlasRelease(artifact: artifact)
    Issue.record("Expected OFFICIAL_CHECKED real data to remain blocked")
  } catch RouteAtlasReleaseError.invalid(let issues) {
    #expect(
      issues.map(\.code)
        == [
          "UNRELEASED_ATLAS_EVIDENCE",
          "UNRELEASED_ATLAS_TOPOLOGY_EVIDENCE",
        ]
    )
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("OSM-directed K7 candidate remains blocked only by unreleased evidence")
func osmDirectedK7RouteAtlasCandidateRemainsBlocked() throws {
  let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let artifactURL =
    repositoryRoot
    .appendingPathComponent("data/route-atlas/candidates", isDirectory: true)
    .appendingPathComponent(
      "k7-northwest-up-aoba-to-kohoku-osm-directed-candidate.json"
    )
  let artifact = try JSONDecoder().decode(
    RouteAtlasReleaseArtifact.self,
    from: Data(contentsOf: artifactURL)
  )

  #expect(artifact.routePlan.occurrences.count == 13)
  #expect(artifact.topologySlice.edges.count == 15)
  #expect(artifact.definition.segments.count == 15)

  do {
    _ = try RouteAtlasRelease(artifact: artifact)
    Issue.record("Expected OSM-derived candidate data to remain blocked")
  } catch RouteAtlasReleaseError.invalid(let issues) {
    #expect(
      issues.map(\.code)
        == [
          "UNRELEASED_ATLAS_EVIDENCE",
          "UNRELEASED_ATLAS_TOPOLOGY_EVIDENCE",
        ]
    )
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Route Atlas release rejects a schematic successor absent from topology")
func routeAtlasReleaseRejectsInventedConnection() {
  let fixture = routeAtlasFixture()
  let driftedSegments = fixture.definition.segments.map { segment in
    guard segment.id == "test.segment.loop" else { return segment }
    return RouteAtlasSegment(
      id: segment.id,
      topologyEdgeID: segment.topologyEdgeID,
      fromNodeID: segment.fromNodeID,
      toNodeID: segment.toNodeID,
      successorSegmentIDs: [
        "test.segment.turn",
        "test.segment.loop",
      ],
      points: segment.points
    )
  }
  let definition = routeAtlasDefinition(
    fixture: fixture,
    segments: driftedSegments
  )

  do {
    _ = try RouteAtlasRelease(
      networkSnapshot: fixture.networkSnapshot,
      routePlan: fixture.routePlan,
      sourceRegistry: fixture.sourceRegistry,
      topologySlice: fixture.topologySlice,
      definition: definition
    )
    Issue.record("Expected an invented visual connection to block atlas release")
  } catch RouteAtlasReleaseError.invalid(let issues) {
    #expect(issues.contains(.segmentSuccessorMismatch("test.segment.loop")))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Route Atlas release requires complete topology and occurrence coverage")
func routeAtlasReleaseRejectsMissingCoverage() {
  let fixture = routeAtlasFixture()
  let definition = routeAtlasDefinition(
    fixture: fixture,
    segments: fixture.definition.segments.filter {
      $0.id != "test.segment.turn"
    },
    occurrenceBindings: fixture.definition.occurrenceBindings.filter {
      $0.occurrenceID != "test.occurrence.turn"
    }
  )

  do {
    _ = try RouteAtlasRelease(
      networkSnapshot: fixture.networkSnapshot,
      routePlan: fixture.routePlan,
      sourceRegistry: fixture.sourceRegistry,
      topologySlice: fixture.topologySlice,
      definition: definition
    )
    Issue.record("Expected missing topology and route coverage to block release")
  } catch RouteAtlasReleaseError.invalid(let issues) {
    #expect(issues.contains(.missingTopologyEdge("test.topology-edge.turn")))
    #expect(issues.contains(.missingOccurrenceBinding("test.occurrence.turn")))
    #expect(issues.contains(.segmentSuccessorMismatch("test.segment.loop")))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Route Atlas release rejects snapshot drift and unreleased layout evidence")
func routeAtlasReleaseRejectsSnapshotAndEvidenceDrift() {
  let fixture = routeAtlasFixture()
  let definition = RouteAtlasDefinition(
    id: fixture.definition.id,
    networkSnapshotID: "test.snapshot.other",
    routePlanID: fixture.definition.routePlanID,
    topologySliceID: fixture.definition.topologySliceID,
    nodes: fixture.definition.nodes,
    segments: fixture.definition.segments,
    occurrenceBindings: fixture.definition.occurrenceBindings,
    evidence: RouteAtlasEvidence(
      state: .officialChecked,
      checkedAt: fixture.definition.evidence.checkedAt,
      sourceReferenceIDs: fixture.definition.evidence.sourceReferenceIDs
    )
  )

  do {
    _ = try RouteAtlasRelease(
      networkSnapshot: fixture.networkSnapshot,
      routePlan: fixture.routePlan,
      sourceRegistry: fixture.sourceRegistry,
      topologySlice: fixture.topologySlice,
      definition: definition
    )
    Issue.record("Expected snapshot and evidence drift to block atlas release")
  } catch RouteAtlasReleaseError.invalid(let issues) {
    #expect(issues.contains(.atlasSnapshotMismatch))
    #expect(issues.contains(.unreleasedAtlasEvidence))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Route Atlas release rejects reordered occurrence bindings")
func routeAtlasReleaseRejectsReorderedOccurrences() {
  let fixture = routeAtlasFixture()
  let definition = routeAtlasDefinition(
    fixture: fixture,
    occurrenceBindings: Array(fixture.definition.occurrenceBindings.reversed())
  )

  do {
    _ = try RouteAtlasRelease(
      networkSnapshot: fixture.networkSnapshot,
      routePlan: fixture.routePlan,
      sourceRegistry: fixture.sourceRegistry,
      topologySlice: fixture.topologySlice,
      definition: definition
    )
    Issue.record("Expected reordered occurrence bindings to block atlas release")
  } catch RouteAtlasReleaseError.invalid(let issues) {
    #expect(issues.contains(.occurrenceBindingOrderMismatch))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Route Atlas release requires released topology evidence")
func routeAtlasReleaseRejectsUnreleasedTopology() {
  let fixture = routeAtlasFixture()
  let topology = RouteAtlasTopologySlice(
    id: fixture.topologySlice.id,
    networkSnapshotID: fixture.topologySlice.networkSnapshotID,
    nodes: fixture.topologySlice.nodes,
    edges: fixture.topologySlice.edges,
    evidence: RouteAtlasEvidence(
      state: .officialChecked,
      checkedAt: fixture.topologySlice.evidence.checkedAt,
      sourceReferenceIDs: fixture.topologySlice.evidence.sourceReferenceIDs
    )
  )

  do {
    _ = try RouteAtlasRelease(
      networkSnapshot: fixture.networkSnapshot,
      routePlan: fixture.routePlan,
      sourceRegistry: fixture.sourceRegistry,
      topologySlice: topology,
      definition: fixture.definition
    )
    Issue.record("Expected unreleased topology evidence to block atlas release")
  } catch RouteAtlasReleaseError.invalid(let issues) {
    #expect(issues.contains(.unreleasedTopologyEvidence))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Route Atlas release requires every evidence ID to resolve to the correct source role")
func routeAtlasReleaseRejectsUnresolvedAndMisclassifiedSources() {
  let fixture = routeAtlasFixture()
  let driftedRegistry = RouteAtlasSourceRegistry(
    references: [
      RouteAtlasSourceReference(
        id: "test.source.reviewed-atlas",
        roles: [.topologyEvidence],
        authorityName: "Synthetic misclassified review authority",
        sourceURL: "https://example.test/misclassified-layout",
        contentSHA256:
          "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
        checkedAt: "2026-07-23",
        licenceIdentifier: "SYNTHETIC"
      )
    ]
  )

  do {
    _ = try RouteAtlasRelease(
      networkSnapshot: fixture.networkSnapshot,
      routePlan: fixture.routePlan,
      sourceRegistry: driftedRegistry,
      topologySlice: fixture.topologySlice,
      definition: fixture.definition
    )
    Issue.record("Expected unresolved and misclassified sources to block release")
  } catch RouteAtlasReleaseError.invalid(let issues) {
    #expect(
      issues.contains(
        .unresolvedTopologySource("test.source.reviewed-topology")
      )
    )
    #expect(
      issues.contains(.invalidLayoutSourceRole("test.source.reviewed-atlas"))
    )
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Route Atlas release artifact round-trips before validation")
func routeAtlasReleaseArtifactRoundTrips() throws {
  let fixture = routeAtlasFixture()
  let artifact = RouteAtlasReleaseArtifact(
    networkSnapshot: fixture.networkSnapshot,
    routePlan: fixture.routePlan,
    sourceRegistry: fixture.sourceRegistry,
    topologySlice: fixture.topologySlice,
    definition: fixture.definition
  )
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  let encoded = try encoder.encode(artifact)
  let decoded = try JSONDecoder().decode(
    RouteAtlasReleaseArtifact.self,
    from: encoded
  )
  let release = try RouteAtlasRelease(artifact: decoded)

  #expect(decoded == artifact)
  #expect(release.sourceRegistry == fixture.sourceRegistry)
}

@Test("Route Atlas release artifact rejects schema drift")
func routeAtlasReleaseArtifactRejectsSchemaDrift() {
  let fixture = routeAtlasFixture()
  let artifact = RouteAtlasReleaseArtifact(
    schemaVersion: "2.0",
    networkSnapshot: fixture.networkSnapshot,
    routePlan: fixture.routePlan,
    sourceRegistry: fixture.sourceRegistry,
    topologySlice: fixture.topologySlice,
    definition: fixture.definition
  )

  do {
    _ = try RouteAtlasRelease(artifact: artifact)
    Issue.record("Expected release artifact schema drift to block validation")
  } catch RouteAtlasReleaseError.invalid(let issues) {
    #expect(issues.contains(.invalidArtifactSchemaVersion))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

private struct RouteAtlasFixture {
  let networkSnapshot: NetworkSnapshot
  let routePlan: RoutePlan
  let sourceRegistry: RouteAtlasSourceRegistry
  let topologySlice: RouteAtlasTopologySlice
  let definition: RouteAtlasDefinition
}

private func routeAtlasFixture() -> RouteAtlasFixture {
  let networkSnapshot = NetworkSnapshot(
    id: "test.snapshot.route-atlas",
    status: .active,
    effectiveAt: "2026-07-23T00:00:00+09:00"
  )
  let routePlan = RoutePlan(
    id: "test.plan.route-atlas",
    networkSnapshotID: networkSnapshot.id,
    entryFacilityID: "test.entrance",
    exitFacilityID: "test.exit",
    recoveryPolicy: .strict,
    occurrences: [
      RouteOccurrence(
        id: "test.occurrence.loop-1",
        index: 0,
        kind: .edge,
        entityID: "test.edge.loop"
      ),
      RouteOccurrence(
        id: "test.occurrence.turn",
        index: 1,
        kind: .junctionMovement,
        entityID: "test.movement.turn"
      ),
      RouteOccurrence(
        id: "test.occurrence.loop-2",
        index: 2,
        kind: .edge,
        entityID: "test.edge.loop"
      ),
    ]
  )
  let sourceRegistry = RouteAtlasSourceRegistry(
    references: [
      RouteAtlasSourceReference(
        id: "test.source.reviewed-topology",
        roles: [.topologyEvidence],
        authorityName: "Synthetic topology review authority",
        sourceURL: "https://example.test/reviewed-topology",
        contentSHA256:
          "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        checkedAt: "2026-07-23",
        licenceIdentifier: "SYNTHETIC"
      ),
      RouteAtlasSourceReference(
        id: "test.source.reviewed-atlas",
        roles: [.layoutEvidence],
        authorityName: "Synthetic layout review authority",
        sourceURL: "https://example.test/reviewed-layout",
        contentSHA256:
          "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        checkedAt: "2026-07-23",
        licenceIdentifier: "SYNTHETIC"
      ),
    ]
  )
  let topologySlice = RouteAtlasTopologySlice(
    id: "test.topology.route-atlas",
    networkSnapshotID: networkSnapshot.id,
    nodes: [
      RouteAtlasTopologyNode(id: "test.node.a"),
      RouteAtlasTopologyNode(id: "test.node.b"),
    ],
    edges: [
      RouteAtlasTopologyEdge(
        id: "test.topology-edge.loop",
        routeEntityID: "test.edge.loop",
        fromNodeID: "test.node.a",
        toNodeID: "test.node.b",
        successorEdgeIDs: ["test.topology-edge.turn"]
      ),
      RouteAtlasTopologyEdge(
        id: "test.topology-edge.turn",
        routeEntityID: "test.movement.turn",
        fromNodeID: "test.node.b",
        toNodeID: "test.node.a",
        successorEdgeIDs: ["test.topology-edge.loop"]
      ),
    ],
    evidence: RouteAtlasEvidence(
      state: .released,
      checkedAt: "2026-07-23",
      sourceReferenceIDs: ["test.source.reviewed-topology"]
    )
  )
  let definition = RouteAtlasDefinition(
    id: "test.atlas.route-atlas",
    networkSnapshotID: networkSnapshot.id,
    routePlanID: routePlan.id,
    topologySliceID: topologySlice.id,
    nodes: [
      RouteAtlasLayoutNode(
        topologyNodeID: "test.node.a",
        point: RouteAtlasPoint(x: 0.1, y: 0.8)
      ),
      RouteAtlasLayoutNode(
        topologyNodeID: "test.node.b",
        point: RouteAtlasPoint(x: 0.5, y: 0.5)
      ),
    ],
    segments: [
      RouteAtlasSegment(
        id: "test.segment.loop",
        topologyEdgeID: "test.topology-edge.loop",
        fromNodeID: "test.node.a",
        toNodeID: "test.node.b",
        successorSegmentIDs: ["test.segment.turn"],
        points: [
          RouteAtlasPoint(x: 0.1, y: 0.8),
          RouteAtlasPoint(x: 0.3, y: 0.65),
          RouteAtlasPoint(x: 0.5, y: 0.5),
        ]
      ),
      RouteAtlasSegment(
        id: "test.segment.turn",
        topologyEdgeID: "test.topology-edge.turn",
        fromNodeID: "test.node.b",
        toNodeID: "test.node.a",
        successorSegmentIDs: ["test.segment.loop"],
        points: [
          RouteAtlasPoint(x: 0.5, y: 0.5),
          RouteAtlasPoint(x: 0.3, y: 0.35),
          RouteAtlasPoint(x: 0.1, y: 0.8),
        ]
      ),
    ],
    occurrenceBindings: [
      RouteAtlasOccurrenceBinding(
        occurrenceID: "test.occurrence.loop-1",
        occurrenceIndex: 0,
        segmentID: "test.segment.loop"
      ),
      RouteAtlasOccurrenceBinding(
        occurrenceID: "test.occurrence.turn",
        occurrenceIndex: 1,
        segmentID: "test.segment.turn"
      ),
      RouteAtlasOccurrenceBinding(
        occurrenceID: "test.occurrence.loop-2",
        occurrenceIndex: 2,
        segmentID: "test.segment.loop"
      ),
    ],
    evidence: RouteAtlasEvidence(
      state: .released,
      checkedAt: "2026-07-23",
      sourceReferenceIDs: ["test.source.reviewed-atlas"]
    )
  )
  return RouteAtlasFixture(
    networkSnapshot: networkSnapshot,
    routePlan: routePlan,
    sourceRegistry: sourceRegistry,
    topologySlice: topologySlice,
    definition: definition
  )
}

private func routeAtlasDefinition(
  fixture: RouteAtlasFixture,
  segments: [RouteAtlasSegment]? = nil,
  occurrenceBindings: [RouteAtlasOccurrenceBinding]? = nil
) -> RouteAtlasDefinition {
  RouteAtlasDefinition(
    id: fixture.definition.id,
    networkSnapshotID: fixture.definition.networkSnapshotID,
    routePlanID: fixture.definition.routePlanID,
    topologySliceID: fixture.definition.topologySliceID,
    nodes: fixture.definition.nodes,
    segments: segments ?? fixture.definition.segments,
    occurrenceBindings: occurrenceBindings ?? fixture.definition.occurrenceBindings,
    evidence: fixture.definition.evidence
  )
}
