import KaidoDomain
import KaidoNavigation
import KaidoRouting
import SwiftUI

/// A design-only dense-route example for the shared topology renderer.
///
/// The route names and directional facilities follow current operator
/// references, while the normalized layout is Kaido-generated. This preview is
/// not a Route Atlas release and cannot start navigation.
struct C2CompletedRouteDemoView: View {
  static let previewPresentation = C2CompletedRouteDemo.presentation

  var body: some View {
    ZStack {
      KaidoTheme.paper
        .ignoresSafeArea()

      VStack(alignment: .leading, spacing: 12) {
        header

        ProductTopologyMapView(
          presentation: Self.previewPresentation,
          usesDarkStyle: false,
          showsPositionStatus: false
        )
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
    .accessibilityValue("DEMO_NOT_NAVIGATION")
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
        Text("富ヶ谷入口（外回り）")
        Image(systemName: "arrow.right")
        Text("初台南出口（外回り）")
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
      Stop(id: "oi-pa-west", point: point(0.38, 0.83)),
      Stop(id: "oi", point: point(0.25, 0.78)),
      Stop(id: "ohashi", point: point(0.18, 0.72)),
      Stop(id: "tomigaya-return", point: point(0.18, 0.66)),
      Stop(id: "hatsudai-exit", point: point(0.15, 0.56)),
    ]

    let occurrences = stops.indices.dropLast().map { index in
      let isRepeatedTomigayaSegment = index == 0 || index == 16
      return RouteAtlasJourneyOccurrence(
        occurrenceID: "demo.c2.occurrence.\(index)",
        occurrenceIndex: index,
        segmentID:
          isRepeatedTomigayaSegment
          ? "demo.c2.segment.tomigaya-to-hatsudai"
          : "demo.c2.segment.\(stops[index].id)-to-\(stops[index + 1].id)",
        points: [stops[index].point, stops[index + 1].point],
        state: .planned,
        repeatOrdinal: index == 16 ? 2 : 1,
        repeatCount: isRepeatedTomigayaSegment ? 2 : 1
      )
    }

    let bayShoreOccurrenceIDs = Set(
      occurrences
        .filter { (9...13).contains($0.occurrenceIndex) }
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
          point: stops[13].point,
          japanese: "大井PA（西行き）",
          simplifiedChinese: "大井 PA（西行）",
          english: "Oi PA (westbound)"
        ),
        landmark(
          id: "demo.c2.junction.oi",
          kind: .junction,
          occurrenceIndex: 14,
          point: stops[14].point,
          japanese: "大井JCT → C2 外回り",
          simplifiedChinese: "大井 JCT → C2 外回り",
          english: "Oi JCT → C2 outer"
        ),
        junction("ohashi", 15, stops[15].point, "大橋", "大桥"),
        landmark(
          id: "demo.c2.exit.hatsudai-minami.outer",
          kind: .exit,
          occurrenceIndex: 16,
          point: stops[17].point,
          japanese: "初台南出口（C2 外回り）",
          simplifiedChinese: "初台南出口（C2 外回り）",
          english: "Hatsudai-minami exit (C2 outer)"
        ),
      ],
      entranceCount: 1,
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
