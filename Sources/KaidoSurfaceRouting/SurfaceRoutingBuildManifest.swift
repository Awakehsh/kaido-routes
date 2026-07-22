import Foundation

public enum SurfaceRoutingBuildSourceRole: String, Codable, Sendable {
  case roadNetwork = "ROAD_NETWORK"
  case administration = "ADMINISTRATION"
  case timeZone = "TIME_ZONE"
}

public struct SurfaceRoutingBuildSource: Codable, Equatable, Sendable {
  public let id: String
  public let roles: [SurfaceRoutingBuildSourceRole]
  public let snapshotAt: String
  public let uri: String
  public let sha256: String
  public let byteCount: Int64
  public let licence: String
  public let attribution: String

  public init(
    id: String,
    roles: [SurfaceRoutingBuildSourceRole],
    snapshotAt: String,
    uri: String,
    sha256: String,
    byteCount: Int64,
    licence: String,
    attribution: String
  ) {
    self.id = id
    self.roles = roles
    self.snapshotAt = snapshotAt
    self.uri = uri
    self.sha256 = sha256
    self.byteCount = byteCount
    self.licence = licence
    self.attribution = attribution
  }

  private enum CodingKeys: String, CodingKey {
    case id = "source_id"
    case roles
    case snapshotAt = "snapshot_at"
    case uri
    case sha256
    case byteCount = "byte_count"
    case licence
    case attribution
  }
}

public enum SurfaceRoutingBuildArtifactRole: String, Codable, Sendable {
  case providerConfiguration = "PROVIDER_CONFIGURATION"
  case engineBinary = "ENGINE_BINARY"
  case routingTiles = "ROUTING_TILES"
  case administrationDatabase = "ADMINISTRATION_DATABASE"
  case timeZoneDatabase = "TIME_ZONE_DATABASE"
  case kaidoDirectedGraph = "KAIDO_DIRECTED_GRAPH"
}

public enum SurfaceRoutingSelectedPathIdentity: String, Codable, Sendable {
  case osmNodePath = "OSM_NODE_PATH"
  case osmWayPointPairs = "OSM_WAY_POINT_PAIRS"
}

public struct SurfaceRoutingBuildArtifact: Codable, Equatable, Sendable {
  public let id: String
  public let role: SurfaceRoutingBuildArtifactRole
  public let relativePath: String
  public let format: String
  public let sha256: String
  public let byteCount: Int64

  public init(
    id: String,
    role: SurfaceRoutingBuildArtifactRole,
    relativePath: String,
    format: String,
    sha256: String,
    byteCount: Int64
  ) {
    self.id = id
    self.role = role
    self.relativePath = relativePath
    self.format = format
    self.sha256 = sha256
    self.byteCount = byteCount
  }

  private enum CodingKeys: String, CodingKey {
    case id = "artifact_id"
    case role
    case relativePath = "relative_path"
    case format
    case sha256
    case byteCount = "byte_count"
  }
}

public struct SurfaceRoutingEngineBuild: Codable, Equatable, Sendable {
  public let id: String
  public let providerID: String
  public let providerVersion: String
  public let containerImage: String
  public let containerDigest: String

  public init(
    id: String,
    providerID: String,
    providerVersion: String,
    containerImage: String,
    containerDigest: String
  ) {
    self.id = id
    self.providerID = providerID
    self.providerVersion = providerVersion
    self.containerImage = containerImage
    self.containerDigest = containerDigest
  }

  private enum CodingKeys: String, CodingKey {
    case id = "build_id"
    case providerID = "provider_id"
    case providerVersion = "provider_version"
    case containerImage = "container_image"
    case containerDigest = "container_digest"
  }
}

public struct SurfaceRoutingBuildCapabilities: Codable, Equatable, Sendable {
  public let includesAdministrativeData: Bool
  public let includesTimeZoneData: Bool
  public let keepsAllOSMNodeIDs: Bool
  public let selectedPathIdentity: SurfaceRoutingSelectedPathIdentity?

  public init(
    includesAdministrativeData: Bool,
    includesTimeZoneData: Bool,
    keepsAllOSMNodeIDs: Bool,
    selectedPathIdentity: SurfaceRoutingSelectedPathIdentity? = nil
  ) {
    self.includesAdministrativeData = includesAdministrativeData
    self.includesTimeZoneData = includesTimeZoneData
    self.keepsAllOSMNodeIDs = keepsAllOSMNodeIDs
    self.selectedPathIdentity = selectedPathIdentity
  }

  private enum CodingKeys: String, CodingKey {
    case includesAdministrativeData = "includes_administrative_data"
    case includesTimeZoneData = "includes_time_zone_data"
    case keepsAllOSMNodeIDs = "keeps_all_osm_node_ids"
    case selectedPathIdentity = "selected_path_identity"
  }
}

/// One self-hosted provider observation proving its administrative lookup.
///
/// The check records observed values rather than build intent. The evidence
/// checksum binds the observation to a retained local response without
/// requiring that raw provider output be committed to this repository.
public struct SurfaceRoutingAdminVerification: Codable, Equatable, Sendable {
  public let id: String
  public let coordinate: SurfaceCoordinate
  public let expectedRegionCode: String
  public let observedCountryCode: String
  public let observedStateCode: String
  public let driveOnRight: Bool
  public let checkedAt: String
  public let evidenceSHA256: String

  public init(
    id: String,
    coordinate: SurfaceCoordinate,
    expectedRegionCode: String,
    observedCountryCode: String,
    observedStateCode: String,
    driveOnRight: Bool,
    checkedAt: String,
    evidenceSHA256: String
  ) {
    self.id = id
    self.coordinate = coordinate
    self.expectedRegionCode = expectedRegionCode
    self.observedCountryCode = observedCountryCode
    self.observedStateCode = observedStateCode
    self.driveOnRight = driveOnRight
    self.checkedAt = checkedAt
    self.evidenceSHA256 = evidenceSHA256
  }

  private enum CodingKeys: String, CodingKey {
    case id = "check_id"
    case coordinate
    case expectedRegionCode = "expected_region_code"
    case observedCountryCode = "observed_country_code"
    case observedStateCode = "observed_state_code"
    case driveOnRight = "drive_on_right"
    case checkedAt = "checked_at"
    case evidenceSHA256 = "evidence_sha256"
  }
}

public enum SurfaceRoutingBuildIntendedUse: String, Codable, Sendable {
  case labOnly = "LAB_ONLY"
  case releaseCandidate = "RELEASE_CANDIDATE"
}

/// Reproducible identity for one bounded surface-routing engine build.
///
/// The manifest contains metadata and checksums only. It does not grant a right
/// to redistribute the source data or generated routing databases.
public struct SurfaceRoutingBuildManifest: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = "1.0.0"

  public let schemaVersion: String
  public let id: String
  public let createdAt: String
  public let intendedUse: SurfaceRoutingBuildIntendedUse
  public let networkSnapshotID: String
  public let providerDatasetID: String
  public let engineBuild: SurfaceRoutingEngineBuild
  public let sources: [SurfaceRoutingBuildSource]
  public let artifacts: [SurfaceRoutingBuildArtifact]
  public let capabilities: SurfaceRoutingBuildCapabilities
  public let adminVerifications: [SurfaceRoutingAdminVerification]
  public let releaseBlockers: [String]

  public init(
    schemaVersion: String = SurfaceRoutingBuildManifest.currentSchemaVersion,
    id: String,
    createdAt: String,
    intendedUse: SurfaceRoutingBuildIntendedUse,
    networkSnapshotID: String,
    providerDatasetID: String,
    engineBuild: SurfaceRoutingEngineBuild,
    sources: [SurfaceRoutingBuildSource],
    artifacts: [SurfaceRoutingBuildArtifact],
    capabilities: SurfaceRoutingBuildCapabilities,
    adminVerifications: [SurfaceRoutingAdminVerification],
    releaseBlockers: [String]
  ) {
    self.schemaVersion = schemaVersion
    self.id = id
    self.createdAt = createdAt
    self.intendedUse = intendedUse
    self.networkSnapshotID = networkSnapshotID
    self.providerDatasetID = providerDatasetID
    self.engineBuild = engineBuild
    self.sources = sources
    self.artifacts = artifacts
    self.capabilities = capabilities
    self.adminVerifications = adminVerifications
    self.releaseBlockers = releaseBlockers
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case id = "manifest_id"
    case createdAt = "created_at"
    case intendedUse = "intended_use"
    case networkSnapshotID = "network_snapshot_id"
    case providerDatasetID = "provider_dataset_id"
    case engineBuild = "engine_build"
    case sources
    case artifacts
    case capabilities
    case adminVerifications = "admin_verifications"
    case releaseBlockers = "release_blockers"
  }
}

public enum SurfaceRoutingManifestValidationProfile: String, Codable, Sendable {
  case structural = "STRUCTURAL"
  case releaseCandidate = "RELEASE_CANDIDATE"
}

public enum SurfaceRoutingManifestValidationIssueCode: String, Codable, Sendable {
  case unsupportedSchemaVersion = "UNSUPPORTED_SCHEMA_VERSION"
  case invalidIdentity = "INVALID_IDENTITY"
  case invalidTimestamp = "INVALID_TIMESTAMP"
  case invalidChecksum = "INVALID_CHECKSUM"
  case invalidByteCount = "INVALID_BYTE_COUNT"
  case invalidRelativePath = "INVALID_RELATIVE_PATH"
  case invalidSource = "INVALID_SOURCE"
  case invalidArtifact = "INVALID_ARTIFACT"
  case duplicateSourceID = "DUPLICATE_SOURCE_ID"
  case duplicateArtifactID = "DUPLICATE_ARTIFACT_ID"
  case duplicateArtifactRole = "DUPLICATE_ARTIFACT_ROLE"
  case graphSnapshotMismatch = "GRAPH_SNAPSHOT_MISMATCH"
  case providerDatasetMismatch = "PROVIDER_DATASET_MISMATCH"
  case wrongIntendedUse = "WRONG_INTENDED_USE"
  case missingSourceRole = "MISSING_SOURCE_ROLE"
  case missingArtifactRole = "MISSING_ARTIFACT_ROLE"
  case missingCapability = "MISSING_CAPABILITY"
  case invalidAdminVerification = "INVALID_ADMIN_VERIFICATION"
  case missingTokyoLeftDrivingVerification = "MISSING_TOKYO_LEFT_DRIVING_VERIFICATION"
  case releaseBlocker = "RELEASE_BLOCKER"
}

public struct SurfaceRoutingManifestValidationIssue: Codable, Equatable, Sendable {
  public let code: SurfaceRoutingManifestValidationIssueCode
  public let path: String
  public let message: String

  public init(
    code: SurfaceRoutingManifestValidationIssueCode,
    path: String,
    message: String
  ) {
    self.code = code
    self.path = path
    self.message = message
  }
}

public struct SurfaceRoutingManifestValidationReport: Codable, Equatable, Sendable {
  public let profile: SurfaceRoutingManifestValidationProfile
  public let isValid: Bool
  public let issues: [SurfaceRoutingManifestValidationIssue]

  public init(
    profile: SurfaceRoutingManifestValidationProfile,
    issues: [SurfaceRoutingManifestValidationIssue]
  ) {
    self.profile = profile
    self.isValid = issues.isEmpty
    self.issues = issues
  }

  private enum CodingKeys: String, CodingKey {
    case profile
    case isValid = "is_valid"
    case issues
  }
}

/// Validates manifest identity before an engine build can supply path evidence.
public enum SurfaceRoutingBuildManifestValidator {
  public static func validate(
    _ manifest: SurfaceRoutingBuildManifest,
    graph: SurfaceRoadGraphSnapshot,
    profile: SurfaceRoutingManifestValidationProfile
  ) -> SurfaceRoutingManifestValidationReport {
    var issues: [SurfaceRoutingManifestValidationIssue] = []

    func issue(
      _ code: SurfaceRoutingManifestValidationIssueCode,
      _ path: String,
      _ message: String
    ) {
      issues.append(.init(code: code, path: path, message: message))
    }

    if manifest.schemaVersion != SurfaceRoutingBuildManifest.currentSchemaVersion {
      issue(
        .unsupportedSchemaVersion,
        "schema_version",
        "expected \(SurfaceRoutingBuildManifest.currentSchemaVersion)"
      )
    }
    for (path, value) in [
      ("manifest_id", manifest.id),
      ("network_snapshot_id", manifest.networkSnapshotID),
      ("provider_dataset_id", manifest.providerDatasetID),
      ("engine_build.build_id", manifest.engineBuild.id),
      ("engine_build.provider_id", manifest.engineBuild.providerID),
      ("engine_build.provider_version", manifest.engineBuild.providerVersion),
      ("engine_build.container_image", manifest.engineBuild.containerImage),
    ] where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issue(.invalidIdentity, path, "value must not be empty")
    }
    if !isISO8601(manifest.createdAt) {
      issue(.invalidTimestamp, "created_at", "value must be an ISO 8601 timestamp")
    }
    if !isContainerSHA256(manifest.engineBuild.containerDigest) {
      issue(
        .invalidChecksum,
        "engine_build.container_digest",
        "value must be sha256 followed by 64 hexadecimal characters"
      )
    }
    if manifest.networkSnapshotID != graph.networkSnapshotID {
      issue(
        .graphSnapshotMismatch,
        "network_snapshot_id",
        "manifest and Kaido graph snapshots differ"
      )
    }
    if manifest.providerDatasetID != graph.provenance?.sourceDatasetID {
      issue(
        .providerDatasetMismatch,
        "provider_dataset_id",
        "manifest and Kaido graph provider datasets differ"
      )
    }

    appendSourceIssues(manifest.sources, issue: issue)
    appendArtifactIssues(manifest.artifacts, issue: issue)
    appendAdminVerificationIssues(manifest.adminVerifications, issue: issue)
    for (index, blocker) in manifest.releaseBlockers.enumerated()
    where blocker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issue(
        .invalidIdentity,
        "release_blockers[\(index)]",
        "release blockers must not be empty"
      )
    }

    if !manifest.sources.contains(where: { $0.roles.contains(.roadNetwork) }) {
      issue(
        .missingSourceRole,
        "sources",
        "every manifest requires a ROAD_NETWORK source"
      )
    }
    for role in [
      SurfaceRoutingBuildArtifactRole.routingTiles,
      .kaidoDirectedGraph,
    ] where !manifest.artifacts.contains(where: { $0.role == role }) {
      issue(
        .missingArtifactRole,
        "artifacts",
        "every manifest requires artifact role \(role.rawValue)"
      )
    }
    if !manifest.capabilities.keepsAllOSMNodeIDs
      && manifest.capabilities.selectedPathIdentity != .osmWayPointPairs
    {
      issue(
        .missingCapability,
        "capabilities.selected_path_identity",
        "selected-path translation requires OSM nodes or OSM way point-pair identity"
      )
    }

    guard profile == .releaseCandidate else {
      return .init(profile: profile, issues: issues)
    }

    if manifest.intendedUse != .releaseCandidate {
      issue(
        .wrongIntendedUse,
        "intended_use",
        "release validation requires RELEASE_CANDIDATE"
      )
    }
    for role in SurfaceRoutingBuildSourceRole.allCases
    where role != .roadNetwork
      && !manifest.sources.contains(where: { $0.roles.contains(role) })
    {
      issue(
        .missingSourceRole,
        "sources",
        "release manifest lacks source role \(role.rawValue)"
      )
    }
    for role in [
      SurfaceRoutingBuildArtifactRole.providerConfiguration,
      .administrationDatabase,
      .timeZoneDatabase,
    ]
    where !manifest.artifacts.contains(where: { $0.role == role }) {
      issue(
        .missingArtifactRole,
        "artifacts",
        "release manifest lacks artifact role \(role.rawValue)"
      )
    }
    for (path, enabled) in [
      (
        "capabilities.includes_administrative_data",
        manifest.capabilities.includesAdministrativeData
      ),
      ("capabilities.includes_time_zone_data", manifest.capabilities.includesTimeZoneData),
    ] where !enabled {
      issue(.missingCapability, path, "release capability must be true")
    }
    let hasTokyoLeftDrivingCheck = manifest.adminVerifications.contains { check in
      check.expectedRegionCode == "JP-13"
        && check.observedCountryCode == "JP"
        && ["13", "JP-13"].contains(check.observedStateCode)
        && !check.driveOnRight
        && check.coordinate.isValid
        && isISO8601(check.checkedAt)
        && isSHA256(check.evidenceSHA256)
    }
    if !hasTokyoLeftDrivingCheck {
      issue(
        .missingTokyoLeftDrivingVerification,
        "admin_verifications",
        "release manifest requires a checksummed Tokyo observation with drive_on_right=false"
      )
    }
    for (index, blocker) in manifest.releaseBlockers.enumerated()
    where !blocker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issue(
        .releaseBlocker,
        "release_blockers[\(index)]",
        blocker
      )
    }

    return .init(profile: profile, issues: issues)
  }

  private static func appendSourceIssues(
    _ sources: [SurfaceRoutingBuildSource],
    issue: (
      SurfaceRoutingManifestValidationIssueCode,
      String,
      String
    ) -> Void
  ) {
    let duplicateIDs = duplicateValues(sources.map(\.id))
    for id in duplicateIDs {
      issue(.duplicateSourceID, "sources", "duplicate source_id \(id)")
    }
    for (index, source) in sources.enumerated() {
      let path = "sources[\(index)]"
      if source.id.isEmpty || source.roles.isEmpty || Set(source.roles).count != source.roles.count
        || source.uri.isEmpty || source.licence.isEmpty || source.attribution.isEmpty
      {
        issue(.invalidSource, path, "source metadata is incomplete or has duplicate roles")
      }
      if !isISO8601(source.snapshotAt) {
        issue(.invalidTimestamp, "\(path).snapshot_at", "value must be an ISO 8601 timestamp")
      }
      if !isSHA256(source.sha256) {
        issue(.invalidChecksum, "\(path).sha256", "value must contain 64 hexadecimal characters")
      }
      if source.byteCount <= 0 {
        issue(.invalidByteCount, "\(path).byte_count", "value must be greater than zero")
      }
    }
  }

  private static func appendArtifactIssues(
    _ artifacts: [SurfaceRoutingBuildArtifact],
    issue: (
      SurfaceRoutingManifestValidationIssueCode,
      String,
      String
    ) -> Void
  ) {
    for id in duplicateValues(artifacts.map(\.id)) {
      issue(.duplicateArtifactID, "artifacts", "duplicate artifact_id \(id)")
    }
    for role in duplicateValues(artifacts.map(\.role)) {
      issue(.duplicateArtifactRole, "artifacts", "duplicate artifact role \(role.rawValue)")
    }
    for (index, artifact) in artifacts.enumerated() {
      let path = "artifacts[\(index)]"
      if artifact.id.isEmpty || artifact.format.isEmpty {
        issue(.invalidArtifact, path, "artifact metadata is incomplete")
      }
      if !isSafeRelativePath(artifact.relativePath) {
        issue(
          .invalidRelativePath,
          "\(path).relative_path",
          "path must be relative and must not contain empty, dot, or parent components"
        )
      }
      if !isSHA256(artifact.sha256) {
        issue(.invalidChecksum, "\(path).sha256", "value must contain 64 hexadecimal characters")
      }
      if artifact.byteCount <= 0 {
        issue(.invalidByteCount, "\(path).byte_count", "value must be greater than zero")
      }
    }
  }

  private static func appendAdminVerificationIssues(
    _ checks: [SurfaceRoutingAdminVerification],
    issue: (
      SurfaceRoutingManifestValidationIssueCode,
      String,
      String
    ) -> Void
  ) {
    for (index, check) in checks.enumerated() {
      let path = "admin_verifications[\(index)]"
      if check.id.isEmpty || !check.coordinate.isValid || check.expectedRegionCode.isEmpty
        || check.observedCountryCode.isEmpty || check.observedStateCode.isEmpty
        || !isISO8601(check.checkedAt) || !isSHA256(check.evidenceSHA256)
      {
        issue(
          .invalidAdminVerification,
          path,
          "admin observation must have valid identity, coordinate, timestamp, and checksum"
        )
      }
    }
  }

  private static func duplicateValues<Value: Hashable>(_ values: [Value]) -> [Value] {
    var seen = Set<Value>()
    var duplicates = Set<Value>()
    for value in values where !seen.insert(value).inserted {
      duplicates.insert(value)
    }
    return duplicates.sorted { String(describing: $0) < String(describing: $1) }
  }

  private static func isISO8601(_ value: String) -> Bool {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if formatter.date(from: value) != nil { return true }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value) != nil
  }

  private static func isSHA256(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy { byte in
        (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
      }
  }

  private static func isContainerSHA256(_ value: String) -> Bool {
    value.hasPrefix("sha256:") && isSHA256(String(value.dropFirst("sha256:".count)))
  }

  private static func isSafeRelativePath(_ value: String) -> Bool {
    guard !value.isEmpty, !value.hasPrefix("/") else { return false }
    return value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
      !$0.isEmpty && $0 != "." && $0 != ".."
    }
  }
}

extension SurfaceRoutingBuildSourceRole: CaseIterable {}
extension SurfaceRoutingBuildArtifactRole: CaseIterable {}
