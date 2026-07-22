import Foundation
import KaidoDomain

public enum NavigationPresentationProjectionError: Error, Equatable, Sendable {
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
  case promptEmissionMismatch
  case guidanceFrameNotCurrentOccurrence
  case inconsistentSurfaceState
  case missingExitName(String, KaidoReleaseLocale)
}

public enum PreDriveReviewProjectionError: Error, Equatable, Sendable {
  case invalidActualDistance
  case invalidTariffDistance
  case invalidEstimatedAmount
}

public enum NavigationPresentationProjector {
  public static func project(
    _ request: NavigationPresentationRequest
  ) throws -> NavigationPresentationProjection {
    try validate(request)

    guard
      let interfaceContent = request.guidanceFrame.presentationSource.localizedContent[
        request.languages.interfaceLocale
      ],
      let voiceContent = request.guidanceFrame.presentationSource.localizedContent[
        request.languages.guidanceVoiceLocale
      ],
      let interfaceDecisionPointName = request.guidanceFrame.localizedDecisionPointNames[
        request.languages.interfaceLocale
      ]
    else {
      // Full locale validation above makes this unreachable, but retain a typed
      // fail-closed boundary if the release locale set changes.
      throw NavigationPresentationProjectionError.missingLocale(
        request.languages.interfaceLocale
      )
    }

    let marker = markerPresentation(for: request.snapshot)
    let passage = passagePresentation(for: request.passageEvidence)
    let routeEditingAvailability = routeEditingAvailability(
      phase: request.snapshot.journeyPhase,
      context: request.drivingContext
    )
    let finishDrive = try finishDrivePresentation(for: request)

    let iPhone = surfacePresentation(
      .iPhone,
      request: request,
      displayText: interfaceContent.displayText,
      decisionPointName: interfaceDecisionPointName,
      marker: marker,
      passage: passage,
      routeEditingAvailability: routeEditingAvailability,
      finishDrive: finishDrive
    )
    let carPlay = surfacePresentation(
      .carPlay,
      request: request,
      displayText: interfaceContent.displayText,
      decisionPointName: interfaceDecisionPointName,
      marker: marker,
      passage: passage,
      routeEditingAvailability: routeEditingAvailability,
      finishDrive: finishDrive
    )

    return NavigationPresentationProjection(
      interfaceLocale: request.languages.interfaceLocale,
      iPhone: iPhone,
      carPlay: carPlay,
      voice: NavigationVoicePresentation(
        locale: request.languages.guidanceVoiceLocale,
        promptID: request.guidanceFrame.promptID,
        stage: request.guidanceFrame.stage,
        distanceMeters: request.guidanceFrame.distanceMeters,
        maneuver: request.guidanceFrame.maneuver,
        spokenText: voiceContent.spokenText,
        shouldSpeak: request.promptEmission != nil
      )
    )
  }

  public static func passagePresentation(
    for evidence: RoutePassageEvidence
  ) -> RoutePassagePresentation {
    switch evidence {
    case .knownClosed:
      RoutePassagePresentation(
        evidence: evidence,
        tone: .blocked,
        usesPositiveOpenColor: false
      )
    case .plannedConflict:
      RoutePassagePresentation(
        evidence: evidence,
        tone: .warning,
        usesPositiveOpenColor: false
      )
    case .noKnownConflictRealtimeUnconfirmed:
      RoutePassagePresentation(
        evidence: evidence,
        tone: .unconfirmed,
        usesPositiveOpenColor: false
      )
    case .realtimeConfirmedPassable:
      RoutePassagePresentation(
        evidence: evidence,
        tone: .confirmedPassable,
        usesPositiveOpenColor: true
      )
    }
  }

  private static func validate(_ request: NavigationPresentationRequest) throws {
    do {
      try GuidanceFrameValidator.validate(request.guidanceFrame)
    } catch let error as GuidanceFrameValidationError {
      throw projectionError(for: error)
    }
    if let emission = request.promptEmission {
      guard emission.promptID == request.guidanceFrame.promptID,
        emission.anchorID == request.guidanceFrame.anchorID,
        emission.anchorOccurrenceID == request.guidanceFrame.anchorOccurrenceID,
        request.snapshot.lastGuidancePromptID == emission.promptID,
        request.snapshot.emittedGuidancePromptIDs.contains(emission.promptID)
      else {
        throw NavigationPresentationProjectionError.promptEmissionMismatch
      }
    }
    if let currentOccurrenceID = request.snapshot.currentOccurrenceID,
      currentOccurrenceID != request.guidanceFrame.anchorOccurrenceID
    {
      throw NavigationPresentationProjectionError.guidanceFrameNotCurrentOccurrence
    }
    switch (
      request.snapshot.presentationSurface,
      request.snapshot.carPlayConnectionState
    ) {
    case (.iPhone, .disconnected), (.carPlay, .connected):
      break
    case (.iPhone, .connected), (.carPlay, .disconnected):
      throw NavigationPresentationProjectionError.inconsistentSurfaceState
    }
  }

  private static func projectionError(
    for error: GuidanceFrameValidationError
  ) -> NavigationPresentationProjectionError {
    switch error {
    case .missingPromptID: .missingPromptID
    case .missingAnchorID: .missingAnchorID
    case .missingAnchorOccurrenceID: .missingAnchorOccurrenceID
    case .missingMovementOccurrenceID: .missingMovementOccurrenceID
    case .missingDecisionZoneID: .missingDecisionZoneID
    case .invalidDistanceMeters: .invalidDistanceMeters
    case .missingDecisionPointNameJapanese: .missingDecisionPointNameJapanese
    case .missingDecisionPointLocale(let locale): .missingDecisionPointLocale(locale)
    case .decisionPointJapaneseNameMismatch: .decisionPointJapaneseNameMismatch
    case .missingRouteShield: .missingRouteShield
    case .missingJapaneseSignText: .missingJapaneseSignText
    case .missingLocale(let locale): .missingLocale(locale)
    case .incompleteLocale(let locale): .incompleteLocale(locale)
    case .japaneseSignTextMismatch(let locale): .japaneseSignTextMismatch(locale)
    }
  }

  private static func markerPresentation(
    for snapshot: NavigationSnapshot
  ) -> NavigationMarkerPresentation {
    if snapshot.routeCandidateResolution == .ambiguous
      || snapshot.markerStyle == NavigationMarkerPresentation.unresolved.rawValue
    {
      return .unresolved
    }
    if snapshot.locationConfidence <= .low
      || snapshot.markerStyle != NavigationMarkerPresentation.measured.rawValue
    {
      return .estimated
    }
    return .measured
  }

  private static func routeEditingAvailability(
    phase: JourneyPhase,
    context: PresentationDrivingContext
  ) -> RouteEditingAvailability {
    if context.isVehicleMoving && context.isInsideDecisionZone {
      return .unavailableInDecisionZone
    }
    if context.isVehicleMoving {
      return .unavailableWhileMoving
    }
    if phase != .planning {
      return .lockedForActiveDrive
    }
    return .availableWhileParked
  }

  private static func finishDrivePresentation(
    for request: NavigationPresentationRequest
  ) throws -> FinishDrivePresentation? {
    guard let exitFacilityID = request.snapshot.finishConfirmationExitFacilityID else {
      return nil
    }
    guard let names = request.facilityNames[exitFacilityID]?.values else {
      throw NavigationPresentationProjectionError.missingExitName(
        exitFacilityID,
        request.languages.interfaceLocale
      )
    }
    for locale in KaidoReleaseLocale.allCases {
      guard let name = names[locale],
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        throw NavigationPresentationProjectionError.missingExitName(exitFacilityID, locale)
      }
    }
    guard let exitName = names[request.languages.interfaceLocale] else {
      throw NavigationPresentationProjectionError.missingExitName(
        exitFacilityID,
        request.languages.interfaceLocale
      )
    }
    return FinishDrivePresentation(
      exitFacilityID: exitFacilityID,
      localizedExitName: exitName
    )
  }

  private static func surfacePresentation(
    _ surface: NavigationPresentationSurface,
    request: NavigationPresentationRequest,
    displayText: String,
    decisionPointName: String,
    marker: NavigationMarkerPresentation,
    passage: RoutePassagePresentation,
    routeEditingAvailability: RouteEditingAvailability,
    finishDrive: FinishDrivePresentation?
  ) -> NavigationSurfacePresentation {
    NavigationSurfacePresentation(
      surface: surface,
      isPrimarySurface: request.snapshot.presentationSurface == surface,
      routePlanID: request.snapshot.activeRoutePlanID,
      currentOccurrenceID: request.snapshot.currentOccurrenceID,
      nextMovementOccurrenceID: request.guidanceFrame.movementOccurrenceID,
      guidancePromptID: request.guidanceFrame.promptID,
      guidanceAnchorID: request.guidanceFrame.anchorID,
      guidanceAnchorOccurrenceID: request.guidanceFrame.anchorOccurrenceID,
      decisionZoneID: request.guidanceFrame.decisionZoneID,
      guidanceStage: request.guidanceFrame.stage,
      distanceMeters: request.guidanceFrame.distanceMeters,
      decisionPointNameJapanese: request.guidanceFrame.decisionPointNameJapanese,
      localizedDecisionPointName: decisionPointName,
      maneuver: request.guidanceFrame.maneuver,
      lanePreparation: request.guidanceFrame.lanePreparation,
      marker: marker,
      routeShields: request.guidanceFrame.presentationSource.routeShields,
      japaneseSignText: request.guidanceFrame.presentationSource.japaneseSignText,
      localizedDisplayText: displayText,
      passage: passage,
      routeEditingAvailability: routeEditingAvailability,
      requiresPhoneTouchWhileMoving: false,
      finishDrive: finishDrive
    )
  }
}

public enum PreDriveReviewProjector {
  public static func project(
    _ request: PreDriveReviewRequest
  ) throws -> PreDriveReviewPresentation {
    guard request.actualDistanceKM.isFinite, request.actualDistanceKM > 0 else {
      throw PreDriveReviewProjectionError.invalidActualDistance
    }
    if let tariffDistanceKM = request.tariffDistanceKM,
      !tariffDistanceKM.isFinite || tariffDistanceKM < 0
    {
      throw PreDriveReviewProjectionError.invalidTariffDistance
    }
    if let estimatedAmountYen = request.estimatedAmountYen, estimatedAmountYen < 0 {
      throw PreDriveReviewProjectionError.invalidEstimatedAmount
    }
    return PreDriveReviewPresentation(
      actualDistanceKM: request.actualDistanceKM,
      tariffDistanceKM: request.tariffDistanceKM,
      estimatedAmountYen: request.estimatedAmountYen,
      tollEvidenceStatus: request.tollEvidenceStatus,
      passage: NavigationPresentationProjector.passagePresentation(
        for: request.passageEvidence
      )
    )
  }
}
