import KaidoNavigation
import KaidoRouting

enum WholeShutoLiveJourneyAdmissionResolution: Sendable {
  case available(WholeShutoLiveJourneyAdmission)
  case unavailable(String)
}

typealias WholeShutoLiveJourneyAdmissionResolver =
  @Sendable (ShutoPlannedRoute)
  -> WholeShutoLiveJourneyAdmissionResolution

/// Content-addressed on-device authoring for one exact RoutePlan.
///
/// The application may derive a foreground product release only from the
/// bundled, validated network and its released junction catalog. The selected
/// plan is reconstructed first, every route decision must already have
/// source-bound guidance, and the resulting product release is validated by
/// the normal `KaidoProductRelease` runtime gate before Core Location can be
/// attached.
struct WholeShutoRouteReleaseAuthority: Sendable {
  static let guidanceIncompleteCode =
    "WHOLE_SHUTO_NAVIGATION_GUIDANCE_INCOMPLETE"
  static let recoveryUnavailableCode =
    "WHOLE_SHUTO_NAVIGATION_RECOVERY_UNAVAILABLE"
  static let runtimeInvalidCode =
    "WHOLE_SHUTO_NAVIGATION_RUNTIME_INVALID"

  let database: ShutoNetworkDatabase
  let runtimeContext: ShutoPlannedRouteRuntimeCompiler.NetworkContext

  init(database: ShutoNetworkDatabase) throws {
    self.database = database
    runtimeContext = try ShutoPlannedRouteRuntimeCompiler.NetworkContext(
      database: database
    )
  }

  func resolve(
    route selectedRoute: ShutoPlannedRoute
  ) -> WholeShutoLiveJourneyAdmissionResolution {
    do {
      let reconstructed = try ShutoRoutePlanner(database: database)
        .restore(routePlan: selectedRoute.routePlan)
      guard reconstructed == selectedRoute else {
        return .unavailable(Self.runtimeInvalidCode)
      }
      let release =
        try ShutoCircuitProductReleaseBuilder
        .buildPlannedRouteRelease(
          context: runtimeContext,
          route: reconstructed
        )
      let core = try KaidoLiveJourneyAdmission(
        release: release,
        selectedRoutePlan: reconstructed.routePlan,
        journeyPlan: JourneyPlanCompiler.expresswayOnly(release: release)
      )
      return .available(
        try WholeShutoLiveJourneyAdmission(core: core)
      )
    } catch let error as ShutoCircuitProductReleaseBuilderError {
      switch error {
      case .incompleteJunctionGuidance, .missingReviewedMovement,
        .invalidReviewedMovementOrder, .unsupportedCircuit:
        return .unavailable(Self.guidanceIncompleteCode)
      case .missingRecoveryCandidate:
        return .unavailable(Self.recoveryUnavailableCode)
      case .missingEntryPredecessor, .missingGraphEdge, .missingGraphNode,
        .inconsistentRepeatedEntity:
        return .unavailable(Self.runtimeInvalidCode)
      }
    } catch {
      return .unavailable(Self.runtimeInvalidCode)
    }
  }
}
