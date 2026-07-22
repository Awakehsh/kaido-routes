import Foundation
import KaidoDomain

public enum GuidanceProgressBridgeError: Error, Equatable, Sendable {
  case insufficientMatcherEvidence
  case invalidMatcherProgress
  case networkSnapshotMismatch
  case routePlanMismatch
  case invalidDecisionZone
  case unknownCurrentOccurrence
  case occurrenceBindingMismatch
  case targetBehindCurrent
  case skippedRouteOccurrence(String)
  case incompleteCorridor
  case invalidGeometry(String)
}

/// Converts a HIGH Swift-matcher along-edge result into route distance to a reviewed zone.
/// Lateral match error is never interpreted as route progress.
public enum GuidanceProgressBridge {
  public static func resolve(
    estimate: MatcherEstimate,
    routePlan: RoutePlan,
    corridor: RouteMatcherCorridor,
    decisionZone: DecisionZoneProgressDefinition,
    skippedOccurrenceIDs: Set<String> = []
  ) throws -> GuidanceProgressObservation {
    guard estimate.confidence == .high,
      let currentOccurrenceID = estimate.occurrenceID,
      let directedEdgeID = estimate.directedEdgeID,
      let fractionAlongEdge = estimate.fractionAlongEdge
    else {
      throw GuidanceProgressBridgeError.insufficientMatcherEvidence
    }
    guard estimate.estimatedAtMilliseconds >= 0,
      fractionAlongEdge.isFinite,
      (0...1).contains(fractionAlongEdge)
    else {
      throw GuidanceProgressBridgeError.invalidMatcherProgress
    }
    guard routePlan.networkSnapshotID == corridor.networkSnapshotID,
      routePlan.networkSnapshotID == decisionZone.networkSnapshotID
    else {
      throw GuidanceProgressBridgeError.networkSnapshotMismatch
    }
    guard routePlan.id == corridor.routePlanID,
      routePlan.id == decisionZone.routePlanID
    else {
      throw GuidanceProgressBridgeError.routePlanMismatch
    }
    guard !decisionZone.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      decisionZone.entryOffsetMeters.isFinite,
      decisionZone.entryOffsetMeters >= 0,
      let targetRouteOccurrence = routePlan.occurrence(
        id: decisionZone.movementOccurrenceID
      ),
      targetRouteOccurrence.kind == .junctionMovement
    else {
      throw GuidanceProgressBridgeError.invalidDecisionZone
    }
    let routeOccurrenceIDs = routePlan.occurrences.map(\.id)
    let routeOccurrenceIndexes = routePlan.occurrences.map(\.index)
    guard corridor.validationIssues.isEmpty,
      Set(routeOccurrenceIDs).count == routeOccurrenceIDs.count,
      Set(routeOccurrenceIndexes).count == routeOccurrenceIndexes.count
    else {
      throw GuidanceProgressBridgeError.incompleteCorridor
    }

    let corridorOccurrencesByID = Dictionary(
      uniqueKeysWithValues: corridor.occurrences.map { ($0.id, $0) }
    )
    let corridorOccurrencesByIndex = Dictionary(
      uniqueKeysWithValues: corridor.occurrences.map { ($0.index, $0) }
    )
    let routeOccurrencesByIndex = Dictionary(
      uniqueKeysWithValues: routePlan.occurrences.map { ($0.index, $0) }
    )
    let edgesByID = Dictionary(uniqueKeysWithValues: corridor.edges.map { ($0.id, $0) })

    guard let currentRouteOccurrence = routePlan.occurrence(id: currentOccurrenceID),
      let currentBinding = corridorOccurrencesByID[currentOccurrenceID]
    else {
      throw GuidanceProgressBridgeError.unknownCurrentOccurrence
    }
    guard currentBinding.index == currentRouteOccurrence.index,
      currentBinding.directedEdgeID == directedEdgeID,
      let targetBinding = corridorOccurrencesByID[targetRouteOccurrence.id],
      targetBinding.index == targetRouteOccurrence.index
    else {
      throw GuidanceProgressBridgeError.occurrenceBindingMismatch
    }
    guard targetBinding.index >= currentBinding.index else {
      throw GuidanceProgressBridgeError.targetBehindCurrent
    }

    for index in currentBinding.index...targetBinding.index {
      guard let routeOccurrence = routeOccurrencesByIndex[index],
        let corridorOccurrence = corridorOccurrencesByIndex[index],
        routeOccurrence.id == corridorOccurrence.id,
        routeOccurrence.kind != .edge
          || routeOccurrence.entityID == corridorOccurrence.directedEdgeID
      else {
        throw GuidanceProgressBridgeError.incompleteCorridor
      }
      if skippedOccurrenceIDs.contains(routeOccurrence.id) {
        throw GuidanceProgressBridgeError.skippedRouteOccurrence(routeOccurrence.id)
      }
    }

    guard let currentEdge = edgesByID[currentBinding.directedEdgeID],
      let targetEdge = edgesByID[targetBinding.directedEdgeID]
    else {
      throw GuidanceProgressBridgeError.incompleteCorridor
    }
    let currentEdgeLength = currentEdge.lengthMeters
    let targetEdgeLength = targetEdge.lengthMeters
    guard currentEdgeLength.isFinite, currentEdgeLength > 0 else {
      throw GuidanceProgressBridgeError.invalidGeometry(currentEdge.id)
    }
    guard targetEdgeLength.isFinite, targetEdgeLength > 0,
      decisionZone.entryOffsetMeters <= targetEdgeLength
    else {
      throw GuidanceProgressBridgeError.invalidGeometry(targetEdge.id)
    }

    let distanceMeters: Double
    if currentBinding.index == targetBinding.index {
      distanceMeters = max(
        0,
        decisionZone.entryOffsetMeters - fractionAlongEdge * currentEdgeLength
      )
    } else {
      var total = (1 - fractionAlongEdge) * currentEdgeLength
      if currentBinding.index + 1 < targetBinding.index {
        for index in (currentBinding.index + 1)..<targetBinding.index {
          guard let binding = corridorOccurrencesByIndex[index],
            let edge = edgesByID[binding.directedEdgeID],
            edge.lengthMeters.isFinite,
            edge.lengthMeters > 0
          else {
            throw GuidanceProgressBridgeError.incompleteCorridor
          }
          total += edge.lengthMeters
        }
      }
      distanceMeters = total + decisionZone.entryOffsetMeters
    }
    guard distanceMeters.isFinite else {
      throw GuidanceProgressBridgeError.invalidGeometry(currentEdge.id)
    }

    return GuidanceProgressObservation(
      occurrenceID: currentOccurrenceID,
      distanceToDecisionPointMeters: distanceMeters,
      observedAtMilliseconds: estimate.estimatedAtMilliseconds
    )
  }
}
