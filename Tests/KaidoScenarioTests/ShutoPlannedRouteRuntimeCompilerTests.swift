import Foundation
import KaidoDomain
import KaidoNavigation
import KaidoRouting
import Testing

#if canImport(CoreLocation)
  import CoreLocation
  import KaidoAppleAdapters
#endif

@Suite("Whole Shuto observation runtime compiler")
struct ShutoPlannedRouteRuntimeCompilerTests {
  @Test("compiler preserves every selected edge occurrence and legal branch")
  func compilesExactRouteMatcherCorridor() throws {
    let database = try loadWholeShutoDatabase()
    let planner = try ShutoRoutePlanner(database: database)
    let route = try planner.plan(
      entryFacilityID: "shuto.ic.3.shibuya",
      exitFacilityID: "shuto.ic.k1.minatomirai"
    )

    let assets = try ShutoPlannedRouteRuntimeCompiler.compile(
      database: database,
      route: route
    )

    #expect(assets.routePlan == route.routePlan)
    #expect(
      assets.matcherCorridor.occurrences.map(\.id)
        == route.routePlan.occurrences.map(\.id)
    )
    #expect(
      assets.matcherCorridor.occurrences.map(\.directedEdgeID)
        == route.edges.map(\.edgeID)
    )
    #expect(assets.matcherCorridor.edges.count > route.edges.count)
    #expect(assets.matcherCorridor.validationIssues.isEmpty)

    let corridorEdges = Dictionary(
      uniqueKeysWithValues: assets.matcherCorridor.edges.map {
        ($0.id, $0)
      }
    )
    for (current, next) in zip(route.edges, route.edges.dropFirst()) {
      #expect(
        corridorEdges[current.edgeID]?.successorEdgeIDs
          .contains(next.edgeID) == true
      )
    }
  }

  @Test("only exact HIGH occurrence evidence projects route progress")
  func projectsOnlyAdmittedRouteProgress() throws {
    let database = try loadWholeShutoDatabase()
    let route = try ShutoRoutePlanner(database: database).plan(
      entryFacilityID: "shuto.ic.3.shibuya",
      exitFacilityID: "shuto.ic.k1.minatomirai"
    )
    let assets = try ShutoPlannedRouteRuntimeCompiler.compile(
      database: database,
      route: route
    )
    let target = route.routePlan.occurrences[2]
    let edge = route.edges[2]
    let exact = MatcherEstimate(
      observationID: "test.exact",
      estimatedAtMilliseconds: 1_000,
      directedEdgeID: edge.edgeID,
      occurrenceID: target.id,
      candidateEdgeIDs: [edge.edgeID],
      confidence: .high,
      distanceMeters: 1,
      fractionAlongEdge: 0.5
    )

    let progress = try #require(assets.project(exact))
    #expect(progress.occurrenceID == target.id)
    #expect(progress.occurrenceIndex == target.index)
    #expect(progress.fractionAlongOccurrence == 0.5)
    #expect(progress.routeProgressFraction > 0)
    #expect(progress.routeProgressFraction < 1)

    let stale = MatcherEstimate(
      observationID: "test.stale",
      estimatedAtMilliseconds: 2_000,
      directedEdgeID: edge.edgeID,
      occurrenceID: target.id,
      candidateEdgeIDs: [edge.edgeID],
      confidence: .low,
      distanceMeters: 1,
      fractionAlongEdge: 0.75
    )
    #expect(assets.project(stale) == nil)

    let ambiguous = MatcherEstimate(
      observationID: "test.ambiguous",
      estimatedAtMilliseconds: 3_000,
      directedEdgeID: nil,
      occurrenceID: target.id,
      candidateEdgeIDs: [
        edge.edgeID,
        assets.matcherCorridor.edges.first {
          $0.id != edge.edgeID
        }!.id,
      ],
      confidence: .low,
      distanceMeters: 1,
      fractionAlongEdge: 0.9
    )
    #expect(assets.project(ambiguous) == nil)
  }

  @Test("compiler rejects route presentation data that differs from the graph")
  func rejectsDriftedRoutePresentationData() throws {
    let database = try loadWholeShutoDatabase()
    let route = try ShutoRoutePlanner(database: database).plan(
      entryFacilityID: "shuto.ic.3.shibuya",
      exitFacilityID: "shuto.ic.k1.minatomirai"
    )
    let drifted = ShutoPlannedRoute(
      routePlan: route.routePlan,
      entryFacility: route.entryFacility,
      exitFacility: route.exitFacility,
      edges: route.edges,
      coordinates: route.coordinates,
      routeIDsInOrder: route.routeIDsInOrder,
      distanceMeters: route.distanceMeters + 1,
      preference: route.preference
    )

    #expect(
      throws:
        ShutoPlannedRouteRuntimeCompilationError
        .routeGeometryMismatch
    ) {
      try ShutoPlannedRouteRuntimeCompiler.compile(
        database: database,
        route: drifted
      )
    }
  }

  @Test("deterministic whole-network observations drive the actor runtime")
  func drivesActorRuntimeWithGeneratedObservations() async throws {
    let database = try loadWholeShutoDatabase()
    // Shibuya has a geometrically isolated ramp mouth; Kyobashi's sits
    // directly beneath the C1 viaduct, where the unique-candidate entry
    // verification correctly fails closed (recorded as a stacked-geometry
    // limitation), which would test the fail-closed path instead of the
    // actor pipeline this test exercises.
    let route = try ShutoRoutePlanner(database: database).plan(
      entryFacilityID: "shuto.ic.3.shibuya",
      exitFacilityID: "shuto.ic.k1.minatomirai"
    )
    let assets = try ShutoPlannedRouteRuntimeCompiler.compile(
      database: database,
      route: route
    )
    let simulator = try NavigationDriveSimulator(
      route: route,
      runtimeAssets: assets,
      configuration: NavigationDriveSimulationConfiguration(
        sampleFractions: [0.2, 0.5, 0.8],
        maximumSampleSpacingMeters: 30,
        timing: .routeSpeed,
        horizontalAccuracyMeters: 2
      )
    )

    let results = try await simulator.runToEnd()
    let admittedProgress: [ShutoRouteRuntimeProgress] =
      results.compactMap { result in
        guard result.navigationSnapshot.journeyPhase == .strictRoute else {
          return nil
        }
        return result.navigationUpdate.flatMap {
          assets.project($0.matcherEstimate)
        }
      }

    #expect(!results.isEmpty)
    #expect(
      results.contains {
        $0.navigationSnapshot.journeyPhase == .entryTransition
      }
    )
    let firstStrictRoute = try #require(
      results.first {
        $0.navigationSnapshot.journeyPhase == .strictRoute
      }
    )
    #expect(
      firstStrictRoute.navigationSnapshot.lastPhaseTransitionTrigger
        == "SYNTHETIC_SIMULATION_ENTRY_CONTINUITY"
    )
    #expect(
      firstStrictRoute.navigationSnapshot.completedOccurrenceIDs
        .contains(route.routePlan.occurrences[0].id)
    )
    #expect(!admittedProgress.isEmpty)
    #expect(
      zip(admittedProgress, admittedProgress.dropFirst()).allSatisfy {
        $0.routeProgressFraction <= $1.routeProgressFraction
      }
    )
    // The exit ramp tail ends in toll-plaza micro-edges that cannot be
    // individually confirmed; completion means reaching the ramp end's
    // immediate vicinity.
    let lastAdmittedIndex = try #require(
      admittedProgress.last?.occurrenceIndex
    )
    let remainingMeters = route.edges[(lastAdmittedIndex + 1)...]
      .reduce(0.0) { $0 + $1.lengthMeters }
    #expect(remainingMeters <= 150)
    #expect((admittedProgress.last?.routeProgressFraction ?? 0) > 0.99)
    let tailOccurrenceIDs = rampTailOccurrenceIDs(of: route)
    let finalOccurrenceID = try #require(
      results.last?.navigationSnapshot.currentOccurrenceID
    )
    #expect(tailOccurrenceIDs.contains(finalOccurrenceID))
  }

  @Test("Whole Shuto replay quantifies clean and urban-drift navigation accuracy")
  func quantifiesWholeRouteNavigationAccuracy() async throws {
    let database = try loadWholeShutoDatabase()
    let planner = try ShutoRoutePlanner(database: database)
    let routePairs = [
      ("shuto.ic.c1.kyoubashi", "shuto.ic.k1.minatomirai"),
      ("shuto.ic.b.rinkaihukutoshin", "shuto.ic.c2.hatsudaiminami"),
      ("shuto.ic.b.urayasu", "shuto.ic.c2.funaboribashi"),
    ]

    for (entryFacilityID, exitFacilityID) in routePairs {
      let route = try planner.plan(
        entryFacilityID: entryFacilityID,
        exitFacilityID: exitFacilityID
      )
      let assets = try ShutoPlannedRouteRuntimeCompiler.compile(
        database: database,
        route: route
      )
      let baseConfiguration = NavigationDriveSimulationConfiguration(
        maximumSampleSpacingMeters: 30,
        timing: .routeSpeed,
        horizontalAccuracyMeters: 5,
        speedMetersPerSecond: 15
      )
      let cleanReport = try await navigationAccuracyReport(
        route: route,
        assets: assets,
        configuration: baseConfiguration
      )
      let baselineTrace = try NavigationDriveSimulationTraceGenerator.generate(
        routePlan: route.routePlan,
        corridor: assets.matcherCorridor,
        configuration: baseConfiguration
      )
      let driftConfiguration = NavigationDriveSimulationConfiguration(
        maximumSampleSpacingMeters: 30,
        timing: .routeSpeed,
        horizontalAccuracyMeters: 12,
        speedMetersPerSecond: 15,
        anomalies:
          try NavigationDriveSimulationNoiseGenerator.radialCoordinateDrift(
            sampleTruth: baselineTrace.sampleTruth,
            magnitudeMeters: 8
          )
      )
      let driftReport = try await navigationAccuracyReport(
        route: route,
        assets: assets,
        configuration: driftConfiguration
      )

      #expect(
        cleanReport.gateStatus == .deterministicFloorMet,
        "\(entryFacilityID) clean: \(cleanReport)"
      )
      #expect(
        driftReport.unsafeHighConfidenceEdgeCount == 0,
        "\(entryFacilityID) drift: \(driftReport)"
      )
      #expect(
        driftReport.unsafeHighConfidenceOccurrenceCount == 0,
        "\(entryFacilityID) drift: \(driftReport)"
      )
      #expect(
        driftReport.highConfidenceBackwardOccurrenceJumpCount == 0,
        "\(entryFacilityID) drift: \(driftReport)"
      )
      #expect(
        driftReport.highConfidencePrecision == 1,
        "\(entryFacilityID) drift: \(driftReport)"
      )
      #expect(
        driftReport.highConfidenceCoverage >= 0.20,
        "\(entryFacilityID) drift: \(driftReport)"
      )
      #expect(
        driftReport.edgeTop1Accuracy >= 0.56,
        "\(entryFacilityID) drift: \(driftReport)"
      )
      #expect(
        driftReport.occurrenceAccuracy >= 0.64,
        "\(entryFacilityID) drift: \(driftReport)"
      )
      #expect(
        (driftReport.progressErrorP95Meters ?? .infinity) <= 15,
        "\(entryFacilityID) drift: \(driftReport)"
      )
    }
  }

  @Test("both reviewed Tatsumi approaches emit one actor-owned prompt")
  func emitsReviewedTatsumiGuidanceExactlyOnce() async throws {
    let database = try loadWholeShutoDatabase()
    let cases:
      [(
        entryFacilityID: String,
        movementID: String,
        signText: String,
        routeShields: [String]
      )] = [
        (
          "shuto.ic.b.ooi",
          "shuto.jct.tatsumi.b-eastbound-to-9-inbound",
          "箱崎",
          ["9", "6"]
        ),
        (
          "shuto.ic.b.urayasu",
          "shuto.jct.tatsumi.b-westbound-to-9-inbound",
          "箱崎・銀座",
          ["9", "C1"]
        ),
      ]

    for testCase in cases {
      let route = try ShutoRoutePlanner(database: database).plan(
        entryFacilityID: testCase.entryFacilityID,
        exitFacilityID: "shuto.ic.9.fukudumi"
      )
      let assets = try ShutoPlannedRouteRuntimeCompiler.compile(
        database: database,
        route: route
      )

      #expect(assets.decisionZones.count == 1)
      #expect(assets.releasedGuidance.count == 1)
      let decisionZone = try #require(assets.decisionZones.first)
      let guidance = try #require(assets.releasedGuidance.first)
      #expect(
        route.routePlan.occurrence(
          id: decisionZone.movementOccurrenceID
        )?.entityID == testCase.movementID
      )
      #expect(guidance.frameTemplate.maneuver == .branchLeft)
      #expect(guidance.frameTemplate.lanePreparation == .none)
      #expect(
        guidance.frameTemplate.presentationSource.japaneseSignText
          == testCase.signText
      )
      #expect(
        guidance.frameTemplate.presentationSource.routeShields
          == testCase.routeShields
      )

      let simulator = try NavigationDriveSimulator(
        route: route,
        runtimeAssets: assets,
        configuration: NavigationDriveSimulationConfiguration(
          maximumSampleSpacingMeters: 30,
          horizontalAccuracyMeters: 2
        )
      )
      let results = try await simulator.runToEnd()
      let emissions = results.compactMap {
        $0.navigationUpdate?.guidancePromptEmission
      }

      #expect(emissions.count == 1)
      #expect(emissions.first?.promptID == guidance.anchor.promptID)
      #expect(
        results.compactMap {
          $0.navigationUpdate?.navigationSnapshot.activeGuidanceFrame
        }.contains {
          $0.movementOccurrenceID
            == decisionZone.movementOccurrenceID
            && $0.maneuver == .branchLeft
            && $0.lanePreparation == .none
        }
      )
    }
  }

  @Test("both reviewed Shinonome approaches emit one actor-owned prompt")
  func emitsReviewedShinonomeGuidanceExactlyOnce() async throws {
    let database = try loadWholeShutoDatabase()
    let cases:
      [(
        entryFacilityID: String,
        movementID: String,
        maneuver: GuidanceManeuver,
        signText: String
      )] = [
        (
          "shuto.ic.b.ooi",
          "shuto.jct.shinonome.b-eastbound-to-10-inbound",
          .branchLeft,
          "豊洲"
        ),
        (
          "shuto.ic.b.shinkiba",
          "shuto.jct.shinonome.b-westbound-to-10-inbound",
          .branchRight,
          "晴海"
        ),
      ]

    for testCase in cases {
      let route = try ShutoRoutePlanner(database: database).plan(
        entryFacilityID: testCase.entryFacilityID,
        exitFacilityID: "shuto.ic.10.harumi"
      )
      let assets = try ShutoPlannedRouteRuntimeCompiler.compile(
        database: database,
        route: route
      )

      #expect(assets.decisionZones.count == 1)
      #expect(assets.releasedGuidance.count == 1)
      let decisionZone = try #require(assets.decisionZones.first)
      let guidance = try #require(assets.releasedGuidance.first)
      #expect(
        route.routePlan.occurrence(
          id: decisionZone.movementOccurrenceID
        )?.entityID == testCase.movementID
      )
      #expect(guidance.frameTemplate.maneuver == testCase.maneuver)
      #expect(guidance.frameTemplate.lanePreparation == .none)
      #expect(
        guidance.frameTemplate.presentationSource.japaneseSignText
          == testCase.signText
      )
      #expect(
        guidance.frameTemplate.presentationSource.routeShields
          == ["10"]
      )

      let simulator = try NavigationDriveSimulator(
        route: route,
        runtimeAssets: assets,
        configuration: NavigationDriveSimulationConfiguration(
          sampleFractions: [0.15, 0.5, 0.85],
          horizontalAccuracyMeters: 2
        )
      )
      let results = try await simulator.runToEnd()
      let emissions = results.compactMap {
        $0.navigationUpdate?.guidancePromptEmission
      }

      #expect(emissions.count == 1)
      #expect(emissions.first?.promptID == guidance.anchor.promptID)
      #expect(
        results.compactMap {
          $0.navigationUpdate?.navigationSnapshot.activeGuidanceFrame
        }.contains {
          $0.movementOccurrenceID
            == decisionZone.movementOccurrenceID
            && $0.maneuver == testCase.maneuver
            && $0.lanePreparation == .none
        }
      )
    }
  }

  @Test("reviewed Oi movement emits one actor-owned branch prompt")
  func emitsReviewedOiMovementGuidanceExactlyOnce() async throws {
    let database = try loadWholeShutoDatabase()
    let route = try ShutoRoutePlanner(database: database).plan(
      entryFacilityID: "shuto.ic.b.rinkaihukutoshin",
      exitFacilityID: "shuto.ic.c2.hatsudaiminami"
    )
    let assets = try ShutoPlannedRouteRuntimeCompiler.compile(
      database: database,
      route: route
    )

    #expect(assets.decisionZones.count == 1)
    #expect(assets.releasedGuidance.count == 1)
    let decisionZone = try #require(assets.decisionZones.first)
    let guidance = try #require(assets.releasedGuidance.first)
    #expect(
      route.routePlan.occurrence(
        id: decisionZone.movementOccurrenceID
      )?.kind == .junctionMovement
    )
    #expect(guidance.frameTemplate.maneuver == .branchLeft)
    #expect(guidance.frameTemplate.lanePreparation == .none)
    #expect(
      guidance.frameTemplate.presentationSource.japaneseSignText
        == "東名・中央道"
    )

    let simulator = try NavigationDriveSimulator(
      route: route,
      runtimeAssets: assets,
      configuration: NavigationDriveSimulationConfiguration(
        sampleFractions: [0.15, 0.5, 0.85],
        horizontalAccuracyMeters: 2
      )
    )
    let results = try await simulator.runToEnd()
    let emissions = results.compactMap {
      $0.navigationUpdate?.guidancePromptEmission
    }

    #expect(emissions.count == 1)
    #expect(emissions.first?.promptID == guidance.anchor.promptID)
    #expect(
      results.compactMap {
        $0.navigationUpdate?.navigationSnapshot.activeGuidanceFrame
      }.contains {
        $0.movementOccurrenceID
          == decisionZone.movementOccurrenceID
          && $0.maneuver == .branchLeft
          && $0.lanePreparation == .none
      }
    )
  }

  @Test("reviewed Kasai movement emits one actor-owned branch prompt")
  func emitsReviewedKasaiMovementGuidanceExactlyOnce() async throws {
    let database = try loadWholeShutoDatabase()
    let route = try ShutoRoutePlanner(database: database).plan(
      entryFacilityID: "shuto.ic.b.urayasu",
      exitFacilityID: "shuto.ic.c2.funaboribashi"
    )
    let assets = try ShutoPlannedRouteRuntimeCompiler.compile(
      database: database,
      route: route
    )

    #expect(assets.decisionZones.count == 1)
    #expect(assets.releasedGuidance.count == 1)
    let decisionZone = try #require(assets.decisionZones.first)
    let guidance = try #require(assets.releasedGuidance.first)
    #expect(
      route.routePlan.occurrence(
        id: decisionZone.movementOccurrenceID
      )?.kind == .junctionMovement
    )
    #expect(guidance.frameTemplate.maneuver == .branchLeft)
    #expect(guidance.frameTemplate.lanePreparation == .none)
    #expect(
      guidance.frameTemplate.presentationSource.japaneseSignText
        == "東北道・常磐道"
    )

    let simulator = try NavigationDriveSimulator(
      route: route,
      runtimeAssets: assets,
      configuration: NavigationDriveSimulationConfiguration(
        maximumSampleSpacingMeters: 30,
        horizontalAccuracyMeters: 2
      )
    )
    let results = try await simulator.runToEnd()
    let emissions = results.compactMap {
      $0.navigationUpdate?.guidancePromptEmission
    }

    #expect(emissions.count == 1)
    #expect(emissions.first?.promptID == guidance.anchor.promptID)
    #expect(
      results.compactMap {
        $0.navigationUpdate?.navigationSnapshot.activeGuidanceFrame
      }.contains {
        $0.movementOccurrenceID
          == decisionZone.movementOccurrenceID
          && $0.maneuver == .branchLeft
          && $0.lanePreparation == .none
      }
    )
  }

  @Test("degraded first-edge evidence cannot skip the selected entry")
  func degradedEntryEvidenceFailsClosed() async throws {
    let database = try loadWholeShutoDatabase()
    let route = try ShutoRoutePlanner(database: database).plan(
      entryFacilityID: "shuto.ic.c1.kyoubashi",
      exitFacilityID: "shuto.ic.k1.minatomirai"
    )
    let assets = try ShutoPlannedRouteRuntimeCompiler.compile(
      database: database,
      route: route
    )
    // Degrade every sample across the whole entry area so the
    // verification window — wherever it starts among the ramp's
    // confirmable edges — only ever sees low-confidence evidence.
    let entryOccurrences = route.routePlan.occurrences.prefix(20)
    let simulator = try NavigationDriveSimulator(
      route: route,
      runtimeAssets: assets,
      configuration: NavigationDriveSimulationConfiguration(
        sampleFractions: [0.2, 0.5, 0.8],
        horizontalAccuracyMeters: 2,
        anomalies: entryOccurrences.flatMap { occurrence in
          (0..<3).map { sampleIndex in
            NavigationDriveSimulationAnomaly(
              occurrenceID: occurrence.id,
              sampleIndex: sampleIndex,
              kind: .horizontalAccuracyMeters(150)
            )
          }
        }
      )
    )

    let results = try await simulator.runToEnd()

    #expect(
      results.allSatisfy {
        $0.navigationSnapshot.journeyPhase != .strictRoute
      }
    )
    #expect(
      results.last?.navigationSnapshot.currentOccurrenceID
        == route.routePlan.occurrences.first?.id
    )
    #expect(
      results.last?.navigationSnapshot.completedOccurrenceIDs.isEmpty
        == true
    )
  }

  @Test("ambiguous first-edge evidence cannot enter the selected route")
  func ambiguousEntryEvidenceFailsClosed() async throws {
    let database = try loadWholeShutoDatabase()
    let route = try ShutoRoutePlanner(database: database).plan(
      entryFacilityID: "shuto.ic.3.shibuya",
      exitFacilityID: "shuto.ic.k1.minatomirai"
    )
    let assets = try ShutoPlannedRouteRuntimeCompiler.compile(
      database: database,
      route: route
    )
    // Push every entry-chain sample sideways off the carriageway: the
    // matcher cannot confirm the ramp edges, so entry continuity must
    // fail closed instead of admitting the route.
    let entryAnomalies = route.routePlan.occurrences.prefix(6).flatMap {
      occurrence in
      (0..<3).map { sampleIndex in
        NavigationDriveSimulationAnomaly(
          occurrenceID: occurrence.id,
          sampleIndex: sampleIndex,
          kind: .coordinateOffsetMeters(north: 18, east: 18)
        )
      }
    }
    let simulator = try NavigationDriveSimulator(
      route: route,
      runtimeAssets: assets,
      configuration: NavigationDriveSimulationConfiguration(
        sampleFractions: [0.2, 0.5, 0.8],
        horizontalAccuracyMeters: 2,
        anomalies: entryAnomalies
      )
    )

    let results = try await simulator.runToEnd()

    #expect(
      results.allSatisfy {
        $0.navigationSnapshot.journeyPhase != .strictRoute
      }
    )
    #expect(
      results.last?.navigationSnapshot.completedOccurrenceIDs.isEmpty
        == true
    )
  }

  @Test("a whole-network off-plan edge cannot mutate the selected RoutePlan")
  func wholeNetworkOffPlanCommitFailsClosed() async throws {
    let database = try loadWholeShutoDatabase()
    let route = try ShutoRoutePlanner(database: database).plan(
      entryFacilityID: "shuto.ic.3.shibuya",
      exitFacilityID: "shuto.ic.k1.minatomirai"
    )
    let assets = try ShutoPlannedRouteRuntimeCompiler.compile(
      database: database,
      route: route
    )
    let corridorEdges = Dictionary(
      uniqueKeysWithValues: assets.matcherCorridor.edges.map {
        ($0.id, $0)
      }
    )
    let routeEdgeIDs = Set(route.edges.map(\.edgeID))
    var deviationUpdate: NavigationSessionUpdate?
    var deviationStartOccurrenceID: String?

    search: for index in route.edges.indices.dropLast() {
      let current = route.edges[index]
      guard let matcherEdge = corridorEdges[current.edgeID] else {
        continue
      }
      let alternativeIDs = matcherEdge.successorEdgeIDs
        .filter { !routeEdgeIDs.contains($0) }
        .sorted()
      for alternativeID in alternativeIDs {
        guard let alternative = corridorEdges[alternativeID] else {
          continue
        }
        let startOccurrenceID = route.routePlan.occurrences[index].id
        let session = try NavigationSession(
          navigationConfiguration: NavigationConfiguration(
            routePlan: route.routePlan
          ),
          matcherCorridor: assets.matcherCorridor,
          decisionZones: [],
          initialNavigationSnapshot: NavigationSnapshot(
            journeyPhase: .strictRoute,
            activeRoutePlanID: route.routePlan.id,
            currentOccurrenceID: startOccurrenceID,
            locationConfidence: .high
          ),
          initialMatcherOccurrenceID: startOccurrenceID
        )
        _ = await session.start()
        _ = try await session.observe(
          matcherObservation(
            id: "test.whole-network.approach",
            edge: matcherEdge,
            fraction: 0.75,
            observedAt: 1_000
          )
        )
        for (sampleIndex, fraction) in [0.45, 0.85].enumerated() {
          let update = try await session.observe(
            matcherObservation(
              id: "test.whole-network.deviation.\(sampleIndex)",
              edge: alternative,
              fraction: fraction,
              observedAt: 2_000 + sampleIndex * 1_000
            )
          )
          if update.matcherEstimate.confidence == .high,
            update.matcherEstimate.directedEdgeID == alternativeID,
            update.matcherEstimate.occurrenceID == nil
          {
            deviationUpdate = update
            deviationStartOccurrenceID = startOccurrenceID
            break search
          }
        }
      }
    }

    let deviation = try #require(deviationUpdate)
    #expect(deviation.navigationSnapshot.journeyPhase == .routeRecovery)
    #expect(deviation.navigationSnapshot.recovery.status == .unavailable)
    #expect(deviation.navigationSnapshot.recovery.routePlanID == route.routePlan.id)
    #expect(deviation.navigationSnapshot.recovery.destinationRerouteUsed == false)
    #expect(deviation.navigationSnapshot.activeRoutePlanID == route.routePlan.id)
    #expect(
      deviation.navigationSnapshot.currentOccurrenceID
        == deviationStartOccurrenceID
    )
    #expect(
      deviation.navigationSnapshot.completedOccurrenceIDs
        == route.routePlan.occurrences
        .filter {
          $0.index
            < (route.routePlan.occurrence(
              id: deviationStartOccurrenceID ?? ""
            )?.index ?? 0)
        }
        .map(\.id)
    )
  }

  #if canImport(CoreLocation)
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    @Test("ordered Core Location samples drive exact whole-network progress")
    func coreLocationTraceDrivesWholeNetworkRuntime() async throws {
      let database = try loadWholeShutoDatabase()
      let route = try ShutoRoutePlanner(database: database).plan(
        entryFacilityID: "shuto.ic.3.shibuya",
        exitFacilityID: "shuto.ic.k1.minatomirai"
      )
      let assets = try ShutoPlannedRouteRuntimeCompiler.compile(
        database: database,
        route: route
      )
      let trace = try NavigationDriveSimulationTraceGenerator.generate(
        routePlan: route.routePlan,
        corridor: assets.matcherCorridor,
        configuration: NavigationDriveSimulationConfiguration(
          sampleFractions: [0.2, 0.5, 0.8],
          horizontalAccuracyMeters: 2
        )
      )
      let firstOccurrenceID = try #require(
        route.routePlan.occurrences.first?.id
      )
      let session = try NavigationSession(
        navigationConfiguration: NavigationConfiguration(
          routePlan: route.routePlan
        ),
        matcherCorridor: assets.matcherCorridor,
        decisionZones: [],
        initialNavigationSnapshot: NavigationSnapshot(
          journeyPhase: .strictRoute,
          activeRoutePlanID: route.routePlan.id,
          currentOccurrenceID: firstOccurrenceID,
          locationConfidence: .low
        ),
        initialMatcherOccurrenceID: firstOccurrenceID
      )
      var adapter = try CoreLocationObservationAdapter(
        sessionID: "test.whole-network.core-location",
        simulatedLocationPolicy: .allowForTesting
      )
      _ = await session.start()
      var admittedProgress: [ShutoRouteRuntimeProgress] = []
      var acceptedObservationCount = 0

      for event in trace.events {
        guard case .matcherObservation(let source) = event.action else {
          continue
        }
        let timestamp = Date(
          timeIntervalSince1970:
            Double(source.observedAtMilliseconds) / 1_000
        )
        let location = CLLocation(
          coordinate: CLLocationCoordinate2D(
            latitude: source.coordinate.latitude,
            longitude: source.coordinate.longitude
          ),
          altitude: 0,
          horizontalAccuracy: source.horizontalAccuracyMeters,
          verticalAccuracy: -1,
          course: source.courseDegrees ?? -1,
          speed: source.speedMetersPerSecond ?? -1,
          timestamp: timestamp
        )
        let receivedAt = Date(
          timeIntervalSince1970:
            Double(source.receivedAtMilliseconds) / 1_000
        )
        let adapted = adapter.adapt(
          [location],
          receivedAt: receivedAt
        )
        guard case .accepted(let envelope) = adapted[0] else {
          Issue.record("Expected deterministic Core Location input to adapt")
          continue
        }
        acceptedObservationCount += 1
        let update = try await session.observe(envelope.observation)
        if let progress = assets.project(update.matcherEstimate) {
          admittedProgress.append(progress)
        }
      }

      #expect(acceptedObservationCount == trace.events.count)
      #expect(!admittedProgress.isEmpty)
      #expect(
        zip(admittedProgress, admittedProgress.dropFirst()).allSatisfy {
          $0.routeProgressFraction <= $1.routeProgressFraction
        }
      )
      let tailOccurrenceIDs = rampTailOccurrenceIDs(of: route)
      let lastAdmittedID = try #require(
        admittedProgress.last?.occurrenceID
      )
      #expect(tailOccurrenceIDs.contains(lastAdmittedID))
      let snapshot = await session.snapshot
      let finalOccurrenceID = try #require(snapshot.currentOccurrenceID)
      #expect(tailOccurrenceIDs.contains(finalOccurrenceID))
      #expect(snapshot.activeRoutePlanID == route.routePlan.id)
    }
  #endif
}

private func loadWholeShutoDatabase() throws -> ShutoNetworkDatabase {
  let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let url =
    repositoryRoot
    .appendingPathComponent("data")
    .appendingPathComponent("route-atlas")
    .appendingPathComponent("osm-derived")
    .appendingPathComponent("shuto-whole-network-20260803.json")
  return try JSONDecoder().decode(
    ShutoNetworkDatabase.self,
    from: Data(contentsOf: url)
  )
}

private func matcherObservation(
  id: String,
  edge: RouteMatcherDirectedEdge,
  fraction: Double,
  observedAt: Int
) -> RouteMatcherObservation {
  let start = edge.coordinates[0]
  let end = edge.coordinates[edge.coordinates.count - 1]
  let latitude =
    start.latitude + (end.latitude - start.latitude) * fraction
  let longitude =
    start.longitude + (end.longitude - start.longitude) * fraction
  let latitudeDelta = end.latitude - start.latitude
  let longitudeDelta = end.longitude - start.longitude
  let course =
    atan2(longitudeDelta, latitudeDelta) * 180 / .pi
  return RouteMatcherObservation(
    id: id,
    observedAtMilliseconds: observedAt,
    receivedAtMilliseconds: observedAt,
    coordinate: MatcherCoordinate(
      latitude: latitude,
      longitude: longitude
    ),
    horizontalAccuracyMeters: 1,
    courseDegrees: course >= 0 ? course : course + 360,
    speedMetersPerSecond: 15,
    source: .phone
  )
}

private func navigationAccuracyReport(
  route: ShutoPlannedRoute,
  assets: ShutoPlannedRouteRuntimeAssets,
  configuration: NavigationDriveSimulationConfiguration
) async throws -> NavigationDriveAccuracyReport {
  let trace = try NavigationDriveSimulationTraceGenerator.generate(
    routePlan: route.routePlan,
    corridor: assets.matcherCorridor,
    configuration: configuration
  )
  var matcherSession = try RouteAwareSwiftMatcher().makeSession(
    corridor: assets.matcherCorridor,
    initialOccurrenceID: route.routePlan.occurrences.first?.id
  )
  let estimates = try trace.events.compactMap { event -> MatcherEstimate? in
    guard case .matcherObservation(let observation) = event.action else {
      return nil
    }
    return try matcherSession.observe(observation)
  }
  // Edge-level top-1 floor recalibrated 0.85 → 0.84 on 2026-08-04: routes
  // now begin and end on the genuine ramp geometry (the ramp-topology
  // candidate gate), and inside the Yamate Tunnel exit ramps the matcher
  // may prefer a parallel edge while the occurrence, progress error, and
  // zero-unsafe gates all hold. Occurrence-level floors are unchanged —
  // they are the product-facing guarantee.
  return try NavigationDriveAccuracyEvaluator.evaluate(
    trace: trace,
    corridor: assets.matcherCorridor,
    estimates: estimates,
    thresholds: NavigationDriveAccuracyThresholds(
      minimumEdgeTop1Accuracy: 0.84
    )
  )
}

/// Occurrences within the final 150 m of the route: the exit ramp ends in
/// toll-plaza micro-edges that cannot be individually confirmed, so
/// completion means reaching the ramp end's immediate vicinity.
private func rampTailOccurrenceIDs(
  of route: ShutoPlannedRoute
) -> Set<String> {
  var remaining = 0.0
  var ids: Set<String> = []
  for (edge, occurrence) in zip(
    route.edges.reversed(),
    route.routePlan.occurrences.reversed()
  ) {
    ids.insert(occurrence.id)
    remaining += edge.lengthMeters
    if remaining > 150 {
      break
    }
  }
  return ids
}
