import KaidoAppleAdapters
import KaidoDomain
import SwiftUI

struct GuidanceVoiceSetupPanel: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale
  @ObservedObject var model: GuidanceVoiceSetupModel
  @ObservedObject var audioSourceModel: GuidanceAudioSourceSetupModel
  let releasedEntry: BundledProductReleaseEntry?
  let isParked: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 15) {
      header
      guidanceLanguageSelection
      if releasedEntry != nil {
        audioSourceSelection
      }
      sampleMonitor
      voiceSelection
      readiness
      if let recommendedUpgradeProfile =
        model.recommendedUpgradeProfile
      {
        recommendedUpgrade(recommendedUpgradeProfile)
      }
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
      audioSourceModel.configure(for: releasedEntry)
      model.refreshProfiles()
    }
    .onChange(of: releasedEntry?.release.releaseID) {
      audioSourceModel.configure(for: releasedEntry)
    }
    .onDisappear {
      model.stop()
    }
  }

  private var audioSourceSelection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(
        copy.resolve(
          japanese: "ナビ音色",
          simplifiedChinese: "导航音色",
          english: "GUIDANCE VOICE STYLE"
        )
      )
      .font(.system(size: 9, weight: .black, design: .monospaced))
      .tracking(0.65)
      .foregroundStyle(KaidoTheme.muted)

      Menu {
        Button {
          audioSourceModel.select(selectionID: nil)
        } label: {
          voiceMenuLabel(
            title: deviceVoiceTitle,
            detail: "APPLE · INSTALLED",
            isSelected: audioSourceModel.usesDeviceVoice
          )
        }

        ForEach(
          audioSourceModel.choices,
          id: \.selectionID
        ) { choice in
          Button {
            audioSourceModel.select(
              selectionID: choice.selectionID
            )
          } label: {
            voiceMenuLabel(
              title: displayName(choice.displayName),
              detail: "REVIEWED · OFFLINE",
              isSelected:
                audioSourceModel.selectedSelectionID
                == choice.selectionID
            )
          }
        }
      } label: {
        HStack(spacing: 11) {
          Image(systemName: "waveform.badge.plus")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(KaidoTheme.positionCyan)
            .frame(width: 25)

          VStack(alignment: .leading, spacing: 2) {
            Text(audioSourceTitle)
              .font(.system(size: 13, weight: .black))
              .foregroundStyle(KaidoTheme.routeWhite)

            Text(audioSourceDetail)
              .font(.system(size: 8, weight: .black, design: .monospaced))
              .foregroundStyle(KaidoTheme.positionCyan)
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
      .disabled(!isParked)
      .opacity(isParked ? 1 : 0.55)
      .accessibilityLabel(
        copy.resolve(
          japanese: "ナビ音色を選択",
          simplifiedChinese: "选择导航音色",
          english: "Choose guidance voice style"
        )
      )
      .accessibilityValue("\(audioSourceTitle)，\(audioSourceDetail)")
      .accessibilityIdentifier("voice-check-audio-source-menu")

      Text(
        copy.resolve(
          japanese:
            "端末音声または完全審査済みのオフライン音色を停車中に選びます。選択はナビ開始時に固定されます。",
          simplifiedChinese:
            "停车时可选择设备声音或已完整审核的离线音色；启程后本次导航会冻结该选择。",
          english:
            "Choose the device voice or a fully reviewed offline voice while parked. Navigation freezes the choice when it starts."
        )
      )
      .font(.system(size: 9, weight: .medium))
      .foregroundStyle(KaidoTheme.muted)
      .fixedSize(horizontal: false, vertical: true)

      if let code = audioSourceModel.lastErrorCode {
        Text(code)
          .font(.system(size: 8, weight: .bold, design: .monospaced))
          .foregroundStyle(KaidoTheme.evidenceCoral)
      }
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text(
          copy.resolve(
            japanese: "ナビ音声の確認",
            simplifiedChinese: "导航声音确认",
            english: "Navigation voice check"
          )
        )
        .font(.system(size: 19, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.routeWhite)

        Text("PARKED SOUND CHECK · \(model.languageCode.uppercased())")
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

  private var guidanceLanguageSelection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(
        copy.resolve(
          japanese: "ナビ音声の言語",
          simplifiedChinese: "导航声音语言",
          english: "GUIDANCE VOICE LANGUAGE"
        )
      )
      .font(.system(size: 9, weight: .black, design: .monospaced))
      .tracking(0.65)
      .foregroundStyle(KaidoTheme.muted)

      HStack(spacing: 5) {
        ForEach(KaidoReleaseLocale.allCases, id: \.self) { locale in
          Button {
            model.selectGuidanceLocale(locale)
          } label: {
            Text(locale.interfaceLanguageCode)
              .font(.system(size: 10, weight: .black, design: .monospaced))
              .frame(maxWidth: .infinity)
              .frame(height: 34)
              .foregroundStyle(
                model.selectedGuidanceLocale == locale
                  ? KaidoTheme.asphalt
                  : KaidoTheme.muted
              )
              .background(
                model.selectedGuidanceLocale == locale
                  ? KaidoTheme.signalAmber
                  : KaidoTheme.asphalt.opacity(0.48)
              )
              .clipShape(RoundedRectangle(cornerRadius: 9))
          }
          .buttonStyle(.plain)
          .accessibilityLabel(copy.languageName(locale))
          .accessibilityAddTraits(
            model.selectedGuidanceLocale == locale ? .isSelected : []
          )
          .accessibilityIdentifier(
            "voice-check-language-\(locale.rawValue)"
          )
        }
      }
      .padding(4)
      .background(KaidoTheme.asphalt.opacity(0.4))
      .clipShape(RoundedRectangle(cornerRadius: 12))

      Text(
        copy.resolve(
          japanese: "画面表示と言語案内は別々に選べます。",
          simplifiedChinese: "界面语言与导航声音可分别选择。",
          english: "Interface and guidance voice languages are selected independently."
        )
      )
      .font(.system(size: 9, weight: .medium))
      .foregroundStyle(KaidoTheme.muted)
    }
  }

  private var sampleMonitor: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label(
          copy.resolve(
            japanese: "端末音声の固定例文",
            simplifiedChinese: "设备声音固定样句",
            english: "DEVICE VOICE SAMPLE"
          ),
          systemImage: "waveform"
        )
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
          .accessibilityIdentifier("voice-check-sample")
          .accessibilityValue(model.auditionText)
      }
    }
    .padding(13)
    .background(KaidoTheme.asphalt.opacity(0.5))
    .clipShape(RoundedRectangle(cornerRadius: 14))
  }

  private var voiceSelection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(
        copy.resolve(
          japanese: "インストール済み音声",
          simplifiedChinese: "设备已安装声音",
          english: "INSTALLED DEVICE VOICES"
        )
      )
      .font(.system(size: 9, weight: .black, design: .monospaced))
      .tracking(0.65)
      .foregroundStyle(KaidoTheme.muted)

      Menu {
        Button {
          model.selectVoice(identifier: nil)
        } label: {
          voiceMenuLabel(
            title: automaticSelectionTitle,
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
      .accessibilityLabel(
        copy.resolve(
          japanese:
            "インストール済みの\(copy.languageName(model.selectedGuidanceLocale))ナビ音声を選択",
          simplifiedChinese:
            "选择已安装的\(copy.languageName(model.selectedGuidanceLocale))导航声音",
          english:
            "Choose an installed \(copy.languageName(model.selectedGuidanceLocale)) guidance voice"
        )
      )
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

  private func recommendedUpgrade(
    _ profile: GuidanceSpeechVoiceProfile
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Label {
        VStack(alignment: .leading, spacing: 2) {
          Text(
            copy.resolve(
              japanese: "高品質の音声を試せます",
              simplifiedChinese: "可以试听更高质量的声音",
              english: "Try a higher-quality voice"
            )
          )
          .font(.system(size: 12, weight: .black))

          Text("\(profile.name) · \(profile.quality.label)")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
        }
      } icon: {
        Image(systemName: "sparkles")
      }
      .foregroundStyle(KaidoTheme.signalAmber)

      Text(
        copy.resolve(
          japanese:
            "現在のナビ音声は変更せずに候補を試聴します。聞き終えてから明示的に使用してください。",
          simplifiedChinese:
            "先试听候选声音，不会改变当前导航声音；听完后再明确启用。",
          english:
            "Audition the candidate without changing navigation. Enable it explicitly only after listening."
        )
      )
      .font(.system(size: 10, weight: .medium))
      .foregroundStyle(KaidoTheme.muted)
      .fixedSize(horizontal: false, vertical: true)

      Button {
        model.auditionRecommendedUpgrade(
          isVehicleMoving: !isParked
        )
      } label: {
        Label(
          upgradeAuditionTitle(profile),
          systemImage: "speaker.wave.2.fill"
        )
        .font(.system(size: 12, weight: .black))
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .foregroundStyle(KaidoTheme.routeWhite)
        .background(KaidoTheme.positionCyan.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 11))
      }
      .buttonStyle(.plain)
      .disabled(!isParked || !model.canAudition)
      .opacity(isParked && model.canAudition ? 1 : 0.55)
      .accessibilityIdentifier("voice-check-upgrade-audition")

      if model.canUseLastAuditionedUpgrade {
        Button {
          model.useLastAuditionedUpgrade()
        } label: {
          Label(
            copy.resolve(
              japanese: "この音声をナビで使用",
              simplifiedChinese: "在导航中使用这个声音",
              english: "Use this voice for navigation"
            ),
            systemImage: "checkmark.seal.fill"
          )
          .font(.system(size: 12, weight: .black))
          .frame(maxWidth: .infinity)
          .frame(height: 40)
          .foregroundStyle(KaidoTheme.asphalt)
          .background(KaidoTheme.confirmedGreen)
          .clipShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("voice-check-upgrade-confirm")
      }
    }
    .padding(12)
    .background(KaidoTheme.signalAmber.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 13))
    .overlay {
      RoundedRectangle(cornerRadius: 13)
        .stroke(KaidoTheme.signalAmber.opacity(0.35), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("voice-check-upgrade")
  }

  private var auditionButton: some View {
    Button {
      model.audition(isVehicleMoving: !isParked)
    } label: {
      HStack(spacing: 9) {
        Image(systemName: auditionSymbol)
        Text(auditionTitle)
        Spacer()
        Text(
          copy.resolve(
            japanese: "停車中",
            simplifiedChinese: "停车",
            english: "PARKED"
          )
        )
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
    .accessibilityHint(
      copy.resolve(
        japanese: "固定例文だけを再生し、ナビ開始や案内プロンプトの消費は行いません",
        simplifiedChinese: "只播放固定样句，不会开始导航或消耗导航提示",
        english:
          "Plays only the fixed sample; it does not start navigation or consume a guidance prompt"
      )
    )
    .accessibilityIdentifier("voice-check-audition")
  }

  private var authorityBoundary: some View {
    Label(
      copy.resolve(
        japanese:
          "試聴には経路・位置・案内権限がありません。ここでは端末音声だけを試聴します。オフライン音色は完全な審査済みリリースだけが選択肢に表示されます。",
        simplifiedChinese:
          "试听没有路线、位置或提示权限；这里仅试听设备声音。离线音色只有在整套语料完整审核并随版本发布后才会出现在选项中。",
        english:
          "Audition has no route, location, or prompt authority and previews only the device voice. Offline styles appear only as complete reviewed releases."
      ),
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

      Text(auditionStatusDetail)
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
    return automaticSelectionTitle
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
      return copy.resolve(
        japanese:
          "高品質の\(copy.languageName(model.selectedGuidanceLocale))音声をインストール済み",
        simplifiedChinese:
          "高质量\(copy.languageName(model.selectedGuidanceLocale))声音已安装",
        english:
          "High-quality \(copy.languageName(model.selectedGuidanceLocale)) voice installed"
      )
    }
    if model.recommendedUpgradeProfile != nil {
      return copy.resolve(
        japanese: "高品質の候補がインストール済み",
        simplifiedChinese: "已安装更高质量的候选声音",
        english: "A higher-quality candidate is installed"
      )
    }
    if model.profiles.isEmpty {
      return copy.resolve(
        japanese:
          "\(copy.languageName(model.selectedGuidanceLocale))音声の一覧を待っています",
        simplifiedChinese:
          "等待系统列出\(copy.languageName(model.selectedGuidanceLocale))声音",
        english:
          "Waiting for installed \(copy.languageName(model.selectedGuidanceLocale)) voices"
      )
    }
    return copy.resolve(
      japanese: "現在はシステム標準品質のみ",
      simplifiedChinese: "当前只能使用系统默认音质",
      english: "Only default system quality is available"
    )
  }

  private var readinessDetail: String {
    if model.effectiveProfile?.quality.isHigherQuality == true {
      return copy.resolve(
        japanese: "実際の音質はこの iPhone で試聴して確認してください。",
        simplifiedChinese: "实际音质仍需在这台 iPhone 上试听确认。",
        english: "Audition the voice on this iPhone to confirm its actual quality."
      )
    }
    if let recommendedUpgradeProfile =
      model.recommendedUpgradeProfile
    {
      return copy.resolve(
        japanese:
          "\(recommendedUpgradeProfile.name) を現在の設定を変えずに試聴し、確認後に使用できます。",
        simplifiedChinese:
          "可以先试听 \(recommendedUpgradeProfile.name)，当前设置不会改变；确认后再启用。",
        english:
          "Audition \(recommendedUpgradeProfile.name) without changing the current setting, then enable it after confirmation."
      )
    }
    return copy.resolve(
      japanese:
        "現在の DEFAULT は基本音声です。速度調整では高品質音声にはなりません。"
        + "機械的な響きを減らすには、iPhone の「設定 → アクセシビリティ → 読み上げコンテンツ → 声 → "
        + "\(copy.languageName(model.selectedGuidanceLocale))」で拡張またはプレミアム音声をダウンロードし、"
        + "ここに戻って試聴してください。",
      simplifiedChinese:
        "当前 DEFAULT 是基础声线，调整语速不能把它变成高级音色。"
        + "要减少机器感，请先在 iPhone“设置 → 辅助功能 → 朗读内容 → 声音 → "
        + "\(copy.languageName(model.selectedGuidanceLocale))”下载增强或高级声音，"
        + "再回到这里试听。",
      english:
        "DEFAULT is the basic voice; changing its rate cannot turn it into a higher-quality voice. "
        + "To reduce the synthetic sound, open iPhone Settings → Accessibility → Spoken Content → Voices → "
        + "\(copy.languageName(model.selectedGuidanceLocale)), download an enhanced or premium voice, "
        + "then return here to audition it."
    )
  }

  private var readinessSymbol: String {
    if model.recommendedUpgradeProfile != nil {
      return "sparkles"
    }
    return model.effectiveProfile?.quality.isHigherQuality == true
      ? "checkmark.seal.fill"
      : "arrow.down.circle.fill"
  }

  private var readinessColor: Color {
    if model.recommendedUpgradeProfile != nil {
      return KaidoTheme.signalAmber
    }
    return model.effectiveProfile?.quality.isHigherQuality == true
      ? KaidoTheme.confirmedGreen
      : KaidoTheme.evidenceCoral
  }

  private var auditionTitle: String {
    guard isParked else {
      return copy.resolve(
        japanese: "走行中は試聴できません",
        simplifiedChinese: "行驶中不可试听",
        english: "Audition unavailable while moving"
      )
    }
    return switch model.state {
    case .preparing:
      copy.resolve(
        japanese: "準備中",
        simplifiedChinese: "正在准备",
        english: "Preparing"
      )
    case .speaking:
      copy.resolve(
        japanese: "再生中",
        simplifiedChinese: "正在试听",
        english: "Playing sample"
      )
    case .completed:
      copy.resolve(
        japanese: "端末音声をもう一度試聴",
        simplifiedChinese: "再次试听设备声音",
        english: "Audition device voice again"
      )
    case .ready, .blocked:
      copy.resolve(
        japanese: "現在の端末音声を試聴",
        simplifiedChinese: "试听当前设备声音",
        english: "Audition current device voice"
      )
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

  private var automaticSelectionTitle: String {
    copy.resolve(
      japanese: "最高品質を自動選択",
      simplifiedChinese: "自动选择最高质量",
      english: "Automatically select highest quality"
    )
  }

  private var deviceVoiceTitle: String {
    copy.resolve(
      japanese: "端末音声",
      simplifiedChinese: "设备声音",
      english: "Device voice"
    )
  }

  private var audioSourceTitle: String {
    guard let choice = audioSourceModel.selectedChoice else {
      return deviceVoiceTitle
    }
    return displayName(choice.displayName)
  }

  private var audioSourceDetail: String {
    audioSourceModel.selectedChoice == nil
      ? "APPLE · INSTALLED"
      : "REVIEWED · OFFLINE"
  }

  private func displayName(
    _ name: AppBundleGuidanceAudioDisplayName
  ) -> String {
    switch interfaceLocale {
    case .japanese:
      name.japanese
    case .simplifiedChinese:
      name.simplifiedChinese
    case .english:
      name.english
    }
  }

  private func upgradeAuditionTitle(
    _ profile: GuidanceSpeechVoiceProfile
  ) -> String {
    let auditioned =
      model.lastAuditionedProfile?.identifier == profile.identifier
    return copy.resolve(
      japanese: auditioned
        ? "\(profile.name) をもう一度試聴"
        : "\(profile.name) を試聴",
      simplifiedChinese: auditioned
        ? "再次试听 \(profile.name)"
        : "试听 \(profile.name)",
      english: auditioned
        ? "Audition \(profile.name) again"
        : "Audition \(profile.name)"
    )
  }

  private var auditionStatusDetail: String {
    switch model.state {
    case .ready:
      copy.resolve(
        japanese: "停車中に固定例文を試聴します。ナビ案内は消費しません。",
        simplifiedChinese: "停车后试听固定样句，不会消耗导航提示。",
        english:
          "Audition the fixed sample while parked; no navigation prompt is consumed."
      )
    case .preparing:
      copy.resolve(
        japanese:
          "インストール済みの\(copy.languageName(model.selectedGuidanceLocale))音声を確認中です。",
        simplifiedChinese:
          "正在解析设备已安装的\(copy.languageName(model.selectedGuidanceLocale))音色。",
        english:
          "Resolving installed \(copy.languageName(model.selectedGuidanceLocale)) voices."
      )
    case .speaking(let profile):
      "\(profile.name) · \(profile.quality.label)"
    case .completed(let profile):
      copy.resolve(
        japanese: "試聴済み \(profile.name) · \(profile.quality.label)",
        simplifiedChinese: "已试听 \(profile.name) · \(profile.quality.label)",
        english: "Auditioned \(profile.name) · \(profile.quality.label)"
      )
    case .blocked(let code):
      code
    }
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
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
