import CryptoKit
import Foundation
import KaidoDomain
import KaidoNavigation

public struct GuidanceAudioRecordingWorkItem:
  Codable, Equatable, Sendable
{
  public let key: GuidanceAudioAssetKey
  public let spokenText: String
  public let spokenTextSHA256: String
  public let suggestedResourceFilename: String

  public init(
    key: GuidanceAudioAssetKey,
    spokenText: String,
    spokenTextSHA256: String,
    suggestedResourceFilename: String
  ) {
    self.key = key
    self.spokenText = spokenText
    self.spokenTextSHA256 = spokenTextSHA256
    self.suggestedResourceFilename = suggestedResourceFilename
  }

  private enum CodingKeys: String, CodingKey {
    case key
    case spokenText = "spoken_text"
    case spokenTextSHA256 = "spoken_text_sha256"
    case suggestedResourceFilename = "suggested_resource_filename"
  }
}

/// A deterministic list of every spoken asset required by one product release.
///
/// The worklist contains no synthesis decision and grants no release authority.
/// It exists so a voice pipeline can generate the complete occurrence-scoped
/// corpus without copying prompt identities or reviewed text by hand.
public struct GuidanceAudioRecordingWorklist:
  Codable, Equatable, Sendable
{
  public static let currentSchemaVersion = "1.0"

  public let schemaVersion: String
  public let productReleaseID: String
  public let navigationReleaseID: String
  public let networkSnapshotID: String
  public let routePlanID: String
  public let items: [GuidanceAudioRecordingWorkItem]

  public init(
    schemaVersion: String = GuidanceAudioRecordingWorklist.currentSchemaVersion,
    productReleaseID: String,
    navigationReleaseID: String,
    networkSnapshotID: String,
    routePlanID: String,
    items: [GuidanceAudioRecordingWorkItem]
  ) {
    self.schemaVersion = schemaVersion
    self.productReleaseID = productReleaseID
    self.navigationReleaseID = navigationReleaseID
    self.networkSnapshotID = networkSnapshotID
    self.routePlanID = routePlanID
    self.items = items
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case productReleaseID = "product_release_id"
    case navigationReleaseID = "navigation_release_id"
    case networkSnapshotID = "network_snapshot_id"
    case routePlanID = "route_plan_id"
    case items
  }
}

public struct GuidanceAudioLanguageProfile:
  Codable, Equatable, Sendable
{
  public let languageCode: String
  public let provenance: GuidanceAudioSynthesisProvenance

  public init(
    languageCode: String,
    provenance: GuidanceAudioSynthesisProvenance
  ) {
    self.languageCode = languageCode
    self.provenance = provenance
  }

  private enum CodingKeys: String, CodingKey {
    case languageCode = "language_code"
    case provenance
  }
}

/// Human-reviewed release metadata plus one selected voice per locale.
///
/// Resource filenames and prompt records are derived from the product release
/// worklist. This configuration deliberately cannot rewrite spoken text or
/// occurrence identity.
public struct GuidanceAudioAuthoringConfiguration:
  Codable, Equatable, Sendable
{
  public static let currentSchemaVersion = "1.1"

  public let schemaVersion: String
  public let releaseID: String
  public let releasedAt: String
  public let languageProfiles: [GuidanceAudioLanguageProfile]

  public init(
    schemaVersion: String =
      GuidanceAudioAuthoringConfiguration.currentSchemaVersion,
    releaseID: String,
    releasedAt: String,
    languageProfiles: [GuidanceAudioLanguageProfile]
  ) {
    self.schemaVersion = schemaVersion
    self.releaseID = releaseID
    self.releasedAt = releasedAt
    self.languageProfiles = languageProfiles
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case releaseID = "release_id"
    case releasedAt = "released_at"
    case languageProfiles = "language_profiles"
  }
}

public enum GuidanceAudioAuthoringIssue: Equatable, Sendable {
  case invalidConfigurationSchemaVersion
  case duplicateLanguageProfile(String)
  case missingLanguageProfile(String)
  case unexpectedLanguageProfile(String)

  public var code: String {
    switch self {
    case .invalidConfigurationSchemaVersion:
      "GUIDANCE_AUDIO_AUTHORING_SCHEMA_VERSION_INVALID"
    case .duplicateLanguageProfile:
      "GUIDANCE_AUDIO_AUTHORING_LANGUAGE_PROFILE_DUPLICATE"
    case .missingLanguageProfile:
      "GUIDANCE_AUDIO_AUTHORING_LANGUAGE_PROFILE_MISSING"
    case .unexpectedLanguageProfile:
      "GUIDANCE_AUDIO_AUTHORING_LANGUAGE_PROFILE_UNEXPECTED"
    }
  }

  fileprivate var sortKey: String {
    switch self {
    case .invalidConfigurationSchemaVersion:
      code
    case .duplicateLanguageProfile(let languageCode),
      .missingLanguageProfile(let languageCode),
      .unexpectedLanguageProfile(let languageCode):
      "\(code):\(languageCode)"
    }
  }
}

public enum GuidanceAudioAuthoringError:
  Error, Equatable, Sendable
{
  case invalidProductGuidance
  case worklistDrift
  case invalidConfiguration([GuidanceAudioAuthoringIssue])
  case invalidReview([GuidanceAudioReviewIssue])
  case resourceMissing(String)
  case resourceUnreadable(String)
  case invalidWaveAudio(String)
  case invalidRelease([GuidanceAudioReleaseIssue])
}

public enum GuidanceAudioRecordingWorklistCodec {
  public static func derive(
    productRelease: KaidoProductRelease
  ) throws -> GuidanceAudioRecordingWorklist {
    var items: [GuidanceAudioRecordingWorkItem] = []
    var keys: Set<GuidanceAudioAssetKey> = []
    var filenames: Set<String> = []

    for definition in productRelease.navigation.bundle.releasedGuidance {
      for locale in KaidoReleaseLocale.allCases {
        guard
          let content =
            definition.frameTemplate.presentationSource.localizedContent[
              locale
            ]
        else {
          throw GuidanceAudioAuthoringError.invalidProductGuidance
        }
        let spokenText = normalizedGuidanceAudioValue(
          content.spokenText
        )
        guard !spokenText.isEmpty else {
          throw GuidanceAudioAuthoringError.invalidProductGuidance
        }
        let key = GuidanceAudioAssetKey(
          promptID: definition.anchor.promptID,
          anchorID: definition.anchor.anchorID,
          anchorOccurrenceID: definition.anchor.occurrenceID,
          languageCode: locale.speechLanguageCode
        )
        guard keys.insert(key).inserted else {
          throw GuidanceAudioAuthoringError.invalidProductGuidance
        }
        let textHash = guidanceAudioSHA256Hex(Data(spokenText.utf8))
        let filename = suggestedFilename(
          key: key,
          spokenTextSHA256: textHash
        )
        guard filenames.insert(filename).inserted else {
          throw GuidanceAudioAuthoringError.invalidProductGuidance
        }
        items.append(
          GuidanceAudioRecordingWorkItem(
            key: key,
            spokenText: spokenText,
            spokenTextSHA256: textHash,
            suggestedResourceFilename: filename
          )
        )
      }
    }

    items.sort {
      canonicalGuidanceAudioKey($0.key)
        < canonicalGuidanceAudioKey($1.key)
    }
    return GuidanceAudioRecordingWorklist(
      productReleaseID: productRelease.releaseID,
      navigationReleaseID: productRelease.navigation.releaseID,
      networkSnapshotID:
        productRelease.navigation.bundle.networkSnapshot.id,
      routePlanID: productRelease.navigation.bundle.routePlan.id,
      items: items
    )
  }

  public static func encode(
    productRelease: KaidoProductRelease
  ) throws -> Data {
    let worklist = try derive(productRelease: productRelease)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(worklist)
  }

  public static func decode(
    _ data: Data,
    productRelease: KaidoProductRelease
  ) throws -> GuidanceAudioRecordingWorklist {
    let decoded = try JSONDecoder().decode(
      GuidanceAudioRecordingWorklist.self,
      from: data
    )
    guard
      decoded
        == (try derive(productRelease: productRelease))
    else {
      throw GuidanceAudioAuthoringError.worklistDrift
    }
    return decoded
  }

  private static func suggestedFilename(
    key: GuidanceAudioAssetKey,
    spokenTextSHA256: String
  ) -> String {
    let identity =
      canonicalGuidanceAudioKey(key)
      + ":\(spokenTextSHA256)"
    let identityHash = guidanceAudioSHA256Hex(Data(identity.utf8))
    let locale = key.languageCode.lowercased().map {
      $0.isLetter || $0.isNumber ? $0 : "-"
    }
    return "guidance-\(String(locale))-\(identityHash.prefix(20)).wav"
  }
}

public enum GuidanceAudioAuthoringConfigurationCodec {
  public static func encode(
    _ configuration: GuidanceAudioAuthoringConfiguration
  ) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(configuration)
  }

  public static func decode(
    _ data: Data
  ) throws -> GuidanceAudioAuthoringConfiguration {
    try JSONDecoder().decode(
      GuidanceAudioAuthoringConfiguration.self,
      from: data
    )
  }
}

public enum GuidanceAudioReleaseAuthor {
  public static func buildManifest(
    productRelease: KaidoProductRelease,
    configuration: GuidanceAudioAuthoringConfiguration,
    reviewChecklist: GuidanceAudioReviewChecklist,
    resourceProvider: (String) throws -> GuidanceAudioResource?
  ) throws -> GuidanceAudioReleaseManifest {
    let worklist = try GuidanceAudioRecordingWorklistCodec.derive(
      productRelease: productRelease
    )
    let profiles = try validatedProfiles(configuration)
    var resources: [String: GuidanceAudioResource] = [:]
    var metadataByFilename: [String: GuidanceWaveMetadata] = [:]
    var records: [GuidanceAudioAssetRecord] = []

    for item in worklist.items {
      let filename = item.suggestedResourceFilename
      let resource: GuidanceAudioResource?
      do {
        resource = try resourceProvider(filename)
      } catch {
        throw GuidanceAudioAuthoringError.resourceUnreadable(filename)
      }
      guard let resource else {
        throw GuidanceAudioAuthoringError.resourceMissing(filename)
      }
      guard let metadata = GuidanceWaveMetadata(data: resource.data) else {
        throw GuidanceAudioAuthoringError.invalidWaveAudio(filename)
      }
      resources[filename] = resource
      metadataByFilename[filename] = metadata
    }

    let provenanceByLanguage = profiles.mapValues(\.provenance)
    let reviews: [GuidanceAudioAssetKey: GuidanceAudioAssetReview]
    do {
      reviews = try GuidanceAudioReviewValidator.validate(
        reviewChecklist,
        productRelease: productRelease,
        worklist: worklist,
        releaseAt: configuration.releasedAt,
        provenanceByLanguage: provenanceByLanguage,
        resources: resources
      )
    } catch GuidanceAudioReviewError.invalid(let issues) {
      throw GuidanceAudioAuthoringError.invalidReview(issues)
    }

    for item in worklist.items {
      let filename = item.suggestedResourceFilename
      guard
        let resource = resources[filename],
        let metadata = metadataByFilename[filename],
        let profile = profiles[item.key.languageCode],
        let review = reviews[item.key]
      else {
        throw GuidanceAudioAuthoringError.invalidProductGuidance
      }
      records.append(
        GuidanceAudioAssetRecord(
          key: item.key,
          spokenText: item.spokenText,
          spokenTextSHA256: item.spokenTextSHA256,
          resourceFilename: filename,
          audioSHA256: guidanceAudioSHA256Hex(resource.data),
          byteCount: resource.data.count,
          sampleRateHz: metadata.sampleRateHz,
          channelCount: metadata.channelCount,
          durationMilliseconds: metadata.durationMilliseconds,
          provenance: profile.provenance,
          review: review
        )
      )
    }

    let manifest = GuidanceAudioReleaseManifest(
      releaseID: configuration.releaseID,
      releasedAt: configuration.releasedAt,
      productReleaseID: worklist.productReleaseID,
      navigationReleaseID: worklist.navigationReleaseID,
      networkSnapshotID: worklist.networkSnapshotID,
      routePlanID: worklist.routePlanID,
      assets: records
    )
    do {
      _ = try GuidanceAudioRelease(
        manifest: manifest,
        productRelease: productRelease,
        resourceProvider: { resources[$0] }
      )
    } catch GuidanceAudioReleaseError.invalid(let issues) {
      throw GuidanceAudioAuthoringError.invalidRelease(issues)
    }
    return manifest
  }

  private static func validatedProfiles(
    _ configuration: GuidanceAudioAuthoringConfiguration
  ) throws -> [String: GuidanceAudioLanguageProfile] {
    var issues: [GuidanceAudioAuthoringIssue] = []
    if configuration.schemaVersion
      != GuidanceAudioAuthoringConfiguration.currentSchemaVersion
    {
      issues.append(.invalidConfigurationSchemaVersion)
    }
    let expected = Set(
      KaidoReleaseLocale.allCases.map(\.speechLanguageCode)
    )
    var profiles: [String: GuidanceAudioLanguageProfile] = [:]
    for profile in configuration.languageProfiles {
      if profiles[profile.languageCode] != nil {
        issues.append(.duplicateLanguageProfile(profile.languageCode))
      } else {
        profiles[profile.languageCode] = profile
      }
      if !expected.contains(profile.languageCode) {
        issues.append(.unexpectedLanguageProfile(profile.languageCode))
      }
    }
    for languageCode in expected where profiles[languageCode] == nil {
      issues.append(.missingLanguageProfile(languageCode))
    }

    issues = sortedUnique(issues)
    guard issues.isEmpty else {
      throw GuidanceAudioAuthoringError.invalidConfiguration(issues)
    }
    return profiles
  }

  private static func sortedUnique(
    _ issues: [GuidanceAudioAuthoringIssue]
  ) -> [GuidanceAudioAuthoringIssue] {
    var result: [GuidanceAudioAuthoringIssue] = []
    for issue in issues.sorted(by: { $0.sortKey < $1.sortKey })
    where !result.contains(issue) {
      result.append(issue)
    }
    return result
  }
}

private func canonicalGuidanceAudioKey(
  _ key: GuidanceAudioAssetKey
) -> String {
  [
    key.anchorOccurrenceID,
    key.anchorID,
    key.promptID,
    key.languageCode,
  ].joined(separator: "\u{1f}")
}

private func normalizedGuidanceAudioValue(_ value: String) -> String {
  value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func guidanceAudioSHA256Hex(_ data: Data) -> String {
  SHA256.hash(data: data).map {
    String(format: "%02x", $0)
  }.joined()
}
