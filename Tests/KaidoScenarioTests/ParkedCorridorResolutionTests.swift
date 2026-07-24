import KaidoDomain
import KaidoRouting
import Testing

@Test("Ambiguous freehand corridor requires an explicit parked choice")
func ambiguousCorridorRequiresExplicitResolution() throws {
  var editor = try corridorEditorSession()
  let editorBeforeResolution = editor.snapshot
  var resolution = try ParkedCorridorResolutionSession(
    editorSnapshot: editor.snapshot,
    match: FreehandCorridorChoiceMatch(
      networkSnapshotID: editor.snapshot.networkSnapshotID,
      decisionPointID: "test.decision.corridor",
      candidateChoiceIDs: [
        "test.choice.left",
        "test.choice.right",
      ]
    ),
    interaction: .parked
  )

  #expect(resolution.snapshot.state == .resolutionRequired)
  #expect(
    resolution.snapshot.candidateChoices.map(\.id) == [
      "test.choice.left",
      "test.choice.right",
    ])
  #expect(editor.snapshot == editorBeforeResolution)

  let selected = try resolution.resolve(
    choiceID: "test.choice.left",
    editorSnapshot: editor.snapshot,
    interaction: .parked
  )
  #expect(resolution.snapshot.state == .resolved)
  #expect(resolution.snapshot.selectedChoiceID == selected.id)
  #expect(editor.snapshot == editorBeforeResolution)

  try editor.select(
    choiceID: selected.id,
    movementOccurrenceID: "test.occurrence.left-movement",
    outgoingEdgeOccurrenceID: "test.occurrence.left-edge",
    interaction: .parked
  )
  #expect(
    editor.snapshot.occurrences.map(\.id) == [
      "test.occurrence.entry",
      "test.occurrence.left-movement",
      "test.occurrence.left-edge",
    ])
}

@Test("Corridor candidates must belong to the exact current editor cursor")
func corridorCandidatesMustMatchCurrentCursor() throws {
  var editor = try corridorEditorSession()

  #expect(throws: ParkedCorridorResolutionError.interactionLocked) {
    try ParkedCorridorResolutionSession(
      editorSnapshot: editor.snapshot,
      match: validCorridorMatch(),
      interaction: .moving
    )
  }
  #expect(throws: ParkedCorridorResolutionError.identityMismatch) {
    try ParkedCorridorResolutionSession(
      editorSnapshot: editor.snapshot,
      match: FreehandCorridorChoiceMatch(
        networkSnapshotID: "test.snapshot.other",
        decisionPointID: "test.decision.corridor",
        candidateChoiceIDs: ["test.choice.left"]
      ),
      interaction: .parked
    )
  }
  #expect(throws: ParkedCorridorResolutionError.invalidCandidates) {
    try ParkedCorridorResolutionSession(
      editorSnapshot: editor.snapshot,
      match: FreehandCorridorChoiceMatch(
        networkSnapshotID: editor.snapshot.networkSnapshotID,
        decisionPointID: "test.decision.corridor",
        candidateChoiceIDs: ["test.choice.future"]
      ),
      interaction: .parked
    )
  }

  var resolution = try ParkedCorridorResolutionSession(
    editorSnapshot: editor.snapshot,
    match: validCorridorMatch(),
    interaction: .parked
  )
  #expect(throws: ParkedCorridorResolutionError.illegalCandidate) {
    try resolution.resolve(
      choiceID: "test.choice.future",
      editorSnapshot: editor.snapshot,
      interaction: .parked
    )
  }
  #expect(resolution.snapshot.state == .resolutionRequired)

  try editor.select(
    choiceID: "test.choice.left",
    movementOccurrenceID: "test.occurrence.left-movement",
    outgoingEdgeOccurrenceID: "test.occurrence.left-edge",
    interaction: .parked
  )
  #expect(throws: ParkedCorridorResolutionError.staleEditorCursor) {
    try resolution.resolve(
      choiceID: "test.choice.right",
      editorSnapshot: editor.snapshot,
      interaction: .parked
    )
  }
}

@Test("Zero and one corridor candidates never author a route directly")
func unmatchedAndExactCorridorsStillRequireUserAction() throws {
  let editor = try corridorEditorSession()
  let empty = try ParkedCorridorResolutionSession(
    editorSnapshot: editor.snapshot,
    match: FreehandCorridorChoiceMatch(
      networkSnapshotID: editor.snapshot.networkSnapshotID,
      decisionPointID: "test.decision.corridor",
      candidateChoiceIDs: []
    ),
    interaction: .parked
  )
  #expect(empty.snapshot.state == .unmatched)
  #expect(empty.snapshot.candidateChoices.isEmpty)

  var exact = try ParkedCorridorResolutionSession(
    editorSnapshot: editor.snapshot,
    match: FreehandCorridorChoiceMatch(
      networkSnapshotID: editor.snapshot.networkSnapshotID,
      decisionPointID: "test.decision.corridor",
      candidateChoiceIDs: ["test.choice.left"]
    ),
    interaction: .parked
  )
  #expect(exact.snapshot.state == .confirmationRequired)
  #expect(editor.snapshot.occurrences.map(\.id) == ["test.occurrence.entry"])
  #expect(throws: ParkedCorridorResolutionError.interactionLocked) {
    try exact.resolve(
      choiceID: "test.choice.left",
      editorSnapshot: editor.snapshot,
      interaction: .moving
    )
  }
  #expect(exact.snapshot.state == .confirmationRequired)
}

private func validCorridorMatch() -> FreehandCorridorChoiceMatch {
  FreehandCorridorChoiceMatch(
    networkSnapshotID: "test.snapshot.corridor",
    decisionPointID: "test.decision.corridor",
    candidateChoiceIDs: [
      "test.choice.left",
      "test.choice.right",
    ]
  )
}

private func corridorEditorSession() throws -> ExpertRouteEditorSession {
  let leftChoice = ReviewedRouteEditorChoice(
    id: "test.choice.left",
    movementID: "test.movement.left",
    movementTollDomainID: "test.toll.shuto",
    outgoingEdgeID: "test.edge.left",
    outgoingEdgeTollDomainID: "test.toll.shuto",
    destination: .decisionPoint("test.decision.exit")
  )
  let rightChoice = ReviewedRouteEditorChoice(
    id: "test.choice.right",
    movementID: "test.movement.right",
    movementTollDomainID: "test.toll.shuto",
    outgoingEdgeID: "test.edge.right",
    outgoingEdgeTollDomainID: "test.toll.shuto",
    destination: .decisionPoint("test.decision.exit")
  )
  let exitChoice = ReviewedRouteEditorChoice(
    id: "test.choice.exit",
    movementID: "test.movement.exit",
    movementTollDomainID: "test.toll.shuto",
    outgoingEdgeID: "test.edge.exit",
    outgoingEdgeTollDomainID: "test.toll.shuto",
    destination: .exitFacility("test.exit.directional")
  )
  return try ExpertRouteEditorSession(
    catalog: ReviewedRouteEditorCatalog(
      networkSnapshotID: "test.snapshot.corridor",
      entrances: [
        ReviewedRouteEditorEntrance(
          facilityID: "test.entrance.directional",
          initialEdgeID: "test.edge.entry",
          initialEdgeTollDomainID: "test.toll.shuto",
          firstDecisionPointID: "test.decision.corridor"
        )
      ],
      decisionPoints: [
        ReviewedRouteEditorDecisionPoint(
          id: "test.decision.corridor",
          incomingApproachID: "test.approach.corridor",
          junctionComplexID: "test.junction.corridor",
          choices: [leftChoice, rightChoice]
        ),
        ReviewedRouteEditorDecisionPoint(
          id: "test.decision.exit",
          incomingApproachID: "test.approach.exit",
          junctionComplexID: "test.junction.exit",
          choices: [exitChoice]
        ),
      ]
    ),
    routePlanID: "test.plan.corridor",
    entranceFacilityID: "test.entrance.directional",
    initialOccurrenceID: "test.occurrence.entry",
    recoveryPolicy: .strict,
    interaction: .parked
  )
}
