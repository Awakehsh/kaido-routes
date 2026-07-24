import KaidoDomain
import XCTest

@testable import KaidoRoutesApp

final class ReleasedRouteEditorAdapterTests: XCTestCase {
  func testBundledReleaseResolvesLocalizedEditorAndReplaysExactOccurrences()
    throws
  {
    let entry = try XCTUnwrap(
      BundledProductReleaseCatalogLoader.bundledPreview()
        .demoEntries.first
    )
    var adapter = try ReleasedRouteEditorAdapter(
      productRelease: entry.release,
      locale: .simplifiedChinese
    )

    XCTAssertEqual(
      adapter.productReleaseID,
      "preview.synthetic.product-release.v1"
    )
    XCTAssertEqual(
      adapter.navigationReleaseID,
      "test.navigation-release.release-bundle.v1"
    )
    XCTAssertEqual(adapter.entranceTitle, "测试入口")
    XCTAssertEqual(
      adapter.steps.map(\.choiceTitle),
      ["继续循环", "继续循环", "驶向出口"]
    )
    XCTAssertEqual(
      adapter.snapshot.occurrences.map(\.id),
      ["test.occurrence.entry"]
    )

    for step in adapter.steps {
      try adapter.selectReleasedChoice(step.choiceID)
    }

    XCTAssertNil(adapter.nextStep)
    XCTAssertEqual(
      try adapter.compileReleasedRoute(),
      entry.release.navigation.bundle.routePlan
    )
    XCTAssertEqual(
      adapter.snapshot.occurrences.map(\.id),
      entry.release.navigation.bundle.routePlan.occurrences.map(\.id)
    )
  }

  func testAdapterRejectsChoiceOutsideExactReleasedRecipeWithoutMutation()
    throws
  {
    let entry = try XCTUnwrap(
      BundledProductReleaseCatalogLoader.bundledPreview()
        .demoEntries.first
    )
    var adapter = try ReleasedRouteEditorAdapter(
      productRelease: entry.release,
      locale: .english
    )
    let original = adapter.snapshot

    XCTAssertThrowsError(
      try adapter.selectReleasedChoice("test.choice.exit")
    ) {
      XCTAssertEqual(
        $0 as? ReleasedRouteEditorAdapterError,
        .choiceDoesNotMatchRelease(
          expected: "test.choice.loop",
          actual: "test.choice.exit"
        )
      )
    }
    XCTAssertEqual(adapter.snapshot, original)
    XCTAssertThrowsError(try adapter.compileReleasedRoute()) {
      XCTAssertEqual(
        $0 as? ReleasedRouteEditorAdapterError,
        .incompleteReleasedRoute
      )
    }
  }
}
