import KaidoNavigation
import SwiftUI

enum ReleasedRouteAtlasOverlayPresentation: Equatable {
  case unavailable
  case ready(
    projection: RouteAtlasJourneyProjection,
    isRealRoadAuthority: Bool
  )
  case blocked(String)
}

func releasedRouteAtlasOverlayErrorCode(_ error: Error) -> String {
  guard
    case RouteAtlasJourneyProjectionError.invalid(let issues) = error
  else {
    return "ATLAS_OVERLAY_PROJECTION_FAILED"
  }
  return Array(Set(issues.map(\.code))).sorted().joined(separator: "+")
}

struct ReleasedRouteAtlasOverlayContainer: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale

  let presentation: ReleasedRouteAtlasOverlayPresentation

  @ViewBuilder
  var body: some View {
    switch presentation {
    case .unavailable:
      EmptyView()
    case .ready(let projection, let isRealRoadAuthority):
      ReleasedRouteAtlasOverlayCard(
        projection: projection,
        isRealRoadAuthority: isRealRoadAuthority
      )
    case .blocked(let code):
      ReviewBoundaryCard(
        symbol: "map.fill.badge.xmark",
        title: copy.resolve(
          japanese: "ルートアトラス表示を停止",
          simplifiedChinese: "Route Atlas 路线层已阻止",
          english: "Route Atlas overlay blocked"
        ),
        detail: copy.resolve(
          japanese:
            "リリース、RoutePlan、または actor の occurrence 状態が一致しないため、経路線を表示しません。",
          simplifiedChinese:
            "发布包、RoutePlan 或 actor occurrence 状态不一致，因此不会绘制路线。",
          english:
            "Release, RoutePlan, or actor occurrence identity did not match, so no route line is rendered."
        ),
        code: code,
        color: KaidoTheme.evidenceCoral
      )
      .accessibilityIdentifier("released-route-atlas-overlay-blocked")
      .accessibilityValue(code)
    }
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }
}

/// Draws only a renderer-neutral projection produced from one validated
/// RouteAtlasRelease. It owns no graph, route progress, or position policy.
struct ReleasedRouteAtlasOverlayCard: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale

  let projection: RouteAtlasJourneyProjection
  let isRealRoadAuthority: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      atlas
      legend

      if repeatedTraversalCount > 0 {
        repetitionNotice
      }

      identity
      attributions
    }
    .padding(14)
    .background(KaidoTheme.instrument)
    .clipShape(RoundedRectangle(cornerRadius: 18))
    .overlay {
      RoundedRectangle(cornerRadius: 18)
        .stroke(KaidoTheme.signalAmber.opacity(0.46), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("released-route-atlas-overlay")
    .accessibilityLabel(accessibilityLabel)
    .accessibilityValue(accessibilityValue)
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(
          copy.resolve(
            japanese: "選択ルート · アトラス",
            simplifiedChinese: "已选路线 · Route Atlas",
            english: "Selected route · Route Atlas"
          )
        )
        .font(.system(size: 18, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.routeWhite)

        Text(
          copy.resolve(
            japanese:
              "経路状態は actor の occurrence だけを表示します。現在地マーカーとは別です。",
            simplifiedChinese:
              "路线状态只来自 actor occurrence，与当前位置标记相互独立。",
            english:
              "Route state comes only from actor occurrences and stays separate from the position marker."
          )
        )
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(KaidoTheme.muted)
        .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 8)

      StatusCapsule(
        title: isRealRoadAuthority ? "RELEASED" : "SYNTHETIC",
        color:
          isRealRoadAuthority
          ? KaidoTheme.positionCyan
          : KaidoTheme.evidenceCoral
      )
    }
  }

  private var atlas: some View {
    Canvas { context, size in
      for segment in projection.contextSegments {
        context.stroke(
          path(for: segment.points, in: size),
          with: .color(KaidoTheme.steel.opacity(0.62)),
          style: StrokeStyle(
            lineWidth: 3,
            lineCap: .round,
            lineJoin: .round
          )
        )
      }

      for occurrence in orderedOccurrencesForDrawing {
        let offset =
          (Double(occurrence.repeatOrdinal - 1)
            - Double(occurrence.repeatCount - 1) / 2)
          * 6
        let points = offsetPoints(
          scaledPoints(occurrence.points, in: size),
          by: offset
        )
        let path = path(for: points)
        context.stroke(
          path,
          with: .color(color(for: occurrence.state)),
          style: strokeStyle(for: occurrence.state)
        )

        if occurrence.isRepeatedTraversal,
          let point = midpoint(of: points)
        {
          let markerRect = CGRect(
            x: point.x - 8,
            y: point.y - 8,
            width: 16,
            height: 16
          )
          context.fill(
            Path(ellipseIn: markerRect),
            with: .color(KaidoTheme.asphalt)
          )
          context.stroke(
            Path(ellipseIn: markerRect),
            with: .color(color(for: occurrence.state)),
            lineWidth: 2
          )
          context.draw(
            Text("\(occurrence.repeatOrdinal)")
              .font(.system(size: 8, weight: .black, design: .monospaced))
              .foregroundStyle(KaidoTheme.routeWhite),
            at: point
          )
        }
      }
    }
    .frame(height: 250)
    .padding(8)
    .background(KaidoTheme.asphalt.opacity(0.72))
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay(alignment: .topTrailing) {
      Text("N")
        .font(.system(size: 9, weight: .black, design: .monospaced))
        .foregroundStyle(KaidoTheme.routeWhite)
        .padding(10)
    }
    .accessibilityHidden(true)
  }

  private var legend: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 12) {
        ForEach(legendStates, id: \.rawValue) { state in
          legendItem(state)
        }
      }

      VStack(alignment: .leading, spacing: 7) {
        ForEach(legendStates, id: \.rawValue) { state in
          legendItem(state)
        }
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("released-route-atlas-legend")
  }

  private func legendItem(
    _ state: RouteAtlasJourneyOccurrenceState
  ) -> some View {
    HStack(spacing: 5) {
      Capsule()
        .fill(color(for: state))
        .frame(width: 18, height: state == .current ? 5 : 3)

      Text(stateTitle(state))
        .font(.system(size: 8, weight: .black, design: .monospaced))
        .foregroundStyle(KaidoTheme.muted)
    }
  }

  private var repetitionNotice: some View {
    HStack(alignment: .top, spacing: 9) {
      Image(systemName: "repeat")
        .foregroundStyle(KaidoTheme.signalAmber)
        .accessibilityHidden(true)

      Text(
        copy.resolve(
          japanese:
            "同じ模式線を通る \(repeatedTraversalCount) 個の occurrence を番号付きの別トラックで保持しています。",
          simplifiedChinese:
            "同一示意线上的 \(repeatedTraversalCount) 个 occurrence 以编号独立轨道保留。",
          english:
            "\(repeatedTraversalCount) occurrences on repeated schematic segments remain separate numbered tracks."
        )
      )
      .font(.system(size: 9, weight: .semibold))
      .foregroundStyle(KaidoTheme.muted)
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding(10)
    .background(KaidoTheme.signalAmber.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 11))
    .accessibilityIdentifier("released-route-atlas-repetition")
  }

  private var identity: some View {
    VStack(alignment: .leading, spacing: 4) {
      identityRow("ROUTE PLAN", value: projection.routePlanID)
      identityRow("ATLAS", value: projection.atlasID)
      identityRow("SNAPSHOT", value: projection.networkSnapshotID)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("released-route-atlas-identity")
  }

  private var attributions: some View {
    VStack(alignment: .leading, spacing: 5) {
      ForEach(projection.attributions, id: \.sourceID) { attribution in
        if let url = URL(string: attribution.sourceURL) {
          Link(destination: url) {
            HStack(spacing: 5) {
              Image(systemName: "arrow.up.right.square")
              Text(attribution.authorityName)
              Text("· \(attribution.licenceIdentifier)")
            }
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(KaidoTheme.muted)
          }
          .accessibilityLabel(
            "\(attribution.authorityName), \(attribution.licenceIdentifier)"
          )
        }
      }
    }
    .accessibilityIdentifier("released-route-atlas-attribution")
  }

  private func identityRow(_ label: String, value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(label)
        .font(.system(size: 7, weight: .black, design: .monospaced))
        .foregroundStyle(KaidoTheme.muted)
        .frame(width: 74, alignment: .leading)

      Text(verbatim: value)
        .font(.system(size: 8, weight: .semibold, design: .monospaced))
        .foregroundStyle(KaidoTheme.routeWhite)
        .lineLimit(2)
    }
  }

  private var orderedOccurrencesForDrawing: [RouteAtlasJourneyOccurrence] {
    projection.occurrences.sorted {
      let left = drawingOrder($0.state)
      let right = drawingOrder($1.state)
      return left == right
        ? $0.occurrenceIndex < $1.occurrenceIndex
        : left < right
    }
  }

  private func drawingOrder(
    _ state: RouteAtlasJourneyOccurrenceState
  ) -> Int {
    switch state {
    case .planned, .future:
      0
    case .passed:
      1
    case .skipped:
      2
    case .current:
      3
    }
  }

  private func color(
    for state: RouteAtlasJourneyOccurrenceState
  ) -> Color {
    switch state {
    case .planned:
      KaidoTheme.signalAmber.opacity(0.9)
    case .passed:
      KaidoTheme.routeWhite.opacity(0.48)
    case .current:
      KaidoTheme.positionCyan
    case .future:
      KaidoTheme.signalAmber.opacity(0.62)
    case .skipped:
      KaidoTheme.evidenceCoral
    }
  }

  private func strokeStyle(
    for state: RouteAtlasJourneyOccurrenceState
  ) -> StrokeStyle {
    switch state {
    case .current:
      StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
    case .skipped:
      StrokeStyle(
        lineWidth: 4,
        lineCap: .round,
        lineJoin: .round,
        dash: [7, 5]
      )
    case .planned, .passed, .future:
      StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
    }
  }

  private func stateTitle(
    _ state: RouteAtlasJourneyOccurrenceState
  ) -> String {
    switch state {
    case .planned:
      copy.resolve(
        japanese: "計画",
        simplifiedChinese: "计划",
        english: "PLANNED"
      )
    case .passed:
      copy.resolve(
        japanese: "通過",
        simplifiedChinese: "已通过",
        english: "PASSED"
      )
    case .current:
      copy.resolve(
        japanese: "現在",
        simplifiedChinese: "当前",
        english: "CURRENT"
      )
    case .future:
      copy.resolve(
        japanese: "後続",
        simplifiedChinese: "后续",
        english: "FUTURE"
      )
    case .skipped:
      copy.resolve(
        japanese: "スキップ",
        simplifiedChinese: "已跳过",
        english: "SKIPPED"
      )
    }
  }

  private var legendStates: [RouteAtlasJourneyOccurrenceState] {
    let states = Set(projection.occurrences.map(\.state))
    return [
      .planned,
      .passed,
      .current,
      .future,
      .skipped,
    ].filter(states.contains)
  }

  private var repeatedTraversalCount: Int {
    projection.occurrences.filter(\.isRepeatedTraversal).count
  }

  private func path(
    for points: [RouteAtlasPoint],
    in size: CGSize
  ) -> Path {
    path(for: scaledPoints(points, in: size))
  }

  private func path(for points: [CGPoint]) -> Path {
    var path = Path()
    guard let first = points.first else { return path }
    path.move(to: first)
    for point in points.dropFirst() {
      path.addLine(to: point)
    }
    return path
  }

  private func scaledPoints(
    _ points: [RouteAtlasPoint],
    in size: CGSize
  ) -> [CGPoint] {
    let margin: CGFloat = 16
    let width = max(size.width - margin * 2, 1)
    let height = max(size.height - margin * 2, 1)
    return points.map {
      CGPoint(
        x: margin + CGFloat($0.x) * width,
        y: margin + CGFloat($0.y) * height
      )
    }
  }

  private func offsetPoints(
    _ points: [CGPoint],
    by distance: Double
  ) -> [CGPoint] {
    guard points.count >= 2, distance != 0 else { return points }
    return points.indices.map { index in
      let previous = points[index == points.startIndex ? index : index - 1]
      let next = points[index == points.index(before: points.endIndex) ? index : index + 1]
      let dx = next.x - previous.x
      let dy = next.y - previous.y
      let length = max(hypot(dx, dy), 0.001)
      return CGPoint(
        x: points[index].x - dy / length * CGFloat(distance),
        y: points[index].y + dx / length * CGFloat(distance)
      )
    }
  }

  private func midpoint(of points: [CGPoint]) -> CGPoint? {
    guard !points.isEmpty else { return nil }
    if points.count == 1 { return points[0] }
    var lengths: [CGFloat] = []
    var total: CGFloat = 0
    for index in 1..<points.count {
      let length = hypot(
        points[index].x - points[index - 1].x,
        points[index].y - points[index - 1].y
      )
      lengths.append(length)
      total += length
    }
    let target = total / 2
    var traversed: CGFloat = 0
    for (offset, length) in lengths.enumerated() {
      guard traversed + length < target else {
        let fraction = length == 0 ? 0 : (target - traversed) / length
        let start = points[offset]
        let end = points[offset + 1]
        return CGPoint(
          x: start.x + (end.x - start.x) * fraction,
          y: start.y + (end.y - start.y) * fraction
        )
      }
      traversed += length
    }
    return points.last
  }

  private var accessibilityLabel: String {
    copy.resolve(
      japanese:
        "リリース済み Route Atlas 上の選択ルート。\(projection.occurrences.count) occurrence。",
      simplifiedChinese:
        "已发布 Route Atlas 上的所选路线，共 \(projection.occurrences.count) 个 occurrence。",
      english:
        "Selected route on the released Route Atlas, \(projection.occurrences.count) occurrences."
    )
  }

  private var accessibilityValue: String {
    projection.occurrences.map {
      "\($0.occurrenceID):\($0.state.rawValue):"
        + "\($0.repeatOrdinal)/\($0.repeatCount)"
    }
    .joined(separator: " | ")
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }
}
