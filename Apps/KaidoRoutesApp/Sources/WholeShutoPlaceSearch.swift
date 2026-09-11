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
  case empty
  case unavailable
}

@MainActor
final class WholeShutoPlaceSearchController: ObservableObject {
  typealias Search = @MainActor (String, ShutoCoordinate?) async throws
    -> [(WholeShutoPlaceSuggestion, WholeShutoPlace)]

  @Published private(set) var suggestions: [WholeShutoPlaceSuggestion] = []
  @Published private(set) var state: WholeShutoPlaceSearchState = .idle
  @Published private(set) var selectedSuggestion: WholeShutoPlaceSuggestion?

  private let localPlaces: [(WholeShutoPlaceSuggestion, WholeShutoPlace)]
  private let searchPlaces: Search?
  private var placesByID: [String: WholeShutoPlace] = [:]
  private var requestID = UUID()

  init(
    localPlaces: [(WholeShutoPlaceSuggestion, WholeShutoPlace)] = [],
    usesMapKit: Bool = true,
    searchPlaces: Search? = nil
  ) {
    self.localPlaces = localPlaces
    self.searchPlaces = usesMapKit ? (searchPlaces ?? Self.searchMapKit) : nil
  }

  convenience init(previewPlaces: [(WholeShutoPlaceSuggestion, WholeShutoPlace)]) {
    self.init(localPlaces: previewPlaces, usesMapKit: false)
  }

  func update(query: String, near _: ShutoCoordinate?) {
    dismissResults()
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if selectedSuggestion?.title == normalized { return }
    selectedSuggestion = nil
    guard !normalized.isEmpty else { return }
    let key = Self.searchKey(normalized)
    let matches = localPlaces.filter { suggestion, _ in
      [suggestion.title, suggestion.subtitle, suggestion.id].contains {
        Self.searchKey($0).contains(key)
      }
    }.sorted {
      if ($0.1.parkingAreaID != nil) != ($1.1.parkingAreaID != nil) {
        return $0.1.parkingAreaID != nil
      }
      if $0.0.isShutoFacility != $1.0.isShutoFacility { return $0.0.isShutoFacility }
      return $0.0.id < $1.0.id
    }
    append(matches)
    state = suggestions.isEmpty ? .idle : .results
  }

  func search(query: String, near coordinate: ShutoCoordinate?) async {
    clearSelection()
    update(query: query, near: coordinate)
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return }
    guard let searchPlaces else {
      state = suggestions.isEmpty ? .empty : .results
      return
    }
    let currentRequest = requestID
    state = .searching
    do {
      let results = try await searchPlaces(normalized, coordinate)
      guard currentRequest == requestID else { return }
      append(results)
      state = suggestions.isEmpty ? .empty : .results
    } catch {
      guard currentRequest == requestID else { return }
      state = .unavailable
    }
  }

  func resolve(_ suggestion: WholeShutoPlaceSuggestion) async throws -> WholeShutoPlace {
    guard let place = placesByID[suggestion.id] else {
      state = .unavailable
      throw C2NavigationDemoError.placeNotFound
    }
    dismissResults()
    selectedSuggestion = suggestion
    return place
  }

  func clearSelection() {
    selectedSuggestion = nil
  }

  func dismissResults() {
    requestID = UUID()
    suggestions = []
    placesByID = [:]
    state = .idle
  }

  private func append(_ results: [(WholeShutoPlaceSuggestion, WholeShutoPlace)]) {
    let facilityTitles = Set(suggestions.filter(\.isShutoFacility).map {
      Self.searchKey($0.title).filter { !$0.isWhitespace }
    })
    for (suggestion, place) in results where placesByID[suggestion.id] == nil {
      // Keep the bundled directional identity when MapKit repeats a facility.
      guard !facilityTitles.contains(Self.searchKey(suggestion.title).filter { !$0.isWhitespace }) else { continue }
      suggestions.append(suggestion)
      placesByID[suggestion.id] = place
    }
  }

  private static func searchKey(_ text: String) -> String {
    (text.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? text)
      .replacingOccurrences(of: "黒", with: "黑").lowercased()
  }

  private static func searchMapKit(
    query: String, near coordinate: ShutoCoordinate?
  ) async throws -> [(WholeShutoPlaceSuggestion, WholeShutoPlace)] {
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = query
    request.resultTypes = [.address, .pointOfInterest]
    if let coordinate {
      request.region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
        latitudinalMeters: 120_000, longitudinalMeters: 120_000)
    }
    let response: MKLocalSearch.Response
    do {
      response = try await MKLocalSearch(request: request).start()
    } catch let error as MKError where error.code == .placemarkNotFound {
      return []
    }
    return response.mapItems.map { item in
      let coordinate: CLLocationCoordinate2D
      let address: String
      if #available(iOS 26.0, *) {
        coordinate = item.location.coordinate
        address = item.address?.fullAddress ?? ""
      } else {
        coordinate = item.placemark.coordinate
        address = item.placemark.title ?? ""
      }
      let title = item.name ?? address
      return (
        WholeShutoPlaceSuggestion(
          id: "mapkit:\(coordinate.latitude),\(coordinate.longitude):\(title)",
          title: title, subtitle: address),
        WholeShutoPlace(
          title: title,
          coordinate: ShutoCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude))
      )
    }
  }
}
