import CryptoKit
import Foundation
import KaidoAppleAdapters
import KaidoDomain
import KaidoNavigation
import KaidoPresentation
import Testing

@Test("Product release round-trips one exact navigation and atlas authority")
func kaidoProductReleaseRoundTrips() throws {
  let navigationFixture = navigationReleaseBundleFixture()
  let navigationArtifact = navigationReleaseArtifact(navigationFixture)
  let atlasArtifact = productRouteAtlasArtifact(
    navigationFixture,
    includeIncomingApproach: true
  )
  let artifact = KaidoProductReleaseArtifact(
    releaseID: "test.product-release.v1",
    releasedAt: "2026-07-24T12:00:00+09:00",
    navigationRelease: navigationArtifact,
    routeAtlasRelease: atlasArtifact
  )

  let data = try KaidoProductReleaseArtifactCodec.encode(artifact)
  let repeatedData = try KaidoProductReleaseArtifactCodec.encode(artifact)
  let release = try KaidoProductReleaseArtifactCodec.decode(data)

  #expect(data == repeatedData)
  #expect(release.releaseID == artifact.releaseID)
  #expect(release.navigation.bundle.routePlan == navigationFixture.routePlan)
  #expect(release.routeAtlas.routePlan == navigationFixture.routePlan)
  #expect(release.routeAtlas.topologySlice.edges.count == 5)
  #expect(release.runtimeUse == .syntheticTestOnlyDisabled)
  #expect(release.foregroundLiveInputAuthority == nil)
}

@Test("Product release blocks an editor approach absent from released atlas topology")
func kaidoProductReleaseRequiresEditorAtlasCoverage() throws {
  let navigationFixture = navigationReleaseBundleFixture()
  let navigationArtifact = navigationReleaseArtifact(navigationFixture)
  let atlasArtifact = productRouteAtlasArtifact(
    navigationFixture,
    includeIncomingApproach: false
  )
  _ = try RouteAtlasRelease(artifact: atlasArtifact)
  let artifact = KaidoProductReleaseArtifact(
    releaseID: "test.product-release.missing-editor-approach",
    releasedAt: "2026-07-24T12:00:00+09:00",
    navigationRelease: navigationArtifact,
    routeAtlasRelease: atlasArtifact
  )

  do {
    _ = try KaidoProductRelease(artifact: artifact)
    Issue.record("Expected the uncovered editor approach to block product release")
  } catch KaidoProductReleaseError.invalid(let issues) {
    #expect(
      issues.contains(
        .missingAtlasEditorEntity(.incomingApproach, "test.approach.loop")
      )
    )
    #expect(issues.count == 1)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Individually valid releases cannot cross snapshot or RoutePlan identity")
func kaidoProductReleaseRejectsIndependentReleaseDrift() throws {
  let navigationFixture = navigationReleaseBundleFixture()
  let navigationArtifact = navigationReleaseArtifact(navigationFixture)
  let otherAtlas = routeAtlasFixture()
  let atlasArtifact = RouteAtlasReleaseArtifact(
    networkSnapshot: otherAtlas.networkSnapshot,
    routePlan: otherAtlas.routePlan,
    sourceRegistry: RouteAtlasSourceRegistry(
      references: otherAtlas.sourceRegistry.references.map { source in
        RouteAtlasSourceReference(
          id: source.id,
          roles: source.roles,
          authorityName: source.authorityName,
          sourceURL: source.sourceURL,
          contentSHA256: source.contentSHA256,
          checkedAt: source.checkedAt,
          licenceIdentifier: "SYNTHETIC_TEST_ONLY"
        )
      }
    ),
    topologySlice: otherAtlas.topologySlice,
    definition: otherAtlas.definition
  )
  _ = try NavigationRelease(artifact: navigationArtifact)
  _ = try RouteAtlasRelease(artifact: atlasArtifact)

  let artifact = KaidoProductReleaseArtifact(
    releaseID: "test.product-release.drift",
    releasedAt: "2026-07-24T12:00:00+09:00",
    navigationRelease: navigationArtifact,
    routeAtlasRelease: atlasArtifact
  )
  do {
    _ = try KaidoProductRelease(artifact: artifact)
    Issue.record("Expected independently valid release drift to fail")
  } catch KaidoProductReleaseError.invalid(let issues) {
    #expect(issues.contains(.networkSnapshotMismatch))
    #expect(issues.contains(.routePlanMismatch))
    #expect(issues.count == 2)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Product release rejects an unknown schema and future navigation release")
func kaidoProductReleaseRejectsSchemaAndChronologyDrift() {
  let navigationFixture = navigationReleaseBundleFixture()
  let validNavigation = navigationReleaseArtifact(navigationFixture)
  let futureNavigation = NavigationReleaseArtifact(
    releaseID: validNavigation.releaseID,
    releasedAt: "2026-07-25T12:00:00+09:00",
    editorCatalogID: validNavigation.editorCatalogID,
    networkSnapshot: validNavigation.networkSnapshot,
    routePlan: validNavigation.routePlan,
    sourceRegistry: validNavigation.sourceRegistry,
    assetEvidence: validNavigation.assetEvidence,
    editorCatalog: validNavigation.editorCatalog,
    editorPresentationCatalog: validNavigation.editorPresentationCatalog,
    runtimePolicy: validNavigation.runtimePolicy,
    matcherCorridor: validNavigation.matcherCorridor,
    decisionZones: validNavigation.decisionZones,
    releasedGuidance: validNavigation.releasedGuidance,
    junctionViews: validNavigation.junctionViews
  )
  let artifact = KaidoProductReleaseArtifact(
    schemaVersion: "7.0",
    releaseID: "test.product-release.future-navigation",
    releasedAt: "2026-07-24T12:00:00+09:00",
    navigationRelease: futureNavigation,
    routeAtlasRelease: productRouteAtlasArtifact(
      navigationFixture,
      includeIncomingApproach: true
    )
  )

  do {
    _ = try KaidoProductRelease(artifact: artifact)
    Issue.record("Expected schema and chronology drift to block product release")
  } catch KaidoProductReleaseError.invalid(let issues) {
    #expect(issues.contains(.invalidArtifactSchemaVersion))
    #expect(issues.contains(.navigationReleaseAfterProductRelease))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Product release requires a finite positive actual route distance")
func kaidoProductReleaseRequiresActualRouteDistance() {
  let validFixture = navigationReleaseBundleFixture()
  let routePlan = RoutePlan(
    id: validFixture.routePlan.id,
    networkSnapshotID: validFixture.routePlan.networkSnapshotID,
    entryFacilityID: validFixture.routePlan.entryFacilityID,
    exitFacilityID: validFixture.routePlan.exitFacilityID,
    recoveryPolicy: validFixture.routePlan.recoveryPolicy,
    occurrences: validFixture.routePlan.occurrences
  )
  let fixture = NavigationReleaseBundleFixture(
    networkSnapshot: validFixture.networkSnapshot,
    routePlan: routePlan,
    editorCatalog: validFixture.editorCatalog,
    editorPresentationCatalog: validFixture.editorPresentationCatalog,
    runtimePolicy: validFixture.runtimePolicy,
    matcherCorridor: validFixture.matcherCorridor,
    decisionZones: validFixture.decisionZones,
    releasedGuidance: validFixture.releasedGuidance,
    junctionViews: validFixture.junctionViews
  )
  let artifact = KaidoProductReleaseArtifact(
    releaseID: "test.product-release.missing-actual-distance",
    releasedAt: "2026-07-24T12:00:00+09:00",
    navigationRelease: navigationReleaseArtifact(fixture),
    routeAtlasRelease: productRouteAtlasArtifact(
      fixture,
      includeIncomingApproach: true
    )
  )

  do {
    _ = try KaidoProductRelease(artifact: artifact)
    Issue.record("Expected missing actual distance to block product release")
  } catch KaidoProductReleaseError.invalid(let issues) {
    #expect(issues == [.actualRouteDistanceUnavailable])
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Synthetic product evidence cannot request foreground live input")
func syntheticProductReleaseCannotRequestLiveInput() throws {
  let fixture = navigationReleaseBundleFixture()
  let artifact = KaidoProductReleaseArtifact(
    releaseID: "test.product-release.synthetic-live-input",
    releasedAt: "2026-07-24T12:00:00+09:00",
    runtimeUse: KaidoProductRuntimeUseDeclaration(
      evidenceScope: .syntheticTestOnly,
      liveInputPolicy: .foregroundWhenInUse
    ),
    navigationRelease: navigationReleaseArtifact(fixture),
    routeAtlasRelease: productRouteAtlasArtifact(
      fixture,
      includeIncomingApproach: true
    )
  )

  do {
    _ = try KaidoProductRelease(artifact: artifact)
    Issue.record("Expected synthetic live input to fail closed")
  } catch KaidoProductReleaseError.invalid(let issues) {
    #expect(
      issues == [
        .invalidRuntimeUse(.syntheticLiveInputForbidden)
      ]
    )
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Product release requires an explicit runtime-use declaration")
func productReleaseRequiresRuntimeUse() {
  let fixture = navigationReleaseBundleFixture()
  let artifact = KaidoProductReleaseArtifact(
    releaseID: "test.product-release.missing-runtime-use",
    releasedAt: "2026-07-24T12:00:00+09:00",
    runtimeUse: nil,
    navigationRelease: navigationReleaseArtifact(fixture),
    routeAtlasRelease: productRouteAtlasArtifact(
      fixture,
      includeIncomingApproach: true
    )
  )

  do {
    _ = try KaidoProductRelease(artifact: artifact)
    Issue.record("Expected missing runtime use to fail closed")
  } catch KaidoProductReleaseError.invalid(let issues) {
    #expect(issues == [.missingRuntimeUse])
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Only a validated released-road product mints foreground authority")
func releasedRoadProductMintsForegroundAuthority() throws {
  let fixture = navigationReleaseBundleFixture()
  let artifact = KaidoProductReleaseArtifact(
    releaseID: "test.product-release.released-road",
    releasedAt: "2026-07-24T12:00:00+09:00",
    runtimeUse: KaidoProductRuntimeUseDeclaration(
      evidenceScope: .releasedRoad,
      liveInputPolicy: .foregroundWhenInUse
    ),
    navigationRelease: productNavigationReleaseArtifact(
      fixture,
      licenceIdentifier: "TEST_REVIEWED_ROAD_ONLY"
    ),
    routeAtlasRelease: productRouteAtlasArtifact(
      fixture,
      includeIncomingApproach: true,
      licenceIdentifier: "TEST_REVIEWED_ROAD_ONLY"
    )
  )

  let release = try KaidoProductRelease(artifact: artifact)
  let authority = try #require(release.foregroundLiveInputAuthority)

  #expect(release.runtimeUseEvaluation.foregroundLiveInputAdmitted)
  #expect(authority.runtimeIdentity == release.runtimeIdentity)
  #expect(release.runtimeIdentity.productReleaseID == artifact.releaseID)
  #expect(release.runtimeIdentity.navigationReleaseID == artifact.navigationRelease.releaseID)
  #expect(release.runtimeIdentity.runtimePolicyID == fixture.runtimePolicy.id)
  #expect(release.runtimeIdentity.networkSnapshotID == fixture.networkSnapshot.id)
  #expect(release.runtimeIdentity.routePlanID == fixture.routePlan.id)
  #expect(release.runtimeIdentity.matcherCorridorID == fixture.matcherCorridor.id)
}

@Test("Product author assembles only one exact released-road foreground artifact")
func productReleaseAuthorBuildsReleasedRoadArtifact() throws {
  let fixture = navigationReleaseBundleFixture()
  let navigationArtifact = productNavigationReleaseArtifact(
    fixture,
    licenceIdentifier: "TEST_REVIEWED_ROAD_ONLY"
  )
  let atlasArtifact = productRouteAtlasArtifact(
    fixture,
    includeIncomingApproach: true,
    licenceIdentifier: "TEST_REVIEWED_ROAD_ONLY"
  )
  let configuration = KaidoProductReleaseAuthoringConfiguration(
    releaseID: "test.product-release.authored",
    releasedAt: "2026-07-24T12:30:00+09:00"
  )

  let configurationData =
    try KaidoProductReleaseAuthoringConfigurationCodec.encode(
      configuration
    )
  let repeatedConfigurationData =
    try KaidoProductReleaseAuthoringConfigurationCodec.encode(
      configuration
    )
  let decodedConfiguration =
    try KaidoProductReleaseAuthoringConfigurationCodec.decode(
      configurationData
    )
  let artifact = try KaidoProductReleaseAuthor.buildArtifact(
    navigationRelease: navigationArtifact,
    routeAtlasRelease: atlasArtifact,
    configuration: decodedConfiguration
  )
  let encoded = try KaidoProductReleaseArtifactCodec.encode(artifact)
  let release = try KaidoProductReleaseArtifactCodec.decode(encoded)

  #expect(configurationData == repeatedConfigurationData)
  #expect(decodedConfiguration == configuration)
  #expect(artifact.navigationRelease == navigationArtifact)
  #expect(artifact.routeAtlasRelease == atlasArtifact)
  #expect(
    artifact.runtimeUse
      == KaidoProductRuntimeUseDeclaration(
        evidenceScope: .releasedRoad,
        liveInputPolicy: .foregroundWhenInUse
      )
  )
  #expect(release.releaseID == configuration.releaseID)
  #expect(release.foregroundLiveInputAuthority != nil)
}

@Test("Product author never promotes synthetic inputs")
func productReleaseAuthorRejectsSyntheticInputs() {
  let fixture = navigationReleaseBundleFixture()
  let configuration = KaidoProductReleaseAuthoringConfiguration(
    releaseID: "test.product-release.no-synthetic-promotion",
    releasedAt: "2026-07-24T12:30:00+09:00"
  )

  do {
    _ = try KaidoProductReleaseAuthor.buildArtifact(
      navigationRelease: navigationReleaseArtifact(fixture),
      routeAtlasRelease: productRouteAtlasArtifact(
        fixture,
        includeIncomingApproach: true
      ),
      configuration: configuration
    )
    Issue.record("Expected synthetic inputs to fail released-road authoring")
  } catch KaidoProductReleaseAuthoringError.invalidProductRelease(
    let issues
  ) {
    #expect(
      issues.contains {
        $0.code == "PRODUCT_RUNTIME_SOURCE_SCOPE_MISMATCH"
      }
    )
    #expect(
      !issues.contains {
        $0.code == "SYNTHETIC_PRODUCT_LIVE_INPUT_FORBIDDEN"
      }
    )
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Product author rechecks editor coverage across valid nested releases")
func productReleaseAuthorRejectsJointCoverageDrift() {
  let fixture = navigationReleaseBundleFixture()
  let configuration = KaidoProductReleaseAuthoringConfiguration(
    releaseID: "test.product-release.joint-drift",
    releasedAt: "2026-07-24T12:30:00+09:00"
  )

  do {
    _ = try KaidoProductReleaseAuthor.buildArtifact(
      navigationRelease: productNavigationReleaseArtifact(
        fixture,
        licenceIdentifier: "TEST_REVIEWED_ROAD_ONLY"
      ),
      routeAtlasRelease: productRouteAtlasArtifact(
        fixture,
        includeIncomingApproach: false,
        licenceIdentifier: "TEST_REVIEWED_ROAD_ONLY"
      ),
      configuration: configuration
    )
    Issue.record("Expected editor-atlas coverage drift to block authoring")
  } catch KaidoProductReleaseAuthoringError.invalidProductRelease(
    let issues
  ) {
    #expect(
      issues.contains(
        .missingAtlasEditorEntity(
          .incomingApproach,
          "test.approach.loop"
        )
      )
    )
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Product author rejects invalid metadata before release assembly")
func productReleaseAuthorRejectsInvalidConfiguration() {
  let fixture = navigationReleaseBundleFixture()
  let configuration = KaidoProductReleaseAuthoringConfiguration(
    schemaVersion: "2.0",
    releaseID: " ",
    releasedAt: "not-a-date"
  )

  do {
    _ = try KaidoProductReleaseAuthor.buildArtifact(
      navigationRelease: navigationReleaseArtifact(fixture),
      routeAtlasRelease: productRouteAtlasArtifact(
        fixture,
        includeIncomingApproach: true
      ),
      configuration: configuration
    )
    Issue.record("Expected invalid authoring metadata to fail")
  } catch KaidoProductReleaseAuthoringError.invalidConfiguration(
    let issues
  ) {
    #expect(
      issues == [
        .invalidConfigurationSchemaVersion,
        .invalidReleaseIdentity,
      ]
    )
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Product author classifies invalid nested releases before the joint gate")
func productReleaseAuthorRejectsInvalidNestedInputs() {
  let fixture = navigationReleaseBundleFixture()
  let validNavigation = productNavigationReleaseArtifact(
    fixture,
    licenceIdentifier: "TEST_REVIEWED_ROAD_ONLY"
  )
  let invalidNavigation = NavigationReleaseArtifact(
    schemaVersion: "999.0",
    releaseID: validNavigation.releaseID,
    releasedAt: validNavigation.releasedAt,
    editorCatalogID: validNavigation.editorCatalogID,
    networkSnapshot: validNavigation.networkSnapshot,
    routePlan: validNavigation.routePlan,
    sourceRegistry: validNavigation.sourceRegistry,
    assetEvidence: validNavigation.assetEvidence,
    editorCatalog: validNavigation.editorCatalog,
    editorPresentationCatalog: validNavigation.editorPresentationCatalog,
    runtimePolicy: validNavigation.runtimePolicy,
    matcherCorridor: validNavigation.matcherCorridor,
    decisionZones: validNavigation.decisionZones,
    releasedGuidance: validNavigation.releasedGuidance,
    junctionViews: validNavigation.junctionViews
  )
  let validAtlas = productRouteAtlasArtifact(
    fixture,
    includeIncomingApproach: true,
    licenceIdentifier: "TEST_REVIEWED_ROAD_ONLY"
  )
  let invalidAtlas = RouteAtlasReleaseArtifact(
    schemaVersion: "2.0",
    networkSnapshot: validAtlas.networkSnapshot,
    routePlan: validAtlas.routePlan,
    sourceRegistry: validAtlas.sourceRegistry,
    topologySlice: validAtlas.topologySlice,
    definition: validAtlas.definition
  )
  let configuration = KaidoProductReleaseAuthoringConfiguration(
    releaseID: "test.product-release.invalid-nested-input",
    releasedAt: "2026-07-24T12:30:00+09:00"
  )

  do {
    _ = try KaidoProductReleaseAuthor.buildArtifact(
      navigationRelease: invalidNavigation,
      routeAtlasRelease: validAtlas,
      configuration: configuration
    )
    Issue.record("Expected invalid navigation input to fail independently")
  } catch KaidoProductReleaseAuthoringError.invalidNavigationRelease(
    let issues
  ) {
    #expect(issues == [.invalidArtifactSchemaVersion])
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  do {
    _ = try KaidoProductReleaseAuthor.buildArtifact(
      navigationRelease: validNavigation,
      routeAtlasRelease: invalidAtlas,
      configuration: configuration
    )
    Issue.record("Expected invalid Route Atlas input to fail independently")
  } catch KaidoProductReleaseAuthoringError.invalidRouteAtlasRelease(
    let issues
  ) {
    #expect(issues == [.invalidArtifactSchemaVersion])
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("App bundle staging derives one deterministic compile-time descriptor")
func appBundleStagingPreparesForegroundProduct() throws {
  let productData = try appBundleReleasedProductData()
  let configuration = AppBundleReleaseStagingConfiguration(
    descriptorSymbol: "releasedK7AobaKohoku",
    productResourceName: "k7-aoba-kohoku-product-release"
  )

  let configurationData =
    try AppBundleReleaseStagingConfigurationCodec.encode(configuration)
  let decodedConfiguration =
    try AppBundleReleaseStagingConfigurationCodec.decode(configurationData)
  let package = try AppBundleReleaseStagingAuthor.prepare(
    configuration: decodedConfiguration,
    productArtifactData: productData
  )
  let repeated = try AppBundleReleaseStagingAuthor.prepare(
    configuration: decodedConfiguration,
    productArtifactData: productData
  )
  let manifestData =
    try AppBundleReleaseStagingManifestCodec.encode(package.manifest)
  let decodedManifest =
    try AppBundleReleaseStagingManifestCodec.decode(manifestData)

  #expect(package == repeated)
  #expect(decodedConfiguration == configuration)
  #expect(decodedManifest == package.manifest)
  #expect(
    decodedConfiguration.schemaVersion
      == AppBundleReleaseStagingConfiguration.currentSchemaVersion
  )
  #expect(
    decodedManifest.schemaVersion
      == AppBundleReleaseStagingManifest.currentSchemaVersion
  )
  #expect(package.manifest.descriptor.role == .foregroundNavigation)
  #expect(
    package.manifest.descriptor.expectedReleaseID
      == "test.product-release.app-bundle"
  )
  #expect(
    package.manifest.descriptor.expectedSHA256
      == testSHA256Hex(productData)
  )
  #expect(package.manifest.descriptor.guidanceAudioChoices.isEmpty)
  #expect(
    package.manifest.resources
      == [
        AppBundleStagedResourceRecord(
          relativePath:
            "Resources/k7-aoba-kohoku-product-release.json",
          kind: .productRelease,
          sha256: testSHA256Hex(productData),
          byteCount: productData.count
        )
      ]
  )
  #expect(
    package.files.map(\.relativePath)
      == [
        "Resources/k7-aoba-kohoku-product-release.json",
        "Sources/BundledProductReleaseDescriptor+releasedK7AobaKohoku.swift",
        "app-bundle-staging-manifest.json",
      ]
  )
  let generatedSource = try #require(
    package.files.first {
      $0.relativePath.hasPrefix("Sources/")
    }
  )
  let sourceText = try #require(
    String(data: generatedSource.data, encoding: .utf8)
  )
  #expect(
    sourceText.contains(
      "static let releasedK7AobaKohoku"
    )
  )
  #expect(sourceText.contains("role: .foregroundNavigation"))
}

@Test("App bundle staging pins signed evidence update trust roots")
func appBundleStagingPinsPreDriveEvidenceUpdateTrust() throws {
  let productData = try appBundleReleasedProductData()
  let keyPair = try PreDriveEvidenceUpdateCodec.generateSigningKeyPair(
    keyID: "test.pre-drive-evidence.2026"
  )
  let endpoint = PreDriveEvidenceUpdateEndpoint(
    url: "https://updates.kaido.test/evidence/k7.json"
  )
  let configuration = AppBundleReleaseStagingConfiguration(
    descriptorSymbol: "releasedK7WithEvidenceTrust",
    productResourceName: "k7-product",
    preDriveEvidenceUpdateTrustKeys: [keyPair.trustKey],
    preDriveEvidenceUpdateEndpoint: endpoint
  )

  let package = try AppBundleReleaseStagingAuthor.prepare(
    configuration: configuration,
    productArtifactData: productData
  )
  let generatedSource = try #require(
    package.files.first { $0.relativePath.hasPrefix("Sources/") }
  )
  let sourceText = try #require(
    String(data: generatedSource.data, encoding: .utf8)
  )

  #expect(
    package.manifest.descriptor.preDriveEvidenceUpdateTrustKeys
      == [keyPair.trustKey]
  )
  #expect(
    package.manifest.descriptor.preDriveEvidenceUpdateEndpoint
      == endpoint
  )
  #expect(
    sourceText.contains(
      "PreDriveEvidenceUpdateTrustKey("
    )
  )
  #expect(
    sourceText.contains(
      "keyID: \"test.pre-drive-evidence.2026\""
    )
  )
  #expect(
    sourceText.contains(
      "publicKeyBase64: \"\(keyPair.trustKey.publicKeyBase64)\""
    )
  )
  #expect(
    sourceText.contains(
      "PreDriveEvidenceUpdateEndpoint("
    )
  )
  #expect(
    sourceText.contains(
      "url: \"https://updates.kaido.test/evidence/k7.json\""
    )
  )
}

@Test("App bundle staging rejects invalid signed update trust registries")
func appBundleStagingRejectsInvalidPreDriveEvidenceUpdateTrust() throws {
  let keyPair = try PreDriveEvidenceUpdateCodec.generateSigningKeyPair(
    keyID: "test.pre-drive-evidence.duplicate"
  )
  let configuration = AppBundleReleaseStagingConfiguration(
    descriptorSymbol: "releasedK7WithInvalidTrust",
    productResourceName: "k7-product",
    preDriveEvidenceUpdateTrustKeys: [
      keyPair.trustKey,
      keyPair.trustKey,
    ]
  )

  do {
    _ = try AppBundleReleaseStagingAuthor.prepare(
      configuration: configuration,
      productArtifactData: try appBundleReleasedProductData()
    )
    Issue.record("Expected duplicate signed update trust to fail")
  } catch AppBundleReleaseStagingError.invalidConfiguration(let issues) {
    #expect(issues == [.invalidPreDriveEvidenceUpdateTrustKeys])
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("App bundle staging rejects invalid or untrusted update endpoints")
func appBundleStagingRejectsInvalidPreDriveEvidenceUpdateEndpoint()
  throws
{
  let keyPair = try PreDriveEvidenceUpdateCodec.generateSigningKeyPair(
    keyID: "test.pre-drive-evidence.endpoint"
  )
  let productData = try appBundleReleasedProductData()

  do {
    _ = try AppBundleReleaseStagingAuthor.prepare(
      configuration: AppBundleReleaseStagingConfiguration(
        descriptorSymbol: "releasedK7WithHTTPUpdate",
        productResourceName: "k7-product",
        preDriveEvidenceUpdateTrustKeys: [keyPair.trustKey],
        preDriveEvidenceUpdateEndpoint: PreDriveEvidenceUpdateEndpoint(
          url: "http://updates.kaido.test/evidence/k7.json"
        )
      ),
      productArtifactData: productData
    )
    Issue.record("Expected a non-HTTPS update endpoint to fail")
  } catch AppBundleReleaseStagingError.invalidConfiguration(let issues) {
    #expect(issues == [.invalidPreDriveEvidenceUpdateEndpoint])
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  do {
    _ = try AppBundleReleaseStagingAuthor.prepare(
      configuration: AppBundleReleaseStagingConfiguration(
        descriptorSymbol: "releasedK7WithUntrustedUpdate",
        productResourceName: "k7-product",
        preDriveEvidenceUpdateEndpoint: PreDriveEvidenceUpdateEndpoint(
          url: "https://updates.kaido.test/evidence/k7.json"
        )
      ),
      productArtifactData: productData
    )
    Issue.record("Expected an endpoint without trust roots to fail")
  } catch AppBundleReleaseStagingError.invalidConfiguration(let issues) {
    #expect(
      issues == [.incompletePreDriveEvidenceUpdateConfiguration]
    )
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("App bundle staging rejects synthetic products and partial optional input")
func appBundleStagingRejectsNonForegroundInput() throws {
  let fixture = navigationReleaseBundleFixture()
  let syntheticData = try KaidoProductReleaseArtifactCodec.encode(
    KaidoProductReleaseArtifact(
      releaseID: "test.product-release.synthetic-staging",
      releasedAt: "2026-07-24T12:00:00+09:00",
      navigationRelease: navigationReleaseArtifact(fixture),
      routeAtlasRelease: productRouteAtlasArtifact(
        fixture,
        includeIncomingApproach: true
      )
    )
  )
  let configuration = AppBundleReleaseStagingConfiguration(
    descriptorSymbol: "releasedK7AobaKohoku",
    productResourceName: "k7-aoba-kohoku-product-release"
  )

  do {
    _ = try AppBundleReleaseStagingAuthor.prepare(
      configuration: configuration,
      productArtifactData: syntheticData
    )
    Issue.record("Expected synthetic product staging to fail")
  } catch AppBundleReleaseStagingError.foregroundProductRequired {
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  do {
    _ = try AppBundleReleaseStagingAuthor.prepare(
      configuration: AppBundleReleaseStagingConfiguration(
        descriptorSymbol: "releasedK7AobaKohoku",
        productResourceName: "k7-aoba-kohoku-product-release",
        guidanceAudioOptions: [
          appBundleGuidanceAudioOption(
            selectionID: "calm",
            manifestResourceName: "k7-guidance-audio"
          )
        ]
      ),
      productArtifactData: try appBundleReleasedProductData()
    )
    Issue.record("Expected partial guidance audio input to fail")
  } catch AppBundleReleaseStagingError.guidanceAudioInputMismatch {
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  do {
    _ = try AppBundleReleaseStagingAuthor.prepare(
      configuration: AppBundleReleaseStagingConfiguration(
        descriptorSymbol: "releasedK7AobaKohoku",
        productResourceName: "k7-aoba-kohoku-product-release",
        preDriveEvidenceManifestResourceName: "k7-pre-drive-evidence"
      ),
      productArtifactData: try appBundleReleasedProductData()
    )
    Issue.record("Expected partial pre-drive evidence input to fail")
  } catch AppBundleReleaseStagingError.preDriveEvidenceInputMismatch {
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("App bundle staging validates configuration before artifact admission")
func appBundleStagingRejectsInvalidConfiguration() throws {
  let configuration = AppBundleReleaseStagingConfiguration(
    schemaVersion: "3.0",
    descriptorSymbol: "class",
    productResourceName: "../product",
    guidanceAudioOptions: [
      appBundleGuidanceAudioOption(
        selectionID: " calm ",
        manifestResourceName: "../product"
      )
    ]
  )

  do {
    _ = try AppBundleReleaseStagingAuthor.prepare(
      configuration: configuration,
      productArtifactData: Data()
    )
    Issue.record("Expected invalid staging configuration to fail")
  } catch AppBundleReleaseStagingError.invalidConfiguration(let issues) {
    #expect(
      issues
        == [
          .invalidSchemaVersion,
          .invalidDescriptorSymbol,
          .invalidProductResourceName,
          .invalidGuidanceAudioOption,
          .duplicateManifestResourceName,
        ]
    )
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("App bundle staging retains one complete released guidance audio pack")
func appBundleStagingPreparesGuidanceAudio() throws {
  let productData = try appBundleReleasedProductData()
  let productRelease = try KaidoProductReleaseArtifactCodec.decode(
    productData
  )
  let baseFixture = guidanceAudioManifestFixture(productRelease)
  let releasedRecords = baseFixture.manifest.assets.map { record in
    GuidanceAudioAssetRecord(
      key: record.key,
      spokenText: record.spokenText,
      spokenTextSHA256: record.spokenTextSHA256,
      resourceFilename: record.resourceFilename,
      audioSHA256: record.audioSHA256,
      byteCount: record.byteCount,
      sampleRateHz: record.sampleRateHz,
      channelCount: record.channelCount,
      durationMilliseconds: record.durationMilliseconds,
      provenance: GuidanceAudioSynthesisProvenance(
        evidenceScope: .releasedAsset,
        generationMode: .localOpenWeight,
        engineID: "test.engine",
        engineVersion: "1.0.0",
        modelID: "test/model",
        modelRevision: String(repeating: "a", count: 40),
        modelArtifactKind: .originalCheckpoint,
        convertedModelLineage: nil,
        voiceID: record.provenance.voiceID,
        licenceIdentifier: "Apache-2.0",
        sourceURL:
          "https://example.com/test-guidance-audio/tree/"
          + String(repeating: "a", count: 40),
        redistributionDecision: .approvedForAppDistribution,
        redistributionReviewID: "test.redistribution-review.released",
        redistributionReviewSHA256:
          String(repeating: "b", count: 64),
        generatedAt: "2026-07-24T13:00:00+09:00",
        reviewedAt: "2026-07-24T14:00:00+09:00"
      ),
      review: record.review
    )
  }
  let manifest = GuidanceAudioReleaseManifest(
    releaseID: "test.guidance-audio.app-bundle.v1",
    releasedAt: "2026-07-24T15:00:00+09:00",
    productReleaseID: productRelease.releaseID,
    navigationReleaseID: productRelease.navigation.releaseID,
    networkSnapshotID:
      productRelease.navigation.bundle.networkSnapshot.id,
    routePlanID: productRelease.navigation.bundle.routePlan.id,
    assets: releasedRecords
  )
  let manifestData = try GuidanceAudioReleaseManifestCodec.encode(
    manifest,
    productRelease: productRelease,
    resourceProvider: { baseFixture.resources[$0] }
  )
  let configuration = AppBundleReleaseStagingConfiguration(
    descriptorSymbol: "releasedK7WithAudio",
    productResourceName: "k7-product",
    guidanceAudioOptions: [
      appBundleGuidanceAudioOption(
        selectionID: "calm",
        manifestResourceName: "k7-guidance-audio"
      )
    ]
  )

  let package = try AppBundleReleaseStagingAuthor.prepare(
    configuration: configuration,
    productArtifactData: productData,
    guidanceAudioManifestDataProvider: { _ in manifestData },
    guidanceAudioResourceProvider: {
      _,
      filename in baseFixture.resources[filename]
    }
  )
  let audioDescriptor = try #require(
    package.manifest.descriptor.guidanceAudioChoices.first
  )

  #expect(audioDescriptor.selectionID == "calm")
  #expect(
    audioDescriptor.expectedReleaseID
      == "test.guidance-audio.app-bundle.v1"
  )
  #expect(
    audioDescriptor.expectedManifestSHA256
      == testSHA256Hex(manifestData)
  )
  #expect(
    package.manifest.resources.count
      == 2 + Set(releasedRecords.map(\.resourceFilename)).count
  )
  #expect(
    package.manifest.resources.filter {
      $0.kind == .guidanceAudioWave
    }.count == Set(releasedRecords.map(\.resourceFilename)).count
  )
}

@Test("App bundle staging retains multiple independently selected audio packs")
func appBundleStagingPreparesMultipleGuidanceAudioChoices() throws {
  let productData = try appBundleReleasedProductData()
  let productRelease = try KaidoProductReleaseArtifactCodec.decode(
    productData
  )
  let baseFixture = guidanceAudioManifestFixture(productRelease)

  func releasedRecords(
    voiceID: String
  ) -> [GuidanceAudioAssetRecord] {
    let records = baseFixture.manifest.assets.map { record in
      return GuidanceAudioAssetRecord(
        key: record.key,
        spokenText: record.spokenText,
        spokenTextSHA256: record.spokenTextSHA256,
        resourceFilename: record.resourceFilename,
        audioSHA256: record.audioSHA256,
        byteCount: record.byteCount,
        sampleRateHz: record.sampleRateHz,
        channelCount: record.channelCount,
        durationMilliseconds: record.durationMilliseconds,
        provenance: GuidanceAudioSynthesisProvenance(
          evidenceScope: .releasedAsset,
          generationMode: .localOpenWeight,
          engineID: "test.engine",
          engineVersion: "1.0.0",
          modelID: "test/model",
          modelRevision: String(repeating: "a", count: 40),
          modelArtifactKind: .originalCheckpoint,
          convertedModelLineage: nil,
          voiceID: voiceID,
          licenceIdentifier: "Apache-2.0",
          sourceURL:
            "https://example.com/test-guidance-audio/tree/"
            + String(repeating: "a", count: 40),
          redistributionDecision: .approvedForAppDistribution,
          redistributionReviewID:
            "test.redistribution-review.\(voiceID)",
          redistributionReviewSHA256:
            String(repeating: "b", count: 64),
          generatedAt: "2026-07-24T13:00:00+09:00",
          reviewedAt: "2026-07-24T14:00:00+09:00"
        ),
        review: record.review
      )
    }
    return records
  }

  let calm = releasedRecords(voiceID: "calm")
  let direct = releasedRecords(voiceID: "direct")
  func manifest(
    releaseID: String,
    records: [GuidanceAudioAssetRecord]
  ) throws -> Data {
    try GuidanceAudioReleaseManifestCodec.encode(
      GuidanceAudioReleaseManifest(
        releaseID: releaseID,
        releasedAt: "2026-07-24T15:00:00+09:00",
        productReleaseID: productRelease.releaseID,
        navigationReleaseID: productRelease.navigation.releaseID,
        networkSnapshotID:
          productRelease.navigation.bundle.networkSnapshot.id,
        routePlanID: productRelease.navigation.bundle.routePlan.id,
        assets: records
      ),
      productRelease: productRelease,
      resourceProvider: { baseFixture.resources[$0] }
    )
  }
  let calmManifest = try manifest(
    releaseID: "test.guidance-audio.calm.v1",
    records: calm
  )
  let directManifest = try manifest(
    releaseID: "test.guidance-audio.direct.v1",
    records: direct
  )
  let configuration = AppBundleReleaseStagingConfiguration(
    descriptorSymbol: "releasedK7WithSelectableAudio",
    productResourceName: "k7-product",
    guidanceAudioOptions: [
      appBundleGuidanceAudioOption(
        selectionID: "calm",
        manifestResourceName: "k7-guidance-audio-calm"
      ),
      appBundleGuidanceAudioOption(
        selectionID: "direct",
        manifestResourceName: "k7-guidance-audio-direct"
      ),
    ]
  )

  let package = try AppBundleReleaseStagingAuthor.prepare(
    configuration: configuration,
    productArtifactData: productData,
    guidanceAudioManifestDataProvider: { resourceName in
      switch resourceName {
      case "k7-guidance-audio-calm":
        calmManifest
      case "k7-guidance-audio-direct":
        directManifest
      default:
        nil
      }
    },
    guidanceAudioResourceProvider: {
      _,
      filename in baseFixture.resources[filename]
    }
  )

  #expect(
    package.manifest.descriptor.guidanceAudioChoices.map(
      \.selectionID
    ) == ["calm", "direct"]
  )
  #expect(
    package.manifest.resources.filter {
      $0.kind == .guidanceAudioManifest
    }.count == 2
  )
  #expect(
    package.manifest.resources.filter {
      $0.kind == .guidanceAudioWave
    }.count == calm.count + direct.count
  )
  let logicalFilename = baseFixture.manifest.assets[0].resourceFilename
  #expect(
    package.files.contains {
      $0.relativePath == "Resources/calm--\(logicalFilename)"
    }
  )
  #expect(
    package.files.contains {
      $0.relativePath == "Resources/direct--\(logicalFilename)"
    }
  )

  do {
    _ = try AppBundleReleaseStagingAuthor.prepare(
      configuration: configuration,
      productArtifactData: productData,
      guidanceAudioManifestDataProvider: { _ in calmManifest },
      guidanceAudioResourceProvider: {
        _,
        filename in baseFixture.resources[filename]
      }
    )
    Issue.record("Expected duplicate audio release identity to fail")
  } catch AppBundleReleaseStagingError.duplicateGuidanceAudioReleaseID(
    let releaseID
  ) {
    #expect(releaseID == "test.guidance-audio.calm.v1")
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("App bundle staging pins one exact current pre-drive evidence bundle")
func appBundleStagingPreparesPreDriveEvidence() throws {
  let productData = try appBundleReleasedProductData()
  let productRelease = try KaidoProductReleaseArtifactCodec.decode(
    productData
  )
  let routePlan = productRelease.navigation.bundle.routePlan
  let evidenceManifest = PreDriveEvidenceBundleManifest(
    releaseID: "test.pre-drive-evidence.app-bundle.v1",
    releasedAt: "2026-07-24T12:45:00+09:00",
    evidenceScope: .releasedRoad,
    productReleaseID: productRelease.releaseID,
    navigationReleaseID: productRelease.navigation.releaseID,
    networkSnapshotID: routePlan.networkSnapshotID,
    routePlanID: routePlan.id,
    sourceRegistry: [
      PreDriveEvidenceSourceReference(
        id: "test.pre-drive-source.tariff",
        roles: [.tariffQuery],
        authorityName: "Test reviewed tariff authority",
        sourceURL: "https://example.com/tariff",
        contentSHA256: String(repeating: "a", count: 64),
        checkedAt: "2026-07-24T12:00:00+09:00",
        reviewerID: "test.reviewer.tariff",
        reviewedAt: "2026-07-24T12:40:00+09:00"
      ),
      PreDriveEvidenceSourceReference(
        id: "test.pre-drive-source.passage",
        roles: [.passageReview],
        authorityName: "Test reviewed passage authority",
        sourceURL: "https://example.com/passage",
        contentSHA256: String(repeating: "b", count: 64),
        checkedAt: "2026-07-24T12:05:00+09:00",
        reviewerID: "test.reviewer.passage",
        reviewedAt: "2026-07-24T12:40:00+09:00"
      ),
    ],
    records: [
      PreDriveEvidenceRecord(
        id: "test.pre-drive-record.standard-etc",
        validFrom: "2026-07-24T12:35:00+09:00",
        expiresAt: "2026-07-25T00:00:00+09:00",
        sourceReferenceIDs: [
          "test.pre-drive-source.tariff",
          "test.pre-drive-source.passage",
        ],
        evidence: PreDriveReviewEvidence(
          evaluatedAt: "2026-07-24T12:30:00+09:00",
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
              checkedAt: "2026-07-24T12:00:00+09:00",
              officialQueryReference: "https://example.com/tariff"
            )
          ]
        )
      )
    ]
  )
  let context = PreDriveEvidenceBundleContext(
    productReleaseID: productRelease.releaseID,
    productReleasedAt: productRelease.releasedAt,
    navigationReleaseID: productRelease.navigation.releaseID,
    routePlan: routePlan,
    evidenceScope: .releasedRoad
  )
  let evidenceData = try PreDriveEvidenceBundleCodec.encode(
    evidenceManifest,
    context: context
  )
  let configuration = AppBundleReleaseStagingConfiguration(
    descriptorSymbol: "releasedK7WithPreDriveEvidence",
    productResourceName: "k7-product",
    preDriveEvidenceManifestResourceName: "k7-pre-drive-evidence"
  )

  let package = try AppBundleReleaseStagingAuthor.prepare(
    configuration: configuration,
    productArtifactData: productData,
    preDriveEvidenceManifestData: evidenceData
  )
  let descriptor = try #require(
    package.manifest.descriptor.preDriveEvidence
  )

  #expect(
    descriptor.expectedReleaseID
      == "test.pre-drive-evidence.app-bundle.v1"
  )
  #expect(
    descriptor.expectedManifestSHA256 == testSHA256Hex(evidenceData)
  )
  #expect(
    package.manifest.resources
      .contains {
        $0.kind == .preDriveEvidenceManifest
          && $0.relativePath
            == "Resources/k7-pre-drive-evidence.json"
      }
  )
  let generatedSource = try #require(
    package.files.first { $0.relativePath.hasPrefix("Sources/") }
  )
  let sourceText = try #require(
    String(data: generatedSource.data, encoding: .utf8)
  )
  #expect(
    sourceText.contains(
      "AppBundlePreDriveEvidenceDescriptor("
    )
  )
}

@Test("Released-road runtime scope rejects mixed synthetic sources")
func releasedRoadRuntimeScopeRejectsSyntheticSources() {
  let evaluation = KaidoProductRuntimeUseEvaluator.evaluate(
    declaration: KaidoProductRuntimeUseDeclaration(
      evidenceScope: .releasedRoad,
      liveInputPolicy: .foregroundWhenInUse
    ),
    sources: [
      KaidoProductRuntimeSourceDescriptor(
        domain: .navigation,
        sourceID: "test.source.navigation",
        licenceIdentifier: "TEST_REVIEWED_ROAD_ONLY"
      ),
      KaidoProductRuntimeSourceDescriptor(
        domain: .routeAtlas,
        sourceID: "test.source.atlas",
        licenceIdentifier: "SYNTHETIC_TEST_ONLY"
      ),
    ]
  )

  #expect(!evaluation.isValid)
  #expect(!evaluation.foregroundLiveInputAdmitted)
  #expect(
    evaluation.issues == [
      .sourceScopeMismatch(.routeAtlas, sourceID: "test.source.atlas")
    ]
  )
}

@Test("Route Atlas evidence cannot postdate the product release")
func kaidoProductReleaseRejectsFutureAtlasEvidence() {
  let navigationFixture = navigationReleaseBundleFixture()
  let artifact = KaidoProductReleaseArtifact(
    releaseID: "test.product-release.future-atlas-evidence",
    releasedAt: "2026-07-24T12:00:00+09:00",
    navigationRelease: navigationReleaseArtifact(navigationFixture),
    routeAtlasRelease: productRouteAtlasArtifact(
      navigationFixture,
      includeIncomingApproach: true,
      checkedAt: "2026-07-25"
    )
  )

  do {
    _ = try KaidoProductRelease(artifact: artifact)
    Issue.record("Expected future Route Atlas evidence to block product release")
  } catch KaidoProductReleaseError.invalid(let issues) {
    #expect(
      issues.contains(
        .atlasEvidenceAfterProductRelease("SOURCE:test.source.product-topology")
      )
    )
    #expect(
      issues.contains(
        .atlasEvidenceAfterProductRelease(
          "TOPOLOGY:test.topology.product-release"
        )
      )
    )
    #expect(
      issues.contains(
        .atlasEvidenceAfterProductRelease("LAYOUT:test.atlas.product-release")
      )
    )
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Product runtime consumes only the joint release runtime policy")
func kaidoProductRuntimeUsesJointReleaseAuthority() async throws {
  let navigationFixture = navigationReleaseBundleFixture()
  let release = try KaidoProductRelease(
    artifact: KaidoProductReleaseArtifact(
      releaseID: "test.product-release.runtime",
      releasedAt: "2026-07-24T12:00:00+09:00",
      navigationRelease: navigationReleaseArtifact(navigationFixture),
      routeAtlasRelease: productRouteAtlasArtifact(
        navigationFixture,
        includeIncomingApproach: true
      )
    )
  )

  let runtime = try KaidoProductNavigationRuntime(release: release)
  let started = await runtime.session.start()
  let finish = await runtime.session.finishDrive()

  #expect(runtime.productReleaseID == release.releaseID)
  #expect(runtime.navigationReleaseID == release.navigation.releaseID)
  #expect(runtime.networkSnapshotID == navigationFixture.networkSnapshot.id)
  #expect(runtime.routePlanID == navigationFixture.routePlan.id)
  #expect(runtime.routeAtlas == release.routeAtlas)
  #expect(runtime.journeyPlan.productReleaseID == release.releaseID)
  #expect(runtime.journeyPlan.routePlanID == navigationFixture.routePlan.id)
  #expect(runtime.journeyPlan.accessLeg == nil)
  #expect(runtime.journeyPlan.finishPolicy == .finishOnRequest)
  #expect(
    runtime.journeyPlan.precomputedEgressOptions
      == navigationFixture.runtimePolicy.egressOptions
  )
  #expect(
    runtime.release.navigation.bundle.runtimePolicy
      == navigationFixture.runtimePolicy
  )
  #expect(started.activeRoutePlanID == navigationFixture.routePlan.id)
  #expect(started.currentOccurrenceID == navigationFixture.routePlan.occurrences.first?.id)
  #expect(started.journeyPhase == .planning)
  #expect(started.strictRouteAutoCommitAllowed == false)
  #expect(finish.egress.status == .active)
  #expect(finish.egress.exitFacilityID == navigationFixture.routePlan.exitFacilityID)
}

func productRouteAtlasArtifact(
  _ fixture: NavigationReleaseBundleFixture,
  includeIncomingApproach: Bool,
  checkedAt: String = "2026-07-23",
  licenceIdentifier: String = "SYNTHETIC_TEST_ONLY"
) -> RouteAtlasReleaseArtifact {
  let topologySourceID = "test.source.product-topology"
  let layoutSourceID = "test.source.product-layout"
  let sourceRegistry = RouteAtlasSourceRegistry(
    references: [
      RouteAtlasSourceReference(
        id: topologySourceID,
        roles: [.topologyEvidence],
        authorityName: "Synthetic product topology authority",
        sourceURL: "https://example.com/test-product-topology",
        contentSHA256: String(repeating: "b", count: 64),
        checkedAt: checkedAt,
        licenceIdentifier: licenceIdentifier
      ),
      RouteAtlasSourceReference(
        id: layoutSourceID,
        roles: [.layoutEvidence],
        authorityName: "Synthetic product layout authority",
        sourceURL: "https://example.com/test-product-layout",
        contentSHA256: String(repeating: "c", count: 64),
        checkedAt: checkedAt,
        licenceIdentifier: licenceIdentifier
      ),
    ]
  )

  var nodes = [
    RouteAtlasTopologyNode(id: "test.node.a"),
    RouteAtlasTopologyNode(id: "test.node.b"),
    RouteAtlasTopologyNode(id: "test.node.c"),
    RouteAtlasTopologyNode(id: "test.node.d"),
  ]
  var edges = [
    RouteAtlasTopologyEdge(
      id: "test.topology-edge.loop",
      routeEntityID: "test.edge.loop",
      fromNodeID: "test.node.a",
      toNodeID: "test.node.b",
      successorEdgeIDs: [
        "test.topology-edge.loop-movement",
        "test.topology-edge.exit-movement",
      ]
    ),
    RouteAtlasTopologyEdge(
      id: "test.topology-edge.loop-movement",
      routeEntityID: "test.movement.loop",
      fromNodeID: "test.node.b",
      toNodeID: "test.node.a",
      successorEdgeIDs: ["test.topology-edge.loop"]
    ),
    RouteAtlasTopologyEdge(
      id: "test.topology-edge.exit-movement",
      routeEntityID: "test.movement.exit",
      fromNodeID: "test.node.b",
      toNodeID: "test.node.c",
      successorEdgeIDs: ["test.topology-edge.exit"]
    ),
    RouteAtlasTopologyEdge(
      id: "test.topology-edge.exit",
      routeEntityID: "test.edge.exit",
      fromNodeID: "test.node.c",
      toNodeID: "test.node.d"
    ),
  ]
  if includeIncomingApproach {
    nodes.append(RouteAtlasTopologyNode(id: "test.node.editor-approach"))
    edges.append(
      RouteAtlasTopologyEdge(
        id: "test.topology-edge.editor-approach",
        routeEntityID: "test.approach.loop",
        fromNodeID: "test.node.editor-approach",
        toNodeID: "test.node.b",
        successorEdgeIDs: [
          "test.topology-edge.loop-movement",
          "test.topology-edge.exit-movement",
        ]
      )
    )
  }
  let topology = RouteAtlasTopologySlice(
    id: "test.topology.product-release",
    networkSnapshotID: fixture.networkSnapshot.id,
    nodes: nodes,
    edges: edges,
    evidence: RouteAtlasEvidence(
      state: .released,
      checkedAt: checkedAt,
      sourceReferenceIDs: [topologySourceID]
    )
  )

  var layoutNodes = [
    RouteAtlasLayoutNode(
      topologyNodeID: "test.node.a",
      point: RouteAtlasPoint(x: 0.1, y: 0.8)
    ),
    RouteAtlasLayoutNode(
      topologyNodeID: "test.node.b",
      point: RouteAtlasPoint(x: 0.5, y: 0.5)
    ),
    RouteAtlasLayoutNode(
      topologyNodeID: "test.node.c",
      point: RouteAtlasPoint(x: 0.75, y: 0.35)
    ),
    RouteAtlasLayoutNode(
      topologyNodeID: "test.node.d",
      point: RouteAtlasPoint(x: 0.95, y: 0.2)
    ),
  ]
  var segments = [
    RouteAtlasSegment(
      id: "test.segment.loop",
      topologyEdgeID: "test.topology-edge.loop",
      fromNodeID: "test.node.a",
      toNodeID: "test.node.b",
      successorSegmentIDs: [
        "test.segment.loop-movement",
        "test.segment.exit-movement",
      ],
      points: [
        RouteAtlasPoint(x: 0.1, y: 0.8),
        RouteAtlasPoint(x: 0.5, y: 0.5),
      ]
    ),
    RouteAtlasSegment(
      id: "test.segment.loop-movement",
      topologyEdgeID: "test.topology-edge.loop-movement",
      fromNodeID: "test.node.b",
      toNodeID: "test.node.a",
      successorSegmentIDs: ["test.segment.loop"],
      points: [
        RouteAtlasPoint(x: 0.5, y: 0.5),
        RouteAtlasPoint(x: 0.1, y: 0.8),
      ]
    ),
    RouteAtlasSegment(
      id: "test.segment.exit-movement",
      topologyEdgeID: "test.topology-edge.exit-movement",
      fromNodeID: "test.node.b",
      toNodeID: "test.node.c",
      successorSegmentIDs: ["test.segment.exit"],
      points: [
        RouteAtlasPoint(x: 0.5, y: 0.5),
        RouteAtlasPoint(x: 0.75, y: 0.35),
      ]
    ),
    RouteAtlasSegment(
      id: "test.segment.exit",
      topologyEdgeID: "test.topology-edge.exit",
      fromNodeID: "test.node.c",
      toNodeID: "test.node.d",
      points: [
        RouteAtlasPoint(x: 0.75, y: 0.35),
        RouteAtlasPoint(x: 0.95, y: 0.2),
      ]
    ),
  ]
  if includeIncomingApproach {
    layoutNodes.append(
      RouteAtlasLayoutNode(
        topologyNodeID: "test.node.editor-approach",
        point: RouteAtlasPoint(x: 0.05, y: 0.5)
      )
    )
    segments.append(
      RouteAtlasSegment(
        id: "test.segment.editor-approach",
        topologyEdgeID: "test.topology-edge.editor-approach",
        fromNodeID: "test.node.editor-approach",
        toNodeID: "test.node.b",
        successorSegmentIDs: [
          "test.segment.loop-movement",
          "test.segment.exit-movement",
        ],
        points: [
          RouteAtlasPoint(x: 0.05, y: 0.5),
          RouteAtlasPoint(x: 0.5, y: 0.5),
        ]
      )
    )
  }
  let segmentByEntityID = Dictionary(
    uniqueKeysWithValues: zip(
      edges.map(\.routeEntityID),
      segments.map(\.id)
    )
  )
  let occurrenceBindings = fixture.routePlan.occurrences.map { occurrence in
    RouteAtlasOccurrenceBinding(
      occurrenceID: occurrence.id,
      occurrenceIndex: occurrence.index,
      segmentID: segmentByEntityID[occurrence.entityID]!
    )
  }
  let definition = RouteAtlasDefinition(
    id: "test.atlas.product-release",
    networkSnapshotID: fixture.networkSnapshot.id,
    routePlanID: fixture.routePlan.id,
    topologySliceID: topology.id,
    nodes: layoutNodes,
    segments: segments,
    occurrenceBindings: occurrenceBindings,
    evidence: RouteAtlasEvidence(
      state: .released,
      checkedAt: checkedAt,
      sourceReferenceIDs: [layoutSourceID]
    )
  )
  return RouteAtlasReleaseArtifact(
    networkSnapshot: fixture.networkSnapshot,
    routePlan: fixture.routePlan,
    sourceRegistry: sourceRegistry,
    topologySlice: topology,
    definition: definition
  )
}

private func productNavigationReleaseArtifact(
  _ fixture: NavigationReleaseBundleFixture,
  licenceIdentifier: String
) -> NavigationReleaseArtifact {
  let artifact = navigationReleaseArtifact(fixture)
  return NavigationReleaseArtifact(
    schemaVersion: artifact.schemaVersion,
    releaseID: artifact.releaseID,
    releasedAt: artifact.releasedAt,
    editorCatalogID: artifact.editorCatalogID,
    networkSnapshot: artifact.networkSnapshot,
    routePlan: artifact.routePlan,
    sourceRegistry: NavigationReleaseSourceRegistry(
      references: artifact.sourceRegistry.references.map { source in
        NavigationReleaseSourceReference(
          id: source.id,
          roles: source.roles,
          authorityName: source.authorityName,
          sourceURL: source.sourceURL,
          contentSHA256: source.contentSHA256,
          checkedAt: source.checkedAt,
          licenceIdentifier: licenceIdentifier
        )
      }
    ),
    assetEvidence: artifact.assetEvidence,
    editorCatalog: artifact.editorCatalog,
    editorPresentationCatalog: artifact.editorPresentationCatalog,
    runtimePolicy: artifact.runtimePolicy,
    matcherCorridor: artifact.matcherCorridor,
    decisionZones: artifact.decisionZones,
    releasedGuidance: artifact.releasedGuidance,
    junctionViews: artifact.junctionViews
  )
}

private func appBundleGuidanceAudioOption(
  selectionID: String,
  manifestResourceName: String
) -> AppBundleGuidanceAudioStagingOption {
  AppBundleGuidanceAudioStagingOption(
    selectionID: selectionID,
    displayName: AppBundleGuidanceAudioDisplayName(
      japanese: "落ち着き",
      simplifiedChinese: "沉稳",
      english: "Calm"
    ),
    manifestResourceName: manifestResourceName
  )
}

func appBundleReleasedProductData() throws -> Data {
  let fixture = navigationReleaseBundleFixture()
  let artifact = try KaidoProductReleaseAuthor.buildArtifact(
    navigationRelease: productNavigationReleaseArtifact(
      fixture,
      licenceIdentifier: "TEST_REVIEWED_ROAD_ONLY"
    ),
    routeAtlasRelease: productRouteAtlasArtifact(
      fixture,
      includeIncomingApproach: true,
      licenceIdentifier: "TEST_REVIEWED_ROAD_ONLY"
    ),
    configuration: KaidoProductReleaseAuthoringConfiguration(
      releaseID: "test.product-release.app-bundle",
      releasedAt: "2026-07-24T12:30:00+09:00"
    )
  )
  return try KaidoProductReleaseArtifactCodec.encode(artifact)
}

private func testSHA256Hex(_ data: Data) -> String {
  SHA256.hash(data: data).map {
    String(format: "%02x", $0)
  }.joined()
}
