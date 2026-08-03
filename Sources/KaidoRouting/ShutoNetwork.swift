import Foundation
import KaidoDomain

public struct ShutoCoordinate: Codable, Equatable, Hashable, Sendable {
  public let latitude: Double
  public let longitude: Double

  public init(latitude: Double, longitude: Double) {
    self.latitude = latitude
    self.longitude = longitude
  }
}

public struct ShutoNetworkDatabase: Decodable, Sendable {
  public struct Route: Decodable, Equatable, Sendable {
    public let routeID: String
    public let officialNameJA: String
    public let operationalStatus: String

    private enum CodingKeys: String, CodingKey {
      case routeID = "route_id"
      case officialNameJA = "official_name_ja"
      case operationalStatus = "operational_status"
    }
  }

  public struct Node: Decodable, Equatable, Sendable {
    public let nodeID: Int64
    public let latitude: Double
    public let longitude: Double

    public var coordinate: ShutoCoordinate {
      ShutoCoordinate(latitude: latitude, longitude: longitude)
    }

    private enum CodingKeys: String, CodingKey {
      case nodeID = "node_id"
      case latitude
      case longitude
    }
  }

  public struct RouteMembership: Decodable, Equatable, Hashable, Sendable {
    public let routeID: String
    public let directionsJA: [String]

    private enum CodingKeys: String, CodingKey {
      case routeID = "route_id"
      case directionsJA = "directions_ja"
    }
  }

  public struct Way: Decodable, Equatable, Sendable {
    public let wayID: Int64
    public let kind: String
    public let nodeIDs: [Int64]
    public let routeMemberships: [RouteMembership]
    public let tags: [String: String]

    private enum CodingKeys: String, CodingKey {
      case wayID = "way_id"
      case kind
      case nodeIDs = "node_ids"
      case routeMemberships = "route_memberships"
      case tags
    }
  }

  public struct Edge: Decodable, Equatable, Hashable, Sendable {
    public let edgeID: String
    public let fromNodeID: Int64
    public let toNodeID: Int64
    public let wayID: Int64
    public let segmentIndex: Int
    public let kind: String
    public let direction: String
    public let lengthMeters: Double
    public let routeMemberships: [RouteMembership]

    private enum CodingKeys: String, CodingKey {
      case edgeID = "edge_id"
      case fromNodeID = "from_node_id"
      case toNodeID = "to_node_id"
      case wayID = "way_id"
      case segmentIndex = "segment_index"
      case kind
      case direction
      case lengthMeters = "length_meters"
      case routeMemberships = "route_memberships"
    }
  }

  public struct FacilityEdgeCandidate:
    Decodable, Equatable, Hashable, Sendable
  {
    public let edgeID: String
    public let distanceMeters: Double

    private enum CodingKeys: String, CodingKey {
      case edgeID = "edge_id"
      case distanceMeters = "distance_meters"
    }
  }

  public struct Facility: Decodable, Equatable, Identifiable, Sendable {
    public var id: String { facilityID }

    public let facilityID: String
    public let routeID: String
    public let nameJA: String
    public let readingJA: String
    public let coordinate: ShutoCoordinate
    public let entranceDirections: [String]
    public let exitDirections: [String]
    public let etcOnly: Bool
    public let operationalStatus: String
    public let geometryMatchState: String
    public let entryEdgeCandidates: [FacilityEdgeCandidate]
    public let exitEdgeCandidates: [FacilityEdgeCandidate]

    public var canEnter: Bool {
      operationalStatus == "AVAILABLE" && !entryEdgeCandidates.isEmpty
    }

    public var canExit: Bool {
      operationalStatus == "AVAILABLE" && !exitEdgeCandidates.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
      case facilityID = "facility_id"
      case routeID = "route_id"
      case nameJA = "name_ja"
      case readingJA = "reading_ja"
      case coordinate
      case entranceDirections = "entrance_directions"
      case exitDirections = "exit_directions"
      case etcOnly = "etc_only"
      case operationalStatus = "operational_status"
      case geometryMatchState = "geometry_match_state"
      case entryEdgeCandidates = "entry_edge_candidates"
      case exitEdgeCandidates = "exit_edge_candidates"
    }
  }

  public struct Junction: Decodable, Equatable, Identifiable, Sendable {
    public var id: String { junctionID }

    public let junctionID: String
    public let nameJA: String
    public let officialDetailReference: String
    public let officialDetailSHA256: String
    public let coordinate: ShutoCoordinate?
    public let geometryMatchState: String
    public let osmNodeIDs: [Int64]

    private enum CodingKeys: String, CodingKey {
      case junctionID = "junction_id"
      case nameJA = "name_ja"
      case officialDetailReference = "official_detail_reference"
      case officialDetailSHA256 = "official_detail_sha256"
      case coordinate
      case geometryMatchState = "geometry_match_state"
      case osmNodeIDs = "osm_node_ids"
    }
  }

  public struct ParkingArea: Decodable, Equatable, Identifiable, Sendable {
    public var id: String { parkingAreaID }

    public let parkingAreaID: String
    public let nameJA: String
    public let baseNameJA: String
    public let officialRouteNameJA: String
    public let routeID: String?
    public let directionJA: String?
    public let dynamicStatus: String
    public let coordinate: ShutoCoordinate

    private enum CodingKeys: String, CodingKey {
      case parkingAreaID = "parking_area_id"
      case nameJA = "name_ja"
      case baseNameJA = "base_name_ja"
      case officialRouteNameJA = "official_route_name_ja"
      case routeID = "route_id"
      case directionJA = "direction_ja"
      case dynamicStatus = "dynamic_status"
      case coordinate
    }
  }

  public let schemaVersion: String
  public let databaseID: String
  public let networkSnapshotID: String
  public let verificationState: String
  public let checkedAt: String
  public let routes: [Route]
  public let nodes: [Node]
  public let ways: [Way]
  public let edges: [Edge]
  public let directionalFacilities: [Facility]
  public let junctions: [Junction]
  public let parkingAreas: [ParkingArea]

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case databaseID = "database_id"
    case networkSnapshotID = "network_snapshot_id"
    case verificationState = "verification_state"
    case checkedAt = "checked_at"
    case routes
    case nodes
    case ways
    case edges
    case directionalFacilities = "directional_facilities"
    case junctions
    case parkingAreas = "parking_areas"
  }

  public func validate() throws {
    guard schemaVersion == "1.0" else {
      throw ShutoNetworkError.unsupportedSchema
    }
    guard routes.count == 26, directionalFacilities.count >= 140,
      junctions.count >= 35, parkingAreas.count >= 15,
      nodes.count >= 2_000, edges.count >= 2_000
    else {
      throw ShutoNetworkError.incompleteNetwork
    }
    guard Set(nodes.map(\.nodeID)).count == nodes.count,
      Set(edges.map(\.edgeID)).count == edges.count,
      Set(directionalFacilities.map(\.facilityID)).count
        == directionalFacilities.count,
      Set(junctions.map(\.junctionID)).count == junctions.count
    else {
      throw ShutoNetworkError.duplicateIdentity
    }
    let nodeIDs = Set(nodes.map(\.nodeID))
    guard edges.allSatisfy({
      $0.lengthMeters > 0 && nodeIDs.contains($0.fromNodeID)
        && nodeIDs.contains($0.toNodeID)
    }) else {
      throw ShutoNetworkError.invalidEdge
    }
    guard junctions.allSatisfy({
      !$0.osmNodeIDs.isEmpty
        && $0.osmNodeIDs.allSatisfy(nodeIDs.contains)
    }) else {
      throw ShutoNetworkError.invalidJunction
    }
  }
}

public enum ShutoRoutePreference:
  String, CaseIterable, Codable, Sendable
{
  case recommended = "RECOMMENDED"
  case fewerJunctions = "FEWER_JUNCTIONS"
  case preferBayshore = "PREFER_BAYSHORE"
}

public struct ShutoPlannedRoute: Equatable, Sendable {
  public let routePlan: RoutePlan
  public let entryFacility: ShutoNetworkDatabase.Facility
  public let exitFacility: ShutoNetworkDatabase.Facility
  public let edges: [ShutoNetworkDatabase.Edge]
  public let coordinates: [ShutoCoordinate]
  public let routeIDsInOrder: [String]
  public let distanceMeters: Double
  public let preference: ShutoRoutePreference

  public init(
    routePlan: RoutePlan,
    entryFacility: ShutoNetworkDatabase.Facility,
    exitFacility: ShutoNetworkDatabase.Facility,
    edges: [ShutoNetworkDatabase.Edge],
    coordinates: [ShutoCoordinate],
    routeIDsInOrder: [String],
    distanceMeters: Double,
    preference: ShutoRoutePreference
  ) {
    self.routePlan = routePlan
    self.entryFacility = entryFacility
    self.exitFacility = exitFacility
    self.edges = edges
    self.coordinates = coordinates
    self.routeIDsInOrder = routeIDsInOrder
    self.distanceMeters = distanceMeters
    self.preference = preference
  }
}

public struct ShutoRouteRecommendation: Equatable, Sendable {
  public let route: ShutoPlannedRoute
  public let surfaceAccessDistanceMeters: Double
  public let surfaceEgressDistanceMeters: Double
  public let totalScoreMeters: Double

  public init(
    route: ShutoPlannedRoute,
    surfaceAccessDistanceMeters: Double,
    surfaceEgressDistanceMeters: Double,
    totalScoreMeters: Double
  ) {
    self.route = route
    self.surfaceAccessDistanceMeters = surfaceAccessDistanceMeters
    self.surfaceEgressDistanceMeters = surfaceEgressDistanceMeters
    self.totalScoreMeters = totalScoreMeters
  }
}

public enum ShutoNetworkError: Error, Equatable {
  case unsupportedSchema
  case incompleteNetwork
  case duplicateIdentity
  case invalidEdge
  case invalidJunction
  case facilityUnavailable
  case routeUnavailable
}

public struct ShutoRoutePlanner: Sendable {
  private struct QueueValue: Comparable {
    let cost: Double
    let nodeID: Int64

    static func < (lhs: QueueValue, rhs: QueueValue) -> Bool {
      if lhs.cost != rhs.cost {
        return lhs.cost < rhs.cost
      }
      return lhs.nodeID < rhs.nodeID
    }
  }

  let database: ShutoNetworkDatabase
  let nodesByID: [Int64: ShutoNetworkDatabase.Node]
  let edgesByID: [String: ShutoNetworkDatabase.Edge]
  let outgoingEdges: [Int64: [ShutoNetworkDatabase.Edge]]
  let facilitiesByID: [String: ShutoNetworkDatabase.Facility]

  public init(database: ShutoNetworkDatabase) throws {
    try database.validate()
    self.database = database
    nodesByID = Dictionary(
      uniqueKeysWithValues: database.nodes.map { ($0.nodeID, $0) }
    )
    edgesByID = Dictionary(
      uniqueKeysWithValues: database.edges.map { ($0.edgeID, $0) }
    )
    outgoingEdges = Dictionary(
      grouping: database.edges,
      by: \.fromNodeID
    )
    facilitiesByID = Dictionary(
      uniqueKeysWithValues:
        database.directionalFacilities.map { ($0.facilityID, $0) }
    )
  }

  public func plan(
    entryFacilityID: String,
    exitFacilityID: String,
    preference: ShutoRoutePreference = .recommended
  ) throws -> ShutoPlannedRoute {
    guard let entryFacility = facilitiesByID[entryFacilityID],
      let exitFacility = facilitiesByID[exitFacilityID],
      entryFacility.canEnter,
      exitFacility.canExit
    else {
      throw ShutoNetworkError.facilityUnavailable
    }
    return try shortestRoute(
      entryFacility: entryFacility,
      exitFacility: exitFacility,
      preference: preference
    )
  }

  public func recommend(
    from origin: ShutoCoordinate,
    to destination: ShutoCoordinate,
    preference: ShutoRoutePreference = .recommended,
    maximumFacilityCandidates: Int = 7
  ) throws -> [ShutoRouteRecommendation] {
    let entryCandidates = database.directionalFacilities
      .filter(\.canEnter)
      .map {
        ($0, Self.distance(origin, $0.coordinate))
      }
      .sorted {
        if $0.1 != $1.1 { return $0.1 < $1.1 }
        return $0.0.facilityID < $1.0.facilityID
      }
      .prefix(maximumFacilityCandidates)
    let exitCandidates = database.directionalFacilities
      .filter(\.canExit)
      .map {
        ($0, Self.distance($0.coordinate, destination))
      }
      .sorted {
        if $0.1 != $1.1 { return $0.1 < $1.1 }
        return $0.0.facilityID < $1.0.facilityID
      }
      .prefix(maximumFacilityCandidates)

    var recommendations: [ShutoRouteRecommendation] = []
    for (entry, accessDistance) in entryCandidates {
      for (exit, egressDistance) in exitCandidates
      where entry.facilityID != exit.facilityID {
        guard
          let route = try? shortestRoute(
            entryFacility: entry,
            exitFacility: exit,
            preference: preference
          ),
          route.distanceMeters >= 750
        else {
          continue
        }
        recommendations.append(
          ShutoRouteRecommendation(
            route: route,
            surfaceAccessDistanceMeters: accessDistance,
            surfaceEgressDistanceMeters: egressDistance,
            totalScoreMeters:
              route.distanceMeters
              + accessDistance * 1.25
              + egressDistance * 1.25
              + routeComplexityPenalty(
                route,
                preference: preference
              )
          )
        )
      }
    }
    var signatures = Set<String>()
    return recommendations
      .sorted {
        if $0.totalScoreMeters != $1.totalScoreMeters {
          return $0.totalScoreMeters < $1.totalScoreMeters
        }
        return $0.route.routePlan.id < $1.route.routePlan.id
      }
      .filter {
        let signature =
          $0.route.entryFacility.facilityID + "|"
          + $0.route.exitFacility.facilityID + "|"
          + $0.route.routeIDsInOrder.joined(separator: ",")
        return signatures.insert(signature).inserted
      }
      .prefix(3)
      .map { $0 }
  }

  private func shortestRoute(
    entryFacility: ShutoNetworkDatabase.Facility,
    exitFacility: ShutoNetworkDatabase.Facility,
    preference: ShutoRoutePreference
  ) throws -> ShutoPlannedRoute {
    let entryEdges = entryFacility.entryEdgeCandidates.compactMap {
      candidate in
      edgesByID[candidate.edgeID].map {
        edge in (edge, candidate.distanceMeters)
      }
    }
    let exitEdges = exitFacility.exitEdgeCandidates.compactMap {
      candidate in
      edgesByID[candidate.edgeID].map {
        edge in (edge, candidate.distanceMeters)
      }
    }
    guard !entryEdges.isEmpty, !exitEdges.isEmpty else {
      throw ShutoNetworkError.facilityUnavailable
    }

    var distances: [Int64: Double] = [:]
    var previousEdges: [Int64: ShutoNetworkDatabase.Edge] = [:]
    var sourceEdgeByNode: [Int64: ShutoNetworkDatabase.Edge] = [:]
    var queue = MinHeap<QueueValue>()
    for (edge, matchDistance) in entryEdges {
      let cost = edgeCost(edge, preference: preference) + matchDistance
      if cost < distances[edge.toNodeID, default: .infinity] {
        distances[edge.toNodeID] = cost
        sourceEdgeByNode[edge.toNodeID] = edge
        queue.insert(QueueValue(cost: cost, nodeID: edge.toNodeID))
      }
    }
    let exitEdgesByNode = Dictionary(
      grouping: exitEdges,
      by: { $0.0.fromNodeID }
    )
    var selectedTarget:
      (
        nodeID: Int64,
        exitEdge: ShutoNetworkDatabase.Edge,
        totalCost: Double
      )?

    while let current = queue.removeMinimum() {
      guard current.cost == distances[current.nodeID] else { continue }
      if let candidates = exitEdgesByNode[current.nodeID] {
        for (edge, matchDistance) in candidates {
          let total =
            current.cost + edgeCost(edge, preference: preference)
            + matchDistance
          if selectedTarget == nil
            || total < selectedTarget!.totalCost
          {
            selectedTarget = (current.nodeID, edge, total)
          }
        }
      }
      if let selectedTarget, current.cost > selectedTarget.totalCost {
        break
      }
      for edge in outgoingEdges[current.nodeID, default: []] {
        let candidate =
          current.cost + edgeCost(edge, preference: preference)
        if candidate >= distances[edge.toNodeID, default: .infinity] {
          continue
        }
        distances[edge.toNodeID] = candidate
        previousEdges[edge.toNodeID] = edge
        queue.insert(
          QueueValue(cost: candidate, nodeID: edge.toNodeID)
        )
      }
    }
    guard let selectedTarget else {
      throw ShutoNetworkError.routeUnavailable
    }

    var reversedEdges: [ShutoNetworkDatabase.Edge] = []
    var nodeID = selectedTarget.nodeID
    while let edge = previousEdges[nodeID] {
      reversedEdges.append(edge)
      nodeID = edge.fromNodeID
    }
    guard let entryEdge = sourceEdgeByNode[nodeID] else {
      throw ShutoNetworkError.routeUnavailable
    }
    var routeEdges = [entryEdge] + reversedEdges.reversed()
    if routeEdges.last?.edgeID != selectedTarget.exitEdge.edgeID {
      routeEdges.append(selectedTarget.exitEdge)
    }
    routeEdges = routeEdges.reduce(into: []) { result, edge in
      if result.last?.edgeID != edge.edgeID {
        result.append(edge)
      }
    }
    return assemblePlannedRoute(
      routeEdges: routeEdges,
      planID:
        "shuto.\(entryFacility.facilityID)."
        + "\(exitFacility.facilityID).\(preference.rawValue.lowercased())",
      entryFacility: entryFacility,
      exitFacility: exitFacility,
      preference: preference
    )
  }

  func assemblePlannedRoute(
    routeEdges: [ShutoNetworkDatabase.Edge],
    planID: String,
    entryFacility: ShutoNetworkDatabase.Facility,
    exitFacility: ShutoNetworkDatabase.Facility,
    preference: ShutoRoutePreference
  ) -> ShutoPlannedRoute {
    let coordinates = routeCoordinates(routeEdges)
    let routeIDs = orderedRouteIDs(routeEdges)
    let distanceMeters = routeEdges.reduce(0) {
      $0 + $1.lengthMeters
    }
    let occurrences = routeEdges.enumerated().map { index, edge in
      let reviewedMovement =
        index > 0
        ? ShutoJunctionMovementCatalog.releasedDefinition(
          database: database,
          incoming: routeEdges[index - 1],
          outgoing: edge
        )
        : nil
      return RouteOccurrence(
        id: "shuto.\(index).\(edge.edgeID)",
        index: index,
        kind:
          reviewedMovement != nil || edge.kind == "LINK"
          ? .junctionMovement
          : .edge,
        entityID: reviewedMovement?.id ?? edge.edgeID,
        tollDomainID: "shuto.toll-domain"
      )
    }
    let routePlan = RoutePlan(
      id: planID,
      networkSnapshotID: database.networkSnapshotID,
      entryFacilityID: entryFacility.facilityID,
      exitFacilityID: exitFacility.facilityID,
      recoveryPolicy: .safeRejoin,
      actualDistanceKM: distanceMeters / 1_000,
      occurrences: occurrences
    )
    return ShutoPlannedRoute(
      routePlan: routePlan,
      entryFacility: entryFacility,
      exitFacility: exitFacility,
      edges: routeEdges,
      coordinates: coordinates,
      routeIDsInOrder: routeIDs,
      distanceMeters: distanceMeters,
      preference: preference
    )
  }

  func edgeCost(
    _ edge: ShutoNetworkDatabase.Edge,
    preference: ShutoRoutePreference
  ) -> Double {
    let routeIDs = Set(edge.routeMemberships.map(\.routeID))
    switch preference {
    case .recommended:
      return edge.lengthMeters + (edge.kind == "LINK" ? 180 : 0)
    case .fewerJunctions:
      return edge.lengthMeters + (edge.kind == "LINK" ? 800 : 0)
    case .preferBayshore:
      return edge.lengthMeters * (routeIDs.contains("B") ? 0.86 : 1)
        + (edge.kind == "LINK" ? 120 : 0)
    }
  }

  private func routeComplexityPenalty(
    _ route: ShutoPlannedRoute,
    preference: ShutoRoutePreference
  ) -> Double {
    let routeChanges = max(0, route.routeIDsInOrder.count - 1)
    let junctionMovements = route.edges.filter {
      $0.kind == "LINK"
    }.count
    switch preference {
    case .recommended:
      return Double(routeChanges) * 1_200
        + Double(junctionMovements) * 30
    case .fewerJunctions:
      return Double(routeChanges) * 3_000
        + Double(junctionMovements) * 90
    case .preferBayshore:
      return Double(routeChanges) * 800
        + Double(junctionMovements) * 20
    }
  }

  func routeCoordinates(
    _ edges: [ShutoNetworkDatabase.Edge]
  ) -> [ShutoCoordinate] {
    guard let first = edges.first,
      let firstNode = nodesByID[first.fromNodeID]
    else {
      return []
    }
    return [firstNode.coordinate]
      + edges.compactMap { nodesByID[$0.toNodeID]?.coordinate }
  }

  func orderedRouteIDs(
    _ edges: [ShutoNetworkDatabase.Edge]
  ) -> [String] {
    var result: [String] = []
    for edge in edges {
      let candidates = edge.routeMemberships.map(\.routeID)
      let next =
        candidates.first(where: { $0 == result.last })
        ?? candidates.first
      if let next, next != result.last {
        result.append(next)
      }
    }
    return result
  }

  static func distance(
    _ first: ShutoCoordinate,
    _ second: ShutoCoordinate
  ) -> Double {
    let latitude1 = first.latitude * .pi / 180
    let longitude1 = first.longitude * .pi / 180
    let latitude2 = second.latitude * .pi / 180
    let longitude2 = second.longitude * .pi / 180
    let latitudeDelta = latitude2 - latitude1
    let longitudeDelta = longitude2 - longitude1
    let value =
      pow(sin(latitudeDelta / 2), 2)
      + cos(latitude1) * cos(latitude2)
      * pow(sin(longitudeDelta / 2), 2)
    return 2 * 6_371_000 * asin(min(1, sqrt(value)))
  }
}

struct MinHeap<Element: Comparable> {
  private var values: [Element] = []

  var isEmpty: Bool { values.isEmpty }

  mutating func insert(_ value: Element) {
    values.append(value)
    var index = values.count - 1
    while index > 0 {
      let parent = (index - 1) / 2
      guard values[index] < values[parent] else { break }
      values.swapAt(index, parent)
      index = parent
    }
  }

  mutating func removeMinimum() -> Element? {
    guard !values.isEmpty else { return nil }
    if values.count == 1 {
      return values.removeLast()
    }
    let minimum = values[0]
    values[0] = values.removeLast()
    var index = 0
    while true {
      let left = index * 2 + 1
      let right = left + 1
      var candidate = index
      if left < values.count && values[left] < values[candidate] {
        candidate = left
      }
      if right < values.count && values[right] < values[candidate] {
        candidate = right
      }
      guard candidate != index else { break }
      values.swapAt(index, candidate)
      index = candidate
    }
    return minimum
  }
}
