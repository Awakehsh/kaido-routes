import Foundation

public enum SharedRouteEvidenceState: String, Codable, Sendable {
  case communityCandidate = "COMMUNITY_CANDIDATE"
  case officialChecked = "OFFICIAL_CHECKED"
  case fieldChecked = "FIELD_CHECKED"
  case released = "RELEASED"
  case staleReviewRequired = "STALE_REVIEW_REQUIRED"
}

public struct SharedRouteDocument: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = "1.0"

  public let schemaVersion: String
  public let evidenceState: SharedRouteEvidenceState
  public let templateParameters: [String: String]
  public let routePlan: RoutePlan

  public init(
    schemaVersion: String = SharedRouteDocument.currentSchemaVersion,
    evidenceState: SharedRouteEvidenceState,
    templateParameters: [String: String] = [:],
    routePlan: RoutePlan
  ) {
    self.schemaVersion = schemaVersion
    self.evidenceState = evidenceState
    self.templateParameters = templateParameters
    self.routePlan = routePlan
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case evidenceState = "evidence_state"
    case templateParameters = "template_parameters"
    case routePlan = "route_plan"
  }
}

public enum SharedRouteCodecError: Error, Equatable, Sendable {
  case unsupportedSchemaVersion(String)
  case invalidDocument([String])
}

public enum SharedRouteCodec {
  public static func encode(_ document: SharedRouteDocument) throws -> Data {
    try validate(document)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(document)
  }

  public static func decode(_ data: Data) throws -> SharedRouteDocument {
    let document = try JSONDecoder().decode(SharedRouteDocument.self, from: data)
    try validate(document)
    return document
  }

  public static func validate(_ document: SharedRouteDocument) throws {
    guard document.schemaVersion == SharedRouteDocument.currentSchemaVersion else {
      throw SharedRouteCodecError.unsupportedSchemaVersion(document.schemaVersion)
    }

    let plan = document.routePlan
    var errors: [String] = []
    if plan.id.isEmpty { errors.append("EMPTY_PLAN_ID") }
    if plan.networkSnapshotID.isEmpty { errors.append("EMPTY_NETWORK_SNAPSHOT_ID") }
    if plan.entryFacilityID.isEmpty { errors.append("EMPTY_ENTRY_FACILITY_ID") }
    if plan.exitFacilityID.isEmpty { errors.append("EMPTY_EXIT_FACILITY_ID") }
    if plan.occurrences.isEmpty { errors.append("EMPTY_ROUTE_OCCURRENCES") }

    let occurrenceIDs = plan.occurrences.map(\.id)
    if occurrenceIDs.contains(where: \.isEmpty) {
      errors.append("EMPTY_OCCURRENCE_ID")
    }
    if Set(occurrenceIDs).count != occurrenceIDs.count {
      errors.append("DUPLICATE_OCCURRENCE_ID")
    }
    if !plan.occurrences.enumerated().allSatisfy({ offset, occurrence in
      occurrence.index == offset
    }) {
      errors.append("NONCONTIGUOUS_OCCURRENCE_INDEX")
    }
    if plan.occurrences.contains(where: { $0.entityID.isEmpty }) {
      errors.append("EMPTY_OCCURRENCE_ENTITY_ID")
    }
    if document.templateParameters.contains(where: { key, value in
      key.isEmpty || value.isEmpty
    }) {
      errors.append("EMPTY_TEMPLATE_PARAMETER")
    }

    guard errors.isEmpty else {
      throw SharedRouteCodecError.invalidDocument(errors)
    }
  }
}
