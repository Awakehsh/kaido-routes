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
}
