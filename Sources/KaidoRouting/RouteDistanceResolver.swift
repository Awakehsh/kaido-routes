import Foundation
import KaidoDomain

public enum RouteDistanceResolutionError: Error, Equatable, Sendable {
  case networkSnapshotMismatch
  case invalidEntityDistance(String)
  case missingOccurrenceDistance(String)
  case invalidTotalDistance

  public var code: String {
    switch self {
    case .networkSnapshotMismatch:
      "ROUTE_DISTANCE_SNAPSHOT_MISMATCH"
    case .invalidEntityDistance:
      "INVALID_REVIEWED_ENTITY_DISTANCE"
    case .missingOccurrenceDistance:
      "MISSING_REVIEWED_OCCURRENCE_DISTANCE"
    case .invalidTotalDistance:
      "INVALID_ACTUAL_ROUTE_DISTANCE"
    }
  }
}

/// Snapshot-bound, reviewed lengths for route entities.
///
/// Resolution iterates RoutePlan occurrences rather than unique entity IDs, so
/// every repeated traversal contributes its full reviewed length.
public struct ReviewedRouteDistanceCatalog: Equatable, Sendable {
  public let networkSnapshotID: String
  public let distanceKMByEntityID: [String: Double]

  public init(
    networkSnapshotID: String,
    distanceKMByEntityID: [String: Double]
  ) {
    self.networkSnapshotID = networkSnapshotID
    self.distanceKMByEntityID = distanceKMByEntityID
  }
}

public enum RouteDistanceResolver {
  public static func resolve(
    routePlan: RoutePlan,
    catalog: ReviewedRouteDistanceCatalog
  ) throws -> RoutePlan {
    guard routePlan.networkSnapshotID == catalog.networkSnapshotID else {
      throw RouteDistanceResolutionError.networkSnapshotMismatch
    }
    for (entityID, distanceKM) in catalog.distanceKMByEntityID
    where entityID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || !distanceKM.isFinite || distanceKM < 0
    {
      throw RouteDistanceResolutionError.invalidEntityDistance(entityID)
    }

    var actualDistanceKM = 0.0
    for occurrence in routePlan.occurrences {
      guard let distanceKM = catalog.distanceKMByEntityID[occurrence.entityID] else {
        throw RouteDistanceResolutionError.missingOccurrenceDistance(occurrence.id)
      }
      actualDistanceKM += distanceKM
    }
    guard actualDistanceKM.isFinite, actualDistanceKM > 0 else {
      throw RouteDistanceResolutionError.invalidTotalDistance
    }

    return RoutePlan(
      id: routePlan.id,
      networkSnapshotID: routePlan.networkSnapshotID,
      entryFacilityID: routePlan.entryFacilityID,
      exitFacilityID: routePlan.exitFacilityID,
      recoveryPolicy: routePlan.recoveryPolicy,
      actualDistanceKM: actualDistanceKM,
      occurrences: routePlan.occurrences
    )
  }
}
