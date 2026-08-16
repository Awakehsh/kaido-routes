import AVFAudio
import KaidoAppleAdapters
import KaidoPresentation
import XCTest

@MainActor
final class PhysicalAudioQualificationTests: XCTestCase {
  func testGuidanceOutputStopsBeforeImmediateReplacement() async throws {
    let output = AVSpeechGuidanceOutput()
    defer { output.stop() }
    let firstIdentity = GuidanceSpeechIdentity(
      promptID: "surface.access.0",
      anchorID: "PROVIDER_SURFACE_STEP",
      anchorOccurrenceID: "surface.access.0"
    )
    let secondIdentity = GuidanceSpeechIdentity(
      promptID: "surface.access.1",
      anchorID: "PROVIDER_SURFACE_STEP",
      anchorOccurrenceID: "surface.access.1"
    )
    let secondStarted = expectation(description: "replacement started")
    let secondFinished = expectation(description: "replacement finished")
    output.eventHandler = { event in
      switch event {
      case .didStart(let identity) where identity == secondIdentity:
        secondStarted.fulfill()
      case .didFinish(let identity) where identity == secondIdentity:
        secondFinished.fulfill()
      default:
        break
      }
    }

    try output.speak(
      GuidanceSpeechCommand(
        identity: firstIdentity,
        routePlanID: "test.plan.surface-audio",
        languageCode: "en-US",
        spokenText: "Continue straight"
      )
    )
    output.stop()
    try output.speak(
      GuidanceSpeechCommand(
        identity: secondIdentity,
        routePlanID: "test.plan.surface-audio",
        languageCode: "en-US",
        spokenText: "Turn left"
      )
    )

    await fulfillment(
      of: [secondStarted, secondFinished],
      timeout: 20,
      enforceOrder: true
    )
  }

  func testInstalledVoicesCompleteThroughTheVoicePromptOutputRoute()
    async throws
  {
    let output = AVSpeechVoiceAuditionOutput()
    defer {
      output.stop()
    }

    for sample in [
      (languageCode: "ja-JP", spokenText: "K7、第三京浜・出口へ"),
      (languageCode: "zh-CN", spokenText: "K7，前往第三京浜・出口へ"),
      (languageCode: "en-US", spokenText: "K7, toward 第三京浜・出口へ"),
    ] {
      let started = expectation(
        description: "\(sample.languageCode) started"
      )
      let finished = expectation(
        description: "\(sample.languageCode) finished"
      )
      var startedProfile: GuidanceSpeechVoiceProfile?
      var outputPortTypes: [String] = []

      output.eventHandler = { event in
        switch event {
        case .didStart(let profile):
          let audioSession = AVAudioSession.sharedInstance()
          startedProfile = profile
          outputPortTypes = audioSession.currentRoute.outputs
            .map(\.portType.rawValue)
            .filter { !$0.isEmpty }
            .sorted()
          XCTAssertEqual(profile.languageCode, sample.languageCode)
          XCTAssertEqual(audioSession.category, .playback)
          XCTAssertEqual(audioSession.mode, .voicePrompt)
          XCTAssertFalse(outputPortTypes.isEmpty)
          started.fulfill()
        case .didFinish(let profile):
          XCTAssertEqual(profile, startedProfile)
          finished.fulfill()
        case .didCancel:
          XCTFail("Physical audio audition was cancelled")
          finished.fulfill()
        }
      }

      try output.audition(
        GuidanceVoiceAuditionRequest(
          languageCode: sample.languageCode,
          preferredVoiceIdentifier: nil,
          spokenText: sample.spokenText
        )
      )
      await fulfillment(
        of: [started, finished],
        timeout: 20,
        enforceOrder: true
      )

      XCTAssertNotNil(startedProfile)
      XCTAssertFalse(outputPortTypes.isEmpty)
    }
  }
}
