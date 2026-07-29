import CoreLocation
import KaidoRouting
import MapKit
import SwiftUI

struct WholeShutoProductView: View {
  @StateObject private var model: WholeShutoProductModel
  @State private var showsNetworkFacts = false

  init(model: WholeShutoProductModel = WholeShutoProductModel()) {
    _model = StateObject(wrappedValue: model)
  }

  var body: some View {
    ZStack {
      map
        .ignoresSafeArea()

      VStack(spacing: 0) {
        topBar
        Spacer(minLength: 0)

        if isDriving {
          drivingDock
        } else {
          planningDock
        }
      }

      if let prompt = model.activeJunctionPrompt {
        VStack {
          Spacer()
          WholeShutoJunctionInset(prompt: prompt)
            .padding(.horizontal, 14)
            .padding(.bottom, 142)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .allowsHitTesting(false)
      }
    }
    .animation(.easeOut(duration: 0.22), value: model.phase)
    .animation(
      .easeOut(duration: 0.22),
      value: model.activeJunctionPrompt
    )
    .preferredColorScheme(isDriving ? .dark : .light)
    .sheet(isPresented: $showsNetworkFacts) {
      WholeShutoNetworkFactsView(model: model)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("whole-shuto-product")
    .accessibilityValue(model.phase.rawValue)
  }

  @ViewBuilder
  private var map: some View {
    if model.mapMode == .network {
      WholeShutoNetworkDiagram(
        database: model.database,
        selectedRoute: model.selectedRoute,
        currentCoordinate: model.currentCoordinate,
        usesDarkStyle: isDriving,
        visibleBottomFraction:
          isDriving ? 0.92 : 0.66
      )
    } else {
      WholeShutoGeographicMap(model: model)
    }
  }

  private var topBar: some View {
    VStack(spacing: 8) {
      HStack(spacing: 10) {
        if model.phase != .planning {
          Button {
            model.reset()
          } label: {
            Image(systemName: "chevron.left")
              .font(.system(size: 14, weight: .black))
              .frame(width: 38, height: 38)
          }
          .buttonStyle(WholeShutoCircleButtonStyle(isDriving: isDriving))
          .accessibilityLabel("返回路线规划")
        }

        VStack(alignment: .leading, spacing: 0) {
          Text("KAIDO")
            .font(.system(size: 9, weight: .black, design: .rounded))
            .tracking(1.7)
            .foregroundStyle(
              isDriving ? KaidoTheme.confirmedGreen : KaidoTheme.routeGreen
            )
          Text(topTitle)
            .font(.system(size: 18, weight: .black, design: .rounded))
            .foregroundStyle(
              isDriving ? KaidoTheme.routeWhite : KaidoTheme.ink
            )
        }

        Spacer()

        mapModeControl

        if !isDriving {
          Button {
            showsNetworkFacts = true
          } label: {
            Image(systemName: "info")
              .font(.system(size: 14, weight: .black))
              .frame(width: 38, height: 38)
          }
          .buttonStyle(WholeShutoCircleButtonStyle(isDriving: false))
          .accessibilityLabel("全网数据说明")
        }
      }

      if isDriving {
        instructionBanner
      }
    }
    .padding(.horizontal, 14)
    .padding(.top, 7)
  }

  private var mapModeControl: some View {
    HStack(spacing: 0) {
      mapModeButton(
        .geographic,
        symbol: "map.fill",
        label: "地图"
      )
      mapModeButton(
        .network,
        symbol: "point.3.connected.trianglepath.dotted",
        label: "全网"
      )
    }
    .padding(3)
    .background(
      isDriving
        ? KaidoTheme.instrument.opacity(0.94)
        : KaidoTheme.paperRaised.opacity(0.96)
    )
    .clipShape(Capsule())
    .overlay {
      Capsule()
        .stroke(
          isDriving ? KaidoTheme.steel : KaidoTheme.paperDivider,
          lineWidth: 1
        )
    }
  }

  private func mapModeButton(
    _ mode: WholeShutoMapMode,
    symbol: String,
    label: String
  ) -> some View {
    Button {
      model.mapMode = mode
    } label: {
      HStack(spacing: 4) {
        Image(systemName: symbol)
          .font(.system(size: 10, weight: .black))
        Text(label)
          .font(.system(size: 9, weight: .black, design: .rounded))
      }
      .foregroundStyle(
        model.mapMode == mode
          ? KaidoTheme.routeWhite
          : isDriving ? KaidoTheme.muted : KaidoTheme.quietText
      )
      .padding(.horizontal, 9)
      .frame(height: 30)
      .background(
        model.mapMode == mode
          ? KaidoTheme.routeGreen
          : Color.clear
      )
      .clipShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("whole-shuto-map-\(mode.rawValue.lowercased())")
  }

  private var planningDock: some View {
    VStack(spacing: 0) {
      if model.phase == .planning {
        routeComposer
      } else {
        routeReview
      }
    }
    .background(.ultraThinMaterial)
    .clipShape(
      UnevenRoundedRectangle(
        topLeadingRadius: 20,
        topTrailingRadius: 20
      )
    )
    .overlay(alignment: .top) {
      Capsule()
        .fill(KaidoTheme.roadGray.opacity(0.65))
        .frame(width: 36, height: 4)
        .padding(.top, 8)
    }
    .shadow(color: .black.opacity(0.16), radius: 18, y: -3)
  }

  private var routeComposer: some View {
    VStack(spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("首都高全网导航")
            .font(.system(size: 22, weight: .black, design: .rounded))
            .foregroundStyle(KaidoTheme.ink)
          Text("任意地点出发 · 自动选择方向正确的入口与出口")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(KaidoTheme.quietText)
        }
        Spacer()
        Text("26 ROUTES")
          .font(.system(size: 8, weight: .black, design: .monospaced))
          .foregroundStyle(KaidoTheme.routeGreenDeep)
          .padding(.horizontal, 8)
          .frame(height: 24)
          .background(KaidoTheme.confirmedGreen.opacity(0.18))
          .clipShape(Capsule())
      }

      VStack(spacing: 0) {
        routeField(
          symbol: "location.fill",
          tint: KaidoTheme.positionCyan,
          label: "出发地",
          text: $model.originQuery,
          prompt: "当前位置或地点"
        )
        HStack(spacing: 0) {
          Rectangle()
            .fill(KaidoTheme.paperDivider)
            .frame(width: 1, height: 12)
            .padding(.leading, 16)
          Rectangle()
            .fill(KaidoTheme.paperDivider)
            .frame(height: 1)
            .padding(.leading, 15)
        }
        routeField(
          symbol: "flag.fill",
          tint: KaidoTheme.evidenceCoral,
          label: "目的地",
          text: $model.destinationQuery,
          prompt: "输入任何目的地"
        )
      }
      .padding(.horizontal, 10)
      .background(KaidoTheme.paperRaised.opacity(0.92))
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay {
        RoundedRectangle(cornerRadius: 12)
          .stroke(KaidoTheme.paperDivider, lineWidth: 1)
      }

      HStack(spacing: 8) {
        preferenceMenu

        Button {
          model.planJourney()
        } label: {
          HStack {
            if model.isPlanning {
              ProgressView()
                .tint(.white)
            } else {
              Text("规划路线")
              Spacer()
              Image(systemName: "arrow.right")
            }
          }
          .font(.system(size: 13, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)
          .padding(.horizontal, 16)
          .frame(maxWidth: .infinity)
          .frame(height: 48)
          .background(KaidoTheme.routeGreen)
          .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(model.isPlanning)
        .accessibilityIdentifier("whole-shuto-plan-route")
      }

      if let failureCode = model.failureCode {
        HStack(spacing: 7) {
          Image(systemName: "exclamationmark.triangle.fill")
          Text(failureMessage(failureCode))
          Spacer()
          if failureCode == "LOCATION_UNAVAILABLE" {
            Button("使用示例") {
              model.usePreviewPlaces()
            }
            .font(.system(size: 10, weight: .black))
          }
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(KaidoTheme.evidenceCoral)
      }
    }
    .padding(.horizontal, 16)
    .padding(.top, 22)
    .padding(.bottom, 14)
  }

  private func routeField(
    symbol: String,
    tint: Color,
    label: String,
    text: Binding<String>,
    prompt: String
  ) -> some View {
    HStack(spacing: 10) {
      ZStack {
        Circle()
          .fill(tint.opacity(0.18))
          .frame(width: 30, height: 30)
        Image(systemName: symbol)
          .font(.system(size: 11, weight: .black))
          .foregroundStyle(tint)
      }

      VStack(alignment: .leading, spacing: 1) {
        Text(label)
          .font(.system(size: 8, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.quietText)
        TextField(prompt, text: text)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(KaidoTheme.ink)
          .textInputAutocapitalization(.never)
          .submitLabel(.route)
          .onSubmit {
            if !model.destinationQuery.isEmpty {
              model.planJourney()
            }
          }
      }
    }
    .frame(height: 52)
  }

  private var preferenceMenu: some View {
    Menu {
      Button("推荐路线") { model.preference = .recommended }
      Button("减少复杂分岔") { model.preference = .fewerJunctions }
      Button("优先湾岸线") { model.preference = .preferBayshore }
    } label: {
      VStack(alignment: .leading, spacing: 1) {
        Text("路线偏好")
          .font(.system(size: 8, weight: .black, design: .rounded))
        HStack(spacing: 5) {
          Text(preferenceLabel)
          Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 8, weight: .black))
        }
        .font(.system(size: 11, weight: .black, design: .rounded))
      }
      .foregroundStyle(KaidoTheme.ink)
      .padding(.horizontal, 12)
      .frame(width: 126, height: 48, alignment: .leading)
      .background(KaidoTheme.paperRaised.opacity(0.92))
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .overlay {
        RoundedRectangle(cornerRadius: 10)
          .stroke(KaidoTheme.paperDivider, lineWidth: 1)
      }
    }
  }

  private var routeReview: some View {
    VStack(spacing: 11) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text(routeSummaryTitle)
            .font(.system(size: 19, weight: .black, design: .rounded))
          Text(routeSummarySubtitle)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(KaidoTheme.quietText)
        }
        Spacer()
        Text(distanceLabel(model.selectedRoute?.distanceMeters ?? 0))
          .font(.system(size: 20, weight: .black, design: .rounded))
      }
      .foregroundStyle(KaidoTheme.ink)

      if model.recommendations.count > 1 {
        ScrollView(.horizontal) {
          HStack(spacing: 7) {
            ForEach(model.recommendations.indices, id: \.self) { index in
              Button {
                model.selectRecommendation(at: index)
              } label: {
                let route = model.recommendations[index].route
                VStack(alignment: .leading, spacing: 3) {
                  Text(index == 0 ? "推荐" : "备选 \(index)")
                    .font(.system(size: 8, weight: .black))
                  Text(
                    route.routeIDsInOrder
                      .map(shieldLabel)
                      .joined(separator: " · ")
                  )
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .lineLimit(1)
                  Text(distanceLabel(route.distanceMeters))
                    .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(
                  index == model.selectedRecommendationIndex
                    ? KaidoTheme.routeWhite
                    : KaidoTheme.ink
                )
                .padding(.horizontal, 11)
                .frame(height: 55, alignment: .leading)
                .background(
                  index == model.selectedRecommendationIndex
                    ? KaidoTheme.routeGreen
                    : KaidoTheme.paperRaised
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
              }
              .buttonStyle(.plain)
            }
          }
        }
        .scrollIndicators(.hidden)
      }

      HStack(spacing: 8) {
        routeBoundary(
          title: model.selectedRoute?.entryFacility.nameJA ?? "—",
          detail:
            (model.selectedRoute?.entryFacility.entranceDirections ?? [])
            .joined(separator: " / "),
          label: "入口",
          tint: KaidoTheme.positionCyan
        )
        Image(systemName: "arrow.right")
          .font(.system(size: 11, weight: .black))
          .foregroundStyle(KaidoTheme.roadGray)
        routeBoundary(
          title: model.selectedRoute?.exitFacility.nameJA ?? "—",
          detail:
            (model.selectedRoute?.exitFacility.exitDirections ?? [])
            .joined(separator: " / "),
          label: "出口",
          tint: KaidoTheme.evidenceCoral
        )
      }

      HStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 2) {
          Text("当前通行状态")
            .font(.system(size: 8, weight: .black))
          Text("尚未连接实时路况 · 出发前需确认")
            .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(KaidoTheme.signalAmber)
        Spacer()
        Button {
          model.startNavigationSimulation()
        } label: {
          HStack(spacing: 8) {
            Text("开始完整预演")
            Image(systemName: "play.fill")
          }
          .font(.system(size: 12, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)
          .padding(.horizontal, 15)
          .frame(height: 45)
          .background(KaidoTheme.routeGreen)
          .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("whole-shuto-start-simulation")
      }
    }
    .padding(.horizontal, 16)
    .padding(.top, 22)
    .padding(.bottom, 12)
  }

  private func routeBoundary(
    title: String,
    detail: String,
    label: String,
    tint: Color
  ) -> some View {
    HStack(spacing: 8) {
      Circle()
        .fill(tint)
        .frame(width: 9, height: 9)
      VStack(alignment: .leading, spacing: 1) {
        Text("\(label) · \(title)")
          .font(.system(size: 11, weight: .black, design: .rounded))
          .lineLimit(1)
        Text(detail.isEmpty ? "方向由路线确定" : detail)
          .font(.system(size: 8, weight: .bold))
          .foregroundStyle(KaidoTheme.quietText)
          .lineLimit(1)
      }
    }
    .foregroundStyle(KaidoTheme.ink)
    .padding(.horizontal, 10)
    .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
    .background(KaidoTheme.paperRaised.opacity(0.88))
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  private var drivingDock: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Circle()
            .fill(positionStatusColor)
            .frame(width: 7, height: 7)
          Text(positionStatusLabel)
            .font(.system(size: 8, weight: .black, design: .rounded))
            .foregroundStyle(positionStatusColor)
            .accessibilityIdentifier("whole-shuto-position-state")
            .accessibilityValue(model.positionState.rawValue)
        }
        Text(drivingDistanceLabel)
          .font(.system(size: 20, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)
        Text(drivingBoundaryLabel)
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(KaidoTheme.muted)
          .lineLimit(1)
      }

      Spacer(minLength: 4)

      Button {
        model.advanceSimulation()
      } label: {
        Image(systemName: "forward.end.fill")
          .font(.system(size: 13, weight: .black))
          .frame(width: 42, height: 42)
      }
      .buttonStyle(WholeShutoCircleButtonStyle(isDriving: true))
      .accessibilityLabel("前进一步")

      Button {
        model.togglePlayback()
      } label: {
        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: 15, weight: .black))
          .frame(width: 48, height: 48)
          .foregroundStyle(KaidoTheme.asphalt)
          .background(KaidoTheme.confirmedGreen)
          .clipShape(Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(model.isPlaying ? "暂停预演" : "继续预演")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(KaidoTheme.asphalt.opacity(0.96))
    .overlay(alignment: .top) {
      Rectangle()
        .fill(KaidoTheme.steel)
        .frame(height: 1)
    }
  }

  private var instructionBanner: some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 9)
          .fill(KaidoTheme.routeGreen)
          .frame(width: 48, height: 48)
        Image(systemName: instructionSymbol)
          .font(.system(size: 22, weight: .black))
          .foregroundStyle(KaidoTheme.routeWhite)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(instructionKicker)
          .font(.system(size: 8, weight: .black, design: .rounded))
          .tracking(0.5)
          .foregroundStyle(KaidoTheme.confirmedGreen)
        Text(instructionTitle)
          .font(.system(size: 16, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)
          .lineLimit(2)
      }
      Spacer()
      if let routeID = activeRouteShield {
        Text(shieldLabel(routeID))
          .font(.system(size: 12, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)
          .frame(minWidth: 38, minHeight: 30)
          .background(routeColor(routeID))
          .clipShape(RoundedRectangle(cornerRadius: 6))
      }
    }
    .padding(8)
    .background(KaidoTheme.asphalt.opacity(0.94))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(KaidoTheme.steel, lineWidth: 1)
    }
  }

  private var isDriving: Bool {
    ![.planning, .review].contains(model.phase)
  }

  private var topTitle: String {
    if isDriving {
      return "首都高导航预演"
    }
    return model.phase == .review ? "路线确认" : "首都高全网"
  }

  private var routeSummaryTitle: String {
    guard let route = model.selectedRoute else { return "路线" }
    return route.routeIDsInOrder
      .map(shieldLabel)
      .joined(separator: "  →  ")
  }

  private var routeSummarySubtitle: String {
    guard let route = model.selectedRoute else { return "" }
    return "\(route.entryFacility.nameJA)入口 → \(route.exitFacility.nameJA)出口"
  }

  private var preferenceLabel: String {
    switch model.preference {
    case .recommended: "推荐"
    case .fewerJunctions: "少分岔"
    case .preferBayshore: "湾岸优先"
    }
  }

  private var instructionSymbol: String {
    switch model.phase {
    case .surfaceAccess: "arrow.turn.up.right"
    case .entryTransition: "arrow.up.right"
    case .expressway:
      model.activeJunctionPrompt == nil
        ? "arrow.up" : "arrow.triangle.branch"
    case .exitTransition: "arrow.up.right"
    case .surfaceEgress: "arrow.turn.up.left"
    case .completed: "checkmark"
    case .planning, .review: "map"
    }
  }

  private var instructionKicker: String {
    switch model.phase {
    case .surfaceAccess: "一般道路 · 前往入口"
    case .entryTransition: "进入首都高"
    case .expressway:
      model.activeJunctionPrompt == nil ? "继续行驶" : "接近分岔"
    case .exitTransition: "驶出首都高"
    case .surfaceEgress: "一般道路 · 前往目的地"
    case .completed: "已到达"
    case .planning, .review: ""
    }
  }

  private var instructionTitle: String {
    guard let route = model.selectedRoute else { return "" }
    switch model.phase {
    case .surfaceAccess:
      return "前往 \(route.entryFacility.nameJA)入口"
    case .entryTransition:
      return
        "从 \(route.entryFacility.nameJA) 进入 "
        + "\(route.routeIDsInOrder.first.map(shieldLabel) ?? "首都高")"
    case .expressway:
      if let prompt = model.activeJunctionPrompt {
        return "\(prompt.nameJA)：驶向 \(shieldLabel(prompt.outgoingRouteID))"
      }
      return "沿 \(activeRouteShield.map(shieldLabel) ?? "当前路线") 继续"
    case .exitTransition:
      return "从 \(route.exitFacility.nameJA)出口 驶出"
    case .surfaceEgress:
      return "继续前往 \(model.destination?.title ?? "目的地")"
    case .completed:
      return "已到达 \(model.destination?.title ?? "目的地")"
    case .planning, .review:
      return ""
    }
  }

  private var activeRouteShield: String? {
    if let prompt = model.activeJunctionPrompt {
      return prompt.outgoingRouteID
    }
    if model.phase == .expressway, let routeID = model.activeRouteID {
      return routeID
    }
    guard let route = model.selectedRoute else { return nil }
    let index = min(
      route.routeIDsInOrder.count - 1,
      max(
        0,
        Int(
          model.progressFraction
            * Double(max(route.routeIDsInOrder.count, 1))
        )
      )
    )
    guard route.routeIDsInOrder.indices.contains(index) else { return nil }
    return route.routeIDsInOrder[index]
  }

  private var positionStatusLabel: String {
    let prefix = model.restoredFromCheckpoint ? "已恢复 · " : ""
    switch model.positionState {
    case .surfacePreview:
      return prefix + "MapKit 一般道路 · 预演"
    case .boundaryTransition:
      return prefix + "边界转换 · 预演"
    case .networkPreview:
      return prefix + "路线位置 · 预演"
    case .networkDegraded:
      return prefix + "定位证据不足 · 未推进"
    case .tunnelEstimated:
      return prefix + "隧道位置推算 · 预演"
    case .routeInterrupted:
      return prefix + "路线中断 · 无已发布重入路线"
    case .completed:
      return "路线完成"
    case .unavailable:
      return ""
    }
  }

  private var positionStatusColor: Color {
    switch model.positionState {
    case .completed:
      return KaidoTheme.confirmedGreen
    case .networkDegraded, .tunnelEstimated, .routeInterrupted:
      return KaidoTheme.signalAmber
    default:
      return KaidoTheme.positionCyan
    }
  }

  private var drivingDistanceLabel: String {
    guard let route = model.selectedRoute else { return "—" }
    switch model.phase {
    case .surfaceAccess:
      return distanceLabel(
        (model.accessRoute?.distanceMeters ?? 0)
          * (1 - model.progressFraction)
      )
    case .entryTransition:
      return "进入 \(route.routeIDsInOrder.first.map(shieldLabel) ?? "")"
    case .expressway:
      return distanceLabel(
        route.distanceMeters * (1 - model.progressFraction)
      )
    case .exitTransition:
      return "\(route.exitFacility.nameJA)出口"
    case .surfaceEgress:
      return distanceLabel(
        (model.egressRoute?.distanceMeters ?? 0)
          * (1 - model.progressFraction)
      )
    case .completed:
      return "到达"
    case .planning, .review:
      return ""
    }
  }

  private var drivingBoundaryLabel: String {
    guard let route = model.selectedRoute else { return "" }
    return "\(route.entryFacility.nameJA)入口 → \(route.exitFacility.nameJA)出口"
  }

  private func distanceLabel(_ meters: Double) -> String {
    if meters >= 1_000 {
      return String(format: "%.1f km", meters / 1_000)
    }
    return "\(Int(max(0, meters).rounded())) m"
  }

  private func failureMessage(_ code: String) -> String {
    switch code {
    case "DESTINATION_REQUIRED":
      return "请输入目的地"
    case "LOCATION_UNAVAILABLE":
      return "无法读取当前位置，也可输入出发地"
    case "NO_SHUTO_ROUTE":
      return "未找到方向合法的首都高路线"
    default:
      return "地点或路线暂时无法解析"
    }
  }
}

private struct WholeShutoCircleButtonStyle: ButtonStyle {
  let isDriving: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(
        isDriving ? KaidoTheme.routeWhite : KaidoTheme.ink
      )
      .background(
        isDriving
          ? KaidoTheme.instrument.opacity(0.94)
          : KaidoTheme.paperRaised.opacity(0.96)
      )
      .clipShape(Circle())
      .overlay {
        Circle()
          .stroke(
            isDriving ? KaidoTheme.steel : KaidoTheme.paperDivider,
            lineWidth: 1
          )
      }
      .scaleEffect(configuration.isPressed ? 0.94 : 1)
  }
}

private struct WholeShutoNetworkDiagram: View {
  let database: ShutoNetworkDatabase
  let selectedRoute: ShutoPlannedRoute?
  let currentCoordinate: ShutoCoordinate?
  let usesDarkStyle: Bool
  let visibleBottomFraction: Double

  private var nodesByID: [Int64: ShutoCoordinate] {
    Dictionary(
      uniqueKeysWithValues: database.nodes.map {
        ($0.nodeID, $0.coordinate)
      }
    )
  }

  var body: some View {
    Canvas { context, size in
      let transform = DiagramTransform(
        size: size,
        visibleBottomFraction: visibleBottomFraction
      )
      context.fill(
        Path(CGRect(origin: .zero, size: size)),
        with: .color(
          usesDarkStyle ? KaidoTheme.asphalt : KaidoTheme.paper
        )
      )

      drawWater(context: &context, size: size)

      let nodeCoordinates = nodesByID
      for way in database.ways where way.kind == "MAINLINE" {
        let points = way.nodeIDs.compactMap {
          nodeCoordinates[$0].map(transform.point)
        }
        guard points.count > 1 else { continue }
        var path = Path()
        path.move(to: points[0])
        for point in points.dropFirst() {
          path.addLine(to: point)
        }
        let routeID = way.routeMemberships.first?.routeID ?? ""
        context.stroke(
          path,
          with: .color(
            routeColor(routeID).opacity(usesDarkStyle ? 0.50 : 0.62)
          ),
          style: StrokeStyle(
            lineWidth: usesDarkStyle ? 2.5 : 2.2,
            lineCap: .round,
            lineJoin: .round
          )
        )
      }

      if let selectedRoute {
        let points = selectedRoute.coordinates.map(transform.point)
        if points.count > 1 {
          var path = Path()
          path.move(to: points[0])
          for point in points.dropFirst() {
            path.addLine(to: point)
          }
          context.stroke(
            path,
            with: .color(
              usesDarkStyle
                ? KaidoTheme.routeWhite.opacity(0.86)
                : Color.white.opacity(0.95)
            ),
            style: StrokeStyle(
              lineWidth: 10,
              lineCap: .round,
              lineJoin: .round
            )
          )
          context.stroke(
            path,
            with: .color(KaidoTheme.signalAmber),
            style: StrokeStyle(
              lineWidth: 6,
              lineCap: .round,
              lineJoin: .round
            )
          )
        }
        marker(
          context: &context,
          at: transform.point(selectedRoute.entryFacility.coordinate),
          color: KaidoTheme.positionCyan,
          label: "入"
        )
        marker(
          context: &context,
          at: transform.point(selectedRoute.exitFacility.coordinate),
          color: KaidoTheme.evidenceCoral,
          label: "出"
        )
      }

      for junction in database.junctions.prefix(39) {
        guard let coordinate = junction.coordinate else { continue }
        let point = transform.point(coordinate)
        context.fill(
          Path(
            ellipseIn: CGRect(
              x: point.x - 2.2,
              y: point.y - 2.2,
              width: 4.4,
              height: 4.4
            )
          ),
          with: .color(
            usesDarkStyle
              ? KaidoTheme.routeWhite.opacity(0.8)
              : KaidoTheme.ink.opacity(0.65)
          )
        )
      }

      for facility in database.directionalFacilities
      where facility.operationalStatus == "AVAILABLE" {
        let point = transform.point(facility.coordinate)
        context.fill(
          Path(
            ellipseIn: CGRect(
              x: point.x - 1.6,
              y: point.y - 1.6,
              width: 3.2,
              height: 3.2
            )
          ),
          with: .color(
            usesDarkStyle
              ? KaidoTheme.muted.opacity(0.72)
              : KaidoTheme.quietText.opacity(0.52)
          )
        )
      }

      for parkingArea in database.parkingAreas {
        let point = transform.point(parkingArea.coordinate)
        let frame = CGRect(
          x: point.x - 4.5,
          y: point.y - 4.5,
          width: 9,
          height: 9
        )
        context.fill(
          Path(roundedRect: frame, cornerRadius: 2),
          with: .color(KaidoTheme.signalAmber)
        )
        context.draw(
          context.resolve(
            Text("P")
              .font(.system(size: 5, weight: .black))
              .foregroundStyle(KaidoTheme.asphalt)
          ),
          at: point
        )
      }

      if let currentCoordinate {
        let point = transform.point(currentCoordinate)
        context.fill(
          Path(
            ellipseIn: CGRect(
              x: point.x - 7,
              y: point.y - 7,
              width: 14,
              height: 14
            )
          ),
          with: .color(Color.white)
        )
        context.fill(
          Path(
            ellipseIn: CGRect(
              x: point.x - 4.5,
              y: point.y - 4.5,
              width: 9,
              height: 9
            )
          ),
          with: .color(KaidoTheme.positionCyan)
        )
      }

      drawRouteShields(
        context: &context,
        transform: transform,
        nodeCoordinates: nodeCoordinates
      )
    }
    .overlay(alignment: .bottomTrailing) {
      VStack(alignment: .trailing, spacing: 2) {
        Text("SHUTO NETWORK")
          .font(.system(size: 8, weight: .black, design: .monospaced))
          .tracking(0.8)
        Text("线路关系图 · 非道路比例")
          .font(.system(size: 7, weight: .bold))
      }
      .foregroundStyle(
        usesDarkStyle ? KaidoTheme.muted : KaidoTheme.quietText
      )
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(.ultraThinMaterial)
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .padding(12)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityIdentifier("whole-shuto-network-map")
    .accessibilityLabel("首都高全网线路图")
    .accessibilityValue(
      selectedRoute == nil
        ? "26条路线"
        : selectedRoute!.routeIDsInOrder
          .map(shieldLabel)
          .joined(separator: "到")
    )
  }

  private func drawWater(
    context: inout GraphicsContext,
    size: CGSize
  ) {
    var bay = Path()
    bay.move(to: CGPoint(x: size.width * 0.58, y: size.height * 0.54))
    bay.addCurve(
      to: CGPoint(x: size.width, y: size.height * 0.44),
      control1: CGPoint(x: size.width * 0.76, y: size.height * 0.47),
      control2: CGPoint(x: size.width * 0.88, y: size.height * 0.46)
    )
    bay.addLine(to: CGPoint(x: size.width, y: size.height))
    bay.addLine(to: CGPoint(x: size.width * 0.44, y: size.height))
    bay.addCurve(
      to: CGPoint(x: size.width * 0.58, y: size.height * 0.54),
      control1: CGPoint(x: size.width * 0.50, y: size.height * 0.77),
      control2: CGPoint(x: size.width * 0.54, y: size.height * 0.64)
    )
    context.fill(
      bay,
      with: .color(
        usesDarkStyle
          ? Color(hex: 0x112C36)
          : KaidoTheme.surfaceWater
      )
    )
  }

  private func drawRouteShields(
    context: inout GraphicsContext,
    transform: DiagramTransform,
    nodeCoordinates: [Int64: ShutoCoordinate]
  ) {
    let featured = ["C1", "C2", "B", "1_HANEDA", "3", "4", "5", "6_MUKOJIMA", "7", "K1", "K7_YOKOHAMA_KITA", "S1"]
    for routeID in featured {
      let coordinates = database.ways
        .filter {
          $0.kind == "MAINLINE"
            && $0.routeMemberships.contains { $0.routeID == routeID }
        }
        .flatMap(\.nodeIDs)
        .compactMap { nodeCoordinates[$0] }
      guard !coordinates.isEmpty else { continue }
      let coordinate = coordinates[coordinates.count / 2]
      let point = transform.point(coordinate)
      let label = shieldLabel(routeID)
      let resolved = context.resolve(
        Text(label)
          .font(.system(size: 7, weight: .black, design: .rounded))
          .foregroundStyle(Color.white)
      )
      let frame = CGRect(
        x: point.x - 11,
        y: point.y - 8,
        width: 22,
        height: 16
      )
      context.fill(
        Path(roundedRect: frame, cornerRadius: 4),
        with: .color(routeColor(routeID))
      )
      context.draw(resolved, at: point)
    }
  }

  private func marker(
    context: inout GraphicsContext,
    at point: CGPoint,
    color: Color,
    label: String
  ) {
    let frame = CGRect(
      x: point.x - 10,
      y: point.y - 10,
      width: 20,
      height: 20
    )
    context.fill(
      Path(ellipseIn: frame),
      with: .color(Color.white)
    )
    context.fill(
      Path(ellipseIn: frame.insetBy(dx: 2.5, dy: 2.5)),
      with: .color(color)
    )
    context.draw(
      context.resolve(
        Text(label)
          .font(.system(size: 7, weight: .black))
          .foregroundStyle(Color.white)
      ),
      at: point
    )
  }
}

private struct DiagramTransform {
  let size: CGSize
  let visibleBottomFraction: Double

  func point(_ coordinate: ShutoCoordinate) -> CGPoint {
    let minimumLongitude = 139.29
    let maximumLongitude = 140.14
    let minimumLatitude = 35.34
    let maximumLatitude = 35.94
    let x =
      (coordinate.longitude - minimumLongitude)
      / (maximumLongitude - minimumLongitude)
    let y =
      (maximumLatitude - coordinate.latitude)
      / (maximumLatitude - minimumLatitude)
    return CGPoint(
      x: 16 + min(1, max(0, x)) * (size.width - 32),
      y:
        62
        + min(1, max(0, y))
        * max(100, size.height * visibleBottomFraction - 108)
    )
  }
}

private struct WholeShutoGeographicMap: View {
  @ObservedObject var model: WholeShutoProductModel
  @State private var camera = MapCameraPosition.automatic

  var body: some View {
    Map(position: $camera) {
      if let accessRoute = model.accessRoute,
        model.phase == .review || model.phase == .surfaceAccess
      {
        MapPolyline(
          coordinates: accessRoute.coordinates.map(\.mapCoordinate)
        )
        .stroke(
          KaidoTheme.positionCyan,
          style: StrokeStyle(
            lineWidth: 5,
            lineCap: .round,
            lineJoin: .round,
            dash: [7, 5]
          )
        )
      }

      if let route = model.selectedRoute {
        MapPolyline(
          coordinates: route.coordinates.map(\.mapCoordinate)
        )
        .stroke(
          Color.white.opacity(0.88),
          style: StrokeStyle(
            lineWidth: 10,
            lineCap: .round,
            lineJoin: .round
          )
        )
        MapPolyline(
          coordinates: route.coordinates.map(\.mapCoordinate)
        )
        .stroke(
          KaidoTheme.routeGreen,
          style: StrokeStyle(
            lineWidth: 7,
            lineCap: .round,
            lineJoin: .round
          )
        )

        Annotation(
          "\(route.entryFacility.nameJA)入口",
          coordinate: route.entryFacility.coordinate.mapCoordinate
        ) {
          WholeShutoMapMarker(
            text: "入",
            color: KaidoTheme.positionCyan
          )
        }
        Annotation(
          "\(route.exitFacility.nameJA)出口",
          coordinate: route.exitFacility.coordinate.mapCoordinate
        ) {
          WholeShutoMapMarker(
            text: "出",
            color: KaidoTheme.evidenceCoral
          )
        }
      }

      ForEach(visibleFacilities) { facility in
        Annotation(
          facility.nameJA,
          coordinate: facility.coordinate.mapCoordinate
        ) {
          WholeShutoFacilityLabel(
            prefix: "IC",
            name: facility.nameJA,
            color: KaidoTheme.routeGreenDeep
          )
        }
      }

      ForEach(visibleParkingAreas) { parkingArea in
        Annotation(
          parkingArea.nameJA,
          coordinate: parkingArea.coordinate.mapCoordinate
        ) {
          WholeShutoFacilityLabel(
            prefix: "P",
            name: parkingArea.baseNameJA,
            color: KaidoTheme.signalAmber,
            darkText: true
          )
        }
      }

      if let egressRoute = model.egressRoute,
        model.phase == .review || model.phase == .surfaceEgress
          || model.phase == .completed
      {
        MapPolyline(
          coordinates: egressRoute.coordinates.map(\.mapCoordinate)
        )
        .stroke(
          KaidoTheme.evidenceCoral,
          style: StrokeStyle(
            lineWidth: 5,
            lineCap: .round,
            lineJoin: .round,
            dash: [7, 5]
          )
        )
      }

      ForEach(visibleJunctionPrompts) { prompt in
        Annotation(
          prompt.nameJA,
          coordinate: prompt.coordinate.mapCoordinate
        ) {
          WholeShutoFacilityLabel(
            prefix: "JCT",
            name: prompt.nameJA,
            color: KaidoTheme.ink
          )
        }
      }

      if let current = model.currentCoordinate {
        Annotation("当前位置", coordinate: current.mapCoordinate) {
          ZStack {
            Circle()
              .fill(Color.white)
              .frame(width: 27, height: 27)
              .shadow(radius: 4)
            Image(systemName: "location.north.fill")
              .font(.system(size: 13, weight: .black))
              .foregroundStyle(KaidoTheme.positionCyan)
          }
        }
      }
    }
    .mapStyle(
      model.phase == .planning || model.phase == .review
        ? .standard(elevation: .flat)
        : .standard(elevation: .realistic, pointsOfInterest: .excludingAll)
    )
    .mapControls {
      MapCompass()
    }
    .onAppear {
      updateCamera()
    }
    .onChange(of: model.phase) {
      updateCamera()
    }
    .onChange(of: model.currentCoordinate?.latitude) {
      updateCamera()
    }
    .accessibilityIdentifier("whole-shuto-geographic-map")
  }

  private var visibleRouteIDs: Set<String> {
    Set(model.selectedRoute?.routeIDsInOrder ?? [])
  }

  private var visibleFacilities: [ShutoNetworkDatabase.Facility] {
    let facilities = model.database.directionalFacilities.filter {
      $0.operationalStatus == "AVAILABLE"
        && (visibleRouteIDs.isEmpty || visibleRouteIDs.contains($0.routeID))
    }
    guard isDriving, let current = model.currentCoordinate else {
      return Array(facilities.prefix(45))
    }
    return facilities
      .map { ($0, geographicDistance($0.coordinate, current)) }
      .filter { $0.1 <= 3_000 }
      .sorted { $0.1 < $1.1 }
      .prefix(3)
      .map(\.0)
  }

  private var visibleJunctionPrompts: [WholeShutoJunctionPrompt] {
    guard isDriving else {
      return model.junctionPrompts
    }
    let activeID = model.activeJunctionPrompt?.id
    return model.junctionPrompts
      .filter {
        $0.id != activeID
          && $0.progressFraction > model.progressFraction + 0.006
      }
      .prefix(2)
      .map { $0 }
  }

  private var visibleParkingAreas: [ShutoNetworkDatabase.ParkingArea] {
    let parkingAreas = model.database.parkingAreas.filter {
      visibleRouteIDs.isEmpty
        || $0.routeID.map(visibleRouteIDs.contains) == true
    }
    guard isDriving, let current = model.currentCoordinate else {
      return parkingAreas
    }
    return parkingAreas.filter {
      geographicDistance($0.coordinate, current) <= 7_000
    }
  }

  private var isDriving: Bool {
    ![WholeShutoJourneyPhase.planning, .review].contains(model.phase)
  }

  private func updateCamera() {
    guard isDriving, let current = model.currentCoordinate else {
      camera = .automatic
      return
    }
    withAnimation(.easeOut(duration: 0.35)) {
      camera = .region(
        MKCoordinateRegion(
          center: current.mapCoordinate,
          latitudinalMeters: 13_000,
          longitudinalMeters: 13_000
        )
      )
    }
  }

  private func geographicDistance(
    _ first: ShutoCoordinate,
    _ second: ShutoCoordinate
  ) -> Double {
    CLLocation(
      latitude: first.latitude,
      longitude: first.longitude
    ).distance(
      from: CLLocation(
        latitude: second.latitude,
        longitude: second.longitude
      )
    )
  }
}

private struct WholeShutoMapMarker: View {
  let text: String
  let color: Color

  var body: some View {
    Text(text)
      .font(.system(size: 8, weight: .black))
      .foregroundStyle(Color.white)
      .frame(width: 25, height: 25)
      .background(color)
      .clipShape(Circle())
      .overlay {
        Circle().stroke(Color.white, lineWidth: 2)
      }
      .shadow(radius: 3)
  }
}

private struct WholeShutoFacilityLabel: View {
  let prefix: String
  let name: String
  let color: Color
  var darkText = false

  var body: some View {
    HStack(spacing: 3) {
      Text(prefix)
        .font(.system(size: 7, weight: .black, design: .rounded))
      Text(name)
        .font(.system(size: 8, weight: .black, design: .rounded))
        .lineLimit(1)
    }
    .foregroundStyle(darkText ? KaidoTheme.asphalt : Color.white)
    .padding(.horizontal, 6)
    .frame(height: 20)
    .background(color)
    .clipShape(Capsule())
    .overlay {
      Capsule().stroke(Color.white.opacity(0.9), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.24), radius: 3, y: 1)
  }
}

private struct WholeShutoJunctionInset: View {
  let prompt: WholeShutoJunctionPrompt

  var body: some View {
    HStack(spacing: 12) {
      junctionGraphic
        .frame(width: 112, height: 92)

      VStack(alignment: .leading, spacing: 4) {
        Text("接近分岔 · \(prompt.nameJA)")
          .font(.system(size: 9, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.confirmedGreen)
        Text(
          "\(branchLabel) · 驶向 "
            + "\(shieldLabel(prompt.outgoingRouteID)) "
            + "\(prompt.outgoingDirectionJA)"
        )
          .font(.system(size: 19, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)
        HStack(spacing: 6) {
          Text(shieldLabel(prompt.incomingRouteID))
            .junctionShield(color: routeColor(prompt.incomingRouteID))
          Image(systemName: "arrow.right")
            .font(.system(size: 9, weight: .black))
          Text(shieldLabel(prompt.outgoingRouteID))
            .junctionShield(color: routeColor(prompt.outgoingRouteID))
        }
        Text(verbatim: prompt.japaneseSignText)
          .font(.system(size: 10, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)
        Text(
          prompt.routeShields.map(shieldLabel)
            .joined(separator: " · ")
        )
        .font(.system(size: 8, weight: .bold, design: .monospaced))
        .foregroundStyle(KaidoTheme.muted)
        Text("\(laneGuidanceLabel) · \(prompt.checkedAt)")
          .font(.system(size: 8, weight: .bold))
          .foregroundStyle(KaidoTheme.muted)
      }
      Spacer(minLength: 0)
    }
    .padding(10)
    .background(KaidoTheme.asphalt.opacity(0.97))
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .stroke(KaidoTheme.signalAmber.opacity(0.72), lineWidth: 1.5)
    }
    .shadow(color: .black.opacity(0.36), radius: 12, y: 5)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "\(prompt.nameJA)，从\(shieldLabel(prompt.incomingRouteID))"
        + "\(branchLabel)，驶向\(shieldLabel(prompt.outgoingRouteID))"
        + "\(prompt.outgoingDirectionJA)，"
        + "日文路牌\(prompt.japaneseSignText)，\(laneGuidanceLabel)"
    )
    .accessibilityIdentifier("whole-shuto-junction-inset")
  }

  private var branchLabel: String {
    switch prompt.branchSide {
    case .left:
      "左分岔"
    case .right:
      "右分岔"
    case .straight:
      "直行"
    }
  }

  private var laneGuidanceLabel: String {
    switch prompt.laneGuidanceState {
    case .notReleased:
      "车道编号尚未发布"
    }
  }

  private var junctionGraphic: some View {
    Canvas { context, size in
      let bottom = CGPoint(x: size.width / 2, y: size.height)
      let split = CGPoint(x: size.width / 2, y: size.height * 0.56)
      let left = CGPoint(x: size.width * 0.22, y: 12)
      let straight = CGPoint(x: size.width / 2, y: 10)
      let right = CGPoint(x: size.width * 0.78, y: 12)

      var approach = Path()
      approach.move(to: bottom)
      approach.addLine(to: split)
      context.stroke(
        approach,
        with: .color(KaidoTheme.signalAmber),
        style: StrokeStyle(lineWidth: 8, lineCap: .round)
      )

      func branchPath(to endpoint: CGPoint) -> Path {
        var path = Path()
        path.move(to: split)
        path.addCurve(
          to: endpoint,
          control1: CGPoint(
            x: split.x + (endpoint.x - split.x) * 0.18,
            y: size.height * 0.37
          ),
          control2: CGPoint(
            x: split.x + (endpoint.x - split.x) * 0.78,
            y: size.height * 0.25
          )
        )
        return path
      }

      let selectedEnd: CGPoint
      let alternativeEnds: [CGPoint]
      switch prompt.branchSide {
      case .left:
        selectedEnd = left
        alternativeEnds = [straight]
      case .right:
        selectedEnd = right
        alternativeEnds = [straight]
      case .straight:
        selectedEnd = straight
        alternativeEnds = [left, right]
      }
      for endpoint in alternativeEnds {
        context.stroke(
          branchPath(to: endpoint),
          with: .color(KaidoTheme.steel),
          style: StrokeStyle(lineWidth: 7, lineCap: .round)
        )
      }
      context.stroke(
        branchPath(to: selectedEnd),
        with: .color(KaidoTheme.signalAmber),
        style: StrokeStyle(lineWidth: 8, lineCap: .round)
      )

      let routeCue = context.resolve(
        Text(shieldLabel(prompt.outgoingRouteID))
          .font(.system(size: 13, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)
      )
      let cueFrame = CGRect(
        x: selectedEnd.x - 18,
        y: selectedEnd.y - 10,
        width: 36,
        height: 25
      )
      context.fill(
        Path(roundedRect: cueFrame, cornerRadius: 6),
        with: .color(routeColor(prompt.outgoingRouteID))
      )
      context.draw(
        routeCue,
        at: CGPoint(x: selectedEnd.x, y: selectedEnd.y + 2.5)
      )
    }
    .background(KaidoTheme.instrument)
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }
}

private struct WholeShutoNetworkFactsView: View {
  @ObservedObject var model: WholeShutoProductModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section("全网范围") {
          fact("路线", "\(model.database.routes.count)")
          fact("IC 名称", "\(model.database.directionalFacilities.count)")
          fact("JCT", "\(model.database.junctions.count)")
          fact(
            "JCT 官方详图索引",
            "\(officialJunctionReferenceCount)"
              + " / \(model.database.junctions.count)"
          )
          fact("PA", "\(model.database.parkingAreas.count)")
          fact("数据日期", model.database.checkedAt)
        }

        Section("准确性边界") {
          Label(
            "路线、IC 方向、JCT 与 PA 名单来自首都高当前官方页面。",
            systemImage: "checkmark.seal"
          )
          Label(
            "道路几何和连通为固定版本 OSM 候选，不代表官方车道级授权。",
            systemImage: "point.3.connected.trianglepath.dotted"
          )
          Label(
            "实时通行、临时封闭、收费与 PA 开放状态尚未确认。",
            systemImage: "exclamationmark.triangle"
          )
        }
      }
      .navigationTitle("首都高全网")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("完成") { dismiss() }
        }
      }
    }
  }

  private func fact(_ label: String, _ value: String) -> some View {
    HStack {
      Text(label)
      Spacer()
      Text(value)
        .foregroundStyle(.secondary)
    }
  }

  private var officialJunctionReferenceCount: Int {
    model.database.junctions.filter {
      $0.officialDetailSHA256.count == 64
    }.count
  }
}

private extension Text {
  func junctionShield(color: Color) -> some View {
    font(.system(size: 9, weight: .black, design: .rounded))
      .foregroundStyle(Color.white)
      .padding(.horizontal, 7)
      .frame(height: 22)
      .background(color)
      .clipShape(RoundedRectangle(cornerRadius: 5))
  }
}

private extension ShutoCoordinate {
  var mapCoordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }
}

private func shieldLabel(_ routeID: String) -> String {
  routeID
    .replacingOccurrences(of: "_HANEDA", with: "")
    .replacingOccurrences(of: "_UENO", with: "")
    .replacingOccurrences(of: "_MUKOJIMA", with: "")
    .replacingOccurrences(of: "_MISATO", with: "")
    .replacingOccurrences(of: "_YOKOHAMA_KITA", with: "")
    .replacingOccurrences(of: "_YOKOHAMA_HOKUSEI", with: "")
}

private func routeColor(_ routeID: String) -> Color {
  switch routeID {
  case "C1", "1_HANEDA", "1_UENO", "5", "S1", "S2", "S5":
    return Color(hex: 0x2877B7)
  case "C2", "6_MUKOJIMA", "6_MISATO", "K6":
    return Color(hex: 0x2F8E63)
  case "B", "9", "11", "K5":
    return Color(hex: 0x8065A7)
  case "3", "K1", "K2", "K3":
    return Color(hex: 0x34658D)
  case "4", "K7_YOKOHAMA_KITA", "K7_YOKOHAMA_HOKUSEI":
    return Color(hex: 0xC84E45)
  case "7", "10":
    return Color(hex: 0xC9822E)
  case "2":
    return Color(hex: 0x7C5E99)
  default:
    return KaidoTheme.routeGreen
  }
}
