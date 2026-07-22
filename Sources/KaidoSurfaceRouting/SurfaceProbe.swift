import Foundation

public struct AnchorBindingObservation: Codable, Equatable, Sendable {
  public let anchorID: String
  public let directedSurfaceEdgeID: String
  public let terminalDistanceMeters: Double
  public let terminalBearingDegrees: Double

  public init(
    anchorID: String,
    directedSurfaceEdgeID: String,
    terminalDistanceMeters: Double,
    terminalBearingDegrees: Double
  ) {
    self.anchorID = anchorID
    self.directedSurfaceEdgeID = directedSurfaceEdgeID
    self.terminalDistanceMeters = terminalDistanceMeters
    self.terminalBearingDegrees = terminalBearingDegrees
  }

  private enum CodingKeys: String, CodingKey {
    case anchorID = "anchor_id"
    case directedSurfaceEdgeID = "directed_surface_edge_id"
    case terminalDistanceMeters = "terminal_distance_meters"
    case terminalBearingDegrees = "terminal_bearing_degrees"
  }
}

public struct SurfaceCandidateInspection: Codable, Equatable, Sendable {
  public let anchorBinding: AnchorBindingObservation?
  public let geometryBindingIsUnambiguous: Bool?
  public let expresswayEdgeIDsBeforeEntry: [String]?
  public let crossedTollDomainIDs: [String]?

  public init(
    anchorBinding: AnchorBindingObservation?,
    geometryBindingIsUnambiguous: Bool?,
    expresswayEdgeIDsBeforeEntry: [String]?,
    crossedTollDomainIDs: [String]?
  ) {
    self.anchorBinding = anchorBinding
    self.geometryBindingIsUnambiguous = geometryBindingIsUnambiguous
    self.expresswayEdgeIDsBeforeEntry = expresswayEdgeIDsBeforeEntry
    self.crossedTollDomainIDs = crossedTollDomainIDs
  }

  private enum CodingKeys: String, CodingKey {
    case anchorBinding = "anchor_binding"
    case geometryBindingIsUnambiguous = "geometry_binding_is_unambiguous"
    case expresswayEdgeIDsBeforeEntry = "expressway_edge_ids_before_entry"
    case crossedTollDomainIDs = "crossed_toll_domain_ids"
  }
}

public enum SurfaceHardGate: String, Codable, CaseIterable, Sendable {
  case correctDirectedApproach = "CORRECT_DIRECTED_APPROACH"
  case noEarlyExpressway = "NO_EARLY_EXPRESSWAY"
  case compatibleRouteJoin = "COMPATIBLE_ROUTE_JOIN"
  case allowedTollDomain = "ALLOWED_TOLL_DOMAIN"
  case geometryBindable = "GEOMETRY_BINDABLE"
  case honestProviderStatus = "HONEST_PROVIDER_STATUS"
}

public enum HardGateStatus: String, Codable, Sendable {
  case pass = "PASS"
  case fail = "FAIL"
  case notEvaluated = "NOT_EVALUATED"
}

public struct HardGateResult: Codable, Equatable, Sendable {
  public let gate: SurfaceHardGate
  public let status: HardGateStatus
  public let reasonCodes: [String]

  public init(gate: SurfaceHardGate, status: HardGateStatus, reasonCodes: [String] = []) {
    self.gate = gate
    self.status = status
    self.reasonCodes = reasonCodes
  }

  private enum CodingKeys: String, CodingKey {
    case gate
    case status
    case reasonCodes = "reason_codes"
  }
}

public enum SurfaceProbeDisposition: String, Codable, Sendable {
  case accepted = "ACCEPTED"
  case rejected = "REJECTED"
  case providerFailure = "PROVIDER_FAILURE"
  case invalidResponse = "INVALID_RESPONSE"
}

public struct SurfaceCandidateEvaluation: Codable, Equatable, Sendable {
  public let candidateID: String?
  public let candidate: SurfaceRouteCandidate?
  public let inspection: SurfaceCandidateInspection?
  public let disposition: SurfaceProbeDisposition
  public let hardGates: [HardGateResult]

  public init(
    candidateID: String?,
    candidate: SurfaceRouteCandidate? = nil,
    inspection: SurfaceCandidateInspection? = nil,
    disposition: SurfaceProbeDisposition,
    hardGates: [HardGateResult]
  ) {
    self.candidateID = candidateID
    self.candidate = candidate
    self.inspection = inspection
    self.disposition = disposition
    self.hardGates = hardGates
  }

  public var isAccepted: Bool { disposition == .accepted }

  private enum CodingKeys: String, CodingKey {
    case candidateID = "candidate_id"
    case candidate
    case inspection
    case disposition
    case hardGates = "hard_gates"
  }
}

public enum SurfaceHardGateEvaluator {
  public static func evaluate(
    candidate: SurfaceRouteCandidate,
    request: SurfaceRouteRequest,
    fixture: EntranceProbeFixture,
    inspection: SurfaceCandidateInspection,
    expectedProviderID: String
  ) -> SurfaceCandidateEvaluation {
    let gates = [
      directedApproachGate(request: request, fixture: fixture, inspection: inspection),
      earlyExpresswayGate(fixture: fixture, inspection: inspection),
      routeJoinGate(request: request, fixture: fixture),
      tollDomainGate(fixture: fixture, inspection: inspection),
      geometryGate(candidate: candidate, inspection: inspection),
      providerStatusGate(candidate: candidate, expectedProviderID: expectedProviderID),
    ]
    let disposition: SurfaceProbeDisposition =
      gates.allSatisfy { $0.status == .pass } ? .accepted : .rejected

    return SurfaceCandidateEvaluation(
      candidateID: candidate.id,
      candidate: candidate,
      inspection: inspection,
      disposition: disposition,
      hardGates: gates
    )
  }

  public static func disclosedFailure(
    _ failure: SurfaceProviderFailure
  ) -> SurfaceCandidateEvaluation {
    var gates = notEvaluatedGates()
    replace(
      gate: .honestProviderStatus,
      in: &gates,
      with: HardGateResult(
        gate: .honestProviderStatus,
        status: .pass,
        reasonCodes: ["PROVIDER_FAILURE_DISCLOSED_\(failure.kind.rawValue)"]
      )
    )
    return SurfaceCandidateEvaluation(
      candidateID: nil,
      disposition: .providerFailure,
      hardGates: gates
    )
  }

  public static func invalidEmptySuccess() -> SurfaceCandidateEvaluation {
    var gates = notEvaluatedGates()
    replace(
      gate: .honestProviderStatus,
      in: &gates,
      with: HardGateResult(
        gate: .honestProviderStatus,
        status: .fail,
        reasonCodes: ["EMPTY_SUCCESS_RESPONSE"]
      )
    )
    return SurfaceCandidateEvaluation(
      candidateID: nil,
      disposition: .invalidResponse,
      hardGates: gates
    )
  }

  private static func directedApproachGate(
    request: SurfaceRouteRequest,
    fixture: EntranceProbeFixture,
    inspection: SurfaceCandidateInspection
  ) -> HardGateResult {
    var reasons: [String] = []
    if request.destinationAnchor.id != fixture.approachAnchor.id {
      reasons.append("REQUEST_ANCHOR_MISMATCH")
    }
    guard let binding = inspection.anchorBinding else {
      reasons.append("ANCHOR_BINDING_MISSING")
      return gate(.correctDirectedApproach, reasons: reasons)
    }
    if binding.anchorID != fixture.approachAnchor.id {
      reasons.append("ANCHOR_ID_MISMATCH")
    }
    if binding.directedSurfaceEdgeID != fixture.approachAnchor.directedSurfaceEdgeID {
      reasons.append("APPROACH_EDGE_MISMATCH")
    }
    if binding.terminalDistanceMeters > fixture.approachAnchor.maxTerminalDistanceMeters {
      reasons.append("TERMINAL_TOO_FAR")
    }
    if binding.terminalDistanceMeters < 0 {
      reasons.append("INVALID_TERMINAL_DISTANCE")
    }
    if !(0..<360).contains(binding.terminalBearingDegrees) {
      reasons.append("INVALID_TERMINAL_BEARING")
    }
    if angularDifference(
      binding.terminalBearingDegrees,
      fixture.approachAnchor.expectedBearingDegrees
    ) > fixture.approachAnchor.bearingToleranceDegrees {
      reasons.append("TERMINAL_HEADING_MISMATCH")
    }
    return gate(.correctDirectedApproach, reasons: reasons)
  }

  private static func earlyExpresswayGate(
    fixture: EntranceProbeFixture,
    inspection: SurfaceCandidateInspection
  ) -> HardGateResult {
    guard let edgeIDs = inspection.expresswayEdgeIDsBeforeEntry else {
      return gate(.noEarlyExpressway, reasons: ["EARLY_EXPRESSWAY_INSPECTION_MISSING"])
    }
    guard !edgeIDs.isEmpty else {
      return gate(.noEarlyExpressway, reasons: [])
    }

    let knownForbidden = Set(fixture.prohibitions.forbiddenEarlyExpresswayEdgeIDs)
    let crossedKnownForbidden = edgeIDs.contains { knownForbidden.contains($0) }
    return gate(
      .noEarlyExpressway,
      reasons: [
        crossedKnownForbidden
          ? "KNOWN_FORBIDDEN_EARLY_EXPRESSWAY_ENTRY"
          : "EARLY_EXPRESSWAY_ENTRY"
      ]
    )
  }

  private static func routeJoinGate(
    request: SurfaceRouteRequest,
    fixture: EntranceProbeFixture
  ) -> HardGateResult {
    var reasons: [String] = []
    if request.entranceFacilityID != fixture.entrance.facilityID {
      reasons.append("FACILITY_MISMATCH")
    }
    if !fixture.journeyCompatibility.allowedJoinOccurrenceIDs.contains(
      request.selectedJoinOccurrenceID
    ) {
      reasons.append("JOIN_OCCURRENCE_NOT_ALLOWED")
    }
    return gate(.compatibleRouteJoin, reasons: reasons)
  }

  private static func tollDomainGate(
    fixture: EntranceProbeFixture,
    inspection: SurfaceCandidateInspection
  ) -> HardGateResult {
    guard let crossedIDs = inspection.crossedTollDomainIDs else {
      return gate(.allowedTollDomain, reasons: ["TOLL_DOMAIN_INSPECTION_MISSING"])
    }
    let forbidden = Set(fixture.prohibitions.forbiddenTollDomainIDs)
    let crossedForbidden = crossedIDs.contains { forbidden.contains($0) }
    return gate(
      .allowedTollDomain,
      reasons: crossedForbidden ? ["FORBIDDEN_TOLL_DOMAIN_CROSSED"] : []
    )
  }

  private static func geometryGate(
    candidate: SurfaceRouteCandidate,
    inspection: SurfaceCandidateInspection
  ) -> HardGateResult {
    var reasons: [String] = []
    if candidate.coordinates.count < 2 {
      reasons.append("GEOMETRY_TOO_SHORT")
    }
    if candidate.coordinates.contains(where: { !$0.isValid }) {
      reasons.append("INVALID_GEOMETRY_COORDINATE")
    }
    if candidate.distanceMeters < 0 || candidate.expectedTravelTimeSeconds < 0 {
      reasons.append("INVALID_ROUTE_METRICS")
    }
    switch inspection.geometryBindingIsUnambiguous {
    case true:
      break
    case false:
      reasons.append("GEOMETRY_BINDING_AMBIGUOUS")
    case nil:
      reasons.append("GEOMETRY_BINDING_UNKNOWN")
    }
    return gate(.geometryBindable, reasons: reasons)
  }

  private static func providerStatusGate(
    candidate: SurfaceRouteCandidate,
    expectedProviderID: String
  ) -> HardGateResult {
    gate(
      .honestProviderStatus,
      reasons: candidate.providerID == expectedProviderID
        ? [] : ["CANDIDATE_PROVIDER_MISMATCH"]
    )
  }

  private static func gate(
    _ gate: SurfaceHardGate,
    reasons: [String]
  ) -> HardGateResult {
    HardGateResult(
      gate: gate,
      status: reasons.isEmpty ? .pass : .fail,
      reasonCodes: reasons
    )
  }

  private static func angularDifference(_ lhs: Double, _ rhs: Double) -> Double {
    let difference = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
    return min(difference, 360 - difference)
  }

  private static func notEvaluatedGates() -> [HardGateResult] {
    SurfaceHardGate.allCases.map {
      HardGateResult(gate: $0, status: .notEvaluated)
    }
  }

  private static func replace(
    gate: SurfaceHardGate,
    in gates: inout [HardGateResult],
    with result: HardGateResult
  ) {
    guard let index = gates.firstIndex(where: { $0.gate == gate }) else { return }
    gates[index] = result
  }
}

public protocol SurfaceCandidateInspector: Sendable {
  func inspect(
    candidate: SurfaceRouteCandidate,
    request: SurfaceRouteRequest,
    fixture: EntranceProbeFixture
  ) async -> SurfaceCandidateInspection
}

public enum ProbeRetentionClassification: String, Codable, Sendable {
  case rawLocalOnly = "RAW_LOCAL_ONLY"
  case reviewedScalars = "REVIEWED_SCALARS"
  case reviewedDerivedFixture = "REVIEWED_DERIVED_FIXTURE"
}

public struct SurfaceProbeRunContext: Codable, Equatable, Sendable {
  public let runID: String
  public let requestedAt: String
  public let environment: [String: String]
  public let retentionClassification: ProbeRetentionClassification

  public init(
    runID: String,
    requestedAt: String,
    environment: [String: String],
    retentionClassification: ProbeRetentionClassification = .rawLocalOnly
  ) {
    self.runID = runID
    self.requestedAt = requestedAt
    self.environment = environment
    self.retentionClassification = retentionClassification
  }

  private enum CodingKeys: String, CodingKey {
    case runID = "run_id"
    case requestedAt = "requested_at"
    case environment
    case retentionClassification = "retention_classification"
  }
}

public enum SurfaceProbeResponseStatus: String, Codable, Sendable {
  case success = "SUCCESS"
  case providerFailure = "PROVIDER_FAILURE"
  case invalidResponse = "INVALID_RESPONSE"
}

public enum SurfaceProbeDecision: String, Codable, Sendable {
  case pass = "PASS"
  case fail = "FAIL"
}

public struct SurfaceProbeResult: Codable, Equatable, Sendable {
  public let schemaVersion: String
  public let context: SurfaceProbeRunContext
  public let fixtureID: String
  public let originID: String
  public let request: SurfaceRouteRequest
  public let provider: SurfaceRouteProviderMetadata
  public let responseStatus: SurfaceProbeResponseStatus
  public let providerFailure: SurfaceProviderFailure?
  public let evaluations: [SurfaceCandidateEvaluation]
  public let providerLatencyMilliseconds: Int
  public let decision: SurfaceProbeDecision

  public init(
    context: SurfaceProbeRunContext,
    fixtureID: String,
    originID: String,
    request: SurfaceRouteRequest,
    provider: SurfaceRouteProviderMetadata,
    responseStatus: SurfaceProbeResponseStatus,
    providerFailure: SurfaceProviderFailure?,
    evaluations: [SurfaceCandidateEvaluation],
    providerLatencyMilliseconds: Int
  ) {
    schemaVersion = "1.0"
    self.context = context
    self.fixtureID = fixtureID
    self.originID = originID
    self.request = request
    self.provider = provider
    self.responseStatus = responseStatus
    self.providerFailure = providerFailure
    self.evaluations = evaluations
    self.providerLatencyMilliseconds = providerLatencyMilliseconds
    decision = evaluations.contains(where: \.isAccepted) ? .pass : .fail
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case context
    case fixtureID = "fixture_id"
    case originID = "origin_id"
    case request
    case provider
    case responseStatus = "response_status"
    case providerFailure = "provider_failure"
    case evaluations
    case providerLatencyMilliseconds = "provider_latency_milliseconds"
    case decision
  }
}

public enum SurfaceProbeRunnerError: Error, Equatable, Sendable {
  case invalidFixture([FixtureValidationIssue])
}

public struct SurfaceProbeRunner<Provider, Inspector>: Sendable
where Provider: SurfaceRouteProvider, Inspector: SurfaceCandidateInspector {
  public let provider: Provider
  public let inspector: Inspector

  public init(provider: Provider, inspector: Inspector) {
    self.provider = provider
    self.inspector = inspector
  }

  public func run(
    fixture: EntranceProbeFixture,
    originID: String,
    context: SurfaceProbeRunContext
  ) async throws -> SurfaceProbeResult {
    let issues = fixture.structuralValidationIssues()
    guard issues.isEmpty else {
      throw SurfaceProbeRunnerError.invalidFixture(issues)
    }
    let request = try fixture.makeRequest(originID: originID)

    let startedAt = ProcessInfo.processInfo.systemUptime
    let response = await provider.routes(for: request)
    let latency = max(
      0,
      Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)
    )

    switch response {
    case .failure(let failure):
      return SurfaceProbeResult(
        context: context,
        fixtureID: fixture.id,
        originID: originID,
        request: request,
        provider: provider.metadata,
        responseStatus: .providerFailure,
        providerFailure: failure,
        evaluations: [SurfaceHardGateEvaluator.disclosedFailure(failure)],
        providerLatencyMilliseconds: latency
      )

    case .success(let candidates) where candidates.isEmpty:
      return SurfaceProbeResult(
        context: context,
        fixtureID: fixture.id,
        originID: originID,
        request: request,
        provider: provider.metadata,
        responseStatus: .invalidResponse,
        providerFailure: nil,
        evaluations: [SurfaceHardGateEvaluator.invalidEmptySuccess()],
        providerLatencyMilliseconds: latency
      )

    case .success(let candidates):
      var evaluations: [SurfaceCandidateEvaluation] = []
      for candidate in candidates {
        let inspection = await inspector.inspect(
          candidate: candidate,
          request: request,
          fixture: fixture
        )
        evaluations.append(
          SurfaceHardGateEvaluator.evaluate(
            candidate: candidate,
            request: request,
            fixture: fixture,
            inspection: inspection,
            expectedProviderID: provider.metadata.id
          )
        )
      }
      return SurfaceProbeResult(
        context: context,
        fixtureID: fixture.id,
        originID: originID,
        request: request,
        provider: provider.metadata,
        responseStatus: .success,
        providerFailure: nil,
        evaluations: evaluations,
        providerLatencyMilliseconds: latency
      )
    }
  }

}
