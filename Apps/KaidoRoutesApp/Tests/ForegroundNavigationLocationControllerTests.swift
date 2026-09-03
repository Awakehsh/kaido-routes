import CoreLocation
import Foundation
import KaidoNavigation
import XCTest

@testable import KaidoRoutesApp

final class ForegroundNavigationLocationControllerTests: XCTestCase {
  @MainActor
  func testSyntheticAuthorityNeverAttachesOrRequestsALocationSource() throws {
    let identity = try SyntheticProductRuntimeFixture.bundled().release.runtimeIdentity
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
  func testReleasedAuthorityRequiresTheExactRuntimeIdentity() throws {
    let authority = try makeReleasedAuthority()
    let otherAuthority = try makeReleasedAuthority(
      productReleaseID: "test.product.release.other"
    )
    let consumer = RecordingLocationConsumer(
      identity: otherAuthority.runtimeIdentity
    )

    XCTAssertThrowsError(
      try ForegroundNavigationLocationController(
        authority: .releasedProduct(authority),
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

  func testSyntheticProductReleaseCannotMintForegroundAuthority() throws {
    let release = try SyntheticProductRuntimeFixture.bundled().release

    XCTAssertEqual(release.runtimeUse, .syntheticTestOnlyDisabled)
    XCTAssertNil(release.foregroundLiveInputAuthority)
  }

  @MainActor
  func testExplicitAuthorizationStartsAndSerializesCallbackBatches() async throws {
    let authority = try makeReleasedAuthority()
    let identity = authority.runtimeIdentity
    let consumer = RecordingLocationConsumer(identity: identity)
    let source = FakeForegroundNavigationLocationSource(
      authorizationStatus: .notDetermined
    )
    let controller = try ForegroundNavigationLocationController(
      authority: .releasedProduct(authority),
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
    XCTAssertEqual(source.backgroundNavigationEnabled, true)
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
    XCTAssertEqual(source.backgroundNavigationEnabled, false)
  }

  @MainActor
  func testActiveNavigationContinuesAcrossBackgroundAndForeground() async throws {
    let authority = try makeReleasedAuthority()
    let identity = authority.runtimeIdentity
    let consumer = RecordingLocationConsumer(identity: identity)
    let source = FakeForegroundNavigationLocationSource(
      authorizationStatus: .authorizedWhenInUse
    )
    let controller = try ForegroundNavigationLocationController(
      authority: .releasedProduct(authority),
      consumer: consumer,
      source: source
    )
    controller.start()
    XCTAssertEqual(controller.state, .running)
    XCTAssertEqual(source.startCount, 1)

    await controller.handleScenePhase(.background)

    XCTAssertEqual(controller.state, .running)
    XCTAssertEqual(source.stopCount, 0)
    XCTAssertFalse(controller.canStart)
    XCTAssertTrue(controller.maintainsActiveNavigationAcrossSceneChanges)

    let consumed = expectation(description: "background callback consumed")
    consumer.didConsume = { consumed.fulfill() }
    source.deliver(
      [makeLocation(longitude: 139.7600, timestamp: 101)],
      receivedAt: Date(timeIntervalSince1970: 102)
    )
    await fulfillment(of: [consumed], timeout: 2)

    await controller.handleScenePhase(.active)

    XCTAssertEqual(controller.state, .running)
    XCTAssertEqual(source.startCount, 1)
    XCTAssertEqual(source.stopCount, 0)

    await controller.stop()
    XCTAssertEqual(controller.state, .stopped)
  }

  @MainActor
  func testAuthorizationPromptRoundTripPreservesOneExplicitStart() async throws {
    let authority = try makeReleasedAuthority()
    let identity = authority.runtimeIdentity
    let consumer = RecordingLocationConsumer(identity: identity)
    let source = FakeForegroundNavigationLocationSource(
      authorizationStatus: .notDetermined
    )
    let controller = try ForegroundNavigationLocationController(
      authority: .releasedProduct(authority),
      consumer: consumer,
      source: source
    )

    controller.start()
    XCTAssertEqual(controller.state, .awaitingAuthorization)

    await controller.handleScenePhase(.inactive)
    XCTAssertEqual(controller.state, .sceneInactive)
    XCTAssertEqual(source.startCount, 0)

    source.deliverAuthorization(.authorizedWhenInUse)
    XCTAssertEqual(controller.state, .sceneInactive)
    XCTAssertEqual(source.startCount, 0)

    await controller.handleScenePhase(.active)
    XCTAssertEqual(controller.state, .running)
    XCTAssertEqual(source.startCount, 1)

    await controller.stop()
    XCTAssertEqual(controller.state, .stopped)
    XCTAssertEqual(source.stopCount, 2)
  }

  @MainActor
  func testExplicitStopWaitsForTheCurrentActorCallbackBeforeReturning()
    async throws
  {
    let authority = try makeReleasedAuthority()
    let identity = authority.runtimeIdentity
    let consumer = SuspendedLocationConsumer(identity: identity)
    let source = FakeForegroundNavigationLocationSource(
      authorizationStatus: .authorizedWhenInUse
    )
    let controller = try ForegroundNavigationLocationController(
      authority: .releasedProduct(authority),
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

    let stop = Task {
      await controller.stop()
    }
    await Task.yield()

    XCTAssertEqual(source.stopCount, 1)
    XCTAssertEqual(consumer.completedBatchCount, 0)

    consumer.resume()
    await stop.value

    XCTAssertEqual(consumer.completedBatchCount, 1)
    XCTAssertEqual(controller.state, .stopped)
  }

  @MainActor
  func testRepeatedSceneChangesDoNotRestartActiveNavigation() async throws {
    let authority = try makeReleasedAuthority()
    let identity = authority.runtimeIdentity
    let consumer = RecordingLocationConsumer(identity: identity)
    let source = FakeForegroundNavigationLocationSource(
      authorizationStatus: .authorizedWhenInUse
    )
    let controller = try ForegroundNavigationLocationController(
      authority: .releasedProduct(authority),
      consumer: consumer,
      source: source
    )
    controller.start()
    await controller.handleScenePhase(.inactive)
    await controller.handleScenePhase(.background)
    await controller.handleScenePhase(.active)

    XCTAssertEqual(controller.state, .running)
    XCTAssertFalse(controller.canStart)
    XCTAssertEqual(source.startCount, 1)
    XCTAssertEqual(source.stopCount, 0)
  }

  @MainActor
  func testPermissionDowngradeStopsAndRequiresAnotherExplicitStart() throws {
    let authority = try makeReleasedAuthority()
    let identity = authority.runtimeIdentity
    let consumer = RecordingLocationConsumer(identity: identity)
    let source = FakeForegroundNavigationLocationSource(
      authorizationStatus: .authorizedWhenInUse
    )
    let controller = try ForegroundNavigationLocationController(
      authority: .releasedProduct(authority),
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
  func testCallbackBacklogDropsOldestPendingBatchWithoutStoppingLocation()
    async throws
  {
    let authority = try makeReleasedAuthority()
    let identity = authority.runtimeIdentity
    let consumer = SuspendedLocationConsumer(identity: identity)
    let source = FakeForegroundNavigationLocationSource(
      authorizationStatus: .authorizedWhenInUse
    )
    let controller = try ForegroundNavigationLocationController(
      authority: .releasedProduct(authority),
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

    XCTAssertEqual(controller.state, .running)
    XCTAssertEqual(
      controller.lastTransientFailureCode,
      "LOCATION_CALLBACK_BACKLOG_EXCEEDED"
    )
    XCTAssertEqual(source.stopCount, 0)

    consumer.resume()
    for _ in 0..<100 where consumer.completedBatchCount < 9 {
      await Task.yield()
    }
    XCTAssertEqual(consumer.completedBatchCount, 9)
  }

  @MainActor
  func testRuntimeMustBeReadyBeforeTheControllerCanStart() throws {
    let authority = try makeReleasedAuthority()
    let identity = authority.runtimeIdentity
    let consumer = RecordingLocationConsumer(
      identity: identity,
      acceptsLocations: false
    )
    let source = FakeForegroundNavigationLocationSource(
      authorizationStatus: .authorizedWhenInUse
    )
    let controller = try ForegroundNavigationLocationController(
      authority: .releasedProduct(authority),
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
    let authority = try makeReleasedAuthority()
    let identity = authority.runtimeIdentity
    let consumer = RecordingLocationConsumer(identity: identity)
    let source = FakeForegroundNavigationLocationSource(
      authorizationStatus: .authorizedWhenInUse
    )
    let controller = try ForegroundNavigationLocationController(
      authority: .releasedProduct(authority),
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
  func testProductionSourceIsConfiguredForBackgroundAutomotiveNavigation() {
    let manager = CLLocationManager()
    let source = CoreLocationForegroundNavigationSource(
      locationManager: manager,
      backgroundModes: ["audio", "location"]
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

    source.setBackgroundNavigationEnabled(true)
    XCTAssertTrue(manager.allowsBackgroundLocationUpdates)
    XCTAssertTrue(manager.showsBackgroundLocationIndicator)

    source.setBackgroundNavigationEnabled(false)
    XCTAssertFalse(manager.allowsBackgroundLocationUpdates)
    XCTAssertFalse(manager.showsBackgroundLocationIndicator)
  }

  @MainActor
  func testMissingBackgroundLocationModeFailsClosedBeforeStarting() throws {
    let authority = try makeReleasedAuthority()
    let consumer = RecordingLocationConsumer(identity: authority.runtimeIdentity)
    let source = FakeForegroundNavigationLocationSource(
      authorizationStatus: .authorizedWhenInUse,
      supportsBackgroundNavigation: false
    )
    let controller = try ForegroundNavigationLocationController(
      authority: .releasedProduct(authority),
      consumer: consumer,
      source: source
    )

    XCTAssertEqual(controller.state, .failed("BACKGROUND_LOCATION_MODE_MISSING"))
    XCTAssertFalse(controller.canStart)
    controller.start()
    XCTAssertEqual(source.startCount, 0)
  }

  private func makeReleasedAuthority(
    productReleaseID: String = "test.product.release"
  ) throws -> KaidoForegroundLiveInputAuthority {
    let url = try XCTUnwrap(
      Bundle.main.url(
        forResource: SyntheticProductRuntimeFixture.resourceName,
        withExtension: "json"
      )
    )
    var root = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: url))
        as? [String: Any]
    )
    root["release_id"] = productReleaseID
    root["runtime_use"] = [
      "evidence_scope": "RELEASED_ROAD",
      "live_input_policy": "FOREGROUND_WHEN_IN_USE",
    ]
    for releaseKey in ["navigation_release", "route_atlas_release"] {
      var nestedRelease = try XCTUnwrap(root[releaseKey] as? [String: Any])
      var registry = try XCTUnwrap(
        nestedRelease["source_registry"] as? [String: Any]
      )
      var references = try XCTUnwrap(
        registry["references"] as? [[String: Any]]
      )
      for index in references.indices {
        references[index]["licence_identifier"] = "TEST_REVIEWED_ROAD_ONLY"
      }
      registry["references"] = references
      nestedRelease["source_registry"] = registry
      root[releaseKey] = nestedRelease
    }
    let data = try JSONSerialization.data(withJSONObject: root)
    let release = try KaidoProductReleaseArtifactCodec.decode(data)
    return try XCTUnwrap(release.foregroundLiveInputAuthority)
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
  let foregroundNavigationRuntimeIdentity: KaidoProductRuntimeIdentity
  let canConsumeForegroundNavigationLocations = true
  var didStart: (() -> Void)?
  private(set) var completedBatchCount = 0

  private var continuation: CheckedContinuation<Void, Never>?

  init(identity: KaidoProductRuntimeIdentity) {
    foregroundNavigationRuntimeIdentity = identity
  }

  func consumeForegroundNavigationLocations(
    _: [CLLocation],
    receivedAt _: Date
  ) async {
    if completedBatchCount == 0 {
      didStart?()
      await withCheckedContinuation { continuation in
        self.continuation = continuation
      }
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

  let foregroundNavigationRuntimeIdentity: KaidoProductRuntimeIdentity
  var canConsumeForegroundNavigationLocations: Bool {
    acceptsLocations
  }
  var acceptsLocations: Bool
  var batches: [Batch] = []
  var didConsume: (() -> Void)?

  init(
    identity: KaidoProductRuntimeIdentity,
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
  let supportsBackgroundNavigation: Bool
  private(set) var authorizationRequestCount = 0
  private(set) var startCount = 0
  private(set) var stopCount = 0
  private(set) var backgroundNavigationEnabled = false

  init(
    authorizationStatus: CLAuthorizationStatus = .notDetermined,
    accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy,
    supportsBackgroundNavigation: Bool = true
  ) {
    self.authorizationStatus = authorizationStatus
    self.accuracyAuthorization = accuracyAuthorization
    self.supportsBackgroundNavigation = supportsBackgroundNavigation
  }

  func requestWhenInUseAuthorization() {
    authorizationRequestCount += 1
  }

  func setBackgroundNavigationEnabled(_ enabled: Bool) {
    backgroundNavigationEnabled = enabled && supportsBackgroundNavigation
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
