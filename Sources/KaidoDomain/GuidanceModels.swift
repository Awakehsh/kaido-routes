import Foundation

public enum KaidoReleaseLocale: String, Codable, CaseIterable, Hashable, Sendable {
  case japanese = "ja-JP"
  case simplifiedChinese = "zh-Hans"
  case english = "en"
}

public struct LocalizedGuidanceContent: Equatable, Sendable {
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
}

public struct GuidancePresentationSource: Equatable, Sendable {
  public let routeShields: [String]
  public let japaneseSignText: String
  public let localizedContent: [KaidoReleaseLocale: LocalizedGuidanceContent]

  public init(
    routeShields: [String],
    japaneseSignText: String,
    localizedContent: [KaidoReleaseLocale: LocalizedGuidanceContent]
  ) {
    self.routeShields = routeShields
    self.japaneseSignText = japaneseSignText
    self.localizedContent = localizedContent
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

public struct GuidanceFrameTemplate: Equatable, Sendable {
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
public struct ReleasedGuidanceDefinition: Equatable, Sendable {
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
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
