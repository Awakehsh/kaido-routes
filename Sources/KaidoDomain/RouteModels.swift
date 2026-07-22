import Foundation

public struct NetworkSnapshot: Codable, Equatable, Sendable {
  public let id: String
  public let status: Status
  public let effectiveAt: String

  public enum Status: String, Codable, Sendable {
    case active = "ACTIVE"
    case proposed = "PROPOSED"
    case retired = "RETIRED"
    case test = "TEST"
  }

  public init(id: String, status: Status, effectiveAt: String) {
    self.id = id
    self.status = status
    self.effectiveAt = effectiveAt
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case status
    case effectiveAt = "effective_at"
  }
}

public struct RouteOccurrence: Codable, Equatable, Hashable, Sendable {
  public enum Kind: String, Codable, Sendable {
    case edge = "EDGE"
    case junctionMovement = "JUNCTION_MOVEMENT"
    case paVisit = "PA_VISIT"
  }

  public let id: String
  public let index: Int
  public let kind: Kind
  public let entityID: String
  public let parkingAreaID: String?
  public let tollDomainID: String?
  public let isOptional: Bool

  public init(
    id: String,
    index: Int,
    kind: Kind,
    entityID: String,
    parkingAreaID: String? = nil,
    tollDomainID: String? = nil,
    isOptional: Bool = false
  ) {
    self.id = id
    self.index = index
    self.kind = kind
    self.entityID = entityID
    self.parkingAreaID = parkingAreaID
    self.tollDomainID = tollDomainID
    self.isOptional = isOptional
  }

  private enum CodingKeys: String, CodingKey {
    case id = "occurrence_id"
    case index
    case kind
    case entityID = "entity_id"
    case parkingAreaID = "parking_area_id"
    case tollDomainID = "toll_domain_id"
    case isOptional = "optional"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    index = try container.decode(Int.self, forKey: .index)
    kind = try container.decode(Kind.self, forKey: .kind)
    entityID = try container.decode(String.self, forKey: .entityID)
    parkingAreaID = try container.decodeIfPresent(String.self, forKey: .parkingAreaID)
    tollDomainID = try container.decodeIfPresent(String.self, forKey: .tollDomainID)
    isOptional = try container.decodeIfPresent(Bool.self, forKey: .isOptional) ?? false
  }
}

public struct RoutePlan: Codable, Equatable, Sendable {
  public enum RecoveryPolicy: String, Codable, Sendable {
    case strict = "STRICT"
    case safeRejoin = "SAFE_REJOIN"
    case safeExit = "SAFE_EXIT"
    case manualWhenParked = "MANUAL_WHEN_PARKED"
  }

  public let id: String
  public let entryFacilityID: String
  public let exitFacilityID: String
  public let recoveryPolicy: RecoveryPolicy
  public let actualDistanceKM: Double?
  public let occurrences: [RouteOccurrence]

  public init(
    id: String,
    entryFacilityID: String,
    exitFacilityID: String,
    recoveryPolicy: RecoveryPolicy,
    actualDistanceKM: Double? = nil,
    occurrences: [RouteOccurrence]
  ) {
    self.id = id
    self.entryFacilityID = entryFacilityID
    self.exitFacilityID = exitFacilityID
    self.recoveryPolicy = recoveryPolicy
    self.actualDistanceKM = actualDistanceKM
    self.occurrences = occurrences
  }

  public func occurrence(id: String) -> RouteOccurrence? {
    occurrences.first { $0.id == id }
  }

  public func occurrence(entityID: String, after index: Int = -1) -> RouteOccurrence? {
    occurrences.first { $0.index > index && $0.entityID == entityID }
  }

  private enum CodingKeys: String, CodingKey {
    case id = "plan_id"
    case entryFacilityID = "entry_facility_id"
    case exitFacilityID = "exit_facility_id"
    case recoveryPolicy = "recovery_policy"
    case actualDistanceKM = "actual_distance_km"
    case occurrences
  }
}
