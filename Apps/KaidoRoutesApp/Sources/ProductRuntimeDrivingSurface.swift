import Foundation
import KaidoPresentation
import SwiftUI

/// Renders only the projection produced from one actor-owned runtime update.
///
/// The view has no route progress, guidance, lane, sign, or speech policy of
/// its own. Its input remains synthetic until a real joint product release and
/// device-qualified location pipeline exist.
struct ProductRuntimeDrivingSurface: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let projection: NavigationPresentationProjection

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      guidance

      if let junctionView = phone.junctionView {
        ReviewedJunctionViewCard(
          definition: junctionView,
          iPhone: phone,
          carPlay: projection.carPlay
        )
      }

      statusRows

      if let finishDrive = phone.finishDrive {
        finishDriveNotice(finishDrive)
      }
    }
    .padding(13)
    .background(KaidoTheme.asphalt.opacity(0.48))
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .overlay {
      RoundedRectangle(cornerRadius: 16)
        .stroke(KaidoTheme.positionCyan.opacity(0.42), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("product-runtime-driving-surface")
    .accessibilityValue(
      [
        phone.currentOccurrenceID ?? "NO_CURRENT_OCCURRENCE",
        phone.nextMovementOccurrenceID ?? "NO_NEXT_MOVEMENT",
        phone.guidancePromptID,
        projection.voice.shouldSpeak ? "VOICE_EVENT" : "VISUAL_UPDATE",
      ].joined(separator: " | ")
    )
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        Text("Actor 导航画面")
          .font(.system(.headline, design: .rounded, weight: .black))
          .foregroundStyle(KaidoTheme.routeWhite)

        Text("ONE UPDATE · PHONE + CARPLAY + VOICE")
          .font(.system(.caption2, design: .monospaced, weight: .black))
          .tracking(0.5)
          .foregroundStyle(KaidoTheme.positionCyan)
      }

      Spacer()

      StatusCapsule(
        title: projection.voice.shouldSpeak ? "VOICE EVENT" : "VISUAL UPDATE",
        color: projection.voice.shouldSpeak
          ? KaidoTheme.signalAmber
          : KaidoTheme.positionCyan
      )
    }
  }

  @ViewBuilder
  private var guidance: some View {
    let accessibility = NavigationAccessibilityProjector.project(
      phone,
      locale: projection.interfaceLocale
    )

    VStack(alignment: .leading, spacing: 11) {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 9) {
          routeShield(accessibility)
          guidanceText
          distanceAndStage
        }
      } else {
        HStack(alignment: .top, spacing: 11) {
          routeShield(accessibility)
          guidanceText
          Spacer(minLength: 2)
          distanceAndStage
        }
      }

      Divider()
        .overlay(KaidoTheme.steel)

      VStack(alignment: .leading, spacing: 4) {
        Label(
          phone.localizedDecisionPointName,
          systemImage: "arrow.triangle.branch"
        )
        .font(.subheadline.weight(.bold))
        .foregroundStyle(KaidoTheme.routeWhite)

        Text(verbatim: phone.nextMovementOccurrenceID ?? "NO MOVEMENT")
          .font(.system(.caption2, design: .monospaced, weight: .medium))
          .foregroundStyle(KaidoTheme.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(12)
    .background(KaidoTheme.instrument.opacity(0.72))
    .clipShape(RoundedRectangle(cornerRadius: 13))
    .accessibilityElement(children: .contain)
    .accessibilityLabel(accessibility.guidanceLabel)
    .accessibilityIdentifier("product-runtime-driving-guidance")
  }

  private func routeShield(
    _ accessibility: NavigationAccessibilityPresentation
  ) -> some View {
    Text(phone.routeShields.first ?? "—")
      .font(.system(.title2, design: .rounded, weight: .black))
      .foregroundStyle(KaidoTheme.asphalt)
      .padding(.horizontal, 13)
      .frame(minWidth: 46, minHeight: 44)
      .background(KaidoTheme.signalAmber)
      .clipShape(RoundedRectangle(cornerRadius: 9))
      .accessibilityLabel(
        accessibility.routeShieldLabels.first ?? "路线盾牌未知"
      )
      .accessibilityIdentifier("product-runtime-driving-route-shield")
  }

  private var guidanceText: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(verbatim: phone.japaneseSignText)
        .font(.system(.headline, design: .rounded, weight: .black))
        .foregroundStyle(KaidoTheme.routeWhite)
        .fixedSize(horizontal: false, vertical: true)

      Text(phone.localizedDisplayText)
        .font(.subheadline.weight(.bold))
        .foregroundStyle(KaidoTheme.muted)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var distanceAndStage: some View {
    VStack(
      alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing,
      spacing: 2
    ) {
      Text(distanceLabel(phone.distanceMeters))
        .font(.system(.title3, design: .rounded, weight: .black))
        .foregroundStyle(KaidoTheme.routeWhite)

      Text(verbatim: phone.guidanceStage.rawValue)
        .font(.system(.caption2, design: .monospaced, weight: .black))
        .foregroundStyle(KaidoTheme.signalAmber)
    }
  }

  private var statusRows: some View {
    VStack(spacing: 7) {
      statusRow(
        title: "位置呈现",
        value: markerLabel,
        detail: phone.marker.rawValue,
        color: phone.marker == .measured
          ? KaidoTheme.positionCyan
          : KaidoTheme.signalAmber,
        accessibilityID: "product-runtime-driving-marker"
      )
      statusRow(
        title: "实时通行",
        value: passageLabel,
        detail: phone.passage.evidence.rawValue,
        color: phone.passage.usesPositiveOpenColor
          ? KaidoTheme.confirmedGreen
          : KaidoTheme.signalAmber,
        accessibilityID: "product-runtime-driving-passage"
      )
      statusRow(
        title: "路线编辑",
        value: editingLabel,
        detail: phone.requiresPhoneTouchWhileMoving
          ? "PHONE TOUCH REQUIRED"
          : "NO PHONE TOUCH",
        color: phone.routeEditingAvailability == .availableWhileParked
          ? KaidoTheme.confirmedGreen
          : KaidoTheme.evidenceCoral,
        accessibilityID: "product-runtime-driving-editing"
      )
    }
  }

  private func statusRow(
    title: String,
    value: String,
    detail: String,
    color: Color,
    accessibilityID: String
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(title)
        .font(.system(.caption, design: .monospaced, weight: .bold))
        .foregroundStyle(KaidoTheme.muted)

      Text(value)
        .font(.subheadline.weight(.black))
        .foregroundStyle(color)

      Spacer()

      Text(verbatim: detail)
        .font(.system(.caption2, design: .monospaced, weight: .bold))
        .foregroundStyle(KaidoTheme.muted)
        .multilineTextAlignment(.trailing)
    }
    .padding(10)
    .background(KaidoTheme.instrument.opacity(0.64))
    .clipShape(RoundedRectangle(cornerRadius: 11))
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(accessibilityID)
    .accessibilityValue(detail)
  }

  private func finishDriveNotice(
    _ finishDrive: FinishDrivePresentation
  ) -> some View {
    Label(
      "先确认结束出口：\(finishDrive.localizedExitName)",
      systemImage: "door.left.hand.open"
    )
    .font(.subheadline.weight(.bold))
    .foregroundStyle(KaidoTheme.signalAmber)
    .padding(11)
    .background(KaidoTheme.signalAmber.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 11))
  }

  private var phone: NavigationSurfacePresentation {
    projection.iPhone
  }

  private var markerLabel: String {
    switch phone.marker {
    case .measured:
      "测量位置"
    case .estimated:
      "估算位置"
    case .unresolved:
      "位置未解析"
    }
  }

  private var passageLabel: String {
    switch phone.passage.tone {
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

  private var editingLabel: String {
    switch phone.routeEditingAvailability {
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
