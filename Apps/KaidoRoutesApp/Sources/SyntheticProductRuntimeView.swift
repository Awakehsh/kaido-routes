import KaidoAppleAdapters
import KaidoNavigation
import SwiftUI

struct SyntheticProductRuntimePanel: View {
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale
  @ObservedObject var model: SyntheticProductRuntimeModel
  @ObservedObject private var locationController: ForegroundNavigationLocationController

  init(model: SyntheticProductRuntimeModel) {
    self.model = model
    locationController = model.foregroundNavigationLocationController
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header
      releaseIdentity
      runtimeMetrics
      actorState
      simulationControls
      ReleasedRouteAtlasOverlayContainer(
        presentation: model.routeAtlasOverlayPresentation
      )
      actorProjection
      lifecycleState
      foregroundLocationState
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
      locationController.refreshRuntimeAvailability()
      if ProcessInfo.processInfo.arguments.contains(
        "-PRODUCT-RUNTIME-AUTO-TRACE"
      ) {
        await model.runDeterministicPreviewTrace()
      }
    }
    .onChange(of: scenePhase, initial: true) { _, newPhase in
      Task {
        await handleScenePhase(newPhase.productRuntimePhase)
      }
    }
  }

  private var header: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 3) {
        Text(
          copy.resolve(
            japanese: "製品ランタイム演習",
            simplifiedChinese: "产品运行时演练",
            english: "Product runtime rehearsal"
          )
        )
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
      Metric(
        value: "\(model.routeOccurrenceCount)",
        label: copy.resolve(
          japanese: "経路ステップ",
          simplifiedChinese: "路线步骤",
          english: "ROUTE STEPS"
        )
      )
      DividerMark()
      Metric(
        value: "\(model.corridorEdgeCount)",
        label: copy.resolve(
          japanese: "コリドー辺",
          simplifiedChinese: "走廊边",
          english: "CORRIDOR EDGES"
        )
      )
      DividerMark()
      Metric(
        value: "\(model.entryTransitionEdgeCount)",
        label: copy.resolve(
          japanese: "入口辺",
          simplifiedChinese: "入口边",
          english: "ENTRY EDGES"
        )
      )
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
        Label(
          copy.resolve(
            japanese: "入口アダプタのスモーク入力",
            simplifiedChinese: "运行入口适配器冒烟输入",
            english: "Run the entry-adapter smoke trace"
          ),
          systemImage: "point.3.connected.trianglepath.dotted"
        )
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
      .accessibilityLabel(
        copy.resolve(
          japanese: "実時間位置情報に接続せず、入口アダプタのスモーク入力を実行",
          simplifiedChinese: "运行入口适配器冒烟输入，不连接实时定位",
          english: "Run the entry-adapter smoke trace without live location"
        )
      )
      .accessibilityIdentifier("product-runtime-run-trace")
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("product-runtime-presentation-state")
    .accessibilityValue(model.presentationState.label)
  }

  private var simulationControls: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        VStack(alignment: .leading, spacing: 2) {
          Text(
            copy.resolve(
              japanese: "経路シミュレーション",
              simplifiedChinese: "全程路线模拟",
              english: "Full-route simulation"
            )
          )
          .font(.system(size: 12, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)

          Text("MATCHER → NAVIGATION SESSION → PRESENTATION")
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .foregroundStyle(KaidoTheme.muted)
        }

        Spacer()

        Text(model.simulationStatus?.state.rawValue ?? "UNAVAILABLE")
          .font(.system(size: 9, weight: .black, design: .monospaced))
          .foregroundStyle(simulationColor)
      }

      if let status = model.simulationStatus {
        ProgressView(value: status.progress)
          .tint(KaidoTheme.positionCyan)

        HStack(spacing: 8) {
          RuntimeStateBadge(
            label: "EVENTS",
            value: "\(status.completedEventCount)/\(status.totalEventCount)"
          )
          RuntimeStateBadge(
            label: "SPEED",
            value: "\(status.speed.multiplier)×"
          )
          RuntimeStateBadge(
            label: "FAULT",
            value: model.simulationPreset.rawValue
          )
        }
      }

      HStack(spacing: 8) {
        Button {
          Task {
            await model.playNavigationSimulation()
          }
        } label: {
          Label(
            copy.resolve(
              japanese: "再生",
              simplifiedChinese: "播放",
              english: "Play"
            ),
            systemImage: "play.fill"
          )
          .font(.system(.caption, design: .rounded, weight: .black))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 9)
        }
        .buttonStyle(.borderedProminent)
        .tint(KaidoTheme.positionCyan)
        .disabled(!model.canPlayNavigationSimulation)
        .accessibilityIdentifier("product-runtime-simulation-play")

        Button {
          Task {
            await model.pauseNavigationSimulation()
          }
        } label: {
          Image(systemName: "pause.fill")
            .font(.system(size: 12, weight: .black))
            .padding(.vertical, 9)
        }
        .buttonStyle(.bordered)
        .tint(KaidoTheme.signalAmber)
        .disabled(!model.canPauseNavigationSimulation)
        .accessibilityLabel(
          copy.resolve(
            japanese: "一時停止",
            simplifiedChinese: "暂停",
            english: "Pause"
          )
        )
        .accessibilityIdentifier("product-runtime-simulation-pause")

        Button {
          Task {
            await model.stepNavigationSimulation()
          }
        } label: {
          Image(systemName: "forward.frame.fill")
            .font(.system(size: 12, weight: .black))
            .padding(.vertical, 9)
        }
        .buttonStyle(.bordered)
        .tint(KaidoTheme.routeWhite)
        .disabled(!model.canStepNavigationSimulation)
        .accessibilityLabel(
          copy.resolve(
            japanese: "一ステップ進む",
            simplifiedChinese: "单步前进",
            english: "Step one event"
          )
        )
        .accessibilityIdentifier("product-runtime-simulation-step")

        Button {
          Task {
            await model.resetNavigationSimulation()
          }
        } label: {
          Image(systemName: "arrow.counterclockwise")
            .font(.system(size: 12, weight: .black))
            .padding(.vertical, 9)
        }
        .buttonStyle(.bordered)
        .tint(KaidoTheme.muted)
        .disabled(!model.canResetNavigationSimulation)
        .accessibilityLabel(
          copy.resolve(
            japanese: "シミュレーションをリセット",
            simplifiedChinese: "重置模拟",
            english: "Reset simulation"
          )
        )
        .accessibilityIdentifier("product-runtime-simulation-reset")
      }

      HStack(spacing: 8) {
        Menu {
          ForEach(
            ProductNavigationRuntimeSimulationPreset.allCases,
            id: \.rawValue
          ) { preset in
            Button(simulationPresetLabel(preset)) {
              Task {
                await model.selectNavigationSimulationPreset(preset)
              }
            }
          }
        } label: {
          Label(
            simulationPresetLabel(model.simulationPreset),
            systemImage: "waveform.path.ecg"
          )
          .font(.system(.caption2, design: .rounded, weight: .black))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .tint(KaidoTheme.evidenceCoral)
        .accessibilityIdentifier("product-runtime-simulation-preset")

        Menu {
          ForEach(
            NavigationDriveSimulationSpeed.allCases,
            id: \.rawValue
          ) { speed in
            Button("\(speed.multiplier)×") {
              Task {
                await model.setNavigationSimulationSpeed(speed)
              }
            }
          }
        } label: {
          Label(
            "\(model.simulationStatus?.speed.multiplier ?? 1)×",
            systemImage: "speedometer"
          )
          .font(.system(.caption2, design: .rounded, weight: .black))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .tint(KaidoTheme.signalAmber)
        .accessibilityIdentifier("product-runtime-simulation-speed")
      }

      Text(
        copy.resolve(
          japanese:
            "入口承認を偽装せず、合成 strict-route seed から開始します。結果は実走証拠ではありません。",
          simplifiedChinese:
            "不伪造入口审批，从合成 strict-route seed 开始；结果不属于实车证据。",
          english:
            "Starts from a synthetic strict-route seed without forging entry admission; results are not field evidence."
        )
      )
      .font(.system(size: 9, weight: .semibold))
      .foregroundStyle(KaidoTheme.muted)

      if let failure = model.simulationFailureCode {
        Text(failure)
          .font(.system(size: 9, weight: .black, design: .monospaced))
          .foregroundStyle(KaidoTheme.evidenceCoral)
      }
    }
    .padding(12)
    .background(KaidoTheme.asphalt.opacity(0.42))
    .clipShape(RoundedRectangle(cornerRadius: 13))
    .overlay(alignment: .leading) {
      Rectangle()
        .fill(simulationColor)
        .frame(width: 2)
        .padding(.vertical, 10)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("product-runtime-simulation")
    .accessibilityValue(
      model.simulationStatus?.state.rawValue ?? "UNAVAILABLE"
    )
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

  private var foregroundLocationState: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(locationController.state.label)
          .font(.system(size: 9, weight: .black, design: .monospaced))
          .tracking(0.35)
          .foregroundStyle(foregroundLocationColor)

        Spacer()

        Text("WHEN IN USE · FOREGROUND ONLY")
          .font(.system(size: 8, weight: .black, design: .monospaced))
          .foregroundStyle(KaidoTheme.muted)
      }

      Text(locationController.state.detail)
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(KaidoTheme.muted)

      HStack(spacing: 8) {
        RuntimeStateBadge(
          label: "AUTH",
          value: locationController.authorizationLabel
        )
        RuntimeStateBadge(
          label: "ACCURACY",
          value: locationController.accuracyAuthorizationLabel
        )
      }

      HStack(spacing: 8) {
        Button {
          locationController.start()
        } label: {
          Label(
            copy.resolve(
              japanese: "前景位置情報を開始",
              simplifiedChinese: "启动前台定位",
              english: "Start foreground location"
            ),
            systemImage: "location.fill"
          )
          .font(.system(.caption, design: .rounded, weight: .black))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(KaidoTheme.positionCyan)
        .disabled(!locationController.canStart)
        .accessibilityIdentifier("product-runtime-start-live-location")

        Button {
          Task {
            await locationController.stop()
          }
        } label: {
          Label(
            copy.resolve(
              japanese: "停止",
              simplifiedChinese: "停止",
              english: "Stop"
            ),
            systemImage: "stop.fill"
          )
          .font(.system(.caption, design: .rounded, weight: .black))
          .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
        .tint(KaidoTheme.signalAmber)
        .disabled(!locationController.canStop)
        .accessibilityIdentifier("product-runtime-stop-live-location")
      }
    }
    .padding(11)
    .background(KaidoTheme.asphalt.opacity(0.42))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(alignment: .leading) {
      Rectangle()
        .fill(foregroundLocationColor)
        .frame(width: 2)
        .padding(.vertical, 10)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("product-runtime-live-location")
    .accessibilityValue(locationController.state.label)
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

        if let voice = model.speechVoiceProfile {
          Text(
            "VOICE · \(voice.name) · \(voice.languageCode) · "
              + voice.quality.label
          )
          .font(.system(size: 9, weight: .black, design: .monospaced))
          .foregroundStyle(
            voice.quality == .defaultQuality
              ? KaidoTheme.signalAmber
              : KaidoTheme.positionCyan
          )

          Text(voiceQualityDetail(voice.quality))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(KaidoTheme.muted.opacity(0.82))

          if !voice.quality.isHigherQuality {
            Text(
              copy.resolve(
                japanese:
                  "iPhone の設定で拡張またはプレミアム音声をダウンロードすると、Kaido が優先して使用します。",
                simplifiedChinese:
                  "在 iPhone 设置中下载增强或高级声音后，Kaido 会自动优先使用。",
                english:
                  "Download an enhanced or premium voice in iPhone Settings and Kaido will prefer it automatically."
              )
            )
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(KaidoTheme.signalAmber.opacity(0.9))
          }
        }

        Text(
          copy.resolve(
            japanese: "一回限りの案内だけを発話し、中断後に古い案内を再生しません。",
            simplifiedChinese: "只有一次性提示可以发声；中断后不会补播旧提示。",
            english:
              "Only one-shot prompts may speak; interrupted prompts are never replayed."
          )
        )
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(KaidoTheme.muted.opacity(0.82))
      }
    }
    .padding(11)
    .background(KaidoTheme.asphalt.opacity(0.42))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("product-runtime-speech")
    .accessibilityValue(speechAccessibilityValue)
  }

  private var safetyNotice: some View {
    HStack(alignment: .top, spacing: 9) {
      Image(systemName: "exclamationmark.shield.fill")
        .foregroundStyle(KaidoTheme.evidenceCoral)
        .accessibilityHidden(true)

      Text(
        copy.resolve(
          japanese:
            "この演習は製品の構成境界を通過しますが、すべての情報源は SYNTHETIC_TEST_ONLY です。リアルタイム位置情報、バックグラウンド位置情報、CarPlay は有効にならず、実道路ナビには使用できません。",
          simplifiedChinese:
            "这套演练通过产品组合边界，但所有来源均为 SYNTHETIC_TEST_ONLY。不会启用实时定位、后台定位或 CarPlay，也不能作为真实道路导航。",
          english:
            "This rehearsal passes the product composition boundary, but every source is SYNTHETIC_TEST_ONLY. Live location, background location, and CarPlay remain disabled, so it cannot serve as real-road navigation."
        )
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
    case .ended:
      KaidoTheme.muted
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

  private var simulationColor: Color {
    switch model.simulationStatus?.state {
    case .playing:
      KaidoTheme.positionCyan
    case .paused, .ready:
      KaidoTheme.signalAmber
    case .completed:
      KaidoTheme.routeWhite
    case nil:
      KaidoTheme.evidenceCoral
    }
  }

  private func simulationPresetLabel(
    _ preset: ProductNavigationRuntimeSimulationPreset
  ) -> String {
    switch preset {
    case .clean:
      copy.resolve(
        japanese: "正常",
        simplifiedChinese: "正常",
        english: "Clean"
      )
    case .gpsDrift:
      copy.resolve(
        japanese: "GPS ドリフト",
        simplifiedChinese: "GPS 漂移",
        english: "GPS drift"
      )
    case .signalGap:
      copy.resolve(
        japanese: "信号中断",
        simplifiedChinese: "信号中断",
        english: "Signal gap"
      )
    case .poorAccuracy:
      copy.resolve(
        japanese: "低精度",
        simplifiedChinese: "低精度",
        english: "Poor accuracy"
      )
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

  private var foregroundLocationColor: Color {
    switch locationController.state {
    case .running:
      KaidoTheme.positionCyan
    case .idle, .stopped, .awaitingAuthorization, .sceneInactive:
      KaidoTheme.signalAmber
    case .releaseBlocked, .runtimeUnavailable, .permissionDenied, .failed:
      KaidoTheme.evidenceCoral
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

  private var speechAccessibilityValue: String {
    guard let voice = model.speechVoiceProfile else {
      return model.speechStatusLabel
    }
    return
      "\(model.speechStatusLabel) · \(voice.name) · "
      + "\(voice.languageCode) · \(voice.quality.label)"
  }

  private func voiceQualityDetail(
    _ quality: GuidanceSpeechVoiceQuality
  ) -> String {
    switch quality {
    case .premium:
      copy.resolve(
        japanese: "Premium 音声を使用します。",
        simplifiedChinese: "当前使用设备上的 Premium 声音。",
        english: "Using the installed Premium voice."
      )
    case .enhanced:
      copy.resolve(
        japanese: "拡張音声を使用します。",
        simplifiedChinese: "当前使用设备上的增强声音。",
        english: "Using the installed enhanced voice."
      )
    case .defaultQuality:
      copy.resolve(
        japanese: "標準音声を使用します。",
        simplifiedChinese: "当前使用设备上的基础声音。",
        english: "Using the installed default voice."
      )
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

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
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
