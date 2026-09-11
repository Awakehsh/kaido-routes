import Foundation

/// One dated tariff rule for one vehicle class and payment method. The Shuto
/// tariff uses the shortest all-Shuto path between entry and exit ("料金距離")
/// regardless of the driven route, so lap count never changes the quoted band.
/// Amounts derive from the operator formula
/// (料金距離 × 円/km + 150円) × 消費税率, clamped to the lower/upper limits.
public struct ShutoTariffEvidence: Equatable, Sendable {
  public let tariffID: String
  public let status: String
  public let vehicleClassJA: String
  public let paymentJA: String
  public let minimumYen: Int
  public let maximumYen: Int
  public let yenPerKilometer: Double
  public let fixedYen: Double
  public let consumptionTaxRate: Double
  public let sourceURL: String
  public let checkedAt: String
  /// First and last JST calendar day ("YYYY-MM-DD") the rule is payable;
  /// nil leaves that side open.
  public let effectiveFrom: String?
  public let effectiveUntil: String?

  public init(
    tariffID: String,
    status: String,
    vehicleClassJA: String,
    paymentJA: String,
    minimumYen: Int,
    maximumYen: Int,
    yenPerKilometer: Double,
    fixedYen: Double,
    consumptionTaxRate: Double,
    sourceURL: String,
    checkedAt: String,
    effectiveFrom: String? = nil,
    effectiveUntil: String? = nil
  ) {
    self.tariffID = tariffID
    self.status = status
    self.vehicleClassJA = vehicleClassJA
    self.paymentJA = paymentJA
    self.minimumYen = minimumYen
    self.maximumYen = maximumYen
    self.yenPerKilometer = yenPerKilometer
    self.fixedYen = fixedYen
    self.consumptionTaxRate = consumptionTaxRate
    self.sourceURL = sourceURL
    self.checkedAt = checkedAt
    self.effectiveFrom = effectiveFrom
    self.effectiveUntil = effectiveUntil
  }

  /// Normal car, ETC, until the 2026-10-01 revision. Checked on the operator
  /// ETC fee page, which on 2026-09-12 still quoted this rule as current.
  public static let etcNormalCarUntil2026September = ShutoTariffEvidence(
    tariffID: "shutoko.tariff.etc.normal-car.until-2026-09",
    status: "ACTIVE",
    vehicleClassJA: "普通車",
    paymentJA: "ETC",
    minimumYen: 300,
    maximumYen: 1_950,
    yenPerKilometer: 29.52,
    fixedYen: 150,
    consumptionTaxRate: 0.10,
    sourceURL: "https://www.shutoko.jp/fee/fee-info/pay_etc/",
    checkedAt: "2026-09-12",
    effectiveUntil: "2026-09-30"
  )

  /// Normal car, ETC, from the 2026-10-01 revision. The operator's revision
  /// site, checked 2026-09-12, states verbatim that the rate per kilometre
  /// rises for a normal car from 29.52 to 32.472 yen at 00:00 on
  /// 2026-10-01, that the 300 yen lower limit and the 55.0 km upper-limit
  /// distance are kept, and that cash vehicles pay the ETC upper limit. The
  /// upper amount is the operator's own formula at 55.0 km,
  /// (55.0 × 32.472 + 150) × 1.10 = 2,129.6, in the 10 yen unit the current
  /// cap also uses: 2,130 yen. Earlier than its first day the selector
  /// below never returns it, so a dated future rule is never quoted early.
  public static let etcNormalCarFrom2026October = ShutoTariffEvidence(
    tariffID: "shutoko.tariff.etc.normal-car.from-2026-10",
    status: "ACTIVE",
    vehicleClassJA: "普通車",
    paymentJA: "ETC",
    minimumYen: 300,
    maximumYen: 2_130,
    yenPerKilometer: 32.472,
    fixedYen: 150,
    consumptionTaxRate: 0.10,
    sourceURL: "https://www.shutoko.jp/ss/2026ryoukin-kaitei/",
    checkedAt: "2026-09-12",
    effectiveFrom: "2026-10-01"
  )

  /// The normal-car ETC rule payable on one JST calendar day ("YYYY-MM-DD").
  public static func etcNormalCar(effectiveOn day: String) -> ShutoTariffEvidence {
    etcNormalCarFrom2026October.effectiveFrom.map { day >= $0 } == true
      ? etcNormalCarFrom2026October
      : etcNormalCarUntil2026September
  }

  /// Pre-tax-rounding amount for a tariff distance; callers decide banding.
  package func rawYen(forTariffDistanceMeters meters: Double) -> Double {
    (meters / 1_000 * yenPerKilometer + fixedYen)
      * (1 + consumptionTaxRate)
  }
}

/// A band statement honest about geometry limits: snapshot geometry only
/// approximates operator tariff distance, so mid-range amounts stay estimates
/// and the limit bands are asserted only with a safety margin.
public enum ShutoTariffBand: Equatable, Sendable {
  case minimum(yen: Int)
  case estimated(yen: Int)
  case maximum(yen: Int)

  /// The quoted amount regardless of band certainty; used to order pairings.
  public var quotedYen: Int {
    switch self {
    case .minimum(let yen), .estimated(let yen), .maximum(let yen):
      return yen
    }
  }
}

extension ShutoRoutePlanner {
  /// Distance-uncertainty margin between snapshot geometry and operator
  /// tariff distance.
  private static let tariffDistanceMarginMeters = 500.0

  /// Tariff band for one entry/exit pairing under one dated tariff rule.
  /// The fare distance is the shortest DRIVABLE directed path between the
  /// two TOLL POINTS, where same-named ramps bill as one toll point — both
  /// verified against the operator's own fare search on 2026-08-04:
  /// Hatsudai-minami to Tomigaya quotes the minimum; Shinjuku to Yoyogi —
  /// one kilometer apart on the ground but only connected through a full
  /// C1 circuit — quotes ¥860; and Daikoku-Futo resolves its Bayshore and
  /// Daikoku Line ramps to the single toll point B08, pricing the Namamugi
  /// pairing over the 15 km Bayshore-side path. Direction matters (an
  /// undirected distance under-quotes every turn-back pairing), and the
  /// toll-point grouping takes the cheapest ramp of each name.
  public func tariffBand(
    entryFacilityID: String,
    exitFacilityID: String,
    evidence: ShutoTariffEvidence
  ) throws -> ShutoTariffBand {
    guard
      let distance = tollPointFareDistanceMeters(
        entryFacilityID: entryFacilityID,
        exitFacilityID: exitFacilityID
      )
    else {
      throw ShutoNetworkError.routeUnavailable
    }
    let margin = Self.tariffDistanceMarginMeters
    if evidence.rawYen(forTariffDistanceMeters: distance + margin)
      <= Double(evidence.minimumYen)
    {
      return .minimum(yen: evidence.minimumYen)
    }
    if evidence.rawYen(forTariffDistanceMeters: distance - margin)
      >= Double(evidence.maximumYen)
    {
      return .maximum(yen: evidence.maximumYen)
    }
    let raw = evidence.rawYen(forTariffDistanceMeters: distance)
    let rounded = Int((raw / 10).rounded()) * 10
    let clamped = min(
      max(rounded, evidence.minimumYen),
      evidence.maximumYen
    )
    return .estimated(yen: clamped)
  }

  /// Shortest directed network distance between two toll points, seeding
  /// from every same-named entrance ramp and terminating at every
  /// same-named exit ramp.
  private func tollPointFareDistanceMeters(
    entryFacilityID: String,
    exitFacilityID: String
  ) -> Double? {
    guard let entry = facilitiesByID[entryFacilityID],
      let exit = facilitiesByID[exitFacilityID]
    else { return nil }
    let entryGroup = database.directionalFacilities.filter {
      $0.nameJA == entry.nameJA && $0.canEnter
    }
    let exitGroup = database.directionalFacilities.filter {
      $0.nameJA == exit.nameJA && $0.canExit
    }

    var targets: [Int64: Double] = [:]
    for facility in exitGroup {
      for candidate in facility.exitEdgeCandidates {
        guard let edge = edgesByID[candidate.edgeID] else { continue }
        let tail = candidate.distanceMeters + edge.lengthMeters
        if tail < targets[edge.fromNodeID, default: .infinity] {
          targets[edge.fromNodeID] = tail
        }
      }
    }
    guard !targets.isEmpty else { return nil }

    struct QueueValue: Comparable {
      let cost: Double
      let nodeID: Int64

      static func < (lhs: QueueValue, rhs: QueueValue) -> Bool {
        if lhs.cost != rhs.cost { return lhs.cost < rhs.cost }
        return lhs.nodeID < rhs.nodeID
      }
    }
    var distances: [Int64: Double] = [:]
    var queue = MinHeap<QueueValue>()
    for facility in entryGroup {
      for candidate in facility.entryEdgeCandidates {
        guard let edge = edgesByID[candidate.edgeID] else { continue }
        let cost = candidate.distanceMeters + edge.lengthMeters
        if cost < distances[edge.toNodeID, default: .infinity] {
          distances[edge.toNodeID] = cost
          queue.insert(QueueValue(cost: cost, nodeID: edge.toNodeID))
        }
      }
    }
    var best: Double?
    while let current = queue.removeMinimum() {
      guard current.cost == distances[current.nodeID] else { continue }
      if let bestSoFar = best, current.cost >= bestSoFar { break }
      if let tail = targets[current.nodeID] {
        let total = current.cost + tail
        if total < (best ?? .infinity) {
          best = total
        }
      }
      for edge in outgoingEdges[current.nodeID, default: []] {
        let candidate = current.cost + edge.lengthMeters
        if candidate < distances[edge.toNodeID, default: .infinity] {
          distances[edge.toNodeID] = candidate
          queue.insert(
            QueueValue(cost: candidate, nodeID: edge.toNodeID)
          )
        }
      }
    }
    return best
  }
}
