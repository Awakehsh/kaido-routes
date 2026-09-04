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
    let estimate = try matcherSession.observe(observation)
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
    let resolvesLongitudinalCandidates =
      longitudinalCandidatesAreResolved(in: estimate)

    if requiresRestorationReacquisition {
      engine.observeLocation(
        Self.locationObservation(
          from: estimate,
          source: observation,
          admitsOccurrenceProgress: admitsOccurrenceProgress,
          admitsMediumConfidence: resolvesLongitudinalCandidates,
          resolvesLongitudinalCandidates: resolvesLongitudinalCandidates
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

    engine.observeLocation(
      Self.locationObservation(
        from: estimate,
        source: observation,
        admitsOccurrenceProgress: admitsOccurrenceProgress,
        admitsMediumConfidence: admitsMediumConfidenceProgress,
        resolvesLongitudinalCandidates: resolvesLongitudinalCandidates
      )
    )
    if detectsOffPlanDeviation,
      estimate.confidence == .high,
      estimate.occurrenceID == nil,
      let directedEdgeID = estimate.directedEdgeID,
      estimate.candidateEdgeIDs == [directedEdgeID],
      !isOnActiveRecoveryPath(directedEdgeID)
    {
      engine.observeBranch(
        BranchObservation(
          observedMovementID:
            uniquelyReleasedRecoveryTrigger(containing: directedEdgeID)
            ?? directedEdgeID,
          confidence: .high
        )
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
  /// event and restarts route matching at the exact first occurrence only after
  /// strict-route entry succeeds.
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
    if let observation = decision.engineObservation {
      engine.observeLocation(observation)
    }
    if decision.status == .strictRouteEntered,
      let firstOccurrenceID = admission.context.entryTransition.firstRouteOccurrenceID
    {
      if engine.snapshot.journeyPhase != .strictRoute {
        engine.enterStrictRoute(
          firstOccurrenceID: firstOccurrenceID,
          trigger: "VERIFIED_FIRST_ROUTE_EDGE_CONTINUITY"
        )
      }
      try matcherSession.restart(at: firstOccurrenceID)
    }
    return EntryTransitionSessionUpdate(
      status: decision.status,
      rejectionReason: decision.rejectionReason,
      acceptedTransitionEdgeIndex: decision.acceptedTransitionEdgeIndex,
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
    resolvesLongitudinalCandidates: Bool
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
    let admittedConfidence: LocationConfidence =
      estimate.confidence == .medium
        && admitsMediumConfidence
        && estimate.occurrenceID != nil
        && resolvesLongitudinalCandidates
      ? .high
      : LocationConfidence(rawValue: estimate.confidence.rawValue) ?? .lost
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
      (lower...upper).contains { index in
        matcherCorridor.occurrences.first {
          $0.index == index && $0.directedEdgeID == candidateID
        } != nil
      }
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
    decisionZones: [DecisionZoneProgressDefinition],
    releasedGuidance: [ReleasedGuidanceDefinition]
  ) -> [String: DecisionZoneProgressDefinition] {
    let zonesByID = Dictionary(uniqueKeysWithValues: decisionZones.map { ($0.id, $0) })
    var result: [String: DecisionZoneProgressDefinition] = [:]
    for definition in releasedGuidance where result[definition.anchor.occurrenceID] == nil {
      result[definition.anchor.occurrenceID] =
        zonesByID[
          definition.frameTemplate.decisionZoneID
        ]
    }
    return result
  }
}
