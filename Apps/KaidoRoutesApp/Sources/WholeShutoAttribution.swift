import Foundation
import KaidoRouting
import SwiftUI

enum WholeShutoAttributionError: Error, Equatable {
  case identityDrift([String])
}

/// Visible OSM/ODbL attribution derived from the exact bundled whole-Shuto
/// database metadata. This is deliberately separate from the immutable legacy
/// Route Atlas catalog reviewed for the retained K7 produced work.
///
/// It checks identity only. The database it reads is the one the product
/// model's planner has already validated.
struct WholeShutoAttribution: Equatable, Sendable {
  static let resourceName = "shuto-whole-network-20260804"
  // The parking-access review adds the parking-area interiors the network
  // build drops, so the bundled graph is not the unrevised build and does
  // not answer to its identity.
  static let expectedDatabaseID =
    "kaido.shuto.whole-network.2026-08-04+pa-access-20260908+facility-candidates-20260914+facility-closures-20261012"
  static let expectedNetworkSnapshotID =
    "shuto-official-2026-07-29-osm-2026-08-04"
  static let expectedVerificationState =
    "OFFICIAL_FACILITIES_OSM_GEOMETRY_CANDIDATE"
  static let expectedAttribution = "© OpenStreetMap contributors"
  static let expectedLicenceIdentifier = "ODbL-1.0"
  static let sourceURLString = "https://www.openstreetmap.org/copyright"
  static let licenceURLString =
    "https://opendatacommons.org/licenses/odbl/1-0/"

  let resourceName: String
  let databaseID: String
  let networkSnapshotID: String
  let sourceLabel: String
  let attribution: String
  let sourceURL: URL
  let licenceIdentifier: String
  let licenceLabel: String
  let licenceURL: URL
  let sourceAccessibilityIdentifier: String
  let licenceAccessibilityIdentifier: String
  let navigationAuthority: Bool

  init(database: ShutoNetworkDatabase) throws {
    var issues: [String] = []
    if database.databaseID != Self.expectedDatabaseID {
      issues.append("database identity drift")
    }
    if database.networkSnapshotID != Self.expectedNetworkSnapshotID {
      issues.append("network snapshot identity drift")
    }
    if database.verificationState != Self.expectedVerificationState {
      issues.append("verification state drift")
    }
    if database.sources.osm.attribution != Self.expectedAttribution {
      issues.append("OSM attribution drift")
    }
    if database.sources.osm.licence != Self.expectedLicenceIdentifier {
      issues.append("OSM licence drift")
    }
    guard
      let sourceURL = URL(string: Self.sourceURLString),
      sourceURL.scheme == "https",
      let licenceURL = URL(string: Self.licenceURLString),
      licenceURL.scheme == "https"
    else {
      issues.append("attribution URL contract is invalid")
      throw WholeShutoAttributionError.identityDrift(issues.sorted())
    }
    guard issues.isEmpty else {
      throw WholeShutoAttributionError.identityDrift(issues.sorted())
    }

    resourceName = Self.resourceName
    databaseID = database.databaseID
    networkSnapshotID = database.networkSnapshotID
    sourceLabel = "OpenStreetMap"
    attribution = database.sources.osm.attribution
    self.sourceURL = sourceURL
    licenceIdentifier = database.sources.osm.licence
    licenceLabel = "ODbL 1.0"
    self.licenceURL = licenceURL
    sourceAccessibilityIdentifier = "route-atlas-attribution-source"
    licenceAccessibilityIdentifier = "route-atlas-attribution-licence"
    navigationAuthority = false
  }
}

/// The corner credit every map drawing the OSM-derived network carries, as
/// the OSMF attribution guideline asks of an interactive map. It links to the
/// OpenStreetMap copyright page, which states the ODbL terms.
struct WholeShutoMapCredit: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale

  /// The tap target's height; a map that seats its own marks above the
  /// credit leaves this much room for it.
  static let rowHeight: CGFloat = 44

  let attribution: WholeShutoAttribution

  var body: some View {
    Link(destination: attribution.sourceURL) {
      Text(verbatim: "© \(attribution.sourceLabel)")
        .font(.system(size: 9, weight: .medium, design: .rounded))
        .foregroundStyle(KaidoInk.textSecondary)
        .padding(.horizontal, 6)
        .frame(minHeight: 22)
        .background(KaidoInk.surface.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .frame(minHeight: Self.rowHeight)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .environment(\.colorScheme, .dark)
    .accessibilityLabel(
      copy.resolve(
        japanese: "地図データ、\(attribution.attribution)",
        simplifiedChinese: "地图数据，\(attribution.attribution)",
        english: "Map data, \(attribution.attribution)"
      )
    )
    .accessibilityHint(
      copy.resolve(
        japanese: "\(attribution.sourceLabel) の著作権とライセンスを開く",
        simplifiedChinese: "打开 \(attribution.sourceLabel) 版权与许可",
        english: "Opens \(attribution.sourceLabel) copyright and licence"
      )
    )
    .accessibilityIdentifier("whole-shuto-map-credit")
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }
}
