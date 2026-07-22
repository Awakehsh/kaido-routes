import KaidoDomain
import KaidoNavigation
import Testing

@Test("Matcher fraction becomes route distance through ordered occurrences")
func guidanceProgressBridgeUsesRouteGeometry() throws {
  let fixture = bridgeFixture()
  let estimate = MatcherEstimate(
    observationID: "test.observation",
    estimatedAtMilliseconds: 1_000,
    directedEdgeID: "test.edge.current",
    occurrenceID: "test.occurrence.current",
    candidateEdgeIDs: ["test.edge.current"],
    confidence: .high,
    distanceMeters: 9_999,
    fractionAlongEdge: 0.25
  )

  let progress = try GuidanceProgressBridge.resolve(
    estimate: estimate,
    routePlan: fixture.routePlan,
    corridor: fixture.corridor,
    decisionZone: fixture.decisionZone
  )

  let expected =
    fixture.currentEdge.lengthMeters * 0.75
    + fixture.intermediateEdge.lengthMeters + 5
  #expect(abs(progress.distanceToDecisionPointMeters - expected) < 0.001)
  #expect(progress.occurrenceID == "test.occurrence.current")
  #expect(progress.observedAtMilliseconds == 1_000)
}

@Test("Repeated edge entities remain occurrence-scoped in distance bridging")
func guidanceProgressBridgePreservesRepeatedOccurrenceIdentity() throws {
  let fixture = bridgeFixture(repeatCurrentEdge: true)
  let estimate = MatcherEstimate(
    observationID: nil,
    estimatedAtMilliseconds: 2_000,
    directedEdgeID: "test.edge.current",
    occurrenceID: "test.occurrence.current",
    candidateEdgeIDs: ["test.edge.current"],
    confidence: .high,
    distanceMeters: 0,
    fractionAlongEdge: 0.5
  )

  let progress = try GuidanceProgressBridge.resolve(
    estimate: estimate,
    routePlan: fixture.routePlan,
    corridor: fixture.corridor,
    decisionZone: fixture.decisionZone
  )

  #expect(progress.occurrenceID == "test.occurrence.current")
  #expect(
    progress.distanceToDecisionPointMeters
      < fixture.currentEdge.lengthMeters + fixture.intermediateEdge.lengthMeters + 5
  )
}

@Test("LOW, missing fraction, and skipped paths fail closed")
func guidanceProgressBridgeRejectsInsufficientEvidence() {
  let fixture = bridgeFixture()
  let low = MatcherEstimate(
    observationID: nil,
    estimatedAtMilliseconds: 1_000,
    directedEdgeID: "test.edge.current",
    occurrenceID: "test.occurrence.current",
    candidateEdgeIDs: ["test.edge.current"],
    confidence: .low,
    distanceMeters: 0,
    fractionAlongEdge: 0.5
  )
  #expect(throws: GuidanceProgressBridgeError.insufficientMatcherEvidence) {
    try GuidanceProgressBridge.resolve(
      estimate: low,
      routePlan: fixture.routePlan,
      corridor: fixture.corridor,
      decisionZone: fixture.decisionZone
    )
  }

  let missingFraction = MatcherEstimate(
    observationID: nil,
    estimatedAtMilliseconds: 1_000,
    directedEdgeID: "test.edge.current",
    occurrenceID: "test.occurrence.current",
    candidateEdgeIDs: ["test.edge.current"],
    confidence: .high,
    distanceMeters: 0
  )
  #expect(throws: GuidanceProgressBridgeError.insufficientMatcherEvidence) {
    try GuidanceProgressBridge.resolve(
      estimate: missingFraction,
      routePlan: fixture.routePlan,
      corridor: fixture.corridor,
      decisionZone: fixture.decisionZone
    )
  }

  #expect(
    throws: GuidanceProgressBridgeError.skippedRouteOccurrence(
      "test.occurrence.intermediate"
    )
  ) {
    try GuidanceProgressBridge.resolve(
      estimate: MatcherEstimate(
        observationID: nil,
        estimatedAtMilliseconds: 1_000,
        directedEdgeID: "test.edge.current",
        occurrenceID: "test.occurrence.current",
        candidateEdgeIDs: ["test.edge.current"],
        confidence: .high,
        distanceMeters: 0,
        fractionAlongEdge: 0.5
      ),
      routePlan: fixture.routePlan,
      corridor: fixture.corridor,
      decisionZone: fixture.decisionZone,
      skippedOccurrenceIDs: ["test.occurrence.intermediate"]
    )
  }
}

@Test("Swift matcher publishes the selected along-edge fraction")
func swiftMatcherPublishesAlongEdgeFraction() throws {
  let edge = RouteMatcherDirectedEdge(
    id: "test.edge",
    coordinates: [
      MatcherCoordinate(latitude: 35.68, longitude: 139.76),
      MatcherCoordinate(latitude: 35.68, longitude: 139.761),
    ]
  )
  var session = try RouteAwareSwiftMatcher().makeSession(
    corridor: RouteMatcherCorridor(
      id: "test.corridor",
      networkSnapshotID: "test.snapshot",
      routePlanID: "test.plan",
      edges: [edge],
      occurrences: [
        RouteMatcherOccurrence(id: "test.occurrence", index: 0, directedEdgeID: edge.id)
      ]
    ),
    initialOccurrenceID: "test.occurrence"
  )

  let estimate = try session.observe(
    RouteMatcherObservation(
      observedAtMilliseconds: 1_000,
      receivedAtMilliseconds: 1_000,
      coordinate: MatcherCoordinate(latitude: 35.68, longitude: 139.7605),
      horizontalAccuracyMeters: 5,
      courseDegrees: 90,
      speedMetersPerSecond: 10,
      source: .phone
    )
  )

  #expect(estimate.confidence == .high)
  #expect(abs((estimate.fractionAlongEdge ?? -1) - 0.5) < 0.001)
  #expect((estimate.distanceMeters ?? .infinity) < 0.001)
}

private struct GuidanceProgressBridgeFixture {
  let routePlan: RoutePlan
  let corridor: RouteMatcherCorridor
  let decisionZone: DecisionZoneProgressDefinition
  let currentEdge: RouteMatcherDirectedEdge
  let intermediateEdge: RouteMatcherDirectedEdge
}

private func bridgeFixture(
  repeatCurrentEdge: Bool = false
) -> GuidanceProgressBridgeFixture {
  let currentEdge = RouteMatcherDirectedEdge(
    id: "test.edge.current",
    coordinates: [
      MatcherCoordinate(latitude: 35.68, longitude: 139.76),
      MatcherCoordinate(latitude: 35.68, longitude: 139.761),
    ],
    successorEdgeIDs: ["test.edge.intermediate"]
  )
  let intermediateEdge = RouteMatcherDirectedEdge(
    id: "test.edge.intermediate",
    coordinates: [
      MatcherCoordinate(latitude: 35.68, longitude: 139.761),
      MatcherCoordinate(latitude: 35.68, longitude: 139.762),
    ],
    successorEdgeIDs: ["test.edge.movement"]
  )
  let movementEdge = RouteMatcherDirectedEdge(
    id: "test.edge.movement",
    coordinates: [
      MatcherCoordinate(latitude: 35.68, longitude: 139.762),
      MatcherCoordinate(latitude: 35.68, longitude: 139.7622),
    ]
  )
  let routeOccurrences = [
    RouteOccurrence(
      id: "test.occurrence.prior-copy",
      index: 0,
      kind: .edge,
      entityID: "test.edge.current"
    ),
    RouteOccurrence(
      id: "test.occurrence.current",
      index: 1,
      kind: .edge,
      entityID: "test.edge.current"
    ),
    RouteOccurrence(
      id: "test.occurrence.intermediate",
      index: 2,
      kind: .edge,
      entityID: "test.edge.intermediate"
    ),
    RouteOccurrence(
      id: "test.occurrence.movement",
      index: 3,
      kind: .junctionMovement,
      entityID: "test.movement"
    ),
  ]
  let corridorOccurrences = [
    RouteMatcherOccurrence(
      id: "test.occurrence.prior-copy",
      index: 0,
      directedEdgeID: repeatCurrentEdge ? currentEdge.id : "test.edge.prior"
    ),
    RouteMatcherOccurrence(
      id: "test.occurrence.current",
      index: 1,
      directedEdgeID: currentEdge.id
    ),
    RouteMatcherOccurrence(
      id: "test.occurrence.intermediate",
      index: 2,
      directedEdgeID: intermediateEdge.id
    ),
    RouteMatcherOccurrence(
      id: "test.occurrence.movement",
      index: 3,
      directedEdgeID: movementEdge.id
    ),
  ]
  let priorEdge = RouteMatcherDirectedEdge(
    id: "test.edge.prior",
    coordinates: [
      MatcherCoordinate(latitude: 35.68, longitude: 139.759),
      MatcherCoordinate(latitude: 35.68, longitude: 139.76),
    ],
    successorEdgeIDs: [currentEdge.id]
  )
  let routePlan = RoutePlan(
    id: "test.plan",
    networkSnapshotID: "test.snapshot",
    entryFacilityID: "test.entry",
    exitFacilityID: "test.exit",
    recoveryPolicy: .strict,
    occurrences: routeOccurrences
  )
  return GuidanceProgressBridgeFixture(
    routePlan: routePlan,
    corridor: RouteMatcherCorridor(
      id: "test.corridor",
      networkSnapshotID: routePlan.networkSnapshotID,
      routePlanID: routePlan.id,
      edges: [priorEdge, currentEdge, intermediateEdge, movementEdge],
      occurrences: corridorOccurrences
    ),
    decisionZone: DecisionZoneProgressDefinition(
      id: "test.zone",
      networkSnapshotID: routePlan.networkSnapshotID,
      routePlanID: routePlan.id,
      movementOccurrenceID: "test.occurrence.movement",
      entryOffsetMeters: 5
    ),
    currentEdge: currentEdge,
    intermediateEdge: intermediateEdge
  )
}
