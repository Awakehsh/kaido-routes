import Combine
import Foundation

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
  case navigationStartNotAdmitted = "NAVIGATION_START_NOT_ADMITTED"
  case navigationRuntimeUnavailable = "NAVIGATION_RUNTIME_UNAVAILABLE"
}

@MainActor
final class KaidoProductJourneyModel: ObservableObject {
  @Published private(set) var stage: KaidoProductJourneyStage = .atlas
  @Published private(set) var lastBlocker: KaidoProductJourneyBlocker?

  let composition: KaidoRoutesAppModel

  private var compositionSubscription: AnyCancellable?
  private var reviewSubscription: AnyCancellable?

  init(composition: KaidoRoutesAppModel = KaidoRoutesAppModel()) {
    self.composition = composition
    compositionSubscription = composition.objectWillChange.sink {
      [weak self] _ in
      self?.objectWillChange.send()
    }
    reviewSubscription = composition.preDriveReview.$snapshot.sink {
      [weak self] snapshot in
      guard let self else { return }
      if snapshot == nil, stage.order >= KaidoProductJourneyStage.review.order {
        stage = .authoring
        lastBlocker = .routeReviewNotReady
      } else {
        objectWillChange.send()
      }
    }
  }

  var routeReviewReady: Bool {
    composition.preDriveReview.snapshot != nil
  }

  var canStartNavigation: Bool {
    routeReviewReady
      && composition.preDriveReview.snapshot?.navigationStartAllowed == true
      && composition.safety.routeReleaseAuthority
  }

  var navigationBlocker: KaidoProductJourneyBlocker? {
    guard routeReviewReady else {
      return .routeReviewNotReady
    }
    guard composition.safety.routeReleaseAuthority else {
      return .routeReleaseAuthorityUnavailable
    }
    guard
      composition.preDriveReview.snapshot?.navigationStartAllowed == true
    else {
      return .navigationStartNotAdmitted
    }
    return .navigationRuntimeUnavailable
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
      stage = .review
      lastBlocker = nil
    }
  }

  func go(to requestedStage: KaidoProductJourneyStage) {
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
        lastBlocker = .routeReviewNotReady
        return
      }
      stage = .review
      lastBlocker = nil
    case .navigation:
      requestNavigationStart()
    }
  }

  func requestNavigationStart() {
    guard canStartNavigation else {
      lastBlocker = navigationBlocker
      return
    }

    // A future released-road composition must inject the real runtime surface
    // before this state becomes reachable. Never substitute the bundled
    // synthetic actor trace for a user-started navigation session.
    lastBlocker = .navigationRuntimeUnavailable
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
