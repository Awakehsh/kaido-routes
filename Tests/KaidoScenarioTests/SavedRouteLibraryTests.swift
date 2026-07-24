import Foundation
import KaidoAppleAdapters
import KaidoDomain
import Testing

@Test("Saved-route library round-trip preserves exact occurrence intent")
func savedRouteLibraryRoundTripPreservesOccurrences() throws {
  let record = makeSavedRouteRecord()
  let library = SavedRouteLibraryDocument(records: [record])

  let first = try SavedRouteLibraryCodec.encode(library)
  let decoded = try SavedRouteLibraryCodec.decode(first)
  let second = try SavedRouteLibraryCodec.encode(decoded)

  #expect(decoded == library)
  #expect(first == second)
  #expect(
    decoded.records[0].document.routePlan.occurrences.map(\.id) == [
      "test.occurrence.loop-1",
      "test.occurrence.turn",
      "test.occurrence.loop-2",
    ])
  #expect(
    decoded.records[0].document.routePlan.occurrences.map(\.entityID) == [
      "test.edge.loop",
      "test.movement.turn",
      "test.edge.loop",
    ])
}

@Test("Saved-route lifecycle preserves shared authority and provenance")
func savedRouteLifecyclePreservesSharedDocument() throws {
  let localRecord = makeSavedRouteRecord()
  let original = SavedRouteLibraryDocument(
    records: [localRecord]
  )
  let sharedData = try SavedRouteLibraryEditor.exportData(
    recordID: localRecord.id,
    from: original
  )

  let imported = try SavedRouteLibraryEditor.importing(
    sharedRouteData: sharedData,
    recordID: "test.saved-route.imported",
    displayName: "  Imported loop  ",
    savedAt: "2026-07-25T06:00:00+09:00",
    into: original
  )
  let importedRecord = imported.records[0]
  #expect(
    imported.records.map(\.id) == [
      "test.saved-route.imported",
      localRecord.id,
    ])
  #expect(importedRecord.displayName == "Imported loop")
  #expect(importedRecord.origin == .sharedImport)
  #expect(importedRecord.document == localRecord.document)
  #expect(
    importedRecord.document.routePlan.occurrences.map(\.entityID) == [
      "test.edge.loop",
      "test.movement.turn",
      "test.edge.loop",
    ])

  let renamed = try SavedRouteLibraryEditor.renaming(
    recordID: importedRecord.id,
    displayName: "  Renamed import  ",
    in: imported
  )
  #expect(renamed.records[0].displayName == "Renamed import")
  #expect(renamed.records[0].savedAt == importedRecord.savedAt)
  #expect(renamed.records[0].origin == .sharedImport)
  #expect(renamed.records[0].document == importedRecord.document)
  #expect(
    try SavedRouteLibraryEditor.exportData(
      recordID: importedRecord.id,
      from: renamed
    ) == sharedData
  )

  let removed = try SavedRouteLibraryEditor.removing(
    recordID: importedRecord.id,
    from: renamed
  )
  #expect(removed == original)
}

@Test("Saved-route lifecycle fails closed without implicit migration")
func savedRouteLifecycleRejectsInvalidMutation() throws {
  let record = makeSavedRouteRecord()
  let library = SavedRouteLibraryDocument(records: [record])

  #expect(
    throws: SavedRouteLibraryMutationError.invalidDisplayName
  ) {
    _ = try SavedRouteLibraryEditor.renaming(
      recordID: record.id,
      displayName: " ",
      in: library
    )
  }
  #expect(
    throws:
      SavedRouteLibraryMutationError
      .recordNotFound("test.saved-route.unknown")
  ) {
    _ = try SavedRouteLibraryEditor.removing(
      recordID: "test.saved-route.unknown",
      from: library
    )
  }
  #expect(
    throws:
      SavedRouteLibraryMutationError
      .recordNotFound("test.saved-route.unknown")
  ) {
    _ = try SavedRouteLibraryEditor.exportData(
      recordID: "test.saved-route.unknown",
      from: library
    )
  }

  let unsupported = SharedRouteDocument(
    schemaVersion: "999",
    evidenceState: record.document.evidenceState,
    templateParameters: record.document.templateParameters,
    routePlan: record.document.routePlan
  )
  let unsupportedData = try JSONEncoder().encode(unsupported)
  #expect(
    throws: SharedRouteCodecError.unsupportedSchemaVersion("999")
  ) {
    _ = try SavedRouteLibraryEditor.importing(
      sharedRouteData: unsupportedData,
      recordID: "test.saved-route.imported",
      displayName: "Unsupported",
      savedAt: "2026-07-25T06:00:00+09:00",
      into: library
    )
  }
}

@Test("Saved-route library rejects metadata and embedded document drift")
func savedRouteLibraryRejectsInvalidRecords() throws {
  let valid = makeSavedRouteRecord()
  let invalidDocument = SharedRouteDocument(
    evidenceState: .communityCandidate,
    routePlan: RoutePlan(
      id: "test.plan.invalid",
      networkSnapshotID: "test.snapshot.saved-v1",
      entryFacilityID: "test.entry",
      exitFacilityID: "test.exit",
      recoveryPolicy: .strict,
      occurrences: []
    )
  )
  let library = SavedRouteLibraryDocument(
    records: [
      valid,
      SavedRouteRecord(
        id: valid.id,
        displayName: " ",
        savedAt: "not-a-date",
        origin: .sharedImport,
        document: invalidDocument
      ),
    ]
  )

  do {
    try SavedRouteLibraryCodec.validate(library)
    Issue.record("Expected invalid saved-route records to fail")
  } catch SavedRouteLibraryCodecError.invalid(let issues) {
    #expect(
      issues.map(\.code) == [
        "SAVED_ROUTE_DOCUMENT_INVALID",
        "SAVED_ROUTE_ID_DUPLICATE",
        "SAVED_ROUTE_NAME_EMPTY",
        "SAVED_ROUTE_SAVED_AT_INVALID",
      ]
    )
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Saved route reopens only through one exact current release")
func savedRouteReleaseMatcherRequiresOneWholeRoutePlan() throws {
  let record = makeSavedRouteRecord()
  let exact = SavedRouteReleaseCandidate(
    releaseID: "test.release.exact",
    routePlan: record.document.routePlan
  )
  var driftedPlan = record.document.routePlan
  driftedPlan = RoutePlan(
    id: driftedPlan.id,
    networkSnapshotID: "test.snapshot.saved-v2",
    entryFacilityID: driftedPlan.entryFacilityID,
    exitFacilityID: driftedPlan.exitFacilityID,
    recoveryPolicy: driftedPlan.recoveryPolicy,
    actualDistanceKM: driftedPlan.actualDistanceKM,
    occurrences: driftedPlan.occurrences
  )

  #expect(
    try SavedRouteReleaseMatcher.select(
      record: record,
      candidates: [
        SavedRouteReleaseCandidate(
          releaseID: "test.release.snapshot-drift",
          routePlan: driftedPlan
        ),
        exact,
      ]
    ) == .selected("test.release.exact")
  )
  #expect(
    try SavedRouteReleaseMatcher.select(
      record: record,
      candidates: [
        SavedRouteReleaseCandidate(
          releaseID: "test.release.snapshot-drift",
          routePlan: driftedPlan
        )
      ]
    ) == .unavailable
  )
  #expect(
    try SavedRouteReleaseMatcher.select(
      record: record,
      candidates: [
        exact,
        SavedRouteReleaseCandidate(
          releaseID: "test.release.second-exact",
          routePlan: record.document.routePlan
        ),
      ]
    )
      == .ambiguous([
        "test.release.exact",
        "test.release.second-exact",
      ])
  )
}

@Test("Saved route candidate identities fail closed")
func savedRouteReleaseMatcherRejectsCandidateIdentityDrift() throws {
  let record = makeSavedRouteRecord()

  #expect(throws: SavedRouteReleaseMatcherError.emptyCandidateReleaseID) {
    _ = try SavedRouteReleaseMatcher.select(
      record: record,
      candidates: [
        SavedRouteReleaseCandidate(
          releaseID: "",
          routePlan: record.document.routePlan
        )
      ]
    )
  }
  #expect(
    throws:
      SavedRouteReleaseMatcherError
      .duplicateCandidateReleaseID("test.release.duplicate")
  ) {
    _ = try SavedRouteReleaseMatcher.select(
      record: record,
      candidates: [
        SavedRouteReleaseCandidate(
          releaseID: "test.release.duplicate",
          routePlan: record.document.routePlan
        ),
        SavedRouteReleaseCandidate(
          releaseID: "test.release.duplicate",
          routePlan: record.document.routePlan
        ),
      ]
    )
  }
}

@MainActor
@Test("Saved-route file store atomically round-trips one whole library")
func savedRouteFileStoreRoundTripsLibrary() throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent(
      "kaido-saved-route-store-\(UUID().uuidString)",
      isDirectory: true
    )
  defer {
    try? FileManager.default.removeItem(at: directory)
  }
  let store = try FileSavedRouteLibraryStore(directoryURL: directory)
  let library = SavedRouteLibraryDocument(
    records: [makeSavedRouteRecord()]
  )

  #expect(try store.load() == nil)
  try store.save(library)
  #expect(try store.load() == library)

  let encoded = try Data(contentsOf: store.fileURL)
  #expect(try SavedRouteLibraryCodec.decode(encoded) == library)
}

@MainActor
@Test("Saved-route file store refuses unsafe names and corrupt input")
func savedRouteFileStoreFailsClosed() throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent(
      "kaido-saved-route-store-\(UUID().uuidString)",
      isDirectory: true
    )
  defer {
    try? FileManager.default.removeItem(at: directory)
  }

  #expect(throws: SavedRouteLibraryStoreError.invalidPathComponent) {
    _ = try FileSavedRouteLibraryStore(
      directoryURL: directory,
      fileName: "../saved-routes.json"
    )
  }

  let store = try FileSavedRouteLibraryStore(directoryURL: directory)
  try FileManager.default.createDirectory(
    at: directory,
    withIntermediateDirectories: true
  )
  try Data("{\"schema_version\":\"999\"}".utf8).write(
    to: store.fileURL
  )
  #expect(throws: SavedRouteLibraryStoreError.readFailed) {
    _ = try store.load()
  }
}

private func makeSavedRouteRecord() -> SavedRouteRecord {
  SavedRouteRecord(
    id: "test.saved-route.loop",
    displayName: "Two-loop night route",
    savedAt: "2026-07-25T05:00:00+09:00",
    origin: .authoredHere,
    document: SharedRouteDocument(
      evidenceState: .communityCandidate,
      templateParameters: ["lap_count": "2"],
      routePlan: RoutePlan(
        id: "test.plan.saved",
        networkSnapshotID: "test.snapshot.saved-v1",
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
    )
  )
}
