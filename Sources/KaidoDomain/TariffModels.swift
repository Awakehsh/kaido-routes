import Foundation

public enum TariffVersionStatus: String, Codable, Equatable, Sendable {
  case active = "ACTIVE"
  case proposed = "PROPOSED"
  case retired = "RETIRED"
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
