import AVFAudio
import KaidoPresentation
import ObjectiveC
import XCTest

@testable import KaidoAppleAdapters

final class GuidanceSpeechProsodyTests: XCTestCase {
  @MainActor
  func testInterruptionDoesNotInventAnEndEvent() {
    let notifications = NotificationCenter()
    let session = AVAudioSession.sharedInstance()
    let output = AVSpeechGuidanceOutput(audioSession: session, notifications: notifications)
    var events: [GuidanceSpeechOutputEvent] = []
    output.eventHandler = { events.append($0) }
    notifications.post(
      name: AVAudioSession.interruptionNotification, object: session,
      userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
    drainMainQueue()
    XCTAssertEqual(events, [.interruptionBegan])
    notifications.post(
      name: AVAudioSession.interruptionNotification, object: session,
      userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
    drainMainQueue()
    XCTAssertEqual(events, [.interruptionBegan, .interruptionEnded])
  }

  @MainActor
  func testMediaResetReplacesTheOrphanedSynthesizer() {
    let notifications = NotificationCenter()
    let session = AVAudioSession.sharedInstance()
    let original = AVSpeechSynthesizer()
    let replacement = AVSpeechSynthesizer()
    let output = AVSpeechGuidanceOutput(
      synthesizer: original, audioSession: session,
      synthesizerFactory: { replacement }, notifications: notifications)
    var events: [GuidanceSpeechOutputEvent] = []
    output.eventHandler = { events.append($0) }
    notifications.post(name: AVAudioSession.mediaServicesWereResetNotification, object: session)
    drainMainQueue()
    XCTAssertNil(original.delegate)
    XCTAssertTrue(replacement.delegate === output)
    XCTAssertEqual(events, [.interruptionBegan])
  }

  @MainActor
  func testBluetoothRouteChangeWaitsForRecovery() {
    let notifications = NotificationCenter()
    let session = AVAudioSession.sharedInstance()
    let output = AVSpeechGuidanceOutput(audioSession: session, notifications: notifications)
    var events: [GuidanceSpeechOutputEvent] = []
    output.eventHandler = { events.append($0) }
    notifications.post(
      name: AVAudioSession.routeChangeNotification, object: session,
      userInfo: [
        AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.newDeviceAvailable
          .rawValue
      ])
    drainMainQueue()
    XCTAssertEqual(events, [.interruptionBegan])
  }

  @MainActor
  func testAudioSessionNotificationsPostedOffTheMainThreadAreHandledInOrder() {
    let notifications = NotificationCenter()
    let session = AVAudioSession.sharedInstance()
    let original = AVSpeechSynthesizer()
    let replacement = AVSpeechSynthesizer()
    let output = AVSpeechGuidanceOutput(
      synthesizer: original, audioSession: session,
      synthesizerFactory: { replacement }, notifications: notifications)
    var events: [GuidanceSpeechOutputEvent] = []
    output.eventHandler = { events.append($0) }

    // iOS posts route changes on a secondary thread, e.g. when car Bluetooth connects.
    let posted = expectation(description: "posted off the main thread")
    DispatchQueue.global().async {
      notifications.post(
        name: AVAudioSession.routeChangeNotification, object: session,
        userInfo: [
          AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.newDeviceAvailable
            .rawValue
        ])
      notifications.post(
        name: AVAudioSession.interruptionNotification, object: session,
        userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
      notifications.post(name: AVAudioSession.mediaServicesWereResetNotification, object: session)
      posted.fulfill()
    }
    wait(for: [posted], timeout: 5)
    drainMainQueue()

    XCTAssertEqual(events, [.interruptionBegan, .interruptionEnded, .interruptionBegan])
    XCTAssertTrue(output.isInterrupted)
    XCTAssertNil(original.delegate)
    XCTAssertTrue(replacement.delegate === output)
  }

  @MainActor
  func testPrepareSetsTheCategoryWithoutActivatingTheSession() throws {
    let session = AVAudioSession.sharedInstance()
    let recorder = AudioSessionRequestRecorder()
    defer { recorder.uninstall() }
    var voiceLookups: [String] = []
    let synthesizer = SilentSynthesizer()
    let output = AVSpeechGuidanceOutput(
      synthesizer: synthesizer, audioSession: session, notifications: NotificationCenter(),
      preferredVoiceIdentifierProvider: {
        voiceLookups.append($0)
        return nil
      })
    output.prepare(languageCode: "ja-JP")
    XCTAssertEqual(recorder.categories, [.playback])
    XCTAssertEqual(recorder.modes, [.voicePrompt])
    XCTAssertEqual(recorder.activations, [])
    XCTAssertEqual(voiceLookups, ["ja-JP"])

    // The prompt itself still activates the session.
    try output.speak(
      GuidanceSpeechCommand(
        identity: GuidanceSpeechIdentity(
          promptID: "surface.access.0", anchorID: "PROVIDER_SURFACE_STEP",
          anchorOccurrenceID: "surface.access.0"),
        routePlanID: "route", languageCode: "ja-JP", spokenText: "テスト"))
    XCTAssertEqual(recorder.activations, [true])
    XCTAssertEqual(synthesizer.spokenTexts, ["テスト"])
  }

  @MainActor
  func testStoppingWithNothingSpokenDoesNotWaitOnTheSpeechEngine() {
    let synthesizer = SpeakingStateRecordingSynthesizer()
    let output = AVSpeechGuidanceOutput(
      synthesizer: synthesizer, notifications: NotificationCenter())
    output.stop()
    output.stop()
    XCTAssertEqual(synthesizer.speakingStateReads, 0)
    XCTAssertEqual(synthesizer.stopRequests, 0)
  }

  func testNavigationProsodyPreservesBluetoothLeadIn() {
    let utterance = AVSpeechUtterance(string: "test")
    utterance.applyGuidanceProsody(
      .navigation(languageCode: "ja-JP"), minimumLeadIn: 0.6
    )
    XCTAssertEqual(utterance.preUtteranceDelay, 0.6)
  }

  func testSharedUtteranceConfigurationAppliesTheWholeNavigationProsody() {
    let prosody = GuidanceSpeechProsody.navigation(languageCode: "ja-JP")
    let utterance = AVSpeechUtterance(string: "test")

    utterance.applyGuidanceProsody(prosody)

    XCTAssertEqual(utterance.rate, prosody.rate)
    XCTAssertEqual(utterance.pitchMultiplier, prosody.pitchMultiplier)
    XCTAssertEqual(
      utterance.preUtteranceDelay,
      prosody.preUtteranceDelay
    )
    XCTAssertEqual(
      utterance.postUtteranceDelay,
      prosody.postUtteranceDelay
    )
  }

  /// Runs every main-queue block enqueued before this call, including the
  /// main-actor hop each audio-session notification handler takes.
  @MainActor
  private func drainMainQueue() {
    let drained = expectation(description: "main queue drained")
    DispatchQueue.main.async { drained.fulfill() }
    wait(for: [drained], timeout: 5)
  }
}

/// Records category and activation requests on every AVAudioSession, without
/// reaching the audio server, until `uninstall`. The session is a singleton
/// the app cannot subclass or replace, so the recorder swaps the methods. It
/// also keeps the test off the simulator's audio hardware: a first real
/// category set while speech threads run crashed in TextToSpeech once.
@MainActor
final class AudioSessionRequestRecorder {
  private(set) var categories: [AVAudioSession.Category] = []
  private(set) var modes: [AVAudioSession.Mode] = []
  private(set) var activations: [Bool] = []
  private var restorations: [(Method, IMP)] = []

  init() {
    let category: @convention(block) (
      AVAudioSession, NSString, NSString, UInt, UnsafeMutablePointer<NSError?>?
    ) -> Bool = { [unowned self] _, category, mode, _, _ in
      MainActor.assumeIsolated {
        categories.append(AVAudioSession.Category(rawValue: category as String))
        modes.append(AVAudioSession.Mode(rawValue: mode as String))
      }
      return true
    }
    let activation: @convention(block) (
      AVAudioSession, Bool, UInt, UnsafeMutablePointer<NSError?>?
    ) -> Bool = { [unowned self] _, active, _, _ in
      MainActor.assumeIsolated { activations.append(active) }
      return true
    }
    replace(#selector(AVAudioSession.setCategory(_:mode:options:)), with: category)
    replace(#selector(AVAudioSession.setActive(_:options:)), with: activation)
  }

  func uninstall() {
    for (method, original) in restorations { method_setImplementation(method, original) }
    restorations = []
  }

  private func replace(_ selector: Selector, with block: Any) {
    let method = class_getInstanceMethod(AVAudioSession.self, selector)!
    restorations.append((method, method_getImplementation(method)))
    method_setImplementation(method, imp_implementationWithBlock(block))
  }
}

/// Takes utterances without speaking them.
private final class SilentSynthesizer: AVSpeechSynthesizer {
  private(set) var spokenTexts: [String] = []

  override func speak(_ utterance: AVSpeechUtterance) {
    spokenTexts.append(utterance.speechString)
  }
}

/// Counts the calls that block on, or act on, the speech engine.
private final class SpeakingStateRecordingSynthesizer: AVSpeechSynthesizer {
  private(set) var speakingStateReads = 0
  private(set) var stopRequests = 0

  override var isSpeaking: Bool {
    speakingStateReads += 1
    return super.isSpeaking
  }

  override func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
    stopRequests += 1
    return super.stopSpeaking(at: boundary)
  }
}
