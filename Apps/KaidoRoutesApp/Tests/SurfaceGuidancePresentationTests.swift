import KaidoDomain
import XCTest
@testable import KaidoRoutesApp

final class SurfaceGuidancePresentationTests: XCTestCase {
  func testKeepRightDoesNotBecomeARightTurnAcrossLanguages() {
    let result = SurfaceGuidancePresentation.instruction("Keep right at the fork", sourceLanguageCode: "en-US", locale: .simplifiedChinese)
    XCTAssertEqual(result.text, "保持右侧行驶")
    XCTAssertEqual(result.languageCode, "zh-CN")
    XCTAssertEqual(SurfaceManeuver.from(instruction: "Keep right at the fork"), .keepRight)
  }

  func testInterfaceAndVoiceCanUseDifferentWordingForTheSameSource() {
    let source = "左折して晴海通りに入ります"
    XCTAssertEqual(SurfaceGuidancePresentation.instruction(source, sourceLanguageCode: "ja-JP", locale: .japanese).text, source)
    XCTAssertEqual(SurfaceGuidancePresentation.instruction(source, sourceLanguageCode: "ja-JP", locale: .english).text, "Turn left")
    XCTAssertEqual(SurfaceGuidancePresentation.instruction(source, sourceLanguageCode: "ja-JP", locale: .simplifiedChinese).text, "请左转")
  }

  func testMapKitLocationPrefixedTurnUsesTheChosenLanguage() {
    let source = "在港区芝公園三丁目，朝Daiichi Keihin方向右转进入日比谷通り"
    XCTAssertEqual(SurfaceGuidancePresentation.instruction(source, sourceLanguageCode: "zh-CN", locale: .english).text, "Turn right")
    XCTAssertEqual(SurfaceGuidancePresentation.instruction(source, sourceLanguageCode: "zh-CN", locale: .japanese).text, "右折してください")
  }

  func testUnknownActionRetainsOriginalTextAndItsLanguage() {
    let result = SurfaceGuidancePresentation.instruction("Take the third exit at the roundabout", sourceLanguageCode: "en-US", locale: .japanese)
    XCTAssertEqual(result.text, "Take the third exit at the roundabout")
    XCTAssertEqual(result.languageCode, "en-US")
  }
}
