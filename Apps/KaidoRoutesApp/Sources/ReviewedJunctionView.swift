import KaidoDomain
import KaidoPresentation
import SwiftUI

struct ReviewedJunctionViewCard: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let definition: JunctionViewDefinition
  let iPhone: NavigationSurfacePresentation
  let carPlay: NavigationSurfacePresentation

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header

      JunctionVectorDiagram(
        definition: definition,
        accessibilityText:
          phoneAccessibility.junctionDiagramLabel ?? "无路口示意"
      )
      .frame(height: dynamicTypeSize.isAccessibilitySize ? 250 : 190)

      laneLayout
      surfaceOwnership
      identityFooter
    }
    .padding(14)
    .background(KaidoTheme.asphalt.opacity(0.58))
    .clipShape(RoundedRectangle(cornerRadius: 17))
    .overlay {
      RoundedRectangle(cornerRadius: 17)
        .stroke(KaidoTheme.positionCyan.opacity(0.42), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("reviewed-junction-card")
  }

  @ViewBuilder
  private var header: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: 10) {
        headerText
        routeShields
      }
    } else {
      HStack(alignment: .top, spacing: 12) {
        headerText
        Spacer()
        routeShields
      }
    }
  }

  private var headerText: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text("合成路口示意")
        .font(.system(.headline, design: .rounded, weight: .black))
        .foregroundStyle(KaidoTheme.routeWhite)

      Text("REVIEW CONTRACT · FIXTURE ONLY")
        .font(.system(.caption2, design: .monospaced, weight: .black))
        .tracking(0.55)
        .foregroundStyle(KaidoTheme.positionCyan)

      Text("几何、车道与分支均来自同一不可变定义")
        .font(.subheadline)
        .foregroundStyle(KaidoTheme.muted)
    }
  }

  private var routeShields: some View {
    HStack(spacing: 6) {
      ForEach(Array(definition.routeShields.enumerated()), id: \.offset) {
        index,
        shield in
        Text(verbatim: shield)
          .font(.system(.title3, design: .rounded, weight: .black))
          .foregroundStyle(KaidoTheme.asphalt)
          .padding(.horizontal, 12)
          .frame(minWidth: 44, minHeight: 44)
          .background(KaidoTheme.signalAmber)
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .accessibilityLabel(
            phoneAccessibility.routeShieldLabels[index]
          )
          .accessibilityIdentifier("junction-route-shield-\(index)")
      }
    }
  }

  private var laneLayout: some View {
    VStack(alignment: .leading, spacing: 8) {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 3) {
          laneTitle
          laneLegend
        }
      } else {
        HStack {
          laneTitle
          Spacer()
          laneLegend
        }
      }

      HStack(spacing: 6) {
        ForEach(0..<definition.laneLayout.laneCount, id: \.self) { laneIndex in
          laneCell(laneIndex)
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(phoneAccessibility.junctionLaneLabel ?? "无车道信息")
    .accessibilityIdentifier("junction-lane-layout")
  }

  private var laneTitle: some View {
    Text("车道 · 从左到右")
      .font(.system(.caption, design: .monospaced, weight: .black))
      .foregroundStyle(KaidoTheme.muted)
  }

  private var laneLegend: some View {
    HStack(spacing: 5) {
      Image(systemName: "checkmark.circle.fill")
        .accessibilityHidden(true)
      Text("首选")
      Image(systemName: "arrow.up")
        .accessibilityHidden(true)
      Text("可用")
      Image(systemName: "xmark")
        .accessibilityHidden(true)
      Text("不可用")
    }
    .font(.caption2.weight(.bold))
    .foregroundStyle(KaidoTheme.muted)
  }

  private func laneCell(_ laneIndex: Int) -> some View {
    let isPreferred = definition.laneLayout.preferredLaneIndices.contains(laneIndex)
    let isAllowed = definition.laneLayout.allowedLaneIndices.contains(laneIndex)
    let color =
      isPreferred
      ? KaidoTheme.signalAmber
      : isAllowed ? KaidoTheme.routeWhite : KaidoTheme.steel
    let icon =
      isPreferred
      ? "checkmark.circle.fill"
      : isAllowed ? "arrow.up" : "xmark"

    return VStack(spacing: 4) {
      Image(systemName: icon)
        .font(.headline.weight(.black))

      Text("\(laneIndex + 1)")
        .font(.system(.caption, design: .monospaced, weight: .black))

      if dynamicTypeSize.isAccessibilitySize {
        Text(laneStateLabel(isPreferred: isPreferred, isAllowed: isAllowed))
          .font(.caption2.weight(.bold))
      }
    }
    .foregroundStyle(isAllowed ? KaidoTheme.asphalt : KaidoTheme.routeWhite)
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
    .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 82 : 52)
    .background(color)
    .clipShape(RoundedRectangle(cornerRadius: 9))
  }

  private func laneStateLabel(isPreferred: Bool, isAllowed: Bool) -> String {
    if isPreferred {
      return "首选"
    }
    if isAllowed {
      return "可用"
    }
    return "不可用"
  }

  private var surfaceOwnership: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("共享投影")
          .font(.system(.caption, design: .monospaced, weight: .black))
          .foregroundStyle(KaidoTheme.muted)

        Spacer()

        Text("NO CARPLAY SCENE")
          .font(.system(.caption2, design: .monospaced, weight: .black))
          .foregroundStyle(KaidoTheme.evidenceCoral)
          .accessibilityLabel("仅投影所有权，没有 CarPlay 场景")
          .accessibilityIdentifier("junction-no-carplay-scene")
      }

      if dynamicTypeSize.isAccessibilitySize {
        VStack(spacing: 8) {
          iPhoneOwnership
          carPlayOwnership
        }
      } else {
        HStack(spacing: 8) {
          iPhoneOwnership
          carPlayOwnership
        }
      }
    }
  }

  private var iPhoneOwnership: some View {
    SurfaceOwnershipCell(
      title: "iPhone",
      status: iPhone.isPrimarySurface ? "PRIMARY" : "COMPANION",
      isPrimary: iPhone.isPrimarySurface,
      accessibilityText: phoneAccessibility.surfaceOwnershipLabel,
      accessibilityID: "junction-surface-iphone"
    )
  }

  private var carPlayOwnership: some View {
    SurfaceOwnershipCell(
      title: "CarPlay",
      status: carPlay.isPrimarySurface ? "PRIMARY" : "COMPANION",
      isPrimary: carPlay.isPrimarySurface,
      accessibilityText: carPlayAccessibility.surfaceOwnershipLabel,
      accessibilityID: "junction-surface-carplay"
    )
  }

  private var identityFooter: some View {
    VStack(alignment: .leading, spacing: 6) {
      identityRow(
        title: "CURRENT",
        value: iPhone.currentOccurrenceID ?? "NONE"
      )
      identityRow(
        title: "NEXT MOVEMENT",
        value: iPhone.nextMovementOccurrenceID ?? "NONE"
      )
      identityRow(title: "JCT VIEW", value: definition.id)

      HStack {
        Text(verbatim: definition.evidence.state.rawValue)
          .font(.system(.caption2, design: .monospaced, weight: .black))
          .foregroundStyle(KaidoTheme.positionCyan)

        Text("SYNTHETIC RELEASE-GATE VALUE")
          .font(.system(.caption2, design: .monospaced, weight: .black))
          .foregroundStyle(KaidoTheme.evidenceCoral)
          .accessibilityLabel("合成发布门槛值，不是真实道路发布证据")
          .accessibilityIdentifier("junction-synthetic-evidence-warning")

        Spacer()

        Text(verbatim: definition.evidence.checkedAt)
          .font(.system(.caption2, design: .monospaced, weight: .medium))
          .foregroundStyle(KaidoTheme.muted)
      }
    }
    .padding(10)
    .background(KaidoTheme.instrument.opacity(0.72))
    .clipShape(RoundedRectangle(cornerRadius: 11))
  }

  private func identityRow(title: String, value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(title)
        .font(.system(.caption2, design: .monospaced, weight: .black))
        .foregroundStyle(KaidoTheme.muted)
        .frame(
          width: dynamicTypeSize.isAccessibilitySize ? nil : 88,
          alignment: .leading
        )

      Text(verbatim: value)
        .font(.system(.caption2, design: .monospaced, weight: .medium))
        .foregroundStyle(KaidoTheme.routeWhite)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var phoneAccessibility: NavigationAccessibilityPresentation {
    NavigationAccessibilityProjector.project(
      iPhone,
      locale: .simplifiedChinese
    )
  }

  private var carPlayAccessibility: NavigationAccessibilityPresentation {
    NavigationAccessibilityProjector.project(
      carPlay,
      locale: .simplifiedChinese
    )
  }
}

private struct JunctionVectorDiagram: View {
  let definition: JunctionViewDefinition
  let accessibilityText: String

  var body: some View {
    ZStack(alignment: .top) {
      RoundedRectangle(cornerRadius: 14)
        .fill(KaidoTheme.instrument.opacity(0.82))

      Canvas { context, size in
        for junctionPath in orderedPaths {
          var renderedPath = Path()
          for (index, point) in junctionPath.points.enumerated() {
            let renderedPoint = CGPoint(
              x: point.x * size.width,
              y: point.y * size.height
            )
            if index == 0 {
              renderedPath.move(to: renderedPoint)
            } else {
              renderedPath.addLine(to: renderedPoint)
            }
          }
          context.stroke(
            renderedPath,
            with: .color(pathColor(junctionPath.role)),
            style: StrokeStyle(
              lineWidth: junctionPath.role == .selected ? 10 : 7,
              lineCap: .round,
              lineJoin: .round
            )
          )
        }
        drawSelectedPathMarker(context: context, size: size)
      }
      .padding(.horizontal, 34)
      .padding(.top, 28)
      .padding(.bottom, 16)

      Text(verbatim: definition.japaneseSignText)
        .font(.system(.subheadline, design: .rounded, weight: .black))
        .foregroundStyle(KaidoTheme.routeWhite)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(KaidoTheme.asphalt.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.top, 9)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
    .accessibilityIdentifier("junction-vector-diagram")
  }

  private var orderedPaths: [JunctionViewPath] {
    definition.paths.sorted { roleRank($0.role) < roleRank($1.role) }
  }

  private func roleRank(_ role: JunctionViewPathRole) -> Int {
    switch role {
    case .approach:
      0
    case .alternative:
      1
    case .selected:
      2
    }
  }

  private func pathColor(_ role: JunctionViewPathRole) -> Color {
    switch role {
    case .approach:
      KaidoTheme.routeWhite.opacity(0.72)
    case .alternative:
      KaidoTheme.steel
    case .selected:
      KaidoTheme.signalAmber
    }
  }

  private func drawSelectedPathMarker(
    context: GraphicsContext,
    size: CGSize
  ) {
    guard
      let endpoint = definition.paths.first(where: { $0.role == .selected })?
        .points.last
    else {
      return
    }
    let renderedPoint = CGPoint(
      x: endpoint.x * size.width,
      y: endpoint.y * size.height
    )
    let markerRect = CGRect(
      x: renderedPoint.x - 11,
      y: renderedPoint.y - 11,
      width: 22,
      height: 22
    )
    context.fill(
      Path(ellipseIn: markerRect),
      with: .color(KaidoTheme.signalAmber)
    )
    context.draw(
      Text("✓")
        .font(.caption.weight(.black))
        .foregroundStyle(KaidoTheme.asphalt),
      at: renderedPoint
    )
  }
}

private struct SurfaceOwnershipCell: View {
  let title: String
  let status: String
  let isPrimary: Bool
  let accessibilityText: String
  let accessibilityID: String

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.system(.subheadline, design: .rounded, weight: .black))
        .foregroundStyle(KaidoTheme.routeWhite)

      Text(verbatim: status)
        .font(.system(.caption, design: .monospaced, weight: .black))
        .foregroundStyle(
          isPrimary ? KaidoTheme.positionCyan : KaidoTheme.muted
        )
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .background(
      isPrimary
        ? KaidoTheme.positionCyan.opacity(0.12)
        : KaidoTheme.instrument
    )
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay {
      RoundedRectangle(cornerRadius: 10)
        .stroke(
          isPrimary
            ? KaidoTheme.positionCyan.opacity(0.55)
            : KaidoTheme.steel,
          lineWidth: 1
        )
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityText)
    .accessibilityIdentifier(accessibilityID)
  }
}
