import Foundation
import KaidoNavigation

enum InternalLocationCalibrationFixtureError: Error, Equatable {
  case missingResource(String)
  case invalidCandidate([String])
}

/// Exact, review-only graph input for the internal device-calibration harness.
///
/// The fixture deliberately consumes the tracked ODbL candidate database. It can
/// drive matcher measurement, but `navigationAuthority` must remain false and it
/// cannot be passed to the released navigation composition.
struct InternalLocationCalibrationFixture: Sendable {
  static let databaseResourceName = "k7-northwest-260721-directed-database"
  static let candidateResourceName =
    "k7-northwest-up-aoba-to-kohoku-osm-directed-candidate"

  let corridor: RouteMatcherCorridor
  let initialOccurrenceID: String
  let entryFacilityID: String
  let exitFacilityID: String
  let evidenceState: String
  let attribution: String
  let attributionURL: URL
  let licence: String
  let licenceURL: URL
  let navigationAuthority: Bool

  static func bundled(in bundle: Bundle = .main) throws
    -> InternalLocationCalibrationFixture
  {
    guard
      let databaseURL = bundle.url(
        forResource: databaseResourceName,
        withExtension: "json"
      )
    else {
      throw InternalLocationCalibrationFixtureError.missingResource(
        "\(databaseResourceName).json"
      )
    }
    guard
      let candidateURL = bundle.url(
        forResource: candidateResourceName,
        withExtension: "json"
      )
    else {
      throw InternalLocationCalibrationFixtureError.missingResource(
        "\(candidateResourceName).json"
      )
    }
    return try decode(
      databaseData: Data(contentsOf: databaseURL),
      candidateData: Data(contentsOf: candidateURL)
    )
  }

  static func decode(databaseData: Data, candidateData: Data) throws
    -> InternalLocationCalibrationFixture
  {
    let decoder = JSONDecoder()
    let database = try decoder.decode(DirectedDatabase.self, from: databaseData)
    let candidate = try decoder.decode(RouteAtlasCandidate.self, from: candidateData)
    var issues: [String] = []

    if database.schemaVersion != "1.0" {
      issues.append("unsupported directed database schema")
    }
    if database.databaseID.isEmpty {
      issues.append("candidate database id is empty")
    }
    if candidate.schemaVersion != "1.0" {
      issues.append("unsupported candidate schema")
    }
    if database.navigationAuthority {
      issues.append("candidate database unexpectedly has navigation authority")
    }
    if database.licence != "ODbL-1.0" {
      issues.append("candidate database licence is not ODbL-1.0")
    }
    if database.licenceURL.absoluteString
      != "https://opendatacommons.org/licenses/odbl/1-0/"
    {
      issues.append("candidate database licence URL has drifted")
    }
    if database.attribution != "© OpenStreetMap contributors" {
      issues.append("candidate database attribution has drifted")
    }
    if database.attributionURL.absoluteString
      != "https://www.openstreetmap.org/copyright"
    {
      issues.append("candidate database attribution URL has drifted")
    }
    if candidate.definition.evidence.state != "CANDIDATE" {
      issues.append("route atlas evidence is not CANDIDATE")
    }
    if candidate.networkSnapshot.status != "ACTIVE" {
      issues.append("candidate network snapshot is not active")
    }
    if candidate.definition.networkSnapshotID != candidate.networkSnapshot.id
      || candidate.definition.networkSnapshotID
        != candidate.routePlan.networkSnapshotID
    {
      issues.append("candidate network snapshot identity drift")
    }
    if candidate.definition.routePlanID != candidate.routePlan.planID {
      issues.append("candidate route plan identity drift")
    }
    if candidate.networkSnapshot.effectiveAt != database.source.sourceSnapshotAt {
      issues.append("candidate and database source timestamps drift")
    }
    if candidate.routePlan.entryFacilityID != database.route.entryFacilityID
      || candidate.routePlan.exitFacilityID != database.route.exitFacilityID
    {
      issues.append("candidate and database directional facilities drift")
    }

    let nodesByID = Dictionary(
      database.nodes.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    if nodesByID.count != database.nodes.count {
      issues.append("candidate database node ids are not unique")
    }
    let waysByID = Dictionary(
      database.ways.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    if waysByID.count != database.ways.count {
      issues.append("candidate database way ids are not unique")
    }

    let routeWayIDs = database.route.wayIDs
    let alternativeWayIDs = database.divergenceAlternatives.map(\.wayID)
    if Set(routeWayIDs).count != routeWayIDs.count {
      issues.append("candidate route way ids are not unique")
    }
    if Set(alternativeWayIDs).count != alternativeWayIDs.count {
      issues.append("candidate alternative way ids are not unique")
    }
    if !Set(routeWayIDs).isDisjoint(with: alternativeWayIDs) {
      issues.append("candidate route and alternative ways overlap")
    }
    if Set(routeWayIDs + alternativeWayIDs) != Set(database.ways.map(\.id)) {
      issues.append("candidate database corridor way coverage is not exact")
    }
    if routeWayIDs.isEmpty {
      issues.append("candidate route has no ways")
    }
    if candidate.routePlan.occurrences.map(\.index)
      != Array(0..<candidate.routePlan.occurrences.count)
    {
      issues.append("candidate occurrence indexes are not contiguous")
    }
    if candidate.routePlan.occurrences.count != routeWayIDs.count {
      issues.append("candidate occurrence and route-way counts drift")
    }

    var edges: [RouteMatcherDirectedEdge] = []
    for way in database.ways {
      if way.nodeIDs.count < 2 {
        issues.append("way \(way.id) has fewer than two nodes")
      }
      if way.tags["oneway"] != "yes" {
        issues.append("way \(way.id) is not explicitly one-way")
      }
      let coordinates = way.nodeIDs.compactMap { nodeID -> MatcherCoordinate? in
        guard let node = nodesByID[nodeID] else {
          issues.append("way \(way.id) references missing node \(nodeID)")
          return nil
        }
        return MatcherCoordinate(latitude: node.latitude, longitude: node.longitude)
      }
      var successorWayIDs: [Int64] = []
      if let routeIndex = routeWayIDs.firstIndex(of: way.id),
        routeIndex + 1 < routeWayIDs.count
      {
        successorWayIDs.append(routeWayIDs[routeIndex + 1])
      }
      successorWayIDs.append(
        contentsOf: database.divergenceAlternatives.compactMap {
          $0.afterWayID == way.id ? $0.wayID : nil
        }
      )
      edges.append(
        RouteMatcherDirectedEdge(
          id: edgeID(for: way.id),
          coordinates: coordinates,
          successorEdgeIDs: Set(successorWayIDs.map { edgeID(for: $0) })
        )
      )
    }

    for (index, wayID) in routeWayIDs.enumerated() {
      guard let way = waysByID[wayID] else {
        issues.append("route references missing way \(wayID)")
        continue
      }
      if index == 0, way.nodeIDs.first != database.route.entryNodeID {
        issues.append("route does not start at the exact entrance node")
      }
      if index == routeWayIDs.count - 1,
        way.nodeIDs.last != database.route.exitNodeID
      {
        issues.append("route does not end at the exact exit node")
      }
      if index + 1 < routeWayIDs.count,
        let nextWay = waysByID[routeWayIDs[index + 1]],
        way.nodeIDs.last != nextWay.nodeIDs.first
      {
        issues.append("route ways \(wayID) and \(nextWay.id) are disconnected")
      }
      guard index < candidate.routePlan.occurrences.count else { continue }
      let occurrence = candidate.routePlan.occurrences[index]
      if occurrence.kind != "EDGE"
        || occurrence.entityID != edgeID(for: wayID)
      {
        issues.append("candidate occurrence \(index) does not bind route way \(wayID)")
      }
    }

    for alternative in database.divergenceAlternatives {
      if !routeWayIDs.contains(alternative.afterWayID) {
        issues.append("candidate divergence does not leave a route way")
      }
      guard let after = waysByID[alternative.afterWayID],
        let branch = waysByID[alternative.wayID]
      else {
        issues.append("candidate divergence references a missing way")
        continue
      }
      if after.nodeIDs.last != branch.nodeIDs.first {
        issues.append("candidate divergence \(alternative.wayID) is disconnected")
      }
    }

    let occurrences = candidate.routePlan.occurrences.map {
      RouteMatcherOccurrence(
        id: $0.occurrenceID,
        index: $0.index,
        directedEdgeID: $0.entityID
      )
    }
    let corridor = RouteMatcherCorridor(
      id: "internal-calibration.\(database.databaseID)",
      networkSnapshotID: candidate.definition.networkSnapshotID,
      routePlanID: candidate.routePlan.planID,
      edges: edges,
      occurrences: occurrences
    )
    issues.append(contentsOf: corridor.validationIssues)

    let uniqueIssues = Array(Set(issues)).sorted()
    guard uniqueIssues.isEmpty, let initialOccurrenceID = occurrences.first?.id else {
      throw InternalLocationCalibrationFixtureError.invalidCandidate(uniqueIssues)
    }
    return InternalLocationCalibrationFixture(
      corridor: corridor,
      initialOccurrenceID: initialOccurrenceID,
      entryFacilityID: database.route.entryFacilityID,
      exitFacilityID: database.route.exitFacilityID,
      evidenceState: candidate.definition.evidence.state,
      attribution: database.attribution,
      attributionURL: database.attributionURL,
      licence: database.licence,
      licenceURL: database.licenceURL,
      navigationAuthority: database.navigationAuthority
    )
  }

  private static func edgeID(for wayID: Int64) -> String {
    "shutoko.edge.osm-way.\(wayID).forward"
  }
}

private struct DirectedDatabase: Decodable {
  let schemaVersion: String
  let databaseID: String
  let source: Source
  let route: Route
  let divergenceAlternatives: [DivergenceAlternative]
  let nodes: [Node]
  let ways: [Way]
  let licence: String
  let licenceURL: URL
  let attribution: String
  let attributionURL: URL
  let navigationAuthority: Bool

  struct Source: Decodable {
    let sourceSnapshotAt: String

    enum CodingKeys: String, CodingKey {
      case sourceSnapshotAt = "source_snapshot_at"
    }
  }

  struct Route: Decodable {
    let entryFacilityID: String
    let entryNodeID: Int64
    let exitFacilityID: String
    let exitNodeID: Int64
    let wayIDs: [Int64]

    enum CodingKeys: String, CodingKey {
      case entryFacilityID = "entry_facility_id"
      case entryNodeID = "entry_node_id"
      case exitFacilityID = "exit_facility_id"
      case exitNodeID = "exit_node_id"
      case wayIDs = "way_ids"
    }
  }

  struct DivergenceAlternative: Decodable {
    let afterWayID: Int64
    let wayID: Int64

    enum CodingKeys: String, CodingKey {
      case afterWayID = "after_way_id"
      case wayID = "way_id"
    }
  }

  struct Node: Decodable {
    let id: Int64
    let latitude: Double
    let longitude: Double

    enum CodingKeys: String, CodingKey {
      case id
      case latitude = "lat"
      case longitude = "lon"
    }
  }

  struct Way: Decodable {
    let id: Int64
    let nodeIDs: [Int64]
    let tags: [String: String]

    enum CodingKeys: String, CodingKey {
      case id
      case nodeIDs = "nodes"
      case tags
    }
  }

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case databaseID = "database_id"
    case source
    case route
    case divergenceAlternatives = "divergence_alternatives"
    case nodes
    case ways
    case licence
    case licenceURL = "licence_url"
    case attribution
    case attributionURL = "attribution_url"
    case navigationAuthority = "navigation_authority"
  }
}

private struct RouteAtlasCandidate: Decodable {
  let schemaVersion: String
  let definition: Definition
  let networkSnapshot: NetworkSnapshot
  let routePlan: RoutePlan

  struct Definition: Decodable {
    let networkSnapshotID: String
    let routePlanID: String
    let evidence: Evidence

    struct Evidence: Decodable {
      let state: String
    }

    enum CodingKeys: String, CodingKey {
      case networkSnapshotID = "network_snapshot_id"
      case routePlanID = "route_plan_id"
      case evidence
    }
  }

  struct NetworkSnapshot: Decodable {
    let id: String
    let effectiveAt: String
    let status: String

    enum CodingKeys: String, CodingKey {
      case id
      case effectiveAt = "effective_at"
      case status
    }
  }

  struct RoutePlan: Decodable {
    let planID: String
    let networkSnapshotID: String
    let entryFacilityID: String
    let exitFacilityID: String
    let occurrences: [Occurrence]

    struct Occurrence: Decodable {
      let occurrenceID: String
      let entityID: String
      let index: Int
      let kind: String

      enum CodingKeys: String, CodingKey {
        case occurrenceID = "occurrence_id"
        case entityID = "entity_id"
        case index
        case kind
      }
    }

    enum CodingKeys: String, CodingKey {
      case planID = "plan_id"
      case networkSnapshotID = "network_snapshot_id"
      case entryFacilityID = "entry_facility_id"
      case exitFacilityID = "exit_facility_id"
      case occurrences
    }
  }

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case definition
    case networkSnapshot = "network_snapshot"
    case routePlan = "route_plan"
  }
}
