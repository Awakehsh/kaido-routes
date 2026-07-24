import Combine
import Foundation
import KaidoDomain
import KaidoRouting

struct ParkedRouteEditorFixturePresentation: Sendable {
  let entranceTitle: String
  let completedRouteTitle: String
  let choiceTitles: [String: String]
  let choiceDetails: [String: String]
  let decisionTitles: [String: String]
}

struct ParkedRouteEditorFixture: Sendable {
  let catalog: ReviewedRouteEditorCatalog
  let distanceCatalog: ReviewedRouteDistanceCatalog
  let entranceFacilityID: String
  let routePlanID: String
  let initialOccurrenceID: String
  let presentations: [KaidoReleaseLocale: ParkedRouteEditorFixturePresentation]
  let freehandCorridorMatch: FreehandCorridorChoiceMatch

  static let synthetic = ParkedRouteEditorFixture(
    catalog: ReviewedRouteEditorCatalog(
      networkSnapshotID: "preview.synthetic.snapshot-v1",
      entrances: [
        ReviewedRouteEditorEntrance(
          facilityID: "preview.synthetic.entrance.eastbound",
          initialEdgeID: "preview.synthetic.edge.entry-mainline",
          initialEdgeTollDomainID: "preview.synthetic.toll.shuto",
          firstDecisionPointID: "preview.synthetic.decision.loop-gate"
        )
      ],
      decisionPoints: [
        ReviewedRouteEditorDecisionPoint(
          id: "preview.synthetic.decision.loop-gate",
          incomingApproachID: "preview.synthetic.approach.entry.eastbound",
          junctionComplexID: "preview.synthetic.junction.loop-gate",
          choices: [
            ReviewedRouteEditorChoice(
              id: "preview.synthetic.choice.enter-loop",
              movementID: "preview.synthetic.movement.enter-loop",
              movementTollDomainID: "preview.synthetic.toll.shuto",
              outgoingEdgeID: "preview.synthetic.edge.loop",
              outgoingEdgeTollDomainID: "preview.synthetic.toll.shuto",
              destination: .decisionPoint("preview.synthetic.decision.loop")
            ),
            ReviewedRouteEditorChoice(
              id: "preview.synthetic.choice.early-exit",
              movementID: "preview.synthetic.movement.early-exit",
              movementTollDomainID: "preview.synthetic.toll.shuto",
              outgoingEdgeID: "preview.synthetic.edge.early-exit-ramp",
              outgoingEdgeTollDomainID: "preview.synthetic.toll.shuto",
              destination: .exitFacility("preview.synthetic.exit.eastbound")
            ),
          ]
        ),
        ReviewedRouteEditorDecisionPoint(
          id: "preview.synthetic.decision.loop",
          incomingApproachID: "preview.synthetic.approach.loop.clockwise",
          junctionComplexID: "preview.synthetic.junction.loop",
          choices: [
            ReviewedRouteEditorChoice(
              id: "preview.synthetic.choice.repeat-loop",
              movementID: "preview.synthetic.movement.repeat-loop",
              movementTollDomainID: "preview.synthetic.toll.shuto",
              outgoingEdgeID: "preview.synthetic.edge.loop",
              outgoingEdgeTollDomainID: "preview.synthetic.toll.shuto",
              destination: .decisionPoint("preview.synthetic.decision.loop")
            ),
            ReviewedRouteEditorChoice(
              id: "preview.synthetic.choice.final-exit",
              movementID: "preview.synthetic.movement.final-exit",
              movementTollDomainID: "preview.synthetic.toll.shuto",
              outgoingEdgeID: "preview.synthetic.edge.final-exit-ramp",
              outgoingEdgeTollDomainID: "preview.synthetic.toll.shuto",
              destination: .exitFacility("preview.synthetic.exit.eastbound")
            ),
          ]
        ),
      ],
      lapTemplates: [
        ReviewedRouteEditorLapTemplate(
          id: "preview.synthetic.lap-template.loop",
          startDecisionPointID: "preview.synthetic.decision.loop",
          choiceIDs: ["preview.synthetic.choice.repeat-loop"]
        )
      ]
    ),
    distanceCatalog: ReviewedRouteDistanceCatalog(
      networkSnapshotID: "preview.synthetic.snapshot-v1",
      distanceKMByEntityID: [
        "preview.synthetic.edge.entry-mainline": 1.8,
        "preview.synthetic.movement.enter-loop": 0.4,
        "preview.synthetic.edge.loop": 12,
        "preview.synthetic.movement.early-exit": 0.3,
        "preview.synthetic.edge.early-exit-ramp": 1.2,
        "preview.synthetic.movement.repeat-loop": 0.4,
        "preview.synthetic.movement.final-exit": 0.3,
        "preview.synthetic.edge.final-exit-ramp": 1.4,
      ]
    ),
    entranceFacilityID: "preview.synthetic.entrance.eastbound",
    routePlanID: "preview.synthetic.route-plan",
    initialOccurrenceID: "preview.synthetic.occurrence.entry.0",
    presentations: [
      .japanese: ParkedRouteEditorFixturePresentation(
        entranceTitle: "デモ入口・東行き",
        completedRouteTitle: "経路作成完了",
        choiceTitles: [
          "preview.synthetic.choice.enter-loop": "デモループへ進む",
          "preview.synthetic.choice.early-exit": "デモ出口へ直接進む",
          "preview.synthetic.choice.repeat-loop": "もう一度ループを走る",
          "preview.synthetic.choice.final-exit": "デモ出口へ進む",
        ],
        choiceDetails: [
          "preview.synthetic.choice.enter-loop": "次の審査済み分岐へ進む",
          "preview.synthetic.choice.early-exit": "明示した東行き出口を選ぶ",
          "preview.synthetic.choice.repeat-loop":
            "重複区間を新しい occurrence として保持",
          "preview.synthetic.choice.final-exit": "経路を完了してコンパイルを許可",
        ],
        decisionTitles: [
          "preview.synthetic.decision.loop-gate": "ループ入口の分岐",
          "preview.synthetic.decision.loop": "ループ内の分岐",
        ]
      ),
      .simplifiedChinese: ParkedRouteEditorFixturePresentation(
        entranceTitle: "演示入口 · 东向",
        completedRouteTitle: "路线已完成",
        choiceTitles: [
          "preview.synthetic.choice.enter-loop": "进入演示环线",
          "preview.synthetic.choice.early-exit": "直接驶出演示出口",
          "preview.synthetic.choice.repeat-loop": "再经过一次环线",
          "preview.synthetic.choice.final-exit": "驶出演示出口",
        ],
        choiceDetails: [
          "preview.synthetic.choice.enter-loop": "前往下一个已审核分岔",
          "preview.synthetic.choice.early-exit": "选择明确的东向出口",
          "preview.synthetic.choice.repeat-loop": "保留重复路段为新 occurrence",
          "preview.synthetic.choice.final-exit": "完成路线后允许编译",
        ],
        decisionTitles: [
          "preview.synthetic.decision.loop-gate": "环线入口分岔",
          "preview.synthetic.decision.loop": "环线内分岔",
        ]
      ),
      .english: ParkedRouteEditorFixturePresentation(
        entranceTitle: "Demo entrance · eastbound",
        completedRouteTitle: "Route complete",
        choiceTitles: [
          "preview.synthetic.choice.enter-loop": "Enter the demo loop",
          "preview.synthetic.choice.early-exit": "Take the demo exit directly",
          "preview.synthetic.choice.repeat-loop": "Travel the loop again",
          "preview.synthetic.choice.final-exit": "Take the demo exit",
        ],
        choiceDetails: [
          "preview.synthetic.choice.enter-loop": "Continue to the next reviewed decision",
          "preview.synthetic.choice.early-exit": "Choose the explicit eastbound exit",
          "preview.synthetic.choice.repeat-loop":
            "Preserve the repeated segment as a fresh occurrence",
          "preview.synthetic.choice.final-exit": "Complete the route and allow compilation",
        ],
        decisionTitles: [
          "preview.synthetic.decision.loop-gate": "Loop entrance decision",
          "preview.synthetic.decision.loop": "Decision inside the loop",
        ]
      ),
    ],
    freehandCorridorMatch: FreehandCorridorChoiceMatch(
      networkSnapshotID: "preview.synthetic.snapshot-v1",
      decisionPointID: "preview.synthetic.decision.loop-gate",
      candidateChoiceIDs: [
        "preview.synthetic.choice.enter-loop",
        "preview.synthetic.choice.early-exit",
      ]
    )
  )
}

enum ParkedRouteEditorModelError: Error, Equatable, Sendable {
  case incompleteLocalizedPresentation(KaidoReleaseLocale)
}

@MainActor
final class ParkedRouteEditorModel: ObservableObject {
  @Published private(set) var snapshot: ExpertRouteEditorSnapshot
  @Published private(set) var compiledRoutePlan: RoutePlan?
  @Published private(set) var corridorResolution: ParkedCorridorResolutionSnapshot?
  @Published private(set) var lastErrorCode: String?

  let fixture: ParkedRouteEditorFixture
  let interaction: RouteEditorInteractionContext

  private var session: ExpertRouteEditorSession
  private var corridorResolutionSession: ParkedCorridorResolutionSession?
  private var nextSelectionSerial = 1
  private var nextLapDuplicationSerial = 1
  private var successfulEditCount = 0

  init(
    fixture: ParkedRouteEditorFixture = .synthetic,
    interaction: RouteEditorInteractionContext = .parked
  ) throws {
    try Self.validatePresentations(fixture)
    self.fixture = fixture
    self.interaction = interaction
    session = try ExpertRouteEditorSession(
      catalog: fixture.catalog,
      routePlanID: fixture.routePlanID,
      entranceFacilityID: fixture.entranceFacilityID,
      initialOccurrenceID: fixture.initialOccurrenceID,
      recoveryPolicy: .strict,
      interaction: interaction
    )
    snapshot = session.snapshot
    corridorResolution = nil
  }

  var canUndo: Bool {
    successfulEditCount > 0
  }

  var canCompile: Bool {
    (try? session.makeRoutePlan(interaction: interaction)) != nil
  }

  var canSubmitFreehandCorridor: Bool {
    interaction == .parked
      && snapshot.state == .editing
      && snapshot.currentDecisionPointID == fixture.freehandCorridorMatch.decisionPointID
      && corridorResolution == nil
  }

  func entranceTitle(for locale: KaidoReleaseLocale) -> String {
    presentation(for: locale).entranceTitle
  }

  func decisionTitle(for locale: KaidoReleaseLocale) -> String {
    guard let decisionPointID = snapshot.currentDecisionPointID else {
      return presentation(for: locale).completedRouteTitle
    }
    guard
      let title = presentation(for: locale).decisionTitles[decisionPointID]
    else {
      preconditionFailure(
        "Validated editor presentation lost decision \(decisionPointID)"
      )
    }
    return title
  }

  func title(
    for choice: ReviewedRouteEditorChoice,
    locale: KaidoReleaseLocale
  ) -> String {
    guard let title = presentation(for: locale).choiceTitles[choice.id] else {
      preconditionFailure(
        "Validated editor presentation lost choice title \(choice.id)"
      )
    }
    return title
  }

  func detail(
    for choice: ReviewedRouteEditorChoice,
    locale: KaidoReleaseLocale
  ) -> String {
    guard let detail = presentation(for: locale).choiceDetails[choice.id] else {
      preconditionFailure(
        "Validated editor presentation lost choice detail \(choice.id)"
      )
    }
    return detail
  }

  func select(choiceID: String) {
    let serial = nextSelectionSerial
    do {
      try session.select(
        choiceID: choiceID,
        movementOccurrenceID: "preview.synthetic.occurrence.movement.\(serial)",
        outgoingEdgeOccurrenceID: "preview.synthetic.occurrence.edge.\(serial)",
        interaction: interaction
      )
      nextSelectionSerial += 1
      successfulEditCount += 1
      corridorResolutionSession = nil
      corridorResolution = nil
      compiledRoutePlan = nil
      lastErrorCode = nil
      snapshot = session.snapshot
    } catch let error as ExpertRouteEditorError {
      lastErrorCode = error.code
    } catch {
      lastErrorCode = "UNKNOWN_EDITOR_ERROR"
    }
  }

  func submitFreehandCorridor() {
    do {
      let resolutionSession = try ParkedCorridorResolutionSession(
        editorSnapshot: snapshot,
        match: fixture.freehandCorridorMatch,
        interaction: interaction
      )
      corridorResolutionSession = resolutionSession
      corridorResolution = resolutionSession.snapshot
      lastErrorCode = nil
    } catch let error as ParkedCorridorResolutionError {
      corridorResolutionSession = nil
      corridorResolution = nil
      lastErrorCode = error.code
    } catch {
      corridorResolutionSession = nil
      corridorResolution = nil
      lastErrorCode = "UNKNOWN_CORRIDOR_ERROR"
    }
  }

  func resolveFreehandCorridor(choiceID: String) {
    guard var resolutionSession = corridorResolutionSession else {
      lastErrorCode = ParkedCorridorResolutionError.resolutionNotAllowed.code
      return
    }
    var editorSession = session
    let serial = nextSelectionSerial
    do {
      let selectedChoice = try resolutionSession.resolve(
        choiceID: choiceID,
        editorSnapshot: snapshot,
        interaction: interaction
      )
      try editorSession.select(
        choiceID: selectedChoice.id,
        movementOccurrenceID: "preview.synthetic.occurrence.movement.\(serial)",
        outgoingEdgeOccurrenceID: "preview.synthetic.occurrence.edge.\(serial)",
        interaction: interaction
      )
      session = editorSession
      corridorResolutionSession = resolutionSession
      corridorResolution = resolutionSession.snapshot
      nextSelectionSerial += 1
      successfulEditCount += 1
      compiledRoutePlan = nil
      lastErrorCode = nil
      snapshot = editorSession.snapshot
    } catch let error as ParkedCorridorResolutionError {
      corridorResolution = resolutionSession.snapshot
      lastErrorCode = error.code
    } catch let error as ExpertRouteEditorError {
      corridorResolution = resolutionSession.snapshot
      lastErrorCode = error.code
    } catch {
      corridorResolution = resolutionSession.snapshot
      lastErrorCode = "UNKNOWN_CORRIDOR_ERROR"
    }
  }

  func duplicate(lapCandidateID: String) {
    guard
      let candidate = snapshot.availableLapCandidates.first(where: {
        $0.id == lapCandidateID
      })
    else {
      lastErrorCode = ExpertRouteEditorError.illegalLapCandidate.code
      return
    }
    let serial = nextLapDuplicationSerial
    let newOccurrenceIDs = candidate.sourceOccurrenceIDs.indices.map { offset in
      "preview.synthetic.occurrence.lap-copy.\(serial).\(offset + 1)"
    }
    do {
      try session.duplicateLap(
        candidateID: candidate.id,
        newOccurrenceIDs: newOccurrenceIDs,
        interaction: interaction
      )
      nextLapDuplicationSerial += 1
      successfulEditCount += 1
      corridorResolutionSession = nil
      corridorResolution = nil
      compiledRoutePlan = nil
      lastErrorCode = nil
      snapshot = session.snapshot
    } catch let error as ExpertRouteEditorError {
      lastErrorCode = error.code
    } catch {
      lastErrorCode = "UNKNOWN_EDITOR_ERROR"
    }
  }

  func undo() {
    do {
      try session.undo(interaction: interaction)
      successfulEditCount -= 1
      corridorResolutionSession = nil
      corridorResolution = nil
      compiledRoutePlan = nil
      lastErrorCode = nil
      snapshot = session.snapshot
    } catch let error as ExpertRouteEditorError {
      lastErrorCode = error.code
    } catch {
      lastErrorCode = "UNKNOWN_EDITOR_ERROR"
    }
  }

  func compile() {
    do {
      let authoredRoutePlan = try session.makeRoutePlan(interaction: interaction)
      compiledRoutePlan = try RouteDistanceResolver.resolve(
        routePlan: authoredRoutePlan,
        catalog: fixture.distanceCatalog
      )
      lastErrorCode = nil
      snapshot = session.snapshot
    } catch let error as ExpertRouteEditorError {
      lastErrorCode = error.code
    } catch let error as RouteDistanceResolutionError {
      lastErrorCode = error.code
    } catch {
      lastErrorCode = "UNKNOWN_EDITOR_ERROR"
    }
  }

  private func presentation(
    for locale: KaidoReleaseLocale
  ) -> ParkedRouteEditorFixturePresentation {
    guard let presentation = fixture.presentations[locale] else {
      preconditionFailure(
        "Validated editor presentation lost locale \(locale.rawValue)"
      )
    }
    return presentation
  }

  private static func validatePresentations(
    _ fixture: ParkedRouteEditorFixture
  ) throws {
    let decisionIDs = Set(fixture.catalog.decisionPoints.map(\.id))
    let choiceIDs = Set(
      fixture.catalog.decisionPoints.flatMap { point in
        point.choices.map(\.id)
      }
    )
    for locale in KaidoReleaseLocale.allCases {
      guard
        let presentation = fixture.presentations[locale],
        !presentation.entranceTitle.trimmingCharacters(
          in: .whitespacesAndNewlines
        ).isEmpty,
        !presentation.completedRouteTitle.trimmingCharacters(
          in: .whitespacesAndNewlines
        ).isEmpty,
        Set(presentation.decisionTitles.keys) == decisionIDs,
        Set(presentation.choiceTitles.keys) == choiceIDs,
        Set(presentation.choiceDetails.keys) == choiceIDs,
        presentation.decisionTitles.values.allSatisfy({
          !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }),
        presentation.choiceTitles.values.allSatisfy({
          !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }),
        presentation.choiceDetails.values.allSatisfy({
          !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })
      else {
        throw ParkedRouteEditorModelError.incompleteLocalizedPresentation(
          locale
        )
      }
    }
  }
}
