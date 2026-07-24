import KaidoRouting
import XCTest

@testable import KaidoRoutesApp

@MainActor
final class ParkedRouteEditorModelTests: XCTestCase {
  func testEditorStartsAtExactParkedEntranceWithCurrentChoicesOnly() throws {
    let model = try ParkedRouteEditorModel()

    XCTAssertEqual(model.interaction, .parked)
    XCTAssertEqual(
      model.snapshot.entranceFacilityID,
      "preview.synthetic.entrance.eastbound"
    )
    XCTAssertEqual(
      model.snapshot.incomingApproachID,
      "preview.synthetic.approach.entry.eastbound"
    )
    XCTAssertEqual(
      model.snapshot.junctionComplexID,
      "preview.synthetic.junction.loop-gate"
    )
    XCTAssertEqual(
      model.snapshot.availableChoices.map(\.id),
      [
        "preview.synthetic.choice.enter-loop",
        "preview.synthetic.choice.early-exit",
      ]
    )
    XCTAssertEqual(
      model.snapshot.occurrences.map(\.id),
      ["preview.synthetic.occurrence.entry.0"]
    )
    XCTAssertFalse(model.canUndo)
    XCTAssertFalse(model.canCompile)
  }

  func testFutureChoiceFailsClosedWithoutMutatingRoute() throws {
    let model = try ParkedRouteEditorModel()
    let originalSnapshot = model.snapshot

    model.select(choiceID: "preview.synthetic.choice.final-exit")

    XCTAssertEqual(model.lastErrorCode, "ILLEGAL_EDITOR_CHOICE")
    XCTAssertEqual(model.snapshot, originalSnapshot)
    XCTAssertFalse(model.canCompile)
  }

  func testReviewedLapCandidateDuplicatesValuesAndUndoRemovesWholeLap() throws {
    let model = try ParkedRouteEditorModel()

    model.select(choiceID: "preview.synthetic.choice.enter-loop")
    XCTAssertTrue(model.snapshot.availableLapCandidates.isEmpty)

    model.select(choiceID: "preview.synthetic.choice.repeat-loop")
    let candidate = try XCTUnwrap(model.snapshot.availableLapCandidates.first)
    XCTAssertEqual(
      candidate.reviewedTemplateID,
      "preview.synthetic.lap-template.loop"
    )
    XCTAssertEqual(
      candidate.sourceOccurrenceIDs,
      [
        "preview.synthetic.occurrence.movement.2",
        "preview.synthetic.occurrence.edge.2",
      ]
    )

    model.duplicate(lapCandidateID: candidate.id)

    XCTAssertNil(model.lastErrorCode)
    XCTAssertEqual(
      Array(model.snapshot.occurrences.suffix(2).map(\.id)),
      [
        "preview.synthetic.occurrence.lap-copy.1.1",
        "preview.synthetic.occurrence.lap-copy.1.2",
      ]
    )
    XCTAssertEqual(
      Array(model.snapshot.occurrences.suffix(2).map(\.entityID)),
      [
        "preview.synthetic.movement.repeat-loop",
        "preview.synthetic.edge.loop",
      ]
    )
    XCTAssertEqual(model.snapshot.availableLapCandidates.count, 2)

    let removedIDs = Set(model.snapshot.occurrences.suffix(2).map(\.id))
    model.undo()

    XCTAssertEqual(model.snapshot.availableLapCandidates.count, 1)
    XCTAssertEqual(model.snapshot.occurrences.count, 5)

    model.duplicate(lapCandidateID: candidate.id)

    XCTAssertEqual(
      Array(model.snapshot.occurrences.suffix(2).map(\.id)),
      [
        "preview.synthetic.occurrence.lap-copy.2.1",
        "preview.synthetic.occurrence.lap-copy.2.2",
      ]
    )
    XCTAssertTrue(
      removedIDs.isDisjoint(with: Set(model.snapshot.occurrences.map(\.id)))
    )
  }

  func testUnknownLapCandidateFailsClosedWithoutMutatingRoute() throws {
    let model = try ParkedRouteEditorModel()
    let originalSnapshot = model.snapshot

    model.duplicate(lapCandidateID: "preview.synthetic.lap.unknown")

    XCTAssertEqual(model.lastErrorCode, "ILLEGAL_EDITOR_LAP_CANDIDATE")
    XCTAssertEqual(model.snapshot, originalSnapshot)
  }

  func testRepeatedLoopSelectionsKeepFreshOccurrenceIdentityAfterUndo() throws {
    let model = try ParkedRouteEditorModel()

    model.select(choiceID: "preview.synthetic.choice.enter-loop")
    model.select(choiceID: "preview.synthetic.choice.repeat-loop")
    model.select(choiceID: "preview.synthetic.choice.repeat-loop")

    XCTAssertEqual(
      model.snapshot.occurrences.map(\.entityID)
        .filter { $0 == "preview.synthetic.edge.loop" }
        .count,
      3
    )
    XCTAssertEqual(
      Set(model.snapshot.occurrences.map(\.id)).count,
      model.snapshot.occurrences.count
    )

    let removedIDs = Set(model.snapshot.occurrences.suffix(2).map(\.id))
    model.undo()
    model.select(choiceID: "preview.synthetic.choice.repeat-loop")

    XCTAssertTrue(
      removedIDs.isDisjoint(with: Set(model.snapshot.occurrences.map(\.id)))
    )
    XCTAssertEqual(model.snapshot.currentDecisionPointID, "preview.synthetic.decision.loop")
  }

  func testExplicitExitUnlocksDomainCompilation() throws {
    let model = try ParkedRouteEditorModel()

    model.select(choiceID: "preview.synthetic.choice.early-exit")

    XCTAssertEqual(model.snapshot.state, .finished)
    XCTAssertEqual(
      model.snapshot.selectedExitFacilityID,
      "preview.synthetic.exit.eastbound"
    )
    XCTAssertTrue(model.snapshot.availableChoices.isEmpty)
    XCTAssertTrue(model.canCompile)

    model.compile()

    let routePlan = try XCTUnwrap(model.compiledRoutePlan)
    XCTAssertEqual(routePlan.networkSnapshotID, "preview.synthetic.snapshot-v1")
    XCTAssertEqual(routePlan.entryFacilityID, "preview.synthetic.entrance.eastbound")
    XCTAssertEqual(routePlan.exitFacilityID, "preview.synthetic.exit.eastbound")
    XCTAssertEqual(
      try XCTUnwrap(routePlan.actualDistanceKM),
      3.3,
      accuracy: 0.000_001
    )
    XCTAssertEqual(routePlan.occurrences.map(\.index), [0, 1, 2])
  }

  func testMovingEditorInitializationFailsClosed() {
    XCTAssertThrowsError(
      try ParkedRouteEditorModel(interaction: .moving)
    ) { error in
      XCTAssertEqual(error as? ExpertRouteEditorError, .interactionLocked)
    }
  }
}
