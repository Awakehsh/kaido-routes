#if canImport(MapKit)
  import CoreLocation
  import Foundation
  import KaidoSurfaceRouting
  @preconcurrency import MapKit

  public struct MapKitSurfaceRouteProvider: SurfaceRouteProvider {
    public let metadata = SurfaceRouteProviderMetadata(
      id: "apple.mapkit",
      adapterVersion: "1.0.0",
      providerVersion: nil,
      dataReviewStatus: .reviewRequired
    )

    public init() {}

    public func routes(for request: SurfaceRouteRequest) async -> SurfaceProviderResponse {
      guard request.origin.isValid, request.destinationAnchor.coordinate.isValid else {
        return .failure(
          SurfaceProviderFailure(
            kind: .invalidRequest,
            providerErrorCode: "INVALID_COORDINATE"
          )
        )
      }

      let directionsRequest = MKDirections.Request()
      directionsRequest.source = Self.mapItem(for: request.origin)
      directionsRequest.destination = Self.mapItem(for: request.destinationAnchor.coordinate)
      directionsRequest.transportType = .automobile
      directionsRequest.requestsAlternateRoutes = request.preferences.requestAlternatives

      if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
        directionsRequest.highwayPreference = request.preferences.avoidHighways ? .avoid : .any
        directionsRequest.tollPreference = request.preferences.avoidTolls ? .avoid : .any
      }

      do {
        let response = try await MKDirections(request: directionsRequest).calculate()
        guard !response.routes.isEmpty else {
          return .failure(
            SurfaceProviderFailure(
              kind: .noRoute,
              providerErrorCode: "EMPTY_ROUTE_SET"
            )
          )
        }

        return .success(
          response.routes.enumerated().map { index, route in
            Self.candidate(from: route, requestID: request.id, index: index)
          }
        )
      } catch {
        return .failure(Self.failure(from: error))
      }
    }

    private static func mapItem(for coordinate: SurfaceCoordinate) -> MKMapItem {
      let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
      if #available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, *) {
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

    private static func candidate(
      from route: MKRoute,
      requestID: String,
      index: Int
    ) -> SurfaceRouteCandidate {
      let flags: (hasHighways: Bool?, hasTolls: Bool?)
      if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
        flags = (route.hasHighways, route.hasTolls)
      } else {
        flags = (nil, nil)
      }

      return SurfaceRouteCandidate(
        id: "\(requestID).mapkit.\(index)",
        providerID: "apple.mapkit",
        coordinates: coordinates(from: route.polyline),
        steps: route.steps.enumerated().map { stepIndex, step in
          SurfaceRouteStep(
            id: "\(requestID).mapkit.\(index).step.\(stepIndex)",
            instruction: step.instructions,
            notice: step.notice,
            distanceMeters: step.distance
          )
        },
        distanceMeters: route.distance,
        expectedTravelTimeSeconds: route.expectedTravelTime,
        hasHighways: flags.hasHighways,
        hasTolls: flags.hasTolls,
        advisoryNotices: route.advisoryNotices
      )
    }

    private static func coordinates(from polyline: MKPolyline) -> [SurfaceCoordinate] {
      let points = polyline.points()
      return (0..<polyline.pointCount).map { index in
        let coordinate = points[index].coordinate
        return SurfaceCoordinate(
          latitude: coordinate.latitude,
          longitude: coordinate.longitude
        )
      }
    }

    private static func failure(from error: any Error) -> SurfaceProviderFailure {
      let nsError = error as NSError
      if nsError.domain == NSURLErrorDomain {
        return SurfaceProviderFailure(
          kind: nsError.code == NSURLErrorCancelled ? .cancelled : .network,
          providerErrorCode: "\(nsError.code)",
          message: nsError.localizedDescription
        )
      }

      if nsError.domain == MKError.errorDomain,
        nsError.code >= 0,
        let code = MKError.Code(rawValue: UInt(nsError.code))
      {
        let kind: SurfaceProviderFailure.Kind
        switch code {
        case .directionsNotFound, .placemarkNotFound:
          kind = .noRoute
        case .loadingThrottled:
          kind = .throttled
        case .serverFailure:
          kind = .server
        case .unknown, .decodingFailed:
          kind = .unknown
        @unknown default:
          kind = .unknown
        }
        return SurfaceProviderFailure(
          kind: kind,
          providerErrorCode: "MKError.\(code.rawValue)",
          message: nsError.localizedDescription
        )
      }

      return SurfaceProviderFailure(
        kind: .unknown,
        providerErrorCode: "\(nsError.domain).\(nsError.code)",
        message: nsError.localizedDescription
      )
    }
  }
#endif
