import Foundation

public enum KaidoReleaseLocale: String, Codable, CaseIterable, Hashable, Sendable {
  case japanese = "ja-JP"
  case simplifiedChinese = "zh-Hans"
  case english = "en"
}

private struct KaidoReleaseLocaleCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int? = nil

  init?(stringValue: String) {
    self.stringValue = stringValue
  }

  init?(intValue: Int) {
    return nil
  }

  init(_ locale: KaidoReleaseLocale) {
    stringValue = locale.rawValue
  }
}

public struct LocalizedGuidanceContent: Codable, Equatable, Sendable {
  public let displayText: String
  public let spokenText: String
  public let spokenForms: [String: String]
  public let preservedJapaneseSignText: String

  public init(
    displayText: String,
    spokenText: String,
    spokenForms: [String: String],
    preservedJapaneseSignText: String
  ) {
    self.displayText = displayText
    self.spokenText = spokenText
    self.spokenForms = spokenForms
    self.preservedJapaneseSignText = preservedJapaneseSignText
  }

  private enum CodingKeys: String, CodingKey {
    case displayText = "display_text"
    case spokenText = "spoken_text"
    case spokenForms = "spoken_forms"
    case preservedJapaneseSignText = "preserved_japanese_sign_text"
  }
}

public struct GuidancePresentationSource: Codable, Equatable, Sendable {
  public let routeShields: [String]
  public let japaneseSignText: String
  public let localizedContent: [KaidoReleaseLocale: LocalizedGuidanceContent]
  public let junctionView: JunctionViewDefinition?

  public init(
    routeShields: [String],
    japaneseSignText: String,
    localizedContent: [KaidoReleaseLocale: LocalizedGuidanceContent],
    junctionView: JunctionViewDefinition? = nil
  ) {
    self.routeShields = routeShields
    self.japaneseSignText = japaneseSignText
    self.localizedContent = localizedContent
    self.junctionView = junctionView
  }

  private enum CodingKeys: String, CodingKey {
    case routeShields = "route_shields"
    case japaneseSignText = "japanese_sign_text"
    case localizedContent = "localized_content"
    case junctionView = "junction_view"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    routeShields = try container.decode([String].self, forKey: .routeShields)
    japaneseSignText = try container.decode(String.self, forKey: .japaneseSignText)
    junctionView = try container.decodeIfPresent(
      JunctionViewDefinition.self,
      forKey: .junctionView
    )
    let localeContainer = try container.nestedContainer(
      keyedBy: KaidoReleaseLocaleCodingKey.self,
      forKey: .localizedContent
    )
    var content: [KaidoReleaseLocale: LocalizedGuidanceContent] = [:]
    for key in localeContainer.allKeys {
      guard let locale = KaidoReleaseLocale(rawValue: key.stringValue) else {
        throw DecodingError.dataCorruptedError(
          forKey: key,
          in: localeContainer,
          debugDescription: "Unknown release locale \(key.stringValue)"
        )
      }
      content[locale] = try localeContainer.decode(
        LocalizedGuidanceContent.self,
        forKey: key
      )
    }
    localizedContent = content
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(routeShields, forKey: .routeShields)
    try container.encode(japaneseSignText, forKey: .japaneseSignText)
    try container.encodeIfPresent(junctionView, forKey: .junctionView)
    var localeContainer = container.nestedContainer(
      keyedBy: KaidoReleaseLocaleCodingKey.self,
      forKey: .localizedContent
    )
    for locale in KaidoReleaseLocale.allCases {
      guard let content = localizedContent[locale] else { continue }
      try localeContainer.encode(content, forKey: KaidoReleaseLocaleCodingKey(locale))
    }
  }
}

public enum GuidancePromptStage: String, Codable, Sendable {
  case preview = "PREVIEW"
  case prepare = "PREPARE"
  case commit = "COMMIT"
  case recovery = "RECOVERY"
  case finish = "FINISH"
}

public enum GuidanceManeuver: String, Codable, Sendable {
  case stayMainline = "STAY_MAINLINE"
  case keepLeft = "KEEP_LEFT"
  case keepRight = "KEEP_RIGHT"
  case takeExitLeft = "TAKE_EXIT_LEFT"
  case takeExitRight = "TAKE_EXIT_RIGHT"
  case mergeLeft = "MERGE_LEFT"
  case mergeRight = "MERGE_RIGHT"
}

public enum GuidanceLanePreparation: String, Codable, Sendable {
  case none = "NONE"
  case stayMainline = "STAY_MAINLINE"
  case keepLeft = "KEEP_LEFT"
  case keepRight = "KEEP_RIGHT"
  case useLeftLanes = "USE_LEFT_LANES"
  case useRightLanes = "USE_RIGHT_LANES"
}

/// One occurrence-scoped, structured instruction shared by every adapter.
public struct GuidanceFrame: Equatable, Sendable {
  public let promptID: String
  public let anchorID: String
  public let anchorOccurrenceID: String
  public let movementOccurrenceID: String
  public let decisionZoneID: String
  public let stage: GuidancePromptStage
  public let distanceMeters: Double
  public let decisionPointNameJapanese: String
  public let localizedDecisionPointNames: [KaidoReleaseLocale: String]
  public let maneuver: GuidanceManeuver
  public let lanePreparation: GuidanceLanePreparation
  public let presentationSource: GuidancePresentationSource

  public init(
    promptID: String,
    anchorID: String,
    anchorOccurrenceID: String,
    movementOccurrenceID: String,
    decisionZoneID: String,
    stage: GuidancePromptStage,
    distanceMeters: Double,
    decisionPointNameJapanese: String,
    localizedDecisionPointNames: [KaidoReleaseLocale: String],
    maneuver: GuidanceManeuver,
    lanePreparation: GuidanceLanePreparation,
    presentationSource: GuidancePresentationSource
  ) {
    self.promptID = promptID
    self.anchorID = anchorID
    self.anchorOccurrenceID = anchorOccurrenceID
    self.movementOccurrenceID = movementOccurrenceID
    self.decisionZoneID = decisionZoneID
    self.stage = stage
    self.distanceMeters = distanceMeters
    self.decisionPointNameJapanese = decisionPointNameJapanese
    self.localizedDecisionPointNames = localizedDecisionPointNames
    self.maneuver = maneuver
    self.lanePreparation = lanePreparation
    self.presentationSource = presentationSource
  }
}

public struct GuidanceFrameTemplate: Codable, Equatable, Sendable {
  public let movementOccurrenceID: String
  public let decisionZoneID: String
  public let stage: GuidancePromptStage
  public let decisionPointNameJapanese: String
  public let localizedDecisionPointNames: [KaidoReleaseLocale: String]
  public let maneuver: GuidanceManeuver
  public let lanePreparation: GuidanceLanePreparation
  public let presentationSource: GuidancePresentationSource

  public init(
    movementOccurrenceID: String,
    decisionZoneID: String,
    stage: GuidancePromptStage,
    decisionPointNameJapanese: String,
    localizedDecisionPointNames: [KaidoReleaseLocale: String],
    maneuver: GuidanceManeuver,
    lanePreparation: GuidanceLanePreparation,
    presentationSource: GuidancePresentationSource
  ) {
    self.movementOccurrenceID = movementOccurrenceID
    self.decisionZoneID = decisionZoneID
    self.stage = stage
    self.decisionPointNameJapanese = decisionPointNameJapanese
    self.localizedDecisionPointNames = localizedDecisionPointNames
    self.maneuver = maneuver
    self.lanePreparation = lanePreparation
    self.presentationSource = presentationSource
  }

  private enum CodingKeys: String, CodingKey {
    case movementOccurrenceID = "movement_occurrence_id"
    case decisionZoneID = "decision_zone_id"
    case stage
    case decisionPointNameJapanese = "decision_point_name_ja"
    case localizedDecisionPointNames = "localized_decision_point_names"
    case maneuver
    case lanePreparation = "lane_preparation"
    case presentationSource = "presentation_source"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    movementOccurrenceID = try container.decode(
      String.self,
      forKey: .movementOccurrenceID
    )
    decisionZoneID = try container.decode(String.self, forKey: .decisionZoneID)
    stage = try container.decode(GuidancePromptStage.self, forKey: .stage)
    decisionPointNameJapanese = try container.decode(
      String.self,
      forKey: .decisionPointNameJapanese
    )
    maneuver = try container.decode(GuidanceManeuver.self, forKey: .maneuver)
    lanePreparation = try container.decode(
      GuidanceLanePreparation.self,
      forKey: .lanePreparation
    )
    presentationSource = try container.decode(
      GuidancePresentationSource.self,
      forKey: .presentationSource
    )
    let localeContainer = try container.nestedContainer(
      keyedBy: KaidoReleaseLocaleCodingKey.self,
      forKey: .localizedDecisionPointNames
    )
    var names: [KaidoReleaseLocale: String] = [:]
    for key in localeContainer.allKeys {
      guard let locale = KaidoReleaseLocale(rawValue: key.stringValue) else {
        throw DecodingError.dataCorruptedError(
          forKey: key,
          in: localeContainer,
          debugDescription: "Unknown release locale \(key.stringValue)"
        )
      }
      names[locale] = try localeContainer.decode(String.self, forKey: key)
    }
    localizedDecisionPointNames = names
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(movementOccurrenceID, forKey: .movementOccurrenceID)
    try container.encode(decisionZoneID, forKey: .decisionZoneID)
    try container.encode(stage, forKey: .stage)
    try container.encode(decisionPointNameJapanese, forKey: .decisionPointNameJapanese)
    try container.encode(maneuver, forKey: .maneuver)
    try container.encode(lanePreparation, forKey: .lanePreparation)
    try container.encode(presentationSource, forKey: .presentationSource)
    var localeContainer = container.nestedContainer(
      keyedBy: KaidoReleaseLocaleCodingKey.self,
      forKey: .localizedDecisionPointNames
    )
    for locale in KaidoReleaseLocale.allCases {
      guard let name = localizedDecisionPointNames[locale] else { continue }
      try localeContainer.encode(name, forKey: KaidoReleaseLocaleCodingKey(locale))
    }
  }

  public func makeFrame(
    anchor: GuidanceAnchorDefinition,
    distanceMeters: Double
  ) -> GuidanceFrame {
    GuidanceFrame(
      promptID: anchor.promptID,
      anchorID: anchor.anchorID,
      anchorOccurrenceID: anchor.occurrenceID,
      movementOccurrenceID: movementOccurrenceID,
      decisionZoneID: decisionZoneID,
      stage: stage,
      distanceMeters: distanceMeters,
      decisionPointNameJapanese: decisionPointNameJapanese,
      localizedDecisionPointNames: localizedDecisionPointNames,
      maneuver: maneuver,
      lanePreparation: lanePreparation,
      presentationSource: presentationSource
    )
  }
}

/// A reviewed distance trigger bound to one route occurrence and immutable frame template.
public struct ReleasedGuidanceDefinition: Codable, Equatable, Sendable {
  public let anchor: GuidanceAnchorDefinition
  public let triggerDistanceMeters: Double
  public let frameTemplate: GuidanceFrameTemplate

  public init(
    anchor: GuidanceAnchorDefinition,
    triggerDistanceMeters: Double,
    frameTemplate: GuidanceFrameTemplate
  ) {
    self.anchor = anchor
    self.triggerDistanceMeters = triggerDistanceMeters
    self.frameTemplate = frameTemplate
  }

  private enum CodingKeys: String, CodingKey {
    case anchor
    case triggerDistanceMeters = "trigger_distance_meters"
    case frameTemplate = "frame_template"
  }
}

/// Locates one reviewed DecisionZone entry on a specific RoutePlan movement occurrence.
public struct DecisionZoneProgressDefinition: Codable, Equatable, Sendable {
  public let id: String
  public let networkSnapshotID: String
  public let routePlanID: String
  public let movementOccurrenceID: String
  public let entryOffsetMeters: Double

  public init(
    id: String,
    networkSnapshotID: String,
    routePlanID: String,
    movementOccurrenceID: String,
    entryOffsetMeters: Double
  ) {
    self.id = id
    self.networkSnapshotID = networkSnapshotID
    self.routePlanID = routePlanID
    self.movementOccurrenceID = movementOccurrenceID
    self.entryOffsetMeters = entryOffsetMeters
  }

  private enum CodingKeys: String, CodingKey {
    case id = "decision_zone_id"
    case networkSnapshotID = "network_snapshot_id"
    case routePlanID = "route_plan_id"
    case movementOccurrenceID = "movement_occurrence_id"
    case entryOffsetMeters = "entry_offset_meters"
  }
}

public struct GuidanceProgressObservation: Equatable, Sendable {
  public let occurrenceID: String
  public let distanceToDecisionPointMeters: Double
  public let observedAtMilliseconds: Int

  public init(
    occurrenceID: String,
    distanceToDecisionPointMeters: Double,
    observedAtMilliseconds: Int
  ) {
    self.occurrenceID = occurrenceID
    self.distanceToDecisionPointMeters = distanceToDecisionPointMeters
    self.observedAtMilliseconds = observedAtMilliseconds
  }
}

public struct GuidancePromptEmission: Equatable, Sendable {
  public let promptID: String
  public let anchorID: String
  public let anchorOccurrenceID: String

  public init(promptID: String, anchorID: String, anchorOccurrenceID: String) {
    self.promptID = promptID
    self.anchorID = anchorID
    self.anchorOccurrenceID = anchorOccurrenceID
  }
}

public enum GuidancePlanningStatus: String, Codable, Sendable {
  case inactive = "INACTIVE"
  case waitingForAnchor = "WAITING_FOR_ANCHOR"
  case frameUpdated = "FRAME_UPDATED"
  case promptEmitted = "PROMPT_EMITTED"
  case insufficientRouteEvidence = "INSUFFICIENT_ROUTE_EVIDENCE"
  case staleObservation = "STALE_OBSERVATION"
  case notCurrentOccurrence = "NOT_CURRENT_OCCURRENCE"
  case noReleasedDefinition = "NO_RELEASED_DEFINITION"
  case invalidDefinition = "INVALID_DEFINITION"
}

public enum GuidanceFrameValidationError: Error, Equatable, Sendable {
  case missingPromptID
  case missingAnchorID
  case missingAnchorOccurrenceID
  case missingMovementOccurrenceID
  case missingDecisionZoneID
  case invalidDistanceMeters
  case missingDecisionPointNameJapanese
  case missingDecisionPointLocale(KaidoReleaseLocale)
  case decisionPointJapaneseNameMismatch
  case missingRouteShield
  case missingJapaneseSignText
  case missingLocale(KaidoReleaseLocale)
  case incompleteLocale(KaidoReleaseLocale)
  case japaneseSignTextMismatch(KaidoReleaseLocale)
  case invalidJunctionView(JunctionViewValidationError)
  case junctionViewMovementMismatch
  case junctionViewJapaneseSignMismatch
  case junctionViewRouteShieldMismatch
}

public enum GuidanceFrameValidator {
  public static func validate(_ frame: GuidanceFrame) throws {
    guard !normalized(frame.promptID).isEmpty else {
      throw GuidanceFrameValidationError.missingPromptID
    }
    guard !normalized(frame.anchorID).isEmpty else {
      throw GuidanceFrameValidationError.missingAnchorID
    }
    guard !normalized(frame.anchorOccurrenceID).isEmpty else {
      throw GuidanceFrameValidationError.missingAnchorOccurrenceID
    }
    guard !normalized(frame.movementOccurrenceID).isEmpty else {
      throw GuidanceFrameValidationError.missingMovementOccurrenceID
    }
    guard !normalized(frame.decisionZoneID).isEmpty else {
      throw GuidanceFrameValidationError.missingDecisionZoneID
    }
    guard frame.distanceMeters.isFinite, frame.distanceMeters >= 0 else {
      throw GuidanceFrameValidationError.invalidDistanceMeters
    }
    guard !normalized(frame.decisionPointNameJapanese).isEmpty else {
      throw GuidanceFrameValidationError.missingDecisionPointNameJapanese
    }
    for locale in KaidoReleaseLocale.allCases {
      guard let name = frame.localizedDecisionPointNames[locale],
        !normalized(name).isEmpty
      else {
        throw GuidanceFrameValidationError.missingDecisionPointLocale(locale)
      }
    }
    guard
      frame.localizedDecisionPointNames[.japanese] == frame.decisionPointNameJapanese
    else {
      throw GuidanceFrameValidationError.decisionPointJapaneseNameMismatch
    }

    let source = frame.presentationSource
    guard !source.routeShields.isEmpty,
      source.routeShields.allSatisfy({ !normalized($0).isEmpty })
    else {
      throw GuidanceFrameValidationError.missingRouteShield
    }
    guard !normalized(source.japaneseSignText).isEmpty else {
      throw GuidanceFrameValidationError.missingJapaneseSignText
    }
    for locale in KaidoReleaseLocale.allCases {
      guard let content = source.localizedContent[locale] else {
        throw GuidanceFrameValidationError.missingLocale(locale)
      }
      guard !normalized(content.displayText).isEmpty,
        !normalized(content.spokenText).isEmpty,
        !content.spokenForms.isEmpty,
        content.spokenForms.allSatisfy({
          !normalized($0.key).isEmpty && !normalized($0.value).isEmpty
        }),
        !normalized(content.preservedJapaneseSignText).isEmpty
      else {
        throw GuidanceFrameValidationError.incompleteLocale(locale)
      }
      guard content.preservedJapaneseSignText == source.japaneseSignText else {
        throw GuidanceFrameValidationError.japaneseSignTextMismatch(locale)
      }
    }
    if let junctionView = source.junctionView {
      do {
        try JunctionViewValidator.validate(junctionView)
      } catch let error as JunctionViewValidationError {
        throw GuidanceFrameValidationError.invalidJunctionView(error)
      }
      guard junctionView.movementOccurrenceID == frame.movementOccurrenceID else {
        throw GuidanceFrameValidationError.junctionViewMovementMismatch
      }
      guard junctionView.japaneseSignText == source.japaneseSignText else {
        throw GuidanceFrameValidationError.junctionViewJapaneseSignMismatch
      }
      guard junctionView.routeShields == source.routeShields else {
        throw GuidanceFrameValidationError.junctionViewRouteShieldMismatch
      }
    }
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
