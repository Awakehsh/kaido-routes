import Foundation
import KaidoDomain

public enum EntranceApproachAvailability: String, Equatable, Sendable {
  case available = "AVAILABLE"
  case unavailable = "UNAVAILABLE"
  case unknown = "UNKNOWN"
}

public struct EntranceCandidate: Equatable, Sendable {
  public let facilityID: String
  public let straightLineDistanceKM: Double
  public let surfaceETAMinutes: Double
  public let legalJoinOccurrenceIDs: Set<String>
  public let approachAvailability: EntranceApproachAvailability

  public init(
    facilityID: String,
    straightLineDistanceKM: Double,
    surfaceETAMinutes: Double,
    legalJoinOccurrenceIDs: Set<String>,
    approachAvailability: EntranceApproachAvailability = .available
  ) {
    self.facilityID = facilityID
    self.straightLineDistanceKM = straightLineDistanceKM
    self.surfaceETAMinutes = surfaceETAMinutes
    self.legalJoinOccurrenceIDs = legalJoinOccurrenceIDs
    self.approachAvailability = approachAvailability
  }
}

public struct EntranceRecommendation: Equatable, Sendable {
  public let selectedFacilityID: String?
  public let joinOccurrenceID: String?
  public let rejections: [String: [String]]

  public init(
    selectedFacilityID: String?,
    joinOccurrenceID: String?,
    rejections: [String: [String]]
  ) {
    self.selectedFacilityID = selectedFacilityID
    self.joinOccurrenceID = joinOccurrenceID
    self.rejections = rejections
  }
}

public enum EntranceRecommender {
  public static func recommend(
    candidates: [EntranceCandidate],
    allowedJoinOccurrenceIDs: Set<String>
  ) -> EntranceRecommendation {
    var eligible: [(candidate: EntranceCandidate, joins: Set<String>)] = []
    var rejections: [String: [String]] = [:]

    for candidate in candidates {
      switch candidate.approachAvailability {
      case .available:
        break
      case .unavailable:
        rejections[candidate.facilityID, default: []].append(
          "APPROACH_UNAVAILABLE_AT_ENTRY_TIME"
        )
      case .unknown:
        rejections[candidate.facilityID, default: []].append(
          "APPROACH_AVAILABILITY_UNKNOWN"
        )
      }
      let joins = candidate.legalJoinOccurrenceIDs.intersection(allowedJoinOccurrenceIDs)
      if joins.isEmpty {
        rejections[candidate.facilityID, default: []].append("NO_LEGAL_ROUTE_JOIN")
      }
      if candidate.approachAvailability == .available, !joins.isEmpty {
        eligible.append((candidate, joins))
      }
    }

    let selected = eligible.min {
      if $0.candidate.surfaceETAMinutes != $1.candidate.surfaceETAMinutes {
        return $0.candidate.surfaceETAMinutes < $1.candidate.surfaceETAMinutes
      }
      if $0.candidate.straightLineDistanceKM != $1.candidate.straightLineDistanceKM {
        return $0.candidate.straightLineDistanceKM < $1.candidate.straightLineDistanceKM
      }
      return $0.candidate.facilityID < $1.candidate.facilityID
    }

    return EntranceRecommendation(
      selectedFacilityID: selected?.candidate.facilityID,
      joinOccurrenceID: selected?.joins.sorted().first,
      rejections: rejections
    )
  }
}

public struct RecoveryCandidate: Equatable, Sendable {
  public let targetOccurrenceID: String
  public let recoveryOccurrenceIDs: [String]
  public let isReleased: Bool
  public let staysInAllowedTollDomain: Bool

  public init(
    targetOccurrenceID: String,
    recoveryOccurrenceIDs: [String],
    isReleased: Bool,
    staysInAllowedTollDomain: Bool
  ) {
    self.targetOccurrenceID = targetOccurrenceID
    self.recoveryOccurrenceIDs = recoveryOccurrenceIDs
    self.isReleased = isReleased
    self.staysInAllowedTollDomain = staysInAllowedTollDomain
  }
}

public enum RecoveryPlanner {
  public static func choose(
    candidates: [RecoveryCandidate],
    routePlan: RoutePlan,
    after currentIndex: Int
  ) -> RecoveryCandidate? {
    candidates
      .filter { candidate in
        guard candidate.isReleased, candidate.staysInAllowedTollDomain,
          let target = routePlan.occurrence(id: candidate.targetOccurrenceID)
        else {
          return false
        }
        return target.index > currentIndex
      }
      .min { lhs, rhs in
        let lhsIndex = routePlan.occurrence(id: lhs.targetOccurrenceID)?.index ?? .max
        let rhsIndex = routePlan.occurrence(id: rhs.targetOccurrenceID)?.index ?? .max
        if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
        if lhs.recoveryOccurrenceIDs.count != rhs.recoveryOccurrenceIDs.count {
          return lhs.recoveryOccurrenceIDs.count < rhs.recoveryOccurrenceIDs.count
        }
        return lhs.targetOccurrenceID < rhs.targetOccurrenceID
      }
  }
}

public struct EgressOption: Equatable, Sendable {
  public let id: String
  public let firstEligibleOccurrenceID: String
  public let exitFacilityID: String
  public let egressOccurrenceIDs: [String]
  public let isReleased: Bool

  public init(
    id: String,
    firstEligibleOccurrenceID: String,
    exitFacilityID: String,
    egressOccurrenceIDs: [String],
    isReleased: Bool
  ) {
    self.id = id
    self.firstEligibleOccurrenceID = firstEligibleOccurrenceID
    self.exitFacilityID = exitFacilityID
    self.egressOccurrenceIDs = egressOccurrenceIDs
    self.isReleased = isReleased
  }
}

public enum EgressPlanner {
  public static func choose(
    options: [EgressOption],
    routePlan: RoutePlan,
    from currentIndex: Int
  ) -> EgressOption? {
    options
      .filter { option in
        guard option.isReleased,
          let firstEligible = routePlan.occurrence(id: option.firstEligibleOccurrenceID)
        else {
          return false
        }
        return firstEligible.index >= currentIndex
      }
      .min { lhs, rhs in
        let lhsIndex = routePlan.occurrence(id: lhs.firstEligibleOccurrenceID)?.index ?? .max
        let rhsIndex = routePlan.occurrence(id: rhs.firstEligibleOccurrenceID)?.index ?? .max
        if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
        return lhs.id < rhs.id
      }
  }
}
