import Combine
import CoreLocation
import Foundation
import KaidoRouting
@preconcurrency import MapKit

struct WholeShutoPlaceSuggestion: Equatable, Identifiable {
  let id: String
  let title: String
  let subtitle: String
}

enum WholeShutoPlaceSearchState: Equatable {
  case idle
  case searching
  case results
  case resolving
  case unavailable
}

@MainActor
final class WholeShutoPlaceSearchController:
  NSObject,
  ObservableObject,
  @preconcurrency MKLocalSearchCompleterDelegate
{
  @Published private(set) var suggestions: [WholeShutoPlaceSuggestion] = []
  @Published private(set) var state: WholeShutoPlaceSearchState = .idle
  @Published private(set) var selectedSuggestion: WholeShutoPlaceSuggestion?

  private let completer: MKLocalSearchCompleter?
  private let previewSuggestionsByID: [String: WholeShutoPlaceSuggestion]
  private let previewPlacesByID: [String: WholeShutoPlace]
  private var completionsByID: [String: MKLocalSearchCompletion] = [:]

  override init() {
    let completer = MKLocalSearchCompleter()
    self.completer = completer
    previewSuggestionsByID = [:]
    previewPlacesByID = [:]
    super.init()
    completer.delegate = self
    completer.resultTypes = [.address, .pointOfInterest]
  }

  init(previewPlaces: [(WholeShutoPlaceSuggestion, WholeShutoPlace)]) {
    completer = nil
    previewSuggestionsByID = Dictionary(
      uniqueKeysWithValues: previewPlaces.map { ($0.0.id, $0.0) }
    )
    previewPlacesByID = Dictionary(
      uniqueKeysWithValues: previewPlaces.map { ($0.0.id, $0.1) }
    )
    super.init()
  }

  func update(
    query: String,
    near coordinate: ShutoCoordinate?
  ) {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalized.count >= 2 else {
      clearResults()
      return
    }
    if selectedSuggestion?.title == normalized {
      suggestions = []
      state = .idle
      return
    }

    selectedSuggestion = nil
    state = .searching
    if completer == nil {
      suggestions = previewSuggestionsByID.values
        .sorted { $0.id < $1.id }
        .filter { suggestion in
          suggestion.title.localizedCaseInsensitiveContains(normalized)
            || suggestion.subtitle.localizedCaseInsensitiveContains(normalized)
        }
      state = suggestions.isEmpty ? .idle : .results
      return
    }

    if let coordinate {
      completer?.region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(
          latitude: coordinate.latitude,
          longitude: coordinate.longitude
        ),
        latitudinalMeters: 120_000,
        longitudinalMeters: 120_000
      )
    }
    completer?.queryFragment = normalized
  }

  func resolve(
    _ suggestion: WholeShutoPlaceSuggestion
  ) async throws -> WholeShutoPlace {
    state = .resolving
    if let preview = previewPlacesByID[suggestion.id] {
      selectedSuggestion = suggestion
      suggestions = []
      state = .idle
      return preview
    }
    guard let completion = completionsByID[suggestion.id] else {
      state = .unavailable
      throw C2NavigationDemoError.placeNotFound
    }

    do {
      let request = MKLocalSearch.Request(completion: completion)
      let response = try await MKLocalSearch(request: request).start()
      guard let item = response.mapItems.first else {
        throw C2NavigationDemoError.placeNotFound
      }
      let coordinate: CLLocationCoordinate2D
      if #available(iOS 26.0, *) {
        coordinate = item.location.coordinate
      } else {
        coordinate = item.placemark.coordinate
      }
      let place = WholeShutoPlace(
        title: item.name ?? suggestion.title,
        coordinate: ShutoCoordinate(
          latitude: coordinate.latitude,
          longitude: coordinate.longitude
        )
      )
      selectedSuggestion = suggestion
      suggestions = []
      state = .idle
      return place
    } catch {
      state = .unavailable
      throw error
    }
  }

  func clearSelection() {
    selectedSuggestion = nil
  }

  func dismissResults() {
    suggestions = []
    if state != .resolving {
      state = .idle
    }
  }

  func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
    let completions = completer.results.prefix(5)
    var mapped: [WholeShutoPlaceSuggestion] = []
    var originals: [String: MKLocalSearchCompletion] = [:]
    for completion in completions {
      let id = Self.suggestionID(
        title: completion.title,
        subtitle: completion.subtitle
      )
      guard originals[id] == nil else { continue }
      originals[id] = completion
      mapped.append(
        WholeShutoPlaceSuggestion(
          id: id,
          title: completion.title,
          subtitle: completion.subtitle
        )
      )
    }
    completionsByID = originals
    suggestions = mapped
    state = mapped.isEmpty ? .idle : .results
  }

  func completer(
    _: MKLocalSearchCompleter,
    didFailWithError _: any Error
  ) {
    completionsByID = [:]
    suggestions = []
    state = .unavailable
  }

  private func clearResults() {
    completer?.queryFragment = ""
    completionsByID = [:]
    suggestions = []
    state = .idle
  }

  private static func suggestionID(
    title: String,
    subtitle: String
  ) -> String {
    "\(title)|\(subtitle)"
  }
}
