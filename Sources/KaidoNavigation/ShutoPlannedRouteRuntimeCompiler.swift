import Foundation
import KaidoDomain
import KaidoRouting

public enum ShutoPlannedRouteRuntimeCompilationError:
  Error, Equatable, Sendable
{
  case networkSnapshotMismatch
  case invalidRoutePlanBinding
  case facilityBindingMismatch
  case networkEdgeBindingMismatch
  case routeGeometryMismatch
  case discontinuousRouteEdgeOrder
  case missingNode(Int64)
  case invalidMatcherCorridor([String])
}

public struct ShutoRouteRuntimeProgress: Equatable, Sendable {
  public let occurrenceID: String
  public let occurrenceIndex: Int
  public let directedEdgeID: String
  public let fractionAlongOccurrence: Double
  public let distanceAlongRouteMeters: Double
  public let routeProgressFraction: Double
  public let coordinate: ShutoCoordinate

  public init(
    occurrenceID: String,
    occurrenceIndex: Int,
    directedEdgeID: String,
    fractionAlongOccurrence: Double,
    distanceAlongRouteMeters: Double,
    routeProgressFraction: Double,
    coordinate: ShutoCoordinate
  ) {
    self.occurrenceID = occurrenceID
    self.occurrenceIndex = occurrenceIndex
    self.directedEdgeID = directedEdgeID
    self.fractionAlongOccurrence = fractionAlongOccurrence
    self.distanceAlongRouteMeters = distanceAlongRouteMeters
    self.routeProgressFraction = routeProgressFraction
    self.coordinate = coordinate
  }
}

/// Exact matcher inputs compiled from one selected whole-Shuto route.
///
/// The corridor includes every ordered RoutePlan edge plus graph-adjacent
/// alternatives at route nodes. Alternative edges let the matcher abstain or
/// report a deviation without allowing a provider to mutate the RoutePlan.
public struct ShutoPlannedRouteRuntimeAssets: Equatable, Sendable {
  public let routePlan: RoutePlan
  public let matcherCorridor: RouteMatcherCorridor
  public let decisionZones: [DecisionZoneProgressDefinition]
  public let releasedGuidance: [ReleasedGuidanceDefinition]
  public let recoveryCandidates: [RecoveryCandidate]

  private let routeEdges: [RouteMatcherDirectedEdge]
  private let routeEdgeLengthsMeters: [Double]
  private let cumulativeDistanceAtOccurrence: [Double]
  private let totalDistanceMeters: Double

  package init(
    routePlan: RoutePlan,
    matcherCorridor: RouteMatcherCorridor,
    decisionZones: [DecisionZoneProgressDefinition],
    releasedGuidance: [ReleasedGuidanceDefinition],
    recoveryCandidates: [RecoveryCandidate] = [],
    routeEdges: [RouteMatcherDirectedEdge],
    routeEdgeLengthsMeters: [Double]
  ) {
    self.routePlan = routePlan
    self.matcherCorridor = matcherCorridor
    self.decisionZones = decisionZones
    self.releasedGuidance = releasedGuidance
    self.recoveryCandidates = recoveryCandidates
    self.routeEdges = routeEdges
    self.routeEdgeLengthsMeters = routeEdgeLengthsMeters

    var cumulative = [0.0]
    cumulative.reserveCapacity(routeEdges.count)
    for lengthMeters in routeEdgeLengthsMeters.dropLast() {
      cumulative.append(cumulative.last! + lengthMeters)
    }
    cumulativeDistanceAtOccurrence = cumulative
    totalDistanceMeters = routeEdgeLengthsMeters.reduce(0, +)
  }

  /// Projects only an unambiguous HIGH matcher commit onto route progress.
  ///
  /// LOW, stale, stacked-road, off-route, or incomplete evidence returns nil
  /// so callers preserve their last admitted progress and expose degradation.
  public func project(
    _ estimate: MatcherEstimate
  ) -> ShutoRouteRuntimeProgress? {
    guard estimate.confidence == .high,
      let occurrenceID = estimate.occurrenceID,
      let directedEdgeID = estimate.directedEdgeID,
      estimate.candidateEdgeIDs == [directedEdgeID],
      let fraction = estimate.fractionAlongEdge,
      fraction.isFinite,
      (0...1).contains(fraction),
      let occurrence = routePlan.occurrence(id: occurrenceID),
      matcherCorridor.occurrences.first(where: {
        $0.id == occurrenceID
          && $0.index == occurrence.index
          && $0.directedEdgeID == directedEdgeID
      }) != nil,
      routeEdges.indices.contains(occurrence.index),
      routeEdgeLengthsMeters.indices.contains(occurrence.index),
      cumulativeDistanceAtOccurrence.indices.contains(occurrence.index),
      totalDistanceMeters > 0
    else {
      return nil
    }

    let edge = routeEdges[occurrence.index]
    guard edge.id == directedEdgeID,
      let start = edge.coordinates.first,
      let end = edge.coordinates.last
    else {
      return nil
    }
    let edgeLengthMeters = routeEdgeLengthsMeters[occurrence.index]
    let distance =
      cumulativeDistanceAtOccurrence[occurrence.index]
      + edgeLengthMeters * fraction
    return ShutoRouteRuntimeProgress(
      occurrenceID: occurrenceID,
      occurrenceIndex: occurrence.index,
      directedEdgeID: directedEdgeID,
      fractionAlongOccurrence: fraction,
      distanceAlongRouteMeters: distance,
      routeProgressFraction: min(1, max(0, distance / totalDistanceMeters)),
      coordinate: ShutoCoordinate(
        latitude: start.latitude + (end.latitude - start.latitude) * fraction,
        longitude: start.longitude + (end.longitude - start.longitude) * fraction
      )
    )
  }
}

public enum ShutoPlannedRouteRuntimeCompiler {
  public static func compile(
    database: ShutoNetworkDatabase,
    route: ShutoPlannedRoute
  ) throws -> ShutoPlannedRouteRuntimeAssets {
    try database.validate()
    guard route.routePlan.networkSnapshotID == database.networkSnapshotID else {
      throw ShutoPlannedRouteRuntimeCompilationError
        .networkSnapshotMismatch
    }
    let nodesByID = Dictionary(
      uniqueKeysWithValues: database.nodes.map { ($0.nodeID, $0) }
    )
    let edgesByID = Dictionary(
      uniqueKeysWithValues: database.edges.map { ($0.edgeID, $0) }
    )
    let facilitiesByID = Dictionary(
      uniqueKeysWithValues: database.directionalFacilities.map {
        ($0.facilityID, $0)
      }
    )
    guard
      route.routePlan.entryFacilityID == route.entryFacility.facilityID,
      route.routePlan.exitFacilityID == route.exitFacility.facilityID,
      facilitiesByID[route.entryFacility.facilityID] == route.entryFacility,
      facilitiesByID[route.exitFacility.facilityID] == route.exitFacility,
      route.entryFacility.canEnter,
      route.exitFacility.canExit
    else {
      throw ShutoPlannedRouteRuntimeCompilationError
        .facilityBindingMismatch
    }
    let reviewedMovementByIndex = Dictionary(
      uniqueKeysWithValues: route.edges.indices.dropFirst().compactMap {
        index -> (Int, ShutoJunctionMovementDefinition)? in
        guard
          let definition =
            ShutoJunctionMovementCatalog.releasedDefinition(
              database: database,
              incoming: route.edges[index - 1],
              outgoing: route.edges[index]
            )
        else {
          return nil
        }
        return (index, definition)
      }
    )
    guard
      route.edges.count == route.routePlan.occurrences.count,
      !route.edges.isEmpty,
      zip(route.routePlan.occurrences, route.edges).enumerated()
        .allSatisfy({
          offset, binding in
          let (occurrence, edge) = binding
          guard occurrence.index == offset else { return false }
          if let reviewedMovement = reviewedMovementByIndex[offset] {
            return occurrence.kind == .junctionMovement
              && occurrence.entityID == reviewedMovement.id
          }
          return occurrence.entityID == edge.edgeID
            && occurrence.kind
              == (edge.kind == "LINK" ? .junctionMovement : .edge)
        })
    else {
      throw ShutoPlannedRouteRuntimeCompilationError
        .invalidRoutePlanBinding
    }
    guard
      route.edges.allSatisfy({ edgesByID[$0.edgeID] == $0 }),
      route.entryFacility.entryEdgeCandidates.contains(where: {
        $0.edgeID == route.edges.first?.edgeID
      }),
      route.exitFacility.exitEdgeCandidates.contains(where: {
        $0.edgeID == route.edges.last?.edgeID
      })
    else {
      throw ShutoPlannedRouteRuntimeCompilationError
        .networkEdgeBindingMismatch
    }
    guard
      zip(route.edges, route.edges.dropFirst()).allSatisfy({
        $0.toNodeID == $1.fromNodeID
      })
    else {
      throw ShutoPlannedRouteRuntimeCompilationError
        .discontinuousRouteEdgeOrder
    }

    guard
      let firstNode = route.edges.first.flatMap({
        nodesByID[$0.fromNodeID]
      })
    else {
      throw ShutoPlannedRouteRuntimeCompilationError
        .routeGeometryMismatch
    }
    let expectedCoordinates =
      [firstNode.coordinate]
      + route.edges.compactMap { nodesByID[$0.toNodeID]?.coordinate }
    let expectedDistance = route.edges.reduce(0) {
      $0 + $1.lengthMeters
    }
    var expectedRouteIDs: [String] = []
    for edge in route.edges {
      let candidates = edge.routeMemberships.map(\.routeID)
      let next =
        candidates.first(where: { $0 == expectedRouteIDs.last })
        ?? candidates.first
      if let next, next != expectedRouteIDs.last {
        expectedRouteIDs.append(next)
      }
    }
    guard
      expectedCoordinates.count == route.edges.count + 1,
      route.coordinates == expectedCoordinates,
      abs(route.distanceMeters - expectedDistance) < 0.001,
      route.routeIDsInOrder == expectedRouteIDs,
      route.routePlan.actualDistanceKM.map({
        abs($0 - expectedDistance / 1_000) < 0.000_001
      }) ?? true
    else {
      throw ShutoPlannedRouteRuntimeCompilationError
        .routeGeometryMismatch
    }

    let routeNodeIDs = Set(
      route.edges.flatMap { [$0.fromNodeID, $0.toNodeID] }
    )
    let corridorDatabaseEdges = database.edges.filter {
      routeNodeIDs.contains($0.fromNodeID)
        || routeNodeIDs.contains($0.toNodeID)
    }
    let corridorEdgeIDs = Set(corridorDatabaseEdges.map(\.edgeID))
    let outgoingEdges = Dictionary(
      grouping: corridorDatabaseEdges,
      by: \.fromNodeID
    )

    func matcherEdge(
      _ edge: ShutoNetworkDatabase.Edge
    ) throws -> RouteMatcherDirectedEdge {
      guard let from = nodesByID[edge.fromNodeID] else {
        throw
          ShutoPlannedRouteRuntimeCompilationError
          .missingNode(edge.fromNodeID)
      }
      guard let to = nodesByID[edge.toNodeID] else {
        throw
          ShutoPlannedRouteRuntimeCompilationError
          .missingNode(edge.toNodeID)
      }
      return RouteMatcherDirectedEdge(
        id: edge.edgeID,
        coordinates: [
          MatcherCoordinate(
            latitude: from.latitude,
            longitude: from.longitude
          ),
          MatcherCoordinate(
            latitude: to.latitude,
            longitude: to.longitude
          ),
        ],
        successorEdgeIDs: Set(
          outgoingEdges[edge.toNodeID, default: []]
            .map(\.edgeID)
            .filter(corridorEdgeIDs.contains)
        )
      )
    }

    let corridorEdges = try corridorDatabaseEdges.map(matcherEdge)
    let corridor = RouteMatcherCorridor(
      id: "\(route.routePlan.id).matcher-corridor.v1",
      networkSnapshotID: database.networkSnapshotID,
      routePlanID: route.routePlan.id,
      edges: corridorEdges,
      occurrences: zip(route.routePlan.occurrences, route.edges).map {
        occurrence, edge in
        RouteMatcherOccurrence(
          id: occurrence.id,
          index: occurrence.index,
          directedEdgeID: edge.edgeID
        )
      }
    )
    let guidanceMatches = ShutoJunctionGuidanceCompiler.compile(
      database: database,
      route: route
    )
    let decisionZones = guidanceMatches.map { match in
      DecisionZoneProgressDefinition(
        id:
          "\(match.definition.id)."
          + "\(match.outgoingOccurrenceID).decision-zone",
        networkSnapshotID: database.networkSnapshotID,
        routePlanID: route.routePlan.id,
        movementOccurrenceID: match.outgoingOccurrenceID,
        entryOffsetMeters: 0
      )
    }
    let zonesByMovementOccurrenceID = Dictionary(
      uniqueKeysWithValues: decisionZones.map {
        ($0.movementOccurrenceID, $0)
      }
    )
    let releasedGuidance = guidanceMatches.compactMap {
      match -> ReleasedGuidanceDefinition? in
      guard
        let decisionZone =
          zonesByMovementOccurrenceID[match.outgoingOccurrenceID]
      else {
        return nil
      }
      let definition = match.definition
      let maneuver: GuidanceManeuver
      switch definition.branchSide {
      case .left:
        maneuver = .branchLeft
      case .right:
        maneuver = .branchRight
      case .straight:
        maneuver = .stayMainline
      }
      return ReleasedGuidanceDefinition(
        anchor: GuidanceAnchorDefinition(
          occurrenceID: match.incomingOccurrenceID,
          anchorID: "COMMIT",
          promptID:
            "\(definition.id)."
            + "\(match.outgoingOccurrenceID).commit"
        ),
        triggerDistanceMeters:
          definition.commitTriggerDistanceMeters,
        frameTemplate: GuidanceFrameTemplate(
          movementOccurrenceID: match.outgoingOccurrenceID,
          decisionZoneID: decisionZone.id,
          stage: .commit,
          decisionPointNameJapanese: match.junctionNameJA,
          localizedDecisionPointNames:
            definition.localizedJunctionNames,
          maneuver: maneuver,
          lanePreparation: .none,
          presentationSource: GuidancePresentationSource(
            routeShields: definition.routeShields,
            japaneseSignText: definition.japaneseSignText,
            localizedContent: definition.localizedContent
          )
        )
      )
    }
    let issues = NavigationRuntimeConfigurationValidator.issues(
      routePlan: route.routePlan,
      matcherCorridor: corridor,
      decisionZones: decisionZones,
      releasedGuidance: releasedGuidance
    )
    guard issues.isEmpty else {
      throw
        ShutoPlannedRouteRuntimeCompilationError
        .invalidMatcherCorridor(issues)
    }

    let corridorByID = Dictionary(
      uniqueKeysWithValues: corridorEdges.map { ($0.id, $0) }
    )
    let routeMatcherEdges = try route.edges.map { edge in
      guard let matcherEdge = corridorByID[edge.edgeID] else {
        throw ShutoPlannedRouteRuntimeCompilationError
          .invalidRoutePlanBinding
      }
      return matcherEdge
    }
    return ShutoPlannedRouteRuntimeAssets(
      routePlan: route.routePlan,
      matcherCorridor: corridor,
      decisionZones: decisionZones,
      releasedGuidance: releasedGuidance,
      recoveryCandidates: deriveRecoveryCandidates(
        database: database,
        route: route
      ),
      routeEdges: routeMatcherEdges,
      routeEdgeLengthsMeters: route.edges.map(\.lengthMeters)
    )
  }

  /// Wrong-turn recovery candidates: for every plan node where a legal
  /// alternative movement diverges from the plan, a bounded directed search
  /// over the whole snapshot finds the cheapest legal path back onto a
  /// strictly later plan occurrence. The rejoin objective always stays the
  /// active RoutePlan — loops make this natural because the ring comes back
  /// around. Candidates derive from the same released snapshot as the plan
  /// itself and never mutate it; they carry no navigation-grade guidance
  /// claim (reviewed movements and speech remain separately gated).
  static func deriveRecoveryCandidates(
    database: ShutoNetworkDatabase,
    route: ShutoPlannedRoute
  ) -> [RecoveryCandidate] {
    let occurrences = route.routePlan.occurrences
    let edges = route.edges
    guard occurrences.count == edges.count, edges.count > 1 else {
      return []
    }
    let maximumRecoveryMeters = 30_000.0

    var outgoing: [Int64: [ShutoNetworkDatabase.Edge]] = [:]
    for edge in database.edges {
      outgoing[edge.fromNodeID, default: []].append(edge)
    }
    for node in outgoing.keys {
      outgoing[node]?.sort { $0.edgeID < $1.edgeID }
    }
    // Plan occurrence indices that begin at a node, in plan order.
    var planIndicesByNode: [Int64: [Int]] = [:]
    for (index, edge) in edges.enumerated() {
      planIndicesByNode[edge.fromNodeID, default: []].append(index)
    }
    func rejoinIndex(at node: Int64, after divergence: Int) -> Int? {
      planIndicesByNode[node]?.first { $0 > divergence }
    }

    var candidates: [RecoveryCandidate] = []
    for index in 0..<(edges.count - 1) {
      let divergenceNode = edges[index].toNodeID
      let plannedNextEdgeID = edges[index + 1].edgeID
      let alternatives = (outgoing[divergenceNode] ?? [])
        .filter { $0.edgeID != plannedNextEdgeID }
      guard !alternatives.isEmpty else { continue }

      // Multi-source bounded Dijkstra seeded with every wrong turn at this
      // node; the first settled node that carries a later plan occurrence
      // is the cheapest legal rejoin.
      var distances: [Int64: Double] = [:]
      var previousEdge: [Int64: ShutoNetworkDatabase.Edge] = [:]
      var frontier: [(cost: Double, node: Int64)] = []
      func push(_ cost: Double, _ node: Int64) {
        frontier.append((cost, node))
        var child = frontier.count - 1
        while child > 0 {
          let parent = (child - 1) / 2
          guard frontier[child].cost < frontier[parent].cost else { break }
          frontier.swapAt(child, parent)
          child = parent
        }
      }
      func pop() -> (cost: Double, node: Int64)? {
        guard let top = frontier.first else { return nil }
        frontier[0] = frontier[frontier.count - 1]
        frontier.removeLast()
        var parent = 0
        while true {
          let left = parent * 2 + 1
          let right = left + 1
          var smallest = parent
          if left < frontier.count,
            frontier[left].cost < frontier[smallest].cost
          {
            smallest = left
          }
          if right < frontier.count,
            frontier[right].cost < frontier[smallest].cost
          {
            smallest = right
          }
          if smallest == parent { break }
          frontier.swapAt(parent, smallest)
          parent = smallest
        }
        return top
      }

      for alternative in alternatives {
        let cost = alternative.lengthMeters
        if cost <= maximumRecoveryMeters,
          cost < distances[alternative.toNodeID] ?? .infinity
        {
          distances[alternative.toNodeID] = cost
          previousEdge[alternative.toNodeID] = alternative
          push(cost, alternative.toNodeID)
        }
      }

      var settled: Set<Int64> = []
      var rejoin: (node: Int64, target: Int)?
      while let current = pop() {
        if settled.contains(current.node) { continue }
        settled.insert(current.node)
        if let target = rejoinIndex(at: current.node, after: index) {
          rejoin = (current.node, target)
          break
        }
        for edge in outgoing[current.node] ?? [] {
          let cost = current.cost + edge.lengthMeters
          guard cost <= maximumRecoveryMeters,
            cost < distances[edge.toNodeID] ?? .infinity
          else { continue }
          distances[edge.toNodeID] = cost
          previousEdge[edge.toNodeID] = edge
          push(cost, edge.toNodeID)
        }
      }
      guard let rejoin else { continue }

      var pathEdgeIDs: [String] = []
      var cursor = rejoin.node
      while let edge = previousEdge[cursor] {
        pathEdgeIDs.append(edge.edgeID)
        cursor = edge.fromNodeID
        if cursor == divergenceNode { break }
      }
      candidates.append(
        RecoveryCandidate(
          targetOccurrenceID: occurrences[rejoin.target].id,
          recoveryOccurrenceIDs: pathEdgeIDs.reversed(),
          isReleased: true,
          staysInAllowedTollDomain: true
        )
      )
    }
    return candidates
  }
}
