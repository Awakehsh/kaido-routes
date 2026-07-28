import KaidoDomain
import KaidoNavigation
import KaidoPresentation
import SwiftUI

struct KaidoProductJourneyView: View {
  @StateObject private var model: KaidoProductJourneyModel
  @State private var planningMode = ProductPlanningMode.guided
  @State private var showsSavedRoutes = false
  @State private var showsSettings = false

  init(model: KaidoProductJourneyModel = KaidoProductJourneyModel()) {
    _model = StateObject(wrappedValue: model)
  }

  var body: some View {
    ZStack {
      stageBackground
        .ignoresSafeArea()

      if model.stage == .navigation {
        driveStage
      } else {
        VStack(spacing: 0) {
          parkedHeader

          ScrollViewReader { proxy in
            ScrollView {
              Color.clear
                .frame(height: 0)
                .id("product-journey-top")
                .accessibilityHidden(true)

              stageContent
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 112)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("product-journey-scroll")
            .onChange(of: model.stage) {
              proxy.scrollTo("product-journey-top", anchor: .top)
            }
          }
        }
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if model.stage == .authoring || model.stage == .review {
        journeyActionDock
      }
    }
    .environment(
      \.kaidoInterfaceLocale,
      model.composition.languageSettings.interfaceLocale
    )
    .preferredColorScheme(
      model.stage == .navigation ? .dark : .light
    )
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("product-journey-stage")
    .accessibilityValue(model.stage.rawValue)
    .sheet(isPresented: $showsSavedRoutes) {
      ProductSavedRoutesSheet(
        model: model.composition.savedRouteLibrary,
        openRoute: {
          showsSavedRoutes = false
          model.openSavedRoute($0)
        }
      )
      .environment(
        \.kaidoInterfaceLocale,
        model.composition.languageSettings.interfaceLocale
      )
    }
    .sheet(isPresented: $showsSettings) {
      ProductSettingsSheet(
        model: model.composition.languageSettings
      )
      .environment(
        \.kaidoInterfaceLocale,
        model.composition.languageSettings.interfaceLocale
      )
    }
  }

  private var parkedHeader: some View {
    HStack(spacing: 12) {
      if model.stage != .atlas {
        Button {
          withAnimation(.easeOut(duration: 0.18)) {
            model.goBack()
          }
        } label: {
          Image(systemName: "chevron.left")
            .font(.system(size: 14, weight: .black))
            .frame(width: 38, height: 38)
            .foregroundStyle(KaidoTheme.ink)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
          copy.resolve(
            japanese: "戻る",
            simplifiedChinese: "返回",
            english: "Back"
          )
        )
        .accessibilityIdentifier("product-journey-back")
      }

      VStack(alignment: .leading, spacing: 1) {
        Text("KAIDO")
          .font(.system(size: 10, weight: .black, design: .rounded))
          .tracking(1.1)
          .foregroundStyle(KaidoTheme.routeGreen)

        Text(stageTitle)
          .font(.system(size: 20, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.ink)
      }

      Spacer()

      Button {
        showsSettings = true
      } label: {
        Image(systemName: "slider.horizontal.3")
          .font(.system(size: 15, weight: .bold))
          .frame(width: 38, height: 38)
          .foregroundStyle(KaidoTheme.ink)
          .background(KaidoTheme.paperRaised)
          .clipShape(Circle())
          .overlay {
            Circle()
              .stroke(KaidoTheme.paperDivider, lineWidth: 1)
          }
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        copy.resolve(
          japanese: "設定",
          simplifiedChinese: "设置",
          english: "Settings"
        )
      )
      .accessibilityIdentifier("product-journey-settings")
    }
    .padding(.horizontal, 18)
    .frame(height: 62)
    .background(KaidoTheme.paper)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(KaidoTheme.paperDivider)
        .frame(height: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("product-journey-header")
  }

  @ViewBuilder
  private var stageContent: some View {
    switch model.stage {
    case .atlas:
      ProductRoutesStage(
        model: model,
        showsSavedRoutes: $showsSavedRoutes
      )
    case .authoring:
      ProductPlanStage(
        model: model,
        planningMode: $planningMode
      )
    case .review:
      ProductReviewStage(model: model)
    case .navigation:
      EmptyView()
    }
  }

  @ViewBuilder
  private var driveStage: some View {
    if let runtime = model.activeRuntime {
      ProductDriveStage(
        model: model,
        runtime: runtime
      )
    } else {
      VStack(spacing: 12) {
        Image(systemName: "exclamationmark.triangle")
        Text(
          copy.resolve(
            japanese: "ナビゲーションを開始できません",
            simplifiedChinese: "无法开始导航",
            english: "Navigation could not start"
          )
        )
      }
      .foregroundStyle(KaidoTheme.routeWhite)
    }
  }

  private var journeyActionDock: some View {
    HStack(spacing: 10) {
      Button {
        withAnimation(.easeOut(duration: 0.18)) {
          model.goBack()
        }
      } label: {
        Image(systemName: "chevron.left")
          .font(.system(size: 14, weight: .black))
          .frame(width: 48, height: 50)
          .foregroundStyle(KaidoTheme.ink)
          .background(KaidoTheme.paperRaised)
          .overlay {
            Rectangle()
              .stroke(KaidoTheme.paperDivider, lineWidth: 1)
          }
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        copy.resolve(
          japanese: "戻る",
          simplifiedChinese: "返回",
          english: "Back"
        )
      )

      Button {
        withAnimation(.easeOut(duration: 0.18)) {
          model.advance()
        }
      } label: {
        HStack {
          Text(primaryActionTitle)
          Spacer()
          Image(systemName: "arrow.right")
        }
        .font(.system(size: 14, weight: .black, design: .rounded))
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .foregroundStyle(KaidoTheme.paperRaised)
        .background(
          primaryActionEnabled
            ? KaidoTheme.routeGreen
            : KaidoTheme.roadGray
        )
      }
      .buttonStyle(.plain)
      .disabled(!primaryActionEnabled)
      .accessibilityIdentifier("product-journey-primary-action")
      .accessibilityValue(
        primaryActionEnabled ? "AVAILABLE" : "BLOCKED"
      )
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 12)
    .background(.ultraThinMaterial)
    .overlay(alignment: .top) {
      Rectangle()
        .fill(KaidoTheme.paperDivider)
        .frame(height: 1)
    }
  }

  private var primaryActionEnabled: Bool {
    switch model.stage {
    case .authoring:
      model.routeReviewReady
    case .review:
      model.canEnterDrivingStage
    case .atlas, .navigation:
      false
    }
  }

  private var primaryActionTitle: String {
    switch model.stage {
    case .authoring:
      copy.resolve(
        japanese: "出発前確認へ",
        simplifiedChinese: "查看行前确认",
        english: "Review the journey"
      )
    case .review:
      model.canStartRehearsal
        ? copy.resolve(
          japanese: "演習を開始",
          simplifiedChinese: "开始演练",
          english: "Start rehearsal"
        )
        : copy.resolve(
          japanese: "ナビを開始",
          simplifiedChinese: "开始导航",
          english: "Start navigation"
        )
    case .atlas, .navigation:
      ""
    }
  }

  private var stageTitle: String {
    switch model.stage {
    case .atlas:
      copy.resolve(
        japanese: "ルート",
        simplifiedChinese: "路线",
        english: "Routes"
      )
    case .authoring:
      copy.resolve(
        japanese: "ルート設計",
        simplifiedChinese: "设计路线",
        english: "Plan"
      )
    case .review:
      copy.resolve(
        japanese: "出発前確認",
        simplifiedChinese: "出发前确认",
        english: "Review"
      )
    case .navigation:
      copy.resolve(
        japanese: "走行",
        simplifiedChinese: "行驶",
        english: "Drive"
      )
    }
  }

  private var stageBackground: Color {
    model.stage == .navigation
      ? KaidoTheme.asphalt
      : KaidoTheme.paper
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(
      locale: model.composition.languageSettings.interfaceLocale
    )
  }
}

private struct ProductRoutesStage: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale
  @ObservedObject var model: KaidoProductJourneyModel
  @Binding var showsSavedRoutes: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      originControl

      ProductMapProjectionPicker(
        model: model.composition.productMapPresentation,
        usesDarkStyle: false
      )

      ProductMapViewport(
        mapModel: model.composition.productMapPresentation,
        surfaceID: "routes",
        presentation: model.discoveryRouteAtlasPresentation,
        navigationSnapshot: nil,
        positionEvidence: nil,
        usesDarkStyle: false
      )

      entranceRecommendation
      routeCatalog
      routeActions
    }
  }

  private var originControl: some View {
    Button {
    } label: {
      HStack(spacing: 12) {
        Image(systemName: "location.circle.fill")
          .font(.system(size: 20))
          .foregroundStyle(KaidoTheme.routeGreen)

        VStack(alignment: .leading, spacing: 2) {
          Text(
            copy.resolve(
              japanese: "ここから出発",
              simplifiedChinese: "从这里出发",
              english: "Start from here"
            )
          )
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(KaidoTheme.quietText)

          Text(
            copy.resolve(
              japanese: "港区虎ノ門 1 丁目付近",
              simplifiedChinese: "港区虎之门 1 丁目附近",
              english: "Near Toranomon 1-chome, Minato"
            )
          )
          .font(.system(size: 14, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.ink)
        }

        Spacer()

        Image(systemName: "chevron.down")
          .font(.system(size: 11, weight: .black))
          .foregroundStyle(KaidoTheme.quietText)
      }
      .padding(.horizontal, 14)
      .frame(height: 62)
      .background(KaidoTheme.paperRaised)
      .overlay {
        Rectangle()
          .stroke(KaidoTheme.paperDivider, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("product-routes-origin")
  }

  private var entranceRecommendation: some View {
    HStack(spacing: 10) {
      Image(systemName: "location.north.line.fill")
        .foregroundStyle(KaidoTheme.paperRaised)
        .frame(width: 30, height: 30)
        .background(KaidoTheme.routeGreen)
        .clipShape(Circle())

      VStack(alignment: .leading, spacing: 2) {
        Text(recommendedEntranceTitle)
          .font(.system(size: 13, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.ink)

        Text(
          copy.resolve(
            japanese: "この経路に対応する方向入口",
            simplifiedChinese: "与当前路线方向兼容",
            english: "Compatible with this route direction"
          )
        )
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(KaidoTheme.quietText)
      }

      Spacer()

      VStack(alignment: .trailing, spacing: 1) {
        Text(
          copy.resolve(
            japanese: "約 7 分",
            simplifiedChinese: "约 7 分钟",
            english: "About 7 min"
          )
        )
        .font(.system(size: 12, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.routeGreenDeep)

        Text(
          copy.resolve(
            japanese: "入口まで",
            simplifiedChinese: "到入口",
            english: "to entrance"
          )
        )
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(KaidoTheme.quietText)
      }
    }
    .padding(12)
    .background(KaidoTheme.paperRaised)
    .overlay(alignment: .leading) {
      Rectangle()
        .fill(KaidoTheme.routeGreen)
        .frame(width: 3)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("product-routes-recommendation")
  }

  private var routeCatalog: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(
          copy.resolve(
            japanese: "おすすめ",
            simplifiedChinese: "推荐",
            english: "Recommended"
          )
        )
        .font(.system(size: 18, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.ink)

        Spacer()

        Text(
          copy.resolve(
            japanese: "すべて",
            simplifiedChinese: "全部",
            english: "All"
          )
        )
        .font(.system(size: 11, weight: .black))
        .foregroundStyle(KaidoTheme.routeGreen)
      }

      if let authoring = model.composition.releasedRouteAuthoring {
        ForEach(authoring.options) { option in
          routeCard(option)
        }
      } else {
        Text(
          copy.resolve(
            japanese: "現在利用できる経路はありません",
            simplifiedChinese: "当前没有可用路线",
            english: "No routes are currently available"
          )
        )
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(KaidoTheme.quietText)
        .padding(.vertical, 20)
      }
    }
  }

  private func routeCard(
    _ option: ReleasedProductRouteOptionPresentation
  ) -> some View {
    Button {
      withAnimation(.easeOut(duration: 0.18)) {
        model.selectRouteForPlanning(option.productReleaseID)
      }
    } label: {
      HStack(spacing: 13) {
        VStack(spacing: 2) {
          Text(option.primaryRouteShield)
            .font(.system(size: 13, weight: .black, design: .rounded))
          Text(
            copy.resolve(
              japanese:
                model.usesDemoRehearsal ? "演習" : "リリース",
              simplifiedChinese:
                model.usesDemoRehearsal ? "演练" : "发布",
              english:
                model.usesDemoRehearsal ? "DEMO" : "RELEASED"
            )
          )
          .font(.system(size: 7, weight: .black, design: .rounded))
        }
        .foregroundStyle(KaidoTheme.paperRaised)
        .frame(width: 47, height: 47)
        .background(KaidoTheme.routeGreen)
        .clipShape(RoundedRectangle(cornerRadius: 10))

        VStack(alignment: .leading, spacing: 5) {
          HStack(spacing: 7) {
            Text(option.routeTitle)
              .font(.system(size: 15, weight: .black, design: .rounded))
              .foregroundStyle(KaidoTheme.ink)

            if model.usesDemoRehearsal {
              Text(
                copy.resolve(
                  japanese: "演習",
                  simplifiedChinese: "演练",
                  english: "DEMO"
                )
              )
              .font(.system(size: 7, weight: .black, design: .rounded))
              .foregroundStyle(KaidoTheme.routeGreen)
              .padding(.horizontal, 6)
              .padding(.vertical, 3)
              .overlay {
                Capsule()
                  .stroke(KaidoTheme.routeGreen.opacity(0.5), lineWidth: 1)
              }
            }
          }

          Text(option.entranceTitle)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(KaidoTheme.quietText)
            .lineLimit(1)

          HStack(spacing: 12) {
            Text(String(format: "%.1f km", option.actualDistanceKM))
            Text(
              copy.resolve(
                japanese: "\(option.decisionCount) 分岐",
                simplifiedChinese: "\(option.decisionCount) 个分岔",
                english: "\(option.decisionCount) decisions"
              )
            )
          }
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(KaidoTheme.quietText)
        }

        Spacer(minLength: 4)

        Image(systemName: "chevron.right")
          .font(.system(size: 11, weight: .black))
          .foregroundStyle(KaidoTheme.quietText)
      }
      .padding(13)
      .background(KaidoTheme.paperRaised)
      .overlay(alignment: .leading) {
        Rectangle()
          .fill(KaidoTheme.signalAmber)
          .frame(width: 3)
      }
      .overlay {
        Rectangle()
          .stroke(KaidoTheme.paperDivider, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(
      "product-route-option-\(option.productReleaseID)"
    )
    .accessibilityLabel(
      "\(option.routeTitle), \(option.entranceTitle)"
    )
  }

  private var routeActions: some View {
    HStack(spacing: 10) {
      Button {
        withAnimation(.easeOut(duration: 0.18)) {
          model.advance()
        }
      } label: {
        actionTile(
          title: copy.resolve(
            japanese: "ルートを作る",
            simplifiedChinese: "自己设计路线",
            english: "Create route"
          ),
          symbol: "point.3.connected.trianglepath.dotted"
        )
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("product-routes-create")

      Button {
        showsSavedRoutes = true
      } label: {
        actionTile(
          title: copy.resolve(
            japanese: "保存ルート",
            simplifiedChinese: "我的路线",
            english: "Saved routes"
          ),
          symbol: "bookmark"
        )
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("product-routes-saved")
    }
  }

  private func actionTile(
    title: String,
    symbol: String
  ) -> some View {
    HStack(spacing: 9) {
      Image(systemName: symbol)
      Text(title)
      Spacer(minLength: 2)
      Image(systemName: "chevron.right")
        .font(.system(size: 9, weight: .black))
    }
    .font(.system(size: 12, weight: .black, design: .rounded))
    .foregroundStyle(KaidoTheme.ink)
    .padding(.horizontal, 12)
    .frame(maxWidth: .infinity)
    .frame(height: 54)
    .background(KaidoTheme.paperRaised)
    .overlay {
      Rectangle()
        .stroke(KaidoTheme.paperDivider, lineWidth: 1)
    }
  }

  private var recommendedEntranceTitle: String {
    model.composition.releasedRouteAuthoring?.options.first?.entranceTitle
      ?? copy.resolve(
        japanese: "対応入口を確認中",
        simplifiedChinese: "正在确认兼容入口",
        english: "Checking compatible entrance"
      )
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }
}

private enum ProductPlanningMode: String, CaseIterable, Identifiable {
  case guided
  case expert

  var id: String { rawValue }
}

private struct ProductPlanStage: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale
  @ObservedObject var model: KaidoProductJourneyModel
  @Binding var planningMode: ProductPlanningMode

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      ProductMapProjectionPicker(
        model: model.composition.productMapPresentation,
        usesDarkStyle: false
      )

      ProductMapViewport(
        mapModel: model.composition.productMapPresentation,
        surfaceID: "plan",
        presentation: mapPresentation,
        navigationSnapshot: nil,
        positionEvidence: nil,
        usesDarkStyle: false
      )

      planningModePicker
      editor
    }
  }

  private var planningModePicker: some View {
    HStack(spacing: 0) {
      ForEach(ProductPlanningMode.allCases) { mode in
        Button {
          planningMode = mode
        } label: {
          Text(modeTitle(mode))
            .font(.system(size: 11, weight: .black, design: .rounded))
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .foregroundStyle(
              planningMode == mode
                ? KaidoTheme.paperRaised
                : KaidoTheme.quietText
            )
            .background(
              planningMode == mode
                ? KaidoTheme.routeGreen
                : KaidoTheme.paperRaised
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(
          planningMode == mode ? .isSelected : []
        )
        .accessibilityIdentifier(
          "product-plan-mode-\(mode.rawValue)"
        )
      }
    }
    .overlay {
      Rectangle()
        .stroke(KaidoTheme.paperDivider, lineWidth: 1)
    }
  }

  @ViewBuilder
  private var editor: some View {
    if let authoring = model.composition.releasedRouteAuthoring {
      if authoring.hasSelection {
        selectedRouteEditor(authoring)
      } else {
        routePicker(authoring)
      }
    } else {
      Text(
        copy.resolve(
          japanese: "このプレビューで作成できる経路はありません",
          simplifiedChinese: "当前预览没有可编辑路线",
          english: "No editable route is available in this preview"
        )
      )
      .font(.system(size: 13, weight: .bold))
      .foregroundStyle(KaidoTheme.quietText)
    }
  }

  private func routePicker(
    _ authoring: ReleasedProductRouteAuthoringModel
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      sectionTitle(
        copy.resolve(
          japanese: "経路を選択",
          simplifiedChinese: "选择路线",
          english: "Choose a route"
        )
      )

      ForEach(authoring.options) { option in
        Button {
          model.selectRouteForPlanning(option.productReleaseID)
        } label: {
          HStack {
            VStack(alignment: .leading, spacing: 3) {
              Text(option.entranceTitle)
                .font(.system(size: 14, weight: .black, design: .rounded))
              Text(option.finalChoiceTitle)
                .font(.system(size: 11, weight: .bold))
            }
            Spacer()
            Image(systemName: "chevron.right")
          }
          .foregroundStyle(KaidoTheme.ink)
          .padding(13)
          .background(KaidoTheme.paperRaised)
          .overlay {
            Rectangle()
              .stroke(KaidoTheme.paperDivider, lineWidth: 1)
          }
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func selectedRouteEditor(
    _ authoring: ReleasedProductRouteAuthoringModel
  ) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          Text(model.selectedRouteOption?.entranceTitle ?? "")
            .font(.system(size: 17, weight: .black, design: .rounded))
            .foregroundStyle(KaidoTheme.ink)
          Text(
            planningMode == .guided
              ? copy.resolve(
                japanese: "確認済みの順序で分岐を選びます",
                simplifiedChinese: "按已审核顺序选择分岔",
                english: "Choose the reviewed decisions in order"
              )
              : copy.resolve(
                japanese: "現在の進入方向から合法な分岐だけを表示",
                simplifiedChinese: "只显示当前来向的合法分岔",
                english: "Only legal choices from the current approach"
              )
          )
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(KaidoTheme.quietText)
        }

        Spacer()

        Button {
          authoring.clearSelection()
        } label: {
          Text(
            copy.resolve(
              japanese: "変更",
              simplifiedChinese: "更换",
              english: "Change"
            )
          )
          .font(.system(size: 10, weight: .black))
          .foregroundStyle(KaidoTheme.routeGreen)
        }
        .buttonStyle(.plain)
      }

      routeThread(authoring)

      if let step = authoring.currentStep {
        decisionStep(step, authoring: authoring)
      } else if authoring.compiledRoutePlan == nil {
        Button {
          authoring.compile()
        } label: {
          Label(
            copy.resolve(
              japanese: "経路を確定",
              simplifiedChinese: "确认路线",
              english: "Confirm route"
            ),
            systemImage: "checkmark"
          )
          .font(.system(size: 13, weight: .black, design: .rounded))
          .frame(maxWidth: .infinity)
          .frame(height: 48)
          .foregroundStyle(KaidoTheme.paperRaised)
          .background(KaidoTheme.routeGreen)
        }
        .buttonStyle(.plain)
        .disabled(!authoring.canCompile)
        .accessibilityIdentifier("released-route-compile")
      }

      if authoring.compiledRoutePlan != nil {
        tripSetup(authoring)
      }
    }
    .padding(14)
    .background(KaidoTheme.paperRaised)
    .overlay {
      Rectangle()
        .stroke(KaidoTheme.paperDivider, lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("product-plan-editor")
  }

  private func routeThread(
    _ authoring: ReleasedProductRouteAuthoringModel
  ) -> some View {
    let occurrences = authoring.snapshot?.occurrences ?? []
    return VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 4) {
        ForEach(Array(occurrences.enumerated()), id: \.offset) { _, _ in
          Capsule()
            .fill(KaidoTheme.routeGreen)
            .frame(maxWidth: .infinity)
            .frame(height: 5)
        }

        if occurrences.isEmpty {
          Capsule()
            .fill(KaidoTheme.roadGray)
            .frame(maxWidth: .infinity)
            .frame(height: 5)
        }
      }

      HStack {
        Text(
          copy.resolve(
            japanese: "入口",
            simplifiedChinese: "入口",
            english: "Entrance"
          )
        )
        Spacer()
        Text(
          copy.resolve(
            japanese: "\(occurrences.count) 区間",
            simplifiedChinese: "\(occurrences.count) 个路段",
            english: "\(occurrences.count) segments"
          )
        )
      }
      .font(.system(size: 9, weight: .black))
      .foregroundStyle(KaidoTheme.quietText)
    }
  }

  private func decisionStep(
    _ step: ReleasedRouteEditorStepPresentation,
    authoring: ReleasedProductRouteAuthoringModel
  ) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      Text(step.decisionTitle)
        .font(.system(size: 14, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.ink)

      Button {
        authoring.selectReleasedChoice(step.choiceID)
      } label: {
        HStack(spacing: 12) {
          Image(systemName: "arrow.turn.up.right")
            .font(.system(size: 17, weight: .black))
            .frame(width: 38, height: 38)
            .foregroundStyle(KaidoTheme.paperRaised)
            .background(KaidoTheme.routeGreen)

          VStack(alignment: .leading, spacing: 3) {
            Text(step.choiceTitle)
              .font(.system(size: 13, weight: .black))
            Text(step.choiceDetail)
              .font(.system(size: 10, weight: .bold))
              .foregroundStyle(KaidoTheme.quietText)
          }

          Spacer()
          Image(systemName: "plus")
            .font(.system(size: 11, weight: .black))
        }
        .foregroundStyle(KaidoTheme.ink)
        .padding(12)
        .background(KaidoTheme.paper)
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("released-route-choice-\(step.choiceID)")
    }
  }

  private func tripSetup(
    _ authoring: ReleasedProductRouteAuthoringModel
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Divider()
        .overlay(KaidoTheme.paperDivider)

      sectionTitle(
        copy.resolve(
          japanese: "出発設定",
          simplifiedChinese: "出发设置",
          english: "Trip setup"
        )
      )

      ScrollView(.horizontal) {
        HStack(spacing: 7) {
          ForEach(
            authoring.availableVehicleClasses,
            id: \.rawValue
          ) { vehicleClass in
            let selected =
              authoring.selectedVehicleClass == vehicleClass
            Button {
              authoring.selectVehicleClass(vehicleClass)
            } label: {
              Text(vehicleClass.officialJapaneseLabel)
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(
                  selected
                    ? KaidoTheme.paperRaised
                    : KaidoTheme.ink
                )
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(
                  selected
                    ? KaidoTheme.routeGreen
                    : KaidoTheme.paper
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(
              "released-vehicle-class-\(vehicleClass.rawValue)"
            )
            .accessibilityAddTraits(selected ? .isSelected : [])
          }
        }
      }
      .scrollIndicators(.hidden)

      HStack(spacing: 8) {
        ForEach(
          authoring.availablePaymentMethods,
          id: \.rawValue
        ) { paymentMethod in
          let selected =
            authoring.selectedPaymentMethod == paymentMethod
          Button {
            authoring.selectPaymentMethod(paymentMethod)
          } label: {
            Text(paymentMethod.rawValue)
              .font(.system(size: 11, weight: .black, design: .rounded))
              .frame(maxWidth: .infinity)
              .frame(height: 38)
              .foregroundStyle(
                selected
                  ? KaidoTheme.paperRaised
                  : KaidoTheme.ink
              )
              .background(
                selected
                  ? KaidoTheme.routeGreen
                  : KaidoTheme.paper
              )
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier(
            "released-payment-method-\(paymentMethod.rawValue)"
          )
          .accessibilityAddTraits(selected ? .isSelected : [])
        }
      }

      if authoring.reviewReady {
        Label(
          copy.resolve(
            japanese: "出発前確認の準備ができました",
            simplifiedChinese: "已可进入行前确认",
            english: "Ready for pre-drive review"
          ),
          systemImage: "checkmark.circle.fill"
        )
        .font(.system(size: 11, weight: .black))
        .foregroundStyle(KaidoTheme.routeGreen)
        .accessibilityIdentifier("released-route-review-ready")
      } else if authoring.compiledRoutePlan != nil {
        Text(setupPrompt(authoring))
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(KaidoTheme.quietText)
          .accessibilityIdentifier("released-route-authoring-blocker")
          .accessibilityValue(authoring.lastErrorCode ?? "SELECTION_REQUIRED")
      }
    }
  }

  private func setupPrompt(
    _ authoring: ReleasedProductRouteAuthoringModel
  ) -> String {
    if authoring.selectedVehicleClass == nil {
      return copy.resolve(
        japanese: "車種を選択してください",
        simplifiedChinese: "请选择车型",
        english: "Choose a vehicle class"
      )
    }
    if authoring.selectedPaymentMethod == nil {
      return copy.resolve(
        japanese: "支払方法を選択してください",
        simplifiedChinese: "请选择支付方式",
        english: "Choose a payment method"
      )
    }
    return copy.resolve(
      japanese: "現在の行前情報を確認できません",
      simplifiedChinese: "当前行前信息不可用",
      english: "Current pre-drive information is unavailable"
    )
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 15, weight: .black, design: .rounded))
      .foregroundStyle(KaidoTheme.ink)
  }

  private func modeTitle(_ mode: ProductPlanningMode) -> String {
    switch mode {
    case .guided:
      copy.resolve(
        japanese: "ガイド",
        simplifiedChinese: "推荐",
        english: "Guided"
      )
    case .expert:
      copy.resolve(
        japanese: "エキスパート",
        simplifiedChinese: "专家",
        english: "Expert"
      )
    }
  }

  private var mapPresentation: ReleasedRouteAtlasOverlayPresentation {
    switch model.routeAtlasOverlayPresentation {
    case .unavailable:
      model.discoveryRouteAtlasPresentation
    case .ready, .blocked:
      model.routeAtlasOverlayPresentation
    }
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }
}

private struct ProductReviewStage: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale
  @ObservedObject var model: KaidoProductJourneyModel

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      ProductMapProjectionPicker(
        model: model.composition.productMapPresentation,
        usesDarkStyle: false
      )

      ProductMapViewport(
        mapModel: model.composition.productMapPresentation,
        surfaceID: "review",
        presentation: model.routeAtlasOverlayPresentation,
        navigationSnapshot: nil,
        positionEvidence: nil,
        usesDarkStyle: false
      )

      journeySummary

      if let snapshot = model.preDriveReviewSnapshot {
        metrics(snapshot)
        availability(snapshot)
      } else if model.hasExpiredReferencePreDriveInformation,
        let reference = model.referencePreDriveInformation
      {
        metrics(reference.snapshot)
        staleInformation(reference)
      } else {
        routeOnlyMetrics
        unavailableInformation
      }
      voice
    }
  }

  private var journeySummary: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 3) {
          Text(
            model.selectedRouteOption?.routeTitle
              ?? copy.resolve(
                japanese: "選択した経路",
                simplifiedChinese: "已选路线",
                english: "Selected route"
              )
          )
          .font(.system(size: 21, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.ink)

          Text(
            model.selectedRouteOption?.entranceTitle
              ?? copy.resolve(
                japanese: "選択した入口",
                simplifiedChinese: "已选入口",
                english: "Selected entrance"
              )
          )
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(KaidoTheme.quietText)
        }

        Spacer()

        Text(model.selectedRouteOption?.primaryRouteShield ?? "—")
          .font(.system(size: 15, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.paperRaised)
          .frame(width: 44, height: 44)
          .background(KaidoTheme.routeGreen)
          .clipShape(RoundedRectangle(cornerRadius: 9))
      }

      HStack(spacing: 8) {
        Image(systemName: "location.circle.fill")
        Text(
          copy.resolve(
            japanese: "現在地",
            simplifiedChinese: "当前位置",
            english: "Current origin"
          )
        )
        Image(systemName: "arrow.right")
        Text(
          model.selectedRouteOption?.entranceTitle
            ?? copy.resolve(
              japanese: "方向入口",
              simplifiedChinese: "方向入口",
              english: "Directional entrance"
            )
        )
      }
      .font(.system(size: 10, weight: .bold))
      .foregroundStyle(KaidoTheme.quietText)

      routeThread
    }
    .padding(16)
    .background(KaidoTheme.paperRaised)
    .overlay {
      Rectangle()
        .stroke(KaidoTheme.paperDivider, lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("product-review-summary")
  }

  private var routeThread: some View {
    HStack(spacing: 0) {
      Circle()
        .fill(KaidoTheme.routeGreen)
        .frame(width: 9, height: 9)
      Rectangle()
        .fill(KaidoTheme.routeGreen)
        .frame(height: 3)
      Circle()
        .fill(KaidoTheme.signalAmber)
        .frame(width: 9, height: 9)
      Rectangle()
        .fill(KaidoTheme.routeGreen)
        .frame(height: 3)
      Circle()
        .stroke(KaidoTheme.routeGreen, lineWidth: 3)
        .frame(width: 11, height: 11)
    }
    .accessibilityHidden(true)
  }

  private func metrics(
    _ snapshot: PreDriveReviewSnapshot
  ) -> some View {
    let presentation = snapshot.presentation
    return VStack(spacing: 0) {
      reviewRow(
        title: copy.resolve(
          japanese: "走行予定距離",
          simplifiedChinese: "实际规划距离",
          english: "Planned distance"
        ),
        value: String(
          format: "%.1f km",
          presentation.actualDistanceKM
        )
      )

      Divider()
        .overlay(KaidoTheme.paperDivider)

      reviewRow(
        title: copy.resolve(
          japanese: "料金計算距離",
          simplifiedChinese: "计费距离",
          english: "Tariff distance"
        ),
        value:
          presentation.tariffDistanceKM.map {
            String(format: "%.1f km", $0)
          } ?? "—"
      )

      Divider()
        .overlay(KaidoTheme.paperDivider)

      reviewRow(
        title: copy.resolve(
          japanese: "料金",
          simplifiedChinese: "费用",
          english: "Toll"
        ),
        value:
          presentation.estimatedAmountYen.map {
            "¥\($0)"
          } ?? "—"
      )

      Divider()
        .overlay(KaidoTheme.paperDivider)

      reviewRow(
        title: copy.resolve(
          japanese: "経路",
          simplifiedChinese: "路线",
          english: "Route"
        ),
        value: copy.resolve(
          japanese: "\(snapshot.occurrenceCount) 区間",
          simplifiedChinese: "\(snapshot.occurrenceCount) 个路段",
          english: "\(snapshot.occurrenceCount) segments"
        )
      )
    }
    .padding(.horizontal, 14)
    .background(KaidoTheme.paperRaised)
    .overlay {
      Rectangle()
        .stroke(KaidoTheme.paperDivider, lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("product-review-metrics")
  }

  private func availability(
    _ snapshot: PreDriveReviewSnapshot
  ) -> some View {
    let tone = snapshot.presentation.passage.tone
    return HStack(alignment: .top, spacing: 11) {
      Image(
        systemName:
          tone == .blocked || tone == .warning
          ? "exclamationmark.octagon.fill"
          : "exclamationmark.circle.fill"
      )
      .foregroundStyle(
        tone == .blocked || tone == .warning
          ? KaidoTheme.evidenceCoral
          : KaidoTheme.signalAmber
      )

      VStack(alignment: .leading, spacing: 3) {
        Text(
          passageTitle(tone)
        )
        .font(.system(size: 12, weight: .black))
        .foregroundStyle(KaidoTheme.ink)

        Text(
          copy.resolve(
            japanese: "確認時刻：\(snapshot.checkedAt)",
            simplifiedChinese: "检查时间：\(snapshot.checkedAt)",
            english: "Checked: \(snapshot.checkedAt)"
          )
        )
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(KaidoTheme.quietText)
      }
    }
    .padding(13)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      tone == .blocked || tone == .warning
        ? KaidoTheme.evidenceCoral.opacity(0.12)
        : KaidoTheme.signalAmber.opacity(0.12)
    )
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(
      tone == .blocked || tone == .warning
        ? "product-review-passage-blocker"
        : "product-review-availability"
    )
  }

  private var routeOnlyMetrics: some View {
    let routePlan = model.compiledRoutePlan
    return VStack(spacing: 0) {
      reviewRow(
        title: copy.resolve(
          japanese: "走行予定距離",
          simplifiedChinese: "实际规划距离",
          english: "Planned distance"
        ),
        value:
          routePlan?.actualDistanceKM.map {
            String(format: "%.1f km", $0)
          } ?? "—"
      )

      Divider()
        .overlay(KaidoTheme.paperDivider)

      reviewRow(
        title: copy.resolve(
          japanese: "料金",
          simplifiedChinese: "费用",
          english: "Toll"
        ),
        value: copy.resolve(
          japanese: "現在情報なし",
          simplifiedChinese: "无当前信息",
          english: "Not current"
        )
      )

      Divider()
        .overlay(KaidoTheme.paperDivider)

      reviewRow(
        title: copy.resolve(
          japanese: "経路",
          simplifiedChinese: "路线",
          english: "Route"
        ),
        value: copy.resolve(
          japanese: "\(routePlan?.occurrences.count ?? 0) 区間",
          simplifiedChinese: "\(routePlan?.occurrences.count ?? 0) 个路段",
          english: "\(routePlan?.occurrences.count ?? 0) segments"
        )
      )
    }
    .padding(.horizontal, 14)
    .background(KaidoTheme.paperRaised)
    .overlay {
      Rectangle()
        .stroke(KaidoTheme.paperDivider, lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("product-review-metrics")
  }

  private func staleInformation(
    _ reference: ReleasedPreDriveInformationReference
  ) -> some View {
    HStack(alignment: .top, spacing: 11) {
      Image(systemName: "clock.badge.exclamationmark.fill")
        .foregroundStyle(KaidoTheme.signalAmber)

      VStack(alignment: .leading, spacing: 4) {
        Text(
          copy.resolve(
            japanese: "料金・通行情報は期限切れ",
            simplifiedChinese: "费用与通行信息已过期",
            english: "Toll and passage information has expired"
          )
        )
        .font(.system(size: 12, weight: .black))
        .foregroundStyle(KaidoTheme.ink)

        Text(
          copy.resolve(
            japanese:
              "最終確認：\(reference.snapshot.checkedAt) · 期限：\(reference.expiresAt)。経路は利用できます。現地の標識・規制・料金表示に従ってください。",
            simplifiedChinese:
              "最后检查：\(reference.snapshot.checkedAt) · 到期：\(reference.expiresAt)。路线仍可使用，请遵守现场标志、管制与收费信息。",
            english:
              "Last checked: \(reference.snapshot.checkedAt) · expired: \(reference.expiresAt). The route remains available; follow on-road signs, restrictions, and toll notices."
          )
        )
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(KaidoTheme.quietText)
      }
    }
    .padding(13)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(KaidoTheme.signalAmber.opacity(0.12))
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("product-review-information-stale")
  }

  private var unavailableInformation: some View {
    HStack(alignment: .top, spacing: 11) {
      Image(systemName: "info.circle.fill")
        .foregroundStyle(KaidoTheme.signalAmber)

      VStack(alignment: .leading, spacing: 4) {
        Text(
          copy.resolve(
            japanese: "現在の料金・リアルタイム通行情報なし",
            simplifiedChinese: "无当前费用与实时通行信息",
            english: "No current toll or realtime passage information"
          )
        )
        .font(.system(size: 12, weight: .black))
        .foregroundStyle(KaidoTheme.ink)

        Text(
          copy.resolve(
            japanese:
              "検証済み経路は利用できます。現地の標識・規制・料金表示に従ってください。",
            simplifiedChinese:
              "已验证路线仍可使用，请遵守现场标志、管制与收费信息。",
            english:
              "The reviewed route remains available. Follow on-road signs, restrictions, and toll notices."
          )
        )
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(KaidoTheme.quietText)
      }
    }
    .padding(13)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(KaidoTheme.signalAmber.opacity(0.12))
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("product-review-information-unavailable")
  }

  private func passageTitle(
    _ tone: RoutePassagePresentationTone
  ) -> String {
    switch tone {
    case .blocked:
      copy.resolve(
        japanese: "既知の通行止め：ナビ開始不可",
        simplifiedChinese: "已知封闭：无法开始导航",
        english: "Known closure: navigation cannot start"
      )
    case .warning:
      copy.resolve(
        japanese: "計画上の通行競合：ナビ開始不可",
        simplifiedChinese: "已知计划冲突：无法开始导航",
        english: "Known planned conflict: navigation cannot start"
      )
    case .unconfirmed:
      copy.resolve(
        japanese: "リアルタイム通行状態は未確認",
        simplifiedChinese: "实时通行状态尚未确认",
        english: "Realtime passage is unconfirmed"
      )
    case .confirmedPassable:
      copy.resolve(
        japanese: "リアルタイム通行可能",
        simplifiedChinese: "实时确认可通行",
        english: "Realtime passage confirmed"
      )
    }
  }

  private var voice: some View {
    HStack(spacing: 12) {
      Image(systemName: "speaker.wave.2")
        .foregroundStyle(KaidoTheme.routeGreen)
      VStack(alignment: .leading, spacing: 2) {
        Text(
          copy.resolve(
            japanese: "案内音声",
            simplifiedChinese: "引导语音",
            english: "Guidance voice"
          )
        )
        .font(.system(size: 11, weight: .black))
        .foregroundStyle(KaidoTheme.ink)
        Text(
          model.composition.languageSettings.guidanceVoiceLocale
            .nativeLanguageName
        )
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(KaidoTheme.quietText)
      }
      Spacer()
      Image(systemName: "chevron.right")
        .font(.system(size: 10, weight: .black))
        .foregroundStyle(KaidoTheme.quietText)
    }
    .padding(13)
    .background(KaidoTheme.paperRaised)
    .overlay {
      Rectangle()
        .stroke(KaidoTheme.paperDivider, lineWidth: 1)
    }
    .accessibilityIdentifier("product-review-voice")
  }

  private func reviewRow(
    title: String,
    value: String
  ) -> some View {
    HStack {
      Text(title)
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(KaidoTheme.quietText)
      Spacer()
      Text(value)
        .font(.system(size: 13, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.ink)
    }
    .frame(height: 48)
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }
}

private struct ProductDriveStage: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale
  @Environment(\.scenePhase) private var scenePhase
  @ObservedObject var model: KaidoProductJourneyModel
  @ObservedObject var runtime: ProductNavigationRuntimeModel
  @ObservedObject private var locationController: ForegroundNavigationLocationController
  @State private var isStartingRehearsal = false
  @State private var showsFinishConfirmation = false

  init(
    model: KaidoProductJourneyModel,
    runtime: ProductNavigationRuntimeModel
  ) {
    self.model = model
    self.runtime = runtime
    locationController = runtime.foregroundNavigationLocationController
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 14) {
        driveHeader
        guidance

        ProductMapProjectionPicker(
          model: model.composition.productMapPresentation,
          usesDarkStyle: true
        )

        ProductMapViewport(
          mapModel: model.composition.productMapPresentation,
          surfaceID: "drive",
          presentation: runtime.routeAtlasOverlayPresentation,
          navigationSnapshot: runtime.snapshot,
          positionEvidence: runtime.topologyPositionEvidence,
          usesDarkStyle: true
        )

        routeProgress
        if runtime.isRealRoadAuthority {
          liveLocationControl
        }
        rehearsalControls
      }
      .padding(.horizontal, 16)
      .padding(.top, 8)
      .padding(.bottom, 30)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("product-drive-surface")
    }
    .scrollIndicators(.hidden)
    .background(KaidoTheme.asphalt)
    .task {
      await runtime.activate()
      locationController.refreshRuntimeAvailability()
    }
    .onChange(of: scenePhase, initial: true) { _, newPhase in
      Task {
        await handleScenePhase(newPhase.productRuntimePhase)
      }
    }
    .confirmationDialog(
      copy.resolve(
        japanese: "演習を終了しますか？",
        simplifiedChinese: "结束本次演练？",
        english: "End this rehearsal?"
      ),
      isPresented: $showsFinishConfirmation
    ) {
      Button(
        copy.resolve(
          japanese: "演習を終了",
          simplifiedChinese: "结束演练",
          english: "End rehearsal"
        ),
        role: .destructive
      ) {
        Task {
          if runtime.isRealRoadAuthority {
            await model.endNavigation()
          } else {
            await model.endRehearsal()
          }
        }
      }
      Button(
        copy.resolve(
          japanese: "続ける",
          simplifiedChinese: "继续行驶",
          english: "Continue driving"
        ),
        role: .cancel
      ) {
      }
    }
  }

  private var driveHeader: some View {
    HStack {
      VStack(alignment: .leading, spacing: 1) {
        Text("KAIDO")
          .font(.system(size: 9, weight: .black, design: .rounded))
          .tracking(1)
          .foregroundStyle(KaidoTheme.signalAmber)

        Text(
          copy.resolve(
            japanese: "走行",
            simplifiedChinese: "行驶",
            english: "Drive"
          )
        )
        .font(.system(size: 20, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.routeWhite)
      }

      Spacer()

      if !runtime.isRealRoadAuthority {
        Text(
          copy.resolve(
            japanese: "演習",
            simplifiedChinese: "演练",
            english: "DEMO"
          )
        )
        .font(.system(size: 8, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.signalAmber)
        .padding(.horizontal, 9)
        .frame(height: 26)
        .overlay {
          Capsule()
            .stroke(KaidoTheme.signalAmber.opacity(0.6), lineWidth: 1)
        }
      }

      Button {
        showsFinishConfirmation = true
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 13, weight: .black))
          .frame(width: 38, height: 38)
          .foregroundStyle(KaidoTheme.routeWhite)
          .background(KaidoTheme.instrument)
          .clipShape(Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        copy.resolve(
          japanese: "演習を終了",
          simplifiedChinese: "结束演练",
          english: "End rehearsal"
        )
      )
      .accessibilityIdentifier("product-drive-finish")
    }
  }

  @ViewBuilder
  private var guidance: some View {
    if let projection = runtime.presentationProjection {
      let phone = projection.iPhone
      HStack(alignment: .top, spacing: 12) {
        Text(phone.routeShields.first ?? "—")
          .font(.system(size: 18, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.asphalt)
          .frame(width: 48, height: 48)
          .background(KaidoTheme.signalAmber)
          .clipShape(RoundedRectangle(cornerRadius: 10))

        VStack(alignment: .leading, spacing: 4) {
          Text(distanceLabel(phone.distanceMeters))
            .font(.system(size: 21, weight: .black, design: .rounded))
            .foregroundStyle(KaidoTheme.routeWhite)

          Text(phone.localizedDecisionPointName)
            .font(.system(size: 16, weight: .black, design: .rounded))
            .foregroundStyle(KaidoTheme.routeWhite)

          Text(verbatim: phone.japaneseSignText)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(KaidoTheme.muted)
        }

        Spacer()

        Image(systemName: maneuverSymbol(phone.maneuver))
          .font(.system(size: 21, weight: .black))
          .foregroundStyle(KaidoTheme.signalAmber)
      }
      .padding(14)
      .background(KaidoTheme.instrument)
      .clipShape(RoundedRectangle(cornerRadius: 16))
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("product-drive-guidance")
    } else {
      HStack(spacing: 12) {
        Image(systemName: "arrow.up")
          .font(.system(size: 21, weight: .black))
          .foregroundStyle(KaidoTheme.signalAmber)
          .frame(width: 44)

        VStack(alignment: .leading, spacing: 3) {
          Text(
            copy.resolve(
              japanese: "経路に沿って進みます",
              simplifiedChinese: "沿所选路线前进",
              english: "Follow the selected route"
            )
          )
          .font(.system(size: 16, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)

          Text(
            copy.resolve(
              japanese: "次の分岐は位置確認後に表示",
              simplifiedChinese: "确认位置后显示下一分岔",
              english: "The next decision appears after position resolves"
            )
          )
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(KaidoTheme.muted)
        }
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(KaidoTheme.instrument)
      .clipShape(RoundedRectangle(cornerRadius: 16))
      .accessibilityIdentifier("product-drive-guidance-pending")
    }
  }

  private var routeProgress: some View {
    let currentIndex = runtime.snapshot?.currentOccurrenceIndex
    let current =
      currentIndex.map { min(runtime.routeOccurrenceCount, $0 + 1) } ?? 0
    return VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(
          copy.resolve(
            japanese: "経路進行",
            simplifiedChinese: "路线进度",
            english: "Route progress"
          )
        )
        .font(.system(size: 10, weight: .black))
        .foregroundStyle(KaidoTheme.routeWhite)

        Spacer()

        Text("\(current) / \(runtime.routeOccurrenceCount)")
          .font(.system(size: 10, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.muted)
      }

      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule()
            .fill(KaidoTheme.steel)
          Capsule()
            .fill(KaidoTheme.signalAmber)
            .frame(
              width:
                proxy.size.width
                * progressFraction(
                  current: current,
                  total: runtime.routeOccurrenceCount
                )
            )
        }
      }
      .frame(height: 5)
    }
    .padding(12)
    .background(KaidoTheme.instrument)
    .clipShape(RoundedRectangle(cornerRadius: 13))
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("product-drive-progress")
    .accessibilityValue("\(current) of \(runtime.routeOccurrenceCount)")
  }

  private var liveLocationControl: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label(
          copy.resolve(
            japanese: "前景位置情報",
            simplifiedChinese: "前台定位",
            english: "Foreground location"
          ),
          systemImage: "location.fill"
        )
        .font(.system(size: 10, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.routeWhite)

        Spacer()

        Text(locationController.state.label)
          .font(.system(size: 8, weight: .black, design: .monospaced))
          .foregroundStyle(
            locationController.state == .running
              ? KaidoTheme.positionCyan
              : KaidoTheme.muted
          )
          .accessibilityIdentifier("product-drive-location-state")
          .accessibilityValue(locationController.state.label)
      }

      Text(locationStateDetail)
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(KaidoTheme.muted)
        .fixedSize(horizontal: false, vertical: true)

      Button {
        if locationController.canStop {
          Task {
            await locationController.stop()
          }
        } else {
          locationController.start()
        }
      } label: {
        Label(
          locationController.canStop
            ? copy.resolve(
              japanese: "前景位置情報を停止",
              simplifiedChinese: "停止前台定位",
              english: "Stop foreground location"
            )
            : copy.resolve(
              japanese: "前景位置情報を開始",
              simplifiedChinese: "启动前台定位",
              english: "Start foreground location"
            ),
          systemImage:
            locationController.canStop
            ? "location.slash.fill"
            : "location.fill"
        )
        .font(.system(size: 12, weight: .black, design: .rounded))
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .foregroundStyle(
          locationActionAvailable
            ? KaidoTheme.asphalt
            : KaidoTheme.muted
        )
        .background(
          locationActionAvailable
            ? KaidoTheme.signalAmber
            : KaidoTheme.steel.opacity(0.38)
        )
      }
      .buttonStyle(.plain)
      .disabled(!locationActionAvailable)
      .accessibilityIdentifier("product-drive-location-action")
      .accessibilityValue(
        locationController.canStop
          ? "STOPPABLE"
          : (locationController.canStart ? "AVAILABLE" : "BLOCKED")
      )
    }
    .padding(12)
    .background(KaidoTheme.instrument)
    .clipShape(RoundedRectangle(cornerRadius: 13))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("product-drive-live-location")
  }

  @ViewBuilder
  private var rehearsalControls: some View {
    if !runtime.isRealRoadAuthority {
      VStack(spacing: 9) {
        if runtime.canRunDeterministicPreviewTrace {
          Button {
            isStartingRehearsal = true
            Task {
              await runtime.runDeterministicPreviewTrace()
              isStartingRehearsal = false
            }
          } label: {
            Label(
              copy.resolve(
                japanese: "走行演習を開始",
                simplifiedChinese: "开始行驶演练",
                english: "Start driving rehearsal"
              ),
              systemImage: "play.fill"
            )
            .font(.system(size: 13, weight: .black, design: .rounded))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(KaidoTheme.asphalt)
            .background(KaidoTheme.signalAmber)
          }
          .buttonStyle(.plain)
          .disabled(isStartingRehearsal)
          .accessibilityIdentifier("product-drive-start-rehearsal")
        } else if runtime.canStepNavigationSimulation {
          Button {
            Task {
              await runtime.stepNavigationSimulation()
            }
          } label: {
            Label(
              copy.resolve(
                japanese: "次の区間へ",
                simplifiedChinese: "前往下一段",
                english: "Advance one segment"
              ),
              systemImage: "forward.frame.fill"
            )
            .font(.system(size: 12, weight: .black, design: .rounded))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .foregroundStyle(KaidoTheme.routeWhite)
            .background(KaidoTheme.routeGreenDeep)
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("product-drive-next-segment")
        }

        Text(
          copy.resolve(
            japanese: "演習データを使用しています",
            simplifiedChinese: "当前使用演练数据",
            english: "This drive uses rehearsal data"
          )
        )
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(KaidoTheme.muted)
      }
    }
  }

  private func distanceLabel(_ meters: Double) -> String {
    if meters >= 1_000 {
      return String(format: "%.1f km", meters / 1_000)
    }
    return "\(Int(meters.rounded())) m"
  }

  private func maneuverSymbol(_ maneuver: GuidanceManeuver) -> String {
    switch maneuver {
    case .keepLeft:
      "arrow.up.left"
    case .keepRight:
      "arrow.up.right"
    case .takeExitLeft, .mergeLeft:
      "arrow.turn.up.left"
    case .takeExitRight, .mergeRight:
      "arrow.turn.up.right"
    case .stayMainline:
      "arrow.up"
    }
  }

  private func progressFraction(
    current: Int,
    total: Int
  ) -> Double {
    guard total > 0 else { return 0 }
    return min(1, max(0, Double(current) / Double(total)))
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }

  private var locationActionAvailable: Bool {
    locationController.canStart || locationController.canStop
  }

  private var locationStateDetail: String {
    switch locationController.state {
    case .idle, .stopped:
      copy.resolve(
        japanese: "明示的に開始するまで位置情報は接続されません。",
        simplifiedChinese: "只有明确启动后才会连接定位。",
        english: "Location remains disconnected until you explicitly start it."
      )
    case .awaitingAuthorization:
      copy.resolve(
        japanese: "使用中の位置情報許可を待っています。",
        simplifiedChinese: "正在等待使用期间定位授权。",
        english: "Waiting for When In Use location authorization."
      )
    case .running:
      copy.resolve(
        japanese:
          "前景更新はリリースに固定された actor に送られます。バックグラウンド位置情報は無効です。",
        simplifiedChinese:
          "前台更新会送入 release-bound actor；后台定位保持禁用。",
        english:
          "Foreground updates feed the release-bound actor; background location remains disabled."
      )
    case .sceneInactive:
      copy.resolve(
        japanese: "画面が非アクティブになったため位置情報を停止しました。",
        simplifiedChinese: "界面进入非活动状态，定位已停止。",
        english: "Location stopped because the scene became inactive."
      )
    case .permissionDenied:
      copy.resolve(
        japanese: "位置情報が拒否または制限されています。",
        simplifiedChinese: "定位权限被拒绝或受限。",
        english: "Location permission is denied or restricted."
      )
    case .releaseBlocked(let reason):
      reason.rawValue
    case .runtimeUnavailable:
      copy.resolve(
        japanese: "ナビゲーション actor の準備を待っています。",
        simplifiedChinese: "正在等待导航 actor 就绪。",
        english: "Waiting for the navigation actor to become ready."
      )
    case .failed(let code):
      code
    }
  }

  private func handleScenePhase(
    _ phase: ProductNavigationRuntimeScenePhase
  ) async {
    switch phase {
    case .active:
      await runtime.handleScenePhase(phase)
      await locationController.handleScenePhase(phase)
      locationController.refreshRuntimeAvailability()
    case .inactive, .background:
      await locationController.handleScenePhase(phase)
      await runtime.handleScenePhase(phase)
    }
  }
}

private struct ProductSavedRoutesSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale
  @ObservedObject var model: SavedRouteLibraryModel
  let openRoute: (String) -> Void

  var body: some View {
    NavigationStack {
      Group {
        if model.records.isEmpty {
          ContentUnavailableView(
            copy.resolve(
              japanese: "保存ルートはありません",
              simplifiedChinese: "还没有保存路线",
              english: "No saved routes"
            ),
            systemImage: "bookmark",
            description: Text(
              copy.resolve(
                japanese: "設計した経路を保存すると、ここに表示されます。",
                simplifiedChinese: "保存设计好的路线后，会显示在这里。",
                english: "Routes you save after planning appear here."
              )
            )
          )
        } else {
          List(model.records, id: \.id) { record in
            VStack(alignment: .leading, spacing: 5) {
              Text(record.displayName)
                .font(.headline)
              Text(
                copy.resolve(
                  japanese: "走行前に現在のリリース確認が必要です",
                  simplifiedChinese: "行驶前需要重新确认当前版本",
                  english: "Current release review is required before driving"
                )
              )
              .font(.caption)
              .foregroundStyle(.secondary)

              Button {
                openRoute(record.id)
              } label: {
                Text(
                  copy.resolve(
                    japanese: "停車中の編集で開く",
                    simplifiedChinese: "在停车编辑器中打开",
                    english: "Open in parked editor"
                  )
                )
              }
              .disabled(
                !isSelectable(record)
              )
            }
          }
        }
      }
      .navigationTitle(
        copy.resolve(
          japanese: "保存ルート",
          simplifiedChinese: "我的路线",
          english: "Saved routes"
        )
      )
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(
            copy.resolve(
              japanese: "完了",
              simplifiedChinese: "完成",
              english: "Done"
            )
          ) {
            dismiss()
          }
        }
      }
    }
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }

  private func isSelectable(_ record: SavedRouteRecord) -> Bool {
    if case .selected = model.availability(for: record) {
      return true
    }
    return false
  }
}

private struct ProductSettingsSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale
  @ObservedObject var model: KaidoLanguageSettingsModel

  var body: some View {
    NavigationStack {
      Form {
        Section(
          copy.resolve(
            japanese: "画面",
            simplifiedChinese: "界面",
            english: "Interface"
          )
        ) {
          KaidoInterfaceLanguagePicker(model: model)
        }

        Section(
          copy.resolve(
            japanese: "案内音声",
            simplifiedChinese: "引导语音",
            english: "Guidance voice"
          )
        ) {
          ForEach(KaidoReleaseLocale.allCases, id: \.self) { locale in
            Button {
              model.selectGuidanceVoiceLocale(locale)
            } label: {
              HStack {
                Text(locale.nativeLanguageName)
                Spacer()
                if model.guidanceVoiceLocale == locale {
                  Image(systemName: "checkmark")
                }
              }
            }
            .accessibilityAddTraits(
              model.guidanceVoiceLocale == locale ? .isSelected : []
            )
            .accessibilityIdentifier(
              "product-settings-guidance-voice-\(locale.rawValue)"
            )
          }
        }

        Section(
          copy.resolve(
            japanese: "プライバシーとデータ",
            simplifiedChinese: "隐私与数据",
            english: "Privacy & data"
          )
        ) {
          Label {
            VStack(alignment: .leading, spacing: 3) {
              Text(
                copy.resolve(
                  japanese: "位置情報はこのデバイス内で処理されます",
                  simplifiedChinese: "位置信息仅在此设备上处理",
                  english: "Location is processed on this device"
                )
              )
              .font(.body)

              Text(
                copy.resolve(
                  japanese:
                    "明示的にナビを開始した後だけ使用し、経路進捗をサーバーへ送信しません。",
                  simplifiedChinese:
                    "仅在你明确开始导航后使用，路线进度不会发送到服务器。",
                  english:
                    "Used only after you explicitly start navigation; route progress is not sent to a server."
                )
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }
          } icon: {
            Image(systemName: "location.shield")
          }
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier("product-settings-location-privacy")

          Link(destination: ProductPrivacyDisclosure.policyURL) {
            Label(
              copy.resolve(
                japanese: "プライバシーポリシー",
                simplifiedChinese: "隐私政策",
                english: "Privacy policy"
              ),
              systemImage: "hand.raised"
            )
          }
          .accessibilityIdentifier("product-settings-privacy-policy")
        }

        Section(
          copy.resolve(
            japanese: "このアプリについて",
            simplifiedChinese: "关于",
            english: "About"
          )
        ) {
          LabeledContent(
            copy.resolve(
              japanese: "バージョン",
              simplifiedChinese: "版本",
              english: "Version"
            ),
            value: ProductPrivacyDisclosure.versionDescription()
          )
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier("product-settings-version")
          .accessibilityValue(
            ProductPrivacyDisclosure.versionDescription()
          )
        }
      }
      .accessibilityIdentifier("product-settings")
      .navigationTitle(
        copy.resolve(
          japanese: "設定",
          simplifiedChinese: "设置",
          english: "Settings"
        )
      )
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(
            copy.resolve(
              japanese: "完了",
              simplifiedChinese: "完成",
              english: "Done"
            )
          ) {
            dismiss()
          }
        }
      }
    }
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }
}

struct ReviewBoundaryCard: View {
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
