import KaidoDomain
import KaidoNavigation
import Testing

@Test("Product release round-trips one exact navigation and atlas authority")
func kaidoProductReleaseRoundTrips() throws {
  let navigationFixture = navigationReleaseBundleFixture()
  let navigationArtifact = navigationReleaseArtifact(navigationFixture)
  let atlasArtifact = productRouteAtlasArtifact(
    navigationFixture,
    includeIncomingApproach: true
  )
  let artifact = KaidoProductReleaseArtifact(
    releaseID: "test.product-release.v1",
    releasedAt: "2026-07-24T12:00:00+09:00",
    navigationRelease: navigationArtifact,
    routeAtlasRelease: atlasArtifact
  )

  let data = try KaidoProductReleaseArtifactCodec.encode(artifact)
  let repeatedData = try KaidoProductReleaseArtifactCodec.encode(artifact)
  let release = try KaidoProductReleaseArtifactCodec.decode(data)

  #expect(data == repeatedData)
  #expect(release.releaseID == artifact.releaseID)
  #expect(release.navigation.bundle.routePlan == navigationFixture.routePlan)
  #expect(release.routeAtlas.routePlan == navigationFixture.routePlan)
  #expect(release.routeAtlas.topologySlice.edges.count == 5)
  #expect(release.runtimeUse == .syntheticTestOnlyDisabled)
  #expect(release.foregroundLiveInputAuthority == nil)
}

@Test("Product release blocks an editor approach absent from released atlas topology")
func kaidoProductReleaseRequiresEditorAtlasCoverage() throws {
  let navigationFixture = navigationReleaseBundleFixture()
  let navigationArtifact = navigationReleaseArtifact(navigationFixture)
  let atlasArtifact = productRouteAtlasArtifact(
    navigationFixture,
    includeIncomingApproach: false
  )
  _ = try RouteAtlasRelease(artifact: atlasArtifact)
  let artifact = KaidoProductReleaseArtifact(
    releaseID: "test.product-release.missing-editor-approach",
    releasedAt: "2026-07-24T12:00:00+09:00",
    navigationRelease: navigationArtifact,
    routeAtlasRelease: atlasArtifact
  )

  do {
    _ = try KaidoProductRelease(artifact: artifact)
    Issue.record("Expected the uncovered editor approach to block product release")
  } catch KaidoProductReleaseError.invalid(let issues) {
    #expect(
      issues.contains(
        .missingAtlasEditorEntity(.incomingApproach, "test.approach.loop")
      )
    )
    #expect(issues.count == 1)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Individually valid releases cannot cross snapshot or RoutePlan identity")
func kaidoProductReleaseRejectsIndependentReleaseDrift() throws {
  let navigationFixture = navigationReleaseBundleFixture()
  let navigationArtifact = navigationReleaseArtifact(navigationFixture)
  let otherAtlas = routeAtlasFixture()
  let atlasArtifact = RouteAtlasReleaseArtifact(
    networkSnapshot: otherAtlas.networkSnapshot,
    routePlan: otherAtlas.routePlan,
    sourceRegistry: RouteAtlasSourceRegistry(
      references: otherAtlas.sourceRegistry.references.map { source in
        RouteAtlasSourceReference(
          id: source.id,
          roles: source.roles,
          authorityName: source.authorityName,
          sourceURL: source.sourceURL,
          contentSHA256: source.contentSHA256,
          checkedAt: source.checkedAt,
          licenceIdentifier: "SYNTHETIC_TEST_ONLY"
        )
      }
    ),
    topologySlice: otherAtlas.topologySlice,
    definition: otherAtlas.definition
  )
  _ = try NavigationRelease(artifact: navigationArtifact)
  _ = try RouteAtlasRelease(artifact: atlasArtifact)

  let artifact = KaidoProductReleaseArtifact(
    releaseID: "test.product-release.drift",
    releasedAt: "2026-07-24T12:00:00+09:00",
    navigationRelease: navigationArtifact,
    routeAtlasRelease: atlasArtifact
  )
  do {
    _ = try KaidoProductRelease(artifact: artifact)
    Issue.record("Expected independently valid release drift to fail")
  } catch KaidoProductReleaseError.invalid(let issues) {
    #expect(issues.contains(.networkSnapshotMismatch))
    #expect(issues.contains(.routePlanMismatch))
    #expect(issues.count == 2)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Product release rejects an unknown schema and future navigation release")
func kaidoProductReleaseRejectsSchemaAndChronologyDrift() {
  let navigationFixture = navigationReleaseBundleFixture()
  let validNavigation = navigationReleaseArtifact(navigationFixture)
  let futureNavigation = NavigationReleaseArtifact(
    releaseID: validNavigation.releaseID,
    releasedAt: "2026-07-25T12:00:00+09:00",
    editorCatalogID: validNavigation.editorCatalogID,
    networkSnapshot: validNavigation.networkSnapshot,
    routePlan: validNavigation.routePlan,
    sourceRegistry: validNavigation.sourceRegistry,
    assetEvidence: validNavigation.assetEvidence,
    editorCatalog: validNavigation.editorCatalog,
    runtimePolicy: validNavigation.runtimePolicy,
    matcherCorridor: validNavigation.matcherCorridor,
    decisionZones: validNavigation.decisionZones,
    releasedGuidance: validNavigation.releasedGuidance,
    junctionViews: validNavigation.junctionViews
  )
  let artifact = KaidoProductReleaseArtifact(
    schemaVersion: "4.0",
    releaseID: "test.product-release.future-navigation",
    releasedAt: "2026-07-24T12:00:00+09:00",
    navigationRelease: futureNavigation,
    routeAtlasRelease: productRouteAtlasArtifact(
      navigationFixture,
      includeIncomingApproach: true
    )
  )

  do {
    _ = try KaidoProductRelease(artifact: artifact)
    Issue.record("Expected schema and chronology drift to block product release")
  } catch KaidoProductReleaseError.invalid(let issues) {
    #expect(issues.contains(.invalidArtifactSchemaVersion))
    #expect(issues.contains(.navigationReleaseAfterProductRelease))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Synthetic product evidence cannot request foreground live input")
func syntheticProductReleaseCannotRequestLiveInput() throws {
  let fixture = navigationReleaseBundleFixture()
  let artifact = KaidoProductReleaseArtifact(
    releaseID: "test.product-release.synthetic-live-input",
    releasedAt: "2026-07-24T12:00:00+09:00",
    runtimeUse: KaidoProductRuntimeUseDeclaration(
      evidenceScope: .syntheticTestOnly,
      liveInputPolicy: .foregroundWhenInUse
    ),
    navigationRelease: navigationReleaseArtifact(fixture),
    routeAtlasRelease: productRouteAtlasArtifact(
      fixture,
      includeIncomingApproach: true
    )
  )

  do {
    _ = try KaidoProductRelease(artifact: artifact)
    Issue.record("Expected synthetic live input to fail closed")
  } catch KaidoProductReleaseError.invalid(let issues) {
    #expect(
      issues == [
        .invalidRuntimeUse(.syntheticLiveInputForbidden)
      ]
    )
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Product release requires an explicit runtime-use declaration")
func productReleaseRequiresRuntimeUse() {
  let fixture = navigationReleaseBundleFixture()
  let artifact = KaidoProductReleaseArtifact(
    releaseID: "test.product-release.missing-runtime-use",
    releasedAt: "2026-07-24T12:00:00+09:00",
    runtimeUse: nil,
    navigationRelease: navigationReleaseArtifact(fixture),
    routeAtlasRelease: productRouteAtlasArtifact(
      fixture,
      includeIncomingApproach: true
    )
  )

  do {
    _ = try KaidoProductRelease(artifact: artifact)
    Issue.record("Expected missing runtime use to fail closed")
  } catch KaidoProductReleaseError.invalid(let issues) {
    #expect(issues == [.missingRuntimeUse])
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Only a validated released-road product mints foreground authority")
func releasedRoadProductMintsForegroundAuthority() throws {
  let fixture = navigationReleaseBundleFixture()
  let artifact = KaidoProductReleaseArtifact(
    releaseID: "test.product-release.released-road",
    releasedAt: "2026-07-24T12:00:00+09:00",
    runtimeUse: KaidoProductRuntimeUseDeclaration(
      evidenceScope: .releasedRoad,
      liveInputPolicy: .foregroundWhenInUse
    ),
    navigationRelease: productNavigationReleaseArtifact(
      fixture,
      licenceIdentifier: "TEST_REVIEWED_ROAD_ONLY"
    ),
    routeAtlasRelease: productRouteAtlasArtifact(
      fixture,
      includeIncomingApproach: true,
      licenceIdentifier: "TEST_REVIEWED_ROAD_ONLY"
    )
  )

  let release = try KaidoProductRelease(artifact: artifact)
  let authority = try #require(release.foregroundLiveInputAuthority)

  #expect(release.runtimeUseEvaluation.foregroundLiveInputAdmitted)
  #expect(authority.runtimeIdentity == release.runtimeIdentity)
  #expect(release.runtimeIdentity.productReleaseID == artifact.releaseID)
  #expect(release.runtimeIdentity.navigationReleaseID == artifact.navigationRelease.releaseID)
  #expect(release.runtimeIdentity.runtimePolicyID == fixture.runtimePolicy.id)
  #expect(release.runtimeIdentity.networkSnapshotID == fixture.networkSnapshot.id)
  #expect(release.runtimeIdentity.routePlanID == fixture.routePlan.id)
  #expect(release.runtimeIdentity.matcherCorridorID == fixture.matcherCorridor.id)
}

@Test("Released-road runtime scope rejects mixed synthetic sources")
func releasedRoadRuntimeScopeRejectsSyntheticSources() {
  let evaluation = KaidoProductRuntimeUseEvaluator.evaluate(
    declaration: KaidoProductRuntimeUseDeclaration(
      evidenceScope: .releasedRoad,
      liveInputPolicy: .foregroundWhenInUse
    ),
    sources: [
      KaidoProductRuntimeSourceDescriptor(
        domain: .navigation,
        sourceID: "test.source.navigation",
        licenceIdentifier: "TEST_REVIEWED_ROAD_ONLY"
      ),
      KaidoProductRuntimeSourceDescriptor(
        domain: .routeAtlas,
        sourceID: "test.source.atlas",
        licenceIdentifier: "SYNTHETIC_TEST_ONLY"
      ),
    ]
  )

  #expect(!evaluation.isValid)
  #expect(!evaluation.foregroundLiveInputAdmitted)
  #expect(
    evaluation.issues == [
      .sourceScopeMismatch(.routeAtlas, sourceID: "test.source.atlas")
    ]
  )
}

@Test("Route Atlas evidence cannot postdate the product release")
func kaidoProductReleaseRejectsFutureAtlasEvidence() {
  let navigationFixture = navigationReleaseBundleFixture()
  let artifact = KaidoProductReleaseArtifact(
    releaseID: "test.product-release.future-atlas-evidence",
    releasedAt: "2026-07-24T12:00:00+09:00",
    navigationRelease: navigationReleaseArtifact(navigationFixture),
    routeAtlasRelease: productRouteAtlasArtifact(
      navigationFixture,
      includeIncomingApproach: true,
      checkedAt: "2026-07-25"
    )
  )

  do {
    _ = try KaidoProductRelease(artifact: artifact)
    Issue.record("Expected future Route Atlas evidence to block product release")
  } catch KaidoProductReleaseError.invalid(let issues) {
    #expect(
      issues.contains(
        .atlasEvidenceAfterProductRelease("SOURCE:test.source.product-topology")
      )
    )
    #expect(
      issues.contains(
        .atlasEvidenceAfterProductRelease(
          "TOPOLOGY:test.topology.product-release"
        )
      )
    )
    #expect(
      issues.contains(
        .atlasEvidenceAfterProductRelease("LAYOUT:test.atlas.product-release")
      )
    )
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Product runtime consumes only the joint release runtime policy")
func kaidoProductRuntimeUsesJointReleaseAuthority() async throws {
  let navigationFixture = navigationReleaseBundleFixture()
  let release = try KaidoProductRelease(
    artifact: KaidoProductReleaseArtifact(
      releaseID: "test.product-release.runtime",
      releasedAt: "2026-07-24T12:00:00+09:00",
      navigationRelease: navigationReleaseArtifact(navigationFixture),
      routeAtlasRelease: productRouteAtlasArtifact(
        navigationFixture,
        includeIncomingApproach: true
      )
    )
  )

  let runtime = try KaidoProductNavigationRuntime(release: release)
  let started = await runtime.session.start()
  let finish = await runtime.session.finishDrive()

  #expect(runtime.productReleaseID == release.releaseID)
  #expect(runtime.navigationReleaseID == release.navigation.releaseID)
  #expect(runtime.networkSnapshotID == navigationFixture.networkSnapshot.id)
  #expect(runtime.routePlanID == navigationFixture.routePlan.id)
  #expect(runtime.routeAtlas == release.routeAtlas)
  #expect(
    runtime.release.navigation.bundle.runtimePolicy
      == navigationFixture.runtimePolicy
  )
  #expect(started.activeRoutePlanID == navigationFixture.routePlan.id)
  #expect(started.currentOccurrenceID == navigationFixture.routePlan.occurrences.first?.id)
  #expect(started.journeyPhase == .planning)
  #expect(started.strictRouteAutoCommitAllowed == false)
  #expect(finish.egress.status == .active)
  #expect(finish.egress.exitFacilityID == navigationFixture.routePlan.exitFacilityID)
}

func productRouteAtlasArtifact(
  _ fixture: NavigationReleaseBundleFixture,
  includeIncomingApproach: Bool,
  checkedAt: String = "2026-07-23",
  licenceIdentifier: String = "SYNTHETIC_TEST_ONLY"
) -> RouteAtlasReleaseArtifact {
  let topologySourceID = "test.source.product-topology"
  let layoutSourceID = "test.source.product-layout"
  let sourceRegistry = RouteAtlasSourceRegistry(
    references: [
      RouteAtlasSourceReference(
        id: topologySourceID,
        roles: [.topologyEvidence],
        authorityName: "Synthetic product topology authority",
        sourceURL: "https://example.com/test-product-topology",
        contentSHA256: String(repeating: "b", count: 64),
        checkedAt: checkedAt,
        licenceIdentifier: licenceIdentifier
      ),
      RouteAtlasSourceReference(
        id: layoutSourceID,
        roles: [.layoutEvidence],
        authorityName: "Synthetic product layout authority",
        sourceURL: "https://example.com/test-product-layout",
        contentSHA256: String(repeating: "c", count: 64),
        checkedAt: checkedAt,
        licenceIdentifier: licenceIdentifier
      ),
    ]
  )

  var nodes = [
    RouteAtlasTopologyNode(id: "test.node.a"),
    RouteAtlasTopologyNode(id: "test.node.b"),
    RouteAtlasTopologyNode(id: "test.node.c"),
    RouteAtlasTopologyNode(id: "test.node.d"),
  ]
  var edges = [
    RouteAtlasTopologyEdge(
      id: "test.topology-edge.loop",
      routeEntityID: "test.edge.loop",
      fromNodeID: "test.node.a",
      toNodeID: "test.node.b",
      successorEdgeIDs: [
        "test.topology-edge.loop-movement",
        "test.topology-edge.exit-movement",
      ]
    ),
    RouteAtlasTopologyEdge(
      id: "test.topology-edge.loop-movement",
      routeEntityID: "test.movement.loop",
      fromNodeID: "test.node.b",
      toNodeID: "test.node.a",
      successorEdgeIDs: ["test.topology-edge.loop"]
    ),
    RouteAtlasTopologyEdge(
      id: "test.topology-edge.exit-movement",
      routeEntityID: "test.movement.exit",
      fromNodeID: "test.node.b",
      toNodeID: "test.node.c",
      successorEdgeIDs: ["test.topology-edge.exit"]
    ),
    RouteAtlasTopologyEdge(
      id: "test.topology-edge.exit",
      routeEntityID: "test.edge.exit",
      fromNodeID: "test.node.c",
      toNodeID: "test.node.d"
    ),
  ]
  if includeIncomingApproach {
    nodes.append(RouteAtlasTopologyNode(id: "test.node.editor-approach"))
    edges.append(
      RouteAtlasTopologyEdge(
        id: "test.topology-edge.editor-approach",
        routeEntityID: "test.approach.loop",
        fromNodeID: "test.node.editor-approach",
        toNodeID: "test.node.b",
        successorEdgeIDs: [
          "test.topology-edge.loop-movement",
          "test.topology-edge.exit-movement",
        ]
      )
    )
  }
  let topology = RouteAtlasTopologySlice(
    id: "test.topology.product-release",
    networkSnapshotID: fixture.networkSnapshot.id,
    nodes: nodes,
    edges: edges,
    evidence: RouteAtlasEvidence(
      state: .released,
      checkedAt: checkedAt,
      sourceReferenceIDs: [topologySourceID]
    )
  )

  var layoutNodes = [
    RouteAtlasLayoutNode(
      topologyNodeID: "test.node.a",
      point: RouteAtlasPoint(x: 0.1, y: 0.8)
    ),
    RouteAtlasLayoutNode(
      topologyNodeID: "test.node.b",
      point: RouteAtlasPoint(x: 0.5, y: 0.5)
    ),
    RouteAtlasLayoutNode(
      topologyNodeID: "test.node.c",
      point: RouteAtlasPoint(x: 0.75, y: 0.35)
    ),
    RouteAtlasLayoutNode(
      topologyNodeID: "test.node.d",
      point: RouteAtlasPoint(x: 0.95, y: 0.2)
    ),
  ]
  var segments = [
    RouteAtlasSegment(
      id: "test.segment.loop",
      topologyEdgeID: "test.topology-edge.loop",
      fromNodeID: "test.node.a",
      toNodeID: "test.node.b",
      successorSegmentIDs: [
        "test.segment.loop-movement",
        "test.segment.exit-movement",
      ],
      points: [
        RouteAtlasPoint(x: 0.1, y: 0.8),
        RouteAtlasPoint(x: 0.5, y: 0.5),
      ]
    ),
    RouteAtlasSegment(
      id: "test.segment.loop-movement",
      topologyEdgeID: "test.topology-edge.loop-movement",
      fromNodeID: "test.node.b",
      toNodeID: "test.node.a",
      successorSegmentIDs: ["test.segment.loop"],
      points: [
        RouteAtlasPoint(x: 0.5, y: 0.5),
        RouteAtlasPoint(x: 0.1, y: 0.8),
      ]
    ),
    RouteAtlasSegment(
      id: "test.segment.exit-movement",
      topologyEdgeID: "test.topology-edge.exit-movement",
      fromNodeID: "test.node.b",
      toNodeID: "test.node.c",
      successorSegmentIDs: ["test.segment.exit"],
      points: [
        RouteAtlasPoint(x: 0.5, y: 0.5),
        RouteAtlasPoint(x: 0.75, y: 0.35),
      ]
    ),
    RouteAtlasSegment(
      id: "test.segment.exit",
      topologyEdgeID: "test.topology-edge.exit",
      fromNodeID: "test.node.c",
      toNodeID: "test.node.d",
      points: [
        RouteAtlasPoint(x: 0.75, y: 0.35),
        RouteAtlasPoint(x: 0.95, y: 0.2),
      ]
    ),
  ]
  if includeIncomingApproach {
    layoutNodes.append(
      RouteAtlasLayoutNode(
        topologyNodeID: "test.node.editor-approach",
        point: RouteAtlasPoint(x: 0.05, y: 0.5)
      )
    )
    segments.append(
      RouteAtlasSegment(
        id: "test.segment.editor-approach",
        topologyEdgeID: "test.topology-edge.editor-approach",
        fromNodeID: "test.node.editor-approach",
        toNodeID: "test.node.b",
        successorSegmentIDs: [
          "test.segment.loop-movement",
          "test.segment.exit-movement",
        ],
        points: [
          RouteAtlasPoint(x: 0.05, y: 0.5),
          RouteAtlasPoint(x: 0.5, y: 0.5),
        ]
      )
    )
  }
  let segmentByEntityID = Dictionary(
    uniqueKeysWithValues: zip(
      edges.map(\.routeEntityID),
      segments.map(\.id)
    )
  )
  let occurrenceBindings = fixture.routePlan.occurrences.map { occurrence in
    RouteAtlasOccurrenceBinding(
      occurrenceID: occurrence.id,
      occurrenceIndex: occurrence.index,
      segmentID: segmentByEntityID[occurrence.entityID]!
    )
  }
  let definition = RouteAtlasDefinition(
    id: "test.atlas.product-release",
    networkSnapshotID: fixture.networkSnapshot.id,
    routePlanID: fixture.routePlan.id,
    topologySliceID: topology.id,
    nodes: layoutNodes,
    segments: segments,
    occurrenceBindings: occurrenceBindings,
    evidence: RouteAtlasEvidence(
      state: .released,
      checkedAt: checkedAt,
      sourceReferenceIDs: [layoutSourceID]
    )
  )
  return RouteAtlasReleaseArtifact(
    networkSnapshot: fixture.networkSnapshot,
    routePlan: fixture.routePlan,
    sourceRegistry: sourceRegistry,
    topologySlice: topology,
    definition: definition
  )
}

private func productNavigationReleaseArtifact(
  _ fixture: NavigationReleaseBundleFixture,
  licenceIdentifier: String
) -> NavigationReleaseArtifact {
  let artifact = navigationReleaseArtifact(fixture)
  return NavigationReleaseArtifact(
    schemaVersion: artifact.schemaVersion,
    releaseID: artifact.releaseID,
    releasedAt: artifact.releasedAt,
    editorCatalogID: artifact.editorCatalogID,
    networkSnapshot: artifact.networkSnapshot,
    routePlan: artifact.routePlan,
    sourceRegistry: NavigationReleaseSourceRegistry(
      references: artifact.sourceRegistry.references.map { source in
        NavigationReleaseSourceReference(
          id: source.id,
          roles: source.roles,
          authorityName: source.authorityName,
          sourceURL: source.sourceURL,
          contentSHA256: source.contentSHA256,
          checkedAt: source.checkedAt,
          licenceIdentifier: licenceIdentifier
        )
      }
    ),
    assetEvidence: artifact.assetEvidence,
    editorCatalog: artifact.editorCatalog,
    runtimePolicy: artifact.runtimePolicy,
    matcherCorridor: artifact.matcherCorridor,
    decisionZones: artifact.decisionZones,
    releasedGuidance: artifact.releasedGuidance,
    junctionViews: artifact.junctionViews
  )
}
