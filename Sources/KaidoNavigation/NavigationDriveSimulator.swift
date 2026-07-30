import Foundation
import KaidoDomain
import KaidoRouting

/// Playback is deterministic: speed changes only the wall-clock delay used by
/// an adapter and never changes observation timestamps or matcher input.
public enum NavigationDriveSimulationSpeed: Int, CaseIterable, Sendable {
  case realtime = 1
  case fiveTimes = 5
  case twentyTimes = 20

  public var multiplier: Int {
    rawValue
  }
}

public enum NavigationDriveSimulationState: String, Equatable, Sendable {
  case ready = "READY"
  case playing = "PLAYING"
  case paused = "PAUSED"
  case completed = "COMPLETED"
}

public enum NavigationDriveSimulationTiming: String, Equatable, Sendable {
  case fixedObservationInterval = "FIXED_OBSERVATION_INTERVAL"
  case routeSpeed = "ROUTE_SPEED"
}

public enum NavigationDriveSimulationEvidenceScope: String, Equatable, Sendable {
  case syntheticTestOnly = "SYNTHETIC_TEST_ONLY"
}

public enum NavigationDriveSimulationError: Error, Equatable, Sendable {
  case invalidConfiguration([String])
  case invalidTrace([String])
}

public enum NavigationDriveSimulationAnomalyKind: Equatable, Sendable {
  case horizontalAccuracyMeters(Double)
  case coordinateOffsetMeters(north: Double, east: Double)
  case receptionDelayMilliseconds(Int)
  case signalGapBeforeMilliseconds(Int)
}

/// Targets one distinct RoutePlan occurrence and one generated sample.
///
/// Repeated traversals of the same directed edge remain independently
/// addressable because the target is an occurrence ID, not an edge ID.
public struct NavigationDriveSimulationAnomaly: Equatable, Sendable {
  public let occurrenceID: String
  public let sampleIndex: Int
  public let kind: NavigationDriveSimulationAnomalyKind

  public init(
    occurrenceID: String,
    sampleIndex: Int,
    kind: NavigationDriveSimulationAnomalyKind
  ) {
    self.occurrenceID = occurrenceID
    self.sampleIndex = sampleIndex
    self.kind = kind
  }
}

public enum NavigationDriveSimulationNoiseGenerator {
  /// Produces a repeatable eight-direction coordinate drift around route truth.
  ///
  /// The pattern is deterministic so matcher changes can be compared without
  /// random seeds or hidden fixture state.
  public static func radialCoordinateDrift(
    sampleTruth: [NavigationDriveSimulationSampleTruth],
    magnitudeMeters: Double
  ) throws -> [NavigationDriveSimulationAnomaly] {
    guard magnitudeMeters.isFinite, magnitudeMeters > 0 else {
      throw NavigationDriveSimulationError.invalidConfiguration([
        "simulation coordinate drift magnitude is invalid"
      ])
    }
    let diagonal = magnitudeMeters / sqrt(2)
    let offsets = [
      (north: 0.0, east: magnitudeMeters),
      (north: diagonal, east: diagonal),
      (north: magnitudeMeters, east: 0.0),
      (north: diagonal, east: -diagonal),
      (north: 0.0, east: -magnitudeMeters),
      (north: -diagonal, east: -diagonal),
      (north: -magnitudeMeters, east: 0.0),
      (north: -diagonal, east: diagonal),
    ]
    return sampleTruth.enumerated().map { index, truth in
      let offset = offsets[index % offsets.count]
      return NavigationDriveSimulationAnomaly(
        occurrenceID: truth.occurrenceID,
        sampleIndex: truth.sampleIndex,
        kind: .coordinateOffsetMeters(
          north: offset.north,
          east: offset.east
        )
      )
    }
  }
}

public struct NavigationDriveSimulationConfiguration: Equatable, Sendable {
  public let startedAtMilliseconds: Int
  public let observationIntervalMilliseconds: Int
  public let sampleFractions: [Double]
  public let maximumSampleSpacingMeters: Double?
  public let timing: NavigationDriveSimulationTiming
  public let horizontalAccuracyMeters: Double
  public let speedMetersPerSecond: Double
  public let source: MatcherLocationSource
  public let anomalies: [NavigationDriveSimulationAnomaly]
  public let completesAtExitHandoff: Bool

  public init(
    startedAtMilliseconds: Int = 1_000,
    observationIntervalMilliseconds: Int = 1_000,
    sampleFractions: [Double] = [0.15, 0.5, 0.85],
    maximumSampleSpacingMeters: Double? = nil,
    timing: NavigationDriveSimulationTiming = .fixedObservationInterval,
    horizontalAccuracyMeters: Double = 3,
    speedMetersPerSecond: Double = 15,
    source: MatcherLocationSource = .phone,
    anomalies: [NavigationDriveSimulationAnomaly] = [],
    completesAtExitHandoff: Bool = false
  ) {
    self.startedAtMilliseconds = startedAtMilliseconds
    self.observationIntervalMilliseconds = observationIntervalMilliseconds
    self.sampleFractions = sampleFractions
    self.maximumSampleSpacingMeters = maximumSampleSpacingMeters
    self.timing = timing
    self.horizontalAccuracyMeters = horizontalAccuracyMeters
    self.speedMetersPerSecond = speedMetersPerSecond
    self.source = source
    self.anomalies = anomalies
    self.completesAtExitHandoff = completesAtExitHandoff
  }
}

public enum NavigationDriveSimulationAction: Equatable, Sendable {
  case matcherObservation(RouteMatcherObservation)
  case enterTunnel
  case exitTunnel
  case connectCarPlay
  case disconnectCarPlay
  case finishDrive
  case completeAtExitHandoff
}

public struct NavigationDriveSimulationEvent: Equatable, Sendable {
  public let id: String
  public let atMilliseconds: Int
  public let action: NavigationDriveSimulationAction

  public init(
    id: String,
    atMilliseconds: Int,
    action: NavigationDriveSimulationAction
  ) {
    self.id = id
    self.atMilliseconds = atMilliseconds
    self.action = action
  }
}

/// Exact route-owned truth for one generated matcher observation.
///
/// Coordinate anomalies change only the observation. This record retains the
/// selected RoutePlan occurrence and along-route position so deterministic
/// accuracy evaluation can distinguish a plausible-looking replay from a
/// correct matcher result.
public struct NavigationDriveSimulationSampleTruth: Equatable, Sendable {
  public let observationID: String
  public let occurrenceID: String
  public let occurrenceIndex: Int
  public let directedEdgeID: String
  public let sampleIndex: Int
  public let fractionAlongOccurrence: Double
  public let routeDistanceMeters: Double

  public init(
    observationID: String,
    occurrenceID: String,
    occurrenceIndex: Int,
    directedEdgeID: String,
    sampleIndex: Int,
    fractionAlongOccurrence: Double,
    routeDistanceMeters: Double
  ) {
    self.observationID = observationID
    self.occurrenceID = occurrenceID
    self.occurrenceIndex = occurrenceIndex
    self.directedEdgeID = directedEdgeID
    self.sampleIndex = sampleIndex
    self.fractionAlongOccurrence = fractionAlongOccurrence
    self.routeDistanceMeters = routeDistanceMeters
  }
}

public struct NavigationDriveSimulationTrace: Equatable, Sendable {
  public let routePlanID: String
  public let matcherCorridorID: String
  public let events: [NavigationDriveSimulationEvent]
  public let sampleTruth: [NavigationDriveSimulationSampleTruth]

  public init(
    routePlanID: String,
    matcherCorridorID: String,
    events: [NavigationDriveSimulationEvent],
    sampleTruth: [NavigationDriveSimulationSampleTruth]
  ) {
    self.routePlanID = routePlanID
    self.matcherCorridorID = matcherCorridorID
    self.events = events
    self.sampleTruth = sampleTruth
  }

  public var evidenceScope: NavigationDriveSimulationEvidenceScope {
    .syntheticTestOnly
  }

  public var grantsNavigationAuthority: Bool {
    false
  }
}

public enum NavigationDriveSimulationTraceGenerator {
  private static let maximumGeneratedSamplesPerOccurrence = 100_000

  public static func generate(
    routePlan: RoutePlan,
    corridor: RouteMatcherCorridor,
    egressOptions: [EgressOption] = [],
    configuration: NavigationDriveSimulationConfiguration = .init()
  ) throws -> NavigationDriveSimulationTrace {
    let issues = validationIssues(
      routePlan: routePlan,
      corridor: corridor,
      egressOptions: egressOptions,
      configuration: configuration
    )
    guard issues.isEmpty else {
      throw NavigationDriveSimulationError.invalidConfiguration(issues)
    }

    let edges = Dictionary(uniqueKeysWithValues: corridor.edges.map { ($0.id, $0) })
    let anomalies = Dictionary(
      grouping: configuration.anomalies,
      by: { SimulationSampleKey($0.occurrenceID, $0.sampleIndex) }
    )
    var events: [NavigationDriveSimulationEvent] = []
    var sampleTruth: [NavigationDriveSimulationSampleTruth] = []
    var observedAt = configuration.startedAtMilliseconds
    var lastReceivedAt = configuration.startedAtMilliseconds
    var distanceBeforeOccurrenceMeters = 0.0
    var previousSampleDistanceMeters: Double?
    let finishOccurrenceIndex =
      configuration.completesAtExitHandoff
      ? egressOptions.compactMap {
        routePlan.occurrence(id: $0.firstEligibleOccurrenceID)?.index
      }.min()
      : nil

    for occurrence in corridor.occurrences.sorted(by: { $0.index < $1.index }) {
      guard let edge = edges[occurrence.directedEdgeID] else { continue }
      let edgeLengthMeters = distance(along: edge.coordinates)
      let sampleFractions = sampleFractions(
        along: edge.coordinates,
        configuration: configuration
      )
      if occurrence.index == finishOccurrenceIndex {
        events.append(
          NavigationDriveSimulationEvent(
            id: "simulation.finish-drive",
            atMilliseconds: observedAt,
            action: .finishDrive
          )
        )
        observedAt += configuration.observationIntervalMilliseconds
      }
      for (sampleIndex, fraction) in sampleFractions.enumerated() {
        let sampleDistanceMeters =
          distanceBeforeOccurrenceMeters + edgeLengthMeters * fraction
        if configuration.timing == .routeSpeed,
          let previousSampleDistanceMeters
        {
          let travelMilliseconds =
            (sampleDistanceMeters - previousSampleDistanceMeters)
            / configuration.speedMetersPerSecond * 1_000
          observedAt += max(1, Int(travelMilliseconds.rounded()))
        }
        let sampleKey = SimulationSampleKey(occurrence.id, sampleIndex)
        let sampleAnomalies = anomalies[sampleKey] ?? []
        let gap = sampleAnomalies.reduce(0) { partial, anomaly in
          guard case .signalGapBeforeMilliseconds(let value) = anomaly.kind else {
            return partial
          }
          return partial + value
        }
        observedAt += gap

        var sample = coordinate(
          along: edge.coordinates,
          fraction: fraction
        )
        var accuracy = configuration.horizontalAccuracyMeters
        var receptionDelay = 0
        for anomaly in sampleAnomalies {
          switch anomaly.kind {
          case .horizontalAccuracyMeters(let value):
            accuracy = value
          case .coordinateOffsetMeters(let north, let east):
            sample.coordinate = offset(
              sample.coordinate,
              northMeters: north,
              eastMeters: east
            )
          case .receptionDelayMilliseconds(let value):
            receptionDelay += value
          case .signalGapBeforeMilliseconds:
            break
          }
        }
        let receivedAt = max(lastReceivedAt, observedAt + receptionDelay)
        let observationID = "simulation.\(occurrence.index).\(sampleIndex)"
        sampleTruth.append(
          NavigationDriveSimulationSampleTruth(
            observationID: observationID,
            occurrenceID: occurrence.id,
            occurrenceIndex: occurrence.index,
            directedEdgeID: occurrence.directedEdgeID,
            sampleIndex: sampleIndex,
            fractionAlongOccurrence: fraction,
            routeDistanceMeters: sampleDistanceMeters
          )
        )
        let observation = RouteMatcherObservation(
          id: observationID,
          observedAtMilliseconds: observedAt,
          receivedAtMilliseconds: receivedAt,
          coordinate: sample.coordinate,
          horizontalAccuracyMeters: accuracy,
          courseDegrees: sample.bearingDegrees,
          speedMetersPerSecond: configuration.speedMetersPerSecond,
          source: configuration.source
        )
        events.append(
          NavigationDriveSimulationEvent(
            id: observationID,
            atMilliseconds: observedAt,
            action: .matcherObservation(observation)
          )
        )
        lastReceivedAt = receivedAt
        previousSampleDistanceMeters = sampleDistanceMeters
        if configuration.timing == .fixedObservationInterval {
          observedAt += configuration.observationIntervalMilliseconds
        }
      }
      distanceBeforeOccurrenceMeters += edgeLengthMeters
    }

    if configuration.completesAtExitHandoff {
      events.append(
        NavigationDriveSimulationEvent(
          id: "simulation.complete-exit-handoff",
          atMilliseconds: observedAt,
          action: .completeAtExitHandoff
        )
      )
    }

    return NavigationDriveSimulationTrace(
      routePlanID: routePlan.id,
      matcherCorridorID: corridor.id,
      events: events,
      sampleTruth: sampleTruth
    )
  }

  private static func validationIssues(
    routePlan: RoutePlan,
    corridor: RouteMatcherCorridor,
    egressOptions: [EgressOption],
    configuration: NavigationDriveSimulationConfiguration
  ) -> [String] {
    var issues: [String] = []
    let edgesByID = Dictionary(
      corridor.edges.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    if corridor.routePlanID != routePlan.id {
      issues.append("matcher corridor RoutePlan ID does not match")
    }
    if corridor.networkSnapshotID != routePlan.networkSnapshotID {
      issues.append("matcher corridor network snapshot ID does not match")
    }
    if corridor.occurrences.map(\.id) != routePlan.occurrences.map(\.id) {
      issues.append("matcher corridor occurrence order does not match RoutePlan")
    }
    issues.append(contentsOf: corridor.validationIssues)
    if configuration.startedAtMilliseconds < 0 {
      issues.append("simulation start time is negative")
    }
    if configuration.observationIntervalMilliseconds <= 0 {
      issues.append("simulation observation interval is not positive")
    }
    if configuration.sampleFractions.count < 2
      || configuration.sampleFractions.contains(where: {
        !$0.isFinite || $0 <= 0 || $0 >= 1
      })
      || zip(
        configuration.sampleFractions,
        configuration.sampleFractions.dropFirst()
      ).contains(where: { $0 >= $1 })
    {
      issues.append("simulation sample fractions are invalid")
    }
    if let maximumSampleSpacingMeters =
      configuration.maximumSampleSpacingMeters,
      !maximumSampleSpacingMeters.isFinite
        || maximumSampleSpacingMeters <= 0
    {
      issues.append("simulation maximum sample spacing is invalid")
    }
    if let maximumSampleSpacingMeters =
      configuration.maximumSampleSpacingMeters,
      maximumSampleSpacingMeters.isFinite,
      maximumSampleSpacingMeters > 0,
      corridor.edges.contains(where: {
        ceil(distance(along: $0.coordinates) / maximumSampleSpacingMeters)
          > Double(maximumGeneratedSamplesPerOccurrence)
      })
    {
      issues.append("simulation maximum sample spacing creates excessive samples")
    }
    if !configuration.horizontalAccuracyMeters.isFinite
      || configuration.horizontalAccuracyMeters <= 0
    {
      issues.append("simulation horizontal accuracy is invalid")
    }
    if !configuration.speedMetersPerSecond.isFinite
      || configuration.speedMetersPerSecond < 0
    {
      issues.append("simulation speed is invalid")
    }
    if configuration.timing == .routeSpeed,
      configuration.speedMetersPerSecond <= 0
    {
      issues.append("route-speed simulation requires positive speed")
    }
    if configuration.timing == .routeSpeed,
      configuration.speedMetersPerSecond > 0
    {
      let routeDistanceMeters = corridor.occurrences.reduce(0.0) {
        partial, occurrence in
        partial
          + (edgesByID[occurrence.directedEdgeID].map {
            distance(along: $0.coordinates)
          } ?? 0)
      }
      let traceDurationMilliseconds =
        routeDistanceMeters / configuration.speedMetersPerSecond * 1_000
      if !traceDurationMilliseconds.isFinite
        || traceDurationMilliseconds
          > Double(Int.max)
          - Double(max(0, configuration.startedAtMilliseconds))
      {
        issues.append("route-speed simulation duration is invalid")
      }
    }
    if configuration.completesAtExitHandoff,
      !egressOptions.contains(where: {
        $0.isReleased
          && $0.exitFacilityID == routePlan.exitFacilityID
          && routePlan.occurrence(id: $0.firstEligibleOccurrenceID) != nil
      })
    {
      issues.append("simulation released egress option is missing")
    }

    let occurrenceIDs = Set(corridor.occurrences.map(\.id))
    let occurrencesByID = Dictionary(
      corridor.occurrences.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    for anomaly in configuration.anomalies {
      if !occurrenceIDs.contains(anomaly.occurrenceID) {
        issues.append("simulation anomaly occurrence is unknown")
      }
      let generatedFractions =
        occurrencesByID[anomaly.occurrenceID]
        .flatMap { edgesByID[$0.directedEdgeID] }
        .map {
          sampleFractions(
            along: $0.coordinates,
            configuration: configuration
          )
        } ?? []
      if !generatedFractions.indices.contains(anomaly.sampleIndex) {
        issues.append("simulation anomaly sample index is invalid")
      }
      switch anomaly.kind {
      case .horizontalAccuracyMeters(let value):
        if !value.isFinite || value <= 0 {
          issues.append("simulation anomaly accuracy is invalid")
        }
      case .coordinateOffsetMeters(let north, let east):
        if !north.isFinite || !east.isFinite {
          issues.append("simulation anomaly coordinate offset is invalid")
        }
      case .receptionDelayMilliseconds(let value),
        .signalGapBeforeMilliseconds(let value):
        if value < 0 {
          issues.append("simulation anomaly time is negative")
        }
      }
    }
    return Array(Set(issues)).sorted()
  }

  private static func sampleFractions(
    along coordinates: [MatcherCoordinate],
    configuration: NavigationDriveSimulationConfiguration
  ) -> [Double] {
    guard
      let maximumSpacing =
        configuration.maximumSampleSpacingMeters,
      maximumSpacing.isFinite,
      maximumSpacing > 0
    else {
      return configuration.sampleFractions
    }
    let edgeLength = distance(along: coordinates)
    let requestedSampleCount = ceil(edgeLength / maximumSpacing)
    guard requestedSampleCount.isFinite,
      requestedSampleCount
        <= Double(maximumGeneratedSamplesPerOccurrence)
    else {
      return configuration.sampleFractions
    }
    let sampleCount = max(1, Int(requestedSampleCount))
    let evenlySpacedFractions =
      (0..<sampleCount).map {
        (Double($0) + 0.5) / Double(sampleCount)
      }
    return Array(
      Set(configuration.sampleFractions + evenlySpacedFractions)
    ).sorted()
  }

  private static func distance(
    along coordinates: [MatcherCoordinate]
  ) -> Double {
    zip(coordinates, coordinates.dropFirst()).reduce(0) {
      $0 + matcherCoordinateDistanceMeters($1.0, $1.1)
    }
  }

  private static func coordinate(
    along coordinates: [MatcherCoordinate],
    fraction: Double
  ) -> SimulationCoordinateSample {
    let segments = zip(coordinates, coordinates.dropFirst()).map {
      (
        start: $0,
        end: $1,
        length: matcherCoordinateDistanceMeters($0, $1)
      )
    }
    let totalLength = segments.reduce(0) { $0 + $1.length }
    var target = totalLength * fraction
    for (index, segment) in segments.enumerated() {
      if target <= segment.length || index == segments.count - 1 {
        let segmentFraction =
          segment.length > 0 ? min(1, max(0, target / segment.length)) : 0
        return SimulationCoordinateSample(
          coordinate: MatcherCoordinate(
            latitude: segment.start.latitude
              + (segment.end.latitude - segment.start.latitude) * segmentFraction,
            longitude: segment.start.longitude
              + (segment.end.longitude - segment.start.longitude) * segmentFraction
          ),
          bearingDegrees: bearing(
            from: segment.start,
            to: segment.end
          )
        )
      }
      target -= segment.length
    }
    return SimulationCoordinateSample(
      coordinate: coordinates.last!,
      bearingDegrees: bearing(
        from: coordinates[coordinates.count - 2],
        to: coordinates.last!
      )
    )
  }

  private static func bearing(
    from start: MatcherCoordinate,
    to end: MatcherCoordinate
  ) -> Double {
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

  private static func offset(
    _ coordinate: MatcherCoordinate,
    northMeters: Double,
    eastMeters: Double
  ) -> MatcherCoordinate {
    let earthRadiusMeters = 6_371_000.0
    let latitudeRadians = coordinate.latitude * .pi / 180
    let latitudeDelta = northMeters / earthRadiusMeters
    let longitudeDelta =
      eastMeters / max(1, earthRadiusMeters * cos(latitudeRadians))
    return MatcherCoordinate(
      latitude: coordinate.latitude + latitudeDelta * 180 / .pi,
      longitude: coordinate.longitude + longitudeDelta * 180 / .pi
    )
  }
}

public struct NavigationDriveSimulationStatus: Equatable, Sendable {
  public let state: NavigationDriveSimulationState
  public let speed: NavigationDriveSimulationSpeed
  public let completedEventCount: Int
  public let totalEventCount: Int
  public let lastEventID: String?

  public var progress: Double {
    guard totalEventCount > 0 else { return 0 }
    return Double(completedEventCount) / Double(totalEventCount)
  }

  public var evidenceScope: NavigationDriveSimulationEvidenceScope {
    .syntheticTestOnly
  }

  public var grantsNavigationAuthority: Bool {
    false
  }
}

public struct NavigationDriveSimulationStepResult: Equatable, Sendable {
  public let event: NavigationDriveSimulationEvent
  public let eventIndex: Int
  public let navigationSnapshot: NavigationSnapshot
  public let navigationUpdate: NavigationSessionUpdate?
  public let status: NavigationDriveSimulationStatus
}

/// A synthetic-only controller around the real route matcher and
/// `NavigationSession` reducer.
///
/// A selected whole-Shuto route exercises the actor's ordered entry reducer
/// through a package-only synthetic path before strict-route matching begins.
/// It never manufactures release-bound entrance evidence. Its output is
/// deterministic test evidence and never field, road, traffic, or release
/// authority.
public actor NavigationDriveSimulator {
  public nonisolated let evidenceScope: NavigationDriveSimulationEvidenceScope = .syntheticTestOnly
  public let releaseID: String
  public let routePlanID: String
  public let matcherCorridorID: String
  public let trace: NavigationDriveSimulationTrace

  public nonisolated var grantsNavigationAuthority: Bool {
    false
  }

  private let runtime: NavigationDriveSimulationRuntime
  private var session: NavigationSession
  private var eventIndex = 0
  private var state: NavigationDriveSimulationState = .ready
  private var speed: NavigationDriveSimulationSpeed
  private var lastEventID: String?
  private var sessionStarted = false

  public init(
    release: KaidoProductRelease,
    configuration: NavigationDriveSimulationConfiguration = .init(),
    speed: NavigationDriveSimulationSpeed = .fiveTimes
  ) throws {
    let runtime = NavigationDriveSimulationRuntime(release: release)
    let trace = try NavigationDriveSimulationTraceGenerator.generate(
      routePlan: runtime.routePlan,
      corridor: runtime.matcherCorridor,
      egressOptions: runtime.egressOptions,
      configuration: configuration
    )
    try self.init(runtime: runtime, trace: trace, speed: speed)
  }

  public init(
    release: KaidoProductRelease,
    trace: NavigationDriveSimulationTrace,
    speed: NavigationDriveSimulationSpeed = .fiveTimes
  ) throws {
    try self.init(
      runtime: NavigationDriveSimulationRuntime(release: release),
      trace: trace,
      speed: speed
    )
  }

  /// Runs a selected whole-Shuto route through the real matcher and actor
  /// reducer without manufacturing released-road or live-location authority.
  public init(
    route: ShutoPlannedRoute,
    runtimeAssets: ShutoPlannedRouteRuntimeAssets,
    configuration: NavigationDriveSimulationConfiguration = .init(),
    speed: NavigationDriveSimulationSpeed = .fiveTimes
  ) throws {
    let runtime = try NavigationDriveSimulationRuntime(
      route: route,
      runtimeAssets: runtimeAssets
    )
    let trace = try NavigationDriveSimulationTraceGenerator.generate(
      routePlan: runtime.routePlan,
      corridor: runtime.matcherCorridor,
      configuration: configuration
    )
    try self.init(runtime: runtime, trace: trace, speed: speed)
  }

  private init(
    runtime: NavigationDriveSimulationRuntime,
    trace: NavigationDriveSimulationTrace,
    speed: NavigationDriveSimulationSpeed
  ) throws {
    var issues: [String] = []
    if trace.routePlanID != runtime.routePlan.id {
      issues.append("simulation trace RoutePlan ID does not match release")
    }
    if trace.matcherCorridorID != runtime.matcherCorridor.id {
      issues.append("simulation trace matcher corridor ID does not match release")
    }
    if trace.events.isEmpty {
      issues.append("simulation trace is empty")
    }
    let eventIDs = trace.events.map(\.id)
    if Set(eventIDs).count != eventIDs.count
      || eventIDs.contains(where: {
        $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      })
    {
      issues.append("simulation event IDs are invalid")
    }
    if trace.events.contains(where: { $0.atMilliseconds < 0 })
      || zip(trace.events, trace.events.dropFirst()).contains(where: {
        $0.atMilliseconds > $1.atMilliseconds
      })
    {
      issues.append("simulation event times are invalid")
    }
    guard issues.isEmpty else {
      throw NavigationDriveSimulationError.invalidTrace(issues.sorted())
    }

    self.runtime = runtime
    self.trace = trace
    self.speed = speed
    releaseID = runtime.runtimeID
    routePlanID = trace.routePlanID
    matcherCorridorID = trace.matcherCorridorID
    session = try Self.makeSession(runtime: runtime)
  }

  public var status: NavigationDriveSimulationStatus {
    currentStatus
  }

  public var navigationSnapshot: NavigationSnapshot {
    get async {
      await session.snapshot
    }
  }

  public func setSpeed(
    _ speed: NavigationDriveSimulationSpeed
  ) -> NavigationDriveSimulationStatus {
    self.speed = speed
    return currentStatus
  }

  public func play() -> NavigationDriveSimulationStatus {
    guard state != .completed else { return currentStatus }
    state = .playing
    return currentStatus
  }

  public func pause() -> NavigationDriveSimulationStatus {
    guard state != .completed else { return currentStatus }
    state = .paused
    return currentStatus
  }

  public func step() async throws -> NavigationDriveSimulationStepResult? {
    guard state != .completed else { return nil }
    state = .paused
    return try await processNextEvent()
  }

  public func advanceIfPlaying() async throws
    -> NavigationDriveSimulationStepResult?
  {
    guard state == .playing else { return nil }
    return try await processNextEvent()
  }

  public func runToEnd() async throws -> [NavigationDriveSimulationStepResult] {
    guard state != .completed else { return [] }
    state = .playing
    var results: [NavigationDriveSimulationStepResult] = []
    while state == .playing {
      guard let result = try await processNextEvent() else { break }
      results.append(result)
    }
    return results
  }

  public func reset() async throws -> NavigationDriveSimulationStatus {
    session = try Self.makeSession(runtime: runtime)
    eventIndex = 0
    state = .ready
    lastEventID = nil
    sessionStarted = false
    _ = await startSessionIfNeeded()
    return currentStatus
  }

  /// Restores only coordinate-free route occurrence identity.
  ///
  /// Matcher posterior is intentionally discarded. Playback resumes at the
  /// first observation for the restored occurrence, which must reacquire a
  /// HIGH estimate before callers admit new progress.
  public func restore(
    at occurrenceID: String
  ) async throws -> NavigationDriveSimulationStatus {
    guard
      let occurrence = runtime.routePlan.occurrence(id: occurrenceID),
      let firstEventIndex = trace.events.firstIndex(where: {
        $0.id.hasPrefix("simulation.\(occurrence.index).")
      })
    else {
      throw NavigationDriveSimulationError.invalidTrace([
        "restored simulation occurrence is unavailable"
      ])
    }
    session = try Self.makeSession(
      runtime: runtime,
      initialOccurrenceID: occurrenceID
    )
    eventIndex = firstEventIndex
    state = .paused
    lastEventID = nil
    sessionStarted = false
    _ = await startSessionIfNeeded()
    return currentStatus
  }

  public func delayBeforeNextEventMilliseconds() -> Int? {
    guard eventIndex < trace.events.count else { return nil }
    let previousTime =
      eventIndex == 0
      ? trace.events[0].atMilliseconds
      : trace.events[eventIndex - 1].atMilliseconds
    let delta = max(
      0,
      trace.events[eventIndex].atMilliseconds - previousTime
    )
    return delta / speed.multiplier
  }

  private var currentStatus: NavigationDriveSimulationStatus {
    NavigationDriveSimulationStatus(
      state: state,
      speed: speed,
      completedEventCount: eventIndex,
      totalEventCount: trace.events.count,
      lastEventID: lastEventID
    )
  }

  private func processNextEvent() async throws
    -> NavigationDriveSimulationStepResult?
  {
    guard eventIndex < trace.events.count else {
      state = .completed
      return nil
    }
    _ = await startSessionIfNeeded()
    let currentIndex = eventIndex
    let event = trace.events[currentIndex]
    let update: NavigationSessionUpdate?
    let snapshot: NavigationSnapshot
    switch event.action {
    case .matcherObservation(let observation):
      let sessionSnapshot = await session.snapshot
      let usesSyntheticEntryTransition =
        runtime.syntheticEntryTransition != nil
        && (sessionSnapshot.journeyPhase == .planning
          || sessionSnapshot.journeyPhase == .approachToEntry
          || sessionSnapshot.journeyPhase == .entryTransition)
      let result =
        usesSyntheticEntryTransition
        ? try await session
          .observeSyntheticSimulationEntryTransition(observation)
        : try await session.observe(observation)
      update = result
      snapshot = result.navigationSnapshot
    case .enterTunnel:
      update = nil
      snapshot = await session.enterTunnel()
    case .exitTunnel:
      update = nil
      snapshot = await session.exitTunnel()
    case .connectCarPlay:
      update = nil
      snapshot = await session.connectCarPlay()
    case .disconnectCarPlay:
      update = nil
      snapshot = await session.disconnectCarPlay()
    case .finishDrive:
      update = nil
      snapshot = await session.finishDrive()
    case .completeAtExitHandoff:
      update = nil
      snapshot = await session.completeAtExitHandoff()
    }
    eventIndex += 1
    lastEventID = event.id
    if eventIndex == trace.events.count {
      state = .completed
    }
    return NavigationDriveSimulationStepResult(
      event: event,
      eventIndex: currentIndex,
      navigationSnapshot: snapshot,
      navigationUpdate: update,
      status: currentStatus
    )
  }

  @discardableResult
  private func startSessionIfNeeded() async -> NavigationSnapshot {
    guard !sessionStarted else { return await session.snapshot }
    sessionStarted = true
    return await session.start()
  }

  private static func makeSession(
    runtime: NavigationDriveSimulationRuntime,
    initialOccurrenceID: String? = nil
  ) throws -> NavigationSession {
    let firstOccurrenceID = runtime.routePlan.occurrences.first?.id
    let initialSnapshot: NavigationSnapshot
    let initialMatcherOccurrenceID: String?
    if let initialOccurrenceID {
      var restored = NavigationSnapshot(
        journeyPhase: .strictRoute,
        activeRoutePlanID: runtime.routePlan.id,
        currentOccurrenceID: initialOccurrenceID,
        locationConfidence: .low
      )
      restored.lastPhaseTransitionTrigger =
        "SYNTHETIC_SIMULATION_STRICT_ROUTE_RESTORE"
      initialSnapshot = restored
      initialMatcherOccurrenceID = initialOccurrenceID
    } else if runtime.syntheticEntryTransition != nil {
      var pendingEntry = NavigationSnapshot(
        journeyPhase: .planning,
        activeRoutePlanID: runtime.routePlan.id,
        locationConfidence: .low
      )
      pendingEntry.lastPhaseTransitionTrigger =
        "SYNTHETIC_SIMULATION_ENTRY_PENDING"
      initialSnapshot = pendingEntry
      initialMatcherOccurrenceID = nil
    } else {
      var seeded = NavigationSnapshot(
        journeyPhase: .strictRoute,
        activeRoutePlanID: runtime.routePlan.id,
        currentOccurrenceID: firstOccurrenceID,
        locationConfidence: .low
      )
      seeded.lastPhaseTransitionTrigger =
        "SYNTHETIC_SIMULATION_STRICT_ROUTE_SEED"
      initialSnapshot = seeded
      initialMatcherOccurrenceID = firstOccurrenceID
    }
    return try NavigationSession(
      navigationConfiguration: NavigationConfiguration(
        routePlan: runtime.routePlan,
        entryTransition: runtime.syntheticEntryTransition,
        recoveryCandidates: runtime.recoveryCandidates,
        egressOptions: runtime.egressOptions,
        releasedGuidance: runtime.releasedGuidance,
        allowsUserConfirmedExitHandoffCompletion: true
      ),
      matcherCorridor: runtime.matcherCorridor,
      decisionZones: runtime.decisionZones,
      initialNavigationSnapshot: initialSnapshot,
      initialMatcherOccurrenceID: initialMatcherOccurrenceID
    )
  }
}

private struct NavigationDriveSimulationRuntime: Sendable {
  let runtimeID: String
  let routePlan: RoutePlan
  let matcherCorridor: RouteMatcherCorridor
  let recoveryCandidates: [RecoveryCandidate]
  let egressOptions: [EgressOption]
  let decisionZones: [DecisionZoneProgressDefinition]
  let releasedGuidance: [ReleasedGuidanceDefinition]
  let syntheticEntryTransition: EntryTransition?

  init(release: KaidoProductRelease) {
    let bundle = release.navigation.bundle
    runtimeID = release.releaseID
    routePlan = bundle.routePlan
    matcherCorridor = bundle.matcherCorridor
    recoveryCandidates = bundle.runtimePolicy.recoveryCandidates
    egressOptions = bundle.runtimePolicy.egressOptions
    decisionZones = bundle.decisionZones
    releasedGuidance = bundle.releasedGuidance
    syntheticEntryTransition = nil
  }

  init(
    route: ShutoPlannedRoute,
    runtimeAssets: ShutoPlannedRouteRuntimeAssets
  ) throws {
    guard route.edges.count >= 2,
      route.routePlan.occurrences.count >= 2,
      route.edges[0].edgeID != route.edges[1].edgeID
    else {
      throw NavigationDriveSimulationError.invalidConfiguration([
        "whole-Shuto simulation entry requires two distinct ordered route edges"
      ])
    }
    guard runtimeAssets.routePlan == route.routePlan else {
      throw NavigationDriveSimulationError.invalidConfiguration([
        "whole-Shuto runtime assets do not match the selected route"
      ])
    }
    runtimeID = "synthetic.\(route.routePlan.id)"
    routePlan = route.routePlan
    matcherCorridor = runtimeAssets.matcherCorridor
    recoveryCandidates = []
    egressOptions = []
    decisionZones = runtimeAssets.decisionZones
    releasedGuidance = runtimeAssets.releasedGuidance
    syntheticEntryTransition = EntryTransition(
      facilityID: route.entryFacility.facilityID,
      directedEdgeIDs: [
        route.edges[0].edgeID,
        route.edges[1].edgeID,
      ],
      firstRouteOccurrenceID:
        route.routePlan.occurrences[1].id
    )
  }
}

private struct SimulationSampleKey: Hashable {
  let occurrenceID: String
  let sampleIndex: Int

  init(_ occurrenceID: String, _ sampleIndex: Int) {
    self.occurrenceID = occurrenceID
    self.sampleIndex = sampleIndex
  }
}

private struct SimulationCoordinateSample {
  var coordinate: MatcherCoordinate
  let bearingDegrees: Double
}
