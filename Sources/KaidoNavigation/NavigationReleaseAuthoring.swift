import Foundation
import KaidoDomain
import KaidoRouting
import KaidoSurfaceRouting

/// The reviewed runtime assets for one navigation release before provenance
/// metadata turns them into a distributable artifact.
///
/// A draft carries no release authority. The authoring gate preserves every
/// value unchanged and must construct a valid `NavigationRelease` before an
/// artifact may be written.
public struct NavigationReleaseDraft: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = "1.0"

  public let schemaVersion: String
  public let editorCatalogID: String
  public let networkSnapshot: NetworkSnapshot
  public let routePlan: RoutePlan
  public let editorCatalog: ReviewedRouteEditorCatalog
  public let editorPresentationCatalog: ReviewedRouteEditorPresentationCatalog
  public let runtimePolicy: ReleasedNavigationRuntimePolicy
  public let matcherCorridor: RouteMatcherCorridor
  public let decisionZones: [DecisionZoneProgressDefinition]
  public let releasedGuidance: [ReleasedGuidanceDefinition]
  public let junctionViews: [JunctionViewDefinition]
  public let surfaceAccessDefinition: ReleasedSurfaceAccessDefinition?

  public init(
    schemaVersion: String = NavigationReleaseDraft.currentSchemaVersion,
    editorCatalogID: String,
    networkSnapshot: NetworkSnapshot,
    routePlan: RoutePlan,
    editorCatalog: ReviewedRouteEditorCatalog,
    editorPresentationCatalog: ReviewedRouteEditorPresentationCatalog,
    runtimePolicy: ReleasedNavigationRuntimePolicy,
    matcherCorridor: RouteMatcherCorridor,
    decisionZones: [DecisionZoneProgressDefinition],
    releasedGuidance: [ReleasedGuidanceDefinition],
    junctionViews: [JunctionViewDefinition] = [],
    surfaceAccessDefinition: ReleasedSurfaceAccessDefinition? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.editorCatalogID = editorCatalogID
    self.networkSnapshot = networkSnapshot
    self.routePlan = routePlan
    self.editorCatalog = editorCatalog
    self.editorPresentationCatalog = editorPresentationCatalog
    self.runtimePolicy = runtimePolicy
    self.matcherCorridor = matcherCorridor
    self.decisionZones = decisionZones
    self.releasedGuidance = releasedGuidance
    self.junctionViews = junctionViews
    self.surfaceAccessDefinition = surfaceAccessDefinition
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case editorCatalogID = "editor_catalog_id"
    case networkSnapshot = "network_snapshot"
    case routePlan = "route_plan"
    case editorCatalog = "editor_catalog"
    case editorPresentationCatalog = "editor_presentation_catalog"
    case runtimePolicy = "runtime_policy"
    case matcherCorridor = "matcher_corridor"
    case decisionZones = "decision_zones"
    case releasedGuidance = "released_guidance"
    case junctionViews = "junction_views"
    case surfaceAccessDefinition = "surface_access_definition"
  }
}

/// Reproducible release identity and reviewed provenance for one draft.
public struct NavigationReleaseAuthoringConfiguration:
  Codable, Equatable, Sendable
{
  public static let currentSchemaVersion = "1.0"

  public let schemaVersion: String
  public let releaseID: String
  public let releasedAt: String
  public let sourceRegistry: NavigationReleaseSourceRegistry
  public let assetEvidence: [NavigationReleaseAssetEvidence]

  public init(
    schemaVersion: String =
      NavigationReleaseAuthoringConfiguration.currentSchemaVersion,
    releaseID: String,
    releasedAt: String,
    sourceRegistry: NavigationReleaseSourceRegistry,
    assetEvidence: [NavigationReleaseAssetEvidence]
  ) {
    self.schemaVersion = schemaVersion
    self.releaseID = releaseID
    self.releasedAt = releasedAt
    self.sourceRegistry = sourceRegistry
    self.assetEvidence = assetEvidence
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case releaseID = "release_id"
    case releasedAt = "released_at"
    case sourceRegistry = "source_registry"
    case assetEvidence = "asset_evidence"
  }
}

public enum NavigationReleaseAuthoringIssue: Equatable, Sendable {
  case invalidDraftSchemaVersion
  case invalidEditorCatalogID
  case invalidConfigurationSchemaVersion
  case invalidReleaseIdentity

  public var code: String {
    switch self {
    case .invalidDraftSchemaVersion:
      "INVALID_NAVIGATION_RELEASE_DRAFT_SCHEMA_VERSION"
    case .invalidEditorCatalogID:
      "INVALID_NAVIGATION_RELEASE_DRAFT_EDITOR_CATALOG_ID"
    case .invalidConfigurationSchemaVersion:
      "INVALID_NAVIGATION_RELEASE_AUTHORING_SCHEMA_VERSION"
    case .invalidReleaseIdentity:
      "INVALID_NAVIGATION_RELEASE_AUTHORING_IDENTITY"
    }
  }
}

public enum NavigationReleaseAuthoringError:
  Error, Equatable, Sendable
{
  case invalidDraft([NavigationReleaseAuthoringIssue])
  case invalidConfiguration([NavigationReleaseAuthoringIssue])
  case invalidRelease([NavigationReleaseIssue])
}

/// Builds a schema-current navigation artifact without mutating reviewed input.
public enum NavigationReleaseAuthor {
  public static func buildArtifact(
    draft: NavigationReleaseDraft,
    configuration: NavigationReleaseAuthoringConfiguration
  ) throws -> NavigationReleaseArtifact {
    let draftIssues = draftValidationIssues(draft)
    guard draftIssues.isEmpty else {
      throw NavigationReleaseAuthoringError.invalidDraft(draftIssues)
    }
    let configurationIssues = configurationValidationIssues(
      configuration
    )
    guard configurationIssues.isEmpty else {
      throw NavigationReleaseAuthoringError.invalidConfiguration(
        configurationIssues
      )
    }

    let artifact = NavigationReleaseArtifact(
      releaseID: configuration.releaseID,
      releasedAt: configuration.releasedAt,
      editorCatalogID: draft.editorCatalogID,
      networkSnapshot: draft.networkSnapshot,
      routePlan: draft.routePlan,
      sourceRegistry: configuration.sourceRegistry,
      assetEvidence: configuration.assetEvidence,
      editorCatalog: draft.editorCatalog,
      editorPresentationCatalog: draft.editorPresentationCatalog,
      runtimePolicy: draft.runtimePolicy,
      matcherCorridor: draft.matcherCorridor,
      decisionZones: draft.decisionZones,
      releasedGuidance: draft.releasedGuidance,
      junctionViews: draft.junctionViews,
      surfaceAccessDefinition: draft.surfaceAccessDefinition
    )
    do {
      _ = try NavigationRelease(artifact: artifact)
    } catch NavigationReleaseError.invalid(let issues) {
      throw NavigationReleaseAuthoringError.invalidRelease(issues)
    }
    return artifact
  }

  private static func draftValidationIssues(
    _ draft: NavigationReleaseDraft
  ) -> [NavigationReleaseAuthoringIssue] {
    var issues: [NavigationReleaseAuthoringIssue] = []
    if draft.schemaVersion
      != NavigationReleaseDraft.currentSchemaVersion
    {
      issues.append(.invalidDraftSchemaVersion)
    }
    if draft.editorCatalogID.trimmingCharacters(
      in: .whitespacesAndNewlines
    ).isEmpty {
      issues.append(.invalidEditorCatalogID)
    }
    return issues
  }

  private static func configurationValidationIssues(
    _ configuration: NavigationReleaseAuthoringConfiguration
  ) -> [NavigationReleaseAuthoringIssue] {
    var issues: [NavigationReleaseAuthoringIssue] = []
    if configuration.schemaVersion
      != NavigationReleaseAuthoringConfiguration.currentSchemaVersion
    {
      issues.append(.invalidConfigurationSchemaVersion)
    }
    if configuration.releaseID.trimmingCharacters(
      in: .whitespacesAndNewlines
    ).isEmpty || !isISO8601DateTime(configuration.releasedAt) {
      issues.append(.invalidReleaseIdentity)
    }
    return issues
  }

  private static func isISO8601DateTime(_ value: String) -> Bool {
    let standard = ISO8601DateFormatter()
    if standard.date(from: value) != nil {
      return true
    }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [
      .withInternetDateTime,
      .withFractionalSeconds,
    ]
    return fractional.date(from: value) != nil
  }
}

public enum NavigationReleaseDraftCodec {
  public static func encode(
    _ draft: NavigationReleaseDraft
  ) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(draft)
  }

  public static func decode(_ data: Data) throws
    -> NavigationReleaseDraft
  {
    try JSONDecoder().decode(NavigationReleaseDraft.self, from: data)
  }
}

public enum NavigationReleaseAuthoringConfigurationCodec {
  public static func encode(
    _ configuration: NavigationReleaseAuthoringConfiguration
  ) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(configuration)
  }

  public static func decode(_ data: Data) throws
    -> NavigationReleaseAuthoringConfiguration
  {
    try JSONDecoder().decode(
      NavigationReleaseAuthoringConfiguration.self,
      from: data
    )
  }
}
