import Foundation
import KaidoRouting
import SwiftUI

struct EntranceRecommendationPanel: View {
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
        Text("入口推荐")
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
        title: "方向优先",
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
          Text("推荐精确入口")
            .font(.system(size: 9, weight: .black, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(KaidoTheme.positionCyan)

          Text(snapshot.selectedFacilityTitle)
            .font(.system(size: 17, weight: .black, design: .rounded))
            .foregroundStyle(KaidoTheme.routeWhite)

          Text(snapshot.selectedCarriagewayTitle)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(KaidoTheme.muted)
        }

        Spacer()
      }

      HStack(spacing: 8) {
        EntranceMetric(
          value: minutes(snapshot.selection.surfaceETAMinutes),
          label: "地表预计"
        )
        EntranceMetric(
          value: kilometers(snapshot.selection.straightLineDistanceKM),
          label: "直线距离"
        )
        EntranceMetric(
          value: "第 \(snapshot.selection.straightLineDistanceRank)",
          label: "距离排名"
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
      "推荐精确入口，\(snapshot.selectedFacilityTitle)，目标车道\(snapshot.selectedCarriagewayTitle)，"
        + "地表预计\(minutes(snapshot.selection.surfaceETAMinutes))，"
        + "直线距离排名第\(snapshot.selection.straightLineDistanceRank)"
    )
  }

  private var selectionReasons: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text("为什么不是最近入口")
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
        Text("较近候选没有被静默采用")
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
              Text(candidate.facilityTitle)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(KaidoTheme.routeWhite)

              Text(rejectionCopy(candidate.reasonCodes))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(KaidoTheme.evidenceCoral)

              Text(
                "\(candidate.targetCarriagewayTitle) · "
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
      "精确方向车道一致"
    case .legalRouteJoin:
      "可合法接入当前 RoutePlan occurrence"
    case .approachAvailableAtEntryTime:
      "预计到达时段可用"
    case .lowestSurfaceETAAfterHardFilters:
      "通过硬筛选后，地表 ETA 最短"
    }
  }

  private func rejectionCopy(_ reasonCodes: [String]) -> String {
    reasonCodes.map { reasonCode in
      switch reasonCode {
      case "NO_LEGAL_ROUTE_JOIN":
        "不能合法接入当前路线"
      case "APPROACH_UNAVAILABLE_AT_ENTRY_TIME":
        "预计到达时段不可用"
      case "APPROACH_AVAILABILITY_UNKNOWN":
        "预计到达时段的通行条件未知"
      default:
        reasonCode
      }
    }.joined(separator: " · ")
  }

  private func kilometers(_ value: Double) -> String {
    String(format: "%.1f km", value)
  }

  private func minutes(_ value: Double) -> String {
    String(format: "%.0f min", value)
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
