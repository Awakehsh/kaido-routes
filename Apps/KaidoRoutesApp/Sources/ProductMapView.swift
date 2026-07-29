import KaidoDomain
import KaidoNavigation
import MapKit
import SwiftUI

extension ProductMapProjection {
  func title(for locale: KaidoReleaseLocale) -> String {
    let copy = KaidoInterfaceText(locale: locale)
    return switch self {
    case .geographic:
      copy.resolve(
        japanese: "地図",
        simplifiedChinese: "地图",
        english: "Map"
      )
    case .topology:
      copy.resolve(
        japanese: "路線",
        simplifiedChinese: "线路",
        english: "Lines"
      )
    }
  }
}

struct ProductMapProjectionPicker: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale
  @ObservedObject var model: ProductMapPresentationModel
  let usesDarkStyle: Bool

  var body: some View {
    HStack(spacing: 3) {
      ForEach(ProductMapProjection.allCases) { projection in
        Button {
          withAnimation(.easeOut(duration: 0.16)) {
            model.select(projection)
          }
        } label: {
          Text(projection.title(for: interfaceLocale))
            .font(.system(size: 12, weight: .black, design: .rounded))
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .foregroundStyle(
              model.projection == projection
                ? selectedForeground
                : unselectedForeground
            )
            .background(
              model.projection == projection
                ? selectedBackground
                : Color.clear
            )
            .clipShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(
          model.projection == projection ? .isSelected : []
        )
        .accessibilityIdentifier(
          "product-map-projection-\(projection.rawValue)"
        )
      }
    }
    .padding(3)
    .background(
      usesDarkStyle
        ? KaidoTheme.instrument
        : KaidoTheme.paperRaised
    )
    .overlay {
      Rectangle()
        .stroke(
          usesDarkStyle
            ? KaidoTheme.steel
            : KaidoTheme.paperDivider,
          lineWidth: 1
        )
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("product-map-projection-picker")
    .accessibilityValue(model.projection.rawValue)
  }

  private var selectedForeground: Color {
    usesDarkStyle ? KaidoTheme.ink : KaidoTheme.paperRaised
  }

  private var unselectedForeground: Color {
    usesDarkStyle ? KaidoTheme.muted : KaidoTheme.quietText
  }

  private var selectedBackground: Color {
    usesDarkStyle ? KaidoTheme.routeWhite : KaidoTheme.routeGreen
  }
}

struct ProductMapViewport: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale
  @ObservedObject var mapModel: ProductMapPresentationModel

  let surfaceID: String
  let presentation: ReleasedRouteAtlasOverlayPresentation
  let geographicPresentation: ProductGeographicMapPresentation?
  let navigationSnapshot: NavigationSnapshot?
  let positionEvidence: ProductTopologyPositionEvidence?
  let topologyFacilities: ProductTopologyFacilityPresentation?
  let usesDarkStyle: Bool
  var junctionPresentation: ProductJunctionInsetPresentation? = nil

  var body: some View {
    VStack(spacing: 0) {
      ZStack(alignment: .bottom) {
        map

        if let junctionPresentation {
          ProductJunctionInsetView(presentation: junctionPresentation)
            .padding(10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(1)
        }
      }
      .frame(minHeight: usesDarkStyle ? 300 : 258)
      .animation(
        .easeOut(duration: 0.22),
        value: junctionPresentation?.decisionZoneID
      )

      HStack(spacing: 7) {
        Image(systemName: "circle.fill")
          .font(.system(size: 5))
          .foregroundStyle(
            usesDarkStyle
              ? KaidoTheme.signalAmber
              : KaidoTheme.routeGreen
          )

        Text(scopeLabel)
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(
            usesDarkStyle ? KaidoTheme.muted : KaidoTheme.quietText
          )

        Spacer()

        Text(
          mapModel.projection.title(for: interfaceLocale)
        )
        .font(.system(size: 9, weight: .black, design: .rounded))
        .foregroundStyle(
          usesDarkStyle
            ? KaidoTheme.routeWhite
            : KaidoTheme.routeGreenDeep
        )
      }
      .padding(.horizontal, 12)
      .frame(height: 32)
      .background(
        usesDarkStyle
          ? KaidoTheme.asphalt
          : KaidoTheme.paperRaised
      )
    }
    .background(
      usesDarkStyle
        ? KaidoTheme.instrument
        : KaidoTheme.paperRaised
    )
    .clipShape(RoundedRectangle(cornerRadius: usesDarkStyle ? 18 : 4))
    .overlay {
      RoundedRectangle(cornerRadius: usesDarkStyle ? 18 : 4)
        .stroke(
          usesDarkStyle
            ? KaidoTheme.steel
            : KaidoTheme.paperDivider,
          lineWidth: 1
        )
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("product-map-\(surfaceID)")
    .accessibilityValue(mapModel.projection.rawValue)
  }

  @ViewBuilder
  private var map: some View {
    if mapModel.projection == .geographic {
      if let geographicPresentation {
        ProductGeographicMapView(
          presentation: geographicPresentation,
          followsPosition: surfaceID == "drive",
          usesDarkStyle: usesDarkStyle
        )
      } else {
        mapUnavailable(
          copy.resolve(
            japanese: "この経路の地図はまだ利用できません",
            simplifiedChinese: "这条路线的地图暂不可用",
            english: "The map for this route is not available yet"
          )
        )
      }
    } else {
      switch presentation {
      case .ready(let projection, _):
        ProductTopologyMapView(
          presentation: ProductTopologyMapPresentation.make(
            projection: projection,
            evidence: positionEvidence,
            snapshot: navigationSnapshot,
            facilities: topologyFacilities
          ),
          usesDarkStyle: usesDarkStyle,
          showsPositionStatus: surfaceID == "drive"
        )
      case .unavailable, .blocked:
        mapUnavailable(
          copy.resolve(
            japanese: "この経路の地図はまだ利用できません",
            simplifiedChinese: "这条路线的地图暂不可用",
            english: "The map for this route is not available yet"
          )
        )
      }
    }
  }

  private func mapUnavailable(_ message: String) -> some View {
    ZStack {
      usesDarkStyle ? KaidoTheme.instrument : KaidoTheme.paperRaised
      VStack(spacing: 8) {
        Image(systemName: "map")
          .font(.system(size: 24, weight: .light))
        Text(message)
          .font(.system(size: 12, weight: .bold))
      }
      .foregroundStyle(
        usesDarkStyle ? KaidoTheme.muted : KaidoTheme.quietText
      )
    }
  }

  private var scopeLabel: String {
    if surfaceID == "drive" {
      return copy.resolve(
        japanese: "ナビゲーション地図",
        simplifiedChinese: "导航地图",
        english: "Navigation map"
      )
    }
    return copy.resolve(
      japanese: "ルート地図",
      simplifiedChinese: "路线地图",
      english: "Route map"
    )
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }
}

struct ProductTopologyMapView: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale

  let presentation: ProductTopologyMapPresentation
  let usesDarkStyle: Bool
  let showsPositionStatus: Bool

  var body: some View {
    ZStack(alignment: .topLeading) {
      background

      Canvas { context, size in
        drawContext(context: &context, size: size)
        drawRoute(context: &context, size: size)
        drawMeasuredMarker(context: &context, size: size)
      }
      .accessibilityHidden(true)

      if let facilities = presentation.facilities {
        GeometryReader { proxy in
          ForEach(facilities.landmarks) { landmark in
            let point = mapPoint(landmark.point, size: proxy.size)
            let badgeCenter = landmarkBadgeCenter(
              landmark,
              facilities: facilities,
              size: proxy.size
            )

            Path { path in
              path.move(to: point)
              path.addLine(to: badgeCenter)
            }
            .stroke(
              primaryText.opacity(usesDarkStyle ? 0.36 : 0.24),
              style: StrokeStyle(
                lineWidth: 1,
                lineCap: .round,
                dash: [3, 3]
              )
            )

            ProductTopologyLandmarkBadge(
              landmark: landmark,
              usesDarkStyle: usesDarkStyle
            )
            .position(badgeCenter)

            Circle()
              .fill(KaidoTheme.routeGreen)
              .frame(width: 11, height: 11)
              .overlay {
                Circle()
                  .stroke(KaidoTheme.paperRaised, lineWidth: 2)
              }
              .position(point)
              .accessibilityHidden(true)
          }
        }
      }

      topologyHeader
      bottomChrome
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("product-topology-map")
    .accessibilityValue(
      "\(presentation.orderedOccurrences.count) ordered occurrences, "
        + "\(presentation.repeatedOccurrenceCount) repeated occurrences"
    )
  }

  private var topologyHeader: some View {
    HStack(spacing: 9) {
      if let routeShield = presentation.facilities?.routeShields.first {
        Text(routeShield)
          .font(.system(size: 14, weight: .black, design: .rounded))
          .foregroundStyle(.white)
          .frame(width: 40, height: 34)
          .background(KaidoTheme.routeGreen)
          .clipShape(RoundedRectangle(cornerRadius: 6))
          .overlay {
            RoundedRectangle(cornerRadius: 6)
              .stroke(.white.opacity(0.92), lineWidth: 1.5)
          }
          .accessibilityIdentifier("product-topology-route-shield")
      }

      VStack(alignment: .leading, spacing: 2) {
        Text(
          copy.resolve(
            japanese: "選択ルート全体",
            simplifiedChinese: "所选路线全览",
            english: "Selected route overview"
          )
        )
        .font(.system(size: 11, weight: .black, design: .rounded))

        Text(routeEndpointLabel)
          .font(.system(size: 9, weight: .bold))
          .lineLimit(1)
          .minimumScaleFactor(0.68)
      }

      Spacer(minLength: 4)
    }
    .foregroundStyle(primaryText)
    .padding(.horizontal, 10)
    .frame(height: 52)
    .background(
      LinearGradient(
        colors: [
          statusBackground,
          statusBackground.opacity(0.78),
          .clear,
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    )
  }

  private var bottomChrome: some View {
    VStack {
      Spacer()

      if let facilities = presentation.facilities {
        facilitySummary(facilities)
      }
      if showsPositionStatus {
        positionStatus
      }
    }
  }

  private func facilitySummary(
    _ facilities: ProductTopologyFacilityPresentation
  ) -> some View {
    HStack(spacing: 0) {
      facilityMetric(
        copy.resolve(
          japanese: "入口",
          simplifiedChinese: "入口",
          english: "ENTRY"
        ),
        count: facilities.entranceCount
      )
      facilityMetric("JCT", count: facilities.junctionCount)
      facilityMetric("PA", count: facilities.parkingAreaCount)
      facilityMetric(
        copy.resolve(
          japanese: "出口",
          simplifiedChinese: "出口",
          english: "EXIT"
        ),
        count: facilities.exitCount
      )
    }
    .frame(height: 32)
    .background(statusBackground)
    .overlay(alignment: .top) {
      Rectangle()
        .fill(
          usesDarkStyle
            ? KaidoTheme.steel.opacity(0.58)
            : KaidoTheme.paperDivider
        )
        .frame(height: 1)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityIdentifier("product-topology-facility-summary")
    .accessibilityValue(
      "entrance=\(facilities.entranceCount);"
        + "junction=\(facilities.junctionCount);"
        + "parking=\(facilities.parkingAreaCount);"
        + "exit=\(facilities.exitCount)"
    )
  }

  private func facilityMetric(
    _ label: String,
    count: Int
  ) -> some View {
    HStack(spacing: 4) {
      Text(label)
        .font(.system(size: 8, weight: .black, design: .rounded))
      Text("\(count)")
        .font(.system(size: 10, weight: .black, design: .monospaced))
    }
    .foregroundStyle(
      count > 0 ? primaryText : primaryText.opacity(0.42)
    )
    .frame(maxWidth: .infinity)
  }

  private var positionStatus: some View {
    HStack {
      switch presentation.position {
      case .measured(let marker):
        Label(
          copy.resolve(
            japanese: "現在地 · 区間 \(marker.occurrenceIndex + 1)",
            simplifiedChinese: "当前位置 · 第 \(marker.occurrenceIndex + 1) 段",
            english: "Current position · segment \(marker.occurrenceIndex + 1)"
          ),
          systemImage: "location.fill"
        )
        .accessibilityIdentifier("product-topology-position-marker")
      case .estimated:
        Label(
          copy.resolve(
            japanese: "位置を推定中",
            simplifiedChinese: "位置估算中",
            english: "Position estimated"
          ),
          systemImage: "location.circle"
        )
        .accessibilityIdentifier("product-topology-position-estimated")
      case .unavailable:
        Label(
          copy.resolve(
            japanese: "現在地は未確定",
            simplifiedChinese: "当前位置尚未确定",
            english: "Current position unavailable"
          ),
          systemImage: "location.slash"
        )
        .accessibilityIdentifier("product-topology-position-unavailable")
      }

      Spacer()

      if presentation.repeatedOccurrenceCount > 0 {
        Label(
          copy.resolve(
            japanese: "反復を保持",
            simplifiedChinese: "保留重复路段",
            english: "Repeats retained"
          ),
          systemImage: "repeat"
        )
        .accessibilityIdentifier("product-topology-repeated-occurrences")
      }
    }
    .font(.system(size: 9, weight: .black))
    .foregroundStyle(primaryText)
    .padding(.horizontal, 10)
    .frame(height: 32)
    .background(statusBackground)
  }

  private var routeEndpointLabel: String {
    guard
      let facilities = presentation.facilities,
      let entrance = facilities.landmarks.first(where: {
        $0.kind == .entrance
      })?.title.value(for: interfaceLocale),
      let exit = facilities.landmarks.first(where: {
        $0.kind == .exit
      })?.title.value(for: interfaceLocale)
    else {
      return copy.resolve(
        japanese: "\(presentation.orderedOccurrences.count) 区間",
        simplifiedChinese: "\(presentation.orderedOccurrences.count) 个路段",
        english: "\(presentation.orderedOccurrences.count) route segments"
      )
    }
    return "\(entrance) → \(exit)"
  }

  private func landmarkBadgeCenter(
    _ landmark: ProductTopologyLandmark,
    facilities: ProductTopologyFacilityPresentation,
    size: CGSize
  ) -> CGPoint {
    let landmarks = facilities.landmarks.sorted {
      $0.occurrenceIndex < $1.occurrenceIndex
    }
    let ordinal =
      landmarks.firstIndex(where: { $0.id == landmark.id }) ?? 0
    let firstRowY: CGFloat = 78
    let lastRowY = max(
      firstRowY,
      size.height - plotBottomInset - 18
    )
    let rowStep =
      (lastRowY - firstRowY)
      / CGFloat(max(1, landmarks.count - 1))
    let badgeHalfWidth: CGFloat = 74
    let edgePadding: CGFloat = 10
    let leftColumnX = edgePadding + badgeHalfWidth
    let rightColumnX = size.width - edgePadding - badgeHalfWidth
    return CGPoint(
      x: ordinal.isMultiple(of: 2) ? rightColumnX : leftColumnX,
      y: firstRowY + CGFloat(ordinal) * rowStep
    )
  }

  private var plotBottomInset: CGFloat {
    CGFloat(presentation.facilities == nil ? 0 : 32)
      + CGFloat(showsPositionStatus ? 32 : 0)
      + 10
  }

  private func mapPoint(
    _ point: RouteAtlasPoint,
    size: CGSize
  ) -> CGPoint {
    let horizontalInset: CGFloat = 16
    let topInset: CGFloat = 52
    return CGPoint(
      x:
        horizontalInset
        + point.x * max(1, size.width - horizontalInset * 2),
      y:
        topInset
        + point.y * max(1, size.height - topInset - plotBottomInset)
    )
  }

  private var background: Color {
    usesDarkStyle ? KaidoTheme.asphalt : KaidoTheme.paper
  }

  private var primaryText: Color {
    usesDarkStyle ? KaidoTheme.routeWhite : KaidoTheme.ink
  }

  private var statusBackground: Color {
    usesDarkStyle
      ? KaidoTheme.instrument.opacity(0.94)
      : KaidoTheme.paperRaised.opacity(0.96)
  }

  private func drawContext(
    context: inout GraphicsContext,
    size: CGSize
  ) {
    for segment in presentation.projection.contextSegments {
      context.stroke(
        path(
          for: scaledPoints(
            ProductTopologyGeometry.octilinear(segment.points),
            size: size
          )
        ),
        with: .color(
          usesDarkStyle
            ? Color(hex: 0x675C94).opacity(0.7)
            : Color(hex: 0x7167A4).opacity(0.52)
        ),
        style: StrokeStyle(
          lineWidth: 3,
          lineCap: .square,
          lineJoin: .miter
        )
      )
    }
  }

  private func drawRoute(
    context: inout GraphicsContext,
    size: CGSize
  ) {
    for occurrence in presentation.orderedOccurrences {
      let points = offsetPoints(
        scaledPoints(
          ProductTopologyGeometry.octilinear(occurrence.points),
          size: size
        ),
        occurrence: occurrence
      )
      context.stroke(
        path(for: points),
        with: .color(color(for: occurrence.state)),
        style: strokeStyle(for: occurrence.state)
      )

      if occurrence.isRepeatedTraversal,
        let labelPoint = point(
          along: points,
          fraction: repeatLabelFraction(occurrence)
        )
      {
        context.fill(
          Path(
            ellipseIn: CGRect(
              x: labelPoint.x - 7,
              y: labelPoint.y - 7,
              width: 14,
              height: 14
            )
          ),
          with: .color(background)
        )
        context.draw(
          Text("\(occurrence.repeatOrdinal)")
            .font(.system(size: 7, weight: .black, design: .rounded))
            .foregroundStyle(primaryText),
          at: labelPoint
        )
      }
    }
  }

  private func drawMeasuredMarker(
    context: inout GraphicsContext,
    size: CGSize
  ) {
    guard case .measured(let marker) = presentation.position else {
      return
    }
    let point = offsetPoint(
      mapPoint(marker.point, size: size),
      marker: marker,
      size: size
    )
    context.fill(
      Path(
        ellipseIn: CGRect(
          x: point.x - 10,
          y: point.y - 10,
          width: 20,
          height: 20
        )
      ),
      with: .color(KaidoTheme.positionCyan.opacity(0.22))
    )
    context.fill(
      Path(
        ellipseIn: CGRect(
          x: point.x - 5,
          y: point.y - 5,
          width: 10,
          height: 10
        )
      ),
      with: .color(KaidoTheme.positionCyan)
    )
    context.stroke(
      Path(
        ellipseIn: CGRect(
          x: point.x - 5,
          y: point.y - 5,
          width: 10,
          height: 10
        )
      ),
      with: .color(KaidoTheme.paperRaised),
      lineWidth: 2
    )
  }

  private func scaledPoints(
    _ points: [RouteAtlasPoint],
    size: CGSize
  ) -> [CGPoint] {
    points.map { mapPoint($0, size: size) }
  }

  private func path(for points: [CGPoint]) -> Path {
    Path { path in
      guard let first = points.first else { return }
      path.move(to: first)
      for point in points.dropFirst() {
        path.addLine(to: point)
      }
    }
  }

  private func offsetPoints(
    _ points: [CGPoint],
    occurrence: RouteAtlasJourneyOccurrence
  ) -> [CGPoint] {
    guard occurrence.repeatCount > 1 else { return points }
    let offset =
      (Double(occurrence.repeatOrdinal - 1)
        - Double(occurrence.repeatCount - 1) / 2)
      * 5
    return points.map {
      CGPoint(x: $0.x, y: $0.y + offset)
    }
  }

  private func offsetPoint(
    _ point: CGPoint,
    marker: ProductTopologyMarker,
    size: CGSize
  ) -> CGPoint {
    guard marker.repeatCount > 1 else { return point }
    let offset =
      (Double(marker.repeatOrdinal - 1)
        - Double(marker.repeatCount - 1) / 2)
      * 5
    return CGPoint(
      x: min(max(0, point.x), size.width),
      y: min(max(0, point.y + offset), size.height)
    )
  }

  private func repeatLabelFraction(
    _ occurrence: RouteAtlasJourneyOccurrence
  ) -> Double {
    let centeredOrdinal =
      Double(occurrence.repeatOrdinal - 1)
      - Double(occurrence.repeatCount - 1) / 2
    let step = min(
      0.18,
      0.6 / Double(max(1, occurrence.repeatCount - 1))
    )
    return min(0.82, max(0.18, 0.5 + centeredOrdinal * step))
  }

  private func point(
    along points: [CGPoint],
    fraction: Double
  ) -> CGPoint? {
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
        return CGPoint(
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

  private func color(
    for state: RouteAtlasJourneyOccurrenceState
  ) -> Color {
    switch state {
    case .planned:
      usesDarkStyle ? KaidoTheme.signalAmber : KaidoTheme.routeGreen
    case .passed:
      usesDarkStyle
        ? KaidoTheme.routeWhite.opacity(0.38)
        : KaidoTheme.roadGray
    case .current:
      KaidoTheme.positionCyan
    case .future:
      usesDarkStyle
        ? KaidoTheme.signalAmber.opacity(0.74)
        : KaidoTheme.routeGreen.opacity(0.64)
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
        dash: [6, 5]
      )
    case .planned, .passed, .future:
      StrokeStyle(lineWidth: 5, lineCap: .square, lineJoin: .miter)
    }
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }
}

private struct ProductTopologyLandmarkBadge: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale

  let landmark: ProductTopologyLandmark
  let usesDarkStyle: Bool

  var body: some View {
    HStack(spacing: 5) {
      Text(kindLabel)
        .font(.system(size: 7, weight: .black, design: .rounded))
        .foregroundStyle(.white.opacity(0.86))
        .padding(.horizontal, 4)
        .frame(minHeight: 20)
        .overlay {
          RoundedRectangle(cornerRadius: 3)
            .stroke(.white.opacity(0.72), lineWidth: 1)
        }

      Text(title)
        .font(.system(size: 8.5, weight: .black, design: .rounded))
        .foregroundStyle(.white)
        .lineLimit(2)
        .minimumScaleFactor(0.72)
    }
    .padding(5)
    .frame(width: 148, alignment: .leading)
    .background(KaidoTheme.routeGreen)
    .clipShape(RoundedRectangle(cornerRadius: 5))
    .overlay {
      RoundedRectangle(cornerRadius: 5)
        .stroke(.white.opacity(usesDarkStyle ? 0.82 : 0.96), lineWidth: 1)
    }
    .shadow(
      color: .black.opacity(usesDarkStyle ? 0.34 : 0.16),
      radius: 3,
      y: 2
    )
    .accessibilityElement(children: .ignore)
    .accessibilityIdentifier(
      "product-topology-landmark-\(landmark.kind.rawValue)-\(landmark.id)"
    )
    .accessibilityLabel(accessibilityLabel)
  }

  private var title: String {
    landmark.title.value(for: interfaceLocale)
      ?? landmark.title.value(for: .japanese)
      ?? ""
  }

  private var kindLabel: String {
    switch landmark.kind {
    case .entrance:
      return copy.resolve(
        japanese: "入口",
        simplifiedChinese: "入口",
        english: "IN"
      )
    case .junction:
      return "JCT"
    case .exit:
      return copy.resolve(
        japanese: "出口",
        simplifiedChinese: "出口",
        english: "OUT"
      )
    }
  }

  private var accessibilityLabel: String {
    guard
      let detail = landmark.detail?.value(for: interfaceLocale),
      !detail.isEmpty
    else {
      return "\(kindLabel), \(title)"
    }
    return "\(kindLabel), \(title), \(detail)"
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }
}

struct ProductGeographicMapView: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale

  let presentation: ProductGeographicMapPresentation
  let followsPosition: Bool
  let usesDarkStyle: Bool
  @State private var cameraPosition: MapCameraPosition

  init(
    presentation: ProductGeographicMapPresentation,
    followsPosition: Bool,
    usesDarkStyle: Bool
  ) {
    self.presentation = presentation
    self.followsPosition = followsPosition
    self.usesDarkStyle = usesDarkStyle
    _cameraPosition = State(
      initialValue: .region(Self.fullRouteRegion(for: presentation))
    )
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      Map(
        position: $cameraPosition,
        interactionModes: [.pan, .zoom, .rotate]
      ) {
        ForEach(presentation.paths) { routePath in
          MapPolyline(
            coordinates: routePath.coordinates.map(\.coreLocationCoordinate)
          )
          .stroke(
            usesDarkStyle
              ? KaidoTheme.signalAmber
              : KaidoTheme.routeGreen,
            style: StrokeStyle(
              lineWidth: usesDarkStyle ? 7 : 6,
              lineCap: .round,
              lineJoin: .round
            )
          )
        }

        if let startCoordinate = presentation.startCoordinate {
          Annotation(
            copy.resolve(
              japanese: "青葉入口",
              simplifiedChinese: "青叶入口",
              english: "Aoba entrance"
            ),
            coordinate: startCoordinate.coreLocationCoordinate,
            anchor: .center
          ) {
            endpointMarker("A")
              .accessibilityIdentifier("product-geographic-route-start")
          }
        }

        if let finishCoordinate = presentation.finishCoordinate {
          Annotation(
            copy.resolve(
              japanese: "港北出口",
              simplifiedChinese: "港北出口",
              english: "Kohoku exit"
            ),
            coordinate: finishCoordinate.coreLocationCoordinate,
            anchor: .center
          ) {
            endpointMarker("K")
              .accessibilityIdentifier("product-geographic-route-finish")
          }
        }

        if let marker = presentation.marker {
          Annotation(
            copy.resolve(
              japanese: "現在地",
              simplifiedChinese: "当前位置",
              english: "Current position"
            ),
            coordinate: marker.coordinate.coreLocationCoordinate,
            anchor: .center
          ) {
            ZStack {
              Circle()
                .fill(KaidoTheme.positionCyan.opacity(0.24))
                .frame(width: 34, height: 34)
              Circle()
                .fill(KaidoTheme.positionCyan)
                .frame(width: 18, height: 18)
                .overlay {
                  Circle()
                    .stroke(KaidoTheme.routeWhite, lineWidth: 3)
                }
            }
            .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            .accessibilityIdentifier("product-geographic-position-marker")
            .accessibilityValue(marker.occurrenceID)
          }
        }
      }
      .mapStyle(
        .standard(
          elevation: .flat,
          pointsOfInterest: .excludingAll,
          showsTraffic: false
        )
      )
      .onChange(of: presentation.marker) { _, marker in
        guard followsPosition else { return }
        withAnimation(.easeInOut(duration: 0.4)) {
          cameraPosition =
            marker.map {
              .region(Self.followRegion(for: $0.coordinate))
            }
            ?? .region(Self.fullRouteRegion(for: presentation))
        }
      }

      HStack(spacing: 8) {
        Image(systemName: "map.fill")
        Text(
          copy.resolve(
            japanese: "K7 ルート",
            simplifiedChinese: "K7 路线",
            english: "K7 route"
          )
        )
      }
      .font(.system(size: 10, weight: .black, design: .rounded))
      .foregroundStyle(
        usesDarkStyle ? KaidoTheme.routeWhite : KaidoTheme.ink
      )
      .padding(.horizontal, 10)
      .frame(height: 30)
      .background(.ultraThinMaterial)
      .clipShape(Capsule())
      .padding(10)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("product-geographic-map")
    .accessibilityValue(
      "\(presentation.paths.count) route segments, "
        + "\(presentation.coordinateCount) coordinates, "
        + (presentation.marker == nil ? "route overview" : "position visible")
    )
  }

  private func endpointMarker(_ label: String) -> some View {
    Text(label)
      .font(.system(size: 10, weight: .black, design: .rounded))
      .foregroundStyle(KaidoTheme.routeWhite)
      .frame(width: 24, height: 24)
      .background(KaidoTheme.routeGreenDeep)
      .clipShape(Circle())
      .overlay {
        Circle()
          .stroke(KaidoTheme.routeWhite, lineWidth: 2)
      }
      .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
  }

  private static func fullRouteRegion(
    for presentation: ProductGeographicMapPresentation
  ) -> MKCoordinateRegion {
    let coordinates = presentation.paths.flatMap(\.coordinates)
    guard
      let minimumLatitude = coordinates.map(\.latitude).min(),
      let maximumLatitude = coordinates.map(\.latitude).max(),
      let minimumLongitude = coordinates.map(\.longitude).min(),
      let maximumLongitude = coordinates.map(\.longitude).max()
    else {
      return MKCoordinateRegion(
        center: CLLocationCoordinate2D(
          latitude: 35.53,
          longitude: 139.57
        ),
        span: MKCoordinateSpan(
          latitudeDelta: 0.08,
          longitudeDelta: 0.08
        )
      )
    }
    return MKCoordinateRegion(
      center: CLLocationCoordinate2D(
        latitude: (minimumLatitude + maximumLatitude) * 0.5,
        longitude: (minimumLongitude + maximumLongitude) * 0.5
      ),
      span: MKCoordinateSpan(
        latitudeDelta: max(
          0.012,
          (maximumLatitude - minimumLatitude) * 1.5
        ),
        longitudeDelta: max(
          0.012,
          (maximumLongitude - minimumLongitude) * 1.35
        )
      )
    )
  }

  private static func followRegion(
    for coordinate: ProductMapCoordinate
  ) -> MKCoordinateRegion {
    MKCoordinateRegion(
      center: coordinate.coreLocationCoordinate,
      span: MKCoordinateSpan(
        latitudeDelta: 0.012,
        longitudeDelta: 0.012
      )
    )
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }
}

extension ProductMapCoordinate {
  fileprivate var coreLocationCoordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(
      latitude: latitude,
      longitude: longitude
    )
  }
}
