import Foundation
import KaidoNavigation
import Testing

@Test("Calibration evaluator produces scoped reliability bins and nearest-rank p95")
func calibrationEvaluatorProducesReliabilityAndPerformance() throws {
  let context = calibrationTraceContext(traceID: "trace-a")
  let entries = (1...20).map { index in
    calibrationMatchedEntry(
      id: "observation-\(index)",
      confidence: index <= 10 ? .high : .medium,
      selectedEdgeID: "edge",
      selectedOccurrenceID: "occurrence",
      adaptationDurationMicroseconds: index * 100,
      matchingDurationMicroseconds: index * 1_000
    )
  }
  let trace = MatcherPrivateTrace(context: context, entries: entries)
  let annotations = entries.map {
    MatcherGroundTruthAnnotation(
      observationID: $0.observationID,
      partition: .heldOut,
      directedEdgeID: "edge",
      occurrenceID: "occurrence"
    )
  }
  let report = try MatcherCalibrationEvaluator.evaluate(
    traces: [trace],
    annotations: annotations,
    reportID: "report",
    configuration: MatcherCalibrationEvaluatorConfiguration(
      minimumHeldOutSamplesPerCohort: 20,
      matcherP95BudgetMicroseconds: 20_000
    )
  )

  #expect(report.gateStatus == .statisticalFloorMet)
  #expect(report.traceCount == 1)
  #expect(report.matchedEntryCount == 20)
  #expect(report.annotatedEntryCount == 20)
  #expect(report.unsafeHighConfidenceEdgeCount == 0)
  #expect(report.adaptationP95Microseconds == 1_900)
  #expect(report.matcherP95Microseconds == 19_000)
  #expect(report.pipelineP95Microseconds == 20_900)
  #expect(report.matcherP95BudgetMet)
  #expect(report.reliabilityBins.count == 2)
  #expect(report.reliabilityBins.allSatisfy { $0.observedEdgeAccuracy == 1 })
  #expect(
    report.probabilityCalibrationStatus == .unavailableCategoricalConfidenceOnly
  )
}

@Test("Any annotated false HIGH result blocks the calibration statistical floor")
func calibrationEvaluatorBlocksUnsafeHighConfidence() throws {
  let trace = MatcherPrivateTrace(
    context: calibrationTraceContext(traceID: "unsafe"),
    entries: [
      calibrationMatchedEntry(
        id: "wrong-high",
        confidence: .high,
        selectedEdgeID: "wrong-edge",
        selectedOccurrenceID: "wrong-occurrence"
      )
    ]
  )
  let report = try MatcherCalibrationEvaluator.evaluate(
    traces: [trace],
    annotations: [
      MatcherGroundTruthAnnotation(
        observationID: "wrong-high",
        partition: .heldOut,
        directedEdgeID: "truth-edge",
        occurrenceID: "truth-occurrence"
      )
    ],
    reportID: "unsafe-report",
    configuration: MatcherCalibrationEvaluatorConfiguration(
      minimumHeldOutSamplesPerCohort: 1
    )
  )

  #expect(report.gateStatus == .unsafeHighConfidenceObserved)
  #expect(report.unsafeHighConfidenceEdgeCount == 1)
  #expect(report.unsafeHighConfidenceOccurrenceCount == 1)
  #expect(report.reliabilityBins[0].wrongEdgeCount == 1)
}

@Test("Calibration reports stay insufficient without the configured held-out floor")
func calibrationEvaluatorRequiresHeldOutEvidence() throws {
  let trace = MatcherPrivateTrace(
    context: calibrationTraceContext(traceID: "tuning-only"),
    entries: [calibrationMatchedEntry(id: "tuning", confidence: .high)]
  )
  let report = try MatcherCalibrationEvaluator.evaluate(
    traces: [trace],
    annotations: [
      MatcherGroundTruthAnnotation(
        observationID: "tuning",
        partition: .tuning,
        directedEdgeID: "edge",
        occurrenceID: "occurrence"
      )
    ],
    reportID: "tuning-report",
    configuration: MatcherCalibrationEvaluatorConfiguration(
      minimumHeldOutSamplesPerCohort: 1
    )
  )

  #expect(report.gateStatus == .insufficientHeldOutEvidence)
}

@Test("Synthetic and software-simulated traces cannot satisfy the field statistical floor")
func calibrationEvaluatorKeepsSyntheticEvidenceSeparate() throws {
  let syntheticTrace = MatcherPrivateTrace(
    context: calibrationTraceContext(
      traceID: "synthetic",
      collectionMethod: .syntheticTest
    ),
    entries: [calibrationMatchedEntry(id: "synthetic-observation", confidence: .high)]
  )
  let syntheticAnnotation = MatcherGroundTruthAnnotation(
    observationID: "synthetic-observation",
    partition: .heldOut,
    directedEdgeID: "edge",
    occurrenceID: "occurrence"
  )
  let syntheticReport = try MatcherCalibrationEvaluator.evaluate(
    traces: [syntheticTrace],
    annotations: [syntheticAnnotation],
    reportID: "synthetic-report",
    configuration: MatcherCalibrationEvaluatorConfiguration(
      minimumHeldOutSamplesPerCohort: 1
    )
  )
  #expect(syntheticReport.gateStatus == .syntheticEvidenceOnly)

  let simulatedTrace = MatcherPrivateTrace(
    context: calibrationTraceContext(traceID: "simulated-field"),
    entries: [
      calibrationMatchedEntry(
        id: "simulated-observation",
        confidence: .high,
        simulatedBySoftware: true
      )
    ]
  )
  let simulatedReport = try MatcherCalibrationEvaluator.evaluate(
    traces: [simulatedTrace],
    annotations: [
      MatcherGroundTruthAnnotation(
        observationID: "simulated-observation",
        partition: .heldOut,
        directedEdgeID: "edge",
        occurrenceID: "occurrence"
      )
    ],
    reportID: "simulated-report",
    configuration: MatcherCalibrationEvaluatorConfiguration(
      minimumHeldOutSamplesPerCohort: 1
    )
  )
  #expect(simulatedReport.gateStatus == .simulatedEvidencePresent)
  #expect(simulatedReport.simulatedMatchedEntryCount == 1)
  #expect(simulatedReport.reliabilityBins[0].simulatedBySoftware)
}

@Test("Evaluator refuses to combine different device or transport scopes")
func calibrationEvaluatorRejectsMixedScope() throws {
  let phoneTrace = MatcherPrivateTrace(
    context: calibrationTraceContext(traceID: "phone"),
    entries: [calibrationMatchedEntry(id: "phone-observation", confidence: .high)]
  )
  let wirelessTrace = MatcherPrivateTrace(
    context: calibrationTraceContext(
      traceID: "wireless",
      scope: MatcherCalibrationScope(
        networkSnapshotID: "snapshot",
        matcherAlgorithmID: "matcher",
        matcherConfigurationID: "configuration",
        deviceConfigurationID: "device-wireless",
        fieldTransportContext: .fieldDeclaredWirelessCarPlay
      )
    ),
    entries: [
      calibrationMatchedEntry(
        id: "wireless-observation",
        confidence: .high,
        source: .wirelessCarPlay,
        fieldTransportContext: .fieldDeclaredWirelessCarPlay
      )
    ]
  )

  #expect(throws: MatcherCalibrationEvaluatorError.mixedCalibrationScope) {
    try MatcherCalibrationEvaluator.evaluate(
      traces: [phoneTrace, wirelessTrace],
      annotations: [],
      reportID: "mixed"
    )
  }
}

@Test("Public calibration JSON contains scalars but no private trace fields")
func calibrationReportIsCoordinateFree() throws {
  let trace = MatcherPrivateTrace(
    context: calibrationTraceContext(traceID: "private-trace-id"),
    entries: [calibrationMatchedEntry(id: "private-observation-id", confidence: .high)]
  )
  let report = try MatcherCalibrationEvaluator.evaluate(
    traces: [trace],
    annotations: [
      MatcherGroundTruthAnnotation(
        observationID: "private-observation-id",
        partition: .heldOut,
        directedEdgeID: "edge",
        occurrenceID: "occurrence"
      )
    ],
    reportID: "public-report",
    configuration: MatcherCalibrationEvaluatorConfiguration(
      minimumHeldOutSamplesPerCohort: 1
    )
  )
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  let reportJSON = String(decoding: try encoder.encode(report), as: UTF8.self)
  let traceJSON = String(decoding: try encoder.encode(trace), as: UTF8.self)

  #expect(reportJSON.contains("reliability_bins"))
  #expect(reportJSON.contains("matcher_p95_us"))
  #expect(!reportJSON.contains("latitude"))
  #expect(!reportJSON.contains("private-observation-id"))
  #expect(!reportJSON.contains("private-trace-id"))
  #expect(!reportJSON.contains("private-route-plan"))
  #expect(!reportJSON.contains("iPhone Private Model"))
  #expect(!reportJSON.contains("private-head-unit"))
  #expect(traceJSON.contains("latitude"))
  #expect(traceJSON.contains("PRIVATE_RAW_LOCATION"))
  #expect(traceJSON.contains("private-observation-id"))
}

@Test("Invalid private trace shape and duplicate annotations fail closed")
func calibrationEvaluatorRejectsInvalidEvidence() throws {
  let invalidEntry = MatcherPrivateTraceEntry(
    observationID: "invalid",
    status: .matched,
    adaptationDurationMicroseconds: 1,
    matchingDurationMicroseconds: 1
  )
  let invalidTrace = MatcherPrivateTrace(
    context: calibrationTraceContext(traceID: "invalid"),
    entries: [invalidEntry]
  )
  #expect(throws: MatcherCalibrationEvaluatorError.self) {
    try MatcherCalibrationEvaluator.evaluate(
      traces: [invalidTrace],
      annotations: [],
      reportID: "invalid"
    )
  }

  let validTrace = MatcherPrivateTrace(
    context: calibrationTraceContext(traceID: "valid"),
    entries: [calibrationMatchedEntry(id: "duplicate", confidence: .high)]
  )
  let annotation = MatcherGroundTruthAnnotation(
    observationID: "duplicate",
    partition: .heldOut,
    directedEdgeID: "edge"
  )
  #expect(throws: MatcherCalibrationEvaluatorError.duplicateAnnotation("duplicate")) {
    try MatcherCalibrationEvaluator.evaluate(
      traces: [validTrace],
      annotations: [annotation, annotation],
      reportID: "duplicates"
    )
  }

  let rejectedTrace = MatcherPrivateTrace(
    context: calibrationTraceContext(traceID: "rejected"),
    entries: [
      MatcherPrivateTraceEntry(
        observationID: "adapter-rejected",
        status: .adapterRejected,
        adapterRejectionCode: "INVALID_COORDINATE",
        adaptationDurationMicroseconds: 1
      )
    ]
  )
  #expect(
    throws: MatcherCalibrationEvaluatorError.annotationRequiresMatchedEntry(
      "adapter-rejected"
    )
  ) {
    try MatcherCalibrationEvaluator.evaluate(
      traces: [rejectedTrace],
      annotations: [
        MatcherGroundTruthAnnotation(
          observationID: "adapter-rejected",
          partition: .heldOut,
          directedEdgeID: "edge"
        )
      ],
      reportID: "rejected-annotation"
    )
  }
}

private func calibrationTraceContext(
  traceID: String,
  scope: MatcherCalibrationScope = MatcherCalibrationScope(
    networkSnapshotID: "snapshot",
    matcherAlgorithmID: "matcher",
    matcherConfigurationID: "configuration",
    deviceConfigurationID: "device-phone",
    fieldTransportContext: .phoneOnly
  ),
  collectionMethod: MatcherTraceCollectionMethod = .automatedLogger
) -> MatcherPrivateTraceContext {
  MatcherPrivateTraceContext(
    traceID: traceID,
    scope: scope,
    routePlanID: "private-route-plan",
    deviceModel: "iPhone Private Model",
    operatingSystemVersion: "Private OS",
    appBuild: "private-build",
    mountDescription: "private-mount",
    headUnitDescription: "private-head-unit",
    collectionMethod: collectionMethod,
    startedAtMilliseconds: 1_000
  )
}

private func calibrationMatchedEntry(
  id: String,
  confidence: MatcherConfidence,
  selectedEdgeID: String? = "edge",
  selectedOccurrenceID: String? = "occurrence",
  source: MatcherLocationSource = .phone,
  producedByExternalAccessory: Bool = false,
  simulatedBySoftware: Bool = false,
  fieldTransportContext: MatcherFieldTransportContext = .phoneOnly,
  adaptationDurationMicroseconds: Int = 100,
  matchingDurationMicroseconds: Int = 1_000
) -> MatcherPrivateTraceEntry {
  MatcherPrivateTraceEntry(
    observationID: id,
    status: .matched,
    observation: MatcherReplayObservation(
      id: id,
      observedAtMilliseconds: 1_000,
      receivedAtMilliseconds: 1_001,
      coordinate: MatcherCoordinate(latitude: 35.68, longitude: 139.76),
      horizontalAccuracyMeters: 5,
      courseDegrees: 90,
      speedMetersPerSecond: 10,
      source: source
    ),
    provenance: MatcherTraceSourceProvenance(
      calibrationCohort: source,
      sourceInformationAvailable: true,
      producedByExternalAccessory: producedByExternalAccessory,
      simulatedBySoftware: simulatedBySoftware,
      fieldTransportContext: fieldTransportContext
    ),
    estimate: MatcherEstimate(
      observationID: id,
      estimatedAtMilliseconds: 1_000,
      directedEdgeID: selectedEdgeID,
      occurrenceID: selectedOccurrenceID,
      candidateEdgeIDs: selectedEdgeID.map { [$0] } ?? [],
      confidence: confidence,
      distanceMeters: selectedEdgeID == nil ? nil : 1
    ),
    adaptationDurationMicroseconds: adaptationDurationMicroseconds,
    matchingDurationMicroseconds: matchingDurationMicroseconds
  )
}
