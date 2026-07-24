import Foundation
import KaidoDomain
import KaidoRouting

public enum ProductEditorAtlasEntityRole: String, Equatable, Sendable {
  case entranceEdge = "ENTRANCE_EDGE"
  case incomingApproach = "INCOMING_APPROACH"
  case movement = "MOVEMENT"
  case outgoingEdge = "OUTGOING_EDGE"
}

/// The one file a product build may use to pair navigation runtime assets with
/// renderer-neutral released topology.
///
/// Both nested artifacts retain their independent validators. This outer
/// artifact adds cross-artifact identity and authoring-coverage checks.
public struct KaidoProductReleaseArtifact: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = "1.0"

  public let schemaVersion: String
  public let releaseID: String
  public let releasedAt: String
  public let navigationRelease: NavigationReleaseArtifact
  public let routeAtlasRelease: RouteAtlasReleaseArtifact

  public init(
    schemaVersion: String = KaidoProductReleaseArtifact.currentSchemaVersion,
    releaseID: String,
    releasedAt: String,
    navigationRelease: NavigationReleaseArtifact,
    routeAtlasRelease: RouteAtlasReleaseArtifact
  ) {
    self.schemaVersion = schemaVersion
    self.releaseID = releaseID
    self.releasedAt = releasedAt
    self.navigationRelease = navigationRelease
    self.routeAtlasRelease = routeAtlasRelease
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case releaseID = "release_id"
    case releasedAt = "released_at"
    case navigationRelease = "navigation_release"
    case routeAtlasRelease = "route_atlas_release"
  }
}

public enum KaidoProductReleaseIssue: Equatable, Sendable {
  case invalidArtifactSchemaVersion
  case invalidArtifactIdentity
  case invalidNavigationRelease(NavigationReleaseIssue)
  case invalidRouteAtlasRelease(RouteAtlasReleaseIssue)
  case networkSnapshotMismatch
  case routePlanMismatch
  case navigationReleaseAfterProductRelease
  case atlasEvidenceAfterProductRelease(String)
  case missingAtlasEditorEntity(ProductEditorAtlasEntityRole, String)

  public var code: String {
    switch self {
    case .invalidArtifactSchemaVersion:
      "INVALID_PRODUCT_RELEASE_ARTIFACT_SCHEMA_VERSION"
    case .invalidArtifactIdentity:
      "INVALID_PRODUCT_RELEASE_ARTIFACT_IDENTITY"
    case .invalidNavigationRelease(let issue):
      issue.code
    case .invalidRouteAtlasRelease(let issue):
      issue.code
    case .networkSnapshotMismatch:
      "PRODUCT_RELEASE_NETWORK_SNAPSHOT_MISMATCH"
    case .routePlanMismatch:
      "PRODUCT_RELEASE_ROUTE_PLAN_MISMATCH"
    case .navigationReleaseAfterProductRelease:
      "NAVIGATION_RELEASE_AFTER_PRODUCT_RELEASE"
    case .atlasEvidenceAfterProductRelease:
      "ATLAS_EVIDENCE_AFTER_PRODUCT_RELEASE"
    case .missingAtlasEditorEntity:
      "MISSING_PRODUCT_ATLAS_EDITOR_ENTITY"
    }
  }

  var sortKey: String {
    switch self {
    case .invalidNavigationRelease(let issue):
      "NAVIGATION:\(issue.sortKey)"
    case .invalidRouteAtlasRelease(let issue):
      "ATLAS:\(issue.sortKey)"
    case .atlasEvidenceAfterProductRelease(let detail):
      "\(code):\(detail)"
    case .missingAtlasEditorEntity(let role, let entityID):
      "\(code):\(role.rawValue):\(entityID)"
    default:
      code
    }
  }
}

public enum KaidoProductReleaseError: Error, Equatable, Sendable {
  case invalid([KaidoProductReleaseIssue])
}

/// A validated product release whose navigation and atlas views cannot drift.
public struct KaidoProductRelease: Equatable, Sendable {
  public let releaseID: String
  public let releasedAt: String
  public let navigation: NavigationRelease
  public let routeAtlas: RouteAtlasRelease

  public init(artifact: KaidoProductReleaseArtifact) throws {
    var issues: [KaidoProductReleaseIssue] = []

    if artifact.schemaVersion != KaidoProductReleaseArtifact.currentSchemaVersion {
      issues.append(.invalidArtifactSchemaVersion)
    }
    if Self.normalized(artifact.releaseID).isEmpty
      || !Self.isISO8601DateTime(artifact.releasedAt)
    {
      issues.append(.invalidArtifactIdentity)
    }

    let navigation: NavigationRelease?
    do {
      navigation = try NavigationRelease(artifact: artifact.navigationRelease)
    } catch NavigationReleaseError.invalid(let nestedIssues) {
      issues.append(
        contentsOf: nestedIssues.map(KaidoProductReleaseIssue.invalidNavigationRelease)
      )
      navigation = nil
    }

    let routeAtlas: RouteAtlasRelease?
    do {
      routeAtlas = try RouteAtlasRelease(artifact: artifact.routeAtlasRelease)
    } catch RouteAtlasReleaseError.invalid(let nestedIssues) {
      issues.append(
        contentsOf: nestedIssues.map(KaidoProductReleaseIssue.invalidRouteAtlasRelease)
      )
      routeAtlas = nil
    }

    if let navigation, let routeAtlas {
      let networkSnapshotMatches =
        navigation.bundle.networkSnapshot == routeAtlas.networkSnapshot
      let routePlanMatches = navigation.bundle.routePlan == routeAtlas.routePlan
      if !networkSnapshotMatches {
        issues.append(.networkSnapshotMismatch)
      }
      if !routePlanMatches {
        issues.append(.routePlanMismatch)
      }
      if let navigationDate = Self.parseISO8601(navigation.releasedAt),
        let productDate = Self.parseISO8601(artifact.releasedAt),
        navigationDate > productDate
      {
        issues.append(.navigationReleaseAfterProductRelease)
      }

      if networkSnapshotMatches, routePlanMatches {
        let atlasEntityIDs = Set(
          routeAtlas.topologySlice.edges.map(\.routeEntityID)
        )
        let catalog = navigation.bundle.editorCatalog
        for entrance in catalog.entrances
        where !atlasEntityIDs.contains(entrance.initialEdgeID) {
          issues.append(.missingAtlasEditorEntity(.entranceEdge, entrance.initialEdgeID))
        }
        for decisionPoint in catalog.decisionPoints {
          if !atlasEntityIDs.contains(decisionPoint.incomingApproachID) {
            issues.append(
              .missingAtlasEditorEntity(
                .incomingApproach,
                decisionPoint.incomingApproachID
              )
            )
          }
          for choice in decisionPoint.choices {
            if !atlasEntityIDs.contains(choice.movementID) {
              issues.append(.missingAtlasEditorEntity(.movement, choice.movementID))
            }
            if !atlasEntityIDs.contains(choice.outgoingEdgeID) {
              issues.append(
                .missingAtlasEditorEntity(.outgoingEdge, choice.outgoingEdgeID)
              )
            }
          }
        }
      }

      if Self.isISO8601DateTime(artifact.releasedAt) {
        let productReleaseDate = String(artifact.releasedAt.prefix(10))
        for source in routeAtlas.sourceRegistry.references
        where source.checkedAt > productReleaseDate {
          issues.append(
            .atlasEvidenceAfterProductRelease("SOURCE:\(source.id)")
          )
        }
        if routeAtlas.topologySlice.evidence.checkedAt > productReleaseDate {
          issues.append(
            .atlasEvidenceAfterProductRelease(
              "TOPOLOGY:\(routeAtlas.topologySlice.id)"
            )
          )
        }
        if routeAtlas.definition.evidence.checkedAt > productReleaseDate {
          issues.append(
            .atlasEvidenceAfterProductRelease(
              "LAYOUT:\(routeAtlas.definition.id)"
            )
          )
        }
      }
    }

    issues = Self.sortedUnique(issues)
    guard issues.isEmpty, let navigation, let routeAtlas else {
      throw KaidoProductReleaseError.invalid(issues)
    }

    releaseID = artifact.releaseID
    releasedAt = artifact.releasedAt
    self.navigation = navigation
    self.routeAtlas = routeAtlas
  }

  private static func sortedUnique(
    _ issues: [KaidoProductReleaseIssue]
  ) -> [KaidoProductReleaseIssue] {
    var result: [KaidoProductReleaseIssue] = []
    for issue in issues.sorted(by: { $0.sortKey < $1.sortKey })
    where !result.contains(issue) {
      result.append(issue)
    }
    return result
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func parseISO8601(_ value: String) -> Date? {
    let standard = ISO8601DateFormatter()
    if let date = standard.date(from: value) {
      return date
    }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value)
  }

  private static func isISO8601DateTime(_ value: String) -> Bool {
    parseISO8601(value) != nil
  }
}

public enum KaidoProductReleaseArtifactCodec {
  public static func encode(_ artifact: KaidoProductReleaseArtifact) throws -> Data {
    _ = try KaidoProductRelease(artifact: artifact)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(artifact)
  }

  public static func decode(_ data: Data) throws -> KaidoProductRelease {
    let artifact = try JSONDecoder().decode(KaidoProductReleaseArtifact.self, from: data)
    return try KaidoProductRelease(artifact: artifact)
  }
}
