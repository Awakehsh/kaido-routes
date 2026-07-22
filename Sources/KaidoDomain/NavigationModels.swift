import Foundation

public enum JourneyPhase: String, Codable, Sendable {
  case planning = "PLANNING"
  case approachToEntry = "APPROACH_TO_ENTRY"
  case entryTransition = "ENTRY_TRANSITION"
  case strictRoute = "STRICT_ROUTE"
  case routeRecovery = "ROUTE_RECOVERY"
  case exitTransition = "EXIT_TRANSITION"
  case surfaceEgress = "SURFACE_EGRESS"
  case completed = "COMPLETED"
}

public enum LocationConfidence: String, Codable, Comparable, Sendable {
  case lost = "LOST"
  case low = "LOW"
  case medium = "MEDIUM"
  case high = "HIGH"

  private var rank: Int {
    switch self {
    case .lost: 0
    case .low: 1
    case .medium: 2
    case .high: 3
    }
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rank < rhs.rank
  }
}

public enum SignalReacquisitionStatus: String, Codable, Sendable {
  case inactive = "INACTIVE"
  case pending = "PENDING"
  case confirmed = "CONFIRMED"
}

public enum RouteCandidateResolution: String, Codable, Sendable {
  case unknown = "UNKNOWN"
  case ambiguous = "AMBIGUOUS"
  case resolved = "RESOLVED"
}

public struct EntryTransition: Equatable, Sendable {
  public let facilityID: String
  public let directedEdgeIDs: [String]
  public let firstRouteOccurrenceID: String?

  public init(
    facilityID: String,
    directedEdgeIDs: [String],
    firstRouteOccurrenceID: String? = nil
  ) {
    self.facilityID = facilityID
    self.directedEdgeIDs = directedEdgeIDs
    self.firstRouteOccurrenceID = firstRouteOccurrenceID
  }
}

public struct LocationObservation: Equatable, Sendable {
  public let directedEdgeID: String?
  public let matchedEntityID: String?
  public let expectedOccurrenceID: String?
  public let matchedOccurrenceID: String?
  public let candidateOccurrenceIDs: Set<String>
  public let candidateResolution: RouteCandidateResolution
  public let projectedOccurrenceID: String?
  public let observedAtMilliseconds: Int?
  public let reportedConfidence: LocationConfidence?
  public let horizontalAccuracyMeters: Double?
  public let ageMilliseconds: Int?
  public let headingMatches: Bool?
  public let forwardContinuity: Bool
  public let reachableOccurrenceIDs: Set<String>
  public let insideEntryRegion: Bool

  public init(
    directedEdgeID: String? = nil,
    matchedEntityID: String? = nil,
    expectedOccurrenceID: String? = nil,
    matchedOccurrenceID: String? = nil,
    candidateOccurrenceIDs: Set<String> = [],
    candidateResolution: RouteCandidateResolution = .unknown,
    projectedOccurrenceID: String? = nil,
    observedAtMilliseconds: Int? = nil,
    reportedConfidence: LocationConfidence? = nil,
    horizontalAccuracyMeters: Double? = nil,
    ageMilliseconds: Int? = nil,
    headingMatches: Bool? = nil,
    forwardContinuity: Bool = false,
    reachableOccurrenceIDs: Set<String> = [],
    insideEntryRegion: Bool = false
  ) {
    self.directedEdgeID = directedEdgeID
    self.matchedEntityID = matchedEntityID
    self.expectedOccurrenceID = expectedOccurrenceID
    self.matchedOccurrenceID = matchedOccurrenceID
    self.candidateOccurrenceIDs = candidateOccurrenceIDs
    self.candidateResolution = candidateResolution
    self.projectedOccurrenceID = projectedOccurrenceID
    self.observedAtMilliseconds = observedAtMilliseconds
    self.reportedConfidence = reportedConfidence
    self.horizontalAccuracyMeters = horizontalAccuracyMeters
    self.ageMilliseconds = ageMilliseconds
    self.headingMatches = headingMatches
    self.forwardContinuity = forwardContinuity
    self.reachableOccurrenceIDs = reachableOccurrenceIDs
    self.insideEntryRegion = insideEntryRegion
  }

  public var effectiveConfidence: LocationConfidence {
    if let horizontalAccuracyMeters, horizontalAccuracyMeters < 0 {
      return .lost
    }
    if let ageMilliseconds, ageMilliseconds >= 10_000 {
      return .low
    }
    return reportedConfidence ?? .medium
  }
}

public struct BranchObservation: Equatable, Sendable {
  public let observedMovementID: String?
  public let candidateOccurrenceIDs: Set<String>
  public let confidence: LocationConfidence

  public init(
    observedMovementID: String? = nil,
    candidateOccurrenceIDs: Set<String> = [],
    confidence: LocationConfidence
  ) {
    self.observedMovementID = observedMovementID
    self.candidateOccurrenceIDs = candidateOccurrenceIDs
    self.confidence = confidence
  }
}

public struct SignGuidance: Equatable, Sendable {
  public let routeShields: [String]
  public let destinationsJapanese: [String]
  public let destinationsEnglish: [String]

  public init(
    routeShields: [String] = [],
    destinationsJapanese: [String] = [],
    destinationsEnglish: [String] = []
  ) {
    self.routeShields = routeShields
    self.destinationsJapanese = destinationsJapanese
    self.destinationsEnglish = destinationsEnglish
  }
}

public struct RecoveryState: Equatable, Sendable {
  public enum Status: String, Sendable {
    case inactive = "INACTIVE"
    case active = "ACTIVE"
    case unavailable = "NO_RELEASED_REJOIN"
  }

  public var status: Status = .inactive
  public var objective: String?
  public var routePlanID: String?
  public var chosenRejoinOccurrenceID: String?
  public var destinationRerouteUsed = false

  public init() {}
}

public struct EgressState: Equatable, Sendable {
  public enum Status: String, Sendable {
    case inactive = "INACTIVE"
    case active = "ACTIVE"
    case unavailable = "UNAVAILABLE"
  }

  public var status: Status = .inactive
  public var exitFacilityID: String?
  public var firstEligibleOccurrenceID: String?
  public var prohibitedActions: [String] = []

  public init() {}
}

public struct NavigationSnapshot: Equatable, Sendable {
  public var journeyPhase: JourneyPhase
  public var lastPhaseTransitionTrigger: String?
  public var activeRoutePlanID: String?
  public var currentOccurrenceID: String?
  public var currentOccurrenceIndex: Int?
  public var completedOccurrenceIDs: [String]
  public var pendingOccurrenceIDs: [String]
  public var skippedOccurrenceIDs: [String]
  public var locationConfidence: LocationConfidence
  public var markerStyle: String
  public var ambiguityReason: String?
  public var signalReacquisitionStatus: SignalReacquisitionStatus
  public var signalReacquisitionTrigger: String?
  public var routeCandidateResolution: RouteCandidateResolution
  public var strictRouteAutoCommitAllowed: Bool
  public var routeExecutable: Bool
  public var routeWarnings: [String]
  public var routeBlockingReasons: [String]
  public var routeBlockingOccurrenceIDs: [String]
  public var recovery: RecoveryState
  public var egress: EgressState
  public var signGuidance: SignGuidance
  public var prohibitedGuidanceActions: [String]
  public var requiresRouteEditingWhileMoving: Bool
  public var requiresPhoneTouchWhileMoving: Bool
  public var showsEntryRouteShieldAndDirection: Bool
  public var finishConfirmationExitFacilityID: String?

  public init(
    journeyPhase: JourneyPhase = .planning,
    activeRoutePlanID: String? = nil,
    currentOccurrenceID: String? = nil,
    locationConfidence: LocationConfidence = .medium
  ) {
    self.journeyPhase = journeyPhase
    self.lastPhaseTransitionTrigger = nil
    self.activeRoutePlanID = activeRoutePlanID
    self.currentOccurrenceID = currentOccurrenceID
    self.currentOccurrenceIndex = nil
    self.completedOccurrenceIDs = []
    self.pendingOccurrenceIDs = []
    self.skippedOccurrenceIDs = []
    self.locationConfidence = locationConfidence
    self.markerStyle = "MEASURED"
    self.ambiguityReason = nil
    self.signalReacquisitionStatus = .inactive
    self.signalReacquisitionTrigger = nil
    self.routeCandidateResolution = .unknown
    self.strictRouteAutoCommitAllowed = false
    self.routeExecutable = true
    self.routeWarnings = []
    self.routeBlockingReasons = []
    self.routeBlockingOccurrenceIDs = []
    self.recovery = RecoveryState()
    self.egress = EgressState()
    self.signGuidance = SignGuidance()
    self.prohibitedGuidanceActions = []
    self.requiresRouteEditingWhileMoving = false
    self.requiresPhoneTouchWhileMoving = false
    self.showsEntryRouteShieldAndDirection = true
    self.finishConfirmationExitFacilityID = nil
  }
}
