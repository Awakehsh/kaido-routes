import KaidoDomain
import KaidoNavigation
import KaidoRouting
import XCTest

@testable import KaidoRoutesApp

@MainActor
final class WholeShutoParkingDestinationTests: XCTestCase {
  private func waitForJourney(_ model: WholeShutoProductModel) async throws {
    for _ in 0..<3_000 where model.isResolvingCircuitPairing || model.isUpdatingSurfaceRoute || model.isPreparingLiveNavigation || model.isPlanning {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertFalse(model.isResolvingCircuitPairing)
    XCTAssertFalse(model.isUpdatingSurfaceRoute)
    XCTAssertFalse(model.isPreparingLiveNavigation)
    XCTAssertFalse(model.isPlanning)
  }

  private func model(_ circuit: ShutoCircuitDefinition = .wanganDaikokuRun) async throws -> WholeShutoProductModel {
    let model = WholeShutoForegroundReleaseFactory.makeModel(surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(), checkpointStore: nil)
    let id = circuit == .scenicGrandTour ? "shuto.ic.10.harumi" : circuit.kind == .loop ? "shuto.ic.b.wangankanpachi" : "shuto.ic.b.chidoricho"
    let entrance = try XCTUnwrap(model.database.directionalFacilities.first { $0.facilityID == id })
    model.selectCurrentOrigin(entrance.coordinate)
    model.selectCircuit(circuit)
    try await waitForJourney(model)
    XCTAssertNil(model.circuitExitFacilityID)
    XCTAssertTrue(model.startCircuitJourney())
    try await waitForJourney(model)
    return model
  }

  func testDaikokuRecommendationsHavePADestinationAndNoExit() async throws {
    for circuit in [ShutoCircuitDefinition.wanganDaikokuRun, .daikokuYokohamaLoop, .scenicGrandTour] {
      let model = try await model(circuit)
      XCTAssertEqual(model.destination?.parkingAreaID, "shuto.pa.daikoku")
      XCTAssertEqual(model.selectedRoute?.routePlan.destinationParkingAreaID, "shuto.pa.daikoku")
      XCTAssertNil(model.selectedRoute?.exitFacility)
      XCTAssertNil(model.egressRoute)
      XCTAssertNil(model.selectedTariffBand)
      XCTAssertTrue(model.canStartLiveNavigation, model.liveNavigationBlockerCode ?? "")
    }
  }

  func testReplayCompletesInsidePAWithoutExitPhase() async throws {
    let model = try await model()
    model.startNavigationSimulation(autoplay: false)
    var sawExit = false
    for _ in 0..<20_000 where model.phase != .completed && model.failureCode == nil {
      await model.advanceSimulationForTesting()
      sawExit = sawExit || model.phase == .exitTransition || model.phase == .surfaceEgress
    }
    XCTAssertNil(model.failureCode)
    XCTAssertEqual(model.phase, .completed)
    XCTAssertFalse(sawExit)
    XCTAssertEqual(model.currentCoordinate, model.selectedRoute?.coordinates.last)
  }

  func testDestinationSearchKeepsPAIdentity() async throws {
    let model = WholeShutoForegroundReleaseFactory.makeModel(surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(), checkpointStore: nil)
    let search = WholeShutoPlaceSearchController(localPlaces: WholeShutoProductView.localSearchPlaces(in: model.database), usesMapKit: false)
    search.update(query: "大黑", near: nil)
    let suggestion = try XCTUnwrap(search.suggestions.first)
    let place = try await search.resolve(suggestion)
    XCTAssertEqual(place.parkingAreaID, "shuto.pa.daikoku")
    model.selectCurrentOrigin(try XCTUnwrap(model.database.directionalFacilities.first { $0.facilityID == "shuto.ic.10.harumi" }).coordinate)
    model.selectDestinationPreview(place)
    model.planJourney()
    try await waitForJourney(model)
    XCTAssertEqual(model.selectedRoute?.routePlan.destinationParkingAreaID, place.parkingAreaID)
    XCTAssertNil(model.selectedRoute?.exitFacility)
    XCTAssertNil(model.egressRoute)
    XCTAssertTrue(model.canStartLiveNavigation, model.liveNavigationBlockerCode ?? "")
  }

  func testSelectedPAAndSavedRouteRemainTerminalDestinations() async throws {
    let model = try await model()
    model.prepareCustomRouteDraft()
    // An explicit entrance/exit route can change its destination to a PA.
    model.selectCustomExit(facilityID: "shuto.ic.b.daikokufutou")
    XCTAssertTrue(model.applyCustomRoute())
    try await waitForJourney(model)
    try await model.selectJourneyParkingDestination("shuto.pa.oi-westbound")
    try await waitForJourney(model)
    let route = try XCTUnwrap(model.selectedRoute)
    XCTAssertEqual(route.destinationParkingArea?.parkingAreaID, "shuto.pa.oi-westbound")
    XCTAssertNil(route.exitFacility)
    let record = SavedRouteRecord(id: "pa-destination", displayName: "PA destination", savedAt: "2026-09-09T00:00:00Z", origin: .authoredHere, document: SharedRouteDocument(evidenceState: .communityCandidate, templateParameters: model.savedRouteTemplateParameters, routePlan: route.routePlan))
    let restored = WholeShutoForegroundReleaseFactory.makeModel(surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(), checkpointStore: nil)
    XCTAssertTrue(restored.openSavedRoute(record, origin: route.entryFacility.coordinate))
    try await waitForJourney(restored)
    XCTAssertEqual(restored.selectedRoute, route)
    XCTAssertEqual(restored.destination?.parkingAreaID, "shuto.pa.oi-westbound")
    XCTAssertNil(restored.egressRoute)
    XCTAssertTrue(restored.canStartLiveNavigation, restored.liveNavigationBlockerCode ?? "")
  }
}
