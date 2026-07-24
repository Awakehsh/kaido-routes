import Foundation
import KaidoDomain

public enum NavigationSessionCheckpointIssue: Equatable, Hashable, Sendable {
  case invalidSchemaVersion
  case invalidIdentity(String)
  case identityMismatch(String)
  case invalidSavedAtMilliseconds
  case activeRoutePlanMismatch
  case missingCurrentOccurrence
  case unknownOccurrence(String, String)
  case duplicateOccurrence(String, String)
  case inconsistentOccurrenceProgress
  case unknownGuidancePrompt(String)
  case duplicateGuidancePrompt(String)
  case invalidLastGuidancePrompt
  case invalidGuidanceTimestamp
  case invalidRouteExecutionState
  case invalidSafetyState
  case invalidRecoveryState
  case invalidEgressState
  case destinationRerouteUsed

  public var code: String {
    switch self {
    case .invalidSchemaVersion:
      "INVALID_CHECKPOINT_SCHEMA_VERSION"
    case .invalidIdentity:
      "INVALID_CHECKPOINT_IDENTITY"
    case .identityMismatch:
      "CHECKPOINT_RELEASE_IDENTITY_MISMATCH"
    case .invalidSavedAtMilliseconds:
      "INVALID_CHECKPOINT_SAVED_AT"
    case .activeRoutePlanMismatch:
      "CHECKPOINT_ACTIVE_ROUTE_PLAN_MISMATCH"
    case .missingCurrentOccurrence:
      "CHECKPOINT_CURRENT_OCCURRENCE_MISSING"
    case .unknownOccurrence:
      "CHECKPOINT_UNKNOWN_OCCURRENCE"
    case .duplicateOccurrence:
      "CHECKPOINT_DUPLICATE_OCCURRENCE"
    case .inconsistentOccurrenceProgress:
      "CHECKPOINT_OCCURRENCE_PROGRESS_INCONSISTENT"
    case .unknownGuidancePrompt:
      "CHECKPOINT_UNKNOWN_GUIDANCE_PROMPT"
    case .duplicateGuidancePrompt:
      "CHECKPOINT_DUPLICATE_GUIDANCE_PROMPT"
    case .invalidLastGuidancePrompt:
      "CHECKPOINT_LAST_GUIDANCE_PROMPT_INVALID"
    case .invalidGuidanceTimestamp:
      "CHECKPOINT_GUIDANCE_TIMESTAMP_INVALID"
    case .invalidRouteExecutionState:
      "CHECKPOINT_ROUTE_EXECUTION_STATE_INVALID"
    case .invalidSafetyState:
      "CHECKPOINT_SAFETY_STATE_INVALID"
    case .invalidRecoveryState:
      "CHECKPOINT_RECOVERY_STATE_INVALID"
    case .invalidEgressState:
      "CHECKPOINT_EGRESS_STATE_INVALID"
    case .destinationRerouteUsed:
      "CHECKPOINT_DESTINATION_REROUTE_FORBIDDEN"
    }
  }

  fileprivate var sortKey: String {
    switch self {
    case .invalidIdentity(let field), .identityMismatch(let field):
      "\(code):\(field)"
    case .unknownOccurrence(let field, let occurrenceID),
      .duplicateOccurrence(let field, let occurrenceID):
      "\(code):\(field):\(occurrenceID)"
    case .unknownGuidancePrompt(let promptID),
      .duplicateGuidancePrompt(let promptID):
      "\(code):\(promptID)"
    default:
      code
    }
  }
}

public enum NavigationSessionCheckpointError: Error, Equatable, Sendable {
  case invalid([NavigationSessionCheckpointIssue])
}

/// Coordinate-free reducer state retained across one process lifecycle.
///
/// Location, matcher posterior, entry-transition partial evidence, CarPlay
/// connection state, active guidance geometry, and transient speech authority
/// are deliberately excluded.
public struct NavigationSessionCheckpointState: Codable, Equatable, Sendable {
  public let journeyPhase: JourneyPhase
  public let lastPhaseTransitionTrigger: String?
  public let activeRoutePlanID: String?
  public let currentOccurrenceID: String?
  public let skippedOccurrenceIDs: [String]
  public let strictRouteAutoCommitAllowed: Bool
  public let routeExecutable: Bool
  public let routeWarnings: [String]
  public let routeBlockingReasons: [String]
  public let routeBlockingOccurrenceIDs: [String]
  public let recovery: RecoveryState
  public let egress: EgressState
  public let lastGuidanceProgressAtMilliseconds: Int?
  public let emittedGuidancePromptIDs: [String]
  public let lastGuidancePromptID: String?
  public let prohibitedGuidanceActions: [String]
  public let requiresRouteEditingWhileMoving: Bool
  public let showsEntryRouteShieldAndDirection: Bool
  public let finishConfirmationExitFacilityID: String?

  public init(
    journeyPhase: JourneyPhase,
    lastPhaseTransitionTrigger: String? = nil,
    activeRoutePlanID: String?,
    currentOccurrenceID: String?,
    skippedOccurrenceIDs: [String] = [],
    strictRouteAutoCommitAllowed: Bool,
    routeExecutable: Bool,
    routeWarnings: [String] = [],
    routeBlockingReasons: [String] = [],
    routeBlockingOccurrenceIDs: [String] = [],
    recovery: RecoveryState = RecoveryState(),
    egress: EgressState = EgressState(),
    lastGuidanceProgressAtMilliseconds: Int? = nil,
    emittedGuidancePromptIDs: [String] = [],
    lastGuidancePromptID: String? = nil,
    prohibitedGuidanceActions: [String] = [],
    requiresRouteEditingWhileMoving: Bool = false,
    showsEntryRouteShieldAndDirection: Bool = true,
    finishConfirmationExitFacilityID: String? = nil
  ) {
    self.journeyPhase = journeyPhase
    self.lastPhaseTransitionTrigger = lastPhaseTransitionTrigger
    self.activeRoutePlanID = activeRoutePlanID
    self.currentOccurrenceID = currentOccurrenceID
    self.skippedOccurrenceIDs = skippedOccurrenceIDs
    self.strictRouteAutoCommitAllowed = strictRouteAutoCommitAllowed
    self.routeExecutable = routeExecutable
    self.routeWarnings = routeWarnings
    self.routeBlockingReasons = routeBlockingReasons
    self.routeBlockingOccurrenceIDs = routeBlockingOccurrenceIDs
    self.recovery = recovery
    self.egress = egress
    self.lastGuidanceProgressAtMilliseconds =
      lastGuidanceProgressAtMilliseconds
    self.emittedGuidancePromptIDs = emittedGuidancePromptIDs
    self.lastGuidancePromptID = lastGuidancePromptID
    self.prohibitedGuidanceActions = prohibitedGuidanceActions
    self.requiresRouteEditingWhileMoving =
      requiresRouteEditingWhileMoving
    self.showsEntryRouteShieldAndDirection =
      showsEntryRouteShieldAndDirection
    self.finishConfirmationExitFacilityID =
      finishConfirmationExitFacilityID
  }

  fileprivate init(snapshot: NavigationSnapshot) {
    self.init(
      journeyPhase: snapshot.journeyPhase,
      lastPhaseTransitionTrigger: snapshot.lastPhaseTransitionTrigger,
      activeRoutePlanID: snapshot.activeRoutePlanID,
      currentOccurrenceID: snapshot.currentOccurrenceID,
      skippedOccurrenceIDs: snapshot.skippedOccurrenceIDs,
      strictRouteAutoCommitAllowed:
        snapshot.strictRouteAutoCommitAllowed,
      routeExecutable: snapshot.routeExecutable,
      routeWarnings: snapshot.routeWarnings,
      routeBlockingReasons: snapshot.routeBlockingReasons,
      routeBlockingOccurrenceIDs: snapshot.routeBlockingOccurrenceIDs,
      recovery: snapshot.recovery,
      egress: snapshot.egress,
      lastGuidanceProgressAtMilliseconds:
        snapshot.lastGuidanceProgressAtMilliseconds,
      emittedGuidancePromptIDs: snapshot.emittedGuidancePromptIDs,
      lastGuidancePromptID: snapshot.lastGuidancePromptID,
      prohibitedGuidanceActions: snapshot.prohibitedGuidanceActions,
      requiresRouteEditingWhileMoving:
        snapshot.requiresRouteEditingWhileMoving,
      showsEntryRouteShieldAndDirection:
        snapshot.showsEntryRouteShieldAndDirection,
      finishConfirmationExitFacilityID:
        snapshot.finishConfirmationExitFacilityID
    )
  }

  private enum CodingKeys: String, CodingKey {
    case journeyPhase = "journey_phase"
    case lastPhaseTransitionTrigger = "last_phase_transition_trigger"
    case activeRoutePlanID = "active_route_plan_id"
    case currentOccurrenceID = "current_occurrence_id"
    case skippedOccurrenceIDs = "skipped_occurrence_ids"
    case strictRouteAutoCommitAllowed = "strict_route_auto_commit_allowed"
    case routeExecutable = "route_executable"
    case routeWarnings = "route_warnings"
    case routeBlockingReasons = "route_blocking_reasons"
    case routeBlockingOccurrenceIDs = "route_blocking_occurrence_ids"
    case recovery
    case egress
    case lastGuidanceProgressAtMilliseconds =
      "last_guidance_progress_at_milliseconds"
    case emittedGuidancePromptIDs = "emitted_guidance_prompt_ids"
    case lastGuidancePromptID = "last_guidance_prompt_id"
    case prohibitedGuidanceActions = "prohibited_guidance_actions"
    case requiresRouteEditingWhileMoving =
      "requires_route_editing_while_moving"
    case showsEntryRouteShieldAndDirection =
      "shows_entry_route_shield_and_direction"
    case finishConfirmationExitFacilityID =
      "finish_confirmation_exit_facility_id"
  }
}

/// Versioned, release-bound process-restoration envelope.
public struct NavigationSessionCheckpoint: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = "1.0"

  public let schemaVersion: String
  public let productReleaseID: String
  public let navigationReleaseID: String
  public let runtimePolicyID: String
  public let networkSnapshotID: String
  public let routePlanID: String
  public let matcherCorridorID: String
  public let savedAtMilliseconds: Int
  public let state: NavigationSessionCheckpointState

  public init(
    schemaVersion: String = NavigationSessionCheckpoint.currentSchemaVersion,
    productReleaseID: String,
    navigationReleaseID: String,
    runtimePolicyID: String,
    networkSnapshotID: String,
    routePlanID: String,
    matcherCorridorID: String,
    savedAtMilliseconds: Int,
    state: NavigationSessionCheckpointState
  ) {
    self.schemaVersion = schemaVersion
    self.productReleaseID = productReleaseID
    self.navigationReleaseID = navigationReleaseID
    self.runtimePolicyID = runtimePolicyID
    self.networkSnapshotID = networkSnapshotID
    self.routePlanID = routePlanID
    self.matcherCorridorID = matcherCorridorID
    self.savedAtMilliseconds = savedAtMilliseconds
    self.state = state
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case productReleaseID = "product_release_id"
    case navigationReleaseID = "navigation_release_id"
    case runtimePolicyID = "runtime_policy_id"
    case networkSnapshotID = "network_snapshot_id"
    case routePlanID = "route_plan_id"
    case matcherCorridorID = "matcher_corridor_id"
    case savedAtMilliseconds = "saved_at_milliseconds"
    case state
  }
}

public enum NavigationSessionCheckpointCodec {
  public static func encode(
    _ checkpoint: NavigationSessionCheckpoint
  ) throws -> Data {
    let issues = structuralIssues(checkpoint)
    guard issues.isEmpty else {
      throw NavigationSessionCheckpointError.invalid(issues)
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(checkpoint)
  }

  public static func decode(
    _ data: Data
  ) throws -> NavigationSessionCheckpoint {
    let checkpoint = try JSONDecoder().decode(
      NavigationSessionCheckpoint.self,
      from: data
    )
    let issues = structuralIssues(checkpoint)
    guard issues.isEmpty else {
      throw NavigationSessionCheckpointError.invalid(issues)
    }
    return checkpoint
  }

  private static func structuralIssues(
    _ checkpoint: NavigationSessionCheckpoint
  ) -> [NavigationSessionCheckpointIssue] {
    var issues: [NavigationSessionCheckpointIssue] = []
    if checkpoint.schemaVersion
      != NavigationSessionCheckpoint.currentSchemaVersion
    {
      issues.append(.invalidSchemaVersion)
    }
    for (field, value) in [
      ("product_release_id", checkpoint.productReleaseID),
      ("navigation_release_id", checkpoint.navigationReleaseID),
      ("runtime_policy_id", checkpoint.runtimePolicyID),
      ("network_snapshot_id", checkpoint.networkSnapshotID),
      ("route_plan_id", checkpoint.routePlanID),
      ("matcher_corridor_id", checkpoint.matcherCorridorID),
    ] where normalized(value).isEmpty {
      issues.append(.invalidIdentity(field))
    }
    if checkpoint.savedAtMilliseconds < 0 {
      issues.append(.invalidSavedAtMilliseconds)
    }
    return sorted(issues)
  }

  fileprivate static func sorted(
    _ issues: [NavigationSessionCheckpointIssue]
  ) -> [NavigationSessionCheckpointIssue] {
    Array(Set(issues)).sorted { $0.sortKey < $1.sortKey }
  }

  fileprivate static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

extension NavigationSessionCheckpoint {
  package static func capture(
    release: KaidoProductRelease,
    snapshot: NavigationSnapshot,
    savedAtMilliseconds: Int
  ) throws -> NavigationSessionCheckpoint {
    let bundle = release.navigation.bundle
    let checkpoint = NavigationSessionCheckpoint(
      productReleaseID: release.releaseID,
      navigationReleaseID: release.navigation.releaseID,
      runtimePolicyID: bundle.runtimePolicy.id,
      networkSnapshotID: bundle.networkSnapshot.id,
      routePlanID: bundle.routePlan.id,
      matcherCorridorID: bundle.matcherCorridor.id,
      savedAtMilliseconds: savedAtMilliseconds,
      state: NavigationSessionCheckpointState(snapshot: snapshot)
    )
    let issues = checkpoint.validationIssues(for: release)
    guard issues.isEmpty else {
      throw NavigationSessionCheckpointError.invalid(issues)
    }
    return checkpoint
  }

  package func restoredSnapshot(
    for release: KaidoProductRelease
  ) throws -> NavigationSnapshot {
    let issues = validationIssues(for: release)
    guard issues.isEmpty else {
      throw NavigationSessionCheckpointError.invalid(issues)
    }

    let routePlan = release.navigation.bundle.routePlan
    let restoredPhase: JourneyPhase =
      state.journeyPhase == .entryTransition
      ? .approachToEntry
      : state.journeyPhase
    var snapshot = NavigationSnapshot(
      journeyPhase: restoredPhase,
      activeRoutePlanID: routePlan.id,
      currentOccurrenceID: state.currentOccurrenceID,
      locationConfidence: .lost
    )
    snapshot.lastPhaseTransitionTrigger =
      state.journeyPhase == .entryTransition
      ? "SESSION_RESTORED_ENTRY_EVIDENCE_RESET"
      : state.lastPhaseTransitionTrigger
    if let currentOccurrenceID = state.currentOccurrenceID,
      let current = routePlan.occurrence(id: currentOccurrenceID)
    {
      snapshot.currentOccurrenceIndex = current.index
      snapshot.completedOccurrenceIDs = routePlan.occurrences
        .filter {
          $0.index < current.index
            && !state.skippedOccurrenceIDs.contains($0.id)
        }
        .map(\.id)
      snapshot.pendingOccurrenceIDs = routePlan.occurrences
        .filter {
          $0.index >= current.index
            && !state.skippedOccurrenceIDs.contains($0.id)
        }
        .map(\.id)
    }
    snapshot.skippedOccurrenceIDs = state.skippedOccurrenceIDs
    snapshot.markerStyle = "ESTIMATED"
    snapshot.ambiguityReason =
      requiresMatcherReacquisition
      ? "SESSION_RESTORATION_REACQUISITION_REQUIRED"
      : nil
    snapshot.signalReacquisitionStatus =
      requiresMatcherReacquisition ? .pending : .inactive
    snapshot.signalReacquisitionTrigger =
      requiresMatcherReacquisition ? "SESSION_RESTORED" : nil
    snapshot.routeCandidateResolution = .unknown
    snapshot.strictRouteAutoCommitAllowed =
      restoredPhase == .approachToEntry
      ? false
      : state.strictRouteAutoCommitAllowed
    snapshot.routeExecutable = state.routeExecutable
    snapshot.routeWarnings = state.routeWarnings
    snapshot.routeBlockingReasons = state.routeBlockingReasons
    snapshot.routeBlockingOccurrenceIDs =
      state.routeBlockingOccurrenceIDs
    snapshot.recovery = state.recovery
    snapshot.egress = state.egress
    snapshot.guidanceAnchorStatus = .inactive
    snapshot.guidancePlanningStatus = .inactive
    snapshot.activeGuidanceFrame = nil
    snapshot.lastGuidanceProgressAtMilliseconds =
      state.lastGuidanceProgressAtMilliseconds
    snapshot.emittedGuidancePromptIDs =
      state.emittedGuidancePromptIDs
    snapshot.lastGuidancePromptID = state.lastGuidancePromptID
    snapshot.presentationSurface = .iPhone
    snapshot.carPlayConnectionState = .disconnected
    snapshot.lastPresentationTransitionTrigger = "SESSION_RESTORED"
    snapshot.prohibitedGuidanceActions =
      state.prohibitedGuidanceActions
    snapshot.requiresRouteEditingWhileMoving =
      state.requiresRouteEditingWhileMoving
    snapshot.requiresPhoneTouchWhileMoving = false
    snapshot.showsEntryRouteShieldAndDirection =
      state.showsEntryRouteShieldAndDirection
    snapshot.finishConfirmationExitFacilityID =
      state.finishConfirmationExitFacilityID
    return snapshot
  }

  package var requiresMatcherReacquisition: Bool {
    switch state.journeyPhase {
    case .strictRoute, .routeRecovery, .exitTransition, .surfaceEgress:
      true
    case .planning, .approachToEntry, .entryTransition, .completed:
      false
    }
  }

  package func validationIssues(
    for release: KaidoProductRelease
  ) -> [NavigationSessionCheckpointIssue] {
    var issues: [NavigationSessionCheckpointIssue] = []
    let bundle = release.navigation.bundle
    for (field, actual, expected) in [
      ("product_release_id", productReleaseID, release.releaseID),
      (
        "navigation_release_id",
        navigationReleaseID,
        release.navigation.releaseID
      ),
      ("runtime_policy_id", runtimePolicyID, bundle.runtimePolicy.id),
      ("network_snapshot_id", networkSnapshotID, bundle.networkSnapshot.id),
      ("route_plan_id", routePlanID, bundle.routePlan.id),
      (
        "matcher_corridor_id",
        matcherCorridorID,
        bundle.matcherCorridor.id
      ),
    ] where actual != expected {
      issues.append(.identityMismatch(field))
    }
    if schemaVersion != NavigationSessionCheckpoint.currentSchemaVersion {
      issues.append(.invalidSchemaVersion)
    }
    if savedAtMilliseconds < 0 {
      issues.append(.invalidSavedAtMilliseconds)
    }
    if state.activeRoutePlanID != bundle.routePlan.id {
      issues.append(.activeRoutePlanMismatch)
    }

    let occurrenceIDs = Set(bundle.routePlan.occurrences.map(\.id))
    let requiresCurrentOccurrence: Bool
    switch state.journeyPhase {
    case .strictRoute, .routeRecovery, .exitTransition, .surfaceEgress:
      requiresCurrentOccurrence = true
    case .planning, .approachToEntry, .entryTransition, .completed:
      requiresCurrentOccurrence = false
    }
    if requiresCurrentOccurrence && state.currentOccurrenceID == nil {
      issues.append(.missingCurrentOccurrence)
    }
    if let currentOccurrenceID = state.currentOccurrenceID,
      !occurrenceIDs.contains(currentOccurrenceID)
    {
      issues.append(
        .unknownOccurrence("current_occurrence_id", currentOccurrenceID)
      )
    }
    validateOccurrences(
      state.skippedOccurrenceIDs,
      field: "skipped_occurrence_ids",
      known: occurrenceIDs,
      issues: &issues
    )
    validateOccurrences(
      state.routeBlockingOccurrenceIDs,
      field: "route_blocking_occurrence_ids",
      known: occurrenceIDs,
      issues: &issues
    )
    if let currentOccurrenceID = state.currentOccurrenceID,
      state.skippedOccurrenceIDs.contains(currentOccurrenceID)
    {
      issues.append(.inconsistentOccurrenceProgress)
    }
    let strictRoutePhases: [JourneyPhase] = [
      .strictRoute,
      .routeRecovery,
      .exitTransition,
      .surfaceEgress,
    ]
    if state.strictRouteAutoCommitAllowed,
      !strictRoutePhases.contains(state.journeyPhase)
    {
      issues.append(.invalidRouteExecutionState)
    }
    if state.routeExecutable {
      if !state.routeBlockingReasons.isEmpty
        || !state.routeBlockingOccurrenceIDs.isEmpty
      {
        issues.append(.invalidRouteExecutionState)
      }
    } else if state.routeBlockingReasons.isEmpty
      || state.routeBlockingOccurrenceIDs.isEmpty
    {
      issues.append(.invalidRouteExecutionState)
    }
    if state.requiresRouteEditingWhileMoving
      || !state.showsEntryRouteShieldAndDirection
    {
      issues.append(.invalidSafetyState)
    }

    let promptIDs = Set(bundle.releasedGuidance.map(\.anchor.promptID))
    var seenPromptIDs: Set<String> = []
    for promptID in state.emittedGuidancePromptIDs {
      if !promptIDs.contains(promptID) {
        issues.append(.unknownGuidancePrompt(promptID))
      }
      if !seenPromptIDs.insert(promptID).inserted {
        issues.append(.duplicateGuidancePrompt(promptID))
      }
    }
    if state.lastGuidancePromptID
      != state.emittedGuidancePromptIDs.last
    {
      issues.append(.invalidLastGuidancePrompt)
    }
    if let timestamp = state.lastGuidanceProgressAtMilliseconds,
      timestamp < 0 || timestamp > savedAtMilliseconds
    {
      issues.append(.invalidGuidanceTimestamp)
    }

    if state.recovery.destinationRerouteUsed {
      issues.append(.destinationRerouteUsed)
    }
    switch state.recovery.status {
    case .inactive:
      if state.recovery.objective != nil
        || state.recovery.routePlanID != nil
        || state.recovery.chosenRejoinOccurrenceID != nil
      {
        issues.append(.invalidRecoveryState)
      }
    case .active, .unavailable:
      if state.recovery.routePlanID != bundle.routePlan.id
        || state.recovery.objective != "REJOIN_ACTIVE_ROUTE_PLAN"
      {
        issues.append(.invalidRecoveryState)
      }
      if state.recovery.status == .active {
        let validActiveRecovery: Bool
        if let chosen = state.recovery.chosenRejoinOccurrenceID,
          let target = bundle.routePlan.occurrence(id: chosen),
          let currentID = state.currentOccurrenceID,
          let current = bundle.routePlan.occurrence(id: currentID)
        {
          validActiveRecovery =
            target.index > current.index
            && bundle.runtimePolicy.recoveryCandidates.contains(where: {
              $0.isReleased && $0.targetOccurrenceID == chosen
            })
        } else {
          validActiveRecovery = false
        }
        if !validActiveRecovery {
          issues.append(.invalidRecoveryState)
        }
      } else if state.recovery.chosenRejoinOccurrenceID != nil {
        issues.append(.invalidRecoveryState)
      }
    }

    switch state.egress.status {
    case .active:
      let validActiveEgress: Bool
      if let exitFacilityID = state.egress.exitFacilityID,
        let firstEligibleOccurrenceID =
          state.egress.firstEligibleOccurrenceID
      {
        validActiveEgress =
          bundle.runtimePolicy.egressOptions.contains(where: {
            $0.isReleased
              && $0.exitFacilityID == exitFacilityID
              && $0.firstEligibleOccurrenceID
                == firstEligibleOccurrenceID
          })
          && state.finishConfirmationExitFacilityID == exitFacilityID
      } else {
        validActiveEgress = false
      }
      if !validActiveEgress {
        issues.append(.invalidEgressState)
      }
    case .inactive, .unavailable:
      if state.egress.exitFacilityID != nil
        || state.egress.firstEligibleOccurrenceID != nil
        || !state.egress.prohibitedActions.isEmpty
        || state.finishConfirmationExitFacilityID != nil
      {
        issues.append(.invalidEgressState)
      }
    }
    return NavigationSessionCheckpointCodec.sorted(issues)
  }

  private func validateOccurrences(
    _ values: [String],
    field: String,
    known: Set<String>,
    issues: inout [NavigationSessionCheckpointIssue]
  ) {
    var seen: Set<String> = []
    for occurrenceID in values {
      if !known.contains(occurrenceID) {
        issues.append(.unknownOccurrence(field, occurrenceID))
      }
      if !seen.insert(occurrenceID).inserted {
        issues.append(.duplicateOccurrence(field, occurrenceID))
      }
    }
  }
}
