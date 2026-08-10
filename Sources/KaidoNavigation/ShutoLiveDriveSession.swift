import Foundation
import KaidoDomain
import KaidoRouting

/// A live drive over one compiled whole-Shuto route.
///
/// Position comes from real device observations instead of a synthetic
/// trace, and the session owns the same `NavigationSession` reducer the
/// labeled preview uses — so strict-route progress, wrong-turn recovery, and
/// reviewed guidance prompts behave identically in both modes.
///
/// Authority boundaries are unchanged. Road identity comes from the bundled
/// dated snapshot the route was planned on, and turn-by-turn guidance still
/// comes only from reviewed movements: an unreviewed junction yields
/// progress and distance without inventing an instruction. The session
/// therefore never asserts released per-route navigation authority; it
/// asserts exactly what the snapshot and the reviewed guidance set support.
public actor ShutoLiveDriveSession {
  public let routePlanID: String
  public let networkSnapshotID: String

  private let session: NavigationSession
  private var hasStarted = false

  public init(
    assets: ShutoPlannedRouteRuntimeAssets
  ) throws {
    routePlanID = assets.routePlan.id
    networkSnapshotID = assets.matcherCorridor.networkSnapshotID
    guard let firstOccurrenceID = assets.routePlan.occurrences.first?.id
    else {
      throw ShutoLiveDriveSessionError.emptyRoutePlan
    }
    // The drive begins on ordinary roads, so the matcher is seeded at the
    // route head and reports LOW until real geometry confirms the vehicle
    // is on the selected carriageway. Progress is never admitted from the
    // seed alone.
    var seeded = NavigationSnapshot(
      journeyPhase: .strictRoute,
      activeRoutePlanID: assets.routePlan.id,
      currentOccurrenceID: firstOccurrenceID,
      locationConfidence: .low
    )
    seeded.lastPhaseTransitionTrigger = "WHOLE_SHUTO_LIVE_STRICT_ROUTE_SEED"
    session = try NavigationSession(
      navigationConfiguration: NavigationConfiguration(
        routePlan: assets.routePlan,
        recoveryCandidates: assets.recoveryCandidates,
        releasedGuidance: assets.releasedGuidance,
        allowsUserConfirmedExitHandoffCompletion: true
      ),
      matcherCorridor: assets.matcherCorridor,
      decisionZones: assets.decisionZones,
      initialNavigationSnapshot: seeded,
      initialMatcherOccurrenceID: firstOccurrenceID
    )
  }

  @discardableResult
  public func start() async -> NavigationSnapshot {
    guard !hasStarted else { return await session.snapshot }
    hasStarted = true
    return await session.start()
  }

  /// Feeds one real observation. Throws only on an invalid or out-of-order
  /// observation; an unmatchable position returns a LOW estimate instead,
  /// so the caller holds its last admitted progress and shows degradation.
  public func observe(
    _ observation: RouteMatcherObservation
  ) async throws -> NavigationSessionUpdate {
    await start()
    return try await session.observe(observation)
  }

  @discardableResult
  public func finishDrive() async -> NavigationSnapshot {
    await session.finishDrive()
  }

  public var snapshot: NavigationSnapshot {
    get async { await session.snapshot }
  }
}

public enum ShutoLiveDriveSessionError: Error, Equatable, Sendable {
  case emptyRoutePlan
}
