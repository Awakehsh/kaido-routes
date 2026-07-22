import Foundation
import KaidoDomain

public enum RouteEditorInteractionContext: String, Equatable, Sendable {
  case parked = "PARKED"
  case moving = "MOVING"
}

public enum ExpertRouteEditorState: String, Equatable, Sendable {
  case editing = "EDITING"
  case finished = "FINISHED"
}

public enum ExpertRouteEditorError: Error, Equatable, Sendable {
  case invalidCatalog([String])
  case invalidIdentifier
  case unknownEntranceFacility
  case interactionLocked
  case sessionFinished
  case illegalChoice
  case duplicateOccurrenceID
  case nothingToUndo
  case routeIncomplete

  public var code: String {
    switch self {
    case .invalidCatalog:
      "INVALID_EDITOR_CATALOG"
    case .invalidIdentifier:
      "INVALID_IDENTIFIER"
    case .unknownEntranceFacility:
      "UNKNOWN_ENTRANCE_FACILITY"
    case .interactionLocked:
      "EDITOR_INTERACTION_LOCKED"
    case .sessionFinished:
      "EDITOR_SESSION_FINISHED"
    case .illegalChoice:
      "ILLEGAL_EDITOR_CHOICE"
    case .duplicateOccurrenceID:
      "DUPLICATE_OCCURRENCE_ID"
    case .nothingToUndo:
      "NOTHING_TO_UNDO"
    case .routeIncomplete:
      "EDITOR_ROUTE_INCOMPLETE"
    }
  }
}

public enum ReviewedRouteEditorDestination: Equatable, Sendable {
  case decisionPoint(String)
  case exitFacility(String)
}

/// One reviewed outgoing movement shown at an exact directional decision point.
public struct ReviewedRouteEditorChoice: Equatable, Sendable {
  public let id: String
  public let movementID: String
  public let movementTollDomainID: String
  public let outgoingEdgeID: String
  public let outgoingEdgeTollDomainID: String
  public let destination: ReviewedRouteEditorDestination

  public init(
    id: String,
    movementID: String,
    movementTollDomainID: String,
    outgoingEdgeID: String,
    outgoingEdgeTollDomainID: String,
    destination: ReviewedRouteEditorDestination
  ) {
    self.id = id
    self.movementID = movementID
    self.movementTollDomainID = movementTollDomainID
    self.outgoingEdgeID = outgoingEdgeID
    self.outgoingEdgeTollDomainID = outgoingEdgeTollDomainID
    self.destination = destination
  }
}

/// A UI cursor, not a named JCT pin: incoming approach and complex are explicit.
public struct ReviewedRouteEditorDecisionPoint: Equatable, Sendable {
  public let id: String
  public let incomingApproachID: String
  public let junctionComplexID: String
  public let choices: [ReviewedRouteEditorChoice]

  public init(
    id: String,
    incomingApproachID: String,
    junctionComplexID: String,
    choices: [ReviewedRouteEditorChoice]
  ) {
    self.id = id
    self.incomingApproachID = incomingApproachID
    self.junctionComplexID = junctionComplexID
    self.choices = choices
  }
}

/// Begins authoring at one exact directional entrance and first mainline edge.
public struct ReviewedRouteEditorEntrance: Equatable, Sendable {
  public let facilityID: String
  public let initialEdgeID: String
  public let initialEdgeTollDomainID: String
  public let firstDecisionPointID: String

  public init(
    facilityID: String,
    initialEdgeID: String,
    initialEdgeTollDomainID: String,
    firstDecisionPointID: String
  ) {
    self.facilityID = facilityID
    self.initialEdgeID = initialEdgeID
    self.initialEdgeTollDomainID = initialEdgeTollDomainID
    self.firstDecisionPointID = firstDecisionPointID
  }
}

/// Snapshot-bound authoring data. Cycles are valid; missing references are not.
public struct ReviewedRouteEditorCatalog: Equatable, Sendable {
  public let networkSnapshotID: String
  public let entrances: [ReviewedRouteEditorEntrance]
  public let decisionPoints: [ReviewedRouteEditorDecisionPoint]

  public init(
    networkSnapshotID: String,
    entrances: [ReviewedRouteEditorEntrance],
    decisionPoints: [ReviewedRouteEditorDecisionPoint]
  ) {
    self.networkSnapshotID = networkSnapshotID
    self.entrances = entrances
    self.decisionPoints = decisionPoints
  }

  public var validationIssues: [String] {
    var issues: [String] = []
    if networkSnapshotID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append("network snapshot ID is empty")
    }
    if entrances.isEmpty { issues.append("editor entrances are empty") }
    if decisionPoints.isEmpty { issues.append("editor decision points are empty") }

    let entranceIDs = entrances.map(\.facilityID)
    if Set(entranceIDs).count != entranceIDs.count {
      issues.append("editor entrance facility IDs are not unique")
    }
    let decisionPointIDs = decisionPoints.map(\.id)
    let decisionPointIDSet = Set(decisionPointIDs)
    if decisionPointIDSet.count != decisionPointIDs.count {
      issues.append("editor decision point IDs are not unique")
    }

    for entrance in entrances {
      if [
        entrance.facilityID,
        entrance.initialEdgeID,
        entrance.initialEdgeTollDomainID,
        entrance.firstDecisionPointID,
      ].contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
        issues.append("editor entrance contains an empty identifier")
      }
      if !decisionPointIDSet.contains(entrance.firstDecisionPointID) {
        issues.append("editor entrance references an unknown decision point")
      }
    }

    var allChoiceIDs: [String] = []
    for decisionPoint in decisionPoints {
      if [
        decisionPoint.id,
        decisionPoint.incomingApproachID,
        decisionPoint.junctionComplexID,
      ].contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
        issues.append("editor decision point contains an empty identifier")
      }
      if decisionPoint.choices.isEmpty {
        issues.append("editor decision point has no legal choices")
      }
      let movementIDs = decisionPoint.choices.map(\.movementID)
      if Set(movementIDs).count != movementIDs.count {
        issues.append("editor decision point repeats a movement")
      }
      for choice in decisionPoint.choices {
        allChoiceIDs.append(choice.id)
        if [
          choice.id,
          choice.movementID,
          choice.movementTollDomainID,
          choice.outgoingEdgeID,
          choice.outgoingEdgeTollDomainID,
        ].contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
          issues.append("editor choice contains an empty identifier")
        }
        if case .decisionPoint(let nextID) = choice.destination,
          !decisionPointIDSet.contains(nextID)
        {
          issues.append("editor choice references an unknown decision point")
        }
        if case .exitFacility(let exitID) = choice.destination,
          exitID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
          issues.append("editor choice contains an empty exit facility ID")
        }
      }
    }
    if Set(allChoiceIDs).count != allChoiceIDs.count {
      issues.append("editor choice IDs are not unique")
    }
    for entrance in entrances
    where !hasReachableExit(
      from: entrance.firstDecisionPointID,
      decisionPoints: decisionPoints
    ) {
      issues.append("editor entrance has no reachable exit")
    }
    return Array(Set(issues)).sorted()
  }

  private func hasReachableExit(
    from initialDecisionPointID: String,
    decisionPoints: [ReviewedRouteEditorDecisionPoint]
  ) -> Bool {
    var decisionsByID: [String: ReviewedRouteEditorDecisionPoint] = [:]
    for decisionPoint in decisionPoints where decisionsByID[decisionPoint.id] == nil {
      decisionsByID[decisionPoint.id] = decisionPoint
    }
    var pending = [initialDecisionPointID]
    var visited: Set<String> = []
    while let decisionPointID = pending.popLast() {
      guard visited.insert(decisionPointID).inserted,
        let decisionPoint = decisionsByID[decisionPointID]
      else { continue }
      for choice in decisionPoint.choices {
        switch choice.destination {
        case .exitFacility:
          return true
        case .decisionPoint(let nextDecisionPointID):
          pending.append(nextDecisionPointID)
        }
      }
    }
    return false
  }
}

public struct ExpertRouteEditorSnapshot: Equatable, Sendable {
  public let state: ExpertRouteEditorState
  public let networkSnapshotID: String
  public let routePlanID: String
  public let entranceFacilityID: String
  public let currentDecisionPointID: String?
  public let incomingApproachID: String?
  public let junctionComplexID: String?
  public let availableChoices: [ReviewedRouteEditorChoice]
  public let occurrences: [RouteOccurrence]
  public let selectedExitFacilityID: String?

  public init(
    state: ExpertRouteEditorState,
    networkSnapshotID: String,
    routePlanID: String,
    entranceFacilityID: String,
    currentDecisionPointID: String?,
    incomingApproachID: String?,
    junctionComplexID: String?,
    availableChoices: [ReviewedRouteEditorChoice],
    occurrences: [RouteOccurrence],
    selectedExitFacilityID: String?
  ) {
    self.state = state
    self.networkSnapshotID = networkSnapshotID
    self.routePlanID = routePlanID
    self.entranceFacilityID = entranceFacilityID
    self.currentDecisionPointID = currentDecisionPointID
    self.incomingApproachID = incomingApproachID
    self.junctionComplexID = junctionComplexID
    self.availableChoices = availableChoices
    self.occurrences = occurrences
    self.selectedExitFacilityID = selectedExitFacilityID
  }
}

/// Platform-light expert authoring state. UI renders choices; it does not infer them.
public struct ExpertRouteEditorSession: Sendable {
  private struct SelectionRecord: Sendable {
    let decisionPointID: String
    let appendedOccurrenceCount: Int
  }

  private let catalog: ReviewedRouteEditorCatalog
  private let routePlanID: String
  private let entranceFacilityID: String
  private let recoveryPolicy: RoutePlan.RecoveryPolicy
  private var currentDecisionPointID: String?
  private var selectedExitFacilityID: String?
  private var occurrences: [RouteOccurrence]
  private var history: [SelectionRecord]
  public private(set) var state: ExpertRouteEditorState

  public init(
    catalog: ReviewedRouteEditorCatalog,
    routePlanID: String,
    entranceFacilityID: String,
    initialOccurrenceID: String,
    recoveryPolicy: RoutePlan.RecoveryPolicy,
    interaction: RouteEditorInteractionContext
  ) throws {
    guard interaction == .parked else {
      throw ExpertRouteEditorError.interactionLocked
    }
    let catalogIssues = catalog.validationIssues
    guard catalogIssues.isEmpty else {
      throw ExpertRouteEditorError.invalidCatalog(catalogIssues)
    }
    guard !routePlanID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !initialOccurrenceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw ExpertRouteEditorError.invalidIdentifier
    }
    guard
      let entrance = catalog.entrances.first(where: {
        $0.facilityID == entranceFacilityID
      })
    else {
      throw ExpertRouteEditorError.unknownEntranceFacility
    }

    self.catalog = catalog
    self.routePlanID = routePlanID
    self.entranceFacilityID = entranceFacilityID
    self.recoveryPolicy = recoveryPolicy
    currentDecisionPointID = entrance.firstDecisionPointID
    selectedExitFacilityID = nil
    occurrences = [
      RouteOccurrence(
        id: initialOccurrenceID,
        index: 0,
        kind: .edge,
        entityID: entrance.initialEdgeID,
        tollDomainID: entrance.initialEdgeTollDomainID
      )
    ]
    history = []
    state = .editing
  }

  public var snapshot: ExpertRouteEditorSnapshot {
    let decisionPoint = currentDecisionPointID.flatMap(decisionPoint(id:))
    return ExpertRouteEditorSnapshot(
      state: state,
      networkSnapshotID: catalog.networkSnapshotID,
      routePlanID: routePlanID,
      entranceFacilityID: entranceFacilityID,
      currentDecisionPointID: currentDecisionPointID,
      incomingApproachID: decisionPoint?.incomingApproachID,
      junctionComplexID: decisionPoint?.junctionComplexID,
      availableChoices: state == .editing ? decisionPoint?.choices ?? [] : [],
      occurrences: occurrences,
      selectedExitFacilityID: selectedExitFacilityID
    )
  }

  public mutating func select(
    choiceID: String,
    movementOccurrenceID: String,
    outgoingEdgeOccurrenceID: String,
    interaction: RouteEditorInteractionContext
  ) throws {
    guard interaction == .parked else {
      throw ExpertRouteEditorError.interactionLocked
    }
    guard state == .editing, let currentDecisionPointID,
      let decisionPoint = decisionPoint(id: currentDecisionPointID)
    else {
      throw ExpertRouteEditorError.sessionFinished
    }
    guard let choice = decisionPoint.choices.first(where: { $0.id == choiceID }) else {
      throw ExpertRouteEditorError.illegalChoice
    }
    guard !movementOccurrenceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !outgoingEdgeOccurrenceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw ExpertRouteEditorError.invalidIdentifier
    }
    let newIDs = [movementOccurrenceID, outgoingEdgeOccurrenceID]
    let existingIDs = Set(occurrences.map(\.id))
    guard Set(newIDs).count == newIDs.count,
      existingIDs.isDisjoint(with: newIDs)
    else {
      throw ExpertRouteEditorError.duplicateOccurrenceID
    }

    let firstIndex = occurrences.count
    occurrences.append(
      RouteOccurrence(
        id: movementOccurrenceID,
        index: firstIndex,
        kind: .junctionMovement,
        entityID: choice.movementID,
        tollDomainID: choice.movementTollDomainID
      ))
    occurrences.append(
      RouteOccurrence(
        id: outgoingEdgeOccurrenceID,
        index: firstIndex + 1,
        kind: .edge,
        entityID: choice.outgoingEdgeID,
        tollDomainID: choice.outgoingEdgeTollDomainID
      ))
    history.append(
      SelectionRecord(decisionPointID: currentDecisionPointID, appendedOccurrenceCount: 2)
    )

    switch choice.destination {
    case .decisionPoint(let nextDecisionPointID):
      self.currentDecisionPointID = nextDecisionPointID
    case .exitFacility(let exitFacilityID):
      self.currentDecisionPointID = nil
      selectedExitFacilityID = exitFacilityID
      state = .finished
    }
  }

  public mutating func undo(interaction: RouteEditorInteractionContext) throws {
    guard interaction == .parked else {
      throw ExpertRouteEditorError.interactionLocked
    }
    guard let record = history.popLast() else {
      throw ExpertRouteEditorError.nothingToUndo
    }
    occurrences.removeLast(record.appendedOccurrenceCount)
    currentDecisionPointID = record.decisionPointID
    selectedExitFacilityID = nil
    state = .editing
  }

  public func makeRoutePlan(
    interaction: RouteEditorInteractionContext
  ) throws -> RoutePlan {
    guard interaction == .parked else {
      throw ExpertRouteEditorError.interactionLocked
    }
    guard state == .finished, let selectedExitFacilityID else {
      throw ExpertRouteEditorError.routeIncomplete
    }
    return RoutePlan(
      id: routePlanID,
      networkSnapshotID: catalog.networkSnapshotID,
      entryFacilityID: entranceFacilityID,
      exitFacilityID: selectedExitFacilityID,
      recoveryPolicy: recoveryPolicy,
      occurrences: occurrences
    )
  }

  private func decisionPoint(id: String) -> ReviewedRouteEditorDecisionPoint? {
    catalog.decisionPoints.first { $0.id == id }
  }
}
