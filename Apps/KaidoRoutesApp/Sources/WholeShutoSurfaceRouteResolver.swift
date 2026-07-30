import CoreLocation
import KaidoRouting
@preconcurrency import MapKit

protocol WholeShutoSurfaceRouteResolving: Sendable {
  func route(
    from origin: ShutoCoordinate,
    to destination: ShutoCoordinate
  ) async -> WholeShutoSurfaceRoute?
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
