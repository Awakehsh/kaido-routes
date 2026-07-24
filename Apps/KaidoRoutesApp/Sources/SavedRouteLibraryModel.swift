import Combine
import Foundation
import KaidoAppleAdapters
import KaidoDomain

enum SavedRouteLibraryAvailability: Equatable {
  case unavailable
  case selected(String)
  case ambiguous([String])
  case invalid(String)
}

enum SavedRouteLibraryModelError: String, Error, Equatable {
  case storeUnavailable = "SAVED_ROUTE_STORE_UNAVAILABLE"
  case loadFailed = "SAVED_ROUTE_STORE_LOAD_FAILED"
  case writeFailed = "SAVED_ROUTE_STORE_WRITE_FAILED"
  case invalidName = "SAVED_ROUTE_NAME_INVALID"
  case routeUnavailable = "SAVED_ROUTE_PLAN_UNAVAILABLE"
  case recordUnavailable = "SAVED_ROUTE_RECORD_UNAVAILABLE"
  case importFailed = "SAVED_ROUTE_IMPORT_FAILED"
  case exportFailed = "SAVED_ROUTE_EXPORT_FAILED"
}

/// Parked-only saved-route persistence and current-release selection.
///
/// Saving preserves a complete SharedRouteDocument. Selection can identify one
/// exact current product release, but this model cannot compile or execute it.
@MainActor
final class SavedRouteLibraryModel: ObservableObject {
  @Published private(set) var records: [SavedRouteRecord] = []
  @Published private(set) var lastErrorCode: String?
  @Published private(set) var lastSavedRecordID: String?

  private let store: (any SavedRouteLibraryStoring)?
  private let releaseCandidates: [SavedRouteReleaseCandidate]
  private let recordIDProvider: () -> String
  private let savedAtProvider: () -> String

  init(
    store: (any SavedRouteLibraryStoring)?,
    foregroundEntries: [BundledProductReleaseEntry],
    recordIDProvider: @escaping () -> String = {
      "saved-route.\(UUID().uuidString.lowercased())"
    },
    savedAtProvider: @escaping () -> String = {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [
        .withInternetDateTime,
        .withFractionalSeconds,
      ]
      return formatter.string(from: Date())
    }
  ) {
    self.store = store
    releaseCandidates = foregroundEntries.map {
      SavedRouteReleaseCandidate(
        releaseID: $0.release.releaseID,
        routePlan: $0.release.navigation.bundle.routePlan
      )
    }
    self.recordIDProvider = recordIDProvider
    self.savedAtProvider = savedAtProvider
    load()
  }

  var storageAvailable: Bool {
    store != nil
  }

  func save(
    routePlan: RoutePlan?,
    displayName: String,
    evidenceState: SharedRouteEvidenceState,
    templateParameters: [String: String] = [:]
  ) {
    guard let store else {
      fail(.storeUnavailable)
      return
    }
    guard let routePlan else {
      fail(.routeUnavailable)
      return
    }
    let name = displayName.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !name.isEmpty else {
      fail(.invalidName)
      return
    }

    let record = SavedRouteRecord(
      id: recordIDProvider(),
      displayName: name,
      savedAt: savedAtProvider(),
      origin: .authoredHere,
      document: SharedRouteDocument(
        evidenceState: evidenceState,
        templateParameters: templateParameters,
        routePlan: routePlan
      )
    )
    let candidate = SavedRouteLibraryDocument(
      records: [record] + records
    )
    persist(
      candidate,
      store: store,
      successRecordID: record.id
    )
  }

  func importSharedRoute(
    _ data: Data,
    suggestedName: String
  ) {
    guard let store else {
      fail(.storeUnavailable)
      return
    }
    let recordID = recordIDProvider()
    do {
      let candidate = try SavedRouteLibraryEditor.importing(
        sharedRouteData: data,
        recordID: recordID,
        displayName: suggestedName,
        savedAt: savedAtProvider(),
        into: currentLibrary
      )
      persist(
        candidate,
        store: store,
        successRecordID: recordID
      )
    } catch {
      lastSavedRecordID = nil
      lastErrorCode = Self.errorCode(
        error,
        fallback: .importFailed
      )
    }
  }

  func rename(
    recordID: String,
    displayName: String
  ) {
    guard let store else {
      fail(.storeUnavailable)
      return
    }
    do {
      let candidate = try SavedRouteLibraryEditor.renaming(
        recordID: recordID,
        displayName: displayName,
        in: currentLibrary
      )
      persist(candidate, store: store)
    } catch {
      lastSavedRecordID = nil
      lastErrorCode = Self.errorCode(
        error,
        fallback: .writeFailed
      )
    }
  }

  func delete(recordID: String) {
    guard let store else {
      fail(.storeUnavailable)
      return
    }
    do {
      let candidate = try SavedRouteLibraryEditor.removing(
        recordID: recordID,
        from: currentLibrary
      )
      persist(candidate, store: store)
    } catch {
      lastSavedRecordID = nil
      lastErrorCode = Self.errorCode(
        error,
        fallback: .writeFailed
      )
    }
  }

  func exportSharedRoute(recordID: String) -> Data? {
    do {
      let data = try SavedRouteLibraryEditor.exportData(
        recordID: recordID,
        from: currentLibrary
      )
      lastErrorCode = nil
      return data
    } catch {
      lastErrorCode = Self.errorCode(
        error,
        fallback: .exportFailed
      )
      return nil
    }
  }

  func record(id: String) -> SavedRouteRecord? {
    records.first { $0.id == id }
  }

  func availability(
    for record: SavedRouteRecord
  ) -> SavedRouteLibraryAvailability {
    do {
      switch try SavedRouteReleaseMatcher.select(
        record: record,
        candidates: releaseCandidates
      ) {
      case .unavailable:
        return .unavailable
      case .selected(let releaseID):
        return .selected(releaseID)
      case .ambiguous(let releaseIDs):
        return .ambiguous(releaseIDs)
      }
    } catch {
      return .invalid(Self.errorCode(error, fallback: .loadFailed))
    }
  }

  private func load() {
    guard let store else {
      lastErrorCode = SavedRouteLibraryModelError.storeUnavailable.rawValue
      return
    }
    do {
      records = try store.load()?.records ?? []
      lastErrorCode = nil
    } catch {
      records = []
      lastErrorCode = Self.errorCode(
        error,
        fallback: .loadFailed
      )
    }
  }

  private var currentLibrary: SavedRouteLibraryDocument {
    SavedRouteLibraryDocument(records: records)
  }

  private func persist(
    _ candidate: SavedRouteLibraryDocument,
    store: any SavedRouteLibraryStoring,
    successRecordID: String? = nil
  ) {
    do {
      try store.save(candidate)
      records = candidate.records
      lastSavedRecordID = successRecordID
      lastErrorCode = nil
    } catch {
      lastSavedRecordID = nil
      lastErrorCode = Self.errorCode(
        error,
        fallback: .writeFailed
      )
    }
  }

  private func fail(_ error: SavedRouteLibraryModelError) {
    lastSavedRecordID = nil
    lastErrorCode = error.rawValue
  }

  private static func errorCode(
    _ error: Error,
    fallback: SavedRouteLibraryModelError
  ) -> String {
    if let error = error as? SavedRouteLibraryStoreError {
      return error.code
    }
    if let error = error as? SavedRouteLibraryCodecError {
      switch error {
      case .unsupportedSchemaVersion:
        return "SAVED_ROUTE_LIBRARY_SCHEMA_UNSUPPORTED"
      case .invalid(let issues):
        return Array(Set(issues.map(\.code))).sorted()
          .joined(separator: "+")
      }
    }
    if let error = error as? SavedRouteLibraryMutationError {
      return error.code
    }
    if let error = error as? SharedRouteCodecError {
      switch error {
      case .unsupportedSchemaVersion:
        return "SHARED_ROUTE_SCHEMA_UNSUPPORTED"
      case .invalidDocument(let issues):
        return issues.sorted().joined(separator: "+")
      }
    }
    if let error = error as? SavedRouteReleaseMatcherError {
      switch error {
      case .emptyCandidateReleaseID:
        return "SAVED_ROUTE_RELEASE_ID_EMPTY"
      case .duplicateCandidateReleaseID:
        return "SAVED_ROUTE_RELEASE_ID_DUPLICATE"
      case .invalidCandidateRoutePlan:
        return "SAVED_ROUTE_RELEASE_PLAN_INVALID"
      }
    }
    return fallback.rawValue
  }
}
