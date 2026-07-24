import XCTest

@MainActor
final class KRU09AccessibilityUITests: XCTestCase {
  func testCriticalDrivingSurfaceExposesAccessibleSemantics() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-KR-U09-ACCESSIBILITY-PREVIEW"]
    app.launch()
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
