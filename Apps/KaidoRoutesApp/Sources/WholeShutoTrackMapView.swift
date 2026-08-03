import KaidoPresentation
import KaidoRouting
import SwiftUI

struct WholeShutoTrackMapSpan: Equatable {
  let routeID: String
  let startFraction: Double
  let endFraction: Double
}

/// The whole-route track map: the entire selected route in one readable
/// frame, every on-route facility always labeled, and — while driving — the
/// current position as the most prominent point element, rendered above all
/// other layers with nearby labels yielding to it.
struct WholeShutoTrackMapView: View {
  let layout: RouteTrackMapLayout
  let spans: [WholeShutoTrackMapSpan]
  let entryFacilityID: String
  let currentCoordinate: ShutoCoordinate?
  let isPositionEstimated: Bool
  let usesDarkStyle: Bool
  /// Fraction of the view height left visible above the planning/driving
  /// dock; the whole route must fit inside it.
  let visibleBottomFraction: Double

  private struct Palette {
    let background: Color
    let casing: Color
    let baseRoute: Color
    let bayshore: Color
    let label: Color
    let junctionLabel: Color
    let leader: Color
    let position: Color
  }

  private var palette: Palette {
    usesDarkStyle
      ? Palette(
        background: Color(red: 0.05, green: 0.07, blue: 0.1),
        casing: Color(red: 0.11, green: 0.14, blue: 0.2),
        baseRoute: Color(red: 1.0, green: 0.71, blue: 0.33),
        bayshore: Color(red: 0.5, green: 0.65, blue: 0.88),
        label: Color(red: 0.67, green: 0.72, blue: 0.82),
        junctionLabel: Color(red: 0.95, green: 0.97, blue: 1.0),
        leader: Color(red: 0.23, green: 0.29, blue: 0.4),
        position: KaidoTheme.positionCyan
      )
      : Palette(
        background: KaidoTheme.paper,
        casing: Color(red: 0.85, green: 0.87, blue: 0.9),
        baseRoute: Color(red: 0.85, green: 0.5, blue: 0.12),
        bayshore: Color(red: 0.29, green: 0.45, blue: 0.72),
        label: Color(red: 0.35, green: 0.4, blue: 0.48),
        junctionLabel: Color(red: 0.1, green: 0.13, blue: 0.18),
        leader: Color(red: 0.72, green: 0.76, blue: 0.82),
        position: KaidoTheme.positionCyan
      )
  }

  var body: some View {
    GeometryReader { geometry in
      let visibleHeight = geometry.size.height * visibleBottomFraction
      let scale = min(
        geometry.size.width / RouteTrackMapLayout.designWidth,
        visibleHeight / RouteTrackMapLayout.designHeight
      )
      let offsetX =
        (geometry.size.width
          - RouteTrackMapLayout.designWidth * scale) / 2
      let offsetY =
        (visibleHeight
          - RouteTrackMapLayout.designHeight * scale) / 2
      Canvas { context, _ in
        context.translateBy(x: offsetX, y: offsetY)
        context.scaleBy(x: scale, y: scale)
        draw(in: &context)
      }
      .background(palette.background)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityIdentifier("whole-shuto-track-map")
    .accessibilityLabel(
      Text("Whole-route track map with \(layout.facilityMarks.count) facilities")
    )
  }

  private func draw(in context: inout GraphicsContext) {
    let position = currentCoordinate.map {
      layout.nearestTrackPoint(
        to: RouteTrackMapLayout.GeoPoint(
          latitude: $0.latitude,
          longitude: $0.longitude
        ),
        projector: layout.projector.project
      )
    }
    let traveled = position?.fraction ?? 0

    // Casing under everything.
    context.stroke(
      path(layout.trackPoints),
      with: .color(palette.casing),
      style: StrokeStyle(lineWidth: 8.5, lineCap: .round, lineJoin: .round)
    )
    // Traveled portion stays visible but quiet; remaining is bright.
    for span in spans {
      let color =
        span.routeID == "B" ? palette.bayshore : palette.baseRoute
      let traveledEnd = min(span.endFraction, traveled)
      if span.startFraction < traveledEnd {
        context.stroke(
          path(
            layout.points(
              fromFraction: span.startFraction,
              toFraction: traveledEnd
            )
          ),
          with: .color(color.opacity(0.42)),
          style: StrokeStyle(
            lineWidth: 4.6, lineCap: .round, lineJoin: .round
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
          with: .color(color),
          style: StrokeStyle(
            lineWidth: 4.6, lineCap: .round, lineJoin: .round
          )
        )
      }
    }

    // Direction chevrons along the remaining route.
    var chevronFraction = traveled + 0.035
    while chevronFraction < 0.985 {
      let point = layout.point(atFraction: chevronFraction)
      let heading = layout.heading(atFraction: chevronFraction)
      var chevron = Path()
      chevron.move(to: CGPoint(x: -3.6, y: -3))
      chevron.addLine(to: CGPoint(x: 2.4, y: 0))
      chevron.addLine(to: CGPoint(x: -3.6, y: 3))
      context.drawLayer { layer in
        layer.translateBy(x: point.x, y: point.y)
        layer.rotate(by: .degrees(heading))
        layer.stroke(
          chevron,
          with: .color(palette.background),
          style: StrokeStyle(
            lineWidth: 1.8, lineCap: .round, lineJoin: .round
          )
        )
      }
      chevronFraction += 0.058
    }

    // Entrance tick.
    if let entrance = layout.facilityMarks.first(
      where: { $0.id == entryFacilityID }
    ) {
      let heading = layout.heading(atFraction: entrance.fraction)
      var tick = Path()
      tick.move(to: CGPoint(x: 0, y: -8))
      tick.addLine(to: CGPoint(x: 0, y: 8))
      tick.move(to: CGPoint(x: 4, y: -8))
      tick.addLine(to: CGPoint(x: 4, y: 8))
      context.drawLayer { layer in
        layer.translateBy(x: entrance.x, y: entrance.y)
        layer.rotate(by: .degrees(heading + 90))
        layer.stroke(
          tick,
          with: .color(palette.junctionLabel),
          style: StrokeStyle(lineWidth: 2)
        )
      }
    }

    // Facility marks, leaders, and always-on labels. Labels yield to the
    // position marker instead of ever occluding it.
    for mark in layout.facilityMarks {
      let labelYields =
        position.map {
          hypot(mark.labelX - $0.x, mark.labelY - $0.y) < 34
        } ?? false
      if !labelYields {
        var leader = Path()
        leader.move(to: CGPoint(x: mark.x, y: mark.y))
        leader.addLine(to: CGPoint(x: mark.labelX, y: mark.labelY))
        context.stroke(
          leader,
          with: .color(palette.leader),
          style: StrokeStyle(lineWidth: 1)
        )
      }
      switch mark.kind {
      case .junction:
        var diamond = Path()
        diamond.move(to: CGPoint(x: 0, y: -4.4))
        diamond.addLine(to: CGPoint(x: 4.4, y: 0))
        diamond.addLine(to: CGPoint(x: 0, y: 4.4))
        diamond.addLine(to: CGPoint(x: -4.4, y: 0))
        diamond.closeSubpath()
        context.drawLayer { layer in
          layer.translateBy(x: mark.x, y: mark.y)
          layer.fill(diamond, with: .color(palette.background))
          layer.stroke(
            diamond,
            with: .color(palette.junctionLabel),
            style: StrokeStyle(lineWidth: 1.4)
          )
        }
      case .parkingArea:
        let square = Path(
          roundedRect: CGRect(x: mark.x - 3.3, y: mark.y - 3.3, width: 6.6, height: 6.6),
          cornerRadius: 1.8
        )
        context.fill(square, with: .color(KaidoTheme.routeGreen))
      case .interchange:
        let dot = Path(
          ellipseIn: CGRect(x: mark.x - 3, y: mark.y - 3, width: 6, height: 6)
        )
        context.fill(dot, with: .color(palette.background))
        context.stroke(
          dot,
          with: .color(palette.label),
          style: StrokeStyle(lineWidth: 1.4)
        )
      }
      if !labelYields {
        let isJunction = mark.kind == .junction
        let text = Text(mark.nameJA.replacingOccurrences(of: "JCT・", with: "・"))
          .font(
            .system(size: isJunction ? 11.5 : 10.5, weight: isJunction ? .bold : .semibold)
          )
          .foregroundColor(
            isJunction ? palette.junctionLabel : palette.label
          )
        let anchor: UnitPoint
        switch mark.zone {
        case .left: anchor = .trailing
        case .right: anchor = .leading
        case .top, .bottom: anchor = .center
        }
        context.draw(
          text,
          at: CGPoint(x: mark.labelX, y: mark.labelY),
          anchor: anchor
        )
      }
    }

    // The current position renders last, above every other layer.
    if let position {
      let heading = layout.heading(atFraction: position.fraction)
      let halo = Path(
        ellipseIn: CGRect(
          x: position.x - 11, y: position.y - 11, width: 22, height: 22
        )
      )
      context.fill(halo, with: .color(palette.position.opacity(0.22)))
      let dot = Path(
        ellipseIn: CGRect(
          x: position.x - 6.5, y: position.y - 6.5, width: 13, height: 13
        )
      )
      if isPositionEstimated {
        context.fill(dot, with: .color(palette.background))
        context.stroke(
          dot,
          with: .color(palette.position),
          style: StrokeStyle(lineWidth: 2.4, dash: [3, 2.4])
        )
      } else {
        context.fill(dot, with: .color(palette.position))
        context.stroke(
          dot,
          with: .color(palette.background),
          style: StrokeStyle(lineWidth: 1.6)
        )
        var arrow = Path()
        arrow.move(to: CGPoint(x: -2.8, y: -1.4))
        arrow.addLine(to: CGPoint(x: 0, y: -6.6))
        arrow.addLine(to: CGPoint(x: 2.8, y: -1.4))
        arrow.closeSubpath()
        context.drawLayer { layer in
          layer.translateBy(x: position.x, y: position.y)
          layer.rotate(by: .degrees(heading + 90))
          layer.fill(arrow, with: .color(palette.background))
        }
      }
    }
  }

  private func path(
    _ points: [RouteTrackMapLayout.TrackPoint]
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
