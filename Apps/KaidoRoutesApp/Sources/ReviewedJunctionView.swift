import KaidoDomain
import KaidoPresentation
import SwiftUI

struct ReviewedJunctionViewCard: View {
  let definition: JunctionViewDefinition
  let iPhone: NavigationSurfacePresentation
  let carPlay: NavigationSurfacePresentation

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header

      JunctionVectorDiagram(definition: definition)
        .frame(height: 190)

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
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text("合成路口示意")
          .font(.system(size: 15, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)

        Text("REVIEW CONTRACT · FIXTURE ONLY")
          .font(.system(size: 8, weight: .black, design: .monospaced))
          .tracking(0.55)
          .foregroundStyle(KaidoTheme.positionCyan)

        Text("几何、车道与分支均来自同一不可变定义")
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(KaidoTheme.muted)
      }

      Spacer()

      HStack(spacing: 6) {
        ForEach(definition.routeShields, id: \.self) { shield in
          Text(verbatim: shield)
            .font(.system(size: 14, weight: .black, design: .rounded))
            .foregroundStyle(KaidoTheme.asphalt)
            .frame(width: 36, height: 30)
            .background(KaidoTheme.signalAmber)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("路线盾牌 \(shield)")
        }
      }
    }
  }

  private var laneLayout: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("车道 · 从左到右")
          .font(.system(size: 9, weight: .black, design: .monospaced))
          .foregroundStyle(KaidoTheme.muted)

        Spacer()

        Text("黄色 = 首选 · 白色 = 可用")
          .font(.system(size: 8, weight: .medium))
          .foregroundStyle(KaidoTheme.muted)
      }

      HStack(spacing: 6) {
        ForEach(0..<definition.laneLayout.laneCount, id: \.self) { laneIndex in
          laneCell(laneIndex)
        }
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(laneAccessibilityLabel)
  }

  private func laneCell(_ laneIndex: Int) -> some View {
    let isPreferred = definition.laneLayout.preferredLaneIndices.contains(laneIndex)
    let isAllowed = definition.laneLayout.allowedLaneIndices.contains(laneIndex)
    let color =
      isPreferred
      ? KaidoTheme.signalAmber
      : isAllowed ? KaidoTheme.routeWhite : KaidoTheme.steel

    return VStack(spacing: 4) {
      Image(systemName: isAllowed ? "arrow.up" : "xmark")
        .font(.system(size: 13, weight: .black))

      Text("\(laneIndex + 1)")
        .font(.system(size: 9, weight: .black, design: .monospaced))
    }
    .foregroundStyle(isAllowed ? KaidoTheme.asphalt : KaidoTheme.muted)
    .frame(maxWidth: .infinity)
    .frame(height: 46)
    .background(color)
    .clipShape(RoundedRectangle(cornerRadius: 9))
  }

  private var surfaceOwnership: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("共享投影")
          .font(.system(size: 9, weight: .black, design: .monospaced))
          .foregroundStyle(KaidoTheme.muted)

        Spacer()

        Text("NO CARPLAY SCENE")
          .font(.system(size: 8, weight: .black, design: .monospaced))
          .foregroundStyle(KaidoTheme.evidenceCoral)
      }

      HStack(spacing: 8) {
        SurfaceOwnershipCell(
          title: "iPhone",
          status: iPhone.isPrimarySurface ? "PRIMARY" : "COMPANION",
          isPrimary: iPhone.isPrimarySurface
        )
        SurfaceOwnershipCell(
          title: "CarPlay",
          status: carPlay.isPrimarySurface ? "PRIMARY" : "COMPANION",
          isPrimary: carPlay.isPrimarySurface
        )
      }
    }
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
          .font(.system(size: 8, weight: .black, design: .monospaced))
          .foregroundStyle(KaidoTheme.positionCyan)

        Text("SYNTHETIC RELEASE-GATE VALUE")
          .font(.system(size: 8, weight: .black, design: .monospaced))
          .foregroundStyle(KaidoTheme.evidenceCoral)

        Spacer()

        Text(verbatim: definition.evidence.checkedAt)
          .font(.system(size: 8, weight: .medium, design: .monospaced))
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
        .font(.system(size: 8, weight: .black, design: .monospaced))
        .foregroundStyle(KaidoTheme.muted)
        .frame(width: 88, alignment: .leading)

      Text(verbatim: value)
        .font(.system(size: 8, weight: .medium, design: .monospaced))
        .foregroundStyle(KaidoTheme.routeWhite)
        .lineLimit(1)
    }
  }

  private var laneAccessibilityLabel: String {
    let allowed = definition.laneLayout.allowedLaneIndices.map { String($0 + 1) }
      .joined(separator: "、")
    let preferred = definition.laneLayout.preferredLaneIndices.map { String($0 + 1) }
      .joined(separator: "、")
    return
      "共 \(definition.laneLayout.laneCount) 条车道，从左到右编号。"
      + "可用车道 \(allowed)，首选车道 \(preferred)。"
  }
}

private struct JunctionVectorDiagram: View {
  let definition: JunctionViewDefinition

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
      }
      .padding(.horizontal, 34)
      .padding(.top, 28)
      .padding(.bottom, 16)

      Text(verbatim: definition.japaneseSignText)
        .font(.system(size: 11, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.routeWhite)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(KaidoTheme.asphalt.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.top, 9)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "审查路口矢量示意。日文标志目标：\(definition.japaneseSignText)。"
        + "高亮分支来自 \(selectedPathID)。"
    )
  }

  private var orderedPaths: [JunctionViewPath] {
    definition.paths.sorted { roleRank($0.role) < roleRank($1.role) }
  }

  private var selectedPathID: String {
    definition.paths.first(where: { $0.role == .selected })?.id ?? "NONE"
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
}

private struct SurfaceOwnershipCell: View {
  let title: String
  let status: String
  let isPrimary: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.system(size: 10, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.routeWhite)

      Text(verbatim: status)
        .font(.system(size: 8, weight: .black, design: .monospaced))
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
    .accessibilityLabel("\(title) 投影状态：\(status)")
  }
}
