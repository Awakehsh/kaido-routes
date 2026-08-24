import CoreLocation
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

  func testLiveDriveFailsClosedWithoutValidatedNavigationRelease() async {
    let model = WholeShutoProductModel(checkpointStore: nil)
    model.preparePreviewJourney()
    XCTAssertEqual(model.phase, .review)
    XCTAssertTrue(model.isJourneyReadyForPreview)

    XCTAssertFalse(model.canStartLiveNavigation)
    XCTAssertEqual(
      model.liveNavigationBlockerCode,
      "WHOLE_SHUTO_NAVIGATION_RELEASE_REQUIRED"
    )
    let startedLiveJourney = await model.startLiveJourney()
    XCTAssertFalse(startedLiveJourney)
    XCTAssertFalse(model.isLiveDrive)
    XCTAssertFalse(model.isPlaying)
    XCTAssertEqual(model.phase, .review)
    XCTAssertEqual(model.liveLocationState, .inactive)
    XCTAssertEqual(
      model.failureCode,
      "WHOLE_SHUTO_NAVIGATION_RELEASE_REQUIRED"
    )

    model.startNavigationSimulation()
    XCTAssertFalse(model.isLiveDrive)
    XCTAssertTrue(model.isPlaying)
    XCTAssertNil(model.failureCode)
  }

  func testExactC1CircuitAdmitsBundledForegroundNavigation() async throws {
    let database = try WholeShutoNetworkCatalog.bundled()
    let entry = try XCTUnwrap(
      BundledProductReleaseCatalogLoader.bundledForeground()
        .foregroundNavigationEntries.first
    )
    let route = try ShutoCircuitProductReleaseBuilder.plannedRoute(
      database: database
    )
    let core = try KaidoLiveJourneyAdmission(
      release: entry.release,
      selectedRoutePlan: route.routePlan,
      journeyPlan: JourneyPlanCompiler.expresswayOnly(
        release: entry.release
      )
    )
    let model = WholeShutoProductModel(
      database: database,
      locationProvider: WholeShutoUnexpectedLocationProvider(),
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil,
      liveJourneyAdmissions: [
        try WholeShutoLiveJourneyAdmission(core: core)
      ]
    )

    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 37.3349, longitude: -122.0090)
    )
    model.selectCircuit(.c1Inner)
    await waitForCircuitPairing(model)

    XCTAssertEqual(
      model.circuitEntryFacilityID,
      ShutoCircuitProductReleaseBuilder.entryFacilityID
    )
    XCTAssertEqual(
      model.circuitExitFacilityID,
      ShutoCircuitProductReleaseBuilder.exitFacilityID
    )
    XCTAssertTrue(model.startCircuitJourney())
    await waitForLiveNavigationPreparation(model)
    XCTAssertEqual(model.selectedRoute?.routePlan, route.routePlan)
    XCTAssertTrue(model.canStartLiveNavigation)
    XCTAssertNil(model.liveNavigationBlockerCode)
  }

  func testC1OuterCircuitBuildsForegroundNavigationOnDemand() async throws {
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6777, longitude: 139.7708)
    )
    model.selectCircuit(.c1Outer)
    await waitForCircuitPairing(model)

    XCTAssertNotNil(model.circuitEntryFacilityID)
    XCTAssertNotNil(model.circuitExitFacilityID)
    XCTAssertEqual(
      model.circuitEntryFacilityID,
      "shuto.ic.c1.kyoubashi"
    )
    XCTAssertTrue(model.startCircuitJourney())
    for _ in 0..<400
    where model.isUpdatingSurfaceRoute || !model.canStartLiveNavigation {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }

    XCTAssertEqual(model.phase, .review)
    XCTAssertEqual(
      model.selectedRoute?.routePlan.id.hasPrefix(
        "shuto.circuit.c1-outer."
      ),
      true
    )
    XCTAssertTrue(model.canStartLiveNavigation)
    XCTAssertNil(model.liveNavigationBlockerCode)
  }

  func testLongSurfaceAccessCanReachReleasedCircuitNavigation() async throws {
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6979, longitude: 139.4139)
    )
    model.selectCircuit(.c1Outer)
    await waitForCircuitPairing(model)

    let distance = try XCTUnwrap(model.circuitEntranceDistanceMeters)
    XCTAssertEqual(
      ShutoEntranceAccessTier.classify(distanceMeters: distance),
      .extended
    )
    XCTAssertNotNil(model.circuitEntryFacilityID)
    XCTAssertNotNil(model.circuitExitFacilityID)
    XCTAssertTrue(model.startCircuitJourney())
    for _ in 0..<400
    where model.isUpdatingSurfaceRoute || !model.canStartLiveNavigation {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }

    XCTAssertEqual(model.phase, .review)
    XCTAssertNotNil(model.accessRoute)
    XCTAssertNotNil(model.egressRoute)
    XCTAssertTrue(model.canStartLiveNavigation)
    XCTAssertNil(model.liveNavigationBlockerCode)
  }

  func testWanganDaikokuRunAdmitsBundledForegroundNavigation() async throws {
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    let expected = try ShutoCircuitProductReleaseBuilder.plannedWanganRoute(
      database: model.database
    )

    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6812, longitude: 139.7671)
    )
    model.selectCircuit(.wanganDaikokuRun)
    await waitForCircuitPairing(model)

    XCTAssertEqual(
      model.circuitEntryFacilityID,
      ShutoCircuitProductReleaseBuilder.wanganEntryFacilityID
    )
    XCTAssertEqual(
      model.circuitExitFacilityID,
      ShutoCircuitProductReleaseBuilder.wanganExitFacilityID
    )
    XCTAssertTrue(model.startCircuitJourney())
    await waitForLiveNavigationPreparation(model)
    XCTAssertEqual(model.selectedRoute?.routePlan, expected.routePlan)
    XCTAssertTrue(model.canStartLiveNavigation)
    XCTAssertNil(model.liveNavigationBlockerCode)
  }

  func testC2InnerCircuitAdmitsBundledForegroundNavigation() async throws {
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    let expected = try ShutoCircuitProductReleaseBuilder.plannedC2Route(
      database: model.database
    )

    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6812, longitude: 139.7671)
    )
    model.selectCircuit(.c2InnerWithBayshore)
    await waitForCircuitPairing(model)

    XCTAssertEqual(
      model.circuitEntryFacilityID,
      ShutoCircuitProductReleaseBuilder.c2EntryFacilityID
    )
    XCTAssertEqual(
      model.circuitExitFacilityID,
      ShutoCircuitProductReleaseBuilder.c2ExitFacilityID
    )
    XCTAssertTrue(model.startCircuitJourney())
    await waitForLiveNavigationPreparation(model)
    XCTAssertEqual(model.selectedRoute?.routePlan, expected.routePlan)
    XCTAssertTrue(model.canStartLiveNavigation)
    XCTAssertNil(model.liveNavigationBlockerCode)
  }

  func testDaikokuYokohamaCircuitAdmitsBundledForegroundNavigation()
    async throws
  {
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    let expected =
      try ShutoCircuitProductReleaseBuilder
      .plannedDaikokuRoute(database: model.database)

    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6812, longitude: 139.7671)
    )
    model.selectCircuit(.daikokuYokohamaLoop)
    await waitForCircuitPairing(model)

    XCTAssertEqual(
      model.circuitEntryFacilityID,
      ShutoCircuitProductReleaseBuilder.daikokuEntryFacilityID
    )
    XCTAssertEqual(
      model.circuitExitFacilityID,
      ShutoCircuitProductReleaseBuilder.daikokuExitFacilityID
    )
    XCTAssertTrue(model.startCircuitJourney())
    await waitForLiveNavigationPreparation(model)
    XCTAssertEqual(model.selectedRoute?.routePlan, expected.routePlan)
    XCTAssertTrue(model.canStartLiveNavigation)
    XCTAssertNil(model.liveNavigationBlockerCode)
  }

  func testScenicGrandTourAdmitsBundledForegroundNavigation()
    async throws
  {
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    let expected =
      try ShutoCircuitProductReleaseBuilder
      .plannedScenicRoute(database: model.database)

    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6812, longitude: 139.7671)
    )
    model.selectCircuit(.scenicGrandTour)
    await waitForCircuitPairing(model)

    XCTAssertEqual(
      model.circuitEntryFacilityID,
      ShutoCircuitProductReleaseBuilder.scenicEntryFacilityID
    )
    XCTAssertEqual(
      model.circuitExitFacilityID,
      ShutoCircuitProductReleaseBuilder.scenicExitFacilityID
    )
    XCTAssertTrue(model.startCircuitJourney())
    await waitForLiveNavigationPreparation(model)
    XCTAssertEqual(model.selectedRoute?.routePlan, expected.routePlan)
    XCTAssertTrue(model.canStartLiveNavigation)
    XCTAssertNil(model.liveNavigationBlockerCode)
  }

  func testExactCustomRouteWithCompleteGuidanceAdmitsOnDeviceNavigation()
    async throws
  {
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6812, longitude: 139.7671)
    )
    model.prepareCustomRouteDraft()
    model.selectCustomEntry(facilityID: "shuto.ic.b.urayasu")
    model.selectCustomExit(facilityID: "shuto.ic.9.fukudumi")

    XCTAssertTrue(model.applyCustomRoute())
    for _ in 0..<300
    where model.isPreparingLiveNavigation || model.isUpdatingSurfaceRoute {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }

    XCTAssertEqual(
      model.selectedRoute?.routePlan.entryFacilityID,
      "shuto.ic.b.urayasu"
    )
    XCTAssertEqual(
      model.selectedRoute?.routePlan.exitFacilityID,
      "shuto.ic.9.fukudumi"
    )
    XCTAssertFalse(model.isPreparingLiveNavigation)
    XCTAssertTrue(model.canStartLiveNavigation)
    XCTAssertNil(model.liveNavigationBlockerCode)
  }

  func testShibuyaToGinzaCustomRouteAdmitsOnDeviceNavigation()
    async throws
  {
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6580, longitude: 139.7016)
    )
    model.prepareCustomRouteDraft()
    model.selectCustomEntry(facilityID: "shuto.ic.3.shibuya")
    model.selectCustomExit(facilityID: "shuto.ic.c1.ginza")

    XCTAssertTrue(model.applyCustomRoute())
    for _ in 0..<300
    where model.isPreparingLiveNavigation || model.isUpdatingSurfaceRoute {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }

    XCTAssertEqual(
      model.selectedRoute?.routePlan.entryFacilityID,
      "shuto.ic.3.shibuya"
    )
    XCTAssertEqual(
      model.selectedRoute?.routePlan.exitFacilityID,
      "shuto.ic.c1.ginza"
    )
    XCTAssertFalse(model.isPreparingLiveNavigation)
    XCTAssertTrue(model.canStartLiveNavigation)
    XCTAssertNil(model.liveNavigationBlockerCode)
  }

  func testRoute2And5RadialPairsAdmitOnDeviceNavigation()
    async throws
  {
    let pairs = [
      ("shuto.ic.2.meguro", "shuto.ic.c1.ginza"),
      ("shuto.ic.2.tengenji", "shuto.ic.c1.ginza"),
      ("shuto.ic.c1.ginza", "shuto.ic.2.meguro"),
      ("shuto.ic.5.higashiikebukuro", "shuto.ic.c1.ginza"),
      ("shuto.ic.c1.ginza", "shuto.ic.5.higashiikebukuro"),
    ]

    for (entryFacilityID, exitFacilityID) in pairs {
      let model = WholeShutoForegroundReleaseFactory.makeModel(
        surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
        checkpointStore: nil
      )
      model.selectCurrentOrigin(
        ShutoCoordinate(latitude: 35.6812, longitude: 139.7671)
      )
      model.prepareCustomRouteDraft()
      model.selectCustomEntry(facilityID: entryFacilityID)
      model.selectCustomExit(facilityID: exitFacilityID)

      XCTAssertTrue(model.applyCustomRoute())
      for _ in 0..<300
      where model.isPreparingLiveNavigation
        || model.isUpdatingSurfaceRoute
      {
        try? await Task.sleep(nanoseconds: 50_000_000)
      }

      XCTAssertEqual(
        model.selectedRoute?.routePlan.entryFacilityID,
        entryFacilityID
      )
      XCTAssertEqual(
        model.selectedRoute?.routePlan.exitFacilityID,
        exitFacilityID
      )
      XCTAssertFalse(model.isPreparingLiveNavigation)
      XCTAssertTrue(
        model.canStartLiveNavigation,
        "Expected live admission for \(entryFacilityID) -> \(exitFacilityID), blocker: \(model.liveNavigationBlockerCode ?? "none")"
      )
      XCTAssertNil(model.liveNavigationBlockerCode)
    }
  }

  func testNewlyCompletedApproachesAdmitOnDeviceNavigation()
    async throws
  {
    let pairs = [
      ("shuto.ic.c1.shibakouen", "shuto.ic.4.shinjuku"),
      ("shuto.ic.c1.ginza", "shuto.ic.3.shibuya"),
      ("shuto.ic.10.harumi", "shuto.ic.b.urayasu"),
      ("shuto.ic.b.ooi", "shuto.ic.b.urayasu"),
      ("shuto.ic.c2.hatsudaiminami", "shuto.ic.b.urayasu"),
      ("shuto.ic.c1.ginza", "shuto.ic.1-ueno.ueno"),
      ("shuto.ic.c1.shibakouen", "shuto.ic.6-mukojima.komagata"),
      ("shuto.ic.6-mukojima.komagata", "shuto.ic.c1.ginza"),
      ("shuto.ic.4.hatagaya", "shuto.ic.c2.nishiikebukuro"),
      ("shuto.ic.c2.nishiikebukuro", "shuto.ic.4.takaido"),
      ("shuto.ic.k2.mitsuzawa", "shuto.ic.k1.yokohamakouen"),
      ("shuto.ic.k1.higashikanagawa", "shuto.ic.k2.mitsuzawa"),
      ("shuto.ic.k1.minatomirai", "shuto.ic.k3.hananoki"),
      ("shuto.ic.k3.shinyamashita", "shuto.ic.k1.minatomirai"),
      ("shuto.ic.k3.hananoki", "shuto.ic.k3.shinyamashita"),
      ("shuto.ic.k1.asada", "shuto.ic.k6.daishi"),
      ("shuto.ic.k6.daishi", "shuto.ic.k1.hamakawasaki"),
      ("shuto.ic.c2.oujiminami", "shuto.ic.5.nakadai"),
      ("shuto.ic.c2.oujiminami", "shuto.ic.c2.nishiikebukuro"),
      ("shuto.ic.5.nakadai", "shuto.ic.c1.ginza"),
      ("shuto.ic.5.nakadai", "shuto.ic.c2.oujiminami"),
      ("shuto.ic.c2.nishiikebukuro", "shuto.ic.5.nakadai"),
      ("shuto.ic.c2.nishiikebukuro", "shuto.ic.c2.oujiminami"),
      ("shuto.ic.b.higashiogishima", "shuto.ic.b.kukouchuou"),
      ("shuto.ic.k1.daishi", "shuto.ic.k5.daikokufutou"),
      (
        "shuto.ic.k1.daishi",
        "shuto.ic.k7-yokohama-kita.shinyokohama"
      ),
      ("shuto.ic.k5.daikokufutou", "shuto.ic.k1.yokohamakouen"),
      (
        "shuto.ic.k5.daikokufutou",
        "shuto.ic.k7-yokohama-kita.shinyokohama"
      ),
      (
        "shuto.ic.k1.minatomirai",
        "shuto.ic.k7-yokohama-kita.shinyokohama"
      ),
      ("shuto.ic.k1.minatomirai", "shuto.ic.k1.daishi"),
      (
        "shuto.ic.k7-yokohama-hokusei.yokohamaaoba",
        "shuto.ic.k1.daishi"
      ),
      (
        "shuto.ic.k7-yokohama-hokusei.yokohamaaoba",
        "shuto.ic.k5.daikokufutou"
      ),
      (
        "shuto.ic.k7-yokohama-hokusei.yokohamaaoba",
        "shuto.ic.k1.yokohamakouen"
      ),
    ]

    for (entryFacilityID, exitFacilityID) in pairs {
      let model = WholeShutoForegroundReleaseFactory.makeModel(
        surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
        checkpointStore: nil
      )
      model.selectCurrentOrigin(
        ShutoCoordinate(latitude: 35.6812, longitude: 139.7671)
      )
      model.prepareCustomRouteDraft()
      model.selectCustomEntry(facilityID: entryFacilityID)
      model.selectCustomExit(facilityID: exitFacilityID)

      XCTAssertTrue(model.applyCustomRoute())
      for _ in 0..<300
      where model.isPreparingLiveNavigation
        || model.isUpdatingSurfaceRoute
      {
        try? await Task.sleep(nanoseconds: 50_000_000)
      }

      XCTAssertEqual(
        model.selectedRoute?.routePlan.entryFacilityID,
        entryFacilityID
      )
      XCTAssertEqual(
        model.selectedRoute?.routePlan.exitFacilityID,
        exitFacilityID
      )
      XCTAssertFalse(model.isPreparingLiveNavigation)
      XCTAssertTrue(
        model.canStartLiveNavigation,
        "Expected live admission for \(entryFacilityID) -> \(exitFacilityID), blocker: \(model.liveNavigationBlockerCode ?? "none")"
      )
      XCTAssertNil(
        model.liveNavigationBlockerCode,
        "Unexpected blocker for \(entryFacilityID) -> \(exitFacilityID)"
      )
    }
  }

  func testLiveJourneyStartsAtCurrentPositionWithSurfaceInstruction()
    async throws
  {
    let output = WholeShutoRecordingSpeechOutput()
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoInstructionSurfaceRouteResolver(),
      checkpointStore: nil,
      speechOutput: output
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6812, longitude: 139.7671)
    )
    model.prepareCustomRouteDraft()
    model.selectCustomEntry(facilityID: "shuto.ic.b.urayasu")
    model.selectCustomExit(facilityID: "shuto.ic.9.fukudumi")
    XCTAssertTrue(model.applyCustomRoute())
    for _ in 0..<300
    where model.isPreparingLiveNavigation || model.isUpdatingSurfaceRoute {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }

    let started = await model.startLiveJourney()
    XCTAssertTrue(started)
    XCTAssertTrue(model.isLiveDrive)
    XCTAssertEqual(model.phase, .surfaceAccess)
    XCTAssertEqual(model.activeSurfaceInstruction, "Continue on local road")
    XCTAssertEqual(
      try XCTUnwrap(model.activeSurfaceInstructionRemainingMeters),
      1_200,
      accuracy: 0.01
    )
    let command = try XCTUnwrap(output.commands.only)
    XCTAssertEqual(command.routePlanID, model.selectedRoute?.routePlan.id)
    XCTAssertEqual(command.languageCode, "en-US")
    XCTAssertEqual(command.spokenText, "Continue on local road")
    XCTAssertTrue(command.identity.promptID.hasPrefix("provider.surface."))
    model.reset()
  }

  func testLiveSurfaceSpeechPreannouncesNextStepExactlyOnce()
    async throws
  {
    let output = WholeShutoRecordingSpeechOutput()
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoMultiStepSurfaceRouteResolver(),
      checkpointStore: nil,
      speechOutput: output
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6812, longitude: 139.7671)
    )
    model.prepareCustomRouteDraft()
    model.selectCustomEntry(facilityID: "shuto.ic.b.urayasu")
    model.selectCustomExit(facilityID: "shuto.ic.9.fukudumi")
    XCTAssertTrue(model.applyCustomRoute())
    for _ in 0..<300
    where model.isPreparingLiveNavigation || model.isUpdatingSurfaceRoute {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }

    let started = await model.startLiveJourney()
    XCTAssertTrue(started)
    XCTAssertEqual(output.commands.map(\.spokenText), ["Continue straight"])
    let route = try XCTUnwrap(model.accessRoute)
    let start = try XCTUnwrap(route.coordinates.first)
    let end = try XCTUnwrap(route.coordinates.last)
    let midpoint = ShutoCoordinate(
      latitude: (start.latitude + end.latitude) / 2,
      longitude: (start.longitude + end.longitude) / 2
    )
    let envelope = Self.liveLocationEnvelope(
      id: "surface.preannounce",
      coordinate: midpoint
    )
    await model.consumeLiveObservationForTesting(envelope)
    await model.consumeLiveObservationForTesting(envelope)

    XCTAssertEqual(
      output.commands.map(\.spokenText),
      ["Continue straight", "Turn left"]
    )
    model.reset()
  }

  func testLiveSurfaceAccessReroutesAfterTwoConsecutiveOffRouteFixes()
    async throws
  {
    let locationSource = WholeShutoBackgroundNavigationLocationSource()
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoInstructionSurfaceRouteResolver(),
      checkpointStore: nil,
      liveLocationSource: locationSource,
      speechOutput: WholeShutoRecordingSpeechOutput()
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6812, longitude: 139.7671)
    )
    model.prepareCustomRouteDraft()
    model.selectCustomEntry(facilityID: "shuto.ic.b.urayasu")
    model.selectCustomExit(facilityID: "shuto.ic.9.fukudumi")
    XCTAssertTrue(model.applyCustomRoute())
    for _ in 0..<300
    where model.isPreparingLiveNavigation || model.isUpdatingSurfaceRoute {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }

    let started = await model.startLiveJourney()
    XCTAssertTrue(started)
    let routePlan = try XCTUnwrap(model.selectedRoute?.routePlan)
    let route = try XCTUnwrap(model.accessRoute)
    let originalEgressRoute = try XCTUnwrap(model.egressRoute)
    let start = try XCTUnwrap(route.coordinates.first)
    let end = try XCTUnwrap(route.coordinates.last)
    let midpoint = ShutoCoordinate(
      latitude: (start.latitude + end.latitude) / 2,
      longitude: (start.longitude + end.longitude) / 2
    )
    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(id: "surface.midpoint", coordinate: midpoint)
    )

    XCTAssertEqual(model.phase, .surfaceAccess)
    XCTAssertEqual(model.liveLocationState, .available)
    XCTAssertEqual(model.progressFraction, 0.5, accuracy: 0.02)
    XCTAssertEqual(
      try XCTUnwrap(model.activeSurfaceInstructionRemainingMeters),
      600,
      accuracy: 25
    )

    let acceptedProgress = model.progressFraction
    let offRoute = ShutoCoordinate(
      latitude: midpoint.latitude + 0.01,
      longitude: midpoint.longitude
    )
    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(id: "surface.off-route.0", coordinate: offRoute)
    )

    XCTAssertEqual(model.phase, .surfaceAccess)
    XCTAssertEqual(model.liveLocationState, .degraded)
    XCTAssertEqual(model.liveLocationIssueCode, "SURFACE_ROUTE_OFF_ROUTE")
    XCTAssertEqual(model.progressFraction, acceptedProgress, accuracy: 0.001)
    XCTAssertEqual(model.accessRoute, route)
    XCTAssertFalse(model.isReroutingSurfaceRoute)

    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(id: "surface.off-route.1", coordinate: offRoute)
    )
    for _ in 0..<100
    where model.accessRoute?.coordinates.first != offRoute {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }

    XCTAssertEqual(model.phase, .surfaceAccess)
    XCTAssertEqual(model.selectedRoute?.routePlan, routePlan)
    XCTAssertEqual(model.accessRoute?.coordinates.first, offRoute)
    XCTAssertEqual(model.accessRoute?.coordinates.last, route.coordinates.last)
    XCTAssertEqual(model.egressRoute, originalEgressRoute)
    XCTAssertEqual(model.activeSurfaceInstruction, "Continue on local road")
    XCTAssertEqual(model.progressFraction, 0, accuracy: 0.001)
    XCTAssertEqual(model.liveLocationState, .available)
    XCTAssertNil(model.liveLocationIssueCode)
    XCTAssertFalse(model.isReroutingSurfaceRoute)
    model.reset()
  }

  func testReleasedLiveRecoveryKeepsConsumingLocationUntilRouteRejoin()
    async throws
  {
    var nowMilliseconds = 1_000
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil,
      speechOutput: WholeShutoRecordingSpeechOutput(),
      nowMillisecondsProvider: { nowMilliseconds }
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6763, longitude: 139.7720)
    )
    model.prepareCustomRouteDraft()
    model.selectCustomEntry(facilityID: "shuto.ic.b.rinkaihukutoshin")
    model.selectCustomExit(facilityID: "shuto.ic.b.daikokufutou")
    XCTAssertTrue(model.applyCustomRoute())
    for _ in 0..<300
    where model.isPreparingLiveNavigation || model.isUpdatingSurfaceRoute
      || !model.canStartLiveNavigation
    {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }

    let route = try XCTUnwrap(model.selectedRoute)
    let context = try ShutoPlannedRouteRuntimeCompiler.NetworkContext(
      database: model.database
    )
    let release =
      try ShutoCircuitProductReleaseBuilder
      .buildPlannedRouteRelease(context: context, route: route)
    let recovery = try XCTUnwrap(
      release.navigation.bundle.runtimePolicy.recoveryCandidates.first
    )
    let divergence = try XCTUnwrap(
      route.routePlan.occurrence(id: recovery.divergenceOccurrenceID)
    )
    let target = try XCTUnwrap(
      route.routePlan.occurrence(id: recovery.targetOccurrenceID)
    )
    XCTAssertLessThan(divergence.index, target.index)
    XCTAssertFalse(recovery.recoveryOccurrenceIDs.isEmpty)

    let started = await model.startLiveJourney()
    XCTAssertTrue(started)
    let corridorEdges = Dictionary(
      uniqueKeysWithValues: release.navigation.bundle.matcherCorridor.edges
        .map { ($0.id, $0) }
    )
    let corridorOccurrences = release.navigation.bundle.matcherCorridor
      .occurrences.sorted { $0.index < $1.index }
    let accessEnd = try XCTUnwrap(model.accessRoute?.coordinates.last)
    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(
        id: "recovery.access-end",
        coordinate: accessEnd,
        atMilliseconds: nowMilliseconds,
        courseDegrees: Self.bearing(
          from: route.coordinates[0],
          to: route.coordinates[1]
        )
      )
    )

    for occurrence in corridorOccurrences
    where occurrence.index <= divergence.index {
      let edge = try XCTUnwrap(corridorEdges[occurrence.directedEdgeID])
      let start = try XCTUnwrap(edge.coordinates.first)
      let end = try XCTUnwrap(edge.coordinates.last)
      let startCoordinate = ShutoCoordinate(
        latitude: start.latitude,
        longitude: start.longitude
      )
      let endCoordinate = ShutoCoordinate(
        latitude: end.latitude,
        longitude: end.longitude
      )
      for fraction in [0.25, 0.75] {
        nowMilliseconds += 1_000
        await model.consumeLiveObservationForTesting(
          Self.liveLocationEnvelope(
            id: "recovery.route.\(occurrence.index).\(fraction)",
            coordinate: Self.interpolate(
              from: startCoordinate,
              to: endCoordinate,
              fraction: fraction
            ),
            atMilliseconds: nowMilliseconds,
            courseDegrees: Self.bearing(
              from: startCoordinate,
              to: endCoordinate
            )
          )
        )
      }
    }
    XCTAssertEqual(model.phase, .expressway)
    XCTAssertEqual(model.runtimeJourneyPhase, .strictRoute)
    XCTAssertLessThanOrEqual(
      try XCTUnwrap(
        route.routePlan.occurrence(
          id: try XCTUnwrap(model.runtimeOccurrenceID)
        )
      ).index,
      divergence.index
    )
    let preRecoveryCoordinate = try XCTUnwrap(model.currentCoordinate)

    var observedActiveRecovery = false
    for edgeID in recovery.recoveryOccurrenceIDs {
      let edge = try XCTUnwrap(corridorEdges[edgeID])
      let start = try XCTUnwrap(edge.coordinates.first)
      let end = try XCTUnwrap(edge.coordinates.last)
      let startCoordinate = ShutoCoordinate(
        latitude: start.latitude,
        longitude: start.longitude
      )
      let endCoordinate = ShutoCoordinate(
        latitude: end.latitude,
        longitude: end.longitude
      )
      for fraction in [0.25, 0.75] {
        nowMilliseconds += 1_000
        await model.consumeLiveObservationForTesting(
          Self.liveLocationEnvelope(
            id: "recovery.path.\(edgeID).\(fraction)",
            coordinate: Self.interpolate(
              from: startCoordinate,
              to: endCoordinate,
              fraction: fraction
            ),
            atMilliseconds: nowMilliseconds,
            courseDegrees: Self.bearing(
              from: startCoordinate,
              to: endCoordinate
            )
          )
        )
        if model.runtimeRecoveryStatus == .active {
          observedActiveRecovery = true
          XCTAssertTrue(model.isPlaying)
          XCTAssertTrue(model.canConsumeForegroundNavigationLocations)
          XCTAssertEqual(
            model.runtimeRecoveryTargetOccurrenceID,
            recovery.targetOccurrenceID
          )
          XCTAssertFalse(model.activeRecoveryRouteCoordinates.isEmpty)
          XCTAssertNotEqual(model.currentCoordinate, preRecoveryCoordinate)
        }
      }
    }
    XCTAssertTrue(observedActiveRecovery)

    for occurrence in corridorOccurrences
    where occurrence.index >= target.index
      && occurrence.index < target.index + 2
    {
      let edge = try XCTUnwrap(corridorEdges[occurrence.directedEdgeID])
      let start = try XCTUnwrap(edge.coordinates.first)
      let end = try XCTUnwrap(edge.coordinates.last)
      let startCoordinate = ShutoCoordinate(
        latitude: start.latitude,
        longitude: start.longitude
      )
      let endCoordinate = ShutoCoordinate(
        latitude: end.latitude,
        longitude: end.longitude
      )
      for fraction in [0.25, 0.75] {
        nowMilliseconds += 1_000
        await model.consumeLiveObservationForTesting(
          Self.liveLocationEnvelope(
            id: "recovery.rejoin.\(occurrence.index).\(fraction)",
            coordinate: Self.interpolate(
              from: startCoordinate,
              to: endCoordinate,
              fraction: fraction
            ),
            atMilliseconds: nowMilliseconds,
            courseDegrees: Self.bearing(
              from: startCoordinate,
              to: endCoordinate
            )
          )
        )
      }
    }

    XCTAssertEqual(model.runtimeJourneyPhase, .strictRoute)
    XCTAssertEqual(model.runtimeRecoveryStatus, .inactive)
    XCTAssertNil(model.runtimeRecoveryTargetOccurrenceID)
    XCTAssertNil(model.runtimeRecoveryDirectedEdgeID)
    XCTAssertTrue(model.activeRecoveryRouteCoordinates.isEmpty)
    XCTAssertTrue(model.isPlaying)
    XCTAssertGreaterThanOrEqual(
      try XCTUnwrap(
        route.routePlan.occurrence(id: try XCTUnwrap(model.runtimeOccurrenceID))
      ).index,
      target.index
    )
    model.reset()
  }

  func testLiveTunnelGapCoastsPresentationWithoutAdvancingAuthority()
    async throws
  {
    var nowMilliseconds = 1_000
    let output = WholeShutoRecordingSpeechOutput()
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil,
      speechOutput: output,
      nowMillisecondsProvider: { nowMilliseconds }
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6275, longitude: 139.7730)
    )
    model.prepareCustomRouteDraft()
    model.selectCustomEntry(
      facilityID: "shuto.ic.b.rinkaihukutoshin"
    )
    model.selectCustomExit(
      facilityID: "shuto.ic.c2.hatsudaiminami"
    )
    XCTAssertTrue(model.applyCustomRoute())
    for _ in 0..<300
    where model.isPreparingLiveNavigation || model.isUpdatingSurfaceRoute
      || !model.canStartLiveNavigation
    {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }
    XCTAssertTrue(
      model.canStartLiveNavigation,
      model.liveNavigationBlockerCode ?? "no blocker code"
    )
    let started = await model.startLiveJourney()
    XCTAssertTrue(started)

    let route = try XCTUnwrap(model.selectedRoute)
    let accessEnd = try XCTUnwrap(model.accessRoute?.coordinates.last)
    let initialCourse = Self.bearing(
      from: route.coordinates[0],
      to: route.coordinates[1]
    )
    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(
        id: "tunnel.access-end",
        coordinate: accessEnd,
        atMilliseconds: nowMilliseconds,
        courseDegrees: initialCourse
      )
    )

    var observationIndex = 0
    for edgeIndex in route.edges.indices {
      let start = route.coordinates[edgeIndex]
      let end = route.coordinates[edgeIndex + 1]
      let course = Self.bearing(from: start, to: end)
      for fraction in [0.25, 0.75] {
        observationIndex += 1
        nowMilliseconds += 1_000
        let coordinate = ShutoCoordinate(
          latitude: start.latitude
            + (end.latitude - start.latitude) * fraction,
          longitude: start.longitude
            + (end.longitude - start.longitude) * fraction
        )
        await model.consumeLiveObservationForTesting(
          Self.liveLocationEnvelope(
            id: "tunnel.route.\(observationIndex)",
            coordinate: coordinate,
            atMilliseconds: nowMilliseconds,
            courseDegrees: course,
            speedMetersPerSecond: 18
          )
        )
        if model.phase == .expressway,
          model.liveLocationState == .available,
          model.positionState == .tunnelEstimated,
          model.runtimeOccurrenceID != nil
        {
          break
        }
      }
      if model.phase == .expressway,
        model.liveLocationState == .available,
        model.positionState == .tunnelEstimated,
        model.runtimeOccurrenceID != nil
      {
        break
      }
    }

    XCTAssertEqual(model.phase, .expressway)
    XCTAssertEqual(model.liveLocationState, .available)
    XCTAssertEqual(model.positionState, .tunnelEstimated)
    let authoritativeOccurrence = try XCTUnwrap(model.runtimeOccurrenceID)
    let authoritativeProgress = model.progressFraction
    let authoritativeCoordinate = try XCTUnwrap(model.currentCoordinate)
    let spokenPromptCount = output.commands.count

    nowMilliseconds += WholeShutoProductModel.liveLocationStaleAfterMilliseconds
    model.evaluateLiveLocationFreshness(
      atMilliseconds: nowMilliseconds
    )

    XCTAssertEqual(model.liveLocationState, .stale)
    XCTAssertEqual(model.positionState, .tunnelEstimated)
    XCTAssertEqual(model.runtimeOccurrenceID, authoritativeOccurrence)
    XCTAssertEqual(model.progressFraction, authoritativeProgress)
    XCTAssertGreaterThan(
      try XCTUnwrap(model.tunnelEstimatedProgressFraction),
      authoritativeProgress
    )
    XCTAssertGreaterThan(
      try XCTUnwrap(model.tunnelEstimateUncertaintyMeters),
      TunnelPositionEstimator.minimumUncertaintyRadiusMeters
    )
    XCTAssertNotEqual(model.currentCoordinate, authoritativeCoordinate)
    XCTAssertEqual(output.commands.count, spokenPromptCount)

    nowMilliseconds += 1_000
    let unrelatedRawCoordinate = ShutoCoordinate(
      latitude: 35.0,
      longitude: 140.0
    )
    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(
        id: "tunnel.weak-unrelated-fix",
        coordinate: unrelatedRawCoordinate,
        atMilliseconds: nowMilliseconds,
        courseDegrees: 0,
        speedMetersPerSecond: 18
      )
    )

    XCTAssertNotEqual(model.currentCoordinate, unrelatedRawCoordinate)
    XCTAssertEqual(model.runtimeOccurrenceID, authoritativeOccurrence)
    XCTAssertEqual(model.progressFraction, authoritativeProgress)
    XCTAssertEqual(output.commands.count, spokenPromptCount)
    model.reset()
  }

  func testLiveJourneyContinuesWhenScreenLocksAndStopsWhenEnded()
    async throws
  {
    let locationSource = WholeShutoBackgroundNavigationLocationSource()
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoInstructionSurfaceRouteResolver(),
      checkpointStore: nil,
      liveLocationSource: locationSource,
      speechOutput: WholeShutoRecordingSpeechOutput()
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6812, longitude: 139.7671)
    )
    model.prepareCustomRouteDraft()
    model.selectCustomEntry(facilityID: "shuto.ic.b.urayasu")
    model.selectCustomExit(facilityID: "shuto.ic.9.fukudumi")
    XCTAssertTrue(model.applyCustomRoute())
    for _ in 0..<300
    where model.isPreparingLiveNavigation || model.isUpdatingSurfaceRoute {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }

    let started = await model.startLiveJourney()
    XCTAssertTrue(started)
    XCTAssertTrue(model.isPlaying)
    XCTAssertEqual(locationSource.startCount, 1)
    XCTAssertTrue(locationSource.backgroundNavigationEnabled)

    await model.handleScenePhase(.inactive)
    await model.handleScenePhase(.background)

    XCTAssertTrue(model.isLiveDrive)
    XCTAssertTrue(model.isPlaying)
    XCTAssertNotEqual(model.liveLocationState, .resumeRequired)
    XCTAssertNotEqual(model.liveLocationIssueCode, "LIVE_RESUME_REQUIRED")
    XCTAssertEqual(locationSource.startCount, 1)
    XCTAssertEqual(locationSource.stopCount, 0)
    XCTAssertTrue(locationSource.backgroundNavigationEnabled)

    await model.handleScenePhase(.active)
    XCTAssertTrue(model.isPlaying)
    XCTAssertEqual(locationSource.startCount, 1)

    model.reset()
    for _ in 0..<100 where locationSource.stopCount == 0 {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertEqual(locationSource.stopCount, 1)
    XCTAssertFalse(locationSource.backgroundNavigationEnabled)
  }

  func testFirstLocationPermissionRoundTripStartsTheSameLiveJourney()
    async throws
  {
    let locationSource = WholeShutoBackgroundNavigationLocationSource(
      authorizationStatus: .notDetermined
    )
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoInstructionSurfaceRouteResolver(),
      checkpointStore: nil,
      liveLocationSource: locationSource,
      speechOutput: WholeShutoRecordingSpeechOutput()
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6812, longitude: 139.7671)
    )
    model.prepareCustomRouteDraft()
    model.selectCustomEntry(facilityID: "shuto.ic.b.urayasu")
    model.selectCustomExit(facilityID: "shuto.ic.9.fukudumi")
    XCTAssertTrue(model.applyCustomRoute())
    for _ in 0..<300
    where model.isPreparingLiveNavigation || model.isUpdatingSurfaceRoute {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }

    let started = await model.startLiveJourney()
    XCTAssertTrue(started)
    XCTAssertTrue(model.isPlaying)
    XCTAssertEqual(model.liveLocationState, .awaitingAuthorization)
    XCTAssertEqual(locationSource.authorizationRequestCount, 1)
    XCTAssertEqual(locationSource.startCount, 0)

    await model.handleScenePhase(.inactive)
    locationSource.deliverAuthorization(.authorizedWhenInUse)
    await model.handleScenePhase(.active)

    XCTAssertTrue(model.isPlaying)
    XCTAssertEqual(model.liveLocationState, .acquiring)
    XCTAssertEqual(locationSource.startCount, 1)
    XCTAssertTrue(locationSource.backgroundNavigationEnabled)
    model.reset()
  }

  func testOnDeviceRouteAuthorityAdmitsYokohamaRouteAfterCompleteReview()
    throws
  {
    let database = try WholeShutoNetworkCatalog.bundled()
    let route = try ShutoRoutePlanner(database: database).plan(
      entryFacilityID: "shuto.ic.k1.yokohamakouen",
      exitFacilityID: "shuto.ic.k7-yokohama-hokusei.yokohamaaoba"
    )
    let authority = try WholeShutoRouteReleaseAuthority(database: database)

    switch authority.resolve(route: route) {
    case .available(let admission):
      XCTAssertEqual(admission.core.selectedRoutePlan, route.routePlan)
    case .unavailable(let code):
      XCTFail("Expected live admission after complete review, got \(code)")
    }
  }

  func testOnDeviceRouteAuthorityAdmitsRinkaiToHatsudaiWithoutPredecessor()
    throws
  {
    let database = try WholeShutoNetworkCatalog.bundled()
    let route = try ShutoRoutePlanner(database: database).plan(
      entryFacilityID: "shuto.ic.b.rinkaihukutoshin",
      exitFacilityID: "shuto.ic.c2.hatsudaiminami"
    )
    let reconstructed = try ShutoRoutePlanner(database: database)
      .restore(routePlan: route.routePlan)
    XCTAssertEqual(reconstructed, route)
    let artifact =
      try ShutoCircuitProductReleaseBuilder
      .buildPlannedRouteArtifact(
        database: database,
        route: reconstructed
      )
    let release = try KaidoProductRelease(artifact: artifact)
    XCTAssertEqual(
      release.navigation.bundle.runtimePolicy.entryTransition
        .directedEdgeIDs,
      Array(route.edges.prefix(2).map(\.edgeID))
    )
    XCTAssertEqual(
      release.navigation.bundle.runtimePolicy.entryTransition
        .firstRouteOccurrenceID,
      route.routePlan.occurrences.first?.id
    )
    let core = try KaidoLiveJourneyAdmission(
      release: release,
      selectedRoutePlan: route.routePlan,
      journeyPlan: JourneyPlanCompiler.expresswayOnly(release: release)
    )
    XCTAssertEqual(core.selectedRoutePlan, route.routePlan)
    let authority = try WholeShutoRouteReleaseAuthority(database: database)

    switch authority.resolve(route: route) {
    case .available(let admission):
      XCTAssertEqual(admission.core.selectedRoutePlan, route.routePlan)
    case .unavailable(let code):
      XCTFail("Expected live admission, got \(code)")
    }
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

  func testRecommendedAndCustomRoutesExposeCurrentTariffBand() throws {
    let model = WholeShutoProductModel(checkpointStore: nil)
    model.preparePreviewJourney()
    let recommendedBand = try XCTUnwrap(model.selectedTariffBand)
    XCTAssertGreaterThan(recommendedBand.quotedYen, 0)
    XCTAssertEqual(
      model.savedRouteTemplateParameters,
      [
        "source": "RECOMMENDATION",
        "preference": model.selectedRoute?.preference.rawValue ?? "",
      ]
    )

    let customModel = WholeShutoProductModel(checkpointStore: nil)
    customModel.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6586, longitude: 139.7454)
    )
    customModel.prepareCustomRouteDraft()
    XCTAssertTrue(customModel.applyCustomRoute())
    let customBand = try XCTUnwrap(customModel.selectedTariffBand)
    XCTAssertGreaterThan(customBand.quotedYen, 0)
    XCTAssertEqual(
      customModel.savedRouteTemplateParameters["source"],
      "CUSTOM"
    )
  }

  func testTariffBandSurvivesReviewCheckpointRestore() throws {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: store)
    model.preparePreviewJourney()
    let expected = try XCTUnwrap(model.selectedTariffBand)

    let restored = WholeShutoProductModel(
      database: model.database,
      checkpointStore: store
    )

    XCTAssertEqual(restored.phase, .review)
    XCTAssertEqual(restored.selectedTariffBand, expected)
  }

  func testFreshlySavedRecommendedRouteReopensOnCurrentSnapshot()
    throws
  {
    let source = WholeShutoProductModel(checkpointStore: nil)
    source.preparePreviewJourney()
    let route = try XCTUnwrap(source.selectedRoute)
    XCTAssertEqual(
      route.routePlan.id,
      "shuto.shuto.ic.c1.ginza.shuto.ic.k1.yokohamakouen.recommended"
    )
    XCTAssertEqual(route.routePlan.occurrences.count, 789)
    XCTAssertEqual(
      source.savedRouteTemplateParameters,
      [
        "source": "RECOMMENDATION",
        "preference": "RECOMMENDED",
      ]
    )
    let restoredRoute = try source.planner.restore(
      routePlan: route.routePlan,
      preference: route.preference
    )
    XCTAssertEqual(restoredRoute.routePlan, route.routePlan)
    XCTAssertNoThrow(
      try ShutoPlannedRouteRuntimeCompiler.compile(
        database: source.database,
        route: restoredRoute
      )
    )

    let libraryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "kaido-saved-recommended-\(UUID().uuidString)",
        isDirectory: true
      )
    defer {
      try? FileManager.default.removeItem(at: libraryDirectory)
    }
    let libraryStore = try FileSavedRouteLibraryStore(
      directoryURL: libraryDirectory
    )
    let library = SavedRouteLibraryModel(
      store: libraryStore,
      foregroundEntries: [],
      recordIDProvider: { "saved-route.recommended-preview" },
      savedAtProvider: { "2026-08-12T12:00:00Z" }
    )
    library.save(
      routePlan: route.routePlan,
      displayName: "Tokyo Yokohama Snapshot",
      evidenceState: .communityCandidate,
      templateParameters: source.savedRouteTemplateParameters
    )
    XCTAssertNil(library.lastErrorCode)

    let reloadedStore = try FileSavedRouteLibraryStore(
      directoryURL: libraryDirectory
    )
    let reloadedLibrary = SavedRouteLibraryModel(
      store: reloadedStore,
      foregroundEntries: []
    )
    let record = try XCTUnwrap(reloadedLibrary.records.first)
    XCTAssertEqual(record.document.routePlan, route.routePlan)
    XCTAssertEqual(
      record.document.templateParameters,
      source.savedRouteTemplateParameters
    )

    let reopened = WholeShutoProductModel(
      database: source.database,
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    XCTAssertEqual(
      reopened.savedRouteAvailability(record),
      .currentSnapshot(source.database.networkSnapshotID)
    )
    XCTAssertTrue(
      reopened.openSavedRoute(
        record,
        origin: source.origin?.coordinate
      )
    )
    XCTAssertEqual(reopened.phase, .review)
    XCTAssertEqual(reopened.selectedRoute?.routePlan, route.routePlan)
    XCTAssertFalse(reopened.isCircuitRouteSelected)
    XCTAssertFalse(reopened.isCustomRouteSelected)
    XCTAssertEqual(
      reopened.savedRouteTemplateParameters,
      source.savedRouteTemplateParameters
    )
  }

  func testSavedCircuitRouteOpensExactRepeatedPlanOnCurrentSnapshot()
    async throws
  {
    let source = WholeShutoProductModel(checkpointStore: nil)
    let circuitRoute = try source.planner.planCircuit(
      circuit: .c2InnerWithBayshore,
      entryFacilityID: "shuto.ic.c2.hatsudaiminami",
      exitFacilityID: "shuto.ic.c2.tomigaya",
      laps: 2
    )
    let templateParameters = [
      "source": "CIRCUIT",
      "preference": circuitRoute.preference.rawValue,
      "circuit_id": ShutoCircuitDefinition.c2InnerWithBayshore.circuitID,
      "laps": "2",
    ]
    let record = Self.savedRouteRecord(
      circuitRoute.routePlan,
      templateParameters: templateParameters
    )
    let model = WholeShutoProductModel(
      database: source.database,
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )

    XCTAssertEqual(
      model.savedRouteAvailability(record),
      .currentSnapshot(source.database.networkSnapshotID)
    )
    let origin = ShutoCoordinate(
      latitude: 35.6798,
      longitude: 139.6862
    )
    XCTAssertTrue(model.openSavedRoute(record, origin: origin))
    for _ in 0..<1_000 where model.isUpdatingSurfaceRoute {
      await Task.yield()
    }

    XCTAssertEqual(model.phase, .review)
    XCTAssertTrue(model.isCircuitRouteSelected)
    XCTAssertFalse(model.isCustomRouteSelected)
    XCTAssertEqual(
      model.selectedCircuit,
      .c2InnerWithBayshore
    )
    XCTAssertEqual(model.circuitLaps, 2)
    XCTAssertEqual(model.savedRouteTemplateParameters, templateParameters)
    XCTAssertEqual(model.selectedRoute?.routePlan, circuitRoute.routePlan)
    XCTAssertEqual(model.origin?.coordinate, origin)
    XCTAssertEqual(
      model.destination?.coordinate,
      circuitRoute.exitFacility.coordinate
    )
    XCTAssertEqual(
      model.destination?.title,
      circuitRoute.exitFacility.nameJA
    )
    XCTAssertNotNil(model.accessRoute)
    XCTAssertNotNil(model.egressRoute)
    XCTAssertNotNil(model.selectedTariffBand)
    let edgeIDs = try XCTUnwrap(model.selectedRoute?.edges.map(\.edgeID))
    XCTAssertLessThan(Set(edgeIDs).count, edgeIDs.count)
    XCTAssertFalse(model.canStartLiveNavigation)
  }

  func testSavedCircuitRouteResavePreservesTemplateProvenance()
    throws
  {
    let source = WholeShutoProductModel(checkpointStore: nil)
    let circuitRoute = try source.planner.planCircuit(
      circuit: .c2InnerWithBayshore,
      entryFacilityID: "shuto.ic.c2.hatsudaiminami",
      exitFacilityID: "shuto.ic.c2.tomigaya",
      laps: 2
    )
    let templateParameters = [
      "source": "CIRCUIT",
      "preference": circuitRoute.preference.rawValue,
      "circuit_id": ShutoCircuitDefinition.c2InnerWithBayshore.circuitID,
      "laps": "2",
      "variant": "NIGHT",
    ]
    let record = Self.savedRouteRecord(
      circuitRoute.routePlan,
      templateParameters: templateParameters
    )
    let model = WholeShutoProductModel(
      database: source.database,
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )

    XCTAssertTrue(
      model.openSavedRoute(
        record,
        origin: ShutoCoordinate(latitude: 35.68, longitude: 139.69)
      )
    )

    let libraryStore = WholeShutoMemorySavedRouteLibraryStore()
    let library = SavedRouteLibraryModel(
      store: libraryStore,
      foregroundEntries: [],
      recordIDProvider: { "saved-route.resaved-circuit" },
      savedAtProvider: { "2026-08-12T12:00:00Z" }
    )
    library.save(
      routePlan: model.selectedRoute?.routePlan,
      displayName: "Resaved circuit",
      evidenceState: .communityCandidate,
      templateParameters: model.savedRouteTemplateParameters
    )

    let resaved = try XCTUnwrap(library.records.first)
    XCTAssertEqual(resaved.document.routePlan, circuitRoute.routePlan)
    XCTAssertEqual(
      resaved.document.templateParameters,
      templateParameters
    )
    XCTAssertNil(library.lastErrorCode)
  }

  func testSavedCircuitMetadataMustMatchTheExactCircuitPlan() throws {
    let source = WholeShutoProductModel(checkpointStore: nil)
    let circuit = ShutoCircuitDefinition.c2InnerWithBayshore
    let circuitRoute = try source.planner.planCircuit(
      circuit: circuit,
      entryFacilityID: "shuto.ic.c2.hatsudaiminami",
      exitFacilityID: "shuto.ic.c2.tomigaya",
      laps: 2
    )
    let preference = circuitRoute.preference.rawValue
    let invalidParameters = [
      [
        "source": "UNKNOWN",
        "preference": preference,
      ],
      [
        "source": "CIRCUIT",
        "preference": preference,
        "circuit_id": circuit.circuitID,
      ],
      [
        "source": "CIRCUIT",
        "preference": preference,
        "circuit_id": "shuto.circuit.unknown",
        "laps": "2",
      ],
      [
        "source": "CIRCUIT",
        "preference": preference,
        "circuit_id": circuit.circuitID,
        "laps": "invalid",
      ],
      [
        "source": "CIRCUIT",
        "preference": preference,
        "circuit_id": circuit.circuitID,
        "laps": "1",
      ],
      [
        "source": "CUSTOM",
        "preference": preference,
        "circuit_id": circuit.circuitID,
        "laps": "2",
      ],
    ]

    for parameters in invalidParameters {
      let record = Self.savedRouteRecord(
        circuitRoute.routePlan,
        templateParameters: parameters
      )
      let model = WholeShutoProductModel(
        database: source.database,
        checkpointStore: nil
      )

      XCTAssertEqual(
        model.savedRouteAvailability(record),
        .invalid("SAVED_ROUTE_CURRENT_SNAPSHOT_INVALID")
      )
      XCTAssertFalse(
        model.openSavedRoute(
          record,
          origin: ShutoCoordinate(latitude: 35.68, longitude: 139.69)
        )
      )
      XCTAssertEqual(model.phase, .planning)
      XCTAssertNil(model.selectedRoute)
      XCTAssertEqual(
        model.failureCode,
        "SAVED_ROUTE_CURRENT_SNAPSHOT_INVALID"
      )
    }
  }

  func testSavedRouteSnapshotMismatchCannotOpen() throws {
    let source = WholeShutoProductModel(checkpointStore: nil)
    source.preparePreviewJourney()
    let plan = try XCTUnwrap(source.selectedRoute?.routePlan)
    let driftedPlan = RoutePlan(
      id: plan.id,
      networkSnapshotID: "shuto.future-snapshot",
      entryFacilityID: plan.entryFacilityID,
      exitFacilityID: plan.exitFacilityID,
      recoveryPolicy: plan.recoveryPolicy,
      actualDistanceKM: plan.actualDistanceKM,
      occurrences: plan.occurrences
    )
    let record = Self.savedRouteRecord(driftedPlan)
    let model = WholeShutoProductModel(
      database: source.database,
      checkpointStore: nil
    )

    XCTAssertEqual(model.savedRouteAvailability(record), .unavailable)
    XCTAssertFalse(
      model.openSavedRoute(
        record,
        origin: ShutoCoordinate(latitude: 35.68, longitude: 139.76)
      )
    )
    XCTAssertEqual(model.phase, .planning)
    XCTAssertEqual(
      model.failureCode,
      "SAVED_ROUTE_NETWORK_SNAPSHOT_MISMATCH"
    )
  }

  func testSavedRepeatedRouteSimulationRestoresExactProgress()
    async throws
  {
    let store = WholeShutoMemoryCheckpointStore()
    let source = WholeShutoProductModel(checkpointStore: nil)
    let circuitRoute = try source.planner.planCircuit(
      circuit: .c2InnerWithBayshore,
      entryFacilityID: "shuto.ic.c2.hatsudaiminami",
      exitFacilityID: "shuto.ic.c2.tomigaya",
      laps: 2
    )
    let record = Self.savedRouteRecord(
      circuitRoute.routePlan,
      templateParameters: [
        "source": "CIRCUIT",
        "preference": circuitRoute.preference.rawValue,
        "circuit_id": ShutoCircuitDefinition.c2InnerWithBayshore.circuitID,
        "laps": "2",
      ]
    )
    let model = WholeShutoProductModel(
      database: source.database,
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: store
    )
    XCTAssertTrue(
      model.openSavedRoute(
        record,
        origin: ShutoCoordinate(latitude: 35.68, longitude: 139.69)
      )
    )
    for _ in 0..<1_000 where model.isUpdatingSurfaceRoute {
      await Task.yield()
    }
    model.startNavigationSimulation()
    _ = await model.pausePlayback()
    await advance(
      model,
      until: {
        $0.phase == .expressway && $0.progressFraction > 0.02
      },
      maximumTicks: 1_000
    )
    let expectedProgress = model.progressFraction
    let expectedOccurrenceID = try XCTUnwrap(model.runtimeOccurrenceID)
    XCTAssertEqual(model.selectedRoute?.routePlan, circuitRoute.routePlan)

    let restored = WholeShutoProductModel(
      database: source.database,
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: store
    )

    XCTAssertEqual(restored.phase, .expressway)
    XCTAssertEqual(restored.selectedRoute?.routePlan, circuitRoute.routePlan)
    XCTAssertEqual(restored.runtimeOccurrenceID, expectedOccurrenceID)
    XCTAssertEqual(restored.progressFraction, expectedProgress)
    XCTAssertFalse(restored.isCustomRouteSelected)
    XCTAssertTrue(restored.isCircuitRouteSelected)
    XCTAssertEqual(restored.selectedCircuit, .c2InnerWithBayshore)
    XCTAssertEqual(restored.circuitLaps, 2)
    XCTAssertTrue(restored.restoredFromCheckpoint)
    XCTAssertNil(restored.failureCode)
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

  private func waitForLiveNavigationPreparation(
    _ model: WholeShutoProductModel
  ) async {
    for _ in 0..<1_000
    where model.isPreparingLiveNavigation
      || !model.canStartLiveNavigation
    {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }
  }

  func testCircuitLapControlFollowsPlannerRange() {
    let model = WholeShutoProductModel(checkpointStore: nil)
    let range = ShutoCircuitDefinition.loopLapRange

    model.selectCircuit(.c2InnerWithBayshore)
    XCTAssertEqual(model.circuitLaps, range.lowerBound)

    model.selectCircuitLaps(range.lowerBound - 1)
    XCTAssertEqual(model.circuitLaps, range.lowerBound)

    model.selectCircuitLaps(range.upperBound)
    XCTAssertEqual(model.circuitLaps, range.upperBound)

    model.selectCircuitLaps(range.upperBound + 1)
    XCTAssertEqual(model.circuitLaps, range.upperBound)

    model.selectCircuit(.scenicGrandTour)
    XCTAssertEqual(model.circuitLaps, 1)
    model.selectCircuitLaps(2)
    XCTAssertEqual(model.circuitLaps, 1)
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
    XCTAssertEqual(
      model.savedRouteTemplateParameters,
      [
        "source": "CIRCUIT",
        "preference": route.preference.rawValue,
        "circuit_id": "shuto.circuit.c2-inner-bayshore",
        "laps": "2",
      ]
    )
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
    _ = await model.pausePlayback()
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

  func testPauseReturnsOnlyAfterPlaybackIsStable() async throws {
    let model = WholeShutoProductModel(checkpointStore: nil)
    model.preparePreviewJourney()
    model.startNavigationSimulation()

    try await Task.sleep(nanoseconds: 500_000_000)
    let pausedActivePlayback = await model.pausePlayback()
    XCTAssertTrue(pausedActivePlayback)
    let pausedPhase = model.phase
    let pausedProgress = model.progressFraction
    let pausedOccurrenceID = model.runtimeOccurrenceID

    try await Task.sleep(nanoseconds: 650_000_000)
    XCTAssertFalse(model.isPlaying)
    XCTAssertEqual(model.phase, pausedPhase)
    XCTAssertEqual(model.progressFraction, pausedProgress)
    XCTAssertEqual(model.runtimeOccurrenceID, pausedOccurrenceID)
    let pausedAgain = await model.pausePlayback()
    XCTAssertFalse(pausedAgain)

    model.resumePlayback()
    XCTAssertTrue(model.isPlaying)
    _ = await model.pausePlayback()
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

    // The preview journey now crosses reviewed junctions, and every prompt
    // it carries must still come from an exact reviewed movement definition;
    // a prompt is never synthesized from route geometry alone.
    XCTAssertTrue(
      model.junctionPrompts.allSatisfy { prompt in
        ShutoJunctionMovementCatalog.released.contains {
          $0.id == prompt.movementID
        }
      }
    )

    model.prepareJunctionPreview()

    let prompt = model.junctionPrompts.first {
      $0.movementID == "shuto.jct.oi.b-westbound-to-c2-outer"
    }
    XCTAssertNotNil(prompt)
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

      // The Bayshore continuations are reviewed too, so select the
      // movement under test rather than assuming it is the only prompt.
      let prompt = model.junctionPrompts.first {
        $0.movementID == testCase.movementID
      }
      XCTAssertNotNil(prompt)
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

      // The westbound approach now also passes a reviewed Tatsumi
      // continuation, so select the movement under test.
      let prompt = model.junctionPrompts.first {
        $0.movementID == testCase.movementID
      }
      XCTAssertNotNil(prompt)
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
    _ = await model.pausePlayback()
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
    _ = await model.pausePlayback()
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

  func testLiveCheckpointReturnsToReviewWithoutSimulationOrProgress() {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: store)
    model.preparePreviewJourney()
    model.startNavigationSimulation()

    let checkpoint = try? XCTUnwrap(store.checkpoint)
    XCTAssertNotNil(checkpoint)
    store.checkpoint = checkpoint?.replacingDriveMode(
      .live,
      progressFraction: 0.72
    )

    let restored = WholeShutoProductModel(
      database: model.database,
      checkpointStore: store
    )

    XCTAssertTrue(restored.restoredFromCheckpoint)
    XCTAssertEqual(restored.phase, .review)
    XCTAssertEqual(restored.progressFraction, 0)
    XCTAssertFalse(restored.isLiveDrive)
    XCTAssertFalse(restored.isPlaying)
    XCTAssertNil(restored.runtimeOccurrenceID)
    XCTAssertEqual(
      restored.failureCode,
      "WHOLE_SHUTO_NAVIGATION_RELEASE_REQUIRED"
    )
    XCTAssertEqual(
      restored.liveLocationIssueCode,
      "WHOLE_SHUTO_NAVIGATION_RELEASE_REQUIRED"
    )
    XCTAssertEqual(
      restored.selectedRoute?.routePlan,
      checkpoint?.routePlan
    )
    XCTAssertEqual(restored.accessRoute, checkpoint?.accessRoute)
    XCTAssertEqual(restored.egressRoute, checkpoint?.egressRoute)
  }

  func testSimulationCheckpointRejectsRuntimeAssetIdentityDrift()
    async throws
  {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: store)
    model.preparePreviewJourney()
    model.startNavigationSimulation()
    _ = await model.pausePlayback()
    await advance(model, until: { $0.phase == .entryTransition })

    let checkpoint = try XCTUnwrap(store.checkpoint)
    XCTAssertNotNil(checkpoint.runtimeAssetIdentity)
    let otherRoute = try model.planner.plan(
      entryFacilityID: "shuto.ic.b.urayasu",
      exitFacilityID: "shuto.ic.9.fukudumi"
    )
    let otherIdentity = try ShutoPlannedRouteRuntimeCompiler.compile(
      database: model.database,
      route: otherRoute
    ).runtimeAssetIdentity
    XCTAssertNotEqual(checkpoint.runtimeAssetIdentity, otherIdentity)
    store.checkpoint = checkpoint.replacingRuntimeAssetIdentity(
      otherIdentity
    )

    let restored = WholeShutoProductModel(
      database: model.database,
      checkpointStore: store
    )

    XCTAssertTrue(restored.restoredFromCheckpoint)
    XCTAssertEqual(restored.phase, .review)
    XCTAssertFalse(restored.isPlaying)
    XCTAssertNil(restored.runtimeOccurrenceID)
    XCTAssertEqual(
      restored.failureCode,
      "WHOLE_SHUTO_CHECKPOINT_RUNTIME_INVALID"
    )
  }

  func testCheckpointRoutePlanDriftDoesNotRestore() async throws {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: store)
    model.preparePreviewJourney()
    model.startNavigationSimulation()
    _ = await model.pausePlayback()

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
    XCTAssertEqual(
      restored.checkpointIssueCode,
      "WHOLE_SHUTO_CHECKPOINT_ROUTE_INVALID"
    )
    XCTAssertNil(store.checkpoint)
  }

  func testCheckpointLoadFailureIsVisibleAndInvalidated() {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: store)
    model.preparePreviewJourney()
    XCTAssertNotNil(store.checkpoint)

    store.loadError = .loadFailed
    let restored = WholeShutoProductModel(
      database: model.database,
      checkpointStore: store
    )

    XCTAssertEqual(restored.phase, .planning)
    XCTAssertNil(restored.selectedRoute)
    XCTAssertFalse(restored.restoredFromCheckpoint)
    XCTAssertEqual(
      restored.checkpointIssueCode,
      "WHOLE_SHUTO_CHECKPOINT_LOAD_FAILED"
    )
    XCTAssertNil(store.checkpoint)
    XCTAssertEqual(store.removeCount, 1)

    store.loadError = nil
    let nextLaunch = WholeShutoProductModel(
      database: model.database,
      checkpointStore: store
    )
    XCTAssertNil(nextLaunch.checkpointIssueCode)
    XCTAssertEqual(nextLaunch.phase, .planning)
  }

  func testCheckpointSchemaDriftIsVisibleAndRemoved() throws {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: store)
    model.preparePreviewJourney()
    store.checkpoint = try XCTUnwrap(store.checkpoint)
      .replacingSchemaVersion("1.0")

    let restored = WholeShutoProductModel(
      database: model.database,
      checkpointStore: store
    )

    XCTAssertEqual(restored.phase, .planning)
    XCTAssertNil(restored.selectedRoute)
    XCTAssertFalse(restored.restoredFromCheckpoint)
    XCTAssertEqual(
      restored.checkpointIssueCode,
      "WHOLE_SHUTO_CHECKPOINT_SCHEMA_UNSUPPORTED"
    )
    XCTAssertNil(store.checkpoint)
  }

  func testCheckpointSaveFailureInvalidatesTheOlderCheckpoint() async {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: store)
    model.preparePreviewJourney()
    XCTAssertNotNil(store.checkpoint)

    store.saveError = .saveFailed
    await model.handleScenePhase(.background)

    XCTAssertEqual(model.phase, .review)
    XCTAssertNotNil(model.selectedRoute)
    XCTAssertEqual(
      model.checkpointIssueCode,
      "WHOLE_SHUTO_CHECKPOINT_SAVE_FAILED"
    )
    XCTAssertNil(store.checkpoint)
    XCTAssertEqual(store.removeCount, 1)

    store.saveError = nil
    await model.handleScenePhase(.background)
    XCTAssertNil(model.checkpointIssueCode)
    XCTAssertNotNil(store.checkpoint)

    let restored = WholeShutoProductModel(
      database: model.database,
      checkpointStore: store
    )
    XCTAssertEqual(restored.phase, .review)
    XCTAssertTrue(restored.restoredFromCheckpoint)
    XCTAssertNil(restored.checkpointIssueCode)
  }

  func testCheckpointRemoveFailureIsVisibleAndRetryable() {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: store)
    model.preparePreviewJourney()
    XCTAssertNotNil(store.checkpoint)

    store.removeError = .removeFailed
    model.reset()

    XCTAssertEqual(model.phase, .planning)
    XCTAssertEqual(
      model.checkpointIssueCode,
      "WHOLE_SHUTO_CHECKPOINT_REMOVE_FAILED"
    )
    XCTAssertNotNil(store.checkpoint)

    store.removeError = nil
    model.reset()
    XCTAssertNil(model.checkpointIssueCode)
    XCTAssertNil(store.checkpoint)
  }

  func testExpresswayPreviewExplicitlyReportsTunnelEstimation() async {
    let model = WholeShutoProductModel(checkpointStore: nil)
    model.preparePreviewJourney()
    model.startNavigationSimulation()
    _ = await model.pausePlayback()

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
    _ = await model.pausePlayback()

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
    _ = await model.pausePlayback()

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

    let didReachJunction = await model.advanceSimulationToJunctionPreview()
    XCTAssertTrue(didReachJunction)

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

    await model.handleScenePhase(.background)

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

    let didReachJunction = await model.advanceSimulationToJunctionPreview()
    XCTAssertTrue(didReachJunction)

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

    let didReachJunction = await model.advanceSimulationToJunctionPreview()
    XCTAssertTrue(didReachJunction)

    let command = try XCTUnwrap(
      output.commands.last { $0.spokenText.contains("辰巳ジャンクション") }
    )
    XCTAssertEqual(command.languageCode, "ja-JP")
    // Each reviewed movement is spoken exactly once by the actor.
    XCTAssertEqual(
      output.commands.filter {
        $0.spokenText.contains("辰巳ジャンクション")
      }.count,
      1
    )
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

    let didReachJunction = await model.advanceSimulationToJunctionPreview()
    XCTAssertTrue(didReachJunction)

    let command = try XCTUnwrap(
      output.commands.last { $0.spokenText.contains("東雲ジャンクション") }
    )
    XCTAssertEqual(command.languageCode, "ja-JP")
    // Each reviewed movement is spoken exactly once by the actor.
    XCTAssertEqual(
      output.commands.filter {
        $0.spokenText.contains("東雲ジャンクション")
      }.count,
      1
    )
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

    let didReachJunction = await model.advanceSimulationToJunctionPreview()
    XCTAssertTrue(didReachJunction)

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

  private static func liveLocationEnvelope(
    id: String,
    coordinate: ShutoCoordinate,
    atMilliseconds: Int = 1_000,
    courseDegrees: Double = 90,
    speedMetersPerSecond: Double = 10
  ) -> CoreLocationObservationEnvelope {
    CoreLocationObservationEnvelope(
      observation: RouteMatcherObservation(
        id: id,
        observedAtMilliseconds: atMilliseconds,
        receivedAtMilliseconds: atMilliseconds,
        coordinate: MatcherCoordinate(
          latitude: coordinate.latitude,
          longitude: coordinate.longitude
        ),
        horizontalAccuracyMeters: 5,
        courseDegrees: courseDegrees,
        speedMetersPerSecond: speedMetersPerSecond,
        speedAccuracyMetersPerSecond: 1,
        source: .phone
      ),
      provenance: CoreLocationObservationProvenance(
        deliverySource: .deviceOrUndisclosed,
        sourceInformationAvailable: true,
        isSimulatedBySoftware: false,
        carPlayConnectionContext: .disconnected,
        matcherCalibrationCohort: .phone,
        courseAccuracyDegrees: 2,
        speedAccuracyMetersPerSecond: 1,
        observationAgeMilliseconds: 0
      )
    )
  }

  private static func bearing(
    from start: ShutoCoordinate,
    to end: ShutoCoordinate
  ) -> Double {
    let startLatitude = start.latitude * .pi / 180
    let endLatitude = end.latitude * .pi / 180
    let longitudeDelta = (end.longitude - start.longitude) * .pi / 180
    let y = sin(longitudeDelta) * cos(endLatitude)
    let x =
      cos(startLatitude) * sin(endLatitude)
      - sin(startLatitude) * cos(endLatitude) * cos(longitudeDelta)
    let degrees = atan2(y, x) * 180 / .pi
    return degrees >= 0 ? degrees : degrees + 360
  }

  private static func interpolate(
    from start: ShutoCoordinate,
    to end: ShutoCoordinate,
    fraction: Double
  ) -> ShutoCoordinate {
    ShutoCoordinate(
      latitude: start.latitude
        + (end.latitude - start.latitude) * fraction,
      longitude: start.longitude
        + (end.longitude - start.longitude) * fraction
    )
  }

  private static func savedRouteRecord(
    _ routePlan: RoutePlan,
    templateParameters: [String: String] = [:]
  ) -> SavedRouteRecord {
    SavedRouteRecord(
      id: "saved-route.test",
      displayName: "Test route",
      savedAt: "2026-08-11T12:00:00Z",
      origin: .authoredHere,
      document: SharedRouteDocument(
        evidenceState: .communityCandidate,
        templateParameters: templateParameters,
        routePlan: routePlan
      )
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
  var loadError: WholeShutoTestCheckpointStoreError?
  var saveError: WholeShutoTestCheckpointStoreError?
  var removeError: WholeShutoTestCheckpointStoreError?
  private(set) var loadCount = 0
  private(set) var saveCount = 0
  private(set) var removeCount = 0

  func load() throws -> WholeShutoJourneyCheckpoint? {
    loadCount += 1
    if let loadError { throw loadError }
    return checkpoint
  }

  func save(_ checkpoint: WholeShutoJourneyCheckpoint) throws {
    saveCount += 1
    if let saveError { throw saveError }
    self.checkpoint = checkpoint
  }

  func remove() throws {
    removeCount += 1
    if let removeError { throw removeError }
    checkpoint = nil
  }
}

private enum WholeShutoTestCheckpointStoreError: Error {
  case loadFailed
  case saveFailed
  case removeFailed
}

@MainActor
private final class WholeShutoMemorySavedRouteLibraryStore:
  SavedRouteLibraryStoring
{
  var library: SavedRouteLibraryDocument?

  func load() throws -> SavedRouteLibraryDocument? {
    library
  }

  func save(_ library: SavedRouteLibraryDocument) throws {
    self.library = library
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

private struct WholeShutoInstructionSurfaceRouteResolver:
  WholeShutoSurfaceRouteResolving
{
  func route(
    from origin: ShutoCoordinate,
    to destination: ShutoCoordinate
  ) async -> WholeShutoSurfaceRoute? {
    WholeShutoSurfaceRoute(
      coordinates: [origin, destination],
      distanceMeters: 1_200,
      expectedTravelTimeSeconds: 180,
      instructions: ["Continue on local road"],
      steps: [
        WholeShutoSurfaceRouteStep(
          instruction: "Continue on local road",
          distanceMeters: 1_200
        )
      ],
      guidanceLanguageCode: "en-US"
    )
  }
}

private struct WholeShutoMultiStepSurfaceRouteResolver:
  WholeShutoSurfaceRouteResolving
{
  func route(
    from origin: ShutoCoordinate,
    to destination: ShutoCoordinate
  ) async -> WholeShutoSurfaceRoute? {
    WholeShutoSurfaceRoute(
      coordinates: [origin, destination],
      distanceMeters: 1_200,
      expectedTravelTimeSeconds: 180,
      instructions: ["Continue straight", "Turn left"],
      steps: [
        WholeShutoSurfaceRouteStep(
          instruction: "Continue straight",
          distanceMeters: 700
        ),
        WholeShutoSurfaceRouteStep(
          instruction: "Turn left",
          distanceMeters: 500
        ),
      ],
      guidanceLanguageCode: "en-US"
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

@MainActor
private final class WholeShutoBackgroundNavigationLocationSource:
  ForegroundNavigationLocationSource
{
  weak var delegate: (any ForegroundNavigationLocationSourceDelegate)?
  private(set) var authorizationStatus: CLAuthorizationStatus
  let accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
  let supportsBackgroundNavigation = true
  private(set) var authorizationRequestCount = 0
  private(set) var startCount = 0
  private(set) var stopCount = 0
  private(set) var backgroundNavigationEnabled = false

  init(
    authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
  ) {
    self.authorizationStatus = authorizationStatus
  }

  func requestWhenInUseAuthorization() {
    authorizationRequestCount += 1
  }

  func setBackgroundNavigationEnabled(_ enabled: Bool) {
    backgroundNavigationEnabled = enabled
  }

  func startUpdatingLocation() {
    startCount += 1
  }

  func stopUpdatingLocation() {
    stopCount += 1
  }

  func deliverAuthorization(_ status: CLAuthorizationStatus) {
    authorizationStatus = status
    delegate?.foregroundNavigationLocationSourceDidChangeAuthorization(self)
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
  fileprivate func replacingSchemaVersion(_ schemaVersion: String) -> Self {
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
      driveMode: driveMode,
      phase: phase,
      progressFraction: progressFraction,
      runtimeOccurrenceID: runtimeOccurrenceID,
      runtimeFractionAlongOccurrence: runtimeFractionAlongOccurrence,
      consumedGuidancePromptIDs: consumedGuidancePromptIDs,
      mapMode: mapMode,
      accessRoute: accessRoute,
      egressRoute: egressRoute,
      circuitID: circuitID,
      circuitLaps: circuitLaps,
      runtimeAssetIdentity: runtimeAssetIdentity,
      liveNavigationCheckpoint: liveNavigationCheckpoint
    )
  }

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
      driveMode: driveMode,
      phase: phase,
      progressFraction: progressFraction,
      runtimeOccurrenceID: runtimeOccurrenceID,
      runtimeFractionAlongOccurrence: runtimeFractionAlongOccurrence,
      consumedGuidancePromptIDs: consumedGuidancePromptIDs,
      mapMode: mapMode,
      accessRoute: accessRoute,
      egressRoute: egressRoute,
      circuitID: circuitID,
      circuitLaps: circuitLaps,
      runtimeAssetIdentity: runtimeAssetIdentity,
      liveNavigationCheckpoint: liveNavigationCheckpoint
    )
  }

  fileprivate func replacingDriveMode(
    _ driveMode: WholeShutoDriveMode,
    progressFraction: Double
  ) -> Self {
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
      driveMode: driveMode,
      phase: phase,
      progressFraction: progressFraction,
      runtimeOccurrenceID: runtimeOccurrenceID,
      runtimeFractionAlongOccurrence: runtimeFractionAlongOccurrence,
      consumedGuidancePromptIDs: consumedGuidancePromptIDs,
      mapMode: mapMode,
      accessRoute: accessRoute,
      egressRoute: egressRoute,
      circuitID: circuitID,
      circuitLaps: circuitLaps,
      runtimeAssetIdentity: runtimeAssetIdentity,
      liveNavigationCheckpoint: liveNavigationCheckpoint
    )
  }

  fileprivate func replacingRuntimeAssetIdentity(
    _ runtimeAssetIdentity: ShutoRuntimeAssetIdentity?
  ) -> Self {
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
      driveMode: driveMode,
      phase: phase,
      progressFraction: progressFraction,
      runtimeOccurrenceID: runtimeOccurrenceID,
      runtimeFractionAlongOccurrence: runtimeFractionAlongOccurrence,
      consumedGuidancePromptIDs: consumedGuidancePromptIDs,
      mapMode: mapMode,
      accessRoute: accessRoute,
      egressRoute: egressRoute,
      circuitID: circuitID,
      circuitLaps: circuitLaps,
      runtimeAssetIdentity: runtimeAssetIdentity,
      liveNavigationCheckpoint: liveNavigationCheckpoint
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
    eventHandler?(.didFinish(command.identity))
  }

  func stop() {}
}
