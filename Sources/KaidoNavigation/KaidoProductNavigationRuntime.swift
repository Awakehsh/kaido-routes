import KaidoDomain

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

  public init(release: KaidoProductRelease) throws {
    let bundle = release.navigation.bundle
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
    self.release = release
    self.entryTransitionAdmissionContext = entryTransitionAdmissionContext
    session = try NavigationSession(
      navigationConfiguration: NavigationConfiguration(
        routePlan: bundle.routePlan,
        entryTransition: bundle.runtimePolicy.entryTransition,
        recoveryCandidates: bundle.runtimePolicy.recoveryCandidates,
        egressOptions: bundle.runtimePolicy.egressOptions,
        releasedGuidance: bundle.releasedGuidance
      ),
      matcherCorridor: bundle.matcherCorridor,
      decisionZones: bundle.decisionZones,
      entryTransitionAdmissionContext: entryTransitionAdmissionContext
    )
  }
}
