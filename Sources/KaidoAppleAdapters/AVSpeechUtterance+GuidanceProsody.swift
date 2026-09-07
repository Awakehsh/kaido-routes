#if os(iOS) || os(tvOS) || os(watchOS) || targetEnvironment(macCatalyst)
  import AVFAudio

  extension AVSpeechUtterance {
    func applyGuidanceProsody(
      _ prosody: GuidanceSpeechProsody,
      minimumLeadIn: TimeInterval = 0
    ) {
      rate = prosody.rate
      pitchMultiplier = prosody.pitchMultiplier
      preUtteranceDelay = max(prosody.preUtteranceDelay, minimumLeadIn)
      postUtteranceDelay = prosody.postUtteranceDelay
    }
  }
#endif
