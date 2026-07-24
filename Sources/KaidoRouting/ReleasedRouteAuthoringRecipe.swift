import Foundation
import KaidoDomain

/// Why one exact RoutePlan cannot be replayed through its reviewed editor catalog.
///
/// "Released" names the intended consumer boundary. Constructing this value does
/// not promote evidence or make a route eligible for navigation.
public enum ReleasedRouteAuthoringError: Error, Equatable, Sendable {
  case invalidRoutePlan
  case invalidEditorCatalog([String])
  case networkSnapshotMismatch
  case unknownEntranceFacility
  case entranceOccurrenceMismatch
  case unsupportedOccurrenceSequence(String)
  case unavailableChoice(String)
  case ambiguousChoice(String)
  case destinationMismatch(String)
  case authoredRouteMismatch

  public var code: String {
    switch self {
    case .invalidRoutePlan:
      "INVALID_RELEASED_AUTHORING_ROUTE_PLAN"
    case .invalidEditorCatalog:
      "INVALID_RELEASED_AUTHORING_EDITOR_CATALOG"
    case .networkSnapshotMismatch:
      "RELEASED_AUTHORING_SNAPSHOT_MISMATCH"
    case .unknownEntranceFacility:
      "UNKNOWN_RELEASED_AUTHORING_ENTRANCE"
    case .entranceOccurrenceMismatch:
      "RELEASED_AUTHORING_ENTRANCE_OCCURRENCE_MISMATCH"
    case .unsupportedOccurrenceSequence:
      "UNSUPPORTED_RELEASED_AUTHORING_OCCURRENCE_SEQUENCE"
    case .unavailableChoice:
      "RELEASED_AUTHORING_CHOICE_UNAVAILABLE"
    case .ambiguousChoice:
      "RELEASED_AUTHORING_CHOICE_AMBIGUOUS"
    case .destinationMismatch:
      "RELEASED_AUTHORING_DESTINATION_MISMATCH"
    case .authoredRouteMismatch:
      "AUTHORED_ROUTE_DOES_NOT_MATCH_RELEASE"
    }
  }

  package var sortKey: String {
    switch self {
    case .invalidEditorCatalog(let issues):
      "\(code):\(issues.joined(separator: ","))"
    case .unsupportedOccurrenceSequence(let occurrenceID),
      .unavailableChoice(let occurrenceID),
      .ambiguousChoice(let occurrenceID),
      .destinationMismatch(let occurrenceID):
      "\(code):\(occurrenceID)"
    default:
      code
    }
  }
}

/// One user-submittable reviewed choice in the exact released occurrence order.
public struct ReleasedRouteAuthoringStep: Equatable, Sendable {
  public let decisionPointID: String
  public let choiceID: String
  public let movementOccurrenceID: String
  public let outgoingEdgeOccurrenceID: String

  public init(
    decisionPointID: String,
    choiceID: String,
    movementOccurrenceID: String,
    outgoingEdgeOccurrenceID: String
  ) {
    self.decisionPointID = decisionPointID
    self.choiceID = choiceID
    self.movementOccurrenceID = movementOccurrenceID
    self.outgoingEdgeOccurrenceID = outgoingEdgeOccurrenceID
  }
}

/// Proves that an exact RoutePlan is expressible by one reviewed editor catalog.
///
/// The recipe preserves occurrence IDs and repeated traversals. It does not
/// select choices on the user's behalf or provide presentation labels.
public struct ReleasedRouteAuthoringRecipe: Equatable, Sendable {
  public let routePlan: RoutePlan
  public let editorCatalog: ReviewedRouteEditorCatalog
  public let steps: [ReleasedRouteAuthoringStep]

  public init(
    routePlan: RoutePlan,
    editorCatalog: ReviewedRouteEditorCatalog
  ) throws {
    let catalogIssues = editorCatalog.validationIssues
    guard catalogIssues.isEmpty else {
      throw ReleasedRouteAuthoringError.invalidEditorCatalog(catalogIssues)
    }
    guard Self.routePlanIsStructurallyValid(routePlan) else {
      throw ReleasedRouteAuthoringError.invalidRoutePlan
    }
    guard routePlan.networkSnapshotID == editorCatalog.networkSnapshotID else {
      throw ReleasedRouteAuthoringError.networkSnapshotMismatch
    }
    guard
      let entrance = editorCatalog.entrances.first(where: {
        $0.facilityID == routePlan.entryFacilityID
      })
    else {
      throw ReleasedRouteAuthoringError.unknownEntranceFacility
    }
    guard
      let initialOccurrence = routePlan.occurrences.first,
      Self.matchesInitialOccurrence(initialOccurrence, entrance: entrance)
    else {
      throw ReleasedRouteAuthoringError.entranceOccurrenceMismatch
    }

    let remainingOccurrences = routePlan.occurrences.dropFirst()
    guard !remainingOccurrences.isEmpty, remainingOccurrences.count.isMultiple(of: 2) else {
      throw ReleasedRouteAuthoringError.unsupportedOccurrenceSequence(
        remainingOccurrences.first?.id ?? initialOccurrence.id
      )
    }

    var currentDecisionPointID = entrance.firstDecisionPointID
    var resolvedSteps: [ReleasedRouteAuthoringStep] = []
    var offset = remainingOccurrences.startIndex
    while offset < remainingOccurrences.endIndex {
      let movement = remainingOccurrences[offset]
      let edgeIndex = remainingOccurrences.index(after: offset)
      let outgoingEdge = remainingOccurrences[edgeIndex]
      guard Self.isSupportedMovement(movement),
        Self.isSupportedEdge(outgoingEdge)
      else {
        throw ReleasedRouteAuthoringError.unsupportedOccurrenceSequence(
          !Self.isSupportedMovement(movement) ? movement.id : outgoingEdge.id
        )
      }
      guard
        let decisionPoint = editorCatalog.decisionPoints.first(where: {
          $0.id == currentDecisionPointID
        })
      else {
        throw ReleasedRouteAuthoringError.unavailableChoice(movement.id)
      }

      let matchingChoices = decisionPoint.choices.filter {
        Self.matches(
          choice: $0,
          movement: movement,
          outgoingEdge: outgoingEdge
        )
      }
      guard !matchingChoices.isEmpty else {
        throw ReleasedRouteAuthoringError.unavailableChoice(movement.id)
      }
      guard matchingChoices.count == 1, let choice = matchingChoices.first else {
        throw ReleasedRouteAuthoringError.ambiguousChoice(movement.id)
      }

      let isFinalStep =
        remainingOccurrences.index(after: edgeIndex) == remainingOccurrences.endIndex
      switch (choice.destination, isFinalStep) {
      case (.decisionPoint(let nextDecisionPointID), false):
        currentDecisionPointID = nextDecisionPointID
      case (.exitFacility(let exitFacilityID), true)
      where exitFacilityID == routePlan.exitFacilityID:
        break
      default:
        throw ReleasedRouteAuthoringError.destinationMismatch(movement.id)
      }

      resolvedSteps.append(
        ReleasedRouteAuthoringStep(
          decisionPointID: decisionPoint.id,
          choiceID: choice.id,
          movementOccurrenceID: movement.id,
          outgoingEdgeOccurrenceID: outgoingEdge.id
        )
      )
      offset = remainingOccurrences.index(after: edgeIndex)
    }

    self.routePlan = routePlan
    self.editorCatalog = editorCatalog
    steps = resolvedSteps
  }

  /// Starts a parked editor with the exact release-owned route and first occurrence IDs.
  public func makeSession(
    interaction: RouteEditorInteractionContext
  ) throws -> ExpertRouteEditorSession {
    guard let initialOccurrenceID = routePlan.occurrences.first?.id else {
      throw ReleasedRouteAuthoringError.invalidRoutePlan
    }
    return try ExpertRouteEditorSession(
      catalog: editorCatalog,
      routePlanID: routePlan.id,
      entranceFacilityID: routePlan.entryFacilityID,
      initialOccurrenceID: initialOccurrenceID,
      recoveryPolicy: routePlan.recoveryPolicy,
      interaction: interaction
    )
  }

  /// Returns the exact released plan only after the user-authored session matches it.
  ///
  /// `ExpertRouteEditorSession` intentionally owns no reviewed distance. This
  /// method compares every other field and occurrence before restoring the
  /// release-owned `actualDistanceKM`.
  public func compile(
    session: ExpertRouteEditorSession,
    interaction: RouteEditorInteractionContext
  ) throws -> RoutePlan {
    let authored = try session.makeRoutePlan(interaction: interaction)
    guard Self.matchesReleaseIdentity(authored, routePlan) else {
      throw ReleasedRouteAuthoringError.authoredRouteMismatch
    }
    return routePlan
  }

  private static func routePlanIsStructurallyValid(_ routePlan: RoutePlan) -> Bool {
    guard !normalized(routePlan.id).isEmpty,
      !normalized(routePlan.networkSnapshotID).isEmpty,
      !normalized(routePlan.entryFacilityID).isEmpty,
      !normalized(routePlan.exitFacilityID).isEmpty,
      !routePlan.occurrences.isEmpty,
      routePlan.actualDistanceKM.map({ $0.isFinite && $0 > 0 }) != false
    else {
      return false
    }
    let occurrenceIDs = routePlan.occurrences.map(\.id)
    guard Set(occurrenceIDs).count == occurrenceIDs.count,
      routePlan.occurrences.map(\.index) == Array(0..<routePlan.occurrences.count)
    else {
      return false
    }
    return routePlan.occurrences.allSatisfy {
      !normalized($0.id).isEmpty && !normalized($0.entityID).isEmpty
    }
  }

  private static func matchesInitialOccurrence(
    _ occurrence: RouteOccurrence,
    entrance: ReviewedRouteEditorEntrance
  ) -> Bool {
    occurrence.kind == .edge
      && occurrence.entityID == entrance.initialEdgeID
      && occurrence.tollDomainID == entrance.initialEdgeTollDomainID
      && occurrence.parkingAreaID == nil
      && !occurrence.isOptional
  }

  private static func isSupportedMovement(_ occurrence: RouteOccurrence) -> Bool {
    occurrence.kind == .junctionMovement
      && occurrence.parkingAreaID == nil
      && !occurrence.isOptional
  }

  private static func isSupportedEdge(_ occurrence: RouteOccurrence) -> Bool {
    occurrence.kind == .edge
      && occurrence.parkingAreaID == nil
      && !occurrence.isOptional
  }

  private static func matches(
    choice: ReviewedRouteEditorChoice,
    movement: RouteOccurrence,
    outgoingEdge: RouteOccurrence
  ) -> Bool {
    choice.movementID == movement.entityID
      && movement.tollDomainID == choice.movementTollDomainID
      && choice.outgoingEdgeID == outgoingEdge.entityID
      && outgoingEdge.tollDomainID == choice.outgoingEdgeTollDomainID
  }

  private static func matchesReleaseIdentity(
    _ authored: RoutePlan,
    _ released: RoutePlan
  ) -> Bool {
    authored.id == released.id
      && authored.networkSnapshotID == released.networkSnapshotID
      && authored.entryFacilityID == released.entryFacilityID
      && authored.exitFacilityID == released.exitFacilityID
      && authored.recoveryPolicy == released.recoveryPolicy
      && authored.occurrences == released.occurrences
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
