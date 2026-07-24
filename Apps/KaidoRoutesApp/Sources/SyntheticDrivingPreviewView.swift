import KaidoDomain
import KaidoPresentation
import SwiftUI

struct SyntheticDrivingPreviewPanel: View {
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
  }

  private var header: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 3) {
        Text("行驶状态")
          .font(.system(size: 19, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)

        Text("DRIVING SURFACE · SYNTHETIC")
          .font(.system(size: 9, weight: .bold, design: .monospaced))
          .tracking(0.75)
          .foregroundStyle(KaidoTheme.muted)

        Text("仅执行投影合同，不接入实时定位或导航")
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(KaidoTheme.muted)
      }

      Spacer()

      StatusCapsule(
        title: "NO LIVE DATA",
        color: KaidoTheme.positionCyan
      )
    }
  }

  private var stateSelector: some View {
    LazyVGrid(
      columns: [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
      ],
      spacing: 6
    ) {
      ForEach(SyntheticDrivingPreviewCase.allCases) { previewCase in
        Button {
          model.select(previewCase)
        } label: {
          Text(caseLabel(previewCase))
            .font(.system(size: 9, weight: .bold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
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
      }
    }
  }

  private var guidanceCard: some View {
    let presentation = model.state.projection.iPhone
    return VStack(alignment: .leading, spacing: 13) {
      HStack(alignment: .top, spacing: 12) {
        Text(presentation.routeShields.first ?? "—")
          .font(.system(size: 20, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.asphalt)
          .frame(width: 48, height: 38)
          .background(KaidoTheme.signalAmber)
          .clipShape(RoundedRectangle(cornerRadius: 10))
          .accessibilityLabel(
            "路线盾牌 \(presentation.routeShields.first ?? "未知")"
          )

        VStack(alignment: .leading, spacing: 3) {
          Text(verbatim: presentation.japaneseSignText)
            .font(.system(size: 17, weight: .black, design: .rounded))
            .foregroundStyle(KaidoTheme.routeWhite)

          Text(presentation.localizedDisplayText)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(KaidoTheme.muted)
        }

        Spacer(minLength: 2)

        VStack(alignment: .trailing, spacing: 2) {
          Text(distanceLabel(presentation.distanceMeters))
            .font(.system(size: 18, weight: .black, design: .rounded))
            .foregroundStyle(KaidoTheme.routeWhite)

          Text(verbatim: presentation.guidanceStage.rawValue)
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .foregroundStyle(KaidoTheme.signalAmber)
        }
      }

      Divider()
        .overlay(KaidoTheme.steel)

      HStack {
        Label(
          presentation.localizedDecisionPointName,
          systemImage: "arrow.triangle.branch"
        )
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(KaidoTheme.routeWhite)

        Spacer()

        Text(verbatim: presentation.nextMovementOccurrenceID ?? "NO MOVEMENT")
          .font(.system(size: 8, weight: .medium, design: .monospaced))
          .foregroundStyle(KaidoTheme.muted)
          .lineLimit(1)
      }
    }
    .padding(14)
    .background(KaidoTheme.asphalt.opacity(0.55))
    .clipShape(RoundedRectangle(cornerRadius: 16))
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
      dashed: marker != .measured
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
        : KaidoTheme.signalAmber
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
        : KaidoTheme.evidenceCoral
    )
  }

  private func finishDriveCard(_ finishDrive: FinishDrivePresentation) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("先确认结束出口")
            .font(.system(size: 9, weight: .black, design: .monospaced))
            .tracking(0.5)
            .foregroundStyle(KaidoTheme.signalAmber)

          Text(finishDrive.localizedExitName)
            .font(.system(size: 20, weight: .black, design: .rounded))
            .foregroundStyle(KaidoTheme.routeWhite)
        }

        Spacer()

        Image(systemName: "door.left.hand.open")
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(KaidoTheme.signalAmber)
      }

      Text("BEFORE BRANCH GUIDANCE")
        .font(.system(size: 9, weight: .black, design: .monospaced))
        .foregroundStyle(KaidoTheme.muted)

      Label("禁止掉头、倒车或反向行驶", systemImage: "arrow.uturn.backward.circle.fill")
        .font(.system(size: 11, weight: .bold))
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
  let icon: String
  let title: String
  let value: String
  let detail: String
  let color: Color
  var dashed = false

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(color)
        .frame(width: 34, height: 34)
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

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 9, weight: .bold, design: .monospaced))
          .foregroundStyle(KaidoTheme.muted)

        Text(value)
          .font(.system(size: 13, weight: .black))
          .foregroundStyle(color)
      }

      Spacer()

      Text(verbatim: detail)
        .font(.system(size: 8, weight: .medium, design: .monospaced))
        .foregroundStyle(KaidoTheme.muted)
        .multilineTextAlignment(.trailing)
    }
    .padding(11)
    .background(KaidoTheme.asphalt.opacity(0.42))
    .clipShape(RoundedRectangle(cornerRadius: 13))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(title)：\(value)。\(detail)")
  }
}
