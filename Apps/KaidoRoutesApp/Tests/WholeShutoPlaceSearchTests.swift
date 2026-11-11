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

  func testBundledShutoFacilityAppearsBeforeMapKitSuggestions() async throws {
    let shibaura = WholeShutoPlace(
      title: "芝浦 IC",
      coordinate: ShutoCoordinate(
        latitude: 35.6415,
        longitude: 139.7555
      )
    )
    let suggestion = WholeShutoPlaceSuggestion(
      id: "shuto-facility:shuto.ic.1.shibaura",
      title: "芝浦 IC",
      subtitle: "1 · 入口 内回り",
      isShutoFacility: true
    )
    let controller = WholeShutoPlaceSearchController(
      localPlaces: [(suggestion, shibaura)]
    )

    controller.update(query: "芝浦", near: nil)

    XCTAssertEqual(controller.state, .results)
    XCTAssertEqual(controller.suggestions.first, suggestion)
    let selected = try await controller.resolve(suggestion)
    XCTAssertEqual(selected, shibaura)
  }

  func testSearchKeepsSameNamePlacesAtDifferentAddressesSelectable() async throws {
    let first = WholeShutoPlaceSuggestion(id: "branch-a", title: "Cafe", subtitle: "Shiba")
    let second = WholeShutoPlaceSuggestion(id: "branch-b", title: "Cafe", subtitle: "Ginza")
    let ginza = WholeShutoPlace(title: "Cafe", coordinate: .init(latitude: 35.67, longitude: 139.76))
    let controller = WholeShutoPlaceSearchController(searchPlaces: { query, near in
      XCTAssertEqual(query, "Cafe")
      XCTAssertEqual(near, self.tokyoTower.coordinate)
      return [(first, self.tokyoTower), (second, ginza)]
    })

    await controller.search(query: " Cafe ", near: tokyoTower.coordinate)

    XCTAssertEqual(controller.state, .results)
    XCTAssertEqual(controller.suggestions, [first, second])
    XCTAssertNil(controller.selectedSuggestion)
    let place = try await controller.resolve(second)
    XCTAssertEqual(place, ginza)
  }

  func testSearchDistinguishesNoResultsFromUnavailable() async {
    let empty = WholeShutoPlaceSearchController(searchPlaces: { _, _ in [] })
    await empty.search(query: "unknown", near: nil)
    XCTAssertEqual(empty.state, .empty)

    let unavailable = WholeShutoPlaceSearchController(searchPlaces: { _, _ in
      throw URLError(.notConnectedToInternet)
    })
    await unavailable.search(query: "Tokyo", near: nil)
    XCTAssertEqual(unavailable.state, .unavailable)
  }

  func testEditingQueryDiscardsSelectedPlace() async throws {
    let controller = makeController()
    await controller.search(query: "东京塔", near: nil)
    _ = try await controller.resolve(XCTUnwrap(controller.suggestions.first))

    controller.update(query: "东京站", near: nil)

    XCTAssertNil(controller.selectedSuggestion)
    XCTAssertEqual(controller.suggestions.map(\.id), ["preview.tokyo-station"])
    controller.update(query: "", near: nil)
    XCTAssertEqual(controller.state, .idle)
    XCTAssertTrue(controller.suggestions.isEmpty)
  }

  func testOlderSearchCannotReplaceEditedQueryOrSelection() async throws {
    var response: CheckedContinuation<[(WholeShutoPlaceSuggestion, WholeShutoPlace)], any Error>?
    let controller = WholeShutoPlaceSearchController(
      localPlaces: [(WholeShutoPlaceSuggestion(id: "tower", title: "东京塔", subtitle: "Tokyo"), tokyoTower)],
      searchPlaces: { _, _ in try await withCheckedThrowingContinuation { response = $0 } })
    let search = Task { await controller.search(query: "old", near: nil) }
    while response == nil { await Task.yield() }
    controller.update(query: "东京塔", near: nil)
    let selected = try await controller.resolve(XCTUnwrap(controller.suggestions.first))
    response?.resume(returning: [(
      WholeShutoPlaceSuggestion(id: "old", title: "Old", subtitle: ""), tokyoTower)])
    await search.value

    XCTAssertEqual(selected, tokyoTower)
    XCTAssertEqual(controller.selectedSuggestion?.id, "tower")
    XCTAssertTrue(controller.suggestions.isEmpty)
    XCTAssertEqual(controller.state, .idle)
  }

  func testSearchPreservesBundledPADestinationIdentity() async throws {
    let parking = WholeShutoPlace(title: "大黒PA", coordinate: tokyoTower.coordinate, parkingAreaID: "daikoku")
    let controller = WholeShutoPlaceSearchController(
      localPlaces: [(WholeShutoPlaceSuggestion(id: "pa", title: "大黒PA", subtitle: "PA", isShutoFacility: true), parking)],
      searchPlaces: { _, _ in [(
        WholeShutoPlaceSuggestion(id: "mapkit:pa", title: "大黑 PA", subtitle: "Yokohama"),
        WholeShutoPlace(title: "大黑 PA", coordinate: self.tokyoTower.coordinate))] })
    await controller.search(query: "大黑", near: nil)
    XCTAssertEqual(controller.suggestions.map(\.id), ["pa"])
    let selected = try await controller.resolve(XCTUnwrap(controller.suggestions.first))
    XCTAssertEqual(selected.parkingAreaID, "daikoku")
  }

  func testTypingAppendsCompletionsAfterBundledMatchesWithoutSubmit() async throws {
    let facility = WholeShutoPlaceSuggestion(id: "ginza-ic", title: "銀座 IC", subtitle: "C1", isShutoFacility: true)
    let store = WholeShutoPlaceSuggestion(id: "completion:store", title: "銀座三越", subtitle: "中央区銀座")
    var queries: [String] = []
    let controller = WholeShutoPlaceSearchController(
      localPlaces: [(facility, tokyoTower)],
      completePlaces: { query, near in
        queries.append(query)
        XCTAssertEqual(near, self.tokyoTower.coordinate)
        return [store, WholeShutoPlaceSuggestion(id: "completion:ic", title: "銀座IC", subtitle: "")]
      },
      resolveCompletion: { suggestion in
        XCTAssertEqual(suggestion, store)
        return self.tokyoTower
      },
      completionDelay: .zero)

    controller.update(query: "銀座", near: tokyoTower.coordinate)
    XCTAssertEqual(controller.suggestions, [facility])

    try await waitUntil { controller.suggestions.count == 2 }
    XCTAssertEqual(queries, ["銀座"])
    XCTAssertEqual(controller.suggestions, [facility, store])
    XCTAssertEqual(controller.state, .results)
    let place = try await controller.resolve(store)
    XCTAssertEqual(place, tokyoTower)
    XCTAssertEqual(controller.selectedSuggestion, store)
    XCTAssertTrue(controller.suggestions.isEmpty)
  }

  func testEditedQueryDiscardsAnOlderCompletion() async throws {
    var answers: [String: CheckedContinuation<[WholeShutoPlaceSuggestion], any Error>] = [:]
    let controller = WholeShutoPlaceSearchController(
      completePlaces: { query, _ in try await withCheckedThrowingContinuation { answers[query] = $0 } },
      resolveCompletion: { _ in self.tokyoTower },
      completionDelay: .zero)

    controller.update(query: "中華", near: nil)
    XCTAssertEqual(controller.state, .searching)
    try await waitUntil { answers["中華"] != nil }
    controller.update(query: "中華街", near: nil)
    try await waitUntil { answers["中華街"] != nil }
    answers["中華"]?.resume(returning: [WholeShutoPlaceSuggestion(id: "old", title: "中華料理", subtitle: "")])
    answers["中華街"]?.resume(returning: [WholeShutoPlaceSuggestion(id: "new", title: "横浜中華街", subtitle: "")])

    try await waitUntil { !controller.suggestions.isEmpty }
    XCTAssertEqual(controller.suggestions.map(\.id), ["new"])
  }

  func testSubmittedSearchReplacesPendingCompletion() async throws {
    var completionCalls = 0
    let place = WholeShutoPlace(title: "横浜中華街", coordinate: tokyoTower.coordinate)
    let controller = WholeShutoPlaceSearchController(
      searchPlaces: { _, _ in [(WholeShutoPlaceSuggestion(id: "search", title: "横浜中華街", subtitle: ""), place)] },
      completePlaces: { _, _ in
        completionCalls += 1
        return [WholeShutoPlaceSuggestion(id: "completion", title: "横浜中華街", subtitle: "")]
      },
      resolveCompletion: { _ in place },
      completionDelay: .milliseconds(50))

    await controller.search(query: "中華街", near: nil)
    try await Task.sleep(for: .milliseconds(150))

    XCTAssertEqual(completionCalls, 0)
    XCTAssertEqual(controller.suggestions.map(\.id), ["search"])
  }

  private func waitUntil(
    _ condition: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line
  ) async throws {
    for _ in 0..<200 where !condition() {
      try await Task.sleep(for: .milliseconds(5))
    }
    XCTAssertTrue(condition(), file: file, line: line)
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
