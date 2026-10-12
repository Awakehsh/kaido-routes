import Foundation
import KaidoAppleAdapters
import KaidoNavigation
import KaidoPresentation
import KaidoRouting
import Synchronization

@MainActor
enum WholeShutoForegroundReleaseFactory {
  /// The bundled foreground releases are immutable, hash-pinned resources,
  /// so one verified load serves every route selection in the process.
  private nonisolated static let foregroundEntries = Result {
    try BundledProductReleaseCatalogLoader.bundledForeground()
      .foregroundNavigationEntries
  }

  static func makeModel(
    surfaceRouteResolver: any WholeShutoSurfaceRouteResolving =
      WholeShutoMapKitSurfaceRouteResolver(),
    checkpointStore: (any WholeShutoJourneyCheckpointStoring)? =
      WholeShutoFileCheckpointStore(),
    liveLocationSource: (any ForegroundNavigationLocationSource)? = nil,
    speechOutput: (any GuidanceSpeechOutput)? = nil,
    nowMillisecondsProvider: @escaping () -> Int = {
      Int((Date().timeIntervalSince1970 * 1_000).rounded())
    },
    languageSelectionProvider: @escaping () -> NavigationLanguageSelection = {
      WholeShutoProductModel.storedLanguageSelection()
    },
    driveRecordPreferenceStore: UserDefaults = .standard,
    driveHistoryStore: (any DriveHistoryStoring)? = nil
  ) -> WholeShutoProductModel {
    do {
      let database = try WholeShutoNetworkCatalog.bundled()
      let authority = LazyRouteReleaseAuthority(database: database)
      return WholeShutoProductModel(
        database: database,
        surfaceRouteResolver: surfaceRouteResolver,
        checkpointStore: checkpointStore,
        speechOutput: speechOutput,
        liveJourneyAdmissions: [],
        liveJourneyAdmissionResolver: { route in
          let foregroundEntries: [BundledProductReleaseEntry]
          let resolvedAuthority: WholeShutoRouteReleaseAuthority
          do {
            foregroundEntries = try Self.foregroundEntries.get()
            resolvedAuthority = try authority.value()
            try Task.checkCancellation()
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
            return resolvedAuthority.resolve(route: route)
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
              try Task.checkCancellation()
              return .available(
                try WholeShutoLiveJourneyAdmission(
                  core: core,
                  runtimeAssets: resolvedAuthority.runtimeContext.compile(
                    route: route
                  )
                )
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
        languageSelectionProvider: languageSelectionProvider,
        driveRecordPreferenceStore: driveRecordPreferenceStore,
        driveHistoryStore: driveHistoryStore
      )
    } catch {
      preconditionFailure("Invalid bundled Whole-Shuto foreground release: \(error)")
    }
  }
}

/// Builds the on-device route authority for the first route that needs it
/// and keeps it. Its network context validates and hashes the whole
/// database, which must not repeat on every route selection, and building it
/// at launch would delay the first frame.
private final class LazyRouteReleaseAuthority: Sendable {
  private let database: ShutoNetworkDatabase
  private let authority =
    Mutex<Result<WholeShutoRouteReleaseAuthority, any Error>?>(nil)

  init(database: ShutoNetworkDatabase) {
    self.database = database
  }

  func value() throws -> WholeShutoRouteReleaseAuthority {
    try authority.withLock { cached in
      if let cached { return try cached.get() }
      let built = Result {
        try WholeShutoRouteReleaseAuthority(database: database)
      }
      cached = built
      return try built.get()
    }
  }
}
