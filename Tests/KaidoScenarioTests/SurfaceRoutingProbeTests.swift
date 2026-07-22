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
