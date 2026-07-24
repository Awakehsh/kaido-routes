import KaidoDomain
import KaidoNavigation
import KaidoSurfaceRouting
import Testing

@Test("Released surface access is exact RoutePlan policy with provenance coverage")
func releasedSurfaceAccessRequiresExactPolicyAndEvidence() throws {
  let fixture = navigationReleaseBundleFixture()
  let definition = releasedSurfaceAccessDefinition(fixture)
  let artifact = navigationReleaseArtifact(
    fixture,
    surfaceAccessDefinition: definition
  )

  let release = try NavigationRelease(artifact: artifact)
  #expect(release.bundle.surfaceAccessDefinition == definition)
  #expect(
    release.assetEvidence.contains {
      $0.role == .surfaceAccess && $0.assetID == definition.id
    }
  )

  let missingEvidence = artifact.assetEvidence.filter {
    !($0.role == .surfaceAccess && $0.assetID == definition.id)
  }
  let uncoveredArtifact = NavigationReleaseArtifact(
    releaseID: artifact.releaseID,
    releasedAt: artifact.releasedAt,
    editorCatalogID: artifact.editorCatalogID,
    networkSnapshot: artifact.networkSnapshot,
    routePlan: artifact.routePlan,
    sourceRegistry: artifact.sourceRegistry,
    assetEvidence: missingEvidence,
    editorCatalog: artifact.editorCatalog,
    editorPresentationCatalog: artifact.editorPresentationCatalog,
    runtimePolicy: artifact.runtimePolicy,
    matcherCorridor: artifact.matcherCorridor,
    decisionZones: artifact.decisionZones,
    releasedGuidance: artifact.releasedGuidance,
    junctionViews: artifact.junctionViews,
    surfaceAccessDefinition: definition
  )
  do {
    _ = try NavigationRelease(artifact: uncoveredArtifact)
    Issue.record("Expected missing surface-access evidence to block release")
  } catch NavigationReleaseError.invalid(let issues) {
    #expect(
      issues.contains(
        .missingAssetEvidence("SURFACE_ACCESS:\(definition.id)")
      )
    )
  }
}

@Test("Surface access identity drift blocks the whole navigation bundle")
func releasedSurfaceAccessRejectsIdentityDrift() {
  let fixture = navigationReleaseBundleFixture()
  let valid = releasedSurfaceAccessDefinition(fixture)
  let drifted = ReleasedSurfaceAccessDefinition(
    id: valid.id,
    routePlanID: "other.plan",
    approachPolicy: SurfaceApproachPolicy(
      networkSnapshotID: "other.snapshot",
      entranceFacilityID: "other.entrance",
      allowedJoinOccurrenceIDs: valid.approachPolicy.allowedJoinOccurrenceIDs,
      destinationAnchor: valid.approachPolicy.destinationAnchor,
      entryTransitionDirectedEdgeIDs: ["other.transition"],
      compatibleExitFacilityIDs: ["other.exit"],
      forbiddenEarlyExpresswayEdgeIDs:
        valid.approachPolicy.forbiddenEarlyExpresswayEdgeIDs,
      forbiddenTollDomainIDs: valid.approachPolicy.forbiddenTollDomainIDs
    ),
    allowedFinishPolicies: valid.allowedFinishPolicies
  )

  do {
    _ = try NavigationReleaseBundle(
      networkSnapshot: fixture.networkSnapshot,
      routePlan: fixture.routePlan,
      editorCatalog: fixture.editorCatalog,
      editorPresentationCatalog: fixture.editorPresentationCatalog,
      runtimePolicy: fixture.runtimePolicy,
      matcherCorridor: fixture.matcherCorridor,
      decisionZones: fixture.decisionZones,
      releasedGuidance: fixture.releasedGuidance,
      junctionViews: fixture.junctionViews,
      surfaceAccessDefinition: drifted
    )
    Issue.record("Expected surface access identity drift to block the bundle")
  } catch NavigationReleaseBundleError.invalid(let issues) {
    let details = issues.compactMap { issue -> [ReleasedSurfaceAccessIssue]? in
      guard case .invalidSurfaceAccessDefinition(let details) = issue else {
        return nil
      }
      return details
    }.flatMap { $0 }
    #expect(details.contains(.networkSnapshotMismatch))
    #expect(details.contains(.routePlanMismatch))
    #expect(details.contains(.entranceMismatch))
    #expect(details.contains(.entryTransitionMismatch))
    #expect(details.contains(.incompatibleExit))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Accepted surface candidate composes around the exact released RoutePlan")
func journeyPlanPreservesAcceptedSurfacePathOccurrences() throws {
  let fixture = navigationReleaseBundleFixture()
  let definition = releasedSurfaceAccessDefinition(fixture)
  let release = try productRelease(
    fixture,
    surfaceAccessDefinition: definition
  )
  let input = acceptedSurfaceAccessInput(fixture, definition: definition)

  let plan = try JourneyPlanCompiler.surfaceAccess(
    release: release,
    request: input.request,
    candidate: input.candidate,
    inspection: input.inspection,
    expectedProviderID: input.candidate.providerID,
    finishPolicy: .fixedExit
  )

  #expect(plan.productReleaseID == release.releaseID)
  #expect(plan.navigationReleaseID == release.navigation.releaseID)
  #expect(plan.networkSnapshotID == fixture.networkSnapshot.id)
  #expect(plan.routePlanID == fixture.routePlan.id)
  #expect(plan.entryTransition == fixture.runtimePolicy.entryTransition)
  #expect(plan.precomputedEgressOptions == fixture.runtimePolicy.egressOptions)
  #expect(plan.selectedEgressOptionID == fixture.runtimePolicy.egressOptions.first?.id)
  #expect(
    plan.accessLeg?.directedEdgeIDs
      == ["test.surface.edge-a", "test.surface.edge-b", "test.surface.edge-a"]
  )
  #expect(plan.accessLeg?.joinOccurrenceID == fixture.routePlan.occurrences.first?.id)
  #expect(plan.initialPhase == .planning)
}

@Test("Rejected, ambiguous, or provider-drifted candidates cannot create a JourneyPlan")
func journeyPlanRejectsSurfaceAuthorityDrift() throws {
  let fixture = navigationReleaseBundleFixture()
  let definition = releasedSurfaceAccessDefinition(fixture)
  let release = try productRelease(
    fixture,
    surfaceAccessDefinition: definition
  )
  let input = acceptedSurfaceAccessInput(fixture, definition: definition)
  let providerDrift = SurfaceRouteCandidate(
    id: input.candidate.id,
    providerID: "other.provider",
    coordinates: input.candidate.coordinates,
    steps: input.candidate.steps,
    distanceMeters: input.candidate.distanceMeters,
    expectedTravelTimeSeconds: input.candidate.expectedTravelTimeSeconds,
    selectedPathEvidence: input.candidate.selectedPathEvidence
  )
  do {
    _ = try JourneyPlanCompiler.surfaceAccess(
      release: release,
      request: input.request,
      candidate: providerDrift,
      inspection: input.inspection,
      expectedProviderID: input.candidate.providerID,
      finishPolicy: .finishOnRequest
    )
    Issue.record("Expected provider drift to block JourneyPlan creation")
  } catch JourneyPlanCompilerError.candidateRejected(let gates) {
    #expect(
      gates.contains {
        $0.gate == .honestProviderStatus && $0.status == .fail
      }
    )
  }

  let snapshotDriftInspection = SurfaceCandidateInspection(
    networkSnapshotID: "other.snapshot",
    anchorBinding: input.inspection.anchorBinding,
    geometryBindingIsUnambiguous: true,
    expresswayEdgeIDsBeforeEntry: [],
    crossedTollDomainIDs: [],
    resolvedPathEdgeIDs: input.inspection.resolvedPathEdgeIDs
  )
  do {
    _ = try JourneyPlanCompiler.surfaceAccess(
      release: release,
      request: input.request,
      candidate: input.candidate,
      inspection: snapshotDriftInspection,
      expectedProviderID: input.candidate.providerID,
      finishPolicy: .finishOnRequest
    )
    Issue.record("Expected inspection snapshot drift to block JourneyPlan creation")
  } catch JourneyPlanCompilerError.inspectionSnapshotMismatch {
    // Expected.
  }

  let earlyExpresswayInspection = SurfaceCandidateInspection(
    networkSnapshotID: fixture.networkSnapshot.id,
    anchorBinding: input.inspection.anchorBinding,
    geometryBindingIsUnambiguous: true,
    expresswayEdgeIDsBeforeEntry: ["test.expressway.forbidden"],
    crossedTollDomainIDs: [],
    resolvedPathEdgeIDs: input.inspection.resolvedPathEdgeIDs
  )
  do {
    _ = try JourneyPlanCompiler.surfaceAccess(
      release: release,
      request: input.request,
      candidate: input.candidate,
      inspection: earlyExpresswayInspection,
      expectedProviderID: input.candidate.providerID,
      finishPolicy: .finishOnRequest
    )
    Issue.record("Expected early expressway entry to block JourneyPlan creation")
  } catch JourneyPlanCompilerError.candidateRejected(let gates) {
    #expect(
      gates.contains {
        $0.gate == .noEarlyExpressway && $0.status == .fail
      }
    )
  }

  let ambiguousInspection = SurfaceCandidateInspection(
    networkSnapshotID: fixture.networkSnapshot.id,
    anchorBinding: input.inspection.anchorBinding,
    geometryBindingIsUnambiguous: false,
    expresswayEdgeIDsBeforeEntry: [],
    crossedTollDomainIDs: [],
    ambiguousDirectedEdgeIDs: ["test.surface.edge-a"],
    resolvedPathEdgeIDs: input.inspection.resolvedPathEdgeIDs
  )
  do {
    _ = try JourneyPlanCompiler.surfaceAccess(
      release: release,
      request: input.request,
      candidate: input.candidate,
      inspection: ambiguousInspection,
      expectedProviderID: input.candidate.providerID,
      finishPolicy: .finishOnRequest
    )
    Issue.record("Expected ambiguous geometry to block JourneyPlan creation")
  } catch JourneyPlanCompilerError.candidateRejected(let gates) {
    #expect(
      gates.contains {
        $0.gate == .geometryBindable && $0.status == .fail
      }
    )
  }

  let evidenceDrift = SurfaceRouteCandidate(
    id: input.candidate.id,
    providerID: input.candidate.providerID,
    coordinates: input.candidate.coordinates,
    steps: input.candidate.steps,
    distanceMeters: input.candidate.distanceMeters,
    expectedTravelTimeSeconds: input.candidate.expectedTravelTimeSeconds,
    selectedPathEvidence: SurfaceSelectedPathEvidence(
      networkSnapshotID: fixture.networkSnapshot.id,
      providerDatasetID: "test.dataset",
      directedEdgeIDs: ["test.surface.other"]
    )
  )
  do {
    _ = try JourneyPlanCompiler.surfaceAccess(
      release: release,
      request: input.request,
      candidate: evidenceDrift,
      inspection: input.inspection,
      expectedProviderID: input.candidate.providerID,
      finishPolicy: .finishOnRequest
    )
    Issue.record("Expected selected-path evidence drift to block JourneyPlan creation")
  } catch JourneyPlanCompilerError.selectedPathEvidenceMismatch {
    // Expected.
  }
}

@Test("Surface access cannot be injected into a release that omitted it")
func journeyPlanRequiresReleasedSurfaceAccess() throws {
  let fixture = navigationReleaseBundleFixture()
  let definition = releasedSurfaceAccessDefinition(fixture)
  let release = try KaidoProductRelease(
    artifact: KaidoProductReleaseArtifact(
      releaseID: "test.product-release.route-only",
      releasedAt: "2026-07-24T12:00:00+09:00",
      navigationRelease: navigationReleaseArtifact(fixture),
      routeAtlasRelease: productRouteAtlasArtifact(
        fixture,
        includeIncomingApproach: true
      )
    )
  )
  let input = acceptedSurfaceAccessInput(fixture, definition: definition)

  do {
    _ = try JourneyPlanCompiler.surfaceAccess(
      release: release,
      request: input.request,
      candidate: input.candidate,
      inspection: input.inspection,
      expectedProviderID: input.candidate.providerID,
      finishPolicy: .finishOnRequest
    )
    Issue.record("Expected an omitted release asset to block surface access")
  } catch JourneyPlanCompilerError.surfaceAccessNotReleased {
    // Expected.
  }
}

@Test("Return-near-origin remains unavailable without a reviewed surface egress")
func journeyPlanRequiresReleasedReturnEgress() throws {
  let fixture = navigationReleaseBundleFixture()
  let definition = releasedSurfaceAccessDefinition(fixture)
  let release = try productRelease(
    fixture,
    surfaceAccessDefinition: definition
  )
  let input = acceptedSurfaceAccessInput(fixture, definition: definition)

  do {
    _ = try JourneyPlanCompiler.surfaceAccess(
      release: release,
      request: input.request,
      candidate: input.candidate,
      inspection: input.inspection,
      expectedProviderID: input.candidate.providerID,
      finishPolicy: .returnNearOrigin
    )
    Issue.record("Expected missing return egress to fail closed")
  } catch JourneyPlanCompilerError.surfaceEgressNotReleased {
    // Expected.
  }
}

private struct SurfaceAccessInput {
  let request: SurfaceRouteRequest
  let candidate: SurfaceRouteCandidate
  let inspection: SurfaceCandidateInspection
}

private func releasedSurfaceAccessDefinition(
  _ fixture: NavigationReleaseBundleFixture
) -> ReleasedSurfaceAccessDefinition {
  ReleasedSurfaceAccessDefinition(
    id: "test.surface-access.release-bundle",
    routePlanID: fixture.routePlan.id,
    approachPolicy: SurfaceApproachPolicy(
      networkSnapshotID: fixture.networkSnapshot.id,
      entranceFacilityID: fixture.routePlan.entryFacilityID,
      allowedJoinOccurrenceIDs: [fixture.routePlan.occurrences[0].id],
      destinationAnchor: DirectedApproachAnchor(
        id: "test.anchor.release-bundle",
        coordinate: SurfaceCoordinate(latitude: 35.68, longitude: 139.759),
        directedSurfaceEdgeID: "test.surface.edge-b",
        expectedBearingDegrees: 45,
        bearingToleranceDegrees: 20,
        maxTerminalDistanceMeters: 12
      ),
      entryTransitionDirectedEdgeIDs:
        fixture.runtimePolicy.entryTransition.directedEdgeIDs,
      compatibleExitFacilityIDs: [fixture.routePlan.exitFacilityID],
      forbiddenEarlyExpresswayEdgeIDs: ["test.expressway.forbidden"],
      forbiddenTollDomainIDs: ["test.toll.forbidden"]
    ),
    allowedFinishPolicies: [
      .fixedExit,
      .finishOnRequest,
      .returnNearOrigin,
    ]
  )
}

private func acceptedSurfaceAccessInput(
  _ fixture: NavigationReleaseBundleFixture,
  definition: ReleasedSurfaceAccessDefinition
) -> SurfaceAccessInput {
  let directedEdgeIDs = [
    "test.surface.edge-a",
    "test.surface.edge-b",
    "test.surface.edge-a",
  ]
  let request = SurfaceRouteRequest(
    id: "test.surface-request.release-bundle",
    originID: "test.origin.release-bundle",
    origin: SurfaceCoordinate(latitude: 35.675, longitude: 139.754),
    entranceFacilityID: fixture.routePlan.entryFacilityID,
    selectedJoinOccurrenceID: fixture.routePlan.occurrences[0].id,
    destinationAnchor: definition.approachPolicy.destinationAnchor
  )
  let candidate = SurfaceRouteCandidate(
    id: "test.surface-candidate.release-bundle",
    providerID: "test.provider",
    coordinates: [
      request.origin,
      definition.approachPolicy.destinationAnchor.coordinate,
    ],
    steps: [],
    distanceMeters: 900,
    expectedTravelTimeSeconds: 240,
    selectedPathEvidence: SurfaceSelectedPathEvidence(
      networkSnapshotID: fixture.networkSnapshot.id,
      providerDatasetID: "test.dataset",
      directedEdgeIDs: directedEdgeIDs
    )
  )
  let inspection = SurfaceCandidateInspection(
    networkSnapshotID: fixture.networkSnapshot.id,
    anchorBinding: AnchorBindingObservation(
      anchorID: definition.approachPolicy.destinationAnchor.id,
      directedSurfaceEdgeID:
        definition.approachPolicy.destinationAnchor.directedSurfaceEdgeID,
      terminalDistanceMeters: 4,
      terminalBearingDegrees: 45
    ),
    geometryBindingIsUnambiguous: true,
    expresswayEdgeIDsBeforeEntry: [],
    crossedTollDomainIDs: [],
    resolvedPathEdgeIDs: directedEdgeIDs
  )
  return SurfaceAccessInput(
    request: request,
    candidate: candidate,
    inspection: inspection
  )
}

private func productRelease(
  _ fixture: NavigationReleaseBundleFixture,
  surfaceAccessDefinition: ReleasedSurfaceAccessDefinition
) throws -> KaidoProductRelease {
  try KaidoProductRelease(
    artifact: KaidoProductReleaseArtifact(
      releaseID: "test.product-release.surface-access",
      releasedAt: "2026-07-24T12:00:00+09:00",
      navigationRelease: navigationReleaseArtifact(
        fixture,
        surfaceAccessDefinition: surfaceAccessDefinition
      ),
      routeAtlasRelease: productRouteAtlasArtifact(
        fixture,
        includeIncomingApproach: true
      )
    )
  )
}
