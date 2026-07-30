import Foundation
import KaidoDomain
import KaidoRouting
import Testing

@Suite("Whole Shuto junction guidance")
struct ShutoJunctionGuidanceTests {
  @Test("exact Kasai movement projects reviewed branch and sign guidance")
  func projectsExactKasaiMovement() throws {
    let database = try loadDatabase()
    let route = try ShutoRoutePlanner(database: database).plan(
      entryFacilityID: "shuto.ic.b.urayasu",
      exitFacilityID: "shuto.ic.c2.funaboribashi"
    )

    let match = try #require(
      ShutoJunctionGuidanceCompiler.compile(
        database: database,
        route: route
      ).only
    )
    let definition = match.definition

    #expect(match.junctionNameJA == "葛西JCT")
    #expect(
      definition.id == "shuto.jct.kasai.b-westbound-to-c2-inner"
    )
    #expect(definition.incomingRouteID == "B")
    #expect(definition.incomingDirectionJA == "西行き")
    #expect(definition.outgoingRouteID == "C2")
    #expect(definition.outgoingDirectionJA == "内回り")
    #expect(definition.branchSide == .left)
    #expect(definition.japaneseSignText == "東北道・常磐道")
    #expect(definition.routeShields == ["C2", "E4", "E6", "6"])
    #expect(definition.laneGuidanceState == .notReleased)
    #expect(definition.checkedAt == "2026-07-30")
    #expect(
      definition.sources.allSatisfy {
        $0.url.hasPrefix("https://www.shutoko.jp/")
      }
    )

    let incomingIndex = try #require(
      route.edges.firstIndex {
        $0.edgeID == definition.incomingEdgeID
      }
    )
    #expect(
      route.edges[incomingIndex + 1].edgeID
        == definition.outgoingEdgeID
    )
    #expect(
      match.incomingOccurrenceID
        == route.routePlan.occurrences[incomingIndex].id
    )
    #expect(
      match.outgoingOccurrenceID
        == route.routePlan.occurrences[incomingIndex + 1].id
    )
    #expect(
      route.routePlan.occurrences[incomingIndex + 1].kind
        == .junctionMovement
    )
    #expect(
      route.routePlan.occurrences[incomingIndex + 1].entityID
        == definition.id
    )
    #expect(
      definition.localizedContent[.simplifiedChinese]?.displayText
        == "向左分岔，驶入 C2 内环"
    )
    #expect(
      definition.localizedContent.values.allSatisfy {
        $0.preservedJapaneseSignText == "東北道・常磐道"
      }
    )
    #expect(definition.commitTriggerDistanceMeters == 100)
    #expect(match.progressFraction > 0)
    #expect(match.progressFraction < 1)
  }

  @Test("exact Oi movement projects reviewed branch and sign guidance")
  func projectsExactOiMovement() throws {
    let database = try loadDatabase()
    let route = try ShutoRoutePlanner(database: database).plan(
      entryFacilityID: "shuto.ic.b.rinkaihukutoshin",
      exitFacilityID: "shuto.ic.c2.hatsudaiminami"
    )

    let match = try #require(
      ShutoJunctionGuidanceCompiler.compile(
        database: database,
        route: route
      ).only
    )
    let definition = match.definition

    #expect(match.junctionNameJA == "大井JCT")
    #expect(
      definition.id == "shuto.jct.oi.b-westbound-to-c2-outer"
    )
    #expect(definition.incomingRouteID == "B")
    #expect(definition.incomingDirectionJA == "西行き")
    #expect(definition.outgoingRouteID == "C2")
    #expect(definition.outgoingDirectionJA == "外回り")
    #expect(definition.branchSide == .left)
    #expect(definition.japaneseSignText == "東名・中央道")
    #expect(definition.routeShields == ["C2", "3", "E1", "E20"])
    #expect(definition.laneGuidanceState == .notReleased)
    #expect(definition.checkedAt == "2026-07-29")
    #expect(
      definition.sources.allSatisfy {
        $0.url.hasPrefix("https://www.shutoko.jp/")
      }
    )

    let incomingIndex = try #require(
      route.edges.firstIndex {
        $0.edgeID == definition.incomingEdgeID
      }
    )
    #expect(
      route.edges[incomingIndex + 1].edgeID
        == definition.outgoingEdgeID
    )
    #expect(
      match.incomingOccurrenceID
        == route.routePlan.occurrences[incomingIndex].id
    )
    #expect(
      match.outgoingOccurrenceID
        == route.routePlan.occurrences[incomingIndex + 1].id
    )
    #expect(
      route.routePlan.occurrences[incomingIndex + 1].kind
        == .junctionMovement
    )
    #expect(
      route.routePlan.occurrences[incomingIndex + 1].entityID
        == definition.id
    )
    #expect(
      definition.localizedContent[.simplifiedChinese]?.displayText
        == "向左分岔，驶入 C2 外环"
    )
    #expect(
      definition.localizedContent.values.allSatisfy {
        $0.preservedJapaneseSignText == "東名・中央道"
      }
    )
    #expect(definition.commitTriggerDistanceMeters == 100)
    #expect(match.progressFraction > 0)
    #expect(match.progressFraction < 1)
  }

  @Test("unreviewed route-label changes do not create junction guidance")
  func suppressesUnreviewedRouteLabelChanges() throws {
    let database = try loadDatabase()
    let planner = try ShutoRoutePlanner(database: database)
    let recommendation = try #require(
      planner.recommend(
        from: ShutoCoordinate(
          latitude: 35.681236,
          longitude: 139.767125
        ),
        to: ShutoCoordinate(
          latitude: 35.443708,
          longitude: 139.646794
        )
      ).first
    )

    #expect(
      ShutoJunctionGuidanceCompiler.compile(
        database: database,
        route: recommendation.route
      ).isEmpty
    )
  }

  @Test("snapshot drift suppresses reviewed junction guidance")
  func suppressesSnapshotDrift() throws {
    let database = try loadDatabase()
    let route = try ShutoRoutePlanner(database: database).plan(
      entryFacilityID: "shuto.ic.b.rinkaihukutoshin",
      exitFacilityID: "shuto.ic.c2.hatsudaiminami"
    )
    let driftedPlan = RoutePlan(
      id: route.routePlan.id,
      networkSnapshotID: "test.drifted-snapshot",
      entryFacilityID: route.routePlan.entryFacilityID,
      exitFacilityID: route.routePlan.exitFacilityID,
      recoveryPolicy: route.routePlan.recoveryPolicy,
      actualDistanceKM: route.routePlan.actualDistanceKM,
      occurrences: route.routePlan.occurrences
    )
    let driftedRoute = ShutoPlannedRoute(
      routePlan: driftedPlan,
      entryFacility: route.entryFacility,
      exitFacility: route.exitFacility,
      edges: route.edges,
      coordinates: route.coordinates,
      routeIDsInOrder: route.routeIDsInOrder,
      distanceMeters: route.distanceMeters,
      preference: route.preference
    )

    #expect(
      ShutoJunctionGuidanceCompiler.compile(
        database: database,
        route: driftedRoute
      ).isEmpty
    )
  }

  private func loadDatabase() throws -> ShutoNetworkDatabase {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let url =
      repositoryRoot
      .appendingPathComponent("data")
      .appendingPathComponent("route-atlas")
      .appendingPathComponent("osm-derived")
      .appendingPathComponent("shuto-whole-network-20260728.json")
    return try JSONDecoder().decode(
      ShutoNetworkDatabase.self,
      from: Data(contentsOf: url)
    )
  }
}

extension Collection {
  fileprivate var only: Element? {
    count == 1 ? first : nil
  }
}
