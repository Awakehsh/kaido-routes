import KaidoDomain
import KaidoRouting
import XCTest

@testable import KaidoRoutesApp

@MainActor
final class KaidoLanguageSettingsModelTests: XCTestCase {
  func testDefaultsKeepInterfaceAndGuidanceVoiceIndependent() {
    let model = KaidoLanguageSettingsModel(
      store: RecordingKaidoLanguagePreferenceStore(),
      preferredLanguages: ["zh-Hans-CN"]
    )

    XCTAssertEqual(model.interfaceLocale, .simplifiedChinese)
    XCTAssertEqual(model.guidanceVoiceLocale, .japanese)
  }

  func testSelectionsPersistWithoutMutatingTheOtherLanguage() {
    let store = RecordingKaidoLanguagePreferenceStore()
    let model = KaidoLanguageSettingsModel(
      store: store,
      preferredLanguages: ["en-US"]
    )

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

  func testExplicitGuidanceSelectionPersistsWhenItMatchesTheDefault() {
    let store = RecordingKaidoLanguagePreferenceStore()
    let model = KaidoLanguageSettingsModel(
      store: store,
      preferredLanguages: ["en-US"]
    )

    model.selectGuidanceVoiceLocale(.japanese)

    XCTAssertEqual(model.guidanceVoiceLocale, .japanese)
    XCTAssertEqual(store.guidanceVoiceLocale(), .japanese)
    XCTAssertNil(store.interfaceLocale())
  }

  func testUnsetInterfaceLanguageNamesTheOriginInTheDeviceLanguage() {
    let key = "app.kaidoroutes.language.interface"
    let defaults = UserDefaults.standard
    let stored = defaults.string(forKey: key)
    defer { defaults.set(stored, forKey: key) }
    defaults.removeObject(forKey: key)

    let deviceLocale = KaidoReleaseLocale.matchingPreferredLanguage(
      Locale.preferredLanguages
    )
    XCTAssertEqual(
      WholeShutoProductModel.storedLanguageSelection().interfaceLocale,
      deviceLocale
    )
    let model = WholeShutoProductModel(checkpointStore: nil)
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6586, longitude: 139.7454)
    )
    XCTAssertEqual(
      model.origin?.title,
      KaidoInterfaceText(locale: deviceLocale).resolve(
        japanese: "現在地",
        simplifiedChinese: "当前位置",
        english: "Current location"
      )
    )
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
    let model = KaidoLanguageSettingsModel(
      store: store,
      preferredLanguages: ["zh-Hans-CN"]
    )

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
      "左側を進み、ビー わんがんせん、横浜方面へ。"
    )
    XCTAssertEqual(
      KaidoReleaseLocale.simplifiedChinese.guidanceAuditionText,
      "保持左侧，跟随 B 路线 湾岸线，横滨方向。"
    )
    XCTAssertEqual(
      KaidoReleaseLocale.english.guidanceAuditionText,
      "Keep left for Route B toward Yokohama."
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
