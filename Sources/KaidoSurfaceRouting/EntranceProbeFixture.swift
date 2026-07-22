import Foundation

public struct EntranceProbeFixture: Codable, Equatable, Sendable {
  public let schemaVersion: String
  public let id: String
  public let networkSnapshotID: String
  public let evidence: ProbeEvidence
  public let entrance: ProbeEntranceFacility
  public let approachAnchor: DirectedApproachAnchor
  public let entryTransition: ProbeEntryTransition
  public let journeyCompatibility: ProbeJourneyCompatibility
  public let prohibitions: ProbeProhibitions
  public let origins: [ProbeOrigin]

  public init(
    schemaVersion: String,
    id: String,
    networkSnapshotID: String,
    evidence: ProbeEvidence,
    entrance: ProbeEntranceFacility,
    approachAnchor: DirectedApproachAnchor,
    entryTransition: ProbeEntryTransition,
    journeyCompatibility: ProbeJourneyCompatibility,
    prohibitions: ProbeProhibitions,
    origins: [ProbeOrigin]
  ) {
    self.schemaVersion = schemaVersion
    self.id = id
    self.networkSnapshotID = networkSnapshotID
    self.evidence = evidence
    self.entrance = entrance
    self.approachAnchor = approachAnchor
    self.entryTransition = entryTransition
    self.journeyCompatibility = journeyCompatibility
    self.prohibitions = prohibitions
    self.origins = origins
  }

  public func origin(id: String) -> ProbeOrigin? {
    origins.first { $0.id == id }
  }

  public func makeRequest(originID: String) throws -> SurfaceRouteRequest {
    guard let origin = origin(id: originID) else {
      throw EntranceProbeFixtureError.unknownOrigin(originID)
    }

    return SurfaceRouteRequest(
      id: "\(id).\(origin.id)",
      originID: origin.id,
      origin: origin.coordinate,
      entranceFacilityID: entrance.facilityID,
      selectedJoinOccurrenceID: entryTransition.firstRouteOccurrenceID,
      destinationAnchor: approachAnchor
    )
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case id = "fixture_id"
    case networkSnapshotID = "network_snapshot_id"
    case evidence
    case entrance
    case approachAnchor = "approach_anchor"
    case entryTransition = "entry_transition"
    case journeyCompatibility = "journey_compatibility"
    case prohibitions
    case origins
  }
}

public enum EntranceProbeFixtureError: Error, Equatable, Sendable {
  case unknownOrigin(String)
}

public struct ProbeEvidence: Codable, Equatable, Sendable {
  public enum Classification: String, Codable, Sendable {
    case synthetic = "SYNTHETIC"
    case communityCandidate = "COMMUNITY_CANDIDATE"
    case officialChecked = "OFFICIAL_CHECKED"
    case fieldChecked = "FIELD_CHECKED"
    case released = "RELEASED"
    case staleReviewRequired = "STALE_REVIEW_REQUIRED"
  }

  public let classification: Classification
  public let checkedAt: String
  public let sources: [ProbeEvidenceSource]
  public let limitations: [String]
  public let releaseBlockers: [String]

  public init(
    classification: Classification,
    checkedAt: String,
    sources: [ProbeEvidenceSource],
    limitations: [String],
    releaseBlockers: [String]
  ) {
    self.classification = classification
    self.checkedAt = checkedAt
    self.sources = sources
    self.limitations = limitations
    self.releaseBlockers = releaseBlockers
  }

  private enum CodingKeys: String, CodingKey {
    case classification
    case checkedAt = "checked_at"
    case sources
    case limitations
    case releaseBlockers = "release_blockers"
  }
}

public struct ProbeEvidenceSource: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable {
    case operatorSource = "OPERATOR"
    case structuredData = "STRUCTURED_DATA"
    case fieldEvidence = "FIELD"
    case communityDiscovery = "COMMUNITY"
  }

  public let id: String
  public let kind: Kind
  public let uri: String
  public let licenceClass: String
  public let checkedAt: String
  public let supports: String

  public init(
    id: String,
    kind: Kind,
    uri: String,
    licenceClass: String,
    checkedAt: String,
    supports: String
  ) {
    self.id = id
    self.kind = kind
    self.uri = uri
    self.licenceClass = licenceClass
    self.checkedAt = checkedAt
    self.supports = supports
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case kind
    case uri
    case licenceClass = "licence_class"
    case checkedAt = "checked_at"
    case supports
  }
}

public struct ProbeEntranceFacility: Codable, Equatable, Sendable {
  public let facilityID: String
  public let accessComplexID: String
  public let targetCarriagewayID: String
  public let targetDirection: String

  public init(
    facilityID: String,
    accessComplexID: String,
    targetCarriagewayID: String,
    targetDirection: String
  ) {
    self.facilityID = facilityID
    self.accessComplexID = accessComplexID
    self.targetCarriagewayID = targetCarriagewayID
    self.targetDirection = targetDirection
  }

  private enum CodingKeys: String, CodingKey {
    case facilityID = "facility_id"
    case accessComplexID = "access_complex_id"
    case targetCarriagewayID = "target_carriageway_id"
    case targetDirection = "target_direction"
  }
}

public struct ProbeEntryTransition: Codable, Equatable, Sendable {
  public let directedEdgeIDs: [String]
  public let firstRouteOccurrenceID: String
  public let targetExpresswayEdgeID: String?

  public init(
    directedEdgeIDs: [String],
    firstRouteOccurrenceID: String,
    targetExpresswayEdgeID: String? = nil
  ) {
    self.directedEdgeIDs = directedEdgeIDs
    self.firstRouteOccurrenceID = firstRouteOccurrenceID
    self.targetExpresswayEdgeID = targetExpresswayEdgeID
  }

  private enum CodingKeys: String, CodingKey {
    case directedEdgeIDs = "directed_edge_ids"
    case firstRouteOccurrenceID = "first_route_occurrence_id"
    case targetExpresswayEdgeID = "target_expressway_edge_id"
  }
}

public struct ProbeJourneyCompatibility: Codable, Equatable, Sendable {
  public enum FinishPolicy: String, Codable, Sendable {
    case fixedExit = "FIXED_EXIT"
    case returnNearOrigin = "RETURN_NEAR_ORIGIN"
    case finishOnRequest = "FINISH_ON_REQUEST"
  }

  public let allowedJoinOccurrenceIDs: [String]
  public let finishPolicies: [FinishPolicy]
  public let compatibleExitFacilityIDs: [String]

  public init(
    allowedJoinOccurrenceIDs: [String],
    finishPolicies: [FinishPolicy],
    compatibleExitFacilityIDs: [String]
  ) {
    self.allowedJoinOccurrenceIDs = allowedJoinOccurrenceIDs
    self.finishPolicies = finishPolicies
    self.compatibleExitFacilityIDs = compatibleExitFacilityIDs
  }

  private enum CodingKeys: String, CodingKey {
    case allowedJoinOccurrenceIDs = "allowed_join_occurrence_ids"
    case finishPolicies = "finish_policies"
    case compatibleExitFacilityIDs = "compatible_exit_facility_ids"
  }
}

public struct ProbeProhibitions: Codable, Equatable, Sendable {
  public let forbiddenEarlyExpresswayEdgeIDs: [String]
  public let forbiddenTollDomainIDs: [String]

  public init(
    forbiddenEarlyExpresswayEdgeIDs: [String],
    forbiddenTollDomainIDs: [String]
  ) {
    self.forbiddenEarlyExpresswayEdgeIDs = forbiddenEarlyExpresswayEdgeIDs
    self.forbiddenTollDomainIDs = forbiddenTollDomainIDs
  }

  private enum CodingKeys: String, CodingKey {
    case forbiddenEarlyExpresswayEdgeIDs = "forbidden_early_expressway_edge_ids"
    case forbiddenTollDomainIDs = "forbidden_toll_domain_ids"
  }
}

public struct ProbeOrigin: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, CaseIterable, Sendable {
    case sameSide = "SAME_SIDE"
    case crossDirection = "CROSS_DIRECTION"
    case nearestIncompatible = "NEAREST_INCOMPATIBLE"
  }

  public let id: String
  public let kind: Kind
  public let coordinate: SurfaceCoordinate
  public let notes: String

  public init(id: String, kind: Kind, coordinate: SurfaceCoordinate, notes: String) {
    self.id = id
    self.kind = kind
    self.coordinate = coordinate
    self.notes = notes
  }

  private enum CodingKeys: String, CodingKey {
    case id = "origin_id"
    case kind
    case coordinate
    case notes
  }
}

public struct FixtureValidationIssue: Codable, Equatable, Sendable {
  public let code: String
  public let path: String

  public init(code: String, path: String) {
    self.code = code
    self.path = path
  }
}

extension EntranceProbeFixture {
  public func structuralValidationIssues() -> [FixtureValidationIssue] {
    var issues: [FixtureValidationIssue] = []

    if schemaVersion != "1.0" {
      issues.append(.init(code: "UNSUPPORTED_SCHEMA_VERSION", path: "schema_version"))
    }
    if !approachAnchor.coordinate.isValid {
      issues.append(.init(code: "INVALID_ANCHOR_COORDINATE", path: "approach_anchor.coordinate"))
    }
    if !(0..<360).contains(approachAnchor.expectedBearingDegrees) {
      issues.append(
        .init(code: "INVALID_EXPECTED_BEARING", path: "approach_anchor.expected_bearing_degrees")
      )
    }
    if !(0...180).contains(approachAnchor.bearingToleranceDegrees) {
      issues.append(
        .init(code: "INVALID_BEARING_TOLERANCE", path: "approach_anchor.bearing_tolerance_degrees")
      )
    }
    if approachAnchor.maxTerminalDistanceMeters <= 0 {
      issues.append(
        .init(
          code: "INVALID_TERMINAL_DISTANCE",
          path: "approach_anchor.max_terminal_distance_meters"
        )
      )
    }
    if entryTransition.directedEdgeIDs.isEmpty {
      issues.append(
        .init(code: "EMPTY_ENTRY_TRANSITION", path: "entry_transition.directed_edge_ids")
      )
    }
    if !journeyCompatibility.allowedJoinOccurrenceIDs.contains(
      entryTransition.firstRouteOccurrenceID
    ) {
      issues.append(
        .init(
          code: "FIRST_OCCURRENCE_NOT_ALLOWED_JOIN",
          path: "journey_compatibility.allowed_join_occurrence_ids"
        )
      )
    }

    let originIDs = origins.map(\.id)
    if Set(originIDs).count != originIDs.count {
      issues.append(.init(code: "DUPLICATE_ORIGIN_ID", path: "origins"))
    }
    let originKinds = Set(origins.map(\.kind))
    for kind in ProbeOrigin.Kind.allCases where !originKinds.contains(kind) {
      issues.append(.init(code: "MISSING_ORIGIN_KIND_\(kind.rawValue)", path: "origins"))
    }
    for (index, origin) in origins.enumerated() where !origin.coordinate.isValid {
      issues.append(.init(code: "INVALID_ORIGIN_COORDINATE", path: "origins[\(index)].coordinate"))
    }

    if evidence.classification == .synthetic {
      var syntheticIDs = [
        id,
        networkSnapshotID,
        entrance.facilityID,
        entrance.accessComplexID,
        entrance.targetCarriagewayID,
        approachAnchor.id,
        approachAnchor.directedSurfaceEdgeID,
        entryTransition.firstRouteOccurrenceID,
      ]
      syntheticIDs.append(contentsOf: entryTransition.directedEdgeIDs)
      if let targetExpresswayEdgeID = entryTransition.targetExpresswayEdgeID {
        syntheticIDs.append(targetExpresswayEdgeID)
      }
      syntheticIDs.append(contentsOf: journeyCompatibility.allowedJoinOccurrenceIDs)
      syntheticIDs.append(contentsOf: journeyCompatibility.compatibleExitFacilityIDs)
      syntheticIDs.append(contentsOf: prohibitions.forbiddenEarlyExpresswayEdgeIDs)
      syntheticIDs.append(contentsOf: prohibitions.forbiddenTollDomainIDs)
      syntheticIDs.append(contentsOf: origins.map(\.id))

      if syntheticIDs.contains(where: { !$0.hasPrefix("test.") }) {
        issues.append(.init(code: "SYNTHETIC_ID_NOT_NAMESPACED", path: "fixture"))
      }
    } else if evidence.sources.isEmpty {
      issues.append(.init(code: "NON_SYNTHETIC_EVIDENCE_MISSING", path: "evidence.sources"))
    }

    return issues
  }

  public func releaseValidationIssues() -> [FixtureValidationIssue] {
    var issues = structuralValidationIssues()

    if evidence.classification != .released {
      issues.append(.init(code: "NOT_RELEASED", path: "evidence.classification"))
    }
    if !evidence.releaseBlockers.isEmpty {
      issues.append(.init(code: "HAS_RELEASE_BLOCKERS", path: "evidence.release_blockers"))
    }

    let sourceKinds = Set(evidence.sources.map(\.kind))
    if !sourceKinds.contains(.operatorSource) {
      issues.append(.init(code: "OPERATOR_EVIDENCE_MISSING", path: "evidence.sources"))
    }
    if !sourceKinds.contains(.structuredData) {
      issues.append(.init(code: "STRUCTURED_DATA_EVIDENCE_MISSING", path: "evidence.sources"))
    }

    return issues
  }
}
