import Foundation
import KaidoRouting
import SwiftUI

enum WholeShutoAttributionError: Error, Equatable {
  case invalidNetworkMetadata
  case identityDrift([String])
}

/// Visible OSM/ODbL attribution derived from the exact bundled whole-Shuto
/// database metadata. This is deliberately separate from the immutable legacy
/// Route Atlas catalog reviewed for the retained K7 produced work.
struct WholeShutoAttribution: Equatable, Sendable {
  static let resourceName = "shuto-whole-network-20260804"
  static let expectedDatabaseID = "kaido.shuto.whole-network.2026-08-04"
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
    do {
      try database.validate()
    } catch {
      throw WholeShutoAttributionError.invalidNetworkMetadata
    }

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

struct WholeShutoMapCredit: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale

  let attribution: WholeShutoAttribution

  var body: some View {
    Link(destination: attribution.sourceURL) {
      Text("© OpenStreetMap")
        .font(.system(size: 9, weight: .medium, design: .rounded))
        .foregroundStyle(KaidoTheme.nightQuiet)
        .padding(.horizontal, 6)
        .frame(minHeight: 22)
        .background(KaidoTheme.night.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .frame(minHeight: 44)
    .accessibilityLabel(
      copy.resolve(
        japanese: "地図データの出典、\(attribution.attribution)",
        simplifiedChinese: "地图数据来源，\(attribution.attribution)",
        english: "Map data source, \(attribution.attribution)"
      )
    )
    .accessibilityHint(
      copy.resolve(
        japanese: "\(attribution.sourceLabel) の出典説明を開く",
        simplifiedChinese: "打开 \(attribution.sourceLabel) 来源说明",
        english: "Open the \(attribution.sourceLabel) source statement"
      )
    )
    .accessibilityIdentifier("whole-shuto-map-credit")
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }

}
