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
    self.release = release
    session = try NavigationSession(
      navigationConfiguration: NavigationConfiguration(
        routePlan: bundle.routePlan,
        releasedGuidance: bundle.releasedGuidance
      ),
      matcherCorridor: bundle.matcherCorridor,
      decisionZones: bundle.decisionZones
    )
  }
}
