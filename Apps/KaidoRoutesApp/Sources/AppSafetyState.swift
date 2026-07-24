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

  var isParkedInteractionContext: Bool {
    routeEditorContext == RouteEditorInteractionContext.parked.rawValue
  }

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
    label(for: .simplifiedChinese)
  }

  func label(for locale: KaidoReleaseLocale) -> String {
    let copy = KaidoInterfaceText(locale: locale)
    return switch self {
    case .network:
      copy.resolve(
        japanese: "全体図",
        simplifiedChinese: "全网",
        english: "Network"
      )
    case .k7Evidence:
      copy.resolve(
        japanese: "K7 証拠",
        simplifiedChinese: "K7 证据",
        english: "K7 evidence"
      )
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
    accessibilityLabel(for: .simplifiedChinese)
  }

  func accessibilityLabel(for locale: KaidoReleaseLocale) -> String {
    let copy = KaidoInterfaceText(locale: locale)
    return switch self {
    case .network:
      copy.resolve(
        japanese:
          "北を上に固定した首都高速の全体識別図。26 路線を識別できますが、ナビには使用できません。",
        simplifiedChinese:
          "固定北向首都高速全网识别图。二十六条路线已识别，不可用于导航。",
        english:
          "North-up Shuto Expressway recognition atlas. Twenty-six routes are identified; it is not navigation authority."
      )
    case .k7Evidence:
      copy.resolve(
        japanese:
          "K7 横浜北西線上りのトポロジー模式候補。一般道への後続は未審査で、ナビには使用できません。",
        simplifiedChinese:
          "K7 横滨北西线上行拓扑示意候选。地表后继未审核，不可用于导航。",
        english:
          "K7 Yokohama Northwest Route inbound topology candidate. Surface successors are unreviewed; it is not navigation authority."
      )
    }
  }
}

@MainActor
final class KaidoRoutesAppModel: ObservableObject {
  @Published var atlasMode: RouteAtlasMode = .network

  let safety = AppSafetyState.preview
  let productReleaseCatalog: BundledProductReleaseCatalog
  let routeAtlasAttributions: RouteAtlasAttributionCatalog
  let entranceRecommendation: EntranceRecommendationModel
  let routeEditor: ParkedRouteEditorModel
  let releasedRouteAuthoring: ReleasedProductRouteAuthoringModel?
  let preDriveEvidenceUpdates: PreDriveEvidenceUpdateModel?
  let savedRouteLibrary: SavedRouteLibraryModel
  let preDriveReview: PreDriveReviewModel
  let languageSettings: KaidoLanguageSettingsModel
  let guidanceVoiceSetup: GuidanceVoiceSetupModel
  let guidanceLanguagePreview: GuidanceLanguagePreviewModel
  let syntheticDrivingPreview: SyntheticDrivingPreviewModel
  let syntheticProductRuntime: SyntheticProductRuntimeModel
  let locationCalibration: InternalLocationCalibrationModel

  private let guidanceVoicePreferenceStore: any GuidanceVoicePreferenceStoring
  private var languageSettingsSubscriptions: Set<AnyCancellable> = []

  init(
    productReleaseCatalog injectedProductReleaseCatalog:
      BundledProductReleaseCatalog? = nil,
    savedRouteStore: (any SavedRouteLibraryStoring)? = nil,
    preDriveEvidenceUpdateStore:
      (any PreDriveEvidenceUpdateStoring)? = nil,
    preDriveEvidenceUpdateFetcher:
      (any PreDriveEvidenceUpdateFetching)? = nil,
    releasedPreDriveEvidenceProvider:
      ReleasedProductRouteAuthoringModel.EvidenceProvider? = nil
  ) {
    do {
      let routeEditor = try ParkedRouteEditorModel()
      self.routeEditor = routeEditor
      let productReleaseCatalog: BundledProductReleaseCatalog
      if let injectedProductReleaseCatalog {
        productReleaseCatalog = injectedProductReleaseCatalog
      } else {
        productReleaseCatalog =
          try BundledProductReleaseCatalogLoader.bundledPreview()
      }
      self.productReleaseCatalog = productReleaseCatalog
      savedRouteLibrary = SavedRouteLibraryModel(
        store: savedRouteStore,
        foregroundEntries:
          productReleaseCatalog.foregroundNavigationEntries
      )
      routeAtlasAttributions = try RouteAtlasAttributionCatalog.bundled()
      entranceRecommendation = try EntranceRecommendationModel(
        routeEditor: routeEditor
      )
      preDriveReview = PreDriveReviewModel(routeEditor: routeEditor)
      let languageSettings = KaidoLanguageSettingsModel()
      self.languageSettings = languageSettings
      if productReleaseCatalog.foregroundNavigationEntries.isEmpty {
        preDriveEvidenceUpdates = nil
        releasedRouteAuthoring = nil
      } else {
        let preDriveEvidenceUpdates = PreDriveEvidenceUpdateModel(
          entries: productReleaseCatalog.foregroundNavigationEntries,
          store: preDriveEvidenceUpdateStore,
          fetcher: preDriveEvidenceUpdateFetcher
        )
        self.preDriveEvidenceUpdates = preDriveEvidenceUpdates
        let evidenceProvider =
          releasedPreDriveEvidenceProvider
          ?? { entry, session in
            try preDriveEvidenceUpdates.evidence(
              for: entry,
              session: session
            )
          }
        let releasedRouteAuthoring =
          try ReleasedProductRouteAuthoringModel(
            entries: productReleaseCatalog.foregroundNavigationEntries,
            locale: languageSettings.interfaceLocale,
            evidenceProvider: evidenceProvider
          )
        self.releasedRouteAuthoring = releasedRouteAuthoring
        preDriveEvidenceUpdates.evidenceDidChange = {
          [weak releasedRouteAuthoring] in
          releasedRouteAuthoring?.evidenceSourceDidChange()
        }
      }
      let guidanceVoicePreferenceStore =
        UserDefaultsGuidanceVoicePreferenceStore()
      self.guidanceVoicePreferenceStore =
        guidanceVoicePreferenceStore
      guidanceVoiceSetup = GuidanceVoiceSetupModel(
        guidanceLocale: languageSettings.guidanceVoiceLocale,
        preferenceStore: guidanceVoicePreferenceStore,
        guidanceLocaleDidChange: {
          languageSettings.selectGuidanceVoiceLocale($0)
        }
      )
      guidanceLanguagePreview = try GuidanceLanguagePreviewModel()
      syntheticDrivingPreview = try SyntheticDrivingPreviewModel()
      let guidanceSpeechOutput = AVSpeechGuidanceOutput(
        preferredVoiceIdentifierProvider: {
          guidanceVoicePreferenceStore.identifier(for: $0)
        }
      )
      syntheticProductRuntime = try SyntheticProductRuntimeModel(
        speechOutput: guidanceSpeechOutput,
        languageSelectionProvider: {
          NavigationLanguageSelection(
            interfaceLocale: languageSettings.interfaceLocale,
            guidanceVoiceLocale: languageSettings.guidanceVoiceLocale
          )
        },
        checkpointStore:
          FileNavigationSessionCheckpointStore.applicationSupport()
      )
      locationCalibration = try InternalLocationCalibrationModel(
        fixture: .bundled()
      )
      languageSettings.objectWillChange.sink { [weak self] _ in
        self?.objectWillChange.send()
      }
      .store(in: &languageSettingsSubscriptions)
      languageSettings.$interfaceLocale.sink { [weak self] locale in
        self?.releasedRouteAuthoring?.updateLocale(locale)
      }
      .store(in: &languageSettingsSubscriptions)
      if let releasedRouteAuthoring {
        releasedRouteAuthoring.objectWillChange.sink { [weak self] _ in
          self?.objectWillChange.send()
        }
        .store(in: &languageSettingsSubscriptions)
      }
      if let preDriveEvidenceUpdates {
        preDriveEvidenceUpdates.objectWillChange.sink {
          [weak self] _ in
          self?.objectWillChange.send()
        }
        .store(in: &languageSettingsSubscriptions)
      }
      savedRouteLibrary.objectWillChange.sink { [weak self] _ in
        self?.objectWillChange.send()
      }
      .store(in: &languageSettingsSubscriptions)
    } catch {
      preconditionFailure("Invalid internal app fixture: \(error)")
    }
  }

  static func production() -> KaidoRoutesAppModel {
    KaidoRoutesAppModel(
      savedRouteStore: try? FileSavedRouteLibraryStore.applicationSupport(),
      preDriveEvidenceUpdateStore:
        try? FilePreDriveEvidenceUpdateStore.applicationSupport()
    )
  }

  func attribution(for mode: RouteAtlasMode) -> RouteAtlasAttribution {
    routeAtlasAttributions.attribution(for: mode)
  }

  func makeForegroundNavigationRuntime(
    for entry: BundledProductReleaseEntry
  ) throws -> ProductNavigationRuntimeModel {
    let fallback = AVSpeechGuidanceOutput(
      preferredVoiceIdentifierProvider: {
        [guidanceVoicePreferenceStore] languageCode in
        guidanceVoicePreferenceStore.identifier(for: languageCode)
      }
    )
    let speechOutput: any GuidanceSpeechOutput
    if let guidanceAudioRelease = entry.guidanceAudioRelease {
      speechOutput = ReleasedGuidanceAudioOutput(
        release: guidanceAudioRelease,
        player: AVAudioPlayerGuidancePlayback(),
        fallback: fallback
      )
    } else {
      speechOutput = fallback
    }
    return try ProductNavigationRuntimeModel(
      releasedEntry: entry,
      speechOutput: speechOutput,
      languageSelectionProvider: {
        [languageSettings] in
        NavigationLanguageSelection(
          interfaceLocale: languageSettings.interfaceLocale,
          guidanceVoiceLocale: languageSettings.guidanceVoiceLocale
        )
      },
      checkpointStore:
        FileNavigationSessionCheckpointStore.applicationSupport()
    )
  }
}
