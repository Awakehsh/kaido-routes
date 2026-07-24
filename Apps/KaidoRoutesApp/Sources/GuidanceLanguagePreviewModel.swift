import Combine
import KaidoDomain
import KaidoPresentation

struct GuidanceLanguagePreviewFixture: Equatable, Sendable {
  let networkSnapshotID: String
  let routePlanID: String
  let guidanceFrame: GuidanceFrame
  let passageEvidence: RoutePassageEvidence

  static let synthetic = GuidanceLanguagePreviewFixture(
    networkSnapshotID: "preview.synthetic.snapshot-v1",
    routePlanID: "preview.synthetic.route-plan",
    guidanceFrame: GuidanceFrame(
      promptID: "preview.synthetic.prompt.prepare",
      anchorID: "PREPARE",
      anchorOccurrenceID: "preview.synthetic.occurrence.anchor",
      movementOccurrenceID: "preview.synthetic.occurrence.movement",
      decisionZoneID: "preview.synthetic.zone.junction",
      stage: .prepare,
      distanceMeters: 800,
      decisionPointNameJapanese: "辰巳JCT",
      localizedDecisionPointNames: [
        .japanese: "辰巳JCT",
        .simplifiedChinese: "辰巳 JCT",
        .english: "Tatsumi JCT",
      ],
      maneuver: .keepLeft,
      lanePreparation: .useLeftLanes,
      presentationSource: GuidancePresentationSource(
        routeShields: ["B"],
        japaneseSignText: "B 湾岸線・横浜方面",
        localizedContent: [
          .japanese: LocalizedGuidanceContent(
            displayText: "左側を進み、B 湾岸線・横浜方面へ",
            spokenText: "B 湾岸線、横浜方面へ",
            spokenForms: ["B": "ビー", "湾岸線": "わんがんせん"],
            preservedJapaneseSignText: "B 湾岸線・横浜方面"
          ),
          .simplifiedChinese: LocalizedGuidanceContent(
            displayText: "保持左侧，跟随 B 湾岸线・横滨方向",
            spokenText: "保持左侧，跟随 B 湾岸线，横滨方向",
            spokenForms: ["B": "B 路线", "湾岸線": "湾岸线"],
            preservedJapaneseSignText: "B 湾岸線・横浜方面"
          ),
          .english: LocalizedGuidanceContent(
            displayText: "Keep left for Route B toward Yokohama",
            spokenText: "Keep left for Route B toward Yokohama",
            spokenForms: ["B": "Route B", "湾岸線": "Bayshore Route"],
            preservedJapaneseSignText: "B 湾岸線・横浜方面"
          ),
        ]
      )
    ),
    passageEvidence: .noKnownConflictRealtimeUnconfirmed
  )
}

enum GuidanceLanguagePreviewModelError: Error, Equatable, Sendable {
  case projection(NavigationPresentationProjectionError)
  case unexpectedVoiceAuthority

  var code: String {
    switch self {
    case .projection:
      "GUIDANCE_LANGUAGE_PROJECTION_FAILED"
    case .unexpectedVoiceAuthority:
      "GUIDANCE_LANGUAGE_UNEXPECTED_VOICE_AUTHORITY"
    }
  }
}

@MainActor
final class GuidanceLanguagePreviewModel: ObservableObject {
  @Published private(set) var selection: NavigationLanguageSelection
  @Published private(set) var projection: NavigationPresentationProjection
  @Published private(set) var lastErrorCode: String?

  let fixture: GuidanceLanguagePreviewFixture

  init(
    fixture: GuidanceLanguagePreviewFixture = .synthetic,
    selection: NavigationLanguageSelection = NavigationLanguageSelection(
      interfaceLocale: .simplifiedChinese,
      guidanceVoiceLocale: .english
    )
  ) throws {
    self.fixture = fixture
    let projection = try Self.project(
      fixture: fixture,
      selection: selection
    )
    guard !projection.voice.shouldSpeak else {
      throw GuidanceLanguagePreviewModelError.unexpectedVoiceAuthority
    }
    self.selection = selection
    self.projection = projection
  }

  func selectInterfaceLocale(_ locale: KaidoReleaseLocale) {
    update(
      NavigationLanguageSelection(
        interfaceLocale: locale,
        guidanceVoiceLocale: selection.guidanceVoiceLocale
      )
    )
  }

  func selectGuidanceVoiceLocale(_ locale: KaidoReleaseLocale) {
    update(
      NavigationLanguageSelection(
        interfaceLocale: selection.interfaceLocale,
        guidanceVoiceLocale: locale
      )
    )
  }

  private func update(_ proposedSelection: NavigationLanguageSelection) {
    do {
      let proposedProjection = try Self.project(
        fixture: fixture,
        selection: proposedSelection
      )
      guard !proposedProjection.voice.shouldSpeak else {
        throw GuidanceLanguagePreviewModelError.unexpectedVoiceAuthority
      }
      selection = proposedSelection
      projection = proposedProjection
      lastErrorCode = nil
    } catch let error as GuidanceLanguagePreviewModelError {
      lastErrorCode = error.code
    } catch {
      lastErrorCode = "UNKNOWN_GUIDANCE_LANGUAGE_ERROR"
    }
  }

  private static func project(
    fixture: GuidanceLanguagePreviewFixture,
    selection: NavigationLanguageSelection
  ) throws -> NavigationPresentationProjection {
    let snapshot = NavigationSnapshot(
      journeyPhase: .planning,
      activeRoutePlanID: fixture.routePlanID,
      currentOccurrenceID: fixture.guidanceFrame.anchorOccurrenceID,
      locationConfidence: .medium
    )
    do {
      return try NavigationPresentationProjector.project(
        NavigationPresentationRequest(
          snapshot: snapshot,
          networkSnapshotID: fixture.networkSnapshotID,
          guidanceFrame: fixture.guidanceFrame,
          languages: selection,
          passageEvidence: fixture.passageEvidence,
          drivingContext: PresentationDrivingContext(
            isVehicleMoving: false,
            isInsideDecisionZone: false
          )
        )
      )
    } catch let error as NavigationPresentationProjectionError {
      throw GuidanceLanguagePreviewModelError.projection(error)
    }
  }
}
