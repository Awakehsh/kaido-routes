import Foundation

public enum GraphHopperSurfaceRouteNormalizationError: Error, Equatable, Sendable {
  case invalidIdentity
  case invalidInfoResponse
  case invalidRouteResponse
  case providerVersionMismatch(expected: String, received: String)
  case dataTimestampMismatch(expected: String, received: String)
  case invalidDataTimestamp(String)
  case profileUnavailable(String)
  case encodedValueUnavailable(String)
  case invalidRouteCount(Int)
  case encodedRouteGeometry
  case invalidRouteMetrics
  case invalidRouteGeometry
  case invalidInstructions
  case invalidPathDetail(name: String)
  case unsupportedCountry(segmentIndex: Int, received: String)
}

extension GraphHopperSurfaceRouteNormalizationError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .invalidIdentity:
      "candidate, provider, profile, version, timestamp, and dataset identity must be present"
    case .invalidInfoResponse:
      "GraphHopper info response cannot be decoded"
    case .invalidRouteResponse:
      "GraphHopper route response cannot be decoded"
    case .providerVersionMismatch(let expected, let received):
      "GraphHopper version \(received) does not match expected version \(expected)"
    case .dataTimestampMismatch(let expected, let received):
      "GraphHopper road timestamp \(received) does not match expected timestamp \(expected)"
    case .invalidDataTimestamp(let received):
      "GraphHopper road timestamp \(received) is missing, invalid, or epoch-valued"
    case .profileUnavailable(let profile):
      "GraphHopper profile \(profile) is unavailable"
    case .encodedValueUnavailable(let value):
      "GraphHopper build does not expose required encoded value \(value)"
    case .invalidRouteCount(let count):
      "bounded surface routing requires exactly one GraphHopper path, received \(count)"
    case .encodedRouteGeometry:
      "GraphHopper route geometry must be an unencoded GeoJSON LineString"
    case .invalidRouteMetrics:
      "GraphHopper route or instruction metrics are invalid"
    case .invalidRouteGeometry:
      "GraphHopper route geometry is invalid or incomplete"
    case .invalidInstructions:
      "GraphHopper route lacks valid diagnostic instructions"
    case .invalidPathDetail(let name):
      "GraphHopper path detail \(name) does not exactly partition the route point pairs"
    case .unsupportedCountry(let segmentIndex, let received):
      "GraphHopper segment \(segmentIndex) reports country=\(received)"
    }
  }
}

public struct GraphHopperNormalizedSurfaceRoute: Equatable, Sendable {
  public let candidateWithoutSelectedPathEvidence: SurfaceRouteCandidate
  public let translationRequest: OSMWayPointPathTranslationRequest

  public init(
    candidateWithoutSelectedPathEvidence: SurfaceRouteCandidate,
    translationRequest: OSMWayPointPathTranslationRequest
  ) {
    self.candidateWithoutSelectedPathEvidence = candidateWithoutSelectedPathEvidence
    self.translationRequest = translationRequest
  }

  public func translatedCandidate(
    graph: SurfaceRoadGraphSnapshot,
    configuration: OSMWayPointPathTranslatorConfiguration = .init()
  ) throws -> SurfaceRouteCandidate {
    try translatedCandidate(
      translator: OSMWayPointPathTranslator(graph: graph, configuration: configuration)
    )
  }

  public func translatedCandidate(
    translator: OSMWayPointPathTranslator
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

/// Converts one manifest-bound GraphHopper route into Kaido surface input.
///
/// The build and request must both disable route-point simplification. Every
/// point pair must then be covered by `edge_key`, `osm_way_id`, and `country`
/// path details. GraphHopper instructions remain diagnostic and never author a
/// localized Kaido `GuidanceFrame`.
public struct GraphHopperSurfaceRouteNormalizer: Sendable {
  public let providerID: String
  public let providerDatasetID: String
  public let expectedProviderVersion: String
  public let expectedRoadDataTimestamp: String
  public let expectedProfileName: String
  public let requiredCountryCode: String

  public init(
    providerID: String,
    providerDatasetID: String,
    expectedProviderVersion: String,
    expectedRoadDataTimestamp: String,
    expectedProfileName: String,
    requiredCountryCode: String = "JPN"
  ) {
    self.providerID = providerID
    self.providerDatasetID = providerDatasetID
    self.expectedProviderVersion = expectedProviderVersion
    self.expectedRoadDataTimestamp = expectedRoadDataTimestamp
    self.expectedProfileName = expectedProfileName
    self.requiredCountryCode = requiredCountryCode
  }

  public func normalize(
    infoResponseData: Data,
    routeResponseData: Data,
    candidateID: String
  ) throws -> GraphHopperNormalizedSurfaceRoute {
    guard !providerID.isEmpty, !providerDatasetID.isEmpty,
      !expectedProviderVersion.isEmpty, !expectedRoadDataTimestamp.isEmpty,
      !expectedProfileName.isEmpty, !requiredCountryCode.isEmpty,
      !candidateID.isEmpty
    else {
      throw GraphHopperSurfaceRouteNormalizationError.invalidIdentity
    }
    try validateTimestamp(expectedRoadDataTimestamp)

    let info: GraphHopperInfoResponse
    do {
      info = try JSONDecoder().decode(GraphHopperInfoResponse.self, from: infoResponseData)
    } catch {
      throw GraphHopperSurfaceRouteNormalizationError.invalidInfoResponse
    }
    guard info.version == expectedProviderVersion else {
      throw GraphHopperSurfaceRouteNormalizationError.providerVersionMismatch(
        expected: expectedProviderVersion,
        received: info.version
      )
    }
    try validateTimestamp(info.dataDate)
    guard info.dataDate == expectedRoadDataTimestamp else {
      throw GraphHopperSurfaceRouteNormalizationError.dataTimestampMismatch(
        expected: expectedRoadDataTimestamp,
        received: info.dataDate
      )
    }
    guard info.profiles.contains(where: { $0.name == expectedProfileName }) else {
      throw GraphHopperSurfaceRouteNormalizationError.profileUnavailable(
        expectedProfileName
      )
    }
    for requiredValue in ["country", "osm_way_id", "road_class", "toll"]
    where info.encodedValues[requiredValue] == nil {
      throw GraphHopperSurfaceRouteNormalizationError.encodedValueUnavailable(
        requiredValue
      )
    }

    let response: GraphHopperRouteResponse
    do {
      response = try JSONDecoder().decode(GraphHopperRouteResponse.self, from: routeResponseData)
    } catch {
      throw GraphHopperSurfaceRouteNormalizationError.invalidRouteResponse
    }
    try validateTimestamp(response.info.roadDataTimestamp)
    guard response.info.roadDataTimestamp == expectedRoadDataTimestamp else {
      throw GraphHopperSurfaceRouteNormalizationError.dataTimestampMismatch(
        expected: expectedRoadDataTimestamp,
        received: response.info.roadDataTimestamp
      )
    }
    guard response.paths.count == 1 else {
      throw GraphHopperSurfaceRouteNormalizationError.invalidRouteCount(
        response.paths.count
      )
    }
    let path = response.paths[0]
    guard path.pointsEncoded == false else {
      throw GraphHopperSurfaceRouteNormalizationError.encodedRouteGeometry
    }
    guard path.distance.isFinite, path.distance >= 0,
      path.timeMilliseconds.isFinite, path.timeMilliseconds >= 0,
      path.instructions.allSatisfy({ instruction in
        instruction.distance.isFinite && instruction.distance >= 0
          && instruction.timeMilliseconds.isFinite && instruction.timeMilliseconds >= 0
      })
    else {
      throw GraphHopperSurfaceRouteNormalizationError.invalidRouteMetrics
    }

    let coordinates = try normalizeGeometry(path.points)
    guard !path.instructions.isEmpty,
      path.instructions.allSatisfy({ instruction in
        !instruction.text.isEmpty && instruction.interval.count == 2
          && instruction.interval[0] >= 0
          && instruction.interval[0] <= instruction.interval[1]
          && instruction.interval[1] < coordinates.count
      })
    else {
      throw GraphHopperSurfaceRouteNormalizationError.invalidInstructions
    }

    let segmentCount = coordinates.count - 1
    let providerEdgeKeys = try expand(
      path.details.edgeKeys,
      name: "edge_key",
      segmentCount: segmentCount
    )
    let osmWayIDs = try expand(
      path.details.osmWayIDs,
      name: "osm_way_id",
      segmentCount: segmentCount
    )
    let countries = try expand(
      path.details.countries,
      name: "country",
      segmentCount: segmentCount
    )
    for (index, country) in countries.enumerated() where country != requiredCountryCode {
      throw GraphHopperSurfaceRouteNormalizationError.unsupportedCountry(
        segmentIndex: index,
        received: country
      )
    }

    let steps = path.instructions.enumerated().map { index, instruction in
      SurfaceRouteStep(
        id: "graphhopper.instruction.\(index)",
        instruction: instruction.text,
        notice: [instruction.streetRef, instruction.streetName]
          .compactMap { $0 }
          .filter { !$0.isEmpty }
          .joined(separator: " / ")
          .nilIfEmpty,
        distanceMeters: instruction.distance
      )
    }
    let candidate = SurfaceRouteCandidate(
      id: candidateID,
      providerID: providerID,
      coordinates: coordinates,
      steps: steps,
      distanceMeters: path.distance,
      expectedTravelTimeSeconds: path.timeMilliseconds / 1_000
    )
    return GraphHopperNormalizedSurfaceRoute(
      candidateWithoutSelectedPathEvidence: candidate,
      translationRequest: OSMWayPointPathTranslationRequest(
        providerDatasetID: providerDatasetID,
        routeCoordinates: coordinates,
        segmentIdentities: zip(providerEdgeKeys, osmWayIDs).map {
          OSMWayPointPathSegmentIdentity(
            providerDirectedEdgeKey: $0,
            osmWayID: $1
          )
        }
      )
    )
  }

  private func validateTimestamp(_ value: String) throws {
    guard value != "1970-01-01T00:00:00Z",
      ISO8601DateFormatter().date(from: value) != nil
    else {
      throw GraphHopperSurfaceRouteNormalizationError.invalidDataTimestamp(value)
    }
  }

  private func normalizeGeometry(
    _ geometry: GraphHopperGeoJSONLineString
  ) throws -> [SurfaceCoordinate] {
    guard geometry.type == "LineString", geometry.coordinates.count >= 2 else {
      throw GraphHopperSurfaceRouteNormalizationError.invalidRouteGeometry
    }
    let coordinates = try geometry.coordinates.map { coordinate -> SurfaceCoordinate in
      guard coordinate.count == 2,
        coordinate[0].isFinite, coordinate[1].isFinite
      else {
        throw GraphHopperSurfaceRouteNormalizationError.invalidRouteGeometry
      }
      return SurfaceCoordinate(latitude: coordinate[1], longitude: coordinate[0])
    }
    guard coordinates.allSatisfy(\.isValid) else {
      throw GraphHopperSurfaceRouteNormalizationError.invalidRouteGeometry
    }
    return coordinates
  }

  private func expand<Value: Decodable & Equatable & Sendable>(
    _ details: [GraphHopperPathDetail<Value>],
    name: String,
    segmentCount: Int
  ) throws -> [Value] {
    var result: [Value] = []
    var expectedStart = 0
    for detail in details {
      guard detail.fromIndex == expectedStart,
        detail.toIndex > detail.fromIndex,
        detail.toIndex <= segmentCount
      else {
        throw GraphHopperSurfaceRouteNormalizationError.invalidPathDetail(name: name)
      }
      result.append(
        contentsOf: repeatElement(detail.value, count: detail.toIndex - detail.fromIndex))
      expectedStart = detail.toIndex
    }
    guard expectedStart == segmentCount, result.count == segmentCount else {
      throw GraphHopperSurfaceRouteNormalizationError.invalidPathDetail(name: name)
    }
    return result
  }
}

private struct GraphHopperInfoResponse: Decodable {
  let profiles: [GraphHopperProfile]
  let version: String
  let encodedValues: [String: [String]]
  let dataDate: String

  private enum CodingKeys: String, CodingKey {
    case profiles
    case version
    case encodedValues = "encoded_values"
    case dataDate = "data_date"
  }
}

private struct GraphHopperProfile: Decodable {
  let name: String
}

private struct GraphHopperRouteResponse: Decodable {
  let info: GraphHopperRouteInfo
  let paths: [GraphHopperPath]
}

private struct GraphHopperRouteInfo: Decodable {
  let roadDataTimestamp: String

  private enum CodingKeys: String, CodingKey {
    case roadDataTimestamp = "road_data_timestamp"
  }
}

private struct GraphHopperPath: Decodable {
  let distance: Double
  let timeMilliseconds: Double
  let pointsEncoded: Bool
  let points: GraphHopperGeoJSONLineString
  let instructions: [GraphHopperInstruction]
  let details: GraphHopperPathDetails

  private enum CodingKeys: String, CodingKey {
    case distance
    case timeMilliseconds = "time"
    case pointsEncoded = "points_encoded"
    case points
    case instructions
    case details
  }
}

private struct GraphHopperGeoJSONLineString: Decodable {
  let type: String
  let coordinates: [[Double]]
}

private struct GraphHopperInstruction: Decodable {
  let text: String
  let distance: Double
  let timeMilliseconds: Double
  let interval: [Int]
  let streetName: String?
  let streetRef: String?

  private enum CodingKeys: String, CodingKey {
    case text
    case distance
    case timeMilliseconds = "time"
    case interval
    case streetName = "street_name"
    case streetRef = "street_ref"
  }
}

private struct GraphHopperPathDetails: Decodable {
  let edgeKeys: [GraphHopperPathDetail<Int64>]
  let osmWayIDs: [GraphHopperPathDetail<Int64>]
  let countries: [GraphHopperPathDetail<String>]

  private enum CodingKeys: String, CodingKey {
    case edgeKeys = "edge_key"
    case osmWayIDs = "osm_way_id"
    case countries = "country"
  }
}

private struct GraphHopperPathDetail<Value: Decodable & Equatable & Sendable>:
  Decodable, Equatable, Sendable
{
  let fromIndex: Int
  let toIndex: Int
  let value: Value

  init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()
    fromIndex = try container.decode(Int.self)
    toIndex = try container.decode(Int.self)
    value = try container.decode(Value.self)
    guard container.isAtEnd else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "GraphHopper path detail must contain exactly three values"
      )
    }
  }
}

extension String {
  fileprivate var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
