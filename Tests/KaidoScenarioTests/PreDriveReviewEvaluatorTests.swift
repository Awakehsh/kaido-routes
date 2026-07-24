import KaidoDomain
import KaidoPresentation
import Testing

@Test("Shuto tariff vehicle classes retain the official five-category order")
func shutoVehicleClassesRetainOfficialOrder() {
  #expect(
    ShutoVehicleClass.allCases.map(\.rawValue)
      == [
        "LIGHT_MOTORCYCLE",
        "STANDARD",
        "MEDIUM",
        "LARGE",
        "EXTRA_LARGE",
      ]
  )
  #expect(
    ShutoVehicleClass.allCases.map(\.officialJapaneseLabel)
      == ["軽・二輪", "普通車", "中型車", "大型車", "特大車"]
  )
}

@Test("Shuto payment methods remain independent from vehicle class")
func shutoPaymentMethodsRemainIndependent() {
  #expect(ShutoPaymentMethod.allCases.map(\.rawValue) == ["ETC", "CASH"])
  #expect(
    ShutoPaymentMethod.allCases.map(\.officialJapaneseLabel)
      == ["ETC", "現金"]
  )
}

@Test("Pre-drive review binds current tariff evidence to one exact route")
func preDriveReviewBindsExactRouteEvidence() throws {
  let routePlan = preDriveRoutePlan()
  let active = preDriveTariffQuote()
  let proposed = TariffQuote(
    id: "test.quote.proposed",
    entryFacilityID: routePlan.entryFacilityID,
    exitFacilityID: routePlan.exitFacilityID,
    vehicleClass: .standard,
    paymentMethod: .etc,
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
    session: preDriveSession(),
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
    vehicleClass: .standard,
    paymentMethod: .etc,
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
      session: preDriveSession(),
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
    vehicleClass: .lightMotorcycle,
    paymentMethod: .etc,
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
      session: preDriveSession(),
      evidence: preDriveEvidence(
        quotes: [preDriveTariffQuote(), mismatchedProposed]
      )
    )
  }
}

@Test("Pre-drive review rejects evidence that drifts from the selected session class")
func preDriveReviewRejectsProviderVehicleClassDrift() {
  let evidence = preDriveEvidence(
    vehicleClass: .lightMotorcycle,
    quotes: [
      preDriveTariffQuote(vehicleClass: .lightMotorcycle)
    ]
  )

  #expect(
    throws: PreDriveReviewEvaluationError.sessionVehicleClassMismatch
  ) {
    try PreDriveReviewEvaluator.evaluate(
      routePlan: preDriveRoutePlan(),
      session: preDriveSession(),
      evidence: evidence
    )
  }
}

@Test("Pre-drive review rejects positive live passage without authority")
func preDriveReviewRejectsUnauthorizedRealtimePassage() {
  let evidence = PreDriveReviewEvidence(
    evaluatedAt: "2026-07-24T12:00:00+09:00",
    networkSnapshotID: "test.snapshot.pre-drive",
    routePlanID: "test.plan.pre-drive",
    vehicleClass: .standard,
    paymentMethod: .etc,
    passageEvidence: .realtimeConfirmedPassable,
    tariffQuotes: [preDriveTariffQuote()]
  )

  #expect(
    throws: PreDriveReviewEvaluationError.realtimePassageAuthorityUnavailable
  ) {
    try PreDriveReviewEvaluator.evaluate(
      routePlan: preDriveRoutePlan(),
      session: preDriveSession(),
      evidence: evidence
    )
  }
}

@Test("Pre-drive review rejects evidence that drifts from the selected payment path")
func preDriveReviewRejectsProviderPaymentMethodDrift() {
  let evidence = preDriveEvidence(
    paymentMethod: .cash,
    quotes: [
      preDriveTariffQuote(paymentMethod: .cash)
    ]
  )

  #expect(
    throws: PreDriveReviewEvaluationError.sessionPaymentMethodMismatch
  ) {
    try PreDriveReviewEvaluator.evaluate(
      routePlan: preDriveRoutePlan(),
      session: preDriveSession(),
      evidence: evidence
    )
  }
}

@Test("Pre-drive review rejects a mixed payment-method quote")
func preDriveReviewRejectsMixedPaymentMethodQuote() {
  #expect(
    throws: PreDriveReviewEvaluationError.tariffPaymentMethodMismatch
  ) {
    try PreDriveReviewEvaluator.evaluate(
      routePlan: preDriveRoutePlan(),
      session: preDriveSession(),
      evidence: preDriveEvidence(
        quotes: [
          preDriveTariffQuote(),
          preDriveTariffQuote(
            id: "test.quote.cash.proposed",
            paymentMethod: .cash,
            tariffVersionStatus: .proposed
          ),
        ]
      )
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

private func preDriveSession() -> PreDriveReviewSession {
  PreDriveReviewSession(
    networkSnapshotID: "test.snapshot.pre-drive",
    routePlanID: "test.plan.pre-drive",
    vehicleClass: .standard,
    paymentMethod: .etc
  )
}

private func preDriveTariffQuote(
  id: String = "test.quote.active",
  vehicleClass: ShutoVehicleClass = .standard,
  paymentMethod: ShutoPaymentMethod = .etc,
  tariffVersionStatus: TariffVersionStatus = .active
) -> TariffQuote {
  TariffQuote(
    id: id,
    entryFacilityID: "test.entrance",
    exitFacilityID: "test.exit",
    vehicleClass: vehicleClass,
    paymentMethod: paymentMethod,
    tariffVersionID: "test.tariff.\(tariffVersionStatus.rawValue.lowercased())",
    tariffVersionStatus: tariffVersionStatus,
    tariffDistanceKM: 6.7,
    estimatedAmountYen: 630,
    evidenceStatus: .estimated,
    checkedAt: "2026-07-24T09:00:00+09:00",
    officialQueryReference: "https://example.com/tariff/active"
  )
}

private func preDriveEvidence(
  vehicleClass: ShutoVehicleClass = .standard,
  paymentMethod: ShutoPaymentMethod = .etc,
  quotes: [TariffQuote]
) -> PreDriveReviewEvidence {
  PreDriveReviewEvidence(
    evaluatedAt: "2026-07-24T12:00:00+09:00",
    networkSnapshotID: "test.snapshot.pre-drive",
    routePlanID: "test.plan.pre-drive",
    vehicleClass: vehicleClass,
    paymentMethod: paymentMethod,
    passageEvidence: .noKnownConflictRealtimeUnconfirmed,
    tariffQuotes: quotes
  )
}
