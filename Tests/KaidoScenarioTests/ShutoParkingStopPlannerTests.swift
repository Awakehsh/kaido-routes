import Foundation
import KaidoDomain
import KaidoNavigation
import KaidoRouting
import Testing

@Suite("Selected PA stops")
struct ShutoParkingStopPlannerTests {
  private func loadDatabase() throws -> ShutoNetworkDatabase {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let database = try JSONDecoder().decode(ShutoNetworkDatabase.self, from: Data(contentsOf: root.appendingPathComponent("data/route-atlas/osm-derived/shuto-whole-network-20260804.json")))
    return database
  }

  private func planner() throws -> ShutoRoutePlanner { try ShutoRoutePlanner(database: loadDatabase()) }

  @Test("a selected PA preserves the route around its directional access and return")
  func addsDirectionalStop() throws {
    let planner = try planner()
    let base = try planner.plan(entryFacilityID: "shuto.ic.b.chidoricho", exitFacilityID: "shuto.ic.b.daikokufutou")
    let options = planner.parkingStopOptions(for: base)
    let oi = try #require(options.first { $0.id == "shuto.pa.oi-westbound" })
    #expect(!options.contains { $0.id == "shuto.pa.oi-eastbound" })
    let route = try planner.addingParkingStops([oi.id], to: base)
    #expect(route.edges.prefix(oi.departureIndex) == base.edges.prefix(oi.departureIndex))
    #expect(route.edges.suffix(base.edges.count - oi.returnIndex) == base.edges.suffix(base.edges.count - oi.returnIndex))
    #expect(route.routePlan.occurrences.filter { $0.parkingAreaID == oi.id }.count == oi.parkingArea.interiorEdgeIDs?.count)
    #expect(route.entryFacility == base.entryFacility)
    #expect(route.exitFacility == base.exitFacility)
    #expect(try planner.restore(routePlan: route.routePlan).describesSameRoad(as: route))
    let database = try loadDatabase()
    let artifact = try ShutoCircuitProductReleaseBuilder.buildPlannedRouteArtifact(database: database, route: route)
    #expect(try KaidoProductRelease(artifact: artifact).foregroundLiveInputAuthority != nil)
    #expect(try planner.addingParkingStops([], to: base) == base)
    #expect(throws: ShutoNetworkError.facilityUnavailable) {
      _ = try planner.addingParkingStops(["shuto.pa.oi-eastbound"], to: base)
    }
  }

  @Test("multiple stops follow route order and keep the tariff pairing")
  func multipleStopsFollowRouteOrder() throws {
    let planner = try planner()
    let base = try planner.plan(entryFacilityID: "shuto.ic.b.chidoricho", exitFacilityID: "shuto.ic.b.daikokufutou")
    let ids = ["shuto.pa.daikoku", "shuto.pa.oi-westbound"]
    let route = try planner.addingParkingStops(ids, to: base)
    #expect(try planner.addingParkingStops(ids.reversed(), to: base) == route)
    let visits = route.routePlan.occurrences.compactMap(\.parkingAreaID)
    #expect(visits.first == "shuto.pa.oi-westbound")
    #expect(visits.last == "shuto.pa.daikoku")
    #expect(try planner.tariffBand(entryFacilityID: route.entryFacility.facilityID, exitFacilityID: route.exitFacility!.facilityID, evidence: .etcNormalCarUntil2026September) == planner.tariffBand(entryFacilityID: base.entryFacility.facilityID, exitFacilityID: base.exitFacility!.facilityID, evidence: .etcNormalCarUntil2026September))
    #expect(!planner.parkingStopOptions(for: base).contains { ["shuto.pa.yoga", "shuto.pa.ichikawa"].contains($0.id) })
  }

  @Test("a selected stop occurs once without changing loop count")
  func addsStopOnFirstLapOnly() throws {
    let planner = try planner()
    let base = try planner.planCircuit(circuit: .daikokuYokohamaLoop, entryFacilityID: "shuto.ic.b.wangankanpachi", exitFacilityID: "shuto.ic.b.daikokufutou", laps: 2)
    let options = planner.parkingStopOptions(for: base)
    let stop = try #require(options.first { $0.id == "shuto.pa.daikoku" })
    let route = try planner.addingParkingStops([stop.id], to: base)
    #expect(route.lapBoundaryOccurrenceIndices.count == 3)
    #expect(route.routePlan.occurrences.filter { $0.parkingAreaID == stop.id }.count == stop.parkingArea.interiorEdgeIDs?.count)
    #expect(route.edges[route.lapBoundaryOccurrenceIndices[1]..<route.lapBoundaryOccurrenceIndices[2]] == base.edges[base.lapBoundaryOccurrenceIndices[1]..<base.lapBoundaryOccurrenceIndices[2]])
  }
}
