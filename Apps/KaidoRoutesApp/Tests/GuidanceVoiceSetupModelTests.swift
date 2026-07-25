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

  func testRecommendedUpgradeRequiresAuditionAndExplicitConfirmation() throws {
    let premium = Self.profiles[0]
    let basic = GuidanceSpeechVoiceProfile(
      identifier: "test.voice.default",
      name: "Basic",
      languageCode: "ja-JP",
      quality: .defaultQuality
    )
    let store = RecordingGuidanceVoicePreferenceStore(
      identifier: basic.identifier
    )
    let output = RecordingGuidanceVoiceAuditionOutput()
    let model = GuidanceVoiceSetupModel(
      preferenceStore: store,
      output: output,
      profileProvider: { _ in [premium, basic] }
    )
    model.refreshProfiles()

    XCTAssertEqual(model.selectedProfile, basic)
    XCTAssertEqual(model.effectiveProfile, basic)
    XCTAssertEqual(model.recommendedUpgradeProfile, premium)
    XCTAssertFalse(model.canUseLastAuditionedUpgrade)

    model.auditionRecommendedUpgrade()

    let request = try XCTUnwrap(output.requests.first)
    XCTAssertEqual(request.preferredVoiceIdentifier, premium.identifier)
    XCTAssertEqual(model.upgradeAuditionProfile, premium)
    XCTAssertEqual(model.selectedProfile, basic)
    XCTAssertEqual(
      store.identifier(for: GuidanceVoiceSetupModel.japaneseLanguageCode),
      basic.identifier
    )

    output.eventHandler?(.didStart(premium))
    output.eventHandler?(.didFinish(premium))

    XCTAssertEqual(model.state, .completed(premium))
    XCTAssertEqual(model.lastAuditionedProfile, premium)
    XCTAssertEqual(model.effectiveProfile, basic)
    XCTAssertTrue(model.canUseLastAuditionedUpgrade)
    XCTAssertEqual(
      store.identifier(for: GuidanceVoiceSetupModel.japaneseLanguageCode),
      basic.identifier
    )

    model.useLastAuditionedUpgrade()

    XCTAssertEqual(model.selectedProfile, premium)
    XCTAssertEqual(model.effectiveProfile, premium)
    XCTAssertNil(model.recommendedUpgradeProfile)
    XCTAssertNil(model.upgradeAuditionProfile)
    XCTAssertNil(model.lastAuditionedProfile)
    XCTAssertEqual(model.state, .ready)
    XCTAssertEqual(
      store.identifier(for: GuidanceVoiceSetupModel.japaneseLanguageCode),
      premium.identifier
    )
  }

  func testRecommendedUpgradeFailsClosedOnResolvedVoiceDrift() {
    let premium = Self.profiles[0]
    let basic = GuidanceSpeechVoiceProfile(
      identifier: "test.voice.default",
      name: "Basic",
      languageCode: "ja-JP",
      quality: .defaultQuality
    )
    let store = RecordingGuidanceVoicePreferenceStore(
      identifier: basic.identifier
    )
    let output = RecordingGuidanceVoiceAuditionOutput()
    let model = GuidanceVoiceSetupModel(
      preferenceStore: store,
      output: output,
      profileProvider: { _ in [premium, basic] }
    )
    model.refreshProfiles()
    model.auditionRecommendedUpgrade()

    output.eventHandler?(.didStart(basic))
    output.eventHandler?(.didCancel(basic))

    XCTAssertEqual(
      model.state,
      .blocked("VOICE_UPGRADE_RESOLUTION_DRIFT")
    )
    XCTAssertNil(model.upgradeAuditionProfile)
    XCTAssertNil(model.lastAuditionedProfile)
    XCTAssertFalse(model.canUseLastAuditionedUpgrade)
    XCTAssertEqual(output.stopCallCount, 1)
    XCTAssertEqual(
      store.identifier(for: GuidanceVoiceSetupModel.japaneseLanguageCode),
      basic.identifier
    )
  }

  func testAutomaticHighestQualityNeedsNoUpgradeConfirmation() {
    let model = GuidanceVoiceSetupModel(
      preferenceStore: RecordingGuidanceVoicePreferenceStore(),
      output: RecordingGuidanceVoiceAuditionOutput(),
      profileProvider: { _ in Self.profiles }
    )

    model.refreshProfiles()

    XCTAssertTrue(model.usesAutomaticSelection)
    XCTAssertEqual(model.effectiveProfile, Self.profiles[0])
    XCTAssertNil(model.recommendedUpgradeProfile)
    XCTAssertFalse(model.canUseLastAuditionedUpgrade)
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
    XCTAssertEqual(
      model.auditionText,
      "保持左侧，跟随 B 路线 湾岸线，横滨方向。"
    )
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

  func testReleasedAudioStyleSelectionPersistsPerProduct() {
    let store = RecordingGuidanceAudioSourcePreferenceStore(
      selections: ["test.product": "direct"]
    )
    let model = GuidanceAudioSourceSetupModel(
      preferenceStore: store
    )
    let choices = [
      Self.audioChoice("calm"),
      Self.audioChoice("direct"),
    ]

    model.configure(
      productReleaseID: "test.product",
      choices: choices
    )

    XCTAssertEqual(model.selectedSelectionID, "direct")
    XCTAssertEqual(model.selectedChoice?.selectionID, "direct")
    XCTAssertFalse(model.usesDeviceVoice)

    model.select(selectionID: "calm")
    XCTAssertEqual(model.selectedSelectionID, "calm")
    XCTAssertEqual(store.selections["test.product"], "calm")

    model.select(selectionID: nil)
    XCTAssertTrue(model.usesDeviceVoice)
    XCTAssertNil(store.selections["test.product"])
  }

  func testReleasedAudioStyleRejectsStaleOrUnknownSelection() {
    let store = RecordingGuidanceAudioSourcePreferenceStore(
      selections: ["test.product": "removed"]
    )
    let model = GuidanceAudioSourceSetupModel(
      preferenceStore: store
    )

    model.configure(
      productReleaseID: "test.product",
      choices: [Self.audioChoice("calm")]
    )

    XCTAssertTrue(model.usesDeviceVoice)
    XCTAssertNil(store.selections["test.product"])
    XCTAssertEqual(
      model.lastErrorCode,
      "GUIDANCE_AUDIO_PREFERENCE_UNAVAILABLE"
    )

    model.select(selectionID: "unknown")
    XCTAssertTrue(model.usesDeviceVoice)
    XCTAssertEqual(
      model.lastErrorCode,
      "GUIDANCE_AUDIO_SELECTION_UNAVAILABLE"
    )
  }

  func testUserDefaultsAudioSourcePreferenceIsProductScoped() {
    let suiteName = "GuidanceAudioSourceSetupModelTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let store = UserDefaultsGuidanceAudioSourcePreferenceStore(
      defaults: defaults,
      keyPrefix: "test.guidance-audio-source"
    )

    store.setSelectionID("calm", for: "product.a")
    store.setSelectionID("direct", for: "product.b")

    XCTAssertEqual(store.selectionID(for: "product.a"), "calm")
    XCTAssertEqual(store.selectionID(for: "product.b"), "direct")
    store.setSelectionID(nil, for: "product.a")
    XCTAssertNil(store.selectionID(for: "product.a"))
    XCTAssertEqual(store.selectionID(for: "product.b"), "direct")
  }

  private static func audioChoice(
    _ selectionID: String
  ) -> BundledGuidanceAudioReleaseDescriptor {
    BundledGuidanceAudioReleaseDescriptor(
      selectionID: selectionID,
      displayName: AppBundleGuidanceAudioDisplayName(
        japanese: selectionID,
        simplifiedChinese: selectionID,
        english: selectionID
      ),
      manifestResourceName: "audio-\(selectionID)",
      expectedManifestSHA256: String(repeating: "a", count: 64),
      expectedReleaseID: "test.audio.\(selectionID)"
    )
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
private final class RecordingGuidanceAudioSourcePreferenceStore:
  GuidanceAudioSourcePreferenceStoring
{
  fileprivate var selections: [String: String]

  init(selections: [String: String] = [:]) {
    self.selections = selections
  }

  func selectionID(for productReleaseID: String) -> String? {
    selections[productReleaseID]
  }

  func setSelectionID(
    _ selectionID: String?,
    for productReleaseID: String
  ) {
    selections[productReleaseID] = selectionID
  }
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
