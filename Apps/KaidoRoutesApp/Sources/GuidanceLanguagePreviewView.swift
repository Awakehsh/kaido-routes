import KaidoDomain
import SwiftUI

struct GuidanceLanguagePreviewPanel: View {
  @ObservedObject var model: GuidanceLanguagePreviewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header
      interfaceSelector
      physicalSignPreview
      voiceSelector
      spokenPreview

      if let lastErrorCode = model.lastErrorCode {
        Text(verbatim: lastErrorCode)
          .font(.system(size: 9, weight: .bold, design: .monospaced))
          .foregroundStyle(KaidoTheme.evidenceCoral)
          .accessibilityLabel("语言设置错误：\(lastErrorCode)")
      }
    }
    .padding(16)
    .background(KaidoTheme.instrument)
    .clipShape(RoundedRectangle(cornerRadius: 22))
    .overlay {
      RoundedRectangle(cornerRadius: 22)
        .stroke(KaidoTheme.signalAmber.opacity(0.42), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
  }

  private var header: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 3) {
        Text("语言与标志")
          .font(.system(size: 19, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)

        Text("GUIDANCE PREVIEW · SYNTHETIC")
          .font(.system(size: 9, weight: .bold, design: .monospaced))
          .tracking(0.75)
          .foregroundStyle(KaidoTheme.muted)

        Text("界面说明与引导语音可以独立选择")
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(KaidoTheme.muted)
      }

      Spacer()

      StatusCapsule(
        title: "独立选择",
        color: KaidoTheme.signalAmber
      )
    }
  }

  private var interfaceSelector: some View {
    LanguageSelector(
      title: "导航界面语言",
      selectedLocale: model.selection.interfaceLocale,
      accent: KaidoTheme.positionCyan,
      action: model.selectInterfaceLocale
    )
  }

  private var voiceSelector: some View {
    LanguageSelector(
      title: "引导语音语言",
      selectedLocale: model.selection.guidanceVoiceLocale,
      accent: KaidoTheme.signalAmber,
      action: model.selectGuidanceVoiceLocale
    )
  }

  private var physicalSignPreview: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .center, spacing: 12) {
        ForEach(model.projection.iPhone.routeShields, id: \.self) { shield in
          Text(verbatim: shield)
            .font(.system(size: 18, weight: .black, design: .rounded))
            .foregroundStyle(KaidoTheme.asphalt)
            .frame(width: 44, height: 34)
            .background(KaidoTheme.signalAmber)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .accessibilityLabel("路线盾牌 \(shield)")
        }

        VStack(alignment: .leading, spacing: 2) {
          Text("日本道路标志目标")
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(KaidoTheme.signalAmber)

          Text(verbatim: model.projection.iPhone.japaneseSignText)
            .font(.system(size: 17, weight: .black, design: .rounded))
            .foregroundStyle(KaidoTheme.routeWhite)
        }

        Spacer(minLength: 4)
      }

      Divider()
        .overlay(KaidoTheme.steel)

      VStack(alignment: .leading, spacing: 4) {
        Text(localeLabel(model.selection.interfaceLocale))
          .font(.system(size: 8, weight: .black, design: .monospaced))
          .foregroundStyle(KaidoTheme.positionCyan)

        Text(model.projection.iPhone.localizedDisplayText)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(KaidoTheme.routeWhite)

        Text(model.projection.iPhone.localizedDecisionPointName)
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(KaidoTheme.muted)
      }
    }
    .padding(13)
    .background(KaidoTheme.asphalt.opacity(0.5))
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .stroke(KaidoTheme.steel.opacity(0.8), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
  }

  private var spokenPreview: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "speaker.slash.fill")
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(KaidoTheme.signalAmber)
        .frame(width: 28)

      VStack(alignment: .leading, spacing: 4) {
        Text("TEXT PREVIEW · AUDIO NOT CONNECTED")
          .font(.system(size: 8, weight: .black, design: .monospaced))
          .tracking(0.45)
          .foregroundStyle(KaidoTheme.signalAmber)

        Text(model.projection.voice.spokenText)
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(KaidoTheme.routeWhite)

        Text(verbatim: model.projection.voice.locale.rawValue)
          .font(.system(size: 9, weight: .medium, design: .monospaced))
          .foregroundStyle(KaidoTheme.muted)
      }

      Spacer(minLength: 4)
    }
    .padding(12)
    .background(KaidoTheme.signalAmber.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 13))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "引导语音文本预览，尚未连接音频，"
        + "\(model.projection.voice.spokenText)"
    )
  }

  private func localeLabel(_ locale: KaidoReleaseLocale) -> String {
    switch locale {
    case .japanese:
      "日本語 EXPLANATION"
    case .simplifiedChinese:
      "简体中文 EXPLANATION"
    case .english:
      "ENGLISH EXPLANATION"
    }
  }
}

private struct LanguageSelector: View {
  let title: String
  let selectedLocale: KaidoReleaseLocale
  let accent: Color
  let action: (KaidoReleaseLocale) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 10, weight: .black, design: .monospaced))
        .tracking(0.55)
        .foregroundStyle(accent)

      HStack(spacing: 6) {
        ForEach(KaidoReleaseLocale.allCases, id: \.self) { locale in
          Button {
            action(locale)
          } label: {
            Text(buttonLabel(locale))
              .font(.system(size: 10, weight: .bold))
              .frame(maxWidth: .infinity)
              .frame(height: 36)
              .foregroundStyle(
                selectedLocale == locale
                  ? KaidoTheme.asphalt
                  : KaidoTheme.muted
              )
              .background(
                selectedLocale == locale
                  ? accent
                  : KaidoTheme.asphalt.opacity(0.55)
              )
              .clipShape(RoundedRectangle(cornerRadius: 9))
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(
            selectedLocale == locale ? .isSelected : []
          )
          .accessibilityLabel("\(title)，\(accessibilityLabel(locale))")
        }
      }
    }
  }

  private func buttonLabel(_ locale: KaidoReleaseLocale) -> String {
    switch locale {
    case .japanese:
      "日本語"
    case .simplifiedChinese:
      "简体中文"
    case .english:
      "English"
    }
  }

  private func accessibilityLabel(_ locale: KaidoReleaseLocale) -> String {
    switch locale {
    case .japanese:
      "日语"
    case .simplifiedChinese:
      "简体中文"
    case .english:
      "英语"
    }
  }
}
