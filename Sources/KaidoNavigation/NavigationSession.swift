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
  /// Recovery with no rejoin that began past the plan's last choice of road,
  /// while the car is still near the exit. A street running on beside or
  /// under the road the exit leaves looks the same as that road here, so
  /// the car may have taken the exit or missed it; nothing yet tells which.
  public let isConfirmingPlannedExit: Bool
  /// Whether presentation draws the car at this fix's place on the plan. An
  /// admitted HIGH fix is drawn, and so is a fix on the plan held below it
  /// only because an off-plan road runs beside the plan: the road a fork just
  /// behind the car leaves by. On either road the car has come as far, so the
  /// marker keeps moving while admission, guidance and deviation wait for
  /// the roads to part.
  public let drawsPosition: Bool

  public init(
    matcherEstimate: MatcherEstimate,
    matcherDiagnostics: RouteMatcherSessionDiagnostics,
    navigationSnapshot: NavigationSnapshot,
    guidanceProgressState: NavigationSessionGuidanceProgressState,
    guidanceProgressObservation: GuidanceProgressObservation? = nil,
    guidancePromptEmission: GuidancePromptEmission? = nil,
    guidanceBridgeError: GuidanceProgressBridgeError? = nil,
    isConfirmingPlannedExit: Bool = false,
    drawsPosition: Bool
  ) {
    self.isConfirmingPlannedExit = isConfirmingPlannedExit
    self.drawsPosition = drawsPosition
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
  /// The commit cue of the first decision the car reaches before entry can
  /// be confirmed, where the route runs straight on from the ramp (Toyosu:
  /// the Shinonome JCT fork). Its cue is shown, not spoken, there; the App
  /// says it once as the car comes to the entrance, as part of the plan.
  public nonisolated let entranceAnnouncementGuidance: ReleasedGuidanceDefinition?
  private var routeJoinAdmission: RouteJoinAdmission?
  private var surfaceEgressAdmission: SurfaceEgressHandoffEvidenceAdmission?
  private let routePlan: RoutePlan
  private let matcherCorridor: RouteMatcherCorridor
  private let guidanceProgressRoute: GuidanceProgressBridge.Route
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
  /// Route length before each occurrence index, plus the total at the end.
  private let routeDistanceBeforeIndex: [Double]
  private let routeEnd: RouteEndGeometry?
  private let destinationParkingAreaEntry: DestinationParkingAreaEntry?
  private let parkingStopBypasses: [ParkingStopBypass]
  /// Mid-route PA stops the car passed by, and the passes a shortcut onto a
  /// later pass left out. Their road is not driven, so reach from admitted
  /// progress does not count it.
  private var skippedParkingStops: [Range<Int>] = []
  private var parkingStopBypassRun: (count: Int, lastObservedAtMilliseconds: Int, stop: Range<Int>)?
  private var offPlanRun: (count: Int, lastObservedAtMilliseconds: Int, edgeID: String)?
  private var laterPassRun: (count: Int, lastObservedAtMilliseconds: Int)?
  private var unplannedExitRun: (count: Int, lastObservedAtMilliseconds: Int)?
  /// Every road the car can drive without having left the expressway: the
  /// plan's own and those of the rest of the network.
  private let expresswayRoads: [[MatcherCoordinate]]
  private let corridorEdgeCoordinates: [String: [MatcherCoordinate]]
  private let corridorSuccessorEdgeIDs: [String: Set<String>]
  private let corridorEdgesByID: [String: RouteMatcherDirectedEdge]
  private var exitRun: (count: Int, lastObservedAtMilliseconds: Int)?
  private var lastMatchedOccurrenceIndex: Int?
  private var lastObservedCoordinate: MatcherCoordinate?
  /// Whether the current recovery began past the plan's last choice of road.
  private var recoveryBeganPastLastChoice: Bool?
  /// When the engine last admitted a position on the plan. Nothing the car
  /// drove since can lie farther ahead than plausible driving allows.
  private var lastProgressObservedAtMilliseconds: Int?

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
    requiresRestorationReacquisition: Bool = false,
    expresswayRoads: [[MatcherCoordinate]] = []
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
    guidanceProgressRoute = GuidanceProgressBridge.Route(
      routePlan: routePlan, corridor: matcherCorridor
    )
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
    let entryTransitionAdmission = entryTransitionAdmissionContext.map {
      EntryTransitionEvidenceAdmission(context: $0)
    }
    self.entryTransitionAdmission = entryTransitionAdmission
    entranceAnnouncementGuidance = entryTransitionAdmission.flatMap { admission in
      Self.firstDecisionBeforeEntry(
        routePlan: routePlan,
        releasedGuidance: navigationConfiguration.releasedGuidance,
        separatedIndex: admission.firstSeparatedRouteHeadIndex
      )
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
    let edgeLengths = Dictionary(
      matcherCorridor.edges.map { ($0.id, $0.lengthMeters) },
      uniquingKeysWith: { first, _ in first }
    )
    var distances = [0.0]
    for occurrence in matcherCorridor.occurrences.sorted(by: { $0.index < $1.index }) {
      distances.append(distances[distances.count - 1] + (edgeLengths[occurrence.directedEdgeID] ?? 0))
    }
    routeDistanceBeforeIndex = distances
    routeEnd =
      routePlan.destinationParkingAreaID == nil
      ? RouteEndGeometry(routePlan: routePlan, corridor: matcherCorridor)
      : nil
    corridorEdgeCoordinates = Dictionary(
      matcherCorridor.edges.map { ($0.id, $0.coordinates) },
      uniquingKeysWith: { first, _ in first }
    )
    corridorSuccessorEdgeIDs = Dictionary(
      matcherCorridor.edges.map { ($0.id, $0.successorEdgeIDs) },
      uniquingKeysWith: { first, _ in first }
    )
    corridorEdgesByID = Dictionary(
      matcherCorridor.edges.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    let planEdgeIDs = Set(matcherCorridor.occurrences.map(\.directedEdgeID))
    self.expresswayRoads =
      matcherCorridor.edges.filter { planEdgeIDs.contains($0.id) }.map(\.coordinates)
      + expresswayRoads
    destinationParkingAreaEntry = DestinationParkingAreaEntry(
      routePlan: routePlan,
      corridor: matcherCorridor
    )
    parkingStopBypasses = ParkingStopBypass.all(
      routePlan: routePlan,
      corridor: matcherCorridor
    )
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
    lastObservedCoordinate = observation.coordinate
    matcherSession.occurrenceWindow = occurrenceWindow(
      atMilliseconds: observation.observedAtMilliseconds
    )
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
    let observed = returnOccurrenceID.map { estimate.replacingOccurrenceID($0) } ?? estimate
    let isWithinReach = isWithinReachOfProgress(
      observed,
      atMilliseconds: observation.observedAtMilliseconds
    )
    engine.observeLocation(
      Self.locationObservation(
        from: observed,
        source: observation,
        admitsOccurrenceProgress: admitsOccurrenceProgress,
        admitsMediumConfidence: admitsMediumConfidenceProgress,
        resolvesLongitudinalCandidates: resolvesLongitudinalCandidates,
        separatedFromOffPlanRoads: separatedFromOffPlanRoads && isWithinReach
      )
    )
    let isBesideOffPlanRoad =
      observed.occurrenceID != nil && isWithinReach
      && observation.horizontalAccuracyMeters < Self.coarseFixAccuracyMeters
      && (matched.isHeldLowOnlyByOffPlanRoads
        || estimate.confidence == .high
        || estimate.confidence == .medium && resolvesLongitudinalCandidates)
    // Only an admitted fix at the occurrence progress stands on confirms
    // where the car is; one on a detour says nothing about the plan.
    if detectsOffPlanDeviation, engine.snapshot.locationConfidence == .high,
      let observedIndex = observed.occurrenceID.flatMap({ occurrenceIndexByID[$0] }),
      observedIndex == engine.snapshot.currentOccurrenceIndex
    {
      lastProgressObservedAtMilliseconds = observation.observedAtMilliseconds
    }
    if wasRecovering, engine.snapshot.journeyPhase == .strictRoute,
      let returnOccurrenceID
    {
      try matcherSession.restart(at: returnOccurrenceID)
    } else if !isWithinReach, let currentOccurrenceID = engine.snapshot.currentOccurrenceID {
      // The matcher followed a repeated traversal, or a misplaced fix, to a
      // place the car cannot have reached; anchor it back on admitted progress.
      try matcherSession.restart(at: currentOccurrenceID)
    }
    let continuesPastRouteEnd =
      estimate.occurrenceID == nil
      && estimate.confidence != .lost
      && estimate.directedEdgeID.map(continuesPastRouteEnd) == true
    // A ramp beside an earlier pass can read as that pass, even one under
    // cover that leaves reacquisition pending; the car's position past the
    // exit decides it.
    if engine.snapshot.journeyPhase == .strictRoute
      || engine.snapshot.journeyPhase == .routeRecovery
    {
      observeRouteEnd(
        estimate: estimate,
        continuesPastRouteEnd: continuesPastRouteEnd,
        observation: observation
      )
    }
    // A fix past the planned exit can also be clear of every expressway road;
    // the planned exit's own evidence, just weighed, wins. A car that left
    // the expressway right after a tunnel never reacquires the plan, so this
    // runs before reacquisition holds everything else back.
    if detectsOffPlanDeviation,
      let handedOver = handOverAtUnplannedExit(
        estimate: estimate,
        observation: observation,
        recentOffPlanPlacementEdgeID: matched.recentOffPlanPlacementEdgeID
      )
    {
      return handedOver
    }
    // Reacquisition after a tunnel waits for the plan, which a car that left
    // it there never gives back. Meanwhile a deviation is weighed only on a
    // road off the plan that the car can have reached since it was last
    // placed on it: after the portal the first fixes are the worst, so not on
    // a pass of the plan behind progress, nor the road the plan leaves at its
    // last choice.
    let isReacquiring = engine.snapshot.signalReacquisitionStatus == .pending
    if detectsOffPlanDeviation {
      try observeShortcutToLaterPass(estimate: estimate, observation: observation)
    }
    if detectsOffPlanDeviation,
      engine.snapshot.journeyPhase == .strictRoute
        || engine.snapshot.journeyPhase == .routeRecovery,
      !continuesPastRouteEnd,
      isReacquiring || !observeParkingStopBypass(estimate: estimate, observation: observation)
    {
      observeOffPlanEvidence(
        estimate: estimate,
        isOnReachableOffPlanEdge: matched.isOnReachableOffPlanEdge,
        edgeDistancesMeters: matched.edgeDistancesMeters,
        observation: observation,
        onlyOnReachableBranches: isReacquiring,
        recentOffPlanPlacementEdgeID: matched.recentOffPlanPlacementEdgeID
      )
    }
    if engine.snapshot.signalReacquisitionStatus == .pending {
      return update(
        estimate: Self.restorationEstimate(from: estimate),
        guidanceProgressState: .insufficientMatcherEvidence
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
        guidanceProgressState: .notApplicable,
        isBesideOffPlanRoad: isBesideOffPlanRoad
      )
    }

    do {
      let progress = try GuidanceProgressBridge.resolve(
        estimate: estimate,
        route: guidanceProgressRoute,
        decisionZone: decisionZone,
        skippedOccurrenceIDs: Set(engine.snapshot.skippedOccurrenceIDs)
      )
      let emission = engine.observeGuidanceProgress(progress)
      return update(
        estimate: estimate,
        guidanceProgressState: .resolved,
        guidanceProgressObservation: progress,
        guidancePromptEmission: emission,
        isBesideOffPlanRoad: isBesideOffPlanRoad
      )
    } catch let error as GuidanceProgressBridgeError {
      let state: NavigationSessionGuidanceProgressState =
        error == .insufficientMatcherEvidence
        ? .insufficientMatcherEvidence
        : .blocked
      return update(
        estimate: estimate,
        guidanceProgressState: state,
        guidanceBridgeError: error,
        isBesideOffPlanRoad: isBesideOffPlanRoad
      )
    }
  }

  /// Fixes on no corridor road and far from every expressway road: the car
  /// left the expressway where the plan does not, and the expressway portion
  /// ends there. A car on a junction branch the plan does not take is still
  /// on the expressway and stays in recovery. Fixes scattered off the expressway by GPS error come within
  /// the margin. As for any deviation, one such fix can be a reflection;
  /// consecutive ones mean the car left.
  static let unplannedExitMarginMeters = 100.0

  /// The update for a fix that ended the expressway portion at an unplanned
  /// exit, or nil when it did not.
  private func handOverAtUnplannedExit(
    estimate: MatcherEstimate,
    observation: RouteMatcherObservation,
    recentOffPlanPlacementEdgeID: String?
  ) -> NavigationSessionUpdate? {
    guard engine.snapshot.journeyPhase == .strictRoute
      || engine.snapshot.journeyPhase == .routeRecovery
    else { return nil }
    observeUnplannedExit(
      estimate: estimate,
      observation: observation,
      recentOffPlanPlacementEdgeID: recentOffPlanPlacementEdgeID
    )
    guard engine.snapshot.journeyPhase == .surfaceEgress else { return nil }
    return update(estimate: estimate, guidanceProgressState: .notApplicable)
  }

  private func observeUnplannedExit(
    estimate: MatcherEstimate,
    observation: RouteMatcherObservation,
    recentOffPlanPlacementEdgeID: String?
  ) {
    guard observation.horizontalAccuracyMeters < Self.coarseFixAccuracyMeters,
      estimate.confidence == .lost,
      metersFromExpressway(observation.coordinate) >= Self.unplannedExitMarginMeters
    else {
      unplannedExitRun = nil
      return
    }
    let continues = unplannedExitRun.map {
      observation.observedAtMilliseconds - $0.lastObservedAtMilliseconds
        <= Self.offPlanDeviationMaximumGapMilliseconds
    } ?? false
    let count = continues ? (unplannedExitRun?.count ?? 0) + 1 : 1
    unplannedExitRun = (count, observation.observedAtMilliseconds)
    // Past the planned exit the same fixes are its own evidence, which takes
    // one more of them; the handover waits for that run to finish or break.
    guard count >= Self.offPlanDeviationObservationCount, exitRun == nil else { return }
    unplannedExitRun = nil
    offPlanRun = nil
    // Past the plan's last choice of road the only way off the expressway is
    // the planned exit. So it is for a car last placed on the exit, or on
    // another ramp of its facility, even with progress short of the last
    // choice: a shortcut onto the exit itself (its link off C1 at Shiodome
    // JCT, taken from Shibakoen before the lap the plan drives first) leaves
    // progress at the fork. Nearness alone is not enough where the exit lies
    // beside the route head: a street that followed the Shibakoen ramp
    // closely enough to enter turns away near the Shiodome link. Coarse
    // fixes along the exit's ramp can withhold its own evidence until the
    // car is already off the expressway. Off it, the car left the expressway
    // somewhere: a fix nearer that exit than any other place it could have
    // left is the exit taken. The road the exit leaves can carry on beside
    // the street the car drives away on (Route 6 at Mukojima, C2 at
    // Senju-Shinbashi), so how near that road is says nothing about which
    // way the car left, and where the corridor stops following it (328 m
    // past Senju-Shinbashi from Gotanda) the car would still be on the
    // expressway. A shortcut onto the plan past its last choice can leave
    // no placement on it either: beside the plan the matcher holds the car
    // on the plan's own continuation, and the stretch lies beyond the
    // window. That the car can have reached it by road, off the plan, is
    // then what says it was on the exit.
    if let routeEnd,
      let currentIndex = engine.snapshot.currentOccurrenceIndex,
      max(currentIndex, lastMatchedOccurrenceIndex ?? currentIndex)
        >= routeEnd.exitSideStartIndex
        || recentOffPlanPlacementEdgeID.map(routeEnd.isOnExit) == true
        || reachesFinalStretchOffPlan(
          from: currentIndex,
          exitSideStartIndex: routeEnd.exitSideStartIndex,
          atMilliseconds: observation.observedAtMilliseconds
        ),
      routeEnd.metersFromExit(observation.coordinate, fromProgress: currentIndex)
        < routeEnd.metersFromOtherDepartures(observation.coordinate, fromProgress: currentIndex)
    {
      engine.finishAtRouteEnd()
      return
    }
    // Past the plan's last choice of road before its destination PA, the
    // only way off the expressway is the road past the PA's entry ramp: the
    // car drove past the PA. Fixes along that road beside the ramp can match
    // the ramp itself and hold progress short of the fork, so admitted
    // progress past the last choice is the evidence. A car that left before
    // it can still come back to the PA and gets surface guidance instead.
    if let entry = destinationParkingAreaEntry,
      let currentIndex = engine.snapshot.currentOccurrenceIndex,
      currentIndex >= entry.approachStartIndex
    {
      engine.endPastDestinationParkingArea(divergenceOccurrenceID: entry.divergenceOccurrenceID)
      return
    }
    engine.leaveAtUnplannedExit()
  }

  /// Whether the car can have reached the plan past its last choice of road
  /// by road from where it left the plan, off the plan it would have driven
  /// meanwhile, within the distance reach allows since progress was
  /// confirmed.
  private func reachesFinalStretchOffPlan(
    from progress: Int,
    exitSideStartIndex: Int,
    atMilliseconds observedAt: Int
  ) -> Bool {
    guard let progressAt = lastProgressObservedAtMilliseconds else { return false }
    let limit =
      Double(max(0, observedAt - progressAt)) / 1_000 * Self.maximumPlausibleSpeedMetersPerSecond
      + Self.reachMarginMeters
    // Progress can run past the fork the car left at: a road beside the plan
    // holds fixes on the plan's own continuation, by up to 24 occurrences on
    // the shortcuts the stress catalog drives. It can also stop short of the
    // fork, by as much as the matcher looks ahead of it. From further back a
    // street following the Shibakoen ramp, 25 occurrences short of the
    // Shiodome link, would reach the link.
    let window = RouteMatcherCorridor.longitudinalCandidateOccurrenceWindow
    let startPasses = Dictionary(
      grouping: (max(0, progress - 2 * window)...(progress + window)).filter { routeEdgeIDByIndex[$0] != nil },
      by: { routeEdgeIDByIndex[$0]! }
    )
    // A road the car could have driven to along the plan in the time is
    // where it would be had it stayed on the plan: reached only that way,
    // the final stretch is no shortcut, and counts where the plan comes to it
    // only beyond that.
    let isFinalStretch = { (edgeID: String) in
      self.occurrenceIndexesByEdgeID[edgeID]?.contains {
        $0 >= exitSideStartIndex
          && !self.isWithinReachOfProgress(index: $0, atMilliseconds: observedAt)
      } == true
    }
    let isPlanAhead = { (edgeID: String) in
      self.occurrenceIndexesByEdgeID[edgeID]?.contains {
        $0 > progress && self.isWithinReachOfProgress(index: $0, atMilliseconds: observedAt)
      } == true
    }
    let laterPasses = { (edgeID: String) in
      (self.occurrenceIndexesByEdgeID[edgeID] ?? []).filter {
        $0 > progress && !self.isWithinReachOfProgress(index: $0, atMilliseconds: observedAt)
      }
    }
    // Onto the final stretch from the plan's own road before it, the car came
    // to the last choice on the plan and could have taken the other road
    // there: nothing then says which. On a loop that road can be the fork the
    // car left at on an earlier pass, so the test is by pass.
    let comesByLastChoice = { (from: String, to: String) -> Bool in
      let stretch = (self.occurrenceIndexesByEdgeID[to] ?? []).filter { $0 >= exitSideStartIndex }
      if let starts = startPasses[from] {
        return starts.allSatisfy { stretch.contains($0 + 1) }
      }
      let passes = laterPasses(from)
      return stretch.contains { passes.contains($0 - 1) }
    }
    return shortestCorridorPath(
      from: Dictionary(
        uniqueKeysWithValues: startPasses.keys.map { ($0, -(corridorEdgesByID[$0]?.lengthMeters ?? 0)) }
      ),
      edgesByID: corridorEdgesByID,
      maximumMeters: limit,
      allows: { from, to in
        isFinalStretch(to) ? !comesByLastChoice(from, to) : !isPlanAhead(to)
      },
      isTarget: { startPasses[$0] == nil && isFinalStretch($0) }
    ) != nil
  }

  /// Distance from the fix to the nearest road of the plan the car can be
  /// on: the matcher's occurrence window.
  private func metersFromPlanInWindow(_ coordinate: MatcherCoordinate) -> Double {
    guard let window = matcherSession.occurrenceWindow else { return 0 }
    return window.compactMap { index in
      routeEdgeIDByIndex[index].flatMap { corridorEdgeCoordinates[$0] }.map {
        RouteEndGeometry.meters(from: coordinate, toPolyline: $0)
      }
    }.min() ?? 0
  }

  private func metersFromExpressway(_ coordinate: MatcherCoordinate) -> Double {
    expresswayRoads.map {
      RouteEndGeometry.meters(from: coordinate, toPolyline: $0)
    }.min() ?? .infinity
  }

  /// Fixes that place the car where the plan cannot be: on an off-plan road
  /// it can have turned onto, or on a traversal of the plan it has already
  /// driven past. Each must be clear of every road of the plan the car can
  /// still be on by twice the error its accuracy allows, so a fix scattered
  /// off the road the car is on is never evidence. One such fix can be a
  /// reflection beside a viaduct; consecutive ones mean the car left the plan.
  static let offPlanDeviationObservationCount = 2
  static let offPlanDeviationMaximumGapMilliseconds = 3_000

  private func observeOffPlanEvidence(
    estimate: MatcherEstimate,
    isOnReachableOffPlanEdge: Bool,
    edgeDistancesMeters: [String: Double],
    observation: RouteMatcherObservation,
    onlyOnReachableBranches: Bool = false,
    recentOffPlanPlacementEdgeID: String? = nil
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
      // corridor along it. So has a car the matcher last placed on a road it
      // can have left the plan for, once the fix is as far from every road of
      // the plan it can be on as an unplanned exit needs: where that road
      // runs stacked on or beside the plan (Route 11 over the Bayshore at
      // Ariake JCT), and through coarse fixes after, no fix along it is
      // evidence before the corridor runs out. Otherwise it proves nothing,
      // and near the route end leaving the corridor is what taking the exit
      // looks like.
      let runEdgeID = continues ? offPlanRun?.edgeID : nil
      let placedEdgeID =
        runEdgeID == nil
          && metersFromPlanInWindow(observation.coordinate) >= Self.unplannedExitMarginMeters
        ? recentOffPlanPlacementEdgeID : nil
      guard let lastEdgeID = runEdgeID ?? placedEdgeID,
        routeEnd.map({
          $0.metersFromExit(
            observation.coordinate, fromProgress: engine.snapshot.currentOccurrenceIndex ?? 0
          ) > $0.exitCoverageMeters(fromProgress: engine.snapshot.currentOccurrenceIndex ?? 0)
        }) ?? true
      else {
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
      let clearance = 3 * max(5, observation.horizontalAccuracyMeters)
      guard let directedEdgeID = estimate.directedEdgeID,
        let distance = estimate.distanceMeters,
        distance <= clearance,
        (isOnReachableOffPlanEdge && !isOnActiveRecoveryPath(directedEdgeID))
          || !onlyOnReachableBranches
            && (isBehindProgress(estimate)
              || isOnRoadLeftAtLastChoice(estimate, observation: observation)),
        // Off the plan by its clearance is no evidence for a road a few
        // metres beside it: a receiver reporting half its error clears 3×
        // that error routinely. The fix must also lie nearer the road it is
        // matched to than any road of the plan, by more than its error.
        isClearOfRemainingPlan(
          edgeDistancesMeters,
          clearanceMeters: max(
            clearance, distance + max(5, observation.horizontalAccuracyMeters)
          )
        ),
        // A fix scattered onto a road beside the plan or across it, even the
        // opposite carriageway, is matched there while the car drives on: a
        // reachable road is evidence only while the course runs along it. A
        // fix without a course can carry a run on but not begin one.
        !(isOnReachableOffPlanEdge && !isOnActiveRecoveryPath(directedEdgeID))
          || (observation.courseDegrees != nil && observation.courseAccuracyDegrees != nil
            ? isDrivingAlong(directedEdgeID, observation: observation)
            : continues),
        // Just out of a tunnel, a receiver that reports half its error places
        // fixes on a road beside the plan as readily as the car on it; only a
        // placement the matcher holds above LOW, driving along that road, shows
        // the car is there.
        !onlyOnReachableBranches
          || estimate.confidence != .low
            && isDrivingAlong(directedEdgeID, observation: observation),
        // Leaving past the destination PA's entry ramp ends the drive; the
        // ramp runs beside the road past it at first, so a fix the matcher
        // is torn about cannot show which one the car took.
        estimate.confidence != .low
          || !isPastDestinationParkingAreaEntry(
            directedEdgeID,
            atMilliseconds: observation.observedAtMilliseconds
          )
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
    if let entry = destinationParkingAreaEntry,
      isPastDestinationParkingAreaEntry(
        edgeID,
        atMilliseconds: observation.observedAtMilliseconds
      )
    {
      engine.endPastDestinationParkingArea(
        divergenceOccurrenceID: entry.divergenceOccurrenceID
      )
      return
    }
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

  /// Progress can run down the exit ahead of a car that drove on past it,
  /// along a ramp beside the road it leaves (Angyo's beside Route S1), and
  /// the matcher then no longer counts that road as one the car can be on.
  /// Past the exit's end, a fix on the road the plan leaves at its last
  /// choice is still evidence the car left the plan when it drives along
  /// that road: where the exit ends beside it (Route 6 at Mukojima), a car
  /// that took the exit scatters onto it too, driving away from it. Beside
  /// the exit nothing tells the two apart.
  private func isOnRoadLeftAtLastChoice(
    _ estimate: MatcherEstimate,
    observation: RouteMatcherObservation
  ) -> Bool {
    guard let routeEnd, estimate.occurrenceID == nil,
      let directedEdgeID = estimate.directedEdgeID,
      let course = observation.courseDegrees,
      let courseAccuracy = observation.courseAccuracyDegrees,
      let currentIndex = engine.snapshot.currentOccurrenceIndex,
      max(currentIndex, lastMatchedOccurrenceIndex ?? currentIndex)
        >= routeEnd.exitSideStartIndex,
      !routeEnd.isAlongExit(observation.coordinate),
      !isOnActiveRecoveryPath(directedEdgeID)
    else { return false }
    return routeEnd.isDrivingAlongRoadLeftAtLastChoice(
      directedEdgeID,
      at: observation.coordinate,
      courseDegrees: course,
      toleranceDegrees: max(30, 3 * courseAccuracy)
    )
  }

  /// Whether the course runs along the road within the fix's error of
  /// where it projects onto `edgeID`, into the roads before and after it.
  private func isDrivingAlong(_ edgeID: String, observation: RouteMatcherObservation) -> Bool {
    guard let coordinates = corridorEdgeCoordinates[edgeID],
      let course = observation.courseDegrees,
      let courseAccuracy = observation.courseAccuracyDegrees
    else { return false }
    return RouteEndGeometry.isDrivingAlong(
      coordinates,
      before: (corridorPredecessorEdgeIDs[edgeID] ?? []).compactMap { corridorEdgeCoordinates[$0] },
      after: (corridorSuccessorEdgeIDs[edgeID] ?? []).sorted().compactMap { corridorEdgeCoordinates[$0] },
      at: observation.coordinate,
      windowMeters: max(5, observation.horizontalAccuracyMeters),
      courseDegrees: course,
      toleranceDegrees: max(20, 3 * courseAccuracy)
    )
  }

  /// Fixes on the road a mid-route PA stop replaced, before the car reached
  /// the PA. Consecutive ones the matcher holds above LOW, at a stop the car
  /// can have reached, mean it passed the stop by: the stop is skipped and
  /// the drive goes on where that road rejoins the plan. A fix there that
  /// does not count is no evidence of a deviation either.
  /// - Returns: whether the fix was on such a road.
  private func observeParkingStopBypass(
    estimate: MatcherEstimate,
    observation: RouteMatcherObservation
  ) -> Bool {
    let progressIndex = engine.snapshot.currentOccurrenceIndex ?? -1
    guard estimate.confidence != .lost,
      let edgeID = estimate.directedEdgeID,
      let stop = parkingStopBypasses.first(where: {
        $0.edgeIDs.contains(edgeID)
          && progressIndex < $0.visitStartIndex
          && !skippedParkingStops.contains($0.occurrences)
      }),
      isWithinReachOfProgress(
        index: stop.occurrences.lowerBound,
        atMilliseconds: observation.observedAtMilliseconds
      )
    else {
      parkingStopBypassRun = nil
      return false
    }
    guard estimate.confidence != .low else {
      parkingStopBypassRun = nil
      return true
    }
    let continues = parkingStopBypassRun.map {
      $0.stop == stop.occurrences
        && observation.observedAtMilliseconds - $0.lastObservedAtMilliseconds
          <= Self.offPlanDeviationMaximumGapMilliseconds
    } ?? false
    let count = continues ? (parkingStopBypassRun?.count ?? 0) + 1 : 1
    parkingStopBypassRun = (count, observation.observedAtMilliseconds, stop.occurrences)
    guard count >= Self.offPlanDeviationObservationCount else { return true }
    parkingStopBypassRun = nil
    offPlanRun = nil
    skippedParkingStops.append(stop.occurrences)
    engine.skipParkingStop(
      occurrenceIDs: routePlan.occurrences
        .filter { stop.occurrences.contains($0.index) }
        .map(\.id)
    )
    return true
  }

  /// The car is on a road leaving the plan at its destination PA's entry
  /// ramp, and can have reached that divergence since admitted progress. A
  /// loop passes near the road in earlier laps; off-plan evidence there is
  /// an ordinary deviation.
  private func isPastDestinationParkingAreaEntry(
    _ directedEdgeID: String,
    atMilliseconds observedAt: Int
  ) -> Bool {
    guard let entry = destinationParkingAreaEntry,
      branchRootEdgeID(of: directedEdgeID).map(entry.passingEdgeIDs.contains) == true
    else { return false }
    return isWithinReachOfProgress(
      index: entry.divergenceIndex + 1,
      atMilliseconds: observedAt
    )
  }

  /// A match on a traversal of the plan well before admitted progress: the
  /// car drives on past where the plan left that road, as when it misses the
  /// exit of a loop it has already driven once.
  private func isBehindProgress(_ estimate: MatcherEstimate) -> Bool {
    guard let progressIndex = engine.snapshot.currentOccurrenceIndex,
      let index = estimate.occurrenceID.flatMap({ occurrenceIndexByID[$0] })
    else { return false }
    return index < progressIndex - RouteMatcherCorridor.longitudinalCandidateOccurrenceWindow
  }

  /// A car can leave the plan for a road the plan drives only later, and
  /// drive on along the plan from there (Tokyo Bay Route onto Route 10 at
  /// Shinonome JCT, straight to Toyosu, where the plan comes back by C2).
  /// Neither the window nor recovery's later-occurrence rejoin reaches that
  /// pass until reach catches up, minutes later, so the drive held progress
  /// at the fork and ended at its own exit as an unplanned one. Three HIGH
  /// fixes in a row on such a road, driving along it, each at least the
  /// unplanned-exit margin from every road of the plan the car can be on,
  /// re-anchor there: the passes between are skipped as a passed-by
  /// waypoint's are. A forward jump cannot be taken back, so the evidence is
  /// what leaving the corridor takes, not the deviation margin: with that
  /// margin a receiver reporting half its error jumped 56 km from the
  /// Bayshore onto Route 9 beside it at Tatsumi JCT.
  private func observeShortcutToLaterPass(
    estimate: MatcherEstimate,
    observation: RouteMatcherObservation
  ) throws {
    guard engine.snapshot.journeyPhase == .strictRoute
      || engine.snapshot.journeyPhase == .routeRecovery,
      estimate.confidence == .high,
      observation.horizontalAccuracyMeters < Self.coarseFixAccuracyMeters,
      let edgeID = estimate.directedEdgeID,
      let laterPass = laterPassIndex(of: edgeID),
      observation.courseDegrees != nil, observation.courseAccuracyDegrees != nil,
      isDrivingAlong(edgeID, observation: observation),
      metersFromPlanInWindow(observation.coordinate) >= Self.unplannedExitMarginMeters,
      let progress = engine.snapshot.currentOccurrenceIndex
    else {
      laterPassRun = nil
      return
    }
    let continues = laterPassRun.map {
      observation.observedAtMilliseconds - $0.lastObservedAtMilliseconds
        <= Self.offPlanDeviationMaximumGapMilliseconds
    } ?? false
    let count = continues ? (laterPassRun?.count ?? 0) + 1 : 1
    laterPassRun = (count, observation.observedAtMilliseconds)
    guard count >= Self.laterPassObservationCount else { return }
    laterPassRun = nil
    offPlanRun = nil
    let skipped = (progress + 1)..<laterPass
    skippedParkingStops.append(skipped)
    engine.skipParkingStop(
      occurrenceIDs: routePlan.occurrences.filter { skipped.contains($0.index) }.map(\.id)
    )
    if let laterPassID = routePlan.occurrences.first(where: { $0.index == laterPass })?.id {
      try matcherSession.restart(at: laterPassID)
    }
  }

  static let laterPassObservationCount = 3

  /// The pass of a road of the plan that the car can be on only by a
  /// shortcut: none between progress and the end of the reach window, and
  /// exactly one after it. A road with more passes ahead, another lap's,
  /// does not say which one the car took.
  private func laterPassIndex(of edgeID: String) -> Int? {
    guard let window = matcherSession.occurrenceWindow,
      let progress = engine.snapshot.currentOccurrenceIndex,
      let passes = occurrenceIndexesByEdgeID[edgeID],
      !passes.contains(where: { $0 >= progress && $0 <= window.upperBound })
    else { return nil }
    let ahead = passes.filter { $0 > window.upperBound }
    return ahead.count == 1 ? ahead[0] : nil
  }

  /// No road of the plan from just before admitted progress onwards, nor
  /// the road its exit leads onto, lies within `clearanceMeters` of the fix.
  private func isClearOfRemainingPlan(
    _ edgeDistancesMeters: [String: Double],
    clearanceMeters: Double
  ) -> Bool {
    let earliestIndex =
      (engine.snapshot.currentOccurrenceIndex ?? 0)
      - RouteMatcherCorridor.longitudinalCandidateOccurrenceWindow
    return !edgeDistancesMeters.contains { edgeID, distance in
      distance <= clearanceMeters
        && (occurrenceIndexesByEdgeID[edgeID]?.last.map { $0 >= earliestIndex } == true
          || continuesPastRouteEnd(edgeID))
    }
  }

  /// Faster than anyone drives the expressway. A match farther ahead of
  /// admitted progress than this allows since that progress is a repeated
  /// traversal or a misplaced fix, not where the car went.
  static let maximumPlausibleSpeedMetersPerSecond = 40.0
  static let reachMarginMeters = 100.0

  private func isWithinReachOfProgress(
    _ estimate: MatcherEstimate,
    atMilliseconds observedAt: Int
  ) -> Bool {
    guard let index = estimate.occurrenceID.flatMap({ occurrenceIndexByID[$0] })
    else { return true }
    return isWithinReachOfProgress(index: index, atMilliseconds: observedAt)
  }

  private func isWithinReachOfProgress(
    index: Int,
    atMilliseconds observedAt: Int
  ) -> Bool {
    guard let progressIndex = engine.snapshot.currentOccurrenceIndex,
      let progressAt = lastProgressObservedAtMilliseconds,
      index > progressIndex
    else { return true }
    let skippedMeters = skippedParkingStops.reduce(0.0) { total, stop in
      let lower = max(stop.lowerBound, progressIndex + 1)
      let upper = min(stop.upperBound, index)
      return lower < upper
        ? total + routeDistanceBeforeIndex[upper] - routeDistanceBeforeIndex[lower]
        : total
    }
    let gapMeters =
      routeDistanceBeforeIndex[index] - routeDistanceBeforeIndex[progressIndex + 1]
      - skippedMeters
    let elapsedSeconds = Double(max(0, observedAt - progressAt)) / 1_000
    return gapMeters
      <= elapsedSeconds * Self.maximumPlausibleSpeedMetersPerSecond + Self.reachMarginMeters
  }

  /// The passes the car can be on: from the longitudinal window behind
  /// admitted progress to the farthest occurrence it can have reached since,
  /// under the reach rule. In recovery progress stands still and the reach
  /// keeps growing, so a car rejoining after a detour can still return.
  private func occurrenceWindow(atMilliseconds observedAt: Int) -> ClosedRange<Int>? {
    guard let progressIndex = engine.snapshot.currentOccurrenceIndex else { return nil }
    var reached = progressIndex
    var beyond = routePlan.occurrences.count
    while beyond - reached > 1 {
      let middle = (reached + beyond) / 2
      if isWithinReachOfProgress(index: middle, atMilliseconds: observedAt) {
        reached = middle
      } else {
        beyond = middle
      }
    }
    return max(0, progressIndex - RouteMatcherCorridor.longitudinalCandidateOccurrenceWindow)...reached
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

  /// The exit is recognised once the car is past the plan's last choice of
  /// road, by consecutive fixes off every corridor road near the exit, where
  /// the corridor holds every road the car could be on instead of it, or on
  /// the road reached only through the route's terminal edge. Each must also
  /// lie clear of every such road, earlier passes of the plan included, by
  /// four times the fix's accuracy, and lie nearer the exit than any of them:
  /// beside the exit the road the car missed it for can be a pass of the plan
  /// the matcher does not consider, and an exit ramp runs within metres of
  /// the road it leaves, so only fixes past its end can tell them apart. A
  /// finished drive cannot be resumed, so the bar is higher than for a
  /// deviation.
  static let exitEvidenceObservationCount = 3
  static let coarseFixAccuracyMeters = 30.0

  private func observeRouteEnd(
    estimate: MatcherEstimate,
    continuesPastRouteEnd: Bool,
    observation: RouteMatcherObservation
  ) {
    let matchedIndex =
      estimate.confidence == .lost
      ? nil : estimate.occurrenceID.flatMap { occurrenceIndexByID[$0] }
    if let matchedIndex {
      lastMatchedOccurrenceIndex = matchedIndex
    }
    guard let routeEnd,
      let currentIndex = engine.snapshot.currentOccurrenceIndex
    else { return }
    // Parallel exit ramps can withhold admitted progress past the last
    // choice; the matcher's own placement there is enough to look for the
    // car having taken the exit.
    let isPastLastChoice =
      max(currentIndex, lastMatchedOccurrenceIndex ?? currentIndex)
      >= routeEnd.exitSideStartIndex
    guard isPastLastChoice || continuesPastRouteEnd else {
      exitRun = nil
      return
    }
    guard observation.horizontalAccuracyMeters < Self.coarseFixAccuracyMeters
    else { return }
    let continues = exitRun.map {
      observation.observedAtMilliseconds - $0.lastObservedAtMilliseconds
        <= Self.offPlanDeviationMaximumGapMilliseconds
    } ?? false
    let clearance = 4 * max(5, observation.horizontalAccuracyMeters)
    let metersFromExit = routeEnd.metersFromExit(observation.coordinate, fromProgress: currentIndex)
    let metersFromOtherRoads = routeEnd.metersFromOtherRoads(
      observation.coordinate, fromProgress: currentIndex
    )
    // Clearing every other road by four times its reported error is not
    // enough on its own: a receiver can report half its true error, and a car
    // that drove on past the exit then scatters as far off the road it is on
    // (past Kasumigaseki, Angyo and Tomigaya). The fix has to lie nearer the
    // exit than any road the car could be on instead. Beside the exit that
    // road can run as close as the exit itself (Kasumigaseki's ramp, a few
    // metres from C1 for 400 m), so there it has to be nearer by more than
    // the fix's error.
    let isAlongExit = routeEnd.isAlongExit(
      observation.coordinate, toleranceMeters: max(5, observation.horizontalAccuracyMeters)
    )
    let nearerExitMarginMeters =
      isAlongExit ? max(5, observation.horizontalAccuracyMeters) : 0
    // Past the end, a road passing beside it stays nearer than the exit to a
    // car driving straight away from both (Route 6 at Mukojima). A fix's
    // course does not scatter with its position: one running along none of
    // those roads within half as far again as the clearance is not on any of
    // them. Fixes scattered off the road a car drove on along lay up to 1.3
    // clearances from it; a map bearing can be 20 degrees off the lanes.
    let drivesAlongNoOtherRoad =
      !isAlongExit
      && observation.courseDegrees.map { course in
        observation.courseAccuracyDegrees.map { courseAccuracy in
          !routeEnd.runsAlongOtherRoad(
            observation.coordinate,
            courseDegrees: course,
            toleranceDegrees: max(20, 3 * courseAccuracy),
            withinMeters: 1.5 * clearance,
            fromProgress: currentIndex
          )
        } ?? false
      } ?? false
    let isOffCorridorAtEnd =
      estimate.confidence == .lost
      && metersFromExit <= routeEnd.exitCoverageMeters(fromProgress: currentIndex) - clearance
      && (metersFromOtherRoads - metersFromExit > nearerExitMarginMeters
        || drivesAlongNoOtherRoad)
    guard isOffCorridorAtEnd || continuesPastRouteEnd,
      metersFromOtherRoads >= clearance
    else {
      exitRun = nil
      return
    }
    let count = continues ? (exitRun?.count ?? 0) + 1 : 1
    exitRun = (count, observation.observedAtMilliseconds)
    guard count >= Self.exitEvidenceObservationCount else { return }
    exitRun = nil
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
      lastProgressObservedAtMilliseconds = evidence.observedAtMilliseconds
      try matcherSession.restart(at: reachedOccurrenceID)
    }
    return EntryTransitionSessionUpdate(
      status: decision.status,
      rejectionReason: decision.rejectionReason,
      reachedOccurrenceID: decision.reachedOccurrenceID,
      navigationSnapshot: engine.snapshot,
      entryStretchGuidanceFrame: entryStretchGuidanceFrame(
        admission: admission,
        observedAtMilliseconds: evidence.observedAtMilliseconds
      )
    )
  }

  /// The commit cue of the earliest decision the car reaches before the
  /// route head leaves the straight road beyond the ramp, when there is one.
  private static func firstDecisionBeforeEntry(
    routePlan: RoutePlan,
    releasedGuidance: [ReleasedGuidanceDefinition],
    separatedIndex: Int?
  ) -> ReleasedGuidanceDefinition? {
    let indexes = Dictionary(
      routePlan.occurrences.map { ($0.id, $0.index) }, uniquingKeysWith: { first, _ in first }
    )
    guard
      let movement = releasedGuidance.compactMap({ indexes[$0.frameTemplate.movementOccurrenceID] })
        .filter({ movement in separatedIndex.map { movement < $0 } ?? true }).min()
    else { return nil }
    return releasedGuidance.first {
      $0.anchor.anchorID == "COMMIT"
        && indexes[$0.frameTemplate.movementOccurrenceID] == movement
    }
  }

  /// Where the route head runs straight on from the ramp, entry waits for
  /// the route to leave that straight line: from Toyosu it stays within
  /// 14 m of it for 1.1 km, past the Shinonome JCT fork, whose cue then
  /// never played. A car on a street along that line looks the same, so
  /// the cue is not spoken there; once ordered evidence has followed the car
  /// along the route head to a cue's anchor, its frame is shown. Entry,
  /// progress and every strict-route rule are unchanged.
  private func entryStretchGuidanceFrame(
    admission: EntryTransitionEvidenceAdmission,
    observedAtMilliseconds: Int
  ) -> GuidanceFrame? {
    guard engine.snapshot.journeyPhase == .entryTransition,
      let occurrenceID = admission.orderedRouteHeadOccurrenceID,
      let decisionZone = guidanceTargetByAnchorOccurrence[occurrenceID],
      let directedEdgeID = guidanceProgressRoute.corridorOccurrencesByID[occurrenceID]?.directedEdgeID
    else { return nil }
    let estimate = MatcherEstimate(
      observationID: nil,
      estimatedAtMilliseconds: observedAtMilliseconds,
      directedEdgeID: directedEdgeID,
      occurrenceID: occurrenceID,
      candidateEdgeIDs: [directedEdgeID],
      confidence: .medium,
      distanceMeters: nil,
      fractionAlongEdge: 0
    )
    guard
      let progress = try? GuidanceProgressBridge.resolve(
        estimate: estimate,
        route: guidanceProgressRoute,
        decisionZone: decisionZone,
        skippedOccurrenceIDs: Set(engine.snapshot.skippedOccurrenceIDs)
      )
    else { return nil }
    return engine.entryStretchGuidanceFrame(progress)
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
      lastProgressObservedAtMilliseconds = evidence.observedAtMilliseconds
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

  /// Ends strict route at the released exit on the driver's Finish command,
  /// which is offered only near the route end. Progress advances to the
  /// terminal occurrence first, as route-end recognition does, so the exit
  /// handoff can complete.
  @discardableResult
  public func finishAtRouteEnd() -> NavigationSnapshot {
    engine.finishAtRouteEnd()
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
    guidanceBridgeError: GuidanceProgressBridgeError? = nil,
    isBesideOffPlanRoad: Bool = false
  ) -> NavigationSessionUpdate {
    NavigationSessionUpdate(
      matcherEstimate: estimate,
      matcherDiagnostics: matcherSession.diagnostics,
      navigationSnapshot: engine.snapshot,
      guidanceProgressState: guidanceProgressState,
      guidanceProgressObservation: guidanceProgressObservation,
      guidancePromptEmission: guidancePromptEmission,
      guidanceBridgeError: guidanceBridgeError,
      isConfirmingPlannedExit: isConfirmingPlannedExit(),
      // A fix that took the car off the plan or into reacquisition is no
      // longer drawn on it.
      drawsPosition: engine.snapshot.locationConfidence == .high
        || isBesideOffPlanRoad && engine.snapshot.journeyPhase == .strictRoute
          && engine.snapshot.signalReacquisitionStatus != .pending
    )
  }

  /// How far from the exit a recovery that began past the last choice still
  /// leaves open whether the car took it: a street beside the road the exit
  /// leaves runs with it for up to about 400 m (Route 6 at Mukojima). Past
  /// this the car is on that road, and the recovery stands.
  static let confirmingPlannedExitMeters = 500.0

  private func isConfirmingPlannedExit() -> Bool {
    guard engine.snapshot.journeyPhase == .routeRecovery,
      let routeEnd,
      let currentIndex = engine.snapshot.currentOccurrenceIndex
    else {
      recoveryBeganPastLastChoice = nil
      return false
    }
    if recoveryBeganPastLastChoice == nil {
      recoveryBeganPastLastChoice =
        max(currentIndex, lastMatchedOccurrenceIndex ?? currentIndex)
        >= routeEnd.exitSideStartIndex
    }
    guard recoveryBeganPastLastChoice == true,
      engine.snapshot.recovery.status == .unavailable,
      let lastObservedCoordinate
    else { return false }
    return routeEnd.metersFromExit(lastObservedCoordinate, fromProgress: currentIndex)
      <= Self.confirmingPlannedExitMeters
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
      let index = estimate.occurrenceID.flatMap({ occurrenceIndexByID[$0] })
    else { return false }
    let lower = max(
      0,
      index - RouteMatcherCorridor.longitudinalCandidateOccurrenceWindow
    )
    let upper = min(
      routePlan.occurrences.count - 1,
      index + RouteMatcherCorridor.longitudinalCandidateOccurrenceWindow
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

/// A mid-route PA stop and the road it replaced: the plan leaves that road
/// at the first of `occurrences` and the road rejoins the plan at its end.
private struct ParkingStopBypass: Sendable {
  let occurrences: Range<Int>
  let visitStartIndex: Int
  let edgeIDs: Set<String>

  /// The stop planner replaces at most this much of the route.
  static let maximumMeters = 3_000.0

  static func all(routePlan: RoutePlan, corridor: RouteMatcherCorridor) -> [Self] {
    let occurrences = corridor.occurrences.sorted { $0.index < $1.index }
    guard occurrences.map(\.index) == Array(occurrences.indices) else { return [] }
    let edgesByID = Dictionary(
      corridor.edges.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    var visits: [ClosedRange<Int>] = []
    for occurrence in routePlan.occurrences where occurrence.kind == .paVisit {
      if let last = visits.last, last.upperBound + 1 == occurrence.index {
        visits[visits.count - 1] = last.lowerBound...occurrence.index
      } else {
        visits.append(occurrence.index...occurrence.index)
      }
    }
    // A PA-terminal plan's last visit is its destination, not a stop.
    if routePlan.destinationParkingAreaID != nil,
      visits.last?.upperBound == routePlan.occurrences.count - 1
    {
      visits.removeLast()
    }
    return visits.compactMap { visit in
      bypass(around: visit, occurrences: occurrences, edgesByID: edgesByID)
    }
  }

  /// Walks back from the PA along the stop's approach to where the plan
  /// left another road, and finds the shortest corridor path from there
  /// that rejoins the plan after the PA without entering it.
  private static func bypass(
    around visit: ClosedRange<Int>,
    occurrences: [RouteMatcherOccurrence],
    edgesByID: [String: RouteMatcherDirectedEdge]
  ) -> Self? {
    var rejoinIndexByEdgeID: [String: Int] = [:]
    var returnMeters = 0.0
    for index in (visit.upperBound + 1)..<occurrences.count where returnMeters <= maximumMeters {
      let edgeID = occurrences[index].directedEdgeID
      if rejoinIndexByEdgeID[edgeID] == nil { rejoinIndexByEdgeID[edgeID] = index }
      returnMeters += edgesByID[edgeID]?.lengthMeters ?? 0
    }
    var approachMeters = 0.0
    for position in stride(from: visit.lowerBound - 1, through: 0, by: -1) {
      guard approachMeters <= maximumMeters,
        let here = edgesByID[occurrences[position].directedEdgeID]
      else { return nil }
      let stopEdgeIDs = Set(occurrences[(position + 1)...visit.upperBound].map(\.directedEdgeID))
      for start in here.successorEdgeIDs.sorted()
      where !stopEdgeIDs.contains(start) {
        if let (path, rejoinEdgeID) = shortestCorridorPath(
          from: [start: 0],
          edgesByID: edgesByID,
          maximumMeters: maximumMeters,
          allows: { _, next in !stopEdgeIDs.contains(next) },
          isTarget: { rejoinIndexByEdgeID[$0] != nil }
        ), !path.isEmpty, let rejoin = rejoinIndexByEdgeID[rejoinEdgeID] {
          return Self(
            occurrences: (position + 1)..<rejoin,
            visitStartIndex: visit.lowerBound,
            edgeIDs: Set(path)
          )
        }
      }
      approachMeters += here.lengthMeters
    }
    return nil
  }
}

/// The shortest road distance through the corridor from `starts`, each at
/// the metres already driven at its start, to the first road `isTarget`
/// takes, entering a road only where `allows` lets it from the road before,
/// within `maximumMeters`: the roads from a start up to it, and the road.
private func shortestCorridorPath(
  from starts: [String: Double],
  edgesByID: [String: RouteMatcherDirectedEdge],
  maximumMeters: Double,
  allows: (_ from: String, _ to: String) -> Bool,
  isTarget: (String) -> Bool
) -> (path: [String], target: String)? {
  var meters = starts
  var previous: [String: String] = [:]
  var open = Set(starts.keys)
  while let current = open.min(by: { meters[$0]! < meters[$1]! }) {
    open.remove(current)
    if isTarget(current) {
      var path: [String] = []
      var edgeID = previous[current]
      while let step = edgeID {
        path.append(step)
        edgeID = previous[step]
      }
      return (path.reversed(), current)
    }
    guard let edge = edgesByID[current] else { continue }
    let reached = meters[current]! + edge.lengthMeters
    guard reached <= maximumMeters else { continue }
    for next in edge.successorEdgeIDs
    where allows(current, next) && reached < meters[next] ?? .infinity {
      meters[next] = reached
      previous[next] = current
      open.insert(next)
    }
  }
  return nil
}

/// For a plan ending in a PA: its last choice of road before the PA visit,
/// where the plan takes the PA's entry ramp, and the roads that pass it by.
private struct DestinationParkingAreaEntry: Sendable {
  let divergenceIndex: Int
  let divergenceOccurrenceID: String
  let passingEdgeIDs: Set<String>
  /// From here to the PA's entry ramp the plan has no other choice of road.
  let approachStartIndex: Int

  init?(routePlan: RoutePlan, corridor: RouteMatcherCorridor) {
    guard let parkingAreaID = routePlan.destinationParkingAreaID else { return nil }
    let visitStart =
      (routePlan.occurrences.last {
        $0.kind != .paVisit || $0.parkingAreaID != parkingAreaID
      }?.index ?? -1) + 1
    let edgesByID = Dictionary(
      corridor.edges.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    let routeEdgeIDs = Set(corridor.occurrences.map(\.directedEdgeID))
    let occurrences = corridor.occurrences.sorted { $0.index < $1.index }
    for position in stride(from: min(visitStart, occurrences.count - 1) - 1, through: 0, by: -1) {
      let occurrence = occurrences[position]
      let next = occurrences[position + 1].directedEdgeID
      let passing = (edgesByID[occurrence.directedEdgeID]?.successorEdgeIDs ?? [])
        .filter { $0 != next }
      guard !passing.isEmpty else { continue }
      // Where the road past the ramp is one the plan drives elsewhere, as a
      // loop that passed the PA earlier, a car on it is not off the plan.
      guard !passing.contains(where: routeEdgeIDs.contains) else { return nil }
      divergenceIndex = occurrence.index
      divergenceOccurrenceID = occurrence.id
      passingEdgeIDs = Set(passing)
      approachStartIndex = RouteEndGeometry.lastChoiceIndex(
        occurrences.compactMap { edgesByID[$0.directedEdgeID] },
        through: occurrence.index
      )
      return
    }
    return nil
  }
}

/// Where a route with a released exit ends, for recognising that the car has
/// driven past it.
private struct RouteEndGeometry: Sendable {
  /// The first occurrence after the plan's last choice of road: from here on
  /// the car can only be on the exit.
  let exitSideStartIndex: Int
  /// The plan from `exitSideStartIndex` to its end.
  private let exit: [MatcherCoordinate]
  /// The roads of the exit: the plan from `exitSideStartIndex`, what
  /// continues past its end, and the exit facility's other ramps.
  private let exitRoadEdgeIDs: Set<String>
  /// The exit facility's other ramps and what the corridor follows past
  /// them, with the last occurrence of the plan they can be reached from: a
  /// car on one left at the planned exit all the same.
  private let exitRamps: [(coordinates: [MatcherCoordinate], lastReachingIndex: Int)]
  /// Every corridor road but the exit and what continues past its end, with
  /// the last occurrence of the plan it can be reached from: the roads the
  /// car could be on instead of the exit, earlier passes of the plan
  /// included. A road no occurrence from admitted progress on leads to —
  /// the other carriageway of a radial the drive came in on, and that
  /// carriageway's own exit — is not one of them.
  private let otherRoads: [(coordinates: [MatcherCoordinate], lastReachingIndex: Int)]
  /// Where the corridor stops following each road the car could be on
  /// instead of the exit: that point, its distance from the exit, and the
  /// last occurrence of the plan the road can be reached from.
  private let roadEnds: [(end: MatcherCoordinate, metersFromExit: Double, lastReachingIndex: Int)]
  /// Where a car that left the corridor along one of those roads can have
  /// left the expressway: the road end itself, or, where the network
  /// carries the road on, the exits the corridor records beyond it.
  private let departures: [(point: MatcherCoordinate, lastReachingIndex: Int)]
  /// The road the plan leaves at its last choice, as far as the corridor
  /// follows it, other than the exit facility's own ramps.
  private let roadLeftAtLastChoice: [String: [MatcherCoordinate]]

  /// The first occurrence after the plan's last choice of road at or before
  /// `end`: one whose predecessor leads somewhere besides it. Relies on
  /// corridor successors carrying every drivable departure from the plan.
  static func lastChoiceIndex(_ routeEdges: [RouteMatcherDirectedEdge], through end: Int) -> Int {
    routeEdges.indices.dropFirst().prefix(while: { $0 <= end }).last { index in
      routeEdges[index - 1].successorEdgeIDs.contains { $0 != routeEdges[index].id }
    } ?? 0
  }

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
    let routeEdgeIDs = Set(routeEdges.map(\.id))
    // A road the plan drives on another pass is still a choice here: on a
    // route that ends beside its start, the road past the exit is the plan.
    let exitSideStartIndex = Self.lastChoiceIndex(routeEdges, through: routeEdges.count - 1)
    self.exitSideStartIndex = exitSideStartIndex
    let exit = routeEdges[exitSideStartIndex...].flatMap(\.coordinates)
    self.exit = exit
    let exitRoadIDs = last.successorEdgeIDs.filter { !routeEdgeIDs.contains($0) }
    var pastEndIDs: Set<String> = []
    var pending = Array(exitRoadIDs)
    while let edgeID = pending.popLast() {
      guard pastEndIDs.insert(edgeID).inserted, let edge = edgesByID[edgeID] else { continue }
      pending += edge.successorEdgeIDs
    }
    let exitEdgeIDs = Set(routeEdges[exitSideStartIndex...].map(\.id))
    var rampIDs: Set<String> = []
    pending = Array(corridor.exitRampEdgeIDs)
    while let edgeID = pending.popLast() {
      guard !routeEdgeIDs.contains(edgeID), !pastEndIDs.contains(edgeID),
        rampIDs.insert(edgeID).inserted, let edge = edgesByID[edgeID]
      else { continue }
      pending += edge.successorEdgeIDs
    }
    var leftRoad: [String: [MatcherCoordinate]] = [:]
    pending =
      exitSideStartIndex > 0
      ? Array(routeEdges[exitSideStartIndex - 1].successorEdgeIDs) : []
    while let edgeID = pending.popLast() {
      guard !routeEdgeIDs.contains(edgeID), !pastEndIDs.contains(edgeID),
        !rampIDs.contains(edgeID), leftRoad[edgeID] == nil,
        let edge = edgesByID[edgeID]
      else { continue }
      leftRoad[edgeID] = edge.coordinates
      pending += edge.successorEdgeIDs
    }
    roadLeftAtLastChoice = leftRoad
    // From the plan's end backwards, each road takes the latest occurrence
    // that leads to it; one already taken is reached from later on, and so
    // is everything it leads to.
    var lastReachingIndex: [String: Int] = [:]
    for index in routeEdges.indices.reversed() {
      pending = [routeEdges[index].id]
      while let edgeID = pending.popLast() {
        guard lastReachingIndex[edgeID] == nil, let edge = edgesByID[edgeID] else { continue }
        lastReachingIndex[edgeID] = index
        pending += edge.successorEdgeIDs
      }
    }
    exitRoadEdgeIDs = exitEdgeIDs.union(pastEndIDs).union(rampIDs)
    exitRamps = corridor.edges.compactMap {
      guard rampIDs.contains($0.id), let reachingIndex = lastReachingIndex[$0.id] else { return nil }
      return ($0.coordinates, reachingIndex)
    }
    otherRoads = corridor.edges.compactMap {
      guard !exitEdgeIDs.contains($0.id), !pastEndIDs.contains($0.id), !rampIDs.contains($0.id),
        let reachingIndex = lastReachingIndex[$0.id]
      else { return nil }
      return ($0.coordinates, reachingIndex)
    }
    roadEnds = corridor.edges.compactMap {
      guard !routeEdgeIDs.contains($0.id), !exitRoadIDs.contains($0.id), !rampIDs.contains($0.id),
        $0.successorEdgeIDs.isEmpty, let end = $0.coordinates.last,
        let reachingIndex = lastReachingIndex[$0.id]
      else { return nil }
      return (end, Self.meters(from: end, toPolyline: exit), reachingIndex)
    }
    departures = corridor.edges.flatMap { edge -> [(point: MatcherCoordinate, lastReachingIndex: Int)] in
      guard !routeEdgeIDs.contains(edge.id), !exitRoadIDs.contains(edge.id), !rampIDs.contains(edge.id),
        edge.successorEdgeIDs.isEmpty, let end = edge.coordinates.last,
        let reachingIndex = lastReachingIndex[edge.id]
      else { return [] }
      return (corridor.onwardExitPoints[edge.id] ?? [end]).map { ($0, reachingIndex) }
    }
  }

  /// How close to the exit the corridor holds every road a car at
  /// `progressIndex` could be on instead of it: the nearest point where it
  /// stops following one. Within this distance a fix matching no corridor
  /// road is on none of them.
  func exitCoverageMeters(fromProgress progressIndex: Int) -> Double {
    roadEnds.filter { $0.lastReachingIndex >= earliestCarIndex(progressIndex) }
      .map(\.metersFromExit).min() ?? .infinity
  }

  /// Admitted progress can run ahead of a car that missed the exit, along
  /// the ramp beside the road it leaves or onto a coarse fix further on, so
  /// past the last choice of road it says nothing about which road the car
  /// took. The car may be anywhere from the matcher's longitudinal window
  /// behind progress, or behind that last choice once progress is past it.
  private func earliestCarIndex(_ progressIndex: Int) -> Int {
    min(progressIndex, exitSideStartIndex)
      - RouteMatcherCorridor.longitudinalCandidateOccurrenceWindow
  }

  /// Whether one of the roads a car at `progressIndex` could be on instead
  /// of the exit runs within `toleranceDegrees` of the course, within
  /// `meters` of the point.
  func runsAlongOtherRoad(
    _ coordinate: MatcherCoordinate,
    courseDegrees: Double,
    toleranceDegrees: Double,
    withinMeters meters: Double,
    fromProgress progressIndex: Int
  ) -> Bool {
    otherRoads.filter { $0.lastReachingIndex >= earliestCarIndex(progressIndex) }.contains { road in
      zip(road.coordinates, road.coordinates.dropFirst()).contains { start, end in
        Self.meters(from: coordinate, toPolyline: [start, end]) <= meters
          && Self.runs(from: start, to: end, within: toleranceDegrees, of: courseDegrees)
      }
    }
  }

  /// Whether a car at `coordinate` driving at `courseDegrees` is driving
  /// along the road the plan leaves at its last choice, on its edge
  /// `edgeID`.
  func isDrivingAlongRoadLeftAtLastChoice(
    _ edgeID: String,
    at coordinate: MatcherCoordinate,
    courseDegrees: Double,
    toleranceDegrees: Double
  ) -> Bool {
    guard let coordinates = roadLeftAtLastChoice[edgeID] else { return false }
    return Self.isDrivingAlong(
      coordinates, at: coordinate, courseDegrees: courseDegrees, toleranceDegrees: toleranceDegrees
    )
  }

  /// Whether a car at `coordinate` driving at `courseDegrees` drives along
  /// the road `coordinates` draws, at its segment nearest the point.
  static func isDrivingAlong(
    _ coordinates: [MatcherCoordinate],
    at coordinate: MatcherCoordinate,
    courseDegrees: Double,
    toleranceDegrees: Double
  ) -> Bool {
    let segments = Array(zip(coordinates, coordinates.dropFirst()))
    guard
      let nearest = segments.min(by: {
        meters(from: coordinate, toPolyline: [$0.0, $0.1])
          < meters(from: coordinate, toPolyline: [$1.0, $1.1])
      })
    else { return false }
    return runs(from: nearest.0, to: nearest.1, within: toleranceDegrees, of: courseDegrees)
  }

  /// Whether the course runs along the road anywhere within `windowMeters`
  /// along it of where the point projects onto `coordinates`: on a curving
  /// ramp, scatter along the road puts the fix nearest a segment whose chord
  /// points 20-30 deg away from the heading at the car. The window reaches
  /// into the edge's predecessors (`before`) and successors (`after`).
  static func isDrivingAlong(
    _ coordinates: [MatcherCoordinate],
    before: [[MatcherCoordinate]],
    after: [[MatcherCoordinate]],
    at coordinate: MatcherCoordinate,
    windowMeters: Double,
    courseDegrees: Double,
    toleranceDegrees: Double
  ) -> Bool {
    let segments = Array(zip(coordinates, coordinates.dropFirst()))
    guard
      let nearest = segments.indices.min(by: {
        meters(from: coordinate, toPolyline: [segments[$0].0, segments[$0].1])
          < meters(from: coordinate, toPolyline: [segments[$1].0, segments[$1].1])
      })
    else { return false }
    let lengths = segments.map { segment in
      let offset = planarOffset(from: segment.0, to: segment.1)
      return hypot(offset.east, offset.north)
    }
    let starts = lengths.indices.map { lengths[..<$0].reduce(0, +) }
    let total = lengths.reduce(0, +)
    let point = planarOffset(from: segments[nearest].0, to: coordinate)
    let direction = planarOffset(from: segments[nearest].0, to: segments[nearest].1)
    let squared = direction.east * direction.east + direction.north * direction.north
    let fraction =
      squared > 0
      ? min(1, max(0, (point.east * direction.east + point.north * direction.north) / squared))
      : 0
    let along = starts[nearest] + lengths[nearest] * fraction
    let runsAlong = { (segment: (MatcherCoordinate, MatcherCoordinate)) in
      runs(from: segment.0, to: segment.1, within: toleranceDegrees, of: courseDegrees)
    }
    if segments.indices.contains(where: { index in
      starts[index] + lengths[index] >= along - windowMeters
        && starts[index] <= along + windowMeters && runsAlong(segments[index])
    }) {
      return true
    }
    func reaches(_ road: [(MatcherCoordinate, MatcherCoordinate)], within reach: Double) -> Bool {
      var remaining = reach
      for segment in road where remaining > 0 {
        if runsAlong(segment) { return true }
        let offset = planarOffset(from: segment.0, to: segment.1)
        remaining -= hypot(offset.east, offset.north)
      }
      return false
    }
    if along - windowMeters < 0,
      before.contains(where: { reaches(Array(zip($0, $0.dropFirst())).reversed(), within: windowMeters - along) })
    {
      return true
    }
    return along + windowMeters > total
      && after.contains(where: { reaches(Array(zip($0, $0.dropFirst())), within: along + windowMeters - total) })
  }

  private static func runs(
    from start: MatcherCoordinate,
    to end: MatcherCoordinate,
    within toleranceDegrees: Double,
    of courseDegrees: Double
  ) -> Bool {
    let offset = planarOffset(from: start, to: end)
    guard offset.east != 0 || offset.north != 0 else { return false }
    let bearing = atan2(offset.east, offset.north) * 180 / .pi
    let difference = abs(courseDegrees - bearing).truncatingRemainder(dividingBy: 360)
    return min(difference, 360 - difference) <= toleranceDegrees
  }

  /// Whether a point lies beside the plan after its last choice of road
  /// rather than past its end: nearer some point of it than its end by more
  /// than `toleranceMeters`. Where the exit curves, a point well past its end
  /// can lie a metre nearer a bend than the end itself.
  func isAlongExit(_ coordinate: MatcherCoordinate, toleranceMeters: Double = 1) -> Bool {
    guard let end = exit.last else { return false }
    return Self.meters(from: coordinate, toPolyline: exit) + toleranceMeters
      < Self.meters(from: coordinate, toPolyline: [end, end])
  }

  /// Whether a road is one of the exit's: from here the only way off the
  /// expressway is the planned exit.
  func isOnExit(_ edgeID: String) -> Bool {
    exitRoadEdgeIDs.contains(edgeID)
  }

  /// Distance from a point to the plan after its last choice of road, or to
  /// another ramp of its exit a car at `progressIndex` can be on.
  func metersFromExit(_ coordinate: MatcherCoordinate, fromProgress progressIndex: Int) -> Double {
    exitRamps.filter { $0.lastReachingIndex >= earliestCarIndex(progressIndex) }
      .map { Self.meters(from: coordinate, toPolyline: $0.coordinates) }
      .reduce(Self.meters(from: coordinate, toPolyline: exit), min)
  }

  /// Distance from a point to the nearest place a car at `progressIndex`
  /// could have left the expressway instead of by the exit: off every
  /// expressway road, it left by the exit or at one of those places, not
  /// along a road that carries on beside it, and not where the corridor
  /// merely stops following a road the network carries on.
  func metersFromOtherDepartures(
    _ coordinate: MatcherCoordinate,
    fromProgress progressIndex: Int
  ) -> Double {
    departures.filter { $0.lastReachingIndex >= earliestCarIndex(progressIndex) }
      .map { Self.meters(from: coordinate, toPolyline: [$0.point, $0.point]) }.min() ?? .infinity
  }

  /// Distance from a point to the nearest road a car at `progressIndex`
  /// could be on instead of the exit.
  func metersFromOtherRoads(
    _ coordinate: MatcherCoordinate,
    fromProgress progressIndex: Int
  ) -> Double {
    otherRoads.filter { $0.lastReachingIndex >= earliestCarIndex(progressIndex) }
      .map { Self.meters(from: coordinate, toPolyline: $0.coordinates) }.min() ?? .infinity
  }

  static func meters(
    from coordinate: MatcherCoordinate,
    toPolyline polyline: [MatcherCoordinate]
  ) -> Double {
    let points = polyline.map { planarOffset(from: coordinate, to: $0) }
    return zip(points, points.dropFirst()).map { start, end in
      let segment = (east: end.east - start.east, north: end.north - start.north)
      let squared = segment.east * segment.east + segment.north * segment.north
      let fraction =
        squared > 0
        ? min(1, max(0, -(start.east * segment.east + start.north * segment.north) / squared))
        : 0
      return hypot(start.east + segment.east * fraction, start.north + segment.north * fraction)
    }.min() ?? .infinity
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
