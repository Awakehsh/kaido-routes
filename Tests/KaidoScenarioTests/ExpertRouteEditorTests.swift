import KaidoDomain
import KaidoRouting
import Testing

@Test("Expert editor exposes only reviewed choices and compiles the selected exit")
func expertEditorBuildsExactOccurrencePlan() throws {
  var session = try ExpertRouteEditorSession(
    catalog: editorCatalog(),
    routePlanID: "test.plan.editor",
    entranceFacilityID: "test.entrance.directional",
    initialOccurrenceID: "test.occurrence.entry-edge",
    recoveryPolicy: .safeRejoin,
    interaction: .parked
  )

  #expect(session.snapshot.currentDecisionPointID == "test.decision.first")
  #expect(session.snapshot.incomingApproachID == "test.approach.first")
  #expect(session.snapshot.availableChoices.map(\.id) == ["test.choice.continue"])

  #expect(throws: ExpertRouteEditorError.illegalChoice) {
    try session.select(
      choiceID: "test.choice.unrelated",
      movementOccurrenceID: "unused-movement",
      outgoingEdgeOccurrenceID: "unused-edge",
      interaction: .parked
    )
  }
  #expect(session.snapshot.occurrences.count == 1)

  try session.select(
    choiceID: "test.choice.continue",
    movementOccurrenceID: "test.occurrence.movement",
    outgoingEdgeOccurrenceID: "test.occurrence.next-edge",
    interaction: .parked
  )
  #expect(session.snapshot.currentDecisionPointID == "test.decision.exit")
  #expect(session.snapshot.availableChoices.map(\.id) == ["test.choice.exit"])

  try session.select(
    choiceID: "test.choice.exit",
    movementOccurrenceID: "test.occurrence.exit-movement",
    outgoingEdgeOccurrenceID: "test.occurrence.exit-edge",
    interaction: .parked
  )
  let routePlan = try session.makeRoutePlan(interaction: .parked)

  #expect(session.state == .finished)
  #expect(routePlan.entryFacilityID == "test.entrance.directional")
  #expect(routePlan.exitFacilityID == "test.exit.directional")
  #expect(routePlan.occurrences.map(\.index) == [0, 1, 2, 3, 4])
  #expect(
    routePlan.occurrences.map(\.entityID) == [
      "test.edge.entry",
      "test.movement.continue",
      "test.edge.next",
      "test.movement.exit",
      "test.edge.exit-ramp",
    ])
}

@Test("Expert editor undo is parked-only and restores the exact prior decision")
func expertEditorUndoRestoresPriorDecision() throws {
  var session = try ExpertRouteEditorSession(
    catalog: editorCatalog(),
    routePlanID: "test.plan.editor",
    entranceFacilityID: "test.entrance.directional",
    initialOccurrenceID: "test.occurrence.entry-edge",
    recoveryPolicy: .strict,
    interaction: .parked
  )

  #expect(throws: ExpertRouteEditorError.interactionLocked) {
    try session.select(
      choiceID: "test.choice.continue",
      movementOccurrenceID: "test.occurrence.movement",
      outgoingEdgeOccurrenceID: "test.occurrence.next-edge",
      interaction: .moving
    )
  }
  try session.select(
    choiceID: "test.choice.continue",
    movementOccurrenceID: "test.occurrence.movement",
    outgoingEdgeOccurrenceID: "test.occurrence.next-edge",
    interaction: .parked
  )
  try session.undo(interaction: .parked)

  #expect(session.snapshot.currentDecisionPointID == "test.decision.first")
  #expect(session.snapshot.occurrences.map(\.id) == ["test.occurrence.entry-edge"])
  #expect(session.snapshot.availableChoices.map(\.id) == ["test.choice.continue"])
  #expect(throws: ExpertRouteEditorError.routeIncomplete) {
    try session.makeRoutePlan(interaction: .parked)
  }
}

@Test("Reviewed editor catalogs may contain cycles without aliasing occurrences")
func expertEditorSupportsReviewedCycles() throws {
  let loopChoice = ReviewedRouteEditorChoice(
    id: "test.choice.loop",
    movementID: "test.movement.loop",
    movementTollDomainID: "test.toll.shuto",
    outgoingEdgeID: "test.edge.loop",
    outgoingEdgeTollDomainID: "test.toll.shuto",
    destination: .decisionPoint("test.decision.loop")
  )
  let exitChoice = ReviewedRouteEditorChoice(
    id: "test.choice.loop-exit",
    movementID: "test.movement.loop-exit",
    movementTollDomainID: "test.toll.shuto",
    outgoingEdgeID: "test.edge.loop-exit",
    outgoingEdgeTollDomainID: "test.toll.shuto",
    destination: .exitFacility("test.exit.loop")
  )
  let catalog = ReviewedRouteEditorCatalog(
    networkSnapshotID: "test.snapshot.loop",
    entrances: [
      ReviewedRouteEditorEntrance(
        facilityID: "test.entrance.loop",
        initialEdgeID: "test.edge.loop",
        initialEdgeTollDomainID: "test.toll.shuto",
        firstDecisionPointID: "test.decision.loop"
      )
    ],
    decisionPoints: [
      ReviewedRouteEditorDecisionPoint(
        id: "test.decision.loop",
        incomingApproachID: "test.approach.loop",
        junctionComplexID: "test.junction.loop",
        choices: [loopChoice, exitChoice]
      )
    ]
  )
  var session = try ExpertRouteEditorSession(
    catalog: catalog,
    routePlanID: "test.plan.loop",
    entranceFacilityID: "test.entrance.loop",
    initialOccurrenceID: "test.occurrence.loop-1-edge",
    recoveryPolicy: .strict,
    interaction: .parked
  )

  try session.select(
    choiceID: loopChoice.id,
    movementOccurrenceID: "test.occurrence.loop-1-movement",
    outgoingEdgeOccurrenceID: "test.occurrence.loop-2-edge",
    interaction: .parked
  )
  try session.select(
    choiceID: loopChoice.id,
    movementOccurrenceID: "test.occurrence.loop-2-movement",
    outgoingEdgeOccurrenceID: "test.occurrence.loop-3-edge",
    interaction: .parked
  )

  #expect(session.snapshot.currentDecisionPointID == "test.decision.loop")
  #expect(session.snapshot.occurrences.map(\.index) == [0, 1, 2, 3, 4])
  #expect(Set(session.snapshot.occurrences.map(\.id)).count == 5)
  #expect(
    session.snapshot.occurrences.map(\.entityID).count(where: { $0 == "test.edge.loop" }) == 3)
}

@Test("Malformed editor catalogs fail closed without traversing duplicate identities")
func malformedEditorCatalogFailsClosed() {
  let loopChoice = ReviewedRouteEditorChoice(
    id: "test.choice.loop",
    movementID: "test.movement.loop",
    movementTollDomainID: "test.toll.shuto",
    outgoingEdgeID: "test.edge.loop",
    outgoingEdgeTollDomainID: "test.toll.shuto",
    destination: .decisionPoint("test.decision.duplicate")
  )
  let duplicateDecision = ReviewedRouteEditorDecisionPoint(
    id: "test.decision.duplicate",
    incomingApproachID: "test.approach",
    junctionComplexID: "test.junction",
    choices: [loopChoice]
  )
  let catalog = ReviewedRouteEditorCatalog(
    networkSnapshotID: "test.snapshot.invalid",
    entrances: [
      ReviewedRouteEditorEntrance(
        facilityID: "test.entrance",
        initialEdgeID: "test.edge",
        initialEdgeTollDomainID: "test.toll.shuto",
        firstDecisionPointID: duplicateDecision.id
      )
    ],
    decisionPoints: [duplicateDecision, duplicateDecision]
  )

  #expect(catalog.validationIssues.contains("editor decision point IDs are not unique"))
  #expect(catalog.validationIssues.contains("editor entrance has no reachable exit"))
  #expect(throws: ExpertRouteEditorError.invalidCatalog(catalog.validationIssues)) {
    try ExpertRouteEditorSession(
      catalog: catalog,
      routePlanID: "test.plan",
      entranceFacilityID: "test.entrance",
      initialOccurrenceID: "test.occurrence",
      recoveryPolicy: .strict,
      interaction: .parked
    )
  }
}

private func editorCatalog() -> ReviewedRouteEditorCatalog {
  ReviewedRouteEditorCatalog(
    networkSnapshotID: "test.snapshot.editor",
    entrances: [
      ReviewedRouteEditorEntrance(
        facilityID: "test.entrance.directional",
        initialEdgeID: "test.edge.entry",
        initialEdgeTollDomainID: "test.toll.shuto",
        firstDecisionPointID: "test.decision.first"
      )
    ],
    decisionPoints: [
      ReviewedRouteEditorDecisionPoint(
        id: "test.decision.first",
        incomingApproachID: "test.approach.first",
        junctionComplexID: "test.junction.first",
        choices: [
          ReviewedRouteEditorChoice(
            id: "test.choice.continue",
            movementID: "test.movement.continue",
            movementTollDomainID: "test.toll.shuto",
            outgoingEdgeID: "test.edge.next",
            outgoingEdgeTollDomainID: "test.toll.shuto",
            destination: .decisionPoint("test.decision.exit")
          )
        ]
      ),
      ReviewedRouteEditorDecisionPoint(
        id: "test.decision.exit",
        incomingApproachID: "test.approach.exit",
        junctionComplexID: "test.junction.exit",
        choices: [
          ReviewedRouteEditorChoice(
            id: "test.choice.exit",
            movementID: "test.movement.exit",
            movementTollDomainID: "test.toll.shuto",
            outgoingEdgeID: "test.edge.exit-ramp",
            outgoingEdgeTollDomainID: "test.toll.shuto",
            destination: .exitFacility("test.exit.directional")
          )
        ]
      ),
    ]
  )
}
