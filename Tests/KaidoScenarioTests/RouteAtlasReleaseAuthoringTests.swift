import KaidoNavigation
import Testing

@Test("Route Atlas author preserves reviewed topology, layout, and provenance")
func routeAtlasReleaseAuthorPreservesReviewedInputs() throws {
  let fixture = routeAtlasFixture()
  let expected = routeAtlasReleaseArtifact(fixture)
  let draft = routeAtlasReleaseDraft(fixture)
  let configuration = routeAtlasReleaseAuthoringConfiguration(fixture)

  let draftData = try RouteAtlasReleaseDraftCodec.encode(draft)
  let configurationData =
    try RouteAtlasReleaseAuthoringConfigurationCodec.encode(
      configuration
    )
  let decodedDraft = try RouteAtlasReleaseDraftCodec.decode(draftData)
  let decodedConfiguration =
    try RouteAtlasReleaseAuthoringConfigurationCodec.decode(
      configurationData
    )
  let artifact = try RouteAtlasReleaseAuthor.buildArtifact(
    draft: decodedDraft,
    configuration: decodedConfiguration
  )
  let artifactData = try RouteAtlasReleaseArtifactCodec.encode(artifact)
  let release = try RouteAtlasReleaseArtifactCodec.decode(artifactData)
  let repeatedDraftData = try RouteAtlasReleaseDraftCodec.encode(draft)
  let repeatedConfigurationData =
    try RouteAtlasReleaseAuthoringConfigurationCodec.encode(
      configuration
    )

  #expect(draftData == repeatedDraftData)
  #expect(configurationData == repeatedConfigurationData)
  #expect(artifact == expected)
  #expect(release.networkSnapshot == fixture.networkSnapshot)
  #expect(release.routePlan == fixture.routePlan)
  #expect(release.sourceRegistry == fixture.sourceRegistry)
  #expect(release.topologySlice == fixture.topologySlice)
  #expect(release.definition == fixture.definition)
}

@Test("Route Atlas author rejects unknown input schemas")
func routeAtlasReleaseAuthorRejectsUnknownSchemas() {
  let fixture = routeAtlasFixture()
  let validDraft = routeAtlasReleaseDraft(fixture)
  let validConfiguration = routeAtlasReleaseAuthoringConfiguration(fixture)
  let invalidDraft = RouteAtlasReleaseDraft(
    schemaVersion: "2.0",
    networkSnapshot: fixture.networkSnapshot,
    routePlan: fixture.routePlan,
    topologySlice: validDraft.topologySlice,
    definition: validDraft.definition
  )

  #expect(
    throws: RouteAtlasReleaseAuthoringError.invalidDraft([
      .invalidDraftSchemaVersion
    ])
  ) {
    _ = try RouteAtlasReleaseAuthor.buildArtifact(
      draft: invalidDraft,
      configuration: validConfiguration
    )
  }

  let invalidConfiguration = RouteAtlasReleaseAuthoringConfiguration(
    schemaVersion: "2.0",
    sourceRegistry: fixture.sourceRegistry,
    topologyEvidence: fixture.topologySlice.evidence,
    layoutEvidence: fixture.definition.evidence
  )
  #expect(
    throws: RouteAtlasReleaseAuthoringError.invalidConfiguration([
      .invalidConfigurationSchemaVersion
    ])
  ) {
    _ = try RouteAtlasReleaseAuthor.buildArtifact(
      draft: validDraft,
      configuration: invalidConfiguration
    )
  }
}

@Test("Route Atlas author returns nothing before both evidence gates pass")
func routeAtlasReleaseAuthorRejectsUnreleasedEvidence() {
  let fixture = routeAtlasFixture()
  let incomplete = RouteAtlasReleaseAuthoringConfiguration(
    sourceRegistry: fixture.sourceRegistry,
    topologyEvidence: fixture.topologySlice.evidence,
    layoutEvidence: RouteAtlasEvidence(
      state: .officialChecked,
      checkedAt: fixture.definition.evidence.checkedAt,
      sourceReferenceIDs:
        fixture.definition.evidence.sourceReferenceIDs
    )
  )

  do {
    _ = try RouteAtlasReleaseAuthor.buildArtifact(
      draft: routeAtlasReleaseDraft(fixture),
      configuration: incomplete
    )
    Issue.record("Expected unreleased layout evidence to block authoring")
  } catch RouteAtlasReleaseAuthoringError.invalidRelease(let issues) {
    #expect(issues.contains(.unreleasedAtlasEvidence))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

private func routeAtlasReleaseArtifact(
  _ fixture: RouteAtlasFixture
) -> RouteAtlasReleaseArtifact {
  RouteAtlasReleaseArtifact(
    networkSnapshot: fixture.networkSnapshot,
    routePlan: fixture.routePlan,
    sourceRegistry: fixture.sourceRegistry,
    topologySlice: fixture.topologySlice,
    definition: fixture.definition
  )
}

private func routeAtlasReleaseDraft(
  _ fixture: RouteAtlasFixture
) -> RouteAtlasReleaseDraft {
  RouteAtlasReleaseDraft(
    networkSnapshot: fixture.networkSnapshot,
    routePlan: fixture.routePlan,
    topologySlice: RouteAtlasTopologyDraft(
      id: fixture.topologySlice.id,
      networkSnapshotID: fixture.topologySlice.networkSnapshotID,
      nodes: fixture.topologySlice.nodes,
      edges: fixture.topologySlice.edges
    ),
    definition: RouteAtlasDefinitionDraft(
      id: fixture.definition.id,
      networkSnapshotID: fixture.definition.networkSnapshotID,
      routePlanID: fixture.definition.routePlanID,
      topologySliceID: fixture.definition.topologySliceID,
      nodes: fixture.definition.nodes,
      segments: fixture.definition.segments,
      occurrenceBindings: fixture.definition.occurrenceBindings
    )
  )
}

private func routeAtlasReleaseAuthoringConfiguration(
  _ fixture: RouteAtlasFixture
) -> RouteAtlasReleaseAuthoringConfiguration {
  RouteAtlasReleaseAuthoringConfiguration(
    sourceRegistry: fixture.sourceRegistry,
    topologyEvidence: fixture.topologySlice.evidence,
    layoutEvidence: fixture.definition.evidence
  )
}
