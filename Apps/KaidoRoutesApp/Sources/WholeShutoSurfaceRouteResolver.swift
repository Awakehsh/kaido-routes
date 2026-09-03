import CoreLocation
import KaidoRouting
import OSLog
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
    var surfaceRoutesByRoutePlanID: [
      String: WholeShutoRouteChoiceSurfaceRoutes
    ] = [:]
    // Evaluate one candidate at a time (two legs in parallel) so a four-route
    // result set cannot fan out into eight simultaneous MapKit requests.
    for recommendation in recommendations {
      guard !Task.isCancelled else { break }
      let entry = recommendation.route.coordinates.first
        ?? recommendation.route.entryFacility.coordinate
      let exit = recommendation.route.coordinates.last
        ?? recommendation.route.exitFacility.coordinate
      async let access = resolver.route(from: origin, to: entry)
      async let egress = resolver.route(from: exit, to: destination)
      let routes = await (access, egress)
      if let accessRoute = routes.0, let egressRoute = routes.1 {
        surfaceRoutesByRoutePlanID[recommendation.route.routePlan.id] =
          WholeShutoRouteChoiceSurfaceRoutes(
            access: accessRoute,
            egress: egressRoute
          )
      }
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
  private static let logger = Logger(
    subsystem: "app.kaidoroutes",
    category: "surface-routing"
  )

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
        Self.logger.error("MapKit returned no automobile route")
        return nil
      }
      guard
        route.polyline.pointCount >= 2,
        route.distance.isFinite,
        route.distance >= 0,
        route.expectedTravelTime.isFinite,
        route.expectedTravelTime >= 0
      else {
        Self.logger.error("MapKit returned invalid route geometry or metrics")
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
        },
        guidanceLanguageCode: Self.supportedSpeechLanguageCode(
          Locale.preferredLanguages.first ?? Locale.current.identifier
        )
      )
    } catch {
      let nsError = error as NSError
      Self.logger.error(
        "MapKit route failed: domain=\(nsError.domain, privacy: .public) code=\(nsError.code)"
      )
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

  private static func supportedSpeechLanguageCode(_ identifier: String) -> String {
    let normalized = identifier.replacingOccurrences(of: "_", with: "-")
      .lowercased()
    if normalized.hasPrefix("ja") { return "ja-JP" }
    if normalized.hasPrefix("zh-hant")
      || normalized.hasPrefix("zh-tw")
      || normalized.hasPrefix("zh-hk")
    {
      return "zh-TW"
    }
    if normalized.hasPrefix("zh") { return "zh-CN" }
    return "en-US"
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
