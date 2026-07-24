import KaidoAppleAdapters
import KaidoDomain
import XCTest

@testable import KaidoRoutesApp

@MainActor
final class SavedRouteLibraryModelTests: XCTestCase {
  func testSavingSyntheticRoutePersistsCommunityCandidateWithoutDeduplication()
    throws
  {
    let store = MemorySavedRouteLibraryStore()
    let model = SavedRouteLibraryModel(
      store: store,
      foregroundEntries: [],
      recordIDProvider: { "test.saved.synthetic" },
      savedAtProvider: { "2026-07-25T05:30:00+09:00" }
    )
    let routePlan = makeRepeatedSavedRoutePlan()

    model.save(
      routePlan: routePlan,
      displayName: "  Loop twice  ",
      evidenceState: .communityCandidate,
      templateParameters: ["lap_count": "2"]
    )

    let record = try XCTUnwrap(model.records.first)
    XCTAssertEqual(record.id, "test.saved.synthetic")
    XCTAssertEqual(record.displayName, "Loop twice")
    XCTAssertEqual(record.origin, .authoredHere)
    XCTAssertEqual(
      record.document.evidenceState,
      .communityCandidate
    )
    XCTAssertEqual(
      record.document.routePlan.occurrences.map(\.entityID),
      [
        "test.edge.loop",
        "test.movement.turn",
        "test.edge.loop",
      ]
    )
    XCTAssertEqual(store.library?.records, [record])
    XCTAssertEqual(model.lastSavedRecordID, record.id)
    XCTAssertNil(model.lastErrorCode)
  }

  func testWriteFailureDoesNotPublishAnUnsavedRecord() {
    let store = MemorySavedRouteLibraryStore()
    store.saveError = SavedRouteLibraryStoreError.writeFailed
    let model = SavedRouteLibraryModel(
      store: store,
      foregroundEntries: []
    )

    model.save(
      routePlan: makeRepeatedSavedRoutePlan(),
      displayName: "Will fail",
      evidenceState: .communityCandidate
    )

    XCTAssertTrue(model.records.isEmpty)
    XCTAssertNil(model.lastSavedRecordID)
    XCTAssertEqual(
      model.lastErrorCode,
      SavedRouteLibraryStoreError.writeFailed.code
    )
  }

  func testExactSavedRouteReopensReleaseOwnedEditorWithoutCompiling()
    throws
  {
    let entry = try makeReleasedProductTestEntry()
    let record = SavedRouteRecord(
      id: "test.saved.released",
      displayName: "Released loop",
      savedAt: "2026-07-25T05:30:00+09:00",
      origin: .authoredHere,
      document: SharedRouteDocument(
        evidenceState: .released,
        routePlan: entry.release.navigation.bundle.routePlan
      )
    )
    let store = MemorySavedRouteLibraryStore(
      library: SavedRouteLibraryDocument(records: [record])
    )
    let composition = KaidoRoutesAppModel(
      productReleaseCatalog: BundledProductReleaseCatalog(
        entries: [entry]
      ),
      savedRouteStore: store
    )
    let journey = KaidoProductJourneyModel(composition: composition)

    journey.openSavedRoute(record.id)

    let authoring = try XCTUnwrap(
      composition.releasedRouteAuthoring
    )
    XCTAssertEqual(journey.stage, .authoring)
    XCTAssertNil(journey.lastBlocker)
    XCTAssertEqual(
      authoring.selectedReleaseID,
      entry.release.releaseID
    )
    XCTAssertNotNil(authoring.currentStep)
    XCTAssertNil(authoring.compiledRoutePlan)
    XCTAssertFalse(journey.routeReviewReady)
    XCTAssertFalse(journey.canStartNavigation)
  }

  func testSnapshotDriftedSavedRouteRemainsVisibleButCannotOpen()
    throws
  {
    let entry = try makeReleasedProductTestEntry()
    let releasedPlan = entry.release.navigation.bundle.routePlan
    let driftedPlan = RoutePlan(
      id: releasedPlan.id,
      networkSnapshotID: "test.snapshot.drift",
      entryFacilityID: releasedPlan.entryFacilityID,
      exitFacilityID: releasedPlan.exitFacilityID,
      recoveryPolicy: releasedPlan.recoveryPolicy,
      actualDistanceKM: releasedPlan.actualDistanceKM,
      occurrences: releasedPlan.occurrences
    )
    let record = SavedRouteRecord(
      id: "test.saved.stale",
      displayName: "Stale route",
      savedAt: "2026-07-25T05:30:00+09:00",
      origin: .sharedImport,
      document: SharedRouteDocument(
        evidenceState: .staleReviewRequired,
        routePlan: driftedPlan
      )
    )
    let store = MemorySavedRouteLibraryStore(
      library: SavedRouteLibraryDocument(records: [record])
    )
    let composition = KaidoRoutesAppModel(
      productReleaseCatalog: BundledProductReleaseCatalog(
        entries: [entry]
      ),
      savedRouteStore: store
    )
    let journey = KaidoProductJourneyModel(composition: composition)

    XCTAssertEqual(
      composition.savedRouteLibrary.availability(for: record),
      .unavailable
    )
    journey.openSavedRoute(record.id)

    XCTAssertEqual(journey.stage, .atlas)
    XCTAssertEqual(journey.lastBlocker, .savedRouteUnavailable)
    XCTAssertNil(
      composition.releasedRouteAuthoring?.selectedReleaseID
    )
  }
}

@MainActor
private final class MemorySavedRouteLibraryStore:
  SavedRouteLibraryStoring
{
  var library: SavedRouteLibraryDocument?
  var loadError: Error?
  var saveError: Error?

  init(library: SavedRouteLibraryDocument? = nil) {
    self.library = library
  }

  func load() throws -> SavedRouteLibraryDocument? {
    if let loadError { throw loadError }
    return library
  }

  func save(_ library: SavedRouteLibraryDocument) throws {
    if let saveError { throw saveError }
    self.library = library
  }
}

private func makeRepeatedSavedRoutePlan() -> RoutePlan {
  RoutePlan(
    id: "test.plan.saved",
    networkSnapshotID: "test.snapshot.saved",
    entryFacilityID: "test.entry",
    exitFacilityID: "test.exit",
    recoveryPolicy: .strict,
    actualDistanceKM: 19.2,
    occurrences: [
      RouteOccurrence(
        id: "test.occurrence.loop-1",
        index: 0,
        kind: .edge,
        entityID: "test.edge.loop"
      ),
      RouteOccurrence(
        id: "test.occurrence.turn",
        index: 1,
        kind: .junctionMovement,
        entityID: "test.movement.turn"
      ),
      RouteOccurrence(
        id: "test.occurrence.loop-2",
        index: 2,
        kind: .edge,
        entityID: "test.edge.loop"
      ),
    ]
  )
}
