import Foundation
import KaidoRouting
import Testing

@Suite("Scratch debug")
struct ScratchDebugTests {
  @Test("debug start route from tokyo tower")
  func debugStart() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let url = repositoryRoot
      .appendingPathComponent("data")
      .appendingPathComponent("route-atlas")
      .appendingPathComponent("osm-derived")
      .appendingPathComponent("shuto-whole-network-20260803.json")
    let database = try JSONDecoder().decode(
      ShutoNetworkDatabase.self,
      from: Data(contentsOf: url)
    )
    let planner = try ShutoRoutePlanner(database: database)
    let origin = ShutoCoordinate(latitude: 35.6586, longitude: 139.7454)
    for circuit in ShutoCircuitDefinition.bundled {
      do {
        let pairing = try planner.recommendedCircuitPairing(
          for: circuit,
          origin: origin,
          evidence: .etcNormalCarActive
        )
        do {
          let route = try planner.planCircuit(
            circuit: circuit,
            entryFacilityID: pairing.entrance.facilityID,
            exitFacilityID: pairing.exit.facilityID,
            laps: 1
          )
          print(
            "SCRATCH", circuit.circuitID,
            pairing.entrance.facilityID, "→",
            pairing.exit.facilityID,
            "plan \(Int(route.distanceMeters))m OK"
          )
        } catch {
          print(
            "SCRATCH", circuit.circuitID,
            pairing.entrance.facilityID, "→",
            pairing.exit.facilityID,
            "PLAN FAILED:", error
          )
        }
      } catch {
        print("SCRATCH", circuit.circuitID, "PAIRING FAILED:", error)
      }
    }
  }
}
