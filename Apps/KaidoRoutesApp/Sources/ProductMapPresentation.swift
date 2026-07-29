import Combine
import Foundation
import KaidoDomain
import KaidoNavigation
import KaidoRouting

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
    key: String = "app.kaidoroutes.map-projection.v2"
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
    projection = store.projection() ?? .geographic
  }

  func select(_ projection: ProductMapProjection) {
    guard projection != self.projection else { return }
    store.setProjection(projection)
    self.projection = projection
  }
}

struct ProductMapCoordinate: Equatable, Sendable {
  let latitude: Double
  let longitude: Double

  init(_ coordinate: MatcherCoordinate) {
    latitude = coordinate.latitude
    longitude = coordinate.longitude
  }
}

struct ProductGeographicRoutePath: Equatable, Identifiable, Sendable {
  let id: String
  let occurrenceIndex: Int
  let coordinates: [ProductMapCoordinate]
}

struct ProductGeographicPositionMarker: Equatable, Sendable {
  let occurrenceID: String
  let coordinate: ProductMapCoordinate
}

struct ProductGeographicMapPresentation: Equatable, Sendable {
  let routePlanID: String
  let paths: [ProductGeographicRoutePath]
  let marker: ProductGeographicPositionMarker?

  var startCoordinate: ProductMapCoordinate? {
    paths.first?.coordinates.first
  }

  var finishCoordinate: ProductMapCoordinate? {
    paths.last?.coordinates.last
  }

  var coordinateCount: Int {
    paths.reduce(0) { $0 + $1.coordinates.count }
  }

  static func make(
    corridor: RouteMatcherCorridor,
    evidence: ProductTopologyPositionEvidence?
  ) -> ProductGeographicMapPresentation? {
    let edgesByID = Dictionary(
      uniqueKeysWithValues: corridor.edges.map { ($0.id, $0) }
    )
    let paths = corridor.occurrences
      .sorted { $0.index < $1.index }
      .compactMap { occurrence -> ProductGeographicRoutePath? in
        guard
          let edge = edgesByID[occurrence.directedEdgeID],
          edge.coordinates.count >= 2
        else {
          return nil
        }
        return ProductGeographicRoutePath(
          id: occurrence.id,
          occurrenceIndex: occurrence.index,
          coordinates: edge.coordinates.map(ProductMapCoordinate.init)
        )
      }
    guard paths.count == corridor.occurrences.count else {
      return nil
    }

    let marker: ProductGeographicPositionMarker?
    if let evidence,
      evidence.routePlanID == corridor.routePlanID,
      let occurrence = corridor.occurrences.first(where: {
        $0.id == evidence.occurrenceID
          && $0.directedEdgeID == evidence.directedEdgeID
      }),
      let edge = edgesByID[occurrence.directedEdgeID],
      let coordinate = coordinate(
        along: edge.coordinates,
        fraction: evidence.fractionAlongOccurrence
      )
    {
      marker = ProductGeographicPositionMarker(
        occurrenceID: occurrence.id,
        coordinate: ProductMapCoordinate(coordinate)
      )
    } else {
      marker = nil
    }

    return ProductGeographicMapPresentation(
      routePlanID: corridor.routePlanID,
      paths: paths,
      marker: marker
    )
  }

  private static func coordinate(
    along coordinates: [MatcherCoordinate],
    fraction: Double
  ) -> MatcherCoordinate? {
    guard let first = coordinates.first else { return nil }
    guard coordinates.count > 1 else { return first }

    let segments = zip(coordinates, coordinates.dropFirst()).map {
      start, end in
      (
        start: start,
        end: end,
        length: planarDistance(from: start, to: end)
      )
    }
    let totalLength = segments.reduce(0) { $0 + $1.length }
    guard totalLength > 0 else { return first }

    var remaining = min(1, max(0, fraction)) * totalLength
    for segment in segments {
      if remaining <= segment.length, segment.length > 0 {
        let localFraction = remaining / segment.length
        return MatcherCoordinate(
          latitude:
            segment.start.latitude
            + (segment.end.latitude - segment.start.latitude)
              * localFraction,
          longitude:
            segment.start.longitude
            + (segment.end.longitude - segment.start.longitude)
            * localFraction
        )
      }
      remaining -= segment.length
    }
    return coordinates.last
  }

  private static func planarDistance(
    from start: MatcherCoordinate,
    to end: MatcherCoordinate
  ) -> Double {
    let latitudeScale = cos(
      ((start.latitude + end.latitude) * 0.5) * .pi / 180
    )
    return hypot(
      end.latitude - start.latitude,
      (end.longitude - start.longitude) * latitudeScale
    )
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

enum ProductTopologyLandmarkKind: String, Equatable, Sendable {
  case entrance
  case junction
  case parkingArea
  case exit
}

struct ProductTopologyLandmark: Equatable, Identifiable, Sendable {
  let id: String
  let kind: ProductTopologyLandmarkKind
  let occurrenceIndex: Int
  let point: RouteAtlasPoint
  let title: RouteEditorLocalizedText
  let detail: RouteEditorLocalizedText?
}

enum ProductTopologyRouteSectionStyle: Equatable, Sendable {
  case primary
  case connector
}

struct ProductTopologyRouteSection: Equatable, Identifiable, Sendable {
  let id: String
  let routeShield: String
  let occurrenceIDs: Set<String>
  let style: ProductTopologyRouteSectionStyle
}

struct ProductTopologyFacilityPresentation: Equatable, Sendable {
  let routeShields: [String]
  let routeSections: [ProductTopologyRouteSection]
  let landmarks: [ProductTopologyLandmark]
  let entranceCount: Int
  let junctionCount: Int
  let parkingAreaCount: Int
  let exitCount: Int

  static func make(
    release: KaidoProductRelease
  ) -> ProductTopologyFacilityPresentation? {
    let bundle = release.navigation.bundle
    let routePlan = bundle.routePlan
    let editorCatalog = bundle.editorCatalog
    let presentationCatalog = bundle.editorPresentationCatalog
    let definition = release.routeAtlas.definition
    let bindingsByOccurrenceID = Dictionary(
      uniqueKeysWithValues: definition.occurrenceBindings.map {
        ($0.occurrenceID, $0)
      }
    )
    let segmentsByID = Dictionary(
      uniqueKeysWithValues: definition.segments.map { ($0.id, $0) }
    )

    func point(
      for occurrence: RouteOccurrence,
      endpoint: ProductTopologyLandmarkEndpoint
    ) -> RouteAtlasPoint? {
      guard
        let binding = bindingsByOccurrenceID[occurrence.id],
        let segment = segmentsByID[binding.segmentID]
      else {
        return nil
      }
      switch endpoint {
      case .start:
        return segment.points.first
      case .end:
        return segment.points.last
      }
    }

    guard
      let entrance = editorCatalog.entrances.first(where: {
        $0.facilityID == routePlan.entryFacilityID
      }),
      let entranceOccurrence = routePlan.occurrence(
        entityID: entrance.initialEdgeID
      ),
      let entrancePoint = point(
        for: entranceOccurrence,
        endpoint: .start
      ),
      let entrancePresentation =
        presentationCatalog.entrances.first(where: {
          $0.facilityID == routePlan.entryFacilityID
        })
    else {
      return nil
    }

    var selectedDecisions: [ProductTopologySelectedDecision] = []
    var junctionLandmarks: [ProductTopologyLandmark] = []
    for step in bundle.routeAuthoringRecipe.steps {
      guard
        let movementOccurrence = routePlan.occurrence(
          id: step.movementOccurrenceID
        ),
        let decisionPoint = editorCatalog.decisionPoints.first(where: {
          $0.id == step.decisionPointID
        }),
        let selectedChoice = decisionPoint.choices.first(where: {
          $0.id == step.choiceID
        }),
        let decisionPresentation =
          presentationCatalog.decisionPoints.first(where: {
            $0.decisionPointID == decisionPoint.id
          }),
        let choicePresentation =
          presentationCatalog.choices.first(where: {
            $0.choiceID == selectedChoice.id
          }),
        let decisionPoint = point(
          for: movementOccurrence,
          endpoint: .start
        )
      else {
        continue
      }

      selectedDecisions.append(
        ProductTopologySelectedDecision(
          choice: selectedChoice,
          presentation: choicePresentation
        )
      )
      junctionLandmarks.append(
        ProductTopologyLandmark(
          id: movementOccurrence.id,
          kind: .junction,
          occurrenceIndex: movementOccurrence.index,
          point: decisionPoint,
          title: decisionPresentation.title,
          detail: choicePresentation.title
        )
      )
    }

    let selectedExit = selectedDecisions.first { decision in
      guard case .exitFacility(let facilityID) = decision.choice.destination
      else {
        return false
      }
      return facilityID == routePlan.exitFacilityID
    }
    guard
      let selectedExit,
      let exitOccurrence = routePlan.occurrences.last,
      let exitPoint = point(for: exitOccurrence, endpoint: .end)
    else {
      return nil
    }

    var seenShields: Set<String> = []
    let routeShields = bundle.releasedGuidance
      .flatMap(\.frameTemplate.presentationSource.routeShields)
      .filter { seenShields.insert($0).inserted }

    let landmarks =
      [
        ProductTopologyLandmark(
          id: routePlan.entryFacilityID,
          kind: .entrance,
          occurrenceIndex: entranceOccurrence.index,
          point: entrancePoint,
          title: entrancePresentation.title,
          detail: nil
        )
      ]
      + junctionLandmarks.sorted { $0.occurrenceIndex < $1.occurrenceIndex }
      + [
        ProductTopologyLandmark(
          id: routePlan.exitFacilityID,
          kind: .exit,
          occurrenceIndex: exitOccurrence.index,
          point: exitPoint,
          title: selectedExit.presentation.title,
          detail: nil
        )
      ]

    return ProductTopologyFacilityPresentation(
      routeShields: routeShields,
      routeSections:
        routeShields.count == 1
        ? [
          ProductTopologyRouteSection(
            id: "released-route-\(routeShields[0])",
            routeShield: routeShields[0],
            occurrenceIDs: Set(routePlan.occurrences.map(\.id)),
            style: .primary
          )
        ]
        : [],
      landmarks: landmarks,
      entranceCount: 1,
      junctionCount: junctionLandmarks.count,
      parkingAreaCount:
        routePlan.occurrences.filter { $0.kind == .paVisit }.count,
      exitCount: 1
    )
  }
}

private enum ProductTopologyLandmarkEndpoint {
  case start
  case end
}

private struct ProductTopologySelectedDecision {
  let choice: ReviewedRouteEditorChoice
  let presentation: ReviewedRouteEditorChoicePresentation
}

struct ProductTopologyMapPresentation: Equatable, Sendable {
  let projection: RouteAtlasJourneyProjection
  let orderedOccurrences: [RouteAtlasJourneyOccurrence]
  let position: ProductTopologyPositionState
  let repeatedOccurrenceCount: Int
  let facilities: ProductTopologyFacilityPresentation?

  static func make(
    projection: RouteAtlasJourneyProjection,
    evidence: ProductTopologyPositionEvidence?,
    snapshot: NavigationSnapshot?,
    facilities: ProductTopologyFacilityPresentation? = nil
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
        orderedOccurrences.filter(\.isRepeatedTraversal).count,
      facilities: facilities
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
