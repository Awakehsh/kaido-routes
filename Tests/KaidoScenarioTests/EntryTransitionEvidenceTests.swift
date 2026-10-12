import Foundation
import KaidoAppleAdapters
import KaidoDomain
import KaidoNavigation
import KaidoRouting
import Testing

@Test("Route-head fixes still on the approach line cannot confirm entry")
func routeHeadOnTheApproachLineCannotConfirmEntry() async throws {
  // Near the ramp's top the route head still lies on the approach's straight
  // line, where a street beneath it is indistinguishable by geometry. Only
  // fixes where the route has left that line move the evidence.
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
  #expect(ordinaryMatcher.guidanceProgressState == .notApplicable)

  let transition = try await runtime.session.observeEntryTransitionEvidence(
    entryEvidence(
      context: context,
      id: "entry.transition",
      at: 1_000,
      edgeID: context.entryTransition.directedEdgeIDs[0]
    )
  )
  #expect(transition.status == .observing)
  #expect(transition.rejectionReason == nil)
  #expect(transition.navigationSnapshot.journeyPhase == .planning)

  // The route head's first 15 m sit within 20 m of the approach line.
  for (index, longitude) in [139.76002, 139.76006, 139.7601, 139.76014].enumerated() {
    let update = try await runtime.session.observeEntryTransitionEvidence(
      entryEvidence(
        context: context,
        id: "entry.head-on-line.\(index)",
        at: 2_000 + index * 1_000,
        edgeID: context.firstRouteDirectedEdgeID,
        occurrenceID: context.entryTransition.firstRouteOccurrenceID,
        coordinate: MatcherCoordinate(latitude: 35.68, longitude: longitude)
      )
    )
    #expect(update.status == .progressed)
    #expect(update.navigationSnapshot.journeyPhase == .entryTransition)
    #expect(update.navigationSnapshot.strictRouteAutoCommitAllowed == false)
  }

  let separated = try await runtime.session.observeEntryTransitionEvidence(
    entryEvidence(
      context: context,
      id: "entry.head-separated",
      at: 7_000,
      edgeID: context.firstRouteDirectedEdgeID,
      occurrenceID: context.entryTransition.firstRouteOccurrenceID,
      coordinate: MatcherCoordinate(latitude: 35.68, longitude: 139.7605)
    )
  )
  #expect(separated.status == .strictRouteEntered)
  #expect(separated.navigationSnapshot.journeyPhase == .strictRoute)
  #expect(
    separated.navigationSnapshot.lastPhaseTransitionTrigger
      == "VERIFIED_ROUTE_HEAD_PROGRESSION"
  )
}

@Test("Ordered route-head fixes past the approach line enter strict navigation")
func routeHeadProgressionPastApproachLineEnters() async throws {
  let database = try loadEntryTestWholeShutoDatabase()
  let release = try KaidoProductRelease(
    artifact: ShutoCircuitProductReleaseBuilder.buildArtifact(database: database)
  )
  let runtime = try KaidoProductNavigationRuntime(release: release)
  let context = runtime.entryTransitionAdmissionContext
  var adapter = try CoreLocationEntryTransitionAdapter(context: context)
  _ = await runtime.session.start()
  var entered: EntryTransitionSessionUpdate?
  var diagnostics: [String] = []

  for (index, point) in entryTestRouteHead(context: context, meters: 600)
    .enumerated()
  {
    let update = try await runtime.session.observeEntryTransitionEvidence(
      try adapter.adapt(entryTestEnvelope(index: index, point: point))
    )
    diagnostics.append("\(index):\(update.status.rawValue)")
    if update.status == .strictRouteEntered {
      entered = update
      break
    }
  }

  let update = try #require(entered, "\(diagnostics)")
  #expect(update.navigationSnapshot.journeyPhase == .strictRoute)
  #expect(
    update.navigationSnapshot.lastPhaseTransitionTrigger
      == "VERIFIED_ROUTE_HEAD_PROGRESSION"
  )
  // Entry lands where the evidence reached; the ramp behind it was driven.
  let reached = try #require(update.navigationSnapshot.currentOccurrenceIndex)
  #expect(reached > 0)
  #expect(
    update.navigationSnapshot.completedOccurrenceIDs.contains(
      try #require(context.entryTransition.firstRouteOccurrenceID)
    )
  )
}

@Test("A surface street continuing the approach never enters C1")
func surfaceStreetBesideTheRampCannotEnter() async throws {
  let database = try loadEntryTestWholeShutoDatabase()
  let release = try KaidoProductRelease(
    artifact: ShutoCircuitProductReleaseBuilder.buildArtifact(database: database)
  )
  let runtime = try KaidoProductNavigationRuntime(release: release)
  let context = runtime.entryTransitionAdmissionContext
  var adapter = try CoreLocationEntryTransitionAdapter(context: context)
  _ = await runtime.session.start()
  let approach = try #require(
    context.matcherCorridor.edges.first {
      $0.id == context.entryTransition.directedEdgeIDs[0]
    }
  )
  let start = approach.coordinates[0]
  let course = replayBearing(start, approach.coordinates[1])
  for index in 0..<60 {
    let point = entryTestOffset(start, bearing: course, meters: Double(index) * 11)
    let update = try await runtime.session.observeEntryTransitionEvidence(
      try adapter.adapt(
        entryTestEnvelope(
          index: index,
          point: (coordinate: point, course: course)
        )
      )
    )
    #expect(update.status != .strictRouteEntered, "fix \(index)")
  }
  let snapshot = await runtime.session.snapshot
  #expect(snapshot.journeyPhase != .strictRoute)
}

@Test("Entry evidence rejects backward progress, simulation, identity drift, and replay")
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

  let ahead = try await runtime.session.observeEntryTransitionEvidence(
    entryEvidence(
      context: context,
      id: "entry.ahead",
      at: 1_000,
      edgeID: context.firstRouteDirectedEdgeID,
      occurrenceID: "test.occurrence.loop-edge-1",
      coordinate: MatcherCoordinate(latitude: 35.68, longitude: 139.7605)
    )
  )
  #expect(ahead.status == .progressed)
  #expect(ahead.navigationSnapshot.journeyPhase == .entryTransition)

  let backward = try await runtime.session.observeEntryTransitionEvidence(
    entryEvidence(
      context: context,
      id: "entry.backward",
      at: 2_000,
      edgeID: context.firstRouteDirectedEdgeID,
      occurrenceID: context.entryTransition.firstRouteOccurrenceID,
      coordinate: MatcherCoordinate(latitude: 35.68, longitude: 139.7605)
    )
  )
  #expect(backward.rejectionReason == .outOfOrderEdge)
  #expect(backward.reachedOccurrenceID == nil)

  let simulated = try await runtime.session.observeEntryTransitionEvidence(
    entryEvidence(
      context: context,
      id: "entry.simulated",
      at: 3_000,
      edgeID: context.firstRouteDirectedEdgeID,
      occurrenceID: context.entryTransition.firstRouteOccurrenceID,
      isSimulated: true
    )
  )
  #expect(simulated.rejectionReason == .simulatedLocation)

  let offPlan = try await runtime.session.observeEntryTransitionEvidence(
    entryEvidence(
      context: context,
      id: "entry.off-plan",
      at: 3_500,
      edgeID: "test.recovery.release-bundle.movement"
    )
  )
  #expect(offPlan.rejectionReason == .unexpectedEdge)

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
      edgeID: context.firstRouteDirectedEdgeID
    )
  )
  #expect(drifted.rejectionReason == .releaseIdentityMismatch)

  let replayed = try await runtime.session.observeEntryTransitionEvidence(
    entryEvidence(
      context: context,
      id: "entry.ahead",
      at: 1_000,
      edgeID: context.firstRouteDirectedEdgeID
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
  occurrenceID: String? = nil,
  coordinate: MatcherCoordinate? = nil,
  isSimulated: Bool = false,
  confidence: MatcherConfidence = .high
) -> EntryTransitionEvidence {
  EntryTransitionEvidence(
    context: context,
    observationID: id,
    observedAtMilliseconds: at,
    receivedAtMilliseconds: at,
    directedEdgeID: edgeID,
    occurrenceID: occurrenceID,
    candidateEdgeIDs: [edgeID],
    confidence: confidence,
    coordinate: coordinate,
    horizontalAccuracyMeters: coordinate == nil ? nil : 5,
    distanceMeters: coordinate == nil ? nil : 1,
    headingErrorDegrees: 1,
    isSimulatedBySoftware: isSimulated
  )
}

/// Points 11 m apart (1 Hz at 40 km/h) along the route head, offset 4 m
/// alternately to each side.
private func entryTestRouteHead(
  context: EntryTransitionAdmissionContext,
  meters: Double
) -> [(coordinate: MatcherCoordinate, course: Double)] {
  let edgesByID = Dictionary(
    uniqueKeysWithValues: context.matcherCorridor.edges.map { ($0.id, $0) }
  )
  var polyline: [MatcherCoordinate] = []
  for occurrence in context.matcherCorridor.occurrences.sorted(by: { $0.index < $1.index }) {
    guard let edge = edgesByID[occurrence.directedEdgeID] else { break }
    polyline += polyline.isEmpty ? edge.coordinates : Array(edge.coordinates.dropFirst())
    if replayLength(polyline) > meters { break }
  }
  return stride(from: 0.0, through: meters, by: 11).enumerated().map { index, along in
    let located = replayLocate(polyline, along: along)
    let side = index.isMultiple(of: 2) ? 90.0 : -90.0
    return (
      entryTestOffset(located.coordinate, bearing: located.bearing + side, meters: 4),
      located.bearing
    )
  }
}

private func entryTestEnvelope(
  index: Int,
  point: (coordinate: MatcherCoordinate, course: Double)
) -> CoreLocationObservationEnvelope {
  let at = (index + 1) * 1_000
  return CoreLocationObservationEnvelope(
    observation: RouteMatcherObservation(
      id: "entry.test.\(index)",
      observedAtMilliseconds: at,
      receivedAtMilliseconds: at,
      coordinate: point.coordinate,
      horizontalAccuracyMeters: 8,
      courseDegrees: point.course,
      courseAccuracyDegrees: 5,
      speedMetersPerSecond: 11,
      speedAccuracyMetersPerSecond: 1,
      source: .phone
    ),
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
}

private func entryTestOffset(
  _ coordinate: MatcherCoordinate,
  bearing: Double,
  meters: Double
) -> MatcherCoordinate {
  replayOffset(coordinate, bearingDegrees: bearing, meters: meters)
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
