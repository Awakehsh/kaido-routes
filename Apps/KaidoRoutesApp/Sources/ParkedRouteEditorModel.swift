import Combine
import KaidoDomain
import KaidoRouting

struct ParkedRouteEditorFixture: Sendable {
  let catalog: ReviewedRouteEditorCatalog
  let distanceCatalog: ReviewedRouteDistanceCatalog
  let entranceFacilityID: String
  let entranceTitle: String
  let routePlanID: String
  let initialOccurrenceID: String
  let choiceTitles: [String: String]
  let choiceDetails: [String: String]
  let decisionTitles: [String: String]

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
    entranceTitle: "演示入口 · 东向",
    routePlanID: "preview.synthetic.route-plan",
    initialOccurrenceID: "preview.synthetic.occurrence.entry.0",
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
  )
}

@MainActor
final class ParkedRouteEditorModel: ObservableObject {
  @Published private(set) var snapshot: ExpertRouteEditorSnapshot
  @Published private(set) var compiledRoutePlan: RoutePlan?
  @Published private(set) var lastErrorCode: String?

  let fixture: ParkedRouteEditorFixture
  let interaction: RouteEditorInteractionContext

  private var session: ExpertRouteEditorSession
  private var nextSelectionSerial = 1
  private var nextLapDuplicationSerial = 1
  private var successfulEditCount = 0

  init(
    fixture: ParkedRouteEditorFixture = .synthetic,
    interaction: RouteEditorInteractionContext = .parked
  ) throws {
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
  }

  var canUndo: Bool {
    successfulEditCount > 0
  }

  var canCompile: Bool {
    (try? session.makeRoutePlan(interaction: interaction)) != nil
  }

  var decisionTitle: String {
    guard let decisionPointID = snapshot.currentDecisionPointID else {
      return "路线已完成"
    }
    return fixture.decisionTitles[decisionPointID] ?? decisionPointID
  }

  func title(for choice: ReviewedRouteEditorChoice) -> String {
    fixture.choiceTitles[choice.id] ?? choice.id
  }

  func detail(for choice: ReviewedRouteEditorChoice) -> String {
    fixture.choiceDetails[choice.id] ?? choice.id
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
      compiledRoutePlan = nil
      lastErrorCode = nil
      snapshot = session.snapshot
    } catch let error as ExpertRouteEditorError {
      lastErrorCode = error.code
    } catch {
      lastErrorCode = "UNKNOWN_EDITOR_ERROR"
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
}
