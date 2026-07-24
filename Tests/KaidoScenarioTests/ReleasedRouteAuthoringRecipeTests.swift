import KaidoDomain
import KaidoRouting
import Testing

@Test("Released authoring preserves repeated occurrences and restores reviewed distance")
func releasedAuthoringReplaysExactOccurrencePlan() throws {
  let fixture = releasedAuthoringFixture()
  let recipe = try ReleasedRouteAuthoringRecipe(
    routePlan: fixture.routePlan,
    editorCatalog: fixture.catalog
  )

  #expect(
    recipe.steps.map(\.choiceID) == [
      "test.choice.loop",
      "test.choice.loop",
      "test.choice.exit",
    ])
  #expect(
    recipe.steps.map(\.movementOccurrenceID) == [
      "test.occurrence.loop-movement-1",
      "test.occurrence.loop-movement-2",
      "test.occurrence.exit-movement",
    ])

  var session = try recipe.makeSession(interaction: .parked)
  for step in recipe.steps {
    #expect(session.snapshot.currentDecisionPointID == step.decisionPointID)
    try session.select(
      choiceID: step.choiceID,
      movementOccurrenceID: step.movementOccurrenceID,
      outgoingEdgeOccurrenceID: step.outgoingEdgeOccurrenceID,
      interaction: .parked
    )
  }

  let compiled = try recipe.compile(session: session, interaction: .parked)
  #expect(compiled == fixture.routePlan)
  #expect(compiled.actualDistanceKM == 12.4)
  #expect(Set(compiled.occurrences.map(\.id)).count == 7)
  #expect(
    compiled.occurrences.filter { $0.entityID == "test.edge.loop" }.map(\.id)
      == [
        "test.occurrence.entry",
        "test.occurrence.loop-edge-1",
        "test.occurrence.loop-edge-2",
      ])
}

@Test("Released authoring session remains parked-only")
func releasedAuthoringSessionRejectsMovingInteraction() throws {
  let fixture = releasedAuthoringFixture()
  let recipe = try ReleasedRouteAuthoringRecipe(
    routePlan: fixture.routePlan,
    editorCatalog: fixture.catalog
  )

  #expect(throws: ExpertRouteEditorError.interactionLocked) {
    try recipe.makeSession(interaction: .moving)
  }
}

@Test("Released authoring rejects snapshot and entrance occurrence drift")
func releasedAuthoringRejectsReleaseIdentityDrift() {
  let fixture = releasedAuthoringFixture()
  let snapshotDrift = RoutePlan(
    id: fixture.routePlan.id,
    networkSnapshotID: "test.snapshot.other",
    entryFacilityID: fixture.routePlan.entryFacilityID,
    exitFacilityID: fixture.routePlan.exitFacilityID,
    recoveryPolicy: fixture.routePlan.recoveryPolicy,
    occurrences: fixture.routePlan.occurrences
  )
  #expect(throws: ReleasedRouteAuthoringError.networkSnapshotMismatch) {
    try ReleasedRouteAuthoringRecipe(
      routePlan: snapshotDrift,
      editorCatalog: fixture.catalog
    )
  }

  var entranceDriftOccurrences = fixture.routePlan.occurrences
  entranceDriftOccurrences[0] = RouteOccurrence(
    id: entranceDriftOccurrences[0].id,
    index: 0,
    kind: .edge,
    entityID: entranceDriftOccurrences[0].entityID,
    tollDomainID: "test.toll.other"
  )
  let entranceDrift = replacingOccurrences(
    in: fixture.routePlan,
    with: entranceDriftOccurrences
  )
  #expect(throws: ReleasedRouteAuthoringError.entranceOccurrenceMismatch) {
    try ReleasedRouteAuthoringRecipe(
      routePlan: entranceDrift,
      editorCatalog: fixture.catalog
    )
  }
}

@Test("Released authoring rejects unsupported and unavailable occurrence steps")
func releasedAuthoringRejectsUnexpressibleRouteShape() {
  let fixture = releasedAuthoringFixture()
  var optionalOccurrences = fixture.routePlan.occurrences
  let movement = optionalOccurrences[1]
  optionalOccurrences[1] = RouteOccurrence(
    id: movement.id,
    index: movement.index,
    kind: movement.kind,
    entityID: movement.entityID,
    tollDomainID: movement.tollDomainID,
    isOptional: true
  )
  #expect(
    throws: ReleasedRouteAuthoringError.unsupportedOccurrenceSequence(
      movement.id
    )
  ) {
    try ReleasedRouteAuthoringRecipe(
      routePlan: replacingOccurrences(
        in: fixture.routePlan,
        with: optionalOccurrences
      ),
      editorCatalog: fixture.catalog
    )
  }

  var unavailableOccurrences = fixture.routePlan.occurrences
  let outgoingEdge = unavailableOccurrences[2]
  unavailableOccurrences[2] = RouteOccurrence(
    id: outgoingEdge.id,
    index: outgoingEdge.index,
    kind: outgoingEdge.kind,
    entityID: "test.edge.unreviewed",
    tollDomainID: outgoingEdge.tollDomainID
  )
  #expect(
    throws: ReleasedRouteAuthoringError.unavailableChoice(
      "test.occurrence.loop-movement-1"
    )
  ) {
    try ReleasedRouteAuthoringRecipe(
      routePlan: replacingOccurrences(
        in: fixture.routePlan,
        with: unavailableOccurrences
      ),
      editorCatalog: fixture.catalog
    )
  }
}

@Test("Released authoring rejects a route that exits before its final occurrence")
func releasedAuthoringRejectsDestinationDrift() {
  let fixture = releasedAuthoringFixture()
  let earlyExitCatalog = ReviewedRouteEditorCatalog(
    networkSnapshotID: fixture.catalog.networkSnapshotID,
    entrances: fixture.catalog.entrances,
    decisionPoints: [
      ReviewedRouteEditorDecisionPoint(
        id: "test.decision.loop",
        incomingApproachID: "test.approach.loop",
        junctionComplexID: "test.junction.loop",
        choices: [
          ReviewedRouteEditorChoice(
            id: "test.choice.loop",
            movementID: "test.movement.loop",
            movementTollDomainID: "test.toll",
            outgoingEdgeID: "test.edge.loop",
            outgoingEdgeTollDomainID: "test.toll",
            destination: .exitFacility("test.exit")
          ),
          ReviewedRouteEditorChoice(
            id: "test.choice.exit",
            movementID: "test.movement.exit",
            movementTollDomainID: "test.toll",
            outgoingEdgeID: "test.edge.exit",
            outgoingEdgeTollDomainID: "test.toll",
            destination: .exitFacility("test.exit")
          ),
        ]
      )
    ]
  )

  #expect(
    throws: ReleasedRouteAuthoringError.destinationMismatch(
      "test.occurrence.loop-movement-1"
    )
  ) {
    try ReleasedRouteAuthoringRecipe(
      routePlan: fixture.routePlan,
      editorCatalog: earlyExitCatalog
    )
  }
}

@Test("Released authoring never promotes a different user-authored route")
func releasedAuthoringCompileRequiresWholeRouteIdentity() throws {
  let fixture = releasedAuthoringFixture()
  let recipe = try ReleasedRouteAuthoringRecipe(
    routePlan: fixture.routePlan,
    editorCatalog: fixture.catalog
  )
  var session = try recipe.makeSession(interaction: .parked)
  try session.select(
    choiceID: "test.choice.exit",
    movementOccurrenceID: "test.occurrence.alternate-exit-movement",
    outgoingEdgeOccurrenceID: "test.occurrence.alternate-exit-edge",
    interaction: .parked
  )

  #expect(throws: ReleasedRouteAuthoringError.authoredRouteMismatch) {
    try recipe.compile(session: session, interaction: .parked)
  }
}

private struct ReleasedAuthoringFixture {
  let routePlan: RoutePlan
  let catalog: ReviewedRouteEditorCatalog
}

private func releasedAuthoringFixture() -> ReleasedAuthoringFixture {
  let routePlan = RoutePlan(
    id: "test.plan.released-authoring",
    networkSnapshotID: "test.snapshot.released-authoring",
    entryFacilityID: "test.entrance",
    exitFacilityID: "test.exit",
    recoveryPolicy: .safeRejoin,
    actualDistanceKM: 12.4,
    occurrences: [
      releasedOccurrence("test.occurrence.entry", 0, .edge, "test.edge.loop"),
      releasedOccurrence(
        "test.occurrence.loop-movement-1",
        1,
        .junctionMovement,
        "test.movement.loop"
      ),
      releasedOccurrence(
        "test.occurrence.loop-edge-1",
        2,
        .edge,
        "test.edge.loop"
      ),
      releasedOccurrence(
        "test.occurrence.loop-movement-2",
        3,
        .junctionMovement,
        "test.movement.loop"
      ),
      releasedOccurrence(
        "test.occurrence.loop-edge-2",
        4,
        .edge,
        "test.edge.loop"
      ),
      releasedOccurrence(
        "test.occurrence.exit-movement",
        5,
        .junctionMovement,
        "test.movement.exit"
      ),
      releasedOccurrence(
        "test.occurrence.exit-edge",
        6,
        .edge,
        "test.edge.exit"
      ),
    ]
  )
  let catalog = ReviewedRouteEditorCatalog(
    networkSnapshotID: routePlan.networkSnapshotID,
    entrances: [
      ReviewedRouteEditorEntrance(
        facilityID: routePlan.entryFacilityID,
        initialEdgeID: "test.edge.loop",
        initialEdgeTollDomainID: "test.toll",
        firstDecisionPointID: "test.decision.loop"
      )
    ],
    decisionPoints: [
      ReviewedRouteEditorDecisionPoint(
        id: "test.decision.loop",
        incomingApproachID: "test.approach.loop",
        junctionComplexID: "test.junction.loop",
        choices: [
          ReviewedRouteEditorChoice(
            id: "test.choice.loop",
            movementID: "test.movement.loop",
            movementTollDomainID: "test.toll",
            outgoingEdgeID: "test.edge.loop",
            outgoingEdgeTollDomainID: "test.toll",
            destination: .decisionPoint("test.decision.loop")
          ),
          ReviewedRouteEditorChoice(
            id: "test.choice.exit",
            movementID: "test.movement.exit",
            movementTollDomainID: "test.toll",
            outgoingEdgeID: "test.edge.exit",
            outgoingEdgeTollDomainID: "test.toll",
            destination: .exitFacility(routePlan.exitFacilityID)
          ),
        ]
      )
    ]
  )
  return ReleasedAuthoringFixture(routePlan: routePlan, catalog: catalog)
}

private func releasedOccurrence(
  _ id: String,
  _ index: Int,
  _ kind: RouteOccurrence.Kind,
  _ entityID: String
) -> RouteOccurrence {
  RouteOccurrence(
    id: id,
    index: index,
    kind: kind,
    entityID: entityID,
    tollDomainID: "test.toll"
  )
}

private func replacingOccurrences(
  in routePlan: RoutePlan,
  with occurrences: [RouteOccurrence]
) -> RoutePlan {
  RoutePlan(
    id: routePlan.id,
    networkSnapshotID: routePlan.networkSnapshotID,
    entryFacilityID: routePlan.entryFacilityID,
    exitFacilityID: routePlan.exitFacilityID,
    recoveryPolicy: routePlan.recoveryPolicy,
    actualDistanceKM: routePlan.actualDistanceKM,
    occurrences: occurrences
  )
}
