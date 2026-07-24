import KaidoPresentation
import SwiftUI

struct PreDriveReviewPanel: View {
  @ObservedObject var model: PreDriveReviewModel

  @ViewBuilder
  var body: some View {
    if let snapshot = model.snapshot {
      review(snapshot)
    } else if model.hasCompiledRoutePlan, let errorCode = model.lastErrorCode {
      blocked(errorCode)
    }
  }

  private func review(_ snapshot: PreDriveReviewSnapshot) -> some View {
    let passage = passageStyle(snapshot.presentation.passage)
    return VStack(alignment: .leading, spacing: 16) {
      header(snapshot, passage: passage)
      distanceLedger(snapshot)
      tollEvidence(snapshot)
      passageEvidence(snapshot, style: passage)
      navigationGate(snapshot)
    }
    .padding(16)
    .background(KaidoTheme.instrument)
    .clipShape(RoundedRectangle(cornerRadius: 22))
    .overlay {
      RoundedRectangle(cornerRadius: 22)
        .stroke(KaidoTheme.evidenceCoral.opacity(0.48), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
  }

  private func header(
    _ snapshot: PreDriveReviewSnapshot,
    passage: PreDrivePassageStyle
  ) -> some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 3) {
        Text("行前确认")
          .font(.system(size: 19, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)

        Text("ROUTE FIRST · SYNTHETIC REVIEW")
          .font(.system(size: 9, weight: .bold, design: .monospaced))
          .tracking(0.75)
          .foregroundStyle(KaidoTheme.muted)

        Text(verbatim: snapshot.routePlanID)
          .font(.system(size: 8, weight: .medium, design: .monospaced))
          .foregroundStyle(KaidoTheme.muted.opacity(0.78))
      }

      Spacer()

      StatusCapsule(
        title: passage.badge,
        color: passage.color
      )
    }
  }

  private func distanceLedger(_ snapshot: PreDriveReviewSnapshot) -> some View {
    HStack(spacing: 8) {
      PreDriveDistanceMetric(
        eyebrow: "实际规划",
        value: kilometers(snapshot.presentation.actualDistanceKM),
        detail: "\(snapshot.occurrenceCount) 个路线步骤",
        accent: KaidoTheme.signalAmber
      )

      Image(systemName: "not.equal")
        .font(.system(size: 12, weight: .black))
        .foregroundStyle(KaidoTheme.evidenceCoral)
        .accessibilityHidden(true)

      PreDriveDistanceMetric(
        eyebrow: "计费距离",
        value: snapshot.presentation.tariffDistanceKM.map(kilometers) ?? "—",
        detail: "独立计费记录",
        accent: KaidoTheme.positionCyan
      )
    }
    .accessibilityElement(children: .contain)
  }

  private func tollEvidence(_ snapshot: PreDriveReviewSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text("通行费证据")
            .font(.system(size: 9, weight: .black, design: .monospaced))
            .tracking(0.7)
            .foregroundStyle(KaidoTheme.muted)

          Text(amount(snapshot.presentation.estimatedAmountYen))
            .font(.system(size: 24, weight: .black, design: .rounded))
            .foregroundStyle(KaidoTheme.routeWhite)
        }

        Spacer()

        Text(snapshot.presentation.tollEvidenceStatus.rawValue)
          .font(.system(size: 9, weight: .black, design: .monospaced))
          .foregroundStyle(KaidoTheme.signalAmber)
          .padding(.horizontal, 9)
          .frame(height: 26)
          .background(KaidoTheme.signalAmber.opacity(0.1))
          .clipShape(Capsule())
      }

      HStack(spacing: 8) {
        ReviewEvidenceIdentity(
          label: "TARIFF VERSION",
          value: snapshot.tariffVersionID
        )
        ReviewEvidenceIdentity(
          label: "VERSION STATE",
          value: snapshot.tariffVersionStatus.rawValue
        )
      }

      HStack {
        Text("\(snapshot.vehicleClass) · \(checkedDate(snapshot.checkedAt))")
          .font(.system(size: 9, weight: .medium, design: .monospaced))
          .foregroundStyle(KaidoTheme.muted)

        Spacer()

        if let url = URL(string: snapshot.officialQueryReference) {
          Link(destination: url) {
            Label("官方查询", systemImage: "arrow.up.right")
              .font(.system(size: 10, weight: .bold))
              .foregroundStyle(KaidoTheme.positionCyan)
          }
        }
      }
    }
    .padding(12)
    .background(KaidoTheme.asphalt.opacity(0.48))
    .clipShape(RoundedRectangle(cornerRadius: 14))
  }

  private func passageEvidence(
    _ snapshot: PreDriveReviewSnapshot,
    style: PreDrivePassageStyle
  ) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "dot.radiowaves.left.and.right")
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(style.color)
        .frame(width: 28)

      VStack(alignment: .leading, spacing: 4) {
        Text(style.primary)
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(KaidoTheme.routeWhite)

        Text(style.secondary)
          .font(.system(size: 12, weight: .black))
          .foregroundStyle(style.color)

        Text(verbatim: snapshot.presentation.passage.evidence.rawValue)
          .font(.system(size: 8, weight: .medium, design: .monospaced))
          .foregroundStyle(KaidoTheme.muted)
      }

      Spacer(minLength: 4)
    }
    .padding(12)
    .background(style.color.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 13))
    .overlay {
      RoundedRectangle(cornerRadius: 13)
        .stroke(style.color.opacity(0.35), lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(style.primary)；\(style.secondary)")
  }

  private func navigationGate(_ snapshot: PreDriveReviewSnapshot) -> some View {
    Button {
    } label: {
      HStack {
        Image(systemName: "lock.fill")
        Text("导航发布包尚未具备")
        Spacer()
        Text(snapshot.navigationStartAllowed ? "READY" : "BLOCKED")
          .font(.system(size: 9, weight: .black, design: .monospaced))
      }
      .font(.system(size: 13, weight: .bold))
      .foregroundStyle(KaidoTheme.muted)
      .padding(.horizontal, 13)
      .frame(height: 44)
      .background(KaidoTheme.steel.opacity(0.34))
      .clipShape(RoundedRectangle(cornerRadius: 11))
    }
    .buttonStyle(.plain)
    .disabled(!snapshot.navigationStartAllowed)
    .accessibilityLabel("导航发布包尚未具备，无法开始导航")
  }

  private func blocked(_ errorCode: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: "exclamationmark.octagon.fill")
        .foregroundStyle(KaidoTheme.evidenceCoral)

      VStack(alignment: .leading, spacing: 3) {
        Text("行前确认已阻止")
          .font(.system(size: 14, weight: .black))
          .foregroundStyle(KaidoTheme.routeWhite)

        Text(verbatim: errorCode)
          .font(.system(size: 9, weight: .bold, design: .monospaced))
          .foregroundStyle(KaidoTheme.evidenceCoral)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(KaidoTheme.instrument)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .overlay {
      RoundedRectangle(cornerRadius: 16)
        .stroke(KaidoTheme.evidenceCoral.opacity(0.45), lineWidth: 1)
    }
  }

  private func kilometers(_ value: Double) -> String {
    String(format: "%.1f km", value)
  }

  private func amount(_ value: Int?) -> String {
    guard let value else { return "金额未知" }
    return "¥\(value.formatted())"
  }

  private func checkedDate(_ value: String) -> String {
    String(value.prefix(10))
  }

  private func passageStyle(
    _ presentation: RoutePassagePresentation
  ) -> PreDrivePassageStyle {
    switch presentation.tone {
    case .blocked:
      PreDrivePassageStyle(
        badge: "已阻止",
        primary: "计划层：存在已知关闭",
        secondary: "当前路线不能开始",
        color: KaidoTheme.evidenceCoral
      )
    case .warning:
      PreDrivePassageStyle(
        badge: "有冲突",
        primary: "计划层：存在通行冲突",
        secondary: "需要重新审查路线",
        color: KaidoTheme.evidenceCoral
      )
    case .unconfirmed:
      PreDrivePassageStyle(
        badge: "未确认",
        primary: "计划层：未发现已知冲突",
        secondary: "实时通行状态尚未确认",
        color: KaidoTheme.evidenceCoral
      )
    case .confirmedPassable:
      PreDrivePassageStyle(
        badge: "实时已确认",
        primary: "实时来源：已确认可通行",
        secondary: "仍需遵循现场标志与管制",
        color: KaidoTheme.confirmedGreen
      )
    }
  }
}

private struct PreDrivePassageStyle {
  let badge: String
  let primary: String
  let secondary: String
  let color: Color
}

private struct PreDriveDistanceMetric: View {
  let eyebrow: String
  let value: String
  let detail: String
  let accent: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Rectangle()
        .fill(accent)
        .frame(width: 28, height: 2)

      Text(eyebrow)
        .font(.system(size: 9, weight: .black, design: .monospaced))
        .tracking(0.55)
        .foregroundStyle(KaidoTheme.muted)

      Text(value)
        .font(.system(size: 18, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.routeWhite)

      Text(detail)
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(KaidoTheme.muted)
    }
    .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
    .padding(11)
    .background(KaidoTheme.asphalt.opacity(0.48))
    .clipShape(RoundedRectangle(cornerRadius: 13))
  }
}

private struct ReviewEvidenceIdentity: View {
  let label: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label)
        .font(.system(size: 7, weight: .black, design: .monospaced))
        .tracking(0.45)
        .foregroundStyle(KaidoTheme.muted)

      Text(verbatim: value)
        .font(.system(size: 8, weight: .semibold, design: .monospaced))
        .foregroundStyle(KaidoTheme.routeWhite)
        .lineLimit(2)
        .minimumScaleFactor(0.7)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(9)
    .background(KaidoTheme.steel.opacity(0.24))
    .clipShape(RoundedRectangle(cornerRadius: 9))
  }
}
