import Foundation
import KaidoRouting
import SwiftUI

struct WholeShutoJourneyReviewView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale
  @ObservedObject var model: WholeShutoProductModel
  @ObservedObject var languageSettings: KaidoLanguageSettingsModel
  @ObservedObject var savedRoutes: SavedRouteLibraryModel
  /// Starting a live drive also needs the location session, which the
  /// product view owns, so the action is handed in.
  var onStartLiveDrive: () -> Void = {}

  var body: some View {
    VStack(spacing: 0) {
      header

      ScrollView {
        VStack(spacing: 18) {
          journeyMetrics
          routePassport
          availabilitySummary
          SavedRouteSavePanel(
            library: savedRoutes,
            routePlan: model.selectedRoute?.routePlan
          ) { displayName in
            savedRoutes.save(
              routePlan: model.selectedRoute?.routePlan,
              displayName: displayName,
              evidenceState: .communityCandidate,
              templateParameters: model.savedRouteTemplateParameters
            )
          }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
      }
      .scrollIndicators(.hidden)

      startAction
    }
    .background(KaidoTheme.nightPanel)
    .presentationDetents([.fraction(0.86), .large])
    .presentationDragIndicator(.visible)
    .presentationCornerRadius(24)
    .presentationBackground(KaidoTheme.nightPanel)
    .presentationContentInteraction(.scrolls)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("whole-shuto-journey-review")
    .onChange(of: model.phase) { _, phase in
      if phase != .review {
        dismiss()
      }
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text("KAIDO · ROUTE PASS")
          .font(.system(size: 9, weight: .black, design: .rounded))
          .tracking(1.7)
          .foregroundStyle(KaidoTheme.routeGreen)
        Text(
          copy.resolve(
            japanese: "出発前の行程確認",
            simplifiedChinese: "出发前确认行程",
            english: "Review before departure"
          )
        )
        .font(.system(size: 23, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.routeWhite)
        Text(
          copy.resolve(
            japanese: "入口から出口まで、選択したルートを固定します",
            simplifiedChinese: "从入口到出口，按你选择的路线预演",
            english: "Preview the exact route you selected from entry to exit"
          )
        )
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(KaidoTheme.nightQuiet)
      }

      Spacer(minLength: 8)

      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 12, weight: .black))
          .foregroundStyle(KaidoTheme.routeWhite)
          .frame(width: 44, height: 44)
          .background(KaidoTheme.nightRaised)
          .clipShape(Circle())
          .overlay {
            Circle()
              .stroke(KaidoTheme.nightDivider, lineWidth: 1)
          }
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        copy.resolve(
          japanese: "行程確認を閉じる",
          simplifiedChinese: "关闭行程确认",
          english: "Close journey review"
        )
      )
      .accessibilityIdentifier("whole-shuto-review-close")
    }
    .padding(.horizontal, 18)
    .padding(.top, 20)
    .padding(.bottom, 16)
  }

  private var journeyMetrics: some View {
    HStack(spacing: 10) {
      metric(
        label: copy.resolve(
          japanese: "全行程",
          simplifiedChinese: "全程",
          english: "FULL JOURNEY"
        ),
        value: distanceLabel(model.plannedJourneyDistanceMeters),
        detail: copy.resolve(
          japanese: "地上区間を含む",
          simplifiedChinese: "包含地面接驳",
          english: "Including surface legs"
        ),
        tint: KaidoTheme.routeGreen,
        accessibilityIdentifier: "whole-shuto-journey-total-distance"
      )
      metric(
        label: copy.resolve(
          japanese: "目安時間",
          simplifiedChinese: "预计用时",
          english: "ESTIMATED TIME"
        ),
        value: durationLabel(model.plannedPreviewDurationSeconds),
        detail: copy.resolve(
          japanese: "リアルタイム交通を含まない",
          simplifiedChinese: "不含实时路况",
          english: "No realtime traffic"
        ),
        tint: KaidoTheme.signalAmber,
        accessibilityIdentifier: "whole-shuto-journey-estimated-duration"
      )
    }
  }

  private var routePassport: some View {
    VStack(spacing: 0) {
      endpoint(
        symbol: "location.fill",
        eyebrow: copy.resolve(
          japanese: "出発地",
          simplifiedChinese: "出发地",
          english: "ORIGIN"
        ),
        title: model.origin?.title ?? "—",
        detail: copy.resolve(
          japanese: "地上道路",
          simplifiedChinese: "地面道路",
          english: "Surface road"
        ),
        tint: KaidoTheme.positionCyan
      )

      surfaceLeg(
        label: copy.resolve(
          japanese: "入口まで",
          simplifiedChinese: "前往入口",
          english: "TO ENTRY"
        ),
        route: model.accessRoute,
        accessibilityIdentifier: "whole-shuto-access-leg"
      )

      endpoint(
        symbol: "arrow.up.right",
        eyebrow: copy.resolve(
          japanese: "入口",
          simplifiedChinese: "入口",
          english: "ENTRY"
        ),
        title: model.selectedRoute?.entryFacility.nameJA ?? "—",
        detail: model.selectedRoute?.entryFacility.entranceDirections
          .joined(separator: " / ") ?? "",
        tint: KaidoTheme.positionCyan
      )

      expresswayLeg

      endpoint(
        symbol: "arrow.up.right",
        eyebrow: copy.resolve(
          japanese: "出口",
          simplifiedChinese: "出口",
          english: "EXIT"
        ),
        title: model.selectedRoute?.exitFacility.nameJA ?? "—",
        detail: model.selectedRoute?.exitFacility.exitDirections
          .joined(separator: " / ") ?? "",
        tint: KaidoTheme.evidenceCoral
      )

      surfaceLeg(
        label: copy.resolve(
          japanese: "目的地まで",
          simplifiedChinese: "前往目的地",
          english: "TO DESTINATION"
        ),
        route: model.egressRoute,
        accessibilityIdentifier: "whole-shuto-egress-leg"
      )

      endpoint(
        symbol: "flag.checkered",
        eyebrow: copy.resolve(
          japanese: "目的地",
          simplifiedChinese: "目的地",
          english: "DESTINATION"
        ),
        title: model.destination?.title ?? "—",
        detail: copy.resolve(
          japanese: "全行程の終点",
          simplifiedChinese: "完整行程终点",
          english: "End of full journey"
        ),
        tint: KaidoTheme.evidenceCoral
      )
    }
    .padding(14)
    .background(KaidoTheme.nightRaised)
    .clipShape(RoundedRectangle(cornerRadius: 18))
    .overlay {
      RoundedRectangle(cornerRadius: 18)
        .stroke(KaidoTheme.nightDivider, lineWidth: 1)
    }
  }

  private func endpoint(
    symbol: String,
    eyebrow: String,
    title: String,
    detail: String,
    tint: Color
  ) -> some View {
    HStack(spacing: 12) {
      ZStack {
        Circle()
          .fill(tint)
          .frame(width: 34, height: 34)
        Image(systemName: symbol)
          .font(.system(size: 12, weight: .black))
          .foregroundStyle(KaidoTheme.routeWhite)
      }

      VStack(alignment: .leading, spacing: 1) {
        Text(eyebrow)
          .font(.system(size: 8, weight: .black, design: .rounded))
          .tracking(0.7)
          .foregroundStyle(tint)
        Text(title)
          .font(.system(size: 14, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
        if !detail.isEmpty {
          Text(detail)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(KaidoTheme.nightQuiet)
            .lineLimit(1)
        }
      }

      Spacer(minLength: 4)
    }
    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  private func surfaceLeg(
    label: String,
    route: WholeShutoSurfaceRoute?,
    accessibilityIdentifier: String
  ) -> some View {
    HStack(spacing: 12) {
      Rectangle()
        .fill(KaidoTheme.roadGray)
        .frame(width: 2, height: 38)
        .padding(.leading, 16)

      VStack(alignment: .leading, spacing: 2) {
        Text(label)
          .font(.system(size: 8, weight: .black, design: .rounded))
          .tracking(0.6)
          .foregroundStyle(KaidoTheme.nightQuiet)
        Text(
          "\(distanceLabel(route?.distanceMeters)) · "
            + durationLabel(route?.expectedTravelTimeSeconds)
        )
        .font(.system(size: 11, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.routeWhite)
      }

      Spacer()
    }
    .frame(height: 46)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(accessibilityIdentifier)
  }

  private var expresswayLeg: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(
          copy.resolve(
            japanese: "選択した首都高ルート",
            simplifiedChinese: "已选择的首都高路线",
            english: "SELECTED SHUTO ROUTE"
          )
        )
        .font(.system(size: 8, weight: .black, design: .rounded))
        .tracking(0.7)
        .foregroundStyle(KaidoTheme.confirmedGreen)

        Spacer()

        Text(distanceLabel(model.selectedRoute?.distanceMeters))
          .font(.system(size: 11, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)
      }

      ScrollView(.horizontal) {
        HStack(spacing: 7) {
          ForEach(
            Array(
              (model.selectedRoute?.routeIDsInOrder ?? []).enumerated()
            ),
            id: \.offset
          ) { index, routeID in
            if index > 0 {
              Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(KaidoTheme.nightQuiet)
            }
            Text(shieldLabel(routeID))
              .font(.system(size: 12, weight: .black, design: .rounded))
              .foregroundStyle(KaidoTheme.routeWhite)
              .padding(.horizontal, 9)
              .frame(height: 30)
              .background(routeColor(routeID))
              .clipShape(RoundedRectangle(cornerRadius: 7))
              .accessibilityLabel(
                routeDisplayLabel(routeID, in: model.database)
              )
          }
        }
      }
      .scrollIndicators(.hidden)
    }
    .padding(12)
    .background(KaidoTheme.night)
    .clipShape(RoundedRectangle(cornerRadius: 13))
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("whole-shuto-expressway-leg")
    .accessibilityValue(
      (model.selectedRoute?.routeIDsInOrder ?? [])
        .map { routeDisplayLabel($0, in: model.database) }
        .joined(separator: " → ")
    )
  }

  private var availabilitySummary: some View {
    VStack(spacing: 0) {
      statusRow(
        symbol: "dot.radiowaves.left.and.right",
        label: copy.resolve(
          japanese: "現在の通行状況",
          simplifiedChinese: "当前通行状态",
          english: "CURRENT PASSAGE"
        ),
        value: copy.resolve(
          japanese: "リアルタイム未確認",
          simplifiedChinese: "实时未确认",
          english: "Realtime unconfirmed"
        ),
        tint: KaidoTheme.signalAmber,
        accessibilityIdentifier: "whole-shuto-passage-status",
        accessibilityValue: "REALTIME_UNCONFIRMED"
      )

      Divider()
        .padding(.leading, 42)

      statusRow(
        symbol: "yensign.circle",
        label: copy.resolve(
          japanese: "通行料金",
          simplifiedChinese: "通行费",
          english: "TOLL"
        ),
        value: tariffPresentation.value,
        tint: tariffPresentation.tint,
        accessibilityIdentifier: "whole-shuto-toll-status",
        accessibilityValue: tariffPresentation.accessibilityValue
      )

      Divider()
        .padding(.leading, 42)

      statusRow(
        symbol: "speaker.wave.2.fill",
        label: copy.resolve(
          japanese: "音声案内",
          simplifiedChinese: "导航语音",
          english: "GUIDANCE VOICE"
        ),
        value: copy.languageName(languageSettings.guidanceVoiceLocale),
        tint: KaidoTheme.routeGreen,
        accessibilityIdentifier: "whole-shuto-guidance-language",
        accessibilityValue: languageSettings.guidanceVoiceLocale.rawValue
      )
    }
    .padding(.horizontal, 12)
    .background(KaidoTheme.nightRaised)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .overlay {
      RoundedRectangle(cornerRadius: 16)
        .stroke(KaidoTheme.nightDivider, lineWidth: 1)
    }
  }

  private var tariffPresentation: (
    value: String,
    tint: Color,
    accessibilityValue: String
  ) {
    let evidence = ShutoTariffEvidence.etcNormalCarActive
    guard let band = model.selectedTariffBand else {
      return (
        copy.resolve(
          japanese: "現在の見積もりなし",
          simplifiedChinese: "暂无当前报价",
          english: "No current quote"
        ),
        KaidoTheme.nightQuiet,
        "UNAVAILABLE"
      )
    }
    let datedSuffix = " · ETC · \(evidence.checkedAt)"
    switch band {
    case .minimum(let yen):
      return (
        copy.resolve(
          japanese: "¥\(yen)・最低料金帯",
          simplifiedChinese: "¥\(yen)·最低费用档",
          english: "¥\(yen) minimum band"
        ) + datedSuffix,
        KaidoTheme.positionCyan,
        "ACTIVE_MINIMUM_BAND · \(evidence.checkedAt)"
      )
    case .estimated(let yen):
      return (
        copy.resolve(
          japanese: "目安 ¥\(yen)",
          simplifiedChinese: "约 ¥\(yen)",
          english: "≈ ¥\(yen)"
        ) + datedSuffix,
        KaidoTheme.signalAmber,
        "ACTIVE_ESTIMATED · \(evidence.checkedAt)"
      )
    case .maximum(let yen):
      return (
        copy.resolve(
          japanese: "¥\(yen)・上限",
          simplifiedChinese: "¥\(yen)·上限",
          english: "¥\(yen) cap"
        ) + datedSuffix,
        KaidoTheme.positionCyan,
        "ACTIVE_MAXIMUM · \(evidence.checkedAt)"
      )
    }
  }

  private func statusRow(
    symbol: String,
    label: String,
    value: String,
    tint: Color,
    accessibilityIdentifier: String,
    accessibilityValue: String
  ) -> some View {
    HStack(spacing: 10) {
      Image(systemName: symbol)
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(tint)
        .frame(width: 24)
      Text(label)
        .font(.system(size: 9, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.nightQuiet)
      Spacer()
      Text(value)
        .font(.system(size: 11, weight: .black, design: .rounded))
        .foregroundStyle(tint)
        .multilineTextAlignment(.trailing)
    }
    .frame(minHeight: 46)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(accessibilityIdentifier)
    .accessibilityValue(accessibilityValue)
  }

  private var startAction: some View {
    VStack(spacing: 8) {
      if let blockerCode = model.liveNavigationBlockerCode {
        HStack(alignment: .top, spacing: 8) {
          Image(
            systemName:
              blockerCode == WholeShutoProductModel.liveNavigationPreparingCode
              ? "hourglass" : "lock.shield.fill"
          )
          .foregroundStyle(KaidoTheme.signalAmber)
          Text(liveNavigationBlockerMessage(blockerCode))
            .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(KaidoTheme.nightQuiet)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(KaidoTheme.signalAmber.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("whole-shuto-live-drive-blocker")
        .accessibilityValue(blockerCode)
      }

      Button {
        onStartLiveDrive()
      } label: {
        HStack(spacing: 9) {
          Text(
            copy.resolve(
              japanese: "案内を開始",
              simplifiedChinese: "开始导航",
              english: "START NAVIGATION"
            )
          )
          Spacer()
          Image(systemName: "location.north.fill")
        }
        .font(.system(size: 14, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.routeWhite)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(KaidoTheme.routeGreen)
        .clipShape(RoundedRectangle(cornerRadius: 11))
      }
      .buttonStyle(.plain)
      .disabled(!model.canStartLiveNavigation)
      .opacity(model.canStartLiveNavigation ? 1 : 0.45)
      .accessibilityIdentifier("whole-shuto-start-live-drive")
      .accessibilityValue(
        model.liveNavigationBlockerCode ?? "AVAILABLE"
      )

      Button {
        model.startNavigationSimulation()
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "play.fill")
            .font(.system(size: 10, weight: .black))
          Text(
            copy.resolve(
              japanese: "走らずにプレビュー（54 km/h 基準・20×）",
              simplifiedChinese: "不开车，先预演（54 km/h 基准 · 20×）",
              english: "Preview without driving (54 km/h reference, 20×)"
            )
          )
          .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(
          model.canStartLiveNavigation
            ? KaidoTheme.nightQuiet
            : KaidoTheme.routeWhite
        )
        .frame(maxWidth: .infinity)
        .frame(height: model.canStartLiveNavigation ? 34 : 48)
        .background(
          model.canStartLiveNavigation
            ? Color.clear
            : KaidoTheme.routeGreen
        )
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(!model.isJourneyReadyForPreview)
      .opacity(model.isJourneyReadyForPreview ? 1 : 0.45)
      .accessibilityIdentifier("whole-shuto-start-simulation")

      Text(
        copy.resolve(
          japanese:
            "一般道はMapKitの経路を案内し、首都高では審査済みの分岐だけを音声案内します。",
          simplifiedChinese:
            "普通道路沿 MapKit 路线导航；进入首都高后只播报已审核的分岔。",
          english:
            "Surface guidance follows MapKit; on Shuto, only reviewed junctions are spoken."
        )
      )
      .font(.system(size: 8, weight: .bold))
      .foregroundStyle(KaidoTheme.nightQuiet)
      .multilineTextAlignment(.center)
    }
    .padding(.horizontal, 18)
    .padding(.top, 12)
    .padding(.bottom, 10)
    .background(KaidoTheme.nightPanel)
    .overlay(alignment: .top) {
      Rectangle()
        .fill(KaidoTheme.nightDivider)
        .frame(height: 1)
    }
  }

  private func liveNavigationBlockerMessage(_ code: String) -> String {
    switch code {
    case WholeShutoProductModel.liveNavigationPreparingCode:
      copy.resolve(
        japanese: "このルートの完全な経路、分岐案内、復帰経路を確認しています。",
        simplifiedChinese: "正在验证这条路线的完整路径、分岔提示和安全重返路线。",
        english: "Validating this route, its junction guidance, and safe rejoin path."
      )
    case WholeShutoRouteReleaseAuthority.guidanceIncompleteCode:
      copy.resolve(
        japanese: "この経路には未確認の分岐案内があります。実走ナビは開始できません。",
        simplifiedChinese: "这条路线包含尚未完成审查的分岔提示，暂时不能开始实车导航。",
        english:
          "This route contains junction guidance that has not yet been reviewed for live navigation."
      )
    case WholeShutoRouteReleaseAuthority.recoveryUnavailableCode:
      copy.resolve(
        japanese: "この経路には公開済みの安全な復帰経路がありません。",
        simplifiedChinese: "这条路线还没有已发布的安全重返路线。",
        english: "This route does not yet have a released safe-rejoin path."
      )
    default:
      copy.resolve(
        japanese: "この正確な経路は実走ナビに利用できません。",
        simplifiedChinese: "这条精确路线目前不能用于实车导航。",
        english: "This exact route is not available for live navigation."
      )
    }
  }

  private func metric(
    label: String,
    value: String,
    detail: String,
    tint: Color,
    accessibilityIdentifier: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Rectangle()
        .fill(tint)
        .frame(width: 30, height: 3)
      Text(label)
        .font(.system(size: 8, weight: .black, design: .rounded))
        .tracking(0.7)
        .foregroundStyle(KaidoTheme.nightQuiet)
      Text(value)
        .font(.system(size: 20, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.routeWhite)
      Text(detail)
        .font(.system(size: 8, weight: .bold))
        .foregroundStyle(KaidoTheme.nightQuiet)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
    .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
    .padding(12)
    .background(KaidoTheme.nightRaised)
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .stroke(KaidoTheme.nightDivider, lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(accessibilityIdentifier)
  }

  private func distanceLabel(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    if value < 1_000 {
      return "\(Int(value.rounded())) m"
    }
    return String(format: "%.1f km", value / 1_000)
  }

  private func durationLabel(_ seconds: Double?) -> String {
    guard let seconds, seconds.isFinite, seconds >= 0 else { return "—" }
    let minutes = max(1, Int(ceil(seconds / 60)))
    if minutes < 60 {
      return copy.resolve(
        japanese: "約 \(minutes) 分",
        simplifiedChinese: "约 \(minutes) 分钟",
        english: "About \(minutes) min"
      )
    }
    let hours = minutes / 60
    let remainder = minutes % 60
    return copy.resolve(
      japanese: "約 \(hours) 時間 \(remainder) 分",
      simplifiedChinese: "约 \(hours) 小时 \(remainder) 分钟",
      english: "About \(hours) hr \(remainder) min"
    )
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }
}
