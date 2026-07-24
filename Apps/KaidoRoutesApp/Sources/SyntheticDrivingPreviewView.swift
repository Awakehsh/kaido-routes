import KaidoDomain
import KaidoPresentation
import SwiftUI

struct SyntheticDrivingPreviewPanel: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ObservedObject var model: SyntheticDrivingPreviewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header
      stateSelector
      guidanceCard

      if let junctionView = model.state.projection.iPhone.junctionView {
        ReviewedJunctionViewCard(
          definition: junctionView,
          iPhone: model.state.projection.iPhone,
          carPlay: model.state.projection.carPlay
        )
      }

      safetyGrid

      if let finishDrive = model.state.projection.iPhone.finishDrive {
        finishDriveCard(finishDrive)
      }

      if let lastErrorCode = model.lastErrorCode {
        Text(verbatim: lastErrorCode)
          .font(.system(size: 9, weight: .bold, design: .monospaced))
          .foregroundStyle(KaidoTheme.evidenceCoral)
          .accessibilityLabel("驾驶预览错误：\(lastErrorCode)")
      }
    }
    .padding(16)
    .background(KaidoTheme.instrument)
    .clipShape(RoundedRectangle(cornerRadius: 22))
    .overlay {
      RoundedRectangle(cornerRadius: 22)
        .stroke(KaidoTheme.positionCyan.opacity(0.35), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("kr-u09-driving-panel")
    .accessibilityValue(layoutMode.rawValue)
  }

  @ViewBuilder
  private var header: some View {
    if layoutMode == .accessibility {
      VStack(alignment: .leading, spacing: 10) {
        headerText
        StatusCapsule(
          title: "NO LIVE DATA",
          color: KaidoTheme.positionCyan
        )
      }
    } else {
      HStack(alignment: .top) {
        headerText
        Spacer()
        StatusCapsule(
          title: "NO LIVE DATA",
          color: KaidoTheme.positionCyan
        )
      }
    }
  }

  private var headerText: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text("行驶状态")
        .font(.system(.title3, design: .rounded, weight: .black))
        .foregroundStyle(KaidoTheme.routeWhite)

      Text("DRIVING SURFACE · SYNTHETIC")
        .font(.system(.caption, design: .monospaced, weight: .bold))
        .tracking(0.75)
        .foregroundStyle(KaidoTheme.muted)

      Text("仅执行投影合同，不接入实时定位或导航")
        .font(.subheadline)
        .foregroundStyle(KaidoTheme.muted)
    }
  }

  private var stateSelector: some View {
    LazyVGrid(
      columns: Array(
        repeating: GridItem(.flexible(), spacing: 6),
        count: KaidoAccessibilityLayoutPolicy.selectorColumnCount(
          for: dynamicTypeSize
        )
      ),
      spacing: 6
    ) {
      ForEach(SyntheticDrivingPreviewCase.allCases) { previewCase in
        Button {
          model.select(previewCase)
        } label: {
          Text(caseLabel(previewCase))
            .font(.headline)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .frame(minHeight: 48)
            .foregroundStyle(
              model.selectedCase == previewCase
                ? KaidoTheme.asphalt
                : KaidoTheme.muted
            )
            .background(
              model.selectedCase == previewCase
                ? caseAccent(previewCase)
                : KaidoTheme.asphalt.opacity(0.55)
            )
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(
          model.selectedCase == previewCase ? .isSelected : []
        )
        .accessibilityLabel("合成驾驶状态：\(caseAccessibilityLabel(previewCase))")
        .accessibilityIdentifier("driving-state-\(previewCase.rawValue.lowercased())")
      }
    }
  }

  @ViewBuilder
  private var guidanceCard: some View {
    let presentation = model.state.projection.iPhone
    let accessibility = accessibilityPresentation

    VStack(alignment: .leading, spacing: 13) {
      if layoutMode == .accessibility {
        VStack(alignment: .leading, spacing: 10) {
          routeShieldBadge(presentation, accessibility: accessibility)
          guidanceText(presentation)
          distanceAndStage(presentation)
        }
      } else {
        HStack(alignment: .top, spacing: 12) {
          routeShieldBadge(presentation, accessibility: accessibility)
          guidanceText(presentation)
          Spacer(minLength: 2)
          distanceAndStage(presentation)
        }
      }

      Divider()
        .overlay(KaidoTheme.steel)

      if layoutMode == .accessibility {
        VStack(alignment: .leading, spacing: 5) {
          decisionPoint(presentation)
          occurrenceID(presentation)
        }
      } else {
        HStack {
          decisionPoint(presentation)
          Spacer()
          occurrenceID(presentation)
        }
      }
    }
    .padding(14)
    .background(KaidoTheme.asphalt.opacity(0.55))
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .accessibilityElement(children: .contain)
    .accessibilityLabel(accessibility.guidanceLabel)
    .accessibilityIdentifier("driving-guidance-card")
  }

  private func routeShieldBadge(
    _ presentation: NavigationSurfacePresentation,
    accessibility: NavigationAccessibilityPresentation
  ) -> some View {
    Text(presentation.routeShields.first ?? "—")
      .font(.system(.title2, design: .rounded, weight: .black))
      .foregroundStyle(KaidoTheme.asphalt)
      .padding(.horizontal, 14)
      .frame(minWidth: 48, minHeight: 44)
      .background(KaidoTheme.signalAmber)
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .accessibilityLabel(
        accessibility.routeShieldLabels.first ?? "路线盾牌未知"
      )
      .accessibilityIdentifier("driving-route-shield")
  }

  private func guidanceText(
    _ presentation: NavigationSurfacePresentation
  ) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(verbatim: presentation.japaneseSignText)
        .font(.system(.headline, design: .rounded, weight: .black))
        .foregroundStyle(KaidoTheme.routeWhite)
        .fixedSize(horizontal: false, vertical: true)

      Text(presentation.localizedDisplayText)
        .font(.subheadline.weight(.bold))
        .foregroundStyle(KaidoTheme.muted)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func distanceAndStage(
    _ presentation: NavigationSurfacePresentation
  ) -> some View {
    VStack(
      alignment: layoutMode == .accessibility ? .leading : .trailing,
      spacing: 2
    ) {
      Text(distanceLabel(presentation.distanceMeters))
        .font(.system(.title3, design: .rounded, weight: .black))
        .foregroundStyle(KaidoTheme.routeWhite)

      Text(verbatim: presentation.guidanceStage.rawValue)
        .font(.system(.caption2, design: .monospaced, weight: .black))
        .foregroundStyle(KaidoTheme.signalAmber)
    }
  }

  private func decisionPoint(
    _ presentation: NavigationSurfacePresentation
  ) -> some View {
    Label(
      presentation.localizedDecisionPointName,
      systemImage: "arrow.triangle.branch"
    )
    .font(.subheadline.weight(.bold))
    .foregroundStyle(KaidoTheme.routeWhite)
  }

  private func occurrenceID(
    _ presentation: NavigationSurfacePresentation
  ) -> some View {
    Text(verbatim: presentation.nextMovementOccurrenceID ?? "NO MOVEMENT")
      .font(.system(.caption2, design: .monospaced, weight: .medium))
      .foregroundStyle(KaidoTheme.muted)
      .lineLimit(layoutMode == .accessibility ? 2 : 1)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var accessibilityPresentation: NavigationAccessibilityPresentation {
    NavigationAccessibilityProjector.project(
      model.state.projection.iPhone,
      locale: .simplifiedChinese
    )
  }

  private var layoutMode: KaidoAccessibilityLayoutMode {
    KaidoAccessibilityLayoutPolicy.mode(for: dynamicTypeSize)
  }

  private var safetyGrid: some View {
    VStack(spacing: 8) {
      markerRow
      passageRow
      editingRow
    }
  }

  private var markerRow: some View {
    let marker = model.state.projection.iPhone.marker
    return SafetyStatusRow(
      icon: markerIcon(marker),
      title: "位置呈现",
      value: markerLabel(marker),
      detail: markerDetail(marker),
      color: markerColor(marker),
      dashed: marker != .measured,
      accessibilityText: accessibilityPresentation.markerLabel,
      accessibilityID: "driving-marker-status"
    )
  }

  private var passageRow: some View {
    let passage = model.state.projection.iPhone.passage
    return SafetyStatusRow(
      icon: passage.usesPositiveOpenColor ? "checkmark.shield.fill" : "questionmark.diamond",
      title: "实时通行",
      value: passageLabel(passage.tone),
      detail: passage.evidence.rawValue,
      color: passage.usesPositiveOpenColor
        ? KaidoTheme.confirmedGreen
        : KaidoTheme.signalAmber,
      accessibilityText: accessibilityPresentation.passageLabel,
      accessibilityID: "driving-passage-status"
    )
  }

  private var editingRow: some View {
    let presentation = model.state.projection.iPhone
    return SafetyStatusRow(
      icon: "hand.raised.fill",
      title: "路线编辑",
      value: editingLabel(presentation.routeEditingAvailability),
      detail: presentation.requiresPhoneTouchWhileMoving
        ? "需要触碰手机"
        : "无需触碰手机",
      color: presentation.routeEditingAvailability == .availableWhileParked
        ? KaidoTheme.confirmedGreen
        : KaidoTheme.evidenceCoral,
      accessibilityText: accessibilityPresentation.routeEditingLabel,
      accessibilityID: "driving-editing-status"
    )
  }

  private func finishDriveCard(_ finishDrive: FinishDrivePresentation) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("先确认结束出口")
            .font(.system(.caption, design: .monospaced, weight: .black))
            .tracking(0.5)
            .foregroundStyle(KaidoTheme.signalAmber)

          Text(finishDrive.localizedExitName)
            .font(.system(.title3, design: .rounded, weight: .black))
            .foregroundStyle(KaidoTheme.routeWhite)
        }

        Spacer()

        Image(systemName: "door.left.hand.open")
          .font(.title2.weight(.bold))
          .foregroundStyle(KaidoTheme.signalAmber)
      }

      Text("BEFORE BRANCH GUIDANCE")
        .font(.system(.caption, design: .monospaced, weight: .black))
        .foregroundStyle(KaidoTheme.muted)

      Label("禁止掉头、倒车或反向行驶", systemImage: "arrow.uturn.backward.circle.fill")
        .font(.subheadline.weight(.bold))
        .foregroundStyle(KaidoTheme.evidenceCoral)
    }
    .padding(14)
    .background(KaidoTheme.signalAmber.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 15))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "结束驾驶先确认出口：\(finishDrive.localizedExitName)。"
        + "随后才提供分支引导。禁止掉头、倒车或反向行驶。"
    )
  }

  private func caseLabel(_ previewCase: SyntheticDrivingPreviewCase) -> String {
    switch previewCase {
    case .measuredReference:
      "测量\n参考"
    case .degradedDecisionZone:
      "降级\n决策区"
    case .reviewedJunctionHandoff:
      "路口\n跨屏投影"
    case .finishDrive:
      "结束\n驾驶"
    }
  }

  private func caseAccessibilityLabel(
    _ previewCase: SyntheticDrivingPreviewCase
  ) -> String {
    switch previewCase {
    case .measuredReference:
      "高置信度测量参考"
    case .degradedDecisionZone:
      "低置信度决策区"
    case .reviewedJunctionHandoff:
      "共享 occurrence 的审查路口投影"
    case .finishDrive:
      "结束驾驶并选择预计算出口"
    }
  }

  private func caseAccent(_ previewCase: SyntheticDrivingPreviewCase) -> Color {
    switch previewCase {
    case .measuredReference:
      KaidoTheme.positionCyan
    case .degradedDecisionZone:
      KaidoTheme.signalAmber
    case .reviewedJunctionHandoff:
      KaidoTheme.positionCyan
    case .finishDrive:
      KaidoTheme.evidenceCoral
    }
  }

  private func markerIcon(_ marker: NavigationMarkerPresentation) -> String {
    switch marker {
    case .measured:
      "location.fill"
    case .estimated:
      "location"
    case .unresolved:
      "location.slash"
    }
  }

  private func markerLabel(_ marker: NavigationMarkerPresentation) -> String {
    switch marker {
    case .measured:
      "测量位置"
    case .estimated:
      "估算位置"
    case .unresolved:
      "位置未解析"
    }
  }

  private func markerDetail(_ marker: NavigationMarkerPresentation) -> String {
    switch marker {
    case .measured:
      "HIGH · MEASURED"
    case .estimated:
      "LOW · ESTIMATED"
    case .unresolved:
      "AMBIGUOUS · UNRESOLVED"
    }
  }

  private func markerColor(_ marker: NavigationMarkerPresentation) -> Color {
    switch marker {
    case .measured:
      KaidoTheme.positionCyan
    case .estimated:
      KaidoTheme.signalAmber
    case .unresolved:
      KaidoTheme.evidenceCoral
    }
  }

  private func passageLabel(_ tone: RoutePassagePresentationTone) -> String {
    switch tone {
    case .blocked:
      "已知封闭"
    case .warning:
      "存在计划冲突"
    case .unconfirmed:
      "尚未确认"
    case .confirmedPassable:
      "已确认可通行"
    }
  }

  private func editingLabel(_ availability: RouteEditingAvailability) -> String {
    switch availability {
    case .availableWhileParked:
      "停车时可编辑"
    case .unavailableWhileMoving:
      "行驶中不可编辑"
    case .unavailableInDecisionZone:
      "决策区不可编辑"
    case .lockedForActiveDrive:
      "活动行程已锁定"
    }
  }

  private func distanceLabel(_ meters: Double) -> String {
    if meters >= 1_000 {
      return String(format: "%.1f km", meters / 1_000)
    }
    return "\(Int(meters.rounded())) m"
  }
}

private struct SafetyStatusRow: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let icon: String
  let title: String
  let value: String
  let detail: String
  let color: Color
  var dashed = false
  let accessibilityText: String
  let accessibilityID: String

  @ViewBuilder
  var body: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 12) {
          statusIcon
          statusText
        }
        detailText
      }
      .modifier(
        SafetyStatusRowSurface(
          accessibilityText: accessibilityText,
          accessibilityID: accessibilityID
        )
      )
    } else {
      HStack(spacing: 12) {
        statusIcon
        statusText
        Spacer()
        detailText
      }
      .modifier(
        SafetyStatusRowSurface(
          accessibilityText: accessibilityText,
          accessibilityID: accessibilityID
        )
      )
    }
  }

  private var statusIcon: some View {
    Image(systemName: icon)
      .font(.headline.weight(.bold))
      .foregroundStyle(color)
      .frame(width: 38, height: 38)
      .overlay {
        Circle()
          .stroke(
            color.opacity(0.7),
            style: StrokeStyle(
              lineWidth: 1.5,
              dash: dashed ? [3, 3] : []
            )
          )
      }
      .accessibilityHidden(true)
  }

  private var statusText: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.system(.caption, design: .monospaced, weight: .bold))
        .foregroundStyle(KaidoTheme.muted)

      Text(value)
        .font(.headline.weight(.black))
        .foregroundStyle(color)
    }
  }

  private var detailText: some View {
    Text(verbatim: detail)
      .font(.system(.caption2, design: .monospaced, weight: .medium))
      .foregroundStyle(KaidoTheme.muted)
      .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
      .fixedSize(horizontal: false, vertical: true)
  }
}

private struct SafetyStatusRowSurface: ViewModifier {
  let accessibilityText: String
  let accessibilityID: String

  func body(content: Content) -> some View {
    content
      .padding(11)
      .background(KaidoTheme.asphalt.opacity(0.42))
      .clipShape(RoundedRectangle(cornerRadius: 13))
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(accessibilityText)
      .accessibilityIdentifier(accessibilityID)
  }
}
