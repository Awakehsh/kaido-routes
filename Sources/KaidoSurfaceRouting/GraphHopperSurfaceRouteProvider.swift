import Foundation

public struct GraphHopperHTTPQueryItem: Equatable, Sendable {
  public let name: String
  public let value: String

  public init(name: String, value: String) {
    self.name = name
    self.value = value
  }
}

public struct GraphHopperHTTPRequest: Equatable, Sendable {
  public let path: String
  public let queryItems: [GraphHopperHTTPQueryItem]

  public init(path: String, queryItems: [GraphHopperHTTPQueryItem] = []) {
    self.path = path
    self.queryItems = queryItems
  }
}

public struct GraphHopperHTTPResponse: Equatable, Sendable {
  public let statusCode: Int
  public let body: Data

  public init(statusCode: Int, body: Data) {
    self.statusCode = statusCode
    self.body = body
  }
}

public enum GraphHopperHTTPTransportFailure: Error, Equatable, Sendable {
  case network(String?)
  case timedOut
  case cancelled
  case responseTooLarge
  case invalidRequest
  case invalidResponse
}

public protocol GraphHopperHTTPTransport: Sendable {
  func get(_ request: GraphHopperHTTPRequest) async throws -> GraphHopperHTTPResponse
}

public struct GraphHopperApproachIdentityBinding: Codable, Equatable, Sendable {
  public let anchorID: String
  public let directedSurfaceEdgeID: String
  public let terminalOSMWayID: Int64

  public init(
    anchorID: String,
    directedSurfaceEdgeID: String,
    terminalOSMWayID: Int64
  ) {
    self.anchorID = anchorID
    self.directedSurfaceEdgeID = directedSurfaceEdgeID
    self.terminalOSMWayID = terminalOSMWayID
  }

  private enum CodingKeys: String, CodingKey {
    case anchorID = "anchor_id"
    case directedSurfaceEdgeID = "directed_surface_edge_id"
    case terminalOSMWayID = "terminal_osm_way_id"
  }
}

public struct GraphHopperSurfaceProviderConfiguration: Codable, Equatable, Sendable {
  public let candidateProviderID: String
  public let adapterVersion: String
  public let profileName: String
  public let dataReviewStatus: ProviderDataReviewStatus
  public let manifestValidationProfile: SurfaceRoutingManifestValidationProfile
  public let approachBindings: [GraphHopperApproachIdentityBinding]

  public init(
    candidateProviderID: String,
    adapterVersion: String,
    profileName: String = "car_surface",
    dataReviewStatus: ProviderDataReviewStatus,
    manifestValidationProfile: SurfaceRoutingManifestValidationProfile,
    approachBindings: [GraphHopperApproachIdentityBinding]
  ) {
    self.candidateProviderID = candidateProviderID
    self.adapterVersion = adapterVersion
    self.profileName = profileName
    self.dataReviewStatus = dataReviewStatus
    self.manifestValidationProfile = manifestValidationProfile
    self.approachBindings = approachBindings
  }

  private enum CodingKeys: String, CodingKey {
    case candidateProviderID = "candidate_provider_id"
    case adapterVersion = "adapter_version"
    case profileName = "profile_name"
    case dataReviewStatus = "data_review_status"
    case manifestValidationProfile = "manifest_validation_profile"
    case approachBindings = "approach_bindings"
  }
}

public enum GraphHopperSurfaceRouteProviderInitializationError: Error, Equatable, Sendable {
  case invalidManifest([SurfaceRoutingManifestValidationIssue])
  case wrongEngineProvider(String)
  case invalidConfiguration
  case invalidRoadDataTimestamp
  case wrongSelectedPathIdentity
  case missingBuildArtifact(SurfaceRoutingBuildArtifactRole)
  case invalidApproachBinding(String)
}

/// Bounded GraphHopper baseline for a reviewed surface access or egress leg.
///
/// Every request first verifies the running build through `/info`, then asks
/// for one unencoded and unsimplified `/route` path. Aligned directional edge
/// keys and OSM way IDs must translate onto one exact Kaido edge path before a
/// candidate can escape this adapter. GraphHopper does not own the expressway
/// `RoutePlan`, recovery target, localized guidance, or driving-side truth.
public struct GraphHopperSurfaceRouteProvider: SurfaceRouteProvider {
  public let metadata: SurfaceRouteProviderMetadata
  public let graph: SurfaceRoadGraphSnapshot
  public let manifest: SurfaceRoutingBuildManifest
  public let configuration: GraphHopperSurfaceProviderConfiguration

  private let transport: any GraphHopperHTTPTransport
  private let bindingsByAnchorID: [String: GraphHopperApproachIdentityBinding]
  private let normalizer: GraphHopperSurfaceRouteNormalizer
  private let translator: OSMWayPointPathTranslator

  public init(
    graph: SurfaceRoadGraphSnapshot,
    manifest: SurfaceRoutingBuildManifest,
    configuration: GraphHopperSurfaceProviderConfiguration,
    transport: any GraphHopperHTTPTransport
  ) throws {
    let report = SurfaceRoutingBuildManifestValidator.validate(
      manifest,
      graph: graph,
      profile: configuration.manifestValidationProfile
    )
    guard report.isValid else {
      throw GraphHopperSurfaceRouteProviderInitializationError.invalidManifest(report.issues)
    }
    guard manifest.engineBuild.providerID.lowercased() == "graphhopper" else {
      throw GraphHopperSurfaceRouteProviderInitializationError.wrongEngineProvider(
        manifest.engineBuild.providerID
      )
    }
    guard manifest.capabilities.selectedPathIdentity == .osmWayPointPairs else {
      throw GraphHopperSurfaceRouteProviderInitializationError.wrongSelectedPathIdentity
    }
    for role in [
      SurfaceRoutingBuildArtifactRole.providerConfiguration,
      .engineBinary,
    ] where !manifest.artifacts.contains(where: { $0.role == role }) {
      throw GraphHopperSurfaceRouteProviderInitializationError.missingBuildArtifact(role)
    }
    guard !configuration.candidateProviderID.isEmpty,
      !configuration.adapterVersion.isEmpty,
      !configuration.profileName.isEmpty,
      !configuration.approachBindings.isEmpty,
      Set(configuration.approachBindings.map(\.anchorID)).count
        == configuration.approachBindings.count
    else {
      throw GraphHopperSurfaceRouteProviderInitializationError.invalidConfiguration
    }

    let roadSources = manifest.sources.filter { $0.roles.contains(.roadNetwork) }
    let roadTimestamps = Set(roadSources.map(\.snapshotAt))
    guard roadTimestamps.count == 1,
      let roadDataTimestamp = roadTimestamps.first,
      roadDataTimestamp != "1970-01-01T00:00:00Z",
      roadDataTimestamp == graph.provenance?.sourceSnapshotAt
    else {
      throw GraphHopperSurfaceRouteProviderInitializationError.invalidRoadDataTimestamp
    }

    let graphEdgesByID = Dictionary(uniqueKeysWithValues: graph.edges.map { ($0.id, $0) })
    for binding in configuration.approachBindings {
      guard !binding.anchorID.isEmpty, !binding.directedSurfaceEdgeID.isEmpty,
        binding.terminalOSMWayID > 0,
        graphEdgesByID[binding.directedSurfaceEdgeID]?.sourceOSMWayID
          == binding.terminalOSMWayID
      else {
        throw GraphHopperSurfaceRouteProviderInitializationError.invalidApproachBinding(
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
    self.normalizer = GraphHopperSurfaceRouteNormalizer(
      providerID: configuration.candidateProviderID,
      providerDatasetID: manifest.providerDatasetID,
      expectedProviderVersion: manifest.engineBuild.providerVersion,
      expectedRoadDataTimestamp: roadDataTimestamp,
      expectedProfileName: configuration.profileName
    )
    self.translator = OSMWayPointPathTranslator(graph: graph)
  }

  public func routes(for request: SurfaceRouteRequest) async -> SurfaceProviderResponse {
    guard request.origin.isValid, request.destinationAnchor.coordinate.isValid,
      (0..<360).contains(request.destinationAnchor.expectedBearingDegrees),
      (0...180).contains(request.destinationAnchor.bearingToleranceDegrees),
      request.destinationAnchor.maxTerminalDistanceMeters > 0,
      request.preferences.avoidHighways, request.preferences.avoidTolls,
      let binding = bindingsByAnchorID[request.destinationAnchor.id],
      binding.directedSurfaceEdgeID == request.destinationAnchor.directedSurfaceEdgeID
    else {
      return .failure(
        SurfaceProviderFailure(
          kind: .invalidRequest,
          providerErrorCode: "APPROACH_OR_PROFILE_NOT_BOUND"
        )
      )
    }

    do {
      let infoResponse = try await transport.get(GraphHopperHTTPRequest(path: "/info"))
      guard (200..<300).contains(infoResponse.statusCode) else {
        return .failure(providerFailure(for: infoResponse))
      }
      let routeResponse = try await transport.get(makeRouteRequest(request))
      guard (200..<300).contains(routeResponse.statusCode) else {
        return .failure(providerFailure(for: routeResponse))
      }
      let normalized = try normalizer.normalize(
        infoResponseData: infoResponse.body,
        routeResponseData: routeResponse.body,
        candidateID: "\(request.id).graphhopper.primary"
      )
      guard
        normalized.translationRequest.segmentIdentities.last?.osmWayID
          == binding.terminalOSMWayID
      else {
        return .failure(
          SurfaceProviderFailure(
            kind: .server,
            providerErrorCode: "TERMINAL_OSM_WAY_REJECTED"
          )
        )
      }
      let candidate = try normalized.translatedCandidate(translator: translator)
      guard
        candidate.selectedPathEvidence?.directedEdgeIDs.last
          == binding.directedSurfaceEdgeID
      else {
        return .failure(
          SurfaceProviderFailure(
            kind: .server,
            providerErrorCode: "TERMINAL_PATH_IDENTITY_REJECTED"
          )
        )
      }
      return .success([candidate])
    } catch let failure as GraphHopperHTTPTransportFailure {
      return .failure(providerFailure(for: failure))
    } catch let error as GraphHopperSurfaceRouteNormalizationError {
      return .failure(
        SurfaceProviderFailure(
          kind: .server,
          providerErrorCode: "INVALID_GRAPHHOPPER_RESPONSE",
          message: error.description
        )
      )
    } catch let error as OSMWayPointPathTranslationError {
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

  private func makeRouteRequest(_ request: SurfaceRouteRequest) -> GraphHopperHTTPRequest {
    let destinationHeading = request.destinationAnchor.expectedBearingDegrees
    return GraphHopperHTTPRequest(
      path: "/route",
      queryItems: [
        GraphHopperHTTPQueryItem(
          name: "point",
          value: "\(request.origin.latitude),\(request.origin.longitude)"
        ),
        GraphHopperHTTPQueryItem(
          name: "point",
          value:
            "\(request.destinationAnchor.coordinate.latitude),\(request.destinationAnchor.coordinate.longitude)"
        ),
        GraphHopperHTTPQueryItem(name: "profile", value: configuration.profileName),
        GraphHopperHTTPQueryItem(name: "locale", value: "ja"),
        GraphHopperHTTPQueryItem(name: "instructions", value: "true"),
        GraphHopperHTTPQueryItem(name: "calc_points", value: "true"),
        GraphHopperHTTPQueryItem(name: "points_encoded", value: "false"),
        GraphHopperHTTPQueryItem(name: "way_point_max_distance", value: "0"),
        GraphHopperHTTPQueryItem(name: "heading", value: "NaN"),
        GraphHopperHTTPQueryItem(name: "heading", value: String(destinationHeading)),
        GraphHopperHTTPQueryItem(name: "heading_penalty", value: "300"),
        GraphHopperHTTPQueryItem(name: "pass_through", value: "true"),
        GraphHopperHTTPQueryItem(name: "details", value: "edge_key"),
        GraphHopperHTTPQueryItem(name: "details", value: "osm_way_id"),
        GraphHopperHTTPQueryItem(name: "details", value: "country"),
        GraphHopperHTTPQueryItem(name: "details", value: "toll"),
        GraphHopperHTTPQueryItem(name: "details", value: "road_class"),
      ]
    )
  }

  private func providerFailure(
    for response: GraphHopperHTTPResponse
  ) -> SurfaceProviderFailure {
    let payload = try? JSONDecoder().decode(GraphHopperErrorPayload.self, from: response.body)
    let message = payload?.message
    let normalizedMessage = message?.lowercased() ?? ""
    if response.statusCode == 429 {
      return SurfaceProviderFailure(
        kind: .throttled,
        providerErrorCode: "GRAPH_HOPPER_HTTP_429",
        message: message
      )
    }
    if response.statusCode == 400,
      ["not found", "cannot find point", "connection between locations"]
        .contains(where: normalizedMessage.contains)
    {
      return SurfaceProviderFailure(
        kind: .noRoute,
        providerErrorCode: "GRAPH_HOPPER_NO_ROUTE",
        message: message
      )
    }
    if (500..<600).contains(response.statusCode) {
      return SurfaceProviderFailure(
        kind: .server,
        providerErrorCode: "GRAPH_HOPPER_HTTP_\(response.statusCode)",
        message: message
      )
    }
    return SurfaceProviderFailure(
      kind: .invalidRequest,
      providerErrorCode: "GRAPH_HOPPER_HTTP_\(response.statusCode)",
      message: message
    )
  }

  private func providerFailure(
    for failure: GraphHopperHTTPTransportFailure
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
    case .invalidRequest:
      SurfaceProviderFailure(kind: .invalidRequest, providerErrorCode: "INVALID_HTTP_REQUEST")
    case .invalidResponse:
      SurfaceProviderFailure(kind: .server, providerErrorCode: "INVALID_HTTP_RESPONSE")
    }
  }
}

private struct GraphHopperErrorPayload: Decodable {
  let message: String?
}
