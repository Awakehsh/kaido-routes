import KaidoNavigation
import KaidoRouting
import KaidoSurfaceRouting

enum WholeShutoLiveJourneyAdmissionError: Error, Equatable {
  case invalidSurfaceProjection
}

/// App presentation geometry bound to one core live admission.
///
/// Surface geometry may drive map presentation and arrival progress, but it
/// cannot alter the release-owned RoutePlan or expressway matcher.
struct WholeShutoLiveJourneyAdmission: Sendable {
  let core: KaidoLiveJourneyAdmission
  let accessRoute: WholeShutoSurfaceRoute
  let egressRoute: WholeShutoSurfaceRoute

  init(
    core: KaidoLiveJourneyAdmission,
    accessRoute: WholeShutoSurfaceRoute,
    egressRoute: WholeShutoSurfaceRoute
  ) throws {
    guard
      let accessLeg = core.journeyPlan.accessLeg,
      let egressLeg = core.journeyPlan.egressLeg,
      let returnTarget = core.journeyPlan.returnTarget,
      let accessDefinition =
        core.release.navigation.bundle.surfaceAccessDefinition,
      let egressDefinition =
        core.release.navigation.bundle.surfaceEgressDefinition,
      let selectedEgressOptionID =
        core.journeyPlan.selectedEgressOptionID,
      let egressPolicy = egressDefinition.policies.first(where: {
        $0.egressOptionID == selectedEgressOptionID
      }),
      Self.isUsable(accessRoute),
      Self.isUsable(egressRoute),
      Self.matchesMetrics(accessRoute, leg: accessLeg),
      Self.matchesMetrics(egressRoute, leg: egressLeg),
      Self.matches(
        accessRoute.coordinates.first,
        returnTarget.coordinate
      ),
      Self.matches(
        accessRoute.coordinates.last,
        accessDefinition.approachPolicy.destinationAnchor.coordinate
      ),
      Self.matches(
        egressRoute.coordinates.first,
        egressPolicy.originAnchor.coordinate
      ),
      Self.matches(
        egressRoute.coordinates.last,
        returnTarget.coordinate
      )
    else {
      throw WholeShutoLiveJourneyAdmissionError.invalidSurfaceProjection
    }
    self.core = core
    self.accessRoute = accessRoute
    self.egressRoute = egressRoute
  }

  private static func isUsable(
    _ route: WholeShutoSurfaceRoute
  ) -> Bool {
    route.coordinates.count >= 2
      && route.distanceMeters.isFinite
      && route.distanceMeters >= 0
      && route.expectedTravelTimeSeconds.isFinite
      && route.expectedTravelTimeSeconds >= 0
      && route.coordinates.allSatisfy {
        $0.latitude.isFinite && $0.longitude.isFinite
      }
  }

  private static func matchesMetrics(
    _ route: WholeShutoSurfaceRoute,
    leg: JourneySurfaceLeg
  ) -> Bool {
    abs(route.distanceMeters - leg.distanceMeters) <= 0.01
      && abs(
        route.expectedTravelTimeSeconds
          - leg.expectedTravelTimeSeconds
      ) <= 0.01
  }

  private static func matches(
    _ coordinate: ShutoCoordinate?,
    _ expected: SurfaceCoordinate
  ) -> Bool {
    guard let coordinate else { return false }
    return abs(coordinate.latitude - expected.latitude) <= 0.000_001
      && abs(coordinate.longitude - expected.longitude) <= 0.000_001
  }
}
