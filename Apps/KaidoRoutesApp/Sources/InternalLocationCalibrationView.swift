import SwiftUI

struct InternalLocationCalibrationPanel: View {
  @ObservedObject var model: InternalLocationCalibrationModel

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header
      candidateIdentity
      transportPicker
      runMetadata
      metrics
      lastEvent
      controls
      privacyNotice
    }
    .padding(16)
    .background(KaidoTheme.instrument)
    .clipShape(RoundedRectangle(cornerRadius: 22))
    .overlay {
      RoundedRectangle(cornerRadius: 22)
        .stroke(KaidoTheme.positionCyan.opacity(0.45), lineWidth: 1)
    }
  }

  private var header: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 3) {
        Text("真机定位校准")
          .font(.system(size: 19, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)

        Text("INTERNAL · FOREGROUND · MEMORY ONLY")
          .font(.system(size: 9, weight: .bold, design: .monospaced))
          .tracking(0.7)
          .foregroundStyle(KaidoTheme.muted)
      }

      Spacer()

      StatusCapsule(
        title: model.state.label,
        color: model.state == .collecting
          ? KaidoTheme.positionCyan : KaidoTheme.evidenceCoral
      )
    }
  }

  private var candidateIdentity: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("K7 横滨北西线上行候选")
          .font(.system(size: 14, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)

        Spacer()

        Text("NO NAV AUTHORITY")
          .font(.system(size: 8, weight: .black, design: .monospaced))
          .foregroundStyle(KaidoTheme.evidenceCoral)
      }

      Text(verbatim: model.fixture.corridor.networkSnapshotID)
        .font(.system(size: 8, weight: .medium, design: .monospaced))
        .foregroundStyle(KaidoTheme.muted)
        .lineLimit(2)

      Text(
        "\(model.fixture.entryFacilityID) → \(model.fixture.exitFacilityID)"
      )
      .font(.system(size: 9, weight: .semibold, design: .monospaced))
      .foregroundStyle(KaidoTheme.muted)
      .lineLimit(2)

      Text(
        "\(model.fixture.corridor.occurrences.count) occurrences · "
          + "\(model.fixture.corridor.edges.count) corridor edges · "
          + "\(model.fixture.evidenceState)"
      )
      .font(.system(size: 9, weight: .bold, design: .monospaced))
      .foregroundStyle(KaidoTheme.positionCyan)
    }
    .padding(12)
    .background(KaidoTheme.asphalt.opacity(0.55))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "内部 K7 候选定位校准，\(model.fixture.corridor.occurrences.count) 个路线 occurrence，"
        + "无导航发布权限"
    )
  }

  private var transportPicker: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("FIELD TRANSPORT CONTEXT")
        .font(.system(size: 8, weight: .black, design: .monospaced))
        .tracking(0.55)
        .foregroundStyle(KaidoTheme.muted)

      Picker("现场连接上下文", selection: $model.transportMode) {
        ForEach(InternalCalibrationTransportMode.allCases) { mode in
          Text(mode.rawValue).tag(mode)
        }
      }
      .pickerStyle(.menu)
      .tint(KaidoTheme.routeWhite)
      .disabled(model.state == .collecting || model.state == .awaitingAuthorization)

      Text("有线或无线只能由乘客现场声明；不能从 CarPlay 连接状态推断。")
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(KaidoTheme.muted)
    }
  }

  private var runMetadata: some View {
    VStack(spacing: 8) {
      CalibrationTextField(
        title: "OPAQUE DEVICE CONFIG ID",
        text: $model.deviceConfigurationID
      )
      CalibrationTextField(
        title: "PRIVATE MOUNT DESCRIPTION",
        text: $model.mountDescription
      )
    }
    .disabled(model.state == .collecting || model.state == .awaitingAuthorization)
  }

  private var metrics: some View {
    VStack(spacing: 10) {
      HStack(spacing: 0) {
        Metric(value: "\(model.summary.entryCount)", label: "样本")
        DividerMark()
        Metric(value: "\(model.summary.matchedCount)", label: "匹配")
        DividerMark()
        Metric(
          value:
            "\(model.summary.adapterRejectionCount + model.summary.matcherRejectionCount)",
          label: "拒绝"
        )
      }

      HStack {
        CalibrationBadge(
          title: "PERMISSION",
          value: model.authorizationLabel
        )
        CalibrationBadge(
          title: "LAST CONFIDENCE",
          value: model.summary.lastConfidence?.rawValue ?? "—"
        )
      }

      if let report = model.report {
        CalibrationBadge(
          title: "REPORT GATE",
          value: report.gateStatus.rawValue
        )
      }
    }
  }

  private var lastEvent: some View {
    Text(model.lastEvent)
      .font(.system(size: 10, weight: .semibold))
      .foregroundStyle(KaidoTheme.muted)
      .accessibilityLabel("校准状态：\(model.lastEvent)")
  }

  private var controls: some View {
    HStack(spacing: 8) {
      Button {
        model.start()
      } label: {
        Label("开始", systemImage: "location.fill")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(CalibrationButtonStyle(active: model.canStart))
      .disabled(!model.canStart)

      Button {
        model.stop()
      } label: {
        Label("停止", systemImage: "stop.fill")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(CalibrationButtonStyle(active: model.canStop))
      .disabled(!model.canStop)

      Button {
        model.discard()
      } label: {
        Label("丢弃", systemImage: "trash")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(CalibrationButtonStyle(active: model.canDiscard))
      .disabled(!model.canDiscard)
    }
    .font(.system(size: 12, weight: .black))
  }

  private var privacyNotice: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("PRIVATE_RAW_LOCATION")
        .font(.system(size: 8, weight: .black, design: .monospaced))
        .tracking(0.55)
        .foregroundStyle(KaidoTheme.evidenceCoral)

      Text(
        "原始坐标只存在本次进程内存，不写文件、不显示、不共享。停止后报告仅含计数、"
          + "来源 cohort 与耗时；它不是现场可靠性通过，也不能发布路线。"
      )
      .font(.system(size: 10, weight: .medium))
      .foregroundStyle(KaidoTheme.muted)

      Text("\(model.fixture.attribution) · \(model.fixture.licence)")
        .font(.system(size: 8, weight: .semibold, design: .monospaced))
        .foregroundStyle(KaidoTheme.muted)
    }
  }
}

private struct CalibrationTextField: View {
  let title: String
  @Binding var text: String

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title)
        .font(.system(size: 8, weight: .black, design: .monospaced))
        .tracking(0.55)
        .foregroundStyle(KaidoTheme.muted)

      TextField("required", text: $text)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .foregroundStyle(KaidoTheme.routeWhite)
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(KaidoTheme.asphalt.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
  }
}

private struct CalibrationBadge: View {
  let title: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.system(size: 7, weight: .black, design: .monospaced))
        .tracking(0.45)
        .foregroundStyle(KaidoTheme.muted)

      Text(value)
        .font(.system(size: 8, weight: .bold, design: .monospaced))
        .foregroundStyle(KaidoTheme.routeWhite)
        .lineLimit(2)
        .minimumScaleFactor(0.65)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(9)
    .background(KaidoTheme.asphalt.opacity(0.45))
    .clipShape(RoundedRectangle(cornerRadius: 9))
  }
}

private struct CalibrationButtonStyle: ButtonStyle {
  let active: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .frame(height: 42)
      .foregroundStyle(active ? KaidoTheme.asphalt : KaidoTheme.muted)
      .background(
        active
          ? KaidoTheme.positionCyan.opacity(configuration.isPressed ? 0.7 : 1)
          : KaidoTheme.steel.opacity(0.28)
      )
      .clipShape(RoundedRectangle(cornerRadius: 10))
  }
}
