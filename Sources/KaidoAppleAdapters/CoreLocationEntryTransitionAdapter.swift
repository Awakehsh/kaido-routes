#if canImport(CoreLocation)
  import CoreLocation
  import Foundation
  import KaidoNavigation

  /// Matches Core Location fixes against the exact release-bound entry corridor.
  ///
  /// This adapter produces evidence only. It cannot advance the journey: the
  /// `NavigationSession` actor independently checks release identity, time,
  /// heading, simulation provenance and ordered route-head progression before
  /// it grants strict-route entry. The matcher's own estimate is passed on;
  /// no fix is relabelled onto the first route edge. The one correction is
  /// the pass of a road the plan drives more than once: the car can only be
  /// on the earliest pass it can have reached since this adapter first saw
  /// it, and the matcher is restarted there.
  public struct CoreLocationEntryTransitionAdapter: Sendable {
    public let context: EntryTransitionAdmissionContext

    private var matcherSession: RouteMatcherSession
    private let edgeByID: [String: RouteMatcherDirectedEdge]
    private let passReach: RoutePassReach
    private var firstObservedAtMilliseconds: Int?

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
      passReach = RoutePassReach(corridor: context.matcherCorridor)
    }

    public mutating func adapt(
      _ envelope: CoreLocationObservationEnvelope
    ) throws -> EntryTransitionEvidence {
      let observation = envelope.observation
      let estimate = try estimate(for: observation)
      return EntryTransitionEvidence(
        context: context,
        observationID: observation.id ?? "",
        observedAtMilliseconds: observation.observedAtMilliseconds,
        receivedAtMilliseconds: observation.receivedAtMilliseconds,
        directedEdgeID: estimate.directedEdgeID,
        occurrenceID: estimate.occurrenceID,
        candidateEdgeIDs: estimate.candidateEdgeIDs,
        confidence: estimate.confidence,
        coordinate: observation.coordinate,
        horizontalAccuracyMeters: observation.horizontalAccuracyMeters,
        distanceMeters: estimate.distanceMeters,
        headingErrorDegrees: headingError(
          estimate: estimate,
          observation: observation
        ),
        isSimulatedBySoftware: envelope.provenance.isSimulatedBySoftware
      )
    }

    /// Offers the same fix as an on-route position rather than an entry-ramp
    /// step, for a driver who says they are already on the selected route.
    ///
    /// Nothing here is relaxed: the estimate is the matcher's own, including
    /// the occurrence it resolved on the pass the car can have reached.
    /// `RouteJoinAdmission` decides whether it holds.
    public mutating func adaptRouteJoin(
      _ envelope: CoreLocationObservationEnvelope
    ) throws -> RouteJoinEvidence {
      let observation = envelope.observation
      let estimate = try estimate(for: observation)
      return RouteJoinEvidence(
        context: context,
        observationID: observation.id ?? "",
        observedAtMilliseconds: observation.observedAtMilliseconds,
        receivedAtMilliseconds: observation.receivedAtMilliseconds,
        occurrenceID: estimate.occurrenceID,
        directedEdgeID: estimate.directedEdgeID,
        candidateEdgeIDs: estimate.candidateEdgeIDs,
        confidence: estimate.confidence,
        headingErrorDegrees: headingError(
          estimate: estimate,
          observation: observation
        ),
        isSimulatedBySoftware: envelope.provenance.isSimulatedBySoftware
      )
    }

    private mutating func estimate(
      for observation: RouteMatcherObservation
    ) throws -> MatcherEstimate {
      let firstObservedAt =
        firstObservedAtMilliseconds ?? observation.observedAtMilliseconds
      firstObservedAtMilliseconds = firstObservedAt
      let estimate = try matcherSession.observe(observation)
      guard
        let pass = passReach.earlierPass(
          of: estimate,
          elapsedMilliseconds: observation.observedAtMilliseconds - firstObservedAt
        )
      else { return estimate }
      try matcherSession.restart(at: pass)
      return MatcherEstimate(
        observationID: estimate.observationID,
        estimatedAtMilliseconds: estimate.estimatedAtMilliseconds,
        directedEdgeID: estimate.directedEdgeID,
        occurrenceID: pass,
        candidateEdgeIDs: estimate.candidateEdgeIDs,
        confidence: estimate.confidence,
        distanceMeters: estimate.distanceMeters,
        fractionAlongEdge: estimate.fractionAlongEdge
      )
    }

    private func headingError(
      estimate: MatcherEstimate,
      observation: RouteMatcherObservation
    ) -> Double? {
      estimate.directedEdgeID.flatMap { edgeID in
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
