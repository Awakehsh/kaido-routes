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
  let encoded = try NavigationReleaseArtifactCodec.encode(artifact)
  let encodedJSON = try #require(String(data: encoded, encoding: .utf8))
  #expect(encodedJSON.contains("\"provider_identity\""))
  #expect(encodedJSON.contains("\"test.surface-build.release-bundle\""))
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
    providerIdentity: valid.providerIdentity,
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

@Test("Surface release requires one reviewed release-candidate provider build")
func releasedSurfaceAccessRejectsUnreviewedProviderBuild() {
  let fixture = navigationReleaseBundleFixture()
  let valid = releasedSurfaceAccessDefinition(fixture)
  let invalidProvider = SurfaceRouteProviderReleaseIdentity(
    providerID: valid.providerIdentity.providerID,
    adapterVersion: valid.providerIdentity.adapterVersion,
    providerVersion: valid.providerIdentity.providerVersion,
    networkSnapshotID: "other.snapshot",
    providerDatasetID: valid.providerIdentity.providerDatasetID,
    buildManifestID: valid.providerIdentity.buildManifestID,
    engineBuildID: valid.providerIdentity.engineBuildID,
    manifestValidationProfile: .structural,
    manifestIntendedUse: .labOnly,
    dataReviewStatus: .reviewRequired
  )
  let definition = ReleasedSurfaceAccessDefinition(
    id: valid.id,
    routePlanID: valid.routePlanID,
    providerIdentity: invalidProvider,
    approachPolicy: valid.approachPolicy,
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
      surfaceAccessDefinition: definition
    )
    Issue.record("Expected an unreviewed provider build to block release")
  } catch NavigationReleaseBundleError.invalid(let issues) {
    let details = issues.compactMap { issue -> [ReleasedSurfaceAccessIssue]? in
      guard case .invalidSurfaceAccessDefinition(let details) = issue else {
        return nil
      }
      return details
    }.flatMap { $0 }
    #expect(details.contains(.invalidProviderIdentity))
    #expect(details.contains(.providerSnapshotMismatch))
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
    providerIdentity: definition.providerIdentity,
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
  #expect(plan.initialPhase == .approachToEntry)
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
      providerIdentity: definition.providerIdentity,
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
      providerIdentity: definition.providerIdentity,
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
      providerIdentity: definition.providerIdentity,
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
      providerIdentity: definition.providerIdentity,
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
      providerIdentity: definition.providerIdentity,
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
      providerIdentity: definition.providerIdentity,
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
      providerIdentity: definition.providerIdentity,
      finishPolicy: .returnNearOrigin
    )
    Issue.record("Expected missing return egress to fail closed")
  } catch JourneyPlanCompilerError.surfaceEgressNotReleased {
    // Expected.
  }
}

@Test("Released surface planner runs provider, graph inspection, and compiler as one gate")
func releasedSurfaceAccessPlannerBuildsOnlyOneReadyPlan() async throws {
  let fixture = navigationReleaseBundleFixture()
  let definition = releasedSurfaceAccessDefinition(fixture)
  let release = try productRelease(
    fixture,
    surfaceAccessDefinition: definition
  )
  let input = acceptedSurfaceAccessInput(fixture, definition: definition)
  let planner = ReleasedSurfaceAccessPlanner(
    provider: StubReleaseBoundSurfaceProvider(
      releaseIdentity: definition.providerIdentity,
      response: .success([input.candidate])
    ),
    inspector: StubSurfaceApproachInspector(
      inspection: input.inspection
    )
  )

  let result = try await planner.plan(
    release: release,
    request: input.request,
    finishPolicy: .finishOnRequest
  )

  #expect(result.disposition == .ready)
  #expect(result.selectedPlan?.accessLeg?.candidateID == input.candidate.id)
  #expect(
    result.selectedPlan?.accessLeg?.providerIdentity
      == definition.providerIdentity
  )
  #expect(result.evaluations.count == 1)
  #expect(result.evaluations[0].isAccepted)
  #expect(result.compilationFailures.isEmpty)
}

@Test("Provider alternative order cannot silently select a surface journey")
func releasedSurfaceAccessPlannerRequiresExplicitAlternativeSelection() async throws {
  let fixture = navigationReleaseBundleFixture()
  let definition = releasedSurfaceAccessDefinition(fixture)
  let release = try productRelease(
    fixture,
    surfaceAccessDefinition: definition
  )
  let input = acceptedSurfaceAccessInput(fixture, definition: definition)
  let candidateB = SurfaceRouteCandidate(
    id: "test.surface-candidate.b",
    providerID: input.candidate.providerID,
    coordinates: input.candidate.coordinates,
    steps: input.candidate.steps,
    distanceMeters: input.candidate.distanceMeters + 100,
    expectedTravelTimeSeconds:
      input.candidate.expectedTravelTimeSeconds + 30,
    selectedPathEvidence: input.candidate.selectedPathEvidence
  )
  let candidateA = SurfaceRouteCandidate(
    id: "test.surface-candidate.a",
    providerID: input.candidate.providerID,
    coordinates: input.candidate.coordinates,
    steps: input.candidate.steps,
    distanceMeters: input.candidate.distanceMeters,
    expectedTravelTimeSeconds: input.candidate.expectedTravelTimeSeconds,
    selectedPathEvidence: input.candidate.selectedPathEvidence
  )
  let planner = ReleasedSurfaceAccessPlanner(
    provider: StubReleaseBoundSurfaceProvider(
      releaseIdentity: definition.providerIdentity,
      response: .success([candidateB, candidateA])
    ),
    inspector: StubSurfaceApproachInspector(
      inspection: input.inspection
    )
  )

  let result = try await planner.plan(
    release: release,
    request: input.request,
    finishPolicy: .finishOnRequest
  )

  #expect(result.disposition == .selectionRequired)
  #expect(result.selectedPlan == nil)
  #expect(
    result.options.map(\.candidateID)
      == ["test.surface-candidate.a", "test.surface-candidate.b"]
  )
  #expect(Set(result.options.map(\.journeyPlan.id)).count == 2)
}

@Test("Surface planner keeps provider failure and malformed success explicit")
func releasedSurfaceAccessPlannerDisclosesProviderResponseFailures() async throws {
  let fixture = navigationReleaseBundleFixture()
  let definition = releasedSurfaceAccessDefinition(fixture)
  let release = try productRelease(
    fixture,
    surfaceAccessDefinition: definition
  )
  let input = acceptedSurfaceAccessInput(fixture, definition: definition)
  let failure = SurfaceProviderFailure(
    kind: .network,
    providerErrorCode: "TEST_NETWORK"
  )
  let failedPlanner = ReleasedSurfaceAccessPlanner(
    provider: StubReleaseBoundSurfaceProvider(
      releaseIdentity: definition.providerIdentity,
      response: .failure(failure)
    ),
    inspector: StubSurfaceApproachInspector(
      inspection: input.inspection
    )
  )
  let failed = try await failedPlanner.plan(
    release: release,
    request: input.request,
    finishPolicy: .finishOnRequest
  )
  #expect(failed.disposition == .providerFailure)
  #expect(failed.providerFailure == failure)
  #expect(failed.selectedPlan == nil)

  let emptyPlanner = ReleasedSurfaceAccessPlanner(
    provider: StubReleaseBoundSurfaceProvider(
      releaseIdentity: definition.providerIdentity,
      response: .success([])
    ),
    inspector: StubSurfaceApproachInspector(
      inspection: input.inspection
    )
  )
  let empty = try await emptyPlanner.plan(
    release: release,
    request: input.request,
    finishPolicy: .finishOnRequest
  )
  #expect(empty.disposition == .invalidResponse)
  #expect(
    empty.evaluations[0].hardGates.contains {
      $0.reasonCodes.contains("EMPTY_SUCCESS_RESPONSE")
    }
  )
}

@Test("Surface planner refuses provider build drift before a request")
func releasedSurfaceAccessPlannerRejectsProviderIdentityDrift() async throws {
  let fixture = navigationReleaseBundleFixture()
  let definition = releasedSurfaceAccessDefinition(fixture)
  let release = try productRelease(
    fixture,
    surfaceAccessDefinition: definition
  )
  let input = acceptedSurfaceAccessInput(fixture, definition: definition)
  let driftedIdentity = SurfaceRouteProviderReleaseIdentity(
    providerID: definition.providerIdentity.providerID,
    adapterVersion: "other.adapter",
    providerVersion: definition.providerIdentity.providerVersion,
    networkSnapshotID: definition.providerIdentity.networkSnapshotID,
    providerDatasetID: definition.providerIdentity.providerDatasetID,
    buildManifestID: definition.providerIdentity.buildManifestID,
    engineBuildID: definition.providerIdentity.engineBuildID,
    manifestValidationProfile: .releaseCandidate,
    manifestIntendedUse: .releaseCandidate,
    dataReviewStatus: .derivedFixtureReviewed
  )
  let planner = ReleasedSurfaceAccessPlanner(
    provider: StubReleaseBoundSurfaceProvider(
      releaseIdentity: driftedIdentity,
      response: .success([input.candidate])
    ),
    inspector: StubSurfaceApproachInspector(
      inspection: input.inspection
    )
  )

  await #expect(throws: JourneyPlanCompilerError.providerIdentityMismatch) {
    _ = try await planner.plan(
      release: release,
      request: input.request,
      finishPolicy: .finishOnRequest
    )
  }
}

@Test("Selected-path dataset drift cannot escape an accepted hard-gate result")
func releasedSurfaceAccessPlannerRejectsDatasetDriftAtCompilation() async throws {
  let fixture = navigationReleaseBundleFixture()
  let definition = releasedSurfaceAccessDefinition(fixture)
  let release = try productRelease(
    fixture,
    surfaceAccessDefinition: definition
  )
  let input = acceptedSurfaceAccessInput(fixture, definition: definition)
  let driftedCandidate = SurfaceRouteCandidate(
    id: input.candidate.id,
    providerID: input.candidate.providerID,
    coordinates: input.candidate.coordinates,
    steps: input.candidate.steps,
    distanceMeters: input.candidate.distanceMeters,
    expectedTravelTimeSeconds: input.candidate.expectedTravelTimeSeconds,
    selectedPathEvidence: SurfaceSelectedPathEvidence(
      networkSnapshotID: fixture.networkSnapshot.id,
      providerDatasetID: "other.dataset",
      directedEdgeIDs:
        input.candidate.selectedPathEvidence?.directedEdgeIDs ?? []
    )
  )
  let planner = ReleasedSurfaceAccessPlanner(
    provider: StubReleaseBoundSurfaceProvider(
      releaseIdentity: definition.providerIdentity,
      response: .success([driftedCandidate])
    ),
    inspector: StubSurfaceApproachInspector(
      inspection: input.inspection
    )
  )

  let result = try await planner.plan(
    release: release,
    request: input.request,
    finishPolicy: .finishOnRequest
  )

  #expect(result.disposition == .rejected)
  #expect(result.options.isEmpty)
  #expect(
    result.compilationFailures
      == [
        ReleasedSurfaceAccessCompilationFailure(
          candidateID: input.candidate.id,
          error: .selectedPathEvidenceMismatch
        )
      ]
  )
}

@Test("Product runtime admits one compiler-minted surface journey")
func productRuntimeAdmitsReleasedSurfaceJourney() async throws {
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
    providerIdentity: definition.providerIdentity,
    finishPolicy: .finishOnRequest
  )

  let runtime = try KaidoProductNavigationRuntime(
    release: release,
    journeyPlan: plan
  )
  let initial = await runtime.session.snapshot
  let started = await runtime.session.start()

  #expect(runtime.journeyPlan == plan)
  #expect(initial.journeyPhase == .approachToEntry)
  #expect(
    initial.lastPhaseTransitionTrigger
      == "RELEASED_SURFACE_ACCESS_PLAN_ADMITTED"
  )
  #expect(started.journeyPhase == .approachToEntry)
  #expect(
    started.currentOccurrenceID
      == fixture.routePlan.occurrences.first?.id
  )
  #expect(!started.strictRouteAutoCommitAllowed)
  #expect(runtime.release.navigation.bundle.routePlan == fixture.routePlan)
}

@Test("Product runtime rejects a surface journey minted for another release")
func productRuntimeRejectsSurfaceJourneyReleaseDrift() throws {
  let fixture = navigationReleaseBundleFixture()
  let definition = releasedSurfaceAccessDefinition(fixture)
  let admittedRelease = try productRelease(
    fixture,
    surfaceAccessDefinition: definition
  )
  let otherRelease = try productRelease(
    fixture,
    surfaceAccessDefinition: definition,
    releaseID: "test.product-release.surface-access.other"
  )
  let input = acceptedSurfaceAccessInput(fixture, definition: definition)
  let otherPlan = try JourneyPlanCompiler.surfaceAccess(
    release: otherRelease,
    request: input.request,
    candidate: input.candidate,
    inspection: input.inspection,
    providerIdentity: definition.providerIdentity,
    finishPolicy: .finishOnRequest
  )

  do {
    _ = try KaidoProductNavigationRuntime(
      release: admittedRelease,
      journeyPlan: otherPlan
    )
    Issue.record("Expected cross-release JourneyPlan admission to fail")
  } catch JourneyPlanRuntimeAdmissionError.invalid(let issues) {
    #expect(issues.contains(.releaseIdentityMismatch))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Surface journey checkpoint cannot restore as a route-only session")
func surfaceJourneyCheckpointBindsJourneyIdentity() async throws {
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
    providerIdentity: definition.providerIdentity,
    finishPolicy: .finishOnRequest
  )
  let runtime = try KaidoProductNavigationRuntime(
    release: release,
    journeyPlan: plan
  )
  _ = await runtime.session.start()
  let checkpoint = try await runtime.makeCheckpoint(
    savedAtMilliseconds: 1_000
  )
  let data = try NavigationSessionCheckpointCodec.encode(checkpoint)
  let decoded = try NavigationSessionCheckpointCodec.decode(data)

  let restored = try KaidoProductNavigationRuntime(
    release: release,
    journeyPlan: plan,
    checkpoint: decoded
  )
  #expect(checkpoint.journeyPlanID == plan.id)
  #expect(restored.journeyPlan == plan)
  #expect(restored.origin == .restored)
  #expect(await restored.session.snapshot.journeyPhase == .approachToEntry)

  do {
    _ = try KaidoProductNavigationRuntime(
      release: release,
      checkpoint: decoded
    )
    Issue.record("Expected access checkpoint to reject route-only restoration")
  } catch NavigationSessionCheckpointError.invalid(let issues) {
    #expect(issues.contains(.identityMismatch("journey_plan_id")))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Released surface egress requires exact option policy and evidence")
func releasedSurfaceEgressRequiresExactPolicyAndEvidence() throws {
  let fixture = navigationReleaseBundleFixture()
  let access = releasedSurfaceAccessDefinition(fixture)
  let egress = releasedSurfaceEgressDefinition(
    fixture,
    providerIdentity: access.providerIdentity
  )
  let artifact = navigationReleaseArtifact(
    fixture,
    surfaceAccessDefinition: access,
    surfaceEgressDefinition: egress
  )

  let release = try NavigationRelease(artifact: artifact)
  #expect(release.bundle.surfaceEgressDefinition == egress)
  #expect(
    release.assetEvidence.contains {
      $0.role == .surfaceEgress && $0.assetID == egress.id
    }
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
      surfaceEgressDefinition: egress
    )
    Issue.record("Expected orphaned surface egress to block release")
  } catch NavigationReleaseBundleError.invalid(let issues) {
    let details = issues.compactMap {
      issue -> [ReleasedSurfaceEgressIssue]? in
      guard case .invalidSurfaceEgressDefinition(let details) = issue
      else {
        return nil
      }
      return details
    }.flatMap { $0 }
    #expect(details.contains(.surfaceAccessNotReleased))
  }

  let missingEvidence = artifact.assetEvidence.filter {
    !($0.role == .surfaceEgress && $0.assetID == egress.id)
  }
  let uncovered = NavigationReleaseArtifact(
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
    surfaceAccessDefinition: access,
    surfaceEgressDefinition: egress
  )
  do {
    _ = try NavigationRelease(artifact: uncovered)
    Issue.record("Expected missing surface-egress evidence to block release")
  } catch NavigationReleaseError.invalid(let issues) {
    #expect(
      issues.contains(
        .missingAssetEvidence("SURFACE_EGRESS:\(egress.id)")
      )
    )
  }

  let policy = egress.policies[0]
  let drifted = ReleasedSurfaceEgressDefinition(
    id: egress.id,
    routePlanID: "other.plan",
    providerIdentity: egress.providerIdentity,
    policies: [
      SurfaceEgressPolicy(
        id: policy.id,
        networkSnapshotID: "other.snapshot",
        egressOptionID: "other.egress",
        exitFacilityID: "other.exit",
        originAnchor: policy.originAnchor,
        returnTargetBearingToleranceDegrees:
          policy.returnTargetBearingToleranceDegrees,
        maxReturnTargetDistanceMeters:
          policy.maxReturnTargetDistanceMeters,
        forbiddenExpresswayEdgeIDs:
          policy.forbiddenExpresswayEdgeIDs,
        forbiddenTollDomainIDs: policy.forbiddenTollDomainIDs
      )
    ]
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
      surfaceAccessDefinition: access,
      surfaceEgressDefinition: drifted
    )
    Issue.record("Expected surface-egress identity drift to block release")
  } catch NavigationReleaseBundleError.invalid(let issues) {
    let details = issues.compactMap {
      issue -> [ReleasedSurfaceEgressIssue]? in
      guard case .invalidSurfaceEgressDefinition(let details) = issue
      else {
        return nil
      }
      return details
    }.flatMap { $0 }
    #expect(details.contains(.routePlanMismatch))
    #expect(details.contains(.policySnapshotMismatch))
    #expect(details.contains(.unknownEgressOption))
  }
}

@Test("Surface return planner ranks only compiler-admitted released paths")
func surfaceReturnPlannerSelectsFastestReleasedPath() async throws {
  let fixture = navigationReleaseBundleFixture()
  let access = releasedSurfaceAccessDefinition(fixture)
  let egress = releasedSurfaceEgressDefinition(
    fixture,
    providerIdentity: access.providerIdentity
  )
  let release = try productRelease(
    fixture,
    surfaceAccessDefinition: access,
    surfaceEgressDefinition: egress
  )
  let accessInput = acceptedSurfaceAccessInput(
    fixture,
    definition: access
  )
  let basePlan = try JourneyPlanCompiler.surfaceAccess(
    release: release,
    request: accessInput.request,
    candidate: accessInput.candidate,
    inspection: accessInput.inspection,
    providerIdentity: access.providerIdentity,
    finishPolicy: .returnNearOrigin
  )
  let target = try #require(basePlan.returnTarget)
  let policy = egress.policies[0]
  let slow = surfaceEgressCandidate(
    id: "test.surface-egress.slow",
    travelTime: 420,
    distance: 1_400,
    fixture: fixture,
    policy: policy,
    target: target,
    providerIdentity: access.providerIdentity
  )
  let fast = surfaceEgressCandidate(
    id: "test.surface-egress.fast",
    travelTime: 300,
    distance: 1_600,
    fixture: fixture,
    policy: policy,
    target: target,
    providerIdentity: access.providerIdentity
  )
  let inspector = StubSurfaceEgressInspector(
    inspectionsByCandidateID: [
      slow.id: surfaceEgressInspection(
        candidate: slow,
        fixture: fixture,
        policy: policy,
        target: target
      ),
      fast.id: surfaceEgressInspection(
        candidate: fast,
        fixture: fixture,
        policy: policy,
        target: target
      ),
    ]
  )
  let planner = ReleasedSurfaceEgressPlanner(
    provider: StubReleaseBoundSurfaceEgressProvider(
      releaseIdentity: access.providerIdentity,
      response: .success([slow, fast])
    ),
    inspector: inspector
  )

  let result = try await planner.plan(
    release: release,
    basePlan: basePlan
  )
  let plan = try #require(result.selectedPlan)
  #expect(result.disposition == .ready)
  #expect(result.options.map(\.candidateID) == [fast.id, slow.id])
  #expect(plan.egressLeg?.candidateID == fast.id)
  #expect(
    plan.egressLeg?.directedEdgeIDs
      == [
        policy.originAnchor.directedSurfaceEdgeID,
        "test.surface.return-middle",
        policy.originAnchor.directedSurfaceEdgeID,
        target.directedSurfaceEdgeID,
      ]
  )
  #expect(plan.selectedEgressOptionID == policy.egressOptionID)
  #expect(plan.routePlanID == basePlan.routePlanID)
  #expect(plan.accessLeg == basePlan.accessLeg)
  #expect(plan.returnTarget == basePlan.returnTarget)

  do {
    _ = try KaidoProductNavigationRuntime(
      release: release,
      journeyPlan: basePlan
    )
    Issue.record("Expected incomplete return plan to fail runtime admission")
  } catch JourneyPlanRuntimeAdmissionError.invalid(let issues) {
    #expect(issues.contains(.surfaceEgressNotReleased))
  }

  let runtime = try KaidoProductNavigationRuntime(
    release: release,
    journeyPlan: plan
  )
  let context = try #require(runtime.surfaceEgressAdmissionContext)
  _ = await runtime.session.start()
  let finish = await runtime.session.finishDrive()
  #expect(finish.journeyPhase == .exitTransition)
  #expect(finish.egress.exitFacilityID == policy.exitFacilityID)
  #expect(
    finish.lastPhaseTransitionTrigger
      == "RELEASED_EGRESS_PLAN_ACTIVATED"
  )

  let simulated = await runtime.session.observeSurfaceEgressHandoffEvidence(
    surfaceEgressEvidence(
      context: context,
      id: "test.egress-handoff.simulated",
      at: 500,
      fractionAlongEdge: 0.1,
      isSimulatedBySoftware: true
    )
  )
  #expect(simulated.status == .rejected)
  #expect(simulated.rejectionReason == .simulatedLocation)
  #expect(simulated.navigationSnapshot.journeyPhase == .exitTransition)

  let first = await runtime.session.observeSurfaceEgressHandoffEvidence(
    surfaceEgressEvidence(
      context: context,
      id: "test.egress-handoff.1",
      at: 1_000,
      fractionAlongEdge: 0.2
    )
  )
  #expect(first.status == .observing)
  #expect(first.navigationSnapshot.journeyPhase == .exitTransition)

  let reversed = await runtime.session.observeSurfaceEgressHandoffEvidence(
    surfaceEgressEvidence(
      context: context,
      id: "test.egress-handoff.2",
      at: 2_000,
      fractionAlongEdge: 0.1
    )
  )
  #expect(reversed.rejectionReason == .nonForwardProgress)
  #expect(reversed.navigationSnapshot.journeyPhase == .exitTransition)

  let admitted = await runtime.session.observeSurfaceEgressHandoffEvidence(
    surfaceEgressEvidence(
      context: context,
      id: "test.egress-handoff.3",
      at: 3_000,
      fractionAlongEdge: 0.4
    )
  )
  #expect(admitted.status == .surfaceEgressEntered)
  #expect(admitted.navigationSnapshot.journeyPhase == .surfaceEgress)
  #expect(
    admitted.navigationSnapshot.lastPhaseTransitionTrigger
      == "VERIFIED_SURFACE_EGRESS_HANDOFF"
  )
}

@Test("Surface return planner keeps provider failures and malformed success explicit")
func surfaceReturnPlannerDisclosesProviderResponseFailures() async throws {
  let fixture = navigationReleaseBundleFixture()
  let access = releasedSurfaceAccessDefinition(fixture)
  let egress = releasedSurfaceEgressDefinition(
    fixture,
    providerIdentity: access.providerIdentity
  )
  let release = try productRelease(
    fixture,
    surfaceAccessDefinition: access,
    surfaceEgressDefinition: egress
  )
  let accessInput = acceptedSurfaceAccessInput(
    fixture,
    definition: access
  )
  let basePlan = try JourneyPlanCompiler.surfaceAccess(
    release: release,
    request: accessInput.request,
    candidate: accessInput.candidate,
    inspection: accessInput.inspection,
    providerIdentity: access.providerIdentity,
    finishPolicy: .returnNearOrigin
  )
  let inspector = StubSurfaceEgressInspector(
    inspectionsByCandidateID: [:]
  )
  let failure = SurfaceProviderFailure(
    kind: .network,
    providerErrorCode: "TEST_EGRESS_NETWORK"
  )
  let failed = try await ReleasedSurfaceEgressPlanner(
    provider: StubReleaseBoundSurfaceEgressProvider(
      releaseIdentity: access.providerIdentity,
      response: .failure(failure)
    ),
    inspector: inspector
  ).plan(
    release: release,
    basePlan: basePlan
  )
  #expect(failed.disposition == .providerFailure)
  #expect(failed.providerFailures.map(\.failure) == [failure])
  #expect(failed.selectedPlan == nil)

  let empty = try await ReleasedSurfaceEgressPlanner(
    provider: StubReleaseBoundSurfaceEgressProvider(
      releaseIdentity: access.providerIdentity,
      response: .success([])
    ),
    inspector: inspector
  ).plan(
    release: release,
    basePlan: basePlan
  )
  #expect(empty.disposition == .invalidResponse)
  #expect(
    empty.evaluations.contains {
      $0.evaluation.hardGates.contains {
        $0.reasonCodes.contains("EMPTY_SUCCESS_RESPONSE")
      }
    }
  )
  #expect(empty.selectedPlan == nil)
}

@Test("Surface return target cannot be replaced by a caller destination")
func surfaceReturnTargetDriftFailsClosed() throws {
  let fixture = navigationReleaseBundleFixture()
  let access = releasedSurfaceAccessDefinition(fixture)
  let egress = releasedSurfaceEgressDefinition(
    fixture,
    providerIdentity: access.providerIdentity
  )
  let release = try productRelease(
    fixture,
    surfaceAccessDefinition: access,
    surfaceEgressDefinition: egress
  )
  let input = acceptedSurfaceAccessInput(fixture, definition: access)
  let basePlan = try JourneyPlanCompiler.surfaceAccess(
    release: release,
    request: input.request,
    candidate: input.candidate,
    inspection: input.inspection,
    providerIdentity: access.providerIdentity,
    finishPolicy: .returnNearOrigin
  )
  let target = try #require(basePlan.returnTarget)
  let policy = egress.policies[0]
  let request = SurfaceEgressRouteRequest(
    id: "test.surface-egress.drift",
    exitFacilityID: policy.exitFacilityID,
    egressOptionID: policy.egressOptionID,
    originAnchor: policy.originAnchor,
    destinationAnchor: DirectedApproachAnchor(
      id: target.id,
      coordinate: SurfaceCoordinate(latitude: 35, longitude: 140),
      directedSurfaceEdgeID: target.directedSurfaceEdgeID,
      expectedBearingDegrees: target.expectedBearingDegrees,
      bearingToleranceDegrees:
        policy.returnTargetBearingToleranceDegrees,
      maxTerminalDistanceMeters: policy.maxReturnTargetDistanceMeters
    )
  )
  do {
    _ = try JourneyPlanCompiler.surfaceEgressPreflight(
      release: release,
      basePlan: basePlan,
      request: request,
      providerIdentity: access.providerIdentity
    )
    Issue.record("Expected caller-selected return target to fail closed")
  } catch JourneyPlanCompilerError.invalidRequest(let reasons) {
    #expect(
      reasons.contains(
        "SURFACE_EGRESS_REQUEST_RETURN_TARGET_MISMATCH"
      )
    )
  }
}

private struct SurfaceAccessInput {
  let request: SurfaceRouteRequest
  let candidate: SurfaceRouteCandidate
  let inspection: SurfaceCandidateInspection
}

private struct StubReleaseBoundSurfaceProvider:
  ReleaseBoundSurfaceRouteProvider
{
  let releaseIdentity: SurfaceRouteProviderReleaseIdentity
  let response: SurfaceProviderResponse

  var metadata: SurfaceRouteProviderMetadata {
    SurfaceRouteProviderMetadata(
      id: releaseIdentity.providerID,
      adapterVersion: releaseIdentity.adapterVersion,
      providerVersion: releaseIdentity.providerVersion,
      dataReviewStatus: releaseIdentity.dataReviewStatus
    )
  }

  func routes(for _: SurfaceRouteRequest) async -> SurfaceProviderResponse {
    response
  }
}

private struct StubSurfaceApproachInspector:
  SurfaceApproachCandidateInspector
{
  let inspection: SurfaceCandidateInspection

  func inspect(
    candidate _: SurfaceRouteCandidate,
    request _: SurfaceRouteRequest,
    policy _: SurfaceApproachPolicy
  ) async -> SurfaceCandidateInspection {
    inspection
  }
}

private struct StubReleaseBoundSurfaceEgressProvider:
  ReleaseBoundSurfaceEgressRouteProvider
{
  let releaseIdentity: SurfaceRouteProviderReleaseIdentity
  let response: SurfaceProviderResponse

  var metadata: SurfaceRouteProviderMetadata {
    SurfaceRouteProviderMetadata(
      id: releaseIdentity.providerID,
      adapterVersion: releaseIdentity.adapterVersion,
      providerVersion: releaseIdentity.providerVersion,
      dataReviewStatus: releaseIdentity.dataReviewStatus
    )
  }

  func egressRoutes(
    for _: SurfaceEgressRouteRequest
  ) async -> SurfaceProviderResponse {
    response
  }
}

private struct StubSurfaceEgressInspector:
  SurfaceEgressCandidateInspector
{
  let inspectionsByCandidateID: [String: SurfaceEgressCandidateInspection]

  func inspect(
    candidate: SurfaceRouteCandidate,
    request _: SurfaceEgressRouteRequest,
    policy _: SurfaceEgressPolicy
  ) async -> SurfaceEgressCandidateInspection {
    inspectionsByCandidateID[candidate.id]
      ?? SurfaceEgressCandidateInspection(
        networkSnapshotID: nil,
        handoffBinding: nil,
        returnTargetBinding: nil,
        geometryBindingIsUnambiguous: nil,
        expresswayEdgeIDsAfterExit: nil,
        crossedTollDomainIDs: nil
      )
  }
}

private func releasedSurfaceAccessDefinition(
  _ fixture: NavigationReleaseBundleFixture
) -> ReleasedSurfaceAccessDefinition {
  ReleasedSurfaceAccessDefinition(
    id: "test.surface-access.release-bundle",
    routePlanID: fixture.routePlan.id,
    providerIdentity: SurfaceRouteProviderReleaseIdentity(
      providerID: "test.provider",
      adapterVersion: "test.adapter.v1",
      providerVersion: "test.engine.v1",
      networkSnapshotID: fixture.networkSnapshot.id,
      providerDatasetID: "test.dataset",
      buildManifestID: "test.surface-build.release-bundle",
      engineBuildID: "test.surface-engine.release-bundle",
      manifestValidationProfile: .releaseCandidate,
      manifestIntendedUse: .releaseCandidate,
      dataReviewStatus: .derivedFixtureReviewed
    ),
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

private func releasedSurfaceEgressDefinition(
  _ fixture: NavigationReleaseBundleFixture,
  providerIdentity: SurfaceRouteProviderReleaseIdentity
) -> ReleasedSurfaceEgressDefinition {
  let option = fixture.runtimePolicy.egressOptions[0]
  return ReleasedSurfaceEgressDefinition(
    id: "test.surface-egress.release-bundle",
    routePlanID: fixture.routePlan.id,
    providerIdentity: providerIdentity,
    policies: [
      SurfaceEgressPolicy(
        id: "test.surface-egress-policy.release-bundle",
        networkSnapshotID: fixture.networkSnapshot.id,
        egressOptionID: option.id,
        exitFacilityID: option.exitFacilityID,
        originAnchor: DirectedSurfaceHandoffAnchor(
          id: "test.surface-egress-handoff.release-bundle",
          coordinate: SurfaceCoordinate(
            latitude: 35.681,
            longitude: 139.761
          ),
          directedSurfaceEdgeID: "test.surface.exit-edge",
          expectedBearingDegrees: 180,
          bearingToleranceDegrees: 25,
          maxStartDistanceMeters: 12
        ),
        returnTargetBearingToleranceDegrees: 30,
        maxReturnTargetDistanceMeters: 18,
        forbiddenExpresswayEdgeIDs: [
          "test.expressway.forbidden"
        ],
        forbiddenTollDomainIDs: ["test.toll.forbidden"]
      )
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

private func surfaceEgressCandidate(
  id: String,
  travelTime: Double,
  distance: Double,
  fixture: NavigationReleaseBundleFixture,
  policy: SurfaceEgressPolicy,
  target: JourneyReturnTarget,
  providerIdentity: SurfaceRouteProviderReleaseIdentity
) -> SurfaceRouteCandidate {
  let edgeIDs = [
    policy.originAnchor.directedSurfaceEdgeID,
    "test.surface.return-middle",
    policy.originAnchor.directedSurfaceEdgeID,
    target.directedSurfaceEdgeID,
  ]
  return SurfaceRouteCandidate(
    id: id,
    providerID: providerIdentity.providerID,
    coordinates: [
      policy.originAnchor.coordinate,
      target.coordinate,
    ],
    steps: [],
    distanceMeters: distance,
    expectedTravelTimeSeconds: travelTime,
    selectedPathEvidence: SurfaceSelectedPathEvidence(
      networkSnapshotID: fixture.networkSnapshot.id,
      providerDatasetID: providerIdentity.providerDatasetID,
      directedEdgeIDs: edgeIDs
    )
  )
}

private func surfaceEgressInspection(
  candidate: SurfaceRouteCandidate,
  fixture: NavigationReleaseBundleFixture,
  policy: SurfaceEgressPolicy,
  target: JourneyReturnTarget
) -> SurfaceEgressCandidateInspection {
  SurfaceEgressCandidateInspection(
    networkSnapshotID: fixture.networkSnapshot.id,
    handoffBinding: SurfaceHandoffBindingObservation(
      anchorID: policy.originAnchor.id,
      directedSurfaceEdgeID:
        policy.originAnchor.directedSurfaceEdgeID,
      startDistanceMeters: 3,
      startBearingDegrees:
        policy.originAnchor.expectedBearingDegrees
    ),
    returnTargetBinding: AnchorBindingObservation(
      anchorID: target.id,
      directedSurfaceEdgeID: target.directedSurfaceEdgeID,
      terminalDistanceMeters: 5,
      terminalBearingDegrees: target.expectedBearingDegrees
    ),
    geometryBindingIsUnambiguous: true,
    expresswayEdgeIDsAfterExit: [],
    crossedTollDomainIDs: [],
    resolvedPathEdgeIDs:
      candidate.selectedPathEvidence?.directedEdgeIDs
  )
}

private func surfaceEgressEvidence(
  context: SurfaceEgressAdmissionContext,
  id: String,
  at: Int,
  fractionAlongEdge: Double,
  isSimulatedBySoftware: Bool = false
) -> SurfaceEgressHandoffEvidence {
  SurfaceEgressHandoffEvidence(
    context: context,
    observationID: id,
    observedAtMilliseconds: at,
    receivedAtMilliseconds: at,
    directedSurfaceEdgeID: context.directedSurfaceEdgeID,
    candidateEdgeIDs: [context.directedSurfaceEdgeID],
    fractionAlongEdge: fractionAlongEdge,
    confidence: .high,
    headingErrorDegrees: 5,
    isSimulatedBySoftware: isSimulatedBySoftware
  )
}

private func productRelease(
  _ fixture: NavigationReleaseBundleFixture,
  surfaceAccessDefinition: ReleasedSurfaceAccessDefinition,
  surfaceEgressDefinition: ReleasedSurfaceEgressDefinition? = nil,
  releaseID: String = "test.product-release.surface-access"
) throws -> KaidoProductRelease {
  try KaidoProductRelease(
    artifact: KaidoProductReleaseArtifact(
      releaseID: releaseID,
      releasedAt: "2026-07-24T12:00:00+09:00",
      navigationRelease: navigationReleaseArtifact(
        fixture,
        surfaceAccessDefinition: surfaceAccessDefinition,
        surfaceEgressDefinition: surfaceEgressDefinition
      ),
      routeAtlasRelease: productRouteAtlasArtifact(
        fixture,
        includeIncomingApproach: true
      )
    )
  )
}
