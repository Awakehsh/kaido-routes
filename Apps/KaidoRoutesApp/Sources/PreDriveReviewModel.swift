import Combine
import Foundation
import KaidoDomain
import KaidoPresentation

typealias PreDriveTariffQuoteFixture = TariffQuote
typealias PreDriveReviewFixture = PreDriveReviewEvidence

extension PreDriveReviewEvidence {
  static let synthetic = PreDriveReviewEvidence(
    evaluatedAt: "2026-07-24T12:00:00+09:00",
    networkSnapshotID: "preview.synthetic.snapshot-v1",
    routePlanID: "preview.synthetic.route-plan",
    vehicleClass: "STANDARD",
    passageEvidence: .noKnownConflictRealtimeUnconfirmed,
    tariffQuotes: [
      TariffQuote(
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
      TariffQuote(
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

  init(
    routePlan: RoutePlan,
    evaluation: PreDriveReviewEvaluation
  ) {
    let quote = evaluation.selectedTariffQuote
    routePlanID = routePlan.id
    occurrenceCount = routePlan.occurrences.count
    presentation = evaluation.presentation
    quoteID = quote.id
    vehicleClass = quote.vehicleClass
    tariffVersionID = quote.tariffVersionID
    tariffVersionStatus = quote.tariffVersionStatus
    checkedAt = quote.checkedAt
    officialQueryReference = quote.officialQueryReference
    ignoredNonActiveQuoteIDs = evaluation.ignoredNonActiveQuoteIDs
  }

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
    } catch let error as PreDriveReviewEvaluationError {
      snapshot = nil
      lastErrorCode = error.code
    } catch {
      snapshot = nil
      lastErrorCode = "UNKNOWN_PRE_DRIVE_REVIEW_ERROR"
    }
  }

  private func makeSnapshot(routePlan: RoutePlan) throws -> PreDriveReviewSnapshot {
    let evaluation = try PreDriveReviewEvaluator.evaluate(
      routePlan: routePlan,
      evidence: fixture
    )
    return PreDriveReviewSnapshot(
      routePlan: routePlan,
      evaluation: evaluation
    )
  }
}
