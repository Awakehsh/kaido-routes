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

@Test("Navigation prosody is locale-specific and remains within Apple bounds")
func navigationSpeechProsodyIsConservative() {
  let japanese = GuidanceSpeechProsody.navigation(languageCode: "ja-JP")
  let chinese = GuidanceSpeechProsody.navigation(languageCode: "zh-CN")
  let english = GuidanceSpeechProsody.navigation(languageCode: "en-US")

  #expect(japanese.rate == 0.46)
  #expect(chinese.rate == 0.47)
  #expect(english.rate == 0.48)
  #expect(japanese.pitchMultiplier == 0.98)
  #expect(japanese.preUtteranceDelay == 0.03)
  #expect(japanese.postUtteranceDelay == 0.02)
}
