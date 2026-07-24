import Foundation
import KaidoPresentation

#if os(iOS) || os(tvOS) || os(watchOS) || targetEnvironment(macCatalyst)
  import AVFAudio
#endif

public enum GuidanceSpeechOutputFailureCode: String, Equatable, Sendable {
  case voiceUnavailable = "VOICE_UNAVAILABLE"
  case audioSessionConfigurationFailed = "AUDIO_SESSION_CONFIGURATION_FAILED"
  case audioSessionActivationFailed = "AUDIO_SESSION_ACTIVATION_FAILED"
}

public enum GuidanceSpeechOutputError: Error, Equatable, Sendable {
  case voiceUnavailable(String)
  case audioSessionConfigurationFailed
  case audioSessionActivationFailed

  public var code: GuidanceSpeechOutputFailureCode {
    switch self {
    case .voiceUnavailable:
      .voiceUnavailable
    case .audioSessionConfigurationFailed:
      .audioSessionConfigurationFailed
    case .audioSessionActivationFailed:
      .audioSessionActivationFailed
    }
  }
}

public enum GuidanceSpeechOutputEvent: Equatable, Sendable {
  case didStart(GuidanceSpeechIdentity)
  case didFinish(GuidanceSpeechIdentity)
  case didCancel(GuidanceSpeechIdentity)
  case interruptionBegan
  case interruptionEnded
}

@MainActor
public protocol GuidanceSpeechOutput: AnyObject {
  var eventHandler: ((GuidanceSpeechOutputEvent) -> Void)? { get set }
  var selectedVoiceProfile: GuidanceSpeechVoiceProfile? { get }

  func speak(_ command: GuidanceSpeechCommand) throws
  func stop()
}

extension GuidanceSpeechOutput {
  public var selectedVoiceProfile: GuidanceSpeechVoiceProfile? {
    nil
  }
}

public enum GuidanceSpeechCoordinatorStatus: Equatable, Sendable {
  case idle
  case scheduled(GuidanceSpeechIdentity)
  case speaking(GuidanceSpeechIdentity)
  case suppressed(GuidanceSpeechSuppressionReason)
  case interrupted
  case stopped
  case failed(GuidanceSpeechOutputFailureCode)
  case invalidProjection
}

/// Connects the pure exactly-once speech scheduler to one Apple audio output.
///
/// Output callbacks may arrive after a newer command replaces an old one. The
/// scheduler ignores those stale callbacks by exact prompt/anchor/occurrence
/// identity, so they cannot stop or replay current guidance.
@MainActor
public final class GuidanceSpeechCoordinator {
  public private(set) var scheduler: GuidanceSpeechScheduler
  public private(set) var status: GuidanceSpeechCoordinatorStatus = .idle {
    didSet {
      guard status != oldValue else { return }
      statusDidChange?(status)
    }
  }
  public var statusDidChange: ((GuidanceSpeechCoordinatorStatus) -> Void)?
  public var selectedVoiceProfile: GuidanceSpeechVoiceProfile? {
    output.selectedVoiceProfile
  }

  private let output: any GuidanceSpeechOutput

  public init(
    expectedRoutePlanID: String,
    output: any GuidanceSpeechOutput
  ) throws {
    scheduler = try GuidanceSpeechScheduler(
      expectedRoutePlanID: expectedRoutePlanID
    )
    self.output = output
    output.eventHandler = { [weak self] event in
      self?.handle(event)
    }
  }

  @discardableResult
  public func submit(
    _ projection: NavigationPresentationProjection
  ) -> GuidanceSpeechCoordinatorStatus {
    do {
      switch try scheduler.submit(projection) {
      case .suppressed(let reason):
        status = .suppressed(reason)
      case .speak(let command, let replacing):
        do {
          if replacing != nil {
            output.stop()
          }
          status = .scheduled(command.identity)
          try output.speak(command)
        } catch let error as GuidanceSpeechOutputError {
          _ = scheduler.didCancel(command.identity)
          status = .failed(error.code)
        } catch {
          _ = scheduler.didCancel(command.identity)
          status = .failed(.audioSessionActivationFailed)
        }
      }
    } catch is GuidanceSpeechSchedulerError {
      status = .invalidProjection
    } catch {
      status = .invalidProjection
    }
    return status
  }

  public func stop() {
    _ = scheduler.stop()
    output.stop()
    status = .stopped
  }

  public func resume() {
    scheduler.resume()
    guard scheduler.state == .idle else { return }
    status = .idle
  }

  private func handle(_ event: GuidanceSpeechOutputEvent) {
    switch event {
    case .didStart(let identity):
      guard scheduler.activeCommand?.identity == identity else { return }
      status = .speaking(identity)
    case .didFinish(let identity):
      guard scheduler.didFinish(identity) else { return }
      status = .idle
    case .didCancel(let identity):
      guard scheduler.didCancel(identity) else { return }
      status = .idle
    case .interruptionBegan:
      _ = scheduler.interruptionBegan()
      status = .interrupted
    case .interruptionEnded:
      scheduler.interruptionEnded()
      guard scheduler.state == .idle else { return }
      status = .idle
    }
  }
}

#if os(iOS) || os(tvOS) || os(watchOS) || targetEnvironment(macCatalyst)
  /// Short-form navigation speech using Apple's voice-prompt audio route.
  ///
  /// The audio session is active only for an admitted prompt. Completion or
  /// cancellation deactivates it with `notifyOthersOnDeactivation`; an Apple
  /// interruption cancels the prompt and deliberately does not resume it.
  @MainActor
  public final class AVSpeechGuidanceOutput: NSObject, GuidanceSpeechOutput {
    public var eventHandler: ((GuidanceSpeechOutputEvent) -> Void)?
    public private(set) var selectedVoiceProfile: GuidanceSpeechVoiceProfile?

    private let synthesizer: AVSpeechSynthesizer
    private let audioSession: AVAudioSession
    private var identityByUtterance: [ObjectIdentifier: GuidanceSpeechIdentity] = [:]
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

    public func speak(_ command: GuidanceSpeechCommand) throws {
      cancelActiveUtterance()

      guard
        let profile = Self.preferredInstalledVoiceProfile(
          for: command.languageCode
        ),
        let voice = AVSpeechSynthesisVoice(
          identifier: profile.identifier
        )
      else {
        throw GuidanceSpeechOutputError.voiceUnavailable(
          command.languageCode
        )
      }
      selectedVoiceProfile = profile

      do {
        try audioSession.setCategory(
          .playback,
          mode: .voicePrompt,
          options: [
            .duckOthers,
            .interruptSpokenAudioAndMixWithOthers,
          ]
        )
      } catch {
        throw GuidanceSpeechOutputError.audioSessionConfigurationFailed
      }
      do {
        try audioSession.setActive(true)
      } catch {
        throw GuidanceSpeechOutputError.audioSessionActivationFailed
      }

      let utterance = AVSpeechUtterance(string: command.spokenText)
      utterance.voice = voice
      let prosody = GuidanceSpeechProsody.navigation(
        languageCode: command.languageCode
      )
      utterance.rate = prosody.rate
      utterance.pitchMultiplier = prosody.pitchMultiplier
      utterance.preUtteranceDelay = prosody.preUtteranceDelay
      utterance.postUtteranceDelay = prosody.postUtteranceDelay
      let utteranceID = ObjectIdentifier(utterance)
      identityByUtterance[utteranceID] = command.identity
      activeUtteranceID = utteranceID
      synthesizer.speak(utterance)
    }

    public static func preferredInstalledVoiceProfile(
      for languageCode: String
    ) -> GuidanceSpeechVoiceProfile? {
      let defaultVoice = AVSpeechSynthesisVoice(language: languageCode)
      var candidates = AVSpeechSynthesisVoice.speechVoices().map { voice in
        let traits = traits(voice)
        return GuidanceSpeechVoiceCandidate(
          identifier: voice.identifier,
          name: voice.name,
          languageCode: voice.language,
          quality: quality(voice.quality),
          isNoveltyVoice: traits.isNoveltyVoice,
          isPersonalVoice: traits.isPersonalVoice
        )
      }
      if let defaultVoice,
        !candidates.contains(where: {
          $0.identifier == defaultVoice.identifier
        })
      {
        let traits = traits(defaultVoice)
        candidates.append(
          GuidanceSpeechVoiceCandidate(
            identifier: defaultVoice.identifier,
            name: defaultVoice.name,
            languageCode: defaultVoice.language,
            quality: quality(defaultVoice.quality),
            isNoveltyVoice: traits.isNoveltyVoice,
            isPersonalVoice: traits.isPersonalVoice
          )
        )
      }
      return GuidanceSpeechVoiceSelector.select(
        languageCode: languageCode,
        candidates: candidates,
        systemDefaultIdentifier: defaultVoice?.identifier
      )
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
        let type = AVAudioSession.InterruptionType(rawValue: rawType)
      else {
        return
      }

      switch type {
      case .began:
        eventHandler?(.interruptionBegan)
        cancelActiveUtterance()
      case .ended:
        eventHandler?(.interruptionEnded)
      @unknown default:
        break
      }
    }

    private func cancelActiveUtterance() {
      guard let utteranceID = activeUtteranceID else {
        guard synthesizer.isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
        deactivateAudioSession()
        return
      }

      let identity = identityByUtterance.removeValue(
        forKey: utteranceID
      )
      activeUtteranceID = nil
      synthesizer.stopSpeaking(at: .immediate)
      deactivateAudioSession()
      if let identity {
        eventHandler?(.didCancel(identity))
      }
    }

    private func complete(
      _ utterance: AVSpeechUtterance,
      event: (
        GuidanceSpeechIdentity
      ) -> GuidanceSpeechOutputEvent
    ) {
      let utteranceID = ObjectIdentifier(utterance)
      guard
        let identity = identityByUtterance.removeValue(
          forKey: utteranceID
        )
      else {
        return
      }
      let wasActive = activeUtteranceID == utteranceID
      if wasActive {
        activeUtteranceID = nil
        deactivateAudioSession()
      }
      eventHandler?(event(identity))
    }

    private func deactivateAudioSession() {
      try? audioSession.setActive(
        false,
        options: .notifyOthersOnDeactivation
      )
    }

    private static func quality(
      _ quality: AVSpeechSynthesisVoiceQuality
    ) -> GuidanceSpeechVoiceQuality {
      switch quality {
      case .premium:
        .premium
      case .enhanced:
        .enhanced
      case .default:
        .defaultQuality
      @unknown default:
        .defaultQuality
      }
    }

    private static func traits(
      _ voice: AVSpeechSynthesisVoice
    ) -> (isNoveltyVoice: Bool, isPersonalVoice: Bool) {
      if #available(iOS 17.0, tvOS 17.0, watchOS 10.0, *) {
        return (
          voice.voiceTraits.contains(.isNoveltyVoice),
          voice.voiceTraits.contains(.isPersonalVoice)
        )
      }
      return (false, false)
    }
  }

  extension AVSpeechGuidanceOutput:
    @preconcurrency AVSpeechSynthesizerDelegate
  {
    public func speechSynthesizer(
      _: AVSpeechSynthesizer,
      didStart utterance: AVSpeechUtterance
    ) {
      guard
        let identity = identityByUtterance[ObjectIdentifier(utterance)]
      else {
        return
      }
      eventHandler?(.didStart(identity))
    }

    public func speechSynthesizer(
      _: AVSpeechSynthesizer,
      didFinish utterance: AVSpeechUtterance
    ) {
      complete(utterance, event: GuidanceSpeechOutputEvent.didFinish)
    }

    public func speechSynthesizer(
      _: AVSpeechSynthesizer,
      didCancel utterance: AVSpeechUtterance
    ) {
      complete(utterance, event: GuidanceSpeechOutputEvent.didCancel)
    }
  }
#endif
