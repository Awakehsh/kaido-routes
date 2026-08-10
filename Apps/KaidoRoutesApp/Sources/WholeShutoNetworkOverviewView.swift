import KaidoPresentation
import KaidoRouting
import SwiftUI

/// Builds and caches the whole-network overview layout once per snapshot.
@MainActor
enum WholeShutoNetworkOverviewCatalog {
  static let badgeLabels: [String: String] = [
    "C1": "C1", "C2": "C2", "B": "B", "1_UENO": "1", "1_HANEDA": "1",
    "2": "2", "3": "3", "4": "4", "5": "5", "6_MUKOJIMA": "6",
    "6_MISATO": "6", "7": "7", "9": "9", "10": "10", "11": "11",
    "S1": "S1", "S2": "S2", "S5": "S5", "K1": "K1", "K2": "K2",
    "K3": "K3", "K5": "K5", "K6": "K6", "K7_YOKOHAMA_KITA": "K7",
    "K7_YOKOHAMA_HOKUSEI": "K7",
  ]

  private static var cachedSnapshotID: String?
  private static var cachedLayout: NetworkOverviewLayout?

  static func layout(
    for database: ShutoNetworkDatabase
  ) -> NetworkOverviewLayout? {
    if cachedSnapshotID == database.networkSnapshotID,
      let cachedLayout
    {
      return cachedLayout
    }
    let nodesByID = Dictionary(
      uniqueKeysWithValues: database.nodes.map {
        ($0.nodeID, $0.coordinate)
      }
    )
    let ways: [NetworkOverviewLayout.WayInput] = database.ways.compactMap {
      way in
      guard way.kind == "MAINLINE",
        let routeID = way.routeMemberships.first?.routeID
      else { return nil }
      let coordinates = way.nodeIDs.compactMap { nodesByID[$0] }.map {
        RouteTrackMapLayout.GeoPoint(
          latitude: $0.latitude,
          longitude: $0.longitude
        )
      }
      guard coordinates.count > 1 else { return nil }
      return NetworkOverviewLayout.WayInput(
        routeID: routeID,
        coordinates: coordinates
      )
    }
    let facilities = database.directionalFacilities
      .filter { $0.operationalStatus == "AVAILABLE" }
      .map {
        NetworkOverviewLayout.FacilityInput(
          id: $0.facilityID,
          nameJA: $0.nameJA,
          coordinate: RouteTrackMapLayout.GeoPoint(
            latitude: $0.coordinate.latitude,
            longitude: $0.coordinate.longitude
          ),
          entranceDirectionCount: $0.entranceDirections.count,
          exitDirectionCount: $0.exitDirections.count,
          etcOnly: $0.etcOnly
        )
      }
    let junctions: [NetworkOverviewLayout.JunctionInput] =
      database.junctions.compactMap { junction in
        guard let coordinate = junction.coordinate else { return nil }
        return NetworkOverviewLayout.JunctionInput(
          id: junction.junctionID,
          nameJA: junction.nameJA,
          coordinate: RouteTrackMapLayout.GeoPoint(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
          )
        )
      }
    let layout = NetworkOverviewLayout.make(
      ways: ways,
      facilities: facilities,
      junctions: junctions,
      badgeLabels: badgeLabels
    )
    cachedSnapshotID = database.networkSnapshotID
    cachedLayout = layout
    return layout
  }
}

/// The whole-network browse map: real snapshot geometry under the focus-plus-
/// context projection in the track-map visual language. Drawing happens in
/// screen space so labels, badges, and marks keep a constant on-screen size —
/// label density therefore self-declutters at low zoom and fills in as the
/// driver pinches closer. Pinch anchors at the fingers, double-tap toggles a
/// closer frame, and panning never lets the diagram leave the screen.
struct WholeShutoNetworkOverviewView: View {
  /// Planning-state marks drawn on top of the diagram: the driver's position
  /// and the derived entrance/exit pairing for the selected circuit. Purely
  /// presentational — the diagram never carries guidance authority.
  struct PlanningOverlay: Equatable {
    struct Mark: Equatable {
      let point: NetworkOverviewLayout.Point
      let nameJA: String
    }

    var highlightedRouteIDs: Set<String> = []
    var currentPosition: NetworkOverviewLayout.Point?
    var entranceMark: Mark?
    var exitMark: Mark?
  }

  let layout: NetworkOverviewLayout
  let usesDarkStyle: Bool
  let visibleBottomFraction: Double
  var initialZoom: Double = 1
  var overlay = PlanningOverlay()

  @State private var zoom: Double = 1
  @State private var pan: CGSize = .zero
  @State private var zoomAtGestureStart: Double?
  @State private var panAtGestureStart: CGSize?

  private static let detailZoomThreshold = 1.9
  private static let maximumZoom = 5.0
  private static let doubleTapZoom = 2.4

  private struct Palette {
    let background: Color
    let water: Color
    let casing: Color
    let label: Color
    let junctionLabel: Color
    let entranceFull: Color
    let entranceHalf: Color
    let exitFull: Color
    let exitHalf: Color
  }

  private var palette: Palette {
    usesDarkStyle
      ? Palette(
        background: Color(red: 0.05, green: 0.07, blue: 0.1),
        water: Color(red: 0.06, green: 0.095, blue: 0.145),
        casing: Color(red: 0.03, green: 0.045, blue: 0.07),
        label: Color(red: 0.67, green: 0.72, blue: 0.82),
        junctionLabel: Color(red: 0.88, green: 0.92, blue: 0.98),
        entranceFull: Color(red: 0.22, green: 0.72, blue: 0.44),
        entranceHalf: Color(red: 0.5, green: 0.78, blue: 0.62),
        exitFull: Color(red: 0.82, green: 0.4, blue: 0.34),
        exitHalf: Color(red: 0.88, green: 0.63, blue: 0.59)
      )
      : Palette(
        background: KaidoTheme.paper,
        water: KaidoTheme.surfaceWater,
        casing: Color.white,
        label: Color(red: 0.32, green: 0.38, blue: 0.44),
        junctionLabel: Color(red: 0.1, green: 0.13, blue: 0.18),
        entranceFull: Color(red: 0.11, green: 0.48, blue: 0.28),
        entranceHalf: Color(red: 0.5, green: 0.75, blue: 0.62),
        exitFull: Color(red: 0.69, green: 0.29, blue: 0.24),
        exitHalf: Color(red: 0.87, green: 0.61, blue: 0.58)
      )
  }

  private func routeLineColor(_ routeID: String) -> Color {
    if usesDarkStyle {
      switch routeID {
      case "C1": return Color(red: 1.0, green: 0.71, blue: 0.33)
      case "C2": return Color(red: 0.37, green: 0.82, blue: 0.41)
      case "B": return Color(red: 0.56, green: 0.66, blue: 0.91)
      case "Y": return Color(red: 0.35, green: 0.39, blue: 0.47)
      default: return routeColor(routeID).opacity(0.95)
      }
    }
    return routeColor(routeID)
  }

  var body: some View {
    GeometryReader { geometry in
      let width = geometry.size.width
      let visibleHeight = geometry.size.height * visibleBottomFraction
      let fit = min(
        width / NetworkOverviewLayout.designWidth,
        visibleHeight / NetworkOverviewLayout.designHeight
      )
      Canvas { context, _ in
        draw(
          in: &context,
          fit: fit,
          width: width,
          visibleHeight: visibleHeight
        )
      }
      .background(palette.background)
      .contentShape(Rectangle())
      .simultaneousGesture(
        SpatialTapGesture(count: 2)
          .onEnded { value in
            withAnimation(.easeOut(duration: 0.28)) {
              if zoom > 1.01 {
                zoom = 1
                pan = .zero
              } else {
                setZoom(
                  Self.doubleTapZoom,
                  anchoredAt: value.location,
                  from: (zoom, pan),
                  fit: fit,
                  width: width,
                  visibleHeight: visibleHeight
                )
              }
            }
          }
      )
      .gesture(
        SimultaneousGesture(
          MagnifyGesture()
            .onChanged { value in
              let startZoom = zoomAtGestureStart ?? zoom
              let startPan = panAtGestureStart ?? pan
              zoomAtGestureStart = startZoom
              panAtGestureStart = startPan
              setZoom(
                startZoom * value.magnification,
                anchoredAt: value.startLocation,
                from: (startZoom, startPan),
                fit: fit,
                width: width,
                visibleHeight: visibleHeight
              )
            }
            .onEnded { _ in
              zoomAtGestureStart = nil
              panAtGestureStart = nil
            },
          DragGesture()
            .onChanged { value in
              let start = panAtGestureStart ?? pan
              panAtGestureStart = start
              pan = clampedPan(
                CGSize(
                  width: start.width + value.translation.width,
                  height: start.height + value.translation.height
                ),
                fit: fit,
                zoom: zoom,
                width: width,
                visibleHeight: visibleHeight
              )
            }
            .onEnded { _ in panAtGestureStart = nil }
        )
      )
      .onAppear { zoom = initialZoom }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityIdentifier("whole-shuto-network-map")
    .accessibilityLabel(
      Text("Whole-Shuto network map")
    )
    .accessibilityValue(
      "\(layout.facilityMarks.count) facilities"
    )
  }

  // MARK: - Viewport

  private func contentOffset(
    fit: Double,
    zoom: Double,
    pan: CGSize,
    width: Double,
    visibleHeight: Double
  ) -> CGPoint {
    CGPoint(
      x: (width - NetworkOverviewLayout.designWidth * fit * zoom) / 2
        + pan.width,
      y: (visibleHeight - NetworkOverviewLayout.designHeight * fit * zoom)
        / 2 + pan.height
    )
  }

  /// Applies a zoom anchored at a screen point: the diagram point under the
  /// fingers stays under the fingers.
  private func setZoom(
    _ requested: Double,
    anchoredAt anchor: CGPoint,
    from start: (zoom: Double, pan: CGSize),
    fit: Double,
    width: Double,
    visibleHeight: Double
  ) {
    let newZoom = min(Self.maximumZoom, max(1, requested))
    let startOffset = contentOffset(
      fit: fit,
      zoom: start.zoom,
      pan: start.pan,
      width: width,
      visibleHeight: visibleHeight
    )
    let contentX = (anchor.x - startOffset.x) / (fit * start.zoom)
    let contentY = (anchor.y - startOffset.y) / (fit * start.zoom)
    let centerX =
      (width - NetworkOverviewLayout.designWidth * fit * newZoom) / 2
    let centerY =
      (visibleHeight - NetworkOverviewLayout.designHeight * fit * newZoom)
      / 2
    zoom = newZoom
    pan = clampedPan(
      CGSize(
        width: anchor.x - centerX - contentX * fit * newZoom,
        height: anchor.y - centerY - contentY * fit * newZoom
      ),
      fit: fit,
      zoom: newZoom,
      width: width,
      visibleHeight: visibleHeight
    )
  }

  /// Keeps at least a corner of the diagram on screen in both axes.
  private func clampedPan(
    _ pan: CGSize,
    fit: Double,
    zoom: Double,
    width: Double,
    visibleHeight: Double
  ) -> CGSize {
    let contentWidth = NetworkOverviewLayout.designWidth * fit * zoom
    let contentHeight = NetworkOverviewLayout.designHeight * fit * zoom
    let baseX = (width - contentWidth) / 2
    let baseY = (visibleHeight - contentHeight) / 2
    let margin = 130.0
    var clamped = pan
    clamped.width = min(
      max(clamped.width, -(baseX + contentWidth) + margin),
      width - baseX - margin
    )
    clamped.height = min(
      max(clamped.height, -(baseY + contentHeight) + margin),
      visibleHeight - baseY - margin
    )
    return clamped
  }

  // MARK: - Drawing

  private func draw(
    in context: inout GraphicsContext,
    fit: Double,
    width: Double,
    visibleHeight: Double
  ) {
    let scale = fit * zoom
    let offset = contentOffset(
      fit: fit,
      zoom: zoom,
      pan: pan,
      width: width,
      visibleHeight: visibleHeight
    )
    func point(_ p: NetworkOverviewLayout.Point) -> CGPoint {
      CGPoint(x: offset.x + p.x * scale, y: offset.y + p.y * scale)
    }
    func path(_ points: [NetworkOverviewLayout.Point]) -> Path {
      var path = Path()
      guard let first = points.first else { return path }
      path.move(to: point(first))
      for p in points.dropFirst() {
        path.addLine(to: point(p))
      }
      return path
    }

    // Stylized Tokyo Bay beneath the network, projected through the same
    // fisheye so the Bayshore Route hugs its coast. Presentation only.
    var water = path(Self.bayOutline(projection: layout.projection))
    water.closeSubpath()
    context.fill(water, with: .color(palette.water))

    let highlighted = overlay.highlightedRouteIDs
    func isDimmed(_ routeID: String) -> Bool {
      !highlighted.isEmpty && !highlighted.contains(routeID)
    }

    // Line weights are screen-point sizes that thicken gently with zoom.
    let weightScale = 0.85 + 0.15 * zoom
    func lineWidth(_ routeID: String) -> Double {
      let isTrunk = ["C1", "C2", "B"].contains(routeID)
      return (isTrunk ? 4.6 : 3.2) * weightScale
    }

    // Pseudo-glow, casing, then route colors. With a circuit selected the
    // member routes keep their color and the rest of the network recedes.
    for polyline in layout.polylines where !isDimmed(polyline.routeID) {
      context.stroke(
        path(polyline.points),
        with: .color(routeLineColor(polyline.routeID).opacity(0.11)),
        style: StrokeStyle(
          lineWidth: lineWidth(polyline.routeID) * 2.6,
          lineCap: .round,
          lineJoin: .round
        )
      )
    }
    for polyline in layout.polylines {
      context.stroke(
        path(polyline.points),
        with: .color(palette.casing),
        style: StrokeStyle(
          lineWidth: lineWidth(polyline.routeID) + 2.6,
          lineCap: .round,
          lineJoin: .round
        )
      )
    }
    for polyline in layout.polylines {
      let dimmed = isDimmed(polyline.routeID)
      context.stroke(
        path(polyline.points),
        with: .color(
          dimmed
            ? palette.label.opacity(usesDarkStyle ? 0.28 : 0.34)
            : routeLineColor(polyline.routeID)
        ),
        style: StrokeStyle(
          lineWidth: dimmed
            ? 2.4 * weightScale : lineWidth(polyline.routeID),
          lineCap: .round,
          lineJoin: .round,
          dash: polyline.routeID == "Y" ? [7, 6] : []
        )
      )
    }

    var occupied: [CGRect] = []
    func claim(_ rect: CGRect) -> Bool {
      // The status bar and title float over the top of the canvas; labels
      // placed under them would be unreadable.
      guard rect.minX > -40, rect.maxX < width + 40,
        rect.minY > 96, rect.maxY < visibleHeight + 20
      else { return false }
      guard !occupied.contains(where: { $0.intersects(rect) }) else {
        return false
      }
      occupied.append(rect)
      return true
    }

    // Route badges claim their space first so junction names never sit
    // underneath them.
    for badge in layout.badges {
      if isDimmed(badge.routeID) { continue }
      let center = point(
        NetworkOverviewLayout.Point(x: badge.x, y: badge.y)
      )
      let badgeWidth: Double = badge.label.count > 1 ? 30 : 22
      let frame = CGRect(
        x: center.x - badgeWidth / 2,
        y: center.y - 11,
        width: badgeWidth,
        height: 22
      )
      let shield = Path(roundedRect: frame, cornerRadius: 5)
      context.fill(shield, with: .color(routeLineColor(badge.routeID)))
      context.stroke(
        shield,
        with: .color(palette.casing),
        style: StrokeStyle(lineWidth: 2)
      )
      context.draw(
        Text(badge.label)
          .font(.system(size: 12, weight: .heavy, design: .rounded))
          .foregroundColor(
            usesDarkStyle ? palette.background : Color.white
          ),
        at: CGPoint(x: frame.midX, y: frame.midY),
        anchor: .center
      )
      occupied.append(frame)
    }

    // Junction diamonds always draw; their names claim screen space, so the
    // base zoom stays quiet and detail fills in while zooming.
    var junctionLabels: [(name: String, at: CGPoint)] = []
    for mark in layout.junctionMarks {
      let center = point(NetworkOverviewLayout.Point(x: mark.x, y: mark.y))
      var diamond = Path()
      diamond.move(to: CGPoint(x: center.x, y: center.y - 3.6))
      diamond.addLine(to: CGPoint(x: center.x + 3.6, y: center.y))
      diamond.addLine(to: CGPoint(x: center.x, y: center.y + 3.6))
      diamond.addLine(to: CGPoint(x: center.x - 3.6, y: center.y))
      diamond.closeSubpath()
      context.fill(diamond, with: .color(palette.casing))
      context.stroke(
        diamond,
        with: .color(palette.junctionLabel),
        style: StrokeStyle(lineWidth: 1.2)
      )
      let name = mark.nameJA.replacingOccurrences(of: "JCT・", with: "・")
      let rect = CGRect(
        x: center.x + 6,
        y: center.y - 15,
        width: Double(name.count) * 11 + 14,
        height: 15
      )
      if claim(rect) {
        junctionLabels.append(
          (name, CGPoint(x: center.x + 8, y: center.y - 8))
        )
      }
    }
    context.drawLayer { layer in
      layer.addFilter(
        .shadow(
          color: palette.background.opacity(0.9),
          radius: 2
        )
      )
      for label in junctionLabels {
        layer.draw(
          Text(label.name)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(palette.junctionLabel),
          at: label.at,
          anchor: .leading
        )
      }
    }

    // Facility detail layer past the pinch threshold: every available IC
    // with its half/full directional facts and ETC constraint.
    if zoom >= Self.detailZoomThreshold {
      drawFacilityDetail(
        in: &context,
        point: point,
        claim: claim
      )
    }

    drawPlanningOverlay(in: &context, point: point)
  }

  private func drawFacilityDetail(
    in context: inout GraphicsContext,
    point: (NetworkOverviewLayout.Point) -> CGPoint,
    claim: (CGRect) -> Bool
  ) {
    for mark in layout.facilityMarks {
      let center = point(NetworkOverviewLayout.Point(x: mark.x, y: mark.y))
      let dot = Path(
        ellipseIn: CGRect(
          x: center.x - 2.4, y: center.y - 2.4, width: 4.8, height: 4.8
        )
      )
      context.fill(dot, with: .color(palette.background))
      context.stroke(
        dot,
        with: .color(palette.label),
        style: StrokeStyle(lineWidth: 1.2)
      )
      let name = mark.nameJA
      let textWidth = Double(name.count) * 9.5 + (mark.etcOnly ? 22 : 0)
      let rect = CGRect(
        x: center.x + 5,
        y: center.y - 6,
        width: textWidth + 24,
        height: 12
      )
      guard claim(rect) else { continue }
      var label = Text(name)
        .font(.system(size: 9, weight: .semibold))
        .foregroundColor(palette.label)
      if mark.etcOnly {
        label =
          label
          + Text(" ETC")
          .font(.system(size: 7, weight: .heavy))
          .foregroundColor(Color(red: 0.55, green: 0.45, blue: 0.75))
      }
      context.draw(
        label,
        at: CGPoint(x: center.x + 7, y: center.y),
        anchor: .leading
      )
      // Direction glyph: left triangle entrance, right triangle exit;
      // solid = both directions, faded = one (half facility).
      let glyphX = center.x + 7 + textWidth + 4
      if mark.entrance != .none {
        var triangle = Path()
        triangle.move(to: CGPoint(x: glyphX, y: center.y + 2.8))
        triangle.addLine(to: CGPoint(x: glyphX, y: center.y - 2.8))
        triangle.addLine(to: CGPoint(x: glyphX + 5, y: center.y))
        triangle.closeSubpath()
        context.fill(
          triangle,
          with: .color(
            mark.entrance == .full
              ? palette.entranceFull : palette.entranceHalf
          )
        )
      }
      if mark.exit != .none {
        var triangle = Path()
        triangle.move(to: CGPoint(x: glyphX + 12, y: center.y + 2.8))
        triangle.addLine(to: CGPoint(x: glyphX + 12, y: center.y - 2.8))
        triangle.addLine(to: CGPoint(x: glyphX + 7, y: center.y))
        triangle.closeSubpath()
        context.fill(
          triangle,
          with: .color(
            mark.exit == .full ? palette.exitFull : palette.exitHalf
          )
        )
      }
    }
  }

  private func drawPlanningOverlay(
    in context: inout GraphicsContext,
    point: (NetworkOverviewLayout.Point) -> CGPoint
  ) {
    func drawMark(
      _ mark: PlanningOverlay.Mark,
      glyph: String,
      color: Color
    ) {
      let center = point(mark.point)
      let disc = Path(
        ellipseIn: CGRect(
          x: center.x - 9, y: center.y - 9, width: 18, height: 18
        )
      )
      context.fill(disc, with: .color(color))
      context.stroke(
        disc,
        with: .color(palette.background),
        style: StrokeStyle(lineWidth: 2)
      )
      context.draw(
        Text(glyph)
          .font(.system(size: 10, weight: .heavy))
          .foregroundColor(palette.background),
        at: center,
        anchor: .center
      )
      let labelFrame = CGRect(
        x: center.x + 12,
        y: center.y - 9,
        width: Double(mark.nameJA.count) * 13 + 12,
        height: 18
      )
      context.fill(
        Path(roundedRect: labelFrame, cornerRadius: 5),
        with: .color(palette.background.opacity(0.85))
      )
      context.draw(
        Text(mark.nameJA)
          .font(.system(size: 12, weight: .bold))
          .foregroundColor(palette.junctionLabel),
        at: CGPoint(x: labelFrame.minX + 6, y: labelFrame.midY),
        anchor: .leading
      )
    }

    if let entrance = overlay.entranceMark {
      drawMark(entrance, glyph: "入", color: KaidoTheme.positionCyan)
    }
    if let exit = overlay.exitMark {
      drawMark(exit, glyph: "出", color: KaidoTheme.evidenceCoral)
    }
    if let position = overlay.currentPosition {
      let center = point(position)
      context.fill(
        Path(
          ellipseIn: CGRect(
            x: center.x - 14, y: center.y - 14, width: 28, height: 28
          )
        ),
        with: .color(KaidoTheme.positionCyan.opacity(0.18))
      )
      let core = Path(
        ellipseIn: CGRect(
          x: center.x - 6, y: center.y - 6, width: 12, height: 12
        )
      )
      context.fill(core, with: .color(KaidoTheme.positionCyan))
      context.stroke(
        core,
        with: .color(.white),
        style: StrokeStyle(lineWidth: 2.4)
      )
    }
  }

  // MARK: - Water

  /// Coarse Tokyo Bay coastline, land side from Isogo up around the bay to
  /// Ichikawa, closed through open water. Deliberately stylized context —
  /// never a road, toll, or navigation claim.
  private static let bayCoast: [(Double, Double)] = [
    (35.395, 139.615),
    (35.415, 139.640),
    (35.440, 139.665),
    (35.455, 139.685),
    (35.475, 139.710),
    (35.495, 139.745),
    (35.520, 139.775),
    (35.545, 139.795),
    (35.565, 139.785),
    (35.585, 139.770),
    (35.605, 139.775),
    (35.625, 139.780),
    (35.635, 139.795),
    (35.645, 139.815),
    (35.640, 139.835),
    (35.640, 139.860),
    (35.650, 139.895),
    (35.660, 139.930),
    (35.590, 139.925),
    (35.490, 139.845),
    (35.410, 139.730),
    (35.375, 139.650),
  ]

  private static func bayOutline(
    projection: NetworkOverviewLayout.Projection
  ) -> [NetworkOverviewLayout.Point] {
    var points = bayCoast.map {
      projection.project(
        RouteTrackMapLayout.GeoPoint(latitude: $0.0, longitude: $0.1)
      )
    }
    // Two rounds of corner cutting on the closed outline so the shore
    // reads as coastline instead of a polygon.
    for _ in 0..<2 {
      var smooth: [NetworkOverviewLayout.Point] = []
      smooth.reserveCapacity(points.count * 2)
      for index in points.indices {
        let a = points[index]
        let b = points[(index + 1) % points.count]
        smooth.append(
          NetworkOverviewLayout.Point(
            x: a.x * 0.75 + b.x * 0.25,
            y: a.y * 0.75 + b.y * 0.25
          )
        )
        smooth.append(
          NetworkOverviewLayout.Point(
            x: a.x * 0.25 + b.x * 0.75,
            y: a.y * 0.25 + b.y * 0.75
          )
        )
      }
      points = smooth
    }
    return points
  }
}
