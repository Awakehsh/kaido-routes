import KaidoRouting
import Testing

@Test("Entrance recommendation explains a farther compatible directional facility")
func entranceRecommendationExplainsDirectionalCompatibility() throws {
  let recommendation = EntranceRecommender.recommend(
    candidates: [
      candidate(
        facilityID: "test.entry.nearest.westbound",
        carriagewayID: "test.carriageway.westbound",
        distanceKM: 0.5,
        etaMinutes: 3,
        joins: []
      ),
      candidate(
        facilityID: "test.entry.unknown.eastbound",
        carriagewayID: "test.carriageway.eastbound",
        distanceKM: 0.9,
        etaMinutes: 4,
        joins: ["test.occurrence.join.eastbound"],
        availability: .unknown
      ),
      candidate(
        facilityID: "test.entry.reviewed.eastbound",
        carriagewayID: "test.carriageway.eastbound",
        distanceKM: 1.8,
        etaMinutes: 7,
        joins: ["test.occurrence.join.eastbound"]
      ),
    ],
    allowedJoinOccurrenceIDs: ["test.occurrence.join.eastbound"]
  )

  #expect(recommendation.status == .selected)
  #expect(recommendation.errorCodes.isEmpty)
  let selection = try #require(recommendation.selection)
  #expect(selection.facilityID == "test.entry.reviewed.eastbound")
  #expect(selection.targetCarriagewayID == "test.carriageway.eastbound")
  #expect(selection.joinOccurrenceID == "test.occurrence.join.eastbound")
  #expect(selection.straightLineDistanceRank == 3)
  #expect(selection.surfaceETAMinutes == 7)
  #expect(
    selection.reasonCodes == [
      .exactDirectionalCarriageway,
      .legalRouteJoin,
      .approachAvailableAtEntryTime,
      .lowestSurfaceETAAfterHardFilters,
    ]
  )
  #expect(
    recommendation.rejections["test.entry.nearest.westbound"] == [
      "NO_LEGAL_ROUTE_JOIN"
    ]
  )
  #expect(
    recommendation.rejections["test.entry.unknown.eastbound"] == [
      "APPROACH_AVAILABILITY_UNKNOWN"
    ]
  )
}

@Test("Entrance recommendation rejects invalid candidate identity or metrics")
func entranceRecommendationRejectsInvalidInputs() {
  let duplicate = candidate(
    facilityID: "test.entry.duplicate",
    carriagewayID: "test.carriageway.eastbound",
    distanceKM: 1,
    etaMinutes: 4,
    joins: ["test.join"]
  )
  let recommendation = EntranceRecommender.recommend(
    candidates: [
      duplicate,
      duplicate,
      candidate(
        facilityID: "test.entry.invalid-metric",
        carriagewayID: "test.carriageway.eastbound",
        distanceKM: .infinity,
        etaMinutes: 5,
        joins: ["test.join"]
      ),
    ],
    allowedJoinOccurrenceIDs: ["test.join"]
  )

  #expect(recommendation.status == .rejected)
  #expect(recommendation.selection == nil)
  #expect(
    recommendation.errorCodes == [
      "DUPLICATE_ENTRANCE_FACILITY_ID",
      "INVALID_ENTRANCE_CANDIDATE_METRIC",
    ]
  )
}

@Test("Entrance recommendation distinguishes no eligible facility from invalid input")
func entranceRecommendationReportsNoEligibleCandidate() {
  let recommendation = EntranceRecommender.recommend(
    candidates: [
      candidate(
        facilityID: "test.entry.closed",
        carriagewayID: "test.carriageway.eastbound",
        distanceKM: 0.6,
        etaMinutes: 3,
        joins: ["test.join"],
        availability: .unavailable
      ),
      candidate(
        facilityID: "test.entry.wrong-route",
        carriagewayID: "test.carriageway.westbound",
        distanceKM: 0.4,
        etaMinutes: 2,
        joins: []
      ),
    ],
    allowedJoinOccurrenceIDs: ["test.join"]
  )

  #expect(recommendation.status == .noEligibleCandidate)
  #expect(recommendation.selection == nil)
  #expect(recommendation.errorCodes.isEmpty)
  #expect(
    recommendation.rejections["test.entry.closed"] == [
      "APPROACH_UNAVAILABLE_AT_ENTRY_TIME"
    ]
  )
  #expect(
    recommendation.rejections["test.entry.wrong-route"] == [
      "NO_LEGAL_ROUTE_JOIN"
    ]
  )
}

private func candidate(
  facilityID: String,
  carriagewayID: String,
  distanceKM: Double,
  etaMinutes: Double,
  joins: Set<String>,
  availability: EntranceApproachAvailability = .available
) -> EntranceCandidate {
  EntranceCandidate(
    facilityID: facilityID,
    targetCarriagewayID: carriagewayID,
    straightLineDistanceKM: distanceKM,
    surfaceETAMinutes: etaMinutes,
    legalJoinOccurrenceIDs: joins,
    approachAvailability: availability
  )
}
