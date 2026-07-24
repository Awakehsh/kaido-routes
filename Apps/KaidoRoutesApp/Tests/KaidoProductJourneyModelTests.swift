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
    let entry = try makeReleasedProductTestEntry()
    let catalog = BundledProductReleaseCatalog(entries: [entry])
    let composition = KaidoRoutesAppModel(
      productReleaseCatalog: catalog,
      releasedPreDriveEvidenceProvider: { entry, session in
        makeReleasedPreDriveEvidence(
          for: entry,
          vehicleClass: session.vehicleClass,
          paymentMethod: session.paymentMethod
        )
      }
    )
    let model = KaidoProductJourneyModel(
      composition: composition,
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
    authorReleasedRoute(
      try XCTUnwrap(composition.releasedRouteAuthoring),
      entry: entry
    )
    guard
      case .ready(let atlasProjection, let isRealRoadAuthority) =
        model.routeAtlasOverlayPresentation
    else {
      return XCTFail("Expected the compiled released route on its atlas")
    }
    XCTAssertTrue(isRealRoadAuthority)
    XCTAssertEqual(
      atlasProjection.routePlanID,
      entry.release.navigation.bundle.routePlan.id
    )
    XCTAssertEqual(
      atlasProjection.occurrences.map(\.state),
      Array(
        repeating: .planned,
        count: entry.release.navigation.bundle.routePlan.occurrences.count
      )
    )
    XCTAssertTrue(
      atlasProjection.occurrences.contains {
        $0.isRepeatedTraversal
      }
    )
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
    let entry = try makeReleasedProductTestEntry()
    let catalog = BundledProductReleaseCatalog(entries: [entry])
    let composition = KaidoRoutesAppModel(
      productReleaseCatalog: catalog,
      releasedPreDriveEvidenceProvider: { entry, session in
        makeReleasedPreDriveEvidence(
          for: entry,
          vehicleClass: session.vehicleClass,
          paymentMethod: session.paymentMethod
        )
      }
    )
    let model = KaidoProductJourneyModel(
      composition: composition,
      navigationRuntimeFactory: { _ in
        throw JourneyRuntimeTestError.constructionFailed
      }
    )
    authorReleasedRoute(
      try XCTUnwrap(composition.releasedRouteAuthoring),
      entry: entry
    )
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
    let entry = try makeReleasedProductTestEntry()
    let catalog = BundledProductReleaseCatalog(entries: [entry])
    let composition = KaidoRoutesAppModel(
      productReleaseCatalog: catalog,
      releasedPreDriveEvidenceProvider: { entry, session in
        makeReleasedPreDriveEvidence(
          for: entry,
          vehicleClass: session.vehicleClass,
          paymentMethod: session.paymentMethod
        )
      }
    )
    let model = KaidoProductJourneyModel(
      composition: composition,
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
    let releasedAuthoring = try XCTUnwrap(
      composition.releasedRouteAuthoring
    )
    authorReleasedRoute(releasedAuthoring, entry: entry)
    model.go(to: .review)
    model.requestNavigationStart()
    let runtime = try XCTUnwrap(model.navigationRuntime)
    await runtime.activate()

    releasedAuthoring.clearSelection()

    for _ in 0..<20 where model.navigationRuntime != nil {
      await Task.yield()
    }
    XCTAssertEqual(model.stage, .authoring)
    XCTAssertEqual(model.lastBlocker, .routeReviewNotReady)
    XCTAssertNil(model.navigationRuntime)
    XCTAssertEqual(runtime.activation, .ended)
  }

  func testInjectedMismatchedReleaseCannotAuthorizeSyntheticRoute()
    throws
  {
    let composition = KaidoRoutesAppModel()
    let entry = try makeReleasedProductTestEntry()
    let model = KaidoProductJourneyModel(
      composition: composition,
      productReleaseSelectionProvider: { _ in .selected(entry) }
    )
    composition.routeEditor.select(
      choiceID: "preview.synthetic.choice.early-exit"
    )
    composition.routeEditor.compile()
    model.go(to: .review)

    XCTAssertFalse(model.canStartNavigation)
    XCTAssertEqual(
      model.navigationBlocker,
      .routeReleaseAuthorityUnavailable
    )
  }

  func testReleasedRouteWithoutPreDriveEvidenceCannotReachReview()
    throws
  {
    let entry = try makeReleasedProductTestEntry()
    let composition = KaidoRoutesAppModel(
      productReleaseCatalog: BundledProductReleaseCatalog(entries: [entry])
    )
    let model = KaidoProductJourneyModel(composition: composition)
    let releasedAuthoring = try XCTUnwrap(
      composition.releasedRouteAuthoring
    )

    authorReleasedRoute(releasedAuthoring, entry: entry)
    model.go(to: .review)

    XCTAssertEqual(model.stage, .atlas)
    XCTAssertFalse(model.routeReviewReady)
    XCTAssertFalse(model.canStartNavigation)
    XCTAssertEqual(
      model.lastBlocker,
      .releasedPreDriveEvidenceUnavailable
    )
    XCTAssertEqual(
      model.navigationBlocker,
      .releasedPreDriveEvidenceUnavailable
    )
  }
}

private enum JourneyRuntimeTestError: Error {
  case constructionFailed
}
