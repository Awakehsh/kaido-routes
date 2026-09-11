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

@Test("A run that moves backward restarts instead of joining")
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

  // MEDIUM already means no independent carriageway competes; LOW does not.
  let weak = try await runtime.session.observeRouteJoinEvidence(
    routeJoinEvidence(
      context: context,
      id: "closed.2",
      at: 1_200,
      confidence: .low
    )
  )
  #expect(weak.rejectionReason == .insufficientConfidence)

  // Indistinguishable geometry leaves the matcher without an edge at all.
  let ambiguous = try await runtime.session.observeRouteJoinEvidence(
    routeJoinEvidence(
      context: context,
      id: "closed.3",
      at: 1_300,
      directedEdgeID: nil,
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

@Test("A run that advances along the plan joins at its latest occurrence")
func routeJoinFollowsForwardProgressAlongThePlan() async throws {
  let runtime = try routeJoinRuntime(id: "test.product-release.join-forward")
  let context = runtime.entryTransitionAdmissionContext
  _ = await runtime.session.start()
  _ = await runtime.session.declareAlreadyOnRoute(atMilliseconds: 1_000)

  // Short segments put consecutive fixes on successive occurrences, and a
  // fix near a segment boundary lists the neighbouring segment as well.
  let first = try await runtime.session.observeRouteJoinEvidence(
    routeJoinEvidence(
      context: context, id: "forward.0", at: 1_500,
      occurrenceID: "test.occurrence.loop-edge-1",
      candidateEdgeIDs: ["test.edge.loop", "test.edge.loop-1"],
      confidence: .medium
    )
  )
  #expect(first.status == .observing)
  let second = try await runtime.session.observeRouteJoinEvidence(
    routeJoinEvidence(
      context: context, id: "forward.1", at: 2_500,
      occurrenceID: "test.occurrence.loop-movement-2"
    )
  )
  #expect(second.status == .observing)
  let third = try await runtime.session.observeRouteJoinEvidence(
    routeJoinEvidence(
      context: context, id: "forward.2", at: 3_500,
      candidateEdgeIDs: ["test.edge.loop", "test.edge.loop-1"],
      confidence: .medium
    )
  )
  #expect(third.status == .joined)
  #expect(third.joinedOccurrenceID == routeJoinOccurrenceID)
  #expect(third.navigationSnapshot.currentOccurrenceID == routeJoinOccurrenceID)
  #expect(
    third.navigationSnapshot.skippedOccurrenceIDs == [
      "test.occurrence.entry",
      "test.occurrence.loop-movement-1",
      "test.occurrence.loop-edge-1",
      "test.occurrence.loop-movement-2",
    ]
  )
}

@Test("A run that jumps further ahead than the candidate window restarts")
func routeJoinRejectsALeapAlongThePlan() throws {
  let occurrences = (0..<40).map {
    RouteOccurrence(
      id: "test.occurrence.long.\($0)", index: $0, kind: .edge,
      entityID: "test.edge.long.\($0)"
    )
  }
  let plan = RoutePlan(
    id: "test.plan.long", networkSnapshotID: "test.snapshot.long",
    entryFacilityID: "test.entrance.long", exitFacilityID: "test.exit.long",
    recoveryPolicy: .strict, occurrences: occurrences
  )
  var run = RouteJoinRun(routePlan: plan)
  let window = RouteJoinRun.maximumOccurrenceAdvance
  func extended(_ index: Int, at: Int) -> Bool {
    run.extend(occurrenceID: occurrences[index].id, atMilliseconds: at)
  }
  // Advancing by the whole window still continues the run.
  #expect(!extended(0, at: 1_000))
  #expect(!extended(window, at: 2_000))
  #expect(extended(2 * window, at: 3_000))
  // One occurrence beyond the window is a leap, and the run starts over.
  #expect(!extended(3 * window + 1, at: 4_000))
  #expect(!extended(3 * window + 1, at: 5_000))
  #expect(extended(3 * window + 2, at: 6_000))
  let unknown = run.extend(
    occurrenceID: "test.occurrence.not-in-plan", atMilliseconds: 7_000
  )
  #expect(!unknown)
}

@Test("The declaration is offered only after a steady on-route run")
func routeJoinOfferNeedsASteadyHeadingCompatibleRun() throws {
  let context = try routeJoinRuntime(id: "test.product-release.join-offer")
    .entryTransitionAdmissionContext
  var offer = RouteJoinOffer(routePlan: navigationReleaseBundleFixture().routePlan)
  func observed(
    _ id: String, at: Int, occurrenceID: String? = routeJoinOccurrenceID,
    directedEdgeID: String? = "test.edge.loop",
    candidateEdgeIDs: [String]? = nil, confidence: MatcherConfidence = .high,
    headingErrorDegrees: Double? = 2
  ) -> Bool {
    offer.observe(
      routeJoinEvidence(
        context: context, id: id, at: at, occurrenceID: occurrenceID,
        directedEdgeID: directedEdgeID, candidateEdgeIDs: candidateEdgeIDs,
        confidence: confidence, headingErrorDegrees: headingErrorDegrees
      )
    )
  }

  // MEDIUM with a neighbouring segment as second candidate is the ordinary
  // on-route estimate at driving speed and counts toward the offer.
  #expect(
    !observed(
      "o.0", at: 1_000, candidateEdgeIDs: ["test.edge.loop", "test.edge.loop-1"],
      confidence: .medium
    )
  )
  #expect(!observed("o.1", at: 2_000))
  #expect(observed("o.2", at: 3_000))
  #expect(observed("o.3", at: 4_000))

  // A fix the matcher cannot place breaks the run, but the offer outlives
  // it for a short grace so a momentary abstention does not flicker it off.
  #expect(observed("o.4", at: 5_000, occurrenceID: nil))
  #expect(observed("o.5", at: 14_000, confidence: .low))
  #expect(!observed("o.6", at: 15_000, confidence: .low))

  // Once withdrawn, every gate refusal keeps it withdrawn, and a single good
  // fix after a refusal is only the start of a new run.
  #expect(!observed("o.7", at: 16_000))
  #expect(!observed("o.8", at: 17_000, headingErrorDegrees: 45))
  #expect(!observed("o.9", at: 18_000, headingErrorDegrees: nil))
  #expect(!observed("o.10", at: 19_000, directedEdgeID: nil))
  #expect(!observed("o.11", at: 20_000, occurrenceID: "test.occurrence.not-in-plan"))
  #expect(!observed("o.12", at: 21_000))
  #expect(!observed("o.13", at: 22_000))
  #expect(observed("o.14", at: 23_000))

  // Forward progress along the plan continues the run; a pause longer than
  // the car could stay unobserved starts it over and, past the grace,
  // withdraws the offer until three fresh fixes hold.
  #expect(observed("o.15", at: 24_000, occurrenceID: "test.occurrence.loop-edge-1"))
  #expect(!observed("o.16", at: 40_000, occurrenceID: "test.occurrence.loop-edge-1"))
  #expect(!observed("o.17", at: 41_000, occurrenceID: "test.occurrence.loop-movement-2"))
  #expect(observed("o.18", at: 42_000))

  offer.reset()
  #expect(!observed("o.19", at: 43_000))
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
  directedEdgeID: String? = "test.edge.loop",
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
    candidateEdgeIDs: candidateEdgeIDs ?? [directedEdgeID ?? "test.edge.loop"],
    confidence: confidence,
    headingErrorDegrees: headingErrorDegrees,
    isSimulatedBySoftware: isSimulated
  )
}
