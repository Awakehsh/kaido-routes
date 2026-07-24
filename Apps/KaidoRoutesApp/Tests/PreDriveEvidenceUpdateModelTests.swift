import Foundation
import KaidoAppleAdapters
import KaidoDomain
import KaidoPresentation
import XCTest

@testable import KaidoRoutesApp

@MainActor
final class PreDriveEvidenceUpdateModelTests: XCTestCase {
  func testExplicitHTTPSRefreshVerifiesPersistsAndPublishes() async throws {
    let keyPair = try PreDriveEvidenceUpdateCodec.generateSigningKeyPair(
      keyID: "test.app.pre-drive-evidence.refresh"
    )
    let endpoint = PreDriveEvidenceUpdateEndpoint(
      url: "https://updates.kaido.test/evidence/released-road.json"
    )
    let entry = try makeReleasedProductTestEntry(
      includePreDriveEvidence: true,
      preDriveEvidenceUpdateTrustKeys: [keyPair.trustKey],
      preDriveEvidenceUpdateEndpoint: endpoint
    )
    let envelope = try makeSignedPreDriveEvidenceUpdate(
      for: entry,
      keyPair: keyPair,
      releaseID: "test.pre-drive-evidence.refresh.v2",
      releasedAt: "2026-07-25T13:00:00+09:00",
      amountYen: 1_480
    )
    let fetcher = FixedPreDriveEvidenceUpdateFetcher(
      response: .data(envelope)
    )
    let store = MemoryPreDriveEvidenceUpdateStore()
    let now = try XCTUnwrap(
      ISO8601DateFormatter().date(
        from: "2026-07-25T13:30:00+09:00"
      )
    )
    let model = PreDriveEvidenceUpdateModel(
      entries: [entry],
      store: store,
      fetcher: fetcher,
      currentDateProvider: { now }
    )
    var evidenceChangeCount = 0
    model.evidenceDidChange = {
      evidenceChangeCount += 1
    }

    XCTAssertTrue(
      model.canRefresh(productReleaseID: entry.release.releaseID)
    )
    await model.refresh(productReleaseID: entry.release.releaseID)

    let requestedEndpoints = await fetcher.requestedEndpoints()
    XCTAssertEqual(requestedEndpoints, [endpoint])
    XCTAssertEqual(
      model.state,
      .installed(
        productReleaseID: entry.release.releaseID,
        evidenceReleaseID: "test.pre-drive-evidence.refresh.v2"
      )
    )
    XCTAssertEqual(store.values[entry.release.releaseID], envelope)
    XCTAssertEqual(evidenceChangeCount, 1)
    XCTAssertEqual(
      try model.evidence(
        for: entry,
        session: preDriveEvidenceUpdateSession(for: entry)
      )?.tariffQuotes.first?.estimatedAmountYen,
      1_480
    )
  }

  func testRefreshFailureNeverReplacesBundledEvidence() async throws {
    let keyPair = try PreDriveEvidenceUpdateCodec.generateSigningKeyPair(
      keyID: "test.app.pre-drive-evidence.refresh-failure"
    )
    let entry = try makeReleasedProductTestEntry(
      includePreDriveEvidence: true,
      preDriveEvidenceUpdateTrustKeys: [keyPair.trustKey],
      preDriveEvidenceUpdateEndpoint: PreDriveEvidenceUpdateEndpoint(
        url: "https://updates.kaido.test/evidence/failure.json"
      )
    )
    let store = MemoryPreDriveEvidenceUpdateStore()
    let now = try XCTUnwrap(
      ISO8601DateFormatter().date(
        from: "2026-07-25T13:30:00+09:00"
      )
    )
    let invalidFetcher = FixedPreDriveEvidenceUpdateFetcher(
      response: .data(Data("not-a-signed-envelope".utf8))
    )
    let invalidModel = PreDriveEvidenceUpdateModel(
      entries: [entry],
      store: store,
      fetcher: invalidFetcher,
      currentDateProvider: { now }
    )

    await invalidModel.refresh(
      productReleaseID: entry.release.releaseID
    )

    XCTAssertEqual(
      invalidModel.state,
      .blocked(
        PreDriveEvidenceUpdateModelError
          .fetchedEnvelopeInvalid.rawValue
      )
    )
    XCTAssertTrue(store.values.isEmpty)
    XCTAssertEqual(
      try invalidModel.evidence(
        for: entry,
        session: preDriveEvidenceUpdateSession(for: entry)
      )?.tariffQuotes.first?.estimatedAmountYen,
      1_320
    )

    let networkModel = PreDriveEvidenceUpdateModel(
      entries: [entry],
      store: store,
      fetcher: FixedPreDriveEvidenceUpdateFetcher(
        response: .failure(.timedOut)
      ),
      currentDateProvider: { now }
    )
    await networkModel.refresh(
      productReleaseID: entry.release.releaseID
    )
    XCTAssertEqual(
      networkModel.state,
      .blocked(
        PreDriveEvidenceUpdateFetchError.timedOut.code
      )
    )
    XCTAssertTrue(store.values.isEmpty)
  }

  func testRefreshRequiresTheSelectedProductPinnedEndpoint()
    async throws
  {
    let keyPair = try PreDriveEvidenceUpdateCodec.generateSigningKeyPair(
      keyID: "test.app.pre-drive-evidence.no-endpoint"
    )
    let entry = try makeReleasedProductTestEntry(
      includePreDriveEvidence: true,
      preDriveEvidenceUpdateTrustKeys: [keyPair.trustKey]
    )
    let fetcher = FixedPreDriveEvidenceUpdateFetcher(
      response: .failure(.network)
    )
    let model = PreDriveEvidenceUpdateModel(
      entries: [entry],
      store: MemoryPreDriveEvidenceUpdateStore(),
      fetcher: fetcher
    )

    XCTAssertFalse(
      model.canRefresh(productReleaseID: entry.release.releaseID)
    )
    await model.refresh(productReleaseID: entry.release.releaseID)

    XCTAssertEqual(
      model.state,
      .blocked(
        PreDriveEvidenceUpdateModelError.refreshUnavailable.rawValue
      )
    )
    let requestedEndpoints = await fetcher.requestedEndpoints()
    XCTAssertTrue(requestedEndpoints.isEmpty)
  }

  func testFileStoreAtomicallyRoundTripsOneProductEnvelope() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "kaido-pre-drive-update-\(UUID().uuidString)",
        isDirectory: true
      )
    defer {
      try? FileManager.default.removeItem(at: directory)
    }
    let store = FilePreDriveEvidenceUpdateStore(
      directoryURL: directory
    )
    let data = Data("test-signed-envelope".utf8)

    try store.save(
      data,
      productReleaseID: "test.product.file-store"
    )

    XCTAssertEqual(
      try store.load(productReleaseID: "test.product.file-store"),
      data
    )
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
      ).count,
      1
    )
  }

  func testImportPersistsBeforePublishingNewEvidence() throws {
    let keyPair = try PreDriveEvidenceUpdateCodec.generateSigningKeyPair(
      keyID: "test.app.pre-drive-evidence"
    )
    let entry = try makeReleasedProductTestEntry(
      includePreDriveEvidence: true,
      preDriveEvidenceUpdateTrustKeys: [keyPair.trustKey]
    )
    let store = MemoryPreDriveEvidenceUpdateStore()
    let now = try XCTUnwrap(
      ISO8601DateFormatter().date(
        from: "2026-07-25T13:30:00+09:00"
      )
    )
    let envelope = try makeSignedPreDriveEvidenceUpdate(
      for: entry,
      keyPair: keyPair,
      releaseID: "test.pre-drive-evidence.app.v2",
      releasedAt: "2026-07-25T13:00:00+09:00",
      amountYen: 1_480
    )
    let model = PreDriveEvidenceUpdateModel(
      entries: [entry],
      store: store,
      currentDateProvider: { now }
    )
    var evidenceChangeCount = 0
    model.evidenceDidChange = {
      evidenceChangeCount += 1
    }

    model.importEnvelope(envelope)

    XCTAssertEqual(
      model.state,
      .installed(
        productReleaseID: entry.release.releaseID,
        evidenceReleaseID: "test.pre-drive-evidence.app.v2"
      )
    )
    XCTAssertEqual(
      store.values[entry.release.releaseID],
      envelope
    )
    XCTAssertEqual(evidenceChangeCount, 1)
    XCTAssertEqual(
      try model.evidence(
        for: entry,
        session: preDriveEvidenceUpdateSession(for: entry)
      )?.tariffQuotes.first?.estimatedAmountYen,
      1_480
    )
  }

  func testPersistenceFailureLeavesBundledEvidenceActive() throws {
    let keyPair = try PreDriveEvidenceUpdateCodec.generateSigningKeyPair(
      keyID: "test.app.pre-drive-evidence.persistence"
    )
    let entry = try makeReleasedProductTestEntry(
      includePreDriveEvidence: true,
      preDriveEvidenceUpdateTrustKeys: [keyPair.trustKey]
    )
    let store = MemoryPreDriveEvidenceUpdateStore()
    store.failSaves = true
    let now = try XCTUnwrap(
      ISO8601DateFormatter().date(
        from: "2026-07-25T13:30:00+09:00"
      )
    )
    let model = PreDriveEvidenceUpdateModel(
      entries: [entry],
      store: store,
      currentDateProvider: { now }
    )
    var evidenceChangeCount = 0
    model.evidenceDidChange = {
      evidenceChangeCount += 1
    }

    model.importEnvelope(
      try makeSignedPreDriveEvidenceUpdate(
        for: entry,
        keyPair: keyPair,
        releaseID: "test.pre-drive-evidence.persistence.v2",
        releasedAt: "2026-07-25T13:00:00+09:00",
        amountYen: 1_480
      )
    )

    XCTAssertEqual(
      model.state,
      .blocked(
        PreDriveEvidenceUpdateModelError.persistenceFailed.rawValue
      )
    )
    XCTAssertEqual(evidenceChangeCount, 0)
    XCTAssertEqual(
      try model.evidence(
        for: entry,
        session: preDriveEvidenceUpdateSession(for: entry)
      )?.tariffQuotes.first?.estimatedAmountYen,
      1_320
    )
  }

  func testRollbackAndUntrustedUpdatesFailClosed() throws {
    let keyPair = try PreDriveEvidenceUpdateCodec.generateSigningKeyPair(
      keyID: "test.app.pre-drive-evidence.rollback"
    )
    let otherKeyPair =
      try PreDriveEvidenceUpdateCodec.generateSigningKeyPair(
        keyID: "test.app.pre-drive-evidence.untrusted"
      )
    let entry = try makeReleasedProductTestEntry(
      includePreDriveEvidence: true,
      preDriveEvidenceUpdateTrustKeys: [keyPair.trustKey]
    )
    let store = MemoryPreDriveEvidenceUpdateStore()
    let model = PreDriveEvidenceUpdateModel(
      entries: [entry],
      store: store
    )

    model.importEnvelope(
      try makeSignedPreDriveEvidenceUpdate(
        for: entry,
        keyPair: otherKeyPair,
        releaseID: "test.pre-drive-evidence.untrusted.v2",
        releasedAt: "2026-07-25T13:00:00+09:00",
        amountYen: 1_480
      )
    )
    XCTAssertEqual(
      model.state,
      .blocked(
        PreDriveEvidenceUpdateModelError.noTrustedProductMatch.rawValue
      )
    )

    model.importEnvelope(
      try makeSignedPreDriveEvidenceUpdate(
        for: entry,
        keyPair: keyPair,
        releaseID: "test.pre-drive-evidence.rollback.v2",
        releasedAt: "2026-07-25T12:10:00+09:00",
        amountYen: 1_480
      )
    )
    XCTAssertEqual(
      model.state,
      .blocked(
        PreDriveEvidenceUpdateModelError.rollbackRejected.rawValue
      )
    )
    XCTAssertTrue(store.values.isEmpty)
  }

  func testFutureUpdateActivatesOnlyAtItsReleaseTimeAndRestores()
    throws
  {
    let keyPair = try PreDriveEvidenceUpdateCodec.generateSigningKeyPair(
      keyID: "test.app.pre-drive-evidence.future"
    )
    let entry = try makeReleasedProductTestEntry(
      includePreDriveEvidence: true,
      preDriveEvidenceUpdateTrustKeys: [keyPair.trustKey]
    )
    let store = MemoryPreDriveEvidenceUpdateStore()
    var now = try XCTUnwrap(
      ISO8601DateFormatter().date(
        from: "2026-07-25T13:30:00+09:00"
      )
    )
    let envelope = try makeSignedPreDriveEvidenceUpdate(
      for: entry,
      keyPair: keyPair,
      releaseID: "test.pre-drive-evidence.future.v2",
      releasedAt: "2026-07-25T14:00:00+09:00",
      amountYen: 1_480
    )
    let model = PreDriveEvidenceUpdateModel(
      entries: [entry],
      store: store,
      currentDateProvider: { now }
    )
    model.importEnvelope(envelope)

    XCTAssertEqual(
      try model.evidence(
        for: entry,
        session: preDriveEvidenceUpdateSession(for: entry)
      )?.tariffQuotes.first?.estimatedAmountYen,
      1_320
    )

    now = try XCTUnwrap(
      ISO8601DateFormatter().date(
        from: "2026-07-25T14:30:00+09:00"
      )
    )
    XCTAssertEqual(
      try model.evidence(
        for: entry,
        session: preDriveEvidenceUpdateSession(for: entry)
      )?.tariffQuotes.first?.estimatedAmountYen,
      1_480
    )

    let restored = PreDriveEvidenceUpdateModel(
      entries: [entry],
      store: store,
      currentDateProvider: { now }
    )
    XCTAssertEqual(
      restored.state,
      .installed(
        productReleaseID: entry.release.releaseID,
        evidenceReleaseID: "test.pre-drive-evidence.future.v2"
      )
    )
    XCTAssertEqual(
      try restored.evidence(
        for: entry,
        session: preDriveEvidenceUpdateSession(for: entry)
      )?.tariffQuotes.first?.estimatedAmountYen,
      1_480
    )
  }

  func testEffectiveUpdateNeverFallsBackAndRejectsReleaseIDReuse()
    throws
  {
    let keyPair = try PreDriveEvidenceUpdateCodec.generateSigningKeyPair(
      keyID: "test.app.pre-drive-evidence.no-fallback"
    )
    let entry = try makeReleasedProductTestEntry(
      includePreDriveEvidence: true,
      preDriveEvidencePaymentMethods: [.etc, .cash],
      preDriveEvidenceUpdateTrustKeys: [keyPair.trustKey]
    )
    let store = MemoryPreDriveEvidenceUpdateStore()
    let now = try XCTUnwrap(
      ISO8601DateFormatter().date(
        from: "2026-07-25T13:30:00+09:00"
      )
    )
    let model = PreDriveEvidenceUpdateModel(
      entries: [entry],
      store: store,
      currentDateProvider: { now }
    )
    model.importEnvelope(
      try makeSignedPreDriveEvidenceUpdate(
        for: entry,
        keyPair: keyPair,
        releaseID: "test.pre-drive-evidence.no-fallback.v2",
        releasedAt: "2026-07-25T13:00:00+09:00",
        amountYen: 1_480
      )
    )

    XCTAssertThrowsError(
      try model.evidence(
        for: entry,
        session: preDriveEvidenceUpdateSession(
          for: entry,
          paymentMethod: .cash
        )
      )
    ) {
      XCTAssertEqual(
        $0 as? PreDriveEvidenceResolutionError,
        .profileUnavailable
      )
    }

    model.importEnvelope(
      try makeSignedPreDriveEvidenceUpdate(
        for: entry,
        keyPair: keyPair,
        releaseID: "test.pre-drive-evidence.no-fallback.v2",
        releasedAt: "2026-07-25T13:15:00+09:00",
        amountYen: 1_520
      )
    )
    XCTAssertEqual(
      model.state,
      .blocked(
        PreDriveEvidenceUpdateModelError.releaseIdentityReused.rawValue
      )
    )
    XCTAssertEqual(
      try model.evidence(
        for: entry,
        session: preDriveEvidenceUpdateSession(for: entry)
      )?.tariffQuotes.first?.estimatedAmountYen,
      1_480
    )
  }
}

private actor FixedPreDriveEvidenceUpdateFetcher:
  PreDriveEvidenceUpdateFetching
{
  enum Response: Sendable {
    case data(Data)
    case failure(PreDriveEvidenceUpdateFetchError)
  }

  private let response: Response
  private var endpoints: [PreDriveEvidenceUpdateEndpoint] = []

  init(response: Response) {
    self.response = response
  }

  func fetch(
    endpoint: PreDriveEvidenceUpdateEndpoint
  ) async throws -> Data {
    endpoints.append(endpoint)
    switch response {
    case .data(let data):
      return data
    case .failure(let error):
      throw error
    }
  }

  func requestedEndpoints() -> [PreDriveEvidenceUpdateEndpoint] {
    endpoints
  }
}

private final class MemoryPreDriveEvidenceUpdateStore:
  PreDriveEvidenceUpdateStoring
{
  var values: [String: Data] = [:]
  var failSaves = false

  func load(productReleaseID: String) throws -> Data? {
    values[productReleaseID]
  }

  func save(_ data: Data, productReleaseID: String) throws {
    if failSaves {
      throw CocoaError(.fileWriteNoPermission)
    }
    values[productReleaseID] = data
  }
}

private func preDriveEvidenceUpdateSession(
  for entry: BundledProductReleaseEntry,
  paymentMethod: ShutoPaymentMethod = .etc
) -> PreDriveReviewSession {
  let routePlan = entry.release.navigation.bundle.routePlan
  return PreDriveReviewSession(
    networkSnapshotID: routePlan.networkSnapshotID,
    routePlanID: routePlan.id,
    vehicleClass: .standard,
    paymentMethod: paymentMethod
  )
}

private func makeSignedPreDriveEvidenceUpdate(
  for entry: BundledProductReleaseEntry,
  keyPair: PreDriveEvidenceUpdateSigningKeyPair,
  releaseID: String,
  releasedAt: String,
  amountYen: Int
) throws -> Data {
  let routePlan = entry.release.navigation.bundle.routePlan
  let manifest = PreDriveEvidenceBundleManifest(
    releaseID: releaseID,
    releasedAt: releasedAt,
    evidenceScope: .releasedRoad,
    productReleaseID: entry.release.releaseID,
    navigationReleaseID: entry.release.navigation.releaseID,
    networkSnapshotID: routePlan.networkSnapshotID,
    routePlanID: routePlan.id,
    sourceRegistry: [
      PreDriveEvidenceSourceReference(
        id: "test.update.tariff-source",
        roles: [.tariffQuery],
        authorityName: "Test tariff authority",
        sourceURL: "https://example.com/update-tariff",
        contentSHA256: String(repeating: "c", count: 64),
        checkedAt: "2026-07-25T11:45:00+09:00",
        reviewerID: "test.update.tariff-reviewer",
        reviewedAt: "2026-07-25T12:00:00+09:00"
      ),
      PreDriveEvidenceSourceReference(
        id: "test.update.passage-source",
        roles: [.passageReview],
        authorityName: "Test passage authority",
        sourceURL: "https://example.com/update-passage",
        contentSHA256: String(repeating: "d", count: 64),
        checkedAt: "2026-07-25T11:50:00+09:00",
        reviewerID: "test.update.passage-reviewer",
        reviewedAt: "2026-07-25T12:00:00+09:00"
      ),
    ],
    records: [
      PreDriveEvidenceRecord(
        id: "test.update.standard-etc",
        validFrom: "2026-07-25T12:05:00+09:00",
        expiresAt: "2026-07-26T12:00:00+09:00",
        sourceReferenceIDs: [
          "test.update.tariff-source",
          "test.update.passage-source",
        ],
        evidence: PreDriveReviewEvidence(
          evaluatedAt: "2026-07-25T12:00:00+09:00",
          networkSnapshotID: routePlan.networkSnapshotID,
          routePlanID: routePlan.id,
          vehicleClass: .standard,
          paymentMethod: .etc,
          passageEvidence: .noKnownConflictRealtimeUnconfirmed,
          tariffQuotes: [
            TariffQuote(
              id: "\(releaseID).tariff",
              entryFacilityID: routePlan.entryFacilityID,
              exitFacilityID: routePlan.exitFacilityID,
              vehicleClass: .standard,
              paymentMethod: .etc,
              tariffVersionID: "\(releaseID).tariff-version",
              tariffVersionStatus: .active,
              tariffDistanceKM: 24.8,
              estimatedAmountYen: amountYen,
              evidenceStatus: .verifiedQuery,
              checkedAt: "2026-07-25T11:45:00+09:00",
              officialQueryReference:
                "https://example.com/update-tariff"
            )
          ]
        )
      )
    ]
  )
  let manifestData = try PreDriveEvidenceBundleCodec.encode(
    manifest,
    context: PreDriveEvidenceBundleContext(
      productReleaseID: entry.release.releaseID,
      productReleasedAt: entry.release.releasedAt,
      navigationReleaseID: entry.release.navigation.releaseID,
      routePlan: routePlan,
      evidenceScope: .releasedRoad
    )
  )
  return try PreDriveEvidenceUpdateCodec.sign(
    manifestData: manifestData,
    productRelease: entry.release,
    keyID: keyPair.trustKey.keyID,
    privateKeyData: keyPair.privateKeyData
  )
}
