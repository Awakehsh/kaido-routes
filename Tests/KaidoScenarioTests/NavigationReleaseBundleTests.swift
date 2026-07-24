import Foundation
import KaidoDomain
import KaidoNavigation
import KaidoRouting
import Testing

@Test("Navigation release bundle accepts repeated graph entities as distinct occurrences")
func navigationReleaseBundleAcceptsCoherentRepeatedOccurrences() throws {
  let fixture = navigationReleaseBundleFixture()
  let bundle = try NavigationReleaseBundle(
    networkSnapshot: fixture.networkSnapshot,
    routePlan: fixture.routePlan,
    editorCatalog: fixture.editorCatalog,
    runtimePolicy: fixture.runtimePolicy,
    matcherCorridor: fixture.matcherCorridor,
    decisionZones: fixture.decisionZones,
    releasedGuidance: fixture.releasedGuidance,
    junctionViews: fixture.junctionViews
  )

  #expect(bundle.routePlan.occurrences.count == 7)
  #expect(
    bundle.routePlan.occurrences.filter { $0.entityID == "test.movement.loop" }.map(\.id)
      == ["test.occurrence.loop-movement-1", "test.occurrence.loop-movement-2"]
  )
  #expect(bundle.decisionZones.count == 3)
  #expect(bundle.junctionViews.map(\.id) == ["test.junction-view.exit"])
  #expect(
    bundle.routeAuthoringRecipe.steps.map(\.movementOccurrenceID) == [
      "test.occurrence.loop-movement-1",
      "test.occurrence.loop-movement-2",
      "test.occurrence.exit-movement",
    ])
}

@Test("Navigation release bundle rejects RoutePlan and editor-catalog step drift")
func navigationReleaseBundleRejectsEditorStepDrift() {
  let fixture = navigationReleaseBundleFixture()
  var occurrences = fixture.routePlan.occurrences
  let exitEdge = occurrences[6]
  occurrences[6] = RouteOccurrence(
    id: exitEdge.id,
    index: exitEdge.index,
    kind: exitEdge.kind,
    entityID: "test.edge.unreviewed",
    tollDomainID: exitEdge.tollDomainID
  )
  let driftedRoutePlan = RoutePlan(
    id: fixture.routePlan.id,
    networkSnapshotID: fixture.routePlan.networkSnapshotID,
    entryFacilityID: fixture.routePlan.entryFacilityID,
    exitFacilityID: fixture.routePlan.exitFacilityID,
    recoveryPolicy: fixture.routePlan.recoveryPolicy,
    occurrences: occurrences
  )

  do {
    _ = try NavigationReleaseBundle(
      networkSnapshot: fixture.networkSnapshot,
      routePlan: driftedRoutePlan,
      editorCatalog: fixture.editorCatalog,
      runtimePolicy: fixture.runtimePolicy,
      matcherCorridor: fixture.matcherCorridor,
      decisionZones: fixture.decisionZones,
      releasedGuidance: fixture.releasedGuidance,
      junctionViews: fixture.junctionViews
    )
    Issue.record("Expected editor-catalog step drift to block release")
  } catch NavigationReleaseBundleError.invalid(let issues) {
    #expect(
      issues.contains(
        .routePlanEditorCatalogMismatch(
          .unavailableChoice("test.occurrence.exit-movement")
        )
      )
    )
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Every repeated movement occurrence needs its own DecisionZone and guidance")
func navigationReleaseBundleRejectsMissingOccurrenceAssets() {
  let fixture = navigationReleaseBundleFixture()
  let missingOccurrenceID = "test.occurrence.loop-movement-2"

  do {
    _ = try NavigationReleaseBundle(
      networkSnapshot: fixture.networkSnapshot,
      routePlan: fixture.routePlan,
      editorCatalog: fixture.editorCatalog,
      runtimePolicy: fixture.runtimePolicy,
      matcherCorridor: fixture.matcherCorridor,
      decisionZones: fixture.decisionZones.filter {
        $0.movementOccurrenceID != missingOccurrenceID
      },
      releasedGuidance: fixture.releasedGuidance.filter {
        $0.frameTemplate.movementOccurrenceID != missingOccurrenceID
      },
      junctionViews: fixture.junctionViews
    )
    Issue.record("Expected missing occurrence-scoped assets to block release")
  } catch NavigationReleaseBundleError.invalid(let issues) {
    #expect(issues.contains(.missingDecisionZoneForMovement(missingOccurrenceID)))
    #expect(issues.contains(.missingGuidanceForMovement(missingOccurrenceID)))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Duplicate movement DecisionZones fail even when their IDs are unique")
func navigationReleaseBundleRejectsDuplicateMovementZones() {
  let fixture = navigationReleaseBundleFixture()
  let duplicate = DecisionZoneProgressDefinition(
    id: "test.zone.loop-1.duplicate",
    networkSnapshotID: fixture.networkSnapshot.id,
    routePlanID: fixture.routePlan.id,
    movementOccurrenceID: "test.occurrence.loop-movement-1",
    entryOffsetMeters: 6
  )

  do {
    _ = try NavigationReleaseBundle(
      networkSnapshot: fixture.networkSnapshot,
      routePlan: fixture.routePlan,
      editorCatalog: fixture.editorCatalog,
      runtimePolicy: fixture.runtimePolicy,
      matcherCorridor: fixture.matcherCorridor,
      decisionZones: fixture.decisionZones + [duplicate],
      releasedGuidance: fixture.releasedGuidance,
      junctionViews: fixture.junctionViews
    )
    Issue.record("Expected duplicate movement DecisionZones to block release")
  } catch NavigationReleaseBundleError.invalid(let issues) {
    #expect(
      issues.contains(
        .duplicateDecisionZoneForMovement("test.occurrence.loop-movement-1")
      )
    )
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Junction views must be registered exactly and cannot be orphaned")
func navigationReleaseBundleRejectsJunctionViewRegistryDrift() {
  let fixture = navigationReleaseBundleFixture()

  do {
    _ = try NavigationReleaseBundle(
      networkSnapshot: fixture.networkSnapshot,
      routePlan: fixture.routePlan,
      editorCatalog: fixture.editorCatalog,
      runtimePolicy: fixture.runtimePolicy,
      matcherCorridor: fixture.matcherCorridor,
      decisionZones: fixture.decisionZones,
      releasedGuidance: fixture.releasedGuidance,
      junctionViews: []
    )
    Issue.record("Expected an unregistered embedded JunctionView to block release")
  } catch NavigationReleaseBundleError.invalid(let issues) {
    #expect(issues.contains(.unregisteredJunctionView("test.junction-view.exit")))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  let guidanceWithoutJunctionView = fixture.releasedGuidance.map { definition in
    guard
      definition.frameTemplate.movementOccurrenceID
        == "test.occurrence.exit-movement"
    else {
      return definition
    }
    return releasedGuidanceDefinition(
      anchorOccurrenceID: definition.anchor.occurrenceID,
      movementOccurrenceID: definition.frameTemplate.movementOccurrenceID,
      decisionZoneID: definition.frameTemplate.decisionZoneID,
      promptID: definition.anchor.promptID
    )
  }
  do {
    _ = try NavigationReleaseBundle(
      networkSnapshot: fixture.networkSnapshot,
      routePlan: fixture.routePlan,
      editorCatalog: fixture.editorCatalog,
      runtimePolicy: fixture.runtimePolicy,
      matcherCorridor: fixture.matcherCorridor,
      decisionZones: fixture.decisionZones,
      releasedGuidance: guidanceWithoutJunctionView,
      junctionViews: fixture.junctionViews
    )
    Issue.record("Expected an orphaned JunctionView to block release")
  } catch NavigationReleaseBundleError.invalid(let issues) {
    #expect(issues.contains(.orphanedJunctionView("test.junction-view.exit")))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  do {
    let bundleWithoutJunctionViews = try NavigationReleaseBundle(
      networkSnapshot: fixture.networkSnapshot,
      routePlan: fixture.routePlan,
      editorCatalog: fixture.editorCatalog,
      runtimePolicy: fixture.runtimePolicy,
      matcherCorridor: fixture.matcherCorridor,
      decisionZones: fixture.decisionZones,
      releasedGuidance: guidanceWithoutJunctionView,
      junctionViews: []
    )
    #expect(bundleWithoutJunctionViews.junctionViews.isEmpty)
  } catch {
    Issue.record("A consistently absent optional JunctionView should pass: \(error)")
  }

  let mismatchedRegistryView = releasedJunctionView(
    networkSnapshotID: fixture.networkSnapshot.id,
    sourceReferenceIDs: ["test.source.different-review"]
  )
  do {
    _ = try NavigationReleaseBundle(
      networkSnapshot: fixture.networkSnapshot,
      routePlan: fixture.routePlan,
      editorCatalog: fixture.editorCatalog,
      runtimePolicy: fixture.runtimePolicy,
      matcherCorridor: fixture.matcherCorridor,
      decisionZones: fixture.decisionZones,
      releasedGuidance: fixture.releasedGuidance,
      junctionViews: [mismatchedRegistryView]
    )
    Issue.record("Expected JunctionView registry definition drift to block release")
  } catch NavigationReleaseBundleError.invalid(let issues) {
    #expect(issues.contains(.junctionViewDefinitionMismatch("test.junction-view.exit")))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Release status and runtime snapshot identity fail closed")
func navigationReleaseBundleRejectsSnapshotDrift() {
  let fixture = navigationReleaseBundleFixture()
  let proposedSnapshot = NetworkSnapshot(
    id: fixture.networkSnapshot.id,
    status: .proposed,
    effectiveAt: fixture.networkSnapshot.effectiveAt
  )
  do {
    _ = try NavigationReleaseBundle(
      networkSnapshot: proposedSnapshot,
      routePlan: fixture.routePlan,
      editorCatalog: fixture.editorCatalog,
      runtimePolicy: fixture.runtimePolicy,
      matcherCorridor: fixture.matcherCorridor,
      decisionZones: fixture.decisionZones,
      releasedGuidance: fixture.releasedGuidance,
      junctionViews: fixture.junctionViews
    )
    Issue.record("Expected a proposed snapshot to block release")
  } catch NavigationReleaseBundleError.invalid(let issues) {
    #expect(issues.contains(.invalidNetworkSnapshot))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  let driftedCorridor = RouteMatcherCorridor(
    id: fixture.matcherCorridor.id,
    networkSnapshotID: "test.snapshot.other",
    routePlanID: fixture.matcherCorridor.routePlanID,
    edges: fixture.matcherCorridor.edges,
    occurrences: fixture.matcherCorridor.occurrences
  )
  do {
    _ = try NavigationReleaseBundle(
      networkSnapshot: fixture.networkSnapshot,
      routePlan: fixture.routePlan,
      editorCatalog: fixture.editorCatalog,
      runtimePolicy: fixture.runtimePolicy,
      matcherCorridor: driftedCorridor,
      decisionZones: fixture.decisionZones,
      releasedGuidance: fixture.releasedGuidance,
      junctionViews: fixture.junctionViews
    )
    Issue.record("Expected matcher-corridor snapshot drift to block release")
  } catch NavigationReleaseBundleError.invalid(let issues) {
    #expect(
      issues.contains(
        .invalidRuntimeConfiguration(
          "matcher corridor network snapshot does not match"
        )
      )
    )
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Released runtime policy binds entry, recovery, and egress to the RoutePlan")
func navigationReleaseBundleRejectsIncompleteRuntimePolicy() {
  let fixture = navigationReleaseBundleFixture()
  let invalidPolicy = ReleasedNavigationRuntimePolicy(
    id: fixture.runtimePolicy.id,
    networkSnapshotID: fixture.networkSnapshot.id,
    routePlanID: fixture.routePlan.id,
    entryTransition: EntryTransition(
      facilityID: "test.entrance.other",
      directedEdgeIDs: [],
      firstRouteOccurrenceID: nil
    ),
    recoveryCandidates: [],
    egressOptions: []
  )

  do {
    _ = try NavigationReleaseBundle(
      networkSnapshot: fixture.networkSnapshot,
      routePlan: fixture.routePlan,
      editorCatalog: fixture.editorCatalog,
      runtimePolicy: invalidPolicy,
      matcherCorridor: fixture.matcherCorridor,
      decisionZones: fixture.decisionZones,
      releasedGuidance: fixture.releasedGuidance,
      junctionViews: fixture.junctionViews
    )
    Issue.record("Expected incomplete runtime policy to block release")
  } catch NavigationReleaseBundleError.invalid(let issues) {
    #expect(
      issues.contains(
        .invalidRuntimePolicy(.invalidEntryTransition)
      )
    )
    #expect(
      issues.contains(
        .invalidRuntimePolicy(.missingReleasedRecovery)
      )
    )
    #expect(
      issues.contains(
        .invalidRuntimePolicy(.missingReleasedEgress)
      )
    )
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Released recovery must rejoin at a later RoutePlan occurrence")
func navigationReleaseBundleRejectsUnusableRecoveryTarget() {
  let fixture = navigationReleaseBundleFixture()
  let invalidPolicy = ReleasedNavigationRuntimePolicy(
    id: fixture.runtimePolicy.id,
    networkSnapshotID: fixture.runtimePolicy.networkSnapshotID,
    routePlanID: fixture.runtimePolicy.routePlanID,
    entryTransition: fixture.runtimePolicy.entryTransition,
    recoveryCandidates: [
      RecoveryCandidate(
        targetOccurrenceID: "test.occurrence.entry",
        recoveryOccurrenceIDs: [
          "test.recovery.invalid.movement",
          "test.recovery.invalid.edge",
        ],
        isReleased: true,
        staysInAllowedTollDomain: true
      )
    ],
    egressOptions: fixture.runtimePolicy.egressOptions
  )

  do {
    _ = try NavigationReleaseBundle(
      networkSnapshot: fixture.networkSnapshot,
      routePlan: fixture.routePlan,
      editorCatalog: fixture.editorCatalog,
      runtimePolicy: invalidPolicy,
      matcherCorridor: fixture.matcherCorridor,
      decisionZones: fixture.decisionZones,
      releasedGuidance: fixture.releasedGuidance,
      junctionViews: fixture.junctionViews
    )
    Issue.record("Expected an unusable recovery target to block release")
  } catch NavigationReleaseBundleError.invalid(let issues) {
    #expect(
      issues.contains(
        .invalidRuntimePolicy(
          .invalidRecoveryCandidate("test.occurrence.entry")
        )
      )
    )
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Released rejoin candidates require the RoutePlan SAFE_REJOIN policy")
func navigationReleaseBundleRejectsUnexpectedRecoveryCandidates() {
  let fixture = navigationReleaseBundleFixture()
  let strictRoutePlan = RoutePlan(
    id: fixture.routePlan.id,
    networkSnapshotID: fixture.routePlan.networkSnapshotID,
    entryFacilityID: fixture.routePlan.entryFacilityID,
    exitFacilityID: fixture.routePlan.exitFacilityID,
    recoveryPolicy: .strict,
    actualDistanceKM: fixture.routePlan.actualDistanceKM,
    occurrences: fixture.routePlan.occurrences
  )

  do {
    _ = try NavigationReleaseBundle(
      networkSnapshot: fixture.networkSnapshot,
      routePlan: strictRoutePlan,
      editorCatalog: fixture.editorCatalog,
      runtimePolicy: fixture.runtimePolicy,
      matcherCorridor: fixture.matcherCorridor,
      decisionZones: fixture.decisionZones,
      releasedGuidance: fixture.releasedGuidance,
      junctionViews: fixture.junctionViews
    )
    Issue.record("Expected STRICT policy with rejoin candidates to block release")
  } catch NavigationReleaseBundleError.invalid(let issues) {
    #expect(
      issues.contains(
        .invalidRuntimePolicy(.unexpectedReleasedRecovery)
      )
    )
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Released runtime egress cannot replace the compiled RoutePlan exit")
func navigationReleaseBundleRejectsRuntimeEgressExitDrift() {
  let fixture = navigationReleaseBundleFixture()
  let driftedPolicy = ReleasedNavigationRuntimePolicy(
    id: fixture.runtimePolicy.id,
    networkSnapshotID: fixture.runtimePolicy.networkSnapshotID,
    routePlanID: fixture.runtimePolicy.routePlanID,
    entryTransition: fixture.runtimePolicy.entryTransition,
    recoveryCandidates: fixture.runtimePolicy.recoveryCandidates,
    egressOptions: [
      EgressOption(
        id: "test.egress.other",
        firstEligibleOccurrenceID: "test.occurrence.loop-edge-2",
        exitFacilityID: "test.exit.other",
        egressOccurrenceIDs: [
          "test.egress.other.movement",
          "test.egress.other.edge",
        ],
        isReleased: true
      )
    ]
  )

  do {
    _ = try NavigationReleaseBundle(
      networkSnapshot: fixture.networkSnapshot,
      routePlan: fixture.routePlan,
      editorCatalog: fixture.editorCatalog,
      runtimePolicy: driftedPolicy,
      matcherCorridor: fixture.matcherCorridor,
      decisionZones: fixture.decisionZones,
      releasedGuidance: fixture.releasedGuidance,
      junctionViews: fixture.junctionViews
    )
    Issue.record("Expected runtime egress exit drift to block release")
  } catch NavigationReleaseBundleError.invalid(let issues) {
    #expect(
      issues.contains(
        .invalidRuntimePolicy(.invalidEgressOption("test.egress.other"))
      )
    )
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Navigation release artifact round-trips through the provenance and bundle gates")
func navigationReleaseArtifactRoundTrips() throws {
  let fixture = navigationReleaseBundleFixture()
  let artifact = navigationReleaseArtifact(fixture)

  let data = try NavigationReleaseArtifactCodec.encode(artifact)
  let repeatedData = try NavigationReleaseArtifactCodec.encode(artifact)
  let release = try NavigationReleaseArtifactCodec.decode(data)

  #expect(data == repeatedData)
  #expect(release.releaseID == artifact.releaseID)
  #expect(release.bundle.routePlan == fixture.routePlan)
  #expect(release.bundle.editorCatalog == fixture.editorCatalog)
  #expect(release.bundle.runtimePolicy == fixture.runtimePolicy)
  #expect(release.bundle.matcherCorridor == fixture.matcherCorridor)
  #expect(release.bundle.decisionZones == fixture.decisionZones)
  #expect(release.bundle.releasedGuidance == fixture.releasedGuidance)
  #expect(release.bundle.junctionViews == fixture.junctionViews)
  #expect(release.assetEvidence.count == 10)

  let json = try #require(String(data: data, encoding: .utf8))
  #expect(json.contains("\"schema_version\" : \"2.0\""))
  #expect(json.contains("\"ja-JP\""))
  #expect(json.contains("\"zh-Hans\""))
  #expect(json.contains("\"en\""))
}

@Test("Navigation release artifact requires an evidenced runtime policy")
func navigationReleaseArtifactRejectsMissingRuntimePolicy() throws {
  let fixture = navigationReleaseBundleFixture()
  let valid = navigationReleaseArtifact(fixture)
  let artifact = NavigationReleaseArtifact(
    releaseID: valid.releaseID,
    releasedAt: valid.releasedAt,
    editorCatalogID: valid.editorCatalogID,
    networkSnapshot: valid.networkSnapshot,
    routePlan: valid.routePlan,
    sourceRegistry: valid.sourceRegistry,
    assetEvidence: valid.assetEvidence,
    editorCatalog: valid.editorCatalog,
    runtimePolicy: nil,
    matcherCorridor: valid.matcherCorridor,
    decisionZones: valid.decisionZones,
    releasedGuidance: valid.releasedGuidance,
    junctionViews: valid.junctionViews
  )

  let unvalidatedData = try JSONEncoder().encode(artifact)
  do {
    _ = try NavigationReleaseArtifactCodec.decode(unvalidatedData)
    Issue.record("Expected a missing runtime policy to block release")
  } catch NavigationReleaseError.invalid(let issues) {
    #expect(issues.contains(.missingRuntimePolicy))
    #expect(
      issues.contains(
        .orphanAssetEvidence(
          "RUNTIME_POLICY:test.runtime-policy.release-bundle"
        )
      )
    )
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Navigation release artifact rejects schema and exact evidence coverage drift")
func navigationReleaseArtifactRejectsSchemaAndCoverageDrift() {
  let fixture = navigationReleaseBundleFixture()
  let valid = navigationReleaseArtifact(fixture)
  let missingEvidence = valid.assetEvidence.filter {
    !($0.role == .decisionZone && $0.assetID == "test.zone.loop-2")
  }
  let artifact = NavigationReleaseArtifact(
    schemaVersion: "3.0",
    releaseID: valid.releaseID,
    releasedAt: valid.releasedAt,
    editorCatalogID: valid.editorCatalogID,
    networkSnapshot: valid.networkSnapshot,
    routePlan: valid.routePlan,
    sourceRegistry: valid.sourceRegistry,
    assetEvidence: missingEvidence,
    editorCatalog: valid.editorCatalog,
    runtimePolicy: valid.runtimePolicy,
    matcherCorridor: valid.matcherCorridor,
    decisionZones: valid.decisionZones,
    releasedGuidance: valid.releasedGuidance,
    junctionViews: valid.junctionViews
  )

  do {
    _ = try NavigationRelease(artifact: artifact)
    Issue.record("Expected schema and evidence coverage drift to block release")
  } catch NavigationReleaseError.invalid(let issues) {
    #expect(issues.contains(.invalidArtifactSchemaVersion))
    #expect(
      issues.contains(
        .missingAssetEvidence("DECISION_ZONE:test.zone.loop-2")
      )
    )
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Navigation release artifact requires released evidence and matching junction provenance")
func navigationReleaseArtifactRejectsUnreleasedAndJunctionEvidenceDrift() {
  let fixture = navigationReleaseBundleFixture()
  let valid = navigationReleaseArtifact(fixture)
  let driftedEvidence = valid.assetEvidence.map { evidence in
    if evidence.role == .editorCatalog {
      return NavigationReleaseAssetEvidence(
        role: evidence.role,
        assetID: evidence.assetID,
        state: .officialChecked,
        checkedAt: evidence.checkedAt,
        sourceReferenceIDs: evidence.sourceReferenceIDs
      )
    }
    if evidence.role == .junctionView {
      return NavigationReleaseAssetEvidence(
        role: evidence.role,
        assetID: evidence.assetID,
        state: evidence.state,
        checkedAt: "2026-07-24",
        sourceReferenceIDs: evidence.sourceReferenceIDs
      )
    }
    return evidence
  }
  let artifact = NavigationReleaseArtifact(
    releaseID: valid.releaseID,
    releasedAt: valid.releasedAt,
    editorCatalogID: valid.editorCatalogID,
    networkSnapshot: valid.networkSnapshot,
    routePlan: valid.routePlan,
    sourceRegistry: valid.sourceRegistry,
    assetEvidence: driftedEvidence,
    editorCatalog: valid.editorCatalog,
    runtimePolicy: valid.runtimePolicy,
    matcherCorridor: valid.matcherCorridor,
    decisionZones: valid.decisionZones,
    releasedGuidance: valid.releasedGuidance,
    junctionViews: valid.junctionViews
  )

  do {
    _ = try NavigationRelease(artifact: artifact)
    Issue.record("Expected unreleased and drifted evidence to block release")
  } catch NavigationReleaseError.invalid(let issues) {
    #expect(
      issues.contains(
        .unreleasedAssetEvidence(
          "EDITOR_CATALOG:test.catalog.release-bundle"
        )
      )
    )
    #expect(
      issues.contains(
        .junctionViewEvidenceMismatch("test.junction-view.exit")
      )
    )
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Navigation release evidence cannot postdate its release")
func navigationReleaseArtifactRejectsFutureEvidence() {
  let fixture = navigationReleaseBundleFixture()
  let valid = navigationReleaseArtifact(fixture)
  let futureEvidence = valid.assetEvidence.map { evidence in
    guard evidence.role == .editorCatalog else { return evidence }
    return NavigationReleaseAssetEvidence(
      role: evidence.role,
      assetID: evidence.assetID,
      state: evidence.state,
      checkedAt: "2026-07-25",
      sourceReferenceIDs: evidence.sourceReferenceIDs
    )
  }
  let artifact = NavigationReleaseArtifact(
    releaseID: valid.releaseID,
    releasedAt: "2026-07-24T12:00:00+09:00",
    editorCatalogID: valid.editorCatalogID,
    networkSnapshot: valid.networkSnapshot,
    routePlan: valid.routePlan,
    sourceRegistry: valid.sourceRegistry,
    assetEvidence: futureEvidence,
    editorCatalog: valid.editorCatalog,
    runtimePolicy: valid.runtimePolicy,
    matcherCorridor: valid.matcherCorridor,
    decisionZones: valid.decisionZones,
    releasedGuidance: valid.releasedGuidance,
    junctionViews: valid.junctionViews
  )

  do {
    _ = try NavigationRelease(artifact: artifact)
    Issue.record("Expected future evidence to block navigation release")
  } catch NavigationReleaseError.invalid(let issues) {
    #expect(
      issues.contains(
        .evidenceAfterRelease("EDITOR_CATALOG:test.catalog.release-bundle")
      )
    )
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

struct NavigationReleaseBundleFixture {
  let networkSnapshot: NetworkSnapshot
  let routePlan: RoutePlan
  let editorCatalog: ReviewedRouteEditorCatalog
  let runtimePolicy: ReleasedNavigationRuntimePolicy
  let matcherCorridor: RouteMatcherCorridor
  let decisionZones: [DecisionZoneProgressDefinition]
  let releasedGuidance: [ReleasedGuidanceDefinition]
  let junctionViews: [JunctionViewDefinition]
}

func navigationReleaseArtifact(
  _ fixture: NavigationReleaseBundleFixture
) -> NavigationReleaseArtifact {
  let sourceID = "test.source.junction-view"
  let sourceRegistry = NavigationReleaseSourceRegistry(
    references: [
      NavigationReleaseSourceReference(
        id: sourceID,
        roles: Set(NavigationReleaseAssetRole.allCases),
        authorityName: "Synthetic test authority",
        sourceURL: "https://example.com/test-navigation-release-source",
        contentSHA256: String(repeating: "a", count: 64),
        checkedAt: "2026-07-23",
        licenceIdentifier: "SYNTHETIC_TEST_ONLY"
      )
    ]
  )
  var evidence = [
    NavigationReleaseAssetEvidence(
      role: .editorCatalog,
      assetID: "test.catalog.release-bundle",
      state: .released,
      checkedAt: "2026-07-23",
      sourceReferenceIDs: [sourceID]
    ),
    NavigationReleaseAssetEvidence(
      role: .runtimePolicy,
      assetID: fixture.runtimePolicy.id,
      state: .released,
      checkedAt: "2026-07-23",
      sourceReferenceIDs: [sourceID]
    ),
    NavigationReleaseAssetEvidence(
      role: .matcherCorridor,
      assetID: fixture.matcherCorridor.id,
      state: .released,
      checkedAt: "2026-07-23",
      sourceReferenceIDs: [sourceID]
    ),
  ]
  evidence.append(
    contentsOf: fixture.decisionZones.map {
      NavigationReleaseAssetEvidence(
        role: .decisionZone,
        assetID: $0.id,
        state: .released,
        checkedAt: "2026-07-23",
        sourceReferenceIDs: [sourceID]
      )
    }
  )
  evidence.append(
    contentsOf: fixture.releasedGuidance.map {
      NavigationReleaseAssetEvidence(
        role: .guidance,
        assetID: $0.anchor.promptID,
        state: .released,
        checkedAt: "2026-07-23",
        sourceReferenceIDs: [sourceID]
      )
    }
  )
  evidence.append(
    contentsOf: fixture.junctionViews.map {
      NavigationReleaseAssetEvidence(
        role: .junctionView,
        assetID: $0.id,
        state: .released,
        checkedAt: $0.evidence.checkedAt,
        sourceReferenceIDs: $0.evidence.sourceReferenceIDs
      )
    }
  )

  return NavigationReleaseArtifact(
    releaseID: "test.navigation-release.release-bundle.v1",
    releasedAt: "2026-07-23T12:00:00+09:00",
    editorCatalogID: "test.catalog.release-bundle",
    networkSnapshot: fixture.networkSnapshot,
    routePlan: fixture.routePlan,
    sourceRegistry: sourceRegistry,
    assetEvidence: evidence,
    editorCatalog: fixture.editorCatalog,
    runtimePolicy: fixture.runtimePolicy,
    matcherCorridor: fixture.matcherCorridor,
    decisionZones: fixture.decisionZones,
    releasedGuidance: fixture.releasedGuidance,
    junctionViews: fixture.junctionViews
  )
}

func navigationReleaseBundleFixture() -> NavigationReleaseBundleFixture {
  let networkSnapshot = NetworkSnapshot(
    id: "test.snapshot.release-bundle",
    status: .active,
    effectiveAt: "2026-07-23T00:00:00+09:00"
  )
  let routePlan = RoutePlan(
    id: "test.plan.release-bundle",
    networkSnapshotID: networkSnapshot.id,
    entryFacilityID: "test.entrance",
    exitFacilityID: "test.exit",
    recoveryPolicy: .safeRejoin,
    occurrences: [
      routeOccurrence("test.occurrence.entry", 0, .edge, "test.edge.loop"),
      routeOccurrence(
        "test.occurrence.loop-movement-1",
        1,
        .junctionMovement,
        "test.movement.loop"
      ),
      routeOccurrence("test.occurrence.loop-edge-1", 2, .edge, "test.edge.loop"),
      routeOccurrence(
        "test.occurrence.loop-movement-2",
        3,
        .junctionMovement,
        "test.movement.loop"
      ),
      routeOccurrence("test.occurrence.loop-edge-2", 4, .edge, "test.edge.loop"),
      routeOccurrence(
        "test.occurrence.exit-movement",
        5,
        .junctionMovement,
        "test.movement.exit"
      ),
      routeOccurrence("test.occurrence.exit-edge", 6, .edge, "test.edge.exit"),
    ]
  )
  let editorCatalog = ReviewedRouteEditorCatalog(
    networkSnapshotID: networkSnapshot.id,
    entrances: [
      ReviewedRouteEditorEntrance(
        facilityID: "test.entrance",
        initialEdgeID: "test.edge.loop",
        initialEdgeTollDomainID: "test.toll",
        firstDecisionPointID: "test.decision.loop"
      )
    ],
    decisionPoints: [
      ReviewedRouteEditorDecisionPoint(
        id: "test.decision.loop",
        incomingApproachID: "test.approach.loop",
        junctionComplexID: "test.junction.loop",
        choices: [
          ReviewedRouteEditorChoice(
            id: "test.choice.loop",
            movementID: "test.movement.loop",
            movementTollDomainID: "test.toll",
            outgoingEdgeID: "test.edge.loop",
            outgoingEdgeTollDomainID: "test.toll",
            destination: .decisionPoint("test.decision.loop")
          ),
          ReviewedRouteEditorChoice(
            id: "test.choice.exit",
            movementID: "test.movement.exit",
            movementTollDomainID: "test.toll",
            outgoingEdgeID: "test.edge.exit",
            outgoingEdgeTollDomainID: "test.toll",
            destination: .exitFacility("test.exit")
          ),
        ]
      )
    ]
  )
  let runtimePolicy = ReleasedNavigationRuntimePolicy(
    id: "test.runtime-policy.release-bundle",
    networkSnapshotID: networkSnapshot.id,
    routePlanID: routePlan.id,
    entryTransition: EntryTransition(
      facilityID: routePlan.entryFacilityID,
      directedEdgeIDs: [
        "test.entry-transition.surface",
        "test.entry-transition.ramp",
      ],
      firstRouteOccurrenceID: routePlan.occurrences.first?.id
    ),
    recoveryCandidates: [
      RecoveryCandidate(
        targetOccurrenceID: "test.occurrence.loop-edge-2",
        recoveryOccurrenceIDs: [
          "test.recovery.release-bundle.movement",
          "test.recovery.release-bundle.edge",
        ],
        isReleased: true,
        staysInAllowedTollDomain: true
      )
    ],
    egressOptions: [
      EgressOption(
        id: "test.egress.release-bundle",
        firstEligibleOccurrenceID: "test.occurrence.loop-edge-2",
        exitFacilityID: routePlan.exitFacilityID,
        egressOccurrenceIDs: [
          "test.egress.release-bundle.movement",
          "test.egress.release-bundle.edge",
        ],
        isReleased: true
      )
    ]
  )
  let matcherCorridor = RouteMatcherCorridor(
    id: "test.corridor.release-bundle",
    networkSnapshotID: networkSnapshot.id,
    routePlanID: routePlan.id,
    edges: [
      matcherEdge(
        "test.entry-transition.surface",
        139.7590,
        139.7595,
        successors: ["test.entry-transition.ramp"]
      ),
      matcherEdge(
        "test.entry-transition.ramp",
        139.7595,
        139.7600,
        successors: ["test.edge.loop"]
      ),
      matcherEdge(
        "test.edge.loop",
        139.7600,
        139.7610,
        successors: ["test.edge.loop-movement", "test.edge.exit-movement"]
      ),
      matcherEdge(
        "test.edge.loop-movement",
        139.7610,
        139.7612,
        successors: ["test.edge.loop"]
      ),
      matcherEdge(
        "test.edge.exit-movement",
        139.7610,
        139.7613,
        successors: ["test.edge.exit"]
      ),
      matcherEdge("test.edge.exit", 139.7613, 139.7620),
    ],
    occurrences: [
      matcherOccurrence("test.occurrence.entry", 0, "test.edge.loop"),
      matcherOccurrence(
        "test.occurrence.loop-movement-1",
        1,
        "test.edge.loop-movement"
      ),
      matcherOccurrence("test.occurrence.loop-edge-1", 2, "test.edge.loop"),
      matcherOccurrence(
        "test.occurrence.loop-movement-2",
        3,
        "test.edge.loop-movement"
      ),
      matcherOccurrence("test.occurrence.loop-edge-2", 4, "test.edge.loop"),
      matcherOccurrence(
        "test.occurrence.exit-movement",
        5,
        "test.edge.exit-movement"
      ),
      matcherOccurrence("test.occurrence.exit-edge", 6, "test.edge.exit"),
    ]
  )
  let decisionZones = [
    decisionZone(
      "test.zone.loop-1",
      "test.occurrence.loop-movement-1",
      networkSnapshot.id,
      routePlan.id
    ),
    decisionZone(
      "test.zone.loop-2",
      "test.occurrence.loop-movement-2",
      networkSnapshot.id,
      routePlan.id
    ),
    decisionZone(
      "test.zone.exit",
      "test.occurrence.exit-movement",
      networkSnapshot.id,
      routePlan.id
    ),
  ]
  let junctionView = releasedJunctionView(networkSnapshotID: networkSnapshot.id)
  let releasedGuidance = [
    releasedGuidanceDefinition(
      anchorOccurrenceID: "test.occurrence.entry",
      movementOccurrenceID: "test.occurrence.loop-movement-1",
      decisionZoneID: "test.zone.loop-1",
      promptID: "test.prompt.loop-1"
    ),
    releasedGuidanceDefinition(
      anchorOccurrenceID: "test.occurrence.loop-edge-1",
      movementOccurrenceID: "test.occurrence.loop-movement-2",
      decisionZoneID: "test.zone.loop-2",
      promptID: "test.prompt.loop-2"
    ),
    releasedGuidanceDefinition(
      anchorOccurrenceID: "test.occurrence.loop-edge-2",
      movementOccurrenceID: "test.occurrence.exit-movement",
      decisionZoneID: "test.zone.exit",
      promptID: "test.prompt.exit",
      junctionView: junctionView
    ),
  ]
  return NavigationReleaseBundleFixture(
    networkSnapshot: networkSnapshot,
    routePlan: routePlan,
    editorCatalog: editorCatalog,
    runtimePolicy: runtimePolicy,
    matcherCorridor: matcherCorridor,
    decisionZones: decisionZones,
    releasedGuidance: releasedGuidance,
    junctionViews: [junctionView]
  )
}

private func routeOccurrence(
  _ id: String,
  _ index: Int,
  _ kind: RouteOccurrence.Kind,
  _ entityID: String
) -> RouteOccurrence {
  RouteOccurrence(
    id: id,
    index: index,
    kind: kind,
    entityID: entityID,
    tollDomainID: "test.toll"
  )
}

private func matcherEdge(
  _ id: String,
  _ startLongitude: Double,
  _ endLongitude: Double,
  successors: Set<String> = []
) -> RouteMatcherDirectedEdge {
  RouteMatcherDirectedEdge(
    id: id,
    coordinates: [
      MatcherCoordinate(latitude: 35.68, longitude: startLongitude),
      MatcherCoordinate(latitude: 35.68, longitude: endLongitude),
    ],
    successorEdgeIDs: successors
  )
}

private func matcherOccurrence(
  _ id: String,
  _ index: Int,
  _ directedEdgeID: String
) -> RouteMatcherOccurrence {
  RouteMatcherOccurrence(id: id, index: index, directedEdgeID: directedEdgeID)
}

private func decisionZone(
  _ id: String,
  _ movementOccurrenceID: String,
  _ networkSnapshotID: String,
  _ routePlanID: String
) -> DecisionZoneProgressDefinition {
  DecisionZoneProgressDefinition(
    id: id,
    networkSnapshotID: networkSnapshotID,
    routePlanID: routePlanID,
    movementOccurrenceID: movementOccurrenceID,
    entryOffsetMeters: 5
  )
}

private func releasedGuidanceDefinition(
  anchorOccurrenceID: String,
  movementOccurrenceID: String,
  decisionZoneID: String,
  promptID: String,
  junctionView: JunctionViewDefinition? = nil
) -> ReleasedGuidanceDefinition {
  ReleasedGuidanceDefinition(
    anchor: GuidanceAnchorDefinition(
      occurrenceID: anchorOccurrenceID,
      anchorID: "PREPARE",
      promptID: promptID
    ),
    triggerDistanceMeters: 500,
    frameTemplate: GuidanceFrameTemplate(
      movementOccurrenceID: movementOccurrenceID,
      decisionZoneID: decisionZoneID,
      stage: .prepare,
      decisionPointNameJapanese: "テストJCT",
      localizedDecisionPointNames: [
        .japanese: "テストJCT",
        .simplifiedChinese: "测试 JCT",
        .english: "Test JCT",
      ],
      maneuver: .keepLeft,
      lanePreparation: .useLeftLanes,
      presentationSource: releaseGuidancePresentationSource(
        junctionView: junctionView
      )
    )
  )
}

private func releaseGuidancePresentationSource(
  junctionView: JunctionViewDefinition?
) -> GuidancePresentationSource {
  let sign = "B 湾岸線・横浜方面"
  return GuidancePresentationSource(
    routeShields: ["B"],
    japaneseSignText: sign,
    localizedContent: [
      .japanese: releaseLocalizedContent(
        display: "左側を進む",
        spoken: "左側を進んでください",
        spokenForm: "ビー",
        sign: sign
      ),
      .simplifiedChinese: releaseLocalizedContent(
        display: "保持左侧",
        spoken: "请保持左侧",
        spokenForm: "B 路线",
        sign: sign
      ),
      .english: releaseLocalizedContent(
        display: "Keep left",
        spoken: "Keep left",
        spokenForm: "Route B",
        sign: sign
      ),
    ],
    junctionView: junctionView
  )
}

private func releaseLocalizedContent(
  display: String,
  spoken: String,
  spokenForm: String,
  sign: String
) -> LocalizedGuidanceContent {
  LocalizedGuidanceContent(
    displayText: display,
    spokenText: spoken,
    spokenForms: ["B": spokenForm],
    preservedJapaneseSignText: sign
  )
}

private func releasedJunctionView(
  networkSnapshotID: String,
  sourceReferenceIDs: [String] = ["test.source.junction-view"]
) -> JunctionViewDefinition {
  JunctionViewDefinition(
    id: "test.junction-view.exit",
    networkSnapshotID: networkSnapshotID,
    movementOccurrenceID: "test.occurrence.exit-movement",
    paths: [
      JunctionViewPath(
        id: "test.path.approach",
        role: .approach,
        points: [
          JunctionViewPoint(x: 0.5, y: 1),
          JunctionViewPoint(x: 0.5, y: 0.5),
        ]
      ),
      JunctionViewPath(
        id: "test.path.selected",
        role: .selected,
        points: [
          JunctionViewPoint(x: 0.5, y: 0.5),
          JunctionViewPoint(x: 0.2, y: 0),
        ]
      ),
      JunctionViewPath(
        id: "test.path.alternative",
        role: .alternative,
        points: [
          JunctionViewPoint(x: 0.5, y: 0.5),
          JunctionViewPoint(x: 0.8, y: 0),
        ]
      ),
    ],
    laneLayout: JunctionViewLaneLayout(
      laneCount: 3,
      allowedLaneIndices: [0, 1],
      preferredLaneIndices: [0]
    ),
    japaneseSignText: "B 湾岸線・横浜方面",
    routeShields: ["B"],
    evidence: JunctionViewEvidence(
      state: .released,
      checkedAt: "2026-07-23",
      sourceReferenceIDs: sourceReferenceIDs
    )
  )
}
