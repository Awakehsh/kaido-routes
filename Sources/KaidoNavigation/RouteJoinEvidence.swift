import Foundation
import KaidoDomain

/// Why a driver-declared route join was refused.
public enum RouteJoinRejectionReason: String, Equatable, Sendable {
  case runtimeNotReleaseAdmitted = "RUNTIME_NOT_RELEASE_ADMITTED"
  case releaseIdentityMismatch = "RELEASE_IDENTITY_MISMATCH"
  case journeyPhaseNotEligible = "JOURNEY_PHASE_NOT_ELIGIBLE"
  case notDeclaredByDriver = "NOT_DECLARED_BY_DRIVER"
  case declarationExpired = "DECLARATION_EXPIRED"
  case invalidObservationIdentity = "INVALID_OBSERVATION_IDENTITY"
  case invalidTimestamp = "INVALID_TIMESTAMP"
  case replayedOrStaleObservation = "REPLAYED_OR_STALE_OBSERVATION"
  case receiveOrderReversal = "RECEIVE_ORDER_REVERSAL"
  case delayedObservation = "DELAYED_OBSERVATION"
  case simulatedLocation = "SIMULATED_LOCATION"
  case unsupportedEvidenceSource = "UNSUPPORTED_EVIDENCE_SOURCE"
  case insufficientConfidence = "INSUFFICIENT_CONFIDENCE"
  case ambiguousEdge = "AMBIGUOUS_EDGE"
  case missingHeading = "MISSING_HEADING"
  case headingMismatch = "HEADING_MISMATCH"
  case unresolvedOccurrence = "UNRESOLVED_ROUTE_OCCURRENCE"
  case occurrenceNotInPlan = "OCCURRENCE_NOT_IN_ROUTE_PLAN"
}

public enum RouteJoinAdmissionStatus: String, Equatable, Sendable {
  case rejected = "REJECTED"
  case observing = "OBSERVING"
  case joined = "JOINED"
}

public enum RouteJoinEvidenceSource: String, Equatable, Sendable {
  case coreLocationRouteAwareMatcher = "CORE_LOCATION_ROUTE_AWARE_MATCHER"
}

/// One immutable on-route match offered while the driver claims to already be
/// driving the selected route.
///
/// The driver supplies only the intent. Position still comes from the reviewed
/// route-aware matcher, so this value carries the resolved occurrence rather
/// than letting the App name one.
public struct RouteJoinEvidence: Equatable, Sendable {
  public let productReleaseID: String
  public let navigationReleaseID: String
  public let runtimePolicyID: String
  public let networkSnapshotID: String
  public let routePlanID: String
  public let matcherCorridorID: String
  public let observationID: String
  public let observedAtMilliseconds: Int
  public let receivedAtMilliseconds: Int
  public let occurrenceID: String?
  public let directedEdgeID: String?
  public let candidateEdgeIDs: [String]
  public let confidence: MatcherConfidence
  public let headingErrorDegrees: Double?
  public let source: RouteJoinEvidenceSource
  public let isSimulatedBySoftware: Bool

  package init(
    context: EntryTransitionAdmissionContext,
    observationID: String,
    observedAtMilliseconds: Int,
    receivedAtMilliseconds: Int,
    occurrenceID: String?,
    directedEdgeID: String?,
    candidateEdgeIDs: [String],
    confidence: MatcherConfidence,
    headingErrorDegrees: Double?,
    source: RouteJoinEvidenceSource = .coreLocationRouteAwareMatcher,
    isSimulatedBySoftware: Bool
  ) {
    productReleaseID = context.productReleaseID
    navigationReleaseID = context.navigationReleaseID
    runtimePolicyID = context.runtimePolicyID
    networkSnapshotID = context.networkSnapshotID
    routePlanID = context.routePlanID
    matcherCorridorID = context.matcherCorridorID
    self.observationID = observationID
    self.observedAtMilliseconds = observedAtMilliseconds
    self.receivedAtMilliseconds = receivedAtMilliseconds
    self.occurrenceID = occurrenceID
    self.directedEdgeID = directedEdgeID
    self.candidateEdgeIDs = candidateEdgeIDs
    self.confidence = confidence
    self.headingErrorDegrees = headingErrorDegrees
    self.source = source
    self.isSimulatedBySoftware = isSimulatedBySoftware
  }
}

public struct RouteJoinSessionUpdate: Equatable, Sendable {
  public let status: RouteJoinAdmissionStatus
  public let rejectionReason: RouteJoinRejectionReason?
  public let joinedOccurrenceID: String?
  public let navigationSnapshot: NavigationSnapshot

  public init(
    status: RouteJoinAdmissionStatus,
    rejectionReason: RouteJoinRejectionReason? = nil,
    joinedOccurrenceID: String? = nil,
    navigationSnapshot: NavigationSnapshot
  ) {
    self.status = status
    self.rejectionReason = rejectionReason
    self.joinedOccurrenceID = joinedOccurrenceID
    self.navigationSnapshot = navigationSnapshot
  }
}

package struct RouteJoinAdmissionDecision: Equatable, Sendable {
  package let status: RouteJoinAdmissionStatus
  package let rejectionReason: RouteJoinRejectionReason?
  package let joinedOccurrenceID: String?
}

/// Admits a join onto the strict route that no reviewed entry ramp proved.
///
/// Sensors cannot separate an elevated Shuto carriageway from the surface road
/// beneath it, so a driver who is already on the expressway when the drive
/// starts can never satisfy `EntryTransitionEvidenceAdmission`. This admission
/// takes the one thing the driver knows and the phone does not — that the car
/// is on the expressway — and still refuses to move until the matcher settles
/// on one exact plan occurrence on its own. The declaration is a permission to
/// look, never a position.
///
/// It is deliberately stricter than ramp entry: no reviewed edge sequence
/// backs this transition, so the heading window is tighter and the continuity
/// run is longer.
package struct RouteJoinAdmission: Sendable {
  static let maximumEvidenceAgeMilliseconds = 10_000
  static let maximumHeadingErrorDegrees = 30.0
  static let minimumObservationCount = 3
  static let maximumGapMilliseconds = 6_000
  /// A declaration the matcher cannot honor within this window lapses, so the
  /// App reports an honest failure instead of joining minutes later from a
  /// place the driver never confirmed.
  static let declarationLifetimeMilliseconds = 45_000

  package let context: EntryTransitionAdmissionContext

  private let planOccurrenceIDs: Set<String>
  private var declaredAtMilliseconds: Int?
  private var candidateOccurrenceID: String?
  private var observationCount = 0
  private var lastObservationID: String?
  private var lastObservedAtMilliseconds: Int?
  private var lastReceivedAtMilliseconds: Int?
  private var lastAcceptedAtMilliseconds: Int?

  package init(
    context: EntryTransitionAdmissionContext,
    routePlan: RoutePlan
  ) {
    self.context = context
    planOccurrenceIDs = Set(routePlan.occurrences.map(\.id))
  }

  package var isDeclared: Bool { declaredAtMilliseconds != nil }

  package mutating func declare(atMilliseconds milliseconds: Int) {
    declaredAtMilliseconds = milliseconds
    resetContinuity()
  }

  package mutating func withdraw() {
    declaredAtMilliseconds = nil
    resetContinuity()
  }

  package mutating func admit(
    _ evidence: RouteJoinEvidence,
    journeyPhase: JourneyPhase
  ) -> RouteJoinAdmissionDecision {
    guard
      journeyPhase == .planning
        || journeyPhase == .approachToEntry
        || journeyPhase == .entryTransition
    else {
      return rejected(.journeyPhaseNotEligible)
    }
    guard let declaredAtMilliseconds else {
      return rejected(.notDeclaredByDriver)
    }
    guard identityMatches(evidence) else {
      return rejected(.releaseIdentityMismatch)
    }
    guard
      !evidence.observationID
        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return rejected(.invalidObservationIdentity)
    }
    guard evidence.receivedAtMilliseconds >= evidence.observedAtMilliseconds
    else {
      return rejected(.invalidTimestamp)
    }
    let (evidenceAgeMilliseconds, ageOverflow) =
      evidence.receivedAtMilliseconds.subtractingReportingOverflow(
        evidence.observedAtMilliseconds
      )
    guard !ageOverflow else {
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

    guard
      evidence.observedAtMilliseconds - declaredAtMilliseconds
        <= Self.declarationLifetimeMilliseconds
    else {
      withdraw()
      return rejected(.declarationExpired)
    }
    guard evidenceAgeMilliseconds < Self.maximumEvidenceAgeMilliseconds else {
      return rejected(.delayedObservation)
    }
    guard !evidence.isSimulatedBySoftware else {
      return rejected(.simulatedLocation)
    }
    guard evidence.source == .coreLocationRouteAwareMatcher else {
      return rejected(.unsupportedEvidenceSource)
    }
    guard evidence.confidence == .high else {
      resetContinuity()
      return rejected(.insufficientConfidence)
    }
    guard let directedEdgeID = evidence.directedEdgeID,
      evidence.candidateEdgeIDs == [directedEdgeID]
    else {
      resetContinuity()
      return rejected(.ambiguousEdge)
    }
    guard let headingErrorDegrees = evidence.headingErrorDegrees,
      headingErrorDegrees.isFinite,
      (0...180).contains(headingErrorDegrees)
    else {
      resetContinuity()
      return rejected(.missingHeading)
    }
    guard headingErrorDegrees <= Self.maximumHeadingErrorDegrees else {
      resetContinuity()
      return rejected(.headingMismatch)
    }
    guard let occurrenceID = evidence.occurrenceID else {
      resetContinuity()
      return rejected(.unresolvedOccurrence)
    }
    guard planOccurrenceIDs.contains(occurrenceID) else {
      resetContinuity()
      return rejected(.occurrenceNotInPlan)
    }

    // A run that drifts onto a different occurrence, or pauses long enough for
    // the car to have moved somewhere unobserved, starts over rather than
    // joining at a place two distant fixes happened to agree on.
    let continuesRun =
      candidateOccurrenceID == occurrenceID
      && lastAcceptedAtMilliseconds.map({
        evidence.observedAtMilliseconds - $0 <= Self.maximumGapMilliseconds
      }) == true
    candidateOccurrenceID = occurrenceID
    observationCount = continuesRun ? observationCount + 1 : 1
    lastAcceptedAtMilliseconds = evidence.observedAtMilliseconds

    guard observationCount >= Self.minimumObservationCount else {
      return RouteJoinAdmissionDecision(
        status: .observing,
        rejectionReason: nil,
        joinedOccurrenceID: nil
      )
    }
    return RouteJoinAdmissionDecision(
      status: .joined,
      rejectionReason: nil,
      joinedOccurrenceID: occurrenceID
    )
  }

  private func identityMatches(_ evidence: RouteJoinEvidence) -> Bool {
    evidence.productReleaseID == context.productReleaseID
      && evidence.navigationReleaseID == context.navigationReleaseID
      && evidence.runtimePolicyID == context.runtimePolicyID
      && evidence.networkSnapshotID == context.networkSnapshotID
      && evidence.routePlanID == context.routePlanID
      && evidence.matcherCorridorID == context.matcherCorridorID
  }

  private mutating func resetContinuity() {
    candidateOccurrenceID = nil
    observationCount = 0
    lastAcceptedAtMilliseconds = nil
  }

  private func rejected(
    _ reason: RouteJoinRejectionReason
  ) -> RouteJoinAdmissionDecision {
    RouteJoinAdmissionDecision(
      status: .rejected,
      rejectionReason: reason,
      joinedOccurrenceID: nil
    )
  }
}
