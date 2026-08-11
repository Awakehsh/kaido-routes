import Combine
import Foundation
import KaidoDomain
import KaidoPresentation

@MainActor
protocol KaidoLanguagePreferenceStoring: AnyObject {
  func interfaceLocale() -> KaidoReleaseLocale?
  func guidanceVoiceLocale() -> KaidoReleaseLocale?
  func setInterfaceLocale(_ locale: KaidoReleaseLocale)
  func setGuidanceVoiceLocale(_ locale: KaidoReleaseLocale)
}

@MainActor
final class UserDefaultsKaidoLanguagePreferenceStore:
  KaidoLanguagePreferenceStoring
{
  private let defaults: UserDefaults
  private let interfaceLocaleKey: String
  private let guidanceVoiceLocaleKey: String

  init(
    defaults: UserDefaults = .standard,
    keyPrefix: String = "app.kaidoroutes.language"
  ) {
    self.defaults = defaults
    interfaceLocaleKey = "\(keyPrefix).interface"
    guidanceVoiceLocaleKey = "\(keyPrefix).guidance-voice"
  }

  func interfaceLocale() -> KaidoReleaseLocale? {
    locale(forKey: interfaceLocaleKey)
  }

  func guidanceVoiceLocale() -> KaidoReleaseLocale? {
    locale(forKey: guidanceVoiceLocaleKey)
  }

  func setInterfaceLocale(_ locale: KaidoReleaseLocale) {
    defaults.set(locale.rawValue, forKey: interfaceLocaleKey)
  }

  func setGuidanceVoiceLocale(_ locale: KaidoReleaseLocale) {
    defaults.set(locale.rawValue, forKey: guidanceVoiceLocaleKey)
  }

  private func locale(forKey key: String) -> KaidoReleaseLocale? {
    guard
      let rawValue = defaults.string(forKey: key),
      let locale = KaidoReleaseLocale(rawValue: rawValue)
    else {
      return nil
    }
    return locale
  }
}

@MainActor
final class KaidoLanguageSettingsModel: ObservableObject {
  @Published private(set) var interfaceLocale: KaidoReleaseLocale
  @Published private(set) var guidanceVoiceLocale: KaidoReleaseLocale

  private let store: any KaidoLanguagePreferenceStoring

  init(
    store: any KaidoLanguagePreferenceStoring =
      UserDefaultsKaidoLanguagePreferenceStore(),
    preferredLanguages: [String] = Locale.preferredLanguages
  ) {
    self.store = store
    interfaceLocale =
      store.interfaceLocale()
      ?? KaidoReleaseLocale.matchingPreferredLanguage(preferredLanguages)
    // Sign text on the Shuto Expressway is Japanese, so spoken guidance
    // defaults to Japanese whatever the interface language is.
    guidanceVoiceLocale = store.guidanceVoiceLocale() ?? .japanese
  }

  func selectInterfaceLocale(_ locale: KaidoReleaseLocale) {
    store.setInterfaceLocale(locale)
    guard locale != interfaceLocale else { return }
    interfaceLocale = locale
  }

  func selectGuidanceVoiceLocale(_ locale: KaidoReleaseLocale) {
    store.setGuidanceVoiceLocale(locale)
    guard locale != guidanceVoiceLocale else { return }
    guidanceVoiceLocale = locale
  }
}

extension KaidoReleaseLocale {
  var interfaceLanguageCode: String {
    switch self {
    case .japanese:
      "JA"
    case .simplifiedChinese:
      "简"
    case .english:
      "EN"
    }
  }

  var nativeLanguageName: String {
    switch self {
    case .japanese:
      "日本語"
    case .simplifiedChinese:
      "简体中文"
    case .english:
      "English"
    }
  }

  var guidanceAuditionSpokenText: String {
    switch self {
    case .japanese:
      "左側を進み、B 湾岸線、横浜方面へ。"
    case .simplifiedChinese:
      "保持左侧，跟随 B 湾岸线，横滨方向。"
    case .english:
      "Keep left for Route B toward Yokohama."
    }
  }

  var guidanceAuditionSpokenForms: [String: String] {
    switch self {
    case .japanese:
      ["B": "ビー", "湾岸線": "わんがんせん"]
    case .simplifiedChinese:
      ["B": "B 路线"]
    case .english:
      ["B": "Route B"]
    }
  }

  var guidanceAuditionText: String {
    GuidanceSpokenFormRenderer.render(
      spokenText: guidanceAuditionSpokenText,
      spokenForms: guidanceAuditionSpokenForms
    )
  }
}
