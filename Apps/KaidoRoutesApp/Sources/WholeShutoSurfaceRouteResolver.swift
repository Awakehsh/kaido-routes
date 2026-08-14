import CoreLocation
import KaidoRouting
@preconcurrency import MapKit

protocol WholeShutoSurfaceRouteResolving: Sendable {
  func route(
    from origin: ShutoCoordinate,
    to destination: ShutoCoordinate
  ) async -> WholeShutoSurfaceRoute?
}

struct WholeShutoRouteChoiceSurfaceRoutes: Equatable, Sendable {
  let access: WholeShutoSurfaceRoute
  let egress: WholeShutoSurfaceRoute
}

struct WholeShutoRouteChoiceEvaluation: Equatable, Sendable {
  let recommendations: [ShutoRouteRecommendation]
  let surfaceRoutesByRoutePlanID: [String: WholeShutoRouteChoiceSurfaceRoutes]
  let usesComparableProviderMetrics: Bool
}

struct WholeShutoSurfaceRouteChoiceEvaluator: Sendable {
  private struct CandidateResult: Sendable {
    let routePlanID: String
    let surfaceRoutes: WholeShutoRouteChoiceSurfaceRoutes?
  }

  private static let surfaceScoreWeight = 1.25
  private static let surfaceReferenceSpeedMetersPerSecond = 8.3

  private let resolver: any WholeShutoSurfaceRouteResolving

  init(resolver: any WholeShutoSurfaceRouteResolving) {
    self.resolver = resolver
  }

  func evaluate(
    recommendations: [ShutoRouteRecommendation],
    origin: ShutoCoordinate,
    destination: ShutoCoordinate
  ) async -> WholeShutoRouteChoiceEvaluation {
    let surfaceRoutesByRoutePlanID = await withTaskGroup(
      of: CandidateResult.self,
      returning: [
        String: WholeShutoRouteChoiceSurfaceRoutes
      ].self
    ) { group in
      for recommendation in recommendations {
        group.addTask {
          async let access = resolver.route(
            from: origin,
            to: recommendation.route.entryFacility.coordinate
          )
          async let egress = resolver.route(
            from: recommendation.route.exitFacility.coordinate,
            to: destination
          )
          let routes = await (access, egress)
          let surfaceRoutes = routes.0.flatMap { accessRoute in
            routes.1.map { egressRoute in
              WholeShutoRouteChoiceSurfaceRoutes(
                access: accessRoute,
                egress: egressRoute
              )
            }
          }
          return CandidateResult(
            routePlanID: recommendation.route.routePlan.id,
            surfaceRoutes: surfaceRoutes
          )
        }
      }

      var results: [String: WholeShutoRouteChoiceSurfaceRoutes] = [:]
      for await result in group {
        if let surfaceRoutes = result.surfaceRoutes {
          results[result.routePlanID] = surfaceRoutes
        }
      }
      return results
    }

    guard
      !recommendations.isEmpty,
      surfaceRoutesByRoutePlanID.count == recommendations.count
    else {
      return WholeShutoRouteChoiceEvaluation(
        recommendations: recommendations,
        surfaceRoutesByRoutePlanID: surfaceRoutesByRoutePlanID,
        usesComparableProviderMetrics: false
      )
    }

    let refinedRecommendations = recommendations.map { recommendation in
      guard
        let routes = surfaceRoutesByRoutePlanID[
          recommendation.route.routePlan.id
        ]
      else {
        return recommendation
      }
      let originalSurfaceScore =
        (recommendation.surfaceAccessDistanceMeters
          + recommendation.surfaceEgressDistanceMeters) * Self.surfaceScoreWeight
      let kaidoRouteScore =
        recommendation.totalScoreMeters - originalSurfaceScore
      let providerSurfaceScore =
        (routes.access.expectedTravelTimeSeconds
          + routes.egress.expectedTravelTimeSeconds)
        * Self.surfaceReferenceSpeedMetersPerSecond
        * Self.surfaceScoreWeight
      return ShutoRouteRecommendation(
        route: recommendation.route,
        surfaceAccessDistanceMeters: routes.access.distanceMeters,
        surfaceEgressDistanceMeters: routes.egress.distanceMeters,
        totalScoreMeters: kaidoRouteScore + providerSurfaceScore
      )
    }
    .sorted {
      if $0.totalScoreMeters != $1.totalScoreMeters {
        return $0.totalScoreMeters < $1.totalScoreMeters
      }
      return $0.route.routePlan.id < $1.route.routePlan.id
    }

    return WholeShutoRouteChoiceEvaluation(
      recommendations: refinedRecommendations,
      surfaceRoutesByRoutePlanID: surfaceRoutesByRoutePlanID,
      usesComparableProviderMetrics: true
    )
  }
}

struct WholeShutoMapKitSurfaceRouteResolver:
  WholeShutoSurfaceRouteResolving,
  Sendable
{
  func route(
    from origin: ShutoCoordinate,
    to destination: ShutoCoordinate
  ) async -> WholeShutoSurfaceRoute? {
    let request = MKDirections.Request()
    request.source = Self.mapItem(origin)
    request.destination = Self.mapItem(destination)
    request.transportType = .automobile
    request.requestsAlternateRoutes = false
    request.highwayPreference = .avoid
    request.tollPreference = .avoid
    do {
      guard
        let route = try await MKDirections(request: request)
          .calculate().routes.first
      else {
        return nil
      }
      let points = route.polyline.points()
      return WholeShutoSurfaceRoute(
        coordinates: (0..<route.polyline.pointCount).map {
          let coordinate = points[$0].coordinate
          return ShutoCoordinate(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
          )
        },
        distanceMeters: route.distance,
        expectedTravelTimeSeconds: route.expectedTravelTime,
        instructions: route.steps.map(\.instructions).filter {
          !$0.isEmpty
        },
        steps: route.steps.compactMap { step in
          guard !step.instructions.isEmpty, step.distance > 0 else {
            return nil
          }
          return WholeShutoSurfaceRouteStep(
            instruction: step.instructions,
            distanceMeters: step.distance
          )
        }
      )
    } catch {
      return nil
    }
  }

  private static func mapItem(
    _ coordinate: ShutoCoordinate
  ) -> MKMapItem {
    let location = CLLocation(
      latitude: coordinate.latitude,
      longitude: coordinate.longitude
    )
    if #available(iOS 26.0, *) {
      return MKMapItem(location: location, address: nil)
    }
    return MKMapItem(
      placemark: MKPlacemark(
        coordinate: CLLocationCoordinate2D(
          latitude: coordinate.latitude,
          longitude: coordinate.longitude
        )
      )
    )
  }
}

struct WholeShutoPreviewSurfaceRouteResolver:
  WholeShutoSurfaceRouteResolving,
  Sendable
{
  func route(
    from origin: ShutoCoordinate,
    to destination: ShutoCoordinate
  ) async -> WholeShutoSurfaceRoute? {
    let distance = CLLocation(
      latitude: origin.latitude,
      longitude: origin.longitude
    ).distance(
      from: CLLocation(
        latitude: destination.latitude,
        longitude: destination.longitude
      )
    )
    return WholeShutoSurfaceRoute(
      coordinates: [origin, destination],
      distanceMeters: distance,
      expectedTravelTimeSeconds: distance / 8.3,
      instructions: []
    )
  }
}
