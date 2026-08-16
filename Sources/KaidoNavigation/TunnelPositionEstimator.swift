import Foundation

/// A presentation-only estimate used while fresh route-resolved location is
/// unavailable inside a tunnel or covered road. It never grants matcher,
/// occurrence, branch, guidance, or completion authority.
public struct TunnelPositionEstimate: Equatable, Sendable {
  public let routeDistanceMeters: Double
  public let uncertaintyRadiusMeters: Double
  public let elapsedSeconds: Double
  public let isAtLimit: Bool

  public init(
    routeDistanceMeters: Double,
    uncertaintyRadiusMeters: Double,
    elapsedSeconds: Double,
    isAtLimit: Bool
  ) {
    self.routeDistanceMeters = routeDistanceMeters
    self.uncertaintyRadiusMeters = uncertaintyRadiusMeters
    self.elapsedSeconds = elapsedSeconds
    self.isAtLimit = isAtLimit
  }
}

/// Propagates the last route-resolved position using speed only as weak
/// evidence. Callers must supply a safety limit at or before the next released
/// decision point; this reducer cannot cross it or mutate navigation state.
public enum TunnelPositionEstimator {
  public static let maximumHorizonSeconds = 45.0
  public static let maximumSpeedMetersPerSecond = 50.0
  public static let minimumUncertaintyRadiusMeters = 25.0

  public static func estimate(
    anchorRouteDistanceMeters: Double,
    routeDistanceMeters: Double,
    safetyLimitRouteDistanceMeters: Double,
    speedMetersPerSecond: Double,
    speedAccuracyMetersPerSecond: Double?,
    elapsedMilliseconds: Int
  ) -> TunnelPositionEstimate? {
    guard
      anchorRouteDistanceMeters.isFinite,
      routeDistanceMeters.isFinite,
      safetyLimitRouteDistanceMeters.isFinite,
      speedMetersPerSecond.isFinite,
      anchorRouteDistanceMeters >= 0,
      routeDistanceMeters > 0,
      anchorRouteDistanceMeters <= routeDistanceMeters,
      safetyLimitRouteDistanceMeters >= anchorRouteDistanceMeters,
      speedMetersPerSecond > 0,
      elapsedMilliseconds >= 0,
      speedAccuracyMetersPerSecond.map({ $0.isFinite && $0 >= 0 }) != false
    else {
      return nil
    }

    let elapsedSeconds = min(
      Double(elapsedMilliseconds) / 1_000,
      maximumHorizonSeconds
    )
    let boundedSpeed = min(
      speedMetersPerSecond,
      maximumSpeedMetersPerSecond
    )
    let unconstrainedDistance =
      anchorRouteDistanceMeters
      + boundedSpeed * elapsedSeconds
    let safetyLimit = min(
      routeDistanceMeters,
      safetyLimitRouteDistanceMeters
    )
    let estimatedDistance = min(unconstrainedDistance, safetyLimit)
    let speedUncertainty = speedAccuracyMetersPerSecond ?? max(2, boundedSpeed * 0.2)
    let uncertainty =
      minimumUncertaintyRadiusMeters
      + speedUncertainty * elapsedSeconds
      + 0.05 * max(0, estimatedDistance - anchorRouteDistanceMeters)

    return TunnelPositionEstimate(
      routeDistanceMeters: estimatedDistance,
      uncertaintyRadiusMeters: uncertainty,
      elapsedSeconds: elapsedSeconds,
      isAtLimit:
        unconstrainedDistance >= safetyLimit
        || Double(elapsedMilliseconds) / 1_000 >= maximumHorizonSeconds
    )
  }
}
