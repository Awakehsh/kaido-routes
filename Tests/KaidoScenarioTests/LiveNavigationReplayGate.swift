#if canImport(CoreLocation)
  import CoreLocation
  import Foundation
  import KaidoAppleAdapters
  import KaidoDomain
  import KaidoNavigation
  import KaidoRouting

  /// Deterministic 1 Hz replay of a bundled foreground release through the
  /// same Core Location adapters, entry gate and `NavigationSession` the App
  /// drives. The trace is synthetic: it proves deterministic behaviour under a
  /// declared noise model, never field reliability.
  struct LiveNavigationReplayGate {
    let release: KaidoProductRelease
    let database: ShutoNetworkDatabase

    private let corridorEdgesByID: [String: RouteMatcherDirectedEdge]
    private let databaseEdgesByID: [String: ShutoNetworkDatabase.Edge]
    private let nodesByID: [Int64: ShutoNetworkDatabase.Node]
    private let outgoingEdges: [Int64: [ShutoNetworkDatabase.Edge]]
    private let parkingInteriorEdgeIDs: Set<String>
    let routeEdgeIDs: [String]
    let routeStartDistances: [Double]
    let routeLengthMeters: Double

    init(release: KaidoProductRelease, database: ShutoNetworkDatabase) {
      self.release = release
      self.database = database
      let corridor = release.navigation.bundle.matcherCorridor
      corridorEdgesByID = Dictionary(
        uniqueKeysWithValues: corridor.edges.map { ($0.id, $0) }
      )
      databaseEdgesByID = Dictionary(
        uniqueKeysWithValues: database.edges.map { ($0.edgeID, $0) }
      )
      nodesByID = Dictionary(
        uniqueKeysWithValues: database.nodes.map { ($0.nodeID, $0) }
      )
      outgoingEdges = Dictionary(grouping: database.edges, by: \.fromNodeID)
      parkingInteriorEdgeIDs = Set(
        database.parkingAreas.flatMap { $0.interiorEdgeIDs ?? [] }
      )
      routeEdgeIDs = corridor.occurrences.sorted { $0.index < $1.index }
        .map(\.directedEdgeID)
      var starts: [Double] = []
      var total = 0.0
      for edgeID in routeEdgeIDs {
        starts.append(total)
        total += corridorEdgesByID[edgeID].map(replayLength) ?? 0
      }
      routeStartDistances = starts
      routeLengthMeters = total
    }

    // MARK: Ground truth

    /// The planned drive: a straight surface lead-in, the reviewed entry
    /// transition, every RoutePlan occurrence, then either a surface run-out
    /// past the exit or a stop inside the destination PA.
    func plannedLegs() -> [ReplayGateLeg] {
      var legs = approachLegs()
      legs += routeLegs(through: routeEdgeIDs.count - 1)
      legs += terminalLegs()
      return legs
    }

    /// A surface street that continues the approach straight ahead beneath
    /// or beside the ramp and never climbs it.
    func surfaceStreetLegs(meters: Double = 1_200) -> [ReplayGateLeg] {
      let approach = approachLegs()
      let first = approach[0].coordinates
      let start = first[0]
      let bearing = replayBearing(first[0], first[1])
      return [
        ReplayGateLeg(
          kind: .approach,
          coordinates: [
            start, replayOffset(start, bearingDegrees: bearing, meters: meters),
          ],
          speedMetersPerSecond: Self.surfaceSpeed
        )
      ]
    }

    /// The planned drive up to `movementIndex - 1`, then the alternative
    /// outgoing edge at that junction followed for `branchMeters`.
    func wrongBranchLegs(
      movementIndex: Int,
      alternativeEdgeID: String,
      branchMeters: Double = 2_500
    ) -> [ReplayGateLeg] {
      var legs = approachLegs()
      legs += routeLegs(through: movementIndex - 1)
      legs += branchPath(from: alternativeEdgeID, meters: branchMeters).map {
        edge in
        ReplayGateLeg(
          kind: .offPlan(edge.edgeID),
          coordinates: coordinates(of: edge),
          speedMetersPerSecond: speed(forDatabaseEdge: edge)
        )
      }
      return legs
    }

    /// Alternative expressway edges leaving the node at which RoutePlan
    /// occurrence `movementIndex` begins.
    func alternativeEdgeIDs(atMovementIndex movementIndex: Int) -> [String] {
      guard movementIndex > 0,
        let incoming = databaseEdgesByID[routeEdgeIDs[movementIndex - 1]],
        let planned = databaseEdgesByID[routeEdgeIDs[movementIndex]]
      else { return [] }
      return (outgoingEdges[planned.fromNodeID] ?? [])
        .filter {
          $0.edgeID != planned.edgeID && $0.toNodeID != incoming.fromNodeID
            && ShutoOperationalBranchCatalog.reviewedNonNavigableBranch(
              networkSnapshotID: database.networkSnapshotID,
              incomingDirectedEdgeID: incoming.edgeID,
              startDirectedEdgeID: $0.edgeID
            ) == nil
        }
        .map(\.edgeID)
        .sorted()
    }

    private func approachLegs() -> [ReplayGateLeg] {
      let transition = release.navigation.bundle.runtimePolicy.entryTransition
      let firstRouteEdgeID = routeEdgeIDs[0]
      // Transition edges in front of the RoutePlan; a route-prefix transition
      // contributes nothing beyond the route itself.
      let leadEdgeIDs = Array(
        transition.directedEdgeIDs.prefix { $0 != firstRouteEdgeID }
      )
      var legs: [ReplayGateLeg] = []
      let firstCoordinates =
        leadEdgeIDs.first.flatMap { corridorEdgesByID[$0]?.coordinates }
        ?? corridorEdgesByID[firstRouteEdgeID]!.coordinates
      let start = firstCoordinates[0]
      let bearing = replayBearing(firstCoordinates[0], firstCoordinates[1])
      legs.append(
        ReplayGateLeg(
          kind: .approach,
          coordinates: [
            replayOffset(start, bearingDegrees: bearing + 180, meters: 200),
            start,
          ],
          speedMetersPerSecond: Self.surfaceSpeed
        )
      )
      for edgeID in leadEdgeIDs {
        guard let edge = corridorEdgesByID[edgeID] else { continue }
        legs.append(
          ReplayGateLeg(
            kind: .approach,
            coordinates: edge.coordinates,
            speedMetersPerSecond: databaseEdgesByID[edgeID].map(
              speed(forDatabaseEdge:)
            ) ?? Self.surfaceSpeed
          )
        )
      }
      return legs
    }

    private func routeLegs(through lastIndex: Int) -> [ReplayGateLeg] {
      (0...lastIndex).map { index in
        let edgeID = routeEdgeIDs[index]
        return ReplayGateLeg(
          kind: .occurrence(index),
          coordinates: corridorEdgesByID[edgeID]!.coordinates,
          speedMetersPerSecond: databaseEdgesByID[edgeID].map(
            speed(forDatabaseEdge:)
          ) ?? Self.rampSpeed
        )
      }
    }

    private func terminalLegs() -> [ReplayGateLeg] {
      let last = corridorEdgesByID[routeEdgeIDs.last!]!.coordinates
      if release.navigation.bundle.routePlan.destinationParkingAreaID != nil {
        return [
          ReplayGateLeg(
            kind: .parked,
            coordinates: [last.last!, last.last!],
            speedMetersPerSecond: 0,
            dwellSeconds: 20
          )
        ]
      }
      // The exit ramp's own continuation where the graph has one, then a
      // straight surface run-out.
      var legs = branchPath(from: routeEdgeIDs.last!, meters: 300).dropFirst().map {
        edge in
        ReplayGateLeg(
          kind: .egress,
          coordinates: coordinates(of: edge),
          speedMetersPerSecond: Self.surfaceSpeed
        )
      }
      let tail = legs.last?.coordinates ?? last
      let end = tail[tail.count - 1]
      let bearing = replayBearing(tail[tail.count - 2], end)
      legs.append(
        ReplayGateLeg(
          kind: .egress,
          coordinates: [
            end, replayOffset(end, bearingDegrees: bearing, meters: 300),
          ],
          speedMetersPerSecond: Self.surfaceSpeed
        )
      )
      return legs
    }

    private func branchPath(
      from edgeID: String,
      meters: Double
    ) -> [ShutoNetworkDatabase.Edge] {
      guard var current = databaseEdgesByID[edgeID] else { return [] }
      var path = [current]
      var travelled = current.lengthMeters
      var visited: Set<String> = [current.edgeID]
      while travelled < meters {
        let bearing = edgeBearing(current)
        let next = (outgoingEdges[current.toNodeID] ?? [])
          .filter {
            $0.toNodeID != current.fromNodeID && !visited.contains($0.edgeID)
          }
          .min { lhs, rhs in
            let lhsKey = (
              lhs.wayID == current.wayID ? 0 : 1,
              replayAngularDifference(bearing, edgeBearing(lhs))
            )
            let rhsKey = (
              rhs.wayID == current.wayID ? 0 : 1,
              replayAngularDifference(bearing, edgeBearing(rhs))
            )
            return lhsKey < rhsKey
          }
        guard let next else { break }
        path.append(next)
        visited.insert(next.edgeID)
        travelled += next.lengthMeters
        current = next
      }
      return path
    }

    private func coordinates(
      of edge: ShutoNetworkDatabase.Edge
    ) -> [MatcherCoordinate] {
      [edge.fromNodeID, edge.toNodeID].compactMap { nodesByID[$0] }.map {
        MatcherCoordinate(latitude: $0.latitude, longitude: $0.longitude)
      }
    }

    private func edgeBearing(_ edge: ShutoNetworkDatabase.Edge) -> Double {
      let points = coordinates(of: edge)
      return replayBearing(points[0], points[1])
    }

    private func speed(forDatabaseEdge edge: ShutoNetworkDatabase.Edge) -> Double {
      if parkingInteriorEdgeIDs.contains(edge.edgeID) { return Self.parkingSpeed }
      return edge.kind == "MAINLINE" ? Self.mainlineSpeed : Self.rampSpeed
    }

    static let mainlineSpeed = 70 / 3.6
    static let rampSpeed = 40 / 3.6
    static let parkingSpeed = 15 / 3.6
    static let surfaceSpeed = 30 / 3.6

    /// Reviewed movements whose every cue is anchored at or after the
    /// preceding decision, where that decision's alternative branch stays
    /// within the matcher's widest ambiguity allowance of the plan all the
    /// way to this movement. Geometry cannot confirm the car took the planned
    /// branch before this decision, so its cue is withheld rather than
    /// spoken for a road the car may not be on.
    func structurallyUnconfirmableMovementIndexes() -> Set<Int> {
      let plan = release.navigation.bundle.routePlan
      let movementIndexes = plan.occurrences
        .filter { $0.kind == .junctionMovement }.map(\.index)
      let anchorsByMovement = Dictionary(
        grouping: release.navigation.bundle.releasedGuidance,
        by: { $0.frameTemplate.movementOccurrenceID }
      ).compactMapValues { definitions in
        definitions.compactMap { plan.occurrence(id: $0.anchor.occurrenceID)?.index }
          .min()
      }
      let routeEdges = Set(routeEdgeIDs)
      var result: Set<Int> = []
      for movement in movementIndexes {
        guard
          let earliestAnchor = plan.occurrences.first(where: { $0.index == movement })
            .flatMap({ anchorsByMovement[$0.id] }),
          let previous = movementIndexes.last(where: { $0 < movement }),
          earliestAnchor >= previous,
          let incoming = corridorEdgesByID[routeEdgeIDs[previous - 1]]
        else { continue }
        var branch: [[MatcherCoordinate]] = []
        var frontier = incoming.successorEdgeIDs.filter { !routeEdges.contains($0) }
        var seen = Set(frontier)
        var travelled = 0.0
        while let edgeID = frontier.popFirst(), travelled < 2_000 {
          guard let edge = corridorEdgesByID[edgeID] else { continue }
          branch.append(edge.coordinates)
          travelled += replayLength(edge)
          for next in edge.successorEdgeIDs
          where !routeEdges.contains(next) && seen.insert(next).inserted {
            frontier.insert(next)
          }
        }
        guard !branch.isEmpty else { continue }
        let from = routeStartDistances[previous]
        let to = routeStartDistances[movement]
        let samples = stride(from: from, through: to, by: 10).map { distance in
          routePoint(atDistance: distance)
        }
        let unconfirmable = samples.allSatisfy { point in
          branch.contains {
            replayDistance(from: point, toPolyline: $0) <= Self.ambiguityAllowanceMeters
          }
        }
        if unconfirmable { result.insert(movement) }
      }
      return result
    }

    /// The matcher's widest ambiguity allowance.
    static let ambiguityAllowanceMeters = 25.0

    private func routePoint(atDistance distance: Double) -> MatcherCoordinate {
      let index = max(
        0,
        (routeStartDistances.lastIndex { $0 <= distance }) ?? 0
      )
      let edge = corridorEdgesByID[routeEdgeIDs[index]]!
      return replayLocate(
        edge.coordinates,
        along: distance - routeStartDistances[index]
      ).coordinate
    }

    // MARK: Route geometry helpers

    func routeDistance(occurrenceIndex: Int, fraction: Double) -> Double {
      routeStartDistances[occurrenceIndex]
        + fraction
        * (corridorEdgesByID[routeEdgeIDs[occurrenceIndex]].map(replayLength)
          ?? 0)
    }

    func distanceFromRouteEdge(
      occurrenceIndex: Int,
      to coordinate: MatcherCoordinate
    ) -> Double {
      guard let edge = corridorEdgesByID[routeEdgeIDs[occurrenceIndex]] else {
        return .infinity
      }
      return replayDistance(from: coordinate, toPolyline: edge.coordinates)
    }

    // MARK: Replay

    func run(
      legs: [ReplayGateLeg],
      seed: UInt64,
      noise: ReplayGateNoiseModel = .urban
    ) async throws -> ReplayGateRun {
      let truth = ReplayGateTruthSampler.sample(legs: legs, gate: self)
      let runtime = try KaidoProductNavigationRuntime(
        release: release,
        journeyPlan: JourneyPlanCompiler.expresswayOnly(release: release)
      )
      let session = try ShutoLiveDriveSession(runtime: runtime)
      var entryAdapter = try CoreLocationEntryTransitionAdapter(
        context: runtime.entryTransitionAdmissionContext
      )
      var observationAdapter = try CoreLocationObservationAdapter(
        sessionID: "replay-gate.\(release.releaseID).\(seed)"
      )
      var generator = ReplayGateNoiseGenerator(seed: seed, model: noise)
      let promptMovements = Dictionary(
        uniqueKeysWithValues: release.navigation.bundle.releasedGuidance.map {
          ($0.anchor.promptID, $0.frameTemplate.movementOccurrenceID)
        }
      )
      _ = await session.start()
      let startedAt = 1_800_000_000_000
      var records: [ReplayGateFixRecord] = []
      records.reserveCapacity(truth.count)
      for (second, point) in truth.enumerated() {
        let fix = generator.fix(for: point)
        let observedAt = startedAt + second * 1_000
        let receivedAt = observedAt + fix.receptionDelayMilliseconds
        let location = CLLocation(
          coordinate: CLLocationCoordinate2D(
            latitude: fix.coordinate.latitude,
            longitude: fix.coordinate.longitude
          ),
          altitude: 0,
          horizontalAccuracy: fix.horizontalAccuracyMeters,
          verticalAccuracy: -1,
          course: fix.courseDegrees ?? -1,
          courseAccuracy: fix.courseAccuracyDegrees ?? -1,
          speed: fix.speedMetersPerSecond ?? -1,
          speedAccuracy: fix.speedAccuracyMetersPerSecond ?? -1,
          timestamp: Date(timeIntervalSince1970: Double(observedAt) / 1_000)
        )
        let adapted = observationAdapter.adapt(
          [location],
          receivedAt: Date(timeIntervalSince1970: Double(receivedAt) / 1_000)
        )
        guard case .accepted(let envelope) = adapted.first else {
          throw ReplayGateError.observationRejected(second)
        }
        let before = await session.snapshot
        var rawConfidence: MatcherConfidence?
        var emittedMovementIDs: [String] = []
        var estimate: MatcherEstimate?
        switch before.journeyPhase {
        case .planning, .approachToEntry, .entryTransition:
          let evidence = try entryAdapter.adapt(envelope)
          _ = try await session.observeEntryTransitionEvidence(evidence)
          rawConfidence = evidence.confidence
        case .strictRoute, .routeRecovery:
          let update = try await session.observe(envelope.observation)
          rawConfidence = update.matcherEstimate.confidence
          estimate = update.matcherEstimate
          if let emission = update.guidancePromptEmission,
            let movement = promptMovements[emission.promptID]
          {
            emittedMovementIDs.append(movement)
          }
        case .exitTransition:
          _ = await session.completeAtExitHandoff()
        case .surfaceEgress, .completed:
          break
        }
        var after = await session.snapshot
        if after.journeyPhase == .exitTransition {
          // Expressway-only journeys hand off to completion immediately.
          after = await session.completeAtExitHandoff()
        }
        records.append(
          ReplayGateFixRecord(
            second: second,
            truth: point,
            observedCoordinate: fix.coordinate,
            horizontalAccuracyMeters: fix.horizontalAccuracyMeters,
            phase: after.journeyPhase,
            currentOccurrenceIndex: after.currentOccurrenceIndex,
            engineConfidence: after.locationConfidence,
            rawConfidence: rawConfidence,
            estimate: estimate,
            recoveryStatus: after.recovery.status,
            emittedMovementOccurrenceIDs: emittedMovementIDs
          )
        )
        if after.journeyPhase == .completed { break }
      }
      return ReplayGateRun(gate: self, records: records, truthCount: truth.count)
    }

  }

  enum ReplayGateError: Error {
    case observationRejected(Int)
  }

  enum ReplayGateLegKind: Equatable, Sendable {
    case approach
    case occurrence(Int)
    case offPlan(String)
    case egress
    case parked
  }

  struct ReplayGateLeg: Sendable {
    let kind: ReplayGateLegKind
    let coordinates: [MatcherCoordinate]
    let speedMetersPerSecond: Double
    var dwellSeconds: Double = 0
  }

  struct ReplayGateTruthPoint: Sendable {
    let coordinate: MatcherCoordinate
    let bearingDegrees: Double
    let speedMetersPerSecond: Double
    let kind: ReplayGateLegKind
    /// Distance along the RoutePlan, only while on a planned occurrence.
    let routeDistanceMeters: Double?
    /// Distance travelled along an off-plan branch since leaving the route.
    let offPlanDistanceMeters: Double?
  }

  enum ReplayGateTruthSampler {
    /// Samples strictly once per second from a piecewise constant-speed
    /// trajectory; a short edge is crossed between fixes like a real car.
    static func sample(
      legs: [ReplayGateLeg],
      gate: LiveNavigationReplayGate
    ) -> [ReplayGateTruthPoint] {
      struct TimedLeg {
        let leg: ReplayGateLeg
        let start: Double
        let duration: Double
        let length: Double
        let offPlanStart: Double?
      }
      var timed: [TimedLeg] = []
      var clock = 0.0
      var offPlanTravelled = 0.0
      var hasLeftRoute = false
      for leg in legs {
        let length = replayLength(leg.coordinates)
        let duration =
          leg.speedMetersPerSecond > 0
          ? length / leg.speedMetersPerSecond : leg.dwellSeconds
        var offPlanStart: Double?
        if case .offPlan = leg.kind {
          hasLeftRoute = true
          offPlanStart = offPlanTravelled
          offPlanTravelled += length
        }
        _ = hasLeftRoute
        timed.append(
          TimedLeg(
            leg: leg,
            start: clock,
            duration: duration,
            length: length,
            offPlanStart: offPlanStart
          )
        )
        clock += duration
      }
      var points: [ReplayGateTruthPoint] = []
      var cursor = 0
      var second = 0.0
      while second < clock {
        while cursor < timed.count - 1,
          second >= timed[cursor].start + timed[cursor].duration
        {
          cursor += 1
        }
        let current = timed[cursor]
        let along =
          current.leg.speedMetersPerSecond > 0
          ? min(
            current.length,
            (second - current.start) * current.leg.speedMetersPerSecond
          ) : current.length
        let located = replayLocate(current.leg.coordinates, along: along)
        var routeDistance: Double?
        if case .occurrence(let index) = current.leg.kind {
          routeDistance =
            gate.routeStartDistances[index] + along
        }
        points.append(
          ReplayGateTruthPoint(
            coordinate: located.coordinate,
            bearingDegrees: located.bearing,
            speedMetersPerSecond: current.leg.speedMetersPerSecond,
            kind: current.leg.kind,
            routeDistanceMeters: routeDistance,
            offPlanDistanceMeters: current.offPlanStart.map { $0 + along }
          )
        )
        second += 1
      }
      return points
    }
  }

  struct ReplayGateNoiseModel: Sendable {
    let accuracyRange: ClosedRange<Double>
    let burstAccuracyRange: ClosedRange<Double>
    let burstStartProbability: Double
    let burstSecondsRange: ClosedRange<Double>
    let errorCorrelation: Double
    let courseAccuracyRange: ClosedRange<Double>
    let burstCourseAccuracyRange: ClosedRange<Double>
    let speedAccuracyRange: ClosedRange<Double>
    let burstSpeedAccuracyRange: ClosedRange<Double>

    /// 5–15 m open-sky fixes with 30–60 m bursts under structures. The
    /// horizontal error is a correlated 2D Gaussian whose radius falls within
    /// the reported accuracy about 68% of the time.
    static let urban = ReplayGateNoiseModel(
      accuracyRange: 5...15,
      burstAccuracyRange: 30...60,
      burstStartProbability: 0.012,
      burstSecondsRange: 4...12,
      errorCorrelation: 0.7,
      courseAccuracyRange: 3...10,
      burstCourseAccuracyRange: 15...35,
      speedAccuracyRange: 0.3...1,
      burstSpeedAccuracyRange: 1.5...3
    )
  }

  struct ReplayGateFix: Sendable {
    let coordinate: MatcherCoordinate
    let horizontalAccuracyMeters: Double
    let courseDegrees: Double?
    let courseAccuracyDegrees: Double?
    let speedMetersPerSecond: Double?
    let speedAccuracyMetersPerSecond: Double?
    let receptionDelayMilliseconds: Int
  }

  struct ReplayGateNoiseGenerator {
    private var random: ReplayGateRandom
    private let model: ReplayGateNoiseModel
    private var northError = 0.0
    private var eastError = 0.0
    private var burstRemaining = 0

    init(seed: UInt64, model: ReplayGateNoiseModel) {
      random = ReplayGateRandom(seed: seed)
      self.model = model
    }

    mutating func fix(for truth: ReplayGateTruthPoint) -> ReplayGateFix {
      if burstRemaining == 0,
        random.uniform() < model.burstStartProbability
      {
        burstRemaining = Int(random.uniform(model.burstSecondsRange).rounded())
      }
      let inBurst = burstRemaining > 0
      if inBurst { burstRemaining -= 1 }
      let accuracy = random.uniform(
        inBurst ? model.burstAccuracyRange : model.accuracyRange
      )
      // A 68% radius equals 1.515 standard deviations of each axis. The
      // correlated error is kept in units of the current sigma, so a fix
      // leaving a burst reports an accuracy its error honours.
      let sigma = accuracy / 1.515
      let rho = model.errorCorrelation
      let innovation = sqrt(1 - rho * rho)
      northError = rho * northError + innovation * random.gaussian()
      eastError = rho * eastError + innovation * random.gaussian()
      let coordinate = replayOffset(
        truth.coordinate,
        northMeters: northError * sigma,
        eastMeters: eastError * sigma
      )
      let moving = truth.speedMetersPerSecond >= 1
      let courseAccuracy = random.uniform(
        inBurst ? model.burstCourseAccuracyRange : model.courseAccuracyRange
      )
      let speedAccuracy = random.uniform(
        inBurst ? model.burstSpeedAccuracyRange : model.speedAccuracyRange
      )
      var course: Double?
      if moving {
        let value =
          truth.bearingDegrees + courseAccuracy * random.gaussian()
        course = value.truncatingRemainder(dividingBy: 360) < 0
          ? value.truncatingRemainder(dividingBy: 360) + 360
          : value.truncatingRemainder(dividingBy: 360)
      }
      let speed = max(
        0,
        truth.speedMetersPerSecond + speedAccuracy * random.gaussian()
      )
      return ReplayGateFix(
        coordinate: coordinate,
        horizontalAccuracyMeters: accuracy,
        courseDegrees: course,
        courseAccuracyDegrees: moving ? courseAccuracy : nil,
        speedMetersPerSecond: speed,
        speedAccuracyMetersPerSecond: speedAccuracy,
        receptionDelayMilliseconds: Int(random.uniform(0...300))
      )
    }
  }

  /// SplitMix64: a tiny, fully reproducible generator.
  struct ReplayGateRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var value = state
      value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
      value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
      return value ^ (value >> 31)
    }

    mutating func uniform() -> Double {
      Double(next() >> 11) / Double(UInt64(1) << 53)
    }

    mutating func uniform(_ range: ClosedRange<Double>) -> Double {
      range.lowerBound + (range.upperBound - range.lowerBound) * uniform()
    }

    mutating func gaussian() -> Double {
      let first = max(uniform(), .leastNonzeroMagnitude)
      let second = uniform()
      return sqrt(-2 * log(first)) * cos(2 * .pi * second)
    }
  }

  struct ReplayGateFixRecord: Sendable {
    let second: Int
    let truth: ReplayGateTruthPoint
    let observedCoordinate: MatcherCoordinate
    let horizontalAccuracyMeters: Double
    let phase: JourneyPhase
    let currentOccurrenceIndex: Int?
    let engineConfidence: LocationConfidence
    let rawConfidence: MatcherConfidence?
    let estimate: MatcherEstimate?
    let recoveryStatus: RecoveryState.Status
    let emittedMovementOccurrenceIDs: [String]
  }

  struct ReplayGateRun {
    let gate: LiveNavigationReplayGate
    let records: [ReplayGateFixRecord]
    let truthCount: Int

    var entryRecord: ReplayGateFixRecord? {
      records.first { $0.phase == .strictRoute }
    }

    var reachedCompletion: Bool {
      records.last?.phase == .completed
    }

    var expresswayRecords: [ReplayGateFixRecord] {
      records.filter { $0.phase == .strictRoute || $0.phase == .routeRecovery }
    }

    /// A committed occurrence that begins more than `aheadToleranceMeters`
    /// beyond where the car truly is, or any commit while the car is off the
    /// plan, unless the committed edge is geometrically under the car.
    func wrongCommitCount(aheadToleranceMeters: Double = 60) -> Int {
      records.count { record in
        guard record.phase == .strictRoute || record.phase == .routeRecovery,
          let index = record.currentOccurrenceIndex
        else { return false }
        switch record.truth.kind {
        case .occurrence:
          guard let truthDistance = record.truth.routeDistanceMeters else {
            return false
          }
          return gate.routeStartDistances[index]
            > truthDistance + aheadToleranceMeters
        case .approach:
          return true
        case .offPlan, .egress, .parked:
          return false
        }
      }
    }

    /// Commits of an occurrence at or beyond the planned movement while the
    /// car is on the alternative branch and not on that occurrence's edge.
    func offPlanCommitCount(movementIndex: Int) -> Int {
      records.count { record in
        guard case .offPlan = record.truth.kind,
          let index = record.currentOccurrenceIndex,
          index >= movementIndex
        else { return false }
        return gate.distanceFromRouteEdge(
          occurrenceIndex: index,
          to: record.truth.coordinate
        ) > 30
      }
    }

    func offPlanPromptCount(movementIndex: Int) -> Int {
      let plan = gate.release.navigation.bundle.routePlan
      return records.reduce(0) { count, record in
        guard case .offPlan = record.truth.kind else { return count }
        return count
          + record.emittedMovementOccurrenceIDs.count {
            (plan.occurrence(id: $0)?.index ?? 0) >= movementIndex
          }
      }
    }

    var deviationDetectedAfterOffPlanMeters: Double? {
      records.first {
        $0.phase == .routeRecovery && $0.truth.offPlanDistanceMeters != nil
      }?.truth.offPlanDistanceMeters
    }

    /// Movements whose first spoken cue came at or after the car reached the
    /// maneuver, or never came, while the car was on the planned route.
    func lateOrMissingCueMovementIndexes(
      throughRouteDistance limit: Double? = nil
    ) -> [Int] {
      let plan = gate.release.navigation.bundle.routePlan
      let guided = Set(
        gate.release.navigation.bundle.releasedGuidance.map {
          $0.frameTemplate.movementOccurrenceID
        }
      )
      var firstCueDistance: [String: Double] = [:]
      for record in records {
        for movementID in record.emittedMovementOccurrenceIDs
        where firstCueDistance[movementID] == nil {
          firstCueDistance[movementID] =
            record.truth.routeDistanceMeters ?? .infinity
        }
      }
      return guided.compactMap { movementID -> Int? in
        guard let movement = plan.occurrence(id: movementID) else { return nil }
        let maneuverDistance = gate.routeStartDistances[movement.index]
        if let limit, maneuverDistance > limit { return nil }
        guard let cue = firstCueDistance[movementID] else {
          return movement.index
        }
        return cue < maneuverDistance ? nil : movement.index
      }.sorted()
    }

    func minimumCueLeadMeters() -> Double? {
      let plan = gate.release.navigation.bundle.routePlan
      var leads: [Double] = []
      var seen: Set<String> = []
      for record in records {
        for movementID in record.emittedMovementOccurrenceIDs
        where seen.insert(movementID).inserted {
          guard let movement = plan.occurrence(id: movementID),
            let truth = record.truth.routeDistanceMeters
          else { continue }
          leads.append(gate.routeStartDistances[movement.index] - truth)
        }
      }
      return leads.min()
    }

    /// Fixes the App shows as weak position: at review time any fresh
    /// expressway fix whose raw matcher result was below HIGH.
    var rawBelowHighFraction: Double {
      let strict = records.filter { $0.phase == .strictRoute }
      guard !strict.isEmpty else { return 0 }
      return Double(strict.count { $0.rawConfidence != .high })
        / Double(strict.count)
    }

    var longestRawBelowHighRunSeconds: Int {
      longestRun(in: records.filter { $0.phase == .strictRoute }) {
        $0.rawConfidence != .high
      }
    }

    /// Longest stretch on the expressway without a fix the engine admitted
    /// as route progress.
    var longestUnadmittedSeconds: Int {
      longestRun(in: records.filter { $0.phase == .strictRoute }) {
        $0.engineConfidence != .high
      }
    }

    /// Longest stretch on the expressway in which no fix placed the car on
    /// any corridor road: the only gap the App may label weak position.
    var longestLostSeconds: Int {
      longestRun(in: expresswayRecords) { $0.rawConfidence == .lost }
    }

    var admittedFraction: Double {
      let strict = records.filter { $0.phase == .strictRoute }
      guard !strict.isEmpty else { return 0 }
      return Double(strict.count { $0.engineConfidence == .high })
        / Double(strict.count)
    }

    /// Seconds between the car leaving the last planned occurrence (exit
    /// run-out or PA stop) and the journey completing.
    var completionDelaySeconds: Int? {
      guard reachedCompletion,
        let leftAt = records.first(where: {
          $0.truth.kind == .egress || $0.truth.kind == .parked
        })?.second,
        let completedAt = records.last?.second
      else { return nil }
      return completedAt - leftAt
    }

    private func longestRun(
      in records: [ReplayGateFixRecord],
      _ predicate: (ReplayGateFixRecord) -> Bool
    ) -> Int {
      var longest = 0
      var current = 0
      var previousSecond: Int?
      for record in records {
        if predicate(record),
          previousSecond.map({ record.second == $0 + 1 }) ?? true
        {
          current += 1
        } else {
          current = predicate(record) ? 1 : 0
        }
        longest = max(longest, current)
        previousSecond = record.second
      }
      return longest
    }
  }

  // MARK: Geometry

  func replayLength(_ edge: RouteMatcherDirectedEdge) -> Double {
    replayLength(edge.coordinates)
  }

  func replayLength(_ coordinates: [MatcherCoordinate]) -> Double {
    zip(coordinates, coordinates.dropFirst()).reduce(0) {
      $0 + replayHaversine($1.0, $1.1)
    }
  }

  func replayHaversine(_ lhs: MatcherCoordinate, _ rhs: MatcherCoordinate)
    -> Double
  {
    let latitude1 = lhs.latitude * .pi / 180
    let latitude2 = rhs.latitude * .pi / 180
    let deltaLatitude = latitude2 - latitude1
    let deltaLongitude = (rhs.longitude - lhs.longitude) * .pi / 180
    let value =
      sin(deltaLatitude / 2) * sin(deltaLatitude / 2)
      + cos(latitude1) * cos(latitude2) * sin(deltaLongitude / 2)
      * sin(deltaLongitude / 2)
    return 2 * 6_371_000 * atan2(sqrt(value), sqrt(max(0, 1 - value)))
  }

  func replayBearing(_ start: MatcherCoordinate, _ end: MatcherCoordinate)
    -> Double
  {
    let latitude1 = start.latitude * .pi / 180
    let latitude2 = end.latitude * .pi / 180
    let deltaLongitude = (end.longitude - start.longitude) * .pi / 180
    let y = sin(deltaLongitude) * cos(latitude2)
    let x =
      cos(latitude1) * sin(latitude2)
      - sin(latitude1) * cos(latitude2) * cos(deltaLongitude)
    let degrees = atan2(y, x) * 180 / .pi
    return degrees >= 0 ? degrees : degrees + 360
  }

  func replayAngularDifference(_ lhs: Double, _ rhs: Double) -> Double {
    let difference = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
    return min(difference, 360 - difference)
  }

  func replayOffset(
    _ coordinate: MatcherCoordinate,
    northMeters: Double,
    eastMeters: Double
  ) -> MatcherCoordinate {
    let radius = 6_371_000.0
    let latitude = coordinate.latitude * .pi / 180
    return MatcherCoordinate(
      latitude: coordinate.latitude + northMeters / radius * 180 / .pi,
      longitude: coordinate.longitude
        + eastMeters / (radius * cos(latitude)) * 180 / .pi
    )
  }

  func replayOffset(
    _ coordinate: MatcherCoordinate,
    bearingDegrees: Double,
    meters: Double
  ) -> MatcherCoordinate {
    let radians = bearingDegrees * .pi / 180
    return replayOffset(
      coordinate,
      northMeters: meters * cos(radians),
      eastMeters: meters * sin(radians)
    )
  }

  func replayLocate(
    _ coordinates: [MatcherCoordinate],
    along distance: Double
  ) -> (coordinate: MatcherCoordinate, bearing: Double) {
    var remaining = distance
    for (start, end) in zip(coordinates, coordinates.dropFirst()) {
      let length = replayHaversine(start, end)
      let bearing = replayBearing(start, end)
      if remaining <= length || length == 0 {
        let fraction = length > 0 ? remaining / length : 0
        return (
          MatcherCoordinate(
            latitude: start.latitude + (end.latitude - start.latitude) * fraction,
            longitude: start.longitude
              + (end.longitude - start.longitude) * fraction
          ),
          bearing
        )
      }
      remaining -= length
    }
    let last = coordinates[coordinates.count - 1]
    let previous = coordinates[max(0, coordinates.count - 2)]
    return (last, replayBearing(previous, last))
  }

  func replayDistance(
    from point: MatcherCoordinate,
    toPolyline coordinates: [MatcherCoordinate]
  ) -> Double {
    zip(coordinates, coordinates.dropFirst()).map { start, end in
      let latitudeScale = 6_371_000.0 * .pi / 180
      let longitudeScale = latitudeScale * cos(point.latitude * .pi / 180)
      let segmentX = (end.longitude - start.longitude) * longitudeScale
      let segmentY = (end.latitude - start.latitude) * latitudeScale
      let pointX = (point.longitude - start.longitude) * longitudeScale
      let pointY = (point.latitude - start.latitude) * latitudeScale
      let squared = segmentX * segmentX + segmentY * segmentY
      let fraction =
        squared > 0
        ? min(1, max(0, (pointX * segmentX + pointY * segmentY) / squared)) : 0
      return hypot(pointX - segmentX * fraction, pointY - segmentY * fraction)
    }.min() ?? .infinity
  }
#endif
