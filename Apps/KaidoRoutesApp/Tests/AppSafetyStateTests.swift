import XCTest

@testable import KaidoRoutesApp

final class AppSafetyStateTests: XCTestCase {
  func testPreviewCannotClaimNavigationAuthority() {
    let state = AppSafetyState.preview

    XCTAssertEqual(state.journeyPhase, "PLANNING")
    XCTAssertEqual(state.routeEditorContext, "PARKED")
    XCTAssertTrue(state.isParkedInteractionContext)
    XCTAssertEqual(
      state.guidanceProgress,
      "INSUFFICIENT_MATCHER_EVIDENCE"
    )
    XCTAssertEqual(
      state.passageEvidence,
      "NO_KNOWN_CONFLICT_REALTIME_UNCONFIRMED"
    )
    XCTAssertFalse(state.routeReleaseAuthority)
    XCTAssertFalse(state.measuredPositionAvailable)
  }
}
