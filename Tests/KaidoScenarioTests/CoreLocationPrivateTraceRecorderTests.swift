#if canImport(CoreLocation)
  import CoreLocation
  import Foundation
  import KaidoAppleAdapters
  import KaidoNavigation
  import Testing

  @Test("Core Location recorder builds an in-memory valid private trace")
  func coreLocationRecorderBuildsPrivateTrace() throws {
    let context = coreLocationTraceContext()
    var recorder = CoreLocationPrivateTraceRecorder(context: context)
    let envelope = coreLocationTraceEnvelope(id: "field.0")
    try recorder.recordMatch(
      envelope,
      estimate: coreLocationTraceEstimate(id: "field.0"),
      adaptationDurationMicroseconds: 120,
      matchingDurationMicroseconds: 900
    )
    try recorder.recordAdapterRejection(
      CoreLocationObservationRejection(
        observationID: "field.1",
        reason: .futureTimestamp
      ),
      adaptationDurationMicroseconds: 80
    )

    #expect(recorder.trace.validationIssues.isEmpty)
    #expect(recorder.trace.entries.count == 2)
    #expect(recorder.trace.entries[0].observation?.coordinate.latitude == 35.68)
    #expect(recorder.trace.entries[0].provenance?.producedByExternalAccessory == false)
    #expect(recorder.trace.entries[1].status == .adapterRejected)
    #expect(recorder.trace.entries[1].observation == nil)
  }

  @Test("Core Location recorder rejects scope drift and invalid timings")
  func coreLocationRecorderRejectsScopeDrift() throws {
    var recorder = CoreLocationPrivateTraceRecorder(context: coreLocationTraceContext())
    let wirelessEnvelope = coreLocationTraceEnvelope(
      id: "wireless.0",
      carPlayContext: .fieldDeclaredWireless,
      source: .wirelessCarPlay
    )

    #expect(throws: CoreLocationPrivateTraceRecorderError.fieldTransportScopeMismatch) {
      try recorder.recordMatch(
        wirelessEnvelope,
        estimate: coreLocationTraceEstimate(id: "wireless.0"),
        adaptationDurationMicroseconds: 1,
        matchingDurationMicroseconds: 1
      )
    }
    #expect(throws: CoreLocationPrivateTraceRecorderError.invalidDuration) {
      try recorder.recordAdapterRejection(
        CoreLocationObservationRejection(
          observationID: "rejected",
          reason: .invalidCoordinate
        ),
        adaptationDurationMicroseconds: -1
      )
    }
    #expect(recorder.entries.isEmpty)
  }

  @Test("Core Location private trace can produce only a coordinate-free public report")
  func coreLocationTraceProducesRedactedReport() throws {
    var recorder = CoreLocationPrivateTraceRecorder(context: coreLocationTraceContext())
    let envelope = coreLocationTraceEnvelope(id: "field.0")
    try recorder.recordMatch(
      envelope,
      estimate: coreLocationTraceEstimate(id: "field.0"),
      adaptationDurationMicroseconds: 100,
      matchingDurationMicroseconds: 800
    )
    let report = try MatcherCalibrationEvaluator.evaluate(
      traces: [recorder.trace],
      annotations: [
        MatcherGroundTruthAnnotation(
          observationID: "field.0",
          partition: .heldOut,
          directedEdgeID: "edge",
          occurrenceID: "occurrence"
        )
      ],
      reportID: "redacted",
      configuration: MatcherCalibrationEvaluatorConfiguration(
        minimumHeldOutSamplesPerCohort: 1
      )
    )
    let json = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)

    #expect(report.gateStatus == .statisticalFloorMet)
    #expect(!json.contains("latitude"))
    #expect(!json.contains("field.0"))
    #expect(!json.contains("private-route-plan"))
  }

  @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
  @Test("Calibration session measures the real adapter-to-matcher pipeline in order")
  func coreLocationCalibrationSessionProcessesDelegateBatch() throws {
    var session = try makeCoreLocationCalibrationSession()
    let outcomes = try session.process(
      [
        coreLocationCalibrationFix(),
        coreLocationCalibrationFix(horizontalAccuracy: -1),
      ],
      receivedAt: Date(timeIntervalSince1970: 1_001)
    )

    guard case .matched(_, let estimate) = outcomes[0] else {
      Issue.record("expected matched outcome")
      return
    }
    guard case .adapterRejected(let rejection) = outcomes[1] else {
      Issue.record("expected adapter rejection")
      return
    }
    #expect(estimate.directedEdgeID == "edge")
    #expect(rejection.reason == .invalidHorizontalAccuracy)
    #expect(session.privateTrace.validationIssues.isEmpty)
    #expect(session.privateTrace.entries.count == 2)
    #expect(session.privateTrace.entries[0].adaptationDurationMicroseconds >= 0)
    #expect(session.privateTrace.entries[0].matchingDurationMicroseconds != nil)
  }

  @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
  @Test("Calibration session records matcher receive-order rejection")
  func coreLocationCalibrationSessionRecordsMatcherRejection() throws {
    var session = try makeCoreLocationCalibrationSession()
    _ = try session.process(
      [coreLocationCalibrationFix(timestamp: Date(timeIntervalSince1970: 1_000))],
      receivedAt: Date(timeIntervalSince1970: 1_001)
    )
    let outcomes = try session.process(
      [coreLocationCalibrationFix(timestamp: Date(timeIntervalSince1970: 999))],
      receivedAt: Date(timeIntervalSince1970: 1_000)
    )

    guard case .matcherRejected(_, let code) = outcomes[0] else {
      Issue.record("expected matcher rejection")
      return
    }
    #expect(code == "INVALID_OBSERVATION")
    #expect(session.privateTrace.entries[1].status == .matcherRejected)
    #expect(session.privateTrace.entries[1].matcherRejectionCode == "INVALID_OBSERVATION")
    #expect(session.privateTrace.validationIssues.isEmpty)
  }

  @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
  @Test("Calibration session refuses snapshot, algorithm, and transport scope drift")
  func coreLocationCalibrationSessionRejectsScopeDrift() throws {
    #expect(
      throws: CoreLocationMatcherCalibrationSessionError.networkSnapshotMismatch
    ) {
      try makeCoreLocationCalibrationSession(networkSnapshotID: "other-snapshot")
    }
    #expect(
      throws: CoreLocationMatcherCalibrationSessionError.matcherAlgorithmMismatch
    ) {
      try makeCoreLocationCalibrationSession(matcherAlgorithmID: "other-matcher")
    }
    #expect(
      throws: CoreLocationMatcherCalibrationSessionError.fieldTransportScopeMismatch
    ) {
      try makeCoreLocationCalibrationSession(
        fieldTransportContext: .fieldDeclaredWirelessCarPlay
      )
    }
  }

  private func coreLocationTraceContext() -> MatcherPrivateTraceContext {
    MatcherPrivateTraceContext(
      traceID: "private-trace",
      scope: MatcherCalibrationScope(
        networkSnapshotID: "snapshot",
        matcherAlgorithmID: "matcher",
        matcherConfigurationID: "configuration",
        deviceConfigurationID: "phone-test-device",
        fieldTransportContext: .phoneOnly
      ),
      routePlanID: "private-route-plan",
      deviceModel: "private-device",
      operatingSystemVersion: "private-os",
      appBuild: "private-build",
      mountDescription: "private-mount",
      collectionMethod: .automatedLogger,
      startedAtMilliseconds: 1_000
    )
  }

  private func coreLocationTraceEnvelope(
    id: String,
    carPlayContext: AppleCarPlayConnectionContext = .disconnected,
    source: MatcherLocationSource = .phone
  ) -> CoreLocationObservationEnvelope {
    CoreLocationObservationEnvelope(
      observation: RouteMatcherObservation(
        id: id,
        observedAtMilliseconds: 1_000,
        receivedAtMilliseconds: 1_001,
        coordinate: MatcherCoordinate(latitude: 35.68, longitude: 139.76),
        horizontalAccuracyMeters: 5,
        courseDegrees: 90,
        speedMetersPerSecond: 10,
        source: source
      ),
      provenance: CoreLocationObservationProvenance(
        deliverySource: .deviceOrUndisclosed,
        sourceInformationAvailable: true,
        isSimulatedBySoftware: false,
        carPlayConnectionContext: carPlayContext,
        matcherCalibrationCohort: source,
        courseAccuracyDegrees: 2,
        speedAccuracyMetersPerSecond: 1,
        observationAgeMilliseconds: 1
      )
    )
  }

  private func coreLocationTraceEstimate(id: String) -> MatcherEstimate {
    MatcherEstimate(
      observationID: id,
      estimatedAtMilliseconds: 1_000,
      directedEdgeID: "edge",
      occurrenceID: "occurrence",
      candidateEdgeIDs: ["edge"],
      confidence: .high,
      distanceMeters: 1
    )
  }

  @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
  private func makeCoreLocationCalibrationSession(
    networkSnapshotID: String = "snapshot",
    matcherAlgorithmID: String = RouteAwareSwiftMatcher.algorithmID,
    fieldTransportContext: MatcherFieldTransportContext = .phoneOnly
  ) throws -> CoreLocationMatcherCalibrationSession {
    let edge = RouteMatcherDirectedEdge(
      id: "edge",
      coordinates: [
        MatcherCoordinate(latitude: 35.68, longitude: 139.76),
        MatcherCoordinate(latitude: 35.68, longitude: 139.762),
      ]
    )
    let corridor = RouteMatcherCorridor(
      id: "corridor",
      networkSnapshotID: "snapshot",
      edges: [edge],
      occurrences: [
        RouteMatcherOccurrence(id: "occurrence", index: 0, directedEdgeID: "edge")
      ]
    )
    let matcherSession = try RouteAwareSwiftMatcher().makeSession(
      corridor: corridor,
      initialOccurrenceID: "occurrence"
    )
    let observationAdapter = try CoreLocationObservationAdapter(
      sessionID: "calibration",
      sourceEvidenceProvider: CalibrationFixedSourceEvidenceProvider()
    )
    let context = MatcherPrivateTraceContext(
      traceID: "private-calibration",
      scope: MatcherCalibrationScope(
        networkSnapshotID: networkSnapshotID,
        matcherAlgorithmID: matcherAlgorithmID,
        matcherConfigurationID: "configuration",
        deviceConfigurationID: "device",
        fieldTransportContext: fieldTransportContext
      ),
      routePlanID: "private-route-plan",
      deviceModel: "private-device",
      operatingSystemVersion: "private-os",
      appBuild: "private-build",
      mountDescription: "private-mount",
      collectionMethod: .automatedLogger,
      startedAtMilliseconds: 1_000
    )
    return try CoreLocationMatcherCalibrationSession(
      observationAdapter: observationAdapter,
      matcherSession: matcherSession,
      traceRecorder: CoreLocationPrivateTraceRecorder(context: context)
    )
  }

  @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
  private func coreLocationCalibrationFix(
    horizontalAccuracy: Double = 5,
    timestamp: Date = Date(timeIntervalSince1970: 1_000)
  ) -> CLLocation {
    CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: 35.68, longitude: 139.761),
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

  private struct CalibrationFixedSourceEvidenceProvider:
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
