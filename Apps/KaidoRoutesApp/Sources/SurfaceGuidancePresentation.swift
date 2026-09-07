import Foundation
import KaidoDomain

enum SurfaceGuidancePresentation {
  static func instruction(
    _ original: String,
    sourceLanguageCode: String?,
    locale: KaidoReleaseLocale
  ) -> (text: String, languageCode: String) {
    let source = sourceLanguageCode.flatMap { code in
      let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
    if let sourceLanguageCode = source,
      Locale.Language(identifier: sourceLanguageCode).languageCode
        == Locale.Language(identifier: locale.rawValue).languageCode
    {
      return (original, sourceLanguageCode)
    }
    let copy = KaidoInterfaceText(locale: locale)
    let text: String
    switch SurfaceManeuver.from(instruction: original) {
    case .left:
      text = copy.resolve(japanese: "左折してください", simplifiedChinese: "请左转", english: "Turn left")
    case .right:
      text = copy.resolve(japanese: "右折してください", simplifiedChinese: "请右转", english: "Turn right")
    case .slightLeft:
      text = copy.resolve(japanese: "左方向へ進んでください", simplifiedChinese: "向左前方行驶", english: "Bear left")
    case .slightRight:
      text = copy.resolve(japanese: "右方向へ進んでください", simplifiedChinese: "向右前方行驶", english: "Bear right")
    case .keepLeft:
      text = copy.resolve(japanese: "左側を進んでください", simplifiedChinese: "保持左侧行驶", english: "Keep left")
    case .keepRight:
      text = copy.resolve(japanese: "右側を進んでください", simplifiedChinese: "保持右侧行驶", english: "Keep right")
    case .straight:
      text = copy.resolve(japanese: "そのまま直進してください", simplifiedChinese: "继续直行", english: "Continue straight")
    case .uTurn:
      text = copy.resolve(japanese: "Uターンしてください", simplifiedChinese: "请掉头", english: "Make a U-turn")
    case .unknown:
      return (original, source ?? locale.speechLanguageCode)
    }
    return (text, locale.speechLanguageCode)
  }
}
