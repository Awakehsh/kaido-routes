import Foundation

/// Current Shuto Expressway tariff vehicle classes.
///
/// These stable IDs map to the operator's five Japanese categories. Payment
/// method, including ETC, is deliberately not part of vehicle-class identity.
public enum ShutoVehicleClass: String, Codable, CaseIterable, Equatable, Sendable {
  case lightMotorcycle = "LIGHT_MOTORCYCLE"
  case standard = "STANDARD"
  case medium = "MEDIUM"
  case large = "LARGE"
  case extraLarge = "EXTRA_LARGE"

  public var officialJapaneseLabel: String {
    switch self {
    case .lightMotorcycle:
      "軽・二輪"
    case .standard:
      "普通車"
    case .medium:
      "中型車"
    case .large:
      "大型車"
    case .extraLarge:
      "特大車"
    }
  }
}

/// The operator's two tariff paths used by the current product scope.
///
/// Selecting a method does not prove that a directional entrance accepts it;
/// route-specific evidence must still establish that independently.
public enum ShutoPaymentMethod: String, Codable, CaseIterable, Equatable, Sendable {
  case etc = "ETC"
  case cash = "CASH"

  public var officialJapaneseLabel: String {
    switch self {
    case .etc:
      "ETC"
    case .cash:
      "現金"
    }
  }
}

public enum TariffVersionStatus: String, Codable, Equatable, Sendable {
  case active = "ACTIVE"
  case proposed = "PROPOSED"
  case retired = "RETIRED"
}

public enum TollEvidenceStatus: String, Codable, Equatable, Sendable {
  case verifiedQuery = "VERIFIED_QUERY"
  case estimated = "ESTIMATED"
  case unknown = "UNKNOWN"
}

/// One dated tariff result. It remains session evidence and is deliberately
/// separate from a versioned RoutePlan or product release.
public struct TariffQuote: Codable, Equatable, Sendable {
  public let id: String
  public let entryFacilityID: String
  public let exitFacilityID: String
  public let vehicleClass: ShutoVehicleClass
  public let paymentMethod: ShutoPaymentMethod
  public let tariffVersionID: String
  public let tariffVersionStatus: TariffVersionStatus
  public let tariffDistanceKM: Double?
  public let estimatedAmountYen: Int?
  public let evidenceStatus: TollEvidenceStatus
  public let checkedAt: String
  public let officialQueryReference: String

  public init(
    id: String,
    entryFacilityID: String,
    exitFacilityID: String,
    vehicleClass: ShutoVehicleClass,
    paymentMethod: ShutoPaymentMethod,
    tariffVersionID: String,
    tariffVersionStatus: TariffVersionStatus,
    tariffDistanceKM: Double?,
    estimatedAmountYen: Int?,
    evidenceStatus: TollEvidenceStatus,
    checkedAt: String,
    officialQueryReference: String
  ) {
    self.id = id
    self.entryFacilityID = entryFacilityID
    self.exitFacilityID = exitFacilityID
    self.vehicleClass = vehicleClass
    self.paymentMethod = paymentMethod
    self.tariffVersionID = tariffVersionID
    self.tariffVersionStatus = tariffVersionStatus
    self.tariffDistanceKM = tariffDistanceKM
    self.estimatedAmountYen = estimatedAmountYen
    self.evidenceStatus = evidenceStatus
    self.checkedAt = checkedAt
    self.officialQueryReference = officialQueryReference
  }

  private enum CodingKeys: String, CodingKey {
    case id = "quote_id"
    case entryFacilityID = "entry_facility_id"
    case exitFacilityID = "exit_facility_id"
    case vehicleClass = "vehicle_class"
    case paymentMethod = "payment_method"
    case tariffVersionID = "tariff_version_id"
    case tariffVersionStatus = "tariff_version_status"
    case tariffDistanceKM = "tariff_distance_km"
    case estimatedAmountYen = "estimated_amount_yen"
    case evidenceStatus = "status"
    case checkedAt = "checked_at"
    case officialQueryReference = "official_query_reference"
  }
}

public struct TariffCandidate: Equatable, Sendable {
  public let quoteID: String
  public let tariffVersionID: String
  public let versionStatus: TariffVersionStatus

  public init(
    quoteID: String,
    tariffVersionID: String,
    versionStatus: TariffVersionStatus
  ) {
    self.quoteID = quoteID
    self.tariffVersionID = tariffVersionID
    self.versionStatus = versionStatus
  }
}

public struct TariffSelectionResult: Equatable, Sendable {
  public enum Status: String, Sendable {
    case selected = "SELECTED"
    case rejected = "REJECTED"
  }

  public let status: Status
  public let selectedCandidate: TariffCandidate?
  public let ignoredNonActiveQuoteIDs: [String]
  public let errorCodes: [String]

  public init(
    status: Status,
    selectedCandidate: TariffCandidate? = nil,
    ignoredNonActiveQuoteIDs: [String] = [],
    errorCodes: [String] = []
  ) {
    self.status = status
    self.selectedCandidate = selectedCandidate
    self.ignoredNonActiveQuoteIDs = ignoredNonActiveQuoteIDs
    self.errorCodes = errorCodes
  }
}

public enum TariffSelector {
  public static func selectCurrent(
    from candidates: [TariffCandidate]
  ) -> TariffSelectionResult {
    let active = candidates.filter { $0.versionStatus == .active }
    let ignored = candidates.filter { $0.versionStatus != .active }.map(\.quoteID)

    guard active.count == 1, let selected = active.first else {
      return TariffSelectionResult(
        status: .rejected,
        ignoredNonActiveQuoteIDs: ignored,
        errorCodes: ["NO_UNIQUE_ACTIVE_TARIFF"]
      )
    }
    return TariffSelectionResult(
      status: .selected,
      selectedCandidate: selected,
      ignoredNonActiveQuoteIDs: ignored
    )
  }
}
