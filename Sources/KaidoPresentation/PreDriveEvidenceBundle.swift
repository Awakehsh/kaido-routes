import Foundation
import KaidoDomain

/// The authority boundary of one dated pre-drive evidence bundle.
///
/// Synthetic fixtures can execute the same validation contract, but only a
/// released-road bundle may be enrolled beside a foreground product release.
public enum PreDriveEvidenceScope: String, Codable, Equatable, Sendable {
  case syntheticTestOnly = "SYNTHETIC_TEST_ONLY"
  case releasedRoad = "RELEASED_ROAD"
}

public enum PreDriveEvidenceSourceRole:
  String, Codable, CaseIterable, Equatable, Sendable
{
  case tariffQuery = "TARIFF_QUERY"
  case passageReview = "PASSAGE_REVIEW"
}

public struct PreDriveEvidenceSourceReference:
  Codable, Equatable, Sendable
{
  public let id: String
  public let roles: [PreDriveEvidenceSourceRole]
  public let authorityName: String
  public let sourceURL: String
  public let contentSHA256: String
  public let checkedAt: String
  public let reviewerID: String
  public let reviewedAt: String

  public init(
    id: String,
    roles: [PreDriveEvidenceSourceRole],
    authorityName: String,
    sourceURL: String,
    contentSHA256: String,
    checkedAt: String,
    reviewerID: String,
    reviewedAt: String
  ) {
    self.id = id
    self.roles = roles
    self.authorityName = authorityName
    self.sourceURL = sourceURL
    self.contentSHA256 = contentSHA256
    self.checkedAt = checkedAt
    self.reviewerID = reviewerID
    self.reviewedAt = reviewedAt
  }

  private enum CodingKeys: String, CodingKey {
    case id = "source_reference_id"
    case roles
    case authorityName = "authority_name"
    case sourceURL = "source_url"
    case contentSHA256 = "content_sha256"
    case checkedAt = "checked_at"
    case reviewerID = "reviewer_id"
    case reviewedAt = "reviewed_at"
  }
}

public struct PreDriveEvidenceRecord: Codable, Equatable, Sendable {
  public let id: String
  public let validFrom: String
  public let expiresAt: String
  public let sourceReferenceIDs: [String]
  public let evidence: PreDriveReviewEvidence

  public init(
    id: String,
    validFrom: String,
    expiresAt: String,
    sourceReferenceIDs: [String],
    evidence: PreDriveReviewEvidence
  ) {
    self.id = id
    self.validFrom = validFrom
    self.expiresAt = expiresAt
    self.sourceReferenceIDs = sourceReferenceIDs
    self.evidence = evidence
  }

  private enum CodingKeys: String, CodingKey {
    case id = "record_id"
    case validFrom = "valid_from"
    case expiresAt = "expires_at"
    case sourceReferenceIDs = "source_reference_ids"
    case evidence
  }
}

/// A hash-pinnable set of current session evidence for one exact product route.
///
/// This is deliberately separate from the versioned product release. It may be
/// replaced on a later App release without changing RoutePlan authority, and
/// every record expires independently at runtime.
public struct PreDriveEvidenceBundleManifest:
  Codable, Equatable, Sendable
{
  public static let currentSchemaVersion = "1.0"

  public let schemaVersion: String
  public let releaseID: String
  public let releasedAt: String
  public let evidenceScope: PreDriveEvidenceScope
  public let productReleaseID: String
  public let navigationReleaseID: String
  public let networkSnapshotID: String
  public let routePlanID: String
  public let sourceRegistry: [PreDriveEvidenceSourceReference]
  public let records: [PreDriveEvidenceRecord]

  public init(
    schemaVersion: String = PreDriveEvidenceBundleManifest.currentSchemaVersion,
    releaseID: String,
    releasedAt: String,
    evidenceScope: PreDriveEvidenceScope,
    productReleaseID: String,
    navigationReleaseID: String,
    networkSnapshotID: String,
    routePlanID: String,
    sourceRegistry: [PreDriveEvidenceSourceReference],
    records: [PreDriveEvidenceRecord]
  ) {
    self.schemaVersion = schemaVersion
    self.releaseID = releaseID
    self.releasedAt = releasedAt
    self.evidenceScope = evidenceScope
    self.productReleaseID = productReleaseID
    self.navigationReleaseID = navigationReleaseID
    self.networkSnapshotID = networkSnapshotID
    self.routePlanID = routePlanID
    self.sourceRegistry = sourceRegistry
    self.records = records
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case releaseID = "release_id"
    case releasedAt = "released_at"
    case evidenceScope = "evidence_scope"
    case productReleaseID = "product_release_id"
    case navigationReleaseID = "navigation_release_id"
    case networkSnapshotID = "network_snapshot_id"
    case routePlanID = "route_plan_id"
    case sourceRegistry = "source_registry"
    case records
  }
}

public struct PreDriveEvidenceBundleContext: Equatable, Sendable {
  public let productReleaseID: String
  public let productReleasedAt: String
  public let navigationReleaseID: String
  public let routePlan: RoutePlan
  public let evidenceScope: PreDriveEvidenceScope

  public init(
    productReleaseID: String,
    productReleasedAt: String,
    navigationReleaseID: String,
    routePlan: RoutePlan,
    evidenceScope: PreDriveEvidenceScope
  ) {
    self.productReleaseID = productReleaseID
    self.productReleasedAt = productReleasedAt
    self.navigationReleaseID = navigationReleaseID
    self.routePlan = routePlan
    self.evidenceScope = evidenceScope
  }
}

public struct PreDriveEvidenceProfileKey:
  Hashable, Equatable, Sendable
{
  public let vehicleClass: ShutoVehicleClass
  public let paymentMethod: ShutoPaymentMethod

  public init(
    vehicleClass: ShutoVehicleClass,
    paymentMethod: ShutoPaymentMethod
  ) {
    self.vehicleClass = vehicleClass
    self.paymentMethod = paymentMethod
  }
}

public enum PreDriveEvidenceBundleIssue: Equatable, Sendable {
  case invalidSchemaVersion
  case invalidReleaseIdentity
  case evidenceScopeMismatch
  case productReleaseMismatch
  case evidenceBeforeProductRelease
  case navigationReleaseMismatch
  case networkSnapshotMismatch
  case routePlanMismatch
  case missingRecords
  case duplicateSourceReference(String)
  case invalidSourceReference(String)
  case orphanSourceReference(String)
  case duplicateRecord(String)
  case duplicateProfile(PreDriveEvidenceProfileKey)
  case invalidRecord(String)
  case missingSourceReference(String)
  case missingSourceRole(String, PreDriveEvidenceSourceRole)
  case invalidEvidence(String, String)

  public var code: String {
    switch self {
    case .invalidSchemaVersion:
      "PRE_DRIVE_EVIDENCE_SCHEMA_VERSION_INVALID"
    case .invalidReleaseIdentity:
      "PRE_DRIVE_EVIDENCE_RELEASE_IDENTITY_INVALID"
    case .evidenceScopeMismatch:
      "PRE_DRIVE_EVIDENCE_SCOPE_MISMATCH"
    case .productReleaseMismatch:
      "PRE_DRIVE_EVIDENCE_PRODUCT_RELEASE_MISMATCH"
    case .evidenceBeforeProductRelease:
      "PRE_DRIVE_EVIDENCE_BEFORE_PRODUCT_RELEASE"
    case .navigationReleaseMismatch:
      "PRE_DRIVE_EVIDENCE_NAVIGATION_RELEASE_MISMATCH"
    case .networkSnapshotMismatch:
      "PRE_DRIVE_EVIDENCE_NETWORK_SNAPSHOT_MISMATCH"
    case .routePlanMismatch:
      "PRE_DRIVE_EVIDENCE_ROUTE_PLAN_MISMATCH"
    case .missingRecords:
      "PRE_DRIVE_EVIDENCE_RECORDS_MISSING"
    case .duplicateSourceReference:
      "PRE_DRIVE_EVIDENCE_SOURCE_DUPLICATE"
    case .invalidSourceReference:
      "PRE_DRIVE_EVIDENCE_SOURCE_INVALID"
    case .orphanSourceReference:
      "PRE_DRIVE_EVIDENCE_SOURCE_ORPHANED"
    case .duplicateRecord:
      "PRE_DRIVE_EVIDENCE_RECORD_DUPLICATE"
    case .duplicateProfile:
      "PRE_DRIVE_EVIDENCE_PROFILE_DUPLICATE"
    case .invalidRecord:
      "PRE_DRIVE_EVIDENCE_RECORD_INVALID"
    case .missingSourceReference:
      "PRE_DRIVE_EVIDENCE_SOURCE_MISSING"
    case .missingSourceRole(_, let role):
      switch role {
      case .tariffQuery:
        "PRE_DRIVE_EVIDENCE_TARIFF_SOURCE_MISSING"
      case .passageReview:
        "PRE_DRIVE_EVIDENCE_PASSAGE_SOURCE_MISSING"
      }
    case .invalidEvidence:
      "PRE_DRIVE_EVIDENCE_EVALUATION_INVALID"
    }
  }

  fileprivate var sortKey: String {
    switch self {
    case .duplicateSourceReference(let id),
      .invalidSourceReference(let id),
      .orphanSourceReference(let id),
      .duplicateRecord(let id),
      .invalidRecord(let id),
      .missingSourceReference(let id):
      "\(code):\(id)"
    case .duplicateProfile(let profile):
      "\(code):\(profile.vehicleClass.rawValue):\(profile.paymentMethod.rawValue)"
    case .missingSourceRole(let recordID, let role):
      "\(code):\(recordID):\(role.rawValue)"
    case .invalidEvidence(let recordID, let detail):
      "\(code):\(recordID):\(detail)"
    default:
      code
    }
  }
}

public enum PreDriveEvidenceBundleError: Error, Equatable, Sendable {
  case invalid([PreDriveEvidenceBundleIssue])
}

public enum PreDriveEvidenceResolutionError:
  Error, Equatable, Sendable
{
  case routeIdentityMismatch
  case profileUnavailable
  case notYetValid
  case expired

  public var code: String {
    switch self {
    case .routeIdentityMismatch:
      "PRE_DRIVE_EVIDENCE_ROUTE_IDENTITY_MISMATCH"
    case .profileUnavailable:
      "PRE_DRIVE_EVIDENCE_PROFILE_UNAVAILABLE"
    case .notYetValid:
      "PRE_DRIVE_EVIDENCE_NOT_YET_VALID"
    case .expired:
      "PRE_DRIVE_EVIDENCE_EXPIRED"
    }
  }
}

public struct PreDriveEvidenceBundle: Equatable, Sendable {
  public let manifest: PreDriveEvidenceBundleManifest
  private let recordsByProfile: [PreDriveEvidenceProfileKey: PreDriveEvidenceRecord]

  public init(
    manifest: PreDriveEvidenceBundleManifest,
    context: PreDriveEvidenceBundleContext
  ) throws {
    var issues: [PreDriveEvidenceBundleIssue] = []

    if manifest.schemaVersion
      != PreDriveEvidenceBundleManifest.currentSchemaVersion
    {
      issues.append(.invalidSchemaVersion)
    }
    guard
      !Self.normalized(manifest.releaseID).isEmpty,
      manifest.releaseID == Self.normalized(manifest.releaseID),
      let releasedAt = Self.parseISO8601(manifest.releasedAt)
    else {
      issues.append(.invalidReleaseIdentity)
      throw PreDriveEvidenceBundleError.invalid(Self.sortedUnique(issues))
    }
    if manifest.evidenceScope != context.evidenceScope {
      issues.append(.evidenceScopeMismatch)
    }
    if manifest.productReleaseID != context.productReleaseID {
      issues.append(.productReleaseMismatch)
    }
    if let productReleasedAt = Self.parseISO8601(
      context.productReleasedAt
    ) {
      if releasedAt < productReleasedAt {
        issues.append(.evidenceBeforeProductRelease)
      }
    } else {
      issues.append(.invalidReleaseIdentity)
    }
    if manifest.navigationReleaseID != context.navigationReleaseID {
      issues.append(.navigationReleaseMismatch)
    }
    if manifest.networkSnapshotID != context.routePlan.networkSnapshotID {
      issues.append(.networkSnapshotMismatch)
    }
    if manifest.routePlanID != context.routePlan.id {
      issues.append(.routePlanMismatch)
    }

    var sourcesByID: [String: PreDriveEvidenceSourceReference] = [:]
    for source in manifest.sourceRegistry {
      if sourcesByID[source.id] != nil {
        issues.append(.duplicateSourceReference(source.id))
        continue
      }
      sourcesByID[source.id] = source
      if !Self.isValid(source, noLaterThan: releasedAt) {
        issues.append(.invalidSourceReference(source.id))
      }
    }

    var seenRecordIDs: Set<String> = []
    var recordsByProfile: [PreDriveEvidenceProfileKey: PreDriveEvidenceRecord] = [:]
    var referencedSourceIDs: Set<String> = []

    for record in manifest.records {
      if !seenRecordIDs.insert(record.id).inserted {
        issues.append(.duplicateRecord(record.id))
      }
      let profile = PreDriveEvidenceProfileKey(
        vehicleClass: record.evidence.vehicleClass,
        paymentMethod: record.evidence.paymentMethod
      )
      if recordsByProfile[profile] != nil {
        issues.append(.duplicateProfile(profile))
      } else {
        recordsByProfile[profile] = record
      }

      guard
        Self.isValid(record, releasedAt: releasedAt),
        let evaluatedAt = Self.parseISO8601(record.evidence.evaluatedAt)
      else {
        issues.append(.invalidRecord(record.id))
        continue
      }

      var roles: Set<PreDriveEvidenceSourceRole> = []
      var seenRecordSourceIDs: Set<String> = []
      for sourceID in record.sourceReferenceIDs {
        guard seenRecordSourceIDs.insert(sourceID).inserted else {
          issues.append(.invalidRecord(record.id))
          continue
        }
        referencedSourceIDs.insert(sourceID)
        guard let source = sourcesByID[sourceID] else {
          issues.append(.missingSourceReference(sourceID))
          continue
        }
        roles.formUnion(source.roles)
        if let checkedAt = Self.parseISO8601(source.checkedAt),
          checkedAt > evaluatedAt
        {
          issues.append(.invalidRecord(record.id))
        }
      }
      for role in PreDriveEvidenceSourceRole.allCases
      where !roles.contains(role) {
        issues.append(.missingSourceRole(record.id, role))
      }

      do {
        _ = try PreDriveReviewEvaluator.evaluate(
          routePlan: context.routePlan,
          session: PreDriveReviewSession(
            networkSnapshotID: record.evidence.networkSnapshotID,
            routePlanID: record.evidence.routePlanID,
            vehicleClass: record.evidence.vehicleClass,
            paymentMethod: record.evidence.paymentMethod
          ),
          evidence: record.evidence
        )
      } catch let error as PreDriveReviewEvaluationError {
        issues.append(.invalidEvidence(record.id, error.code))
      } catch {
        issues.append(.invalidEvidence(record.id, "UNKNOWN"))
      }
    }

    if manifest.records.isEmpty {
      issues.append(.missingRecords)
    }
    for sourceID in sourcesByID.keys
    where !referencedSourceIDs.contains(sourceID) {
      issues.append(.orphanSourceReference(sourceID))
    }

    issues = Self.sortedUnique(issues)
    guard issues.isEmpty else {
      throw PreDriveEvidenceBundleError.invalid(issues)
    }
    self.manifest = manifest
    self.recordsByProfile = recordsByProfile
  }

  public func evidence(
    for session: PreDriveReviewSession,
    at date: Date
  ) throws -> PreDriveReviewEvidence {
    guard
      session.networkSnapshotID == manifest.networkSnapshotID,
      session.routePlanID == manifest.routePlanID
    else {
      throw PreDriveEvidenceResolutionError.routeIdentityMismatch
    }
    let profile = PreDriveEvidenceProfileKey(
      vehicleClass: session.vehicleClass,
      paymentMethod: session.paymentMethod
    )
    guard let record = recordsByProfile[profile] else {
      throw PreDriveEvidenceResolutionError.profileUnavailable
    }
    guard
      let validFrom = Self.parseISO8601(record.validFrom),
      let expiresAt = Self.parseISO8601(record.expiresAt),
      let releasedAt = Self.parseISO8601(manifest.releasedAt)
    else {
      throw PreDriveEvidenceResolutionError.profileUnavailable
    }
    guard date >= validFrom, date >= releasedAt else {
      throw PreDriveEvidenceResolutionError.notYetValid
    }
    guard date < expiresAt else {
      throw PreDriveEvidenceResolutionError.expired
    }
    return record.evidence
  }

  private static func isValid(
    _ source: PreDriveEvidenceSourceReference,
    noLaterThan releasedAt: Date
  ) -> Bool {
    let required = [
      source.id,
      source.authorityName,
      source.sourceURL,
      source.reviewerID,
    ]
    guard
      required.allSatisfy({
        !$0.isEmpty && $0 == normalized($0)
      }),
      !source.roles.isEmpty,
      Set(source.roles).count == source.roles.count,
      isSHA256(source.contentSHA256),
      let url = URL(string: source.sourceURL),
      url.scheme?.lowercased() == "https",
      url.host != nil,
      let checkedAt = parseISO8601(source.checkedAt),
      let reviewedAt = parseISO8601(source.reviewedAt),
      checkedAt <= reviewedAt,
      reviewedAt <= releasedAt
    else {
      return false
    }
    return true
  }

  private static func isValid(
    _ record: PreDriveEvidenceRecord,
    releasedAt: Date
  ) -> Bool {
    guard
      !normalized(record.id).isEmpty,
      record.id == normalized(record.id),
      !record.sourceReferenceIDs.isEmpty,
      let evaluatedAt = parseISO8601(record.evidence.evaluatedAt),
      let validFrom = parseISO8601(record.validFrom),
      let expiresAt = parseISO8601(record.expiresAt),
      evaluatedAt <= validFrom,
      validFrom <= releasedAt,
      releasedAt < expiresAt
    else {
      return false
    }
    return true
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func isSHA256(_ value: String) -> Bool {
    let digest = value.lowercased()
    return digest.count == 64
      && digest.allSatisfy {
        ("0"..."9").contains($0) || ("a"..."f").contains($0)
      }
  }

  private static func parseISO8601(_ value: String) -> Date? {
    let standard = ISO8601DateFormatter()
    if let result = standard.date(from: value) {
      return result
    }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value)
  }

  private static func sortedUnique(
    _ issues: [PreDriveEvidenceBundleIssue]
  ) -> [PreDriveEvidenceBundleIssue] {
    var result: [PreDriveEvidenceBundleIssue] = []
    for issue in issues.sorted(by: { $0.sortKey < $1.sortKey })
    where !result.contains(issue) {
      result.append(issue)
    }
    return result
  }
}

public enum PreDriveEvidenceBundleCodec {
  public static func encode(
    _ manifest: PreDriveEvidenceBundleManifest,
    context: PreDriveEvidenceBundleContext
  ) throws -> Data {
    _ = try PreDriveEvidenceBundle(
      manifest: manifest,
      context: context
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(manifest)
  }

  public static func decode(
    _ data: Data,
    context: PreDriveEvidenceBundleContext
  ) throws -> PreDriveEvidenceBundle {
    let manifest = try JSONDecoder().decode(
      PreDriveEvidenceBundleManifest.self,
      from: data
    )
    return try PreDriveEvidenceBundle(
      manifest: manifest,
      context: context
    )
  }
}
