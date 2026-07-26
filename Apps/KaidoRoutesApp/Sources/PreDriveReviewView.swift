import KaidoPresentation
import SwiftUI

enum PreDriveReviewDisplayScope: Equatable {
  case synthetic
  case rehearsal
  case released
}

struct PreDriveReviewPanel: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale
  @ObservedObject var model: PreDriveReviewModel
  let navigationStartAvailable: Bool
  let displayScope: PreDriveReviewDisplayScope
  let releasedSnapshot: PreDriveReviewSnapshot?
  let releasedErrorCode: String?

  init(
    model: PreDriveReviewModel,
    navigationStartAvailable: Bool = false,
    displayScope: PreDriveReviewDisplayScope = .synthetic,
    releasedSnapshot: PreDriveReviewSnapshot? = nil,
    releasedErrorCode: String? = nil
  ) {
    self.model = model
    self.navigationStartAvailable = navigationStartAvailable
    self.displayScope = displayScope
    self.releasedSnapshot = releasedSnapshot
    self.releasedErrorCode = releasedErrorCode
  }

  @ViewBuilder
  var body: some View {
    switch displayScope {
    case .synthetic:
      if let snapshot = model.snapshot {
        review(snapshot)
      } else if model.hasCompiledRoutePlan, let errorCode = model.lastErrorCode {
        blocked(errorCode)
      }
    case .rehearsal, .released:
      if let releasedSnapshot {
        review(releasedSnapshot)
      } else if let releasedErrorCode {
        blocked(releasedErrorCode)
      }
    }
  }

  private func review(_ snapshot: PreDriveReviewSnapshot) -> some View {
    let passage = passageStyle(snapshot.presentation.passage)
    return VStack(alignment: .leading, spacing: 16) {
      header(snapshot, passage: passage)
      distanceLedger(snapshot)
      tollEvidence(snapshot)
      passageEvidence(snapshot, style: passage)
      navigationGate
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
        Text(
          copy.resolve(
            japanese: "出発前確認",
            simplifiedChinese: "行前确认",
            english: "Pre-drive review"
          )
        )
        .font(.system(size: 19, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.routeWhite)

        Text(reviewScopeLabel)
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
        eyebrow: copy.resolve(
          japanese: "実走予定",
          simplifiedChinese: "实际规划",
          english: "PLANNED ROUTE"
        ),
        value: kilometers(snapshot.presentation.actualDistanceKM),
        detail: copy.resolve(
          japanese: "\(snapshot.occurrenceCount) 経路ステップ",
          simplifiedChinese: "\(snapshot.occurrenceCount) 个路线步骤",
          english: "\(snapshot.occurrenceCount) route steps"
        ),
        accent: KaidoTheme.signalAmber
      )

      Image(systemName: "not.equal")
        .font(.system(size: 12, weight: .black))
        .foregroundStyle(KaidoTheme.evidenceCoral)
        .accessibilityHidden(true)

      PreDriveDistanceMetric(
        eyebrow: copy.resolve(
          japanese: "料金計算距離",
          simplifiedChinese: "计费距离",
          english: "TARIFF DISTANCE"
        ),
        value: snapshot.presentation.tariffDistanceKM.map(kilometers) ?? "—",
        detail: copy.resolve(
          japanese: "独立した料金記録",
          simplifiedChinese: "独立计费记录",
          english: "Independent tariff record"
        ),
        accent: KaidoTheme.positionCyan
      )
    }
    .accessibilityElement(children: .contain)
  }

  private func tollEvidence(_ snapshot: PreDriveReviewSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text(
            copy.resolve(
              japanese: "通行料金の根拠",
              simplifiedChinese: "通行费证据",
              english: "TOLL EVIDENCE"
            )
          )
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
        Text(
          "\(snapshot.vehicleClass.rawValue) · \(snapshot.vehicleClass.officialJapaneseLabel) · "
            + "\(snapshot.paymentMethod.rawValue) · \(checkedDate(snapshot.checkedAt))"
        )
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .foregroundStyle(KaidoTheme.muted)

        Spacer()

        if let url = URL(string: snapshot.officialQueryReference) {
          Link(destination: url) {
            Label(
              copy.resolve(
                japanese:
                  displayScope == .rehearsal ? "演習参照" : "公式照会",
                simplifiedChinese:
                  displayScope == .rehearsal ? "演练参考" : "官方查询",
                english:
                  displayScope == .rehearsal
                  ? "Rehearsal reference" : "Official query"
              ),
              systemImage: "arrow.up.right"
            )
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

  private var navigationGate: some View {
    HStack {
      Image(
        systemName:
          navigationStartAvailable
          ? "key.horizontal.fill"
          : "lock.fill"
      )
      Text(
        navigationStartAvailable
          ? displayScope == .rehearsal
            ? copy.resolve(
              japanese: "演習リリースを固定済み",
              simplifiedChinese: "演练发布包已绑定",
              english: "Rehearsal release bound"
            )
            : copy.resolve(
              japanese: "統合リリースを固定済み",
              simplifiedChinese: "联合发布包已绑定",
              english: "Joint release bound"
            )
          : copy.resolve(
            japanese: "ナビリリースが未準備",
            simplifiedChinese: "导航发布包尚未具备",
            english: "Navigation release unavailable"
          )
      )
      Spacer()
      Text(navigationStartAvailable ? "READY" : "BLOCKED")
        .font(.system(size: 9, weight: .black, design: .monospaced))
    }
    .font(.system(size: 13, weight: .bold))
    .foregroundStyle(
      navigationStartAvailable
        ? KaidoTheme.positionCyan
        : KaidoTheme.muted
    )
    .padding(.horizontal, 13)
    .frame(height: 44)
    .background(
      navigationStartAvailable
        ? KaidoTheme.positionCyan.opacity(0.1)
        : KaidoTheme.steel.opacity(0.34)
    )
    .clipShape(RoundedRectangle(cornerRadius: 11))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      navigationStartAvailable
        ? displayScope == .rehearsal
          ? copy.resolve(
            japanese: "演習リリースを固定済みです。運転リハーサルを開始できます。",
            simplifiedChinese: "演练发布包已绑定，可以开始驾驶演练",
            english:
              "The rehearsal release is bound and the driving rehearsal can start."
          )
          : copy.resolve(
            japanese: "統合リリースを固定済みです。ユーザーがナビを開始できます。",
            simplifiedChinese: "联合发布包已绑定，可以由用户开始导航",
            english:
              "The joint release is bound and the user may start navigation."
          )
        : copy.resolve(
          japanese: "ナビリリースが未準備のため、ナビを開始できません。",
          simplifiedChinese: "导航发布包尚未具备，无法开始导航",
          english: "The navigation release is unavailable, so navigation cannot start."
        )
    )
    .accessibilityIdentifier("pre-drive-navigation-gate")
    .accessibilityValue(
      navigationStartAvailable ? "READY" : "BLOCKED"
    )
  }

  private func blocked(_ errorCode: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: "exclamationmark.octagon.fill")
        .foregroundStyle(KaidoTheme.evidenceCoral)

      VStack(alignment: .leading, spacing: 3) {
        Text(
          copy.resolve(
            japanese: "出発前確認で停止",
            simplifiedChinese: "行前确认已阻止",
            english: "Pre-drive review blocked"
          )
        )
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
    guard let value else {
      return copy.resolve(
        japanese: "金額不明",
        simplifiedChinese: "金额未知",
        english: "Amount unknown"
      )
    }
    return "¥\(value.formatted())"
  }

  private func checkedDate(_ value: String) -> String {
    String(value.prefix(10))
  }

  private var reviewScopeLabel: String {
    switch displayScope {
    case .synthetic:
      "ROUTE FIRST · SYNTHETIC REVIEW"
    case .rehearsal:
      "ROUTE FIRST · SYNTHETIC REHEARSAL"
    case .released:
      "ROUTE FIRST · RELEASE-BOUND REVIEW"
    }
  }

  private func passageStyle(
    _ presentation: RoutePassagePresentation
  ) -> PreDrivePassageStyle {
    switch presentation.tone {
    case .blocked:
      PreDrivePassageStyle(
        badge: copy.resolve(
          japanese: "停止",
          simplifiedChinese: "已阻止",
          english: "BLOCKED"
        ),
        primary: copy.resolve(
          japanese: "計画レイヤー：既知の通行止めあり",
          simplifiedChinese: "计划层：存在已知关闭",
          english: "Plan layer: known closure"
        ),
        secondary: copy.resolve(
          japanese: "現在の経路は開始できません",
          simplifiedChinese: "当前路线不能开始",
          english: "The current route cannot start"
        ),
        color: KaidoTheme.evidenceCoral
      )
    case .warning:
      PreDrivePassageStyle(
        badge: copy.resolve(
          japanese: "競合あり",
          simplifiedChinese: "有冲突",
          english: "CONFLICT"
        ),
        primary: copy.resolve(
          japanese: "計画レイヤー：通行競合あり",
          simplifiedChinese: "计划层：存在通行冲突",
          english: "Plan layer: passage conflict"
        ),
        secondary: copy.resolve(
          japanese: "経路の再審査が必要です",
          simplifiedChinese: "需要重新审查路线",
          english: "The route requires another review"
        ),
        color: KaidoTheme.evidenceCoral
      )
    case .unconfirmed:
      PreDrivePassageStyle(
        badge: copy.resolve(
          japanese: "未確認",
          simplifiedChinese: "未确认",
          english: "UNCONFIRMED"
        ),
        primary: copy.resolve(
          japanese: "計画レイヤー：既知の競合なし",
          simplifiedChinese: "计划层：未发现已知冲突",
          english: "Plan layer: no known conflict"
        ),
        secondary: copy.resolve(
          japanese: "リアルタイム通行状態は未確認です",
          simplifiedChinese: "实时通行状态尚未确认",
          english: "Realtime passage state is unconfirmed"
        ),
        color: KaidoTheme.evidenceCoral
      )
    case .confirmedPassable:
      PreDrivePassageStyle(
        badge: copy.resolve(
          japanese: "リアルタイム確認済み",
          simplifiedChinese: "实时已确认",
          english: "REALTIME CONFIRMED"
        ),
        primary: copy.resolve(
          japanese: "リアルタイム情報：通行可能を確認",
          simplifiedChinese: "实时来源：已确认可通行",
          english: "Realtime source: passage confirmed"
        ),
        secondary: copy.resolve(
          japanese: "現地の標識と規制には引き続き従ってください",
          simplifiedChinese: "仍需遵循现场标志与管制",
          english: "Continue to follow on-road signs and restrictions"
        ),
        color: KaidoTheme.confirmedGreen
      )
    }
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
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
