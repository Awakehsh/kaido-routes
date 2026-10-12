import Foundation
import KaidoDomain
import KaidoRouting

public enum NavigationSessionConfigurationError: Error, Equatable, Sendable {
  case invalid([String])
}

public enum NavigationSessionGuidanceProgressState: String, Equatable, Sendable {
  case notApplicable = "NOT_APPLICABLE"
  case insufficientMatcherEvidence = "INSUFFICIENT_MATCHER_EVIDENCE"
  case resolved = "RESOLVED"
  case blocked = "BLOCKED"
}

public struct NavigationSessionUpdate: Equatable, Sendable {
  public let matcherEstimate: MatcherEstimate
  public let matcherDiagnostics: RouteMatcherSessionDiagnostics
  public let navigationSnapshot: NavigationSnapshot
  public let guidanceProgressState: NavigationSessionGuidanceProgressState
  public let guidanceProgressObservation: GuidanceProgressObservation?
  public let guidancePromptEmission: GuidancePromptEmission?
  public let guidanceBridgeError: GuidanceProgressBridgeError?

  public init(
    matcherEstimate: MatcherEstimate,
    matcherDiagnostics: RouteMatcherSessionDiagnostics,
    navigationSnapshot: NavigationSnapshot,
    guidanceProgressState: NavigationSessionGuidanceProgressState,
    guidanceProgressObservation: GuidanceProgressObservation? = nil,
    guidancePromptEmission: GuidancePromptEmission? = nil,
    guidanceBridgeError: GuidanceProgressBridgeError? = nil
  ) {
    self.matcherEstimate = matcherEstimate
    self.matcherDiagnostics = matcherDiagnostics
    self.navigationSnapshot = navigationSnapshot
    self.guidanceProgressState = guidanceProgressState
    self.guidanceProgressObservation = guidanceProgressObservation
    self.guidancePromptEmission = guidancePromptEmission
    self.guidanceBridgeError = guidanceBridgeError
  }

  /// The confidence the session admitted for this fix, after promotion and
  /// separation from off-plan roads. Presentation reads this, never the raw
  /// matcher value: only an admitted fix moves route progress or guidance.
  public var admittedConfidence: LocationConfidence {
    navigationSnapshot.locationConfidence
  }
}

/// Serializes the live matcher and navigation reducer for one compiled RoutePlan.
/// Apple adapters submit typed observations; they do not reproduce progress policy.
public actor NavigationSession {
  private var engine: NavigationEngine
  private var matcherSession: RouteMatcherSession
  private var entryTransitionAdmission: EntryTransitionEvidenceAdmission?
  private var routeJoinAdmission: RouteJoinAdmission?
  private var surfaceEgressAdmission: SurfaceEgressHandoffEvidenceAdmission?
  private let routePlan: RoutePlan
  private let matcherCorridor: RouteMatcherCorridor
  private let configuredEntryTransition: EntryTransition?
  private let configuredRoutePlan: RoutePlan?
  private let configuredLapBoundaryOccurrenceIDs: [String]
  private let releasedRecoveryCandidates: [RecoveryCandidate]
  private let guidanceTargetByAnchorOccurrence: [String: DecisionZoneProgressDefinition]
  private var requiresRestorationReacquisition: Bool
  private let routeEdgeIDs: Set<String>
  private let routeEdgeIDByIndex: [Int: String]
  private let occurrenceIndexesByEdgeID: [String: [Int]]
  private let occurrenceIndexByID: [String: Int]
  private let corridorPredecessorEdgeIDs: [String: [String]]
  private let routeEnd: RouteEndGeometry?
  private var offPlanRun: (count: Int, lastObservedAtMilliseconds: Int, edgeID: String)?
  private var exitEvidenceCount = 0
  private var lastMatchedOccurrenceIndex: Int?

  package init(
    navigationConfiguration: NavigationConfiguration,
    matcherCorridor: RouteMatcherCorridor,
    decisionZones: [DecisionZoneProgressDefinition],
    initialNavigationSnapshot: NavigationSnapshot = NavigationSnapshot(),
    matcherConfiguration: RouteAwareSwiftMatcherConfiguration = .init(),
    matcherSessionConfiguration: RouteMatcherSessionConfiguration = .init(),
    initialMatcherOccurrenceID: String? = nil,
    entryTransitionAdmissionContext: EntryTransitionAdmissionContext? = nil,
    surfaceEgressAdmissionContext: SurfaceEgressAdmissionContext? = nil,
    requiresRestorationReacquisition: Bool = false
  ) throws {
    guard let routePlan = navigationConfiguration.routePlan else {
      throw NavigationSessionConfigurationError.invalid(["route plan is missing"])
    }
    let issues = NavigationRuntimeConfigurationValidator.issues(
      routePlan: routePlan,
      matcherCorridor: matcherCorridor,
      decisionZones: decisionZones,
      releasedGuidance: navigationConfiguration.releasedGuidance,
      recoveryCandidates: navigationConfiguration.recoveryCandidates
    )
    var allIssues = issues
    if let transition = navigationConfiguration.entryTransition {
      allIssues.append(
        contentsOf: EntryTransitionCorridorValidator.issues(
          transition: transition,
          routePlan: routePlan,
          matcherCorridor: matcherCorridor
        )
      )
    }
    if let context = entryTransitionAdmissionContext {
      if context.networkSnapshotID != routePlan.networkSnapshotID
        || context.routePlanID != routePlan.id
        || context.matcherCorridorID != matcherCorridor.id
        || context.matcherCorridor != matcherCorridor
        || context.entryTransition != navigationConfiguration.entryTransition
      {
        allIssues.append("entry transition admission identity does not match runtime")
      }
      if context.productReleaseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || context.navigationReleaseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || context.runtimePolicyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        allIssues.append("entry transition admission release identity is invalid")
      }
      let firstRouteDirectedEdgeID = matcherCorridor.occurrences.first(where: {
        $0.id == routePlan.occurrences.first?.id
      })?.directedEdgeID
      if context.firstRouteDirectedEdgeID != firstRouteDirectedEdgeID {
        allIssues.append("entry transition first RoutePlan edge binding does not match")
      }
    }
    if let context = surfaceEgressAdmissionContext {
      if context.networkSnapshotID != routePlan.networkSnapshotID
        || context.routePlanID != routePlan.id
        || context.egressOptionID
          != navigationConfiguration.selectedEgressOptionID
        || context.matcherCorridorID != context.matcherCorridor.id
        || context.matcherCorridor.networkSnapshotID
          != routePlan.networkSnapshotID
        || context.matcherCorridor.routePlanID != routePlan.id
        || context.matcherCorridor.egressOptionID
          != context.egressOptionID
        || context.matcherCorridor.exitFacilityID
          != context.exitFacilityID
      {
        allIssues.append(
          "surface egress admission identity does not match runtime"
        )
      }
      let selectedOption = navigationConfiguration.egressOptions.first(
        where: { $0.id == context.egressOptionID }
      )
      if selectedOption?.exitFacilityID != context.exitFacilityID
        || selectedOption?.isReleased != true
      {
        allIssues.append(
          "surface egress admission option is not released"
        )
      }
      if [
        context.productReleaseID,
        context.navigationReleaseID,
        context.journeyPlanID,
        context.runtimePolicyID,
        context.handoffAnchorID,
        context.directedSurfaceEdgeID,
        context.matcherCorridorID,
        context.handoffOccurrenceID,
      ].contains(where: {
        $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }) {
        allIssues.append(
          "surface egress admission release identity is invalid"
        )
      }
      if !context.matcherCorridor.validationIssues.isEmpty
        || context.matcherCorridor.occurrences.first?.id
          != context.handoffOccurrenceID
        || context.matcherCorridor.occurrences.first?.index != 0
        || context.matcherCorridor.occurrences.first?.directedEdgeID
          != context.directedSurfaceEdgeID
      {
        allIssues.append(
          "surface egress handoff occurrence does not match runtime"
        )
      }
    }
    allIssues = Array(Set(allIssues)).sorted()
    guard allIssues.isEmpty else {
      throw NavigationSessionConfigurationError.invalid(allIssues)
    }

    self.routePlan = routePlan
    self.matcherCorridor = matcherCorridor
    configuredEntryTransition = navigationConfiguration.entryTransition
    configuredRoutePlan = navigationConfiguration.routePlan
    configuredLapBoundaryOccurrenceIDs =
      navigationConfiguration.lapBoundaryOccurrenceIDs
    releasedRecoveryCandidates = navigationConfiguration.recoveryCandidates
    guidanceTargetByAnchorOccurrence = Self.guidanceTargets(
      routePlan: routePlan,
      decisionZones: decisionZones,
      releasedGuidance: navigationConfiguration.releasedGuidance
    )
    engine = NavigationEngine(
      configuration: navigationConfiguration,
      initialSnapshot: initialNavigationSnapshot
    )
    entryTransitionAdmission = entryTransitionAdmissionContext.map {
      EntryTransitionEvidenceAdmission(context: $0)
    }
    routeJoinAdmission = entryTransitionAdmissionContext.map {
      RouteJoinAdmission(context: $0, routePlan: routePlan)
    }
    surfaceEgressAdmission = surfaceEgressAdmissionContext.map {
      SurfaceEgressHandoffEvidenceAdmission(context: $0)
    }
    matcherSession = try RouteAwareSwiftMatcher(
      configuration: matcherConfiguration
    ).makeSession(
      corridor: matcherCorridor,
      sessionConfiguration: matcherSessionConfiguration,
      initialOccurrenceID: initialMatcherOccurrenceID
    )
    self.requiresRestorationReacquisition =
      requiresRestorationReacquisition
    routeEdgeIDs = Set(matcherCorridor.occurrences.map(\.directedEdgeID))
    routeEdgeIDByIndex = Dictionary(
      matcherCorridor.occurrences.map { ($0.index, $0.directedEdgeID) },
      uniquingKeysWith: { first, _ in first }
    )
    occurrenceIndexByID = Dictionary(
      matcherCorridor.occurrences.map { ($0.id, $0.index) },
      uniquingKeysWith: { first, _ in first }
    )
    occurrenceIndexesByEdgeID = Dictionary(
      grouping: matcherCorridor.occurrences,
      by: \.directedEdgeID
    ).mapValues { $0.map(\.index).sorted() }
    var predecessors: [String: [String]] = [:]
    for edge in matcherCorridor.edges {
      for successor in edge.successorEdgeIDs {
        predecessors[successor, default: []].append(edge.id)
      }
    }
    corridorPredecessorEdgeIDs = predecessors
    routeEnd =
      routePlan.destinationParkingAreaID == nil
      ? RouteEndGeometry(routePlan: routePlan, corridor: matcherCorridor)
      : nil
  }

  public var snapshot: NavigationSnapshot {
    engine.snapshot
  }

  @discardableResult
  public func start() -> NavigationSnapshot {
    engine.start()
    return engine.snapshot
  }

  public func observe(
    _ observation: RouteMatcherObservation
  ) throws -> NavigationSessionUpdate {
    let matched = try matcherSession.observeWithContext(observation)
    let estimate = matched.estimate
    let separatedFromOffPlanRoads = matched.competingOffPlanEdgeIDs.isEmpty
    let admitsOccurrenceProgress =
      engine.snapshot.journeyPhase == .strictRoute
      || engine.snapshot.journeyPhase == .routeRecovery
      || engine.snapshot.journeyPhase == .exitTransition
      || engine.snapshot.journeyPhase == .surfaceEgress
    let detectsOffPlanDeviation =
      engine.snapshot.journeyPhase == .strictRoute
      || engine.snapshot.journeyPhase == .routeRecovery
    let admitsMediumConfidenceProgress =
      engine.snapshot.journeyPhase == .strictRoute
      || engine.snapshot.journeyPhase == .routeRecovery
    let resolvesLongitudinalCandidates =
      longitudinalCandidatesAreResolved(in: estimate)

    if requiresRestorationReacquisition {
      engine.observeLocation(
        Self.locationObservation(
          from: estimate,
          source: observation,
          admitsOccurrenceProgress: admitsOccurrenceProgress,
          admitsMediumConfidence: resolvesLongitudinalCandidates,
          resolvesLongitudinalCandidates: resolvesLongitudinalCandidates,
          separatedFromOffPlanRoads: separatedFromOffPlanRoads
        )
      )
      if engine.snapshot.signalReacquisitionStatus == .confirmed {
        requiresRestorationReacquisition = false
      }
      return update(
        estimate: Self.restorationEstimate(from: estimate),
        guidanceProgressState: .insufficientMatcherEvidence
      )
    }

    let wasRecovering = engine.snapshot.journeyPhase == .routeRecovery
    let returnOccurrenceID = wasRecovering ? earliestReturnOccurrenceID(for: estimate) : nil
    engine.observeLocation(
      Self.locationObservation(
        from: returnOccurrenceID.map { estimate.replacingOccurrenceID($0) } ?? estimate,
        source: observation,
        admitsOccurrenceProgress: admitsOccurrenceProgress,
        admitsMediumConfidence: admitsMediumConfidenceProgress,
        resolvesLongitudinalCandidates: resolvesLongitudinalCandidates,
        separatedFromOffPlanRoads: separatedFromOffPlanRoads
      )
    )
    if wasRecovering, engine.snapshot.journeyPhase == .strictRoute,
      let returnOccurrenceID
    {
      try matcherSession.restart(at: returnOccurrenceID)
    }
    if engine.snapshot.signalReacquisitionStatus == .pending {
      return update(
        estimate: Self.restorationEstimate(from: estimate),
        guidanceProgressState: .insufficientMatcherEvidence
      )
    }
    let continuesPastRouteEnd =
      estimate.occurrenceID == nil
      && estimate.confidence != .lost
      && estimate.directedEdgeID.map(continuesPastRouteEnd) == true
    if engine.snapshot.journeyPhase == .strictRoute {
      observeRouteEnd(
        estimate: estimate,
        continuesPastRouteEnd: continuesPastRouteEnd,
        observation: observation
      )
    }
    if detectsOffPlanDeviation,
      engine.snapshot.journeyPhase == .strictRoute
        || engine.snapshot.journeyPhase == .routeRecovery,
      !continuesPastRouteEnd
    {
      observeOffPlanEvidence(
        estimate: estimate,
        isOnReachableOffPlanEdge: matched.isOnReachableOffPlanEdge,
        observation: observation
      )
    }

    guard admitsOccurrenceProgress else {
      return update(
        estimate: estimate,
        guidanceProgressState: .notApplicable
      )
    }

    let anchorOccurrenceID = estimate.occurrenceID ?? engine.snapshot.currentOccurrenceID
    guard let anchorOccurrenceID,
      let decisionZone = guidanceTargetByAnchorOccurrence[anchorOccurrenceID]
    else {
      return update(
        estimate: estimate,
        guidanceProgressState: .notApplicable
      )
    }

    do {
      let progress = try GuidanceProgressBridge.resolve(
        estimate: estimate,
        routePlan: routePlan,
        corridor: matcherCorridor,
        decisionZone: decisionZone,
        skippedOccurrenceIDs: Set(engine.snapshot.skippedOccurrenceIDs)
      )
      let emission = engine.observeGuidanceProgress(progress)
      return update(
        estimate: estimate,
        guidanceProgressState: .resolved,
        guidanceProgressObservation: progress,
        guidancePromptEmission: emission
      )
    } catch let error as GuidanceProgressBridgeError {
      let state: NavigationSessionGuidanceProgressState =
        error == .insufficientMatcherEvidence
        ? .insufficientMatcherEvidence
        : .blocked
      return update(
        estimate: estimate,
        guidanceProgressState: state,
        guidanceBridgeError: error
      )
    }
  }

  /// Fixes that place the car on an off-plan road with no RoutePlan edge
  /// among the candidates. One such fix can be a reflection beside a
  /// viaduct; consecutive ones mean the car took a road the plan did not.
  static let offPlanDeviationObservationCount = 2
  static let offPlanDeviationMaximumGapMilliseconds = 3_000

  private func observeOffPlanEvidence(
    estimate: MatcherEstimate,
    isOnReachableOffPlanEdge: Bool,
    observation: RouteMatcherObservation
  ) {
    guard observation.horizontalAccuracyMeters < Self.coarseFixAccuracyMeters
    else { return }
    let continues = offPlanRun.map {
      observation.observedAtMilliseconds - $0.lastObservedAtMilliseconds
        <= Self.offPlanDeviationMaximumGapMilliseconds
    } ?? false
    let edgeID: String
    if estimate.confidence == .lost {
      // Beyond every corridor road: a run already on a branch has left the
      // corridor along it. Without that run it proves nothing.
      guard continues, let lastEdgeID = offPlanRun?.edgeID else {
        offPlanRun = nil
        return
      }
      edgeID = lastEdgeID
    } else if estimate.occurrenceID == nil,
      estimate.directedEdgeID == nil,
      !estimate.candidateEdgeIDs.contains(where: routeEdgeIDs.contains)
    {
      // Two segments of the same off-plan road equally near the fix.
      return
    } else {
      // The fix must sit on the off-plan road within the error its accuracy
      // allows; a fix merely nearer to it than to the plan is not evidence.
      guard isOnReachableOffPlanEdge,
        let distance = estimate.distanceMeters,
        distance <= 2 * max(5, observation.horizontalAccuracyMeters),
        let directedEdgeID = estimate.directedEdgeID,
        !estimate.candidateEdgeIDs.contains(where: routeEdgeIDs.contains),
        !isOnActiveRecoveryPath(directedEdgeID)
      else {
        offPlanRun = nil
        return
      }
      edgeID = directedEdgeID
    }
    let count = continues ? (offPlanRun?.count ?? 0) + 1 : 1
    offPlanRun = (count, observation.observedAtMilliseconds, edgeID)
    guard count >= Self.offPlanDeviationObservationCount else { return }
    offPlanRun = nil
    engine.observeBranch(
      BranchObservation(
        observedMovementID:
          uniquelyReleasedRecoveryTrigger(containing: edgeID)
          ?? branchRootEdgeID(of: edgeID)
          ?? edgeID,
        confidence: .high
      )
    )
  }

  /// The earliest occurrence of the matched edge after current progress. Off
  /// the plan, the matcher can return to any traversal of a repeated road;
  /// the car can only be at the next one it has not yet driven.
  private func earliestReturnOccurrenceID(for estimate: MatcherEstimate) -> String? {
    guard let edgeID = estimate.directedEdgeID,
      let occurrenceID = estimate.occurrenceID,
      let matched = routePlan.occurrence(id: occurrenceID),
      let currentIndex = engine.snapshot.currentOccurrenceIndex,
      let earliest = occurrenceIndexesByEdgeID[edgeID]?.first(where: {
        $0 > currentIndex
      }),
      earliest < matched.index
    else { return nil }
    return routePlan.occurrences.first { $0.index == earliest }?.id
  }

  /// Whether an off-plan edge is reached only through the route's terminal
  /// edge: the exit's own continuation past the end of the plan.
  private func continuesPastRouteEnd(_ directedEdgeID: String) -> Bool {
    guard let terminalEdgeID = routeEdgeIDByIndex[routePlan.occurrences.count - 1],
      occurrenceIndexesByEdgeID[terminalEdgeID]?.count == 1,
      let root = branchRootEdgeID(of: directedEdgeID)
    else { return false }
    return (corridorPredecessorEdgeIDs[root] ?? []).filter(routeEdgeIDs.contains)
      == [terminalEdgeID]
  }

  /// The first off-plan edge of the branch an observed off-plan edge belongs
  /// to: the edge recovery candidates name as their trigger.
  private func branchRootEdgeID(of directedEdgeID: String) -> String? {
    var current = directedEdgeID
    var visited: Set<String> = [current]
    while true {
      let predecessors = corridorPredecessorEdgeIDs[current] ?? []
      if predecessors.contains(where: routeEdgeIDs.contains) {
        return current
      }
      guard predecessors.count == 1, let previous = predecessors.first,
        visited.insert(previous).inserted
      else {
        return nil
      }
      current = previous
    }
  }

  /// Fixes beyond the end of the route's last edge, once admitted progress is
  /// in the exit tail. A 15 m terminal edge is crossed between two 1 Hz
  /// fixes, so the exit is recognised by where the car went, not by one
  /// exact match on that edge.
  static let exitEvidenceObservationCount = 2
  static let coarseFixAccuracyMeters = 30.0

  private func observeRouteEnd(
    estimate: MatcherEstimate,
    continuesPastRouteEnd: Bool,
    observation: RouteMatcherObservation
  ) {
    if estimate.confidence != .lost,
      let index = estimate.occurrenceID.flatMap({ occurrenceIndexByID[$0] })
    {
      lastMatchedOccurrenceIndex = index
    }
    guard let routeEnd,
      let currentIndex = engine.snapshot.currentOccurrenceIndex
    else { return }
    // Parallel exit ramps can withhold admitted progress for the whole
    // tail; the matcher's own placement there is enough to look for the car
    // having driven past the end.
    let isInTail =
      max(currentIndex, lastMatchedOccurrenceIndex ?? currentIndex)
      >= routeEnd.tailStartIndex
    guard isInTail || continuesPastRouteEnd else { return }
    if engine.snapshot.locationConfidence == .high,
      estimate.occurrenceID != nil
    {
      exitEvidenceCount = 0
      return
    }
    // A road reachable only through the terminal edge proves the car drove
    // it, however far admitted progress lags behind.
    guard observation.horizontalAccuracyMeters < Self.coarseFixAccuracyMeters,
      continuesPastRouteEnd
        || routeEnd.isBeyondEnd(
          observation.coordinate,
          matcherLost: estimate.confidence == .lost
        )
    else { return }
    exitEvidenceCount += 1
    guard exitEvidenceCount >= Self.exitEvidenceObservationCount else { return }
    exitEvidenceCount = 0
    engine.finishAtRouteEnd()
  }

  private func isOnActiveRecoveryPath(_ directedEdgeID: String) -> Bool {
    guard engine.snapshot.journeyPhase == .routeRecovery,
      engine.snapshot.recovery.status == .active,
      let targetOccurrenceID =
        engine.snapshot.recovery.chosenRejoinOccurrenceID
    else {
      return false
    }
    return releasedRecoveryCandidates.contains {
      $0.isReleased
        && $0.targetOccurrenceID == targetOccurrenceID
        && $0.recoveryOccurrenceIDs.contains(directedEdgeID)
    }
  }

  private func uniquelyReleasedRecoveryTrigger(
    containing directedEdgeID: String
  ) -> String? {
    guard engine.snapshot.journeyPhase == .strictRoute,
      let currentIndex = engine.snapshot.currentOccurrenceIndex
    else {
      return nil
    }
    let matchingCandidates =
      releasedRecoveryCandidates.filter { candidate in
        guard candidate.isReleased,
          candidate.staysInAllowedTollDomain,
          candidate.recoveryOccurrenceIDs.contains(directedEdgeID),
          let divergence = routePlan.occurrence(
            id: candidate.divergenceOccurrenceID
          ),
          let target = routePlan.occurrence(id: candidate.targetOccurrenceID),
          divergence.index >= currentIndex,
          target.index > currentIndex
        else {
          return false
        }
        return true
      }
    guard matchingCandidates.count == 1 else { return nil }
    return matchingCandidates[0].triggerDirectedEdgeID
  }

  /// Exercises ordered entry continuity for the deterministic simulator only.
  ///
  /// The method is package-scoped, accepts no release evidence, and cannot be
  /// called by the App or an Apple location adapter. Its snapshot remains
  /// explicitly synthetic and grants no navigation or road authority.
  package func observeSyntheticSimulationEntryTransition(
    _ observation: RouteMatcherObservation
  ) throws -> NavigationSessionUpdate {
    let estimate = try matcherSession.observe(observation)
    let eligiblePhase =
      engine.snapshot.journeyPhase == .planning
      || engine.snapshot.journeyPhase == .approachToEntry
      || engine.snapshot.journeyPhase == .entryTransition
    guard eligiblePhase, let transition = configuredEntryTransition else {
      return update(
        estimate: estimate,
        guidanceProgressState: .notApplicable
      )
    }

    guard estimate.confidence == .high,
      let directedEdgeID = estimate.directedEdgeID,
      estimate.candidateEdgeIDs == [directedEdgeID],
      transition.directedEdgeIDs.contains(directedEdgeID),
      observation.courseDegrees != nil
    else {
      engine.observeLocation(
        Self.locationObservation(
          from: estimate,
          source: observation,
          admitsOccurrenceProgress: false,
          admitsMediumConfidence: false,
          resolvesLongitudinalCandidates: false
        )
      )
      return update(
        estimate: estimate,
        guidanceProgressState: .insufficientMatcherEvidence
      )
    }

    let previousPhase = engine.snapshot.journeyPhase
    let isFinalTransitionEdge =
      directedEdgeID == transition.directedEdgeIDs.last
    engine.observeLocation(
      LocationObservation(
        directedEdgeID: directedEdgeID,
        observedAtMilliseconds: observation.observedAtMilliseconds,
        reportedConfidence: .high,
        horizontalAccuracyMeters:
          observation.horizontalAccuracyMeters,
        ageMilliseconds:
          observation.receivedAtMilliseconds
          - observation.observedAtMilliseconds,
        headingMatches: true,
        forwardContinuity: true,
        reachableOccurrenceIDs:
          isFinalTransitionEdge
          ? Set(
            [transition.firstRouteOccurrenceID].compactMap {
              $0
            }
          )
          : []
      )
    )
    if previousPhase != .strictRoute,
      engine.snapshot.journeyPhase == .strictRoute,
      let firstOccurrenceID = transition.firstRouteOccurrenceID
    {
      engine.markSyntheticSimulationEntryTransition()
      try matcherSession.restart(at: firstOccurrenceID)
    }
    return update(
      estimate: estimate,
      guidanceProgressState: .notApplicable
    )
  }

  /// Applies release-bound, multi-observation entrance evidence.
  ///
  /// The ordinary route matcher cannot call this path or manufacture forward
  /// continuity. The actor serializes admission with every other navigation
  /// event and restarts route matching at the occurrence the evidence reached
  /// only after strict-route entry succeeds.
  public func observeEntryTransitionEvidence(
    _ evidence: EntryTransitionEvidence
  ) throws -> EntryTransitionSessionUpdate {
    guard var admission = entryTransitionAdmission else {
      return EntryTransitionSessionUpdate(
        status: .rejected,
        rejectionReason: .runtimeNotReleaseAdmitted,
        navigationSnapshot: engine.snapshot
      )
    }

    let decision = admission.admit(
      evidence,
      journeyPhase: engine.snapshot.journeyPhase
    )
    entryTransitionAdmission = admission
    if decision.status == .progressed {
      engine.beginEntryTransition()
    }
    if decision.status == .strictRouteEntered,
      let firstOccurrenceID = admission.context.entryTransition.firstRouteOccurrenceID,
      let reachedOccurrenceID = decision.reachedOccurrenceID
    {
      engine.enterStrictRoute(
        firstOccurrenceID: firstOccurrenceID,
        reachedOccurrenceID: reachedOccurrenceID,
        trigger: "VERIFIED_ROUTE_HEAD_PROGRESSION"
      )
      try matcherSession.restart(at: reachedOccurrenceID)
    }
    return EntryTransitionSessionUpdate(
      status: decision.status,
      rejectionReason: decision.rejectionReason,
      reachedOccurrenceID: decision.reachedOccurrenceID,
      navigationSnapshot: engine.snapshot
    )
  }

  /// Drops one whole lap of a loop the driver decided not to complete.
  ///
  /// The App asks; the released lap boundaries decide where the drive lands.
  /// Returns the occurrence it moved to, or `nil` when no whole lap is left
  /// ahead to drop.
  @discardableResult
  public func skipOneLap() -> String? {
    guard let occurrenceID = engine.skipOneLap(
      trigger: "DRIVER_DROPPED_ONE_LAP"
    ) else {
      return nil
    }
    try? matcherSession.restart(at: occurrenceID)
    return occurrenceID
  }

  @discardableResult
  public func skipRemainingLaps() throws -> String? {
    var updatedEngine = engine
    guard let occurrenceID = updatedEngine.skipRemainingLaps(
      trigger: "DRIVER_FINISHING_CURRENT_LAP"
    ) else { return nil }
    try matcherSession.restart(at: occurrenceID)
    engine = updatedEngine
    return occurrenceID
  }

  public var remainingWholeLapsAhead: Int {
    guard let routePlan = configuredRoutePlan,
      let currentIndex = engine.snapshot.currentOccurrenceIndex
    else {
      return 0
    }
    let boundaries = configuredLapBoundaryOccurrenceIDs.compactMap {
      routePlan.occurrence(id: $0)?.index
    }
    guard boundaries.count >= 2,
      let lap = boundaries.indices.dropLast().last(where: {
        currentIndex >= boundaries[$0] && currentIndex < boundaries[$0 + 1]
      })
    else {
      return 0
    }
    return boundaries.count - 2 - lap
  }

  /// Records that the driver says the car is already on the selected route.
  ///
  /// This grants no position. It only opens `observeRouteJoinEvidence` for a
  /// bounded window, and the matcher still has to settle on one exact plan
  /// occurrence before the session leaves `ENTRY_TRANSITION`.
  public func declareAlreadyOnRoute(
    atMilliseconds milliseconds: Int
  ) -> Bool {
    guard var admission = routeJoinAdmission,
      engine.snapshot.journeyPhase == .planning
        || engine.snapshot.journeyPhase == .approachToEntry
        || engine.snapshot.journeyPhase == .entryTransition
    else {
      return false
    }
    admission.declare(atMilliseconds: milliseconds)
    routeJoinAdmission = admission
    return true
  }

  public func withdrawAlreadyOnRouteDeclaration() {
    guard var admission = routeJoinAdmission else { return }
    admission.withdraw()
    routeJoinAdmission = admission
  }

  public var isAlreadyOnRouteDeclared: Bool {
    routeJoinAdmission?.isDeclared ?? false
  }

  /// Applies one matcher-resolved on-route position offered under the driver's
  /// declaration, and joins the strict route once the run holds.
  public func observeRouteJoinEvidence(
    _ evidence: RouteJoinEvidence
  ) throws -> RouteJoinSessionUpdate {
    guard var admission = routeJoinAdmission else {
      return RouteJoinSessionUpdate(
        status: .rejected,
        rejectionReason: .runtimeNotReleaseAdmitted,
        navigationSnapshot: engine.snapshot
      )
    }

    let decision = admission.admit(
      evidence,
      journeyPhase: engine.snapshot.journeyPhase
    )
    routeJoinAdmission = admission
    if decision.status == .joined,
      let occurrenceID = decision.joinedOccurrenceID
    {
      engine.joinStrictRoute(
        atOccurrenceID: occurrenceID,
        trigger: "DRIVER_DECLARED_ROUTE_JOIN"
      )
      try matcherSession.restart(at: occurrenceID)
      admission.withdraw()
      routeJoinAdmission = admission
    }
    return RouteJoinSessionUpdate(
      status: decision.status,
      rejectionReason: decision.rejectionReason,
      joinedOccurrenceID: decision.joinedOccurrenceID,
      navigationSnapshot: engine.snapshot
    )
  }

  /// Requires two fresh, forward, release-bound observations on the exact
  /// ordinary-road handoff edge before leaving `EXIT_TRANSITION`.
  public func observeSurfaceEgressHandoffEvidence(
    _ evidence: SurfaceEgressHandoffEvidence
  ) -> SurfaceEgressHandoffSessionUpdate {
    guard var admission = surfaceEgressAdmission else {
      return SurfaceEgressHandoffSessionUpdate(
        status: .rejected,
        rejectionReason: .runtimeNotReleaseAdmitted,
        navigationSnapshot: engine.snapshot
      )
    }
    let decision = admission.admit(
      evidence,
      snapshot: engine.snapshot
    )
    surfaceEgressAdmission = admission
    if decision.status == .surfaceEgressEntered {
      engine.activateSurfaceEgress()
    }
    return SurfaceEgressHandoffSessionUpdate(
      status: decision.status,
      rejectionReason: decision.rejectionReason,
      navigationSnapshot: engine.snapshot
    )
  }

  @discardableResult
  public func resetMatcher() -> NavigationSnapshot {
    matcherSession.reset()
    return engine.snapshot
  }

  @discardableResult
  public func restartMatcher(at occurrenceID: String?) throws -> NavigationSnapshot {
    try matcherSession.restart(at: occurrenceID)
    return engine.snapshot
  }

  @discardableResult
  public func connectCarPlay() -> NavigationSnapshot {
    engine.connectCarPlay()
    return engine.snapshot
  }

  @discardableResult
  public func disconnectCarPlay() -> NavigationSnapshot {
    engine.disconnectCarPlay()
    return engine.snapshot
  }

  @discardableResult
  public func enterTunnel() -> NavigationSnapshot {
    engine.enterTunnel()
    return engine.snapshot
  }

  @discardableResult
  public func exitTunnel() -> NavigationSnapshot {
    engine.exitTunnel()
    return engine.snapshot
  }

  @discardableResult
  public func observeBranch(_ observation: BranchObservation) -> NavigationSnapshot {
    engine.observeBranch(observation)
    return engine.snapshot
  }

  @discardableResult
  public func updateRestriction(subjectID: String, state: String) -> NavigationSnapshot {
    engine.updateRestriction(subjectID: subjectID, state: state)
    return engine.snapshot
  }

  @discardableResult
  public func finishDrive() -> NavigationSnapshot {
    engine.finishDrive()
    return engine.snapshot
  }

  /// Applies the explicit route-only exit-handoff completion boundary.
  ///
  /// The reducer refuses completion unless the runtime configuration permits
  /// it, the released exit is active, and progress is on the terminal
  /// RoutePlan occurrence.
  @discardableResult
  public func completeAtExitHandoff() -> NavigationSnapshot {
    engine.completeAtExitHandoff()
    return engine.snapshot
  }

  private func update(
    estimate: MatcherEstimate,
    guidanceProgressState: NavigationSessionGuidanceProgressState,
    guidanceProgressObservation: GuidanceProgressObservation? = nil,
    guidancePromptEmission: GuidancePromptEmission? = nil,
    guidanceBridgeError: GuidanceProgressBridgeError? = nil
  ) -> NavigationSessionUpdate {
    NavigationSessionUpdate(
      matcherEstimate: estimate,
      matcherDiagnostics: matcherSession.diagnostics,
      navigationSnapshot: engine.snapshot,
      guidanceProgressState: guidanceProgressState,
      guidanceProgressObservation: guidanceProgressObservation,
      guidancePromptEmission: guidancePromptEmission,
      guidanceBridgeError: guidanceBridgeError
    )
  }

  private static func locationObservation(
    from estimate: MatcherEstimate,
    source observation: RouteMatcherObservation,
    admitsOccurrenceProgress: Bool,
    admitsMediumConfidence: Bool,
    resolvesLongitudinalCandidates: Bool,
    separatedFromOffPlanRoads: Bool = true
  ) -> LocationObservation {
    guard admitsOccurrenceProgress else {
      return LocationObservation(
        observedAtMilliseconds: observation.observedAtMilliseconds,
        reportedConfidence: LocationConfidence(rawValue: estimate.confidence.rawValue) ?? .lost,
        horizontalAccuracyMeters: observation.horizontalAccuracyMeters,
        ageMilliseconds: observation.receivedAtMilliseconds
          - observation.observedAtMilliseconds
      )
    }
    let candidateResolution: RouteCandidateResolution
    if estimate.directedEdgeID != nil,
      estimate.candidateEdgeIDs.count == 1 || resolvesLongitudinalCandidates
    {
      candidateResolution = .resolved
    } else if estimate.candidateEdgeIDs.count > 1 {
      candidateResolution = .ambiguous
    } else {
      candidateResolution = .unknown
    }
    // An off-plan road inside the candidate radius can be where the car is:
    // a branch running beside the plan is not separated by score margin.
    let admittedConfidence: LocationConfidence
    switch estimate.confidence {
    case .high:
      admittedConfidence = separatedFromOffPlanRoads ? .high : .medium
    case .medium:
      admittedConfidence =
        admitsMediumConfidence
          && estimate.occurrenceID != nil
          && resolvesLongitudinalCandidates
          && separatedFromOffPlanRoads
        ? .high : .medium
    case .low:
      admittedConfidence = .low
    case .lost:
      admittedConfidence = .lost
    }
    return LocationObservation(
      directedEdgeID: estimate.directedEdgeID,
      matchedEntityID: estimate.directedEdgeID,
      matchedOccurrenceID: estimate.occurrenceID,
      candidateOccurrenceIDs: Set([estimate.occurrenceID].compactMap { $0 }),
      candidateResolution: candidateResolution,
      observedAtMilliseconds: observation.observedAtMilliseconds,
      reportedConfidence: admittedConfidence,
      horizontalAccuracyMeters: observation.horizontalAccuracyMeters,
      ageMilliseconds: observation.receivedAtMilliseconds
        - observation.observedAtMilliseconds,
      forwardContinuity: false
    )
  }

  private func longitudinalCandidatesAreResolved(
    in estimate: MatcherEstimate
  ) -> Bool {
    guard estimate.directedEdgeID != nil,
      let occurrenceID = estimate.occurrenceID,
      let occurrence = routePlan.occurrence(id: occurrenceID)
    else { return false }
    let lower = max(
      0,
      occurrence.index
        - RouteMatcherCorridor.longitudinalCandidateOccurrenceWindow
    )
    let upper = min(
      routePlan.occurrences.count - 1,
      occurrence.index
        + RouteMatcherCorridor.longitudinalCandidateOccurrenceWindow
    )
    return estimate.candidateEdgeIDs.allSatisfy { candidateID in
      (lower...upper).contains { routeEdgeIDByIndex[$0] == candidateID }
    }
  }

  private static func restorationEstimate(
    from estimate: MatcherEstimate
  ) -> MatcherEstimate {
    MatcherEstimate(
      observationID: estimate.observationID,
      estimatedAtMilliseconds: estimate.estimatedAtMilliseconds,
      directedEdgeID: estimate.directedEdgeID,
      occurrenceID: estimate.occurrenceID,
      candidateEdgeIDs: estimate.candidateEdgeIDs,
      confidence: estimate.confidence == .lost ? .lost : .low,
      distanceMeters: estimate.distanceMeters,
      fractionAlongEdge: estimate.fractionAlongEdge
    )
  }

  private static func guidanceTargets(
    routePlan: RoutePlan,
    decisionZones: [DecisionZoneProgressDefinition],
    releasedGuidance: [ReleasedGuidanceDefinition]
  ) -> [String: DecisionZoneProgressDefinition] {
    let zonesByID = Dictionary(uniqueKeysWithValues: decisionZones.map { ($0.id, $0) })
    // Repeated RoutePlan scans for every anchor on every segment make long
    // circuit startup quadratic. Resolve indices once before filling the map.
    let indicesByID = Dictionary(uniqueKeysWithValues: routePlan.occurrences.map { ($0.id, $0.index) })
    let targets = releasedGuidance.compactMap { definition
      -> (anchor: Int, movement: Int, zone: DecisionZoneProgressDefinition)? in
      guard let anchor = indicesByID[definition.anchor.occurrenceID],
        let movement = indicesByID[definition.frameTemplate.movementOccurrenceID],
        let zone = zonesByID[definition.frameTemplate.decisionZoneID]
      else { return nil }
      return (anchor, movement, zone)
    }
    var result: [String: DecisionZoneProgressDefinition] = [:]
    for occurrence in routePlan.occurrences {
      guard let target = targets.lazy.filter({
        $0.anchor <= occurrence.index
          && (occurrence.index < $0.movement || $0.anchor == occurrence.index)
      }).min(by: { $0.movement < $1.movement })
      else { continue }
      result[occurrence.id] = target.zone
    }
    return result
  }
}

/// Where a route with a released exit ends, for recognising that the car has
/// driven past it.
private struct RouteEndGeometry: Sendable {
  /// Occurrences that begin within this distance of the route end form the
  /// exit tail; admitted progress must have reached it.
  static let tailMeters = 300.0
  static let beyondEndMeters = 15.0
  static let lostClearanceMeters = 40.0

  let tailStartIndex: Int
  private let end: MatcherCoordinate
  private let direction: (east: Double, north: Double)

  init?(routePlan: RoutePlan, corridor: RouteMatcherCorridor) {
    let edgesByID = Dictionary(
      corridor.edges.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    let routeEdges = corridor.occurrences.sorted { $0.index < $1.index }
      .compactMap { edgesByID[$0.directedEdgeID] }
    guard routeEdges.count == routePlan.occurrences.count,
      let last = routeEdges.last,
      last.coordinates.count >= 2
    else { return nil }
    var remaining = 0.0
    var tailStart = routeEdges.count - 1
    for index in stride(from: routeEdges.count - 1, through: 0, by: -1) {
      remaining += routeEdges[index].lengthMeters
      guard remaining <= Self.tailMeters else { break }
      tailStart = index
    }
    let end = last.coordinates[last.coordinates.count - 1]
    let before = last.coordinates[last.coordinates.count - 2]
    let offset = Self.planarOffset(from: before, to: end)
    let length = hypot(offset.east, offset.north)
    guard length > 0 else { return nil }
    tailStartIndex = tailStart
    self.end = end
    direction = (offset.east / length, offset.north / length)
  }

  func isBeyondEnd(_ coordinate: MatcherCoordinate, matcherLost: Bool) -> Bool {
    let offset = Self.planarOffset(from: end, to: coordinate)
    let along = offset.east * direction.east + offset.north * direction.north
    return along >= Self.beyondEndMeters
      || (matcherLost
        && hypot(offset.east, offset.north) >= Self.lostClearanceMeters)
  }

  private static func planarOffset(
    from origin: MatcherCoordinate,
    to point: MatcherCoordinate
  ) -> (east: Double, north: Double) {
    let metersPerDegree = 6_371_000.0 * .pi / 180
    return (
      (point.longitude - origin.longitude) * metersPerDegree
        * cos(origin.latitude * .pi / 180),
      (point.latitude - origin.latitude) * metersPerDegree
    )
  }
}

extension MatcherEstimate {
  fileprivate func replacingOccurrenceID(_ occurrenceID: String) -> MatcherEstimate {
    MatcherEstimate(
      observationID: observationID,
      estimatedAtMilliseconds: estimatedAtMilliseconds,
      directedEdgeID: directedEdgeID,
      occurrenceID: occurrenceID,
      candidateEdgeIDs: candidateEdgeIDs,
      confidence: confidence,
      distanceMeters: distanceMeters,
      fractionAlongEdge: fractionAlongEdge
    )
  }
}
