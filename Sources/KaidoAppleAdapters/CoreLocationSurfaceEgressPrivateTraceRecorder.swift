#if canImport(CoreLocation)
  import Foundation
  import KaidoNavigation

  public enum CoreLocationSurfaceEgressPrivateTraceRecorderError:
    Error, Equatable, Sendable
  {
    case invalidDuration
    case missingObservationID
    case estimateObservationMismatch
    case emptyMatcherRejectionCode
    case fieldTransportScopeMismatch
  }

  /// Builds one in-memory private trace for the released surface-egress matcher.
  ///
  /// It performs no file I/O. Raw coordinates may leave memory only through an
  /// explicitly private field-test workflow. Tracked output must use the
  /// coordinate-free `SurfaceEgressMatcherCalibrationReport`.
  public struct CoreLocationSurfaceEgressPrivateTraceRecorder: Sendable {
    public let context: SurfaceEgressPrivateTraceContext
    public private(set) var entries: [SurfaceEgressPrivateTraceEntry] = []

    public init(context: SurfaceEgressPrivateTraceContext) {
      self.context = context
    }

    public var trace: SurfaceEgressPrivateTrace {
      SurfaceEgressPrivateTrace(context: context, entries: entries)
    }

    public mutating func recordAdapterRejection(
      _ rejection: CoreLocationObservationRejection,
      adaptationDurationMicroseconds: Int
    ) throws {
      guard adaptationDurationMicroseconds >= 0 else {
        throw CoreLocationSurfaceEgressPrivateTraceRecorderError.invalidDuration
      }
      entries.append(
        SurfaceEgressPrivateTraceEntry(
          observationID: rejection.observationID,
          status: .adapterRejected,
          adapterRejectionCode: rejection.reason.rawValue,
          adaptationDurationMicroseconds: adaptationDurationMicroseconds
        )
      )
    }

    public mutating func recordMatch(
      _ envelope: CoreLocationObservationEnvelope,
      estimate: SurfaceEgressMatcherEstimate,
      adaptationDurationMicroseconds: Int,
      matchingDurationMicroseconds: Int
    ) throws {
      guard adaptationDurationMicroseconds >= 0, matchingDurationMicroseconds >= 0 else {
        throw CoreLocationSurfaceEgressPrivateTraceRecorderError.invalidDuration
      }
      let observation = try replayObservation(from: envelope.observation)
      guard estimate.observationID == observation.id else {
        throw CoreLocationSurfaceEgressPrivateTraceRecorderError
          .estimateObservationMismatch
      }
      let provenance = traceProvenance(from: envelope.provenance)
      try validateScope(provenance)
      entries.append(
        SurfaceEgressPrivateTraceEntry(
          observationID: observation.id,
          status: .matched,
          observation: observation,
          provenance: provenance,
          estimate: estimate,
          adaptationDurationMicroseconds: adaptationDurationMicroseconds,
          matchingDurationMicroseconds: matchingDurationMicroseconds
        )
      )
    }

    public mutating func recordMatcherRejection(
      _ envelope: CoreLocationObservationEnvelope,
      matcherRejectionCode: String,
      adaptationDurationMicroseconds: Int,
      matchingDurationMicroseconds: Int
    ) throws {
      guard adaptationDurationMicroseconds >= 0, matchingDurationMicroseconds >= 0 else {
        throw CoreLocationSurfaceEgressPrivateTraceRecorderError.invalidDuration
      }
      guard !matcherRejectionCode.isEmpty else {
        throw CoreLocationSurfaceEgressPrivateTraceRecorderError
          .emptyMatcherRejectionCode
      }
      let observation = try replayObservation(from: envelope.observation)
      let provenance = traceProvenance(from: envelope.provenance)
      try validateScope(provenance)
      entries.append(
        SurfaceEgressPrivateTraceEntry(
          observationID: observation.id,
          status: .matcherRejected,
          observation: observation,
          provenance: provenance,
          matcherRejectionCode: matcherRejectionCode,
          adaptationDurationMicroseconds: adaptationDurationMicroseconds,
          matchingDurationMicroseconds: matchingDurationMicroseconds
        )
      )
    }

    private func replayObservation(
      from observation: RouteMatcherObservation
    ) throws -> MatcherReplayObservation {
      guard let id = observation.id else {
        throw CoreLocationSurfaceEgressPrivateTraceRecorderError.missingObservationID
      }
      return MatcherReplayObservation(
        id: id,
        observedAtMilliseconds: observation.observedAtMilliseconds,
        receivedAtMilliseconds: observation.receivedAtMilliseconds,
        coordinate: observation.coordinate,
        horizontalAccuracyMeters: observation.horizontalAccuracyMeters,
        courseDegrees: observation.courseDegrees,
        speedMetersPerSecond: observation.speedMetersPerSecond,
        source: observation.source
      )
    }

    private func traceProvenance(
      from provenance: CoreLocationObservationProvenance
    ) -> MatcherTraceSourceProvenance {
      MatcherTraceSourceProvenance(
        calibrationCohort: provenance.matcherCalibrationCohort,
        sourceInformationAvailable: provenance.sourceInformationAvailable,
        producedByExternalAccessory: provenance.deliverySource == .externalAccessory,
        simulatedBySoftware: provenance.isSimulatedBySoftware,
        fieldTransportContext: Self.fieldTransportContext(
          provenance.carPlayConnectionContext
        ),
        courseAccuracyDegrees: provenance.courseAccuracyDegrees,
        speedAccuracyMetersPerSecond: provenance.speedAccuracyMetersPerSecond
      )
    }

    private func validateScope(_ provenance: MatcherTraceSourceProvenance) throws {
      guard provenance.fieldTransportContext == context.scope.fieldTransportContext else {
        throw CoreLocationSurfaceEgressPrivateTraceRecorderError
          .fieldTransportScopeMismatch
      }
    }

    private static func fieldTransportContext(
      _ context: AppleCarPlayConnectionContext
    ) -> MatcherFieldTransportContext {
      switch context {
      case .disconnected:
        .phoneOnly
      case .connectedTransportUnknown:
        .carPlayConnectedTransportUnknown
      case .fieldDeclaredWired:
        .fieldDeclaredWiredCarPlay
      case .fieldDeclaredWireless:
        .fieldDeclaredWirelessCarPlay
      }
    }
  }
#endif
