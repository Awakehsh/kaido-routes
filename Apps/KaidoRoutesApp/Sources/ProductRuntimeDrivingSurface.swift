import Foundation
import KaidoPresentation
import SwiftUI

/// Renders only the projection produced from one actor-owned runtime update.
///
/// The view has no route progress, guidance, lane, sign, or speech policy of
/// its own. Its input remains synthetic until a real joint product release and
/// device-qualified location pipeline exist.
struct ProductRuntimeDrivingSurface: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale
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
        Text(
          copy.resolve(
            japanese: "Actor ナビ画面",
            simplifiedChinese: "Actor 导航画面",
            english: "Actor navigation surface"
          )
        )
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
        accessibility.routeShieldLabels.first
          ?? copy.resolve(
            japanese: "ルートシールド不明",
            simplifiedChinese: "路线盾牌未知",
            english: "Unknown route shield"
          )
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
        title: copy.resolve(
          japanese: "位置表示",
          simplifiedChinese: "位置呈现",
          english: "POSITION"
        ),
        value: markerLabel,
        detail: phone.marker.rawValue,
        color: phone.marker == .measured
          ? KaidoTheme.positionCyan
          : KaidoTheme.signalAmber,
        accessibilityID: "product-runtime-driving-marker"
      )
      statusRow(
        title: copy.resolve(
          japanese: "リアルタイム通行",
          simplifiedChinese: "实时通行",
          english: "REALTIME PASSAGE"
        ),
        value: passageLabel,
        detail: phone.passage.evidence.rawValue,
        color: phone.passage.usesPositiveOpenColor
          ? KaidoTheme.confirmedGreen
          : KaidoTheme.signalAmber,
        accessibilityID: "product-runtime-driving-passage"
      )
      statusRow(
        title: copy.resolve(
          japanese: "経路編集",
          simplifiedChinese: "路线编辑",
          english: "ROUTE EDITING"
        ),
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
      copy.resolve(
        japanese: "終了出口を先に確認：\(finishDrive.localizedExitName)",
        simplifiedChinese: "先确认结束出口：\(finishDrive.localizedExitName)",
        english: "Confirm the finishing exit first: \(finishDrive.localizedExitName)"
      ),
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
      copy.resolve(
        japanese: "測定位置",
        simplifiedChinese: "测量位置",
        english: "Measured position"
      )
    case .estimated:
      copy.resolve(
        japanese: "推定位置",
        simplifiedChinese: "估算位置",
        english: "Estimated position"
      )
    case .unresolved:
      copy.resolve(
        japanese: "位置未解決",
        simplifiedChinese: "位置未解析",
        english: "Position unresolved"
      )
    }
  }

  private var passageLabel: String {
    switch phone.passage.tone {
    case .blocked:
      copy.resolve(
        japanese: "既知の通行止め",
        simplifiedChinese: "已知封闭",
        english: "Known closure"
      )
    case .warning:
      copy.resolve(
        japanese: "計画競合あり",
        simplifiedChinese: "存在计划冲突",
        english: "Plan conflict"
      )
    case .unconfirmed:
      copy.resolve(
        japanese: "未確認",
        simplifiedChinese: "尚未确认",
        english: "Unconfirmed"
      )
    case .confirmedPassable:
      copy.resolve(
        japanese: "通行可能を確認済み",
        simplifiedChinese: "已确认可通行",
        english: "Passage confirmed"
      )
    }
  }

  private var editingLabel: String {
    switch phone.routeEditingAvailability {
    case .availableWhileParked:
      copy.resolve(
        japanese: "停車中は編集可能",
        simplifiedChinese: "停车时可编辑",
        english: "Editable while parked"
      )
    case .unavailableWhileMoving:
      copy.resolve(
        japanese: "走行中は編集不可",
        simplifiedChinese: "行驶中不可编辑",
        english: "Unavailable while moving"
      )
    case .unavailableInDecisionZone:
      copy.resolve(
        japanese: "判断ゾーン内は編集不可",
        simplifiedChinese: "决策区不可编辑",
        english: "Unavailable in DecisionZone"
      )
    case .lockedForActiveDrive:
      copy.resolve(
        japanese: "走行中のためロック",
        simplifiedChinese: "活动行程已锁定",
        english: "Locked for active drive"
      )
    }
  }

  private func distanceLabel(_ meters: Double) -> String {
    if meters >= 1_000 {
      return String(format: "%.1f km", meters / 1_000)
    }
    return "\(Int(meters.rounded())) m"
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }
}
