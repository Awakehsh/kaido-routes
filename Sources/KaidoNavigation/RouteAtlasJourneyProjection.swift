import KaidoDomain

/// The renderer-neutral visual state of one exact RoutePlan occurrence.
///
/// `planned` is used before a NavigationSnapshot exists. Once actor-owned
/// progress is supplied, every occurrence is passed, current, future, or
/// skipped. Repeated occurrences remain separate values even when they share
/// one schematic segment.
public enum RouteAtlasJourneyOccurrenceState: String, Codable, Equatable, Sendable {
  case planned = "PLANNED"
  case passed = "PASSED"
  case current = "CURRENT"
  case future = "FUTURE"
  case skipped = "SKIPPED"
}

public struct RouteAtlasJourneyContextSegment: Equatable, Sendable {
  public let segmentID: String
  public let points: [RouteAtlasPoint]

  public init(segmentID: String, points: [RouteAtlasPoint]) {
    self.segmentID = segmentID
    self.points = points
  }
}

public struct RouteAtlasJourneyAttribution: Equatable, Sendable {
  public let sourceID: String
  public let authorityName: String
  public let sourceURL: String
  public let licenceIdentifier: String

  public init(
    sourceID: String,
    authorityName: String,
    sourceURL: String,
    licenceIdentifier: String
  ) {
    self.sourceID = sourceID
    self.authorityName = authorityName
    self.sourceURL = sourceURL
    self.licenceIdentifier = licenceIdentifier
  }
}

public struct RouteAtlasJourneyOccurrence: Equatable, Sendable {
  public let occurrenceID: String
  public let occurrenceIndex: Int
  public let segmentID: String
  public let points: [RouteAtlasPoint]
  public let state: RouteAtlasJourneyOccurrenceState
  public let repeatOrdinal: Int
  public let repeatCount: Int

  public init(
    occurrenceID: String,
    occurrenceIndex: Int,
    segmentID: String,
    points: [RouteAtlasPoint],
    state: RouteAtlasJourneyOccurrenceState,
    repeatOrdinal: Int,
    repeatCount: Int
  ) {
    self.occurrenceID = occurrenceID
    self.occurrenceIndex = occurrenceIndex
    self.segmentID = segmentID
    self.points = points
    self.state = state
    self.repeatOrdinal = repeatOrdinal
    self.repeatCount = repeatCount
  }

  public var isRepeatedTraversal: Bool {
    repeatCount > 1
  }
}

/// One immutable atlas projection bound to the exact released snapshot,
/// RoutePlan, layout, and optional actor-owned progress state.
public struct RouteAtlasJourneyProjection: Equatable, Sendable {
  public let networkSnapshotID: String
  public let routePlanID: String
  public let atlasID: String
  public let topologySliceID: String
  public let contextSegments: [RouteAtlasJourneyContextSegment]
  public let occurrences: [RouteAtlasJourneyOccurrence]
  public let attributions: [RouteAtlasJourneyAttribution]
  public let currentOccurrenceID: String?

  public init(
    networkSnapshotID: String,
    routePlanID: String,
    atlasID: String,
    topologySliceID: String,
    contextSegments: [RouteAtlasJourneyContextSegment],
    occurrences: [RouteAtlasJourneyOccurrence],
    attributions: [RouteAtlasJourneyAttribution],
    currentOccurrenceID: String?
  ) {
    self.networkSnapshotID = networkSnapshotID
    self.routePlanID = routePlanID
    self.atlasID = atlasID
    self.topologySliceID = topologySliceID
    self.contextSegments = contextSegments
    self.occurrences = occurrences
    self.attributions = attributions
    self.currentOccurrenceID = currentOccurrenceID
  }
}

public enum RouteAtlasJourneyProjectionIssue: Equatable, Sendable {
  case routePlanMismatch
  case missingCurrentOccurrence
  case unknownCurrentOccurrence(String)
  case currentOccurrenceIndexMismatch(String)
  case duplicateProgressOccurrence(String)
  case unknownProgressOccurrence(String)
  case currentOccurrenceSkipped(String)
  case completedProgressOrderMismatch
  case pendingProgressOrderMismatch
  case invalidOccurrenceBinding(String)

  public var code: String {
    switch self {
    case .routePlanMismatch:
      "ATLAS_OVERLAY_ROUTE_PLAN_MISMATCH"
    case .missingCurrentOccurrence:
      "ATLAS_OVERLAY_CURRENT_OCCURRENCE_MISSING"
    case .unknownCurrentOccurrence:
      "ATLAS_OVERLAY_CURRENT_OCCURRENCE_UNKNOWN"
    case .currentOccurrenceIndexMismatch:
      "ATLAS_OVERLAY_CURRENT_INDEX_MISMATCH"
    case .duplicateProgressOccurrence:
      "ATLAS_OVERLAY_PROGRESS_OCCURRENCE_DUPLICATE"
    case .unknownProgressOccurrence:
      "ATLAS_OVERLAY_PROGRESS_OCCURRENCE_UNKNOWN"
    case .currentOccurrenceSkipped:
      "ATLAS_OVERLAY_CURRENT_OCCURRENCE_SKIPPED"
    case .completedProgressOrderMismatch:
      "ATLAS_OVERLAY_COMPLETED_ORDER_MISMATCH"
    case .pendingProgressOrderMismatch:
      "ATLAS_OVERLAY_PENDING_ORDER_MISMATCH"
    case .invalidOccurrenceBinding:
      "ATLAS_OVERLAY_BINDING_INVALID"
    }
  }

  fileprivate var sortKey: String {
    switch self {
    case .unknownCurrentOccurrence(let id),
      .currentOccurrenceIndexMismatch(let id),
      .duplicateProgressOccurrence(let id),
      .unknownProgressOccurrence(let id),
      .currentOccurrenceSkipped(let id),
      .invalidOccurrenceBinding(let id):
      "\(code):\(id)"
    default:
      code
    }
  }
}

public enum RouteAtlasJourneyProjectionError: Error, Equatable, Sendable {
  case invalid([RouteAtlasJourneyProjectionIssue])
}

/// Projects only a validated RouteAtlasRelease.
///
/// The renderer receives exact released points and occurrence identities. It
/// never infers a connection from coordinate contact and never derives route
/// progress itself.
public enum RouteAtlasJourneyProjector {
  public static func project(
    release: RouteAtlasRelease,
    navigationSnapshot: NavigationSnapshot? = nil
  ) throws -> RouteAtlasJourneyProjection {
    let issues = progressIssues(
      routePlan: release.routePlan,
      navigationSnapshot: navigationSnapshot
    )
    guard issues.isEmpty else {
      throw RouteAtlasJourneyProjectionError.invalid(issues)
    }

    let segmentsByID = Dictionary(
      uniqueKeysWithValues: release.definition.segments.map { ($0.id, $0) }
    )
    var repeatedCounts: [String: Int] = [:]
    for binding in release.definition.occurrenceBindings {
      repeatedCounts[binding.segmentID, default: 0] += 1
    }
    var repeatedOrdinals: [String: Int] = [:]
    var projectionIssues: [RouteAtlasJourneyProjectionIssue] = []
    let occurrences = release.definition.occurrenceBindings.compactMap {
      binding -> RouteAtlasJourneyOccurrence? in
      guard let segment = segmentsByID[binding.segmentID] else {
        projectionIssues.append(
          .invalidOccurrenceBinding(binding.occurrenceID)
        )
        return nil
      }
      let ordinal = repeatedOrdinals[binding.segmentID, default: 0] + 1
      repeatedOrdinals[binding.segmentID] = ordinal
      return RouteAtlasJourneyOccurrence(
        occurrenceID: binding.occurrenceID,
        occurrenceIndex: binding.occurrenceIndex,
        segmentID: binding.segmentID,
        points: segment.points,
        state: state(
          for: binding.occurrenceID,
          navigationSnapshot: navigationSnapshot
        ),
        repeatOrdinal: ordinal,
        repeatCount: repeatedCounts[binding.segmentID] ?? 1
      )
    }
    guard projectionIssues.isEmpty else {
      throw RouteAtlasJourneyProjectionError.invalid(
        sortedUnique(projectionIssues)
      )
    }

    return RouteAtlasJourneyProjection(
      networkSnapshotID: release.networkSnapshot.id,
      routePlanID: release.routePlan.id,
      atlasID: release.definition.id,
      topologySliceID: release.topologySlice.id,
      contextSegments: release.definition.segments.map {
        RouteAtlasJourneyContextSegment(
          segmentID: $0.id,
          points: $0.points
        )
      },
      occurrences: occurrences,
      attributions: release.sourceRegistry.references
        .sorted { $0.id < $1.id }
        .map {
          RouteAtlasJourneyAttribution(
            sourceID: $0.id,
            authorityName: $0.authorityName,
            sourceURL: $0.sourceURL,
            licenceIdentifier: $0.licenceIdentifier
          )
        },
      currentOccurrenceID:
        navigationSnapshot?.journeyPhase == .completed
        ? nil
        : navigationSnapshot?.currentOccurrenceID
    )
  }

  private static func progressIssues(
    routePlan: RoutePlan,
    navigationSnapshot: NavigationSnapshot?
  ) -> [RouteAtlasJourneyProjectionIssue] {
    guard let snapshot = navigationSnapshot else { return [] }
    var issues: [RouteAtlasJourneyProjectionIssue] = []
    guard snapshot.activeRoutePlanID == routePlan.id else {
      return [.routePlanMismatch]
    }

    let occurrenceIDs = routePlan.occurrences.map(\.id)
    let occurrenceIDSet = Set(occurrenceIDs)
    for values in [
      snapshot.completedOccurrenceIDs,
      snapshot.pendingOccurrenceIDs,
      snapshot.skippedOccurrenceIDs,
    ] {
      var seen: Set<String> = []
      for id in values {
        if !seen.insert(id).inserted {
          issues.append(.duplicateProgressOccurrence(id))
        }
        if !occurrenceIDSet.contains(id) {
          issues.append(.unknownProgressOccurrence(id))
        }
      }
    }
    if let currentOccurrenceID = snapshot.currentOccurrenceID {
      guard
        let current = routePlan.occurrence(id: currentOccurrenceID)
      else {
        issues.append(.unknownCurrentOccurrence(currentOccurrenceID))
        return sortedUnique(issues)
      }
      if snapshot.currentOccurrenceIndex != current.index {
        issues.append(
          .currentOccurrenceIndexMismatch(currentOccurrenceID)
        )
      }
      if snapshot.skippedOccurrenceIDs.contains(currentOccurrenceID) {
        issues.append(.currentOccurrenceSkipped(currentOccurrenceID))
      }

      if snapshot.journeyPhase != .completed {
        let skipped = Set(snapshot.skippedOccurrenceIDs)
        let expectedCompleted = routePlan.occurrences
          .filter { $0.index < current.index && !skipped.contains($0.id) }
          .map(\.id)
        let expectedPending = routePlan.occurrences
          .filter { $0.index >= current.index && !skipped.contains($0.id) }
          .map(\.id)
        if snapshot.completedOccurrenceIDs != expectedCompleted {
          issues.append(.completedProgressOrderMismatch)
        }
        if snapshot.pendingOccurrenceIDs != expectedPending {
          issues.append(.pendingProgressOrderMismatch)
        }
      }
    } else if snapshot.journeyPhase != .completed {
      issues.append(.missingCurrentOccurrence)
    }

    return sortedUnique(issues)
  }

  private static func state(
    for occurrenceID: String,
    navigationSnapshot: NavigationSnapshot?
  ) -> RouteAtlasJourneyOccurrenceState {
    guard let snapshot = navigationSnapshot else { return .planned }
    if snapshot.skippedOccurrenceIDs.contains(occurrenceID) {
      return .skipped
    }
    if snapshot.journeyPhase == .completed
      || snapshot.completedOccurrenceIDs.contains(occurrenceID)
    {
      return .passed
    }
    if snapshot.currentOccurrenceID == occurrenceID {
      return .current
    }
    return .future
  }

  private static func sortedUnique(
    _ issues: [RouteAtlasJourneyProjectionIssue]
  ) -> [RouteAtlasJourneyProjectionIssue] {
    var seen: Set<String> = []
    return issues.sorted { $0.sortKey < $1.sortKey }.filter {
      seen.insert($0.sortKey).inserted
    }
  }
}
