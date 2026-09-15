import KaidoDomain
import KaidoPresentation
import SwiftUI
import XCTest

@testable import KaidoRoutesApp

@MainActor
final class AccessibilityPresentationTests: XCTestCase {
  func testCriticalTextColorsMeetNormalTextContrastFloor() {
    let backgrounds = [
      KaidoTheme.asphaltToken,
      KaidoTheme.instrumentToken,
    ]
    let textColors = [
      KaidoTheme.routeWhiteToken,
      KaidoTheme.signalAmberToken,
      KaidoTheme.evidenceCoralToken,
      KaidoTheme.confirmedGreenToken,
      KaidoTheme.positionCyanToken,
      KaidoTheme.mutedToken,
    ]

    for background in backgrounds {
      for foreground in textColors {
        XCTAssertGreaterThanOrEqual(
          foreground.contrastRatio(against: background),
          4.5
        )
      }
    }
    XCTAssertGreaterThanOrEqual(
      KaidoTheme.routeWhiteToken.contrastRatio(
        against: KaidoTheme.steelToken
      ),
      4.5
    )
  }

  /// Every text and accent role has to clear the normal-text bar against
  /// every ground it can land on, in *both* palettes. This is the line that
  /// makes the `day` map appearance safe to offer: the whole-Shuto surfaces
  /// take `.preferredColorScheme` from that preference, so a ground can
  /// lighten under text that was only ever checked against a dark one.
  func testEveryPaletteRoleClearsNormalTextContrast() {
    for (appearance, palette) in [
      ("night", KaidoPalette.night), ("day", KaidoPalette.day),
    ] {
      let grounds = [
        ("surface", palette.surface),
        ("surfacePanel", palette.surfacePanel),
        ("surfaceRaised", palette.surfaceRaised),
        ("surfaceRaisedTop", palette.surfaceRaisedTop),
        ("mapPlate", palette.mapPlate),
      ]
      let inks = [
        ("textPrimary", palette.textPrimary),
        ("textSecondary", palette.textSecondary),
        ("textQuiet", palette.textQuiet),
        ("accentWarm", palette.accentWarm),
        ("accentCool", palette.accentCool),
        ("accentClay", palette.accentClay),
      ]
      for (groundName, ground) in grounds {
        for (inkName, ink) in inks {
          XCTAssertGreaterThanOrEqual(
            ink.contrastRatio(against: ground),
            4.5,
            "\(appearance): \(inkName) on \(groundName)"
          )
        }
      }
      // A chip filled with the accent carries the ground colour as its label,
      // which only works because the two move in opposite directions between
      // the palettes.
      XCTAssertGreaterThanOrEqual(
        palette.surface.contrastRatio(against: palette.accentWarm),
        4.5,
        "\(appearance): accent-filled chip label"
      )
    }
  }

  func testAccessibilityDynamicTypeUsesSingleColumnControls() {
    XCTAssertEqual(
      KaidoAccessibilityLayoutPolicy.mode(for: .large),
      .standard
    )
    XCTAssertEqual(
      KaidoAccessibilityLayoutPolicy.selectorColumnCount(for: .large),
      2
    )
    XCTAssertEqual(
      KaidoAccessibilityLayoutPolicy.mode(for: .accessibility1),
      .accessibility
    )
    XCTAssertEqual(
      KaidoAccessibilityLayoutPolicy.selectorColumnCount(
        for: .accessibility5
      ),
      1
    )
  }

  func testJunctionStateProducesVoiceOverAndNonColorSemantics() throws {
    let model = try SyntheticDrivingPreviewModel(
      initialCase: .reviewedJunctionHandoff
    )
    let accessibility = NavigationAccessibilityProjector.project(
      model.state.projection.iPhone,
      locale: .simplifiedChinese
    )

    XCTAssertEqual(accessibility.routeShieldLabels, ["路线盾牌 B"])
    XCTAssertTrue(
      accessibility.guidanceLabel.contains("B 湾岸線・横浜方面")
    )
    XCTAssertEqual(accessibility.passageLabel, "实时通行，尚未确认")
    XCTAssertEqual(
      accessibility.routeEditingLabel,
      "路线编辑，决策区不可编辑"
    )
    XCTAssertTrue(accessibility.selectedPathHasNonColorCue)
    XCTAssertTrue(accessibility.preferredLanesHaveNonColorCue)
    XCTAssertTrue(
      accessibility.junctionDiagramLabel?.contains("勾选标记") == true
    )
    XCTAssertTrue(
      accessibility.junctionLaneLabel?.contains("首选车道 1") == true
    )
  }
}
