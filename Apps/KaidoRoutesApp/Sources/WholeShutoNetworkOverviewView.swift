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
    let parkingAreas = database.parkingAreas.map {
      NetworkOverviewLayout.ParkingAreaInput(
        id: $0.parkingAreaID,
        nameJA: $0.nameJA,
        baseNameJA: $0.baseNameJA,
        routeID: $0.routeID,
        directionJA: $0.directionJA,
        coordinate: RouteTrackMapLayout.GeoPoint(
          latitude: $0.coordinate.latitude,
          longitude: $0.coordinate.longitude
        )
      )
    }
    let layout = NetworkOverviewLayout.make(
      ways: ways,
      facilities: facilities,
      junctions: junctions,
      parkingAreas: parkingAreas,
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
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale

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
  let visibleBottomFraction: Double
  var initialZoom: Double = 1
  var overlay = PlanningOverlay()
  /// Top strip where labels never place, covering floating UI (the portrait
  /// title bar); landscape hosts controls in a side column and needs almost
  /// none.
  var labelTopInset: Double = 96

  @State private var zoom: Double = 1
  @State private var pan: CGSize = .zero
  @State private var zoomAtGestureStart: Double?
  @State private var panAtGestureStart: CGSize?

  private static let detailZoomThreshold = 1.9
  private static let maximumZoom = 5.0
  private static let doubleTapZoom = 2.4

  /// The single midnight palette: near-black blue asphalt, ink bay, receded
  /// blue rest-of-network, and plated labels. The diagram renders identically
  /// day and night — the product's visual identity is the lit expressway.
  private enum Midnight {
    static let background = Color(red: 0.031, green: 0.043, blue: 0.078)
    static let water = Color(red: 0.039, green: 0.067, blue: 0.133)
    static let casing = Color(red: 0.075, green: 0.1, blue: 0.16)
    static let restCore = Color(red: 0.173, green: 0.227, blue: 0.36)
    static let leader = Color(red: 0.192, green: 0.251, blue: 0.369)
    static let plate = Color(red: 0.02, green: 0.031, blue: 0.063)
    static let label = Color(red: 0.62, green: 0.68, blue: 0.8)
    static let junctionLabel = Color(red: 0.79, green: 0.84, blue: 0.95)
    static let entranceFull = Color(red: 0.22, green: 0.72, blue: 0.44)
    static let entranceHalf = Color(red: 0.5, green: 0.78, blue: 0.62)
    static let exitFull = Color(red: 0.82, green: 0.4, blue: 0.34)
    static let exitHalf = Color(red: 0.88, green: 0.63, blue: 0.59)
    static let pa = Color(red: 0.42, green: 0.82, blue: 0.58)
    static let place = Color(red: 0.93, green: 0.82, blue: 0.55)
  }

  private func routeLineColor(_ routeID: String) -> Color {
    routeColor(routeID)
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
      .background(Midnight.background)
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
      copy.resolve(
        japanese: "首都高全体路線図",
        simplifiedChinese: "首都高全网线路图",
        english: "Whole-Shuto network map"
      )
    )
    .accessibilityValue(
      {
        let count = copy.resolve(
          japanese: "\(layout.facilityMarks.count)施設",
          simplifiedChinese: "\(layout.facilityMarks.count)个设施",
          english: "\(layout.facilityMarks.count) facilities"
        )
        let parking = copy.resolve(
          japanese: "\(layout.parkingAreaMarks.count)PA",
          simplifiedChinese: "\(layout.parkingAreaMarks.count)个PA",
          english: "\(layout.parkingAreaMarks.count) PAs"
        )
        let notable = layout.parkingAreaMarks.filter(\.notable)
          .map(\.shortNameJA)
        let places = layout.placeMarks.map {
          $0.name(for: interfaceLocale)
        }
        let named = (notable + places).joined(separator: " ")
        var value = "\(count) · \(parking) · \(named)"
        let highlighted = overlay.highlightedRouteIDs.sorted()
        if !highlighted.isEmpty {
          value += " · " + highlighted.joined(separator: " ")
        }
        return value
      }()
    )
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
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
    context.fill(water, with: .color(Midnight.water))

    let highlighted = overlay.highlightedRouteIDs
    func isDimmed(_ routeID: String) -> Bool {
      !highlighted.contains(routeID)
    }
    func junctionIsOnSelection(_ mark: NetworkOverviewLayout.JunctionMark)
      -> Bool
    {
      !highlighted.isEmpty && !mark.routeIDs.isDisjoint(with: highlighted)
    }

    // Line weights are screen-point sizes that thicken gently with zoom.
    let weightScale = 0.85 + 0.15 * zoom
    func lineWidth(_ routeID: String) -> Double {
      let isTrunk = ["C1", "C2", "B"].contains(routeID)
      return (isTrunk ? 4.6 : 3.2) * weightScale
    }

    // Rest of the network first: dark casing plus a receded blue core.
    // A selected circuit (or planned route) keeps rainbow color on its
    // members only; browsing with no selection leaves the whole net receded.
    for polyline in layout.polylines {
      context.stroke(
        path(polyline.points),
        with: .color(Midnight.casing),
        style: StrokeStyle(
          lineWidth: lineWidth(polyline.routeID) + 2.8,
          lineCap: .round,
          lineJoin: .round
        )
      )
    }
    for polyline in layout.polylines where isDimmed(polyline.routeID) {
      context.stroke(
        path(polyline.points),
        with: .color(Midnight.restCore),
        style: StrokeStyle(
          lineWidth: 2.2 * weightScale,
          lineCap: .round,
          lineJoin: .round
        )
      )
    }

    // Lit members keep each route's own color, slightly thicker than the
    // receded net. No neon halo and no white-hot core — those read as a
    // highlighter, not a selected carriageway.
    let litLines = layout.polylines.filter { !isDimmed($0.routeID) }
    for polyline in litLines {
      let color = routeLineColor(polyline.routeID)
      context.stroke(
        path(polyline.points),
        with: .color(color.opacity(0.28)),
        style: StrokeStyle(
          lineWidth: lineWidth(polyline.routeID) + 3.2,
          lineCap: .round,
          lineJoin: .round
        )
      )
      context.stroke(
        path(polyline.points),
        with: .color(color),
        style: StrokeStyle(
          lineWidth: lineWidth(polyline.routeID) + 0.8,
          lineCap: .round,
          lineJoin: .round,
          dash: polyline.routeID == "Y" ? [7, 6] : []
        )
      )
    }

    var occupied: [CGRect] = []
    func claim(_ rect: CGRect) -> Bool {
      // Labels never place under floating UI at the top of the canvas.
      guard rect.minX > -40, rect.maxX < width + 40,
        rect.minY > labelTopInset, rect.maxY < visibleHeight + 20
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
      context.fill(shield, with: .color(Midnight.plate))
      context.stroke(
        shield,
        with: .color(routeLineColor(badge.routeID)),
        style: StrokeStyle(lineWidth: 1.6)
      )
      context.draw(
        Text(badge.label)
          .font(.system(size: 12, weight: .heavy, design: .rounded))
          .foregroundColor(routeLineColor(badge.routeID)),
        at: CGPoint(x: frame.midX, y: frame.midY),
        anchor: .center
      )
      occupied.append(frame)
    }

    // Planning marks claim their space ahead of junction names: the derived
    // pairing and the driver's position always win the label fight.
    for mark in [overlay.entranceMark, overlay.exitMark].compactMap({ $0 }) {
      let center = point(mark.point)
      occupied.append(
        CGRect(
          x: center.x - 14,
          y: center.y - 16,
          width: Double(mark.nameJA.count) * 13 + 58,
          height: 34
        )
      )
    }
    if let position = overlay.currentPosition {
      let center = point(position)
      occupied.append(
        CGRect(x: center.x - 16, y: center.y - 16, width: 32, height: 32)
      )
    }

    func onSelection(_ routeIDs: Set<String>) -> Bool {
      highlighted.isEmpty || !routeIDs.isDisjoint(with: highlighted)
    }

    func plateName(
      _ name: String,
      at center: CGPoint,
      color: Color,
      emphasized: Bool,
      offset: CGSize = CGSize(width: 8, height: -26),
      context: inout GraphicsContext
    ) {
      let rect = CGRect(
        x: center.x + offset.width,
        y: center.y + offset.height,
        width: Double(name.count) * 11 + 16,
        height: 20
      )
      guard claim(rect) else { return }
      var leader = Path()
      leader.move(to: CGPoint(x: center.x, y: center.y))
      leader.addLine(to: CGPoint(x: rect.minX + 4, y: rect.maxY - 2))
      context.stroke(
        leader,
        with: .color(Midnight.leader),
        style: StrokeStyle(lineWidth: 1.2)
      )
      context.fill(
        Path(roundedRect: rect, cornerRadius: 6),
        with: .color(Midnight.plate.opacity(emphasized ? 0.85 : 0.62))
      )
      context.draw(
        Text(name)
          .font(.system(size: 11, weight: .bold))
          .foregroundColor(emphasized ? color : Midnight.label),
        at: CGPoint(x: rect.minX + 8, y: rect.midY),
        anchor: .leading
      )
    }

    // Classic places use silhouettes on the small diagram; names join
    // once pinched in. Icons claim space before junction plates.
    let showPlaceNames = zoom >= Self.detailZoomThreshold
    for mark in layout.placeMarks {
      let center = point(NetworkOverviewLayout.Point(x: mark.x, y: mark.y))
      let emphasized = onSelection(mark.routeIDs)
      occupied.append(
        CGRect(x: center.x - 13, y: center.y - 15, width: 26, height: 30)
      )
      NetworkOverviewPlaceGlyph.draw(
        mark.icon,
        at: center,
        color: emphasized ? Midnight.place : Midnight.label,
        plate: Midnight.plate.opacity(emphasized ? 0.9 : 0.7),
        context: &context
      )
      if showPlaceNames {
        plateName(
          mark.name(for: interfaceLocale),
          at: center,
          color: Midnight.place,
          emphasized: emphasized,
          offset: CGSize(width: 16, height: -10),
          context: &context
        )
      }
    }

    let showEveryParkingArea = zoom >= Self.detailZoomThreshold
    let parkingAreasToLabel =
      showEveryParkingArea
      ? layout.parkingAreaMarks
      : layout.parkingAreaMarks.filter(\.notable)
    for mark in parkingAreasToLabel {
      let center = point(NetworkOverviewLayout.Point(x: mark.x, y: mark.y))
      let emphasized = onSelection(mark.routeIDs)
      let square = Path(
        roundedRect: CGRect(
          x: center.x - 3.2, y: center.y - 3.2, width: 6.4, height: 6.4
        ),
        cornerRadius: 1.4
      )
      context.fill(square, with: .color(Midnight.plate))
      context.stroke(
        square,
        with: .color(emphasized ? Midnight.pa : Midnight.label),
        style: StrokeStyle(lineWidth: 1.3)
      )
      let name: String
      if showEveryParkingArea, let direction = mark.directionJA,
        !direction.isEmpty
      {
        name = "\(mark.shortNameJA)（\(direction)）"
      } else {
        name = mark.shortNameJA
      }
      plateName(
        name,
        at: center,
        color: Midnight.pa,
        emphasized: emphasized,
        context: &context
      )
    }

    // Junction diamonds and names always draw. Collision still thins the
    // plates at low zoom; a selected circuit only changes emphasis, it
    // never hides names.
    var junctionLabels: [(name: String, at: CGPoint, emphasized: Bool)] = []
    for mark in layout.junctionMarks {
      let center = point(NetworkOverviewLayout.Point(x: mark.x, y: mark.y))
      let emphasized =
        highlighted.isEmpty || junctionIsOnSelection(mark)
      var diamond = Path()
      diamond.move(to: CGPoint(x: center.x, y: center.y - 3.6))
      diamond.addLine(to: CGPoint(x: center.x + 3.6, y: center.y))
      diamond.addLine(to: CGPoint(x: center.x, y: center.y + 3.6))
      diamond.addLine(to: CGPoint(x: center.x - 3.6, y: center.y))
      diamond.closeSubpath()
      context.fill(diamond, with: .color(Midnight.plate))
      context.stroke(
        diamond,
        with: .color(
          emphasized ? Midnight.junctionLabel : Midnight.label
        ),
        style: StrokeStyle(lineWidth: 1.2)
      )
      let name = mark.nameJA.replacingOccurrences(of: "JCT・", with: "・")
      let rect = CGRect(
        x: center.x + 8,
        y: center.y - 26,
        width: Double(name.count) * 11 + 16,
        height: 20
      )
      if claim(rect) {
        junctionLabels.append(
          (name, CGPoint(x: center.x + 8, y: center.y - 26), emphasized)
        )
      }
    }
    // Names ride on small plates with a short leader back to the diamond,
    // so text never fights the route lines underneath.
    for label in junctionLabels {
      let plate = CGRect(
        x: label.at.x,
        y: label.at.y,
        width: Double(label.name.count) * 11 + 16,
        height: 20
      )
      var leader = Path()
      leader.move(to: CGPoint(x: label.at.x - 8, y: label.at.y + 26))
      leader.addLine(to: CGPoint(x: plate.minX + 4, y: plate.maxY - 2))
      context.stroke(
        leader,
        with: .color(Midnight.leader),
        style: StrokeStyle(lineWidth: 1.2)
      )
      context.fill(
        Path(roundedRect: plate, cornerRadius: 6),
        with: .color(Midnight.plate.opacity(label.emphasized ? 0.85 : 0.62))
      )
      context.draw(
        Text(label.name)
          .font(.system(size: 11, weight: .bold))
          .foregroundColor(
            label.emphasized ? Midnight.junctionLabel : Midnight.label
          ),
        at: CGPoint(x: plate.minX + 8, y: plate.midY),
        anchor: .leading
      )
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
      context.fill(dot, with: .color(Midnight.background))
      context.stroke(
        dot,
        with: .color(Midnight.label),
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
        .foregroundColor(Midnight.label)
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
              ? Midnight.entranceFull : Midnight.entranceHalf
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
            mark.exit == .full ? Midnight.exitFull : Midnight.exitHalf
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
        with: .color(Midnight.background),
        style: StrokeStyle(lineWidth: 2)
      )
      context.draw(
        Text(glyph)
          .font(.system(size: 10, weight: .heavy))
          .foregroundColor(Midnight.background),
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
        with: .color(Midnight.plate.opacity(0.85))
      )
      context.draw(
        Text(mark.nameJA)
          .font(.system(size: 12, weight: .bold))
          .foregroundColor(Midnight.junctionLabel),
        at: CGPoint(x: labelFrame.minX + 6, y: labelFrame.midY),
        anchor: .leading
      )
    }

    if let entrance = overlay.entranceMark {
      // Circuit-sheet start grid: a checkered bar across the carriageway
      // just ahead of the entrance, oriented along the nearest member
      // route segment. Pure presentation, no competitive semantics.
      if !overlay.highlightedRouteIDs.isEmpty,
        let angle = nearestHighlightedSegmentAngle(to: entrance.point)
      {
        let center = point(entrance.point)
        context.drawLayer { layer in
          layer.translateBy(
            x: center.x + cos(angle) * 20,
            y: center.y + sin(angle) * 20
          )
          layer.rotate(by: Angle(radians: angle))
          for column in 0..<2 {
            for row in 0..<6 {
              let cell = CGRect(
                x: Double(column) * 5 - 5,
                y: Double(row) * 5 - 15,
                width: 5,
                height: 5
              )
              layer.fill(
                Path(cell),
                with: .color(
                  (column + row) % 2 == 0
                    ? Color.white.opacity(0.92)
                    : Midnight.plate
                )
              )
            }
          }
        }
      }
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

  /// Direction of the nearest highlighted-route segment to a design-space
  /// point, used to orient the entrance start grid across the carriageway.
  private func nearestHighlightedSegmentAngle(
    to target: NetworkOverviewLayout.Point
  ) -> Double? {
    var best: (distance: Double, angle: Double)?
    for polyline in layout.polylines
    where overlay.highlightedRouteIDs.contains(polyline.routeID) {
      let points = polyline.points
      guard points.count > 1 else { continue }
      for index in stride(from: 0, to: points.count - 1, by: 2) {
        let a = points[index]
        let b = points[min(index + 2, points.count - 1)]
        let midX = (a.x + b.x) / 2
        let midY = (a.y + b.y) / 2
        let distance =
          (midX - target.x) * (midX - target.x)
          + (midY - target.y) * (midY - target.y)
        if best == nil || distance < best!.distance {
          best = (distance, atan2(b.y - a.y, b.x - a.x))
        }
      }
    }
    return best?.angle
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

/// Screen-space silhouettes for the classic places on the network diagram.
/// Drawn in a 20×24 box so Tokyo Tower and Skytree stay distinct at the
/// unzoomed mark size.
private enum NetworkOverviewPlaceGlyph {
  static func draw(
    _ icon: NetworkOverviewLayout.PlaceIcon,
    at center: CGPoint,
    color: Color,
    plate: Color,
    context: inout GraphicsContext
  ) {
    let box = CGRect(
      x: center.x - 10,
      y: center.y - 12,
      width: 20,
      height: 24
    )
    context.fill(
      Path(roundedRect: box.insetBy(dx: -3, dy: -2), cornerRadius: 7),
      with: .color(plate)
    )
    context.stroke(
      Path(roundedRect: box.insetBy(dx: -3, dy: -2), cornerRadius: 7),
      with: .color(color.opacity(0.45)),
      style: StrokeStyle(lineWidth: 1)
    )

    func p(_ x: Double, _ y: Double) -> CGPoint {
      CGPoint(
        x: box.minX + x / 20 * box.width,
        y: box.minY + y / 24 * box.height
      )
    }

    switch icon {
    case .tokyoTower:
      var tower = Path()
      tower.move(to: p(10, 0.4))
      tower.addLine(to: p(10.9, 3.1))
      tower.addLine(to: p(13.4, 3.1))
      tower.addLine(to: p(13.4, 5.3))
      tower.addLine(to: p(11.5, 5.3))
      tower.addLine(to: p(15.6, 12.2))
      tower.addLine(to: p(16.8, 12.2))
      tower.addLine(to: p(16.8, 14.5))
      tower.addLine(to: p(18.6, 23.4))
      tower.addLine(to: p(1.4, 23.4))
      tower.addLine(to: p(3.2, 14.5))
      tower.addLine(to: p(3.2, 12.2))
      tower.addLine(to: p(8.5, 5.3))
      tower.addLine(to: p(6.6, 5.3))
      tower.addLine(to: p(6.6, 3.1))
      tower.addLine(to: p(9.1, 3.1))
      tower.closeSubpath()
      context.fill(tower, with: .color(color))

    case .tokyoSkytree:
      var tree = Path()
      tree.move(to: p(10, 0.3))
      tree.addLine(to: p(11.0, 4.2))
      tree.addQuadCurve(to: p(11.2, 7.4), control: p(13.6, 5.6))
      tree.addLine(to: p(11.0, 11.2))
      tree.addQuadCurve(to: p(11.6, 15.4), control: p(14.8, 13.2))
      tree.addLine(to: p(12.4, 19.6))
      tree.addLine(to: p(14.8, 23.5))
      tree.addLine(to: p(5.2, 23.5))
      tree.addLine(to: p(7.6, 19.6))
      tree.addLine(to: p(8.4, 15.4))
      tree.addQuadCurve(to: p(9.0, 11.2), control: p(5.2, 13.2))
      tree.addLine(to: p(8.8, 7.4))
      tree.addQuadCurve(to: p(9.0, 4.2), control: p(6.4, 5.6))
      tree.closeSubpath()
      context.fill(tree, with: .color(color))

    case .airplane:
      var plane = Path()
      plane.move(to: p(1.6, 13.2))
      plane.addLine(to: p(8.2, 12.4))
      plane.addLine(to: p(11.4, 4.2))
      plane.addLine(to: p(13.2, 4.2))
      plane.addLine(to: p(12.4, 12.2))
      plane.addLine(to: p(16.4, 11.8))
      plane.addLine(to: p(18.6, 8.6))
      plane.addLine(to: p(19.4, 9.2))
      plane.addLine(to: p(17.6, 13.4))
      plane.addLine(to: p(19.4, 15.2))
      plane.addLine(to: p(18.4, 16.0))
      plane.addLine(to: p(16.2, 14.6))
      plane.addLine(to: p(12.2, 14.8))
      plane.addLine(to: p(13.6, 20.8))
      plane.addLine(to: p(11.8, 20.8))
      plane.addLine(to: p(10.0, 14.8))
      plane.addLine(to: p(6.2, 15.2))
      plane.addQuadCurve(to: p(1.6, 13.2), control: p(1.2, 14.6))
      plane.closeSubpath()
      context.fill(plane, with: .color(color))

    case .ferrisWheel:
      let wheelOrigin = p(3.2, 1.6)
      let wheelExtent = p(16.8, 15.2)
      let wheel = Path(
        ellipseIn: CGRect(
          x: wheelOrigin.x,
          y: wheelOrigin.y,
          width: wheelExtent.x - wheelOrigin.x,
          height: wheelExtent.y - wheelOrigin.y
        )
      )
      context.stroke(
        wheel,
        with: .color(color),
        style: StrokeStyle(lineWidth: 1.5)
      )
      let hub = CGPoint(x: p(10, 8.4).x, y: p(10, 8.4).y)
      for index in 0..<6 {
        let angle = Double(index) * .pi / 3
        var spoke = Path()
        spoke.move(to: hub)
        spoke.addLine(
          to: CGPoint(
            x: hub.x + cos(angle) * (p(16.4, 8.4).x - hub.x),
            y: hub.y + sin(angle) * (p(16.4, 8.4).x - hub.x)
          )
        )
        context.stroke(
          spoke,
          with: .color(color),
          style: StrokeStyle(lineWidth: 1)
        )
      }
      var legs = Path()
      legs.move(to: p(8.4, 14.4))
      legs.addLine(to: p(5.2, 23.2))
      legs.move(to: p(11.6, 14.4))
      legs.addLine(to: p(14.8, 23.2))
      context.stroke(
        legs,
        with: .color(color),
        style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
      )

    case .suspensionBridge:
      var deck = Path()
      deck.move(to: p(0.8, 18.4))
      deck.addLine(to: p(19.2, 18.4))
      context.stroke(
        deck,
        with: .color(color),
        style: StrokeStyle(lineWidth: 1.7, lineCap: .round)
      )
      var towers = Path()
      towers.addRect(
        CGRect(
          x: p(5.2, 5.2).x,
          y: p(5.2, 5.2).y,
          width: p(6.6, 5.2).x - p(5.2, 5.2).x,
          height: p(6.6, 18.4).y - p(5.2, 5.2).y
        )
      )
      towers.addRect(
        CGRect(
          x: p(13.4, 5.2).x,
          y: p(13.4, 5.2).y,
          width: p(14.8, 5.2).x - p(13.4, 5.2).x,
          height: p(14.8, 18.4).y - p(13.4, 5.2).y
        )
      )
      context.fill(towers, with: .color(color))
      var cables = Path()
      cables.move(to: p(1.2, 18.4))
      cables.addQuadCurve(to: p(5.9, 5.2), control: p(3.0, 9.5))
      cables.addQuadCurve(to: p(14.1, 5.2), control: p(10.0, 1.4))
      cables.addQuadCurve(to: p(18.8, 18.4), control: p(17.0, 9.5))
      context.stroke(
        cables,
        with: .color(color),
        style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
      )

    case .cableStayedBridge:
      var deck = Path()
      deck.move(to: p(0.8, 18.6))
      deck.addLine(to: p(19.2, 18.6))
      context.stroke(
        deck,
        with: .color(color),
        style: StrokeStyle(lineWidth: 1.7, lineCap: .round)
      )
      var towers = Path()
      towers.addRect(
        CGRect(
          x: p(6.4, 3.6).x,
          y: p(6.4, 3.6).y,
          width: p(7.6, 3.6).x - p(6.4, 3.6).x,
          height: p(7.6, 18.6).y - p(6.4, 3.6).y
        )
      )
      towers.addRect(
        CGRect(
          x: p(12.4, 3.6).x,
          y: p(12.4, 3.6).y,
          width: p(13.6, 3.6).x - p(12.4, 3.6).x,
          height: p(13.6, 18.6).y - p(12.4, 3.6).y
        )
      )
      context.fill(towers, with: .color(color))
      var stays = Path()
      for t in [3.0, 7.5, 11.5, 16.5] {
        stays.move(to: p(7.0, 4.2))
        stays.addLine(to: p(t, 18.6))
        stays.move(to: p(13.0, 4.2))
        stays.addLine(to: p(20.0 - t, 18.6))
      }
      context.stroke(
        stays,
        with: .color(color),
        style: StrokeStyle(lineWidth: 0.9)
      )

    case .harpBridge:
      var deck = Path()
      deck.move(to: p(0.8, 19.0))
      deck.addLine(to: p(19.2, 19.0))
      context.stroke(
        deck,
        with: .color(color),
        style: StrokeStyle(lineWidth: 1.7, lineCap: .round)
      )
      var towers = Path()
      towers.addRect(
        CGRect(
          x: p(4.6, 2.4).x,
          y: p(4.6, 2.4).y,
          width: p(6.0, 2.4).x - p(4.6, 2.4).x,
          height: p(6.0, 19.0).y - p(4.6, 2.4).y
        )
      )
      towers.addRect(
        CGRect(
          x: p(14.4, 9.4).x,
          y: p(14.4, 9.4).y,
          width: p(15.6, 9.4).x - p(14.4, 9.4).x,
          height: p(15.6, 19.0).y - p(14.4, 9.4).y
        )
      )
      context.fill(towers, with: .color(color))
      var harp = Path()
      for t in [8.0, 11.0, 14.0, 17.5] {
        harp.move(to: p(5.3, 2.8))
        harp.addLine(to: p(t, 19.0))
      }
      context.stroke(
        harp,
        with: .color(color),
        style: StrokeStyle(lineWidth: 0.95)
      )

    case .archBridge:
      var arch = Path()
      arch.move(to: p(1.4, 19.2))
      arch.addQuadCurve(to: p(18.6, 19.2), control: p(10.0, 1.2))
      context.stroke(
        arch,
        with: .color(color),
        style: StrokeStyle(lineWidth: 1.7, lineCap: .round)
      )
      var deck = Path()
      deck.move(to: p(0.8, 19.2))
      deck.addLine(to: p(19.2, 19.2))
      context.stroke(
        deck,
        with: .color(color),
        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
      )
    }
  }
}
