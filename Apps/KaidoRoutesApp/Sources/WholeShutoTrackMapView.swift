import KaidoPresentation
import KaidoRouting
import SwiftUI

struct WholeShutoTrackMapSpan: Equatable {
  let routeID: String
  let startFraction: Double
  let endFraction: Double
}

/// The whole-route track map in the midnight identity: the entire selected
/// route in one readable frame, drawn in screen space so marks and labels
/// keep a constant on-screen size. Facility names ride on collision-managed
/// plates beside their route points — the next facility ahead of the driver
/// always claims first and carries its remaining distance — and the driver
/// can pinch, double-tap, and pan exactly like the network diagram.
struct WholeShutoTrackMapView: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale

  let layout: RouteTrackMapLayout
  let spans: [WholeShutoTrackMapSpan]
  let entryFacilityID: String
  let currentCoordinate: ShutoCoordinate?
  let routeProgressFraction: Double?
  let isPositionEstimated: Bool
  /// Fraction of the view height left visible above the planning/driving
  /// dock; the whole route must fit inside it at base zoom.
  let visibleBottomFraction: Double
  var routeDistanceMeters: Double = 0
  /// Overrides the top strip where plates never place; portrait derives it
  /// from the floating banner, landscape needs almost none.
  var labelTopInsetOverride: Double? = nil

  @Binding var zoom: Double
  @Binding var pan: CGSize
  @State private var zoomAtGestureStart: Double?
  @State private var panAtGestureStart: CGSize?
  /// While driving the frame follows the position at a closer zoom until
  /// the driver takes over with a gesture; recentering hands it back.
  @Binding var userAdjustedViewport: Bool

  private static let maximumZoom = 5.0
  private static let doubleTapZoom = 2.2
  private static let followZoom = 2.4

  private enum Midnight {
    static let background = Color(red: 0.031, green: 0.043, blue: 0.078)
    static let casing = Color(red: 0.075, green: 0.1, blue: 0.16)
    static let plate = Color(red: 0.02, green: 0.031, blue: 0.063)
    static let label = Color(red: 0.62, green: 0.68, blue: 0.8)
    static let junctionLabel = Color(red: 0.79, green: 0.84, blue: 0.95)
    static let leader = Color(red: 0.192, green: 0.251, blue: 0.369)
    static let position = KaidoTheme.positionCyan
  }

  var body: some View {
    GeometryReader { geometry in
      let width = geometry.size.width
      let visibleHeight = geometry.size.height * visibleBottomFraction
      let fit = min(
        width / RouteTrackMapLayout.designWidth,
        visibleHeight / RouteTrackMapLayout.designHeight
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
            userAdjustedViewport = true
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
              userAdjustedViewport = true
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
              userAdjustedViewport = true
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
      .overlay(alignment: .bottomTrailing) {
        if currentCoordinate != nil, userAdjustedViewport {
          Button {
            userAdjustedViewport = false
            withAnimation(.easeOut(duration: 0.3)) {
              followPosition(
                fit: fit,
                width: width,
                visibleHeight: visibleHeight
              )
            }
          } label: {
            Image(systemName: "location.fill")
              .font(.system(size: 15, weight: .black))
              .foregroundStyle(Midnight.position)
              .frame(width: 44, height: 44)
              .background(Midnight.plate.opacity(0.92))
              .clipShape(Circle())
              .overlay {
                Circle()
                  .stroke(Midnight.leader, lineWidth: 1)
              }
          }
          .buttonStyle(.plain)
          .padding(.trailing, 14)
          .padding(.bottom, geometry.size.height - visibleHeight + 58)
          .accessibilityIdentifier("whole-shuto-track-map-recenter")
        }
      }
      .onAppear {
        if currentCoordinate != nil {
          followPosition(
            fit: fit,
            width: width,
            visibleHeight: visibleHeight
          )
        }
      }
      .onChange(of: currentCoordinate?.latitude) {
        guard !userAdjustedViewport else { return }
        followPosition(
          fit: fit,
          width: width,
          visibleHeight: visibleHeight
        )
      }
      .onChange(of: routeProgressFraction) {
        guard !userAdjustedViewport else { return }
        followPosition(
          fit: fit,
          width: width,
          visibleHeight: visibleHeight
        )
      }
      .onChange(of: currentCoordinate == nil) {
        if currentCoordinate == nil {
          userAdjustedViewport = false
          zoom = 1
          pan = .zero
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityIdentifier("whole-shuto-track-map")
    .accessibilityLabel(
      copy.resolve(
        japanese: "\(layout.facilityMarks.count)施設を含む全経路トラックマップ",
        simplifiedChinese: "包含\(layout.facilityMarks.count)个设施的全路线轨迹图",
        english: "Whole-route track map with \(layout.facilityMarks.count) facilities"
      )
    )
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }

  /// Centers the driving frame on the current position at the follow zoom.
  private func followPosition(
    fit: Double,
    width: Double,
    visibleHeight: Double
  ) {
    guard let position = currentTrackPosition else { return }
    let followZoom = Self.followZoom
    let centerX =
      (width - RouteTrackMapLayout.designWidth * fit * followZoom) / 2
    let centerY =
      (visibleHeight
        - RouteTrackMapLayout.designHeight * fit * followZoom) / 2
    zoom = followZoom
    pan = clampedPan(
      CGSize(
        width: width * 0.5 - centerX - position.x * fit * followZoom,
        height: visibleHeight * 0.52 - centerY
          - position.y * fit * followZoom
      ),
      fit: fit,
      zoom: followZoom,
      width: width,
      visibleHeight: visibleHeight
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
      x: (width - RouteTrackMapLayout.designWidth * fit * zoom) / 2
        + pan.width,
      y: (visibleHeight - RouteTrackMapLayout.designHeight * fit * zoom)
        / 2 + pan.height
    )
  }

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
      (width - RouteTrackMapLayout.designWidth * fit * newZoom) / 2
    let centerY =
      (visibleHeight - RouteTrackMapLayout.designHeight * fit * newZoom)
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

  private func clampedPan(
    _ pan: CGSize,
    fit: Double,
    zoom: Double,
    width: Double,
    visibleHeight: Double
  ) -> CGSize {
    let contentWidth = RouteTrackMapLayout.designWidth * fit * zoom
    let contentHeight = RouteTrackMapLayout.designHeight * fit * zoom
    let baseX = (width - contentWidth) / 2
    let baseY = (visibleHeight - contentHeight) / 2
    let margin = 120.0
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
    func place(_ x: Double, _ y: Double) -> CGPoint {
      CGPoint(x: offset.x + x * scale, y: offset.y + y * scale)
    }
    func path(_ points: [RouteTrackMapLayout.TrackPoint]) -> Path {
      var path = Path()
      guard let first = points.first else { return path }
      path.move(to: place(first.x, first.y))
      for point in points.dropFirst() {
        path.addLine(to: place(point.x, point.y))
      }
      return path
    }

    let position = currentTrackPosition

    let traveled = position?.fraction ?? 0
    let weightScale = 0.85 + 0.15 * zoom

    // Casing under everything.
    context.stroke(
      path(layout.trackPoints),
      with: .color(Midnight.casing),
      style: StrokeStyle(
        lineWidth: 9 * weightScale, lineCap: .round, lineJoin: .round
      )
    )

    // Neon underglow on the remaining route, then span colors: traveled
    // stays visible but quiet, remaining is lit.
    context.drawLayer { layer in
      layer.addFilter(.blur(radius: 5))
      for span in spans {
        let remainingStart = max(span.startFraction, traveled)
        guard remainingStart < span.endFraction else { continue }
        layer.stroke(
          path(
            layout.points(
              fromFraction: remainingStart,
              toFraction: span.endFraction
            )
          ),
          with: .color(spanColor(span).opacity(0.5)),
          style: StrokeStyle(
            lineWidth: 13 * weightScale,
            lineCap: .round,
            lineJoin: .round
          )
        )
      }
    }
    for span in spans {
      let traveledEnd = min(span.endFraction, traveled)
      if span.startFraction < traveledEnd {
        context.stroke(
          path(
            layout.points(
              fromFraction: span.startFraction,
              toFraction: traveledEnd
            )
          ),
          with: .color(spanColor(span).opacity(0.36)),
          style: StrokeStyle(
            lineWidth: 5 * weightScale, lineCap: .round, lineJoin: .round
          )
        )
      }
      let remainingStart = max(span.startFraction, traveled)
      if remainingStart < span.endFraction {
        context.stroke(
          path(
            layout.points(
              fromFraction: remainingStart,
              toFraction: span.endFraction
            )
          ),
          with: .color(spanColor(span)),
          style: StrokeStyle(
            lineWidth: 5 * weightScale, lineCap: .round, lineJoin: .round
          )
        )
      }
    }
    // Hot core on the remaining route.
    for span in spans {
      let remainingStart = max(span.startFraction, traveled)
      guard remainingStart < span.endFraction else { continue }
      context.stroke(
        path(
          layout.points(
            fromFraction: remainingStart,
            toFraction: span.endFraction
          )
        ),
        with: .color(Color.white.opacity(0.85)),
        style: StrokeStyle(
          lineWidth: 1.7 * weightScale, lineCap: .round, lineJoin: .round
        )
      )
    }

    // Direction chevrons along the remaining route.
    var chevronFraction = traveled + 0.035
    while chevronFraction < 0.985 {
      let point = layout.point(atFraction: chevronFraction)
      let heading = layout.heading(atFraction: chevronFraction)
      let center = place(point.x, point.y)
      var chevron = Path()
      chevron.move(to: CGPoint(x: -3.8, y: -3.2))
      chevron.addLine(to: CGPoint(x: 2.6, y: 0))
      chevron.addLine(to: CGPoint(x: -3.8, y: 3.2))
      context.drawLayer { layer in
        layer.translateBy(x: center.x, y: center.y)
        layer.rotate(by: .degrees(heading))
        layer.stroke(
          chevron,
          with: .color(Midnight.background.opacity(0.9)),
          style: StrokeStyle(
            lineWidth: 2, lineCap: .round, lineJoin: .round
          )
        )
      }
      chevronFraction += 0.058 / min(zoom, 2.2)
    }

    // Checkered start grid across the carriageway at the entrance,
    // matching the network diagram's circuit-sheet language.
    if let entrance = layout.facilityMarks.first(
      where: { $0.id == entryFacilityID }
    ) {
      let heading = layout.heading(atFraction: entrance.fraction)
      let center = place(entrance.x, entrance.y)
      context.drawLayer { layer in
        layer.translateBy(x: center.x, y: center.y)
        layer.rotate(by: .degrees(heading))
        for column in 0..<2 {
          for row in 0..<6 {
            let cell = CGRect(
              x: Double(column) * 4.6 - 4.6,
              y: Double(row) * 4.6 - 13.8,
              width: 4.6,
              height: 4.6
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

    // Label planning: collision-managed plates beside their route points.
    // The next facility ahead of the driver claims first and carries its
    // remaining distance; junctions outrank ICs and PAs for the rest.
    var occupied: [CGRect] = []
    let topInset =
      labelTopInsetOverride ?? (currentCoordinate == nil ? 96.0 : 200.0)
    func claim(_ rect: CGRect) -> Bool {
      guard rect.minX > -30, rect.maxX < width + 30,
        rect.minY > topInset, rect.maxY < visibleHeight + 16
      else { return false }
      guard !occupied.contains(where: { $0.intersects(rect) }) else {
        return false
      }
      occupied.append(rect)
      return true
    }
    if let position {
      let center = place(position.x, position.y)
      occupied.append(
        CGRect(x: center.x - 16, y: center.y - 16, width: 32, height: 32)
      )
    }

    let nextMark =
      position == nil
      ? nil
      : layout.facilityMarks
        .filter { $0.fraction > traveled + 0.002 }
        .min { $0.fraction < $1.fraction }
    let orderedMarks = layout.facilityMarks.sorted { left, right in
      if left.id == nextMark?.id { return true }
      if right.id == nextMark?.id { return false }
      let leftRank = rank(left.kind)
      let rightRank = rank(right.kind)
      if leftRank != rightRank { return leftRank < rightRank }
      return left.fraction < right.fraction
    }

    struct PlacedLabel {
      let text: Text
      let plate: CGRect
      let leaderFrom: CGPoint
      let accent: Color?
    }
    var labels: [PlacedLabel] = []

    let centroidX =
      layout.trackPoints.reduce(0) { $0 + $1.x }
      / Double(max(layout.trackPoints.count, 1))
    for mark in orderedMarks {
      let center = place(mark.x, mark.y)
      let isNext = mark.id == nextMark?.id
      let name = mark.nameJA.replacingOccurrences(of: "JCT・", with: "・")
      let title: String
      if isNext, routeDistanceMeters > 0 {
        let remaining =
          (mark.fraction - traveled) * routeDistanceMeters
        title = "\(distanceText(remaining)) \(name)"
      } else {
        title = name
      }
      let plateWidth = Double(title.count) * 11 + 16
      // Prefer the side away from the loop body so plates sit outside; the
      // next facility may also step above or below so it always lands even
      // when it sits right beside the position marker.
      let outward: Double = mark.x >= centroidX ? 1 : -1
      var candidates: [CGRect] = []
      for side in [outward, -outward] {
        let originX =
          side > 0 ? center.x + 10 : center.x - 10 - plateWidth
        candidates.append(
          CGRect(
            x: originX, y: center.y - 10, width: plateWidth, height: 20
          )
        )
        if isNext {
          for verticalOffset in [-30.0, 30.0, -52.0, 52.0] {
            candidates.append(
              CGRect(
                x: originX,
                y: center.y - 10 + verticalOffset,
                width: plateWidth,
                height: 20
              )
            )
          }
        }
      }
      guard let plate = candidates.first(where: { claim($0) }) else {
        continue
      }
      let tint: Color =
        switch mark.kind {
        case .junction: Midnight.junctionLabel
        case .parkingArea: KaidoTheme.confirmedGreen
        case .interchange: Midnight.label
        }
      labels.append(
        PlacedLabel(
          text: Text(title)
            .font(
              .system(
                size: mark.kind == .junction ? 11 : 10,
                weight: mark.kind == .junction || isNext ? .bold : .semibold
              )
            )
            .foregroundColor(isNext ? Color.white : tint),
          plate: plate,
          leaderFrom: center,
          accent: isNext ? Midnight.position : nil
        )
      )
    }

    // Marks above the line work.
    for mark in layout.facilityMarks {
      let center = place(mark.x, mark.y)
      switch mark.kind {
      case .junction:
        var diamond = Path()
        diamond.move(to: CGPoint(x: center.x, y: center.y - 4.2))
        diamond.addLine(to: CGPoint(x: center.x + 4.2, y: center.y))
        diamond.addLine(to: CGPoint(x: center.x, y: center.y + 4.2))
        diamond.addLine(to: CGPoint(x: center.x - 4.2, y: center.y))
        diamond.closeSubpath()
        context.fill(diamond, with: .color(Midnight.plate))
        context.stroke(
          diamond,
          with: .color(Midnight.junctionLabel),
          style: StrokeStyle(lineWidth: 1.4)
        )
      case .parkingArea:
        let square = Path(
          roundedRect: CGRect(
            x: center.x - 3.6, y: center.y - 3.6, width: 7.2, height: 7.2
          ),
          cornerRadius: 2
        )
        context.fill(square, with: .color(KaidoTheme.confirmedGreen))
        context.draw(
          Text("P")
            .font(.system(size: 5.5, weight: .black))
            .foregroundColor(Midnight.background),
          at: center,
          anchor: .center
        )
      case .interchange:
        let dot = Path(
          ellipseIn: CGRect(
            x: center.x - 3, y: center.y - 3, width: 6, height: 6
          )
        )
        context.fill(dot, with: .color(Midnight.background))
        context.stroke(
          dot,
          with: .color(Midnight.label),
          style: StrokeStyle(lineWidth: 1.4)
        )
      }
    }

    // Plates on top, each with a short leader back to its point.
    for label in labels {
      let plateEdge = CGPoint(
        x: label.leaderFrom.x < label.plate.midX
          ? label.plate.minX : label.plate.maxX,
        y: label.plate.midY
      )
      var leader = Path()
      leader.move(to: label.leaderFrom)
      leader.addLine(to: plateEdge)
      context.stroke(
        leader,
        with: .color(Midnight.leader),
        style: StrokeStyle(lineWidth: 1.1)
      )
      context.fill(
        Path(roundedRect: label.plate, cornerRadius: 6),
        with: .color(Midnight.plate.opacity(0.88))
      )
      if let accent = label.accent {
        context.stroke(
          Path(roundedRect: label.plate, cornerRadius: 6),
          with: .color(accent),
          style: StrokeStyle(lineWidth: 1.2)
        )
      }
      context.draw(
        label.text,
        at: CGPoint(x: label.plate.minX + 8, y: label.plate.midY),
        anchor: .leading
      )
    }

    // The current position renders last, above every other layer.
    if let position {
      let heading = layout.heading(atFraction: position.fraction)
      let center = place(position.x, position.y)
      let halo = Path(
        ellipseIn: CGRect(
          x: center.x - 12, y: center.y - 12, width: 24, height: 24
        )
      )
      context.fill(halo, with: .color(Midnight.position.opacity(0.22)))
      let dot = Path(
        ellipseIn: CGRect(
          x: center.x - 7, y: center.y - 7, width: 14, height: 14
        )
      )
      if isPositionEstimated {
        context.fill(dot, with: .color(Midnight.background))
        context.stroke(
          dot,
          with: .color(Midnight.position),
          style: StrokeStyle(lineWidth: 2.4, dash: [3, 2.4])
        )
      } else {
        context.fill(dot, with: .color(Midnight.position))
        context.stroke(
          dot,
          with: .color(Midnight.background),
          style: StrokeStyle(lineWidth: 1.6)
        )
        var arrow = Path()
        arrow.move(to: CGPoint(x: -3, y: -1.6))
        arrow.addLine(to: CGPoint(x: 0, y: -7))
        arrow.addLine(to: CGPoint(x: 3, y: -1.6))
        arrow.closeSubpath()
        context.drawLayer { layer in
          layer.translateBy(x: center.x, y: center.y)
          layer.rotate(by: .degrees(heading + 90))
          layer.fill(arrow, with: .color(Midnight.background))
        }
      }
    }
  }

  private var currentTrackPosition: RouteTrackMapLayout.TrackPoint? {
    if let routeProgressFraction {
      return layout.point(atFraction: min(1, max(0, routeProgressFraction)))
    }
    return currentCoordinate.map {
      layout.nearestTrackPoint(
        to: RouteTrackMapLayout.GeoPoint(
          latitude: $0.latitude,
          longitude: $0.longitude
        ),
        projector: layout.projector.project
      )
    }
  }

  private func spanColor(_ span: WholeShutoTrackMapSpan) -> Color {
    KaidoTheme.selectedRouteLineColor(span.routeID)
  }

  private func rank(_ kind: RouteTrackMapLayout.FacilityKind) -> Int {
    switch kind {
    case .junction: 0
    case .parkingArea: 1
    case .interchange: 2
    }
  }

  private func distanceText(_ meters: Double) -> String {
    if meters < 950 {
      return "\(Int((meters / 50).rounded() * 50))m"
    }
    return String(format: "%.1fkm", meters / 1000)
  }
}
