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

public enum ShutoOperationalBranchCatalog {
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
    )
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
}
