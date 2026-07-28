import AVFAudio
import KaidoAppleAdapters
import XCTest

@MainActor
final class PhysicalAudioQualificationTests: XCTestCase {
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
