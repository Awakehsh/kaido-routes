import Combine
import Foundation
import KaidoDomain

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
      UserDefaultsKaidoLanguagePreferenceStore()
  ) {
    self.store = store
    interfaceLocale = store.interfaceLocale() ?? .simplifiedChinese
    guidanceVoiceLocale = store.guidanceVoiceLocale() ?? .japanese
  }

  func selectInterfaceLocale(_ locale: KaidoReleaseLocale) {
    guard locale != interfaceLocale else { return }
    store.setInterfaceLocale(locale)
    interfaceLocale = locale
  }

  func selectGuidanceVoiceLocale(_ locale: KaidoReleaseLocale) {
    guard locale != guidanceVoiceLocale else { return }
    store.setGuidanceVoiceLocale(locale)
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

  var guidanceAuditionText: String {
    switch self {
    case .japanese:
      "この先、左側です。"
    case .simplifiedChinese:
      "前方请靠左行驶。"
    case .english:
      "Keep left ahead."
    }
  }
}
