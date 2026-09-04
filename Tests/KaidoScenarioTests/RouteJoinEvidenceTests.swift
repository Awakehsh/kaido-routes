import Foundation
import KaidoDomain
import KaidoNavigation
import Testing

@Test("A declared join enters the strict route at the matched occurrence")
func declaredRouteJoinEntersStrictRouteAtMatchedOccurrence() async throws {
  let runtime = try routeJoinRuntime(id: "test.product-release.route-join")
  let context = runtime.entryTransitionAdmissionContext
  _ = await runtime.session.start()

  let declared = await runtime.session.declareAlreadyOnRoute(
    atMilliseconds: 1_000
  )
  #expect(declared)
  #expect(await runtime.session.isAlreadyOnRouteDeclared)

  let first = try await runtime.session.observeRouteJoinEvidence(
    routeJoinEvidence(context: context, id: "join.0", at: 1_500)
  )
  #expect(first.status == .observing)
  #expect(first.navigationSnapshot.journeyPhase == .planning)

  let second = try await runtime.session.observeRouteJoinEvidence(
    routeJoinEvidence(context: context, id: "join.1", at: 3_000)
  )
  #expect(second.status == .observing)
  #expect(second.navigationSnapshot.journeyPhase == .planning)

  let third = try await runtime.session.observeRouteJoinEvidence(
    routeJoinEvidence(context: context, id: "join.2", at: 6_000)
  )
  #expect(third.status == .joined)
  #expect(third.joinedOccurrenceID == routeJoinOccurrenceID)
  #expect(third.navigationSnapshot.journeyPhase == .strictRoute)
  #expect(third.navigationSnapshot.currentOccurrenceID == routeJoinOccurrenceID)
  #expect(
    third.navigationSnapshot.lastPhaseTransitionTrigger
      == "DRIVER_DECLARED_ROUTE_JOIN"
  )

  // The drive never passed what it joined ahead of, so those occurrences are
  // skipped. Reporting them completed would claim passage without evidence.
  #expect(
    third.navigationSnapshot.skippedOccurrenceIDs == [
      "test.occurrence.entry",
      "test.occurrence.loop-movement-1",
      "test.occurrence.loop-edge-1",
      "test.occurrence.loop-movement-2",
    ]
  )
  #expect(third.navigationSnapshot.completedOccurrenceIDs.isEmpty)

  // The declaration is spent once it is honored.
  #expect(await runtime.session.isAlreadyOnRouteDeclared == false)
}

@Test("A run that changes occurrence restarts instead of joining")
func routeJoinRequiresOneSteadyOccurrence() async throws {
  let runtime = try routeJoinRuntime(id: "test.product-release.join-drift")
  let context = runtime.entryTransitionAdmissionContext
  _ = await runtime.session.start()
  _ = await runtime.session.declareAlreadyOnRoute(atMilliseconds: 1_000)

  _ = try await runtime.session.observeRouteJoinEvidence(
    routeJoinEvidence(context: context, id: "drift.0", at: 1_500)
  )
  _ = try await runtime.session.observeRouteJoinEvidence(
    routeJoinEvidence(context: context, id: "drift.1", at: 3_000)
  )
  let drifted = try await runtime.session.observeRouteJoinEvidence(
    routeJoinEvidence(
      context: context,
      id: "drift.2",
      at: 4_000,
      occurrenceID: "test.occurrence.loop-edge-1"
    )
  )
  #expect(drifted.status == .observing)
  #expect(drifted.navigationSnapshot.journeyPhase == .planning)

  // A stalled run cannot be resumed by a fix arriving after the gap window.
  let afterGap = try await runtime.session.observeRouteJoinEvidence(
    routeJoinEvidence(
      context: context,
      id: "drift.3",
      at: 20_000,
      occurrenceID: "test.occurrence.loop-edge-1"
    )
  )
  #expect(afterGap.status == .observing)
  #expect(afterGap.navigationSnapshot.journeyPhase == .planning)
}

@Test("Route join evidence fails closed on every weak signal")
func routeJoinEvidenceFailsClosed() async throws {
  let runtime = try routeJoinRuntime(id: "test.product-release.join-rejects")
  let context = runtime.entryTransitionAdmissionContext
  _ = await runtime.session.start()

  let undeclared = try await runtime.session.observeRouteJoinEvidence(
    routeJoinEvidence(context: context, id: "closed.0", at: 500)
  )
  #expect(undeclared.rejectionReason == .notDeclaredByDriver)

  _ = await runtime.session.declareAlreadyOnRoute(atMilliseconds: 1_000)

  let simulated = try await runtime.session.observeRouteJoinEvidence(
    routeJoinEvidence(
      context: context,
      id: "closed.1",
      at: 1_100,
      isSimulated: true
    )
  )
  #expect(simulated.rejectionReason == .simulatedLocation)

  let weak = try await runtime.session.observeRouteJoinEvidence(
    routeJoinEvidence(
      context: context,
      id: "closed.2",
      at: 1_200,
      confidence: .medium
    )
  )
  #expect(weak.rejectionReason == .insufficientConfidence)

  let ambiguous = try await runtime.session.observeRouteJoinEvidence(
    routeJoinEvidence(
      context: context,
      id: "closed.3",
      at: 1_300,
      candidateEdgeIDs: ["test.edge.loop", "test.edge.exit"]
    )
  )
  #expect(ambiguous.rejectionReason == .ambiguousEdge)

  // The ramp window is 45 degrees; a join with no reviewed edge sequence
  // behind it holds a 30 degree window.
  let heading = try await runtime.session.observeRouteJoinEvidence(
    routeJoinEvidence(
      context: context,
      id: "closed.4",
      at: 1_400,
      headingErrorDegrees: 40
    )
  )
  #expect(heading.rejectionReason == .headingMismatch)

  let unknown = try await runtime.session.observeRouteJoinEvidence(
    routeJoinEvidence(
      context: context,
      id: "closed.5",
      at: 1_500,
      occurrenceID: "test.occurrence.not-in-plan"
    )
  )
  #expect(unknown.rejectionReason == .occurrenceNotInPlan)

  let unresolved = try await runtime.session.observeRouteJoinEvidence(
    routeJoinEvidence(
      context: context,
      id: "closed.6",
      at: 1_600,
      occurrenceID: nil
    )
  )
  #expect(unresolved.rejectionReason == .unresolvedOccurrence)

  #expect(unresolved.navigationSnapshot.journeyPhase == .planning)
}

@Test("A declaration the matcher cannot honor lapses instead of joining late")
func routeJoinDeclarationExpires() async throws {
  let runtime = try routeJoinRuntime(id: "test.product-release.join-expiry")
  let context = runtime.entryTransitionAdmissionContext
  _ = await runtime.session.start()
  _ = await runtime.session.declareAlreadyOnRoute(atMilliseconds: 1_000)

  let lapsed = try await runtime.session.observeRouteJoinEvidence(
    routeJoinEvidence(context: context, id: "expiry.0", at: 50_000)
  )
  #expect(lapsed.rejectionReason == .declarationExpired)
  #expect(await runtime.session.isAlreadyOnRouteDeclared == false)

  let afterLapse = try await runtime.session.observeRouteJoinEvidence(
    routeJoinEvidence(context: context, id: "expiry.1", at: 51_000)
  )
  #expect(afterLapse.rejectionReason == .notDeclaredByDriver)
  #expect(afterLapse.navigationSnapshot.journeyPhase == .planning)
}

@Test("Withdrawing the declaration closes the join path")
func routeJoinDeclarationCanBeWithdrawn() async throws {
  let runtime = try routeJoinRuntime(id: "test.product-release.join-withdraw")
  let context = runtime.entryTransitionAdmissionContext
  _ = await runtime.session.start()
  _ = await runtime.session.declareAlreadyOnRoute(atMilliseconds: 1_000)
  await runtime.session.withdrawAlreadyOnRouteDeclaration()

  let withdrawn = try await runtime.session.observeRouteJoinEvidence(
    routeJoinEvidence(context: context, id: "withdraw.0", at: 1_500)
  )
  #expect(withdrawn.rejectionReason == .notDeclaredByDriver)
}

private let routeJoinOccurrenceID = "test.occurrence.loop-edge-2"

private func routeJoinRuntime(
  id: String
) throws -> KaidoProductNavigationRuntime {
  let fixture = navigationReleaseBundleFixture()
  let release = try KaidoProductRelease(
    artifact: KaidoProductReleaseArtifact(
      releaseID: id,
      releasedAt: "2026-09-04T12:00:00+09:00",
      navigationRelease: navigationReleaseArtifact(fixture),
      routeAtlasRelease: productRouteAtlasArtifact(
        fixture,
        includeIncomingApproach: true
      )
    )
  )
  return try KaidoProductNavigationRuntime(release: release)
}

private func routeJoinEvidence(
  context: EntryTransitionAdmissionContext,
  id: String,
  at: Int,
  occurrenceID: String? = routeJoinOccurrenceID,
  directedEdgeID: String = "test.edge.loop",
  candidateEdgeIDs: [String]? = nil,
  confidence: MatcherConfidence = .high,
  headingErrorDegrees: Double? = 2,
  isSimulated: Bool = false
) -> RouteJoinEvidence {
  RouteJoinEvidence(
    context: context,
    observationID: id,
    observedAtMilliseconds: at,
    receivedAtMilliseconds: at,
    occurrenceID: occurrenceID,
    directedEdgeID: directedEdgeID,
    candidateEdgeIDs: candidateEdgeIDs ?? [directedEdgeID],
    confidence: confidence,
    headingErrorDegrees: headingErrorDegrees,
    isSimulatedBySoftware: isSimulated
  )
}
