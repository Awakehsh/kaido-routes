/// The passes of each road a RoutePlan drives more than once, and which of
/// them a car first seen at the start of the drive can have reached.
///
/// Geometry cannot tell two passes of one road apart. A loop can drive the
/// road beside its entrance again near its end, and a matcher that settles on
/// that later pass cannot move back. Before the session has progress of its
/// own, the car can only be on the earliest pass it can have reached since it
/// was first seen, under the session's reach rule.
package struct RoutePassReach: Sendable {
  private let passesByEdgeID: [String: [Int]]
  private let occurrenceIDByIndex: [Int: String]
  private let indexByOccurrenceID: [String: Int]
  private let distanceBeforeIndex: [Int: Double]

  package init(corridor: RouteMatcherCorridor) {
    let occurrences = corridor.occurrences.sorted { $0.index < $1.index }
    let lengths = Dictionary(
      corridor.edges.map { ($0.id, $0.lengthMeters) },
      uniquingKeysWith: { first, _ in first }
    )
    var distance = 0.0
    var distanceBeforeIndex: [Int: Double] = [:]
    for occurrence in occurrences {
      distanceBeforeIndex[occurrence.index] = distance
      distance += lengths[occurrence.directedEdgeID] ?? 0
    }
    self.distanceBeforeIndex = distanceBeforeIndex
    passesByEdgeID = Dictionary(grouping: occurrences, by: \.directedEdgeID)
      .compactMapValues { $0.count > 1 ? $0.map(\.index) : nil }
    occurrenceIDByIndex = Dictionary(
      occurrences.map { ($0.index, $0.id) },
      uniquingKeysWith: { first, _ in first }
    )
    indexByOccurrenceID = Dictionary(
      occurrences.map { ($0.id, $0.index) },
      uniquingKeysWith: { first, _ in first }
    )
  }

  /// The earliest pass of the estimate's road, when the matcher placed the
  /// car on a later one and the car can have reached the earliest within
  /// `elapsedMilliseconds` of being first seen at the route start.
  package func earlierPass(
    of estimate: MatcherEstimate,
    elapsedMilliseconds: Int
  ) -> String? {
    guard let edgeID = estimate.directedEdgeID,
      let earliest = passesByEdgeID[edgeID]?.first,
      let matched = estimate.occurrenceID.flatMap({ indexByOccurrenceID[$0] }),
      earliest < matched,
      let distance = distanceBeforeIndex[earliest]
    else { return nil }
    let reach =
      Double(max(0, elapsedMilliseconds)) / 1_000
      * NavigationSession.maximumPlausibleSpeedMetersPerSecond
      + NavigationSession.reachMarginMeters
    return distance <= reach ? occurrenceIDByIndex[earliest] : nil
  }
}
