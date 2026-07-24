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

          RouteAtlasCard(
            mode: model.atlasMode,
            attribution: model.attribution(for: model.atlasMode)
          )

          EntranceRecommendationPanel(model: model.entranceRecommendation)

          ParkedRouteEditorPanel(model: model.routeEditor)

          PreDriveReviewPanel(model: model.preDriveReview)

          GuidanceLanguagePreviewPanel(
            model: model.guidanceLanguagePreview
          )

          SyntheticDrivingPreviewPanel(
            model: model.syntheticDrivingPreview
          )

          SyntheticProductRuntimePanel(
            model: model.syntheticProductRuntime
          )

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

struct RouteAtlasCard: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale

  let mode: RouteAtlasMode
  let attribution: RouteAtlasAttribution

  var body: some View {
    VStack(spacing: 0) {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mode.accessibilityLabel(for: interfaceLocale))
      }
      .frame(height: mode.mapViewportHeight)

      RouteAtlasAttributionStrip(attribution: attribution)
    }
    .background(KaidoTheme.instrument)
    .clipShape(RoundedRectangle(cornerRadius: 24))
    .overlay {
      RoundedRectangle(cornerRadius: 24)
        .stroke(KaidoTheme.steel.opacity(0.85), lineWidth: 1)
    }
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

private struct RouteAtlasAttributionStrip: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale

  let attribution: RouteAtlasAttribution

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 12) {
        sourceLink
        Spacer(minLength: 8)
        licenceLink
      }

      VStack(alignment: .leading, spacing: 7) {
        sourceLink
        licenceLink
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(KaidoTheme.asphalt.opacity(0.86))
    .overlay(alignment: .top) {
      Rectangle()
        .fill(KaidoTheme.steel.opacity(0.8))
        .frame(height: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("route-atlas-attribution-strip")
    .accessibilityValue("ALWAYS_VISIBLE · ADJACENT_TO_MAP · NATIVE_LINKS")
  }

  private var sourceLink: some View {
    Link(destination: attribution.sourceURL) {
      HStack(spacing: 5) {
        Text(attribution.attribution)
          .lineLimit(2)

        Image(systemName: "arrow.up.right")
          .font(.system(size: 7, weight: .black))
      }
      .font(.system(size: 9, weight: .bold, design: .monospaced))
      .foregroundStyle(KaidoTheme.muted)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      copy.resolve(
        japanese: "地図データの出典、\(attribution.attribution)",
        simplifiedChinese: "地图数据来源，\(attribution.attribution)",
        english: "Map data source, \(attribution.attribution)"
      )
    )
    .accessibilityHint(
      copy.resolve(
        japanese: "\(attribution.sourceLabel) の出典説明を開く",
        simplifiedChinese: "打开 \(attribution.sourceLabel) 来源说明",
        english: "Open the \(attribution.sourceLabel) source statement"
      )
    )
    .accessibilityIdentifier(attribution.sourceAccessibilityIdentifier)
  }

  private var licenceLink: some View {
    Link(destination: attribution.licenceURL) {
      HStack(spacing: 5) {
        Text(attribution.licenceLabel)

        Image(systemName: "doc.text")
          .font(.system(size: 7, weight: .black))
      }
      .font(.system(size: 9, weight: .black, design: .monospaced))
      .foregroundStyle(KaidoTheme.positionCyan)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      copy.resolve(
        japanese: "データライセンス、\(attribution.licenceIdentifier)",
        simplifiedChinese: "数据许可证，\(attribution.licenceIdentifier)",
        english: "Data licence, \(attribution.licenceIdentifier)"
      )
    )
    .accessibilityHint(
      copy.resolve(
        japanese: "ライセンス全文を開く",
        simplifiedChinese: "打开许可证全文",
        english: "Open the full licence"
      )
    )
    .accessibilityIdentifier(attribution.licenceAccessibilityIdentifier)
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }
}

struct RouteAtlasAttributionPreviewHost: View {
  private let attribution: RouteAtlasAttribution

  init() {
    do {
      attribution = try RouteAtlasAttributionCatalog.bundled()
        .attribution(for: .k7Evidence)
    } catch {
      preconditionFailure("Invalid Route Atlas attribution fixture: \(error)")
    }
  }

  var body: some View {
    ScrollView {
      RouteAtlasCard(
        mode: .k7Evidence,
        attribution: attribution
      )
      .padding(18)
    }
    .background(KaidoTheme.asphalt.ignoresSafeArea())
    .accessibilityIdentifier("route-atlas-attribution-preview")
  }
}

struct ParkedRouteEditorPanel: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale
  @ObservedObject var model: ParkedRouteEditorModel

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      editorHeader
      entrance
      RouteOccurrenceRail(occurrences: model.snapshot.occurrences)

      if model.corridorResolution?.state == .resolved {
        corridorResolutionReceipt
      }

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
          .accessibilityLabel(
            copy.resolve(
              japanese: "経路編集エラー：\(lastErrorCode)",
              simplifiedChinese: "路线编辑错误：\(lastErrorCode)",
              english: "Route editor error: \(lastErrorCode)"
            )
          )
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
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("kr-u03-editor-panel")
  }

  private var editorHeader: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 3) {
        Text(
          copy.resolve(
            japanese: "停車中の経路作成",
            simplifiedChinese: "停驻路线编排",
            english: "Parked route authoring"
          )
        )
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
        Text(model.entranceTitle(for: interfaceLocale))
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
      copy.resolve(
        japanese:
          "正確な入口、\(model.entranceTitle(for: interfaceLocale))、\(model.snapshot.entranceFacilityID)",
        simplifiedChinese:
          "精确入口，\(model.entranceTitle(for: interfaceLocale))，\(model.snapshot.entranceFacilityID)",
        english:
          "Exact entrance, \(model.entranceTitle(for: interfaceLocale)), \(model.snapshot.entranceFacilityID)"
      )
    )
  }

  private var currentDecision: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(
            copy.resolve(
              japanese: "現在の分岐",
              simplifiedChinese: "当前分岔",
              english: "CURRENT DECISION"
            )
          )
          .font(.system(size: 9, weight: .black, design: .monospaced))
          .tracking(0.8)
          .foregroundStyle(KaidoTheme.signalAmber)

          Text(model.decisionTitle(for: interfaceLocale))
            .font(.system(size: 16, weight: .black, design: .rounded))
            .foregroundStyle(KaidoTheme.routeWhite)
            .accessibilityIdentifier("route-editor-current-decision")
            .accessibilityValue(
              model.snapshot.currentDecisionPointID ?? "NONE"
            )
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

      if let resolution = activeCorridorResolution {
        corridorResolutionChoices(resolution)
      } else {
        if model.canSubmitFreehandCorridor {
          SyntheticFreehandCorridorPad {
            model.submitFreehandCorridor()
          }
        }
        legalChoiceButtons
      }
    }
  }

  private var activeCorridorResolution: ParkedCorridorResolutionSnapshot? {
    guard let resolution = model.corridorResolution,
      resolution.decisionPointID == model.snapshot.currentDecisionPointID,
      resolution.state == .confirmationRequired
        || resolution.state == .resolutionRequired
    else {
      return nil
    }
    return resolution
  }

  private var legalChoiceButtons: some View {
    VStack(spacing: 8) {
      ForEach(model.snapshot.availableChoices, id: \.id) { choice in
        Button {
          model.select(choiceID: choice.id)
        } label: {
          routeChoiceLabel(choice)
        }
        .buttonStyle(.plain)
        .accessibilityHint(
          copy.resolve(
            japanese: "審査済み choice ID \(choice.id) を送信",
            simplifiedChinese: "提交已审核 choice ID \(choice.id)",
            english: "Submit reviewed choice ID \(choice.id)"
          )
        )
      }
    }
  }

  private func corridorResolutionChoices(
    _ resolution: ParkedCorridorResolutionSnapshot
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label(
          copy.resolve(
            japanese: "描画した経路候補が複数あります",
            simplifiedChinese: "手绘走廊有歧义",
            english: "Drawn corridor is ambiguous"
          ),
          systemImage: "point.3.filled.connected.trianglepath.dotted"
        )
        .font(.system(size: 13, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.signalAmber)

        Spacer()

        Text("\(resolution.candidateChoices.count) REVIEWED")
          .font(.system(size: 9, weight: .black, design: .monospaced))
          .foregroundStyle(KaidoTheme.signalAmber)
      }

      Text(
        copy.resolve(
          japanese: "停車中に現在の合法な分岐を選んでください。描画だけでは経路を作成しません。",
          simplifiedChinese: "停车状态下选择一个当前合法分岔；手势本身不会创建路线。",
          english:
            "While parked, choose one currently legal decision; the gesture itself never authors a route."
        )
      )
      .font(.system(size: 10, weight: .medium))
      .foregroundStyle(KaidoTheme.muted)

      ForEach(
        Array(resolution.candidateChoices.enumerated()),
        id: \.element.id
      ) { index, choice in
        Button {
          model.resolveFreehandCorridor(choiceID: choice.id)
        } label: {
          routeChoiceLabel(choice)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("corridor-candidate-\(index)")
      }
    }
    .padding(12)
    .background(KaidoTheme.signalAmber.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .stroke(
          KaidoTheme.signalAmber.opacity(0.55),
          style: StrokeStyle(lineWidth: 1, dash: [6, 4])
        )
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("corridor-resolution-card")
    .accessibilityValue(resolution.state.rawValue)
  }

  private func routeChoiceLabel(
    _ choice: ReviewedRouteEditorChoice
  ) -> some View {
    HStack(spacing: 12) {
      Image(systemName: "arrow.triangle.branch")
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(KaidoTheme.signalAmber)
        .frame(width: 22)

      VStack(alignment: .leading, spacing: 2) {
        Text(model.title(for: choice, locale: interfaceLocale))
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(KaidoTheme.routeWhite)

        Text(model.detail(for: choice, locale: interfaceLocale))
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

  private var corridorResolutionReceipt: some View {
    Label(
      copy.resolve(
        japanese: "描画候補を確認済み。経路への追加は editor session が実行",
        simplifiedChinese: "已确认手绘候选；路线由 editor session 追加",
        english: "Drawn candidate confirmed; the editor session appends the route"
      ),
      systemImage: "checkmark.circle.fill"
    )
    .font(.system(size: 11, weight: .bold))
    .foregroundStyle(KaidoTheme.positionCyan)
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(KaidoTheme.positionCyan.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 11))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      copy.resolve(
        japanese:
          "描画した経路候補を確認済み、\(model.corridorResolution?.selectedChoiceID ?? "選択不明")",
        simplifiedChinese:
          "手绘走廊候选已确认，\(model.corridorResolution?.selectedChoiceID ?? "未知选择")",
        english:
          "Drawn corridor candidate confirmed, \(model.corridorResolution?.selectedChoiceID ?? "unknown choice")"
      )
    )
    .accessibilityIdentifier("corridor-resolution-selected")
  }

  private var selectedExit: some View {
    HStack(spacing: 12) {
      Image(systemName: "checkmark.seal.fill")
        .font(.system(size: 22, weight: .bold))
        .foregroundStyle(KaidoTheme.positionCyan)

      VStack(alignment: .leading, spacing: 2) {
        Text(
          copy.resolve(
            japanese: "明示した出口を選択済み",
            simplifiedChinese: "明确出口已选择",
            english: "Explicit exit selected"
          )
        )
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
          Text(
            copy.resolve(
              japanese: "審査済みの閉ループ",
              simplifiedChinese: "已审核闭合圈",
              english: "Reviewed closed lap"
            )
          )
          .font(.system(size: 13, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)

          Text(
            copy.resolve(
              japanese: "session が返した occurrence 列だけを複製",
              simplifiedChinese: "只复制 session 给出的 occurrence 序列",
              english: "Copies only the occurrence sequence supplied by the session"
            )
          )
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
              Text(
                copy.resolve(
                  japanese: "もう 1 周追加",
                  simplifiedChinese: "再加一圈",
                  english: "Add another lap"
                )
              )
              .font(.system(size: 13, weight: .black))
              .foregroundStyle(KaidoTheme.routeWhite)

              Text(
                copy.resolve(
                  japanese:
                    "\(candidate.sourceOccurrenceIDs.count) occurrence・新しい独立 ID",
                  simplifiedChinese:
                    "\(candidate.sourceOccurrenceIDs.count) 个 occurrence · 新建独立 ID",
                  english:
                    "\(candidate.sourceOccurrenceIDs.count) occurrences · new independent IDs"
                )
              )
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
          copy.resolve(
            japanese: "審査済み閉ループ \(index + 1) をもう 1 周追加",
            simplifiedChinese: "按第 \(index + 1) 个已审核闭合序列再加一圈",
            english: "Add another lap using reviewed closed sequence \(index + 1)"
          )
        )
        .accessibilityHint(
          copy.resolve(
            japanese:
              "session 候補 \(candidate.id) を送信して新しい occurrence ID を作成",
            simplifiedChinese:
              "提交 session 候选 \(candidate.id) 并创建全新 occurrence ID",
            english:
              "Submit session candidate \(candidate.id) and create fresh occurrence IDs"
          )
        )
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
        Label(
          copy.resolve(
            japanese: "元に戻す",
            simplifiedChinese: "撤销",
            english: "Undo"
          ),
          systemImage: "arrow.uturn.backward"
        )
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
          model.compiledRoutePlan == nil
            ? copy.resolve(
              japanese: "経路をコンパイル",
              simplifiedChinese: "编译路线",
              english: "Compile route"
            )
            : copy.resolve(
              japanese: "経路コンパイル済み",
              simplifiedChinese: "路线已编译",
              english: "Route compiled"
            ),
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
      .accessibilityIdentifier("route-editor-compile")
    }
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }
}

private struct SyntheticFreehandCorridorPad: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale
  @State private var points: [CGPoint] = []

  let onCompleted: () -> Void

  var body: some View {
    Button(action: onCompleted) {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(
              copy.resolve(
                japanese: "進みたい方向を描く",
                simplifiedChinese: "手绘想走的方向",
                english: "Draw the intended direction"
              )
            )
            .font(.system(size: 12, weight: .black, design: .rounded))
            .foregroundStyle(KaidoTheme.routeWhite)

            Text("SYNTHETIC MATCH · PARKED ONLY")
              .font(.system(size: 8, weight: .black, design: .monospaced))
              .foregroundStyle(KaidoTheme.evidenceCoral)
          }

          Spacer()

          Image(systemName: "pencil.and.scribble")
            .foregroundStyle(KaidoTheme.positionCyan)
        }

        Canvas { context, _ in
          guard let first = points.first else { return }
          var path = Path()
          path.move(to: first)
          for point in points.dropFirst() {
            path.addLine(to: point)
          }
          context.stroke(
            path,
            with: .color(KaidoTheme.positionCyan),
            style: StrokeStyle(
              lineWidth: 5,
              lineCap: .round,
              lineJoin: .round,
              dash: [8, 5]
            )
          )
        }
        .frame(height: 104)
        .background(KaidoTheme.asphalt.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
          RoundedRectangle(cornerRadius: 12)
            .stroke(KaidoTheme.positionCyan.opacity(0.45), lineWidth: 1)
        }
        .contentShape(Rectangle())
      }
      .padding(12)
      .background(KaidoTheme.positionCyan.opacity(0.06))
      .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    .buttonStyle(.plain)
    .simultaneousGesture(
      DragGesture(minimumDistance: 0)
        .onChanged { value in
          points.append(value.location)
        }
        .onEnded { _ in
          guard points.count > 1 else {
            points = []
            return
          }
          onCompleted()
        }
    )
    .accessibilityLabel(
      copy.resolve(
        japanese:
          "合成の経路描画領域。ジェスチャーは固定テスト候補を読み込むだけで、経路を直接作成しません。",
        simplifiedChinese:
          "合成手绘走廊区域。手势只加载固定测试候选，不会直接创建路线。",
        english:
          "Synthetic corridor drawing area. The gesture loads fixed test candidates and never authors a route directly."
      )
    )
    .accessibilityHint(
      copy.resolve(
        japanese: "ダブルタップで合成ジェスチャー候補を送信",
        simplifiedChinese: "双击可提交合成手势候选",
        english: "Double-tap to submit the synthetic gesture candidate"
      )
    )
    .accessibilityIdentifier("corridor-draw-pad")
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
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
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale

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
    .accessibilityLabel(
      copy.resolve(
        japanese: "経路 occurrence 列、全 \(occurrences.count) 項目",
        simplifiedChinese: "路线 occurrence 序列，共 \(occurrences.count) 项",
        english: "Route occurrence sequence, \(occurrences.count) items"
      )
    )
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }
}

private struct OccurrenceNode: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale

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
      copy.resolve(
        japanese:
          "\(occurrence.index + 1) 番目の occurrence、\(occurrence.kind.rawValue)、\(occurrence.entityID)",
        simplifiedChinese:
          "第 \(occurrence.index + 1) 个 occurrence，\(occurrence.kind.rawValue)，\(occurrence.entityID)",
        english:
          "Occurrence \(occurrence.index + 1), \(occurrence.kind.rawValue), \(occurrence.entityID)"
      )
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

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
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
