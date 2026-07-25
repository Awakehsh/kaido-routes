import CryptoKit
import Foundation
import KaidoNavigation

public enum SurfaceEgressMatcherCalibrationAuthoringIssue:
  String, Codable, Equatable, Sendable
{
  case noPrivateTraces =
    "SURFACE_EGRESS_CALIBRATION_PRIVATE_TRACES_EMPTY"
  case invalidConfigurationSchema =
    "SURFACE_EGRESS_CALIBRATION_AUTHORING_SCHEMA_INVALID"
  case invalidConfigurationIdentity =
    "SURFACE_EGRESS_CALIBRATION_AUTHORING_IDENTITY_INVALID"
  case invalidConfigurationTimestamp =
    "SURFACE_EGRESS_CALIBRATION_AUTHORING_TIMESTAMP_INVALID"
  case invalidEvaluatorConfiguration =
    "SURFACE_EGRESS_CALIBRATION_EVALUATOR_CONFIGURATION_INVALID"
  case invalidAnnotationSetSchema =
    "SURFACE_EGRESS_CALIBRATION_ANNOTATION_SCHEMA_INVALID"
  case invalidAnnotationReviewIdentity =
    "SURFACE_EGRESS_CALIBRATION_ANNOTATION_REVIEW_IDENTITY_INVALID"
  case invalidAnnotationReviewTimestamp =
    "SURFACE_EGRESS_CALIBRATION_ANNOTATION_REVIEW_TIMESTAMP_INVALID"
  case independentAnnotationReviewRequired =
    "SURFACE_EGRESS_CALIBRATION_INDEPENDENT_ANNOTATION_REVIEW_REQUIRED"
  case annotationSetEmpty =
    "SURFACE_EGRESS_CALIBRATION_ANNOTATIONS_EMPTY"
  case annotationScopeMismatch =
    "SURFACE_EGRESS_CALIBRATION_ANNOTATION_SCOPE_MISMATCH"
  case annotationReviewBeforeCollection =
    "SURFACE_EGRESS_CALIBRATION_ANNOTATION_REVIEW_BEFORE_COLLECTION"
  case annotationReviewAfterReport =
    "SURFACE_EGRESS_CALIBRATION_ANNOTATION_REVIEW_AFTER_REPORT"
  case traceCollectionAfterReport =
    "SURFACE_EGRESS_CALIBRATION_TRACE_COLLECTION_AFTER_REPORT"
}

public enum SurfaceEgressMatcherCalibrationAuthoringError:
  Error, Equatable, Sendable
{
  case privateTraceDecodeFailed(Int)
  case annotationSetDecodeFailed
  case artifactDecodeFailed
  case invalidConfiguration(
    [SurfaceEgressMatcherCalibrationAuthoringIssue]
  )
  case invalidAnnotationSet(
    [SurfaceEgressMatcherCalibrationAuthoringIssue]
  )
  case evaluation(SurfaceEgressMatcherCalibrationEvaluatorError)
  case invalidArtifact(
    [SurfaceEgressMatcherCalibrationArtifactIssue]
  )
  case artifactContentMismatch

  public var redactedCodes: [String] {
    switch self {
    case .privateTraceDecodeFailed(let index):
      ["SURFACE_EGRESS_CALIBRATION_PRIVATE_TRACE_DECODE_FAILED:\(index)"]
    case .annotationSetDecodeFailed:
      ["SURFACE_EGRESS_CALIBRATION_ANNOTATION_SET_DECODE_FAILED"]
    case .artifactDecodeFailed:
      ["SURFACE_EGRESS_CALIBRATION_ARTIFACT_DECODE_FAILED"]
    case .invalidConfiguration(let issues),
      .invalidAnnotationSet(let issues):
      issues.map(\.rawValue)
    case .evaluation:
      ["SURFACE_EGRESS_CALIBRATION_EVALUATION_FAILED"]
    case .invalidArtifact(let issues):
      issues.map(\.rawValue)
    case .artifactContentMismatch:
      ["SURFACE_EGRESS_CALIBRATION_ARTIFACT_CONTENT_MISMATCH"]
    }
  }
}

/// Converts exact private input bytes into one auditable coordinate-free artifact.
///
/// Hashes are calculated over the bytes supplied to this API. Revalidation
/// requires those same private bytes and independently re-runs the evaluator.
public enum SurfaceEgressMatcherCalibrationArtifactAuthor {
  public static func build(
    privateTraceData: [Data],
    privateAnnotationSetData: Data,
    configuration:
      SurfaceEgressMatcherCalibrationAuthoringConfiguration
  ) throws -> SurfaceEgressMatcherCalibrationArtifact {
    let configurationIssues = validate(configuration)
    guard configurationIssues.isEmpty else {
      throw
        SurfaceEgressMatcherCalibrationAuthoringError
        .invalidConfiguration(configurationIssues)
    }
    guard !privateTraceData.isEmpty else {
      throw
        SurfaceEgressMatcherCalibrationAuthoringError
        .invalidConfiguration([.noPrivateTraces])
    }

    let decoder = JSONDecoder()
    let traces: [SurfaceEgressPrivateTrace] =
      try privateTraceData
      .enumerated().map { index, data in
        do {
          return try decoder.decode(
            SurfaceEgressPrivateTrace.self,
            from: data
          )
        } catch {
          throw
            SurfaceEgressMatcherCalibrationAuthoringError
            .privateTraceDecodeFailed(index)
        }
      }
    let annotationSet: SurfaceEgressGroundTruthAnnotationSet
    do {
      annotationSet = try decoder.decode(
        SurfaceEgressGroundTruthAnnotationSet.self,
        from: privateAnnotationSetData
      )
    } catch {
      throw SurfaceEgressMatcherCalibrationAuthoringError
        .annotationSetDecodeFailed
    }
    let annotationIssues = validate(
      annotationSet,
      traces: traces,
      generatedAt: configuration.generatedAt
    )
    guard annotationIssues.isEmpty else {
      throw
        SurfaceEgressMatcherCalibrationAuthoringError
        .invalidAnnotationSet(annotationIssues)
    }

    let report: SurfaceEgressMatcherCalibrationReport
    do {
      report = try SurfaceEgressMatcherCalibrationEvaluator.evaluate(
        traces: traces,
        annotations: annotationSet.annotations,
        reportID: configuration.reportID,
        configuration: MatcherCalibrationEvaluatorConfiguration(
          minimumHeldOutSamplesPerCohort:
            configuration.minimumHeldOutSamplesPerCohort,
          matcherP95BudgetMicroseconds:
            configuration.matcherP95BudgetMicroseconds
        )
      )
    } catch let error as SurfaceEgressMatcherCalibrationEvaluatorError {
      throw SurfaceEgressMatcherCalibrationAuthoringError.evaluation(
        error
      )
    }

    let artifact = SurfaceEgressMatcherCalibrationArtifact(
      generatedAt: configuration.generatedAt,
      report: report,
      privateTraceSHA256: privateTraceData.map(sha256Hex).sorted(),
      groundTruthReview: SurfaceEgressGroundTruthReviewSummary(
        reviewID: annotationSet.reviewID,
        reviewerID: annotationSet.reviewerID,
        reviewedAt: annotationSet.reviewedAt,
        evidenceMethod: annotationSet.evidenceMethod,
        independentlyReviewed: annotationSet.independentlyReviewed,
        annotationCount: annotationSet.annotations.count,
        privateAnnotationSetSHA256: sha256Hex(
          privateAnnotationSetData
        )
      )
    )
    let artifactIssues =
      SurfaceEgressMatcherCalibrationArtifactValidator.issues(
        in: artifact
      )
    guard artifactIssues.isEmpty else {
      throw SurfaceEgressMatcherCalibrationAuthoringError.invalidArtifact(
        artifactIssues
      )
    }
    return artifact
  }

  public static func validate(
    artifactData: Data,
    privateTraceData: [Data],
    privateAnnotationSetData: Data
  ) throws -> SurfaceEgressMatcherCalibrationArtifact {
    let artifact: SurfaceEgressMatcherCalibrationArtifact
    do {
      artifact = try SurfaceEgressMatcherCalibrationArtifactCodec.decode(
        artifactData
      )
    } catch {
      throw SurfaceEgressMatcherCalibrationAuthoringError
        .artifactDecodeFailed
    }
    let artifactIssues =
      SurfaceEgressMatcherCalibrationArtifactValidator.issues(
        in: artifact
      )
    guard artifactIssues.isEmpty else {
      throw SurfaceEgressMatcherCalibrationAuthoringError.invalidArtifact(
        artifactIssues
      )
    }
    let rebuilt = try build(
      privateTraceData: privateTraceData,
      privateAnnotationSetData: privateAnnotationSetData,
      configuration:
        SurfaceEgressMatcherCalibrationAuthoringConfiguration(
          reportID: artifact.report.reportID,
          generatedAt: artifact.generatedAt,
          minimumHeldOutSamplesPerCohort:
            artifact.report.minimumHeldOutSamplesPerCohort,
          matcherP95BudgetMicroseconds:
            artifact.report.matcherP95BudgetMicroseconds
        )
    )
    guard rebuilt == artifact else {
      throw SurfaceEgressMatcherCalibrationAuthoringError
        .artifactContentMismatch
    }
    return artifact
  }

  private static func validate(
    _ configuration:
      SurfaceEgressMatcherCalibrationAuthoringConfiguration
  ) -> [SurfaceEgressMatcherCalibrationAuthoringIssue] {
    var issues: [SurfaceEgressMatcherCalibrationAuthoringIssue] = []
    if configuration.schemaVersion
      != SurfaceEgressMatcherCalibrationAuthoringConfiguration
      .currentSchemaVersion
    {
      issues.append(.invalidConfigurationSchema)
    }
    if configuration.reportID.trimmingCharacters(
      in: .whitespacesAndNewlines
    ).isEmpty {
      issues.append(.invalidConfigurationIdentity)
    }
    if parseISO8601(configuration.generatedAt) == nil {
      issues.append(.invalidConfigurationTimestamp)
    }
    if configuration.minimumHeldOutSamplesPerCohort <= 0
      || configuration.matcherP95BudgetMicroseconds <= 0
    {
      issues.append(.invalidEvaluatorConfiguration)
    }
    return sorted(issues)
  }

  private static func validate(
    _ annotationSet: SurfaceEgressGroundTruthAnnotationSet,
    traces: [SurfaceEgressPrivateTrace],
    generatedAt: String
  ) -> [SurfaceEgressMatcherCalibrationAuthoringIssue] {
    var issues: [SurfaceEgressMatcherCalibrationAuthoringIssue] = []
    if annotationSet.schemaVersion
      != SurfaceEgressGroundTruthAnnotationSet.currentSchemaVersion
    {
      issues.append(.invalidAnnotationSetSchema)
    }
    if annotationSet.reviewID.trimmingCharacters(
      in: .whitespacesAndNewlines
    ).isEmpty
      || annotationSet.reviewerID.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty
    {
      issues.append(.invalidAnnotationReviewIdentity)
    }
    let reviewedAt = parseISO8601(annotationSet.reviewedAt)
    if reviewedAt == nil {
      issues.append(.invalidAnnotationReviewTimestamp)
    }
    if !annotationSet.independentlyReviewed {
      issues.append(.independentAnnotationReviewRequired)
    }
    if annotationSet.annotations.isEmpty {
      issues.append(.annotationSetEmpty)
    }
    if annotationSet.scope.validationIssues.isEmpty == false
      || traces.contains(where: {
        $0.context.scope != annotationSet.scope
      })
    {
      issues.append(.annotationScopeMismatch)
    }
    if let generatedAt = parseISO8601(generatedAt) {
      let generatedAtMilliseconds =
        generatedAt.timeIntervalSince1970 * 1_000
      let latestCollectionMilliseconds =
        traces.flatMap { trace in
          [trace.context.startedAtMilliseconds]
            + trace.entries.compactMap {
              $0.observation?.receivedAtMilliseconds
            }
        }.max()
      if latestCollectionMilliseconds.map({
        Double($0) > generatedAtMilliseconds
      }) == true {
        issues.append(.traceCollectionAfterReport)
      }
      if let reviewedAt {
        if reviewedAt > generatedAt {
          issues.append(.annotationReviewAfterReport)
        }
        if latestCollectionMilliseconds.map({
          reviewedAt.timeIntervalSince1970 * 1_000 < Double($0)
        }) == true {
          issues.append(.annotationReviewBeforeCollection)
        }
      }
    }
    return sorted(issues)
  }

  private static func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map {
      String(format: "%02x", $0)
    }.joined()
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
    _ issues: [SurfaceEgressMatcherCalibrationAuthoringIssue]
  ) -> [SurfaceEgressMatcherCalibrationAuthoringIssue] {
    Array(Set(issues)).sorted { $0.rawValue < $1.rawValue }
  }
}
