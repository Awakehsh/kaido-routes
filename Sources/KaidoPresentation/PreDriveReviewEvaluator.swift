import Foundation
import KaidoDomain

/// Dated evidence evaluated immediately before a drive. This is intentionally
/// not part of a versioned product release because tariff and passage evidence
/// have independent freshness and authority.
public struct PreDriveReviewEvidence: Equatable, Sendable {
  public let evaluatedAt: String
  public let networkSnapshotID: String
  public let routePlanID: String
  public let vehicleClass: String
  public let passageEvidence: RoutePassageEvidence
  public let tariffQuotes: [TariffQuote]

  public init(
    evaluatedAt: String,
    networkSnapshotID: String,
    routePlanID: String,
    vehicleClass: String,
    passageEvidence: RoutePassageEvidence,
    tariffQuotes: [TariffQuote]
  ) {
    self.evaluatedAt = evaluatedAt
    self.networkSnapshotID = networkSnapshotID
    self.routePlanID = routePlanID
    self.vehicleClass = vehicleClass
    self.passageEvidence = passageEvidence
    self.tariffQuotes = tariffQuotes
  }
}

public struct PreDriveReviewEvaluation: Equatable, Sendable {
  public let presentation: PreDriveReviewPresentation
  public let selectedTariffQuote: TariffQuote
  public let ignoredNonActiveQuoteIDs: [String]

  public init(
    presentation: PreDriveReviewPresentation,
    selectedTariffQuote: TariffQuote,
    ignoredNonActiveQuoteIDs: [String]
  ) {
    self.presentation = presentation
    self.selectedTariffQuote = selectedTariffQuote
    self.ignoredNonActiveQuoteIDs = ignoredNonActiveQuoteIDs
  }
}

public enum PreDriveReviewEvaluationError: Error, Equatable, Sendable {
  case routeIdentityMismatch
  case actualDistanceUnavailable
  case invalidTariffEvidence
  case noUniqueActiveTariff
  case tariffRouteMismatch
  case tariffVehicleClassMismatch
  case realtimePassageAuthorityUnavailable
  case projectionFailed

  public var code: String {
    switch self {
    case .routeIdentityMismatch:
      "PRE_DRIVE_ROUTE_IDENTITY_MISMATCH"
    case .actualDistanceUnavailable:
      "PRE_DRIVE_ACTUAL_DISTANCE_UNAVAILABLE"
    case .invalidTariffEvidence:
      "PRE_DRIVE_INVALID_TARIFF_EVIDENCE"
    case .noUniqueActiveTariff:
      "PRE_DRIVE_NO_UNIQUE_ACTIVE_TARIFF"
    case .tariffRouteMismatch:
      "PRE_DRIVE_TARIFF_ROUTE_MISMATCH"
    case .tariffVehicleClassMismatch:
      "PRE_DRIVE_TARIFF_VEHICLE_CLASS_MISMATCH"
    case .realtimePassageAuthorityUnavailable:
      "PRE_DRIVE_REALTIME_PASSAGE_AUTHORITY_UNAVAILABLE"
    case .projectionFailed:
      "PRE_DRIVE_PROJECTION_FAILED"
    }
  }
}

public enum PreDriveReviewEvaluator {
  public static func evaluate(
    routePlan: RoutePlan,
    evidence: PreDriveReviewEvidence
  ) throws -> PreDriveReviewEvaluation {
    guard routePlan.id == evidence.routePlanID,
      routePlan.networkSnapshotID == evidence.networkSnapshotID
    else {
      throw PreDriveReviewEvaluationError.routeIdentityMismatch
    }
    guard let actualDistanceKM = routePlan.actualDistanceKM,
      actualDistanceKM.isFinite,
      actualDistanceKM > 0
    else {
      throw PreDriveReviewEvaluationError.actualDistanceUnavailable
    }
    guard let evaluatedAt = parseISO8601(evidence.evaluatedAt) else {
      throw PreDriveReviewEvaluationError.invalidTariffEvidence
    }
    guard !normalized(evidence.vehicleClass).isEmpty else {
      throw PreDriveReviewEvaluationError.invalidTariffEvidence
    }
    guard evidence.passageEvidence != .realtimeConfirmedPassable else {
      throw PreDriveReviewEvaluationError.realtimePassageAuthorityUnavailable
    }

    let quoteIDs = evidence.tariffQuotes.map(\.id)
    guard !quoteIDs.isEmpty, Set(quoteIDs).count == quoteIDs.count else {
      throw PreDriveReviewEvaluationError.invalidTariffEvidence
    }
    for quote in evidence.tariffQuotes {
      try validate(
        quote: quote,
        for: routePlan,
        vehicleClass: evidence.vehicleClass,
        evaluatedAt: evaluatedAt
      )
    }

    let selection = TariffSelector.selectCurrent(
      from: evidence.tariffQuotes.map {
        TariffCandidate(
          quoteID: $0.id,
          tariffVersionID: $0.tariffVersionID,
          versionStatus: $0.tariffVersionStatus
        )
      }
    )
    guard selection.status == .selected,
      let selected = selection.selectedCandidate,
      let quote = evidence.tariffQuotes.first(where: {
        $0.id == selected.quoteID
          && $0.tariffVersionID == selected.tariffVersionID
          && $0.tariffVersionStatus == selected.versionStatus
      })
    else {
      throw PreDriveReviewEvaluationError.noUniqueActiveTariff
    }

    let presentation: PreDriveReviewPresentation
    do {
      presentation = try PreDriveReviewProjector.project(
        PreDriveReviewRequest(
          actualDistanceKM: actualDistanceKM,
          tariffDistanceKM: quote.tariffDistanceKM,
          estimatedAmountYen: quote.estimatedAmountYen,
          tollEvidenceStatus: quote.evidenceStatus,
          passageEvidence: evidence.passageEvidence
        )
      )
    } catch {
      throw PreDriveReviewEvaluationError.projectionFailed
    }
    return PreDriveReviewEvaluation(
      presentation: presentation,
      selectedTariffQuote: quote,
      ignoredNonActiveQuoteIDs: selection.ignoredNonActiveQuoteIDs
    )
  }

  private static func validate(
    quote: TariffQuote,
    for routePlan: RoutePlan,
    vehicleClass: String,
    evaluatedAt: Date
  ) throws {
    guard !normalized(quote.id).isEmpty,
      !normalized(quote.entryFacilityID).isEmpty,
      !normalized(quote.exitFacilityID).isEmpty,
      !normalized(quote.vehicleClass).isEmpty,
      !normalized(quote.tariffVersionID).isEmpty,
      let checkedAt = parseISO8601(quote.checkedAt),
      checkedAt <= evaluatedAt,
      let sourceURL = URL(string: quote.officialQueryReference),
      sourceURL.scheme?.lowercased() == "https",
      sourceURL.host != nil
    else {
      throw PreDriveReviewEvaluationError.invalidTariffEvidence
    }
    guard quote.entryFacilityID == routePlan.entryFacilityID,
      quote.exitFacilityID == routePlan.exitFacilityID
    else {
      throw PreDriveReviewEvaluationError.tariffRouteMismatch
    }
    guard quote.vehicleClass == vehicleClass else {
      throw PreDriveReviewEvaluationError.tariffVehicleClassMismatch
    }
    if let distance = quote.tariffDistanceKM,
      !distance.isFinite || distance < 0
    {
      throw PreDriveReviewEvaluationError.invalidTariffEvidence
    }
    if let amount = quote.estimatedAmountYen, amount < 0 {
      throw PreDriveReviewEvaluationError.invalidTariffEvidence
    }
    if quote.evidenceStatus != .unknown,
      quote.tariffDistanceKM == nil || quote.estimatedAmountYen == nil
    {
      throw PreDriveReviewEvaluationError.invalidTariffEvidence
    }
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func parseISO8601(_ value: String) -> Date? {
    let standard = ISO8601DateFormatter()
    if let date = standard.date(from: value) {
      return date
    }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value)
  }
}
