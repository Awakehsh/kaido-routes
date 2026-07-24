import Foundation
import KaidoAppleAdapters
import KaidoNavigation
import KaidoPresentation
import Testing

@Test("Pre-drive evidence author derives every product-owned identity")
func preDriveEvidenceAuthorDerivesProductIdentity() throws {
  let release = try preDriveAuthoringProduct()
  let draft = preDriveEvidenceAuthoringDraft()
  let configuration = preDriveEvidenceAuthoringConfiguration()

  let manifest = try PreDriveEvidenceBundleAuthor.buildManifest(
    productRelease: release,
    draft: draft,
    configuration: configuration
  )
  let routePlan = release.navigation.bundle.routePlan
  let record = try #require(manifest.records.first)
  let quote = try #require(record.evidence.tariffQuotes.first)

  #expect(manifest.releaseID == configuration.releaseID)
  #expect(manifest.releasedAt == configuration.releasedAt)
  #expect(manifest.evidenceScope == .releasedRoad)
  #expect(manifest.productReleaseID == release.releaseID)
  #expect(manifest.navigationReleaseID == release.navigation.releaseID)
  #expect(manifest.networkSnapshotID == routePlan.networkSnapshotID)
  #expect(manifest.routePlanID == routePlan.id)
  #expect(record.evidence.networkSnapshotID == routePlan.networkSnapshotID)
  #expect(record.evidence.routePlanID == routePlan.id)
  #expect(quote.entryFacilityID == routePlan.entryFacilityID)
  #expect(quote.exitFacilityID == routePlan.exitFacilityID)
  #expect(quote.vehicleClass == record.evidence.vehicleClass)
  #expect(quote.paymentMethod == record.evidence.paymentMethod)
  #expect(manifest.sourceRegistry == draft.sourceRegistry)
}

@Test("Pre-drive evidence drafts round-trip without release or route authority")
func preDriveEvidenceDraftRoundTripsWithoutAuthority() throws {
  let draft = preDriveEvidenceAuthoringDraft()
  let configuration = preDriveEvidenceAuthoringConfiguration()
  let draftData = try PreDriveEvidenceBundleDraftCodec.encode(draft)
  let repeatedDraftData = try PreDriveEvidenceBundleDraftCodec.encode(draft)
  let configurationData =
    try PreDriveEvidenceAuthoringConfigurationCodec.encode(
      configuration
    )
  let draftText = try #require(
    String(data: draftData, encoding: .utf8)
  )

  #expect(
    try PreDriveEvidenceBundleDraftCodec.decode(draftData)
      == draft
  )
  #expect(
    try PreDriveEvidenceAuthoringConfigurationCodec.decode(
      configurationData
    ) == configuration
  )
  #expect(draftData == repeatedDraftData)
  #expect(!draftText.contains("\"product_release_id\""))
  #expect(!draftText.contains("\"navigation_release_id\""))
  #expect(!draftText.contains("\"network_snapshot_id\""))
  #expect(!draftText.contains("\"route_plan_id\""))
  #expect(!draftText.contains("\"entry_facility_id\""))
  #expect(!draftText.contains("\"exit_facility_id\""))
  #expect(!draftText.contains("\"evidence_scope\""))
  #expect(!draftText.contains("\"release_id\""))
  #expect(!draftText.contains("\"released_at\""))
}

@Test("Pre-drive evidence author rejects synthetic product authority")
func preDriveEvidenceAuthorRejectsSyntheticProduct() throws {
  let fixture = navigationReleaseBundleFixture()
  let release = try KaidoProductRelease(
    artifact: KaidoProductReleaseArtifact(
      releaseID: "test.product.pre-drive-authoring.synthetic",
      releasedAt: "2026-07-24T12:30:00+09:00",
      navigationRelease: navigationReleaseArtifact(fixture),
      routeAtlasRelease: productRouteAtlasArtifact(
        fixture,
        includeIncomingApproach: true
      )
    )
  )

  #expect(
    throws: PreDriveEvidenceAuthoringError.foregroundProductRequired
  ) {
    try PreDriveEvidenceBundleAuthor.buildManifest(
      productRelease: release,
      draft: preDriveEvidenceAuthoringDraft(),
      configuration: preDriveEvidenceAuthoringConfiguration()
    )
  }
}

@Test("Pre-drive evidence author rejects unknown authoring schemas")
func preDriveEvidenceAuthorRejectsUnknownSchemas() throws {
  let release = try preDriveAuthoringProduct()
  let validDraft = preDriveEvidenceAuthoringDraft()
  let invalidDraft = PreDriveEvidenceBundleDraft(
    schemaVersion: "2.0",
    sourceRegistry: validDraft.sourceRegistry,
    records: validDraft.records
  )
  let invalidConfiguration =
    PreDriveEvidenceAuthoringConfiguration(
      schemaVersion: "2.0",
      releaseID: " test.pre-drive-evidence.authoring.v1 ",
      releasedAt: "not-a-date"
    )

  #expect(
    throws: PreDriveEvidenceAuthoringError.invalidDraft([
      .invalidDraftSchemaVersion
    ])
  ) {
    try PreDriveEvidenceBundleAuthor.buildManifest(
      productRelease: release,
      draft: invalidDraft,
      configuration: preDriveEvidenceAuthoringConfiguration()
    )
  }
  #expect(
    throws: PreDriveEvidenceAuthoringError.invalidConfiguration([
      .invalidConfigurationSchemaVersion,
      .invalidReleaseIdentity,
    ])
  ) {
    try PreDriveEvidenceBundleAuthor.buildManifest(
      productRelease: release,
      draft: validDraft,
      configuration: invalidConfiguration
    )
  }
}

@Test("Pre-drive evidence author returns nothing before the whole gate passes")
func preDriveEvidenceAuthorRejectsInvalidReviewedDraft() throws {
  let valid = preDriveEvidenceAuthoringDraft()
  let source = try #require(valid.sourceRegistry.first)
  let invalidSource = PreDriveEvidenceSourceReference(
    id: source.id,
    roles: [.tariffQuery],
    authorityName: source.authorityName,
    sourceURL: source.sourceURL,
    contentSHA256: source.contentSHA256,
    checkedAt: source.checkedAt,
    reviewerID: source.reviewerID,
    reviewedAt: source.reviewedAt
  )
  let invalidDraft = PreDriveEvidenceBundleDraft(
    sourceRegistry: [invalidSource],
    records: valid.records.map {
      PreDriveEvidenceRecordDraft(
        id: $0.id,
        validFrom: $0.validFrom,
        expiresAt: $0.expiresAt,
        sourceReferenceIDs: [invalidSource.id],
        evidence: $0.evidence
      )
    }
  )

  do {
    _ = try PreDriveEvidenceBundleAuthor.buildManifest(
      productRelease: preDriveAuthoringProduct(),
      draft: invalidDraft,
      configuration: preDriveEvidenceAuthoringConfiguration()
    )
    Issue.record("Expected missing passage authority to block authoring")
  } catch PreDriveEvidenceAuthoringError.invalidBundle(let issues) {
    #expect(
      issues.contains(
        .missingSourceRole(
          "test.pre-drive-record.authoring.standard-etc",
          .passageReview
        )
      )
    )
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

private func preDriveAuthoringProduct() throws -> KaidoProductRelease {
  try KaidoProductReleaseArtifactCodec.decode(
    appBundleReleasedProductData()
  )
}

private func preDriveEvidenceAuthoringConfiguration()
  -> PreDriveEvidenceAuthoringConfiguration
{
  PreDriveEvidenceAuthoringConfiguration(
    releaseID: "test.pre-drive-evidence.authoring.v1",
    releasedAt: "2026-07-24T13:15:00+09:00"
  )
}

private func preDriveEvidenceAuthoringDraft()
  -> PreDriveEvidenceBundleDraft
{
  let tariffSource = PreDriveEvidenceSourceReference(
    id: "test.pre-drive-source.authoring.tariff",
    roles: [.tariffQuery],
    authorityName: "Test tariff authority",
    sourceURL: "https://example.com/test-tariff",
    contentSHA256: String(repeating: "a", count: 64),
    checkedAt: "2026-07-24T12:40:00+09:00",
    reviewerID: "test.reviewer.authoring.tariff",
    reviewedAt: "2026-07-24T13:10:00+09:00"
  )
  let passageSource = PreDriveEvidenceSourceReference(
    id: "test.pre-drive-source.authoring.passage",
    roles: [.passageReview],
    authorityName: "Test passage authority",
    sourceURL: "https://example.com/test-passage",
    contentSHA256: String(repeating: "b", count: 64),
    checkedAt: "2026-07-24T12:45:00+09:00",
    reviewerID: "test.reviewer.authoring.passage",
    reviewedAt: "2026-07-24T13:10:00+09:00"
  )
  return PreDriveEvidenceBundleDraft(
    sourceRegistry: [tariffSource, passageSource],
    records: [
      PreDriveEvidenceRecordDraft(
        id: "test.pre-drive-record.authoring.standard-etc",
        validFrom: "2026-07-24T13:00:00+09:00",
        expiresAt: "2026-07-25T00:00:00+09:00",
        sourceReferenceIDs: [
          tariffSource.id,
          passageSource.id,
        ],
        evidence: PreDriveReviewEvidenceDraft(
          evaluatedAt: "2026-07-24T12:50:00+09:00",
          vehicleClass: .standard,
          paymentMethod: .etc,
          passageEvidence: .noKnownConflictRealtimeUnconfirmed,
          tariffQuotes: [
            PreDriveTariffQuoteDraft(
              id: "test.pre-drive-quote.authoring.standard-etc",
              tariffVersionID: "test.pre-drive-tariff.authoring.v1",
              tariffVersionStatus: .active,
              tariffDistanceKM: 24.8,
              estimatedAmountYen: 1_320,
              evidenceStatus: .verifiedQuery,
              checkedAt: "2026-07-24T12:40:00+09:00",
              officialQueryReference:
                "https://example.com/test-tariff"
            )
          ]
        )
      )
    ]
  )
}
