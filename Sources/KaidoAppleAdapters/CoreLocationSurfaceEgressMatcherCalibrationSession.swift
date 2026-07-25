#if canImport(CoreLocation)
  import CoreLocation
  import Dispatch
  import Foundation
  import KaidoNavigation

  public enum CoreLocationSurfaceEgressMatcherCalibrationSessionError:
    Error, Equatable, Sendable
  {
    case admissionScopeMismatch
    case matcherCorridorMismatch
    case matcherAlgorithmMismatch
    case matcherConfigurationMismatch
    case fieldTransportScopeMismatch
    case invalidTraceContext([String])
    case missingAdaptationResult
  }

  public enum CoreLocationSurfaceEgressMatcherCalibrationOutcome:
    Equatable, Sendable
  {
    case adapterRejected(CoreLocationObservationRejection)
    case matched(
      CoreLocationObservationEnvelope,
      SurfaceEgressMatcherEstimate
    )
    case matcherRejected(CoreLocationObservationEnvelope, code: String)
  }

  /// Executes the exact Core Location -> surface-egress matcher calibration path.
  ///
  /// This session owns an independent matcher posterior and cannot consume or
  /// report expressway matcher evidence.
  public struct CoreLocationSurfaceEgressMatcherCalibrationSession: Sendable {
    public let admissionContext: SurfaceEgressAdmissionContext
    public private(set) var observationAdapter: CoreLocationObservationAdapter
    public private(set) var matcherSession: SurfaceEgressMatcherSession
    public private(set) var traceRecorder: CoreLocationSurfaceEgressPrivateTraceRecorder

    public init(
      admissionContext: SurfaceEgressAdmissionContext,
      observationAdapter: CoreLocationObservationAdapter,
      matcherSession: SurfaceEgressMatcherSession,
      traceRecorder: CoreLocationSurfaceEgressPrivateTraceRecorder
    ) throws {
      let contextIssues = traceRecorder.context.validationIssues
      guard contextIssues.isEmpty else {
        throw
          CoreLocationSurfaceEgressMatcherCalibrationSessionError
          .invalidTraceContext(contextIssues)
      }
      guard traceRecorder.context.scope.matches(admissionContext) else {
        throw CoreLocationSurfaceEgressMatcherCalibrationSessionError
          .admissionScopeMismatch
      }
      guard matcherSession.corridor == admissionContext.matcherCorridor else {
        throw CoreLocationSurfaceEgressMatcherCalibrationSessionError
          .matcherCorridorMismatch
      }
      guard
        traceRecorder.context.scope.matcherAlgorithmID
          == SurfaceEgressMatcherSession.algorithmID
      else {
        throw CoreLocationSurfaceEgressMatcherCalibrationSessionError
          .matcherAlgorithmMismatch
      }
      guard
        traceRecorder.context.scope.matcherConfiguration
          == matcherSession.configuration
      else {
        throw CoreLocationSurfaceEgressMatcherCalibrationSessionError
          .matcherConfigurationMismatch
      }
      guard
        Self.fieldTransportContext(observationAdapter.carPlayConnectionContext)
          == traceRecorder.context.scope.fieldTransportContext
      else {
        throw CoreLocationSurfaceEgressMatcherCalibrationSessionError
          .fieldTransportScopeMismatch
      }
      self.admissionContext = admissionContext
      self.observationAdapter = observationAdapter
      self.matcherSession = matcherSession
      self.traceRecorder = traceRecorder
    }

    public var privateTrace: SurfaceEgressPrivateTrace {
      traceRecorder.trace
    }

    /// Processes one delegate batch in delivery order at one shared receive time.
    public mutating func process(
      _ locations: [CLLocation],
      receivedAt: Date = Date()
    ) throws -> [CoreLocationSurfaceEgressMatcherCalibrationOutcome] {
      try locations.map { location in
        let adaptationStart = DispatchTime.now().uptimeNanoseconds
        guard
          let adaptationResult = observationAdapter.adapt(
            [location],
            receivedAt: receivedAt
          ).first
        else {
          throw CoreLocationSurfaceEgressMatcherCalibrationSessionError
            .missingAdaptationResult
        }
        let adaptationDuration = Self.elapsedMicroseconds(
          since: adaptationStart
        )

        switch adaptationResult {
        case .rejected(let rejection):
          try traceRecorder.recordAdapterRejection(
            rejection,
            adaptationDurationMicroseconds: adaptationDuration
          )
          return .adapterRejected(rejection)
        case .accepted(let envelope):
          let matchingStart = DispatchTime.now().uptimeNanoseconds
          do {
            let estimate = try matcherSession.observe(envelope.observation)
            let matchingDuration = Self.elapsedMicroseconds(
              since: matchingStart
            )
            try traceRecorder.recordMatch(
              envelope,
              estimate: estimate,
              adaptationDurationMicroseconds: adaptationDuration,
              matchingDurationMicroseconds: matchingDuration
            )
            return .matched(envelope, estimate)
          } catch let error as SurfaceEgressMatcherError {
            let matchingDuration = Self.elapsedMicroseconds(
              since: matchingStart
            )
            let code = Self.matcherRejectionCode(error)
            try traceRecorder.recordMatcherRejection(
              envelope,
              matcherRejectionCode: code,
              adaptationDurationMicroseconds: adaptationDuration,
              matchingDurationMicroseconds: matchingDuration
            )
            return .matcherRejected(envelope, code: code)
          }
        }
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

    private static func matcherRejectionCode(
      _ error: SurfaceEgressMatcherError
    ) -> String {
      switch error {
      case .invalidConfiguration:
        "INVALID_CONFIGURATION"
      case .invalidCorridor:
        "INVALID_CORRIDOR"
      case .invalidObservation:
        "INVALID_OBSERVATION"
      }
    }

    private static func elapsedMicroseconds(
      since startNanoseconds: UInt64
    ) -> Int {
      let endNanoseconds = DispatchTime.now().uptimeNanoseconds
      guard endNanoseconds >= startNanoseconds else { return 0 }
      let microseconds = (endNanoseconds - startNanoseconds) / 1_000
      return microseconds > UInt64(Int.max) ? Int.max : Int(microseconds)
    }
  }
#endif
