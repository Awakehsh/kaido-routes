import Foundation

/// Reproducible metadata for assembling one real-road product release.
///
/// Runtime scope is deliberately not configurable here. This authoring path is
/// only for a released-road product that admits foreground When In Use input
/// after the complete joint release passes validation.
public struct KaidoProductReleaseAuthoringConfiguration:
  Codable, Equatable, Sendable
{
  public static let currentSchemaVersion = "1.0"

  public let schemaVersion: String
  public let releaseID: String
  public let releasedAt: String

  public init(
    schemaVersion: String =
      KaidoProductReleaseAuthoringConfiguration.currentSchemaVersion,
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

public enum KaidoProductReleaseAuthoringIssue: Equatable, Sendable {
  case invalidConfigurationSchemaVersion
  case invalidReleaseIdentity

  public var code: String {
    switch self {
    case .invalidConfigurationSchemaVersion:
      "INVALID_PRODUCT_RELEASE_AUTHORING_SCHEMA_VERSION"
    case .invalidReleaseIdentity:
      "INVALID_PRODUCT_RELEASE_AUTHORING_IDENTITY"
    }
  }
}

public enum KaidoProductReleaseAuthoringError: Error, Equatable, Sendable {
  case invalidConfiguration([KaidoProductReleaseAuthoringIssue])
  case invalidNavigationRelease([NavigationReleaseIssue])
  case invalidRouteAtlasRelease([RouteAtlasReleaseIssue])
  case invalidProductRelease([KaidoProductReleaseIssue])
}

/// Assembles two independently valid release artifacts into the one product
/// artifact that the app distribution catalog consumes.
///
/// This author never changes either nested artifact and never exposes a
/// synthetic mode. Cross-artifact identity, chronology, editor-atlas coverage,
/// evidence scope, and live-input admission are all revalidated before an
/// artifact is returned.
public enum KaidoProductReleaseAuthor {
  public static func buildArtifact(
    navigationRelease: NavigationReleaseArtifact,
    routeAtlasRelease: RouteAtlasReleaseArtifact,
    configuration: KaidoProductReleaseAuthoringConfiguration
  ) throws -> KaidoProductReleaseArtifact {
    let configurationIssues = validationIssues(configuration)
    guard configurationIssues.isEmpty else {
      throw KaidoProductReleaseAuthoringError.invalidConfiguration(
        configurationIssues
      )
    }

    do {
      _ = try NavigationRelease(artifact: navigationRelease)
    } catch NavigationReleaseError.invalid(let issues) {
      throw KaidoProductReleaseAuthoringError.invalidNavigationRelease(
        issues
      )
    }

    do {
      _ = try RouteAtlasRelease(artifact: routeAtlasRelease)
    } catch RouteAtlasReleaseError.invalid(let issues) {
      throw KaidoProductReleaseAuthoringError.invalidRouteAtlasRelease(
        issues
      )
    }

    let artifact = KaidoProductReleaseArtifact(
      releaseID: configuration.releaseID,
      releasedAt: configuration.releasedAt,
      runtimeUse: KaidoProductRuntimeUseDeclaration(
        evidenceScope: .releasedRoad,
        liveInputPolicy: .foregroundWhenInUse
      ),
      navigationRelease: navigationRelease,
      routeAtlasRelease: routeAtlasRelease
    )
    do {
      _ = try KaidoProductRelease(artifact: artifact)
    } catch KaidoProductReleaseError.invalid(let issues) {
      throw KaidoProductReleaseAuthoringError.invalidProductRelease(
        issues
      )
    }
    return artifact
  }

  private static func validationIssues(
    _ configuration: KaidoProductReleaseAuthoringConfiguration
  ) -> [KaidoProductReleaseAuthoringIssue] {
    var issues: [KaidoProductReleaseAuthoringIssue] = []
    if configuration.schemaVersion
      != KaidoProductReleaseAuthoringConfiguration.currentSchemaVersion
    {
      issues.append(.invalidConfigurationSchemaVersion)
    }
    if configuration.releaseID.trimmingCharacters(
      in: .whitespacesAndNewlines
    ).isEmpty || !isISO8601DateTime(configuration.releasedAt) {
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

public enum KaidoProductReleaseAuthoringConfigurationCodec {
  public static func encode(
    _ configuration: KaidoProductReleaseAuthoringConfiguration
  ) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(configuration)
  }

  public static func decode(_ data: Data) throws
    -> KaidoProductReleaseAuthoringConfiguration
  {
    try JSONDecoder().decode(
      KaidoProductReleaseAuthoringConfiguration.self,
      from: data
    )
  }
}
