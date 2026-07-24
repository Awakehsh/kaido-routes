import CryptoKit
import Foundation
import KaidoNavigation

public enum GuidanceAudioReviewStatus:
  String, Codable, Equatable, Sendable
{
  case pending = "PENDING"
  case passed = "PASSED"
  case rejected = "REJECTED"
}

/// Human review attached to one exact guidance WAV.
///
/// A release accepts only `PASSED` values. `PENDING` exists solely so the CLI
/// can prepare a complete identity- and hash-bound checklist before a reviewer
/// listens to the private audio files.
public struct GuidanceAudioAssetReview:
  Codable, Equatable, Sendable
{
  public let reviewerID: String
  public let reviewedAt: String
  public let pronunciation: GuidanceAudioReviewStatus
  public let intelligibility: GuidanceAudioReviewStatus
  public let audioQuality: GuidanceAudioReviewStatus

  public init(
    reviewerID: String,
    reviewedAt: String,
    pronunciation: GuidanceAudioReviewStatus,
    intelligibility: GuidanceAudioReviewStatus,
    audioQuality: GuidanceAudioReviewStatus
  ) {
    self.reviewerID = reviewerID
    self.reviewedAt = reviewedAt
    self.pronunciation = pronunciation
    self.intelligibility = intelligibility
    self.audioQuality = audioQuality
  }

  public static let pending = GuidanceAudioAssetReview(
    reviewerID: "",
    reviewedAt: "",
    pronunciation: .pending,
    intelligibility: .pending,
    audioQuality: .pending
  )

  private enum CodingKeys: String, CodingKey {
    case reviewerID = "reviewer_id"
    case reviewedAt = "reviewed_at"
    case pronunciation
    case intelligibility
    case audioQuality = "audio_quality"
  }
}

public struct GuidanceAudioReviewChecklistRecord:
  Codable, Equatable, Sendable
{
  public let key: GuidanceAudioAssetKey
  public let spokenTextSHA256: String
  public let resourceFilename: String
  public let audioSHA256: String
  public let review: GuidanceAudioAssetReview

  public init(
    key: GuidanceAudioAssetKey,
    spokenTextSHA256: String,
    resourceFilename: String,
    audioSHA256: String,
    review: GuidanceAudioAssetReview
  ) {
    self.key = key
    self.spokenTextSHA256 = spokenTextSHA256
    self.resourceFilename = resourceFilename
    self.audioSHA256 = audioSHA256
    self.review = review
  }

  private enum CodingKeys: String, CodingKey {
    case key
    case spokenTextSHA256 = "spoken_text_sha256"
    case resourceFilename = "resource_filename"
    case audioSHA256 = "audio_sha256"
    case review
  }
}

/// One complete private-audio review checklist for an exact product worklist.
///
/// It contains hashes and identities, never audio bytes. Preparation leaves
/// every decision pending. A human reviewer fills the review fields only after
/// listening to the exact hash-bound WAV.
public struct GuidanceAudioReviewChecklist:
  Codable, Equatable, Sendable
{
  public static let currentSchemaVersion = "1.0"

  public let schemaVersion: String
  public let reviewID: String
  public let productReleaseID: String
  public let navigationReleaseID: String
  public let networkSnapshotID: String
  public let routePlanID: String
  public let records: [GuidanceAudioReviewChecklistRecord]

  public init(
    schemaVersion: String =
      GuidanceAudioReviewChecklist.currentSchemaVersion,
    reviewID: String,
    productReleaseID: String,
    navigationReleaseID: String,
    networkSnapshotID: String,
    routePlanID: String,
    records: [GuidanceAudioReviewChecklistRecord]
  ) {
    self.schemaVersion = schemaVersion
    self.reviewID = reviewID
    self.productReleaseID = productReleaseID
    self.navigationReleaseID = navigationReleaseID
    self.networkSnapshotID = networkSnapshotID
    self.routePlanID = routePlanID
    self.records = records
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case reviewID = "review_id"
    case productReleaseID = "product_release_id"
    case navigationReleaseID = "navigation_release_id"
    case networkSnapshotID = "network_snapshot_id"
    case routePlanID = "route_plan_id"
    case records
  }
}

public enum GuidanceAudioReviewIssue: Equatable, Sendable {
  case invalidSchemaVersion
  case invalidReviewIdentity
  case productReleaseMismatch
  case navigationReleaseMismatch
  case networkSnapshotMismatch
  case routePlanMismatch
  case duplicateRecord(GuidanceAudioAssetKey)
  case missingRecord(GuidanceAudioAssetKey)
  case unexpectedRecord(GuidanceAudioAssetKey)
  case recordBindingMismatch(GuidanceAudioAssetKey)
  case invalidReviewer(GuidanceAudioAssetKey)
  case reviewIncomplete(GuidanceAudioAssetKey)
  case reviewChronologyInvalid(GuidanceAudioAssetKey)

  public var code: String {
    switch self {
    case .invalidSchemaVersion:
      "GUIDANCE_AUDIO_REVIEW_SCHEMA_VERSION_INVALID"
    case .invalidReviewIdentity:
      "GUIDANCE_AUDIO_REVIEW_IDENTITY_INVALID"
    case .productReleaseMismatch:
      "GUIDANCE_AUDIO_REVIEW_PRODUCT_RELEASE_MISMATCH"
    case .navigationReleaseMismatch:
      "GUIDANCE_AUDIO_REVIEW_NAVIGATION_RELEASE_MISMATCH"
    case .networkSnapshotMismatch:
      "GUIDANCE_AUDIO_REVIEW_NETWORK_SNAPSHOT_MISMATCH"
    case .routePlanMismatch:
      "GUIDANCE_AUDIO_REVIEW_ROUTE_PLAN_MISMATCH"
    case .duplicateRecord:
      "GUIDANCE_AUDIO_REVIEW_RECORD_DUPLICATE"
    case .missingRecord:
      "GUIDANCE_AUDIO_REVIEW_RECORD_MISSING"
    case .unexpectedRecord:
      "GUIDANCE_AUDIO_REVIEW_RECORD_UNEXPECTED"
    case .recordBindingMismatch:
      "GUIDANCE_AUDIO_REVIEW_RECORD_BINDING_MISMATCH"
    case .invalidReviewer:
      "GUIDANCE_AUDIO_REVIEW_REVIEWER_INVALID"
    case .reviewIncomplete:
      "GUIDANCE_AUDIO_REVIEW_INCOMPLETE"
    case .reviewChronologyInvalid:
      "GUIDANCE_AUDIO_REVIEW_CHRONOLOGY_INVALID"
    }
  }

  fileprivate var sortKey: String {
    switch self {
    case .duplicateRecord(let key),
      .missingRecord(let key),
      .unexpectedRecord(let key),
      .recordBindingMismatch(let key),
      .invalidReviewer(let key),
      .reviewIncomplete(let key),
      .reviewChronologyInvalid(let key):
      "\(code):\(guidanceAudioReviewKey(key))"
    default:
      code
    }
  }
}

public enum GuidanceAudioReviewError:
  Error, Equatable, Sendable
{
  case invalidReviewID
  case resourceMissing(String)
  case resourceUnreadable(String)
  case resourceURLInvalid(String)
  case resourceFilenameMismatch(String)
  case invalidWaveAudio(String)
  case invalid([GuidanceAudioReviewIssue])

  public var code: String {
    switch self {
    case .invalidReviewID:
      "GUIDANCE_AUDIO_REVIEW_IDENTITY_INVALID"
    case .resourceMissing:
      "GUIDANCE_AUDIO_REVIEW_RESOURCE_MISSING"
    case .resourceUnreadable:
      "GUIDANCE_AUDIO_REVIEW_RESOURCE_UNREADABLE"
    case .resourceURLInvalid:
      "GUIDANCE_AUDIO_REVIEW_RESOURCE_URL_INVALID"
    case .resourceFilenameMismatch:
      "GUIDANCE_AUDIO_REVIEW_RESOURCE_FILENAME_MISMATCH"
    case .invalidWaveAudio:
      "GUIDANCE_AUDIO_REVIEW_WAVE_INVALID"
    case .invalid:
      "GUIDANCE_AUDIO_REVIEW_INVALID"
    }
  }
}

public enum GuidanceAudioReviewChecklistCodec {
  public static func prepare(
    reviewID: String,
    productRelease: KaidoProductRelease,
    resourceProvider: (String) throws -> GuidanceAudioResource?
  ) throws -> GuidanceAudioReviewChecklist {
    guard isValidReviewValue(reviewID) else {
      throw GuidanceAudioReviewError.invalidReviewID
    }
    let worklist = try GuidanceAudioRecordingWorklistCodec.derive(
      productRelease: productRelease
    )
    var records: [GuidanceAudioReviewChecklistRecord] = []
    for item in worklist.items {
      let filename = item.suggestedResourceFilename
      let resource: GuidanceAudioResource?
      do {
        resource = try resourceProvider(filename)
      } catch {
        throw GuidanceAudioReviewError.resourceUnreadable(filename)
      }
      guard let resource else {
        throw GuidanceAudioReviewError.resourceMissing(filename)
      }
      guard resource.url.isFileURL else {
        throw GuidanceAudioReviewError.resourceURLInvalid(filename)
      }
      guard resource.url.lastPathComponent == filename else {
        throw GuidanceAudioReviewError.resourceFilenameMismatch(filename)
      }
      guard GuidanceWaveMetadata(data: resource.data) != nil else {
        throw GuidanceAudioReviewError.invalidWaveAudio(filename)
      }
      records.append(
        GuidanceAudioReviewChecklistRecord(
          key: item.key,
          spokenTextSHA256: item.spokenTextSHA256,
          resourceFilename: filename,
          audioSHA256: reviewSHA256Hex(resource.data),
          review: .pending
        )
      )
    }
    return GuidanceAudioReviewChecklist(
      reviewID: reviewID,
      productReleaseID: worklist.productReleaseID,
      navigationReleaseID: worklist.navigationReleaseID,
      networkSnapshotID: worklist.networkSnapshotID,
      routePlanID: worklist.routePlanID,
      records: records
    )
  }

  public static func encode(
    _ checklist: GuidanceAudioReviewChecklist
  ) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(checklist)
  }

  public static func decode(
    _ data: Data
  ) throws -> GuidanceAudioReviewChecklist {
    try JSONDecoder().decode(
      GuidanceAudioReviewChecklist.self,
      from: data
    )
  }
}

enum GuidanceAudioReviewValidator {
  static func validate(
    _ checklist: GuidanceAudioReviewChecklist,
    productRelease: KaidoProductRelease,
    worklist: GuidanceAudioRecordingWorklist,
    releaseAt: String,
    provenanceByLanguage: [String: GuidanceAudioSynthesisProvenance],
    resources: [String: GuidanceAudioResource]
  ) throws -> [GuidanceAudioAssetKey: GuidanceAudioAssetReview] {
    var issues: [GuidanceAudioReviewIssue] = []
    if checklist.schemaVersion
      != GuidanceAudioReviewChecklist.currentSchemaVersion
    {
      issues.append(.invalidSchemaVersion)
    }
    if !isValidReviewValue(checklist.reviewID) {
      issues.append(.invalidReviewIdentity)
    }
    if checklist.productReleaseID != productRelease.releaseID {
      issues.append(.productReleaseMismatch)
    }
    if checklist.navigationReleaseID
      != productRelease.navigation.releaseID
    {
      issues.append(.navigationReleaseMismatch)
    }
    if checklist.networkSnapshotID
      != productRelease.navigation.bundle.networkSnapshot.id
    {
      issues.append(.networkSnapshotMismatch)
    }
    if checklist.routePlanID
      != productRelease.navigation.bundle.routePlan.id
    {
      issues.append(.routePlanMismatch)
    }

    let expectedByKey = Dictionary(
      uniqueKeysWithValues: worklist.items.map { ($0.key, $0) }
    )
    var reviews: [GuidanceAudioAssetKey: GuidanceAudioAssetReview] = [:]
    for record in checklist.records {
      let key = record.key
      guard reviews[key] == nil else {
        issues.append(.duplicateRecord(key))
        continue
      }
      reviews[key] = record.review
      guard let expected = expectedByKey[key] else {
        issues.append(.unexpectedRecord(key))
        continue
      }
      guard
        let resource = resources[expected.suggestedResourceFilename],
        record.spokenTextSHA256 == expected.spokenTextSHA256,
        record.resourceFilename == expected.suggestedResourceFilename,
        record.audioSHA256 == reviewSHA256Hex(resource.data)
      else {
        issues.append(.recordBindingMismatch(key))
        continue
      }
      let review = record.review
      if !isValidReviewValue(review.reviewerID) {
        issues.append(.invalidReviewer(key))
      }
      if review.pronunciation != .passed
        || review.intelligibility != .passed
        || review.audioQuality != .passed
      {
        issues.append(.reviewIncomplete(key))
      }
      guard
        let provenance = provenanceByLanguage[key.languageCode],
        let generatedAt = reviewParseISO8601(provenance.generatedAt),
        let reviewedAt = reviewParseISO8601(review.reviewedAt),
        let profileReviewedAt = reviewParseISO8601(
          provenance.reviewedAt
        ),
        let releaseDate = reviewParseISO8601(releaseAt),
        generatedAt <= reviewedAt,
        reviewedAt <= profileReviewedAt,
        profileReviewedAt <= releaseDate
      else {
        issues.append(.reviewChronologyInvalid(key))
        continue
      }
    }
    for key in Set(expectedByKey.keys).subtracting(reviews.keys) {
      issues.append(.missingRecord(key))
    }

    issues = sortedUniqueReviewIssues(issues)
    guard issues.isEmpty else {
      throw GuidanceAudioReviewError.invalid(issues)
    }
    return reviews
  }
}

private func isValidReviewValue(_ value: String) -> Bool {
  !value.isEmpty
    && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func guidanceAudioReviewKey(
  _ key: GuidanceAudioAssetKey
) -> String {
  [
    key.anchorOccurrenceID,
    key.anchorID,
    key.promptID,
    key.languageCode,
  ].joined(separator: "\u{1f}")
}

private func reviewSHA256Hex(_ data: Data) -> String {
  SHA256.hash(data: data).map {
    String(format: "%02x", $0)
  }.joined()
}

private func reviewParseISO8601(_ value: String) -> Date? {
  let standard = ISO8601DateFormatter()
  if let result = standard.date(from: value) {
    return result
  }
  let fractional = ISO8601DateFormatter()
  fractional.formatOptions = [
    .withInternetDateTime,
    .withFractionalSeconds,
  ]
  return fractional.date(from: value)
}

private func sortedUniqueReviewIssues(
  _ issues: [GuidanceAudioReviewIssue]
) -> [GuidanceAudioReviewIssue] {
  var result: [GuidanceAudioReviewIssue] = []
  for issue in issues.sorted(by: { $0.sortKey < $1.sortKey })
  where !result.contains(issue) {
    result.append(issue)
  }
  return result
}
