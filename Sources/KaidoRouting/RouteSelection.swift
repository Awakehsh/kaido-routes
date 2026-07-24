import Foundation
import KaidoDomain

public enum EntranceApproachAvailability: String, Equatable, Sendable {
  case available = "AVAILABLE"
  case unavailable = "UNAVAILABLE"
  case unknown = "UNKNOWN"
}

public struct EntranceCandidate: Equatable, Sendable {
  public let facilityID: String
  public let targetCarriagewayID: String
  public let straightLineDistanceKM: Double
  public let surfaceETAMinutes: Double
  public let legalJoinOccurrenceIDs: Set<String>
  public let approachAvailability: EntranceApproachAvailability

  public init(
    facilityID: String,
    targetCarriagewayID: String,
    straightLineDistanceKM: Double,
    surfaceETAMinutes: Double,
    legalJoinOccurrenceIDs: Set<String>,
    approachAvailability: EntranceApproachAvailability = .available
  ) {
    self.facilityID = facilityID
    self.targetCarriagewayID = targetCarriagewayID
    self.straightLineDistanceKM = straightLineDistanceKM
    self.surfaceETAMinutes = surfaceETAMinutes
    self.legalJoinOccurrenceIDs = legalJoinOccurrenceIDs
    self.approachAvailability = approachAvailability
  }
}

public enum EntranceRecommendationStatus: String, Equatable, Sendable {
  case selected = "SELECTED"
  case noEligibleCandidate = "NO_ELIGIBLE_CANDIDATE"
  case rejected = "REJECTED"
}

public enum EntranceRecommendationSelectionReason: String, Equatable, Sendable {
  case exactDirectionalCarriageway = "EXACT_DIRECTIONAL_CARRIAGEWAY"
  case legalRouteJoin = "LEGAL_ROUTE_JOIN"
  case approachAvailableAtEntryTime = "APPROACH_AVAILABLE_AT_ENTRY_TIME"
  case lowestSurfaceETAAfterHardFilters = "LOWEST_SURFACE_ETA_AFTER_HARD_FILTERS"
}

public struct EntranceRecommendationSelection: Equatable, Sendable {
  public let facilityID: String
  public let targetCarriagewayID: String
  public let joinOccurrenceID: String
  public let straightLineDistanceKM: Double
  public let straightLineDistanceRank: Int
  public let surfaceETAMinutes: Double
  public let reasonCodes: [EntranceRecommendationSelectionReason]

  public init(
    facilityID: String,
    targetCarriagewayID: String,
    joinOccurrenceID: String,
    straightLineDistanceKM: Double,
    straightLineDistanceRank: Int,
    surfaceETAMinutes: Double,
    reasonCodes: [EntranceRecommendationSelectionReason]
  ) {
    self.facilityID = facilityID
    self.targetCarriagewayID = targetCarriagewayID
    self.joinOccurrenceID = joinOccurrenceID
    self.straightLineDistanceKM = straightLineDistanceKM
    self.straightLineDistanceRank = straightLineDistanceRank
    self.surfaceETAMinutes = surfaceETAMinutes
    self.reasonCodes = reasonCodes
  }
}

public struct EntranceRecommendation: Equatable, Sendable {
  public let status: EntranceRecommendationStatus
  public let selection: EntranceRecommendationSelection?
  public let rejections: [String: [String]]
  public let errorCodes: [String]

  public var selectedFacilityID: String? {
    selection?.facilityID
  }

  public var joinOccurrenceID: String? {
    selection?.joinOccurrenceID
  }

  public init(
    status: EntranceRecommendationStatus,
    selection: EntranceRecommendationSelection?,
    rejections: [String: [String]],
    errorCodes: [String] = []
  ) {
    self.status = status
    self.selection = selection
    self.rejections = rejections
    self.errorCodes = errorCodes
  }
}

public enum EntranceRecommender {
  public static func recommend(
    candidates: [EntranceCandidate],
    allowedJoinOccurrenceIDs: Set<String>
  ) -> EntranceRecommendation {
    let inputErrors = validateInputs(
      candidates: candidates,
      allowedJoinOccurrenceIDs: allowedJoinOccurrenceIDs
    )
    guard inputErrors.isEmpty else {
      return EntranceRecommendation(
        status: .rejected,
        selection: nil,
        rejections: [:],
        errorCodes: inputErrors
      )
    }

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

    guard let selected else {
      return EntranceRecommendation(
        status: .noEligibleCandidate,
        selection: nil,
        rejections: rejections
      )
    }
    let straightLineDistanceRank =
      candidates.filter {
        $0.straightLineDistanceKM < selected.candidate.straightLineDistanceKM
      }.count + 1
    guard let joinOccurrenceID = selected.joins.sorted().first else {
      return EntranceRecommendation(
        status: .rejected,
        selection: nil,
        rejections: rejections,
        errorCodes: ["ENTRANCE_SELECTION_JOIN_MISSING"]
      )
    }

    return EntranceRecommendation(
      status: .selected,
      selection: EntranceRecommendationSelection(
        facilityID: selected.candidate.facilityID,
        targetCarriagewayID: selected.candidate.targetCarriagewayID,
        joinOccurrenceID: joinOccurrenceID,
        straightLineDistanceKM: selected.candidate.straightLineDistanceKM,
        straightLineDistanceRank: straightLineDistanceRank,
        surfaceETAMinutes: selected.candidate.surfaceETAMinutes,
        reasonCodes: [
          .exactDirectionalCarriageway,
          .legalRouteJoin,
          .approachAvailableAtEntryTime,
          .lowestSurfaceETAAfterHardFilters,
        ]
      ),
      rejections: rejections
    )
  }

  private static func validateInputs(
    candidates: [EntranceCandidate],
    allowedJoinOccurrenceIDs: Set<String>
  ) -> [String] {
    var errorCodes: Set<String> = []
    if candidates.isEmpty {
      errorCodes.insert("NO_ENTRANCE_CANDIDATES")
    }
    if allowedJoinOccurrenceIDs.isEmpty
      || allowedJoinOccurrenceIDs.contains(where: {
        $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      })
    {
      errorCodes.insert("INVALID_ALLOWED_JOIN_OCCURRENCE_IDS")
    }

    var facilityIDs: Set<String> = []
    for candidate in candidates {
      let facilityID = candidate.facilityID.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      let targetCarriagewayID = candidate.targetCarriagewayID.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      if facilityID.isEmpty || targetCarriagewayID.isEmpty {
        errorCodes.insert("INVALID_ENTRANCE_CANDIDATE_IDENTITY")
      }
      if !facilityIDs.insert(candidate.facilityID).inserted {
        errorCodes.insert("DUPLICATE_ENTRANCE_FACILITY_ID")
      }
      if !candidate.straightLineDistanceKM.isFinite
        || candidate.straightLineDistanceKM < 0
        || !candidate.surfaceETAMinutes.isFinite
        || candidate.surfaceETAMinutes < 0
      {
        errorCodes.insert("INVALID_ENTRANCE_CANDIDATE_METRIC")
      }
      if candidate.legalJoinOccurrenceIDs.contains(where: {
        $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }) {
        errorCodes.insert("INVALID_ENTRANCE_LEGAL_JOIN_ID")
      }
    }
    return errorCodes.sorted()
  }
}

public struct RecoveryCandidate: Codable, Equatable, Sendable {
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

  private enum CodingKeys: String, CodingKey {
    case targetOccurrenceID = "target_occurrence_id"
    case recoveryOccurrenceIDs = "recovery_occurrence_ids"
    case isReleased = "released"
    case staysInAllowedTollDomain = "stays_in_allowed_toll_domain"
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

public struct EgressOption: Codable, Equatable, Sendable {
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

  private enum CodingKeys: String, CodingKey {
    case id = "egress_option_id"
    case firstEligibleOccurrenceID = "first_eligible_occurrence_id"
    case exitFacilityID = "exit_facility_id"
    case egressOccurrenceIDs = "egress_occurrence_ids"
    case isReleased = "released"
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
