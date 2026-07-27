import Combine
import Foundation
import KaidoDomain
import KaidoNavigation

enum ProductMapProjection: String, CaseIterable, Identifiable, Sendable {
  case geographic
  case topology

  var id: String { rawValue }
}

@MainActor
protocol ProductMapProjectionPreferenceStoring: AnyObject {
  func projection() -> ProductMapProjection?
  func setProjection(_ projection: ProductMapProjection)
}

@MainActor
final class UserDefaultsProductMapProjectionPreferenceStore:
  ProductMapProjectionPreferenceStoring
{
  private let defaults: UserDefaults
  private let key: String

  init(
    defaults: UserDefaults = .standard,
    key: String = "app.kaidoroutes.map-projection"
  ) {
    self.defaults = defaults
    self.key = key
  }

  func projection() -> ProductMapProjection? {
    guard let rawValue = defaults.string(forKey: key) else {
      return nil
    }
    return ProductMapProjection(rawValue: rawValue)
  }

  func setProjection(_ projection: ProductMapProjection) {
    defaults.set(projection.rawValue, forKey: key)
  }
}

@MainActor
final class ProductMapPresentationModel: ObservableObject {
  @Published private(set) var projection: ProductMapProjection

  private let store: any ProductMapProjectionPreferenceStoring

  init(
    store: any ProductMapProjectionPreferenceStoring =
      UserDefaultsProductMapProjectionPreferenceStore()
  ) {
    self.store = store
    projection = store.projection() ?? .topology
  }

  func select(_ projection: ProductMapProjection) {
    guard projection != self.projection else { return }
    store.setProjection(projection)
    self.projection = projection
  }
}

struct ProductTopologyPositionEvidence: Equatable, Sendable {
  let routePlanID: String
  let occurrenceID: String
  let directedEdgeID: String
  let fractionAlongOccurrence: Double
  let confidence: MatcherConfidence
  let markerStyle: String

  static func admitted(
    estimate: MatcherEstimate,
    snapshot: NavigationSnapshot,
    routePlan: RoutePlan
  ) -> ProductTopologyPositionEvidence? {
    guard
      estimate.confidence == .high,
      estimate.candidateEdgeIDs.count == 1,
      let directedEdgeID = estimate.directedEdgeID,
      estimate.candidateEdgeIDs.first == directedEdgeID,
      let occurrenceID = estimate.occurrenceID,
      let occurrence = routePlan.occurrence(id: occurrenceID),
      occurrence.kind == .edge,
      occurrence.entityID == directedEdgeID,
      snapshot.activeRoutePlanID == routePlan.id,
      snapshot.currentOccurrenceID == occurrenceID,
      snapshot.currentOccurrenceIndex == occurrence.index,
      snapshot.locationConfidence == .high,
      snapshot.routeCandidateResolution == .resolved,
      snapshot.markerStyle == "MEASURED",
      let fraction = estimate.fractionAlongEdge,
      fraction.isFinite,
      (0...1).contains(fraction)
    else {
      return nil
    }
    return ProductTopologyPositionEvidence(
      routePlanID: routePlan.id,
      occurrenceID: occurrenceID,
      directedEdgeID: directedEdgeID,
      fractionAlongOccurrence: fraction,
      confidence: estimate.confidence,
      markerStyle: snapshot.markerStyle
    )
  }
}

enum ProductTopologyPositionState: Equatable, Sendable {
  case unavailable
  case estimated(occurrenceID: String)
  case measured(ProductTopologyMarker)
}

struct ProductTopologyMarker: Equatable, Sendable {
  let occurrenceID: String
  let occurrenceIndex: Int
  let point: RouteAtlasPoint
  let repeatOrdinal: Int
  let repeatCount: Int
}

struct ProductTopologyMapPresentation: Equatable, Sendable {
  let projection: RouteAtlasJourneyProjection
  let orderedOccurrences: [RouteAtlasJourneyOccurrence]
  let position: ProductTopologyPositionState
  let repeatedOccurrenceCount: Int

  static func make(
    projection: RouteAtlasJourneyProjection,
    evidence: ProductTopologyPositionEvidence?,
    snapshot: NavigationSnapshot?
  ) -> ProductTopologyMapPresentation {
    let orderedOccurrences = projection.occurrences.sorted {
      $0.occurrenceIndex < $1.occurrenceIndex
    }
    let position = resolvePosition(
      projection: projection,
      orderedOccurrences: orderedOccurrences,
      evidence: evidence,
      snapshot: snapshot
    )
    return ProductTopologyMapPresentation(
      projection: projection,
      orderedOccurrences: orderedOccurrences,
      position: position,
      repeatedOccurrenceCount:
        orderedOccurrences.filter(\.isRepeatedTraversal).count
    )
  }

  private static func resolvePosition(
    projection: RouteAtlasJourneyProjection,
    orderedOccurrences: [RouteAtlasJourneyOccurrence],
    evidence: ProductTopologyPositionEvidence?,
    snapshot: NavigationSnapshot?
  ) -> ProductTopologyPositionState {
    if let evidence,
      evidence.routePlanID == projection.routePlanID,
      evidence.confidence == .high,
      evidence.markerStyle == "MEASURED",
      let occurrence = orderedOccurrences.first(where: {
        $0.occurrenceID == evidence.occurrenceID
      }),
      let point = point(
        along: ProductTopologyGeometry.octilinear(
          occurrence.points
        ),
        fraction: evidence.fractionAlongOccurrence
      )
    {
      return .measured(
        ProductTopologyMarker(
          occurrenceID: occurrence.occurrenceID,
          occurrenceIndex: occurrence.occurrenceIndex,
          point: point,
          repeatOrdinal: occurrence.repeatOrdinal,
          repeatCount: occurrence.repeatCount
        )
      )
    }

    guard
      let snapshot,
      snapshot.activeRoutePlanID == projection.routePlanID,
      let occurrenceID = snapshot.currentOccurrenceID,
      orderedOccurrences.contains(where: {
        $0.occurrenceID == occurrenceID
      })
    else {
      return .unavailable
    }
    switch snapshot.locationConfidence {
    case .medium, .low:
      return .estimated(occurrenceID: occurrenceID)
    case .high:
      return snapshot.markerStyle == "MEASURED"
        ? .unavailable
        : .estimated(occurrenceID: occurrenceID)
    case .lost:
      return .unavailable
    }
  }

  private static func point(
    along points: [RouteAtlasPoint],
    fraction: Double
  ) -> RouteAtlasPoint? {
    guard let first = points.first else { return nil }
    guard points.count > 1 else { return first }

    let segments = zip(points, points.dropFirst()).map { start, end in
      (
        start: start,
        end: end,
        length: hypot(end.x - start.x, end.y - start.y)
      )
    }
    let totalLength = segments.reduce(0) { $0 + $1.length }
    guard totalLength > 0 else { return first }

    var remaining = min(1, max(0, fraction)) * totalLength
    for segment in segments {
      if remaining <= segment.length, segment.length > 0 {
        let localFraction = remaining / segment.length
        return RouteAtlasPoint(
          x:
            segment.start.x
            + (segment.end.x - segment.start.x) * localFraction,
          y:
            segment.start.y
            + (segment.end.y - segment.start.y) * localFraction
        )
      }
      remaining -= segment.length
    }
    return points.last
  }
}

/// Converts one released display path into endpoint-preserving octilinear
/// geometry. It changes presentation only: every source path remains isolated,
/// and coordinate contact never becomes a graph connection.
enum ProductTopologyGeometry {
  static func octilinear(
    _ points: [RouteAtlasPoint]
  ) -> [RouteAtlasPoint] {
    guard let first = points.first else { return [] }
    var result = [first]

    for end in points.dropFirst() {
      guard let start = result.last else { continue }
      let deltaX = end.x - start.x
      let deltaY = end.y - start.y
      let absoluteX = abs(deltaX)
      let absoluteY = abs(deltaY)
      let tolerance = 0.000_001

      if absoluteX <= tolerance
        || absoluteY <= tolerance
        || abs(absoluteX - absoluteY) <= tolerance
      {
        result.append(end)
        continue
      }

      let elbow: RouteAtlasPoint
      if absoluteX > absoluteY {
        elbow = RouteAtlasPoint(
          x:
            start.x
            + (deltaX < 0 ? -absoluteY : absoluteY),
          y: end.y
        )
      } else {
        elbow = RouteAtlasPoint(
          x: end.x,
          y:
            start.y
            + (deltaY < 0 ? -absoluteX : absoluteX)
        )
      }
      if elbow != start, elbow != end {
        result.append(elbow)
      }
      result.append(end)
    }
    return result
  }
}
