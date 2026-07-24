import Foundation
import KaidoDomain

public struct NavigationAccessibilityPresentation: Equatable, Sendable {
  public let routeShieldLabels: [String]
  public let guidanceLabel: String
  public let markerLabel: String
  public let passageLabel: String
  public let routeEditingLabel: String
  public let surfaceOwnershipLabel: String
  public let junctionDiagramLabel: String?
  public let junctionLaneLabel: String?
  public let selectedPathHasNonColorCue: Bool
  public let preferredLanesHaveNonColorCue: Bool

  public init(
    routeShieldLabels: [String],
    guidanceLabel: String,
    markerLabel: String,
    passageLabel: String,
    routeEditingLabel: String,
    surfaceOwnershipLabel: String,
    junctionDiagramLabel: String?,
    junctionLaneLabel: String?,
    selectedPathHasNonColorCue: Bool,
    preferredLanesHaveNonColorCue: Bool
  ) {
    self.routeShieldLabels = routeShieldLabels
    self.guidanceLabel = guidanceLabel
    self.markerLabel = markerLabel
    self.passageLabel = passageLabel
    self.routeEditingLabel = routeEditingLabel
    self.surfaceOwnershipLabel = surfaceOwnershipLabel
    self.junctionDiagramLabel = junctionDiagramLabel
    self.junctionLaneLabel = junctionLaneLabel
    self.selectedPathHasNonColorCue = selectedPathHasNonColorCue
    self.preferredLanesHaveNonColorCue = preferredLanesHaveNonColorCue
  }
}

public enum NavigationAccessibilityProjector {
  public static func project(
    _ presentation: NavigationSurfacePresentation,
    locale: KaidoReleaseLocale
  ) -> NavigationAccessibilityPresentation {
    let routeShieldLabels = presentation.routeShields.map {
      localizedRouteShieldLabel($0, locale: locale)
    }
    let junction = presentation.junctionView.map {
      junctionAccessibility($0, locale: locale)
    }

    return NavigationAccessibilityPresentation(
      routeShieldLabels: routeShieldLabels,
      guidanceLabel: localizedGuidanceLabel(
        presentation,
        routeShieldLabels: routeShieldLabels,
        locale: locale
      ),
      markerLabel: localizedMarkerLabel(presentation.marker, locale: locale),
      passageLabel: localizedPassageLabel(presentation.passage.tone, locale: locale),
      routeEditingLabel: localizedEditingLabel(
        presentation.routeEditingAvailability,
        locale: locale
      ),
      surfaceOwnershipLabel: localizedSurfaceOwnershipLabel(
        presentation,
        locale: locale
      ),
      junctionDiagramLabel: junction?.diagram,
      junctionLaneLabel: junction?.lanes,
      selectedPathHasNonColorCue: junction != nil,
      preferredLanesHaveNonColorCue:
        presentation.junctionView?.laneLayout.preferredLaneIndices.isEmpty == false
    )
  }

  private static func localizedRouteShieldLabel(
    _ shield: String,
    locale: KaidoReleaseLocale
  ) -> String {
    switch locale {
    case .japanese:
      "ルートシールド \(shield)"
    case .simplifiedChinese:
      "路线盾牌 \(shield)"
    case .english:
      "Route shield \(shield)"
    }
  }

  private static func localizedGuidanceLabel(
    _ presentation: NavigationSurfacePresentation,
    routeShieldLabels: [String],
    locale: KaidoReleaseLocale
  ) -> String {
    let shields = routeShieldLabels.joined(separator: locale == .english ? ", " : "、")
    let distance = "\(Int(presentation.distanceMeters.rounded())) m"
    return switch locale {
    case .japanese:
      "\(shields)。標識 \(presentation.japaneseSignText)。"
        + "\(presentation.localizedDisplayText)。\(distance)。"
        + "次の分岐 \(presentation.localizedDecisionPointName)。"
    case .simplifiedChinese:
      "\(shields)。日文路牌 \(presentation.japaneseSignText)。"
        + "\(presentation.localizedDisplayText)。距离 \(distance)。"
        + "下一分岔 \(presentation.localizedDecisionPointName)。"
    case .english:
      "\(shields). Japanese sign \(presentation.japaneseSignText). "
        + "\(presentation.localizedDisplayText). Distance \(distance). "
        + "Next decision \(presentation.localizedDecisionPointName)."
    }
  }

  private static func localizedMarkerLabel(
    _ marker: NavigationMarkerPresentation,
    locale: KaidoReleaseLocale
  ) -> String {
    switch (locale, marker) {
    case (.japanese, .measured): "位置表示、計測位置"
    case (.japanese, .estimated): "位置表示、推定位置"
    case (.japanese, .unresolved): "位置表示、未解決"
    case (.simplifiedChinese, .measured): "位置呈现，测量位置"
    case (.simplifiedChinese, .estimated): "位置呈现，估算位置"
    case (.simplifiedChinese, .unresolved): "位置呈现，位置未解析"
    case (.english, .measured): "Position, measured"
    case (.english, .estimated): "Position, estimated"
    case (.english, .unresolved): "Position, unresolved"
    }
  }

  private static func localizedPassageLabel(
    _ tone: RoutePassagePresentationTone,
    locale: KaidoReleaseLocale
  ) -> String {
    switch (locale, tone) {
    case (.japanese, .blocked): "通行状態、通行止め確認"
    case (.japanese, .warning): "通行状態、計画上の競合あり"
    case (.japanese, .unconfirmed): "通行状態、リアルタイム未確認"
    case (.japanese, .confirmedPassable): "通行状態、通行可能を確認"
    case (.simplifiedChinese, .blocked): "实时通行，已知封闭"
    case (.simplifiedChinese, .warning): "实时通行，存在计划冲突"
    case (.simplifiedChinese, .unconfirmed): "实时通行，尚未确认"
    case (.simplifiedChinese, .confirmedPassable): "实时通行，已确认可通行"
    case (.english, .blocked): "Passage, known closed"
    case (.english, .warning): "Passage, planned conflict"
    case (.english, .unconfirmed): "Passage, realtime unconfirmed"
    case (.english, .confirmedPassable): "Passage, confirmed passable"
    }
  }

  private static func localizedEditingLabel(
    _ availability: RouteEditingAvailability,
    locale: KaidoReleaseLocale
  ) -> String {
    switch (locale, availability) {
    case (.japanese, .availableWhileParked): "ルート編集、停車中のみ可能"
    case (.japanese, .unavailableWhileMoving): "ルート編集、走行中は使用不可"
    case (.japanese, .unavailableInDecisionZone): "ルート編集、分岐判断区間では使用不可"
    case (.japanese, .lockedForActiveDrive): "ルート編集、走行中のルートはロック済み"
    case (.simplifiedChinese, .availableWhileParked): "路线编辑，停车时可编辑"
    case (.simplifiedChinese, .unavailableWhileMoving): "路线编辑，行驶中不可编辑"
    case (.simplifiedChinese, .unavailableInDecisionZone): "路线编辑，决策区不可编辑"
    case (.simplifiedChinese, .lockedForActiveDrive): "路线编辑，活动行程已锁定"
    case (.english, .availableWhileParked): "Route editing, available while parked"
    case (.english, .unavailableWhileMoving): "Route editing, unavailable while moving"
    case (.english, .unavailableInDecisionZone):
      "Route editing, unavailable in the decision zone"
    case (.english, .lockedForActiveDrive): "Route editing, locked for the active drive"
    }
  }

  private static func localizedSurfaceOwnershipLabel(
    _ presentation: NavigationSurfacePresentation,
    locale: KaidoReleaseLocale
  ) -> String {
    let surface = presentation.surface == .iPhone ? "iPhone" : "CarPlay"
    return switch (locale, presentation.isPrimarySurface) {
    case (.japanese, true): "\(surface)、主要表示"
    case (.japanese, false): "\(surface)、補助表示"
    case (.simplifiedChinese, true): "\(surface)，主显示"
    case (.simplifiedChinese, false): "\(surface)，辅助显示"
    case (.english, true): "\(surface), primary presentation"
    case (.english, false): "\(surface), companion presentation"
    }
  }

  private static func junctionAccessibility(
    _ definition: JunctionViewDefinition,
    locale: KaidoReleaseLocale
  ) -> (diagram: String, lanes: String) {
    let allowed = laneNumbers(definition.laneLayout.allowedLaneIndices, locale: locale)
    let preferred = laneNumbers(
      definition.laneLayout.preferredLaneIndices,
      locale: locale
    )

    switch locale {
    case .japanese:
      return (
        "審査済み分岐図。選択経路をチェック記号で表示。"
          + "標識目標 \(definition.japaneseSignText)。",
        "左から右へ全 \(definition.laneLayout.laneCount) 車線。"
          + "利用可能車線 \(allowed)。推奨車線 \(preferred)。"
      )
    case .simplifiedChinese:
      return (
        "审查路口示意。选中分支带有勾选标记。"
          + "日文路牌目标 \(definition.japaneseSignText)。",
        "从左到右共 \(definition.laneLayout.laneCount) 条车道。"
          + "可用车道 \(allowed)。首选车道 \(preferred)。"
      )
    case .english:
      return (
        "Reviewed junction diagram. The selected branch has a checkmark. "
          + "Japanese sign target \(definition.japaneseSignText).",
        "\(definition.laneLayout.laneCount) lanes from left to right. "
          + "Allowed lanes \(allowed). Preferred lanes \(preferred)."
      )
    }
  }

  private static func laneNumbers(
    _ zeroBasedIndices: [Int],
    locale: KaidoReleaseLocale
  ) -> String {
    zeroBasedIndices.map { String($0 + 1) }
      .joined(separator: locale == .english ? ", " : "、")
  }
}
