import Foundation
import KaidoDomain
import KaidoRouting

public struct NavigationConfiguration: Equatable, Sendable {
  public let routePlan: RoutePlan?
  public let entryTransition: EntryTransition?
  public let recoveryCandidates: [RecoveryCandidate]
  public let egressOptions: [EgressOption]
  public let nextSign: SignGuidance

  public init(
    routePlan: RoutePlan? = nil,
    entryTransition: EntryTransition? = nil,
    recoveryCandidates: [RecoveryCandidate] = [],
    egressOptions: [EgressOption] = [],
    nextSign: SignGuidance = SignGuidance()
  ) {
    self.routePlan = routePlan
    self.entryTransition = entryTransition
    self.recoveryCandidates = recoveryCandidates
    self.egressOptions = egressOptions
    self.nextSign = nextSign
  }
}

public struct NavigationEngine: Sendable {
  public private(set) var snapshot: NavigationSnapshot

  private let configuration: NavigationConfiguration
  private var isInTunnel = false
  private var entryTransitionProgress = -1

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
    synchronizeOccurrenceIndex()
  }

  public mutating func start() {
    guard let routePlan = configuration.routePlan else { return }

    snapshot.activeRoutePlanID = routePlan.id
    if snapshot.currentOccurrenceID == nil {
      snapshot.currentOccurrenceID = routePlan.occurrences.first?.id
    }
    synchronizeOccurrenceIndex()
    refreshPendingOccurrences()
  }

  public mutating func enterTunnel() {
    isInTunnel = true
  }

  public mutating func exitTunnel() {
    isInTunnel = false
  }

  public mutating func observeLocation(_ observation: LocationObservation) {
    let confidence = observation.effectiveConfidence
    snapshot.locationConfidence = confidence
    snapshot.markerStyle = confidence <= .low ? "ESTIMATED" : "MEASURED"

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

    if let occurrenceID = observation.expectedOccurrenceID
      ?? observation.matchedOccurrenceID
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

  public mutating func updateRestriction(subjectID: String, state: String) {
    guard state == "KNOWN_CLOSED",
      let routePlan = configuration.routePlan,
      let occurrence = routePlan.occurrences.first(where: {
        $0.entityID == subjectID && $0.isOptional
      })
    else {
      return
    }

    appendUnique(occurrence.id, to: &snapshot.skippedOccurrenceIDs)
    appendUnique("OPTIONAL_PA_UNAVAILABLE", to: &snapshot.routeWarnings)
    snapshot.routeExecutable = true
    refreshPendingOccurrences()
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

  private mutating func advance(to occurrenceID: String) {
    guard let routePlan = configuration.routePlan,
      let target = routePlan.occurrence(id: occurrenceID)
    else {
      return
    }
    let currentIndex = snapshot.currentOccurrenceIndex ?? -1
    guard target.index >= currentIndex else { return }

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
