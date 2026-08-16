import KaidoNavigation
import Testing

@Test("Tunnel estimate advances only to the supplied decision safety limit")
func tunnelEstimateStopsAtDecisionSafetyLimit() throws {
  let estimate = try #require(
    TunnelPositionEstimator.estimate(
      anchorRouteDistanceMeters: 1_000,
      routeDistanceMeters: 8_000,
      safetyLimitRouteDistanceMeters: 1_350,
      speedMetersPerSecond: 20,
      speedAccuracyMetersPerSecond: 1,
      elapsedMilliseconds: 30_000
    )
  )

  #expect(estimate.routeDistanceMeters == 1_350)
  #expect(estimate.isAtLimit)
  #expect(estimate.uncertaintyRadiusMeters > 25)
}

@Test("Tunnel estimate bounds speed and elapsed-time drift")
func tunnelEstimateBoundsSpeedAndHorizon() throws {
  let estimate = try #require(
    TunnelPositionEstimator.estimate(
      anchorRouteDistanceMeters: 500,
      routeDistanceMeters: 10_000,
      safetyLimitRouteDistanceMeters: 10_000,
      speedMetersPerSecond: 80,
      speedAccuracyMetersPerSecond: 2,
      elapsedMilliseconds: 120_000
    )
  )

  #expect(estimate.elapsedSeconds == 45)
  #expect(estimate.routeDistanceMeters == 2_750)
  #expect(estimate.isAtLimit)
}

@Test("Tunnel estimate rejects inputs that cannot support weak propagation")
func tunnelEstimateRejectsInvalidInputs() {
  #expect(
    TunnelPositionEstimator.estimate(
      anchorRouteDistanceMeters: 1_000,
      routeDistanceMeters: 8_000,
      safetyLimitRouteDistanceMeters: 900,
      speedMetersPerSecond: 20,
      speedAccuracyMetersPerSecond: 1,
      elapsedMilliseconds: 10_000
    ) == nil
  )
  #expect(
    TunnelPositionEstimator.estimate(
      anchorRouteDistanceMeters: 1_000,
      routeDistanceMeters: 8_000,
      safetyLimitRouteDistanceMeters: 2_000,
      speedMetersPerSecond: 0,
      speedAccuracyMetersPerSecond: 1,
      elapsedMilliseconds: 10_000
    ) == nil
  )
  #expect(
    TunnelPositionEstimator.estimate(
      anchorRouteDistanceMeters: 1_000,
      routeDistanceMeters: 8_000,
      safetyLimitRouteDistanceMeters: 2_000,
      speedMetersPerSecond: 20,
      speedAccuracyMetersPerSecond: -1,
      elapsedMilliseconds: 10_000
    ) == nil
  )
}
