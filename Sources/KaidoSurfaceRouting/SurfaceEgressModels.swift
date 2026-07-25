import Foundation

/// Reviewed start identity for the ordinary-road side of one exact exit.
public struct DirectedSurfaceHandoffAnchor: Codable, Equatable, Sendable {
  public let id: String
  public let coordinate: SurfaceCoordinate
  public let directedSurfaceEdgeID: String
  public let expectedBearingDegrees: Double
  public let bearingToleranceDegrees: Double
  public let maxStartDistanceMeters: Double

  public init(
    id: String,
    coordinate: SurfaceCoordinate,
    directedSurfaceEdgeID: String,
    expectedBearingDegrees: Double,
    bearingToleranceDegrees: Double,
    maxStartDistanceMeters: Double
  ) {
    self.id = id
    self.coordinate = coordinate
    self.directedSurfaceEdgeID = directedSurfaceEdgeID
    self.expectedBearingDegrees = expectedBearingDegrees
    self.bearingToleranceDegrees = bearingToleranceDegrees
    self.maxStartDistanceMeters = maxStartDistanceMeters
  }

  public var isValid: Bool {
    !normalized(id).isEmpty
      && coordinate.isValid
      && !normalized(directedSurfaceEdgeID).isEmpty
      && expectedBearingDegrees.isFinite
      && (0..<360).contains(expectedBearingDegrees)
      && bearingToleranceDegrees.isFinite
      && (0...180).contains(bearingToleranceDegrees)
      && maxStartDistanceMeters.isFinite
      && maxStartDistanceMeters >= 0
  }

  private enum CodingKeys: String, CodingKey {
    case id = "anchor_id"
    case coordinate
    case directedSurfaceEdgeID = "directed_surface_edge_id"
    case expectedBearingDegrees = "expected_bearing_degrees"
    case bearingToleranceDegrees = "bearing_tolerance_degrees"
    case maxStartDistanceMeters = "max_start_distance_meters"
  }

  private func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

public struct SurfaceEgressRouteRequest: Codable, Equatable, Sendable {
  public let id: String
  public let exitFacilityID: String
  public let egressOptionID: String
  public let originAnchor: DirectedSurfaceHandoffAnchor
  public let destinationAnchor: DirectedApproachAnchor
  public let preferences: SurfaceRoutePreferences

  public init(
    id: String,
    exitFacilityID: String,
    egressOptionID: String,
    originAnchor: DirectedSurfaceHandoffAnchor,
    destinationAnchor: DirectedApproachAnchor,
    preferences: SurfaceRoutePreferences = SurfaceRoutePreferences()
  ) {
    self.id = id
    self.exitFacilityID = exitFacilityID
    self.egressOptionID = egressOptionID
    self.originAnchor = originAnchor
    self.destinationAnchor = destinationAnchor
    self.preferences = preferences
  }

  private enum CodingKeys: String, CodingKey {
    case id = "request_id"
    case exitFacilityID = "exit_facility_id"
    case egressOptionID = "egress_option_id"
    case originAnchor = "origin_anchor"
    case destinationAnchor = "destination_anchor"
    case preferences
  }
}

public enum SurfaceEgressPolicyIssue: String, Hashable, Sendable {
  case invalidIdentity = "INVALID_SURFACE_EGRESS_POLICY_IDENTITY"
  case invalidOriginAnchor = "INVALID_SURFACE_EGRESS_ORIGIN_ANCHOR"
  case invalidReturnTargetConstraints = "INVALID_SURFACE_EGRESS_RETURN_TARGET_CONSTRAINTS"
  case invalidProhibitions = "INVALID_SURFACE_EGRESS_PROHIBITIONS"
}

/// Release-owned constraints for one exact exit-to-surface handoff.
public struct SurfaceEgressPolicy: Codable, Equatable, Sendable {
  public let id: String
  public let networkSnapshotID: String
  public let egressOptionID: String
  public let exitFacilityID: String
  public let originAnchor: DirectedSurfaceHandoffAnchor
  public let returnTargetBearingToleranceDegrees: Double
  public let maxReturnTargetDistanceMeters: Double
  public let forbiddenExpresswayEdgeIDs: [String]
  public let forbiddenTollDomainIDs: [String]

  public init(
    id: String,
    networkSnapshotID: String,
    egressOptionID: String,
    exitFacilityID: String,
    originAnchor: DirectedSurfaceHandoffAnchor,
    returnTargetBearingToleranceDegrees: Double,
    maxReturnTargetDistanceMeters: Double,
    forbiddenExpresswayEdgeIDs: [String],
    forbiddenTollDomainIDs: [String]
  ) {
    self.id = id
    self.networkSnapshotID = networkSnapshotID
    self.egressOptionID = egressOptionID
    self.exitFacilityID = exitFacilityID
    self.originAnchor = originAnchor
    self.returnTargetBearingToleranceDegrees =
      returnTargetBearingToleranceDegrees
    self.maxReturnTargetDistanceMeters = maxReturnTargetDistanceMeters
    self.forbiddenExpresswayEdgeIDs = forbiddenExpresswayEdgeIDs
    self.forbiddenTollDomainIDs = forbiddenTollDomainIDs
  }

  public var validationIssues: [SurfaceEgressPolicyIssue] {
    var issues: [SurfaceEgressPolicyIssue] = []
    if normalized(id).isEmpty
      || normalized(networkSnapshotID).isEmpty
      || normalized(egressOptionID).isEmpty
      || normalized(exitFacilityID).isEmpty
    {
      issues.append(.invalidIdentity)
    }
    if !originAnchor.isValid {
      issues.append(.invalidOriginAnchor)
    }
    if !returnTargetBearingToleranceDegrees.isFinite
      || !(0...180).contains(returnTargetBearingToleranceDegrees)
      || !maxReturnTargetDistanceMeters.isFinite
      || maxReturnTargetDistanceMeters < 0
    {
      issues.append(.invalidReturnTargetConstraints)
    }
    if invalidUniqueIDs(forbiddenExpresswayEdgeIDs)
      || invalidUniqueIDs(forbiddenTollDomainIDs)
    {
      issues.append(.invalidProhibitions)
    }
    return Array(Set(issues)).sorted { $0.rawValue < $1.rawValue }
  }

  private enum CodingKeys: String, CodingKey {
    case id = "surface_egress_policy_id"
    case networkSnapshotID = "network_snapshot_id"
    case egressOptionID = "egress_option_id"
    case exitFacilityID = "exit_facility_id"
    case originAnchor = "origin_anchor"
    case returnTargetBearingToleranceDegrees =
      "return_target_bearing_tolerance_degrees"
    case maxReturnTargetDistanceMeters = "max_return_target_distance_meters"
    case forbiddenExpresswayEdgeIDs = "forbidden_expressway_edge_ids"
    case forbiddenTollDomainIDs = "forbidden_toll_domain_ids"
  }

  private func invalidUniqueIDs(_ values: [String]) -> Bool {
    values.contains(where: { normalized($0).isEmpty })
      || Set(values).count != values.count
  }

  private func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

public struct SurfaceHandoffBindingObservation: Codable, Equatable, Sendable {
  public let anchorID: String
  public let directedSurfaceEdgeID: String
  public let startDistanceMeters: Double
  public let startBearingDegrees: Double

  public init(
    anchorID: String,
    directedSurfaceEdgeID: String,
    startDistanceMeters: Double,
    startBearingDegrees: Double
  ) {
    self.anchorID = anchorID
    self.directedSurfaceEdgeID = directedSurfaceEdgeID
    self.startDistanceMeters = startDistanceMeters
    self.startBearingDegrees = startBearingDegrees
  }

  private enum CodingKeys: String, CodingKey {
    case anchorID = "anchor_id"
    case directedSurfaceEdgeID = "directed_surface_edge_id"
    case startDistanceMeters = "start_distance_meters"
    case startBearingDegrees = "start_bearing_degrees"
  }
}

/// One exact directed-edge occurrence and its graph-bound geometry.
///
/// Repeated directed edges remain separate occurrences. The index is path
/// order, not an entity identity, and must never be deduplicated.
public struct SurfaceResolvedPathOccurrence: Codable, Equatable, Sendable {
  public let index: Int
  public let directedEdgeID: String
  public let coordinates: [SurfaceCoordinate]

  public init(
    index: Int,
    directedEdgeID: String,
    coordinates: [SurfaceCoordinate]
  ) {
    self.index = index
    self.directedEdgeID = directedEdgeID
    self.coordinates = coordinates
  }

  public var isValid: Bool {
    index >= 0
      && !directedEdgeID.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty
      && coordinates.count >= 2
      && coordinates.allSatisfy(\.isValid)
  }

  private enum CodingKeys: String, CodingKey {
    case index
    case directedEdgeID = "directed_edge_id"
    case coordinates
  }
}

public struct SurfaceEgressCandidateInspection: Codable, Equatable, Sendable {
  public let networkSnapshotID: String?
  public let handoffBinding: SurfaceHandoffBindingObservation?
  public let returnTargetBinding: AnchorBindingObservation?
  public let geometryBindingIsUnambiguous: Bool?
  public let expresswayEdgeIDsAfterExit: [String]?
  public let crossedTollDomainIDs: [String]?
  public let unmatchedSampleCount: Int?
  public let ambiguousDirectedEdgeIDs: [String]?
  public let disconnectedDirectedEdgeIDs: [String]?
  public let resolvedPathEdgeIDs: [String]?
  public let resolvedPathOccurrences: [SurfaceResolvedPathOccurrence]?

  public init(
    networkSnapshotID: String? = nil,
    handoffBinding: SurfaceHandoffBindingObservation?,
    returnTargetBinding: AnchorBindingObservation?,
    geometryBindingIsUnambiguous: Bool?,
    expresswayEdgeIDsAfterExit: [String]?,
    crossedTollDomainIDs: [String]?,
    unmatchedSampleCount: Int? = nil,
    ambiguousDirectedEdgeIDs: [String]? = nil,
    disconnectedDirectedEdgeIDs: [String]? = nil,
    resolvedPathEdgeIDs: [String]? = nil,
    resolvedPathOccurrences: [SurfaceResolvedPathOccurrence]? = nil
  ) {
    self.networkSnapshotID = networkSnapshotID
    self.handoffBinding = handoffBinding
    self.returnTargetBinding = returnTargetBinding
    self.geometryBindingIsUnambiguous = geometryBindingIsUnambiguous
    self.expresswayEdgeIDsAfterExit = expresswayEdgeIDsAfterExit
    self.crossedTollDomainIDs = crossedTollDomainIDs
    self.unmatchedSampleCount = unmatchedSampleCount
    self.ambiguousDirectedEdgeIDs = ambiguousDirectedEdgeIDs
    self.disconnectedDirectedEdgeIDs = disconnectedDirectedEdgeIDs
    self.resolvedPathEdgeIDs = resolvedPathEdgeIDs
    self.resolvedPathOccurrences = resolvedPathOccurrences
  }

  private enum CodingKeys: String, CodingKey {
    case networkSnapshotID = "network_snapshot_id"
    case handoffBinding = "handoff_binding"
    case returnTargetBinding = "return_target_binding"
    case geometryBindingIsUnambiguous = "geometry_binding_is_unambiguous"
    case expresswayEdgeIDsAfterExit = "expressway_edge_ids_after_exit"
    case crossedTollDomainIDs = "crossed_toll_domain_ids"
    case unmatchedSampleCount = "unmatched_sample_count"
    case ambiguousDirectedEdgeIDs = "ambiguous_directed_edge_ids"
    case disconnectedDirectedEdgeIDs = "disconnected_directed_edge_ids"
    case resolvedPathEdgeIDs = "resolved_path_edge_ids"
    case resolvedPathOccurrences = "resolved_path_occurrences"
  }
}

public enum SurfaceEgressHardGate: String, Codable, CaseIterable, Sendable {
  case correctDirectedHandoff = "CORRECT_DIRECTED_HANDOFF"
  case noExpresswayReentry = "NO_EXPRESSWAY_REENTRY"
  case compatibleReleasedExit = "COMPATIBLE_RELEASED_EXIT"
  case allowedTollDomain = "ALLOWED_TOLL_DOMAIN"
  case geometryBindable = "GEOMETRY_BINDABLE"
  case honestProviderStatus = "HONEST_PROVIDER_STATUS"
}

public struct SurfaceEgressHardGateResult: Codable, Equatable, Sendable {
  public let gate: SurfaceEgressHardGate
  public let status: HardGateStatus
  public let reasonCodes: [String]

  public init(
    gate: SurfaceEgressHardGate,
    status: HardGateStatus,
    reasonCodes: [String] = []
  ) {
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

public struct SurfaceEgressCandidateEvaluation: Codable, Equatable, Sendable {
  public let candidateID: String?
  public let candidate: SurfaceRouteCandidate?
  public let inspection: SurfaceEgressCandidateInspection?
  public let disposition: SurfaceProbeDisposition
  public let hardGates: [SurfaceEgressHardGateResult]

  public init(
    candidateID: String?,
    candidate: SurfaceRouteCandidate? = nil,
    inspection: SurfaceEgressCandidateInspection? = nil,
    disposition: SurfaceProbeDisposition,
    hardGates: [SurfaceEgressHardGateResult]
  ) {
    self.candidateID = candidateID
    self.candidate = candidate
    self.inspection = inspection
    self.disposition = disposition
    self.hardGates = hardGates
  }

  public var isAccepted: Bool {
    disposition == .accepted
  }

  private enum CodingKeys: String, CodingKey {
    case candidateID = "candidate_id"
    case candidate
    case inspection
    case disposition
    case hardGates = "hard_gates"
  }
}

public enum SurfaceEgressHardGateEvaluator {
  public static func evaluate(
    candidate: SurfaceRouteCandidate,
    request: SurfaceEgressRouteRequest,
    policy: SurfaceEgressPolicy,
    inspection: SurfaceEgressCandidateInspection,
    expectedProviderID: String
  ) -> SurfaceEgressCandidateEvaluation {
    if !policy.validationIssues.isEmpty {
      return failedEvaluation(
        candidate: candidate,
        inspection: inspection,
        reasons: policy.validationIssues.map(\.rawValue)
      )
    }
    if let snapshotID = inspection.networkSnapshotID,
      snapshotID != policy.networkSnapshotID
    {
      return failedEvaluation(
        candidate: candidate,
        inspection: inspection,
        reasons: ["INSPECTION_NETWORK_SNAPSHOT_MISMATCH"]
      )
    }

    let gates = [
      handoffGate(request: request, policy: policy, inspection: inspection),
      expresswayGate(policy: policy, inspection: inspection),
      exitGate(request: request, policy: policy),
      tollGate(policy: policy, inspection: inspection),
      geometryGate(
        candidate: candidate,
        request: request,
        policy: policy,
        inspection: inspection
      ),
      providerGate(candidate: candidate, expectedProviderID: expectedProviderID),
    ]
    return SurfaceEgressCandidateEvaluation(
      candidateID: candidate.id,
      candidate: candidate,
      inspection: inspection,
      disposition: gates.allSatisfy { $0.status == .pass }
        ? .accepted : .rejected,
      hardGates: gates
    )
  }

  public static func disclosedFailure(
    _ failure: SurfaceProviderFailure
  ) -> SurfaceEgressCandidateEvaluation {
    var gates = notEvaluatedGates()
    replace(
      gate: .honestProviderStatus,
      in: &gates,
      result: SurfaceEgressHardGateResult(
        gate: .honestProviderStatus,
        status: .pass,
        reasonCodes: [
          "PROVIDER_FAILURE_DISCLOSED_\(failure.kind.rawValue)"
        ]
      )
    )
    return SurfaceEgressCandidateEvaluation(
      candidateID: nil,
      disposition: .providerFailure,
      hardGates: gates
    )
  }

  public static func invalidResponse(
    reasonCodes: [String]
  ) -> SurfaceEgressCandidateEvaluation {
    var gates = notEvaluatedGates()
    replace(
      gate: .honestProviderStatus,
      in: &gates,
      result: SurfaceEgressHardGateResult(
        gate: .honestProviderStatus,
        status: .fail,
        reasonCodes: reasonCodes
      )
    )
    return SurfaceEgressCandidateEvaluation(
      candidateID: nil,
      disposition: .invalidResponse,
      hardGates: gates
    )
  }

  private static func handoffGate(
    request: SurfaceEgressRouteRequest,
    policy: SurfaceEgressPolicy,
    inspection: SurfaceEgressCandidateInspection
  ) -> SurfaceEgressHardGateResult {
    var reasons: [String] = []
    if request.originAnchor != policy.originAnchor {
      reasons.append("REQUEST_HANDOFF_ANCHOR_MISMATCH")
    }
    guard let binding = inspection.handoffBinding else {
      reasons.append("HANDOFF_BINDING_MISSING")
      return gate(.correctDirectedHandoff, reasons: reasons)
    }
    if binding.anchorID != policy.originAnchor.id {
      reasons.append("HANDOFF_ANCHOR_ID_MISMATCH")
    }
    if binding.directedSurfaceEdgeID
      != policy.originAnchor.directedSurfaceEdgeID
    {
      reasons.append("HANDOFF_EDGE_MISMATCH")
    }
    if !binding.startDistanceMeters.isFinite
      || binding.startDistanceMeters < 0
    {
      reasons.append("INVALID_HANDOFF_START_DISTANCE")
    } else if binding.startDistanceMeters
      > policy.originAnchor.maxStartDistanceMeters
    {
      reasons.append("HANDOFF_START_TOO_FAR")
    }
    if !binding.startBearingDegrees.isFinite
      || !(0..<360).contains(binding.startBearingDegrees)
    {
      reasons.append("INVALID_HANDOFF_START_BEARING")
    } else if angularDifference(
      binding.startBearingDegrees,
      policy.originAnchor.expectedBearingDegrees
    ) > policy.originAnchor.bearingToleranceDegrees {
      reasons.append("HANDOFF_START_HEADING_MISMATCH")
    }
    return gate(.correctDirectedHandoff, reasons: reasons)
  }

  private static func expresswayGate(
    policy: SurfaceEgressPolicy,
    inspection: SurfaceEgressCandidateInspection
  ) -> SurfaceEgressHardGateResult {
    guard let edgeIDs = inspection.expresswayEdgeIDsAfterExit else {
      return gate(
        .noExpresswayReentry,
        reasons: ["EXPRESSWAY_REENTRY_INSPECTION_MISSING"]
      )
    }
    guard !edgeIDs.isEmpty else {
      return gate(.noExpresswayReentry, reasons: [])
    }
    let forbidden = Set(policy.forbiddenExpresswayEdgeIDs)
    return gate(
      .noExpresswayReentry,
      reasons: [
        edgeIDs.contains(where: forbidden.contains)
          ? "KNOWN_FORBIDDEN_EXPRESSWAY_REENTRY"
          : "EXPRESSWAY_REENTRY"
      ]
    )
  }

  private static func exitGate(
    request: SurfaceEgressRouteRequest,
    policy: SurfaceEgressPolicy
  ) -> SurfaceEgressHardGateResult {
    var reasons: [String] = []
    if request.exitFacilityID != policy.exitFacilityID {
      reasons.append("EXIT_FACILITY_MISMATCH")
    }
    if request.egressOptionID != policy.egressOptionID {
      reasons.append("EGRESS_OPTION_MISMATCH")
    }
    return gate(.compatibleReleasedExit, reasons: reasons)
  }

  private static func tollGate(
    policy: SurfaceEgressPolicy,
    inspection: SurfaceEgressCandidateInspection
  ) -> SurfaceEgressHardGateResult {
    guard let crossed = inspection.crossedTollDomainIDs else {
      return gate(
        .allowedTollDomain,
        reasons: ["TOLL_DOMAIN_INSPECTION_MISSING"]
      )
    }
    let forbidden = Set(policy.forbiddenTollDomainIDs)
    return gate(
      .allowedTollDomain,
      reasons: crossed.contains(where: forbidden.contains)
        ? ["FORBIDDEN_TOLL_DOMAIN_CROSSED"] : []
    )
  }

  private static func geometryGate(
    candidate: SurfaceRouteCandidate,
    request: SurfaceEgressRouteRequest,
    policy: SurfaceEgressPolicy,
    inspection: SurfaceEgressCandidateInspection
  ) -> SurfaceEgressHardGateResult {
    var reasons: [String] = []
    if candidate.coordinates.count < 2 {
      reasons.append("GEOMETRY_TOO_SHORT")
    }
    if candidate.coordinates.contains(where: { !$0.isValid }) {
      reasons.append("INVALID_GEOMETRY_COORDINATE")
    }
    if !candidate.distanceMeters.isFinite
      || candidate.distanceMeters < 0
      || !candidate.expectedTravelTimeSeconds.isFinite
      || candidate.expectedTravelTimeSeconds < 0
    {
      reasons.append("INVALID_ROUTE_METRICS")
    }
    if let binding = inspection.returnTargetBinding {
      if binding.anchorID != request.destinationAnchor.id {
        reasons.append("RETURN_TARGET_ID_MISMATCH")
      }
      if binding.directedSurfaceEdgeID
        != request.destinationAnchor.directedSurfaceEdgeID
      {
        reasons.append("RETURN_TARGET_EDGE_MISMATCH")
      }
      if !binding.terminalDistanceMeters.isFinite
        || binding.terminalDistanceMeters < 0
      {
        reasons.append("INVALID_RETURN_TARGET_DISTANCE")
      } else if binding.terminalDistanceMeters
        > policy.maxReturnTargetDistanceMeters
      {
        reasons.append("RETURN_TARGET_TOO_FAR")
      }
      if !binding.terminalBearingDegrees.isFinite
        || !(0..<360).contains(binding.terminalBearingDegrees)
      {
        reasons.append("INVALID_RETURN_TARGET_BEARING")
      } else if angularDifference(
        binding.terminalBearingDegrees,
        request.destinationAnchor.expectedBearingDegrees
      ) > request.destinationAnchor.bearingToleranceDegrees {
        reasons.append("RETURN_TARGET_HEADING_MISMATCH")
      }
    } else {
      reasons.append("RETURN_TARGET_BINDING_MISSING")
    }
    switch inspection.geometryBindingIsUnambiguous {
    case true:
      break
    case false:
      var hasSpecificReason = false
      if let count = inspection.unmatchedSampleCount, count > 0 {
        reasons.append("GEOMETRY_SAMPLES_UNMATCHED")
        hasSpecificReason = true
      }
      if let values = inspection.ambiguousDirectedEdgeIDs, !values.isEmpty {
        reasons.append("GEOMETRY_BINDING_AMBIGUOUS")
        hasSpecificReason = true
      }
      if let values = inspection.disconnectedDirectedEdgeIDs, !values.isEmpty {
        reasons.append("GEOMETRY_PATH_DISCONNECTED")
        hasSpecificReason = true
      }
      if !hasSpecificReason {
        reasons.append("GEOMETRY_BINDING_AMBIGUOUS")
      }
    case nil:
      reasons.append("GEOMETRY_BINDING_UNKNOWN")
    }
    return gate(.geometryBindable, reasons: reasons)
  }

  private static func providerGate(
    candidate: SurfaceRouteCandidate,
    expectedProviderID: String
  ) -> SurfaceEgressHardGateResult {
    gate(
      .honestProviderStatus,
      reasons: candidate.providerID == expectedProviderID
        ? [] : ["CANDIDATE_PROVIDER_MISMATCH"]
    )
  }

  private static func failedEvaluation(
    candidate: SurfaceRouteCandidate,
    inspection: SurfaceEgressCandidateInspection,
    reasons: [String]
  ) -> SurfaceEgressCandidateEvaluation {
    SurfaceEgressCandidateEvaluation(
      candidateID: candidate.id,
      candidate: candidate,
      inspection: inspection,
      disposition: .rejected,
      hardGates: SurfaceEgressHardGate.allCases.map {
        SurfaceEgressHardGateResult(
          gate: $0,
          status: .fail,
          reasonCodes: reasons
        )
      }
    )
  }

  private static func gate(
    _ gate: SurfaceEgressHardGate,
    reasons: [String]
  ) -> SurfaceEgressHardGateResult {
    SurfaceEgressHardGateResult(
      gate: gate,
      status: reasons.isEmpty ? .pass : .fail,
      reasonCodes: reasons
    )
  }

  private static func notEvaluatedGates() -> [SurfaceEgressHardGateResult] {
    SurfaceEgressHardGate.allCases.map {
      SurfaceEgressHardGateResult(gate: $0, status: .notEvaluated)
    }
  }

  private static func replace(
    gate: SurfaceEgressHardGate,
    in results: inout [SurfaceEgressHardGateResult],
    result: SurfaceEgressHardGateResult
  ) {
    guard let index = results.firstIndex(where: { $0.gate == gate }) else {
      return
    }
    results[index] = result
  }

  private static func angularDifference(
    _ lhs: Double,
    _ rhs: Double
  ) -> Double {
    let difference = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
    return min(difference, 360 - difference)
  }
}

public protocol SurfaceEgressCandidateInspector: Sendable {
  func inspect(
    candidate: SurfaceRouteCandidate,
    request: SurfaceEgressRouteRequest,
    policy: SurfaceEgressPolicy
  ) async -> SurfaceEgressCandidateInspection
}

public protocol SurfaceEgressRouteProvider: Sendable {
  var metadata: SurfaceRouteProviderMetadata { get }

  func egressRoutes(
    for request: SurfaceEgressRouteRequest
  ) async -> SurfaceProviderResponse
}

public protocol ReleaseBoundSurfaceEgressRouteProvider:
  SurfaceEgressRouteProvider
{
  var releaseIdentity: SurfaceRouteProviderReleaseIdentity { get }
}
