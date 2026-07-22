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
