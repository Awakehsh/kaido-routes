import Foundation
import KaidoSurfaceRouting
import Testing

#if canImport(MapKit)
  import KaidoAppleAdapters
#endif

@Test("Synthetic entrance fixture is structurally valid but cannot be released")
func syntheticEntranceFixtureValidation() throws {
  let fixture = try loadSyntheticEntranceFixture()

  #expect(fixture.structuralValidationIssues().isEmpty)
  #expect(
    fixture.releaseValidationIssues().map(\.code).contains("NOT_RELEASED")
  )
  #expect(fixture.origins.count == 3)
  #expect(Set(fixture.origins.map(\.kind)) == Set(ProbeOrigin.Kind.allCases))
}

@Test("A fully inspected surface candidate passes every hard gate")
func inspectedSurfaceCandidatePasses() throws {
  let fixture = try loadSyntheticEntranceFixture()
  let request = try fixture.makeRequest(originID: "test.origin.inner.same-side")
  let candidate = makeCandidate(request: request)
  let inspection = makePassingInspection(fixture: fixture)

  let result = SurfaceHardGateEvaluator.evaluate(
    candidate: candidate,
    request: request,
    fixture: fixture,
    inspection: inspection,
    expectedProviderID: "test.provider"
  )

  #expect(result.disposition == .accepted)
  #expect(result.hardGates.count == SurfaceHardGate.allCases.count)
  #expect(result.hardGates.allSatisfy { $0.status == .pass })
}

@Test("Missing or conflicting inspection evidence fails closed")
func surfaceCandidateInspectionFailsClosed() throws {
  let fixture = try loadSyntheticEntranceFixture()
  let validRequest = try fixture.makeRequest(originID: "test.origin.inner.same-side")
  let request = SurfaceRouteRequest(
    id: validRequest.id,
    originID: validRequest.originID,
    origin: validRequest.origin,
    entranceFacilityID: "test.entry.wrong",
    selectedJoinOccurrenceID: "test.occurrence.wrong",
    destinationAnchor: validRequest.destinationAnchor
  )
  let candidate = SurfaceRouteCandidate(
    id: "test.candidate.invalid",
    providerID: "test.provider",
    coordinates: [request.origin],
    steps: [],
    distanceMeters: 10,
    expectedTravelTimeSeconds: 5
  )
  let inspection = SurfaceCandidateInspection(
    anchorBinding: AnchorBindingObservation(
      anchorID: fixture.approachAnchor.id,
      directedSurfaceEdgeID: "test.surface-edge.wrong",
      terminalDistanceMeters: 100,
      terminalBearingDegrees: 270
    ),
    geometryBindingIsUnambiguous: false,
    expresswayEdgeIDsBeforeEntry: ["test.expressway-edge.wrong-early-entry"],
    crossedTollDomainIDs: ["test.toll-domain.external"]
  )

  let result = SurfaceHardGateEvaluator.evaluate(
    candidate: candidate,
    request: request,
    fixture: fixture,
    inspection: inspection,
    expectedProviderID: "test.provider"
  )
  let statuses = Dictionary(uniqueKeysWithValues: result.hardGates.map { ($0.gate, $0.status) })

  #expect(result.disposition == .rejected)
  #expect(statuses[.correctDirectedApproach] == .fail)
  #expect(statuses[.noEarlyExpressway] == .fail)
  #expect(statuses[.compatibleRouteJoin] == .fail)
  #expect(statuses[.allowedTollDomain] == .fail)
  #expect(statuses[.geometryBindable] == .fail)
  #expect(statuses[.honestProviderStatus] == .pass)
}

@Test("Disconnected directed geometry has a distinct hard-gate reason")
func disconnectedSurfaceGeometryReason() throws {
  let fixture = try loadSyntheticEntranceFixture()
  let request = try fixture.makeRequest(originID: "test.origin.inner.same-side")
  let candidate = makeCandidate(request: request)
  let inspection = SurfaceCandidateInspection(
    anchorBinding: makePassingInspection(fixture: fixture).anchorBinding,
    geometryBindingIsUnambiguous: false,
    expresswayEdgeIDsBeforeEntry: [],
    crossedTollDomainIDs: [],
    unmatchedSampleCount: 0,
    ambiguousDirectedEdgeIDs: [],
    disconnectedDirectedEdgeIDs: ["test.edge.before-gap", "test.edge.after-gap"],
    resolvedPathEdgeIDs: ["test.edge.before-gap", "test.edge.after-gap"]
  )

  let result = SurfaceHardGateEvaluator.evaluate(
    candidate: candidate,
    request: request,
    fixture: fixture,
    inspection: inspection,
    expectedProviderID: "test.provider"
  )
  let geometryGate = result.hardGates.first { $0.gate == .geometryBindable }

  #expect(geometryGate?.status == .fail)
  #expect(geometryGate?.reasonCodes == ["GEOMETRY_PATH_DISCONNECTED"])
}

@Test("Probe runner records accepted candidates without live routing")
func offlineProbeRunnerAcceptsInspectedCandidate() async throws {
  let fixture = try loadSyntheticEntranceFixture()
  let request = try fixture.makeRequest(originID: "test.origin.inner.same-side")
  let provider = FakeSurfaceProvider(response: .success([makeCandidate(request: request)]))
  let inspector = FakeSurfaceInspector(inspection: makePassingInspection(fixture: fixture))
  let runner = SurfaceProbeRunner(provider: provider, inspector: inspector)
  let context = SurfaceProbeRunContext(
    runID: "test.run.accepted",
    requestedAt: "2026-07-22T12:00:00+09:00",
    environment: ["mode": "offline-fixture"]
  )

  let result = try await runner.run(
    fixture: fixture,
    originID: "test.origin.inner.same-side",
    context: context
  )

  #expect(result.responseStatus == .success)
  #expect(result.decision == .pass)
  #expect(result.providerLatencyMilliseconds >= 0)
  #expect(result.evaluations[0].inspectionLatencyMilliseconds != nil)
  #expect(result.evaluations[0].inspectionLatencyMilliseconds! >= 0)
  #expect(result.evaluations.count == 1)
  #expect(
    try JSONDecoder().decode(SurfaceProbeResult.self, from: JSONEncoder().encode(result)) == result)
}

@Test("Repeated probes produce a scalar-only stable summary")
func repeatedSurfaceProbesProduceStableScalarSummary() throws {
  let results = try [
    makeStabilityResult(
      runID: "test.stability.1",
      requestedAt: "2026-07-22T12:00:00+09:00",
      pathEdgeIDs: ["secret.provider.edge.a", "secret.provider.edge.b"],
      distanceMeters: 120,
      providerLatencyMilliseconds: 10,
      inspectionLatencyMilliseconds: 3
    ),
    makeStabilityResult(
      runID: "test.stability.2",
      requestedAt: "2026-07-22T12:01:00+09:00",
      pathEdgeIDs: ["secret.provider.edge.a", "secret.provider.edge.b"],
      distanceMeters: 121,
      providerLatencyMilliseconds: 30,
      inspectionLatencyMilliseconds: 7
    ),
  ]

  let summary = try SurfaceProbeStabilitySummarizer.summarize(results)
  let encoded = try JSONEncoder().encode(summary)
  let json = String(decoding: encoded, as: UTF8.self)

  #expect(summary.assessment == .stablePass)
  #expect(summary.retentionClassification == .scalarLocalOnly)
  #expect(summary.runCount == 2)
  #expect(summary.passingRunCount == 2)
  #expect(summary.failingRunCount == 0)
  #expect(summary.acceptedResolvedPathVariantCount == 1)
  #expect(summary.acceptedRouteSetVariantCount == 1)
  #expect(summary.providerLatencyMilliseconds.minimum == 10)
  #expect(summary.providerLatencyMilliseconds.median == 20)
  #expect(summary.providerLatencyMilliseconds.percentile95 == 30)
  #expect(summary.inspectionLatencyPerRunMilliseconds?.maximum == 7)
  #expect(summary.acceptedDistanceMeters == SurfaceProbeDoubleRange(minimum: 120, maximum: 121))
  #expect(!json.contains("secret.provider.edge"))
  #expect(!json.contains("provider-only instruction"))
  #expect(!json.contains("latitude"))
  #expect(
    try JSONDecoder().decode(SurfaceProbeStabilitySummary.self, from: encoded) == summary)
}

@Test("Repeated probes distinguish route variability from a failed run")
func repeatedSurfaceProbesClassifyVariabilityAndFailure() throws {
  let first = try makeStabilityResult(
    runID: "test.variability.1",
    requestedAt: "2026-07-22T12:00:00+09:00",
    pathEdgeIDs: ["test.path.a"],
    distanceMeters: 120,
    providerLatencyMilliseconds: 10,
    inspectionLatencyMilliseconds: 3
  )
  let second = try makeStabilityResult(
    runID: "test.variability.2",
    requestedAt: "2026-07-22T12:01:00+09:00",
    pathEdgeIDs: ["test.path.b"],
    distanceMeters: 121,
    providerLatencyMilliseconds: 11,
    inspectionLatencyMilliseconds: 4
  )
  let failed = try makeStabilityResult(
    runID: "test.variability.3",
    requestedAt: "2026-07-22T12:02:00+09:00",
    pathEdgeIDs: [],
    distanceMeters: 0,
    providerLatencyMilliseconds: 12,
    inspectionLatencyMilliseconds: 5,
    accepted: false
  )

  let variableSummary = try SurfaceProbeStabilitySummarizer.summarize([first, second])
  let failedSummary = try SurfaceProbeStabilitySummarizer.summarize([first, failed])

  #expect(variableSummary.assessment == .variablePass)
  #expect(variableSummary.acceptedResolvedPathVariantCount == 2)
  #expect(variableSummary.acceptedRouteSetVariantCount == 2)
  #expect(failedSummary.assessment == .fail)
  #expect(failedSummary.passingRunCount == 1)
  #expect(failedSummary.failingRunCount == 1)
  #expect(failedSummary.hardGateFailureCounts[SurfaceHardGate.geometryBindable.rawValue] == 1)
}

@Test("A disclosed provider failure is honest but does not pass the entrance run")
func disclosedProviderFailureStillFailsRun() async throws {
  let fixture = try loadSyntheticEntranceFixture()
  let failure = SurfaceProviderFailure(
    kind: .noRoute,
    providerErrorCode: "TEST_NO_ROUTE"
  )
  let provider = FakeSurfaceProvider(response: .failure(failure))
  let inspector = FakeSurfaceInspector(inspection: makePassingInspection(fixture: fixture))
  let runner = SurfaceProbeRunner(provider: provider, inspector: inspector)

  let result = try await runner.run(
    fixture: fixture,
    originID: "test.origin.inner.cross-direction",
    context: SurfaceProbeRunContext(
      runID: "test.run.provider-failure",
      requestedAt: "2026-07-22T12:00:00+09:00",
      environment: ["mode": "offline-fixture"]
    )
  )
  let gates = result.evaluations[0].hardGates
  let status = Dictionary(uniqueKeysWithValues: gates.map { ($0.gate, $0.status) })

  #expect(result.responseStatus == .providerFailure)
  #expect(result.decision == .fail)
  #expect(result.providerFailure == failure)
  #expect(status[.honestProviderStatus] == .pass)
  #expect(status[.correctDirectedApproach] == .notEvaluated)
}

#if canImport(MapKit)
  @Test("MapKit adapter declares an unresolved data-use review and performs no live request")
  func mapKitAdapterBoundary() {
    let provider = MapKitSurfaceRouteProvider()

    #expect(provider.metadata.id == "apple.mapkit")
    #expect(provider.metadata.providerVersion == nil)
    #expect(provider.metadata.dataReviewStatus == .reviewRequired)
  }
#endif

private struct FakeSurfaceProvider: SurfaceRouteProvider {
  let metadata = SurfaceRouteProviderMetadata(
    id: "test.provider",
    adapterVersion: "1.0.0",
    providerVersion: "fixture",
    dataReviewStatus: .derivedFixtureReviewed
  )
  let response: SurfaceProviderResponse

  func routes(for request: SurfaceRouteRequest) async -> SurfaceProviderResponse {
    response
  }
}

private struct FakeSurfaceInspector: SurfaceCandidateInspector {
  let inspection: SurfaceCandidateInspection

  func inspect(
    candidate: SurfaceRouteCandidate,
    request: SurfaceRouteRequest,
    fixture: EntranceProbeFixture
  ) async -> SurfaceCandidateInspection {
    inspection
  }
}

private func makeCandidate(request: SurfaceRouteRequest) -> SurfaceRouteCandidate {
  SurfaceRouteCandidate(
    id: "test.candidate.accepted",
    providerID: "test.provider",
    coordinates: [request.origin, request.destinationAnchor.coordinate],
    steps: [
      SurfaceRouteStep(
        id: "test.step.approach",
        instruction: "Continue to the directed approach anchor",
        distanceMeters: 120
      )
    ],
    distanceMeters: 120,
    expectedTravelTimeSeconds: 40,
    hasHighways: false,
    hasTolls: false
  )
}

private func makePassingInspection(
  fixture: EntranceProbeFixture
) -> SurfaceCandidateInspection {
  SurfaceCandidateInspection(
    anchorBinding: AnchorBindingObservation(
      anchorID: fixture.approachAnchor.id,
      directedSurfaceEdgeID: fixture.approachAnchor.directedSurfaceEdgeID,
      terminalDistanceMeters: 5,
      terminalBearingDegrees: fixture.approachAnchor.expectedBearingDegrees
    ),
    geometryBindingIsUnambiguous: true,
    expresswayEdgeIDsBeforeEntry: [],
    crossedTollDomainIDs: []
  )
}

private func makeStabilityResult(
  runID: String,
  requestedAt: String,
  pathEdgeIDs: [String],
  distanceMeters: Double,
  providerLatencyMilliseconds: Int,
  inspectionLatencyMilliseconds: Int,
  accepted: Bool = true
) throws -> SurfaceProbeResult {
  let fixture = try loadSyntheticEntranceFixture()
  let request = try fixture.makeRequest(originID: "test.origin.inner.same-side")
  let candidate = SurfaceRouteCandidate(
    id: "secret.provider.candidate",
    providerID: "test.provider",
    coordinates: [request.origin, request.destinationAnchor.coordinate],
    steps: [
      SurfaceRouteStep(
        id: "secret.provider.step",
        instruction: "provider-only instruction",
        distanceMeters: distanceMeters
      )
    ],
    distanceMeters: distanceMeters,
    expectedTravelTimeSeconds: 40,
    hasHighways: false,
    hasTolls: false
  )
  let inspection = SurfaceCandidateInspection(
    anchorBinding: accepted
      ? AnchorBindingObservation(
        anchorID: fixture.approachAnchor.id,
        directedSurfaceEdgeID: fixture.approachAnchor.directedSurfaceEdgeID,
        terminalDistanceMeters: 5,
        terminalBearingDegrees: fixture.approachAnchor.expectedBearingDegrees
      )
      : nil,
    geometryBindingIsUnambiguous: accepted,
    expresswayEdgeIDsBeforeEntry: [],
    crossedTollDomainIDs: [],
    unmatchedSampleCount: accepted ? 0 : 1,
    ambiguousDirectedEdgeIDs: [],
    disconnectedDirectedEdgeIDs: [],
    resolvedPathEdgeIDs: pathEdgeIDs
  )
  let gates = SurfaceHardGate.allCases.map { gate in
    HardGateResult(
      gate: gate,
      status: accepted || gate != .geometryBindable ? .pass : .fail,
      reasonCodes: accepted || gate != .geometryBindable ? [] : ["GEOMETRY_SAMPLES_UNMATCHED"]
    )
  }
  let evaluation = SurfaceCandidateEvaluation(
    candidateID: candidate.id,
    candidate: candidate,
    inspection: inspection,
    inspectionLatencyMilliseconds: inspectionLatencyMilliseconds,
    disposition: accepted ? .accepted : .rejected,
    hardGates: gates
  )

  return SurfaceProbeResult(
    context: SurfaceProbeRunContext(
      runID: runID,
      requestedAt: requestedAt,
      environment: ["mode": "offline-stability"]
    ),
    fixtureID: fixture.id,
    originID: "test.origin.inner.same-side",
    request: request,
    provider: FakeSurfaceProvider(response: .success([])).metadata,
    responseStatus: .success,
    providerFailure: nil,
    evaluations: [evaluation],
    providerLatencyMilliseconds: providerLatencyMilliseconds
  )
}

private func loadSyntheticEntranceFixture() throws -> EntranceProbeFixture {
  let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let fixtureURL =
    repositoryRoot
    .appendingPathComponent("benchmarks", isDirectory: true)
    .appendingPathComponent("surface-routing", isDirectory: true)
    .appendingPathComponent("fixtures", isDirectory: true)
    .appendingPathComponent("synthetic", isDirectory: true)
    .appendingPathComponent("test-inner-entry.json")

  return try JSONDecoder().decode(
    EntranceProbeFixture.self,
    from: Data(contentsOf: fixtureURL)
  )
}
