import Foundation
import KaidoNavigation
import Testing

#if canImport(CoreLocation)
  import CoreLocation
  import KaidoAppleAdapters
#endif

@Test("Surface egress calibration report stays exact-scope and coordinate-free")
func surfaceEgressCalibrationReportIsScopedAndRedacted() throws {
  let admission = surfaceCalibrationAdmission()
  let trace = try surfaceCalibrationTrace(
    admission: admission,
    traceID: "private-surface-trace",
    observationID: "private-surface-observation"
  )
  let report = try SurfaceEgressMatcherCalibrationEvaluator.evaluate(
    traces: [trace],
    annotations: [
      SurfaceEgressGroundTruthAnnotation(
        observationID: "private-surface-observation",
        partition: .heldOut,
        directedEdgeID: admission.directedSurfaceEdgeID,
        occurrenceID: admission.handoffOccurrenceID
      )
    ],
    reportID: "surface-egress-public-report",
    configuration: MatcherCalibrationEvaluatorConfiguration(
      minimumHeldOutSamplesPerCohort: 1
    )
  )
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  let reportJSON = String(
    decoding: try encoder.encode(report),
    as: UTF8.self
  )
  let traceJSON = String(
    decoding: try encoder.encode(trace),
    as: UTF8.self
  )

  #expect(report.gateStatus == .statisticalFloorMet)
  #expect(report.scope.matcherCorridorID == admission.matcherCorridorID)
  #expect(report.scope.handoffOccurrenceID == admission.handoffOccurrenceID)
  #expect(report.reliabilityBins[0].correctOccurrenceCount == 1)
  #expect(!reportJSON.contains("latitude"))
  #expect(!reportJSON.contains("longitude"))
  #expect(!reportJSON.contains("private-surface-observation"))
  #expect(!reportJSON.contains("private-surface-trace"))
  #expect(!reportJSON.contains("private-surface-device"))
  #expect(traceJSON.contains("latitude"))
  #expect(traceJSON.contains("PRIVATE_RAW_LOCATION"))
  #expect(traceJSON.contains("private-surface-observation"))
}

@Test("Surface egress calibration keeps unsafe, synthetic, and simulated evidence closed")
func surfaceEgressCalibrationGateOrderFailsClosed() throws {
  let admission = surfaceCalibrationAdmission()
  let annotation = SurfaceEgressGroundTruthAnnotation(
    observationID: "surface-observation",
    partition: .heldOut,
    directedEdgeID: admission.directedSurfaceEdgeID,
    occurrenceID: admission.handoffOccurrenceID
  )
  let unsafeReport = try SurfaceEgressMatcherCalibrationEvaluator.evaluate(
    traces: [
      try surfaceCalibrationTrace(
        admission: admission,
        traceID: "unsafe",
        observationID: annotation.observationID,
        collectionMethod: .syntheticTest,
        simulatedBySoftware: true,
        selectedOccurrenceIndex: 1
      )
    ],
    annotations: [annotation],
    reportID: "unsafe",
    configuration: MatcherCalibrationEvaluatorConfiguration(
      minimumHeldOutSamplesPerCohort: 1
    )
  )
  #expect(unsafeReport.gateStatus == .unsafeHighConfidenceObserved)
  #expect(unsafeReport.unsafeHighConfidenceEdgeCount == 1)
  #expect(unsafeReport.unsafeHighConfidenceOccurrenceCount == 1)

  let correctAnnotation = SurfaceEgressGroundTruthAnnotation(
    observationID: "surface-observation",
    partition: .heldOut,
    directedEdgeID: admission.directedSurfaceEdgeID,
    occurrenceID: admission.handoffOccurrenceID
  )
  let syntheticReport = try SurfaceEgressMatcherCalibrationEvaluator.evaluate(
    traces: [
      try surfaceCalibrationTrace(
        admission: admission,
        traceID: "synthetic",
        observationID: correctAnnotation.observationID,
        collectionMethod: .syntheticTest
      )
    ],
    annotations: [correctAnnotation],
    reportID: "synthetic",
    configuration: MatcherCalibrationEvaluatorConfiguration(
      minimumHeldOutSamplesPerCohort: 1
    )
  )
  #expect(syntheticReport.gateStatus == .syntheticEvidenceOnly)

  let simulatedReport = try SurfaceEgressMatcherCalibrationEvaluator.evaluate(
    traces: [
      try surfaceCalibrationTrace(
        admission: admission,
        traceID: "simulated",
        observationID: correctAnnotation.observationID,
        simulatedBySoftware: true
      )
    ],
    annotations: [correctAnnotation],
    reportID: "simulated",
    configuration: MatcherCalibrationEvaluatorConfiguration(
      minimumHeldOutSamplesPerCohort: 1
    )
  )
  #expect(simulatedReport.gateStatus == .simulatedEvidencePresent)
  #expect(simulatedReport.simulatedMatchedEntryCount == 1)
}

@Test("Surface egress calibration refuses candidate, configuration, and transport mixing")
func surfaceEgressCalibrationRejectsMixedScopes() throws {
  let admission = surfaceCalibrationAdmission()
  let first = try surfaceCalibrationTrace(
    admission: admission,
    traceID: "first",
    observationID: "first"
  )
  let otherAdmission = surfaceCalibrationAdmission(
    candidateID: "test.surface-candidate.other",
    corridorID: "test.surface-corridor.other"
  )
  let otherCandidate = try surfaceCalibrationTrace(
    admission: otherAdmission,
    traceID: "other-candidate",
    observationID: "other-candidate"
  )
  let otherConfiguration = try surfaceCalibrationTrace(
    admission: admission,
    traceID: "other-configuration",
    observationID: "other-configuration",
    matcherConfigurationID: "test.surface-configuration.other"
  )
  let otherTransport = try surfaceCalibrationTrace(
    admission: admission,
    traceID: "other-transport",
    observationID: "other-transport",
    fieldTransportContext: .fieldDeclaredWirelessCarPlay,
    source: .wirelessCarPlay
  )

  for trace in [otherCandidate, otherConfiguration, otherTransport] {
    #expect(
      throws:
        SurfaceEgressMatcherCalibrationEvaluatorError
        .mixedCalibrationScope
    ) {
      try SurfaceEgressMatcherCalibrationEvaluator.evaluate(
        traces: [first, trace],
        annotations: [],
        reportID: "mixed"
      )
    }
  }

  #expect(
    throws:
      SurfaceEgressMatcherCalibrationEvaluatorError.invalidAnnotation(
        "first"
      )
  ) {
    try SurfaceEgressMatcherCalibrationEvaluator.evaluate(
      traces: [first],
      annotations: [
        SurfaceEgressGroundTruthAnnotation(
          observationID: "first",
          partition: .heldOut,
          directedEdgeID: "unknown-edge",
          occurrenceID: "unknown-occurrence"
        )
      ],
      reportID: "unknown-ground-truth"
    )
  }
}

#if canImport(CoreLocation)
  @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
  @Test("Core Location surface egress calibration measures the exact matcher pipeline")
  func coreLocationSurfaceEgressCalibrationRunsExactPipeline() throws {
    let admission = surfaceCalibrationAdmission()
    var session = try coreLocationSurfaceCalibrationSession(
      admission: admission
    )
    let outcomes = try session.process(
      [
        surfaceCalibrationLocation(),
        surfaceCalibrationLocation(horizontalAccuracy: -1),
      ],
      receivedAt: Date(timeIntervalSince1970: 1_001)
    )

    guard case .matched(_, let estimate) = outcomes[0] else {
      Issue.record("expected surface egress match")
      return
    }
    guard case .adapterRejected(let rejection) = outcomes[1] else {
      Issue.record("expected adapter rejection")
      return
    }
    #expect(estimate.corridorID == admission.matcherCorridorID)
    #expect(estimate.occurrenceID == admission.handoffOccurrenceID)
    #expect(rejection.reason == .invalidHorizontalAccuracy)
    #expect(session.privateTrace.validationIssues.isEmpty)
    #expect(session.privateTrace.entries.count == 2)

    let report = try SurfaceEgressMatcherCalibrationEvaluator.evaluate(
      traces: [session.privateTrace],
      annotations: [
        SurfaceEgressGroundTruthAnnotation(
          observationID: "surface-calibration.0",
          partition: .heldOut,
          directedEdgeID: admission.directedSurfaceEdgeID,
          occurrenceID: admission.handoffOccurrenceID
        )
      ],
      reportID: "surface-calibration-report",
      configuration: MatcherCalibrationEvaluatorConfiguration(
        minimumHeldOutSamplesPerCohort: 1
      )
    )
    let json = String(
      decoding: try JSONEncoder().encode(report),
      as: UTF8.self
    )
    #expect(report.gateStatus == .statisticalFloorMet)
    #expect(!json.contains("latitude"))
    #expect(!json.contains("surface-calibration.0"))
    #expect(!json.contains("private-surface-device"))
  }

  @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
  @Test("Core Location surface egress calibration records receive-order rejection")
  func coreLocationSurfaceEgressCalibrationRecordsMatcherRejection() throws {
    let admission = surfaceCalibrationAdmission()
    var session = try coreLocationSurfaceCalibrationSession(
      admission: admission
    )
    _ = try session.process(
      [surfaceCalibrationLocation(timestamp: Date(timeIntervalSince1970: 1_000))],
      receivedAt: Date(timeIntervalSince1970: 1_001)
    )
    let outcomes = try session.process(
      [surfaceCalibrationLocation(timestamp: Date(timeIntervalSince1970: 999))],
      receivedAt: Date(timeIntervalSince1970: 1_000)
    )

    guard case .matcherRejected(_, let code) = outcomes[0] else {
      Issue.record("expected surface matcher rejection")
      return
    }
    #expect(code == "INVALID_OBSERVATION")
    #expect(session.privateTrace.entries[1].status == .matcherRejected)
    #expect(
      session.privateTrace.entries[1].matcherRejectionCode
        == "INVALID_OBSERVATION"
    )
    #expect(session.privateTrace.validationIssues.isEmpty)
  }

  @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
  @Test("Core Location surface egress calibration rejects identity and transport drift")
  func coreLocationSurfaceEgressCalibrationRejectsScopeDrift() throws {
    let admission = surfaceCalibrationAdmission()

    #expect(
      throws:
        CoreLocationSurfaceEgressMatcherCalibrationSessionError
        .matcherAlgorithmMismatch
    ) {
      try coreLocationSurfaceCalibrationSession(
        admission: admission,
        matcherAlgorithmID: "other-surface-matcher"
      )
    }
    #expect(
      throws:
        CoreLocationSurfaceEgressMatcherCalibrationSessionError
        .fieldTransportScopeMismatch
    ) {
      try coreLocationSurfaceCalibrationSession(
        admission: admission,
        fieldTransportContext: .fieldDeclaredWirelessCarPlay
      )
    }
    #expect(
      throws:
        CoreLocationSurfaceEgressMatcherCalibrationSessionError
        .matcherConfigurationMismatch
    ) {
      try coreLocationSurfaceCalibrationSession(
        admission: admission,
        scopeMatcherConfiguration: SurfaceEgressMatcherConfiguration(
          maximumCandidateRadiusMeters: 81
        )
      )
    }
    #expect(
      throws:
        CoreLocationSurfaceEgressMatcherCalibrationSessionError
        .admissionScopeMismatch
    ) {
      try coreLocationSurfaceCalibrationSession(
        admission: admission,
        scopeAdmission: surfaceCalibrationAdmission(
          candidateID: "test.surface-candidate.other",
          corridorID: "test.surface-corridor.other"
        )
      )
    }
  }
#endif

private func surfaceCalibrationAdmission(
  candidateID: String = "test.surface-candidate",
  corridorID: String = "test.surface-corridor"
) -> SurfaceEgressAdmissionContext {
  let occurrence = SurfaceEgressMatcherOccurrence(
    id: "test.surface-occurrence.0",
    index: 0,
    directedEdgeID: "test.surface-edge.0",
    coordinates: [
      MatcherCoordinate(latitude: 35.6800, longitude: 139.7600),
      MatcherCoordinate(latitude: 35.6800, longitude: 139.7620),
    ]
  )
  let secondOccurrence = SurfaceEgressMatcherOccurrence(
    id: "test.surface-occurrence.1",
    index: 1,
    directedEdgeID: "test.surface-edge.1",
    coordinates: [
      MatcherCoordinate(latitude: 35.6800, longitude: 139.7620),
      MatcherCoordinate(latitude: 35.6810, longitude: 139.7620),
    ]
  )
  let corridor = SurfaceEgressMatcherCorridor(
    id: corridorID,
    networkSnapshotID: "test.snapshot",
    routePlanID: "test.route-plan",
    providerDatasetID: "test.surface-dataset",
    candidateID: candidateID,
    egressOptionID: "test.egress-option",
    exitFacilityID: "test.exit",
    occurrences: [occurrence, secondOccurrence]
  )
  return SurfaceEgressAdmissionContext(
    productReleaseID: "test.product-release",
    navigationReleaseID: "test.navigation-release",
    journeyPlanID: "test.journey-plan",
    runtimePolicyID: "test.runtime-policy",
    networkSnapshotID: corridor.networkSnapshotID,
    routePlanID: corridor.routePlanID,
    egressOptionID: corridor.egressOptionID,
    exitFacilityID: corridor.exitFacilityID,
    handoffAnchorID: "test.handoff-anchor",
    directedSurfaceEdgeID: occurrence.directedEdgeID,
    matcherCorridor: corridor,
    handoffOccurrenceID: occurrence.id
  )
}

private func surfaceCalibrationTrace(
  admission: SurfaceEgressAdmissionContext,
  traceID: String,
  observationID: String,
  collectionMethod: MatcherTraceCollectionMethod = .automatedLogger,
  simulatedBySoftware: Bool = false,
  matcherConfigurationID: String = "test.surface-configuration",
  fieldTransportContext: MatcherFieldTransportContext = .phoneOnly,
  source: MatcherLocationSource = .phone,
  selectedOccurrenceIndex: Int = 0
) throws -> SurfaceEgressPrivateTrace {
  let observation = RouteMatcherObservation(
    id: observationID,
    observedAtMilliseconds: 1_000,
    receivedAtMilliseconds: 1_001,
    coordinate: MatcherCoordinate(latitude: 35.6800, longitude: 139.7610),
    horizontalAccuracyMeters: 5,
    courseDegrees: 90,
    speedMetersPerSecond: 10,
    source: source
  )
  var matcher = try SurfaceEgressMatcherSession(
    corridor: admission.matcherCorridor
  )
  let matchedEstimate = try matcher.observe(observation)
  let selectedOccurrence = admission.matcherCorridor.occurrences[
    selectedOccurrenceIndex
  ]
  let estimate =
    selectedOccurrenceIndex == 0
    ? matchedEstimate
    : SurfaceEgressMatcherEstimate(
      observationID: observationID,
      estimatedAtMilliseconds: observation.observedAtMilliseconds,
      corridorID: admission.matcherCorridorID,
      directedEdgeID: selectedOccurrence.directedEdgeID,
      occurrenceID: selectedOccurrence.id,
      occurrenceIndex: selectedOccurrence.index,
      candidateEdgeIDs: [selectedOccurrence.directedEdgeID],
      candidateOccurrenceIDs: [selectedOccurrence.id],
      confidence: .high,
      lateralDistanceMeters: 1,
      fractionAlongEdge: 0.5
    )
  let replayObservation = MatcherReplayObservation(
    id: observationID,
    observedAtMilliseconds: observation.observedAtMilliseconds,
    receivedAtMilliseconds: observation.receivedAtMilliseconds,
    coordinate: observation.coordinate,
    horizontalAccuracyMeters: observation.horizontalAccuracyMeters,
    courseDegrees: observation.courseDegrees,
    speedMetersPerSecond: observation.speedMetersPerSecond,
    source: source
  )
  let scope = SurfaceEgressMatcherCalibrationScope(
    admissionContext: admission,
    matcherConfigurationID: matcherConfigurationID,
    matcherConfiguration: .init(),
    deviceConfigurationID: "test.surface-device-configuration",
    fieldTransportContext: fieldTransportContext
  )
  return SurfaceEgressPrivateTrace(
    context: SurfaceEgressPrivateTraceContext(
      traceID: traceID,
      scope: scope,
      deviceModel: "private-surface-device",
      operatingSystemVersion: "private-surface-os",
      appBuild: "private-surface-build",
      mountDescription: "private-surface-mount",
      headUnitDescription: "private-surface-head-unit",
      collectionMethod: collectionMethod,
      startedAtMilliseconds: 1_000
    ),
    entries: [
      SurfaceEgressPrivateTraceEntry(
        observationID: observationID,
        status: .matched,
        observation: replayObservation,
        provenance: MatcherTraceSourceProvenance(
          calibrationCohort: source,
          sourceInformationAvailable: true,
          producedByExternalAccessory: false,
          simulatedBySoftware: simulatedBySoftware,
          fieldTransportContext: fieldTransportContext,
          courseAccuracyDegrees: 2,
          speedAccuracyMetersPerSecond: 1
        ),
        estimate: estimate,
        adaptationDurationMicroseconds: 100,
        matchingDurationMicroseconds: 800
      )
    ]
  )
}

#if canImport(CoreLocation)
  @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
  private func coreLocationSurfaceCalibrationSession(
    admission: SurfaceEgressAdmissionContext,
    scopeAdmission: SurfaceEgressAdmissionContext? = nil,
    matcherAlgorithmID: String = SurfaceEgressMatcherSession.algorithmID,
    fieldTransportContext: MatcherFieldTransportContext = .phoneOnly,
    scopeMatcherConfiguration: SurfaceEgressMatcherConfiguration = .init()
  ) throws -> CoreLocationSurfaceEgressMatcherCalibrationSession {
    let observationAdapter = try CoreLocationObservationAdapter(
      sessionID: "surface-calibration",
      sourceEvidenceProvider: SurfaceCalibrationSourceEvidenceProvider()
    )
    let matcherSession = try SurfaceEgressMatcherSession(
      corridor: admission.matcherCorridor
    )
    let scope = SurfaceEgressMatcherCalibrationScope(
      admissionContext: scopeAdmission ?? admission,
      matcherAlgorithmID: matcherAlgorithmID,
      matcherConfigurationID: "test.surface-configuration",
      matcherConfiguration: scopeMatcherConfiguration,
      deviceConfigurationID: "test.surface-device-configuration",
      fieldTransportContext: fieldTransportContext
    )
    let traceContext = SurfaceEgressPrivateTraceContext(
      traceID: "private-surface-calibration",
      scope: scope,
      deviceModel: "private-surface-device",
      operatingSystemVersion: "private-surface-os",
      appBuild: "private-surface-build",
      mountDescription: "private-surface-mount",
      collectionMethod: .automatedLogger,
      startedAtMilliseconds: 1_000
    )
    return try CoreLocationSurfaceEgressMatcherCalibrationSession(
      admissionContext: admission,
      observationAdapter: observationAdapter,
      matcherSession: matcherSession,
      traceRecorder: CoreLocationSurfaceEgressPrivateTraceRecorder(
        context: traceContext
      )
    )
  }

  @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
  private func surfaceCalibrationLocation(
    horizontalAccuracy: Double = 5,
    timestamp: Date = Date(timeIntervalSince1970: 1_000)
  ) -> CLLocation {
    CLLocation(
      coordinate: CLLocationCoordinate2D(
        latitude: 35.6800,
        longitude: 139.7610
      ),
      altitude: 0,
      horizontalAccuracy: horizontalAccuracy,
      verticalAccuracy: 5,
      course: 90,
      courseAccuracy: 2,
      speed: 10,
      speedAccuracy: 1,
      timestamp: timestamp
    )
  }

  private struct SurfaceCalibrationSourceEvidenceProvider:
    CoreLocationSourceEvidenceProviding
  {
    func evidence(for _: CLLocation) -> CoreLocationSourceEvidence {
      CoreLocationSourceEvidence(
        deliverySource: .deviceOrUndisclosed,
        sourceInformationAvailable: true,
        isSimulatedBySoftware: false
      )
    }
  }
#endif
