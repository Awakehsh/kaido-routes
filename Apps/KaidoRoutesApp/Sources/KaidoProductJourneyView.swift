import KaidoDomain
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
          KaidoInterfaceLanguagePicker(
            model: model.composition.languageSettings
          )
          .frame(maxWidth: .infinity, alignment: .trailing)
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
      if model.stage != .navigation {
        actionDock
      }
    }
    .environment(\.kaidoInterfaceLocale, interfaceLocale)
    .preferredColorScheme(.dark)
  }

  private var journeyHeader: some View {
    HStack(alignment: .top, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("KAIDO ROUTES")
          .font(.system(size: 24, weight: .black, design: .rounded))
          .tracking(-0.8)
          .foregroundStyle(KaidoTheme.routeWhite)

        Text(
          copy.resolve(
            japanese: "道を選んでから、出発。",
            simplifiedChinese: "先选路，再出发。",
            english: "Choose the route, then drive."
          )
        )
        .font(.system(size: 17, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.signalAmber)

        Text(
          copy.resolve(
            japanese: "首都高速 · ルートファーストナビゲーション",
            simplifiedChinese: "首都高速 · 路线优先导航",
            english: "SHUTO EXPRESSWAY · ROUTE-FIRST NAVIGATION"
          )
        )
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
    .accessibilityIdentifier("product-journey-header")
    .accessibilityLabel(
      copy.resolve(
        japanese:
          "Kaido Routes。道を選んでから出発。現在のステップは\(stageTitle(model.stage))です。",
        simplifiedChinese:
          "Kaido Routes。先选路，再出发。当前步骤\(stageTitle(model.stage))。",
        english:
          "Kaido Routes. Choose the route, then drive. Current step: \(stageTitle(model.stage))."
      )
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
      navigationStage
        .transition(stageTransition)
    }
  }

  private var atlasStage: some View {
    VStack(spacing: 14) {
      stageIntroduction(
        eyebrow: copy.resolve(
          japanese: "01 · 道路を選ぶ",
          simplifiedChinese: "01 · 选择道路",
          english: "01 · CHOOSE THE ROAD"
        ),
        title: copy.resolve(
          japanese: "道路を知り、経路を組み立てる",
          simplifiedChinese: "先认识道路，再设计路线",
          english: "Recognize the road before authoring the route"
        ),
        detail: copy.resolve(
          japanese:
            "全体図は道路の識別だけに使います。リリース審査を通った有向トポロジーだけが経路に参加できます。",
          simplifiedChinese:
            "全网图只帮助识别；只有经过发布门的有向拓扑才能参与路线。",
          english:
            "The network atlas is for recognition only; only release-gated directed topology may enter a route."
        )
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
        title:
          model.composition.releasedRouteAuthoring == nil
          ? copy.resolve(
            japanese: "現在は合成ルートカタログを使用中",
            simplifiedChinese: "当前使用合成路线目录",
            english: "Synthetic route catalog in use"
          )
          : copy.resolve(
            japanese: "実道路リリースカタログを検証済み",
            simplifiedChinese: "真实道路发布目录已验证",
            english: "Real-road release catalog validated"
          ),
        detail:
          model.composition.releasedRouteAuthoring == nil
          ? copy.resolve(
            japanese:
              "マニフェストのハッシュと本番 codec は検証済みですが、実道路のリリースがないためナビ権限はありません。",
            simplifiedChinese:
              "清单哈希与生产 codec 已验证；没有真实道路发布包，不会获得导航权限。",
            english:
              "The manifest hash and production codec are validated; without a real-road release, navigation authority stays unavailable."
          )
          : copy.resolve(
            japanese:
              "次のステップでは選択したリリース自身の編集レシピと表示文だけを使用します。",
            simplifiedChinese:
              "下一步只使用所选发布包自身的编辑配方与显示文案。",
            english:
              "The next step uses only the selected release's own authoring recipe and presentation."
          ),
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

      SavedRouteLibraryPanel(
        model: model.composition.savedRouteLibrary,
        openRecord: { recordID in
          withAnimation(stageAnimation) {
            model.openSavedRoute(recordID)
          }
        }
      )
    }
  }

  private var authoringStage: some View {
    VStack(spacing: 14) {
      stageIntroduction(
        eyebrow: copy.resolve(
          japanese: "02 · 経路を作る",
          simplifiedChinese: "02 · 编排路线",
          english: "02 · AUTHOR THE ROUTE"
        ),
        title: copy.resolve(
          japanese: "選んだ順序のまま経路を保持",
          simplifiedChinese: "路线按选择顺序保留",
          english: "Preserve the route in authored order"
        ),
        detail: copy.resolve(
          japanese:
            "分岐、重複区間、明示した出口はすべて editor session が記録します。",
          simplifiedChinese:
            "每次分岔、重复路段和明确出口都由 editor session 记录。",
          english:
            "The editor session records every decision, repeated segment, and explicit exit."
        )
      )

      if let releasedRouteAuthoring =
        model.composition.releasedRouteAuthoring
      {
        ReleasedProductRouteAuthoringPanel(
          model: releasedRouteAuthoring
        )
      } else {
        EntranceRecommendationPanel(
          model: model.composition.entranceRecommendation
        )

        ParkedRouteEditorPanel(model: model.composition.routeEditor)
      }

      ReleasedRouteAtlasOverlayContainer(
        presentation: model.routeAtlasOverlayPresentation
      )

      if model.routeReviewReady {
        ReviewBoundaryCard(
          symbol: "checkmark.seal.fill",
          title: copy.resolve(
            japanese: "出発前確認へ進めます",
            simplifiedChinese: "路线已可进入行前确认",
            english: "Route ready for pre-drive review"
          ),
          detail: copy.resolve(
            japanese:
              "コンパイル結果は全 occurrence を保持します。次のステップはこの経路だけを読み取ります。",
            simplifiedChinese:
              "编译结果保留全部 occurrence；下一步只读取这条路线。",
            english:
              "The compiled result preserves every occurrence; the next step reads only this route."
          ),
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
        eyebrow: copy.resolve(
          japanese: "03 · 出発前に確認",
          simplifiedChinese: "03 · 行前确认",
          english: "03 · REVIEW BEFORE DRIVING"
        ),
        title: copy.resolve(
          japanese: "経路・料金根拠・通行状態を確認",
          simplifiedChinese: "确认路线、费用证据与通行状态",
          english: "Review route, toll evidence, and passage state"
        ),
        detail: copy.resolve(
          japanese:
            "実走予定距離と料金計算距離は別々に表示します。未確認のリアルタイム状態を通行可とは表示しません。",
          simplifiedChinese:
            "实际规划距离与计费距离分开；未确认实时状态不会显示为畅通。",
          english:
            "Planned distance stays separate from tariff distance; unconfirmed realtime state is never shown as open."
        )
      )

      if let releasedRouteAuthoring =
        model.composition.releasedRouteAuthoring
      {
        PreDriveReviewPanel(
          model: model.composition.preDriveReview,
          navigationStartAvailable: model.canStartNavigation,
          displayScope: .released,
          releasedSnapshot:
            releasedRouteAuthoring.preDriveReviewSnapshot,
          releasedErrorCode: releasedRouteAuthoring.lastErrorCode
        )
      } else {
        PreDriveReviewPanel(
          model: model.composition.preDriveReview,
          navigationStartAvailable: model.canStartNavigation
        )
      }

      ReleasedRouteAtlasOverlayContainer(
        presentation: model.routeAtlasOverlayPresentation
      )

      SavedRouteSavePanel(
        library: model.composition.savedRouteLibrary,
        routePlan: model.compiledRoutePlan,
        save: {
          model.saveCompiledRoute(named: $0)
        }
      )

      GuidanceVoiceSetupPanel(
        model: model.composition.guidanceVoiceSetup,
        isParked: model.composition.safety.isParkedInteractionContext
      )

      Group {
        if model.canStartNavigation {
          ReviewBoundaryCard(
            symbol: "key.horizontal.fill",
            title: copy.resolve(
              japanese: "リリース ID を固定済み。ユーザー開始待ち",
              simplifiedChinese: "发布身份已绑定，等待用户启动",
              english: "Release identity bound; waiting for user start"
            ),
            detail: copy.resolve(
              japanese:
                "次はこの統合リリースだけから actor を作成します。リアルタイム位置情報はナビ画面で別途開始します。",
              simplifiedChinese:
                "下一步只从这份联合发布包创建 actor；实时定位仍需进入导航页后单独启动。",
              english:
                "The actor will be created only from this joint release; foreground location still requires a separate action in navigation."
            ),
            code: "RELEASE KEY · READY",
            color: KaidoTheme.positionCyan
          )
        } else {
          ReviewBoundaryCard(
            symbol: "lock.shield.fill",
            title: copy.resolve(
              japanese: "実道路ナビはリリース審査で停止中",
              simplifiedChinese: "真实导航仍被发布门阻止",
              english: "Real navigation remains release-gated"
            ),
            detail: copy.resolve(
              japanese:
                "このデモ経路には RELEASED_ROAD 権限、前景ライブ入力トークン、実地適格性証拠がありません。",
              simplifiedChinese:
                "这条演示路线没有 RELEASED_ROAD 权限、前台实时输入令牌和现场资格证据。",
              english:
                "This demo route has no RELEASED_ROAD authority, foreground live-input token, or field qualification evidence."
            ),
            code: model.navigationBlocker?.rawValue ?? "NAVIGATION BLOCKED",
            color: KaidoTheme.evidenceCoral
          )
        }
      }
      .accessibilityIdentifier("product-journey-navigation-blocker")
      .accessibilityValue(
        model.canStartNavigation
          ? "RELEASE_KEY_READY"
          : model.navigationBlocker?.rawValue ?? "NAVIGATION BLOCKED"
      )
    }
  }

  @ViewBuilder
  private var navigationStage: some View {
    if let navigationRuntime = model.navigationRuntime {
      ReleasedProductNavigationPanel(
        model: navigationRuntime,
        endNavigation: {
          await model.endNavigation()
        }
      )
    } else {
      ReviewBoundaryCard(
        symbol: "exclamationmark.shield.fill",
        title: copy.resolve(
          japanese: "ナビランタイムを利用できません",
          simplifiedChinese: "导航运行时不可用",
          english: "Navigation runtime unavailable"
        ),
        detail: copy.resolve(
          japanese:
            "現在の統合リリースに対応する actor がないため、ナビ画面は閉じたままです。",
          simplifiedChinese: "缺少当前联合发布包的 actor，导航页保持关闭。",
          english:
            "The actor for the current joint release is missing, so navigation remains closed."
        ),
        code: KaidoProductJourneyBlocker.navigationRuntimeUnavailable.rawValue,
        color: KaidoTheme.evidenceCoral
      )
    }
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
            Text(mode.label(for: interfaceLocale))
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
          .accessibilityLabel(
            copy.resolve(
              japanese: "\(previousStageTitle)に戻る",
              simplifiedChinese: "返回\(previousStageTitle)",
              english: "Back to \(previousStageTitle)"
            )
          )
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
      copy.resolve(
        japanese: "経路作成を始める",
        simplifiedChinese: "开始设计路线",
        english: "Start authoring the route"
      )
    case .authoring:
      copy.resolve(
        japanese: "出発前確認へ",
        simplifiedChinese: "进入行前确认",
        english: "Continue to pre-drive review"
      )
    case .review:
      model.canStartNavigation
        ? copy.resolve(
          japanese: "ルートナビを開始",
          simplifiedChinese: "开始路线导航",
          english: "Start route navigation"
        )
        : copy.resolve(
          japanese: "ナビは未リリース",
          simplifiedChinese: "导航尚未发布",
          english: "Navigation not released"
        )
    case .navigation:
      copy.resolve(
        japanese: "ナビ実行中",
        simplifiedChinese: "导航运行中",
        english: "Navigation active"
      )
    }
  }

  private var primaryActionSymbol: String {
    switch model.stage {
    case .atlas:
      "point.topleft.down.to.point.bottomright.curvepath"
    case .authoring:
      "checklist.checked"
    case .review:
      model.canStartNavigation ? "key.horizontal.fill" : "lock.fill"
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
      model.canStartNavigation ? "START" : "BLOCKED"
    case .navigation:
      "ACTIVE"
    }
  }

  private var actionGuidance: String? {
    switch model.stage {
    case .atlas:
      copy.resolve(
        japanese: "アトラスは道路識別用です。次は停車中の経路編集へ進みます。",
        simplifiedChinese: "路线图用于识别；下一步进入停车编辑。",
        english:
          "The atlas is for road recognition; next, author the route while parked."
      )
    case .authoring where !model.routeReviewReady:
      copy.resolve(
        japanese: "明示する出口を選び、経路をコンパイルしてください。",
        simplifiedChinese: "先选择明确出口，再编译路线。",
        english: "Choose an explicit exit, then compile the route."
      )
    case .authoring:
      copy.resolve(
        japanese: "経路をコンパイル済みです。距離・料金・通行根拠を確認できます。",
        simplifiedChinese: "路线已编译，可以核对距离、费用与通行证据。",
        english:
          "The route is compiled; distance, toll, and passage evidence are ready for review."
      )
    case .review:
      model.canStartNavigation
        ? copy.resolve(
          japanese:
            "リリースを固定済みです。actor 開始後も前景位置情報は別途開始します。",
          simplifiedChinese:
            "发布包已绑定；启动 actor 后仍需单独开启前台定位。",
          english:
            "The release is bound; foreground location still requires a separate action after actor startup."
        )
        : copy.resolve(
          japanese:
            "実道路の統合リリースと実地適格性証拠がそろうまでナビは開始できません。",
          simplifiedChinese:
            "需要真实联合发布包和现场资格证据后才能开始导航。",
          english:
            "A real joint release and field qualification evidence are required before navigation can start."
        )
    case .navigation:
      nil
    }
  }

  private var previousStageTitle: String {
    switch model.stage {
    case .atlas, .authoring:
      stageTitle(.atlas)
    case .review:
      copy.resolve(
        japanese: "経路編集",
        simplifiedChinese: "路线编辑",
        english: "Route authoring"
      )
    case .navigation:
      stageTitle(.review)
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
    if stage == .navigation, model.canStartNavigation {
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
      copy.resolve(
        japanese: "道路",
        simplifiedChinese: "选路",
        english: "ATLAS"
      )
    case .authoring:
      copy.resolve(
        japanese: "作成",
        simplifiedChinese: "编辑",
        english: "EDIT"
      )
    case .review:
      copy.resolve(
        japanese: "確認",
        simplifiedChinese: "确认",
        english: "REVIEW"
      )
    case .navigation:
      copy.resolve(
        japanese: "ナビ",
        simplifiedChinese: "导航",
        english: "DRIVE"
      )
    }
  }

  private func stageTitle(_ stage: KaidoProductJourneyStage) -> String {
    switch stage {
    case .atlas:
      copy.resolve(
        japanese: "ルートアトラス",
        simplifiedChinese: "路线图",
        english: "Route Atlas"
      )
    case .authoring:
      copy.resolve(
        japanese: "停車中の経路作成",
        simplifiedChinese: "停车编辑",
        english: "Parked authoring"
      )
    case .review:
      copy.resolve(
        japanese: "出発前確認",
        simplifiedChinese: "行前确认",
        english: "Pre-drive review"
      )
    case .navigation:
      copy.resolve(
        japanese: "ルートナビ",
        simplifiedChinese: "路线导航",
        english: "Route navigation"
      )
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

  private var interfaceLocale: KaidoReleaseLocale {
    model.composition.languageSettings.interfaceLocale
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
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
