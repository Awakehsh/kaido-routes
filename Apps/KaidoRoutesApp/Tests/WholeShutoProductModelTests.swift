import KaidoAppleAdapters
import KaidoDomain
import KaidoNavigation
import KaidoPresentation
import KaidoRouting
import KaidoSurfaceRouting
import XCTest

@testable import KaidoRoutesApp

@MainActor
final class WholeShutoProductModelTests: XCTestCase {
  func testPlanningAndResetUseTheNetworkDiagram() {
    let model = WholeShutoProductModel(checkpointStore: nil)

    XCTAssertEqual(model.phase, .planning)
    XCTAssertEqual(model.mapMode, .network)

    model.preparePreviewJourney()
    model.mapMode = .geographic
    model.reset()

    XCTAssertEqual(model.phase, .planning)
    XCTAssertEqual(model.mapMode, .network)
  }

  func testLiveDriveRunsOnRealPositionsWithoutTransportControls() throws {
    let model = WholeShutoProductModel(checkpointStore: nil)
    model.preparePreviewJourney()
    XCTAssertEqual(model.phase, .review)
    XCTAssertTrue(model.isJourneyReadyForPreview)

    XCTAssertTrue(model.startLiveJourney())
    XCTAssertTrue(model.isLiveDrive)
    XCTAssertEqual(model.phase, .surfaceAccess)

    // A live drive follows the vehicle: stepping and pausing are inert.
    model.togglePlayback()
    XCTAssertTrue(model.isPlaying)
    model.advanceSimulation()
    XCTAssertEqual(model.phase, .surfaceAccess)

    // Reaching the ramp mouth hands the surface leg over to entry.
    let route = try XCTUnwrap(model.selectedRoute)
    let entry = try XCTUnwrap(route.coordinates.first)
    model.consumeLiveObservation(
      Self.liveObservation(at: entry, atMilliseconds: 1_000)
    )
    XCTAssertEqual(model.phase, .entryTransition)

    // Starting the labeled preview afterwards leaves live mode.
    model.reset()
    model.preparePreviewJourney()
    model.startNavigationSimulation()
    XCTAssertFalse(model.isLiveDrive)
  }

  func testFirstLaunchInterfaceLanguageFollowsTheDevice() {
    XCTAssertEqual(
      KaidoReleaseLocale.matchingPreferredLanguage(["ja-JP", "en-US"]),
      .japanese
    )
    XCTAssertEqual(
      KaidoReleaseLocale.matchingPreferredLanguage(["zh-Hans-CN"]),
      .simplifiedChinese
    )
    // Traditional Chinese is not authored: English beats a script mismatch.
    XCTAssertEqual(
      KaidoReleaseLocale.matchingPreferredLanguage(["zh-Hant-TW"]),
      .english
    )
    XCTAssertEqual(
      KaidoReleaseLocale.matchingPreferredLanguage(["de-DE", "ja-JP"]),
      .japanese
    )
    XCTAssertEqual(
      KaidoReleaseLocale.matchingPreferredLanguage(["ko-KR"]),
      .english
    )
  }

  private static func liveObservation(
    at coordinate: ShutoCoordinate,
    atMilliseconds: Int
  ) -> RouteMatcherObservation {
    RouteMatcherObservation(
      observedAtMilliseconds: atMilliseconds,
      receivedAtMilliseconds: atMilliseconds,
      coordinate: MatcherCoordinate(
        latitude: coordinate.latitude,
        longitude: coordinate.longitude
      ),
      horizontalAccuracyMeters: 5,
      speedMetersPerSecond: 15,
      source: .phone
    )
  }

  func testCustomRouteFromTheHomeCatalogIsARoundTrip() {
    let model = WholeShutoProductModel(checkpointStore: nil)
    // Tokyo Tower: the nearest enterable facility seeds the draft.
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6586, longitude: 139.7454)
    )
    model.prepareCustomRouteDraft()

    XCTAssertNotNil(model.customEntryFacilityID)
    XCTAssertNotNil(model.customExitFacilityID)
    XCTAssertNotNil(model.customDraftRoute)

    XCTAssertTrue(model.applyCustomRoute())
    XCTAssertEqual(model.phase, .review)
    XCTAssertTrue(model.isCustomRouteSelected)
    XCTAssertEqual(
      model.destination?.coordinate,
      model.origin?.coordinate
    )
  }

  func testCircuitSelectionDerivesThePairingFromOrigin() async {
    let model = WholeShutoProductModel(checkpointStore: nil)
    // Near Hatsudai, west side of the C2 loop.
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6798, longitude: 139.6862)
    )

    model.selectCircuit(.c2InnerWithBayshore)
    await waitForCircuitPairing(model)

    XCTAssertEqual(
      model.selectedCircuit?.circuitID,
      "shuto.circuit.c2-inner-bayshore"
    )
    XCTAssertEqual(model.circuitLaps, 1)
    // The nearest legal start is the Hatsudai radial entrance joining the
    // loop through the all-directions Nishi-Shinjuku JCT; the exit is
    // derived too — the driver never assembles a pairing.
    XCTAssertEqual(
      model.circuitEntryFacilityID,
      "shuto.ic.4.hatsudai"
    )
    XCTAssertNotNil(model.circuitExitFacilityID)
    XCTAssertEqual(model.circuitPairingBand?.quotedYen, 300)
    // Radial entrances that legally join the loop are first-class
    // candidates alongside the loop's own inner ramps.
    XCTAssertTrue(
      model.circuitEntranceCandidates.allSatisfy { $0.canEnter }
    )
  }

  private func waitForCircuitPairing(
    _ model: WholeShutoProductModel
  ) async {
    for _ in 0..<200
    where model.isResolvingCircuitPairing
      || model.circuitExitFacilityID == nil
    {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }
  }

  func testCircuitEntranceTariffBandsResolveFromDatedEvidence() async {
    let model = WholeShutoProductModel(checkpointStore: nil)
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6798, longitude: 139.6862)
    )

    model.selectCircuit(.c2InnerWithBayshore)
    for _ in 0..<200 where model.circuitTariffBandsByFacilityID.isEmpty {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }

    // The Hatsudai-minami pairing exits at Tomigaya just ahead, so the
    // tariff distance stays in the minimum band regardless of laps.
    XCTAssertEqual(
      model.circuitTariffBandsByFacilityID["shuto.ic.c2.hatsudaiminami"],
      .minimum(yen: 300)
    )
  }

  func testCircuitJourneyIsARoundTripThroughTheReviewGate() async {
    let model = WholeShutoProductModel(
      locationProvider: WholeShutoUnexpectedLocationProvider(),
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    let origin = ShutoCoordinate(latitude: 35.6798, longitude: 139.6862)
    model.selectCurrentOrigin(origin)
    model.selectCircuit(.c2InnerWithBayshore)
    model.selectCircuitLaps(2)
    await waitForCircuitPairing(model)

    XCTAssertTrue(model.startCircuitJourney())
    for _ in 0..<1_000 where model.isUpdatingSurfaceRoute {
      await Task.yield()
    }

    XCTAssertEqual(model.phase, .review)
    XCTAssertTrue(model.isCircuitRouteSelected)
    XCTAssertNil(model.failureCode)
    // Round trip: the origin doubles as the destination.
    XCTAssertEqual(model.destination?.coordinate, origin)
    XCTAssertNotNil(model.accessRoute)
    XCTAssertNotNil(model.egressRoute)
    guard let route = model.selectedRoute else {
      return XCTFail("Circuit journey selected no route")
    }
    // Two laps of the ~56 km circuit.
    XCTAssertGreaterThan(route.distanceMeters, 100_000)
    XCTAssertEqual(
      route.routePlan.entryFacilityID,
      "shuto.ic.4.hatsudai"
    )
    XCTAssertEqual(
      Set(route.routePlan.occurrences.map(\.id)).count,
      route.routePlan.occurrences.count
    )
    XCTAssertTrue(model.isJourneyReadyForPreview)
  }

  func testCircuitJourneyRestoresFromCheckpointAsCircuit() async {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(
      locationProvider: WholeShutoUnexpectedLocationProvider(),
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: store
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6798, longitude: 139.6862)
    )
    model.selectCircuit(.c2InnerWithBayshore)
    model.selectCircuitLaps(2)
    await waitForCircuitPairing(model)
    XCTAssertTrue(model.startCircuitJourney())
    for _ in 0..<1_000 where model.isUpdatingSurfaceRoute {
      await Task.yield()
    }
    let expectedRoutePlanID = model.selectedRoute?.routePlan.id
    XCTAssertNotNil(expectedRoutePlanID)

    let restored = WholeShutoProductModel(
      locationProvider: WholeShutoUnexpectedLocationProvider(),
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: store
    )

    XCTAssertTrue(restored.restoredFromCheckpoint)
    XCTAssertEqual(restored.phase, .review)
    XCTAssertTrue(restored.isCircuitRouteSelected)
    XCTAssertEqual(restored.circuitLaps, 2)
    XCTAssertEqual(
      restored.selectedCircuit?.circuitID,
      "shuto.circuit.c2-inner-bayshore"
    )
    XCTAssertEqual(
      restored.selectedRoute?.routePlan.id,
      expectedRoutePlanID
    )
  }

  func testResolvedDestinationPreviewIsExplicitAndResettable() {
    let model = WholeShutoProductModel(checkpointStore: nil)
    let destination = WholeShutoPlace(
      title: "东京塔",
      coordinate: ShutoCoordinate(
        latitude: 35.658581,
        longitude: 139.745433
      )
    )

    model.selectDestinationPreview(destination)

    XCTAssertEqual(model.destinationQuery, "东京塔")
    XCTAssertEqual(model.destination, destination)
    XCTAssertTrue(model.hasSelectedDestinationPreview)

    model.clearDestinationPreview()

    XCTAssertEqual(model.destinationQuery, "东京塔")
    XCTAssertNil(model.destination)
    XCTAssertFalse(model.hasSelectedDestinationPreview)
  }

  func testMeasuredCurrentOriginPlansWithoutASecondLocationRequest() async {
    let locationProvider = WholeShutoUnexpectedLocationProvider()
    let model = WholeShutoProductModel(
      locationProvider: locationProvider,
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    model.selectCurrentOrigin(
      WholeShutoProductModel.previewOrigin.coordinate
    )
    model.selectDestinationPreview(
      WholeShutoProductModel.previewDestination
    )

    model.planJourney()
    for _ in 0..<100 where model.isPlanning {
      await Task.yield()
    }

    XCTAssertFalse(model.isPlanning)
    XCTAssertEqual(model.phase, .review)
    XCTAssertEqual(
      model.origin?.coordinate,
      WholeShutoProductModel.previewOrigin.coordinate
    )
    XCTAssertEqual(locationProvider.requestCount, 0)
    XCTAssertNil(model.failureCode)
  }

  func testComparableSurfaceRoutesRefineChoiceWithoutChangingExactPlans()
    async throws
  {
    let baseline = WholeShutoProductModel(checkpointStore: nil)
    baseline.preparePreviewJourney()
    let originalRecommendations = baseline.recommendations
    let preferredRoute = try XCTUnwrap(
      originalRecommendations.last?.route
    )
    let resolver = WholeShutoRankingSurfaceRouteResolver(
      preferredEntry: preferredRoute.entryFacility.coordinate,
      preferredExit: preferredRoute.exitFacility.coordinate
    )
    let model = WholeShutoProductModel(
      database: baseline.database,
      locationProvider: WholeShutoUnexpectedLocationProvider(),
      surfaceRouteResolver: resolver,
      checkpointStore: nil
    )
    model.selectCurrentOrigin(
      WholeShutoProductModel.previewOrigin.coordinate
    )
    model.selectDestinationPreview(
      WholeShutoProductModel.previewDestination
    )

    model.planJourney()
    for _ in 0..<1_000 where model.isPlanning {
      await Task.yield()
    }

    XCTAssertFalse(model.isPlanning)
    XCTAssertFalse(model.isUpdatingSurfaceRoute)
    XCTAssertEqual(model.phase, .review)
    XCTAssertEqual(
      model.recommendations.first?.route.routePlan.id,
      preferredRoute.routePlan.id
    )
    XCTAssertEqual(
      Set(model.recommendations.map(\.route.routePlan.id)),
      Set(originalRecommendations.map(\.route.routePlan.id))
    )
    let originalPlans = Dictionary(
      uniqueKeysWithValues: originalRecommendations.map {
        ($0.route.routePlan.id, $0.route.routePlan)
      }
    )
    for recommendation in model.recommendations {
      XCTAssertEqual(
        recommendation.route.routePlan,
        originalPlans[recommendation.route.routePlan.id]
      )
      XCTAssertNotNil(
        model.routeChoiceMetricsByRoutePlanID[
          recommendation.route.routePlan.id
        ]
      )
    }
    XCTAssertEqual(
      model.accessRoute?.coordinates.last,
      preferredRoute.entryFacility.coordinate
    )
    XCTAssertEqual(
      model.egressRoute?.coordinates.first,
      preferredRoute.exitFacility.coordinate
    )
    XCTAssertTrue(model.isJourneyReadyForPreview)
    XCTAssertNil(model.failureCode)
  }

  func testIncompleteSurfaceComparisonKeepsDeterministicKaidoOrder()
    async throws
  {
    let model = WholeShutoProductModel(checkpointStore: nil)
    model.preparePreviewJourney()
    let originalRecommendations = model.recommendations
    let unavailableEntry = try XCTUnwrap(
      originalRecommendations.last?.route.entryFacility.coordinate
    )
    let evaluator = WholeShutoSurfaceRouteChoiceEvaluator(
      resolver: WholeShutoPartiallyUnavailableChoiceResolver(
        unavailableEntry: unavailableEntry
      )
    )

    let evaluation = await evaluator.evaluate(
      recommendations: originalRecommendations,
      origin: WholeShutoProductModel.previewOrigin.coordinate,
      destination: WholeShutoProductModel.previewDestination.coordinate
    )

    XCTAssertFalse(evaluation.usesComparableProviderMetrics)
    XCTAssertEqual(
      evaluation.recommendations.map(\.route.routePlan.id),
      originalRecommendations.map(\.route.routePlan.id)
    )
    XCTAssertLessThan(
      evaluation.surfaceRoutesByRoutePlanID.count,
      originalRecommendations.count
    )
  }

  func testCompletedJourneyPreviewKeepsTheArrivalSummaryUntilDone()
    throws
  {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: store)

    model.prepareCompletedJourneyPreview()

    XCTAssertEqual(model.phase, .completed)
    XCTAssertEqual(model.positionState, .completed)
    XCTAssertEqual(model.currentCoordinate, model.destination?.coordinate)
    XCTAssertEqual(model.remainingJourneyDistanceMeters, 0)
    XCTAssertGreaterThan(
      try XCTUnwrap(model.plannedJourneyDistanceMeters),
      try XCTUnwrap(model.selectedRoute?.distanceMeters)
    )
    XCTAssertFalse(model.isPlaying)
    XCTAssertNil(store.checkpoint)

    model.reset()

    XCTAssertEqual(model.phase, .planning)
    XCTAssertNil(model.selectedRoute)
    XCTAssertNil(model.destination)
  }

  func testJourneyReviewCombinesSurfaceAndExactShutoTiming() throws {
    let model = WholeShutoProductModel(checkpointStore: nil)

    model.preparePreviewJourney()

    let route = try XCTUnwrap(model.selectedRoute)
    let access = try XCTUnwrap(model.accessRoute)
    let egress = try XCTUnwrap(model.egressRoute)
    let expectedDuration =
      access.expectedTravelTimeSeconds
      + route.distanceMeters
      / WholeShutoProductModel.simulationReferenceSpeedMetersPerSecond
      + egress.expectedTravelTimeSeconds

    XCTAssertTrue(model.isJourneyReadyForPreview)
    XCTAssertEqual(
      try XCTUnwrap(model.plannedPreviewDurationSeconds),
      expectedDuration,
      accuracy: 0.001
    )
    XCTAssertEqual(
      try XCTUnwrap(model.plannedJourneyDistanceMeters),
      access.distanceMeters + route.distanceMeters + egress.distanceMeters,
      accuracy: 0.001
    )
    XCTAssertEqual(
      try XCTUnwrap(model.remainingPreviewDurationSeconds),
      expectedDuration,
      accuracy: 0.001
    )
    XCTAssertEqual(model.journeyProgressFraction, 0, accuracy: 0.001)
  }

  func testJourneyProgressIncludesSurfaceAndExpresswayLegs() async throws {
    let model = WholeShutoProductModel(checkpointStore: nil)
    model.preparePreviewJourney()

    let plannedDistance = try XCTUnwrap(model.plannedJourneyDistanceMeters)
    let plannedDuration = try XCTUnwrap(model.plannedPreviewDurationSeconds)

    model.startNavigationSimulation()
    model.togglePlayback()
    await model.advanceSimulationForTesting()

    XCTAssertEqual(model.phase, .surfaceAccess)
    XCTAssertEqual(model.progressFraction, 0.04, accuracy: 0.001)
    XCTAssertGreaterThan(model.journeyProgressFraction, 0)
    XCTAssertLessThan(model.journeyProgressFraction, 1)
    XCTAssertLessThan(
      try XCTUnwrap(model.remainingJourneyDistanceMeters),
      plannedDistance
    )
    XCTAssertLessThan(
      try XCTUnwrap(model.remainingPreviewDurationSeconds),
      plannedDuration
    )

    model.prepareCompletedJourneyPreview()

    XCTAssertEqual(model.journeyProgressFraction, 1, accuracy: 0.001)
    XCTAssertEqual(model.remainingPreviewDurationSeconds, 0)
  }

  func testUnavailableSurfaceLegsBlockPreviewUntilRetrySucceeds() async {
    let resolver = WholeShutoRecoveringSurfaceRouteResolver()
    let model = WholeShutoProductModel(
      surfaceRouteResolver: resolver,
      checkpointStore: nil
    )
    model.originQuery = "現在地"
    model.selectCurrentOrigin(
      WholeShutoProductModel.previewOrigin.coordinate
    )
    model.selectDestinationPreview(
      WholeShutoProductModel.previewDestination
    )

    model.planJourney()
    for _ in 0..<100 where model.isPlanning || model.isUpdatingSurfaceRoute {
      await Task.yield()
    }

    XCTAssertEqual(model.phase, .review)
    XCTAssertFalse(model.isJourneyReadyForPreview)
    XCTAssertEqual(model.failureCode, "SURFACE_ROUTE_UNAVAILABLE")

    model.startNavigationSimulation()

    XCTAssertEqual(model.phase, .review)
    XCTAssertFalse(model.isPlaying)

    await resolver.setAvailable(true)
    model.retrySurfaceRoutes()
    for _ in 0..<100 where model.isUpdatingSurfaceRoute {
      await Task.yield()
    }

    XCTAssertTrue(model.isJourneyReadyForPreview)
    XCTAssertNil(model.failureCode)
    XCTAssertNotNil(model.accessRoute)
    XCTAssertNotNil(model.egressRoute)
  }

  func testLatestRouteSelectionOwnsSurfacePreviewAfterOutOfOrderResponses()
    async
  {
    let resolver = WholeShutoOutOfOrderSurfaceRouteResolver()
    let model = WholeShutoProductModel(
      surfaceRouteResolver: resolver,
      checkpointStore: nil
    )
    model.preparePreviewJourney()
    XCTAssertGreaterThanOrEqual(model.recommendations.count, 3)

    let slowRoute = model.recommendations[1].route
    let latestRoute = model.recommendations[2].route
    await resolver.configure(
      slowEntry: slowRoute.coordinates.first
        ?? slowRoute.entryFacility.coordinate,
      slowExit: slowRoute.coordinates.last
        ?? slowRoute.exitFacility.coordinate
    )

    model.selectRecommendation(at: 1)
    XCTAssertTrue(model.isUpdatingSurfaceRoute)
    XCTAssertNil(model.accessRoute)
    XCTAssertNil(model.egressRoute)

    model.selectRecommendation(at: 2)
    try? await Task.sleep(nanoseconds: 80_000_000)

    XCTAssertEqual(model.selectedRecommendationIndex, 2)
    XCTAssertFalse(model.isUpdatingSurfaceRoute)
    // Surface legs land on the plan's own directional ramp mouths, not
    // the IC representative points.
    XCTAssertEqual(
      model.accessRoute?.coordinates.last,
      latestRoute.coordinates.first
    )
    XCTAssertEqual(
      model.egressRoute?.coordinates.first,
      latestRoute.coordinates.last
    )

    try? await Task.sleep(nanoseconds: 180_000_000)

    XCTAssertEqual(
      model.accessRoute?.coordinates.last,
      latestRoute.coordinates.first
    )
    XCTAssertEqual(
      model.egressRoute?.coordinates.first,
      latestRoute.coordinates.last
    )
  }

  func testCustomRoutePinsExactDirectionalEntryAndExit() async throws {
    let model = WholeShutoProductModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    model.preparePreviewJourney()
    model.prepareCustomRouteDraft()

    let entryID = "shuto.ic.c1.takaracho"
    let exitID = "shuto.ic.k1.yokohamakouen"
    XCTAssertTrue(
      model.customEntryCandidates.contains {
        $0.facilityID == entryID
      }
    )
    XCTAssertTrue(
      model.customExitCandidates.contains {
        $0.facilityID == exitID
      }
    )

    model.selectCustomEntry(facilityID: entryID)
    model.selectCustomExit(facilityID: exitID)
    model.selectCustomPreference(.fewerJunctions)

    let draft = try XCTUnwrap(model.customDraftRoute)
    XCTAssertEqual(draft.entryFacility.facilityID, entryID)
    XCTAssertEqual(draft.exitFacility.facilityID, exitID)
    XCTAssertEqual(draft.preference, .fewerJunctions)
    XCTAssertTrue(model.canApplyCustomRoute)
    XCTAssertTrue(model.applyCustomRoute())

    XCTAssertTrue(model.isCustomRouteSelected)
    XCTAssertEqual(model.selectedRoute?.routePlan, draft.routePlan)
    XCTAssertEqual(model.selectedRoute?.entryFacility.facilityID, entryID)
    XCTAssertEqual(model.selectedRoute?.exitFacility.facilityID, exitID)

    for _ in 0..<100 where model.isUpdatingSurfaceRoute {
      await Task.yield()
    }
    XCTAssertFalse(model.isUpdatingSurfaceRoute)
    // Surface legs land on the draft's own directional ramp mouths.
    XCTAssertEqual(
      model.accessRoute?.coordinates.last,
      draft.coordinates.first
    )
    XCTAssertEqual(
      model.egressRoute?.coordinates.first,
      draft.coordinates.last
    )

    model.selectRecommendation(at: 0)

    XCTAssertFalse(model.isCustomRouteSelected)
    XCTAssertNotEqual(model.selectedRoute?.routePlan, draft.routePlan)
  }

  func testCustomRouteSelectionSourceRestoresWithItsExactRoute() async throws {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: store
    )
    model.preparePreviewJourney()
    model.prepareCustomRouteDraft()
    model.selectCustomEntry(facilityID: "shuto.ic.c1.takaracho")
    model.selectCustomExit(facilityID: "shuto.ic.k1.yokohamakouen")
    model.selectCustomPreference(.fewerJunctions)
    XCTAssertTrue(model.applyCustomRoute())

    for _ in 0..<100 where model.isUpdatingSurfaceRoute {
      await Task.yield()
    }
    let selectedPlan = try XCTUnwrap(model.selectedRoute?.routePlan)
    XCTAssertEqual(store.checkpoint?.routeSelectionSource, .custom)

    let restored = WholeShutoProductModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: store
    )

    XCTAssertEqual(restored.phase, .review)
    XCTAssertTrue(restored.isCustomRouteSelected)
    XCTAssertEqual(restored.selectedRoute?.routePlan, selectedPlan)
    XCTAssertEqual(
      restored.customEntryFacilityID,
      "shuto.ic.c1.takaracho"
    )
    XCTAssertEqual(
      restored.customExitFacilityID,
      "shuto.ic.k1.yokohamakouen"
    )
    XCTAssertEqual(restored.customPreference, .fewerJunctions)
  }

  func testJunctionPromptsRequireAnExactReviewedMovement() {
    let model = WholeShutoProductModel(checkpointStore: nil)

    model.preparePreviewJourney()

    XCTAssertTrue(model.junctionPrompts.isEmpty)

    model.prepareJunctionPreview()

    let prompt = try? XCTUnwrap(model.junctionPrompts.only)
    XCTAssertEqual(
      prompt?.movementID,
      "shuto.jct.oi.b-westbound-to-c2-outer"
    )
    XCTAssertEqual(prompt?.nameJA, "大井JCT")
    XCTAssertEqual(prompt?.incomingRouteID, "B")
    XCTAssertEqual(prompt?.outgoingRouteID, "C2")
    XCTAssertEqual(prompt?.outgoingDirectionJA, "外回り")
    XCTAssertEqual(prompt?.branchSide, .left)
    XCTAssertEqual(prompt?.japaneseSignText, "東名・中央道")
    XCTAssertEqual(prompt?.routeShields, ["C2", "3", "E1", "E20"])
    XCTAssertEqual(prompt?.laneGuidanceState, .notReleased)
    XCTAssertEqual(prompt?.localizedJunctionNames[.japanese], "大井JCT")
    XCTAssertEqual(
      prompt?.localizedJunctionNames[.simplifiedChinese],
      "大井 JCT"
    )
    XCTAssertEqual(prompt?.localizedJunctionNames[.english], "Oi JCT")
    XCTAssertEqual(
      prompt?.localizedContent[.japanese]?.displayText,
      "左方向へ分岐し、C2 外回りへ"
    )
    XCTAssertEqual(
      prompt?.localizedContent[.simplifiedChinese]?.displayText,
      "向左分岔，驶入 C2 外环"
    )
    XCTAssertEqual(
      prompt?.localizedContent[.english]?.displayText,
      "Branch left for the C2 Outer Loop"
    )
    XCTAssertTrue(
      prompt?.localizedContent.values.allSatisfy {
        $0.preservedJapaneseSignText == "東名・中央道"
      } == true
    )
    XCTAssertEqual(prompt?.checkedAt, "2026-07-29")
    XCTAssertEqual(model.activeJunctionPrompt, prompt)
    XCTAssertNil(model.failureCode)
  }

  func testKasaiJunctionPromptRequiresTheExactReviewedMovement() {
    let model = WholeShutoProductModel(checkpointStore: nil)

    model.prepareKasaiJunctionPreview()

    let prompt = try? XCTUnwrap(model.junctionPrompts.only)
    XCTAssertEqual(
      prompt?.movementID,
      "shuto.jct.kasai.b-westbound-to-c2-inner"
    )
    XCTAssertEqual(prompt?.nameJA, "葛西JCT")
    XCTAssertEqual(prompt?.incomingRouteID, "B")
    XCTAssertEqual(prompt?.outgoingRouteID, "C2")
    XCTAssertEqual(prompt?.outgoingDirectionJA, "内回り")
    XCTAssertEqual(prompt?.branchSide, .left)
    XCTAssertEqual(prompt?.japaneseSignText, "東北道・常磐道")
    XCTAssertEqual(prompt?.routeShields, ["C2", "E4", "E6", "6"])
    XCTAssertEqual(prompt?.laneGuidanceState, .notReleased)
    XCTAssertEqual(
      prompt?.localizedContent[.japanese]?.displayText,
      "左方向へ分岐し、C2 内回りへ"
    )
    XCTAssertEqual(
      prompt?.localizedContent[.simplifiedChinese]?.displayText,
      "向左分岔，驶入 C2 内环"
    )
    XCTAssertEqual(
      prompt?.localizedContent[.english]?.displayText,
      "Branch left for the C2 Inner Loop"
    )
    XCTAssertEqual(prompt?.checkedAt, "2026-07-30")
    XCTAssertEqual(model.activeJunctionPrompt, prompt)
    XCTAssertNil(model.failureCode)
  }

  func testTatsumiJunctionPromptsPreserveEachApproachSign() {
    let cases:
      [(
        isEastbound: Bool,
        movementID: String,
        signText: String,
        routeShields: [String]
      )] = [
        (
          true,
          "shuto.jct.tatsumi.b-eastbound-to-9-inbound",
          "箱崎",
          ["9", "6"]
        ),
        (
          false,
          "shuto.jct.tatsumi.b-westbound-to-9-inbound",
          "箱崎・銀座",
          ["9", "C1"]
        ),
      ]

    for testCase in cases {
      let model = WholeShutoProductModel(checkpointStore: nil)
      if testCase.isEastbound {
        model.prepareTatsumiEastboundJunctionPreview()
      } else {
        model.prepareTatsumiWestboundJunctionPreview()
      }

      let prompt = try? XCTUnwrap(model.junctionPrompts.only)
      XCTAssertEqual(prompt?.movementID, testCase.movementID)
      XCTAssertEqual(prompt?.nameJA, "辰巳JCT")
      XCTAssertEqual(prompt?.outgoingRouteID, "9")
      XCTAssertEqual(prompt?.outgoingDirectionJA, "上り")
      XCTAssertEqual(prompt?.branchSide, .left)
      XCTAssertEqual(prompt?.japaneseSignText, testCase.signText)
      XCTAssertEqual(prompt?.routeShields, testCase.routeShields)
      XCTAssertEqual(prompt?.laneGuidanceState, .notReleased)
      XCTAssertEqual(
        prompt?.localizedContent[.japanese]?.displayText,
        "左方向へ分岐し、9号深川線 上りへ"
      )
      XCTAssertEqual(
        prompt?.localizedContent[.simplifiedChinese]?.displayText,
        "向左分岔，驶入 9 号深川线上行方向"
      )
      XCTAssertEqual(
        prompt?.localizedContent[.english]?.displayText,
        "Branch left for Route 9 inbound"
      )
      XCTAssertTrue(
        prompt?.localizedContent.values.allSatisfy {
          $0.preservedJapaneseSignText == testCase.signText
        } == true
      )
      XCTAssertEqual(prompt?.checkedAt, "2026-07-30")
      XCTAssertEqual(model.activeJunctionPrompt, prompt)
      XCTAssertNil(model.failureCode)
    }
  }

  func testShinonomeJunctionPromptsPreserveEachApproachBranchAndSign() {
    let cases:
      [(
        isEastbound: Bool,
        movementID: String,
        isLeftBranch: Bool,
        signText: String,
        localizedInstruction: String
      )] = [
        (
          true,
          "shuto.jct.shinonome.b-eastbound-to-10-inbound",
          true,
          "豊洲",
          "向左分岔，驶入 10 号晴海线上行方向"
        ),
        (
          false,
          "shuto.jct.shinonome.b-westbound-to-10-inbound",
          false,
          "晴海",
          "向右分岔，驶入 10 号晴海线上行方向"
        ),
      ]

    for testCase in cases {
      let model = WholeShutoProductModel(checkpointStore: nil)
      if testCase.isEastbound {
        model.prepareShinonomeEastboundJunctionPreview()
      } else {
        model.prepareShinonomeWestboundJunctionPreview()
      }

      let prompt = try? XCTUnwrap(model.junctionPrompts.only)
      XCTAssertEqual(prompt?.movementID, testCase.movementID)
      XCTAssertEqual(prompt?.nameJA, "東雲JCT")
      XCTAssertEqual(prompt?.outgoingRouteID, "10")
      XCTAssertEqual(prompt?.outgoingDirectionJA, "上り")
      XCTAssertEqual(
        prompt?.branchSide,
        testCase.isLeftBranch ? .left : .right
      )
      XCTAssertEqual(prompt?.japaneseSignText, testCase.signText)
      XCTAssertEqual(prompt?.routeShields, ["10"])
      XCTAssertEqual(prompt?.laneGuidanceState, .notReleased)
      XCTAssertEqual(
        prompt?.localizedContent[.simplifiedChinese]?.displayText,
        testCase.localizedInstruction
      )
      XCTAssertTrue(
        prompt?.localizedContent.values.allSatisfy {
          $0.preservedJapaneseSignText == testCase.signText
        } == true
      )
      XCTAssertEqual(prompt?.checkedAt, "2026-07-30")
      XCTAssertEqual(model.activeJunctionPrompt, prompt)
      XCTAssertNil(model.failureCode)
    }
  }

  func testActiveJourneyRestoresPausedOnTheSameNetworkSnapshot()
    async throws
  {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: store)
    model.preparePreviewJourney()
    let originalRoute = try XCTUnwrap(model.selectedRoute)

    model.startNavigationSimulation()
    model.togglePlayback()
    await advance(model, until: { $0.phase == .expressway })
    for _ in 0..<3 {
      await model.advanceSimulationForTesting()
    }
    let savedProgress = model.progressFraction
    let savedCoordinate = model.currentCoordinate

    let restored = WholeShutoProductModel(
      database: model.database,
      checkpointStore: store
    )

    XCTAssertEqual(restored.phase, .expressway)
    XCTAssertEqual(restored.progressFraction, savedProgress)
    XCTAssertEqual(
      restored.runtimeOccurrenceID,
      model.runtimeOccurrenceID
    )
    XCTAssertEqual(
      restored.selectedRoute?.entryFacility.facilityID,
      originalRoute.entryFacility.facilityID
    )
    XCTAssertEqual(
      restored.selectedRoute?.exitFacility.facilityID,
      originalRoute.exitFacility.facilityID
    )
    XCTAssertTrue(restored.restoredFromCheckpoint)
    XCTAssertFalse(restored.isPlaying)

    await restored.advanceSimulationForTesting()
    XCTAssertGreaterThanOrEqual(
      restored.progressFraction,
      savedProgress
    )
    XCTAssertEqual(restored.currentCoordinate, savedCoordinate)
  }

  func testEntryCheckpointBeforeFirstObservationRestoresRuntime()
    async
  {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: store)
    model.preparePreviewJourney()
    model.startNavigationSimulation()
    model.togglePlayback()
    await advance(model, until: { $0.phase == .entryTransition })

    XCTAssertEqual(model.progressFraction, 0)
    XCTAssertNil(model.runtimeOccurrenceID)

    let restored = WholeShutoProductModel(
      database: model.database,
      checkpointStore: store
    )

    XCTAssertEqual(restored.phase, .entryTransition)
    XCTAssertTrue(restored.restoredFromCheckpoint)
    XCTAssertNil(restored.failureCode)

    await advance(restored, until: { $0.matcherConfidence == .high })

    XCTAssertEqual(restored.matcherConfidence, .high)
    XCTAssertEqual(restored.phase, .entryTransition)
    XCTAssertNil(restored.runtimeOccurrenceID)

    await advance(restored, until: { $0.phase == .expressway })

    XCTAssertNotNil(restored.runtimeOccurrenceID)
    XCTAssertGreaterThan(restored.progressFraction, 0)
  }

  func testCheckpointRoutePlanDriftDoesNotRestore() throws {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: store)
    model.preparePreviewJourney()
    model.startNavigationSimulation()
    model.togglePlayback()

    let checkpoint = try XCTUnwrap(store.checkpoint)
    let originalPlan = checkpoint.routePlan
    var occurrences = originalPlan.occurrences
    let first = try XCTUnwrap(occurrences.first)
    occurrences[0] = RouteOccurrence(
      id: first.id,
      index: first.index,
      kind: first.kind,
      entityID: "\(first.entityID).drifted",
      parkingAreaID: first.parkingAreaID,
      tollDomainID: first.tollDomainID,
      isOptional: first.isOptional
    )
    store.checkpoint = checkpoint.replacingRoutePlan(
      RoutePlan(
        id: originalPlan.id,
        networkSnapshotID: originalPlan.networkSnapshotID,
        entryFacilityID: originalPlan.entryFacilityID,
        exitFacilityID: originalPlan.exitFacilityID,
        recoveryPolicy: originalPlan.recoveryPolicy,
        actualDistanceKM: originalPlan.actualDistanceKM,
        occurrences: occurrences
      )
    )

    let restored = WholeShutoProductModel(
      database: model.database,
      checkpointStore: store
    )

    XCTAssertEqual(restored.phase, .planning)
    XCTAssertNil(restored.selectedRoute)
    XCTAssertFalse(restored.restoredFromCheckpoint)
  }

  func testExpresswayPreviewExplicitlyReportsTunnelEstimation() async {
    let model = WholeShutoProductModel(checkpointStore: nil)
    model.preparePreviewJourney()
    model.startNavigationSimulation()
    model.togglePlayback()

    await advance(
      model,
      until: {
        $0.phase == .expressway
          && $0.positionState == .tunnelEstimated
      },
      maximumTicks: 180
    )

    XCTAssertEqual(model.positionState, .tunnelEstimated)
    XCTAssertNil(model.navigationHeadingDegrees)
  }

  func testSimulationStartsOnTheGeographicMapWithRouteProgressTelemetry()
    async throws
  {
    let model = WholeShutoProductModel(checkpointStore: nil)
    model.prepareKasaiJunctionPreview(startsNavigation: true)
    model.togglePlayback()

    let initialRemaining = try XCTUnwrap(
      model.remainingJourneyDistanceMeters
    )
    XCTAssertEqual(model.mapMode, .geographic)
    XCTAssertGreaterThan(initialRemaining, 0)
    XCTAssertNotNil(model.nextReviewedJunctionPrompt)
    XCTAssertNotNil(model.distanceToNextReviewedJunctionMeters)

    await advance(
      model,
      until: {
        $0.phase == .expressway
          && $0.positionState == .networkPreview
          && $0.progressFraction > 0
      },
      maximumTicks: 1_000
    )

    let geometry = try XCTUnwrap(model.routeProgressGeometry)
    let current = try XCTUnwrap(model.currentCoordinate)
    XCTAssertGreaterThan(geometry.traveledCoordinates.count, 1)
    XCTAssertGreaterThan(geometry.remainingCoordinates.count, 1)
    XCTAssertEqual(geometry.traveledCoordinates.last, current)
    XCTAssertEqual(geometry.remainingCoordinates.first, current)
    XCTAssertNotNil(model.navigationHeadingDegrees)
    XCTAssertLessThan(
      try XCTUnwrap(model.remainingJourneyDistanceMeters),
      initialRemaining
    )
  }

  func testEntryTransitionRequiresOrderedObservationsBeforeExpressway()
    async
  {
    let model = WholeShutoProductModel(checkpointStore: nil)
    model.preparePreviewJourney()
    model.startNavigationSimulation()
    model.togglePlayback()

    await advance(model, until: { $0.phase == .entryTransition })

    XCTAssertEqual(model.progressFraction, 0)
    XCTAssertNil(model.runtimeOccurrenceID)
    XCTAssertEqual(model.positionState, .boundaryTransition)

    // The ramp mouth begins with micro-edges the matcher reports at
    // reduced confidence; HIGH must still arrive while the phase remains
    // entryTransition and before any occurrence is admitted.
    await advance(model, until: { $0.matcherConfidence == .high })

    XCTAssertEqual(model.matcherConfidence, .high)
    XCTAssertEqual(model.phase, .entryTransition)
    XCTAssertNil(model.runtimeOccurrenceID)

    await advance(
      model,
      until: { $0.phase == .expressway },
      maximumTicks: 1_000
    )

    XCTAssertEqual(model.phase, .expressway)
    XCTAssertNotNil(model.runtimeOccurrenceID)
    XCTAssertGreaterThan(model.progressFraction, 0)
  }

  func testReviewedJunctionSpeechIsActorOwnedAndNotRepeatedAfterRestore()
    async throws
  {
    let store = WholeShutoMemoryCheckpointStore()
    let initialOutput = WholeShutoRecordingSpeechOutput()
    let model = WholeShutoProductModel(
      checkpointStore: store,
      speechOutput: initialOutput,
      languageSelectionProvider: Self.testLanguages
    )
    model.prepareJunctionPreview(startsNavigation: true)
    model.togglePlayback()

    await advance(
      model,
      until: { _ in !initialOutput.commands.isEmpty },
      maximumTicks: 1_000
    )

    let command = try XCTUnwrap(initialOutput.commands.only)
    XCTAssertEqual(command.languageCode, "ja-JP")
    XCTAssertTrue(command.spokenText.contains("大井ジャンクション"))
    XCTAssertTrue(command.synthesisText.contains("シーツー"))
    XCTAssertEqual(
      model.presentationProjection?.iPhone.maneuver,
      .branchLeft
    )
    XCTAssertEqual(
      model.presentationProjection?.iPhone.lanePreparation,
      GuidanceLanePreparation.none
    )
    XCTAssertEqual(
      model.activeJunctionPrompt?.movementID,
      "shuto.jct.oi.b-westbound-to-c2-outer"
    )

    model.handleScenePhase(.background)

    let restoredOutput = WholeShutoRecordingSpeechOutput()
    let restored = WholeShutoProductModel(
      database: model.database,
      checkpointStore: store,
      speechOutput: restoredOutput,
      languageSelectionProvider: Self.testLanguages
    )
    XCTAssertEqual(restored.phase, .expressway)

    await advance(
      restored,
      until: {
        $0.speechStatus == .suppressed(.duplicate)
      },
      maximumTicks: 80
    )

    XCTAssertTrue(restoredOutput.commands.isEmpty)
    XCTAssertEqual(restored.speechStatus, .suppressed(.duplicate))
  }

  func testKasaiJunctionSpeechIsActorOwned() async throws {
    let output = WholeShutoRecordingSpeechOutput()
    let model = WholeShutoProductModel(
      checkpointStore: nil,
      speechOutput: output,
      languageSelectionProvider: Self.testLanguages
    )
    model.prepareKasaiJunctionPreview(startsNavigation: true)
    model.togglePlayback()

    await advance(
      model,
      until: { _ in !output.commands.isEmpty },
      maximumTicks: 1_000
    )

    let command = try XCTUnwrap(output.commands.only)
    XCTAssertEqual(command.languageCode, "ja-JP")
    XCTAssertTrue(command.spokenText.contains("葛西ジャンクション"))
    XCTAssertTrue(command.synthesisText.contains("シーツー"))
    XCTAssertEqual(
      model.presentationProjection?.iPhone.maneuver,
      .branchLeft
    )
    XCTAssertEqual(
      model.presentationProjection?.iPhone.lanePreparation,
      GuidanceLanePreparation.none
    )
    XCTAssertEqual(
      model.presentationProjection?.iPhone.japaneseSignText,
      "東北道・常磐道"
    )
    XCTAssertEqual(
      model.activeJunctionPrompt?.movementID,
      "shuto.jct.kasai.b-westbound-to-c2-inner"
    )
  }

  func testTatsumiJunctionSpeechIsActorOwned() async throws {
    let output = WholeShutoRecordingSpeechOutput()
    let model = WholeShutoProductModel(
      checkpointStore: nil,
      speechOutput: output,
      languageSelectionProvider: Self.testLanguages
    )
    model.prepareTatsumiEastboundJunctionPreview(
      startsNavigation: true
    )
    model.togglePlayback()

    await advance(
      model,
      until: { _ in !output.commands.isEmpty },
      maximumTicks: 1_000
    )

    let command = try XCTUnwrap(output.commands.only)
    XCTAssertEqual(command.languageCode, "ja-JP")
    XCTAssertTrue(command.spokenText.contains("辰巳ジャンクション"))
    XCTAssertTrue(
      command.synthesisText.contains("きゅうごうふかがわせん")
    )
    XCTAssertEqual(
      model.presentationProjection?.iPhone.maneuver,
      .branchLeft
    )
    XCTAssertEqual(
      model.presentationProjection?.iPhone.lanePreparation,
      GuidanceLanePreparation.none
    )
    XCTAssertEqual(
      model.presentationProjection?.iPhone.japaneseSignText,
      "箱崎"
    )
    XCTAssertEqual(
      model.activeJunctionPrompt?.movementID,
      "shuto.jct.tatsumi.b-eastbound-to-9-inbound"
    )
  }

  func testShinonomeRightBranchSpeechIsActorOwned() async throws {
    let output = WholeShutoRecordingSpeechOutput()
    let model = WholeShutoProductModel(
      checkpointStore: nil,
      speechOutput: output,
      languageSelectionProvider: Self.testLanguages
    )
    model.prepareShinonomeWestboundJunctionPreview(
      startsNavigation: true
    )
    model.togglePlayback()

    await advance(
      model,
      until: { _ in !output.commands.isEmpty },
      maximumTicks: 1_000
    )

    let command = try XCTUnwrap(output.commands.only)
    XCTAssertEqual(command.languageCode, "ja-JP")
    XCTAssertTrue(command.spokenText.contains("東雲ジャンクション"))
    XCTAssertTrue(
      command.synthesisText.contains("じゅうごうはるみせん")
    )
    XCTAssertEqual(
      model.presentationProjection?.iPhone.maneuver,
      .branchRight
    )
    XCTAssertEqual(
      model.presentationProjection?.iPhone.lanePreparation,
      GuidanceLanePreparation.none
    )
    XCTAssertEqual(
      model.presentationProjection?.iPhone.japaneseSignText,
      "晴海"
    )
    XCTAssertEqual(
      model.activeJunctionPrompt?.movementID,
      "shuto.jct.shinonome.b-westbound-to-10-inbound"
    )
  }

  func testReviewedJunctionKeepsInterfaceAndVoiceLanguagesIndependent()
    async throws
  {
    let output = WholeShutoRecordingSpeechOutput()
    let languages = NavigationLanguageSelection(
      interfaceLocale: .english,
      guidanceVoiceLocale: .simplifiedChinese
    )
    let model = WholeShutoProductModel(
      checkpointStore: nil,
      speechOutput: output,
      languageSelectionProvider: { languages }
    )
    model.prepareJunctionPreview(startsNavigation: true)
    model.togglePlayback()

    await advance(
      model,
      until: { _ in !output.commands.isEmpty },
      maximumTicks: 1_000
    )

    let projection = try XCTUnwrap(model.presentationProjection)
    let command = try XCTUnwrap(output.commands.only)
    XCTAssertEqual(projection.interfaceLocale, .english)
    XCTAssertEqual(projection.iPhone.localizedDecisionPointName, "Oi JCT")
    XCTAssertEqual(
      projection.iPhone.localizedDisplayText,
      "Branch left for the C2 Outer Loop"
    )
    XCTAssertEqual(projection.iPhone.japaneseSignText, "東名・中央道")
    XCTAssertEqual(projection.carPlay.japaneseSignText, "東名・中央道")
    XCTAssertEqual(projection.voice.locale, .simplifiedChinese)
    XCTAssertEqual(projection.voice.spokenText, "在大井枢纽向左分岔，驶入 C2 外环")
    XCTAssertEqual(command.languageCode, "zh-CN")
    XCTAssertEqual(command.spokenText, projection.voice.spokenText)
    XCTAssertTrue(command.synthesisText.contains("C 二"))
  }

  private func advance(
    _ model: WholeShutoProductModel,
    until predicate: (WholeShutoProductModel) -> Bool,
    maximumTicks: Int = 80,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    for _ in 0..<maximumTicks {
      if predicate(model) {
        return
      }
      await model.advanceSimulationForTesting()
    }
    XCTFail(
      "Whole-Shuto simulation did not reach the expected state",
      file: file,
      line: line
    )
  }

  private static func testLanguages() -> NavigationLanguageSelection {
    NavigationLanguageSelection(
      interfaceLocale: .simplifiedChinese,
      guidanceVoiceLocale: .japanese
    )
  }
}

extension Collection {
  fileprivate var only: Element? {
    count == 1 ? first : nil
  }
}

@MainActor
private final class WholeShutoMemoryCheckpointStore:
  WholeShutoJourneyCheckpointStoring
{
  var checkpoint: WholeShutoJourneyCheckpoint?

  func load() throws -> WholeShutoJourneyCheckpoint? {
    checkpoint
  }

  func save(_ checkpoint: WholeShutoJourneyCheckpoint) throws {
    self.checkpoint = checkpoint
  }

  func remove() throws {
    checkpoint = nil
  }
}

private actor WholeShutoOutOfOrderSurfaceRouteResolver:
  WholeShutoSurfaceRouteResolving
{
  private var slowEntry: ShutoCoordinate?
  private var slowExit: ShutoCoordinate?

  func configure(
    slowEntry: ShutoCoordinate,
    slowExit: ShutoCoordinate
  ) {
    self.slowEntry = slowEntry
    self.slowExit = slowExit
  }

  func route(
    from origin: ShutoCoordinate,
    to destination: ShutoCoordinate
  ) async -> WholeShutoSurfaceRoute? {
    let isSlow = destination == slowEntry || origin == slowExit
    let delay: UInt64 = isSlow ? 180_000_000 : 20_000_000
    let route = WholeShutoSurfaceRoute(
      coordinates: [origin, destination],
      distanceMeters: Double(delay),
      expectedTravelTimeSeconds: 1,
      instructions: []
    )
    return await Task.detached {
      try? await Task.sleep(nanoseconds: delay)
      return route
    }.value
  }
}

private actor WholeShutoRecoveringSurfaceRouteResolver:
  WholeShutoSurfaceRouteResolving
{
  private var isAvailable = false

  func setAvailable(_ isAvailable: Bool) {
    self.isAvailable = isAvailable
  }

  func route(
    from origin: ShutoCoordinate,
    to destination: ShutoCoordinate
  ) async -> WholeShutoSurfaceRoute? {
    guard isAvailable else { return nil }
    return WholeShutoSurfaceRoute(
      coordinates: [origin, destination],
      distanceMeters: 1_200,
      expectedTravelTimeSeconds: 180,
      instructions: []
    )
  }
}

private actor WholeShutoRankingSurfaceRouteResolver:
  WholeShutoSurfaceRouteResolving
{
  private let preferredEntry: ShutoCoordinate
  private let preferredExit: ShutoCoordinate

  init(
    preferredEntry: ShutoCoordinate,
    preferredExit: ShutoCoordinate
  ) {
    self.preferredEntry = preferredEntry
    self.preferredExit = preferredExit
  }

  func route(
    from origin: ShutoCoordinate,
    to destination: ShutoCoordinate
  ) async -> WholeShutoSurfaceRoute? {
    let isPreferredLeg =
      destination == preferredEntry || origin == preferredExit
    let distanceMeters = isPreferredLeg ? 200.0 : 50_000.0
    let expectedTravelTimeSeconds =
      isPreferredLeg ? 20.0 : 20_000.0
    return WholeShutoSurfaceRoute(
      coordinates: [origin, destination],
      distanceMeters: distanceMeters,
      expectedTravelTimeSeconds: expectedTravelTimeSeconds,
      instructions: []
    )
  }
}

private actor WholeShutoPartiallyUnavailableChoiceResolver:
  WholeShutoSurfaceRouteResolving
{
  private let unavailableEntry: ShutoCoordinate

  init(unavailableEntry: ShutoCoordinate) {
    self.unavailableEntry = unavailableEntry
  }

  func route(
    from origin: ShutoCoordinate,
    to destination: ShutoCoordinate
  ) async -> WholeShutoSurfaceRoute? {
    guard destination != unavailableEntry else {
      return nil
    }
    return WholeShutoSurfaceRoute(
      coordinates: [origin, destination],
      distanceMeters: 1_000,
      expectedTravelTimeSeconds: 120,
      instructions: []
    )
  }
}

@MainActor
private final class WholeShutoUnexpectedLocationProvider:
  C2NavigationCurrentLocationProviding
{
  private(set) var requestCount = 0

  func currentCoordinate() async throws -> SurfaceCoordinate {
    requestCount += 1
    throw C2NavigationDemoError.locationUnavailable
  }
}

extension WholeShutoJourneyCheckpoint {
  fileprivate func replacingRoutePlan(_ routePlan: RoutePlan) -> Self {
    WholeShutoJourneyCheckpoint(
      schemaVersion: schemaVersion,
      networkSnapshotID: networkSnapshotID,
      originQuery: originQuery,
      destinationQuery: destinationQuery,
      origin: origin,
      destination: destination,
      entryFacilityID: entryFacilityID,
      exitFacilityID: exitFacilityID,
      routePlan: routePlan,
      preference: preference,
      routeSelectionSource: routeSelectionSource,
      phase: phase,
      progressFraction: progressFraction,
      runtimeOccurrenceID: runtimeOccurrenceID,
      runtimeFractionAlongOccurrence: runtimeFractionAlongOccurrence,
      consumedGuidancePromptIDs: consumedGuidancePromptIDs,
      mapMode: mapMode,
      accessRoute: accessRoute,
      egressRoute: egressRoute,
      circuitID: circuitID,
      circuitLaps: circuitLaps
    )
  }
}

@MainActor
private final class WholeShutoRecordingSpeechOutput:
  GuidanceSpeechOutput
{
  var eventHandler: ((GuidanceSpeechOutputEvent) -> Void)?
  var selectedVoiceProfile: GuidanceSpeechVoiceProfile?
  private(set) var commands: [GuidanceSpeechCommand] = []

  func speak(_ command: GuidanceSpeechCommand) {
    commands.append(command)
    eventHandler?(.didStart(command.identity))
  }

  func stop() {}
}
