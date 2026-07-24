import Combine
import Foundation
import KaidoDomain
import KaidoPresentation

struct PreDriveTariffQuoteFixture: Equatable, Sendable {
  let id: String
  let entryFacilityID: String
  let exitFacilityID: String
  let vehicleClass: String
  let tariffVersionID: String
  let tariffVersionStatus: TariffVersionStatus
  let tariffDistanceKM: Double?
  let estimatedAmountYen: Int?
  let evidenceStatus: TollEvidenceStatus
  let checkedAt: String
  let officialQueryReference: String
}

struct PreDriveReviewFixture: Equatable, Sendable {
  let networkSnapshotID: String
  let routePlanID: String
  let entryFacilityID: String
  let exitFacilityID: String
  let passageEvidence: RoutePassageEvidence
  let tariffQuotes: [PreDriveTariffQuoteFixture]

  static let synthetic = PreDriveReviewFixture(
    networkSnapshotID: "preview.synthetic.snapshot-v1",
    routePlanID: "preview.synthetic.route-plan",
    entryFacilityID: "preview.synthetic.entrance.eastbound",
    exitFacilityID: "preview.synthetic.exit.eastbound",
    passageEvidence: .noKnownConflictRealtimeUnconfirmed,
    tariffQuotes: [
      PreDriveTariffQuoteFixture(
        id: "preview.synthetic.quote.active",
        entryFacilityID: "preview.synthetic.entrance.eastbound",
        exitFacilityID: "preview.synthetic.exit.eastbound",
        vehicleClass: "STANDARD",
        tariffVersionID: "preview.synthetic.tariff.active",
        tariffVersionStatus: .active,
        tariffDistanceKM: 6.7,
        estimatedAmountYen: 630,
        evidenceStatus: .estimated,
        checkedAt: "2026-07-24T00:00:00+09:00",
        officialQueryReference: "https://search.shutoko.jp/"
      ),
      PreDriveTariffQuoteFixture(
        id: "preview.synthetic.quote.proposed",
        entryFacilityID: "preview.synthetic.entrance.eastbound",
        exitFacilityID: "preview.synthetic.exit.eastbound",
        vehicleClass: "STANDARD",
        tariffVersionID: "preview.synthetic.tariff.proposed",
        tariffVersionStatus: .proposed,
        tariffDistanceKM: 6.7,
        estimatedAmountYen: 700,
        evidenceStatus: .estimated,
        checkedAt: "2026-07-24T00:00:00+09:00",
        officialQueryReference: "https://search.shutoko.jp/"
      ),
    ]
  )
}

enum PreDriveReviewModelError: Error, Equatable, Sendable {
  case routeIdentityMismatch
  case missingActualDistance
  case noUniqueActiveTariff
  case tariffRouteMismatch
  case invalidTariffEvidence
  case invalidProjection

  var code: String {
    switch self {
    case .routeIdentityMismatch:
      "PRE_DRIVE_ROUTE_IDENTITY_MISMATCH"
    case .missingActualDistance:
      "PRE_DRIVE_ACTUAL_DISTANCE_UNAVAILABLE"
    case .noUniqueActiveTariff:
      "PRE_DRIVE_NO_UNIQUE_ACTIVE_TARIFF"
    case .tariffRouteMismatch:
      "PRE_DRIVE_TARIFF_ROUTE_MISMATCH"
    case .invalidTariffEvidence:
      "PRE_DRIVE_INVALID_TARIFF_EVIDENCE"
    case .invalidProjection:
      "PRE_DRIVE_PROJECTION_FAILED"
    }
  }
}

struct PreDriveReviewSnapshot: Equatable, Sendable {
  let routePlanID: String
  let occurrenceCount: Int
  let presentation: PreDriveReviewPresentation
  let quoteID: String
  let vehicleClass: String
  let tariffVersionID: String
  let tariffVersionStatus: TariffVersionStatus
  let checkedAt: String
  let officialQueryReference: String
  let ignoredNonActiveQuoteIDs: [String]

  var navigationStartAllowed: Bool {
    false
  }
}

@MainActor
final class PreDriveReviewModel: ObservableObject {
  @Published private(set) var snapshot: PreDriveReviewSnapshot?
  @Published private(set) var lastErrorCode: String?
  @Published private(set) var hasCompiledRoutePlan = false

  let fixture: PreDriveReviewFixture

  private var routePlanSubscription: AnyCancellable?

  init(
    routeEditor: ParkedRouteEditorModel,
    fixture: PreDriveReviewFixture = .synthetic
  ) {
    self.fixture = fixture
    routePlanSubscription = routeEditor.$compiledRoutePlan.sink { [weak self] routePlan in
      self?.bind(routePlan: routePlan)
    }
  }

  func bind(routePlan: RoutePlan?) {
    hasCompiledRoutePlan = routePlan != nil
    guard let routePlan else {
      snapshot = nil
      lastErrorCode = nil
      return
    }
    do {
      snapshot = try makeSnapshot(routePlan: routePlan)
      lastErrorCode = nil
    } catch let error as PreDriveReviewModelError {
      snapshot = nil
      lastErrorCode = error.code
    } catch {
      snapshot = nil
      lastErrorCode = "UNKNOWN_PRE_DRIVE_REVIEW_ERROR"
    }
  }

  private func makeSnapshot(routePlan: RoutePlan) throws -> PreDriveReviewSnapshot {
    guard routePlan.id == fixture.routePlanID,
      routePlan.networkSnapshotID == fixture.networkSnapshotID,
      routePlan.entryFacilityID == fixture.entryFacilityID,
      routePlan.exitFacilityID == fixture.exitFacilityID
    else {
      throw PreDriveReviewModelError.routeIdentityMismatch
    }
    guard let actualDistanceKM = routePlan.actualDistanceKM,
      actualDistanceKM.isFinite, actualDistanceKM > 0
    else {
      throw PreDriveReviewModelError.missingActualDistance
    }
    guard Set(fixture.tariffQuotes.map(\.id)).count == fixture.tariffQuotes.count else {
      throw PreDriveReviewModelError.invalidTariffEvidence
    }

    let selection = TariffSelector.selectCurrent(
      from: fixture.tariffQuotes.map {
        TariffCandidate(
          quoteID: $0.id,
          tariffVersionID: $0.tariffVersionID,
          versionStatus: $0.tariffVersionStatus
        )
      }
    )
    guard selection.status == .selected,
      let selectedCandidate = selection.selectedCandidate,
      let quote = fixture.tariffQuotes.first(where: {
        $0.id == selectedCandidate.quoteID
          && $0.tariffVersionID == selectedCandidate.tariffVersionID
          && $0.tariffVersionStatus == selectedCandidate.versionStatus
      })
    else {
      throw PreDriveReviewModelError.noUniqueActiveTariff
    }
    guard quote.entryFacilityID == routePlan.entryFacilityID,
      quote.exitFacilityID == routePlan.exitFacilityID
    else {
      throw PreDriveReviewModelError.tariffRouteMismatch
    }
    guard !quote.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !quote.vehicleClass.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !quote.tariffVersionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      ISO8601DateFormatter().date(from: quote.checkedAt) != nil,
      let referenceURL = URL(string: quote.officialQueryReference),
      referenceURL.scheme == "https",
      referenceURL.host != nil
    else {
      throw PreDriveReviewModelError.invalidTariffEvidence
    }

    let presentation: PreDriveReviewPresentation
    do {
      presentation = try PreDriveReviewProjector.project(
        PreDriveReviewRequest(
          actualDistanceKM: actualDistanceKM,
          tariffDistanceKM: quote.tariffDistanceKM,
          estimatedAmountYen: quote.estimatedAmountYen,
          tollEvidenceStatus: quote.evidenceStatus,
          passageEvidence: fixture.passageEvidence
        )
      )
    } catch {
      throw PreDriveReviewModelError.invalidProjection
    }
    return PreDriveReviewSnapshot(
      routePlanID: routePlan.id,
      occurrenceCount: routePlan.occurrences.count,
      presentation: presentation,
      quoteID: quote.id,
      vehicleClass: quote.vehicleClass,
      tariffVersionID: quote.tariffVersionID,
      tariffVersionStatus: quote.tariffVersionStatus,
      checkedAt: quote.checkedAt,
      officialQueryReference: quote.officialQueryReference,
      ignoredNonActiveQuoteIDs: selection.ignoredNonActiveQuoteIDs
    )
  }
}
