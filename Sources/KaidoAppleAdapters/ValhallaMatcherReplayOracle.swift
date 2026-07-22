import Foundation
import KaidoNavigation
import KaidoSurfaceRouting

public enum ValhallaMatcherReplayOracleError: Error, Equatable, Sendable {
  case invalidManifest([SurfaceRoutingManifestValidationIssue])
  case wrongEngineProvider(String)
  case missingOSMNodeIdentity
  case invalidConfiguration
  case invalidFixture([String])
  case snapshotMismatch(expected: String, received: String)
  case fixtureEdgeMissing(String)
  case nonIncreasingObservationTime
  case unsupportedSearchRadius(Double)
  case requestEncodingFailed
  case unsuccessfulHTTPStatus(Int)
}

public struct ValhallaMatcherReplayOracleConfiguration: Equatable, Sendable {
  public let algorithmID: String
  public let manifestValidationProfile: SurfaceRoutingManifestValidationProfile
  public let minimumSearchRadiusMeters: Double
  public let maximumSearchRadiusMeters: Double

  public init(
    algorithmID: String = "valhalla-meili-map-snap-v1",
    manifestValidationProfile: SurfaceRoutingManifestValidationProfile = .structural,
    minimumSearchRadiusMeters: Double = 10,
    maximumSearchRadiusMeters: Double = 100
  ) {
    self.algorithmID = algorithmID
    self.manifestValidationProfile = manifestValidationProfile
    self.minimumSearchRadiusMeters = minimumSearchRadiusMeters
    self.maximumSearchRadiusMeters = maximumSearchRadiusMeters
  }
}

/// Batch Valhalla Meili oracle for the deterministic matcher replay contract.
///
/// Meili exposes match type and point distance, not calibrated confidence or
/// Kaido route occurrences. This adapter therefore reports matched points with
/// LOW confidence and no occurrence. It is an external comparison oracle, not a
/// live safety-commit source.
public struct ValhallaMatcherReplayOracle: Sendable {
  public let graph: SurfaceRoadGraphSnapshot
  public let manifest: SurfaceRoutingBuildManifest
  public let configuration: ValhallaMatcherReplayOracleConfiguration

  private let transport: any ValhallaHTTPTransport
  private let normalizer: ValhallaMapMatchNormalizer

  public init(
    graph: SurfaceRoadGraphSnapshot,
    manifest: SurfaceRoutingBuildManifest,
    configuration: ValhallaMatcherReplayOracleConfiguration = .init(),
    transport: any ValhallaHTTPTransport
  ) throws {
    let report = SurfaceRoutingBuildManifestValidator.validate(
      manifest,
      graph: graph,
      profile: configuration.manifestValidationProfile
    )
    guard report.isValid else {
      throw ValhallaMatcherReplayOracleError.invalidManifest(report.issues)
    }
    guard manifest.engineBuild.providerID.lowercased() == "valhalla" else {
      throw ValhallaMatcherReplayOracleError.wrongEngineProvider(
        manifest.engineBuild.providerID
      )
    }
    guard manifest.capabilities.keepsAllOSMNodeIDs else {
      throw ValhallaMatcherReplayOracleError.missingOSMNodeIdentity
    }
    guard !configuration.algorithmID.isEmpty,
      configuration.minimumSearchRadiusMeters.isFinite,
      configuration.maximumSearchRadiusMeters.isFinite,
      configuration.minimumSearchRadiusMeters > 0,
      configuration.maximumSearchRadiusMeters >= configuration.minimumSearchRadiusMeters,
      configuration.maximumSearchRadiusMeters <= 100
    else {
      throw ValhallaMatcherReplayOracleError.invalidConfiguration
    }
    self.graph = graph
    self.manifest = manifest
    self.configuration = configuration
    self.transport = transport
    self.normalizer = ValhallaMapMatchNormalizer(
      graph: graph,
      expectedProviderDatasetID: manifest.providerDatasetID
    )
  }

  public func requestBody(for fixture: MatcherReplayFixture) throws -> Data {
    try validate(fixture: fixture)
    let observations = fixture.observations
    guard
      zip(observations, observations.dropFirst()).allSatisfy({ pair in
        pair.0.observedAtMilliseconds < pair.1.observedAtMilliseconds
      })
    else {
      throw ValhallaMatcherReplayOracleError.nonIncreasingObservationTime
    }
    let maximumAccuracy = observations.map(\.horizontalAccuracyMeters).max() ?? 0
    let searchRadius = max(
      configuration.minimumSearchRadiusMeters,
      maximumAccuracy + fixture.configuration.ambiguityMarginMeters
    )
    guard searchRadius <= configuration.maximumSearchRadiusMeters else {
      throw ValhallaMatcherReplayOracleError.unsupportedSearchRadius(searchRadius)
    }
    let firstTimestamp = observations[0].observedAtMilliseconds
    let payload = RequestPayload(
      shape: observations.map { observation in
        RequestPoint(
          lat: observation.coordinate.latitude,
          lon: observation.coordinate.longitude,
          time: Double(observation.observedAtMilliseconds - firstTimestamp) / 1_000
        )
      },
      traceOptions: TraceOptions(
        searchRadius: searchRadius,
        gpsAccuracy: maximumAccuracy,
        interpolationDistance: 0
      )
    )
    do {
      return try JSONEncoder().encode(payload)
    } catch {
      throw ValhallaMatcherReplayOracleError.requestEncodingFailed
    }
  }

  public func run(fixture: MatcherReplayFixture) async throws -> MatcherReplayReport {
    let body = try requestBody(for: fixture)
    let response = try await transport.post(action: .traceAttributes, jsonBody: body)
    guard (200..<300).contains(response.statusCode) else {
      throw ValhallaMatcherReplayOracleError.unsuccessfulHTTPStatus(response.statusCode)
    }
    let normalized = try normalizer.normalize(
      responseData: response.body,
      observationIDs: fixture.observations.map(\.id)
    )
    let observationsByID = Dictionary(
      uniqueKeysWithValues: fixture.observations.map { ($0.id, $0) }
    )
    let estimates = normalized.points.map { point in
      let observation = observationsByID[point.observationID]!
      return MatcherEstimate(
        observationID: point.observationID,
        estimatedAtMilliseconds: observation.observedAtMilliseconds,
        directedEdgeID: point.directedEdgeID,
        occurrenceID: nil,
        candidateEdgeIDs: point.candidateDirectedEdgeIDs,
        confidence: point.matchType == .unmatched ? .lost : .low,
        distanceMeters: point.distanceFromTracePointMeters
      )
    }
    return try MatcherReplayEvaluator.evaluate(
      fixture: fixture,
      algorithmID: configuration.algorithmID,
      estimates: estimates
    )
  }

  private func validate(fixture: MatcherReplayFixture) throws {
    let issues = fixture.validationIssues
    guard issues.isEmpty else {
      throw ValhallaMatcherReplayOracleError.invalidFixture(issues)
    }
    guard fixture.networkSnapshotID == graph.networkSnapshotID else {
      throw ValhallaMatcherReplayOracleError.snapshotMismatch(
        expected: graph.networkSnapshotID,
        received: fixture.networkSnapshotID
      )
    }
    let graphEdgeIDs = Set(graph.edges.map(\.id))
    for edge in fixture.edges where !graphEdgeIDs.contains(edge.id) {
      throw ValhallaMatcherReplayOracleError.fixtureEdgeMissing(edge.id)
    }
  }
}

private struct RequestPayload: Encodable {
  let shape: [RequestPoint]
  let costing = "auto"
  let shapeMatch = "map_snap"
  let traceOptions: TraceOptions
  let filters = RequestFilters()

  private enum CodingKeys: String, CodingKey {
    case shape
    case costing
    case shapeMatch = "shape_match"
    case traceOptions = "trace_options"
    case filters
  }
}

private struct RequestPoint: Encodable {
  let lat: Double
  let lon: Double
  let time: Double
}

private struct TraceOptions: Encodable {
  let searchRadius: Double
  let gpsAccuracy: Double
  let interpolationDistance: Double

  private enum CodingKeys: String, CodingKey {
    case searchRadius = "search_radius"
    case gpsAccuracy = "gps_accuracy"
    case interpolationDistance = "interpolation_distance"
  }
}

private struct RequestFilters: Encodable {
  let attributes = [
    "osm_changeset",
    "edge.id",
    "edge.way_id",
    "edge.forward",
    "edge.begin_osm_node_id",
    "edge.end_osm_node_id",
    "matched.point",
    "matched.type",
    "matched.edge_index",
    "matched.begin_route_discontinuity",
    "matched.end_route_discontinuity",
    "matched.distance_along_edge",
    "matched.distance_from_trace_point",
  ]
  let action = "include"
}
