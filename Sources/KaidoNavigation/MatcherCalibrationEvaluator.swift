import Foundation

public enum MatcherCalibrationEvaluatorError: Error, Equatable, Sendable {
  case invalidConfiguration
  case invalidTrace([String])
  case mixedCalibrationScope
  case duplicateObservationID(String)
  case duplicateAnnotation(String)
  case unknownAnnotatedObservation(String)
  case annotationRequiresMatchedEntry(String)
  case invalidAnnotation(String)
  case mixedCollectionMethod
  case emptyReportID
}

public enum MatcherCalibrationEvaluator {
  public static func evaluate(
    traces: [MatcherPrivateTrace],
    annotations: [MatcherGroundTruthAnnotation],
    reportID: String,
    configuration: MatcherCalibrationEvaluatorConfiguration = .init()
  ) throws -> MatcherCalibrationReport {
    guard configuration.isValid else {
      throw MatcherCalibrationEvaluatorError.invalidConfiguration
    }
    guard !reportID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw MatcherCalibrationEvaluatorError.emptyReportID
    }
    guard let scope = traces.first?.context.scope else {
      throw MatcherCalibrationEvaluatorError.invalidTrace(["no private traces supplied"])
    }
    let collectionMethod = traces[0].context.collectionMethod

    var allIssues: [String] = []
    for trace in traces {
      allIssues.append(contentsOf: trace.validationIssues)
      if trace.context.scope != scope {
        throw MatcherCalibrationEvaluatorError.mixedCalibrationScope
      }
      if trace.context.collectionMethod != collectionMethod {
        throw MatcherCalibrationEvaluatorError.mixedCollectionMethod
      }
    }
    guard allIssues.isEmpty else {
      throw MatcherCalibrationEvaluatorError.invalidTrace(Array(Set(allIssues)).sorted())
    }

    let entries = traces.flatMap(\.entries)
    var entriesByID: [String: MatcherPrivateTraceEntry] = [:]
    for entry in entries {
      guard entriesByID.updateValue(entry, forKey: entry.observationID) == nil else {
        throw MatcherCalibrationEvaluatorError.duplicateObservationID(entry.observationID)
      }
    }

    var annotationsByID: [String: MatcherGroundTruthAnnotation] = [:]
    for annotation in annotations {
      guard !annotation.observationID.isEmpty, !annotation.directedEdgeID.isEmpty else {
        throw MatcherCalibrationEvaluatorError.invalidAnnotation(annotation.observationID)
      }
      guard entriesByID[annotation.observationID] != nil else {
        throw MatcherCalibrationEvaluatorError.unknownAnnotatedObservation(
          annotation.observationID
        )
      }
      guard entriesByID[annotation.observationID]?.status == .matched else {
        throw MatcherCalibrationEvaluatorError.annotationRequiresMatchedEntry(
          annotation.observationID
        )
      }
      guard annotationsByID.updateValue(annotation, forKey: annotation.observationID) == nil
      else {
        throw MatcherCalibrationEvaluatorError.duplicateAnnotation(annotation.observationID)
      }
    }

    let matchedEntries = entries.filter { $0.status == .matched }
    let annotatedEntries = matchedEntries.compactMap { entry -> AnnotatedEntry? in
      guard let annotation = annotationsByID[entry.observationID],
        let estimate = entry.estimate,
        let provenance = entry.provenance
      else {
        return nil
      }
      return AnnotatedEntry(
        entry: entry,
        estimate: estimate,
        provenance: provenance,
        annotation: annotation
      )
    }

    let accumulator = ReliabilityAccumulator(entries: annotatedEntries)
    let cohorts = Set(
      matchedEntries.compactMap { entry in
        entry.provenance.map {
          CohortKey(
            calibrationCohort: $0.calibrationCohort,
            producedByExternalAccessory: $0.producedByExternalAccessory,
            simulatedBySoftware: $0.simulatedBySoftware
          )
        }
      }
    )
    let heldOutCounts = Dictionary(
      grouping: annotatedEntries.filter {
        $0.annotation.partition == .heldOut
      }
    ) { entry in
      CohortKey(
        calibrationCohort: entry.provenance.calibrationCohort,
        producedByExternalAccessory: entry.provenance.producedByExternalAccessory,
        simulatedBySoftware: entry.provenance.simulatedBySoftware
      )
    }.mapValues(\.count)

    let unsafeHighConfidenceEdgeCount = annotatedEntries.filter {
      $0.estimate.confidence == .high
        && $0.estimate.directedEdgeID != $0.annotation.directedEdgeID
    }.count
    let unsafeHighConfidenceOccurrenceCount = annotatedEntries.filter {
      guard let truth = $0.annotation.occurrenceID else { return false }
      return $0.estimate.confidence == .high && $0.estimate.occurrenceID != truth
    }.count
    let simulatedMatchedEntryCount = matchedEntries.filter {
      $0.provenance?.simulatedBySoftware == true
    }.count

    let gateStatus: MatcherCalibrationGateStatus
    if unsafeHighConfidenceEdgeCount > 0 || unsafeHighConfidenceOccurrenceCount > 0 {
      gateStatus = .unsafeHighConfidenceObserved
    } else if collectionMethod == .syntheticTest {
      gateStatus = .syntheticEvidenceOnly
    } else if simulatedMatchedEntryCount > 0 {
      gateStatus = .simulatedEvidencePresent
    } else if cohorts.isEmpty
      || cohorts.contains(where: {
        heldOutCounts[$0, default: 0] < configuration.minimumHeldOutSamplesPerCohort
      })
    {
      gateStatus = .insufficientHeldOutEvidence
    } else {
      gateStatus = .statisticalFloorMet
    }

    let adaptationDurations = entries.map(\.adaptationDurationMicroseconds)
    let matchingDurations = matchedEntries.compactMap(\.matchingDurationMicroseconds)
    let pipelineDurations = matchedEntries.compactMap { entry -> Int? in
      guard let matchingDuration = entry.matchingDurationMicroseconds else { return nil }
      let (duration, overflow) = entry.adaptationDurationMicroseconds
        .addingReportingOverflow(matchingDuration)
      return overflow ? nil : duration
    }
    let matcherP95 = percentile95(matchingDurations)

    return MatcherCalibrationReport(
      reportID: reportID,
      scope: scope,
      collectionMethod: collectionMethod,
      traceCount: traces.count,
      entryCount: entries.count,
      matchedEntryCount: matchedEntries.count,
      adapterRejectionCount: entries.filter { $0.status == .adapterRejected }.count,
      matcherRejectionCount: entries.filter { $0.status == .matcherRejected }.count,
      simulatedMatchedEntryCount: simulatedMatchedEntryCount,
      annotatedEntryCount: annotatedEntries.count,
      unannotatedMatchedEntryCount: matchedEntries.count - annotatedEntries.count,
      unsafeHighConfidenceEdgeCount: unsafeHighConfidenceEdgeCount,
      unsafeHighConfidenceOccurrenceCount: unsafeHighConfidenceOccurrenceCount,
      adaptationP95Microseconds: percentile95(adaptationDurations),
      matcherP95Microseconds: matcherP95,
      pipelineP95Microseconds: percentile95(pipelineDurations),
      matcherP95BudgetMicroseconds: configuration.matcherP95BudgetMicroseconds,
      matcherP95BudgetMet: matcherP95.map {
        $0 <= configuration.matcherP95BudgetMicroseconds
      } ?? false,
      reliabilityBins: accumulator.bins,
      gateStatus: gateStatus,
      probabilityCalibrationStatus: .unavailableCategoricalConfidenceOnly
    )
  }

  private static func percentile95(_ values: [Int]) -> Int? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let rank = Int(ceil(Double(sorted.count) * 0.95))
    return sorted[max(0, rank - 1)]
  }
}

private struct AnnotatedEntry {
  let entry: MatcherPrivateTraceEntry
  let estimate: MatcherEstimate
  let provenance: MatcherTraceSourceProvenance
  let annotation: MatcherGroundTruthAnnotation
}

private struct CohortKey: Hashable {
  let calibrationCohort: MatcherLocationSource
  let producedByExternalAccessory: Bool
  let simulatedBySoftware: Bool
}

private struct ReliabilityKey: Hashable {
  let partition: MatcherCalibrationPartition
  let calibrationCohort: MatcherLocationSource
  let producedByExternalAccessory: Bool
  let simulatedBySoftware: Bool
  let confidence: MatcherConfidence
}

private struct ReliabilityCounts {
  var annotatedEdgeCount = 0
  var correctEdgeCount = 0
  var wrongEdgeCount = 0
  var abstainedEdgeCount = 0
  var occurrenceTruthCount = 0
  var correctOccurrenceCount = 0
}

private struct ReliabilityAccumulator {
  let bins: [MatcherReliabilityBin]

  init(entries: [AnnotatedEntry]) {
    var countsByKey: [ReliabilityKey: ReliabilityCounts] = [:]
    for entry in entries {
      let key = ReliabilityKey(
        partition: entry.annotation.partition,
        calibrationCohort: entry.provenance.calibrationCohort,
        producedByExternalAccessory: entry.provenance.producedByExternalAccessory,
        simulatedBySoftware: entry.provenance.simulatedBySoftware,
        confidence: entry.estimate.confidence
      )
      var counts = countsByKey[key, default: ReliabilityCounts()]
      counts.annotatedEdgeCount += 1
      if let selectedEdgeID = entry.estimate.directedEdgeID {
        if selectedEdgeID == entry.annotation.directedEdgeID {
          counts.correctEdgeCount += 1
        } else {
          counts.wrongEdgeCount += 1
        }
      } else {
        counts.abstainedEdgeCount += 1
      }
      if let truthOccurrenceID = entry.annotation.occurrenceID {
        counts.occurrenceTruthCount += 1
        if entry.estimate.occurrenceID == truthOccurrenceID {
          counts.correctOccurrenceCount += 1
        }
      }
      countsByKey[key] = counts
    }

    bins = countsByKey.map { key, counts in
      MatcherReliabilityBin(
        partition: key.partition,
        calibrationCohort: key.calibrationCohort,
        producedByExternalAccessory: key.producedByExternalAccessory,
        simulatedBySoftware: key.simulatedBySoftware,
        confidence: key.confidence,
        annotatedEdgeCount: counts.annotatedEdgeCount,
        correctEdgeCount: counts.correctEdgeCount,
        wrongEdgeCount: counts.wrongEdgeCount,
        abstainedEdgeCount: counts.abstainedEdgeCount,
        observedEdgeAccuracy: counts.annotatedEdgeCount > 0
          ? Double(counts.correctEdgeCount) / Double(counts.annotatedEdgeCount)
          : nil,
        occurrenceTruthCount: counts.occurrenceTruthCount,
        correctOccurrenceCount: counts.correctOccurrenceCount
      )
    }.sorted(by: Self.sortsBefore)
  }

  private static func sortsBefore(
    _ lhs: MatcherReliabilityBin,
    _ rhs: MatcherReliabilityBin
  ) -> Bool {
    let lhsKey =
      "\(lhs.partition.rawValue)|\(lhs.calibrationCohort.rawValue)|\(lhs.producedByExternalAccessory)|\(lhs.simulatedBySoftware)|\(lhs.confidence.rawValue)"
    let rhsKey =
      "\(rhs.partition.rawValue)|\(rhs.calibrationCohort.rawValue)|\(rhs.producedByExternalAccessory)|\(rhs.simulatedBySoftware)|\(rhs.confidence.rawValue)"
    return lhsKey < rhsKey
  }
}
