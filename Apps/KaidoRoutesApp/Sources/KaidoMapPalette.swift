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

/// The map's layer names, resolved from the same `KaidoPalette` the rest of
/// the product reads. Keeping the names lets the renderers go on saying what
/// a colour is *for*; deriving the values means the map and the chrome around
/// it can no longer drift apart, which is what let a `day` appearance turn the
/// map white while the dock stayed black.
enum KaidoMapPalette {
  static let background = KaidoInk.surface
  static let water = KaidoInk.mapWater
  static let casing = KaidoInk.mapCasing
  static let restCore = KaidoInk.mapRestCore
  static let leader = KaidoInk.mapLeader
  static let plate = KaidoInk.mapPlate
  static let label = KaidoInk.textSecondary
  static let junctionLabel = KaidoInk.textPrimary
  /// The active plan's own colour; a component leg that is not the base route
  /// takes `bayshore`, so the two legs stay distinguishable by temperature.
  static let baseRoute = KaidoInk.accentWarm
  static let bayshore = KaidoInk.accentCool
  /// The halo; `positionCore` is the mark inside it. Together they make the
  /// position the highest-contrast point on the map without spending a hue.
  static let position = KaidoInk.positionHalo
  static let positionCore = KaidoInk.positionCore
  static let entranceFull = KaidoInk.accentCool
  static let entranceHalf = KaidoInk.entranceHalf
  static let exitFull = KaidoInk.accentClay
  static let exitHalf = KaidoInk.exitHalf
  static let pa = KaidoInk.accentCool
  static let place = KaidoInk.mapPlace
}
