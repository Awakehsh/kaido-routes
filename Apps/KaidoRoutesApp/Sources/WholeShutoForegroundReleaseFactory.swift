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
    },
    driveRecordPreferenceStore: UserDefaults = .standard
  ) -> WholeShutoProductModel {
    do {
      let database = try WholeShutoNetworkCatalog.bundled()
      return WholeShutoProductModel(
        database: database,
        surfaceRouteResolver: surfaceRouteResolver,
        checkpointStore: checkpointStore,
        speechOutput: speechOutput,
        liveJourneyAdmissions: [],
        liveJourneyAdmissionResolver: { route in
          let foregroundEntries: [BundledProductReleaseEntry]
          do {
            foregroundEntries = try BundledProductReleaseCatalogLoader
              .bundledForeground().foregroundNavigationEntries
          } catch {
            return .unavailable(
              WholeShutoRouteReleaseAuthority.runtimeInvalidCode
            )
          }
          let matches = foregroundEntries.filter {
            $0.release.navigation.bundle.routePlan == route.routePlan
          }
          switch matches.count {
          case 0:
            do {
              return try WholeShutoRouteReleaseAuthority(database: database)
                .resolve(route: route)
            } catch {
              return .unavailable(
                WholeShutoRouteReleaseAuthority.runtimeInvalidCode
              )
            }
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
        nowMillisecondsProvider: nowMillisecondsProvider,
        driveRecordPreferenceStore: driveRecordPreferenceStore
      )
    } catch {
      preconditionFailure("Invalid bundled Whole-Shuto foreground release: \(error)")
    }
  }
}
