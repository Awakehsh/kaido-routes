import Foundation
import KaidoDomain
import KaidoRouting
import Testing

@Suite("Whole Shuto junction guidance")
struct ShutoJunctionGuidanceTests {
  @Test("both exact Shinonome approaches preserve branch and sign")
  func projectsExactShinonomeMovements() throws {
    let database = try loadDatabase()
    let cases:
      [(
        entryFacilityID: String,
        movementID: String,
        incomingDirectionJA: String,
        incomingEdgeID: String,
        outgoingEdgeID: String,
        junctionNodeID: Int64,
        branchSide: ShutoJunctionBranchSide,
        signText: String,
        localizedInstruction: String
      )] = [
        (
          "shuto.ic.b.ooi",
          "shuto.jct.shinonome.b-eastbound-to-10-inbound",
          "東行き",
          "osm.888066406.1.forward",
          "osm.40636701.0.forward",
          493_584_435,
          .left,
          "豊洲",
          "向左分岔，驶入 10 号晴海线上行方向"
        ),
        (
          "shuto.ic.b.shinkiba",
          "shuto.jct.shinonome.b-westbound-to-10-inbound",
          "西行き",
          "osm.678697940.1.forward",
          "osm.44882717.0.forward",
          569_015_558,
          .right,
          "晴海",
          "向右分岔，驶入 10 号晴海线上行方向"
        ),
      ]

    for testCase in cases {
      let route = try ShutoRoutePlanner(database: database).plan(
        entryFacilityID: testCase.entryFacilityID,
        exitFacilityID: "shuto.ic.10.harumi"
      )
      let match = try #require(
        ShutoJunctionGuidanceCompiler.compile(
          database: database,
          route: route
        ).only
      )
      let definition = match.definition

      #expect(match.junctionNameJA == "東雲JCT")
      #expect(definition.id == testCase.movementID)
      #expect(definition.junctionNodeID == testCase.junctionNodeID)
      #expect(definition.incomingEdgeID == testCase.incomingEdgeID)
      #expect(definition.outgoingEdgeID == testCase.outgoingEdgeID)
      #expect(definition.incomingRouteID == "B")
      #expect(
        definition.incomingDirectionJA == testCase.incomingDirectionJA
      )
      #expect(definition.outgoingRouteID == "10")
      #expect(definition.outgoingDirectionJA == "上り")
      #expect(definition.branchSide == testCase.branchSide)
      #expect(definition.japaneseSignText == testCase.signText)
      #expect(definition.routeShields == ["10"])
      #expect(definition.laneGuidanceState == .notReleased)
      #expect(definition.checkedAt == "2026-07-30")
      #expect(
        definition.expectedJunctionDetailSHA256
          == "452e2ca3d124ec3f726b0c3643cedbbc"
          + "e3446b21e755f538b418616278cfa605"
      )
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
          == testCase.localizedInstruction
      )
      #expect(
        definition.localizedContent.values.allSatisfy {
          $0.preservedJapaneseSignText == testCase.signText
        }
      )
      #expect(definition.commitTriggerDistanceMeters == 100)
      #expect(match.progressFraction > 0)
      #expect(match.progressFraction < 1)
    }
  }

  @Test("both exact Tatsumi approaches preserve their reviewed signs")
  func projectsExactTatsumiMovements() throws {
    let database = try loadDatabase()
    let cases:
      [(
        entryFacilityID: String,
        movementID: String,
        incomingDirectionJA: String,
        incomingEdgeID: String,
        outgoingEdgeID: String,
        junctionNodeID: Int64,
        signText: String,
        routeShields: [String]
      )] = [
        (
          "shuto.ic.b.ooi",
          "shuto.jct.tatsumi.b-eastbound-to-9-inbound",
          "東行き",
          "osm.44882718.3.forward",
          "osm.4854234.0.forward",
          31_300_414,
          "箱崎",
          ["9", "6"]
        ),
        (
          "shuto.ic.b.urayasu",
          "shuto.jct.tatsumi.b-westbound-to-9-inbound",
          "西行き",
          "osm.888066409.1.forward",
          "osm.888066410.0.forward",
          31_300_491,
          "箱崎・銀座",
          ["9", "C1"]
        ),
      ]

    for testCase in cases {
      let route = try ShutoRoutePlanner(database: database).plan(
        entryFacilityID: testCase.entryFacilityID,
        exitFacilityID: "shuto.ic.9.fukudumi"
      )
      let match = try #require(
        ShutoJunctionGuidanceCompiler.compile(
          database: database,
          route: route
        ).only
      )
      let definition = match.definition

      #expect(match.junctionNameJA == "辰巳JCT")
      #expect(definition.id == testCase.movementID)
      #expect(definition.junctionNodeID == testCase.junctionNodeID)
      #expect(definition.incomingEdgeID == testCase.incomingEdgeID)
      #expect(definition.outgoingEdgeID == testCase.outgoingEdgeID)
      #expect(definition.incomingRouteID == "B")
      #expect(
        definition.incomingDirectionJA == testCase.incomingDirectionJA
      )
      #expect(definition.outgoingRouteID == "9")
      #expect(definition.outgoingDirectionJA == "上り")
      #expect(definition.branchSide == .left)
      #expect(definition.japaneseSignText == testCase.signText)
      #expect(definition.routeShields == testCase.routeShields)
      #expect(definition.laneGuidanceState == .notReleased)
      #expect(definition.checkedAt == "2026-07-30")
      #expect(
        definition.expectedJunctionDetailSHA256
          == "c4ea23ea7741c0f9f54b875e62b04825"
          + "6501d7df8aac183ce8961d2eaf1b3dda"
      )
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
          == "向左分岔，驶入 9 号深川线上行方向"
      )
      #expect(
        definition.localizedContent.values.allSatisfy {
          $0.preservedJapaneseSignText == testCase.signText
        }
      )
      #expect(definition.commitTriggerDistanceMeters == 100)
      #expect(match.progressFraction > 0)
      #expect(match.progressFraction < 1)
    }
  }

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

  @Test("the C1 inner catalog loop is guided at every diverging junction")
  func guidesTheC1InnerLoop() throws {
    let database = try loadDatabase()
    let planner = try ShutoRoutePlanner(database: database)
    let route = try planner.planCircuit(
      circuit: .c1Inner,
      entryFacilityID: "shuto.ic.c1.shibakouen",
      exitFacilityID: "shuto.ic.c1.shiodome",
      laps: 1
    )

    let matches = ShutoJunctionGuidanceCompiler.compile(
      database: database,
      route: route
    )

    // Every junction where another route diverges from the inner loop is
    // reviewed, so a lap never runs without an instruction at a decision.
    // Ordered as the lap encounters them from Shibakoen.
    #expect(
      matches.map(\.junctionNameJA)
        == ["竹橋JCT", "三宅坂JCT", "谷町JCT", "一ノ橋JCT"]
    )
    // Each keeps the mainline and preserves the operator sign target the
    // driver actually reads at that junction.
    #expect(matches.allSatisfy { $0.definition.branchSide == .straight })
    #expect(
      matches.map(\.definition.japaneseSignText)
        == ["霞が関", "霞が関", "芝公園", "芝公園"]
    )
    #expect(
      matches.allSatisfy {
        $0.definition.routeShields == ["C1"]
          && $0.definition.laneGuidanceState == .notReleased
      }
    )
    // Reviewing a movement promotes its occurrence, which is what lets the
    // runtime bind a decision zone and speak the prompt.
    for match in matches {
      let occurrence = route.routePlan.occurrence(
        id: match.outgoingOccurrenceID
      )
      #expect(occurrence?.kind == .junctionMovement)
      #expect(occurrence?.entityID == match.definition.id)
    }
    #expect(
      matches.map(\.progressFraction)
        == matches.map(\.progressFraction).sorted()
    )
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
      .appendingPathComponent("shuto-whole-network-20260804.json")
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
