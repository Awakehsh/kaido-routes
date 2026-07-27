import Combine
import Foundation
import KaidoDomain
import KaidoNavigation

enum KaidoProductJourneyStage: String, CaseIterable, Equatable, Sendable {
  case atlas = "ATLAS"
  case authoring = "AUTHORING"
  case review = "REVIEW"
  case navigation = "NAVIGATION"

  var order: Int {
    switch self {
    case .atlas:
      0
    case .authoring:
      1
    case .review:
      2
    case .navigation:
      3
    }
  }
}

enum KaidoProductJourneyBlocker: String, Equatable, Sendable {
  case routeReviewNotReady = "ROUTE_REVIEW_NOT_READY"
  case routeReleaseAuthorityUnavailable =
    "ROUTE_RELEASE_AUTHORITY_UNAVAILABLE"
  case productReleaseAmbiguous = "PRODUCT_RELEASE_AMBIGUOUS"
  case releasedPreDriveEvidenceUnavailable =
    "RELEASED_PRE_DRIVE_EVIDENCE_UNAVAILABLE"
  case navigationRuntimeUnavailable = "NAVIGATION_RUNTIME_UNAVAILABLE"
  case savedRouteUnavailable = "SAVED_ROUTE_RELEASE_UNAVAILABLE"
  case savedRouteAmbiguous = "SAVED_ROUTE_RELEASE_AMBIGUOUS"
  case savedRouteInvalid = "SAVED_ROUTE_INVALID"
}

@MainActor
final class KaidoProductJourneyModel: ObservableObject {
  @Published private(set) var stage: KaidoProductJourneyStage = .atlas
  @Published private(set) var lastBlocker: KaidoProductJourneyBlocker?
  @Published private(set) var navigationRuntime: ProductNavigationRuntimeModel?
  @Published private(set) var rehearsalRuntime: ProductNavigationRuntimeModel?

  let composition: KaidoRoutesAppModel

  private let productReleaseSelectionProvider: (RoutePlan) -> BundledProductReleaseSelection
  private let navigationRuntimeFactory:
    (BundledProductReleaseEntry) throws -> ProductNavigationRuntimeModel
  private let rehearsalRuntimeFactory: () throws -> ProductNavigationRuntimeModel
  private var compositionSubscription: AnyCancellable?
  private var reviewSubscription: AnyCancellable?
  private var releasedReviewSubscription: AnyCancellable?

  init(
    composition: KaidoRoutesAppModel = KaidoRoutesAppModel(),
    productReleaseSelectionProvider:
      ((RoutePlan) -> BundledProductReleaseSelection)? = nil,
    navigationRuntimeFactory:
      ((BundledProductReleaseEntry) throws -> ProductNavigationRuntimeModel)? =
      nil,
    rehearsalRuntimeFactory:
      (() throws -> ProductNavigationRuntimeModel)? = nil
  ) {
    self.composition = composition
    self.productReleaseSelectionProvider =
      productReleaseSelectionProvider
      ?? {
        composition.productReleaseCatalog
          .selectForegroundNavigationRelease(matching: $0)
      }
    self.navigationRuntimeFactory =
      navigationRuntimeFactory
      ?? {
        try composition.makeForegroundNavigationRuntime(for: $0)
      }
    self.rehearsalRuntimeFactory =
      rehearsalRuntimeFactory
      ?? {
        try composition.makeDemoRehearsalRuntime()
      }
    compositionSubscription = composition.objectWillChange.sink {
      [weak self] _ in
      self?.objectWillChange.send()
    }
    reviewSubscription = composition.preDriveReview.$snapshot.sink {
      [weak self] snapshot in
      guard let self else { return }
      guard composition.releasedRouteAuthoring == nil else { return }
      if snapshot == nil, stage.order >= KaidoProductJourneyStage.review.order {
        invalidateReview(blocker: .routeReviewNotReady)
      } else {
        objectWillChange.send()
      }
    }
    releasedReviewSubscription =
      composition.releasedRouteAuthoring?.$preDriveReviewSnapshot.sink {
        [weak self] snapshot in
        guard let self else { return }
        if snapshot == nil,
          stage.order >= KaidoProductJourneyStage.review.order
        {
          let blocker: KaidoProductJourneyBlocker =
            composition.releasedRouteAuthoring?.compiledRoutePlan == nil
            ? .routeReviewNotReady
            : .releasedPreDriveEvidenceUnavailable
          invalidateReview(blocker: blocker)
        } else {
          objectWillChange.send()
        }
      }
  }

  var routeReviewReady: Bool {
    if let releasedRouteAuthoring = composition.releasedRouteAuthoring {
      return releasedRouteAuthoring.reviewReady
    }
    return composition.preDriveReview.snapshot != nil
  }

  var compiledRoutePlan: RoutePlan? {
    if let releasedRouteAuthoring = composition.releasedRouteAuthoring {
      return releasedRouteAuthoring.compiledRoutePlan
    }
    return composition.routeEditor.compiledRoutePlan
  }

  var routeAtlasOverlayPresentation: ReleasedRouteAtlasOverlayPresentation {
    guard
      let releasedRouteAuthoring = composition.releasedRouteAuthoring,
      let entry = releasedRouteAuthoring.selectedEntry,
      let routePlan = releasedRouteAuthoring.compiledRoutePlan
    else {
      return .unavailable
    }
    guard entry.release.routeAtlas.routePlan == routePlan else {
      return .blocked("ATLAS_OVERLAY_ROUTE_PLAN_MISMATCH")
    }
    do {
      return .ready(
        projection: try RouteAtlasJourneyProjector.project(
          release: entry.release.routeAtlas
        ),
        isRealRoadAuthority:
          entry.release.foregroundLiveInputAuthority != nil
      )
    } catch {
      return .blocked(releasedRouteAtlasOverlayErrorCode(error))
    }
  }

  var discoveryRouteAtlasPresentation: ReleasedRouteAtlasOverlayPresentation {
    guard let entry = productShellEntry else {
      return .unavailable
    }
    do {
      return .ready(
        projection: try RouteAtlasJourneyProjector.project(
          release: entry.release.routeAtlas
        ),
        isRealRoadAuthority:
          entry.descriptor.role == .foregroundNavigation
          && entry.release.foregroundLiveInputAuthority != nil
      )
    } catch {
      return .blocked(releasedRouteAtlasOverlayErrorCode(error))
    }
  }

  var activeRuntime: ProductNavigationRuntimeModel? {
    navigationRuntime ?? rehearsalRuntime
  }

  var selectedRouteOption: ReleasedProductRouteOptionPresentation? {
    guard
      let authoring = composition.releasedRouteAuthoring,
      let selectedReleaseID = authoring.selectedReleaseID
    else {
      return nil
    }
    return authoring.options.first {
      $0.productReleaseID == selectedReleaseID
    }
  }

  var preDriveReviewSnapshot: PreDriveReviewSnapshot? {
    composition.releasedRouteAuthoring?.preDriveReviewSnapshot
      ?? composition.preDriveReview.snapshot
  }

  var canStartNavigation: Bool {
    guard
      routeReviewReady,
      navigationRuntime == nil,
      rehearsalRuntime == nil
    else {
      return false
    }
    guard case .selected(let entry) = productReleaseSelection else {
      return false
    }
    return entry.descriptor.role == .foregroundNavigation
      && entry.release.foregroundLiveInputAuthority != nil
  }

  var canStartRehearsal: Bool {
    guard
      routeReviewReady,
      navigationRuntime == nil,
      rehearsalRuntime == nil,
      case .selected(let entry) = productReleaseSelection
    else {
      return false
    }
    return entry.descriptor.role == .demoOnly
      && entry.release.foregroundLiveInputAuthority == nil
  }

  var canEnterDrivingStage: Bool {
    canStartNavigation || canStartRehearsal
  }

  var usesDemoRehearsal: Bool {
    composition.releasedRouteAuthoring?.scope == .demoRehearsal
  }

  var productReleaseSelection: BundledProductReleaseSelection {
    guard let routePlan = compiledRoutePlan else {
      return .unavailable
    }
    if let releasedRouteAuthoring = composition.releasedRouteAuthoring {
      guard
        let entry = releasedRouteAuthoring.selectedEntry,
        entry.release.navigation.bundle.routePlan == routePlan,
        releasedRouteAuthoring.reviewReady
      else {
        return .unavailable
      }
      return .selected(entry)
    }
    let selection = productReleaseSelectionProvider(routePlan)
    if case .selected(let entry) = selection,
      entry.release.navigation.bundle.routePlan != routePlan
    {
      return .unavailable
    }
    return selection
  }

  var navigationBlocker: KaidoProductJourneyBlocker? {
    if let releasedRouteAuthoring = composition.releasedRouteAuthoring {
      guard releasedRouteAuthoring.compiledRoutePlan != nil else {
        return .routeReviewNotReady
      }
      guard releasedRouteAuthoring.preDriveReviewSnapshot != nil else {
        return .releasedPreDriveEvidenceUnavailable
      }
    }
    guard routeReviewReady else {
      return .routeReviewNotReady
    }
    switch productReleaseSelection {
    case .unavailable:
      return .routeReleaseAuthorityUnavailable
    case .ambiguous:
      return .productReleaseAmbiguous
    case .selected:
      return nil
    }
  }

  var canAdvance: Bool {
    switch stage {
    case .atlas:
      true
    case .authoring:
      routeReviewReady
    case .review:
      canEnterDrivingStage
    case .navigation:
      false
    }
  }

  func advance() {
    switch stage {
    case .atlas:
      stage = .authoring
      lastBlocker = nil
    case .authoring:
      guard routeReviewReady else {
        lastBlocker = .routeReviewNotReady
        return
      }
      stage = .review
      lastBlocker = nil
    case .review:
      requestNavigationStart()
    case .navigation:
      break
    }
  }

  func selectRouteForPlanning(_ productReleaseID: String) {
    guard let authoring = composition.releasedRouteAuthoring else {
      stage = .authoring
      lastBlocker = nil
      return
    }
    authoring.selectRelease(productReleaseID)
    guard authoring.selectedReleaseID == productReleaseID else {
      lastBlocker = .routeReviewNotReady
      return
    }
    stage = .authoring
    lastBlocker = nil
  }

  func goBack() {
    switch stage {
    case .atlas:
      break
    case .authoring:
      stage = .atlas
      lastBlocker = nil
    case .review:
      stage = .authoring
      lastBlocker = nil
    case .navigation:
      break
    }
  }

  func go(to requestedStage: KaidoProductJourneyStage) {
    if stage == .navigation, requestedStage != .navigation {
      return
    }
    if requestedStage.order <= stage.order {
      stage = requestedStage
      lastBlocker = nil
      return
    }

    switch requestedStage {
    case .atlas:
      stage = .atlas
      lastBlocker = nil
    case .authoring:
      stage = .authoring
      lastBlocker = nil
    case .review:
      guard routeReviewReady else {
        lastBlocker = navigationBlocker ?? .routeReviewNotReady
        return
      }
      stage = .review
      lastBlocker = nil
    case .navigation:
      requestNavigationStart()
    }
  }

  func requestNavigationStart() {
    guard
      routeReviewReady,
      navigationRuntime == nil,
      rehearsalRuntime == nil
    else {
      lastBlocker = navigationBlocker ?? .routeReviewNotReady
      return
    }
    guard case .selected(let entry) = productReleaseSelection else {
      lastBlocker = navigationBlocker
      return
    }
    if entry.descriptor.role == .demoOnly {
      guard
        entry.release.foregroundLiveInputAuthority == nil,
        entry.release.releaseID
          == SyntheticProductRuntimeFixture.expectedProductReleaseID
      else {
        lastBlocker = .navigationRuntimeUnavailable
        return
      }
      do {
        let runtime = try rehearsalRuntimeFactory()
        guard
          runtime.syntheticFixture != nil,
          runtime.productReleaseID == entry.release.releaseID,
          runtime.routePlanID == entry.release.navigation.bundle.routePlan.id
        else {
          lastBlocker = .navigationRuntimeUnavailable
          return
        }
        rehearsalRuntime = runtime
        stage = .navigation
        lastBlocker = nil
      } catch {
        rehearsalRuntime = nil
        lastBlocker = .navigationRuntimeUnavailable
      }
      return
    }
    guard entry.descriptor.role == .foregroundNavigation else {
      lastBlocker = .routeReleaseAuthorityUnavailable
      return
    }
    do {
      navigationRuntime = try navigationRuntimeFactory(entry)
      stage = .navigation
      lastBlocker = nil
    } catch {
      navigationRuntime = nil
      lastBlocker = .navigationRuntimeUnavailable
    }
  }

  func saveCompiledRoute(named displayName: String) {
    let evidenceState: SharedRouteEvidenceState
    if case .selected(let entry) = productReleaseSelection,
      entry.descriptor.role == .foregroundNavigation,
      entry.release.navigation.bundle.routePlan == compiledRoutePlan
    {
      evidenceState = .released
    } else {
      evidenceState = .communityCandidate
    }
    composition.savedRouteLibrary.save(
      routePlan: compiledRoutePlan,
      displayName: displayName,
      evidenceState: evidenceState
    )
    objectWillChange.send()
  }

  func openSavedRoute(_ recordID: String) {
    guard
      let record = composition.savedRouteLibrary.record(id: recordID)
    else {
      lastBlocker = .savedRouteInvalid
      return
    }
    switch composition.savedRouteLibrary.availability(for: record) {
    case .selected(let releaseID):
      guard
        let authoring = composition.releasedRouteAuthoring
      else {
        lastBlocker = .savedRouteUnavailable
        return
      }
      authoring.selectRelease(releaseID)
      guard authoring.selectedReleaseID == releaseID else {
        lastBlocker = .savedRouteInvalid
        return
      }
      stage = .authoring
      lastBlocker = nil
    case .unavailable:
      lastBlocker = .savedRouteUnavailable
    case .ambiguous:
      lastBlocker = .savedRouteAmbiguous
    case .invalid:
      lastBlocker = .savedRouteInvalid
    }
  }

  func endNavigation() async {
    guard let navigationRuntime else {
      lastBlocker = .navigationRuntimeUnavailable
      return
    }
    guard await navigationRuntime.terminate() else {
      lastBlocker = .navigationRuntimeUnavailable
      return
    }
    self.navigationRuntime = nil
    stage = .review
    lastBlocker = nil
  }

  func endRehearsal() async {
    guard let rehearsalRuntime else {
      lastBlocker = .navigationRuntimeUnavailable
      return
    }
    guard await rehearsalRuntime.terminate() else {
      lastBlocker = .navigationRuntimeUnavailable
      return
    }
    self.rehearsalRuntime = nil
    stage = .review
    lastBlocker = nil
  }

  private func invalidateReview(blocker: KaidoProductJourneyBlocker) {
    stage = .authoring
    lastBlocker = blocker
    if let navigationRuntime {
      Task { [weak self, navigationRuntime] in
        _ = await navigationRuntime.terminate()
        guard
          let self,
          self.navigationRuntime === navigationRuntime
        else {
          return
        }
        self.navigationRuntime = nil
      }
    }
    if let rehearsalRuntime {
      Task { [weak self, rehearsalRuntime] in
        _ = await rehearsalRuntime.terminate()
        guard
          let self,
          self.rehearsalRuntime === rehearsalRuntime
        else {
          return
        }
        self.rehearsalRuntime = nil
      }
    }
  }

  private var productShellEntry: BundledProductReleaseEntry? {
    if let selected = composition.releasedRouteAuthoring?.selectedEntry {
      return selected
    }
    return composition.productReleaseCatalog.foregroundNavigationEntries.first
      ?? composition.productReleaseCatalog.demoEntries.first
  }

  static func reviewPreview() -> KaidoProductJourneyModel {
    let model = KaidoProductJourneyModel()
    model.composition.routeEditor.select(
      choiceID: "preview.synthetic.choice.early-exit"
    )
    model.composition.routeEditor.compile()
    model.go(to: .review)
    return model
  }
}
