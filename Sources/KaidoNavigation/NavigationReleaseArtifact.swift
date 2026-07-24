import Foundation
import KaidoDomain
import KaidoRouting

public enum NavigationReleaseAssetRole: String, Codable, CaseIterable, Hashable, Sendable {
  case editorCatalog = "EDITOR_CATALOG"
  case runtimePolicy = "RUNTIME_POLICY"
  case matcherCorridor = "MATCHER_CORRIDOR"
  case decisionZone = "DECISION_ZONE"
  case guidance = "GUIDANCE"
  case junctionView = "JUNCTION_VIEW"
}

public enum NavigationReleaseEvidenceState: String, Codable, Sendable {
  case officialChecked = "OFFICIAL_CHECKED"
  case fieldChecked = "FIELD_CHECKED"
  case released = "RELEASED"
}

public struct NavigationReleaseSourceReference: Codable, Equatable, Sendable {
  public let id: String
  public let roles: Set<NavigationReleaseAssetRole>
  public let authorityName: String
  public let sourceURL: String
  public let contentSHA256: String
  public let checkedAt: String
  public let licenceIdentifier: String

  public init(
    id: String,
    roles: Set<NavigationReleaseAssetRole>,
    authorityName: String,
    sourceURL: String,
    contentSHA256: String,
    checkedAt: String,
    licenceIdentifier: String
  ) {
    self.id = id
    self.roles = roles
    self.authorityName = authorityName
    self.sourceURL = sourceURL
    self.contentSHA256 = contentSHA256
    self.checkedAt = checkedAt
    self.licenceIdentifier = licenceIdentifier
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case roles
    case authorityName = "authority_name"
    case sourceURL = "source_url"
    case contentSHA256 = "content_sha256"
    case checkedAt = "checked_at"
    case licenceIdentifier = "licence_identifier"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    let decodedRoles = try container.decode(
      [NavigationReleaseAssetRole].self,
      forKey: .roles
    )
    guard Set(decodedRoles).count == decodedRoles.count else {
      throw DecodingError.dataCorruptedError(
        forKey: .roles,
        in: container,
        debugDescription: "Navigation release source roles must be unique"
      )
    }
    roles = Set(decodedRoles)
    authorityName = try container.decode(String.self, forKey: .authorityName)
    sourceURL = try container.decode(String.self, forKey: .sourceURL)
    contentSHA256 = try container.decode(String.self, forKey: .contentSHA256)
    checkedAt = try container.decode(String.self, forKey: .checkedAt)
    licenceIdentifier = try container.decode(String.self, forKey: .licenceIdentifier)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(roles.sorted(by: { $0.rawValue < $1.rawValue }), forKey: .roles)
    try container.encode(authorityName, forKey: .authorityName)
    try container.encode(sourceURL, forKey: .sourceURL)
    try container.encode(contentSHA256, forKey: .contentSHA256)
    try container.encode(checkedAt, forKey: .checkedAt)
    try container.encode(licenceIdentifier, forKey: .licenceIdentifier)
  }
}

public struct NavigationReleaseSourceRegistry: Codable, Equatable, Sendable {
  public let references: [NavigationReleaseSourceReference]

  public init(references: [NavigationReleaseSourceReference]) {
    self.references = references
  }
}

/// A dated review record for one exact asset identity inside a release artifact.
///
/// The role and asset ID form the identity. Source references establish why that
/// exact asset was reviewed, while the whole artifact remains the distribution
/// unit. This record never promotes a source or candidate by itself.
public struct NavigationReleaseAssetEvidence: Codable, Equatable, Sendable {
  public let role: NavigationReleaseAssetRole
  public let assetID: String
  public let state: NavigationReleaseEvidenceState
  public let checkedAt: String
  public let sourceReferenceIDs: [String]

  public init(
    role: NavigationReleaseAssetRole,
    assetID: String,
    state: NavigationReleaseEvidenceState,
    checkedAt: String,
    sourceReferenceIDs: [String]
  ) {
    self.role = role
    self.assetID = assetID
    self.state = state
    self.checkedAt = checkedAt
    self.sourceReferenceIDs = sourceReferenceIDs
  }

  private enum CodingKeys: String, CodingKey {
    case role
    case assetID = "asset_id"
    case state
    case checkedAt = "checked_at"
    case sourceReferenceIDs = "source_reference_ids"
  }
}

/// Versioned, distributable input to the navigation release gate.
///
/// Decoding this value alone never makes it eligible for runtime use. Consumers
/// must construct `NavigationRelease`, which validates provenance coverage and
/// reuses the complete `NavigationReleaseBundle` integrity gate.
public struct NavigationReleaseArtifact: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = "2.0"

  public let schemaVersion: String
  public let releaseID: String
  public let releasedAt: String
  public let editorCatalogID: String
  public let networkSnapshot: NetworkSnapshot
  public let routePlan: RoutePlan
  public let sourceRegistry: NavigationReleaseSourceRegistry
  public let assetEvidence: [NavigationReleaseAssetEvidence]
  public let editorCatalog: ReviewedRouteEditorCatalog
  public let runtimePolicy: ReleasedNavigationRuntimePolicy?
  public let matcherCorridor: RouteMatcherCorridor
  public let decisionZones: [DecisionZoneProgressDefinition]
  public let releasedGuidance: [ReleasedGuidanceDefinition]
  public let junctionViews: [JunctionViewDefinition]

  public init(
    schemaVersion: String = NavigationReleaseArtifact.currentSchemaVersion,
    releaseID: String,
    releasedAt: String,
    editorCatalogID: String,
    networkSnapshot: NetworkSnapshot,
    routePlan: RoutePlan,
    sourceRegistry: NavigationReleaseSourceRegistry,
    assetEvidence: [NavigationReleaseAssetEvidence],
    editorCatalog: ReviewedRouteEditorCatalog,
    runtimePolicy: ReleasedNavigationRuntimePolicy?,
    matcherCorridor: RouteMatcherCorridor,
    decisionZones: [DecisionZoneProgressDefinition],
    releasedGuidance: [ReleasedGuidanceDefinition],
    junctionViews: [JunctionViewDefinition] = []
  ) {
    self.schemaVersion = schemaVersion
    self.releaseID = releaseID
    self.releasedAt = releasedAt
    self.editorCatalogID = editorCatalogID
    self.networkSnapshot = networkSnapshot
    self.routePlan = routePlan
    self.sourceRegistry = sourceRegistry
    self.assetEvidence = assetEvidence
    self.editorCatalog = editorCatalog
    self.runtimePolicy = runtimePolicy
    self.matcherCorridor = matcherCorridor
    self.decisionZones = decisionZones
    self.releasedGuidance = releasedGuidance
    self.junctionViews = junctionViews
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case releaseID = "release_id"
    case releasedAt = "released_at"
    case editorCatalogID = "editor_catalog_id"
    case networkSnapshot = "network_snapshot"
    case routePlan = "route_plan"
    case sourceRegistry = "source_registry"
    case assetEvidence = "asset_evidence"
    case editorCatalog = "editor_catalog"
    case runtimePolicy = "runtime_policy"
    case matcherCorridor = "matcher_corridor"
    case decisionZones = "decision_zones"
    case releasedGuidance = "released_guidance"
    case junctionViews = "junction_views"
  }
}

public enum NavigationReleaseIssue: Equatable, Sendable {
  case invalidArtifactSchemaVersion
  case invalidArtifactIdentity
  case invalidEditorCatalogID
  case missingRuntimePolicy
  case invalidSourceRegistry
  case duplicateSourceReference(String)
  case orphanSourceReference(String)
  case duplicateArtifactAsset(String)
  case duplicateAssetEvidence(String)
  case missingAssetEvidence(String)
  case orphanAssetEvidence(String)
  case invalidAssetEvidence(String)
  case unreleasedAssetEvidence(String)
  case unresolvedAssetSource(String)
  case invalidAssetSourceRole(String)
  case junctionViewEvidenceMismatch(String)
  case evidenceAfterRelease(String)
  case invalidBundle(NavigationReleaseBundleIssue)

  public var code: String {
    switch self {
    case .invalidArtifactSchemaVersion:
      "INVALID_NAVIGATION_RELEASE_ARTIFACT_SCHEMA_VERSION"
    case .invalidArtifactIdentity:
      "INVALID_NAVIGATION_RELEASE_ARTIFACT_IDENTITY"
    case .invalidEditorCatalogID:
      "INVALID_NAVIGATION_EDITOR_CATALOG_ID"
    case .missingRuntimePolicy:
      "MISSING_NAVIGATION_RUNTIME_POLICY"
    case .invalidSourceRegistry:
      "INVALID_NAVIGATION_SOURCE_REGISTRY"
    case .duplicateSourceReference:
      "DUPLICATE_NAVIGATION_SOURCE_REFERENCE"
    case .orphanSourceReference:
      "ORPHAN_NAVIGATION_SOURCE_REFERENCE"
    case .duplicateArtifactAsset:
      "DUPLICATE_NAVIGATION_ARTIFACT_ASSET"
    case .duplicateAssetEvidence:
      "DUPLICATE_NAVIGATION_ASSET_EVIDENCE"
    case .missingAssetEvidence:
      "MISSING_NAVIGATION_ASSET_EVIDENCE"
    case .orphanAssetEvidence:
      "ORPHAN_NAVIGATION_ASSET_EVIDENCE"
    case .invalidAssetEvidence:
      "INVALID_NAVIGATION_ASSET_EVIDENCE"
    case .unreleasedAssetEvidence:
      "UNRELEASED_NAVIGATION_ASSET_EVIDENCE"
    case .unresolvedAssetSource:
      "UNRESOLVED_NAVIGATION_ASSET_SOURCE"
    case .invalidAssetSourceRole:
      "INVALID_NAVIGATION_ASSET_SOURCE_ROLE"
    case .junctionViewEvidenceMismatch:
      "NAVIGATION_JUNCTION_VIEW_EVIDENCE_MISMATCH"
    case .evidenceAfterRelease:
      "NAVIGATION_EVIDENCE_AFTER_RELEASE"
    case .invalidBundle(let issue):
      issue.code
    }
  }

  var sortKey: String {
    switch self {
    case .duplicateSourceReference(let detail),
      .orphanSourceReference(let detail),
      .duplicateArtifactAsset(let detail),
      .duplicateAssetEvidence(let detail),
      .missingAssetEvidence(let detail),
      .orphanAssetEvidence(let detail),
      .invalidAssetEvidence(let detail),
      .unreleasedAssetEvidence(let detail),
      .unresolvedAssetSource(let detail),
      .invalidAssetSourceRole(let detail),
      .junctionViewEvidenceMismatch(let detail),
      .evidenceAfterRelease(let detail):
      "\(code):\(detail)"
    case .invalidBundle(let issue):
      "BUNDLE:\(issue.sortKey)"
    default:
      code
    }
  }
}

public enum NavigationReleaseError: Error, Equatable, Sendable {
  case invalid([NavigationReleaseIssue])
}

/// One provenance-checked release artifact and its validated runtime bundle.
public struct NavigationRelease: Equatable, Sendable {
  public let releaseID: String
  public let releasedAt: String
  public let editorCatalogID: String
  public let sourceRegistry: NavigationReleaseSourceRegistry
  public let assetEvidence: [NavigationReleaseAssetEvidence]
  public let bundle: NavigationReleaseBundle

  public init(artifact: NavigationReleaseArtifact) throws {
    var issues = Self.artifactIssues(artifact)
    let bundle: NavigationReleaseBundle?
    if artifact.runtimePolicy == nil {
      issues.append(.missingRuntimePolicy)
    }
    if let runtimePolicy = artifact.runtimePolicy {
      do {
        bundle = try NavigationReleaseBundle(
          networkSnapshot: artifact.networkSnapshot,
          routePlan: artifact.routePlan,
          editorCatalog: artifact.editorCatalog,
          runtimePolicy: runtimePolicy,
          matcherCorridor: artifact.matcherCorridor,
          decisionZones: artifact.decisionZones,
          releasedGuidance: artifact.releasedGuidance,
          junctionViews: artifact.junctionViews
        )
      } catch NavigationReleaseBundleError.invalid(let bundleIssues) {
        issues.append(contentsOf: bundleIssues.map(NavigationReleaseIssue.invalidBundle))
        bundle = nil
      }
    } else {
      bundle = nil
    }
    issues = Self.sortedUnique(issues)
    guard issues.isEmpty, let bundle else {
      throw NavigationReleaseError.invalid(issues)
    }

    releaseID = artifact.releaseID
    releasedAt = artifact.releasedAt
    editorCatalogID = artifact.editorCatalogID
    sourceRegistry = artifact.sourceRegistry
    assetEvidence = artifact.assetEvidence
    self.bundle = bundle
  }

  private struct AssetKey: Hashable {
    let role: NavigationReleaseAssetRole
    let assetID: String

    var description: String {
      "\(role.rawValue):\(assetID)"
    }
  }

  private static func artifactIssues(
    _ artifact: NavigationReleaseArtifact
  ) -> [NavigationReleaseIssue] {
    var issues: [NavigationReleaseIssue] = []

    if artifact.schemaVersion != NavigationReleaseArtifact.currentSchemaVersion {
      issues.append(.invalidArtifactSchemaVersion)
    }
    if normalized(artifact.releaseID).isEmpty || !isISO8601DateTime(artifact.releasedAt) {
      issues.append(.invalidArtifactIdentity)
    }
    if normalized(artifact.editorCatalogID).isEmpty {
      issues.append(.invalidEditorCatalogID)
    }
    let releaseDate =
      isISO8601DateTime(artifact.releasedAt)
      ? String(artifact.releasedAt.prefix(10)) : nil

    var sourcesByID: [String: NavigationReleaseSourceReference] = [:]
    var sourceRegistryIsInvalid = artifact.sourceRegistry.references.isEmpty
    for source in artifact.sourceRegistry.references {
      if sourcesByID[source.id] != nil {
        issues.append(.duplicateSourceReference(source.id))
      } else {
        sourcesByID[source.id] = source
      }
      if normalized(source.id).isEmpty
        || source.roles.isEmpty
        || normalized(source.authorityName).isEmpty
        || !isHTTPSURL(source.sourceURL)
        || !isSHA256(source.contentSHA256)
        || !isISODate(source.checkedAt)
        || normalized(source.licenceIdentifier).isEmpty
      {
        sourceRegistryIsInvalid = true
      }
      if let releaseDate, isISODate(source.checkedAt), source.checkedAt > releaseDate {
        issues.append(.evidenceAfterRelease("SOURCE:\(source.id)"))
      }
    }
    if sourceRegistryIsInvalid {
      issues.append(.invalidSourceRegistry)
    }

    var expectedAssetCounts: [AssetKey: Int] = [:]
    func expect(_ role: NavigationReleaseAssetRole, _ assetID: String) {
      expectedAssetCounts[AssetKey(role: role, assetID: assetID), default: 0] += 1
    }
    expect(.editorCatalog, artifact.editorCatalogID)
    if let runtimePolicy = artifact.runtimePolicy {
      expect(.runtimePolicy, runtimePolicy.id)
    }
    expect(.matcherCorridor, artifact.matcherCorridor.id)
    for definition in artifact.decisionZones {
      expect(.decisionZone, definition.id)
    }
    for definition in artifact.releasedGuidance {
      expect(.guidance, definition.anchor.promptID)
    }
    for definition in artifact.junctionViews {
      expect(.junctionView, definition.id)
    }
    for (key, count) in expectedAssetCounts where count != 1 {
      issues.append(.duplicateArtifactAsset(key.description))
    }

    var evidenceByKey: [AssetKey: [NavigationReleaseAssetEvidence]] = [:]
    var usedSourceIDs: Set<String> = []
    for evidence in artifact.assetEvidence {
      let key = AssetKey(role: evidence.role, assetID: evidence.assetID)
      evidenceByKey[key, default: []].append(evidence)

      if normalized(evidence.assetID).isEmpty
        || !isISODate(evidence.checkedAt)
        || evidence.sourceReferenceIDs.isEmpty
        || evidence.sourceReferenceIDs.contains(where: { normalized($0).isEmpty })
        || Set(evidence.sourceReferenceIDs).count != evidence.sourceReferenceIDs.count
      {
        issues.append(.invalidAssetEvidence(key.description))
      }
      if evidence.state != .released {
        issues.append(.unreleasedAssetEvidence(key.description))
      }
      if let releaseDate, isISODate(evidence.checkedAt),
        evidence.checkedAt > releaseDate
      {
        issues.append(.evidenceAfterRelease(key.description))
      }
      if expectedAssetCounts[key] == nil {
        issues.append(.orphanAssetEvidence(key.description))
      }

      for sourceID in evidence.sourceReferenceIDs {
        usedSourceIDs.insert(sourceID)
        guard let source = sourcesByID[sourceID] else {
          issues.append(.unresolvedAssetSource("\(key.description):\(sourceID)"))
          continue
        }
        if !source.roles.contains(evidence.role) {
          issues.append(.invalidAssetSourceRole("\(key.description):\(sourceID)"))
        }
      }
    }

    for key in expectedAssetCounts.keys {
      let count = evidenceByKey[key]?.count ?? 0
      if count == 0 {
        issues.append(.missingAssetEvidence(key.description))
      } else if count > 1 {
        issues.append(.duplicateAssetEvidence(key.description))
      }
    }
    for sourceID in sourcesByID.keys where !usedSourceIDs.contains(sourceID) {
      issues.append(.orphanSourceReference(sourceID))
    }

    let junctionViewsByID = Dictionary(
      artifact.junctionViews.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    for evidence in artifact.assetEvidence where evidence.role == .junctionView {
      guard let junctionView = junctionViewsByID[evidence.assetID] else { continue }
      if evidence.checkedAt != junctionView.evidence.checkedAt
        || Set(evidence.sourceReferenceIDs)
          != Set(junctionView.evidence.sourceReferenceIDs)
      {
        issues.append(.junctionViewEvidenceMismatch(evidence.assetID))
      }
    }

    return issues
  }

  private static func sortedUnique(
    _ issues: [NavigationReleaseIssue]
  ) -> [NavigationReleaseIssue] {
    var result: [NavigationReleaseIssue] = []
    for issue in issues.sorted(by: { $0.sortKey < $1.sortKey })
    where !result.contains(issue) {
      result.append(issue)
    }
    return result
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func isHTTPSURL(_ value: String) -> Bool {
    guard let components = URLComponents(string: value) else { return false }
    return components.scheme == "https" && components.host?.isEmpty == false
  }

  private static func isSHA256(_ value: String) -> Bool {
    value.count == 64 && value.allSatisfy(\.isHexDigit)
  }

  private static func isISO8601DateTime(_ value: String) -> Bool {
    let standard = ISO8601DateFormatter()
    if standard.date(from: value) != nil {
      return true
    }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value) != nil
  }

  private static func isISODate(_ value: String) -> Bool {
    let parts = value.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3,
      parts[0].count == 4,
      parts[1].count == 2,
      parts[2].count == 2,
      let year = Int(parts[0]),
      let month = Int(parts[1]),
      let day = Int(parts[2])
    else { return false }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let components = DateComponents(
      calendar: calendar,
      timeZone: calendar.timeZone,
      year: year,
      month: month,
      day: day
    )
    guard let date = components.date else { return false }
    let resolved = calendar.dateComponents([.year, .month, .day], from: date)
    return resolved.year == year && resolved.month == month && resolved.day == day
  }
}

public enum NavigationReleaseArtifactCodec {
  public static func encode(_ artifact: NavigationReleaseArtifact) throws -> Data {
    _ = try NavigationRelease(artifact: artifact)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(artifact)
  }

  public static func decode(_ data: Data) throws -> NavigationRelease {
    let artifact = try JSONDecoder().decode(NavigationReleaseArtifact.self, from: data)
    return try NavigationRelease(artifact: artifact)
  }
}
