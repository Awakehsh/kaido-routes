import CryptoKit
import Foundation
import KaidoDomain
import KaidoNavigation
import KaidoPresentation

public enum GuidanceAudioGenerationMode: String, Codable, Sendable {
  case localOpenWeight = "LOCAL_OPEN_WEIGHT"
  case cloudPreGenerated = "CLOUD_PREGENERATED"
  case humanRecorded = "HUMAN_RECORDED"
}

public enum GuidanceAudioEncoding: String, Codable, Sendable {
  case wavPCM16LittleEndian = "WAV_PCM_S16LE"
}

public enum GuidanceAudioEvidenceScope: String, Codable, Sendable {
  case syntheticTestOnly = "SYNTHETIC_TEST_ONLY"
  case releasedAsset = "RELEASED_ASSET"
}

public enum GuidanceAudioRedistributionDecision:
  String, Codable, Sendable
{
  case syntheticTestOnly = "SYNTHETIC_TEST_ONLY"
  case approvedForAppDistribution = "APPROVED_FOR_APP_DISTRIBUTION"
}

public enum GuidanceAudioModelArtifactKind:
  String, Codable, Sendable
{
  case notApplicable = "NOT_APPLICABLE"
  case originalCheckpoint = "ORIGINAL_CHECKPOINT"
  case convertedCheckpoint = "CONVERTED_CHECKPOINT"
}

public struct GuidanceAudioConvertedModelLineage:
  Codable, Equatable, Sendable
{
  public let upstreamModelID: String
  public let upstreamModelRevision: String
  public let upstreamLicenceIdentifier: String
  public let upstreamSourceURL: String
  public let conversionEngineID: String
  public let conversionEngineVersion: String
  public let conversionEngineRevision: String
  public let conversionSourceURL: String

  public init(
    upstreamModelID: String,
    upstreamModelRevision: String,
    upstreamLicenceIdentifier: String,
    upstreamSourceURL: String,
    conversionEngineID: String,
    conversionEngineVersion: String,
    conversionEngineRevision: String,
    conversionSourceURL: String
  ) {
    self.upstreamModelID = upstreamModelID
    self.upstreamModelRevision = upstreamModelRevision
    self.upstreamLicenceIdentifier = upstreamLicenceIdentifier
    self.upstreamSourceURL = upstreamSourceURL
    self.conversionEngineID = conversionEngineID
    self.conversionEngineVersion = conversionEngineVersion
    self.conversionEngineRevision = conversionEngineRevision
    self.conversionSourceURL = conversionSourceURL
  }

  private enum CodingKeys: String, CodingKey {
    case upstreamModelID = "upstream_model_id"
    case upstreamModelRevision = "upstream_model_revision"
    case upstreamLicenceIdentifier = "upstream_licence_identifier"
    case upstreamSourceURL = "upstream_source_url"
    case conversionEngineID = "conversion_engine_id"
    case conversionEngineVersion = "conversion_engine_version"
    case conversionEngineRevision = "conversion_engine_revision"
    case conversionSourceURL = "conversion_source_url"
  }
}

public struct GuidanceAudioSynthesisProvenance: Codable, Equatable, Sendable {
  public let evidenceScope: GuidanceAudioEvidenceScope
  public let generationMode: GuidanceAudioGenerationMode
  public let engineID: String
  public let engineVersion: String
  public let modelID: String
  public let modelRevision: String
  public let modelArtifactKind: GuidanceAudioModelArtifactKind
  public let convertedModelLineage: GuidanceAudioConvertedModelLineage?
  public let voiceID: String
  public let licenceIdentifier: String
  public let sourceURL: String
  public let redistributionDecision: GuidanceAudioRedistributionDecision
  public let redistributionReviewID: String
  public let redistributionReviewSHA256: String
  public let generatedAt: String
  public let reviewedAt: String

  public init(
    evidenceScope: GuidanceAudioEvidenceScope,
    generationMode: GuidanceAudioGenerationMode,
    engineID: String,
    engineVersion: String,
    modelID: String,
    modelRevision: String,
    modelArtifactKind: GuidanceAudioModelArtifactKind,
    convertedModelLineage: GuidanceAudioConvertedModelLineage?,
    voiceID: String,
    licenceIdentifier: String,
    sourceURL: String,
    redistributionDecision: GuidanceAudioRedistributionDecision,
    redistributionReviewID: String,
    redistributionReviewSHA256: String,
    generatedAt: String,
    reviewedAt: String
  ) {
    self.evidenceScope = evidenceScope
    self.generationMode = generationMode
    self.engineID = engineID
    self.engineVersion = engineVersion
    self.modelID = modelID
    self.modelRevision = modelRevision
    self.modelArtifactKind = modelArtifactKind
    self.convertedModelLineage = convertedModelLineage
    self.voiceID = voiceID
    self.licenceIdentifier = licenceIdentifier
    self.sourceURL = sourceURL
    self.redistributionDecision = redistributionDecision
    self.redistributionReviewID = redistributionReviewID
    self.redistributionReviewSHA256 = redistributionReviewSHA256
    self.generatedAt = generatedAt
    self.reviewedAt = reviewedAt
  }

  private enum CodingKeys: String, CodingKey {
    case evidenceScope = "evidence_scope"
    case generationMode = "generation_mode"
    case engineID = "engine_id"
    case engineVersion = "engine_version"
    case modelID = "model_id"
    case modelRevision = "model_revision"
    case modelArtifactKind = "model_artifact_kind"
    case convertedModelLineage = "converted_model_lineage"
    case voiceID = "voice_id"
    case licenceIdentifier = "licence_identifier"
    case sourceURL = "source_url"
    case redistributionDecision = "redistribution_decision"
    case redistributionReviewID = "redistribution_review_id"
    case redistributionReviewSHA256 = "redistribution_review_sha256"
    case generatedAt = "generated_at"
    case reviewedAt = "reviewed_at"
  }
}

public struct GuidanceAudioAssetKey: Codable, Equatable, Hashable, Sendable {
  public let promptID: String
  public let anchorID: String
  public let anchorOccurrenceID: String
  public let languageCode: String

  public init(
    promptID: String,
    anchorID: String,
    anchorOccurrenceID: String,
    languageCode: String
  ) {
    self.promptID = promptID
    self.anchorID = anchorID
    self.anchorOccurrenceID = anchorOccurrenceID
    self.languageCode = languageCode
  }

  private enum CodingKeys: String, CodingKey {
    case promptID = "prompt_id"
    case anchorID = "anchor_id"
    case anchorOccurrenceID = "anchor_occurrence_id"
    case languageCode = "language_code"
  }

  fileprivate var sortKey: String {
    "\(anchorOccurrenceID):\(anchorID):\(promptID):\(languageCode)"
  }
}

public struct GuidanceAudioAssetRecord: Codable, Equatable, Sendable {
  public let key: GuidanceAudioAssetKey
  public let spokenText: String
  public let spokenTextSHA256: String
  public let resourceFilename: String
  public let audioSHA256: String
  public let audioEncoding: GuidanceAudioEncoding
  public let byteCount: Int
  public let sampleRateHz: Int
  public let channelCount: Int
  public let durationMilliseconds: Int
  public let provenance: GuidanceAudioSynthesisProvenance
  public let review: GuidanceAudioAssetReview

  public init(
    key: GuidanceAudioAssetKey,
    spokenText: String,
    spokenTextSHA256: String,
    resourceFilename: String,
    audioSHA256: String,
    audioEncoding: GuidanceAudioEncoding = .wavPCM16LittleEndian,
    byteCount: Int,
    sampleRateHz: Int,
    channelCount: Int,
    durationMilliseconds: Int,
    provenance: GuidanceAudioSynthesisProvenance,
    review: GuidanceAudioAssetReview
  ) {
    self.key = key
    self.spokenText = spokenText
    self.spokenTextSHA256 = spokenTextSHA256
    self.resourceFilename = resourceFilename
    self.audioSHA256 = audioSHA256
    self.audioEncoding = audioEncoding
    self.byteCount = byteCount
    self.sampleRateHz = sampleRateHz
    self.channelCount = channelCount
    self.durationMilliseconds = durationMilliseconds
    self.provenance = provenance
    self.review = review
  }

  private enum CodingKeys: String, CodingKey {
    case key
    case spokenText = "spoken_text"
    case spokenTextSHA256 = "spoken_text_sha256"
    case resourceFilename = "resource_filename"
    case audioSHA256 = "audio_sha256"
    case audioEncoding = "audio_encoding"
    case byteCount = "byte_count"
    case sampleRateHz = "sample_rate_hz"
    case channelCount = "channel_count"
    case durationMilliseconds = "duration_milliseconds"
    case provenance
    case review
  }
}

/// A complete, reviewed, offline audio pack for one exact product release.
///
/// A pack covers every released guidance anchor in all release locales. It is
/// optional at the product level, but once present it is all-or-nothing: a
/// missing, extra, corrupt, or identity-drifted record rejects the whole pack.
public struct GuidanceAudioReleaseManifest: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = "1.4"

  public let schemaVersion: String
  public let releaseID: String
  public let releasedAt: String
  public let productReleaseID: String
  public let navigationReleaseID: String
  public let networkSnapshotID: String
  public let routePlanID: String
  public let assets: [GuidanceAudioAssetRecord]

  public init(
    schemaVersion: String = GuidanceAudioReleaseManifest.currentSchemaVersion,
    releaseID: String,
    releasedAt: String,
    productReleaseID: String,
    navigationReleaseID: String,
    networkSnapshotID: String,
    routePlanID: String,
    assets: [GuidanceAudioAssetRecord]
  ) {
    self.schemaVersion = schemaVersion
    self.releaseID = releaseID
    self.releasedAt = releasedAt
    self.productReleaseID = productReleaseID
    self.navigationReleaseID = navigationReleaseID
    self.networkSnapshotID = networkSnapshotID
    self.routePlanID = routePlanID
    self.assets = assets
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case releaseID = "release_id"
    case releasedAt = "released_at"
    case productReleaseID = "product_release_id"
    case navigationReleaseID = "navigation_release_id"
    case networkSnapshotID = "network_snapshot_id"
    case routePlanID = "route_plan_id"
    case assets
  }
}

public struct GuidanceAudioResource: Equatable, Sendable {
  public let url: URL
  public let data: Data
  /// Manifest-owned name used for exact record validation.
  ///
  /// The App bundle may give two independently released packs distinct
  /// physical filenames while preserving the reviewed logical filename in
  /// each unchanged manifest.
  public let logicalFilename: String

  public init(
    url: URL,
    data: Data,
    logicalFilename: String? = nil
  ) {
    self.url = url
    self.data = data
    self.logicalFilename = logicalFilename ?? url.lastPathComponent
  }
}

public struct ReleasedGuidanceAudioAsset: Equatable, Sendable {
  public let record: GuidanceAudioAssetRecord
  public let resourceURL: URL

  public init(record: GuidanceAudioAssetRecord, resourceURL: URL) {
    self.record = record
    self.resourceURL = resourceURL
  }
}

public enum GuidanceAudioReleaseIssue: Equatable, Sendable {
  case invalidSchemaVersion
  case invalidReleaseIdentity
  case productReleaseMismatch
  case navigationReleaseMismatch
  case networkSnapshotMismatch
  case routePlanMismatch
  case duplicateAsset(GuidanceAudioAssetKey)
  case missingAsset(GuidanceAudioAssetKey)
  case unexpectedAsset(GuidanceAudioAssetKey)
  case invalidAssetRecord(GuidanceAudioAssetKey)
  case spokenTextMismatch(GuidanceAudioAssetKey)
  case spokenTextHashMismatch(GuidanceAudioAssetKey)
  case invalidProvenance(GuidanceAudioAssetKey)
  case provenanceScopeMismatch(GuidanceAudioAssetKey)
  case invalidReview(GuidanceAudioAssetKey)
  case resourceMissing(String)
  case resourceURLInvalid(String)
  case resourceFilenameMismatch(String)
  case resourceHashMismatch(String)
  case resourceByteCountMismatch(String)
  case invalidWaveAudio(String)
  case waveMetadataMismatch(String)

  public var code: String {
    switch self {
    case .invalidSchemaVersion:
      "GUIDANCE_AUDIO_SCHEMA_VERSION_INVALID"
    case .invalidReleaseIdentity:
      "GUIDANCE_AUDIO_RELEASE_IDENTITY_INVALID"
    case .productReleaseMismatch:
      "GUIDANCE_AUDIO_PRODUCT_RELEASE_MISMATCH"
    case .navigationReleaseMismatch:
      "GUIDANCE_AUDIO_NAVIGATION_RELEASE_MISMATCH"
    case .networkSnapshotMismatch:
      "GUIDANCE_AUDIO_NETWORK_SNAPSHOT_MISMATCH"
    case .routePlanMismatch:
      "GUIDANCE_AUDIO_ROUTE_PLAN_MISMATCH"
    case .duplicateAsset:
      "GUIDANCE_AUDIO_ASSET_DUPLICATE"
    case .missingAsset:
      "GUIDANCE_AUDIO_ASSET_MISSING"
    case .unexpectedAsset:
      "GUIDANCE_AUDIO_ASSET_UNEXPECTED"
    case .invalidAssetRecord:
      "GUIDANCE_AUDIO_ASSET_RECORD_INVALID"
    case .spokenTextMismatch:
      "GUIDANCE_AUDIO_SPOKEN_TEXT_MISMATCH"
    case .spokenTextHashMismatch:
      "GUIDANCE_AUDIO_SPOKEN_TEXT_HASH_MISMATCH"
    case .invalidProvenance:
      "GUIDANCE_AUDIO_PROVENANCE_INVALID"
    case .provenanceScopeMismatch:
      "GUIDANCE_AUDIO_PROVENANCE_SCOPE_MISMATCH"
    case .invalidReview:
      "GUIDANCE_AUDIO_REVIEW_INVALID"
    case .resourceMissing:
      "GUIDANCE_AUDIO_RESOURCE_MISSING"
    case .resourceURLInvalid:
      "GUIDANCE_AUDIO_RESOURCE_URL_INVALID"
    case .resourceFilenameMismatch:
      "GUIDANCE_AUDIO_RESOURCE_FILENAME_MISMATCH"
    case .resourceHashMismatch:
      "GUIDANCE_AUDIO_RESOURCE_HASH_MISMATCH"
    case .resourceByteCountMismatch:
      "GUIDANCE_AUDIO_RESOURCE_BYTE_COUNT_MISMATCH"
    case .invalidWaveAudio:
      "GUIDANCE_AUDIO_WAVE_INVALID"
    case .waveMetadataMismatch:
      "GUIDANCE_AUDIO_WAVE_METADATA_MISMATCH"
    }
  }

  fileprivate var sortKey: String {
    switch self {
    case .duplicateAsset(let key),
      .missingAsset(let key),
      .unexpectedAsset(let key),
      .invalidAssetRecord(let key),
      .spokenTextMismatch(let key),
      .spokenTextHashMismatch(let key),
      .invalidProvenance(let key),
      .provenanceScopeMismatch(let key),
      .invalidReview(let key):
      "\(code):\(key.sortKey)"
    case .resourceMissing(let filename),
      .resourceURLInvalid(let filename),
      .resourceFilenameMismatch(let filename),
      .resourceHashMismatch(let filename),
      .resourceByteCountMismatch(let filename),
      .invalidWaveAudio(let filename),
      .waveMetadataMismatch(let filename):
      "\(code):\(filename)"
    default:
      code
    }
  }
}

public enum GuidanceAudioReleaseError: Error, Equatable, Sendable {
  case invalid([GuidanceAudioReleaseIssue])
}

/// A fully validated audio pack with exact command-to-file resolution.
public struct GuidanceAudioRelease: Equatable, Sendable {
  public let manifest: GuidanceAudioReleaseManifest
  public let assets: [ReleasedGuidanceAudioAsset]

  private let assetByKey: [GuidanceAudioAssetKey: ReleasedGuidanceAudioAsset]

  public init(
    manifest: GuidanceAudioReleaseManifest,
    productRelease: KaidoProductRelease,
    resourceProvider: (String) throws -> GuidanceAudioResource?
  ) throws {
    var issues: [GuidanceAudioReleaseIssue] = []

    if manifest.schemaVersion
      != GuidanceAudioReleaseManifest.currentSchemaVersion
    {
      issues.append(.invalidSchemaVersion)
    }
    if Self.normalized(manifest.releaseID).isEmpty
      || !Self.isISO8601DateTime(manifest.releasedAt)
    {
      issues.append(.invalidReleaseIdentity)
    }
    if manifest.productReleaseID != productRelease.releaseID {
      issues.append(.productReleaseMismatch)
    }
    if manifest.navigationReleaseID != productRelease.navigation.releaseID {
      issues.append(.navigationReleaseMismatch)
    }
    if manifest.networkSnapshotID
      != productRelease.navigation.bundle.networkSnapshot.id
    {
      issues.append(.networkSnapshotMismatch)
    }
    if manifest.routePlanID != productRelease.navigation.bundle.routePlan.id {
      issues.append(.routePlanMismatch)
    }

    let expectedTextByKey = Self.expectedTextByKey(productRelease)
    let expectedEvidenceScope: GuidanceAudioEvidenceScope =
      productRelease.runtimeUse.evidenceScope == .releasedRoad
      ? .releasedAsset : .syntheticTestOnly
    let expectedKeys = Set(expectedTextByKey.keys)
    var seenKeys: Set<GuidanceAudioAssetKey> = []
    var loadedAssets: [ReleasedGuidanceAudioAsset] = []

    for record in manifest.assets {
      let key = record.key
      if !seenKeys.insert(key).inserted {
        issues.append(.duplicateAsset(key))
        continue
      }
      if !expectedKeys.contains(key) {
        issues.append(.unexpectedAsset(key))
      }
      if !Self.isValid(record) {
        issues.append(.invalidAssetRecord(key))
      }
      if let expectedText = expectedTextByKey[key],
        record.spokenText != expectedText
      {
        issues.append(.spokenTextMismatch(key))
      }
      if record.spokenTextSHA256.lowercased()
        != Self.sha256Hex(Data(record.spokenText.utf8))
      {
        issues.append(.spokenTextHashMismatch(key))
      }
      if !Self.isValid(
        record.provenance,
        noLaterThan: manifest.releasedAt
      ) {
        issues.append(.invalidProvenance(key))
      }
      if record.provenance.evidenceScope != expectedEvidenceScope {
        issues.append(.provenanceScopeMismatch(key))
      }
      if !Self.isValid(
        record.review,
        provenance: record.provenance,
        noLaterThan: manifest.releasedAt
      ) {
        issues.append(.invalidReview(key))
      }
      guard Self.isSafeWaveFilename(record.resourceFilename) else {
        continue
      }

      let resource: GuidanceAudioResource?
      do {
        resource = try resourceProvider(record.resourceFilename)
      } catch {
        resource = nil
      }
      guard let resource else {
        issues.append(.resourceMissing(record.resourceFilename))
        continue
      }
      if !resource.url.isFileURL {
        issues.append(.resourceURLInvalid(record.resourceFilename))
      }
      if resource.logicalFilename != record.resourceFilename {
        issues.append(.resourceFilenameMismatch(record.resourceFilename))
      }
      if resource.data.count != record.byteCount {
        issues.append(.resourceByteCountMismatch(record.resourceFilename))
      }
      if Self.sha256Hex(resource.data) != record.audioSHA256.lowercased() {
        issues.append(.resourceHashMismatch(record.resourceFilename))
      }
      if let metadata = GuidanceWaveMetadata(data: resource.data) {
        if metadata.sampleRateHz != record.sampleRateHz
          || metadata.channelCount != record.channelCount
          || metadata.durationMilliseconds != record.durationMilliseconds
        {
          issues.append(.waveMetadataMismatch(record.resourceFilename))
        }
      } else {
        issues.append(.invalidWaveAudio(record.resourceFilename))
      }
      loadedAssets.append(
        ReleasedGuidanceAudioAsset(
          record: record,
          resourceURL: resource.url
        )
      )
    }

    for key in expectedKeys.subtracting(seenKeys) {
      issues.append(.missingAsset(key))
    }

    issues = Self.sortedUnique(issues)
    guard issues.isEmpty else {
      throw GuidanceAudioReleaseError.invalid(issues)
    }

    let sortedAssets = loadedAssets.sorted {
      $0.record.key.sortKey < $1.record.key.sortKey
    }
    self.manifest = manifest
    assets = sortedAssets
    assetByKey = Dictionary(
      uniqueKeysWithValues: sortedAssets.map {
        ($0.record.key, $0)
      }
    )
  }

  /// Returns an asset only for the exact released command.
  ///
  /// A nil result is intentionally safe for a composite output to route through
  /// its already-reviewed Apple TTS fallback. It never performs fuzzy text,
  /// locale, prompt, or occurrence matching.
  public func asset(
    matching command: GuidanceSpeechCommand
  ) -> ReleasedGuidanceAudioAsset? {
    guard command.routePlanID == manifest.routePlanID else { return nil }
    let key = GuidanceAudioAssetKey(
      promptID: command.identity.promptID,
      anchorID: command.identity.anchorID,
      anchorOccurrenceID: command.identity.anchorOccurrenceID,
      languageCode: command.languageCode
    )
    guard let asset = assetByKey[key] else { return nil }
    guard asset.record.spokenText == command.spokenText else { return nil }
    return asset
  }

  private static func expectedTextByKey(
    _ productRelease: KaidoProductRelease
  ) -> [GuidanceAudioAssetKey: String] {
    var result: [GuidanceAudioAssetKey: String] = [:]
    for definition in productRelease.navigation.bundle.releasedGuidance {
      for locale in KaidoReleaseLocale.allCases {
        guard
          let content =
            definition.frameTemplate.presentationSource.localizedContent[
              locale
            ]
        else {
          continue
        }
        let key = GuidanceAudioAssetKey(
          promptID: definition.anchor.promptID,
          anchorID: definition.anchor.anchorID,
          anchorOccurrenceID: definition.anchor.occurrenceID,
          languageCode: locale.speechLanguageCode
        )
        result[key] = normalized(content.spokenText)
      }
    }
    return result
  }

  private static func isValid(_ record: GuidanceAudioAssetRecord) -> Bool {
    let key = record.key
    return
      !normalized(key.promptID).isEmpty
      && key.promptID == normalized(key.promptID)
      && !normalized(key.anchorID).isEmpty
      && key.anchorID == normalized(key.anchorID)
      && !normalized(key.anchorOccurrenceID).isEmpty
      && key.anchorOccurrenceID == normalized(key.anchorOccurrenceID)
      && !normalized(key.languageCode).isEmpty
      && key.languageCode == normalized(key.languageCode)
      && !normalized(record.spokenText).isEmpty
      && record.spokenText == normalized(record.spokenText)
      && isSHA256(record.spokenTextSHA256)
      && isSafeWaveFilename(record.resourceFilename)
      && isSHA256(record.audioSHA256)
      && record.audioEncoding == .wavPCM16LittleEndian
      && record.byteCount > 44
      && (8_000...96_000).contains(record.sampleRateHz)
      && record.channelCount == 1
      && record.durationMilliseconds > 0
  }

  private static func isValid(
    _ provenance: GuidanceAudioSynthesisProvenance,
    noLaterThan releasedAt: String
  ) -> Bool {
    let required = [
      provenance.engineID,
      provenance.engineVersion,
      provenance.modelID,
      provenance.modelRevision,
      provenance.voiceID,
      provenance.licenceIdentifier,
      provenance.sourceURL,
      provenance.redistributionReviewID,
    ]
    guard
      required.allSatisfy({
        !$0.isEmpty && $0 == normalized($0)
      }),
      isSHA256(provenance.redistributionReviewSHA256),
      let sourceURL = URL(string: provenance.sourceURL),
      sourceURL.scheme == "https",
      let generatedAt = parseISO8601(provenance.generatedAt),
      let reviewedAt = parseISO8601(provenance.reviewedAt),
      let releaseDate = parseISO8601(releasedAt),
      generatedAt <= reviewedAt,
      reviewedAt <= releaseDate
    else {
      return false
    }
    switch provenance.evidenceScope {
    case .syntheticTestOnly:
      guard
        provenance.redistributionDecision == .syntheticTestOnly,
        provenance.licenceIdentifier == "SYNTHETIC_TEST_ONLY"
      else {
        return false
      }
    case .releasedAsset:
      guard
        provenance.redistributionDecision
          == .approvedForAppDistribution,
        provenance.licenceIdentifier != "SYNTHETIC_TEST_ONLY"
      else {
        return false
      }
    }
    if provenance.generationMode == .localOpenWeight {
      guard
        isImmutableOpenWeightRevision(provenance.modelRevision),
        provenance.sourceURL.contains(provenance.modelRevision)
      else {
        return false
      }
      switch provenance.modelArtifactKind {
      case .notApplicable:
        return false
      case .originalCheckpoint:
        guard provenance.convertedModelLineage == nil else {
          return false
        }
      case .convertedCheckpoint:
        guard
          let lineage = provenance.convertedModelLineage,
          isValid(
            lineage,
            evidenceScope: provenance.evidenceScope
          )
        else {
          return false
        }
      }
    } else {
      guard
        provenance.modelArtifactKind == .notApplicable,
        provenance.convertedModelLineage == nil
      else {
        return false
      }
    }
    return true
  }

  private static func isValid(
    _ lineage: GuidanceAudioConvertedModelLineage,
    evidenceScope: GuidanceAudioEvidenceScope
  ) -> Bool {
    let required = [
      lineage.upstreamModelID,
      lineage.upstreamModelRevision,
      lineage.upstreamLicenceIdentifier,
      lineage.upstreamSourceURL,
      lineage.conversionEngineID,
      lineage.conversionEngineVersion,
      lineage.conversionEngineRevision,
      lineage.conversionSourceURL,
    ]
    guard
      required.allSatisfy({
        !$0.isEmpty && $0 == normalized($0)
      }),
      isImmutableOpenWeightRevision(lineage.upstreamModelRevision),
      isImmutableOpenWeightRevision(lineage.conversionEngineRevision),
      let upstreamSourceURL = URL(string: lineage.upstreamSourceURL),
      upstreamSourceURL.scheme == "https",
      lineage.upstreamSourceURL.contains(lineage.upstreamModelRevision),
      let conversionSourceURL = URL(string: lineage.conversionSourceURL),
      conversionSourceURL.scheme == "https",
      lineage.conversionSourceURL.contains(
        lineage.conversionEngineRevision
      )
    else {
      return false
    }
    if evidenceScope == .releasedAsset {
      return
        lineage.upstreamLicenceIdentifier != "SYNTHETIC_TEST_ONLY"
    }
    return true
  }

  private static func isValid(
    _ review: GuidanceAudioAssetReview,
    provenance: GuidanceAudioSynthesisProvenance,
    noLaterThan releasedAt: String
  ) -> Bool {
    guard
      !normalized(review.reviewerID).isEmpty,
      review.reviewerID == normalized(review.reviewerID),
      review.pronunciation == .passed,
      review.intelligibility == .passed,
      review.audioQuality == .passed,
      let generatedAt = parseISO8601(provenance.generatedAt),
      let assetReviewedAt = parseISO8601(review.reviewedAt),
      let profileReviewedAt = parseISO8601(provenance.reviewedAt),
      let releaseDate = parseISO8601(releasedAt),
      generatedAt <= assetReviewedAt,
      assetReviewedAt <= profileReviewedAt,
      profileReviewedAt <= releaseDate
    else {
      return false
    }
    return true
  }

  private static func isSafeWaveFilename(_ value: String) -> Bool {
    let parts = value.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 2, parts[1].lowercased() == "wav" else {
      return false
    }
    return !parts[0].isEmpty
      && parts[0].allSatisfy {
        $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_"
      }
  }

  private static func isSHA256(_ value: String) -> Bool {
    let digest = value.lowercased()
    return digest.count == 64
      && digest.allSatisfy {
        ("0"..."9").contains($0) || ("a"..."f").contains($0)
      }
  }

  private static func isImmutableOpenWeightRevision(_ value: String) -> Bool {
    (value.count == 40 || value.count == 64)
      && value == value.lowercased()
      && value.allSatisfy {
        ("0"..."9").contains($0) || ("a"..."f").contains($0)
      }
  }

  private static func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map {
      String(format: "%02x", $0)
    }.joined()
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
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

  private static func isISO8601DateTime(_ value: String) -> Bool {
    parseISO8601(value) != nil
  }

  private static func sortedUnique(
    _ issues: [GuidanceAudioReleaseIssue]
  ) -> [GuidanceAudioReleaseIssue] {
    var result: [GuidanceAudioReleaseIssue] = []
    for issue in issues.sorted(by: { $0.sortKey < $1.sortKey })
    where !result.contains(issue) {
      result.append(issue)
    }
    return result
  }
}

public enum GuidanceAudioReleaseManifestCodec {
  public static func encode(
    _ manifest: GuidanceAudioReleaseManifest,
    productRelease: KaidoProductRelease,
    resourceProvider: (String) throws -> GuidanceAudioResource?
  ) throws -> Data {
    _ = try GuidanceAudioRelease(
      manifest: manifest,
      productRelease: productRelease,
      resourceProvider: resourceProvider
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(manifest)
  }

  public static func decode(
    _ data: Data,
    productRelease: KaidoProductRelease,
    resourceProvider: (String) throws -> GuidanceAudioResource?
  ) throws -> GuidanceAudioRelease {
    let manifest = try JSONDecoder().decode(
      GuidanceAudioReleaseManifest.self,
      from: data
    )
    return try GuidanceAudioRelease(
      manifest: manifest,
      productRelease: productRelease,
      resourceProvider: resourceProvider
    )
  }
}

struct GuidanceWaveMetadata {
  let channelCount: Int
  let sampleRateHz: Int
  let durationMilliseconds: Int

  init?(data: Data) {
    let bytes = [UInt8](data)
    guard
      bytes.count >= 44,
      Self.ascii(bytes, 0, 4) == "RIFF",
      Self.ascii(bytes, 8, 4) == "WAVE",
      let riffByteCount = Self.uint32(bytes, 4),
      Int(riffByteCount) + 8 == bytes.count
    else {
      return nil
    }

    var format:
      (
        encoding: Int,
        channels: Int,
        sampleRate: Int,
        byteRate: Int,
        blockAlign: Int,
        bitsPerSample: Int
      )?
    var audioDataByteCount: Int?
    var audioDataOffset: Int?
    var offset = 12
    while offset + 8 <= bytes.count {
      guard let chunkSizeValue = Self.uint32(bytes, offset + 4) else {
        return nil
      }
      let chunkSize = Int(chunkSizeValue)
      let payloadOffset = offset + 8
      guard
        chunkSize >= 0,
        payloadOffset <= bytes.count,
        chunkSize <= bytes.count - payloadOffset
      else {
        return nil
      }

      let chunkID = Self.ascii(bytes, offset, 4)
      if chunkID == "fmt " {
        guard
          chunkSize >= 16,
          let encoding = Self.uint16(bytes, payloadOffset),
          let channels = Self.uint16(bytes, payloadOffset + 2),
          let sampleRate = Self.uint32(bytes, payloadOffset + 4),
          let byteRate = Self.uint32(bytes, payloadOffset + 8),
          let blockAlign = Self.uint16(bytes, payloadOffset + 12),
          let bitsPerSample = Self.uint16(bytes, payloadOffset + 14)
        else {
          return nil
        }
        format = (
          Int(encoding),
          Int(channels),
          Int(sampleRate),
          Int(byteRate),
          Int(blockAlign),
          Int(bitsPerSample)
        )
      } else if chunkID == "data" {
        audioDataByteCount = chunkSize
        audioDataOffset = payloadOffset
      }

      let paddedSize = chunkSize + (chunkSize.isMultiple(of: 2) ? 0 : 1)
      guard paddedSize <= bytes.count - payloadOffset else { return nil }
      offset = payloadOffset + paddedSize
    }

    guard
      offset == bytes.count,
      let format,
      let audioDataByteCount,
      let audioDataOffset,
      format.encoding == 1,
      format.channels > 0,
      format.sampleRate > 0,
      format.bitsPerSample == 16,
      format.blockAlign
        == format.channels * (format.bitsPerSample / 8),
      format.byteRate == format.sampleRate * format.blockAlign,
      audioDataByteCount.isMultiple(of: format.blockAlign),
      Self.containsSignal(
        bytes,
        offset: audioDataOffset,
        byteCount: audioDataByteCount
      )
    else {
      return nil
    }

    channelCount = format.channels
    sampleRateHz = format.sampleRate
    durationMilliseconds = Int(
      (Int64(audioDataByteCount) * 1_000
        + Int64(format.byteRate / 2))
        / Int64(format.byteRate)
    )
  }

  private static func ascii(
    _ bytes: [UInt8],
    _ offset: Int,
    _ count: Int
  ) -> String? {
    guard
      offset >= 0,
      count >= 0,
      offset <= bytes.count,
      count <= bytes.count - offset
    else {
      return nil
    }
    return String(bytes: bytes[offset..<(offset + count)], encoding: .ascii)
  }

  private static func uint16(
    _ bytes: [UInt8],
    _ offset: Int
  ) -> UInt16? {
    guard offset >= 0, offset + 2 <= bytes.count else { return nil }
    return UInt16(bytes[offset])
      | (UInt16(bytes[offset + 1]) << 8)
  }

  private static func uint32(
    _ bytes: [UInt8],
    _ offset: Int
  ) -> UInt32? {
    guard offset >= 0, offset + 4 <= bytes.count else { return nil }
    return UInt32(bytes[offset])
      | (UInt32(bytes[offset + 1]) << 8)
      | (UInt32(bytes[offset + 2]) << 16)
      | (UInt32(bytes[offset + 3]) << 24)
  }

  private static func containsSignal(
    _ bytes: [UInt8],
    offset: Int,
    byteCount: Int
  ) -> Bool {
    guard
      offset >= 0,
      byteCount >= 2,
      byteCount.isMultiple(of: 2),
      offset <= bytes.count,
      byteCount <= bytes.count - offset
    else {
      return false
    }
    var sampleOffset = offset
    let endOffset = offset + byteCount
    while sampleOffset < endOffset {
      guard let sampleBits = uint16(bytes, sampleOffset) else { return false }
      let sample = Int(Int16(bitPattern: sampleBits))
      if abs(sample) >= 64 {
        return true
      }
      sampleOffset += 2
    }
    return false
  }
}
