import KaidoDomain
import KaidoRouting
import SwiftUI

struct RouteAtlasHomeView: View {
  @StateObject private var model = KaidoRoutesAppModel()

  var body: some View {
    ZStack {
      KaidoTheme.asphalt
        .ignoresSafeArea()

      ScrollView {
        VStack(spacing: 14) {
          header
          atlasModePicker

          RouteAtlasCard(mode: model.atlasMode)
            .frame(height: model.atlasMode == .network ? 340 : 300)

          EntranceRecommendationPanel(model: model.entranceRecommendation)

          ParkedRouteEditorPanel(model: model.routeEditor)

          PreDriveReviewPanel(model: model.preDriveReview)

          InternalLocationCalibrationPanel(model: model.locationCalibration)

          if model.atlasMode == .k7Evidence {
            routeDossier
          }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 24)
      }
      .scrollIndicators(.hidden)
    }
    .preferredColorScheme(.dark)
  }

  private var header: some View {
    HStack(alignment: .center) {
      VStack(alignment: .leading, spacing: 1) {
        Text("KAIDO ROUTES")
          .font(.system(size: 24, weight: .black, design: .rounded))
          .tracking(-0.8)
          .foregroundStyle(KaidoTheme.routeWhite)

        Text("首都高速 · ROUTE ATLAS")
          .font(.system(size: 10, weight: .bold, design: .monospaced))
          .tracking(1.35)
          .foregroundStyle(KaidoTheme.muted)
      }

      Spacer()

      StatusCapsule(
        title: "REVIEW",
        color: KaidoTheme.evidenceCoral
      )
    }
    .accessibilityElement(children: .combine)
  }

  private var atlasModePicker: some View {
    HStack(spacing: 4) {
      ForEach(RouteAtlasMode.allCases) { mode in
        Button {
          withAnimation(.easeOut(duration: 0.18)) {
            model.atlasMode = mode
          }
        } label: {
          Text(mode.label)
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .foregroundStyle(
              model.atlasMode == mode
                ? KaidoTheme.asphalt
                : KaidoTheme.muted
            )
            .background(
              model.atlasMode == mode
                ? KaidoTheme.routeWhite
                : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(
          model.atlasMode == mode ? .isSelected : []
        )
      }
    }
    .padding(4)
    .background(KaidoTheme.instrument)
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }

  private var routeDossier: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 3) {
          Text("K7 · 横浜北西線")
            .font(.system(size: 17, weight: .black, design: .rounded))
            .foregroundStyle(KaidoTheme.routeWhite)

          Text("横浜青葉入口 → 横浜港北出口")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(KaidoTheme.muted)
        }

        Spacer()

        Text("CANDIDATE")
          .font(.system(size: 9, weight: .black, design: .monospaced))
          .tracking(0.8)
          .foregroundStyle(KaidoTheme.evidenceCoral)
      }

      HStack(spacing: 0) {
        Metric(value: "13", label: "路线段")
        DividerMark()
        Metric(value: "2", label: "高速分流")
        DividerMark()
        Metric(value: "0", label: "地表后继")
      }

      Button {
      } label: {
        HStack {
          Image(systemName: "lock.fill")
          Text("导航拓扑未发布")
          Spacer()
          Text("26 / 26 仅识别")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
        }
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(KaidoTheme.muted)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(KaidoTheme.steel.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 11))
      }
      .buttonStyle(.plain)
      .disabled(true)
      .accessibilityLabel("导航拓扑尚未发布")
    }
    .padding(16)
    .background(KaidoTheme.instrument)
    .clipShape(RoundedRectangle(cornerRadius: 18))
    .overlay {
      RoundedRectangle(cornerRadius: 18)
        .stroke(KaidoTheme.steel.opacity(0.8), lineWidth: 1)
    }
  }
}

private struct RouteAtlasCard: View {
  let mode: RouteAtlasMode

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .topTrailing) {
        KaidoTheme.instrument

        SVGDocumentView(resourceName: mode.resourceName)
          .aspectRatio(mode.aspectRatio, contentMode: .fit)
          .frame(
            maxWidth: proxy.size.width - 20,
            maxHeight: proxy.size.height - 20
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .padding(10)
          .id(mode)

        evidenceRail
          .padding(14)
      }
      .clipShape(RoundedRectangle(cornerRadius: 24))
      .overlay {
        RoundedRectangle(cornerRadius: 24)
          .stroke(KaidoTheme.steel.opacity(0.85), lineWidth: 1)
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(mode.accessibilityLabel)
    }
    .frame(minHeight: 300)
  }

  private var evidenceRail: some View {
    VStack(alignment: .trailing, spacing: 6) {
      Text("N")
        .font(.system(size: 12, weight: .black, design: .monospaced))
        .foregroundStyle(KaidoTheme.routeWhite)

      Rectangle()
        .fill(KaidoTheme.routeWhite.opacity(0.42))
        .frame(width: 1, height: 28)

      Text(mode == .network ? "CONTEXT" : "EVIDENCE")
        .font(.system(size: 8, weight: .black, design: .monospaced))
        .tracking(0.8)
        .foregroundStyle(KaidoTheme.evidenceCoral)
        .rotationEffect(.degrees(90))
        .frame(width: 14, height: 58)
    }
  }
}

private struct ParkedRouteEditorPanel: View {
  @ObservedObject var model: ParkedRouteEditorModel

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      editorHeader
      entrance
      RouteOccurrenceRail(occurrences: model.snapshot.occurrences)

      if model.snapshot.state == .editing {
        currentDecision
        if !model.snapshot.availableLapCandidates.isEmpty {
          reviewedLapActions
        }
      } else {
        selectedExit
      }

      if let lastErrorCode = model.lastErrorCode {
        Text(lastErrorCode)
          .font(.system(size: 10, weight: .bold, design: .monospaced))
          .foregroundStyle(KaidoTheme.evidenceCoral)
          .accessibilityLabel("路线编辑错误：\(lastErrorCode)")
      }

      editorActions
    }
    .padding(16)
    .background(KaidoTheme.instrument)
    .clipShape(RoundedRectangle(cornerRadius: 22))
    .overlay {
      RoundedRectangle(cornerRadius: 22)
        .stroke(KaidoTheme.signalAmber.opacity(0.45), lineWidth: 1)
    }
  }

  private var editorHeader: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 3) {
        Text("停驻路线编排")
          .font(.system(size: 19, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)

        Text("SYNTHETIC CATALOG · ROUTE FIRST")
          .font(.system(size: 9, weight: .bold, design: .monospaced))
          .tracking(0.85)
          .foregroundStyle(KaidoTheme.muted)

        Text(verbatim: model.snapshot.networkSnapshotID)
          .font(.system(size: 8, weight: .medium, design: .monospaced))
          .foregroundStyle(KaidoTheme.muted.opacity(0.78))
      }

      Spacer()

      StatusCapsule(
        title: model.interaction.rawValue,
        color: KaidoTheme.signalAmber
      )
    }
  }

  private var entrance: some View {
    HStack(spacing: 12) {
      ZStack {
        Circle()
          .fill(KaidoTheme.signalAmber)
          .frame(width: 30, height: 30)

        Image(systemName: "arrow.down.to.line.compact")
          .font(.system(size: 12, weight: .black))
          .foregroundStyle(KaidoTheme.asphalt)
      }

      VStack(alignment: .leading, spacing: 2) {
        Text(model.fixture.entranceTitle)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(KaidoTheme.routeWhite)

        Text(verbatim: model.snapshot.entranceFacilityID)
          .font(.system(size: 9, weight: .medium, design: .monospaced))
          .foregroundStyle(KaidoTheme.muted)
          .lineLimit(1)
          .minimumScaleFactor(0.65)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "精确入口，\(model.fixture.entranceTitle)，\(model.snapshot.entranceFacilityID)"
    )
  }

  private var currentDecision: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("当前分岔")
            .font(.system(size: 9, weight: .black, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(KaidoTheme.signalAmber)

          Text(model.decisionTitle)
            .font(.system(size: 16, weight: .black, design: .rounded))
            .foregroundStyle(KaidoTheme.routeWhite)
        }

        Spacer()

        Text("\(model.snapshot.availableChoices.count) LEGAL")
          .font(.system(size: 9, weight: .black, design: .monospaced))
          .foregroundStyle(KaidoTheme.muted)
      }

      HStack(alignment: .top, spacing: 8) {
        DecisionIdentity(
          label: "INCOMING APPROACH",
          value: model.snapshot.incomingApproachID ?? "—"
        )
        DecisionIdentity(
          label: "JCT COMPLEX",
          value: model.snapshot.junctionComplexID ?? "—"
        )
      }

      VStack(spacing: 8) {
        ForEach(model.snapshot.availableChoices, id: \.id) { choice in
          Button {
            model.select(choiceID: choice.id)
          } label: {
            HStack(spacing: 12) {
              Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(KaidoTheme.signalAmber)
                .frame(width: 22)

              VStack(alignment: .leading, spacing: 2) {
                Text(model.title(for: choice))
                  .font(.system(size: 14, weight: .bold))
                  .foregroundStyle(KaidoTheme.routeWhite)

                Text(model.detail(for: choice))
                  .font(.system(size: 10, weight: .medium))
                  .foregroundStyle(KaidoTheme.muted)
              }

              Spacer(minLength: 8)

              Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(KaidoTheme.muted)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 52)
            .background(KaidoTheme.asphalt.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
              RoundedRectangle(cornerRadius: 12)
                .stroke(KaidoTheme.steel.opacity(0.8), lineWidth: 1)
            }
          }
          .buttonStyle(.plain)
          .accessibilityHint("提交已审核 choice ID \(choice.id)")
        }
      }
    }
  }

  private var selectedExit: some View {
    HStack(spacing: 12) {
      Image(systemName: "checkmark.seal.fill")
        .font(.system(size: 22, weight: .bold))
        .foregroundStyle(KaidoTheme.positionCyan)

      VStack(alignment: .leading, spacing: 2) {
        Text("明确出口已选择")
          .font(.system(size: 14, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)

        Text(verbatim: model.snapshot.selectedExitFacilityID ?? "—")
          .font(.system(size: 9, weight: .medium, design: .monospaced))
          .foregroundStyle(KaidoTheme.muted)
      }

      Spacer()
    }
    .padding(12)
    .background(KaidoTheme.positionCyan.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(KaidoTheme.positionCyan.opacity(0.35), lineWidth: 1)
    }
  }

  private var reviewedLapActions: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        ZStack {
          Circle()
            .stroke(KaidoTheme.signalAmber.opacity(0.55), lineWidth: 1)
            .frame(width: 34, height: 34)

          Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(KaidoTheme.signalAmber)
        }

        VStack(alignment: .leading, spacing: 2) {
          Text("已审核闭合圈")
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundStyle(KaidoTheme.routeWhite)

          Text("只复制 session 给出的 occurrence 序列")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(KaidoTheme.muted)
        }

        Spacer()

        Text("\(model.snapshot.availableLapCandidates.count) READY")
          .font(.system(size: 9, weight: .black, design: .monospaced))
          .foregroundStyle(KaidoTheme.signalAmber)
      }

      ForEach(
        Array(model.snapshot.availableLapCandidates.enumerated()),
        id: \.element.id
      ) { index, candidate in
        Button {
          model.duplicate(lapCandidateID: candidate.id)
        } label: {
          HStack(spacing: 10) {
            Text(String(format: "L%02d", index + 1))
              .font(.system(size: 10, weight: .black, design: .monospaced))
              .foregroundStyle(KaidoTheme.asphalt)
              .frame(width: 34, height: 26)
              .background(KaidoTheme.signalAmber)
              .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 2) {
              Text("再加一圈")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(KaidoTheme.routeWhite)

              Text("\(candidate.sourceOccurrenceIDs.count) 个 occurrence · 新建独立 ID")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(KaidoTheme.muted)
            }

            Spacer()

            Image(systemName: "plus")
              .font(.system(size: 11, weight: .black))
              .foregroundStyle(KaidoTheme.signalAmber)
          }
          .padding(.horizontal, 11)
          .frame(minHeight: 48)
          .background(KaidoTheme.signalAmber.opacity(0.08))
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .overlay {
            RoundedRectangle(cornerRadius: 12)
              .stroke(
                KaidoTheme.signalAmber.opacity(0.42),
                style: StrokeStyle(lineWidth: 1, dash: [5, 3])
              )
          }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
          "按第 \(index + 1) 个已审核闭合序列再加一圈"
        )
        .accessibilityHint("提交 session 候选 \(candidate.id) 并创建全新 occurrence ID")
      }
    }
    .padding(12)
    .background(KaidoTheme.asphalt.opacity(0.36))
    .clipShape(RoundedRectangle(cornerRadius: 14))
  }

  private var editorActions: some View {
    HStack(spacing: 10) {
      Button {
        model.undo()
      } label: {
        Label("撤销", systemImage: "arrow.uturn.backward")
          .font(.system(size: 13, weight: .bold))
          .frame(maxWidth: .infinity)
          .frame(height: 44)
      }
      .buttonStyle(.plain)
      .foregroundStyle(model.canUndo ? KaidoTheme.routeWhite : KaidoTheme.muted)
      .background(KaidoTheme.steel.opacity(model.canUndo ? 0.65 : 0.28))
      .clipShape(RoundedRectangle(cornerRadius: 11))
      .disabled(!model.canUndo)

      Button {
        model.compile()
      } label: {
        Label(
          model.compiledRoutePlan == nil ? "编译路线" : "路线已编译",
          systemImage: model.compiledRoutePlan == nil ? "flag.checkered" : "checkmark"
        )
        .font(.system(size: 13, weight: .black))
        .frame(maxWidth: .infinity)
        .frame(height: 44)
      }
      .buttonStyle(.plain)
      .foregroundStyle(
        model.canCompile && model.compiledRoutePlan == nil
          ? KaidoTheme.asphalt
          : KaidoTheme.muted
      )
      .background(
        model.canCompile && model.compiledRoutePlan == nil
          ? KaidoTheme.signalAmber
          : KaidoTheme.steel.opacity(0.28)
      )
      .clipShape(RoundedRectangle(cornerRadius: 11))
      .disabled(!model.canCompile || model.compiledRoutePlan != nil)
    }
  }
}

private struct DecisionIdentity: View {
  let label: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(label)
        .font(.system(size: 8, weight: .black, design: .monospaced))
        .tracking(0.55)
        .foregroundStyle(KaidoTheme.muted)

      Text(verbatim: value)
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .foregroundStyle(KaidoTheme.routeWhite)
        .lineLimit(2)
        .minimumScaleFactor(0.72)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .background(KaidoTheme.asphalt.opacity(0.5))
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }
}

private struct RouteOccurrenceRail: View {
  let occurrences: [RouteOccurrence]

  var body: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 0) {
        ForEach(Array(occurrences.enumerated()), id: \.element.id) { index, occurrence in
          OccurrenceNode(occurrence: occurrence)

          if index < occurrences.count - 1 {
            Rectangle()
              .fill(KaidoTheme.signalAmber.opacity(0.55))
              .frame(width: 22, height: 2)
          }
        }
      }
      .padding(.vertical, 2)
    }
    .scrollIndicators(.hidden)
    .accessibilityLabel("路线 occurrence 序列，共 \(occurrences.count) 项")
  }
}

private struct OccurrenceNode: View {
  let occurrence: RouteOccurrence

  var body: some View {
    HStack(spacing: 8) {
      ZStack {
        Circle()
          .fill(markerColor.opacity(0.15))
          .frame(width: 30, height: 30)

        Text(String(format: "%02d", occurrence.index + 1))
          .font(.system(size: 9, weight: .black, design: .monospaced))
          .foregroundStyle(markerColor)
      }

      VStack(alignment: .leading, spacing: 2) {
        Text(kindLabel)
          .font(.system(size: 8, weight: .black, design: .monospaced))
          .tracking(0.5)
          .foregroundStyle(KaidoTheme.muted)

        Text(shortEntityID)
          .font(.system(size: 10, weight: .bold, design: .monospaced))
          .foregroundStyle(KaidoTheme.routeWhite)
          .lineLimit(1)
      }
    }
    .frame(width: 122, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "第 \(occurrence.index + 1) 个 occurrence，\(occurrence.kind.rawValue)，\(occurrence.entityID)"
    )
  }

  private var markerColor: Color {
    occurrence.kind == .junctionMovement
      ? KaidoTheme.signalAmber
      : KaidoTheme.routeWhite
  }

  private var kindLabel: String {
    switch occurrence.kind {
    case .edge:
      "ROAD EDGE"
    case .junctionMovement:
      "JCT MOVE"
    case .paVisit:
      "PA VISIT"
    }
  }

  private var shortEntityID: String {
    occurrence.entityID
      .split(separator: ".")
      .suffix(2)
      .joined(separator: " · ")
  }
}

struct StatusCapsule: View {
  let title: String
  let color: Color

  var body: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(color)
        .frame(width: 7, height: 7)

      Text(title)
        .font(.system(size: 10, weight: .black, design: .monospaced))
        .tracking(0.8)
    }
    .foregroundStyle(color)
    .padding(.horizontal, 10)
    .frame(height: 28)
    .background(color.opacity(0.1))
    .clipShape(Capsule())
    .overlay {
      Capsule()
        .stroke(color.opacity(0.45), lineWidth: 1)
    }
  }
}

struct Metric: View {
  let value: String
  let label: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value)
        .font(.system(size: 20, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.routeWhite)

      Text(label)
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(KaidoTheme.muted)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct DividerMark: View {
  var body: some View {
    Rectangle()
      .fill(KaidoTheme.steel)
      .frame(width: 1, height: 34)
      .padding(.horizontal, 10)
  }
}

#Preview("Route Atlas") {
  RouteAtlasHomeView()
}
