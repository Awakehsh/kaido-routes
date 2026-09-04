import Foundation
import KaidoDomain
import KaidoRouting

public enum NavigationRuntimePolicyIssue: Equatable, Sendable {
  case invalidIdentity
  case networkSnapshotMismatch
  case routePlanMismatch
  case invalidEntryTransition
  case missingReleasedRecovery
  case unexpectedReleasedRecovery
  case invalidRecoveryCandidate(String)
  case duplicateRecoveryCandidate
  case missingReleasedEgress
  case invalidEgressOption(String)
  case duplicateEgressOptionID(String)
  case invalidLapBoundaries

  public var code: String {
    switch self {
    case .invalidIdentity:
      "INVALID_RUNTIME_POLICY_IDENTITY"
    case .networkSnapshotMismatch:
      "RUNTIME_POLICY_NETWORK_SNAPSHOT_MISMATCH"
    case .routePlanMismatch:
      "RUNTIME_POLICY_ROUTE_PLAN_MISMATCH"
    case .invalidEntryTransition:
      "INVALID_RUNTIME_POLICY_ENTRY_TRANSITION"
    case .missingReleasedRecovery:
      "MISSING_RELEASED_RUNTIME_RECOVERY"
    case .unexpectedReleasedRecovery:
      "UNEXPECTED_RELEASED_RUNTIME_RECOVERY"
    case .invalidRecoveryCandidate:
      "INVALID_RUNTIME_RECOVERY_CANDIDATE"
    case .duplicateRecoveryCandidate:
      "DUPLICATE_RUNTIME_RECOVERY_CANDIDATE"
    case .missingReleasedEgress:
      "MISSING_RELEASED_RUNTIME_EGRESS"
    case .invalidEgressOption:
      "INVALID_RUNTIME_EGRESS_OPTION"
    case .duplicateEgressOptionID:
      "DUPLICATE_RUNTIME_EGRESS_OPTION_ID"
    case .invalidLapBoundaries:
      "INVALID_RUNTIME_POLICY_LAP_BOUNDARIES"
    }
  }

  var sortKey: String {
    switch self {
    case .invalidRecoveryCandidate(let detail),
      .invalidEgressOption(let detail),
      .duplicateEgressOptionID(let detail):
      "\(code):\(detail)"
    default:
      code
    }
  }
}

/// Route-bound policies required to enter, recover, and finish a released drive.
///
/// These values remain inert until the complete navigation and product release
/// gates accept them. Runtime adapters cannot add or replace policy values.
public struct ReleasedNavigationRuntimePolicy: Codable, Equatable, Sendable {
  public let id: String
  public let networkSnapshotID: String
  public let routePlanID: String
  public let entryTransition: EntryTransition
  public let recoveryCandidates: [RecoveryCandidate]
  public let egressOptions: [EgressOption]
  /// Ordered occurrences bounding each lap of a loop route: `n` laps carry
  /// `n + 1` marks, so lap `i` runs from `[i]` up to `[i + 1]`, and the last
  /// mark is where the exit tail begins. Empty for any route without laps.
  ///
  /// This is released structure, not a hint. It is what lets the navigation
  /// core decide for itself where one lap ahead is, instead of taking a
  /// target occurrence from the App.
  public let lapBoundaryOccurrenceIDs: [String]

  public init(
    id: String,
    networkSnapshotID: String,
    routePlanID: String,
    entryTransition: EntryTransition,
    recoveryCandidates: [RecoveryCandidate],
    egressOptions: [EgressOption],
    lapBoundaryOccurrenceIDs: [String] = []
  ) {
    self.id = id
    self.networkSnapshotID = networkSnapshotID
    self.routePlanID = routePlanID
    self.entryTransition = entryTransition
    self.recoveryCandidates = recoveryCandidates
    self.egressOptions = egressOptions
    self.lapBoundaryOccurrenceIDs = lapBoundaryOccurrenceIDs
  }

  private enum CodingKeys: String, CodingKey {
    case id = "runtime_policy_id"
    case networkSnapshotID = "network_snapshot_id"
    case routePlanID = "route_plan_id"
    case entryTransition = "entry_transition"
    case recoveryCandidates = "recovery_candidates"
    case egressOptions = "egress_options"
    case lapBoundaryOccurrenceIDs = "lap_boundary_occurrence_ids"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    networkSnapshotID = try container.decode(
      String.self,
      forKey: .networkSnapshotID
    )
    routePlanID = try container.decode(String.self, forKey: .routePlanID)
    entryTransition = try container.decode(
      EntryTransition.self,
      forKey: .entryTransition
    )
    recoveryCandidates = try container.decode(
      [RecoveryCandidate].self,
      forKey: .recoveryCandidates
    )
    egressOptions = try container.decode(
      [EgressOption].self,
      forKey: .egressOptions
    )
    lapBoundaryOccurrenceIDs =
      try container.decodeIfPresent(
        [String].self,
        forKey: .lapBoundaryOccurrenceIDs
      ) ?? []
  }

  /// A route without laps has no lap structure to describe, so the key is
  /// absent rather than empty. Released artifacts for routes that never had
  /// laps stay byte-identical.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(networkSnapshotID, forKey: .networkSnapshotID)
    try container.encode(routePlanID, forKey: .routePlanID)
    try container.encode(entryTransition, forKey: .entryTransition)
    try container.encode(recoveryCandidates, forKey: .recoveryCandidates)
    try container.encode(egressOptions, forKey: .egressOptions)
    if !lapBoundaryOccurrenceIDs.isEmpty {
      try container.encode(
        lapBoundaryOccurrenceIDs,
        forKey: .lapBoundaryOccurrenceIDs
      )
    }
  }

  func validationIssues(
    networkSnapshot: NetworkSnapshot,
    routePlan: RoutePlan
  ) -> [NavigationRuntimePolicyIssue] {
    var issues: [NavigationRuntimePolicyIssue] = []
    if Self.normalized(id).isEmpty {
      issues.append(.invalidIdentity)
    }
    if networkSnapshotID != networkSnapshot.id {
      issues.append(.networkSnapshotMismatch)
    }
    if routePlanID != routePlan.id {
      issues.append(.routePlanMismatch)
    }

    let transitionEdgeIDs = entryTransition.directedEdgeIDs
    if entryTransition.facilityID != routePlan.entryFacilityID
      || transitionEdgeIDs.isEmpty
      || transitionEdgeIDs.contains(where: { Self.normalized($0).isEmpty })
      || Set(transitionEdgeIDs).count != transitionEdgeIDs.count
      || entryTransition.firstRouteOccurrenceID != routePlan.occurrences.first?.id
    {
      issues.append(.invalidEntryTransition)
    }

    if routePlan.recoveryPolicy != .safeRejoin && !recoveryCandidates.isEmpty {
      issues.append(.unexpectedReleasedRecovery)
    }
    let firstRouteIndex = routePlan.occurrences.first?.index ?? -1
    for candidate in recoveryCandidates {
      let divergenceIndex = routePlan.occurrence(
        id: candidate.divergenceOccurrenceID
      )?.index
      let targetIndex = routePlan.occurrence(id: candidate.targetOccurrenceID)?.index
      if !candidate.isReleased
        || !candidate.staysInAllowedTollDomain
        || targetIndex.map({ $0 <= firstRouteIndex }) ?? true
        || divergenceIndex == nil
        || targetIndex.map({ target in
          divergenceIndex.map({ target <= $0 }) ?? true
        }) ?? true
        || Self.normalized(candidate.triggerDirectedEdgeID).isEmpty
        || candidate.recoveryOccurrenceIDs.isEmpty
        || candidate.recoveryOccurrenceIDs.first
          != candidate.triggerDirectedEdgeID
        || candidate.recoveryOccurrenceIDs.contains(where: {
          Self.normalized($0).isEmpty
        })
        || Set(candidate.recoveryOccurrenceIDs).count
          != candidate.recoveryOccurrenceIDs.count
      {
        issues.append(.invalidRecoveryCandidate(candidate.targetOccurrenceID))
      }
    }
    if Self.containsDuplicate(recoveryCandidates) {
      issues.append(.duplicateRecoveryCandidate)
    }

    // A lapped route carries one mark per lap plus the end of the last, every
    // mark resolving to a real occurrence in strictly increasing order. A
    // route without laps carries none. Anything between the two would let the
    // core skip to a place the release never described.
    if !lapBoundaryOccurrenceIDs.isEmpty {
      let indices = lapBoundaryOccurrenceIDs.map {
        routePlan.occurrence(id: $0)?.index
      }
      if lapBoundaryOccurrenceIDs.count < 2
        || Set(lapBoundaryOccurrenceIDs).count != lapBoundaryOccurrenceIDs.count
        || indices.contains(where: { $0 == nil })
        || zip(indices, indices.dropFirst()).contains(where: { current, next in
          guard let current, let next else { return true }
          return next <= current
        })
      {
        issues.append(.invalidLapBoundaries)
      }
    }

    if egressOptions.isEmpty {
      issues.append(.missingReleasedEgress)
    }
    let egressIDs = egressOptions.map(\.id)
    for duplicateID in Set(
      egressIDs.filter { id in
        egressIDs.filter { $0 == id }.count > 1
      })
    {
      issues.append(.duplicateEgressOptionID(duplicateID))
    }
    for option in egressOptions {
      if Self.normalized(option.id).isEmpty
        || !option.isReleased
        || routePlan.occurrence(id: option.firstEligibleOccurrenceID) == nil
        || option.exitFacilityID != routePlan.exitFacilityID
        || option.egressOccurrenceIDs.isEmpty
        || option.egressOccurrenceIDs.contains(where: {
          Self.normalized($0).isEmpty
        })
        || Set(option.egressOccurrenceIDs).count != option.egressOccurrenceIDs.count
      {
        issues.append(.invalidEgressOption(option.id))
      }
    }

    return Self.sortedUnique(issues)
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func containsDuplicate<T: Equatable>(_ values: [T]) -> Bool {
    for index in values.indices {
      if values[..<index].contains(values[index]) {
        return true
      }
    }
    return false
  }

  private static func sortedUnique(
    _ issues: [NavigationRuntimePolicyIssue]
  ) -> [NavigationRuntimePolicyIssue] {
    var result: [NavigationRuntimePolicyIssue] = []
    for issue in issues.sorted(by: { $0.sortKey < $1.sortKey })
    where !result.contains(issue) {
      result.append(issue)
    }
    return result
  }
}
