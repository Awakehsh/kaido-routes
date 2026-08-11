import Foundation
import KaidoNavigation
import Testing

@Test("Simulation trace preserves repeated RoutePlan occurrences")
func navigationDriveSimulationTracePreservesOccurrences() throws {
  let release = try simulationProductRelease()
  let bundle = release.navigation.bundle

  let trace = try NavigationDriveSimulationTraceGenerator.generate(
    routePlan: bundle.routePlan,
    corridor: bundle.matcherCorridor,
    configuration: NavigationDriveSimulationConfiguration(
      sampleFractions: [0.25, 0.75],
      completesAtExitHandoff: false
    )
  )

  #expect(trace.routePlanID == bundle.routePlan.id)
  #expect(trace.matcherCorridorID == bundle.matcherCorridor.id)
  #expect(trace.evidenceScope == .syntheticTestOnly)
  #expect(!trace.grantsNavigationAuthority)
  #expect(trace.events.count == bundle.routePlan.occurrences.count * 2)
  #expect(
    trace.events.map(\.id)
      == bundle.routePlan.occurrences.flatMap {
        ["simulation.\($0.index).0", "simulation.\($0.index).1"]
      }
  )
}

@Test("Simulation anomalies target one occurrence without changing route identity")
func navigationDriveSimulationInjectsTargetedAnomalies() throws {
  let release = try simulationProductRelease()
  let bundle = release.navigation.bundle
  let targetOccurrence = try #require(bundle.matcherCorridor.occurrences.dropFirst().first)

  let trace = try NavigationDriveSimulationTraceGenerator.generate(
    routePlan: bundle.routePlan,
    corridor: bundle.matcherCorridor,
    configuration: NavigationDriveSimulationConfiguration(
      sampleFractions: [0.25, 0.75],
      anomalies: [
        NavigationDriveSimulationAnomaly(
          occurrenceID: targetOccurrence.id,
          sampleIndex: 1,
          kind: .horizontalAccuracyMeters(80)
        ),
        NavigationDriveSimulationAnomaly(
          occurrenceID: targetOccurrence.id,
          sampleIndex: 1,
          kind: .signalGapBeforeMilliseconds(15_000)
        ),
      ],
      completesAtExitHandoff: false
    )
  )

  let targetEvent = try #require(
    trace.events.first {
      $0.id == "simulation.\(targetOccurrence.index).1"
    }
  )
  guard case .matcherObservation(let targetObservation) = targetEvent.action else {
    Issue.record("Expected a matcher observation")
    return
  }
  #expect(targetObservation.horizontalAccuracyMeters == 80)
  let previousEvent = try #require(
    trace.events.first {
      $0.id == "simulation.\(targetOccurrence.index).0"
    }
  )
  #expect(targetEvent.atMilliseconds - previousEvent.atMilliseconds == 16_000)
  #expect(trace.routePlanID == bundle.routePlan.id)
}

@Test("Route-speed simulation densifies long edges and keeps time aligned with displacement")
func navigationDriveSimulationUsesRouteSpeedCadence() throws {
  let release = try simulationProductRelease()
  let bundle = release.navigation.bundle
  let firstOccurrence = try #require(
    bundle.matcherCorridor.occurrences.first
  )
  let trace = try NavigationDriveSimulationTraceGenerator.generate(
    routePlan: bundle.routePlan,
    corridor: bundle.matcherCorridor,
    configuration: NavigationDriveSimulationConfiguration(
      sampleFractions: [0.25, 0.75],
      maximumSampleSpacingMeters: 20,
      timing: .routeSpeed,
      speedMetersPerSecond: 10,
      completesAtExitHandoff: false
    )
  )
  let observations: [RouteMatcherObservation] = trace.events.compactMap {
    guard case .matcherObservation(let observation) = $0.action,
      $0.id.hasPrefix("simulation.\(firstOccurrence.index).")
    else {
      return nil
    }
    return observation
  }
  let connectedObservations: [RouteMatcherObservation] =
    trace.events.compactMap {
      guard case .matcherObservation(let observation) = $0.action,
        $0.id.hasPrefix("simulation.0.")
          || $0.id.hasPrefix("simulation.1.")
      else {
        return nil
      }
      return observation
    }

  #expect(observations.count > 2)
  #expect(
    zip(
      connectedObservations,
      connectedObservations.dropFirst()
    ).allSatisfy {
      testDistance($0.coordinate, $1.coordinate) <= 20.5
    }
  )
  for (previous, current) in zip(
    observations,
    observations.dropFirst()
  ) {
    let distanceMeters = testDistance(
      previous.coordinate,
      current.coordinate
    )
    let elapsedMilliseconds =
      current.observedAtMilliseconds
      - previous.observedAtMilliseconds
    let expectedElapsedMilliseconds =
      distanceMeters / 10 * 1_000
    let timingDifference =
      abs(Double(elapsedMilliseconds) - expectedElapsedMilliseconds)
    #expect(distanceMeters <= 20.5)
    #expect(elapsedMilliseconds > 0)
    #expect(timingDifference < 2)
    #expect(current.speedMetersPerSecond == 10)
  }
}

@Test("Accuracy evaluation blocks a wrong HIGH match without hiding safe abstention")
func navigationDriveAccuracyRejectsWrongHighConfidence() throws {
  let release = try simulationProductRelease()
  let bundle = release.navigation.bundle
  let trace = try NavigationDriveSimulationTraceGenerator.generate(
    routePlan: bundle.routePlan,
    corridor: bundle.matcherCorridor,
    configuration: NavigationDriveSimulationConfiguration(
      timing: .routeSpeed,
      completesAtExitHandoff: false
    )
  )
  let exactEstimates = trace.sampleTruth.map {
    MatcherEstimate(
      observationID: $0.observationID,
      estimatedAtMilliseconds: 0,
      directedEdgeID: $0.directedEdgeID,
      occurrenceID: $0.occurrenceID,
      candidateEdgeIDs: [$0.directedEdgeID],
      confidence: .high,
      distanceMeters: 0,
      fractionAlongEdge: $0.fractionAlongOccurrence
    )
  }
  let thresholds = NavigationDriveAccuracyThresholds(
    minimumSampleCount: 1,
    minimumEdgeTop1Accuracy: 0,
    minimumOccurrenceAccuracy: 0,
    minimumHighConfidencePrecision: 1,
    minimumHighConfidenceCoverage: 0,
    maximumProgressErrorP95Meters: 1,
    maximumBackwardProgressRegressionMeters: 1
  )
  let exactReport = try NavigationDriveAccuracyEvaluator.evaluate(
    trace: trace,
    corridor: bundle.matcherCorridor,
    estimates: exactEstimates,
    thresholds: thresholds
  )
  let firstTruth = try #require(trace.sampleTruth.first)
  let otherTruth = try #require(
    trace.sampleTruth.first {
      $0.occurrenceID != firstTruth.occurrenceID
    }
  )
  var unsafeEstimates = exactEstimates
  unsafeEstimates[0] = MatcherEstimate(
    observationID: firstTruth.observationID,
    estimatedAtMilliseconds: 0,
    directedEdgeID: otherTruth.directedEdgeID,
    occurrenceID: otherTruth.occurrenceID,
    candidateEdgeIDs: [otherTruth.directedEdgeID],
    confidence: .high,
    distanceMeters: 0,
    fractionAlongEdge: otherTruth.fractionAlongOccurrence
  )
  let unsafeReport = try NavigationDriveAccuracyEvaluator.evaluate(
    trace: trace,
    corridor: bundle.matcherCorridor,
    estimates: unsafeEstimates,
    thresholds: thresholds
  )

  #expect(exactReport.gateStatus == .deterministicFloorMet)
  #expect(exactReport.highConfidencePrecision == 1)
  #expect(unsafeReport.unsafeHighConfidenceEdgeCount == 1)
  #expect(unsafeReport.unsafeHighConfidenceOccurrenceCount == 1)
  #expect(unsafeReport.gateStatus == .thresholdNotMet)
}

@Test("Simulation controller supports play pause step speed and reset")
func navigationDriveSimulationControlsPlayback() async throws {
  let release = try simulationProductRelease()
  let simulator = try NavigationDriveSimulator(
    release: release,
    configuration: NavigationDriveSimulationConfiguration(
      sampleFractions: [0.25, 0.75],
      completesAtExitHandoff: false
    )
  )

  var status = await simulator.status
  #expect(simulator.evidenceScope == .syntheticTestOnly)
  #expect(!simulator.grantsNavigationAuthority)
  #expect(status.state == .ready)
  #expect(status.evidenceScope == .syntheticTestOnly)
  #expect(!status.grantsNavigationAuthority)
  #expect(status.completedEventCount == 0)
  #expect(status.speed == .fiveTimes)

  status = await simulator.play()
  #expect(status.state == .playing)
  let first = try #require(await simulator.advanceIfPlaying())
  #expect(first.eventIndex == 0)
  #expect(first.status.state == .playing)

  status = await simulator.pause()
  #expect(status.state == .paused)
  let pausedAdvance = try await simulator.advanceIfPlaying()
  #expect(pausedAdvance == nil)

  let second = try #require(await simulator.step())
  #expect(second.eventIndex == 1)
  #expect(second.status.state == .paused)

  status = await simulator.setSpeed(.twentyTimes)
  #expect(status.speed == .twentyTimes)
  status = try await simulator.reset()
  #expect(status.state == .ready)
  #expect(status.completedEventCount == 0)
  #expect(status.speed == .twentyTimes)
  #expect(
    await simulator.navigationSnapshot.currentOccurrenceID
      == release.navigation.bundle.routePlan.occurrences.first?.id
  )
}

@Test("Simulation runs the generated route through the live matcher session")
func navigationDriveSimulationRunsThroughNavigationSession() async throws {
  let release = try simulationProductRelease()
  let simulator = try NavigationDriveSimulator(
    release: release,
    configuration: NavigationDriveSimulationConfiguration(
      sampleFractions: [0.15, 0.5, 0.85],
      completesAtExitHandoff: true
    ),
    speed: .twentyTimes
  )

  let results = try await simulator.runToEnd()
  let estimates = results.compactMap(\.navigationUpdate?.matcherEstimate)
  let snapshot = await simulator.navigationSnapshot

  #expect(!results.isEmpty)
  #expect(estimates.count == release.navigation.bundle.routePlan.occurrences.count * 3)
  #expect(estimates.contains { $0.confidence == .high })
  #expect(snapshot.journeyPhase == .completed)
  #expect(snapshot.currentOccurrenceID == nil)
  #expect(await simulator.status.state == .completed)
}

@Test("Simulation stops on one exact actor-owned guidance emission")
func navigationDriveSimulationStopsOnExactGuidanceEmission() async throws {
  let release = try simulationProductRelease()
  let guidance = try #require(
    release.navigation.bundle.releasedGuidance.first
  )
  let movementOccurrenceID = guidance.frameTemplate.movementOccurrenceID
  let simulator = try NavigationDriveSimulator(
    release: release,
    configuration: NavigationDriveSimulationConfiguration(
      sampleFractions: [0.15, 0.5, 0.85],
      completesAtExitHandoff: false
    )
  )

  let result = try #require(
    await simulator.advancePausedUntilGuidanceEmission(
      movementOccurrenceID: movementOccurrenceID
    )
  )
  let update = try #require(result.navigationUpdate)
  let emission = try #require(update.guidancePromptEmission)
  let frame = try #require(
    update.navigationSnapshot.activeGuidanceFrame
  )

  #expect(emission.promptID == guidance.anchor.promptID)
  #expect(frame.promptID == emission.promptID)
  #expect(frame.movementOccurrenceID == movementOccurrenceID)
  #expect(result.status.state == .paused)
  #expect(result.status.completedEventCount < result.status.totalEventCount)
}

@Test("Unknown guidance occurrence exhausts the finite simulation trace")
func navigationDriveSimulationExhaustsUnknownGuidanceOccurrence()
  async throws
{
  let simulator = try NavigationDriveSimulator(
    release: simulationProductRelease(),
    configuration: NavigationDriveSimulationConfiguration(
      sampleFractions: [0.15, 0.5, 0.85],
      completesAtExitHandoff: false
    )
  )

  let result = try await simulator.advancePausedUntilGuidanceEmission(
    movementOccurrenceID: "unknown.movement-occurrence"
  )
  let status = await simulator.status

  #expect(result == nil)
  #expect(status.state == .completed)
  #expect(status.completedEventCount == status.totalEventCount)
}

private func simulationProductRelease() throws -> KaidoProductRelease {
  let fixture = navigationReleaseBundleFixture()
  return try KaidoProductRelease(
    artifact: KaidoProductReleaseArtifact(
      releaseID: "test.product-release.drive-simulation",
      releasedAt: "2026-07-24T12:00:00+09:00",
      navigationRelease: navigationReleaseArtifact(fixture),
      routeAtlasRelease: productRouteAtlasArtifact(
        fixture,
        includeIncomingApproach: true
      )
    )
  )
}

private func testDistance(
  _ first: MatcherCoordinate,
  _ second: MatcherCoordinate
) -> Double {
  let earthRadiusMeters = 6_371_000.0
  let latitude1 = first.latitude * .pi / 180
  let latitude2 = second.latitude * .pi / 180
  let latitudeDelta = latitude2 - latitude1
  let longitudeDelta =
    (second.longitude - first.longitude) * .pi / 180
  let haversine =
    pow(sin(latitudeDelta / 2), 2)
    + cos(latitude1) * cos(latitude2)
    * pow(sin(longitudeDelta / 2), 2)
  return 2 * earthRadiusMeters
    * atan2(sqrt(haversine), sqrt(1 - haversine))
}
