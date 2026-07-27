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
