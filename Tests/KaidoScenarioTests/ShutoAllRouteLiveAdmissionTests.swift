import Foundation
import KaidoNavigation
import KaidoRouting
import Testing

@Suite("Whole-Shuto all-route live admission")
struct ShutoAllRouteLiveAdmissionTests {
  private struct EntryAudit: Sendable {
    let plannedRouteCount: Int
    let releasedRouteCount: Int
    let blockedRouteCount: Int
    let blockingDecisions: Set<String>
    let failures: [String]
  }

  /// Route decisions no released movement covers yet; a route through one is
  /// refused at Start and nothing else may refuse a planned pair. The two
  /// Honmoku JCT Bayshore-westbound movements wait for review against the
  /// operator's junction diagram. The third is the Asada 上り exit ramp: OSM
  /// tags it ref=K1, so the graph types it mainline, and its diverge node is
  /// listed under Namamugi JCT, so the route classifier reads leaving there
  /// as a junction movement; the operational branch catalog files the same
  /// ramp as a non-navigable dead end. Shrink this set when a review lands.
  private static let knownUnreleasedDecisions: Set<String> = [
    "osm.31711323.6.forward->osm.32403531.0.forward",
    "osm.31711323.6.forward->osm.340606274.0.forward",
    "osm.32592648.13.forward->osm.567321755.0.forward",
  ]

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
      "Set KAIDO_RUN_EXHAUSTIVE_ROUTE_ADMISSION=1 to run the exhaustive audit; `swift test -c release` runs it in about 20 minutes"
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
          var blockedRouteCount = 0
          var blockingDecisions: Set<String> = []
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
              } catch ShutoNetworkError.routeUnavailable,
                ShutoNetworkError.sharedTollPoint
              {
                continue
              } catch ShutoCircuitProductReleaseBuilderError
                .incompleteJunctionGuidance(let decisions)
              where Set(decisions).isSubset(of: Self.knownUnreleasedDecisions) {
                blockedRouteCount += 1
                blockingDecisions.formUnion(decisions)
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
            blockedRouteCount: blockedRouteCount,
            blockingDecisions: blockingDecisions,
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
    let blockedRouteCount = audits.reduce(0) {
      $0 + $1.blockedRouteCount
    }
    let blockingDecisions = audits.reduce(into: Set<String>()) {
      $0.formUnion($1.blockingDecisions)
    }
    let failures = audits.flatMap(\.failures).sorted()

    print(
      "Whole-Shuto live admission audit: planned=\(plannedRouteCount) "
        + "released=\(releasedRouteCount) blocked=\(blockedRouteCount) "
        + "failures=\(failures.count)"
    )

    #expect(plannedRouteCount > 0)
    #expect(
      failures.isEmpty,
      Comment(rawValue: failures.prefix(100).joined(separator: "\n"))
    )
    // Each known decision still blocks some route; one that no longer does
    // has been released and leaves the set.
    #expect(blockingDecisions == Self.knownUnreleasedDecisions)
    #expect(releasedRouteCount + blockedRouteCount == plannedRouteCount)
  }

  @Test(
    "every default circuit pairing and lap count builds live authority",
    .enabled(
      if: ProcessInfo.processInfo.environment[
        "KAIDO_RUN_EXHAUSTIVE_ROUTE_ADMISSION"
      ] == "1",
      "Set KAIDO_RUN_EXHAUSTIVE_ROUTE_ADMISSION=1 to run the exhaustive audit; `swift test -c release` runs it in about 20 minutes"
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
          // Without an origin the planner gates every direction-valid
          // entrance: every entrance some origin can be recommended.
          let entries = planner.circuitEntranceCandidates(for: circuit)

          for entry in entries {
            let pairing: ShutoCircuitPairing
            do {
              pairing = try planner.recommendedCircuitPairing(
                for: circuit,
                entranceFacilityID: entry.facilityID,
                evidence: .etcNormalCarFrom2026October
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
                  exitFacilityID: Self.startedExitFacilityID(circuit, pairing),
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

  @Test(
    "a recommended circuit pairing is always one Start admits",
    arguments: ShutoCircuitDefinition.bundled
  )
  func everyRecommendedCircuitPairingIsAdmitted(
    circuit: ShutoCircuitDefinition
  ) async throws {
    let database = try loadWholeShutoDatabase()
    let runtimeContext = try ShutoPlannedRouteRuntimeCompiler.NetworkContext(
      database: database
    )
    // Without an origin the planner gates every direction-valid entrance:
    // every entrance some origin can be recommended.
    let entrances = try ShutoRoutePlanner(database: database)
      .circuitEntranceCandidates(for: circuit)
      .map(\.facilityID)
    #expect(!entrances.isEmpty)
    let chunkSize = max(1, entrances.count / 4)
    let refusals = await withTaskGroup(
      of: [String].self,
      returning: [String].self
    ) { group in
      for start in stride(from: 0, to: entrances.count, by: chunkSize) {
        let chunk = entrances[start..<min(start + chunkSize, entrances.count)]
        group.addTask {
          let planner = try! ShutoRoutePlanner(database: database)
          var refusals: [String] = []
          for entranceID in chunk {
            do {
              let pairing = try planner.recommendedCircuitPairing(
                for: circuit,
                entranceFacilityID: entranceID,
                evidence: .etcNormalCarFrom2026October
              )
              let route = try planner.planCircuit(
                circuit: circuit,
                entryFacilityID: entranceID,
                exitFacilityID: Self.startedExitFacilityID(circuit, pairing),
                laps: 1
              )
              let release =
                try ShutoCircuitProductReleaseBuilder
                .buildPlannedRouteRelease(context: runtimeContext, route: route)
              if release.foregroundLiveInputAuthority == nil {
                refusals.append("\(entranceID): missing foreground authority")
              }
            } catch {
              refusals.append("\(entranceID): \(error)")
            }
          }
          return refusals
        }
      }
      var all: [String] = []
      for await part in group { all.append(contentsOf: part) }
      return all.sorted()
    }
    #expect(
      refusals.isEmpty,
      Comment(rawValue: refusals.joined(separator: "\n"))
    )
  }

  /// The exit Start plans a recommended pairing with: an experience with a
  /// default parking area drives into it, so its pairing's exit is not part
  /// of the recommended drive.
  private static func startedExitFacilityID(
    _ circuit: ShutoCircuitDefinition,
    _ pairing: ShutoCircuitPairing
  ) -> String? {
    circuit.defaultDestinationParkingAreaID == nil
      ? pairing.exit.facilityID : nil
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
