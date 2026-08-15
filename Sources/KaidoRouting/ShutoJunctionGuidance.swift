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
  /// Additional immediate forks covered by the same operator sign and spoken
  /// instruction. The IDs are ordered after `outgoingEdgeID`; they do not
  /// create additional prompts.
  public let coveredFollowingDecisionEdgeIDs: [String]
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
    coveredFollowingDecisionEdgeIDs: [String] = [],
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
    self.coveredFollowingDecisionEdgeIDs =
      coveredFollowingDecisionEdgeIDs
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
  private static func c2InnerMovement(
    id: String,
    junctionID: String,
    junctionNodeID: Int64,
    incomingEdgeID: String,
    outgoingEdgeID: String,
    incomingRouteID: String = "C2",
    incomingDirectionJA: String = "内回り",
    outgoingRouteID: String = "C2",
    outgoingDirectionJA: String = "内回り",
    coveredFollowingDecisionEdgeIDs: [String] = [],
    branchSide: ShutoJunctionBranchSide,
    japaneseSignText: String,
    routeShields: [String],
    junctionNameJA: String,
    junctionNameZH: String,
    junctionNameEN: String,
    destinationJA: String,
    destinationZH: String,
    destinationEN: String,
    expectedJunctionDetailSHA256: String,
    officialDetailReference: String,
    additionalSources: [String] = []
  ) -> ShutoJunctionMovementDefinition {
    let coversFollowingDecision = !coveredFollowingDecisionEdgeIDs.isEmpty
    let maneuverJA: String
    let maneuverZH: String
    let maneuverEN: String
    switch (branchSide, coversFollowingDecision) {
    case (.left, true):
      maneuverJA = "左方向を保ち"
      maneuverZH = "保持左侧"
      maneuverEN = "keep left"
    case (.right, true):
      maneuverJA = "右方向を保ち"
      maneuverZH = "保持右侧"
      maneuverEN = "keep right"
    case (.left, false):
      maneuverJA = "左方向へ分岐し"
      maneuverZH = "向左分岔"
      maneuverEN = "branch left"
    case (.right, false):
      maneuverJA = "右方向へ分岐し"
      maneuverZH = "向右分岔"
      maneuverEN = "branch right"
    case (.straight, _):
      maneuverJA = "分岐せず"
      maneuverZH = "不要分岔"
      maneuverEN = "continue straight"
    }
    let detailSource = ShutoJunctionGuidanceSource(
      url: officialDetailReference,
      contentSHA256: expectedJunctionDetailSHA256
    )
    return ShutoJunctionMovementDefinition(
      id: id,
      networkSnapshotID: "shuto-official-2026-07-29-osm-2026-08-04",
      junctionID: junctionID,
      junctionNodeID: junctionNodeID,
      incomingEdgeID: incomingEdgeID,
      outgoingEdgeID: outgoingEdgeID,
      incomingRouteID: incomingRouteID,
      incomingDirectionJA: incomingDirectionJA,
      outgoingRouteID: outgoingRouteID,
      outgoingDirectionJA: outgoingDirectionJA,
      coveredFollowingDecisionEdgeIDs: coveredFollowingDecisionEdgeIDs,
      branchSide: branchSide,
      japaneseSignText: japaneseSignText,
      routeShields: routeShields,
      laneGuidanceState: .notReleased,
      localizedJunctionNames: [
        .japanese: junctionNameJA,
        .simplifiedChinese: junctionNameZH,
        .english: junctionNameEN,
      ],
      localizedContent: [
        .japanese: LocalizedGuidanceContent(
          displayText: "\(maneuverJA)、\(destinationJA)へ",
          spokenText:
            "\(junctionNameJA)では\(maneuverJA)、\(destinationJA)へ進んでください",
          spokenForms: [
            "C2": "シーツー",
            "湾岸線": "わんがんせん",
          ],
          preservedJapaneseSignText: japaneseSignText
        ),
        .simplifiedChinese: LocalizedGuidanceContent(
          displayText: "\(maneuverZH)，驶往 \(destinationZH)",
          spokenText: "在\(junctionNameZH)\(maneuverZH)，驶往 \(destinationZH)",
          spokenForms: ["C2": "C 二"],
          preservedJapaneseSignText: japaneseSignText
        ),
        .english: LocalizedGuidanceContent(
          displayText: "\(maneuverEN.capitalized) for \(destinationEN)",
          spokenText: "At \(junctionNameEN), \(maneuverEN) for \(destinationEN)",
          spokenForms: ["C2": "C two"],
          preservedJapaneseSignText: japaneseSignText
        ),
      ],
      commitTriggerDistanceMeters: 100,
      checkedAt: "2026-08-15",
      expectedJunctionDetailSHA256: expectedJunctionDetailSHA256,
      sources: [
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/jct/"
        )
      ] + additionalSources.map { ShutoJunctionGuidanceSource(url: $0) }
        + [detailSource]
    )
  }

  private static func reviewedMovement(
    id: String,
    junctionID: String,
    junctionNodeID: Int64,
    incomingEdgeID: String,
    outgoingEdgeID: String,
    incomingRouteID: String,
    incomingDirectionJA: String,
    outgoingRouteID: String,
    outgoingDirectionJA: String,
    coveredFollowingDecisionEdgeIDs: [String] = [],
    branchSide: ShutoJunctionBranchSide,
    maneuverJA: String? = nil,
    maneuverZH: String? = nil,
    maneuverEN: String? = nil,
    japaneseSignText: String,
    routeShields: [String],
    junctionNameJA: String,
    junctionNameZH: String,
    junctionNameEN: String,
    destinationJA: String,
    destinationZH: String,
    destinationEN: String,
    commitTriggerDistanceMeters: Double = 100,
    expectedJunctionDetailSHA256: String,
    officialDetailReference: String,
    additionalSources: [String]
  ) -> ShutoJunctionMovementDefinition {
    let defaultManeuverJA: String
    let defaultManeuverZH: String
    let defaultManeuverEN: String
    switch branchSide {
    case .left:
      defaultManeuverJA = "左方向へ分岐し"
      defaultManeuverZH = "向左分岔"
      defaultManeuverEN = "branch left"
    case .right:
      defaultManeuverJA = "右方向へ分岐し"
      defaultManeuverZH = "向右分岔"
      defaultManeuverEN = "branch right"
    case .straight:
      defaultManeuverJA = "分岐せず"
      defaultManeuverZH = "不要分岔"
      defaultManeuverEN = "continue straight"
    }
    let resolvedManeuverJA = maneuverJA ?? defaultManeuverJA
    let resolvedManeuverZH = maneuverZH ?? defaultManeuverZH
    let resolvedManeuverEN = maneuverEN ?? defaultManeuverEN
    return ShutoJunctionMovementDefinition(
      id: id,
      networkSnapshotID: "shuto-official-2026-07-29-osm-2026-08-04",
      junctionID: junctionID,
      junctionNodeID: junctionNodeID,
      incomingEdgeID: incomingEdgeID,
      outgoingEdgeID: outgoingEdgeID,
      incomingRouteID: incomingRouteID,
      incomingDirectionJA: incomingDirectionJA,
      outgoingRouteID: outgoingRouteID,
      outgoingDirectionJA: outgoingDirectionJA,
      coveredFollowingDecisionEdgeIDs: coveredFollowingDecisionEdgeIDs,
      branchSide: branchSide,
      japaneseSignText: japaneseSignText,
      routeShields: routeShields,
      laneGuidanceState: .notReleased,
      localizedJunctionNames: [
        .japanese: junctionNameJA,
        .simplifiedChinese: junctionNameZH,
        .english: junctionNameEN,
      ],
      localizedContent: [
        .japanese: LocalizedGuidanceContent(
          displayText: "\(resolvedManeuverJA)、\(destinationJA)へ",
          spokenText:
            "\(junctionNameJA)では\(resolvedManeuverJA)、\(destinationJA)へ進んでください",
          spokenForms: [destinationJA: destinationJA],
          preservedJapaneseSignText: japaneseSignText
        ),
        .simplifiedChinese: LocalizedGuidanceContent(
          displayText: "\(resolvedManeuverZH)，驶往 \(destinationZH)",
          spokenText:
            "在\(junctionNameZH)\(resolvedManeuverZH)，驶往 \(destinationZH)",
          spokenForms: [destinationZH: destinationZH],
          preservedJapaneseSignText: japaneseSignText
        ),
        .english: LocalizedGuidanceContent(
          displayText:
            "\(resolvedManeuverEN.capitalized) for \(destinationEN)",
          spokenText:
            "At \(junctionNameEN), \(resolvedManeuverEN) for \(destinationEN)",
          spokenForms: [destinationEN: destinationEN],
          preservedJapaneseSignText: japaneseSignText
        ),
      ],
      commitTriggerDistanceMeters: commitTriggerDistanceMeters,
      checkedAt: "2026-08-15",
      expectedJunctionDetailSHA256: expectedJunctionDetailSHA256,
      sources: [
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/jct/"
        )
      ] + additionalSources.map { ShutoJunctionGuidanceSource(url: $0) }
        + [
          ShutoJunctionGuidanceSource(
            url: officialDetailReference,
            contentSHA256: expectedJunctionDetailSHA256
          )
        ]
    )
  }

  public static let released: [ShutoJunctionMovementDefinition] = [
    c2InnerMovement(
      id: "shuto.jct.ohashi.c2-inner-stays-on-c2",
      junctionID: "shuto.jct.jct_ohashi",
      junctionNodeID: 7_549_622_953,
      incomingEdgeID: "osm.80581127.78.forward",
      outgoingEdgeID: "osm.331692348.0.forward",
      branchSide: .left,
      japaneseSignText: "湾岸線",
      routeShields: ["C2"],
      junctionNameJA: "大橋JCT",
      junctionNameZH: "大桥 JCT",
      junctionNameEN: "Ohashi JCT",
      destinationJA: "C2 内回り",
      destinationZH: "C2 内环",
      destinationEN: "the C2 Inner Loop",
      expectedJunctionDetailSHA256:
        "5f27a01a763abd067d5bbd9108a6cd19"
        + "368a31492b779f57cd045d5053e4dcaa",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_ohashi",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/branch/",
        "https://www.shutoko.jp/use/network/map/route-c2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.ohashi.3-inbound-stays-on-3",
      junctionID: "shuto.jct.jct_ohashi",
      junctionNodeID: 927_641_089,
      incomingEdgeID: "osm.254992124.8.forward",
      outgoingEdgeID: "osm.254992124.9.forward",
      incomingRouteID: "3",
      incomingDirectionJA: "上り",
      outgoingRouteID: "3",
      outgoingDirectionJA: "上り",
      branchSide: .straight,
      japaneseSignText: "渋谷・都心環状",
      routeShields: ["3", "C1"],
      junctionNameJA: "大橋JCT",
      junctionNameZH: "大桥 JCT",
      junctionNameEN: "Ohashi JCT",
      destinationJA: "3号渋谷線 渋谷・都心環状方面",
      destinationZH: "3号涩谷线涩谷、都心环状方向",
      destinationEN:
        "Route 3 toward Shibuya and the Inner Circular Route",
      expectedJunctionDetailSHA256:
        "5f27a01a763abd067d5bbd9108a6cd19"
        + "368a31492b779f57cd045d5053e4dcaa",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_ohashi",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-3/"
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.ohashi.3-inbound-to-c2",
      junctionID: "shuto.jct.jct_ohashi",
      junctionNodeID: 927_641_089,
      incomingEdgeID: "osm.254992124.8.forward",
      outgoingEdgeID: "osm.78334077.0.forward",
      incomingRouteID: "3",
      incomingDirectionJA: "上り",
      outgoingRouteID: "C2",
      outgoingDirectionJA: "内回り",
      branchSide: .right,
      japaneseSignText: "湾岸線・東北道",
      routeShields: ["C2", "B", "E4"],
      junctionNameJA: "大橋JCT",
      junctionNameZH: "大桥 JCT",
      junctionNameEN: "Ohashi JCT",
      destinationJA: "C2 湾岸線・東北道方面",
      destinationZH: "C2 湾岸线、东北自动车道方向",
      destinationEN:
        "C2 toward the Bayshore Route and Tohoku Expressway",
      expectedJunctionDetailSHA256:
        "5f27a01a763abd067d5bbd9108a6cd19"
        + "368a31492b779f57cd045d5053e4dcaa",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_ohashi",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-3/",
        "https://www.shutoko.jp/use/network/map/route-c2/",
      ]
    ),
    c2InnerMovement(
      id: "shuto.jct.ohashi.c2-inner-to-3",
      junctionID: "shuto.jct.jct_ohashi",
      junctionNodeID: 7_549_622_953,
      incomingEdgeID: "osm.80581127.78.forward",
      outgoingEdgeID: "osm.331922702.0.forward",
      branchSide: .right,
      japaneseSignText: "都心環状・東名",
      routeShields: ["3", "C1", "E1"],
      junctionNameJA: "大橋JCT",
      junctionNameZH: "大桥 JCT",
      junctionNameEN: "Ohashi JCT",
      destinationJA: "3号渋谷線 都心環状・東名方面",
      destinationZH: "3号涩谷线都心环状、东名方向",
      destinationEN:
        "Route 3 toward the Inner Circular Route and Tomei Expressway",
      expectedJunctionDetailSHA256:
        "5f27a01a763abd067d5bbd9108a6cd19"
        + "368a31492b779f57cd045d5053e4dcaa",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_ohashi",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c2/",
        "https://www.shutoko.jp/use/network/map/route-3/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.ohashi.c2-outer-stays-on-c2",
      junctionID: "shuto.jct.jct_ohashi",
      junctionNodeID: 3_387_909_708,
      incomingEdgeID: "osm.772511247.10.forward",
      outgoingEdgeID: "osm.331922711.0.forward",
      incomingRouteID: "C2",
      incomingDirectionJA: "外回り",
      outgoingRouteID: "C2",
      outgoingDirectionJA: "外回り",
      branchSide: .straight,
      japaneseSignText: "中央道・東北道",
      routeShields: ["C2", "4", "5", "E20", "E4"],
      junctionNameJA: "大橋JCT",
      junctionNameZH: "大桥 JCT",
      junctionNameEN: "Ohashi JCT",
      destinationJA: "C2 外回り 中央道・東北道方面",
      destinationZH: "C2 外环中央自动车道、东北自动车道方向",
      destinationEN:
        "the C2 Outer Loop toward the Chuo and Tohoku Expressways",
      expectedJunctionDetailSHA256:
        "5f27a01a763abd067d5bbd9108a6cd19"
        + "368a31492b779f57cd045d5053e4dcaa",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_ohashi",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c2/"
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.ohashi.c2-outer-to-3",
      junctionID: "shuto.jct.jct_ohashi",
      junctionNodeID: 3_387_909_708,
      incomingEdgeID: "osm.772511247.10.forward",
      outgoingEdgeID: "osm.331922695.0.forward",
      incomingRouteID: "C2",
      incomingDirectionJA: "外回り",
      outgoingRouteID: "C2",
      outgoingDirectionJA: "外回り",
      branchSide: .left,
      japaneseSignText: "都心環状・東名",
      routeShields: ["3", "C1", "E1"],
      junctionNameJA: "大橋JCT",
      junctionNameZH: "大桥 JCT",
      junctionNameEN: "Ohashi JCT",
      destinationJA: "3号渋谷線 都心環状・東名方面",
      destinationZH: "3号涩谷线都心环状、东名方向",
      destinationEN:
        "Route 3 toward the Inner Circular Route and Tomei Expressway",
      expectedJunctionDetailSHA256:
        "5f27a01a763abd067d5bbd9108a6cd19"
        + "368a31492b779f57cd045d5053e4dcaa",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_ohashi",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c2/",
        "https://www.shutoko.jp/use/network/map/route-3/",
      ]
    ),
    c2InnerMovement(
      id: "shuto.jct.oi.c2-inner-to-b-eastbound",
      junctionID: "shuto.jct.jct_oi",
      junctionNodeID: 3_387_909_450,
      incomingEdgeID: "osm.331692344.2.forward",
      outgoingEdgeID: "osm.1308572351.0.forward",
      outgoingRouteID: "B",
      outgoingDirectionJA: "東行き",
      branchSide: .left,
      japaneseSignText: "東関東道",
      routeShields: ["B"],
      junctionNameJA: "大井JCT",
      junctionNameZH: "大井 JCT",
      junctionNameEN: "Oi JCT",
      destinationJA: "湾岸線 東行き",
      destinationZH: "湾岸线东行方向",
      destinationEN: "the Bayshore Route eastbound",
      expectedJunctionDetailSHA256:
        "4bfe3cb6117273ec547a62872b971a87f"
        + "cc944fff70b3267022888612aacfc2b",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_oi",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/branch/",
        "https://www.shutoko.jp/use/network/map/route-b/",
        "https://www.shutoko.jp/use/network/map/route-c2/",
      ]
    ),
    c2InnerMovement(
      id: "shuto.jct.kasai.b-eastbound-to-c2-inner",
      junctionID: "shuto.jct.jct_kasai",
      junctionNodeID: 31_330_103,
      incomingEdgeID: "osm.888066402.7.forward",
      outgoingEdgeID: "osm.888066403.0.forward",
      incomingRouteID: "B",
      incomingDirectionJA: "東行き",
      branchSide: .left,
      japaneseSignText: "東北道・常磐道",
      routeShields: ["C2", "E4", "E6"],
      junctionNameJA: "葛西JCT",
      junctionNameZH: "葛西 JCT",
      junctionNameEN: "Kasai JCT",
      destinationJA: "C2 内回り",
      destinationZH: "C2 内环",
      destinationEN: "the C2 Inner Loop",
      expectedJunctionDetailSHA256:
        "5e52b43abc96875472405c2fe5c2ca49"
        + "2946356ac0c86460f1610051289aa7b2",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_kasai",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-b/",
        "https://www.shutoko.jp/use/network/map/route-c2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.komatsugawa.c2-outer-stays-on-c2",
      junctionID: "shuto.jct.jct_komatsugawa",
      junctionNodeID: 370_270_524,
      incomingEdgeID: "osm.184872023.41.forward",
      outgoingEdgeID: "osm.184872023.42.forward",
      incomingRouteID: "C2",
      incomingDirectionJA: "外回り",
      outgoingRouteID: "C2",
      outgoingDirectionJA: "外回り",
      branchSide: .straight,
      japaneseSignText: "湾岸線・東関東道",
      routeShields: ["C2", "B", "E51"],
      junctionNameJA: "小松川JCT",
      junctionNameZH: "小松川 JCT",
      junctionNameEN: "Komatsugawa JCT",
      destinationJA: "C2 外回り 湾岸線・東関東道方面",
      destinationZH: "C2 外环湾岸线、东关东自动车道方向",
      destinationEN:
        "the C2 Outer Loop toward the Bayshore Route and Higashi-Kanto Expressway",
      expectedJunctionDetailSHA256:
        "a5119a85526658f19dda55b445114dd2"
        + "b72a1ee0161a454b0f55712872c84abe",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_komatsugawa",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/branch_komatsugawa/",
        "https://www.shutoko.jp/use/network/map/route-c2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.komatsugawa.c2-outer-to-7-outbound",
      junctionID: "shuto.jct.jct_komatsugawa",
      junctionNodeID: 370_270_524,
      incomingEdgeID: "osm.184872023.41.forward",
      outgoingEdgeID: "osm.751177038.0.forward",
      incomingRouteID: "C2",
      incomingDirectionJA: "外回り",
      outgoingRouteID: "7",
      outgoingDirectionJA: "下り",
      branchSide: .left,
      japaneseSignText: "京葉道路・小松川",
      routeShields: ["7", "E14"],
      junctionNameJA: "小松川JCT",
      junctionNameZH: "小松川 JCT",
      junctionNameEN: "Komatsugawa JCT",
      destinationJA: "7号小松川線 京葉道路方面",
      destinationZH: "7号小松川线京叶道路方向",
      destinationEN: "Route 7 toward the Keiyo Road",
      expectedJunctionDetailSHA256:
        "a5119a85526658f19dda55b445114dd2"
        + "b72a1ee0161a454b0f55712872c84abe",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_komatsugawa",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/branch_komatsugawa/",
        "https://www.shutoko.jp/use/network/map/route-c2/",
        "https://www.shutoko.jp/use/network/map/route-7/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.komatsugawa.7-inbound-stays-on-7",
      junctionID: "shuto.jct.jct_komatsugawa",
      junctionNodeID: 600_726_158,
      incomingEdgeID: "osm.59338971.14.forward",
      outgoingEdgeID: "osm.59338971.15.forward",
      incomingRouteID: "7",
      incomingDirectionJA: "上り",
      outgoingRouteID: "7",
      outgoingDirectionJA: "上り",
      branchSide: .straight,
      japaneseSignText: "都心環状",
      routeShields: ["7", "6", "C1"],
      junctionNameJA: "小松川JCT",
      junctionNameZH: "小松川 JCT",
      junctionNameEN: "Komatsugawa JCT",
      destinationJA: "7号小松川線 都心環状方面",
      destinationZH: "7号小松川线都心环状方向",
      destinationEN: "Route 7 toward the Inner Circular Route",
      expectedJunctionDetailSHA256:
        "a5119a85526658f19dda55b445114dd2"
        + "b72a1ee0161a454b0f55712872c84abe",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_komatsugawa",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/branch_komatsugawa/",
        "https://www.shutoko.jp/use/network/map/route-7/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.komatsugawa.7-inbound-to-c2-inner",
      junctionID: "shuto.jct.jct_komatsugawa",
      junctionNodeID: 600_726_158,
      incomingEdgeID: "osm.59338971.14.forward",
      outgoingEdgeID: "osm.751177037.0.forward",
      incomingRouteID: "7",
      incomingDirectionJA: "上り",
      outgoingRouteID: "C2",
      outgoingDirectionJA: "内回り",
      branchSide: .left,
      japaneseSignText: "東北道・常磐道",
      routeShields: ["C2", "E4", "E6"],
      junctionNameJA: "小松川JCT",
      junctionNameZH: "小松川 JCT",
      junctionNameEN: "Komatsugawa JCT",
      destinationJA: "C2 内回り 東北道・常磐道方面",
      destinationZH: "C2 内环东北自动车道、常磐自动车道方向",
      destinationEN:
        "the C2 Inner Loop toward the Tohoku and Joban Expressways",
      expectedJunctionDetailSHA256:
        "a5119a85526658f19dda55b445114dd2"
        + "b72a1ee0161a454b0f55712872c84abe",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_komatsugawa",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/branch_komatsugawa/",
        "https://www.shutoko.jp/use/network/map/route-c2/",
        "https://www.shutoko.jp/use/network/map/route-7/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.horikiri.c2-inner-toward-kosuge",
      junctionID: "shuto.jct.jct_kosugehorikiri_20180404",
      junctionNodeID: 559_445_920,
      incomingEdgeID: "osm.44422827.8.forward",
      outgoingEdgeID: "osm.44422827.9.forward",
      incomingRouteID: "C2",
      incomingDirectionJA: "内回り",
      outgoingRouteID: "C2",
      outgoingDirectionJA: "内回り",
      branchSide: .straight,
      japaneseSignText: "東北道・常磐道",
      routeShields: ["C2", "E4", "6", "E6"],
      junctionNameJA: "小菅JCT・堀切JCT",
      junctionNameZH: "小菅 JCT・堀切 JCT",
      junctionNameEN: "Kosuge and Horikiri Junctions",
      destinationJA: "小菅JCT 東北道・常磐道方面",
      destinationZH: "小菅 JCT 东北自动车道、常磐自动车道方向",
      destinationEN:
        "Kosuge Junction for the Tohoku or Joban Expressway",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "3beba3e408064642b7641cfbac692f1c"
        + "1f3fec6a0bce421e62c226c1ee6cf695",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/"
        + "jct_kosugehorikiri_20180404",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/fourlanes/",
        "https://www.shutoko.jp/use/network/map/route-c2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.horikiri.c2-inner-to-6-inbound",
      junctionID: "shuto.jct.jct_kosugehorikiri_20180404",
      junctionNodeID: 559_445_920,
      incomingEdgeID: "osm.44422827.8.forward",
      outgoingEdgeID: "osm.44422825.0.forward",
      incomingRouteID: "C2",
      incomingDirectionJA: "内回り",
      outgoingRouteID: "6_MUKOJIMA",
      outgoingDirectionJA: "上り",
      branchSide: .left,
      japaneseSignText: "銀座",
      routeShields: ["6", "C1"],
      junctionNameJA: "小菅JCT・堀切JCT",
      junctionNameZH: "小菅 JCT・堀切 JCT",
      junctionNameEN: "Kosuge and Horikiri Junctions",
      destinationJA: "6号向島線 銀座方面",
      destinationZH: "6号向岛线银座方向",
      destinationEN: "Route 6 toward Ginza",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "3beba3e408064642b7641cfbac692f1c"
        + "1f3fec6a0bce421e62c226c1ee6cf695",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/"
        + "jct_kosugehorikiri_20180404",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/fourlanes/",
        "https://www.shutoko.jp/use/network/map/route-6/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.kosuge.c2-inner-stays-on-c2",
      junctionID: "shuto.jct.jct_kosugehorikiri_20180404",
      junctionNodeID: 309_692_515,
      incomingEdgeID: "osm.44130134.12.forward",
      outgoingEdgeID: "osm.28194807.0.forward",
      incomingRouteID: "C2",
      incomingDirectionJA: "内回り",
      outgoingRouteID: "C2",
      outgoingDirectionJA: "内回り",
      branchSide: .left,
      maneuverJA: "左方向を保ち",
      maneuverZH: "保持左侧",
      maneuverEN: "keep left",
      japaneseSignText: "東北道・大宮",
      routeShields: ["C2", "E4", "S1"],
      junctionNameJA: "小菅JCT・堀切JCT",
      junctionNameZH: "小菅 JCT・堀切 JCT",
      junctionNameEN: "Kosuge and Horikiri Junctions",
      destinationJA: "C2 内回り 東北道・大宮方面",
      destinationZH: "C2 内环东北自动车道、大宫方向",
      destinationEN:
        "the C2 Inner Loop toward the Tohoku Expressway and Omiya",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "3beba3e408064642b7641cfbac692f1c"
        + "1f3fec6a0bce421e62c226c1ee6cf695",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/"
        + "jct_kosugehorikiri_20180404",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/fourlanes/",
        "https://www.shutoko.jp/use/network/map/route-c2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.kosuge.c2-inner-to-6-outbound",
      junctionID: "shuto.jct.jct_kosugehorikiri_20180404",
      junctionNodeID: 309_692_515,
      incomingEdgeID: "osm.44130134.12.forward",
      outgoingEdgeID: "osm.43992332.0.forward",
      incomingRouteID: "C2",
      incomingDirectionJA: "内回り",
      outgoingRouteID: "6_MISATO",
      outgoingDirectionJA: "下り",
      branchSide: .right,
      maneuverJA: "右方向を保ち",
      maneuverZH: "保持右侧",
      maneuverEN: "keep right",
      japaneseSignText: "常磐道・三郷",
      routeShields: ["6", "E6"],
      junctionNameJA: "小菅JCT・堀切JCT",
      junctionNameZH: "小菅 JCT・堀切 JCT",
      junctionNameEN: "Kosuge and Horikiri Junctions",
      destinationJA: "6号三郷線 常磐道・三郷方面",
      destinationZH: "6号三乡线常磐自动车道、三乡方向",
      destinationEN: "Route 6 toward the Joban Expressway and Misato",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "3beba3e408064642b7641cfbac692f1c"
        + "1f3fec6a0bce421e62c226c1ee6cf695",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/"
        + "jct_kosugehorikiri_20180404",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/fourlanes/",
        "https://www.shutoko.jp/use/network/map/route-6/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.horikiri.c2-outer-to-6-inbound",
      junctionID: "shuto.jct.jct_kosugehorikiri_20180404",
      junctionNodeID: 370_270_206,
      incomingEdgeID: "osm.32898851.9.forward",
      outgoingEdgeID: "osm.28188273.0.forward",
      incomingRouteID: "C2",
      incomingDirectionJA: "外回り",
      outgoingRouteID: "6_MUKOJIMA",
      outgoingDirectionJA: "上り",
      branchSide: .right,
      japaneseSignText: "銀座",
      routeShields: ["6", "C1"],
      junctionNameJA: "小菅JCT・堀切JCT",
      junctionNameZH: "小菅 JCT・堀切 JCT",
      junctionNameEN: "Kosuge and Horikiri Junctions",
      destinationJA: "6号向島線 銀座方面",
      destinationZH: "6号向岛线银座方向",
      destinationEN: "Route 6 toward Ginza",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "3beba3e408064642b7641cfbac692f1c"
        + "1f3fec6a0bce421e62c226c1ee6cf695",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/"
        + "jct_kosugehorikiri_20180404",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/fourlanes/",
        "https://www.shutoko.jp/use/network/map/route-6/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.horikiri.c2-outer-stays-on-c2",
      junctionID: "shuto.jct.jct_kosugehorikiri_20180404",
      junctionNodeID: 370_270_206,
      incomingEdgeID: "osm.32898851.9.forward",
      outgoingEdgeID: "osm.44130133.0.forward",
      incomingRouteID: "C2",
      incomingDirectionJA: "外回り",
      outgoingRouteID: "C2",
      outgoingDirectionJA: "外回り",
      branchSide: .left,
      japaneseSignText: "湾岸線・東関東道",
      routeShields: ["C2", "B", "E51", "7"],
      junctionNameJA: "小菅JCT・堀切JCT",
      junctionNameZH: "小菅 JCT・堀切 JCT",
      junctionNameEN: "Kosuge and Horikiri Junctions",
      destinationJA: "C2 外回り 湾岸線・東関東道方面",
      destinationZH: "C2 外环湾岸线、东关东自动车道方向",
      destinationEN:
        "the C2 Outer Loop toward the Bayshore Route and Higashi-Kanto Expressway",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "3beba3e408064642b7641cfbac692f1c"
        + "1f3fec6a0bce421e62c226c1ee6cf695",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/"
        + "jct_kosugehorikiri_20180404",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/fourlanes/",
        "https://www.shutoko.jp/use/network/map/route-c2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.kosuge.c2-outer-to-6-outbound",
      junctionID: "shuto.jct.jct_kosugehorikiri_20180404",
      junctionNodeID: 309_609_006,
      incomingEdgeID: "osm.28194805.12.forward",
      outgoingEdgeID: "osm.28188270.0.forward",
      incomingRouteID: "C2",
      incomingDirectionJA: "外回り",
      outgoingRouteID: "6_MISATO",
      outgoingDirectionJA: "下り",
      branchSide: .left,
      japaneseSignText: "常磐道・三郷",
      routeShields: ["6", "E6"],
      junctionNameJA: "小菅JCT・堀切JCT",
      junctionNameZH: "小菅 JCT・堀切 JCT",
      junctionNameEN: "Kosuge and Horikiri Junctions",
      destinationJA: "6号三郷線 常磐道・三郷方面",
      destinationZH: "6号三乡线常磐自动车道、三乡方向",
      destinationEN: "Route 6 toward the Joban Expressway and Misato",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "3beba3e408064642b7641cfbac692f1c"
        + "1f3fec6a0bce421e62c226c1ee6cf695",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/"
        + "jct_kosugehorikiri_20180404",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/fourlanes/",
        "https://www.shutoko.jp/use/network/map/route-6/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.kosuge.c2-outer-stays-on-c2",
      junctionID: "shuto.jct.jct_kosugehorikiri_20180404",
      junctionNodeID: 309_609_006,
      incomingEdgeID: "osm.28194805.12.forward",
      outgoingEdgeID: "osm.28194805.13.forward",
      incomingRouteID: "C2",
      incomingDirectionJA: "外回り",
      outgoingRouteID: "C2",
      outgoingDirectionJA: "外回り",
      branchSide: .straight,
      japaneseSignText: "湾岸線・東関東道",
      routeShields: ["C2", "B", "E51", "7"],
      junctionNameJA: "小菅JCT・堀切JCT",
      junctionNameZH: "小菅 JCT・堀切 JCT",
      junctionNameEN: "Kosuge and Horikiri Junctions",
      destinationJA: "C2 外回り 湾岸線・東関東道方面",
      destinationZH: "C2 外环湾岸线、东关东自动车道方向",
      destinationEN:
        "the C2 Outer Loop toward the Bayshore Route and Higashi-Kanto Expressway",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "3beba3e408064642b7641cfbac692f1c"
        + "1f3fec6a0bce421e62c226c1ee6cf695",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/"
        + "jct_kosugehorikiri_20180404",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/fourlanes/",
        "https://www.shutoko.jp/use/network/map/route-c2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.kosuge.6-inbound-toward-horikiri",
      junctionID: "shuto.jct.jct_kosugehorikiri_20180404",
      junctionNodeID: 559_445_943,
      incomingEdgeID: "osm.250490207.15.forward",
      outgoingEdgeID: "osm.250490207.16.forward",
      incomingRouteID: "6_MISATO",
      incomingDirectionJA: "上り",
      outgoingRouteID: "6_MISATO",
      outgoingDirectionJA: "上り",
      branchSide: .straight,
      japaneseSignText: "湾岸線・都心環状",
      routeShields: ["C2", "B", "6", "C1"],
      junctionNameJA: "小菅JCT・堀切JCT",
      junctionNameZH: "小菅 JCT・堀切 JCT",
      junctionNameEN: "Kosuge and Horikiri Junctions",
      destinationJA: "堀切JCT 湾岸線・都心環状方面",
      destinationZH: "堀切 JCT 湾岸线、都心环状线方向",
      destinationEN:
        "Horikiri Junction for the Bayshore or Inner Circular Route",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "3beba3e408064642b7641cfbac692f1c"
        + "1f3fec6a0bce421e62c226c1ee6cf695",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/"
        + "jct_kosugehorikiri_20180404",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/fourlanes/",
        "https://www.shutoko.jp/use/network/map/route-6/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.kosuge.6-inbound-to-c2-inner",
      junctionID: "shuto.jct.jct_kosugehorikiri_20180404",
      junctionNodeID: 559_445_943,
      incomingEdgeID: "osm.250490207.15.forward",
      outgoingEdgeID: "osm.31090753.0.forward",
      incomingRouteID: "6_MISATO",
      incomingDirectionJA: "上り",
      outgoingRouteID: "C2",
      outgoingDirectionJA: "内回り",
      branchSide: .right,
      japaneseSignText: "東名・中央道",
      routeShields: ["C2", "E1", "5", "E20"],
      junctionNameJA: "小菅JCT・堀切JCT",
      junctionNameZH: "小菅 JCT・堀切 JCT",
      junctionNameEN: "Kosuge and Horikiri Junctions",
      destinationJA: "C2 内回り 東名・中央道方面",
      destinationZH: "C2 内环东名高速、中央自动车道方向",
      destinationEN:
        "the C2 Inner Loop toward the Tomei and Chuo Expressways",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "3beba3e408064642b7641cfbac692f1c"
        + "1f3fec6a0bce421e62c226c1ee6cf695",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/"
        + "jct_kosugehorikiri_20180404",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/fourlanes/",
        "https://www.shutoko.jp/use/network/map/route-c2/",
        "https://www.shutoko.jp/use/network/map/route-6/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.horikiri.6-outbound-to-c2-outer",
      junctionID: "shuto.jct.jct_kosugehorikiri_20180404",
      junctionNodeID: 564_683_280,
      incomingEdgeID: "osm.817278024.142.forward",
      outgoingEdgeID: "osm.28188274.0.forward",
      incomingRouteID: "6_MUKOJIMA",
      incomingDirectionJA: "下り",
      outgoingRouteID: "C2",
      outgoingDirectionJA: "外回り",
      branchSide: .right,
      japaneseSignText: "湾岸線・東関東道",
      routeShields: ["C2", "B", "E51", "7"],
      junctionNameJA: "小菅JCT・堀切JCT",
      junctionNameZH: "小菅 JCT・堀切 JCT",
      junctionNameEN: "Kosuge and Horikiri Junctions",
      destinationJA: "C2 外回り 湾岸線・東関東道方面",
      destinationZH: "C2 外环湾岸线、东关东自动车道方向",
      destinationEN:
        "the C2 Outer Loop toward the Bayshore Route and Higashi-Kanto Expressway",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "3beba3e408064642b7641cfbac692f1c"
        + "1f3fec6a0bce421e62c226c1ee6cf695",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/"
        + "jct_kosugehorikiri_20180404",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/fourlanes/",
        "https://www.shutoko.jp/use/network/map/route-c2/",
        "https://www.shutoko.jp/use/network/map/route-6/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.horikiri.6-outbound-toward-kosuge",
      junctionID: "shuto.jct.jct_kosugehorikiri_20180404",
      junctionNodeID: 564_683_280,
      incomingEdgeID: "osm.817278024.142.forward",
      outgoingEdgeID: "osm.316265424.0.forward",
      incomingRouteID: "6_MUKOJIMA",
      incomingDirectionJA: "下り",
      outgoingRouteID: "C2",
      outgoingDirectionJA: "内回り",
      branchSide: .straight,
      japaneseSignText: "東北道・常磐道",
      routeShields: ["C2", "E4", "6", "E6"],
      junctionNameJA: "小菅JCT・堀切JCT",
      junctionNameZH: "小菅 JCT・堀切 JCT",
      junctionNameEN: "Kosuge and Horikiri Junctions",
      destinationJA: "小菅JCT 東北道・常磐道方面",
      destinationZH: "小菅 JCT 东北自动车道、常磐自动车道方向",
      destinationEN:
        "Kosuge Junction for the Tohoku or Joban Expressway",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "3beba3e408064642b7641cfbac692f1c"
        + "1f3fec6a0bce421e62c226c1ee6cf695",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/"
        + "jct_kosugehorikiri_20180404",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/fourlanes/",
        "https://www.shutoko.jp/use/network/map/route-c2/",
        "https://www.shutoko.jp/use/network/map/route-6/",
      ]
    ),
    c2InnerMovement(
      id: "shuto.jct.kohoku.c2-inner-stays-on-c2",
      junctionID: "shuto.jct.jct_kouhoku",
      junctionNodeID: 309_692_606,
      incomingEdgeID: "osm.44209394.5.forward",
      outgoingEdgeID: "osm.44180277.0.forward",
      branchSide: .left,
      japaneseSignText: "東池袋・東名",
      routeShields: ["C2"],
      junctionNameJA: "江北JCT",
      junctionNameZH: "江北 JCT",
      junctionNameEN: "Kohoku JCT",
      destinationJA: "C2 内回り",
      destinationZH: "C2 内环",
      destinationEN: "the C2 Inner Loop",
      expectedJunctionDetailSHA256:
        "d168d950ee904e51e2332fb9e6c94cb9"
        + "ffad6ef825b01df9e917d1db8e372d81",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_kouhoku",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c2/"
      ]
    ),
    c2InnerMovement(
      id: "shuto.jct.kohoku.c2-inner-to-s1-outbound",
      junctionID: "shuto.jct.jct_kouhoku",
      junctionNodeID: 309_692_606,
      incomingEdgeID: "osm.44209394.5.forward",
      outgoingEdgeID: "osm.44179919.0.forward",
      outgoingRouteID: "S1",
      outgoingDirectionJA: "下り",
      branchSide: .straight,
      japaneseSignText: "東北道",
      routeShields: ["S1", "E4"],
      junctionNameJA: "江北JCT",
      junctionNameZH: "江北 JCT",
      junctionNameEN: "Kohoku JCT",
      destinationJA: "S1 川口線 下り",
      destinationZH: "S1 川口线下行方向",
      destinationEN: "Route S1 outbound",
      expectedJunctionDetailSHA256:
        "d168d950ee904e51e2332fb9e6c94cb9"
        + "ffad6ef825b01df9e917d1db8e372d81",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_kouhoku",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c2/",
        "https://www.shutoko.jp/use/network/map/route-s1/",
      ]
    ),
    c2InnerMovement(
      id: "shuto.jct.itabashi.c2-inner-keeps-right-through-kumanocho",
      junctionID: "shuto.jct.jct_itabashi_20180404",
      junctionNodeID: 308_930_039,
      incomingEdgeID: "osm.156344609.48.forward",
      outgoingEdgeID: "osm.28195150.0.forward",
      coveredFollowingDecisionEdgeIDs: [
        "osm.28195150.1.forward",
        "osm.28195150.2.forward",
        "osm.28195150.3.forward",
        "osm.28195150.4.forward",
        "osm.28195150.5.forward",
        "osm.28195150.6.forward",
        "osm.28195150.7.forward",
        "osm.28195150.8.forward",
        "osm.28195150.9.forward",
        "osm.28195150.10.forward",
        "osm.28195150.11.forward",
        "osm.28195150.12.forward",
        "osm.28195150.13.forward",
        "osm.28195150.14.forward",
        "osm.28195150.15.forward",
        "osm.28195150.16.forward",
        "osm.28195150.17.forward",
        "osm.28195150.18.forward",
        "osm.28195150.19.forward",
        "osm.28195150.20.forward",
        "osm.28195150.21.forward",
        "osm.28195150.22.forward",
        "osm.28195150.23.forward",
        "osm.28195150.24.forward",
        "osm.28195150.25.forward",
        "osm.28195150.26.forward",
        "osm.28195150.27.forward",
        "osm.28195150.28.forward",
        "osm.28195150.29.forward",
        "osm.28195150.30.forward",
        "osm.28195150.31.forward",
        "osm.28195150.32.forward",
        "osm.28195150.33.forward",
        "osm.28195150.34.forward",
        "osm.28195150.35.forward",
        "osm.28127112.0.forward",
        "osm.28127112.1.forward",
        "osm.28127112.2.forward",
        "osm.28127112.3.forward",
        "osm.28127112.4.forward",
        "osm.28127112.5.forward",
        "osm.28127112.6.forward",
        "osm.28127112.7.forward",
        "osm.28127112.8.forward",
        "osm.28127112.9.forward",
        "osm.28127112.10.forward",
        "osm.28127112.11.forward",
        "osm.28127112.12.forward",
        "osm.28126649.0.forward",
      ],
      branchSide: .right,
      japaneseSignText: "中央道・東名",
      routeShields: ["C2", "E20", "E1"],
      junctionNameJA: "板橋JCT・熊野町JCT",
      junctionNameZH: "板桥 JCT・熊野町 JCT",
      junctionNameEN: "Itabashi and Kumanocho Junctions",
      destinationJA: "C2 内回り",
      destinationZH: "C2 内环",
      destinationEN: "the C2 Inner Loop",
      expectedJunctionDetailSHA256:
        "4c1cb61e312e4b0d70eed1eb542d48c0"
        + "19de9e605d354cd85fdd7800babc80ba",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/"
        + "jct_itabashi_20180404",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/fourlanes/",
        "https://www.shutoko.jp/use/network/map/route-c2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.itabashi.c2-inner-to-5-outbound",
      junctionID: "shuto.jct.jct_itabashi_20180404",
      junctionNodeID: 308_930_039,
      incomingEdgeID: "osm.156344609.48.forward",
      outgoingEdgeID: "osm.28195148.0.forward",
      incomingRouteID: "C2",
      incomingDirectionJA: "内回り",
      outgoingRouteID: "5",
      outgoingDirectionJA: "下り",
      branchSide: .left,
      japaneseSignText: "大宮・関越道",
      routeShields: ["5", "E17"],
      junctionNameJA: "板橋JCT・熊野町JCT",
      junctionNameZH: "板桥 JCT・熊野町 JCT",
      junctionNameEN: "Itabashi and Kumanocho Junctions",
      destinationJA: "5 池袋線 下り",
      destinationZH: "5 池袋线下行方向",
      destinationEN: "Route 5 outbound",
      expectedJunctionDetailSHA256:
        "4c1cb61e312e4b0d70eed1eb542d48c0"
        + "19de9e605d354cd85fdd7800babc80ba",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/"
        + "jct_itabashi_20180404",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/fourlanes/",
        "https://www.shutoko.jp/use/network/map/route-5/",
        "https://www.shutoko.jp/use/network/map/route-c2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.kumanocho.c2-inner-to-5-inbound",
      junctionID: "shuto.jct.jct_itabashi_20180404",
      junctionNodeID: 252_174_760,
      incomingEdgeID: "osm.28127112.12.forward",
      outgoingEdgeID: "osm.23681223.0.forward",
      incomingRouteID: "C2",
      incomingDirectionJA: "内回り",
      outgoingRouteID: "5",
      outgoingDirectionJA: "上り",
      branchSide: .left,
      japaneseSignText: "東池袋・都心環状",
      routeShields: ["5"],
      junctionNameJA: "板橋JCT・熊野町JCT",
      junctionNameZH: "板桥 JCT・熊野町 JCT",
      junctionNameEN: "Itabashi and Kumanocho Junctions",
      destinationJA: "5 池袋線 上り",
      destinationZH: "5 池袋线上行方向",
      destinationEN: "Route 5 inbound",
      expectedJunctionDetailSHA256:
        "4c1cb61e312e4b0d70eed1eb542d48c0"
        + "19de9e605d354cd85fdd7800babc80ba",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/"
        + "jct_itabashi_20180404",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/fourlanes/",
        "https://www.shutoko.jp/use/network/map/route-5/",
        "https://www.shutoko.jp/use/network/map/route-c2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.kumanocho.c2-inner-stays-on-c2",
      junctionID: "shuto.jct.jct_itabashi_20180404",
      junctionNodeID: 252_174_760,
      incomingEdgeID: "osm.28127112.12.forward",
      outgoingEdgeID: "osm.28126649.0.forward",
      incomingRouteID: "C2",
      incomingDirectionJA: "内回り",
      outgoingRouteID: "C2",
      outgoingDirectionJA: "内回り",
      branchSide: .right,
      japaneseSignText: "中央道・東名",
      routeShields: ["C2", "E20", "E1"],
      junctionNameJA: "板橋JCT・熊野町JCT",
      junctionNameZH: "板桥 JCT・熊野町 JCT",
      junctionNameEN: "Itabashi and Kumanocho Junctions",
      destinationJA: "C2 内回り",
      destinationZH: "C2 内环",
      destinationEN: "the C2 Inner Loop",
      expectedJunctionDetailSHA256:
        "4c1cb61e312e4b0d70eed1eb542d48c0"
        + "19de9e605d354cd85fdd7800babc80ba",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/"
        + "jct_itabashi_20180404",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/fourlanes/",
        "https://www.shutoko.jp/use/network/map/route-c2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.itabashi.c2-outer-to-5-outbound",
      junctionID: "shuto.jct.jct_itabashi_20180404",
      junctionNodeID: 263_988_109,
      incomingEdgeID: "osm.44291527.12.forward",
      outgoingEdgeID: "osm.22694126.0.forward",
      incomingRouteID: "C2",
      incomingDirectionJA: "外回り",
      outgoingRouteID: "5",
      outgoingDirectionJA: "下り",
      branchSide: .left,
      japaneseSignText: "大宮・関越道",
      routeShields: ["5", "E17"],
      junctionNameJA: "板橋JCT・熊野町JCT",
      junctionNameZH: "板桥 JCT・熊野町 JCT",
      junctionNameEN: "Itabashi and Kumanocho Junctions",
      destinationJA: "5 池袋線 下り",
      destinationZH: "5 池袋线下行方向",
      destinationEN: "Route 5 outbound",
      expectedJunctionDetailSHA256:
        "4c1cb61e312e4b0d70eed1eb542d48c0"
        + "19de9e605d354cd85fdd7800babc80ba",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/"
        + "jct_itabashi_20180404",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/fourlanes/",
        "https://www.shutoko.jp/use/network/map/route-5/",
        "https://www.shutoko.jp/use/network/map/route-c2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.itabashi.c2-outer-stays-on-c2",
      junctionID: "shuto.jct.jct_itabashi_20180404",
      junctionNodeID: 263_988_109,
      incomingEdgeID: "osm.44291527.12.forward",
      outgoingEdgeID: "osm.24334800.0.forward",
      incomingRouteID: "C2",
      incomingDirectionJA: "外回り",
      outgoingRouteID: "C2",
      outgoingDirectionJA: "外回り",
      branchSide: .right,
      japaneseSignText: "東北道・常磐道",
      routeShields: ["C2", "E4", "E6"],
      junctionNameJA: "板橋JCT・熊野町JCT",
      junctionNameZH: "板桥 JCT・熊野町 JCT",
      junctionNameEN: "Itabashi and Kumanocho Junctions",
      destinationJA: "C2 外回り",
      destinationZH: "C2 外环",
      destinationEN: "the C2 Outer Loop",
      expectedJunctionDetailSHA256:
        "4c1cb61e312e4b0d70eed1eb542d48c0"
        + "19de9e605d354cd85fdd7800babc80ba",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/"
        + "jct_itabashi_20180404",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/fourlanes/",
        "https://www.shutoko.jp/use/network/map/route-5/",
        "https://www.shutoko.jp/use/network/map/route-c2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.itabashi.5-inbound-to-c2-inner",
      junctionID: "shuto.jct.jct_itabashi_20180404",
      junctionNodeID: 562_825_892,
      incomingEdgeID: "osm.44353152.3.forward",
      outgoingEdgeID: "osm.182527890.0.forward",
      incomingRouteID: "5",
      incomingDirectionJA: "上り",
      outgoingRouteID: "C2",
      outgoingDirectionJA: "内回り",
      branchSide: .left,
      japaneseSignText: "常磐道・東関東道",
      routeShields: ["C2", "E6", "E51"],
      junctionNameJA: "板橋JCT・熊野町JCT",
      junctionNameZH: "板桥 JCT・熊野町 JCT",
      junctionNameEN: "Itabashi and Kumanocho Junctions",
      destinationJA: "C2 内回り",
      destinationZH: "C2 内环",
      destinationEN: "the C2 Inner Loop",
      expectedJunctionDetailSHA256:
        "4c1cb61e312e4b0d70eed1eb542d48c0"
        + "19de9e605d354cd85fdd7800babc80ba",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/"
        + "jct_itabashi_20180404",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/fourlanes/",
        "https://www.shutoko.jp/use/network/map/route-5/",
        "https://www.shutoko.jp/use/network/map/route-c2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.itabashi.5-inbound-stays-on-5",
      junctionID: "shuto.jct.jct_itabashi_20180404",
      junctionNodeID: 562_825_892,
      incomingEdgeID: "osm.44353152.3.forward",
      outgoingEdgeID: "osm.44353152.4.forward",
      incomingRouteID: "5",
      incomingDirectionJA: "上り",
      outgoingRouteID: "5",
      outgoingDirectionJA: "上り",
      branchSide: .straight,
      japaneseSignText: "都心環状・東名",
      routeShields: ["5", "E1"],
      junctionNameJA: "板橋JCT・熊野町JCT",
      junctionNameZH: "板桥 JCT・熊野町 JCT",
      junctionNameEN: "Itabashi and Kumanocho Junctions",
      destinationJA: "5 池袋線 上り",
      destinationZH: "5 池袋线上行方向",
      destinationEN: "Route 5 inbound",
      expectedJunctionDetailSHA256:
        "4c1cb61e312e4b0d70eed1eb542d48c0"
        + "19de9e605d354cd85fdd7800babc80ba",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/"
        + "jct_itabashi_20180404",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/fourlanes/",
        "https://www.shutoko.jp/use/network/map/route-5/",
        "https://www.shutoko.jp/use/network/map/route-c2/",
      ]
    ),
    c2InnerMovement(
      id: "shuto.jct.nishishinjuku.c2-inner-stays-on-c2",
      junctionID: "shuto.jct.jct_nishishinjuku",
      junctionNodeID: 308_925_199,
      incomingEdgeID: "osm.190617333.53.forward",
      outgoingEdgeID: "osm.190617333.54.forward",
      branchSide: .straight,
      japaneseSignText: "湾岸線",
      routeShields: ["C2"],
      junctionNameJA: "西新宿JCT",
      junctionNameZH: "西新宿 JCT",
      junctionNameEN: "Nishi-shinjuku JCT",
      destinationJA: "C2 内回り",
      destinationZH: "C2 内环",
      destinationEN: "the C2 Inner Loop",
      expectedJunctionDetailSHA256:
        "377261189835d54ed378c7c5487cebf6"
        + "c108a411449dad525dd975da6e9d1c20",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_nishishinjuku",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c2/"
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.nishishinjuku.4-inbound-to-c2",
      junctionID: "shuto.jct.jct_nishishinjuku",
      junctionNodeID: 267_805_268,
      incomingEdgeID: "osm.848042057.4.forward",
      outgoingEdgeID: "osm.26956960.0.forward",
      incomingRouteID: "4",
      incomingDirectionJA: "上り",
      outgoingRouteID: "4",
      outgoingDirectionJA: "上り",
      branchSide: .left,
      japaneseSignText: "湾岸線・東北道",
      routeShields: ["C2", "5", "E4"],
      junctionNameJA: "西新宿JCT",
      junctionNameZH: "西新宿 JCT",
      junctionNameEN: "Nishi-shinjuku JCT",
      destinationJA: "C2 湾岸線・東北道方面",
      destinationZH: "C2 湾岸线・东北道方向",
      destinationEN: "C2 toward the Bayshore Route and Tohoku Expressway",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "377261189835d54ed378c7c5487cebf6"
        + "c108a411449dad525dd975da6e9d1c20",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_nishishinjuku",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-4/",
        "https://www.shutoko.jp/use/network/map/route-c2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.nishishinjuku.4-inbound-stays-on-4",
      junctionID: "shuto.jct.jct_nishishinjuku",
      junctionNodeID: 267_805_268,
      incomingEdgeID: "osm.848042057.4.forward",
      outgoingEdgeID: "osm.848042056.0.forward",
      incomingRouteID: "4",
      incomingDirectionJA: "上り",
      outgoingRouteID: "4",
      outgoingDirectionJA: "上り",
      branchSide: .right,
      japaneseSignText: "新宿出口・都心環状",
      routeShields: ["4", "C1"],
      junctionNameJA: "西新宿JCT",
      junctionNameZH: "西新宿 JCT",
      junctionNameEN: "Nishi-shinjuku JCT",
      destinationJA: "4号新宿線 新宿出口・都心環状線方面",
      destinationZH: "4号新宿线 新宿出口・都心环状线方向",
      destinationEN: "Route 4 toward Shinjuku and the Inner Circular Route",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "377261189835d54ed378c7c5487cebf6"
        + "c108a411449dad525dd975da6e9d1c20",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_nishishinjuku",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-4/",
        "https://www.shutoko.jp/use/network/map/route-c1/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.nishishinjuku.c2-inner-to-4-outbound",
      junctionID: "shuto.jct.jct_nishishinjuku",
      junctionNodeID: 308_925_199,
      incomingEdgeID: "osm.190617333.53.forward",
      outgoingEdgeID: "osm.28127106.0.forward",
      incomingRouteID: "C2",
      incomingDirectionJA: "内回り",
      outgoingRouteID: "4",
      outgoingDirectionJA: "下り",
      branchSide: .right,
      japaneseSignText: "高井戸・中央道",
      routeShields: ["4", "E20"],
      junctionNameJA: "西新宿JCT",
      junctionNameZH: "西新宿 JCT",
      junctionNameEN: "Nishi-shinjuku JCT",
      destinationJA: "4号新宿線 高井戸・中央道方面",
      destinationZH: "4号新宿线 高井户・中央道方向",
      destinationEN: "Route 4 toward Takaido and the Chuo Expressway",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "377261189835d54ed378c7c5487cebf6"
        + "c108a411449dad525dd975da6e9d1c20",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_nishishinjuku",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-4/",
        "https://www.shutoko.jp/use/network/map/route-c2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.nishishinjuku.c2-outer-to-4-outbound",
      junctionID: "shuto.jct.jct_nishishinjuku",
      junctionNodeID: 3_851_809_274,
      incomingEdgeID: "osm.863812380.3.forward",
      outgoingEdgeID: "osm.381972984.0.forward",
      incomingRouteID: "C2",
      incomingDirectionJA: "外回り",
      outgoingRouteID: "4",
      outgoingDirectionJA: "下り",
      branchSide: .right,
      japaneseSignText: "高井戸・中央道",
      routeShields: ["4", "E20"],
      junctionNameJA: "西新宿JCT",
      junctionNameZH: "西新宿 JCT",
      junctionNameEN: "Nishi-shinjuku JCT",
      destinationJA: "4号新宿線 高井戸・中央道方面",
      destinationZH: "4号新宿线 高井户・中央道方向",
      destinationEN: "Route 4 toward Takaido and the Chuo Expressway",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "377261189835d54ed378c7c5487cebf6"
        + "c108a411449dad525dd975da6e9d1c20",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_nishishinjuku",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-4/",
        "https://www.shutoko.jp/use/network/map/route-c2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.nishishinjuku.c2-outer-stays-on-c2",
      junctionID: "shuto.jct.jct_nishishinjuku",
      junctionNodeID: 3_851_809_274,
      incomingEdgeID: "osm.863812380.3.forward",
      outgoingEdgeID: "osm.863812381.0.forward",
      incomingRouteID: "C2",
      incomingDirectionJA: "外回り",
      outgoingRouteID: "C2",
      outgoingDirectionJA: "外回り",
      branchSide: .straight,
      japaneseSignText: "西池袋・東北道",
      routeShields: ["C2", "5", "E4"],
      junctionNameJA: "西新宿JCT",
      junctionNameZH: "西新宿 JCT",
      junctionNameEN: "Nishi-shinjuku JCT",
      destinationJA: "C2 西池袋・東北道方面",
      destinationZH: "C2 西池袋・东北道方向",
      destinationEN: "C2 toward Nishi-ikebukuro and the Tohoku Expressway",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "377261189835d54ed378c7c5487cebf6"
        + "c108a411449dad525dd975da6e9d1c20",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_nishishinjuku",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-5/",
        "https://www.shutoko.jp/use/network/map/route-c2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.daikoku.b-westbound-to-k5-inbound",
      junctionID: "shuto.jct.jct_daikoku",
      junctionNodeID: 157_941_466,
      incomingEdgeID: "osm.1449791735.2.forward",
      outgoingEdgeID: "osm.15766920.0.forward",
      incomingRouteID: "B",
      incomingDirectionJA: "西行き",
      outgoingRouteID: "K5",
      outgoingDirectionJA: "上り",
      branchSide: .left,
      japaneseSignText: "東名",
      routeShields: ["E1", "K5", "K7"],
      junctionNameJA: "大黒JCT",
      junctionNameZH: "大黑 JCT",
      junctionNameEN: "Daikoku JCT",
      destinationJA: "K5 大黒線 東名方面",
      destinationZH: "K5 大黑线东名高速方向",
      destinationEN: "Route K5 toward the Tomei Expressway",
      expectedJunctionDetailSHA256:
        "4fcd99ab1e97a6a84f6c5c41e86c2b16"
        + "247f5acd1b8c34e1e2e5397cf3c004eb",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_daikoku",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-b/",
        "https://www.shutoko.jp/use/network/map/route-k5/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.namamugi.k5-inbound-to-k1-inbound",
      junctionID: "shuto.jct.jct_namamugi",
      junctionNodeID: 1_032_992_501,
      incomingEdgeID: "osm.32403899.42.forward",
      outgoingEdgeID: "osm.32403899.43.forward",
      incomingRouteID: "K5",
      incomingDirectionJA: "上り",
      outgoingRouteID: "K5",
      outgoingDirectionJA: "上り",
      coveredFollowingDecisionEdgeIDs: [
        "osm.32403899.44.forward",
        "osm.760553865.0.forward",
        "osm.32593083.0.forward",
        "osm.32593083.1.forward",
        "osm.32593083.2.forward",
        "osm.760542684.0.forward",
        "osm.760542684.1.forward",
        "osm.760542684.2.forward",
        "osm.760542684.3.forward",
        "osm.760542684.4.forward",
        "osm.760542684.5.forward",
        "osm.760542684.6.forward",
        "osm.760542684.7.forward",
        "osm.760542684.8.forward",
        "osm.760542684.9.forward",
        "osm.760542684.10.forward",
        "osm.760542684.11.forward",
        "osm.760542684.12.forward",
        "osm.760542684.13.forward",
        "osm.760542684.14.forward",
        "osm.760542684.15.forward",
        "osm.760542684.16.forward",
        "osm.760542684.17.forward",
        "osm.760542684.18.forward",
        "osm.760542684.19.forward",
        "osm.760542684.20.forward",
        "osm.760542684.21.forward",
        "osm.760542684.22.forward",
        "osm.760540203.0.forward",
        "osm.760540203.1.forward",
        "osm.760540203.2.forward",
      ],
      branchSide: .right,
      maneuverJA: "右方向を保ち",
      maneuverZH: "保持右侧",
      maneuverEN: "keep right",
      japaneseSignText: "羽田",
      routeShields: ["K5", "K1"],
      junctionNameJA: "生麦JCT",
      junctionNameZH: "生麦 JCT",
      junctionNameEN: "Namamugi JCT",
      destinationJA: "K1 横羽線 羽田方面",
      destinationZH: "K1 横羽线羽田方向",
      destinationEN: "Route K1 toward Haneda",
      expectedJunctionDetailSHA256:
        "68ce0e28c3d83658d98c7bc68fef815c"
        + "a0f3f7bed77e3bea72573ae2b0c5bd7c",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_namamugi",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-k5/",
        "https://www.shutoko.jp/use/network/map/route-k1/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.namamugi.k1-inbound-stays-on-k1",
      junctionID: "shuto.jct.jct_namamugi",
      junctionNodeID: 4_360_978_732,
      incomingEdgeID: "osm.32592648.13.forward",
      outgoingEdgeID: "osm.438360534.0.forward",
      incomingRouteID: "K1",
      incomingDirectionJA: "上り",
      outgoingRouteID: "K1",
      outgoingDirectionJA: "上り",
      branchSide: .straight,
      japaneseSignText: "羽田",
      routeShields: ["K1"],
      junctionNameJA: "生麦JCT",
      junctionNameZH: "生麦 JCT",
      junctionNameEN: "Namamugi JCT",
      destinationJA: "K1 横羽線 羽田方面",
      destinationZH: "K1 横羽线羽田方向",
      destinationEN: "Route K1 toward Haneda",
      expectedJunctionDetailSHA256:
        "68ce0e28c3d83658d98c7bc68fef815c"
        + "a0f3f7bed77e3bea72573ae2b0c5bd7c",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_namamugi",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-k1/"
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.daishi.k1-inbound-to-k6-outbound",
      junctionID: "shuto.jct.jct_daishi",
      junctionNodeID: 448_041_038,
      incomingEdgeID: "osm.438360534.88.forward",
      outgoingEdgeID: "osm.38093185.0.forward",
      incomingRouteID: "K1",
      incomingDirectionJA: "上り",
      outgoingRouteID: "K6",
      outgoingDirectionJA: "下り",
      branchSide: .left,
      japaneseSignText: "湾岸線",
      routeShields: ["K6", "B"],
      junctionNameJA: "大師JCT",
      junctionNameZH: "大师 JCT",
      junctionNameEN: "Daishi JCT",
      destinationJA: "K6 川崎線 湾岸線方面",
      destinationZH: "K6 川崎线湾岸线方向",
      destinationEN: "Route K6 toward the Bayshore Route",
      expectedJunctionDetailSHA256:
        "2888d66c9bb0f1edba8864802e5c91ce"
        + "d93b34bc190527afa1a2f4e07ca7e7be",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_daishi",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-k1/",
        "https://www.shutoko.jp/use/network/map/route-k6/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.daishi.k1-inbound-stays-on-k1",
      junctionID: "shuto.jct.jct_daishi",
      junctionNodeID: 448_041_038,
      incomingEdgeID: "osm.438360534.88.forward",
      outgoingEdgeID: "osm.438360534.89.forward",
      incomingRouteID: "K1",
      incomingDirectionJA: "上り",
      outgoingRouteID: "K1",
      outgoingDirectionJA: "上り",
      branchSide: .straight,
      japaneseSignText: "羽田",
      routeShields: ["K1"],
      junctionNameJA: "大師JCT",
      junctionNameZH: "大师 JCT",
      junctionNameEN: "Daishi JCT",
      destinationJA: "K1 横羽線 羽田方面",
      destinationZH: "K1 横羽线羽田方向",
      destinationEN: "Route K1 toward Haneda",
      expectedJunctionDetailSHA256:
        "2888d66c9bb0f1edba8864802e5c91ce"
        + "d93b34bc190527afa1a2f4e07ca7e7be",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_daishi",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-k1/",
        "https://www.shutoko.jp/use/network/map/route-k6/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.kawasaki.k6-outbound-to-bayshore",
      junctionID: "shuto.jct.jct_kawasaki",
      junctionNodeID: 36_421_538,
      incomingEdgeID: "osm.82596770.33.forward",
      outgoingEdgeID: "osm.783646149.0.forward",
      incomingRouteID: "K6",
      incomingDirectionJA: "下り",
      outgoingRouteID: "K6",
      outgoingDirectionJA: "下り",
      coveredFollowingDecisionEdgeIDs: [
        "osm.783646149.1.forward",
        "osm.783646149.2.forward",
        "osm.783646149.3.forward",
        "osm.783646149.4.forward",
        "osm.783646149.5.forward",
        "osm.783646149.6.forward",
        "osm.783646149.7.forward",
        "osm.783646149.8.forward",
        "osm.783646149.9.forward",
        "osm.783646149.10.forward",
        "osm.783646149.11.forward",
        "osm.783646149.12.forward",
        "osm.783646149.13.forward",
        "osm.783646149.14.forward",
        "osm.783646149.15.forward",
        "osm.783646149.16.forward",
        "osm.783646149.17.forward",
        "osm.783646149.18.forward",
        "osm.783646149.19.forward",
        "osm.783646149.20.forward",
        "osm.783646149.21.forward",
        "osm.783646149.22.forward",
        "osm.783646149.23.forward",
        "osm.783646149.24.forward",
        "osm.783646149.25.forward",
        "osm.783646149.26.forward",
        "osm.783646149.27.forward",
        "osm.783646149.28.forward",
        "osm.783646149.29.forward",
        "osm.783646149.30.forward",
        "osm.783646149.31.forward",
        "osm.783646149.32.forward",
        "osm.783646149.33.forward",
        "osm.783646149.34.forward",
        "osm.59613958.0.forward",
      ],
      branchSide: .right,
      maneuverJA: "右方向を保ち",
      maneuverZH: "保持右侧",
      maneuverEN: "keep right",
      japaneseSignText: "東京・横浜",
      routeShields: ["B"],
      junctionNameJA: "川崎浮島JCT",
      junctionNameZH: "川崎浮岛 JCT",
      junctionNameEN: "Kawasaki-Ukishima JCT",
      destinationJA: "湾岸線 東京・横浜方面",
      destinationZH: "湾岸线东京、横滨方向",
      destinationEN: "the Bayshore Route toward Tokyo or Yokohama",
      expectedJunctionDetailSHA256:
        "29eb925d30dec708acdc797dfc662d917"
        + "69e80e18e80133b7c6f0bfbd2fba92c",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_kawasaki",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-k6/",
        "https://www.shutoko.jp/use/network/map/route-b/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.kawasaki.k6-outbound-to-aqualine",
      junctionID: "shuto.jct.jct_kawasaki",
      junctionNodeID: 36_421_538,
      incomingEdgeID: "osm.82596770.33.forward",
      outgoingEdgeID: "osm.783649669.0.forward",
      incomingRouteID: "K6",
      incomingDirectionJA: "下り",
      outgoingRouteID: "K6",
      outgoingDirectionJA: "下り",
      branchSide: .straight,
      japaneseSignText: "アクアライン・木更津",
      routeShields: ["CA"],
      junctionNameJA: "川崎浮島JCT",
      junctionNameZH: "川崎浮岛 JCT",
      junctionNameEN: "Kawasaki-Ukishima Junction",
      destinationJA: "東京湾アクアライン 木更津方面",
      destinationZH: "东京湾 Aqua-Line 木更津方向",
      destinationEN: "the Tokyo Bay Aqua-Line toward Kisarazu",
      expectedJunctionDetailSHA256:
        "29eb925d30dec708acdc797dfc662d917"
        + "69e80e18e80133b7c6f0bfbd2fba92c",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_kawasaki",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-k6/"
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.kawasaki.k6-outbound-to-b-eastbound",
      junctionID: "shuto.jct.jct_kawasaki",
      junctionNodeID: 739_475_888,
      incomingEdgeID: "osm.59613958.0.forward",
      outgoingEdgeID: "osm.5208415.0.forward",
      incomingRouteID: "K6",
      incomingDirectionJA: "下り",
      outgoingRouteID: "B",
      outgoingDirectionJA: "東行き",
      branchSide: .left,
      japaneseSignText: "東京",
      routeShields: ["B"],
      junctionNameJA: "川崎浮島JCT",
      junctionNameZH: "川崎浮岛 JCT",
      junctionNameEN: "Kawasaki-Ukishima Junction",
      destinationJA: "湾岸線 東京方面",
      destinationZH: "湾岸线东京方向",
      destinationEN: "the Bayshore Route toward Tokyo",
      expectedJunctionDetailSHA256:
        "29eb925d30dec708acdc797dfc662d917"
        + "69e80e18e80133b7c6f0bfbd2fba92c",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_kawasaki",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-k6/",
        "https://www.shutoko.jp/use/network/map/route-b/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.kawasaki.k6-outbound-to-b-westbound",
      junctionID: "shuto.jct.jct_kawasaki",
      junctionNodeID: 739_475_888,
      incomingEdgeID: "osm.59613958.0.forward",
      outgoingEdgeID: "osm.59613958.1.forward",
      incomingRouteID: "K6",
      incomingDirectionJA: "下り",
      outgoingRouteID: "K6",
      outgoingDirectionJA: "下り",
      branchSide: .right,
      japaneseSignText: "横浜",
      routeShields: ["B"],
      junctionNameJA: "川崎浮島JCT",
      junctionNameZH: "川崎浮岛 JCT",
      junctionNameEN: "Kawasaki-Ukishima Junction",
      destinationJA: "湾岸線 横浜方面",
      destinationZH: "湾岸线横滨方向",
      destinationEN: "the Bayshore Route toward Yokohama",
      expectedJunctionDetailSHA256:
        "29eb925d30dec708acdc797dfc662d917"
        + "69e80e18e80133b7c6f0bfbd2fba92c",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_kawasaki",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-k6/",
        "https://www.shutoko.jp/use/network/map/route-b/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.kawasaki.b-eastbound-stays-on-b",
      junctionID: "shuto.jct.jct_kawasaki",
      junctionNodeID: 36_421_509,
      incomingEdgeID: "osm.5204845.0.forward",
      outgoingEdgeID: "osm.5204845.1.forward",
      incomingRouteID: "B",
      incomingDirectionJA: "東行き",
      outgoingRouteID: "B",
      outgoingDirectionJA: "東行き",
      branchSide: .straight,
      japaneseSignText: "東京・空港中央",
      routeShields: ["B", "1", "11"],
      junctionNameJA: "川崎浮島JCT",
      junctionNameZH: "川崎浮岛 JCT",
      junctionNameEN: "Kawasaki-Ukishima Junction",
      destinationJA: "湾岸線 東京・空港中央方面",
      destinationZH: "湾岸线东京、空港中央方向",
      destinationEN: "the Bayshore Route toward Tokyo and Haneda Airport",
      expectedJunctionDetailSHA256:
        "29eb925d30dec708acdc797dfc662d917"
        + "69e80e18e80133b7c6f0bfbd2fba92c",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_kawasaki",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-b/"
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.kawasaki.b-eastbound-to-k6",
      junctionID: "shuto.jct.jct_kawasaki",
      junctionNodeID: 36_421_509,
      incomingEdgeID: "osm.5204845.0.forward",
      outgoingEdgeID: "osm.5212953.0.forward",
      incomingRouteID: "B",
      incomingDirectionJA: "東行き",
      outgoingRouteID: "K6",
      outgoingDirectionJA: "上り",
      branchSide: .left,
      japaneseSignText: "川崎・木更津",
      routeShields: ["K6", "CA"],
      junctionNameJA: "川崎浮島JCT",
      junctionNameZH: "川崎浮岛 JCT",
      junctionNameEN: "Kawasaki-Ukishima Junction",
      destinationJA: "K6 川崎線・東京湾アクアライン方面",
      destinationZH: "K6 川崎线、东京湾 Aqua-Line 方向",
      destinationEN: "Route K6 or the Tokyo Bay Aqua-Line",
      expectedJunctionDetailSHA256:
        "29eb925d30dec708acdc797dfc662d917"
        + "69e80e18e80133b7c6f0bfbd2fba92c",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_kawasaki",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-b/",
        "https://www.shutoko.jp/use/network/map/route-k6/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.kawasaki.b-westbound-to-k6",
      junctionID: "shuto.jct.jct_kawasaki",
      junctionNodeID: 739_475_893,
      incomingEdgeID: "osm.5204788.17.forward",
      outgoingEdgeID: "osm.5212959.0.forward",
      incomingRouteID: "B",
      incomingDirectionJA: "西行き",
      outgoingRouteID: "K6",
      outgoingDirectionJA: "上り",
      branchSide: .left,
      japaneseSignText: "川崎",
      routeShields: ["K6"],
      junctionNameJA: "川崎浮島JCT",
      junctionNameZH: "川崎浮岛 JCT",
      junctionNameEN: "Kawasaki-Ukishima Junction",
      destinationJA: "K6 川崎線 川崎方面",
      destinationZH: "K6 川崎线川崎方向",
      destinationEN: "Route K6 toward Kawasaki",
      expectedJunctionDetailSHA256:
        "29eb925d30dec708acdc797dfc662d917"
        + "69e80e18e80133b7c6f0bfbd2fba92c",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_kawasaki",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-b/",
        "https://www.shutoko.jp/use/network/map/route-k6/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.shinonome.10-outbound-to-b-westbound",
      junctionID: "shuto.jct.jct_shinonome",
      junctionNodeID: 499_275_905,
      incomingEdgeID: "osm.1264293942.1.forward",
      outgoingEdgeID: "osm.174976692.0.forward",
      incomingRouteID: "10",
      incomingDirectionJA: "下り",
      outgoingRouteID: "B",
      outgoingDirectionJA: "西行き",
      branchSide: .right,
      japaneseSignText: "横浜",
      routeShields: ["B"],
      junctionNameJA: "東雲JCT",
      junctionNameZH: "东云 JCT",
      junctionNameEN: "Shinonome JCT",
      destinationJA: "湾岸線 横浜方面",
      destinationZH: "湾岸线横滨方向",
      destinationEN: "the Bayshore Route toward Yokohama",
      expectedJunctionDetailSHA256:
        "452e2ca3d124ec3f726b0c3643cedbbce"
        + "3446b21e755f538b418616278cfa605",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_shinonome",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-10/",
        "https://www.shutoko.jp/use/network/map/route-b/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.tokai.b-westbound-to-yokohama-branch",
      junctionID: "shuto.jct.jct_tokai",
      junctionNodeID: 35_937_972,
      incomingEdgeID: "osm.45683111.1.forward",
      outgoingEdgeID: "osm.5171344.0.forward",
      incomingRouteID: "B",
      incomingDirectionJA: "西行き",
      outgoingRouteID: "B",
      outgoingDirectionJA: "西行き",
      branchSide: .right,
      japaneseSignText: "横浜公園",
      routeShields: ["B", "K1"],
      junctionNameJA: "東海JCT",
      junctionNameZH: "东海 JCT",
      junctionNameEN: "Tokai JCT",
      destinationJA: "横浜公園方面",
      destinationZH: "横浜公園方向",
      destinationEN: "Yokohama-koen",
      expectedJunctionDetailSHA256:
        "c3e400f7d241f86d628020e9bc8ace34"
        + "3f0d517cbdad993a5f0511443a7cd47a",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_tokai",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-b/",
        "https://www.shutoko.jp/use/network/map/route-1/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.daishi.k1-outbound-stays-on-k1",
      junctionID: "shuto.jct.jct_daishi",
      junctionNodeID: 273_330_999,
      incomingEdgeID: "osm.38093215.12.forward",
      outgoingEdgeID: "osm.38093215.13.forward",
      incomingRouteID: "K1",
      incomingDirectionJA: "下り",
      outgoingRouteID: "K1",
      outgoingDirectionJA: "下り",
      branchSide: .left,
      maneuverJA: "左方向を保ち",
      maneuverZH: "保持左侧",
      maneuverEN: "keep left",
      japaneseSignText: "横浜公園",
      routeShields: ["K1"],
      junctionNameJA: "大師JCT",
      junctionNameZH: "大师 JCT",
      junctionNameEN: "Daishi JCT",
      destinationJA: "K1 横羽線 横浜公園方面",
      destinationZH: "K1 横羽线横浜公園方向",
      destinationEN: "Route K1 toward Yokohama-koen",
      expectedJunctionDetailSHA256:
        "2888d66c9bb0f1edba8864802e5c91ce"
        + "d93b34bc190527afa1a2f4e07ca7e7be",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_daishi",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-k1/",
        "https://www.shutoko.jp/use/network/map/route-k6/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.daishi.k1-outbound-to-k6-outbound",
      junctionID: "shuto.jct.jct_daishi",
      junctionNodeID: 273_330_999,
      incomingEdgeID: "osm.38093215.12.forward",
      outgoingEdgeID: "osm.804932420.0.forward",
      incomingRouteID: "K1",
      incomingDirectionJA: "下り",
      outgoingRouteID: "K1",
      outgoingDirectionJA: "下り",
      branchSide: .right,
      japaneseSignText: "湾岸線・東京湾アクアライン",
      routeShields: ["K6", "B", "CA"],
      junctionNameJA: "大師JCT",
      junctionNameZH: "大师 JCT",
      junctionNameEN: "Daishi JCT",
      destinationJA: "K6 川崎線 湾岸線・東京湾アクアライン方面",
      destinationZH: "K6 川崎线湾岸线・东京湾跨海公路方向",
      destinationEN:
        "Route K6 toward the Bayshore Route and Tokyo Bay Aqua-Line",
      expectedJunctionDetailSHA256:
        "2888d66c9bb0f1edba8864802e5c91ce"
        + "d93b34bc190527afa1a2f4e07ca7e7be",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_daishi",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-k1/",
        "https://www.shutoko.jp/use/network/map/route-k6/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.namamugi.k1-outbound-stays-on-k1",
      junctionID: "shuto.jct.jct_namamugi",
      junctionNodeID: 273_331_184,
      incomingEdgeID: "osm.38093215.138.forward",
      outgoingEdgeID: "osm.38093215.139.forward",
      incomingRouteID: "K1",
      incomingDirectionJA: "下り",
      outgoingRouteID: "K1",
      outgoingDirectionJA: "下り",
      coveredFollowingDecisionEdgeIDs: [
        "osm.38093215.140.forward"
      ],
      branchSide: .left,
      maneuverJA: "最初の分岐で左方向を保ち、続く分岐で右方向を保ち",
      maneuverZH: "在第一个分岔保持左侧，随后在第二个分岔保持右侧",
      maneuverEN: "keep left at the first fork, then keep right",
      japaneseSignText: "横浜公園",
      routeShields: ["K1"],
      junctionNameJA: "生麦JCT",
      junctionNameZH: "生麦 JCT",
      junctionNameEN: "Namamugi JCT",
      destinationJA: "K1 横羽線 横浜公園方面",
      destinationZH: "K1 横羽线横浜公園方向",
      destinationEN: "Route K1 toward Yokohama-koen",
      expectedJunctionDetailSHA256:
        "68ce0e28c3d83658d98c7bc68fef815c"
        + "a0f3f7bed77e3bea72573ae2b0c5bd7c",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_namamugi",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-k1/",
        "https://www.shutoko.jp/use/network/map/route-k5/",
        "https://www.shutoko.jp/use/network/map/route-k7/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.kinko.k1-outbound-stays-on-k1",
      junctionID: "shuto.jct.jct_kinkou",
      junctionNodeID: 273_331_411,
      incomingEdgeID: "osm.760720782.10.forward",
      outgoingEdgeID: "osm.39744129.0.forward",
      incomingRouteID: "K1",
      incomingDirectionJA: "下り",
      outgoingRouteID: "K1",
      outgoingDirectionJA: "下り",
      branchSide: .left,
      maneuverJA: "左方向を保ち",
      maneuverZH: "保持左侧",
      maneuverEN: "keep left",
      japaneseSignText: "横浜公園",
      routeShields: ["K1"],
      junctionNameJA: "金港JCT",
      junctionNameZH: "金港 JCT",
      junctionNameEN: "Kinko JCT",
      destinationJA: "K1 横羽線 横浜公園方面",
      destinationZH: "K1 横羽线横浜公園方向",
      destinationEN: "Route K1 toward Yokohama-koen",
      expectedJunctionDetailSHA256:
        "dc2a994c6b95e83be9c44ab42c2ff852"
        + "06696723d5e7c78cd189ce3960207061",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_kinkou",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-k1/",
        "https://www.shutoko.jp/use/network/map/route-k2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.kinko.k1-outbound-to-k2-outbound",
      junctionID: "shuto.jct.jct_kinkou",
      junctionNodeID: 273_331_411,
      incomingEdgeID: "osm.760720782.10.forward",
      outgoingEdgeID: "osm.31709108.0.forward",
      incomingRouteID: "K1",
      incomingDirectionJA: "下り",
      outgoingRouteID: "K2",
      outgoingDirectionJA: "下り",
      branchSide: .right,
      japaneseSignText: "第三京浜・横浜新道",
      routeShields: ["K2", "E83"],
      junctionNameJA: "金港JCT",
      junctionNameZH: "金港 JCT",
      junctionNameEN: "Kinko JCT",
      destinationJA: "K2 三ツ沢線 第三京浜・横浜新道方面",
      destinationZH: "K2 三泽线第三京滨・横滨新道方向",
      destinationEN:
        "Route K2 toward Daisan Keihin and Yokohama Shindo",
      expectedJunctionDetailSHA256:
        "dc2a994c6b95e83be9c44ab42c2ff852"
        + "06696723d5e7c78cd189ce3960207061",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_kinkou",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-k1/",
        "https://www.shutoko.jp/use/network/map/route-k2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.kinko.k1-inbound-stays-on-k1",
      junctionID: "shuto.jct.jct_kinkou",
      junctionNodeID: 364_550_932,
      incomingEdgeID: "osm.32404414.20.forward",
      outgoingEdgeID: "osm.340606284.0.forward",
      incomingRouteID: "K1",
      incomingDirectionJA: "上り",
      outgoingRouteID: "K1",
      outgoingDirectionJA: "上り",
      branchSide: .right,
      japaneseSignText: "羽田",
      routeShields: ["K1"],
      junctionNameJA: "金港JCT",
      junctionNameZH: "金港 JCT",
      junctionNameEN: "Kinko JCT",
      destinationJA: "K1 横羽線 羽田方面",
      destinationZH: "K1 横羽线羽田方向",
      destinationEN: "Route K1 toward Haneda",
      expectedJunctionDetailSHA256:
        "dc2a994c6b95e83be9c44ab42c2ff852"
        + "06696723d5e7c78cd189ce3960207061",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_kinkou",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-k1/",
        "https://www.shutoko.jp/use/network/map/route-k2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.kinko.k1-inbound-to-k2-outbound",
      junctionID: "shuto.jct.jct_kinkou",
      junctionNodeID: 364_550_932,
      incomingEdgeID: "osm.32404414.20.forward",
      outgoingEdgeID: "osm.34994498.0.forward",
      incomingRouteID: "K1",
      incomingDirectionJA: "上り",
      outgoingRouteID: "K2",
      outgoingDirectionJA: "下り",
      branchSide: .left,
      japaneseSignText: "第三京浜・横浜新道",
      routeShields: ["K2", "E83"],
      junctionNameJA: "金港JCT",
      junctionNameZH: "金港 JCT",
      junctionNameEN: "Kinko JCT",
      destinationJA: "K2 三ツ沢線 第三京浜・横浜新道方面",
      destinationZH: "K2 三泽线第三京滨・横滨新道方向",
      destinationEN:
        "Route K2 toward Daisan Keihin and Yokohama Shindo",
      expectedJunctionDetailSHA256:
        "dc2a994c6b95e83be9c44ab42c2ff852"
        + "06696723d5e7c78cd189ce3960207061",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_kinkou",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-k1/",
        "https://www.shutoko.jp/use/network/map/route-k2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.kinko.k2-inbound-to-k1-outbound",
      junctionID: "shuto.jct.jct_kinkou",
      junctionNodeID: 476_496_811,
      incomingEdgeID: "osm.915304584.0.forward",
      outgoingEdgeID: "osm.39744132.0.forward",
      incomingRouteID: "K2",
      incomingDirectionJA: "上り",
      outgoingRouteID: "K2",
      outgoingDirectionJA: "上り",
      branchSide: .right,
      japaneseSignText: "横浜公園・湾岸線",
      routeShields: ["K1", "K3"],
      junctionNameJA: "金港JCT",
      junctionNameZH: "金港 JCT",
      junctionNameEN: "Kinko JCT",
      destinationJA: "K1 横羽線 横浜公園・K3 狩場線 湾岸線方面",
      destinationZH: "K1 横羽线横滨公园・K3 狩场线湾岸线方向",
      destinationEN:
        "Route K1 toward Yokohama-koen and Route K3 toward the Bayshore Route",
      expectedJunctionDetailSHA256:
        "dc2a994c6b95e83be9c44ab42c2ff852"
        + "06696723d5e7c78cd189ce3960207061",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_kinkou",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-k1/",
        "https://www.shutoko.jp/use/network/map/route-k2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.kinko.k2-inbound-to-k1-inbound",
      junctionID: "shuto.jct.jct_kinkou",
      junctionNodeID: 476_496_811,
      incomingEdgeID: "osm.915304584.0.forward",
      outgoingEdgeID: "osm.915304583.0.forward",
      incomingRouteID: "K2",
      incomingDirectionJA: "上り",
      outgoingRouteID: "K2",
      outgoingDirectionJA: "上り",
      branchSide: .left,
      japaneseSignText: "羽田",
      routeShields: ["K1"],
      junctionNameJA: "金港JCT",
      junctionNameZH: "金港 JCT",
      junctionNameEN: "Kinko JCT",
      destinationJA: "K1 横羽線 羽田方面",
      destinationZH: "K1 横羽线羽田方向",
      destinationEN: "Route K1 toward Haneda",
      expectedJunctionDetailSHA256:
        "dc2a994c6b95e83be9c44ab42c2ff852"
        + "06696723d5e7c78cd189ce3960207061",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_kinkou",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-k1/",
        "https://www.shutoko.jp/use/network/map/route-k2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.ishikawacho.k1-outbound-to-k3-outbound",
      junctionID: "shuto.jct.jct_ishikawacho",
      junctionNodeID: 982_266_259,
      incomingEdgeID: "osm.987587806.0.forward",
      outgoingEdgeID: "osm.38913574.0.forward",
      incomingRouteID: "K1",
      incomingDirectionJA: "下り",
      outgoingRouteID: "K1",
      outgoingDirectionJA: "下り",
      branchSide: .left,
      japaneseSignText: "湾岸線",
      routeShields: ["K3", "B"],
      junctionNameJA: "石川町JCT",
      junctionNameZH: "石川町 JCT",
      junctionNameEN: "Ishikawacho JCT",
      destinationJA: "K3 狩場線 湾岸線方面",
      destinationZH: "K3 狩场线湾岸线方向",
      destinationEN: "Route K3 toward the Bayshore Route",
      expectedJunctionDetailSHA256:
        "7f49d7d4ac190a0fdb160b216e95fee7"
        + "78d83b4869d3bee629345816a19e88dd",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_ishikawacho",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-k1/",
        "https://www.shutoko.jp/use/network/map/route-k3/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.ishikawacho.k1-outbound-to-k3-inbound",
      junctionID: "shuto.jct.jct_ishikawacho",
      junctionNodeID: 982_266_259,
      incomingEdgeID: "osm.987587806.0.forward",
      outgoingEdgeID: "osm.84530636.0.forward",
      incomingRouteID: "K1",
      incomingDirectionJA: "下り",
      outgoingRouteID: "K1",
      outgoingDirectionJA: "下り",
      branchSide: .right,
      japaneseSignText: "保土ヶ谷バイパス",
      routeShields: ["K3"],
      junctionNameJA: "石川町JCT",
      junctionNameZH: "石川町 JCT",
      junctionNameEN: "Ishikawacho JCT",
      destinationJA: "K3 狩場線 保土ヶ谷バイパス方面",
      destinationZH: "K3 狩场线保土谷绕行线方向",
      destinationEN: "Route K3 toward the Hodogaya Bypass",
      expectedJunctionDetailSHA256:
        "7f49d7d4ac190a0fdb160b216e95fee7"
        + "78d83b4869d3bee629345816a19e88dd",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_ishikawacho",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-k1/",
        "https://www.shutoko.jp/use/network/map/route-k3/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.ishikawacho.k3-inbound-to-k1-inbound",
      junctionID: "shuto.jct.jct_ishikawacho",
      junctionNodeID: 364_548_786,
      incomingEdgeID: "osm.84530629.13.forward",
      outgoingEdgeID: "osm.32404412.0.forward",
      incomingRouteID: "K3",
      incomingDirectionJA: "上り",
      outgoingRouteID: "K1",
      outgoingDirectionJA: "上り",
      branchSide: .right,
      japaneseSignText: "横浜公園・羽田",
      routeShields: ["K1"],
      junctionNameJA: "石川町JCT",
      junctionNameZH: "石川町 JCT",
      junctionNameEN: "Ishikawacho JCT",
      destinationJA: "K1 横羽線 横浜公園・羽田方面",
      destinationZH: "K1 横羽线横滨公园・羽田方向",
      destinationEN: "Route K1 toward Yokohama-koen and Haneda",
      expectedJunctionDetailSHA256:
        "7f49d7d4ac190a0fdb160b216e95fee7"
        + "78d83b4869d3bee629345816a19e88dd",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_ishikawacho",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-k1/",
        "https://www.shutoko.jp/use/network/map/route-k3/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.ishikawacho.k3-inbound-stays-on-k3",
      junctionID: "shuto.jct.jct_ishikawacho",
      junctionNodeID: 364_548_786,
      incomingEdgeID: "osm.84530629.13.forward",
      outgoingEdgeID: "osm.340606291.0.forward",
      incomingRouteID: "K3",
      incomingDirectionJA: "上り",
      outgoingRouteID: "K3",
      outgoingDirectionJA: "上り",
      branchSide: .straight,
      japaneseSignText: "保土ヶ谷バイパス",
      routeShields: ["K3"],
      junctionNameJA: "石川町JCT",
      junctionNameZH: "石川町 JCT",
      junctionNameEN: "Ishikawacho JCT",
      destinationJA: "K3 狩場線 保土ヶ谷バイパス方面",
      destinationZH: "K3 狩场线保土谷绕行线方向",
      destinationEN: "Route K3 toward the Hodogaya Bypass",
      expectedJunctionDetailSHA256:
        "7f49d7d4ac190a0fdb160b216e95fee7"
        + "78d83b4869d3bee629345816a19e88dd",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_ishikawacho",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-k1/",
        "https://www.shutoko.jp/use/network/map/route-k3/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.ishikawacho.k3-outbound-stays-on-k3",
      junctionID: "shuto.jct.jct_ishikawacho",
      junctionNodeID: 447_800_585,
      incomingEdgeID: "osm.174480816.59.forward",
      outgoingEdgeID: "osm.174480816.60.forward",
      incomingRouteID: "K3",
      incomingDirectionJA: "下り",
      outgoingRouteID: "K3",
      outgoingDirectionJA: "下り",
      branchSide: .straight,
      japaneseSignText: "湾岸線・空港中央",
      routeShields: ["K3", "B"],
      junctionNameJA: "石川町JCT",
      junctionNameZH: "石川町 JCT",
      junctionNameEN: "Ishikawacho JCT",
      destinationJA: "K3 狩場線 湾岸線・空港中央方面",
      destinationZH: "K3 狩场线湾岸线・空港中央方向",
      destinationEN:
        "Route K3 toward the Bayshore Route and Kuko-Chuo",
      expectedJunctionDetailSHA256:
        "7f49d7d4ac190a0fdb160b216e95fee7"
        + "78d83b4869d3bee629345816a19e88dd",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_ishikawacho",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-k1/",
        "https://www.shutoko.jp/use/network/map/route-k3/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.ishikawacho.k3-outbound-to-k1-inbound",
      junctionID: "shuto.jct.jct_ishikawacho",
      junctionNodeID: 447_800_585,
      incomingEdgeID: "osm.174480816.59.forward",
      outgoingEdgeID: "osm.84530632.0.forward",
      incomingRouteID: "K3",
      incomingDirectionJA: "下り",
      outgoingRouteID: "K1",
      outgoingDirectionJA: "上り",
      branchSide: .left,
      japaneseSignText: "羽田・みなとみらい",
      routeShields: ["K1"],
      junctionNameJA: "石川町JCT",
      junctionNameZH: "石川町 JCT",
      junctionNameEN: "Ishikawacho JCT",
      destinationJA: "K1 横羽線 羽田・みなとみらい方面",
      destinationZH: "K1 横羽线羽田・港未来方向",
      destinationEN: "Route K1 toward Haneda and Minato Mirai",
      expectedJunctionDetailSHA256:
        "7f49d7d4ac190a0fdb160b216e95fee7"
        + "78d83b4869d3bee629345816a19e88dd",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_ishikawacho",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-k1/",
        "https://www.shutoko.jp/use/network/map/route-k3/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.honmoku.k3-outbound-to-b-eastbound",
      junctionID: "shuto.jct.jct_honmoku",
      junctionNodeID: 354_782_234,
      incomingEdgeID: "osm.84530623.12.forward",
      outgoingEdgeID: "osm.38072737.0.forward",
      incomingRouteID: "K3",
      incomingDirectionJA: "下り",
      outgoingRouteID: "K3",
      outgoingDirectionJA: "下り",
      branchSide: .straight,
      japaneseSignText: "空港中央・大黒ふ頭",
      routeShields: ["B", "K5"],
      junctionNameJA: "本牧JCT",
      junctionNameZH: "本牧 JCT",
      junctionNameEN: "Honmoku JCT",
      destinationJA: "湾岸線 空港中央・大黒ふ頭方面",
      destinationZH: "湾岸线空港中央、大黑码头方向",
      destinationEN:
        "the Bayshore Route toward Kuko-Chuo and Daikoku-Futo",
      expectedJunctionDetailSHA256:
        "8d14238a40aaeaef7ec2c22904747f53f"
        + "335173c99583595b2152e5df4dbc934",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_honmoku",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-k3/",
        "https://www.shutoko.jp/use/network/map/route-b/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.honmoku.k3-outbound-to-b-westbound",
      junctionID: "shuto.jct.jct_honmoku",
      junctionNodeID: 354_782_234,
      incomingEdgeID: "osm.84530623.12.forward",
      outgoingEdgeID: "osm.301016676.0.forward",
      incomingRouteID: "K3",
      incomingDirectionJA: "下り",
      outgoingRouteID: "K3",
      outgoingDirectionJA: "下り",
      branchSide: .left,
      japaneseSignText: "幸浦",
      routeShields: ["B"],
      junctionNameJA: "本牧JCT",
      junctionNameZH: "本牧 JCT",
      junctionNameEN: "Honmoku JCT",
      destinationJA: "湾岸線 幸浦方面",
      destinationZH: "湾岸线幸浦方向",
      destinationEN: "the Bayshore Route toward Sachiura",
      expectedJunctionDetailSHA256:
        "8d14238a40aaeaef7ec2c22904747f53f"
        + "335173c99583595b2152e5df4dbc934",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_honmoku",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-k3/",
        "https://www.shutoko.jp/use/network/map/route-b/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.honmoku.b-eastbound-to-k3-inbound",
      junctionID: "shuto.jct.jct_honmoku",
      junctionNodeID: 364_539_038,
      incomingEdgeID: "osm.435760593.169.forward",
      outgoingEdgeID: "osm.32403532.0.forward",
      incomingRouteID: "B",
      incomingDirectionJA: "東行き",
      outgoingRouteID: "K3",
      outgoingDirectionJA: "上り",
      branchSide: .left,
      japaneseSignText: "横浜駅東口・狩場線",
      routeShields: ["K3", "K1", "K2"],
      junctionNameJA: "本牧JCT",
      junctionNameZH: "本牧 JCT",
      junctionNameEN: "Honmoku JCT",
      destinationJA: "K3 狩場線 横浜駅東口方面",
      destinationZH: "K3 狩场线横滨站东口方向",
      destinationEN: "Route K3 toward Yokohama Station East Exit",
      expectedJunctionDetailSHA256:
        "8d14238a40aaeaef7ec2c22904747f53f"
        + "335173c99583595b2152e5df4dbc934",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_honmoku",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-b/",
        "https://www.shutoko.jp/use/network/map/route-k3/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.honmoku.b-eastbound-stays-on-b",
      junctionID: "shuto.jct.jct_honmoku",
      junctionNodeID: 364_539_038,
      incomingEdgeID: "osm.435760593.169.forward",
      outgoingEdgeID: "osm.435760593.170.forward",
      incomingRouteID: "B",
      incomingDirectionJA: "東行き",
      outgoingRouteID: "B",
      outgoingDirectionJA: "東行き",
      branchSide: .straight,
      japaneseSignText: "空港中央・大黒ふ頭",
      routeShields: ["B", "K5"],
      junctionNameJA: "本牧JCT",
      junctionNameZH: "本牧 JCT",
      junctionNameEN: "Honmoku JCT",
      destinationJA: "湾岸線 空港中央・大黒ふ頭方面",
      destinationZH: "湾岸线空港中央、大黑码头方向",
      destinationEN:
        "the Bayshore Route toward Kuko-Chuo and Daikoku-Futo",
      expectedJunctionDetailSHA256:
        "8d14238a40aaeaef7ec2c22904747f53f"
        + "335173c99583595b2152e5df4dbc934",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_honmoku",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-b/",
        "https://www.shutoko.jp/use/network/map/route-k3/",
      ]
    ),
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
    ShutoJunctionMovementDefinition(
      id: "shuto.jct.tanimachi.c1-inner-stays-on-c1",
      networkSnapshotID:
        "shuto-official-2026-07-29-osm-2026-08-04",
      junctionID: "shuto.jct.jct_tanimachi",
      junctionNodeID: 252_175_042,
      incomingEdgeID: "osm.23297430.0.forward",
      outgoingEdgeID: "osm.316123950.0.forward",
      incomingRouteID: "C1",
      incomingDirectionJA: "内回り",
      outgoingRouteID: "C1",
      outgoingDirectionJA: "内回り",
      // The operator diagram shows the Inner Circular continuation on a
      // straight arrow and 3号渋谷線 on a diverging arrow, so this
      // movement keeps the mainline and asserts no lane.
      branchSide: .straight,
      japaneseSignText: "芝公園",
      routeShields: ["C1"],
      laneGuidanceState: .notReleased,
      localizedJunctionNames: [
        .japanese: "谷町JCT",
        .simplifiedChinese: "谷町 JCT",
        .english: "Tanimachi JCT",
      ],
      localizedContent: [
        .japanese: LocalizedGuidanceContent(
          displayText: "分岐せず、都心環状線 芝公園方面へ",
          spokenText:
            "谷町ジャンクションは分岐せず、都心環状線 芝公園方面へ進んでください",
          spokenForms: [
            "都心環状線": "としんかんじょうせん",
            "芝公園": "しばこうえん",
            "谷町": "たにまち",
          ],
          preservedJapaneseSignText: "芝公園"
        ),
        .simplifiedChinese: LocalizedGuidanceContent(
          displayText: "不要分岔，沿都心环状线前往 芝公園 方向",
          spokenText:
            "在谷町 JCT不要分岔，沿都心环状线继续前往 芝公園 方向",
          spokenForms: ["芝公園": "芝公園"],
          preservedJapaneseSignText: "芝公園"
        ),
        .english: LocalizedGuidanceContent(
          displayText: "Stay on the Inner Circular Route toward 芝公園",
          spokenText:
            "At Tanimachi JCT, stay on the Inner Circular Route toward 芝公園",
          spokenForms: ["Inner Circular Route": "Inner Circular Route"],
          preservedJapaneseSignText: "芝公園"
        ),
      ],
      // A keep-going advisory is useful before the diverging ramp, not at
      // its nose, so it commits earlier than a branch instruction.
      commitTriggerDistanceMeters: 300,
      checkedAt: "2026-08-11",
      expectedJunctionDetailSHA256:
        "b7f8b5458757c825d2abf42f315bdb7d"
        + "60e54debbb8a7420f49dd8a4646940fd",
      sources: [
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/jct/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-c1/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-3/"
        ),
        ShutoJunctionGuidanceSource(
          url:
            "https://www.shutoko.jp/-/media/images/responsive/"
            + "customer/use/network/jct/routeguide/jct_tanimachi",
          contentSHA256:
            "b7f8b5458757c825d2abf42f315bdb7d"
            + "60e54debbb8a7420f49dd8a4646940fd"
        ),
      ]
    ),
    ShutoJunctionMovementDefinition(
      id: "shuto.jct.ichinohashi.c1-inner-stays-on-c1",
      networkSnapshotID:
        "shuto-official-2026-07-29-osm-2026-08-04",
      junctionID: "shuto.jct.jct_ichinohashi",
      junctionNodeID: 574_460_605,
      incomingEdgeID: "osm.23297444.19.forward",
      outgoingEdgeID: "osm.23297444.20.forward",
      incomingRouteID: "C1",
      incomingDirectionJA: "内回り",
      outgoingRouteID: "C1",
      outgoingDirectionJA: "内回り",
      // The operator diagram shows the Inner Circular continuation on a
      // straight arrow and 2号目黒線 on a diverging arrow, so this
      // movement keeps the mainline and asserts no lane.
      branchSide: .straight,
      japaneseSignText: "芝公園",
      routeShields: ["C1"],
      laneGuidanceState: .notReleased,
      localizedJunctionNames: [
        .japanese: "一ノ橋JCT",
        .simplifiedChinese: "一之桥 JCT",
        .english: "Ichinohashi JCT",
      ],
      localizedContent: [
        .japanese: LocalizedGuidanceContent(
          displayText: "分岐せず、都心環状線 芝公園方面へ",
          spokenText:
            "一ノ橋ジャンクションは分岐せず、都心環状線 芝公園方面へ進んでください",
          spokenForms: [
            "都心環状線": "としんかんじょうせん",
            "芝公園": "しばこうえん",
            "一ノ橋": "いちのはし",
          ],
          preservedJapaneseSignText: "芝公園"
        ),
        .simplifiedChinese: LocalizedGuidanceContent(
          displayText: "不要分岔，沿都心环状线前往 芝公園 方向",
          spokenText:
            "在一之桥 JCT不要分岔，沿都心环状线继续前往 芝公園 方向",
          spokenForms: ["芝公園": "芝公園"],
          preservedJapaneseSignText: "芝公園"
        ),
        .english: LocalizedGuidanceContent(
          displayText: "Stay on the Inner Circular Route toward 芝公園",
          spokenText:
            "At Ichinohashi JCT, stay on the Inner Circular Route toward 芝公園",
          spokenForms: ["Inner Circular Route": "Inner Circular Route"],
          preservedJapaneseSignText: "芝公園"
        ),
      ],
      // A keep-going advisory is useful before the diverging ramp, not at
      // its nose, so it commits earlier than a branch instruction.
      commitTriggerDistanceMeters: 300,
      checkedAt: "2026-08-11",
      expectedJunctionDetailSHA256:
        "f56355b8bf55596a73adc91f8fa2c83a"
        + "f02ace3089843c63fd7c7b469db7d34d",
      sources: [
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/jct/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-c1/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-2/"
        ),
        ShutoJunctionGuidanceSource(
          url:
            "https://www.shutoko.jp/-/media/images/responsive/"
            + "customer/use/network/jct/routeguide/jct_ichinohashi",
          contentSHA256:
            "f56355b8bf55596a73adc91f8fa2c83a"
            + "f02ace3089843c63fd7c7b469db7d34d"
        ),
      ]
    ),
    ShutoJunctionMovementDefinition(
      id: "shuto.jct.edobashi.c1-inner-stays-on-c1",
      networkSnapshotID:
        "shuto-official-2026-07-29-osm-2026-08-04",
      junctionID: "shuto.jct.jct_edobashi",
      junctionNodeID: 264_871_771,
      incomingEdgeID: "osm.41009552.1.forward",
      outgoingEdgeID: "osm.1085022601.0.forward",
      incomingRouteID: "C1",
      incomingDirectionJA: "内回り",
      outgoingRouteID: "C1",
      outgoingDirectionJA: "内回り",
      // The operator diagram presents the C1/5 神田橋 choice once before
      // two graph forks only about 70 metres apart. One instruction covers
      // both exact C1 continuations so the runtime does not speak twice.
      coveredFollowingDecisionEdgeIDs: ["osm.199311847.0.forward"],
      branchSide: .straight,
      japaneseSignText: "神田橋",
      routeShields: ["C1"],
      laneGuidanceState: .notReleased,
      localizedJunctionNames: [
        .japanese: "江戸橋JCT",
        .simplifiedChinese: "江户桥 JCT",
        .english: "Edobashi JCT",
      ],
      localizedContent: [
        .japanese: LocalizedGuidanceContent(
          displayText: "分岐せず、都心環状線 神田橋方面へ",
          spokenText:
            "江戸橋ジャンクションは分岐せず、都心環状線 神田橋方面へ進んでください",
          spokenForms: [
            "都心環状線": "としんかんじょうせん",
            "神田橋": "かんだばし",
            "江戸橋": "えどばし",
          ],
          preservedJapaneseSignText: "神田橋"
        ),
        .simplifiedChinese: LocalizedGuidanceContent(
          displayText: "不要分岔，沿都心环状线前往 神田橋 方向",
          spokenText:
            "在江户桥 JCT不要分岔，沿都心环状线继续前往 神田橋 方向",
          spokenForms: ["神田橋": "神田橋"],
          preservedJapaneseSignText: "神田橋"
        ),
        .english: LocalizedGuidanceContent(
          displayText: "Stay on the Inner Circular Route toward 神田橋",
          spokenText:
            "At Edobashi JCT, stay on the Inner Circular Route toward 神田橋",
          spokenForms: ["Inner Circular Route": "Inner Circular Route"],
          preservedJapaneseSignText: "神田橋"
        ),
      ],
      commitTriggerDistanceMeters: 400,
      checkedAt: "2026-08-14",
      expectedJunctionDetailSHA256:
        "a855321a4dbf059131cada07f5dfd0e0"
        + "73762b063034053807b25001956db975",
      sources: [
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/jct/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-c1/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-1/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-6/"
        ),
        ShutoJunctionGuidanceSource(
          url:
            "https://www.shutoko.jp/-/media/images/responsive/"
            + "customer/use/network/jct/routeguide/jct_edobashi",
          contentSHA256:
            "a855321a4dbf059131cada07f5dfd0e0"
            + "73762b063034053807b25001956db975"
        ),
      ]
    ),
    ShutoJunctionMovementDefinition(
      id: "shuto.jct.miyakezaka.c1-inner-stays-on-c1",
      networkSnapshotID:
        "shuto-official-2026-07-29-osm-2026-08-04",
      junctionID: "shuto.jct.jct_miyakezaka",
      junctionNodeID: 255_513_709,
      incomingEdgeID: "osm.24402540.6.forward",
      outgoingEdgeID: "osm.24402540.7.forward",
      incomingRouteID: "C1",
      incomingDirectionJA: "内回り",
      outgoingRouteID: "C1",
      outgoingDirectionJA: "内回り",
      // The operator diagram shows the Inner Circular continuation on a
      // straight arrow and 4号新宿線 on a diverging arrow, so this
      // movement keeps the mainline and asserts no lane.
      branchSide: .straight,
      japaneseSignText: "霞が関",
      routeShields: ["C1"],
      laneGuidanceState: .notReleased,
      localizedJunctionNames: [
        .japanese: "三宅坂JCT",
        .simplifiedChinese: "三宅坂 JCT",
        .english: "Miyakezaka JCT",
      ],
      localizedContent: [
        .japanese: LocalizedGuidanceContent(
          displayText: "分岐せず、都心環状線 霞が関方面へ",
          spokenText:
            "三宅坂ジャンクションは分岐せず、都心環状線 霞が関方面へ進んでください",
          spokenForms: [
            "都心環状線": "としんかんじょうせん",
            "霞が関": "かすみがせき",
            "三宅坂": "みやけざか",
          ],
          preservedJapaneseSignText: "霞が関"
        ),
        .simplifiedChinese: LocalizedGuidanceContent(
          displayText: "不要分岔，沿都心环状线前往 霞が関 方向",
          spokenText:
            "在三宅坂 JCT不要分岔，沿都心环状线继续前往 霞が関 方向",
          spokenForms: ["霞が関": "霞が関"],
          preservedJapaneseSignText: "霞が関"
        ),
        .english: LocalizedGuidanceContent(
          displayText: "Stay on the Inner Circular Route toward 霞が関",
          spokenText:
            "At Miyakezaka JCT, stay on the Inner Circular Route toward 霞が関",
          spokenForms: ["Inner Circular Route": "Inner Circular Route"],
          preservedJapaneseSignText: "霞が関"
        ),
      ],
      // A keep-going advisory is useful before the diverging ramp, not at
      // its nose, so it commits earlier than a branch instruction.
      commitTriggerDistanceMeters: 300,
      checkedAt: "2026-08-11",
      expectedJunctionDetailSHA256:
        "a4b648d1710a6658750171468b86d14d"
        + "f4c86d6031841135fddd87e7e2610c71",
      sources: [
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/jct/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-c1/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-4/"
        ),
        ShutoJunctionGuidanceSource(
          url:
            "https://www.shutoko.jp/-/media/images/responsive/"
            + "customer/use/network/jct/routeguide/jct_miyakezaka",
          contentSHA256:
            "a4b648d1710a6658750171468b86d14d"
            + "f4c86d6031841135fddd87e7e2610c71"
        ),
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.miyakezaka.c1-inner-to-4-outbound",
      junctionID: "shuto.jct.jct_miyakezaka",
      junctionNodeID: 255_513_709,
      incomingEdgeID: "osm.24402540.6.forward",
      outgoingEdgeID: "osm.24402503.0.forward",
      incomingRouteID: "C1",
      incomingDirectionJA: "内回り",
      outgoingRouteID: "4",
      outgoingDirectionJA: "下り",
      branchSide: .left,
      japaneseSignText: "新宿・中央道",
      routeShields: ["4", "E20"],
      junctionNameJA: "三宅坂JCT",
      junctionNameZH: "三宅坂 JCT",
      junctionNameEN: "Miyakezaka JCT",
      destinationJA: "4号新宿線 新宿・中央道方面",
      destinationZH: "4号新宿线 新宿・中央道方向",
      destinationEN: "Route 4 toward Shinjuku and the Chuo Expressway",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "a4b648d1710a6658750171468b86d14d"
        + "f4c86d6031841135fddd87e7e2610c71",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_miyakezaka",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c1/",
        "https://www.shutoko.jp/use/network/map/route-4/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.miyakezaka.4-inbound-to-c1-outer",
      junctionID: "shuto.jct.jct_miyakezaka",
      junctionNodeID: 573_233_876,
      incomingEdgeID: "osm.24636595.7.forward",
      outgoingEdgeID: "osm.24636434.0.forward",
      incomingRouteID: "4",
      incomingDirectionJA: "上り",
      outgoingRouteID: "C1",
      outgoingDirectionJA: "外回り",
      branchSide: .left,
      japaneseSignText: "神田橋・箱崎",
      routeShields: ["C1", "5", "6"],
      junctionNameJA: "三宅坂JCT",
      junctionNameZH: "三宅坂 JCT",
      junctionNameEN: "Miyakezaka JCT",
      destinationJA: "都心環状線 神田橋・箱崎方面",
      destinationZH: "都心环状线 神田桥・箱崎方向",
      destinationEN: "the Outer Circular Route toward Kandabashi and Hakozaki",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "a4b648d1710a6658750171468b86d14d"
        + "f4c86d6031841135fddd87e7e2610c71",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_miyakezaka",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c1/",
        "https://www.shutoko.jp/use/network/map/route-4/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.miyakezaka.4-inbound-to-c1-inner",
      junctionID: "shuto.jct.jct_miyakezaka",
      junctionNodeID: 573_233_876,
      incomingEdgeID: "osm.24636595.7.forward",
      outgoingEdgeID: "osm.24636612.0.forward",
      incomingRouteID: "4",
      incomingDirectionJA: "上り",
      outgoingRouteID: "4",
      outgoingDirectionJA: "上り",
      branchSide: .right,
      japaneseSignText: "霞ヶ関・湾岸線",
      routeShields: ["C1"],
      junctionNameJA: "三宅坂JCT",
      junctionNameZH: "三宅坂 JCT",
      junctionNameEN: "Miyakezaka JCT",
      destinationJA: "都心環状線 霞ヶ関・湾岸線方面",
      destinationZH: "都心环状线 霞关・湾岸线方向",
      destinationEN: "the Inner Circular Route toward Kasumigaseki and the Bayshore Route",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "a4b648d1710a6658750171468b86d14d"
        + "f4c86d6031841135fddd87e7e2610c71",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_miyakezaka",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c1/",
        "https://www.shutoko.jp/use/network/map/route-4/",
      ]
    ),
    ShutoJunctionMovementDefinition(
      id: "shuto.jct.takehashi.c1-inner-stays-on-c1",
      networkSnapshotID:
        "shuto-official-2026-07-29-osm-2026-08-04",
      junctionID: "shuto.jct.jct_takehashi",
      junctionNodeID: 264_871_735,
      incomingEdgeID: "osm.1545541219.7.forward",
      outgoingEdgeID: "osm.44779774.0.forward",
      incomingRouteID: "C1",
      incomingDirectionJA: "内回り",
      outgoingRouteID: "C1",
      outgoingDirectionJA: "内回り",
      // The operator diagram shows the Inner Circular continuation on a
      // straight arrow and 5号池袋線 on a diverging arrow, so this
      // movement keeps the mainline and asserts no lane.
      branchSide: .straight,
      japaneseSignText: "霞が関",
      routeShields: ["C1"],
      laneGuidanceState: .notReleased,
      localizedJunctionNames: [
        .japanese: "竹橋JCT",
        .simplifiedChinese: "竹桥 JCT",
        .english: "Takehashi JCT",
      ],
      localizedContent: [
        .japanese: LocalizedGuidanceContent(
          displayText: "分岐せず、都心環状線 霞が関方面へ",
          spokenText:
            "竹橋ジャンクションは分岐せず、都心環状線 霞が関方面へ進んでください",
          spokenForms: [
            "都心環状線": "としんかんじょうせん",
            "霞が関": "かすみがせき",
            "竹橋": "たけはし",
          ],
          preservedJapaneseSignText: "霞が関"
        ),
        .simplifiedChinese: LocalizedGuidanceContent(
          displayText: "不要分岔，沿都心环状线前往 霞が関 方向",
          spokenText:
            "在竹桥 JCT不要分岔，沿都心环状线继续前往 霞が関 方向",
          spokenForms: ["霞が関": "霞が関"],
          preservedJapaneseSignText: "霞が関"
        ),
        .english: LocalizedGuidanceContent(
          displayText: "Stay on the Inner Circular Route toward 霞が関",
          spokenText:
            "At Takehashi JCT, stay on the Inner Circular Route toward 霞が関",
          spokenForms: ["Inner Circular Route": "Inner Circular Route"],
          preservedJapaneseSignText: "霞が関"
        ),
      ],
      // A keep-going advisory is useful before the diverging ramp, not at
      // its nose, so it commits earlier than a branch instruction.
      commitTriggerDistanceMeters: 300,
      checkedAt: "2026-08-11",
      expectedJunctionDetailSHA256:
        "1c1d2a5ebd879002c6053bf0e556f752"
        + "6d068350cd0ee798a370e23389a97ded",
      sources: [
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/jct/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-c1/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-5/"
        ),
        ShutoJunctionGuidanceSource(
          url:
            "https://www.shutoko.jp/-/media/images/responsive/"
            + "customer/use/network/jct/routeguide/jct_takehashi",
          contentSHA256:
            "1c1d2a5ebd879002c6053bf0e556f752"
            + "6d068350cd0ee798a370e23389a97ded"
        ),
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.hamasakibashi.c1-outer-stays-on-c1",
      junctionID: "shuto.jct.jct_hamasakibashi",
      junctionNodeID: 3_218_329_762,
      incomingEdgeID: "osm.316213219.28.forward",
      outgoingEdgeID: "osm.23580153.0.forward",
      incomingRouteID: "C1",
      incomingDirectionJA: "外回り",
      outgoingRouteID: "C1",
      outgoingDirectionJA: "外回り",
      branchSide: .straight,
      japaneseSignText: "芝公園",
      routeShields: ["C1"],
      junctionNameJA: "浜崎橋JCT",
      junctionNameZH: "浜崎桥 JCT",
      junctionNameEN: "Hamasakibashi JCT",
      destinationJA: "都心環状線 芝公園方面",
      destinationZH: "都心环状线 芝公园方向",
      destinationEN: "the Outer Circular Route toward Shiba Park",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "9991505f52afb8f1d4c7f9ee46956daa4"
        + "afad92c55bfb9cc6ccc5cafd2ab82c7",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_hamasakibashi",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c1/",
        "https://www.shutoko.jp/use/network/map/route-1/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.ichinohashi.c1-outer-stays-on-c1",
      junctionID: "shuto.jct.jct_ichinohashi",
      junctionNodeID: 31_297_000,
      incomingEdgeID: "osm.24039737.3.forward",
      outgoingEdgeID: "osm.24039737.4.forward",
      incomingRouteID: "C1",
      incomingDirectionJA: "外回り",
      outgoingRouteID: "C1",
      outgoingDirectionJA: "外回り",
      branchSide: .straight,
      japaneseSignText: "渋谷・新宿",
      routeShields: ["C1"],
      junctionNameJA: "一ノ橋JCT",
      junctionNameZH: "一之桥 JCT",
      junctionNameEN: "Ichinohashi JCT",
      destinationJA: "都心環状線 渋谷・新宿方面",
      destinationZH: "都心环状线 涩谷・新宿方向",
      destinationEN: "the Outer Circular Route toward Shibuya and Shinjuku",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "f56355b8bf55596a73adc91f8fa2c83a"
        + "f02ace3089843c63fd7c7b469db7d34d",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_ichinohashi",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c1/",
        "https://www.shutoko.jp/use/network/map/route-2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.tanimachi.c1-outer-stays-on-c1",
      junctionID: "shuto.jct.jct_tanimachi",
      junctionNodeID: 260_710_778,
      incomingEdgeID: "osm.895902565.2.forward",
      outgoingEdgeID: "osm.243206476.0.forward",
      incomingRouteID: "C1",
      incomingDirectionJA: "外回り",
      outgoingRouteID: "C1",
      outgoingDirectionJA: "外回り",
      branchSide: .straight,
      japaneseSignText: "中央道・北池袋",
      routeShields: ["C1"],
      junctionNameJA: "谷町JCT",
      junctionNameZH: "谷町 JCT",
      junctionNameEN: "Tanimachi JCT",
      destinationJA: "都心環状線 中央道・北池袋方面",
      destinationZH: "都心环状线 中央道・北池袋方向",
      destinationEN:
        "the Outer Circular Route toward the Chuo Expressway and Kita-Ikebukuro",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "b7f8b5458757c825d2abf42f315bdb7d"
        + "60e54debbb8a7420f49dd8a4646940fd",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_tanimachi",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c1/",
        "https://www.shutoko.jp/use/network/map/route-3/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.tanimachi.c1-outer-to-3-outbound",
      junctionID: "shuto.jct.jct_tanimachi",
      junctionNodeID: 260_710_778,
      incomingEdgeID: "osm.895902565.2.forward",
      outgoingEdgeID: "osm.24336502.0.forward",
      incomingRouteID: "C1",
      incomingDirectionJA: "外回り",
      outgoingRouteID: "3",
      outgoingDirectionJA: "下り",
      branchSide: .left,
      japaneseSignText: "東名・渋谷",
      routeShields: ["3", "E1"],
      junctionNameJA: "谷町JCT",
      junctionNameZH: "谷町 JCT",
      junctionNameEN: "Tanimachi JCT",
      destinationJA: "3号渋谷線 東名・渋谷方面",
      destinationZH: "3号涩谷线 东名・涩谷方向",
      destinationEN: "Route 3 toward Shibuya and the Tomei Expressway",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "b7f8b5458757c825d2abf42f315bdb7d"
        + "60e54debbb8a7420f49dd8a4646940fd",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_tanimachi",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c1/",
        "https://www.shutoko.jp/use/network/map/route-3/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.ichinohashi.c1-outer-to-2-outbound",
      junctionID: "shuto.jct.jct_ichinohashi",
      junctionNodeID: 31_297_000,
      incomingEdgeID: "osm.24039737.3.forward",
      outgoingEdgeID: "osm.4853805.0.forward",
      incomingRouteID: "C1",
      incomingDirectionJA: "外回り",
      outgoingRouteID: "2",
      outgoingDirectionJA: "下り",
      branchSide: .left,
      japaneseSignText: "目黒",
      routeShields: ["2"],
      junctionNameJA: "一ノ橋JCT",
      junctionNameZH: "一之桥 JCT",
      junctionNameEN: "Ichinohashi JCT",
      destinationJA: "2号目黒線 目黒方面",
      destinationZH: "2号目黑线 目黑方向",
      destinationEN: "Route 2 toward Meguro",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "f56355b8bf55596a73adc91f8fa2c83a"
        + "f02ace3089843c63fd7c7b469db7d34d",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_ichinohashi",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c1/",
        "https://www.shutoko.jp/use/network/map/route-2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.ichinohashi.c1-inner-to-2-outbound",
      junctionID: "shuto.jct.jct_ichinohashi",
      junctionNodeID: 574_460_605,
      incomingEdgeID: "osm.23297444.19.forward",
      outgoingEdgeID: "osm.45248411.0.forward",
      incomingRouteID: "C1",
      incomingDirectionJA: "内回り",
      outgoingRouteID: "2",
      outgoingDirectionJA: "下り",
      branchSide: .right,
      japaneseSignText: "目黒",
      routeShields: ["2"],
      junctionNameJA: "一ノ橋JCT",
      junctionNameZH: "一之桥 JCT",
      junctionNameEN: "Ichinohashi JCT",
      destinationJA: "2号目黒線 目黒方面",
      destinationZH: "2号目黑线 目黑方向",
      destinationEN: "Route 2 toward Meguro",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "f56355b8bf55596a73adc91f8fa2c83a"
        + "f02ace3089843c63fd7c7b469db7d34d",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_ichinohashi",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c1/",
        "https://www.shutoko.jp/use/network/map/route-2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.ichinohashi.2-inbound-to-c1-outer",
      junctionID: "shuto.jct.jct_ichinohashi",
      junctionNodeID: 574_460_620,
      incomingEdgeID: "osm.7836679.9.forward",
      outgoingEdgeID: "osm.4853802.0.forward",
      incomingRouteID: "2",
      incomingDirectionJA: "上り",
      outgoingRouteID: "2",
      outgoingDirectionJA: "上り",
      branchSide: .left,
      japaneseSignText: "北池袋・新宿",
      routeShields: ["C1", "3", "4", "5"],
      junctionNameJA: "一ノ橋JCT",
      junctionNameZH: "一之桥 JCT",
      junctionNameEN: "Ichinohashi JCT",
      destinationJA: "都心環状線 北池袋・新宿方面",
      destinationZH: "都心环状线 北池袋・新宿方向",
      destinationEN: "the Outer Circular Route toward Kita-Ikebukuro and Shinjuku",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "f56355b8bf55596a73adc91f8fa2c83a"
        + "f02ace3089843c63fd7c7b469db7d34d",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_ichinohashi",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c1/",
        "https://www.shutoko.jp/use/network/map/route-2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.ichinohashi.2-inbound-to-c1-inner",
      junctionID: "shuto.jct.jct_ichinohashi",
      junctionNodeID: 574_460_620,
      incomingEdgeID: "osm.7836679.9.forward",
      outgoingEdgeID: "osm.4853804.0.forward",
      incomingRouteID: "2",
      incomingDirectionJA: "上り",
      outgoingRouteID: "2",
      outgoingDirectionJA: "上り",
      branchSide: .right,
      japaneseSignText: "湾岸線・銀座",
      routeShields: ["C1", "1", "11", "6"],
      junctionNameJA: "一ノ橋JCT",
      junctionNameZH: "一之桥 JCT",
      junctionNameEN: "Ichinohashi JCT",
      destinationJA: "都心環状線 湾岸線・銀座方面",
      destinationZH: "都心环状线 湾岸线・银座方向",
      destinationEN: "the Inner Circular Route toward the Bayshore Route and Ginza",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "f56355b8bf55596a73adc91f8fa2c83a"
        + "f02ace3089843c63fd7c7b469db7d34d",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_ichinohashi",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c1/",
        "https://www.shutoko.jp/use/network/map/route-2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.takehashi.c1-outer-to-5-outbound",
      junctionID: "shuto.jct.jct_takehashi",
      junctionNodeID: 263_987_757,
      incomingEdgeID: "osm.24039773.1.forward",
      outgoingEdgeID: "osm.24334770.0.forward",
      incomingRouteID: "C1",
      incomingDirectionJA: "外回り",
      outgoingRouteID: "5",
      outgoingDirectionJA: "下り",
      branchSide: .left,
      japaneseSignText: "北池袋・関越道",
      routeShields: ["5", "E17"],
      junctionNameJA: "竹橋JCT",
      junctionNameZH: "竹桥 JCT",
      junctionNameEN: "Takehashi JCT",
      destinationJA: "5号池袋線 北池袋・関越道方面",
      destinationZH: "5号池袋线 北池袋・关越道方向",
      destinationEN: "Route 5 toward Kita-Ikebukuro and the Kan-Etsu Expressway",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "1c1d2a5ebd879002c6053bf0e556f752"
        + "6d068350cd0ee798a370e23389a97ded",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_takehashi",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c1/",
        "https://www.shutoko.jp/use/network/map/route-5/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.takehashi.c1-inner-to-5-outbound",
      junctionID: "shuto.jct.jct_takehashi",
      junctionNodeID: 264_871_735,
      incomingEdgeID: "osm.1545541219.7.forward",
      outgoingEdgeID: "osm.1421966435.0.forward",
      incomingRouteID: "C1",
      incomingDirectionJA: "内回り",
      outgoingRouteID: "5",
      outgoingDirectionJA: "下り",
      branchSide: .right,
      japaneseSignText: "北池袋・関越道",
      routeShields: ["5", "E17"],
      junctionNameJA: "竹橋JCT",
      junctionNameZH: "竹桥 JCT",
      junctionNameEN: "Takehashi JCT",
      destinationJA: "5号池袋線 北池袋・関越道方面",
      destinationZH: "5号池袋线 北池袋・关越道方向",
      destinationEN: "Route 5 toward Kita-Ikebukuro and the Kan-Etsu Expressway",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "1c1d2a5ebd879002c6053bf0e556f752"
        + "6d068350cd0ee798a370e23389a97ded",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_takehashi",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c1/",
        "https://www.shutoko.jp/use/network/map/route-5/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.takehashi.5-inbound-to-c1-outer",
      junctionID: "shuto.jct.jct_takehashi",
      junctionNodeID: 252_174_819,
      incomingEdgeID: "osm.23681223.222.forward",
      outgoingEdgeID: "osm.23681223.223.forward",
      incomingRouteID: "5",
      incomingDirectionJA: "上り",
      outgoingRouteID: "5",
      outgoingDirectionJA: "上り",
      branchSide: .left,
      japaneseSignText: "神田橋・箱崎",
      routeShields: ["C1", "6"],
      junctionNameJA: "竹橋JCT",
      junctionNameZH: "竹桥 JCT",
      junctionNameEN: "Takehashi JCT",
      destinationJA: "都心環状線 神田橋・箱崎方面",
      destinationZH: "都心环状线 神田桥・箱崎方向",
      destinationEN: "the Outer Circular Route toward Kandabashi and Hakozaki",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "1c1d2a5ebd879002c6053bf0e556f752"
        + "6d068350cd0ee798a370e23389a97ded",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_takehashi",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c1/",
        "https://www.shutoko.jp/use/network/map/route-5/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.takehashi.5-inbound-to-c1-inner",
      junctionID: "shuto.jct.jct_takehashi",
      junctionNodeID: 252_174_819,
      incomingEdgeID: "osm.23681223.222.forward",
      outgoingEdgeID: "osm.955398790.0.forward",
      incomingRouteID: "5",
      incomingDirectionJA: "上り",
      outgoingRouteID: "5",
      outgoingDirectionJA: "上り",
      branchSide: .right,
      japaneseSignText: "霞が関・中央道",
      routeShields: ["C1", "3", "4", "E20"],
      junctionNameJA: "竹橋JCT",
      junctionNameZH: "竹桥 JCT",
      junctionNameEN: "Takehashi JCT",
      destinationJA: "都心環状線 霞が関・中央道方面",
      destinationZH: "都心环状线 霞关・中央道方向",
      destinationEN: "the Inner Circular Route toward Kasumigaseki and the Chuo Expressway",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "1c1d2a5ebd879002c6053bf0e556f752"
        + "6d068350cd0ee798a370e23389a97ded",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_takehashi",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c1/",
        "https://www.shutoko.jp/use/network/map/route-5/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.miyakezaka.c1-outer-stays-on-c1",
      junctionID: "shuto.jct.jct_miyakezaka",
      junctionNodeID: 260_710_800,
      incomingEdgeID: "osm.45392984.0.forward",
      outgoingEdgeID: "osm.333682073.0.forward",
      incomingRouteID: "C1",
      incomingDirectionJA: "外回り",
      outgoingRouteID: "C1",
      outgoingDirectionJA: "外回り",
      branchSide: .straight,
      japaneseSignText: "神田橋・北池袋",
      routeShields: ["C1"],
      junctionNameJA: "三宅坂JCT",
      junctionNameZH: "三宅坂 JCT",
      junctionNameEN: "Miyakezaka JCT",
      destinationJA: "都心環状線 神田橋・北池袋方面",
      destinationZH: "都心环状线 神田桥・北池袋方向",
      destinationEN:
        "the Outer Circular Route toward Kandabashi and Kita-Ikebukuro",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "a4b648d1710a6658750171468b86d14d"
        + "f4c86d6031841135fddd87e7e2610c71",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_miyakezaka",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c1/",
        "https://www.shutoko.jp/use/network/map/route-4/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.takehashi.c1-outer-stays-on-c1",
      junctionID: "shuto.jct.jct_takehashi",
      junctionNodeID: 263_987_757,
      incomingEdgeID: "osm.24039773.1.forward",
      outgoingEdgeID: "osm.24039773.2.forward",
      incomingRouteID: "C1",
      incomingDirectionJA: "外回り",
      outgoingRouteID: "C1",
      outgoingDirectionJA: "外回り",
      branchSide: .straight,
      japaneseSignText: "神田橋・箱崎",
      routeShields: ["C1"],
      junctionNameJA: "竹橋JCT",
      junctionNameZH: "竹桥 JCT",
      junctionNameEN: "Takehashi JCT",
      destinationJA: "都心環状線 神田橋・箱崎方面",
      destinationZH: "都心环状线 神田桥・箱崎方向",
      destinationEN:
        "the Outer Circular Route toward Kandabashi and Hakozaki",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "1c1d2a5ebd879002c6053bf0e556f752"
        + "6d068350cd0ee798a370e23389a97ded",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_takehashi",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c1/",
        "https://www.shutoko.jp/use/network/map/route-5/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.edobashi.c1-outer-stays-on-c1",
      junctionID: "shuto.jct.jct_edobashi",
      junctionNodeID: 256_426_172,
      incomingEdgeID: "osm.316185365.6.forward",
      outgoingEdgeID: "osm.44779562.0.forward",
      incomingRouteID: "C1",
      incomingDirectionJA: "外回り",
      outgoingRouteID: "C1",
      outgoingDirectionJA: "外回り",
      branchSide: .straight,
      japaneseSignText: "羽田・銀座",
      routeShields: ["C1"],
      junctionNameJA: "江戸橋JCT",
      junctionNameZH: "江户桥 JCT",
      junctionNameEN: "Edobashi JCT",
      destinationJA: "都心環状線 羽田・銀座方面",
      destinationZH: "都心环状线 羽田・银座方向",
      destinationEN: "the Outer Circular Route toward Haneda and Ginza",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "a855321a4dbf059131cada07f5dfd0e0"
        + "73762b063034053807b25001956db975",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_edobashi",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c1/",
        "https://www.shutoko.jp/use/network/map/route-6/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.edobashi.c1-outer-to-6-outbound",
      junctionID: "shuto.jct.jct_edobashi",
      junctionNodeID: 256_426_172,
      incomingEdgeID: "osm.316185365.6.forward",
      outgoingEdgeID: "osm.44803854.0.forward",
      incomingRouteID: "C1",
      incomingDirectionJA: "外回り",
      outgoingRouteID: "6_MUKOJIMA",
      outgoingDirectionJA: "下り",
      branchSide: .left,
      japaneseSignText: "箱崎・常磐道",
      routeShields: ["6", "E6"],
      junctionNameJA: "江戸橋JCT",
      junctionNameZH: "江户桥 JCT",
      junctionNameEN: "Edobashi JCT",
      destinationJA: "6号向島線 箱崎・常磐道方面",
      destinationZH: "6号向岛线 箱崎・常磐道方向",
      destinationEN: "Route 6 toward Hakozaki and the Joban Expressway",
      expectedJunctionDetailSHA256:
        "a855321a4dbf059131cada07f5dfd0e0"
        + "73762b063034053807b25001956db975",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_edobashi",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/edobashi_hakozaki/",
        "https://www.shutoko.jp/use/network/map/route-c1/",
        "https://www.shutoko.jp/use/network/map/route-6/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.edobashi.c1-inner-to-6-outbound",
      junctionID: "shuto.jct.jct_edobashi",
      junctionNodeID: 264_871_771,
      incomingEdgeID: "osm.41009552.1.forward",
      outgoingEdgeID: "osm.44804643.0.forward",
      incomingRouteID: "C1",
      incomingDirectionJA: "内回り",
      outgoingRouteID: "6_MUKOJIMA",
      outgoingDirectionJA: "下り",
      branchSide: .right,
      japaneseSignText: "上野",
      routeShields: ["1"],
      junctionNameJA: "江戸橋JCT",
      junctionNameZH: "江户桥 JCT",
      junctionNameEN: "Edobashi JCT",
      destinationJA: "上野方面",
      destinationZH: "上野方向",
      destinationEN: "Ueno",
      expectedJunctionDetailSHA256:
        "a855321a4dbf059131cada07f5dfd0e0"
        + "73762b063034053807b25001956db975",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_edobashi",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/edobashi_hakozaki/",
        "https://www.shutoko.jp/use/network/map/route-c1/",
        "https://www.shutoko.jp/use/network/map/route-1u/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.edobashi.6-inbound-toward-ginza",
      junctionID: "shuto.jct.jct_edobashi",
      junctionNodeID: 499_275_976,
      incomingEdgeID: "osm.44805858.19.forward",
      outgoingEdgeID: "osm.40971852.0.forward",
      incomingRouteID: "6_MUKOJIMA",
      incomingDirectionJA: "上り",
      outgoingRouteID: "1_UENO",
      outgoingDirectionJA: "上り",
      branchSide: .left,
      maneuverJA: "左方向を保ち",
      maneuverZH: "保持左侧",
      maneuverEN: "keep left",
      japaneseSignText: "銀座・横浜",
      routeShields: ["C1", "7"],
      junctionNameJA: "江戸橋JCT",
      junctionNameZH: "江户桥 JCT",
      junctionNameEN: "Edobashi JCT",
      destinationJA: "都心環状線 銀座・横浜方面",
      destinationZH: "都心环状线 银座・横滨方向",
      destinationEN: "the Inner Circular Route toward Ginza and Yokohama",
      expectedJunctionDetailSHA256:
        "a855321a4dbf059131cada07f5dfd0e0"
        + "73762b063034053807b25001956db975",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_edobashi",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c1/",
        "https://www.shutoko.jp/use/network/map/route-1u/",
        "https://www.shutoko.jp/use/network/map/route-6/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.edobashi.6-inbound-toward-kandabashi",
      junctionID: "shuto.jct.jct_edobashi",
      junctionNodeID: 499_275_976,
      incomingEdgeID: "osm.44805858.19.forward",
      outgoingEdgeID: "osm.44803855.0.forward",
      incomingRouteID: "6_MUKOJIMA",
      incomingDirectionJA: "上り",
      outgoingRouteID: "6_MUKOJIMA",
      outgoingDirectionJA: "上り",
      branchSide: .right,
      maneuverJA: "右方向を保ち",
      maneuverZH: "保持右侧",
      maneuverEN: "keep right",
      japaneseSignText: "神田橋・北池袋・中央道",
      routeShields: ["C1", "5", "E20"],
      junctionNameJA: "江戸橋JCT",
      junctionNameZH: "江户桥 JCT",
      junctionNameEN: "Edobashi JCT",
      destinationJA: "神田橋・北池袋・中央道方面",
      destinationZH: "神田橋・北池袋・中央道方向",
      destinationEN: "Kandabashi, Kita-ikebukuro, and the Chuo Expressway",
      expectedJunctionDetailSHA256:
        "a855321a4dbf059131cada07f5dfd0e0"
        + "73762b063034053807b25001956db975",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_edobashi",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c1/",
        "https://www.shutoko.jp/use/network/map/route-5/",
        "https://www.shutoko.jp/use/network/map/route-6/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.hakozaki.6-outbound-to-9-primary",
      junctionID: "shuto.jct.jct_hakozaki",
      junctionNodeID: 568_090_177,
      incomingEdgeID: "osm.28194421.7.forward",
      outgoingEdgeID: "osm.44804029.0.forward",
      incomingRouteID: "6_MUKOJIMA",
      incomingDirectionJA: "下り",
      outgoingRouteID: "9",
      outgoingDirectionJA: "下り",
      branchSide: .straight,
      maneuverJA: "青色の案内に従い",
      maneuverZH: "沿蓝色引导行驶",
      maneuverEN: "follow the blue route marking",
      japaneseSignText: "9・湾岸線",
      routeShields: ["9", "B"],
      junctionNameJA: "箱崎JCT",
      junctionNameZH: "箱崎 JCT",
      junctionNameEN: "Hakozaki JCT",
      destinationJA: "9号深川線・湾岸線方面",
      destinationZH: "9号深川线・湾岸线方向",
      destinationEN: "Route 9 and the Bayshore Route",
      commitTriggerDistanceMeters: 500,
      expectedJunctionDetailSHA256:
        "49f645e5cf96c1be9e7003e857d2cf4b"
        + "aed0c502daaca7b7469c41d1e8f43373",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_hakozaki",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/edobashi_hakozaki/",
        "https://www.shutoko.jp/use/network/map/route-6/",
        "https://www.shutoko.jp/use/network/map/route-9/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.hakozaki.6-outbound-to-9-secondary",
      junctionID: "shuto.jct.jct_hakozaki",
      junctionNodeID: 568_090_177,
      incomingEdgeID: "osm.28194421.7.forward",
      outgoingEdgeID: "osm.44804208.0.forward",
      incomingRouteID: "6_MUKOJIMA",
      incomingDirectionJA: "下り",
      outgoingRouteID: "9",
      outgoingDirectionJA: "下り",
      branchSide: .straight,
      maneuverJA: "青色の案内に従い",
      maneuverZH: "沿蓝色引导行驶",
      maneuverEN: "follow the blue route marking",
      japaneseSignText: "9・湾岸線",
      routeShields: ["9", "B"],
      junctionNameJA: "箱崎JCT",
      junctionNameZH: "箱崎 JCT",
      junctionNameEN: "Hakozaki JCT",
      destinationJA: "9号深川線・湾岸線方面",
      destinationZH: "9号深川线・湾岸线方向",
      destinationEN: "Route 9 and the Bayshore Route",
      commitTriggerDistanceMeters: 500,
      expectedJunctionDetailSHA256:
        "49f645e5cf96c1be9e7003e857d2cf4b"
        + "aed0c502daaca7b7469c41d1e8f43373",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_hakozaki",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/edobashi_hakozaki/",
        "https://www.shutoko.jp/use/network/map/route-6/",
        "https://www.shutoko.jp/use/network/map/route-9/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.hakozaki.6-outbound-stays-on-6",
      junctionID: "shuto.jct.jct_hakozaki",
      junctionNodeID: 568_090_177,
      incomingEdgeID: "osm.28194421.7.forward",
      outgoingEdgeID: "osm.44805851.0.forward",
      incomingRouteID: "6_MUKOJIMA",
      incomingDirectionJA: "下り",
      outgoingRouteID: "6_MUKOJIMA",
      outgoingDirectionJA: "下り",
      branchSide: .straight,
      maneuverJA: "赤色の案内に従い",
      maneuverZH: "沿红色引导行驶",
      maneuverEN: "follow the red route marking",
      japaneseSignText: "6 常磐道・7 京葉道路",
      routeShields: ["6", "E6", "7", "E14"],
      junctionNameJA: "箱崎JCT",
      junctionNameZH: "箱崎 JCT",
      junctionNameEN: "Hakozaki JCT",
      destinationJA: "6号向島線・7号小松川線方面",
      destinationZH: "6号向岛线・7号小松川线方向",
      destinationEN: "Routes 6 and 7",
      commitTriggerDistanceMeters: 500,
      expectedJunctionDetailSHA256:
        "49f645e5cf96c1be9e7003e857d2cf4b"
        + "aed0c502daaca7b7469c41d1e8f43373",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_hakozaki",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/edobashi_hakozaki/",
        "https://www.shutoko.jp/use/network/map/route-6/",
        "https://www.shutoko.jp/use/network/map/route-7/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.hakozaki.6-inbound-to-9-outbound",
      junctionID: "shuto.jct.jct_hakozaki",
      junctionNodeID: 565_480_310,
      incomingEdgeID: "osm.1544854472.1.forward",
      outgoingEdgeID: "osm.44804206.0.forward",
      incomingRouteID: "6_MUKOJIMA",
      incomingDirectionJA: "上り",
      outgoingRouteID: "9",
      outgoingDirectionJA: "下り",
      branchSide: .left,
      japaneseSignText: "湾岸線・東関東道",
      routeShields: ["9", "B"],
      junctionNameJA: "箱崎JCT",
      junctionNameZH: "箱崎 JCT",
      junctionNameEN: "Hakozaki JCT",
      destinationJA: "9号深川線 湾岸線・東関東道方面",
      destinationZH: "9号深川线 湾岸线・东关东道方向",
      destinationEN: "Route 9 toward the Bayshore Route",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "49f645e5cf96c1be9e7003e857d2cf4b"
        + "aed0c502daaca7b7469c41d1e8f43373",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_hakozaki",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/edobashi_hakozaki/",
        "https://www.shutoko.jp/use/network/map/route-6/",
        "https://www.shutoko.jp/use/network/map/route-9/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.hakozaki.6-inbound-toward-ginza",
      junctionID: "shuto.jct.jct_hakozaki",
      junctionNodeID: 565_480_310,
      incomingEdgeID: "osm.1544854472.1.forward",
      outgoingEdgeID: "osm.876405654.0.forward",
      incomingRouteID: "6_MUKOJIMA",
      incomingDirectionJA: "上り",
      outgoingRouteID: "6_MUKOJIMA",
      outgoingDirectionJA: "上り",
      branchSide: .right,
      japaneseSignText: "銀座",
      routeShields: ["C1"],
      junctionNameJA: "箱崎JCT",
      junctionNameZH: "箱崎 JCT",
      junctionNameEN: "Hakozaki JCT",
      destinationJA: "都心環状線 銀座方面",
      destinationZH: "都心环状线 银座方向",
      destinationEN: "the Inner Circular Route toward Ginza",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "49f645e5cf96c1be9e7003e857d2cf4b"
        + "aed0c502daaca7b7469c41d1e8f43373",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_hakozaki",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c1/",
        "https://www.shutoko.jp/use/network/map/route-6/",
      ]
    ),
    ShutoJunctionMovementDefinition(
      id: "shuto.jct.tatsumi.b-westbound-stays-on-b",
      networkSnapshotID:
        "shuto-official-2026-07-29-osm-2026-08-04",
      junctionID: "shuto.jct.jct_tatsumi",
      junctionNodeID: 31_300_491,
      incomingEdgeID: "osm.888066409.1.forward",
      outgoingEdgeID: "osm.679272067.0.forward",
      incomingRouteID: "B",
      incomingDirectionJA: "西行き",
      outgoingRouteID: "B",
      outgoingDirectionJA: "西行き",
      // The operator diagram shows the Bayshore continuation on a straight
      // arrow and 9号深川線 on a diverging arrow, so this movement
      // keeps the mainline and asserts no lane.
      branchSide: .straight,
      japaneseSignText: "横浜",
      routeShields: ["B"],
      laneGuidanceState: .notReleased,
      localizedJunctionNames: [
        .japanese: "辰巳JCT",
        .simplifiedChinese: "辰巳 JCT",
        .english: "Tatsumi JCT",
      ],
      localizedContent: [
        .japanese: LocalizedGuidanceContent(
          displayText: "分岐せず、湾岸線 横浜方面へ",
          spokenText:
            "辰巳ジャンクションは分岐せず、湾岸線 横浜方面へ進んでください",
          spokenForms: [
            "湾岸線": "わんがんせん",
            "横浜": "よこはま",
            "辰巳": "たつみ",
          ],
          preservedJapaneseSignText: "横浜"
        ),
        .simplifiedChinese: LocalizedGuidanceContent(
          displayText: "不要分岔，沿湾岸线前往 横浜 方向",
          spokenText:
            "在辰巳 JCT不要分岔，沿湾岸线继续前往 横浜 方向",
          spokenForms: ["横浜": "横浜"],
          preservedJapaneseSignText: "横浜"
        ),
        .english: LocalizedGuidanceContent(
          displayText: "Stay on the Bayshore Route toward 横浜",
          spokenText:
            "At Tatsumi JCT, stay on the Bayshore Route toward 横浜",
          spokenForms: ["Bayshore Route": "Bayshore Route"],
          preservedJapaneseSignText: "横浜"
        ),
      ],
      commitTriggerDistanceMeters: 300,
      checkedAt: "2026-08-11",
      expectedJunctionDetailSHA256:
        "c4ea23ea7741c0f9f54b875e62b04825"
        + "6501d7df8aac183ce8961d2eaf1b3dda",
      sources: [
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/jct/"
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
      id: "shuto.jct.shinonome.b-westbound-stays-on-b",
      networkSnapshotID:
        "shuto-official-2026-07-29-osm-2026-08-04",
      junctionID: "shuto.jct.jct_shinonome",
      junctionNodeID: 569_015_558,
      incomingEdgeID: "osm.678697940.1.forward",
      outgoingEdgeID: "osm.678697940.2.forward",
      incomingRouteID: "B",
      incomingDirectionJA: "西行き",
      outgoingRouteID: "B",
      outgoingDirectionJA: "西行き",
      // The operator diagram shows the Bayshore continuation on a straight
      // arrow and 10号晴海線 on a diverging arrow, so this movement
      // keeps the mainline and asserts no lane.
      branchSide: .straight,
      japaneseSignText: "横浜",
      routeShields: ["B"],
      laneGuidanceState: .notReleased,
      localizedJunctionNames: [
        .japanese: "東雲JCT",
        .simplifiedChinese: "东云 JCT",
        .english: "Shinonome JCT",
      ],
      localizedContent: [
        .japanese: LocalizedGuidanceContent(
          displayText: "分岐せず、湾岸線 横浜方面へ",
          spokenText:
            "東雲ジャンクションは分岐せず、湾岸線 横浜方面へ進んでください",
          spokenForms: [
            "湾岸線": "わんがんせん",
            "横浜": "よこはま",
            "東雲": "しののめ",
          ],
          preservedJapaneseSignText: "横浜"
        ),
        .simplifiedChinese: LocalizedGuidanceContent(
          displayText: "不要分岔，沿湾岸线前往 横浜 方向",
          spokenText:
            "在东云 JCT不要分岔，沿湾岸线继续前往 横浜 方向",
          spokenForms: ["横浜": "横浜"],
          preservedJapaneseSignText: "横浜"
        ),
        .english: LocalizedGuidanceContent(
          displayText: "Stay on the Bayshore Route toward 横浜",
          spokenText:
            "At Shinonome JCT, stay on the Bayshore Route toward 横浜",
          spokenForms: ["Bayshore Route": "Bayshore Route"],
          preservedJapaneseSignText: "横浜"
        ),
      ],
      commitTriggerDistanceMeters: 300,
      checkedAt: "2026-08-11",
      expectedJunctionDetailSHA256:
        "452e2ca3d124ec3f726b0c3643cedbbc"
        + "e3446b21e755f538b418616278cfa605",
      sources: [
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/jct/"
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
      id: "shuto.jct.ariake.b-westbound-stays-on-b",
      networkSnapshotID:
        "shuto-official-2026-07-29-osm-2026-08-04",
      junctionID: "shuto.jct.jct_ariake",
      junctionNodeID: 31_288_751,
      incomingEdgeID: "osm.1313249026.0.forward",
      outgoingEdgeID: "osm.1313249025.0.forward",
      incomingRouteID: "B",
      incomingDirectionJA: "西行き",
      outgoingRouteID: "B",
      outgoingDirectionJA: "西行き",
      // The operator diagram shows the Bayshore continuation on a straight
      // arrow and 11号台場線 on a diverging arrow, so this movement
      // keeps the mainline and asserts no lane.
      branchSide: .straight,
      japaneseSignText: "横浜",
      routeShields: ["B"],
      laneGuidanceState: .notReleased,
      localizedJunctionNames: [
        .japanese: "有明JCT",
        .simplifiedChinese: "有明 JCT",
        .english: "Ariake JCT",
      ],
      localizedContent: [
        .japanese: LocalizedGuidanceContent(
          displayText: "分岐せず、湾岸線 横浜方面へ",
          spokenText:
            "有明ジャンクションは分岐せず、湾岸線 横浜方面へ進んでください",
          spokenForms: [
            "湾岸線": "わんがんせん",
            "横浜": "よこはま",
            "有明": "ありあけ",
          ],
          preservedJapaneseSignText: "横浜"
        ),
        .simplifiedChinese: LocalizedGuidanceContent(
          displayText: "不要分岔，沿湾岸线前往 横浜 方向",
          spokenText:
            "在有明 JCT不要分岔，沿湾岸线继续前往 横浜 方向",
          spokenForms: ["横浜": "横浜"],
          preservedJapaneseSignText: "横浜"
        ),
        .english: LocalizedGuidanceContent(
          displayText: "Stay on the Bayshore Route toward 横浜",
          spokenText:
            "At Ariake JCT, stay on the Bayshore Route toward 横浜",
          spokenForms: ["Bayshore Route": "Bayshore Route"],
          preservedJapaneseSignText: "横浜"
        ),
      ],
      commitTriggerDistanceMeters: 300,
      checkedAt: "2026-08-11",
      expectedJunctionDetailSHA256:
        "0351ca02b8260a625334bc17931b57d3"
        + "5d19631b4305fab64e014daf0aad4c26",
      sources: [
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/jct/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-b/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-11/"
        ),
        ShutoJunctionGuidanceSource(
          url:
            "https://www.shutoko.jp/-/media/images/responsive/"
            + "customer/use/network/jct/routeguide/jct_ariake",
          contentSHA256:
            "0351ca02b8260a625334bc17931b57d3"
            + "5d19631b4305fab64e014daf0aad4c26"
        ),
      ]
    ),
    ShutoJunctionMovementDefinition(
      id: "shuto.jct.kasai.b-westbound-stays-on-b",
      networkSnapshotID:
        "shuto-official-2026-07-29-osm-2026-08-04",
      junctionID: "shuto.jct.jct_kasai",
      junctionNodeID: 8_256_670_336,
      incomingEdgeID: "osm.888066413.1.forward",
      outgoingEdgeID: "osm.44129629.0.forward",
      incomingRouteID: "B",
      incomingDirectionJA: "西行き",
      outgoingRouteID: "B",
      outgoingDirectionJA: "西行き",
      branchSide: .straight,
      japaneseSignText: "横浜",
      routeShields: ["B"],
      laneGuidanceState: .notReleased,
      localizedJunctionNames: [
        .japanese: "葛西JCT",
        .simplifiedChinese: "葛西 JCT",
        .english: "Kasai JCT",
      ],
      localizedContent: [
        .japanese: LocalizedGuidanceContent(
          displayText: "分岐せず、湾岸線 横浜方面へ",
          spokenText:
            "葛西ジャンクションは分岐せず、湾岸線 横浜方面へ進んでください",
          spokenForms: [
            "湾岸線": "わんがんせん",
            "横浜": "よこはま",
            "葛西": "かさい",
          ],
          preservedJapaneseSignText: "横浜"
        ),
        .simplifiedChinese: LocalizedGuidanceContent(
          displayText: "不要分岔，沿湾岸线前往 横浜 方向",
          spokenText:
            "在葛西 JCT 不要分岔，沿湾岸线继续前往 横浜 方向",
          spokenForms: ["横浜": "横浜"],
          preservedJapaneseSignText: "横浜"
        ),
        .english: LocalizedGuidanceContent(
          displayText: "Stay on the Bayshore Route toward 横浜",
          spokenText:
            "At Kasai JCT, stay on the Bayshore Route toward 横浜",
          spokenForms: ["Bayshore Route": "Bayshore Route"],
          preservedJapaneseSignText: "横浜"
        ),
      ],
      commitTriggerDistanceMeters: 300,
      checkedAt: "2026-08-15",
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
            + "infoboard/chara/cases/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-b/"
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
      id: "shuto.jct.oi.b-westbound-stays-on-b",
      networkSnapshotID:
        "shuto-official-2026-07-29-osm-2026-08-04",
      junctionID: "shuto.jct.jct_oi",
      junctionNodeID: 6_534_476_215,
      incomingEdgeID: "osm.266086991.11.forward",
      outgoingEdgeID: "osm.266086991.12.forward",
      incomingRouteID: "B",
      incomingDirectionJA: "西行き",
      outgoingRouteID: "B",
      outgoingDirectionJA: "西行き",
      // The operator diagram shows the Bayshore continuation on a straight
      // arrow and 中央環状線 on a diverging arrow, so this movement
      // keeps the mainline and asserts no lane.
      branchSide: .straight,
      japaneseSignText: "横浜",
      routeShields: ["B"],
      laneGuidanceState: .notReleased,
      localizedJunctionNames: [
        .japanese: "大井JCT",
        .simplifiedChinese: "大井 JCT",
        .english: "Oi JCT",
      ],
      localizedContent: [
        .japanese: LocalizedGuidanceContent(
          displayText: "分岐せず、湾岸線 横浜方面へ",
          spokenText:
            "大井ジャンクションは分岐せず、湾岸線 横浜方面へ進んでください",
          spokenForms: [
            "湾岸線": "わんがんせん",
            "横浜": "よこはま",
            "大井": "おおい",
          ],
          preservedJapaneseSignText: "横浜"
        ),
        .simplifiedChinese: LocalizedGuidanceContent(
          displayText: "不要分岔，沿湾岸线前往 横浜 方向",
          spokenText:
            "在大井 JCT不要分岔，沿湾岸线继续前往 横浜 方向",
          spokenForms: ["横浜": "横浜"],
          preservedJapaneseSignText: "横浜"
        ),
        .english: LocalizedGuidanceContent(
          displayText: "Stay on the Bayshore Route toward 横浜",
          spokenText:
            "At Oi JCT, stay on the Bayshore Route toward 横浜",
          spokenForms: ["Bayshore Route": "Bayshore Route"],
          preservedJapaneseSignText: "横浜"
        ),
      ],
      commitTriggerDistanceMeters: 300,
      checkedAt: "2026-08-11",
      expectedJunctionDetailSHA256:
        "4bfe3cb6117273ec547a62872b971a87"
        + "fcc944fff70b3267022888612aacfc2b",
      sources: [
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/jct/"
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
            + "customer/use/network/jct/routeguide/jct_oi",
          contentSHA256:
            "4bfe3cb6117273ec547a62872b971a87"
            + "fcc944fff70b3267022888612aacfc2b"
        ),
      ]
    ),
    ShutoJunctionMovementDefinition(
      id: "shuto.jct.tokai.b-westbound-stays-on-b",
      networkSnapshotID:
        "shuto-official-2026-07-29-osm-2026-08-04",
      junctionID: "shuto.jct.jct_tokai",
      junctionNodeID: 35_937_972,
      incomingEdgeID: "osm.45683111.1.forward",
      outgoingEdgeID: "osm.45683111.2.forward",
      incomingRouteID: "B",
      incomingDirectionJA: "西行き",
      outgoingRouteID: "B",
      outgoingDirectionJA: "西行き",
      branchSide: .straight,
      japaneseSignText: "空港中央・大黒ふ頭",
      routeShields: ["B"],
      laneGuidanceState: .notReleased,
      localizedJunctionNames: [
        .japanese: "東海JCT",
        .simplifiedChinese: "东海 JCT",
        .english: "Tokai JCT",
      ],
      localizedContent: [
        .japanese: LocalizedGuidanceContent(
          displayText: "分岐せず、湾岸線 空港中央・大黒ふ頭方面へ",
          spokenText:
            "東海ジャンクションは分岐せず、湾岸線 空港中央・大黒ふ頭方面へ進んでください",
          spokenForms: [
            "湾岸線": "わんがんせん",
            "空港中央": "くうこうちゅうおう",
            "大黒ふ頭": "だいこくふとう",
            "東海": "とうかい",
          ],
          preservedJapaneseSignText: "空港中央・大黒ふ頭"
        ),
        .simplifiedChinese: LocalizedGuidanceContent(
          displayText: "不要分岔，沿湾岸线前往 空港中央・大黒ふ頭 方向",
          spokenText:
            "在东海 JCT 不要分岔，沿湾岸线继续前往 空港中央・大黒ふ頭 方向",
          spokenForms: ["空港中央・大黒ふ頭": "空港中央・大黒ふ頭"],
          preservedJapaneseSignText: "空港中央・大黒ふ頭"
        ),
        .english: LocalizedGuidanceContent(
          displayText:
            "Stay on the Bayshore Route toward 空港中央・大黒ふ頭",
          spokenText:
            "At Tokai JCT, stay on the Bayshore Route toward 空港中央・大黒ふ頭",
          spokenForms: ["Bayshore Route": "Bayshore Route"],
          preservedJapaneseSignText: "空港中央・大黒ふ頭"
        ),
      ],
      commitTriggerDistanceMeters: 300,
      checkedAt: "2026-08-15",
      expectedJunctionDetailSHA256:
        "c3e400f7d241f86d628020e9bc8ace34"
        + "3f0d517cbdad993a5f0511443a7cd47a",
      sources: [
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/jct/"
        ),
        ShutoJunctionGuidanceSource(
          url:
            "https://www.shutoko.jp/ss/shutokodeikou/"
            + "blog/2019/11/part.html"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-b/"
        ),
        ShutoJunctionGuidanceSource(
          url:
            "https://www.shutoko.jp/-/media/images/responsive/"
            + "customer/use/network/jct/routeguide/jct_tokai",
          contentSHA256:
            "c3e400f7d241f86d628020e9bc8ace34"
            + "3f0d517cbdad993a5f0511443a7cd47a"
        ),
      ]
    ),
    ShutoJunctionMovementDefinition(
      id: "shuto.jct.kawasaki.b-westbound-stays-on-b",
      networkSnapshotID:
        "shuto-official-2026-07-29-osm-2026-08-04",
      junctionID: "shuto.jct.jct_kawasaki",
      junctionNodeID: 739_475_893,
      incomingEdgeID: "osm.5204788.17.forward",
      outgoingEdgeID: "osm.5204789.0.forward",
      incomingRouteID: "B",
      incomingDirectionJA: "西行き",
      outgoingRouteID: "B",
      outgoingDirectionJA: "西行き",
      // The operator diagram shows the Bayshore continuation on a straight
      // arrow and 神奈川6号川崎線 on a diverging arrow, so this movement
      // keeps the mainline and asserts no lane.
      branchSide: .straight,
      japaneseSignText: "横浜",
      routeShields: ["B"],
      laneGuidanceState: .notReleased,
      localizedJunctionNames: [
        .japanese: "川崎浮島JCT",
        .simplifiedChinese: "川崎浮岛 JCT",
        .english: "Kawasaki-Ukishima JCT",
      ],
      localizedContent: [
        .japanese: LocalizedGuidanceContent(
          displayText: "分岐せず、湾岸線 横浜方面へ",
          spokenText:
            "川崎浮島ジャンクションは分岐せず、湾岸線 横浜方面へ進んでください",
          spokenForms: [
            "湾岸線": "わんがんせん",
            "横浜": "よこはま",
            "川崎浮島": "かわさきうきしま",
          ],
          preservedJapaneseSignText: "横浜"
        ),
        .simplifiedChinese: LocalizedGuidanceContent(
          displayText: "不要分岔，沿湾岸线前往 横浜 方向",
          spokenText:
            "在川崎浮岛 JCT不要分岔，沿湾岸线继续前往 横浜 方向",
          spokenForms: ["横浜": "横浜"],
          preservedJapaneseSignText: "横浜"
        ),
        .english: LocalizedGuidanceContent(
          displayText: "Stay on the Bayshore Route toward 横浜",
          spokenText:
            "At Kawasaki-Ukishima JCT, stay on the Bayshore Route toward 横浜",
          spokenForms: ["Bayshore Route": "Bayshore Route"],
          preservedJapaneseSignText: "横浜"
        ),
      ],
      commitTriggerDistanceMeters: 300,
      checkedAt: "2026-08-15",
      expectedJunctionDetailSHA256:
        "29eb925d30dec708acdc797dfc662d91"
        + "769e80e18e80133b7c6f0bfbd2fba92c",
      sources: [
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/jct/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-b/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-k6/"
        ),
        ShutoJunctionGuidanceSource(
          url:
            "https://www.shutoko.jp/-/media/images/responsive/"
            + "customer/use/network/jct/routeguide/jct_kawasaki",
          contentSHA256:
            "29eb925d30dec708acdc797dfc662d91"
            + "769e80e18e80133b7c6f0bfbd2fba92c"
        ),
      ]
    ),
    ShutoJunctionMovementDefinition(
      id: "shuto.jct.daikoku.b-westbound-stays-on-b",
      networkSnapshotID:
        "shuto-official-2026-07-29-osm-2026-08-04",
      junctionID: "shuto.jct.jct_daikoku",
      junctionNodeID: 157_941_466,
      incomingEdgeID: "osm.1449791735.2.forward",
      outgoingEdgeID: "osm.489510478.0.forward",
      incomingRouteID: "B",
      incomingDirectionJA: "西行き",
      outgoingRouteID: "B",
      outgoingDirectionJA: "西行き",
      // The operator diagram shows the Bayshore continuation on a straight
      // arrow and 神奈川5号大黒線 on a diverging arrow, so this movement
      // keeps the mainline and asserts no lane.
      branchSide: .straight,
      japaneseSignText: "横浜公園・横横道路",
      routeShields: ["B", "K3", "E16"],
      laneGuidanceState: .notReleased,
      localizedJunctionNames: [
        .japanese: "大黒JCT",
        .simplifiedChinese: "大黑 JCT",
        .english: "Daikoku JCT",
      ],
      localizedContent: [
        .japanese: LocalizedGuidanceContent(
          displayText: "分岐せず、湾岸線 横浜公園・横横道路方面へ",
          spokenText:
            "大黒ジャンクションは分岐せず、湾岸線 横浜公園・横横道路方面へ進んでください",
          spokenForms: [
            "湾岸線": "わんがんせん",
            "横浜公園": "よこはまこうえん",
            "横横道路": "よこよこどうろ",
            "大黒": "だいこく",
          ],
          preservedJapaneseSignText: "横浜公園・横横道路"
        ),
        .simplifiedChinese: LocalizedGuidanceContent(
          displayText: "不要分岔，沿湾岸线前往 横浜公園・横横道路 方向",
          spokenText:
            "在大黑 JCT不要分岔，沿湾岸线继续前往 横浜公園・横横道路 方向",
          spokenForms: ["横浜公園・横横道路": "横浜公園・横横道路"],
          preservedJapaneseSignText: "横浜公園・横横道路"
        ),
        .english: LocalizedGuidanceContent(
          displayText:
            "Stay on the Bayshore Route toward 横浜公園 and 横横道路",
          spokenText:
            "At Daikoku JCT, stay on the Bayshore Route toward 横浜公園 and 横横道路",
          spokenForms: ["Bayshore Route": "Bayshore Route"],
          preservedJapaneseSignText: "横浜公園・横横道路"
        ),
      ],
      commitTriggerDistanceMeters: 300,
      checkedAt: "2026-08-11",
      expectedJunctionDetailSHA256:
        "4fcd99ab1e97a6a84f6c5c41e86c2b16"
        + "247f5acd1b8c34e1e2e5397cf3c004eb",
      sources: [
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/jct/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-b/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-k5/"
        ),
        ShutoJunctionGuidanceSource(
          url:
            "https://www.shutoko.jp/-/media/images/responsive/"
            + "customer/use/network/jct/routeguide/jct_daikoku",
          contentSHA256:
            "4fcd99ab1e97a6a84f6c5c41e86c2b16"
            + "247f5acd1b8c34e1e2e5397cf3c004eb"
        ),
      ]
    ),
    ShutoJunctionMovementDefinition(
      id: "shuto.jct.tatsumi.b-eastbound-stays-on-b",
      networkSnapshotID:
        "shuto-official-2026-07-29-osm-2026-08-04",
      junctionID: "shuto.jct.jct_tatsumi",
      junctionNodeID: 31_300_414,
      incomingEdgeID: "osm.44882718.3.forward",
      outgoingEdgeID: "osm.678761503.0.forward",
      incomingRouteID: "B",
      incomingDirectionJA: "東行き",
      outgoingRouteID: "B",
      outgoingDirectionJA: "東行き",
      // The operator diagram shows the Bayshore continuation on a straight
      // arrow and 9号深川線 on a diverging arrow, so this movement
      // keeps the mainline and asserts no lane.
      branchSide: .straight,
      japaneseSignText: "浦安",
      routeShields: ["B"],
      laneGuidanceState: .notReleased,
      localizedJunctionNames: [
        .japanese: "辰巳JCT",
        .simplifiedChinese: "辰巳 JCT",
        .english: "Tatsumi JCT",
      ],
      localizedContent: [
        .japanese: LocalizedGuidanceContent(
          displayText: "分岐せず、湾岸線 浦安方面へ",
          spokenText:
            "辰巳ジャンクションは分岐せず、湾岸線 浦安方面へ進んでください",
          spokenForms: [
            "湾岸線": "わんがんせん",
            "浦安": "うらやす",
            "辰巳": "たつみ",
          ],
          preservedJapaneseSignText: "浦安"
        ),
        .simplifiedChinese: LocalizedGuidanceContent(
          displayText: "不要分岔，沿湾岸线前往 浦安 方向",
          spokenText:
            "在辰巳 JCT不要分岔，沿湾岸线继续前往 浦安 方向",
          spokenForms: ["浦安": "浦安"],
          preservedJapaneseSignText: "浦安"
        ),
        .english: LocalizedGuidanceContent(
          displayText: "Stay on the Bayshore Route toward 浦安",
          spokenText:
            "At Tatsumi JCT, stay on the Bayshore Route toward 浦安",
          spokenForms: ["Bayshore Route": "Bayshore Route"],
          preservedJapaneseSignText: "浦安"
        ),
      ],
      commitTriggerDistanceMeters: 300,
      checkedAt: "2026-08-11",
      expectedJunctionDetailSHA256:
        "c4ea23ea7741c0f9f54b875e62b04825"
        + "6501d7df8aac183ce8961d2eaf1b3dda",
      sources: [
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/jct/"
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
      id: "shuto.jct.shinonome.b-eastbound-stays-on-b",
      networkSnapshotID:
        "shuto-official-2026-07-29-osm-2026-08-04",
      junctionID: "shuto.jct.jct_shinonome",
      junctionNodeID: 493_584_435,
      incomingEdgeID: "osm.888066406.1.forward",
      outgoingEdgeID: "osm.23169038.0.forward",
      incomingRouteID: "B",
      incomingDirectionJA: "東行き",
      outgoingRouteID: "B",
      outgoingDirectionJA: "東行き",
      // The operator diagram shows the Bayshore continuation on a straight
      // arrow and 10号晴海線 on a diverging arrow, so this movement
      // keeps the mainline and asserts no lane.
      branchSide: .straight,
      japaneseSignText: "浦安",
      routeShields: ["B"],
      laneGuidanceState: .notReleased,
      localizedJunctionNames: [
        .japanese: "東雲JCT",
        .simplifiedChinese: "东云 JCT",
        .english: "Shinonome JCT",
      ],
      localizedContent: [
        .japanese: LocalizedGuidanceContent(
          displayText: "分岐せず、湾岸線 浦安方面へ",
          spokenText:
            "東雲ジャンクションは分岐せず、湾岸線 浦安方面へ進んでください",
          spokenForms: [
            "湾岸線": "わんがんせん",
            "浦安": "うらやす",
            "東雲": "しののめ",
          ],
          preservedJapaneseSignText: "浦安"
        ),
        .simplifiedChinese: LocalizedGuidanceContent(
          displayText: "不要分岔，沿湾岸线前往 浦安 方向",
          spokenText:
            "在东云 JCT不要分岔，沿湾岸线继续前往 浦安 方向",
          spokenForms: ["浦安": "浦安"],
          preservedJapaneseSignText: "浦安"
        ),
        .english: LocalizedGuidanceContent(
          displayText: "Stay on the Bayshore Route toward 浦安",
          spokenText:
            "At Shinonome JCT, stay on the Bayshore Route toward 浦安",
          spokenForms: ["Bayshore Route": "Bayshore Route"],
          preservedJapaneseSignText: "浦安"
        ),
      ],
      commitTriggerDistanceMeters: 300,
      checkedAt: "2026-08-11",
      expectedJunctionDetailSHA256:
        "452e2ca3d124ec3f726b0c3643cedbbc"
        + "e3446b21e755f538b418616278cfa605",
      sources: [
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/jct/"
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
      id: "shuto.jct.ariake.b-eastbound-stays-on-b",
      networkSnapshotID:
        "shuto-official-2026-07-29-osm-2026-08-04",
      junctionID: "shuto.jct.jct_ariake",
      junctionNodeID: 31_288_813,
      incomingEdgeID: "osm.266086989.2.forward",
      outgoingEdgeID: "osm.266086989.3.forward",
      incomingRouteID: "B",
      incomingDirectionJA: "東行き",
      outgoingRouteID: "B",
      outgoingDirectionJA: "東行き",
      // The operator diagram shows the Bayshore continuation on a straight
      // arrow and 11号台場線 on a diverging arrow, so this movement
      // keeps the mainline and asserts no lane.
      branchSide: .straight,
      japaneseSignText: "葛西",
      routeShields: ["B"],
      laneGuidanceState: .notReleased,
      localizedJunctionNames: [
        .japanese: "有明JCT",
        .simplifiedChinese: "有明 JCT",
        .english: "Ariake JCT",
      ],
      localizedContent: [
        .japanese: LocalizedGuidanceContent(
          displayText: "分岐せず、湾岸線 葛西方面へ",
          spokenText:
            "有明ジャンクションは分岐せず、湾岸線 葛西方面へ進んでください",
          spokenForms: [
            "湾岸線": "わんがんせん",
            "葛西": "かさい",
            "有明": "ありあけ",
          ],
          preservedJapaneseSignText: "葛西"
        ),
        .simplifiedChinese: LocalizedGuidanceContent(
          displayText: "不要分岔，沿湾岸线前往 葛西 方向",
          spokenText:
            "在有明 JCT不要分岔，沿湾岸线继续前往 葛西 方向",
          spokenForms: ["葛西": "葛西"],
          preservedJapaneseSignText: "葛西"
        ),
        .english: LocalizedGuidanceContent(
          displayText: "Stay on the Bayshore Route toward 葛西",
          spokenText:
            "At Ariake JCT, stay on the Bayshore Route toward 葛西",
          spokenForms: ["Bayshore Route": "Bayshore Route"],
          preservedJapaneseSignText: "葛西"
        ),
      ],
      commitTriggerDistanceMeters: 300,
      checkedAt: "2026-08-11",
      expectedJunctionDetailSHA256:
        "0351ca02b8260a625334bc17931b57d3"
        + "5d19631b4305fab64e014daf0aad4c26",
      sources: [
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/jct/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-b/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-11/"
        ),
        ShutoJunctionGuidanceSource(
          url:
            "https://www.shutoko.jp/-/media/images/responsive/"
            + "customer/use/network/jct/routeguide/jct_ariake",
          contentSHA256:
            "0351ca02b8260a625334bc17931b57d3"
            + "5d19631b4305fab64e014daf0aad4c26"
        ),
      ]
    ),
    ShutoJunctionMovementDefinition(
      id: "shuto.jct.daikoku.b-eastbound-stays-on-b",
      networkSnapshotID:
        "shuto-official-2026-07-29-osm-2026-08-04",
      junctionID: "shuto.jct.jct_daikoku",
      junctionNodeID: 364_206_183,
      incomingEdgeID: "osm.5365195.2.forward",
      outgoingEdgeID: "osm.5365195.3.forward",
      incomingRouteID: "B",
      incomingDirectionJA: "東行き",
      outgoingRouteID: "B",
      outgoingDirectionJA: "東行き",
      // The operator diagram shows the Bayshore continuation on a straight
      // arrow and 神奈川5号大黒線 on a diverging arrow, so this movement
      // keeps the mainline and asserts no lane.
      branchSide: .straight,
      japaneseSignText: "アクアライン・空港中央",
      routeShields: ["B", "CA"],
      laneGuidanceState: .notReleased,
      localizedJunctionNames: [
        .japanese: "大黒JCT",
        .simplifiedChinese: "大黑 JCT",
        .english: "Daikoku JCT",
      ],
      localizedContent: [
        .japanese: LocalizedGuidanceContent(
          displayText: "分岐せず、湾岸線 アクアライン・空港中央方面へ",
          spokenText:
            "大黒ジャンクションは分岐せず、湾岸線 アクアライン・空港中央方面へ進んでください",
          spokenForms: [
            "湾岸線": "わんがんせん",
            "アクアライン": "あくあらいん",
            "空港中央": "くうこうちゅうおう",
            "大黒": "だいこく",
          ],
          preservedJapaneseSignText: "アクアライン・空港中央"
        ),
        .simplifiedChinese: LocalizedGuidanceContent(
          displayText: "不要分岔，沿湾岸线前往 アクアライン・空港中央 方向",
          spokenText:
            "在大黑 JCT不要分岔，沿湾岸线继续前往 アクアライン・空港中央 方向",
          spokenForms: [
            "アクアライン・空港中央": "アクアライン・空港中央"
          ],
          preservedJapaneseSignText: "アクアライン・空港中央"
        ),
        .english: LocalizedGuidanceContent(
          displayText:
            "Stay on the Bayshore Route toward アクアライン and 空港中央",
          spokenText:
            "At Daikoku JCT, stay on the Bayshore Route toward アクアライン and 空港中央",
          spokenForms: ["Bayshore Route": "Bayshore Route"],
          preservedJapaneseSignText: "アクアライン・空港中央"
        ),
      ],
      commitTriggerDistanceMeters: 300,
      checkedAt: "2026-08-11",
      expectedJunctionDetailSHA256:
        "4fcd99ab1e97a6a84f6c5c41e86c2b16"
        + "247f5acd1b8c34e1e2e5397cf3c004eb",
      sources: [
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/jct/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-b/"
        ),
        ShutoJunctionGuidanceSource(
          url: "https://www.shutoko.jp/use/network/map/route-k5/"
        ),
        ShutoJunctionGuidanceSource(
          url:
            "https://www.shutoko.jp/-/media/images/responsive/"
            + "customer/use/network/jct/routeguide/jct_daikoku",
          contentSHA256:
            "4fcd99ab1e97a6a84f6c5c41e86c2b16"
            + "247f5acd1b8c34e1e2e5397cf3c004eb"
        ),
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.hamasakibashi.c1-outer-to-1-outbound",
      junctionID: "shuto.jct.jct_hamasakibashi",
      junctionNodeID: 3_218_329_762,
      incomingEdgeID: "osm.316213219.28.forward",
      outgoingEdgeID: "osm.45021972.0.forward",
      incomingRouteID: "C1",
      incomingDirectionJA: "外回り",
      outgoingRouteID: "1_HANEDA",
      outgoingDirectionJA: "下り",
      branchSide: .left,
      japaneseSignText: "羽田・湾岸線",
      routeShields: ["1", "B"],
      junctionNameJA: "浜崎橋JCT",
      junctionNameZH: "浜崎桥 JCT",
      junctionNameEN: "Hamasakibashi JCT",
      destinationJA: "1号羽田線 羽田・湾岸線方面",
      destinationZH: "1号羽田线 羽田・湾岸线方向",
      destinationEN: "Route 1 toward Haneda and the Bayshore Route",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "9991505f52afb8f1d4c7f9ee46956daa4"
        + "afad92c55bfb9cc6ccc5cafd2ab82c7",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_hamasakibashi",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c1/",
        "https://www.shutoko.jp/use/network/map/route-1/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.kasai.b-eastbound-stays-on-b",
      junctionID: "shuto.jct.jct_kasai",
      junctionNodeID: 31_330_103,
      incomingEdgeID: "osm.888066402.7.forward",
      outgoingEdgeID: "osm.44129862.0.forward",
      incomingRouteID: "B",
      incomingDirectionJA: "東行き",
      outgoingRouteID: "B",
      outgoingDirectionJA: "東行き",
      branchSide: .straight,
      japaneseSignText: "浦安",
      routeShields: ["B"],
      junctionNameJA: "葛西JCT",
      junctionNameZH: "葛西 JCT",
      junctionNameEN: "Kasai JCT",
      destinationJA: "湾岸線 浦安方面",
      destinationZH: "湾岸线浦安方向",
      destinationEN: "the Bayshore Route toward Urayasu",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "5e52b43abc96875472405c2fe5c2ca49"
        + "2946356ac0c86460f1610051289aa7b2",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_kasai",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-b/",
        "https://www.shutoko.jp/use/network/map/route-c2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.miyakezaka.c1-outer-to-4-outbound",
      junctionID: "shuto.jct.jct_miyakezaka",
      junctionNodeID: 260_710_800,
      incomingEdgeID: "osm.45392984.0.forward",
      outgoingEdgeID: "osm.24636451.0.forward",
      incomingRouteID: "C1",
      incomingDirectionJA: "外回り",
      outgoingRouteID: "4",
      outgoingDirectionJA: "下り",
      branchSide: .left,
      japaneseSignText: "新宿・中央道",
      routeShields: ["4", "E20"],
      junctionNameJA: "三宅坂JCT",
      junctionNameZH: "三宅坂 JCT",
      junctionNameEN: "Miyakezaka JCT",
      destinationJA: "4号新宿線 新宿・中央道方面",
      destinationZH: "4号新宿线 新宿・中央道方向",
      destinationEN: "Route 4 toward Shinjuku and the Chuo Expressway",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "a4b648d1710a6658750171468b86d14d"
        + "f4c86d6031841135fddd87e7e2610c71",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_miyakezaka",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c1/",
        "https://www.shutoko.jp/use/network/map/route-4/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.oi.c2-inner-stays-on-c2",
      junctionID: "shuto.jct.jct_oi",
      junctionNodeID: 3_387_909_450,
      incomingEdgeID: "osm.331692344.2.forward",
      outgoingEdgeID: "osm.1308572350.0.forward",
      incomingRouteID: "C2",
      incomingDirectionJA: "内回り",
      outgoingRouteID: "C2",
      outgoingDirectionJA: "内回り",
      branchSide: .right,
      japaneseSignText: "中央道・都心環状",
      routeShields: ["C2", "E20"],
      junctionNameJA: "大井JCT",
      junctionNameZH: "大井 JCT",
      junctionNameEN: "Oi JCT",
      destinationJA: "C2 内回り 中央道・都心環状方面",
      destinationZH: "C2 内环 中央道・都心环状方向",
      destinationEN:
        "the C2 Inner Loop toward the Chuo Expressway and Inner Circular Route",
      expectedJunctionDetailSHA256:
        "4bfe3cb6117273ec547a62872b971a87f"
        + "cc944fff70b3267022888612aacfc2b",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_oi",
      additionalSources: [
        "https://www.shutoko.jp/use/safety/branch/",
        "https://www.shutoko.jp/use/network/map/route-c2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.shinonome.10-outbound-to-b-eastbound",
      junctionID: "shuto.jct.jct_shinonome",
      junctionNodeID: 499_275_905,
      incomingEdgeID: "osm.1264293942.1.forward",
      outgoingEdgeID: "osm.40971846.0.forward",
      incomingRouteID: "10",
      incomingDirectionJA: "下り",
      outgoingRouteID: "B",
      outgoingDirectionJA: "東行き",
      branchSide: .left,
      japaneseSignText: "浦安",
      routeShields: ["B"],
      junctionNameJA: "東雲JCT",
      junctionNameZH: "东云 JCT",
      junctionNameEN: "Shinonome JCT",
      destinationJA: "湾岸線 浦安方面",
      destinationZH: "湾岸线浦安方向",
      destinationEN: "the Bayshore Route toward Urayasu",
      expectedJunctionDetailSHA256:
        "452e2ca3d124ec3f726b0c3643cedbbce"
        + "3446b21e755f538b418616278cfa605",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_shinonome",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-10/",
        "https://www.shutoko.jp/use/network/map/route-b/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.tanimachi.c1-inner-to-3-outbound",
      junctionID: "shuto.jct.jct_tanimachi",
      junctionNodeID: 252_175_042,
      incomingEdgeID: "osm.23297430.0.forward",
      outgoingEdgeID: "osm.45332351.0.forward",
      incomingRouteID: "C1",
      incomingDirectionJA: "内回り",
      outgoingRouteID: "3",
      outgoingDirectionJA: "下り",
      branchSide: .right,
      japaneseSignText: "東名・渋谷",
      routeShields: ["3", "E1"],
      junctionNameJA: "谷町JCT",
      junctionNameZH: "谷町 JCT",
      junctionNameEN: "Tanimachi JCT",
      destinationJA: "3号渋谷線 東名・渋谷方面",
      destinationZH: "3号涩谷线 东名・涩谷方向",
      destinationEN: "Route 3 toward Shibuya and the Tomei Expressway",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "b7f8b5458757c825d2abf42f315bdb7d"
        + "60e54debbb8a7420f49dd8a4646940fd",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_tanimachi",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c1/",
        "https://www.shutoko.jp/use/network/map/route-3/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.ryogoku.6-outbound-stays-on-6",
      junctionID: "shuto.jct.jct_ryogoku",
      junctionNodeID: 6_698_927_667,
      incomingEdgeID: "osm.1544832378.11.forward",
      outgoingEdgeID: "osm.712498144.0.forward",
      incomingRouteID: "6_MUKOJIMA",
      incomingDirectionJA: "下り",
      outgoingRouteID: "6_MUKOJIMA",
      outgoingDirectionJA: "下り",
      branchSide: .left,
      japaneseSignText: "東北道・常磐道",
      routeShields: ["6", "E4", "E6"],
      junctionNameJA: "両国JCT",
      junctionNameZH: "两国 JCT",
      junctionNameEN: "Ryogoku JCT",
      destinationJA: "6号向島線 東北道・常磐道方面",
      destinationZH: "6号向岛线 东北道・常磐道方向",
      destinationEN:
        "Route 6 toward the Tohoku and Joban Expressways",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "720995e96dbb9e570a481e8918bd8b49"
        + "bef2b7af9e79b4ab660eb6e1460ad66a",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_ryogoku",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-6/",
        "https://www.shutoko.jp/use/network/map/route-7/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.ryogoku.6-outbound-to-7-outbound",
      junctionID: "shuto.jct.jct_ryogoku",
      junctionNodeID: 6_698_927_667,
      incomingEdgeID: "osm.1544832378.11.forward",
      outgoingEdgeID: "osm.44506762.0.forward",
      incomingRouteID: "6_MUKOJIMA",
      incomingDirectionJA: "下り",
      outgoingRouteID: "7",
      outgoingDirectionJA: "下り",
      branchSide: .right,
      japaneseSignText: "京葉道路",
      routeShields: ["7", "E14"],
      junctionNameJA: "両国JCT",
      junctionNameZH: "两国 JCT",
      junctionNameEN: "Ryogoku JCT",
      destinationJA: "7号小松川線 京葉道路方面",
      destinationZH: "7号小松川线 京叶道路方向",
      destinationEN: "Route 7 toward the Keiyo Road",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "720995e96dbb9e570a481e8918bd8b49"
        + "bef2b7af9e79b4ab660eb6e1460ad66a",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_ryogoku",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-6/",
        "https://www.shutoko.jp/use/network/map/route-7/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.shibaura.1-outbound-stays-on-1",
      junctionID: "shuto.jct.jct_shibaura",
      junctionNodeID: 31_252_934,
      incomingEdgeID: "osm.1102698847.2.forward",
      outgoingEdgeID: "osm.1102698847.3.forward",
      incomingRouteID: "1_HANEDA",
      incomingDirectionJA: "下り",
      outgoingRouteID: "1_HANEDA",
      outgoingDirectionJA: "下り",
      branchSide: .right,
      japaneseSignText: "横浜",
      routeShields: ["1", "K1"],
      junctionNameJA: "芝浦JCT",
      junctionNameZH: "芝浦 JCT",
      junctionNameEN: "Shibaura JCT",
      destinationJA: "1号羽田線 横浜方面",
      destinationZH: "1号羽田线 横滨方向",
      destinationEN: "Route 1 toward Yokohama",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "c190fee58d35efdaeb0ad62015c838131"
        + "e00f4e7386cde2510e8aa1d83a1790c",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_shibaura",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-1/",
        "https://www.shutoko.jp/use/network/map/route-11/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.shibaura.1-outbound-to-11-outbound",
      junctionID: "shuto.jct.jct_shibaura",
      junctionNodeID: 31_252_934,
      incomingEdgeID: "osm.1102698847.2.forward",
      outgoingEdgeID: "osm.4847519.0.forward",
      incomingRouteID: "1_HANEDA",
      incomingDirectionJA: "下り",
      outgoingRouteID: "11",
      outgoingDirectionJA: "下り",
      branchSide: .left,
      japaneseSignText: "湾岸線",
      routeShields: ["11", "B"],
      junctionNameJA: "芝浦JCT",
      junctionNameZH: "芝浦 JCT",
      junctionNameEN: "Shibaura JCT",
      destinationJA: "11号台場線 湾岸線方面",
      destinationZH: "11号台场线 湾岸线方向",
      destinationEN: "Route 11 toward the Bayshore Route",
      commitTriggerDistanceMeters: 300,
      expectedJunctionDetailSHA256:
        "c190fee58d35efdaeb0ad62015c838131"
        + "e00f4e7386cde2510e8aa1d83a1790c",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_shibaura",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-1/",
        "https://www.shutoko.jp/use/network/map/route-11/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.ariake.11-outbound-to-b-eastbound",
      junctionID: "shuto.jct.jct_ariake",
      junctionNodeID: 31_252_897,
      incomingEdgeID: "osm.45019025.1.forward",
      outgoingEdgeID: "osm.202805893.0.forward",
      incomingRouteID: "11",
      incomingDirectionJA: "下り",
      outgoingRouteID: "B",
      outgoingDirectionJA: "東行き",
      branchSide: .straight,
      japaneseSignText: "東関東道",
      routeShields: ["E51", "B", "9"],
      junctionNameJA: "有明JCT",
      junctionNameZH: "有明 JCT",
      junctionNameEN: "Ariake JCT",
      destinationJA: "湾岸線 東関東道方面",
      destinationZH: "湾岸线东关东自动车道方向",
      destinationEN:
        "the Bayshore Route toward the Higashi-Kanto Expressway",
      expectedJunctionDetailSHA256:
        "0351ca02b8260a625334bc17931b57d3"
        + "5d19631b4305fab64e014daf0aad4c26",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_ariake",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-11/",
        "https://www.shutoko.jp/use/network/map/route-b/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.ariake.11-outbound-to-b-westbound",
      junctionID: "shuto.jct.jct_ariake",
      junctionNodeID: 31_252_897,
      incomingEdgeID: "osm.45019025.1.forward",
      outgoingEdgeID: "osm.4848758.0.forward",
      incomingRouteID: "11",
      incomingDirectionJA: "下り",
      outgoingRouteID: "B",
      outgoingDirectionJA: "西行き",
      branchSide: .right,
      japaneseSignText: "横浜・空港中央",
      routeShields: ["B", "1"],
      junctionNameJA: "有明JCT",
      junctionNameZH: "有明 JCT",
      junctionNameEN: "Ariake JCT",
      destinationJA: "湾岸線 横浜・空港中央方面",
      destinationZH: "湾岸线横滨、空港中央方向",
      destinationEN:
        "the Bayshore Route toward Yokohama and Kuko-Chuo",
      expectedJunctionDetailSHA256:
        "0351ca02b8260a625334bc17931b57d3"
        + "5d19631b4305fab64e014daf0aad4c26",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_ariake",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-11/",
        "https://www.shutoko.jp/use/network/map/route-b/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.ariake.b-westbound-to-11-inbound",
      junctionID: "shuto.jct.jct_ariake",
      junctionNodeID: 31_288_751,
      incomingEdgeID: "osm.1313249026.0.forward",
      outgoingEdgeID: "osm.23169048.0.forward",
      incomingRouteID: "B",
      incomingDirectionJA: "西行き",
      outgoingRouteID: "11",
      outgoingDirectionJA: "上り",
      branchSide: .left,
      japaneseSignText: "銀座",
      routeShields: ["11", "C1"],
      junctionNameJA: "有明JCT",
      junctionNameZH: "有明 JCT",
      junctionNameEN: "Ariake JCT",
      destinationJA: "11号台場線 銀座方面",
      destinationZH: "11号台场线银座方向",
      destinationEN: "Route 11 toward Ginza",
      expectedJunctionDetailSHA256:
        "0351ca02b8260a625334bc17931b57d3"
        + "5d19631b4305fab64e014daf0aad4c26",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_ariake",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-b/",
        "https://www.shutoko.jp/use/network/map/route-11/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.ariake.b-eastbound-to-11-inbound",
      junctionID: "shuto.jct.jct_ariake",
      junctionNodeID: 31_288_813,
      incomingEdgeID: "osm.266086989.2.forward",
      outgoingEdgeID: "osm.4848757.0.forward",
      incomingRouteID: "B",
      incomingDirectionJA: "東行き",
      outgoingRouteID: "11",
      outgoingDirectionJA: "上り",
      branchSide: .left,
      japaneseSignText: "都心環状",
      routeShields: ["11", "C1"],
      junctionNameJA: "有明JCT",
      junctionNameZH: "有明 JCT",
      junctionNameEN: "Ariake JCT",
      destinationJA: "11号台場線 都心環状方面",
      destinationZH: "11号台场线都心环状线方向",
      destinationEN: "Route 11 toward the Inner Circular Route",
      expectedJunctionDetailSHA256:
        "0351ca02b8260a625334bc17931b57d3"
        + "5d19631b4305fab64e014daf0aad4c26",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_ariake",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-b/",
        "https://www.shutoko.jp/use/network/map/route-11/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.kouhoku.c2-outer-to-s1-outbound",
      junctionID: "shuto.jct.jct_kouhoku",
      junctionNodeID: 263_988_157,
      incomingEdgeID: "osm.780870438.63.forward",
      outgoingEdgeID: "osm.28188172.0.forward",
      incomingRouteID: "C2",
      incomingDirectionJA: "外回り",
      outgoingRouteID: "S1",
      outgoingDirectionJA: "下り",
      branchSide: .left,
      japaneseSignText: "東北道",
      routeShields: ["S1", "E4"],
      junctionNameJA: "江北JCT",
      junctionNameZH: "江北 JCT",
      junctionNameEN: "Kohoku JCT",
      destinationJA: "S1 川口線 東北道方面",
      destinationZH: "S1 川口线东北自动车道方向",
      destinationEN: "Route S1 toward the Tohoku Expressway",
      expectedJunctionDetailSHA256:
        "d168d950ee904e51e2332fb9e6c94cb9"
        + "ffad6ef825b01df9e917d1db8e372d81",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_kouhoku",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c2/",
        "https://www.shutoko.jp/use/network/map/route-s1/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.kouhoku.c2-outer-stays-on-c2",
      junctionID: "shuto.jct.jct_kouhoku",
      junctionNodeID: 263_988_157,
      incomingEdgeID: "osm.780870438.63.forward",
      outgoingEdgeID: "osm.44211094.0.forward",
      incomingRouteID: "C2",
      incomingDirectionJA: "外回り",
      outgoingRouteID: "C2",
      outgoingDirectionJA: "外回り",
      branchSide: .right,
      japaneseSignText: "常磐道・湾岸線",
      routeShields: ["C2", "E6", "6"],
      junctionNameJA: "江北JCT",
      junctionNameZH: "江北 JCT",
      junctionNameEN: "Kohoku JCT",
      destinationJA: "C2 中央環状線 常磐道・湾岸線方面",
      destinationZH: "C2 中央环状线常磐道、湾岸线方向",
      destinationEN:
        "the C2 Outer Loop toward the Joban Expressway and Bayshore Route",
      expectedJunctionDetailSHA256:
        "d168d950ee904e51e2332fb9e6c94cb9"
        + "ffad6ef825b01df9e917d1db8e372d81",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_kouhoku",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-c2/",
        "https://www.shutoko.jp/use/network/map/route-s1/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.kouhoku.s1-inbound-to-c2-inner",
      junctionID: "shuto.jct.jct_kouhoku",
      junctionNodeID: 308_933_022,
      incomingEdgeID: "osm.438367463.80.forward",
      outgoingEdgeID: "osm.28127450.0.forward",
      incomingRouteID: "S1",
      incomingDirectionJA: "上り",
      outgoingRouteID: "S1",
      outgoingDirectionJA: "上り",
      branchSide: .right,
      japaneseSignText: "中央道・東名",
      routeShields: ["C2", "E20", "5", "E1"],
      junctionNameJA: "江北JCT",
      junctionNameZH: "江北 JCT",
      junctionNameEN: "Kohoku JCT",
      destinationJA: "C2 中央環状線 中央道・東名方面",
      destinationZH: "C2 中央环状线中央道、东名高速方向",
      destinationEN:
        "the C2 Inner Loop toward the Chuo and Tomei expressways",
      expectedJunctionDetailSHA256:
        "d168d950ee904e51e2332fb9e6c94cb9"
        + "ffad6ef825b01df9e917d1db8e372d81",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_kouhoku",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-s1/",
        "https://www.shutoko.jp/use/network/map/route-c2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.kouhoku.s1-inbound-to-c2-outer",
      junctionID: "shuto.jct.jct_kouhoku",
      junctionNodeID: 308_933_022,
      incomingEdgeID: "osm.438367463.80.forward",
      outgoingEdgeID: "osm.867182414.0.forward",
      incomingRouteID: "S1",
      incomingDirectionJA: "上り",
      outgoingRouteID: "S1",
      outgoingDirectionJA: "上り",
      branchSide: .straight,
      japaneseSignText: "東関東道・銀座",
      routeShields: ["E51", "C2", "6"],
      junctionNameJA: "江北JCT",
      junctionNameZH: "江北 JCT",
      junctionNameEN: "Kohoku JCT",
      destinationJA: "C2 中央環状線 東関東道・銀座方面",
      destinationZH: "C2 中央环状线东关东自动车道、银座方向",
      destinationEN:
        "the C2 Outer Loop toward the Higashi-Kanto Expressway and Ginza",
      expectedJunctionDetailSHA256:
        "d168d950ee904e51e2332fb9e6c94cb9"
        + "ffad6ef825b01df9e917d1db8e372d81",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_kouhoku",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-s1/",
        "https://www.shutoko.jp/use/network/map/route-c2/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.daikoku.b-eastbound-to-k5-inbound",
      junctionID: "shuto.jct.jct_daikoku",
      junctionNodeID: 364_206_183,
      incomingEdgeID: "osm.5365195.2.forward",
      outgoingEdgeID: "osm.32355890.0.forward",
      incomingRouteID: "B",
      incomingDirectionJA: "東行き",
      outgoingRouteID: "K5",
      outgoingDirectionJA: "上り",
      branchSide: .left,
      japaneseSignText: "東名",
      routeShields: ["E1", "K5", "K1", "K7"],
      junctionNameJA: "大黒JCT",
      junctionNameZH: "大黑 JCT",
      junctionNameEN: "Daikoku JCT",
      destinationJA: "K5 大黒線 東名方面",
      destinationZH: "K5 大黑线东名高速方向",
      destinationEN: "Route K5 toward the Tomei Expressway",
      expectedJunctionDetailSHA256:
        "4fcd99ab1e97a6a84f6c5c41e86c2b16"
        + "247f5acd1b8c34e1e2e5397cf3c004eb",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_daikoku",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-b/",
        "https://www.shutoko.jp/use/network/map/route-k5/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.daikoku.k5-outbound-to-b-eastbound",
      junctionID: "shuto.jct.jct_daikoku",
      junctionNodeID: 364_203_327,
      incomingEdgeID: "osm.32355898.7.forward",
      outgoingEdgeID: "osm.32592543.0.forward",
      incomingRouteID: "K5",
      incomingDirectionJA: "下り",
      outgoingRouteID: "K5",
      outgoingDirectionJA: "下り",
      branchSide: .left,
      japaneseSignText: "空港中央・東関東道",
      routeShields: ["B", "K6", "E51"],
      junctionNameJA: "大黒JCT",
      junctionNameZH: "大黑 JCT",
      junctionNameEN: "Daikoku JCT",
      destinationJA: "湾岸線 空港中央・東関東道方面",
      destinationZH: "湾岸线空港中央、东关东自动车道方向",
      destinationEN:
        "the Bayshore Route toward Kuko-Chuo and the Higashi-Kanto Expressway",
      expectedJunctionDetailSHA256:
        "4fcd99ab1e97a6a84f6c5c41e86c2b16"
        + "247f5acd1b8c34e1e2e5397cf3c004eb",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_daikoku",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-k5/",
        "https://www.shutoko.jp/use/network/map/route-b/",
      ]
    ),
    reviewedMovement(
      id: "shuto.jct.daikoku.k5-outbound-to-b-westbound",
      junctionID: "shuto.jct.jct_daikoku",
      junctionNodeID: 364_203_327,
      incomingEdgeID: "osm.32355898.7.forward",
      outgoingEdgeID: "osm.779045459.0.forward",
      incomingRouteID: "K5",
      incomingDirectionJA: "下り",
      outgoingRouteID: "K5",
      outgoingDirectionJA: "下り",
      branchSide: .straight,
      japaneseSignText: "横浜公園・幸浦",
      routeShields: ["B", "K3"],
      junctionNameJA: "大黒JCT",
      junctionNameZH: "大黑 JCT",
      junctionNameEN: "Daikoku JCT",
      destinationJA: "湾岸線 横浜公園・幸浦方面",
      destinationZH: "湾岸线横滨公园、幸浦方向",
      destinationEN:
        "the Bayshore Route toward Yokohama Park and Sachiura",
      expectedJunctionDetailSHA256:
        "4fcd99ab1e97a6a84f6c5c41e86c2b16"
        + "247f5acd1b8c34e1e2e5397cf3c004eb",
      officialDetailReference:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_daikoku",
      additionalSources: [
        "https://www.shutoko.jp/use/network/map/route-k5/",
        "https://www.shutoko.jp/use/network/map/route-b/",
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
    let routesByID = Dictionary(
      uniqueKeysWithValues: database.routes.map { ($0.routeID, $0) }
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
        }),
        outgoing.routeMemberships.contains(where: {
          $0.routeID == definition.outgoingRouteID
        }),
        routesByID[definition.incomingRouteID]?
          .officialDirectionsJA.contains(
            definition.incomingDirectionJA
          ) == true,
        routesByID[definition.outgoingRouteID]?
          .officialDirectionsJA.contains(
            definition.outgoingDirectionJA
          ) == true,
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
        hasValidCoveredContinuation(
          definition,
          database: database,
          initialOutgoing: outgoing
        ),
        definition.commitTriggerDistanceMeters.isFinite,
        definition.commitTriggerDistanceMeters > 0
      else {
        return false
      }
      return true
    }
  }

  /// Resolves a later fork intentionally covered by one earlier operator sign.
  /// The complete ordered edge prefix must be present in the selected route;
  /// matching one repeated edge ID alone is never sufficient.
  public static func releasedDefinitionCoveringFollowingDecision(
    database: ShutoNetworkDatabase,
    routeEdges: [ShutoNetworkDatabase.Edge],
    decisionIndex: Int
  ) -> ShutoJunctionMovementDefinition? {
    guard decisionIndex >= 1, decisionIndex + 1 < routeEdges.count else {
      return nil
    }
    for definition in released
    where !definition.coveredFollowingDecisionEdgeIDs.isEmpty {
      for offset in definition.coveredFollowingDecisionEdgeIDs.indices
      where definition.coveredFollowingDecisionEdgeIDs[offset]
        == routeEdges[decisionIndex + 1].edgeID
      {
        let baseDecisionIndex = decisionIndex - offset - 1
        guard baseDecisionIndex >= 0,
          let base = releasedDefinition(
            database: database,
            incoming: routeEdges[baseDecisionIndex],
            outgoing: routeEdges[baseDecisionIndex + 1]
          ),
          base.id == definition.id
        else {
          continue
        }
        let actualContinuation = routeEdges[
          (baseDecisionIndex + 2)...(decisionIndex + 1)
        ].map(\.edgeID)
        guard
          actualContinuation
            == Array(
              definition.coveredFollowingDecisionEdgeIDs.prefix(offset + 1)
            )
        else {
          continue
        }
        return definition
      }
    }
    return nil
  }

  private static func hasValidCoveredContinuation(
    _ definition: ShutoJunctionMovementDefinition,
    database: ShutoNetworkDatabase,
    initialOutgoing: ShutoNetworkDatabase.Edge
  ) -> Bool {
    guard
      Set(definition.coveredFollowingDecisionEdgeIDs).count
        == definition.coveredFollowingDecisionEdgeIDs.count,
      !definition.coveredFollowingDecisionEdgeIDs.contains(
        definition.incomingEdgeID
      ),
      !definition.coveredFollowingDecisionEdgeIDs.contains(
        definition.outgoingEdgeID
      )
    else {
      return false
    }
    let edgesByID = Dictionary(
      uniqueKeysWithValues: database.edges.map { ($0.edgeID, $0) }
    )
    var previous = initialOutgoing
    for edgeID in definition.coveredFollowingDecisionEdgeIDs {
      guard let edge = edgesByID[edgeID],
        previous.toNodeID == edge.fromNodeID,
        edge.routeMemberships.contains(where: {
          $0.routeID == definition.outgoingRouteID
        })
      else {
        return false
      }
      previous = edge
    }
    return true
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
    let routesByID = Dictionary(
      uniqueKeysWithValues: database.routes.map { ($0.routeID, $0) }
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
          }),
          outgoing.routeMemberships.contains(where: {
            $0.routeID == definition.outgoingRouteID
          }),
          routesByID[definition.incomingRouteID]?
            .officialDirectionsJA.contains(
              definition.incomingDirectionJA
            ) == true,
          routesByID[definition.outgoingRouteID]?
            .officialDirectionsJA.contains(
              definition.outgoingDirectionJA
            ) == true,
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
