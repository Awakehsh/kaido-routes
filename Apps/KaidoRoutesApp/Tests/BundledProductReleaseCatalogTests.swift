import Foundation
import KaidoAppleAdapters
import KaidoDomain
import KaidoNavigation
import KaidoPresentation
import XCTest

@testable import KaidoRoutesApp

final class BundledProductReleaseCatalogTests: XCTestCase {
  func testBundledForegroundManifestLoadsExactC1Release() throws {
    let catalog = try BundledProductReleaseCatalogLoader.bundledForeground()
    let foreground = try XCTUnwrap(
      catalog.foregroundNavigationEntries.first
    )

    XCTAssertEqual(catalog.entries.count, 1)
    XCTAssertTrue(catalog.demoEntries.isEmpty)
    XCTAssertEqual(
      foreground.release.releaseID,
      "shutoko.product.c1-inner-shibakoen-shiodome.2026-08-15"
    )
    XCTAssertEqual(
      foreground.release.navigation.bundle.routePlan.entryFacilityID,
      "shuto.ic.c1.shibakouen"
    )
    XCTAssertEqual(
      foreground.release.navigation.bundle.routePlan.exitFacilityID,
      "shuto.ic.c1.shiodome"
    )
    XCTAssertEqual(
      foreground.release.navigation.bundle.routePlan.occurrences.count,
      632
    )
    XCTAssertNotNil(foreground.release.foregroundLiveInputAuthority)
  }

  func testBundledManifestLoadsHashBoundDemoAndForegroundReleases() throws {
    let catalog = try BundledProductReleaseCatalogLoader.bundledPreview()
    let demo = try XCTUnwrap(catalog.demoEntries.first)
    let foreground = try XCTUnwrap(
      catalog.foregroundNavigationEntries.first
    )

    XCTAssertEqual(catalog.entries.count, 2)
    XCTAssertEqual(catalog.demoEntries.count, 1)
    XCTAssertEqual(catalog.foregroundNavigationEntries.count, 1)
    XCTAssertEqual(
      demo.release.releaseID,
      "preview.synthetic.product-release.v1"
    )
    XCTAssertEqual(demo.descriptor.role, .demoOnly)
    XCTAssertGreaterThan(demo.encodedByteCount, 0)
    XCTAssertNil(demo.release.foregroundLiveInputAuthority)
    XCTAssertTrue(demo.guidanceAudioChoices.isEmpty)
    XCTAssertEqual(
      foreground.release.releaseID,
      "shutoko.product.k7-aoba-to-kohoku.2026-07-27"
    )
    XCTAssertEqual(
      foreground.release.navigation.bundle.routePlan.actualDistanceKM,
      7.031167671
    )
    XCTAssertEqual(foreground.descriptor.role, .foregroundNavigation)
    XCTAssertNotNil(foreground.release.foregroundLiveInputAuthority)
    XCTAssertTrue(foreground.guidanceAudioChoices.isEmpty)
    XCTAssertEqual(
      foreground.preDriveEvidenceBundle?.manifest.releaseID,
      "shutoko.pre-drive.k7-aoba-to-kohoku.2026-07-27T2224+09"
    )
    XCTAssertEqual(
      foreground.preDriveEvidenceBundle?.manifest.records.count,
      10
    )
    XCTAssertEqual(
      foreground.descriptor.preDriveEvidenceUpdateTrustKeys,
      [
        PreDriveEvidenceUpdateTrustKey(
          keyID: "kaido.pre-drive.k7-aoba-kohoku.2026-01",
          algorithm: .ed25519,
          publicKeyBase64:
            "71TezxLZ0+RfgnPaxgyECnTq2w42R5mk4llV/WYFJy8="
        )
      ]
    )
    XCTAssertEqual(
      foreground.descriptor.preDriveEvidenceUpdateEndpoint,
      PreDriveEvidenceUpdateEndpoint(
        url:
          "https://awakehsh.github.io/kaido-routes/updates/"
          + "k7-aoba-to-kohoku-pre-drive-evidence-update.json"
      )
    )
  }

  func testContentMutationFailsAtManifestHashBeforeCodecAdmission() throws {
    let data = try bundledPreviewData()
    var mutated = data
    mutated.append(0x20)

    XCTAssertThrowsError(
      try load(
        descriptor: .syntheticPreview,
        data: mutated
      )
    ) {
      XCTAssertEqual(
        $0 as? BundledProductReleaseCatalogError,
        .resourceHashMismatch(
          "synthetic-product-runtime-preview.json"
        )
      )
    }
  }

  func testManifestRoleCannotPromoteSyntheticRelease() throws {
    let data = try bundledPreviewData()
    let descriptor = BundledProductReleaseDescriptor(
      resourceName: "synthetic-product-runtime-preview",
      resourceExtension: "json",
      expectedSHA256:
        BundledProductReleaseCatalogLoader.sha256Hex(data),
      expectedReleaseID: "preview.synthetic.product-release.v1",
      role: .foregroundNavigation
    )

    XCTAssertThrowsError(
      try load(descriptor: descriptor, data: data)
    ) {
      XCTAssertEqual(
        $0 as? BundledProductReleaseCatalogError,
        .releaseRoleMismatch(
          "synthetic-product-runtime-preview.json"
        )
      )
    }
  }

  func testReleasedRoadRoleRequiresCodecMintedForegroundAuthority() throws {
    let data = try releasedRoadData()
    let descriptor = BundledProductReleaseDescriptor(
      resourceName: "released-road-product",
      resourceExtension: "json",
      expectedSHA256:
        BundledProductReleaseCatalogLoader.sha256Hex(data),
      expectedReleaseID: "test.released-road.product",
      role: .foregroundNavigation
    )

    let catalog = try load(descriptor: descriptor, data: data)
    let entry = try XCTUnwrap(
      catalog.foregroundNavigationEntries.first
    )

    XCTAssertEqual(catalog.demoEntries.count, 0)
    XCTAssertEqual(entry.release.runtimeUse.evidenceScope, .releasedRoad)
    XCTAssertEqual(
      entry.release.runtimeUse.liveInputPolicy,
      .foregroundWhenInUse
    )
    XCTAssertNotNil(entry.release.foregroundLiveInputAuthority)
  }

  func testForegroundReleaseRetainsValidatedSignedUpdateTrust() throws {
    let data = try releasedRoadData()
    let keyPair = try PreDriveEvidenceUpdateCodec.generateSigningKeyPair(
      keyID: "test.catalog.pre-drive-evidence"
    )
    let endpoint = PreDriveEvidenceUpdateEndpoint(
      url: "https://updates.kaido.test/evidence/released-road.json"
    )
    let descriptor = BundledProductReleaseDescriptor(
      resourceName: "released-road-product",
      resourceExtension: "json",
      expectedSHA256:
        BundledProductReleaseCatalogLoader.sha256Hex(data),
      expectedReleaseID: "test.released-road.product",
      role: .foregroundNavigation,
      preDriveEvidenceUpdateTrustKeys: [keyPair.trustKey],
      preDriveEvidenceUpdateEndpoint: endpoint
    )

    let entry = try XCTUnwrap(
      load(descriptor: descriptor, data: data)
        .foregroundNavigationEntries.first
    )

    XCTAssertEqual(
      entry.preDriveEvidenceUpdateTrustKeys,
      [keyPair.trustKey]
    )
    XCTAssertEqual(entry.preDriveEvidenceUpdateEndpoint, endpoint)
  }

  func testSignedUpdateEndpointRequiresHTTPSAndTrust() throws {
    let data = try releasedRoadData()
    let keyPair = try PreDriveEvidenceUpdateCodec.generateSigningKeyPair(
      keyID: "test.catalog.endpoint"
    )
    let base = BundledProductReleaseDescriptor(
      resourceName: "released-road-product",
      resourceExtension: "json",
      expectedSHA256:
        BundledProductReleaseCatalogLoader.sha256Hex(data),
      expectedReleaseID: "test.released-road.product",
      role: .foregroundNavigation,
      preDriveEvidenceUpdateTrustKeys: [keyPair.trustKey],
      preDriveEvidenceUpdateEndpoint: PreDriveEvidenceUpdateEndpoint(
        url: "http://updates.kaido.test/evidence/released-road.json"
      )
    )

    XCTAssertThrowsError(try load(descriptor: base, data: data)) {
      XCTAssertEqual(
        $0 as? BundledProductReleaseCatalogError,
        .invalidPreDriveEvidenceUpdateEndpoint(
          base.resourceFilename
        )
      )
    }

    let untrusted = BundledProductReleaseDescriptor(
      resourceName: base.resourceName,
      resourceExtension: base.resourceExtension,
      expectedSHA256: base.expectedSHA256,
      expectedReleaseID: base.expectedReleaseID,
      role: base.role,
      preDriveEvidenceUpdateEndpoint: PreDriveEvidenceUpdateEndpoint(
        url: "https://updates.kaido.test/evidence/released-road.json"
      )
    )
    XCTAssertThrowsError(try load(descriptor: untrusted, data: data)) {
      XCTAssertEqual(
        $0 as? BundledProductReleaseCatalogError,
        .preDriveEvidenceUpdateEndpointTrustMismatch(
          untrusted.resourceFilename
        )
      )
    }
  }

  func testSignedUpdateTrustCannotAttachToDemoRole() throws {
    let data = try bundledPreviewData()
    let keyPair = try PreDriveEvidenceUpdateCodec.generateSigningKeyPair(
      keyID: "test.catalog.demo-trust"
    )
    let descriptor = BundledProductReleaseDescriptor(
      resourceName: "synthetic-product-runtime-preview",
      resourceExtension: "json",
      expectedSHA256:
        BundledProductReleaseCatalogLoader.sha256Hex(data),
      expectedReleaseID: "preview.synthetic.product-release.v1",
      role: .demoOnly,
      preDriveEvidenceUpdateTrustKeys: [keyPair.trustKey]
    )

    XCTAssertThrowsError(
      try load(descriptor: descriptor, data: data)
    ) {
      XCTAssertEqual(
        $0 as? BundledProductReleaseCatalogError,
        .preDriveEvidenceUpdateTrustRoleMismatch(
          descriptor.resourceFilename
        )
      )
    }
  }

  func testSignedUpdateEndpointCannotAttachToDemoRole() throws {
    let data = try bundledPreviewData()
    let keyPair = try PreDriveEvidenceUpdateCodec.generateSigningKeyPair(
      keyID: "test.catalog.demo-endpoint"
    )
    let descriptor = BundledProductReleaseDescriptor(
      resourceName: "synthetic-product-runtime-preview",
      resourceExtension: "json",
      expectedSHA256:
        BundledProductReleaseCatalogLoader.sha256Hex(data),
      expectedReleaseID: "preview.synthetic.product-release.v1",
      role: .demoOnly,
      preDriveEvidenceUpdateTrustKeys: [keyPair.trustKey],
      preDriveEvidenceUpdateEndpoint: PreDriveEvidenceUpdateEndpoint(
        url: "https://updates.kaido.test/evidence/demo.json"
      )
    )

    XCTAssertThrowsError(
      try load(descriptor: descriptor, data: data)
    ) {
      XCTAssertEqual(
        $0 as? BundledProductReleaseCatalogError,
        .preDriveEvidenceUpdateEndpointRoleMismatch(
          descriptor.resourceFilename
        )
      )
    }
  }

  func testDuplicateSignedUpdateTrustFailsClosed() throws {
    let data = try releasedRoadData()
    let keyPair = try PreDriveEvidenceUpdateCodec.generateSigningKeyPair(
      keyID: "test.catalog.duplicate-trust"
    )
    let descriptor = BundledProductReleaseDescriptor(
      resourceName: "released-road-product",
      resourceExtension: "json",
      expectedSHA256:
        BundledProductReleaseCatalogLoader.sha256Hex(data),
      expectedReleaseID: "test.released-road.product",
      role: .foregroundNavigation,
      preDriveEvidenceUpdateTrustKeys: [
        keyPair.trustKey,
        keyPair.trustKey,
      ]
    )

    XCTAssertThrowsError(
      try load(descriptor: descriptor, data: data)
    ) {
      XCTAssertEqual(
        $0 as? BundledProductReleaseCatalogError,
        .invalidPreDriveEvidenceUpdateTrust(
          descriptor.resourceFilename
        )
      )
    }
  }

  func testNavigationSelectionRequiresWholeRoutePlanEquality() throws {
    let data = try releasedRoadData()
    let descriptor = BundledProductReleaseDescriptor(
      resourceName: "released-road-product",
      resourceExtension: "json",
      expectedSHA256:
        BundledProductReleaseCatalogLoader.sha256Hex(data),
      expectedReleaseID: "test.released-road.product",
      role: .foregroundNavigation
    )
    let catalog = try load(descriptor: descriptor, data: data)
    let releasedRoutePlan = try XCTUnwrap(
      catalog.foregroundNavigationEntries.first
    ).release.navigation.bundle.routePlan

    guard
      case .selected(let selected) =
        catalog.selectForegroundNavigationRelease(
          matching: releasedRoutePlan
        )
    else {
      return XCTFail("Expected exact released RoutePlan selection")
    }
    XCTAssertEqual(selected.release.releaseID, "test.released-road.product")

    let driftedRoutePlan = RoutePlan(
      id: releasedRoutePlan.id,
      networkSnapshotID: "\(releasedRoutePlan.networkSnapshotID).drift",
      entryFacilityID: releasedRoutePlan.entryFacilityID,
      exitFacilityID: releasedRoutePlan.exitFacilityID,
      recoveryPolicy: releasedRoutePlan.recoveryPolicy,
      actualDistanceKM: releasedRoutePlan.actualDistanceKM,
      occurrences: releasedRoutePlan.occurrences
    )
    XCTAssertEqual(
      catalog.selectForegroundNavigationRelease(
        matching: driftedRoutePlan
      ),
      .unavailable
    )
  }

  func testNavigationSelectionFailsClosedWhenExactRouteHasMultipleReleases()
    throws
  {
    let firstData = try releasedRoadData(
      releaseID: "test.released-road.first"
    )
    let secondData = try releasedRoadData(
      releaseID: "test.released-road.second"
    )
    let descriptors = [
      releasedRoadDescriptor(
        resourceName: "released-road-first",
        releaseID: "test.released-road.first",
        data: firstData
      ),
      releasedRoadDescriptor(
        resourceName: "released-road-second",
        releaseID: "test.released-road.second",
        data: secondData
      ),
    ]
    let catalog = try BundledProductReleaseCatalogLoader.load(
      descriptors: descriptors
    ) { descriptor in
      switch descriptor.resourceName {
      case "released-road-first":
        firstData
      case "released-road-second":
        secondData
      default:
        nil
      }
    }
    let routePlan = try XCTUnwrap(
      catalog.foregroundNavigationEntries.first
    ).release.navigation.bundle.routePlan

    XCTAssertEqual(
      catalog.selectForegroundNavigationRelease(matching: routePlan),
      .ambiguous([
        "test.released-road.first",
        "test.released-road.second",
      ])
    )
  }

  func testDuplicateResourceAndReleaseIdentityFailClosed() throws {
    let data = try bundledPreviewData()
    let descriptor = BundledProductReleaseDescriptor.syntheticPreview

    XCTAssertThrowsError(
      try BundledProductReleaseCatalogLoader.load(
        descriptors: [descriptor, descriptor]
      ) { _ in data }
    ) {
      XCTAssertEqual(
        $0 as? BundledProductReleaseCatalogError,
        .duplicateResource(
          "synthetic-product-runtime-preview.json"
        )
      )
    }

    let duplicateIdentityDescriptor = BundledProductReleaseDescriptor(
      resourceName: "second-synthetic-resource",
      resourceExtension: "json",
      expectedSHA256:
        BundledProductReleaseCatalogLoader.sha256Hex(data),
      expectedReleaseID: descriptor.expectedReleaseID,
      role: .demoOnly
    )
    XCTAssertThrowsError(
      try BundledProductReleaseCatalogLoader.load(
        descriptors: [descriptor, duplicateIdentityDescriptor]
      ) { _ in data }
    ) {
      XCTAssertEqual(
        $0 as? BundledProductReleaseCatalogError,
        .duplicateReleaseID(descriptor.expectedReleaseID)
      )
    }
  }

  func testMissingCorruptAndInvalidDescriptorHaveStableFailures() throws {
    let descriptor = BundledProductReleaseDescriptor.syntheticPreview

    XCTAssertThrowsError(
      try BundledProductReleaseCatalogLoader.load(
        descriptors: [descriptor]
      ) { _ in nil }
    ) {
      XCTAssertEqual(
        $0 as? BundledProductReleaseCatalogError,
        .missingResource(descriptor.resourceFilename)
      )
    }

    let corruptData = Data("not-json".utf8)
    let corruptDescriptor = BundledProductReleaseDescriptor(
      resourceName: "corrupt-product-release",
      resourceExtension: "json",
      expectedSHA256:
        BundledProductReleaseCatalogLoader.sha256Hex(corruptData),
      expectedReleaseID: "test.corrupt.release",
      role: .demoOnly
    )
    XCTAssertThrowsError(
      try load(
        descriptor: corruptDescriptor,
        data: corruptData
      )
    ) {
      XCTAssertEqual(
        $0 as? BundledProductReleaseCatalogError,
        .invalidProductRelease(
          corruptDescriptor.resourceFilename
        )
      )
    }

    let invalidDescriptor = BundledProductReleaseDescriptor(
      resourceName: "../outside-bundle",
      resourceExtension: "json",
      expectedSHA256: String(repeating: "0", count: 64),
      expectedReleaseID: "test.invalid.descriptor",
      role: .demoOnly
    )
    XCTAssertThrowsError(
      try BundledProductReleaseCatalogLoader.load(
        descriptors: [invalidDescriptor]
      ) { _ in Data() }
    ) {
      XCTAssertEqual(
        $0 as? BundledProductReleaseCatalogError,
        .invalidDescriptor(invalidDescriptor.resourceFilename)
      )
    }
  }

  func testEmptyManifestAndReleaseIdentityDriftHaveStableFailures()
    throws
  {
    XCTAssertThrowsError(
      try BundledProductReleaseCatalogLoader.load(
        descriptors: []
      ) { _ in nil }
    ) {
      XCTAssertEqual(
        $0 as? BundledProductReleaseCatalogError,
        .emptyManifest
      )
    }

    let data = try bundledPreviewData()
    let driftedDescriptor = BundledProductReleaseDescriptor(
      resourceName: "identity-drift",
      resourceExtension: "json",
      expectedSHA256:
        BundledProductReleaseCatalogLoader.sha256Hex(data),
      expectedReleaseID: "preview.synthetic.product-release.drift",
      role: .demoOnly
    )
    XCTAssertThrowsError(
      try load(descriptor: driftedDescriptor, data: data)
    ) {
      XCTAssertEqual(
        $0 as? BundledProductReleaseCatalogError,
        .releaseIdentityMismatch(
          driftedDescriptor.resourceFilename
        )
      )
    }
  }

  func testDeclaredGuidanceAudioCannotSilentlyDisappear() throws {
    let data = try bundledPreviewData()
    let guidanceAudio = BundledGuidanceAudioReleaseDescriptor(
      selectionID: "calm",
      displayName: AppBundleGuidanceAudioDisplayName(
        japanese: "落ち着き",
        simplifiedChinese: "沉稳",
        english: "Calm"
      ),
      manifestResourceName: "test-guidance-audio",
      expectedManifestSHA256: String(repeating: "0", count: 64),
      expectedReleaseID: "test.guidance-audio.v1"
    )
    let descriptor = BundledProductReleaseDescriptor(
      resourceName: "synthetic-product-runtime-preview",
      resourceExtension: "json",
      expectedSHA256:
        BundledProductReleaseCatalogLoader.sha256Hex(data),
      expectedReleaseID: "preview.synthetic.product-release.v1",
      role: .demoOnly,
      guidanceAudioChoices: [guidanceAudio]
    )

    XCTAssertThrowsError(
      try load(descriptor: descriptor, data: data)
    ) {
      XCTAssertEqual(
        $0 as? BundledProductReleaseCatalogError,
        .missingGuidanceAudioManifest(
          guidanceAudio.manifestFilename
        )
      )
    }
  }

  func testGuidanceAudioChoicesRequireUniqueStableSelectionIDs() throws {
    let data = try bundledPreviewData()
    let first = BundledGuidanceAudioReleaseDescriptor(
      selectionID: "calm",
      displayName: AppBundleGuidanceAudioDisplayName(
        japanese: "落ち着き",
        simplifiedChinese: "沉稳",
        english: "Calm"
      ),
      manifestResourceName: "test-guidance-audio-calm",
      expectedManifestSHA256: String(repeating: "0", count: 64),
      expectedReleaseID: "test.guidance-audio.calm"
    )
    let second = BundledGuidanceAudioReleaseDescriptor(
      selectionID: "calm",
      displayName: AppBundleGuidanceAudioDisplayName(
        japanese: "直接",
        simplifiedChinese: "直接",
        english: "Direct"
      ),
      manifestResourceName: "test-guidance-audio-direct",
      expectedManifestSHA256: String(repeating: "1", count: 64),
      expectedReleaseID: "test.guidance-audio.direct"
    )
    let descriptor = BundledProductReleaseDescriptor(
      resourceName: "synthetic-product-runtime-preview",
      resourceExtension: "json",
      expectedSHA256:
        BundledProductReleaseCatalogLoader.sha256Hex(data),
      expectedReleaseID: "preview.synthetic.product-release.v1",
      role: .demoOnly,
      guidanceAudioChoices: [first, second]
    )

    XCTAssertThrowsError(
      try load(descriptor: descriptor, data: data)
    ) {
      XCTAssertEqual(
        $0 as? BundledProductReleaseCatalogError,
        .invalidGuidanceAudioDescriptor(
          descriptor.resourceFilename
        )
      )
    }
  }

  func testHashBoundPreDriveEvidenceLoadsForOneExactForegroundRelease()
    throws
  {
    let data = try releasedRoadData()
    let release = try KaidoProductReleaseArtifactCodec.decode(data)
    let evidenceData = try releasedPreDriveEvidenceData(for: release)
    let evidenceDescriptor = BundledPreDriveEvidenceDescriptor(
      manifestResourceName: "released-pre-drive-evidence",
      expectedManifestSHA256:
        BundledProductReleaseCatalogLoader.sha256Hex(evidenceData),
      expectedReleaseID: "test.pre-drive-evidence.catalog.v1"
    )
    let descriptor = BundledProductReleaseDescriptor(
      resourceName: "released-road-product",
      resourceExtension: "json",
      expectedSHA256:
        BundledProductReleaseCatalogLoader.sha256Hex(data),
      expectedReleaseID: "test.released-road.product",
      role: .foregroundNavigation,
      preDriveEvidence: evidenceDescriptor
    )

    let catalog = try BundledProductReleaseCatalogLoader.load(
      descriptors: [descriptor],
      preDriveEvidenceDataProvider: { _ in evidenceData },
      dataProvider: { _ in data }
    )
    let entry = try XCTUnwrap(
      catalog.foregroundNavigationEntries.first
    )
    let evidenceBundle = try XCTUnwrap(entry.preDriveEvidenceBundle)
    let date = try XCTUnwrap(
      ISO8601DateFormatter().date(
        from: "2026-07-25T12:30:00+09:00"
      )
    )
    let evidence = try evidenceBundle.evidence(
      for: PreDriveReviewSession(
        networkSnapshotID:
          release.navigation.bundle.routePlan.networkSnapshotID,
        routePlanID: release.navigation.bundle.routePlan.id,
        vehicleClass: .standard,
        paymentMethod: .etc
      ),
      at: date
    )

    XCTAssertEqual(evidence.vehicleClass, .standard)
    XCTAssertEqual(evidence.paymentMethod, .etc)
    XCTAssertEqual(
      evidenceBundle.manifest.releaseID,
      evidenceDescriptor.expectedReleaseID
    )
  }

  func testPreDriveEvidenceHashAndPresenceFailClosed() throws {
    let data = try releasedRoadData()
    let release = try KaidoProductReleaseArtifactCodec.decode(data)
    let evidenceData = try releasedPreDriveEvidenceData(for: release)
    let descriptor = BundledProductReleaseDescriptor(
      resourceName: "released-road-product",
      resourceExtension: "json",
      expectedSHA256:
        BundledProductReleaseCatalogLoader.sha256Hex(data),
      expectedReleaseID: "test.released-road.product",
      role: .foregroundNavigation,
      preDriveEvidence: BundledPreDriveEvidenceDescriptor(
        manifestResourceName: "released-pre-drive-evidence",
        expectedManifestSHA256: String(repeating: "0", count: 64),
        expectedReleaseID: "test.pre-drive-evidence.catalog.v1"
      )
    )

    XCTAssertThrowsError(
      try BundledProductReleaseCatalogLoader.load(
        descriptors: [descriptor]
      ) { _ in data }
    ) {
      XCTAssertEqual(
        $0 as? BundledProductReleaseCatalogError,
        .missingPreDriveEvidenceManifest(
          "released-pre-drive-evidence.json"
        )
      )
    }

    XCTAssertThrowsError(
      try BundledProductReleaseCatalogLoader.load(
        descriptors: [descriptor],
        preDriveEvidenceDataProvider: { _ in evidenceData }
      ) { _ in data }
    ) {
      XCTAssertEqual(
        $0 as? BundledProductReleaseCatalogError,
        .preDriveEvidenceManifestHashMismatch(
          "released-pre-drive-evidence.json"
        )
      )
    }
  }

  private func load(
    descriptor: BundledProductReleaseDescriptor,
    data: Data
  ) throws -> BundledProductReleaseCatalog {
    try BundledProductReleaseCatalogLoader.load(
      descriptors: [descriptor]
    ) { _ in data }
  }

  private func bundledPreviewData() throws -> Data {
    let url = try XCTUnwrap(
      Bundle.main.url(
        forResource: SyntheticProductRuntimeFixture.resourceName,
        withExtension: "json"
      )
    )
    return try Data(contentsOf: url)
  }

  private func releasedRoadDescriptor(
    resourceName: String,
    releaseID: String,
    data: Data
  ) -> BundledProductReleaseDescriptor {
    BundledProductReleaseDescriptor(
      resourceName: resourceName,
      resourceExtension: "json",
      expectedSHA256:
        BundledProductReleaseCatalogLoader.sha256Hex(data),
      expectedReleaseID: releaseID,
      role: .foregroundNavigation
    )
  }

  private func releasedRoadData(
    releaseID: String = "test.released-road.product"
  ) throws -> Data {
    var root = try XCTUnwrap(
      JSONSerialization.jsonObject(with: bundledPreviewData())
        as? [String: Any]
    )
    root["release_id"] = releaseID
    root["runtime_use"] = [
      "evidence_scope": "RELEASED_ROAD",
      "live_input_policy": "FOREGROUND_WHEN_IN_USE",
    ]
    for releaseKey in ["navigation_release", "route_atlas_release"] {
      var nestedRelease = try XCTUnwrap(
        root[releaseKey] as? [String: Any]
      )
      var registry = try XCTUnwrap(
        nestedRelease["source_registry"] as? [String: Any]
      )
      var references = try XCTUnwrap(
        registry["references"] as? [[String: Any]]
      )
      for index in references.indices {
        references[index]["licence_identifier"] =
          "TEST_REVIEWED_ROAD_ONLY"
      }
      registry["references"] = references
      nestedRelease["source_registry"] = registry
      root[releaseKey] = nestedRelease
    }
    return try JSONSerialization.data(withJSONObject: root)
  }

  private func releasedPreDriveEvidenceData(
    for release: KaidoProductRelease
  ) throws -> Data {
    let routePlan = release.navigation.bundle.routePlan
    let manifest = PreDriveEvidenceBundleManifest(
      releaseID: "test.pre-drive-evidence.catalog.v1",
      releasedAt: "2026-07-25T12:15:00+09:00",
      evidenceScope: .releasedRoad,
      productReleaseID: release.releaseID,
      navigationReleaseID: release.navigation.releaseID,
      networkSnapshotID: routePlan.networkSnapshotID,
      routePlanID: routePlan.id,
      sourceRegistry: [
        PreDriveEvidenceSourceReference(
          id: "test.pre-drive-source.tariff",
          roles: [.tariffQuery],
          authorityName: "Test tariff authority",
          sourceURL: "https://example.com/tariff",
          contentSHA256: String(repeating: "a", count: 64),
          checkedAt: "2026-07-25T11:30:00+09:00",
          reviewerID: "test.reviewer.tariff",
          reviewedAt: "2026-07-25T12:10:00+09:00"
        ),
        PreDriveEvidenceSourceReference(
          id: "test.pre-drive-source.passage",
          roles: [.passageReview],
          authorityName: "Test passage authority",
          sourceURL: "https://example.com/passage",
          contentSHA256: String(repeating: "b", count: 64),
          checkedAt: "2026-07-25T11:35:00+09:00",
          reviewerID: "test.reviewer.passage",
          reviewedAt: "2026-07-25T12:10:00+09:00"
        ),
      ],
      records: [
        PreDriveEvidenceRecord(
          id: "test.pre-drive-record.standard-etc",
          validFrom: "2026-07-25T12:00:00+09:00",
          expiresAt: "2026-07-26T00:00:00+09:00",
          sourceReferenceIDs: [
            "test.pre-drive-source.tariff",
            "test.pre-drive-source.passage",
          ],
          evidence: PreDriveReviewEvidence(
            evaluatedAt: "2026-07-25T11:45:00+09:00",
            networkSnapshotID: routePlan.networkSnapshotID,
            routePlanID: routePlan.id,
            vehicleClass: .standard,
            paymentMethod: .etc,
            passageEvidence: .noKnownConflictRealtimeUnconfirmed,
            tariffQuotes: [
              TariffQuote(
                id: "test.tariff.standard-etc.active",
                entryFacilityID: routePlan.entryFacilityID,
                exitFacilityID: routePlan.exitFacilityID,
                vehicleClass: .standard,
                paymentMethod: .etc,
                tariffVersionID: "test.tariff.v1",
                tariffVersionStatus: .active,
                tariffDistanceKM: 24.8,
                estimatedAmountYen: 1_320,
                evidenceStatus: .verifiedQuery,
                checkedAt: "2026-07-25T11:30:00+09:00",
                officialQueryReference: "https://example.com/tariff"
              )
            ]
          )
        )
      ]
    )
    return try PreDriveEvidenceBundleCodec.encode(
      manifest,
      context: PreDriveEvidenceBundleContext(
        productReleaseID: release.releaseID,
        productReleasedAt: release.releasedAt,
        navigationReleaseID: release.navigation.releaseID,
        routePlan: routePlan,
        evidenceScope: .releasedRoad
      )
    )
  }
}
