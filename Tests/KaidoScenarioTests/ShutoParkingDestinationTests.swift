import Foundation
import KaidoDomain
import KaidoNavigation
import KaidoRouting
import Testing

@Suite("PA destinations")
struct ShutoParkingDestinationTests {
  private func database() throws -> ShutoNetworkDatabase {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try JSONDecoder().decode(ShutoNetworkDatabase.self, from: Data(contentsOf: root.appendingPathComponent("data/route-atlas/osm-derived/shuto-whole-network-20260804.json")))
  }

  @Test("Daikoku recommendations end inside the PA without an exit", arguments: ["wangan", "loop", "scenic"])
  func recommendedDestination(_ name: String) throws {
    let database = try database()
    let route: ShutoPlannedRoute
    switch name {
    case "wangan": route = try ShutoCircuitProductReleaseBuilder.plannedWanganRoute(database: database)
    case "loop": route = try ShutoCircuitProductReleaseBuilder.plannedDaikokuRoute(database: database)
    default: route = try ShutoCircuitProductReleaseBuilder.plannedScenicRoute(database: database)
    }
    #expect(route.exitFacility == nil)
    #expect(route.routePlan.exitFacilityID == nil)
    #expect(route.routePlan.destinationParkingAreaID == "shuto.pa.daikoku")
    #expect(route.routePlan.occurrences.last?.kind == .paVisit)
    let parking = try #require(route.destinationParkingArea)
    #expect(route.edges.last?.kind == "PARKING")
    #expect(route.edges.last?.toNodeID != parking.returnNodeID)
    let release = try ShutoCircuitProductReleaseBuilder.buildPlannedRouteArtifact(database: database, route: route)
    let product = try KaidoProductRelease(artifact: release)
    #expect(product.navigation.bundle.runtimePolicy.egressOptions.isEmpty)
    let journey = JourneyPlanCompiler.expresswayOnly(release: product)
    #expect(journey.finishPolicy == .parkingArea)
    _ = try KaidoLiveJourneyAdmission(release: product, selectedRoutePlan: route.routePlan, journeyPlan: journey).makeRuntime()
  }

  @Test("PA identity survives saving and does not create an exit")
  func restoresParkingDestination() throws {
    let planner = try ShutoRoutePlanner(database: database())
    let route = try planner.plan(entryFacilityID: "shuto.ic.10.harumi", destinationParkingAreaID: "shuto.pa.oi-westbound")
    let encoded = try JSONEncoder().encode(route.routePlan)
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(object["exit_facility_id"] == nil)
    #expect(object["destination_parking_area_id"] as? String == "shuto.pa.oi-westbound")
    let plan = try JSONDecoder().decode(RoutePlan.self, from: encoded)
    #expect(try planner.restore(routePlan: plan).describesSameRoad(as: route))
  }

  @Test("only the final PA visit completes the journey")
  func arrivalRespectsEarlierVisitsAndRemainingLaps() {
    let plan = RoutePlan(id: "test.pa-arrival", networkSnapshotID: "test.snapshot", entryFacilityID: "test.entry", destinationParkingAreaID: "test.pa", recoveryPolicy: .strict, occurrences: [
      .init(id: "road", index: 0, kind: .edge, entityID: "road"),
      .init(id: "earlier-pa", index: 1, kind: .paVisit, entityID: "parking", parkingAreaID: "test.pa"),
      .init(id: "later-road", index: 2, kind: .edge, entityID: "road"),
      .init(id: "final-pa", index: 3, kind: .paVisit, entityID: "parking", parkingAreaID: "test.pa"),
      .init(id: "parking-bay", index: 4, kind: .paVisit, entityID: "parking-bay", parkingAreaID: "test.pa"),
    ])
    var engine = NavigationEngine(configuration: .init(routePlan: plan), initialSnapshot: .init(journeyPhase: .strictRoute, currentOccurrenceID: "road"))
    engine.observeLocation(.init(matchedOccurrenceID: "earlier-pa", candidateResolution: .resolved, reportedConfidence: .high))
    #expect(engine.snapshot.journeyPhase == .strictRoute)
    engine.observeLocation(.init(matchedOccurrenceID: "final-pa", candidateResolution: .resolved, reportedConfidence: .high))
    #expect(engine.snapshot.journeyPhase == .completed)
    #expect(engine.snapshot.skippedOccurrenceIDs == ["parking-bay"])
    #expect(!engine.snapshot.completedOccurrenceIDs.contains("parking-bay"))
    #expect(engine.snapshot.egress.exitFacilityID == nil)
  }

  @Test("the requested laps finish before the PA destination")
  func completesLapsBeforeArrival() throws {
    let planner = try ShutoRoutePlanner(database: database())
    let route = try planner.planCircuit(circuit: .daikokuYokohamaLoop, entryFacilityID: "shuto.ic.b.wangankanpachi", laps: 2)
    #expect(route.lapBoundaryOccurrenceIndices.count == 3)
    let firstPA = try #require(route.routePlan.occurrences.first { $0.kind == .paVisit })
    #expect(firstPA.index >= route.lapBoundaryOccurrenceIndices[2])
    #expect(route.routePlan.occurrences.last?.parkingAreaID == "shuto.pa.daikoku")
  }
}
