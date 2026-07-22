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
  public let validatedRequiredEntityIDs: [String]
  public let unresolvedRequiredEntityIDs: [String]
  public let crossedTollDomainIDs: [String]
  public let boundaryOccurrenceIDs: [String]
  public let selectedTemplateVariantID: String?
  public let selectedTemplateParameters: [String]

  public init(
    status: Status,
    errorCodes: [String] = [],
    syntheticFacilityIDs: [String] = [],
    substitutedMovementIDs: [String] = [],
    validatedRequiredEntityIDs: [String] = [],
    unresolvedRequiredEntityIDs: [String] = [],
    crossedTollDomainIDs: [String] = [],
    boundaryOccurrenceIDs: [String] = [],
    selectedTemplateVariantID: String? = nil,
    selectedTemplateParameters: [String] = []
  ) {
    self.status = status
    self.errorCodes = errorCodes
    self.syntheticFacilityIDs = syntheticFacilityIDs
    self.substitutedMovementIDs = substitutedMovementIDs
    self.validatedRequiredEntityIDs = validatedRequiredEntityIDs
    self.unresolvedRequiredEntityIDs = unresolvedRequiredEntityIDs
    self.crossedTollDomainIDs = crossedTollDomainIDs
    self.boundaryOccurrenceIDs = boundaryOccurrenceIDs
    self.selectedTemplateVariantID = selectedTemplateVariantID
    self.selectedTemplateParameters = selectedTemplateParameters
  }
}

public struct ReviewedLapTemplate: Equatable, Sendable {
  public let id: String
  public let sourceOccurrenceIDs: [String]

  public init(id: String, sourceOccurrenceIDs: [String]) {
    self.id = id
    self.sourceOccurrenceIDs = sourceOccurrenceIDs
  }
}

public struct LapDuplicationRequest: Equatable, Sendable {
  public let reviewedTemplateID: String
  public let newOccurrenceIDs: [String]

  public init(reviewedTemplateID: String, newOccurrenceIDs: [String]) {
    self.reviewedTemplateID = reviewedTemplateID
    self.newOccurrenceIDs = newOccurrenceIDs
  }
}

public struct RoutePlanExpansionResult: Equatable, Sendable {
  public let status: CompileResult.Status
  public let errorCodes: [String]
  public let routePlan: RoutePlan?

  public init(
    status: CompileResult.Status,
    errorCodes: [String] = [],
    routePlan: RoutePlan? = nil
  ) {
    self.status = status
    self.errorCodes = errorCodes
    self.routePlan = routePlan
  }
}

public struct RouteComponentRequirement: Equatable, Sendable {
  public let templateID: String
  public let requiredEntityIDsInOrder: [String]

  public init(templateID: String, requiredEntityIDsInOrder: [String]) {
    self.templateID = templateID
    self.requiredEntityIDsInOrder = requiredEntityIDsInOrder
  }
}

public struct RouteTemplateVariantSelection: Equatable, Sendable {
  public let templateID: String
  public let parameters: [String: String]

  public init(templateID: String, parameters: [String: String]) {
    self.templateID = templateID
    self.parameters = parameters
  }
}

public struct ApprovedRouteTemplateVariant: Equatable, Sendable {
  public let id: String
  public let templateID: String
  public let networkSnapshotID: String
  public let parameters: [String: String]
  public let requiredEntityIDsInOrder: [String]

  public init(
    id: String,
    templateID: String,
    networkSnapshotID: String,
    parameters: [String: String],
    requiredEntityIDsInOrder: [String]
  ) {
    self.id = id
    self.templateID = templateID
    self.networkSnapshotID = networkSnapshotID
    self.parameters = parameters
    self.requiredEntityIDsInOrder = requiredEntityIDsInOrder
  }
}

public struct TollDomainPolicy: Equatable, Sendable {
  public let allowedTollDomainIDs: Set<String>
  public let requiresEveryOccurrenceClassified: Bool

  public init(
    allowedTollDomainIDs: Set<String>,
    requiresEveryOccurrenceClassified: Bool = true
  ) {
    self.allowedTollDomainIDs = allowedTollDomainIDs
    self.requiresEveryOccurrenceClassified = requiresEveryOccurrenceClassified
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

public struct ParkingAreaPathRequest: Equatable, Sendable {
  public let parkingAreaID: String
  public let sourceCarriagewayID: String
  public let accessMovementID: String
  public let returnMovementID: String
  public let returnCarriagewayID: String

  public init(
    parkingAreaID: String,
    sourceCarriagewayID: String,
    accessMovementID: String,
    returnMovementID: String,
    returnCarriagewayID: String
  ) {
    self.parkingAreaID = parkingAreaID
    self.sourceCarriagewayID = sourceCarriagewayID
    self.accessMovementID = accessMovementID
    self.returnMovementID = returnMovementID
    self.returnCarriagewayID = returnCarriagewayID
  }
}

public struct DirectionalParkingAreaPath: Equatable, Sendable {
  public let id: String
  public let parkingAreaID: String
  public let sourceCarriagewayID: String
  public let accessMovementID: String
  public let returnMovementID: String
  public let returnCarriagewayID: String

  public init(
    id: String,
    parkingAreaID: String,
    sourceCarriagewayID: String,
    accessMovementID: String,
    returnMovementID: String,
    returnCarriagewayID: String
  ) {
    self.id = id
    self.parkingAreaID = parkingAreaID
    self.sourceCarriagewayID = sourceCarriagewayID
    self.accessMovementID = accessMovementID
    self.returnMovementID = returnMovementID
    self.returnCarriagewayID = returnCarriagewayID
  }
}

public enum StrictRouteCompiler {
  public static func validate(
    routePlan: RoutePlan,
    templateSelection: RouteTemplateVariantSelection,
    approvedVariants: [ApprovedRouteTemplateVariant]
  ) -> CompileResult {
    guard !templateSelection.templateID.isEmpty,
      !templateSelection.parameters.contains(where: { key, value in
        key.isEmpty || value.isEmpty
      })
    else {
      return CompileResult(
        status: .rejected,
        errorCodes: ["INVALID_TEMPLATE_PARAMETERS"]
      )
    }

    let parameterMatchingVariants = approvedVariants.filter {
      $0.templateID == templateSelection.templateID
        && $0.parameters == templateSelection.parameters
    }
    guard !parameterMatchingVariants.isEmpty else {
      return CompileResult(
        status: .rejected,
        errorCodes: ["UNAPPROVED_TEMPLATE_PARAMETERS"]
      )
    }
    let parameterBindings = templateSelection.parameters.map {
      "\($0.key)=\($0.value)"
    }.sorted()
    let matchingVariants = parameterMatchingVariants.filter {
      $0.networkSnapshotID == routePlan.networkSnapshotID
    }
    guard !matchingVariants.isEmpty else {
      return CompileResult(
        status: .rejected,
        errorCodes: ["TEMPLATE_VARIANT_SNAPSHOT_MISMATCH"],
        selectedTemplateParameters: parameterBindings
      )
    }
    guard matchingVariants.count == 1, let variant = matchingVariants.first else {
      return CompileResult(
        status: .rejected,
        errorCodes: ["AMBIGUOUS_APPROVED_TEMPLATE_VARIANT"]
      )
    }

    guard !variant.id.isEmpty, !variant.networkSnapshotID.isEmpty else {
      return CompileResult(
        status: .rejected,
        errorCodes: ["INVALID_APPROVED_TEMPLATE_VARIANT"],
        selectedTemplateParameters: parameterBindings
      )
    }
    let componentResult = validate(
      routePlan: routePlan,
      componentRequirement: RouteComponentRequirement(
        templateID: variant.templateID,
        requiredEntityIDsInOrder: variant.requiredEntityIDsInOrder
      )
    )
    return CompileResult(
      status: componentResult.status,
      errorCodes: componentResult.errorCodes,
      validatedRequiredEntityIDs: componentResult.validatedRequiredEntityIDs,
      unresolvedRequiredEntityIDs: componentResult.unresolvedRequiredEntityIDs,
      selectedTemplateVariantID: variant.id,
      selectedTemplateParameters: parameterBindings
    )
  }

  public static func appendLap(
    to routePlan: RoutePlan,
    request: LapDuplicationRequest,
    reviewedTemplate: ReviewedLapTemplate
  ) -> RoutePlanExpansionResult {
    guard request.reviewedTemplateID == reviewedTemplate.id,
      !reviewedTemplate.sourceOccurrenceIDs.isEmpty,
      reviewedTemplate.sourceOccurrenceIDs.count == request.newOccurrenceIDs.count
    else {
      return RoutePlanExpansionResult(
        status: .rejected,
        errorCodes: ["INVALID_REVIEWED_LAP_TEMPLATE"]
      )
    }

    let sourceCount = reviewedTemplate.sourceOccurrenceIDs.count
    let sourceOccurrences = routePlan.occurrences
    let existingIDs = Set(sourceOccurrences.map(\.id))
    guard existingIDs.count == sourceOccurrences.count,
      sourceOccurrences.enumerated().allSatisfy({ offset, occurrence in
        occurrence.index == offset
      })
    else {
      return RoutePlanExpansionResult(
        status: .rejected,
        errorCodes: ["INVALID_ROUTE_OCCURRENCE_SEQUENCE"]
      )
    }
    guard sourceCount <= sourceOccurrences.count,
      let sourceStart = sourceOccurrences.indices.first(where: { start in
        guard start + sourceCount <= sourceOccurrences.count else { return false }
        return Array(sourceOccurrences[start..<(start + sourceCount)].map(\.id))
          == reviewedTemplate.sourceOccurrenceIDs
      })
    else {
      return RoutePlanExpansionResult(
        status: .rejected,
        errorCodes: ["REVIEWED_LAP_SEQUENCE_NOT_FOUND"]
      )
    }

    let newIDs = Set(request.newOccurrenceIDs)
    guard !request.newOccurrenceIDs.contains(where: \.isEmpty) else {
      return RoutePlanExpansionResult(
        status: .rejected,
        errorCodes: ["INVALID_OCCURRENCE_ID"]
      )
    }
    guard newIDs.count == request.newOccurrenceIDs.count,
      newIDs.isDisjoint(with: existingIDs)
    else {
      return RoutePlanExpansionResult(
        status: .rejected,
        errorCodes: ["DUPLICATE_OCCURRENCE_ID"]
      )
    }

    let sourceSlice = sourceOccurrences[sourceStart..<(sourceStart + sourceCount)]
    let duplicated = zip(sourceSlice, request.newOccurrenceIDs).enumerated().map {
      offset, pair in
      let (source, newID) = pair
      return RouteOccurrence(
        id: newID,
        index: sourceOccurrences.count + offset,
        kind: source.kind,
        entityID: source.entityID,
        parkingAreaID: source.parkingAreaID,
        tollDomainID: source.tollDomainID,
        isOptional: source.isOptional
      )
    }
    let expandedPlan = RoutePlan(
      id: routePlan.id,
      networkSnapshotID: routePlan.networkSnapshotID,
      entryFacilityID: routePlan.entryFacilityID,
      exitFacilityID: routePlan.exitFacilityID,
      recoveryPolicy: routePlan.recoveryPolicy,
      actualDistanceKM: routePlan.actualDistanceKM,
      occurrences: sourceOccurrences + duplicated
    )
    return RoutePlanExpansionResult(status: .accepted, routePlan: expandedPlan)
  }

  public static func validate(
    routePlan: RoutePlan,
    componentRequirement: RouteComponentRequirement
  ) -> CompileResult {
    guard !componentRequirement.requiredEntityIDsInOrder.isEmpty else {
      return CompileResult(
        status: .rejected,
        errorCodes: ["EMPTY_ROUTE_COMPONENT_REQUIREMENT"]
      )
    }

    var nextRequiredIndex = 0
    var validated: [String] = []
    for occurrence in routePlan.occurrences
    where nextRequiredIndex < componentRequirement.requiredEntityIDsInOrder.count {
      let requiredID = componentRequirement.requiredEntityIDsInOrder[nextRequiredIndex]
      if occurrence.entityID == requiredID {
        validated.append(requiredID)
        nextRequiredIndex += 1
      }
    }

    let unresolved = Array(
      componentRequirement.requiredEntityIDsInOrder.dropFirst(nextRequiredIndex)
    )
    guard unresolved.isEmpty else {
      return CompileResult(
        status: .rejected,
        errorCodes: ["MISSING_OR_OUT_OF_ORDER_ROUTE_COMPONENT"],
        validatedRequiredEntityIDs: validated,
        unresolvedRequiredEntityIDs: unresolved
      )
    }
    return CompileResult(
      status: .accepted,
      validatedRequiredEntityIDs: validated
    )
  }

  public static func validate(
    routePlan: RoutePlan,
    tollDomainPolicy: TollDomainPolicy
  ) -> CompileResult {
    var crossedDomainIDs: [String] = []
    var boundaryOccurrenceIDs: [String] = []
    var hasUnclassifiedOccurrence = false

    for occurrence in routePlan.occurrences {
      guard let domainID = occurrence.tollDomainID else {
        if tollDomainPolicy.requiresEveryOccurrenceClassified {
          hasUnclassifiedOccurrence = true
          boundaryOccurrenceIDs.append(occurrence.id)
        }
        continue
      }
      guard !tollDomainPolicy.allowedTollDomainIDs.contains(domainID) else { continue }
      boundaryOccurrenceIDs.append(occurrence.id)
      if !crossedDomainIDs.contains(domainID) {
        crossedDomainIDs.append(domainID)
      }
    }

    var errorCodes: [String] = []
    if !crossedDomainIDs.isEmpty {
      errorCodes.append("EXTERNAL_TOLL_DOMAIN_BOUNDARY")
    }
    if hasUnclassifiedOccurrence {
      errorCodes.append("UNCLASSIFIED_TOLL_DOMAIN")
    }
    guard errorCodes.isEmpty else {
      return CompileResult(
        status: .rejected,
        errorCodes: errorCodes,
        crossedTollDomainIDs: crossedDomainIDs,
        boundaryOccurrenceIDs: boundaryOccurrenceIDs
      )
    }
    return CompileResult(status: .accepted)
  }

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

  public static func validate(
    parkingAreaPath request: ParkingAreaPathRequest,
    releasedPaths: [DirectionalParkingAreaPath]
  ) -> CompileResult {
    let exists = releasedPaths.contains { path in
      path.parkingAreaID == request.parkingAreaID
        && path.sourceCarriagewayID == request.sourceCarriagewayID
        && path.accessMovementID == request.accessMovementID
        && path.returnMovementID == request.returnMovementID
        && path.returnCarriagewayID == request.returnCarriagewayID
    }
    guard exists else {
      return CompileResult(
        status: .rejected,
        errorCodes: ["MISSING_DIRECTIONAL_PA_PATH"]
      )
    }
    return CompileResult(status: .accepted)
  }
}
