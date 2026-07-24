import KaidoAppleAdapters
import Testing

@Test("Speech voice selection prefers installed premium and enhanced quality")
func speechVoiceSelectionPrefersQuality() throws {
  let selected = GuidanceSpeechVoiceSelector.select(
    languageCode: "ja-JP",
    candidates: [
      GuidanceSpeechVoiceCandidate(
        identifier: "test.voice.default",
        name: "Default",
        languageCode: "ja-JP",
        quality: .defaultQuality
      ),
      GuidanceSpeechVoiceCandidate(
        identifier: "test.voice.enhanced",
        name: "Enhanced",
        languageCode: "ja-JP",
        quality: .enhanced
      ),
      GuidanceSpeechVoiceCandidate(
        identifier: "test.voice.premium",
        name: "Premium",
        languageCode: "ja-JP",
        quality: .premium
      ),
    ],
    systemDefaultIdentifier: "test.voice.default"
  )

  #expect(try #require(selected).identifier == "test.voice.premium")
  #expect(selected?.quality == .premium)
}

@Test("Speech voice selection excludes novelty, personal, and wrong-locale voices")
func speechVoiceSelectionRejectsIneligibleVoices() throws {
  let selected = GuidanceSpeechVoiceSelector.select(
    languageCode: "zh_CN",
    candidates: [
      GuidanceSpeechVoiceCandidate(
        identifier: "test.voice.novelty",
        name: "Novelty",
        languageCode: "zh-CN",
        quality: .premium,
        isNoveltyVoice: true
      ),
      GuidanceSpeechVoiceCandidate(
        identifier: "test.voice.personal",
        name: "Personal",
        languageCode: "zh-CN",
        quality: .premium,
        isPersonalVoice: true
      ),
      GuidanceSpeechVoiceCandidate(
        identifier: "test.voice.wrong-locale",
        name: "Taiwan",
        languageCode: "zh-TW",
        quality: .premium
      ),
      GuidanceSpeechVoiceCandidate(
        identifier: "test.voice.standard",
        name: "Standard",
        languageCode: "zh-CN",
        quality: .enhanced
      ),
    ],
    systemDefaultIdentifier: nil
  )

  #expect(try #require(selected).identifier == "test.voice.standard")
}

@Test("System default breaks equal-quality speech voice ties")
func speechVoiceSelectionUsesSystemDefaultTieBreak() throws {
  let selected = GuidanceSpeechVoiceSelector.select(
    languageCode: "en-US",
    candidates: [
      GuidanceSpeechVoiceCandidate(
        identifier: "test.voice.alpha",
        name: "Alpha",
        languageCode: "en-US",
        quality: .defaultQuality
      ),
      GuidanceSpeechVoiceCandidate(
        identifier: "test.voice.system",
        name: "System",
        languageCode: "en-US",
        quality: .defaultQuality
      ),
    ],
    systemDefaultIdentifier: "test.voice.system"
  )

  #expect(try #require(selected).identifier == "test.voice.system")
}

@Test("An eligible installed preference overrides automatic quality ranking")
func speechVoiceSelectionHonorsExplicitPreference() throws {
  let candidates = [
    GuidanceSpeechVoiceCandidate(
      identifier: "test.voice.premium",
      name: "Premium",
      languageCode: "ja-JP",
      quality: .premium
    ),
    GuidanceSpeechVoiceCandidate(
      identifier: "test.voice.enhanced",
      name: "Enhanced",
      languageCode: "ja-JP",
      quality: .enhanced
    ),
  ]

  let selected = GuidanceSpeechVoiceSelector.select(
    languageCode: "ja-JP",
    candidates: candidates,
    systemDefaultIdentifier: nil,
    preferredIdentifier: "test.voice.enhanced"
  )

  #expect(try #require(selected).identifier == "test.voice.enhanced")
  #expect(selected?.quality == .enhanced)
}

@Test("A stale or ineligible preference falls back to the best installed voice")
func speechVoiceSelectionRejectsStalePreference() throws {
  let selected = GuidanceSpeechVoiceSelector.select(
    languageCode: "ja-JP",
    candidates: [
      GuidanceSpeechVoiceCandidate(
        identifier: "test.voice.default",
        name: "Default",
        languageCode: "ja-JP",
        quality: .defaultQuality
      ),
      GuidanceSpeechVoiceCandidate(
        identifier: "test.voice.premium",
        name: "Premium",
        languageCode: "ja-JP",
        quality: .premium
      ),
    ],
    systemDefaultIdentifier: "test.voice.default",
    preferredIdentifier: "test.voice.removed"
  )

  #expect(try #require(selected).identifier == "test.voice.premium")
}

@Test("Ranked speech profiles are exact-locale, eligible, and identifier-unique")
func speechVoiceSelectionProducesAuditableCatalog() {
  let ranked = GuidanceSpeechVoiceSelector.rankedProfiles(
    languageCode: "ja_JP",
    candidates: [
      GuidanceSpeechVoiceCandidate(
        identifier: "test.voice.enhanced",
        name: "Enhanced",
        languageCode: "ja-JP",
        quality: .enhanced
      ),
      GuidanceSpeechVoiceCandidate(
        identifier: "test.voice.enhanced",
        name: "Duplicate",
        languageCode: "ja-JP",
        quality: .defaultQuality
      ),
      GuidanceSpeechVoiceCandidate(
        identifier: "test.voice.default",
        name: "Default",
        languageCode: "ja-JP",
        quality: .defaultQuality
      ),
      GuidanceSpeechVoiceCandidate(
        identifier: "test.voice.personal",
        name: "Personal",
        languageCode: "ja-JP",
        quality: .premium,
        isPersonalVoice: true
      ),
      GuidanceSpeechVoiceCandidate(
        identifier: "test.voice.wrong-locale",
        name: "Wrong locale",
        languageCode: "en-US",
        quality: .premium
      ),
    ],
    systemDefaultIdentifier: "test.voice.default"
  )

  #expect(
    ranked.map(\.identifier) == [
      "test.voice.enhanced",
      "test.voice.default",
    ]
  )
}

@Test("Navigation prosody preserves Apple's neutral rate and pitch")
func navigationSpeechProsodyUsesNeutralBaseline() {
  let japanese = GuidanceSpeechProsody.navigation(languageCode: "ja-JP")
  let chinese = GuidanceSpeechProsody.navigation(languageCode: "zh-CN")
  let english = GuidanceSpeechProsody.navigation(languageCode: "en-US")

  #expect(japanese.rate == 0.5)
  #expect(chinese.rate == 0.5)
  #expect(english.rate == 0.5)
  #expect(japanese.pitchMultiplier == 1)
  #expect(japanese.preUtteranceDelay == 0.03)
  #expect(japanese.postUtteranceDelay == 0.02)
}

@Test("Only enhanced and premium voices satisfy higher-quality readiness")
func speechVoiceQualityReadinessIsExplicit() {
  #expect(!GuidanceSpeechVoiceQuality.defaultQuality.isHigherQuality)
  #expect(GuidanceSpeechVoiceQuality.enhanced.isHigherQuality)
  #expect(GuidanceSpeechVoiceQuality.premium.isHigherQuality)
}
