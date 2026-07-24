import KaidoDomain
import XCTest

@testable import KaidoRoutesApp

final class KaidoInterfaceLocalizationTests: XCTestCase {
  func testExactReleaseLocaleSelectsOneInterfaceCopy() {
    let values: [(KaidoReleaseLocale, String)] = [
      (.japanese, "経路"),
      (.simplifiedChinese, "路线"),
      (.english, "Route"),
    ]

    for (locale, expected) in values {
      XCTAssertEqual(
        KaidoInterfaceText(locale: locale).resolve(
          japanese: "経路",
          simplifiedChinese: "路线",
          english: "Route"
        ),
        expected
      )
    }
  }

  func testLanguageNamesAreLocalizedForTheInterfaceNotTheVoice() {
    let japanese = KaidoInterfaceText(locale: .japanese)
    let chinese = KaidoInterfaceText(locale: .simplifiedChinese)
    let english = KaidoInterfaceText(locale: .english)

    XCTAssertEqual(japanese.languageName(.simplifiedChinese), "簡体字中国語")
    XCTAssertEqual(chinese.languageName(.japanese), "日语")
    XCTAssertEqual(english.languageName(.english), "English")
  }
}
