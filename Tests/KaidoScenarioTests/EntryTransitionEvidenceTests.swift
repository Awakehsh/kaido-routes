import Foundation
import KaidoAppleAdapters
import KaidoDomain
import KaidoNavigation
import KaidoRouting
import Testing

@Test("Product runtime admits only an ordered release-bound entry sequence")
func productRuntimeAdmitsReleaseBoundEntryEvidence() async throws {
  let fixture = navigationReleaseBundleFixture()
  let release = try KaidoProductRelease(
    artifact: KaidoProductReleaseArtifact(
      releaseID: "test.product-release.entry-evidence",
      releasedAt: "2026-07-24T12:00:00+09:00",
      navigationRelease: navigationReleaseArtifact(fixture),
      routeAtlasRelease: productRouteAtlasArtifact(
        fixture,
        includeIncomingApproach: true
      )
    )
  )
  let runtime = try KaidoProductNavigationRuntime(release: release)
  let context = runtime.entryTransitionAdmissionContext
  _ = await runtime.session.start()

  let ordinaryMatcher = try await runtime.session.observe(
    RouteMatcherObservation(
      id: "ordinary.0",
      observedAtMilliseconds: 500,
      receivedAtMilliseconds: 500,
      coordinate: MatcherCoordinate(latitude: 35.68, longitude: 139.7611),
      horizontalAccuracyMeters: 3,
      courseDegrees: 90,
      speedMetersPerSecond: 12,
      source: .phone
    )
  )
  #expect(ordinaryMatcher.navigationSnapshot.journeyPhase == .planning)
  #expect(
    ordinaryMatcher.navigationSnapshot.currentOccurrenceID
      == fixture.routePlan.occurrences.first?.id
  )
  #expect(ordinaryMatcher.guidanceProgressState == .notApplicable)

  let surface = try await runtime.session.observeEntryTransitionEvidence(
    entryEvidence(
      context: context,
      id: "entry.0",
      at: 1_000,
      edgeID: context.entryTransition.directedEdgeIDs[0]
    )
  )
  #expect(surface.status == .observing)
  #expect(surface.acceptedTransitionEdgeIndex == 0)
  #expect(surface.navigationSnapshot.journeyPhase == .entryTransition)
  #expect(surface.navigationSnapshot.strictRouteAutoCommitAllowed == false)

  let ramp = try await runtime.session.observeEntryTransitionEvidence(
    entryEvidence(
      context: context,
      id: "entry.1",
      at: 2_000,
      edgeID: context.entryTransition.directedEdgeIDs[1]
    )
  )
  #expect(ramp.status == .strictRouteEntered)
  #expect(ramp.rejectionReason == nil)
  #expect(ramp.navigationSnapshot.journeyPhase == .strictRoute)
  #expect(ramp.navigationSnapshot.strictRouteAutoCommitAllowed)
  #expect(ramp.navigationSnapshot.lastPhaseTransitionTrigger == "VERIFIED_ENTRY_CONTINUITY")
  #expect(
    ramp.navigationSnapshot.currentOccurrenceID
      == context.entryTransition.firstRouteOccurrenceID
  )
}

@Test("Two ordered MEDIUM fixes on the first route edge enter strict navigation")
func firstRouteEdgeContinuityAdmitsRealisticEntryFixes() async throws {
  let fixture = navigationReleaseBundleFixture()
  let release = try KaidoProductRelease(
    artifact: KaidoProductReleaseArtifact(
      releaseID: "test.product-release.first-route-entry",
      releasedAt: "2026-09-03T12:00:00+09:00",
      navigationRelease: navigationReleaseArtifact(fixture),
      routeAtlasRelease: productRouteAtlasArtifact(
        fixture,
        includeIncomingApproach: true
      )
    )
  )
  let runtime = try KaidoProductNavigationRuntime(release: release)
  let context = runtime.entryTransitionAdmissionContext
  _ = await runtime.session.start()

  let first = try await runtime.session.observeEntryTransitionEvidence(
    entryEvidence(
      context: context,
      id: "first-route.0",
      at: 1_000,
      edgeID: context.firstRouteDirectedEdgeID,
      confidence: .medium
    )
  )
  #expect(first.status == .observing)
  #expect(first.navigationSnapshot.journeyPhase == .planning)

  let second = try await runtime.session.observeEntryTransitionEvidence(
    entryEvidence(
      context: context,
      id: "first-route.1",
      at: 2_000,
      edgeID: context.firstRouteDirectedEdgeID,
      confidence: .medium
    )
  )
  #expect(second.status == .strictRouteEntered)
  #expect(second.navigationSnapshot.journeyPhase == .strictRoute)
  #expect(
    second.navigationSnapshot.lastPhaseTransitionTrigger
      == "VERIFIED_FIRST_ROUTE_EDGE_CONTINUITY"
  )
  #expect(
    second.navigationSnapshot.currentOccurrenceID
      == context.entryTransition.firstRouteOccurrenceID
  )
}

@Test("Core Location adapter enters C1 from 1 Hz 8 m accuracy fixes")
func coreLocationAdapterAdmitsRealisticC1EntryFixes() async throws {
  let database = try loadEntryTestWholeShutoDatabase()
  let release = try KaidoProductRelease(
    artifact: ShutoCircuitProductReleaseBuilder.buildArtifact(database: database)
  )
  let runtime = try KaidoProductNavigationRuntime(release: release)
  let context = runtime.entryTransitionAdmissionContext
  let edge = try #require(
    context.matcherCorridor.edges.first {
      $0.id == context.firstRouteDirectedEdgeID
    }
  )
  let start = try #require(edge.coordinates.first)
  let end = try #require(edge.coordinates.last)
  let course = entryTestBearing(from: start, to: end)
  var adapter = try CoreLocationEntryTransitionAdapter(context: context)
  _ = await runtime.session.start()
  var entered = false
  var diagnostics: [String] = []

  for (index, fraction) in [0.15, 0.4, 0.65, 0.9].enumerated() {
    let at = (index + 1) * 1_000
    let observation = RouteMatcherObservation(
      id: "c1.entry.realistic.\(index)",
      observedAtMilliseconds: at,
      receivedAtMilliseconds: at,
      coordinate: MatcherCoordinate(
        latitude: start.latitude + (end.latitude - start.latitude) * fraction,
        longitude: start.longitude + (end.longitude - start.longitude) * fraction
      ),
      horizontalAccuracyMeters: 8,
      courseDegrees: course,
      courseAccuracyDegrees: 5,
      speedMetersPerSecond: 10,
      speedAccuracyMetersPerSecond: 1,
      source: .phone
    )
    let envelope = CoreLocationObservationEnvelope(
      observation: observation,
      provenance: CoreLocationObservationProvenance(
        deliverySource: .deviceOrUndisclosed,
        sourceInformationAvailable: true,
        isSimulatedBySoftware: false,
        carPlayConnectionContext: .disconnected,
        matcherCalibrationCohort: .phone,
        courseAccuracyDegrees: 5,
        speedAccuracyMetersPerSecond: 1,
        observationAgeMilliseconds: 0
      )
    )
    let evidence = try adapter.adapt(envelope)
    let update = try await runtime.session.observeEntryTransitionEvidence(evidence)
    diagnostics.append(
      "\(index):\(evidence.confidence.rawValue):\(evidence.directedEdgeID ?? "nil"):"
        + "\(evidence.candidateEdgeIDs):\(String(describing: update.rejectionReason))"
    )
    if update.status == .strictRouteEntered {
      entered = true
      break
    }
  }

  #expect(entered, "\(diagnostics)")
  let snapshot = await runtime.session.snapshot
  #expect(snapshot.journeyPhase == .strictRoute)
}

@Test("Entry evidence rejects skips, simulation, identity drift, and replay")
func entryEvidenceFailsClosed() async throws {
  let fixture = navigationReleaseBundleFixture()
  let release = try KaidoProductRelease(
    artifact: KaidoProductReleaseArtifact(
      releaseID: "test.product-release.entry-rejection",
      releasedAt: "2026-07-24T12:00:00+09:00",
      navigationRelease: navigationReleaseArtifact(fixture),
      routeAtlasRelease: productRouteAtlasArtifact(
        fixture,
        includeIncomingApproach: true
      )
    )
  )
  let runtime = try KaidoProductNavigationRuntime(release: release)
  let context = runtime.entryTransitionAdmissionContext
  _ = await runtime.session.start()

  let skipped = try await runtime.session.observeEntryTransitionEvidence(
    entryEvidence(
      context: context,
      id: "entry.skip",
      at: 1_000,
      edgeID: context.entryTransition.directedEdgeIDs[1]
    )
  )
  #expect(skipped.rejectionReason == .outOfOrderEdge)
  #expect(skipped.navigationSnapshot.journeyPhase == .planning)

  let first = try await runtime.session.observeEntryTransitionEvidence(
    entryEvidence(
      context: context,
      id: "entry.first",
      at: 2_000,
      edgeID: context.entryTransition.directedEdgeIDs[0]
    )
  )
  #expect(first.navigationSnapshot.journeyPhase == .entryTransition)

  let simulated = try await runtime.session.observeEntryTransitionEvidence(
    entryEvidence(
      context: context,
      id: "entry.simulated",
      at: 3_000,
      edgeID: context.entryTransition.directedEdgeIDs[1],
      isSimulated: true
    )
  )
  #expect(simulated.rejectionReason == .simulatedLocation)
  #expect(simulated.navigationSnapshot.journeyPhase == .entryTransition)

  let driftedContext = EntryTransitionAdmissionContext(
    productReleaseID: "test.product-release.other",
    navigationReleaseID: context.navigationReleaseID,
    runtimePolicyID: context.runtimePolicyID,
    networkSnapshotID: context.networkSnapshotID,
    routePlanID: context.routePlanID,
    matcherCorridorID: context.matcherCorridorID,
    entryTransition: context.entryTransition,
    matcherCorridor: context.matcherCorridor,
    firstRouteDirectedEdgeID: context.firstRouteDirectedEdgeID
  )
  let drifted = try await runtime.session.observeEntryTransitionEvidence(
    entryEvidence(
      context: driftedContext,
      id: "entry.drift",
      at: 4_000,
      edgeID: context.entryTransition.directedEdgeIDs[1]
    )
  )
  #expect(drifted.rejectionReason == .releaseIdentityMismatch)

  let replayed = try await runtime.session.observeEntryTransitionEvidence(
    entryEvidence(
      context: context,
      id: "entry.first",
      at: 2_000,
      edgeID: context.entryTransition.directedEdgeIDs[0]
    )
  )
  #expect(replayed.rejectionReason == .replayedOrStaleObservation)
  #expect(replayed.navigationSnapshot.journeyPhase == .entryTransition)
}

@Test("A raw session without product release cannot admit entry evidence")
func rawNavigationSessionCannotAdmitEntryEvidence() async throws {
  let fixture = navigationSessionFixture()
  let session = try NavigationSession(
    navigationConfiguration: fixture.configuration,
    matcherCorridor: fixture.corridor,
    decisionZones: [fixture.decisionZone]
  )
  let context = EntryTransitionAdmissionContext(
    productReleaseID: "test.product.raw",
    navigationReleaseID: "test.navigation.raw",
    runtimePolicyID: "test.policy.raw",
    networkSnapshotID: fixture.corridor.networkSnapshotID,
    routePlanID: fixture.corridor.routePlanID,
    matcherCorridorID: fixture.corridor.id,
    entryTransition: EntryTransition(
      facilityID: "test.entrance",
      directedEdgeIDs: ["test.transition.surface", "test.transition.ramp"],
      firstRouteOccurrenceID: "test.occurrence.approach"
    ),
    matcherCorridor: fixture.corridor,
    firstRouteDirectedEdgeID: "test.edge.approach"
  )

  let update = try await session.observeEntryTransitionEvidence(
    entryEvidence(
      context: context,
      id: "entry.raw",
      at: 1_000,
      edgeID: "test.transition.surface"
    )
  )
  #expect(update.status == .rejected)
  #expect(update.rejectionReason == .runtimeNotReleaseAdmitted)
}

@Test("Navigation release rejects entry edges absent from its matcher corridor")
func navigationReleaseRejectsUnboundEntryGeometry() {
  let fixture = navigationReleaseBundleFixture()
  let transitionIDs = Set(fixture.runtimePolicy.entryTransition.directedEdgeIDs)
  let corridor = RouteMatcherCorridor(
    id: fixture.matcherCorridor.id,
    networkSnapshotID: fixture.matcherCorridor.networkSnapshotID,
    routePlanID: fixture.matcherCorridor.routePlanID,
    edges: fixture.matcherCorridor.edges.filter { !transitionIDs.contains($0.id) },
    occurrences: fixture.matcherCorridor.occurrences
  )

  do {
    _ = try NavigationReleaseBundle(
      networkSnapshot: fixture.networkSnapshot,
      routePlan: fixture.routePlan,
      editorCatalog: fixture.editorCatalog,
      editorPresentationCatalog: fixture.editorPresentationCatalog,
      runtimePolicy: fixture.runtimePolicy,
      matcherCorridor: corridor,
      decisionZones: fixture.decisionZones,
      releasedGuidance: fixture.releasedGuidance,
      junctionViews: fixture.junctionViews
    )
    Issue.record("Expected missing entry geometry to block release")
  } catch NavigationReleaseBundleError.invalid(let issues) {
    #expect(
      issues.contains {
        if case .invalidEntryTransitionCorridor(let detail) = $0 {
          return detail.contains("missing from matcher corridor")
        }
        return false
      }
    )
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

private func entryEvidence(
  context: EntryTransitionAdmissionContext,
  id: String,
  at: Int,
  edgeID: String,
  isSimulated: Bool = false,
  confidence: MatcherConfidence = .high
) -> EntryTransitionEvidence {
  EntryTransitionEvidence(
    context: context,
    observationID: id,
    observedAtMilliseconds: at,
    receivedAtMilliseconds: at,
    directedEdgeID: edgeID,
    candidateEdgeIDs: [edgeID],
    confidence: confidence,
    headingErrorDegrees: 1,
    isSimulatedBySoftware: isSimulated
  )
}

private func loadEntryTestWholeShutoDatabase() throws -> ShutoNetworkDatabase {
  let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  return try JSONDecoder().decode(
    ShutoNetworkDatabase.self,
    from: Data(
      contentsOf:
        repositoryRoot
        .appendingPathComponent("data/route-atlas/osm-derived")
        .appendingPathComponent("shuto-whole-network-20260804.json")
    )
  )
}

private func entryTestBearing(
  from start: MatcherCoordinate,
  to end: MatcherCoordinate
) -> Double {
  let degrees = atan2(
    end.longitude - start.longitude,
    end.latitude - start.latitude
  ) * 180 / .pi
  return degrees >= 0 ? degrees : degrees + 360
}
