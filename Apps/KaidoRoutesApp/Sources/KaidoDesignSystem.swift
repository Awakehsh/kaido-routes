import SwiftUI

/// One complete set of semantic values for the whole-Shuto product surfaces.
///
/// Two instances exist, `night` and `day`. Nothing reads a palette directly:
/// `KaidoInk` resolves the pair against the trait collection, so a surface
/// that reads `KaidoInk.surfaceRaised` follows the system appearance without
/// the view knowing which one it got. Moving the product to a different
/// colour direction is an edit to this file, not to the call sites.
///
/// Values are `KaidoColorToken` rather than `Color` so the contrast tests can
/// measure them.
struct KaidoPalette: Equatable, Sendable {
  // Grounds, darkest to nearest the eye.
  let surface: KaidoColorToken
  let surfacePanel: KaidoColorToken
  let surfaceRaised: KaidoColorToken
  /// Top stop of the raised gradient; a card reads as one lit face rather
  /// than a flat fill.
  let surfaceRaisedTop: KaidoColorToken
  let divider: KaidoColorToken

  // Text. Every one of the three clears 4.5:1 against `surface`,
  // `surfacePanel` and `surfaceRaised`; `AccessibilityPresentationTests`
  // holds that line.
  let textPrimary: KaidoColorToken
  let textSecondary: KaidoColorToken
  let textQuiet: KaidoColorToken

  // Accents. Three hues, no more: the route experience owns the warm one,
  // the measured/enterable things own the cool one, and leaving or failing
  // owns the clay one. The warm accent carries the route everywhere Kaido
  // draws the ground itself — cards, thumbnails, the track map; only the
  // provider basemap takes `mapRouteDriving` instead, for the reason given
  // there.
  //
  // Each accent is mid-lightness in *both* palettes, which is what lets it
  // read against a dark ground and a light one. The cost is that a control
  // filled with an accent must label itself with `surface`, never
  // `textPrimary`: a light label on `accentWarm` measures 2.28:1. The
  // filled-chip assertion in `AccessibilityPresentationTests` holds that
  // pairing, and `KRU09AccessibilityUITests` catches it on the rendered
  // screen if a call site gets it wrong anyway.
  let accentWarm: KaidoColorToken
  /// Casing beneath `accentWarm`, so a route line reads as a drawn road
  /// rather than a stroke.
  let accentWarmDeep: KaidoColorToken
  let accentCool: KaidoColorToken
  let accentClay: KaidoColorToken

  // Map layers.
  /// The planned route drawn on the provider basemap. It cannot be
  /// `accentWarm`: that basemap paints its own congestion layer in amber and
  /// red, so a warm route line reads as a jam rather than as the route. Blue
  /// is the one hue the congestion band never uses, which is why every
  /// mainstream navigator draws its route in it.
  let mapRouteDriving: KaidoColorToken
  let mapWater: KaidoColorToken
  let mapCasing: KaidoColorToken
  /// Off-route network. Deliberately near the ground — the contract keeps
  /// it as quiet context, not as information, so it is exempt from the 3:1
  /// bar that identifiable marks must clear.
  let mapRestCore: KaidoColorToken
  let mapLeader: KaidoColorToken
  let mapPlate: KaidoColorToken
  let mapPlace: KaidoColorToken
  /// The position marker is the highest-contrast point on the map by
  /// construction: a `textPrimary`-weight core inside an `accentCool` halo.
  /// It never competes with a route colour because it is not a hue.
  let positionCore: KaidoColorToken
  let positionHalo: KaidoColorToken
  /// Direction-restricted facilities render at reduced strength; the full
  /// pair carries the unrestricted case.
  let entranceHalf: KaidoColorToken
  let exitHalf: KaidoColorToken
}

extension KaidoPalette {
  /// Midnight, desaturated. The operator route shields keep their own hues,
  /// so the ground stays quiet enough for them to read as information.
  static let night = KaidoPalette(
    surface: KaidoColorToken(hex: 0x0A0C10),
    surfacePanel: KaidoColorToken(hex: 0x10131A),
    surfaceRaised: KaidoColorToken(hex: 0x1E232E),
    surfaceRaisedTop: KaidoColorToken(hex: 0x212734),
    divider: KaidoColorToken(hex: 0x282E3B),
    textPrimary: KaidoColorToken(hex: 0xEAEEF3),
    textSecondary: KaidoColorToken(hex: 0x9BA3B2),
    textQuiet: KaidoColorToken(hex: 0x8892A4),
    accentWarm: KaidoColorToken(hex: 0xC9955A),
    accentWarmDeep: KaidoColorToken(hex: 0x7A5A32),
    accentCool: KaidoColorToken(hex: 0x7FA8B4),
    accentClay: KaidoColorToken(hex: 0xCE7C67),
    mapRouteDriving: KaidoColorToken(hex: 0x4E8FE8),
    mapWater: KaidoColorToken(hex: 0x0B1119),
    mapCasing: KaidoColorToken(hex: 0x161A23),
    mapRestCore: KaidoColorToken(hex: 0x353C4C),
    mapLeader: KaidoColorToken(hex: 0x353C4C),
    mapPlate: KaidoColorToken(hex: 0x070910),
    mapPlace: KaidoColorToken(hex: 0xB8A88C),
    positionCore: KaidoColorToken(hex: 0xEAEEF3),
    positionHalo: KaidoColorToken(hex: 0x7FA8B4),
    entranceHalf: KaidoColorToken(hex: 0x5E8791),
    exitHalf: KaidoColorToken(hex: 0xA5685A)
  )

  static let day = KaidoPalette(
    surface: KaidoColorToken(hex: 0xF2F4F7),
    surfacePanel: KaidoColorToken(hex: 0xFFFFFF),
    surfaceRaised: KaidoColorToken(hex: 0xFFFFFF),
    surfaceRaisedTop: KaidoColorToken(hex: 0xFFFFFF),
    divider: KaidoColorToken(hex: 0xD9DEE6),
    textPrimary: KaidoColorToken(hex: 0x141922),
    textSecondary: KaidoColorToken(hex: 0x47515F),
    textQuiet: KaidoColorToken(hex: 0x5F6978),
    accentWarm: KaidoColorToken(hex: 0x8A5C28),
    accentWarmDeep: KaidoColorToken(hex: 0x6B4720),
    accentCool: KaidoColorToken(hex: 0x2F6373),
    accentClay: KaidoColorToken(hex: 0xA3402F),
    mapRouteDriving: KaidoColorToken(hex: 0x1A5FD0),
    mapWater: KaidoColorToken(hex: 0xDCE6EF),
    mapCasing: KaidoColorToken(hex: 0xCDD5DE),
    mapRestCore: KaidoColorToken(hex: 0x8A97A5),
    mapLeader: KaidoColorToken(hex: 0x99A4B0),
    mapPlate: KaidoColorToken(hex: 0xFFFFFF),
    mapPlace: KaidoColorToken(hex: 0x7A6A4E),
    positionCore: KaidoColorToken(hex: 0x141922),
    positionHalo: KaidoColorToken(hex: 0x2F6373),
    entranceHalf: KaidoColorToken(hex: 0x4D7C89),
    exitHalf: KaidoColorToken(hex: 0xB86A5B)
  )
}

/// The product's colour entry point. Every value resolves `night` or `day`
/// from the trait collection at draw time, so appearance changes repaint
/// without a single view reading `colorScheme`.
enum KaidoInk {
  static let surface = resolve(\.surface)
  static let surfacePanel = resolve(\.surfacePanel)
  static let surfaceRaised = resolve(\.surfaceRaised)
  static let surfaceRaisedTop = resolve(\.surfaceRaisedTop)
  static let divider = resolve(\.divider)

  static let textPrimary = resolve(\.textPrimary)
  static let textSecondary = resolve(\.textSecondary)
  static let textQuiet = resolve(\.textQuiet)

  static let accentWarm = resolve(\.accentWarm)
  static let accentWarmDeep = resolve(\.accentWarmDeep)
  static let accentCool = resolve(\.accentCool)
  static let accentClay = resolve(\.accentClay)

  static let mapRouteDriving = resolve(\.mapRouteDriving)
  static let mapWater = resolve(\.mapWater)
  static let mapCasing = resolve(\.mapCasing)
  static let mapRestCore = resolve(\.mapRestCore)
  static let mapLeader = resolve(\.mapLeader)
  static let mapPlate = resolve(\.mapPlate)
  static let mapPlace = resolve(\.mapPlace)
  static let positionCore = resolve(\.positionCore)
  static let positionHalo = resolve(\.positionHalo)
  static let entranceHalf = resolve(\.entranceHalf)
  static let exitHalf = resolve(\.exitHalf)

  /// Route shields carry the operator's own ground colour, which does not
  /// change with appearance, so the mark on top of them cannot either.
  /// `RouteExperiencePresentationTests` measures this token against every
  /// shield ground.
  static let onShieldToken = KaidoColorToken(hex: 0xEEF2F2)
  static let onShield = onShieldToken.color

  /// The raised card face, as one gradient rather than a flat fill.
  static let raisedFace = LinearGradient(
    colors: [surfaceRaisedTop, surfaceRaised],
    startPoint: .top,
    endPoint: .bottom
  )

  static func palette(for style: UIUserInterfaceStyle) -> KaidoPalette {
    style == .dark ? .night : .day
  }

  private static func resolve(
    _ token: KeyPath<KaidoPalette, KaidoColorToken>
  ) -> Color {
    Color(UIColor { traits in
      let hex = palette(for: traits.userInterfaceStyle)[keyPath: token].hex
      return UIColor(
        red: Double((hex >> 16) & 0xFF) / 255,
        green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255,
        alpha: 1
      )
    })
  }
}

/// Seven roles, each bound to a system text style so Dynamic Type still
/// scales them. A card that needs more than three of these is carrying more
/// information than it should.
enum KaidoType {
  /// Drive time on a route card; the primary instruction while driving.
  static let display = Font.system(.title, design: .rounded).weight(.bold)
  static let title = Font.system(.title3, design: .rounded).weight(.bold)
  static let headline = Font.subheadline.weight(.semibold)
  static let body = Font.footnote
  static let label = Font.caption.weight(.semibold)
  static let caption = Font.caption2.weight(.medium)
  /// Route shields are drawn marks, not prose: they hold their size so the
  /// shield geometry stays legible at the size signs are read.
  static let mark = Font.system(size: 10, weight: .black, design: .rounded)
}

enum KaidoSpace {
  /// Shields in a row; an icon and its label.
  static let xs: CGFloat = 4
  /// Rows inside one card.
  static let sm: CGFloat = 8
  /// Cards in a row; groups inside a panel.
  static let md: CGFloat = 12
  /// Card padding; the screen's side gutter.
  static let lg: CGFloat = 16
  /// Between sections.
  static let xl: CGFloat = 24
}

enum KaidoRadius {
  static let mark: CGFloat = 4
  static let control: CGFloat = 10
  static let card: CGFloat = 14
  static let sheet: CGFloat = 20
}

extension View {
  /// A card face: lit gradient, a hairline of light along the top edge, and
  /// an ambient shadow. Replaces the 1px divider-coloured stroke, which on a
  /// dark ground read as a flat sticker.
  func kaidoRaised(cornerRadius: CGFloat = KaidoRadius.card) -> some View {
    background(KaidoInk.raisedFace)
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .strokeBorder(Color.white.opacity(0.055), lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.45), radius: 10, x: 0, y: 4)
  }

  /// A dock or banner floating over the map.
  func kaidoFloating(cornerRadius: CGFloat = KaidoRadius.sheet) -> some View {
    background(KaidoInk.surfacePanel)
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.55), radius: 22, x: 0, y: -6)
  }
}
