import KaidoDomain
import KaidoPresentation
import XCTest

@testable import KaidoRoutesApp

@MainActor
final class GuidanceLanguagePreviewModelTests: XCTestCase {
  func testDefaultInterfaceAndVoiceLocalesAreIndependent() throws {
    let model = try GuidanceLanguagePreviewModel()

    XCTAssertEqual(model.selection.interfaceLocale, .simplifiedChinese)
    XCTAssertEqual(model.selection.guidanceVoiceLocale, .english)
    XCTAssertEqual(
      model.projection.iPhone.localizedDisplayText,
      "保持左侧，跟随 B 湾岸线・横滨方向"
    )
    XCTAssertEqual(
      model.projection.voice.spokenText,
      "Keep left for Route B toward Yokohama"
    )
    XCTAssertEqual(model.projection.iPhone.japaneseSignText, "B 湾岸線・横浜方面")
    XCTAssertEqual(model.projection.iPhone.routeShields, ["B"])
    XCTAssertFalse(model.projection.voice.shouldSpeak)
    XCTAssertNil(model.lastErrorCode)
  }

  func testEachLanguageSettingChangesOnlyItsOwnProjection() throws {
    let model = try GuidanceLanguagePreviewModel()

    model.selectInterfaceLocale(.japanese)

    XCTAssertEqual(model.selection.interfaceLocale, .japanese)
    XCTAssertEqual(model.selection.guidanceVoiceLocale, .english)
    XCTAssertEqual(
      model.projection.iPhone.localizedDisplayText,
      "左側を進み、B 湾岸線・横浜方面へ"
    )
    XCTAssertEqual(
      model.projection.voice.spokenText,
      "Keep left for Route B toward Yokohama"
    )

    model.selectGuidanceVoiceLocale(.simplifiedChinese)

    XCTAssertEqual(model.selection.interfaceLocale, .japanese)
    XCTAssertEqual(model.selection.guidanceVoiceLocale, .simplifiedChinese)
    XCTAssertEqual(
      model.projection.iPhone.localizedDisplayText,
      "左側を進み、B 湾岸線・横浜方面へ"
    )
    XCTAssertEqual(
      model.projection.voice.spokenText,
      "保持左侧，跟随 B 湾岸线，横滨方向"
    )
    XCTAssertEqual(model.projection.iPhone.japaneseSignText, "B 湾岸線・横浜方面")
    XCTAssertFalse(model.projection.voice.shouldSpeak)
  }

  func testJapaneseSignAndRouteShieldSurviveEveryInterfaceLocale() throws {
    let model = try GuidanceLanguagePreviewModel()

    for locale in KaidoReleaseLocale.allCases {
      model.selectInterfaceLocale(locale)

      XCTAssertEqual(model.selection.interfaceLocale, locale)
      XCTAssertEqual(model.projection.iPhone.japaneseSignText, "B 湾岸線・横浜方面")
      XCTAssertEqual(model.projection.iPhone.routeShields, ["B"])
      XCTAssertNil(model.lastErrorCode)
    }
  }

  func testIncompleteSignPreservationFailsInitialization() {
    let fixture = GuidanceLanguagePreviewFixture.synthetic
    var localizedContent = fixture.guidanceFrame.presentationSource.localizedContent
    localizedContent[.english] = LocalizedGuidanceContent(
      displayText: "Keep left for Route B toward Yokohama",
      spokenText: "Keep left for Route B toward Yokohama",
      spokenForms: ["B": "Route B"],
      preservedJapaneseSignText: "Route B toward Yokohama"
    )
    let invalidFrame = GuidanceFrame(
      promptID: fixture.guidanceFrame.promptID,
      anchorID: fixture.guidanceFrame.anchorID,
      anchorOccurrenceID: fixture.guidanceFrame.anchorOccurrenceID,
      movementOccurrenceID: fixture.guidanceFrame.movementOccurrenceID,
      decisionZoneID: fixture.guidanceFrame.decisionZoneID,
      stage: fixture.guidanceFrame.stage,
      distanceMeters: fixture.guidanceFrame.distanceMeters,
      decisionPointNameJapanese: fixture.guidanceFrame.decisionPointNameJapanese,
      localizedDecisionPointNames: fixture.guidanceFrame.localizedDecisionPointNames,
      maneuver: fixture.guidanceFrame.maneuver,
      lanePreparation: fixture.guidanceFrame.lanePreparation,
      presentationSource: GuidancePresentationSource(
        routeShields: fixture.guidanceFrame.presentationSource.routeShields,
        japaneseSignText: fixture.guidanceFrame.presentationSource.japaneseSignText,
        localizedContent: localizedContent
      )
    )
    let invalidFixture = GuidanceLanguagePreviewFixture(
      networkSnapshotID: fixture.networkSnapshotID,
      routePlanID: fixture.routePlanID,
      guidanceFrame: invalidFrame,
      passageEvidence: fixture.passageEvidence
    )

    XCTAssertThrowsError(
      try GuidanceLanguagePreviewModel(fixture: invalidFixture)
    ) { error in
      XCTAssertEqual(
        error as? GuidanceLanguagePreviewModelError,
        .projection(.japaneseSignTextMismatch(.english))
      )
    }
  }
}
