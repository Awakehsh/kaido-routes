import Foundation

/// A geometry-adapter result, not route authority.
///
/// The adapter may compare a parked freehand gesture with reviewed display
/// geometry, but it can return only stable choice IDs for the exact current
/// editor cursor. This value never contains or creates RoutePlan occurrences.
public struct FreehandCorridorChoiceMatch: Equatable, Sendable {
  public let networkSnapshotID: String
  public let decisionPointID: String
  public let candidateChoiceIDs: [String]

  public init(
    networkSnapshotID: String,
    decisionPointID: String,
    candidateChoiceIDs: [String]
  ) {
    self.networkSnapshotID = networkSnapshotID
    self.decisionPointID = decisionPointID
    self.candidateChoiceIDs = candidateChoiceIDs
  }
}

public enum ParkedCorridorResolutionState: String, Equatable, Sendable {
  case unmatched = "UNMATCHED"
  case confirmationRequired = "CONFIRMATION_REQUIRED"
  case resolutionRequired = "RESOLUTION_REQUIRED"
  case resolved = "RESOLVED"
}

public enum ParkedCorridorResolutionError: Error, Equatable, Sendable {
  case invalidIdentifier
  case interactionLocked
  case editorNotEditable
  case identityMismatch
  case invalidCandidates
  case resolutionNotAllowed
  case illegalCandidate
  case staleEditorCursor

  public var code: String {
    switch self {
    case .invalidIdentifier:
      "INVALID_CORRIDOR_IDENTIFIER"
    case .interactionLocked:
      "CORRIDOR_INTERACTION_LOCKED"
    case .editorNotEditable:
      "CORRIDOR_EDITOR_NOT_EDITABLE"
    case .identityMismatch:
      "CORRIDOR_IDENTITY_MISMATCH"
    case .invalidCandidates:
      "INVALID_CORRIDOR_CANDIDATES"
    case .resolutionNotAllowed:
      "CORRIDOR_RESOLUTION_NOT_ALLOWED"
    case .illegalCandidate:
      "ILLEGAL_CORRIDOR_CANDIDATE"
    case .staleEditorCursor:
      "STALE_CORRIDOR_EDITOR_CURSOR"
    }
  }
}

public struct ParkedCorridorResolutionSnapshot: Equatable, Sendable {
  public let state: ParkedCorridorResolutionState
  public let networkSnapshotID: String
  public let routePlanID: String
  public let decisionPointID: String
  public let candidateChoices: [ReviewedRouteEditorChoice]
  public let selectedChoiceID: String?

  public init(
    state: ParkedCorridorResolutionState,
    networkSnapshotID: String,
    routePlanID: String,
    decisionPointID: String,
    candidateChoices: [ReviewedRouteEditorChoice],
    selectedChoiceID: String?
  ) {
    self.state = state
    self.networkSnapshotID = networkSnapshotID
    self.routePlanID = routePlanID
    self.decisionPointID = decisionPointID
    self.candidateChoices = candidateChoices
    self.selectedChoiceID = selectedChoiceID
  }
}

/// Parked-only confirmation boundary between gesture matching and route editing.
///
/// Resolving this session returns one already-reviewed editor choice. It does
/// not mutate an `ExpertRouteEditorSession`; the caller must explicitly submit
/// the returned stable choice ID to that session with fresh occurrence IDs.
public struct ParkedCorridorResolutionSession: Sendable {
  private let networkSnapshotID: String
  private let routePlanID: String
  private let decisionPointID: String
  private let candidateChoices: [ReviewedRouteEditorChoice]
  private var selectedChoiceID: String?

  public init(
    editorSnapshot: ExpertRouteEditorSnapshot,
    match: FreehandCorridorChoiceMatch,
    interaction: RouteEditorInteractionContext
  ) throws {
    guard interaction == .parked else {
      throw ParkedCorridorResolutionError.interactionLocked
    }
    guard editorSnapshot.state == .editing,
      let currentDecisionPointID = editorSnapshot.currentDecisionPointID
    else {
      throw ParkedCorridorResolutionError.editorNotEditable
    }
    guard
      !match.networkSnapshotID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !match.decisionPointID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !match.candidateChoiceIDs.contains(where: {
        $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      })
    else {
      throw ParkedCorridorResolutionError.invalidIdentifier
    }
    guard match.networkSnapshotID == editorSnapshot.networkSnapshotID,
      match.decisionPointID == currentDecisionPointID
    else {
      throw ParkedCorridorResolutionError.identityMismatch
    }
    guard Set(match.candidateChoiceIDs).count == match.candidateChoiceIDs.count else {
      throw ParkedCorridorResolutionError.invalidCandidates
    }

    let currentChoicesByID = Dictionary(
      uniqueKeysWithValues: editorSnapshot.availableChoices.map { ($0.id, $0) }
    )
    let candidates = match.candidateChoiceIDs.compactMap { currentChoicesByID[$0] }
    guard candidates.count == match.candidateChoiceIDs.count else {
      throw ParkedCorridorResolutionError.invalidCandidates
    }

    networkSnapshotID = match.networkSnapshotID
    routePlanID = editorSnapshot.routePlanID
    decisionPointID = match.decisionPointID
    candidateChoices = candidates
    selectedChoiceID = nil
  }

  public var snapshot: ParkedCorridorResolutionSnapshot {
    ParkedCorridorResolutionSnapshot(
      state: state,
      networkSnapshotID: networkSnapshotID,
      routePlanID: routePlanID,
      decisionPointID: decisionPointID,
      candidateChoices: candidateChoices,
      selectedChoiceID: selectedChoiceID
    )
  }

  public mutating func resolve(
    choiceID: String,
    editorSnapshot: ExpertRouteEditorSnapshot,
    interaction: RouteEditorInteractionContext
  ) throws -> ReviewedRouteEditorChoice {
    guard interaction == .parked else {
      throw ParkedCorridorResolutionError.interactionLocked
    }
    guard state == .confirmationRequired || state == .resolutionRequired else {
      throw ParkedCorridorResolutionError.resolutionNotAllowed
    }
    guard currentEditorStillMatches(editorSnapshot) else {
      throw ParkedCorridorResolutionError.staleEditorCursor
    }
    guard let choice = candidateChoices.first(where: { $0.id == choiceID }) else {
      throw ParkedCorridorResolutionError.illegalCandidate
    }
    selectedChoiceID = choice.id
    return choice
  }

  private var state: ParkedCorridorResolutionState {
    if selectedChoiceID != nil {
      return .resolved
    }
    switch candidateChoices.count {
    case 0:
      return .unmatched
    case 1:
      return .confirmationRequired
    default:
      return .resolutionRequired
    }
  }

  private func currentEditorStillMatches(
    _ editorSnapshot: ExpertRouteEditorSnapshot
  ) -> Bool {
    guard editorSnapshot.state == .editing,
      editorSnapshot.networkSnapshotID == networkSnapshotID,
      editorSnapshot.routePlanID == routePlanID,
      editorSnapshot.currentDecisionPointID == decisionPointID
    else {
      return false
    }
    let choicesByID = Dictionary(
      uniqueKeysWithValues: editorSnapshot.availableChoices.map { ($0.id, $0) }
    )
    return candidateChoices.allSatisfy { choicesByID[$0.id] == $0 }
  }
}
