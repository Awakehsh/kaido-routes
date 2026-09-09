import KaidoDomain
import KaidoRouting
import XCTest

@testable import KaidoRoutesApp

@MainActor
final class WholeShutoParkingStopTests: XCTestCase {
  private func waitForJourney(_ model: WholeShutoProductModel) async throws {
    for _ in 0..<2_000 where model.isResolvingCircuitPairing || model.isUpdatingSurfaceRoute || model.isPreparingLiveNavigation {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertFalse(model.isResolvingCircuitPairing)
    XCTAssertFalse(model.isUpdatingSurfaceRoute)
    XCTAssertFalse(model.isPreparingLiveNavigation)
  }

  private func model(circuit: ShutoCircuitDefinition = .wanganDaikokuRun, store: (any WholeShutoJourneyCheckpointStoring)? = nil) async throws -> WholeShutoProductModel {
    let model = WholeShutoForegroundReleaseFactory.makeModel(surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(), checkpointStore: store)
    let entranceID = circuit.kind == .loop ? "shuto.ic.b.wangankanpachi" : "shuto.ic.b.chidoricho"
    let entrance = try XCTUnwrap(model.database.directionalFacilities.first { $0.facilityID == entranceID })
    model.selectCurrentOrigin(entrance.coordinate)
    model.selectCircuit(circuit)
    try await waitForJourney(model)
    XCTAssertTrue(model.startCircuitJourney())
    try await waitForJourney(model)
    return model
  }

  func testAddAndRemoveStopRetainsIncludedPAAndNavigation() async throws {
    let model = try await model()
    let base = try XCTUnwrap(model.selectedRoute)
    let tariff = model.circuitPairingBand
    let options = try await model.journeyParkingStopOptions()
    XCTAssertTrue(options.contains { $0.id == "shuto.pa.oi-westbound" })
    XCTAssertFalse(options.contains { $0.id == "shuto.pa.oi-eastbound" })
    XCTAssertEqual(model.includedParkingStops.map(\.parkingAreaID), ["shuto.pa.daikoku"])
    try await model.selectJourneyParkingStops(["shuto.pa.oi-westbound"])
    try await waitForJourney(model)
    XCTAssertTrue(model.canStartLiveNavigation, model.liveNavigationBlockerCode ?? "")
    XCTAssertEqual(model.selectedRoute?.entryFacility, base.entryFacility)
    XCTAssertEqual(model.selectedRoute?.exitFacility, base.exitFacility)
    XCTAssertEqual(model.circuitPairingBand, tariff)
    XCTAssertTrue(model.selectedRoute?.routePlan.occurrences.contains { $0.parkingAreaID == "shuto.pa.oi-westbound" } == true)
    try await model.selectJourneyParkingStops([])
    try await waitForJourney(model)
    XCTAssertEqual(model.selectedRoute, base)
    XCTAssertNil(model.parkingStopSelection)
    XCTAssertTrue(model.canStartLiveNavigation)
  }

  func testSavedCircuitRetainsEditableStopAndRejectsMetadataDrift() async throws {
    let model = try await model(circuit: .daikokuYokohamaLoop)
    let base = try XCTUnwrap(model.selectedRoute)
    try await model.selectJourneyParkingStops(["shuto.pa.daikoku"])
    try await waitForJourney(model)
    let route = try XCTUnwrap(model.selectedRoute)
    let parameters = model.savedRouteTemplateParameters
    let record = SavedRouteRecord(id: "pa-test", displayName: "PA stop", savedAt: "2026-09-09T00:00:00Z", origin: .authoredHere, document: SharedRouteDocument(evidenceState: .communityCandidate, templateParameters: parameters, routePlan: route.routePlan))
    let reopened = WholeShutoForegroundReleaseFactory.makeModel(surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(), checkpointStore: nil)
    XCTAssertTrue(reopened.openSavedRoute(record, origin: base.entryFacility.coordinate))
    try await waitForJourney(reopened)
    XCTAssertEqual(reopened.selectedRoute, route)
    XCTAssertTrue(reopened.canStartLiveNavigation, reopened.liveNavigationBlockerCode ?? "")
    try await reopened.selectJourneyParkingStops([])
    XCTAssertEqual(reopened.selectedRoute, base)
    let invalid = SavedRouteRecord(id: "invalid", displayName: "Invalid", savedAt: record.savedAt, origin: .authoredHere, document: SharedRouteDocument(evidenceState: .communityCandidate, templateParameters: parameters, routePlan: base.routePlan))
    XCTAssertFalse(reopened.openSavedRoute(invalid, origin: base.entryFacility.coordinate))
  }

  func testCheckpointRetainsStopAndDrivingCannotEditIt() async throws {
    let store = ParkingStopCheckpointStore()
    let model = try await model(store: store)
    try await model.selectJourneyParkingStops(["shuto.pa.oi-westbound"])
    try await waitForJourney(model)
    let route = try XCTUnwrap(model.selectedRoute)
    model.startNavigationSimulation(autoplay: false)
    XCTAssertNotEqual(model.phase, .review)
    do {
      try await model.selectJourneyParkingStops([])
      XCTFail("Driving must not edit PA stops")
    } catch {}
    XCTAssertEqual(model.selectedRoute, route)
    XCTAssertNotNil(store.checkpoint?.parkingStops)
    let restored = WholeShutoForegroundReleaseFactory.makeModel(surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(), checkpointStore: store)
    XCTAssertEqual(restored.selectedRoute, route)
    XCTAssertEqual(restored.parkingStopSelection?.parkingAreaIDs, ["shuto.pa.oi-westbound"])
  }

  func testCustomRouteExitChangeAndSavedRouteRetainStops() async throws {
    let model = try await model()
    model.prepareCustomRouteDraft()
    XCTAssertTrue(model.applyCustomRoute())
    try await waitForJourney(model)
    try await model.selectJourneyParkingStops(["shuto.pa.oi-westbound"])
    try await waitForJourney(model)
    try await model.selectJourneyExit("shuto.ic.b.higashiogishima")
    try await waitForJourney(model)
    let route = try XCTUnwrap(model.selectedRoute)
    XCTAssertEqual(route.exitFacility.facilityID, "shuto.ic.b.higashiogishima")
    XCTAssertTrue(route.routePlan.occurrences.contains { $0.parkingAreaID == "shuto.pa.oi-westbound" })
    let record = SavedRouteRecord(id: "custom-pa", displayName: "Custom PA", savedAt: "2026-09-09T00:00:00Z", origin: .authoredHere, document: SharedRouteDocument(evidenceState: .communityCandidate, templateParameters: model.savedRouteTemplateParameters, routePlan: route.routePlan))
    let reopened = WholeShutoForegroundReleaseFactory.makeModel(surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(), checkpointStore: nil)
    XCTAssertTrue(reopened.openSavedRoute(record, origin: route.entryFacility.coordinate))
    XCTAssertEqual(reopened.selectedRoute, route)
    try await reopened.selectJourneyParkingStops([])
    XCTAssertFalse(reopened.selectedRoute?.routePlan.occurrences.contains { $0.parkingAreaID == "shuto.pa.oi-westbound" } == true)
  }

  func testInvalidStopLeavesSelectedRouteUntouched() async throws {
    let model = try await model()
    let previous = model.selectedRoute
    do {
      try await model.selectJourneyParkingStops(["shuto.pa.ichikawa"])
      XCTFail("Unsupported stop must be rejected")
    } catch {}
    XCTAssertEqual(model.selectedRoute, previous)
    XCTAssertFalse(model.isUpdatingParkingStops)
    XCTAssertNil(model.parkingStopSelection)
  }
}

@MainActor
private final class ParkingStopCheckpointStore: WholeShutoJourneyCheckpointStoring {
  var checkpoint: WholeShutoJourneyCheckpoint?
  func load() throws -> WholeShutoJourneyCheckpoint? { checkpoint }
  func save(_ checkpoint: WholeShutoJourneyCheckpoint) throws { self.checkpoint = checkpoint }
  func remove() throws { checkpoint = nil }
}
