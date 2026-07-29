import CoreLocation
import KaidoSurfaceRouting
import MapKit
import SwiftUI

struct C2NavigationDemoView: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale
  @StateObject private var model: C2NavigationDemoModel
  @State private var mapLayer = C2NavigationMapLayer.route
  @FocusState private var focusedEndpoint: C2NavigationEndpoint?

  let dismiss: () -> Void

  init(
    model: C2NavigationDemoModel = C2NavigationDemoModel(),
    dismiss: @escaping () -> Void = {}
  ) {
    _model = StateObject(wrappedValue: model)
    self.dismiss = dismiss
  }

  var body: some View {
    ZStack {
      background
        .ignoresSafeArea()

      if model.phase == .planning
        || model.phase == .routing
        || model.phase == .failed
      {
        planningStage
      } else {
        drivingStage
      }

      if model.phase == .routing {
        routingOverlay
      }
    }
    .preferredColorScheme(
      isDriving ? .dark : .light
    )
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("c2-full-navigation")
    .accessibilityValue(model.phase.rawValue)
  }

  private var planningStage: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        planningHeader
        endpointEditor
        routeContract

        ProductTopologyMapView(
          presentation: C2CompletedRouteDemo.presentation,
          usesDarkStyle: false,
          showsPositionStatus: false,
          landmarkLabelMode: .route
        )
        .frame(height: 390)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
          RoundedRectangle(cornerRadius: 14)
            .stroke(KaidoTheme.paperDivider, lineWidth: 1)
        }
        .accessibilityIdentifier("c2-navigation-planning-map")

        if let failureCode = model.failureCode {
          failureNotice(failureCode)
        }

        startButton
      }
      .padding(.horizontal, 16)
      .padding(.top, 10)
      .padding(.bottom, 28)
    }
    .scrollIndicators(.hidden)
  }

  private var planningHeader: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text("KAIDO")
          .font(.system(size: 10, weight: .black, design: .rounded))
          .tracking(1.8)
          .foregroundStyle(KaidoTheme.routeGreen)

        Text(
          copy.resolve(
            japanese: "どこからでも、経路どおりに",
            simplifiedChinese: "从任何地方，按选定路线走",
            english: "Start anywhere. Keep your route."
          )
        )
        .font(.system(size: 25, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.ink)

        Text(
          copy.resolve(
            japanese: "一般道 → 首都高 → 一般道を一つのナビに",
            simplifiedChinese: "地面道路 → 首都高 → 地面道路，一次完成",
            english: "Surface roads → Shuto route → surface roads"
          )
        )
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(KaidoTheme.quietText)
      }

      Spacer(minLength: 8)

      closeButton(usesDarkStyle: false)
    }
  }

  private var endpointEditor: some View {
    VStack(spacing: 0) {
      endpointRow(
        endpoint: .origin,
        symbol: "location.fill",
        label: copy.resolve(
          japanese: "出発地",
          simplifiedChinese: "出发地",
          english: "FROM"
        ),
        placeholder: copy.resolve(
          japanese: "現在地または住所",
          simplifiedChinese: "当前位置或地址",
          english: "Current location or address"
        ),
        text: $model.originQuery
      )

      Divider()
        .padding(.leading, 48)

      endpointRow(
        endpoint: .destination,
        symbol: "flag.checkered",
        label: copy.resolve(
          japanese: "目的地",
          simplifiedChinese: "最终目的地",
          english: "TO"
        ),
        placeholder: copy.resolve(
          japanese: "住所または場所を入力",
          simplifiedChinese: "输入地址或地点",
          english: "Enter an address or place"
        ),
        text: $model.destinationQuery
      )
    }
    .background(KaidoTheme.paperRaised)
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .stroke(KaidoTheme.paperDivider, lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("c2-navigation-endpoints")
  }

  private func endpointRow(
    endpoint: C2NavigationEndpoint,
    symbol: String,
    label: String,
    placeholder: String,
    text: Binding<String>
  ) -> some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 15, weight: .black))
        .foregroundStyle(
          endpoint == .origin
            ? KaidoTheme.routeGreen
            : KaidoTheme.evidenceCoral
        )
        .frame(width: 24)

      VStack(alignment: .leading, spacing: 2) {
        Text(label)
          .font(.system(size: 8, weight: .black, design: .monospaced))
          .foregroundStyle(KaidoTheme.quietText)

        TextField(placeholder, text: text)
          .font(.system(size: 14, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.ink)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .submitLabel(
            endpoint == .origin ? .next : .route
          )
          .focused($focusedEndpoint, equals: endpoint)
          .onSubmit {
            if endpoint == .origin {
              focusedEndpoint = .destination
            } else {
              focusedEndpoint = nil
              Task {
                await model.startNavigation()
              }
            }
          }
          .accessibilityIdentifier(
            endpoint == .origin
              ? "c2-navigation-origin"
              : "c2-navigation-destination"
          )
      }
    }
    .padding(.horizontal, 14)
    .frame(height: 62)
  }

  private var routeContract: some View {
    HStack(spacing: 8) {
      contractNode(
        title: copy.resolve(
          japanese: "一般道",
          simplifiedChinese: "地面道路",
          english: "Surface"
        ),
        detail: "MapKit",
        color: KaidoTheme.positionCyan
      )
      contractArrow
      contractNode(
        title: "富ヶ谷",
        detail: "C2 外回り",
        color: KaidoTheme.routeGreen
      )
      contractArrow
      contractNode(
        title: "C2 + B",
        detail: copy.resolve(
          japanese: "指定経路",
          simplifiedChinese: "选定路线",
          english: "RoutePlan"
        ),
        color: KaidoTheme.signalAmber
      )
      contractArrow
      contractNode(
        title: "初台南",
        detail: copy.resolve(
          japanese: "目的地へ",
          simplifiedChinese: "到目的地",
          english: "To destination"
        ),
        color: KaidoTheme.evidenceCoral
      )
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("c2-navigation-route-contract")
  }

  private func contractNode(
    title: String,
    detail: String,
    color: Color
  ) -> some View {
    VStack(spacing: 2) {
      Text(title)
        .font(.system(size: 10, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.ink)
      Text(detail)
        .font(.system(size: 7, weight: .bold, design: .monospaced))
        .foregroundStyle(KaidoTheme.quietText)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 44)
    .background(color.opacity(0.11))
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(color)
        .frame(height: 2)
    }
  }

  private var contractArrow: some View {
    Image(systemName: "chevron.right")
      .font(.system(size: 8, weight: .black))
      .foregroundStyle(KaidoTheme.quietText)
  }

  private var startButton: some View {
    Button {
      focusedEndpoint = nil
      Task {
        await model.startNavigation()
      }
    } label: {
      HStack {
        Text(
          copy.resolve(
            japanese: "全区間ナビを開始",
            simplifiedChinese: "开始完整导航模拟",
            english: "Start complete navigation"
          )
        )
        Spacer()
        Image(systemName: "arrow.right")
      }
      .font(.system(size: 15, weight: .black, design: .rounded))
      .padding(.horizontal, 18)
      .frame(maxWidth: .infinity)
      .frame(height: 54)
      .foregroundStyle(KaidoTheme.routeWhite)
      .background(
        model.canStart
          ? KaidoTheme.routeGreen
          : KaidoTheme.roadGray
      )
    }
    .buttonStyle(.plain)
    .disabled(!model.canStart)
    .accessibilityIdentifier("c2-navigation-start")
    .accessibilityValue(
      model.canStart ? "AVAILABLE" : "DESTINATION_REQUIRED"
    )
  }

  private func failureNotice(_ code: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "exclamationmark.triangle.fill")
      VStack(alignment: .leading, spacing: 3) {
        Text(
          copy.resolve(
            japanese: "地上経路を準備できません",
            simplifiedChinese: "无法准备地面路线",
            english: "Surface route could not be prepared"
          )
        )
        .font(.system(size: 12, weight: .black))
        Text(failureDetail(code))
          .font(.system(size: 10, weight: .bold))
      }
    }
    .foregroundStyle(KaidoTheme.evidenceCoral)
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(KaidoTheme.evidenceCoral.opacity(0.08))
    .accessibilityIdentifier("c2-navigation-failure")
    .accessibilityValue(code)
  }

  private var routingOverlay: some View {
    VStack(spacing: 12) {
      ProgressView()
        .tint(KaidoTheme.routeGreen)
      Text(
        copy.resolve(
          japanese: "入口と出口後の一般道を計算中",
          simplifiedChinese: "正在计算入口前和出口后的地面路线",
          english: "Calculating both surface-road legs"
        )
      )
      .font(.system(size: 12, weight: .black, design: .rounded))
      .foregroundStyle(KaidoTheme.ink)
    }
    .padding(24)
    .background(.regularMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .shadow(radius: 18)
    .accessibilityIdentifier("c2-navigation-routing")
  }

  private var drivingStage: some View {
    VStack(spacing: 10) {
      driveHeader
      guidanceCard

      if model.phase == .expressway {
        mapLayerControl
      }

      GeometryReader { proxy in
        ZStack(alignment: .bottom) {
          drivingMap
            .frame(width: proxy.size.width, height: proxy.size.height)

          if let junctionInset {
            ProductJunctionInsetView(presentation: junctionInset)
              .padding(10)
              .transition(.move(edge: .bottom).combined(with: .opacity))
          }
        }
      }
      .frame(maxHeight: .infinity)
      .clipShape(RoundedRectangle(cornerRadius: 14))
      .overlay {
        RoundedRectangle(cornerRadius: 14)
          .stroke(KaidoTheme.steel, lineWidth: 1)
      }

      journeyRail
      playbackControl
    }
    .padding(.horizontal, 12)
    .padding(.top, 6)
    .padding(.bottom, 8)
  }

  private var driveHeader: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 1) {
        Text("KAIDO · C2")
          .font(.system(size: 9, weight: .black, design: .monospaced))
          .tracking(0.8)
          .foregroundStyle(KaidoTheme.signalAmber)
        Text(phaseTitle)
          .font(.system(size: 18, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)
      }

      Spacer()

      Text("SIMULATION")
        .font(.system(size: 8, weight: .black, design: .monospaced))
        .foregroundStyle(KaidoTheme.signalAmber)
        .padding(.horizontal, 8)
        .frame(height: 26)
        .overlay {
          Capsule()
            .stroke(KaidoTheme.signalAmber.opacity(0.65), lineWidth: 1)
        }

      closeButton(usesDarkStyle: true)
    }
  }

  private var guidanceCard: some View {
    HStack(alignment: .top, spacing: 12) {
      Text(routeShield)
        .font(.system(size: 13, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.asphalt)
        .minimumScaleFactor(0.7)
        .frame(width: 52, height: 50)
        .background(KaidoTheme.signalAmber)
        .clipShape(RoundedRectangle(cornerRadius: 10))

      VStack(alignment: .leading, spacing: 3) {
        if let distance = guidanceDistance {
          Text(distance)
            .font(.system(size: 18, weight: .black, design: .rounded))
            .foregroundStyle(KaidoTheme.routeWhite)
        }
        Text(guidanceTitle)
          .font(.system(size: 15, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)
          .lineLimit(2)

        Text(guidanceDetail)
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(
            model.isTunnelPositionEstimated
              ? KaidoTheme.signalAmber
              : KaidoTheme.muted
          )
          .lineLimit(2)
      }

      Spacer(minLength: 4)

      Image(systemName: guidanceSymbol)
        .font(.system(size: 24, weight: .black))
        .foregroundStyle(KaidoTheme.signalAmber)
        .frame(width: 34)
    }
    .padding(13)
    .background(KaidoTheme.instrument)
    .clipShape(RoundedRectangle(cornerRadius: 15))
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("c2-navigation-guidance")
    .accessibilityValue(
      [
        model.phase.rawValue,
        guidanceTitle,
        guidanceDistance ?? "NO_DISTANCE",
      ].joined(separator: " | ")
    )
  }

  private var mapLayerControl: some View {
    HStack(spacing: 4) {
      ForEach(C2NavigationMapLayer.allCases, id: \.rawValue) { layer in
        Button {
          withAnimation(.easeOut(duration: 0.18)) {
            mapLayer = layer
          }
        } label: {
          Text(mapLayerTitle(layer))
            .font(.system(size: 10, weight: .black, design: .rounded))
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .foregroundStyle(
              mapLayer == layer
                ? KaidoTheme.asphalt
                : KaidoTheme.muted
            )
            .background(
              mapLayer == layer
                ? KaidoTheme.signalAmber
                : KaidoTheme.instrument
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
          "c2-navigation-map-\(layer.rawValue)"
        )
        .accessibilityAddTraits(
          mapLayer == layer ? .isSelected : []
        )
      }
    }
    .padding(3)
    .background(KaidoTheme.instrument)
    .clipShape(RoundedRectangle(cornerRadius: 9))
  }

  @ViewBuilder
  private var drivingMap: some View {
    switch model.phase {
    case .surfaceAccess, .entryTransition, .exitTransition,
      .surfaceEgress, .completed:
      if let route = model.activeSurfaceRoute {
        C2SurfaceRouteMap(
          candidate: route,
          progressFraction: model.surfaceProgressFraction,
          isCompleted: model.phase == .completed
        )
      } else {
        Color(white: 0.12)
      }
    case .expressway:
      ProductTopologyMapView(
        presentation: model.topologyPresentation,
        usesDarkStyle: true,
        showsPositionStatus: true,
        landmarkLabelMode:
          mapLayer == .facilities ? .facilities : .route
      )
    case .planning, .routing, .failed:
      Color.clear
    }
  }

  private var journeyRail: some View {
    VStack(spacing: 7) {
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule()
            .fill(KaidoTheme.steel)
          Capsule()
            .fill(KaidoTheme.signalAmber)
            .frame(
              width: proxy.size.width * model.journeyProgressFraction
            )
        }
      }
      .frame(height: 5)

      HStack {
        railLabel(
          copy.resolve(
            japanese: "入口へ",
            simplifiedChinese: "到入口",
            english: "Entrance"
          )
        )
        Spacer()
        railLabel("C2 + B")
        Spacer()
        railLabel(
          copy.resolve(
            japanese: "出口",
            simplifiedChinese: "出口",
            english: "Exit"
          )
        )
        Spacer()
        railLabel(
          copy.resolve(
            japanese: "目的地",
            simplifiedChinese: "目的地",
            english: "Destination"
          )
        )
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 9)
    .background(KaidoTheme.instrument)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("c2-navigation-progress")
    .accessibilityValue(
      "\(Int((model.journeyProgressFraction * 100).rounded())) percent"
    )
  }

  private func railLabel(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 7, weight: .black, design: .rounded))
      .foregroundStyle(KaidoTheme.muted)
  }

  private var playbackControl: some View {
    HStack(spacing: 8) {
      if model.phase == .completed {
        Button {
          model.replay()
        } label: {
          playbackLabel(
            title: copy.resolve(
              japanese: "もう一度走る",
              simplifiedChinese: "重新模拟",
              english: "Replay"
            ),
            symbol: "arrow.counterclockwise"
          )
        }
        .buttonStyle(.plain)
      } else {
        Button {
          if model.isPlaying {
            model.pause()
          } else {
            model.resume()
          }
        } label: {
          playbackLabel(
            title:
              model.isPlaying
              ? copy.resolve(
                japanese: "一時停止",
                simplifiedChinese: "暂停",
                english: "Pause"
              )
              : copy.resolve(
                japanese: "続ける",
                simplifiedChinese: "继续",
                english: "Resume"
              ),
            symbol: model.isPlaying ? "pause.fill" : "play.fill"
          )
        }
        .buttonStyle(.plain)
      }

      Button {
        model.reset()
      } label: {
        Image(systemName: "stop.fill")
          .font(.system(size: 12, weight: .black))
          .frame(width: 46, height: 42)
          .foregroundStyle(KaidoTheme.routeWhite)
          .background(KaidoTheme.steel)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        copy.resolve(
          japanese: "シミュレーションを終了",
          simplifiedChinese: "结束模拟",
          english: "End simulation"
        )
      )
      .accessibilityIdentifier("c2-navigation-stop")
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("c2-navigation-playback")
  }

  private func playbackLabel(
    title: String,
    symbol: String
  ) -> some View {
    Label(title, systemImage: symbol)
      .font(.system(size: 12, weight: .black, design: .rounded))
      .frame(maxWidth: .infinity)
      .frame(height: 42)
      .foregroundStyle(KaidoTheme.asphalt)
      .background(KaidoTheme.signalAmber)
      .accessibilityIdentifier("c2-navigation-play-pause")
  }

  private func closeButton(usesDarkStyle: Bool) -> some View {
    Button {
      dismiss()
    } label: {
      Image(systemName: "xmark")
        .font(.system(size: 12, weight: .black))
        .frame(width: 36, height: 36)
        .foregroundStyle(
          usesDarkStyle ? KaidoTheme.routeWhite : KaidoTheme.ink
        )
        .background(
          usesDarkStyle ? KaidoTheme.instrument : KaidoTheme.paperRaised
        )
        .clipShape(Circle())
        .overlay {
          Circle()
            .stroke(
              usesDarkStyle
                ? KaidoTheme.steel
                : KaidoTheme.paperDivider,
              lineWidth: 1
            )
        }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      copy.resolve(
        japanese: "閉じる",
        simplifiedChinese: "关闭",
        english: "Close"
      )
    )
  }

  private var background: Color {
    isDriving ? KaidoTheme.asphalt : KaidoTheme.paper
  }

  private var isDriving: Bool {
    switch model.phase {
    case .surfaceAccess, .entryTransition, .expressway,
      .exitTransition, .surfaceEgress, .completed:
      true
    case .planning, .routing, .failed:
      false
    }
  }

  private var phaseTitle: String {
    switch model.phase {
    case .surfaceAccess:
      copy.resolve(
        japanese: "富ヶ谷入口へ",
        simplifiedChinese: "前往富ヶ谷入口",
        english: "To Tomigaya entrance"
      )
    case .entryTransition:
      copy.resolve(
        japanese: "首都高へ進入",
        simplifiedChinese: "正在进入首都高",
        english: "Entering Shuto Expressway"
      )
    case .expressway:
      "C2 + B"
    case .exitTransition:
      copy.resolve(
        japanese: "初台南出口",
        simplifiedChinese: "驶出初台南出口",
        english: "Hatsudai-minami exit"
      )
    case .surfaceEgress:
      copy.resolve(
        japanese: "目的地へ",
        simplifiedChinese: "前往最终目的地",
        english: "To final destination"
      )
    case .completed:
      copy.resolve(
        japanese: "到着",
        simplifiedChinese: "已到达",
        english: "Arrived"
      )
    case .planning, .routing, .failed:
      ""
    }
  }

  private var routeShield: String {
    switch model.phase {
    case .surfaceAccess, .surfaceEgress, .completed:
      copy.resolve(
        japanese: "一般道",
        simplifiedChinese: "地面",
        english: "ROAD"
      )
    case .entryTransition, .exitTransition:
      "C2"
    case .expressway:
      (10...12).contains(model.expresswayOccurrenceIndex)
        ? "B"
        : "C2"
    case .planning, .routing, .failed:
      "—"
    }
  }

  private var guidanceTitle: String {
    if let step = model.currentSurfaceStep,
      model.phase == .surfaceAccess || model.phase == .surfaceEgress
    {
      return step.instruction.isEmpty ? phaseTitle : step.instruction
    }
    switch model.phase {
    case .entryTransition:
      return copy.resolve(
        japanese: "富ヶ谷入口から C2 外回りへ",
        simplifiedChinese: "从富ヶ谷入口进入 C2 外回",
        english: "Enter C2 outer at Tomigaya"
      )
    case .expressway:
      return highwayGuidanceTitle
    case .exitTransition:
      return copy.resolve(
        japanese: "初台南出口から一般道へ",
        simplifiedChinese: "从初台南出口进入地面道路",
        english: "Leave at Hatsudai-minami"
      )
    case .completed:
      return copy.resolve(
        japanese: "目的地に到着しました",
        simplifiedChinese: "已到达最终目的地",
        english: "You have arrived"
      )
    case .surfaceAccess, .surfaceEgress:
      return phaseTitle
    case .planning, .routing, .failed:
      return ""
    }
  }

  private var highwayGuidanceTitle: String {
    switch model.highwayInstruction {
    case .continueC2:
      return copy.resolve(
        japanese: "C2 外回りをそのまま進む",
        simplifiedChinese: "沿 C2 外回继续行驶",
        english: "Continue on C2 outer"
      )
    case .kasaiRight:
      return copy.resolve(
        japanese: "葛西JCTを右分岐、B 横浜方面へ",
        simplifiedChinese: "葛西 JCT 右分岔，进入 B 横浜方向",
        english: "Keep right at Kasai JCT for B Yokohama"
      )
    case .continueB:
      return copy.resolve(
        japanese: "B 湾岸線西行きを進む",
        simplifiedChinese: "沿 B 湾岸线西行继续",
        english: "Continue westbound on Bayshore Route B"
      )
    case .oiLeft:
      return copy.resolve(
        japanese: "大井JCTを左分岐、C2 外回りへ",
        simplifiedChinese: "大井 JCT 左分岔，进入 C2 外回",
        english: "Keep left at Oi JCT for C2 outer"
      )
    case .tunnelC2:
      return copy.resolve(
        japanese: "山手トンネル内、C2 外回りを進む",
        simplifiedChinese: "山手隧道内沿 C2 外回继续",
        english: "Continue on C2 outer in Yamate Tunnel"
      )
    case .hatsudaiExit:
      return copy.resolve(
        japanese: "初台南出口へ",
        simplifiedChinese: "驶向初台南出口",
        english: "Take Hatsudai-minami exit"
      )
    }
  }

  private var guidanceDetail: String {
    if model.isTunnelPositionEstimated {
      return copy.resolve(
        japanese: "トンネル内 · 位置は推定 · 経路は変更しません",
        simplifiedChinese: "隧道内 · 位置为估算 · 不改变选定路线",
        english: "Tunnel · estimated position · route unchanged"
      )
    }
    switch model.phase {
    case .surfaceAccess:
      return copy.resolve(
        japanese: "MapKit の一般道案内 · 高速は富ヶ谷から",
        simplifiedChinese: "MapKit 地面导航 · 高速段从富ヶ谷开始",
        english: "MapKit surface guidance · expressway starts at Tomigaya"
      )
    case .entryTransition:
      return copy.resolve(
        japanese: "入口認識後、C2 経路へ自動切替",
        simplifiedChinese: "识别入口后自动切换到 C2 路线",
        english: "Switching to the C2 route after entry recognition"
      )
    case .expressway:
      return copy.resolve(
        japanese: "首都高公式の方向・分岐情報を反映",
        simplifiedChinese: "方向与分岔信息已按首都高官方资料核对",
        english: "Directions and branches checked against official Shuto sources"
      )
    case .exitTransition:
      return copy.resolve(
        japanese: "出口引き継ぎ後、一般道案内へ",
        simplifiedChinese: "出口交接后切换到地面导航",
        english: "Surface guidance resumes after the exit handoff"
      )
    case .surfaceEgress:
      return model.destination?.title ?? ""
    case .completed:
      return model.destination?.title ?? ""
    case .planning, .routing, .failed:
      return ""
    }
  }

  private var guidanceDistance: String? {
    if let step = model.currentSurfaceStep,
      model.phase == .surfaceAccess || model.phase == .surfaceEgress
    {
      return distanceLabel(step.distanceMeters)
    }
    if model.phase == .expressway,
      model.highwayInstruction == .oiLeft
    {
      return "500 m"
    }
    return nil
  }

  private var junctionInset: ProductJunctionInsetPresentation? {
    guard let inset = model.junctionInset else { return nil }
    let instruction: String
    switch inset.decisionZoneID {
    case "demo.c2.kasai.outer-to-b-west":
      instruction = copy.resolve(
        japanese: "葛西JCTを右分岐、B湾岸線西行（横浜方面）へ",
        simplifiedChinese: "葛西 JCT 右分岔，进入 B 湾岸线西行（横滨方向）",
        english: "Keep right at Kasai JCT for B westbound toward Yokohama"
      )
    case "demo.c2.oi.b-west-to-c2-outer":
      instruction = copy.resolve(
        japanese: "大井JCTを左分岐、C2外回り（渋谷・中央道方面）へ",
        simplifiedChinese: "大井 JCT 左分岔，进入 C2 外回（涩谷、中央道方向）",
        english: "Keep left at Oi JCT for C2 outer toward Shibuya and Chuo"
      )
    default:
      instruction = inset.localizedInstruction
    }
    return ProductJunctionInsetPresentation(
      decisionZoneID: inset.decisionZoneID,
      movementOccurrenceID: inset.movementOccurrenceID,
      selectedBranch: inset.selectedBranch,
      distanceMeters: inset.distanceMeters,
      japaneseSignText: inset.japaneseSignText,
      localizedInstruction: instruction,
      routeShield: inset.routeShield
    )
  }

  private var guidanceSymbol: String {
    switch model.phase {
    case .surfaceAccess, .surfaceEgress:
      "arrow.up"
    case .entryTransition:
      "arrow.merge"
    case .expressway:
      switch model.highwayInstruction {
      case .kasaiRight:
        "arrow.up.right"
      case .oiLeft:
        "arrow.up.left"
      case .hatsudaiExit:
        "arrow.turn.up.left"
      case .continueC2, .continueB, .tunnelC2:
        "arrow.up"
      }
    case .exitTransition:
      "arrow.turn.up.left"
    case .completed:
      "checkmark.circle.fill"
    case .planning, .routing, .failed:
      "arrow.up"
    }
  }

  private func mapLayerTitle(_ layer: C2NavigationMapLayer) -> String {
    switch layer {
    case .route:
      copy.resolve(
        japanese: "走行ルート",
        simplifiedChinese: "当前路线",
        english: "Route"
      )
    case .facilities:
      copy.resolve(
        japanese: "全体 · IC / PA",
        simplifiedChinese: "全程 · IC / PA",
        english: "Overview · IC / PA"
      )
    }
  }

  private func failureDetail(_ code: String) -> String {
    switch code {
    case "CURRENT_LOCATION_PERMISSION_DENIED":
      return copy.resolve(
        japanese: "位置情報を許可するか、出発地を住所で入力してください。",
        simplifiedChinese: "请允许定位，或直接输入出发地址。",
        english: "Allow location access or enter a starting address."
      )
    case "PLACE_NOT_FOUND":
      return copy.resolve(
        japanese: "住所または場所名を確認してください。",
        simplifiedChinese: "请检查输入的地址或地点名称。",
        english: "Check the address or place name."
      )
    default:
      return copy.resolve(
        japanese: "ネットワークを確認して、もう一度お試しください。",
        simplifiedChinese: "请检查网络后重试。",
        english: "Check the network and try again."
      )
    }
  }

  private func distanceLabel(_ meters: Double) -> String {
    if meters >= 1_000 {
      return String(format: "%.1f km", meters / 1_000)
    }
    return "\(Int(meters.rounded())) m"
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }
}

private enum C2NavigationEndpoint: Hashable {
  case origin
  case destination
}

private enum C2NavigationMapLayer: String, CaseIterable {
  case route
  case facilities
}

private struct C2SurfaceRouteMap: View {
  let candidate: SurfaceRouteCandidate
  let progressFraction: Double
  let isCompleted: Bool

  @State private var camera: MapCameraPosition = .automatic

  var body: some View {
    Map(position: $camera, interactionModes: []) {
      MapPolyline(coordinates: coordinates)
        .stroke(
          KaidoTheme.routeGreen,
          style: StrokeStyle(
            lineWidth: 7,
            lineCap: .round,
            lineJoin: .round
          )
        )

      if let first = coordinates.first {
        Annotation("START", coordinate: first) {
          endpointMarker(
            symbol: "circle.fill",
            color: KaidoTheme.positionCyan
          )
        }
      }

      if let last = coordinates.last {
        Annotation("FINISH", coordinate: last) {
          endpointMarker(
            symbol:
              isCompleted ? "checkmark.circle.fill" : "flag.checkered",
            color: KaidoTheme.evidenceCoral
          )
        }
      }

      if let currentCoordinate {
        Annotation("CURRENT", coordinate: currentCoordinate) {
          ZStack {
            Circle()
              .fill(.white)
              .frame(width: 24, height: 24)
            Image(systemName: "location.north.fill")
              .font(.system(size: 12, weight: .black))
              .foregroundStyle(KaidoTheme.routeGreen)
          }
          .shadow(radius: 3)
        }
      }
    }
    .mapStyle(.standard(elevation: .flat))
    .overlay(alignment: .bottomTrailing) {
      Text("MapKit")
        .font(.system(size: 7, weight: .black, design: .monospaced))
        .foregroundStyle(KaidoTheme.ink)
        .padding(.horizontal, 6)
        .frame(height: 18)
        .background(.thinMaterial)
        .clipShape(Capsule())
        .padding(8)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Surface route map")
    .accessibilityValue(
      "\(Int((progressFraction * 100).rounded())) percent"
    )
    .accessibilityIdentifier("c2-navigation-surface-map")
  }

  private var coordinates: [CLLocationCoordinate2D] {
    candidate.coordinates.map {
      CLLocationCoordinate2D(
        latitude: $0.latitude,
        longitude: $0.longitude
      )
    }
  }

  private var currentCoordinate: CLLocationCoordinate2D? {
    guard !coordinates.isEmpty else { return nil }
    let index = min(
      coordinates.count - 1,
      max(
        0,
        Int(
          (progressFraction * Double(coordinates.count - 1)).rounded()
        )
      )
    )
    return coordinates[index]
  }

  private func endpointMarker(
    symbol: String,
    color: Color
  ) -> some View {
    Image(systemName: symbol)
      .font(.system(size: 12, weight: .black))
      .foregroundStyle(.white)
      .frame(width: 22, height: 22)
      .background(color)
      .clipShape(Circle())
      .shadow(radius: 2)
  }
}
