import Foundation
import KaidoDomain

/// A drivable route experience over the whole-network snapshot. Two kinds:
///
/// - `loop`: a closed cycle over member carriageways. Anchors are an
///   unordered set — the planner discovers travel order from directed forward
///   distance, so one definition serves any compatible entrance, and laps
///   repeat the cycle as distinct ordered occurrences.
/// - `tour`: an open, ordered pass through the anchors — a versioned candidate
///   course (a PA-terminated run or a multi-route grand tour) driven exactly
///   once.
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
  public let localizedDisplayNames: [KaidoReleaseLocale: String]
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
  public let localizedLandmarkNames: [KaidoReleaseLocale: [String]]

  public init(
    circuitID: String,
    displayNameJA: String,
    localizedDisplayNames: [KaidoReleaseLocale: String] = [:],
    kind: Kind,
    memberRouteIDs: Set<String>,
    entranceDirectionsByRouteID: [String: String],
    exitDirectionsByRouteID: [String: String]? = nil,
    anchors: [Anchor],
    paStopNamesJA: [String] = [],
    landmarkNamesJA: [String] = [],
    localizedLandmarkNames: [KaidoReleaseLocale: [String]] = [:]
  ) {
    self.circuitID = circuitID
    self.displayNameJA = displayNameJA
    self.localizedDisplayNames = localizedDisplayNames
    self.kind = kind
    self.memberRouteIDs = memberRouteIDs
    self.entranceDirectionsByRouteID = entranceDirectionsByRouteID
    self.exitDirectionsByRouteID = exitDirectionsByRouteID
    self.anchors = anchors
    self.paStopNamesJA = paStopNamesJA
    self.landmarkNamesJA = landmarkNamesJA
    self.localizedLandmarkNames = localizedLandmarkNames
  }

  public func displayName(for locale: KaidoReleaseLocale) -> String {
    localizedDisplayNames[locale] ?? displayNameJA
  }

  public func landmarkNames(for locale: KaidoReleaseLocale) -> [String] {
    localizedLandmarkNames[locale] ?? landmarkNamesJA
  }

  /// C2 Central Circular inner loop, closed between Oi JCT and Kasai JCT by
  /// the Bayshore Route. C2 alone is not a closed ring.
  public static let c2InnerWithBayshore = ShutoCircuitDefinition(
    circuitID: "shuto.circuit.c2-inner-bayshore",
    displayNameJA: "中央環状線 内回り＋湾岸線",
    localizedDisplayNames: [
      .japanese: "中央環状線 内回り＋湾岸線",
      .simplifiedChinese: "中央环状线 内环＋湾岸线",
      .english: "C2 Inner + Bayshore Circuit",
    ],
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
    landmarkNamesJA: ["山手トンネル", "東京港トンネル"],
    localizedLandmarkNames: [
      .japanese: ["山手トンネル", "東京港トンネル"],
      .simplifiedChinese: ["山手隧道", "东京港隧道"],
      .english: ["Yamate Tunnel", "Tokyo Port Tunnel"],
    ]
  )

  /// C1 Inner Circular inner loop.
  public static let c1Inner = ShutoCircuitDefinition(
    circuitID: "shuto.circuit.c1-inner",
    displayNameJA: "都心環状線 内回り",
    localizedDisplayNames: [
      .japanese: "都心環状線 内回り",
      .simplifiedChinese: "都心环状线 内环",
      .english: "C1 Inner Circuit",
    ],
    kind: .loop,
    memberRouteIDs: ["C1"],
    entranceDirectionsByRouteID: ["C1": "内回り"],
    anchors: [
      .facility("shuto.ic.c1.takaracho"),
      .facility("shuto.ic.c1.kandabashi"),
      .facility("shuto.ic.c1.kasumigaseki"),
      .facility("shuto.ic.c1.shiodome"),
    ],
    landmarkNamesJA: ["東京タワー", "銀座", "皇居"],
    localizedLandmarkNames: [
      .japanese: ["東京タワー", "銀座", "皇居"],
      .simplifiedChinese: ["东京塔", "银座", "皇居"],
      .english: ["Tokyo Tower", "Ginza", "Imperial Palace"],
    ]
  )

  /// Bayshore westbound run ending at Daikoku PA: Tokyo waterfront onto the
  /// Bayshore Route, across the Tsurumi Tsubasa Bridge, off at Daikoku Futo
  /// beside the PA.
  public static let wanganDaikokuRun = ShutoCircuitDefinition(
    circuitID: "shuto.circuit.wangan-daikoku-run",
    displayNameJA: "湾岸線 大黒PAラン",
    localizedDisplayNames: [
      .japanese: "湾岸線 大黒PAラン",
      .simplifiedChinese: "湾岸线 大黑 PA 巡游",
      .english: "Bayshore to Daikoku PA",
    ],
    kind: .tour,
    memberRouteIDs: ["B"],
    entranceDirectionsByRouteID: ["B": "西行き"],
    anchors: [
      .junction("shuto.jct.jct_tokai"),
      .facility("shuto.ic.b.daikokufutou"),
    ],
    paStopNamesJA: ["大黒PA"],
    landmarkNamesJA: ["東京港トンネル", "羽田空港", "鶴見つばさ橋"],
    localizedLandmarkNames: [
      .japanese: ["東京港トンネル", "羽田空港", "鶴見つばさ橋"],
      .simplifiedChinese: ["东京港隧道", "羽田机场", "鹤见翼桥"],
      .english: ["Tokyo Port Tunnel", "Haneda Airport", "Tsurumi Tsubasa Bridge"],
    ]
  )

  /// Yokohama-side loop around Daikoku, in the carriageway direction the
  /// snapshot's junction movements support: Bayshore westbound into Daikoku,
  /// the Daikoku Line up to Namamugi, the Yokohane Line up to Daishi, and
  /// the Kawasaki Line back down to the Bayshore at Kawasaki-Ukishima.
  public static let daikokuYokohamaLoop = ShutoCircuitDefinition(
    circuitID: "shuto.circuit.daikoku-yokohama-loop",
    displayNameJA: "大黒周回（湾岸・大黒・横羽・川崎）",
    localizedDisplayNames: [
      .japanese: "大黒周回（湾岸・大黒・横羽・川崎）",
      .simplifiedChinese: "大黑环线（湾岸・大黑・横羽・川崎）",
      .english: "Daikoku Yokohama Circuit",
    ],
    kind: .loop,
    memberRouteIDs: ["B", "K1", "K5", "K6"],
    entranceDirectionsByRouteID: [
      "B": "西行き",
      "K1": "上り",
      "K5": "上り",
      "K6": "下り",
    ],
    // K1 exits stay unmapped: the snapshot's directed graph at Ishikawacho
    // and Namamugi is verified complete against upstream OSM (2026-08-10),
    // yet the cheapest legal drivable path Daikoku-Futo to Namamugi still
    // measures ~30 km where the operator fare search prices the pairing at
    // 660 yen (~15 km). Until the operator's fare-distance rule for that
    // cross-carriageway turnaround is reproduced, any K1 exit quote here
    // would be wrong, so only Bayshore/Kawasaki exits are offered.
    exitDirectionsByRouteID: [
      "B": "西行き",
      "K6": "下り",
    ],
    anchors: [
      .facility("shuto.ic.k1.asada"),
      .facility("shuto.ic.k6.tonomachi"),
      .facility("shuto.ic.b.higashiogishima"),
    ],
    paStopNamesJA: ["大黒PA"],
    landmarkNamesJA: ["鶴見つばさ橋", "川崎臨海部"],
    localizedLandmarkNames: [
      .japanese: ["鶴見つばさ橋", "川崎臨海部"],
      .simplifiedChinese: ["鹤见翼桥", "川崎临海区"],
      .english: ["Tsurumi Tsubasa Bridge", "Kawasaki Waterfront"],
    ]
  )

  /// The scenic grand tour the snapshot's junction movements support: Harumi
  /// onto the Bayshore westbound, the Haneda Line down past the airport, the
  /// Yokohane Line through Minato Mirai, the Kariba Line to Honmoku, and the
  /// Bayshore over the Yokohama Bay Bridge to finish beside Daikoku PA.
  public static let scenicGrandTour = ShutoCircuitDefinition(
    circuitID: "shuto.circuit.scenic-grand-tour",
    displayNameJA: "横浜絶景ツアー（羽田・みなとみらい・ベイブリッジ）",
    localizedDisplayNames: [
      .japanese: "横浜絶景ツアー（羽田・みなとみらい・ベイブリッジ）",
      .simplifiedChinese: "横滨景观巡游（羽田・港未来・海湾大桥）",
      .english: "Yokohama Scenic Tour",
    ],
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
    ],
    localizedLandmarkNames: [
      .japanese: ["羽田空港", "みなとみらい", "横浜ベイブリッジ", "大黒PA"],
      .simplifiedChinese: ["羽田机场", "港未来", "横滨海湾大桥", "大黑 PA"],
      .english: ["Haneda Airport", "Minato Mirai", "Yokohama Bay Bridge", "Daikoku PA"],
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

  /// Loops accept off-member entrances the reachability gates admit — the
  /// fare rule's shortest-path pricing makes a minimum-band excursion
  /// possible from almost any ramp, so a radial entrance legally joining
  /// the loop is a first-class start. An entrance on a member route still
  /// has to match the experience's carriageway direction: an opposite-loop
  /// ramp is a different experience, not an approach. Tours keep their
  /// reviewed maps everywhere because their course identity depends on
  /// them.
  private func isEligibleEntrance(
    _ facility: ShutoNetworkDatabase.Facility,
    for circuit: ShutoCircuitDefinition
  ) -> Bool {
    guard facility.canEnter else { return false }
    switch circuit.kind {
    case .loop:
      guard circuit.memberRouteIDs.contains(facility.routeID) else {
        return true
      }
      return circuit.entranceDirectionsByRouteID[facility.routeID].map {
        facility.entranceDirections.contains($0)
      } ?? false
    case .tour:
      return circuit.memberRouteIDs.contains(facility.routeID)
        && circuit.entranceDirectionsByRouteID[facility.routeID].map {
          facility.entranceDirections.contains($0)
        } ?? false
    }
  }

  private func isEligibleExit(
    _ facility: ShutoNetworkDatabase.Facility,
    for circuit: ShutoCircuitDefinition
  ) -> Bool {
    guard facility.canExit else { return false }
    let directions =
      circuit.exitDirectionsByRouteID
      ?? circuit.entranceDirectionsByRouteID
    switch circuit.kind {
    case .loop:
      guard circuit.memberRouteIDs.contains(facility.routeID) else {
        return true
      }
      return directions[facility.routeID].map {
        facility.exitDirections.contains($0)
      } ?? false
    case .tour:
      return circuit.memberRouteIDs.contains(facility.routeID)
        && directions[facility.routeID].map {
          facility.exitDirections.contains($0)
        } ?? false
    }
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
      let approaches = circuitApproaches(
        entryFacility: entrance,
        isMember: isMember,
        cost: cost,
        viability: &viability
      )
      return approaches.contains { approach in
        let forward = forwardDistances(
          from: approach.target,
          cost: cost
        )
        var anchorReaches: [(node: Int64, distance: Double)] = []
        var nearestAnchorNode: (node: Int64, distance: Double)?
        var farthestAnchorNode: (node: Int64, distance: Double)?
        for nodes in anchorSets {
          let best = nodes.compactMap { node in
            forward[node].map { (node, $0) }
          }.min { $0.1 < $1.1 }
          guard let best, best.1 <= Self.entranceReachabilityBudget
          else {
            return false
          }
          anchorReaches.append(best)
          if best.1 < (nearestAnchorNode?.distance ?? .infinity) {
            nearestAnchorNode = best
          }
          if best.1 > (farthestAnchorNode?.distance ?? -1) {
            farthestAnchorNode = best
          }
        }
        guard let nearestAnchorNode, let farthestAnchorNode else {
          return false
        }
        // The anchors form a reviewed cyclic sequence in the experience's
        // carriageway direction: from a correct landing, forward distances
        // must be non-decreasing around the rotated cycle. An entrance that
        // joins the OPPOSITE carriageway reaches every anchor too — in
        // reverse order — and is a different experience, not an approach.
        if circuit.kind == .loop, anchorReaches.count >= 3 {
          let count = anchorReaches.count
          var startIndex = 0
          for index in anchorReaches.indices
          where anchorReaches[index].distance
            < anchorReaches[startIndex].distance
          {
            startIndex = index
          }
          for offset in 1..<count {
            let previous =
              anchorReaches[(startIndex + offset - 1) % count].distance
            let next =
              anchorReaches[(startIndex + offset) % count].distance
            if next + 1_000 < previous {
              return false
            }
          }
        }
        // A loop entrance must feed an actual cycle: from the farthest
        // anchor the lap must close back to the first anchor within the
        // closing-arc budget. The landing itself may sit on a one-way
        // merge lane, so the cycle — not the landing — is what must be
        // revisitable.
        if circuit.kind == .loop {
          let back = forwardDistances(
            from: farthestAnchorNode.node,
            cost: cost
          )
          guard
            let closing = back[nearestAnchorNode.node],
            closing <= Self.loopClosureBudget
          else { return false }
        }
        return true
      }
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
    // Tariff-best exit for a loop: consider the soonest forward exits plus
    // every reachable exit near the entrance — the pairing that keeps the
    // shortest entry-exit path (and therefore the band) small usually sits
    // right beside the entrance, often far down the forward ranking. A
    // same-named exit is never recommended: community and operator practice
    // treats an identical entry/exit name as a pairing to avoid.
    var candidates: [ShutoNetworkDatabase.Facility] = []
    for exit in exits.prefix(8)
    where exit.nameJA != entrance.nameJA {
      candidates.append(exit)
    }
    for exit in exits
    where
      exit.nameJA != entrance.nameJA
      && Self.distance(entrance.coordinate, exit.coordinate) <= 4_500
      && !candidates.contains(where: {
        $0.facilityID == exit.facilityID
      })
    {
      candidates.append(exit)
    }
    var best: (
      facility: ShutoNetworkDatabase.Facility,
      band: ShutoTariffBand,
      rank: Int
    )?
    for (rank, exit) in candidates.enumerated() {
      guard
        let band = try? tariffBand(
          entryFacilityID: entrance.facilityID,
          exitFacilityID: exit.facilityID,
          evidence: evidence
        )
      else { continue }
      let isBetter =
        best == nil
        || band.quotedYen < best!.band.quotedYen
        || (band.quotedYen == best!.band.quotedYen
          && rank < best!.rank)
      if isBetter {
        best = (exit, band, rank)
      }
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
      exit: best.facility,
      tariffBand: best.band,
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

    // Assemble: approach + one-time entry + body + tail, with distinct
    // occurrences per lap.
    var routeEdges = traversal.approachEdges
    routeEdges.append(contentsOf: traversal.entryEdges)
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
    /// Driven exactly once before the first lap: empty for an entrance
    /// already on the cycle, the merge-lane-to-join stretch for a radial
    /// entrance whose landing the cycle can never revisit.
    let entryEdges: [ShutoNetworkDatabase.Edge]
    /// One complete lap for a loop (join-to-join), or the tour's ordered
    /// anchor pass.
    let bodyEdges: [ShutoNetworkDatabase.Edge]
    /// Where the exit tail begins: the cycle's join node for a loop, the
    /// last anchor's settled node for a tour.
    let finalNode: Int64
  }

  /// Entrance approach plus the experience body: one closed loop through the
  /// anchors' cyclic sequence, or the tour's ordered anchor pass. A ramp can
  /// geometrically match edges of several nearby carriageways, so a few
  /// cheapest landings are tried and the traversal with the shortest driven
  /// geometry wins — a wrong-carriageway landing only "recovers" through an
  /// extra half-loop and loses the comparison.
  private func circuitTraversal(
    circuit: ShutoCircuitDefinition,
    entryFacility: ShutoNetworkDatabase.Facility,
    isMember: (ShutoNetworkDatabase.Edge) -> Bool,
    cost: (ShutoNetworkDatabase.Edge) -> Double,
    viability: inout [Int64: Bool]
  ) throws -> CircuitTraversal {
    let approaches = circuitApproaches(
      entryFacility: entryFacility,
      isMember: isMember,
      cost: cost,
      viability: &viability
    )
    guard !approaches.isEmpty else {
      throw ShutoNetworkError.routeUnavailable
    }
    let anchorSets = try anchorNodeSets(
      for: circuit,
      isMember: isMember,
      viability: &viability
    )

    var best: CircuitTraversal?
    var bestMeters = Double.infinity
    for approach in approaches {
      guard
        let candidate = try? traversalBody(
          circuit: circuit,
          approach: approach,
          anchorSets: anchorSets,
          cost: cost
        )
      else { continue }
      let meters = (
        candidate.approachEdges + candidate.entryEdges
          + candidate.bodyEdges
      ).reduce(0) { $0 + $1.lengthMeters }
      if meters < bestMeters {
        bestMeters = meters
        best = candidate
      }
    }
    guard let best else {
      throw ShutoNetworkError.routeUnavailable
    }
    return best
  }

  private func traversalBody(
    circuit: ShutoCircuitDefinition,
    approach: (edges: [ShutoNetworkDatabase.Edge], target: Int64),
    anchorSets: [Set<Int64>],
    cost: (ShutoNetworkDatabase.Edge) -> Double
  ) throws -> CircuitTraversal {
    let landing = approach.target
    let orderedSets: [Set<Int64>]
    switch circuit.kind {
    case .loop:
      // The cyclic anchor sequence pins the carriageway direction; the
      // entrance only chooses where the cycle is joined, so rotate the
      // sequence to the nearest-forward anchor.
      let forward = forwardDistances(from: landing, cost: cost)
      var startIndex = 0
      var startDistance = Double.infinity
      for (index, nodes) in anchorSets.enumerated() {
        guard
          let best = nodes.compactMap({ forward[$0] }).min()
        else {
          throw ShutoNetworkError.routeUnavailable
        }
        if best < startDistance {
          startDistance = best
          startIndex = index
        }
      }
      orderedSets = (0..<anchorSets.count).map {
        anchorSets[(startIndex + $0) % anchorSets.count]
      }
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
      // Close back to the earliest revisitable point of the traversed path
      // — the join node. An on-cycle entrance closes to its own landing; a
      // radial entrance lands on a merge lane the ring can never re-enter,
      // so its lap cycle starts where the approach first joined the ring.
      var pathNodes: Set<Int64> = [landing]
      for edge in bodyEdges {
        pathNodes.insert(edge.fromNodeID)
      }
      guard
        let closure = circuitDijkstra(
          from: currentNode,
          cost: cost,
          isTarget: { pathNodes.contains($0) }
        )
      else {
        throw ShutoNetworkError.routeUnavailable
      }
      let joinNode = closure.target
      let joinIndex =
        bodyEdges.firstIndex { $0.fromNodeID == joinNode }
        ?? bodyEdges.count
      let entryEdges = Array(bodyEdges[..<joinIndex])
      let cycleEdges =
        Array(bodyEdges[joinIndex...]) + closure.edges
      guard !cycleEdges.isEmpty else {
        throw ShutoNetworkError.routeUnavailable
      }
      return CircuitTraversal(
        approachEdges: approach.edges,
        entryEdges: entryEdges,
        bodyEdges: cycleEdges,
        finalNode: joinNode
      )
    case .tour:
      return CircuitTraversal(
        approachEdges: approach.edges,
        entryEdges: [],
        bodyEdges: bodyEdges,
        finalNode: currentNode
      )
    }
  }

  /// Anchor node sets on the experience carriageways, resolved from the
  /// snapshot's own facilities and junctions with growing search radius.
  /// For loops the cyclic anchor sequence also prunes each set to the
  /// carriageway that travels in the cycle's direction — both directions of
  /// a ring are usually drivable, and a leg settling on the opposite
  /// carriageway can only be "reached" by an extra half-loop.
  private func anchorNodeSets(
    for circuit: ShutoCircuitDefinition,
    isMember: (ShutoNetworkDatabase.Edge) -> Bool,
    viability: inout [Int64: Bool]
  ) throws -> [Set<Int64>] {
    var anchorSets: [Set<Int64>] = []
    var anchorCoordinates: [ShutoCoordinate] = []
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
      anchorCoordinates.append(coordinate)
    }
    guard circuit.kind == .loop, anchorSets.count >= 3 else {
      return anchorSets
    }
    let longitudeScale = cos(anchorCoordinates[0].latitude * .pi / 180)
    for index in anchorSets.indices {
      let count = anchorSets.count
      let previous = anchorCoordinates[(index + count - 1) % count]
      let next = anchorCoordinates[(index + 1) % count]
      let expected = (
        x: (next.longitude - previous.longitude) * longitudeScale,
        y: next.latitude - previous.latitude
      )
      let aligned = anchorSets[index].filter { node in
        outgoingEdges[node, default: []].contains { edge in
          guard isMember(edge), edge.kind == "MAINLINE",
            let from = nodesByID[edge.fromNodeID],
            let to = nodesByID[edge.toNodeID]
          else { return false }
          let heading = (
            x: (to.coordinate.longitude - from.coordinate.longitude)
              * longitudeScale,
            y: to.coordinate.latitude - from.coordinate.latitude
          )
          return heading.x * expected.x + heading.y * expected.y > 0
        }
      }
      if !aligned.isEmpty {
        anchorSets[index] = aligned
      }
    }
    return anchorSets
  }

  // MARK: - Directed search helpers

  /// Ramp candidates onto the circuit carriageways: the cheapest viable
  /// nodes with an outgoing member mainline edge, at most one per branch
  /// (settled targets are not expanded, so consecutive downstream nodes of
  /// the same carriageway collapse into one candidate while a parallel
  /// carriageway surfaces as its own).
  private func circuitApproaches(
    entryFacility: ShutoNetworkDatabase.Facility,
    isMember: (ShutoNetworkDatabase.Edge) -> Bool,
    cost: (ShutoNetworkDatabase.Edge) -> Double,
    viability: inout [Int64: Bool]
  ) -> [(edges: [ShutoNetworkDatabase.Edge], target: Int64)] {
    let seeds = entryFacility.entryEdgeCandidates.compactMap {
      candidate in
      edgesByID[candidate.edgeID].map {
        (edge: $0, cost: candidate.distanceMeters + cost($0))
      }
    }
    guard !seeds.isEmpty else { return [] }

    var distances: [Int64: Double] = [:]
    var previous: [Int64: ShutoNetworkDatabase.Edge] = [:]
    var seedEdgeByNode: [Int64: ShutoNetworkDatabase.Edge] = [:]
    var queue = MinHeap<CircuitQueueValue>()
    for seed in seeds {
      if seed.cost < distances[seed.edge.toNodeID, default: .infinity] {
        distances[seed.edge.toNodeID] = seed.cost
        seedEdgeByNode[seed.edge.toNodeID] = seed.edge
        queue.insert(
          CircuitQueueValue(cost: seed.cost, nodeID: seed.edge.toNodeID)
        )
      }
    }
    var results: [(edges: [ShutoNetworkDatabase.Edge], target: Int64)] =
      []
    var firstTargetCost: Double?
    while let current = queue.removeMinimum() {
      guard current.cost == distances[current.nodeID] else { continue }
      if let firstTargetCost,
        current.cost > firstTargetCost + 25_000
      {
        break
      }
      let isTarget =
        outgoingEdges[current.nodeID, default: []].contains {
          isMember($0) && $0.kind == "MAINLINE"
        } && isViable(current.nodeID, cache: &viability)
      if isTarget {
        var reversed: [ShutoNetworkDatabase.Edge] = []
        var nodeID = current.nodeID
        while let edge = previous[nodeID] {
          reversed.append(edge)
          nodeID = edge.fromNodeID
        }
        if let seedEdge = seedEdgeByNode[nodeID] {
          reversed.append(seedEdge)
        }
        results.append((reversed.reversed(), current.nodeID))
        if firstTargetCost == nil {
          firstTargetCost = current.cost
        }
        if results.count >= 4 {
          break
        }
        // A settled landing is not expanded: its downstream carriageway
        // nodes would only shadow other branches.
        continue
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
    return results
  }

  private func circuitApproach(
    entryFacility: ShutoNetworkDatabase.Facility,
    isMember: (ShutoNetworkDatabase.Edge) -> Bool,
    cost: (ShutoNetworkDatabase.Edge) -> Double,
    viability: inout [Int64: Bool]
  ) -> (edges: [ShutoNetworkDatabase.Edge], target: Int64)? {
    circuitApproaches(
      entryFacility: entryFacility,
      isMember: isMember,
      cost: cost,
      viability: &viability
    ).first
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
