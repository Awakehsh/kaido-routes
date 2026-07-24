import Foundation
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

@Test("Pre-drive evidence bundle resolves one exact fresh session profile")
func preDriveEvidenceBundleResolvesFreshExactProfile() throws {
  let manifest = preDriveEvidenceBundleManifest()
  let context = preDriveEvidenceBundleContext()
  let data = try PreDriveEvidenceBundleCodec.encode(
    manifest,
    context: context
  )
  let bundle = try PreDriveEvidenceBundleCodec.decode(
    data,
    context: context
  )
  let now = try #require(
    ISO8601DateFormatter().date(
      from: "2026-07-24T12:30:00+09:00"
    )
  )

  let evidence = try bundle.evidence(for: preDriveSession(), at: now)
  let repeatedData = try PreDriveEvidenceBundleCodec.encode(
    manifest,
    context: context
  )

  #expect(evidence == preDriveEvidence(quotes: [preDriveTariffQuote()]))
  #expect(bundle.manifest.releaseID == "test.pre-drive-evidence.v1")
  #expect(data == repeatedData)
}

@Test("Pre-drive evidence bundle fails closed outside its validity window")
func preDriveEvidenceBundleRejectsNotYetValidAndExpiredProfiles() throws {
  let bundle = try PreDriveEvidenceBundle(
    manifest: preDriveEvidenceBundleManifest(),
    context: preDriveEvidenceBundleContext()
  )
  let before = try #require(
    ISO8601DateFormatter().date(
      from: "2026-07-24T11:59:59+09:00"
    )
  )
  let beforeBundleRelease = try #require(
    ISO8601DateFormatter().date(
      from: "2026-07-24T12:10:00+09:00"
    )
  )
  let expiry = try #require(
    ISO8601DateFormatter().date(
      from: "2026-07-25T00:00:00+09:00"
    )
  )

  #expect(throws: PreDriveEvidenceResolutionError.notYetValid) {
    try bundle.evidence(for: preDriveSession(), at: before)
  }
  #expect(throws: PreDriveEvidenceResolutionError.notYetValid) {
    try bundle.evidence(
      for: preDriveSession(),
      at: beforeBundleRelease
    )
  }
  #expect(throws: PreDriveEvidenceResolutionError.expired) {
    try bundle.evidence(for: preDriveSession(), at: expiry)
  }
  #expect(throws: PreDriveEvidenceResolutionError.profileUnavailable) {
    try bundle.evidence(
      for: PreDriveReviewSession(
        networkSnapshotID: preDriveSession().networkSnapshotID,
        routePlanID: preDriveSession().routePlanID,
        vehicleClass: .standard,
        paymentMethod: .cash
      ),
      at: before
    )
  }
}

@Test("Pre-drive evidence bundle rejects identity, role, and profile drift")
func preDriveEvidenceBundleRejectsAuthorityDrift() {
  let valid = preDriveEvidenceBundleManifest()
  let duplicateRecord = PreDriveEvidenceRecord(
    id: "test.pre-drive-record.duplicate",
    validFrom: valid.records[0].validFrom,
    expiresAt: valid.records[0].expiresAt,
    sourceReferenceIDs: valid.records[0].sourceReferenceIDs,
    evidence: valid.records[0].evidence
  )
  let drifted = PreDriveEvidenceBundleManifest(
    releaseID: valid.releaseID,
    releasedAt: valid.releasedAt,
    evidenceScope: .releasedRoad,
    productReleaseID: "test.product.other",
    navigationReleaseID: valid.navigationReleaseID,
    networkSnapshotID: valid.networkSnapshotID,
    routePlanID: valid.routePlanID,
    sourceRegistry: valid.sourceRegistry,
    records: valid.records + [duplicateRecord]
  )

  do {
    _ = try PreDriveEvidenceBundle(
      manifest: drifted,
      context: preDriveEvidenceBundleContext()
    )
    Issue.record("Expected authority and duplicate-profile drift to fail")
  } catch PreDriveEvidenceBundleError.invalid(let issues) {
    #expect(issues.contains(.evidenceScopeMismatch))
    #expect(issues.contains(.productReleaseMismatch))
    #expect(
      issues.contains(
        .duplicateProfile(
          PreDriveEvidenceProfileKey(
            vehicleClass: .standard,
            paymentMethod: .etc
          )
        )
      )
    )
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Pre-drive evidence bundle requires reviewed tariff and passage sources")
func preDriveEvidenceBundleRequiresBothSourceRoles() {
  let valid = preDriveEvidenceBundleManifest()
  let missingPassageRole = PreDriveEvidenceBundleManifest(
    releaseID: valid.releaseID,
    releasedAt: valid.releasedAt,
    evidenceScope: valid.evidenceScope,
    productReleaseID: valid.productReleaseID,
    navigationReleaseID: valid.navigationReleaseID,
    networkSnapshotID: valid.networkSnapshotID,
    routePlanID: valid.routePlanID,
    sourceRegistry: [valid.sourceRegistry[0]],
    records: [
      PreDriveEvidenceRecord(
        id: valid.records[0].id,
        validFrom: valid.records[0].validFrom,
        expiresAt: valid.records[0].expiresAt,
        sourceReferenceIDs: [valid.sourceRegistry[0].id],
        evidence: valid.records[0].evidence
      )
    ]
  )

  do {
    _ = try PreDriveEvidenceBundle(
      manifest: missingPassageRole,
      context: preDriveEvidenceBundleContext()
    )
    Issue.record("Expected missing passage provenance to fail")
  } catch PreDriveEvidenceBundleError.invalid(let issues) {
    #expect(
      issues.contains(
        .missingSourceRole(
          "test.pre-drive-record.standard-etc",
          .passageReview
        )
      )
    )
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Pre-drive evidence bundle cannot predate its product release")
func preDriveEvidenceBundleCannotPredateProductRelease() {
  let context = PreDriveEvidenceBundleContext(
    productReleaseID: "test.product.pre-drive",
    productReleasedAt: "2026-07-24T12:30:00+09:00",
    navigationReleaseID: "test.navigation.pre-drive",
    routePlan: preDriveRoutePlan(),
    evidenceScope: .syntheticTestOnly
  )

  do {
    _ = try PreDriveEvidenceBundle(
      manifest: preDriveEvidenceBundleManifest(),
      context: context
    )
    Issue.record("Expected pre-product evidence release to fail")
  } catch PreDriveEvidenceBundleError.invalid(let issues) {
    #expect(issues.contains(.evidenceBeforeProductRelease))
  } catch {
    Issue.record("Unexpected error: \(error)")
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

private func preDriveEvidenceBundleContext() -> PreDriveEvidenceBundleContext {
  PreDriveEvidenceBundleContext(
    productReleaseID: "test.product.pre-drive",
    productReleasedAt: "2026-07-24T11:30:00+09:00",
    navigationReleaseID: "test.navigation.pre-drive",
    routePlan: preDriveRoutePlan(),
    evidenceScope: .syntheticTestOnly
  )
}

private func preDriveEvidenceBundleManifest()
  -> PreDriveEvidenceBundleManifest
{
  PreDriveEvidenceBundleManifest(
    releaseID: "test.pre-drive-evidence.v1",
    releasedAt: "2026-07-24T12:15:00+09:00",
    evidenceScope: .syntheticTestOnly,
    productReleaseID: "test.product.pre-drive",
    navigationReleaseID: "test.navigation.pre-drive",
    networkSnapshotID: "test.snapshot.pre-drive",
    routePlanID: "test.plan.pre-drive",
    sourceRegistry: [
      PreDriveEvidenceSourceReference(
        id: "test.pre-drive-source.tariff",
        roles: [.tariffQuery],
        authorityName: "Synthetic tariff authority",
        sourceURL: "https://example.com/tariff",
        contentSHA256:
          "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        checkedAt: "2026-07-24T09:00:00+09:00",
        reviewerID: "test.reviewer.tariff",
        reviewedAt: "2026-07-24T12:05:00+09:00"
      ),
      PreDriveEvidenceSourceReference(
        id: "test.pre-drive-source.passage",
        roles: [.passageReview],
        authorityName: "Synthetic passage authority",
        sourceURL: "https://example.com/passage",
        contentSHA256:
          "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        checkedAt: "2026-07-24T10:00:00+09:00",
        reviewerID: "test.reviewer.passage",
        reviewedAt: "2026-07-24T12:10:00+09:00"
      ),
    ],
    records: [
      PreDriveEvidenceRecord(
        id: "test.pre-drive-record.standard-etc",
        validFrom: "2026-07-24T12:00:00+09:00",
        expiresAt: "2026-07-25T00:00:00+09:00",
        sourceReferenceIDs: [
          "test.pre-drive-source.tariff",
          "test.pre-drive-source.passage",
        ],
        evidence: preDriveEvidence(quotes: [preDriveTariffQuote()])
      )
    ]
  )
}
