import AppIntents
import KaidoAppleAdapters
import KaidoDomain
import SwiftUI

extension GuidanceSpeechMode {
  func title(in locale: KaidoReleaseLocale) -> String {
    let copy = KaidoInterfaceText(locale: locale)
    switch self {
    case .full:
      return copy.resolve(japanese: "すべての案内", simplifiedChinese: "全部播报", english: "Full guidance")
    case .concise:
      return copy.resolve(japanese: "簡潔な案内", simplifiedChinese: "简洁播报", english: "Concise guidance")
    case .muted:
      return copy.resolve(japanese: "消音", simplifiedChinese: "静音", english: "Muted")
    }
  }
}

extension GuidanceSpeechVolume {
  func title(in locale: KaidoReleaseLocale) -> String {
    let copy = KaidoInterfaceText(locale: locale)
    switch self {
    case .soft: return copy.resolve(japanese: "小さめ", simplifiedChinese: "较轻", english: "Softer")
    case .normal: return copy.resolve(japanese: "標準", simplifiedChinese: "标准", english: "Normal")
    case .loud: return copy.resolve(japanese: "大きめ", simplifiedChinese: "较响", english: "Louder")
    }
  }
}

struct WholeShutoVoiceSettingsView: View {
  @ObservedObject var model: WholeShutoProductModel
  @ObservedObject var languages: KaidoLanguageSettingsModel
  @StateObject private var voice: GuidanceVoiceSetupModel

  init(model: WholeShutoProductModel, languages: KaidoLanguageSettingsModel) {
    self.model = model
    self.languages = languages
    _voice = StateObject(wrappedValue: GuidanceVoiceSetupModel(
      guidanceLocale: languages.guidanceVoiceLocale,
      output: AppGuidanceSpeechOutputFactory.makeAudition()
    ))
  }

  var body: some View {
    Form {
      Section {
        ShortcutsLink()
        Text(copy.resolve(
          japanese: "Siri で案内の消音、周回数の変更、休憩と再開を操作できます。",
          simplifiedChinese: "可通过 Siri 静音、调整圈数、休息和继续导航。",
          english: "Use Siri to mute guidance, change laps, take a break, or resume navigation."
        ))
        .font(.footnote)
      }
      Section {
        Picker(copy.resolve(japanese: "案内", simplifiedChinese: "播报方式", english: "Guidance"), selection: Binding(
          get: { model.speechMode }, set: { model.setSpeechMode($0) }
        )) {
          ForEach(GuidanceSpeechMode.allCases, id: \.self) { mode in
            Text(mode.title(in: languages.interfaceLocale)).tag(mode)
          }
        }
        .accessibilityIdentifier("whole-shuto-speech-mode")
        Picker(copy.resolve(japanese: "音量", simplifiedChinese: "播报音量", english: "Voice volume"), selection: Binding(
          get: { model.speechVolume }, set: { model.setSpeechVolume($0) }
        )) {
          ForEach(GuidanceSpeechVolume.allCases, id: \.self) { volume in
            Text(volume.title(in: languages.interfaceLocale)).tag(volume)
          }
        }
        .accessibilityIdentifier("whole-shuto-speech-volume")
      } footer: {
        Text(copy.resolve(
          japanese: "簡潔な案内では予告と本線継続の確認を減らし、分岐と一般道の案内を残します。",
          simplifiedChinese: "简洁播报减少提前提醒和主线确认，保留分岔与普通道路引导。",
          english: "Concise guidance reduces advance reminders and mainline confirmations while keeping junction and ordinary-road directions."
        ))
      }

      Section {
        LabeledContent(copy.resolve(japanese: "言語", simplifiedChinese: "语音语言", english: "Voice language"),
          value: languages.guidanceVoiceLocale.nativeLanguageName)
        Picker(copy.resolve(japanese: "声", simplifiedChinese: "声音", english: "Voice"), selection: Binding(
          get: { voice.selectedVoiceIdentifier ?? "" },
          set: { voice.selectVoice(identifier: $0.isEmpty ? nil : $0) }
        )) {
          Text(copy.resolve(japanese: "システム標準", simplifiedChinese: "系统默认", english: "System default")).tag("")
          ForEach(voice.profiles, id: \.identifier) { profile in
            Text(profile.name).tag(profile.identifier)
          }
        }
        .accessibilityIdentifier("whole-shuto-installed-voice")
        Text(voice.auditionText).font(.body)
        Button {
          voice.audition()
        } label: {
          Label(copy.resolve(japanese: "声を試す", simplifiedChinese: "试听声音", english: "Preview voice"),
            systemImage: "speaker.wave.2")
        }
        .disabled(!voice.canAudition)
        .accessibilityIdentifier("whole-shuto-voice-audition")
        if case .speaking = voice.state {
          Button(copy.resolve(japanese: "停止", simplifiedChinese: "停止试听", english: "Stop preview")) { voice.stop() }
        }
        if case .completed = voice.state {
          Text(copy.resolve(japanese: "再生完了", simplifiedChinese: "试听完成", english: "Preview finished"))
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("whole-shuto-voice-audition-complete")
        }
        if case .blocked = voice.state {
          Text(copy.resolve(
            japanese: "声を再生できません。端末の音量と利用可能な声を確認してください。",
            simplifiedChinese: "无法播放声音，请检查设备音量和已安装的声音。",
            english: "Voice preview is unavailable. Check device volume and installed voices."
          ))
          .foregroundStyle(.secondary)
        }
        Button(copy.resolve(japanese: "声の一覧を更新", simplifiedChinese: "刷新声音列表", english: "Refresh voices")) {
          voice.refreshProfiles()
        }
      } footer: {
        Text(copy.resolve(
          japanese: "端末にインストール済みの声を使用します。",
          simplifiedChinese: "使用设备已安装的声音。",
          english: "Uses voices installed on this device."
        ))
      }
    }
    .navigationTitle(copy.resolve(japanese: "声と案内", simplifiedChinese: "声音与播报", english: "Voice and guidance"))
    .onAppear { voice.refreshProfiles() }
    .onChange(of: languages.guidanceVoiceLocale) { _, locale in voice.selectGuidanceLocale(locale) }
    .onDisappear { voice.stop() }
  }

  private var copy: KaidoInterfaceText { KaidoInterfaceText(locale: languages.interfaceLocale) }
}
