import KaidoDomain

/// A live drive admitted by one validated product release.
///
/// Whole-Shuto route assets are useful for deterministic planning and replay,
/// but they are not navigation release authority. Callers must supply the
/// product runtime produced from a `KaidoProductRelease`; this type never
/// derives admission identities or released surface geometry from asset
/// hashes.
public actor ShutoLiveDriveSession {
  public nonisolated let routePlanID: String
  public nonisolated let networkSnapshotID: String
  public nonisolated let productReleaseID: String
  public nonisolated let navigationReleaseID: String
  public nonisolated let entryTransitionAdmissionContext:
    EntryTransitionAdmissionContext
  public nonisolated let surfaceEgressAdmissionContext:
    SurfaceEgressAdmissionContext?

  private let runtime: KaidoProductNavigationRuntime
  private let session: NavigationSession
  private var hasStarted = false

  public init(runtime: KaidoProductNavigationRuntime) throws {
    guard runtime.release.foregroundLiveInputAuthority != nil else {
      throw ShutoLiveDriveSessionError
        .navigationReleaseNotForegroundAuthorized
    }
    let hasCompleteSurfaceJourney =
      runtime.journeyPlan.accessLeg != nil
      && runtime.journeyPlan.egressLeg != nil
    let isExpresswayOnly =
      runtime.journeyPlan
      == JourneyPlanCompiler.expresswayOnly(release: runtime.release)
    guard hasCompleteSurfaceJourney || isExpresswayOnly else {
      throw ShutoLiveDriveSessionError.invalidJourneyComposition
    }
    routePlanID = runtime.routePlanID
    networkSnapshotID = runtime.networkSnapshotID
    productReleaseID = runtime.productReleaseID
    navigationReleaseID = runtime.navigationReleaseID
    entryTransitionAdmissionContext =
      runtime.entryTransitionAdmissionContext
    surfaceEgressAdmissionContext = runtime.surfaceEgressAdmissionContext
    self.runtime = runtime
    session = runtime.session
  }

  @discardableResult
  public func start() async -> NavigationSnapshot {
    guard !hasStarted else { return await session.snapshot }
    hasStarted = true
    return await session.start()
  }

  public func observeEntryTransitionEvidence(
    _ evidence: EntryTransitionEvidence
  ) async throws -> EntryTransitionSessionUpdate {
    await start()
    return try await session.observeEntryTransitionEvidence(evidence)
  }

  public func observe(
    _ observation: RouteMatcherObservation
  ) async throws -> NavigationSessionUpdate {
    await start()
    return try await session.observe(observation)
  }

  @discardableResult
  public func finishDrive() async -> NavigationSnapshot {
    await start()
    return await session.finishDrive()
  }

  public func observeSurfaceEgressHandoffEvidence(
    _ evidence: SurfaceEgressHandoffEvidence
  ) async -> SurfaceEgressHandoffSessionUpdate {
    await start()
    return await session.observeSurfaceEgressHandoffEvidence(evidence)
  }

  @discardableResult
  public func completeAtExitHandoff() async -> NavigationSnapshot {
    await session.completeAtExitHandoff()
  }

  public func makeCheckpoint(
    savedAtMilliseconds: Int
  ) async throws -> NavigationSessionCheckpoint {
    try await runtime.makeCheckpoint(
      savedAtMilliseconds: savedAtMilliseconds
    )
  }

  public var snapshot: NavigationSnapshot {
    get async { await session.snapshot }
  }
}

public enum ShutoLiveDriveSessionError: Error, Equatable, Sendable {
  case navigationReleaseNotForegroundAuthorized
  case invalidJourneyComposition
}
