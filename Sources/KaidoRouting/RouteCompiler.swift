import Foundation
import KaidoDomain

public struct CompileResult: Equatable, Sendable {
  public enum Status: String, Sendable {
    case accepted = "ACCEPTED"
    case rejected = "REJECTED"
  }

  public let status: Status
  public let errorCodes: [String]
  public let syntheticFacilityIDs: [String]
  public let substitutedMovementIDs: [String]

  public init(
    status: Status,
    errorCodes: [String] = [],
    syntheticFacilityIDs: [String] = [],
    substitutedMovementIDs: [String] = []
  ) {
    self.status = status
    self.errorCodes = errorCodes
    self.syntheticFacilityIDs = syntheticFacilityIDs
    self.substitutedMovementIDs = substitutedMovementIDs
  }
}

public struct DirectedMovementRequest: Equatable, Sendable {
  public let incomingApproachID: String
  public let junctionComplexID: String
  public let outgoingCarriagewayID: String

  public init(
    incomingApproachID: String,
    junctionComplexID: String,
    outgoingCarriagewayID: String
  ) {
    self.incomingApproachID = incomingApproachID
    self.junctionComplexID = junctionComplexID
    self.outgoingCarriagewayID = outgoingCarriagewayID
  }
}

public struct LegalMovement: Equatable, Sendable {
  public let id: String
  public let incomingApproachID: String
  public let junctionComplexID: String
  public let outgoingCarriagewayID: String

  public init(
    id: String,
    incomingApproachID: String,
    junctionComplexID: String,
    outgoingCarriagewayID: String
  ) {
    self.id = id
    self.incomingApproachID = incomingApproachID
    self.junctionComplexID = junctionComplexID
    self.outgoingCarriagewayID = outgoingCarriagewayID
  }
}

public enum FacilityKind: String, Sendable {
  case entrance = "ENTRANCE"
  case exit = "EXIT"
}

public struct DirectionalFacility: Equatable, Sendable {
  public let id: String
  public let kind: FacilityKind
  public let carriagewayID: String

  public init(id: String, kind: FacilityKind, carriagewayID: String) {
    self.id = id
    self.kind = kind
    self.carriagewayID = carriagewayID
  }
}

public struct FacilityRequest: Equatable, Sendable {
  public let kind: FacilityKind
  public let carriagewayID: String

  public init(kind: FacilityKind, carriagewayID: String) {
    self.kind = kind
    self.carriagewayID = carriagewayID
  }
}

public enum StrictRouteCompiler {
  public static func validate(
    movement request: DirectedMovementRequest,
    legalMovements: [LegalMovement]
  ) -> CompileResult {
    let isLegal = legalMovements.contains {
      $0.incomingApproachID == request.incomingApproachID
        && $0.junctionComplexID == request.junctionComplexID
        && $0.outgoingCarriagewayID == request.outgoingCarriagewayID
    }

    guard isLegal else {
      return CompileResult(
        status: .rejected,
        errorCodes: ["ILLEGAL_JUNCTION_MOVEMENT"]
      )
    }
    return CompileResult(status: .accepted)
  }

  public static func validate(
    facility request: FacilityRequest,
    explicitFacilities: [DirectionalFacility]
  ) -> CompileResult {
    let exists = explicitFacilities.contains {
      $0.kind == request.kind && $0.carriagewayID == request.carriagewayID
    }

    guard exists else {
      let error =
        request.kind == .entrance
        ? "MISSING_DIRECTIONAL_ENTRANCE"
        : "MISSING_DIRECTIONAL_EXIT"
      return CompileResult(status: .rejected, errorCodes: [error])
    }
    return CompileResult(status: .accepted)
  }

  public static func validateSnapshot(
    savedSnapshotID: String,
    currentSnapshotID: String,
    reviewedMigrationExists: Bool
  ) -> CompileResult {
    guard savedSnapshotID == currentSnapshotID || reviewedMigrationExists else {
      return CompileResult(
        status: .rejected,
        errorCodes: ["INCOMPATIBLE_NETWORK_SNAPSHOT"]
      )
    }
    return CompileResult(status: .accepted)
  }
}
