import Foundation
import KaidoDomain
import KaidoPresentation
import SwiftUI

struct ProductJunctionInsetPresentation: Equatable {
  enum SelectedBranch: Hashable {
    case left
    case right
  }

  let decisionZoneID: String
  let movementOccurrenceID: String
  let selectedBranch: SelectedBranch
  let distanceMeters: Double
  let japaneseSignText: String
  let localizedInstruction: String
  let routeShield: String?

  init?(
    _ surface: NavigationSurfacePresentation,
    navigationSnapshot: NavigationSnapshot?
  ) {
    guard
      let navigationSnapshot,
      let activeFrame = navigationSnapshot.activeGuidanceFrame,
      navigationSnapshot.emittedGuidancePromptIDs.contains(
        activeFrame.promptID
      ),
      activeFrame.decisionZoneID == surface.decisionZoneID,
      activeFrame.movementOccurrenceID == surface.nextMovementOccurrenceID
    else {
      return nil
    }

    let selectedBranch: SelectedBranch
    switch surface.maneuver {
    case .keepLeft, .takeExitLeft, .mergeLeft:
      selectedBranch = .left
    case .keepRight, .takeExitRight, .mergeRight:
      selectedBranch = .right
    case .stayMainline:
      return nil
    }

    guard
      !surface.decisionZoneID.trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty,
      let movementOccurrenceID = surface.nextMovementOccurrenceID,
      !movementOccurrenceID.trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty,
      !surface.japaneseSignText.trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty
    else {
      return nil
    }

    self.decisionZoneID = surface.decisionZoneID
    self.movementOccurrenceID = movementOccurrenceID
    self.selectedBranch = selectedBranch
    distanceMeters = surface.distanceMeters
    japaneseSignText = surface.japaneseSignText
    localizedInstruction = surface.localizedDisplayText
    routeShield = surface.routeShields.first
  }
}

struct ProductJunctionInsetView: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let presentation: ProductJunctionInsetPresentation

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        LinearGradient(
          colors: [
            Color(hex: 0xAEC5CF),
            Color(hex: 0x71838A),
            KaidoTheme.asphalt,
          ],
          startPoint: .top,
          endPoint: .bottom
        )

        JunctionRoadScene(selectedBranch: presentation.selectedBranch)
          .accessibilityHidden(true)

        VStack(spacing: 0) {
          signGantry
          Spacer(minLength: 0)
          instructionBar
        }
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
    .frame(
      height: dynamicTypeSize.isAccessibilitySize ? 226 : 190
    )
    .clipShape(RoundedRectangle(cornerRadius: 15))
    .overlay {
      RoundedRectangle(cornerRadius: 15)
        .stroke(KaidoTheme.routeWhite.opacity(0.78), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.38), radius: 12, y: 5)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityIdentifier("product-junction-inset")
    .accessibilityValue(
      [
        presentation.decisionZoneID,
        presentation.movementOccurrenceID,
        presentation.japaneseSignText,
      ].joined(separator: " | ")
    )
  }

  private var signGantry: some View {
    HStack(alignment: .top, spacing: 7) {
      if let routeShield = presentation.routeShield {
        Text(verbatim: routeShield)
          .font(.system(size: 15, weight: .black, design: .rounded))
          .foregroundStyle(.white)
          .frame(width: 40, height: 34)
          .background(Color(hex: 0x13874A))
          .clipShape(RoundedRectangle(cornerRadius: 5))
          .overlay {
            RoundedRectangle(cornerRadius: 5)
              .stroke(.white, lineWidth: 2)
          }
      }

      HStack(spacing: 8) {
        Image(
          systemName:
            presentation.selectedBranch == .left
            ? "arrow.down.left"
            : "arrow.down.right"
        )
        .font(.system(size: 15, weight: .black))

        Text(verbatim: presentation.japaneseSignText)
          .font(.system(size: 14, weight: .black, design: .rounded))
          .lineLimit(2)
          .minimumScaleFactor(0.78)

        Spacer(minLength: 0)
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 11)
      .frame(minHeight: 42)
      .background(Color(hex: 0x087A43))
      .clipShape(RoundedRectangle(cornerRadius: 5))
      .overlay {
        RoundedRectangle(cornerRadius: 5)
          .stroke(.white.opacity(0.9), lineWidth: 1.5)
      }

      Text(distanceLabel)
        .font(.system(size: 13, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.asphalt)
        .padding(.horizontal, 9)
        .frame(height: 34)
        .background(KaidoTheme.routeWhite)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
    .padding(.horizontal, 10)
    .padding(.top, 9)
  }

  private var instructionBar: some View {
    HStack(spacing: 9) {
      Image(
        systemName:
          presentation.selectedBranch == .left
          ? "arrow.turn.up.left"
          : "arrow.turn.up.right"
      )
      .font(.system(size: 18, weight: .black))
      .foregroundStyle(KaidoTheme.signalAmber)

      VStack(alignment: .leading, spacing: 1) {
        Text(
          copy.resolve(
            japanese: "前方の分岐",
            simplifiedChinese: "前方分岔",
            english: "UPCOMING JUNCTION"
          )
        )
        .font(.system(size: 8, weight: .black, design: .rounded))
        .tracking(0.6)
        .foregroundStyle(KaidoTheme.signalAmber)

        Text(presentation.localizedInstruction)
          .font(.system(size: 12, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)
          .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
          .minimumScaleFactor(0.8)
      }

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
    .background(KaidoTheme.asphalt.opacity(0.92))
  }

  private var distanceLabel: String {
    if presentation.distanceMeters >= 1_000 {
      return String(
        format: "%.1f km",
        presentation.distanceMeters / 1_000
      )
    }
    return "\(Int(presentation.distanceMeters.rounded())) m"
  }

  private var accessibilityLabel: String {
    copy.resolve(
      japanese:
        "\(distanceLabel)先の分岐。標識は\(presentation.japaneseSignText)。\(presentation.localizedInstruction)",
      simplifiedChinese:
        "\(distanceLabel) 后进入分岔。路牌为\(presentation.japaneseSignText)。\(presentation.localizedInstruction)",
      english:
        "Junction in \(distanceLabel). Sign: \(presentation.japaneseSignText). \(presentation.localizedInstruction)"
    )
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }
}

private struct JunctionRoadScene: View {
  let selectedBranch: ProductJunctionInsetPresentation.SelectedBranch

  var body: some View {
    Canvas { context, size in
      drawStructures(context: context, size: size)
      drawRoads(context: context, size: size)
      drawLaneMarkings(context: context, size: size)
      drawSelectedRoute(context: context, size: size)
    }
  }

  private func drawStructures(
    context: GraphicsContext,
    size: CGSize
  ) {
    let bridge = CGRect(
      x: 0,
      y: size.height * 0.31,
      width: size.width,
      height: size.height * 0.07
    )
    context.fill(
      Path(bridge),
      with: .color(Color(hex: 0x5D6B70))
    )
    context.fill(
      Path(
        CGRect(
          x: size.width * 0.12,
          y: bridge.maxY,
          width: size.width * 0.055,
          height: size.height * 0.27
        )
      ),
      with: .color(Color(hex: 0x718086))
    )
    context.fill(
      Path(
        CGRect(
          x: size.width * 0.82,
          y: bridge.maxY,
          width: size.width * 0.055,
          height: size.height * 0.27
        )
      ),
      with: .color(Color(hex: 0x718086))
    )
  }

  private func drawRoads(
    context: GraphicsContext,
    size: CGSize
  ) {
    context.fill(
      polygon(
        [
          point(0.08, 1, size),
          point(0.92, 1, size),
          point(0.59, 0.52, size),
          point(0.41, 0.52, size),
        ]
      ),
      with: .color(Color(hex: 0x303A3F))
    )

    context.fill(
      polygon(
        [
          point(0.41, 0.56, size),
          point(0.56, 0.49, size),
          point(0.31, 0.19, size),
          point(0.02, 0.19, size),
        ]
      ),
      with: .color(Color(hex: 0x303A3F))
    )

    context.fill(
      polygon(
        [
          point(0.46, 0.52, size),
          point(0.60, 0.56, size),
          point(0.83, 0.17, size),
          point(0.61, 0.17, size),
        ]
      ),
      with: .color(Color(hex: 0x303A3F))
    )

    var gore = Path()
    gore.move(to: point(0.49, 0.55, size))
    gore.addLine(to: point(0.42, 0.39, size))
    gore.addLine(to: point(0.57, 0.39, size))
    gore.closeSubpath()
    context.fill(gore, with: .color(KaidoTheme.routeWhite.opacity(0.78)))
  }

  private func drawLaneMarkings(
    context: GraphicsContext,
    size: CGSize
  ) {
    var approach = Path()
    approach.move(to: point(0.5, 1, size))
    approach.addLine(to: point(0.5, 0.57, size))
    context.stroke(
      approach,
      with: .color(KaidoTheme.routeWhite.opacity(0.74)),
      style: StrokeStyle(
        lineWidth: 2,
        lineCap: .round,
        dash: [9, 8]
      )
    )

    for side: ProductJunctionInsetPresentation.SelectedBranch in [
      .left, .right,
    ] {
      context.stroke(
        branchPath(side, size: size),
        with: .color(KaidoTheme.routeWhite.opacity(0.42)),
        style: StrokeStyle(
          lineWidth: 2,
          lineCap: .round,
          dash: [7, 7]
        )
      )
    }
  }

  private func drawSelectedRoute(
    context: GraphicsContext,
    size: CGSize
  ) {
    var route = Path()
    route.move(to: point(0.5, 0.98, size))
    route.addLine(to: point(0.5, 0.58, size))
    if selectedBranch == .left {
      route.addCurve(
        to: point(0.17, 0.2, size),
        control1: point(0.45, 0.47, size),
        control2: point(0.29, 0.3, size)
      )
    } else {
      route.addCurve(
        to: point(0.72, 0.18, size),
        control1: point(0.55, 0.47, size),
        control2: point(0.65, 0.3, size)
      )
    }
    context.stroke(
      route,
      with: .color(KaidoTheme.signalAmber.opacity(0.28)),
      style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round)
    )
    context.stroke(
      route,
      with: .color(KaidoTheme.signalAmber),
      style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
    )

    let arrowTip =
      selectedBranch == .left
      ? point(0.17, 0.2, size)
      : point(0.72, 0.18, size)
    let arrowDirection: CGFloat = selectedBranch == .left ? -1 : 1
    var arrow = Path()
    arrow.move(to: arrowTip)
    arrow.addLine(
      to: CGPoint(
        x: arrowTip.x - arrowDirection * 1,
        y: arrowTip.y + 18
      )
    )
    arrow.addLine(
      to: CGPoint(
        x: arrowTip.x - arrowDirection * 17,
        y: arrowTip.y + 5
      )
    )
    arrow.closeSubpath()
    context.fill(arrow, with: .color(KaidoTheme.signalAmber))
  }

  private func branchPath(
    _ side: ProductJunctionInsetPresentation.SelectedBranch,
    size: CGSize
  ) -> Path {
    var path = Path()
    path.move(to: point(0.5, 0.56, size))
    if side == .left {
      path.addCurve(
        to: point(0.17, 0.19, size),
        control1: point(0.43, 0.45, size),
        control2: point(0.29, 0.29, size)
      )
    } else {
      path.addCurve(
        to: point(0.72, 0.17, size),
        control1: point(0.56, 0.45, size),
        control2: point(0.65, 0.28, size)
      )
    }
    return path
  }

  private func polygon(_ points: [CGPoint]) -> Path {
    var path = Path()
    guard let first = points.first else { return path }
    path.move(to: first)
    for point in points.dropFirst() {
      path.addLine(to: point)
    }
    path.closeSubpath()
    return path
  }

  private func point(
    _ x: CGFloat,
    _ y: CGFloat,
    _ size: CGSize
  ) -> CGPoint {
    CGPoint(x: x * size.width, y: y * size.height)
  }
}
