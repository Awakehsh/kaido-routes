import KaidoDomain
import KaidoPresentation
import XCTest

@testable import KaidoRoutesApp

@MainActor
final class PreDriveReviewModelTests: XCTestCase {
  func testReviewAppearsOnlyAfterExactRouteCompilation() throws {
    let editor = try ParkedRouteEditorModel()
    let review = PreDriveReviewModel(routeEditor: editor)

    XCTAssertNil(review.snapshot)
    XCTAssertFalse(review.hasCompiledRoutePlan)

    editor.select(choiceID: "preview.synthetic.choice.early-exit")
    XCTAssertNil(review.snapshot)

    editor.compile()

    let snapshot = try XCTUnwrap(review.snapshot)
    XCTAssertTrue(review.hasCompiledRoutePlan)
    XCTAssertNil(review.lastErrorCode)
    XCTAssertEqual(snapshot.routePlanID, "preview.synthetic.route-plan")
    XCTAssertEqual(snapshot.occurrenceCount, 3)
    XCTAssertEqual(snapshot.presentation.actualDistanceKM, 3.3, accuracy: 0.000_001)
    XCTAssertEqual(snapshot.presentation.tariffDistanceKM, 6.7)
    XCTAssertEqual(snapshot.presentation.estimatedAmountYen, 630)
    XCTAssertEqual(snapshot.presentation.tollEvidenceStatus, .estimated)
    XCTAssertEqual(snapshot.tariffVersionStatus, .active)
    XCTAssertEqual(
      snapshot.ignoredNonActiveQuoteIDs,
      ["preview.synthetic.quote.proposed"]
    )
    XCTAssertEqual(snapshot.presentation.passage.tone, .unconfirmed)
    XCTAssertFalse(snapshot.presentation.passage.usesPositiveOpenColor)
    XCTAssertFalse(snapshot.navigationStartAllowed)
  }

  func testRepeatedLapOccurrencesIncreaseActualButNotTariffDistance() throws {
    let editor = try ParkedRouteEditorModel()
    let review = PreDriveReviewModel(routeEditor: editor)

    editor.select(choiceID: "preview.synthetic.choice.enter-loop")
    editor.select(choiceID: "preview.synthetic.choice.repeat-loop")
    let candidate = try XCTUnwrap(editor.snapshot.availableLapCandidates.first)
    editor.duplicate(lapCandidateID: candidate.id)
    editor.select(choiceID: "preview.synthetic.choice.final-exit")
    editor.compile()

    let snapshot = try XCTUnwrap(review.snapshot)
    XCTAssertEqual(snapshot.occurrenceCount, 9)
    XCTAssertEqual(snapshot.presentation.actualDistanceKM, 40.7, accuracy: 0.000_001)
    XCTAssertEqual(snapshot.presentation.tariffDistanceKM, 6.7)

    editor.undo()

    XCTAssertNil(review.snapshot)
    XCTAssertFalse(review.hasCompiledRoutePlan)
  }

  func testRouteIdentityAndMissingDistanceFailClosed() throws {
    let editor = try ParkedRouteEditorModel()
    let review = PreDriveReviewModel(routeEditor: editor)
    let mismatched = RoutePlan(
      id: "preview.synthetic.route-plan",
      networkSnapshotID: "preview.synthetic.snapshot-drift",
      entryFacilityID: "preview.synthetic.entrance.eastbound",
      exitFacilityID: "preview.synthetic.exit.eastbound",
      recoveryPolicy: .strict,
      actualDistanceKM: 3.3,
      occurrences: []
    )

    review.bind(routePlan: mismatched)

    XCTAssertNil(review.snapshot)
    XCTAssertEqual(
      review.lastErrorCode,
      "PRE_DRIVE_ROUTE_IDENTITY_MISMATCH"
    )

    let missingDistance = RoutePlan(
      id: "preview.synthetic.route-plan",
      networkSnapshotID: "preview.synthetic.snapshot-v1",
      entryFacilityID: "preview.synthetic.entrance.eastbound",
      exitFacilityID: "preview.synthetic.exit.eastbound",
      recoveryPolicy: .strict,
      occurrences: []
    )

    review.bind(routePlan: missingDistance)

    XCTAssertNil(review.snapshot)
    XCTAssertEqual(
      review.lastErrorCode,
      "PRE_DRIVE_ACTUAL_DISTANCE_UNAVAILABLE"
    )
  }

  func testDuplicateTariffQuoteIdentityFailsClosed() throws {
    let editor = try ParkedRouteEditorModel()
    let duplicate = PreDriveReviewFixture(
      networkSnapshotID: PreDriveReviewFixture.synthetic.networkSnapshotID,
      routePlanID: PreDriveReviewFixture.synthetic.routePlanID,
      entryFacilityID: PreDriveReviewFixture.synthetic.entryFacilityID,
      exitFacilityID: PreDriveReviewFixture.synthetic.exitFacilityID,
      passageEvidence: PreDriveReviewFixture.synthetic.passageEvidence,
      tariffQuotes: [
        PreDriveReviewFixture.synthetic.tariffQuotes[0],
        PreDriveReviewFixture.synthetic.tariffQuotes[0],
      ]
    )
    let review = PreDriveReviewModel(routeEditor: editor, fixture: duplicate)

    editor.select(choiceID: "preview.synthetic.choice.early-exit")
    editor.compile()

    XCTAssertNil(review.snapshot)
    XCTAssertEqual(
      review.lastErrorCode,
      "PRE_DRIVE_INVALID_TARIFF_EVIDENCE"
    )
  }
}
