import Foundation
import KaidoNavigation
import Testing

@Test("Synthetic matcher corpus reproduces deterministic negative-control failures")
func syntheticMatcherCorpusReplaysDeterministically() throws {
  let fixtures = try loadMatcherFixtures()
  #expect(fixtures.count == 6)

  let runner = NearestEdgeNegativeControl()
  var observationCount = 0
  for fixture in fixtures {
    let first = try runner.run(fixture: fixture)
    let second = try runner.run(fixture: fixture)
    #expect(first == second)
    #expect(first.expectationMatched == true)
    observationCount += first.metrics.observationCount
  }
  #expect(observationCount == 23)
}

@Test("Repeated-edge fixture retains 15, 30, and 60 second gaps")
func repeatedEdgeFixtureRetainsGapBands() throws {
  let fixture = try loadMatcherFixture(named: "repeated-edge-gaps")
  let report = try NearestEdgeNegativeControl().run(fixture: fixture)

  #expect(report.metrics.edgeTop1CorrectCount == 7)
  #expect(report.metrics.occurrenceTruthCount == 7)
  #expect(report.metrics.occurrenceCorrectCount == 0)
  #expect(report.metrics.observationGapDurationsMilliseconds == [15_000, 30_000, 60_000])
  #expect(report.safetyFailures == [.routeOccurrenceUnavailable])
}

@Test("Stacked geometry exposes a false high-confidence nearest-edge tie-break")
func stackedGeometryFailsNearestEdgeControl() throws {
  let fixture = try loadMatcherFixture(named: "stacked-carriageway")
  let report = try NearestEdgeNegativeControl().run(fixture: fixture)

  #expect(report.metrics.edgeTop1CorrectCount == 0)
  #expect(report.safetyFailures.contains(.falseHighConfidenceEdgeMatch))
  #expect(report.safetyFailures.contains(.highConfidenceAmbiguity))
  #expect(report.estimates.allSatisfy { $0.confidence == .high })
}

@Test("A high-confidence prediction inside a tunnel branch gap fails closed")
func tunnelGapRejectsPredictedBranchCommit() throws {
  let fixture = try loadMatcherFixture(named: "tunnel-branch-reacquisition")
  let baseline = try NearestEdgeNegativeControl().run(fixture: fixture)
  let inventedGapCommit = MatcherEstimate(
    observationID: nil,
    estimatedAtMilliseconds: 15_000,
    directedEdgeID: "test.edge.tunnel-planned",
    occurrenceID: "test.occurrence.tunnel-planned",
    candidateEdgeIDs: ["test.edge.tunnel-planned"],
    confidence: .high,
    distanceMeters: nil
  )

  let report = try MatcherReplayEvaluator.evaluate(
    fixture: fixture,
    algorithmID: "test.matcher.invented-gap-commit",
    estimates: baseline.estimates + [inventedGapCommit]
  )

  #expect(report.safetyFailures.contains(.branchCommitDuringObservationGap))
  #expect(report.expectationMatched == nil)
}

@Test("Occurrence-level evaluation detects a backward jump on repeated geometry")
func replayEvaluatorDetectsBackwardOccurrenceJump() throws {
  let fixture = try loadMatcherFixture(named: "repeated-edge-gaps")
  let estimates = fixture.observations.enumerated().map { offset, observation in
    let truth = fixture.groundTruthIntervals.first {
      $0.contains(observation.observedAtMilliseconds)
    }!
    let occurrenceID =
      offset == fixture.observations.count - 1
      ? "test.occurrence.lap-1"
      : truth.occurrenceID
    return MatcherEstimate(
      observationID: observation.id,
      estimatedAtMilliseconds: observation.observedAtMilliseconds,
      directedEdgeID: truth.directedEdgeID,
      occurrenceID: occurrenceID,
      candidateEdgeIDs: [truth.directedEdgeID],
      confidence: .high,
      distanceMeters: 0
    )
  }

  let report = try MatcherReplayEvaluator.evaluate(
    fixture: fixture,
    algorithmID: "test.matcher.backward-jump",
    estimates: estimates
  )

  #expect(report.safetyFailures == [.backwardOccurrenceJump])
  #expect(report.expectationMatched == nil)
}

@Test("Replay validation permits late observed time but requires receive ordering")
func replayValidationSeparatesObservationAndReceiveTime() throws {
  let fixture = try loadMatcherFixture(named: "stale-reordered-sources")
  #expect(fixture.validationIssues.isEmpty)
  #expect(
    fixture.observations.map(\.source) == [
      .phone, .wiredCarPlay, .wirelessCarPlay, .accessory,
    ])
  #expect(fixture.observations.map(\.observedAtMilliseconds) == [0, 2_000, 1_000, 13_000])
  #expect(fixture.observations.map(\.receivedAtMilliseconds) == [0, 2_000, 12_000, 13_000])

  let invalid = MatcherReplayFixture(
    fixtureID: fixture.fixtureID,
    networkSnapshotID: fixture.networkSnapshotID,
    evidenceClassification: fixture.evidenceClassification,
    configuration: fixture.configuration,
    edges: fixture.edges,
    routeOccurrences: fixture.routeOccurrences,
    initialOccurrenceID: fixture.initialOccurrenceID,
    observations: Array(fixture.observations.reversed()),
    groundTruthIntervals: fixture.groundTruthIntervals,
    branchDecisions: fixture.branchDecisions,
    expectedNegativeControlFailures: fixture.expectedNegativeControlFailures
  )
  #expect(invalid.validationIssues.contains("observations must be ordered by received_at_ms"))
}

@Test("Replay validation reports duplicate occurrence IDs without trapping")
func replayValidationReportsDuplicateOccurrences() throws {
  let fixture = try loadMatcherFixture(named: "stacked-carriageway")
  let invalid = MatcherReplayFixture(
    fixtureID: fixture.fixtureID,
    networkSnapshotID: fixture.networkSnapshotID,
    evidenceClassification: fixture.evidenceClassification,
    configuration: fixture.configuration,
    edges: fixture.edges,
    routeOccurrences: [fixture.routeOccurrences[0], fixture.routeOccurrences[0]],
    initialOccurrenceID: fixture.initialOccurrenceID,
    observations: fixture.observations,
    groundTruthIntervals: fixture.groundTruthIntervals,
    branchDecisions: fixture.branchDecisions,
    expectedNegativeControlFailures: fixture.expectedNegativeControlFailures
  )

  #expect(invalid.validationIssues.contains("occurrence IDs are not unique"))
  #expect(invalid.validationIssues.contains("occurrence indexes must be contiguous from zero"))
}

@Test("Route-aware Swift HMM is deterministic and has no safety failures")
func routeAwareSwiftMatcherClearsTrackedSafetyFloor() throws {
  let fixtures = try loadMatcherFixtures()
  let matcher = try RouteAwareSwiftMatcher()
  var observationCount = 0
  var occurrenceTruthCount = 0
  var occurrenceCorrectCount = 0

  for fixture in fixtures {
    let first = try matcher.run(fixture: fixture)
    let second = try matcher.run(fixture: fixture)
    #expect(first == second)
    #expect(first.safetyFailures.isEmpty, "\(fixture.fixtureID): \(first.safetyFailures)")
    observationCount += first.metrics.observationCount
    occurrenceTruthCount += first.metrics.occurrenceTruthCount
    occurrenceCorrectCount += first.metrics.occurrenceCorrectCount
  }

  #expect(observationCount == 23)
  #expect(occurrenceTruthCount == 21)
  #expect(occurrenceCorrectCount == occurrenceTruthCount)
}

@Test("Route-aware Swift HMM resolves repeated occurrences without a backward jump")
func routeAwareSwiftMatcherResolvesRepeatedOccurrences() throws {
  let fixture = try loadMatcherFixture(named: "repeated-edge-gaps")
  let report = try RouteAwareSwiftMatcher().run(fixture: fixture)

  #expect(report.metrics.edgeTop1CorrectCount == 7)
  #expect(report.metrics.occurrenceCorrectCount == 7)
  #expect(
    report.estimates.compactMap(\.occurrenceID) == [
      "test.occurrence.lap-1",
      "test.occurrence.lap-1",
      "test.occurrence.lap-2",
      "test.occurrence.lap-2",
      "test.occurrence.lap-3",
      "test.occurrence.lap-3",
      "test.occurrence.lap-4",
    ])
  #expect(report.safetyFailures.isEmpty)
}

@Test("Route-aware Swift HMM keeps ambiguity, stale fixes, and tunnel reacquisition low")
func routeAwareSwiftMatcherKeepsUnsafeEvidenceLow() throws {
  let matcher = try RouteAwareSwiftMatcher()
  let stacked = try matcher.run(fixture: loadMatcherFixture(named: "stacked-carriageway"))
  #expect(stacked.estimates.allSatisfy { $0.confidence == .low })
  #expect(stacked.estimates.allSatisfy { $0.candidateEdgeIDs.count == 2 })

  let stale = try matcher.run(fixture: loadMatcherFixture(named: "stale-reordered-sources"))
  let lateFix = try #require(
    stale.estimates.first { $0.observationID == "late-wireless-fix" }
  )
  #expect(lateFix.confidence == .low)

  let tunnel = try matcher.run(fixture: loadMatcherFixture(named: "tunnel-branch-reacquisition"))
  let reacquired = try #require(tunnel.estimates.first { $0.observationID == "after-tunnel" })
  #expect(reacquired.confidence == .low)
  #expect(reacquired.occurrenceID == "test.occurrence.tunnel-planned")
  #expect(tunnel.estimates.allSatisfy { $0.observationID != nil })
}

@Test("Route-aware Swift HMM never promotes a stale first observation")
func routeAwareSwiftMatcherKeepsInitialStaleFixLow() throws {
  let source = try loadMatcherFixture(named: "stale-reordered-sources")
  let observation = MatcherReplayObservation(
    id: "initial-stale-fix",
    observedAtMilliseconds: 0,
    receivedAtMilliseconds: 10_000,
    coordinate: source.observations[0].coordinate,
    horizontalAccuracyMeters: 4,
    courseDegrees: 90,
    speedMetersPerSecond: 12,
    source: .phone
  )
  let fixture = MatcherReplayFixture(
    fixtureID: "synthetic.matcher.initial-stale-fix",
    networkSnapshotID: source.networkSnapshotID,
    evidenceClassification: "SYNTHETIC",
    configuration: source.configuration,
    edges: source.edges,
    routeOccurrences: source.routeOccurrences,
    initialOccurrenceID: source.initialOccurrenceID,
    observations: [observation],
    groundTruthIntervals: [
      MatcherGroundTruthInterval(
        startMilliseconds: 0,
        endMilliseconds: 0,
        directedEdgeID: source.edges[0].id,
        occurrenceID: source.initialOccurrenceID,
        classification: .onRoute
      )
    ],
    expectedNegativeControlFailures: []
  )

  let report = try RouteAwareSwiftMatcher().run(fixture: fixture)
  #expect(report.estimates[0].confidence == .low)
  #expect(!report.safetyFailures.contains(.highConfidenceStaleObservation))
}

@Test("Route-aware Swift HMM does not high-commit the first noisy wrong-branch fix")
func routeAwareSwiftMatcherDefersNoisyBranchCommit() throws {
  let fixture = try loadMatcherFixture(named: "wrong-branch-noisy-fix")
  let report = try RouteAwareSwiftMatcher().run(fixture: fixture)
  let firstAfterBranch = try #require(
    report.estimates.first { $0.observationID == "first-noisy-after-branch" }
  )
  let laterAfterBranch = try #require(
    report.estimates.first { $0.observationID == "later-after-branch" }
  )

  #expect(firstAfterBranch.confidence == .low)
  #expect(firstAfterBranch.candidateEdgeIDs.count > 1)
  #expect(laterAfterBranch.directedEdgeID == "test.edge.wrong-branch")
  #expect(report.safetyFailures.isEmpty)
}

@Test("Incremental matcher session is identical to batch replay")
func routeMatcherSessionMatchesBatchReplay() throws {
  let matcher = try RouteAwareSwiftMatcher()
  for fixture in try loadMatcherFixtures() {
    let batch = try matcher.estimates(fixture: fixture)
    var session = try matcher.makeSession(
      corridor: routeMatcherCorridor(fixture),
      sessionConfiguration: RouteMatcherSessionConfiguration(
        ambiguityMarginMeters: fixture.configuration.ambiguityMarginMeters,
        staleObservationThresholdMilliseconds: fixture.configuration
          .staleObservationThresholdMilliseconds,
        observationGapThresholdMilliseconds: fixture.configuration
          .observationGapThresholdMilliseconds
      ),
      initialOccurrenceID: fixture.initialOccurrenceID
    )
    let streamed = try fixture.observations.map {
      try session.observe(routeMatcherObservation($0))
    }

    #expect(streamed == batch)
  }
}

@Test("Stale fixes do not mutate accepted incremental session state")
func routeMatcherSessionRejectsStaleStateMutation() throws {
  let fixture = try loadMatcherFixture(named: "stale-reordered-sources")
  let matcher = try RouteAwareSwiftMatcher()
  var session = try matcher.makeSession(
    corridor: routeMatcherCorridor(fixture),
    initialOccurrenceID: fixture.initialOccurrenceID
  )

  _ = try session.observe(routeMatcherObservation(fixture.observations[0]))
  let beforeStale = session.diagnostics
  let staleEstimate = try session.observe(routeMatcherObservation(fixture.observations[2]))

  #expect(staleEstimate.confidence == .low)
  #expect(session.diagnostics.acceptedObservationCount == beforeStale.acceptedObservationCount)
  #expect(session.diagnostics.activeStateCount == beforeStale.activeStateCount)
}

@Test("Matcher session reset and restart discard prior temporal evidence")
func routeMatcherSessionResetsAndRestarts() throws {
  let fixture = try loadMatcherFixture(named: "repeated-edge-gaps")
  let matcher = try RouteAwareSwiftMatcher()
  var session = try matcher.makeSession(
    corridor: routeMatcherCorridor(fixture),
    initialOccurrenceID: "test.occurrence.lap-1"
  )
  for observation in fixture.observations {
    _ = try session.observe(routeMatcherObservation(observation))
  }
  #expect(session.diagnostics.acceptedObservationCount == fixture.observations.count)

  session.reset()
  #expect(session.diagnostics.acceptedObservationCount == 0)
  #expect(session.diagnostics.activeStateCount == 0)
  let firstAfterReset = try session.observe(routeMatcherObservation(fixture.observations[0]))
  #expect(firstAfterReset.occurrenceID == "test.occurrence.lap-1")

  try session.restart(at: "test.occurrence.lap-3")
  let firstAfterRestart = try session.observe(routeMatcherObservation(fixture.observations[0]))
  #expect(firstAfterRestart.occurrenceID == "test.occurrence.lap-3")
}

@Test("Corridor spatial index excludes distant roads from an observation query")
func routeMatcherSessionUsesCorridorSpatialIndex() throws {
  let localCoordinates = [
    MatcherCoordinate(latitude: 35.6800, longitude: 139.7600),
    MatcherCoordinate(latitude: 35.6800, longitude: 139.7610),
  ]
  let distantEdges = (0..<100).map { index in
    let latitude = 34.0 + Double(index) * 0.001
    return RouteMatcherDirectedEdge(
      id: "distant-\(index)",
      coordinates: [
        MatcherCoordinate(latitude: latitude, longitude: 135.0),
        MatcherCoordinate(latitude: latitude, longitude: 135.001),
      ]
    )
  }
  let corridor = RouteMatcherCorridor(
    id: "test.corridor.indexed",
    networkSnapshotID: "test.snapshot",
    routePlanID: "test.plan",
    edges: [RouteMatcherDirectedEdge(id: "local", coordinates: localCoordinates)]
      + distantEdges,
    occurrences: [RouteMatcherOccurrence(id: "local-occurrence", index: 0, directedEdgeID: "local")]
  )
  var session = try RouteAwareSwiftMatcher().makeSession(
    corridor: corridor,
    initialOccurrenceID: "local-occurrence"
  )
  let estimate = try session.observe(
    RouteMatcherObservation(
      id: "near-local",
      observedAtMilliseconds: 1_000,
      receivedAtMilliseconds: 1_000,
      coordinate: MatcherCoordinate(latitude: 35.6800, longitude: 139.7605),
      horizontalAccuracyMeters: 5,
      courseDegrees: 90,
      speedMetersPerSecond: 10,
      source: .phone
    )
  )

  #expect(estimate.directedEdgeID == "local")
  #expect(session.diagnostics.indexedEdgeCount == 101)
  #expect(session.diagnostics.lastQueriedEdgeCount == 1)
}

@Test("Matcher session bounds repeated-occurrence active state growth")
func routeMatcherSessionBoundsActiveStates() throws {
  let edge = RouteMatcherDirectedEdge(
    id: "loop-edge",
    coordinates: [
      MatcherCoordinate(latitude: 35.6800, longitude: 139.7600),
      MatcherCoordinate(latitude: 35.6800, longitude: 139.7610),
    ]
  )
  let corridor = RouteMatcherCorridor(
    id: "test.corridor.repeated-state-bound",
    networkSnapshotID: "test.snapshot",
    routePlanID: "test.plan",
    edges: [edge],
    occurrences: (0..<200).map {
      RouteMatcherOccurrence(id: "loop-\($0)", index: $0, directedEdgeID: edge.id)
    }
  )
  var session = try RouteAwareSwiftMatcher().makeSession(
    corridor: corridor,
    sessionConfiguration: RouteMatcherSessionConfiguration(maximumActiveStates: 7)
  )
  _ = try session.observe(
    RouteMatcherObservation(
      observedAtMilliseconds: 1_000,
      receivedAtMilliseconds: 1_000,
      coordinate: MatcherCoordinate(latitude: 35.6800, longitude: 139.7605),
      horizontalAccuracyMeters: 5,
      courseDegrees: 90,
      speedMetersPerSecond: 10,
      source: .phone
    )
  )

  #expect(session.diagnostics.activeStateCount == 7)
}

@Test("Invalid live observation fails without changing matcher state")
func routeMatcherSessionRejectsInvalidObservation() throws {
  let fixture = try loadMatcherFixture(named: "parallel-surface-expressway")
  var session = try RouteAwareSwiftMatcher().makeSession(
    corridor: routeMatcherCorridor(fixture),
    initialOccurrenceID: fixture.initialOccurrenceID
  )
  let invalid = RouteMatcherObservation(
    observedAtMilliseconds: 2_000,
    receivedAtMilliseconds: 1_000,
    coordinate: fixture.observations[0].coordinate,
    horizontalAccuracyMeters: 5,
    source: .phone
  )

  #expect(throws: RouteAwareSwiftMatcherError.invalidObservation) {
    try session.observe(invalid)
  }
  #expect(session.diagnostics.acceptedObservationCount == 0)
  #expect(session.diagnostics.activeStateCount == 0)

  let overflowingAge = RouteMatcherObservation(
    observedAtMilliseconds: Int.min,
    receivedAtMilliseconds: Int.max,
    coordinate: fixture.observations[0].coordinate,
    horizontalAccuracyMeters: 5,
    source: .phone
  )
  #expect(throws: RouteAwareSwiftMatcherError.invalidObservation) {
    try session.observe(overflowingAge)
  }
  #expect(session.diagnostics.acceptedObservationCount == 0)

  let first = fixture.observations[0]
  _ = try session.observe(
    RouteMatcherObservation(
      id: first.id,
      observedAtMilliseconds: 2_000,
      receivedAtMilliseconds: 2_000,
      coordinate: first.coordinate,
      horizontalAccuracyMeters: first.horizontalAccuracyMeters,
      courseDegrees: first.courseDegrees,
      speedMetersPerSecond: first.speedMetersPerSecond,
      source: first.source
    )
  )
  let outOfReceiveOrder = RouteMatcherObservation(
    observedAtMilliseconds: 1_500,
    receivedAtMilliseconds: 1_500,
    coordinate: first.coordinate,
    horizontalAccuracyMeters: 5,
    source: .phone
  )
  #expect(throws: RouteAwareSwiftMatcherError.invalidObservation) {
    try session.observe(outOfReceiveOrder)
  }
  #expect(session.diagnostics.acceptedObservationCount == 1)
}

private func loadMatcherFixtures() throws -> [MatcherReplayFixture] {
  let directory = matcherFixtureDirectory()
  return try FileManager.default.contentsOfDirectory(
    at: directory,
    includingPropertiesForKeys: nil
  )
  .filter { $0.pathExtension == "json" }
  .sorted { $0.lastPathComponent < $1.lastPathComponent }
  .map { try JSONDecoder().decode(MatcherReplayFixture.self, from: Data(contentsOf: $0)) }
}

private func routeMatcherCorridor(_ fixture: MatcherReplayFixture) -> RouteMatcherCorridor {
  let edges = fixture.edges.map { edge in
    RouteMatcherDirectedEdge(
      id: edge.id,
      coordinates: edge.coordinates,
      successorEdgeIDs: Set(
        fixture.edges.compactMap { candidate in
          edge.coordinates.last == candidate.coordinates.first ? candidate.id : nil
        }
      )
    )
  }
  return RouteMatcherCorridor(
    id: fixture.fixtureID,
    networkSnapshotID: fixture.networkSnapshotID,
    routePlanID: fixture.fixtureID,
    edges: edges,
    occurrences: fixture.routeOccurrences.map {
      RouteMatcherOccurrence(
        id: $0.occurrenceID,
        index: $0.index,
        directedEdgeID: $0.directedEdgeID
      )
    }
  )
}

private func routeMatcherObservation(
  _ observation: MatcherReplayObservation
) -> RouteMatcherObservation {
  RouteMatcherObservation(
    id: observation.id,
    observedAtMilliseconds: observation.observedAtMilliseconds,
    receivedAtMilliseconds: observation.receivedAtMilliseconds,
    coordinate: observation.coordinate,
    horizontalAccuracyMeters: observation.horizontalAccuracyMeters,
    courseDegrees: observation.courseDegrees,
    speedMetersPerSecond: observation.speedMetersPerSecond,
    source: observation.source
  )
}

private func loadMatcherFixture(named name: String) throws -> MatcherReplayFixture {
  let url = matcherFixtureDirectory().appendingPathComponent("\(name).json")
  return try JSONDecoder().decode(MatcherReplayFixture.self, from: Data(contentsOf: url))
}

private func matcherFixtureDirectory() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("benchmarks/map-matching/fixtures/synthetic")
}
