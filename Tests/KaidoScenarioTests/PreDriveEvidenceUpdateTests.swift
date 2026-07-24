import CryptoKit
import Foundation
import KaidoAppleAdapters
import KaidoNavigation
import KaidoPresentation
import Testing

@Test("Signed pre-drive evidence updates verify the exact manifest bytes")
func preDriveEvidenceUpdateRoundTrips() throws {
  let fixture = try preDriveEvidenceUpdateFixture()

  let encoded = try PreDriveEvidenceUpdateCodec.sign(
    manifestData: fixture.manifestData,
    productRelease: fixture.productRelease,
    keyID: fixture.trustKey.keyID,
    privateKeyData: fixture.privateKeyData
  )
  let verified = try PreDriveEvidenceUpdateCodec.verify(
    encoded,
    productRelease: fixture.productRelease,
    trustedKeys: [fixture.trustKey]
  )

  #expect(verified.manifestData == fixture.manifestData)
  #expect(
    verified.bundle.manifest.releaseID
      == fixture.manifest.releaseID
  )
  #expect(
    verified.bundle.manifest.productReleaseID
      == fixture.productRelease.releaseID
  )
  #expect(verified.envelope.keyID == fixture.trustKey.keyID)
}

@Test("Signed pre-drive evidence updates reject payload and signature drift")
func preDriveEvidenceUpdateRejectsTampering() throws {
  let fixture = try preDriveEvidenceUpdateFixture()
  let encoded = try PreDriveEvidenceUpdateCodec.sign(
    manifestData: fixture.manifestData,
    productRelease: fixture.productRelease,
    keyID: fixture.trustKey.keyID,
    privateKeyData: fixture.privateKeyData
  )
  let envelope = try JSONDecoder().decode(
    PreDriveEvidenceUpdateEnvelope.self,
    from: encoded
  )
  var changedManifest = fixture.manifestData
  changedManifest.append(0x20)
  let drifted = PreDriveEvidenceUpdateEnvelope(
    keyID: envelope.keyID,
    algorithm: envelope.algorithm,
    manifestSHA256: preDriveEvidenceUpdateTestSHA256Hex(changedManifest),
    manifestBase64: changedManifest.base64EncodedString(),
    signatureBase64: envelope.signatureBase64
  )
  let driftedData = try JSONEncoder().encode(drifted)

  #expect(
    throws: PreDriveEvidenceUpdateError.signatureInvalid
  ) {
    try PreDriveEvidenceUpdateCodec.verify(
      driftedData,
      productRelease: fixture.productRelease,
      trustedKeys: [fixture.trustKey]
    )
  }

  let invalidHash = PreDriveEvidenceUpdateEnvelope(
    keyID: envelope.keyID,
    algorithm: envelope.algorithm,
    manifestSHA256: String(repeating: "0", count: 64),
    manifestBase64: envelope.manifestBase64,
    signatureBase64: envelope.signatureBase64
  )
  #expect(
    throws: PreDriveEvidenceUpdateError.manifestHashMismatch
  ) {
    try PreDriveEvidenceUpdateCodec.verify(
      JSONEncoder().encode(invalidHash),
      productRelease: fixture.productRelease,
      trustedKeys: [fixture.trustKey]
    )
  }
}

@Test("Signed pre-drive evidence updates require one pinned trust key")
func preDriveEvidenceUpdateRequiresPinnedTrust() throws {
  let fixture = try preDriveEvidenceUpdateFixture()
  let encoded = try PreDriveEvidenceUpdateCodec.sign(
    manifestData: fixture.manifestData,
    productRelease: fixture.productRelease,
    keyID: fixture.trustKey.keyID,
    privateKeyData: fixture.privateKeyData
  )
  let otherKey = try PreDriveEvidenceUpdateCodec.generateSigningKeyPair(
    keyID: "test.pre-drive-update.other"
  ).trustKey

  #expect(
    throws: PreDriveEvidenceUpdateError.trustedKeyUnavailable
  ) {
    try PreDriveEvidenceUpdateCodec.verify(
      encoded,
      productRelease: fixture.productRelease,
      trustedKeys: [otherKey]
    )
  }
  #expect(
    throws: PreDriveEvidenceUpdateError.invalidTrustRegistry
  ) {
    try PreDriveEvidenceUpdateCodec.verify(
      encoded,
      productRelease: fixture.productRelease,
      trustedKeys: [fixture.trustKey, fixture.trustKey]
    )
  }
}

@Test("Signed pre-drive evidence updates remain bound to one exact product")
func preDriveEvidenceUpdateRejectsProductDrift() throws {
  let fixture = try preDriveEvidenceUpdateFixture()
  let encoded = try PreDriveEvidenceUpdateCodec.sign(
    manifestData: fixture.manifestData,
    productRelease: fixture.productRelease,
    keyID: fixture.trustKey.keyID,
    privateKeyData: fixture.privateKeyData
  )
  let original = try #require(
    String(data: appBundleReleasedProductData(), encoding: .utf8)
  )
  let driftedData = try #require(
    original.replacingOccurrences(
      of: "test.product-release.app-bundle",
      with: "test.product-release.update-drift"
    ).data(using: .utf8)
  )
  let driftedProduct = try KaidoProductReleaseArtifactCodec.decode(
    driftedData
  )

  do {
    _ = try PreDriveEvidenceUpdateCodec.verify(
      encoded,
      productRelease: driftedProduct,
      trustedKeys: [fixture.trustKey]
    )
    Issue.record("Expected product identity drift to block the update")
  } catch PreDriveEvidenceUpdateError.invalidBundle(let issues) {
    #expect(issues.contains(.productReleaseMismatch))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Synthetic products cannot mint signed evidence updates")
func preDriveEvidenceUpdateRejectsSyntheticProduct() throws {
  let fixture = navigationReleaseBundleFixture()
  let synthetic = try KaidoProductRelease(
    artifact: KaidoProductReleaseArtifact(
      releaseID: "test.product.pre-drive-update.synthetic",
      releasedAt: "2026-07-24T12:30:00+09:00",
      navigationRelease: navigationReleaseArtifact(fixture),
      routeAtlasRelease: productRouteAtlasArtifact(
        fixture,
        includeIncomingApproach: true
      )
    )
  )
  let keyPair = try PreDriveEvidenceUpdateCodec.generateSigningKeyPair(
    keyID: "test.pre-drive-update.synthetic"
  )

  #expect(
    throws: PreDriveEvidenceUpdateError.foregroundProductRequired
  ) {
    try PreDriveEvidenceUpdateCodec.sign(
      manifestData: Data("{}".utf8),
      productRelease: synthetic,
      keyID: keyPair.trustKey.keyID,
      privateKeyData: keyPair.privateKeyData
    )
  }
}

private struct PreDriveEvidenceUpdateTestFixture {
  let productRelease: KaidoProductRelease
  let manifest: PreDriveEvidenceBundleManifest
  let manifestData: Data
  let privateKeyData: Data
  let trustKey: PreDriveEvidenceUpdateTrustKey
}

private func preDriveEvidenceUpdateFixture()
  throws -> PreDriveEvidenceUpdateTestFixture
{
  let productRelease = try KaidoProductReleaseArtifactCodec.decode(
    appBundleReleasedProductData()
  )
  let draft = preDriveEvidenceUpdateDraft(
    productRelease: productRelease
  )
  let manifest = try PreDriveEvidenceBundleAuthor.buildManifest(
    productRelease: productRelease,
    draft: draft,
    configuration: PreDriveEvidenceAuthoringConfiguration(
      releaseID: "test.pre-drive-evidence.signed-update.v1",
      releasedAt: "2026-07-24T13:15:00+09:00"
    )
  )
  let manifestData = try PreDriveEvidenceBundleCodec.encode(
    manifest,
    context: PreDriveEvidenceBundleContext(
      productReleaseID: productRelease.releaseID,
      productReleasedAt: productRelease.releasedAt,
      navigationReleaseID: productRelease.navigation.releaseID,
      routePlan: productRelease.navigation.bundle.routePlan,
      evidenceScope: .releasedRoad
    )
  )
  let keyPair = try PreDriveEvidenceUpdateCodec.generateSigningKeyPair(
    keyID: "test.pre-drive-update.release-2026"
  )
  return PreDriveEvidenceUpdateTestFixture(
    productRelease: productRelease,
    manifest: manifest,
    manifestData: manifestData,
    privateKeyData: keyPair.privateKeyData,
    trustKey: keyPair.trustKey
  )
}

private func preDriveEvidenceUpdateDraft(
  productRelease: KaidoProductRelease
) -> PreDriveEvidenceBundleDraft {
  let routePlan = productRelease.navigation.bundle.routePlan
  let tariffSource = PreDriveEvidenceSourceReference(
    id: "test.pre-drive-update-source.tariff",
    roles: [.tariffQuery],
    authorityName: "Test tariff authority",
    sourceURL: "https://example.com/test-tariff",
    contentSHA256: String(repeating: "a", count: 64),
    checkedAt: "2026-07-24T12:40:00+09:00",
    reviewerID: "test.reviewer.update.tariff",
    reviewedAt: "2026-07-24T13:10:00+09:00"
  )
  let passageSource = PreDriveEvidenceSourceReference(
    id: "test.pre-drive-update-source.passage",
    roles: [.passageReview],
    authorityName: "Test passage authority",
    sourceURL: "https://example.com/test-passage",
    contentSHA256: String(repeating: "b", count: 64),
    checkedAt: "2026-07-24T12:45:00+09:00",
    reviewerID: "test.reviewer.update.passage",
    reviewedAt: "2026-07-24T13:10:00+09:00"
  )
  return PreDriveEvidenceBundleDraft(
    sourceRegistry: [tariffSource, passageSource],
    records: [
      PreDriveEvidenceRecordDraft(
        id: "test.pre-drive-update-record.standard-etc",
        validFrom: "2026-07-24T13:00:00+09:00",
        expiresAt: "2026-07-26T00:00:00+09:00",
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
              id: "test.pre-drive-update-quote.standard-etc",
              tariffVersionID: "test.pre-drive-update-tariff.v1",
              tariffVersionStatus: .active,
              tariffDistanceKM: routePlan.actualDistanceKM,
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

private func preDriveEvidenceUpdateTestSHA256Hex(_ data: Data) -> String {
  SHA256.hash(data: data)
    .map { String(format: "%02x", $0) }
    .joined()
}
