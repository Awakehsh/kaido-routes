import Foundation
import KaidoDomain

public enum RouteAtlasEvidenceState: String, Sendable {
  case candidate = "CANDIDATE"
  case officialChecked = "OFFICIAL_CHECKED"
  case fieldChecked = "FIELD_CHECKED"
  case released = "RELEASED"
}

public struct RouteAtlasEvidence: Equatable, Sendable {
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
}

public struct RouteAtlasTopologyNode: Equatable, Sendable {
  public let id: String

  public init(id: String) {
    self.id = id
  }
}

/// One displayable directed part of a reviewed network slice.
///
/// `routeEntityID` binds the topology back to the exact entity used by a
/// RoutePlan occurrence. Successors are authored by the reviewed graph and are
/// never inferred from schematic geometry.
public struct RouteAtlasTopologyEdge: Equatable, Sendable {
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
}

/// The reviewed graph truth for the exact network coverage visible in an atlas.
public struct RouteAtlasTopologySlice: Equatable, Sendable {
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
}

/// A renderer-neutral point in a normalized north-up atlas coordinate space.
public struct RouteAtlasPoint: Equatable, Sendable {
  public let x: Double
  public let y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

public struct RouteAtlasLayoutNode: Equatable, Sendable {
  public let topologyNodeID: String
  public let point: RouteAtlasPoint

  public init(topologyNodeID: String, point: RouteAtlasPoint) {
    self.topologyNodeID = topologyNodeID
    self.point = point
  }
}

/// One schematic path with an exact one-to-one topology-edge binding.
///
/// A renderer may simplify these points visually, but it must use
/// `successorSegmentIDs` for interaction and highlighting. Coordinate crossings
/// never create a graph connection.
public struct RouteAtlasSegment: Equatable, Sendable {
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
}

/// A route occurrence remains distinct even when another occurrence uses the
/// same topology edge and schematic segment.
public struct RouteAtlasOccurrenceBinding: Equatable, Sendable {
  public let occurrenceID: String
  public let occurrenceIndex: Int
  public let segmentID: String

  public init(occurrenceID: String, occurrenceIndex: Int, segmentID: String) {
    self.occurrenceID = occurrenceID
    self.occurrenceIndex = occurrenceIndex
    self.segmentID = segmentID
  }
}

/// Reviewed schematic geometry without independently authored road labels.
///
/// Route shields and displayed names must be resolved from snapshot-bound
/// released metadata; this value intentionally exposes no arbitrary label text.
public struct RouteAtlasDefinition: Equatable, Sendable {
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
}

public enum RouteAtlasReleaseIssue: Equatable, Sendable {
  case invalidNetworkSnapshot
  case routePlanSnapshotMismatch
  case invalidRoutePlan
  case invalidTopologySlice
  case topologySnapshotMismatch
  case unreleasedTopologyEvidence
  case invalidTopologyEvidence
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

  fileprivate var sortKey: String {
    switch self {
    case .duplicateLayoutNodeID(let id),
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
  public let topologySlice: RouteAtlasTopologySlice
  public let definition: RouteAtlasDefinition

  public init(
    networkSnapshot: NetworkSnapshot,
    routePlan: RoutePlan,
    topologySlice: RouteAtlasTopologySlice,
    definition: RouteAtlasDefinition
  ) throws {
    let issues = Self.validationIssues(
      networkSnapshot: networkSnapshot,
      routePlan: routePlan,
      topologySlice: topologySlice,
      definition: definition
    )
    guard issues.isEmpty else {
      throw RouteAtlasReleaseError.invalid(issues)
    }
    self.networkSnapshot = networkSnapshot
    self.routePlan = routePlan
    self.topologySlice = topologySlice
    self.definition = definition
  }

  private static func validationIssues(
    networkSnapshot: NetworkSnapshot,
    routePlan: RoutePlan,
    topologySlice: RouteAtlasTopologySlice,
    definition: RouteAtlasDefinition
  ) -> [RouteAtlasReleaseIssue] {
    var issues: [RouteAtlasReleaseIssue] = []

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
      guard let topologyEdge = topologySlice.edges.first(where: {
        $0.id == segment.topologyEdgeID
      }) else {
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
