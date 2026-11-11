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
  /// Sign-text directions a Shuto facility admits. They stay Japanese; the
  /// entrance and exit words around them follow the interface language.
  let entranceDirections: [String]
  let exitDirections: [String]

  init(
    id: String,
    title: String,
    subtitle: String,
    isShutoFacility: Bool = false,
    entranceDirections: [String] = [],
    exitDirections: [String] = []
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.isShutoFacility = isShutoFacility
    self.entranceDirections = entranceDirections
    self.exitDirections = exitDirections
  }

  func displaySubtitle(_ copy: KaidoInterfaceText) -> String {
    var parts = subtitle.isEmpty ? [] : [subtitle]
    if !entranceDirections.isEmpty {
      parts.append(
        copy.resolve(japanese: "入口", simplifiedChinese: "入口", english: "Entry")
          + " " + entranceDirections.joined(separator: " / ")
      )
    }
    if !exitDirections.isEmpty {
      parts.append(
        copy.resolve(japanese: "出口", simplifiedChinese: "出口", english: "Exit")
          + " " + exitDirections.joined(separator: " / ")
      )
    }
    return parts.joined(separator: " · ")
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
  /// Suggestions while the driver types. They carry no coordinate until one
  /// is chosen, which keeps typing to one completion request per pause.
  typealias Complete = @MainActor (String, ShutoCoordinate?) async throws
    -> [WholeShutoPlaceSuggestion]
  typealias ResolveCompletion = @MainActor (WholeShutoPlaceSuggestion) async throws
    -> WholeShutoPlace

  @Published private(set) var suggestions: [WholeShutoPlaceSuggestion] = []
  @Published private(set) var state: WholeShutoPlaceSearchState = .idle
  @Published private(set) var selectedSuggestion: WholeShutoPlaceSuggestion?

  private let localPlaces: [(WholeShutoPlaceSuggestion, WholeShutoPlace)]
  private let searchPlaces: Search?
  private let completePlaces: Complete?
  private let resolveCompletion: ResolveCompletion?
  private let completionDelay: Duration
  private var placesByID: [String: WholeShutoPlace] = [:]
  private var completionIDs: Set<String> = []
  private var completionTask: Task<Void, Never>?
  private var requestID = UUID()

  init(
    localPlaces: [(WholeShutoPlaceSuggestion, WholeShutoPlace)] = [],
    usesMapKit: Bool = true,
    searchPlaces: Search? = nil,
    completePlaces: Complete? = nil,
    resolveCompletion: ResolveCompletion? = nil,
    completionDelay: Duration = .milliseconds(250)
  ) {
    self.localPlaces = localPlaces
    self.searchPlaces = usesMapKit ? (searchPlaces ?? Self.searchMapKit) : nil
    if usesMapKit, searchPlaces == nil, completePlaces == nil {
      let completer = MapKitPlaceCompleter()
      self.completePlaces = completer.complete
      self.resolveCompletion = completer.resolve
    } else {
      self.completePlaces = completePlaces
      self.resolveCompletion = resolveCompletion
    }
    self.completionDelay = completionDelay
  }

  convenience init(previewPlaces: [(WholeShutoPlaceSuggestion, WholeShutoPlace)]) {
    self.init(localPlaces: previewPlaces, usesMapKit: false)
  }

  func update(query: String, near coordinate: ShutoCoordinate?) {
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
    guard completePlaces != nil else {
      state = suggestions.isEmpty ? .idle : .results
      return
    }
    state = suggestions.isEmpty ? .searching : .results
    let currentRequest = requestID
    let delay = completionDelay
    completionTask = Task { [weak self] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled, let self, currentRequest == self.requestID,
        let completePlaces = self.completePlaces
      else { return }
      let completions = (try? await completePlaces(normalized, coordinate)) ?? []
      guard !Task.isCancelled, currentRequest == self.requestID else { return }
      self.appendCompletions(completions)
      self.state = self.suggestions.isEmpty ? .idle : .results
    }
  }

  func search(query: String, near coordinate: ShutoCoordinate?) async {
    clearSelection()
    update(query: query, near: coordinate)
    completionTask?.cancel()
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
    let place: WholeShutoPlace
    if let known = placesByID[suggestion.id] {
      place = known
    } else if completionIDs.contains(suggestion.id), let resolveCompletion {
      do {
        place = try await resolveCompletion(suggestion)
      } catch {
        state = .unavailable
        throw error
      }
    } else {
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
    completionTask?.cancel()
    completionTask = nil
    suggestions = []
    placesByID = [:]
    completionIDs = []
    state = .idle
  }

  private func append(_ results: [(WholeShutoPlaceSuggestion, WholeShutoPlace)]) {
    for (suggestion, place) in results
    where placesByID[suggestion.id] == nil && !repeatsBundledFacility(suggestion) {
      suggestions.append(suggestion)
      placesByID[suggestion.id] = place
    }
  }

  private func appendCompletions(_ results: [WholeShutoPlaceSuggestion]) {
    for suggestion in results
    where !completionIDs.contains(suggestion.id) && !repeatsBundledFacility(suggestion) {
      suggestions.append(suggestion)
      completionIDs.insert(suggestion.id)
    }
  }

  /// Keeps the bundled directional identity when MapKit repeats a facility.
  private func repeatsBundledFacility(_ suggestion: WholeShutoPlaceSuggestion) -> Bool {
    guard !suggestion.isShutoFacility else { return false }
    let title = Self.searchKey(suggestion.title).filter { !$0.isWhitespace }
    return suggestions.contains {
      $0.isShutoFacility && Self.searchKey($0.title).filter { !$0.isWhitespace } == title
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

/// Wraps `MKLocalSearchCompleter`, which reports results through its delegate,
/// as one async call per query. A newer query answers the older one empty.
@MainActor
final class MapKitPlaceCompleter: NSObject, MKLocalSearchCompleterDelegate {
  private let completer = MKLocalSearchCompleter()
  private var pending: CheckedContinuation<[MKLocalSearchCompletion], any Error>?
  private var completionsByID: [String: MKLocalSearchCompletion] = [:]

  override init() {
    super.init()
    completer.delegate = self
    completer.resultTypes = [.address, .pointOfInterest]
  }

  func complete(
    _ query: String, near coordinate: ShutoCoordinate?
  ) async throws -> [WholeShutoPlaceSuggestion] {
    pending?.resume(returning: [])
    pending = nil
    if let coordinate {
      completer.region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
        latitudinalMeters: 120_000, longitudinalMeters: 120_000)
    }
    let completions: [MKLocalSearchCompletion]
    if completer.queryFragment == query, !completer.isSearching {
      // An unchanged fragment produces no new delegate callback.
      completions = completer.results
    } else {
      completions = try await withCheckedThrowingContinuation { continuation in
        pending = continuation
        completer.queryFragment = query
      }
    }
    completionsByID = [:]
    return completions.map { completion in
      let id = "mapkit-completion:\(completion.title)\n\(completion.subtitle)"
      completionsByID[id] = completion
      return WholeShutoPlaceSuggestion(id: id, title: completion.title, subtitle: completion.subtitle)
    }
  }

  func resolve(_ suggestion: WholeShutoPlaceSuggestion) async throws -> WholeShutoPlace {
    guard let completion = completionsByID[suggestion.id] else {
      throw C2NavigationDemoError.placeNotFound
    }
    let response = try await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start()
    guard let item = response.mapItems.first else {
      throw C2NavigationDemoError.placeNotFound
    }
    let coordinate: CLLocationCoordinate2D
    if #available(iOS 26.0, *) {
      coordinate = item.location.coordinate
    } else {
      coordinate = item.placemark.coordinate
    }
    return WholeShutoPlace(
      title: suggestion.title,
      coordinate: ShutoCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude))
  }

  nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
    MainActor.assumeIsolated {
      pending?.resume(returning: completer.results)
      pending = nil
    }
  }

  nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
    MainActor.assumeIsolated {
      if (error as? MKError)?.code == .placemarkNotFound {
        pending?.resume(returning: [])
      } else {
        pending?.resume(throwing: error)
      }
      pending = nil
    }
  }
}
