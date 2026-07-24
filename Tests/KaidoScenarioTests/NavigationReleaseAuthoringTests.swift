import KaidoNavigation
import Testing

@Test("Navigation release author preserves one complete reviewed draft")
func navigationReleaseAuthorPreservesReviewedDraft() throws {
  let fixture = navigationReleaseBundleFixture()
  let expected = navigationReleaseArtifact(fixture)
  let draft = navigationReleaseDraft(
    artifact: expected,
    fixture: fixture
  )
  let configuration = navigationReleaseAuthoringConfiguration(
    artifact: expected
  )

  let draftData = try NavigationReleaseDraftCodec.encode(draft)
  let configurationData =
    try NavigationReleaseAuthoringConfigurationCodec.encode(
      configuration
    )
  let decodedDraft = try NavigationReleaseDraftCodec.decode(draftData)
  let decodedConfiguration =
    try NavigationReleaseAuthoringConfigurationCodec.decode(
      configurationData
    )
  let artifact = try NavigationReleaseAuthor.buildArtifact(
    draft: decodedDraft,
    configuration: decodedConfiguration
  )
  let encoded = try NavigationReleaseArtifactCodec.encode(artifact)
  let release = try NavigationReleaseArtifactCodec.decode(encoded)
  let repeatedDraftData =
    try NavigationReleaseDraftCodec.encode(draft)
  let repeatedConfigurationData =
    try NavigationReleaseAuthoringConfigurationCodec.encode(
      configuration
    )

  #expect(draftData == repeatedDraftData)
  #expect(configurationData == repeatedConfigurationData)
  #expect(artifact == expected)
  #expect(release.bundle.routePlan == fixture.routePlan)
  #expect(release.bundle.editorCatalog == fixture.editorCatalog)
  #expect(release.bundle.matcherCorridor == fixture.matcherCorridor)
  #expect(release.assetEvidence == expected.assetEvidence)
}

@Test("Navigation release author rejects unknown input schemas")
func navigationReleaseAuthorRejectsUnknownSchemas() {
  let fixture = navigationReleaseBundleFixture()
  let expected = navigationReleaseArtifact(fixture)
  let invalidDraft = NavigationReleaseDraft(
    schemaVersion: "2.0",
    editorCatalogID: expected.editorCatalogID,
    networkSnapshot: fixture.networkSnapshot,
    routePlan: fixture.routePlan,
    editorCatalog: fixture.editorCatalog,
    editorPresentationCatalog: fixture.editorPresentationCatalog,
    runtimePolicy: fixture.runtimePolicy,
    matcherCorridor: fixture.matcherCorridor,
    decisionZones: fixture.decisionZones,
    releasedGuidance: fixture.releasedGuidance,
    junctionViews: fixture.junctionViews
  )
  #expect(
    throws: NavigationReleaseAuthoringError.invalidDraft([
      .invalidDraftSchemaVersion
    ])
  ) {
    _ = try NavigationReleaseAuthor.buildArtifact(
      draft: invalidDraft,
      configuration: navigationReleaseAuthoringConfiguration(
        artifact: expected
      )
    )
  }

  let invalidConfiguration = NavigationReleaseAuthoringConfiguration(
    schemaVersion: "2.0",
    releaseID: expected.releaseID,
    releasedAt: expected.releasedAt,
    sourceRegistry: expected.sourceRegistry,
    assetEvidence: expected.assetEvidence
  )
  #expect(
    throws: NavigationReleaseAuthoringError.invalidConfiguration([
      .invalidConfigurationSchemaVersion
    ])
  ) {
    _ = try NavigationReleaseAuthor.buildArtifact(
      draft: navigationReleaseDraft(
        artifact: expected,
        fixture: fixture
      ),
      configuration: invalidConfiguration
    )
  }
}

@Test("Navigation release author writes nothing before the whole gate passes")
func navigationReleaseAuthorRejectsIncompleteEvidence() {
  let fixture = navigationReleaseBundleFixture()
  let expected = navigationReleaseArtifact(fixture)
  let incomplete = NavigationReleaseAuthoringConfiguration(
    releaseID: expected.releaseID,
    releasedAt: expected.releasedAt,
    sourceRegistry: expected.sourceRegistry,
    assetEvidence: expected.assetEvidence.filter {
      $0.role != .matcherCorridor
    }
  )

  do {
    _ = try NavigationReleaseAuthor.buildArtifact(
      draft: navigationReleaseDraft(
        artifact: expected,
        fixture: fixture
      ),
      configuration: incomplete
    )
    Issue.record("Expected incomplete evidence to block authoring")
  } catch NavigationReleaseAuthoringError.invalidRelease(let issues) {
    #expect(
      issues.contains(
        .missingAssetEvidence(
          "MATCHER_CORRIDOR:\(fixture.matcherCorridor.id)"
        )
      )
    )
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

private func navigationReleaseDraft(
  artifact: NavigationReleaseArtifact,
  fixture: NavigationReleaseBundleFixture
) -> NavigationReleaseDraft {
  NavigationReleaseDraft(
    editorCatalogID: artifact.editorCatalogID,
    networkSnapshot: fixture.networkSnapshot,
    routePlan: fixture.routePlan,
    editorCatalog: fixture.editorCatalog,
    editorPresentationCatalog: fixture.editorPresentationCatalog,
    runtimePolicy: fixture.runtimePolicy,
    matcherCorridor: fixture.matcherCorridor,
    decisionZones: fixture.decisionZones,
    releasedGuidance: fixture.releasedGuidance,
    junctionViews: fixture.junctionViews
  )
}

private func navigationReleaseAuthoringConfiguration(
  artifact: NavigationReleaseArtifact
) -> NavigationReleaseAuthoringConfiguration {
  NavigationReleaseAuthoringConfiguration(
    releaseID: artifact.releaseID,
    releasedAt: artifact.releasedAt,
    sourceRegistry: artifact.sourceRegistry,
    assetEvidence: artifact.assetEvidence
  )
}
