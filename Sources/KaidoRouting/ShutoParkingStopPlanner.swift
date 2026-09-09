import Foundation

public struct ShutoParkingStopOption: Equatable, Identifiable, Sendable {
  public var id: String { parkingArea.parkingAreaID }
  public let parkingArea: ShutoNetworkDatabase.ParkingArea
  public let departureIndex: Int
  public let returnIndex: Int
  public let addedDistanceMeters: Double
  let edges: [ShutoNetworkDatabase.Edge]
}

extension ShutoRoutePlanner {
  /// A stop replaces only the local bypass between two ordered route nodes.
  /// Searching stops at the route, so another lap cannot make an opposite-side
  /// PA look reachable. Connecting legs stay within the expressway graph and
  /// cannot cross another PA interior.
  public func parkingStopOptions(for route: ShutoPlannedRoute) -> [ShutoParkingStopOption] {
    let visited = Set(route.routePlan.occurrences.compactMap(\.parkingAreaID))
    var indicesByNode: [Int64: [Int]] = [:]
    for (index, edge) in route.edges.enumerated() {
      indicesByNode[edge.fromNodeID, default: []].append(index)
    }
    let routeNodes = Set(indicesByNode.keys)
    let incoming = Dictionary(grouping: database.edges, by: \.toNodeID)
    var options: [ShutoParkingStopOption] = []
    for parking in database.parkingAreas where parking.isDrivable && !visited.contains(parking.parkingAreaID) {
      guard let access = parking.accessNodeID, let exit = parking.returnNodeID,
        let interiorIDs = parking.interiorEdgeIDs else { continue }
      let interior = interiorIDs.compactMap { edgesByID[$0] }
      guard interior.count == interiorIDs.count else { continue }
      let approaches = parkingConnections(
        from: access, reverse: true, routeNodes: routeNodes,
        adjacency: incoming
      )
      let returns = parkingConnections(
        from: exit, reverse: false, routeNodes: routeNodes,
        adjacency: outgoingEdges
      )
      var best: ShutoParkingStopOption?
      for approach in approaches {
        for start in indicesByNode[approach.node, default: []] {
          for returning in returns {
            guard let end = indicesByNode[returning.node]?.first(where: { $0 >= start }),
              !route.lapBoundaryOccurrenceIndices.contains(where: { start < $0 && $0 < end }),
              !route.edges[start..<end].contains(where: { $0.kind == "PARKING" })
            else { continue }
            let bypassDistance = route.edges[start..<end].reduce(0) { $0 + $1.lengthMeters }
            // PA access is local, not permission to replace an expressway tour.
            guard bypassDistance <= Self.parkingConnectionLimitMeters else { continue }
            let edges = approach.edges + interior + returning.edges
            let distance = edges.reduce(0) { $0 + $1.lengthMeters }
            let option = ShutoParkingStopOption(
              parkingArea: parking, departureIndex: start, returnIndex: end,
              addedDistanceMeters: distance - bypassDistance, edges: edges
            )
            if best == nil || start < best!.departureIndex
              || (start == best!.departureIndex && option.addedDistanceMeters < best!.addedDistanceMeters) {
              best = option
            }
          }
        }
      }
      if let best { options.append(best) }
    }
    return options.sorted {
      if $0.departureIndex != $1.departureIndex { return $0.departureIndex < $1.departureIndex }
      return $0.id < $1.id
    }
  }

  public func addingParkingStops(
    _ parkingAreaIDs: [String], to base: ShutoPlannedRoute
  ) throws -> ShutoPlannedRoute {
    guard !parkingAreaIDs.isEmpty else { return base }
    let ids = Set(parkingAreaIDs)
    let selected = parkingStopOptions(for: base).filter { ids.contains($0.id) }
    guard ids.count == parkingAreaIDs.count, selected.count == ids.count else {
      throw ShutoNetworkError.facilityUnavailable
    }
    var edges: [ShutoNetworkDatabase.Edge] = []
    var cursor = 0
    var boundaries = base.lapBoundaryOccurrenceIndices
    for stop in selected {
      guard stop.departureIndex >= cursor else { throw ShutoNetworkError.routeUnavailable }
      edges.append(contentsOf: base.edges[cursor..<stop.departureIndex])
      edges.append(contentsOf: stop.edges)
      let delta = stop.edges.count - (stop.returnIndex - stop.departureIndex)
      for index in boundaries.indices where base.lapBoundaryOccurrenceIndices[index] > stop.departureIndex {
        boundaries[index] += delta
      }
      cursor = stop.returnIndex
    }
    edges.append(contentsOf: base.edges[cursor...])
    guard zip(edges, edges.dropFirst()).allSatisfy({ $0.toNodeID == $1.fromNodeID }) else {
      throw ShutoNetworkError.routeUnavailable
    }
    return assemblePlannedRoute(
      routeEdges: edges,
      planID: base.routePlan.id + ".pa." + selected.map(\.id).joined(separator: "+"),
      entryFacility: base.entryFacility, exitFacility: base.exitFacility,
      preference: base.preference, lapBoundaryOccurrenceIndices: boundaries
    )
  }

  private static let parkingConnectionLimitMeters = 3_000.0

  private struct ParkingQueueEntry: Comparable {
    let distance: Double
    let node: Int64
    static func < (lhs: Self, rhs: Self) -> Bool {
      lhs.distance == rhs.distance ? lhs.node < rhs.node : lhs.distance < rhs.distance
    }
  }

  private func parkingConnections(
    from start: Int64, reverse: Bool, routeNodes: Set<Int64>,
    adjacency: [Int64: [ShutoNetworkDatabase.Edge]]
  ) -> [(node: Int64, edges: [ShutoNetworkDatabase.Edge])] {
    var queue = MinHeap<ParkingQueueEntry>()
    queue.insert(.init(distance: 0, node: start))
    var distances: [Int64: Double] = [start: 0]
    var previous: [Int64: ShutoNetworkDatabase.Edge] = [:]
    var result: [(node: Int64, edges: [ShutoNetworkDatabase.Edge])] = []
    while let current = queue.removeMinimum() {
      guard distances[current.node] == current.distance else { continue }
      if routeNodes.contains(current.node) {
        var edges: [ShutoNetworkDatabase.Edge] = []
        var node = current.node
        while let edge = previous[node] {
          edges.append(edge)
          node = reverse ? edge.toNodeID : edge.fromNodeID
        }
        result.append((current.node, reverse ? edges : edges.reversed()))
        continue
      }
      for edge in adjacency[current.node, default: []]
      where edge.kind == "MAINLINE" || edge.kind == "LINK" {
        let next = reverse ? edge.fromNodeID : edge.toNodeID
        let distance = current.distance + edge.lengthMeters
        guard distance <= Self.parkingConnectionLimitMeters,
          distance < distances[next, default: .infinity] else { continue }
        distances[next] = distance
        previous[next] = edge
        queue.insert(.init(distance: distance, node: next))
      }
    }
    return result
  }
}
