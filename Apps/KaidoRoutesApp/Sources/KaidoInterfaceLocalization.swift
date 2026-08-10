import Foundation
import KaidoDomain
import SwiftUI

extension KaidoReleaseLocale {
  /// The interface language a first launch should open in: the device's own
  /// preferred language when the product speaks it, English otherwise. A
  /// Japanese iPhone must never open in Chinese because of a build-time
  /// default.
  static func matchingPreferredLanguage(
    _ preferredLanguages: [String] = Locale.preferredLanguages
  ) -> KaidoReleaseLocale {
    for identifier in preferredLanguages {
      let language = Locale(identifier: identifier).language
      guard let code = language.languageCode?.identifier else { continue }
      switch code {
      case "ja":
        return .japanese
      case "zh":
        // Only Simplified Chinese is authored; Traditional readers get
        // English rather than mismatched script.
        return language.script?.identifier == "Hant"
          ? .english : .simplifiedChinese
      case "en":
        return .english
      default:
        continue
      }
    }
    return .english
  }
}

struct KaidoInterfaceText: Equatable, Sendable {
  let locale: KaidoReleaseLocale

  func resolve(
    japanese: String,
    simplifiedChinese: String,
    english: String
  ) -> String {
    switch locale {
    case .japanese:
      japanese
    case .simplifiedChinese:
      simplifiedChinese
    case .english:
      english
    }
  }

  func languageName(_ language: KaidoReleaseLocale) -> String {
    switch (locale, language) {
    case (.japanese, .japanese):
      "日本語"
    case (.japanese, .simplifiedChinese):
      "簡体字中国語"
    case (.japanese, .english):
      "英語"
    case (.simplifiedChinese, .japanese):
      "日语"
    case (.simplifiedChinese, .simplifiedChinese):
      "简体中文"
    case (.simplifiedChinese, .english):
      "英语"
    case (.english, .japanese):
      "Japanese"
    case (.english, .simplifiedChinese):
      "Simplified Chinese"
    case (.english, .english):
      "English"
    }
  }
}

private struct KaidoInterfaceLocaleEnvironmentKey: EnvironmentKey {
  static let defaultValue = KaidoReleaseLocale.matchingPreferredLanguage()
}

extension EnvironmentValues {
  var kaidoInterfaceLocale: KaidoReleaseLocale {
    get { self[KaidoInterfaceLocaleEnvironmentKey.self] }
    set { self[KaidoInterfaceLocaleEnvironmentKey.self] = newValue }
  }
}

struct KaidoInterfaceLanguagePicker: View {
  @ObservedObject var model: KaidoLanguageSettingsModel

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: model.interfaceLocale)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(
        copy.resolve(
          japanese: "画面表示",
          simplifiedChinese: "界面语言",
          english: "INTERFACE LANGUAGE"
        )
      )
      .font(.system(size: 8, weight: .black, design: .monospaced))
      .tracking(0.55)
      .foregroundStyle(KaidoTheme.muted)

      HStack(spacing: 4) {
        ForEach(KaidoReleaseLocale.allCases, id: \.self) { locale in
          Button {
            model.selectInterfaceLocale(locale)
          } label: {
            Text(locale.interfaceLanguageCode)
              .font(.system(size: 9, weight: .black, design: .monospaced))
              .frame(minWidth: 31, minHeight: 29)
              .foregroundStyle(
                model.interfaceLocale == locale
                  ? KaidoTheme.asphalt
                  : KaidoTheme.muted
              )
              .background(
                model.interfaceLocale == locale
                  ? KaidoTheme.positionCyan
                  : KaidoTheme.asphalt.opacity(0.52)
              )
              .clipShape(RoundedRectangle(cornerRadius: 8))
          }
          .buttonStyle(.plain)
          .accessibilityLabel(copy.languageName(locale))
          .accessibilityAddTraits(
            model.interfaceLocale == locale ? .isSelected : []
          )
          .accessibilityIdentifier(
            "product-journey-interface-language-\(locale.rawValue)"
          )
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("product-journey-interface-language")
    .accessibilityValue(model.interfaceLocale.rawValue)
  }
}
