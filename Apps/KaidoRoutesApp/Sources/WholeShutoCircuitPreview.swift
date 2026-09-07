import Foundation

struct WholeShutoCircuitPreview: Equatable, Sendable {
  let points: [CGPoint]
  let distanceMeters: Double
  let junctionCount: Int
  /// Shuto route codes in course order, from the card's representative
  /// route: what the driver reads on the overhead signs, in the order the
  /// experience actually uses them.
  let routeIDsInOrder: [String]

  var referenceMinutes: Int { max(1, Int(ceil(distanceMeters / 15 / 60))) }
}
