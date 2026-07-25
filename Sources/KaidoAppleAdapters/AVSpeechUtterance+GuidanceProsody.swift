#if os(iOS) || os(tvOS) || os(watchOS) || targetEnvironment(macCatalyst)
  import AVFAudio

  extension AVSpeechUtterance {
    func applyGuidanceProsody(_ prosody: GuidanceSpeechProsody) {
      rate = prosody.rate
      pitchMultiplier = prosody.pitchMultiplier
      preUtteranceDelay = prosody.preUtteranceDelay
      postUtteranceDelay = prosody.postUtteranceDelay
    }
  }
#endif
