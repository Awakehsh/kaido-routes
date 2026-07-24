import KaidoDomain
import KaidoNavigation
import KaidoRouting

enum ReleasedRouteEditorAdapterError: Error, Equatable, Sendable {
  case missingEntranceTitle(String)
  case missingDecisionTitle(String)
  case missingChoicePresentation(String)
  case missingChoiceTitle(String)
  case missingChoiceDetail(String)
  case noRemainingStep
  case choiceDoesNotMatchRelease(expected: String, actual: String)
  case incompleteReleasedRoute
}

struct ReleasedRouteEditorStepPresentation: Equatable, Sendable {
  let decisionPointID: String
  let decisionTitle: String
  let choiceID: String
  let choiceTitle: String
  let choiceDetail: String
  let movementOccurrenceID: String
  let outgoingEdgeOccurrenceID: String
}

/// App-facing, locale-resolved adapter for one exact joint product release.
///
/// It never falls back to raw IDs and never creates occurrence identity. The
/// release-owned recipe supplies every submitted choice and occurrence ID, and
/// compilation succeeds only when the reconstructed plan equals the release.
struct ReleasedRouteEditorAdapter {
  let productReleaseID: String
  let navigationReleaseID: String
  let locale: KaidoReleaseLocale
  let entranceTitle: String
  let steps: [ReleasedRouteEditorStepPresentation]

  private let recipe: ReleasedRouteAuthoringRecipe
  private let interaction: RouteEditorInteractionContext
  private var session: ExpertRouteEditorSession
  private var completedStepCount = 0

  init(
    productRelease: KaidoProductRelease,
    locale: KaidoReleaseLocale,
    interaction: RouteEditorInteractionContext = .parked
  ) throws {
    let release = productRelease.navigation
    let bundle = release.bundle
    let presentation = bundle.editorPresentationCatalog
    let entranceFacilityID = bundle.routePlan.entryFacilityID
    guard
      let entranceTitle = presentation.title(
        forEntrance: entranceFacilityID,
        locale: locale
      )
    else {
      throw ReleasedRouteEditorAdapterError.missingEntranceTitle(
        entranceFacilityID
      )
    }

    let resolvedSteps = try bundle.routeAuthoringRecipe.steps.map { step in
      guard
        let decisionTitle = presentation.title(
          forDecisionPoint: step.decisionPointID,
          locale: locale
        )
      else {
        throw ReleasedRouteEditorAdapterError.missingDecisionTitle(
          step.decisionPointID
        )
      }
      guard
        let choice = presentation.presentation(forChoice: step.choiceID)
      else {
        throw ReleasedRouteEditorAdapterError.missingChoicePresentation(
          step.choiceID
        )
      }
      guard let choiceTitle = choice.title.value(for: locale) else {
        throw ReleasedRouteEditorAdapterError.missingChoiceTitle(
          step.choiceID
        )
      }
      guard let choiceDetail = choice.detail.value(for: locale) else {
        throw ReleasedRouteEditorAdapterError.missingChoiceDetail(
          step.choiceID
        )
      }
      return ReleasedRouteEditorStepPresentation(
        decisionPointID: step.decisionPointID,
        decisionTitle: decisionTitle,
        choiceID: step.choiceID,
        choiceTitle: choiceTitle,
        choiceDetail: choiceDetail,
        movementOccurrenceID: step.movementOccurrenceID,
        outgoingEdgeOccurrenceID: step.outgoingEdgeOccurrenceID
      )
    }

    productReleaseID = productRelease.releaseID
    navigationReleaseID = release.releaseID
    self.locale = locale
    self.entranceTitle = entranceTitle
    steps = resolvedSteps
    recipe = bundle.routeAuthoringRecipe
    self.interaction = interaction
    session = try bundle.routeAuthoringRecipe.makeSession(
      interaction: interaction
    )
  }

  var snapshot: ExpertRouteEditorSnapshot {
    session.snapshot
  }

  var nextStep: ReleasedRouteEditorStepPresentation? {
    guard completedStepCount < steps.count else { return nil }
    return steps[completedStepCount]
  }

  mutating func selectReleasedChoice(_ choiceID: String) throws {
    guard let step = nextStep else {
      throw ReleasedRouteEditorAdapterError.noRemainingStep
    }
    guard choiceID == step.choiceID else {
      throw ReleasedRouteEditorAdapterError.choiceDoesNotMatchRelease(
        expected: step.choiceID,
        actual: choiceID
      )
    }
    try session.select(
      choiceID: step.choiceID,
      movementOccurrenceID: step.movementOccurrenceID,
      outgoingEdgeOccurrenceID: step.outgoingEdgeOccurrenceID,
      interaction: interaction
    )
    completedStepCount += 1
  }

  func compileReleasedRoute() throws -> RoutePlan {
    guard completedStepCount == steps.count else {
      throw ReleasedRouteEditorAdapterError.incompleteReleasedRoute
    }
    return try recipe.compile(
      session: session,
      interaction: interaction
    )
  }
}
