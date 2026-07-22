import Foundation
import KaidoDomain

public enum NavigationPresentationProjectionError: Error, Equatable, Sendable {
  case missingRouteShield
  case missingJapaneseSignText
  case missingLocale(KaidoReleaseLocale)
  case incompleteLocale(KaidoReleaseLocale)
  case japaneseSignTextMismatch(KaidoReleaseLocale)
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
      let interfaceContent = request.guidance.localizedContent[
        request.languages.interfaceLocale
      ],
      let voiceContent = request.guidance.localizedContent[
        request.languages.guidanceVoiceLocale
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
      marker: marker,
      passage: passage,
      routeEditingAvailability: routeEditingAvailability,
      finishDrive: finishDrive
    )
    let carPlay = surfacePresentation(
      .carPlay,
      request: request,
      displayText: interfaceContent.displayText,
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
        spokenText: voiceContent.spokenText
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
    guard !request.guidance.routeShields.isEmpty,
      request.guidance.routeShields.allSatisfy({
        !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      })
    else {
      throw NavigationPresentationProjectionError.missingRouteShield
    }
    guard
      !request.guidance.japaneseSignText.trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty
    else {
      throw NavigationPresentationProjectionError.missingJapaneseSignText
    }
    for locale in KaidoReleaseLocale.allCases {
      guard let content = request.guidance.localizedContent[locale] else {
        throw NavigationPresentationProjectionError.missingLocale(locale)
      }
      guard
        !content.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        !content.spokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        !content.spokenForms.isEmpty,
        content.spokenForms.allSatisfy({
          !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })
      else {
        throw NavigationPresentationProjectionError.incompleteLocale(locale)
      }
      guard content.preservedJapaneseSignText == request.guidance.japaneseSignText else {
        throw NavigationPresentationProjectionError.japaneseSignTextMismatch(locale)
      }
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
      nextMovementOccurrenceID: request.nextMovementOccurrenceID,
      marker: marker,
      routeShields: request.guidance.routeShields,
      japaneseSignText: request.guidance.japaneseSignText,
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
