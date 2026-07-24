import SwiftUI

struct KaidoProductJourneyView: View {
  @StateObject private var model: KaidoProductJourneyModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(model: KaidoProductJourneyModel = KaidoProductJourneyModel()) {
    _model = StateObject(wrappedValue: model)
  }

  var body: some View {
    ZStack {
      KaidoTheme.asphalt
        .ignoresSafeArea()

      ScrollView {
        VStack(spacing: 16) {
          journeyHeader
          routeProgress
          stageContent
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 20)
      }
      .scrollIndicators(.hidden)
      .accessibilityIdentifier("product-journey-scroll")
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      actionDock
    }
    .preferredColorScheme(.dark)
  }

  private var journeyHeader: some View {
    HStack(alignment: .top, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("KAIDO ROUTES")
          .font(.system(size: 24, weight: .black, design: .rounded))
          .tracking(-0.8)
          .foregroundStyle(KaidoTheme.routeWhite)

        Text("先选路，再出发。")
          .font(.system(size: 17, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.signalAmber)

        Text("首都高速 · ROUTE-FIRST NAVIGATION")
          .font(.system(size: 9, weight: .bold, design: .monospaced))
          .tracking(0.9)
          .foregroundStyle(KaidoTheme.muted)
      }

      Spacer(minLength: 8)

      VStack(alignment: .trailing, spacing: 6) {
        StatusCapsule(
          title: "REVIEW BUILD",
          color: KaidoTheme.evidenceCoral
        )

        Text(stageCounter)
          .font(.system(size: 10, weight: .black, design: .monospaced))
          .foregroundStyle(KaidoTheme.muted)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "Kaido Routes。先选路，再出发。当前步骤\(stageTitle(model.stage))。"
    )
  }

  private var routeProgress: some View {
    HStack(spacing: 0) {
      ForEach(
        Array(KaidoProductJourneyStage.allCases.enumerated()),
        id: \.element.rawValue
      ) { index, stage in
        JourneyStageButton(
          stage: stage,
          title: stageShortTitle(stage),
          symbol: stageSymbol(stage),
          state: stageVisualState(stage)
        ) {
          changeStage(to: stage)
        }

        if index < KaidoProductJourneyStage.allCases.count - 1 {
          Rectangle()
            .fill(progressLineColor(after: stage))
            .frame(height: 2)
            .overlay {
              if progressLineIsLocked(after: stage) {
                HStack(spacing: 4) {
                  ForEach(0..<3, id: \.self) { _ in
                    Circle()
                      .fill(KaidoTheme.steel)
                      .frame(width: 3, height: 3)
                  }
                }
              }
            }
            .accessibilityHidden(true)
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 13)
    .background(KaidoTheme.instrument)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .overlay {
      RoundedRectangle(cornerRadius: 16)
        .stroke(KaidoTheme.steel.opacity(0.8), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("product-journey-stage")
    .accessibilityValue(model.stage.rawValue)
  }

  @ViewBuilder
  private var stageContent: some View {
    switch model.stage {
    case .atlas:
      atlasStage
        .transition(stageTransition)
    case .authoring:
      authoringStage
        .transition(stageTransition)
    case .review:
      reviewStage
        .transition(stageTransition)
    case .navigation:
      navigationUnavailable
        .transition(stageTransition)
    }
  }

  private var atlasStage: some View {
    VStack(spacing: 14) {
      stageIntroduction(
        eyebrow: "01 · CHOOSE THE ROAD",
        title: "先认识道路，再设计路线",
        detail: "全网图只帮助识别；只有经过发布门的有向拓扑才能参与路线。"
      )

      atlasModePicker

      RouteAtlasCard(
        mode: model.composition.atlasMode,
        attribution: model.composition.attribution(
          for: model.composition.atlasMode
        )
      )

      ReviewBoundaryCard(
        symbol: "shield.lefthalf.filled",
        title: "当前使用合成路线目录",
        detail:
          "清单哈希与生产 codec 已验证；没有真实道路发布包，不会获得导航权限。",
        code:
          "\(model.composition.productReleaseCatalog.foregroundNavigationEntries.count)"
          + " RELEASED ROAD · "
          + "\(model.composition.productReleaseCatalog.demoEntries.count) DEMO",
        color: KaidoTheme.evidenceCoral
      )
      .accessibilityIdentifier("product-journey-release-catalog")
      .accessibilityValue(
        "\(model.composition.productReleaseCatalog.foregroundNavigationEntries.count)"
          + " RELEASED ROAD · "
          + "\(model.composition.productReleaseCatalog.demoEntries.count) DEMO"
      )
    }
  }

  private var authoringStage: some View {
    VStack(spacing: 14) {
      stageIntroduction(
        eyebrow: "02 · AUTHOR THE ROUTE",
        title: "路线按选择顺序保留",
        detail: "每次分岔、重复路段和明确出口都由 editor session 记录。"
      )

      EntranceRecommendationPanel(
        model: model.composition.entranceRecommendation
      )

      ParkedRouteEditorPanel(model: model.composition.routeEditor)

      if model.routeReviewReady {
        ReviewBoundaryCard(
          symbol: "checkmark.seal.fill",
          title: "路线已可进入行前确认",
          detail: "编译结果保留全部 occurrence；下一步只读取这条路线。",
          code: "ROUTE PLAN READY",
          color: KaidoTheme.positionCyan
        )
        .accessibilityIdentifier("product-journey-route-ready")
      }
    }
  }

  private var reviewStage: some View {
    VStack(spacing: 14) {
      stageIntroduction(
        eyebrow: "03 · REVIEW BEFORE DRIVING",
        title: "确认路线、费用证据与通行状态",
        detail: "实际规划距离与计费距离分开；未确认实时状态不会显示为畅通。"
      )

      PreDriveReviewPanel(model: model.composition.preDriveReview)

      GuidanceVoiceSetupPanel(
        model: model.composition.guidanceVoiceSetup,
        isParked: model.composition.safety.isParkedInteractionContext
      )

      ReviewBoundaryCard(
        symbol: "lock.shield.fill",
        title: "真实导航仍被发布门阻止",
        detail:
          "这条演示路线没有 RELEASED_ROAD 权限、前台实时输入令牌和现场资格证据。",
        code: model.navigationBlocker?.rawValue ?? "NAVIGATION BLOCKED",
        color: KaidoTheme.evidenceCoral
      )
      .accessibilityIdentifier("product-journey-navigation-blocker")
      .accessibilityValue(
        model.navigationBlocker?.rawValue ?? "NAVIGATION BLOCKED"
      )
    }
  }

  private var navigationUnavailable: some View {
    ReviewBoundaryCard(
      symbol: "exclamationmark.shield.fill",
      title: "导航运行时不可用",
      detail: "没有真实联合发布包时，App 不会用合成 actor trace 代替用户导航。",
      code: KaidoProductJourneyBlocker.navigationRuntimeUnavailable.rawValue,
      color: KaidoTheme.evidenceCoral
    )
  }

  private var atlasModePicker: some View {
    HStack(spacing: 4) {
      ForEach(RouteAtlasMode.allCases) { mode in
        Button {
          withAnimation(stageAnimation) {
            model.composition.atlasMode = mode
          }
        } label: {
          VStack(spacing: 3) {
            Text(mode.label)
              .font(.system(size: 12, weight: .black, design: .rounded))

            Text(mode == .network ? "RECOGNITION" : "EVIDENCE")
              .font(.system(size: 7, weight: .black, design: .monospaced))
              .tracking(0.5)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 9)
          .foregroundStyle(
            model.composition.atlasMode == mode
              ? KaidoTheme.asphalt
              : KaidoTheme.muted
          )
          .background(
            model.composition.atlasMode == mode
              ? KaidoTheme.routeWhite
              : Color.clear
          )
          .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(
          model.composition.atlasMode == mode ? .isSelected : []
        )
        .accessibilityIdentifier("product-journey-atlas-\(mode.rawValue)")
      }
    }
    .padding(4)
    .background(KaidoTheme.instrument)
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }

  private var actionDock: some View {
    VStack(spacing: 8) {
      if let guidance = actionGuidance {
        Text(guidance)
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(
            model.stage == .review
              ? KaidoTheme.evidenceCoral
              : KaidoTheme.muted
          )
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityIdentifier("product-journey-action-guidance")
      }

      HStack(spacing: 10) {
        if model.stage != .atlas {
          Button {
            changeStageBack()
          } label: {
            Image(systemName: "chevron.left")
              .font(.system(size: 14, weight: .black))
              .frame(width: 44, height: 48)
              .foregroundStyle(KaidoTheme.routeWhite)
              .background(KaidoTheme.steel.opacity(0.72))
              .clipShape(RoundedRectangle(cornerRadius: 13))
          }
          .buttonStyle(.plain)
          .accessibilityLabel("返回\(previousStageTitle)")
          .accessibilityIdentifier("product-journey-back")
        }

        Button {
          advance()
        } label: {
          HStack(spacing: 9) {
            Image(systemName: primaryActionSymbol)
            Text(primaryActionTitle)
            Spacer(minLength: 4)
            Text(nextStageCode)
              .font(.system(size: 8, weight: .black, design: .monospaced))
              .tracking(0.4)
          }
          .font(.system(size: 14, weight: .black, design: .rounded))
          .padding(.horizontal, 15)
          .frame(maxWidth: .infinity)
          .frame(height: 48)
          .foregroundStyle(
            model.canAdvance
              ? KaidoTheme.asphalt
              : KaidoTheme.muted
          )
          .background(
            model.canAdvance
              ? KaidoTheme.signalAmber
              : KaidoTheme.steel.opacity(0.38)
          )
          .clipShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .disabled(!model.canAdvance)
        .accessibilityIdentifier("product-journey-primary-action")
        .accessibilityValue(model.canAdvance ? "AVAILABLE" : "BLOCKED")
      }
    }
    .padding(.horizontal, 18)
    .padding(.top, 10)
    .padding(.bottom, 8)
    .background(.ultraThinMaterial)
    .overlay(alignment: .top) {
      Rectangle()
        .fill(KaidoTheme.steel.opacity(0.85))
        .frame(height: 1)
    }
  }

  private func stageIntroduction(
    eyebrow: String,
    title: String,
    detail: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(eyebrow)
        .font(.system(size: 9, weight: .black, design: .monospaced))
        .tracking(0.85)
        .foregroundStyle(KaidoTheme.signalAmber)

      Text(title)
        .font(.system(size: 21, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.routeWhite)

      Text(detail)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(KaidoTheme.muted)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var stageCounter: String {
    String(format: "%02d / 04", model.stage.order + 1)
  }

  private var primaryActionTitle: String {
    switch model.stage {
    case .atlas:
      "开始设计路线"
    case .authoring:
      "进入行前确认"
    case .review:
      "导航尚未发布"
    case .navigation:
      "导航运行中"
    }
  }

  private var primaryActionSymbol: String {
    switch model.stage {
    case .atlas:
      "point.topleft.down.to.point.bottomright.curvepath"
    case .authoring:
      "checklist.checked"
    case .review:
      "lock.fill"
    case .navigation:
      "location.fill"
    }
  }

  private var nextStageCode: String {
    switch model.stage {
    case .atlas:
      "EDIT"
    case .authoring:
      "REVIEW"
    case .review:
      "BLOCKED"
    case .navigation:
      "ACTIVE"
    }
  }

  private var actionGuidance: String? {
    switch model.stage {
    case .atlas:
      "路线图用于识别；下一步进入停车编辑。"
    case .authoring where !model.routeReviewReady:
      "先选择明确出口，再编译路线。"
    case .authoring:
      "路线已编译，可以核对距离、费用与通行证据。"
    case .review:
      "需要真实联合发布包和现场资格证据后才能开始导航。"
    case .navigation:
      nil
    }
  }

  private var previousStageTitle: String {
    switch model.stage {
    case .atlas, .authoring:
      "路线图"
    case .review:
      "路线编辑"
    case .navigation:
      "行前确认"
    }
  }

  private var stageAnimation: Animation? {
    reduceMotion ? nil : .easeInOut(duration: 0.22)
  }

  private var stageTransition: AnyTransition {
    reduceMotion
      ? .identity
      : .asymmetric(
        insertion: .opacity.combined(with: .offset(x: 18)),
        removal: .opacity.combined(with: .offset(x: -12))
      )
  }

  private func changeStage(to stage: KaidoProductJourneyStage) {
    withAnimation(stageAnimation) {
      model.go(to: stage)
    }
  }

  private func changeStageBack() {
    withAnimation(stageAnimation) {
      model.goBack()
    }
  }

  private func advance() {
    withAnimation(stageAnimation) {
      model.advance()
    }
  }

  private func stageVisualState(
    _ stage: KaidoProductJourneyStage
  ) -> JourneyStageVisualState {
    if stage == model.stage {
      return .current
    }
    if stage.order < model.stage.order {
      return .completed
    }
    if stage == .review, model.routeReviewReady {
      return .available
    }
    return .locked
  }

  private func progressLineColor(
    after stage: KaidoProductJourneyStage
  ) -> Color {
    stage.order < model.stage.order
      ? KaidoTheme.signalAmber
      : KaidoTheme.steel.opacity(0.55)
  }

  private func progressLineIsLocked(
    after stage: KaidoProductJourneyStage
  ) -> Bool {
    stage.order >= model.stage.order
  }

  private func stageShortTitle(_ stage: KaidoProductJourneyStage) -> String {
    switch stage {
    case .atlas:
      "选路"
    case .authoring:
      "编辑"
    case .review:
      "确认"
    case .navigation:
      "导航"
    }
  }

  private func stageTitle(_ stage: KaidoProductJourneyStage) -> String {
    switch stage {
    case .atlas:
      "路线图"
    case .authoring:
      "停车编辑"
    case .review:
      "行前确认"
    case .navigation:
      "路线导航"
    }
  }

  private func stageSymbol(_ stage: KaidoProductJourneyStage) -> String {
    switch stage {
    case .atlas:
      "map.fill"
    case .authoring:
      "point.3.connected.trianglepath.dotted"
    case .review:
      "checklist.checked"
    case .navigation:
      "location.fill"
    }
  }
}

private enum JourneyStageVisualState {
  case completed
  case current
  case available
  case locked
}

private struct JourneyStageButton: View {
  let stage: KaidoProductJourneyStage
  let title: String
  let symbol: String
  let state: JourneyStageVisualState
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 5) {
        ZStack {
          Circle()
            .fill(circleFill)
            .frame(width: 31, height: 31)

          Image(systemName: state == .completed ? "checkmark" : symbol)
            .font(.system(size: 11, weight: .black))
            .foregroundStyle(symbolColor)
        }

        Text(title)
          .font(.system(size: 8, weight: .black, design: .monospaced))
          .foregroundStyle(labelColor)
      }
      .frame(width: 48)
    }
    .buttonStyle(.plain)
    .disabled(state == .locked)
    .accessibilityLabel(title)
    .accessibilityValue(accessibilityState)
    .accessibilityAddTraits(state == .current ? .isSelected : [])
    .accessibilityRemoveTraits(
      state == .current ? [] : .isSelected
    )
    .accessibilityIdentifier("product-journey-step-\(stage.rawValue.lowercased())")
  }

  private var circleFill: Color {
    switch state {
    case .completed, .current:
      KaidoTheme.signalAmber
    case .available:
      KaidoTheme.positionCyan
    case .locked:
      KaidoTheme.steel.opacity(0.55)
    }
  }

  private var symbolColor: Color {
    switch state {
    case .completed, .current, .available:
      KaidoTheme.asphalt
    case .locked:
      KaidoTheme.muted
    }
  }

  private var labelColor: Color {
    switch state {
    case .current:
      KaidoTheme.routeWhite
    case .completed, .available:
      KaidoTheme.signalAmber
    case .locked:
      KaidoTheme.muted
    }
  }

  private var accessibilityState: String {
    switch state {
    case .completed:
      "COMPLETED"
    case .current:
      "CURRENT"
    case .available:
      "AVAILABLE"
    case .locked:
      "LOCKED"
    }
  }
}

private struct ReviewBoundaryCard: View {
  let symbol: String
  let title: String
  let detail: String
  let code: String
  let color: Color

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 17, weight: .black))
        .foregroundStyle(color)
        .frame(width: 26)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 5) {
        Text(title)
          .font(.system(size: 13, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)

        Text(detail)
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(KaidoTheme.muted)
          .fixedSize(horizontal: false, vertical: true)

        Text(verbatim: code)
          .font(.system(size: 8, weight: .black, design: .monospaced))
          .foregroundStyle(color)
      }

      Spacer(minLength: 2)
    }
    .padding(13)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(color.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .stroke(color.opacity(0.38), lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
  }
}
