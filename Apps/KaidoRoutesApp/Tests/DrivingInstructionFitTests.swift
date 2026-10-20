import KaidoDomain
import KaidoNavigation
import SwiftUI
import XCTest

@testable import KaidoRoutesApp

/// The driving instruction follows the driver's text size, and the longest
/// released cue in each language still leaves the map most of the screen.
@MainActor
final class DrivingInstructionFitTests: XCTestCase {
  /// A 375 pt-wide, 667 pt-tall phone, the smallest the App supports.
  private static let screenHeight = 667.0
  /// The instruction column beside the maneuver tile and the controls, and
  /// the card's full width, which the instruction takes at accessibility
  /// sizes: the screen less the bar's and the card's padding.
  private static let cardWidth: Double = 375 - 28 - 20
  private static let columnWidth: Double = cardWidth - 56 - 13 - 13 - 44
  /// The banner sits over the map: the instruction takes at most this much
  /// of the screen.
  private static let heightBudget = 0.4 * screenHeight

  func testLongestCueFitsAtTheLargestAccessibilitySize() throws {
    for (locale, cue) in try Self.longestCues() {
      let height = Self.height(
        of: DrivingInstructionText(text: cue),
        width: Self.cardWidth,
        size: .accessibility5
      )
      XCTAssertLessThanOrEqual(height, Self.heightBudget, "\(locale.rawValue): \(cue)")
    }
  }

  func testInstructionGrowsWithTheTextSizeUpToItsLargest() throws {
    for (locale, cue) in try Self.longestCues() {
      let view = DrivingInstructionText(text: cue)
      let large = Self.height(of: view, width: Self.cardWidth, size: .large)
      let largest = Self.height(of: view, width: Self.cardWidth, size: DrivingInstructionText.largestSize)
      let beyond = Self.height(of: view, width: Self.cardWidth, size: .accessibility5)
      XCTAssertGreaterThan(largest, large, locale.rawValue)
      XCTAssertEqual(beyond, largest, locale.rawValue)
    }
  }

  /// At the default text size the instruction lays out exactly as the fixed
  /// 20 pt it replaces.
  func testDefaultSizeLaysOutAsBefore() throws {
    for (locale, cue) in try Self.longestCues() {
      let before = Text(cue)
        .font(.system(size: 20, weight: .bold, design: .rounded))
        .fixedSize(horizontal: false, vertical: true)
      for width in [Self.columnWidth, Self.cardWidth] {
        XCTAssertEqual(
          Self.height(of: DrivingInstructionText(text: cue), width: width, size: .large),
          Self.height(of: before, width: width, size: .large),
          "\(locale.rawValue) at \(width)"
        )
      }
    }
  }

  private static func longestCues() throws -> [(KaidoReleaseLocale, String)] {
    let catalog = try BundledProductReleaseCatalogLoader.bundledForeground()
    return try KaidoReleaseLocale.allCases.map { locale in
      let cues = catalog.foregroundNavigationEntries.flatMap { entry in
        entry.release.navigation.bundle.releasedGuidance.compactMap {
          $0.frameTemplate.presentationSource.localizedContent[locale]?.displayText
        }
      }
      return (locale, try XCTUnwrap(cues.max { $0.count < $1.count }))
    }
  }

  private static func height(
    of view: some View,
    width: Double,
    size: DynamicTypeSize
  ) -> Double {
    UIHostingController(rootView: view.environment(\.dynamicTypeSize, size))
      .sizeThatFits(in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
      .height
  }
}
