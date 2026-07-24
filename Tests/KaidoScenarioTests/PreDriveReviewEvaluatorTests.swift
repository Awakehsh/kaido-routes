import KaidoDomain
import KaidoPresentation
import Testing

@Test("Pre-drive review binds current tariff evidence to one exact route")
func preDriveReviewBindsExactRouteEvidence() throws {
  let routePlan = preDriveRoutePlan()
  let active = preDriveTariffQuote()
  let proposed = TariffQuote(
    id: "test.quote.proposed",
    entryFacilityID: routePlan.entryFacilityID,
    exitFacilityID: routePlan.exitFacilityID,
    vehicleClass: "STANDARD",
    tariffVersionID: "test.tariff.proposed",
    tariffVersionStatus: .proposed,
    tariffDistanceKM: 6.7,
    estimatedAmountYen: 700,
    evidenceStatus: .estimated,
    checkedAt: "2026-07-24T09:00:00+09:00",
    officialQueryReference: "https://example.com/tariff/proposed"
  )

  let result = try PreDriveReviewEvaluator.evaluate(
    routePlan: routePlan,
    evidence: preDriveEvidence(quotes: [proposed, active])
  )

  #expect(result.selectedTariffQuote == active)
  #expect(result.ignoredNonActiveQuoteIDs == [proposed.id])
  #expect(result.presentation.actualDistanceKM == 27.4)
  #expect(result.presentation.tariffDistanceKM == 6.7)
  #expect(result.presentation.passage.tone == .unconfirmed)
  #expect(!result.presentation.passage.usesPositiveOpenColor)
}

@Test("Pre-drive review validates every quote, including non-active evidence")
func preDriveReviewRejectsInvalidNonActiveEvidence() {
  let routePlan = preDriveRoutePlan()
  let invalidProposed = TariffQuote(
    id: "test.quote.proposed",
    entryFacilityID: routePlan.entryFacilityID,
    exitFacilityID: routePlan.exitFacilityID,
    vehicleClass: "STANDARD",
    tariffVersionID: "test.tariff.proposed",
    tariffVersionStatus: .proposed,
    tariffDistanceKM: 6.7,
    estimatedAmountYen: 700,
    evidenceStatus: .estimated,
    checkedAt: "2026-07-24T13:00:00+09:00",
    officialQueryReference: "https://example.com/tariff/proposed"
  )

  #expect(throws: PreDriveReviewEvaluationError.invalidTariffEvidence) {
    try PreDriveReviewEvaluator.evaluate(
      routePlan: routePlan,
      evidence: preDriveEvidence(
        quotes: [preDriveTariffQuote(), invalidProposed]
      )
    )
  }
}

@Test("Pre-drive review rejects every tariff quote for another vehicle class")
func preDriveReviewRejectsVehicleClassDrift() {
  let routePlan = preDriveRoutePlan()
  let mismatchedProposed = TariffQuote(
    id: "test.quote.proposed.other-vehicle",
    entryFacilityID: routePlan.entryFacilityID,
    exitFacilityID: routePlan.exitFacilityID,
    vehicleClass: "LIGHT",
    tariffVersionID: "test.tariff.proposed",
    tariffVersionStatus: .proposed,
    tariffDistanceKM: 6.7,
    estimatedAmountYen: 580,
    evidenceStatus: .estimated,
    checkedAt: "2026-07-24T09:00:00+09:00",
    officialQueryReference: "https://example.com/tariff/proposed"
  )

  #expect(
    throws: PreDriveReviewEvaluationError.tariffVehicleClassMismatch
  ) {
    try PreDriveReviewEvaluator.evaluate(
      routePlan: routePlan,
      evidence: preDriveEvidence(
        quotes: [preDriveTariffQuote(), mismatchedProposed]
      )
    )
  }
}

@Test("Pre-drive review rejects positive live passage without authority")
func preDriveReviewRejectsUnauthorizedRealtimePassage() {
  let evidence = PreDriveReviewEvidence(
    evaluatedAt: "2026-07-24T12:00:00+09:00",
    networkSnapshotID: "test.snapshot.pre-drive",
    routePlanID: "test.plan.pre-drive",
    vehicleClass: "STANDARD",
    passageEvidence: .realtimeConfirmedPassable,
    tariffQuotes: [preDriveTariffQuote()]
  )

  #expect(
    throws: PreDriveReviewEvaluationError.realtimePassageAuthorityUnavailable
  ) {
    try PreDriveReviewEvaluator.evaluate(
      routePlan: preDriveRoutePlan(),
      evidence: evidence
    )
  }
}

private func preDriveRoutePlan() -> RoutePlan {
  RoutePlan(
    id: "test.plan.pre-drive",
    networkSnapshotID: "test.snapshot.pre-drive",
    entryFacilityID: "test.entrance",
    exitFacilityID: "test.exit",
    recoveryPolicy: .strict,
    actualDistanceKM: 27.4,
    occurrences: [
      RouteOccurrence(
        id: "test.occurrence.pre-drive",
        index: 0,
        kind: .edge,
        entityID: "test.edge.pre-drive"
      )
    ]
  )
}

private func preDriveTariffQuote() -> TariffQuote {
  TariffQuote(
    id: "test.quote.active",
    entryFacilityID: "test.entrance",
    exitFacilityID: "test.exit",
    vehicleClass: "STANDARD",
    tariffVersionID: "test.tariff.active",
    tariffVersionStatus: .active,
    tariffDistanceKM: 6.7,
    estimatedAmountYen: 630,
    evidenceStatus: .estimated,
    checkedAt: "2026-07-24T09:00:00+09:00",
    officialQueryReference: "https://example.com/tariff/active"
  )
}

private func preDriveEvidence(
  quotes: [TariffQuote]
) -> PreDriveReviewEvidence {
  PreDriveReviewEvidence(
    evaluatedAt: "2026-07-24T12:00:00+09:00",
    networkSnapshotID: "test.snapshot.pre-drive",
    routePlanID: "test.plan.pre-drive",
    vehicleClass: "STANDARD",
    passageEvidence: .noKnownConflictRealtimeUnconfirmed,
    tariffQuotes: quotes
  )
}
