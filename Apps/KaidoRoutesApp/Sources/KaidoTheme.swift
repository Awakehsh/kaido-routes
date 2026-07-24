import SwiftUI

enum KaidoTheme {
  static let asphaltToken = KaidoColorToken(hex: 0x0E171C)
  static let instrumentToken = KaidoColorToken(hex: 0x162329)
  static let steelToken = KaidoColorToken(hex: 0x31444B)
  static let routeWhiteToken = KaidoColorToken(hex: 0xEEF2F2)
  static let signalAmberToken = KaidoColorToken(hex: 0xF0B641)
  static let evidenceCoralToken = KaidoColorToken(hex: 0xF07D6D)
  static let confirmedGreenToken = KaidoColorToken(hex: 0x6EC59B)
  static let positionCyanToken = KaidoColorToken(hex: 0x5FC9D5)
  static let mutedToken = KaidoColorToken(hex: 0x91A1A7)

  static let asphalt = asphaltToken.color
  static let instrument = instrumentToken.color
  static let steel = steelToken.color
  static let routeWhite = routeWhiteToken.color
  static let signalAmber = signalAmberToken.color
  static let evidenceCoral = evidenceCoralToken.color
  static let confirmedGreen = confirmedGreenToken.color
  static let positionCyan = positionCyanToken.color
  static let muted = mutedToken.color
}

extension Color {
  init(hex: UInt32, opacity: Double = 1) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: opacity
    )
  }
}
