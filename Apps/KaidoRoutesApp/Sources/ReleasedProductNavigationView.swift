import SwiftUI

struct ReleasedProductNavigationPanel: View {
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
        Text("路线导航")
          .font(.system(size: 23, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)

        Text("RELEASE-BOUND · USER STARTED")
          .font(.system(size: 9, weight: .black, design: .monospaced))
          .tracking(0.7)
          .foregroundStyle(KaidoTheme.signalAmber)
      }

      Spacer()

      StatusCapsule(
        title: model.activation.label,
        color: activationColor
      )
      .accessibilityIdentifier("released-runtime-activation")
      .accessibilityValue(model.activation.label)
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

      Text("用户明确启动后才连接定位")
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

        Text(locationController.state.label)
          .font(.system(size: 8, weight: .black, design: .monospaced))
          .foregroundStyle(locationColor)
      }

      Text(locationController.state.detail)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(KaidoTheme.muted)
        .fixedSize(horizontal: false, vertical: true)

      HStack {
        runtimeMetric(
          title: "授权",
          value: locationController.authorizationLabel
        )
        runtimeMetric(
          title: "精度",
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
          locationController.canStop ? "停止前台定位" : "启动前台定位",
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
    .accessibilityValue(locationController.state.label)
  }

  @ViewBuilder
  private var actorProjection: some View {
    if let projection = model.presentationProjection {
      ProductRuntimeDrivingSurface(projection: projection)
    } else {
      ReviewBoundaryCard(
        symbol: "scope",
        title: "等待 release-bound actor 证据",
        detail:
          "定位未进入严格路线，或尚未产生有效 guidance frame；界面不会猜测当前位置或下一分岔。",
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
      title: "实时通行状态尚未确认",
      detail: "静态发布身份和实时开放状态保持分离；缺少实时证据不会显示为畅通。",
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
      Label("结束本次导航", systemImage: "xmark.circle.fill")
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
