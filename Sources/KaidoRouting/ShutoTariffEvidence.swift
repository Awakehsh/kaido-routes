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
    checkedAt: String
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
  }

  /// Normal car, ETC. Checked on the operator ETC fee page; the announced
  /// 2026-10-01 revision remains PROPOSED and is intentionally not encoded.
  public static let etcNormalCarActive = ShutoTariffEvidence(
    tariffID: "shutoko.tariff.etc.normal-car.active",
    status: "ACTIVE",
    vehicleClassJA: "普通車",
    paymentJA: "ETC",
    minimumYen: 300,
    maximumYen: 1_950,
    yenPerKilometer: 29.52,
    fixedYen: 150,
    consumptionTaxRate: 0.10,
    sourceURL: "https://www.shutoko.jp/fee/fee-info/pay_etc/",
    checkedAt: "2026-08-03"
  )

  /// Pre-tax-rounding amount for a tariff distance; callers decide banding.
  func rawYen(forTariffDistanceMeters meters: Double) -> Double {
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
  /// The tariff distance is the operator's fare kilometrage between the two
  /// toll points — a network distance independent of both the driven route
  /// and the carriageway direction. The classic Shinjuku-to-Yoyogi pairing
  /// is about one fare kilometer even though the drivable path runs to
  /// Miyakezaka and back, so this uses the undirected shortest path over
  /// the snapshot as the approximation.
  public func tariffBand(
    entryFacilityID: String,
    exitFacilityID: String,
    evidence: ShutoTariffEvidence
  ) throws -> ShutoTariffBand {
    guard
      let distance = undirectedFareDistanceMeters(
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

  /// Undirected shortest network distance between two facilities' toll
  /// boundaries, seeded and terminated at their actual entry/exit edge
  /// candidates.
  private func undirectedFareDistanceMeters(
    entryFacilityID: String,
    exitFacilityID: String
  ) -> Double? {
    guard let entry = facilitiesByID[entryFacilityID],
      let exit = facilitiesByID[exitFacilityID]
    else { return nil }

    var neighbors: [Int64: [(node: Int64, meters: Double)]] = [:]
    for edge in database.edges {
      neighbors[edge.fromNodeID, default: []].append(
        (edge.toNodeID, edge.lengthMeters)
      )
      neighbors[edge.toNodeID, default: []].append(
        (edge.fromNodeID, edge.lengthMeters)
      )
    }

    var targets: [Int64: Double] = [:]
    for candidate in exit.exitEdgeCandidates {
      guard let edge = edgesByID[candidate.edgeID] else { continue }
      for node in [edge.fromNodeID, edge.toNodeID] {
        let offset = candidate.distanceMeters
        if offset < targets[node, default: .infinity] {
          targets[node] = offset
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
    for candidate in entry.entryEdgeCandidates {
      guard let edge = edgesByID[candidate.edgeID] else { continue }
      for node in [edge.fromNodeID, edge.toNodeID] {
        let offset = candidate.distanceMeters
        if offset < distances[node, default: .infinity] {
          distances[node] = offset
          queue.insert(QueueValue(cost: offset, nodeID: node))
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
      for neighbor in neighbors[current.nodeID, default: []] {
        let candidate = current.cost + neighbor.meters
        if candidate < distances[neighbor.node, default: .infinity] {
          distances[neighbor.node] = candidate
          queue.insert(
            QueueValue(cost: candidate, nodeID: neighbor.node)
          )
        }
      }
    }
    return best
  }
}
