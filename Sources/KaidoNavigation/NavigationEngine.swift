import Foundation
import KaidoDomain
import KaidoRouting

public struct NavigationConfiguration: Equatable, Sendable {
  public let routePlan: RoutePlan?
  public let entryTransition: EntryTransition?
  public let recoveryCandidates: [RecoveryCandidate]
  public let egressOptions: [EgressOption]
  public let selectedEgressOptionID: String?
  public let nextSign: SignGuidance
  public let guidanceAnchors: [GuidanceAnchorDefinition]
  public let releasedGuidance: [ReleasedGuidanceDefinition]
  public let allowsUserConfirmedExitHandoffCompletion: Bool
  public let signalReacquisitionMinimumObservations: Int
  public let signalReacquisitionMaximumGapMilliseconds: Int
  /// Occurrences bounding each lap of a loop route, released structure that
  /// lets the engine locate one lap ahead without being told where it is.
  public let lapBoundaryOccurrenceIDs: [String]

  public init(
    routePlan: RoutePlan? = nil,
    entryTransition: EntryTransition? = nil,
    recoveryCandidates: [RecoveryCandidate] = [],
    egressOptions: [EgressOption] = [],
    selectedEgressOptionID: String? = nil,
    nextSign: SignGuidance = SignGuidance(),
    guidanceAnchors: [GuidanceAnchorDefinition] = [],
    releasedGuidance: [ReleasedGuidanceDefinition] = [],
    allowsUserConfirmedExitHandoffCompletion: Bool = false,
    signalReacquisitionMinimumObservations: Int = 2,
    signalReacquisitionMaximumGapMilliseconds: Int = 5_000,
    lapBoundaryOccurrenceIDs: [String] = []
  ) {
    self.routePlan = routePlan
    self.entryTransition = entryTransition
    self.recoveryCandidates = recoveryCandidates
    self.egressOptions = egressOptions
    self.selectedEgressOptionID = selectedEgressOptionID
    self.nextSign = nextSign
    self.guidanceAnchors = guidanceAnchors
    self.releasedGuidance = releasedGuidance
    self.allowsUserConfirmedExitHandoffCompletion =
      allowsUserConfirmedExitHandoffCompletion
    self.signalReacquisitionMinimumObservations = max(
      2,
      signalReacquisitionMinimumObservations
    )
    self.signalReacquisitionMaximumGapMilliseconds = max(
      0,
      signalReacquisitionMaximumGapMilliseconds
    )
    self.lapBoundaryOccurrenceIDs = lapBoundaryOccurrenceIDs
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
  private let occurrencePositions: [String: Int]
  /// The plan's occurrence IDs and indexes in plan order, for the lists
  /// rebuilt on every admitted fix.
  private let occurrenceIDs: [String]
  private let occurrenceIndexes: [Int]
  private let releasedGuidanceIsValid: Bool
  /// The completed and pending lists `advance` last built, and the inputs
  /// it built them from. Most fixes stay on the same occurrence, and an
  /// array compares equal to its own unchanged copy without a scan.
  private var builtOccurrenceLists:
    (targetIndex: Int, skipped: [String], completed: [String], pending: [String])?

  public init(
    configuration: NavigationConfiguration,
    initialSnapshot: NavigationSnapshot = NavigationSnapshot()
  ) {
    self.configuration = configuration
    let positions = Dictionary(
      (configuration.routePlan?.occurrences ?? []).enumerated()
        .map { ($1.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    occurrencePositions = positions
    occurrenceIDs = (configuration.routePlan?.occurrences ?? []).map(\.id)
    occurrenceIndexes = (configuration.routePlan?.occurrences ?? []).map(\.index)
    releasedGuidanceIsValid =
      configuration.routePlan.map {
        GuidanceFramePlanner.definitionsAreValid(
          configuration.releasedGuidance, routePlan: $0, occurrencePositions: positions
        )
      } ?? false
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
    guard snapshot.journeyPhase != .completed,
      snapshot.routeExecutable,
      let routePlan = configuration.routePlan
    else { return }

    snapshot.activeRoutePlanID = routePlan.id
    if snapshot.currentOccurrenceID == nil {
      snapshot.currentOccurrenceID = routePlan.occurrences.first?.id
    }
    synchronizeOccurrenceIndex()
    refreshPendingOccurrences()
  }

  /// Keeps deterministic simulation provenance explicit after the synthetic
  /// controller exercises the same ordered entry reducer.
  package mutating func markSyntheticSimulationEntryTransition() {
    guard snapshot.journeyPhase == .strictRoute,
      snapshot.lastPhaseTransitionTrigger == "VERIFIED_ENTRY_CONTINUITY"
    else {
      return
    }
    snapshot.lastPhaseTransitionTrigger =
      "SYNTHETIC_SIMULATION_ENTRY_CONTINUITY"
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
      occurrencePositions: occurrencePositions,
      definitions: configuration.releasedGuidance,
      definitionsAreValid: releasedGuidanceIsValid,
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

  /// The frame of the cue that ordered evidence along the route head has
  /// made due while entry is still being confirmed, for the driver to see.
  /// Nothing is recorded as spoken: the strict-route cue still plays when
  /// progress reaches it.
  public func entryStretchGuidanceFrame(
    _ observation: GuidanceProgressObservation
  ) -> GuidanceFrame? {
    guard snapshot.journeyPhase == .entryTransition else { return nil }
    let result = GuidanceFramePlanner.plan(
      snapshot: snapshot,
      routePlan: configuration.routePlan,
      occurrencePositions: occurrencePositions,
      definitions: configuration.releasedGuidance,
      definitionsAreValid: releasedGuidanceIsValid,
      observation: observation,
      followsEntryEvidence: true
    )
    return result.status == .promptEmitted ? result.frame : nil
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
    guard snapshot.journeyPhase != .completed else { return }
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
      completeParkingArrival(observation)
      return
    }

    if let entityID = observation.matchedEntityID,
      let routePlan = configuration.routePlan
    {
      let currentIndex = snapshot.currentOccurrenceIndex ?? -1
      if let occurrence = routePlan.occurrence(entityID: entityID, after: currentIndex - 1) {
        advance(to: occurrence.id)
        completeParkingArrival(observation)
      }
    }
  }

  private mutating func completeParkingArrival(_ observation: LocationObservation) {
    guard snapshot.journeyPhase == .strictRoute,
      observation.candidateResolution == .resolved,
      let plan = configuration.routePlan, let parkingID = plan.destinationParkingAreaID,
      let index = snapshot.currentOccurrenceIndex,
      plan.occurrences[index...].allSatisfy({ $0.kind == .paVisit && $0.parkingAreaID == parkingID })
    else { return }
    // Arrival is inside the final PA visit, not at a particular parking bay.
    // Earlier PA visits cannot finish a route that still has road or lap edges.
    for occurrence in plan.occurrences where occurrence.index > index {
      appendUnique(occurrence.id, to: &snapshot.skippedOccurrenceIDs)
    }
    snapshot.journeyPhase = .completed
    snapshot.lastPhaseTransitionTrigger = "PARKING_AREA_DESTINATION_REACHED"
    snapshot.completedOccurrenceIDs = plan.occurrences
      .filter { $0.index <= index && !snapshot.skippedOccurrenceIDs.contains($0.id) }.map(\.id)
    snapshot.pendingOccurrenceIDs = []
    snapshot.currentOccurrenceID = nil
    snapshot.currentOccurrenceIndex = nil
    snapshot.strictRouteAutoCommitAllowed = false
    snapshot.activeGuidanceFrame = nil
    snapshot.guidancePlanningStatus = .inactive
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
        after: currentIndex,
        triggeredBy: observedMovementID
      )
    else {
      activateUnavailableRecovery(routePlan: routePlan)
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
    guard snapshot.journeyPhase != .completed,
      let routePlan = configuration.routePlan
    else { return }
    let currentIndex = snapshot.currentOccurrenceIndex ?? -1
    let eligibleOptions: [EgressOption]
    if let selectedEgressOptionID = configuration.selectedEgressOptionID {
      eligibleOptions = configuration.egressOptions.filter {
        $0.id == selectedEgressOptionID
      }
    } else {
      eligibleOptions = configuration.egressOptions
    }
    guard
      let option = EgressPlanner.choose(
        options: eligibleOptions,
        routePlan: routePlan,
        from: currentIndex
      )
    else {
      snapshot.egress = EgressState()
      snapshot.egress.status = .unavailable
      snapshot.finishConfirmationExitFacilityID = nil
      return
    }

    snapshot.egress = EgressState()
    snapshot.egress.status = .active
    snapshot.egress.exitFacilityID = option.exitFacilityID
    snapshot.egress.firstEligibleOccurrenceID = option.firstEligibleOccurrenceID
    appendUnique("U_TURN_OR_REVERSAL", to: &snapshot.egress.prohibitedActions)
    snapshot.finishConfirmationExitFacilityID = option.exitFacilityID
    snapshot.journeyPhase = .exitTransition
    snapshot.lastPhaseTransitionTrigger =
      "RELEASED_EGRESS_PLAN_ACTIVATED"
  }

  /// Marks that ordered entry evidence has begun on the route head.
  package mutating func beginEntryTransition() {
    guard snapshot.journeyPhase == .planning
      || snapshot.journeyPhase == .approachToEntry
    else { return }
    snapshot.journeyPhase = .entryTransition
    snapshot.strictRouteAutoCommitAllowed = false
  }

  /// Enters STRICT_ROUTE from verified entry evidence. The evidence may only
  /// be complete once the car has driven some way along the route head, so
  /// progress lands on the occurrence that evidence reached; everything
  /// before it was driven, not skipped.
  package mutating func enterStrictRoute(
    firstOccurrenceID: String,
    reachedOccurrenceID: String? = nil,
    trigger: String
  ) {
    guard snapshot.journeyPhase == .planning
      || snapshot.journeyPhase == .approachToEntry
      || snapshot.journeyPhase == .entryTransition
    else { return }
    snapshot.journeyPhase = .strictRoute
    snapshot.lastPhaseTransitionTrigger = trigger
    snapshot.strictRouteAutoCommitAllowed = true
    snapshot.ambiguityReason = nil
    advance(to: firstOccurrenceID)
    if let reachedOccurrenceID { advance(to: reachedOccurrenceID) }
  }

  /// Ends strict-route progress at the released exit once the car has been
  /// observed past the end of the route, also from a deviation the exit's
  /// own road read as. The occurrences between admitted progress and the
  /// terminal edge were driven to get there.
  package mutating func finishAtRouteEnd() {
    guard snapshot.journeyPhase == .strictRoute
      || snapshot.journeyPhase == .routeRecovery,
      let terminal = configuration.routePlan?.occurrences.last
    else { return }
    advance(to: terminal.id)
    finishDrive()
  }

  /// Ends a PA-terminal drive whose car went on past the entry ramp of its
  /// destination PA. Kaido cannot tell a closed PA from a missed turn, and
  /// nothing past the ramp leads back to it, so the drive ends here instead
  /// of looking for a rejoin. Everything up to the divergence was driven.
  package mutating func endPastDestinationParkingArea(
    divergenceOccurrenceID: String
  ) {
    guard snapshot.journeyPhase == .strictRoute
      || snapshot.journeyPhase == .routeRecovery,
      let routePlan = configuration.routePlan,
      routePlan.destinationParkingAreaID != nil,
      let divergence = routePlan.occurrence(id: divergenceOccurrenceID)
    else { return }
    if divergence.index > (snapshot.currentOccurrenceIndex ?? -1) {
      advance(to: divergence.id)
    }
    for occurrence in routePlan.occurrences where occurrence.index > divergence.index {
      appendUnique(occurrence.id, to: &snapshot.skippedOccurrenceIDs)
    }
    snapshot.recovery = RecoveryState()
    snapshot.journeyPhase = .completed
    snapshot.lastPhaseTransitionTrigger = "DESTINATION_PARKING_AREA_NOT_ENTERED"
    snapshot.completedOccurrenceIDs = routePlan.occurrences
      .filter {
        $0.index <= divergence.index
          && !snapshot.skippedOccurrenceIDs.contains($0.id)
      }
      .map(\.id)
    snapshot.pendingOccurrenceIDs = []
    snapshot.currentOccurrenceID = nil
    snapshot.currentOccurrenceIndex = nil
    snapshot.strictRouteAutoCommitAllowed = false
    snapshot.activeGuidanceFrame = nil
    snapshot.guidancePlanningStatus = .inactive
  }

  /// The car stayed on the road a mid-route PA stop leaves and rejoins, so
  /// the stop was not made: its occurrences are skipped rather than driven,
  /// and progress goes on where that road rejoins the plan.
  package mutating func skipParkingStop(occurrenceIDs: [String]) {
    guard snapshot.journeyPhase == .strictRoute
      || snapshot.journeyPhase == .routeRecovery
    else { return }
    for occurrenceID in occurrenceIDs {
      appendUnique(occurrenceID, to: &snapshot.skippedOccurrenceIDs)
    }
    let skipped = Set(snapshot.skippedOccurrenceIDs)
    snapshot.completedOccurrenceIDs.removeAll(where: skipped.contains)
    snapshot.activeGuidanceFrame = nil
    snapshot.guidancePlanningStatus = .inactive
    refreshPendingOccurrences()
  }

  /// The car left the expressway where the plan does not. The expressway
  /// portion ends there: it is neither a recovery back onto the plan nor a
  /// completion of it. Progress stays where it stood.
  package mutating func leaveAtUnplannedExit() {
    guard snapshot.journeyPhase == .strictRoute
      || snapshot.journeyPhase == .routeRecovery
    else { return }
    snapshot.recovery = RecoveryState()
    snapshot.egress = EgressState()
    snapshot.finishConfirmationExitFacilityID = nil
    snapshot.activeGuidanceFrame = nil
    snapshot.guidancePlanningStatus = .inactive
    snapshot.journeyPhase = .surfaceEgress
    snapshot.lastPhaseTransitionTrigger = "UNPLANNED_EXIT"
  }

  /// Joins STRICT_ROUTE at an occurrence no reviewed entry ramp proved.
  ///
  /// The driver was already on the expressway when the drive started, so the
  /// occurrences ahead of the join were never driven. They are recorded as
  /// skipped: `advance(to:)` would otherwise report them completed, which
  /// would claim passage the session has no evidence for.
  package mutating func joinStrictRoute(
    atOccurrenceID occurrenceID: String,
    trigger: String
  ) {
    guard snapshot.journeyPhase == .planning
      || snapshot.journeyPhase == .approachToEntry
      || snapshot.journeyPhase == .entryTransition,
      let routePlan = configuration.routePlan,
      let target = routePlan.occurrence(id: occurrenceID)
    else { return }
    for occurrence in routePlan.occurrences
    where occurrence.index < target.index {
      appendUnique(occurrence.id, to: &snapshot.skippedOccurrenceIDs)
    }
    snapshot.journeyPhase = .strictRoute
    snapshot.lastPhaseTransitionTrigger = trigger
    snapshot.strictRouteAutoCommitAllowed = true
    snapshot.ambiguityReason = nil
    advance(to: occurrenceID)
  }

  /// Drops one whole lap of a loop the driver chose not to complete.
  ///
  /// The target is not the caller's to name. It is the same road one lap
  /// ahead, measured against the released lap boundaries, so the App can ask
  /// for a lap to be dropped but can never ask the drive to jump somewhere
  /// the release did not describe. The dropped lap is recorded as skipped: it
  /// was not driven.
  ///
  /// Returns the occurrence the drive moved to, or `nil` when there is no
  /// whole lap left ahead to drop or the next lap does not drive the current
  /// road — as when the car is inside a PA stop only this lap makes.
  @discardableResult
  package mutating func skipOneLap(trigger: String) -> String? {
    guard let laps = lapRanges(),
      let lap = laps.firstIndex(where: { $0.contains(snapshot.currentOccurrenceIndex ?? -1) }),
      lap + 1 < laps.count
    else {
      return nil
    }
    return skip(toSameRoadIn: laps[lap + 1], from: laps[lap], trigger: trigger)
  }

  /// Retains the current partial lap and the released exit tail in one change.
  /// Intermediate lap copies are skipped, never published as visited positions.
  /// Like `skipOneLap`, it lands on the same road in the last lap and refuses
  /// when that lap does not drive it.
  @discardableResult
  package mutating func skipRemainingLaps(trigger: String) -> String? {
    guard let laps = lapRanges(),
      let lap = laps.firstIndex(where: { $0.contains(snapshot.currentOccurrenceIndex ?? -1) }),
      lap + 1 < laps.count
    else { return nil }
    return skip(toSameRoadIn: laps[laps.count - 1], from: laps[lap], trigger: trigger)
  }

  /// The occurrence ranges of the released laps, while the strict route is
  /// being driven.
  private func lapRanges() -> [Range<Int>]? {
    guard snapshot.journeyPhase == .strictRoute,
      let routePlan = configuration.routePlan
    else { return nil }
    let boundaries = configuration.lapBoundaryOccurrenceIDs.compactMap {
      routePlan.occurrence(id: $0)?.index
    }
    guard boundaries.count == configuration.lapBoundaryOccurrenceIDs.count,
      boundaries.count >= 2
    else { return nil }
    return zip(boundaries, boundaries.dropFirst()).map { $0..<$1 }
  }

  /// Moves to the occurrence in `target` that drives the current road: the
  /// same entity at the same rank among that entity's occurrences in its lap.
  /// Laps differ in length once a PA stop sits in one of them, so an index
  /// offset would land on another road.
  private mutating func skip(
    toSameRoadIn target: Range<Int>,
    from lap: Range<Int>,
    trigger: String
  ) -> String? {
    guard let routePlan = configuration.routePlan,
      let currentIndex = snapshot.currentOccurrenceIndex,
      let current = routePlan.occurrences.first(where: { $0.index == currentIndex })
    else { return nil }
    let rank = routePlan.occurrences.count {
      lap.contains($0.index) && $0.index < currentIndex && $0.entityID == current.entityID
    }
    let sameRoad = routePlan.occurrences.filter {
      target.contains($0.index) && $0.entityID == current.entityID
    }
    guard sameRoad.indices.contains(rank) else { return nil }
    let destination = sameRoad[rank]
    for occurrence in routePlan.occurrences
    where occurrence.index > currentIndex && occurrence.index < destination.index {
      appendUnique(occurrence.id, to: &snapshot.skippedOccurrenceIDs)
    }
    snapshot.lastPhaseTransitionTrigger = trigger
    advance(to: destination.id)
    return destination.id
  }

  package mutating func activateSurfaceEgress() {
    guard snapshot.journeyPhase == .exitTransition,
      snapshot.egress.status == .active
    else {
      return
    }
    snapshot.journeyPhase = .surfaceEgress
    snapshot.lastPhaseTransitionTrigger =
      "VERIFIED_SURFACE_EGRESS_HANDOFF"
  }

  /// Completes a route-only journey only after the selected released exit and
  /// the terminal RoutePlan occurrence are both current.
  ///
  /// This is an explicit user confirmation boundary. It does not infer an
  /// ordinary-road movement, activate a surface matcher, or authorize
  /// `SURFACE_EGRESS`.
  public mutating func completeAtExitHandoff() {
    guard configuration.allowsUserConfirmedExitHandoffCompletion,
      let routePlan = configuration.routePlan,
      let terminalOccurrence = routePlan.occurrences.last,
      snapshot.journeyPhase == .exitTransition,
      snapshot.egress.status == .active,
      snapshot.egress.exitFacilityID == routePlan.exitFacilityID,
      snapshot.currentOccurrenceID == terminalOccurrence.id,
      snapshot.currentOccurrenceIndex == terminalOccurrence.index
    else {
      return
    }

    snapshot.journeyPhase = .completed
    snapshot.lastPhaseTransitionTrigger =
      "USER_CONFIRMED_EXIT_HANDOFF_COMPLETED"
    snapshot.completedOccurrenceIDs = routePlan.occurrences
      .filter { !snapshot.skippedOccurrenceIDs.contains($0.id) }
      .map(\.id)
    snapshot.pendingOccurrenceIDs = []
    snapshot.currentOccurrenceID = nil
    snapshot.currentOccurrenceIndex = nil
    snapshot.strictRouteAutoCommitAllowed = false
    snapshot.activeGuidanceFrame = nil
    snapshot.guidancePlanningStatus = .inactive
  }

  private mutating func updateEntryTransition(
    with observation: LocationObservation,
    confidence: LocationConfidence
  ) {
    guard
      snapshot.journeyPhase == .planning
        || snapshot.journeyPhase == .approachToEntry
        || snapshot.journeyPhase == .entryTransition,
      let transition = configuration.entryTransition,
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
    guard confidence == .high else {
      resetSignalReacquisition(status: .pending)
      return
    }
    snapshot.locationConfidence = .low
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
    guard gap > 0 else { return }
    guard gap <= configuration.signalReacquisitionMaximumGapMilliseconds
    else {
      beginReacquisitionWindow(candidates: candidates, observedAt: observedAt)
      return
    }

    var consistentCandidates = reacquisitionCandidateOccurrenceIDs.intersection(candidates)
    // Exact adjacent occurrences are a continuous window even when short
    // road segments put consecutive fixes on different edges. Never bridge
    // a skipped movement or an ambiguous branch to complete reacquisition.
    if consistentCandidates.isEmpty,
      observation.candidateResolution == .resolved,
      candidates.count == 1,
      reacquisitionCandidateOccurrenceIDs.count == 1,
      let previousID = reacquisitionCandidateOccurrenceIDs.first,
      let currentID = candidates.first,
      let plan = configuration.routePlan,
      let previous = plan.occurrence(id: previousID),
      let current = plan.occurrence(id: currentID),
      current.index == previous.index + 1
    {
      consistentCandidates = candidates
    }
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
    snapshot.locationConfidence = .high
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
      activateUnavailableRecovery(routePlan: routePlan)
      return
    }
    activateRecovery(recovery, routePlan: routePlan)
  }

  private mutating func activateRecovery(
    _ recovery: RecoveryCandidate,
    routePlan: RoutePlan
  ) {
    snapshot.journeyPhase = .routeRecovery
    snapshot.recovery = RecoveryState()
    snapshot.recovery.status = .active
    snapshot.recovery.objective = "REJOIN_ACTIVE_ROUTE_PLAN"
    snapshot.recovery.routePlanID = routePlan.id
    snapshot.recovery.chosenRejoinOccurrenceID = recovery.targetOccurrenceID
    snapshot.recovery.destinationRerouteUsed = false
    clearEgress()
    appendUnique("ABRUPT_LANE_CHANGE_OR_REVERSAL", to: &snapshot.prohibitedGuidanceActions)
    snapshot.requiresRouteEditingWhileMoving = false
  }

  private mutating func activateUnavailableRecovery(
    routePlan: RoutePlan
  ) {
    snapshot.journeyPhase = .routeRecovery
    snapshot.recovery = RecoveryState()
    snapshot.recovery.status = .unavailable
    snapshot.recovery.objective = "REJOIN_ACTIVE_ROUTE_PLAN"
    snapshot.recovery.routePlanID = routePlan.id
    clearEgress()
    appendUnique(
      "ABRUPT_LANE_CHANGE_OR_REVERSAL",
      to: &snapshot.prohibitedGuidanceActions
    )
    snapshot.requiresRouteEditingWhileMoving = false
  }

  private mutating func clearEgress() {
    snapshot.egress = EgressState()
    snapshot.finishConfirmationExitFacilityID = nil
  }

  private mutating func advance(to occurrenceID: String) {
    guard let routePlan = configuration.routePlan,
      let target = occurrence(id: occurrenceID, in: routePlan)
    else {
      return
    }
    let currentIndex = snapshot.currentOccurrenceIndex ?? -1
    guard target.index >= currentIndex else { return }

    if snapshot.journeyPhase == .routeRecovery,
      snapshot.recovery.status == .unavailable,
      target.index > currentIndex
    {
      snapshot.journeyPhase = .strictRoute
      snapshot.recovery = RecoveryState()
      snapshot.lastPhaseTransitionTrigger =
        "EXACT_LATER_ROUTE_OCCURRENCE_REACQUIRED"
    }

    // Short occurrences are crossed between 1 Hz fixes, so the first
    // admitted position at or past the rejoin occurrence is the rejoin. An
    // admitted position on the plan before it means the car never left: the
    // deviation was not real and nothing was skipped.
    if snapshot.journeyPhase == .routeRecovery,
      snapshot.recovery.status == .active,
      let rejoin = snapshot.recovery.chosenRejoinOccurrenceID
        .flatMap({ occurrence(id: $0, in: routePlan) }),
      target.index > currentIndex
    {
      if target.index >= rejoin.index {
        for occurrence in routePlan.occurrences
        where occurrence.index > currentIndex
          && occurrence.index < rejoin.index
        {
          appendUnique(occurrence.id, to: &snapshot.skippedOccurrenceIDs)
        }
        snapshot.lastPhaseTransitionTrigger = "RELEASED_RECOVERY_REJOINED"
      } else {
        snapshot.lastPhaseTransitionTrigger = "PLANNED_ROUTE_REACQUIRED"
      }
      snapshot.journeyPhase = .strictRoute
      snapshot.recovery = RecoveryState()
    }

    if snapshot.currentOccurrenceID != target.id {
      snapshot.activeGuidanceFrame = nil
      snapshot.guidancePlanningStatus = .inactive
    }
    snapshot.currentOccurrenceID = target.id
    snapshot.currentOccurrenceIndex = target.index
    if let built = builtOccurrenceLists, built.targetIndex == target.index,
      built.skipped == snapshot.skippedOccurrenceIDs,
      built.completed == snapshot.completedOccurrenceIDs,
      built.pending == snapshot.pendingOccurrenceIDs
    {
      return
    }
    snapshot.completedOccurrenceIDs = unskippedOccurrenceIDs { $0 < target.index }
    refreshPendingOccurrences()
    builtOccurrenceLists = (
      target.index, snapshot.skippedOccurrenceIDs,
      snapshot.completedOccurrenceIDs, snapshot.pendingOccurrenceIDs
    )
  }

  /// The first occurrence with this ID, as `RoutePlan.occurrence(id:)`
  /// finds it, without searching a long plan on every fix.
  private func occurrence(id: String, in routePlan: RoutePlan) -> RouteOccurrence? {
    occurrencePositions[id].map { routePlan.occurrences[$0] }
  }

  /// IDs of the occurrences whose index passes `include`, in plan order,
  /// less the skipped ones. Runs on every admitted fix, and a dropped lap
  /// leaves hundreds of skipped occurrences.
  private func unskippedOccurrenceIDs(where include: (Int) -> Bool) -> [String] {
    let skipped = Set(snapshot.skippedOccurrenceIDs)
    var ids: [String] = []
    for position in occurrenceIDs.indices
    where include(occurrenceIndexes[position]) && !skipped.contains(occurrenceIDs[position]) {
      ids.append(occurrenceIDs[position])
    }
    return ids
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
    guard configuration.routePlan != nil else {
      snapshot.pendingOccurrenceIDs = []
      return
    }
    let currentIndex = snapshot.currentOccurrenceIndex ?? -1
    snapshot.pendingOccurrenceIDs = unskippedOccurrenceIDs { $0 >= currentIndex }
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
