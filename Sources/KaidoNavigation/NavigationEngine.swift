import Foundation
import KaidoDomain
import KaidoRouting

public struct NavigationConfiguration: Equatable, Sendable {
  public let routePlan: RoutePlan?
  public let entryTransition: EntryTransition?
  public let recoveryCandidates: [RecoveryCandidate]
  public let egressOptions: [EgressOption]
  public let nextSign: SignGuidance
  public let guidanceAnchors: [GuidanceAnchorDefinition]
  public let releasedGuidance: [ReleasedGuidanceDefinition]
  public let signalReacquisitionMinimumObservations: Int
  public let signalReacquisitionMaximumGapMilliseconds: Int

  public init(
    routePlan: RoutePlan? = nil,
    entryTransition: EntryTransition? = nil,
    recoveryCandidates: [RecoveryCandidate] = [],
    egressOptions: [EgressOption] = [],
    nextSign: SignGuidance = SignGuidance(),
    guidanceAnchors: [GuidanceAnchorDefinition] = [],
    releasedGuidance: [ReleasedGuidanceDefinition] = [],
    signalReacquisitionMinimumObservations: Int = 2,
    signalReacquisitionMaximumGapMilliseconds: Int = 5_000
  ) {
    self.routePlan = routePlan
    self.entryTransition = entryTransition
    self.recoveryCandidates = recoveryCandidates
    self.egressOptions = egressOptions
    self.nextSign = nextSign
    self.guidanceAnchors = guidanceAnchors
    self.releasedGuidance = releasedGuidance
    self.signalReacquisitionMinimumObservations = max(
      2,
      signalReacquisitionMinimumObservations
    )
    self.signalReacquisitionMaximumGapMilliseconds = max(
      0,
      signalReacquisitionMaximumGapMilliseconds
    )
  }
}

public struct NavigationEngine: Sendable {
  public private(set) var snapshot: NavigationSnapshot

  private let configuration: NavigationConfiguration
  private var isInTunnel = false
  private var tunnelSignalWasDegraded = false
  private var reacquisitionCandidateOccurrenceIDs: Set<String> = []
  private var reacquisitionObservationCount = 0
  private var lastReacquisitionObservationAtMilliseconds: Int?
  private var entryTransitionProgress = -1
  private var emittedGuidanceAnchorKeys: Set<GuidanceAnchorKey> = []

  public init(
    configuration: NavigationConfiguration,
    initialSnapshot: NavigationSnapshot = NavigationSnapshot()
  ) {
    self.configuration = configuration
    self.snapshot = initialSnapshot
    self.snapshot.activeRoutePlanID =
      configuration.routePlan?.id
      ?? initialSnapshot.activeRoutePlanID
    self.snapshot.signGuidance = configuration.nextSign
    self.emittedGuidanceAnchorKeys = Set(
      configuration.allGuidanceAnchors.compactMap { definition in
        guard self.snapshot.emittedGuidancePromptIDs.contains(definition.promptID) else {
          return nil
        }
        return GuidanceAnchorKey(
          occurrenceID: definition.occurrenceID,
          anchorID: definition.anchorID
        )
      }
    )
    synchronizeOccurrenceIndex()
  }

  public mutating func start() {
    guard snapshot.routeExecutable,
      let routePlan = configuration.routePlan
    else { return }

    snapshot.activeRoutePlanID = routePlan.id
    if snapshot.currentOccurrenceID == nil {
      snapshot.currentOccurrenceID = routePlan.occurrences.first?.id
    }
    synchronizeOccurrenceIndex()
    refreshPendingOccurrences()
  }

  public mutating func reachGuidanceAnchor(
    occurrenceID: String,
    anchorID: String
  ) {
    let matches = configuration.allGuidanceAnchors.filter {
      $0.occurrenceID == occurrenceID && $0.anchorID == anchorID
    }
    guard matches.count == 1, let definition = matches.first else {
      snapshot.guidanceAnchorStatus = matches.isEmpty ? .unknownAnchor : .invalidDefinition
      return
    }
    guard snapshot.currentOccurrenceID == occurrenceID else {
      snapshot.guidanceAnchorStatus = .notCurrentOccurrence
      return
    }

    let key = GuidanceAnchorKey(occurrenceID: occurrenceID, anchorID: anchorID)
    guard emittedGuidanceAnchorKeys.insert(key).inserted else {
      snapshot.guidanceAnchorStatus = .duplicateSuppressed
      return
    }

    snapshot.guidanceAnchorStatus = .emitted
    snapshot.emittedGuidancePromptIDs.append(definition.promptID)
    snapshot.lastGuidancePromptID = definition.promptID
  }

  @discardableResult
  public mutating func observeGuidanceProgress(
    _ observation: GuidanceProgressObservation
  ) -> GuidancePromptEmission? {
    if let lastObservedAt = snapshot.lastGuidanceProgressAtMilliseconds,
      observation.observedAtMilliseconds <= lastObservedAt
    {
      snapshot.guidancePlanningStatus = .staleObservation
      return nil
    }
    snapshot.lastGuidanceProgressAtMilliseconds = observation.observedAtMilliseconds

    let result = GuidanceFramePlanner.plan(
      snapshot: snapshot,
      routePlan: configuration.routePlan,
      definitions: configuration.releasedGuidance,
      observation: observation
    )
    snapshot.guidancePlanningStatus = result.status
    guard let frame = result.frame else { return nil }
    snapshot.activeGuidanceFrame = frame

    guard let emission = result.promptEmission else { return nil }
    let key = GuidanceAnchorKey(
      occurrenceID: emission.anchorOccurrenceID,
      anchorID: emission.anchorID
    )
    guard emittedGuidanceAnchorKeys.insert(key).inserted else {
      snapshot.guidancePlanningStatus = .frameUpdated
      return nil
    }
    snapshot.guidanceAnchorStatus = .emitted
    snapshot.emittedGuidancePromptIDs.append(emission.promptID)
    snapshot.lastGuidancePromptID = emission.promptID
    return emission
  }

  public mutating func connectCarPlay() {
    snapshot.carPlayConnectionState = .connected
    snapshot.presentationSurface = .carPlay
    snapshot.lastPresentationTransitionTrigger = "CARPLAY_CONNECTED"
  }

  public mutating func disconnectCarPlay() {
    snapshot.carPlayConnectionState = .disconnected
    snapshot.presentationSurface = .iPhone
    snapshot.lastPresentationTransitionTrigger = "CARPLAY_DISCONNECTED"
    snapshot.requiresPhoneTouchWhileMoving = false
  }

  public mutating func enterTunnel() {
    isInTunnel = true
    tunnelSignalWasDegraded = false
    resetSignalReacquisition(status: .inactive)
  }

  public mutating func exitTunnel() {
    isInTunnel = false
    guard tunnelSignalWasDegraded else { return }
    resetSignalReacquisition(status: .pending)
    snapshot.ambiguityReason = "POST_TUNNEL_REACQUISITION_PENDING"
  }

  public mutating func observeLocation(_ observation: LocationObservation) {
    let confidence = observation.effectiveConfidence
    snapshot.locationConfidence = confidence
    snapshot.markerStyle = confidence <= .low ? "ESTIMATED" : "MEASURED"
    snapshot.routeCandidateResolution = observation.candidateResolution

    if isInTunnel && confidence <= .low {
      tunnelSignalWasDegraded = true
      snapshot.ambiguityReason = "TUNNEL_POSITION_UNCERTAIN"
    }

    if isInTunnel && tunnelSignalWasDegraded && confidence == .high,
      snapshot.signalReacquisitionStatus == .inactive
    {
      resetSignalReacquisition(status: .pending)
      snapshot.ambiguityReason = "POST_TUNNEL_REACQUISITION_PENDING"
    }

    if snapshot.signalReacquisitionStatus == .pending {
      updateSignalReacquisition(with: observation, confidence: confidence)
      return
    }

    let claimedOccurrenceIDs = claimedOccurrenceIDs(from: observation)
    if observation.candidateResolution == .ambiguous {
      snapshot.markerStyle = "UNRESOLVED"
      snapshot.ambiguityReason = "MULTIPLE_OCCURRENCE_CANDIDATES"
      return
    }
    if observation.candidateResolution == .resolved,
      claimedOccurrenceIDs.count != 1
    {
      snapshot.markerStyle = "UNRESOLVED"
      snapshot.ambiguityReason = "ROUTE_CANDIDATE_EVIDENCE_INCONSISTENT"
      return
    }
    if isRouteCandidateAmbiguity(snapshot.ambiguityReason),
      observation.candidateResolution != .resolved
    {
      snapshot.markerStyle = "UNRESOLVED"
      return
    }

    if observation.insideEntryRegion,
      observation.directedEdgeID == nil,
      confidence <= .low
    {
      snapshot.strictRouteAutoCommitAllowed = false
      snapshot.ambiguityReason = "GEOFENCE_ONLY_NO_DIRECTED_RAMP_MATCH"
      snapshot.requiresPhoneTouchWhileMoving = false
      snapshot.showsEntryRouteShieldAndDirection = true
    }

    updateEntryTransition(with: observation, confidence: confidence)

    guard confidence == .high else { return }

    if observation.candidateResolution == .resolved,
      isRouteCandidateAmbiguity(snapshot.ambiguityReason)
    {
      snapshot.ambiguityReason = nil
      snapshot.markerStyle = "MEASURED"
    }

    let singletonCandidateOccurrenceID =
      claimedOccurrenceIDs.count == 1 ? claimedOccurrenceIDs.first : nil
    if let occurrenceID = observation.expectedOccurrenceID
      ?? observation.matchedOccurrenceID
      ?? singletonCandidateOccurrenceID
    {
      advance(to: occurrenceID)
      return
    }

    if let entityID = observation.matchedEntityID,
      let routePlan = configuration.routePlan
    {
      let currentIndex = snapshot.currentOccurrenceIndex ?? -1
      if let occurrence = routePlan.occurrence(entityID: entityID, after: currentIndex - 1) {
        advance(to: occurrence.id)
      }
    }
  }

  public mutating func observeBranch(_ observation: BranchObservation) {
    guard observation.confidence == .high,
      let observedMovementID = observation.observedMovementID,
      let routePlan = configuration.routePlan
    else {
      return
    }

    let currentIndex = snapshot.currentOccurrenceIndex ?? -1
    let plannedMovement = routePlan.occurrences.first {
      $0.index > currentIndex && $0.kind == .junctionMovement
    }

    if plannedMovement?.entityID == observedMovementID {
      if let plannedMovement { advance(to: plannedMovement.id) }
      return
    }

    guard
      let recovery = RecoveryPlanner.choose(
        candidates: configuration.recoveryCandidates,
        routePlan: routePlan,
        after: currentIndex
      )
    else {
      snapshot.recovery.status = .unavailable
      return
    }
    activateRecovery(recovery, routePlan: routePlan)
  }

  public mutating func updateRestriction(subjectID: String, state: String) {
    guard state == "KNOWN_CLOSED",
      let routePlan = configuration.routePlan
    else {
      return
    }

    let parkingAreaOccurrences = routePlan.occurrences.filter {
      $0.parkingAreaID == subjectID
    }
    if !parkingAreaOccurrences.isEmpty {
      if parkingAreaOccurrences.allSatisfy(\.isOptional) {
        for occurrence in parkingAreaOccurrences {
          appendUnique(occurrence.id, to: &snapshot.skippedOccurrenceIDs)
        }
        appendUnique("OPTIONAL_PA_UNAVAILABLE", to: &snapshot.routeWarnings)
        refreshPendingOccurrences()
      } else {
        let reason =
          parkingAreaOccurrences.allSatisfy { !$0.isOptional }
          ? "REQUIRED_PA_UNAVAILABLE"
          : "PA_OPTIONALITY_INCONSISTENT"
        blockRoute(occurrences: parkingAreaOccurrences, reason: reason)
      }
      return
    }

    let affectedOccurrences = routePlan.occurrences.filter {
      $0.entityID == subjectID
    }
    guard !affectedOccurrences.isEmpty else { return }
    let requiredOccurrences = affectedOccurrences.filter { !$0.isOptional }
    if requiredOccurrences.isEmpty {
      for occurrence in affectedOccurrences {
        appendUnique(occurrence.id, to: &snapshot.skippedOccurrenceIDs)
      }
      appendUnique("OPTIONAL_ROUTE_OCCURRENCE_UNAVAILABLE", to: &snapshot.routeWarnings)
      refreshPendingOccurrences()
    } else {
      blockRoute(
        occurrences: requiredOccurrences,
        reason: "REQUIRED_OCCURRENCE_CLOSED"
      )
    }
  }

  public mutating func finishDrive() {
    guard let routePlan = configuration.routePlan else { return }
    let currentIndex = snapshot.currentOccurrenceIndex ?? -1
    guard
      let option = EgressPlanner.choose(
        options: configuration.egressOptions,
        routePlan: routePlan,
        from: currentIndex
      )
    else {
      snapshot.egress.status = .unavailable
      return
    }

    snapshot.egress.status = .active
    snapshot.egress.exitFacilityID = option.exitFacilityID
    snapshot.egress.firstEligibleOccurrenceID = option.firstEligibleOccurrenceID
    appendUnique("U_TURN_OR_REVERSAL", to: &snapshot.egress.prohibitedActions)
    snapshot.finishConfirmationExitFacilityID = option.exitFacilityID
  }

  private mutating func updateEntryTransition(
    with observation: LocationObservation,
    confidence: LocationConfidence
  ) {
    guard let transition = configuration.entryTransition,
      let directedEdgeID = observation.directedEdgeID,
      let position = transition.directedEdgeIDs.firstIndex(of: directedEdgeID),
      confidence == .high,
      observation.headingMatches != false
    else {
      return
    }

    if position == 0 {
      entryTransitionProgress = 0
    } else if position == entryTransitionProgress + 1,
      observation.forwardContinuity
    {
      entryTransitionProgress = position
    } else if position > entryTransitionProgress {
      return
    }

    snapshot.journeyPhase = .entryTransition
    snapshot.strictRouteAutoCommitAllowed = false

    let isFinalTransitionEdge =
      entryTransitionProgress == transition.directedEdgeIDs.count - 1
    guard isFinalTransitionEdge,
      observation.forwardContinuity,
      let firstOccurrenceID = transition.firstRouteOccurrenceID,
      observation.reachableOccurrenceIDs.contains(firstOccurrenceID)
    else {
      return
    }

    snapshot.journeyPhase = .strictRoute
    snapshot.lastPhaseTransitionTrigger = "VERIFIED_ENTRY_CONTINUITY"
    snapshot.strictRouteAutoCommitAllowed = true
    snapshot.ambiguityReason = nil
    advance(to: firstOccurrenceID)
  }

  private mutating func updateSignalReacquisition(
    with observation: LocationObservation,
    confidence: LocationConfidence
  ) {
    guard confidence == .high else { return }
    snapshot.markerStyle = "UNRESOLVED"

    let candidates = eligibleReacquisitionCandidates(from: observation)
    guard !candidates.isEmpty,
      let observedAt = observation.observedAtMilliseconds
    else {
      return
    }

    guard let previousObservedAt = lastReacquisitionObservationAtMilliseconds else {
      beginReacquisitionWindow(candidates: candidates, observedAt: observedAt)
      return
    }

    let gap = observedAt - previousObservedAt
    guard gap >= 0,
      gap <= configuration.signalReacquisitionMaximumGapMilliseconds
    else {
      beginReacquisitionWindow(candidates: candidates, observedAt: observedAt)
      return
    }

    let consistentCandidates = reacquisitionCandidateOccurrenceIDs.intersection(candidates)
    guard !consistentCandidates.isEmpty else {
      beginReacquisitionWindow(candidates: candidates, observedAt: observedAt)
      return
    }

    reacquisitionCandidateOccurrenceIDs = consistentCandidates
    reacquisitionObservationCount += 1
    lastReacquisitionObservationAtMilliseconds = observedAt

    guard
      reacquisitionObservationCount
        >= configuration.signalReacquisitionMinimumObservations,
      consistentCandidates.count == 1,
      let occurrenceID = consistentCandidates.first
    else {
      return
    }

    advance(to: occurrenceID)
    snapshot.signalReacquisitionStatus = .confirmed
    snapshot.signalReacquisitionTrigger = "CONSISTENT_POST_TUNNEL_WINDOW"
    snapshot.ambiguityReason = nil
    snapshot.markerStyle = "MEASURED"
    tunnelSignalWasDegraded = false
    reacquisitionCandidateOccurrenceIDs = []
    reacquisitionObservationCount = 0
    lastReacquisitionObservationAtMilliseconds = nil
  }

  private func eligibleReacquisitionCandidates(
    from observation: LocationObservation
  ) -> Set<String> {
    guard let routePlan = configuration.routePlan else { return [] }
    var candidateIDs = observation.candidateOccurrenceIDs
    if let expectedOccurrenceID = observation.expectedOccurrenceID {
      candidateIDs.insert(expectedOccurrenceID)
    }
    if let matchedOccurrenceID = observation.matchedOccurrenceID {
      candidateIDs.insert(matchedOccurrenceID)
    }
    let currentIndex = snapshot.currentOccurrenceIndex ?? -1
    return Set(
      candidateIDs.filter { occurrenceID in
        routePlan.occurrence(id: occurrenceID).map { $0.index >= currentIndex } ?? false
      })
  }

  private func claimedOccurrenceIDs(
    from observation: LocationObservation
  ) -> Set<String> {
    var candidateIDs = observation.candidateOccurrenceIDs
    if let expectedOccurrenceID = observation.expectedOccurrenceID {
      candidateIDs.insert(expectedOccurrenceID)
    }
    if let matchedOccurrenceID = observation.matchedOccurrenceID {
      candidateIDs.insert(matchedOccurrenceID)
    }
    return candidateIDs
  }

  private func isRouteCandidateAmbiguity(_ reason: String?) -> Bool {
    reason == "MULTIPLE_OCCURRENCE_CANDIDATES"
      || reason == "ROUTE_CANDIDATE_EVIDENCE_INCONSISTENT"
  }

  private mutating func beginReacquisitionWindow(
    candidates: Set<String>,
    observedAt: Int
  ) {
    reacquisitionCandidateOccurrenceIDs = candidates
    reacquisitionObservationCount = 1
    lastReacquisitionObservationAtMilliseconds = observedAt
  }

  private mutating func resetSignalReacquisition(
    status: SignalReacquisitionStatus
  ) {
    snapshot.signalReacquisitionStatus = status
    snapshot.signalReacquisitionTrigger = nil
    reacquisitionCandidateOccurrenceIDs = []
    reacquisitionObservationCount = 0
    lastReacquisitionObservationAtMilliseconds = nil
  }

  private mutating func blockRoute(
    occurrences: [RouteOccurrence],
    reason: String
  ) {
    snapshot.routeExecutable = false
    appendUnique(reason, to: &snapshot.routeBlockingReasons)
    for occurrence in occurrences {
      appendUnique(occurrence.id, to: &snapshot.routeBlockingOccurrenceIDs)
    }
    activateRestrictionRecoveryIfDriving()
  }

  private mutating func activateRestrictionRecoveryIfDriving() {
    guard snapshot.journeyPhase == .strictRoute || snapshot.journeyPhase == .routeRecovery,
      let routePlan = configuration.routePlan
    else { return }
    let currentIndex = snapshot.currentOccurrenceIndex ?? -1
    let blockedIndex =
      snapshot.routeBlockingOccurrenceIDs.compactMap {
        routePlan.occurrence(id: $0)?.index
      }.max() ?? currentIndex
    let avoidThroughIndex = max(currentIndex, blockedIndex)
    guard
      let recovery = RecoveryPlanner.choose(
        candidates: configuration.recoveryCandidates,
        routePlan: routePlan,
        after: avoidThroughIndex
      )
    else {
      snapshot.journeyPhase = .routeRecovery
      snapshot.recovery.status = .unavailable
      snapshot.recovery.objective = "REJOIN_ACTIVE_ROUTE_PLAN"
      snapshot.recovery.routePlanID = routePlan.id
      snapshot.recovery.destinationRerouteUsed = false
      snapshot.egress.status = .inactive
      appendUnique(
        "ABRUPT_LANE_CHANGE_OR_REVERSAL",
        to: &snapshot.prohibitedGuidanceActions
      )
      snapshot.requiresRouteEditingWhileMoving = false
      return
    }
    activateRecovery(recovery, routePlan: routePlan)
  }

  private mutating func activateRecovery(
    _ recovery: RecoveryCandidate,
    routePlan: RoutePlan
  ) {
    snapshot.journeyPhase = .routeRecovery
    snapshot.recovery.status = .active
    snapshot.recovery.objective = "REJOIN_ACTIVE_ROUTE_PLAN"
    snapshot.recovery.routePlanID = routePlan.id
    snapshot.recovery.chosenRejoinOccurrenceID = recovery.targetOccurrenceID
    snapshot.recovery.destinationRerouteUsed = false
    snapshot.egress.status = .inactive
    appendUnique("ABRUPT_LANE_CHANGE_OR_REVERSAL", to: &snapshot.prohibitedGuidanceActions)
    snapshot.requiresRouteEditingWhileMoving = false
  }

  private mutating func advance(to occurrenceID: String) {
    guard let routePlan = configuration.routePlan,
      let target = routePlan.occurrence(id: occurrenceID)
    else {
      return
    }
    let currentIndex = snapshot.currentOccurrenceIndex ?? -1
    guard target.index >= currentIndex else { return }

    if snapshot.currentOccurrenceID != target.id {
      snapshot.activeGuidanceFrame = nil
      snapshot.guidancePlanningStatus = .inactive
    }
    snapshot.currentOccurrenceID = target.id
    snapshot.currentOccurrenceIndex = target.index
    snapshot.completedOccurrenceIDs = routePlan.occurrences
      .filter { $0.index < target.index && !snapshot.skippedOccurrenceIDs.contains($0.id) }
      .map(\.id)
    refreshPendingOccurrences()
  }

  private mutating func synchronizeOccurrenceIndex() {
    guard let routePlan = configuration.routePlan,
      let currentOccurrenceID = snapshot.currentOccurrenceID,
      let occurrence = routePlan.occurrence(id: currentOccurrenceID)
    else {
      snapshot.currentOccurrenceIndex = nil
      return
    }
    snapshot.currentOccurrenceIndex = occurrence.index
  }

  private mutating func refreshPendingOccurrences() {
    guard let routePlan = configuration.routePlan else {
      snapshot.pendingOccurrenceIDs = []
      return
    }
    let currentIndex = snapshot.currentOccurrenceIndex ?? -1
    snapshot.pendingOccurrenceIDs = routePlan.occurrences
      .filter { occurrence in
        occurrence.index >= currentIndex
          && !snapshot.skippedOccurrenceIDs.contains(occurrence.id)
      }
      .map(\.id)
  }

  private func appendUnique(_ value: String, to array: inout [String]) {
    if !array.contains(value) { array.append(value) }
  }
}

extension NavigationConfiguration {
  fileprivate var allGuidanceAnchors: [GuidanceAnchorDefinition] {
    guidanceAnchors + releasedGuidance.map(\.anchor)
  }
}

private struct GuidanceAnchorKey: Hashable, Sendable {
  let occurrenceID: String
  let anchorID: String
}
