import KaidoAppleAdapters
import KaidoDomain
import KaidoRouting
import MapKit
import SwiftUI

/// Every way to the chosen place: time, distance and roads, nothing about
/// who guides them.
struct DestinationRouteChoicePanel: View {
  let choice: DestinationRouteChoice
  let locale: KaidoReleaseLocale
  let onSelect: (Int) -> Void
  let onGo: () -> Void
  let onCancel: () -> Void

  private var copy: KaidoInterfaceText { KaidoInterfaceText(locale: locale) }

  var body: some View {
    VStack(alignment: .leading, spacing: KaidoSpace.md) {
      HStack {
        Text(choice.destination.title)
          .font(.title3.weight(.bold))
          .foregroundStyle(KaidoInk.textPrimary)
          .lineLimit(1)
        Spacer()
        Button(copy.resolve(japanese: "閉じる", simplifiedChinese: "关闭", english: "Close"), action: onCancel)
          .font(.subheadline.weight(.semibold))
          .frame(minHeight: 44)
          .accessibilityIdentifier("destination-route-close")
      }
      ForEach(Array(choice.options.enumerated()), id: \.element.id) { index, option in
        Button { onSelect(index) } label: { card(option, selected: index == choice.selectedIndex) }
          .buttonStyle(.plain)
          .accessibilityIdentifier("destination-route-option-\(index)")
          .accessibilityAddTraits(index == choice.selectedIndex ? .isSelected : [])
      }
      Button(action: onGo) {
        Text(copy.resolve(japanese: "出発", simplifiedChinese: "出发", english: "Go"))
          .font(.headline.weight(.bold))
          .foregroundStyle(KaidoInk.surface)
          .frame(maxWidth: .infinity, minHeight: 54)
          .background(KaidoInk.mapRouteDriving)
          .clipShape(RoundedRectangle(cornerRadius: KaidoRadius.card))
      }
      .accessibilityIdentifier("destination-route-go")
    }
  }

  private func card(_ option: DestinationRouteOption, selected: Bool) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        if let seconds = option.travelSeconds {
          Text("\(Int((seconds / 60).rounded()))")
            .font(.system(size: selected ? 26 : 22, weight: .heavy))
          Text(copy.resolve(japanese: "分", simplifiedChinese: "分钟", english: "min"))
            .font(.caption)
            .foregroundStyle(KaidoInk.textSecondary)
        }
        if let meters = option.distanceMeters {
          Text(ProviderGuidedDriveView.distanceLabel(meters))
            .font(.subheadline.weight(.bold))
            .foregroundStyle(KaidoInk.textSecondary)
            .padding(.leading, option.travelSeconds == nil ? 0 : 6)
        }
      }
      .foregroundStyle(KaidoInk.textPrimary)
      roads(option.roads)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(selected ? KaidoInk.surfaceRaised : KaidoInk.surfacePanel)
    .clipShape(RoundedRectangle(cornerRadius: KaidoRadius.card))
    .overlay {
      RoundedRectangle(cornerRadius: KaidoRadius.card)
        .stroke(selected ? KaidoInk.mapRouteDriving : KaidoInk.divider, lineWidth: selected ? 2 : 1)
    }
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private func roads(_ roads: DestinationRouteOption.Roads) -> some View {
    switch roads {
    case .provider(let usesExpressway, let name):
      let kind =
        usesExpressway
        ? copy.resolve(japanese: "高速道路", simplifiedChinese: "高速", english: "Expressway")
        : copy.resolve(japanese: "一般道路", simplifiedChinese: "一般道路", english: "Local roads")
      Text(name.map { "\(kind) · \($0)" } ?? kind)
        .font(.caption)
        .foregroundStyle(KaidoInk.textQuiet)
        .lineLimit(1)
    case .kaido(let routeIDs, let entryNameJA, let exitNameJA):
      HStack(spacing: 4) {
        ForEach(Array(routeIDs.enumerated()), id: \.offset) { _, routeID in
          Text(shieldLabel(routeID))
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundStyle(KaidoInk.onShield)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(KaidoInk.accentCool.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: KaidoRadius.mark))
        }
        Text(exitNameJA.isEmpty ? entryNameJA : "\(entryNameJA) → \(exitNameJA)")
          .font(.caption)
          .foregroundStyle(KaidoInk.textQuiet)
          .lineLimit(1)
      }
    }
  }
}

/// The drive screen for a provider-guided route: the next step, the route
/// on the provider map, arrival time, and one way out.
struct ProviderGuidedDriveView: View {
  @ObservedObject var drive: ProviderGuidedDriveModel
  let locale: KaidoReleaseLocale
  let isMuted: Bool
  let onToggleMute: () -> Void
  let onFinish: () -> Void

  @State private var camera: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)

  private var copy: KaidoInterfaceText { KaidoInterfaceText(locale: locale) }

  var body: some View {
    ZStack {
      Map(position: $camera) {
        MapPolyline(coordinates: drive.route.coordinates.map(\.clCoordinate))
          .stroke(KaidoInk.mapRouteDriving, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
        Marker(drive.destination.title, coordinate: drive.destination.coordinate.clCoordinate)
        UserAnnotation()
      }
      .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
      .ignoresSafeArea()

      VStack(spacing: 0) {
        if drive.phase == .driving {
          header
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        Spacer()
        if !camera.followsUserLocation, drive.phase == .driving {
          HStack {
            Spacer()
            Button {
              camera = .userLocation(followsHeading: true, fallback: .automatic)
            } label: {
              Image(systemName: "location.north.line.fill")
                .font(.system(size: 18, weight: .bold))
                .frame(width: 48, height: 48)
                .background(KaidoInk.surfaceRaised)
                .clipShape(Circle())
            }
            .accessibilityLabel(copy.resolve(japanese: "現在地に戻る", simplifiedChinese: "回到当前位置", english: "Recenter"))
            .padding(14)
          }
        }
        dock
      }
    }
    .environment(\.colorScheme, .dark)
    // The drive covers the home: assistive navigation stays inside it.
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isModal)
    .accessibilityIdentifier("provider-drive")
  }

  private var header: some View {
    HStack(spacing: 14) {
      let instruction = drive.stepProgress.map {
        SurfaceGuidancePresentation.instruction(
          $0.step.instruction, sourceLanguageCode: drive.route.guidanceLanguageCode, locale: locale
        ).text
      }
      let maneuver = drive.stepProgress.map { SurfaceManeuver.from(instruction: $0.step.instruction) } ?? .unknown
      Image(systemName: maneuver.symbol)
        .font(.system(size: 34, weight: .bold))
        .foregroundStyle(KaidoInk.surface)
        .frame(width: 72, height: 72)
        .background(KaidoInk.accentWarm)
        .clipShape(RoundedRectangle(cornerRadius: 12))
      VStack(alignment: .leading, spacing: 2) {
        if drive.isRerouting || drive.isOffRoute {
          Text(copy.resolve(japanese: "ルートを再検索中", simplifiedChinese: "正在重新规划", english: "Rerouting"))
            .font(.title3.weight(.bold))
        } else {
          if let remaining = drive.stepProgress?.remainingMeters {
            Text(Self.distanceLabel(remaining))
              .font(.system(size: 32, weight: .heavy))
          }
          if let instruction {
            Text(instruction)
              .font(.headline.weight(.bold))
              .lineLimit(2)
              .minimumScaleFactor(0.8)
              .accessibilityIdentifier("provider-drive-instruction")
          }
        }
      }
      .foregroundStyle(KaidoInk.textPrimary)
      Spacer(minLength: 0)
      Button(action: onToggleMute) {
        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(KaidoInk.textPrimary)
          .frame(width: 44, height: 44)
      }
      .accessibilityLabel(
        isMuted
          ? copy.resolve(japanese: "音声をオン", simplifiedChinese: "打开语音", english: "Unmute")
          : copy.resolve(japanese: "音声をオフ", simplifiedChinese: "关闭语音", english: "Mute"))
      .accessibilityIdentifier("provider-drive-mute")
    }
    .padding(14)
    .background(KaidoInk.surfacePanel.opacity(0.96))
    .clipShape(RoundedRectangle(cornerRadius: 18))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("provider-drive-step")
  }

  @ViewBuilder
  private var dock: some View {
    VStack(alignment: .leading, spacing: 10) {
      if drive.phase == .arrived {
        HStack(spacing: 14) {
          Image(systemName: "checkmark")
            .font(.system(size: 22, weight: .heavy))
            .foregroundStyle(KaidoInk.surface)
            .frame(width: 52, height: 52)
            .background(KaidoInk.accentCool)
            .clipShape(Circle())
          VStack(alignment: .leading, spacing: 2) {
            Text(copy.resolve(japanese: "到着", simplifiedChinese: "已到达", english: "Arrived"))
              .font(.caption.weight(.bold))
              .foregroundStyle(KaidoInk.accentCool)
            Text(drive.destination.title)
              .font(.title2.weight(.heavy))
              .lineLimit(1)
          }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("provider-drive-arrived")
        finishButton(title: copy.resolve(japanese: "完了", simplifiedChinese: "完成", english: "Done"))
      } else {
        if drive.isLocationDenied {
          Text(copy.resolve(
            japanese: "位置情報がオフです。設定で許可してください",
            simplifiedChinese: "定位已关闭，请在设置中允许",
            english: "Location is off. Allow it in Settings"))
            .font(.footnote.weight(.semibold))
            .foregroundStyle(KaidoInk.accentClay)
        } else if drive.isPositionStale {
          Text(copy.resolve(
            japanese: "位置不確か · 自動再取得中",
            simplifiedChinese: "定位弱 · 正在自动重新定位",
            english: "Weak position · reacquiring"))
            .font(.footnote.weight(.semibold))
            .foregroundStyle(KaidoInk.accentClay)
            .accessibilityIdentifier("provider-drive-position-stale")
        }
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 2) {
            Text(arrivalTimeText)
              .font(.system(size: 26, weight: .heavy))
            Text("\(minutesText) · \(Self.distanceLabel(drive.remainingMeters))")
              .font(.subheadline.weight(.bold))
              .foregroundStyle(KaidoInk.accentCool)
            Text(drive.destination.title)
              .font(.footnote)
              .foregroundStyle(KaidoInk.textQuiet)
              .lineLimit(1)
          }
          Spacer()
          Button(action: onFinish) {
            Text(copy.resolve(japanese: "終了", simplifiedChinese: "结束", english: "End"))
              .font(.headline.weight(.bold))
              .foregroundStyle(KaidoInk.textPrimary)
              .frame(minWidth: 72, minHeight: 48)
              .background(KaidoInk.accentClay.opacity(0.85))
              .clipShape(RoundedRectangle(cornerRadius: KaidoRadius.control))
          }
          .accessibilityIdentifier("provider-drive-end")
        }
        .foregroundStyle(KaidoInk.textPrimary)
      }
    }
    .padding(.horizontal, KaidoSpace.lg)
    .padding(.top, KaidoSpace.lg)
    .padding(.bottom, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(KaidoInk.surfacePanel.ignoresSafeArea(edges: .bottom))
  }

  private func finishButton(title: String) -> some View {
    Button(action: onFinish) {
      Text(title)
        .font(.headline.weight(.bold))
        .foregroundStyle(KaidoInk.surface)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(KaidoInk.accentCool)
        .clipShape(RoundedRectangle(cornerRadius: KaidoRadius.card))
    }
    .accessibilityIdentifier("provider-drive-done")
  }

  private var minutesText: String {
    let minutes = Int((drive.remainingSeconds / 60).rounded(.up))
    return copy.resolve(japanese: "\(minutes)分", simplifiedChinese: "\(minutes) 分钟", english: "\(minutes) min")
  }

  private var arrivalTimeText: String {
    let arrival = Date().addingTimeInterval(drive.remainingSeconds)
    let time = arrival.formatted(date: .omitted, time: .shortened)
    return copy.resolve(japanese: "\(time) 到着", simplifiedChinese: "\(time) 到达", english: "Arrive \(time)")
  }

  static func distanceLabel(_ meters: Double) -> String {
    if meters >= 1_000 {
      return String(format: "%.1f km", meters / 1_000)
    }
    return "\(Int(max(0, meters).rounded())) m"
  }
}

extension ShutoCoordinate {
  fileprivate var clCoordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }
}
