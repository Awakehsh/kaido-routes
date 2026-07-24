import KaidoNavigation
import KaidoPresentation

/// App-facing pre-drive boundary for one exact joint product release.
///
/// The product owns the RoutePlan and actual distance. Dated tariff and passage
/// evidence arrives separately for the current session and must bind back to
/// that exact route before the app may render the review.
struct ReleasedPreDriveReviewAdapter: Equatable, Sendable {
  let productReleaseID: String
  let navigationReleaseID: String
  let routePlanID: String
  let evaluation: PreDriveReviewEvaluation

  init(
    productRelease: KaidoProductRelease,
    evidence: PreDriveReviewEvidence
  ) throws {
    let release = productRelease.navigation
    let routePlan = release.bundle.routePlan
    evaluation = try PreDriveReviewEvaluator.evaluate(
      routePlan: routePlan,
      evidence: evidence
    )
    productReleaseID = productRelease.releaseID
    navigationReleaseID = release.releaseID
    routePlanID = routePlan.id
  }
}
