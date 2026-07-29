import Foundation
import KaidoSurfaceRouting
import XCTest

@testable import KaidoRoutesApp

@MainActor
final class C2NavigationSimulationCheckpointTests: XCTestCase {
  func testFileStoreRoundTripsAndRemovesExactCheckpoint() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "kaido-c2-checkpoint-\(UUID().uuidString)",
        isDirectory: true
      )
    defer {
      try? FileManager.default.removeItem(at: directory)
    }
    let store = try FileC2NavigationSimulationCheckpointStore(
      directoryURL: directory
    )
    let checkpoint = makeCheckpoint()

    try store.save(checkpoint)

    XCTAssertEqual(try store.load(), checkpoint)
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: store.fileURL.path)
    )

    try store.remove()

    XCTAssertNil(try store.load())
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: store.fileURL.path)
    )
  }

  func testFileStoreRejectsRouteDatabaseDrift() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "kaido-c2-checkpoint-\(UUID().uuidString)",
        isDirectory: true
      )
    defer {
      try? FileManager.default.removeItem(at: directory)
    }
    let store = try FileC2NavigationSimulationCheckpointStore(
      directoryURL: directory
    )
    let checkpoint = makeCheckpoint(
      routeDatabaseID: "stale.route.database"
    )

    XCTAssertThrowsError(try store.save(checkpoint)) { error in
      XCTAssertEqual(
        error as? C2NavigationSimulationCheckpointStoreError,
        .invalidCheckpoint
      )
    }
  }

  func testActiveJourneyRestoresPausedAtExactProgress() async throws {
    let store = C2MemorySimulationCheckpointStore()
    let model = makeModel(checkpointStore: store)

    await model.planJourney()
    XCTAssertEqual(model.phase, .review)
    model.startPreparedNavigation()
    model.pause()
    advance(
      model,
      until: {
        $0.phase == .expressway
          && $0.expresswayOccurrenceIndex == 9
          && $0.expresswayOccurrenceFraction == 0.5
      }
    )
    let saved = try XCTUnwrap(store.checkpoint)

    let restored = makeModel(checkpointStore: store)

    XCTAssertEqual(restored.phase, saved.phase)
    XCTAssertEqual(
      restored.expresswayOccurrenceIndex,
      saved.expresswayOccurrenceIndex
    )
    XCTAssertEqual(
      restored.expresswayOccurrenceFraction,
      saved.expresswayOccurrenceFraction
    )
    XCTAssertEqual(restored.originQuery, saved.originQuery)
    XCTAssertEqual(restored.destinationQuery, saved.destinationQuery)
    XCTAssertEqual(restored.suspensionReason, .appInactive)
    XCTAssertTrue(restored.restoredFromCheckpoint)
    XCTAssertTrue(restored.hasRestorableJourney)
    XCTAssertFalse(restored.isPlaying)

    restored.resume()

    XCTAssertTrue(restored.isPlaying)
    XCTAssertFalse(restored.restoredFromCheckpoint)
    restored.pause()
    restored.reset()
    XCTAssertNil(store.checkpoint)
  }

  private func makeModel(
    checkpointStore: any C2NavigationSimulationCheckpointStoring
  ) -> C2NavigationDemoModel {
    C2NavigationDemoModel(
      originQuery: "東京都庁",
      destinationQuery: "東京駅",
      locationProvider: C2CheckpointLocationProvider(),
      placeResolver: C2CheckpointPlaceResolver(),
      surfaceProvider: C2CheckpointSurfaceRouteProvider(),
      playbackInterval: .seconds(60),
      checkpointStore: checkpointStore
    )
  }

  private func advance(
    _ model: C2NavigationDemoModel,
    until predicate: (C2NavigationDemoModel) -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    for _ in 0..<240 {
      if predicate(model) {
        return
      }
      model.advanceOneTickForTesting()
    }
    XCTFail(
      "Simulation did not reach the expected restored state",
      file: file,
      line: line
    )
  }

  private func makeCheckpoint(
    routeDatabaseID: String =
      C2NavigationSimulationCheckpoint.routeDatabaseID
  ) -> C2NavigationSimulationCheckpoint {
    let origin = C2NavigationResolvedPlace(
      title: "東京都庁",
      coordinate: C2CheckpointLocationProvider.coordinate
    )
    let destination = C2NavigationResolvedPlace(
      title: "東京駅",
      coordinate: C2CheckpointPlaceResolver.coordinate
    )
    return C2NavigationSimulationCheckpoint(
      routeDatabaseID: routeDatabaseID,
      originQuery: origin.title,
      destinationQuery: destination.title,
      origin: origin,
      destination: destination,
      accessRoute: C2CheckpointSurfaceRouteProvider.accessCandidate,
      egressRoute: C2CheckpointSurfaceRouteProvider.egressCandidate,
      phase: .expressway,
      surfaceProgressFraction: 0,
      surfaceStepIndex: 0,
      expresswayOccurrenceIndex: 9,
      expresswayOccurrenceFraction: 0.5,
      transitionTick: 0
    )
  }
}

@MainActor
private final class C2MemorySimulationCheckpointStore:
  C2NavigationSimulationCheckpointStoring
{
  var checkpoint: C2NavigationSimulationCheckpoint?

  func load() throws -> C2NavigationSimulationCheckpoint? {
    checkpoint
  }

  func save(
    _ checkpoint: C2NavigationSimulationCheckpoint
  ) throws {
    self.checkpoint = checkpoint
  }

  func remove() throws {
    checkpoint = nil
  }
}

@MainActor
private final class C2CheckpointLocationProvider:
  C2NavigationCurrentLocationProviding
{
  nonisolated static let coordinate = SurfaceCoordinate(
    latitude: 35.6896,
    longitude: 139.6917
  )

  func currentCoordinate() async throws -> SurfaceCoordinate {
    Self.coordinate
  }
}

@MainActor
private final class C2CheckpointPlaceResolver:
  C2NavigationPlaceResolving
{
  nonisolated static let coordinate = SurfaceCoordinate(
    latitude: 35.6812,
    longitude: 139.7671
  )

  func resolve(
    query: String,
    near _: SurfaceCoordinate?
  ) async throws -> C2NavigationResolvedPlace {
    C2NavigationResolvedPlace(
      title: query,
      coordinate: Self.coordinate
    )
  }
}

private struct C2CheckpointSurfaceRouteProvider: SurfaceRouteProvider {
  let metadata = SurfaceRouteProviderMetadata(
    id: "test.c2.checkpoint.surface",
    adapterVersion: "1.0.0",
    providerVersion: "test",
    dataReviewStatus: .derivedFixtureReviewed
  )

  func routes(
    for request: SurfaceRouteRequest
  ) async -> SurfaceProviderResponse {
    switch request.id {
    case "demo.c2.surface-access":
      .success([Self.accessCandidate])
    case "demo.c2.surface-egress":
      .success([Self.egressCandidate])
    default:
      .failure(
        SurfaceProviderFailure(
          kind: .invalidRequest,
          providerErrorCode: "UNKNOWN_TEST_REQUEST"
        )
      )
    }
  }

  static let accessCandidate = SurfaceRouteCandidate(
    id: "test.c2.checkpoint.access",
    providerID: "test.c2.checkpoint.surface",
    coordinates: [
      C2CheckpointLocationProvider.coordinate,
      C2NavigationDemoModel.tomigayaEntranceCoordinate,
    ],
    steps: [
      SurfaceRouteStep(
        id: "test.c2.checkpoint.access.step",
        instruction: "Continue to Tomigaya entrance",
        distanceMeters: 2_400
      )
    ],
    distanceMeters: 2_400,
    expectedTravelTimeSeconds: 540,
    hasHighways: false,
    hasTolls: false
  )

  static let egressCandidate = SurfaceRouteCandidate(
    id: "test.c2.checkpoint.egress",
    providerID: "test.c2.checkpoint.surface",
    coordinates: [
      C2NavigationDemoModel.hatsudaiMinamiExitCoordinate,
      C2CheckpointPlaceResolver.coordinate,
    ],
    steps: [
      SurfaceRouteStep(
        id: "test.c2.checkpoint.egress.step",
        instruction: "Continue to the final destination",
        distanceMeters: 4_920
      )
    ],
    distanceMeters: 4_920,
    expectedTravelTimeSeconds: 980,
    hasHighways: false,
    hasTolls: false
  )
}
