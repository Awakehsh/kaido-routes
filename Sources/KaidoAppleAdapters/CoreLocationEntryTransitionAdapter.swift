#if canImport(CoreLocation)
  import CoreLocation
  import Foundation
  import KaidoNavigation

  /// Matches Core Location fixes against the exact release-bound entry corridor.
  ///
  /// This adapter produces evidence only. It cannot advance the journey: the
  /// `NavigationSession` actor independently checks release identity, time,
  /// ambiguity, heading, simulation provenance, and the complete ordered edge
  /// sequence before it grants strict-route entry.
  public struct CoreLocationEntryTransitionAdapter: Sendable {
    public let context: EntryTransitionAdmissionContext

    private var matcherSession: RouteMatcherSession
    private let edgeByID: [String: RouteMatcherDirectedEdge]

    public init(
      context: EntryTransitionAdmissionContext,
      matcherConfiguration: RouteAwareSwiftMatcherConfiguration = .init(),
      matcherSessionConfiguration: RouteMatcherSessionConfiguration = .init()
    ) throws {
      self.context = context
      matcherSession = try RouteAwareSwiftMatcher(
        configuration: matcherConfiguration
      ).makeSession(
        corridor: context.matcherCorridor,
        sessionConfiguration: matcherSessionConfiguration
      )
      edgeByID = Dictionary(
        context.matcherCorridor.edges.map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
      )
    }

    public mutating func adapt(
      _ envelope: CoreLocationObservationEnvelope
    ) throws -> EntryTransitionEvidence {
      let observation = envelope.observation
      let estimate = try matcherSession.observe(observation)
      let headingError: Double? = estimate.directedEdgeID.flatMap { edgeID in
        guard let course = observation.courseDegrees,
          observation.speedMetersPerSecond.map({ $0 >= 2 }) == true,
          let edge = edgeByID[edgeID],
          let bearing = Self.closestBearing(
            to: observation.coordinate,
            on: edge.coordinates
          )
        else {
          return nil
        }
        return Self.angularDifferenceDegrees(course, bearing)
      }

      return EntryTransitionEvidence(
        context: context,
        observationID: observation.id ?? "",
        observedAtMilliseconds: observation.observedAtMilliseconds,
        receivedAtMilliseconds: observation.receivedAtMilliseconds,
        directedEdgeID: estimate.directedEdgeID,
        candidateEdgeIDs: estimate.candidateEdgeIDs,
        confidence: estimate.confidence,
        headingErrorDegrees: headingError,
        isSimulatedBySoftware: envelope.provenance.isSimulatedBySoftware
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
        let measurement = segmentMeasurement(point: point, start: start, end: end)
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
      let referenceLatitude = (start.latitude + end.latitude + point.latitude) / 3
      let latitudeScale = earthRadiusMeters * .pi / 180
      let longitudeScale = latitudeScale * cos(referenceLatitude * .pi / 180)
      let segmentX = (end.longitude - start.longitude) * longitudeScale
      let segmentY = (end.latitude - start.latitude) * latitudeScale
      let pointX = (point.longitude - start.longitude) * longitudeScale
      let pointY = (point.latitude - start.latitude) * latitudeScale
      let squaredLength = segmentX * segmentX + segmentY * segmentY
      let fraction =
        squaredLength > 0
        ? min(1, max(0, (pointX * segmentX + pointY * segmentY) / squaredLength))
        : 0
      let deltaX = pointX - segmentX * fraction
      let deltaY = pointY - segmentY * fraction
      let bearing = atan2(segmentX, segmentY) * 180 / .pi
      return (
        distanceMeters: hypot(deltaX, deltaY),
        bearingDegrees: bearing >= 0 ? bearing : bearing + 360
      )
    }

    private static func angularDifferenceDegrees(_ lhs: Double, _ rhs: Double) -> Double {
      let difference = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
      return min(difference, 360 - difference)
    }
  }
#endif
