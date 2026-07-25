import Foundation

public enum SurfaceEgressGroundTruthEvidenceMethod:
  String, Codable, Equatable, Sendable
{
  case passengerObserved = "PASSENGER_OBSERVED"
  case reviewedPrivateMedia = "REVIEWED_PRIVATE_MEDIA"
  case controlledSurvey = "CONTROLLED_SURVEY"
  case syntheticTest = "SYNTHETIC_TEST"
}

public enum SurfaceEgressGroundTruthPrivacyClassification:
  String, Codable, Equatable, Sendable
{
  case privateGroundTruth = "PRIVATE_GROUND_TRUTH"
}

/// Private, independently reviewed truth for one exact calibration scope.
///
/// Observation IDs link to raw location entries, so this set is private input
/// and must never be committed as the coordinate-free public artifact.
public struct SurfaceEgressGroundTruthAnnotationSet:
  Codable, Equatable, Sendable
{
  public static let currentSchemaVersion = "1.0"

  public let schemaVersion: String
  public let reviewID: String
  public let reviewerID: String
  public let reviewedAt: String
  public let evidenceMethod: SurfaceEgressGroundTruthEvidenceMethod
  public let independentlyReviewed: Bool
  public let privacyClassification: SurfaceEgressGroundTruthPrivacyClassification
  public let scope: SurfaceEgressMatcherCalibrationScope
  public let annotations: [SurfaceEgressGroundTruthAnnotation]

  public init(
    schemaVersion: String =
      SurfaceEgressGroundTruthAnnotationSet.currentSchemaVersion,
    reviewID: String,
    reviewerID: String,
    reviewedAt: String,
    evidenceMethod: SurfaceEgressGroundTruthEvidenceMethod,
    independentlyReviewed: Bool,
    privacyClassification:
      SurfaceEgressGroundTruthPrivacyClassification = .privateGroundTruth,
    scope: SurfaceEgressMatcherCalibrationScope,
    annotations: [SurfaceEgressGroundTruthAnnotation]
  ) {
    self.schemaVersion = schemaVersion
    self.reviewID = reviewID
    self.reviewerID = reviewerID
    self.reviewedAt = reviewedAt
    self.evidenceMethod = evidenceMethod
    self.independentlyReviewed = independentlyReviewed
    self.privacyClassification = privacyClassification
    self.scope = scope
    self.annotations = annotations
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case reviewID = "review_id"
    case reviewerID = "reviewer_id"
    case reviewedAt = "reviewed_at"
    case evidenceMethod = "evidence_method"
    case independentlyReviewed = "independently_reviewed"
    case privacyClassification = "privacy_classification"
    case scope
    case annotations
  }
}

public struct SurfaceEgressMatcherCalibrationAuthoringConfiguration:
  Codable, Equatable, Sendable
{
  public static let currentSchemaVersion = "1.0"

  public let schemaVersion: String
  public let reportID: String
  public let generatedAt: String
  public let minimumHeldOutSamplesPerCohort: Int
  public let matcherP95BudgetMicroseconds: Int

  public init(
    schemaVersion: String =
      SurfaceEgressMatcherCalibrationAuthoringConfiguration.currentSchemaVersion,
    reportID: String,
    generatedAt: String,
    minimumHeldOutSamplesPerCohort: Int = 30,
    matcherP95BudgetMicroseconds: Int = 50_000
  ) {
    self.schemaVersion = schemaVersion
    self.reportID = reportID
    self.generatedAt = generatedAt
    self.minimumHeldOutSamplesPerCohort =
      minimumHeldOutSamplesPerCohort
    self.matcherP95BudgetMicroseconds = matcherP95BudgetMicroseconds
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case reportID = "report_id"
    case generatedAt = "generated_at"
    case minimumHeldOutSamplesPerCohort =
      "minimum_held_out_samples_per_cohort"
    case matcherP95BudgetMicroseconds = "matcher_p95_budget_us"
  }
}

/// Coordinate-free ground-truth provenance retained in the public artifact.
public struct SurfaceEgressGroundTruthReviewSummary:
  Codable, Equatable, Sendable
{
  public let reviewID: String
  public let reviewerID: String
  public let reviewedAt: String
  public let evidenceMethod: SurfaceEgressGroundTruthEvidenceMethod
  public let independentlyReviewed: Bool
  public let annotationCount: Int
  public let privateAnnotationSetSHA256: String

  public init(
    reviewID: String,
    reviewerID: String,
    reviewedAt: String,
    evidenceMethod: SurfaceEgressGroundTruthEvidenceMethod,
    independentlyReviewed: Bool,
    annotationCount: Int,
    privateAnnotationSetSHA256: String
  ) {
    self.reviewID = reviewID
    self.reviewerID = reviewerID
    self.reviewedAt = reviewedAt
    self.evidenceMethod = evidenceMethod
    self.independentlyReviewed = independentlyReviewed
    self.annotationCount = annotationCount
    self.privateAnnotationSetSHA256 = privateAnnotationSetSHA256
  }

  private enum CodingKeys: String, CodingKey {
    case reviewID = "review_id"
    case reviewerID = "reviewer_id"
    case reviewedAt = "reviewed_at"
    case evidenceMethod = "evidence_method"
    case independentlyReviewed = "independently_reviewed"
    case annotationCount = "annotation_count"
    case privateAnnotationSetSHA256 =
      "private_annotation_set_sha256"
  }
}

/// Public, coordinate-free artifact bound to exact private input bytes.
///
/// A statistical floor remains matcher evidence only. The two false authority
/// fields are invariant and make that non-release status explicit to consumers.
public struct SurfaceEgressMatcherCalibrationArtifact:
  Codable, Equatable, Sendable
{
  public static let currentSchemaVersion = "1.0"

  public let schemaVersion: String
  public let generatedAt: String
  public let report: SurfaceEgressMatcherCalibrationReport
  public let privateTraceSHA256: [String]
  public let groundTruthReview: SurfaceEgressGroundTruthReviewSummary
  public let navigationAuthority: Bool
  public let releaseApproval: Bool

  public init(
    schemaVersion: String =
      SurfaceEgressMatcherCalibrationArtifact.currentSchemaVersion,
    generatedAt: String,
    report: SurfaceEgressMatcherCalibrationReport,
    privateTraceSHA256: [String],
    groundTruthReview: SurfaceEgressGroundTruthReviewSummary,
    navigationAuthority: Bool = false,
    releaseApproval: Bool = false
  ) {
    self.schemaVersion = schemaVersion
    self.generatedAt = generatedAt
    self.report = report
    self.privateTraceSHA256 = privateTraceSHA256
    self.groundTruthReview = groundTruthReview
    self.navigationAuthority = navigationAuthority
    self.releaseApproval = releaseApproval
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case generatedAt = "generated_at"
    case report
    case privateTraceSHA256 = "private_trace_sha256"
    case groundTruthReview = "ground_truth_review"
    case navigationAuthority = "navigation_authority"
    case releaseApproval = "release_approval"
  }
}

public enum SurfaceEgressMatcherCalibrationArtifactIssue:
  String, Codable, Equatable, Sendable
{
  case invalidArtifactSchema =
    "SURFACE_EGRESS_CALIBRATION_ARTIFACT_SCHEMA_INVALID"
  case invalidArtifactTimestamp =
    "SURFACE_EGRESS_CALIBRATION_ARTIFACT_TIMESTAMP_INVALID"
  case invalidReport = "SURFACE_EGRESS_CALIBRATION_REPORT_INVALID"
  case invalidPrivateTraceDigests =
    "SURFACE_EGRESS_CALIBRATION_PRIVATE_TRACE_DIGESTS_INVALID"
  case privateTraceCountMismatch =
    "SURFACE_EGRESS_CALIBRATION_PRIVATE_TRACE_COUNT_MISMATCH"
  case invalidGroundTruthSummary =
    "SURFACE_EGRESS_CALIBRATION_GROUND_TRUTH_SUMMARY_INVALID"
  case groundTruthCountMismatch =
    "SURFACE_EGRESS_CALIBRATION_GROUND_TRUTH_COUNT_MISMATCH"
  case groundTruthChronologyInvalid =
    "SURFACE_EGRESS_CALIBRATION_GROUND_TRUTH_CHRONOLOGY_INVALID"
  case syntheticClassificationMismatch =
    "SURFACE_EGRESS_CALIBRATION_SYNTHETIC_CLASSIFICATION_MISMATCH"
  case navigationAuthorityPresent =
    "SURFACE_EGRESS_CALIBRATION_NAVIGATION_AUTHORITY_PRESENT"
  case releaseApprovalPresent =
    "SURFACE_EGRESS_CALIBRATION_RELEASE_APPROVAL_PRESENT"
}

public enum SurfaceEgressMatcherCalibrationArtifactValidator {
  public static func issues(
    in artifact: SurfaceEgressMatcherCalibrationArtifact
  ) -> [SurfaceEgressMatcherCalibrationArtifactIssue] {
    var issues: [SurfaceEgressMatcherCalibrationArtifactIssue] = []
    if artifact.schemaVersion
      != SurfaceEgressMatcherCalibrationArtifact.currentSchemaVersion
    {
      issues.append(.invalidArtifactSchema)
    }
    guard
      let generatedAt = parseISO8601(artifact.generatedAt)
    else {
      issues.append(.invalidArtifactTimestamp)
      return sorted(issues)
    }
    if !reportIsValid(artifact.report) {
      issues.append(.invalidReport)
    }
    let digests = artifact.privateTraceSHA256
    if digests.isEmpty
      || digests != digests.sorted()
      || Set(digests).count != digests.count
      || !digests.allSatisfy(isSHA256)
    {
      issues.append(.invalidPrivateTraceDigests)
    }
    if digests.count != artifact.report.traceCount {
      issues.append(.privateTraceCountMismatch)
    }
    let review = artifact.groundTruthReview
    if review.reviewID.trimmingCharacters(
      in: .whitespacesAndNewlines
    ).isEmpty
      || review.reviewerID.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty
      || !review.independentlyReviewed
      || review.annotationCount <= 0
      || !isSHA256(review.privateAnnotationSetSHA256)
    {
      issues.append(.invalidGroundTruthSummary)
    }
    if review.annotationCount != artifact.report.annotatedEntryCount {
      issues.append(.groundTruthCountMismatch)
    }
    if let reviewedAt = parseISO8601(review.reviewedAt) {
      if reviewedAt > generatedAt {
        issues.append(.groundTruthChronologyInvalid)
      }
    } else {
      issues.append(.invalidGroundTruthSummary)
    }
    let syntheticTrace =
      artifact.report.collectionMethod == .syntheticTest
    let syntheticTruth = review.evidenceMethod == .syntheticTest
    if syntheticTrace != syntheticTruth {
      issues.append(.syntheticClassificationMismatch)
    }
    if artifact.navigationAuthority {
      issues.append(.navigationAuthorityPresent)
    }
    if artifact.releaseApproval {
      issues.append(.releaseApprovalPresent)
    }
    return sorted(issues)
  }

  private static func reportIsValid(
    _ report: SurfaceEgressMatcherCalibrationReport
  ) -> Bool {
    guard
      report.schemaVersion
        == SurfaceEgressMatcherCalibrationReport.currentSchemaVersion,
      !report.reportID.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty,
      report.scope.validationIssues.isEmpty,
      report.traceCount > 0,
      report.entryCount > 0,
      report.traceCount <= report.entryCount,
      report.matchedEntryCount >= 0,
      report.adapterRejectionCount >= 0,
      report.matcherRejectionCount >= 0,
      report.matchedEntryCount + report.adapterRejectionCount
        + report.matcherRejectionCount == report.entryCount,
      report.annotatedEntryCount >= 0,
      report.unannotatedMatchedEntryCount >= 0,
      report.annotatedEntryCount + report.unannotatedMatchedEntryCount
        == report.matchedEntryCount,
      report.simulatedMatchedEntryCount >= 0,
      report.simulatedMatchedEntryCount <= report.matchedEntryCount,
      report.unsafeHighConfidenceEdgeCount >= 0,
      report.unsafeHighConfidenceEdgeCount
        <= report.annotatedEntryCount,
      report.unsafeHighConfidenceOccurrenceCount >= 0,
      report.unsafeHighConfidenceOccurrenceCount
        <= report.annotatedEntryCount,
      report.minimumHeldOutSamplesPerCohort > 0,
      report.matcherP95BudgetMicroseconds > 0,
      report.probabilityCalibrationStatus
        == .unavailableCategoricalConfidenceOnly
    else {
      return false
    }
    guard
      let adaptationP95Microseconds =
        report.adaptationP95Microseconds,
      adaptationP95Microseconds >= 0,
      let matcherP95Microseconds = report.matcherP95Microseconds,
      matcherP95Microseconds >= 0,
      let pipelineP95Microseconds = report.pipelineP95Microseconds,
      pipelineP95Microseconds >= 0
    else {
      return false
    }
    guard
      report.matcherP95BudgetMet
        == (matcherP95Microseconds
          <= report.matcherP95BudgetMicroseconds)
    else {
      return false
    }
    guard
      report.reliabilityBins.map(\.annotatedEdgeCount).reduce(0, +)
        == report.annotatedEntryCount,
      report.reliabilityBins.map(\.occurrenceTruthCount).reduce(0, +)
        == report.annotatedEntryCount
    else {
      return false
    }
    let binKeys = report.reliabilityBins.map {
      "\($0.partition.rawValue)|\($0.calibrationCohort.rawValue)|"
        + "\($0.producedByExternalAccessory)|\($0.simulatedBySoftware)|"
        + $0.confidence.rawValue
    }
    guard Set(binKeys).count == binKeys.count else {
      return false
    }
    for bin in report.reliabilityBins {
      let expectedEdgeAccuracy =
        Double(bin.correctEdgeCount) / Double(bin.annotatedEdgeCount)
      guard
        bin.annotatedEdgeCount > 0,
        bin.correctEdgeCount >= 0,
        bin.wrongEdgeCount >= 0,
        bin.abstainedEdgeCount >= 0,
        bin.correctEdgeCount + bin.wrongEdgeCount
          + bin.abstainedEdgeCount == bin.annotatedEdgeCount,
        bin.occurrenceTruthCount == bin.annotatedEdgeCount,
        bin.correctOccurrenceCount >= 0,
        bin.correctOccurrenceCount <= bin.occurrenceTruthCount,
        bin.observedEdgeAccuracy.map({
          $0.isFinite && (0...1).contains($0)
            && $0 == expectedEdgeAccuracy
        }) == true
      else {
        return false
      }
    }
    let highBins = report.reliabilityBins.filter {
      $0.confidence == .high
    }
    guard
      report.unsafeHighConfidenceEdgeCount
        == highBins.map(\.wrongEdgeCount).reduce(0, +),
      report.unsafeHighConfidenceOccurrenceCount
        == highBins.map({
          $0.occurrenceTruthCount - $0.correctOccurrenceCount
        }).reduce(0, +)
    else {
      return false
    }
    if report.unsafeHighConfidenceEdgeCount > 0
      || report.unsafeHighConfidenceOccurrenceCount > 0
    {
      return report.gateStatus == .unsafeHighConfidenceObserved
    }
    if report.collectionMethod == .syntheticTest {
      return report.gateStatus == .syntheticEvidenceOnly
    }
    if report.simulatedMatchedEntryCount > 0 {
      return report.gateStatus == .simulatedEvidencePresent
    }
    return report.gateStatus == .insufficientHeldOutEvidence
      || report.gateStatus == .statisticalFloorMet
  }

  private static func isSHA256(_ value: String) -> Bool {
    value.count == 64
      && value == value.lowercased()
      && value.unicodeScalars.allSatisfy {
        (Unicode.Scalar("0").value...Unicode.Scalar("9").value)
          .contains($0.value)
          || (Unicode.Scalar("a").value...Unicode.Scalar("f").value)
            .contains($0.value)
      }
  }

  private static func parseISO8601(_ value: String) -> Date? {
    let standard = ISO8601DateFormatter()
    if let date = standard.date(from: value) {
      return date
    }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [
      .withInternetDateTime,
      .withFractionalSeconds,
    ]
    return fractional.date(from: value)
  }

  private static func sorted(
    _ issues: [SurfaceEgressMatcherCalibrationArtifactIssue]
  ) -> [SurfaceEgressMatcherCalibrationArtifactIssue] {
    Array(Set(issues)).sorted { $0.rawValue < $1.rawValue }
  }
}

public enum SurfaceEgressGroundTruthAnnotationSetCodec {
  public static func encode(
    _ annotationSet: SurfaceEgressGroundTruthAnnotationSet
  ) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(annotationSet)
  }

  public static func decode(
    _ data: Data
  ) throws -> SurfaceEgressGroundTruthAnnotationSet {
    try JSONDecoder().decode(
      SurfaceEgressGroundTruthAnnotationSet.self,
      from: data
    )
  }
}

public enum SurfaceEgressMatcherCalibrationAuthoringConfigurationCodec {
  public static func encode(
    _ configuration:
      SurfaceEgressMatcherCalibrationAuthoringConfiguration
  ) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(configuration)
  }

  public static func decode(
    _ data: Data
  ) throws -> SurfaceEgressMatcherCalibrationAuthoringConfiguration {
    try JSONDecoder().decode(
      SurfaceEgressMatcherCalibrationAuthoringConfiguration.self,
      from: data
    )
  }
}

public enum SurfaceEgressMatcherCalibrationArtifactCodec {
  public static func encode(
    _ artifact: SurfaceEgressMatcherCalibrationArtifact
  ) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(artifact)
  }

  public static func decode(
    _ data: Data
  ) throws -> SurfaceEgressMatcherCalibrationArtifact {
    try JSONDecoder().decode(
      SurfaceEgressMatcherCalibrationArtifact.self,
      from: data
    )
  }
}
