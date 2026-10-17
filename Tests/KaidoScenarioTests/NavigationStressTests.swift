#if canImport(CoreLocation)
  import Foundation
  import KaidoDomain
  import KaidoNavigation
  import KaidoRouting
  import XCTest

  // The main-versus-branch navigation stress harness, driven by
  // `scripts/stress/compare.sh` (docs/testing/navigation-stress.md). The script
  // selects, schedules and caches units and writes the report; this file only
  // drives each unit through the 1 Hz replay gate. compare.sh copies this file
  // into both trees, so main and branch always run the same harness, and the
  // cache keys rows by this file's content.

  /// One seeded drive of one cell: the cache and scheduling unit.
  struct NavigationStressUnit: Sendable {
    let group: String
    let route: String
    let profile: String
    let extra: String
    let seed: UInt64
  }

  enum NavigationStress {
    static let profiles: [String: ReplayGateNoiseModel] = [
      "URBAN": .urban, "MULTIPATH": .multipath, "UNDER2X": .underReported,
    ]

    static var env: [String: String] { ProcessInfo.processInfo.environment }

    /// Units, one per line: group, route, profile, extra and seed, tab-separated,
    /// in the order they should start.
    static func units(at path: String) throws -> [NavigationStressUnit] {
      try String(contentsOfFile: path, encoding: .utf8)
        .split(separator: "\n")
        .map { line in
          let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
          precondition(fields.count == 5, "malformed unit: \(line)")
          return NavigationStressUnit(
            group: fields[0], route: fields[1], profile: fields[2], extra: fields[3],
            seed: UInt64(fields[4])!
          )
        }
    }

    /// The next unclaimed index, from a counter file every worker shares.
    static func claim(_ path: String) -> Int {
      let descriptor = open(path, O_RDWR | O_CREAT, 0o644)
      precondition(descriptor >= 0, "cannot open \(path)")
      defer { close(descriptor) }
      flock(descriptor, LOCK_EX)
      defer { flock(descriptor, LOCK_UN) }
      var buffer = [UInt8](repeating: 0, count: 32)
      let count = pread(descriptor, &buffer, buffer.count, 0)
      let next = count > 0 ? Int(String(decoding: buffer[..<count], as: UTF8.self))! : 0
      let text = Array(String(next + 1).utf8)
      ftruncate(descriptor, 0)
      pwrite(descriptor, text, text.count, 0)
      return next
    }

    // MARK: Fixtures

    struct Fixture {
      let gate: LiveNavigationReplayGate
      var stopIndices: Range<Int>? = nil
      var bypass: [ShutoNetworkDatabase.Edge] = []
      var laps: [Range<Int>] = []
    }

    static let cache = NavigationStressCache()

    static func context() throws -> ShutoPlannedRouteRuntimeCompiler.NetworkContext {
      try cache.value("context") {
        try ShutoPlannedRouteRuntimeCompiler.NetworkContext(database: try replayGateDatabase())
      }
    }

    static func planner() throws -> ShutoRoutePlanner {
      try cache.value("planner") { try ShutoRoutePlanner(database: try replayGateDatabase()) }
    }

    static func fixture(_ route: String) throws -> Fixture {
      try cache.value("fixture:" + route) { try buildFixture(route) }
    }

    static func buildFixture(_ route: String) throws -> Fixture {
      let database = try replayGateDatabase()
      if route.hasPrefix("bundled:") {
        return Fixture(gate: try replayGate(String(route.dropFirst("bundled:".count))))
      }
      let planner = try planner()
      if route.hasPrefix("lapchange:") {
        return try lapChangeFixture(route, planner: planner, database: database)
      }
      if route.hasPrefix("via:") {
        return try viaFixture(route, planner: planner, database: database)
      }
      let parts = route.split(separator: ":")
      let laps = Int(parts[2])!
      let circuit: ShutoCircuitDefinition
      var entry: String
      switch parts[1] {
      case "c1-inner": circuit = .c1Inner; entry = "shuto.ic.c1.shibakouen"
      case "c1-outer":
        circuit = .c1Outer
        entry = planner.circuitEntranceCandidates(for: .c1Outer).first { $0.routeID == "C1" }!.facilityID
      case "c2": circuit = .c2InnerWithBayshore; entry = "shuto.ic.c2.oujiminami"
      case "daikoku", "stop": circuit = .daikokuYokohamaLoop; entry = "shuto.ic.b.wangankanpachi"
      case "c1-inner-s1": circuit = .c1Inner; entry = "shuto.ic.s1.shingou"
      case "c1-outer-s1": circuit = .c1Outer; entry = "shuto.ic.s1.shingou"
      case "c2-s1": circuit = .c2InnerWithBayshore; entry = "shuto.ic.s1.shingou"
      case "c1-inner-r4": circuit = .c1Inner; entry = "shuto.ic.4.yoyogi"
      case "c1-outer-r4": circuit = .c1Outer; entry = "shuto.ic.4.yoyogi"
      default: fatalError(route)
      }
      let exitID: String?
      switch parts[1] {
      case "c1-inner": exitID = "shuto.ic.c1.shiodome"
      case "c2": exitID = "shuto.ic.5.itabashihoncho"
      case "stop": exitID = "shuto.ic.1-haneda.haneda"
      case "daikoku": exitID = nil
      case "c1-inner-s1", "c1-outer-s1", "c2-s1": exitID = "shuto.ic.s1.angyou"
      case "c1-inner-r4", "c1-outer-r4": exitID = "shuto.ic.4.gaien"
      default:
        exitID = try planner.recommendedCircuitPairing(
          for: circuit, entranceFacilityID: entry, evidence: .etcNormalCarFrom2026October
        ).exit.facilityID
      }
      let base = try planner.planCircuit(
        circuit: circuit, entryFacilityID: entry, exitFacilityID: exitID, laps: laps
      )
      var planned = base
      var stopIndices: Range<Int>?
      var bypass: [ShutoNetworkDatabase.Edge] = []
      if parts[1] == "stop" {
        let stop = planner.parkingStopOptions(for: base).first { $0.id == "shuto.pa.daikoku" }!
        planned = try planner.addingParkingStops([stop.id], to: base)
        let stopLength = planned.edges.count - base.edges.count + stop.returnIndex - stop.departureIndex
        stopIndices = stop.departureIndex..<(stop.departureIndex + stopLength)
        bypass = Array(base.edges[stop.departureIndex..<stop.returnIndex])
      }
      let release = try ShutoCircuitProductReleaseBuilder.buildPlannedRouteRelease(
        context: try context(), route: planned
      )
      return Fixture(
        gate: LiveNavigationReplayGate(release: release, database: database),
        stopIndices: stopIndices,
        bypass: bypass,
        laps: lapRanges(planned)
      )
    }

    static let viaCircuits: [String: ShutoCircuitDefinition] = [
      "c1i": .c1Inner, "c1o": .c1Outer, "c2": .c2InnerWithBayshore,
      "wangan": .wanganDaikokuRun, "daikoku": .daikokuYokohamaLoop, "scenic": .scenicGrandTour,
    ]

    /// `via:<circuit>:<entry>:<exit or ->:<laps>`: any planned circuit, `-`
    /// ending at the circuit's default destination.
    static func viaFixture(
      _ route: String,
      planner: ShutoRoutePlanner,
      database: ShutoNetworkDatabase
    ) throws -> Fixture {
      let parts = route.split(separator: ":").map(String.init)
      let planned = try planner.planCircuit(
        circuit: viaCircuits[parts[1]]!, entryFacilityID: parts[2],
        exitFacilityID: parts[3] == "-" ? nil : parts[3], laps: Int(parts[4])!
      )
      let release = try ShutoCircuitProductReleaseBuilder.buildPlannedRouteRelease(
        context: try context(), route: planned
      )
      return Fixture(
        gate: LiveNavigationReplayGate(release: release, database: database),
        laps: lapRanges(planned)
      )
    }

    static func lapRanges(_ route: ShutoPlannedRoute) -> [Range<Int>] {
      let boundaries = route.lapBoundaryOccurrenceIndices
      return zip(boundaries, boundaries.dropFirst()).map { $0..<$1 }
    }

    static func lapChangeFixture(
      _ route: String,
      planner: ShutoRoutePlanner,
      database: ShutoNetworkDatabase
    ) throws -> Fixture {
      if route.hasPrefix("lapchange:stop") {
        return try fixture("loop:stop:3")
      }
      let planned = try planner.planCircuit(
        circuit: .daikokuYokohamaLoop,
        entryFacilityID: "shuto.ic.b.wangankanpachi",
        destinationParkingAreaID: "shuto.pa.daikoku",
        laps: 3
      )
      let release = try ShutoCircuitProductReleaseBuilder.buildPlannedRouteRelease(
        context: try context(), route: planned
      )
      return Fixture(
        gate: LiveNavigationReplayGate(release: release, database: database),
        laps: lapRanges(planned)
      )
    }

    // MARK: Legs

    static func bypassLegs(_ fixture: Fixture, database: ShutoNetworkDatabase) -> [ReplayGateLeg] {
      let nodes = Dictionary(uniqueKeysWithValues: database.nodes.map { ($0.nodeID, $0) })
      let stopIndices = fixture.stopIndices!
      let bypassLegs = fixture.bypass.map { edge in
        ReplayGateLeg(
          kind: .offPlan(edge.edgeID),
          coordinates: [edge.fromNodeID, edge.toNodeID].map {
            MatcherCoordinate(latitude: nodes[$0]!.latitude, longitude: nodes[$0]!.longitude)
          },
          speedMetersPerSecond: LiveNavigationReplayGate.mainlineSpeed
        )
      }
      var legs: [ReplayGateLeg] = []
      for leg in fixture.gate.plannedLegs() {
        if case .occurrence(let index) = leg.kind, stopIndices.contains(index) {
          if index == stopIndices.lowerBound { legs += bypassLegs }
          continue
        }
        legs.append(leg)
      }
      return legs
    }

    /// The planned drive with the lap-1 PA stop made again in lap 2: the
    /// lap-2 stretch the stop replaced is swapped for the stop's own roads,
    /// driven off the plan. Returns the legs and the lap-2 divergence index.
    static func paReentryLegs(_ fixture: Fixture) -> (legs: [ReplayGateLeg], divergence: Int) {
      let gate = fixture.gate
      let stopIndices = fixture.stopIndices!
      let bypassIDs = fixture.bypass.map(\.edgeID)
      let ids = gate.routeEdgeIDs
      let lap2 = fixture.laps[1]
      let start = lap2.first { index in
        index + bypassIDs.count <= ids.count && Array(ids[index..<(index + bypassIDs.count)]) == bypassIDs
      }!
      let replaced = start..<(start + bypassIDs.count)
      let planned = gate.plannedLegs()
      let stopLegs: [ReplayGateLeg] = planned.compactMap { leg in
        guard case .occurrence(let index) = leg.kind, stopIndices.contains(index) else { return nil }
        return ReplayGateLeg(
          kind: .offPlan(ids[index]), coordinates: leg.coordinates,
          speedMetersPerSecond: leg.speedMetersPerSecond, dwellSeconds: leg.dwellSeconds
        )
      }
      var legs: [ReplayGateLeg] = []
      for leg in planned {
        if case .occurrence(let index) = leg.kind, replaced.contains(index) {
          if index == replaced.lowerBound { legs += stopLegs }
          continue
        }
        legs.append(leg)
      }
      return (legs, start)
    }

    /// Movement indexes in a runtime loop at the bundled junction pair.
    static func pairMovementIndexes(_ fixture: Fixture, spec: String) throws -> [Int] {
      let fields = Dictionary(
        uniqueKeysWithValues: spec.split(separator: ",").map {
          let kv = $0.split(separator: "=")
          return (String(kv[0]), String(kv[1]))
        }
      )
      let bundledMovement = Int(fields["pair"]!)!
      let bundledFile =
        bundledMovement == 234
        ? "c2-inner-oujiminami-itabashihoncho-product-release.json"
        : "c1-inner-shibakoen-to-shiodome-product-release.json"
      let bundledGate = try NavigationStress.fixture("bundled:" + bundledFile).gate
      let incoming = bundledGate.routeEdgeIDs[bundledMovement - 1]
      let planned = bundledGate.routeEdgeIDs[bundledMovement]
      let ids = fixture.gate.routeEdgeIDs
      let matches = (1..<ids.count).filter { ids[$0 - 1] == incoming && ids[$0] == planned }
      let lap = fields["lap"]!
      let lapRange: Range<Int> = lap == "last" ? fixture.laps.last! : fixture.laps[Int(lap)! - 1]
      return matches.filter { lapRange.contains($0) }
    }

    static func sameRoadOccurrenceIndex(
      as index: Int, in lap: Range<Int>, plan: RoutePlan, laps: [Range<Int>]
    ) -> Int? {
      guard let current = plan.occurrences.first(where: { $0.index == index }),
        let ownLap = laps.first(where: { $0.contains(index) })
      else { return nil }
      let rank = plan.occurrences.count {
        ownLap.contains($0.index) && $0.index < index && $0.entityID == current.entityID
      }
      let sameRoad = plan.occurrences.filter {
        lap.contains($0.index) && $0.entityID == current.entityID
      }
      return sameRoad.indices.contains(rank) ? sameRoad[rank].index : nil
    }

    // MARK: Records

    static func baseRecord(
      _ unit: NavigationStressUnit, run: ReplayGateRun, gate: LiveNavigationReplayGate, seconds: Double
    ) -> [String: Any] {
      let window = RouteMatcherCorridor.longitudinalCandidateOccurrenceWindow
      let indexByID = Dictionary(
        uniqueKeysWithValues: gate.release.navigation.bundle.routePlan.occurrences.map { ($0.id, $0.index) }
      )
      var behind = 0
      var mayFire = 0
      var previousIndex: Int? = nil
      for record in run.records {
        if let before = previousIndex,
          let matched = record.estimate?.occurrenceID.flatMap({ indexByID[$0] }),
          matched < before - window
        {
          mayFire += 1
        }
        previousIndex = record.currentOccurrenceIndex
      }
      var maxLag = 0.0
      var maxAhead = -Double.infinity
      for record in run.records where record.phase == .strictRoute {
        if let current = record.currentOccurrenceIndex,
          let matched = record.estimate?.occurrenceID.flatMap({ indexByID[$0] }),
          matched < current - window
        {
          behind += 1
        }
        if let current = record.currentOccurrenceIndex, let truth = record.truth.routeDistanceMeters {
          let committed = gate.routeStartDistances[current]
          maxLag = max(maxLag, truth - committed)
          maxAhead = max(maxAhead, committed - truth)
        }
      }
      // Both wrong-commit rules, computed here so every tree reports them
      // alike: the rule before #73, and #73's (junction, error scale, pass).
      let errorScale = profiles[unit.profile]!.errorScale
      let movementIndexes = gate.release.navigation.bundle.routePlan.occurrences
        .filter { $0.kind == .junctionMovement }.map(\.index)
      var wrongOld = 0
      var wrong73 = 0
      var previousCommitIndex: Int? = nil
      for record in run.records {
        guard record.phase == .strictRoute || record.phase == .routeRecovery,
          let index = record.currentOccurrenceIndex
        else { continue }
        defer { previousCommitIndex = index }
        switch record.truth.kind {
        case .occurrence(let truthIndex):
          guard let truthDistance = record.truth.routeDistanceMeters else { continue }
          let ahead = gate.routeStartDistances[index] - truthDistance
          if ahead > 60 { wrongOld += 1 }
          let passesUnreachedJunction = movementIndexes.contains { $0 > truthIndex && $0 <= index }
          let committedEnd =
            index + 1 < gate.routeStartDistances.count
            ? gate.routeStartDistances[index + 1] : gate.routeLengthMeters
          if ahead > 60 * errorScale || (ahead > 60 && passesUnreachedJunction)
            || (index != previousCommitIndex
              && index != run.lapChangeOutcome?.fromOccurrenceIndex
              && committedEnd < truthDistance - 1_500)
          {
            wrong73 += 1
          }
        case .approach:
          wrongOld += 1
          wrong73 += 1
        case .offPlan, .egress, .parked:
          continue
        }
      }
      // When each lap boundary is first committed, against when the car
      // truly reaches it: what the lap counter and the drive record follow.
      let laps = (try? fixture(unit.route))?.laps ?? []
      let marks = laps.map(\.lowerBound) + (laps.last.map { [$0.upperBound] } ?? [])
      let lapMarks: [(mark: Int, commit: Int, truth: Int)] = marks.map { mark in
        let commit = run.records.first {
          ($0.phase == .strictRoute || $0.phase == .routeRecovery || $0.phase == .completed)
            && ($0.currentOccurrenceIndex ?? -1) >= mark
        }?.second ?? -1
        let truth = run.records.first { record in
          if case .occurrence(let index) = record.truth.kind { return index >= mark }
          if case .egress = record.truth.kind { return true }
          return false
        }?.second ?? -1
        return (mark, commit, truth)
      }
      let firstOff = run.records.first { $0.truth.offPlanDistanceMeters != nil }
      let detection = run.records.first {
        $0.truth.offPlanDistanceMeters != nil
          && ($0.phase == .routeRecovery || $0.phase == .completed)
      }
      let last = run.records.last
      var record: [String: Any] = [
        "group": unit.group, "route": unit.route, "profile": unit.profile, "seed": unit.seed,
        "extra": unit.extra,
        "occurrences": gate.routeEdgeIDs.count,
        "completed": run.reachedCompletion,
        "early": run.completedEarly(),
        "wrong": run.wrongCommitCount(),
        "wrongOld": wrongOld,
        "wrong73": wrong73,
        "falseRecovery": run.falseRouteRecoveryCount,
        "unadmitted": run.longestUnadmittedSeconds,
        "lostRun": run.longestLostSeconds,
        "entered": run.entryRecord != nil,
        "fixes": run.records.count, "truth": run.truthCount,
        "behindEstimates": behind,
        "mayFire": mayFire,
        "maxLagMeters": Int(maxLag),
        "maxAheadMeters": maxAhead.isFinite ? Int(maxAhead) : 0,
        "finalPhase": last?.phase.rawValue ?? "-",
        "finalRecovery": last?.recoveryStatus.rawValue ?? "-",
        "finalTrigger": last?.phaseTrigger ?? "-",
        "finalIndex": last?.currentOccurrenceIndex ?? -1,
        "delay": run.completionDelaySeconds ?? -1,
        "lapMarks": lapMarks.map(\.mark),
        "lapCommitSeconds": lapMarks.map(\.commit),
        "lapTruthSeconds": lapMarks.map(\.truth),
        "lateCues": run.lateOrMissingCueMovementIndexes(),
        "wall": (seconds * 10).rounded() / 10,
      ]
      // Handover to ordinary roads (#75): the first fix in SURFACE_EGRESS by UNPLANNED_EXIT.
      if let handoverIndex = run.records.firstIndex(where: {
        $0.phase == .surfaceEgress && $0.phaseTrigger == "UNPLANNED_EXIT"
      }) {
        let handover = run.records[handoverIndex]
        record["handover"] = true
        record["handoverSecond"] = handover.second
        record["handoverPrevPhase"] = handoverIndex > 0 ? run.records[handoverIndex - 1].phase.rawValue : "-"
        var truthKind = "other"
        var edgeKind = "-"
        switch handover.truth.kind {
        case .occurrence: truthKind = "occurrence"
        case .approach: truthKind = "approach"
        case .egress: truthKind = "egress"
        case .parked: truthKind = "parked"
        case .offPlan(let edgeID):
          truthKind = "offPlan"
          edgeKind = gate.database.edges.first { $0.edgeID == edgeID }?.kind ?? "notInNetwork"
        }
        record["handoverTruth"] = truthKind
        record["handoverEdgeKind"] = edgeKind
        record["handoverOffPlanMeters"] = handover.truth.offPlanDistanceMeters.map { Int($0) } ?? -1
        var streak = 0
        for earlier in run.records[..<handoverIndex].reversed() {
          guard earlier.phase == .strictRoute || earlier.phase == .routeRecovery,
            earlier.engineConfidence != .high
          else { break }
          streak += 1
        }
        record["handoverUnadmittedStreak"] = streak
        var lapBehindBeforeHandover = false
        var previousCurrent: Int? = nil
        for (offset, earlier) in run.records[..<handoverIndex].enumerated() {
          if offset >= handoverIndex - 30, let before = previousCurrent,
            let matched = earlier.estimate?.occurrenceID.flatMap({ indexByID[$0] }),
            matched < before - window
          {
            lapBehindBeforeHandover = true
          }
          previousCurrent = earlier.currentOccurrenceIndex
        }
        record["handoverLapBehind30s"] = lapBehindBeforeHandover
      } else {
        record["handover"] = false
      }
      // State when the car reached the divergence: the last fix before it left the plan.
      if let offIndex = run.records.firstIndex(where: { $0.truth.offPlanDistanceMeters != nil }), offIndex > 0 {
        let atJunction = run.records[offIndex - 1]
        record["junctionPhase"] = atJunction.phase.rawValue
        record["junctionCurrent"] = atJunction.currentOccurrenceIndex ?? -1
        if let current = atJunction.currentOccurrenceIndex, let truthDistance = atJunction.truth.routeDistanceMeters {
          record["junctionLagMeters"] = Int(truthDistance - gate.routeStartDistances[current])
        } else {
          record["junctionLagMeters"] = -99_999
        }
        var junctionStreak = 0
        for earlier in run.records[..<offIndex].reversed() {
          guard earlier.phase == .strictRoute || earlier.phase == .routeRecovery,
            earlier.engineConfidence != .high
          else { break }
          junctionStreak += 1
        }
        record["junctionUnadmittedStreak"] = junctionStreak
        var lapBehindAtJunction = false
        var previousAtJunction: Int? = nil
        for (offset, earlier) in run.records[..<offIndex].enumerated() {
          if offset >= offIndex - 30, let before = previousAtJunction,
            let matched = earlier.estimate?.occurrenceID.flatMap({ indexByID[$0] }),
            matched < before - window
          {
            lapBehindAtJunction = true
          }
          previousAtJunction = earlier.currentOccurrenceIndex
        }
        record["junctionLapBehind30s"] = lapBehindAtJunction
      }
      if let firstOff {
        record["offStartSecond"] = firstOff.second
        record["detectedAfterMeters"] = run.deviationDetectedAfterOffPlanMeters.map { Int($0) } ?? -1
        record["detectSeconds"] = detection.map { $0.second - firstOff.second } ?? -1
        record["detectPhase"] = detection?.phase.rawValue ?? "never"
        record["completedAfterMeters"] = run.completedAfterOffPlanMeters.map { Int($0) } ?? -1
        record["anyUnavailable"] = run.records.contains { $0.recoveryStatus == .unavailable }
      }
      return record
    }

    /// Per-fix trace of one run, when KAIDO_STRESS_TRACE names a file.
    static func trace(_ unit: NavigationStressUnit, run: ReplayGateRun, gate: LiveNavigationReplayGate, tag: String) {
      guard let path = env["KAIDO_STRESS_TRACE"] else { return }
      let indexByID = Dictionary(
        uniqueKeysWithValues: gate.release.navigation.bundle.routePlan.occurrences.map { ($0.id, $0.index) }
      )
      let window = RouteMatcherCorridor.longitudinalCandidateOccurrenceWindow
      var lines = ["TRACE \(unit.group) \(unit.route) \(unit.profile) \(unit.extra) \(tag) seed=\(unit.seed)"]
      var previousIndex: Int? = nil
      for record in run.records {
        let truthIndex = record.truth.routeDistanceMeters.map { distance in
          (gate.routeStartDistances.lastIndex { $0 <= distance }) ?? 0
        }
        let matched = record.estimate?.occurrenceID.flatMap { indexByID[$0] }
        let fire = previousIndex.flatMap { before in matched.map { $0 < before - window } } ?? false
        var kind = "\(record.truth.kind)"
        if kind.count > 40 { kind = String(kind.prefix(40)) }
        lines.append(
          [
            "t=\(record.second)", "truth=\(kind)", "tIdx=\(truthIndex.map(String.init) ?? "-")",
            "off=\(record.truth.offPlanDistanceMeters.map { String(Int($0)) } ?? "-")",
            "phase=\(record.phase.rawValue)", "cur=\(record.currentOccurrenceIndex.map(String.init) ?? "-")",
            "est=\(matched.map(String.init) ?? "-")", "edge=\(record.estimate?.directedEdgeID ?? "-")",
            "conf=\(record.estimate?.confidence.rawValue ?? "-")", "eng=\(record.engineConfidence.rawValue)",
            "dist=\(record.estimate?.distanceMeters.map { String(Int($0)) } ?? "-")",
            "acc=\(record.horizontalAccuracyMeters.map { String(Int($0)) } ?? "-")",
            "rec=\(record.recoveryStatus.rawValue)", "trig=\(record.phaseTrigger ?? "-")",
            "ahead=\(record.currentOccurrenceIndex.flatMap { current in record.truth.routeDistanceMeters.map { String(Int(gate.routeStartDistances[current] - $0)) } } ?? "-")",
            fire ? "BEHIND" : "",
          ].joined(separator: " ")
        )
        previousIndex = record.currentOccurrenceIndex
      }
      append(Data((lines.joined(separator: "\n") + "\n").utf8), to: path)
    }

    /// One line per unit, written whole so a unit's rows are cached all or none.
    static func emit(_ unit: NavigationStressUnit, rows: [[String: Any]]) {
      let line: [String: Any] = [
        "unit": [unit.group, unit.route, unit.profile, unit.extra, unit.seed],
        "rows": rows,
      ]
      var data = try! JSONSerialization.data(withJSONObject: line, options: [.sortedKeys])
      data.append(contentsOf: Array("\n".utf8))
      append(data, to: env["KAIDO_STRESS_OUT"]!)
    }

    static func append(_ data: Data, to path: String) {
      if !FileManager.default.fileExists(atPath: path) {
        FileManager.default.createFile(atPath: path, contents: nil)
      }
      let handle = FileHandle(forWritingAtPath: path)!
      handle.seekToEndOfFile()
      handle.write(data)
      handle.closeFile()
    }

    // MARK: Drives

    static func rows(_ unit: NavigationStressUnit) async throws -> [[String: Any]] {
      let fixture = try NavigationStress.fixture(unit.route)
      let gate = fixture.gate
      let noise = profiles[unit.profile]!
      let seed = unit.seed
      let database = try replayGateDatabase()
      var rows: [[String: Any]] = []
      switch unit.group {
      case "planned":
        let clock = ContinuousClock.now
        let run = try await gate.run(legs: gate.plannedLegs(), seed: seed, noise: noise)
        let elapsed = ContinuousClock.now - clock
        rows.append(baseRecord(unit, run: run, gate: gate, seconds: elapsed.seconds))
        trace(unit, run: run, gate: gate, tag: "")
      case "missedFinal":
        let movementIndex = gate.finalDivergenceIndex
        for alternative in gate.alternativeEdgeIDs(atMovementIndex: movementIndex) {
          let clock = ContinuousClock.now
          let run = try await gate.run(
            legs: gate.wrongBranchLegs(
              movementIndex: movementIndex, alternativeEdgeID: alternative, branchMeters: 1_500
            ),
            seed: seed, noise: noise
          )
          let elapsed = ContinuousClock.now - clock
          var record = baseRecord(unit, run: run, gate: gate, seconds: elapsed.seconds)
          record["movement"] = movementIndex
          record["alternative"] = alternative
          record["isPAEnding"] = gate.finalStopStartIndex != nil
          record["offPlanCommits"] = run.offPlanCommitCount(movementIndex: movementIndex)
          record["offPlanPrompts"] = run.offPlanPromptCount(movementIndex: movementIndex)
          rows.append(record)
          trace(unit, run: run, gate: gate, tag: "m=\(movementIndex) alt=\(alternative)")
        }
      case "wrongBranch":
        let movementIndexes: [Int]
        if unit.extra.hasPrefix("m=") {
          movementIndexes = [Int(unit.extra.dropFirst(2))!]
        } else {
          movementIndexes = try pairMovementIndexes(fixture, spec: unit.extra)
        }
        if movementIndexes.isEmpty {
          rows.append(["group": unit.group, "route": unit.route, "extra": unit.extra, "error": "no-pair"])
        }
        let released = gate.release.navigation.bundle.runtimePolicy.recoveryCandidates
        for movementIndex in movementIndexes {
          for alternative in gate.alternativeEdgeIDs(atMovementIndex: movementIndex) {
            let clock = ContinuousClock.now
            let run = try await gate.run(
              legs: gate.wrongBranchLegs(movementIndex: movementIndex, alternativeEdgeID: alternative),
              seed: seed, noise: noise
            )
            let elapsed = ContinuousClock.now - clock
            var record = baseRecord(unit, run: run, gate: gate, seconds: elapsed.seconds)
            record["movement"] = movementIndex
            record["alternative"] = alternative
            record["offPlanCommits"] = run.offPlanCommitCount(movementIndex: movementIndex)
            record["offPlanPrompts"] = run.offPlanPromptCount(movementIndex: movementIndex)
            record["hasReleasedDetour"] = released.contains { $0.triggerDirectedEdgeID == alternative }
            rows.append(record)
            trace(unit, run: run, gate: gate, tag: "m=\(movementIndex) alt=\(alternative)")
          }
        }
      case "paReentry":
        let (legs, divergence) = paReentryLegs(fixture)
        let clock = ContinuousClock.now
        let run = try await gate.run(legs: legs, seed: seed, noise: noise)
        let elapsed = ContinuousClock.now - clock
        var record = baseRecord(unit, run: run, gate: gate, seconds: elapsed.seconds)
        record["movement"] = divergence
        record["offPlanCommits"] = run.offPlanCommitCount(movementIndex: divergence + fixture.bypass.count)
        record["offPlanPrompts"] = run.offPlanPromptCount(movementIndex: divergence + fixture.bypass.count)
        record["anyRecovery"] = run.records.contains { $0.phase == .routeRecovery }
        let skipped = Set(run.finalSnapshot?.skippedOccurrenceIDs ?? [])
        record["skippedCount"] = skipped.count
        rows.append(record)
        trace(unit, run: run, gate: gate, tag: "m=\(divergence)")
      case "stopBypass":
        let clock = ContinuousClock.now
        let run = try await gate.run(legs: bypassLegs(fixture, database: database), seed: seed, noise: noise)
        let elapsed = ContinuousClock.now - clock
        var record = baseRecord(unit, run: run, gate: gate, seconds: elapsed.seconds)
        let stopIDs = gate.release.navigation.bundle.routePlan.occurrences
          .filter { fixture.stopIndices!.contains($0.index) }.map(\.id)
        let skipped = Set(run.finalSnapshot?.skippedOccurrenceIDs ?? [])
        let completedIDs = Set(run.finalSnapshot?.completedOccurrenceIDs ?? [])
        record["stopSkipped"] = stopIDs.allSatisfy(skipped.contains)
        record["stopCompleted"] = stopIDs.contains(where: completedIDs.contains)
        record["anyRecovery"] = run.records.contains { $0.phase == .routeRecovery || $0.recoveryStatus != .inactive }
        rows.append(record)
        trace(unit, run: run, gate: gate, tag: "")
      case "lapChange":
        let plan = gate.release.navigation.bundle.routePlan
        let action: ReplayGateLapChange.Action = unit.extra.hasSuffix("drop") ? .dropOneLap : .finishCurrentLap
        let from: Int
        let targetLap: Int
        if unit.extra.hasPrefix("stop") {
          let planner = try planner()
          let base = try planner.planCircuit(
            circuit: .daikokuYokohamaLoop,
            entryFacilityID: "shuto.ic.b.wangankanpachi",
            exitFacilityID: "shuto.ic.1-haneda.haneda",
            laps: 3
          )
          let stop = planner.parkingStopOptions(for: base).first { $0.id == "shuto.pa.daikoku" }!
          from =
            stop.departureIndex + fixture.stopIndices!.count + 20
          let stopLap = fixture.laps.firstIndex { $0.contains(stop.departureIndex) }!
          targetLap = action == .dropOneLap ? stopLap + 1 : fixture.laps.count - 1
        } else {
          from = fixture.laps[0].lowerBound + fixture.laps[0].count / 2
          targetLap = fixture.laps.count - 1
        }
        let to = sameRoadOccurrenceIndex(
          as: from, in: fixture.laps[targetLap], plan: plan, laps: fixture.laps
        )!
        let clock = ContinuousClock.now
        let run = try await gate.run(
          legs: gate.plannedLegs(skippingAfter: from - 1, through: to - 1),
          seed: seed, noise: noise,
          lapChange: ReplayGateLapChange(action: action, afterOccurrenceIndex: from)
        )
        let elapsed = ContinuousClock.now - clock
        var record = baseRecord(unit, run: run, gate: gate, seconds: elapsed.seconds)
        let landed = run.lapChangeOutcome?.landedOccurrenceID.flatMap { plan.occurrence(id: $0) }
        let asked = run.lapChangeOutcome.flatMap { outcome in
          plan.occurrences.first { $0.index == outcome.fromOccurrenceIndex }
        }
        let expected = asked.flatMap {
          sameRoadOccurrenceIndex(as: $0.index, in: fixture.laps[targetLap], plan: plan, laps: fixture.laps)
        }
        record["landedCorrect"] = landed != nil && landed?.index == expected && landed?.entityID == asked?.entityID
        rows.append(record)
        trace(unit, run: run, gate: gate, tag: "")
      default:
        fatalError(unit.group)
      }
      return rows
    }
  }

  final class NavigationStressCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: Any] = [:]
    private var keyLocks: [String: NSLock] = [:]

    func value<T>(_ key: String, _ build: () throws -> T) throws -> T {
      lock.lock()
      let keyLock: NSLock
      if let existing = keyLocks[key] {
        keyLock = existing
      } else {
        keyLock = NSLock()
        keyLocks[key] = keyLock
      }
      lock.unlock()
      keyLock.lock()
      defer { keyLock.unlock() }
      lock.lock()
      let cached = entries[key] as? T
      lock.unlock()
      if let cached { return cached }
      let built = try build()
      lock.lock()
      entries[key] = built
      lock.unlock()
      return built
    }
  }

  /// One worker: drives units until the shared claim counter runs past the
  /// list. compare.sh starts one worker process per core over the same list,
  /// longest drives first, because drives in one process scale badly across
  /// threads (shared route-plan storage turns retain/release into contended
  /// atomics), while separate processes share nothing.
  final class NavigationStressTests: XCTestCase {
    func testDriveUnits() async throws {
      let env = NavigationStress.env
      guard let unitsPath = env["KAIDO_STRESS_UNITS"] else {
        throw XCTSkip("Run by scripts/stress/compare.sh; see docs/testing/navigation-stress.md")
      }
      let units = try NavigationStress.units(at: unitsPath)
      let claims = env["KAIDO_STRESS_CLAIMS"]!
      var index = NavigationStress.claim(claims)
      while index < units.count {
        NavigationStress.emit(units[index], rows: try await NavigationStress.rows(units[index]))
        index = NavigationStress.claim(claims)
      }
    }
  }

  extension Duration {
    fileprivate var seconds: Double {
      Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
  }
#endif
