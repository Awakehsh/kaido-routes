import Foundation
import KaidoPresentation

#if os(iOS) || os(tvOS) || os(watchOS) || targetEnvironment(macCatalyst)
  import AVFAudio
#endif

public enum GuidanceRecordedAudioPlaybackEvent: Equatable, Sendable {
  case didStart(UUID)
  case didFinish(UUID)
  case didCancel(UUID)
  case interruptionBegan(UUID)
  case interruptionEnded(UUID)
}

/// Plays one already validated local guidance-audio resource.
///
/// A failed `play` call must not emit an event. Once `play` succeeds, the
/// player owns exactly one terminal finish or cancel event for its playback ID.
@MainActor
public protocol GuidanceRecordedAudioPlaying: AnyObject {
  var eventHandler: ((GuidanceRecordedAudioPlaybackEvent) -> Void)? {
    get set
  }

  func play(
    _ asset: ReleasedGuidanceAudioAsset,
    playbackID: UUID
  ) throws
  func stop()
}

/// Uses a complete reviewed audio release before falling back to Apple TTS.
///
/// Released audio is selected only by the exact RoutePlan, prompt, anchor,
/// occurrence, locale, and spoken-text identity. A lookup or playback-start
/// failure uses the supplied fallback. Once recorded playback starts, a later
/// failure or interruption is terminal and is never replayed through fallback.
@MainActor
public final class ReleasedGuidanceAudioOutput: GuidanceSpeechOutput {
  public var eventHandler: ((GuidanceSpeechOutputEvent) -> Void)?
  public var selectedVoiceProfile: GuidanceSpeechVoiceProfile? {
    isUsingFallback ? fallback.selectedVoiceProfile : nil
  }

  private enum ActiveSource {
    case recorded(
      playbackID: UUID,
      identity: GuidanceSpeechIdentity
    )
    case fallback(GuidanceSpeechIdentity)
  }

  private enum InterruptedSource {
    case recorded(UUID)
    case fallback
  }

  private let release: GuidanceAudioRelease
  private let player: any GuidanceRecordedAudioPlaying
  private let fallback: any GuidanceSpeechOutput
  private var activeSource: ActiveSource?
  private var interruptedSource: InterruptedSource?
  private var isUsingFallback = false

  public init(
    release: GuidanceAudioRelease,
    player: any GuidanceRecordedAudioPlaying,
    fallback: any GuidanceSpeechOutput
  ) {
    self.release = release
    self.player = player
    self.fallback = fallback
    player.eventHandler = { [weak self] event in
      self?.handleRecordedEvent(event)
    }
    fallback.eventHandler = { [weak self] event in
      self?.handleFallbackEvent(event)
    }
  }

  public func speak(_ command: GuidanceSpeechCommand) throws {
    stop()

    guard let asset = release.asset(matching: command) else {
      try speakWithFallback(command)
      return
    }

    let playbackID = UUID()
    isUsingFallback = false
    activeSource = .recorded(
      playbackID: playbackID,
      identity: command.identity
    )
    do {
      try player.play(asset, playbackID: playbackID)
    } catch {
      if case .recorded(let activeID, _) = activeSource,
        activeID == playbackID
      {
        activeSource = nil
      }
      try speakWithFallback(command)
    }
  }

  public func stop() {
    interruptedSource = nil
    guard let activeSource else { return }
    self.activeSource = nil

    switch activeSource {
    case .recorded(_, let identity):
      player.stop()
      eventHandler?(.didCancel(identity))
    case .fallback(let identity):
      fallback.stop()
      eventHandler?(.didCancel(identity))
    }
  }

  private func speakWithFallback(
    _ command: GuidanceSpeechCommand
  ) throws {
    isUsingFallback = true
    activeSource = .fallback(command.identity)
    do {
      try fallback.speak(command)
    } catch {
      activeSource = nil
      throw error
    }
  }

  private func handleRecordedEvent(
    _ event: GuidanceRecordedAudioPlaybackEvent
  ) {
    switch event {
    case .didStart(let playbackID):
      guard
        case .recorded(let activeID, let identity) = activeSource,
        activeID == playbackID
      else {
        return
      }
      eventHandler?(.didStart(identity))
    case .didFinish(let playbackID):
      guard
        case .recorded(let activeID, let identity) = activeSource,
        activeID == playbackID
      else {
        return
      }
      activeSource = nil
      eventHandler?(.didFinish(identity))
    case .didCancel(let playbackID):
      guard
        case .recorded(let activeID, let identity) = activeSource,
        activeID == playbackID
      else {
        return
      }
      activeSource = nil
      eventHandler?(.didCancel(identity))
    case .interruptionBegan(let playbackID):
      guard
        case .recorded(let activeID, _) = activeSource,
        activeID == playbackID
      else {
        return
      }
      activeSource = nil
      interruptedSource = .recorded(playbackID)
      eventHandler?(.interruptionBegan)
    case .interruptionEnded(let playbackID):
      guard
        case .recorded(let interruptedID) = interruptedSource,
        interruptedID == playbackID
      else {
        return
      }
      interruptedSource = nil
      eventHandler?(.interruptionEnded)
    }
  }

  private func handleFallbackEvent(
    _ event: GuidanceSpeechOutputEvent
  ) {
    switch event {
    case .didStart(let identity):
      guard
        case .fallback(let activeIdentity) = activeSource,
        activeIdentity == identity
      else {
        return
      }
      eventHandler?(event)
    case .didFinish(let identity), .didCancel(let identity):
      guard
        case .fallback(let activeIdentity) = activeSource,
        activeIdentity == identity
      else {
        return
      }
      activeSource = nil
      eventHandler?(event)
    case .interruptionBegan:
      guard case .fallback = activeSource else { return }
      activeSource = nil
      interruptedSource = .fallback
      eventHandler?(event)
    case .interruptionEnded:
      guard case .fallback = interruptedSource else { return }
      interruptedSource = nil
      eventHandler?(event)
    }
  }
}

#if os(iOS) || os(tvOS) || os(watchOS) || targetEnvironment(macCatalyst)
  /// Local WAV playback through Apple's navigation voice-prompt audio route.
  @MainActor
  public final class AVAudioPlayerGuidancePlayback: NSObject,
    GuidanceRecordedAudioPlaying
  {
    public var eventHandler:
      (
        (GuidanceRecordedAudioPlaybackEvent) -> Void
      )?

    private let audioSession: AVAudioSession
    private var audioPlayer: AVAudioPlayer?
    private var activePlaybackID: UUID?
    private var interruptedPlaybackID: UUID?

    public init(audioSession: AVAudioSession = .sharedInstance()) {
      self.audioSession = audioSession
      super.init()
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

    public func play(
      _ asset: ReleasedGuidanceAudioAsset,
      playbackID: UUID
    ) throws {
      stop()

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
        throw GuidanceSpeechOutputError
          .audioSessionConfigurationFailed
      }
      do {
        try audioSession.setActive(true)
      } catch {
        throw GuidanceSpeechOutputError.audioSessionActivationFailed
      }

      do {
        let player = try AVAudioPlayer(contentsOf: asset.resourceURL)
        player.delegate = self
        player.volume = 1
        guard player.prepareToPlay(), player.play() else {
          deactivateAudioSession()
          throw GuidanceSpeechOutputError.recordedAudioPlaybackFailed
        }
        audioPlayer = player
        activePlaybackID = playbackID
        eventHandler?(.didStart(playbackID))
      } catch let error as GuidanceSpeechOutputError {
        throw error
      } catch {
        deactivateAudioSession()
        throw GuidanceSpeechOutputError.recordedAudioPlaybackFailed
      }
    }

    public func stop() {
      guard let playbackID = activePlaybackID else { return }
      activePlaybackID = nil
      audioPlayer?.stop()
      audioPlayer = nil
      deactivateAudioSession()
      eventHandler?(.didCancel(playbackID))
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
        guard let playbackID = activePlaybackID else { return }
        interruptedPlaybackID = playbackID
        eventHandler?(.interruptionBegan(playbackID))
        stop()
      case .ended:
        guard let playbackID = interruptedPlaybackID else { return }
        interruptedPlaybackID = nil
        eventHandler?(.interruptionEnded(playbackID))
      @unknown default:
        break
      }
    }

    private func complete(_ successfully: Bool) {
      guard let playbackID = activePlaybackID else { return }
      activePlaybackID = nil
      audioPlayer = nil
      deactivateAudioSession()
      eventHandler?(
        successfully ? .didFinish(playbackID) : .didCancel(playbackID)
      )
    }

    private func deactivateAudioSession() {
      try? audioSession.setActive(
        false,
        options: .notifyOthersOnDeactivation
      )
    }
  }

  extension AVAudioPlayerGuidancePlayback:
    @preconcurrency AVAudioPlayerDelegate
  {
    public func audioPlayerDidFinishPlaying(
      _: AVAudioPlayer,
      successfully flag: Bool
    ) {
      complete(flag)
    }

    public func audioPlayerDecodeErrorDidOccur(
      _: AVAudioPlayer,
      error _: (any Error)?
    ) {
      complete(false)
    }
  }
#endif
