import Combine
import CoreLocation
import Foundation
import KaidoRouting
@preconcurrency import MapKit

struct WholeShutoPlaceSuggestion: Equatable, Identifiable {
  let id: String
  let title: String
  let subtitle: String
  let isShutoFacility: Bool

  init(
    id: String,
    title: String,
    subtitle: String,
    isShutoFacility: Bool = false
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.isShutoFacility = isShutoFacility
  }
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
  private let localSuggestionsByID: [String: WholeShutoPlaceSuggestion]
  private let localPlacesByID: [String: WholeShutoPlace]
  private var completionsByID: [String: MKLocalSearchCompletion] = [:]
  private var localMatches: [WholeShutoPlaceSuggestion] = []

  override init() {
    let completer = MKLocalSearchCompleter()
    self.completer = completer
    localSuggestionsByID = [:]
    localPlacesByID = [:]
    super.init()
    configure(completer)
  }

  init(
    localPlaces: [(WholeShutoPlaceSuggestion, WholeShutoPlace)],
    usesMapKit: Bool = true
  ) {
    let completer = usesMapKit ? MKLocalSearchCompleter() : nil
    self.completer = completer
    localSuggestionsByID = Dictionary(
      uniqueKeysWithValues: localPlaces.map { ($0.0.id, $0.0) }
    )
    localPlacesByID = Dictionary(
      uniqueKeysWithValues: localPlaces.map { ($0.0.id, $0.1) }
    )
    super.init()
    if let completer {
      configure(completer)
    }
  }

  init(previewPlaces: [(WholeShutoPlaceSuggestion, WholeShutoPlace)]) {
    completer = nil
    localSuggestionsByID = Dictionary(
      uniqueKeysWithValues: previewPlaces.map { ($0.0.id, $0.0) }
    )
    localPlacesByID = Dictionary(
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
    localMatches = localSuggestionsByID.values
      .filter { suggestion in
        suggestion.title.localizedCaseInsensitiveContains(normalized)
          || suggestion.subtitle.localizedCaseInsensitiveContains(normalized)
      }
      .sorted {
        if $0.isShutoFacility != $1.isShutoFacility {
          return $0.isShutoFacility
        }
        return $0.id < $1.id
      }
    if completer == nil {
      suggestions = localMatches
      state = suggestions.isEmpty ? .idle : .results
      return
    }

    suggestions = localMatches
    state = localMatches.isEmpty ? .searching : .results

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
    if let localPlace = localPlacesByID[suggestion.id] {
      selectedSuggestion = suggestion
      suggestions = []
      state = .idle
      return localPlace
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
    completer?.cancel()
    completionsByID = [:]
    suggestions = []
    localMatches = []
    if state != .resolving {
      state = .idle
    }
  }

  func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
    let completions = completer.results.prefix(5)
    var mapped = localMatches
    var originals: [String: MKLocalSearchCompletion] = [:]
    var canonicalTitles = Set(localMatches.map { Self.canonicalTitle($0.title) })
    for completion in completions {
      let id = Self.suggestionID(
        title: completion.title,
        subtitle: completion.subtitle
      )
      let canonicalTitle = Self.canonicalTitle(completion.title)
      guard originals[id] == nil,
        !canonicalTitles.contains(canonicalTitle)
      else { continue }
      originals[id] = completion
      canonicalTitles.insert(canonicalTitle)
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
    suggestions = localMatches
    state = localMatches.isEmpty ? .unavailable : .results
  }

  private func clearResults() {
    completer?.queryFragment = ""
    completionsByID = [:]
    localMatches = []
    suggestions = []
    state = .idle
  }

  private func configure(_ completer: MKLocalSearchCompleter) {
    completer.delegate = self
    completer.resultTypes = [.address, .pointOfInterest]
  }

  private static func suggestionID(
    title: String,
    subtitle: String
  ) -> String {
    "\(title)|\(subtitle)"
  }

  private static func canonicalTitle(_ title: String) -> String {
    title
      .replacingOccurrences(of: " ", with: "")
      .replacingOccurrences(of: "　", with: "")
      .lowercased()
  }
}
