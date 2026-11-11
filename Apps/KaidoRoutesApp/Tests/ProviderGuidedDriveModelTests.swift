import CoreLocation
import KaidoAppleAdapters
import KaidoDomain
import KaidoPresentation
import KaidoRouting
import XCTest

@testable import KaidoRoutesApp

@MainActor
final class ProviderGuidedDriveModelTests: XCTestCase {
  // About 1.1 km due north along one meridian.
  private let start = ShutoCoordinate(latitude: 35.600, longitude: 139.700)
  private let end = ShutoCoordinate(latitude: 35.610, longitude: 139.700)
  private let destination = WholeShutoPlace(
    title: "Destination", coordinate: ShutoCoordinate(latitude: 35.610, longitude: 139.700))
  private var now = Date(timeIntervalSince1970: 1_000)

  private func route(hasHighways: Bool = false, firstStep: String = "Head north") -> WholeShutoSurfaceRoute {
    WholeShutoSurfaceRoute(
      coordinates: [start, end],
      distanceMeters: 1_110,
      expectedTravelTimeSeconds: 180,
      instructions: [firstStep, "Turn right onto Main Street"],
      steps: [
        .init(instruction: firstStep, distanceMeters: 600),
        .init(instruction: "Turn right onto Main Street", distanceMeters: 510),
      ],
      guidanceLanguageCode: "en-US",
      hasHighways: hasHighways)
  }

  private func makeDrive(
    resolver: ProviderRouteStub = ProviderRouteStub(routes: []),
    source: FakeLocationSource = FakeLocationSource(),
    output: RecordingSpeechOutput? = RecordingSpeechOutput()
  ) -> ProviderGuidedDriveModel {
    ProviderGuidedDriveModel(
      route: route(), destination: destination, resolver: resolver, source: source,
      speechOutput: output, speechMode: .full, voiceLocale: { .english },
      now: { [unowned self] in self.now })
  }

  private func north(_ fraction: Double, eastMeters: Double = 0) -> ShutoCoordinate {
    ShutoCoordinate(
      latitude: start.latitude + (end.latitude - start.latitude) * fraction,
      longitude: start.longitude + eastMeters / (111_320 * cos(35.6 * .pi / 180)))
  }

  func testStartTracksInTheBackgroundAndSpeaksTheFirstStep() {
    let source = FakeLocationSource()
    let output = RecordingSpeechOutput()
    let drive = makeDrive(source: source, output: output)

    drive.start()

    XCTAssertTrue(source.isUpdating)
    XCTAssertTrue(source.backgroundEnabled)
    XCTAssertEqual(output.spokenTexts, ["Head north"])
    drive.end()
    XCTAssertFalse(source.isUpdating)
    XCTAssertFalse(source.backgroundEnabled)
  }

  func testProgressFollowsTheRouteAndArrivesAtItsEnd() {
    let source = FakeLocationSource()
    let output = RecordingSpeechOutput()
    let drive = makeDrive(source: source, output: output)
    drive.start()

    drive.observe(north(0.7), horizontalAccuracyMeters: 10, at: now)
    XCTAssertEqual(drive.progressFraction, 0.7, accuracy: 0.01)
    XCTAssertEqual(drive.stepProgress?.index, 1)
    XCTAssertEqual(drive.phase, .driving)

    drive.observe(end, horizontalAccuracyMeters: 10, at: now)
    XCTAssertEqual(drive.phase, .arrived)
    XCTAssertFalse(source.isUpdating)
    XCTAssertTrue(output.spokenTexts.contains(WholeShutoJourneyNotice.nearDestination.text(locale: .english)))
  }

  func testStoppingBesideThePlaceOffTheLineArrivesInsteadOfRerouting() {
    let resolver = ProviderRouteStub(routes: [route()])
    let drive = makeDrive(resolver: resolver)
    drive.start()
    drive.observe(north(0.9), horizontalAccuracyMeters: 10, at: now)

    let beside = ShutoCoordinate(latitude: end.latitude - 0.0002, longitude: end.longitude + 0.0004)
    drive.observe(beside, horizontalAccuracyMeters: 10, at: now)
    drive.observe(beside, horizontalAccuracyMeters: 10, at: now)

    XCTAssertEqual(drive.phase, .arrived)
    XCTAssertEqual(resolver.requestCount, 0)
  }

  func testACoarseFixFarFromThePlaceDoesNotArrive() {
    let source = FakeLocationSource()
    let drive = makeDrive(source: source)
    drive.start()

    drive.observe(north(0.1), horizontalAccuracyMeters: 1_000, at: now)

    XCTAssertEqual(drive.phase, .driving)
    XCTAssertTrue(source.isUpdating)
  }

  func testAFixAlreadyStaleWhenDeliveredMovesNothing() {
    let source = FakeLocationSource()
    let drive = makeDrive(source: source)
    drive.start()
    func deliver(_ coordinate: ShutoCoordinate, age: TimeInterval) {
      let fix = CLLocation(
        coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
        altitude: 0, horizontalAccuracy: 10, verticalAccuracy: -1,
        timestamp: now.addingTimeInterval(-age))
      drive.foregroundNavigationLocationSource(source, didDeliver: [fix], receivedAt: now)
    }

    deliver(end, age: 15)
    XCTAssertEqual(drive.phase, .driving)
    XCTAssertEqual(drive.progressFraction, 0)

    deliver(north(0.5), age: 1)
    XCTAssertEqual(drive.progressFraction, 0.5, accuracy: 0.01)
  }

  func testCoarseAccuracyWidensTheCorridorInsteadOfLeavingTheRoute() {
    let resolver = ProviderRouteStub(routes: [route()])
    let drive = makeDrive(resolver: resolver)
    drive.start()

    for _ in 0..<3 {
      drive.observe(north(0.3, eastMeters: 80), horizontalAccuracyMeters: 40, at: now)
    }

    XCTAssertFalse(drive.isOffRoute)
    XCTAssertEqual(resolver.requestCount, 0)
  }

  func testOneSidewaysFixChangesNothingAndTwoReroute() async throws {
    let detour = WholeShutoSurfaceRoute(
      coordinates: [north(0.3, eastMeters: 200), end], distanceMeters: 800,
      expectedTravelTimeSeconds: 120, instructions: ["Turn left"],
      steps: [.init(instruction: "Turn left", distanceMeters: 800)], guidanceLanguageCode: "en-US",
      hasHighways: false)
    let resolver = ProviderRouteStub(routes: [detour])
    let drive = makeDrive(resolver: resolver)
    drive.start()
    drive.observe(north(0.3), horizontalAccuracyMeters: 10, at: now)

    drive.observe(north(0.3, eastMeters: 200), horizontalAccuracyMeters: 10, at: now)
    XCTAssertFalse(drive.isOffRoute)
    XCTAssertEqual(resolver.requestCount, 0)

    drive.observe(north(0.3, eastMeters: 200), horizontalAccuracyMeters: 10, at: now)
    XCTAssertTrue(drive.isOffRoute)
    try await waitUntil { drive.route == detour }
    XCTAssertEqual(resolver.requestCount, 1)
    XCTAssertEqual(drive.progressFraction, 0)
    XCTAssertFalse(drive.isOffRoute)
  }

  func testRerouteWaitsOutItsCooldown() async throws {
    let resolver = ProviderRouteStub(routes: [])
    let drive = makeDrive(resolver: resolver)
    drive.start()
    let away = north(0.3, eastMeters: 300)
    drive.observe(away, horizontalAccuracyMeters: 10, at: now)
    drive.observe(away, horizontalAccuracyMeters: 10, at: now)
    try await waitUntil { !drive.isRerouting }

    drive.observe(away, horizontalAccuracyMeters: 10, at: now.addingTimeInterval(10))
    try await waitUntil { !drive.isRerouting }
    XCTAssertEqual(resolver.requestCount, 1)

    drive.observe(away, horizontalAccuracyMeters: 10, at: now.addingTimeInterval(16))
    try await waitUntil { resolver.requestCount == 2 }
  }

  func testRerouteKeepsTheRoadKindTheDriverChose() async throws {
    let highway = route(hasHighways: true, firstStep: "Take the ramp")
    let local = route(hasHighways: false, firstStep: "Continue on local roads")
    let drive = makeDrive(resolver: ProviderRouteStub(routes: [highway, local]))
    drive.start()
    let away = north(0.3, eastMeters: 300)
    drive.observe(away, horizontalAccuracyMeters: 10, at: now)
    drive.observe(away, horizontalAccuracyMeters: 10, at: now)

    try await waitUntil { drive.route == local }
  }

  func testAStaleFixSpeaksOnceAMinuteAndACoarseOneNever() {
    let output = RecordingSpeechOutput()
    let drive = makeDrive(output: output)
    drive.start()
    let notice = WholeShutoJourneyNotice.positionLost.text(locale: .english)

    drive.observe(north(0.1), horizontalAccuracyMeters: 65, at: now)
    now = now.addingTimeInterval(9)
    drive.evaluateFixFreshness()
    XCTAssertFalse(output.spokenTexts.contains(notice))
    XCTAssertFalse(drive.isPositionStale)

    now = now.addingTimeInterval(2)
    drive.evaluateFixFreshness()
    XCTAssertTrue(drive.isPositionStale)
    now = now.addingTimeInterval(30)
    drive.evaluateFixFreshness()
    XCTAssertEqual(output.spokenTexts.filter { $0 == notice }.count, 1)

    now = now.addingTimeInterval(31)
    drive.evaluateFixFreshness()
    XCTAssertEqual(output.spokenTexts.filter { $0 == notice }.count, 2)

    drive.observe(north(0.2), horizontalAccuracyMeters: 10, at: now)
    XCTAssertFalse(drive.isPositionStale)
  }

  private func waitUntil(
    _ condition: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line
  ) async throws {
    for _ in 0..<200 where !condition() {
      try await Task.sleep(for: .milliseconds(5))
    }
    XCTAssertTrue(condition(), file: file, line: line)
  }
}

@MainActor
final class DestinationRouteChoiceTests: XCTestCase {
  func testIdenticalProviderPathIsListedOnceAsKaidoWithTheProviderTime() throws {
    let planner = try ShutoRoutePlanner(database: WholeShutoNetworkCatalog.bundled())
    let origin = ShutoCoordinate(latitude: 35.6812, longitude: 139.7671)
    let destination = WholeShutoPlace(
      title: "Yokohama", coordinate: ShutoCoordinate(latitude: 35.4437, longitude: 139.6380))
    let recommendations = Array(try planner.recommend(from: origin, to: destination.coordinate).prefix(2))
    XCTAssertEqual(recommendations.count, 2)
    var legs: [String: WholeShutoRouteChoiceSurfaceRoutes] = [:]
    for recommendation in recommendations.prefix(1) {
      let route = recommendation.route
      legs[route.routePlan.id] = WholeShutoRouteChoiceSurfaceRoutes(
        access: leg([origin, route.coordinates[0]], seconds: 300),
        egress: leg([route.coordinates[route.coordinates.count - 1], destination.coordinate], seconds: 300))
    }
    let timedKaido = recommendations[0]
    let timedLegs = try XCTUnwrap(legs[timedKaido.route.routePlan.id])
    let fullPath = timedLegs.access.coordinates + timedKaido.route.coordinates + timedLegs.egress.coordinates
    let fullDistance = timedLegs.access.distanceMeters + timedKaido.route.distanceMeters
      + timedLegs.egress.distanceMeters
    let sameAsKaido = WholeShutoSurfaceRoute(
      coordinates: fullPath, distanceMeters: fullDistance, expectedTravelTimeSeconds: 3_000,
      instructions: [], hasHighways: true)
    let localRoads = WholeShutoSurfaceRoute(
      coordinates: [origin, destination.coordinate], distanceMeters: 31_000,
      expectedTravelTimeSeconds: 2_400, instructions: [], hasHighways: false, name: "R15")

    let choice = WholeShutoProductModel.destinationRouteChoice(
      destination: destination,
      evaluation: WholeShutoRouteChoiceEvaluation(
        recommendations: recommendations, surfaceRoutesByRoutePlanID: legs,
        usesComparableProviderMetrics: false),
      providerRoutes: [sameAsKaido, localRoads])

    XCTAssertEqual(choice.options.map(\.travelSeconds), [2_400, 3_000, nil])
    XCTAssertEqual(choice.options[0].source, .provider(localRoads))
    XCTAssertEqual(choice.options[0].roads, .provider(usesExpressway: false, name: "R15"))
    XCTAssertEqual(choice.options[1].source, .kaido(recommendationIndex: 0))
    XCTAssertEqual(choice.options[2].source, .kaido(recommendationIndex: 1))
  }

  private func leg(_ coordinates: [ShutoCoordinate], seconds: Double) -> WholeShutoSurfaceRoute {
    let meters = WholeShutoProductModel.distance(coordinates[0], coordinates[coordinates.count - 1])
    return WholeShutoSurfaceRoute(
      coordinates: coordinates, distanceMeters: meters, expectedTravelTimeSeconds: seconds,
      instructions: [])
  }
}

final class ProviderRouteStub: WholeShutoSurfaceRouteResolving, @unchecked Sendable {
  private let lock = NSLock()
  private let routes: [WholeShutoSurfaceRoute]
  private var requests = 0

  init(routes: [WholeShutoSurfaceRoute]) { self.routes = routes }

  var requestCount: Int { lock.withLock { requests } }

  func route(from origin: ShutoCoordinate, to destination: ShutoCoordinate) async -> WholeShutoSurfaceRoute? {
    nil
  }

  func providerRoutes(from origin: ShutoCoordinate, to destination: ShutoCoordinate) async
    -> [WholeShutoSurfaceRoute]
  {
    lock.withLock { requests += 1 }
    return routes
  }
}

@MainActor
final class FakeLocationSource: ForegroundNavigationLocationSource {
  weak var delegate: (any ForegroundNavigationLocationSourceDelegate)?
  var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
  var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
  let supportsBackgroundNavigation = true
  private(set) var isUpdating = false
  private(set) var backgroundEnabled = false

  func requestWhenInUseAuthorization() {}
  func setBackgroundNavigationEnabled(_ enabled: Bool) { backgroundEnabled = enabled }
  func startUpdatingLocation() { isUpdating = true }
  func stopUpdatingLocation() { isUpdating = false }
}

@MainActor
final class RecordingSpeechOutput: GuidanceSpeechOutput {
  var eventHandler: ((GuidanceSpeechOutputEvent) -> Void)?
  var selectedVoiceProfile: GuidanceSpeechVoiceProfile?
  private(set) var spokenTexts: [String] = []

  func speak(_ command: GuidanceSpeechCommand) throws {
    spokenTexts.append(command.spokenText)
    eventHandler?(.didStart(command.identity))
    eventHandler?(.didFinish(command.identity))
  }

  func stop() {}
}
