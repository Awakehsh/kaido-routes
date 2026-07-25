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
  public let distanceMeters: Double
  public let expectedTravelTimeSeconds: Double

  public var providerID: String {
    providerIdentity.providerID
  }
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
  case finishPolicyNotReleased = "JOURNEY_PLAN_FINISH_POLICY_NOT_RELEASED"
  case invalidFinishComposition = "INVALID_JOURNEY_PLAN_FINISH_COMPOSITION"
  case surfaceEgressNotReleased = "JOURNEY_PLAN_SURFACE_EGRESS_NOT_RELEASED"
  case invalidInitialPhase = "INVALID_JOURNEY_PLAN_INITIAL_PHASE"
  case routeOnlyCompositionMismatch = "JOURNEY_PLAN_ROUTE_ONLY_COMPOSITION_MISMATCH"
}

public enum JourneyPlanRuntimeAdmissionError: Error, Equatable, Sendable {
  case invalid([JourneyPlanRuntimeAdmissionIssue])
}

public enum JourneyPlanCompilerError: Error, Equatable, Sendable {
  case surfaceAccessNotReleased
  case invalidReleasedSurfaceAccess([ReleasedSurfaceAccessIssue])
  case providerIdentityMismatch
  case invalidRequest([String])
  case inspectionSnapshotMismatch
  case candidateRejected([HardGateResult])
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
      throw JourneyPlanCompilerError.surfaceEgressNotReleased
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
    if finishPolicy == .returnNearOrigin {
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

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
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
    if egressLeg != nil {
      issues.append(.surfaceEgressNotReleased)
    }

    if let accessLeg {
      validateSurfaceAccessLeg(
        accessLeg,
        release: release,
        issues: &issues
      )
    } else if self != JourneyPlanCompiler.routeOnly(release: release) {
      issues.append(.routeOnlyCompositionMismatch)
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
    case .finishOnRequest:
      if selectedEgressOptionID != nil {
        issues.append(.invalidFinishComposition)
      }
    case .returnNearOrigin:
      issues.append(.surfaceEgressNotReleased)
    }
  }

  private func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
