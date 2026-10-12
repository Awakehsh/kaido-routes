import SwiftUI

struct KaidoColorToken: Equatable, Sendable {
  let hex: UInt32

  var color: Color {
    Color(hex: hex)
  }

  func contrastRatio(against background: KaidoColorToken) -> Double {
    let foregroundLuminance = relativeLuminance
    let backgroundLuminance = background.relativeLuminance
    return
      (max(foregroundLuminance, backgroundLuminance) + 0.05)
      / (min(foregroundLuminance, backgroundLuminance) + 0.05)
  }

  private var relativeLuminance: Double {
    let red = linearComponent(Double((hex >> 16) & 0xFF) / 255)
    let green = linearComponent(Double((hex >> 8) & 0xFF) / 255)
    let blue = linearComponent(Double(hex & 0xFF) / 255)
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue
  }

  private func linearComponent(_ component: Double) -> Double {
    if component <= 0.04045 {
      return component / 12.92
    }
    return pow((component + 0.055) / 1.055, 2.4)
  }
}

enum KaidoAccessibilityLayoutMode: String, Equatable, Sendable {
  case standard = "STANDARD"
  case accessibility = "ACCESSIBILITY"
}

enum KaidoAccessibilityLayoutPolicy {
  static func mode(for dynamicTypeSize: DynamicTypeSize) -> KaidoAccessibilityLayoutMode {
    dynamicTypeSize.isAccessibilitySize ? .accessibility : .standard
  }

  static func selectorColumnCount(for dynamicTypeSize: DynamicTypeSize) -> Int {
    mode(for: dynamicTypeSize) == .accessibility ? 1 : 2
  }
}

extension View {
  /// Machine state for UI tests. Debug builds expose `code` as the
  /// accessibility value so tests assert state whatever the interface
  /// language; a Release build exposes only `spoken`, so VoiceOver never
  /// reads a test code.
  func kaidoAccessibilityValue(code: String, spoken: String = "") -> some View {
    #if DEBUG
      accessibilityValue(code)
    #else
      accessibilityValue(spoken)
    #endif
  }
}
