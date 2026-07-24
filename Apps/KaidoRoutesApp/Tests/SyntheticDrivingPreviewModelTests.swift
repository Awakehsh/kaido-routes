import KaidoDomain
import KaidoPresentation
import XCTest

@testable import KaidoRoutesApp

@MainActor
final class SyntheticDrivingPreviewModelTests: XCTestCase {
  func testDefaultStatePreservesDegradedDecisionZoneSemantics() throws {
    let model = try SyntheticDrivingPreviewModel()
    let state = model.state
    let phone = state.projection.iPhone

    XCTAssertEqual(model.selectedCase, .degradedDecisionZone)
    XCTAssertEqual(state.snapshot.locationConfidence, .low)
    XCTAssertEqual(phone.marker, .estimated)
    XCTAssertEqual(phone.passage.tone, .unconfirmed)
    XCTAssertFalse(phone.passage.usesPositiveOpenColor)
    XCTAssertEqual(
      phone.routeEditingAvailability,
      .unavailableInDecisionZone
    )
    XCTAssertFalse(phone.requiresPhoneTouchWhileMoving)
    XCTAssertTrue(state.isInsideDecisionZone)
    XCTAssertFalse(state.projection.voice.shouldSpeak)
  }

  func testMeasuredReferenceIsDistinctFromEstimatedState() throws {
    let model = try SyntheticDrivingPreviewModel()
    let estimated = model.state.projection.iPhone.marker

    model.select(.measuredReference)

    XCTAssertEqual(model.selectedCase, .measuredReference)
    XCTAssertEqual(estimated, .estimated)
    XCTAssertEqual(model.state.snapshot.locationConfidence, .high)
    XCTAssertEqual(model.state.projection.iPhone.marker, .measured)
    XCTAssertNotEqual(model.state.projection.iPhone.marker, estimated)
    XCTAssertNil(model.lastErrorCode)
  }

  func testFinishDriveRunsEngineAndNamesSelectedExitFirst() throws {
    let model = try SyntheticDrivingPreviewModel()

    model.select(.finishDrive)

    let state = model.state
    let finish = try XCTUnwrap(state.projection.iPhone.finishDrive)
    XCTAssertEqual(model.selectedCase, .finishDrive)
    XCTAssertEqual(state.snapshot.egress.status, .active)
    XCTAssertEqual(
      state.snapshot.egress.exitFacilityID,
      "preview.synthetic.exit.shibakoen"
    )
    XCTAssertTrue(
      state.snapshot.egress.prohibitedActions.contains("U_TURN_OR_REVERSAL")
    )
    XCTAssertEqual(finish.exitFacilityID, state.snapshot.egress.exitFacilityID)
    XCTAssertEqual(finish.localizedExitName, "芝公园出口")
    XCTAssertEqual(finish.announcementPriority, .beforeBranchGuidance)
    XCTAssertEqual(state.projection.iPhone.routeShields, ["C1"])
    XCTAssertEqual(state.projection.carPlay.finishDrive, finish)
    XCTAssertFalse(state.projection.voice.shouldSpeak)
  }

  func testReviewedJunctionHandoffSharesOccurrenceAndImmutableView() throws {
    let model = try SyntheticDrivingPreviewModel()

    model.select(.reviewedJunctionHandoff)

    let state = model.state
    let phone = state.projection.iPhone
    let carPlay = state.projection.carPlay
    let junctionView = try XCTUnwrap(phone.junctionView)
    XCTAssertEqual(model.selectedCase, .reviewedJunctionHandoff)
    XCTAssertEqual(state.snapshot.presentationSurface, .carPlay)
    XCTAssertEqual(state.snapshot.carPlayConnectionState, .connected)
    XCTAssertFalse(phone.isPrimarySurface)
    XCTAssertTrue(carPlay.isPrimarySurface)
    XCTAssertEqual(phone.currentOccurrenceID, carPlay.currentOccurrenceID)
    XCTAssertEqual(
      phone.nextMovementOccurrenceID,
      carPlay.nextMovementOccurrenceID
    )
    XCTAssertEqual(phone.guidancePromptID, carPlay.guidancePromptID)
    XCTAssertEqual(phone.distanceMeters, carPlay.distanceMeters)
    XCTAssertEqual(phone.maneuver, carPlay.maneuver)
    XCTAssertEqual(phone.lanePreparation, carPlay.lanePreparation)
    XCTAssertEqual(carPlay.junctionView, junctionView)
    XCTAssertEqual(
      junctionView.networkSnapshotID,
      "preview.synthetic.driving-snapshot-v1"
    )
    XCTAssertEqual(
      junctionView.movementOccurrenceID,
      phone.nextMovementOccurrenceID
    )
    XCTAssertEqual(
      junctionView.paths.first(where: { $0.role == .selected })?.id,
      "preview.synthetic.junction-path.selected"
    )
    XCTAssertEqual(junctionView.laneLayout.laneCount, 3)
    XCTAssertEqual(junctionView.laneLayout.allowedLaneIndices, [0, 1])
    XCTAssertEqual(junctionView.laneLayout.preferredLaneIndices, [0])
    XCTAssertEqual(junctionView.japaneseSignText, phone.japaneseSignText)
    XCTAssertEqual(junctionView.routeShields, phone.routeShields)
    XCTAssertEqual(junctionView.evidence.state, .released)
    XCTAssertFalse(state.projection.voice.shouldSpeak)
  }

  func testEveryStateKeepsPhoneAndCarPlayOccurrenceSemanticsAligned() throws {
    let model = try SyntheticDrivingPreviewModel()

    for previewCase in SyntheticDrivingPreviewCase.allCases {
      model.select(previewCase)

      let phone = model.state.projection.iPhone
      let carPlay = model.state.projection.carPlay
      XCTAssertEqual(phone.currentOccurrenceID, carPlay.currentOccurrenceID)
      XCTAssertEqual(
        phone.nextMovementOccurrenceID,
        carPlay.nextMovementOccurrenceID
      )
      XCTAssertEqual(phone.marker, carPlay.marker)
      XCTAssertEqual(phone.finishDrive, carPlay.finishDrive)
      XCTAssertFalse(model.state.projection.voice.shouldSpeak)
      XCTAssertNil(model.lastErrorCode)
    }
  }

  func testMissingFinishNamesFailClosedWithoutReplacingCurrentState() throws {
    let valid = SyntheticDrivingPreviewFixture.synthetic
    let invalid = SyntheticDrivingPreviewFixture(
      networkSnapshotID: valid.networkSnapshotID,
      routePlan: valid.routePlan,
      egressOption: valid.egressOption,
      approachFrame: valid.approachFrame,
      junctionFrame: valid.junctionFrame,
      finishFrame: valid.finishFrame,
      facilityNames: [:]
    )
    let model = try SyntheticDrivingPreviewModel(fixture: invalid)

    model.select(.finishDrive)

    XCTAssertEqual(model.selectedCase, .degradedDecisionZone)
    XCTAssertEqual(model.state.previewCase, .degradedDecisionZone)
    XCTAssertEqual(
      model.lastErrorCode,
      "DRIVING_PREVIEW_PROJECTION_FAILED"
    )
    XCTAssertNil(model.state.projection.iPhone.finishDrive)
  }

  func testUnreleasedJunctionViewFailsClosedWithoutReplacingCurrentState() throws {
    let valid = SyntheticDrivingPreviewFixture.synthetic
    let validView = try XCTUnwrap(
      valid.junctionFrame.presentationSource.junctionView
    )
    let unreleasedView = JunctionViewDefinition(
      id: validView.id,
      networkSnapshotID: validView.networkSnapshotID,
      movementOccurrenceID: validView.movementOccurrenceID,
      paths: validView.paths,
      laneLayout: validView.laneLayout,
      japaneseSignText: validView.japaneseSignText,
      routeShields: validView.routeShields,
      evidence: JunctionViewEvidence(
        state: .officialChecked,
        checkedAt: validView.evidence.checkedAt,
        sourceReferenceIDs: validView.evidence.sourceReferenceIDs
      )
    )
    let invalidFrame = replacingJunctionView(
      in: valid.junctionFrame,
      with: unreleasedView
    )
    let invalidFixture = SyntheticDrivingPreviewFixture(
      networkSnapshotID: valid.networkSnapshotID,
      routePlan: valid.routePlan,
      egressOption: valid.egressOption,
      approachFrame: valid.approachFrame,
      junctionFrame: invalidFrame,
      finishFrame: valid.finishFrame,
      facilityNames: valid.facilityNames
    )
    let model = try SyntheticDrivingPreviewModel(fixture: invalidFixture)

    model.select(.reviewedJunctionHandoff)

    XCTAssertEqual(model.selectedCase, .degradedDecisionZone)
    XCTAssertEqual(model.state.previewCase, .degradedDecisionZone)
    XCTAssertEqual(
      model.lastErrorCode,
      "DRIVING_PREVIEW_PROJECTION_FAILED"
    )
    XCTAssertNil(model.state.projection.iPhone.junctionView)
  }

  private func replacingJunctionView(
    in frame: GuidanceFrame,
    with junctionView: JunctionViewDefinition
  ) -> GuidanceFrame {
    GuidanceFrame(
      promptID: frame.promptID,
      anchorID: frame.anchorID,
      anchorOccurrenceID: frame.anchorOccurrenceID,
      movementOccurrenceID: frame.movementOccurrenceID,
      decisionZoneID: frame.decisionZoneID,
      stage: frame.stage,
      distanceMeters: frame.distanceMeters,
      decisionPointNameJapanese: frame.decisionPointNameJapanese,
      localizedDecisionPointNames: frame.localizedDecisionPointNames,
      maneuver: frame.maneuver,
      lanePreparation: frame.lanePreparation,
      presentationSource: GuidancePresentationSource(
        routeShields: frame.presentationSource.routeShields,
        japaneseSignText: frame.presentationSource.japaneseSignText,
        localizedContent: frame.presentationSource.localizedContent,
        junctionView: junctionView
      )
    )
  }
}
