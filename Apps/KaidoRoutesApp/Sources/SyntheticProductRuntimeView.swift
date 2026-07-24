import SwiftUI

struct SyntheticProductRuntimePanel: View {
  @Environment(\.scenePhase) private var scenePhase
  @ObservedObject var model: SyntheticProductRuntimeModel

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header
      releaseIdentity
      runtimeMetrics
      actorState
      actorProjection
      lifecycleState
      inputState
      speechState
      safetyNotice
    }
    .padding(16)
    .background(KaidoTheme.instrument)
    .clipShape(RoundedRectangle(cornerRadius: 22))
    .overlay {
      RoundedRectangle(cornerRadius: 22)
        .stroke(KaidoTheme.signalAmber.opacity(0.48), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("synthetic-product-runtime-panel")
    .task {
      await model.activate()
      if ProcessInfo.processInfo.arguments.contains(
        "-PRODUCT-RUNTIME-AUTO-TRACE"
      ) {
        await model.runDeterministicPreviewTrace()
      }
    }
    .onChange(of: scenePhase, initial: true) { _, newPhase in
      Task {
        await model.handleScenePhase(newPhase.productRuntimePhase)
      }
    }
  }

  private var header: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 3) {
        Text("产品运行时合成")
          .font(.system(size: 19, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)

        Text("SYNTHETIC JOINT RELEASE · ACTOR OWNED")
          .font(.system(size: 9, weight: .bold, design: .monospaced))
          .tracking(0.7)
          .foregroundStyle(KaidoTheme.muted)
      }

      Spacer()

      StatusCapsule(
        title: model.activation.label,
        color: activationColor
      )
      .accessibilityIdentifier("product-runtime-activation")
      .accessibilityValue(model.activation.label)
    }
  }

  private var releaseIdentity: some View {
    VStack(alignment: .leading, spacing: 8) {
      RuntimeIdentityRow(
        label: "PRODUCT RELEASE",
        value: model.productReleaseID
      )
      RuntimeIdentityRow(
        label: "NAVIGATION RELEASE",
        value: model.navigationReleaseID
      )
      RuntimeIdentityRow(
        label: "ROUTE PLAN",
        value: model.routePlanID
      )
      RuntimeIdentityRow(
        label: "NETWORK SNAPSHOT",
        value: model.networkSnapshotID
      )
    }
    .padding(12)
    .background(KaidoTheme.asphalt.opacity(0.55))
    .clipShape(RoundedRectangle(cornerRadius: 13))
  }

  private var runtimeMetrics: some View {
    HStack(spacing: 0) {
      Metric(value: "\(model.routeOccurrenceCount)", label: "路线步骤")
      DividerMark()
      Metric(value: "\(model.corridorEdgeCount)", label: "走廊边")
      DividerMark()
      Metric(value: "\(model.entryTransitionEdgeCount)", label: "入口边")
    }
  }

  private var actorState: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("ATOMIC NAVIGATION SNAPSHOT")
        .font(.system(size: 8, weight: .black, design: .monospaced))
        .tracking(0.6)
        .foregroundStyle(KaidoTheme.muted)

      HStack {
        RuntimeStateBadge(
          label: "PHASE",
          value: model.snapshot?.journeyPhase.rawValue ?? "—"
        )
        RuntimeStateBadge(
          label: "CONFIDENCE",
          value: model.snapshot?.locationConfidence.rawValue ?? "—"
        )
      }

      HStack {
        Text("STRICT ENTRY")
          .font(.system(size: 9, weight: .black, design: .monospaced))
          .foregroundStyle(KaidoTheme.muted)

        Spacer()

        Text(
          model.snapshot?.strictRouteAutoCommitAllowed == true
            ? "ADMITTED" : "LOCKED"
        )
        .font(.system(size: 10, weight: .black, design: .monospaced))
        .foregroundStyle(
          model.snapshot?.strictRouteAutoCommitAllowed == true
            ? KaidoTheme.positionCyan : KaidoTheme.evidenceCoral
        )
      }
    }
    .padding(12)
    .background(KaidoTheme.asphalt.opacity(0.42))
    .clipShape(RoundedRectangle(cornerRadius: 13))
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("product-runtime-snapshot")
    .accessibilityValue(
      "\(model.snapshot?.journeyPhase.rawValue ?? "UNAVAILABLE"), "
        + "\(model.snapshot?.strictRouteAutoCommitAllowed == true ? "ADMITTED" : "LOCKED")"
    )
  }

  private var lifecycleState: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: lifecycleSymbol)
        .font(.system(size: 12, weight: .black))
        .foregroundStyle(lifecycleColor)
        .frame(width: 20)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        Text("SESSION LIFECYCLE · \(model.lifecycleStatusLabel)")
          .font(.system(size: 9, weight: .black, design: .monospaced))
          .tracking(0.35)
          .foregroundStyle(lifecycleColor)

        Text(model.lifecycleStatusDetail)
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(KaidoTheme.muted)
      }
    }
    .padding(11)
    .background(KaidoTheme.asphalt.opacity(0.42))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(alignment: .leading) {
      Rectangle()
        .fill(lifecycleColor)
        .frame(width: 2)
        .padding(.vertical, 10)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("product-runtime-lifecycle")
    .accessibilityValue(model.lifecycleStatusLabel)
  }

  private var actorProjection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(model.presentationState.label)
          .font(.system(size: 9, weight: .black, design: .monospaced))
          .tracking(0.35)
          .foregroundStyle(presentationColor)

        Spacer()

        Text("SYNTHETIC INPUT ONLY")
          .font(.system(size: 8, weight: .black, design: .monospaced))
          .foregroundStyle(KaidoTheme.evidenceCoral)
      }

      if let projection = model.presentationProjection {
        ProductRuntimeDrivingSurface(projection: projection)
      } else {
        Text(model.presentationState.detail)
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(KaidoTheme.muted)
          .padding(11)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(KaidoTheme.asphalt.opacity(0.42))
          .clipShape(RoundedRectangle(cornerRadius: 12))
      }

      Button {
        Task {
          await model.runDeterministicPreviewTrace()
        }
      } label: {
        Label("执行合成 actor 输入链", systemImage: "point.3.connected.trianglepath.dotted")
          .font(.system(.subheadline, design: .rounded, weight: .black))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 11)
          .foregroundStyle(
            model.canRunDeterministicPreviewTrace
              ? KaidoTheme.asphalt
              : KaidoTheme.muted
          )
          .background(
            model.canRunDeterministicPreviewTrace
              ? KaidoTheme.positionCyan
              : KaidoTheme.steel.opacity(0.35)
          )
          .clipShape(RoundedRectangle(cornerRadius: 11))
      }
      .buttonStyle(.plain)
      .disabled(!model.canRunDeterministicPreviewTrace)
      .accessibilityLabel("执行合成 actor 输入链，不连接实时定位")
      .accessibilityIdentifier("product-runtime-run-trace")
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("product-runtime-presentation-state")
    .accessibilityValue(model.presentationState.label)
  }

  private var inputState: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(model.inputState.label)
        .font(.system(size: 10, weight: .black, design: .monospaced))
        .foregroundStyle(KaidoTheme.signalAmber)

      Text(model.inputState.detail)
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(KaidoTheme.muted)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("product-runtime-input")
    .accessibilityValue(model.inputState.label)
  }

  private var speechState: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: speechSymbol)
        .font(.system(size: 13, weight: .black))
        .foregroundStyle(speechColor)
        .frame(width: 20)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        Text("GUIDANCE AUDIO · \(model.speechStatusLabel)")
          .font(.system(size: 9, weight: .black, design: .monospaced))
          .tracking(0.35)
          .foregroundStyle(speechColor)

        Text(model.speechStatusDetail)
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(KaidoTheme.muted)

        Text("一次性提示才可发声；中断结束不补播旧提示。")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(KaidoTheme.muted.opacity(0.82))
      }
    }
    .padding(11)
    .background(KaidoTheme.asphalt.opacity(0.42))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("product-runtime-speech")
    .accessibilityValue(model.speechStatusLabel)
  }

  private var safetyNotice: some View {
    HStack(alignment: .top, spacing: 9) {
      Image(systemName: "exclamationmark.shield.fill")
        .foregroundStyle(KaidoTheme.evidenceCoral)
        .accessibilityHidden(true)

      Text(
        "该文件完整通过产品发布门，但所有来源均为 SYNTHETIC_TEST_ONLY。"
          + "当前 scene 未连接 CLLocationManager、后台定位或 CarPlay，"
          + "语音适配器也不会在没有一次性 prompt emission 时激活，"
          + "不可作为真实道路导航。"
      )
      .font(.system(size: 10, weight: .semibold))
      .foregroundStyle(KaidoTheme.muted)
    }
    .padding(11)
    .background(KaidoTheme.evidenceCoral.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .accessibilityIdentifier("product-runtime-safety")
  }

  private var activationColor: Color {
    switch model.activation {
    case .validating:
      KaidoTheme.signalAmber
    case .ready:
      KaidoTheme.positionCyan
    case .failed:
      KaidoTheme.evidenceCoral
    }
  }

  private var speechColor: Color {
    switch model.speechStatus {
    case .scheduled, .speaking:
      KaidoTheme.positionCyan
    case .failed, .invalidProjection:
      KaidoTheme.evidenceCoral
    case .interrupted, .suppressed:
      KaidoTheme.signalAmber
    case .idle, .stopped:
      KaidoTheme.muted
    }
  }

  private var presentationColor: Color {
    switch model.presentationState {
    case .awaitingGuidanceFrame:
      KaidoTheme.signalAmber
    case .ready:
      KaidoTheme.positionCyan
    case .blocked:
      KaidoTheme.evidenceCoral
    }
  }

  private var lifecycleColor: Color {
    switch model.lifecycleState {
    case .foreground:
      KaidoTheme.positionCyan
    case .restoredReacquisitionRequired, .inactiveCheckpointed,
      .backgroundCheckpointed, .inactiveUnpersisted,
      .backgroundUnpersisted:
      KaidoTheme.signalAmber
    case .checkpointFailed, .checkpointRejected:
      KaidoTheme.evidenceCoral
    }
  }

  private var lifecycleSymbol: String {
    switch model.lifecycleState {
    case .foreground:
      "location.fill"
    case .restoredReacquisitionRequired:
      "location.magnifyingglass"
    case .inactiveCheckpointed, .backgroundCheckpointed:
      "externaldrive.fill.badge.checkmark"
    case .inactiveUnpersisted, .backgroundUnpersisted:
      "memorychip"
    case .checkpointFailed, .checkpointRejected:
      "externaldrive.fill.badge.xmark"
    }
  }

  private var speechSymbol: String {
    switch model.speechStatus {
    case .scheduled, .speaking:
      "speaker.wave.2.fill"
    case .failed, .invalidProjection:
      "speaker.slash.fill"
    case .interrupted:
      "phone.down.fill"
    case .suppressed, .stopped:
      "speaker.slash"
    case .idle:
      "speaker"
    }
  }
}

private struct RuntimeIdentityRow: View {
  let label: String
  let value: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(label)
        .font(.system(size: 8, weight: .black, design: .monospaced))
        .foregroundStyle(KaidoTheme.muted)
        .frame(width: 104, alignment: .leading)

      Text(verbatim: value)
        .font(.system(size: 8, weight: .semibold, design: .monospaced))
        .foregroundStyle(KaidoTheme.routeWhite)
        .lineLimit(2)
    }
  }
}

private struct RuntimeStateBadge: View {
  let label: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label)
        .font(.system(size: 8, weight: .black, design: .monospaced))
        .foregroundStyle(KaidoTheme.muted)

      Text(value)
        .font(.system(size: 11, weight: .black, design: .monospaced))
        .foregroundStyle(KaidoTheme.routeWhite)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
