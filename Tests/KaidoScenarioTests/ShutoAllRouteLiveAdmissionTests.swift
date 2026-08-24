import Foundation
import KaidoNavigation
import KaidoRouting
import Testing

@Suite("Whole-Shuto all-route live admission")
struct ShutoAllRouteLiveAdmissionTests {
  private struct EntryAudit: Sendable {
    let plannedRouteCount: Int
    let releasedRouteCount: Int
    let failures: [String]
  }

  private struct CircuitAudit: Sendable {
    let plannedRouteCount: Int
    let releasedRouteCount: Int
    let failures: [String]
  }

  @Test(
    "every plannable directional facility pair builds live authority",
    .enabled(
      if: ProcessInfo.processInfo.environment[
        "KAIDO_RUN_EXHAUSTIVE_ROUTE_ADMISSION"
      ] == "1",
      "Set KAIDO_RUN_EXHAUSTIVE_ROUTE_ADMISSION=1 to run the exhaustive audit"
    )
  )
  func everyPlannableFacilityPairBuildsLiveAuthority() async throws {
    let database = try loadWholeShutoDatabase()
    let runtimeContext = try ShutoPlannedRouteRuntimeCompiler.NetworkContext(
      database: database
    )
    let entries = database.directionalFacilities
      .filter(\.canEnter)
      .sorted { $0.facilityID < $1.facilityID }
    let exits = database.directionalFacilities
      .filter(\.canExit)
      .sorted { $0.facilityID < $1.facilityID }

    let audits = await withTaskGroup(
      of: EntryAudit.self,
      returning: [EntryAudit].self
    ) { group in
      for entry in entries {
        group.addTask {
          let planner = try! ShutoRoutePlanner(database: database)
          var plannedRouteCount = 0
          var releasedRouteCount = 0
          var failures: [String] = []

          for exit in exits where exit.facilityID != entry.facilityID {
            for preference in ShutoRoutePreference.allCases {
              do {
                let route = try planner.plan(
                  entryFacilityID: entry.facilityID,
                  exitFacilityID: exit.facilityID,
                  preference: preference
                )
                plannedRouteCount += 1
                let release =
                  try ShutoCircuitProductReleaseBuilder
                  .buildPlannedRouteRelease(
                    context: runtimeContext,
                    route: route
                  )
                guard release.foregroundLiveInputAuthority != nil else {
                  failures.append(
                    "\(entry.facilityID)->\(exit.facilityID)"
                      + "[\(preference.rawValue)]: missing foreground authority"
                  )
                  continue
                }
                releasedRouteCount += 1
              } catch ShutoNetworkError.routeUnavailable {
                continue
              } catch {
                failures.append(
                  "\(entry.facilityID)->\(exit.facilityID)"
                    + "[\(preference.rawValue)]: \(error)"
                )
              }
            }
          }
          return EntryAudit(
            plannedRouteCount: plannedRouteCount,
            releasedRouteCount: releasedRouteCount,
            failures: failures
          )
        }
      }

      var results: [EntryAudit] = []
      for await audit in group {
        results.append(audit)
      }
      return results
    }

    let plannedRouteCount = audits.reduce(0) {
      $0 + $1.plannedRouteCount
    }
    let releasedRouteCount = audits.reduce(0) {
      $0 + $1.releasedRouteCount
    }
    let failures = audits.flatMap(\.failures).sorted()

    print(
      "Whole-Shuto live admission audit: planned=\(plannedRouteCount) "
        + "released=\(releasedRouteCount) failures=\(failures.count)"
    )

    #expect(plannedRouteCount > 0)
    #expect(
      failures.isEmpty,
      Comment(rawValue: failures.prefix(100).joined(separator: "\n"))
    )
    #expect(releasedRouteCount == plannedRouteCount)
  }

  @Test(
    "every default circuit pairing and lap count builds live authority",
    .enabled(
      if: ProcessInfo.processInfo.environment[
        "KAIDO_RUN_EXHAUSTIVE_ROUTE_ADMISSION"
      ] == "1",
      "Set KAIDO_RUN_EXHAUSTIVE_ROUTE_ADMISSION=1 to run the exhaustive audit"
    )
  )
  func everyDefaultCircuitBuildsLiveAuthority() async throws {
    let database = try loadWholeShutoDatabase()
    let runtimeContext = try ShutoPlannedRouteRuntimeCompiler.NetworkContext(
      database: database
    )
    let audits = await withTaskGroup(
      of: CircuitAudit.self,
      returning: [CircuitAudit].self
    ) { group in
      for circuit in ShutoCircuitDefinition.bundled {
        group.addTask {
          let planner = try! ShutoRoutePlanner(database: database)
          var plannedRouteCount = 0
          var releasedRouteCount = 0
          var failures: [String] = []
          let entries = planner.circuitEntranceCandidates(
            for: circuit,
            origin: nil
          ).prefix(3)

          for entry in entries {
            let pairing: ShutoCircuitPairing
            do {
              pairing = try planner.recommendedCircuitPairing(
                for: circuit,
                entranceFacilityID: entry.facilityID,
                evidence: .etcNormalCarActive
              )
            } catch ShutoNetworkError.facilityUnavailable {
              continue
            } catch ShutoNetworkError.routeUnavailable {
              continue
            } catch {
              failures.append(
                "\(circuit.circuitID)[\(entry.facilityID)]: \(error)"
              )
              continue
            }

            let lapCounts =
              circuit.kind == .loop
              ? Array(ShutoCircuitDefinition.loopLapRange) : [1]
            for laps in lapCounts {
              do {
                let route = try planner.planCircuit(
                  circuit: circuit,
                  entryFacilityID: pairing.entrance.facilityID,
                  exitFacilityID: pairing.exit.facilityID,
                  laps: laps
                )
                plannedRouteCount += 1
                let release =
                  try ShutoCircuitProductReleaseBuilder
                  .buildPlannedRouteRelease(
                    context: runtimeContext,
                    route: route
                  )
                guard release.foregroundLiveInputAuthority != nil else {
                  failures.append(
                    "\(circuit.circuitID)[\(entry.facilityID),\(laps)]: "
                      + "missing foreground authority"
                  )
                  continue
                }
                releasedRouteCount += 1
              } catch {
                failures.append(
                  "\(circuit.circuitID)[\(entry.facilityID),\(laps)]: \(error)"
                )
              }
            }
          }
          return CircuitAudit(
            plannedRouteCount: plannedRouteCount,
            releasedRouteCount: releasedRouteCount,
            failures: failures
          )
        }
      }

      var results: [CircuitAudit] = []
      for await audit in group {
        results.append(audit)
      }
      return results
    }

    let plannedRouteCount = audits.reduce(0) {
      $0 + $1.plannedRouteCount
    }
    let releasedRouteCount = audits.reduce(0) {
      $0 + $1.releasedRouteCount
    }
    let failures = audits.flatMap(\.failures).sorted()

    print(
      "Whole-Shuto circuit live admission audit: planned=\(plannedRouteCount) "
        + "released=\(releasedRouteCount) failures=\(failures.count)"
    )
    #expect(plannedRouteCount > 0)
    #expect(
      failures.isEmpty,
      Comment(rawValue: failures.prefix(100).joined(separator: "\n"))
    )
    #expect(releasedRouteCount == plannedRouteCount)
  }

  private func loadWholeShutoDatabase() throws -> ShutoNetworkDatabase {
    let databaseURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("data")
      .appendingPathComponent("route-atlas")
      .appendingPathComponent("osm-derived")
      .appendingPathComponent("shuto-whole-network-20260804.json")
    return try JSONDecoder().decode(
      ShutoNetworkDatabase.self,
      from: Data(contentsOf: databaseURL)
    )
  }
}
