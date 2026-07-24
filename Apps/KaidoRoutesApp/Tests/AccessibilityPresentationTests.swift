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
