import KaidoRouting
import XCTest

@testable import KaidoRoutesApp

@MainActor
final class WholeShutoPlaceSearchTests: XCTestCase {
  private let tokyoTower = WholeShutoPlace(
    title: "东京塔",
    coordinate: ShutoCoordinate(
      latitude: 35.658581,
      longitude: 139.745433
    )
  )

  func testPreviewSearchFiltersVisiblePlaceContent() {
    let controller = makeController()

    controller.update(query: "东京", near: nil)

    XCTAssertEqual(controller.state, .results)
    XCTAssertEqual(
      controller.suggestions.map(\.id),
      ["preview.tokyo-station", "preview.tokyo-tower"]
    )
    XCTAssertEqual(controller.suggestions.last?.subtitle, "东京都港区芝公园")
  }

  func testPreviewSelectionResolvesExactCoordinate() async throws {
    let controller = makeController()
    controller.update(query: "东京塔", near: nil)
    XCTAssertEqual(controller.suggestions.count, 1)
    let suggestion = try XCTUnwrap(controller.suggestions.first)

    let selected = try await controller.resolve(suggestion)

    XCTAssertEqual(selected, tokyoTower)
    XCTAssertEqual(controller.selectedSuggestion, suggestion)
    XCTAssertTrue(controller.suggestions.isEmpty)
    XCTAssertEqual(controller.state, .idle)
  }

  private func makeController() -> WholeShutoPlaceSearchController {
    WholeShutoPlaceSearchController(
      previewPlaces: [
        (
          WholeShutoPlaceSuggestion(
            id: "preview.tokyo-tower",
            title: "东京塔",
            subtitle: "东京都港区芝公园"
          ),
          tokyoTower
        ),
        (
          WholeShutoPlaceSuggestion(
            id: "preview.tokyo-station",
            title: "东京站",
            subtitle: "东京都千代田区丸之内"
          ),
          WholeShutoPlace(
            title: "东京站",
            coordinate: ShutoCoordinate(
              latitude: 35.681236,
              longitude: 139.767125
            )
          )
        ),
      ]
    )
  }
}
