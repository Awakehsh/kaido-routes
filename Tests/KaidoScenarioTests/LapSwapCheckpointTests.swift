import Foundation
import KaidoDomain
import KaidoNavigation
import KaidoRouting
import Testing

/// A lap added mid-drive replans the loop with one more lap. The drive moves
/// onto that plan where it stands, because the two plans are the same road
/// up to there.
@Suite("Carrying a drive onto a plan with one more lap")
struct LapSwapCheckpointTests {
  @Test("the drive carries over at the same occurrence on the strict route")
  func carriesTheDriveOverAtTheSameOccurrence() throws {
    let (twoLaps, threeLaps) = try daikokuLoopReleases()
    let plan = twoLaps.navigation.bundle.routePlan
    let boundaries = try lapBoundaries(twoLaps)
    // Partway through the second and last lap, before the exit tail.
    try #require(boundaries[1] + 100 < boundaries[2])
    let current = plan.occurrences[boundaries[1] + 100]
    let releasedPrompts = twoLaps.navigation.bundle.releasedGuidance.map(\.anchor.promptID)
    let threeLapPrompts = Set(threeLaps.navigation.bundle.releasedGuidance.map(\.anchor.promptID))
    let sharedPrompt = try #require(releasedPrompts.first(where: threeLapPrompts.contains))
    let tailPrompt = try #require(releasedPrompts.last { !threeLapPrompts.contains($0) })
    let checkpoint = try strictCheckpoint(
      release: twoLaps,
      at: current,
      emittedPromptIDs: [sharedPrompt, tailPrompt]
    )

    let journeyPlan = JourneyPlanCompiler.expresswayOnly(release: threeLaps)
    let carried = try checkpoint.carried(
      from: twoLaps,
      onto: threeLaps,
      journeyPlan: journeyPlan
    )
    #expect(carried.routePlanID == threeLaps.navigation.bundle.routePlan.id)
    #expect(carried.state.currentOccurrenceID == current.id)
    #expect(carried.state.journeyPhase == .strictRoute)
    // A cue the new plan does not release cannot carry over.
    #expect(carried.state.emittedGuidancePromptIDs == [sharedPrompt])

    let runtime = try KaidoProductNavigationRuntime(
      release: threeLaps,
      journeyPlan: journeyPlan,
      checkpoint: carried
    )
    let snapshot = try awaitSnapshot(runtime.session)
    #expect(snapshot.journeyPhase == .strictRoute)
    #expect(snapshot.currentOccurrenceIndex == current.index)
    // The new session places the car itself before it moves anything.
    #expect(snapshot.signalReacquisitionStatus == .pending)
  }

  @Test("a drive on a road only the old plan drives is not carried")
  func refusesWhereThePlansDiverge() throws {
    let (twoLaps, threeLaps) = try daikokuLoopReleases()
    let plan = twoLaps.navigation.bundle.routePlan
    let threeLapPlan = threeLaps.navigation.bundle.routePlan
    let divergence = try #require(
      plan.occurrences.indices.first { plan.occurrences[$0] != threeLapPlan.occurrences[$0] }
    )
    let checkpoint = try strictCheckpoint(
      release: twoLaps,
      at: plan.occurrences[divergence]
    )
    #expect(
      throws: NavigationSessionCheckpointError.invalid([.routePlanDiverges])
    ) {
      try checkpoint.carried(
        from: twoLaps,
        onto: threeLaps,
        journeyPlan: JourneyPlanCompiler.expresswayOnly(release: threeLaps)
      )
    }
  }

  @Test("a drive in route recovery is not carried")
  func refusesDuringRouteRecovery() throws {
    let (twoLaps, threeLaps) = try daikokuLoopReleases()
    let plan = twoLaps.navigation.bundle.routePlan
    var snapshot = NavigationSnapshot(
      journeyPhase: .routeRecovery,
      activeRoutePlanID: plan.id,
      currentOccurrenceID: plan.occurrences[200].id
    )
    snapshot.currentOccurrenceIndex = 200
    snapshot.strictRouteAutoCommitAllowed = true
    snapshot.recovery.status = .unavailable
    snapshot.recovery.objective = "REJOIN_ACTIVE_ROUTE_PLAN"
    snapshot.recovery.routePlanID = plan.id
    let checkpoint = try NavigationSessionCheckpoint.capture(
      release: twoLaps,
      journeyPlan: JourneyPlanCompiler.expresswayOnly(release: twoLaps),
      snapshot: snapshot,
      savedAtMilliseconds: 10_000
    )
    #expect(
      throws: NavigationSessionCheckpointError.invalid([.journeyPlanPhaseMismatch])
    ) {
      try checkpoint.carried(
        from: twoLaps,
        onto: threeLaps,
        journeyPlan: JourneyPlanCompiler.expresswayOnly(release: threeLaps)
      )
    }
  }

  private func strictCheckpoint(
    release: KaidoProductRelease,
    at occurrence: RouteOccurrence,
    emittedPromptIDs: [String] = []
  ) throws -> NavigationSessionCheckpoint {
    var snapshot = NavigationSnapshot(
      journeyPhase: .strictRoute,
      activeRoutePlanID: release.navigation.bundle.routePlan.id,
      currentOccurrenceID: occurrence.id
    )
    snapshot.currentOccurrenceIndex = occurrence.index
    snapshot.strictRouteAutoCommitAllowed = true
    snapshot.emittedGuidancePromptIDs = emittedPromptIDs
    snapshot.lastGuidancePromptID = emittedPromptIDs.last
    return try NavigationSessionCheckpoint.capture(
      release: release,
      journeyPlan: JourneyPlanCompiler.expresswayOnly(release: release),
      snapshot: snapshot,
      savedAtMilliseconds: 10_000
    )
  }

  private func lapBoundaries(_ release: KaidoProductRelease) throws -> [Int] {
    let plan = release.navigation.bundle.routePlan
    return try release.navigation.bundle.runtimePolicy.lapBoundaryOccurrenceIDs.map {
      try #require(plan.occurrence(id: $0)?.index)
    }
  }

  private func awaitSnapshot(_ session: NavigationSession) throws -> NavigationSnapshot {
    let box = SnapshotBox()
    let semaphore = DispatchSemaphore(value: 0)
    Task {
      box.snapshot = await session.snapshot
      semaphore.signal()
    }
    semaphore.wait()
    return try #require(box.snapshot)
  }

  private func daikokuLoopReleases() throws -> (KaidoProductRelease, KaidoProductRelease) {
    let database = try replayGateDatabase()
    let planner = try ShutoRoutePlanner(database: database)
    let context = try ShutoPlannedRouteRuntimeCompiler.NetworkContext(database: database)
    func release(laps: Int) throws -> KaidoProductRelease {
      try ShutoCircuitProductReleaseBuilder.buildPlannedRouteRelease(
        context: context,
        route: try planner.planCircuit(
          circuit: .daikokuYokohamaLoop,
          entryFacilityID: "shuto.ic.b.wangankanpachi",
          exitFacilityID: "shuto.ic.1-haneda.haneda",
          laps: laps
        )
      )
    }
    return (try release(laps: 2), try release(laps: 3))
  }
}

private final class SnapshotBox: @unchecked Sendable {
  var snapshot: NavigationSnapshot?
}
