import CryptoKit
import Foundation
import KaidoDomain
import KaidoRouting

public enum ShutoPlannedRouteRuntimeCompilationError:
  Error, Equatable, Sendable
{
  case networkSnapshotMismatch
  case invalidRoutePlanBinding
  case facilityBindingMismatch
  case networkEdgeBindingMismatch
  case routeGeometryMismatch
  case discontinuousRouteEdgeOrder
  case missingNode(Int64)
  case invalidMatcherCorridor([String])
  case assetIdentityEncodingFailed
}

public struct ShutoRouteRuntimeProgress: Equatable, Sendable {
  public let occurrenceID: String
  public let occurrenceIndex: Int
  public let directedEdgeID: String
  public let fractionAlongOccurrence: Double
  public let distanceAlongRouteMeters: Double
  public let routeProgressFraction: Double
  public let coordinate: ShutoCoordinate

  public init(
    occurrenceID: String,
    occurrenceIndex: Int,
    directedEdgeID: String,
    fractionAlongOccurrence: Double,
    distanceAlongRouteMeters: Double,
    routeProgressFraction: Double,
    coordinate: ShutoCoordinate
  ) {
    self.occurrenceID = occurrenceID
    self.occurrenceIndex = occurrenceIndex
    self.directedEdgeID = directedEdgeID
    self.fractionAlongOccurrence = fractionAlongOccurrence
    self.distanceAlongRouteMeters = distanceAlongRouteMeters
    self.routeProgressFraction = routeProgressFraction
    self.coordinate = coordinate
  }
}

public enum ShutoRouteDecisionKind: String, Codable, Equatable, Sendable {
  case junction = "JUNCTION"
  case graphDivergence = "GRAPH_DIVERGENCE"
}

public struct ShutoRouteDecisionCoverage: Codable, Equatable, Sendable {
  public let kind: ShutoRouteDecisionKind
  public let divergenceOccurrenceID: String
  public let plannedOutgoingOccurrenceID: String
  public let junctionNodeID: Int64
  public let incomingDirectedEdgeID: String
  public let plannedOutgoingDirectedEdgeID: String
  public let alternativeOutgoingDirectedEdgeIDs: [String]
  public let releasedGuidanceDefinitionID: String?

  private enum CodingKeys: String, CodingKey {
    case kind
    case divergenceOccurrenceID = "divergence_occurrence_id"
    case plannedOutgoingOccurrenceID = "planned_outgoing_occurrence_id"
    case junctionNodeID = "junction_node_id"
    case incomingDirectedEdgeID = "incoming_directed_edge_id"
    case plannedOutgoingDirectedEdgeID = "planned_outgoing_directed_edge_id"
    case alternativeOutgoingDirectedEdgeIDs =
      "alternative_outgoing_directed_edge_ids"
    case releasedGuidanceDefinitionID = "released_guidance_definition_id"
  }
}

public struct ShutoRouteRecoveryBranchCoverage:
  Codable, Equatable, Sendable
{
  public enum Kind: String, Codable, Equatable, Sendable {
    case expresswayBranch = "EXPRESSWAY_BRANCH"
    case surfaceExit = "SURFACE_EXIT"
    case missedExit = "MISSED_EXIT"
    case unavailableExpresswayBranch = "UNAVAILABLE_EXPRESSWAY_BRANCH"
  }

  public let kind: Kind
  public let divergenceOccurrenceID: String
  public let triggerDirectedEdgeID: String
  public let candidateTargetOccurrenceID: String?
  public let candidateIsReleased: Bool

  private enum CodingKeys: String, CodingKey {
    case kind
    case divergenceOccurrenceID = "divergence_occurrence_id"
    case triggerDirectedEdgeID = "trigger_directed_edge_id"
    case candidateTargetOccurrenceID = "candidate_target_occurrence_id"
    case candidateIsReleased = "candidate_is_released"
  }
}

/// Route-local expressway coverage required before a release may admit live
/// observations. This report does not cover surface access/egress, freshness,
/// audio review, or field evidence and grants no navigation authority.
public struct ShutoRouteLiveReleaseCoverage:
  Codable, Equatable, Sendable
{
  public let networkSnapshotID: String
  public let routePlanID: String
  public let decisions: [ShutoRouteDecisionCoverage]
  public let recoveryBranches: [ShutoRouteRecoveryBranchCoverage]

  public var missingGuidanceDecisionCount: Int {
    decisions.count {
      $0.kind == .junction && $0.releasedGuidanceDefinitionID == nil
    }
  }

  public var guidanceDecisionCount: Int {
    decisions.count { $0.kind == .junction }
  }

  public var nonJunctionGraphDivergenceCount: Int {
    decisions.count { $0.kind == .graphDivergence }
  }

  public var missingReleasedRecoveryBranchCount: Int {
    recoveryBranches.count { !$0.candidateIsReleased }
  }

  public func recoveryBranchCount(
    kind: ShutoRouteRecoveryBranchCoverage.Kind
  ) -> Int {
    recoveryBranches.count { $0.kind == kind }
  }

  public func missingRecoveryCandidateBranchCount(
    kind: ShutoRouteRecoveryBranchCoverage.Kind
  ) -> Int {
    recoveryBranches.count {
      $0.kind == kind && $0.candidateTargetOccurrenceID == nil
    }
  }

  public var missingRecoveryCandidateBranchCount: Int {
    recoveryBranches.count { $0.candidateTargetOccurrenceID == nil }
  }

  public var expresswayReleaseCoverageComplete: Bool {
    missingGuidanceDecisionCount == 0
      && missingReleasedRecoveryBranchCount == 0
  }

  private enum CodingKeys: String, CodingKey {
    case networkSnapshotID = "network_snapshot_id"
    case routePlanID = "route_plan_id"
    case decisions
    case recoveryBranches = "recovery_branches"
  }
}

public struct ShutoNetworkJunctionMovementCoverage:
  Codable, Equatable, Sendable
{
  public let junctionID: String
  public let junctionNameJapanese: String
  public let junctionNodeID: Int64
  public let incomingDirectedEdgeID: String
  public let incomingRouteMemberships: [ShutoNetworkDatabase.RouteMembership]
  public let incomingWayTags: [String: String]
  public let outgoingDirectedEdgeID: String
  public let outgoingRouteMemberships: [ShutoNetworkDatabase.RouteMembership]
  public let outgoingWayTags: [String: String]
  public let releasedGuidanceDefinitionID: String?
  public let officialDetailReference: String
  public let officialDetailSHA256: String

  private enum CodingKeys: String, CodingKey {
    case junctionID = "junction_id"
    case junctionNameJapanese = "junction_name_ja"
    case junctionNodeID = "junction_node_id"
    case incomingDirectedEdgeID = "incoming_directed_edge_id"
    case incomingRouteMemberships = "incoming_route_memberships"
    case incomingWayTags = "incoming_way_tags"
    case outgoingDirectedEdgeID = "outgoing_directed_edge_id"
    case outgoingRouteMemberships = "outgoing_route_memberships"
    case outgoingWayTags = "outgoing_way_tags"
    case releasedGuidanceDefinitionID = "released_guidance_definition_id"
    case officialDetailReference = "official_detail_reference"
    case officialDetailSHA256 = "official_detail_sha256"
  }
}

/// Snapshot-wide worklist for movements between available expressway
/// mainlines at a real branching JCT. Terminal exits and unavailable routes
/// stay in route-local recovery/egress coverage. This is an authoring
/// inventory, not proof that graph adjacency is a legal or released movement.
public struct ShutoNetworkLiveReleaseCoverage:
  Codable, Equatable, Sendable
{
  public let networkSnapshotID: String
  public let movements: [ShutoNetworkJunctionMovementCoverage]

  public var incomingApproachCount: Int {
    Set(
      movements.map {
        "\($0.junctionID)|\($0.junctionNodeID)|\($0.incomingDirectedEdgeID)"
      }
    ).count
  }

  public var junctionCount: Int {
    Set(movements.map(\.junctionID)).count
  }

  public var releasedMovementCount: Int {
    movements.count { $0.releasedGuidanceDefinitionID != nil }
  }

  public var missingMovementReviewCount: Int {
    movements.count - releasedMovementCount
  }

  private enum CodingKeys: String, CodingKey {
    case networkSnapshotID = "network_snapshot_id"
    case movements
  }
}

/// A deterministic integrity binding for one whole-Shuto network artifact and
/// the exact route-local runtime assets compiled from it.
///
/// This is not a `KaidoProductRelease` and grants no live-input or navigation
/// authority. It only proves that the candidate runtime inputs agree at the
/// canonical semantic layer; it cannot promote OSM/provider geometry,
/// unreviewed movements, lane data, realtime state, or field observations.
public struct ShutoRuntimeAssetIdentity: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = "1.0"

  public let schemaVersion: String
  public let networkArtifactID: String
  public let networkArtifactSHA256: String
  public let routeRuntimeID: String
  public let routeRuntimeSHA256: String
  public let networkSnapshotID: String
  public let routePlanID: String
  public let verificationState: String

  package init(
    schemaVersion: String = ShutoRuntimeAssetIdentity.currentSchemaVersion,
    networkArtifactID: String,
    networkArtifactSHA256: String,
    routeRuntimeID: String,
    routeRuntimeSHA256: String,
    networkSnapshotID: String,
    routePlanID: String,
    verificationState: String
  ) {
    self.schemaVersion = schemaVersion
    self.networkArtifactID = networkArtifactID
    self.networkArtifactSHA256 = networkArtifactSHA256
    self.routeRuntimeID = routeRuntimeID
    self.routeRuntimeSHA256 = routeRuntimeSHA256
    self.networkSnapshotID = networkSnapshotID
    self.routePlanID = routePlanID
    self.verificationState = verificationState
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case networkArtifactID = "network_artifact_id"
    case networkArtifactSHA256 = "network_artifact_sha256"
    case routeRuntimeID = "route_runtime_id"
    case routeRuntimeSHA256 = "route_runtime_sha256"
    case networkSnapshotID = "network_snapshot_id"
    case routePlanID = "route_plan_id"
    case verificationState = "verification_state"
  }
}

/// Exact matcher inputs compiled from one selected whole-Shuto route.
///
/// The corridor includes every ordered RoutePlan edge plus graph-adjacent
/// alternatives at route nodes. Alternative edges let the matcher abstain or
/// report a deviation without allowing a provider to mutate the RoutePlan.
public struct ShutoPlannedRouteRuntimeAssets: Equatable, Sendable {
  public let runtimeAssetIdentity: ShutoRuntimeAssetIdentity
  public let routePlan: RoutePlan
  public let matcherCorridor: RouteMatcherCorridor
  public let decisionZones: [DecisionZoneProgressDefinition]
  public let releasedGuidance: [ReleasedGuidanceDefinition]
  public let recoveryCandidates: [RecoveryCandidate]
  public let liveReleaseCoverage: ShutoRouteLiveReleaseCoverage

  private let routeEdges: [RouteMatcherDirectedEdge]
  private let routeEdgeLengthsMeters: [Double]
  private let cumulativeDistanceAtOccurrence: [Double]
  private let totalDistanceMeters: Double

  package init(
    runtimeAssetIdentity: ShutoRuntimeAssetIdentity,
    routePlan: RoutePlan,
    matcherCorridor: RouteMatcherCorridor,
    decisionZones: [DecisionZoneProgressDefinition],
    releasedGuidance: [ReleasedGuidanceDefinition],
    recoveryCandidates: [RecoveryCandidate] = [],
    liveReleaseCoverage: ShutoRouteLiveReleaseCoverage,
    routeEdges: [RouteMatcherDirectedEdge],
    routeEdgeLengthsMeters: [Double]
  ) {
    self.runtimeAssetIdentity = runtimeAssetIdentity
    self.routePlan = routePlan
    self.matcherCorridor = matcherCorridor
    self.decisionZones = decisionZones
    self.releasedGuidance = releasedGuidance
    self.recoveryCandidates = recoveryCandidates
    self.liveReleaseCoverage = liveReleaseCoverage
    self.routeEdges = routeEdges
    self.routeEdgeLengthsMeters = routeEdgeLengthsMeters

    var cumulative = [0.0]
    cumulative.reserveCapacity(routeEdges.count)
    for lengthMeters in routeEdgeLengthsMeters.dropLast() {
      cumulative.append(cumulative.last! + lengthMeters)
    }
    cumulativeDistanceAtOccurrence = cumulative
    totalDistanceMeters = routeEdgeLengthsMeters.reduce(0, +)
  }

  /// Projects only an unambiguous HIGH matcher commit onto route progress.
  ///
  /// LOW, stale, stacked-road, off-route, or incomplete evidence returns nil
  /// so callers preserve their last admitted progress and expose degradation.
  public func project(
    _ estimate: MatcherEstimate
  ) -> ShutoRouteRuntimeProgress? {
    guard estimate.confidence == .high,
      let occurrenceID = estimate.occurrenceID,
      let directedEdgeID = estimate.directedEdgeID,
      estimate.candidateEdgeIDs == [directedEdgeID],
      let fraction = estimate.fractionAlongEdge,
      fraction.isFinite,
      (0...1).contains(fraction),
      let occurrence = routePlan.occurrence(id: occurrenceID),
      matcherCorridor.occurrences.first(where: {
        $0.id == occurrenceID
          && $0.index == occurrence.index
          && $0.directedEdgeID == directedEdgeID
      }) != nil,
      routeEdges.indices.contains(occurrence.index),
      routeEdgeLengthsMeters.indices.contains(occurrence.index),
      cumulativeDistanceAtOccurrence.indices.contains(occurrence.index),
      totalDistanceMeters > 0
    else {
      return nil
    }

    let edge = routeEdges[occurrence.index]
    guard edge.id == directedEdgeID,
      let start = edge.coordinates.first,
      let end = edge.coordinates.last
    else {
      return nil
    }
    let edgeLengthMeters = routeEdgeLengthsMeters[occurrence.index]
    let distance =
      cumulativeDistanceAtOccurrence[occurrence.index]
      + edgeLengthMeters * fraction
    return ShutoRouteRuntimeProgress(
      occurrenceID: occurrenceID,
      occurrenceIndex: occurrence.index,
      directedEdgeID: directedEdgeID,
      fractionAlongOccurrence: fraction,
      distanceAlongRouteMeters: distance,
      routeProgressFraction: min(1, max(0, distance / totalDistanceMeters)),
      coordinate: ShutoCoordinate(
        latitude: start.latitude + (end.latitude - start.latitude) * fraction,
        longitude: start.longitude + (end.longitude - start.longitude) * fraction
      )
    )
  }
}

public enum ShutoPlannedRouteRuntimeCompiler {
  private struct NetworkArtifactHashPayload: Encodable {
    let schemaVersion: String
    let database: ShutoNetworkDatabase

    private enum CodingKeys: String, CodingKey {
      case schemaVersion = "schema_version"
      case database
    }
  }

  private struct CanonicalMatcherEdge: Encodable {
    let id: String
    let coordinates: [MatcherCoordinate]
    let successorEdgeIDs: [String]

    init(_ edge: RouteMatcherDirectedEdge) {
      id = edge.id
      coordinates = edge.coordinates
      successorEdgeIDs = edge.successorEdgeIDs.sorted()
    }

    private enum CodingKeys: String, CodingKey {
      case id
      case coordinates
      case successorEdgeIDs = "successor_edge_ids"
    }
  }

  private struct CanonicalMatcherCorridor: Encodable {
    let id: String
    let networkSnapshotID: String
    let routePlanID: String
    let edges: [CanonicalMatcherEdge]
    let occurrences: [RouteMatcherOccurrence]

    init(_ corridor: RouteMatcherCorridor) {
      id = corridor.id
      networkSnapshotID = corridor.networkSnapshotID
      routePlanID = corridor.routePlanID
      edges = corridor.edges.map(CanonicalMatcherEdge.init)
      occurrences = corridor.occurrences
    }

    private enum CodingKeys: String, CodingKey {
      case id = "corridor_id"
      case networkSnapshotID = "network_snapshot_id"
      case routePlanID = "route_plan_id"
      case edges
      case occurrences
    }
  }

  private struct RouteRuntimeHashPayload: Encodable {
    let schemaVersion: String
    let networkArtifactID: String
    let networkArtifactSHA256: String
    let routePlan: RoutePlan
    let matcherCorridor: CanonicalMatcherCorridor
    let decisionZones: [DecisionZoneProgressDefinition]
    let releasedGuidance: [ReleasedGuidanceDefinition]
    let recoveryCandidates: [RecoveryCandidate]
    let liveReleaseCoverage: ShutoRouteLiveReleaseCoverage
    let routeEdgeIDs: [String]
    let routeEdgeLengthsMeters: [Double]

    private enum CodingKeys: String, CodingKey {
      case schemaVersion = "schema_version"
      case networkArtifactID = "network_artifact_id"
      case networkArtifactSHA256 = "network_artifact_sha256"
      case routePlan = "route_plan"
      case matcherCorridor = "matcher_corridor"
      case decisionZones = "decision_zones"
      case releasedGuidance = "released_guidance"
      case recoveryCandidates = "recovery_candidates"
      case liveReleaseCoverage = "live_release_coverage"
      case routeEdgeIDs = "route_edge_ids"
      case routeEdgeLengthsMeters = "route_edge_lengths_meters"
    }
  }

  public static func compile(
    database: ShutoNetworkDatabase,
    route: ShutoPlannedRoute
  ) throws -> ShutoPlannedRouteRuntimeAssets {
    try database.validate()
    guard route.routePlan.networkSnapshotID == database.networkSnapshotID else {
      throw ShutoPlannedRouteRuntimeCompilationError
        .networkSnapshotMismatch
    }
    let nodesByID = Dictionary(
      uniqueKeysWithValues: database.nodes.map { ($0.nodeID, $0) }
    )
    let edgesByID = Dictionary(
      uniqueKeysWithValues: database.edges.map { ($0.edgeID, $0) }
    )
    let facilitiesByID = Dictionary(
      uniqueKeysWithValues: database.directionalFacilities.map {
        ($0.facilityID, $0)
      }
    )
    guard
      route.routePlan.entryFacilityID == route.entryFacility.facilityID,
      route.routePlan.exitFacilityID == route.exitFacility.facilityID,
      facilitiesByID[route.entryFacility.facilityID] == route.entryFacility,
      facilitiesByID[route.exitFacility.facilityID] == route.exitFacility,
      route.entryFacility.canEnter,
      route.exitFacility.canExit
    else {
      throw ShutoPlannedRouteRuntimeCompilationError
        .facilityBindingMismatch
    }
    let reviewedMovementByIndex = Dictionary(
      uniqueKeysWithValues: route.edges.indices.dropFirst().compactMap {
        index -> (Int, ShutoJunctionMovementDefinition)? in
        guard
          let definition =
            ShutoJunctionMovementCatalog.releasedDefinition(
              database: database,
              incoming: route.edges[index - 1],
              outgoing: route.edges[index]
            )
        else {
          return nil
        }
        return (index, definition)
      }
    )
    guard
      route.edges.count == route.routePlan.occurrences.count,
      !route.edges.isEmpty,
      zip(route.routePlan.occurrences, route.edges).enumerated()
        .allSatisfy({
          offset, binding in
          let (occurrence, edge) = binding
          guard occurrence.index == offset else { return false }
          if let reviewedMovement = reviewedMovementByIndex[offset] {
            return occurrence.kind == .junctionMovement
              && occurrence.entityID == reviewedMovement.id
          }
          return occurrence.entityID == edge.edgeID
            && occurrence.kind
              == (edge.kind == "LINK" ? .junctionMovement : .edge)
        })
    else {
      throw ShutoPlannedRouteRuntimeCompilationError
        .invalidRoutePlanBinding
    }
    guard
      route.edges.allSatisfy({ edgesByID[$0.edgeID] == $0 }),
      route.entryFacility.entryEdgeCandidates.contains(where: {
        $0.edgeID == route.edges.first?.edgeID
      }),
      route.exitFacility.exitEdgeCandidates.contains(where: {
        $0.edgeID == route.edges.last?.edgeID
      })
    else {
      throw ShutoPlannedRouteRuntimeCompilationError
        .networkEdgeBindingMismatch
    }
    guard
      zip(route.edges, route.edges.dropFirst()).allSatisfy({
        $0.toNodeID == $1.fromNodeID
      })
    else {
      throw ShutoPlannedRouteRuntimeCompilationError
        .discontinuousRouteEdgeOrder
    }

    guard
      let firstNode = route.edges.first.flatMap({
        nodesByID[$0.fromNodeID]
      })
    else {
      throw ShutoPlannedRouteRuntimeCompilationError
        .routeGeometryMismatch
    }
    let expectedCoordinates =
      [firstNode.coordinate]
      + route.edges.compactMap { nodesByID[$0.toNodeID]?.coordinate }
    let expectedDistance = route.edges.reduce(0) {
      $0 + $1.lengthMeters
    }
    var expectedRouteIDs: [String] = []
    for edge in route.edges {
      let candidates = edge.routeMemberships.map(\.routeID)
      let next =
        candidates.first(where: { $0 == expectedRouteIDs.last })
        ?? candidates.first
      if let next, next != expectedRouteIDs.last {
        expectedRouteIDs.append(next)
      }
    }
    guard
      expectedCoordinates.count == route.edges.count + 1,
      route.coordinates == expectedCoordinates,
      abs(route.distanceMeters - expectedDistance) < 0.001,
      route.routeIDsInOrder == expectedRouteIDs,
      route.routePlan.actualDistanceKM.map({
        abs($0 - expectedDistance / 1_000) < 0.000_001
      }) ?? true
    else {
      throw ShutoPlannedRouteRuntimeCompilationError
        .routeGeometryMismatch
    }

    let routeNodeIDs = Set(
      route.edges.flatMap { [$0.fromNodeID, $0.toNodeID] }
    )
    let corridorDatabaseEdges = database.edges.filter {
      routeNodeIDs.contains($0.fromNodeID)
        || routeNodeIDs.contains($0.toNodeID)
    }
    let corridorEdgeIDs = Set(corridorDatabaseEdges.map(\.edgeID))
    let outgoingEdges = Dictionary(
      grouping: corridorDatabaseEdges,
      by: \.fromNodeID
    )

    func matcherEdge(
      _ edge: ShutoNetworkDatabase.Edge
    ) throws -> RouteMatcherDirectedEdge {
      guard let from = nodesByID[edge.fromNodeID] else {
        throw
          ShutoPlannedRouteRuntimeCompilationError
          .missingNode(edge.fromNodeID)
      }
      guard let to = nodesByID[edge.toNodeID] else {
        throw
          ShutoPlannedRouteRuntimeCompilationError
          .missingNode(edge.toNodeID)
      }
      return RouteMatcherDirectedEdge(
        id: edge.edgeID,
        coordinates: [
          MatcherCoordinate(
            latitude: from.latitude,
            longitude: from.longitude
          ),
          MatcherCoordinate(
            latitude: to.latitude,
            longitude: to.longitude
          ),
        ],
        successorEdgeIDs: Set(
          outgoingEdges[edge.toNodeID, default: []]
            .map(\.edgeID)
            .filter(corridorEdgeIDs.contains)
        )
      )
    }

    let corridorEdges = try corridorDatabaseEdges.map(matcherEdge)
    let corridor = RouteMatcherCorridor(
      id: "\(route.routePlan.id).matcher-corridor.v1",
      networkSnapshotID: database.networkSnapshotID,
      routePlanID: route.routePlan.id,
      edges: corridorEdges,
      occurrences: zip(route.routePlan.occurrences, route.edges).map {
        occurrence, edge in
        RouteMatcherOccurrence(
          id: occurrence.id,
          index: occurrence.index,
          directedEdgeID: edge.edgeID
        )
      }
    )
    let guidanceMatches = ShutoJunctionGuidanceCompiler.compile(
      database: database,
      route: route
    )
    let decisionZones = guidanceMatches.map { match in
      DecisionZoneProgressDefinition(
        id:
          "\(match.definition.id)."
          + "\(match.outgoingOccurrenceID).decision-zone",
        networkSnapshotID: database.networkSnapshotID,
        routePlanID: route.routePlan.id,
        movementOccurrenceID: match.outgoingOccurrenceID,
        entryOffsetMeters: 0
      )
    }
    let zonesByMovementOccurrenceID = Dictionary(
      uniqueKeysWithValues: decisionZones.map {
        ($0.movementOccurrenceID, $0)
      }
    )
    let releasedGuidance = guidanceMatches.compactMap {
      match -> ReleasedGuidanceDefinition? in
      guard
        let decisionZone =
          zonesByMovementOccurrenceID[match.outgoingOccurrenceID]
      else {
        return nil
      }
      let definition = match.definition
      let maneuver: GuidanceManeuver
      switch definition.branchSide {
      case .left:
        maneuver = .branchLeft
      case .right:
        maneuver = .branchRight
      case .straight:
        maneuver = .stayMainline
      }
      return ReleasedGuidanceDefinition(
        anchor: GuidanceAnchorDefinition(
          occurrenceID: match.incomingOccurrenceID,
          anchorID: "COMMIT",
          promptID:
            "\(definition.id)."
            + "\(match.outgoingOccurrenceID).commit"
        ),
        triggerDistanceMeters:
          definition.commitTriggerDistanceMeters,
        frameTemplate: GuidanceFrameTemplate(
          movementOccurrenceID: match.outgoingOccurrenceID,
          decisionZoneID: decisionZone.id,
          stage: .commit,
          decisionPointNameJapanese: match.junctionNameJA,
          localizedDecisionPointNames:
            definition.localizedJunctionNames,
          maneuver: maneuver,
          lanePreparation: .none,
          presentationSource: GuidancePresentationSource(
            routeShields: definition.routeShields,
            japaneseSignText: definition.japaneseSignText,
            localizedContent: definition.localizedContent
          )
        )
      )
    }
    let issues = NavigationRuntimeConfigurationValidator.issues(
      routePlan: route.routePlan,
      matcherCorridor: corridor,
      decisionZones: decisionZones,
      releasedGuidance: releasedGuidance
    )
    guard issues.isEmpty else {
      throw
        ShutoPlannedRouteRuntimeCompilationError
        .invalidMatcherCorridor(issues)
    }

    let corridorByID = Dictionary(
      uniqueKeysWithValues: corridorEdges.map { ($0.id, $0) }
    )
    let routeMatcherEdges = try route.edges.map { edge in
      guard let matcherEdge = corridorByID[edge.edgeID] else {
        throw ShutoPlannedRouteRuntimeCompilationError
          .invalidRoutePlanBinding
      }
      return matcherEdge
    }
    let recoveryCandidates = deriveRecoveryCandidates(
      database: database,
      route: route
    )
    let liveReleaseCoverage = liveReleaseCoverage(
      database: database,
      route: route,
      recoveryCandidates: recoveryCandidates
    )
    let networkArtifactID = database.databaseID
    let networkArtifactSHA256 = try canonicalSHA256(
      NetworkArtifactHashPayload(
        schemaVersion: ShutoRuntimeAssetIdentity.currentSchemaVersion,
        database: database
      )
    )
    let routeRuntimeSHA256 = try canonicalSHA256(
      RouteRuntimeHashPayload(
        schemaVersion: ShutoRuntimeAssetIdentity.currentSchemaVersion,
        networkArtifactID: networkArtifactID,
        networkArtifactSHA256: networkArtifactSHA256,
        routePlan: route.routePlan,
        matcherCorridor: CanonicalMatcherCorridor(corridor),
        decisionZones: decisionZones,
        releasedGuidance: releasedGuidance,
        recoveryCandidates: recoveryCandidates,
        liveReleaseCoverage: liveReleaseCoverage,
        routeEdgeIDs: route.edges.map(\.edgeID),
        routeEdgeLengthsMeters: route.edges.map(\.lengthMeters)
      )
    )
    let runtimeAssetIdentity = ShutoRuntimeAssetIdentity(
      networkArtifactID: networkArtifactID,
      networkArtifactSHA256: networkArtifactSHA256,
      routeRuntimeID: route.routePlan.id,
      routeRuntimeSHA256: routeRuntimeSHA256,
      networkSnapshotID: database.networkSnapshotID,
      routePlanID: route.routePlan.id,
      verificationState: database.verificationState
    )
    return ShutoPlannedRouteRuntimeAssets(
      runtimeAssetIdentity: runtimeAssetIdentity,
      routePlan: route.routePlan,
      matcherCorridor: corridor,
      decisionZones: decisionZones,
      releasedGuidance: releasedGuidance,
      recoveryCandidates: recoveryCandidates,
      liveReleaseCoverage: liveReleaseCoverage,
      routeEdges: routeMatcherEdges,
      routeEdgeLengthsMeters: route.edges.map(\.lengthMeters)
    )
  }

  private static func canonicalSHA256<Value: Encodable>(
    _ value: Value
  ) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data: Data
    do {
      data = try encoder.encode(value)
    } catch {
      throw ShutoPlannedRouteRuntimeCompilationError
        .assetIdentityEncodingFailed
    }
    return SHA256.hash(data: data).map {
      String(format: "%02x", $0)
    }.joined()
  }

  public static func liveReleaseCoverage(
    database: ShutoNetworkDatabase,
    route: ShutoPlannedRoute
  ) -> ShutoRouteLiveReleaseCoverage {
    liveReleaseCoverage(
      database: database,
      route: route,
      recoveryCandidates: deriveRecoveryCandidates(
        database: database,
        route: route
      )
    )
  }

  public static func networkLiveReleaseCoverage(
    database: ShutoNetworkDatabase
  ) throws -> ShutoNetworkLiveReleaseCoverage {
    try database.validate()
    let incoming = Dictionary(grouping: database.edges, by: \.toNodeID)
    let outgoing = Dictionary(grouping: database.edges, by: \.fromNodeID)
    let availableRouteIDs = Set(
      database.routes.filter { $0.operationalStatus == "AVAILABLE" }
        .map(\.routeID)
    )
    let waysByID = Dictionary(
      uniqueKeysWithValues: database.ways.map { ($0.wayID, $0) }
    )
    var movements: [ShutoNetworkJunctionMovementCoverage] = []

    for junction in database.junctions.sorted(by: {
      $0.junctionID < $1.junctionID
    }) {
      for nodeID in junction.osmNodeIDs.sorted() {
        for incomingEdge in (incoming[nodeID] ?? []).sorted(by: {
          $0.edgeID < $1.edgeID
        }) {
          let choices = (outgoing[nodeID] ?? [])
            .filter { $0.toNodeID != incomingEdge.fromNodeID }
            .filter {
              leadsToAvailableMainline(
                from: $0,
                outgoing: outgoing,
                availableRouteIDs: availableRouteIDs
              )
            }
            .sorted { $0.edgeID < $1.edgeID }
          guard choices.count > 1 else { continue }
          for outgoingEdge in choices {
            let definition =
              ShutoJunctionMovementCatalog.releasedDefinition(
                database: database,
                incoming: incomingEdge,
                outgoing: outgoingEdge
              )
            movements.append(
              ShutoNetworkJunctionMovementCoverage(
                junctionID: junction.junctionID,
                junctionNameJapanese: junction.nameJA,
                junctionNodeID: nodeID,
                incomingDirectedEdgeID: incomingEdge.edgeID,
                incomingRouteMemberships: incomingEdge.routeMemberships,
                incomingWayTags: waysByID[incomingEdge.wayID]?.tags ?? [:],
                outgoingDirectedEdgeID: outgoingEdge.edgeID,
                outgoingRouteMemberships: outgoingEdge.routeMemberships,
                outgoingWayTags: waysByID[outgoingEdge.wayID]?.tags ?? [:],
                releasedGuidanceDefinitionID: definition?.id,
                officialDetailReference: junction.officialDetailReference,
                officialDetailSHA256: junction.officialDetailSHA256
              )
            )
          }
        }
      }
    }
    return ShutoNetworkLiveReleaseCoverage(
      networkSnapshotID: database.networkSnapshotID,
      movements: movements
    )
  }

  private static func liveReleaseCoverage(
    database: ShutoNetworkDatabase,
    route: ShutoPlannedRoute,
    recoveryCandidates: [RecoveryCandidate]
  ) -> ShutoRouteLiveReleaseCoverage {
    let outgoing = Dictionary(grouping: database.edges, by: \.fromNodeID)
    let availableRouteIDs = Set(
      database.routes.filter { $0.operationalStatus == "AVAILABLE" }
        .map(\.routeID)
    )
    let candidatesByBranch = Dictionary(
      uniqueKeysWithValues: recoveryCandidates.map {
        ("\($0.divergenceOccurrenceID)|\($0.triggerDirectedEdgeID)", $0)
      }
    )
    var decisions: [ShutoRouteDecisionCoverage] = []
    var recoveryBranches: [ShutoRouteRecoveryBranchCoverage] = []
    guard route.edges.count == route.routePlan.occurrences.count,
      route.edges.count > 1
    else {
      return ShutoRouteLiveReleaseCoverage(
        networkSnapshotID: database.networkSnapshotID,
        routePlanID: route.routePlan.id,
        decisions: [],
        recoveryBranches: []
      )
    }

    for index in 0..<(route.edges.count - 1) {
      let incoming = route.edges[index]
      let plannedOutgoing = route.edges[index + 1]
      let alternatives = (outgoing[incoming.toNodeID] ?? [])
        .filter { $0.edgeID != plannedOutgoing.edgeID }
        .sorted { $0.edgeID < $1.edgeID }
      guard !alternatives.isEmpty else { continue }
      let divergenceOccurrenceID = route.routePlan.occurrences[index].id
      let immediateDefinition = ShutoJunctionMovementCatalog.releasedDefinition(
        database: database,
        incoming: incoming,
        outgoing: plannedOutgoing
      )
      let startsTerminalExitBranch = route.edges[(index + 1)...]
        .allSatisfy { $0.kind == "LINK" }
      let hasAvailableExpresswayAlternative = alternatives.contains {
        leadsToAvailableMainline(
          from: $0,
          outgoing: outgoing,
          availableRouteIDs: availableRouteIDs
        )
      }
      let plannedContinuesOnAvailableExpressway = leadsToAvailableMainline(
        from: plannedOutgoing,
        outgoing: outgoing,
        availableRouteIDs: availableRouteIDs
      )
      let isJunctionDecision = !startsTerminalExitBranch
        && plannedContinuesOnAvailableExpressway
        && hasAvailableExpresswayAlternative
      let definition = immediateDefinition
        ?? (isJunctionDecision
          ? ShutoJunctionMovementCatalog
            .releasedDefinitionCoveringFollowingDecision(
              database: database,
              routeEdges: route.edges,
              decisionIndex: index
            )
          : nil)
      decisions.append(
        ShutoRouteDecisionCoverage(
          kind: isJunctionDecision ? .junction : .graphDivergence,
          divergenceOccurrenceID: divergenceOccurrenceID,
          plannedOutgoingOccurrenceID:
            route.routePlan.occurrences[index + 1].id,
          junctionNodeID: incoming.toNodeID,
          incomingDirectedEdgeID: incoming.edgeID,
          plannedOutgoingDirectedEdgeID: plannedOutgoing.edgeID,
          alternativeOutgoingDirectedEdgeIDs: alternatives.map(\.edgeID),
          releasedGuidanceDefinitionID: definition?.id
        )
      )
      for alternative in alternatives {
        let candidate = candidatesByBranch[
          "\(divergenceOccurrenceID)|\(alternative.edgeID)"
        ]
        recoveryBranches.append(
          ShutoRouteRecoveryBranchCoverage(
            kind: recoveryBranchKind(
              isJunctionDecision: isJunctionDecision,
              startsTerminalExitBranch: startsTerminalExitBranch,
              alternative: alternative,
              outgoing: outgoing,
              availableRouteIDs: availableRouteIDs
            ),
            divergenceOccurrenceID: divergenceOccurrenceID,
            triggerDirectedEdgeID: alternative.edgeID,
            candidateTargetOccurrenceID: candidate?.targetOccurrenceID,
            candidateIsReleased: candidate?.isReleased == true
          )
        )
      }
    }
    return ShutoRouteLiveReleaseCoverage(
      networkSnapshotID: database.networkSnapshotID,
      routePlanID: route.routePlan.id,
      decisions: decisions,
      recoveryBranches: recoveryBranches
    )
  }

  /// Distinguishes an expressway-to-expressway connector from an off-ramp.
  /// The first mainline reached owns the result: an unavailable route such as
  /// the closed Yaesu Route is not followed through to a later open route.
  private static func leadsToAvailableMainline(
    from start: ShutoNetworkDatabase.Edge,
    outgoing: [Int64: [ShutoNetworkDatabase.Edge]],
    availableRouteIDs: Set<String>
  ) -> Bool {
    firstMainlineAvailability(
      from: start,
      outgoing: outgoing,
      availableRouteIDs: availableRouteIDs
    ) == .available
  }

  private enum FirstMainlineAvailability {
    case available
    case unavailable
    case none
  }

  private static func recoveryBranchKind(
    isJunctionDecision: Bool,
    startsTerminalExitBranch: Bool,
    alternative: ShutoNetworkDatabase.Edge,
    outgoing: [Int64: [ShutoNetworkDatabase.Edge]],
    availableRouteIDs: Set<String>
  ) -> ShutoRouteRecoveryBranchCoverage.Kind {
    switch firstMainlineAvailability(
      from: alternative,
      outgoing: outgoing,
      availableRouteIDs: availableRouteIDs
    ) {
    case .available where startsTerminalExitBranch:
      return .missedExit
    case .available where isJunctionDecision:
      return .expresswayBranch
    case .available:
      return .expresswayBranch
    case .unavailable:
      return .unavailableExpresswayBranch
    case .none:
      return .surfaceExit
    }
  }

  private static func firstMainlineAvailability(
    from start: ShutoNetworkDatabase.Edge,
    outgoing: [Int64: [ShutoNetworkDatabase.Edge]],
    availableRouteIDs: Set<String>
  ) -> FirstMainlineAvailability {
    var queue: [(edge: ShutoNetworkDatabase.Edge, distance: Double)] = [
      (start, 0)
    ]
    var seen = Set([start.edgeID])
    var index = 0
    while index < queue.count {
      let current = queue[index]
      index += 1
      if current.edge.kind == "MAINLINE" {
        return current.edge.routeMemberships.contains {
          availableRouteIDs.contains($0.routeID)
        } ? .available : .unavailable
      }
      let distance = current.distance + current.edge.lengthMeters
      guard distance <= 2_000 else { continue }
      for next in outgoing[current.edge.toNodeID] ?? []
      where seen.insert(next.edgeID).inserted {
        queue.append((next, distance))
      }
    }
    return .none
  }

  /// Wrong-turn recovery candidates: for every plan node where an available
  /// graph movement diverges from the plan, a bounded directed search finds a
  /// candidate path back onto a strictly later plan occurrence. The rejoin
  /// objective always stays the active RoutePlan — loops make this natural
  /// because the ring comes back around.
  ///
  /// The whole-Shuto graph is a planning candidate, not a navigation release.
  /// These paths therefore remain unreleased and cannot be executed by
  /// `RecoveryPlanner`. A future `KaidoProductRelease` must separately bind
  /// reviewed recovery movements before a runtime can admit them.
  static func deriveRecoveryCandidates(
    database: ShutoNetworkDatabase,
    route: ShutoPlannedRoute
  ) -> [RecoveryCandidate] {
    let occurrences = route.routePlan.occurrences
    let edges = route.edges
    guard occurrences.count == edges.count, edges.count > 1 else {
      return []
    }
    let maximumRecoveryMeters = 30_000.0

    var outgoing: [Int64: [ShutoNetworkDatabase.Edge]] = [:]
    for edge in database.edges {
      outgoing[edge.fromNodeID, default: []].append(edge)
    }
    for node in outgoing.keys {
      outgoing[node]?.sort { $0.edgeID < $1.edgeID }
    }
    // Plan occurrence indices that begin at a node, in plan order.
    var planIndicesByNode: [Int64: [Int]] = [:]
    for (index, edge) in edges.enumerated() {
      planIndicesByNode[edge.fromNodeID, default: []].append(index)
    }
    func rejoinIndex(at node: Int64, after divergence: Int) -> Int? {
      planIndicesByNode[node]?.first { $0 > divergence }
    }

    var candidates: [RecoveryCandidate] = []
    for index in 0..<(edges.count - 1) {
      let divergenceNode = edges[index].toNodeID
      let plannedNextEdgeID = edges[index + 1].edgeID
      let alternatives = (outgoing[divergenceNode] ?? [])
        .filter { $0.edgeID != plannedNextEdgeID }
      guard !alternatives.isEmpty else { continue }

      for alternative in alternatives {
        // Each search is rooted in one observed wrong-turn edge. Keeping
        // candidates separate prevents another branch at the same junction
        // from borrowing an unrelated rejoin path.
        var distances: [Int64: Double] = [:]
        var previousEdge: [Int64: ShutoNetworkDatabase.Edge] = [:]
        var frontier: [(cost: Double, node: Int64)] = []
        func push(_ cost: Double, _ node: Int64) {
          frontier.append((cost, node))
          var child = frontier.count - 1
          while child > 0 {
            let parent = (child - 1) / 2
            guard frontier[child].cost < frontier[parent].cost else { break }
            frontier.swapAt(child, parent)
            child = parent
          }
        }
        func pop() -> (cost: Double, node: Int64)? {
          guard let top = frontier.first else { return nil }
          frontier[0] = frontier[frontier.count - 1]
          frontier.removeLast()
          var parent = 0
          while true {
            let left = parent * 2 + 1
            let right = left + 1
            var smallest = parent
            if left < frontier.count,
              frontier[left].cost < frontier[smallest].cost
            {
              smallest = left
            }
            if right < frontier.count,
              frontier[right].cost < frontier[smallest].cost
            {
              smallest = right
            }
            if smallest == parent { break }
            frontier.swapAt(parent, smallest)
            parent = smallest
          }
          return top
        }

        let cost = alternative.lengthMeters
        guard cost <= maximumRecoveryMeters else { continue }
        distances[alternative.toNodeID] = cost
        previousEdge[alternative.toNodeID] = alternative
        push(cost, alternative.toNodeID)

        var settled: Set<Int64> = []
        var rejoin: (node: Int64, target: Int)?
        while let current = pop() {
          if settled.contains(current.node) { continue }
          settled.insert(current.node)
          if let target = rejoinIndex(at: current.node, after: index) {
            rejoin = (current.node, target)
            break
          }
          for edge in outgoing[current.node] ?? [] {
            let nextCost = current.cost + edge.lengthMeters
            guard nextCost <= maximumRecoveryMeters,
              nextCost < distances[edge.toNodeID] ?? .infinity
            else { continue }
            distances[edge.toNodeID] = nextCost
            previousEdge[edge.toNodeID] = edge
            push(nextCost, edge.toNodeID)
          }
        }
        guard let rejoin else { continue }

        var pathEdgeIDs: [String] = []
        var cursor = rejoin.node
        while let edge = previousEdge[cursor] {
          pathEdgeIDs.append(edge.edgeID)
          cursor = edge.fromNodeID
          if cursor == divergenceNode { break }
        }
        candidates.append(
          RecoveryCandidate(
            divergenceOccurrenceID: occurrences[index].id,
            triggerDirectedEdgeID: alternative.edgeID,
            targetOccurrenceID: occurrences[rejoin.target].id,
            recoveryOccurrenceIDs: pathEdgeIDs.reversed(),
            isReleased: false,
            staysInAllowedTollDomain: true
          )
        )
      }
    }
    return candidates
  }
}
