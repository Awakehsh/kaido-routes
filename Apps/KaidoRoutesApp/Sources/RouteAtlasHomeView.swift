import SwiftUI

struct RouteAtlasHomeView: View {
  @StateObject private var model = KaidoRoutesAppModel()

  var body: some View {
    ZStack {
      KaidoTheme.asphalt
        .ignoresSafeArea()

      VStack(spacing: 14) {
        header
        atlasModePicker

        RouteAtlasCard(mode: model.atlasMode)
          .frame(maxHeight: .infinity)

        routeDossier
      }
      .padding(.horizontal, 18)
      .padding(.top, 8)
      .padding(.bottom, 12)
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

private struct StatusCapsule: View {
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

private struct Metric: View {
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

private struct DividerMark: View {
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
