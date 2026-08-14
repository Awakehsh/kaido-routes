import Foundation
import KaidoNavigation

@MainActor
enum WholeShutoForegroundReleaseFactory {
  static func makeModel(
    surfaceRouteResolver: any WholeShutoSurfaceRouteResolving =
      WholeShutoMapKitSurfaceRouteResolver(),
    checkpointStore: (any WholeShutoJourneyCheckpointStoring)? =
      WholeShutoUserDefaultsCheckpointStore()
  ) -> WholeShutoProductModel {
    do {
      let database = try WholeShutoNetworkCatalog.bundled()
      let catalog = try BundledProductReleaseCatalogLoader
        .bundledForeground()
      guard catalog.foregroundNavigationEntries.count == 1,
        let entry = catalog.foregroundNavigationEntries.first
      else {
        preconditionFailure("Invalid bundled Whole-Shuto foreground catalog")
      }
      let route = try ShutoCircuitProductReleaseBuilder.plannedRoute(
        database: database
      )
      let journeyPlan = JourneyPlanCompiler.expresswayOnly(
        release: entry.release
      )
      let core = try KaidoLiveJourneyAdmission(
        release: entry.release,
        selectedRoutePlan: route.routePlan,
        journeyPlan: journeyPlan
      )
      let admission = try WholeShutoLiveJourneyAdmission(core: core)
      return WholeShutoProductModel(
        database: database,
        surfaceRouteResolver: surfaceRouteResolver,
        checkpointStore: checkpointStore,
        liveJourneyAdmissions: [admission]
      )
    } catch {
      preconditionFailure("Invalid bundled Whole-Shuto foreground release: \(error)")
    }
  }
}
