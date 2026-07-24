import KaidoDomain
import KaidoPresentation
import XCTest

@testable import KaidoRoutesApp

@MainActor
final class KaidoProductJourneyModelTests: XCTestCase {
  func testJourneyStartsAtAtlasAndCannotSkipUncompiledRoute() {
    let model = KaidoProductJourneyModel()

    XCTAssertEqual(model.stage, .atlas)
    XCTAssertTrue(model.canAdvance)
    XCTAssertFalse(model.routeReviewReady)

    model.go(to: .review)

    XCTAssertEqual(model.stage, .atlas)
    XCTAssertEqual(model.lastBlocker, .routeReviewNotReady)
  }

  func testExactCompiledRouteUnlocksReviewInOrder() throws {
    let model = KaidoProductJourneyModel()

    model.advance()
    XCTAssertEqual(model.stage, .authoring)
    XCTAssertFalse(model.canAdvance)

    model.composition.routeEditor.select(
      choiceID: "preview.synthetic.choice.early-exit"
    )
    model.composition.routeEditor.compile()

    XCTAssertTrue(model.routeReviewReady)
    XCTAssertTrue(model.canAdvance)

    model.advance()

    XCTAssertEqual(model.stage, .review)
    XCTAssertNil(model.lastBlocker)
    XCTAssertEqual(
      try XCTUnwrap(model.composition.preDriveReview.snapshot)
        .routePlanID,
      "preview.synthetic.route-plan"
    )
  }

  func testSyntheticReviewCannotStartNavigation() {
    let model = KaidoProductJourneyModel.reviewPreview()

    XCTAssertEqual(model.stage, .review)
    XCTAssertFalse(model.canStartNavigation)
    XCTAssertEqual(
      model.navigationBlocker,
      .routeReleaseAuthorityUnavailable
    )

    model.requestNavigationStart()

    XCTAssertEqual(model.stage, .review)
    XCTAssertEqual(
      model.lastBlocker,
      .routeReleaseAuthorityUnavailable
    )
  }

  func testInvalidatedCompiledRouteReturnsReviewToAuthoring() {
    let model = KaidoProductJourneyModel.reviewPreview()

    model.composition.routeEditor.undo()

    XCTAssertEqual(model.stage, .authoring)
    XCTAssertFalse(model.routeReviewReady)
    XCTAssertEqual(model.lastBlocker, .routeReviewNotReady)
  }

  func testCompletedStagesRemainNavigableWithoutUnlockingFutureStage() {
    let model = KaidoProductJourneyModel.reviewPreview()

    model.go(to: .atlas)
    XCTAssertEqual(model.stage, .atlas)

    model.go(to: .authoring)
    XCTAssertEqual(model.stage, .authoring)

    model.go(to: .navigation)
    XCTAssertEqual(model.stage, .authoring)
    XCTAssertEqual(
      model.lastBlocker,
      .routeReleaseAuthorityUnavailable
    )
  }

  func testExactSelectedReleaseCreatesUserStartedRuntimeAndEndsCleanly()
    async throws
  {
    let composition = KaidoRoutesAppModel()
    let entry = try makeReleasedProductTestEntry()
    let model = KaidoProductJourneyModel(
      composition: composition,
      productReleaseSelectionProvider: { _ in
        .selected(entry)
      },
      navigationRuntimeFactory: {
        try ProductNavigationRuntimeModel(
          releasedEntry: $0,
          languageSelectionProvider: {
            NavigationLanguageSelection(
              interfaceLocale: .simplifiedChinese,
              guidanceVoiceLocale: .japanese
            )
          }
        )
      }
    )
    composition.routeEditor.select(
      choiceID: "preview.synthetic.choice.early-exit"
    )
    composition.routeEditor.compile()
    model.go(to: .review)

    XCTAssertTrue(model.canStartNavigation)
    XCTAssertNil(model.navigationBlocker)

    model.requestNavigationStart()

    XCTAssertEqual(model.stage, .navigation)
    XCTAssertNil(model.lastBlocker)
    let runtime = try XCTUnwrap(model.navigationRuntime)
    XCTAssertTrue(runtime.isRealRoadAuthority)
    await runtime.activate()
    XCTAssertEqual(runtime.activation, .ready)

    await model.endNavigation()

    XCTAssertEqual(model.stage, .review)
    XCTAssertNil(model.navigationRuntime)
    XCTAssertNil(model.lastBlocker)
  }

  func testRuntimeConstructionFailureKeepsReviewFailClosed() throws {
    let composition = KaidoRoutesAppModel()
    let entry = try makeReleasedProductTestEntry()
    let model = KaidoProductJourneyModel(
      composition: composition,
      productReleaseSelectionProvider: { _ in
        .selected(entry)
      },
      navigationRuntimeFactory: { _ in
        throw JourneyRuntimeTestError.constructionFailed
      }
    )
    composition.routeEditor.select(
      choiceID: "preview.synthetic.choice.early-exit"
    )
    composition.routeEditor.compile()
    model.go(to: .review)

    model.requestNavigationStart()

    XCTAssertEqual(model.stage, .review)
    XCTAssertNil(model.navigationRuntime)
    XCTAssertEqual(
      model.lastBlocker,
      .navigationRuntimeUnavailable
    )
  }

  func testRouteInvalidationTerminatesAnActiveReleasedRuntime()
    async throws
  {
    let composition = KaidoRoutesAppModel()
    let entry = try makeReleasedProductTestEntry()
    let model = KaidoProductJourneyModel(
      composition: composition,
      productReleaseSelectionProvider: { _ in
        .selected(entry)
      },
      navigationRuntimeFactory: {
        try ProductNavigationRuntimeModel(
          releasedEntry: $0,
          languageSelectionProvider: {
            NavigationLanguageSelection(
              interfaceLocale: .simplifiedChinese,
              guidanceVoiceLocale: .japanese
            )
          }
        )
      }
    )
    composition.routeEditor.select(
      choiceID: "preview.synthetic.choice.early-exit"
    )
    composition.routeEditor.compile()
    model.go(to: .review)
    model.requestNavigationStart()
    let runtime = try XCTUnwrap(model.navigationRuntime)
    await runtime.activate()

    composition.routeEditor.undo()

    for _ in 0..<20 where model.navigationRuntime != nil {
      await Task.yield()
    }
    XCTAssertEqual(model.stage, .authoring)
    XCTAssertEqual(model.lastBlocker, .routeReviewNotReady)
    XCTAssertNil(model.navigationRuntime)
    XCTAssertEqual(runtime.activation, .ended)
  }
}

private enum JourneyRuntimeTestError: Error {
  case constructionFailed
}
