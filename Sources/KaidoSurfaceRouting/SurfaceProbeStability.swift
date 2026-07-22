import Foundation

public enum SurfaceProbeStabilityAssessment: String, Codable, Sendable {
  case stablePass = "STABLE_PASS"
  case variablePass = "VARIABLE_PASS"
  case fail = "FAIL"
}

public struct SurfaceProbeIntegerDistribution: Codable, Equatable, Sendable {
  public let minimum: Int
  public let median: Double
  public let percentile95: Int
  public let maximum: Int

  public init(minimum: Int, median: Double, percentile95: Int, maximum: Int) {
    self.minimum = minimum
    self.median = median
    self.percentile95 = percentile95
    self.maximum = maximum
  }

  private enum CodingKeys: String, CodingKey {
    case minimum
    case median
    case percentile95 = "percentile_95"
    case maximum
  }
}

public struct SurfaceProbeDoubleRange: Codable, Equatable, Sendable {
  public let minimum: Double
  public let maximum: Double

  public init(minimum: Double, maximum: Double) {
    self.minimum = minimum
    self.maximum = maximum
  }
}

public struct SurfaceProbeCountRange: Codable, Equatable, Sendable {
  public let minimum: Int
  public let maximum: Int

  public init(minimum: Int, maximum: Int) {
    self.minimum = minimum
    self.maximum = maximum
  }
}

/// A low-retention comparison of repeated surface probes.
///
/// The summary deliberately excludes coordinates, instructions, edge IDs, path
/// hashes, and provider candidate IDs. It reports only counts and scalar ranges.
/// `SCALAR_LOCAL_ONLY` does not imply that provider terms have been reviewed.
public struct SurfaceProbeStabilitySummary: Codable, Equatable, Sendable {
  public let schemaVersion: String
  public let fixtureID: String
  public let originID: String
  public let provider: SurfaceRouteProviderMetadata
  public let observedFrom: String
  public let observedThrough: String
  public let retentionClassification: ProbeRetentionClassification
  public let runCount: Int
  public let passingRunCount: Int
  public let failingRunCount: Int
  public let assessment: SurfaceProbeStabilityAssessment
  public let responseStatusCounts: [String: Int]
  public let hardGateFailureCounts: [String: Int]
  public let providerLatencyMilliseconds: SurfaceProbeIntegerDistribution
  public let inspectionLatencyPerRunMilliseconds: SurfaceProbeIntegerDistribution?
  public let acceptedCandidateCountRange: SurfaceProbeCountRange
  public let acceptedDistanceMeters: SurfaceProbeDoubleRange?
  public let acceptedTravelTimeSeconds: SurfaceProbeDoubleRange?
  public let terminalDistanceMeters: SurfaceProbeDoubleRange?
  public let terminalBearingDegrees: SurfaceProbeDoubleRange?
  public let acceptedResolvedPathVariantCount: Int
  public let acceptedRouteSetVariantCount: Int
  public let acceptedApproachEdgeVariantCount: Int
  public let missingResolvedPathEvaluationCount: Int
  public let maximumUnmatchedSampleCount: Int
  public let maximumAmbiguousEdgeCount: Int
  public let maximumDisconnectedEdgeCount: Int

  fileprivate init(
    fixtureID: String,
    originID: String,
    provider: SurfaceRouteProviderMetadata,
    observedFrom: String,
    observedThrough: String,
    runCount: Int,
    passingRunCount: Int,
    assessment: SurfaceProbeStabilityAssessment,
    responseStatusCounts: [String: Int],
    hardGateFailureCounts: [String: Int],
    providerLatencyMilliseconds: SurfaceProbeIntegerDistribution,
    inspectionLatencyPerRunMilliseconds: SurfaceProbeIntegerDistribution?,
    acceptedCandidateCountRange: SurfaceProbeCountRange,
    acceptedDistanceMeters: SurfaceProbeDoubleRange?,
    acceptedTravelTimeSeconds: SurfaceProbeDoubleRange?,
    terminalDistanceMeters: SurfaceProbeDoubleRange?,
    terminalBearingDegrees: SurfaceProbeDoubleRange?,
    acceptedResolvedPathVariantCount: Int,
    acceptedRouteSetVariantCount: Int,
    acceptedApproachEdgeVariantCount: Int,
    missingResolvedPathEvaluationCount: Int,
    maximumUnmatchedSampleCount: Int,
    maximumAmbiguousEdgeCount: Int,
    maximumDisconnectedEdgeCount: Int
  ) {
    schemaVersion = "1.0"
    self.fixtureID = fixtureID
    self.originID = originID
    self.provider = provider
    self.observedFrom = observedFrom
    self.observedThrough = observedThrough
    retentionClassification = .scalarLocalOnly
    self.runCount = runCount
    self.passingRunCount = passingRunCount
    failingRunCount = runCount - passingRunCount
    self.assessment = assessment
    self.responseStatusCounts = responseStatusCounts
    self.hardGateFailureCounts = hardGateFailureCounts
    self.providerLatencyMilliseconds = providerLatencyMilliseconds
    self.inspectionLatencyPerRunMilliseconds = inspectionLatencyPerRunMilliseconds
    self.acceptedCandidateCountRange = acceptedCandidateCountRange
    self.acceptedDistanceMeters = acceptedDistanceMeters
    self.acceptedTravelTimeSeconds = acceptedTravelTimeSeconds
    self.terminalDistanceMeters = terminalDistanceMeters
    self.terminalBearingDegrees = terminalBearingDegrees
    self.acceptedResolvedPathVariantCount = acceptedResolvedPathVariantCount
    self.acceptedRouteSetVariantCount = acceptedRouteSetVariantCount
    self.acceptedApproachEdgeVariantCount = acceptedApproachEdgeVariantCount
    self.missingResolvedPathEvaluationCount = missingResolvedPathEvaluationCount
    self.maximumUnmatchedSampleCount = maximumUnmatchedSampleCount
    self.maximumAmbiguousEdgeCount = maximumAmbiguousEdgeCount
    self.maximumDisconnectedEdgeCount = maximumDisconnectedEdgeCount
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case fixtureID = "fixture_id"
    case originID = "origin_id"
    case provider
    case observedFrom = "observed_from"
    case observedThrough = "observed_through"
    case retentionClassification = "retention_classification"
    case runCount = "run_count"
    case passingRunCount = "passing_run_count"
    case failingRunCount = "failing_run_count"
    case assessment
    case responseStatusCounts = "response_status_counts"
    case hardGateFailureCounts = "hard_gate_failure_counts"
    case providerLatencyMilliseconds = "provider_latency_milliseconds"
    case inspectionLatencyPerRunMilliseconds = "inspection_latency_per_run_milliseconds"
    case acceptedCandidateCountRange = "accepted_candidate_count_range"
    case acceptedDistanceMeters = "accepted_distance_meters"
    case acceptedTravelTimeSeconds = "accepted_travel_time_seconds"
    case terminalDistanceMeters = "terminal_distance_meters"
    case terminalBearingDegrees = "terminal_bearing_degrees"
    case acceptedResolvedPathVariantCount = "accepted_resolved_path_variant_count"
    case acceptedRouteSetVariantCount = "accepted_route_set_variant_count"
    case acceptedApproachEdgeVariantCount = "accepted_approach_edge_variant_count"
    case missingResolvedPathEvaluationCount = "missing_resolved_path_evaluation_count"
    case maximumUnmatchedSampleCount = "maximum_unmatched_sample_count"
    case maximumAmbiguousEdgeCount = "maximum_ambiguous_edge_count"
    case maximumDisconnectedEdgeCount = "maximum_disconnected_edge_count"
  }
}

/// A conservative scalar-only comparison of stability summaries from separate
/// observation windows. Provider path identity remains intentionally absent.
public struct SurfaceProbeCrossWindowSummary: Codable, Equatable, Sendable {
  public let schemaVersion: String
  public let fixtureID: String
  public let originID: String
  public let provider: SurfaceRouteProviderMetadata
  public let observedFrom: String
  public let observedThrough: String
  public let retentionClassification: ProbeRetentionClassification
  public let windowCount: Int
  public let runCount: Int
  public let passingRunCount: Int
  public let failingRunCount: Int
  public let assessment: SurfaceProbeStabilityAssessment
  public let batchAssessmentCounts: [String: Int]
  public let acceptedDistanceMeters: SurfaceProbeDoubleRange?
  public let scalarVariationReasons: [String]
  public let routeIdentityComparableAcrossWindows: Bool

  fileprivate init(
    fixtureID: String,
    originID: String,
    provider: SurfaceRouteProviderMetadata,
    observedFrom: String,
    observedThrough: String,
    windowCount: Int,
    runCount: Int,
    passingRunCount: Int,
    failingRunCount: Int,
    assessment: SurfaceProbeStabilityAssessment,
    batchAssessmentCounts: [String: Int],
    acceptedDistanceMeters: SurfaceProbeDoubleRange?,
    scalarVariationReasons: [String]
  ) {
    schemaVersion = "1.0"
    self.fixtureID = fixtureID
    self.originID = originID
    self.provider = provider
    self.observedFrom = observedFrom
    self.observedThrough = observedThrough
    retentionClassification = .scalarLocalOnly
    self.windowCount = windowCount
    self.runCount = runCount
    self.passingRunCount = passingRunCount
    self.failingRunCount = failingRunCount
    self.assessment = assessment
    self.batchAssessmentCounts = batchAssessmentCounts
    self.acceptedDistanceMeters = acceptedDistanceMeters
    self.scalarVariationReasons = scalarVariationReasons
    routeIdentityComparableAcrossWindows = false
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case fixtureID = "fixture_id"
    case originID = "origin_id"
    case provider
    case observedFrom = "observed_from"
    case observedThrough = "observed_through"
    case retentionClassification = "retention_classification"
    case windowCount = "window_count"
    case runCount = "run_count"
    case passingRunCount = "passing_run_count"
    case failingRunCount = "failing_run_count"
    case assessment
    case batchAssessmentCounts = "batch_assessment_counts"
    case acceptedDistanceMeters = "accepted_distance_meters"
    case scalarVariationReasons = "scalar_variation_reasons"
    case routeIdentityComparableAcrossWindows = "route_identity_comparable_across_windows"
  }
}

public enum SurfaceProbeStabilityError: Error, Equatable, Sendable {
  case noResults
  case insufficientWindows
  case inconsistentFixture
  case inconsistentOrigin
  case inconsistentProvider
}

public enum SurfaceProbeStabilitySummarizer {
  public static func summarize(
    _ results: [SurfaceProbeResult]
  ) throws -> SurfaceProbeStabilitySummary {
    guard let first = results.first else { throw SurfaceProbeStabilityError.noResults }
    guard results.allSatisfy({ $0.fixtureID == first.fixtureID }) else {
      throw SurfaceProbeStabilityError.inconsistentFixture
    }
    guard results.allSatisfy({ $0.originID == first.originID }) else {
      throw SurfaceProbeStabilityError.inconsistentOrigin
    }
    guard results.allSatisfy({ $0.provider == first.provider }) else {
      throw SurfaceProbeStabilityError.inconsistentProvider
    }

    let acceptedByRun = results.map { result in
      result.evaluations.filter(\.isAccepted)
    }
    let acceptedEvaluations = acceptedByRun.flatMap { $0 }
    let pathSignatures = acceptedEvaluations.map { evaluation -> String in
      guard let edgeIDs = evaluation.inspection?.resolvedPathEdgeIDs,
        !edgeIDs.isEmpty
      else { return "<missing>" }
      return edgeIDs.joined(separator: "\u{1f}")
    }
    let routeSetSignatures = acceptedByRun.map { evaluations in
      evaluations.map { evaluation -> String in
        guard let edgeIDs = evaluation.inspection?.resolvedPathEdgeIDs,
          !edgeIDs.isEmpty
        else { return "<missing>" }
        return edgeIDs.joined(separator: "\u{1f}")
      }
      .sorted()
      .joined(separator: "\u{1e}")
    }
    let approachEdgeIDs = acceptedEvaluations.compactMap {
      $0.inspection?.anchorBinding?.directedSurfaceEdgeID
    }
    let missingPathCount = pathSignatures.count { $0 == "<missing>" }
    let passingRunCount = results.count { $0.decision == .pass }
    let routeSetVariantCount = Set(routeSetSignatures).count
    let approachVariantCount = Set(approachEdgeIDs).count

    let assessment: SurfaceProbeStabilityAssessment
    if passingRunCount != results.count {
      assessment = .fail
    } else if routeSetVariantCount != 1 || approachVariantCount != 1 || missingPathCount > 0 {
      assessment = .variablePass
    } else {
      assessment = .stablePass
    }

    let responseStatusCounts = counts(results.map { $0.responseStatus.rawValue })
    let failedHardGates = results.flatMap(\.evaluations).flatMap(\.hardGates)
      .filter { $0.status == .fail }
      .map { $0.gate.rawValue }
    let inspectionLatencies = results.compactMap { result -> Int? in
      let values = result.evaluations.compactMap(\.inspectionLatencyMilliseconds)
      return values.isEmpty ? nil : values.reduce(0, +)
    }
    let inspections = results.flatMap(\.evaluations).compactMap(\.inspection)
    let observations = results.map(\.context.requestedAt).sorted()

    return SurfaceProbeStabilitySummary(
      fixtureID: first.fixtureID,
      originID: first.originID,
      provider: first.provider,
      observedFrom: observations.first ?? first.context.requestedAt,
      observedThrough: observations.last ?? first.context.requestedAt,
      runCount: results.count,
      passingRunCount: passingRunCount,
      assessment: assessment,
      responseStatusCounts: responseStatusCounts,
      hardGateFailureCounts: counts(failedHardGates),
      providerLatencyMilliseconds: integerDistribution(
        results.map(\.providerLatencyMilliseconds)
      ),
      inspectionLatencyPerRunMilliseconds: inspectionLatencies.isEmpty
        ? nil : integerDistribution(inspectionLatencies),
      acceptedCandidateCountRange: countRange(acceptedByRun.map(\.count)),
      acceptedDistanceMeters: doubleRange(
        acceptedEvaluations.compactMap { $0.candidate?.distanceMeters }
      ),
      acceptedTravelTimeSeconds: doubleRange(
        acceptedEvaluations.compactMap { $0.candidate?.expectedTravelTimeSeconds }
      ),
      terminalDistanceMeters: doubleRange(
        acceptedEvaluations.compactMap { $0.inspection?.anchorBinding?.terminalDistanceMeters }
      ),
      terminalBearingDegrees: doubleRange(
        acceptedEvaluations.compactMap { $0.inspection?.anchorBinding?.terminalBearingDegrees }
      ),
      acceptedResolvedPathVariantCount: Set(pathSignatures).count,
      acceptedRouteSetVariantCount: routeSetVariantCount,
      acceptedApproachEdgeVariantCount: approachVariantCount,
      missingResolvedPathEvaluationCount: missingPathCount,
      maximumUnmatchedSampleCount: inspections.compactMap(\.unmatchedSampleCount).max() ?? 0,
      maximumAmbiguousEdgeCount: inspections.compactMap { $0.ambiguousDirectedEdgeIDs?.count }.max()
        ?? 0,
      maximumDisconnectedEdgeCount: inspections.compactMap {
        $0.disconnectedDirectedEdgeIDs?.count
      }.max() ?? 0
    )
  }

  public static func summarizeWindows(
    _ summaries: [SurfaceProbeStabilitySummary]
  ) throws -> SurfaceProbeCrossWindowSummary {
    guard let first = summaries.first else { throw SurfaceProbeStabilityError.noResults }
    guard summaries.count >= 2 else { throw SurfaceProbeStabilityError.insufficientWindows }
    guard summaries.allSatisfy({ $0.fixtureID == first.fixtureID }) else {
      throw SurfaceProbeStabilityError.inconsistentFixture
    }
    guard summaries.allSatisfy({ $0.originID == first.originID }) else {
      throw SurfaceProbeStabilityError.inconsistentOrigin
    }
    guard summaries.allSatisfy({ $0.provider == first.provider }) else {
      throw SurfaceProbeStabilityError.inconsistentProvider
    }

    let distanceRanges = summaries.compactMap(\.acceptedDistanceMeters)
    let missingPassingDistance = summaries.contains {
      $0.passingRunCount > 0 && $0.acceptedDistanceMeters == nil
    }
    let rangesHaveNoCommonValue: Bool
    if let maximumMinimum = distanceRanges.map(\.minimum).max(),
      let minimumMaximum = distanceRanges.map(\.maximum).min()
    {
      rangesHaveNoCommonValue = maximumMinimum > minimumMaximum
    } else {
      rangesHaveNoCommonValue = false
    }

    var reasons: [String] = []
    if summaries.contains(where: { $0.assessment == .variablePass }) {
      reasons.append("BATCH_REPORTED_VARIABILITY")
    }
    if missingPassingDistance {
      reasons.append("MISSING_ACCEPTED_DISTANCE_RANGE")
    }
    if rangesHaveNoCommonValue {
      reasons.append("NON_OVERLAPPING_ACCEPTED_DISTANCE_RANGES")
    }

    let assessment: SurfaceProbeStabilityAssessment
    if summaries.contains(where: { $0.assessment == .fail }) {
      assessment = .fail
    } else if !reasons.isEmpty {
      assessment = .variablePass
    } else {
      assessment = .stablePass
    }

    let observations = summaries.flatMap { [$0.observedFrom, $0.observedThrough] }.sorted()
    return SurfaceProbeCrossWindowSummary(
      fixtureID: first.fixtureID,
      originID: first.originID,
      provider: first.provider,
      observedFrom: observations.first ?? first.observedFrom,
      observedThrough: observations.last ?? first.observedThrough,
      windowCount: summaries.count,
      runCount: summaries.map(\.runCount).reduce(0, +),
      passingRunCount: summaries.map(\.passingRunCount).reduce(0, +),
      failingRunCount: summaries.map(\.failingRunCount).reduce(0, +),
      assessment: assessment,
      batchAssessmentCounts: counts(summaries.map { $0.assessment.rawValue }),
      acceptedDistanceMeters: doubleRange(
        distanceRanges.flatMap { [$0.minimum, $0.maximum] }
      ),
      scalarVariationReasons: reasons
    )
  }

  private static func counts(_ values: [String]) -> [String: Int] {
    values.reduce(into: [:]) { counts, value in
      counts[value, default: 0] += 1
    }
  }

  private static func integerDistribution(
    _ values: [Int]
  ) -> SurfaceProbeIntegerDistribution {
    let sorted = values.sorted()
    let midpoint = sorted.count / 2
    let median =
      sorted.count.isMultiple(of: 2)
      ? Double(sorted[midpoint - 1] + sorted[midpoint]) / 2
      : Double(sorted[midpoint])
    let percentile95Index = max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)
    return SurfaceProbeIntegerDistribution(
      minimum: sorted[0],
      median: median,
      percentile95: sorted[percentile95Index],
      maximum: sorted[sorted.count - 1]
    )
  }

  private static func countRange(_ values: [Int]) -> SurfaceProbeCountRange {
    SurfaceProbeCountRange(minimum: values.min() ?? 0, maximum: values.max() ?? 0)
  }

  private static func doubleRange(_ values: [Double]) -> SurfaceProbeDoubleRange? {
    guard let minimum = values.min(), let maximum = values.max() else { return nil }
    return SurfaceProbeDoubleRange(minimum: minimum, maximum: maximum)
  }
}
