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
}
