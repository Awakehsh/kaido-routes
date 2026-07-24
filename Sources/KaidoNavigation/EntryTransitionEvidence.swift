import Foundation
import KaidoDomain

/// Release identity and reviewed geometry required by the Apple entry adapter.
///
/// External code can inspect this value and pass it to `KaidoAppleAdapters`, but
/// only a validated `KaidoProductNavigationRuntime` can construct it.
public struct EntryTransitionAdmissionContext: Equatable, Sendable {
  public let productReleaseID: String
  public let navigationReleaseID: String
  public let runtimePolicyID: String
  public let networkSnapshotID: String
  public let routePlanID: String
  public let matcherCorridorID: String
  public let entryTransition: EntryTransition
  public let matcherCorridor: RouteMatcherCorridor
  public let firstRouteDirectedEdgeID: String

  package init(
    productReleaseID: String,
    navigationReleaseID: String,
    runtimePolicyID: String,
    networkSnapshotID: String,
    routePlanID: String,
    matcherCorridorID: String,
    entryTransition: EntryTransition,
    matcherCorridor: RouteMatcherCorridor,
    firstRouteDirectedEdgeID: String
  ) {
    self.productReleaseID = productReleaseID
    self.navigationReleaseID = navigationReleaseID
    self.runtimePolicyID = runtimePolicyID
    self.networkSnapshotID = networkSnapshotID
    self.routePlanID = routePlanID
    self.matcherCorridorID = matcherCorridorID
    self.entryTransition = entryTransition
    self.matcherCorridor = matcherCorridor
    self.firstRouteDirectedEdgeID = firstRouteDirectedEdgeID
  }
}

public enum EntryTransitionEvidenceSource: String, Equatable, Sendable {
  case coreLocationRouteAwareMatcher = "CORE_LOCATION_ROUTE_AWARE_MATCHER"
}

/// One immutable entry-path match produced by the reviewed Apple adapter.
///
/// The initializer is package-scoped so an application cannot turn an arbitrary
/// edge ID or boolean into entry authority. `NavigationSession` still validates
/// every field and owns ordered continuity.
public struct EntryTransitionEvidence: Equatable, Sendable {
  public let productReleaseID: String
  public let navigationReleaseID: String
  public let runtimePolicyID: String
  public let networkSnapshotID: String
  public let routePlanID: String
  public let matcherCorridorID: String
  public let observationID: String
  public let observedAtMilliseconds: Int
  public let receivedAtMilliseconds: Int
  public let directedEdgeID: String?
  public let candidateEdgeIDs: [String]
  public let confidence: MatcherConfidence
  public let headingErrorDegrees: Double?
  public let source: EntryTransitionEvidenceSource
  public let isSimulatedBySoftware: Bool

  package init(
    context: EntryTransitionAdmissionContext,
    observationID: String,
    observedAtMilliseconds: Int,
    receivedAtMilliseconds: Int,
    directedEdgeID: String?,
    candidateEdgeIDs: [String],
    confidence: MatcherConfidence,
    headingErrorDegrees: Double?,
    source: EntryTransitionEvidenceSource = .coreLocationRouteAwareMatcher,
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
    self.directedEdgeID = directedEdgeID
    self.candidateEdgeIDs = candidateEdgeIDs
    self.confidence = confidence
    self.headingErrorDegrees = headingErrorDegrees
    self.source = source
    self.isSimulatedBySoftware = isSimulatedBySoftware
  }

  package init(
    productReleaseID: String,
    navigationReleaseID: String,
    runtimePolicyID: String,
    networkSnapshotID: String,
    routePlanID: String,
    matcherCorridorID: String,
    observationID: String,
    observedAtMilliseconds: Int,
    receivedAtMilliseconds: Int,
    directedEdgeID: String?,
    candidateEdgeIDs: [String],
    confidence: MatcherConfidence,
    headingErrorDegrees: Double?,
    source: EntryTransitionEvidenceSource,
    isSimulatedBySoftware: Bool
  ) {
    self.productReleaseID = productReleaseID
    self.navigationReleaseID = navigationReleaseID
    self.runtimePolicyID = runtimePolicyID
    self.networkSnapshotID = networkSnapshotID
    self.routePlanID = routePlanID
    self.matcherCorridorID = matcherCorridorID
    self.observationID = observationID
    self.observedAtMilliseconds = observedAtMilliseconds
    self.receivedAtMilliseconds = receivedAtMilliseconds
    self.directedEdgeID = directedEdgeID
    self.candidateEdgeIDs = candidateEdgeIDs
    self.confidence = confidence
    self.headingErrorDegrees = headingErrorDegrees
    self.source = source
    self.isSimulatedBySoftware = isSimulatedBySoftware
  }
}

public enum EntryTransitionEvidenceRejectionReason: String, Equatable, Sendable {
  case runtimeNotReleaseAdmitted = "RUNTIME_NOT_RELEASE_ADMITTED"
  case releaseIdentityMismatch = "RELEASE_IDENTITY_MISMATCH"
  case journeyPhaseNotEligible = "JOURNEY_PHASE_NOT_ELIGIBLE"
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
  case unexpectedEdge = "UNEXPECTED_ENTRY_EDGE"
  case outOfOrderEdge = "OUT_OF_ORDER_ENTRY_EDGE"
}

public enum EntryTransitionAdmissionStatus: String, Equatable, Sendable {
  case rejected = "REJECTED"
  case observing = "OBSERVING"
  case progressed = "PROGRESSED"
  case strictRouteEntered = "STRICT_ROUTE_ENTERED"
}

public struct EntryTransitionSessionUpdate: Equatable, Sendable {
  public let status: EntryTransitionAdmissionStatus
  public let rejectionReason: EntryTransitionEvidenceRejectionReason?
  public let acceptedTransitionEdgeIndex: Int?
  public let navigationSnapshot: NavigationSnapshot

  public init(
    status: EntryTransitionAdmissionStatus,
    rejectionReason: EntryTransitionEvidenceRejectionReason? = nil,
    acceptedTransitionEdgeIndex: Int? = nil,
    navigationSnapshot: NavigationSnapshot
  ) {
    self.status = status
    self.rejectionReason = rejectionReason
    self.acceptedTransitionEdgeIndex = acceptedTransitionEdgeIndex
    self.navigationSnapshot = navigationSnapshot
  }
}

package struct EntryTransitionAdmissionDecision: Equatable, Sendable {
  package let status: EntryTransitionAdmissionStatus
  package let rejectionReason: EntryTransitionEvidenceRejectionReason?
  package let acceptedTransitionEdgeIndex: Int?
  package let engineObservation: LocationObservation?
}

package struct EntryTransitionEvidenceAdmission: Sendable {
  static let maximumEvidenceAgeMilliseconds = 10_000
  static let maximumHeadingErrorDegrees = 45.0

  package let context: EntryTransitionAdmissionContext

  private var progress = -1
  private var lastObservationID: String?
  private var lastObservedAtMilliseconds: Int?
  private var lastReceivedAtMilliseconds: Int?

  package init(context: EntryTransitionAdmissionContext) {
    self.context = context
  }

  package mutating func admit(
    _ evidence: EntryTransitionEvidence,
    journeyPhase: JourneyPhase
  ) -> EntryTransitionAdmissionDecision {
    guard
      journeyPhase == .planning
        || journeyPhase == .approachToEntry
        || journeyPhase == .entryTransition
    else {
      return rejected(.journeyPhaseNotEligible)
    }
    guard identityMatches(evidence) else {
      return rejected(.releaseIdentityMismatch)
    }
    guard !evidence.observationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return rejected(.invalidObservationIdentity)
    }
    guard evidence.receivedAtMilliseconds >= evidence.observedAtMilliseconds else {
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
      lastObservedAtMilliseconds.map({ evidence.observedAtMilliseconds > $0 }) != false
    else {
      return rejected(.replayedOrStaleObservation)
    }
    guard
      lastReceivedAtMilliseconds.map({ evidence.receivedAtMilliseconds >= $0 }) != false
    else {
      return rejected(.receiveOrderReversal)
    }
    lastObservationID = evidence.observationID
    lastObservedAtMilliseconds = evidence.observedAtMilliseconds
    lastReceivedAtMilliseconds = evidence.receivedAtMilliseconds

    guard evidenceAgeMilliseconds < Self.maximumEvidenceAgeMilliseconds
    else {
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
    guard let directedEdgeID = evidence.directedEdgeID,
      evidence.candidateEdgeIDs == [directedEdgeID]
    else {
      return rejected(.ambiguousEdge)
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
    guard
      let position = context.entryTransition.directedEdgeIDs.firstIndex(
        of: directedEdgeID
      )
    else {
      return rejected(.unexpectedEdge)
    }

    let advanced: Bool
    if progress == -1, position == 0 {
      progress = 0
      advanced = false
    } else if position == progress {
      advanced = false
    } else if position == progress + 1 {
      progress = position
      advanced = true
    } else {
      return rejected(.outOfOrderEdge)
    }

    let isFinal =
      progress == context.entryTransition.directedEdgeIDs.count - 1
      && advanced
    let firstOccurrenceID = context.entryTransition.firstRouteOccurrenceID
    let observation = LocationObservation(
      directedEdgeID: directedEdgeID,
      observedAtMilliseconds: evidence.observedAtMilliseconds,
      reportedConfidence: .high,
      ageMilliseconds: evidenceAgeMilliseconds,
      headingMatches: true,
      forwardContinuity: advanced,
      reachableOccurrenceIDs: isFinal ? Set([firstOccurrenceID].compactMap { $0 }) : []
    )
    return EntryTransitionAdmissionDecision(
      status: isFinal ? .strictRouteEntered : (advanced ? .progressed : .observing),
      rejectionReason: nil,
      acceptedTransitionEdgeIndex: progress,
      engineObservation: observation
    )
  }

  private func identityMatches(_ evidence: EntryTransitionEvidence) -> Bool {
    evidence.productReleaseID == context.productReleaseID
      && evidence.navigationReleaseID == context.navigationReleaseID
      && evidence.runtimePolicyID == context.runtimePolicyID
      && evidence.networkSnapshotID == context.networkSnapshotID
      && evidence.routePlanID == context.routePlanID
      && evidence.matcherCorridorID == context.matcherCorridorID
  }

  private func rejected(
    _ reason: EntryTransitionEvidenceRejectionReason
  ) -> EntryTransitionAdmissionDecision {
    EntryTransitionAdmissionDecision(
      status: .rejected,
      rejectionReason: reason,
      acceptedTransitionEdgeIndex: progress >= 0 ? progress : nil,
      engineObservation: nil
    )
  }
}

package enum EntryTransitionCorridorValidator {
  package static func issues(
    transition: EntryTransition,
    routePlan: RoutePlan,
    matcherCorridor: RouteMatcherCorridor
  ) -> [String] {
    let transitionEdgeIDs = transition.directedEdgeIDs
    guard transitionEdgeIDs.count >= 2 else {
      return ["entry transition requires at least two reviewed directed edges"]
    }

    let edgeByID = Dictionary(
      matcherCorridor.edges.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    var issues: [String] = []
    for edgeID in transitionEdgeIDs where edgeByID[edgeID] == nil {
      issues.append("entry transition edge \(edgeID) is missing from matcher corridor")
    }
    for (currentID, nextID) in zip(transitionEdgeIDs, transitionEdgeIDs.dropFirst()) {
      if edgeByID[currentID]?.successorEdgeIDs.contains(nextID) != true {
        issues.append("entry transition edge \(currentID) does not lead to \(nextID)")
      }
    }

    guard let firstOccurrenceID = transition.firstRouteOccurrenceID,
      let firstOccurrence = routePlan.occurrence(id: firstOccurrenceID),
      let firstBinding = matcherCorridor.occurrences.first(where: {
        $0.id == firstOccurrence.id && $0.index == firstOccurrence.index
      }),
      let finalTransitionEdgeID = transitionEdgeIDs.last
    else {
      issues.append("entry transition cannot resolve the first RoutePlan occurrence")
      return Array(Set(issues)).sorted()
    }

    if finalTransitionEdgeID != firstBinding.directedEdgeID,
      edgeByID[finalTransitionEdgeID]?.successorEdgeIDs.contains(
        firstBinding.directedEdgeID
      ) != true
    {
      issues.append(
        "entry transition final edge does not lead to the first RoutePlan occurrence"
      )
    }
    return Array(Set(issues)).sorted()
  }
}
