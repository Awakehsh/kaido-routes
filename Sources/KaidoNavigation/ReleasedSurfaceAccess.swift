import Foundation
import KaidoDomain
import KaidoRouting
import KaidoSurfaceRouting

public enum JourneyFinishPolicy: String, Codable, CaseIterable, Hashable, Sendable {
  case fixedExit = "FIXED_EXIT"
  case returnNearOrigin = "RETURN_NEAR_ORIGIN"
  case finishOnRequest = "FINISH_ON_REQUEST"
}

public enum ReleasedSurfaceAccessIssue: String, Hashable, Sendable {
  case invalidIdentity = "INVALID_RELEASED_SURFACE_ACCESS_IDENTITY"
  case networkSnapshotMismatch = "SURFACE_ACCESS_NETWORK_SNAPSHOT_MISMATCH"
  case routePlanMismatch = "SURFACE_ACCESS_ROUTE_PLAN_MISMATCH"
  case invalidProviderIdentity = "INVALID_RELEASED_SURFACE_PROVIDER_IDENTITY"
  case providerSnapshotMismatch = "SURFACE_PROVIDER_NETWORK_SNAPSHOT_MISMATCH"
  case invalidApproachPolicy = "INVALID_RELEASED_SURFACE_APPROACH_POLICY"
  case entranceMismatch = "SURFACE_ACCESS_ENTRANCE_MISMATCH"
  case joinOccurrenceMismatch = "SURFACE_ACCESS_JOIN_OCCURRENCE_MISMATCH"
  case entryTransitionMismatch = "SURFACE_ACCESS_ENTRY_TRANSITION_MISMATCH"
  case incompatibleExit = "SURFACE_ACCESS_INCOMPATIBLE_EXIT"
  case invalidFinishPolicies = "INVALID_RELEASED_SURFACE_FINISH_POLICIES"
}

/// Reviewed surface-access constraints bound to one exact released RoutePlan.
///
/// This definition contains no route result. It only lets the product re-run
/// the surface hard gates against a candidate without giving the provider
/// authority to author or mutate the Shuto RoutePlan.
public struct ReleasedSurfaceAccessDefinition: Codable, Equatable, Sendable {
  public let id: String
  public let routePlanID: String
  public let providerIdentity: SurfaceRouteProviderReleaseIdentity
  public let approachPolicy: SurfaceApproachPolicy
  public let allowedFinishPolicies: [JourneyFinishPolicy]

  public init(
    id: String,
    routePlanID: String,
    providerIdentity: SurfaceRouteProviderReleaseIdentity,
    approachPolicy: SurfaceApproachPolicy,
    allowedFinishPolicies: [JourneyFinishPolicy]
  ) {
    self.id = id
    self.routePlanID = routePlanID
    self.providerIdentity = providerIdentity
    self.approachPolicy = approachPolicy
    self.allowedFinishPolicies = allowedFinishPolicies
  }

  public func validationIssues(
    networkSnapshot: NetworkSnapshot,
    routePlan: RoutePlan,
    runtimePolicy: ReleasedNavigationRuntimePolicy
  ) -> [ReleasedSurfaceAccessIssue] {
    var issues: [ReleasedSurfaceAccessIssue] = []
    if normalized(id).isEmpty {
      issues.append(.invalidIdentity)
    }
    if approachPolicy.networkSnapshotID != networkSnapshot.id {
      issues.append(.networkSnapshotMismatch)
    }
    if routePlanID != routePlan.id {
      issues.append(.routePlanMismatch)
    }
    if !providerIdentity.validationIssues.isEmpty {
      issues.append(.invalidProviderIdentity)
    }
    if providerIdentity.networkSnapshotID != networkSnapshot.id {
      issues.append(.providerSnapshotMismatch)
    }
    if !approachPolicy.validationIssues.isEmpty {
      issues.append(.invalidApproachPolicy)
    }
    if approachPolicy.entranceFacilityID != routePlan.entryFacilityID
      || approachPolicy.entranceFacilityID != runtimePolicy.entryTransition.facilityID
    {
      issues.append(.entranceMismatch)
    }
    guard let firstOccurrenceID = routePlan.occurrences.first?.id else {
      issues.append(.joinOccurrenceMismatch)
      return sortedUnique(issues)
    }
    if approachPolicy.allowedJoinOccurrenceIDs != [firstOccurrenceID] {
      issues.append(.joinOccurrenceMismatch)
    }
    if approachPolicy.entryTransitionDirectedEdgeIDs
      != runtimePolicy.entryTransition.directedEdgeIDs
      || runtimePolicy.entryTransition.firstRouteOccurrenceID != firstOccurrenceID
    {
      issues.append(.entryTransitionMismatch)
    }
    let compatibleExits = Set(approachPolicy.compatibleExitFacilityIDs)
    let requiredExits = Set(
      [routePlan.exitFacilityID] + runtimePolicy.egressOptions.map(\.exitFacilityID)
    )
    if requiredExits != compatibleExits {
      issues.append(.incompatibleExit)
    }
    if allowedFinishPolicies.isEmpty
      || Set(allowedFinishPolicies).count != allowedFinishPolicies.count
    {
      issues.append(.invalidFinishPolicies)
    }
    return sortedUnique(issues)
  }

  private enum CodingKeys: String, CodingKey {
    case id = "surface_access_definition_id"
    case routePlanID = "route_plan_id"
    case providerIdentity = "provider_identity"
    case approachPolicy = "approach_policy"
    case allowedFinishPolicies = "allowed_finish_policies"
  }

  private func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func sortedUnique(
    _ issues: [ReleasedSurfaceAccessIssue]
  ) -> [ReleasedSurfaceAccessIssue] {
    Array(Set(issues)).sorted { $0.rawValue < $1.rawValue }
  }
}

public enum SurfaceEgressSelectionPolicy: String, Codable, Sendable {
  case fastestThenShortest = "FASTEST_THEN_SHORTEST"
}

public enum ReleasedSurfaceEgressIssue: String, Hashable, Sendable {
  case invalidIdentity = "INVALID_RELEASED_SURFACE_EGRESS_IDENTITY"
  case routePlanMismatch = "SURFACE_EGRESS_ROUTE_PLAN_MISMATCH"
  case invalidProviderIdentity = "INVALID_RELEASED_SURFACE_EGRESS_PROVIDER_IDENTITY"
  case providerSnapshotMismatch = "SURFACE_EGRESS_PROVIDER_NETWORK_SNAPSHOT_MISMATCH"
  case invalidPolicies = "INVALID_RELEASED_SURFACE_EGRESS_POLICIES"
  case policySnapshotMismatch = "SURFACE_EGRESS_POLICY_NETWORK_SNAPSHOT_MISMATCH"
  case unknownEgressOption = "SURFACE_EGRESS_UNKNOWN_EGRESS_OPTION"
  case exitFacilityMismatch = "SURFACE_EGRESS_EXIT_FACILITY_MISMATCH"
  case surfaceAccessNotReleased = "SURFACE_EGRESS_ACCESS_NOT_RELEASED"
  case returnPolicyNotReleased = "SURFACE_EGRESS_RETURN_POLICY_NOT_RELEASED"
}

/// Reviewed ordinary-road return constraints for exact released exit options.
///
/// The definition authorizes neither a destination-first reroute nor an
/// expressway re-entry. A return request is derived from the accepted access
/// leg and must pass one policy's complete surface hard gates.
public struct ReleasedSurfaceEgressDefinition: Codable, Equatable, Sendable {
  public let id: String
  public let routePlanID: String
  public let providerIdentity: SurfaceRouteProviderReleaseIdentity
  public let selectionPolicy: SurfaceEgressSelectionPolicy
  public let policies: [SurfaceEgressPolicy]

  public init(
    id: String,
    routePlanID: String,
    providerIdentity: SurfaceRouteProviderReleaseIdentity,
    selectionPolicy: SurfaceEgressSelectionPolicy = .fastestThenShortest,
    policies: [SurfaceEgressPolicy]
  ) {
    self.id = id
    self.routePlanID = routePlanID
    self.providerIdentity = providerIdentity
    self.selectionPolicy = selectionPolicy
    self.policies = policies
  }

  public func validationIssues(
    networkSnapshot: NetworkSnapshot,
    routePlan: RoutePlan,
    runtimePolicy: ReleasedNavigationRuntimePolicy
  ) -> [ReleasedSurfaceEgressIssue] {
    var issues: [ReleasedSurfaceEgressIssue] = []
    if normalized(id).isEmpty {
      issues.append(.invalidIdentity)
    }
    if routePlanID != routePlan.id {
      issues.append(.routePlanMismatch)
    }
    if !providerIdentity.validationIssues.isEmpty {
      issues.append(.invalidProviderIdentity)
    }
    if providerIdentity.networkSnapshotID != networkSnapshot.id {
      issues.append(.providerSnapshotMismatch)
    }
    let policyIDs = policies.map(\.id)
    let egressOptionIDs = policies.map(\.egressOptionID)
    if policies.isEmpty
      || policyIDs.contains(where: { normalized($0).isEmpty })
      || Set(policyIDs).count != policyIDs.count
      || Set(egressOptionIDs).count != egressOptionIDs.count
      || policies.contains(where: { !$0.validationIssues.isEmpty })
    {
      issues.append(.invalidPolicies)
    }

    let optionsByID = Dictionary(
      runtimePolicy.egressOptions.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    for policy in policies {
      if policy.networkSnapshotID != networkSnapshot.id {
        issues.append(.policySnapshotMismatch)
      }
      guard let option = optionsByID[policy.egressOptionID],
        option.isReleased
      else {
        issues.append(.unknownEgressOption)
        continue
      }
      if policy.exitFacilityID != option.exitFacilityID {
        issues.append(.exitFacilityMismatch)
      }
    }
    return Array(Set(issues)).sorted { $0.rawValue < $1.rawValue }
  }

  private enum CodingKeys: String, CodingKey {
    case id = "surface_egress_definition_id"
    case routePlanID = "route_plan_id"
    case providerIdentity = "provider_identity"
    case selectionPolicy = "selection_policy"
    case policies
  }

  private func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

public enum JourneySurfaceLegRole: String, Codable, Sendable {
  case access = "SURFACE_ACCESS"
  case egress = "SURFACE_EGRESS"
}

/// An accepted provider result projected into a bounded journey leg.
///
/// Only `JourneyPlanCompiler` can create this value. Provider steps and prose
/// are deliberately excluded from released navigation authority.
public struct JourneySurfaceLeg: Equatable, Sendable {
  public let role: JourneySurfaceLegRole
  public let networkSnapshotID: String
  public let providerIdentity: SurfaceRouteProviderReleaseIdentity
  public let candidateID: String
  public let originID: String
  public let destinationAnchorID: String
  public let entranceFacilityID: String?
  public let exitFacilityID: String?
  public let joinOccurrenceID: String?
  public let directedEdgeIDs: [String]
  public let egressMatcherCorridor: SurfaceEgressMatcherCorridor?
  public let distanceMeters: Double
  public let expectedTravelTimeSeconds: Double

  public var providerID: String {
    providerIdentity.providerID
  }
}

/// Exact return target frozen from an accepted surface-access candidate.
///
/// The value is intentionally runtime-only. Checkpoint restoration requires
/// the caller to present the same immutable JourneyPlan.
public struct JourneyReturnTarget: Equatable, Sendable {
  public let id: String
  public let coordinate: SurfaceCoordinate
  public let directedSurfaceEdgeID: String
  public let expectedBearingDegrees: Double
}

/// One immutable product journey composition around the authoritative RoutePlan.
public struct JourneyPlan: Equatable, Sendable {
  public let id: String
  public let productReleaseID: String
  public let navigationReleaseID: String
  public let networkSnapshotID: String
  public let routePlanID: String
  public let originID: String?
  public let accessLeg: JourneySurfaceLeg?
  public let returnTarget: JourneyReturnTarget?
  public let entryTransition: EntryTransition
  public let finishPolicy: JourneyFinishPolicy
  public let precomputedEgressOptions: [EgressOption]
  public let selectedEgressOptionID: String?
  public let egressLeg: JourneySurfaceLeg?
  public let initialPhase: JourneyPhase

}

public enum JourneyPlanRuntimeAdmissionIssue: String, Hashable, Sendable {
  case invalidIdentity = "INVALID_JOURNEY_PLAN_IDENTITY"
  case releaseIdentityMismatch = "JOURNEY_PLAN_RELEASE_IDENTITY_MISMATCH"
  case routeIdentityMismatch = "JOURNEY_PLAN_ROUTE_IDENTITY_MISMATCH"
  case entryTransitionMismatch = "JOURNEY_PLAN_ENTRY_TRANSITION_MISMATCH"
  case egressOptionsMismatch = "JOURNEY_PLAN_EGRESS_OPTIONS_MISMATCH"
  case surfaceAccessNotReleased = "JOURNEY_PLAN_SURFACE_ACCESS_NOT_RELEASED"
  case invalidSurfaceAccessLeg = "INVALID_JOURNEY_PLAN_SURFACE_ACCESS_LEG"
  case surfaceAccessReleaseMismatch = "JOURNEY_PLAN_SURFACE_ACCESS_RELEASE_MISMATCH"
  case invalidReturnTarget = "INVALID_JOURNEY_PLAN_RETURN_TARGET"
  case finishPolicyNotReleased = "JOURNEY_PLAN_FINISH_POLICY_NOT_RELEASED"
  case invalidFinishComposition = "INVALID_JOURNEY_PLAN_FINISH_COMPOSITION"
  case surfaceEgressNotReleased = "JOURNEY_PLAN_SURFACE_EGRESS_NOT_RELEASED"
  case invalidSurfaceEgressLeg = "INVALID_JOURNEY_PLAN_SURFACE_EGRESS_LEG"
  case surfaceEgressReleaseMismatch = "JOURNEY_PLAN_SURFACE_EGRESS_RELEASE_MISMATCH"
  case invalidInitialPhase = "INVALID_JOURNEY_PLAN_INITIAL_PHASE"
  case routeOnlyCompositionMismatch = "JOURNEY_PLAN_ROUTE_ONLY_COMPOSITION_MISMATCH"
}

public enum JourneyPlanRuntimeAdmissionError: Error, Equatable, Sendable {
  case invalid([JourneyPlanRuntimeAdmissionIssue])
}

public enum JourneyPlanCompilerError: Error, Equatable, Sendable {
  case surfaceAccessNotReleased
  case invalidReleasedSurfaceAccess([ReleasedSurfaceAccessIssue])
  case invalidReleasedSurfaceEgress([ReleasedSurfaceEgressIssue])
  case providerIdentityMismatch
  case invalidRequest([String])
  case inspectionSnapshotMismatch
  case candidateRejected([HardGateResult])
  case egressCandidateRejected([SurfaceEgressHardGateResult])
  case invalidResolvedPath
  case selectedPathEvidenceMismatch
  case finishPolicyNotReleased(JourneyFinishPolicy)
  case surfaceEgressNotReleased
}

public enum JourneyPlanCompiler {
  public static func routeOnly(
    release: KaidoProductRelease
  ) -> JourneyPlan {
    let bundle = release.navigation.bundle
    return JourneyPlan(
      id: "\(release.releaseID).journey.route-only",
      productReleaseID: release.releaseID,
      navigationReleaseID: release.navigation.releaseID,
      networkSnapshotID: bundle.networkSnapshot.id,
      routePlanID: bundle.routePlan.id,
      originID: nil,
      accessLeg: nil,
      returnTarget: nil,
      entryTransition: bundle.runtimePolicy.entryTransition,
      finishPolicy: .finishOnRequest,
      precomputedEgressOptions: bundle.runtimePolicy.egressOptions,
      selectedEgressOptionID: nil,
      egressLeg: nil,
      initialPhase: .planning
    )
  }

  package static func surfaceAccess(
    release: KaidoProductRelease,
    request: SurfaceRouteRequest,
    candidate: SurfaceRouteCandidate,
    inspection: SurfaceCandidateInspection,
    providerIdentity: SurfaceRouteProviderReleaseIdentity,
    finishPolicy: JourneyFinishPolicy
  ) throws -> JourneyPlan {
    let definition = try surfaceAccessPreflight(
      release: release,
      request: request,
      providerIdentity: providerIdentity,
      finishPolicy: finishPolicy
    )
    let bundle = release.navigation.bundle
    guard normalized(candidate.id).isEmpty == false,
      normalized(candidate.providerID).isEmpty == false
    else {
      throw JourneyPlanCompilerError.invalidRequest([
        "INVALID_SURFACE_ACCESS_PROVIDER_IDENTITY"
      ])
    }
    guard inspection.networkSnapshotID == bundle.networkSnapshot.id else {
      throw JourneyPlanCompilerError.inspectionSnapshotMismatch
    }

    let evaluation = SurfaceHardGateEvaluator.evaluate(
      candidate: candidate,
      request: request,
      policy: definition.approachPolicy,
      inspection: inspection,
      expectedProviderID: providerIdentity.providerID
    )
    guard evaluation.isAccepted else {
      throw JourneyPlanCompilerError.candidateRejected(evaluation.hardGates)
    }
    guard let directedEdgeIDs = inspection.resolvedPathEdgeIDs,
      !directedEdgeIDs.isEmpty,
      !directedEdgeIDs.contains(where: { normalized($0).isEmpty })
    else {
      throw JourneyPlanCompilerError.invalidResolvedPath
    }
    if let selectedPathEvidence = candidate.selectedPathEvidence {
      guard selectedPathEvidence.networkSnapshotID == bundle.networkSnapshot.id,
        selectedPathEvidence.providerDatasetID
          == providerIdentity.providerDatasetID,
        selectedPathEvidence.directedEdgeIDs == directedEdgeIDs
      else {
        throw JourneyPlanCompilerError.selectedPathEvidenceMismatch
      }
    }
    guard
      let returnBearing = initialBearingDegrees(
        coordinates: candidate.coordinates
      ), let returnEdgeID = directedEdgeIDs.first
    else {
      throw JourneyPlanCompilerError.invalidResolvedPath
    }
    let returnTarget = JourneyReturnTarget(
      id: request.originID,
      coordinate: request.origin,
      directedSurfaceEdgeID: returnEdgeID,
      expectedBearingDegrees: returnBearing
    )

    let selectedEgressOptionID: String?
    switch finishPolicy {
    case .fixedExit:
      selectedEgressOptionID =
        bundle.runtimePolicy.egressOptions.first(where: {
          $0.isReleased && $0.exitFacilityID == bundle.routePlan.exitFacilityID
        })?.id
      guard selectedEgressOptionID != nil else {
        throw JourneyPlanCompilerError.finishPolicyNotReleased(finishPolicy)
      }
    case .finishOnRequest:
      selectedEgressOptionID = nil
    case .returnNearOrigin:
      selectedEgressOptionID = nil
    }

    let accessLeg = JourneySurfaceLeg(
      role: .access,
      networkSnapshotID: bundle.networkSnapshot.id,
      providerIdentity: providerIdentity,
      candidateID: candidate.id,
      originID: request.originID,
      destinationAnchorID: request.destinationAnchor.id,
      entranceFacilityID: request.entranceFacilityID,
      exitFacilityID: nil,
      joinOccurrenceID: request.selectedJoinOccurrenceID,
      directedEdgeIDs: directedEdgeIDs,
      egressMatcherCorridor: nil,
      distanceMeters: candidate.distanceMeters,
      expectedTravelTimeSeconds: candidate.expectedTravelTimeSeconds
    )
    return JourneyPlan(
      id: "\(release.releaseID).journey.\(request.id).\(candidate.id)",
      productReleaseID: release.releaseID,
      navigationReleaseID: release.navigation.releaseID,
      networkSnapshotID: bundle.networkSnapshot.id,
      routePlanID: bundle.routePlan.id,
      originID: request.originID,
      accessLeg: accessLeg,
      returnTarget: returnTarget,
      entryTransition: bundle.runtimePolicy.entryTransition,
      finishPolicy: finishPolicy,
      precomputedEgressOptions: bundle.runtimePolicy.egressOptions,
      selectedEgressOptionID: selectedEgressOptionID,
      egressLeg: nil,
      initialPhase: .approachToEntry
    )
  }

  package static func surfaceAccessPreflight(
    release: KaidoProductRelease,
    request: SurfaceRouteRequest,
    providerIdentity: SurfaceRouteProviderReleaseIdentity,
    finishPolicy: JourneyFinishPolicy
  ) throws -> ReleasedSurfaceAccessDefinition {
    let bundle = release.navigation.bundle
    guard let definition = bundle.surfaceAccessDefinition else {
      throw JourneyPlanCompilerError.surfaceAccessNotReleased
    }
    let definitionIssues = definition.validationIssues(
      networkSnapshot: bundle.networkSnapshot,
      routePlan: bundle.routePlan,
      runtimePolicy: bundle.runtimePolicy
    )
    guard definitionIssues.isEmpty else {
      throw JourneyPlanCompilerError.invalidReleasedSurfaceAccess(definitionIssues)
    }
    guard providerIdentity == definition.providerIdentity else {
      throw JourneyPlanCompilerError.providerIdentityMismatch
    }
    guard definition.allowedFinishPolicies.contains(finishPolicy) else {
      throw JourneyPlanCompilerError.finishPolicyNotReleased(finishPolicy)
    }
    if finishPolicy == .returnNearOrigin,
      bundle.surfaceEgressDefinition == nil
    {
      throw JourneyPlanCompilerError.surfaceEgressNotReleased
    }

    var requestIssues: [String] = []
    if normalized(request.id).isEmpty
      || normalized(request.originID).isEmpty
      || !request.origin.isValid
    {
      requestIssues.append("INVALID_SURFACE_ACCESS_REQUEST_IDENTITY")
    }
    if request.entranceFacilityID != definition.approachPolicy.entranceFacilityID {
      requestIssues.append("SURFACE_ACCESS_REQUEST_ENTRANCE_MISMATCH")
    }
    if request.destinationAnchor != definition.approachPolicy.destinationAnchor {
      requestIssues.append("SURFACE_ACCESS_REQUEST_ANCHOR_MISMATCH")
    }
    if request.selectedJoinOccurrenceID != bundle.routePlan.occurrences.first?.id
      || !definition.approachPolicy.allowedJoinOccurrenceIDs.contains(
        request.selectedJoinOccurrenceID
      )
    {
      requestIssues.append("SURFACE_ACCESS_REQUEST_JOIN_MISMATCH")
    }
    guard requestIssues.isEmpty else {
      throw JourneyPlanCompilerError.invalidRequest(requestIssues.sorted())
    }
    return definition
  }

  package static func surfaceEgress(
    release: KaidoProductRelease,
    basePlan: JourneyPlan,
    request: SurfaceEgressRouteRequest,
    candidate: SurfaceRouteCandidate,
    inspection: SurfaceEgressCandidateInspection,
    providerIdentity: SurfaceRouteProviderReleaseIdentity
  ) throws -> JourneyPlan {
    let policy = try surfaceEgressPreflight(
      release: release,
      basePlan: basePlan,
      request: request,
      providerIdentity: providerIdentity
    )
    let bundle = release.navigation.bundle
    guard inspection.networkSnapshotID == bundle.networkSnapshot.id else {
      throw JourneyPlanCompilerError.inspectionSnapshotMismatch
    }
    let evaluation = SurfaceEgressHardGateEvaluator.evaluate(
      candidate: candidate,
      request: request,
      policy: policy,
      inspection: inspection,
      expectedProviderID: providerIdentity.providerID
    )
    guard evaluation.isAccepted else {
      throw JourneyPlanCompilerError.egressCandidateRejected(
        evaluation.hardGates
      )
    }
    guard let directedEdgeIDs = inspection.resolvedPathEdgeIDs,
      !directedEdgeIDs.isEmpty,
      !directedEdgeIDs.contains(where: { normalized($0).isEmpty })
    else {
      throw JourneyPlanCompilerError.invalidResolvedPath
    }
    guard let resolvedOccurrences = inspection.resolvedPathOccurrences,
      resolvedOccurrences.count == directedEdgeIDs.count,
      resolvedOccurrences.map(\.index)
        == Array(0..<resolvedOccurrences.count),
      resolvedOccurrences.map(\.directedEdgeID) == directedEdgeIDs,
      resolvedOccurrences.allSatisfy(\.isValid)
    else {
      throw JourneyPlanCompilerError.invalidResolvedPath
    }
    if let selectedPathEvidence = candidate.selectedPathEvidence {
      guard
        selectedPathEvidence.networkSnapshotID
          == bundle.networkSnapshot.id,
        selectedPathEvidence.providerDatasetID
          == providerIdentity.providerDatasetID,
        selectedPathEvidence.directedEdgeIDs == directedEdgeIDs
      else {
        throw JourneyPlanCompilerError.selectedPathEvidenceMismatch
      }
    }

    let journeyID =
      "\(basePlan.id).return.\(request.egressOptionID).\(candidate.id)"
    let matcherOccurrences = resolvedOccurrences.map { occurrence in
      SurfaceEgressMatcherOccurrence(
        id: "\(journeyID).surface-occurrence.\(occurrence.index)",
        index: occurrence.index,
        directedEdgeID: occurrence.directedEdgeID,
        coordinates: occurrence.coordinates.map {
          MatcherCoordinate(
            latitude: $0.latitude,
            longitude: $0.longitude
          )
        }
      )
    }
    let egressMatcherCorridor = SurfaceEgressMatcherCorridor(
      id: "\(journeyID).surface-egress-corridor",
      networkSnapshotID: bundle.networkSnapshot.id,
      routePlanID: bundle.routePlan.id,
      providerDatasetID: providerIdentity.providerDatasetID,
      candidateID: candidate.id,
      egressOptionID: request.egressOptionID,
      exitFacilityID: request.exitFacilityID,
      occurrences: matcherOccurrences
    )
    guard egressMatcherCorridor.validationIssues.isEmpty else {
      throw JourneyPlanCompilerError.invalidResolvedPath
    }
    let egressLeg = JourneySurfaceLeg(
      role: .egress,
      networkSnapshotID: bundle.networkSnapshot.id,
      providerIdentity: providerIdentity,
      candidateID: candidate.id,
      originID: request.originAnchor.id,
      destinationAnchorID: request.destinationAnchor.id,
      entranceFacilityID: nil,
      exitFacilityID: request.exitFacilityID,
      joinOccurrenceID: nil,
      directedEdgeIDs: directedEdgeIDs,
      egressMatcherCorridor: egressMatcherCorridor,
      distanceMeters: candidate.distanceMeters,
      expectedTravelTimeSeconds: candidate.expectedTravelTimeSeconds
    )
    return JourneyPlan(
      id: journeyID,
      productReleaseID: basePlan.productReleaseID,
      navigationReleaseID: basePlan.navigationReleaseID,
      networkSnapshotID: basePlan.networkSnapshotID,
      routePlanID: basePlan.routePlanID,
      originID: basePlan.originID,
      accessLeg: basePlan.accessLeg,
      returnTarget: basePlan.returnTarget,
      entryTransition: basePlan.entryTransition,
      finishPolicy: .returnNearOrigin,
      precomputedEgressOptions: basePlan.precomputedEgressOptions,
      selectedEgressOptionID: request.egressOptionID,
      egressLeg: egressLeg,
      initialPhase: basePlan.initialPhase
    )
  }

  package static func surfaceEgressPreflight(
    release: KaidoProductRelease,
    basePlan: JourneyPlan,
    request: SurfaceEgressRouteRequest,
    providerIdentity: SurfaceRouteProviderReleaseIdentity
  ) throws -> SurfaceEgressPolicy {
    let bundle = release.navigation.bundle
    guard let definition = bundle.surfaceEgressDefinition else {
      throw JourneyPlanCompilerError.surfaceEgressNotReleased
    }
    let definitionIssues = definition.validationIssues(
      networkSnapshot: bundle.networkSnapshot,
      routePlan: bundle.routePlan,
      runtimePolicy: bundle.runtimePolicy
    )
    guard definitionIssues.isEmpty else {
      throw JourneyPlanCompilerError.invalidReleasedSurfaceEgress(
        definitionIssues
      )
    }
    guard providerIdentity == definition.providerIdentity else {
      throw JourneyPlanCompilerError.providerIdentityMismatch
    }
    guard basePlan.productReleaseID == release.releaseID,
      basePlan.navigationReleaseID == release.navigation.releaseID,
      basePlan.networkSnapshotID == bundle.networkSnapshot.id,
      basePlan.routePlanID == bundle.routePlan.id,
      basePlan.entryTransition == bundle.runtimePolicy.entryTransition,
      basePlan.precomputedEgressOptions == bundle.runtimePolicy.egressOptions,
      basePlan.finishPolicy == .returnNearOrigin,
      basePlan.initialPhase == .approachToEntry,
      let accessLeg = basePlan.accessLeg,
      let returnTarget = basePlan.returnTarget,
      let accessDefinition = bundle.surfaceAccessDefinition,
      accessDefinition.allowedFinishPolicies.contains(.returnNearOrigin),
      basePlan.originID == accessLeg.originID,
      basePlan.originID == returnTarget.id,
      accessLeg.role == .access,
      accessLeg.networkSnapshotID == bundle.networkSnapshot.id,
      accessLeg.providerIdentity == accessDefinition.providerIdentity,
      accessLeg.destinationAnchorID
        == accessDefinition.approachPolicy.destinationAnchor.id,
      accessLeg.entranceFacilityID
        == accessDefinition.approachPolicy.entranceFacilityID,
      accessLeg.exitFacilityID == nil,
      accessLeg.joinOccurrenceID
        == bundle.routePlan.occurrences.first?.id,
      accessLeg.directedEdgeIDs.first
        == returnTarget.directedSurfaceEdgeID,
      basePlan.egressLeg == nil,
      basePlan.selectedEgressOptionID == nil
    else {
      throw JourneyPlanCompilerError.invalidRequest([
        "INVALID_SURFACE_EGRESS_BASE_PLAN"
      ])
    }
    guard
      let policy = definition.policies.first(where: {
        $0.egressOptionID == request.egressOptionID
      })
    else {
      throw JourneyPlanCompilerError.invalidRequest([
        "SURFACE_EGRESS_OPTION_NOT_RELEASED"
      ])
    }

    let expectedDestinationAnchor = DirectedApproachAnchor(
      id: returnTarget.id,
      coordinate: returnTarget.coordinate,
      directedSurfaceEdgeID: returnTarget.directedSurfaceEdgeID,
      expectedBearingDegrees: returnTarget.expectedBearingDegrees,
      bearingToleranceDegrees:
        policy.returnTargetBearingToleranceDegrees,
      maxTerminalDistanceMeters: policy.maxReturnTargetDistanceMeters
    )
    var requestIssues: [String] = []
    if normalized(request.id).isEmpty {
      requestIssues.append("INVALID_SURFACE_EGRESS_REQUEST_IDENTITY")
    }
    if request.exitFacilityID != policy.exitFacilityID
      || request.egressOptionID != policy.egressOptionID
    {
      requestIssues.append("SURFACE_EGRESS_REQUEST_EXIT_MISMATCH")
    }
    if request.originAnchor != policy.originAnchor {
      requestIssues.append("SURFACE_EGRESS_REQUEST_HANDOFF_MISMATCH")
    }
    if request.destinationAnchor != expectedDestinationAnchor {
      requestIssues.append("SURFACE_EGRESS_REQUEST_RETURN_TARGET_MISMATCH")
    }
    guard requestIssues.isEmpty else {
      throw JourneyPlanCompilerError.invalidRequest(requestIssues.sorted())
    }
    return policy
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func initialBearingDegrees(
    coordinates: [SurfaceCoordinate]
  ) -> Double? {
    guard let origin = coordinates.first else { return nil }
    for destination in coordinates.dropFirst()
    where destination != origin {
      let originLatitude = origin.latitude * .pi / 180
      let destinationLatitude = destination.latitude * .pi / 180
      let longitudeDelta =
        (destination.longitude - origin.longitude) * .pi / 180
      let y = sin(longitudeDelta) * cos(destinationLatitude)
      let x =
        cos(originLatitude) * sin(destinationLatitude)
        - sin(originLatitude) * cos(destinationLatitude)
        * cos(longitudeDelta)
      let bearing = atan2(y, x) * 180 / .pi
      return bearing >= 0 ? bearing : bearing + 360
    }
    return nil
  }
}

extension JourneyPlan {
  package func runtimeAdmissionIssues(
    for release: KaidoProductRelease
  ) -> [JourneyPlanRuntimeAdmissionIssue] {
    let bundle = release.navigation.bundle
    var issues: [JourneyPlanRuntimeAdmissionIssue] = []

    if normalized(id).isEmpty {
      issues.append(.invalidIdentity)
    }
    if productReleaseID != release.releaseID
      || navigationReleaseID != release.navigation.releaseID
    {
      issues.append(.releaseIdentityMismatch)
    }
    if networkSnapshotID != bundle.networkSnapshot.id
      || routePlanID != bundle.routePlan.id
    {
      issues.append(.routeIdentityMismatch)
    }
    if entryTransition != bundle.runtimePolicy.entryTransition {
      issues.append(.entryTransitionMismatch)
    }
    if precomputedEgressOptions != bundle.runtimePolicy.egressOptions {
      issues.append(.egressOptionsMismatch)
    }

    if let accessLeg {
      validateSurfaceAccessLeg(
        accessLeg,
        release: release,
        issues: &issues
      )
      validateReturnTarget(issues: &issues)
    } else if self != JourneyPlanCompiler.routeOnly(release: release) {
      issues.append(.routeOnlyCompositionMismatch)
    }
    if let egressLeg {
      validateSurfaceEgressLeg(
        egressLeg,
        release: release,
        issues: &issues
      )
    }

    validateFinishComposition(
      release: release,
      issues: &issues
    )
    return Array(Set(issues)).sorted { $0.rawValue < $1.rawValue }
  }

  private func validateSurfaceAccessLeg(
    _ accessLeg: JourneySurfaceLeg,
    release: KaidoProductRelease,
    issues: inout [JourneyPlanRuntimeAdmissionIssue]
  ) {
    let bundle = release.navigation.bundle
    guard let definition = bundle.surfaceAccessDefinition else {
      issues.append(.surfaceAccessNotReleased)
      return
    }

    if originID == nil
      || normalized(originID ?? "").isEmpty
      || originID != accessLeg.originID
      || accessLeg.role != .access
      || normalized(accessLeg.candidateID).isEmpty
      || normalized(accessLeg.originID).isEmpty
      || accessLeg.exitFacilityID != nil
      || accessLeg.egressMatcherCorridor != nil
      || accessLeg.directedEdgeIDs.isEmpty
      || accessLeg.directedEdgeIDs.contains(where: { normalized($0).isEmpty })
      || !accessLeg.distanceMeters.isFinite
      || accessLeg.distanceMeters < 0
      || !accessLeg.expectedTravelTimeSeconds.isFinite
      || accessLeg.expectedTravelTimeSeconds < 0
    {
      issues.append(.invalidSurfaceAccessLeg)
    }

    if accessLeg.networkSnapshotID != bundle.networkSnapshot.id
      || accessLeg.providerIdentity != definition.providerIdentity
      || accessLeg.destinationAnchorID
        != definition.approachPolicy.destinationAnchor.id
      || accessLeg.entranceFacilityID
        != definition.approachPolicy.entranceFacilityID
      || accessLeg.joinOccurrenceID != bundle.routePlan.occurrences.first?.id
    {
      issues.append(.surfaceAccessReleaseMismatch)
    }
    if initialPhase != .approachToEntry {
      issues.append(.invalidInitialPhase)
    }
  }

  private func validateReturnTarget(
    issues: inout [JourneyPlanRuntimeAdmissionIssue]
  ) {
    guard let returnTarget else {
      issues.append(.invalidReturnTarget)
      return
    }
    if originID != returnTarget.id
      || normalized(returnTarget.id).isEmpty
      || !returnTarget.coordinate.isValid
      || normalized(returnTarget.directedSurfaceEdgeID).isEmpty
      || returnTarget.directedSurfaceEdgeID
        != accessLeg?.directedEdgeIDs.first
      || !returnTarget.expectedBearingDegrees.isFinite
      || !(0..<360).contains(returnTarget.expectedBearingDegrees)
    {
      issues.append(.invalidReturnTarget)
    }
  }

  private func validateSurfaceEgressLeg(
    _ egressLeg: JourneySurfaceLeg,
    release: KaidoProductRelease,
    issues: inout [JourneyPlanRuntimeAdmissionIssue]
  ) {
    let bundle = release.navigation.bundle
    guard let definition = bundle.surfaceEgressDefinition else {
      issues.append(.surfaceEgressNotReleased)
      return
    }
    guard let selectedEgressOptionID,
      let policy = definition.policies.first(where: {
        $0.egressOptionID == selectedEgressOptionID
      }),
      let returnTarget
    else {
      issues.append(.surfaceEgressReleaseMismatch)
      return
    }

    if egressLeg.role != .egress
      || normalized(egressLeg.candidateID).isEmpty
      || normalized(egressLeg.originID).isEmpty
      || egressLeg.entranceFacilityID != nil
      || egressLeg.joinOccurrenceID != nil
      || egressLeg.egressMatcherCorridor == nil
      || egressLeg.directedEdgeIDs.isEmpty
      || egressLeg.directedEdgeIDs.contains(where: {
        normalized($0).isEmpty
      })
      || !egressLeg.distanceMeters.isFinite
      || egressLeg.distanceMeters < 0
      || !egressLeg.expectedTravelTimeSeconds.isFinite
      || egressLeg.expectedTravelTimeSeconds < 0
    {
      issues.append(.invalidSurfaceEgressLeg)
    }
    if egressLeg.networkSnapshotID != bundle.networkSnapshot.id
      || egressLeg.providerIdentity != definition.providerIdentity
      || egressLeg.originID != policy.originAnchor.id
      || egressLeg.destinationAnchorID != returnTarget.id
      || egressLeg.exitFacilityID != policy.exitFacilityID
      || egressLeg.directedEdgeIDs.first
        != policy.originAnchor.directedSurfaceEdgeID
      || egressLeg.directedEdgeIDs.last
        != returnTarget.directedSurfaceEdgeID
    {
      issues.append(.surfaceEgressReleaseMismatch)
    }
    if let corridor = egressLeg.egressMatcherCorridor {
      if !corridor.validationIssues.isEmpty
        || corridor.networkSnapshotID != bundle.networkSnapshot.id
        || corridor.routePlanID != bundle.routePlan.id
        || corridor.providerDatasetID
          != definition.providerIdentity.providerDatasetID
        || corridor.candidateID != egressLeg.candidateID
        || corridor.egressOptionID != selectedEgressOptionID
        || corridor.exitFacilityID != policy.exitFacilityID
        || corridor.occurrences.map(\.directedEdgeID)
          != egressLeg.directedEdgeIDs
      {
        issues.append(.surfaceEgressReleaseMismatch)
      }
    }
  }

  private func validateFinishComposition(
    release: KaidoProductRelease,
    issues: inout [JourneyPlanRuntimeAdmissionIssue]
  ) {
    let bundle = release.navigation.bundle
    if accessLeg != nil,
      bundle.surfaceAccessDefinition?.allowedFinishPolicies.contains(
        finishPolicy
      ) != true
    {
      issues.append(.finishPolicyNotReleased)
    }

    switch finishPolicy {
    case .fixedExit:
      let expectedID = bundle.runtimePolicy.egressOptions.first(where: {
        $0.isReleased && $0.exitFacilityID == bundle.routePlan.exitFacilityID
      })?.id
      if selectedEgressOptionID == nil
        || selectedEgressOptionID != expectedID
      {
        issues.append(.invalidFinishComposition)
      }
      if egressLeg != nil {
        issues.append(.invalidFinishComposition)
      }
    case .finishOnRequest:
      if selectedEgressOptionID != nil || egressLeg != nil {
        issues.append(.invalidFinishComposition)
      }
    case .returnNearOrigin:
      if selectedEgressOptionID == nil
        || egressLeg == nil
        || returnTarget == nil
        || bundle.surfaceEgressDefinition == nil
      {
        issues.append(.surfaceEgressNotReleased)
      }
    }
  }

  private func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
