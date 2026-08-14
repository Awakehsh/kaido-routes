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
      guard !catalog.foregroundNavigationEntries.isEmpty else {
        preconditionFailure("Invalid bundled Whole-Shuto foreground catalog")
      }
      let admissions = try catalog.foregroundNavigationEntries.map { entry in
        let journeyPlan = JourneyPlanCompiler.expresswayOnly(
          release: entry.release
        )
        let core = try KaidoLiveJourneyAdmission(
          release: entry.release,
          selectedRoutePlan: entry.release.navigation.bundle.routePlan,
          journeyPlan: journeyPlan
        )
        return try WholeShutoLiveJourneyAdmission(core: core)
      }
      return WholeShutoProductModel(
        database: database,
        surfaceRouteResolver: surfaceRouteResolver,
        checkpointStore: checkpointStore,
        liveJourneyAdmissions: admissions
      )
    } catch {
      preconditionFailure("Invalid bundled Whole-Shuto foreground release: \(error)")
    }
  }
}
