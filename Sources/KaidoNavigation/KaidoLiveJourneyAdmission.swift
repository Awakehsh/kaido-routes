import KaidoDomain

public enum KaidoLiveJourneyAdmissionError:
  Error, Equatable, Sendable
{
  case selectedRoutePlanMismatch
  case foregroundLiveInputAuthorityMissing
  case invalidJourneyComposition
}

/// Immutable authority binding for one user-selected live journey.
///
/// The selected RoutePlan is compared by full value, not by an ID supplied by
/// UI code. A foreground authority is required before Core Location may be
/// attached. The journey may either carry both released surface legs or use
/// the release-owned expressway-only entrance/exit handoff composition.
public struct KaidoLiveJourneyAdmission: Sendable {
  public let release: KaidoProductRelease
  public let selectedRoutePlan: RoutePlan
  public let journeyPlan: JourneyPlan
  public let foregroundLiveInputAuthority: KaidoForegroundLiveInputAuthority
  private let validatedRuntime: KaidoProductNavigationRuntime

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
    let hasCompleteSurfaceJourney =
      journeyPlan.accessLeg != nil && journeyPlan.egressLeg != nil
    let isExpresswayOnly =
      journeyPlan == JourneyPlanCompiler.expresswayOnly(release: release)
    guard hasCompleteSurfaceJourney || isExpresswayOnly else {
      throw KaidoLiveJourneyAdmissionError.invalidJourneyComposition
    }

    // Admission is an authority boundary. Do not expose foreground input
    // authority until the complete release and journey composition has passed
    // the same validation used to create a live runtime.
    let validatedRuntime = try KaidoProductNavigationRuntime(
      release: release,
      journeyPlan: journeyPlan
    )

    self.release = release
    self.selectedRoutePlan = selectedRoutePlan
    self.journeyPlan = journeyPlan
    foregroundLiveInputAuthority = authority
    self.validatedRuntime = validatedRuntime
  }

  public func makeRuntime() throws -> KaidoProductNavigationRuntime {
    validatedRuntime
  }
}
