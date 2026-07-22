import Foundation

public enum OSRMDrivingSide: String, Codable, Sendable {
  case left
  case right
}

public enum OSRMSurfaceRouteNormalizationError: Error, Equatable, Sendable {
  case invalidIdentity
  case invalidResponse
  case unsuccessfulCode(String)
  case missingProviderDataset
  case providerDatasetMismatch(expected: String, received: String)
  case invalidRouteCount(Int)
  case invalidLegCount(Int)
  case invalidRouteMetrics
  case invalidRouteGeometry
  case invalidNodeAnnotation
  case invalidSteps
  case unsupportedDrivingSide(stepIndex: Int, received: String)
}

extension OSRMSurfaceRouteNormalizationError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .invalidIdentity:
      "candidate, provider, and expected dataset identity must be present"
    case .invalidResponse:
      "OSRM route response cannot be decoded"
    case .unsuccessfulCode(let code):
      "OSRM route response code is \(code), not Ok"
    case .missingProviderDataset:
      "OSRM response omits data_version; the build must set --data_version"
    case .providerDatasetMismatch(let expected, let received):
      "OSRM dataset \(received) does not match expected dataset \(expected)"
    case .invalidRouteCount(let count):
      "bounded surface routing requires exactly one OSRM route, received \(count)"
    case .invalidLegCount(let count):
      "bounded surface routing requires exactly one OSRM leg, received \(count)"
    case .invalidRouteMetrics:
      "OSRM route or step metrics are invalid"
    case .invalidRouteGeometry:
      "OSRM route geometry is invalid or is not a full GeoJSON LineString"
    case .invalidNodeAnnotation:
      "OSRM route lacks a valid ordered annotations=nodes path"
    case .invalidSteps:
      "OSRM route lacks valid diagnostic steps"
    case .unsupportedDrivingSide(let stepIndex, let received):
      "OSRM step \(stepIndex) reports driving_side=\(received)"
    }
  }
}

public struct OSRMNormalizedSurfaceRoute: Equatable, Sendable {
  public let candidateWithoutSelectedPathEvidence: SurfaceRouteCandidate
  public let translationRequest: OSMNodePathTranslationRequest

  public init(
    candidateWithoutSelectedPathEvidence: SurfaceRouteCandidate,
    translationRequest: OSMNodePathTranslationRequest
  ) {
    self.candidateWithoutSelectedPathEvidence = candidateWithoutSelectedPathEvidence
    self.translationRequest = translationRequest
  }

  public func translatedCandidate(
    graph: SurfaceRoadGraphSnapshot,
    configuration: OSMNodePathTranslatorConfiguration = .init()
  ) throws -> SurfaceRouteCandidate {
    try translatedCandidate(
      translator: OSMNodePathTranslator(graph: graph, configuration: configuration)
    )
  }

  public func translatedCandidate(
    translator: OSMNodePathTranslator
  ) throws -> SurfaceRouteCandidate {
    let evidence = try translator.translate(translationRequest)
    let candidate = candidateWithoutSelectedPathEvidence
    return SurfaceRouteCandidate(
      id: candidate.id,
      providerID: candidate.providerID,
      coordinates: candidate.coordinates,
      steps: candidate.steps,
      distanceMeters: candidate.distanceMeters,
      expectedTravelTimeSeconds: candidate.expectedTravelTimeSeconds,
      hasHighways: candidate.hasHighways,
      hasTolls: candidate.hasTolls,
      advisoryNotices: candidate.advisoryNotices,
      selectedPathEvidence: evidence
    )
  }
}

/// Converts one bounded OSRM route response into Kaido surface-route input.
///
/// The build must set `osrm-extract --data_version` to the exact dataset ID in
/// the checksummed build manifest. `data_version` missing from the response is
/// not treated as an implicit match. OSRM maneuver fields remain diagnostic;
/// they never author Kaido's localized `GuidanceFrame`.
public struct OSRMSurfaceRouteNormalizer: Sendable {
  public let providerID: String
  public let expectedProviderDatasetID: String
  public let requiredDrivingSide: OSRMDrivingSide

  public init(
    providerID: String,
    expectedProviderDatasetID: String,
    requiredDrivingSide: OSRMDrivingSide = .left
  ) {
    self.providerID = providerID
    self.expectedProviderDatasetID = expectedProviderDatasetID
    self.requiredDrivingSide = requiredDrivingSide
  }

  public func normalize(
    routeResponseData: Data,
    candidateID: String
  ) throws -> OSRMNormalizedSurfaceRoute {
    guard !providerID.isEmpty, !expectedProviderDatasetID.isEmpty, !candidateID.isEmpty else {
      throw OSRMSurfaceRouteNormalizationError.invalidIdentity
    }

    let response: RouteResponse
    do {
      response = try JSONDecoder().decode(RouteResponse.self, from: routeResponseData)
    } catch {
      throw OSRMSurfaceRouteNormalizationError.invalidResponse
    }
    guard response.code == "Ok" else {
      throw OSRMSurfaceRouteNormalizationError.unsuccessfulCode(response.code)
    }
    guard let receivedDatasetID = response.dataVersion, !receivedDatasetID.isEmpty else {
      throw OSRMSurfaceRouteNormalizationError.missingProviderDataset
    }
    guard receivedDatasetID == expectedProviderDatasetID else {
      throw OSRMSurfaceRouteNormalizationError.providerDatasetMismatch(
        expected: expectedProviderDatasetID,
        received: receivedDatasetID
      )
    }
    let routes = response.routes ?? []
    guard routes.count == 1 else {
      throw OSRMSurfaceRouteNormalizationError.invalidRouteCount(routes.count)
    }
    let route = routes[0]
    guard route.legs.count == 1 else {
      throw OSRMSurfaceRouteNormalizationError.invalidLegCount(route.legs.count)
    }
    guard route.distance.isFinite, route.distance >= 0,
      route.duration.isFinite, route.duration >= 0,
      route.legs[0].steps.allSatisfy({ step in
        step.distance.isFinite && step.distance >= 0
          && step.duration.isFinite && step.duration >= 0
      })
    else {
      throw OSRMSurfaceRouteNormalizationError.invalidRouteMetrics
    }

    let coordinates = try normalizeGeometry(route.geometry)
    let nodeIDs = route.legs[0].annotation.nodes
    guard nodeIDs.count >= 2, nodeIDs.allSatisfy({ $0 > 0 }),
      zip(nodeIDs, nodeIDs.dropFirst()).allSatisfy({ pair in pair.0 != pair.1 })
    else {
      throw OSRMSurfaceRouteNormalizationError.invalidNodeAnnotation
    }
    guard !route.legs[0].steps.isEmpty,
      route.legs[0].steps.allSatisfy({ !$0.maneuver.type.isEmpty })
    else {
      throw OSRMSurfaceRouteNormalizationError.invalidSteps
    }
    for (index, step) in route.legs[0].steps.enumerated()
    where step.drivingSide != requiredDrivingSide.rawValue {
      throw OSRMSurfaceRouteNormalizationError.unsupportedDrivingSide(
        stepIndex: index,
        received: step.drivingSide
      )
    }

    let steps = route.legs[0].steps.enumerated().map { index, step in
      let maneuver = [step.maneuver.type, step.maneuver.modifier]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
      let roadIdentity = [step.ref, step.name, step.destinations]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " / ")
      return SurfaceRouteStep(
        id: "osrm.maneuver.\(index)",
        instruction: maneuver,
        notice: roadIdentity.isEmpty ? nil : roadIdentity,
        distanceMeters: step.distance
      )
    }
    let candidate = SurfaceRouteCandidate(
      id: candidateID,
      providerID: providerID,
      coordinates: coordinates,
      steps: steps,
      distanceMeters: route.distance,
      expectedTravelTimeSeconds: route.duration
    )
    return OSRMNormalizedSurfaceRoute(
      candidateWithoutSelectedPathEvidence: candidate,
      translationRequest: OSMNodePathTranslationRequest(
        providerDatasetID: receivedDatasetID,
        routeCoordinates: coordinates,
        orderedOSMNodeIDs: nodeIDs
      )
    )
  }

  private func normalizeGeometry(_ geometry: GeoJSONLineString) throws -> [SurfaceCoordinate] {
    guard geometry.type == "LineString", geometry.coordinates.count >= 2 else {
      throw OSRMSurfaceRouteNormalizationError.invalidRouteGeometry
    }
    let coordinates = try geometry.coordinates.map { coordinate -> SurfaceCoordinate in
      guard coordinate.count == 2,
        coordinate[0].isFinite, coordinate[1].isFinite
      else {
        throw OSRMSurfaceRouteNormalizationError.invalidRouteGeometry
      }
      return SurfaceCoordinate(latitude: coordinate[1], longitude: coordinate[0])
    }
    guard coordinates.allSatisfy(\.isValid) else {
      throw OSRMSurfaceRouteNormalizationError.invalidRouteGeometry
    }
    return coordinates
  }
}

private struct RouteResponse: Decodable {
  let code: String
  let dataVersion: String?
  let routes: [Route]?

  private enum CodingKeys: String, CodingKey {
    case code
    case dataVersion = "data_version"
    case routes
  }
}

private struct Route: Decodable {
  let distance: Double
  let duration: Double
  let geometry: GeoJSONLineString
  let legs: [RouteLeg]
}

private struct GeoJSONLineString: Decodable {
  let type: String
  let coordinates: [[Double]]
}

private struct RouteLeg: Decodable {
  let annotation: RouteAnnotation
  let steps: [RouteStep]
}

private struct RouteAnnotation: Decodable {
  let nodes: [Int64]
}

private struct RouteStep: Decodable {
  let distance: Double
  let duration: Double
  let name: String?
  let ref: String?
  let destinations: String?
  let drivingSide: String
  let maneuver: RouteManeuver

  private enum CodingKeys: String, CodingKey {
    case distance
    case duration
    case name
    case ref
    case destinations
    case drivingSide = "driving_side"
    case maneuver
  }
}

private struct RouteManeuver: Decodable {
  let type: String
  let modifier: String?
}
