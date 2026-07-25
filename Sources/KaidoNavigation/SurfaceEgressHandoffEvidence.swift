import Foundation
import KaidoDomain
import KaidoRouting

/// Exact release and JourneyPlan identity required to leave the expressway
/// runtime and begin one compiled ordinary-road egress leg.
public struct SurfaceEgressAdmissionContext: Equatable, Sendable {
  public let productReleaseID: String
  public let navigationReleaseID: String
  public let journeyPlanID: String
  public let runtimePolicyID: String
  public let networkSnapshotID: String
  public let routePlanID: String
  public let egressOptionID: String
  public let exitFacilityID: String
  public let handoffAnchorID: String
  public let directedSurfaceEdgeID: String
  public let matcherCorridorID: String
  public let matcherCorridor: SurfaceEgressMatcherCorridor
  public let handoffOccurrenceID: String

  package init(
    productReleaseID: String,
    navigationReleaseID: String,
    journeyPlanID: String,
    runtimePolicyID: String,
    networkSnapshotID: String,
    routePlanID: String,
    egressOptionID: String,
    exitFacilityID: String,
    handoffAnchorID: String,
    directedSurfaceEdgeID: String,
    matcherCorridor: SurfaceEgressMatcherCorridor,
    handoffOccurrenceID: String
  ) {
    self.productReleaseID = productReleaseID
    self.navigationReleaseID = navigationReleaseID
    self.journeyPlanID = journeyPlanID
    self.runtimePolicyID = runtimePolicyID
    self.networkSnapshotID = networkSnapshotID
    self.routePlanID = routePlanID
    self.egressOptionID = egressOptionID
    self.exitFacilityID = exitFacilityID
    self.handoffAnchorID = handoffAnchorID
    self.directedSurfaceEdgeID = directedSurfaceEdgeID
    matcherCorridorID = matcherCorridor.id
    self.matcherCorridor = matcherCorridor
    self.handoffOccurrenceID = handoffOccurrenceID
  }
}

public enum SurfaceEgressHandoffEvidenceSource:
  String, Equatable, Sendable
{
  case coreLocationRouteAwareMatcher =
    "CORE_LOCATION_ROUTE_AWARE_MATCHER"
}

/// One exit-side match from a reviewed Apple adapter.
///
/// A caller cannot construct this value outside the package. Two fresh HIGH
/// observations with increasing along-edge progress are required before the
/// session changes phase.
public struct SurfaceEgressHandoffEvidence: Equatable, Sendable {
  public let productReleaseID: String
  public let navigationReleaseID: String
  public let journeyPlanID: String
  public let runtimePolicyID: String
  public let networkSnapshotID: String
  public let routePlanID: String
  public let egressOptionID: String
  public let exitFacilityID: String
  public let handoffAnchorID: String
  public let observationID: String
  public let observedAtMilliseconds: Int
  public let receivedAtMilliseconds: Int
  public let directedSurfaceEdgeID: String?
  public let candidateEdgeIDs: [String]
  public let matcherCorridorID: String
  public let surfaceOccurrenceID: String?
  public let candidateOccurrenceIDs: [String]
  public let fractionAlongEdge: Double?
  public let confidence: MatcherConfidence
  public let headingErrorDegrees: Double?
  public let source: SurfaceEgressHandoffEvidenceSource
  public let isSimulatedBySoftware: Bool

  package init(
    context: SurfaceEgressAdmissionContext,
    observationID: String,
    observedAtMilliseconds: Int,
    receivedAtMilliseconds: Int,
    directedSurfaceEdgeID: String?,
    candidateEdgeIDs: [String],
    surfaceOccurrenceID: String?,
    candidateOccurrenceIDs: [String],
    fractionAlongEdge: Double?,
    confidence: MatcherConfidence,
    headingErrorDegrees: Double?,
    source: SurfaceEgressHandoffEvidenceSource =
      .coreLocationRouteAwareMatcher,
    isSimulatedBySoftware: Bool
  ) {
    productReleaseID = context.productReleaseID
    navigationReleaseID = context.navigationReleaseID
    journeyPlanID = context.journeyPlanID
    runtimePolicyID = context.runtimePolicyID
    networkSnapshotID = context.networkSnapshotID
    routePlanID = context.routePlanID
    egressOptionID = context.egressOptionID
    exitFacilityID = context.exitFacilityID
    handoffAnchorID = context.handoffAnchorID
    self.observationID = observationID
    self.observedAtMilliseconds = observedAtMilliseconds
    self.receivedAtMilliseconds = receivedAtMilliseconds
    self.directedSurfaceEdgeID = directedSurfaceEdgeID
    self.candidateEdgeIDs = candidateEdgeIDs
    matcherCorridorID = context.matcherCorridorID
    self.surfaceOccurrenceID = surfaceOccurrenceID
    self.candidateOccurrenceIDs = candidateOccurrenceIDs
    self.fractionAlongEdge = fractionAlongEdge
    self.confidence = confidence
    self.headingErrorDegrees = headingErrorDegrees
    self.source = source
    self.isSimulatedBySoftware = isSimulatedBySoftware
  }
}

public enum SurfaceEgressHandoffRejectionReason:
  String, Equatable, Sendable
{
  case runtimeNotReleaseAdmitted = "RUNTIME_NOT_RELEASE_ADMITTED"
  case releaseIdentityMismatch = "RELEASE_IDENTITY_MISMATCH"
  case journeyPhaseNotEligible = "JOURNEY_PHASE_NOT_ELIGIBLE"
  case inactiveEgressPlan = "INACTIVE_EGRESS_PLAN"
  case invalidObservationIdentity = "INVALID_OBSERVATION_IDENTITY"
  case invalidTimestamp = "INVALID_TIMESTAMP"
  case replayedOrStaleObservation = "REPLAYED_OR_STALE_OBSERVATION"
  case receiveOrderReversal = "RECEIVE_ORDER_REVERSAL"
  case delayedObservation = "DELAYED_OBSERVATION"
  case simulatedLocation = "SIMULATED_LOCATION"
  case unsupportedEvidenceSource = "UNSUPPORTED_EVIDENCE_SOURCE"
  case insufficientConfidence = "INSUFFICIENT_CONFIDENCE"
  case ambiguousEdge = "AMBIGUOUS_EDGE"
  case unexpectedEdge = "UNEXPECTED_SURFACE_EGRESS_EDGE"
  case ambiguousOccurrence = "AMBIGUOUS_SURFACE_EGRESS_OCCURRENCE"
  case unexpectedOccurrence = "UNEXPECTED_SURFACE_EGRESS_OCCURRENCE"
  case invalidAlongEdgeProgress = "INVALID_ALONG_EDGE_PROGRESS"
  case nonForwardProgress = "NON_FORWARD_PROGRESS"
  case missingHeading = "MISSING_HEADING"
  case headingMismatch = "HEADING_MISMATCH"
}

public enum SurfaceEgressHandoffAdmissionStatus:
  String, Equatable, Sendable
{
  case rejected = "REJECTED"
  case observing = "OBSERVING"
  case surfaceEgressEntered = "SURFACE_EGRESS_ENTERED"
}

public struct SurfaceEgressHandoffSessionUpdate:
  Equatable, Sendable
{
  public let status: SurfaceEgressHandoffAdmissionStatus
  public let rejectionReason: SurfaceEgressHandoffRejectionReason?
  public let navigationSnapshot: NavigationSnapshot

  public init(
    status: SurfaceEgressHandoffAdmissionStatus,
    rejectionReason: SurfaceEgressHandoffRejectionReason? = nil,
    navigationSnapshot: NavigationSnapshot
  ) {
    self.status = status
    self.rejectionReason = rejectionReason
    self.navigationSnapshot = navigationSnapshot
  }
}

package struct SurfaceEgressHandoffDecision: Equatable, Sendable {
  package let status: SurfaceEgressHandoffAdmissionStatus
  package let rejectionReason: SurfaceEgressHandoffRejectionReason?
}

package struct SurfaceEgressHandoffEvidenceAdmission: Sendable {
  static let maximumEvidenceAgeMilliseconds = 10_000
  static let maximumHeadingErrorDegrees = 45.0

  package let context: SurfaceEgressAdmissionContext

  private var lastObservationID: String?
  private var lastObservedAtMilliseconds: Int?
  private var lastReceivedAtMilliseconds: Int?
  private var admittedFractionAlongEdge: Double?

  package init(context: SurfaceEgressAdmissionContext) {
    self.context = context
  }

  package mutating func admit(
    _ evidence: SurfaceEgressHandoffEvidence,
    snapshot: NavigationSnapshot
  ) -> SurfaceEgressHandoffDecision {
    guard snapshot.journeyPhase == .exitTransition else {
      return rejected(.journeyPhaseNotEligible)
    }
    guard snapshot.egress.status == .active,
      snapshot.egress.exitFacilityID == context.exitFacilityID
    else {
      return rejected(.inactiveEgressPlan)
    }
    guard identityMatches(evidence) else {
      return rejected(.releaseIdentityMismatch)
    }
    guard
      !evidence.observationID.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty
    else {
      return rejected(.invalidObservationIdentity)
    }
    guard
      evidence.receivedAtMilliseconds
        >= evidence.observedAtMilliseconds
    else {
      return rejected(.invalidTimestamp)
    }
    let (age, overflow) =
      evidence.receivedAtMilliseconds.subtractingReportingOverflow(
        evidence.observedAtMilliseconds
      )
    guard !overflow else {
      return rejected(.invalidTimestamp)
    }
    guard evidence.observationID != lastObservationID,
      lastObservedAtMilliseconds.map({
        evidence.observedAtMilliseconds > $0
      }) != false
    else {
      return rejected(.replayedOrStaleObservation)
    }
    guard
      lastReceivedAtMilliseconds.map({
        evidence.receivedAtMilliseconds >= $0
      }) != false
    else {
      return rejected(.receiveOrderReversal)
    }
    lastObservationID = evidence.observationID
    lastObservedAtMilliseconds = evidence.observedAtMilliseconds
    lastReceivedAtMilliseconds = evidence.receivedAtMilliseconds

    guard age < Self.maximumEvidenceAgeMilliseconds else {
      return rejected(.delayedObservation)
    }
    guard !evidence.isSimulatedBySoftware else {
      return rejected(.simulatedLocation)
    }
    guard evidence.source == .coreLocationRouteAwareMatcher else {
      return rejected(.unsupportedEvidenceSource)
    }
    guard evidence.confidence == .high else {
      return rejected(.insufficientConfidence)
    }
    guard let edgeID = evidence.directedSurfaceEdgeID,
      evidence.candidateEdgeIDs == [edgeID]
    else {
      return rejected(.ambiguousEdge)
    }
    guard edgeID == context.directedSurfaceEdgeID else {
      return rejected(.unexpectedEdge)
    }
    guard let occurrenceID = evidence.surfaceOccurrenceID,
      evidence.candidateOccurrenceIDs == [occurrenceID]
    else {
      return rejected(.ambiguousOccurrence)
    }
    guard occurrenceID == context.handoffOccurrenceID else {
      return rejected(.unexpectedOccurrence)
    }
    guard let fraction = evidence.fractionAlongEdge,
      fraction.isFinite,
      (0...1).contains(fraction)
    else {
      return rejected(.invalidAlongEdgeProgress)
    }
    guard let headingErrorDegrees = evidence.headingErrorDegrees,
      headingErrorDegrees.isFinite,
      (0...180).contains(headingErrorDegrees)
    else {
      return rejected(.missingHeading)
    }
    guard headingErrorDegrees <= Self.maximumHeadingErrorDegrees else {
      return rejected(.headingMismatch)
    }

    guard let previousFraction = admittedFractionAlongEdge else {
      admittedFractionAlongEdge = fraction
      return SurfaceEgressHandoffDecision(
        status: .observing,
        rejectionReason: nil
      )
    }
    guard fraction > previousFraction else {
      return rejected(.nonForwardProgress)
    }
    admittedFractionAlongEdge = fraction
    return SurfaceEgressHandoffDecision(
      status: .surfaceEgressEntered,
      rejectionReason: nil
    )
  }

  private func identityMatches(
    _ evidence: SurfaceEgressHandoffEvidence
  ) -> Bool {
    evidence.productReleaseID == context.productReleaseID
      && evidence.navigationReleaseID == context.navigationReleaseID
      && evidence.journeyPlanID == context.journeyPlanID
      && evidence.runtimePolicyID == context.runtimePolicyID
      && evidence.networkSnapshotID == context.networkSnapshotID
      && evidence.routePlanID == context.routePlanID
      && evidence.egressOptionID == context.egressOptionID
      && evidence.exitFacilityID == context.exitFacilityID
      && evidence.handoffAnchorID == context.handoffAnchorID
      && evidence.matcherCorridorID == context.matcherCorridorID
  }

  private func rejected(
    _ reason: SurfaceEgressHandoffRejectionReason
  ) -> SurfaceEgressHandoffDecision {
    SurfaceEgressHandoffDecision(
      status: .rejected,
      rejectionReason: reason
    )
  }
}
