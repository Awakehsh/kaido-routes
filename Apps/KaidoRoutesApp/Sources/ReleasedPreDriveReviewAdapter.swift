import KaidoNavigation
import KaidoPresentation

/// App-facing pre-drive boundary for one exact joint product release.
///
/// The product owns the RoutePlan and actual distance. Dated tariff and passage
/// evidence arrives separately for the current session and must bind back to
/// that exact route plus the independently selected vehicle class and payment
/// method before the app may render the review.
struct ReleasedPreDriveReviewAdapter: Equatable, Sendable {
  let productReleaseID: String
  let navigationReleaseID: String
  let routePlanID: String
  let session: PreDriveReviewSession
  let evaluation: PreDriveReviewEvaluation

  init(
    productRelease: KaidoProductRelease,
    session: PreDriveReviewSession,
    evidence: PreDriveReviewEvidence
  ) throws {
    let release = productRelease.navigation
    let routePlan = release.bundle.routePlan
    evaluation = try PreDriveReviewEvaluator.evaluate(
      routePlan: routePlan,
      session: session,
      evidence: evidence
    )
    productReleaseID = productRelease.releaseID
    navigationReleaseID = release.releaseID
    routePlanID = routePlan.id
    self.session = session
  }
}
