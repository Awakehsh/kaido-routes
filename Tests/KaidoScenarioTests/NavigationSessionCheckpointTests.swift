import Foundation
import KaidoAppleAdapters
import KaidoDomain
import KaidoNavigation
import Testing

@Test("Checkpoint round-trip restores progress but requires fresh matcher continuity")
func navigationCheckpointRestoresConservatively() async throws {
  let release = try checkpointProductRelease()
  let bundle = release.navigation.bundle
  var snapshot = NavigationSnapshot(
    journeyPhase: .strictRoute,
    activeRoutePlanID: bundle.routePlan.id,
    currentOccurrenceID: "test.occurrence.entry",
    locationConfidence: .high
  )
  snapshot.strictRouteAutoCommitAllowed = true
  snapshot.emittedGuidancePromptIDs = ["test.prompt.loop-1"]
  snapshot.lastGuidancePromptID = "test.prompt.loop-1"
  snapshot.lastGuidanceProgressAtMilliseconds = 1_000
  snapshot.carPlayConnectionState = .connected
  snapshot.presentationSurface = .carPlay

  let checkpoint = try NavigationSessionCheckpoint.capture(
    release: release,
    snapshot: snapshot,
    savedAtMilliseconds: 2_000
  )
  let data = try NavigationSessionCheckpointCodec.encode(checkpoint)
  let decoded = try NavigationSessionCheckpointCodec.decode(data)
  #expect(
    try NavigationSessionCheckpointCodec.encode(decoded) == data
  )
  let restoredRuntime = try KaidoProductNavigationRuntime(
    release: release,
    checkpoint: decoded
  )
  let restored = await restoredRuntime.session.snapshot

  #expect(restoredRuntime.origin == .restored)
  #expect(restored.currentOccurrenceID == "test.occurrence.entry")
  #expect(restored.currentOccurrenceIndex == 0)
  #expect(restored.locationConfidence == .lost)
  #expect(restored.markerStyle == "ESTIMATED")
  #expect(restored.signalReacquisitionStatus == .pending)
  #expect(
    restored.ambiguityReason
      == "SESSION_RESTORATION_REACQUISITION_REQUIRED"
  )
  #expect(restored.carPlayConnectionState == .disconnected)
  #expect(restored.presentationSurface == .iPhone)
  #expect(restored.activeGuidanceFrame == nil)
  #expect(restored.emittedGuidancePromptIDs == ["test.prompt.loop-1"])

  let first = try await restoredRuntime.session.observe(
    checkpointMatcherObservation(
      longitude: 139.7602,
      observedAtMilliseconds: 3_000
    )
  )
  #expect(first.matcherEstimate.confidence == .low)
  #expect(first.guidanceProgressState == .insufficientMatcherEvidence)
  #expect(first.guidancePromptEmission == nil)
  #expect(
    first.navigationSnapshot.currentOccurrenceID
      == "test.occurrence.entry"
  )
  #expect(first.navigationSnapshot.locationConfidence == .low)
  #expect(first.navigationSnapshot.signalReacquisitionStatus == .pending)

  let second = try await restoredRuntime.session.observe(
    checkpointMatcherObservation(
      longitude: 139.7604,
      observedAtMilliseconds: 9_000
    )
  )
  #expect(second.guidancePromptEmission == nil)
  #expect(second.matcherEstimate.confidence == .low)
  #expect(second.guidanceProgressState == .insufficientMatcherEvidence)
  #expect(second.navigationSnapshot.signalReacquisitionStatus == .pending)

  let third = try await restoredRuntime.session.observe(
    checkpointMatcherObservation(
      longitude: 139.7605,
      observedAtMilliseconds: 10_000
    )
  )
  #expect(third.guidancePromptEmission == nil)
  #expect(third.matcherEstimate.confidence == .low)
  #expect(third.guidanceProgressState == .insufficientMatcherEvidence)
  #expect(third.navigationSnapshot.signalReacquisitionStatus == .confirmed)
  #expect(third.navigationSnapshot.emittedGuidancePromptIDs == ["test.prompt.loop-1"])
}

@Test("Checkpoint cannot inject an unknown released-guidance prompt")
func navigationCheckpointRejectsPromptLedgerInjection() throws {
  let release = try checkpointProductRelease()
  let checkpoint = try checkpointForRelease(release)
  let data = try NavigationSessionCheckpointCodec.encode(checkpoint)
  var root = try #require(
    JSONSerialization.jsonObject(with: data) as? [String: Any]
  )
  var state = try #require(root["state"] as? [String: Any])
  state["emitted_guidance_prompt_ids"] = ["test.prompt.unreleased"]
  state["last_guidance_prompt_id"] = "test.prompt.unreleased"
  root["state"] = state
  let injected = try NavigationSessionCheckpointCodec.decode(
    JSONSerialization.data(withJSONObject: root)
  )

  do {
    _ = try KaidoProductNavigationRuntime(
      release: release,
      checkpoint: injected
    )
    Issue.record("Expected an injected prompt ledger value to fail")
  } catch NavigationSessionCheckpointError.invalid(let issues) {
    #expect(
      issues.contains(
        .unknownGuidancePrompt("test.prompt.unreleased")
      )
    )
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Checkpoint cannot restore moving-edit or early strict-route authority")
func navigationCheckpointRejectsSafetyAuthorityInjection() throws {
  let release = try checkpointProductRelease()
  let checkpoint = try checkpointForRelease(release)
  let data = try NavigationSessionCheckpointCodec.encode(checkpoint)
  var root = try #require(
    JSONSerialization.jsonObject(with: data) as? [String: Any]
  )
  var state = try #require(root["state"] as? [String: Any])
  state["journey_phase"] = JourneyPhase.planning.rawValue
  state["requires_route_editing_while_moving"] = true
  state["shows_entry_route_shield_and_direction"] = false
  root["state"] = state
  let injected = try NavigationSessionCheckpointCodec.decode(
    JSONSerialization.data(withJSONObject: root)
  )

  do {
    _ = try KaidoProductNavigationRuntime(
      release: release,
      checkpoint: injected
    )
    Issue.record("Expected injected navigation authority to fail")
  } catch NavigationSessionCheckpointError.invalid(let issues) {
    #expect(issues.contains(.invalidRouteExecutionState))
    #expect(issues.contains(.invalidSafetyState))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Checkpoint release identity drift fails closed")
func navigationCheckpointRejectsReleaseDrift() throws {
  let release = try checkpointProductRelease()
  let checkpoint = try checkpointForRelease(release)
  let drifted = NavigationSessionCheckpoint(
    productReleaseID: checkpoint.productReleaseID,
    navigationReleaseID: checkpoint.navigationReleaseID,
    runtimePolicyID: checkpoint.runtimePolicyID,
    networkSnapshotID: checkpoint.networkSnapshotID,
    routePlanID: "test.plan.other",
    matcherCorridorID: checkpoint.matcherCorridorID,
    savedAtMilliseconds: checkpoint.savedAtMilliseconds,
    state: checkpoint.state
  )

  do {
    _ = try KaidoProductNavigationRuntime(
      release: release,
      checkpoint: drifted
    )
    Issue.record("Expected checkpoint identity drift to fail")
  } catch NavigationSessionCheckpointError.invalid(let issues) {
    #expect(issues.contains(.identityMismatch("route_plan_id")))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Checkpoint codec rejects unknown schema before runtime restoration")
func navigationCheckpointRejectsUnknownSchema() throws {
  let release = try checkpointProductRelease()
  let checkpoint = try checkpointForRelease(release)
  let unknown = NavigationSessionCheckpoint(
    schemaVersion: "2.0",
    productReleaseID: checkpoint.productReleaseID,
    navigationReleaseID: checkpoint.navigationReleaseID,
    runtimePolicyID: checkpoint.runtimePolicyID,
    networkSnapshotID: checkpoint.networkSnapshotID,
    routePlanID: checkpoint.routePlanID,
    matcherCorridorID: checkpoint.matcherCorridorID,
    savedAtMilliseconds: checkpoint.savedAtMilliseconds,
    state: checkpoint.state
  )

  #expect(
    throws: NavigationSessionCheckpointError.invalid([
      .invalidSchemaVersion
    ])
  ) {
    try NavigationSessionCheckpointCodec.encode(unknown)
  }
}

@Test("Partial entry evidence is never restored across a process boundary")
func navigationCheckpointDropsPartialEntryEvidence() throws {
  let release = try checkpointProductRelease()
  var snapshot = NavigationSnapshot(
    journeyPhase: .entryTransition,
    activeRoutePlanID: release.navigation.bundle.routePlan.id,
    currentOccurrenceID: "test.occurrence.entry",
    locationConfidence: .high
  )
  snapshot.strictRouteAutoCommitAllowed = false
  let checkpoint = try NavigationSessionCheckpoint.capture(
    release: release,
    snapshot: snapshot,
    savedAtMilliseconds: 1_000
  )
  let restored = try checkpoint.restoredSnapshot(for: release)

  #expect(restored.journeyPhase == .approachToEntry)
  #expect(!restored.strictRouteAutoCommitAllowed)
  #expect(
    restored.lastPhaseTransitionTrigger
      == "SESSION_RESTORED_ENTRY_EVIDENCE_RESET"
  )
}

@MainActor
@Test("File checkpoint store atomically round-trips and removes one active session")
func fileNavigationCheckpointStoreRoundTrips() throws {
  let directoryURL = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer {
    try? FileManager.default.removeItem(at: directoryURL)
  }
  let store = try FileNavigationSessionCheckpointStore(
    directoryURL: directoryURL
  )
  let checkpoint = try checkpointForRelease(
    checkpointProductRelease()
  )

  #expect(try store.load() == nil)
  try store.save(checkpoint)
  #expect(try store.load() == checkpoint)
  try store.remove()
  #expect(try store.load() == nil)
}

private func checkpointProductRelease() throws -> KaidoProductRelease {
  let fixture = navigationReleaseBundleFixture()
  return try KaidoProductRelease(
    artifact: KaidoProductReleaseArtifact(
      releaseID: "test.product-release.checkpoint",
      releasedAt: "2026-07-24T12:00:00+09:00",
      navigationRelease: navigationReleaseArtifact(fixture),
      routeAtlasRelease: productRouteAtlasArtifact(
        fixture,
        includeIncomingApproach: true
      )
    )
  )
}

private func checkpointForRelease(
  _ release: KaidoProductRelease
) throws -> NavigationSessionCheckpoint {
  var snapshot = NavigationSnapshot(
    journeyPhase: .strictRoute,
    activeRoutePlanID: release.navigation.bundle.routePlan.id,
    currentOccurrenceID: "test.occurrence.entry",
    locationConfidence: .high
  )
  snapshot.strictRouteAutoCommitAllowed = true
  return try NavigationSessionCheckpoint.capture(
    release: release,
    snapshot: snapshot,
    savedAtMilliseconds: 2_000
  )
}

private func checkpointMatcherObservation(
  longitude: Double,
  observedAtMilliseconds: Int
) -> RouteMatcherObservation {
  RouteMatcherObservation(
    observedAtMilliseconds: observedAtMilliseconds,
    receivedAtMilliseconds: observedAtMilliseconds,
    coordinate: MatcherCoordinate(
      latitude: 35.68,
      longitude: longitude
    ),
    horizontalAccuracyMeters: 3,
    courseDegrees: 90,
    speedMetersPerSecond: 20,
    source: .phone
  )
}
