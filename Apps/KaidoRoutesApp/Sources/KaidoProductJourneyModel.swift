import Combine
import Foundation
import KaidoDomain

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
}

@MainActor
final class KaidoProductJourneyModel: ObservableObject {
  @Published private(set) var stage: KaidoProductJourneyStage = .atlas
  @Published private(set) var lastBlocker: KaidoProductJourneyBlocker?
  @Published private(set) var navigationRuntime: ProductNavigationRuntimeModel?

  let composition: KaidoRoutesAppModel

  private let productReleaseSelectionProvider: (RoutePlan) -> BundledProductReleaseSelection
  private let navigationRuntimeFactory:
    (BundledProductReleaseEntry) throws -> ProductNavigationRuntimeModel
  private var compositionSubscription: AnyCancellable?
  private var reviewSubscription: AnyCancellable?
  private var releasedReviewSubscription: AnyCancellable?

  init(
    composition: KaidoRoutesAppModel = KaidoRoutesAppModel(),
    productReleaseSelectionProvider:
      ((RoutePlan) -> BundledProductReleaseSelection)? = nil,
    navigationRuntimeFactory:
      ((BundledProductReleaseEntry) throws -> ProductNavigationRuntimeModel)? =
      nil
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

  var canStartNavigation: Bool {
    guard routeReviewReady, navigationRuntime == nil else {
      return false
    }
    if case .selected = productReleaseSelection {
      return true
    }
    return false
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
      canStartNavigation
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
    guard routeReviewReady else {
      lastBlocker = navigationBlocker ?? .routeReviewNotReady
      return
    }
    guard case .selected(let entry) = productReleaseSelection else {
      lastBlocker = navigationBlocker
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
