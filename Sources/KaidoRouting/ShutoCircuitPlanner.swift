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
    /// A parking area the course stops at rather than passes. Unlike a
    /// facility or junction anchor, this requires the entire reviewed
    /// directional path, including any repeated edges inside the PA.
    case parkingArea(String)
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
  public var defaultDestinationParkingAreaID: String? {
    switch circuitID {
    case Self.wanganDaikokuRun.circuitID, Self.daikokuYokohamaLoop.circuitID, Self.scenicGrandTour.circuitID: "shuto.pa.daikoku"
    default: nil
    }
  }
  /// Parking areas the course actually drives into, in course order. This
  /// is read off the anchors rather than listed separately so a card can
  /// never advertise a stop the route does not make.
  public var parkingAreaStopIDs: [String] {
    anchors.compactMap {
      if case .parkingArea(let parkingAreaID) = $0 { parkingAreaID }
      else { nil }
    }
  }
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

  /// C1 Inner Circular outer loop.
  public static let c1Outer = ShutoCircuitDefinition(
    circuitID: "shuto.circuit.c1-outer",
    displayNameJA: "都心環状線 外回り",
    localizedDisplayNames: [
      .japanese: "都心環状線 外回り",
      .simplifiedChinese: "都心环状线 外环",
      .english: "C1 Outer Circuit",
    ],
    kind: .loop,
    memberRouteIDs: ["C1"],
    entranceDirectionsByRouteID: ["C1": "外回り"],
    anchors: [
      .facility("shuto.ic.c1.kyoubashi"),
      .facility("shuto.ic.c1.shiodome"),
      .facility("shuto.ic.c1.shibakouen"),
      .facility("shuto.ic.c1.kasumigaseki"),
      .facility("shuto.ic.c1.kandabashi"),
    ],
    landmarkNamesJA: ["東京タワー", "銀座", "皇居"],
    localizedLandmarkNames: [
      .japanese: ["東京タワー", "銀座", "皇居"],
      .simplifiedChinese: ["东京塔", "银座", "皇居"],
      .english: ["Tokyo Tower", "Ginza", "Imperial Palace"],
    ]
  )

  /// Bayshore westbound run into Daikoku PA: Tokyo waterfront onto the
  /// Bayshore Route, across the Tsurumi Tsubasa Bridge, into the parking
  /// area itself, then back onto the Bayshore for the Daikoku Futo exit.
  /// The parking area is the point of the run, so it is an anchor the
  /// course drives through, not a landmark it passes.
  public static let wanganDaikokuRun = ShutoCircuitDefinition(
    circuitID: "shuto.circuit.wangan-daikoku-run",
    displayNameJA: "湾岸線 大黒PAラン",
    localizedDisplayNames: [
      .japanese: "湾岸線 大黒PAラン",
      .simplifiedChinese: "湾岸线 大黑 PA 巡游",
      .english: "Bayshore to Daikoku PA",
    ],
    kind: .tour,
    // K5 carries the through carriageway inside the Daikoku interchange and
    // the parking area's own ramps, so the course needs it as a connector
    // even though no entrance or exit is ever offered on it.
    memberRouteIDs: ["B", "K5"],
    entranceDirectionsByRouteID: ["B": "西行き"],
    exitDirectionsByRouteID: ["B": "西行き"],
    anchors: [
      .junction("shuto.jct.jct_tokai"),
      .parkingArea("shuto.pa.daikoku"),
      .facility("shuto.ic.b.daikokufutou"),
    ],
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
  /// the Kawasaki Line back to the Bayshore at Kawasaki-Ukishima. The
  /// operator signs the Kawasaki Line's Daishi-to-Ukishima carriageway 上り:
  /// both its entrances (大師, 殿町) are 上り and lead toward Ukishima.
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
      "K6": "上り",
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
      "K6": "上り",
    ],
    anchors: [
      .facility("shuto.ic.k1.asada"),
      .facility("shuto.ic.k6.tonomachi"),
      .facility("shuto.ic.b.higashiogishima"),
    ],
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
  /// Bayshore over the Yokohama Bay Bridge to visit Daikoku PA.
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
      .parkingArea("shuto.pa.daikoku"),
    ],
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

  /// Inclusive lap range for `.loop` experiences. Tours are always one pass.
  public static let loopLapRange = 1...9

  public static let bundled: [ShutoCircuitDefinition] = [
    .c1Inner,
    .c1Outer,
    .c2InnerWithBayshore,
    .wanganDaikokuRun,
    .daikokuYokohamaLoop,
    .scenicGrandTour,
  ]
}

/// Raised for structurally invalid circuit requests such as a bad lap count.
/// Direction-invalid facilities continue to use `facilityUnavailable`.
public enum ShutoCircuitError: Error, Equatable {
  case invalidLapCount
}

/// Surface-access tiers for reaching an entrance from the origin: Tokyo's
/// inner wards space Shuto entrances every 1–3 km, so 8 km (~15–20 min of
/// city driving) covers ordinary urban origins, 16 km is offered with a far
/// label, and longer access is explicit while the surface provider determines
/// whether a legal driving route actually exists.
public enum ShutoEntranceAccessTier: Equatable, Sendable {
  case nearby
  case far
  case extended

  public static let nearbyRadiusMeters = 8_000.0
  public static let outerRadiusMeters = 16_000.0

  public static func classify(
    distanceMeters: Double
  ) -> ShutoEntranceAccessTier {
    if distanceMeters <= nearbyRadiusMeters { return .nearby }
    if distanceMeters <= outerRadiusMeters { return .far }
    return .extended
  }
}

/// One derived entrance/exit pairing for an experience: the recommendation
/// the home card shows before any manual adjustment.
public struct ShutoCircuitPairing: Equatable, Sendable {
  public let entrance: ShutoNetworkDatabase.Facility
  /// The recommended exit. An experience with a default destination parking
  /// area ends there instead, so its recommended drive has no exit; this is
  /// then only the soonest course exit after the last anchor, for a driver
  /// who explicitly asks to end at an exit.
  public let exit: ShutoNetworkDatabase.Facility
  public let tariffBand: ShutoTariffBand?
  /// Geodesic origin-to-entrance distance when an origin was provided.
  public let entranceDistanceMeters: Double?

  public init(
    entrance: ShutoNetworkDatabase.Facility,
    exit: ShutoNetworkDatabase.Facility,
    tariffBand: ShutoTariffBand?,
    entranceDistanceMeters: Double?
  ) {
    self.entrance = entrance
    self.exit = exit
    self.tariffBand = tariffBand
    self.entranceDistanceMeters = entranceDistanceMeters
  }
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

  /// An expressway approach meter against a straight-line surface meter
  /// when ranking entrances by time to the course: the product's expressway
  /// reference is 54 km/h (catalog card, drive preview) and its surface
  /// access reference ~27 km/h (8 km in 15–20 min, `ShutoEntranceAccessTier`).
  private static let approachMeterWeight = 0.5

  /// How far past the soonest exit after the final lap a loop's recommended
  /// exit may sit: one inner-ward ramp spacing (1–3 km, see
  /// `ShutoEntranceAccessTier`), enough to reach the next exit or two for a
  /// lower band, never another pass of the course.
  private static let exitTariffSearchMeters = 3_000.0

  /// How much of a loop's final lap may stay undriven when the lap ends at
  /// the branch back onto the radial it came from instead of at that
  /// radial's merge. The branch sits just before the merge, so ending the
  /// lap at the merge sends a driver heading home round the course again.
  /// On the 2026-08-04 snapshot every C1 and C2 radial's branch back lies
  /// 357–845 m before its merge, inside the junction; 竹橋's 745 m also
  /// passes the 北の丸 exit's branch, which offers no other movement.
  private static let finalLapReturnGapMeters = 900.0

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

  /// Experiences accept off-member entrances the reachability gates admit — the
  /// fare rule's shortest-path pricing makes a minimum-band excursion
  /// possible from almost any ramp, so a radial entrance legally joining
  /// the loop is a first-class start. An entrance on a member route still
  /// has to match the experience's carriageway direction: an opposite-loop
  /// ramp is a different experience, not an approach. Tours still traverse
  /// every anchor in order after the connecting expressway approach.
  private func isEligibleEntrance(
    _ facility: ShutoNetworkDatabase.Facility,
    for circuit: ShutoCircuitDefinition
  ) -> Bool {
    guard facility.canEnter else { return false }
    guard circuit.memberRouteIDs.contains(facility.routeID) else {
      return true
    }
    return circuit.entranceDirectionsByRouteID[facility.routeID].map {
      facility.entranceDirections.contains($0)
    } ?? false
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
  /// experience, ranked from an origin by the time to reach the course: the
  /// straight line to the ramp at city speed plus, at expressway speed, the
  /// approach the plan drives before its first lap or tour pass. The
  /// reachability gate runs on the nearest `entranceCandidateLimit`
  /// candidates plus every direction-valid member-route entrance, so a
  /// distant origin never loses the route's own ramps behind nearer radial
  /// approaches. Without an origin there is no nearness to bound by: every
  /// direction-valid entrance is gated, so the list holds every entrance
  /// some origin can be offered.
  public func circuitEntranceCandidates(
    for circuit: ShutoCircuitDefinition,
    origin: ShutoCoordinate? = nil,
    includeConnectingEntrances: Bool = true
  ) -> [ShutoNetworkDatabase.Facility] {
    rankedCircuitEntrances(
      for: circuit,
      origin: origin,
      includeConnectingEntrances: includeConnectingEntrances
    ).map(\.facility)
  }

  /// `circuitEntranceCandidates` with, when an origin ranks them, the
  /// traversal each entrance drives: its approach, entry and one lap or pass.
  private func rankedCircuitEntrances(
    for circuit: ShutoCircuitDefinition,
    origin: ShutoCoordinate?,
    includeConnectingEntrances: Bool
  ) -> [(facility: ShutoNetworkDatabase.Facility, traversal: CircuitTraversal?)] {
    let eligible = database.directionalFacilities.filter {
      isEligibleEntrance($0, for: circuit)
        && (includeConnectingEntrances || circuit.memberRouteIDs.contains($0.routeID))
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
      self.circuitCost(edge, isMember: isMember(edge))
    }
    var viability: [Int64: Bool] = [:]
    guard
      let anchorSets = try? anchorNodeSets(
        for: circuit,
        isMember: isMember,
        viability: &viability
      )
    else { return [] }
    let boundedCandidates =
      origin == nil ? ranked : Array(ranked.prefix(Self.entranceCandidateLimit))
    let candidateIDs = Set(boundedCandidates.map(\.facilityID))
    let candidates = boundedCandidates + ranked.filter {
      circuit.memberRouteIDs.contains($0.routeID)
        && !candidateIDs.contains($0.facilityID)
    }
    let reachable = candidates.compactMap {
      entrance -> (
        ShutoNetworkDatabase.Facility,
        [(edges: [ShutoNetworkDatabase.Edge], target: Int64)]
      )? in
      let approaches = circuitApproaches(
        entryFacility: entrance,
        isMember: isMember,
        cost: cost,
        viability: &viability
      )
      let admitted = approaches.contains { approach in
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
        if circuit.kind == .tour, let first = anchorReaches.first,
          anchorReaches.dropFirst().contains(where: { $0.distance + 1_000 < first.distance }) {
          return false
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
      return admitted ? (entrance, approaches) : nil
    }
    guard let origin else { return reachable.map { ($0.0, nil) } }
    // The gates measure from where the approach joins the course, so a ramp
    // beside the origin passes them even with an 18 km off-course approach,
    // and straight-line nearness alone would then outrank the course's own
    // ramp a few kilometers away.
    return reachable.compactMap {
      entrance, approaches -> (ShutoNetworkDatabase.Facility, CircuitTraversal, Double)? in
      guard
        let traversal = try? shortestTraversal(
          circuit: circuit,
          approaches: approaches,
          anchorSets: anchorSets,
          cost: cost
        )
      else { return nil }
      let approachMeters = (traversal.approachEdges + traversal.entryEdges)
        .reduce(0) { $0 + $1.lengthMeters }
      return (
        entrance,
        traversal,
        Self.distance(origin, entrance.coordinate)
          + approachMeters * Self.approachMeterWeight
      )
    }
    .sorted {
      if $0.2 != $1.2 { return $0.2 < $1.2 }
      return $0.0.facilityID < $1.0.facilityID
    }
    .map { ($0.0, $0.1) }
  }

  /// Direction-valid exits ranked by forward travel distance after the
  /// experience body completes — after the loop closes, or after the tour's
  /// last anchor. Geodesic nearness would be wrong here: an exit a few
  /// hundred meters behind the course is almost a full lap away.
  public func circuitExitCandidates(
    for circuit: ShutoCircuitDefinition,
    afterEntering entryFacilityID: String
  ) throws -> [ShutoNetworkDatabase.Facility] {
    try circuitExitTails(for: circuit, afterEntering: entryFacilityID)
      .map(\.facility)
  }

  /// `circuitExitCandidates` in the same order, each with the meters its
  /// exit tail drives after the body and how many of them are on the course.
  private func circuitExitTails(
    for circuit: ShutoCircuitDefinition,
    afterEntering entryFacilityID: String
  ) throws -> [ExitTail] {
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
      self.circuitCost(edge, isMember: isMember(edge))
    }
    var viability: [Int64: Bool] = [:]
    let traversal = try circuitTraversal(
      circuit: circuit,
      entryFacility: entryFacility,
      isMember: isMember,
      cost: cost,
      viability: &viability
    )
    return circuitExitTails(
      for: circuit,
      entryFacility: entryFacility,
      traversal: traversal,
      isMember: isMember,
      cost: cost
    )
  }

  private struct ExitTail {
    let facility: ShutoNetworkDatabase.Facility
    let meters: Double
    let onCourseMeters: Double
  }

  private func circuitExitTails(
    for circuit: ShutoCircuitDefinition,
    entryFacility: ShutoNetworkDatabase.Facility,
    traversal: CircuitTraversal,
    isMember: (ShutoNetworkDatabase.Edge) -> Bool,
    cost: (ShutoNetworkDatabase.Edge) -> Double
  ) -> [ExitTail] {
    let returns =
      circuit.kind == .loop
      ? finalLapReturns(for: circuit, traversal: traversal, isMember: isMember)
      : []
    let forward = tailReach(
      from: traversal.finalNode,
      returns: returns,
      isMember: isMember,
      cost: cost
    )
    let ranked: [(tail: ExitTail, cost: Double)] =
      database.directionalFacilities.compactMap { facility in
        guard isEligibleExit(facility, for: circuit),
          !Self.sharesTollPoint(entryFacility, facility)
        else { return nil }
        return facility.exitEdgeCandidates.compactMap {
          candidate -> (tail: ExitTail, cost: Double)? in
          guard let edge = edgesByID[candidate.edgeID],
            let reach = forward[edge.fromNodeID]
          else { return nil }
          return (
            ExitTail(
              facility: facility,
              meters: reach.meters + edge.lengthMeters,
              onCourseMeters: reach.onCourseMeters
                + (isMember(edge) ? edge.lengthMeters : 0)
            ),
            reach.cost + candidate.distanceMeters
          )
        }.min { $0.cost < $1.cost }
      }
    return
      ranked
      .sorted {
        if $0.cost != $1.cost { return $0.cost < $1.cost }
        return $0.tail.facility.facilityID < $1.tail.facility.facilityID
      }
      .map(\.tail)
  }

  /// A place the final lap may end short of the merge: after the first
  /// `bodyCount` edges of the lap, where `branch` leaves for the approach's
  /// own radial, leaving `undrivenMeters` of the lap undriven.
  private struct FinalLapReturn {
    let bodyCount: Int
    let undrivenMeters: Double
    let branch: ShutoNetworkDatabase.Edge
  }

  /// The branches back onto the radial the approach joined the loop from
  /// that leave the lap within `finalLapReturnGapMeters` of its end. An
  /// entrance on the loop itself has no radial and no such branch.
  private func finalLapReturns(
    for circuit: ShutoCircuitDefinition,
    traversal: CircuitTraversal,
    isMember: (ShutoNetworkDatabase.Edge) -> Bool
  ) -> [FinalLapReturn] {
    guard
      let radial = (traversal.approachEdges + traversal.entryEdges).last(where: {
        $0.kind == "MAINLINE" && !isMember($0)
      })
    else { return [] }
    let radialRouteIDs = Set(radial.routeMemberships.map(\.routeID))
      .subtracting(circuit.memberRouteIDs)
    var returns: [FinalLapReturn] = []
    var undriven = 0.0
    for index in traversal.bodyEdges.indices.reversed() {
      let lapEdge = traversal.bodyEdges[index]
      undriven += lapEdge.lengthMeters
      guard undriven <= Self.finalLapReturnGapMeters else { break }
      for branch in outgoingEdges[lapEdge.fromNodeID, default: []]
      where branch.edgeID != lapEdge.edgeID
        && leadsOntoRoute(branch, routeIDs: radialRouteIDs, isMember: isMember)
      {
        returns.append(
          FinalLapReturn(bodyCount: index, undrivenMeters: undriven, branch: branch)
        )
      }
    }
    return returns
  }

  /// Whether a branch's ramp, followed through links only, reaches a
  /// carriageway of one of `routeIDs` before any other carriageway.
  private func leadsOntoRoute(
    _ branch: ShutoNetworkDatabase.Edge,
    routeIDs: Set<String>,
    isMember: (ShutoNetworkDatabase.Edge) -> Bool
  ) -> Bool {
    var frontier = [branch]
    var seen: Set<String> = []
    while let edge = frontier.popLast() {
      guard seen.insert(edge.edgeID).inserted, edge.kind != "PARKING" else { continue }
      if edge.kind == "MAINLINE" {
        if !isMember(edge), edge.routeMemberships.contains(where: { routeIDs.contains($0.routeID) }) {
          return true
        }
        continue
      }
      frontier.append(contentsOf: outgoingEdges[edge.toNodeID, default: []])
    }
    return false
  }

  /// Cheapest cost, with the meters driven and those on the course, from
  /// where the final lap ends to every node: its merge, or one of its
  /// `returns`, whose undriven lap meters count against the tail's cost.
  /// Exits rank by cost, but the driver covers meters.
  private func tailReach(
    from finalNode: Int64,
    returns: [FinalLapReturn],
    isMember: (ShutoNetworkDatabase.Edge) -> Bool,
    cost: (ShutoNetworkDatabase.Edge) -> Double
  ) -> [Int64: (cost: Double, meters: Double, onCourseMeters: Double)] {
    var reach: [Int64: (cost: Double, meters: Double, onCourseMeters: Double)] = [
      finalNode: (0, 0, 0)
    ]
    var queue = MinHeap<CircuitQueueValue>()
    queue.insert(CircuitQueueValue(cost: 0, nodeID: finalNode))
    for lapReturn in returns {
      let branch = lapReturn.branch
      let seedCost = cost(branch) - lapReturn.undrivenMeters
      guard seedCost < reach[branch.toNodeID]?.cost ?? .infinity else { continue }
      reach[branch.toNodeID] = (
        seedCost, branch.lengthMeters, isMember(branch) ? branch.lengthMeters : 0
      )
      queue.insert(CircuitQueueValue(cost: seedCost, nodeID: branch.toNodeID))
    }
    while let current = queue.removeMinimum() {
      guard let settled = reach[current.nodeID],
        current.cost == settled.cost
      else { continue }
      for edge in outgoingEdges[current.nodeID, default: []] {
        let candidate = current.cost + cost(edge)
        if candidate >= reach[edge.toNodeID]?.cost ?? .infinity {
          continue
        }
        reach[edge.toNodeID] = (
          candidate,
          settled.meters + edge.lengthMeters,
          settled.onCourseMeters + (isMember(edge) ? edge.lengthMeters : 0)
        )
        queue.insert(
          CircuitQueueValue(cost: candidate, nodeID: edge.toNodeID)
        )
      }
    }
    return reach
  }

  /// Exits some directed all-Shuto path reaches after entering at one
  /// facility, other than the entrance's own toll point, in the same order
  /// the caller passes them. An editor that offers only these can never
  /// draft a pairing `plan` would refuse.
  public func exitCandidates(
    _ candidates: [ShutoNetworkDatabase.Facility],
    reachableAfterEntering entryFacilityID: String
  ) -> [ShutoNetworkDatabase.Facility] {
    guard let entry = facilitiesByID[entryFacilityID], entry.canEnter
    else { return [] }
    let cost: (ShutoNetworkDatabase.Edge) -> Double = {
      self.edgeCost($0, preference: .recommended)
    }
    var reachable: Set<Int64> = []
    for candidate in entry.entryEdgeCandidates {
      guard let edge = edgesByID[candidate.edgeID] else { continue }
      reachable.formUnion(forwardDistances(from: edge.toNodeID, cost: cost).keys)
    }
    return candidates.filter { facility in
      facility.canExit
        && !Self.sharesTollPoint(entry, facility)
        && facility.exitEdgeCandidates.contains {
          guard let edge = edgesByID[$0.edgeID] else { return false }
          return reachable.contains(edge.fromNodeID)
        }
    }
  }

  /// Entrances from which some directed all-Shuto path reaches one exit, in
  /// the same order the caller passes them: the mirror of
  /// `exitCandidates(_:reachableAfterEntering:)` for an editor whose driver
  /// fixes the exit first.
  public func entryCandidates(
    _ candidates: [ShutoNetworkDatabase.Facility],
    reaching exitFacilityID: String
  ) -> [ShutoNetworkDatabase.Facility] {
    guard let exit = facilitiesByID[exitFacilityID], exit.canExit
    else { return [] }
    var reaching: Set<Int64> = []
    var frontier: [Int64] = []
    for candidate in exit.exitEdgeCandidates {
      guard let edge = edgesByID[candidate.edgeID],
        reaching.insert(edge.fromNodeID).inserted
      else { continue }
      frontier.append(edge.fromNodeID)
    }
    while let node = frontier.popLast() {
      for edge in incomingEdges[node, default: []]
      where edgeCost(edge, preference: .recommended).isFinite
        && reaching.insert(edge.fromNodeID).inserted
      {
        frontier.append(edge.fromNodeID)
      }
    }
    return candidates.filter { facility in
      facility.canEnter
        && !Self.sharesTollPoint(facility, exit)
        && facility.entryEdgeCandidates.contains {
          guard let edge = edgesByID[$0.edgeID] else { return false }
          return reaching.contains(edge.toNodeID)
        }
    }
  }

  /// The derived pairing an experience card shows: the reachable entrance
  /// that reaches the course soonest, and — for loops — the exit whose
  /// pairing lands in the lowest tariff band among those reached soon after
  /// the final lap, tie-broken by forward travel. Tours keep their
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
    let exits = try circuitExitTails(
      for: circuit,
      afterEntering: entrance.facilityID
    )
    guard let leading = exits.first?.facility else {
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
    // Tariff-best exit for a loop, among the exits within one ramp spacing
    // of the soonest exit after the final lap. The band prices the shortest
    // entry-exit path, so an exit beside the entrance often quotes the
    // minimum — but after the laps it can be most of another lap away, and
    // no fare saving is worth driving a pass the driver did not choose.
    let soonest = exits.map(\.meters).min()!
    let candidates = exits.filter {
      $0.meters <= soonest + Self.exitTariffSearchMeters
    }
    var best: (
      facility: ShutoNetworkDatabase.Facility,
      band: ShutoTariffBand
    )?
    for exit in candidates {
      guard
        let band = try? tariffBand(
          entryFacilityID: entrance.facilityID,
          exitFacilityID: exit.facility.facilityID,
          evidence: evidence
        )
      else { continue }
      if best == nil || band.quotedYen < best!.band.quotedYen {
        best = (exit.facility, band)
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

  /// Pairings for a loop driven from the origin and back to it, one per
  /// entrance, in the order the card lists them. The fare prices only the
  /// shortest path between entrance and exit, so the cheapest return trip
  /// enters near the origin and leaves near it again, driving the approach
  /// back. The three nearest entrances by straight line lead the list,
  /// leaving out any whose approach exceeds twice the straight line to the
  /// course's nearest own ramp plus 1 km: it reaches the course only by a
  /// detour. Each entrance takes the lowest band among the exits whose tail
  /// after the final lap is at most its approach plus one ramp spacing and
  /// drives at most one ramp spacing on the course — the way home, never
  /// another pass — ties going to the exit nearer the origin and then to
  /// the shorter tail; without such an exit it keeps the soonest-exit rule
  /// of `recommendedCircuitPairing`. Of the three, the lowest band comes
  /// first, ties going to the nearer entrance and then to the exit nearer
  /// the origin; every other entrance follows by straight line. Empty for a
  /// tour.
  public func returnTripCircuitPairings(
    for circuit: ShutoCircuitDefinition,
    origin: ShutoCoordinate,
    includeConnectingEntrances: Bool = true,
    evidence: ShutoTariffEvidence?
  ) -> [ShutoCircuitPairing] {
    guard circuit.kind == .loop else { return [] }
    let isMember: (ShutoNetworkDatabase.Edge) -> Bool = { edge in
      edge.routeMemberships.contains {
        circuit.memberRouteIDs.contains($0.routeID)
      }
    }
    let cost: (ShutoNetworkDatabase.Edge) -> Double = { edge in
      self.circuitCost(edge, isMember: isMember(edge))
    }
    let entrances = rankedCircuitEntrances(
      for: circuit,
      origin: origin,
      includeConnectingEntrances: includeConnectingEntrances
    ).compactMap { entrance, traversal in
      traversal.map {
        (
          facility: entrance,
          traversal: $0,
          access: Self.distance(origin, entrance.coordinate),
          approach: ($0.approachEdges + $0.entryEdges).reduce(0) { $0 + $1.lengthMeters }
        )
      }
    }
    guard
      let ownRamp = entrances.filter({
        circuit.memberRouteIDs.contains($0.facility.routeID)
      }).map(\.access).min()
    else { return [] }
    let pairings = entrances
      .filter { $0.approach <= 2 * ownRamp + 1_000 }
      .sorted {
        if $0.access != $1.access { return $0.access < $1.access }
        return $0.facility.facilityID < $1.facility.facilityID
      }
      .compactMap { entrance -> ShutoCircuitPairing? in
        let exits = circuitExitTails(
          for: circuit,
          entryFacility: entrance.facility,
          traversal: entrance.traversal,
          isMember: isMember,
          cost: cost
        ).filter {
          $0.meters <= entrance.approach + Self.exitTariffSearchMeters
            && $0.onCourseMeters <= Self.exitTariffSearchMeters
        }
        guard !exits.isEmpty else {
          return try? recommendedCircuitPairing(
            for: circuit,
            entranceFacilityID: entrance.facility.facilityID,
            origin: origin,
            evidence: evidence
          )
        }
        let bands = evidence.map {
          tariffBands(
            entryFacilityID: entrance.facility.facilityID,
            exitFacilityIDs: exits.map(\.facility.facilityID),
            evidence: $0
          )
        } ?? [:]
        let best = exits.min {
          let first = bands[$0.facility.facilityID]?.quotedYen ?? .max
          let second = bands[$1.facility.facilityID]?.quotedYen ?? .max
          if first != second { return first < second }
          let firstHome = Self.distance($0.facility.coordinate, origin)
          let secondHome = Self.distance($1.facility.coordinate, origin)
          if firstHome != secondHome { return firstHome < secondHome }
          return $0.meters < $1.meters
        }!
        return ShutoCircuitPairing(
          entrance: entrance.facility,
          exit: best.facility,
          tariffBand: bands[best.facility.facilityID],
          entranceDistanceMeters: entrance.access
        )
      }
    let nearest = pairings.prefix(3).sorted {
      let first = $0.tariffBand?.quotedYen ?? .max
      let second = $1.tariffBand?.quotedYen ?? .max
      if first != second { return first < second }
      if $0.entranceDistanceMeters != $1.entranceDistanceMeters {
        return ($0.entranceDistanceMeters ?? 0) < ($1.entranceDistanceMeters ?? 0)
      }
      return Self.distance($0.exit.coordinate, origin) < Self.distance($1.exit.coordinate, origin)
    }
    return nearest + pairings.dropFirst(3)
  }

  /// Plans a whole-experience route: entrance approach, the experience body
  /// (`laps` complete loops as distinct ordered occurrences, or the tour's
  /// single ordered pass), then the exit.
  public func planCircuit(
    circuit: ShutoCircuitDefinition,
    entryFacilityID: String,
    exitFacilityID: String? = nil,
    destinationParkingAreaID: String? = nil,
    laps: Int,
    preference: ShutoRoutePreference = .recommended
  ) throws -> ShutoPlannedRoute {
    try planCircuit(
      circuit: circuit,
      entryFacilityID: entryFacilityID,
      exitFacilityID: exitFacilityID,
      destinationParkingAreaID: destinationParkingAreaID,
      laps: laps,
      preference: preference,
      staysOnCarriagewayOnTies: true
    )
  }

  /// Plans the circuit a stored plan was drawn from — a saved route, or a
  /// drive restored after relaunch — as the planner drew it then. A plan
  /// stored before the carriageway tie-break may take a link the planner
  /// now leaves to the carriageway beside it (Hakozaki JCT, Shibaura JCT); planning it
  /// without the tie-break reproduces it, so it still opens and drives.
  /// Callers still compare the result with the stored plan. Its callers are
  /// the saved-route and checkpoint restores in WholeShutoProductModel; saved
  /// routes are kept without migration, so the earlier plan stays reachable.
  public func planCircuit(
    reproducing storedPlan: RoutePlan,
    circuit: ShutoCircuitDefinition,
    laps: Int,
    preference: ShutoRoutePreference = .recommended
  ) throws -> ShutoPlannedRoute {
    let current = try planCircuit(
      circuit: circuit,
      entryFacilityID: storedPlan.entryFacilityID,
      exitFacilityID: storedPlan.exitFacilityID,
      destinationParkingAreaID: storedPlan.destinationParkingAreaID,
      laps: laps,
      preference: preference
    )
    guard current.routePlan != storedPlan else { return current }
    let earlier = try planCircuit(
      circuit: circuit,
      entryFacilityID: storedPlan.entryFacilityID,
      exitFacilityID: storedPlan.exitFacilityID,
      destinationParkingAreaID: storedPlan.destinationParkingAreaID,
      laps: laps,
      preference: preference,
      staysOnCarriagewayOnTies: false
    )
    return earlier.routePlan == storedPlan ? earlier : current
  }

  private func planCircuit(
    circuit: ShutoCircuitDefinition,
    entryFacilityID: String,
    exitFacilityID: String?,
    destinationParkingAreaID: String?,
    laps: Int,
    preference: ShutoRoutePreference,
    staysOnCarriagewayOnTies: Bool
  ) throws -> ShutoPlannedRoute {
    switch circuit.kind {
    case .loop:
      guard ShutoCircuitDefinition.loopLapRange.contains(laps) else {
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
    let parkingID = destinationParkingAreaID ?? (exitFacilityID == nil ? circuit.defaultDestinationParkingAreaID : nil)
    let parking = database.parkingAreas.first { $0.parkingAreaID == parkingID }
    let exitFacility = parkingID == nil ? exitFacilityID.flatMap { facilitiesByID[$0] } : nil
    guard (parking?.isDrivable == true && exitFacility == nil)
      || (parking == nil && exitFacility.map { isEligibleExit($0, for: circuit) } == true)
    else { throw ShutoNetworkError.facilityUnavailable }
    // Returning to the entrance's own toll point is not plannable as an
    // exact entry/exit route either: whatever the laps, the toll-point path
    // that prices the pairing collapses to the ramps themselves.
    if let exitFacility, Self.sharesTollPoint(entryFacility, exitFacility) {
      throw ShutoNetworkError.sharedTollPoint
    }

    let isMember: (ShutoNetworkDatabase.Edge) -> Bool = { edge in
      edge.routeMemberships.contains {
        circuit.memberRouteIDs.contains($0.routeID)
      }
    }
    let cost: (ShutoNetworkDatabase.Edge) -> Double = { edge in
      self.circuitCost(
        edge, isMember: isMember(edge), staysOnCarriageway: staysOnCarriagewayOnTies
      )
    }
    var viability: [Int64: Bool] = [:]
    var traversal = try circuitTraversal(
      circuit: circuit,
      entryFacility: entryFacility,
      isMember: isMember,
      cost: cost,
      viability: &viability
    )

    var tailEdges: [ShutoNetworkDatabase.Edge]
    var finalLapEdges = traversal.bodyEdges
    if let parking, let access = parking.accessNodeID {
      let arrival = try parkingArrivalEdges(parking)
      if circuit.kind == .tour, parkingID == circuit.defaultDestinationParkingAreaID,
        let start = traversal.bodyEdges.firstIndex(where: { $0.edgeID == parking.interiorEdgeIDs?.first }) {
        traversal.bodyEdges = Array(traversal.bodyEdges.prefix(start)) + arrival
        traversal.finalNode = arrival.last!.toNodeID
        tailEdges = []
      } else {
        let connection: [ShutoNetworkDatabase.Edge]
        if traversal.finalNode == access { connection = [] }
        else if let path = circuitDijkstra(from: traversal.finalNode, cost: cost, isTarget: { $0 == access }) { connection = path.edges }
        else { throw ShutoNetworkError.routeUnavailable }
        tailEdges = connection + arrival
      }
    } else if let exitFacility {
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
    let returns =
      circuit.kind == .loop
      ? finalLapReturns(for: circuit, traversal: traversal, isMember: isMember)
      : []
    guard !exitEdgesByNode.isEmpty,
      let tail = circuitDijkstra(
        seeds: returns.map { ($0.branch, cost($0.branch) - $0.undrivenMeters) },
        start: traversal.finalNode,
        cost: cost,
        isTarget: { exitEdgesByNode[$0] != nil }
      ),
      let exitChoice = exitEdgesByNode[tail.target]?
        .min(by: { $0.match + cost($0.edge) < $1.match + cost($1.edge) })
    else {
      throw ShutoNetworkError.routeUnavailable
    }
    tailEdges = tail.edges
    if tailEdges.last?.edgeID != exitChoice.edge.edgeID {
      tailEdges.append(exitChoice.edge)
    }
    if let lapReturn = returns.first(where: { $0.branch.edgeID == tailEdges.first?.edgeID }) {
      finalLapEdges = Array(traversal.bodyEdges.prefix(lapReturn.bodyCount))
    }

    } else { throw ShutoNetworkError.facilityUnavailable }

    // Assemble: approach + one-time entry + body + tail, with distinct
    // occurrences per lap. Laps legitimately repeat edge IDs, but never the
    // same edge twice in a row — adjacent duplicates would be a stitching
    // fault — so the collapse happens as the route is stitched, letting each
    // lap's true first occurrence index be recorded on the way past.
    var routeEdges: [ShutoNetworkDatabase.Edge] = []
    func appendStretch(_ edges: [ShutoNetworkDatabase.Edge]) {
      for edge in edges where routeEdges.last?.edgeID != edge.edgeID {
        routeEdges.append(edge)
      }
    }
    appendStretch(traversal.approachEdges)
    appendStretch(traversal.entryEdges)
    var lapBoundaryOccurrenceIndices: [Int] = []
    switch circuit.kind {
    case .loop:
      for lap in 0..<laps {
        let lapStart = routeEdges.count
        appendStretch(lap == laps - 1 ? finalLapEdges : traversal.bodyEdges)
        lapBoundaryOccurrenceIndices.append(
          min(lapStart, max(0, routeEdges.count - 1))
        )
      }
      // The final lap ends where the exit tail begins.
      lapBoundaryOccurrenceIndices.append(routeEdges.count)
    case .tour:
      appendStretch(traversal.bodyEdges)
    }
    appendStretch(tailEdges)

    return assemblePlannedRoute(
      routeEdges: routeEdges,
      planID:
        "\(circuit.circuitID).\(entryFacility.facilityID)."
        + "\(parkingID ?? exitFacility!.facilityID).x\(laps)."
        + preference.rawValue.lowercased(),
      entryFacility: entryFacility,
      exitFacility: exitFacility,
      destinationParkingArea: parking,
      preference: preference,
      lapBoundaryOccurrenceIndices: lapBoundaryOccurrenceIndices
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
    var bodyEdges: [ShutoNetworkDatabase.Edge]
    /// Where the exit tail begins: the cycle's join node for a loop, the
    /// last anchor's settled node for a tour.
    var finalNode: Int64
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
    return try shortestTraversal(
      circuit: circuit,
      approaches: approaches,
      anchorSets: anchorSets,
      cost: cost
    )
  }

  private func shortestTraversal(
    circuit: ShutoCircuitDefinition,
    approaches: [(edges: [ShutoNetworkDatabase.Edge], target: Int64)],
    anchorSets: [Set<Int64>],
    cost: (ShutoNetworkDatabase.Edge) -> Double
  ) throws -> CircuitTraversal {
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
    let orderedIndices: [Int]
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
      orderedIndices = (0..<anchorSets.count).map {
        (startIndex + $0) % anchorSets.count
      }
    case .tour:
      orderedIndices = Array(anchorSets.indices)
    }

    var bodyEdges: [ShutoNetworkDatabase.Edge] = []
    var currentNode = landing
    for index in orderedIndices {
      let nodes = anchorSets[index]
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
      if case .parkingArea(let parkingAreaID) = circuit.anchors[index] {
        guard let parkingArea = database.parkingAreas.first(where: {
          $0.parkingAreaID == parkingAreaID
        }), let edgeIDs = parkingArea.interiorEdgeIDs, !edgeIDs.isEmpty else {
          throw ShutoNetworkError.facilityUnavailable
        }
        for edgeID in edgeIDs {
          guard let edge = edgesByID[edgeID], edge.kind == "PARKING",
            edge.fromNodeID == currentNode else {
            throw ShutoNetworkError.routeUnavailable
          }
          bodyEdges.append(edge)
          currentNode = edge.toNodeID
        }
        guard currentNode == parkingArea.returnNodeID else {
          throw ShutoNetworkError.routeUnavailable
        }
      }
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
      case .parkingArea(let parkingAreaID):
        guard
          let parkingArea = database.parkingAreas.first(where: {
            $0.parkingAreaID == parkingAreaID
          }),
          let accessNodeID = parkingArea.accessNodeID
        else {
          // A parking area with no reviewed interior can be signed but not
          // stopped at, and a course that claims to stop there is wrong
          // rather than approximately right.
          throw ShutoNetworkError.facilityUnavailable
        }
        anchorSets.append([accessNodeID])
        anchorCoordinates.append(parkingArea.coordinate)
        continue
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

  /// What an edge costs a circuit search. An edge off the circuit's own
  /// carriageways weighs 25 times its length, so the search keeps to them;
  /// a ramp leaving a carriageway adds `carriagewayDepartureMeters`, so of
  /// two paths that close the one staying on the carriageway wins. At
  /// Hakozaki JCT the outbound Route 6 plan otherwise left the carriageway for
  /// the rotary link, 0.8 m shorter than the carriageway it rejoins.
  private func circuitCost(
    _ edge: ShutoNetworkDatabase.Edge,
    isMember: Bool,
    staysOnCarriageway: Bool = true
  ) -> Double {
    guard edge.kind != "PARKING" else { return .infinity }
    let leavesCarriageway =
      staysOnCarriageway && edge.kind == "LINK"
      && outgoingEdges[edge.fromNodeID, default: []].contains { $0.kind == "MAINLINE" }
    return (edge.lengthMeters + (leavesCarriageway ? Self.carriagewayDepartureMeters : 0))
      * (isMember ? 1 : 25)
  }

  /// The largest difference in length the carriageway tie-break settles.
  static let carriagewayDepartureMeters = 10.0

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

  func circuitDijkstra(
    from node: Int64,
    cost: (ShutoNetworkDatabase.Edge) -> Double,
    isTarget: (Int64) -> Bool
  ) -> (edges: [ShutoNetworkDatabase.Edge], target: Int64)? {
    circuitDijkstra(seeds: nil, start: node, cost: cost, isTarget: isTarget)
  }

  func circuitDijkstra(
    seeds: [(edge: ShutoNetworkDatabase.Edge, cost: Double)],
    cost: (ShutoNetworkDatabase.Edge) -> Double,
    isTarget: (Int64) -> Bool
  ) -> (edges: [ShutoNetworkDatabase.Edge], target: Int64)? {
    circuitDijkstra(seeds: seeds, start: nil, cost: cost, isTarget: isTarget)
  }

  /// Dijkstra that stops at the first settled node satisfying `isTarget`.
  /// Either `seeds` (initial edges with entry costs) or `start` must be given.
  func circuitDijkstra(
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

  /// Full relaxation from one node; used to discover anchor travel order
  /// and gate entrance reachability.
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
