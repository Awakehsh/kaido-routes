import KaidoDomain
import KaidoNavigation
import KaidoRouting
import SwiftUI

/// A design-only dense-route example for the shared topology renderer.
///
/// Operator facts were checked on 2026-07-29 against the current Shutoko C2
/// and B route tables, the 2026-07-01 Navimap, and the official Kasai and Oi
/// JCT detail diagrams. The normalized layout is Kaido-generated. This preview
/// is not a Route Atlas release and cannot start navigation.
///
/// Sources:
/// - https://www.shutoko.jp/use/network/map/route-c2/
/// - https://www.shutoko.jp/use/network/map/route-b/
/// - https://www.shutoko.jp/use/network/navimap/
/// - https://www.shutoko.jp/use/network/jct/
/// - https://www.shutoko-sv.jp/pa/oi-westbound
struct C2CompletedRouteDemoView: View {
  static let previewPresentation = C2CompletedRouteDemo.presentation
  static let previewJunctionInset = C2CompletedRouteDemo.junctionInset

  private enum MapLayer: String, CaseIterable {
    case route
    case facilities

    var label: String {
      switch self {
      case .route:
        return "路线全览"
      case .facilities:
        return "IC · PA"
      }
    }
  }

  @State private var mapLayer: MapLayer
  @State private var showsJunctionInset: Bool

  init() {
    let arguments = ProcessInfo.processInfo.arguments
    _mapLayer = State(
      initialValue: arguments.contains("-C2-JUNCTION-INSET-DEMO")
        ? .route
        : arguments.contains("-C2-FACILITIES-DEMO")
          ? .facilities
          : .route
    )
    _showsJunctionInset = State(
      initialValue: arguments.contains("-C2-JUNCTION-INSET-DEMO")
    )
  }

  var body: some View {
    ZStack(alignment: .top) {
      KaidoTheme.paper
        .ignoresSafeArea()

      VStack(alignment: .leading, spacing: 12) {
        header
        HStack(spacing: 8) {
          layerControl
          junctionSimulationButton
        }

        GeometryReader { proxy in
          ZStack(alignment: .bottom) {
            ProductTopologyMapView(
              presentation: Self.previewPresentation,
              usesDarkStyle: false,
              showsPositionStatus: false,
              landmarkLabelMode:
                mapLayer == .facilities ? .facilities : .route
            )

            if showsJunctionInset {
              ProductJunctionInsetView(
                presentation: Self.previewJunctionInset
              )
              .padding(10)
              .transition(.move(edge: .bottom).combined(with: .opacity))
            }
          }
          .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
          RoundedRectangle(cornerRadius: 10)
            .stroke(KaidoTheme.paperDivider, lineWidth: 1)
        }

        legend
      }
      .padding(.horizontal, 16)
      .padding(.top, 12)
      .padding(.bottom, 10)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("c2-completed-route-demo")
    .accessibilityValue(
      "DEMO_NOT_NAVIGATION;\(mapLayer.rawValue);"
        + "junction=\(showsJunctionInset ? "visible" : "hidden")"
    )
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text("KAIDO")
          .font(.system(size: 10, weight: .black, design: .rounded))
          .tracking(2)
          .foregroundStyle(KaidoTheme.routeGreen)

        Text("C2 + B 完整环线")
          .font(.system(size: 27, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.ink)

        Text("完成一圈后驶向初台南出口")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(KaidoTheme.quietText)

        Text("设施按行驶顺序排列 · 拓扑非地理比例")
          .font(.system(size: 8, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeGreenDeep)
      }

      Spacer(minLength: 8)

      Text("DEMO")
        .font(.system(size: 9, weight: .black, design: .monospaced))
        .tracking(0.8)
        .foregroundStyle(KaidoTheme.routeGreenDeep)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(KaidoTheme.confirmedGreen.opacity(0.2))
        .clipShape(Capsule())
    }
  }

  private var layerControl: some View {
    HStack(spacing: 4) {
      ForEach(MapLayer.allCases, id: \.rawValue) { candidate in
        Button {
          withAnimation(.easeOut(duration: 0.2)) {
            mapLayer = candidate
          }
        } label: {
          Text(candidate.label)
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundStyle(
              mapLayer == candidate
                ? KaidoTheme.routeWhite
                : KaidoTheme.quietText
            )
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(
              mapLayer == candidate
                ? KaidoTheme.routeGreen
                : KaidoTheme.paperRaised
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("c2-demo-mode-\(candidate.rawValue)")
        .accessibilityValue(
          mapLayer == candidate ? "SELECTED" : "AVAILABLE"
        )
      }
    }
    .frame(maxWidth: .infinity)
    .padding(3)
    .background(KaidoTheme.paperRaised)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(KaidoTheme.paperDivider, lineWidth: 1)
    }
  }

  private var junctionSimulationButton: some View {
    Button {
      withAnimation(.easeOut(duration: 0.2)) {
        showsJunctionInset.toggle()
      }
    } label: {
      VStack(spacing: 1) {
        Image(systemName: "arrow.triangle.branch")
          .font(.system(size: 12, weight: .black))
        Text("模拟接近 JCT")
          .font(.system(size: 7, weight: .black, design: .rounded))
      }
      .foregroundStyle(
        showsJunctionInset
          ? KaidoTheme.routeWhite
          : KaidoTheme.routeGreenDeep
      )
      .frame(width: 76, height: 38)
      .background(
        showsJunctionInset
          ? KaidoTheme.routeGreen
          : KaidoTheme.paperRaised
      )
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(KaidoTheme.paperDivider, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("c2-demo-show-kasai-junction")
    .accessibilityLabel("模拟接近葛西 JCT")
    .accessibilityValue(
      showsJunctionInset ? "INSET_VISIBLE" : "INSET_HIDDEN"
    )
  }

  private var legend: some View {
    VStack(spacing: 7) {
      HStack(spacing: 14) {
        routeLegend(
          color: KaidoTheme.routeGreen,
          shield: "C2",
          label: "中央环状线"
        )
        routeLegend(
          color: Color(hex: 0x287E9A),
          shield: "B",
          label: "湾岸线西行"
        )
        Spacer(minLength: 0)
      }

      HStack {
        Text(modeCaption)
        Spacer(minLength: 6)
        Text("设计演示 · 不用于驾驶")
          .foregroundStyle(KaidoTheme.evidenceCoral)
      }
      .font(.system(size: 8, weight: .black, design: .rounded))
      .foregroundStyle(KaidoTheme.quietText)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("c2-completed-route-demo-legend")
  }

  private var modeCaption: String {
    if showsJunctionInset {
      return "葛西 JCT · C2 外回り → B 湾岸线西行 · 右分岔"
    }
    switch mapLayer {
    case .route:
      return "富ヶ谷入口（外回り） → 初台南出口（外回り）"
    case .facilities:
      return "方向设施 · IC 20 · 大井 PA 在分岔后（本路线不进入）"
    }
  }

  private func routeLegend(
    color: Color,
    shield: String,
    label: String
  ) -> some View {
    HStack(spacing: 6) {
      Capsule()
        .fill(color)
        .frame(width: 22, height: 5)
      Text(shield)
        .font(.system(size: 9, weight: .black, design: .rounded))
      Text(label)
        .font(.system(size: 9, weight: .bold))
    }
    .foregroundStyle(KaidoTheme.ink)
  }
}

private enum C2CompletedRouteDemo {
  private struct Stop {
    let id: String
    let point: RouteAtlasPoint
  }

  private enum DirectionalAccess {
    case entrance
    case exit
    case both

    var japanese: String {
      switch self {
      case .entrance:
        return "入口"
      case .exit:
        return "出口"
      case .both:
        return "出入口"
      }
    }

    var simplifiedChinese: String {
      switch self {
      case .entrance:
        return "入口"
      case .exit:
        return "出口"
      case .both:
        return "出入口"
      }
    }

    var english: String {
      switch self {
      case .entrance:
        return "entry"
      case .exit:
        return "exit"
      case .both:
        return "entry/exit"
      }
    }
  }

  static let junctionInset = ProductJunctionInsetPresentation(
    decisionZoneID: "demo.c2.kasai.outer-to-b-west",
    movementOccurrenceID: "demo.c2.occurrence.9",
    selectedBranch: .right,
    distanceMeters: nil,
    japaneseSignText: "9  横浜",
    localizedInstruction: "葛西 JCT 右分岔，驶入 B 湾岸线西行（横浜方向）",
    routeShield: "B"
  )

  static let presentation: ProductTopologyMapPresentation = {
    let stops = [
      Stop(id: "tomigaya-entry", point: point(0.18, 0.66)),
      Stop(id: "hatsudai-pass", point: point(0.15, 0.56)),
      Stop(id: "nishi-shinjuku", point: point(0.17, 0.46)),
      Stop(id: "kumanocho", point: point(0.23, 0.27)),
      Stop(id: "itabashi", point: point(0.34, 0.18)),
      Stop(id: "kohoku", point: point(0.50, 0.13)),
      Stop(id: "kosuge", point: point(0.67, 0.19)),
      Stop(id: "horikiri", point: point(0.76, 0.29)),
      Stop(id: "komatsugawa", point: point(0.84, 0.44)),
      Stop(id: "kasai", point: point(0.84, 0.60)),
      Stop(id: "tatsumi", point: point(0.72, 0.73)),
      Stop(id: "shinonome", point: point(0.62, 0.79)),
      Stop(id: "ariake", point: point(0.50, 0.83)),
      Stop(id: "oi", point: point(0.25, 0.78)),
      Stop(id: "ohashi", point: point(0.18, 0.72)),
      Stop(id: "tomigaya-return", point: point(0.18, 0.66)),
      Stop(id: "hatsudai-exit", point: point(0.15, 0.56)),
    ]

    let occurrences = stops.indices.dropLast().map { index in
      let isRepeatedTomigayaSegment = index == 0 || index == 15
      return RouteAtlasJourneyOccurrence(
        occurrenceID: "demo.c2.occurrence.\(index)",
        occurrenceIndex: index,
        segmentID:
          isRepeatedTomigayaSegment
          ? "demo.c2.segment.tomigaya-to-hatsudai"
          : "demo.c2.segment.\(stops[index].id)-to-\(stops[index + 1].id)",
        points: [stops[index].point, stops[index + 1].point],
        state: .planned,
        repeatOrdinal: index == 15 ? 2 : 1,
        repeatCount: isRepeatedTomigayaSegment ? 2 : 1
      )
    }

    let bayShoreOccurrenceIDs = Set(
      occurrences
        .filter { (9...12).contains($0.occurrenceIndex) }
        .map(\.occurrenceID)
    )
    let c2OccurrenceIDs = Set(occurrences.map(\.occurrenceID))
      .subtracting(bayShoreOccurrenceIDs)

    let facilities = ProductTopologyFacilityPresentation(
      routeShields: ["C2", "B"],
      routeSections: [
        ProductTopologyRouteSection(
          id: "demo.c2.section.central-circular",
          routeShield: "C2",
          occurrenceIDs: c2OccurrenceIDs,
          style: .primary
        ),
        ProductTopologyRouteSection(
          id: "demo.c2.section.bayshore-westbound",
          routeShield: "B",
          occurrenceIDs: bayShoreOccurrenceIDs,
          style: .connector
        ),
      ],
      landmarks: [
        landmark(
          id: "demo.c2.entrance.tomigaya.outer",
          kind: .entrance,
          occurrenceIndex: 0,
          point: stops[0].point,
          japanese: "富ヶ谷入口（C2 外回り）",
          simplifiedChinese: "富ヶ谷入口（C2 外回り）",
          english: "Tomigaya entrance (C2 outer)"
        ),
        interchange(
          "nakanochojabashi",
          2,
          point(0.18, 0.42),
          "中野長者橋",
          "Nakanochojabashi",
          .entrance
        ),
        interchange(
          "nishi-ikebukuro",
          2,
          point(0.195, 0.36),
          "西池袋",
          "Nishi-ikebukuro",
          .exit
        ),
        interchange(
          "takamatsu",
          2,
          point(0.215, 0.31),
          "高松",
          "Takamatsu",
          .entrance
        ),
        interchange(
          "shin-itabashi",
          4,
          point(0.37, 0.16),
          "新板橋",
          "Shin-itabashi",
          .exit
        ),
        interchange(
          "oji-minami",
          4,
          point(0.41, 0.15),
          "王子南",
          "Oji-minami",
          .exit
        ),
        interchange(
          "oji-kita",
          4,
          point(0.45, 0.14),
          "王子北",
          "Oji-kita",
          .entrance
        ),
        interchange(
          "ogi-ohashi",
          5,
          point(0.55, 0.145),
          "扇大橋",
          "Ogi-ohashi",
          .both
        ),
        interchange(
          "senju-shinbashi",
          5,
          point(0.60, 0.16),
          "千住新橋",
          "Senju-shinbashi",
          .both
        ),
        interchange(
          "kosuge",
          6,
          point(0.70, 0.21),
          "小菅",
          "Kosuge",
          .entrance
        ),
        interchange(
          "yotsugi",
          7,
          point(0.79, 0.34),
          "四つ木",
          "Yotsugi",
          .both
        ),
        interchange(
          "hirai-ohashi",
          8,
          point(0.825, 0.40),
          "平井大橋",
          "Hirai-ohashi",
          .exit
        ),
        interchange(
          "funaboribashi",
          8,
          point(0.84, 0.49),
          "船堀橋",
          "Funaboribashi",
          .entrance
        ),
        interchange(
          "seishincho",
          8,
          point(0.84, 0.55),
          "清新町",
          "Seishincho",
          .exit
        ),
        interchange(
          "kasai-bayshore",
          9,
          point(0.82, 0.62),
          "葛西",
          "Kasai",
          .both
        ),
        interchange(
          "shinkiba",
          9,
          point(0.78, 0.67),
          "新木場",
          "Shinkiba",
          .both
        ),
        interchange(
          "ariake",
          12,
          point(0.46, 0.83),
          "有明",
          "Ariake",
          .exit
        ),
        interchange(
          "rinkai-fukutoshin",
          12,
          point(0.42, 0.83),
          "臨海副都心",
          "Rinkai-fukutoshin",
          .entrance,
          simplifiedChineseName: "临海副都心"
        ),
        interchange(
          "oi-bayshore",
          12,
          point(0.30, 0.80),
          "大井",
          "Oi",
          .exit
        ),
        interchange(
          "chukan-oi-minami",
          13,
          point(0.23, 0.76),
          "中環大井南",
          "Chukan-oi-minami",
          .entrance
        ),
        interchange(
          "gotanda",
          13,
          point(0.20, 0.735),
          "五反田",
          "Gotanda",
          .entrance
        ),
        junction("nishi-shinjuku", 2, stops[2].point, "西新宿"),
        junction("kumanocho", 3, stops[3].point, "熊野町"),
        junction("itabashi", 4, stops[4].point, "板橋"),
        junction("kohoku", 5, stops[5].point, "江北"),
        junction("kosuge", 6, stops[6].point, "小菅"),
        junction("horikiri", 7, stops[7].point, "堀切"),
        junction("komatsugawa", 8, stops[8].point, "小松川"),
        landmark(
          id: "demo.c2.junction.kasai",
          kind: .junction,
          occurrenceIndex: 9,
          point: stops[9].point,
          japanese: "葛西JCT → B 西行",
          simplifiedChinese: "葛西 JCT → B 西行",
          english: "Kasai JCT → B westbound"
        ),
        junction("tatsumi", 10, stops[10].point, "辰巳"),
        junction("shinonome", 11, stops[11].point, "東雲", "东云"),
        junction("ariake", 12, stops[12].point, "有明"),
        landmark(
          id: "demo.c2.pa.oi-westbound",
          kind: .parkingArea,
          occurrenceIndex: 13,
          point: point(0.28, 0.91),
          japanese: "大井PA（西行き・大井JCT直進後）",
          simplifiedChinese: "大井 PA（西行 · 本路线不进入）",
          english: "Oi PA (westbound, beyond this route)"
        ),
        landmark(
          id: "demo.c2.junction.oi",
          kind: .junction,
          occurrenceIndex: 13,
          point: stops[13].point,
          japanese: "大井JCT → C2 外回り",
          simplifiedChinese: "大井 JCT → C2 外回り",
          english: "Oi JCT → C2 outer"
        ),
        junction("ohashi", 14, stops[14].point, "大橋", "大桥"),
        landmark(
          id: "demo.c2.exit.hatsudai-minami.outer",
          kind: .exit,
          occurrenceIndex: 15,
          point: stops[16].point,
          japanese: "初台南出口（C2 外回り）",
          simplifiedChinese: "初台南出口（C2 外回り）",
          english: "Hatsudai-minami exit (C2 outer)"
        ),
      ],
      entranceCount: 1,
      interchangeCount: 20,
      junctionCount: 13,
      parkingAreaCount: 1,
      exitCount: 1
    )

    let projection = RouteAtlasJourneyProjection(
      networkSnapshotID: "demo.c2.not-released",
      routePlanID: "demo.c2-completed-circuit",
      atlasID: "demo.c2-generated-layout",
      topologySliceID: "demo.c2.not-navigation-authority",
      contextSegments: contextSegments,
      occurrences: occurrences,
      attributions: [],
      currentOccurrenceID: nil
    )
    return ProductTopologyMapPresentation.make(
      projection: projection,
      evidence: nil,
      snapshot: nil,
      facilities: facilities
    )
  }()

  private static let contextSegments = [
    RouteAtlasJourneyContextSegment(
      segmentID: "demo.context.route-4",
      points: [point(0.17, 0.46), point(0.03, 0.42)]
    ),
    RouteAtlasJourneyContextSegment(
      segmentID: "demo.context.route-5",
      points: [point(0.34, 0.18), point(0.25, 0.03)]
    ),
    RouteAtlasJourneyContextSegment(
      segmentID: "demo.context.s1",
      points: [point(0.50, 0.13), point(0.50, 0.01)]
    ),
    RouteAtlasJourneyContextSegment(
      segmentID: "demo.context.route-6",
      points: [point(0.67, 0.19), point(0.78, 0.04)]
    ),
    RouteAtlasJourneyContextSegment(
      segmentID: "demo.context.route-7",
      points: [point(0.84, 0.44), point(0.98, 0.40)]
    ),
    RouteAtlasJourneyContextSegment(
      segmentID: "demo.context.route-9",
      points: [point(0.72, 0.73), point(0.64, 0.58)]
    ),
    RouteAtlasJourneyContextSegment(
      segmentID: "demo.context.route-11",
      points: [point(0.50, 0.83), point(0.48, 0.96)]
    ),
    RouteAtlasJourneyContextSegment(
      segmentID: "demo.context.route-3",
      points: [point(0.18, 0.72), point(0.04, 0.82)]
    ),
    RouteAtlasJourneyContextSegment(
      segmentID: "demo.context.bayshore-west-after-oi",
      points: [
        point(0.25, 0.78),
        point(0.28, 0.91),
        point(0.36, 0.98),
      ]
    ),
  ]

  private static func junction(
    _ id: String,
    _ occurrenceIndex: Int,
    _ point: RouteAtlasPoint,
    _ japaneseName: String,
    _ simplifiedChineseName: String? = nil
  ) -> ProductTopologyLandmark {
    landmark(
      id: "demo.c2.junction.\(id)",
      kind: .junction,
      occurrenceIndex: occurrenceIndex,
      point: point,
      japanese: "\(japaneseName)JCT",
      simplifiedChinese:
        "\(simplifiedChineseName ?? japaneseName) JCT",
      english: "\(englishJunctionName(id)) JCT"
    )
  }

  private static func interchange(
    _ id: String,
    _ occurrenceIndex: Int,
    _ point: RouteAtlasPoint,
    _ japaneseName: String,
    _ englishName: String,
    _ access: DirectionalAccess,
    simplifiedChineseName: String? = nil
  ) -> ProductTopologyLandmark {
    landmark(
      id: "demo.c2.interchange.\(id)",
      kind: .interchange,
      occurrenceIndex: occurrenceIndex,
      point: point,
      japanese: "\(japaneseName) IC・\(access.japanese)",
      simplifiedChinese:
        "\(simplifiedChineseName ?? japaneseName) IC · "
        + access.simplifiedChinese,
      english: "\(englishName) IC · \(access.english)"
    )
  }

  private static func landmark(
    id: String,
    kind: ProductTopologyLandmarkKind,
    occurrenceIndex: Int,
    point: RouteAtlasPoint,
    japanese: String,
    simplifiedChinese: String,
    english: String
  ) -> ProductTopologyLandmark {
    ProductTopologyLandmark(
      id: id,
      kind: kind,
      occurrenceIndex: occurrenceIndex,
      point: point,
      title: RouteEditorLocalizedText(
        values: [
          .japanese: japanese,
          .simplifiedChinese: simplifiedChinese,
          .english: english,
        ]
      ),
      detail: nil
    )
  }

  private static func point(
    _ x: Double,
    _ y: Double
  ) -> RouteAtlasPoint {
    RouteAtlasPoint(x: x, y: y)
  }

  private static func englishJunctionName(_ id: String) -> String {
    switch id {
    case "nishi-shinjuku": "Nishi-shinjuku"
    case "kumanocho": "Kumanocho"
    case "itabashi": "Itabashi"
    case "kohoku": "Kohoku"
    case "kosuge": "Kosuge"
    case "horikiri": "Horikiri"
    case "komatsugawa": "Komatsugawa"
    case "tatsumi": "Tatsumi"
    case "shinonome": "Shinonome"
    case "ariake": "Ariake"
    case "ohashi": "Ohashi"
    default: id
    }
  }
}
