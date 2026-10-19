import AVFAudio
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
