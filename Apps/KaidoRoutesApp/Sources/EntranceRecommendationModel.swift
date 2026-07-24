import Foundation
import KaidoRouting

struct EntranceRecommendationFixture: Equatable, Sendable {
  let networkSnapshotID: String
  let allowedJoinOccurrenceIDs: Set<String>
  let candidates: [EntranceCandidate]
  let facilityTitles: [String: String]
  let carriagewayTitles: [String: String]

  static let synthetic = EntranceRecommendationFixture(
    networkSnapshotID: "preview.synthetic.snapshot-v1",
    allowedJoinOccurrenceIDs: ["preview.synthetic.occurrence.entry.0"],
    candidates: [
      EntranceCandidate(
        facilityID: "preview.synthetic.entrance.nearest.westbound",
        targetCarriagewayID: "preview.synthetic.carriageway.westbound",
        straightLineDistanceKM: 0.5,
        surfaceETAMinutes: 3,
        legalJoinOccurrenceIDs: []
      ),
      EntranceCandidate(
        facilityID: "preview.synthetic.entrance.unknown.eastbound",
        targetCarriagewayID: "preview.synthetic.carriageway.eastbound",
        straightLineDistanceKM: 0.9,
        surfaceETAMinutes: 4,
        legalJoinOccurrenceIDs: ["preview.synthetic.occurrence.entry.0"],
        approachAvailability: .unknown
      ),
      EntranceCandidate(
        facilityID: "preview.synthetic.entrance.eastbound",
        targetCarriagewayID: "preview.synthetic.carriageway.eastbound",
        straightLineDistanceKM: 1.8,
        surfaceETAMinutes: 7,
        legalJoinOccurrenceIDs: ["preview.synthetic.occurrence.entry.0"]
      ),
    ],
    facilityTitles: [
      "preview.synthetic.entrance.nearest.westbound": "最近入口 · 西向",
      "preview.synthetic.entrance.unknown.eastbound": "近距离入口 · 东向",
      "preview.synthetic.entrance.eastbound": "演示入口 · 东向",
    ],
    carriagewayTitles: [
      "preview.synthetic.carriageway.westbound": "演示主线 · 西向",
      "preview.synthetic.carriageway.eastbound": "演示主线 · 东向",
    ]
  )
}

enum EntranceRecommendationModelError: Error, Equatable, Sendable {
  case networkSnapshotMismatch
  case recommendationRejected([String])
  case noEligibleCandidate
  case editorEntranceMismatch
  case editorJoinMismatch
  case missingPresentationLabel(String)

  var code: String {
    switch self {
    case .networkSnapshotMismatch:
      "ENTRANCE_RECOMMENDATION_SNAPSHOT_MISMATCH"
    case .recommendationRejected:
      "ENTRANCE_RECOMMENDATION_INPUT_REJECTED"
    case .noEligibleCandidate:
      "NO_ELIGIBLE_ENTRANCE_RECOMMENDATION"
    case .editorEntranceMismatch:
      "ENTRANCE_RECOMMENDATION_EDITOR_ENTRANCE_MISMATCH"
    case .editorJoinMismatch:
      "ENTRANCE_RECOMMENDATION_EDITOR_JOIN_MISMATCH"
    case .missingPresentationLabel:
      "ENTRANCE_RECOMMENDATION_LABEL_MISSING"
    }
  }
}

struct EntranceRecommendationRejectedCandidate: Equatable, Sendable {
  let facilityID: String
  let facilityTitle: String
  let targetCarriagewayID: String
  let targetCarriagewayTitle: String
  let straightLineDistanceKM: Double
  let surfaceETAMinutes: Double
  let reasonCodes: [String]
}

struct EntranceRecommendationSnapshot: Equatable, Sendable {
  let networkSnapshotID: String
  let selection: EntranceRecommendationSelection
  let selectedFacilityTitle: String
  let selectedCarriagewayTitle: String
  let rejectedCandidates: [EntranceRecommendationRejectedCandidate]

  var isProximityOnly: Bool {
    !selection.reasonCodes.contains(.exactDirectionalCarriageway)
      || !selection.reasonCodes.contains(.legalRouteJoin)
  }
}

@MainActor
final class EntranceRecommendationModel {
  let fixture: EntranceRecommendationFixture
  let snapshot: EntranceRecommendationSnapshot

  init(
    routeEditor: ParkedRouteEditorModel,
    fixture: EntranceRecommendationFixture = .synthetic
  ) throws {
    self.fixture = fixture
    guard fixture.networkSnapshotID == routeEditor.snapshot.networkSnapshotID else {
      throw EntranceRecommendationModelError.networkSnapshotMismatch
    }

    let recommendation = EntranceRecommender.recommend(
      candidates: fixture.candidates,
      allowedJoinOccurrenceIDs: fixture.allowedJoinOccurrenceIDs
    )
    if recommendation.status == .rejected {
      throw EntranceRecommendationModelError.recommendationRejected(
        recommendation.errorCodes
      )
    }
    guard recommendation.status == .selected,
      let selection = recommendation.selection
    else {
      throw EntranceRecommendationModelError.noEligibleCandidate
    }
    guard selection.facilityID == routeEditor.fixture.entranceFacilityID else {
      throw EntranceRecommendationModelError.editorEntranceMismatch
    }
    guard selection.joinOccurrenceID == routeEditor.fixture.initialOccurrenceID else {
      throw EntranceRecommendationModelError.editorJoinMismatch
    }

    let selectedFacilityTitle = try Self.label(
      selection.facilityID,
      in: fixture.facilityTitles
    )
    let selectedCarriagewayTitle = try Self.label(
      selection.targetCarriagewayID,
      in: fixture.carriagewayTitles
    )
    let candidateByFacilityID = Dictionary(
      uniqueKeysWithValues: fixture.candidates.map { ($0.facilityID, $0) }
    )
    let rejectedCandidates = try recommendation.rejections.map {
      facilityID,
      reasonCodes in
      guard let candidate = candidateByFacilityID[facilityID] else {
        throw EntranceRecommendationModelError.missingPresentationLabel(
          facilityID
        )
      }
      return EntranceRecommendationRejectedCandidate(
        facilityID: facilityID,
        facilityTitle: try Self.label(
          facilityID,
          in: fixture.facilityTitles
        ),
        targetCarriagewayID: candidate.targetCarriagewayID,
        targetCarriagewayTitle: try Self.label(
          candidate.targetCarriagewayID,
          in: fixture.carriagewayTitles
        ),
        straightLineDistanceKM: candidate.straightLineDistanceKM,
        surfaceETAMinutes: candidate.surfaceETAMinutes,
        reasonCodes: reasonCodes
      )
    }.sorted {
      if $0.straightLineDistanceKM != $1.straightLineDistanceKM {
        return $0.straightLineDistanceKM < $1.straightLineDistanceKM
      }
      return $0.facilityID < $1.facilityID
    }

    snapshot = EntranceRecommendationSnapshot(
      networkSnapshotID: fixture.networkSnapshotID,
      selection: selection,
      selectedFacilityTitle: selectedFacilityTitle,
      selectedCarriagewayTitle: selectedCarriagewayTitle,
      rejectedCandidates: rejectedCandidates
    )
  }

  private static func label(
    _ id: String,
    in values: [String: String]
  ) throws -> String {
    guard let value = values[id],
      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw EntranceRecommendationModelError.missingPresentationLabel(id)
    }
    return value
  }
}
