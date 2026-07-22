import KaidoSurfaceRouting
import Testing

@Test("Entrance fixture validator binds a directed transition to its graph snapshot")
func entranceFixtureGraphBindingPasses() {
  let report = EntranceProbeFixtureValidator.validate(
    makeFixture(),
    graph: makeGraph(),
    profile: .structural
  )

  #expect(report.isValid)
  #expect(report.issues.isEmpty)
}

@Test("Entrance fixture validator rejects disconnected and non-expressway targets")
func entranceFixtureGraphBindingFailsClosed() {
  let graph = SurfaceRoadGraphSnapshot(
    networkSnapshotID: "test.network",
    edges: [
      makeEdge(
        id: "test.edge.surface", from: "test.node.0", to: "test.node.1", kind: .ordinaryRoad),
      makeEdge(
        id: "test.edge.ramp", from: "test.node.wrong", to: "test.node.2", kind: .entryTransition),
      makeEdge(id: "test.edge.target", from: "test.node.2", to: "test.node.3", kind: .ordinaryRoad),
    ]
  )

  let report = EntranceProbeFixtureValidator.validate(
    makeFixture(),
    graph: graph,
    profile: .structural
  )
  let codes = Set(report.issues.map(\.code))

  #expect(!report.isValid)
  #expect(codes.contains("APPROACH_TO_TRANSITION_DISCONNECTED"))
  #expect(codes.contains("TARGET_EDGE_NOT_EXPRESSWAY"))
}

@Test("Release-candidate fixture validation requires an explicit target edge")
func entranceFixtureReleaseRequiresTargetEdge() {
  let fixture = makeFixture(targetExpresswayEdgeID: nil)
  let report = EntranceProbeFixtureValidator.validate(
    fixture,
    graph: makeGraph(),
    profile: .releaseCandidate
  )

  #expect(report.issues.map(\.code).contains("TARGET_EXPRESSWAY_EDGE_REQUIRED"))
}

@Test("Entrance fixture validator reports duplicate graph identities without trapping")
func entranceFixtureRejectsDuplicateGraphEdgeIdentity() {
  let base = makeGraph()
  let graph = SurfaceRoadGraphSnapshot(
    networkSnapshotID: base.networkSnapshotID,
    edges: base.edges + [base.edges[0]]
  )

  let report = EntranceProbeFixtureValidator.validate(
    makeFixture(),
    graph: graph,
    profile: .structural
  )

  #expect(report.issues.map(\.code).contains("GRAPH_DUPLICATE_EDGE_ID"))
}

private func makeFixture(targetExpresswayEdgeID: String? = "test.edge.target")
  -> EntranceProbeFixture
{
  EntranceProbeFixture(
    schemaVersion: "1.0",
    id: "test.fixture",
    networkSnapshotID: "test.network",
    evidence: ProbeEvidence(
      classification: .synthetic,
      checkedAt: "2026-07-23",
      sources: [],
      limitations: [],
      releaseBlockers: []
    ),
    entrance: ProbeEntranceFacility(
      facilityID: "test.entry",
      accessComplexID: "test.access-complex",
      targetCarriagewayID: "test.carriageway",
      targetDirection: "TEST"
    ),
    approachAnchor: DirectedApproachAnchor(
      id: "test.anchor",
      coordinate: SurfaceCoordinate(latitude: 35, longitude: 139),
      directedSurfaceEdgeID: "test.edge.surface",
      expectedBearingDegrees: 0,
      bearingToleranceDegrees: 25,
      maxTerminalDistanceMeters: 25
    ),
    entryTransition: ProbeEntryTransition(
      directedEdgeIDs: ["test.edge.ramp"],
      firstRouteOccurrenceID: "test.occurrence",
      targetExpresswayEdgeID: targetExpresswayEdgeID
    ),
    journeyCompatibility: ProbeJourneyCompatibility(
      allowedJoinOccurrenceIDs: ["test.occurrence"],
      finishPolicies: [.finishOnRequest],
      compatibleExitFacilityIDs: []
    ),
    prohibitions: ProbeProhibitions(
      forbiddenEarlyExpresswayEdgeIDs: ["test.edge.ramp"],
      forbiddenTollDomainIDs: []
    ),
    origins: [
      ProbeOrigin(
        id: "test.origin.same",
        kind: .sameSide,
        coordinate: SurfaceCoordinate(latitude: 35, longitude: 139),
        notes: "test"
      ),
      ProbeOrigin(
        id: "test.origin.cross",
        kind: .crossDirection,
        coordinate: SurfaceCoordinate(latitude: 35, longitude: 139),
        notes: "test"
      ),
      ProbeOrigin(
        id: "test.origin.incompatible",
        kind: .nearestIncompatible,
        coordinate: SurfaceCoordinate(latitude: 35, longitude: 139),
        notes: "test"
      ),
    ]
  )
}

private func makeGraph() -> SurfaceRoadGraphSnapshot {
  SurfaceRoadGraphSnapshot(
    networkSnapshotID: "test.network",
    edges: [
      makeEdge(
        id: "test.edge.surface", from: "test.node.0", to: "test.node.1", kind: .ordinaryRoad),
      makeEdge(
        id: "test.edge.ramp", from: "test.node.1", to: "test.node.2", kind: .entryTransition),
      makeEdge(id: "test.edge.target", from: "test.node.2", to: "test.node.3", kind: .expressway),
    ]
  )
}

private func makeEdge(
  id: String,
  from: String,
  to: String,
  kind: SurfaceRoadEdgeKind
) -> SurfaceRoadEdge {
  SurfaceRoadEdge(
    id: id,
    fromNodeID: from,
    toNodeID: to,
    kind: kind,
    coordinates: [
      SurfaceCoordinate(latitude: 35, longitude: 139),
      SurfaceCoordinate(latitude: 35.0001, longitude: 139),
    ]
  )
}
