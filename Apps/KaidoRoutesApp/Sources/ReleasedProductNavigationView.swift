import SwiftUI

struct ReleasedProductNavigationPanel: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale
  @Environment(\.scenePhase) private var scenePhase
  @ObservedObject var model: ProductNavigationRuntimeModel
  @ObservedObject private var locationController: ForegroundNavigationLocationController

  let endNavigation: () async -> Void

  init(
    model: ProductNavigationRuntimeModel,
    endNavigation: @escaping () async -> Void
  ) {
    self.model = model
    self.endNavigation = endNavigation
    locationController = model.foregroundNavigationLocationController
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header
      releaseKey
      ReleasedRouteAtlasOverlayContainer(
        presentation: model.routeAtlasOverlayPresentation
      )
      interlockArrow
      liveInput
      actorProjection
      realtimeBoundary
      endControl
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("released-product-navigation")
    .task {
      await model.activate()
      locationController.refreshRuntimeAvailability()
    }
    .onChange(of: scenePhase, initial: true) { _, newPhase in
      Task {
        await handleScenePhase(newPhase.productRuntimePhase)
      }
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(
          copy.resolve(
            japanese: "ルートナビ",
            simplifiedChinese: "路线导航",
            english: "Route navigation"
          )
        )
        .font(.system(size: 23, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.routeWhite)

        Text("RELEASE-BOUND · USER STARTED")
          .font(.system(size: 9, weight: .black, design: .monospaced))
          .tracking(0.7)
          .foregroundStyle(KaidoTheme.signalAmber)
      }

      Spacer()

      StatusCapsule(
        title: activationLabel,
        color: activationColor
      )
      .accessibilityIdentifier("released-runtime-activation")
      .accessibilityValue(activationLabel)
    }
  }

  private var releaseKey: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label("RELEASE KEY", systemImage: "key.horizontal.fill")
          .font(.system(size: 10, weight: .black, design: .monospaced))
          .tracking(0.45)
          .foregroundStyle(KaidoTheme.positionCyan)

        Spacer()

        Text(model.isRealRoadAuthority ? "BOUND" : "BLOCKED")
          .font(.system(size: 9, weight: .black, design: .monospaced))
          .foregroundStyle(
            model.isRealRoadAuthority
              ? KaidoTheme.positionCyan
              : KaidoTheme.evidenceCoral
          )
      }

      identityRow("PRODUCT", value: model.productReleaseID)
      identityRow("NAVIGATION", value: model.navigationReleaseID)
      identityRow("ROUTE PLAN", value: model.routePlanID)
      identityRow("SNAPSHOT", value: model.networkSnapshotID)
    }
    .padding(14)
    .background(KaidoTheme.instrument)
    .clipShape(RoundedRectangle(cornerRadius: 18))
    .overlay {
      RoundedRectangle(cornerRadius: 18)
        .stroke(KaidoTheme.positionCyan.opacity(0.48), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("released-runtime-key")
    .accessibilityValue(
      model.isRealRoadAuthority ? "RELEASED_ROAD_BOUND" : "BLOCKED"
    )
  }

  private var interlockArrow: some View {
    HStack(spacing: 8) {
      Rectangle()
        .fill(KaidoTheme.steel)
        .frame(height: 1)

      Image(systemName: "arrow.down")
        .font(.system(size: 10, weight: .black))
        .foregroundStyle(KaidoTheme.signalAmber)

      Text(
        copy.resolve(
          japanese: "位置情報はユーザーが明示的に開始した後だけ接続",
          simplifiedChinese: "用户明确启动后才连接定位",
          english: "Location connects only after explicit user start"
        )
      )
      .font(.system(size: 9, weight: .bold))
      .foregroundStyle(KaidoTheme.muted)

      Rectangle()
        .fill(KaidoTheme.steel)
        .frame(height: 1)
    }
    .accessibilityHidden(true)
  }

  private var liveInput: some View {
    VStack(alignment: .leading, spacing: 11) {
      HStack(alignment: .firstTextBaseline) {
        Label("LIVE INPUT", systemImage: "location.fill")
          .font(.system(size: 10, weight: .black, design: .monospaced))
          .tracking(0.45)
          .foregroundStyle(KaidoTheme.signalAmber)

        Spacer()

        Text(locationStateLabel)
          .font(.system(size: 8, weight: .black, design: .monospaced))
          .foregroundStyle(locationColor)
      }

      Text(locationStateDetail)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(KaidoTheme.muted)
        .fixedSize(horizontal: false, vertical: true)

      HStack {
        runtimeMetric(
          title: copy.resolve(
            japanese: "許可",
            simplifiedChinese: "授权",
            english: "AUTHORIZATION"
          ),
          value: locationController.authorizationLabel
        )
        runtimeMetric(
          title: copy.resolve(
            japanese: "精度",
            simplifiedChinese: "精度",
            english: "ACCURACY"
          ),
          value: locationController.accuracyAuthorizationLabel
        )
      }

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
        .font(.system(size: 14, weight: .black, design: .rounded))
        .frame(maxWidth: .infinity)
        .frame(height: 46)
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
        .clipShape(RoundedRectangle(cornerRadius: 12))
      }
      .buttonStyle(.plain)
      .disabled(!locationActionAvailable)
      .accessibilityIdentifier("released-runtime-location-action")
      .accessibilityValue(
        locationActionAvailable ? "AVAILABLE" : "BLOCKED"
      )
    }
    .padding(14)
    .background(KaidoTheme.instrument)
    .clipShape(RoundedRectangle(cornerRadius: 18))
    .overlay {
      RoundedRectangle(cornerRadius: 18)
        .stroke(KaidoTheme.signalAmber.opacity(0.42), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("released-runtime-live-input")
    .accessibilityValue(locationStateLabel)
  }

  @ViewBuilder
  private var actorProjection: some View {
    if let projection = model.presentationProjection {
      ProductRuntimeDrivingSurface(projection: projection)
    } else {
      ReviewBoundaryCard(
        symbol: "scope",
        title: copy.resolve(
          japanese: "リリースに固定された actor の証拠を待機",
          simplifiedChinese: "等待 release-bound actor 证据",
          english: "Waiting for release-bound actor evidence"
        ),
        detail: copy.resolve(
          japanese:
            "位置が厳密経路に入っていないか、有効な guidance frame がまだありません。画面は現在地や次の分岐を推測しません。",
          simplifiedChinese:
            "定位未进入严格路线，或尚未产生有效 guidance frame；界面不会猜测当前位置或下一分岔。",
          english:
            "Location has not entered the strict route or no valid guidance frame exists; the UI will not guess position or the next decision."
        ),
        code: model.presentationState.label,
        color: KaidoTheme.positionCyan
      )
      .accessibilityIdentifier("released-runtime-projection-waiting")
      .accessibilityValue(model.presentationState.label)
    }
  }

  private var realtimeBoundary: some View {
    ReviewBoundaryCard(
      symbol: "wave.3.right.circle.fill",
      title: copy.resolve(
        japanese: "リアルタイム通行状態は未確認",
        simplifiedChinese: "实时通行状态尚未确认",
        english: "Realtime passage state unconfirmed"
      ),
      detail: copy.resolve(
        japanese:
          "静的なリリース ID とリアルタイムの通行可否は分離されています。証拠がなければ通行可とは表示しません。",
        simplifiedChinese:
          "静态发布身份和实时开放状态保持分离；缺少实时证据不会显示为畅通。",
        english:
          "Static release identity stays separate from realtime openness; missing realtime evidence is never shown as open."
      ),
      code: "REALTIME_UNCONFIRMED",
      color: KaidoTheme.evidenceCoral
    )
    .accessibilityIdentifier("released-runtime-realtime")
    .accessibilityValue("REALTIME_UNCONFIRMED")
  }

  private var endControl: some View {
    Button {
      Task {
        await endNavigation()
      }
    } label: {
      Label(
        endNavigationLabel,
        systemImage:
          model.snapshot?.journeyPhase == .exitTransition
          ? "checkmark.circle.fill"
          : "xmark.circle.fill"
      )
      .font(.system(size: 13, weight: .black, design: .rounded))
      .frame(maxWidth: .infinity)
      .frame(height: 44)
      .foregroundStyle(KaidoTheme.routeWhite)
      .background(KaidoTheme.steel.opacity(0.62))
      .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("released-runtime-end")
  }

  private var endNavigationLabel: String {
    if model.snapshot?.journeyPhase == .exitTransition {
      return copy.resolve(
        japanese: "出口引き継ぎ地点で完了",
        simplifiedChinese: "在出口交接点完成",
        english: "Complete at exit handoff"
      )
    }
    return copy.resolve(
      japanese: "このナビを終了",
      simplifiedChinese: "结束本次导航",
      english: "End this navigation"
    )
  }

  private func identityRow(
    _ label: String,
    value: String
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(label)
        .font(.system(size: 8, weight: .black, design: .monospaced))
        .foregroundStyle(KaidoTheme.muted)
        .frame(width: 72, alignment: .leading)

      Text(verbatim: value)
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .foregroundStyle(KaidoTheme.routeWhite)
        .lineLimit(2)
        .minimumScaleFactor(0.72)
    }
  }

  private func runtimeMetric(
    title: String,
    value: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.system(size: 8, weight: .black, design: .monospaced))
        .foregroundStyle(KaidoTheme.muted)

      Text(value)
        .font(.system(size: 9, weight: .black, design: .monospaced))
        .foregroundStyle(KaidoTheme.routeWhite)
        .lineLimit(2)
        .minimumScaleFactor(0.72)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var locationActionAvailable: Bool {
    locationController.canStart || locationController.canStop
  }

  private var activationColor: Color {
    switch model.activation {
    case .validating:
      KaidoTheme.signalAmber
    case .ready:
      KaidoTheme.positionCyan
    case .ended:
      KaidoTheme.muted
    case .failed:
      KaidoTheme.evidenceCoral
    }
  }

  private var locationColor: Color {
    switch locationController.state {
    case .running:
      KaidoTheme.positionCyan
    case .awaitingAuthorization, .idle, .stopped:
      KaidoTheme.signalAmber
    case .releaseBlocked, .runtimeUnavailable, .sceneInactive,
      .permissionDenied, .failed:
      KaidoTheme.evidenceCoral
    }
  }

  private var activationLabel: String {
    switch model.activation {
    case .validating:
      copy.resolve(
        japanese: "検証中",
        simplifiedChinese: "正在验证",
        english: "VALIDATING"
      )
    case .ready:
      copy.resolve(
        japanese: "ランタイム準備完了",
        simplifiedChinese: "运行时已就绪",
        english: "RUNTIME READY"
      )
    case .ended:
      copy.resolve(
        japanese: "ランタイム終了",
        simplifiedChinese: "运行时已结束",
        english: "RUNTIME ENDED"
      )
    case .failed:
      copy.resolve(
        japanese: "停止",
        simplifiedChinese: "已阻止",
        english: "BLOCKED"
      )
    }
  }

  private var locationStateLabel: String {
    switch locationController.state {
    case .releaseBlocked:
      copy.resolve(
        japanese: "ライブ位置情報はリリースで停止",
        simplifiedChinese: "实时定位已被发布门阻止",
        english: "LIVE LOCATION BLOCKED"
      )
    case .runtimeUnavailable:
      copy.resolve(
        japanese: "ランタイム利用不可",
        simplifiedChinese: "运行时不可用",
        english: "RUNTIME UNAVAILABLE"
      )
    case .idle:
      copy.resolve(
        japanese: "ライブ位置情報は待機中",
        simplifiedChinese: "实时定位待机",
        english: "LIVE LOCATION IDLE"
      )
    case .awaitingAuthorization:
      copy.resolve(
        japanese: "位置情報の許可待ち",
        simplifiedChinese: "等待定位授权",
        english: "AWAITING LOCATION AUTHORIZATION"
      )
    case .running:
      copy.resolve(
        japanese: "前景位置情報を実行中",
        simplifiedChinese: "前台定位运行中",
        english: "FOREGROUND LOCATION RUNNING"
      )
    case .stopped:
      copy.resolve(
        japanese: "前景位置情報を停止",
        simplifiedChinese: "前台定位已停止",
        english: "FOREGROUND LOCATION STOPPED"
      )
    case .sceneInactive:
      copy.resolve(
        japanese: "画面非アクティブのため位置情報停止",
        simplifiedChinese: "场景非活动，定位已停止",
        english: "LOCATION STOPPED · SCENE INACTIVE"
      )
    case .permissionDenied:
      copy.resolve(
        japanese: "位置情報の許可なし",
        simplifiedChinese: "定位权限被拒绝",
        english: "LOCATION PERMISSION DENIED"
      )
    case .failed:
      copy.resolve(
        japanese: "位置情報パイプライン停止",
        simplifiedChinese: "定位管线已阻止",
        english: "LOCATION PIPELINE BLOCKED"
      )
    }
  }

  private var locationStateDetail: String {
    switch locationController.state {
    case .releaseBlocked(let reason):
      reason.rawValue
    case .runtimeUnavailable:
      copy.resolve(
        japanese: "リリースに固定された actor は前景入力を受け取る準備ができていません。",
        simplifiedChinese: "绑定发布包的 actor 尚未准备接收前台输入。",
        english:
          "The release-bound actor is not ready to accept foreground input."
      )
    case .idle:
      copy.resolve(
        japanese: "位置情報はユーザーが明示的に操作した後だけ開始します。",
        simplifiedChinese: "只有用户明确操作后才会启动定位。",
        english: "Location starts only after an explicit user action."
      )
    case .awaitingAuthorization:
      copy.resolve(
        japanese: "使用中の位置情報許可を待っています。更新はまだ開始していません。",
        simplifiedChinese: "正在等待“使用 App 期间”定位授权，尚未开始更新。",
        english:
          "Waiting for When In Use authorization; no updates have started."
      )
    case .running:
      copy.resolve(
        japanese:
          "使用中の位置更新をコールバック順のまま正確な release-bound actor に渡します。",
        simplifiedChinese:
          "“使用 App 期间”的定位更新按回调顺序传入精确绑定发布包的 actor。",
        english:
          "When In Use updates feed the exact release-bound actor in callback order."
      )
    case .stopped:
      copy.resolve(
        japanese: "次の明示的な操作まで更新は停止したままです。",
        simplifiedChinese: "定位更新保持停止，直到用户再次明确启动。",
        english: "Updates remain stopped until another explicit user action."
      )
    case .sceneInactive:
      copy.resolve(
        japanese:
          "チェックポイント保存前に更新を停止しました。バックグラウンド位置情報は無効です。",
        simplifiedChinese: "保存检查点前已停止更新；后台定位保持禁用。",
        english:
          "Updates stopped before checkpointing; background location is disabled."
      )
    case .permissionDenied:
      copy.resolve(
        japanese:
          "Core Location が拒否または制限されています。経路進行は受け付けません。",
        simplifiedChinese: "Core Location 被拒绝或受限；不会接受路线进度。",
        english:
          "Core Location is denied or restricted; no route progress is accepted."
      )
    case .failed(let code):
      code
    }
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }

  private func handleScenePhase(
    _ phase: ProductNavigationRuntimeScenePhase
  ) async {
    switch phase {
    case .active:
      await model.handleScenePhase(phase)
      await locationController.handleScenePhase(phase)
    case .inactive, .background:
      await locationController.handleScenePhase(phase)
      await model.handleScenePhase(phase)
    }
  }
}
