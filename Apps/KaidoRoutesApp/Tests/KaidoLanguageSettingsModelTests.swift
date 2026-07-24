import KaidoDomain
import XCTest

@testable import KaidoRoutesApp

@MainActor
final class KaidoLanguageSettingsModelTests: XCTestCase {
  func testDefaultsKeepInterfaceAndGuidanceVoiceIndependent() {
    let model = KaidoLanguageSettingsModel(
      store: RecordingKaidoLanguagePreferenceStore()
    )

    XCTAssertEqual(model.interfaceLocale, .simplifiedChinese)
    XCTAssertEqual(model.guidanceVoiceLocale, .japanese)
  }

  func testSelectionsPersistWithoutMutatingTheOtherLanguage() {
    let store = RecordingKaidoLanguagePreferenceStore()
    let model = KaidoLanguageSettingsModel(store: store)

    model.selectInterfaceLocale(.english)

    XCTAssertEqual(model.interfaceLocale, .english)
    XCTAssertEqual(model.guidanceVoiceLocale, .japanese)
    XCTAssertEqual(store.interfaceLocale(), .english)
    XCTAssertNil(store.guidanceVoiceLocale())

    model.selectGuidanceVoiceLocale(.simplifiedChinese)

    XCTAssertEqual(model.interfaceLocale, .english)
    XCTAssertEqual(model.guidanceVoiceLocale, .simplifiedChinese)
    XCTAssertEqual(store.interfaceLocale(), .english)
    XCTAssertEqual(store.guidanceVoiceLocale(), .simplifiedChinese)
  }

  func testUserDefaultsStoreRejectsUnknownPersistedLocales() {
    let suiteName = "KaidoLanguageSettingsModelTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    defaults.set("unsupported", forKey: "test.language.interface")
    defaults.set("ja-JP", forKey: "test.language.guidance-voice")

    let store = UserDefaultsKaidoLanguagePreferenceStore(
      defaults: defaults,
      keyPrefix: "test.language"
    )
    let model = KaidoLanguageSettingsModel(store: store)

    XCTAssertEqual(model.interfaceLocale, .simplifiedChinese)
    XCTAssertEqual(model.guidanceVoiceLocale, .japanese)
  }

  func testReleaseLocalesMapToExactSpeechLocalesAndFixedSamples() {
    XCTAssertEqual(KaidoReleaseLocale.japanese.speechLanguageCode, "ja-JP")
    XCTAssertEqual(
      KaidoReleaseLocale.simplifiedChinese.speechLanguageCode,
      "zh-CN"
    )
    XCTAssertEqual(KaidoReleaseLocale.english.speechLanguageCode, "en-US")
    XCTAssertEqual(
      KaidoReleaseLocale.japanese.guidanceAuditionText,
      "この先、左側です。"
    )
    XCTAssertEqual(
      KaidoReleaseLocale.simplifiedChinese.guidanceAuditionText,
      "前方请靠左行驶。"
    )
    XCTAssertEqual(
      KaidoReleaseLocale.english.guidanceAuditionText,
      "Keep left ahead."
    )
  }
}

@MainActor
private final class RecordingKaidoLanguagePreferenceStore:
  KaidoLanguagePreferenceStoring
{
  private var storedInterfaceLocale: KaidoReleaseLocale?
  private var storedGuidanceVoiceLocale: KaidoReleaseLocale?

  func interfaceLocale() -> KaidoReleaseLocale? {
    storedInterfaceLocale
  }

  func guidanceVoiceLocale() -> KaidoReleaseLocale? {
    storedGuidanceVoiceLocale
  }

  func setInterfaceLocale(_ locale: KaidoReleaseLocale) {
    storedInterfaceLocale = locale
  }

  func setGuidanceVoiceLocale(_ locale: KaidoReleaseLocale) {
    storedGuidanceVoiceLocale = locale
  }
}
