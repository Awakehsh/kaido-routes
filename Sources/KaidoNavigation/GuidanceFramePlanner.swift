import Foundation
import KaidoDomain

public struct GuidancePlanningResult: Equatable, Sendable {
  public let status: GuidancePlanningStatus
  public let frame: GuidanceFrame?
  public let promptEmission: GuidancePromptEmission?

  public init(
    status: GuidancePlanningStatus,
    frame: GuidanceFrame? = nil,
    promptEmission: GuidancePromptEmission? = nil
  ) {
    self.status = status
    self.frame = frame
    self.promptEmission = promptEmission
  }
}

/// Selects a released occurrence-scoped frame from already resolved route progress.
/// It does not inspect coordinates, mutate RoutePlan progress, or render an adapter value.
public enum GuidanceFramePlanner {
  public static func plan(
    snapshot: NavigationSnapshot,
    routePlan: RoutePlan?,
    definitions: [ReleasedGuidanceDefinition],
    observation: GuidanceProgressObservation
  ) -> GuidancePlanningResult {
    guard observation.distanceToDecisionPointMeters.isFinite,
      observation.distanceToDecisionPointMeters >= 0,
      let routePlan,
      definitionsAreValid(definitions, for: routePlan)
    else {
      return GuidancePlanningResult(status: .invalidDefinition)
    }

    guard snapshot.currentOccurrenceID == observation.occurrenceID else {
      return GuidancePlanningResult(status: .notCurrentOccurrence)
    }
    guard hasSufficientRouteEvidence(snapshot) else {
      return GuidancePlanningResult(status: .insufficientRouteEvidence)
    }

    let currentDefinitions = definitions.filter {
      $0.anchor.occurrenceID == observation.occurrenceID
    }
    guard !currentDefinitions.isEmpty else {
      return GuidancePlanningResult(status: .noReleasedDefinition)
    }

    let emittedPromptIDs = Set(snapshot.emittedGuidancePromptIDs)
    let eligibleOrEmitted = currentDefinitions.filter {
      observation.distanceToDecisionPointMeters <= $0.triggerDistanceMeters
        || emittedPromptIDs.contains($0.anchor.promptID)
    }
    let selected: ReleasedGuidanceDefinition
    if let mostAdvanced = eligibleOrEmitted.min(by: triggerAscending) {
      selected = mostAdvanced
    } else if let outermost = currentDefinitions.max(by: triggerAscending) {
      selected = outermost
    } else {
      return GuidancePlanningResult(status: .noReleasedDefinition)
    }

    let frame = selected.frameTemplate.makeFrame(
      anchor: selected.anchor,
      distanceMeters: observation.distanceToDecisionPointMeters
    )
    do {
      try GuidanceFrameValidator.validate(frame)
    } catch {
      return GuidancePlanningResult(status: .invalidDefinition)
    }

    let isEligible =
      observation.distanceToDecisionPointMeters <= selected.triggerDistanceMeters
    guard isEligible else {
      return GuidancePlanningResult(status: .waitingForAnchor, frame: frame)
    }
    guard !emittedPromptIDs.contains(selected.anchor.promptID) else {
      return GuidancePlanningResult(status: .frameUpdated, frame: frame)
    }

    return GuidancePlanningResult(
      status: .promptEmitted,
      frame: frame,
      promptEmission: GuidancePromptEmission(
        promptID: selected.anchor.promptID,
        anchorID: selected.anchor.anchorID,
        anchorOccurrenceID: selected.anchor.occurrenceID
      )
    )
  }

  private static func hasSufficientRouteEvidence(_ snapshot: NavigationSnapshot) -> Bool {
    guard snapshot.locationConfidence == .high,
      snapshot.routeCandidateResolution == .resolved,
      snapshot.signalReacquisitionStatus != .pending
    else {
      return false
    }
    switch snapshot.journeyPhase {
    case .strictRoute, .routeRecovery, .exitTransition:
      return true
    case .planning, .approachToEntry, .entryTransition, .surfaceEgress, .completed:
      return false
    }
  }

  private static func definitionsAreValid(
    _ definitions: [ReleasedGuidanceDefinition],
    for routePlan: RoutePlan
  ) -> Bool {
    guard !definitions.isEmpty else { return true }
    var anchorKeys: Set<AnchorKey> = []
    var promptIDs: Set<String> = []
    var movementByAnchorOccurrence: [String: String] = [:]
    var triggerDistancesByAnchorOccurrence: [String: Set<Double>] = [:]

    for definition in definitions {
      let anchor = definition.anchor
      let template = definition.frameTemplate
      guard !normalized(anchor.occurrenceID).isEmpty,
        !normalized(anchor.anchorID).isEmpty,
        !normalized(anchor.promptID).isEmpty,
        definition.triggerDistanceMeters.isFinite,
        definition.triggerDistanceMeters >= 0,
        let anchorOccurrence = routePlan.occurrence(id: anchor.occurrenceID),
        let movementOccurrence = routePlan.occurrence(id: template.movementOccurrenceID),
        movementOccurrence.kind == .junctionMovement,
        movementOccurrence.index >= anchorOccurrence.index
      else {
        return false
      }

      let anchorKey = AnchorKey(
        occurrenceID: anchor.occurrenceID,
        anchorID: anchor.anchorID
      )
      guard anchorKeys.insert(anchorKey).inserted,
        promptIDs.insert(anchor.promptID).inserted
      else {
        return false
      }
      if let existingMovement = movementByAnchorOccurrence[anchor.occurrenceID],
        existingMovement != template.movementOccurrenceID
      {
        return false
      }
      movementByAnchorOccurrence[anchor.occurrenceID] = template.movementOccurrenceID
      let triggerInserted =
        triggerDistancesByAnchorOccurrence[anchor.occurrenceID, default: []]
        .insert(definition.triggerDistanceMeters).inserted
      guard triggerInserted else {
        return false
      }

      let validationFrame = template.makeFrame(anchor: anchor, distanceMeters: 0)
      do {
        try GuidanceFrameValidator.validate(validationFrame)
      } catch {
        return false
      }
    }
    return true
  }

  private static func triggerAscending(
    _ lhs: ReleasedGuidanceDefinition,
    _ rhs: ReleasedGuidanceDefinition
  ) -> Bool {
    if lhs.triggerDistanceMeters == rhs.triggerDistanceMeters {
      return lhs.anchor.promptID < rhs.anchor.promptID
    }
    return lhs.triggerDistanceMeters < rhs.triggerDistanceMeters
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

private struct AnchorKey: Hashable {
  let occurrenceID: String
  let anchorID: String
}
