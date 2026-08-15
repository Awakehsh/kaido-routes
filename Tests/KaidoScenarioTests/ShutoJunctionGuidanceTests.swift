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
      // The westbound corridor is reviewed at its continuations too, so
      // this route now guides more than one junction; select the exact
      // movement under test.
      let matches = ShutoJunctionGuidanceCompiler.compile(
        database: database,
        route: route
      )
      let match = try #require(
        matches.first { $0.definition.id == testCase.movementID }
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
      let matches = ShutoJunctionGuidanceCompiler.compile(
        database: database,
        route: route
      )
      let match = try #require(
        matches.first { $0.definition.id == testCase.movementID }
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
      ).first {
        $0.definition.id
          == "shuto.jct.oi.b-westbound-to-c2-outer"
      }
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

    // Edobashi is one operator instruction covering two immediate graph
    // forks; the runtime emits it once before the four later continuations.
    #expect(
      matches.map(\.junctionNameJA)
        == ["江戸橋JCT", "竹橋JCT", "三宅坂JCT", "谷町JCT", "一ノ橋JCT"]
    )
    // Each keeps the mainline and preserves the operator sign target the
    // driver actually reads at that junction.
    #expect(matches.allSatisfy { $0.definition.branchSide == .straight })
    #expect(
      matches.map(\.definition.japaneseSignText)
        == ["神田橋", "霞が関", "霞が関", "芝公園", "芝公園"]
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

  @Test("the C1 outer catalog loop is guided at every diverging junction")
  func guidesTheC1OuterLoop() throws {
    let database = try loadDatabase()
    let route = try ShutoRoutePlanner(database: database).planCircuit(
      circuit: .c1Outer,
      entryFacilityID: "shuto.ic.c1.kyoubashi",
      exitFacilityID: "shuto.ic.c1.shintomicho",
      laps: 1
    )

    let matches = ShutoJunctionGuidanceCompiler.compile(
      database: database,
      route: route
    )

    #expect(
      matches.map(\.junctionNameJA)
        == [
          "浜崎橋JCT", "一ノ橋JCT", "谷町JCT", "三宅坂JCT",
          "竹橋JCT", "江戸橋JCT",
        ]
    )
    #expect(matches.allSatisfy { $0.definition.branchSide == .straight })
    #expect(
      matches.map(\.definition.japaneseSignText)
        == [
          "芝公園", "渋谷・新宿", "中央道・北池袋", "神田橋・北池袋",
          "神田橋・箱崎", "羽田・銀座",
        ]
    )
    #expect(
      matches.allSatisfy {
        $0.definition.routeShields == ["C1"]
          && $0.definition.commitTriggerDistanceMeters == 300
          && $0.definition.laneGuidanceState == .notReleased
      }
    )
    for match in matches {
      let occurrence = route.routePlan.occurrence(
        id: match.outgoingOccurrenceID
      )
      #expect(occurrence?.kind == .junctionMovement)
      #expect(occurrence?.entityID == match.definition.id)
    }
  }

  @Test("the Bayshore westbound run is guided at every diverging junction")
  func guidesTheBayshoreWestboundRun() throws {
    let database = try loadDatabase()
    let planner = try ShutoRoutePlanner(database: database)
    let entrance = try #require(
      planner.circuitEntranceCandidates(
        for: .wanganDaikokuRun,
        origin: nil
      ).first
    )
    let pairing = try planner.recommendedCircuitPairing(
      for: .wanganDaikokuRun,
      entranceFacilityID: entrance.facilityID,
      origin: nil,
      evidence: .etcNormalCarActive
    )
    let route = try planner.planCircuit(
      circuit: .wanganDaikokuRun,
      entryFacilityID: pairing.entrance.facilityID,
      exitFacilityID: pairing.exit.facilityID,
      laps: 1
    )

    let matches = ShutoJunctionGuidanceCompiler.compile(
      database: database,
      route: route
    )

    // Every junction where another route diverges from the westbound
    // Bayshore is reviewed, so the run never passes a decision unguided.
    #expect(
      matches.map(\.junctionNameJA)
        == [
          "葛西JCT", "辰巳JCT", "東雲JCT", "有明JCT", "大井JCT",
          "東海JCT", "川崎浮島JCT", "大黒JCT",
        ]
    )
    #expect(matches.allSatisfy { $0.definition.branchSide == .straight })
    // Daikoku additionally signs Yokohama-Yokosuka Road; each definition
    // preserves the exact destinations and shields on its own diagram.
    #expect(
      matches.map(\.definition.japaneseSignText)
        == [
          "横浜", "横浜", "横浜", "横浜", "横浜",
          "空港中央・大黒ふ頭", "横浜", "横浜公園・横横道路",
        ]
    )
    #expect(
      matches.map(\.definition.routeShields)
        == Array(repeating: ["B"], count: 7)
          + [["B", "K3", "E16"]]
    )
    #expect(
      matches.allSatisfy {
        $0.definition.incomingDirectionJA == "西行き"
      }
    )
    for match in matches {
      let occurrence = route.routePlan.occurrence(
        id: match.outgoingOccurrenceID
      )
      #expect(occurrence?.kind == .junctionMovement)
    }
    #expect(
      matches.map(\.progressFraction)
        == matches.map(\.progressFraction).sorted()
    )
  }

  @Test("the eastbound Bayshore corridor is guided at its diverging junctions")
  func guidesTheEastboundBayshoreCorridor() throws {
    let database = try loadDatabase()
    let route = try ShutoRoutePlanner(database: database).plan(
      entryFacilityID: "shuto.ic.b.ooi",
      exitFacilityID: "shuto.ic.b.urayasu"
    )

    let matches = ShutoJunctionGuidanceCompiler.compile(
      database: database,
      route: route
    ).filter { $0.definition.incomingDirectionJA == "東行き" }

    // Running the Bayshore east, every junction where another route
    // diverges is reviewed, and each preserves the sign target its own
    // operator diagram shows for that approach.
    #expect(
      matches.map(\.junctionNameJA)
        == ["有明JCT", "東雲JCT", "辰巳JCT", "葛西JCT"]
    )
    #expect(
      matches.map(\.definition.japaneseSignText)
        == ["葛西", "浦安", "浦安", "浦安"]
    )
    // Daikoku sits further west on the same carriageway and signs its own
    // continuation for the airport, so it is checked against the catalog.
    let daikoku = try #require(
      ShutoJunctionMovementCatalog.released.first {
        $0.id == "shuto.jct.daikoku.b-eastbound-stays-on-b"
      }
    )
    #expect(daikoku.japaneseSignText == "アクアライン・空港中央")
    #expect(daikoku.routeShields == ["B", "CA"])
    #expect(daikoku.branchSide == .straight)
    #expect(daikoku.incomingDirectionJA == "東行き")
    #expect(matches.allSatisfy { $0.definition.branchSide == .straight })
    #expect(matches.allSatisfy { $0.definition.routeShields == ["B"] })
    for match in matches {
      #expect(
        route.routePlan.occurrence(id: match.outgoingOccurrenceID)?.kind
          == .junctionMovement
      )
    }
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

    let route = recommendation.route
    let matches = ShutoJunctionGuidanceCompiler.compile(
      database: database,
      route: route
    )
    let guidedPairs = Set(
      matches.map {
        "\($0.definition.incomingEdgeID)|\($0.definition.outgoingEdgeID)"
      }
    )
    let reviewedPairs = Set(
      ShutoJunctionMovementCatalog.released.map {
        "\($0.incomingEdgeID)|\($0.outgoingEdgeID)"
      }
    )

    // The route really does cross route-label boundaries.
    let labelChanges = zip(route.edges, route.edges.dropFirst()).filter {
      current, next in
      Set(current.routeMemberships.map(\.routeID))
        != Set(next.routeMemberships.map(\.routeID))
    }
    #expect(!labelChanges.isEmpty)

    // A label change alone never produces guidance: only an exact
    // reviewed movement does.
    for (current, next) in labelChanges {
      let pair = "\(current.edgeID)|\(next.edgeID)"
      if !reviewedPairs.contains(pair) {
        #expect(!guidedPairs.contains(pair))
      }
    }
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

  @Test("official route direction vocabulary gates exact movement guidance")
  func rejectsUnknownOfficialRouteDirection() throws {
    let originalDatabase = try loadDatabase()
    let route = try ShutoRoutePlanner(database: originalDatabase).plan(
      entryFacilityID: "shuto.ic.b.ooi",
      exitFacilityID: "shuto.ic.b.urayasu"
    )
    var document = try #require(
      JSONSerialization.jsonObject(
        with: JSONEncoder().encode(originalDatabase)
      )
        as? [String: Any]
    )
    var routes = try #require(document["routes"] as? [[String: Any]])
    let bayshoreIndex = try #require(
      routes.firstIndex { $0["route_id"] as? String == "B" }
    )
    routes[bayshoreIndex]["official_directions_ja"] = ["西行き"]
    document["routes"] = routes
    let database = try JSONDecoder().decode(
      ShutoNetworkDatabase.self,
      from: JSONSerialization.data(withJSONObject: document)
    )

    let matches = ShutoJunctionGuidanceCompiler.compile(
      database: database,
      route: route
    )

    #expect(matches.isEmpty)
    #expect(throws: ShutoNetworkError.invalidRouteDirections) {
      try database.validate()
    }
  }

  @Test("Miyakezaka and Tanimachi radial branches bind official signs")
  func centralRadialBranchesBindOfficialSigns() throws {
    let database = try loadDatabase()
    let edges = Dictionary(
      uniqueKeysWithValues: database.edges.map { ($0.edgeID, $0) }
    )
    let expectations: [
      (
        incoming: String,
        outgoing: String,
        id: String,
        side: ShutoJunctionBranchSide,
        sign: String
      )
    ] = [
      (
        "osm.24402540.6.forward",
        "osm.24402503.0.forward",
        "shuto.jct.miyakezaka.c1-inner-to-4-outbound",
        .left,
        "新宿・中央道"
      ),
      (
        "osm.24636595.7.forward",
        "osm.24636434.0.forward",
        "shuto.jct.miyakezaka.4-inbound-to-c1-outer",
        .left,
        "神田橋・箱崎"
      ),
      (
        "osm.24636595.7.forward",
        "osm.24636612.0.forward",
        "shuto.jct.miyakezaka.4-inbound-to-c1-inner",
        .right,
        "霞ヶ関・湾岸線"
      ),
      (
        "osm.895902565.2.forward",
        "osm.24336502.0.forward",
        "shuto.jct.tanimachi.c1-outer-to-3-outbound",
        .left,
        "東名・渋谷"
      ),
      (
        "osm.45392984.0.forward",
        "osm.24636451.0.forward",
        "shuto.jct.miyakezaka.c1-outer-to-4-outbound",
        .left,
        "新宿・中央道"
      ),
      (
        "osm.23297430.0.forward",
        "osm.45332351.0.forward",
        "shuto.jct.tanimachi.c1-inner-to-3-outbound",
        .right,
        "東名・渋谷"
      ),
    ]

    for expected in expectations {
      let incoming = try #require(edges[expected.incoming])
      let outgoing = try #require(edges[expected.outgoing])
      let definition = try #require(
        ShutoJunctionMovementCatalog.releasedDefinition(
          database: database,
          incoming: incoming,
          outgoing: outgoing
        )
      )
      #expect(definition.id == expected.id)
      #expect(definition.branchSide == expected.side)
      #expect(definition.japaneseSignText == expected.sign)
    }
  }

  @Test("single-gap JCT approaches bind current official signs")
  func singleGapJunctionApproachesBindOfficialSigns() throws {
    let database = try loadDatabase()
    let edges = Dictionary(
      uniqueKeysWithValues: database.edges.map { ($0.edgeID, $0) }
    )
    let expectations: [
      (
        incoming: String,
        outgoing: String,
        id: String,
        side: ShutoJunctionBranchSide,
        sign: String
      )
    ] = [
      (
        "osm.316213219.28.forward",
        "osm.45021972.0.forward",
        "shuto.jct.hamasakibashi.c1-outer-to-1-outbound",
        .left,
        "羽田・湾岸線"
      ),
      (
        "osm.888066402.7.forward",
        "osm.44129862.0.forward",
        "shuto.jct.kasai.b-eastbound-stays-on-b",
        .straight,
        "浦安"
      ),
      (
        "osm.331692344.2.forward",
        "osm.1308572350.0.forward",
        "shuto.jct.oi.c2-inner-stays-on-c2",
        .right,
        "中央道・都心環状"
      ),
      (
        "osm.1264293942.1.forward",
        "osm.40971846.0.forward",
        "shuto.jct.shinonome.10-outbound-to-b-eastbound",
        .left,
        "浦安"
      ),
    ]

    for expected in expectations {
      let incoming = try #require(edges[expected.incoming])
      let outgoing = try #require(edges[expected.outgoing])
      let definition = try #require(
        ShutoJunctionMovementCatalog.releasedDefinition(
          database: database,
          incoming: incoming,
          outgoing: outgoing
        )
      )
      #expect(definition.id == expected.id)
      #expect(definition.branchSide == expected.side)
      #expect(definition.japaneseSignText == expected.sign)
      #expect(definition.checkedAt == "2026-08-15")
      #expect(
        definition.sources.last?.contentSHA256
          == definition.expectedJunctionDetailSHA256
      )
    }
  }

  @Test("Takehashi and Ichinohashi radial branches bind official signs")
  func takehashiAndIchinohashiBranchesBindOfficialSigns() throws {
    let database = try loadDatabase()
    let edges = Dictionary(
      uniqueKeysWithValues: database.edges.map { ($0.edgeID, $0) }
    )
    let expectations: [
      (
        incoming: String,
        outgoing: String,
        id: String,
        side: ShutoJunctionBranchSide,
        sign: String
      )
    ] = [
      (
        "osm.24039737.3.forward",
        "osm.4853805.0.forward",
        "shuto.jct.ichinohashi.c1-outer-to-2-outbound",
        .left,
        "目黒"
      ),
      (
        "osm.23297444.19.forward",
        "osm.45248411.0.forward",
        "shuto.jct.ichinohashi.c1-inner-to-2-outbound",
        .right,
        "目黒"
      ),
      (
        "osm.7836679.9.forward",
        "osm.4853802.0.forward",
        "shuto.jct.ichinohashi.2-inbound-to-c1-outer",
        .left,
        "北池袋・新宿"
      ),
      (
        "osm.7836679.9.forward",
        "osm.4853804.0.forward",
        "shuto.jct.ichinohashi.2-inbound-to-c1-inner",
        .right,
        "湾岸線・銀座"
      ),
      (
        "osm.24039773.1.forward",
        "osm.24334770.0.forward",
        "shuto.jct.takehashi.c1-outer-to-5-outbound",
        .left,
        "北池袋・関越道"
      ),
      (
        "osm.1545541219.7.forward",
        "osm.1421966435.0.forward",
        "shuto.jct.takehashi.c1-inner-to-5-outbound",
        .right,
        "北池袋・関越道"
      ),
      (
        "osm.23681223.222.forward",
        "osm.23681223.223.forward",
        "shuto.jct.takehashi.5-inbound-to-c1-outer",
        .left,
        "神田橋・箱崎"
      ),
      (
        "osm.23681223.222.forward",
        "osm.955398790.0.forward",
        "shuto.jct.takehashi.5-inbound-to-c1-inner",
        .right,
        "霞が関・中央道"
      ),
    ]

    for expected in expectations {
      let incoming = try #require(edges[expected.incoming])
      let outgoing = try #require(edges[expected.outgoing])
      let definition = try #require(
        ShutoJunctionMovementCatalog.releasedDefinition(
          database: database,
          incoming: incoming,
          outgoing: outgoing
        )
      )
      #expect(definition.id == expected.id)
      #expect(definition.branchSide == expected.side)
      #expect(definition.japaneseSignText == expected.sign)
    }
  }

  @Test("Honmoku movements bind both current operator signs")
  func honmokuMovementsBindCurrentOperatorSigns() throws {
    let database = try loadDatabase()
    let edges = Dictionary(
      uniqueKeysWithValues: database.edges.map { ($0.edgeID, $0) }
    )
    let expectations: [
      (
        incoming: String,
        outgoing: String,
        id: String,
        side: ShutoJunctionBranchSide,
        sign: String,
        shields: [String]
      )
    ] = [
      (
        "osm.84530623.12.forward",
        "osm.301016676.0.forward",
        "shuto.jct.honmoku.k3-outbound-to-b-westbound",
        .left,
        "幸浦",
        ["B"]
      ),
      (
        "osm.84530623.12.forward",
        "osm.38072737.0.forward",
        "shuto.jct.honmoku.k3-outbound-to-b-eastbound",
        .straight,
        "空港中央・大黒ふ頭",
        ["B", "K5"]
      ),
      (
        "osm.435760593.169.forward",
        "osm.32403532.0.forward",
        "shuto.jct.honmoku.b-eastbound-to-k3-inbound",
        .left,
        "横浜駅東口・狩場線",
        ["K3", "K1", "K2"]
      ),
      (
        "osm.435760593.169.forward",
        "osm.435760593.170.forward",
        "shuto.jct.honmoku.b-eastbound-stays-on-b",
        .straight,
        "空港中央・大黒ふ頭",
        ["B", "K5"]
      ),
    ]

    for expected in expectations {
      let incoming = try #require(edges[expected.incoming])
      let outgoing = try #require(edges[expected.outgoing])
      let definition = try #require(
        ShutoJunctionMovementCatalog.releasedDefinition(
          database: database,
          incoming: incoming,
          outgoing: outgoing
        )
      )
      #expect(definition.id == expected.id)
      #expect(definition.branchSide == expected.side)
      #expect(definition.japaneseSignText == expected.sign)
      #expect(definition.routeShields == expected.shields)
      #expect(definition.checkedAt == "2026-08-15")
      #expect(
        definition.expectedJunctionDetailSHA256
          == "8d14238a40aaeaef7ec2c22904747f53f"
          + "335173c99583595b2152e5df4dbc934"
      )
      #expect(
        definition.sources.last?.url
          == "https://www.shutoko.jp/-/media/images/responsive/"
          + "customer/use/network/jct/routeguide/jct_honmoku"
      )
      #expect(
        definition.sources.last?.contentSHA256
          == definition.expectedJunctionDetailSHA256
      )
    }
  }

  @Test("Ariake movements bind all current operator signs")
  func ariakeMovementsBindCurrentOperatorSigns() throws {
    let database = try loadDatabase()
    let edges = Dictionary(
      uniqueKeysWithValues: database.edges.map { ($0.edgeID, $0) }
    )
    let expectations: [
      (
        incoming: String,
        outgoing: String,
        id: String,
        side: ShutoJunctionBranchSide,
        sign: String,
        shields: [String]
      )
    ] = [
      (
        "osm.45019025.1.forward",
        "osm.202805893.0.forward",
        "shuto.jct.ariake.11-outbound-to-b-eastbound",
        .straight,
        "東関東道",
        ["E51", "B", "9"]
      ),
      (
        "osm.45019025.1.forward",
        "osm.4848758.0.forward",
        "shuto.jct.ariake.11-outbound-to-b-westbound",
        .right,
        "横浜・空港中央",
        ["B", "1"]
      ),
      (
        "osm.1313249026.0.forward",
        "osm.23169048.0.forward",
        "shuto.jct.ariake.b-westbound-to-11-inbound",
        .left,
        "銀座",
        ["11", "C1"]
      ),
      (
        "osm.1313249026.0.forward",
        "osm.1313249025.0.forward",
        "shuto.jct.ariake.b-westbound-stays-on-b",
        .straight,
        "横浜",
        ["B"]
      ),
      (
        "osm.266086989.2.forward",
        "osm.4848757.0.forward",
        "shuto.jct.ariake.b-eastbound-to-11-inbound",
        .left,
        "都心環状",
        ["11", "C1"]
      ),
      (
        "osm.266086989.2.forward",
        "osm.266086989.3.forward",
        "shuto.jct.ariake.b-eastbound-stays-on-b",
        .straight,
        "葛西",
        ["B"]
      ),
    ]

    for expected in expectations {
      let incoming = try #require(edges[expected.incoming])
      let outgoing = try #require(edges[expected.outgoing])
      let definition = try #require(
        ShutoJunctionMovementCatalog.releasedDefinition(
          database: database,
          incoming: incoming,
          outgoing: outgoing
        )
      )
      #expect(definition.id == expected.id)
      #expect(definition.branchSide == expected.side)
      #expect(definition.japaneseSignText == expected.sign)
      #expect(definition.routeShields == expected.shields)
      #expect(
        definition.expectedJunctionDetailSHA256
          == "0351ca02b8260a625334bc17931b57d3"
          + "5d19631b4305fab64e014daf0aad4c26"
      )
      #expect(
        definition.sources.last?.url
          == "https://www.shutoko.jp/-/media/images/responsive/"
          + "customer/use/network/jct/routeguide/jct_ariake"
      )
      #expect(
        definition.sources.last?.contentSHA256
          == definition.expectedJunctionDetailSHA256
      )
    }
  }

  @Test("Kohoku movements bind both current operator approaches")
  func kohokuMovementsBindCurrentOperatorApproaches() throws {
    let database = try loadDatabase()
    let edges = Dictionary(
      uniqueKeysWithValues: database.edges.map { ($0.edgeID, $0) }
    )
    let expectations: [
      (
        incoming: String,
        outgoing: String,
        id: String,
        side: ShutoJunctionBranchSide,
        sign: String,
        shields: [String]
      )
    ] = [
      (
        "osm.780870438.63.forward",
        "osm.28188172.0.forward",
        "shuto.jct.kouhoku.c2-outer-to-s1-outbound",
        .left,
        "東北道",
        ["S1", "E4"]
      ),
      (
        "osm.780870438.63.forward",
        "osm.44211094.0.forward",
        "shuto.jct.kouhoku.c2-outer-stays-on-c2",
        .right,
        "常磐道・湾岸線",
        ["C2", "E6", "6"]
      ),
      (
        "osm.438367463.80.forward",
        "osm.28127450.0.forward",
        "shuto.jct.kouhoku.s1-inbound-to-c2-inner",
        .right,
        "中央道・東名",
        ["C2", "E20", "5", "E1"]
      ),
      (
        "osm.438367463.80.forward",
        "osm.867182414.0.forward",
        "shuto.jct.kouhoku.s1-inbound-to-c2-outer",
        .straight,
        "東関東道・銀座",
        ["E51", "C2", "6"]
      ),
    ]

    for expected in expectations {
      let incoming = try #require(edges[expected.incoming])
      let outgoing = try #require(edges[expected.outgoing])
      let definition = try #require(
        ShutoJunctionMovementCatalog.releasedDefinition(
          database: database,
          incoming: incoming,
          outgoing: outgoing
        )
      )
      #expect(definition.id == expected.id)
      #expect(definition.branchSide == expected.side)
      #expect(definition.japaneseSignText == expected.sign)
      #expect(definition.routeShields == expected.shields)
      #expect(
        definition.expectedJunctionDetailSHA256
          == "d168d950ee904e51e2332fb9e6c94cb9"
          + "ffad6ef825b01df9e917d1db8e372d81"
      )
      #expect(
        definition.sources.last?.url
          == "https://www.shutoko.jp/-/media/images/responsive/"
          + "customer/use/network/jct/routeguide/jct_kouhoku"
      )
    }
  }

  @Test("Daikoku movements bind all current operator signs")
  func daikokuMovementsBindCurrentOperatorSigns() throws {
    let database = try loadDatabase()
    let edges = Dictionary(
      uniqueKeysWithValues: database.edges.map { ($0.edgeID, $0) }
    )
    let expectations: [
      (
        incoming: String,
        outgoing: String,
        id: String,
        side: ShutoJunctionBranchSide,
        sign: String,
        shields: [String]
      )
    ] = [
      (
        "osm.1449791735.2.forward",
        "osm.15766920.0.forward",
        "shuto.jct.daikoku.b-westbound-to-k5-inbound",
        .left,
        "東名",
        ["E1", "K5", "K7"]
      ),
      (
        "osm.1449791735.2.forward",
        "osm.489510478.0.forward",
        "shuto.jct.daikoku.b-westbound-stays-on-b",
        .straight,
        "横浜公園・横横道路",
        ["B", "K3", "E16"]
      ),
      (
        "osm.5365195.2.forward",
        "osm.32355890.0.forward",
        "shuto.jct.daikoku.b-eastbound-to-k5-inbound",
        .left,
        "東名",
        ["E1", "K5", "K1", "K7"]
      ),
      (
        "osm.5365195.2.forward",
        "osm.5365195.3.forward",
        "shuto.jct.daikoku.b-eastbound-stays-on-b",
        .straight,
        "アクアライン・空港中央",
        ["B", "CA"]
      ),
      (
        "osm.32355898.7.forward",
        "osm.32592543.0.forward",
        "shuto.jct.daikoku.k5-outbound-to-b-eastbound",
        .left,
        "空港中央・東関東道",
        ["B", "K6", "E51"]
      ),
      (
        "osm.32355898.7.forward",
        "osm.779045459.0.forward",
        "shuto.jct.daikoku.k5-outbound-to-b-westbound",
        .straight,
        "横浜公園・幸浦",
        ["B", "K3"]
      ),
    ]

    for expected in expectations {
      let incoming = try #require(edges[expected.incoming])
      let outgoing = try #require(edges[expected.outgoing])
      let definition = try #require(
        ShutoJunctionMovementCatalog.releasedDefinition(
          database: database,
          incoming: incoming,
          outgoing: outgoing
        )
      )
      #expect(definition.id == expected.id)
      #expect(definition.branchSide == expected.side)
      #expect(definition.japaneseSignText == expected.sign)
      #expect(definition.routeShields == expected.shields)
      #expect(
        definition.expectedJunctionDetailSHA256
          == "4fcd99ab1e97a6a84f6c5c41e86c2b16"
          + "247f5acd1b8c34e1e2e5397cf3c004eb"
      )
      #expect(
        definition.sources.last?.url
          == "https://www.shutoko.jp/-/media/images/responsive/"
          + "customer/use/network/jct/routeguide/jct_daikoku"
      )
    }
  }

  @Test("Ohashi movements bind all three approach signs")
  func ohashiMovementsBindAllThreeApproachSigns() throws {
    let database = try loadDatabase()
    let edges = Dictionary(
      uniqueKeysWithValues: database.edges.map { ($0.edgeID, $0) }
    )
    let expectations: [
      (
        incoming: String,
        outgoing: String,
        id: String,
        side: ShutoJunctionBranchSide,
        sign: String,
        shields: [String]
      )
    ] = [
      (
        "osm.254992124.8.forward",
        "osm.254992124.9.forward",
        "shuto.jct.ohashi.3-inbound-stays-on-3",
        .straight,
        "渋谷・都心環状",
        ["3", "C1"]
      ),
      (
        "osm.254992124.8.forward",
        "osm.78334077.0.forward",
        "shuto.jct.ohashi.3-inbound-to-c2",
        .right,
        "湾岸線・東北道",
        ["C2", "B", "E4"]
      ),
      (
        "osm.80581127.78.forward",
        "osm.331692348.0.forward",
        "shuto.jct.ohashi.c2-inner-stays-on-c2",
        .left,
        "湾岸線",
        ["C2"]
      ),
      (
        "osm.80581127.78.forward",
        "osm.331922702.0.forward",
        "shuto.jct.ohashi.c2-inner-to-3",
        .right,
        "都心環状・東名",
        ["3", "C1", "E1"]
      ),
      (
        "osm.772511247.10.forward",
        "osm.331922711.0.forward",
        "shuto.jct.ohashi.c2-outer-stays-on-c2",
        .straight,
        "中央道・東北道",
        ["C2", "4", "5", "E20", "E4"]
      ),
      (
        "osm.772511247.10.forward",
        "osm.331922695.0.forward",
        "shuto.jct.ohashi.c2-outer-to-3",
        .left,
        "都心環状・東名",
        ["3", "C1", "E1"]
      ),
    ]

    for expected in expectations {
      let incoming = try #require(edges[expected.incoming])
      let outgoing = try #require(edges[expected.outgoing])
      let definition = try #require(
        ShutoJunctionMovementCatalog.releasedDefinition(
          database: database,
          incoming: incoming,
          outgoing: outgoing
        )
      )
      #expect(definition.id == expected.id)
      #expect(definition.branchSide == expected.side)
      #expect(definition.japaneseSignText == expected.sign)
      #expect(definition.routeShields == expected.shields)
      #expect(
        definition.expectedJunctionDetailSHA256
          == "5f27a01a763abd067d5bbd9108a6cd19"
          + "368a31492b779f57cd045d5053e4dcaa"
      )
      #expect(
        definition.sources.last?.url
          == "https://www.shutoko.jp/-/media/images/responsive/"
          + "customer/use/network/jct/routeguide/jct_ohashi"
      )
    }
  }

  @Test("Komatsugawa movements exclude the Funaboribashi facility fork")
  func komatsugawaMovementsExcludeFunaboribashiFacilityFork() throws {
    let database = try loadDatabase()
    let edges = Dictionary(
      uniqueKeysWithValues: database.edges.map { ($0.edgeID, $0) }
    )
    let expectations: [
      (
        incoming: String,
        outgoing: String,
        id: String,
        side: ShutoJunctionBranchSide,
        sign: String,
        shields: [String]
      )
    ] = [
      (
        "osm.184872023.41.forward",
        "osm.184872023.42.forward",
        "shuto.jct.komatsugawa.c2-outer-stays-on-c2",
        .straight,
        "湾岸線・東関東道",
        ["C2", "B", "E51"]
      ),
      (
        "osm.184872023.41.forward",
        "osm.751177038.0.forward",
        "shuto.jct.komatsugawa.c2-outer-to-7-outbound",
        .left,
        "京葉道路・小松川",
        ["7", "E14"]
      ),
      (
        "osm.59338971.14.forward",
        "osm.59338971.15.forward",
        "shuto.jct.komatsugawa.7-inbound-stays-on-7",
        .straight,
        "都心環状",
        ["7", "6", "C1"]
      ),
      (
        "osm.59338971.14.forward",
        "osm.751177037.0.forward",
        "shuto.jct.komatsugawa.7-inbound-to-c2-inner",
        .left,
        "東北道・常磐道",
        ["C2", "E4", "E6"]
      ),
    ]

    for expected in expectations {
      let incoming = try #require(edges[expected.incoming])
      let outgoing = try #require(edges[expected.outgoing])
      let definition = try #require(
        ShutoJunctionMovementCatalog.releasedDefinition(
          database: database,
          incoming: incoming,
          outgoing: outgoing
        )
      )
      #expect(definition.id == expected.id)
      #expect(definition.branchSide == expected.side)
      #expect(definition.japaneseSignText == expected.sign)
      #expect(definition.routeShields == expected.shields)
      #expect(
        definition.expectedJunctionDetailSHA256
          == "a5119a85526658f19dda55b445114dd2"
          + "b72a1ee0161a454b0f55712872c84abe"
      )
      #expect(
        definition.sources.last?.url
          == "https://www.shutoko.jp/-/media/images/responsive/"
          + "customer/use/network/jct/routeguide/jct_komatsugawa"
      )
    }

    let funaboribashiIncoming = try #require(
      edges["osm.4857050.46.forward"]
    )
    for outgoingID in [
      "osm.4857050.47.forward",
      "osm.383231005.0.forward",
    ] {
      let outgoing = try #require(edges[outgoingID])
      #expect(
        ShutoJunctionMovementCatalog.releasedDefinition(
          database: database,
          incoming: funaboribashiIncoming,
          outgoing: outgoing
        ) == nil
      )
    }
  }

  @Test("Ryogoku and Shibaura outbound branches bind official signs")
  func ryogokuAndShibauraOutboundBranchesBindOfficialSigns() throws {
    let database = try loadDatabase()
    let edges = Dictionary(
      uniqueKeysWithValues: database.edges.map { ($0.edgeID, $0) }
    )
    let expectations: [
      (
        incoming: String,
        outgoing: String,
        id: String,
        side: ShutoJunctionBranchSide,
        sign: String,
        shields: [String],
        detailSHA256: String
      )
    ] = [
      (
        "osm.1544832378.11.forward",
        "osm.712498144.0.forward",
        "shuto.jct.ryogoku.6-outbound-stays-on-6",
        .left,
        "東北道・常磐道",
        ["6", "E4", "E6"],
        "720995e96dbb9e570a481e8918bd8b49"
          + "bef2b7af9e79b4ab660eb6e1460ad66a"
      ),
      (
        "osm.1544832378.11.forward",
        "osm.44506762.0.forward",
        "shuto.jct.ryogoku.6-outbound-to-7-outbound",
        .right,
        "京葉道路",
        ["7", "E14"],
        "720995e96dbb9e570a481e8918bd8b49"
          + "bef2b7af9e79b4ab660eb6e1460ad66a"
      ),
      (
        "osm.1102698847.2.forward",
        "osm.1102698847.3.forward",
        "shuto.jct.shibaura.1-outbound-stays-on-1",
        .right,
        "横浜",
        ["1", "K1"],
        "c190fee58d35efdaeb0ad62015c838131"
          + "e00f4e7386cde2510e8aa1d83a1790c"
      ),
      (
        "osm.1102698847.2.forward",
        "osm.4847519.0.forward",
        "shuto.jct.shibaura.1-outbound-to-11-outbound",
        .left,
        "湾岸線",
        ["11", "B"],
        "c190fee58d35efdaeb0ad62015c838131"
          + "e00f4e7386cde2510e8aa1d83a1790c"
      ),
    ]

    for expected in expectations {
      let incoming = try #require(edges[expected.incoming])
      let outgoing = try #require(edges[expected.outgoing])
      let definition = try #require(
        ShutoJunctionMovementCatalog.releasedDefinition(
          database: database,
          incoming: incoming,
          outgoing: outgoing
        )
      )
      #expect(definition.id == expected.id)
      #expect(definition.branchSide == expected.side)
      #expect(definition.japaneseSignText == expected.sign)
      #expect(definition.routeShields == expected.shields)
      #expect(
        definition.expectedJunctionDetailSHA256
          == expected.detailSHA256
      )
      #expect(definition.checkedAt == "2026-08-15")
      #expect(definition.commitTriggerDistanceMeters == 300)
      #expect(
        definition.sources.allSatisfy {
          $0.url.hasPrefix("https://www.shutoko.jp/")
        }
      )
    }
  }

  @Test("Edobashi movements bind every current operator sign")
  func edobashiMovementsBindEveryCurrentOperatorSign() throws {
    let database = try loadDatabase()
    let edges = Dictionary(
      uniqueKeysWithValues: database.edges.map { ($0.edgeID, $0) }
    )
    let expectations: [
      (
        incoming: String,
        outgoing: String,
        id: String,
        side: ShutoJunctionBranchSide,
        sign: String,
        shields: [String]
      )
    ] = [
      (
        "osm.316185365.6.forward",
        "osm.44803854.0.forward",
        "shuto.jct.edobashi.c1-outer-to-6-outbound",
        .left,
        "箱崎・常磐道",
        ["6", "E6"]
      ),
      (
        "osm.41009552.1.forward",
        "osm.44804643.0.forward",
        "shuto.jct.edobashi.c1-inner-to-6-outbound",
        .right,
        "上野",
        ["1"]
      ),
      (
        "osm.44805858.19.forward",
        "osm.40971852.0.forward",
        "shuto.jct.edobashi.6-inbound-toward-ginza",
        .left,
        "銀座・横浜",
        ["C1", "7"]
      ),
      (
        "osm.44805858.19.forward",
        "osm.44803855.0.forward",
        "shuto.jct.edobashi.6-inbound-toward-kandabashi",
        .right,
        "神田橋・北池袋・中央道",
        ["C1", "5", "E20"]
      ),
    ]

    for expected in expectations {
      let incoming = try #require(edges[expected.incoming])
      let outgoing = try #require(edges[expected.outgoing])
      let definition = try #require(
        ShutoJunctionMovementCatalog.releasedDefinition(
          database: database,
          incoming: incoming,
          outgoing: outgoing
        )
      )
      #expect(definition.id == expected.id)
      #expect(definition.branchSide == expected.side)
      #expect(definition.japaneseSignText == expected.sign)
      #expect(definition.routeShields == expected.shields)
      #expect(definition.checkedAt == "2026-08-15")
      #expect(
        definition.expectedJunctionDetailSHA256
          == "a855321a4dbf059131cada07f5dfd0e0"
          + "73762b063034053807b25001956db975"
      )
      #expect(
        definition.sources.contains {
          $0.url
            == "https://www.shutoko.jp/-/media/images/responsive/"
              + "customer/use/network/jct/routeguide/jct_edobashi"
            && $0.contentSHA256
              == "a855321a4dbf059131cada07f5dfd0e0"
                + "73762b063034053807b25001956db975"
        }
      )
    }
  }

  @Test("Yokohama catalog routes bind every reviewed prompt to a movement")
  func yokohamaCatalogGuidanceBindsJunctionOccurrences() throws {
    let database = try loadDatabase()
    let planner = try ShutoRoutePlanner(database: database)
    let routes = [
      try planner.planCircuit(
        circuit: .daikokuYokohamaLoop,
        entryFacilityID: "shuto.ic.b.higashiogishima",
        exitFacilityID: "shuto.ic.b.daikokufutou",
        laps: 1
      ),
      try planner.planCircuit(
        circuit: .scenicGrandTour,
        entryFacilityID: "shuto.ic.10.harumi",
        exitFacilityID: "shuto.ic.b.daikokufutou",
        laps: 1
      ),
    ]

    for route in routes {
      let matches = ShutoJunctionGuidanceCompiler.compile(
        database: database,
        route: route
      )
      #expect(!matches.isEmpty)
      for match in matches {
        let occurrence = route.routePlan.occurrence(
          id: match.outgoingOccurrenceID
        )
        if occurrence?.kind != .junctionMovement
          || occurrence?.entityID != match.definition.id
        {
          Issue.record(
            "\(match.definition.id) targets \(match.outgoingOccurrenceID) as \(String(describing: occurrence))"
          )
        }
      }
    }
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
