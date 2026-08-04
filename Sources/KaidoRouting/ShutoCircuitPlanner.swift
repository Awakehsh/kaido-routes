import Foundation
import KaidoDomain

/// A drivable route experience over the whole-network snapshot. Two kinds:
///
/// - `loop`: a closed cycle over member carriageways. Anchors are an
///   unordered set — the planner discovers travel order from directed forward
///   distance, so one definition serves any compatible entrance, and laps
///   repeat the cycle as distinct ordered occurrences.
/// - `tour`: an open, ordered pass through the anchors — a reviewed course
///   (a PA-terminated run or a multi-route grand tour) driven exactly once.
///
/// The driver chooses the experience; entrances and exits are derived from
/// the origin, the directed graph, and the dated tariff rule — never designed
/// by hand outside the custom editor.
public struct ShutoCircuitDefinition: Equatable, Identifiable, Sendable {
  public enum Kind: String, Equatable, Sendable {
    case loop = "LOOP"
    case tour = "TOUR"
  }

  /// Anchors pin the course to the snapshot by identity, not coordinate
  /// literals: a directional facility or a junction from the same snapshot.
  public enum Anchor: Equatable, Sendable {
    case facility(String)
    case junction(String)
  }

  public var id: String { circuitID }

  public let circuitID: String
  public let displayNameJA: String
  public let kind: Kind
  public let memberRouteIDs: Set<String>
  /// Travel-direction label per member route (`内回り`, `東行き`, `下り`, …).
  /// A facility qualifies as entrance only when its own directions contain
  /// the label mapped for its route; unmapped routes offer none.
  public let entranceDirectionsByRouteID: [String: String]
  /// Exit-side direction labels; `nil` reuses the entrance map (loops), while
  /// tours whose course ends on a specific route override it so mid-course
  /// exits never pollute the recommendation.
  public let exitDirectionsByRouteID: [String: String]?
  /// Unordered for `.loop`, ordered course for `.tour`.
  public let anchors: [Anchor]
  public let paStopNamesJA: [String]
  public let landmarkNamesJA: [String]

  public init(
    circuitID: String,
    displayNameJA: String,
    kind: Kind,
    memberRouteIDs: Set<String>,
    entranceDirectionsByRouteID: [String: String],
    exitDirectionsByRouteID: [String: String]? = nil,
    anchors: [Anchor],
    paStopNamesJA: [String] = [],
    landmarkNamesJA: [String] = []
  ) {
    self.circuitID = circuitID
    self.displayNameJA = displayNameJA
    self.kind = kind
    self.memberRouteIDs = memberRouteIDs
    self.entranceDirectionsByRouteID = entranceDirectionsByRouteID
    self.exitDirectionsByRouteID = exitDirectionsByRouteID
    self.anchors = anchors
    self.paStopNamesJA = paStopNamesJA
    self.landmarkNamesJA = landmarkNamesJA
  }

  /// C2 Central Circular inner loop, closed between Oi JCT and Kasai JCT by
  /// the Bayshore Route. C2 alone is not a closed ring.
  public static let c2InnerWithBayshore = ShutoCircuitDefinition(
    circuitID: "shuto.circuit.c2-inner-bayshore",
    displayNameJA: "中央環状線 内回り＋湾岸線",
    kind: .loop,
    memberRouteIDs: ["C2", "B"],
    entranceDirectionsByRouteID: ["C2": "内回り"],
    anchors: [
      .facility("shuto.ic.c2.gotanda"),
      .facility("shuto.ic.c2.seishincho"),
      .facility("shuto.ic.c2.yotsugi"),
      .facility("shuto.ic.c2.oogioohashi"),
      .facility("shuto.ic.c2.shinitabashi"),
      .facility("shuto.ic.c2.nakanochoujabashi"),
    ],
    paStopNamesJA: ["大井PA"],
    landmarkNamesJA: ["山手トンネル", "東京港トンネル"]
  )

  /// C1 Inner Circular inner loop.
  public static let c1Inner = ShutoCircuitDefinition(
    circuitID: "shuto.circuit.c1-inner",
    displayNameJA: "都心環状線 内回り",
    kind: .loop,
    memberRouteIDs: ["C1"],
    entranceDirectionsByRouteID: ["C1": "内回り"],
    anchors: [
      .facility("shuto.ic.c1.takaracho"),
      .facility("shuto.ic.c1.kandabashi"),
      .facility("shuto.ic.c1.kasumigaseki"),
      .facility("shuto.ic.c1.shiodome"),
    ],
    landmarkNamesJA: ["東京タワー", "銀座", "皇居"]
  )

  /// Bayshore westbound run ending at Daikoku PA: Tokyo waterfront onto the
  /// Bayshore Route, across the Tsurumi Tsubasa Bridge, off at Daikoku Futo
  /// beside the PA.
  public static let wanganDaikokuRun = ShutoCircuitDefinition(
    circuitID: "shuto.circuit.wangan-daikoku-run",
    displayNameJA: "湾岸線 大黒PAラン",
    kind: .tour,
    memberRouteIDs: ["B"],
    entranceDirectionsByRouteID: ["B": "西行き"],
    anchors: [
      .junction("shuto.jct.jct_tokai"),
      .facility("shuto.ic.b.daikokufutou"),
    ],
    paStopNamesJA: ["大黒PA"],
    landmarkNamesJA: ["東京港トンネル", "羽田空港", "鶴見つばさ橋"]
  )

  /// Yokohama-side loop around Daikoku, in the carriageway direction the
  /// snapshot's junction movements support: Bayshore westbound into Daikoku,
  /// the Daikoku Line up to Namamugi, the Yokohane Line up to Daishi, and
  /// the Kawasaki Line back down to the Bayshore at Kawasaki-Ukishima.
  public static let daikokuYokohamaLoop = ShutoCircuitDefinition(
    circuitID: "shuto.circuit.daikoku-yokohama-loop",
    displayNameJA: "大黒周回（湾岸・大黒・横羽・川崎）",
    kind: .loop,
    memberRouteIDs: ["B", "K1", "K5", "K6"],
    entranceDirectionsByRouteID: [
      "B": "西行き",
      "K1": "上り",
    ],
    anchors: [
      .facility("shuto.ic.k5.daikokufutou"),
      .facility("shuto.ic.k1.asada"),
      .facility("shuto.ic.k6.tonomachi"),
    ],
    paStopNamesJA: ["大黒PA"],
    landmarkNamesJA: ["鶴見つばさ橋", "川崎臨海部"]
  )

  /// The scenic grand tour the snapshot's junction movements support: Harumi
  /// onto the Bayshore westbound, the Haneda Line down past the airport, the
  /// Yokohane Line through Minato Mirai, the Kariba Line to Honmoku, and the
  /// Bayshore over the Yokohama Bay Bridge to finish beside Daikoku PA.
  public static let scenicGrandTour = ShutoCircuitDefinition(
    circuitID: "shuto.circuit.scenic-grand-tour",
    displayNameJA: "横浜絶景ツアー（羽田・みなとみらい・ベイブリッジ）",
    kind: .tour,
    // K5 is a course connector, not an entrance/exit surface: the through
    // carriageway inside the Daikoku interchange carries the K5 relation.
    memberRouteIDs: ["10", "B", "1_HANEDA", "K1", "K3", "K5"],
    entranceDirectionsByRouteID: [
      "10": "下り",
      "B": "西行き",
    ],
    exitDirectionsByRouteID: ["B": "東行き"],
    anchors: [
      .facility("shuto.ic.b.ooi"),
      .facility("shuto.ic.k1.koyasu"),
      .facility("shuto.ic.k1.minatomirai"),
      .facility("shuto.ic.k3.shinyamashita"),
    ],
    paStopNamesJA: ["大黒PA"],
    landmarkNamesJA: [
      "羽田空港",
      "みなとみらい",
      "横浜ベイブリッジ",
      "大黒PA",
    ]
  )

  public static let bundled: [ShutoCircuitDefinition] = [
    .c1Inner,
    .c2InnerWithBayshore,
    .wanganDaikokuRun,
    .daikokuYokohamaLoop,
    .scenicGrandTour,
  ]
}

/// Raised for structurally invalid circuit requests (bad lap count,
/// entrance/exit outside the circuit's member routes or direction), or for
/// an origin whose nearest eligible entrance sits beyond the outer surface
/// access radius — the product fails closed instead of navigating tens of
/// kilometers of ordinary roads.
public enum ShutoCircuitError: Error, Equatable {
  case invalidLapCount
  case entranceOutOfRange(nearestDistanceMeters: Double)
}

/// Surface-access tiers for reaching an entrance from the origin: Tokyo's
/// inner wards space Shuto entrances every 1–3 km, so 8 km (~15–20 min of
/// city driving) covers ordinary urban origins, 16 km is offered with an
/// explicit far label, and anything beyond fails closed — a distant origin
/// belongs to a radial approach, not a long surface leg.
public enum ShutoEntranceAccessTier: Equatable, Sendable {
  case nearby
  case far
  case outOfRange

  public static let nearbyRadiusMeters = 8_000.0
  public static let outerRadiusMeters = 16_000.0

  public static func classify(
    distanceMeters: Double
  ) -> ShutoEntranceAccessTier {
    if distanceMeters <= nearbyRadiusMeters { return .nearby }
    if distanceMeters <= outerRadiusMeters { return .far }
    return .outOfRange
  }
}

/// One derived entrance/exit pairing for an experience: the recommendation
/// the home card shows before any manual adjustment.
public struct ShutoCircuitPairing: Equatable, Sendable {
  public let entrance: ShutoNetworkDatabase.Facility
  public let exit: ShutoNetworkDatabase.Facility
  public let tariffBand: ShutoTariffBand?
  /// Geodesic origin-to-entrance distance when an origin was provided.
  public let entranceDistanceMeters: Double?
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

  /// Member-cost budget under which every anchor must stay reachable for an
  /// entrance to qualify. The farthest anchor of the longest bundled loop
  /// sits ~56 km ahead of its worst legitimate entrance, while one kilometer
  /// of penalized off-member detour already costs 25 km-equivalent — so this
  /// bound admits every on-course entrance and rejects detour-dependent ones.
  private static let entranceReachabilityBudget = 70_000.0

  /// Tighter budget for closing a lap from the farthest anchor back to the
  /// entrance's landing node. That closing arc is bounded by the anchor
  /// spacing (~15 km on the bundled loops), while a one-way feeder entrance
  /// can only close through multi-kilometer penalized off-member detours.
  private static let loopClosureBudget = 30_000.0

  /// How many nearest entrance candidates get the (Dijkstra-priced)
  /// reachability check; the pairing UI never needs more alternatives.
  private static let entranceCandidateLimit = 16

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

  private func isEligibleEntrance(
    _ facility: ShutoNetworkDatabase.Facility,
    for circuit: ShutoCircuitDefinition
  ) -> Bool {
    facility.canEnter
      && circuit.memberRouteIDs.contains(facility.routeID)
      && circuit.entranceDirectionsByRouteID[facility.routeID].map {
        facility.entranceDirections.contains($0)
      } ?? false
  }

  private func isEligibleExit(
    _ facility: ShutoNetworkDatabase.Facility,
    for circuit: ShutoCircuitDefinition
  ) -> Bool {
    let directions =
      circuit.exitDirectionsByRouteID
      ?? circuit.entranceDirectionsByRouteID
    return facility.canExit
      && circuit.memberRouteIDs.contains(facility.routeID)
      && directions[facility.routeID].map {
        facility.exitDirections.contains($0)
      } ?? false
  }

  /// Direction-valid entrances that can actually reach every anchor of the
  /// experience, nearest-first from an origin. The reachability gate runs on
  /// the nearest `entranceCandidateLimit` candidates only.
  public func circuitEntranceCandidates(
    for circuit: ShutoCircuitDefinition,
    origin: ShutoCoordinate? = nil
  ) -> [ShutoNetworkDatabase.Facility] {
    let eligible = database.directionalFacilities.filter {
      isEligibleEntrance($0, for: circuit)
    }
    let ranked: [ShutoNetworkDatabase.Facility]
    if let origin {
      ranked = eligible.sorted {
        let first = Self.distance(origin, $0.coordinate)
        let second = Self.distance(origin, $1.coordinate)
        if first != second { return first < second }
        return $0.facilityID < $1.facilityID
      }
    } else {
      ranked = eligible.sorted { $0.facilityID < $1.facilityID }
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
      let anchorSets = try? anchorNodeSets(
        for: circuit,
        isMember: isMember,
        viability: &viability
      )
    else { return [] }
    return ranked.prefix(Self.entranceCandidateLimit).filter { entrance in
      guard
        let approach = circuitApproach(
          entryFacility: entrance,
          isMember: isMember,
          cost: cost,
          viability: &viability
        )
      else { return false }
      let forward = forwardDistances(from: approach.target, cost: cost)
      var farthestAnchorNode: (node: Int64, distance: Double)?
      for nodes in anchorSets {
        let best = nodes.compactMap { node in
          forward[node].map { (node, $0) }
        }.min { $0.1 < $1.1 }
        guard let best, best.1 <= Self.entranceReachabilityBudget else {
          return false
        }
        if best.1 > (farthestAnchorNode?.distance ?? -1) {
          farthestAnchorNode = best
        }
      }
      guard let farthestAnchorNode else { return false }
      // A loop entrance must also be returnable-to: an entrance that merely
      // feeds the loop's carriageway one-way (then dead-ends off the cycle)
      // reaches every anchor but can never close a lap.
      if circuit.kind == .loop {
        let back = forwardDistances(
          from: farthestAnchorNode.node,
          cost: cost
        )
        guard
          let closing = back[approach.target],
          closing <= Self.loopClosureBudget
        else { return false }
      }
      return true
    }
  }

  /// Direction-valid exits ranked by forward travel distance after the
  /// experience body completes — after the loop closes, or after the tour's
  /// last anchor. Geodesic nearness would be wrong here: an exit a few
  /// hundred meters behind the course is almost a full lap away.
  public func circuitExitCandidates(
    for circuit: ShutoCircuitDefinition,
    afterEntering entryFacilityID: String
  ) throws -> [ShutoNetworkDatabase.Facility] {
    guard let entryFacility = facilitiesByID[entryFacilityID],
      isEligibleEntrance(entryFacility, for: circuit)
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
    let traversal = try circuitTraversal(
      circuit: circuit,
      entryFacility: entryFacility,
      isMember: isMember,
      cost: cost,
      viability: &viability
    )
    let forward = forwardDistances(from: traversal.finalNode, cost: cost)
    let ranked: [(ShutoNetworkDatabase.Facility, Double)] =
      database.directionalFacilities.compactMap { facility in
        guard isEligibleExit(facility, for: circuit) else { return nil }
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

  /// The derived pairing an experience card shows: nearest reachable
  /// entrance, and — for loops — the exit whose pairing lands in the lowest
  /// tariff band, tie-broken by shortest forward travel. Tours keep their
  /// forward-ranked course exit.
  public func recommendedCircuitPairing(
    for circuit: ShutoCircuitDefinition,
    origin: ShutoCoordinate?,
    evidence: ShutoTariffEvidence?
  ) throws -> ShutoCircuitPairing {
    guard
      let entrance = circuitEntranceCandidates(
        for: circuit,
        origin: origin
      ).first
    else {
      throw ShutoNetworkError.facilityUnavailable
    }
    return try recommendedCircuitPairing(
      for: circuit,
      entranceFacilityID: entrance.facilityID,
      origin: origin,
      evidence: evidence
    )
  }

  /// The derived pairing for one already-chosen entrance — the alternatives
  /// path when the driver corrects the location-derived recommendation.
  public func recommendedCircuitPairing(
    for circuit: ShutoCircuitDefinition,
    entranceFacilityID: String,
    origin: ShutoCoordinate? = nil,
    evidence: ShutoTariffEvidence?
  ) throws -> ShutoCircuitPairing {
    guard let entrance = facilitiesByID[entranceFacilityID],
      isEligibleEntrance(entrance, for: circuit)
    else {
      throw ShutoNetworkError.facilityUnavailable
    }
    let entranceDistance = origin.map {
      Self.distance($0, entrance.coordinate)
    }
    if let entranceDistance,
      ShutoEntranceAccessTier.classify(
        distanceMeters: entranceDistance
      ) == .outOfRange
    {
      throw ShutoCircuitError.entranceOutOfRange(
        nearestDistanceMeters: entranceDistance
      )
    }
    let exits = try circuitExitCandidates(
      for: circuit,
      afterEntering: entrance.facilityID
    )
    guard let leading = exits.first else {
      throw ShutoNetworkError.routeUnavailable
    }
    guard let evidence, circuit.kind == .loop else {
      let band = evidence.flatMap {
        try? tariffBand(
          entryFacilityID: entrance.facilityID,
          exitFacilityID: leading.facilityID,
          evidence: $0
        )
      }
      return ShutoCircuitPairing(
        entrance: entrance,
        exit: leading,
        tariffBand: band,
        entranceDistanceMeters: entranceDistance
      )
    }
    var best: (ShutoNetworkDatabase.Facility, ShutoTariffBand)?
    for exit in exits.prefix(8) {
      guard
        let band = try? tariffBand(
          entryFacilityID: entrance.facilityID,
          exitFacilityID: exit.facilityID,
          evidence: evidence
        )
      else { continue }
      if best == nil || band.quotedYen < best!.1.quotedYen {
        best = (exit, band)
      }
      if band.quotedYen == evidence.minimumYen { break }
    }
    guard let best else {
      return ShutoCircuitPairing(
        entrance: entrance,
        exit: leading,
        tariffBand: nil,
        entranceDistanceMeters: entranceDistance
      )
    }
    return ShutoCircuitPairing(
      entrance: entrance,
      exit: best.0,
      tariffBand: best.1,
      entranceDistanceMeters: entranceDistance
    )
  }

  /// Plans a whole-experience route: entrance approach, the experience body
  /// (`laps` complete loops as distinct ordered occurrences, or the tour's
  /// single ordered pass), then the exit.
  public func planCircuit(
    circuit: ShutoCircuitDefinition,
    entryFacilityID: String,
    exitFacilityID: String,
    laps: Int,
    preference: ShutoRoutePreference = .recommended
  ) throws -> ShutoPlannedRoute {
    switch circuit.kind {
    case .loop:
      guard (1...9).contains(laps) else {
        throw ShutoCircuitError.invalidLapCount
      }
    case .tour:
      guard laps == 1 else {
        throw ShutoCircuitError.invalidLapCount
      }
    }
    guard let entryFacility = facilitiesByID[entryFacilityID],
      isEligibleEntrance(entryFacility, for: circuit)
    else {
      throw ShutoNetworkError.facilityUnavailable
    }
    guard let exitFacility = facilitiesByID[exitFacilityID],
      isEligibleExit(exitFacility, for: circuit)
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
    let traversal = try circuitTraversal(
      circuit: circuit,
      entryFacility: entryFacility,
      isMember: isMember,
      cost: cost,
      viability: &viability
    )

    // Exit tail from the body's final node onto the exit ramp.
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
        from: traversal.finalNode,
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

    // Assemble: approach + body + tail, distinct occurrences per lap.
    var routeEdges = traversal.approachEdges
    switch circuit.kind {
    case .loop:
      for _ in 0..<laps {
        routeEdges.append(contentsOf: traversal.bodyEdges)
      }
    case .tour:
      routeEdges.append(contentsOf: traversal.bodyEdges)
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

  // MARK: - Shared traversal

  private struct CircuitTraversal {
    let approachEdges: [ShutoNetworkDatabase.Edge]
    let bodyEdges: [ShutoNetworkDatabase.Edge]
    /// Where the exit tail begins: the landing node for a closed loop, the
    /// last anchor's settled node for a tour.
    let finalNode: Int64
  }

  /// Entrance approach plus the experience body: one closed loop through the
  /// anchors (order discovered from forward distance), or the tour's ordered
  /// anchor pass.
  private func circuitTraversal(
    circuit: ShutoCircuitDefinition,
    entryFacility: ShutoNetworkDatabase.Facility,
    isMember: (ShutoNetworkDatabase.Edge) -> Bool,
    cost: (ShutoNetworkDatabase.Edge) -> Double,
    viability: inout [Int64: Bool]
  ) throws -> CircuitTraversal {
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
    let anchorSets = try anchorNodeSets(
      for: circuit,
      isMember: isMember,
      viability: &viability
    )

    let orderedSets: [Set<Int64>]
    switch circuit.kind {
    case .loop:
      // Discover anchor travel order by directed forward distance from the
      // landing node. On a one-way loop, forward distance is travel order.
      let forward = forwardDistances(from: landing, cost: cost)
      var ordered: [(distance: Double, nodes: Set<Int64>)] = []
      for nodes in anchorSets {
        let best = nodes.compactMap { forward[$0] }.min()
        guard let best else {
          throw ShutoNetworkError.routeUnavailable
        }
        ordered.append((best, nodes))
      }
      ordered.sort { $0.distance < $1.distance }
      orderedSets = ordered.map(\.nodes)
    case .tour:
      orderedSets = anchorSets
    }

    var bodyEdges: [ShutoNetworkDatabase.Edge] = []
    var currentNode = landing
    for nodes in orderedSets {
      guard
        let leg = circuitDijkstra(
          from: currentNode,
          cost: cost,
          isTarget: { nodes.contains($0) }
        )
      else {
        throw ShutoNetworkError.routeUnavailable
      }
      bodyEdges.append(contentsOf: leg.edges)
      currentNode = leg.target
    }
    switch circuit.kind {
    case .loop:
      guard
        let closure = circuitDijkstra(
          from: currentNode,
          cost: cost,
          isTarget: { $0 == landing }
        )
      else {
        throw ShutoNetworkError.routeUnavailable
      }
      bodyEdges.append(contentsOf: closure.edges)
      return CircuitTraversal(
        approachEdges: approach.edges,
        bodyEdges: bodyEdges,
        finalNode: landing
      )
    case .tour:
      return CircuitTraversal(
        approachEdges: approach.edges,
        bodyEdges: bodyEdges,
        finalNode: currentNode
      )
    }
  }

  /// Anchor node sets on the experience carriageways, resolved from the
  /// snapshot's own facilities and junctions with growing search radius.
  private func anchorNodeSets(
    for circuit: ShutoCircuitDefinition,
    isMember: (ShutoNetworkDatabase.Edge) -> Bool,
    viability: inout [Int64: Bool]
  ) throws -> [Set<Int64>] {
    var anchorSets: [Set<Int64>] = []
    for anchor in circuit.anchors {
      let coordinate: ShutoCoordinate
      let initialRadius: Double
      switch anchor {
      case .facility(let facilityID):
        guard let facility = facilitiesByID[facilityID] else {
          throw ShutoNetworkError.facilityUnavailable
        }
        coordinate = facility.coordinate
        // A facility sits beside adjacent parallel carriageways.
        initialRadius = 400
      case .junction(let junctionID):
        guard
          let junction = database.junctions.first(where: {
            $0.junctionID == junctionID
          }),
          let junctionCoordinate = junction.coordinate
        else {
          throw ShutoNetworkError.facilityUnavailable
        }
        coordinate = junctionCoordinate
        // A junction is a sprawling ramp complex: a narrow radius can catch
        // only one carriageway and force giant detours onto the legs.
        initialRadius = 800
      }
      var radius = initialRadius
      var nodes: Set<Int64> = []
      while nodes.isEmpty && radius <= 1_600 {
        nodes = circuitNodes(
          near: coordinate,
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
    return anchorSets
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

  /// Full relaxation from one node; used to discover anchor travel order,
  /// rank exits, and gate entrance reachability.
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
