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
  /// The RoutePlan occurrence the matcher resolved, when it resolved one.
  public let occurrenceID: String?
  public let candidateEdgeIDs: [String]
  public let confidence: MatcherConfidence
  /// The fix as reported, and its distance from the matched edge.
  public let coordinate: MatcherCoordinate?
  public let horizontalAccuracyMeters: Double?
  public let distanceMeters: Double?
  public let headingErrorDegrees: Double?
  public let source: EntryTransitionEvidenceSource
  public let isSimulatedBySoftware: Bool

  package init(
    context: EntryTransitionAdmissionContext,
    observationID: String,
    observedAtMilliseconds: Int,
    receivedAtMilliseconds: Int,
    directedEdgeID: String?,
    occurrenceID: String? = nil,
    candidateEdgeIDs: [String],
    confidence: MatcherConfidence,
    coordinate: MatcherCoordinate? = nil,
    horizontalAccuracyMeters: Double? = nil,
    distanceMeters: Double? = nil,
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
    self.occurrenceID = occurrenceID
    self.candidateEdgeIDs = candidateEdgeIDs
    self.confidence = confidence
    self.coordinate = coordinate
    self.horizontalAccuracyMeters = horizontalAccuracyMeters
    self.distanceMeters = distanceMeters
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
    occurrenceID: String? = nil,
    candidateEdgeIDs: [String],
    confidence: MatcherConfidence,
    coordinate: MatcherCoordinate? = nil,
    horizontalAccuracyMeters: Double? = nil,
    distanceMeters: Double? = nil,
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
    self.occurrenceID = occurrenceID
    self.candidateEdgeIDs = candidateEdgeIDs
    self.confidence = confidence
    self.coordinate = coordinate
    self.horizontalAccuracyMeters = horizontalAccuracyMeters
    self.distanceMeters = distanceMeters
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
  /// The furthest RoutePlan occurrence ordered entry evidence has reached.
  public let reachedOccurrenceID: String?
  public let navigationSnapshot: NavigationSnapshot
  /// The frame of a released cue that came due on the route head before
  /// entry was confirmed, shown and not spoken; see
  /// `NavigationSession.observeEntryTransitionEvidence`.
  public let entryStretchGuidanceFrame: GuidanceFrame?

  public init(
    status: EntryTransitionAdmissionStatus,
    rejectionReason: EntryTransitionEvidenceRejectionReason? = nil,
    reachedOccurrenceID: String? = nil,
    navigationSnapshot: NavigationSnapshot,
    entryStretchGuidanceFrame: GuidanceFrame? = nil
  ) {
    self.status = status
    self.rejectionReason = rejectionReason
    self.reachedOccurrenceID = reachedOccurrenceID
    self.navigationSnapshot = navigationSnapshot
    self.entryStretchGuidanceFrame = entryStretchGuidanceFrame
  }
}

package struct EntryTransitionAdmissionDecision: Equatable, Sendable {
  package let status: EntryTransitionAdmissionStatus
  package let rejectionReason: EntryTransitionEvidenceRejectionReason?
  package let reachedOccurrenceID: String?
}

/// Admits strict-route entry from ordered route-head progression.
///
/// The release corridor contains expressway roads only, so a surface street
/// beneath or beside a ramp is invisible to the matcher: a fix there can
/// resolve to the ramp as confidently as a fix on it. Entry is therefore not
/// claimed from presence near the ramp. The evidence must progress forward
/// along the route head and must have outgrown the one surface road geometry
/// can exclude: the straight continuation of the approach. Each fix weighs
/// "on the route head" against "on that straight road" by its distance to
/// each, normalised by its reported accuracy. Only once the route has
/// separated from the approach line, and the fixes followed the route, does
/// that ratio pass the threshold. A route head that never leaves the line
/// within the evidence window cannot be told from a street under it, and
/// entry stays unconfirmed.
package struct EntryTransitionEvidenceAdmission: Sendable {
  static let maximumEvidenceAgeMilliseconds = 10_000
  static let maximumHeadingErrorDegrees = 45.0
  static let minimumProgressObservationCount = 3
  /// Natural log of the odds the route-head hypothesis must reach.
  static let entryLogLikelihoodRatio = 9.0
  static let perFixLogLikelihoodBound = 10.0
  static let minimumAccuracyMeters = 5.0
  /// A reported accuracy is a 68% radius: 1.515 standard deviations of each
  /// horizontal axis.
  static let accuracyRadiusPerSigma = 1.515
  static let routeHeadMeters = 2_000.0
  /// Fixes are compared only where the route head has left the approach line
  /// by this much. Where the two roads are closer, GPS error is correlated
  /// over many seconds and one hypothesis would drift ahead on noise alone.
  static let minimumHypothesisSeparationMeters = 20.0

  package let context: EntryTransitionAdmissionContext

  private let geometry: EntryRouteHeadGeometry
  private var lastObservationID: String?
  private var lastObservedAtMilliseconds: Int?
  private var lastReceivedAtMilliseconds: Int?
  private var progressIndex: Int?
  private var progressObservationCount = 0
  private var logLikelihoodRatio = 0.0

  /// The route-head occurrence that ordered evidence has followed the car
  /// to, once there is as much of it as entry needs: the car has been seen
  /// in order along the route head, though entry may still wait for the
  /// route to leave the straight road beyond the ramp.
  package var orderedRouteHeadOccurrenceID: String? {
    guard progressObservationCount >= Self.minimumProgressObservationCount else { return nil }
    return progressIndex.flatMap(geometry.occurrenceID(at:))
  }

  package init(context: EntryTransitionAdmissionContext) {
    self.context = context
    geometry = EntryRouteHeadGeometry(
      context: context,
      routeHeadMeters: Self.routeHeadMeters
    )
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

    // Refutations: the car is away from every corridor road, on a road the
    // plan does not use, or driving against the route.
    guard evidence.confidence != .lost else {
      return refuted(.insufficientConfidence)
    }
    if let edgeID = evidence.directedEdgeID,
      evidence.occurrenceID == nil,
      evidence.confidence != .low,
      !context.entryTransition.directedEdgeIDs.contains(edgeID)
    {
      return refuted(.unexpectedEdge)
    }
    if let headingError = evidence.headingErrorDegrees {
      guard headingError.isFinite, (0...180).contains(headingError) else {
        return refuted(.missingHeading)
      }
      guard headingError <= Self.maximumHeadingErrorDegrees else {
        return refuted(.headingMismatch)
      }
    }

    let headIndex = evidence.occurrenceID.flatMap(geometry.headIndex(of:))
    guard let headIndex, evidence.directedEdgeID == geometry.edgeID(at: headIndex)
    else {
      // Approach roads, transition edges and ambiguous fixes neither confirm
      // nor refute entry.
      return observing()
    }
    if let coordinate = evidence.coordinate,
      let accuracy = evidence.horizontalAccuracyMeters,
      accuracy.isFinite, accuracy > 0,
      let route = geometry.routeHead(nearest: coordinate),
      route.separationFromApproachLineMeters
        >= Self.minimumHypothesisSeparationMeters
    {
      let sigma = max(Self.minimumAccuracyMeters, accuracy)
        / Self.accuracyRadiusPerSigma
      let surface = geometry.approachLineDistanceMeters(to: coordinate)
      let ratio =
        (surface * surface - route.distanceMeters * route.distanceMeters)
        / (2 * sigma * sigma)
      logLikelihoodRatio += min(
        Self.perFixLogLikelihoodBound,
        max(-Self.perFixLogLikelihoodBound, ratio)
      )
    }

    let residualFits =
      evidence.distanceMeters.map { residual in
        residual
          <= max(
            Self.minimumAccuracyMeters,
            evidence.horizontalAccuracyMeters ?? Self.minimumAccuracyMeters
          )
      } ?? false
    guard evidence.confidence == .medium || evidence.confidence == .high,
      evidence.headingErrorDegrees != nil,
      residualFits
    else {
      return observing()
    }
    if let progressIndex, headIndex + 1 < progressIndex {
      return refuted(.outOfOrderEdge)
    }
    progressIndex = max(progressIndex ?? headIndex, headIndex)
    progressObservationCount += 1
    let reachedOccurrenceID = geometry.occurrenceID(at: progressIndex ?? headIndex)
    let entered =
      progressObservationCount >= Self.minimumProgressObservationCount
      && logLikelihoodRatio >= Self.entryLogLikelihoodRatio
    return EntryTransitionAdmissionDecision(
      status: entered ? .strictRouteEntered : .progressed,
      rejectionReason: nil,
      reachedOccurrenceID: reachedOccurrenceID
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

  private func observing() -> EntryTransitionAdmissionDecision {
    EntryTransitionAdmissionDecision(
      status: .observing,
      rejectionReason: nil,
      reachedOccurrenceID: progressIndex.flatMap(geometry.occurrenceID(at:))
    )
  }

  private mutating func refuted(
    _ reason: EntryTransitionEvidenceRejectionReason
  ) -> EntryTransitionAdmissionDecision {
    progressIndex = nil
    progressObservationCount = 0
    logLikelihoodRatio = 0
    return rejected(reason)
  }

  private func rejected(
    _ reason: EntryTransitionEvidenceRejectionReason
  ) -> EntryTransitionAdmissionDecision {
    EntryTransitionAdmissionDecision(
      status: .rejected,
      rejectionReason: reason,
      reachedOccurrenceID: progressIndex.flatMap(geometry.occurrenceID(at:))
    )
  }
}

/// The first `routeHeadMeters` of the RoutePlan and the straight line the
/// reviewed approach arrives along, on a local plane.
private struct EntryRouteHeadGeometry: Sendable {
  private let occurrenceIDs: [String]
  private let edgeIDs: [String]
  private let headIndexByOccurrenceID: [String: Int]
  private let polyline: [SIMD2<Double>]
  private let origin: MatcherCoordinate
  private let approachStart: SIMD2<Double>
  private let approachDirection: SIMD2<Double>

  init(context: EntryTransitionAdmissionContext, routeHeadMeters: Double) {
    let edgesByID = Dictionary(
      context.matcherCorridor.edges.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    let occurrences = context.matcherCorridor.occurrences.sorted {
      $0.index < $1.index
    }
    var occurrenceIDs: [String] = []
    var edgeIDs: [String] = []
    var coordinates: [MatcherCoordinate] = []
    var travelled = 0.0
    for occurrence in occurrences {
      guard let edge = edgesByID[occurrence.directedEdgeID] else { break }
      occurrenceIDs.append(occurrence.id)
      edgeIDs.append(edge.id)
      coordinates.append(contentsOf: coordinates.isEmpty ? edge.coordinates : Array(edge.coordinates.dropFirst()))
      travelled += edge.lengthMeters
      if travelled >= routeHeadMeters { break }
    }
    let approachEdge =
      context.entryTransition.directedEdgeIDs.first.flatMap { edgesByID[$0] }
      ?? edgeIDs.first.flatMap { edgesByID[$0] }
    let approach = approachEdge?.coordinates ?? coordinates
    let origin = approach.first ?? MatcherCoordinate(latitude: 0, longitude: 0)
    self.origin = origin
    self.occurrenceIDs = occurrenceIDs
    self.edgeIDs = edgeIDs
    headIndexByOccurrenceID = Dictionary(
      uniqueKeysWithValues: occurrenceIDs.enumerated().map { ($1, $0) }
    )
    polyline = coordinates.map { Self.project($0, origin: origin) }
    let start = Self.project(approach.first ?? origin, origin: origin)
    let end = Self.project(approach.last ?? origin, origin: origin)
    let direction = end - start
    let length = (direction * direction).sum().squareRoot()
    approachStart = start
    approachDirection = length > 0 ? direction / length : SIMD2(0, 1)
  }

  func headIndex(of occurrenceID: String) -> Int? {
    headIndexByOccurrenceID[occurrenceID]
  }

  func edgeID(at index: Int) -> String? {
    edgeIDs.indices.contains(index) ? edgeIDs[index] : nil
  }

  func occurrenceID(at index: Int) -> String? {
    occurrenceIDs.indices.contains(index) ? occurrenceIDs[index] : nil
  }

  /// The fix's distance from the route head, and how far the route head's
  /// nearest point lies from the approach line.
  func routeHead(
    nearest coordinate: MatcherCoordinate
  ) -> (distanceMeters: Double, separationFromApproachLineMeters: Double)? {
    let point = Self.project(coordinate, origin: origin)
    let nearest = zip(polyline, polyline.dropFirst()).map { start, end in
      Self.nearestPoint(point, start, end)
    }.min { lhs, rhs in
      Self.length(lhs - point) < Self.length(rhs - point)
    }
    return nearest.map {
      (Self.length($0 - point), approachLineDistanceMeters(projected: $0))
    }
  }

  /// Distance to the ray that continues the approach straight ahead.
  func approachLineDistanceMeters(to coordinate: MatcherCoordinate) -> Double {
    approachLineDistanceMeters(projected: Self.project(coordinate, origin: origin))
  }

  private func approachLineDistanceMeters(projected point: SIMD2<Double>) -> Double {
    let offset = point - approachStart
    let along = (offset * approachDirection).sum()
    guard along > 0 else { return Self.length(offset) }
    return Self.length(offset - approachDirection * along)
  }

  private static func nearestPoint(
    _ point: SIMD2<Double>,
    _ start: SIMD2<Double>,
    _ end: SIMD2<Double>
  ) -> SIMD2<Double> {
    let direction = end - start
    let squared = (direction * direction).sum()
    let fraction =
      squared > 0
      ? min(1, max(0, ((point - start) * direction).sum() / squared)) : 0
    return start + direction * fraction
  }

  private static func length(_ vector: SIMD2<Double>) -> Double {
    (vector * vector).sum().squareRoot()
  }

  private static func project(
    _ coordinate: MatcherCoordinate,
    origin: MatcherCoordinate
  ) -> SIMD2<Double> {
    let metersPerDegree = 6_371_000.0 * .pi / 180
    return SIMD2(
      (coordinate.longitude - origin.longitude) * metersPerDegree
        * cos(origin.latitude * .pi / 180),
      (coordinate.latitude - origin.latitude) * metersPerDegree
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

    let routeEdgeIDs = matcherCorridor.occurrences
      .sorted { $0.index < $1.index }
      .map(\.directedEdgeID)
    let transitionUsesRoutePrefix =
      transitionEdgeIDs.count <= routeEdgeIDs.count
      && Array(routeEdgeIDs.prefix(transitionEdgeIDs.count))
        == transitionEdgeIDs
    if !transitionUsesRoutePrefix,
      finalTransitionEdgeID != firstBinding.directedEdgeID,
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
