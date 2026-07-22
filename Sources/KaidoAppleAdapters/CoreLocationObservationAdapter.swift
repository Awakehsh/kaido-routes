#if canImport(CoreLocation)
  import CoreLocation
  import Foundation
  import KaidoNavigation

  /// Runtime CarPlay context known by the app or explicitly declared by a field run.
  ///
  /// Public CarPlay APIs expose session connection lifecycle, not whether location
  /// delivery is using a wired or wireless transport. The field-declared cases are
  /// test metadata and must never be inferred from a connected CarPlay scene.
  public enum AppleCarPlayConnectionContext: String, Codable, Equatable, Sendable {
    case disconnected = "DISCONNECTED"
    case connectedTransportUnknown = "CONNECTED_TRANSPORT_UNKNOWN"
    case fieldDeclaredWired = "FIELD_DECLARED_WIRED"
    case fieldDeclaredWireless = "FIELD_DECLARED_WIRELESS"
  }

  /// Source evidence exposed by `CLLocationSourceInformation`.
  public enum CoreLocationDeliverySource: String, Codable, Equatable, Sendable {
    case externalAccessory = "EXTERNAL_ACCESSORY"
    case deviceOrUndisclosed = "DEVICE_OR_UNDISCLOSED"
  }

  public enum SimulatedLocationPolicy: String, Codable, Equatable, Sendable {
    case reject = "REJECT"
    case allowForTesting = "ALLOW_FOR_TESTING"
  }

  public struct CoreLocationSourceEvidence: Equatable, Sendable {
    public let deliverySource: CoreLocationDeliverySource
    public let sourceInformationAvailable: Bool
    public let isSimulatedBySoftware: Bool

    public init(
      deliverySource: CoreLocationDeliverySource,
      sourceInformationAvailable: Bool,
      isSimulatedBySoftware: Bool
    ) {
      self.deliverySource = deliverySource
      self.sourceInformationAvailable = sourceInformationAvailable
      self.isSimulatedBySoftware = isSimulatedBySoftware
    }
  }

  public protocol CoreLocationSourceEvidenceProviding: Sendable {
    func evidence(for location: CLLocation) -> CoreLocationSourceEvidence
  }

  public struct SystemCoreLocationSourceEvidenceProvider:
    CoreLocationSourceEvidenceProviding
  {
    public init() {}

    public func evidence(for location: CLLocation) -> CoreLocationSourceEvidence {
      if #available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *),
        let sourceInformation = location.sourceInformation
      {
        return CoreLocationSourceEvidence(
          deliverySource: sourceInformation.isProducedByAccessory
            ? .externalAccessory : .deviceOrUndisclosed,
          sourceInformationAvailable: true,
          isSimulatedBySoftware: sourceInformation.isSimulatedBySoftware
        )
      }
      return CoreLocationSourceEvidence(
        deliverySource: .deviceOrUndisclosed,
        sourceInformationAvailable: false,
        isSimulatedBySoftware: false
      )
    }
  }

  public struct CoreLocationObservationProvenance: Equatable, Sendable {
    public let deliverySource: CoreLocationDeliverySource
    public let sourceInformationAvailable: Bool
    public let isSimulatedBySoftware: Bool
    public let carPlayConnectionContext: AppleCarPlayConnectionContext
    public let matcherCalibrationCohort: MatcherLocationSource
    public let courseAccuracyDegrees: Double?
    public let speedAccuracyMetersPerSecond: Double?
    public let observationAgeMilliseconds: Int

    public init(
      deliverySource: CoreLocationDeliverySource,
      sourceInformationAvailable: Bool,
      isSimulatedBySoftware: Bool,
      carPlayConnectionContext: AppleCarPlayConnectionContext,
      matcherCalibrationCohort: MatcherLocationSource,
      courseAccuracyDegrees: Double?,
      speedAccuracyMetersPerSecond: Double?,
      observationAgeMilliseconds: Int
    ) {
      self.deliverySource = deliverySource
      self.sourceInformationAvailable = sourceInformationAvailable
      self.isSimulatedBySoftware = isSimulatedBySoftware
      self.carPlayConnectionContext = carPlayConnectionContext
      self.matcherCalibrationCohort = matcherCalibrationCohort
      self.courseAccuracyDegrees = courseAccuracyDegrees
      self.speedAccuracyMetersPerSecond = speedAccuracyMetersPerSecond
      self.observationAgeMilliseconds = observationAgeMilliseconds
    }
  }

  public struct CoreLocationObservationEnvelope: Equatable, Sendable {
    public let observation: RouteMatcherObservation
    public let provenance: CoreLocationObservationProvenance

    public init(
      observation: RouteMatcherObservation,
      provenance: CoreLocationObservationProvenance
    ) {
      self.observation = observation
      self.provenance = provenance
    }
  }

  public enum CoreLocationObservationRejectionReason: String, Codable, Equatable, Sendable {
    case invalidCoordinate = "INVALID_COORDINATE"
    case invalidHorizontalAccuracy = "INVALID_HORIZONTAL_ACCURACY"
    case invalidTimestamp = "INVALID_TIMESTAMP"
    case futureTimestamp = "FUTURE_TIMESTAMP"
    case simulatedLocationRejected = "SIMULATED_LOCATION_REJECTED"
  }

  public struct CoreLocationObservationRejection: Equatable, Sendable {
    public let observationID: String
    public let reason: CoreLocationObservationRejectionReason

    public init(
      observationID: String,
      reason: CoreLocationObservationRejectionReason
    ) {
      self.observationID = observationID
      self.reason = reason
    }
  }

  public enum CoreLocationAdaptationResult: Equatable, Sendable {
    case accepted(CoreLocationObservationEnvelope)
    case rejected(CoreLocationObservationRejection)
  }

  public enum CoreLocationObservationAdapterError: Error, Equatable, Sendable {
    case emptySessionID
  }

  /// Converts Core Location callback batches into auditable matcher observations.
  ///
  /// The adapter preserves callback order and the original fix timestamp. It
  /// records rejections instead of silently dropping invalid or simulated fixes.
  public struct CoreLocationObservationAdapter: Sendable {
    public let sessionID: String
    public let simulatedLocationPolicy: SimulatedLocationPolicy
    public private(set) var carPlayConnectionContext: AppleCarPlayConnectionContext

    private let sourceEvidenceProvider: any CoreLocationSourceEvidenceProviding
    private var nextSequenceNumber = 0

    public init(
      sessionID: String,
      simulatedLocationPolicy: SimulatedLocationPolicy = .reject,
      carPlayConnectionContext: AppleCarPlayConnectionContext = .disconnected,
      sourceEvidenceProvider: any CoreLocationSourceEvidenceProviding =
        SystemCoreLocationSourceEvidenceProvider()
    ) throws {
      guard !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw CoreLocationObservationAdapterError.emptySessionID
      }
      self.sessionID = sessionID
      self.simulatedLocationPolicy = simulatedLocationPolicy
      self.carPlayConnectionContext = carPlayConnectionContext
      self.sourceEvidenceProvider = sourceEvidenceProvider
    }

    public mutating func updateCarPlayConnectionContext(
      _ context: AppleCarPlayConnectionContext
    ) {
      carPlayConnectionContext = context
    }

    /// Adapts locations in the exact order supplied by the Core Location delegate.
    /// A single receive timestamp may be shared by every location in the callback.
    public mutating func adapt(
      _ locations: [CLLocation],
      receivedAt: Date = Date()
    ) -> [CoreLocationAdaptationResult] {
      locations.map { location in
        let observationID = "\(sessionID).\(nextSequenceNumber)"
        nextSequenceNumber += 1
        return adapt(
          location,
          observationID: observationID,
          receivedAt: receivedAt
        )
      }
    }

    private func adapt(
      _ location: CLLocation,
      observationID: String,
      receivedAt: Date
    ) -> CoreLocationAdaptationResult {
      let coordinate = MatcherCoordinate(
        latitude: location.coordinate.latitude,
        longitude: location.coordinate.longitude
      )
      guard coordinate.isValid else {
        return rejection(observationID, .invalidCoordinate)
      }
      guard location.horizontalAccuracy.isFinite, location.horizontalAccuracy > 0 else {
        return rejection(observationID, .invalidHorizontalAccuracy)
      }
      guard let observedAtMilliseconds = Self.milliseconds(location.timestamp),
        let receivedAtMilliseconds = Self.milliseconds(receivedAt)
      else {
        return rejection(observationID, .invalidTimestamp)
      }
      guard receivedAt.timeIntervalSince(location.timestamp) >= 0 else {
        return rejection(observationID, .futureTimestamp)
      }
      let (observationAgeMilliseconds, ageOverflow) =
        receivedAtMilliseconds
        .subtractingReportingOverflow(observedAtMilliseconds)
      guard !ageOverflow else {
        return rejection(observationID, .invalidTimestamp)
      }

      let sourceEvidence = sourceEvidenceProvider.evidence(for: location)
      if sourceEvidence.isSimulatedBySoftware, simulatedLocationPolicy == .reject {
        return rejection(observationID, .simulatedLocationRejected)
      }

      let cohort = matcherCalibrationCohort(deliverySource: sourceEvidence.deliverySource)
      let observation = RouteMatcherObservation(
        id: observationID,
        observedAtMilliseconds: observedAtMilliseconds,
        receivedAtMilliseconds: receivedAtMilliseconds,
        coordinate: coordinate,
        horizontalAccuracyMeters: location.horizontalAccuracy,
        courseDegrees: Self.validCourse(location.course),
        speedMetersPerSecond: Self.nonnegativeFinite(location.speed),
        source: cohort
      )
      let provenance = CoreLocationObservationProvenance(
        deliverySource: sourceEvidence.deliverySource,
        sourceInformationAvailable: sourceEvidence.sourceInformationAvailable,
        isSimulatedBySoftware: sourceEvidence.isSimulatedBySoftware,
        carPlayConnectionContext: carPlayConnectionContext,
        matcherCalibrationCohort: cohort,
        courseAccuracyDegrees: Self.courseAccuracy(for: location),
        speedAccuracyMetersPerSecond: Self.speedAccuracy(for: location),
        observationAgeMilliseconds: observationAgeMilliseconds
      )
      return .accepted(
        CoreLocationObservationEnvelope(observation: observation, provenance: provenance)
      )
    }

    private func matcherCalibrationCohort(
      deliverySource: CoreLocationDeliverySource
    ) -> MatcherLocationSource {
      switch carPlayConnectionContext {
      case .fieldDeclaredWired:
        return .wiredCarPlay
      case .fieldDeclaredWireless:
        return .wirelessCarPlay
      case .disconnected, .connectedTransportUnknown:
        return deliverySource == .externalAccessory ? .accessory : .phone
      }
    }

    private static func validCourse(_ value: Double) -> Double? {
      value.isFinite && (0..<360).contains(value) ? value : nil
    }

    private static func nonnegativeFinite(_ value: Double) -> Double? {
      value.isFinite && value >= 0 ? value : nil
    }

    private static func courseAccuracy(for location: CLLocation) -> Double? {
      if #available(iOS 13.4, macOS 10.15.4, watchOS 6.2, tvOS 13.4, *) {
        return nonnegativeFinite(location.courseAccuracy)
      }
      return nil
    }

    private static func speedAccuracy(for location: CLLocation) -> Double? {
      if #available(iOS 10.0, macOS 10.15, watchOS 3.0, tvOS 10.0, *) {
        return nonnegativeFinite(location.speedAccuracy)
      }
      return nil
    }

    private static func milliseconds(_ date: Date) -> Int? {
      let value = date.timeIntervalSince1970 * 1_000
      guard value.isFinite,
        value >= Double(Int.min),
        value <= Double(Int.max)
      else {
        return nil
      }
      return Int(value.rounded())
    }

    private func rejection(
      _ observationID: String,
      _ reason: CoreLocationObservationRejectionReason
    ) -> CoreLocationAdaptationResult {
      .rejected(
        CoreLocationObservationRejection(
          observationID: observationID,
          reason: reason
        )
      )
    }
  }
#endif
