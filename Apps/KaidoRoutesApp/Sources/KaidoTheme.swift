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
  static let paperToken = KaidoColorToken(hex: 0xF4F6F1)
  static let paperRaisedToken = KaidoColorToken(hex: 0xFFFFFF)
  static let inkToken = KaidoColorToken(hex: 0x142327)
  static let routeGreenToken = KaidoColorToken(hex: 0x2F7258)
  static let routeGreenDeepToken = KaidoColorToken(hex: 0x1E4D3D)
  static let roadGrayToken = KaidoColorToken(hex: 0xAAB5B1)
  static let quietTextToken = KaidoColorToken(hex: 0x5E6B68)
  static let paperDividerToken = KaidoColorToken(hex: 0xD8DEDA)
  static let surfaceWaterToken = KaidoColorToken(hex: 0xDDE9EC)
  // Unified midnight surfaces for the whole-Shuto product: blue-black
  // asphalt matched to the network diagram's night palette.
  static let nightToken = KaidoColorToken(hex: 0x080B14)
  static let nightPanelToken = KaidoColorToken(hex: 0x0F1522)
  static let nightRaisedToken = KaidoColorToken(hex: 0x151D30)
  static let nightDividerToken = KaidoColorToken(hex: 0x243252)
  static let nightQuietToken = KaidoColorToken(hex: 0x8B99B8)

  static let asphalt = asphaltToken.color
  static let instrument = instrumentToken.color
  static let steel = steelToken.color
  static let routeWhite = routeWhiteToken.color
  static let signalAmber = signalAmberToken.color
  static let evidenceCoral = evidenceCoralToken.color
  static let confirmedGreen = confirmedGreenToken.color
  static let positionCyan = positionCyanToken.color
  static let muted = mutedToken.color
  static let paper = paperToken.color
  static let paperRaised = paperRaisedToken.color
  static let ink = inkToken.color
  static let routeGreen = routeGreenToken.color
  static let routeGreenDeep = routeGreenDeepToken.color
  static let roadGray = roadGrayToken.color
  static let quietText = quietTextToken.color
  static let paperDivider = paperDividerToken.color
  static let surfaceWater = surfaceWaterToken.color
  static let night = nightToken.color
  static let nightPanel = nightPanelToken.color
  static let nightRaised = nightRaisedToken.color
  static let nightDivider = nightDividerToken.color
  static let nightQuiet = nightQuietToken.color
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
