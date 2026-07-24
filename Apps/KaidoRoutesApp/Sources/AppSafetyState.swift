import Combine
import CoreGraphics
import KaidoAppleAdapters
import KaidoDomain
import KaidoNavigation
import KaidoPresentation
import KaidoRouting

struct AppSafetyState: Equatable, Sendable {
  let journeyPhase: String
  let routeEditorContext: String
  let guidanceProgress: String
  let passageEvidence: String
  let routeReleaseAuthority: Bool
  let measuredPositionAvailable: Bool

  static let preview = AppSafetyState(
    journeyPhase: JourneyPhase.planning.rawValue,
    routeEditorContext: RouteEditorInteractionContext.parked.rawValue,
    guidanceProgress:
      NavigationSessionGuidanceProgressState.insufficientMatcherEvidence.rawValue,
    passageEvidence:
      RoutePassageEvidence.noKnownConflictRealtimeUnconfirmed.rawValue,
    routeReleaseAuthority: false,
    measuredPositionAvailable: false
  )
}

enum RouteAtlasMode: String, CaseIterable, Hashable, Identifiable, Sendable {
  case network
  case k7Evidence

  var id: String { rawValue }

  var label: String {
    switch self {
    case .network:
      "全网"
    case .k7Evidence:
      "K7 证据"
    }
  }

  var resourceName: String {
    switch self {
    case .network:
      "shuto-route-atlas-recognition-reference"
    case .k7Evidence:
      "k7-northwest-up-schematic-layout-candidate"
    }
  }

  var aspectRatio: CGFloat {
    switch self {
    case .network:
      420 / 620
    case .k7Evidence:
      1_000 / 680
    }
  }

  var mapViewportHeight: CGFloat {
    switch self {
    case .network:
      296
    case .k7Evidence:
      252
    }
  }

  var accessibilityLabel: String {
    switch self {
    case .network:
      "固定北向首都高速全网识别图。二十六条路线已识别，不可用于导航。"
    case .k7Evidence:
      "K7 横滨北西线上行拓扑示意候选。地表后继未审核，不可用于导航。"
    }
  }
}

@MainActor
final class KaidoRoutesAppModel: ObservableObject {
  @Published var atlasMode: RouteAtlasMode = .network

  let safety = AppSafetyState.preview
  let routeAtlasAttributions: RouteAtlasAttributionCatalog
  let entranceRecommendation: EntranceRecommendationModel
  let routeEditor: ParkedRouteEditorModel
  let preDriveReview: PreDriveReviewModel
  let guidanceLanguagePreview: GuidanceLanguagePreviewModel
  let syntheticDrivingPreview: SyntheticDrivingPreviewModel
  let syntheticProductRuntime: SyntheticProductRuntimeModel
  let locationCalibration: InternalLocationCalibrationModel

  init() {
    do {
      let routeEditor = try ParkedRouteEditorModel()
      self.routeEditor = routeEditor
      routeAtlasAttributions = try RouteAtlasAttributionCatalog.bundled()
      entranceRecommendation = try EntranceRecommendationModel(
        routeEditor: routeEditor
      )
      preDriveReview = PreDriveReviewModel(routeEditor: routeEditor)
      guidanceLanguagePreview = try GuidanceLanguagePreviewModel()
      syntheticDrivingPreview = try SyntheticDrivingPreviewModel()
      syntheticProductRuntime = try SyntheticProductRuntimeModel(
        checkpointStore:
          FileNavigationSessionCheckpointStore.applicationSupport()
      )
      locationCalibration = try InternalLocationCalibrationModel(
        fixture: .bundled()
      )
    } catch {
      preconditionFailure("Invalid internal app fixture: \(error)")
    }
  }

  func attribution(for mode: RouteAtlasMode) -> RouteAtlasAttribution {
    routeAtlasAttributions.attribution(for: mode)
  }
}
