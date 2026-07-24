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

  public init(
    id: String,
    networkSnapshotID: String,
    routePlanID: String,
    entryTransition: EntryTransition,
    recoveryCandidates: [RecoveryCandidate],
    egressOptions: [EgressOption]
  ) {
    self.id = id
    self.networkSnapshotID = networkSnapshotID
    self.routePlanID = routePlanID
    self.entryTransition = entryTransition
    self.recoveryCandidates = recoveryCandidates
    self.egressOptions = egressOptions
  }

  private enum CodingKeys: String, CodingKey {
    case id = "runtime_policy_id"
    case networkSnapshotID = "network_snapshot_id"
    case routePlanID = "route_plan_id"
    case entryTransition = "entry_transition"
    case recoveryCandidates = "recovery_candidates"
    case egressOptions = "egress_options"
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

    if routePlan.recoveryPolicy == .safeRejoin && recoveryCandidates.isEmpty {
      issues.append(.missingReleasedRecovery)
    }
    if routePlan.recoveryPolicy != .safeRejoin && !recoveryCandidates.isEmpty {
      issues.append(.unexpectedReleasedRecovery)
    }
    let firstRouteIndex = routePlan.occurrences.first?.index ?? -1
    for candidate in recoveryCandidates {
      let targetIndex = routePlan.occurrence(id: candidate.targetOccurrenceID)?.index
      if !candidate.isReleased
        || !candidate.staysInAllowedTollDomain
        || targetIndex.map({ $0 <= firstRouteIndex }) ?? true
        || candidate.recoveryOccurrenceIDs.isEmpty
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
