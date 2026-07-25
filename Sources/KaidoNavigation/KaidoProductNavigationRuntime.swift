import KaidoDomain

public enum KaidoProductNavigationRuntimeOrigin: String, Equatable, Sendable {
  case fresh = "FRESH"
  case restored = "RESTORED"
}

/// The product-facing live composition boundary.
///
/// External adapters cannot construct `NavigationSession` from independently
/// supplied runtime assets. They must first decode and validate one complete
/// `KaidoProductRelease`, then keep its Route Atlas and navigation session
/// together through this value.
public struct KaidoProductNavigationRuntime: Sendable {
  public let release: KaidoProductRelease
  public let session: NavigationSession
  public let entryTransitionAdmissionContext: EntryTransitionAdmissionContext
  public let surfaceEgressAdmissionContext: SurfaceEgressAdmissionContext?
  public let journeyPlan: JourneyPlan
  public let origin: KaidoProductNavigationRuntimeOrigin

  public var productReleaseID: String {
    release.releaseID
  }

  public var navigationReleaseID: String {
    release.navigation.releaseID
  }

  public var networkSnapshotID: String {
    release.navigation.bundle.networkSnapshot.id
  }

  public var routePlanID: String {
    release.navigation.bundle.routePlan.id
  }

  public var routeAtlas: RouteAtlasRelease {
    release.routeAtlas
  }

  public var runtimeIdentity: KaidoProductRuntimeIdentity {
    release.runtimeIdentity
  }

  public init(release: KaidoProductRelease) throws {
    try self.init(
      release: release,
      journeyPlan: JourneyPlanCompiler.routeOnly(release: release),
      checkpoint: nil
    )
  }

  public init(
    release: KaidoProductRelease,
    journeyPlan: JourneyPlan
  ) throws {
    try self.init(
      release: release,
      journeyPlan: journeyPlan,
      checkpoint: nil
    )
  }

  public init(
    release: KaidoProductRelease,
    checkpoint: NavigationSessionCheckpoint
  ) throws {
    try self.init(
      release: release,
      journeyPlan: JourneyPlanCompiler.routeOnly(release: release),
      checkpoint: checkpoint
    )
  }

  public init(
    release: KaidoProductRelease,
    journeyPlan: JourneyPlan,
    checkpoint: NavigationSessionCheckpoint
  ) throws {
    try self.init(
      release: release,
      journeyPlan: journeyPlan,
      checkpoint: Optional(checkpoint)
    )
  }

  private init(
    release: KaidoProductRelease,
    journeyPlan: JourneyPlan,
    checkpoint: NavigationSessionCheckpoint?
  ) throws {
    let bundle = release.navigation.bundle
    let journeyPlanIssues = journeyPlan.runtimeAdmissionIssues(for: release)
    guard journeyPlanIssues.isEmpty else {
      throw JourneyPlanRuntimeAdmissionError.invalid(journeyPlanIssues)
    }
    guard let firstRouteOccurrence = bundle.routePlan.occurrences.first,
      let firstRouteBinding = bundle.matcherCorridor.occurrences.first(where: {
        $0.id == firstRouteOccurrence.id && $0.index == firstRouteOccurrence.index
      })
    else {
      throw NavigationSessionConfigurationError.invalid([
        "entry transition first RoutePlan edge binding is missing"
      ])
    }
    let entryTransitionAdmissionContext = EntryTransitionAdmissionContext(
      productReleaseID: release.releaseID,
      navigationReleaseID: release.navigation.releaseID,
      runtimePolicyID: bundle.runtimePolicy.id,
      networkSnapshotID: bundle.networkSnapshot.id,
      routePlanID: bundle.routePlan.id,
      matcherCorridorID: bundle.matcherCorridor.id,
      entryTransition: bundle.runtimePolicy.entryTransition,
      matcherCorridor: bundle.matcherCorridor,
      firstRouteDirectedEdgeID: firstRouteBinding.directedEdgeID
    )
    let surfaceEgressAdmissionContext: SurfaceEgressAdmissionContext?
    if let selectedEgressOptionID =
      journeyPlan.selectedEgressOptionID,
      let egressLeg = journeyPlan.egressLeg,
      let definition = bundle.surfaceEgressDefinition,
      let policy = definition.policies.first(where: {
        $0.egressOptionID == selectedEgressOptionID
      })
    {
      surfaceEgressAdmissionContext = SurfaceEgressAdmissionContext(
        productReleaseID: release.releaseID,
        navigationReleaseID: release.navigation.releaseID,
        journeyPlanID: journeyPlan.id,
        runtimePolicyID: bundle.runtimePolicy.id,
        networkSnapshotID: bundle.networkSnapshot.id,
        routePlanID: bundle.routePlan.id,
        egressOptionID: selectedEgressOptionID,
        exitFacilityID: policy.exitFacilityID,
        handoffAnchorID: policy.originAnchor.id,
        directedSurfaceEdgeID:
          egressLeg.directedEdgeIDs.first ?? ""
      )
    } else {
      surfaceEgressAdmissionContext = nil
    }
    self.release = release
    self.entryTransitionAdmissionContext = entryTransitionAdmissionContext
    self.surfaceEgressAdmissionContext =
      surfaceEgressAdmissionContext
    self.journeyPlan = journeyPlan
    let initialSnapshot: NavigationSnapshot
    let initialMatcherOccurrenceID: String?
    let requiresRestorationReacquisition: Bool
    if let checkpoint {
      initialSnapshot = try checkpoint.restoredSnapshot(
        for: release,
        journeyPlan: journeyPlan
      )
      initialMatcherOccurrenceID = initialSnapshot.currentOccurrenceID
      requiresRestorationReacquisition =
        checkpoint.requiresMatcherReacquisition
      origin = .restored
    } else {
      var snapshot = NavigationSnapshot(
        journeyPhase: journeyPlan.initialPhase
      )
      if journeyPlan.accessLeg != nil {
        snapshot.lastPhaseTransitionTrigger =
          "RELEASED_SURFACE_ACCESS_PLAN_ADMITTED"
      }
      initialSnapshot = snapshot
      initialMatcherOccurrenceID = nil
      requiresRestorationReacquisition = false
      origin = .fresh
    }
    session = try NavigationSession(
      navigationConfiguration: NavigationConfiguration(
        routePlan: bundle.routePlan,
        entryTransition: bundle.runtimePolicy.entryTransition,
        recoveryCandidates: bundle.runtimePolicy.recoveryCandidates,
        egressOptions: bundle.runtimePolicy.egressOptions,
        selectedEgressOptionID: journeyPlan.selectedEgressOptionID,
        releasedGuidance: bundle.releasedGuidance
      ),
      matcherCorridor: bundle.matcherCorridor,
      decisionZones: bundle.decisionZones,
      initialNavigationSnapshot: initialSnapshot,
      initialMatcherOccurrenceID: initialMatcherOccurrenceID,
      entryTransitionAdmissionContext: entryTransitionAdmissionContext,
      surfaceEgressAdmissionContext:
        surfaceEgressAdmissionContext,
      requiresRestorationReacquisition:
        requiresRestorationReacquisition
    )
  }

  public func makeCheckpoint(
    savedAtMilliseconds: Int
  ) async throws -> NavigationSessionCheckpoint {
    try NavigationSessionCheckpoint.capture(
      release: release,
      journeyPlan: journeyPlan,
      snapshot: await session.snapshot,
      savedAtMilliseconds: savedAtMilliseconds
    )
  }
}
