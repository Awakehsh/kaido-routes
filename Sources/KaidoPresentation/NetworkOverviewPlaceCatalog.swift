import Foundation
import KaidoDomain

/// Presentation anchors for the whole-network browse map. Parking-area
/// identities come from the bundled snapshot; scenic coordinates are public
/// place positions used only to sit a name next to the diagram, never as
/// road, entrance, or movement authority.
public enum NetworkOverviewPlaceCatalog {
  /// PA names that stay on the small (unzoomed) diagram. Every snapshot PA
  /// name appears once the driver pinches past the detail threshold.
  public static let notableParkingAreaIDs: Set<String> = [
    "shuto.pa.daikoku",
    "shuto.pa.tatsumi-1",
    "shuto.pa.shibaura",
    "shuto.pa.heiwajima-inbound",
    "shuto.pa.oi-westbound",
    "shuto.pa.hakozaki",
  ]

  /// Operator 名所グラフ bridges plus the city marks named from C1 and the
  /// waterfront. Bridge seeds snap onto the snapshot carriageway; city marks
  /// sit beside it.
  public static let scenic: [NetworkOverviewLayout.PlaceInput] = [
    .init(
      id: "place.tokyo-tower",
      nameJA: "東京タワー",
      nameZH: "东京塔",
      nameEN: "Tokyo Tower",
      coordinate: .init(latitude: 35.658581, longitude: 139.745438),
      routeIDs: ["C1"],
      snapToRoute: false,
      icon: .tokyoTower
    ),
    .init(
      id: "place.tokyo-skytree",
      nameJA: "東京スカイツリー",
      nameZH: "东京晴空塔",
      nameEN: "Tokyo Skytree",
      coordinate: .init(latitude: 35.710052, longitude: 139.810700),
      routeIDs: ["6_MUKOJIMA", "9"],
      snapToRoute: false,
      icon: .tokyoSkytree
    ),
    .init(
      id: "place.haneda-airport",
      nameJA: "羽田空港",
      nameZH: "羽田机场",
      nameEN: "Haneda Airport",
      coordinate: .init(latitude: 35.5494, longitude: 139.7798),
      routeIDs: ["B", "1_HANEDA"],
      snapToRoute: false,
      icon: .airplane
    ),
    .init(
      id: "place.minato-mirai",
      nameJA: "みなとみらい",
      nameZH: "港未来",
      nameEN: "Minato Mirai",
      coordinate: .init(latitude: 35.4547, longitude: 139.6311),
      routeIDs: ["K1"],
      snapToRoute: false,
      icon: .ferrisWheel
    ),
    .init(
      id: "place.rainbow-bridge",
      nameJA: "レインボーブリッジ",
      nameZH: "彩虹桥",
      nameEN: "Rainbow Bridge",
      coordinate: .init(latitude: 35.6366, longitude: 139.7630),
      routeIDs: ["11"],
      snapToRoute: true,
      icon: .suspensionBridge
    ),
    .init(
      id: "place.yokohama-bay-bridge",
      nameJA: "横浜ベイブリッジ",
      nameZH: "横滨海湾大桥",
      nameEN: "Yokohama Bay Bridge",
      coordinate: .init(latitude: 35.4545, longitude: 139.6740),
      routeIDs: ["B"],
      snapToRoute: true,
      icon: .cableStayedBridge
    ),
    .init(
      id: "place.tsurumi-tsubasa-bridge",
      nameJA: "鶴見つばさ橋",
      nameZH: "鹤见翼桥",
      nameEN: "Tsurumi Tsubasa Bridge",
      coordinate: .init(latitude: 35.473, longitude: 139.685),
      routeIDs: ["B"],
      snapToRoute: true,
      icon: .cableStayedBridge
    ),
    .init(
      id: "place.katsushika-harp-bridge",
      nameJA: "かつしかハープ橋",
      nameZH: "葛饰竖琴桥",
      nameEN: "Katsushika Harp Bridge",
      coordinate: .init(latitude: 35.72278, longitude: 139.84250),
      routeIDs: ["C2"],
      snapToRoute: true,
      icon: .harpBridge
    ),
    .init(
      id: "place.goshikizakura-bridge",
      nameJA: "五色桜大橋",
      nameZH: "五色樱大桥",
      nameEN: "Goshikizakura Bridge",
      coordinate: .init(latitude: 35.76530, longitude: 139.76020),
      routeIDs: ["C2"],
      snapToRoute: true,
      icon: .archBridge
    ),
  ]
}
