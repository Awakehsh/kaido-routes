#if canImport(CoreLocation)
  import CoreLocation
  import Dispatch
  import Foundation
  import KaidoNavigation

  public enum CoreLocationMatcherCalibrationSessionError: Error, Equatable, Sendable {
    case networkSnapshotMismatch
    case matcherAlgorithmMismatch
    case fieldTransportScopeMismatch
    case missingAdaptationResult
  }

  public enum CoreLocationMatcherCalibrationOutcome: Equatable, Sendable {
    case adapterRejected(CoreLocationObservationRejection)
    case matched(CoreLocationObservationEnvelope, MatcherEstimate)
    case matcherRejected(CoreLocationObservationEnvelope, code: String)
  }

  /// Executes and times the real Apple-adapter -> Swift-matcher boundary.
  ///
  /// A session is bound to one calibration scope. Changing phone/CarPlay field
  /// transport starts a new session rather than mixing configurations.
  public struct CoreLocationMatcherCalibrationSession: Sendable {
    public private(set) var observationAdapter: CoreLocationObservationAdapter
    public private(set) var matcherSession: RouteMatcherSession
    public private(set) var traceRecorder: CoreLocationPrivateTraceRecorder

    public init(
      observationAdapter: CoreLocationObservationAdapter,
      matcherSession: RouteMatcherSession,
      traceRecorder: CoreLocationPrivateTraceRecorder
    ) throws {
      guard
        matcherSession.networkSnapshotID
          == traceRecorder.context.scope.networkSnapshotID
      else {
        throw CoreLocationMatcherCalibrationSessionError.networkSnapshotMismatch
      }
      guard
        traceRecorder.context.scope.matcherAlgorithmID
          == RouteAwareSwiftMatcher.algorithmID
      else {
        throw CoreLocationMatcherCalibrationSessionError.matcherAlgorithmMismatch
      }
      guard
        Self.fieldTransportContext(observationAdapter.carPlayConnectionContext)
          == traceRecorder.context.scope.fieldTransportContext
      else {
        throw CoreLocationMatcherCalibrationSessionError.fieldTransportScopeMismatch
      }
      self.observationAdapter = observationAdapter
      self.matcherSession = matcherSession
      self.traceRecorder = traceRecorder
    }

    public var privateTrace: MatcherPrivateTrace {
      traceRecorder.trace
    }

    /// Processes a delegate batch in delivery order using one shared receive time.
    public mutating func process(
      _ locations: [CLLocation],
      receivedAt: Date = Date()
    ) throws -> [CoreLocationMatcherCalibrationOutcome] {
      try locations.map { location in
        let adaptationStart = DispatchTime.now().uptimeNanoseconds
        guard
          let adaptationResult = observationAdapter.adapt(
            [location],
            receivedAt: receivedAt
          ).first
        else {
          throw CoreLocationMatcherCalibrationSessionError.missingAdaptationResult
        }
        let adaptationDuration = Self.elapsedMicroseconds(since: adaptationStart)

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
            let matchingDuration = Self.elapsedMicroseconds(since: matchingStart)
            try traceRecorder.recordMatch(
              envelope,
              estimate: estimate,
              adaptationDurationMicroseconds: adaptationDuration,
              matchingDurationMicroseconds: matchingDuration
            )
            return .matched(envelope, estimate)
          } catch let error as RouteAwareSwiftMatcherError {
            let matchingDuration = Self.elapsedMicroseconds(since: matchingStart)
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

    private static func matcherRejectionCode(_ error: RouteAwareSwiftMatcherError) -> String {
      switch error {
      case .invalidConfiguration:
        "INVALID_CONFIGURATION"
      case .invalidFixture:
        "INVALID_FIXTURE"
      case .invalidCorridor:
        "INVALID_CORRIDOR"
      case .invalidObservation:
        "INVALID_OBSERVATION"
      case .missingInitialOccurrence:
        "MISSING_INITIAL_OCCURRENCE"
      }
    }

    private static func elapsedMicroseconds(since startNanoseconds: UInt64) -> Int {
      let endNanoseconds = DispatchTime.now().uptimeNanoseconds
      guard endNanoseconds >= startNanoseconds else { return 0 }
      let microseconds = (endNanoseconds - startNanoseconds) / 1_000
      return microseconds > UInt64(Int.max) ? Int.max : Int(microseconds)
    }
  }
#endif
