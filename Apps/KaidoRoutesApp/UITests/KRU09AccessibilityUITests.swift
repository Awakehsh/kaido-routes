import XCTest

@MainActor
final class KRU09AccessibilityUITests: XCTestCase {
  /// Dynamic Type and text-clipping audits lay the screen out again at every
  /// text size: about 1.8 s of a 2 s audit locally, and past XCTest's fixed,
  /// unconfigurable audit time limit on a loaded CI runner. They run in
  /// their own tests, which the Verify plan does not select, so the Full plan
  /// runs them beside the iPhone SE Large and AX5 legs.
  private static let textSizeAudits: XCUIAccessibilityAuditType = [
    .dynamicType, .textClipped,
  ]

  func testWholeShutoDefaultHomeAccessibilityAudit() throws {
    try auditDefaultHome(for: .all.subtracting(Self.textSizeAudits))
  }

  func testWholeShutoDefaultHomeTextSizeAudit() throws {
    try auditDefaultHome(for: Self.textSizeAudits)
  }

  func testWholeShutoDeterministicReviewAccessibilityAudit() throws {
    try auditDeterministicReview(for: .all.subtracting(Self.textSizeAudits))
  }

  func testWholeShutoDeterministicReviewTextSizeAudit() throws {
    try auditDeterministicReview(for: Self.textSizeAudits)
  }

  private func auditDefaultHome(
    for auditTypes: XCUIAccessibilityAuditType
  ) throws {
    continueAfterFailure = true
    for isLoading in [true, false] {
      let app = XCUIApplication()
      app.launchArguments = [
        "-app.kaidoroutes.language.interface", "en",
        "-app.kaidoroutes.language.guidance-voice", "ja-JP",
      ]
      if isLoading { app.launchArguments.append("-HOLD-CIRCUIT-PREVIEWS") }
      app.launchSilently()
      XCTAssertTrue(element("whole-shuto-planning-dock", in: app).waitForExistence(timeout: 5))
      let metrics = element("whole-shuto-circuit-metrics-shuto.circuit.c1-inner", in: app)
      if isLoading {
        XCTAssertFalse(metrics.exists)
        let history = app.buttons["whole-shuto-drive-history-open"]
        XCTAssertGreaterThanOrEqual(history.frame.height, 44)
      } else {
        XCTAssertTrue(metrics.waitForExistence(timeout: 30))
      }
      try performAccessibilityAudit(in: app, for: auditTypes)
      app.terminate()
    }
  }

  private func auditDeterministicReview(
    for auditTypes: XCUIAccessibilityAuditType
  ) throws {
    continueAfterFailure = true
    let app = XCUIApplication()
    app.launchArguments = [
      "-WHOLE-SHUTO-ROUTE-PREVIEW",
      "-app.kaidoroutes.language.interface",
      "en",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
    ]
    app.launchSilently()
    XCTAssertTrue(
      element("whole-shuto-route-selection", in: app)
        .waitForExistence(timeout: 5)
    )

    try performAccessibilityAudit(in: app, for: auditTypes)
  }

  func testCriticalDrivingSurfaceExposesAccessibleSemantics() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-KR-U09-ACCESSIBILITY-PREVIEW",
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
    ]
    app.launchSilently()
    let panel = element("kr-u09-driving-panel", in: app)
    XCTAssertTrue(panel.waitForExistence(timeout: 5))
    XCTAssertTrue(
      ["STANDARD", "ACCESSIBILITY"].contains(panel.value as? String ?? "")
    )

    let shield = element("driving-route-shield", in: app)
    XCTAssertTrue(shield.waitForExistence(timeout: 2))
    XCTAssertEqual(shield.label, "路线盾牌 B")

    XCTAssertEqual(
      element("driving-passage-status", in: app).label,
      "实时通行，尚未确认"
    )
    XCTAssertEqual(
      element("driving-editing-status", in: app).label,
      "路线编辑，决策区不可编辑"
    )

    let diagram = reveal("junction-vector-diagram", in: app)
    XCTAssertTrue(diagram.label.contains("选中分支带有勾选标记"))
    let lanes = reveal("junction-lane-layout", in: app)
    XCTAssertTrue(lanes.label.contains("首选车道 1"))
    XCTAssertEqual(
      reveal("junction-no-carplay-scene", in: app).label,
      "仅投影所有权，没有 CarPlay 场景"
    )
    XCTAssertEqual(
      reveal("junction-surface-carplay", in: app).label,
      "CarPlay，主显示"
    )
    XCTAssertEqual(
      reveal("junction-synthetic-evidence-warning", in: app).label,
      "合成发布门槛值，不是真实道路发布证据"
    )
  }

  private func performAccessibilityAudit(
    in app: XCUIApplication,
    for auditTypes: XCUIAccessibilityAuditType
  ) throws {
    try app.performAccessibilityAudit(for: auditTypes) { issue in
      let element = issue.element
      let identifier = element?.identifier ?? "<none>"
      let label = element?.label ?? "<none>"
      // A decorative node carries neither identifier nor label, so the frame
      // is the only thing that says which pixels failed.
      let frame = element.map { "\($0.frame)" } ?? "<none>"
      print(
        "KAIDO_A11Y_AUDIT "
          + "type=\(issue.auditType.rawValue) "
          + "identifier=\(identifier) "
          + "label=\(label) "
          + "frame=\(frame) "
          + "detail=\(issue.detailedDescription)"
      )
      return false
    }
  }

  private func element(
    _ identifier: String,
    in app: XCUIApplication
  ) -> XCUIElement {
    app.descendants(matching: .any)[identifier]
  }

  private func reveal(
    _ identifier: String,
    in app: XCUIApplication
  ) -> XCUIElement {
    let target = element(identifier, in: app)
    XCTAssertTrue(target.waitForExistence(timeout: 2))
    for _ in 0..<8 where !target.isHittable {
      app.swipeUp()
    }
    XCTAssertTrue(target.isHittable, "\(identifier) did not become visible")
    return target
  }

}
