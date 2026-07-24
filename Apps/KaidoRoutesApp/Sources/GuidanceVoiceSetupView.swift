import KaidoAppleAdapters
import SwiftUI

struct GuidanceVoiceSetupPanel: View {
  @ObservedObject var model: GuidanceVoiceSetupModel
  let isParked: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 15) {
      header
      sampleMonitor
      voiceSelection
      readiness
      auditionButton
      if model.state.showsAuditionDetail {
        auditionStatus
      }
      authorityBoundary
    }
    .padding(16)
    .background(KaidoTheme.instrument)
    .clipShape(RoundedRectangle(cornerRadius: 22))
    .overlay {
      RoundedRectangle(cornerRadius: 22)
        .stroke(accentColor.opacity(0.5), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("product-journey-voice-check")
    .accessibilityValue(accessibilityValue)
    .onAppear {
      model.refreshProfiles()
    }
    .onDisappear {
      model.stop()
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text("导航声音确认")
          .font(.system(size: 19, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)

        Text("PARKED SOUND CHECK · JA-JP")
          .font(.system(size: 9, weight: .bold, design: .monospaced))
          .tracking(0.75)
          .foregroundStyle(KaidoTheme.muted)
      }

      Spacer(minLength: 8)

      StatusCapsule(
        title: model.statusLabel,
        color: accentColor
      )
    }
  }

  private var sampleMonitor: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label("固定导航样句", systemImage: "waveform")
          .font(.system(size: 9, weight: .black, design: .monospaced))
          .tracking(0.6)
          .foregroundStyle(KaidoTheme.muted)

        Spacer()

        Text(model.languageCode.uppercased())
          .font(.system(size: 8, weight: .black, design: .monospaced))
          .foregroundStyle(KaidoTheme.positionCyan)
      }

      HStack(alignment: .center, spacing: 12) {
        SoundCheckRail(
          isActive: model.state.isAuditionActive,
          color: accentColor
        )

        Text(verbatim: "「\(model.auditionText)」")
          .font(.system(size: 17, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(13)
    .background(KaidoTheme.asphalt.opacity(0.5))
    .clipShape(RoundedRectangle(cornerRadius: 14))
  }

  private var voiceSelection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("已安装声音")
        .font(.system(size: 9, weight: .black, design: .monospaced))
        .tracking(0.65)
        .foregroundStyle(KaidoTheme.muted)

      Menu {
        Button {
          model.selectVoice(identifier: nil)
        } label: {
          voiceMenuLabel(
            title: "自动选择最高质量",
            detail: "PREMIUM → ENHANCED → DEFAULT",
            isSelected: model.usesAutomaticSelection
          )
        }

        ForEach(model.profiles, id: \.identifier) { profile in
          Button {
            model.selectVoice(identifier: profile.identifier)
          } label: {
            voiceMenuLabel(
              title: profile.name,
              detail: profile.quality.label,
              isSelected:
                model.selectedVoiceIdentifier == profile.identifier
            )
          }
        }
      } label: {
        HStack(spacing: 11) {
          Image(systemName: "person.wave.2.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(KaidoTheme.signalAmber)
            .frame(width: 25)

          VStack(alignment: .leading, spacing: 2) {
            Text(selectionTitle)
              .font(.system(size: 13, weight: .black))
              .foregroundStyle(KaidoTheme.routeWhite)

            Text(selectionDetail)
              .font(.system(size: 8, weight: .black, design: .monospaced))
              .foregroundStyle(selectionDetailColor)
          }

          Spacer()

          Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 11, weight: .black))
            .foregroundStyle(KaidoTheme.muted)
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(KaidoTheme.asphalt.opacity(0.48))
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay {
          RoundedRectangle(cornerRadius: 13)
            .stroke(KaidoTheme.steel.opacity(0.75), lineWidth: 1)
        }
      }
      .accessibilityLabel("选择已安装的日语导航声音")
      .accessibilityValue("\(selectionTitle)，\(selectionDetail)")
      .accessibilityIdentifier("voice-check-profile-menu")
    }
  }

  private var readiness: some View {
    HStack(alignment: .top, spacing: 11) {
      Image(systemName: readinessSymbol)
        .font(.system(size: 14, weight: .black))
        .foregroundStyle(readinessColor)
        .frame(width: 22)

      VStack(alignment: .leading, spacing: 3) {
        Text(readinessTitle)
          .font(.system(size: 12, weight: .black))
          .foregroundStyle(KaidoTheme.routeWhite)

        Text(readinessDetail)
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(KaidoTheme.muted)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 0)
    }
    .padding(12)
    .background(readinessColor.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 13))
    .overlay {
      RoundedRectangle(cornerRadius: 13)
        .stroke(readinessColor.opacity(0.3), lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("voice-check-status")
    .accessibilityLabel("\(readinessTitle)。\(readinessDetail)")
  }

  private var auditionButton: some View {
    Button {
      model.audition(isVehicleMoving: !isParked)
    } label: {
      HStack(spacing: 9) {
        Image(systemName: auditionSymbol)
        Text(auditionTitle)
        Spacer()
        Text("PARKED")
          .font(.system(size: 8, weight: .black, design: .monospaced))
          .tracking(0.45)
      }
      .font(.system(size: 14, weight: .black, design: .rounded))
      .foregroundStyle(KaidoTheme.asphalt)
      .padding(.horizontal, 14)
      .frame(height: 47)
      .background(KaidoTheme.signalAmber)
      .clipShape(RoundedRectangle(cornerRadius: 13))
    }
    .buttonStyle(.plain)
    .disabled(!canAudition)
    .opacity(canAudition ? 1 : 0.55)
    .accessibilityHint("只播放固定样句，不会开始导航或消耗导航提示")
    .accessibilityIdentifier("voice-check-audition")
  }

  private var authorityBoundary: some View {
    Label(
      "试听没有路线、位置或提示权限；偏好只在真正的导航播报到达后决定使用哪个已安装音色。",
      systemImage: "lock.shield"
    )
    .font(.system(size: 9, weight: .medium))
    .foregroundStyle(KaidoTheme.muted)
    .fixedSize(horizontal: false, vertical: true)
  }

  private var auditionStatus: some View {
    HStack(alignment: .top, spacing: 8) {
      Circle()
        .fill(accentColor)
        .frame(width: 6, height: 6)
        .padding(.top, 3)

      Text(model.statusDetail)
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .foregroundStyle(accentColor)
        .fixedSize(horizontal: false, vertical: true)

      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("voice-check-audition-status")
  }

  @ViewBuilder
  private func voiceMenuLabel(
    title: String,
    detail: String,
    isSelected: Bool
  ) -> some View {
    Label {
      Text("\(title) · \(detail)")
    } icon: {
      Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
    }
  }

  private var selectionTitle: String {
    if let selectedProfile = model.selectedProfile {
      return selectedProfile.name
    }
    return "自动选择最高质量"
  }

  private var selectionDetail: String {
    if let selectedProfile = model.selectedProfile {
      return selectedProfile.quality.label
    }
    guard let profile = model.effectiveProfile else {
      return "VOICE CATALOG LOADING"
    }
    return "AUTO · \(profile.name) · \(profile.quality.label)"
  }

  private var selectionDetailColor: Color {
    model.effectiveProfile?.quality.isHigherQuality == true
      ? KaidoTheme.confirmedGreen
      : KaidoTheme.evidenceCoral
  }

  private var readinessTitle: String {
    if model.effectiveProfile?.quality.isHigherQuality == true {
      return "高质量日语声音已安装"
    }
    if model.profiles.isEmpty {
      return "等待系统列出日语声音"
    }
    return "当前只能使用系统默认音质"
  }

  private var readinessDetail: String {
    if model.effectiveProfile?.quality.isHigherQuality == true {
      return "实际音质仍需在这台 iPhone 上试听确认。"
    }
    return
      "要减少机器感，请先在 iPhone“设置 → 辅助功能 → 朗读内容 → 声音 → 日语”下载增强或高级声音，再回到这里试听。"
  }

  private var readinessSymbol: String {
    model.effectiveProfile?.quality.isHigherQuality == true
      ? "checkmark.seal.fill"
      : "arrow.down.circle.fill"
  }

  private var readinessColor: Color {
    model.effectiveProfile?.quality.isHigherQuality == true
      ? KaidoTheme.confirmedGreen
      : KaidoTheme.evidenceCoral
  }

  private var auditionTitle: String {
    guard isParked else { return "行驶中不可试听" }
    return switch model.state {
    case .preparing:
      "正在准备"
    case .speaking:
      "正在试听"
    case .completed:
      "再次试听导航声音"
    case .ready, .blocked:
      "试听导航声音"
    }
  }

  private var auditionSymbol: String {
    guard isParked else { return "car.fill" }
    return switch model.state {
    case .preparing:
      "hourglass"
    case .speaking:
      "waveform"
    case .ready, .completed, .blocked:
      "speaker.wave.2.fill"
    }
  }

  private var accentColor: Color {
    switch model.state {
    case .completed:
      KaidoTheme.confirmedGreen
    case .blocked:
      KaidoTheme.evidenceCoral
    case .ready, .preparing, .speaking:
      KaidoTheme.signalAmber
    }
  }

  private var accessibilityValue: String {
    "\(model.statusLabel)；\(selectionTitle)；\(selectionDetail)"
  }

  private var canAudition: Bool {
    isParked && model.canAudition
  }
}

private struct SoundCheckRail: View {
  let isActive: Bool
  let color: Color

  private let levels: [CGFloat] = [
    0.35, 0.72, 0.5, 1, 0.62, 0.86, 0.42,
  ]

  var body: some View {
    HStack(alignment: .center, spacing: 3) {
      ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
        Capsule()
          .fill(color.opacity(isActive ? 1 : 0.42))
          .frame(width: 3, height: 30 * level)
          .scaleEffect(y: isActive && index.isMultiple(of: 2) ? 1.12 : 1)
      }
    }
    .frame(width: 39, height: 34)
    .accessibilityHidden(true)
  }
}

extension GuidanceVoiceSetupState {
  fileprivate var isAuditionActive: Bool {
    switch self {
    case .preparing, .speaking:
      true
    case .ready, .completed, .blocked:
      false
    }
  }

  fileprivate var showsAuditionDetail: Bool {
    switch self {
    case .ready:
      false
    case .preparing, .speaking, .completed, .blocked:
      true
    }
  }
}
