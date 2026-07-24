import CoreLocation
import XCTest

@testable import KaidoRoutesApp

final class ForegroundNavigationLocationControllerTests: XCTestCase {
  @MainActor
  func testSyntheticAuthorityNeverAttachesOrRequestsALocationSource() throws {
    let identity = makeIdentity()
    let consumer = RecordingLocationConsumer(identity: identity)
    let source = FakeForegroundNavigationLocationSource()
    let controller = try ForegroundNavigationLocationController(
      authority: .blocked(
        identity: identity,
        reason: .syntheticTestOnly
      ),
      consumer: consumer,
      source: source
    )

    XCTAssertEqual(
      controller.state,
      .releaseBlocked(.syntheticTestOnly)
    )
    XCTAssertFalse(controller.canStart)
    XCTAssertEqual(controller.authorizationLabel, "NOT REQUESTED")
    XCTAssertNil(source.delegate)

    controller.start()

    XCTAssertEqual(source.authorizationRequestCount, 0)
    XCTAssertEqual(source.startCount, 0)
    XCTAssertEqual(source.stopCount, 0)
  }

  @MainActor
  func testReleasedAuthorityRequiresTheExactRuntimeIdentity() {
    let identity = makeIdentity()
    let consumer = RecordingLocationConsumer(
      identity: ForegroundNavigationRuntimeIdentity(
        productReleaseID: identity.productReleaseID,
        navigationReleaseID: identity.navigationReleaseID,
        runtimePolicyID: identity.runtimePolicyID,
        networkSnapshotID: identity.networkSnapshotID,
        routePlanID: "test.plan.other",
        matcherCorridorID: identity.matcherCorridorID
      )
    )

    XCTAssertThrowsError(
      try ForegroundNavigationLocationController(
        authority: .releasedProduct(identity: identity),
        consumer: consumer,
        source: FakeForegroundNavigationLocationSource()
      )
    ) {
      XCTAssertEqual(
        $0 as? ForegroundNavigationLocationControllerError,
        .runtimeIdentityMismatch
      )
    }
  }

  @MainActor
  func testReleasedAuthorityRejectsAnIncompleteRuntimeIdentity() {
    let identity = ForegroundNavigationRuntimeIdentity(
      productReleaseID: "test.product.release",
      navigationReleaseID: "test.navigation.release",
      runtimePolicyID: "",
      networkSnapshotID: "test.snapshot",
      routePlanID: "test.plan",
      matcherCorridorID: "test.matcher-corridor"
    )
    let consumer = RecordingLocationConsumer(identity: identity)

    XCTAssertThrowsError(
      try ForegroundNavigationLocationController(
        authority: .releasedProduct(identity: identity),
        consumer: consumer,
        source: FakeForegroundNavigationLocationSource()
      )
    ) {
      XCTAssertEqual(
        $0 as? ForegroundNavigationLocationControllerError,
        .invalidRuntimeIdentity
      )
    }
  }

  @MainActor
  func testExplicitAuthorizationStartsAndSerializesCallbackBatches() async throws {
    let identity = makeIdentity()
    let consumer = RecordingLocationConsumer(identity: identity)
    let source = FakeForegroundNavigationLocationSource(
      authorizationStatus: .notDetermined
    )
    let controller = try ForegroundNavigationLocationController(
      authority: .releasedProduct(identity: identity),
      consumer: consumer,
      source: source
    )
    let consumed = expectation(description: "two callback batches consumed")
    consumed.expectedFulfillmentCount = 2
    consumer.didConsume = {
      consumed.fulfill()
    }

    XCTAssertEqual(controller.state, .idle)
    XCTAssertTrue(controller.canStart)
    controller.start()

    XCTAssertEqual(controller.state, .awaitingAuthorization)
    XCTAssertEqual(source.authorizationRequestCount, 1)
    XCTAssertEqual(source.startCount, 0)

    source.deliverAuthorization(.authorizedWhenInUse)

    XCTAssertEqual(controller.state, .running)
    XCTAssertEqual(source.startCount, 1)
    XCTAssertFalse(controller.canStart)
    XCTAssertTrue(controller.canStop)

    let firstReceivedAt = Date(timeIntervalSince1970: 100)
    let secondReceivedAt = Date(timeIntervalSince1970: 101)
    source.deliver(
      [makeLocation(longitude: 139.7590, timestamp: 90)],
      receivedAt: firstReceivedAt
    )
    source.deliver(
      [makeLocation(longitude: 139.7600, timestamp: 91)],
      receivedAt: secondReceivedAt
    )
    await fulfillment(of: [consumed], timeout: 2)

    XCTAssertEqual(
      consumer.batches.map(\.receivedAt),
      [firstReceivedAt, secondReceivedAt]
    )
    XCTAssertEqual(
      consumer.batches.compactMap { $0.locations.first?.coordinate.longitude },
      [139.7590, 139.7600]
    )

    await controller.stop()

    XCTAssertEqual(controller.state, .stopped)
    XCTAssertEqual(source.stopCount, 1)
  }

  @MainActor
  func testSceneDepartureStopsWithoutAutomaticResume() async throws {
    let identity = makeIdentity()
    let consumer = RecordingLocationConsumer(identity: identity)
    let source = FakeForegroundNavigationLocationSource(
      authorizationStatus: .authorizedWhenInUse
    )
    let controller = try ForegroundNavigationLocationController(
      authority: .releasedProduct(identity: identity),
      consumer: consumer,
      source: source
    )
    controller.start()
    XCTAssertEqual(controller.state, .running)
    XCTAssertEqual(source.startCount, 1)

    await controller.handleScenePhase(.background)

    XCTAssertEqual(controller.state, .sceneInactive)
    XCTAssertEqual(source.stopCount, 1)
    XCTAssertFalse(controller.canStart)

    await controller.handleScenePhase(.active)

    XCTAssertEqual(controller.state, .idle)
    XCTAssertEqual(source.startCount, 1)
    XCTAssertTrue(controller.canStart)

    controller.start()

    XCTAssertEqual(controller.state, .running)
    XCTAssertEqual(source.startCount, 2)
  }

  @MainActor
  func testSceneDepartureWaitsForTheCurrentActorCallbackBeforeCheckpointing()
    async throws
  {
    let identity = makeIdentity()
    let consumer = SuspendedLocationConsumer(identity: identity)
    let source = FakeForegroundNavigationLocationSource(
      authorizationStatus: .authorizedWhenInUse
    )
    let controller = try ForegroundNavigationLocationController(
      authority: .releasedProduct(identity: identity),
      consumer: consumer,
      source: source
    )
    let started = expectation(description: "actor callback started")
    consumer.didStart = {
      started.fulfill()
    }
    controller.start()
    source.deliver(
      [makeLocation(longitude: 139.7590, timestamp: 90)],
      receivedAt: Date(timeIntervalSince1970: 100)
    )
    await fulfillment(of: [started], timeout: 2)

    let transition = Task {
      await controller.handleScenePhase(.background)
    }
    await Task.yield()

    XCTAssertEqual(source.stopCount, 1)
    XCTAssertEqual(consumer.completedBatchCount, 0)

    consumer.resume()
    await transition.value

    XCTAssertEqual(consumer.completedBatchCount, 1)
    XCTAssertEqual(controller.state, .sceneInactive)
  }

  @MainActor
  func testNewerActiveSceneWinsWhileInactiveWaitsForActorDrain() async throws {
    let identity = makeIdentity()
    let consumer = SuspendedLocationConsumer(identity: identity)
    let source = FakeForegroundNavigationLocationSource(
      authorizationStatus: .authorizedWhenInUse
    )
    let controller = try ForegroundNavigationLocationController(
      authority: .releasedProduct(identity: identity),
      consumer: consumer,
      source: source
    )
    let started = expectation(description: "actor callback started")
    consumer.didStart = {
      started.fulfill()
    }
    controller.start()
    source.deliver(
      [makeLocation(longitude: 139.7590, timestamp: 90)],
      receivedAt: Date(timeIntervalSince1970: 100)
    )
    await fulfillment(of: [started], timeout: 2)

    let inactiveTransition = Task {
      await controller.handleScenePhase(.inactive)
    }
    await Task.yield()
    let activeTransition = Task {
      await controller.handleScenePhase(.active)
    }
    await Task.yield()

    consumer.resume()
    await inactiveTransition.value
    await activeTransition.value

    XCTAssertEqual(controller.state, .idle)
    XCTAssertTrue(controller.canStart)
    XCTAssertEqual(source.startCount, 1)
    XCTAssertGreaterThanOrEqual(source.stopCount, 2)
  }

  @MainActor
  func testPermissionDowngradeStopsAndRequiresAnotherExplicitStart() throws {
    let identity = makeIdentity()
    let consumer = RecordingLocationConsumer(identity: identity)
    let source = FakeForegroundNavigationLocationSource(
      authorizationStatus: .authorizedWhenInUse
    )
    let controller = try ForegroundNavigationLocationController(
      authority: .releasedProduct(identity: identity),
      consumer: consumer,
      source: source
    )
    controller.start()

    source.deliverAuthorization(.denied)

    XCTAssertEqual(controller.state, .permissionDenied)
    XCTAssertEqual(source.stopCount, 1)
    XCTAssertFalse(controller.canStart)

    source.deliverAuthorization(.authorizedWhenInUse)

    XCTAssertEqual(controller.state, .stopped)
    XCTAssertTrue(controller.canStart)
    XCTAssertEqual(source.startCount, 1)

    controller.start()

    XCTAssertEqual(source.startCount, 2)
    XCTAssertEqual(controller.state, .running)
  }

  @MainActor
  func testCallbackBacklogFailsClosedInsteadOfDroppingOrReorderingInput()
    async throws
  {
    let identity = makeIdentity()
    let consumer = SuspendedLocationConsumer(identity: identity)
    let source = FakeForegroundNavigationLocationSource(
      authorizationStatus: .authorizedWhenInUse
    )
    let controller = try ForegroundNavigationLocationController(
      authority: .releasedProduct(identity: identity),
      consumer: consumer,
      source: source
    )
    let started = expectation(description: "first callback started")
    consumer.didStart = {
      started.fulfill()
    }
    controller.start()
    source.deliver(
      [makeLocation(longitude: 139.7590, timestamp: 90)],
      receivedAt: Date(timeIntervalSince1970: 100)
    )
    await fulfillment(of: [started], timeout: 2)

    for offset in 1...9 {
      source.deliver(
        [
          makeLocation(
            longitude: 139.7590 + (Double(offset) * 0.0001),
            timestamp: 90 + Double(offset)
          )
        ],
        receivedAt: Date(timeIntervalSince1970: 100 + Double(offset))
      )
    }

    XCTAssertEqual(
      controller.state,
      .failed("LOCATION_CALLBACK_BACKLOG_EXCEEDED")
    )
    XCTAssertEqual(source.stopCount, 1)

    consumer.resume()
    await Task.yield()
  }

  @MainActor
  func testRuntimeMustBeReadyBeforeTheControllerCanStart() throws {
    let identity = makeIdentity()
    let consumer = RecordingLocationConsumer(
      identity: identity,
      acceptsLocations: false
    )
    let source = FakeForegroundNavigationLocationSource(
      authorizationStatus: .authorizedWhenInUse
    )
    let controller = try ForegroundNavigationLocationController(
      authority: .releasedProduct(identity: identity),
      consumer: consumer,
      source: source
    )

    XCTAssertEqual(controller.state, .runtimeUnavailable)
    XCTAssertFalse(controller.canStart)
    controller.start()
    XCTAssertEqual(source.startCount, 0)

    consumer.acceptsLocations = true
    controller.refreshRuntimeAvailability()

    XCTAssertEqual(controller.state, .idle)
    XCTAssertTrue(controller.canStart)
  }

  @MainActor
  func testTransientAndTerminalSourceFailuresRemainDistinct() throws {
    let identity = makeIdentity()
    let consumer = RecordingLocationConsumer(identity: identity)
    let source = FakeForegroundNavigationLocationSource(
      authorizationStatus: .authorizedWhenInUse
    )
    let controller = try ForegroundNavigationLocationController(
      authority: .releasedProduct(identity: identity),
      consumer: consumer,
      source: source
    )
    controller.start()

    source.fail(code: "CORE_LOCATION_LOCATION_UNKNOWN", isTransient: true)

    XCTAssertEqual(controller.state, .running)
    XCTAssertEqual(
      controller.lastTransientFailureCode,
      "CORE_LOCATION_LOCATION_UNKNOWN"
    )
    XCTAssertEqual(source.stopCount, 0)

    source.fail(code: "CORE_LOCATION_1", isTransient: false)

    XCTAssertEqual(controller.state, .failed("CORE_LOCATION_1"))
    XCTAssertEqual(source.stopCount, 1)
  }

  @MainActor
  func testProductionSourceIsConfiguredForForegroundAutomotiveUpdates() {
    let manager = CLLocationManager()
    let source = CoreLocationForegroundNavigationSource(
      locationManager: manager
    )

    XCTAssertTrue(manager.delegate === source)
    XCTAssertEqual(manager.activityType, .automotiveNavigation)
    XCTAssertEqual(
      manager.desiredAccuracy,
      kCLLocationAccuracyBestForNavigation
    )
    XCTAssertEqual(manager.distanceFilter, kCLDistanceFilterNone)
    XCTAssertFalse(manager.pausesLocationUpdatesAutomatically)
    XCTAssertFalse(manager.allowsBackgroundLocationUpdates)
    XCTAssertFalse(manager.showsBackgroundLocationIndicator)
  }

  @MainActor
  private func makeIdentity() -> ForegroundNavigationRuntimeIdentity {
    ForegroundNavigationRuntimeIdentity(
      productReleaseID: "test.product.release",
      navigationReleaseID: "test.navigation.release",
      runtimePolicyID: "test.runtime-policy",
      networkSnapshotID: "test.snapshot",
      routePlanID: "test.plan",
      matcherCorridorID: "test.matcher-corridor"
    )
  }

  @MainActor
  private func makeLocation(
    longitude: Double,
    timestamp: TimeInterval
  ) -> CLLocation {
    CLLocation(
      coordinate: CLLocationCoordinate2D(
        latitude: 35.68,
        longitude: longitude
      ),
      altitude: 0,
      horizontalAccuracy: 5,
      verticalAccuracy: 5,
      course: 90,
      courseAccuracy: 2,
      speed: 10,
      speedAccuracy: 1,
      timestamp: Date(timeIntervalSince1970: timestamp)
    )
  }
}

@MainActor
private final class SuspendedLocationConsumer:
  ForegroundNavigationLocationConsuming
{
  let foregroundNavigationRuntimeIdentity: ForegroundNavigationRuntimeIdentity
  let canConsumeForegroundNavigationLocations = true
  var didStart: (() -> Void)?
  private(set) var completedBatchCount = 0

  private var continuation: CheckedContinuation<Void, Never>?

  init(identity: ForegroundNavigationRuntimeIdentity) {
    foregroundNavigationRuntimeIdentity = identity
  }

  func consumeForegroundNavigationLocations(
    _: [CLLocation],
    receivedAt _: Date
  ) async {
    didStart?()
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
    completedBatchCount += 1
  }

  func resume() {
    continuation?.resume()
    continuation = nil
  }
}

@MainActor
private final class RecordingLocationConsumer:
  ForegroundNavigationLocationConsuming
{
  struct Batch {
    let locations: [CLLocation]
    let receivedAt: Date
  }

  let foregroundNavigationRuntimeIdentity: ForegroundNavigationRuntimeIdentity
  var canConsumeForegroundNavigationLocations: Bool {
    acceptsLocations
  }
  var acceptsLocations: Bool
  var batches: [Batch] = []
  var didConsume: (() -> Void)?

  init(
    identity: ForegroundNavigationRuntimeIdentity,
    acceptsLocations: Bool = true
  ) {
    foregroundNavigationRuntimeIdentity = identity
    self.acceptsLocations = acceptsLocations
  }

  func consumeForegroundNavigationLocations(
    _ locations: [CLLocation],
    receivedAt: Date
  ) async {
    batches.append(Batch(locations: locations, receivedAt: receivedAt))
    didConsume?()
  }
}

@MainActor
private final class FakeForegroundNavigationLocationSource:
  ForegroundNavigationLocationSource
{
  weak var delegate: (any ForegroundNavigationLocationSourceDelegate)?
  var authorizationStatus: CLAuthorizationStatus
  var accuracyAuthorization: CLAccuracyAuthorization
  private(set) var authorizationRequestCount = 0
  private(set) var startCount = 0
  private(set) var stopCount = 0

  init(
    authorizationStatus: CLAuthorizationStatus = .notDetermined,
    accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
  ) {
    self.authorizationStatus = authorizationStatus
    self.accuracyAuthorization = accuracyAuthorization
  }

  func requestWhenInUseAuthorization() {
    authorizationRequestCount += 1
  }

  func startUpdatingLocation() {
    startCount += 1
  }

  func stopUpdatingLocation() {
    stopCount += 1
  }

  func deliverAuthorization(_ status: CLAuthorizationStatus) {
    authorizationStatus = status
    delegate?.foregroundNavigationLocationSourceDidChangeAuthorization(self)
  }

  func deliver(
    _ locations: [CLLocation],
    receivedAt: Date
  ) {
    delegate?.foregroundNavigationLocationSource(
      self,
      didDeliver: locations,
      receivedAt: receivedAt
    )
  }

  func fail(code: String, isTransient: Bool) {
    delegate?.foregroundNavigationLocationSource(
      self,
      didFailWithCode: code,
      isTransient: isTransient
    )
  }
}
