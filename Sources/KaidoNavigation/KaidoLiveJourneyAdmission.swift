import KaidoDomain

public enum KaidoLiveJourneyAdmissionError:
  Error, Equatable, Sendable
{
  case selectedRoutePlanMismatch
  case foregroundLiveInputAuthorityMissing
  case releasedSurfaceAccessRequired
  case releasedSurfaceEgressRequired
}

/// Immutable authority binding for one user-selected live journey.
///
/// The selected RoutePlan is compared by full value, not by an ID supplied by
/// UI code. A foreground authority and both released surface legs are required
/// before Core Location may be attached to the runtime.
public struct KaidoLiveJourneyAdmission: Sendable {
  public let release: KaidoProductRelease
  public let selectedRoutePlan: RoutePlan
  public let journeyPlan: JourneyPlan
  public let foregroundLiveInputAuthority: KaidoForegroundLiveInputAuthority

  public init(
    release: KaidoProductRelease,
    selectedRoutePlan: RoutePlan,
    journeyPlan: JourneyPlan
  ) throws {
    guard release.navigation.bundle.routePlan == selectedRoutePlan else {
      throw KaidoLiveJourneyAdmissionError.selectedRoutePlanMismatch
    }
    guard let authority = release.foregroundLiveInputAuthority else {
      throw
        KaidoLiveJourneyAdmissionError
        .foregroundLiveInputAuthorityMissing
    }
    guard journeyPlan.accessLeg != nil else {
      throw KaidoLiveJourneyAdmissionError.releasedSurfaceAccessRequired
    }
    guard journeyPlan.egressLeg != nil else {
      throw KaidoLiveJourneyAdmissionError.releasedSurfaceEgressRequired
    }

    // This validates every release, RoutePlan, provider, surface-leg, matcher,
    // DecisionZone, guidance, entry, recovery, and egress identity together.
    _ = try KaidoProductNavigationRuntime(
      release: release,
      journeyPlan: journeyPlan
    )

    self.release = release
    self.selectedRoutePlan = selectedRoutePlan
    self.journeyPlan = journeyPlan
    foregroundLiveInputAuthority = authority
  }

  public func makeRuntime() throws -> KaidoProductNavigationRuntime {
    try KaidoProductNavigationRuntime(
      release: release,
      journeyPlan: journeyPlan
    )
  }
}
