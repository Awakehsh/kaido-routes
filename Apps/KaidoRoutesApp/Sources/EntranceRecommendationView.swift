import Foundation
import KaidoRouting
import SwiftUI

struct EntranceRecommendationPanel: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale

  let model: EntranceRecommendationModel

  private var snapshot: EntranceRecommendationSnapshot {
    model.snapshot
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header
      selectedEntrance
      selectionReasons
      rejectedEntrances
    }
    .padding(16)
    .background(KaidoTheme.instrument)
    .clipShape(RoundedRectangle(cornerRadius: 22))
    .overlay {
      RoundedRectangle(cornerRadius: 22)
        .stroke(KaidoTheme.positionCyan.opacity(0.45), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
  }

  private var header: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 3) {
        Text(
          copy.resolve(
            japanese: "入口の提案",
            simplifiedChinese: "入口推荐",
            english: "Entrance recommendation"
          )
        )
        .font(.system(size: 19, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.routeWhite)

        Text("SYNTHETIC CANDIDATES · NO LIVE LOCATION")
          .font(.system(size: 9, weight: .bold, design: .monospaced))
          .tracking(0.7)
          .foregroundStyle(KaidoTheme.muted)

        Text(verbatim: snapshot.networkSnapshotID)
          .font(.system(size: 8, weight: .medium, design: .monospaced))
          .foregroundStyle(KaidoTheme.muted.opacity(0.78))
      }

      Spacer()

      StatusCapsule(
        title: copy.resolve(
          japanese: "方向優先",
          simplifiedChinese: "方向优先",
          english: "DIRECTION FIRST"
        ),
        color: KaidoTheme.positionCyan
      )
    }
  }

  private var selectedEntrance: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 12) {
        ZStack {
          Circle()
            .fill(KaidoTheme.positionCyan)
            .frame(width: 38, height: 38)

          Image(systemName: "arrow.turn.up.right")
            .font(.system(size: 15, weight: .black))
            .foregroundStyle(KaidoTheme.asphalt)
        }

        VStack(alignment: .leading, spacing: 3) {
          Text(
            copy.resolve(
              japanese: "推奨する正確な入口",
              simplifiedChinese: "推荐精确入口",
              english: "RECOMMENDED EXACT ENTRANCE"
            )
          )
          .font(.system(size: 9, weight: .black, design: .monospaced))
          .tracking(0.6)
          .foregroundStyle(KaidoTheme.positionCyan)

          Text(
            model.fixture.facilityTitle(
              for: snapshot.selection.facilityID,
              locale: interfaceLocale
            )
          )
          .font(.system(size: 17, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)

          Text(
            model.fixture.carriagewayTitle(
              for: snapshot.selection.targetCarriagewayID,
              locale: interfaceLocale
            )
          )
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(KaidoTheme.muted)
        }

        Spacer()
      }

      HStack(spacing: 8) {
        EntranceMetric(
          value: minutes(snapshot.selection.surfaceETAMinutes),
          label: copy.resolve(
            japanese: "一般道所要",
            simplifiedChinese: "地表预计",
            english: "Surface ETA"
          )
        )
        EntranceMetric(
          value: kilometers(snapshot.selection.straightLineDistanceKM),
          label: copy.resolve(
            japanese: "直線距離",
            simplifiedChinese: "直线距离",
            english: "Straight line"
          )
        )
        EntranceMetric(
          value: rank(snapshot.selection.straightLineDistanceRank),
          label: copy.resolve(
            japanese: "距離順位",
            simplifiedChinese: "距离排名",
            english: "Distance rank"
          )
        )
      }

      VStack(alignment: .leading, spacing: 5) {
        IdentityRow(
          label: "TARGET CARRIAGEWAY",
          value: snapshot.selection.targetCarriagewayID
        )
        IdentityRow(
          label: "ROUTE JOIN OCCURRENCE",
          value: snapshot.selection.joinOccurrenceID
        )
      }
    }
    .padding(13)
    .background(KaidoTheme.positionCyan.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 15))
    .overlay {
      RoundedRectangle(cornerRadius: 15)
        .stroke(KaidoTheme.positionCyan.opacity(0.35), lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      copy.resolve(
        japanese:
          "推奨する正確な入口、\(selectedFacilityTitle)、対象車線\(selectedCarriagewayTitle)、"
          + "一般道所要時間\(minutes(snapshot.selection.surfaceETAMinutes))、"
          + "直線距離順位\(snapshot.selection.straightLineDistanceRank)位",
        simplifiedChinese:
          "推荐精确入口，\(selectedFacilityTitle)，目标车道\(selectedCarriagewayTitle)，"
          + "地表预计\(minutes(snapshot.selection.surfaceETAMinutes))，"
          + "直线距离排名第\(snapshot.selection.straightLineDistanceRank)",
        english:
          "Recommended exact entrance, \(selectedFacilityTitle), target carriageway "
          + "\(selectedCarriagewayTitle), surface ETA "
          + "\(minutes(snapshot.selection.surfaceETAMinutes)), straight-line distance rank "
          + "\(snapshot.selection.straightLineDistanceRank)"
      )
    )
  }

  private var selectionReasons: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text(
        copy.resolve(
          japanese: "最寄りの入口を選ばない理由",
          simplifiedChinese: "为什么不是最近入口",
          english: "Why not the nearest entrance"
        )
      )
      .font(.system(size: 10, weight: .black, design: .monospaced))
      .tracking(0.65)
      .foregroundStyle(KaidoTheme.signalAmber)

      ForEach(snapshot.selection.reasonCodes, id: \.rawValue) { reason in
        HStack(spacing: 9) {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(KaidoTheme.signalAmber)

          Text(selectionReasonCopy(reason))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(KaidoTheme.routeWhite)

          Spacer(minLength: 4)
        }
      }
    }
    .padding(12)
    .background(KaidoTheme.asphalt.opacity(0.45))
    .clipShape(RoundedRectangle(cornerRadius: 13))
  }

  @ViewBuilder
  private var rejectedEntrances: some View {
    if !snapshot.rejectedCandidates.isEmpty {
      VStack(alignment: .leading, spacing: 9) {
        Text(
          copy.resolve(
            japanese: "近い候補は暗黙に採用されません",
            simplifiedChinese: "较近候选没有被静默采用",
            english: "Nearer candidates were not silently selected"
          )
        )
        .font(.system(size: 10, weight: .black, design: .monospaced))
        .tracking(0.55)
        .foregroundStyle(KaidoTheme.evidenceCoral)

        ForEach(snapshot.rejectedCandidates, id: \.facilityID) { candidate in
          HStack(alignment: .top, spacing: 10) {
            Image(systemName: "xmark.octagon.fill")
              .font(.system(size: 13, weight: .bold))
              .foregroundStyle(KaidoTheme.evidenceCoral)
              .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
              Text(
                model.fixture.facilityTitle(
                  for: candidate.facilityID,
                  locale: interfaceLocale
                )
              )
              .font(.system(size: 12, weight: .bold))
              .foregroundStyle(KaidoTheme.routeWhite)

              Text(rejectionCopy(candidate.reasonCodes))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(KaidoTheme.evidenceCoral)

              Text(
                "\(model.fixture.carriagewayTitle(for: candidate.targetCarriagewayID, locale: interfaceLocale)) · "
                  + "\(kilometers(candidate.straightLineDistanceKM)) · "
                  + "\(minutes(candidate.surfaceETAMinutes))"
              )
              .font(.system(size: 9, weight: .medium))
              .foregroundStyle(KaidoTheme.muted)
            }

            Spacer(minLength: 4)
          }
          .padding(10)
          .background(KaidoTheme.evidenceCoral.opacity(0.06))
          .clipShape(RoundedRectangle(cornerRadius: 11))
          .accessibilityElement(children: .combine)
        }
      }
    }
  }

  private func selectionReasonCopy(
    _ reason: EntranceRecommendationSelectionReason
  ) -> String {
    switch reason {
    case .exactDirectionalCarriageway:
      copy.resolve(
        japanese: "正確な進行方向の車線と一致",
        simplifiedChinese: "精确方向车道一致",
        english: "Matches the exact directional carriageway"
      )
    case .legalRouteJoin:
      copy.resolve(
        japanese: "現在の RoutePlan occurrence へ合法に接続可能",
        simplifiedChinese: "可合法接入当前 RoutePlan occurrence",
        english: "Legally joins the active RoutePlan occurrence"
      )
    case .approachAvailableAtEntryTime:
      copy.resolve(
        japanese: "到着予定時間帯に進入可能",
        simplifiedChinese: "预计到达时段可用",
        english: "Approach is available at the estimated arrival time"
      )
    case .lowestSurfaceETAAfterHardFilters:
      copy.resolve(
        japanese: "必須条件を通過した候補の中で一般道 ETA が最短",
        simplifiedChinese: "通过硬筛选后，地表 ETA 最短",
        english: "Lowest surface ETA after all hard filters"
      )
    }
  }

  private func rejectionCopy(_ reasonCodes: [String]) -> String {
    reasonCodes.map { reasonCode in
      switch reasonCode {
      case "NO_LEGAL_ROUTE_JOIN":
        copy.resolve(
          japanese: "現在の経路へ合法に接続できません",
          simplifiedChinese: "不能合法接入当前路线",
          english: "Cannot legally join the current route"
        )
      case "APPROACH_UNAVAILABLE_AT_ENTRY_TIME":
        copy.resolve(
          japanese: "到着予定時間帯は利用できません",
          simplifiedChinese: "预计到达时段不可用",
          english: "Unavailable at the estimated arrival time"
        )
      case "APPROACH_AVAILABILITY_UNKNOWN":
        copy.resolve(
          japanese: "到着予定時間帯の通行条件が不明です",
          simplifiedChinese: "预计到达时段的通行条件未知",
          english: "Passage conditions are unknown at the estimated arrival time"
        )
      default:
        reasonCode
      }
    }.joined(separator: " · ")
  }

  private func kilometers(_ value: Double) -> String {
    String(format: "%.1f km", value)
  }

  private func minutes(_ value: Double) -> String {
    let rounded = Int(value.rounded())
    return copy.resolve(
      japanese: "\(rounded) 分",
      simplifiedChinese: "\(rounded) 分钟",
      english: "\(rounded) min"
    )
  }

  private func rank(_ value: Int) -> String {
    copy.resolve(
      japanese: "\(value) 位",
      simplifiedChinese: "第 \(value)",
      english: "#\(value)"
    )
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }

  private var selectedFacilityTitle: String {
    model.fixture.facilityTitle(
      for: snapshot.selection.facilityID,
      locale: interfaceLocale
    )
  }

  private var selectedCarriagewayTitle: String {
    model.fixture.carriagewayTitle(
      for: snapshot.selection.targetCarriagewayID,
      locale: interfaceLocale
    )
  }
}

private struct EntranceMetric: View {
  let value: String
  let label: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value)
        .font(.system(size: 16, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.routeWhite)

      Text(label)
        .font(.system(size: 8, weight: .bold))
        .foregroundStyle(KaidoTheme.muted)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(9)
    .background(KaidoTheme.asphalt.opacity(0.5))
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }
}

private struct IdentityRow: View {
  let label: String
  let value: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(label)
        .font(.system(size: 7, weight: .black, design: .monospaced))
        .tracking(0.4)
        .foregroundStyle(KaidoTheme.muted)
        .frame(width: 112, alignment: .leading)

      Text(verbatim: value)
        .font(.system(size: 8, weight: .semibold, design: .monospaced))
        .foregroundStyle(KaidoTheme.routeWhite)
        .lineLimit(1)
        .minimumScaleFactor(0.65)
    }
  }
}
