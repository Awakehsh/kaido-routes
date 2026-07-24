import Foundation
import KaidoDomain

/// Reviewed directed topology before release evidence is attached.
public struct RouteAtlasTopologyDraft: Codable, Equatable, Sendable {
  public let id: String
  public let networkSnapshotID: String
  public let nodes: [RouteAtlasTopologyNode]
  public let edges: [RouteAtlasTopologyEdge]

  public init(
    id: String,
    networkSnapshotID: String,
    nodes: [RouteAtlasTopologyNode],
    edges: [RouteAtlasTopologyEdge]
  ) {
    self.id = id
    self.networkSnapshotID = networkSnapshotID
    self.nodes = nodes
    self.edges = edges
  }

  private enum CodingKeys: String, CodingKey {
    case id = "topology_slice_id"
    case networkSnapshotID = "network_snapshot_id"
    case nodes
    case edges
  }
}

/// Reviewed renderer-neutral layout before release evidence is attached.
public struct RouteAtlasDefinitionDraft: Codable, Equatable, Sendable {
  public let id: String
  public let networkSnapshotID: String
  public let routePlanID: String
  public let topologySliceID: String
  public let nodes: [RouteAtlasLayoutNode]
  public let segments: [RouteAtlasSegment]
  public let occurrenceBindings: [RouteAtlasOccurrenceBinding]

  public init(
    id: String,
    networkSnapshotID: String,
    routePlanID: String,
    topologySliceID: String,
    nodes: [RouteAtlasLayoutNode],
    segments: [RouteAtlasSegment],
    occurrenceBindings: [RouteAtlasOccurrenceBinding]
  ) {
    self.id = id
    self.networkSnapshotID = networkSnapshotID
    self.routePlanID = routePlanID
    self.topologySliceID = topologySliceID
    self.nodes = nodes
    self.segments = segments
    self.occurrenceBindings = occurrenceBindings
  }

  private enum CodingKeys: String, CodingKey {
    case id = "atlas_id"
    case networkSnapshotID = "network_snapshot_id"
    case routePlanID = "route_plan_id"
    case topologySliceID = "topology_slice_id"
    case nodes
    case segments
    case occurrenceBindings = "occurrence_bindings"
  }
}

/// Immutable atlas content with no source registry or release evidence.
///
/// A draft cannot become navigation or rendering authority. Authoring attaches
/// separately reviewed topology and layout evidence, then reruns the complete
/// `RouteAtlasRelease` gate.
public struct RouteAtlasReleaseDraft: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = "1.0"

  public let schemaVersion: String
  public let networkSnapshot: NetworkSnapshot
  public let routePlan: RoutePlan
  public let topologySlice: RouteAtlasTopologyDraft
  public let definition: RouteAtlasDefinitionDraft

  public init(
    schemaVersion: String = RouteAtlasReleaseDraft.currentSchemaVersion,
    networkSnapshot: NetworkSnapshot,
    routePlan: RoutePlan,
    topologySlice: RouteAtlasTopologyDraft,
    definition: RouteAtlasDefinitionDraft
  ) {
    self.schemaVersion = schemaVersion
    self.networkSnapshot = networkSnapshot
    self.routePlan = routePlan
    self.topologySlice = topologySlice
    self.definition = definition
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case networkSnapshot = "network_snapshot"
    case routePlan = "route_plan"
    case topologySlice = "topology_slice"
    case definition
  }
}

/// Reviewed source provenance and independent topology/layout release evidence.
public struct RouteAtlasReleaseAuthoringConfiguration:
  Codable, Equatable, Sendable
{
  public static let currentSchemaVersion = "1.0"

  public let schemaVersion: String
  public let sourceRegistry: RouteAtlasSourceRegistry
  public let topologyEvidence: RouteAtlasEvidence
  public let layoutEvidence: RouteAtlasEvidence

  public init(
    schemaVersion: String =
      RouteAtlasReleaseAuthoringConfiguration.currentSchemaVersion,
    sourceRegistry: RouteAtlasSourceRegistry,
    topologyEvidence: RouteAtlasEvidence,
    layoutEvidence: RouteAtlasEvidence
  ) {
    self.schemaVersion = schemaVersion
    self.sourceRegistry = sourceRegistry
    self.topologyEvidence = topologyEvidence
    self.layoutEvidence = layoutEvidence
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case sourceRegistry = "source_registry"
    case topologyEvidence = "topology_evidence"
    case layoutEvidence = "layout_evidence"
  }
}

public enum RouteAtlasReleaseAuthoringIssue: Equatable, Sendable {
  case invalidDraftSchemaVersion
  case invalidConfigurationSchemaVersion

  public var code: String {
    switch self {
    case .invalidDraftSchemaVersion:
      "INVALID_ROUTE_ATLAS_RELEASE_DRAFT_SCHEMA_VERSION"
    case .invalidConfigurationSchemaVersion:
      "INVALID_ROUTE_ATLAS_RELEASE_AUTHORING_SCHEMA_VERSION"
    }
  }
}

public enum RouteAtlasReleaseAuthoringError:
  Error, Equatable, Sendable
{
  case invalidDraft([RouteAtlasReleaseAuthoringIssue])
  case invalidConfiguration([RouteAtlasReleaseAuthoringIssue])
  case invalidRelease([RouteAtlasReleaseIssue])
}

/// Derives the current artifact without rewriting reviewed content or evidence.
public enum RouteAtlasReleaseAuthor {
  public static func buildArtifact(
    draft: RouteAtlasReleaseDraft,
    configuration: RouteAtlasReleaseAuthoringConfiguration
  ) throws -> RouteAtlasReleaseArtifact {
    guard
      draft.schemaVersion == RouteAtlasReleaseDraft.currentSchemaVersion
    else {
      throw RouteAtlasReleaseAuthoringError.invalidDraft([
        .invalidDraftSchemaVersion
      ])
    }
    guard
      configuration.schemaVersion
        == RouteAtlasReleaseAuthoringConfiguration.currentSchemaVersion
    else {
      throw RouteAtlasReleaseAuthoringError.invalidConfiguration([
        .invalidConfigurationSchemaVersion
      ])
    }

    let artifact = RouteAtlasReleaseArtifact(
      networkSnapshot: draft.networkSnapshot,
      routePlan: draft.routePlan,
      sourceRegistry: configuration.sourceRegistry,
      topologySlice: RouteAtlasTopologySlice(
        id: draft.topologySlice.id,
        networkSnapshotID: draft.topologySlice.networkSnapshotID,
        nodes: draft.topologySlice.nodes,
        edges: draft.topologySlice.edges,
        evidence: configuration.topologyEvidence
      ),
      definition: RouteAtlasDefinition(
        id: draft.definition.id,
        networkSnapshotID: draft.definition.networkSnapshotID,
        routePlanID: draft.definition.routePlanID,
        topologySliceID: draft.definition.topologySliceID,
        nodes: draft.definition.nodes,
        segments: draft.definition.segments,
        occurrenceBindings: draft.definition.occurrenceBindings,
        evidence: configuration.layoutEvidence
      )
    )
    do {
      _ = try RouteAtlasRelease(artifact: artifact)
    } catch RouteAtlasReleaseError.invalid(let issues) {
      throw RouteAtlasReleaseAuthoringError.invalidRelease(issues)
    }
    return artifact
  }
}

public enum RouteAtlasReleaseDraftCodec {
  public static func encode(
    _ draft: RouteAtlasReleaseDraft
  ) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(draft)
  }

  public static func decode(_ data: Data) throws
    -> RouteAtlasReleaseDraft
  {
    try JSONDecoder().decode(RouteAtlasReleaseDraft.self, from: data)
  }
}

public enum RouteAtlasReleaseAuthoringConfigurationCodec {
  public static func encode(
    _ configuration: RouteAtlasReleaseAuthoringConfiguration
  ) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(configuration)
  }

  public static func decode(_ data: Data) throws
    -> RouteAtlasReleaseAuthoringConfiguration
  {
    try JSONDecoder().decode(
      RouteAtlasReleaseAuthoringConfiguration.self,
      from: data
    )
  }
}

public enum RouteAtlasReleaseArtifactCodec {
  public static func encode(
    _ artifact: RouteAtlasReleaseArtifact
  ) throws -> Data {
    _ = try RouteAtlasRelease(artifact: artifact)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(artifact)
  }

  public static func decode(_ data: Data) throws -> RouteAtlasRelease {
    let artifact = try JSONDecoder().decode(
      RouteAtlasReleaseArtifact.self,
      from: data
    )
    return try RouteAtlasRelease(artifact: artifact)
  }
}
