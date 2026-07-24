import SwiftUI

enum KaidoTheme {
  static let asphalt = Color(hex: 0x0E171C)
  static let instrument = Color(hex: 0x162329)
  static let steel = Color(hex: 0x31444B)
  static let routeWhite = Color(hex: 0xEEF2F2)
  static let signalAmber = Color(hex: 0xF0B641)
  static let evidenceCoral = Color(hex: 0xF07D6D)
  static let positionCyan = Color(hex: 0x5FC9D5)
  static let muted = Color(hex: 0x91A1A7)
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
