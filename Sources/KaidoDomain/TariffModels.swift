import Foundation

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
  public let vehicleClass: String
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
    vehicleClass: String,
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
