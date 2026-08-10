import Foundation
import KaidoDomain

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
  public let localizedJunctionNames: [KaidoReleaseLocale: String]
  public let localizedContent: [KaidoReleaseLocale: LocalizedGuidanceContent]
  public let commitTriggerDistanceMeters: Double
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
    localizedJunctionNames: [KaidoReleaseLocale: String],
    localizedContent: [KaidoReleaseLocale: LocalizedGuidanceContent],
    commitTriggerDistanceMeters: Double,
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
    self.localizedJunctionNames = localizedJunctionNames
    self.localizedContent = localizedContent
    self.commitTriggerDistanceMeters = commitTriggerDistanceMeters
    self.checkedAt = checkedAt
    self.expectedJunctionDetailSHA256 =
      expectedJunctionDetailSHA256
    self.sources = sources
  }
}

public enum ShutoJunctionMovementCatalog {
  public static let released: [ShutoJunctionMovementDefinition] = [
    ShutoJunctionMovementDefinition(
      id: "shuto.jct.shinonome.b-eastbound-to-10-inbound",
      networkSnapshotID:
        "shuto-official-2026-07-29-osm-2026-08-04",
      junctionID: "shuto.jct.jct_shinonome",
      junctionNodeID: 493_584_435,
      incomingEdgeID: "osm.888066406.1.forward",
      outgoingEdgeID: "osm.40636701.0.forward",
      incomingRouteID: "B",
      incomingDirectionJA: "東行き",
      outgoingRouteID: "10",
      outgoingDirectionJA: "上り",
      branchSide: .left,
      japaneseSignText: "豊洲",
      routeShields: ["10"],
      laneGuidanceState: .notReleased,
      localizedJunctionNames: [
        .japanese: "東雲JCT",
        .simplifiedChinese: "东云 JCT",
        .english: "Shinonome JCT",
      ],
      localizedContent: [
        .japanese: LocalizedGuidanceContent(
          displayText: "左方向へ分岐し、10号晴海線 上りへ",
          spokenText:
            "東雲ジャンクションでは左方向へ分岐し、10号晴海線 上りへ進んでください",
          spokenForms: ["10号晴海線": "じゅうごうはるみせん"],
          preservedJapaneseSignText: "豊洲"
        ),
        .simplifiedChinese: LocalizedGuidanceContent(
          displayText: "向左分岔，驶入 10 号晴海线上行方向",
          spokenText: "在东云枢纽向左分岔，驶入 10 号晴海线上行方向",
          spokenForms: ["10 号晴海线": "十号晴海线"],
          preservedJapaneseSignText: "豊洲"
        ),
        .english: LocalizedGuidanceContent(
          displayText: "Branch left for Route 10 inbound",
          spokenText:
            "At Shinonome Junction, branch left for Route 10 inbound",
          spokenForms: ["Route 10": "Route ten"],
          preservedJapaneseSignText: "豊洲"
        ),
      ],
      commitTriggerDistanceMeters: 100,
      checkedAt: "2026-07-30",
      expectedJunctionDetailSHA256:
        "452e2ca3d124ec3f726b0c3643cedbbc"
        + "e3446b21e755f538b418616278cfa605",
      sources: [
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/jct/"
        ),
        ShutoJunctionGuidanceSource(
          url:
            "https://www.shutoko.jp/use/convenience/"
            + "infoboard/guidance/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-b/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-10/"
        ),
        ShutoJunctionGuidanceSource(
          url:
            "https://www.shutoko.jp/-/media/images/responsive/"
            + "customer/use/network/jct/routeguide/jct_shinonome",
          contentSHA256:
            "452e2ca3d124ec3f726b0c3643cedbbc"
            + "e3446b21e755f538b418616278cfa605"
        ),
      ]
    ),
    ShutoJunctionMovementDefinition(
      id: "shuto.jct.shinonome.b-westbound-to-10-inbound",
      networkSnapshotID:
        "shuto-official-2026-07-29-osm-2026-08-04",
      junctionID: "shuto.jct.jct_shinonome",
      junctionNodeID: 569_015_558,
      incomingEdgeID: "osm.678697940.1.forward",
      outgoingEdgeID: "osm.44882717.0.forward",
      incomingRouteID: "B",
      incomingDirectionJA: "西行き",
      outgoingRouteID: "10",
      outgoingDirectionJA: "上り",
      branchSide: .right,
      japaneseSignText: "晴海",
      routeShields: ["10"],
      laneGuidanceState: .notReleased,
      localizedJunctionNames: [
        .japanese: "東雲JCT",
        .simplifiedChinese: "东云 JCT",
        .english: "Shinonome JCT",
      ],
      localizedContent: [
        .japanese: LocalizedGuidanceContent(
          displayText: "右方向へ分岐し、10号晴海線 上りへ",
          spokenText:
            "東雲ジャンクションでは右方向へ分岐し、10号晴海線 上りへ進んでください",
          spokenForms: ["10号晴海線": "じゅうごうはるみせん"],
          preservedJapaneseSignText: "晴海"
        ),
        .simplifiedChinese: LocalizedGuidanceContent(
          displayText: "向右分岔，驶入 10 号晴海线上行方向",
          spokenText: "在东云枢纽向右分岔，驶入 10 号晴海线上行方向",
          spokenForms: ["10 号晴海线": "十号晴海线"],
          preservedJapaneseSignText: "晴海"
        ),
        .english: LocalizedGuidanceContent(
          displayText: "Branch right for Route 10 inbound",
          spokenText:
            "At Shinonome Junction, branch right for Route 10 inbound",
          spokenForms: ["Route 10": "Route ten"],
          preservedJapaneseSignText: "晴海"
        ),
      ],
      commitTriggerDistanceMeters: 100,
      checkedAt: "2026-07-30",
      expectedJunctionDetailSHA256:
        "452e2ca3d124ec3f726b0c3643cedbbc"
        + "e3446b21e755f538b418616278cfa605",
      sources: [
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/jct/"
        ),
        ShutoJunctionGuidanceSource(
          url:
            "https://www.shutoko.jp/use/convenience/"
            + "infoboard/guidance/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-b/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-10/"
        ),
        ShutoJunctionGuidanceSource(
          url:
            "https://www.shutoko.jp/-/media/images/responsive/"
            + "customer/use/network/jct/routeguide/jct_shinonome",
          contentSHA256:
            "452e2ca3d124ec3f726b0c3643cedbbc"
            + "e3446b21e755f538b418616278cfa605"
        ),
      ]
    ),
    ShutoJunctionMovementDefinition(
      id: "shuto.jct.tatsumi.b-eastbound-to-9-inbound",
      networkSnapshotID:
        "shuto-official-2026-07-29-osm-2026-08-04",
      junctionID: "shuto.jct.jct_tatsumi",
      junctionNodeID: 31_300_414,
      incomingEdgeID: "osm.44882718.3.forward",
      outgoingEdgeID: "osm.4854234.0.forward",
      incomingRouteID: "B",
      incomingDirectionJA: "東行き",
      outgoingRouteID: "9",
      outgoingDirectionJA: "上り",
      branchSide: .left,
      japaneseSignText: "箱崎",
      routeShields: ["9", "6"],
      laneGuidanceState: .notReleased,
      localizedJunctionNames: [
        .japanese: "辰巳JCT",
        .simplifiedChinese: "辰巳 JCT",
        .english: "Tatsumi JCT",
      ],
      localizedContent: [
        .japanese: LocalizedGuidanceContent(
          displayText: "左方向へ分岐し、9号深川線 上りへ",
          spokenText:
            "辰巳ジャンクションでは左方向へ分岐し、9号深川線 上りへ進んでください",
          spokenForms: ["9号深川線": "きゅうごうふかがわせん"],
          preservedJapaneseSignText: "箱崎"
        ),
        .simplifiedChinese: LocalizedGuidanceContent(
          displayText: "向左分岔，驶入 9 号深川线上行方向",
          spokenText: "在辰巳枢纽向左分岔，驶入 9 号深川线上行方向",
          spokenForms: ["9 号深川线": "九号深川线"],
          preservedJapaneseSignText: "箱崎"
        ),
        .english: LocalizedGuidanceContent(
          displayText: "Branch left for Route 9 inbound",
          spokenText: "At Tatsumi Junction, branch left for Route 9 inbound",
          spokenForms: ["Route 9": "Route nine"],
          preservedJapaneseSignText: "箱崎"
        ),
      ],
      commitTriggerDistanceMeters: 100,
      checkedAt: "2026-07-30",
      expectedJunctionDetailSHA256:
        "c4ea23ea7741c0f9f54b875e62b04825"
        + "6501d7df8aac183ce8961d2eaf1b3dda",
      sources: [
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/jct/"
        ),
        ShutoJunctionGuidanceSource(
          url:
            "https://www.shutoko.jp/use/convenience/"
            + "infoboard/guidance/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-b/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-9/"
        ),
        ShutoJunctionGuidanceSource(
          url:
            "https://www.shutoko.jp/-/media/images/responsive/"
            + "customer/use/network/jct/routeguide/jct_tatsumi",
          contentSHA256:
            "c4ea23ea7741c0f9f54b875e62b04825"
            + "6501d7df8aac183ce8961d2eaf1b3dda"
        ),
      ]
    ),
    ShutoJunctionMovementDefinition(
      id: "shuto.jct.tatsumi.b-westbound-to-9-inbound",
      networkSnapshotID:
        "shuto-official-2026-07-29-osm-2026-08-04",
      junctionID: "shuto.jct.jct_tatsumi",
      junctionNodeID: 31_300_491,
      incomingEdgeID: "osm.888066409.1.forward",
      outgoingEdgeID: "osm.888066410.0.forward",
      incomingRouteID: "B",
      incomingDirectionJA: "西行き",
      outgoingRouteID: "9",
      outgoingDirectionJA: "上り",
      branchSide: .left,
      japaneseSignText: "箱崎・銀座",
      routeShields: ["9", "C1"],
      laneGuidanceState: .notReleased,
      localizedJunctionNames: [
        .japanese: "辰巳JCT",
        .simplifiedChinese: "辰巳 JCT",
        .english: "Tatsumi JCT",
      ],
      localizedContent: [
        .japanese: LocalizedGuidanceContent(
          displayText: "左方向へ分岐し、9号深川線 上りへ",
          spokenText:
            "辰巳ジャンクションでは左方向へ分岐し、9号深川線 上りへ進んでください",
          spokenForms: ["9号深川線": "きゅうごうふかがわせん"],
          preservedJapaneseSignText: "箱崎・銀座"
        ),
        .simplifiedChinese: LocalizedGuidanceContent(
          displayText: "向左分岔，驶入 9 号深川线上行方向",
          spokenText: "在辰巳枢纽向左分岔，驶入 9 号深川线上行方向",
          spokenForms: ["9 号深川线": "九号深川线"],
          preservedJapaneseSignText: "箱崎・銀座"
        ),
        .english: LocalizedGuidanceContent(
          displayText: "Branch left for Route 9 inbound",
          spokenText: "At Tatsumi Junction, branch left for Route 9 inbound",
          spokenForms: ["Route 9": "Route nine"],
          preservedJapaneseSignText: "箱崎・銀座"
        ),
      ],
      commitTriggerDistanceMeters: 100,
      checkedAt: "2026-07-30",
      expectedJunctionDetailSHA256:
        "c4ea23ea7741c0f9f54b875e62b04825"
        + "6501d7df8aac183ce8961d2eaf1b3dda",
      sources: [
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/jct/"
        ),
        ShutoJunctionGuidanceSource(
          url:
            "https://www.shutoko.jp/use/convenience/"
            + "infoboard/guidance/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-b/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-9/"
        ),
        ShutoJunctionGuidanceSource(
          url:
            "https://www.shutoko.jp/-/media/images/responsive/"
            + "customer/use/network/jct/routeguide/jct_tatsumi",
          contentSHA256:
            "c4ea23ea7741c0f9f54b875e62b04825"
            + "6501d7df8aac183ce8961d2eaf1b3dda"
        ),
      ]
    ),
    ShutoJunctionMovementDefinition(
      id: "shuto.jct.kasai.b-westbound-to-c2-inner",
      networkSnapshotID:
        "shuto-official-2026-07-29-osm-2026-08-04",
      junctionID: "shuto.jct.jct_kasai",
      junctionNodeID: 8_256_670_336,
      incomingEdgeID: "osm.888066413.1.forward",
      outgoingEdgeID: "osm.4857053.0.forward",
      incomingRouteID: "B",
      incomingDirectionJA: "西行き",
      outgoingRouteID: "C2",
      outgoingDirectionJA: "内回り",
      branchSide: .left,
      japaneseSignText: "東北道・常磐道",
      routeShields: ["C2", "E4", "E6", "6"],
      laneGuidanceState: .notReleased,
      localizedJunctionNames: [
        .japanese: "葛西JCT",
        .simplifiedChinese: "葛西 JCT",
        .english: "Kasai JCT",
      ],
      localizedContent: [
        .japanese: LocalizedGuidanceContent(
          displayText: "左方向へ分岐し、C2 内回りへ",
          spokenText:
            "葛西ジャンクションでは左方向へ分岐し、C2 内回りへ進んでください",
          spokenForms: ["C2": "シーツー"],
          preservedJapaneseSignText: "東北道・常磐道"
        ),
        .simplifiedChinese: LocalizedGuidanceContent(
          displayText: "向左分岔，驶入 C2 内环",
          spokenText: "在葛西枢纽向左分岔，驶入 C2 内环",
          spokenForms: ["C2": "C 二"],
          preservedJapaneseSignText: "東北道・常磐道"
        ),
        .english: LocalizedGuidanceContent(
          displayText: "Branch left for the C2 Inner Loop",
          spokenText:
            "At Kasai Junction, branch left for the C2 Inner Loop",
          spokenForms: ["C2": "C two"],
          preservedJapaneseSignText: "東北道・常磐道"
        ),
      ],
      commitTriggerDistanceMeters: 100,
      checkedAt: "2026-07-30",
      expectedJunctionDetailSHA256:
        "5e52b43abc96875472405c2fe5c2ca49"
        + "2946356ac0c86460f1610051289aa7b2",
      sources: [
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/jct/"
        ),
        ShutoJunctionGuidanceSource(
          url:
            "https://www.shutoko.jp/use/convenience/"
            + "infoboard/guidance/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-b/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-c2/"
        ),
        ShutoJunctionGuidanceSource(
          url:
            "https://www.shutoko.jp/-/media/images/responsive/"
            + "customer/use/network/jct/routeguide/jct_kasai",
          contentSHA256:
            "5e52b43abc96875472405c2fe5c2ca49"
            + "2946356ac0c86460f1610051289aa7b2"
        ),
      ]
    ),
    ShutoJunctionMovementDefinition(
      id: "shuto.jct.oi.b-westbound-to-c2-outer",
      networkSnapshotID:
        "shuto-official-2026-07-29-osm-2026-08-04",
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
      localizedJunctionNames: [
        .japanese: "大井JCT",
        .simplifiedChinese: "大井 JCT",
        .english: "Oi JCT",
      ],
      localizedContent: [
        .japanese: LocalizedGuidanceContent(
          displayText: "左方向へ分岐し、C2 外回りへ",
          spokenText:
            "大井ジャンクションでは左方向へ分岐し、C2 外回りへ進んでください",
          spokenForms: ["C2": "シーツー"],
          preservedJapaneseSignText: "東名・中央道"
        ),
        .simplifiedChinese: LocalizedGuidanceContent(
          displayText: "向左分岔，驶入 C2 外环",
          spokenText: "在大井枢纽向左分岔，驶入 C2 外环",
          spokenForms: ["C2": "C 二"],
          preservedJapaneseSignText: "東名・中央道"
        ),
        .english: LocalizedGuidanceContent(
          displayText: "Branch left for the C2 Outer Loop",
          spokenText: "At Oi Junction, branch left for the C2 Outer Loop",
          spokenForms: ["C2": "C two"],
          preservedJapaneseSignText: "東名・中央道"
        ),
      ],
      commitTriggerDistanceMeters: 100,
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
    ),
  ]

  public static func releasedDefinition(
    database: ShutoNetworkDatabase,
    incoming: ShutoNetworkDatabase.Edge,
    outgoing: ShutoNetworkDatabase.Edge
  ) -> ShutoJunctionMovementDefinition? {
    let junctionsByID = Dictionary(
      uniqueKeysWithValues: database.junctions.map {
        ($0.junctionID, $0)
      }
    )
    return released.first { definition in
      guard
        definition.networkSnapshotID == database.networkSnapshotID,
        definition.incomingEdgeID == incoming.edgeID,
        definition.outgoingEdgeID == outgoing.edgeID,
        incoming.toNodeID == definition.junctionNodeID,
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
        Set(definition.localizedJunctionNames.keys)
          == Set(KaidoReleaseLocale.allCases),
        Set(definition.localizedContent.keys)
          == Set(KaidoReleaseLocale.allCases),
        definition.localizedContent.values.allSatisfy({
          $0.preservedJapaneseSignText == definition.japaneseSignText
        }),
        definition.commitTriggerDistanceMeters.isFinite,
        definition.commitTriggerDistanceMeters > 0
      else {
        return false
      }
      return true
    }
  }
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
      zip(route.edges, route.routePlan.occurrences).enumerated()
        .allSatisfy({
          index, binding in
          let (edge, occurrence) = binding
          if edge.edgeID == occurrence.entityID {
            return true
          }
          guard index > 0 else { return false }
          return definitions.contains {
            $0.id == occurrence.entityID
              && $0.networkSnapshotID == database.networkSnapshotID
              && $0.incomingEdgeID == route.edges[index - 1].edgeID
              && $0.outgoingEdgeID == edge.edgeID
              && occurrence.kind == .junctionMovement
          }
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
          definition.localizedJunctionNames[.japanese]
            == junction.nameJA,
          Set(definition.localizedJunctionNames.keys)
            == Set(KaidoReleaseLocale.allCases),
          Set(definition.localizedContent.keys)
            == Set(KaidoReleaseLocale.allCases),
          definition.localizedContent.values.allSatisfy({
            $0.preservedJapaneseSignText
              == definition.japaneseSignText
          }),
          definition.commitTriggerDistanceMeters.isFinite,
          definition.commitTriggerDistanceMeters > 0,
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
