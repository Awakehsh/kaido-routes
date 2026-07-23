import Foundation
import KaidoDomain

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
  private let routePlan: RoutePlan
  private let matcherCorridor: RouteMatcherCorridor
  private let guidanceTargetByAnchorOccurrence: [String: DecisionZoneProgressDefinition]

  public init(
    navigationConfiguration: NavigationConfiguration,
    matcherCorridor: RouteMatcherCorridor,
    decisionZones: [DecisionZoneProgressDefinition],
    initialNavigationSnapshot: NavigationSnapshot = NavigationSnapshot(),
    matcherConfiguration: RouteAwareSwiftMatcherConfiguration = .init(),
    matcherSessionConfiguration: RouteMatcherSessionConfiguration = .init(),
    initialMatcherOccurrenceID: String? = nil
  ) throws {
    guard let routePlan = navigationConfiguration.routePlan else {
      throw NavigationSessionConfigurationError.invalid(["route plan is missing"])
    }
    let issues = NavigationRuntimeConfigurationValidator.issues(
      routePlan: routePlan,
      matcherCorridor: matcherCorridor,
      decisionZones: decisionZones,
      releasedGuidance: navigationConfiguration.releasedGuidance
    )
    guard issues.isEmpty else {
      throw NavigationSessionConfigurationError.invalid(issues)
    }

    self.routePlan = routePlan
    self.matcherCorridor = matcherCorridor
    guidanceTargetByAnchorOccurrence = Self.guidanceTargets(
      decisionZones: decisionZones,
      releasedGuidance: navigationConfiguration.releasedGuidance
    )
    engine = NavigationEngine(
      configuration: navigationConfiguration,
      initialSnapshot: initialNavigationSnapshot
    )
    matcherSession = try RouteAwareSwiftMatcher(
      configuration: matcherConfiguration
    ).makeSession(
      corridor: matcherCorridor,
      sessionConfiguration: matcherSessionConfiguration,
      initialOccurrenceID: initialMatcherOccurrenceID
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
    let estimate = try matcherSession.observe(observation)
    engine.observeLocation(
      Self.locationObservation(from: estimate, source: observation)
    )

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
    source observation: RouteMatcherObservation
  ) -> LocationObservation {
    let candidateResolution: RouteCandidateResolution
    if estimate.directedEdgeID != nil, estimate.candidateEdgeIDs.count == 1 {
      candidateResolution = .resolved
    } else if estimate.candidateEdgeIDs.count > 1 {
      candidateResolution = .ambiguous
    } else {
      candidateResolution = .unknown
    }
    return LocationObservation(
      directedEdgeID: estimate.directedEdgeID,
      matchedEntityID: estimate.directedEdgeID,
      matchedOccurrenceID: estimate.occurrenceID,
      candidateOccurrenceIDs: Set([estimate.occurrenceID].compactMap { $0 }),
      candidateResolution: candidateResolution,
      observedAtMilliseconds: observation.observedAtMilliseconds,
      reportedConfidence: LocationConfidence(rawValue: estimate.confidence.rawValue) ?? .lost,
      horizontalAccuracyMeters: observation.horizontalAccuracyMeters,
      ageMilliseconds: observation.receivedAtMilliseconds
        - observation.observedAtMilliseconds,
      forwardContinuity: false
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
