import Foundation

/// Renderer-neutral whole-route track map layout: the entire selected route
/// in one readable frame, every on-route facility always labeled, computed
/// once per route in a fixed design space. The view scales the design space
/// uniformly; no semantic zoom exists.
public struct RouteTrackMapLayout: Equatable, Sendable {
  public static let designWidth = 430.0
  public static let designHeight = 680.0

  public struct GeoPoint: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
      self.latitude = latitude
      self.longitude = longitude
    }
  }

  public enum FacilityKind: Equatable, Sendable {
    case interchange
    case junction
    case parkingArea
  }

  public struct FacilityInput: Equatable, Sendable {
    public let id: String
    public let nameJA: String
    public let kind: FacilityKind
    public let coordinate: GeoPoint

    public init(
      id: String,
      nameJA: String,
      kind: FacilityKind,
      coordinate: GeoPoint
    ) {
      self.id = id
      self.nameJA = nameJA
      self.kind = kind
      self.coordinate = coordinate
    }
  }

  public struct TrackPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let fraction: Double
  }

  public enum LabelZone: Equatable, Sendable {
    case left
    case right
    case top
    case bottom
  }

  public struct FacilityMark: Equatable, Sendable {
    public let id: String
    public let nameJA: String
    public let kind: FacilityKind
    public let fraction: Double
    public let x: Double
    public let y: Double
    public let labelX: Double
    public let labelY: Double
    public let zone: LabelZone
  }

  public let trackPoints: [TrackPoint]
  public let facilityMarks: [FacilityMark]

  /// Smoothed points whose fraction lies inside the range, for span coloring.
  public func points(
    fromFraction start: Double,
    toFraction end: Double
  ) -> [TrackPoint] {
    trackPoints.filter { $0.fraction >= start && $0.fraction <= end }
  }

  public func point(atFraction fraction: Double) -> TrackPoint {
    let clamped = min(max(fraction, 0), 1)
    var best = trackPoints[0]
    var bestDelta = Double.infinity
    for point in trackPoints {
      let delta = abs(point.fraction - clamped)
      if delta < bestDelta {
        bestDelta = delta
        best = point
      }
    }
    return best
  }

  /// Local travel heading in degrees (0 = +x, counterclockwise-positive in
  /// design space, where +y points down).
  public func heading(atFraction fraction: Double) -> Double {
    let before = point(atFraction: max(0, fraction - 0.004))
    let after = point(atFraction: min(1, fraction + 0.004))
    return atan2(after.y - before.y, after.x - before.x) * 180 / .pi
  }

  /// Nearest design-space point on the track for a measured coordinate.
  /// Repeated-lap geometry overlaps, so the nearest projection is stable
  /// for marker placement regardless of the lap ordinal.
  public func nearestTrackPoint(
    to coordinate: GeoPoint,
    projector: (GeoPoint) -> (x: Double, y: Double)
  ) -> TrackPoint {
    let target = projector(coordinate)
    var best = trackPoints[0]
    var bestDistance = Double.infinity
    for point in trackPoints {
      let dx = point.x - target.x
      let dy = point.y - target.y
      let distance = dx * dx + dy * dy
      if distance < bestDistance {
        bestDistance = distance
        best = point
      }
    }
    return best
  }

  /// Projects a geographic coordinate with the same transform the layout
  /// used, so external points (a measured position) land on the same frame.
  public let projector: RouteTrackMapProjector

  // MARK: - Construction

  public static func make(
    routeCoordinates: [GeoPoint],
    facilities: [FacilityInput],
    maximumFacilityDistanceMeters: Double = 400,
    junctionFacilityDistanceMeters: Double = 1_500
  ) -> RouteTrackMapLayout? {
    guard routeCoordinates.count >= 2 else { return nil }

    // Equirectangular meters relative to the route's midpoint latitude.
    let latMid =
      routeCoordinates.reduce(0) { $0 + $1.latitude }
      / Double(routeCoordinates.count)
    let metersPerLon = 111_320 * cos(latMid * .pi / 180)
    let metersPerLat = 110_540.0
    let raw = routeCoordinates.map {
      (x: $0.longitude * metersPerLon, y: -$0.latitude * metersPerLat)
    }
    let minX = raw.map(\.x).min()!
    let maxX = raw.map(\.x).max()!
    let minY = raw.map(\.y).min()!
    let maxY = raw.map(\.y).max()!
    guard maxX > minX, maxY > minY else { return nil }

    // Track box leaves side columns and top/bottom rows for labels.
    let boxMinX = 112.0
    let boxMaxX = 318.0
    let boxMinY = 190.0
    let boxMaxY = 520.0
    let scale = min(
      (boxMaxX - boxMinX) / (maxX - minX),
      (boxMaxY - boxMinY) / (maxY - minY)
    )
    let offsetX = boxMinX + ((boxMaxX - boxMinX) - (maxX - minX) * scale) / 2
    let offsetY = boxMinY + ((boxMaxY - boxMinY) - (maxY - minY) * scale) / 2
    let projector = RouteTrackMapProjector(
      metersPerLon: metersPerLon,
      metersPerLat: metersPerLat,
      minX: minX,
      minY: minY,
      scale: scale,
      offsetX: offsetX,
      offsetY: offsetY
    )
    let projected = routeCoordinates.map(projector.project)

    // Cumulative fractions along the full occurrence sequence.
    var cumulative = [0.0]
    cumulative.reserveCapacity(projected.count)
    for index in 1..<projected.count {
      let dx = projected[index].x - projected[index - 1].x
      let dy = projected[index].y - projected[index - 1].y
      cumulative.append(cumulative[index - 1] + (dx * dx + dy * dy).squareRoot())
    }
    let total = cumulative[projected.count - 1]
    guard total > 0 else { return nil }

    // Downsample, then Chaikin-smooth while preserving fractions.
    let step = max(1, projected.count / 700)
    var sampled: [TrackPoint] = []
    for index in stride(from: 0, to: projected.count, by: step) {
      sampled.append(
        TrackPoint(
          x: projected[index].x,
          y: projected[index].y,
          fraction: cumulative[index] / total
        )
      )
    }
    if sampled.last.map({ $0.fraction < 1 }) ?? false {
      let last = projected[projected.count - 1]
      sampled.append(TrackPoint(x: last.x, y: last.y, fraction: 1))
    }
    var smooth = sampled
    for _ in 0..<2 {
      var next: [TrackPoint] = []
      next.reserveCapacity(smooth.count * 2)
      next.append(smooth[0])
      for index in 0..<(smooth.count - 1) {
        let a = smooth[index]
        let b = smooth[index + 1]
        next.append(
          TrackPoint(
            x: a.x * 0.75 + b.x * 0.25,
            y: a.y * 0.75 + b.y * 0.25,
            fraction: a.fraction * 0.75 + b.fraction * 0.25
          )
        )
        next.append(
          TrackPoint(
            x: a.x * 0.25 + b.x * 0.75,
            y: a.y * 0.25 + b.y * 0.75,
            fraction: a.fraction * 0.25 + b.fraction * 0.75
          )
        )
      }
      next.append(smooth[smooth.count - 1])
      smooth = next
    }

    // Facility snapping: nearest raw point within the per-kind threshold.
    struct Snapped {
      let input: FacilityInput
      let fraction: Double
      let x: Double
      let y: Double
    }
    var snapped: [Snapped] = []
    for facility in facilities {
      let target = projector.project(facility.coordinate)
      var bestIndex = -1
      var bestDistance = Double.infinity
      for index in 0..<projected.count {
        let dx = projected[index].x - target.x
        let dy = projected[index].y - target.y
        let distance = dx * dx + dy * dy
        if distance < bestDistance {
          bestDistance = distance
          bestIndex = index
        }
      }
      let limit =
        (facility.kind == .junction
          ? junctionFacilityDistanceMeters
          : maximumFacilityDistanceMeters) * scale
      guard bestIndex >= 0, bestDistance.squareRoot() <= limit else {
        continue
      }
      snapped.append(
        Snapped(
          input: facility,
          fraction: cumulative[bestIndex] / total,
          x: projected[bestIndex].x,
          y: projected[bestIndex].y
        )
      )
    }
    snapped.sort {
      if $0.fraction != $1.fraction { return $0.fraction < $1.fraction }
      return $0.input.id < $1.input.id
    }
    // Repeated laps snap facilities once; identical IDs stay single marks.
    var seenIDs = Set<String>()
    snapped = snapped.filter { seenIDs.insert($0.input.id).inserted }

    // Zone assignment around the track centroid, then in-zone spreading.
    let centerX = smooth.reduce(0) { $0 + $1.x } / Double(smooth.count)
    let centerY = smooth.reduce(0) { $0 + $1.y } / Double(smooth.count)
    let trackTop = smooth.map(\.y).min() ?? boxMinY
    let trackBottom = smooth.map(\.y).max() ?? boxMaxY
    let leftX = 96.0
    let rightX = 334.0
    let topY = trackTop - 46
    let bottomY = trackBottom + 50

    func zone(forX x: Double, y: Double) -> LabelZone {
      let angle =
        (atan2(y - centerY, x - centerX) * 180 / .pi + 360)
        .truncatingRemainder(dividingBy: 360)
      if angle < 50 || angle >= 310 { return .right }
      if angle < 130 { return .bottom }
      if angle < 230 { return .left }
      return .top
    }

    struct Working {
      let snapped: Snapped
      let zone: LabelZone
      var labelX = 0.0
      var labelY = 0.0
    }
    var working = snapped.map {
      Working(snapped: $0, zone: zone(forX: $0.x, y: $0.y))
    }

    func spread(
      _ values: [Double],
      minimumSeparation: Double,
      lowerBound: Double,
      upperBound: Double
    ) -> [Double] {
      let order = values.indices.sorted { values[$0] < values[$1] }
      var placed = values
      for (rank, index) in order.enumerated() where rank > 0 {
        let previous = placed[order[rank - 1]]
        if placed[index] < previous + minimumSeparation {
          placed[index] = previous + minimumSeparation
        }
      }
      if let lastIndex = order.last, placed[lastIndex] > upperBound {
        let overflow = placed[lastIndex] - upperBound
        for index in order { placed[index] -= overflow }
        for rank in stride(from: order.count - 1, through: 1, by: -1) {
          let current = order[rank]
          let previous = order[rank - 1]
          if placed[previous] > placed[current] - minimumSeparation {
            placed[previous] = placed[current] - minimumSeparation
          }
        }
      }
      if let firstIndex = order.first, placed[firstIndex] < lowerBound {
        let underflow = lowerBound - placed[firstIndex]
        for index in order { placed[index] += underflow }
      }
      return placed
    }

    for zoneCase in [LabelZone.left, .right, .top, .bottom] {
      let indices = working.indices.filter { working[$0].zone == zoneCase }
      guard !indices.isEmpty else { continue }
      switch zoneCase {
      case .left, .right:
        let placed = spread(
          indices.map { working[$0].snapped.y },
          minimumSeparation: 21,
          lowerBound: 150,
          upperBound: 540
        )
        for (offset, index) in indices.enumerated() {
          working[index].labelY = placed[offset]
          working[index].labelX = zoneCase == .left ? leftX : rightX
        }
      case .top, .bottom:
        let placed = spread(
          indices.map { working[$0].snapped.x },
          minimumSeparation: 46,
          lowerBound: 26,
          upperBound: 404
        )
        let order = indices.indices.sorted {
          placed[$0] < placed[$1]
        }
        for (rank, offset) in order.enumerated() {
          let index = indices[offset]
          working[index].labelX = placed[offset]
          let stagger = rank % 2 == 1 ? 20.0 : 0.0
          working[index].labelY =
            zoneCase == .top ? topY - stagger : bottomY + stagger
        }
      }
    }

    let marks = working.map {
      FacilityMark(
        id: $0.snapped.input.id,
        nameJA: $0.snapped.input.nameJA,
        kind: $0.snapped.input.kind,
        fraction: $0.snapped.fraction,
        x: $0.snapped.x,
        y: $0.snapped.y,
        labelX: $0.labelX,
        labelY: $0.labelY,
        zone: $0.zone
      )
    }
    return RouteTrackMapLayout(
      trackPoints: smooth,
      facilityMarks: marks,
      projector: projector
    )
  }
}

/// The exact geographic-to-design-space transform used by one layout.
public struct RouteTrackMapProjector: Equatable, Sendable {
  let metersPerLon: Double
  let metersPerLat: Double
  let minX: Double
  let minY: Double
  let scale: Double
  let offsetX: Double
  let offsetY: Double

  public func project(
    _ coordinate: RouteTrackMapLayout.GeoPoint
  ) -> (x: Double, y: Double) {
    (
      x: offsetX
        + (coordinate.longitude * metersPerLon - minX) * scale,
      y: offsetY
        + (-coordinate.latitude * metersPerLat - minY) * scale
    )
  }
}
