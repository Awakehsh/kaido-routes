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
