import XCTest

@testable import KaidoRoutesApp

@MainActor
final class WholeShutoProductModelTests: XCTestCase {
  func testActiveJourneyRestoresPausedOnTheSameNetworkSnapshot() throws {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: store)
    model.preparePreviewJourney()
    let originalRoute = try XCTUnwrap(model.selectedRoute)

    model.startNavigationSimulation()
    model.togglePlayback()
    advance(model, until: { $0.phase == .expressway })
    model.advanceSimulation()
    let savedProgress = model.progressFraction

    let restored = WholeShutoProductModel(
      database: model.database,
      checkpointStore: store
    )

    XCTAssertEqual(restored.phase, .expressway)
    XCTAssertEqual(restored.progressFraction, savedProgress)
    XCTAssertEqual(
      restored.selectedRoute?.entryFacility.facilityID,
      originalRoute.entryFacility.facilityID
    )
    XCTAssertEqual(
      restored.selectedRoute?.exitFacility.facilityID,
      originalRoute.exitFacility.facilityID
    )
    XCTAssertTrue(restored.restoredFromCheckpoint)
    XCTAssertFalse(restored.isPlaying)
  }

  func testExpresswayPreviewExplicitlyReportsTunnelEstimation() {
    let model = WholeShutoProductModel(checkpointStore: nil)
    model.preparePreviewJourney()
    model.startNavigationSimulation()
    model.togglePlayback()

    advance(
      model,
      until: {
        $0.phase == .expressway
          && $0.positionState == .tunnelEstimated
      },
      maximumTicks: 180
    )

    XCTAssertEqual(model.positionState, .tunnelEstimated)
  }

  private func advance(
    _ model: WholeShutoProductModel,
    until predicate: (WholeShutoProductModel) -> Bool,
    maximumTicks: Int = 80,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    for _ in 0..<maximumTicks {
      if predicate(model) {
        return
      }
      model.advanceSimulation()
    }
    XCTFail(
      "Whole-Shuto simulation did not reach the expected state",
      file: file,
      line: line
    )
  }
}

@MainActor
private final class WholeShutoMemoryCheckpointStore:
  WholeShutoJourneyCheckpointStoring
{
  var checkpoint: WholeShutoJourneyCheckpoint?

  func load() throws -> WholeShutoJourneyCheckpoint? {
    checkpoint
  }

  func save(_ checkpoint: WholeShutoJourneyCheckpoint) throws {
    self.checkpoint = checkpoint
  }

  func remove() throws {
    checkpoint = nil
  }
}
