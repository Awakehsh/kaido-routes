import Foundation

public enum ValhallaServiceAction: String, Sendable {
  case route
  case traceAttributes = "trace_attributes"
}

public struct ValhallaHTTPResponse: Equatable, Sendable {
  public let statusCode: Int
  public let body: Data

  public init(statusCode: Int, body: Data) {
    self.statusCode = statusCode
    self.body = body
  }
}

public enum ValhallaHTTPTransportFailure: Error, Equatable, Sendable {
  case network(String?)
  case timedOut
  case cancelled
  case responseTooLarge
  case invalidResponse
}

public protocol ValhallaHTTPTransport: Sendable {
  func post(
    action: ValhallaServiceAction,
    jsonBody: Data
  ) async throws -> ValhallaHTTPResponse
}

/// Snapshot-bound terminal identity for one reviewed surface approach anchor.
public struct ValhallaApproachIdentityBinding: Codable, Equatable, Sendable {
  public let anchorID: String
  public let directedSurfaceEdgeID: String
  public let terminalOSMNodeID: Int64

  public init(
    anchorID: String,
    directedSurfaceEdgeID: String,
    terminalOSMNodeID: Int64
  ) {
    self.anchorID = anchorID
    self.directedSurfaceEdgeID = directedSurfaceEdgeID
    self.terminalOSMNodeID = terminalOSMNodeID
  }

  private enum CodingKeys: String, CodingKey {
    case anchorID = "anchor_id"
    case directedSurfaceEdgeID = "directed_surface_edge_id"
    case terminalOSMNodeID = "terminal_osm_node_id"
  }
}

public struct ValhallaSurfaceProviderConfiguration: Codable, Equatable, Sendable {
  public let candidateProviderID: String
  public let adapterVersion: String
  public let narrativeLanguage: ValhallaNarrativeLanguage
  public let dataReviewStatus: ProviderDataReviewStatus
  public let manifestValidationProfile: SurfaceRoutingManifestValidationProfile
  public let approachBindings: [ValhallaApproachIdentityBinding]

  public init(
    candidateProviderID: String,
    adapterVersion: String,
    narrativeLanguage: ValhallaNarrativeLanguage = .japanese,
    dataReviewStatus: ProviderDataReviewStatus,
    manifestValidationProfile: SurfaceRoutingManifestValidationProfile,
    approachBindings: [ValhallaApproachIdentityBinding]
  ) {
    self.candidateProviderID = candidateProviderID
    self.adapterVersion = adapterVersion
    self.narrativeLanguage = narrativeLanguage
    self.dataReviewStatus = dataReviewStatus
    self.manifestValidationProfile = manifestValidationProfile
    self.approachBindings = approachBindings
  }

  private enum CodingKeys: String, CodingKey {
    case candidateProviderID = "candidate_provider_id"
    case adapterVersion = "adapter_version"
    case narrativeLanguage = "narrative_language"
    case dataReviewStatus = "data_review_status"
    case manifestValidationProfile = "manifest_validation_profile"
    case approachBindings = "approach_bindings"
  }
}

/// Valhalla narration languages used by the bounded surface adapter.
///
/// Valhalla does not currently provide Chinese narrative instructions. Kaido's
/// Japanese, Chinese, and English product guidance remains structured domain
/// data and must not be derived by translating provider-authored prose.
public enum ValhallaNarrativeLanguage: String, Codable, Sendable {
  case japanese = "ja-JP"
  case english = "en-US"
}

public enum ValhallaSurfaceRouteProviderInitializationError: Error, Equatable, Sendable {
  case invalidManifest([SurfaceRoutingManifestValidationIssue])
  case wrongEngineProvider(String)
  case invalidConfiguration
  case invalidApproachBinding(String)
}

/// Bounded Valhalla adapter for a surface access or egress leg.
///
/// Valhalla selects one ordinary route to the reviewed directed anchor. Its own
/// shape is then edge-walked, normalized, and translated onto the exact Kaido
/// graph before a candidate is returned. This adapter cannot author or mutate
/// the expressway RoutePlan.
public struct ValhallaSurfaceRouteProvider: SurfaceRouteProvider {
  public let metadata: SurfaceRouteProviderMetadata
  public let graph: SurfaceRoadGraphSnapshot
  public let manifest: SurfaceRoutingBuildManifest
  public let configuration: ValhallaSurfaceProviderConfiguration

  private let transport: any ValhallaHTTPTransport
  private let bindingsByAnchorID: [String: ValhallaApproachIdentityBinding]
  private let normalizer: ValhallaSurfaceRouteNormalizer

  public init(
    graph: SurfaceRoadGraphSnapshot,
    manifest: SurfaceRoutingBuildManifest,
    configuration: ValhallaSurfaceProviderConfiguration,
    transport: any ValhallaHTTPTransport
  ) throws {
    let report = SurfaceRoutingBuildManifestValidator.validate(
      manifest,
      graph: graph,
      profile: configuration.manifestValidationProfile
    )
    guard report.isValid else {
      throw ValhallaSurfaceRouteProviderInitializationError.invalidManifest(report.issues)
    }
    guard manifest.engineBuild.providerID.lowercased() == "valhalla" else {
      throw ValhallaSurfaceRouteProviderInitializationError.wrongEngineProvider(
        manifest.engineBuild.providerID
      )
    }
    guard !configuration.candidateProviderID.isEmpty,
      !configuration.adapterVersion.isEmpty,
      !configuration.approachBindings.isEmpty,
      Set(configuration.approachBindings.map(\.anchorID)).count
        == configuration.approachBindings.count
    else {
      throw ValhallaSurfaceRouteProviderInitializationError.invalidConfiguration
    }
    let graphEdgesByID = Dictionary(uniqueKeysWithValues: graph.edges.map { ($0.id, $0) })
    for binding in configuration.approachBindings {
      guard !binding.anchorID.isEmpty, !binding.directedSurfaceEdgeID.isEmpty,
        binding.terminalOSMNodeID > 0,
        graphEdgesByID[binding.directedSurfaceEdgeID]?.toNodeID
          == "osm.node.\(binding.terminalOSMNodeID)"
      else {
        throw ValhallaSurfaceRouteProviderInitializationError.invalidApproachBinding(
          binding.anchorID
        )
      }
    }

    self.metadata = SurfaceRouteProviderMetadata(
      id: configuration.candidateProviderID,
      adapterVersion: configuration.adapterVersion,
      providerVersion: manifest.engineBuild.providerVersion,
      dataReviewStatus: configuration.dataReviewStatus
    )
    self.graph = graph
    self.manifest = manifest
    self.configuration = configuration
    self.transport = transport
    self.bindingsByAnchorID = Dictionary(
      uniqueKeysWithValues: configuration.approachBindings.map { ($0.anchorID, $0) }
    )
    self.normalizer = ValhallaSurfaceRouteNormalizer(
      providerID: configuration.candidateProviderID,
      expectedProviderDatasetID: manifest.providerDatasetID
    )
  }

  public func routes(for request: SurfaceRouteRequest) async -> SurfaceProviderResponse {
    guard request.origin.isValid, request.destinationAnchor.coordinate.isValid,
      let binding = bindingsByAnchorID[request.destinationAnchor.id],
      binding.directedSurfaceEdgeID == request.destinationAnchor.directedSurfaceEdgeID
    else {
      return .failure(
        SurfaceProviderFailure(
          kind: .invalidRequest,
          providerErrorCode: "APPROACH_IDENTITY_NOT_BOUND"
        )
      )
    }

    do {
      let routeRequest = try encodeRouteRequest(request)
      let routeResponse = try await transport.post(action: .route, jsonBody: routeRequest)
      guard (200..<300).contains(routeResponse.statusCode) else {
        return .failure(providerFailure(for: routeResponse))
      }

      let encodedShape = try normalizer.encodedRouteShape(from: routeResponse.body)
      let traceRequest = try encodeTraceRequest(encodedShape: encodedShape)
      let traceResponse = try await transport.post(
        action: .traceAttributes,
        jsonBody: traceRequest
      )
      guard (200..<300).contains(traceResponse.statusCode) else {
        return .failure(providerFailure(for: traceResponse))
      }

      let normalized = try normalizer.normalize(
        routeResponseData: routeResponse.body,
        traceAttributesResponseData: traceResponse.body,
        candidateID: "\(request.id).valhalla.primary",
        terminalOSMNodeID: binding.terminalOSMNodeID
      )
      return .success([try normalized.translatedCandidate(graph: graph)])
    } catch let failure as ValhallaHTTPTransportFailure {
      return .failure(providerFailure(for: failure))
    } catch let error as ValhallaSurfaceRouteNormalizationError {
      return .failure(
        SurfaceProviderFailure(
          kind: .server,
          providerErrorCode: "INVALID_VALHALLA_RESPONSE",
          message: error.description
        )
      )
    } catch let error as OSMSelectedPathTranslationError {
      return .failure(
        SurfaceProviderFailure(
          kind: .server,
          providerErrorCode: "SELECTED_PATH_IDENTITY_REJECTED",
          message: error.description
        )
      )
    } catch {
      return .failure(
        SurfaceProviderFailure(
          kind: .unknown,
          providerErrorCode: "UNEXPECTED_ADAPTER_FAILURE"
        )
      )
    }
  }

  private func encodeRouteRequest(_ request: SurfaceRouteRequest) throws -> Data {
    let payload = RouteRequestPayload(
      locations: [
        .init(coordinate: request.origin),
        .init(
          coordinate: request.destinationAnchor.coordinate,
          heading: Int(request.destinationAnchor.expectedBearingDegrees.rounded()) % 360,
          headingTolerance: Int(request.destinationAnchor.bearingToleranceDegrees.rounded()),
          nodeSnapTolerance: 0
        ),
      ],
      costingOptions: .init(
        auto: .init(
          useHighways: request.preferences.avoidHighways ? 0 : 0.5,
          useTolls: request.preferences.avoidTolls ? 0 : 0.5
        )
      ),
      units: "kilometers",
      language: configuration.narrativeLanguage.rawValue
    )
    return try jsonEncoder.encode(payload)
  }

  private func encodeTraceRequest(encodedShape: String) throws -> Data {
    try jsonEncoder.encode(
      TraceRequestPayload(
        encodedPolyline: encodedShape,
        filters: .init(
          action: "include",
          attributes: [
            "osm_changeset",
            "shape",
            "edge.id",
            "edge.way_id",
            "edge.forward",
            "edge.begin_osm_node_id",
            "edge.length",
            "edge.begin_shape_index",
            "edge.end_shape_index",
            "edge.road_class",
            "edge.use",
            "edge.toll",
            "edge.drive_on_right",
            "node.admin_index",
            "admin.country_code",
            "admin.country_text",
            "admin.state_code",
            "admin.state_text",
          ]
        )
      )
    )
  }

  private var jsonEncoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }

  private func providerFailure(for response: ValhallaHTTPResponse) -> SurfaceProviderFailure {
    let payload = try? JSONDecoder().decode(ValhallaErrorPayload.self, from: response.body)
    let code = payload?.errorCode.map(String.init)
    if response.statusCode == 429 {
      return SurfaceProviderFailure(
        kind: .throttled,
        providerErrorCode: code,
        message: payload?.error
      )
    }
    if let errorCode = payload?.errorCode, [170, 171, 441, 442].contains(errorCode) {
      return SurfaceProviderFailure(
        kind: .noRoute,
        providerErrorCode: String(errorCode),
        message: payload?.error
      )
    }
    if (500..<600).contains(response.statusCode) {
      return SurfaceProviderFailure(
        kind: .server,
        providerErrorCode: code,
        message: payload?.error
      )
    }
    return SurfaceProviderFailure(
      kind: .invalidRequest,
      providerErrorCode: code,
      message: payload?.error
    )
  }

  private func providerFailure(
    for failure: ValhallaHTTPTransportFailure
  ) -> SurfaceProviderFailure {
    switch failure {
    case .cancelled:
      SurfaceProviderFailure(kind: .cancelled)
    case .timedOut:
      SurfaceProviderFailure(kind: .network, providerErrorCode: "REQUEST_TIMED_OUT")
    case .network(let message):
      SurfaceProviderFailure(kind: .network, message: message)
    case .responseTooLarge:
      SurfaceProviderFailure(kind: .server, providerErrorCode: "RESPONSE_TOO_LARGE")
    case .invalidResponse:
      SurfaceProviderFailure(kind: .server, providerErrorCode: "INVALID_HTTP_RESPONSE")
    }
  }
}

private struct RouteRequestPayload: Encodable {
  let locations: [Location]
  let costing = "auto"
  let costingOptions: CostingOptions
  let units: String
  let language: String
  let alternates = 0

  struct Location: Encodable {
    let lat: Double
    let lon: Double
    let type = "break"
    let heading: Int?
    let headingTolerance: Int?
    let nodeSnapTolerance: Double?

    init(
      coordinate: SurfaceCoordinate,
      heading: Int? = nil,
      headingTolerance: Int? = nil,
      nodeSnapTolerance: Double? = nil
    ) {
      self.lat = coordinate.latitude
      self.lon = coordinate.longitude
      self.heading = heading
      self.headingTolerance = headingTolerance
      self.nodeSnapTolerance = nodeSnapTolerance
    }

    private enum CodingKeys: String, CodingKey {
      case lat
      case lon
      case type
      case heading
      case headingTolerance = "heading_tolerance"
      case nodeSnapTolerance = "node_snap_tolerance"
    }
  }

  struct CostingOptions: Encodable {
    let auto: Auto
  }

  struct Auto: Encodable {
    let useHighways: Double
    let useTolls: Double

    private enum CodingKeys: String, CodingKey {
      case useHighways = "use_highways"
      case useTolls = "use_tolls"
    }
  }

  private enum CodingKeys: String, CodingKey {
    case locations
    case costing
    case costingOptions = "costing_options"
    case units
    case language
    case alternates
  }
}

private struct TraceRequestPayload: Encodable {
  let encodedPolyline: String
  let shapeMatch = "edge_walk"
  let costing = "auto"
  let filters: Filters

  struct Filters: Encodable {
    let action: String
    let attributes: [String]
  }

  private enum CodingKeys: String, CodingKey {
    case encodedPolyline = "encoded_polyline"
    case shapeMatch = "shape_match"
    case costing
    case filters
  }
}

private struct ValhallaErrorPayload: Decodable {
  let errorCode: Int?
  let error: String?

  private enum CodingKeys: String, CodingKey {
    case errorCode = "error_code"
    case error
  }
}
