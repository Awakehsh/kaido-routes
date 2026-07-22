import Foundation

public enum EntranceProbeFixtureValidationProfile: String, Codable, Sendable {
  case structural = "STRUCTURAL"
  case releaseCandidate = "RELEASE_CANDIDATE"
}

public struct EntranceProbeFixtureValidationReport: Codable, Equatable, Sendable {
  public let fixtureID: String
  public let profile: EntranceProbeFixtureValidationProfile
  public let issues: [FixtureValidationIssue]

  public init(
    fixtureID: String,
    profile: EntranceProbeFixtureValidationProfile,
    issues: [FixtureValidationIssue]
  ) {
    self.fixtureID = fixtureID
    self.profile = profile
    self.issues = issues
  }

  public var isValid: Bool { issues.isEmpty }

  private enum CodingKeys: String, CodingKey {
    case fixtureID = "fixture_id"
    case profile
    case issues
    case isValid = "is_valid"
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(fixtureID, forKey: .fixtureID)
    try container.encode(profile, forKey: .profile)
    try container.encode(issues, forKey: .issues)
    try container.encode(isValid, forKey: .isValid)
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    fixtureID = try container.decode(String.self, forKey: .fixtureID)
    profile = try container.decode(EntranceProbeFixtureValidationProfile.self, forKey: .profile)
    issues = try container.decode([FixtureValidationIssue].self, forKey: .issues)
  }
}

public enum EntranceProbeFixtureValidator {
  public static func validate(
    _ fixture: EntranceProbeFixture,
    graph: SurfaceRoadGraphSnapshot,
    profile: EntranceProbeFixtureValidationProfile
  ) -> EntranceProbeFixtureValidationReport {
    var issues =
      profile == .releaseCandidate
      ? fixture.releaseValidationIssues() : fixture.structuralValidationIssues()

    if fixture.networkSnapshotID != graph.networkSnapshotID {
      issues.append(.init(code: "NETWORK_SNAPSHOT_MISMATCH", path: "network_snapshot_id"))
    }

    var edgesByID: [String: SurfaceRoadEdge] = [:]
    for (index, edge) in graph.edges.enumerated() {
      if edgesByID[edge.id] != nil {
        issues.append(.init(code: "GRAPH_DUPLICATE_EDGE_ID", path: "graph.edges[\(index)].id"))
      } else {
        edgesByID[edge.id] = edge
      }
    }
    let approachEdge = edgesByID[fixture.approachAnchor.directedSurfaceEdgeID]
    if approachEdge == nil {
      issues.append(
        .init(code: "APPROACH_EDGE_MISSING", path: "approach_anchor.directed_surface_edge_id")
      )
    } else if approachEdge?.kind != .ordinaryRoad {
      issues.append(
        .init(
          code: "APPROACH_EDGE_NOT_ORDINARY_ROAD",
          path: "approach_anchor.directed_surface_edge_id"
        )
      )
    }

    let transitionEdges = fixture.entryTransition.directedEdgeIDs.compactMap { edgesByID[$0] }
    for (index, edgeID) in fixture.entryTransition.directedEdgeIDs.enumerated() {
      guard let edge = edgesByID[edgeID] else {
        issues.append(
          .init(
            code: "ENTRY_TRANSITION_EDGE_MISSING",
            path: "entry_transition.directed_edge_ids[\(index)]")
        )
        continue
      }
      if edge.kind != .entryTransition {
        issues.append(
          .init(
            code: "ENTRY_TRANSITION_EDGE_KIND_MISMATCH",
            path: "entry_transition.directed_edge_ids[\(index)]"
          )
        )
      }
    }

    if transitionEdges.count == fixture.entryTransition.directedEdgeIDs.count,
      let firstTransition = transitionEdges.first,
      let approachEdge,
      approachEdge.toNodeID != firstTransition.fromNodeID
    {
      issues.append(
        .init(code: "APPROACH_TO_TRANSITION_DISCONNECTED", path: "entry_transition")
      )
    }
    if transitionEdges.count == fixture.entryTransition.directedEdgeIDs.count {
      for (index, pair) in zip(transitionEdges, transitionEdges.dropFirst()).enumerated()
      where pair.0.toNodeID != pair.1.fromNodeID {
        issues.append(
          .init(
            code: "ENTRY_TRANSITION_DISCONNECTED",
            path: "entry_transition.directed_edge_ids[\(index + 1)]"
          )
        )
      }
    }

    if let targetEdgeID = fixture.entryTransition.targetExpresswayEdgeID {
      if let targetEdge = edgesByID[targetEdgeID] {
        if targetEdge.kind != .expressway {
          issues.append(
            .init(
              code: "TARGET_EDGE_NOT_EXPRESSWAY",
              path: "entry_transition.target_expressway_edge_id"
            )
          )
        }
        if transitionEdges.count == fixture.entryTransition.directedEdgeIDs.count,
          let lastTransition = transitionEdges.last,
          lastTransition.toNodeID != targetEdge.fromNodeID
        {
          issues.append(
            .init(
              code: "TRANSITION_TO_TARGET_DISCONNECTED",
              path: "entry_transition.target_expressway_edge_id"
            )
          )
        }
      } else {
        issues.append(
          .init(
            code: "TARGET_EXPRESSWAY_EDGE_MISSING",
            path: "entry_transition.target_expressway_edge_id"
          )
        )
      }
    } else if profile == .releaseCandidate {
      issues.append(
        .init(
          code: "TARGET_EXPRESSWAY_EDGE_REQUIRED",
          path: "entry_transition.target_expressway_edge_id"
        )
      )
    }

    return EntranceProbeFixtureValidationReport(
      fixtureID: fixture.id,
      profile: profile,
      issues: issues
    )
  }
}
