import Foundation

public enum SavedRouteOrigin: String, Codable, Equatable, Sendable {
  case authoredHere = "AUTHORED_HERE"
  case sharedImport = "SHARED_IMPORT"
}

/// One user-visible saved route.
///
/// The embedded SharedRouteDocument remains the route contract. Library
/// metadata cannot change its evidence state, snapshot, or occurrence order.
public struct SavedRouteRecord: Codable, Equatable, Sendable {
  public let id: String
  public let displayName: String
  public let savedAt: String
  public let origin: SavedRouteOrigin
  public let document: SharedRouteDocument

  public init(
    id: String,
    displayName: String,
    savedAt: String,
    origin: SavedRouteOrigin,
    document: SharedRouteDocument
  ) {
    self.id = id
    self.displayName = displayName
    self.savedAt = savedAt
    self.origin = origin
    self.document = document
  }

  private enum CodingKeys: String, CodingKey {
    case id = "saved_route_id"
    case displayName = "display_name"
    case savedAt = "saved_at"
    case origin
    case document = "shared_route"
  }
}

/// The complete atomically persisted saved-route value.
public struct SavedRouteLibraryDocument: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = "1.0"

  public let schemaVersion: String
  public let records: [SavedRouteRecord]

  public init(
    schemaVersion: String = SavedRouteLibraryDocument.currentSchemaVersion,
    records: [SavedRouteRecord]
  ) {
    self.schemaVersion = schemaVersion
    self.records = records
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case records
  }
}

public enum SavedRouteLibraryIssue: Equatable, Sendable {
  case emptyRecordID
  case duplicateRecordID(String)
  case emptyDisplayName(String)
  case invalidSavedAt(String)
  case invalidSharedRoute(String)

  public var code: String {
    switch self {
    case .emptyRecordID:
      "SAVED_ROUTE_ID_EMPTY"
    case .duplicateRecordID:
      "SAVED_ROUTE_ID_DUPLICATE"
    case .emptyDisplayName:
      "SAVED_ROUTE_NAME_EMPTY"
    case .invalidSavedAt:
      "SAVED_ROUTE_SAVED_AT_INVALID"
    case .invalidSharedRoute:
      "SAVED_ROUTE_DOCUMENT_INVALID"
    }
  }

  fileprivate var sortKey: String {
    switch self {
    case .emptyRecordID:
      code
    case .duplicateRecordID(let id),
      .emptyDisplayName(let id),
      .invalidSavedAt(let id),
      .invalidSharedRoute(let id):
      "\(code):\(id)"
    }
  }
}

public enum SavedRouteLibraryCodecError: Error, Equatable, Sendable {
  case unsupportedSchemaVersion(String)
  case invalid([SavedRouteLibraryIssue])
}

public enum SavedRouteLibraryCodec {
  public static func encode(
    _ library: SavedRouteLibraryDocument
  ) throws -> Data {
    try validate(library)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(library)
  }

  public static func decode(
    _ data: Data
  ) throws -> SavedRouteLibraryDocument {
    let library = try JSONDecoder().decode(
      SavedRouteLibraryDocument.self,
      from: data
    )
    try validate(library)
    return library
  }

  public static func validate(
    _ library: SavedRouteLibraryDocument
  ) throws {
    guard
      library.schemaVersion
        == SavedRouteLibraryDocument.currentSchemaVersion
    else {
      throw SavedRouteLibraryCodecError.unsupportedSchemaVersion(
        library.schemaVersion
      )
    }

    var issues: [SavedRouteLibraryIssue] = []
    var recordIDs: Set<String> = []
    for record in library.records {
      let recordID = record.id.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      if recordID.isEmpty {
        issues.append(.emptyRecordID)
      } else if !recordIDs.insert(recordID).inserted {
        issues.append(.duplicateRecordID(recordID))
      }
      if record.displayName.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty {
        issues.append(.emptyDisplayName(recordID))
      }
      if !isISO8601DateTime(record.savedAt) {
        issues.append(.invalidSavedAt(recordID))
      }
      do {
        try SharedRouteCodec.validate(record.document)
      } catch {
        issues.append(.invalidSharedRoute(recordID))
      }
    }

    guard issues.isEmpty else {
      throw SavedRouteLibraryCodecError.invalid(
        sortedUnique(issues)
      )
    }
  }

  private static func isISO8601DateTime(_ value: String) -> Bool {
    for options: ISO8601DateFormatter.Options in [
      [.withInternetDateTime, .withFractionalSeconds],
      [.withInternetDateTime],
    ] {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = options
      if formatter.date(from: value) != nil {
        return true
      }
    }
    return false
  }

  private static func sortedUnique(
    _ issues: [SavedRouteLibraryIssue]
  ) -> [SavedRouteLibraryIssue] {
    var seen: Set<String> = []
    return issues.sorted { $0.sortKey < $1.sortKey }.filter {
      seen.insert($0.sortKey).inserted
    }
  }
}

/// One current, independently validated product release candidate.
///
/// Matching may use only full RoutePlan value equality. A plan ID, snapshot ID,
/// geometry, or destination alone is never sufficient.
public struct SavedRouteReleaseCandidate: Equatable, Sendable {
  public let releaseID: String
  public let routePlan: RoutePlan

  public init(releaseID: String, routePlan: RoutePlan) {
    self.releaseID = releaseID
    self.routePlan = routePlan
  }
}

public enum SavedRouteReleaseSelection: Equatable, Sendable {
  case unavailable
  case selected(String)
  case ambiguous([String])
}

public enum SavedRouteReleaseMatcherError: Error, Equatable, Sendable {
  case emptyCandidateReleaseID
  case duplicateCandidateReleaseID(String)
  case invalidCandidateRoutePlan(String)
}

/// Selects a current release for reopening one saved route.
///
/// This is selection only. It grants no runtime authority and does not mutate,
/// migrate, compile, or execute the saved RoutePlan.
public enum SavedRouteReleaseMatcher {
  public static func select(
    record: SavedRouteRecord,
    candidates: [SavedRouteReleaseCandidate]
  ) throws -> SavedRouteReleaseSelection {
    try SavedRouteLibraryCodec.validate(
      SavedRouteLibraryDocument(records: [record])
    )

    var seenReleaseIDs: Set<String> = []
    for candidate in candidates {
      let releaseID = candidate.releaseID.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      guard !releaseID.isEmpty else {
        throw SavedRouteReleaseMatcherError.emptyCandidateReleaseID
      }
      guard seenReleaseIDs.insert(releaseID).inserted else {
        throw
          SavedRouteReleaseMatcherError
          .duplicateCandidateReleaseID(releaseID)
      }
      do {
        try SharedRouteCodec.validate(
          SharedRouteDocument(
            evidenceState: .released,
            routePlan: candidate.routePlan
          )
        )
      } catch {
        throw
          SavedRouteReleaseMatcherError
          .invalidCandidateRoutePlan(releaseID)
      }
    }

    let matches =
      candidates
      .filter { $0.routePlan == record.document.routePlan }
      .map(\.releaseID)
      .sorted()
    switch matches.count {
    case 0:
      return .unavailable
    case 1:
      return .selected(matches[0])
    default:
      return .ambiguous(matches)
    }
  }
}
