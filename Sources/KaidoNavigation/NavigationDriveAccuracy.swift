import Foundation

public enum NavigationDriveAccuracyError: Error, Equatable, Sendable {
  case invalidThresholds
  case identityMismatch
  case invalidTrace([String])
  case duplicateEstimate(String)
  case unknownEstimate(String)
}

public struct NavigationDriveAccuracyThresholds: Equatable, Sendable {
  public let minimumSampleCount: Int
  public let minimumEdgeTop1Accuracy: Double
  public let minimumOccurrenceAccuracy: Double
  public let minimumHighConfidencePrecision: Double
  public let minimumHighConfidenceCoverage: Double
  public let maximumProgressErrorP95Meters: Double
  public let maximumBackwardProgressRegressionMeters: Double

  public init(
    minimumSampleCount: Int = 100,
    minimumEdgeTop1Accuracy: Double = 0.85,
    minimumOccurrenceAccuracy: Double = 0.85,
    minimumHighConfidencePrecision: Double = 1,
    minimumHighConfidenceCoverage: Double = 0.25,
    maximumProgressErrorP95Meters: Double = 15,
    maximumBackwardProgressRegressionMeters: Double = 5
  ) {
    self.minimumSampleCount = minimumSampleCount
    self.minimumEdgeTop1Accuracy = minimumEdgeTop1Accuracy
    self.minimumOccurrenceAccuracy = minimumOccurrenceAccuracy
    self.minimumHighConfidencePrecision = minimumHighConfidencePrecision
    self.minimumHighConfidenceCoverage = minimumHighConfidenceCoverage
    self.maximumProgressErrorP95Meters = maximumProgressErrorP95Meters
    self.maximumBackwardProgressRegressionMeters =
      maximumBackwardProgressRegressionMeters
  }

  fileprivate var isValid: Bool {
    minimumSampleCount > 0
      && [
        minimumEdgeTop1Accuracy,
        minimumOccurrenceAccuracy,
        minimumHighConfidencePrecision,
        minimumHighConfidenceCoverage,
      ].allSatisfy {
        $0.isFinite && (0...1).contains($0)
      }
      && maximumProgressErrorP95Meters.isFinite
      && maximumProgressErrorP95Meters >= 0
      && maximumBackwardProgressRegressionMeters.isFinite
      && maximumBackwardProgressRegressionMeters >= 0
  }
}

public enum NavigationDriveAccuracyGateStatus: String, Equatable, Sendable {
  case deterministicFloorMet = "DETERMINISTIC_FLOOR_MET"
  case insufficientEvidence = "INSUFFICIENT_EVIDENCE"
  case thresholdNotMet = "THRESHOLD_NOT_MET"
}

/// Coordinate-free accuracy summary for one deterministic RoutePlan replay.
///
/// This report evaluates matcher output against generator-owned route truth. It
/// is useful for regression and noise testing, but never represents field,
/// device, live-road, or release evidence.
public struct NavigationDriveAccuracyReport: Equatable, Sendable {
  public let routePlanID: String
  public let matcherCorridorID: String
  public let sampleCount: Int
  public let estimateCount: Int
  public let missingEstimateCount: Int
  public let edgeTop1CorrectCount: Int
  public let occurrenceCorrectCount: Int
  public let highConfidenceCount: Int
  public let highConfidenceCorrectOccurrenceCount: Int
  public let unsafeHighConfidenceEdgeCount: Int
  public let unsafeHighConfidenceOccurrenceCount: Int
  public let progressErrorSampleCount: Int
  public let progressErrorP50Meters: Double?
  public let progressErrorP95Meters: Double?
  public let progressErrorMaximumMeters: Double?
  public let backwardOccurrenceJumpCount: Int
  public let maximumBackwardProgressRegressionMeters: Double
  public let highConfidenceBackwardOccurrenceJumpCount: Int
  public let maximumHighConfidenceBackwardProgressRegressionMeters: Double
  public let gateStatus: NavigationDriveAccuracyGateStatus

  public var edgeTop1Accuracy: Double {
    ratio(edgeTop1CorrectCount, sampleCount)
  }

  public var occurrenceAccuracy: Double {
    ratio(occurrenceCorrectCount, sampleCount)
  }

  public var highConfidencePrecision: Double? {
    guard highConfidenceCount > 0 else { return nil }
    return ratio(highConfidenceCorrectOccurrenceCount, highConfidenceCount)
  }

  public var highConfidenceCoverage: Double {
    ratio(highConfidenceCorrectOccurrenceCount, sampleCount)
  }

  public var evidenceScope: NavigationDriveSimulationEvidenceScope {
    .syntheticTestOnly
  }

  public var grantsNavigationAuthority: Bool {
    false
  }

  private func ratio(_ numerator: Int, _ denominator: Int) -> Double {
    guard denominator > 0 else { return 0 }
    return Double(numerator) / Double(denominator)
  }
}

public enum NavigationDriveAccuracyEvaluator {
  public static func evaluate(
    trace: NavigationDriveSimulationTrace,
    corridor: RouteMatcherCorridor,
    estimates: [MatcherEstimate],
    thresholds: NavigationDriveAccuracyThresholds = .init()
  ) throws -> NavigationDriveAccuracyReport {
    guard thresholds.isValid else {
      throw NavigationDriveAccuracyError.invalidThresholds
    }
    guard trace.matcherCorridorID == corridor.id,
      trace.routePlanID == corridor.routePlanID
    else {
      throw NavigationDriveAccuracyError.identityMismatch
    }

    let issues = traceIssues(trace: trace, corridor: corridor)
    guard issues.isEmpty else {
      throw NavigationDriveAccuracyError.invalidTrace(issues)
    }

    let truthIDs = Set(trace.sampleTruth.map(\.observationID))
    var estimatesByID: [String: MatcherEstimate] = [:]
    for estimate in estimates {
      guard let observationID = estimate.observationID else { continue }
      guard truthIDs.contains(observationID) else {
        throw NavigationDriveAccuracyError.unknownEstimate(observationID)
      }
      guard estimatesByID.updateValue(estimate, forKey: observationID) == nil else {
        throw NavigationDriveAccuracyError.duplicateEstimate(observationID)
      }
    }

    let occurrenceMetrics = occurrenceDistanceMetrics(corridor: corridor)
    var edgeTop1CorrectCount = 0
    var occurrenceCorrectCount = 0
    var highConfidenceCount = 0
    var highConfidenceCorrectOccurrenceCount = 0
    var unsafeHighConfidenceEdgeCount = 0
    var unsafeHighConfidenceOccurrenceCount = 0
    var progressErrors: [Double] = []
    var backwardOccurrenceJumpCount = 0
    var maximumBackwardProgressRegressionMeters = 0.0
    var highConfidenceBackwardOccurrenceJumpCount = 0
    var maximumHighConfidenceBackwardProgressRegressionMeters = 0.0
    var lastOccurrenceIndex: Int?
    var lastEstimatedRouteDistanceMeters: Double?
    var lastHighConfidenceOccurrenceIndex: Int?
    var lastHighConfidenceRouteDistanceMeters: Double?

    for truth in trace.sampleTruth {
      guard let estimate = estimatesByID[truth.observationID] else { continue }
      let edgeIsCorrect = estimate.directedEdgeID == truth.directedEdgeID
      let occurrenceIsCorrect = estimate.occurrenceID == truth.occurrenceID
      if edgeIsCorrect { edgeTop1CorrectCount += 1 }
      if occurrenceIsCorrect { occurrenceCorrectCount += 1 }

      if estimate.confidence == .high {
        highConfidenceCount += 1
        if occurrenceIsCorrect {
          highConfidenceCorrectOccurrenceCount += 1
        } else {
          unsafeHighConfidenceOccurrenceCount += 1
        }
        if !edgeIsCorrect {
          unsafeHighConfidenceEdgeCount += 1
        }
      }

      guard
        let occurrenceID = estimate.occurrenceID,
        let fraction = estimate.fractionAlongEdge,
        fraction.isFinite,
        (0...1).contains(fraction),
        let occurrenceMetric = occurrenceMetrics[occurrenceID]
      else {
        continue
      }
      let estimatedRouteDistanceMeters =
        occurrenceMetric.distanceBeforeMeters
        + occurrenceMetric.edgeLengthMeters * fraction
      progressErrors.append(
        abs(estimatedRouteDistanceMeters - truth.routeDistanceMeters)
      )
      if let lastOccurrenceIndex,
        occurrenceMetric.index < lastOccurrenceIndex
      {
        backwardOccurrenceJumpCount += 1
      }
      if let lastEstimatedRouteDistanceMeters,
        estimatedRouteDistanceMeters < lastEstimatedRouteDistanceMeters
      {
        maximumBackwardProgressRegressionMeters = max(
          maximumBackwardProgressRegressionMeters,
          lastEstimatedRouteDistanceMeters - estimatedRouteDistanceMeters
        )
      }
      lastOccurrenceIndex = max(
        lastOccurrenceIndex ?? occurrenceMetric.index,
        occurrenceMetric.index
      )
      lastEstimatedRouteDistanceMeters = max(
        lastEstimatedRouteDistanceMeters ?? estimatedRouteDistanceMeters,
        estimatedRouteDistanceMeters
      )
      if estimate.confidence == .high {
        if let lastHighConfidenceOccurrenceIndex,
          occurrenceMetric.index < lastHighConfidenceOccurrenceIndex
        {
          highConfidenceBackwardOccurrenceJumpCount += 1
        }
        if let lastHighConfidenceRouteDistanceMeters,
          estimatedRouteDistanceMeters
            < lastHighConfidenceRouteDistanceMeters
        {
          maximumHighConfidenceBackwardProgressRegressionMeters = max(
            maximumHighConfidenceBackwardProgressRegressionMeters,
            lastHighConfidenceRouteDistanceMeters
              - estimatedRouteDistanceMeters
          )
        }
        lastHighConfidenceOccurrenceIndex = max(
          lastHighConfidenceOccurrenceIndex ?? occurrenceMetric.index,
          occurrenceMetric.index
        )
        lastHighConfidenceRouteDistanceMeters = max(
          lastHighConfidenceRouteDistanceMeters
            ?? estimatedRouteDistanceMeters,
          estimatedRouteDistanceMeters
        )
      }
    }

    let sampleCount = trace.sampleTruth.count
    let estimateCount = estimatesByID.count
    let highConfidencePrecision =
      highConfidenceCount > 0
      ? Double(highConfidenceCorrectOccurrenceCount) / Double(highConfidenceCount)
      : nil
    let edgeAccuracy = ratio(edgeTop1CorrectCount, sampleCount)
    let occurrenceAccuracy = ratio(occurrenceCorrectCount, sampleCount)
    let highConfidenceCoverage = ratio(
      highConfidenceCorrectOccurrenceCount,
      sampleCount
    )
    let progressErrorP95Meters = percentile(progressErrors, probability: 0.95)

    let gateStatus: NavigationDriveAccuracyGateStatus
    if sampleCount < thresholds.minimumSampleCount
      || estimateCount < sampleCount
      || highConfidencePrecision == nil
      || progressErrorP95Meters == nil
    {
      gateStatus = .insufficientEvidence
    } else if edgeAccuracy < thresholds.minimumEdgeTop1Accuracy
      || occurrenceAccuracy < thresholds.minimumOccurrenceAccuracy
      || highConfidencePrecision! < thresholds.minimumHighConfidencePrecision
      || highConfidenceCoverage < thresholds.minimumHighConfidenceCoverage
      || progressErrorP95Meters! > thresholds.maximumProgressErrorP95Meters
      || unsafeHighConfidenceEdgeCount > 0
      || unsafeHighConfidenceOccurrenceCount > 0
      || highConfidenceBackwardOccurrenceJumpCount > 0
      || maximumHighConfidenceBackwardProgressRegressionMeters
        > thresholds.maximumBackwardProgressRegressionMeters
    {
      gateStatus = .thresholdNotMet
    } else {
      gateStatus = .deterministicFloorMet
    }

    return NavigationDriveAccuracyReport(
      routePlanID: trace.routePlanID,
      matcherCorridorID: trace.matcherCorridorID,
      sampleCount: sampleCount,
      estimateCount: estimateCount,
      missingEstimateCount: sampleCount - estimateCount,
      edgeTop1CorrectCount: edgeTop1CorrectCount,
      occurrenceCorrectCount: occurrenceCorrectCount,
      highConfidenceCount: highConfidenceCount,
      highConfidenceCorrectOccurrenceCount:
        highConfidenceCorrectOccurrenceCount,
      unsafeHighConfidenceEdgeCount: unsafeHighConfidenceEdgeCount,
      unsafeHighConfidenceOccurrenceCount:
        unsafeHighConfidenceOccurrenceCount,
      progressErrorSampleCount: progressErrors.count,
      progressErrorP50Meters: percentile(progressErrors, probability: 0.5),
      progressErrorP95Meters: progressErrorP95Meters,
      progressErrorMaximumMeters: progressErrors.max(),
      backwardOccurrenceJumpCount: backwardOccurrenceJumpCount,
      maximumBackwardProgressRegressionMeters:
        maximumBackwardProgressRegressionMeters,
      highConfidenceBackwardOccurrenceJumpCount:
        highConfidenceBackwardOccurrenceJumpCount,
      maximumHighConfidenceBackwardProgressRegressionMeters:
        maximumHighConfidenceBackwardProgressRegressionMeters,
      gateStatus: gateStatus
    )
  }

  private static func traceIssues(
    trace: NavigationDriveSimulationTrace,
    corridor: RouteMatcherCorridor
  ) -> [String] {
    var issues = corridor.validationIssues
    let truthIDs = trace.sampleTruth.map(\.observationID)
    if trace.sampleTruth.isEmpty {
      issues.append("simulation sample truth is empty")
    }
    if Set(truthIDs).count != truthIDs.count {
      issues.append("simulation sample truth IDs are not unique")
    }
    let observationIDs = trace.events.compactMap { event -> String? in
      guard case .matcherObservation = event.action else { return nil }
      return event.id
    }
    if observationIDs != truthIDs {
      issues.append("simulation observations and sample truth differ")
    }

    let occurrencesByID = Dictionary(
      corridor.occurrences.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    var previousRouteDistanceMeters: Double?
    for truth in trace.sampleTruth {
      guard let occurrence = occurrencesByID[truth.occurrenceID] else {
        issues.append("simulation sample truth occurrence is unknown")
        continue
      }
      if truth.observationID.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty
        || occurrence.index != truth.occurrenceIndex
        || occurrence.directedEdgeID != truth.directedEdgeID
        || truth.sampleIndex < 0
        || !truth.fractionAlongOccurrence.isFinite
        || !(0...1).contains(truth.fractionAlongOccurrence)
        || !truth.routeDistanceMeters.isFinite
        || truth.routeDistanceMeters < 0
      {
        issues.append("simulation sample truth is invalid")
      }
      if let previousRouteDistanceMeters,
        truth.routeDistanceMeters <= previousRouteDistanceMeters
      {
        issues.append("simulation sample truth does not advance")
      }
      previousRouteDistanceMeters = truth.routeDistanceMeters
    }
    return Array(Set(issues)).sorted()
  }

  private static func occurrenceDistanceMetrics(
    corridor: RouteMatcherCorridor
  ) -> [String: OccurrenceDistanceMetric] {
    let edgesByID = Dictionary(
      corridor.edges.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    var distanceBeforeMeters = 0.0
    var metrics: [String: OccurrenceDistanceMetric] = [:]
    for occurrence in corridor.occurrences.sorted(by: { $0.index < $1.index }) {
      let edgeLengthMeters =
        edgesByID[occurrence.directedEdgeID]?.lengthMeters ?? 0
      metrics[occurrence.id] = OccurrenceDistanceMetric(
        index: occurrence.index,
        distanceBeforeMeters: distanceBeforeMeters,
        edgeLengthMeters: edgeLengthMeters
      )
      distanceBeforeMeters += edgeLengthMeters
    }
    return metrics
  }

  private static func ratio(_ numerator: Int, _ denominator: Int) -> Double {
    guard denominator > 0 else { return 0 }
    return Double(numerator) / Double(denominator)
  }

  private static func percentile(
    _ values: [Double],
    probability: Double
  ) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let rank = Int(ceil(Double(sorted.count) * probability))
    return sorted[max(0, rank - 1)]
  }
}

private struct OccurrenceDistanceMetric {
  let index: Int
  let distanceBeforeMeters: Double
  let edgeLengthMeters: Double
}
