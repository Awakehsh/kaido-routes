import Foundation

public enum ShutoJunctionBranchSide:
  String, Codable, Equatable, Sendable
{
  case left = "LEFT"
  case right = "RIGHT"
  case straight = "STRAIGHT"
}

public enum ShutoJunctionLaneGuidanceState:
  String, Codable, Equatable, Sendable
{
  case notReleased = "NOT_RELEASED"
}

public struct ShutoJunctionGuidanceSource:
  Equatable, Sendable
{
  public let url: String
  public let contentSHA256: String?

  public init(url: String, contentSHA256: String? = nil) {
    self.url = url
    self.contentSHA256 = contentSHA256
  }
}

public struct ShutoJunctionMovementDefinition:
  Equatable, Identifiable, Sendable
{
  public let id: String
  public let networkSnapshotID: String
  public let junctionID: String
  public let junctionNodeID: Int64
  public let incomingEdgeID: String
  public let outgoingEdgeID: String
  public let incomingRouteID: String
  public let incomingDirectionJA: String
  public let outgoingRouteID: String
  public let outgoingDirectionJA: String
  public let branchSide: ShutoJunctionBranchSide
  public let japaneseSignText: String
  public let routeShields: [String]
  public let laneGuidanceState: ShutoJunctionLaneGuidanceState
  public let checkedAt: String
  public let expectedJunctionDetailSHA256: String
  public let sources: [ShutoJunctionGuidanceSource]

  public init(
    id: String,
    networkSnapshotID: String,
    junctionID: String,
    junctionNodeID: Int64,
    incomingEdgeID: String,
    outgoingEdgeID: String,
    incomingRouteID: String,
    incomingDirectionJA: String,
    outgoingRouteID: String,
    outgoingDirectionJA: String,
    branchSide: ShutoJunctionBranchSide,
    japaneseSignText: String,
    routeShields: [String],
    laneGuidanceState: ShutoJunctionLaneGuidanceState,
    checkedAt: String,
    expectedJunctionDetailSHA256: String,
    sources: [ShutoJunctionGuidanceSource]
  ) {
    self.id = id
    self.networkSnapshotID = networkSnapshotID
    self.junctionID = junctionID
    self.junctionNodeID = junctionNodeID
    self.incomingEdgeID = incomingEdgeID
    self.outgoingEdgeID = outgoingEdgeID
    self.incomingRouteID = incomingRouteID
    self.incomingDirectionJA = incomingDirectionJA
    self.outgoingRouteID = outgoingRouteID
    self.outgoingDirectionJA = outgoingDirectionJA
    self.branchSide = branchSide
    self.japaneseSignText = japaneseSignText
    self.routeShields = routeShields
    self.laneGuidanceState = laneGuidanceState
    self.checkedAt = checkedAt
    self.expectedJunctionDetailSHA256 =
      expectedJunctionDetailSHA256
    self.sources = sources
  }
}

public enum ShutoJunctionMovementCatalog {
  public static let released: [ShutoJunctionMovementDefinition] = [
    ShutoJunctionMovementDefinition(
      id: "shuto.jct.oi.b-westbound-to-c2-outer",
      networkSnapshotID:
        "shuto-official-2026-07-29-osm-2026-07-28",
      junctionID: "shuto.jct.jct_oi",
      junctionNodeID: 6_534_476_215,
      incomingEdgeID: "osm.266086991.11.forward",
      outgoingEdgeID: "osm.4854098.0.forward",
      incomingRouteID: "B",
      incomingDirectionJA: "西行き",
      outgoingRouteID: "C2",
      outgoingDirectionJA: "外回り",
      branchSide: .left,
      japaneseSignText: "東名・中央道",
      routeShields: ["C2", "3", "E1", "E20"],
      laneGuidanceState: .notReleased,
      checkedAt: "2026-07-29",
      expectedJunctionDetailSHA256:
        "4bfe3cb6117273ec547a62872b971a87f"
        + "cc944fff70b3267022888612aacfc2b",
      sources: [
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/safety/branch/"
        ),
        ShutoJunctionGuidanceSource(
          url:
            "https://www.shutoko.jp/~/media/pdf/responsive/"
            + "customer/use/safety/branch/branch_info_oi_191121.pdf",
          contentSHA256:
            "04de9cbacfea67e3e7e02ef2dad3be6b"
            + "70ccaafb5d5e11e6a414c88ee59c87fa"
        ),
        ShutoJunctionGuidanceSource(
          url:
            "https://www.shutoko.jp/-/media/images/responsive/"
            + "customer/use/network/jct/routeguide/jct_oi",
          contentSHA256:
            "4bfe3cb6117273ec547a62872b971a87f"
            + "cc944fff70b3267022888612aacfc2b"
        ),
      ]
    )
  ]
}

public struct ShutoJunctionGuidanceMatch:
  Equatable, Identifiable, Sendable
{
  public let definition: ShutoJunctionMovementDefinition
  public let junctionNameJA: String
  public let coordinate: ShutoCoordinate
  public let incomingOccurrenceID: String
  public let outgoingOccurrenceID: String
  public let progressFraction: Double

  public var id: String {
    "\(definition.id)|\(outgoingOccurrenceID)"
  }

  public init(
    definition: ShutoJunctionMovementDefinition,
    junctionNameJA: String,
    coordinate: ShutoCoordinate,
    incomingOccurrenceID: String,
    outgoingOccurrenceID: String,
    progressFraction: Double
  ) {
    self.definition = definition
    self.junctionNameJA = junctionNameJA
    self.coordinate = coordinate
    self.incomingOccurrenceID = incomingOccurrenceID
    self.outgoingOccurrenceID = outgoingOccurrenceID
    self.progressFraction = progressFraction
  }
}

public enum ShutoJunctionGuidanceCompiler {
  public static func compile(
    database: ShutoNetworkDatabase,
    route: ShutoPlannedRoute,
    definitions: [ShutoJunctionMovementDefinition] =
      ShutoJunctionMovementCatalog.released
  ) -> [ShutoJunctionGuidanceMatch] {
    let edgeDistance = route.edges.reduce(0) {
      $0 + $1.lengthMeters
    }
    guard
      route.routePlan.networkSnapshotID == database.networkSnapshotID,
      route.edges.count == route.routePlan.occurrences.count,
      route.distanceMeters > 0,
      abs(route.distanceMeters - edgeDistance) < 0.01,
      zip(route.edges, route.routePlan.occurrences).allSatisfy({
        $0.0.edgeID == $0.1.entityID
      })
    else {
      return []
    }

    let nodesByID = Dictionary(
      uniqueKeysWithValues: database.nodes.map { ($0.nodeID, $0) }
    )
    let junctionsByID = Dictionary(
      uniqueKeysWithValues: database.junctions.map {
        ($0.junctionID, $0)
      }
    )
    let totalDistance = max(route.distanceMeters, 1)
    var cumulativeDistance = 0.0
    var matches: [ShutoJunctionGuidanceMatch] = []

    for index in route.edges.indices.dropLast() {
      let incoming = route.edges[index]
      let outgoing = route.edges[index + 1]
      cumulativeDistance += incoming.lengthMeters

      for definition in definitions
      where definition.networkSnapshotID == database.networkSnapshotID
        && definition.incomingEdgeID == incoming.edgeID
        && definition.outgoingEdgeID == outgoing.edgeID
      {
        guard incoming.toNodeID == definition.junctionNodeID,
          outgoing.fromNodeID == definition.junctionNodeID,
          incoming.routeMemberships.contains(where: {
            $0.routeID == definition.incomingRouteID
              && $0.directionsJA.contains(
                definition.incomingDirectionJA
              )
          }),
          outgoing.routeMemberships.contains(where: {
            $0.routeID == definition.outgoingRouteID
          }),
          let junction = junctionsByID[definition.junctionID],
          junction.osmNodeIDs.contains(definition.junctionNodeID),
          junction.officialDetailSHA256
            == definition.expectedJunctionDetailSHA256,
          let node = nodesByID[definition.junctionNodeID]
        else {
          continue
        }
        matches.append(
          ShutoJunctionGuidanceMatch(
            definition: definition,
            junctionNameJA: junction.nameJA,
            coordinate: node.coordinate,
            incomingOccurrenceID:
              route.routePlan.occurrences[index].id,
            outgoingOccurrenceID:
              route.routePlan.occurrences[index + 1].id,
            progressFraction: cumulativeDistance / totalDistance
          )
        )
      }
    }
    return matches.sorted {
      if $0.progressFraction != $1.progressFraction {
        return $0.progressFraction < $1.progressFraction
      }
      return $0.id < $1.id
    }
  }
}
