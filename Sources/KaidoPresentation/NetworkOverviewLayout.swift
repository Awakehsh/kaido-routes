import Foundation

/// Whole-network browse layout: real snapshot geometry under a focus-plus-
/// context (fisheye) projection centered on the C1 area, so the dense center
/// opens up while the far ends pull in — the algorithmic equivalent of a
/// not-to-scale network diagram. Computed once per snapshot in a fixed design
/// space; the view scales and zooms it uniformly.
public struct NetworkOverviewLayout: Equatable, Sendable {
  public static let designWidth = 1000.0
  public static let designHeight = 1380.0

  public struct Point: Equatable, Sendable {
    public let x: Double
    public let y: Double
  }

  public struct WayInput: Equatable, Sendable {
    public let routeID: String
    public let coordinates: [RouteTrackMapLayout.GeoPoint]

    public init(
      routeID: String,
      coordinates: [RouteTrackMapLayout.GeoPoint]
    ) {
      self.routeID = routeID
      self.coordinates = coordinates
    }
  }

  /// Directional presence from the operator facility facts: a full facility
  /// serves both carriageway directions, a half facility one.
  public enum DirectionalPresence: Equatable, Sendable {
    case none
    case half
    case full
  }

  public struct FacilityInput: Equatable, Sendable {
    public let id: String
    public let nameJA: String
    public let coordinate: RouteTrackMapLayout.GeoPoint
    public let entranceDirectionCount: Int
    public let exitDirectionCount: Int
    public let etcOnly: Bool

    public init(
      id: String,
      nameJA: String,
      coordinate: RouteTrackMapLayout.GeoPoint,
      entranceDirectionCount: Int,
      exitDirectionCount: Int,
      etcOnly: Bool
    ) {
      self.id = id
      self.nameJA = nameJA
      self.coordinate = coordinate
      self.entranceDirectionCount = entranceDirectionCount
      self.exitDirectionCount = exitDirectionCount
      self.etcOnly = etcOnly
    }
  }

  public struct JunctionInput: Equatable, Sendable {
    public let id: String
    public let nameJA: String
    public let coordinate: RouteTrackMapLayout.GeoPoint

    public init(
      id: String,
      nameJA: String,
      coordinate: RouteTrackMapLayout.GeoPoint
    ) {
      self.id = id
      self.nameJA = nameJA
      self.coordinate = coordinate
    }
  }

  public struct Polyline: Equatable, Sendable {
    public let routeID: String
    public let points: [Point]
  }

  public struct RouteBadge: Equatable, Sendable {
    public let routeID: String
    public let label: String
    public let x: Double
    public let y: Double
  }

  public struct JunctionMark: Equatable, Sendable {
    public let id: String
    public let nameJA: String
    public let x: Double
    public let y: Double
  }

  public struct FacilityMark: Equatable, Sendable {
    public let id: String
    public let nameJA: String
    public let x: Double
    public let y: Double
    public let entrance: DirectionalPresence
    public let exit: DirectionalPresence
    public let etcOnly: Bool
  }

  /// The fisheye projection that produced this layout, retained so views can
  /// place arbitrary geographic points (current position, derived entrance
  /// and exit marks) into the same design space.
  public struct Projection: Equatable, Sendable {
    public let focus: RouteTrackMapLayout.GeoPoint
    public let compression: Double
    public let kx: Double
    public let ky: Double
    public let minX: Double
    public let maxY: Double
    public let scale: Double
    public let offsetX: Double
    public let offsetY: Double

    public func project(
      _ coordinate: RouteTrackMapLayout.GeoPoint
    ) -> Point {
      let dx = (coordinate.longitude - focus.longitude) * kx
      let dy = (coordinate.latitude - focus.latitude) * ky
      let radius = (dx * dx + dy * dy).squareRoot()
      let p: (x: Double, y: Double)
      if radius > 1e-9 {
        let compressed = pow(radius, compression)
        p = (dx / radius * compressed, dy / radius * compressed)
      } else {
        p = (0, 0)
      }
      return Point(
        x: offsetX + (p.x - minX) * scale,
        y: offsetY + (maxY - p.y) * scale
      )
    }
  }

  public let polylines: [Polyline]
  public let badges: [RouteBadge]
  public let junctionMarks: [JunctionMark]
  public let facilityMarks: [FacilityMark]
  public let projection: Projection

  // MARK: - Construction

  public static func make(
    ways: [WayInput],
    facilities: [FacilityInput],
    junctions: [JunctionInput],
    badgeLabels: [String: String],
    focus: RouteTrackMapLayout.GeoPoint = .init(
      latitude: 35.672,
      longitude: 139.755
    ),
    compression: Double = 0.62
  ) -> NetworkOverviewLayout? {
    guard !ways.isEmpty else { return nil }

    let kx = 111.32 * cos(focus.latitude * .pi / 180)
    let ky = 110.54
    func fisheye(
      _ coordinate: RouteTrackMapLayout.GeoPoint
    ) -> (x: Double, y: Double) {
      let dx = (coordinate.longitude - focus.longitude) * kx
      let dy = (coordinate.latitude - focus.latitude) * ky
      let radius = (dx * dx + dy * dy).squareRoot()
      guard radius > 1e-9 else { return (0, 0) }
      let compressed = pow(radius, compression)
      return (dx / radius * compressed, dy / radius * compressed)
    }

    var minX = Double.infinity
    var maxX = -Double.infinity
    var minY = Double.infinity
    var maxY = -Double.infinity
    for way in ways {
      for coordinate in way.coordinates {
        let p = fisheye(coordinate)
        minX = min(minX, p.x)
        maxX = max(maxX, p.x)
        minY = min(minY, p.y)
        maxY = max(maxY, p.y)
      }
    }
    guard maxX > minX, maxY > minY else { return nil }
    let margin = 80.0
    let scale = min(
      (designWidth - 2 * margin) / (maxX - minX),
      (designHeight - 2 * margin) / (maxY - minY)
    )
    let offsetX = (designWidth - (maxX - minX) * scale) / 2
    let offsetY = (designHeight - (maxY - minY) * scale) / 2
    let projection = Projection(
      focus: focus,
      compression: compression,
      kx: kx,
      ky: ky,
      minX: minX,
      maxY: maxY,
      scale: scale,
      offsetX: offsetX,
      offsetY: offsetY
    )
    func project(
      _ coordinate: RouteTrackMapLayout.GeoPoint
    ) -> Point {
      projection.project(coordinate)
    }

    func simplifyAndSmooth(_ points: [Point]) -> [Point] {
      guard points.count > 2 else { return points }
      var kept: [Point] = [points[0]]
      for point in points.dropFirst().dropLast() {
        let last = kept[kept.count - 1]
        if ((point.x - last.x) * (point.x - last.x)
          + (point.y - last.y) * (point.y - last.y)).squareRoot() >= 2.2
        {
          kept.append(point)
        }
      }
      kept.append(points[points.count - 1])
      var smooth = kept
      for _ in 0..<2 {
        var next: [Point] = [smooth[0]]
        for index in 0..<(smooth.count - 1) {
          let a = smooth[index]
          let b = smooth[index + 1]
          next.append(
            Point(x: a.x * 0.75 + b.x * 0.25, y: a.y * 0.75 + b.y * 0.25)
          )
          next.append(
            Point(x: a.x * 0.25 + b.x * 0.75, y: a.y * 0.25 + b.y * 0.75)
          )
        }
        next.append(smooth[smooth.count - 1])
        smooth = next
      }
      return smooth
    }

    let polylines: [Polyline] = ways.compactMap { way in
      let projected = way.coordinates.map(project)
      guard projected.count > 1 else { return nil }
      return Polyline(
        routeID: way.routeID,
        points: simplifyAndSmooth(projected)
      )
    }

    // Badges at the midpoint of each route's longest way, pushed apart.
    var badges: [RouteBadge] = []
    let routeIDs = Dictionary(grouping: polylines, by: \.routeID)
    let orderedRouteIDs = routeIDs.keys.sorted {
      let left = routeIDs[$0]!.reduce(0) { $0 + $1.points.count }
      let right = routeIDs[$1]!.reduce(0) { $0 + $1.points.count }
      if left != right { return left > right }
      return $0 < $1
    }
    for routeID in orderedRouteIDs {
      guard let label = badgeLabels[routeID] else { continue }
      let longest = routeIDs[routeID]!.max {
        $0.points.count < $1.points.count
      }!
      var x = longest.points[longest.points.count / 2].x
      var y = longest.points[longest.points.count / 2].y
      for other in badges {
        let dx = x - other.x
        let dy = y - other.y
        let distance = (dx * dx + dy * dy).squareRoot()
        if distance < 42 {
          let push = 42 - distance
          if distance > 0.1 {
            x += dx / distance * push
            y += dy / distance * push
          } else {
            y -= 42
          }
        }
      }
      badges.append(RouteBadge(routeID: routeID, label: label, x: x, y: y))
    }

    let junctionMarks = junctions.map { junction in
      let p = project(junction.coordinate)
      return JunctionMark(
        id: junction.id,
        nameJA: junction.nameJA,
        x: p.x,
        y: p.y
      )
    }

    func presence(_ count: Int) -> DirectionalPresence {
      count >= 2 ? .full : count == 1 ? .half : .none
    }
    let facilityMarks = facilities.map { facility in
      let p = project(facility.coordinate)
      return FacilityMark(
        id: facility.id,
        nameJA: facility.nameJA,
        x: p.x,
        y: p.y,
        entrance: presence(facility.entranceDirectionCount),
        exit: presence(facility.exitDirectionCount),
        etcOnly: facility.etcOnly
      )
    }

    return NetworkOverviewLayout(
      polylines: polylines,
      badges: badges,
      junctionMarks: junctionMarks,
      facilityMarks: facilityMarks,
      projection: projection
    )
  }
}
