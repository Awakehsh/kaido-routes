#if canImport(CoreLocation)
  import CoreLocation
  import Foundation
  import KaidoNavigation

  /// Matches Core Location fixes against one compiler-retained egress corridor.
  ///
  /// The adapter can mint evidence only for its exact runtime context. It does
  /// not share the expressway matcher session and cannot change journey phase.
  public struct CoreLocationSurfaceEgressAdapter: Sendable {
    public let context: SurfaceEgressAdmissionContext

    private var matcherSession: SurfaceEgressMatcherSession
    private let occurrenceByID: [String: SurfaceEgressMatcherOccurrence]

    public init(
      context: SurfaceEgressAdmissionContext,
      matcherConfiguration: SurfaceEgressMatcherConfiguration = .init()
    ) throws {
      self.context = context
      matcherSession = try SurfaceEgressMatcherSession(
        corridor: context.matcherCorridor,
        configuration: matcherConfiguration
      )
      occurrenceByID = Dictionary(
        context.matcherCorridor.occurrences.map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
      )
    }

    public mutating func adapt(
      _ envelope: CoreLocationObservationEnvelope
    ) throws -> SurfaceEgressHandoffEvidence {
      let observation = envelope.observation
      let estimate = try matcherSession.observe(observation)
      let headingError: Double? = estimate.occurrenceID.flatMap {
        occurrenceID in
        guard let course = observation.courseDegrees,
          observation.speedMetersPerSecond.map({ $0 >= 2 }) == true,
          let occurrence = occurrenceByID[occurrenceID],
          let bearing = Self.closestBearing(
            to: observation.coordinate,
            on: occurrence.coordinates
          )
        else {
          return nil
        }
        return Self.angularDifferenceDegrees(course, bearing)
      }

      return SurfaceEgressHandoffEvidence(
        context: context,
        observationID: observation.id ?? "",
        observedAtMilliseconds: observation.observedAtMilliseconds,
        receivedAtMilliseconds: observation.receivedAtMilliseconds,
        directedSurfaceEdgeID: estimate.directedEdgeID,
        candidateEdgeIDs: estimate.candidateEdgeIDs,
        surfaceOccurrenceID: estimate.occurrenceID,
        candidateOccurrenceIDs: estimate.candidateOccurrenceIDs,
        fractionAlongEdge: estimate.fractionAlongEdge,
        confidence: estimate.confidence,
        headingErrorDegrees: headingError,
        isSimulatedBySoftware:
          envelope.provenance.isSimulatedBySoftware
      )
    }

    public mutating func resetMatcher() {
      matcherSession.reset()
    }

    private static func closestBearing(
      to point: MatcherCoordinate,
      on coordinates: [MatcherCoordinate]
    ) -> Double? {
      var closestDistance = Double.infinity
      var closestBearing: Double?
      for (start, end) in zip(coordinates, coordinates.dropFirst()) {
        let measurement = segmentMeasurement(
          point: point,
          start: start,
          end: end
        )
        if measurement.distanceMeters < closestDistance {
          closestDistance = measurement.distanceMeters
          closestBearing = measurement.bearingDegrees
        }
      }
      return closestBearing
    }

    private static func segmentMeasurement(
      point: MatcherCoordinate,
      start: MatcherCoordinate,
      end: MatcherCoordinate
    ) -> (distanceMeters: Double, bearingDegrees: Double) {
      let earthRadiusMeters = 6_371_000.0
      let referenceLatitude =
        (start.latitude + end.latitude + point.latitude) / 3
      let latitudeScale = earthRadiusMeters * .pi / 180
      let longitudeScale =
        latitudeScale * cos(referenceLatitude * .pi / 180)
      let segmentX = (end.longitude - start.longitude) * longitudeScale
      let segmentY = (end.latitude - start.latitude) * latitudeScale
      let pointX = (point.longitude - start.longitude) * longitudeScale
      let pointY = (point.latitude - start.latitude) * latitudeScale
      let squaredLength = segmentX * segmentX + segmentY * segmentY
      let fraction =
        squaredLength > 0
        ? min(
          1,
          max(
            0,
            (pointX * segmentX + pointY * segmentY)
              / squaredLength
          )
        ) : 0
      let deltaX = pointX - segmentX * fraction
      let deltaY = pointY - segmentY * fraction
      let bearing = atan2(segmentX, segmentY) * 180 / .pi
      return (
        hypot(deltaX, deltaY),
        bearing >= 0 ? bearing : bearing + 360
      )
    }

    private static func angularDifferenceDegrees(
      _ lhs: Double,
      _ rhs: Double
    ) -> Double {
      let difference =
        abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
      return min(difference, 360 - difference)
    }
  }
#endif
