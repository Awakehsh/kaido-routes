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
/// context projection in the track-map visual language. Pinch past the detail
/// threshold to reveal every available IC with its half/full directional
/// facts and ETC constraint.
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
  @State private var zoomAtGestureStart: Double?
  @State private var pan: CGSize = .zero
  @State private var panAtGestureStart: CGSize?

  private static let detailZoomThreshold = 1.9

  private struct Palette {
    let background: Color
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
        casing: Color(red: 0.85, green: 0.87, blue: 0.9),
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
      let visibleHeight = geometry.size.height * visibleBottomFraction
      let fit = min(
        geometry.size.width / NetworkOverviewLayout.designWidth,
        visibleHeight / NetworkOverviewLayout.designHeight
      )
      Canvas { context, _ in
        let scale = fit * zoom
        let baseX =
          (geometry.size.width
            - NetworkOverviewLayout.designWidth * scale) / 2
        let baseY =
          (visibleHeight
            - NetworkOverviewLayout.designHeight * scale) / 2
        context.translateBy(
          x: baseX + pan.width,
          y: baseY + pan.height
        )
        context.scaleBy(x: scale, y: scale)
        draw(in: &context, zoom: zoom)
      }
      .background(palette.background)
      .contentShape(Rectangle())
      .gesture(
        SimultaneousGesture(
          MagnificationGesture()
            .onChanged { value in
              let start = zoomAtGestureStart ?? zoom
              zoomAtGestureStart = start
              zoom = min(4.5, max(1, start * value))
            }
            .onEnded { _ in zoomAtGestureStart = nil },
          DragGesture()
            .onChanged { value in
              let start = panAtGestureStart ?? pan
              panAtGestureStart = start
              pan = CGSize(
                width: start.width + value.translation.width,
                height: start.height + value.translation.height
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

  private func draw(in context: inout GraphicsContext, zoom: Double) {
    let highlighted = overlay.highlightedRouteIDs
    func isDimmed(_ routeID: String) -> Bool {
      !highlighted.isEmpty && !highlighted.contains(routeID)
    }

    // Pseudo-glow, casing, then route colors. With a circuit selected the
    // member routes keep their color and the rest of the network recedes.
    for polyline in layout.polylines where !isDimmed(polyline.routeID) {
      context.stroke(
        path(polyline.points),
        with: .color(routeLineColor(polyline.routeID).opacity(0.12)),
        style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round)
      )
    }
    for polyline in layout.polylines {
      context.stroke(
        path(polyline.points),
        with: .color(palette.casing),
        style: StrokeStyle(lineWidth: 7.2, lineCap: .round, lineJoin: .round)
      )
    }
    for polyline in layout.polylines {
      let isTrunk = ["C1", "C2", "B"].contains(polyline.routeID)
      let dimmed = isDimmed(polyline.routeID)
      context.stroke(
        path(polyline.points),
        with: .color(
          dimmed
            ? palette.label.opacity(usesDarkStyle ? 0.28 : 0.34)
            : routeLineColor(polyline.routeID)
        ),
        style: StrokeStyle(
          lineWidth: dimmed ? 2.6 : isTrunk ? 4.4 : 3.4,
          lineCap: .round,
          lineJoin: .round,
          dash: polyline.routeID == "Y" ? [7, 6] : []
        )
      )
    }

    var occupied: [CGRect] = []
    func claim(_ rect: CGRect) -> Bool {
      guard !occupied.contains(where: { $0.intersects(rect) }) else {
        return false
      }
      occupied.append(rect)
      return true
    }

    // Junction diamonds and names lead the label priority.
    for mark in layout.junctionMarks {
      var diamond = Path()
      diamond.move(to: CGPoint(x: 0, y: -3.8))
      diamond.addLine(to: CGPoint(x: 3.8, y: 0))
      diamond.addLine(to: CGPoint(x: 0, y: 3.8))
      diamond.addLine(to: CGPoint(x: -3.8, y: 0))
      diamond.closeSubpath()
      context.drawLayer { layer in
        layer.translateBy(x: mark.x, y: mark.y)
        layer.fill(diamond, with: .color(palette.casing))
        layer.stroke(
          diamond,
          with: .color(palette.junctionLabel),
          style: StrokeStyle(lineWidth: 1.3)
        )
      }
      let name = mark.nameJA.replacingOccurrences(of: "JCT・", with: "・")
      let rect = CGRect(
        x: mark.x + 6,
        y: mark.y - 16,
        width: Double(name.count) * 12 + 8,
        height: 14
      )
      if claim(rect) {
        context.draw(
          Text(name)
            .font(.system(size: 11.5, weight: .bold))
            .foregroundColor(palette.junctionLabel),
          at: CGPoint(x: mark.x + 8, y: mark.y - 9),
          anchor: .leading
        )
      }
    }

    // Route badges.
    for badge in layout.badges {
      if isDimmed(badge.routeID) { continue }
      let width: Double = badge.label.count > 1 ? 34 : 26
      let frame = CGRect(
        x: badge.x - width / 2,
        y: badge.y - 10.5,
        width: width,
        height: 21
      )
      let capsule = Path(roundedRect: frame, cornerRadius: 6)
      context.fill(capsule, with: .color(routeLineColor(badge.routeID)))
      context.stroke(
        capsule,
        with: .color(palette.background),
        style: StrokeStyle(lineWidth: 2)
      )
      context.draw(
        Text(badge.label)
          .font(.system(size: 12, weight: .heavy, design: .rounded))
          .foregroundColor(palette.background),
        at: CGPoint(x: badge.x, y: badge.y),
        anchor: .center
      )
      occupied.append(frame)
    }

    // Facility detail layer past the pinch threshold: every available IC
    // with its half/full directional facts and ETC constraint.
    if zoom >= Self.detailZoomThreshold {
      drawFacilityDetail(in: &context, claim: claim)
    }

    drawPlanningOverlay(in: &context)
  }

  private func drawFacilityDetail(
    in context: inout GraphicsContext,
    claim: (CGRect) -> Bool
  ) {
    for mark in layout.facilityMarks {
      let dot = Path(
        ellipseIn: CGRect(x: mark.x - 2.4, y: mark.y - 2.4, width: 4.8, height: 4.8)
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
        x: mark.x + 5,
        y: mark.y - 6,
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
        at: CGPoint(x: mark.x + 7, y: mark.y),
        anchor: .leading
      )
      // Direction glyph: left triangle entrance, right triangle exit;
      // solid = both directions, faded = one (half facility).
      let glyphX = mark.x + 7 + textWidth + 4
      if mark.entrance != .none {
        var triangle = Path()
        triangle.move(to: CGPoint(x: glyphX, y: mark.y + 2.8))
        triangle.addLine(to: CGPoint(x: glyphX, y: mark.y - 2.8))
        triangle.addLine(to: CGPoint(x: glyphX + 5, y: mark.y))
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
        triangle.move(to: CGPoint(x: glyphX + 12, y: mark.y + 2.8))
        triangle.addLine(to: CGPoint(x: glyphX + 12, y: mark.y - 2.8))
        triangle.addLine(to: CGPoint(x: glyphX + 7, y: mark.y))
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

  private func drawPlanningOverlay(in context: inout GraphicsContext) {
    func drawMark(
      _ mark: PlanningOverlay.Mark,
      glyph: String,
      color: Color
    ) {
      let center = CGPoint(x: mark.point.x, y: mark.point.y)
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
      let center = CGPoint(x: position.x, y: position.y)
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

  private func path(
    _ points: [NetworkOverviewLayout.Point]
  ) -> Path {
    var path = Path()
    guard let first = points.first else { return path }
    path.move(to: CGPoint(x: first.x, y: first.y))
    for point in points.dropFirst() {
      path.addLine(to: CGPoint(x: point.x, y: point.y))
    }
    return path
  }
}
