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

@Test("Expert editor duplicates only an authored reviewed closed lap with fresh values")
func expertEditorDuplicatesReviewedLap() throws {
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
  let template = ReviewedRouteEditorLapTemplate(
    id: "test.lap-template.loop",
    startDecisionPointID: "test.decision.loop",
    choiceIDs: [loopChoice.id]
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
    ],
    lapTemplates: [template]
  )
  var session = try ExpertRouteEditorSession(
    catalog: catalog,
    routePlanID: "test.plan.loop",
    entranceFacilityID: "test.entrance.loop",
    initialOccurrenceID: "test.occurrence.loop-1-edge",
    recoveryPolicy: .strict,
    interaction: .parked
  )

  #expect(session.snapshot.availableLapCandidates.isEmpty)
  try session.select(
    choiceID: loopChoice.id,
    movementOccurrenceID: "test.occurrence.loop-1-movement",
    outgoingEdgeOccurrenceID: "test.occurrence.loop-2-edge",
    interaction: .parked
  )
  let candidate = try #require(session.snapshot.availableLapCandidates.first)
  #expect(candidate.reviewedTemplateID == template.id)
  #expect(
    candidate.sourceOccurrenceIDs == [
      "test.occurrence.loop-1-movement",
      "test.occurrence.loop-2-edge",
    ])

  let beforeMovingAttempt = session.snapshot
  #expect(throws: ExpertRouteEditorError.interactionLocked) {
    try session.duplicateLap(
      candidateID: candidate.id,
      newOccurrenceIDs: [
        "test.occurrence.loop-2-movement",
        "test.occurrence.loop-3-edge",
      ],
      interaction: .moving
    )
  }
  #expect(session.snapshot == beforeMovingAttempt)
  #expect(throws: ExpertRouteEditorError.invalidLapOccurrenceCount) {
    try session.duplicateLap(
      candidateID: candidate.id,
      newOccurrenceIDs: ["test.occurrence.wrong-count"],
      interaction: .parked
    )
  }
  #expect(throws: ExpertRouteEditorError.duplicateOccurrenceID) {
    try session.duplicateLap(
      candidateID: candidate.id,
      newOccurrenceIDs: [
        "test.occurrence.loop-1-movement",
        "test.occurrence.collision",
      ],
      interaction: .parked
    )
  }

  try session.duplicateLap(
    candidateID: candidate.id,
    newOccurrenceIDs: [
      "test.occurrence.loop-2-movement",
      "test.occurrence.loop-3-edge",
    ],
    interaction: .parked
  )

  #expect(session.snapshot.currentDecisionPointID == "test.decision.loop")
  #expect(
    session.snapshot.occurrences.map(\.id) == [
      "test.occurrence.loop-1-edge",
      "test.occurrence.loop-1-movement",
      "test.occurrence.loop-2-edge",
      "test.occurrence.loop-2-movement",
      "test.occurrence.loop-3-edge",
    ])
  #expect(
    session.snapshot.occurrences.map(\.entityID) == [
      "test.edge.loop",
      "test.movement.loop",
      "test.edge.loop",
      "test.movement.loop",
      "test.edge.loop",
    ])
  #expect(session.snapshot.occurrences.map(\.index) == [0, 1, 2, 3, 4])
  #expect(session.snapshot.availableLapCandidates.count == 2)

  try session.undo(interaction: .parked)
  #expect(session.snapshot == beforeMovingAttempt)

  try session.duplicateLap(
    candidateID: candidate.id,
    newOccurrenceIDs: [
      "test.occurrence.loop-3-movement",
      "test.occurrence.loop-4-edge",
    ],
    interaction: .parked
  )
  try session.select(
    choiceID: exitChoice.id,
    movementOccurrenceID: "test.occurrence.exit-movement",
    outgoingEdgeOccurrenceID: "test.occurrence.exit-edge",
    interaction: .parked
  )
  let routePlan = try session.makeRoutePlan(interaction: .parked)
  #expect(routePlan.occurrences.map(\.index) == Array(0..<7))
  #expect(Set(routePlan.occurrences.map(\.id)).count == 7)
}

@Test("A multi-decision lap candidate requires the whole reviewed closed sequence")
func expertEditorMatchesWholeReviewedLapSequence() throws {
  let firstChoice = ReviewedRouteEditorChoice(
    id: "test.choice.a-to-b",
    movementID: "test.movement.a-to-b",
    movementTollDomainID: "test.toll.shuto",
    outgoingEdgeID: "test.edge.b",
    outgoingEdgeTollDomainID: "test.toll.shuto",
    destination: .decisionPoint("test.decision.b")
  )
  let closeChoice = ReviewedRouteEditorChoice(
    id: "test.choice.b-to-a",
    movementID: "test.movement.b-to-a",
    movementTollDomainID: "test.toll.shuto",
    outgoingEdgeID: "test.edge.a",
    outgoingEdgeTollDomainID: "test.toll.shuto",
    destination: .decisionPoint("test.decision.a")
  )
  let exitChoice = ReviewedRouteEditorChoice(
    id: "test.choice.exit-a",
    movementID: "test.movement.exit-a",
    movementTollDomainID: "test.toll.shuto",
    outgoingEdgeID: "test.edge.exit-a",
    outgoingEdgeTollDomainID: "test.toll.shuto",
    destination: .exitFacility("test.exit.a")
  )
  let catalog = ReviewedRouteEditorCatalog(
    networkSnapshotID: "test.snapshot.multi-lap",
    entrances: [
      ReviewedRouteEditorEntrance(
        facilityID: "test.entrance.a",
        initialEdgeID: "test.edge.a",
        initialEdgeTollDomainID: "test.toll.shuto",
        firstDecisionPointID: "test.decision.a"
      )
    ],
    decisionPoints: [
      ReviewedRouteEditorDecisionPoint(
        id: "test.decision.a",
        incomingApproachID: "test.approach.a",
        junctionComplexID: "test.junction.a",
        choices: [firstChoice, exitChoice]
      ),
      ReviewedRouteEditorDecisionPoint(
        id: "test.decision.b",
        incomingApproachID: "test.approach.b",
        junctionComplexID: "test.junction.b",
        choices: [closeChoice]
      ),
    ],
    lapTemplates: [
      ReviewedRouteEditorLapTemplate(
        id: "test.lap-template.a-b-a",
        startDecisionPointID: "test.decision.a",
        choiceIDs: [firstChoice.id, closeChoice.id]
      )
    ]
  )
  var session = try ExpertRouteEditorSession(
    catalog: catalog,
    routePlanID: "test.plan.multi-lap",
    entranceFacilityID: "test.entrance.a",
    initialOccurrenceID: "test.occurrence.edge-a.1",
    recoveryPolicy: .strict,
    interaction: .parked
  )

  try session.select(
    choiceID: firstChoice.id,
    movementOccurrenceID: "test.occurrence.a-to-b.1",
    outgoingEdgeOccurrenceID: "test.occurrence.edge-b.1",
    interaction: .parked
  )
  #expect(session.snapshot.currentDecisionPointID == "test.decision.b")
  #expect(session.snapshot.availableLapCandidates.isEmpty)

  try session.select(
    choiceID: closeChoice.id,
    movementOccurrenceID: "test.occurrence.b-to-a.1",
    outgoingEdgeOccurrenceID: "test.occurrence.edge-a.2",
    interaction: .parked
  )
  let candidate = try #require(session.snapshot.availableLapCandidates.first)
  #expect(
    candidate.sourceOccurrenceIDs == [
      "test.occurrence.a-to-b.1",
      "test.occurrence.edge-b.1",
      "test.occurrence.b-to-a.1",
      "test.occurrence.edge-a.2",
    ])

  try session.duplicateLap(
    candidateID: candidate.id,
    newOccurrenceIDs: [
      "test.occurrence.a-to-b.2",
      "test.occurrence.edge-b.2",
      "test.occurrence.b-to-a.2",
      "test.occurrence.edge-a.3",
    ],
    interaction: .parked
  )
  #expect(session.snapshot.occurrences.map(\.index) == Array(0..<9))
  #expect(session.snapshot.availableLapCandidates.count == 2)

  try session.undo(interaction: .parked)
  #expect(session.snapshot.currentDecisionPointID == "test.decision.a")
  #expect(session.snapshot.occurrences.map(\.index) == Array(0..<5))
  #expect(session.snapshot.availableLapCandidates == [candidate])
}

@Test("Editor catalog rejects a lap template that exits or does not close")
func editorCatalogRejectsUnclosedLapTemplate() {
  let base = editorCatalog()
  let invalid = ReviewedRouteEditorCatalog(
    networkSnapshotID: base.networkSnapshotID,
    entrances: base.entrances,
    decisionPoints: base.decisionPoints,
    lapTemplates: [
      ReviewedRouteEditorLapTemplate(
        id: "test.lap-template.not-closed",
        startDecisionPointID: "test.decision.first",
        choiceIDs: ["test.choice.continue"]
      ),
      ReviewedRouteEditorLapTemplate(
        id: "test.lap-template.exits",
        startDecisionPointID: "test.decision.exit",
        choiceIDs: ["test.choice.exit"]
      ),
    ]
  )

  #expect(
    invalid.validationIssues.filter {
      $0 == "editor lap template does not form a reviewed closed sequence"
    }.count == 1
  )
  #expect(throws: ExpertRouteEditorError.invalidCatalog(invalid.validationIssues)) {
    try ExpertRouteEditorSession(
      catalog: invalid,
      routePlanID: "test.plan",
      entranceFacilityID: "test.entrance.directional",
      initialOccurrenceID: "test.occurrence",
      recoveryPolicy: .strict,
      interaction: .parked
    )
  }
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
