import Foundation

struct WholeShutoCircuitPreview: Equatable, Sendable {
  let points: [CGPoint]
  let distanceMeters: Double
  let junctionCount: Int
  let tunnelDistanceMeters: Double

  var referenceMinutes: Int { max(1, Int(ceil(distanceMeters / 15 / 60))) }
  var tunnelPercent: Int {
    distanceMeters > 0 ? Int((tunnelDistanceMeters / distanceMeters * 100).rounded()) : 0
  }
}
