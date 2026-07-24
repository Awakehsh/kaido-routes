import Foundation

#if os(iOS) || os(tvOS) || os(watchOS) || targetEnvironment(macCatalyst)
  import AVFAudio
#endif

public struct GuidanceVoiceAuditionRequest: Equatable, Sendable {
  public let languageCode: String
  public let preferredVoiceIdentifier: String?
  public let spokenText: String

  public init(
    languageCode: String,
    preferredVoiceIdentifier: String?,
    spokenText: String
  ) {
    self.languageCode = languageCode
    self.preferredVoiceIdentifier = preferredVoiceIdentifier
    self.spokenText = spokenText
  }
}

public enum GuidanceVoiceAuditionFailureCode: String, Equatable, Sendable {
  case invalidRequest = "VOICE_AUDITION_REQUEST_INVALID"
  case voiceUnavailable = "VOICE_AUDITION_VOICE_UNAVAILABLE"
  case audioSessionConfigurationFailed =
    "VOICE_AUDITION_AUDIO_SESSION_CONFIGURATION_FAILED"
  case audioSessionActivationFailed =
    "VOICE_AUDITION_AUDIO_SESSION_ACTIVATION_FAILED"
}

public enum GuidanceVoiceAuditionOutputError: Error, Equatable, Sendable {
  case invalidRequest
  case voiceUnavailable(String)
  case audioSessionConfigurationFailed
  case audioSessionActivationFailed

  public var code: GuidanceVoiceAuditionFailureCode {
    switch self {
    case .invalidRequest:
      .invalidRequest
    case .voiceUnavailable:
      .voiceUnavailable
    case .audioSessionConfigurationFailed:
      .audioSessionConfigurationFailed
    case .audioSessionActivationFailed:
      .audioSessionActivationFailed
    }
  }
}

public enum GuidanceVoiceAuditionOutputEvent: Equatable, Sendable {
  case didStart(GuidanceSpeechVoiceProfile)
  case didFinish(GuidanceSpeechVoiceProfile)
  case didCancel(GuidanceSpeechVoiceProfile)
}

@MainActor
public protocol GuidanceVoiceAuditionOutput: AnyObject {
  var eventHandler: ((GuidanceVoiceAuditionOutputEvent) -> Void)? {
    get set
  }

  func audition(_ request: GuidanceVoiceAuditionRequest) throws
  func stop()
}

#if os(iOS) || os(tvOS) || os(watchOS) || targetEnvironment(macCatalyst)
  /// Parked settings audition for one fixed sample.
  ///
  /// This output is deliberately separate from `GuidanceSpeechOutput`. It has
  /// no RoutePlan, occurrence, prompt, or engine-ledger input and therefore
  /// cannot authorize or consume navigation guidance.
  @MainActor
  public final class AVSpeechVoiceAuditionOutput: NSObject,
    GuidanceVoiceAuditionOutput
  {
    public var eventHandler: ((GuidanceVoiceAuditionOutputEvent) -> Void)?

    private let synthesizer: AVSpeechSynthesizer
    private let audioSession: AVAudioSession
    private var profileByUtterance: [ObjectIdentifier: GuidanceSpeechVoiceProfile] = [:]
    private var activeUtteranceID: ObjectIdentifier?

    public init(
      synthesizer: AVSpeechSynthesizer = AVSpeechSynthesizer(),
      audioSession: AVAudioSession = .sharedInstance()
    ) {
      self.synthesizer = synthesizer
      self.audioSession = audioSession
      super.init()
      synthesizer.delegate = self
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleAudioInterruption(_:)),
        name: AVAudioSession.interruptionNotification,
        object: audioSession
      )
    }

    deinit {
      NotificationCenter.default.removeObserver(self)
    }

    public func audition(_ request: GuidanceVoiceAuditionRequest) throws {
      cancelActiveUtterance()

      let languageCode = request.languageCode.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      let spokenText = request.spokenText.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      guard !languageCode.isEmpty, !spokenText.isEmpty else {
        throw GuidanceVoiceAuditionOutputError.invalidRequest
      }
      guard
        let profile = AVSpeechGuidanceOutput.preferredInstalledVoiceProfile(
          for: languageCode,
          preferredIdentifier: request.preferredVoiceIdentifier
        ),
        let voice = AVSpeechSynthesisVoice(
          identifier: profile.identifier
        )
      else {
        throw GuidanceVoiceAuditionOutputError.voiceUnavailable(
          languageCode
        )
      }

      do {
        try audioSession.setCategory(
          .playback,
          mode: .voicePrompt,
          options: [.duckOthers]
        )
      } catch {
        throw GuidanceVoiceAuditionOutputError
          .audioSessionConfigurationFailed
      }
      do {
        try audioSession.setActive(true)
      } catch {
        throw GuidanceVoiceAuditionOutputError.audioSessionActivationFailed
      }

      let utterance = AVSpeechUtterance(string: spokenText)
      utterance.voice = voice
      let prosody = GuidanceSpeechProsody.navigation(
        languageCode: languageCode
      )
      utterance.rate = prosody.rate
      utterance.pitchMultiplier = prosody.pitchMultiplier
      let utteranceID = ObjectIdentifier(utterance)
      profileByUtterance[utteranceID] = profile
      activeUtteranceID = utteranceID
      synthesizer.speak(utterance)
    }

    public func stop() {
      cancelActiveUtterance()
    }

    @objc
    private func handleAudioInterruption(_ notification: Notification) {
      guard
        let rawType = notification.userInfo?[
          AVAudioSessionInterruptionTypeKey
        ] as? UInt,
        AVAudioSession.InterruptionType(rawValue: rawType) == .began
      else {
        return
      }
      cancelActiveUtterance()
    }

    private func cancelActiveUtterance() {
      guard let utteranceID = activeUtteranceID else {
        guard synthesizer.isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
        deactivateAudioSession()
        return
      }
      let profile = profileByUtterance.removeValue(
        forKey: utteranceID
      )
      activeUtteranceID = nil
      synthesizer.stopSpeaking(at: .immediate)
      deactivateAudioSession()
      if let profile {
        eventHandler?(.didCancel(profile))
      }
    }

    private func complete(
      _ utterance: AVSpeechUtterance,
      event: (
        GuidanceSpeechVoiceProfile
      ) -> GuidanceVoiceAuditionOutputEvent
    ) {
      let utteranceID = ObjectIdentifier(utterance)
      guard
        let profile = profileByUtterance.removeValue(
          forKey: utteranceID
        )
      else {
        return
      }
      if activeUtteranceID == utteranceID {
        activeUtteranceID = nil
        deactivateAudioSession()
      }
      eventHandler?(event(profile))
    }

    private func deactivateAudioSession() {
      try? audioSession.setActive(
        false,
        options: .notifyOthersOnDeactivation
      )
    }
  }

  extension AVSpeechVoiceAuditionOutput:
    @preconcurrency AVSpeechSynthesizerDelegate
  {
    public func speechSynthesizer(
      _: AVSpeechSynthesizer,
      didStart utterance: AVSpeechUtterance
    ) {
      guard
        let profile = profileByUtterance[
          ObjectIdentifier(utterance)
        ]
      else {
        return
      }
      eventHandler?(.didStart(profile))
    }

    public func speechSynthesizer(
      _: AVSpeechSynthesizer,
      didFinish utterance: AVSpeechUtterance
    ) {
      complete(utterance, event: GuidanceVoiceAuditionOutputEvent.didFinish)
    }

    public func speechSynthesizer(
      _: AVSpeechSynthesizer,
      didCancel utterance: AVSpeechUtterance
    ) {
      complete(utterance, event: GuidanceVoiceAuditionOutputEvent.didCancel)
    }
  }
#endif
