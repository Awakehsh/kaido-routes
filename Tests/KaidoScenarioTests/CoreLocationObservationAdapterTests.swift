#if canImport(CoreLocation)
  import CoreLocation
  import Foundation
  import KaidoAppleAdapters
  import KaidoNavigation
  import Testing

  @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
  @Test("Core Location adapter preserves phone evidence without guessing CarPlay transport")
  func coreLocationAdapterDoesNotGuessCarPlayTransport() throws {
    var adapter = try CoreLocationObservationAdapter(
      sessionID: "session",
      carPlayConnectionContext: .connectedTransportUnknown,
      sourceEvidenceProvider: FixedCoreLocationSourceEvidenceProvider(
        evidence: CoreLocationSourceEvidence(
          deliverySource: .deviceOrUndisclosed,
          sourceInformationAvailable: false,
          isSimulatedBySoftware: false
        )
      )
    )
    let envelope = try accepted(
      adapter.adapt(
        [makeLocation()],
        receivedAt: Date(timeIntervalSince1970: 1_001)
      )[0]
    )

    #expect(envelope.observation.source == .phone)
    #expect(envelope.provenance.deliverySource == .deviceOrUndisclosed)
    #expect(envelope.provenance.sourceInformationAvailable == false)
    #expect(envelope.provenance.carPlayConnectionContext == .connectedTransportUnknown)
    #expect(envelope.provenance.matcherCalibrationCohort == .phone)
    #expect(envelope.provenance.observationAgeMilliseconds == 1_000)
  }

  @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
  @Test("Core Location accessory evidence remains distinct from field transport context")
  func coreLocationAdapterSeparatesAccessoryEvidenceFromFieldContext() throws {
    var accessoryAdapter = try CoreLocationObservationAdapter(
      sessionID: "accessory",
      sourceEvidenceProvider: FixedCoreLocationSourceEvidenceProvider(
        evidence: CoreLocationSourceEvidence(
          deliverySource: .externalAccessory,
          sourceInformationAvailable: true,
          isSimulatedBySoftware: false
        )
      )
    )
    let accessory = try accepted(
      accessoryAdapter.adapt(
        [makeLocation()],
        receivedAt: Date(timeIntervalSince1970: 1_001)
      )[0]
    )

    #expect(accessory.observation.source == .accessory)
    #expect(accessory.provenance.deliverySource == .externalAccessory)
    #expect(accessory.provenance.sourceInformationAvailable)

    var fieldAdapter = try CoreLocationObservationAdapter(
      sessionID: "field",
      carPlayConnectionContext: .fieldDeclaredWireless,
      sourceEvidenceProvider: FixedCoreLocationSourceEvidenceProvider(
        evidence: CoreLocationSourceEvidence(
          deliverySource: .deviceOrUndisclosed,
          sourceInformationAvailable: false,
          isSimulatedBySoftware: false
        )
      )
    )
    let field = try accepted(
      fieldAdapter.adapt(
        [makeLocation()],
        receivedAt: Date(timeIntervalSince1970: 1_001)
      )[0]
    )

    #expect(field.observation.source == .wirelessCarPlay)
    #expect(field.provenance.matcherCalibrationCohort == .wirelessCarPlay)
    #expect(field.provenance.deliverySource == .deviceOrUndisclosed)
    #expect(field.provenance.sourceInformationAvailable == false)

    fieldAdapter.updateCarPlayConnectionContext(.fieldDeclaredWired)
    let wiredField = try accepted(
      fieldAdapter.adapt(
        [makeLocation()],
        receivedAt: Date(timeIntervalSince1970: 1_001)
      )[0]
    )
    #expect(wiredField.observation.source == .wiredCarPlay)
    #expect(wiredField.provenance.deliverySource == .deviceOrUndisclosed)
  }

  @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
  @Test("Core Location adapter rejects simulation by default and can admit it for tests")
  func coreLocationAdapterAppliesSimulationPolicy() throws {
    let simulatedEvidence = FixedCoreLocationSourceEvidenceProvider(
      evidence: CoreLocationSourceEvidence(
        deliverySource: .deviceOrUndisclosed,
        sourceInformationAvailable: true,
        isSimulatedBySoftware: true
      )
    )
    let location = makeLocation()

    var productionAdapter = try CoreLocationObservationAdapter(
      sessionID: "production",
      sourceEvidenceProvider: simulatedEvidence
    )
    let rejection = try rejected(
      productionAdapter.adapt(
        [location],
        receivedAt: Date(timeIntervalSince1970: 1_001)
      )[0]
    )
    #expect(rejection.reason == .simulatedLocationRejected)

    var testAdapter = try CoreLocationObservationAdapter(
      sessionID: "test",
      simulatedLocationPolicy: .allowForTesting,
      sourceEvidenceProvider: simulatedEvidence
    )
    let acceptedSimulation = try accepted(
      testAdapter.adapt(
        [location],
        receivedAt: Date(timeIntervalSince1970: 1_001)
      )[0]
    )
    #expect(acceptedSimulation.provenance.isSimulatedBySoftware)
  }

  @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
  @Test("Core Location adapter records invalid fixes and future timestamps as rejections")
  func coreLocationAdapterRejectsInvalidInput() throws {
    #expect(throws: CoreLocationObservationAdapterError.emptySessionID) {
      try CoreLocationObservationAdapter(sessionID: "  ")
    }
    var adapter = try CoreLocationObservationAdapter(sessionID: "invalid")
    let invalidCoordinate = makeLocation(latitude: 91)
    let invalidAccuracy = makeLocation(horizontalAccuracy: -1)
    let future = makeLocation(timestamp: Date(timeIntervalSince1970: 2_000))
    let submillisecondFuture = makeLocation(
      timestamp: Date(timeIntervalSince1970: 1_001.0004)
    )
    let results = adapter.adapt(
      [invalidCoordinate, invalidAccuracy, future, submillisecondFuture],
      receivedAt: Date(timeIntervalSince1970: 1_001)
    )

    #expect(try rejected(results[0]).reason == .invalidCoordinate)
    #expect(try rejected(results[1]).reason == .invalidHorizontalAccuracy)
    #expect(try rejected(results[2]).reason == .futureTimestamp)
    #expect(try rejected(results[3]).reason == .futureTimestamp)
    #expect(try rejected(results[0]).observationID == "invalid.0")
    #expect(try rejected(results[2]).observationID == "invalid.2")
  }

  @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
  @Test("Core Location adapter converts invalid motion fields to missing evidence")
  func coreLocationAdapterSanitizesMotionFields() throws {
    var adapter = try CoreLocationObservationAdapter(sessionID: "motion")
    let envelope = try accepted(
      adapter.adapt(
        [
          makeLocation(
            course: -1,
            courseAccuracy: -1,
            speed: -1,
            speedAccuracy: -1
          )
        ],
        receivedAt: Date(timeIntervalSince1970: 1_001)
      )[0]
    )

    #expect(envelope.observation.courseDegrees == nil)
    #expect(envelope.observation.speedMetersPerSecond == nil)
    #expect(envelope.provenance.courseAccuracyDegrees == nil)
    #expect(envelope.provenance.speedAccuracyMetersPerSecond == nil)
  }

  @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
  @Test("Core Location adapter preserves delegate batch order and deterministic IDs")
  func coreLocationAdapterPreservesBatchOrder() throws {
    var adapter = try CoreLocationObservationAdapter(sessionID: "ordered")
    let results = adapter.adapt(
      [
        makeLocation(longitude: 139.7600, timestamp: Date(timeIntervalSince1970: 1_000)),
        makeLocation(longitude: 139.7610, timestamp: Date(timeIntervalSince1970: 1_001)),
      ],
      receivedAt: Date(timeIntervalSince1970: 1_002)
    )
    let first = try accepted(results[0])
    let second = try accepted(results[1])

    #expect(first.observation.id == "ordered.0")
    #expect(second.observation.id == "ordered.1")
    #expect(first.observation.coordinate.longitude == 139.7600)
    #expect(second.observation.coordinate.longitude == 139.7610)
    #expect(first.observation.receivedAtMilliseconds == second.observation.receivedAtMilliseconds)
  }

  @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
  @Test("Accepted Core Location observations feed the route-aware matcher session")
  func coreLocationAdapterFeedsRouteMatcherSession() throws {
    let edge = RouteMatcherDirectedEdge(
      id: "edge",
      coordinates: [
        MatcherCoordinate(latitude: 35.6800, longitude: 139.7600),
        MatcherCoordinate(latitude: 35.6800, longitude: 139.7620),
      ]
    )
    let corridor = RouteMatcherCorridor(
      id: "core-location-corridor",
      networkSnapshotID: "snapshot",
      routePlanID: "plan",
      edges: [edge],
      occurrences: [
        RouteMatcherOccurrence(id: "occurrence", index: 0, directedEdgeID: edge.id)
      ]
    )
    var session = try RouteAwareSwiftMatcher().makeSession(
      corridor: corridor,
      initialOccurrenceID: "occurrence"
    )
    var adapter = try CoreLocationObservationAdapter(sessionID: "matcher")
    let envelope = try accepted(
      adapter.adapt(
        [makeLocation(longitude: 139.7610, course: 90, speed: 12)],
        receivedAt: Date(timeIntervalSince1970: 1_001)
      )[0]
    )
    let estimate = try session.observe(envelope.observation)

    #expect(estimate.directedEdgeID == "edge")
    #expect(estimate.occurrenceID == "occurrence")
    #expect(session.diagnostics.acceptedObservationCount == 1)
  }

  @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
  @Test("A delayed fix after a no-signal interval cannot seed accepted matcher state")
  func delayedCoreLocationFixRemainsStale() throws {
    var session = try makeSingleEdgeMatcherSession()
    var adapter = try CoreLocationObservationAdapter(sessionID: "delayed")
    let envelope = try accepted(
      adapter.adapt(
        [makeLocation()],
        receivedAt: Date(timeIntervalSince1970: 1_015)
      )[0]
    )
    let estimate = try session.observe(envelope.observation)

    #expect(envelope.provenance.observationAgeMilliseconds == 15_000)
    #expect(estimate.confidence == .low)
    #expect(session.diagnostics.acceptedObservationCount == 0)
    #expect(session.diagnostics.activeStateCount == 0)
  }

  @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
  @Test("Adapter output remains ordered evidence and matcher rejects receive-time reversal")
  func coreLocationAdapterDoesNotHideReceiveOrderReversal() throws {
    var session = try makeSingleEdgeMatcherSession()
    var adapter = try CoreLocationObservationAdapter(sessionID: "receive-order")
    let first = try accepted(
      adapter.adapt(
        [makeLocation(timestamp: Date(timeIntervalSince1970: 1_000))],
        receivedAt: Date(timeIntervalSince1970: 1_001)
      )[0]
    )
    _ = try session.observe(first.observation)

    let second = try accepted(
      adapter.adapt(
        [makeLocation(timestamp: Date(timeIntervalSince1970: 999))],
        receivedAt: Date(timeIntervalSince1970: 1_000)
      )[0]
    )
    #expect(throws: RouteAwareSwiftMatcherError.invalidObservation) {
      try session.observe(second.observation)
    }
    #expect(first.observation.id == "receive-order.0")
    #expect(second.observation.id == "receive-order.1")
    #expect(session.diagnostics.acceptedObservationCount == 1)
  }

  @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
  private func makeLocation(
    latitude: Double = 35.6800,
    longitude: Double = 139.7605,
    horizontalAccuracy: Double = 5,
    course: Double = 90,
    courseAccuracy: Double = 2,
    speed: Double = 10,
    speedAccuracy: Double = 1,
    timestamp: Date = Date(timeIntervalSince1970: 1_000)
  ) -> CLLocation {
    return CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
      altitude: 0,
      horizontalAccuracy: horizontalAccuracy,
      verticalAccuracy: 5,
      course: course,
      courseAccuracy: courseAccuracy,
      speed: speed,
      speedAccuracy: speedAccuracy,
      timestamp: timestamp
    )
  }

  private struct FixedCoreLocationSourceEvidenceProvider:
    CoreLocationSourceEvidenceProviding
  {
    let evidence: CoreLocationSourceEvidence

    func evidence(for _: CLLocation) -> CoreLocationSourceEvidence {
      evidence
    }
  }

  private func makeSingleEdgeMatcherSession() throws -> RouteMatcherSession {
    let edge = RouteMatcherDirectedEdge(
      id: "edge",
      coordinates: [
        MatcherCoordinate(latitude: 35.6800, longitude: 139.7600),
        MatcherCoordinate(latitude: 35.6800, longitude: 139.7620),
      ]
    )
    let corridor = RouteMatcherCorridor(
      id: "core-location-corridor",
      networkSnapshotID: "snapshot",
      routePlanID: "plan",
      edges: [edge],
      occurrences: [
        RouteMatcherOccurrence(id: "occurrence", index: 0, directedEdgeID: edge.id)
      ]
    )
    return try RouteAwareSwiftMatcher().makeSession(
      corridor: corridor,
      initialOccurrenceID: "occurrence"
    )
  }

  private enum CoreLocationAdapterTestError: Error {
    case expectedAccepted
    case expectedRejected
  }

  private func accepted(
    _ result: CoreLocationAdaptationResult
  ) throws -> CoreLocationObservationEnvelope {
    guard case .accepted(let envelope) = result else {
      throw CoreLocationAdapterTestError.expectedAccepted
    }
    return envelope
  }

  private func rejected(
    _ result: CoreLocationAdaptationResult
  ) throws -> CoreLocationObservationRejection {
    guard case .rejected(let rejection) = result else {
      throw CoreLocationAdapterTestError.expectedRejected
    }
    return rejection
  }
#endif
