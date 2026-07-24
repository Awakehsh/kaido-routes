import Foundation
import KaidoDomain

public enum RouteAtlasEvidenceState: String, Codable, Sendable {
  case candidate = "CANDIDATE"
  case officialChecked = "OFFICIAL_CHECKED"
  case fieldChecked = "FIELD_CHECKED"
  case released = "RELEASED"
}

public struct RouteAtlasEvidence: Codable, Equatable, Sendable {
  public let state: RouteAtlasEvidenceState
  public let checkedAt: String
  public let sourceReferenceIDs: [String]

  public init(
    state: RouteAtlasEvidenceState,
    checkedAt: String,
    sourceReferenceIDs: [String]
  ) {
    self.state = state
    self.checkedAt = checkedAt
    self.sourceReferenceIDs = sourceReferenceIDs
  }

  enum CodingKeys: String, CodingKey {
    case state
    case checkedAt = "checked_at"
    case sourceReferenceIDs = "source_reference_ids"
  }
}

public enum RouteAtlasSourceRole: String, Codable, Sendable {
  case topologyEvidence = "TOPOLOGY_EVIDENCE"
  case layoutEvidence = "LAYOUT_EVIDENCE"
}

/// One reviewable evidence record referenced by topology or layout evidence.
///
/// A registry proves that an evidence ID resolves to explicit provenance; it
/// does not promote the referenced material to RELEASED on its own.
public struct RouteAtlasSourceReference: Codable, Equatable, Sendable {
  public let id: String
  public let roles: Set<RouteAtlasSourceRole>
  public let authorityName: String
  public let sourceURL: String
  public let contentSHA256: String
  public let checkedAt: String
  public let licenceIdentifier: String

  public init(
    id: String,
    roles: Set<RouteAtlasSourceRole>,
    authorityName: String,
    sourceURL: String,
    contentSHA256: String,
    checkedAt: String,
    licenceIdentifier: String
  ) {
    self.id = id
    self.roles = roles
    self.authorityName = authorityName
    self.sourceURL = sourceURL
    self.contentSHA256 = contentSHA256
    self.checkedAt = checkedAt
    self.licenceIdentifier = licenceIdentifier
  }

  enum CodingKeys: String, CodingKey {
    case id = "source_reference_id"
    case roles
    case authorityName = "authority_name"
    case sourceURL = "source_url"
    case contentSHA256 = "content_sha256"
    case checkedAt = "checked_at"
    case licenceIdentifier = "licence_identifier"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    let decodedRoles = try container.decode([RouteAtlasSourceRole].self, forKey: .roles)
    guard Set(decodedRoles).count == decodedRoles.count else {
      throw DecodingError.dataCorruptedError(
        forKey: .roles,
        in: container,
        debugDescription: "Route Atlas source roles must be unique"
      )
    }
    roles = Set(decodedRoles)
    authorityName = try container.decode(String.self, forKey: .authorityName)
    sourceURL = try container.decode(String.self, forKey: .sourceURL)
    contentSHA256 = try container.decode(String.self, forKey: .contentSHA256)
    checkedAt = try container.decode(String.self, forKey: .checkedAt)
    licenceIdentifier = try container.decode(String.self, forKey: .licenceIdentifier)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(roles.sorted(by: { $0.rawValue < $1.rawValue }), forKey: .roles)
    try container.encode(authorityName, forKey: .authorityName)
    try container.encode(sourceURL, forKey: .sourceURL)
    try container.encode(contentSHA256, forKey: .contentSHA256)
    try container.encode(checkedAt, forKey: .checkedAt)
    try container.encode(licenceIdentifier, forKey: .licenceIdentifier)
  }
}

public struct RouteAtlasSourceRegistry: Codable, Equatable, Sendable {
  public let references: [RouteAtlasSourceReference]

  public init(references: [RouteAtlasSourceReference]) {
    self.references = references
  }
}

public struct RouteAtlasTopologyNode: Codable, Equatable, Sendable {
  public let id: String

  public init(id: String) {
    self.id = id
  }

  enum CodingKeys: String, CodingKey {
    case id = "node_id"
  }
}

/// One displayable directed part of a reviewed network slice.
///
/// `routeEntityID` binds the topology back to the exact entity used by a
/// RoutePlan occurrence. Successors are authored by the reviewed graph and are
/// never inferred from schematic geometry.
public struct RouteAtlasTopologyEdge: Codable, Equatable, Sendable {
  public let id: String
  public let routeEntityID: String
  public let fromNodeID: String
  public let toNodeID: String
  public let successorEdgeIDs: Set<String>

  public init(
    id: String,
    routeEntityID: String,
    fromNodeID: String,
    toNodeID: String,
    successorEdgeIDs: Set<String> = []
  ) {
    self.id = id
    self.routeEntityID = routeEntityID
    self.fromNodeID = fromNodeID
    self.toNodeID = toNodeID
    self.successorEdgeIDs = successorEdgeIDs
  }

  enum CodingKeys: String, CodingKey {
    case id = "edge_id"
    case routeEntityID = "route_entity_id"
    case fromNodeID = "from_node_id"
    case toNodeID = "to_node_id"
    case successorEdgeIDs = "successor_edge_ids"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    routeEntityID = try container.decode(String.self, forKey: .routeEntityID)
    fromNodeID = try container.decode(String.self, forKey: .fromNodeID)
    toNodeID = try container.decode(String.self, forKey: .toNodeID)
    let decodedSuccessors =
      try container.decodeIfPresent([String].self, forKey: .successorEdgeIDs) ?? []
    guard Set(decodedSuccessors).count == decodedSuccessors.count else {
      throw DecodingError.dataCorruptedError(
        forKey: .successorEdgeIDs,
        in: container,
        debugDescription: "Route Atlas topology successors must be unique"
      )
    }
    successorEdgeIDs = Set(decodedSuccessors)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(routeEntityID, forKey: .routeEntityID)
    try container.encode(fromNodeID, forKey: .fromNodeID)
    try container.encode(toNodeID, forKey: .toNodeID)
    try container.encode(successorEdgeIDs.sorted(), forKey: .successorEdgeIDs)
  }
}

/// The reviewed graph truth for the exact network coverage visible in an atlas.
public struct RouteAtlasTopologySlice: Codable, Equatable, Sendable {
  public let id: String
  public let networkSnapshotID: String
  public let nodes: [RouteAtlasTopologyNode]
  public let edges: [RouteAtlasTopologyEdge]
  public let evidence: RouteAtlasEvidence

  public init(
    id: String,
    networkSnapshotID: String,
    nodes: [RouteAtlasTopologyNode],
    edges: [RouteAtlasTopologyEdge],
    evidence: RouteAtlasEvidence
  ) {
    self.id = id
    self.networkSnapshotID = networkSnapshotID
    self.nodes = nodes
    self.edges = edges
    self.evidence = evidence
  }

  enum CodingKeys: String, CodingKey {
    case id = "topology_slice_id"
    case networkSnapshotID = "network_snapshot_id"
    case nodes
    case edges
    case evidence
  }
}

/// A renderer-neutral point in a normalized north-up atlas coordinate space.
public struct RouteAtlasPoint: Codable, Equatable, Sendable {
  public let x: Double
  public let y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

public struct RouteAtlasLayoutNode: Codable, Equatable, Sendable {
  public let topologyNodeID: String
  public let point: RouteAtlasPoint

  public init(topologyNodeID: String, point: RouteAtlasPoint) {
    self.topologyNodeID = topologyNodeID
    self.point = point
  }

  enum CodingKeys: String, CodingKey {
    case topologyNodeID = "topology_node_id"
    case point
  }
}

/// One schematic path with an exact one-to-one topology-edge binding.
///
/// A renderer may simplify these points visually, but it must use
/// `successorSegmentIDs` for interaction and highlighting. Coordinate crossings
/// never create a graph connection.
public struct RouteAtlasSegment: Codable, Equatable, Sendable {
  public let id: String
  public let topologyEdgeID: String
  public let fromNodeID: String
  public let toNodeID: String
  public let successorSegmentIDs: Set<String>
  public let points: [RouteAtlasPoint]

  public init(
    id: String,
    topologyEdgeID: String,
    fromNodeID: String,
    toNodeID: String,
    successorSegmentIDs: Set<String> = [],
    points: [RouteAtlasPoint]
  ) {
    self.id = id
    self.topologyEdgeID = topologyEdgeID
    self.fromNodeID = fromNodeID
    self.toNodeID = toNodeID
    self.successorSegmentIDs = successorSegmentIDs
    self.points = points
  }

  enum CodingKeys: String, CodingKey {
    case id = "segment_id"
    case topologyEdgeID = "topology_edge_id"
    case fromNodeID = "from_node_id"
    case toNodeID = "to_node_id"
    case successorSegmentIDs = "successor_segment_ids"
    case points
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    topologyEdgeID = try container.decode(String.self, forKey: .topologyEdgeID)
    fromNodeID = try container.decode(String.self, forKey: .fromNodeID)
    toNodeID = try container.decode(String.self, forKey: .toNodeID)
    let decodedSuccessors =
      try container.decodeIfPresent([String].self, forKey: .successorSegmentIDs) ?? []
    guard Set(decodedSuccessors).count == decodedSuccessors.count else {
      throw DecodingError.dataCorruptedError(
        forKey: .successorSegmentIDs,
        in: container,
        debugDescription: "Route Atlas segment successors must be unique"
      )
    }
    successorSegmentIDs = Set(decodedSuccessors)
    points = try container.decode([RouteAtlasPoint].self, forKey: .points)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(topologyEdgeID, forKey: .topologyEdgeID)
    try container.encode(fromNodeID, forKey: .fromNodeID)
    try container.encode(toNodeID, forKey: .toNodeID)
    try container.encode(successorSegmentIDs.sorted(), forKey: .successorSegmentIDs)
    try container.encode(points, forKey: .points)
  }
}

/// A route occurrence remains distinct even when another occurrence uses the
/// same topology edge and schematic segment.
public struct RouteAtlasOccurrenceBinding: Codable, Equatable, Sendable {
  public let occurrenceID: String
  public let occurrenceIndex: Int
  public let segmentID: String

  public init(occurrenceID: String, occurrenceIndex: Int, segmentID: String) {
    self.occurrenceID = occurrenceID
    self.occurrenceIndex = occurrenceIndex
    self.segmentID = segmentID
  }

  enum CodingKeys: String, CodingKey {
    case occurrenceID = "occurrence_id"
    case occurrenceIndex = "occurrence_index"
    case segmentID = "segment_id"
  }
}

/// Reviewed schematic geometry without independently authored road labels.
///
/// Route shields and displayed names must be resolved from snapshot-bound
/// released metadata; this value intentionally exposes no arbitrary label text.
public struct RouteAtlasDefinition: Codable, Equatable, Sendable {
  public let id: String
  public let networkSnapshotID: String
  public let routePlanID: String
  public let topologySliceID: String
  public let nodes: [RouteAtlasLayoutNode]
  public let segments: [RouteAtlasSegment]
  public let occurrenceBindings: [RouteAtlasOccurrenceBinding]
  public let evidence: RouteAtlasEvidence

  public init(
    id: String,
    networkSnapshotID: String,
    routePlanID: String,
    topologySliceID: String,
    nodes: [RouteAtlasLayoutNode],
    segments: [RouteAtlasSegment],
    occurrenceBindings: [RouteAtlasOccurrenceBinding],
    evidence: RouteAtlasEvidence
  ) {
    self.id = id
    self.networkSnapshotID = networkSnapshotID
    self.routePlanID = routePlanID
    self.topologySliceID = topologySliceID
    self.nodes = nodes
    self.segments = segments
    self.occurrenceBindings = occurrenceBindings
    self.evidence = evidence
  }

  enum CodingKeys: String, CodingKey {
    case id = "atlas_id"
    case networkSnapshotID = "network_snapshot_id"
    case routePlanID = "route_plan_id"
    case topologySliceID = "topology_slice_id"
    case nodes
    case segments
    case occurrenceBindings = "occurrence_bindings"
    case evidence
  }
}

public struct RouteAtlasReleaseArtifact: Codable, Equatable, Sendable {
  public let schemaVersion: String
  public let networkSnapshot: NetworkSnapshot
  public let routePlan: RoutePlan
  public let sourceRegistry: RouteAtlasSourceRegistry
  public let topologySlice: RouteAtlasTopologySlice
  public let definition: RouteAtlasDefinition

  public init(
    schemaVersion: String = "1.0",
    networkSnapshot: NetworkSnapshot,
    routePlan: RoutePlan,
    sourceRegistry: RouteAtlasSourceRegistry,
    topologySlice: RouteAtlasTopologySlice,
    definition: RouteAtlasDefinition
  ) {
    self.schemaVersion = schemaVersion
    self.networkSnapshot = networkSnapshot
    self.routePlan = routePlan
    self.sourceRegistry = sourceRegistry
    self.topologySlice = topologySlice
    self.definition = definition
  }

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case networkSnapshot = "network_snapshot"
    case routePlan = "route_plan"
    case sourceRegistry = "source_registry"
    case topologySlice = "topology_slice"
    case definition
  }
}

public enum RouteAtlasReleaseIssue: Equatable, Sendable {
  case invalidArtifactSchemaVersion
  case invalidNetworkSnapshot
  case routePlanSnapshotMismatch
  case invalidRoutePlan
  case invalidTopologySlice
  case topologySnapshotMismatch
  case unreleasedTopologyEvidence
  case invalidTopologyEvidence
  case invalidSourceRegistry
  case duplicateSourceReference(String)
  case orphanSourceReference(String)
  case unresolvedTopologySource(String)
  case invalidTopologySourceRole(String)
  case unresolvedLayoutSource(String)
  case invalidLayoutSourceRole(String)
  case invalidAtlasIdentity
  case atlasSnapshotMismatch
  case atlasRoutePlanMismatch
  case atlasTopologySliceMismatch
  case unreleasedAtlasEvidence
  case invalidAtlasEvidence
  case duplicateLayoutNodeID(String)
  case missingLayoutNode(String)
  case unknownLayoutNode(String)
  case invalidLayoutNode(String)
  case duplicateSegmentID(String)
  case duplicateTopologyEdgeBinding(String)
  case missingTopologyEdge(String)
  case unknownTopologyEdge(String)
  case segmentEndpointMismatch(String)
  case invalidSegmentGeometry(String)
  case segmentSuccessorMismatch(String)
  case duplicateOccurrenceBinding(String)
  case occurrenceBindingOrderMismatch
  case missingOccurrenceBinding(String)
  case unknownOccurrenceBinding(String)
  case occurrenceIndexMismatch(String)
  case occurrenceEntityMismatch(String)

  public var code: String {
    switch self {
    case .invalidArtifactSchemaVersion:
      "INVALID_ATLAS_ARTIFACT_SCHEMA_VERSION"
    case .invalidNetworkSnapshot:
      "INVALID_NETWORK_SNAPSHOT"
    case .routePlanSnapshotMismatch:
      "ROUTE_PLAN_SNAPSHOT_MISMATCH"
    case .invalidRoutePlan:
      "INVALID_ROUTE_PLAN"
    case .invalidTopologySlice:
      "INVALID_ATLAS_TOPOLOGY_SLICE"
    case .topologySnapshotMismatch:
      "ATLAS_TOPOLOGY_SNAPSHOT_MISMATCH"
    case .unreleasedTopologyEvidence:
      "UNRELEASED_ATLAS_TOPOLOGY_EVIDENCE"
    case .invalidTopologyEvidence:
      "INVALID_ATLAS_TOPOLOGY_EVIDENCE"
    case .invalidSourceRegistry:
      "INVALID_ATLAS_SOURCE_REGISTRY"
    case .duplicateSourceReference:
      "DUPLICATE_ATLAS_SOURCE_REFERENCE"
    case .orphanSourceReference:
      "ORPHAN_ATLAS_SOURCE_REFERENCE"
    case .unresolvedTopologySource:
      "UNRESOLVED_ATLAS_TOPOLOGY_SOURCE"
    case .invalidTopologySourceRole:
      "INVALID_ATLAS_TOPOLOGY_SOURCE_ROLE"
    case .unresolvedLayoutSource:
      "UNRESOLVED_ATLAS_LAYOUT_SOURCE"
    case .invalidLayoutSourceRole:
      "INVALID_ATLAS_LAYOUT_SOURCE_ROLE"
    case .invalidAtlasIdentity:
      "INVALID_ATLAS_IDENTITY"
    case .atlasSnapshotMismatch:
      "ATLAS_SNAPSHOT_MISMATCH"
    case .atlasRoutePlanMismatch:
      "ATLAS_ROUTE_PLAN_MISMATCH"
    case .atlasTopologySliceMismatch:
      "ATLAS_TOPOLOGY_SLICE_MISMATCH"
    case .unreleasedAtlasEvidence:
      "UNRELEASED_ATLAS_EVIDENCE"
    case .invalidAtlasEvidence:
      "INVALID_ATLAS_EVIDENCE"
    case .duplicateLayoutNodeID:
      "DUPLICATE_ATLAS_NODE_ID"
    case .missingLayoutNode:
      "MISSING_ATLAS_NODE"
    case .unknownLayoutNode:
      "UNKNOWN_ATLAS_NODE"
    case .invalidLayoutNode:
      "INVALID_ATLAS_NODE"
    case .duplicateSegmentID:
      "DUPLICATE_ATLAS_SEGMENT_ID"
    case .duplicateTopologyEdgeBinding:
      "DUPLICATE_ATLAS_TOPOLOGY_EDGE"
    case .missingTopologyEdge:
      "MISSING_ATLAS_TOPOLOGY_EDGE"
    case .unknownTopologyEdge:
      "UNKNOWN_ATLAS_TOPOLOGY_EDGE"
    case .segmentEndpointMismatch:
      "ATLAS_SEGMENT_ENDPOINT_MISMATCH"
    case .invalidSegmentGeometry:
      "INVALID_ATLAS_SEGMENT_GEOMETRY"
    case .segmentSuccessorMismatch:
      "ATLAS_SUCCESSOR_MISMATCH"
    case .duplicateOccurrenceBinding:
      "DUPLICATE_ATLAS_OCCURRENCE_BINDING"
    case .occurrenceBindingOrderMismatch:
      "ATLAS_OCCURRENCE_ORDER_MISMATCH"
    case .missingOccurrenceBinding:
      "MISSING_ATLAS_OCCURRENCE_BINDING"
    case .unknownOccurrenceBinding:
      "UNKNOWN_ATLAS_OCCURRENCE_BINDING"
    case .occurrenceIndexMismatch:
      "ATLAS_OCCURRENCE_INDEX_MISMATCH"
    case .occurrenceEntityMismatch:
      "ATLAS_OCCURRENCE_ENTITY_MISMATCH"
    }
  }

  var sortKey: String {
    switch self {
    case .duplicateSourceReference(let id),
      .orphanSourceReference(let id),
      .unresolvedTopologySource(let id),
      .invalidTopologySourceRole(let id),
      .unresolvedLayoutSource(let id),
      .invalidLayoutSourceRole(let id),
      .duplicateLayoutNodeID(let id),
      .missingLayoutNode(let id),
      .unknownLayoutNode(let id),
      .invalidLayoutNode(let id),
      .duplicateSegmentID(let id),
      .duplicateTopologyEdgeBinding(let id),
      .missingTopologyEdge(let id),
      .unknownTopologyEdge(let id),
      .segmentEndpointMismatch(let id),
      .invalidSegmentGeometry(let id),
      .segmentSuccessorMismatch(let id),
      .duplicateOccurrenceBinding(let id),
      .missingOccurrenceBinding(let id),
      .unknownOccurrenceBinding(let id),
      .occurrenceIndexMismatch(let id),
      .occurrenceEntityMismatch(let id):
      "\(code):\(id)"
    default:
      code
    }
  }
}

public enum RouteAtlasReleaseError: Error, Equatable, Sendable {
  case invalid([RouteAtlasReleaseIssue])
}

/// A fail-closed, renderer-neutral atlas release for one exact route and network
/// snapshot.
///
/// This type proves internal identity, coverage, and connection integrity. It
/// does not establish that synthetic data or an unreviewed source graph is true
/// on the real road.
public struct RouteAtlasRelease: Equatable, Sendable {
  public let networkSnapshot: NetworkSnapshot
  public let routePlan: RoutePlan
  public let sourceRegistry: RouteAtlasSourceRegistry
  public let topologySlice: RouteAtlasTopologySlice
  public let definition: RouteAtlasDefinition

  public init(
    networkSnapshot: NetworkSnapshot,
    routePlan: RoutePlan,
    sourceRegistry: RouteAtlasSourceRegistry,
    topologySlice: RouteAtlasTopologySlice,
    definition: RouteAtlasDefinition
  ) throws {
    let issues = Self.validationIssues(
      networkSnapshot: networkSnapshot,
      routePlan: routePlan,
      sourceRegistry: sourceRegistry,
      topologySlice: topologySlice,
      definition: definition
    )
    guard issues.isEmpty else {
      throw RouteAtlasReleaseError.invalid(issues)
    }
    self.networkSnapshot = networkSnapshot
    self.routePlan = routePlan
    self.sourceRegistry = sourceRegistry
    self.topologySlice = topologySlice
    self.definition = definition
  }

  public init(artifact: RouteAtlasReleaseArtifact) throws {
    var issues = Self.validationIssues(
      networkSnapshot: artifact.networkSnapshot,
      routePlan: artifact.routePlan,
      sourceRegistry: artifact.sourceRegistry,
      topologySlice: artifact.topologySlice,
      definition: artifact.definition
    )
    if artifact.schemaVersion != "1.0" {
      issues.append(.invalidArtifactSchemaVersion)
    }
    issues = Self.sortedUnique(issues)
    guard issues.isEmpty else {
      throw RouteAtlasReleaseError.invalid(issues)
    }
    self.networkSnapshot = artifact.networkSnapshot
    self.routePlan = artifact.routePlan
    self.sourceRegistry = artifact.sourceRegistry
    self.topologySlice = artifact.topologySlice
    self.definition = artifact.definition
  }

  private static func validationIssues(
    networkSnapshot: NetworkSnapshot,
    routePlan: RoutePlan,
    sourceRegistry: RouteAtlasSourceRegistry,
    topologySlice: RouteAtlasTopologySlice,
    definition: RouteAtlasDefinition
  ) -> [RouteAtlasReleaseIssue] {
    var issues: [RouteAtlasReleaseIssue] = []

    var sourcesByID: [String: RouteAtlasSourceReference] = [:]
    for source in sourceRegistry.references {
      if sourcesByID[source.id] != nil {
        issues.append(.duplicateSourceReference(source.id))
      } else {
        sourcesByID[source.id] = source
      }
    }
    if sourceRegistry.references.isEmpty
      || sourceRegistry.references.contains(where: {
        normalized($0.id).isEmpty
          || normalized($0.authorityName).isEmpty
          || !isHTTPSURL($0.sourceURL)
          || !isSHA256($0.contentSHA256)
          || !isISODate($0.checkedAt)
          || normalized($0.licenceIdentifier).isEmpty
          || $0.roles.isEmpty
      })
    {
      issues.append(.invalidSourceRegistry)
    }

    if normalized(networkSnapshot.id).isEmpty
      || networkSnapshot.status != .active
      || !isISO8601DateTime(networkSnapshot.effectiveAt)
    {
      issues.append(.invalidNetworkSnapshot)
    }
    if routePlan.networkSnapshotID != networkSnapshot.id {
      issues.append(.routePlanSnapshotMismatch)
    }
    if !routePlanIsValid(routePlan) {
      issues.append(.invalidRoutePlan)
    }
    if topologySlice.networkSnapshotID != networkSnapshot.id {
      issues.append(.topologySnapshotMismatch)
    }
    if topologySlice.evidence.state != .released {
      issues.append(.unreleasedTopologyEvidence)
    }
    if !evidenceIsValid(topologySlice.evidence) {
      issues.append(.invalidTopologyEvidence)
    }
    for sourceID in topologySlice.evidence.sourceReferenceIDs {
      guard let source = sourcesByID[sourceID] else {
        issues.append(.unresolvedTopologySource(sourceID))
        continue
      }
      if !source.roles.contains(.topologyEvidence) {
        issues.append(.invalidTopologySourceRole(sourceID))
      }
      if source.checkedAt > topologySlice.evidence.checkedAt {
        issues.append(.invalidTopologyEvidence)
      }
    }

    let topologyNodeIDs = topologySlice.nodes.map(\.id)
    let topologyNodeIDSet = Set(topologyNodeIDs)
    let topologyEdgeIDs = topologySlice.edges.map(\.id)
    let topologyEdgeIDSet = Set(topologyEdgeIDs)
    var topologyEdgesByID: [String: RouteAtlasTopologyEdge] = [:]
    for edge in topologySlice.edges where topologyEdgesByID[edge.id] == nil {
      topologyEdgesByID[edge.id] = edge
    }
    let successorsAreContinuous = topologySlice.edges.allSatisfy { edge in
      edge.successorEdgeIDs.allSatisfy { successorID in
        topologyEdgesByID[successorID]?.fromNodeID == edge.toNodeID
      }
    }
    let topologyIsValid =
      !normalized(topologySlice.id).isEmpty
      && !topologySlice.nodes.isEmpty
      && !topologySlice.edges.isEmpty
      && topologyNodeIDSet.count == topologyNodeIDs.count
      && topologyEdgeIDSet.count == topologyEdgeIDs.count
      && Set(topologySlice.edges.map(\.routeEntityID)).count
        == topologySlice.edges.count
      && topologySlice.nodes.allSatisfy { !normalized($0.id).isEmpty }
      && topologySlice.edges.allSatisfy { edge in
        !normalized(edge.id).isEmpty
          && !normalized(edge.routeEntityID).isEmpty
          && topologyNodeIDSet.contains(edge.fromNodeID)
          && topologyNodeIDSet.contains(edge.toNodeID)
          && edge.fromNodeID != edge.toNodeID
          && edge.successorEdgeIDs.isSubset(of: topologyEdgeIDSet)
      }
      && successorsAreContinuous
    if !topologyIsValid {
      issues.append(.invalidTopologySlice)
    }

    if normalized(definition.id).isEmpty
      || normalized(definition.networkSnapshotID).isEmpty
      || normalized(definition.routePlanID).isEmpty
      || normalized(definition.topologySliceID).isEmpty
    {
      issues.append(.invalidAtlasIdentity)
    }
    if definition.networkSnapshotID != networkSnapshot.id {
      issues.append(.atlasSnapshotMismatch)
    }
    if definition.routePlanID != routePlan.id {
      issues.append(.atlasRoutePlanMismatch)
    }
    if definition.topologySliceID != topologySlice.id {
      issues.append(.atlasTopologySliceMismatch)
    }
    if definition.evidence.state != .released {
      issues.append(.unreleasedAtlasEvidence)
    }
    if !evidenceIsValid(definition.evidence) {
      issues.append(.invalidAtlasEvidence)
    }
    for sourceID in definition.evidence.sourceReferenceIDs {
      guard let source = sourcesByID[sourceID] else {
        issues.append(.unresolvedLayoutSource(sourceID))
        continue
      }
      if !source.roles.contains(.layoutEvidence) {
        issues.append(.invalidLayoutSourceRole(sourceID))
      }
      if source.checkedAt > definition.evidence.checkedAt {
        issues.append(.invalidAtlasEvidence)
      }
    }
    let referencedSourceIDs = Set(
      topologySlice.evidence.sourceReferenceIDs
        + definition.evidence.sourceReferenceIDs
    )
    for sourceID in sourcesByID.keys where !referencedSourceIDs.contains(sourceID) {
      issues.append(.orphanSourceReference(sourceID))
    }

    var layoutNodesByID: [String: RouteAtlasLayoutNode] = [:]
    for node in definition.nodes {
      if layoutNodesByID[node.topologyNodeID] != nil {
        issues.append(.duplicateLayoutNodeID(node.topologyNodeID))
      } else {
        layoutNodesByID[node.topologyNodeID] = node
      }
      if !topologyNodeIDSet.contains(node.topologyNodeID) {
        issues.append(.unknownLayoutNode(node.topologyNodeID))
      }
      if !pointIsValid(node.point) {
        issues.append(.invalidLayoutNode(node.topologyNodeID))
      }
    }
    for nodeID in topologyNodeIDSet where layoutNodesByID[nodeID] == nil {
      issues.append(.missingLayoutNode(nodeID))
    }

    var segmentsByID: [String: RouteAtlasSegment] = [:]
    var segmentByTopologyEdgeID: [String: RouteAtlasSegment] = [:]
    for segment in definition.segments {
      if segmentsByID[segment.id] != nil {
        issues.append(.duplicateSegmentID(segment.id))
      } else {
        segmentsByID[segment.id] = segment
      }
      if segmentByTopologyEdgeID[segment.topologyEdgeID] != nil {
        issues.append(.duplicateTopologyEdgeBinding(segment.topologyEdgeID))
      } else {
        segmentByTopologyEdgeID[segment.topologyEdgeID] = segment
      }
      if !topologyEdgeIDSet.contains(segment.topologyEdgeID) {
        issues.append(.unknownTopologyEdge(segment.topologyEdgeID))
      }
      guard
        let topologyEdge = topologySlice.edges.first(where: {
          $0.id == segment.topologyEdgeID
        })
      else {
        continue
      }
      if segment.fromNodeID != topologyEdge.fromNodeID
        || segment.toNodeID != topologyEdge.toNodeID
      {
        issues.append(.segmentEndpointMismatch(segment.id))
      }
      guard let fromNode = layoutNodesByID[segment.fromNodeID],
        let toNode = layoutNodesByID[segment.toNodeID],
        segment.points.count >= 2,
        segment.points.allSatisfy(pointIsValid),
        segment.points.first == fromNode.point,
        segment.points.last == toNode.point
      else {
        issues.append(.invalidSegmentGeometry(segment.id))
        continue
      }
    }
    for edgeID in topologyEdgeIDSet where segmentByTopologyEdgeID[edgeID] == nil {
      issues.append(.missingTopologyEdge(edgeID))
    }

    for topologyEdge in topologySlice.edges {
      guard let segment = segmentByTopologyEdgeID[topologyEdge.id] else { continue }
      let expectedSuccessors = Set(
        topologyEdge.successorEdgeIDs.compactMap {
          segmentByTopologyEdgeID[$0]?.id
        }
      )
      if segment.successorSegmentIDs != expectedSuccessors
        || !segment.successorSegmentIDs.isSubset(of: Set(segmentsByID.keys))
      {
        issues.append(.segmentSuccessorMismatch(segment.id))
      }
    }

    var routeOccurrencesByID: [String: RouteOccurrence] = [:]
    for occurrence in routePlan.occurrences where routeOccurrencesByID[occurrence.id] == nil {
      routeOccurrencesByID[occurrence.id] = occurrence
    }
    var bindingsByOccurrenceID: [String: RouteAtlasOccurrenceBinding] = [:]
    if definition.occurrenceBindings.map(\.occurrenceID)
      != routePlan.occurrences.map(\.id)
    {
      issues.append(.occurrenceBindingOrderMismatch)
    }
    for binding in definition.occurrenceBindings {
      if bindingsByOccurrenceID[binding.occurrenceID] != nil {
        issues.append(.duplicateOccurrenceBinding(binding.occurrenceID))
      } else {
        bindingsByOccurrenceID[binding.occurrenceID] = binding
      }
      guard let occurrence = routeOccurrencesByID[binding.occurrenceID] else {
        issues.append(.unknownOccurrenceBinding(binding.occurrenceID))
        continue
      }
      if binding.occurrenceIndex != occurrence.index {
        issues.append(.occurrenceIndexMismatch(binding.occurrenceID))
      }
      guard let segment = segmentsByID[binding.segmentID],
        let edge = topologySlice.edges.first(where: {
          $0.id == segment.topologyEdgeID
        }),
        edge.routeEntityID == occurrence.entityID
      else {
        issues.append(.occurrenceEntityMismatch(binding.occurrenceID))
        continue
      }
    }
    for occurrence in routePlan.occurrences
    where bindingsByOccurrenceID[occurrence.id] == nil {
      issues.append(.missingOccurrenceBinding(occurrence.id))
    }

    return sortedUnique(issues)
  }

  private static func routePlanIsValid(_ routePlan: RoutePlan) -> Bool {
    let occurrenceIDs = routePlan.occurrences.map(\.id)
    return !normalized(routePlan.id).isEmpty
      && !normalized(routePlan.networkSnapshotID).isEmpty
      && !routePlan.occurrences.isEmpty
      && Set(occurrenceIDs).count == occurrenceIDs.count
      && routePlan.occurrences.map(\.index) == Array(0..<routePlan.occurrences.count)
      && routePlan.occurrences.allSatisfy {
        !normalized($0.id).isEmpty && !normalized($0.entityID).isEmpty
      }
  }

  private static func pointIsValid(_ point: RouteAtlasPoint) -> Bool {
    point.x.isFinite && point.y.isFinite
      && (0...1).contains(point.x) && (0...1).contains(point.y)
  }

  private static func evidenceIsValid(_ evidence: RouteAtlasEvidence) -> Bool {
    isISODate(evidence.checkedAt)
      && !evidence.sourceReferenceIDs.isEmpty
      && Set(evidence.sourceReferenceIDs).count
        == evidence.sourceReferenceIDs.count
      && evidence.sourceReferenceIDs.allSatisfy { !normalized($0).isEmpty }
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func isISO8601DateTime(_ value: String) -> Bool {
    let standard = ISO8601DateFormatter()
    if standard.date(from: value) != nil {
      return true
    }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value) != nil
  }

  private static func isHTTPSURL(_ value: String) -> Bool {
    guard let components = URLComponents(string: value) else {
      return false
    }
    return components.scheme == "https" && !(components.host ?? "").isEmpty
  }

  private static func isSHA256(_ value: String) -> Bool {
    value.count == 64
      && value.utf8.allSatisfy { byte in
        (48...57).contains(byte)
          || (65...70).contains(byte)
          || (97...102).contains(byte)
      }
  }

  private static func isISODate(_ value: String) -> Bool {
    let parts = value.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3,
      parts[0].count == 4,
      parts[1].count == 2,
      parts[2].count == 2,
      let year = Int(parts[0]),
      let month = Int(parts[1]),
      let day = Int(parts[2])
    else {
      return false
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let components = DateComponents(
      calendar: calendar,
      timeZone: calendar.timeZone,
      year: year,
      month: month,
      day: day
    )
    guard let date = components.date else { return false }
    let resolved = calendar.dateComponents([.year, .month, .day], from: date)
    return resolved.year == year && resolved.month == month && resolved.day == day
  }

  private static func sortedUnique(
    _ issues: [RouteAtlasReleaseIssue]
  ) -> [RouteAtlasReleaseIssue] {
    issues.sorted { $0.sortKey < $1.sortKey }.reduce(into: []) { result, issue in
      if result.last != issue {
        result.append(issue)
      }
    }
  }
}
