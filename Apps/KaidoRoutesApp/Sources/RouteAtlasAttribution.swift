import Foundation

enum RouteAtlasAttributionCatalogError: Error, Equatable {
  case missingResource(String)
  case invalidCatalog([String])
}

struct RouteAtlasAttribution: Equatable, Sendable {
  let mode: RouteAtlasMode
  let resourceName: String
  let sourceLabel: String
  let attribution: String
  let sourceURL: URL
  let licenceIdentifier: String
  let licenceLabel: String
  let licenceURL: URL
  let sourceAccessibilityIdentifier: String
  let licenceAccessibilityIdentifier: String
}

struct RouteAtlasAttributionCatalog: Sendable {
  static let resourceName = "route-atlas-attribution-catalog"
  static let expectedCatalogID = "kaido.route-atlas-attribution.2026-07-24"

  let catalogID: String
  private let entriesByMode: [RouteAtlasMode: RouteAtlasAttribution]

  static func bundled(in bundle: Bundle = .main) throws
    -> RouteAtlasAttributionCatalog
  {
    guard
      let resourceURL = bundle.url(
        forResource: resourceName,
        withExtension: "json"
      )
    else {
      throw RouteAtlasAttributionCatalogError.missingResource(
        "\(resourceName).json"
      )
    }
    return try decode(Data(contentsOf: resourceURL))
  }

  static func decode(_ data: Data) throws -> RouteAtlasAttributionCatalog {
    let document = try JSONDecoder().decode(Document.self, from: data)
    var issues: [String] = []
    if document.schemaVersion != "1.0" {
      issues.append("unsupported attribution catalog schema")
    }
    if document.catalogID != expectedCatalogID {
      issues.append("attribution catalog identity drift")
    }

    var entriesByMode: [RouteAtlasMode: RouteAtlasAttribution] = [:]
    for entry in document.entries {
      guard let mode = RouteAtlasMode(rawValue: entry.modeID) else {
        issues.append("unknown attribution mode \(entry.modeID)")
        continue
      }
      if entriesByMode[mode] != nil {
        issues.append("duplicate attribution mode \(entry.modeID)")
        continue
      }
      guard
        let sourceURL = validatedHTTPSURL(entry.sourceURL),
        let licenceURL = validatedHTTPSURL(entry.licenceURL)
      else {
        issues.append("attribution URLs are invalid for \(entry.modeID)")
        continue
      }
      let attribution = RouteAtlasAttribution(
        mode: mode,
        resourceName: entry.resourceName,
        sourceLabel: entry.sourceLabel,
        attribution: entry.attribution,
        sourceURL: sourceURL,
        licenceIdentifier: entry.licenceIdentifier,
        licenceLabel: entry.licenceLabel,
        licenceURL: licenceURL,
        sourceAccessibilityIdentifier:
          entry.presentation.sourceAccessibilityIdentifier,
        licenceAccessibilityIdentifier:
          entry.presentation.licenceAccessibilityIdentifier
      )
      if attribution.resourceName != mode.resourceName {
        issues.append("attribution resource drift for \(entry.modeID)")
      }
      if (
        entry.presentation.alwaysVisible,
        entry.presentation.placement,
        entry.presentation.requiresInteraction,
        entry.presentation.nativeLinks,
        entry.navigationAuthority
      ) != (true, "ADJACENT_TO_MAP", false, true, false) {
        issues.append("attribution presentation boundary drift for \(entry.modeID)")
      }
      if let expected = ExpectedEntry.forMode(mode),
        !expected.matches(attribution)
      {
        issues.append("attribution evidence drift for \(entry.modeID)")
      }
      entriesByMode[mode] = attribution
    }

    if Set(entriesByMode.keys) != Set(RouteAtlasMode.allCases) {
      issues.append("attribution catalog mode coverage is incomplete")
    }
    let uniqueIssues = Array(Set(issues)).sorted()
    guard uniqueIssues.isEmpty else {
      throw RouteAtlasAttributionCatalogError.invalidCatalog(uniqueIssues)
    }
    return RouteAtlasAttributionCatalog(
      catalogID: document.catalogID,
      entriesByMode: entriesByMode
    )
  }

  func attribution(for mode: RouteAtlasMode) -> RouteAtlasAttribution {
    guard let attribution = entriesByMode[mode] else {
      preconditionFailure("Validated attribution catalog lost mode \(mode.rawValue)")
    }
    return attribution
  }

  private static func validatedHTTPSURL(_ value: String) -> URL? {
    guard let url = URL(string: value), url.scheme == "https", url.host != nil else {
      return nil
    }
    return url
  }

  private struct ExpectedEntry {
    let attribution: String
    let sourceURL: String
    let licenceIdentifier: String
    let licenceURL: String

    static func forMode(_ mode: RouteAtlasMode) -> ExpectedEntry? {
      switch mode {
      case .network:
        ExpectedEntry(
          attribution:
            "National Land Numerical Information (Highway Time Series, N06-2025), Ministry of Land, Infrastructure, Transport and Tourism of Japan",
          sourceURL:
            "https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N06-2025.html",
          licenceIdentifier: "CC-BY-4.0",
          licenceURL: "https://creativecommons.org/licenses/by/4.0/"
        )
      case .k7Evidence:
        ExpectedEntry(
          attribution: "© OpenStreetMap contributors",
          sourceURL: "https://www.openstreetmap.org/copyright",
          licenceIdentifier: "ODbL-1.0",
          licenceURL: "https://opendatacommons.org/licenses/odbl/1-0/"
        )
      }
    }

    func matches(_ entry: RouteAtlasAttribution) -> Bool {
      entry.attribution == attribution
        && entry.sourceURL.absoluteString == sourceURL
        && entry.licenceIdentifier == licenceIdentifier
        && entry.licenceURL.absoluteString == licenceURL
        && entry.sourceAccessibilityIdentifier
          == "route-atlas-attribution-source"
        && entry.licenceAccessibilityIdentifier
          == "route-atlas-attribution-licence"
    }
  }

  private struct Document: Decodable {
    let schemaVersion: String
    let catalogID: String
    let entries: [Entry]

    struct Entry: Decodable {
      let modeID: String
      let resourceName: String
      let sourceLabel: String
      let attribution: String
      let sourceURL: String
      let licenceIdentifier: String
      let licenceLabel: String
      let licenceURL: String
      let presentation: Presentation
      let navigationAuthority: Bool

      struct Presentation: Decodable {
        let alwaysVisible: Bool
        let placement: String
        let requiresInteraction: Bool
        let nativeLinks: Bool
        let sourceAccessibilityIdentifier: String
        let licenceAccessibilityIdentifier: String

        enum CodingKeys: String, CodingKey {
          case alwaysVisible = "always_visible"
          case placement
          case requiresInteraction = "requires_interaction"
          case nativeLinks = "native_links"
          case sourceAccessibilityIdentifier =
            "source_accessibility_identifier"
          case licenceAccessibilityIdentifier =
            "licence_accessibility_identifier"
        }
      }

      enum CodingKeys: String, CodingKey {
        case modeID = "mode_id"
        case resourceName = "resource_name"
        case sourceLabel = "source_label"
        case attribution
        case sourceURL = "source_url"
        case licenceIdentifier = "licence_identifier"
        case licenceLabel = "licence_label"
        case licenceURL = "licence_url"
        case presentation
        case navigationAuthority = "navigation_authority"
      }
    }

    enum CodingKeys: String, CodingKey {
      case schemaVersion = "schema_version"
      case catalogID = "catalog_id"
      case entries
    }
  }
}
