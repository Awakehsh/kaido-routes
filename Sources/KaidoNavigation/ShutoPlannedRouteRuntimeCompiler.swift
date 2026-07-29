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

  private let routeEdges: [RouteMatcherDirectedEdge]
  private let routeEdgeLengthsMeters: [Double]
  private let cumulativeDistanceAtOccurrence: [Double]
  private let totalDistanceMeters: Double

  package init(
    routePlan: RoutePlan,
    matcherCorridor: RouteMatcherCorridor,
    routeEdges: [RouteMatcherDirectedEdge],
    routeEdgeLengthsMeters: [Double]
  ) {
    self.routePlan = routePlan
    self.matcherCorridor = matcherCorridor
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
    guard
      route.edges.count == route.routePlan.occurrences.count,
      !route.edges.isEmpty,
      zip(route.routePlan.occurrences, route.edges).enumerated()
        .allSatisfy({
          offset, binding in
          let (occurrence, edge) = binding
          return occurrence.index == offset
            && occurrence.entityID == edge.edgeID
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
    let issues = NavigationRuntimeConfigurationValidator.issues(
      routePlan: route.routePlan,
      matcherCorridor: corridor,
      decisionZones: [],
      releasedGuidance: []
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
      routeEdges: routeMatcherEdges,
      routeEdgeLengthsMeters: route.edges.map(\.lengthMeters)
    )
  }
}
