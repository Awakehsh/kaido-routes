import Foundation

/// A dated, snapshot-bound correction for an operational branch whose OSM
/// route membership is insufficient to decide whether it remains expressway
/// mainline or leaves to the surface.
public struct ShutoReviewedSurfaceExitBranch: Equatable, Sendable {
  public let id: String
  public let networkSnapshotID: String
  public let junctionNodeID: Int64
  public let incomingDirectedEdgeID: String
  public let startDirectedEdgeID: String
  public let terminalDirectedEdgeID: String
  public let exitNameJapanese: String
  public let effectiveAt: String
  public let checkedAt: String
  public let officialSourceURL: String
}

/// A snapshot-bound graph fragment that cannot carry a RoutePlan movement.
/// This is distinct from a surface exit: the source may label the fragment as
/// an expressway link, but its pinned directed chain reaches no later graph
/// edge and the operator diagram publishes no corresponding JCT branch.
public struct ShutoReviewedNonNavigableBranch: Equatable, Sendable {
  public let id: String
  public let networkSnapshotID: String
  public let junctionNodeID: Int64
  public let incomingDirectedEdgeID: String
  public let startDirectedEdgeID: String
  public let terminalDirectedEdgeID: String
  public let reason: String
  public let checkedAt: String
  public let sourceURLs: [String]
}

public enum ShutoOperationalBranchCatalog {
  public static let reviewedNonNavigableBranches = [
    ShutoReviewedNonNavigableBranch(
      id: "shuto.non-navigable.namamugi-k1-promoted-link-dead-end",
      networkSnapshotID:
        "shuto-official-2026-07-29-osm-2026-08-04",
      junctionNodeID: 4_360_978_732,
      incomingDirectedEdgeID: "osm.32592648.13.forward",
      startDirectedEdgeID: "osm.567321755.0.forward",
      terminalDirectedEdgeID: "osm.1022520297.2.forward",
      reason: "PROMOTED_MOTORWAY_LINK_DEAD_END",
      checkedAt: "2026-08-15",
      sourceURLs: [
        "https://www.shutoko.jp/-/media/images/responsive/"
          + "customer/use/network/jct/routeguide/jct_namamugi",
        "https://www.shutoko.jp/use/network/map/route-k1/asada",
      ]
    )
  ]

  public static let reviewedSurfaceExitBranches = [
    ShutoReviewedSurfaceExitBranch(
      id: "shuto.exit.higashiginza.from-kyobashi",
      networkSnapshotID:
        "shuto-official-2026-07-29-osm-2026-08-04",
      junctionNodeID: 572_570_042,
      incomingDirectedEdgeID: "osm.378284505.0.forward",
      startDirectedEdgeID: "osm.4849055.0.forward",
      terminalDirectedEdgeID: "osm.203301443.0.forward",
      exitNameJapanese: "東銀座出口",
      effectiveAt: "2025-04-05T20:00:00+09:00",
      checkedAt: "2026-08-15",
      officialSourceURL:
        "https://www.shutoko.jp/traffic/control/blockinfo/"
        + "ndata/20250210_0904/"
    ),
    ShutoReviewedSurfaceExitBranch(
      id: "shuto.exit.daishi.from-k6-north-loop",
      networkSnapshotID:
        "shuto-official-2026-07-29-osm-2026-08-04",
      junctionNodeID: 448_041_015,
      incomingDirectedEdgeID: "osm.964816693.3.forward",
      startDirectedEdgeID: "osm.82596771.0.forward",
      terminalDirectedEdgeID: "osm.82596774.28.forward",
      exitNameJapanese: "大師出口",
      effectiveAt: "2026-08-15T00:00:00+09:00",
      checkedAt: "2026-08-15",
      officialSourceURL:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_daishi"
    ),
    ShutoReviewedSurfaceExitBranch(
      id: "shuto.exit.daishi.from-k6-south-loop",
      networkSnapshotID:
        "shuto-official-2026-07-29-osm-2026-08-04",
      junctionNodeID: 3_817_775_796,
      incomingDirectedEdgeID: "osm.82596772.7.forward",
      startDirectedEdgeID: "osm.82596774.0.forward",
      terminalDirectedEdgeID: "osm.82596774.28.forward",
      exitNameJapanese: "大師出口",
      effectiveAt: "2026-08-15T00:00:00+09:00",
      checkedAt: "2026-08-15",
      officialSourceURL:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_daishi"
    ),
    ShutoReviewedSurfaceExitBranch(
      id: "shuto.exit.hakozaki-rotary.from-6-inbound",
      networkSnapshotID:
        "shuto-official-2026-07-29-osm-2026-08-04",
      junctionNodeID: 565_479_944,
      incomingDirectedEdgeID: "osm.1544854470.2.forward",
      startDirectedEdgeID: "osm.766719786.0.forward",
      terminalDirectedEdgeID: "osm.157249387.3.forward",
      exitNameJapanese: "箱崎出口・箱崎PA",
      effectiveAt: "2026-08-15T00:00:00+09:00",
      checkedAt: "2026-08-15",
      officialSourceURL:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_hakozaki"
    ),
    ShutoReviewedSurfaceExitBranch(
      id: "shuto.exit.hakozaki-rotary.from-6-outbound",
      networkSnapshotID:
        "shuto-official-2026-07-29-osm-2026-08-04",
      junctionNodeID: 1_694_598_897,
      incomingDirectedEdgeID: "osm.1544832379.11.forward",
      startDirectedEdgeID: "osm.157249374.0.forward",
      terminalDirectedEdgeID: "osm.157249387.3.forward",
      exitNameJapanese: "箱崎出口・箱崎PA",
      effectiveAt: "2026-08-15T00:00:00+09:00",
      checkedAt: "2026-08-15",
      officialSourceURL:
        "https://www.shutoko.jp/-/media/images/responsive/"
        + "customer/use/network/jct/routeguide/jct_hakozaki"
    ),
  ]

  public static func reviewedSurfaceExitBranch(
    networkSnapshotID: String,
    startDirectedEdgeID: String
  ) -> ShutoReviewedSurfaceExitBranch? {
    reviewedSurfaceExitBranches.first {
      $0.networkSnapshotID == networkSnapshotID
        && $0.startDirectedEdgeID == startDirectedEdgeID
    }
  }

  public static func reviewedNonNavigableBranch(
    networkSnapshotID: String,
    incomingDirectedEdgeID: String,
    startDirectedEdgeID: String
  ) -> ShutoReviewedNonNavigableBranch? {
    reviewedNonNavigableBranches.first {
      $0.networkSnapshotID == networkSnapshotID
        && $0.incomingDirectedEdgeID == incomingDirectedEdgeID
        && $0.startDirectedEdgeID == startDirectedEdgeID
    }
  }
}
