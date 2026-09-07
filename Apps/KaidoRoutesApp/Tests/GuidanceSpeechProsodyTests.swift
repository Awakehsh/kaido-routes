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
    XCTAssertEqual(events, [.interruptionBegan])
    notifications.post(
      name: AVAudioSession.interruptionNotification, object: session,
      userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
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
    XCTAssertEqual(events, [.interruptionBegan])
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
}
