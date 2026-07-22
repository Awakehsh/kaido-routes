import Foundation
import KaidoDomain

public struct NavigationLanguageSelection: Equatable, Sendable {
  public let interfaceLocale: KaidoReleaseLocale
  public let guidanceVoiceLocale: KaidoReleaseLocale

  public init(
    interfaceLocale: KaidoReleaseLocale,
    guidanceVoiceLocale: KaidoReleaseLocale
  ) {
    self.interfaceLocale = interfaceLocale
    self.guidanceVoiceLocale = guidanceVoiceLocale
  }
}

public enum RoutePassageEvidence: String, Codable, Sendable {
  case knownClosed = "KNOWN_CLOSED"
  case plannedConflict = "PLANNED_CONFLICT"
  case noKnownConflictRealtimeUnconfirmed = "NO_KNOWN_CONFLICT_REALTIME_UNCONFIRMED"
  case realtimeConfirmedPassable = "REALTIME_CONFIRMED_PASSABLE"
}

public enum RoutePassagePresentationTone: String, Codable, Sendable {
  case blocked = "BLOCKED"
  case warning = "WARNING"
  case unconfirmed = "UNCONFIRMED"
  case confirmedPassable = "CONFIRMED_PASSABLE"
}

public struct RoutePassagePresentation: Equatable, Sendable {
  public let evidence: RoutePassageEvidence
  public let tone: RoutePassagePresentationTone
  public let usesPositiveOpenColor: Bool

  public init(
    evidence: RoutePassageEvidence,
    tone: RoutePassagePresentationTone,
    usesPositiveOpenColor: Bool
  ) {
    self.evidence = evidence
    self.tone = tone
    self.usesPositiveOpenColor = usesPositiveOpenColor
  }
}

public enum NavigationMarkerPresentation: String, Codable, Sendable {
  case measured = "MEASURED"
  case estimated = "ESTIMATED"
  case unresolved = "UNRESOLVED"
}

public enum RouteEditingAvailability: String, Codable, Sendable {
  case availableWhileParked = "AVAILABLE_WHILE_PARKED"
  case unavailableWhileMoving = "UNAVAILABLE_WHILE_MOVING"
  case unavailableInDecisionZone = "UNAVAILABLE_IN_DECISION_ZONE"
  case lockedForActiveDrive = "LOCKED_FOR_ACTIVE_DRIVE"
}

public struct PresentationDrivingContext: Equatable, Sendable {
  public let isVehicleMoving: Bool
  public let isInsideDecisionZone: Bool

  public init(isVehicleMoving: Bool, isInsideDecisionZone: Bool) {
    self.isVehicleMoving = isVehicleMoving
    self.isInsideDecisionZone = isInsideDecisionZone
  }
}

public struct LocalizedFacilityName: Equatable, Sendable {
  public let values: [KaidoReleaseLocale: String]

  public init(values: [KaidoReleaseLocale: String]) {
    self.values = values
  }
}

public enum FinishDriveAnnouncementPriority: String, Codable, Sendable {
  case beforeBranchGuidance = "BEFORE_BRANCH_GUIDANCE"
}

public struct FinishDrivePresentation: Equatable, Sendable {
  public let exitFacilityID: String
  public let localizedExitName: String
  public let announcementPriority: FinishDriveAnnouncementPriority

  public init(
    exitFacilityID: String,
    localizedExitName: String,
    announcementPriority: FinishDriveAnnouncementPriority = .beforeBranchGuidance
  ) {
    self.exitFacilityID = exitFacilityID
    self.localizedExitName = localizedExitName
    self.announcementPriority = announcementPriority
  }
}

public struct NavigationPresentationRequest: Equatable, Sendable {
  public let snapshot: NavigationSnapshot
  public let guidanceFrame: GuidanceFrame
  public let promptEmission: GuidancePromptEmission?
  public let languages: NavigationLanguageSelection
  public let passageEvidence: RoutePassageEvidence
  public let drivingContext: PresentationDrivingContext
  public let facilityNames: [String: LocalizedFacilityName]

  public init(
    snapshot: NavigationSnapshot,
    guidanceFrame: GuidanceFrame,
    promptEmission: GuidancePromptEmission? = nil,
    languages: NavigationLanguageSelection,
    passageEvidence: RoutePassageEvidence,
    drivingContext: PresentationDrivingContext,
    facilityNames: [String: LocalizedFacilityName] = [:]
  ) {
    self.snapshot = snapshot
    self.guidanceFrame = guidanceFrame
    self.promptEmission = promptEmission
    self.languages = languages
    self.passageEvidence = passageEvidence
    self.drivingContext = drivingContext
    self.facilityNames = facilityNames
  }
}

public struct NavigationSurfacePresentation: Equatable, Sendable {
  public let surface: NavigationPresentationSurface
  public let isPrimarySurface: Bool
  public let routePlanID: String?
  public let currentOccurrenceID: String?
  public let nextMovementOccurrenceID: String?
  public let guidancePromptID: String
  public let guidanceAnchorID: String
  public let guidanceAnchorOccurrenceID: String
  public let decisionZoneID: String
  public let guidanceStage: GuidancePromptStage
  public let distanceMeters: Double
  public let decisionPointNameJapanese: String
  public let localizedDecisionPointName: String
  public let maneuver: GuidanceManeuver
  public let lanePreparation: GuidanceLanePreparation
  public let marker: NavigationMarkerPresentation
  public let routeShields: [String]
  public let japaneseSignText: String
  public let localizedDisplayText: String
  public let passage: RoutePassagePresentation
  public let routeEditingAvailability: RouteEditingAvailability
  public let requiresPhoneTouchWhileMoving: Bool
  public let finishDrive: FinishDrivePresentation?

  public init(
    surface: NavigationPresentationSurface,
    isPrimarySurface: Bool,
    routePlanID: String?,
    currentOccurrenceID: String?,
    nextMovementOccurrenceID: String?,
    guidancePromptID: String,
    guidanceAnchorID: String,
    guidanceAnchorOccurrenceID: String,
    decisionZoneID: String,
    guidanceStage: GuidancePromptStage,
    distanceMeters: Double,
    decisionPointNameJapanese: String,
    localizedDecisionPointName: String,
    maneuver: GuidanceManeuver,
    lanePreparation: GuidanceLanePreparation,
    marker: NavigationMarkerPresentation,
    routeShields: [String],
    japaneseSignText: String,
    localizedDisplayText: String,
    passage: RoutePassagePresentation,
    routeEditingAvailability: RouteEditingAvailability,
    requiresPhoneTouchWhileMoving: Bool,
    finishDrive: FinishDrivePresentation?
  ) {
    self.surface = surface
    self.isPrimarySurface = isPrimarySurface
    self.routePlanID = routePlanID
    self.currentOccurrenceID = currentOccurrenceID
    self.nextMovementOccurrenceID = nextMovementOccurrenceID
    self.guidancePromptID = guidancePromptID
    self.guidanceAnchorID = guidanceAnchorID
    self.guidanceAnchorOccurrenceID = guidanceAnchorOccurrenceID
    self.decisionZoneID = decisionZoneID
    self.guidanceStage = guidanceStage
    self.distanceMeters = distanceMeters
    self.decisionPointNameJapanese = decisionPointNameJapanese
    self.localizedDecisionPointName = localizedDecisionPointName
    self.maneuver = maneuver
    self.lanePreparation = lanePreparation
    self.marker = marker
    self.routeShields = routeShields
    self.japaneseSignText = japaneseSignText
    self.localizedDisplayText = localizedDisplayText
    self.passage = passage
    self.routeEditingAvailability = routeEditingAvailability
    self.requiresPhoneTouchWhileMoving = requiresPhoneTouchWhileMoving
    self.finishDrive = finishDrive
  }
}

public struct NavigationVoicePresentation: Equatable, Sendable {
  public let locale: KaidoReleaseLocale
  public let promptID: String
  public let stage: GuidancePromptStage
  public let distanceMeters: Double
  public let maneuver: GuidanceManeuver
  public let spokenText: String
  public let shouldSpeak: Bool

  public init(
    locale: KaidoReleaseLocale,
    promptID: String,
    stage: GuidancePromptStage,
    distanceMeters: Double,
    maneuver: GuidanceManeuver,
    spokenText: String,
    shouldSpeak: Bool
  ) {
    self.locale = locale
    self.promptID = promptID
    self.stage = stage
    self.distanceMeters = distanceMeters
    self.maneuver = maneuver
    self.spokenText = spokenText
    self.shouldSpeak = shouldSpeak
  }
}

public struct NavigationPresentationProjection: Equatable, Sendable {
  public let interfaceLocale: KaidoReleaseLocale
  public let iPhone: NavigationSurfacePresentation
  public let carPlay: NavigationSurfacePresentation
  public let voice: NavigationVoicePresentation

  public init(
    interfaceLocale: KaidoReleaseLocale,
    iPhone: NavigationSurfacePresentation,
    carPlay: NavigationSurfacePresentation,
    voice: NavigationVoicePresentation
  ) {
    self.interfaceLocale = interfaceLocale
    self.iPhone = iPhone
    self.carPlay = carPlay
    self.voice = voice
  }
}

public enum TollEvidenceStatus: String, Codable, Sendable {
  case verifiedQuery = "VERIFIED_QUERY"
  case estimated = "ESTIMATED"
  case unknown = "UNKNOWN"
}

public struct PreDriveReviewRequest: Equatable, Sendable {
  public let actualDistanceKM: Double
  public let tariffDistanceKM: Double?
  public let estimatedAmountYen: Int?
  public let tollEvidenceStatus: TollEvidenceStatus
  public let passageEvidence: RoutePassageEvidence

  public init(
    actualDistanceKM: Double,
    tariffDistanceKM: Double?,
    estimatedAmountYen: Int?,
    tollEvidenceStatus: TollEvidenceStatus,
    passageEvidence: RoutePassageEvidence
  ) {
    self.actualDistanceKM = actualDistanceKM
    self.tariffDistanceKM = tariffDistanceKM
    self.estimatedAmountYen = estimatedAmountYen
    self.tollEvidenceStatus = tollEvidenceStatus
    self.passageEvidence = passageEvidence
  }
}

public struct PreDriveReviewPresentation: Equatable, Sendable {
  public let actualDistanceKM: Double
  public let tariffDistanceKM: Double?
  public let estimatedAmountYen: Int?
  public let tollEvidenceStatus: TollEvidenceStatus
  public let passage: RoutePassagePresentation

  public init(
    actualDistanceKM: Double,
    tariffDistanceKM: Double?,
    estimatedAmountYen: Int?,
    tollEvidenceStatus: TollEvidenceStatus,
    passage: RoutePassagePresentation
  ) {
    self.actualDistanceKM = actualDistanceKM
    self.tariffDistanceKM = tariffDistanceKM
    self.estimatedAmountYen = estimatedAmountYen
    self.tollEvidenceStatus = tollEvidenceStatus
    self.passage = passage
  }
}
