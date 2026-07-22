import Foundation

public struct OSRMHTTPQueryItem: Equatable, Sendable {
  public let name: String
  public let value: String

  public init(name: String, value: String) {
    self.name = name
    self.value = value
  }
}

public struct OSRMHTTPRequest: Equatable, Sendable {
  public let path: String
  public let queryItems: [OSRMHTTPQueryItem]

  public init(path: String, queryItems: [OSRMHTTPQueryItem]) {
    self.path = path
    self.queryItems = queryItems
  }
}

public struct OSRMHTTPResponse: Equatable, Sendable {
  public let statusCode: Int
  public let body: Data

  public init(statusCode: Int, body: Data) {
    self.statusCode = statusCode
    self.body = body
  }
}

public enum OSRMHTTPTransportFailure: Error, Equatable, Sendable {
  case network(String?)
  case timedOut
  case cancelled
  case responseTooLarge
  case invalidRequest
  case invalidResponse
}

public protocol OSRMHTTPTransport: Sendable {
  func get(_ request: OSRMHTTPRequest) async throws -> OSRMHTTPResponse
}

public struct OSRMApproachIdentityBinding: Codable, Equatable, Sendable {
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

public struct OSRMSurfaceProviderConfiguration: Codable, Equatable, Sendable {
  public let candidateProviderID: String
  public let adapterVersion: String
  public let dataReviewStatus: ProviderDataReviewStatus
  public let manifestValidationProfile: SurfaceRoutingManifestValidationProfile
  public let approachBindings: [OSRMApproachIdentityBinding]

  public init(
    candidateProviderID: String,
    adapterVersion: String,
    dataReviewStatus: ProviderDataReviewStatus,
    manifestValidationProfile: SurfaceRoutingManifestValidationProfile,
    approachBindings: [OSRMApproachIdentityBinding]
  ) {
    self.candidateProviderID = candidateProviderID
    self.adapterVersion = adapterVersion
    self.dataReviewStatus = dataReviewStatus
    self.manifestValidationProfile = manifestValidationProfile
    self.approachBindings = approachBindings
  }

  private enum CodingKeys: String, CodingKey {
    case candidateProviderID = "candidate_provider_id"
    case adapterVersion = "adapter_version"
    case dataReviewStatus = "data_review_status"
    case manifestValidationProfile = "manifest_validation_profile"
    case approachBindings = "approach_bindings"
  }
}

public enum OSRMSurfaceRouteProviderInitializationError: Error, Equatable, Sendable {
  case invalidManifest([SurfaceRoutingManifestValidationIssue])
  case wrongEngineProvider(String)
  case invalidConfiguration
  case invalidApproachBinding(String)
}

/// Bounded OSRM baseline for a surface access or egress leg.
///
/// OSRM selects one route to a reviewed directed anchor and returns its ordered
/// OSM nodes. Kaido accepts the candidate only after `data_version` matches the
/// manifest and every node pair maps to one exact graph edge. OSRM cannot
/// author, optimize, recover, or mutate the active expressway `RoutePlan`.
public struct OSRMSurfaceRouteProvider: SurfaceRouteProvider {
  public let metadata: SurfaceRouteProviderMetadata
  public let graph: SurfaceRoadGraphSnapshot
  public let manifest: SurfaceRoutingBuildManifest
  public let configuration: OSRMSurfaceProviderConfiguration

  private let transport: any OSRMHTTPTransport
  private let bindingsByAnchorID: [String: OSRMApproachIdentityBinding]
  private let normalizer: OSRMSurfaceRouteNormalizer
  private let translator: OSMNodePathTranslator

  public init(
    graph: SurfaceRoadGraphSnapshot,
    manifest: SurfaceRoutingBuildManifest,
    configuration: OSRMSurfaceProviderConfiguration,
    transport: any OSRMHTTPTransport
  ) throws {
    let report = SurfaceRoutingBuildManifestValidator.validate(
      manifest,
      graph: graph,
      profile: configuration.manifestValidationProfile
    )
    guard report.isValid else {
      throw OSRMSurfaceRouteProviderInitializationError.invalidManifest(report.issues)
    }
    guard manifest.engineBuild.providerID.lowercased() == "osrm" else {
      throw OSRMSurfaceRouteProviderInitializationError.wrongEngineProvider(
        manifest.engineBuild.providerID
      )
    }
    guard !configuration.candidateProviderID.isEmpty,
      !configuration.adapterVersion.isEmpty,
      !configuration.approachBindings.isEmpty,
      Set(configuration.approachBindings.map(\.anchorID)).count
        == configuration.approachBindings.count
    else {
      throw OSRMSurfaceRouteProviderInitializationError.invalidConfiguration
    }
    let graphEdgesByID = Dictionary(uniqueKeysWithValues: graph.edges.map { ($0.id, $0) })
    for binding in configuration.approachBindings {
      guard !binding.anchorID.isEmpty, !binding.directedSurfaceEdgeID.isEmpty,
        binding.terminalOSMNodeID > 0,
        graphEdgesByID[binding.directedSurfaceEdgeID]?.toNodeID
          == "osm.node.\(binding.terminalOSMNodeID)"
      else {
        throw OSRMSurfaceRouteProviderInitializationError.invalidApproachBinding(
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
    self.normalizer = OSRMSurfaceRouteNormalizer(
      providerID: configuration.candidateProviderID,
      expectedProviderDatasetID: manifest.providerDatasetID
    )
    self.translator = OSMNodePathTranslator(graph: graph)
  }

  public func routes(for request: SurfaceRouteRequest) async -> SurfaceProviderResponse {
    guard request.origin.isValid, request.destinationAnchor.coordinate.isValid,
      (0..<360).contains(request.destinationAnchor.expectedBearingDegrees),
      (0...180).contains(request.destinationAnchor.bearingToleranceDegrees),
      request.destinationAnchor.maxTerminalDistanceMeters > 0,
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
      let response = try await transport.get(makeHTTPRequest(request))
      guard (200..<300).contains(response.statusCode) else {
        return .failure(providerFailure(for: response))
      }
      let normalized = try normalizer.normalize(
        routeResponseData: response.body,
        candidateID: "\(request.id).osrm.primary"
      )
      guard
        normalized.translationRequest.orderedOSMNodeIDs.last
          == binding.terminalOSMNodeID
      else {
        return .failure(
          SurfaceProviderFailure(
            kind: .server,
            providerErrorCode: "TERMINAL_OSM_NODE_REJECTED"
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
    } catch let failure as OSRMHTTPTransportFailure {
      return .failure(providerFailure(for: failure))
    } catch let error as OSRMSurfaceRouteNormalizationError {
      return .failure(providerFailure(for: error))
    } catch let error as OSMNodePathTranslationError {
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

  private func makeHTTPRequest(_ request: SurfaceRouteRequest) -> OSRMHTTPRequest {
    let origin = "\(request.origin.longitude),\(request.origin.latitude)"
    let destination =
      "\(request.destinationAnchor.coordinate.longitude),\(request.destinationAnchor.coordinate.latitude)"
    let destinationBearing = Int(request.destinationAnchor.expectedBearingDegrees.rounded())
    let bearingTolerance = Int(request.destinationAnchor.bearingToleranceDegrees.rounded())
    var queryItems = [
      OSRMHTTPQueryItem(name: "alternatives", value: "false"),
      OSRMHTTPQueryItem(name: "steps", value: "true"),
      OSRMHTTPQueryItem(name: "annotations", value: "nodes"),
      OSRMHTTPQueryItem(name: "geometries", value: "geojson"),
      OSRMHTTPQueryItem(name: "overview", value: "full"),
      OSRMHTTPQueryItem(name: "continue_straight", value: "true"),
      OSRMHTTPQueryItem(
        name: "bearings",
        value: ";\(destinationBearing),\(bearingTolerance)"
      ),
    ]
    if request.preferences.avoidHighways {
      queryItems.append(OSRMHTTPQueryItem(name: "exclude", value: "motorway"))
    } else if request.preferences.avoidTolls {
      queryItems.append(OSRMHTTPQueryItem(name: "exclude", value: "toll"))
    }
    return OSRMHTTPRequest(
      path: "/route/v1/driving/\(origin);\(destination)",
      queryItems: queryItems
    )
  }

  private func providerFailure(for response: OSRMHTTPResponse) -> SurfaceProviderFailure {
    let payload = try? JSONDecoder().decode(OSRMErrorPayload.self, from: response.body)
    let code = payload?.code
    if response.statusCode == 429 {
      return SurfaceProviderFailure(
        kind: .throttled,
        providerErrorCode: code,
        message: payload?.message
      )
    }
    if ["NoRoute", "NoSegment"].contains(code) {
      return SurfaceProviderFailure(
        kind: .noRoute,
        providerErrorCode: code,
        message: payload?.message
      )
    }
    if (500..<600).contains(response.statusCode) {
      return SurfaceProviderFailure(
        kind: .server,
        providerErrorCode: code,
        message: payload?.message
      )
    }
    return SurfaceProviderFailure(
      kind: .invalidRequest,
      providerErrorCode: code,
      message: payload?.message
    )
  }

  private func providerFailure(
    for error: OSRMSurfaceRouteNormalizationError
  ) -> SurfaceProviderFailure {
    if case .unsuccessfulCode(let code) = error, ["NoRoute", "NoSegment"].contains(code) {
      return SurfaceProviderFailure(
        kind: .noRoute,
        providerErrorCode: code,
        message: error.description
      )
    }
    return SurfaceProviderFailure(
      kind: .server,
      providerErrorCode: "INVALID_OSRM_RESPONSE",
      message: error.description
    )
  }

  private func providerFailure(for failure: OSRMHTTPTransportFailure) -> SurfaceProviderFailure {
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

private struct OSRMErrorPayload: Decodable {
  let code: String?
  let message: String?
}
