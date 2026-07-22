import Foundation

public struct SurfaceCoordinate: Codable, Equatable, Sendable {
  public let latitude: Double
  public let longitude: Double

  public init(latitude: Double, longitude: Double) {
    self.latitude = latitude
    self.longitude = longitude
  }

  public var isValid: Bool {
    (-90...90).contains(latitude) && (-180...180).contains(longitude)
  }
}

public struct DirectedApproachAnchor: Codable, Equatable, Sendable {
  public let id: String
  public let coordinate: SurfaceCoordinate
  public let directedSurfaceEdgeID: String
  public let expectedBearingDegrees: Double
  public let bearingToleranceDegrees: Double
  public let maxTerminalDistanceMeters: Double

  public init(
    id: String,
    coordinate: SurfaceCoordinate,
    directedSurfaceEdgeID: String,
    expectedBearingDegrees: Double,
    bearingToleranceDegrees: Double,
    maxTerminalDistanceMeters: Double
  ) {
    self.id = id
    self.coordinate = coordinate
    self.directedSurfaceEdgeID = directedSurfaceEdgeID
    self.expectedBearingDegrees = expectedBearingDegrees
    self.bearingToleranceDegrees = bearingToleranceDegrees
    self.maxTerminalDistanceMeters = maxTerminalDistanceMeters
  }

  private enum CodingKeys: String, CodingKey {
    case id = "anchor_id"
    case coordinate
    case directedSurfaceEdgeID = "directed_surface_edge_id"
    case expectedBearingDegrees = "expected_bearing_degrees"
    case bearingToleranceDegrees = "bearing_tolerance_degrees"
    case maxTerminalDistanceMeters = "max_terminal_distance_meters"
  }
}

public struct SurfaceRoutePreferences: Codable, Equatable, Sendable {
  public let avoidHighways: Bool
  public let avoidTolls: Bool
  public let requestAlternatives: Bool

  public init(
    avoidHighways: Bool = true,
    avoidTolls: Bool = true,
    requestAlternatives: Bool = true
  ) {
    self.avoidHighways = avoidHighways
    self.avoidTolls = avoidTolls
    self.requestAlternatives = requestAlternatives
  }

  private enum CodingKeys: String, CodingKey {
    case avoidHighways = "avoid_highways"
    case avoidTolls = "avoid_tolls"
    case requestAlternatives = "request_alternatives"
  }
}

public struct SurfaceRouteRequest: Codable, Equatable, Sendable {
  public let id: String
  public let originID: String
  public let origin: SurfaceCoordinate
  public let entranceFacilityID: String
  public let selectedJoinOccurrenceID: String
  public let destinationAnchor: DirectedApproachAnchor
  public let preferences: SurfaceRoutePreferences

  public init(
    id: String,
    originID: String,
    origin: SurfaceCoordinate,
    entranceFacilityID: String,
    selectedJoinOccurrenceID: String,
    destinationAnchor: DirectedApproachAnchor,
    preferences: SurfaceRoutePreferences = SurfaceRoutePreferences()
  ) {
    self.id = id
    self.originID = originID
    self.origin = origin
    self.entranceFacilityID = entranceFacilityID
    self.selectedJoinOccurrenceID = selectedJoinOccurrenceID
    self.destinationAnchor = destinationAnchor
    self.preferences = preferences
  }

  private enum CodingKeys: String, CodingKey {
    case id = "request_id"
    case originID = "origin_id"
    case origin
    case entranceFacilityID = "entrance_facility_id"
    case selectedJoinOccurrenceID = "selected_join_occurrence_id"
    case destinationAnchor = "destination_anchor"
    case preferences
  }
}

public struct SurfaceRouteStep: Codable, Equatable, Sendable {
  public let id: String
  public let instruction: String
  public let notice: String?
  public let distanceMeters: Double

  public init(
    id: String,
    instruction: String,
    notice: String? = nil,
    distanceMeters: Double
  ) {
    self.id = id
    self.instruction = instruction
    self.notice = notice
    self.distanceMeters = distanceMeters
  }

  private enum CodingKeys: String, CodingKey {
    case id = "step_id"
    case instruction
    case notice
    case distanceMeters = "distance_meters"
  }
}

/// A provider-selected path translated onto the exact Kaido graph snapshot.
///
/// Adapters must omit this value unless their complete selected path can be
/// mapped to Kaido directed edge IDs from the same network snapshot. Provider
/// hints, maneuver names, or a second engine rematching an opaque polyline are
/// not selected-path evidence.
public struct SurfaceSelectedPathEvidence: Codable, Equatable, Sendable {
  public let networkSnapshotID: String
  public let providerDatasetID: String
  public let directedEdgeIDs: [String]

  public init(
    networkSnapshotID: String,
    providerDatasetID: String,
    directedEdgeIDs: [String]
  ) {
    self.networkSnapshotID = networkSnapshotID
    self.providerDatasetID = providerDatasetID
    self.directedEdgeIDs = directedEdgeIDs
  }

  private enum CodingKeys: String, CodingKey {
    case networkSnapshotID = "network_snapshot_id"
    case providerDatasetID = "provider_dataset_id"
    case directedEdgeIDs = "directed_edge_ids"
  }
}

public struct SurfaceRouteCandidate: Codable, Equatable, Sendable {
  public let id: String
  public let providerID: String
  public let coordinates: [SurfaceCoordinate]
  public let steps: [SurfaceRouteStep]
  public let distanceMeters: Double
  public let expectedTravelTimeSeconds: Double
  public let hasHighways: Bool?
  public let hasTolls: Bool?
  public let advisoryNotices: [String]
  public let selectedPathEvidence: SurfaceSelectedPathEvidence?

  public init(
    id: String,
    providerID: String,
    coordinates: [SurfaceCoordinate],
    steps: [SurfaceRouteStep],
    distanceMeters: Double,
    expectedTravelTimeSeconds: Double,
    hasHighways: Bool? = nil,
    hasTolls: Bool? = nil,
    advisoryNotices: [String] = [],
    selectedPathEvidence: SurfaceSelectedPathEvidence? = nil
  ) {
    self.id = id
    self.providerID = providerID
    self.coordinates = coordinates
    self.steps = steps
    self.distanceMeters = distanceMeters
    self.expectedTravelTimeSeconds = expectedTravelTimeSeconds
    self.hasHighways = hasHighways
    self.hasTolls = hasTolls
    self.advisoryNotices = advisoryNotices
    self.selectedPathEvidence = selectedPathEvidence
  }

  private enum CodingKeys: String, CodingKey {
    case id = "candidate_id"
    case providerID = "provider_id"
    case coordinates
    case steps
    case distanceMeters = "distance_meters"
    case expectedTravelTimeSeconds = "expected_travel_time_seconds"
    case hasHighways = "has_highways"
    case hasTolls = "has_tolls"
    case advisoryNotices = "advisory_notices"
    case selectedPathEvidence = "selected_path_evidence"
  }
}

public enum ProviderDataReviewStatus: String, Codable, Sendable {
  case reviewRequired = "REVIEW_REQUIRED"
  case scalarRetentionReviewed = "SCALAR_RETENTION_REVIEWED"
  case derivedFixtureReviewed = "DERIVED_FIXTURE_REVIEWED"
}

public struct SurfaceRouteProviderMetadata: Codable, Equatable, Sendable {
  public let id: String
  public let adapterVersion: String
  public let providerVersion: String?
  public let dataReviewStatus: ProviderDataReviewStatus

  public init(
    id: String,
    adapterVersion: String,
    providerVersion: String? = nil,
    dataReviewStatus: ProviderDataReviewStatus
  ) {
    self.id = id
    self.adapterVersion = adapterVersion
    self.providerVersion = providerVersion
    self.dataReviewStatus = dataReviewStatus
  }

  private enum CodingKeys: String, CodingKey {
    case id = "provider_id"
    case adapterVersion = "adapter_version"
    case providerVersion = "provider_version"
    case dataReviewStatus = "data_review_status"
  }
}

public struct SurfaceProviderFailure: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable {
    case noRoute = "NO_ROUTE"
    case network = "NETWORK"
    case throttled = "THROTTLED"
    case server = "SERVER"
    case cancelled = "CANCELLED"
    case invalidRequest = "INVALID_REQUEST"
    case unknown = "UNKNOWN"
  }

  public let kind: Kind
  public let providerErrorCode: String?
  public let message: String?

  public init(
    kind: Kind,
    providerErrorCode: String? = nil,
    message: String? = nil
  ) {
    self.kind = kind
    self.providerErrorCode = providerErrorCode
    self.message = message
  }

  private enum CodingKeys: String, CodingKey {
    case kind
    case providerErrorCode = "provider_error_code"
    case message
  }
}

public enum SurfaceProviderResponse: Equatable, Sendable {
  case success([SurfaceRouteCandidate])
  case failure(SurfaceProviderFailure)
}

public protocol SurfaceRouteProvider: Sendable {
  var metadata: SurfaceRouteProviderMetadata { get }

  func routes(for request: SurfaceRouteRequest) async -> SurfaceProviderResponse
}
