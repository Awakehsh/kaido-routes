import KaidoAppleAdapters
import KaidoDomain
import XCTest

@testable import KaidoRoutesApp

@MainActor
final class GuidanceVoiceSetupModelTests: XCTestCase {
  func testRefreshLoadsProfilesAndPersistsAnExactSelection() {
    let store = RecordingGuidanceVoicePreferenceStore()
    let output = RecordingGuidanceVoiceAuditionOutput()
    let profiles = Self.profiles
    let model = GuidanceVoiceSetupModel(
      preferenceStore: store,
      output: output,
      profileProvider: { _ in profiles }
    )

    model.refreshProfiles()
    model.selectVoice(identifier: profiles[1].identifier)

    XCTAssertEqual(model.profiles, profiles)
    XCTAssertEqual(model.selectedProfile, profiles[1])
    XCTAssertFalse(model.usesAutomaticSelection)
    XCTAssertEqual(
      store.identifier(for: GuidanceVoiceSetupModel.japaneseLanguageCode),
      profiles[1].identifier
    )
    XCTAssertEqual(output.stopCallCount, 1)
  }

  func testAuditionUsesOnlyFixedLocalePreferenceAndSample() throws {
    let store = RecordingGuidanceVoicePreferenceStore(
      identifier: Self.profiles[0].identifier
    )
    let output = RecordingGuidanceVoiceAuditionOutput()
    let model = GuidanceVoiceSetupModel(
      preferenceStore: store,
      output: output,
      profileProvider: { _ in Self.profiles }
    )
    model.refreshProfiles()

    model.audition()

    let request = try XCTUnwrap(output.requests.first)
    XCTAssertEqual(
      request.languageCode,
      GuidanceVoiceSetupModel.japaneseLanguageCode
    )
    XCTAssertEqual(
      request.preferredVoiceIdentifier,
      Self.profiles[0].identifier
    )
    XCTAssertEqual(
      request.spokenText,
      GuidanceVoiceSetupModel.japaneseAuditionText
    )
    XCTAssertEqual(model.state, .preparing)

    output.eventHandler?(.didStart(Self.profiles[0]))
    XCTAssertEqual(model.state, .speaking(Self.profiles[0]))
    output.eventHandler?(.didFinish(Self.profiles[0]))
    XCTAssertEqual(model.state, .completed(Self.profiles[0]))
    XCTAssertEqual(model.lastAuditionedProfile, Self.profiles[0])
  }

  func testMovingContextBlocksAuditionBeforeOutput() {
    let output = RecordingGuidanceVoiceAuditionOutput()
    let model = GuidanceVoiceSetupModel(
      preferenceStore: RecordingGuidanceVoicePreferenceStore(),
      output: output,
      profileProvider: { _ in Self.profiles }
    )

    model.audition(isVehicleMoving: true)

    XCTAssertEqual(
      model.state,
      .blocked("VOICE_AUDITION_MOVING_CONTEXT")
    )
    XCTAssertTrue(output.requests.isEmpty)
  }

  func testGuidanceLanguageSwitchRefreshesAnIndependentInstalledVoiceCatalog() {
    let output = RecordingGuidanceVoiceAuditionOutput()
    var selectedLocale: KaidoReleaseLocale?
    let chineseProfile = GuidanceSpeechVoiceProfile(
      identifier: "test.voice.zh-cn.enhanced",
      name: "Chinese Enhanced",
      languageCode: "zh-CN",
      quality: .enhanced
    )
    let model = GuidanceVoiceSetupModel(
      preferenceStore: RecordingGuidanceVoicePreferenceStore(),
      output: output,
      profileProvider: { languageCode in
        languageCode == "zh-CN" ? [chineseProfile] : Self.profiles
      },
      guidanceLocaleDidChange: {
        selectedLocale = $0
      }
    )
    model.refreshProfiles()

    model.selectGuidanceLocale(.simplifiedChinese)

    XCTAssertEqual(selectedLocale, .simplifiedChinese)
    XCTAssertEqual(model.selectedGuidanceLocale, .simplifiedChinese)
    XCTAssertEqual(model.languageCode, "zh-CN")
    XCTAssertEqual(model.auditionText, "前方请靠左行驶。")
    XCTAssertEqual(model.profiles, [chineseProfile])
    XCTAssertTrue(model.usesAutomaticSelection)
    XCTAssertEqual(output.stopCallCount, 1)
  }

  func testEachGuidanceLanguageRestoresItsOwnInstalledVoicePreference() {
    let suiteName = "GuidanceVoiceSetupModelTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let store = UserDefaultsGuidanceVoicePreferenceStore(
      defaults: defaults,
      keyPrefix: "test.guidance-voice"
    )
    let japaneseProfile = Self.profiles[0]
    let chineseProfile = GuidanceSpeechVoiceProfile(
      identifier: "test.voice.zh-cn.premium",
      name: "Chinese Premium",
      languageCode: "zh-CN",
      quality: .premium
    )
    store.setIdentifier(japaneseProfile.identifier, for: "ja-JP")
    store.setIdentifier(chineseProfile.identifier, for: "zh-CN")
    let model = GuidanceVoiceSetupModel(
      preferenceStore: store,
      output: RecordingGuidanceVoiceAuditionOutput(),
      profileProvider: { languageCode in
        languageCode == "zh-CN" ? [chineseProfile] : Self.profiles
      }
    )

    model.refreshProfiles()
    XCTAssertEqual(model.selectedProfile, japaneseProfile)

    model.selectGuidanceLocale(.simplifiedChinese)
    XCTAssertEqual(model.selectedProfile, chineseProfile)

    model.selectGuidanceLocale(.japanese)
    XCTAssertEqual(model.selectedProfile, japaneseProfile)
  }

  func testMissingInstalledPreferenceFailsClosedAfterCatalogResolution() {
    let store = RecordingGuidanceVoicePreferenceStore(
      identifier: "test.voice.removed"
    )
    let model = GuidanceVoiceSetupModel(
      preferenceStore: store,
      output: RecordingGuidanceVoiceAuditionOutput(),
      profileProvider: { _ in Self.profiles }
    )

    model.refreshProfiles()

    XCTAssertNil(model.selectedVoiceIdentifier)
    XCTAssertNil(
      store.identifier(for: GuidanceVoiceSetupModel.japaneseLanguageCode)
    )
    XCTAssertEqual(
      model.state,
      .blocked("VOICE_PREFERENCE_NO_LONGER_INSTALLED")
    )
  }

  func testColdEmptyCatalogDoesNotEraseStoredPreference() {
    let store = RecordingGuidanceVoicePreferenceStore(
      identifier: "test.voice.pending-enumeration"
    )
    let model = GuidanceVoiceSetupModel(
      preferenceStore: store,
      output: RecordingGuidanceVoiceAuditionOutput(),
      profileProvider: { _ in [] }
    )

    model.refreshProfiles()

    XCTAssertEqual(
      model.selectedVoiceIdentifier,
      "test.voice.pending-enumeration"
    )
    XCTAssertEqual(
      store.identifier(for: GuidanceVoiceSetupModel.japaneseLanguageCode),
      "test.voice.pending-enumeration"
    )
    XCTAssertEqual(model.state, .ready)
  }

  func testUserDefaultsPreferenceStoreRoundTripsByNormalizedLocale() {
    let suiteName = "GuidanceVoiceSetupModelTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let store = UserDefaultsGuidanceVoicePreferenceStore(
      defaults: defaults,
      keyPrefix: "test.guidance-voice"
    )

    store.setIdentifier(" test.voice.enhanced ", for: "ja_JP")

    XCTAssertEqual(
      store.identifier(for: "ja-JP"),
      "test.voice.enhanced"
    )

    store.setIdentifier(nil, for: "ja-JP")
    XCTAssertNil(store.identifier(for: "ja_JP"))
  }

  private static let profiles = [
    GuidanceSpeechVoiceProfile(
      identifier: "test.voice.premium",
      name: "Premium",
      languageCode: "ja-JP",
      quality: .premium
    ),
    GuidanceSpeechVoiceProfile(
      identifier: "test.voice.enhanced",
      name: "Enhanced",
      languageCode: "ja-JP",
      quality: .enhanced
    ),
  ]
}

@MainActor
private final class RecordingGuidanceVoicePreferenceStore:
  GuidanceVoicePreferenceStoring
{
  private var storedIdentifier: String?

  init(identifier: String? = nil) {
    storedIdentifier = identifier
  }

  func identifier(for _: String) -> String? {
    storedIdentifier
  }

  func setIdentifier(_ identifier: String?, for _: String) {
    storedIdentifier = identifier
  }
}

@MainActor
private final class RecordingGuidanceVoiceAuditionOutput:
  GuidanceVoiceAuditionOutput
{
  var eventHandler: ((GuidanceVoiceAuditionOutputEvent) -> Void)?
  private(set) var requests: [GuidanceVoiceAuditionRequest] = []
  private(set) var stopCallCount = 0

  func audition(_ request: GuidanceVoiceAuditionRequest) throws {
    requests.append(request)
  }

  func stop() {
    stopCallCount += 1
  }
}
