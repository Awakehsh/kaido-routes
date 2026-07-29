import CoreLocation
import Foundation
import MapKit
import SwiftUI

struct C2GeographicRoute: Decodable, Equatable, Sendable {
  struct Coordinate: Decodable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double

    var mapCoordinate: CLLocationCoordinate2D {
      CLLocationCoordinate2D(
        latitude: latitude,
        longitude: longitude
      )
    }
  }

  struct Segment: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let routeShield: String
    let distanceMeters: Double
    let checkpointNodeIDs: [Int64]
    let nodeIDs: [Int64]
    let wayIDs: [Int64]
    let coordinates: [Coordinate]

    enum CodingKeys: String, CodingKey {
      case id
      case routeShield = "route_shield"
      case distanceMeters = "distance_meters"
      case checkpointNodeIDs = "checkpoint_node_ids"
      case nodeIDs = "node_ids"
      case wayIDs = "way_ids"
      case coordinates
    }
  }

  struct Facility: Decodable, Equatable, Sendable {
    let facilityID: String
    let coordinate: Coordinate
    let sourceURL: URL
    let osmBoundaryDistanceMeters: Double

    enum CodingKeys: String, CodingKey {
      case facilityID = "facility_id"
      case coordinate
      case sourceURL = "source_url"
      case osmBoundaryDistanceMeters = "osm_boundary_distance_meters"
    }
  }

  struct Facilities: Decodable, Equatable, Sendable {
    let entrance: Facility
    let exit: Facility
  }

  struct Licence: Decodable, Equatable, Sendable {
    let identifier: String
    let attribution: String
    let sourceURL: URL
    let licenceURL: URL

    enum CodingKeys: String, CodingKey {
      case identifier
      case attribution
      case sourceURL = "source_url"
      case licenceURL = "licence_url"
    }
  }

  let schemaVersion: String
  let databaseID: String
  let verificationState: String
  let checkedAt: String
  let licence: Licence
  let operatorFacilities: Facilities
  let segments: [Segment]
  let totalDistanceMeters: Double
  let limitations: [String]

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case databaseID = "database_id"
    case verificationState = "verification_state"
    case checkedAt = "checked_at"
    case licence
    case operatorFacilities = "operator_facilities"
    case segments
    case totalDistanceMeters = "total_distance_meters"
    case limitations
  }

  static func bundled(
    bundle: Bundle = .main
  ) throws -> C2GeographicRoute {
    guard
      let url = bundle.url(
        forResource: "c2-b-20260729-geographic-route",
        withExtension: "json"
      )
    else {
      throw C2GeographicRouteError.resourceMissing
    }
    let route = try JSONDecoder().decode(
      C2GeographicRoute.self,
      from: Data(contentsOf: url)
    )
    try route.validate()
    return route
  }

  func validate() throws {
    guard schemaVersion == "1.0" else {
      throw C2GeographicRouteError.unsupportedSchema
    }
    guard
      databaseID == "kaido.c2-b-geographic-route.2026-07-29",
      verificationState == "GEOMETRY_CANDIDATE_DIRECTION_REVIEWED",
      licence.identifier == "ODbL-1.0",
      segments.map(\.routeShield) == ["C2", "C2→B", "B", "C2"],
      segments.count == 4,
      segments.allSatisfy({
        $0.coordinates.count == $0.nodeIDs.count
          && $0.wayIDs.count == $0.nodeIDs.count - 1
          && $0.coordinates.count >= 2
      }),
      (57_300...57_500).contains(totalDistanceMeters),
      operatorFacilities.entrance.osmBoundaryDistanceMeters <= 25,
      operatorFacilities.exit.osmBoundaryDistanceMeters <= 25
    else {
      throw C2GeographicRouteError.invalidRoute
    }
  }

  var flattenedCoordinates: [Coordinate] {
    segments.enumerated().flatMap { index, segment in
      index == 0
        ? segment.coordinates
        : Array(segment.coordinates.dropFirst())
    }
  }

  func coordinate(at progressFraction: Double) -> Coordinate? {
    let coordinates = flattenedCoordinates
    guard let first = coordinates.first else { return nil }
    guard coordinates.count > 1 else { return first }
    let target = min(1, max(0, progressFraction)) * totalDistanceMeters
    var traversed = 0.0
    for index in 1..<coordinates.count {
      let before = coordinates[index - 1]
      let after = coordinates[index]
      let leg = Self.distance(from: before, to: after)
      if traversed + leg >= target, leg > 0 {
        let fraction = (target - traversed) / leg
        return Coordinate(
          latitude:
            before.latitude
            + (after.latitude - before.latitude) * fraction,
          longitude:
            before.longitude
            + (after.longitude - before.longitude) * fraction
        )
      }
      traversed += leg
    }
    return coordinates.last
  }

  private static func distance(
    from first: Coordinate,
    to second: Coordinate
  ) -> Double {
    let radius = 6_371_000.0
    let lat1 = first.latitude * .pi / 180
    let lon1 = first.longitude * .pi / 180
    let lat2 = second.latitude * .pi / 180
    let lon2 = second.longitude * .pi / 180
    let deltaLatitude = lat2 - lat1
    let deltaLongitude = lon2 - lon1
    let value =
      pow(sin(deltaLatitude / 2), 2)
      + cos(lat1) * cos(lat2)
      * pow(sin(deltaLongitude / 2), 2)
    return 2 * radius * asin(sqrt(value))
  }
}

enum C2GeographicRouteError: Error, Equatable {
  case resourceMissing
  case unsupportedSchema
  case invalidRoute
}

enum C2GeographicRouteCatalog {
  static let bundled = try? C2GeographicRoute.bundled()
}

struct C2GeographicRouteMap: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale

  let route: C2GeographicRoute
  let progressFraction: Double?
  let usesDarkStyle: Bool

  @State private var camera: MapCameraPosition = .automatic

  var body: some View {
    Map(position: $camera, interactionModes: []) {
      ForEach(route.segments) { segment in
        MapPolyline(
          coordinates: segment.coordinates.map(\.mapCoordinate)
        )
        .stroke(
          segmentColor(segment),
          style: StrokeStyle(
            lineWidth: segment.routeShield == "C2→B" ? 8 : 7,
            lineCap: .round,
            lineJoin: .round
          )
        )
      }

      Annotation(
        copy.resolve(
          japanese: "富ヶ谷入口",
          simplifiedChinese: "富ヶ谷入口",
          english: "Tomigaya entrance"
        ),
        coordinate:
          route.operatorFacilities.entrance.coordinate.mapCoordinate
      ) {
        mapMarker(
          symbol: "arrow.down.to.line.compact",
          color: KaidoTheme.routeGreen
        )
      }

      if let kasai = route.segments[safe: 1]?.coordinates.first {
        Annotation("葛西 JCT", coordinate: kasai.mapCoordinate) {
          junctionMarker("B", color: Color(hex: 0x287E9A))
        }
      }

      if let oi = route.segments[safe: 2]?.coordinates.last {
        Annotation("大井 JCT", coordinate: oi.mapCoordinate) {
          junctionMarker("C2", color: KaidoTheme.routeGreen)
        }
      }

      Annotation(
        copy.resolve(
          japanese: "初台南出口",
          simplifiedChinese: "初台南出口",
          english: "Hatsudai-minami exit"
        ),
        coordinate: route.operatorFacilities.exit.coordinate.mapCoordinate
      ) {
        mapMarker(
          symbol: "flag.checkered",
          color: KaidoTheme.evidenceCoral
        )
      }

      if let progressFraction,
        let coordinate = route.coordinate(at: progressFraction)
      {
        Annotation(
          copy.resolve(
            japanese: "現在位置",
            simplifiedChinese: "当前位置",
            english: "Current position"
          ),
          coordinate: coordinate.mapCoordinate
        ) {
          ZStack {
            Circle()
              .fill(.white)
              .frame(width: 28, height: 28)
            Image(systemName: "location.north.fill")
              .font(.system(size: 13, weight: .black))
              .foregroundStyle(KaidoTheme.routeGreen)
          }
          .shadow(radius: 4)
        }
      }
    }
    .mapStyle(
      .standard(
        elevation: .flat,
        emphasis: usesDarkStyle ? .muted : .automatic,
        pointsOfInterest: .excludingAll
      )
    )
    .overlay(alignment: .topLeading) {
      HStack(spacing: 7) {
        routeBadge("C2", color: KaidoTheme.routeGreen)
        routeBadge("B", color: Color(hex: 0x287E9A))
        Text(String(format: "%.1f km", route.totalDistanceMeters / 1_000))
          .font(.system(size: 9, weight: .black, design: .rounded))
          .foregroundStyle(usesDarkStyle ? KaidoTheme.routeWhite : KaidoTheme.ink)
      }
      .padding(8)
      .background(.thinMaterial)
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .padding(9)
    }
    .overlay(alignment: .bottomTrailing) {
      Text("© OpenStreetMap contributors · ODbL 1.0")
        .font(.system(size: 7, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.ink)
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(.thinMaterial)
        .clipShape(Capsule())
        .padding(8)
        .accessibilityIdentifier("c2-geographic-map-attribution")
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(
      copy.resolve(
        japanese: "C2・B 地理ルート",
        simplifiedChinese: "C2 与 B 地理路线图",
        english: "C2 and B geographic route map"
      )
    )
    .accessibilityValue(
      [
        route.databaseID,
        route.verificationState,
        progressFraction.map {
          "\(Int(($0 * 100).rounded())) percent"
        } ?? "PLANNED",
      ].joined(separator: " | ")
    )
    .accessibilityIdentifier("c2-geographic-route-map")
  }

  private func segmentColor(
    _ segment: C2GeographicRoute.Segment
  ) -> Color {
    switch segment.routeShield {
    case "B":
      Color(hex: 0x287E9A)
    case "C2→B":
      KaidoTheme.signalAmber
    default:
      KaidoTheme.routeGreen
    }
  }

  private func routeBadge(
    _ title: String,
    color: Color
  ) -> some View {
    Text(title)
      .font(.system(size: 9, weight: .black, design: .rounded))
      .foregroundStyle(.white)
      .frame(width: 30, height: 24)
      .background(color)
      .clipShape(RoundedRectangle(cornerRadius: 7))
  }

  private func mapMarker(
    symbol: String,
    color: Color
  ) -> some View {
    Image(systemName: symbol)
      .font(.system(size: 11, weight: .black))
      .foregroundStyle(.white)
      .frame(width: 25, height: 25)
      .background(color)
      .clipShape(Circle())
      .overlay {
        Circle().stroke(.white, lineWidth: 2)
      }
      .shadow(radius: 2)
  }

  private func junctionMarker(
    _ shield: String,
    color: Color
  ) -> some View {
    Text(shield)
      .font(.system(size: 8, weight: .black, design: .rounded))
      .foregroundStyle(.white)
      .frame(width: 28, height: 25)
      .background(color)
      .clipShape(RoundedRectangle(cornerRadius: 7))
      .overlay {
        RoundedRectangle(cornerRadius: 7)
          .stroke(.white, lineWidth: 2)
      }
      .shadow(radius: 2)
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }
}

extension Array {
  fileprivate subscript(safe index: Index) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
