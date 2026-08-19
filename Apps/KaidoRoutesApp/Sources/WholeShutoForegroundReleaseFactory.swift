import Foundation
import KaidoAppleAdapters
import KaidoNavigation

@MainActor
enum WholeShutoForegroundReleaseFactory {
  static func makeModel(
    surfaceRouteResolver: any WholeShutoSurfaceRouteResolving =
      WholeShutoMapKitSurfaceRouteResolver(),
    checkpointStore: (any WholeShutoJourneyCheckpointStoring)? =
      WholeShutoUserDefaultsCheckpointStore(),
    liveLocationSource: (any ForegroundNavigationLocationSource)? = nil,
    speechOutput: (any GuidanceSpeechOutput)? = nil,
    nowMillisecondsProvider: @escaping () -> Int = {
      Int((Date().timeIntervalSince1970 * 1_000).rounded())
    }
  ) -> WholeShutoProductModel {
    do {
      let database = try WholeShutoNetworkCatalog.bundled()
      let catalog =
        try BundledProductReleaseCatalogLoader.bundledForeground()
      guard !catalog.foregroundNavigationEntries.isEmpty else {
        preconditionFailure("Invalid bundled Whole-Shuto foreground catalog")
      }
      let foregroundEntries = catalog.foregroundNavigationEntries
      let routeReleaseAuthority = try WholeShutoRouteReleaseAuthority(
        database: database
      )
      return WholeShutoProductModel(
        database: database,
        surfaceRouteResolver: surfaceRouteResolver,
        checkpointStore: checkpointStore,
        speechOutput: speechOutput,
        liveJourneyAdmissions: [],
        releasedForegroundRoutePlans: foregroundEntries.map {
          $0.release.navigation.bundle.routePlan
        },
        liveJourneyAdmissionResolver: { route in
          let matches = foregroundEntries.filter {
            $0.release.navigation.bundle.routePlan == route.routePlan
          }
          switch matches.count {
          case 0:
            return routeReleaseAuthority.resolve(route: route)
          case 1:
            do {
              let release = matches[0].release
              let core = try KaidoLiveJourneyAdmission(
                release: release,
                selectedRoutePlan: route.routePlan,
                journeyPlan: JourneyPlanCompiler.expresswayOnly(
                  release: release
                )
              )
              return .available(
                try WholeShutoLiveJourneyAdmission(core: core)
              )
            } catch {
              return .unavailable(
                WholeShutoRouteReleaseAuthority.runtimeInvalidCode
              )
            }
          default:
            return .unavailable(
              WholeShutoRouteReleaseAuthority.ambiguousReleaseCode
            )
          }
        },
        liveLocationSource: liveLocationSource,
        nowMillisecondsProvider: nowMillisecondsProvider
      )
    } catch {
      preconditionFailure("Invalid bundled Whole-Shuto foreground release: \(error)")
    }
  }
}
