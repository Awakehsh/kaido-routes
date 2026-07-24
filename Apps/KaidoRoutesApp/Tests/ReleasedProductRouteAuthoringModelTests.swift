import XCTest

@testable import KaidoRoutesApp

@MainActor
final class ReleasedProductRouteAuthoringModelTests: XCTestCase {
  func testReleaseOwnedChoicesCompileExactRouteAndAdmitExactEvidence()
    throws
  {
    let entry = try makeReleasedProductTestEntry()
    let model = try ReleasedProductRouteAuthoringModel(
      entries: [entry],
      locale: .simplifiedChinese,
      evidenceProvider: {
        makeReleasedPreDriveEvidence(for: $0)
      }
    )

    XCTAssertEqual(model.options.count, 1)
    XCTAssertFalse(model.options[0].entranceTitle.isEmpty)
    XCTAssertFalse(model.options[0].finalChoiceTitle.isEmpty)
    XCTAssertNil(model.compiledRoutePlan)

    authorReleasedRoute(model, entry: entry)

    XCTAssertEqual(
      model.compiledRoutePlan,
      entry.release.navigation.bundle.routePlan
    )
    XCTAssertTrue(model.reviewReady)
    XCTAssertEqual(
      model.preDriveReviewSnapshot?.routePlanID,
      entry.release.navigation.bundle.routePlan.id
    )
    XCTAssertNil(model.lastErrorCode)
  }

  func testMissingPreDriveEvidenceKeepsCompiledReleaseBlocked() throws {
    let entry = try makeReleasedProductTestEntry()
    let model = try ReleasedProductRouteAuthoringModel(
      entries: [entry],
      locale: .japanese
    )

    authorReleasedRoute(model, entry: entry)

    XCTAssertEqual(
      model.compiledRoutePlan,
      entry.release.navigation.bundle.routePlan
    )
    XCTAssertFalse(model.reviewReady)
    XCTAssertNil(model.preDriveReviewSnapshot)
    XCTAssertEqual(
      model.lastErrorCode,
      ReleasedProductRouteAuthoringError.preDriveEvidenceUnavailable.rawValue
    )
  }

  func testDriftedPreDriveEvidenceFailsClosed() throws {
    let entry = try makeReleasedProductTestEntry()
    let model = try ReleasedProductRouteAuthoringModel(
      entries: [entry],
      locale: .english,
      evidenceProvider: {
        makeReleasedPreDriveEvidence(
          for: $0,
          routePlanID: "test.route-plan.drift"
        )
      }
    )

    authorReleasedRoute(model, entry: entry)

    XCTAssertFalse(model.reviewReady)
    XCTAssertNil(model.preDriveReviewSnapshot)
    XCTAssertEqual(
      model.lastErrorCode,
      ReleasedProductRouteAuthoringError.preDriveEvidenceRejected.rawValue
    )
  }

  func testWrongReleasedChoiceDoesNotMutateEditor() throws {
    let entry = try makeReleasedProductTestEntry()
    let model = try ReleasedProductRouteAuthoringModel(
      entries: [entry],
      locale: .english
    )
    model.selectRelease(entry.release.releaseID)
    let original = try XCTUnwrap(model.snapshot)

    model.selectReleasedChoice("test.choice.not-in-recipe")

    XCTAssertEqual(model.snapshot, original)
    XCTAssertNil(model.compiledRoutePlan)
    XCTAssertEqual(
      model.lastErrorCode,
      ReleasedProductRouteAuthoringError.choiceRejected.rawValue
    )
  }

  func testLocaleChangeRebuildsPresentationWithoutChangingProgress()
    throws
  {
    let entry = try makeReleasedProductTestEntry()
    let model = try ReleasedProductRouteAuthoringModel(
      entries: [entry],
      locale: .simplifiedChinese
    )
    model.selectRelease(entry.release.releaseID)
    let firstStep = try XCTUnwrap(model.currentStep)
    model.selectReleasedChoice(firstStep.choiceID)
    let occurrenceIDs = try XCTUnwrap(model.snapshot).occurrences.map(\.id)
    let nextChoiceID = try XCTUnwrap(model.currentStep).choiceID

    model.updateLocale(.english)

    XCTAssertEqual(model.locale, .english)
    XCTAssertEqual(model.snapshot?.occurrences.map(\.id), occurrenceIDs)
    XCTAssertEqual(model.currentStep?.choiceID, nextChoiceID)
    XCTAssertFalse(try XCTUnwrap(model.currentStep).choiceTitle.isEmpty)
    XCTAssertNil(model.lastErrorCode)
  }

  func testLocaleChangeReevaluatesCompiledRouteEvidence() throws {
    let entry = try makeReleasedProductTestEntry()
    var evidenceAvailable = true
    let model = try ReleasedProductRouteAuthoringModel(
      entries: [entry],
      locale: .japanese,
      evidenceProvider: {
        evidenceAvailable
          ? makeReleasedPreDriveEvidence(for: $0)
          : nil
      }
    )
    authorReleasedRoute(model, entry: entry)
    XCTAssertTrue(model.reviewReady)

    evidenceAvailable = false
    model.updateLocale(.english)

    XCTAssertEqual(model.locale, .english)
    XCTAssertEqual(
      model.compiledRoutePlan,
      entry.release.navigation.bundle.routePlan
    )
    XCTAssertFalse(model.reviewReady)
    XCTAssertEqual(
      model.lastErrorCode,
      ReleasedProductRouteAuthoringError.preDriveEvidenceUnavailable.rawValue
    )
  }
}
