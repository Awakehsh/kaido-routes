import Combine
import KaidoDomain
import KaidoNavigation
import KaidoPresentation
import KaidoRouting

enum SyntheticDrivingPreviewCase: String, CaseIterable, Identifiable, Sendable {
  case measuredReference = "MEASURED_REFERENCE"
  case degradedDecisionZone = "DEGRADED_DECISION_ZONE"
  case reviewedJunctionHandoff = "REVIEWED_JUNCTION_HANDOFF"
  case finishDrive = "FINISH_DRIVE"

  var id: String { rawValue }
}

struct SyntheticDrivingPreviewFixture: Equatable, Sendable {
  let networkSnapshotID: String
  let routePlan: RoutePlan
  let egressOption: EgressOption
  let approachFrame: GuidanceFrame
  let junctionFrame: GuidanceFrame
  let finishFrame: GuidanceFrame
  let facilityNames: [String: LocalizedFacilityName]

  static let synthetic: SyntheticDrivingPreviewFixture = {
    let snapshotID = "preview.synthetic.driving-snapshot-v1"
    let currentOccurrenceID = "preview.synthetic.driving-occurrence.current"
    let egressOccurrenceID = "preview.synthetic.driving-occurrence.egress"
    let exitFacilityID = "preview.synthetic.exit.shibakoen"
    let routePlan = RoutePlan(
      id: "preview.synthetic.driving-route-plan",
      networkSnapshotID: snapshotID,
      entryFacilityID: "preview.synthetic.entry",
      exitFacilityID: "preview.synthetic.exit.default",
      recoveryPolicy: .safeExit,
      occurrences: [
        RouteOccurrence(
          id: currentOccurrenceID,
          index: 0,
          kind: .edge,
          entityID: "preview.synthetic.edge.current"
        ),
        RouteOccurrence(
          id: egressOccurrenceID,
          index: 1,
          kind: .junctionMovement,
          entityID: "preview.synthetic.movement.egress"
        ),
      ]
    )
    return SyntheticDrivingPreviewFixture(
      networkSnapshotID: snapshotID,
      routePlan: routePlan,
      egressOption: EgressOption(
        id: "preview.synthetic.egress.shibakoen",
        firstEligibleOccurrenceID: egressOccurrenceID,
        exitFacilityID: exitFacilityID,
        egressOccurrenceIDs: [egressOccurrenceID],
        isReleased: true
      ),
      approachFrame: GuidanceFrame(
        promptID: "preview.synthetic.prompt.commit",
        anchorID: "COMMIT",
        anchorOccurrenceID: currentOccurrenceID,
        movementOccurrenceID: egressOccurrenceID,
        decisionZoneID: "preview.synthetic.zone.kasai",
        stage: .commit,
        distanceMeters: 300,
        decisionPointNameJapanese: "葛西JCT",
        localizedDecisionPointNames: [
          .japanese: "葛西JCT",
          .simplifiedChinese: "葛西 JCT",
          .english: "Kasai JCT",
        ],
        maneuver: .keepLeft,
        lanePreparation: .useLeftLanes,
        presentationSource: guidanceSource(
          routeShield: "B",
          japaneseSignText: "B 湾岸線・横浜方面",
          japaneseDisplayText: "左側を進み、B 湾岸線・横浜方面へ",
          chineseDisplayText: "保持左侧，跟随 B 湾岸线・横滨方向",
          englishDisplayText: "Keep left for Route B toward Yokohama"
        )
      ),
      junctionFrame: GuidanceFrame(
        promptID: "preview.synthetic.prompt.junction-prepare",
        anchorID: "PREPARE",
        anchorOccurrenceID: currentOccurrenceID,
        movementOccurrenceID: egressOccurrenceID,
        decisionZoneID: "preview.synthetic.zone.reviewed-junction",
        stage: .prepare,
        distanceMeters: 600,
        decisionPointNameJapanese: "テストJCT",
        localizedDecisionPointNames: [
          .japanese: "テストJCT",
          .simplifiedChinese: "测试 JCT",
          .english: "Test JCT",
        ],
        maneuver: .keepLeft,
        lanePreparation: .useLeftLanes,
        presentationSource: guidanceSource(
          routeShield: "B",
          japaneseSignText: "B 湾岸線・横浜方面",
          japaneseDisplayText: "左側を進み、B 湾岸線・横浜方面へ",
          chineseDisplayText: "保持左侧，跟随 B 湾岸线・横滨方向",
          englishDisplayText: "Keep left for Route B toward Yokohama",
          junctionView: JunctionViewDefinition(
            id: "preview.synthetic.junction-view.selected-movement",
            networkSnapshotID: snapshotID,
            movementOccurrenceID: egressOccurrenceID,
            paths: [
              JunctionViewPath(
                id: "preview.synthetic.junction-path.approach",
                role: .approach,
                points: [
                  JunctionViewPoint(x: 0.5, y: 1),
                  JunctionViewPoint(x: 0.5, y: 0.55),
                ]
              ),
              JunctionViewPath(
                id: "preview.synthetic.junction-path.selected",
                role: .selected,
                points: [
                  JunctionViewPoint(x: 0.5, y: 0.55),
                  JunctionViewPoint(x: 0.35, y: 0.3),
                  JunctionViewPoint(x: 0.15, y: 0.05),
                ]
              ),
              JunctionViewPath(
                id: "preview.synthetic.junction-path.alternative",
                role: .alternative,
                points: [
                  JunctionViewPoint(x: 0.5, y: 0.55),
                  JunctionViewPoint(x: 0.65, y: 0.3),
                  JunctionViewPoint(x: 0.85, y: 0.05),
                ]
              ),
            ],
            laneLayout: JunctionViewLaneLayout(
              laneCount: 3,
              allowedLaneIndices: [0, 1],
              preferredLaneIndices: [0]
            ),
            japaneseSignText: "B 湾岸線・横浜方面",
            routeShields: ["B"],
            evidence: JunctionViewEvidence(
              state: .released,
              checkedAt: "2026-07-24",
              sourceReferenceIDs: [
                "preview.synthetic.source.reviewed-junction"
              ]
            )
          )
        )
      ),
      finishFrame: GuidanceFrame(
        promptID: "preview.synthetic.prompt.finish",
        anchorID: "FINISH",
        anchorOccurrenceID: currentOccurrenceID,
        movementOccurrenceID: egressOccurrenceID,
        decisionZoneID: "preview.synthetic.zone.shibakoen-exit",
        stage: .finish,
        distanceMeters: 1_200,
        decisionPointNameJapanese: "芝公園出口",
        localizedDecisionPointNames: [
          .japanese: "芝公園出口",
          .simplifiedChinese: "芝公园出口",
          .english: "Shibakoen Exit",
        ],
        maneuver: .takeExitLeft,
        lanePreparation: .useLeftLanes,
        presentationSource: guidanceSource(
          routeShield: "C1",
          japaneseSignText: "芝公園出口",
          japaneseDisplayText: "芝公園出口へ進みます",
          chineseDisplayText: "将从芝公园出口结束驾驶",
          englishDisplayText: "Finish at Shibakoen Exit"
        )
      ),
      facilityNames: [
        exitFacilityID: LocalizedFacilityName(
          values: [
            .japanese: "芝公園出口",
            .simplifiedChinese: "芝公园出口",
            .english: "Shibakoen Exit",
          ]
        )
      ]
    )
  }()

  private static func guidanceSource(
    routeShield: String,
    japaneseSignText: String,
    japaneseDisplayText: String,
    chineseDisplayText: String,
    englishDisplayText: String,
    junctionView: JunctionViewDefinition? = nil
  ) -> GuidancePresentationSource {
    GuidancePresentationSource(
      routeShields: [routeShield],
      japaneseSignText: japaneseSignText,
      localizedContent: [
        .japanese: LocalizedGuidanceContent(
          displayText: japaneseDisplayText,
          spokenText: japaneseDisplayText,
          spokenForms: [routeShield: routeShield == "B" ? "ビー" : "シーワン"],
          preservedJapaneseSignText: japaneseSignText
        ),
        .simplifiedChinese: LocalizedGuidanceContent(
          displayText: chineseDisplayText,
          spokenText: chineseDisplayText,
          spokenForms: [routeShield: "\(routeShield) 路线"],
          preservedJapaneseSignText: japaneseSignText
        ),
        .english: LocalizedGuidanceContent(
          displayText: englishDisplayText,
          spokenText: englishDisplayText,
          spokenForms: [routeShield: "Route \(routeShield)"],
          preservedJapaneseSignText: japaneseSignText
        ),
      ],
      junctionView: junctionView
    )
  }
}

struct SyntheticDrivingPreviewState: Equatable, Sendable {
  let previewCase: SyntheticDrivingPreviewCase
  let snapshot: NavigationSnapshot
  let projection: NavigationPresentationProjection
  let isInsideDecisionZone: Bool
}

enum SyntheticDrivingPreviewModelError: Error, Equatable, Sendable {
  case projection(NavigationPresentationProjectionError)
  case unexpectedVoiceAuthority
  case degradedStateSemanticDrift
  case finishDriveUnavailable
  case finishDriveSemanticDrift
  case junctionStateSemanticDrift
  case surfaceSemanticDrift

  var code: String {
    switch self {
    case .projection:
      "DRIVING_PREVIEW_PROJECTION_FAILED"
    case .unexpectedVoiceAuthority:
      "DRIVING_PREVIEW_UNEXPECTED_VOICE_AUTHORITY"
    case .degradedStateSemanticDrift:
      "DRIVING_PREVIEW_DEGRADED_STATE_DRIFT"
    case .finishDriveUnavailable:
      "DRIVING_PREVIEW_FINISH_UNAVAILABLE"
    case .finishDriveSemanticDrift:
      "DRIVING_PREVIEW_FINISH_STATE_DRIFT"
    case .junctionStateSemanticDrift:
      "DRIVING_PREVIEW_JUNCTION_STATE_DRIFT"
    case .surfaceSemanticDrift:
      "DRIVING_PREVIEW_SURFACE_STATE_DRIFT"
    }
  }
}

@MainActor
final class SyntheticDrivingPreviewModel: ObservableObject {
  @Published private(set) var selectedCase: SyntheticDrivingPreviewCase
  @Published private(set) var state: SyntheticDrivingPreviewState
  @Published private(set) var lastErrorCode: String?

  let fixture: SyntheticDrivingPreviewFixture

  init(
    fixture: SyntheticDrivingPreviewFixture = .synthetic,
    initialCase: SyntheticDrivingPreviewCase = .degradedDecisionZone
  ) throws {
    self.fixture = fixture
    selectedCase = initialCase
    state = try Self.makeState(
      previewCase: initialCase,
      fixture: fixture
    )
  }

  func select(_ previewCase: SyntheticDrivingPreviewCase) {
    do {
      let proposedState = try Self.makeState(
        previewCase: previewCase,
        fixture: fixture
      )
      selectedCase = previewCase
      state = proposedState
      lastErrorCode = nil
    } catch let error as SyntheticDrivingPreviewModelError {
      lastErrorCode = error.code
    } catch {
      lastErrorCode = "UNKNOWN_DRIVING_PREVIEW_ERROR"
    }
  }

  private static func makeState(
    previewCase: SyntheticDrivingPreviewCase,
    fixture: SyntheticDrivingPreviewFixture
  ) throws -> SyntheticDrivingPreviewState {
    var engine = NavigationEngine(
      configuration: NavigationConfiguration(
        routePlan: fixture.routePlan,
        egressOptions: [fixture.egressOption]
      ),
      initialSnapshot: NavigationSnapshot(
        journeyPhase: .strictRoute,
        activeRoutePlanID: fixture.routePlan.id,
        currentOccurrenceID: fixture.routePlan.occurrences[0].id,
        locationConfidence: .high
      )
    )

    let frame: GuidanceFrame
    let passageEvidence: RoutePassageEvidence
    let drivingContext: PresentationDrivingContext
    let languageSelection: NavigationLanguageSelection
    switch previewCase {
    case .measuredReference:
      frame = fixture.approachFrame
      passageEvidence = .realtimeConfirmedPassable
      drivingContext = PresentationDrivingContext(
        isVehicleMoving: false,
        isInsideDecisionZone: false
      )
      languageSelection = NavigationLanguageSelection(
        interfaceLocale: .simplifiedChinese,
        guidanceVoiceLocale: .english
      )
    case .degradedDecisionZone:
      engine.observeLocation(
        LocationObservation(
          reportedConfidence: .low,
          ageMilliseconds: 12_000
        )
      )
      frame = fixture.approachFrame
      passageEvidence = .noKnownConflictRealtimeUnconfirmed
      drivingContext = PresentationDrivingContext(
        isVehicleMoving: true,
        isInsideDecisionZone: true
      )
      languageSelection = NavigationLanguageSelection(
        interfaceLocale: .simplifiedChinese,
        guidanceVoiceLocale: .english
      )
    case .reviewedJunctionHandoff:
      engine.connectCarPlay()
      frame = fixture.junctionFrame
      passageEvidence = .noKnownConflictRealtimeUnconfirmed
      drivingContext = PresentationDrivingContext(
        isVehicleMoving: true,
        isInsideDecisionZone: true
      )
      languageSelection = NavigationLanguageSelection(
        interfaceLocale: .simplifiedChinese,
        guidanceVoiceLocale: .japanese
      )
    case .finishDrive:
      engine.finishDrive()
      guard engine.snapshot.egress.status == .active else {
        throw SyntheticDrivingPreviewModelError.finishDriveUnavailable
      }
      frame = fixture.finishFrame
      passageEvidence = .realtimeConfirmedPassable
      drivingContext = PresentationDrivingContext(
        isVehicleMoving: true,
        isInsideDecisionZone: false
      )
      languageSelection = NavigationLanguageSelection(
        interfaceLocale: .simplifiedChinese,
        guidanceVoiceLocale: .english
      )
    }

    let projection: NavigationPresentationProjection
    do {
      projection = try NavigationPresentationProjector.project(
        NavigationPresentationRequest(
          snapshot: engine.snapshot,
          networkSnapshotID: fixture.networkSnapshotID,
          guidanceFrame: frame,
          languages: languageSelection,
          passageEvidence: passageEvidence,
          drivingContext: drivingContext,
          facilityNames: fixture.facilityNames
        )
      )
    } catch let error as NavigationPresentationProjectionError {
      throw SyntheticDrivingPreviewModelError.projection(error)
    }

    guard !projection.voice.shouldSpeak else {
      throw SyntheticDrivingPreviewModelError.unexpectedVoiceAuthority
    }
    guard
      projection.iPhone.currentOccurrenceID == projection.carPlay.currentOccurrenceID,
      projection.iPhone.nextMovementOccurrenceID
        == projection.carPlay.nextMovementOccurrenceID,
      projection.iPhone.guidancePromptID == projection.carPlay.guidancePromptID,
      projection.iPhone.guidanceAnchorID == projection.carPlay.guidanceAnchorID,
      projection.iPhone.decisionZoneID == projection.carPlay.decisionZoneID,
      projection.iPhone.distanceMeters == projection.carPlay.distanceMeters,
      projection.iPhone.maneuver == projection.carPlay.maneuver,
      projection.iPhone.lanePreparation == projection.carPlay.lanePreparation,
      projection.iPhone.marker == projection.carPlay.marker,
      projection.iPhone.japaneseSignText == projection.carPlay.japaneseSignText,
      projection.iPhone.routeShields == projection.carPlay.routeShields,
      projection.iPhone.junctionView == projection.carPlay.junctionView,
      projection.iPhone.finishDrive == projection.carPlay.finishDrive
    else {
      throw SyntheticDrivingPreviewModelError.surfaceSemanticDrift
    }

    if previewCase == .reviewedJunctionHandoff {
      guard
        engine.snapshot.presentationSurface == .carPlay,
        engine.snapshot.carPlayConnectionState == .connected,
        projection.carPlay.isPrimarySurface,
        !projection.iPhone.isPrimarySurface,
        let junctionView = projection.iPhone.junctionView,
        junctionView.networkSnapshotID == fixture.networkSnapshotID,
        junctionView.movementOccurrenceID
          == projection.iPhone.nextMovementOccurrenceID,
        junctionView.paths.count(where: { $0.role == .selected }) == 1,
        junctionView.laneLayout.laneCount == 3,
        junctionView.laneLayout.preferredLaneIndices == [0],
        junctionView.japaneseSignText == projection.iPhone.japaneseSignText,
        junctionView.routeShields == projection.iPhone.routeShields,
        junctionView.evidence.state == .released
      else {
        throw SyntheticDrivingPreviewModelError.junctionStateSemanticDrift
      }
    }

    if previewCase == .degradedDecisionZone {
      guard
        engine.snapshot.locationConfidence == .low,
        projection.iPhone.marker == .estimated,
        projection.iPhone.passage.tone == .unconfirmed,
        !projection.iPhone.passage.usesPositiveOpenColor,
        projection.iPhone.routeEditingAvailability == .unavailableInDecisionZone,
        !projection.iPhone.requiresPhoneTouchWhileMoving
      else {
        throw SyntheticDrivingPreviewModelError.degradedStateSemanticDrift
      }
    }

    if previewCase == .finishDrive {
      guard
        let finish = projection.iPhone.finishDrive,
        finish.exitFacilityID == engine.snapshot.egress.exitFacilityID,
        finish.announcementPriority == .beforeBranchGuidance,
        engine.snapshot.egress.prohibitedActions.contains("U_TURN_OR_REVERSAL")
      else {
        throw SyntheticDrivingPreviewModelError.finishDriveSemanticDrift
      }
    }

    return SyntheticDrivingPreviewState(
      previewCase: previewCase,
      snapshot: engine.snapshot,
      projection: projection,
      isInsideDecisionZone: drivingContext.isInsideDecisionZone
    )
  }
}
