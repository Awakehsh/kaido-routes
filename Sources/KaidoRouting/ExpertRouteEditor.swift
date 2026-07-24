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
  case illegalLapCandidate
  case invalidLapOccurrenceCount
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
    case .illegalLapCandidate:
      "ILLEGAL_EDITOR_LAP_CANDIDATE"
    case .invalidLapOccurrenceCount:
      "INVALID_EDITOR_LAP_OCCURRENCE_COUNT"
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

/// One catalog-reviewed closed choice sequence eligible for value duplication.
public struct ReviewedRouteEditorLapTemplate: Equatable, Sendable {
  public let id: String
  public let startDecisionPointID: String
  public let choiceIDs: [String]

  public init(
    id: String,
    startDecisionPointID: String,
    choiceIDs: [String]
  ) {
    self.id = id
    self.startDecisionPointID = startDecisionPointID
    self.choiceIDs = choiceIDs
  }
}

private struct ResolvedRouteEditorLapTemplate: Sendable {
  let template: ReviewedRouteEditorLapTemplate
  let decisionPointIDs: [String]
}

/// Snapshot-bound authoring data. Cycles are valid; missing references are not.
public struct ReviewedRouteEditorCatalog: Equatable, Sendable {
  public let networkSnapshotID: String
  public let entrances: [ReviewedRouteEditorEntrance]
  public let decisionPoints: [ReviewedRouteEditorDecisionPoint]
  public let lapTemplates: [ReviewedRouteEditorLapTemplate]

  public init(
    networkSnapshotID: String,
    entrances: [ReviewedRouteEditorEntrance],
    decisionPoints: [ReviewedRouteEditorDecisionPoint],
    lapTemplates: [ReviewedRouteEditorLapTemplate] = []
  ) {
    self.networkSnapshotID = networkSnapshotID
    self.entrances = entrances
    self.decisionPoints = decisionPoints
    self.lapTemplates = lapTemplates
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
    let lapTemplateIDs = lapTemplates.map(\.id)
    if Set(lapTemplateIDs).count != lapTemplateIDs.count {
      issues.append("editor lap template IDs are not unique")
    }
    for template in lapTemplates {
      if template.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append("editor lap template ID is empty")
      }
      if template.startDecisionPointID.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty {
        issues.append("editor lap template start decision point ID is empty")
      }
      if template.choiceIDs.isEmpty {
        issues.append("editor lap template choice sequence is empty")
      }
      if resolvedLapTemplate(template) == nil {
        issues.append("editor lap template does not form a reviewed closed sequence")
      }
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

  fileprivate func resolvedLapTemplate(
    _ template: ReviewedRouteEditorLapTemplate
  ) -> ResolvedRouteEditorLapTemplate? {
    guard !template.choiceIDs.isEmpty else { return nil }
    var currentDecisionPointID = template.startDecisionPointID
    var decisionPointIDs: [String] = []
    for choiceID in template.choiceIDs {
      guard
        let decisionPoint = decisionPoints.first(where: {
          $0.id == currentDecisionPointID
        }),
        let choice = decisionPoint.choices.first(where: { $0.id == choiceID }),
        case .decisionPoint(let nextDecisionPointID) = choice.destination
      else {
        return nil
      }
      decisionPointIDs.append(currentDecisionPointID)
      currentDecisionPointID = nextDecisionPointID
    }
    guard currentDecisionPointID == template.startDecisionPointID else {
      return nil
    }
    return ResolvedRouteEditorLapTemplate(
      template: template,
      decisionPointIDs: decisionPointIDs
    )
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

/// One previously authored, template-matched closed subsequence.
///
/// UI submits this stable candidate ID; it does not infer closure or reconstruct
/// the source occurrence slice.
public struct ExpertRouteEditorLapCandidate: Equatable, Sendable {
  public let id: String
  public let reviewedTemplateID: String
  public let sourceOccurrenceIDs: [String]

  public init(
    id: String,
    reviewedTemplateID: String,
    sourceOccurrenceIDs: [String]
  ) {
    self.id = id
    self.reviewedTemplateID = reviewedTemplateID
    self.sourceOccurrenceIDs = sourceOccurrenceIDs
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
  public let availableLapCandidates: [ExpertRouteEditorLapCandidate]
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
    availableLapCandidates: [ExpertRouteEditorLapCandidate],
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
    self.availableLapCandidates = availableLapCandidates
    self.occurrences = occurrences
    self.selectedExitFacilityID = selectedExitFacilityID
  }
}

/// Platform-light expert authoring state. UI renders choices; it does not infer them.
public struct ExpertRouteEditorSession: Sendable {
  private struct SelectionRecord: Sendable {
    let decisionPointIDs: [String]
    let choiceIDs: [String]
    let appendedOccurrenceIDs: [String]
  }

  private struct AuthoredStep: Sendable {
    let decisionPointID: String
    let choiceID: String
    let occurrenceIDs: [String]
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
      availableLapCandidates: availableLapCandidates,
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
      SelectionRecord(
        decisionPointIDs: [currentDecisionPointID],
        choiceIDs: [choice.id],
        appendedOccurrenceIDs: newIDs
      )
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

  public mutating func duplicateLap(
    candidateID: String,
    newOccurrenceIDs: [String],
    interaction: RouteEditorInteractionContext
  ) throws {
    guard interaction == .parked else {
      throw ExpertRouteEditorError.interactionLocked
    }
    guard state == .editing else {
      throw ExpertRouteEditorError.sessionFinished
    }
    guard
      let candidate = availableLapCandidates.first(where: { $0.id == candidateID }),
      let template = catalog.lapTemplates.first(where: {
        $0.id == candidate.reviewedTemplateID
      }),
      let resolvedTemplate = catalog.resolvedLapTemplate(template)
    else {
      throw ExpertRouteEditorError.illegalLapCandidate
    }
    guard newOccurrenceIDs.count == candidate.sourceOccurrenceIDs.count else {
      throw ExpertRouteEditorError.invalidLapOccurrenceCount
    }
    guard
      !newOccurrenceIDs.contains(where: {
        $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      })
    else {
      throw ExpertRouteEditorError.invalidIdentifier
    }
    let newIDSet = Set(newOccurrenceIDs)
    guard newIDSet.count == newOccurrenceIDs.count,
      Set(occurrences.map(\.id)).isDisjoint(with: newIDSet)
    else {
      throw ExpertRouteEditorError.duplicateOccurrenceID
    }
    let occurrencesByID = Dictionary(
      uniqueKeysWithValues: occurrences.map { ($0.id, $0) }
    )
    let sourceOccurrences = candidate.sourceOccurrenceIDs.compactMap {
      occurrencesByID[$0]
    }
    guard sourceOccurrences.count == candidate.sourceOccurrenceIDs.count else {
      throw ExpertRouteEditorError.illegalLapCandidate
    }
    let firstIndex = occurrences.count
    let duplicated = zip(sourceOccurrences, newOccurrenceIDs)
      .enumerated()
      .map { offset, pair in
        return RouteOccurrence(
          id: pair.1,
          index: firstIndex + offset,
          kind: pair.0.kind,
          entityID: pair.0.entityID,
          parkingAreaID: pair.0.parkingAreaID,
          tollDomainID: pair.0.tollDomainID,
          isOptional: pair.0.isOptional
        )
      }
    occurrences.append(contentsOf: duplicated)
    history.append(
      SelectionRecord(
        decisionPointIDs: resolvedTemplate.decisionPointIDs,
        choiceIDs: resolvedTemplate.template.choiceIDs,
        appendedOccurrenceIDs: newOccurrenceIDs
      )
    )
  }

  public mutating func undo(interaction: RouteEditorInteractionContext) throws {
    guard interaction == .parked else {
      throw ExpertRouteEditorError.interactionLocked
    }
    guard let record = history.popLast() else {
      throw ExpertRouteEditorError.nothingToUndo
    }
    occurrences.removeLast(record.appendedOccurrenceIDs.count)
    currentDecisionPointID = record.decisionPointIDs.first
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

  private var availableLapCandidates: [ExpertRouteEditorLapCandidate] {
    guard state == .editing, let currentDecisionPointID else { return [] }
    var steps: [AuthoredStep] = []
    for record in history {
      guard record.decisionPointIDs.count == record.choiceIDs.count,
        record.appendedOccurrenceIDs.count == record.choiceIDs.count * 2
      else { return [] }
      for offset in record.choiceIDs.indices {
        let occurrenceOffset = offset * 2
        steps.append(
          AuthoredStep(
            decisionPointID: record.decisionPointIDs[offset],
            choiceID: record.choiceIDs[offset],
            occurrenceIDs: Array(
              record.appendedOccurrenceIDs[occurrenceOffset..<(occurrenceOffset + 2)]
            )
          )
        )
      }
    }
    var candidates: [ExpertRouteEditorLapCandidate] = []
    for template in catalog.lapTemplates
    where template.startDecisionPointID == currentDecisionPointID {
      guard let resolved = catalog.resolvedLapTemplate(template),
        steps.count >= template.choiceIDs.count
      else { continue }
      for start in 0...(steps.count - template.choiceIDs.count) {
        let slice = Array(steps[start..<(start + template.choiceIDs.count)])
        guard slice.map(\.decisionPointID) == resolved.decisionPointIDs,
          slice.map(\.choiceID) == template.choiceIDs
        else { continue }
        let sourceOccurrenceIDs = slice.flatMap(\.occurrenceIDs)
        guard let firstID = sourceOccurrenceIDs.first,
          let lastID = sourceOccurrenceIDs.last
        else { continue }
        candidates.append(
          ExpertRouteEditorLapCandidate(
            id: "\(template.id)::\(firstID)::\(lastID)",
            reviewedTemplateID: template.id,
            sourceOccurrenceIDs: sourceOccurrenceIDs
          )
        )
      }
    }
    return candidates
  }
}
