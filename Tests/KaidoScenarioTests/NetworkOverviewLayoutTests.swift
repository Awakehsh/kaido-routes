import Foundation
import KaidoPresentation
import KaidoRouting
import Testing

@Suite("Network overview layout")
struct NetworkOverviewLayoutTests {
  @Test("the snapshot lays out with every available facility's facts")
  func laysOutWholeNetworkWithFacilityFacts() throws {
    let layout = try #require(try makeLayout())

    // Everything stays inside the fixed design frame.
    #expect(
      layout.polylines.allSatisfy { polyline in
        polyline.points.allSatisfy {
          (0...NetworkOverviewLayout.designWidth).contains($0.x)
            && (0...NetworkOverviewLayout.designHeight).contains($0.y)
        }
      }
    )
    // All 148 available facilities carry their directional facts.
    #expect(layout.facilityMarks.count == 148)
    let hatsudaiMinami = try #require(
      layout.facilityMarks.first {
        $0.id == "shuto.ic.c2.hatsudaiminami"
      }
    )
    #expect(hatsudaiMinami.entrance == .half)
    #expect(hatsudaiMinami.exit == .half)
    #expect(hatsudaiMinami.etcOnly)
    let ogiohashi = try #require(
      layout.facilityMarks.first { $0.id == "shuto.ic.c2.oogioohashi" }
    )
    #expect(ogiohashi.entrance == .full)
    #expect(ogiohashi.exit == .full)
    #expect(layout.parkingAreaMarks.count == 19)
    #expect(
      layout.parkingAreaMarks.filter(\.notable).map(\.shortNameJA).sorted()
        == [
          "大井PA", "大黒PA", "平和島PA", "箱崎PA", "芝浦PA", "辰巳第一PA",
        ]
    )
    #expect(
      layout.placeMarks.map(\.nameJA).sorted() == [
        "かつしかハープ橋",
        "みなとみらい",
        "レインボーブリッジ",
        "五色桜大橋",
        "東京スカイツリー",
        "東京タワー",
        "横浜ベイブリッジ",
        "羽田空港",
        "鶴見つばさ橋",
      ]
    )
    let tokyoTower = try #require(
      layout.placeMarks.first { $0.id == "place.tokyo-tower" }
    )
    #expect(tokyoTower.routeIDs == ["C1"])
    #expect(tokyoTower.icon == .tokyoTower)
    let rainbow = try #require(
      layout.placeMarks.first { $0.id == "place.rainbow-bridge" }
    )
    #expect(rainbow.routeIDs == ["11"])
    #expect(rainbow.icon == .suspensionBridge)
    #expect(
      layout.placeMarks.map(\.icon).sorted { $0.rawValue < $1.rawValue }
        == [
          .airplane,
          .archBridge,
          .cableStayedBridge,
          .cableStayedBridge,
          .ferrisWheel,
          .harpBridge,
          .suspensionBridge,
          .tokyoSkytree,
          .tokyoTower,
        ]
    )
    let daikokuPA = try #require(
      layout.parkingAreaMarks.first { $0.id == "shuto.pa.daikoku" }
    )
    #expect(daikokuPA.notable)
    #expect(daikokuPA.routeIDs.contains("B"))
    // Junction marks and route badges are present and spread apart.
    #expect(layout.junctionMarks.count == 39)
    let edobashi = try #require(
      layout.junctionMarks.first { $0.nameJA == "江戸橋JCT" }
    )
    #expect(edobashi.routeIDs.contains("C1"))
    let daikoku = try #require(
      layout.junctionMarks.first { $0.nameJA == "大黒JCT" }
    )
    #expect(!daikoku.routeIDs.isEmpty)
    #expect(!layout.badges.isEmpty)
    for (index, badge) in layout.badges.enumerated() {
      for other in layout.badges[(index + 1)...] {
        let distance = ((badge.x - other.x) * (badge.x - other.x)
          + (badge.y - other.y) * (badge.y - other.y)).squareRoot()
        #expect(distance >= 28)
      }
    }
  }

  @Test("the focus projection magnifies the center over the periphery")
  func focusProjectionMagnifiesCenter() throws {
    let layout = try #require(try makeLayout())
    // Two C1-area junctions ~2.4 km apart versus two Kanagawa junctions
    // ~4.4 km apart: under the focus projection the central pair must not
    // collapse relative to the peripheral pair.
    func mark(_ name: String) throws -> NetworkOverviewLayout.JunctionMark
    {
      try #require(layout.junctionMarks.first { $0.nameJA == name })
    }
    let edobashi = try mark("江戸橋JCT")
    let tanimachi = try mark("谷町JCT")
    let kanko = try mark("金港JCT")
    let daikoku = try mark("大黒JCT")
    let central = ((edobashi.x - tanimachi.x) * (edobashi.x - tanimachi.x)
      + (edobashi.y - tanimachi.y) * (edobashi.y - tanimachi.y))
      .squareRoot()
    let peripheral = ((kanko.x - daikoku.x) * (kanko.x - daikoku.x)
      + (kanko.y - daikoku.y) * (kanko.y - daikoku.y)).squareRoot()
    #expect(central > peripheral)
  }

  private func makeLayout() throws -> NetworkOverviewLayout? {
    let database = try loadDatabase()
    let nodesByID = Dictionary(
      uniqueKeysWithValues: database.nodes.map {
        ($0.nodeID, $0.coordinate)
      }
    )
    let ways: [NetworkOverviewLayout.WayInput] = database.ways.compactMap {
      way in
      guard way.kind == "MAINLINE",
        let routeID = way.routeMemberships.first?.routeID
      else { return nil }
      let coordinates = way.nodeIDs.compactMap { nodesByID[$0] }.map {
        RouteTrackMapLayout.GeoPoint(
          latitude: $0.latitude,
          longitude: $0.longitude
        )
      }
      guard coordinates.count > 1 else { return nil }
      return NetworkOverviewLayout.WayInput(
        routeID: routeID,
        coordinates: coordinates
      )
    }
    return NetworkOverviewLayout.make(
      ways: ways,
      facilities: database.directionalFacilities
        .filter { $0.operationalStatus == "AVAILABLE" }
        .map {
          NetworkOverviewLayout.FacilityInput(
            id: $0.facilityID,
            nameJA: $0.nameJA,
            coordinate: RouteTrackMapLayout.GeoPoint(
              latitude: $0.coordinate.latitude,
              longitude: $0.coordinate.longitude
            ),
            entranceDirectionCount: $0.entranceDirections.count,
            exitDirectionCount: $0.exitDirections.count,
            etcOnly: $0.etcOnly
          )
        },
      junctions: database.junctions.compactMap { junction in
        guard let coordinate = junction.coordinate else { return nil }
        return NetworkOverviewLayout.JunctionInput(
          id: junction.junctionID,
          nameJA: junction.nameJA,
          coordinate: RouteTrackMapLayout.GeoPoint(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
          )
        )
      },
      parkingAreas: database.parkingAreas.map {
        NetworkOverviewLayout.ParkingAreaInput(
          id: $0.parkingAreaID,
          nameJA: $0.nameJA,
          baseNameJA: $0.baseNameJA,
          routeID: $0.routeID,
          directionJA: $0.directionJA,
          coordinate: RouteTrackMapLayout.GeoPoint(
            latitude: $0.coordinate.latitude,
            longitude: $0.coordinate.longitude
          )
        )
      },
      badgeLabels: [
        "C1": "C1", "C2": "C2", "B": "B", "1_UENO": "1",
        "1_HANEDA": "1", "3": "3", "4": "4", "K1": "K1",
      ]
    )
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
      .appendingPathComponent("shuto-whole-network-20260804.json")
    return try JSONDecoder().decode(
      ShutoNetworkDatabase.self,
      from: Data(contentsOf: url)
    )
  }
}
