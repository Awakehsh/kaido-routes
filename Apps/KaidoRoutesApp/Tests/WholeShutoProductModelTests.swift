import XCTest

@testable import KaidoRoutesApp

@MainActor
final class WholeShutoProductModelTests: XCTestCase {
  func testActiveJourneyRestoresPausedOnTheSameNetworkSnapshot()
    async throws
  {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: store)
    model.preparePreviewJourney()
    let originalRoute = try XCTUnwrap(model.selectedRoute)

    model.startNavigationSimulation()
    model.togglePlayback()
    await advance(model, until: { $0.phase == .expressway })
    for _ in 0..<3 {
      await model.advanceSimulationForTesting()
    }
    let savedProgress = model.progressFraction
    let savedCoordinate = model.currentCoordinate

    let restored = WholeShutoProductModel(
      database: model.database,
      checkpointStore: store
    )

    XCTAssertEqual(restored.phase, .expressway)
    XCTAssertEqual(restored.progressFraction, savedProgress)
    XCTAssertEqual(
      restored.runtimeOccurrenceID,
      model.runtimeOccurrenceID
    )
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

    await restored.advanceSimulationForTesting()
    XCTAssertGreaterThanOrEqual(
      restored.progressFraction,
      savedProgress
    )
    XCTAssertEqual(restored.currentCoordinate, savedCoordinate)
  }

  func testEntryCheckpointBeforeFirstObservationRestoresRuntime()
    async
  {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: store)
    model.preparePreviewJourney()
    model.startNavigationSimulation()
    model.togglePlayback()
    await advance(model, until: { $0.phase == .entryTransition })

    XCTAssertEqual(model.progressFraction, 0)
    XCTAssertNil(model.runtimeOccurrenceID)

    let restored = WholeShutoProductModel(
      database: model.database,
      checkpointStore: store
    )

    XCTAssertEqual(restored.phase, .entryTransition)
    XCTAssertTrue(restored.restoredFromCheckpoint)
    XCTAssertNil(restored.failureCode)

    await restored.advanceSimulationForTesting()

    XCTAssertEqual(restored.matcherConfidence, .high)
    XCTAssertEqual(restored.phase, .entryTransition)
    XCTAssertNil(restored.runtimeOccurrenceID)

    await advance(restored, until: { $0.phase == .expressway })

    XCTAssertNotNil(restored.runtimeOccurrenceID)
    XCTAssertGreaterThan(restored.progressFraction, 0)
  }

  func testExpresswayPreviewExplicitlyReportsTunnelEstimation() async {
    let model = WholeShutoProductModel(checkpointStore: nil)
    model.preparePreviewJourney()
    model.startNavigationSimulation()
    model.togglePlayback()

    await advance(
      model,
      until: {
        $0.phase == .expressway
          && $0.positionState == .tunnelEstimated
      },
      maximumTicks: 180
    )

    XCTAssertEqual(model.positionState, .tunnelEstimated)
  }

  func testEntryTransitionRequiresOrderedObservationsBeforeExpressway()
    async
  {
    let model = WholeShutoProductModel(checkpointStore: nil)
    model.preparePreviewJourney()
    model.startNavigationSimulation()
    model.togglePlayback()

    await advance(model, until: { $0.phase == .entryTransition })

    XCTAssertEqual(model.progressFraction, 0)
    XCTAssertNil(model.runtimeOccurrenceID)
    XCTAssertEqual(model.positionState, .boundaryTransition)

    for _ in 0..<3 {
      await model.advanceSimulationForTesting()
    }

    XCTAssertEqual(model.matcherConfidence, .high)
    XCTAssertEqual(model.phase, .entryTransition)
    XCTAssertNil(model.runtimeOccurrenceID)

    await model.advanceSimulationForTesting()

    XCTAssertEqual(model.phase, .expressway)
    XCTAssertNotNil(model.runtimeOccurrenceID)
    XCTAssertGreaterThan(model.progressFraction, 0)
  }

  private func advance(
    _ model: WholeShutoProductModel,
    until predicate: (WholeShutoProductModel) -> Bool,
    maximumTicks: Int = 80,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    for _ in 0..<maximumTicks {
      if predicate(model) {
        return
      }
      await model.advanceSimulationForTesting()
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
