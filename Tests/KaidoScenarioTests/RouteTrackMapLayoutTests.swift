import Foundation
import KaidoPresentation
import KaidoRouting
import Testing

@Suite("Route track map layout")
struct RouteTrackMapLayoutTests {
  @Test("the C2 circuit lays out whole-route with every facility labeled")
  func laysOutC2CircuitInOneFrame() throws {
    let database = try loadDatabase()
    let planner = try ShutoRoutePlanner(database: database)
    let route = try planner.planCircuit(
      circuit: .c2InnerWithBayshore,
      entryFacilityID: "shuto.ic.c2.hatsudaiminami",
      exitFacilityID: "shuto.ic.c2.tomigaya",
      laps: 2
    )

    let layout = try #require(
      RouteTrackMapLayout.make(
        routeCoordinates: route.coordinates.map {
          RouteTrackMapLayout.GeoPoint(
            latitude: $0.latitude,
            longitude: $0.longitude
          )
        },
        facilities: trackMapFacilities(
          database: database,
          memberRouteIDs: ["C2", "B"]
        )
      )
    )

    // The whole route stays inside the fixed design frame.
    #expect(
      layout.trackPoints.allSatisfy {
        (0...RouteTrackMapLayout.designWidth).contains($0.x)
          && (0...RouteTrackMapLayout.designHeight).contains($0.y)
      }
    )
    // Track fractions cover the full occurrence sequence monotonically.
    #expect(layout.trackPoints.first?.fraction == 0)
    #expect(
      zip(layout.trackPoints, layout.trackPoints.dropFirst())
        .allSatisfy { $0.fraction <= $1.fraction }
    )

    // Every on-route facility is labeled exactly once, always visible.
    let markIDs = layout.facilityMarks.map(\.id)
    #expect(Set(markIDs).count == markIDs.count)
    #expect(layout.facilityMarks.count >= 25)
    #expect(
      markIDs.contains("shuto.ic.c2.hatsudaiminami")
        && markIDs.contains("shuto.ic.c2.seishincho")
    )
    #expect(
      layout.facilityMarks.contains {
        $0.kind == .junction && $0.nameJA == "葛西JCT"
      }
    )
    // Labels stay inside the frame and off the track box interior columns.
    #expect(
      layout.facilityMarks.allSatisfy {
        (0...RouteTrackMapLayout.designWidth).contains($0.labelX)
          && (0...RouteTrackMapLayout.designHeight).contains($0.labelY)
      }
    )
    // Same-zone labels never collide vertically (left/right columns).
    for zone in [RouteTrackMapLayout.LabelZone.left, .right] {
      let ys = layout.facilityMarks
        .filter { $0.zone == zone }
        .map(\.labelY)
        .sorted()
      #expect(
        zip(ys, ys.dropFirst()).allSatisfy { $1 - $0 >= 20 }
      )
    }

    // The position projector lands a measured coordinate on the track.
    let hatsudai = RouteTrackMapLayout.GeoPoint(
      latitude: 35.67511257,
      longitude: 139.6878147
    )
    let nearest = layout.nearestTrackPoint(
      to: hatsudai,
      projector: layout.projector.project
    )
    let projected = layout.projector.project(hatsudai)
    let dx = nearest.x - projected.x
    let dy = nearest.y - projected.y
    #expect((dx * dx + dy * dy).squareRoot() < 8)
  }

  @Test("a degenerate route produces no layout instead of a broken one")
  func rejectsDegenerateRoutes() {
    #expect(
      RouteTrackMapLayout.make(
        routeCoordinates: [
          RouteTrackMapLayout.GeoPoint(latitude: 35, longitude: 139)
        ],
        facilities: []
      ) == nil
    )
  }

  private func trackMapFacilities(
    database: ShutoNetworkDatabase,
    memberRouteIDs: Set<String>
  ) -> [RouteTrackMapLayout.FacilityInput] {
    var inputs: [RouteTrackMapLayout.FacilityInput] = []
    for facility in database.directionalFacilities
    where memberRouteIDs.contains(facility.routeID) {
      inputs.append(
        RouteTrackMapLayout.FacilityInput(
          id: facility.facilityID,
          nameJA: facility.nameJA,
          kind: .interchange,
          coordinate: RouteTrackMapLayout.GeoPoint(
            latitude: facility.coordinate.latitude,
            longitude: facility.coordinate.longitude
          )
        )
      )
    }
    for junction in database.junctions {
      guard let coordinate = junction.coordinate else { continue }
      inputs.append(
        RouteTrackMapLayout.FacilityInput(
          id: junction.junctionID,
          nameJA: junction.nameJA,
          kind: .junction,
          coordinate: RouteTrackMapLayout.GeoPoint(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
          )
        )
      )
    }
    for parkingArea in database.parkingAreas
    where memberRouteIDs.contains(parkingArea.routeID ?? "") {
      inputs.append(
        RouteTrackMapLayout.FacilityInput(
          id: parkingArea.parkingAreaID,
          nameJA: parkingArea.nameJA,
          kind: .parkingArea,
          coordinate: RouteTrackMapLayout.GeoPoint(
            latitude: parkingArea.coordinate.latitude,
            longitude: parkingArea.coordinate.longitude
          )
        )
      )
    }
    return inputs
  }

  private func loadDatabase() throws -> ShutoNetworkDatabase {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let url = repositoryRoot
      .appendingPathComponent("data")
      .appendingPathComponent("route-atlas")
      .appendingPathComponent("osm-derived")
      .appendingPathComponent("shuto-whole-network-20260728.json")
    return try JSONDecoder().decode(
      ShutoNetworkDatabase.self,
      from: Data(contentsOf: url)
    )
  }
}
