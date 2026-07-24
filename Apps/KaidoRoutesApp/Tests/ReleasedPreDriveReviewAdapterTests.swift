import KaidoDomain
import KaidoPresentation
import XCTest

@testable import KaidoRoutesApp

final class ReleasedPreDriveReviewAdapterTests: XCTestCase {
  func testAdapterBindsSessionEvidenceToExactJointRelease() throws {
    let entry = try bundledProductEntry()
    let routePlan = entry.release.navigation.bundle.routePlan
    let adapter = try ReleasedPreDriveReviewAdapter(
      productRelease: entry.release,
      evidence: releasedPreDriveEvidence(routePlan: routePlan)
    )

    XCTAssertEqual(adapter.productReleaseID, entry.release.releaseID)
    XCTAssertEqual(
      adapter.navigationReleaseID,
      entry.release.navigation.releaseID
    )
    XCTAssertEqual(adapter.routePlanID, routePlan.id)
    XCTAssertEqual(
      adapter.evaluation.presentation.actualDistanceKM,
      routePlan.actualDistanceKM
    )
    XCTAssertEqual(
      adapter.evaluation.selectedTariffQuote.id,
      "preview.synthetic.quote.active"
    )
    XCTAssertEqual(adapter.evaluation.presentation.passage.tone, .unconfirmed)
    XCTAssertFalse(
      adapter.evaluation.presentation.passage.usesPositiveOpenColor
    )
  }

  func testAdapterRejectsRouteIdentityDrift() throws {
    let entry = try bundledProductEntry()
    let routePlan = entry.release.navigation.bundle.routePlan
    let evidence = PreDriveReviewEvidence(
      evaluatedAt: "2026-07-24T12:00:00+09:00",
      networkSnapshotID: routePlan.networkSnapshotID,
      routePlanID: "preview.synthetic.route-plan.drift",
      passageEvidence: .noKnownConflictRealtimeUnconfirmed,
      tariffQuotes: [releasedTariffQuote(routePlan: routePlan)]
    )

    XCTAssertThrowsError(
      try ReleasedPreDriveReviewAdapter(
        productRelease: entry.release,
        evidence: evidence
      )
    ) {
      XCTAssertEqual(
        $0 as? PreDriveReviewEvaluationError,
        .routeIdentityMismatch
      )
    }
  }

  func testAdapterRejectsPositiveRealtimeStateWithoutAuthority() throws {
    let entry = try bundledProductEntry()
    let routePlan = entry.release.navigation.bundle.routePlan
    let evidence = PreDriveReviewEvidence(
      evaluatedAt: "2026-07-24T12:00:00+09:00",
      networkSnapshotID: routePlan.networkSnapshotID,
      routePlanID: routePlan.id,
      passageEvidence: .realtimeConfirmedPassable,
      tariffQuotes: [releasedTariffQuote(routePlan: routePlan)]
    )

    XCTAssertThrowsError(
      try ReleasedPreDriveReviewAdapter(
        productRelease: entry.release,
        evidence: evidence
      )
    ) {
      XCTAssertEqual(
        $0 as? PreDriveReviewEvaluationError,
        .realtimePassageAuthorityUnavailable
      )
    }
  }

  private func bundledProductEntry() throws -> BundledProductReleaseEntry {
    try XCTUnwrap(
      BundledProductReleaseCatalogLoader.bundledPreview().demoEntries.first
    )
  }

  private func releasedPreDriveEvidence(
    routePlan: RoutePlan
  ) -> PreDriveReviewEvidence {
    PreDriveReviewEvidence(
      evaluatedAt: "2026-07-24T12:00:00+09:00",
      networkSnapshotID: routePlan.networkSnapshotID,
      routePlanID: routePlan.id,
      passageEvidence: .noKnownConflictRealtimeUnconfirmed,
      tariffQuotes: [releasedTariffQuote(routePlan: routePlan)]
    )
  }

  private func releasedTariffQuote(routePlan: RoutePlan) -> TariffQuote {
    TariffQuote(
      id: "preview.synthetic.quote.active",
      entryFacilityID: routePlan.entryFacilityID,
      exitFacilityID: routePlan.exitFacilityID,
      vehicleClass: "STANDARD",
      tariffVersionID: "preview.synthetic.tariff.active",
      tariffVersionStatus: .active,
      tariffDistanceKM: 6.7,
      estimatedAmountYen: 630,
      evidenceStatus: .estimated,
      checkedAt: "2026-07-24T09:00:00+09:00",
      officialQueryReference: "https://example.com/tariff/active"
    )
  }
}
