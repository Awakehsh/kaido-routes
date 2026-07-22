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
