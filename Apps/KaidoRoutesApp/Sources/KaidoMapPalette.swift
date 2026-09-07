import SwiftUI
import UIKit

enum KaidoMapAppearance: String, CaseIterable {
  case automatic, day, night
  static let preferenceKey = "app.kaidoroutes.map.appearance"

  var colorScheme: ColorScheme? {
    switch self {
    case .automatic: nil
    case .day: .light
    case .night: .dark
    }
  }
}

enum KaidoMapPalette {
  static let background = color(day: 0xF1F5F7, night: 0x080B14)
  static let water = color(day: 0xD7E7F2, night: 0x0A1122)
  static let casing = color(day: 0xCCD7DE, night: 0x131929)
  static let restCore = color(day: 0x7A939F, night: 0x2C3A5C)
  static let leader = color(day: 0x889DA8, night: 0x31405E)
  static let plate = color(day: 0xFFFFFF, night: 0x050810)
  static let label = color(day: 0x425763, night: 0x9EADCC)
  static let junctionLabel = color(day: 0x142A37, night: 0xC9D6F2)
  static let baseRoute = color(day: 0x9B5E00, night: 0xFFB554)
  static let bayshore = color(day: 0x416FB0, night: 0x8FA8E8)
  static let position = color(day: 0x00687A, night: 0x5FC9D5)
  static let entranceFull = color(day: 0x176C43, night: 0x38B870)
  static let entranceHalf = color(day: 0x24794F, night: 0x80C79E)
  static let exitFull = color(day: 0xA4453E, night: 0xD16657)
  static let exitHalf = color(day: 0xAE5E51, night: 0xE0A197)
  static let pa = color(day: 0x166B42, night: 0x6BD194)
  static let place = color(day: 0x8C651D, night: 0xEDD18C)

  private static func color(day: UInt32, night: UInt32) -> Color {
    Color(UIColor { traits in
      let hex = traits.userInterfaceStyle == .dark ? night : day
      return UIColor(
        red: Double((hex >> 16) & 0xFF) / 255,
        green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255,
        alpha: 1
      )
    })
  }
}
