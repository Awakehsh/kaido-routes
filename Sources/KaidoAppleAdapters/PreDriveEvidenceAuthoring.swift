import Foundation
import KaidoDomain
import KaidoNavigation
import KaidoPresentation

/// One reviewed tariff result before product-owned route and profile identity
/// are attached.
///
/// Entry, exit, vehicle class, and payment method are deliberately absent.
/// The author derives them from the exact product RoutePlan and enclosing
/// evidence record so a copied quote cannot drift those identities together.
public struct PreDriveTariffQuoteDraft:
  Codable, Equatable, Sendable
{
  public let id: String
  public let tariffVersionID: String
  public let tariffVersionStatus: TariffVersionStatus
  public let tariffDistanceKM: Double?
  public let estimatedAmountYen: Int?
  public let evidenceStatus: TollEvidenceStatus
  public let checkedAt: String
  public let officialQueryReference: String

  public init(
    id: String,
    tariffVersionID: String,
    tariffVersionStatus: TariffVersionStatus,
    tariffDistanceKM: Double?,
    estimatedAmountYen: Int?,
    evidenceStatus: TollEvidenceStatus,
    checkedAt: String,
    officialQueryReference: String
  ) {
    self.id = id
    self.tariffVersionID = tariffVersionID
    self.tariffVersionStatus = tariffVersionStatus
    self.tariffDistanceKM = tariffDistanceKM
    self.estimatedAmountYen = estimatedAmountYen
    self.evidenceStatus = evidenceStatus
    self.checkedAt = checkedAt
    self.officialQueryReference = officialQueryReference
  }

  private enum CodingKeys: String, CodingKey {
    case id = "quote_id"
    case tariffVersionID = "tariff_version_id"
    case tariffVersionStatus = "tariff_version_status"
    case tariffDistanceKM = "tariff_distance_km"
    case estimatedAmountYen = "estimated_amount_yen"
    case evidenceStatus = "status"
    case checkedAt = "checked_at"
    case officialQueryReference = "official_query_reference"
  }
}

/// Reviewed session evidence before RoutePlan identity is attached.
///
/// The vehicle and payment profile appears once here and is inherited by every
/// derived quote. Snapshot, RoutePlan, entrance, and exit identity come only
/// from the validated product release.
public struct PreDriveReviewEvidenceDraft:
  Codable, Equatable, Sendable
{
  public let evaluatedAt: String
  public let vehicleClass: ShutoVehicleClass
  public let paymentMethod: ShutoPaymentMethod
  public let passageEvidence: RoutePassageEvidence
  public let tariffQuotes: [PreDriveTariffQuoteDraft]

  public init(
    evaluatedAt: String,
    vehicleClass: ShutoVehicleClass,
    paymentMethod: ShutoPaymentMethod,
    passageEvidence: RoutePassageEvidence,
    tariffQuotes: [PreDriveTariffQuoteDraft]
  ) {
    self.evaluatedAt = evaluatedAt
    self.vehicleClass = vehicleClass
    self.paymentMethod = paymentMethod
    self.passageEvidence = passageEvidence
    self.tariffQuotes = tariffQuotes
  }

  private enum CodingKeys: String, CodingKey {
    case evaluatedAt = "evaluated_at"
    case vehicleClass = "vehicle_class"
    case paymentMethod = "payment_method"
    case passageEvidence = "passage_evidence"
    case tariffQuotes = "tariff_quotes"
  }
}

public struct PreDriveEvidenceRecordDraft:
  Codable, Equatable, Sendable
{
  public let id: String
  public let validFrom: String
  public let expiresAt: String
  public let sourceReferenceIDs: [String]
  public let evidence: PreDriveReviewEvidenceDraft

  public init(
    id: String,
    validFrom: String,
    expiresAt: String,
    sourceReferenceIDs: [String],
    evidence: PreDriveReviewEvidenceDraft
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

/// Reviewed current evidence before release metadata and product identity are
/// attached.
///
/// This draft has no product, navigation, snapshot, RoutePlan, entry, exit,
/// evidence-scope, release-ID, or release-time authority.
public struct PreDriveEvidenceBundleDraft:
  Codable, Equatable, Sendable
{
  public static let currentSchemaVersion = "1.0"

  public let schemaVersion: String
  public let sourceRegistry: [PreDriveEvidenceSourceReference]
  public let records: [PreDriveEvidenceRecordDraft]

  public init(
    schemaVersion: String =
      PreDriveEvidenceBundleDraft.currentSchemaVersion,
    sourceRegistry: [PreDriveEvidenceSourceReference],
    records: [PreDriveEvidenceRecordDraft]
  ) {
    self.schemaVersion = schemaVersion
    self.sourceRegistry = sourceRegistry
    self.records = records
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case sourceRegistry = "source_registry"
    case records
  }
}

/// Explicit release metadata for one reviewed evidence draft.
///
/// Evidence scope and every product-owned identity are not configurable. The
/// production author always derives a released-road manifest from one exact
/// foreground product.
public struct PreDriveEvidenceAuthoringConfiguration:
  Codable, Equatable, Sendable
{
  public static let currentSchemaVersion = "1.0"

  public let schemaVersion: String
  public let releaseID: String
  public let releasedAt: String

  public init(
    schemaVersion: String =
      PreDriveEvidenceAuthoringConfiguration.currentSchemaVersion,
    releaseID: String,
    releasedAt: String
  ) {
    self.schemaVersion = schemaVersion
    self.releaseID = releaseID
    self.releasedAt = releasedAt
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case releaseID = "release_id"
    case releasedAt = "released_at"
  }
}

public enum PreDriveEvidenceAuthoringIssue:
  Equatable, Sendable
{
  case invalidDraftSchemaVersion
  case invalidConfigurationSchemaVersion
  case invalidReleaseIdentity

  public var code: String {
    switch self {
    case .invalidDraftSchemaVersion:
      "PRE_DRIVE_EVIDENCE_DRAFT_SCHEMA_VERSION_INVALID"
    case .invalidConfigurationSchemaVersion:
      "PRE_DRIVE_EVIDENCE_AUTHORING_SCHEMA_VERSION_INVALID"
    case .invalidReleaseIdentity:
      "PRE_DRIVE_EVIDENCE_AUTHORING_RELEASE_IDENTITY_INVALID"
    }
  }
}

public enum PreDriveEvidenceAuthoringError:
  Error, Equatable, Sendable
{
  case foregroundProductRequired
  case invalidDraft([PreDriveEvidenceAuthoringIssue])
  case invalidConfiguration([PreDriveEvidenceAuthoringIssue])
  case invalidBundle([PreDriveEvidenceBundleIssue])
}

public enum PreDriveEvidenceBundleDraftCodec {
  public static func encode(
    _ draft: PreDriveEvidenceBundleDraft
  ) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(draft)
  }

  public static func decode(
    _ data: Data
  ) throws -> PreDriveEvidenceBundleDraft {
    try JSONDecoder().decode(
      PreDriveEvidenceBundleDraft.self,
      from: data
    )
  }
}

public enum PreDriveEvidenceAuthoringConfigurationCodec {
  public static func encode(
    _ configuration: PreDriveEvidenceAuthoringConfiguration
  ) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(configuration)
  }

  public static func decode(
    _ data: Data
  ) throws -> PreDriveEvidenceAuthoringConfiguration {
    try JSONDecoder().decode(
      PreDriveEvidenceAuthoringConfiguration.self,
      from: data
    )
  }
}

/// Builds one schema-current pre-drive evidence manifest from reviewed content.
///
/// The exact product supplies every route-owned identity, the record supplies
/// one tariff profile, and the author re-runs the whole bundle gate before
/// returning any manifest.
public enum PreDriveEvidenceBundleAuthor {
  public static func buildManifest(
    productRelease: KaidoProductRelease,
    draft: PreDriveEvidenceBundleDraft,
    configuration: PreDriveEvidenceAuthoringConfiguration
  ) throws -> PreDriveEvidenceBundleManifest {
    guard
      productRelease.runtimeUse.evidenceScope == .releasedRoad,
      productRelease.runtimeUse.liveInputPolicy == .foregroundWhenInUse,
      productRelease.foregroundLiveInputAuthority != nil
    else {
      throw PreDriveEvidenceAuthoringError.foregroundProductRequired
    }

    let draftIssues = validationIssues(draft)
    guard draftIssues.isEmpty else {
      throw PreDriveEvidenceAuthoringError.invalidDraft(draftIssues)
    }
    let configurationIssues = validationIssues(configuration)
    guard configurationIssues.isEmpty else {
      throw PreDriveEvidenceAuthoringError.invalidConfiguration(
        configurationIssues
      )
    }

    let routePlan = productRelease.navigation.bundle.routePlan
    let records = draft.records.map { record in
      let evidence = record.evidence
      return PreDriveEvidenceRecord(
        id: record.id,
        validFrom: record.validFrom,
        expiresAt: record.expiresAt,
        sourceReferenceIDs: record.sourceReferenceIDs,
        evidence: PreDriveReviewEvidence(
          evaluatedAt: evidence.evaluatedAt,
          networkSnapshotID: routePlan.networkSnapshotID,
          routePlanID: routePlan.id,
          vehicleClass: evidence.vehicleClass,
          paymentMethod: evidence.paymentMethod,
          passageEvidence: evidence.passageEvidence,
          tariffQuotes: evidence.tariffQuotes.map { quote in
            TariffQuote(
              id: quote.id,
              entryFacilityID: routePlan.entryFacilityID,
              exitFacilityID: routePlan.exitFacilityID,
              vehicleClass: evidence.vehicleClass,
              paymentMethod: evidence.paymentMethod,
              tariffVersionID: quote.tariffVersionID,
              tariffVersionStatus: quote.tariffVersionStatus,
              tariffDistanceKM: quote.tariffDistanceKM,
              estimatedAmountYen: quote.estimatedAmountYen,
              evidenceStatus: quote.evidenceStatus,
              checkedAt: quote.checkedAt,
              officialQueryReference: quote.officialQueryReference
            )
          }
        )
      )
    }
    let manifest = PreDriveEvidenceBundleManifest(
      releaseID: configuration.releaseID,
      releasedAt: configuration.releasedAt,
      evidenceScope: .releasedRoad,
      productReleaseID: productRelease.releaseID,
      navigationReleaseID: productRelease.navigation.releaseID,
      networkSnapshotID: routePlan.networkSnapshotID,
      routePlanID: routePlan.id,
      sourceRegistry: draft.sourceRegistry,
      records: records
    )
    do {
      _ = try PreDriveEvidenceBundle(
        manifest: manifest,
        context: PreDriveEvidenceBundleContext(
          productReleaseID: productRelease.releaseID,
          productReleasedAt: productRelease.releasedAt,
          navigationReleaseID: productRelease.navigation.releaseID,
          routePlan: routePlan,
          evidenceScope: .releasedRoad
        )
      )
    } catch PreDriveEvidenceBundleError.invalid(let issues) {
      throw PreDriveEvidenceAuthoringError.invalidBundle(issues)
    }
    return manifest
  }

  private static func validationIssues(
    _ draft: PreDriveEvidenceBundleDraft
  ) -> [PreDriveEvidenceAuthoringIssue] {
    guard
      draft.schemaVersion
        != PreDriveEvidenceBundleDraft.currentSchemaVersion
    else {
      return []
    }
    return [.invalidDraftSchemaVersion]
  }

  private static func validationIssues(
    _ configuration: PreDriveEvidenceAuthoringConfiguration
  ) -> [PreDriveEvidenceAuthoringIssue] {
    var issues: [PreDriveEvidenceAuthoringIssue] = []
    if configuration.schemaVersion
      != PreDriveEvidenceAuthoringConfiguration.currentSchemaVersion
    {
      issues.append(.invalidConfigurationSchemaVersion)
    }
    let normalizedReleaseID = configuration.releaseID
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if normalizedReleaseID.isEmpty
      || normalizedReleaseID != configuration.releaseID
      || !isISO8601DateTime(configuration.releasedAt)
    {
      issues.append(.invalidReleaseIdentity)
    }
    return issues
  }

  private static func isISO8601DateTime(_ value: String) -> Bool {
    let standard = ISO8601DateFormatter()
    if standard.date(from: value) != nil {
      return true
    }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [
      .withInternetDateTime,
      .withFractionalSeconds,
    ]
    return fractional.date(from: value) != nil
  }
}
