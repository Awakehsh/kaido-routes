import KaidoRouting
import XCTest

@testable import KaidoRoutesApp

@MainActor
final class EntranceRecommendationModelTests: XCTestCase {
  func testRecommendationExplainsFartherExactEditorEntrance() throws {
    let editor = try ParkedRouteEditorModel()
    let model = try EntranceRecommendationModel(routeEditor: editor)
    let snapshot = model.snapshot

    XCTAssertEqual(
      snapshot.selection.facilityID,
      editor.fixture.entranceFacilityID
    )
    XCTAssertEqual(
      snapshot.selection.joinOccurrenceID,
      editor.fixture.initialOccurrenceID
    )
    XCTAssertEqual(
      snapshot.selection.targetCarriagewayID,
      "preview.synthetic.carriageway.eastbound"
    )
    XCTAssertEqual(snapshot.selection.straightLineDistanceKM, 1.8)
    XCTAssertEqual(snapshot.selection.surfaceETAMinutes, 7)
    XCTAssertEqual(snapshot.selection.straightLineDistanceRank, 3)
    XCTAssertFalse(snapshot.isProximityOnly)
    XCTAssertEqual(
      snapshot.selection.reasonCodes,
      [
        .exactDirectionalCarriageway,
        .legalRouteJoin,
        .approachAvailableAtEntryTime,
        .lowestSurfaceETAAfterHardFilters,
      ]
    )
    XCTAssertEqual(
      snapshot.rejectedCandidates.map(\.facilityID),
      [
        "preview.synthetic.entrance.nearest.westbound",
        "preview.synthetic.entrance.unknown.eastbound",
      ]
    )
    XCTAssertEqual(
      snapshot.rejectedCandidates[0].reasonCodes,
      ["NO_LEGAL_ROUTE_JOIN"]
    )
    XCTAssertEqual(
      snapshot.rejectedCandidates[1].reasonCodes,
      ["APPROACH_AVAILABILITY_UNKNOWN"]
    )
  }

  func testRecommendationRejectsInvalidCandidateSet() throws {
    let editor = try ParkedRouteEditorModel()
    let fixture = EntranceRecommendationFixture.synthetic
    let invalid = EntranceRecommendationFixture(
      networkSnapshotID: fixture.networkSnapshotID,
      allowedJoinOccurrenceIDs: fixture.allowedJoinOccurrenceIDs,
      candidates: fixture.candidates + [fixture.candidates[0]],
      facilityTitles: fixture.facilityTitles,
      carriagewayTitles: fixture.carriagewayTitles
    )

    XCTAssertThrowsError(
      try EntranceRecommendationModel(
        routeEditor: editor,
        fixture: invalid
      )
    ) { error in
      XCTAssertEqual(
        error as? EntranceRecommendationModelError,
        .recommendationRejected(["DUPLICATE_ENTRANCE_FACILITY_ID"])
      )
    }
  }

  func testRecommendationRejectsSnapshotDrift() throws {
    let editor = try ParkedRouteEditorModel()
    let fixture = EntranceRecommendationFixture.synthetic
    let drifted = EntranceRecommendationFixture(
      networkSnapshotID: "preview.synthetic.snapshot-drift",
      allowedJoinOccurrenceIDs: fixture.allowedJoinOccurrenceIDs,
      candidates: fixture.candidates,
      facilityTitles: fixture.facilityTitles,
      carriagewayTitles: fixture.carriagewayTitles
    )

    XCTAssertThrowsError(
      try EntranceRecommendationModel(
        routeEditor: editor,
        fixture: drifted
      )
    ) { error in
      XCTAssertEqual(
        error as? EntranceRecommendationModelError,
        .networkSnapshotMismatch
      )
    }
  }
}
