import Foundation
import KaidoDomain

/// A drivable loop experience over the whole-network snapshot: a set of member
/// routes, one carriageway direction, and a handful of anchor facilities whose
/// positions pin the loop. Anchors are an unordered set — the planner discovers
/// travel order from directed forward distance, so one definition serves any
/// compatible entrance.
public struct ShutoCircuitDefinition: Equatable, Identifiable, Sendable {
  public var id: String { circuitID }

  public let circuitID: String
  public let displayNameJA: String
  public let memberRouteIDs: Set<String>
  public let entranceDirectionJA: String
  public let anchorFacilityIDs: [String]

  public init(
    circuitID: String,
    displayNameJA: String,
    memberRouteIDs: Set<String>,
    entranceDirectionJA: String,
    anchorFacilityIDs: [String]
  ) {
    self.circuitID = circuitID
    self.displayNameJA = displayNameJA
    self.memberRouteIDs = memberRouteIDs
    self.entranceDirectionJA = entranceDirectionJA
    self.anchorFacilityIDs = anchorFacilityIDs
  }

  /// C2 Central Circular inner loop, closed between Oi JCT and Kasai JCT by
  /// the Bayshore Route. C2 alone is not a closed ring.
  public static let c2InnerWithBayshore = ShutoCircuitDefinition(
    circuitID: "shuto.circuit.c2-inner-bayshore",
    displayNameJA: "中央環状線 内回り＋湾岸線",
    memberRouteIDs: ["C2", "B"],
    entranceDirectionJA: "内回り",
    anchorFacilityIDs: [
      "shuto.ic.c2.gotanda",
      "shuto.ic.c2.seishincho",
      "shuto.ic.c2.yotsugi",
      "shuto.ic.c2.oogioohashi",
      "shuto.ic.c2.shinitabashi",
      "shuto.ic.c2.nakanochoujabashi",
    ]
  )

  /// C1 Inner Circular inner loop.
  public static let c1Inner = ShutoCircuitDefinition(
    circuitID: "shuto.circuit.c1-inner",
    displayNameJA: "都心環状線 内回り",
    memberRouteIDs: ["C1"],
    entranceDirectionJA: "内回り",
    anchorFacilityIDs: [
      "shuto.ic.c1.takaracho",
      "shuto.ic.c1.kandabashi",
      "shuto.ic.c1.kasumigaseki",
      "shuto.ic.c1.shiodome",
    ]
  )

  public static let bundled: [ShutoCircuitDefinition] = [
    .c2InnerWithBayshore,
    .c1Inner,
  ]
}

/// Raised for structurally invalid circuit requests (bad lap count,
/// entrance/exit outside the circuit's member routes or direction).
public enum ShutoCircuitError: Error, Equatable {
  case invalidLapCount
}

extension ShutoRoutePlanner {
  /// Deterministic-scenario entry point: builds a planner over a synthetic
  /// `test.*` network without the bundled-data completeness gate. Production
  /// code paths must keep using the validating `init(database:)`.
  public static func forSyntheticScenario(
    database: ShutoNetworkDatabase
  ) -> ShutoRoutePlanner {
    ShutoRoutePlanner(unvalidatedDatabase: database)
  }

  private struct CircuitQueueValue: Comparable {
    let cost: Double
    let nodeID: Int64

    static func < (lhs: CircuitQueueValue, rhs: CircuitQueueValue) -> Bool {
      if lhs.cost != rhs.cost {
        return lhs.cost < rhs.cost
      }
      return lhs.nodeID < rhs.nodeID
    }
  }

  /// Direction-valid entrances for a circuit, nearest-first from an origin.
  public func circuitEntranceCandidates(
    for circuit: ShutoCircuitDefinition,
    origin: ShutoCoordinate? = nil
  ) -> [ShutoNetworkDatabase.Facility] {
    let eligible = database.directionalFacilities.filter {
      $0.canEnter
        && circuit.memberRouteIDs.contains($0.routeID)
        && $0.entranceDirections.contains(circuit.entranceDirectionJA)
    }
    guard let origin else {
      return eligible.sorted { $0.facilityID < $1.facilityID }
    }
    return eligible.sorted {
      let first = Self.distance(origin, $0.coordinate)
      let second = Self.distance(origin, $1.coordinate)
      if first != second { return first < second }
      return $0.facilityID < $1.facilityID
    }
  }

  /// Direction-valid exits for a circuit, ranked by forward travel distance
  /// after the entrance — the first candidate ends the circuit soonest after
  /// where it began. Geodesic nearness would be wrong here: an exit a few
  /// hundred meters behind the entrance is almost a full lap away.
  public func circuitExitCandidates(
    for circuit: ShutoCircuitDefinition,
    afterEntering entryFacilityID: String
  ) throws -> [ShutoNetworkDatabase.Facility] {
    guard let entryFacility = facilitiesByID[entryFacilityID],
      entryFacility.canEnter,
      circuit.memberRouteIDs.contains(entryFacility.routeID),
      entryFacility.entranceDirections
        .contains(circuit.entranceDirectionJA)
    else {
      throw ShutoNetworkError.facilityUnavailable
    }
    let isMember: (ShutoNetworkDatabase.Edge) -> Bool = { edge in
      edge.routeMemberships.contains {
        circuit.memberRouteIDs.contains($0.routeID)
      }
    }
    let cost: (ShutoNetworkDatabase.Edge) -> Double = { edge in
      edge.lengthMeters * (isMember(edge) ? 1 : 25)
    }
    var viability: [Int64: Bool] = [:]
    guard
      let approach = circuitApproach(
        entryFacility: entryFacility,
        isMember: isMember,
        cost: cost,
        viability: &viability
      )
    else {
      throw ShutoNetworkError.routeUnavailable
    }
    let forward = forwardDistances(from: approach.target, cost: cost)
    let ranked: [(ShutoNetworkDatabase.Facility, Double)] =
      database.directionalFacilities.compactMap { facility in
        guard facility.canExit,
          circuit.memberRouteIDs.contains(facility.routeID),
          facility.exitDirections.contains(circuit.entranceDirectionJA)
        else { return nil }
        let tail = facility.exitEdgeCandidates.compactMap {
          candidate -> Double? in
          guard let edge = edgesByID[candidate.edgeID],
            let reach = forward[edge.fromNodeID]
          else { return nil }
          return reach + candidate.distanceMeters
        }.min()
        return tail.map { (facility, $0) }
      }
    return
      ranked
      .sorted {
        if $0.1 != $1.1 { return $0.1 < $1.1 }
        return $0.0.facilityID < $1.0.facilityID
      }
      .map(\.0)
  }

  /// Plans a whole-circuit route: entrance approach, `laps` complete loops
  /// (each lap is a distinct ordered occurrence sequence), then the exit.
  public func planCircuit(
    circuit: ShutoCircuitDefinition,
    entryFacilityID: String,
    exitFacilityID: String,
    laps: Int,
    preference: ShutoRoutePreference = .recommended
  ) throws -> ShutoPlannedRoute {
    guard (1...9).contains(laps) else {
      throw ShutoCircuitError.invalidLapCount
    }
    guard let entryFacility = facilitiesByID[entryFacilityID],
      entryFacility.canEnter,
      circuit.memberRouteIDs.contains(entryFacility.routeID),
      entryFacility.entranceDirections
        .contains(circuit.entranceDirectionJA)
    else {
      throw ShutoNetworkError.facilityUnavailable
    }
    guard let exitFacility = facilitiesByID[exitFacilityID],
      exitFacility.canExit,
      circuit.memberRouteIDs.contains(exitFacility.routeID),
      exitFacility.exitDirections.contains(circuit.entranceDirectionJA)
    else {
      throw ShutoNetworkError.facilityUnavailable
    }

    let isMember: (ShutoNetworkDatabase.Edge) -> Bool = { edge in
      edge.routeMemberships.contains {
        circuit.memberRouteIDs.contains($0.routeID)
      }
    }
    let cost: (ShutoNetworkDatabase.Edge) -> Double = { edge in
      edge.lengthMeters * (isMember(edge) ? 1 : 25)
    }
    var viability: [Int64: Bool] = [:]

    // 1. Entrance approach: ramp candidates onto the circuit carriageway.
    guard
      let approach = circuitApproach(
        entryFacility: entryFacility,
        isMember: isMember,
        cost: cost,
        viability: &viability
      )
    else {
      throw ShutoNetworkError.routeUnavailable
    }
    let landing = approach.target

    // 2. Anchor node sets on the circuit carriageway.
    var anchorSets: [Set<Int64>] = []
    for anchorID in circuit.anchorFacilityIDs {
      guard let anchor = facilitiesByID[anchorID] else {
        throw ShutoNetworkError.facilityUnavailable
      }
      var radius = 400.0
      var nodes: Set<Int64> = []
      while nodes.isEmpty && radius <= 1_600 {
        nodes = circuitNodes(
          near: anchor.coordinate,
          radius: radius,
          isMember: isMember,
          viability: &viability
        )
        radius *= 2
      }
      guard !nodes.isEmpty else {
        throw ShutoNetworkError.routeUnavailable
      }
      anchorSets.append(nodes)
    }

    // 3. Discover anchor travel order by directed forward distance from the
    //    landing node. On a one-way loop, forward distance is travel order.
    let forward = forwardDistances(from: landing, cost: cost)
    var orderedAnchors:
      [(distance: Double, nodes: Set<Int64>)] = []
    for nodes in anchorSets {
      let best = nodes.compactMap { forward[$0] }.min()
      guard let best else {
        throw ShutoNetworkError.routeUnavailable
      }
      orderedAnchors.append((best, nodes))
    }
    orderedAnchors.sort { $0.distance < $1.distance }

    // 4. One loop: landing -> each anchor in travel order -> landing.
    var loopEdges: [ShutoNetworkDatabase.Edge] = []
    var currentNode = landing
    for anchor in orderedAnchors {
      guard
        let leg = circuitDijkstra(
          from: currentNode,
          cost: cost,
          isTarget: { anchor.nodes.contains($0) }
        )
      else {
        throw ShutoNetworkError.routeUnavailable
      }
      loopEdges.append(contentsOf: leg.edges)
      currentNode = leg.target
    }
    guard
      let closure = circuitDijkstra(
        from: currentNode,
        cost: cost,
        isTarget: { $0 == landing }
      )
    else {
      throw ShutoNetworkError.routeUnavailable
    }
    loopEdges.append(contentsOf: closure.edges)

    // 5. Exit tail from the landing node onto the exit ramp.
    let exitEdgesByNode = Dictionary(
      grouping: exitFacility.exitEdgeCandidates.compactMap {
        candidate in
        edgesByID[candidate.edgeID].map {
          (edge: $0, match: candidate.distanceMeters)
        }
      },
      by: { $0.edge.fromNodeID }
    )
    guard !exitEdgesByNode.isEmpty,
      let tail = circuitDijkstra(
        from: landing,
        cost: cost,
        isTarget: { exitEdgesByNode[$0] != nil }
      ),
      let exitChoice = exitEdgesByNode[tail.target]?
        .min(by: { $0.match + cost($0.edge) < $1.match + cost($1.edge) })
    else {
      throw ShutoNetworkError.routeUnavailable
    }
    var tailEdges = tail.edges
    if tailEdges.last?.edgeID != exitChoice.edge.edgeID {
      tailEdges.append(exitChoice.edge)
    }

    // 6. Assemble: approach + laps x loop + tail, distinct occurrences per lap.
    var routeEdges = approach.edges
    for _ in 0..<laps {
      routeEdges.append(contentsOf: loopEdges)
    }
    routeEdges.append(contentsOf: tailEdges)
    // Laps legitimately repeat edge IDs, but never the same edge twice in a
    // row — adjacent duplicates would be a stitching fault.
    routeEdges = routeEdges.reduce(into: []) { result, edge in
      if result.last?.edgeID != edge.edgeID {
        result.append(edge)
      }
    }

    return assemblePlannedRoute(
      routeEdges: routeEdges,
      planID:
        "\(circuit.circuitID).\(entryFacility.facilityID)."
        + "\(exitFacility.facilityID).x\(laps)."
        + preference.rawValue.lowercased(),
      entryFacility: entryFacility,
      exitFacility: exitFacility,
      preference: preference
    )
  }

  // MARK: - Directed search helpers

  /// Ramp candidates onto the circuit carriageway: the first viable node
  /// with an outgoing member mainline edge is the landing point.
  private func circuitApproach(
    entryFacility: ShutoNetworkDatabase.Facility,
    isMember: (ShutoNetworkDatabase.Edge) -> Bool,
    cost: (ShutoNetworkDatabase.Edge) -> Double,
    viability: inout [Int64: Bool]
  ) -> (edges: [ShutoNetworkDatabase.Edge], target: Int64)? {
    let seeds = entryFacility.entryEdgeCandidates.compactMap {
      candidate in
      edgesByID[candidate.edgeID].map {
        (edge: $0, cost: candidate.distanceMeters + cost($0))
      }
    }
    guard !seeds.isEmpty else { return nil }
    return circuitDijkstra(
      seeds: seeds,
      cost: cost,
      isTarget: { [self] node in
        outgoingEdges[node, default: []].contains {
          isMember($0) && $0.kind == "MAINLINE"
        } && isViable(node, cache: &viability)
      }
    )
  }

  private func circuitDijkstra(
    from node: Int64,
    cost: (ShutoNetworkDatabase.Edge) -> Double,
    isTarget: (Int64) -> Bool
  ) -> (edges: [ShutoNetworkDatabase.Edge], target: Int64)? {
    circuitDijkstra(seeds: nil, start: node, cost: cost, isTarget: isTarget)
  }

  private func circuitDijkstra(
    seeds: [(edge: ShutoNetworkDatabase.Edge, cost: Double)],
    cost: (ShutoNetworkDatabase.Edge) -> Double,
    isTarget: (Int64) -> Bool
  ) -> (edges: [ShutoNetworkDatabase.Edge], target: Int64)? {
    circuitDijkstra(seeds: seeds, start: nil, cost: cost, isTarget: isTarget)
  }

  /// Dijkstra that stops at the first settled node satisfying `isTarget`.
  /// Either `seeds` (initial edges with entry costs) or `start` must be given.
  private func circuitDijkstra(
    seeds: [(edge: ShutoNetworkDatabase.Edge, cost: Double)]?,
    start: Int64?,
    cost: (ShutoNetworkDatabase.Edge) -> Double,
    isTarget: (Int64) -> Bool
  ) -> (edges: [ShutoNetworkDatabase.Edge], target: Int64)? {
    var distances: [Int64: Double] = [:]
    var previous: [Int64: ShutoNetworkDatabase.Edge] = [:]
    var seedEdgeByNode: [Int64: ShutoNetworkDatabase.Edge] = [:]
    var queue = MinHeap<CircuitQueueValue>()
    if let start {
      distances[start] = 0
      queue.insert(CircuitQueueValue(cost: 0, nodeID: start))
    }
    for seed in seeds ?? [] {
      if seed.cost < distances[seed.edge.toNodeID, default: .infinity] {
        distances[seed.edge.toNodeID] = seed.cost
        seedEdgeByNode[seed.edge.toNodeID] = seed.edge
        queue.insert(
          CircuitQueueValue(cost: seed.cost, nodeID: seed.edge.toNodeID)
        )
      }
    }
    while let current = queue.removeMinimum() {
      guard current.cost == distances[current.nodeID] else { continue }
      let isStartNode = start != nil && current.nodeID == start
      if !isStartNode && isTarget(current.nodeID) {
        var reversed: [ShutoNetworkDatabase.Edge] = []
        var nodeID = current.nodeID
        while let edge = previous[nodeID] {
          reversed.append(edge)
          nodeID = edge.fromNodeID
        }
        if let seedEdge = seedEdgeByNode[nodeID] {
          reversed.append(seedEdge)
        }
        return (reversed.reversed(), current.nodeID)
      }
      for edge in outgoingEdges[current.nodeID, default: []] {
        let candidate = current.cost + cost(edge)
        if candidate >= distances[edge.toNodeID, default: .infinity] {
          continue
        }
        distances[edge.toNodeID] = candidate
        previous[edge.toNodeID] = edge
        queue.insert(
          CircuitQueueValue(cost: candidate, nodeID: edge.toNodeID)
        )
      }
    }
    return nil
  }

  /// Full relaxation from one node; used to discover anchor travel order.
  private func forwardDistances(
    from node: Int64,
    cost: (ShutoNetworkDatabase.Edge) -> Double
  ) -> [Int64: Double] {
    var distances: [Int64: Double] = [node: 0]
    var queue = MinHeap<CircuitQueueValue>()
    queue.insert(CircuitQueueValue(cost: 0, nodeID: node))
    while let current = queue.removeMinimum() {
      guard current.cost == distances[current.nodeID] else { continue }
      for edge in outgoingEdges[current.nodeID, default: []] {
        let candidate = current.cost + cost(edge)
        if candidate >= distances[edge.toNodeID, default: .infinity] {
          continue
        }
        distances[edge.toNodeID] = candidate
        queue.insert(
          CircuitQueueValue(cost: candidate, nodeID: edge.toNodeID)
        )
      }
    }
    return distances
  }

  /// Nodes near a coordinate that carry a member mainline edge and keep the
  /// graph alive ahead (filters dead-end slivers and exit-ramp stubs).
  private func circuitNodes(
    near coordinate: ShutoCoordinate,
    radius: Double,
    isMember: (ShutoNetworkDatabase.Edge) -> Bool,
    viability: inout [Int64: Bool]
  ) -> Set<Int64> {
    var nodes: Set<Int64> = []
    for edge in database.edges {
      guard isMember(edge), edge.kind == "MAINLINE",
        let node = nodesByID[edge.fromNodeID]
      else { continue }
      guard
        Self.distance(coordinate, node.coordinate) < radius,
        isViable(edge.fromNodeID, cache: &viability)
      else { continue }
      nodes.insert(edge.fromNodeID)
    }
    return nodes
  }

  /// A node is viable when at least `minimumMeters` of directed graph
  /// continues ahead of it.
  private func isViable(
    _ node: Int64,
    minimumMeters: Double = 2_000,
    cache: inout [Int64: Bool]
  ) -> Bool {
    if let cached = cache[node] { return cached }
    var seen: Set<Int64> = [node]
    var frontier: [(Int64, Double)] = [(node, 0)]
    var index = 0
    var viable = false
    while index < frontier.count {
      let (current, travelled) = frontier[index]
      index += 1
      if travelled >= minimumMeters {
        viable = true
        break
      }
      for edge in outgoingEdges[current, default: []] {
        if seen.insert(edge.toNodeID).inserted {
          frontier.append(
            (edge.toNodeID, travelled + edge.lengthMeters)
          )
        }
      }
    }
    cache[node] = viable
    return viable
  }
}
