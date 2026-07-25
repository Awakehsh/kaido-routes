import AVFAudio
import XCTest

@testable import KaidoAppleAdapters

final class GuidanceSpeechProsodyTests: XCTestCase {
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
