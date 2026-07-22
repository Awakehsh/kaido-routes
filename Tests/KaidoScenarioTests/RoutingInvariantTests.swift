import KaidoDomain
import KaidoRouting
import Testing

@Test("A legal movement must match the exact junction complex")
func legalMovementMatchesExactJunction() {
  let request = DirectedMovementRequest(
    incomingApproachID: "test.approach",
    junctionComplexID: "test.junction.requested",
    outgoingCarriagewayID: "test.carriageway"
  )
  let sameRoadsAtAnotherJunction = LegalMovement(
    id: "test.movement.other-junction",
    incomingApproachID: "test.approach",
    junctionComplexID: "test.junction.other",
    outgoingCarriagewayID: "test.carriageway"
  )

  let result = StrictRouteCompiler.validate(
    movement: request,
    legalMovements: [sameRoadsAtAnotherJunction]
  )

  #expect(result.status == .rejected)
  #expect(result.errorCodes.contains("ILLEGAL_JUNCTION_MOVEMENT"))
}

@Test("A parking-area path requires exact access and return directions")
func parkingAreaPathRequiresExactDirections() {
  let request = ParkingAreaPathRequest(
    parkingAreaID: "test.pa",
    sourceCarriagewayID: "test.carriageway.outer",
    accessMovementID: "test.movement.access",
    returnMovementID: "test.movement.return",
    returnCarriagewayID: "test.carriageway.outer"
  )
  let exact = DirectionalParkingAreaPath(
    id: "test.pa-path.outer",
    parkingAreaID: "test.pa",
    sourceCarriagewayID: "test.carriageway.outer",
    accessMovementID: "test.movement.access",
    returnMovementID: "test.movement.return",
    returnCarriagewayID: "test.carriageway.outer"
  )
  let wrongReturn = DirectionalParkingAreaPath(
    id: "test.pa-path.wrong-return",
    parkingAreaID: "test.pa",
    sourceCarriagewayID: "test.carriageway.outer",
    accessMovementID: "test.movement.access",
    returnMovementID: "test.movement.return",
    returnCarriagewayID: "test.carriageway.inner"
  )

  let rejected = StrictRouteCompiler.validate(
    parkingAreaPath: request,
    releasedPaths: [wrongReturn]
  )
  let accepted = StrictRouteCompiler.validate(
    parkingAreaPath: request,
    releasedPaths: [exact]
  )

  #expect(rejected.status == .rejected)
  #expect(rejected.errorCodes == ["MISSING_DIRECTIONAL_PA_PATH"])
  #expect(accepted.status == .accepted)
}

@Test("Adding a reviewed lap creates fresh occurrences without aliasing the source")
func addingReviewedLapCreatesFreshOccurrences() {
  let routePlan = RoutePlan(
    id: "test.plan.one-lap",
    entryFacilityID: "test.entry",
    exitFacilityID: "test.exit",
    recoveryPolicy: .strict,
    occurrences: [
      RouteOccurrence(
        id: "lap-1-edge",
        index: 0,
        kind: .edge,
        entityID: "test.edge.circuit",
        tollDomainID: "test.toll.shuto"
      ),
      RouteOccurrence(
        id: "lap-1-movement",
        index: 1,
        kind: .junctionMovement,
        entityID: "test.movement.circuit",
        tollDomainID: "test.toll.shuto"
      ),
    ]
  )
  let template = ReviewedLapTemplate(
    id: "test.template.reviewed-lap",
    sourceOccurrenceIDs: ["lap-1-edge", "lap-1-movement"]
  )

  let accepted = StrictRouteCompiler.appendLap(
    to: routePlan,
    request: LapDuplicationRequest(
      reviewedTemplateID: template.id,
      newOccurrenceIDs: ["lap-2-edge", "lap-2-movement"]
    ),
    reviewedTemplate: template
  )
  let rejected = StrictRouteCompiler.appendLap(
    to: routePlan,
    request: LapDuplicationRequest(
      reviewedTemplateID: template.id,
      newOccurrenceIDs: ["lap-1-edge", "lap-2-movement"]
    ),
    reviewedTemplate: template
  )
  let malformedPlan = RoutePlan(
    id: routePlan.id,
    entryFacilityID: routePlan.entryFacilityID,
    exitFacilityID: routePlan.exitFacilityID,
    recoveryPolicy: routePlan.recoveryPolicy,
    occurrences: [
      RouteOccurrence(
        id: "lap-1-edge",
        index: 1,
        kind: .edge,
        entityID: "test.edge.circuit"
      ),
      RouteOccurrence(
        id: "lap-1-edge",
        index: 2,
        kind: .junctionMovement,
        entityID: "test.movement.circuit"
      ),
    ]
  )
  let malformed = StrictRouteCompiler.appendLap(
    to: malformedPlan,
    request: LapDuplicationRequest(
      reviewedTemplateID: template.id,
      newOccurrenceIDs: ["lap-2-edge", "lap-2-movement"]
    ),
    reviewedTemplate: template
  )

  #expect(accepted.status == .accepted)
  #expect(
    accepted.routePlan?.occurrences.map(\.id) == [
      "lap-1-edge", "lap-1-movement", "lap-2-edge", "lap-2-movement",
    ])
  #expect(
    accepted.routePlan?.occurrences.map(\.entityID) == [
      "test.edge.circuit", "test.movement.circuit",
      "test.edge.circuit", "test.movement.circuit",
    ])
  #expect(accepted.routePlan?.occurrences.map(\.index) == [0, 1, 2, 3])
  #expect(accepted.routePlan?.occurrences.last?.tollDomainID == "test.toll.shuto")
  #expect(rejected.errorCodes == ["DUPLICATE_OCCURRENCE_ID"])
  #expect(malformed.errorCodes == ["INVALID_ROUTE_OCCURRENCE_SEQUENCE"])
}

@Test("A reviewed circuit template requires every directional component in order")
func circuitTemplateRequiresEveryComponentInOrder() {
  let requirement = RouteComponentRequirement(
    templateID: "test.template.c2-b-circuit",
    requiredEntityIDsInOrder: [
      "test.route.c2-arc",
      "test.movement.c2-to-b",
      "test.route.b-connector",
      "test.movement.b-to-c2",
    ]
  )
  let acceptedPlan = routePlan(entityIDs: requirement.requiredEntityIDsInOrder)
  let wrongOrderPlan = routePlan(entityIDs: [
    "test.route.c2-arc",
    "test.route.b-connector",
    "test.movement.c2-to-b",
    "test.movement.b-to-c2",
  ])

  let accepted = StrictRouteCompiler.validate(
    routePlan: acceptedPlan,
    componentRequirement: requirement
  )
  let rejected = StrictRouteCompiler.validate(
    routePlan: wrongOrderPlan,
    componentRequirement: requirement
  )

  #expect(accepted.status == .accepted)
  #expect(accepted.validatedRequiredEntityIDs == requirement.requiredEntityIDsInOrder)
  #expect(rejected.status == .rejected)
  #expect(rejected.errorCodes == ["MISSING_OR_OUT_OF_ORDER_ROUTE_COMPONENT"])
  #expect(
    rejected.unresolvedRequiredEntityIDs == [
      "test.route.b-connector", "test.movement.b-to-c2",
    ])
}

@Test("A route cannot hide external or unclassified toll-domain occurrences")
func routeCannotHideTollDomainBoundaries() {
  let routePlan = RoutePlan(
    id: "test.plan.toll-boundary",
    entryFacilityID: "test.entry",
    exitFacilityID: "test.exit",
    recoveryPolicy: .strict,
    occurrences: [
      RouteOccurrence(
        id: "shuto-edge",
        index: 0,
        kind: .edge,
        entityID: "test.edge.shuto",
        tollDomainID: "test.toll.shuto"
      ),
      RouteOccurrence(
        id: "external-edge",
        index: 1,
        kind: .edge,
        entityID: "test.edge.external",
        tollDomainID: "test.toll.external"
      ),
      RouteOccurrence(
        id: "unknown-edge",
        index: 2,
        kind: .edge,
        entityID: "test.edge.unknown"
      ),
    ]
  )

  let result = StrictRouteCompiler.validate(
    routePlan: routePlan,
    tollDomainPolicy: TollDomainPolicy(
      allowedTollDomainIDs: ["test.toll.shuto"]
    )
  )

  #expect(result.status == .rejected)
  #expect(
    result.errorCodes == [
      "EXTERNAL_TOLL_DOMAIN_BOUNDARY", "UNCLASSIFIED_TOLL_DOMAIN",
    ])
  #expect(result.crossedTollDomainIDs == ["test.toll.external"])
  #expect(result.boundaryOccurrenceIDs == ["external-edge", "unknown-edge"])
}

private func routePlan(entityIDs: [String]) -> RoutePlan {
  RoutePlan(
    id: "test.plan.components",
    entryFacilityID: "test.entry",
    exitFacilityID: "test.exit",
    recoveryPolicy: .strict,
    occurrences: entityIDs.enumerated().map { index, entityID in
      RouteOccurrence(
        id: "occurrence-\(index)",
        index: index,
        kind: .edge,
        entityID: entityID,
        tollDomainID: "test.toll.shuto"
      )
    }
  )
}

@Test("Tariff selection requires exactly one active version")
func tariffSelectionRequiresUniqueActiveVersion() {
  let proposed = TariffCandidate(
    quoteID: "test.quote.proposed",
    tariffVersionID: "test.tariff.proposed",
    versionStatus: .proposed
  )
  let active = TariffCandidate(
    quoteID: "test.quote.active",
    tariffVersionID: "test.tariff.active",
    versionStatus: .active
  )

  let selected = TariffSelector.selectCurrent(from: [proposed, active])
  let ambiguous = TariffSelector.selectCurrent(from: [active, active])
  let noActive = TariffSelector.selectCurrent(from: [proposed])

  #expect(selected.status == .selected)
  #expect(selected.selectedCandidate == active)
  #expect(selected.ignoredNonActiveQuoteIDs == [proposed.quoteID])
  #expect(ambiguous.status == .rejected)
  #expect(ambiguous.errorCodes == ["NO_UNIQUE_ACTIVE_TARIFF"])
  #expect(noActive.status == .rejected)
  #expect(noActive.errorCodes == ["NO_UNIQUE_ACTIVE_TARIFF"])
}
