import Foundation

public enum ValhallaSurfaceRouteNormalizationError: Error, Equatable, Sendable {
  case invalidIdentity
  case invalidRouteResponse
  case invalidTraceResponse
  case unsuccessfulRouteStatus(Int)
  case unsupportedUnits(String)
  case invalidLegCount(Int)
  case invalidRouteMetrics
  case invalidRouteShape
  case traceShapeMismatch
  case providerDatasetMismatch(expected: String, received: String)
  case invalidTraceEdge(index: Int)
  case discontinuousTraceShape(index: Int)
}

extension ValhallaSurfaceRouteNormalizationError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .invalidIdentity:
      "candidate, provider, dataset, and terminal OSM node identity must be present"
    case .invalidRouteResponse:
      "Valhalla route response cannot be decoded"
    case .invalidTraceResponse:
      "Valhalla trace_attributes response cannot be decoded"
    case .unsuccessfulRouteStatus(let status):
      "Valhalla route status is \(status), not zero"
    case .unsupportedUnits(let units):
      "Valhalla response units \(units) are unsupported; kilometers are required"
    case .invalidLegCount(let count):
      "bounded surface routing requires exactly one Valhalla leg, received \(count)"
    case .invalidRouteMetrics:
      "Valhalla route or maneuver metrics are invalid"
    case .invalidRouteShape:
      "Valhalla encoded route shape is invalid"
    case .traceShapeMismatch:
      "trace_attributes does not describe the exact route shape"
    case .providerDatasetMismatch(let expected, let received):
      "Valhalla dataset \(received) does not match expected dataset \(expected)"
    case .invalidTraceEdge(let index):
      "Valhalla trace edge \(index) lacks valid OSM or shape identity"
    case .discontinuousTraceShape(let index):
      "Valhalla trace edge \(index) is not contiguous on the selected route shape"
    }
  }
}

/// Decoded provider output before selected-path translation onto the Kaido graph.
public struct ValhallaNormalizedSurfaceRoute: Equatable, Sendable {
  public let candidateWithoutSelectedPathEvidence: SurfaceRouteCandidate
  public let translationRequest: OSMSelectedPathTranslationRequest

  public init(
    candidateWithoutSelectedPathEvidence: SurfaceRouteCandidate,
    translationRequest: OSMSelectedPathTranslationRequest
  ) {
    self.candidateWithoutSelectedPathEvidence = candidateWithoutSelectedPathEvidence
    self.translationRequest = translationRequest
  }

  public func translatedCandidate(
    graph: SurfaceRoadGraphSnapshot,
    configuration: OSMSelectedPathTranslatorConfiguration = .init()
  ) throws -> SurfaceRouteCandidate {
    let evidence = try OSMSelectedPathTranslator(
      graph: graph,
      configuration: configuration
    ).translate(translationRequest)
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

/// HTTP-agnostic boundary for the bounded Valhalla surface provider.
///
/// The caller obtains `/route` and `/trace_attributes` responses for one exact
/// encoded shape. This normalizer rejects response drift, then emits both the
/// generic candidate and the OSM identity required by the Kaido translator.
public struct ValhallaSurfaceRouteNormalizer: Sendable {
  public let providerID: String
  public let expectedProviderDatasetID: String

  public init(providerID: String, expectedProviderDatasetID: String) {
    self.providerID = providerID
    self.expectedProviderDatasetID = expectedProviderDatasetID
  }

  public func encodedRouteShape(from routeResponseData: Data) throws -> String {
    let routeResponse: RouteResponse
    do {
      routeResponse = try JSONDecoder().decode(RouteResponse.self, from: routeResponseData)
    } catch {
      throw ValhallaSurfaceRouteNormalizationError.invalidRouteResponse
    }
    guard routeResponse.trip.status == 0 else {
      throw ValhallaSurfaceRouteNormalizationError.unsuccessfulRouteStatus(
        routeResponse.trip.status
      )
    }
    guard routeResponse.trip.units == "kilometers" else {
      throw ValhallaSurfaceRouteNormalizationError.unsupportedUnits(routeResponse.trip.units)
    }
    guard routeResponse.trip.legs.count == 1 else {
      throw ValhallaSurfaceRouteNormalizationError.invalidLegCount(
        routeResponse.trip.legs.count
      )
    }
    let shape = routeResponse.trip.legs[0].shape
    guard !shape.isEmpty else {
      throw ValhallaSurfaceRouteNormalizationError.invalidRouteShape
    }
    return shape
  }

  public func normalize(
    routeResponseData: Data,
    traceAttributesResponseData: Data,
    candidateID: String,
    terminalOSMNodeID: Int64
  ) throws -> ValhallaNormalizedSurfaceRoute {
    guard !providerID.isEmpty, !expectedProviderDatasetID.isEmpty,
      !candidateID.isEmpty, terminalOSMNodeID > 0
    else {
      throw ValhallaSurfaceRouteNormalizationError.invalidIdentity
    }

    let decoder = JSONDecoder()
    let routeResponse: RouteResponse
    do {
      routeResponse = try decoder.decode(RouteResponse.self, from: routeResponseData)
    } catch {
      throw ValhallaSurfaceRouteNormalizationError.invalidRouteResponse
    }
    let traceResponse: TraceAttributesResponse
    do {
      traceResponse = try decoder.decode(
        TraceAttributesResponse.self,
        from: traceAttributesResponseData
      )
    } catch {
      throw ValhallaSurfaceRouteNormalizationError.invalidTraceResponse
    }

    guard routeResponse.trip.status == 0 else {
      throw ValhallaSurfaceRouteNormalizationError.unsuccessfulRouteStatus(
        routeResponse.trip.status
      )
    }
    guard routeResponse.trip.units == "kilometers" else {
      throw ValhallaSurfaceRouteNormalizationError.unsupportedUnits(routeResponse.trip.units)
    }
    guard traceResponse.units == "kilometers" else {
      throw ValhallaSurfaceRouteNormalizationError.unsupportedUnits(traceResponse.units)
    }
    guard routeResponse.trip.legs.count == 1 else {
      throw ValhallaSurfaceRouteNormalizationError.invalidLegCount(
        routeResponse.trip.legs.count
      )
    }
    let leg = routeResponse.trip.legs[0]
    guard leg.shape == traceResponse.shape else {
      throw ValhallaSurfaceRouteNormalizationError.traceShapeMismatch
    }
    guard routeResponse.trip.summary.length.isFinite,
      routeResponse.trip.summary.length >= 0,
      routeResponse.trip.summary.time.isFinite,
      routeResponse.trip.summary.time >= 0,
      leg.maneuvers.allSatisfy({
        !$0.instruction.isEmpty && $0.length.isFinite && $0.length >= 0
      })
    else {
      throw ValhallaSurfaceRouteNormalizationError.invalidRouteMetrics
    }
    let coordinates: [SurfaceCoordinate]
    do {
      coordinates = try ValhallaPolyline6.decode(leg.shape)
    } catch {
      throw ValhallaSurfaceRouteNormalizationError.invalidRouteShape
    }
    guard coordinates.count >= 2, coordinates.allSatisfy(\.isValid) else {
      throw ValhallaSurfaceRouteNormalizationError.invalidRouteShape
    }

    let receivedDatasetID = String(traceResponse.osmChangeset)
    guard receivedDatasetID == expectedProviderDatasetID else {
      throw ValhallaSurfaceRouteNormalizationError.providerDatasetMismatch(
        expected: expectedProviderDatasetID,
        received: receivedDatasetID
      )
    }
    let references = try makeReferences(
      from: traceResponse.edges,
      coordinateCount: coordinates.count
    )

    let steps = leg.maneuvers.enumerated().map { index, maneuver in
      SurfaceRouteStep(
        id: "maneuver.\(index)",
        instruction: maneuver.instruction,
        distanceMeters: maneuver.length * 1_000
      )
    }
    let candidate = SurfaceRouteCandidate(
      id: candidateID,
      providerID: providerID,
      coordinates: coordinates,
      steps: steps,
      distanceMeters: routeResponse.trip.summary.length * 1_000,
      expectedTravelTimeSeconds: routeResponse.trip.summary.time,
      hasHighways: routeResponse.trip.summary.hasHighway,
      hasTolls: routeResponse.trip.summary.hasToll
    )
    let request = OSMSelectedPathTranslationRequest(
      providerDatasetID: receivedDatasetID,
      terminalOSMNodeID: terminalOSMNodeID,
      routeCoordinates: coordinates,
      edgeReferences: references
    )
    return ValhallaNormalizedSurfaceRoute(
      candidateWithoutSelectedPathEvidence: candidate,
      translationRequest: request
    )
  }

  private func makeReferences(
    from edges: [TraceEdge],
    coordinateCount: Int
  ) throws -> [OSMPathEdgeReference] {
    guard !edges.isEmpty else {
      throw ValhallaSurfaceRouteNormalizationError.invalidTraceResponse
    }
    var references: [OSMPathEdgeReference] = []
    for (index, edge) in edges.enumerated() {
      guard let wayID = Int64(exactly: edge.wayID),
        let beginNodeID = Int64(exactly: edge.beginOSMNodeID),
        wayID > 0, beginNodeID > 0,
        edge.beginShapeIndex >= 0,
        edge.endShapeIndex >= edge.beginShapeIndex,
        edge.endShapeIndex < coordinateCount,
        (0...1).contains(edge.sourcePercentAlong ?? 0),
        (0...1).contains(edge.targetPercentAlong ?? 1),
        (edge.sourcePercentAlong ?? 0) < (edge.targetPercentAlong ?? 1)
      else {
        throw ValhallaSurfaceRouteNormalizationError.invalidTraceEdge(index: index)
      }
      if index == 0 {
        guard edge.beginShapeIndex == 0 else {
          throw ValhallaSurfaceRouteNormalizationError.discontinuousTraceShape(index: index)
        }
      } else {
        guard edge.beginShapeIndex == edges[index - 1].endShapeIndex else {
          throw ValhallaSurfaceRouteNormalizationError.discontinuousTraceShape(index: index)
        }
      }
      references.append(
        OSMPathEdgeReference(
          providerEdgeID: String(edge.id),
          osmWayID: wayID,
          beginOSMNodeID: beginNodeID,
          isForward: edge.forward,
          sourcePercentAlong: edge.sourcePercentAlong ?? 0,
          targetPercentAlong: edge.targetPercentAlong ?? 1
        )
      )
    }
    guard edges[edges.count - 1].endShapeIndex == coordinateCount - 1 else {
      throw ValhallaSurfaceRouteNormalizationError.discontinuousTraceShape(
        index: edges.count - 1
      )
    }
    return references
  }
}

private struct RouteResponse: Decodable {
  let trip: Trip
}

private struct Trip: Decodable {
  let status: Int
  let units: String
  let legs: [RouteLeg]
  let summary: RouteSummary
}

private struct RouteLeg: Decodable {
  let shape: String
  let maneuvers: [RouteManeuver]
}

private struct RouteManeuver: Decodable {
  let instruction: String
  let length: Double
}

private struct RouteSummary: Decodable {
  let length: Double
  let time: Double
  let hasHighway: Bool
  let hasToll: Bool

  private enum CodingKeys: String, CodingKey {
    case length
    case time
    case hasHighway = "has_highway"
    case hasToll = "has_toll"
  }
}

private struct TraceAttributesResponse: Decodable {
  let osmChangeset: UInt64
  let shape: String
  let units: String
  let edges: [TraceEdge]

  private enum CodingKeys: String, CodingKey {
    case osmChangeset = "osm_changeset"
    case shape
    case units
    case edges
  }
}

private struct TraceEdge: Decodable {
  let id: UInt64
  let wayID: UInt64
  let beginOSMNodeID: UInt64
  let forward: Bool
  let sourcePercentAlong: Double?
  let targetPercentAlong: Double?
  let beginShapeIndex: Int
  let endShapeIndex: Int

  private enum CodingKeys: String, CodingKey {
    case id
    case wayID = "way_id"
    case beginOSMNodeID = "node_id"
    case forward
    case sourcePercentAlong = "source_percent_along"
    case targetPercentAlong = "target_percent_along"
    case beginShapeIndex = "begin_shape_index"
    case endShapeIndex = "end_shape_index"
  }
}

private enum ValhallaPolyline6 {
  enum DecodingError: Error {
    case invalidByte
    case truncatedValue
    case overflow
  }

  static func decode(_ encoded: String) throws -> [SurfaceCoordinate] {
    let bytes = Array(encoded.utf8)
    guard !bytes.isEmpty else { throw DecodingError.truncatedValue }
    var index = 0
    var latitude: Int64 = 0
    var longitude: Int64 = 0
    var coordinates: [SurfaceCoordinate] = []

    while index < bytes.count {
      let latitudeDelta = try decodeValue(bytes, index: &index)
      let longitudeDelta = try decodeValue(bytes, index: &index)
      let (nextLatitude, latitudeOverflow) = latitude.addingReportingOverflow(latitudeDelta)
      let (nextLongitude, longitudeOverflow) = longitude.addingReportingOverflow(longitudeDelta)
      guard !latitudeOverflow, !longitudeOverflow else { throw DecodingError.overflow }
      latitude = nextLatitude
      longitude = nextLongitude
      coordinates.append(
        SurfaceCoordinate(
          latitude: Double(latitude) / 1_000_000,
          longitude: Double(longitude) / 1_000_000
        )
      )
    }
    return coordinates
  }

  private static func decodeValue(_ bytes: [UInt8], index: inout Int) throws -> Int64 {
    var result: UInt64 = 0
    var shift: UInt64 = 0
    while true {
      guard index < bytes.count else { throw DecodingError.truncatedValue }
      let encodedByte = bytes[index]
      index += 1
      guard (63...126).contains(encodedByte) else { throw DecodingError.invalidByte }
      let value = UInt64(encodedByte - 63)
      guard shift < 64, (value & 0x1f) <= (UInt64.max >> shift) else {
        throw DecodingError.overflow
      }
      result |= (value & 0x1f) << shift
      if value < 0x20 { break }
      shift += 5
    }
    let magnitude = Int64(result >> 1)
    return result & 1 == 1 ? ~magnitude : magnitude
  }
}
