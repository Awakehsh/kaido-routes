import Foundation
import KaidoPresentation

#if canImport(OSLog)
  import OSLog
#endif

#if os(iOS) || os(tvOS) || os(watchOS) || targetEnvironment(macCatalyst)
  import AVFAudio
  import OSLog
#endif

public enum GuidanceSpeechOutputFailureCode: String, Equatable, Sendable {
  case voiceUnavailable = "VOICE_UNAVAILABLE"
  case audioSessionConfigurationFailed = "AUDIO_SESSION_CONFIGURATION_FAILED"
  case audioSessionActivationFailed = "AUDIO_SESSION_ACTIVATION_FAILED"
  case recordedAudioPlaybackFailed = "RECORDED_AUDIO_PLAYBACK_FAILED"
  case playbackTimedOut = "PLAYBACK_TIMED_OUT"
  case retryLimitReached = "RETRY_LIMIT_REACHED"
}

public enum GuidanceSpeechOutputError: Error, Equatable, Sendable {
  case voiceUnavailable(String)
  case audioSessionConfigurationFailed
  case audioSessionActivationFailed
  case recordedAudioPlaybackFailed

  public var code: GuidanceSpeechOutputFailureCode {
    switch self {
    case .voiceUnavailable:
      .voiceUnavailable
    case .audioSessionConfigurationFailed:
      .audioSessionConfigurationFailed
    case .audioSessionActivationFailed:
      .audioSessionActivationFailed
    case .recordedAudioPlaybackFailed:
      .recordedAudioPlaybackFailed
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
  var isInterrupted: Bool { get }

  func speak(_ command: GuidanceSpeechCommand) throws
  func stop()
  func recoverAfterInterruption() throws -> Bool
}

extension GuidanceSpeechOutput {
  public var isInterrupted: Bool { false }
  public func recoverAfterInterruption() throws -> Bool { false }
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

public enum GuidanceSpeechMode: String, CaseIterable, Sendable {
  case full = "FULL"
  case concise = "CONCISE"
  case muted = "MUTED"
}

public enum GuidanceSpeechVolume: String, CaseIterable, Sendable {
  case soft = "SOFT"
  case normal = "NORMAL"
  case loud = "LOUD"

  public static let preferenceKey = "app.kaidoroutes.guidance.volume"

  public var gain: Float {
    switch self {
    case .soft: 0.45
    case .normal: 0.75
    case .loud: 1
    }
  }

  public static func stored(in defaults: UserDefaults = .standard) -> Self {
    defaults.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? .loud
  }
}

/// Connects the pure exactly-once speech scheduler to one Apple audio output.
///
/// Output callbacks may arrive after a newer command replaces an old one. The
/// scheduler ignores those stale callbacks by exact prompt/anchor/occurrence
/// identity, so they cannot stop or replay current guidance.
@MainActor
public final class GuidanceSpeechCoordinator {
  #if canImport(OSLog)
    private static let log = OSLog(subsystem: "app.kaidoroutes", category: "GuidanceAudio")
  #endif
  public private(set) var scheduler: GuidanceSpeechScheduler
  public private(set) var startedIdentities: Set<GuidanceSpeechIdentity> = []
  public private(set) var completedIdentities: Set<GuidanceSpeechIdentity> = []
  public private(set) var status: GuidanceSpeechCoordinatorStatus = .idle {
    didSet {
      guard status != oldValue else { return }
      statusDidChange?(status)
    }
  }
  public var statusDidChange: ((GuidanceSpeechCoordinatorStatus) -> Void)?
  public private(set) var mode: GuidanceSpeechMode = .full
  public var selectedVoiceProfile: GuidanceSpeechVoiceProfile? { output.selectedVoiceProfile }

  public static let playbackTimeoutSeconds: TimeInterval = 30
  private static let retryIntervalSeconds: TimeInterval = 2
  private static let maximumStartAttempts = 3
  private let output: any GuidanceSpeechOutput
  private let now: () -> TimeInterval
  private var activeSurfaceCommand: GuidanceSpeechCommand?
  private var consumedSurfaceIdentities: Set<GuidanceSpeechIdentity> = []
  private var attempts: [GuidanceSpeechIdentity: (count: Int, at: TimeInterval)] = [:]
  private var lastRecoveryAttempt: TimeInterval = -.infinity
  private var deadline: (identity: GuidanceSpeechIdentity, at: TimeInterval)?
  private var deadlineTask: Task<Void, Never>?

  public init(
    expectedRoutePlanID: String,
    output: any GuidanceSpeechOutput,
    now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
  ) throws {
    scheduler = try GuidanceSpeechScheduler(expectedRoutePlanID: expectedRoutePlanID)
    self.output = output
    self.now = now
    output.eventHandler = { [weak self] event in self?.handle(event) }
  }

  @discardableResult
  public func submit(_ projection: NavigationPresentationProjection)
    -> GuidanceSpeechCoordinatorStatus
  {
    submit(projection, requestedRepeat: false)
  }

  public func setMode(_ mode: GuidanceSpeechMode) {
    guard self.mode != mode else { return }
    self.mode = mode
    invalidateGuidance()
    if mode == .muted { status = .suppressed(.voicePreference) }
  }

  @discardableResult
  public func repeatCurrent(_ projection: NavigationPresentationProjection)
    -> GuidanceSpeechCoordinatorStatus
  {
    let identity = GuidanceSpeechIdentity(
      promptID: projection.voice.promptID,
      anchorID: projection.iPhone.guidanceAnchorID,
      anchorOccurrenceID: projection.iPhone.guidanceAnchorOccurrenceID
    )
    guard startedIdentities.contains(identity) else { return suppress(.notAuthorized) }
    return submit(projection, requestedRepeat: true)
  }

  private func submit(
    _ projection: NavigationPresentationProjection, requestedRepeat: Bool
  ) -> GuidanceSpeechCoordinatorStatus
  {
    guard mode != .muted else { return suppress(.voicePreference) }
    if !requestedRepeat, mode == .concise,
      projection.voice.stage == .prepare || projection.voice.stage == .preview
        || projection.voice.maneuver == .stayMainline
    { return suppress(.voicePreference) }
    checkPlaybackDeadline()
    guard recoverOutputIfNeeded() else { return status }
    do {
      switch try scheduler.submit(projection, requestedRepeat: requestedRepeat) {
      case .suppressed(let reason):
        return suppress(reason)
      case .speak(let command, let replacing):
        if activeSurfaceCommand != nil {
          releaseActiveSurfaceCommand()
          output.stop()
        }
        if replacing != nil { output.stop() }
        play(command)
      }
    } catch {
      status = .invalidProjection
    }
    return status
  }

  /// Provider text remains route-bound but cannot preempt released guidance.
  /// A refused or unstarted step is not delivered and remains retryable while
  /// the caller continues to identify it as the current valid instruction.
  @discardableResult
  public func submitProviderSurface(_ command: GuidanceSpeechCommand)
    -> GuidanceSpeechCoordinatorStatus
  {
    guard mode != .muted else { return suppress(.voicePreference) }
    checkPlaybackDeadline()
    guard
      command.routePlanID.trimmingCharacters(in: .whitespacesAndNewlines)
        == scheduler.expectedRoutePlanID,
      [
        command.identity.promptID, command.identity.anchorID, command.identity.anchorOccurrenceID,
        command.languageCode, command.spokenText, command.synthesisText,
      ].allSatisfy({
        !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      })
    else {
      status = .invalidProjection
      return status
    }
    guard !consumedSurfaceIdentities.contains(command.identity) else { return suppress(.duplicate) }
    guard recoverOutputIfNeeded() else { return status }
    guard scheduler.state != .stopped else { return suppress(.stopped) }
    guard scheduler.activeCommand == nil else { return suppress(.notAuthorized) }
    if let activeSurfaceCommand,
      activeSurfaceCommand.identity.anchorID == "JOURNEY_STATUS",
      command.identity.anchorID != "JOURNEY_STATUS"
    {
      releaseActiveSurfaceCommand()
      output.stop()
    }
    guard activeSurfaceCommand == nil else { return suppress(.notAuthorized) }
    consumedSurfaceIdentities.insert(command.identity)
    activeSurfaceCommand = command
    play(command)
    return status
  }

  @discardableResult
  public func repeatCurrentSurface(_ command: GuidanceSpeechCommand)
    -> GuidanceSpeechCoordinatorStatus
  {
    guard mode != .muted,
      command.identity.anchorID == "PROVIDER_SURFACE_STEP",
      startedIdentities.contains(command.identity),
      scheduler.activeCommand == nil
    else { return suppress(.notAuthorized) }
    stopProviderSurface()
    return submitProviderSurface(
      GuidanceSpeechCommand(
        identity: GuidanceSpeechIdentity(
          promptID: command.identity.promptID,
          anchorID: command.identity.anchorID,
          anchorOccurrenceID: command.identity.anchorOccurrenceID,
          deliveryID: UUID()
        ),
        routePlanID: command.routePlanID, languageCode: command.languageCode,
        spokenText: command.spokenText, synthesisText: command.synthesisText
      )
    )
  }

  /// Informational journey notices use the same bounded output and yield to
  /// maneuver speech. They do not authorize any route movement.
  @discardableResult
  public func submitNotice(_ command: GuidanceSpeechCommand) -> GuidanceSpeechCoordinatorStatus {
    guard command.identity.anchorID == "JOURNEY_STATUS" else {
      status = .invalidProjection
      return status
    }
    if let activeSurfaceCommand,
      activeSurfaceCommand.identity.anchorID == "JOURNEY_STATUS",
      activeSurfaceCommand.identity != command.identity
    {
      stopProviderSurface()
    }
    return submitProviderSurface(command)
  }

  public func stopProviderSurface() {
    guard activeSurfaceCommand != nil else { return }
    clearDeadline()
    releaseActiveSurfaceCommand()
    output.stop()
    status = .idle
  }

  /// Called when positioning, phase or route validity withdraws a maneuver.
  /// It does not stop the journey or replay an obsolete instruction.
  public func invalidateGuidance(keepingNotices: Bool = false) {
    if keepingNotices, activeSurfaceCommand?.identity.anchorID == "JOURNEY_STATUS" { return }
    clearDeadline()
    if let identity = scheduler.activeCommand?.identity {
      releaseReleasedCommand(identity)
    }
    releaseActiveSurfaceCommand()
    output.stop()
    if scheduler.state != .interrupted && scheduler.state != .stopped { status = .idle }
  }

  public func stop() {
    invalidateGuidance()
    _ = scheduler.stop()
    status = .stopped
  }

  public func resume() {
    checkPlaybackDeadline()
    scheduler.resume()
    if scheduler.state == .idle { status = .idle }
  }

  public func checkPlaybackDeadline() {
    guard let deadline, now() >= deadline.at else { return }
    guard activeIdentity == deadline.identity else {
      clearDeadline()
      return
    }
    #if canImport(OSLog)
      os_log("Guidance playback deadline expired", log: Self.log, type: .error)
    #endif
    invalidateGuidance()
    status = .failed(.playbackTimedOut)
  }

  private var activeIdentity: GuidanceSpeechIdentity? {
    activeSurfaceCommand?.identity ?? scheduler.activeCommand?.identity
  }

  private func play(_ command: GuidanceSpeechCommand) {
    clearDeadline()
    let time = now()
    if let previous = attempts[command.identity] {
      if previous.count >= Self.maximumStartAttempts {
        #if canImport(OSLog)
          if status != .failed(.retryLimitReached) {
            os_log("Guidance start retry limit reached", log: Self.log, type: .error)
          }
        #endif
        releaseCommand(command.identity)
        status = .failed(.retryLimitReached)
        return
      }
      if time - previous.at < Self.retryIntervalSeconds {
        releaseCommand(command.identity)
        status = .suppressed(.retryPending)
        return
      }
    }
    attempts[command.identity] = ((attempts[command.identity]?.count ?? 0) + 1, time)
    status = .scheduled(command.identity)
    do {
      try output.speak(command)
      guard activeIdentity == command.identity else { return }
      deadline = (command.identity, time + Self.playbackTimeoutSeconds)
      deadlineTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: 30_000_000_000)
        guard !Task.isCancelled else { return }
        self?.checkPlaybackDeadline()
      }
    } catch let error as GuidanceSpeechOutputError {
      releaseCommand(command.identity)
      output.stop()
      status = .failed(error.code)
    } catch {
      releaseCommand(command.identity)
      output.stop()
      status = .failed(.audioSessionActivationFailed)
    }
  }

  private func recoverOutputIfNeeded() -> Bool {
    guard scheduler.state != .stopped else { return true }
    guard scheduler.state == .interrupted || output.isInterrupted else { return true }
    let time = now()
    guard time - lastRecoveryAttempt >= Self.retryIntervalSeconds else { return false }
    lastRecoveryAttempt = time
    do {
      guard try output.recoverAfterInterruption() else {
        status = .interrupted
        return false
      }
      // Outputs confirm recovery only after actual session activation.
      return scheduler.state != .interrupted
    } catch let error as GuidanceSpeechOutputError {
      status = .failed(error.code)
    } catch {
      status = .failed(.audioSessionActivationFailed)
    }
    return false
  }

  private func suppress(_ reason: GuidanceSpeechSuppressionReason)
    -> GuidanceSpeechCoordinatorStatus
  {
    let result = GuidanceSpeechCoordinatorStatus.suppressed(reason)
    if activeIdentity == nil { status = result }
    return result
  }

  private func clearDeadline() {
    deadlineTask?.cancel()
    deadlineTask = nil
    deadline = nil
  }

  private func releaseReleasedCommand(_ identity: GuidanceSpeechIdentity) {
    if startedIdentities.contains(identity) {
      _ = scheduler.didCancel(identity)
    } else {
      _ = scheduler.didFailToStart(identity)
    }
  }

  private func releaseActiveSurfaceCommand() {
    guard let command = activeSurfaceCommand else { return }
    if !startedIdentities.contains(command.identity) {
      consumedSurfaceIdentities.remove(command.identity)
    }
    activeSurfaceCommand = nil
  }

  private func releaseCommand(_ identity: GuidanceSpeechIdentity) {
    if activeSurfaceCommand?.identity == identity {
      releaseActiveSurfaceCommand()
    } else {
      releaseReleasedCommand(identity)
    }
  }

  private func handle(_ event: GuidanceSpeechOutputEvent) {
    switch event {
    case .didStart(let identity):
      guard activeIdentity == identity else { return }
      startedIdentities.insert(identity)
      status = .speaking(identity)
    case .didFinish(let identity):
      guard activeIdentity == identity else { return }
      startedIdentities.insert(identity)
      completedIdentities.insert(identity)
      clearDeadline()
      releaseCommand(identity)
      status = .idle
    case .didCancel(let identity):
      guard activeIdentity == identity else { return }
      clearDeadline()
      releaseCommand(identity)
      status = .idle
    case .interruptionBegan:
      guard scheduler.state != .stopped else { return }
      clearDeadline()
      if let identity = scheduler.activeCommand?.identity { releaseReleasedCommand(identity) }
      releaseActiveSurfaceCommand()
      _ = scheduler.interruptionBegan()
      lastRecoveryAttempt = -.infinity
      status = .interrupted
    case .interruptionEnded:
      scheduler.interruptionEnded()
      attempts.removeAll()
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
    private static let log = OSLog(
      subsystem: "app.kaidoroutes", category: "GuidanceAudio"
    )
    public var eventHandler: ((GuidanceSpeechOutputEvent) -> Void)?
    public private(set) var selectedVoiceProfile: GuidanceSpeechVoiceProfile?

    private var synthesizer: AVSpeechSynthesizer
    private let notifications: NotificationCenter
    private let synthesizerFactory: () -> AVSpeechSynthesizer
    private var interruptionPending = false
    public var isInterrupted: Bool { interruptionPending }
    private let audioSession: AVAudioSession
    private let preferredVoiceIdentifierProvider: (String) -> String?
    private var identityByUtterance: [ObjectIdentifier: GuidanceSpeechIdentity] = [:]
    private var activeUtteranceID: ObjectIdentifier?

    public init(
      synthesizer: AVSpeechSynthesizer = AVSpeechSynthesizer(),
      audioSession: AVAudioSession = .sharedInstance(),
      synthesizerFactory: @escaping () -> AVSpeechSynthesizer = { AVSpeechSynthesizer() },
      notifications: NotificationCenter = .default,
      preferredVoiceIdentifierProvider: @escaping (String) -> String? = {
        _ in nil
      }
    ) {
      self.synthesizer = synthesizer
      self.notifications = notifications
      self.synthesizerFactory = synthesizerFactory
      self.audioSession = audioSession
      self.preferredVoiceIdentifierProvider =
        preferredVoiceIdentifierProvider
      super.init()
      synthesizer.delegate = self
      notifications.addObserver(
        self,
        selector: #selector(handleAudioInterruption(_:)),
        name: AVAudioSession.interruptionNotification,
        object: audioSession
      )
      notifications.addObserver(
        self, selector: #selector(handleMediaServicesReset(_:)),
        name: AVAudioSession.mediaServicesWereResetNotification, object: audioSession
      )
      notifications.addObserver(
        self, selector: #selector(handleAudioRouteChange(_:)),
        name: AVAudioSession.routeChangeNotification, object: audioSession
      )
    }

    deinit {
      notifications.removeObserver(self)
    }

    public func speak(_ command: GuidanceSpeechCommand) throws {
      // The coordinator stops an admitted replacement before calling speak.
      // Only cancel here when a direct caller still owns an active utterance;
      // stopping the same synthesizer twice while its cancellation settles can
      // crash the simulator audio service.
      if activeUtteranceID != nil {
        cancelActiveUtterance()
      }

      guard
        let selection = Self.navigationVoiceSelection(
          for: command.languageCode,
          preferredIdentifier: preferredVoiceIdentifierProvider(
            command.languageCode
          )
        )
      else {
        throw GuidanceSpeechOutputError.voiceUnavailable(
          command.languageCode
        )
      }
      selectedVoiceProfile = selection.profile

      try activateAudioSession()

      let utterance = AVSpeechUtterance(string: command.synthesisText)
      utterance.volume = GuidanceSpeechVolume.stored().gain
      utterance.voice = selection.voice
      let prosody = GuidanceSpeechProsody.navigation(languageCode: command.languageCode)
      utterance.applyGuidanceProsody(prosody, minimumLeadIn: 0.6)
      let utteranceID = ObjectIdentifier(utterance)
      identityByUtterance[utteranceID] = command.identity
      activeUtteranceID = utteranceID
      let ports = audioSession.currentRoute.outputs.map { $0.portType.rawValue }.joined(
        separator: ",")
      os_log("Speech submitted; output ports: %{public}@", log: Self.log, type: .default, ports)
      synthesizer.speak(utterance)
    }

    private func activateAudioSession() throws {
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
        os_log("Audio configuration failed: %ld", log: Self.log, type: .error, (error as NSError).code)
        throw GuidanceSpeechOutputError.audioSessionConfigurationFailed
      }
      do {
        try audioSession.setActive(true)
      } catch {
        os_log("Audio activation failed: %ld", log: Self.log, type: .error, (error as NSError).code)
        if !interruptionPending {
          interruptionPending = true
          eventHandler?(.interruptionBegan)
        }
        throw GuidanceSpeechOutputError.audioSessionActivationFailed
      }

      if interruptionPending {
        interruptionPending = false
        eventHandler?(.interruptionEnded)
      }
    }

    /// Resolves only the explicit preference and the system locale default.
    /// Enumerating every installed voice is reserved for the parked settings
    /// screen because `speechVoices()` can synchronously block first playback.
    static func navigationVoiceSelection(
      for languageCode: String,
      preferredIdentifier: String?
    ) -> (voice: AVSpeechSynthesisVoice, profile: GuidanceSpeechVoiceProfile)? {
      let defaultVoice = AVSpeechSynthesisVoice(language: languageCode)
      var voicesByIdentifier: [String: AVSpeechSynthesisVoice] = [:]
      var candidates: [GuidanceSpeechVoiceCandidate] = []
      for voice in [
        preferredIdentifier.flatMap(AVSpeechSynthesisVoice.init(identifier:)),
        defaultVoice,
      ].compactMap({ $0 }) {
        guard voicesByIdentifier[voice.identifier] == nil else { continue }
        voicesByIdentifier[voice.identifier] = voice
        let voiceTraits = traits(voice)
        candidates.append(
          GuidanceSpeechVoiceCandidate(
            identifier: voice.identifier,
            name: voice.name,
            languageCode: voice.language,
            quality: quality(voice.quality),
            isNoveltyVoice: voiceTraits.isNoveltyVoice,
            isPersonalVoice: voiceTraits.isPersonalVoice
          )
        )
      }
      guard
        let profile = GuidanceSpeechVoiceSelector.select(
          languageCode: languageCode,
          candidates: candidates,
          systemDefaultIdentifier: defaultVoice?.identifier,
          preferredIdentifier: preferredIdentifier
        ),
        let voice = voicesByIdentifier[profile.identifier]
      else {
        return nil
      }
      return (voice, profile)
    }

    public static func preferredInstalledVoiceProfile(
      for languageCode: String,
      preferredIdentifier: String? = nil
    ) -> GuidanceSpeechVoiceProfile? {
      installedVoiceProfiles(
        for: languageCode,
        preferredIdentifier: preferredIdentifier
      ).first
    }

    public static func installedVoiceProfiles(
      for languageCode: String,
      preferredIdentifier: String? = nil
    ) -> [GuidanceSpeechVoiceProfile] {
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
      let ranked = GuidanceSpeechVoiceSelector.rankedProfiles(
        languageCode: languageCode,
        candidates: candidates,
        systemDefaultIdentifier: defaultVoice?.identifier
      )
      guard
        let preferredIdentifier,
        let preferredIndex = ranked.firstIndex(where: {
          $0.identifier == preferredIdentifier
        }),
        preferredIndex != ranked.startIndex
      else {
        return ranked
      }
      var preferredFirst = ranked
      let preferred = preferredFirst.remove(at: preferredIndex)
      preferredFirst.insert(preferred, at: preferredFirst.startIndex)
      return preferredFirst
    }

    public func stop() {
      cancelActiveUtterance()
    }

    public func recoverAfterInterruption() throws -> Bool {
      try activateAudioSession()
      return true
    }

    @objc
    private func handleMediaServicesReset(_ notification: Notification) {
      interruptionPending = true
      eventHandler?(.interruptionBegan)
      synthesizer.delegate = nil
      identityByUtterance.removeAll()
      activeUtteranceID = nil
      synthesizer = synthesizerFactory()
      synthesizer.delegate = self
      os_log("Speech output rebuilt after media services reset", log: Self.log, type: .default)
    }

    @objc
    private func handleAudioRouteChange(_ notification: Notification) {
      guard let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
        let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason),
        reason == .oldDeviceUnavailable || reason == .newDeviceAvailable
      else { return }
      interruptionPending = true
      eventHandler?(.interruptionBegan)
      cancelActiveUtterance()
      os_log("Speech output route changed", log: Self.log, type: .default)
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
        os_log("Audio interruption began", log: Self.log, type: .default)
        interruptionPending = true
        eventHandler?(.interruptionBegan)
        cancelActiveUtterance()
      case .ended:
        os_log("Audio interruption ended", log: Self.log, type: .default)
        interruptionPending = false
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
      os_log("Speech callback completed; active: %d", log: Self.log, type: .default, wasActive)
      if wasActive {
        activeUtteranceID = nil
        deactivateAudioSession()
      }
      eventHandler?(event(identity))
    }

    private func deactivateAudioSession() {
      do {
        try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
      } catch {
        os_log("Audio deactivation failed: %ld", log: Self.log, type: .error, (error as NSError).code)
      }
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
      os_log("Speech synthesis started", log: Self.log, type: .default)
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
