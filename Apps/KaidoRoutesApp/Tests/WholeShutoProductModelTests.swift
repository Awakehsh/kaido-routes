import AVFAudio
import CoreLocation
import KaidoAppleAdapters
import KaidoDomain
import KaidoNavigation
import KaidoPresentation
import KaidoRouting
import KaidoSurfaceRouting
import MapKit
import Synchronization
import XCTest

@testable import KaidoRoutesApp

@MainActor
final class WholeShutoProductModelTests: XCTestCase {

  func testJourneyEndingChangesPreserveRouteAndRestoreFixedOrigin() async throws {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(), checkpointStore: store
    )
    model.preparePreviewJourney()
    let route = try XCTUnwrap(model.selectedRoute)
    let origin = try XCTUnwrap(model.origin)
    model.selectJourneyEnding(.returnToOrigin)
    await waitForEndingRoutes(model)
    XCTAssertEqual(model.destination, origin)
    XCTAssertEqual(model.selectedRoute, route)
    XCTAssertEqual(model.egressRoute?.coordinates.last, origin.coordinate)
    XCTAssertEqual(store.checkpoint?.journeyEnding, .returnToOrigin)

    let target = WholeShutoPlace(title: "Other place", coordinate: .init(latitude: 35.45, longitude: 139.64))
    model.selectJourneyEnding(.destination, destination: target)
    await waitForEndingRoutes(model)
    XCTAssertEqual(model.selectedRoute, route)
    XCTAssertEqual(model.egressRoute?.coordinates.last, target.coordinate)
    XCTAssertTrue(model.isJourneyReadyForPreview)

    model.selectJourneyEnding(.exit)
    await waitForEndingRoutes(model)
    XCTAssertEqual(model.selectedRoute, route)
    XCTAssertNil(model.egressRoute)
    XCTAssertEqual(model.destination?.coordinate, route.coordinates.last)
    XCTAssertTrue(model.isJourneyReadyForPreview)
    XCTAssertNotNil(model.plannedPreviewDurationSeconds)
    model.startNavigationSimulation(autoplay: false)
    let restored = WholeShutoProductModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(), checkpointStore: store
    )
    XCTAssertEqual(restored.journeyEnding, .exit)
    XCTAssertEqual(restored.selectedRoute, route)
    XCTAssertNil(restored.egressRoute)
    XCTAssertEqual(restored.phase, .surfaceAccess)
  }

  func testExitEndingCompletesWithoutInventingSurfaceEgress() async throws {
    let model = WholeShutoProductModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(), checkpointStore: nil
    )
    model.preparePreviewJourney()
    model.selectJourneyEnding(.exit)
    await waitForEndingRoutes(model)
    model.startNavigationSimulation(autoplay: false)
    for _ in 0..<20_000 where model.phase != .completed { await model.advanceSimulationForTesting() }
    XCTAssertEqual(model.phase, .completed)
    XCTAssertNil(model.egressRoute)
    XCTAssertEqual(model.currentCoordinate, model.selectedRoute?.coordinates.last)
  }

  func testDaikokuDefaultsToPAAndC1ReturnsToStart() async throws {
    let model = WholeShutoProductModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(), checkpointStore: nil
    )
    model.selectCurrentOrigin(.init(latitude: 35.6586, longitude: 139.7454))
    model.selectCircuit(.c1Inner)
    await waitForCircuitPairing(model)
    XCTAssertTrue(model.startCircuitJourney())
    await waitForEndingRoutes(model)
    XCTAssertEqual(model.journeyEnding, .returnToOrigin)
    XCTAssertEqual(model.destination, model.origin)
    model.reset()
    model.selectCurrentOrigin(.init(latitude: 35.6586, longitude: 139.7454))
    let tour = try XCTUnwrap(ShutoCircuitDefinition.bundled.first { $0.kind == .tour })
    model.selectCircuit(tour)
    await waitForCircuitPairing(model)
    XCTAssertTrue(model.startCircuitJourney())
    await waitForEndingRoutes(model)
    XCTAssertEqual(model.journeyEnding, .destination)
    XCTAssertEqual(model.selectedRoute?.routePlan.destinationParkingAreaID, "shuto.pa.daikoku")
    XCTAssertNil(model.selectedRoute?.exitFacility)
    XCTAssertNil(model.egressRoute)
    XCTAssertNil(model.egressRoute)
  }

  func testExitChangeRetainsCircuitAndLapsAndRejectsInvalidExit() async throws {
    let model = WholeShutoProductModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(), checkpointStore: nil
    )
    model.selectCurrentOrigin(.init(latitude: 35.6586, longitude: 139.7454))
    model.selectCircuit(.c1Inner)
    await waitForCircuitPairing(model)
    model.selectCircuitLaps(2)
    XCTAssertTrue(model.startCircuitJourney())
    await waitForEndingRoutes(model)
    let original = try XCTUnwrap(model.selectedRoute)
    do {
      try await model.selectJourneyExit("missing-exit")
      XCTFail("An unavailable exit must be rejected")
    } catch {}
    XCTAssertEqual(model.selectedRoute?.routePlan.id, original.routePlan.id)
    XCTAssertEqual(model.journeyEnding, .returnToOrigin)
    let candidates = try await model.journeyExitCandidates()
    let alternative = try XCTUnwrap(candidates.first { $0.facilityID != original.exitFacility?.facilityID })
    try await model.selectJourneyExit(alternative.facilityID)
    await waitForEndingRoutes(model)
    XCTAssertEqual(model.selectedRoute?.exitFacility?.facilityID, alternative.facilityID)
    XCTAssertEqual(model.selectedCircuit, .c1Inner)
    XCTAssertEqual(model.circuitLaps, 2)
    XCTAssertTrue(model.isCircuitRouteSelected)
    XCTAssertEqual(model.journeyEnding, .exit)
    XCTAssertNil(model.egressRoute)
  }

  func testMissingAccessStillBlocksAnExitOnlyJourney() async throws {
    let resolver = WholeShutoRecoveringSurfaceRouteResolver()
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: resolver, checkpointStore: nil
    )
    model.selectCurrentOrigin(.init(latitude: 35.6586, longitude: 139.7454))
    model.prepareCustomRouteDraft()
    XCTAssertTrue(model.applyCustomRoute())
    await waitForEndingRoutes(model)
    XCTAssertFalse(model.isJourneyReadyForPreview)
    XCTAssertFalse(model.canStartLiveNavigation)
    XCTAssertEqual(model.failureCode, "SURFACE_ROUTE_UNAVAILABLE")
    let started = await model.startLiveJourney()
    XCTAssertFalse(started)
    await resolver.setAvailable(true)
    model.retrySurfaceRoutes()
    await waitForEndingRoutes(model)
    XCTAssertTrue(model.isJourneyReadyForPreview)
    XCTAssertNil(model.egressRoute)
  }

  func testOnwardDestinationStartsAutomaticallyAfterExit() async throws {
    let model = WholeShutoProductModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(), checkpointStore: nil
    )
    model.preparePreviewJourney()
    let plan = try XCTUnwrap(model.selectedRoute?.routePlan)
    let target = WholeShutoPlace(title: "Onward stop", coordinate: .init(latitude: 35.45, longitude: 139.64))
    model.selectJourneyEnding(.destination, destination: target)
    await waitForEndingRoutes(model)
    model.startNavigationSimulation(autoplay: false)
    for _ in 0..<20_000 where model.phase != .surfaceEgress && model.phase != .completed {
      await model.advanceSimulationForTesting()
    }
    XCTAssertEqual(model.phase, .surfaceEgress)
    XCTAssertEqual(model.selectedRoute?.routePlan.id, plan.id)
    XCTAssertEqual(model.egressRoute?.coordinates.last, target.coordinate)
    for _ in 0..<1_000 where model.phase != .completed {
      await model.advanceSimulationForTesting()
    }
    XCTAssertEqual(model.phase, .completed)
    XCTAssertEqual(model.currentCoordinate, target.coordinate)
  }

  private func waitForEndingRoutes(_ model: WholeShutoProductModel) async {
    for _ in 0..<400 where model.isUpdatingSurfaceRoute {
      try? await Task.sleep(for: .milliseconds(20))
    }
    XCTAssertFalse(model.isUpdatingSurfaceRoute)
  }

  func testSpeechPrewarmPreparesTheGuidanceVoiceWithoutActivatingAudio() {
    let session = AVAudioSession.sharedInstance()
    let recorder = AudioSessionRequestRecorder()
    defer { recorder.uninstall() }
    var voiceLookups: [String] = []
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      checkpointStore: nil,
      speechOutput: LazyAVSpeechGuidanceOutput {
        AVSpeechGuidanceOutput(
          audioSession: session, notifications: NotificationCenter(),
          preferredVoiceIdentifierProvider: {
            voiceLookups.append($0)
            return nil
          })
      },
      languageSelectionProvider: {
        NavigationLanguageSelection(interfaceLocale: .english, guidanceVoiceLocale: .japanese)
      })
    model.prewarmSpeechOutput()
    XCTAssertEqual(recorder.categories, [])
    model.prewarmSpeechAudioSession()
    XCTAssertEqual(recorder.categories, [.playback])
    XCTAssertEqual(voiceLookups, [])
    model.prewarmGuidanceVoice()
    XCTAssertEqual(voiceLookups, ["ja-JP"])
    XCTAssertEqual(recorder.activations, [])
  }

  func testSpeechRecoveryStalePositionCancelsObsoleteManeuver() async throws {
    let output = SpeechRecoveryAppOutput()
    let model = try await speechRecoveryModel(output: output)
    let stops = output.stopCount
    XCTAssertNotNil(output.active)
    model.evaluateLiveLocationFreshness(atMilliseconds: 100_000)
    XCTAssertEqual(model.liveLocationState, .stale)
    XCTAssertFalse(model.hasCurrentGuidancePosition)
    XCTAssertNil(model.activeJunctionInsetPrompt)
    XCTAssertEqual(output.active?.anchorID, "JOURNEY_STATUS")
    XCTAssertGreaterThan(output.stopCount, stops)
    XCTAssertTrue(output.commands.last?.identity.promptID.contains("positionLost") == true)
    let notices = output.commands.count
    model.evaluateLiveLocationFreshness(atMilliseconds: 101_000)
    XCTAssertEqual(output.commands.count, notices)
    model.reset()
  }

  func testLocalizedSurfaceSpeechKeepsTheSelectedRouteAndInterfaceText() async throws {
    let output = SpeechRecoveryAppOutput()
    output.autoFinish = true
    let model = try await speechRecoveryModel(output: output, guidanceLocale: .japanese)
    model.setSpeechMode(.full)
    let route = try XCTUnwrap(model.accessRoute)
    let plan = try XCTUnwrap(model.selectedRoute?.routePlan)
    await model.consumeLiveObservationForTesting(Self.liveLocationEnvelope(
      id: "translated-surface.current", coordinate: try XCTUnwrap(route.coordinates.first), atMilliseconds: 1_000))
    let localized = "そのまま直進してください"
    XCTAssertEqual(model.surfaceInstruction(in: .english), "Continue on local road")
    XCTAssertEqual(model.currentInstructionForRepeat, localized)
    XCTAssertTrue(model.repeatGuidance())
    XCTAssertEqual(output.commands.last?.spokenText, localized)
    XCTAssertEqual(output.commands.last?.languageCode, "ja-JP")
    XCTAssertEqual(model.accessRoute, route)
    XCTAssertEqual(model.selectedRoute?.routePlan, plan)
    model.reset()
  }

  func testSpeechRecoveryCurrentStepPrecedesPreviewAfterFixGap() async throws {
    let output = SpeechRecoveryAppOutput()
    output.autoFinish = true
    let model = try await speechRecoveryModel(
      output: output, resolver: SpeechRecoveryShortStepResolver())
    let route = try XCTUnwrap(model.accessRoute)
    let start = try XCTUnwrap(route.coordinates.first)
    let end = try XCTUnwrap(route.coordinates.last)
    let coordinate = ShutoCoordinate(
      latitude: start.latitude + (end.latitude - start.latitude) * 0.325,
      longitude: start.longitude + (end.longitude - start.longitude) * 0.325)
    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(
        id: "speech-recovery.fix-return", coordinate: coordinate, atMilliseconds: 30_000))
    XCTAssertTrue(model.hasCurrentGuidancePosition)
    XCTAssertEqual(model.activeSurfaceInstruction, "Turn left at A")
    XCTAssertEqual(output.commands.map(\.spokenText), ["Continue straight", "Turn left at A"])
    model.reset()
  }

  func testSpeechRecoveryRetriesAnUnstartedJunctionThroughLiveObservations() async throws {
    let output = SpeechRecoveryAppOutput()
    output.autoFinish = true
    output.failNextReleased = true
    let model = try await speechRecoveryModel(output: output)
    let route = try XCTUnwrap(model.selectedRoute)
    var timestamp = 1_000
    var lastCoordinate = try XCTUnwrap(model.accessRoute?.coordinates.last)
    var lastCourse = Self.bearing(from: route.coordinates[0], to: route.coordinates[1])
    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(
        id: "speech-recovery.entry", coordinate: lastCoordinate,
        atMilliseconds: timestamp, courseDegrees: lastCourse))
    for index in route.edges.indices {
      let start = route.coordinates[index]
      let end = route.coordinates[index + 1]
      lastCourse = Self.bearing(from: start, to: end)
      for fraction in [0.25, 0.75] {
        timestamp += 1_000
        lastCoordinate = ShutoCoordinate(
          latitude: start.latitude + (end.latitude - start.latitude) * fraction,
          longitude: start.longitude + (end.longitude - start.longitude) * fraction)
        await model.consumeLiveObservationForTesting(
          Self.liveLocationEnvelope(
            id: "speech-recovery.\(timestamp)", coordinate: lastCoordinate,
            atMilliseconds: timestamp, courseDegrees: lastCourse, speedMetersPerSecond: 18))
        if output.failedCommand != nil { break }
      }
      if output.failedCommand != nil { break }
    }
    let failed = try XCTUnwrap(output.failedCommand)
    XCTAssertFalse(model.hasCompletedActiveGuidancePrompt)
    XCTAssertFalse(output.commands.contains { $0.identity == failed.identity })
    try await Task.sleep(nanoseconds: 2_100_000_000)
    output.autoFinish = false
    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(
        id: "speech-recovery.retry", coordinate: lastCoordinate,
        atMilliseconds: timestamp + 1_000, courseDegrees: lastCourse, speedMetersPerSecond: 18))
    XCTAssertEqual(output.commands.filter { $0.identity == failed.identity }.count, 1)
    XCTAssertFalse(model.hasCompletedActiveGuidancePrompt)
    output.finishActive()
    XCTAssertTrue(model.hasCompletedActiveGuidancePrompt)
    model.reset()
  }

  func testSpeechRecoveryRejectsStaleButKeepsInaccurateSurfaceFixes() async throws {
    for (observedAt, accuracy, accepted) in [(10.0, 5.0, false), (30.0, 100.0, true)] {
      let output = SpeechRecoveryAppOutput()
      output.autoFinish = true
      let model = try await speechRecoveryModel(output: output, resolver: SpeechRecoveryShortStepResolver())
      let route = try XCTUnwrap(model.accessRoute)
      let start = try XCTUnwrap(route.coordinates.first)
      let end = try XCTUnwrap(route.coordinates.last)
      let location = CLLocation(
        coordinate: CLLocationCoordinate2D(
          latitude: start.latitude + (end.latitude - start.latitude) * 0.325,
          longitude: start.longitude + (end.longitude - start.longitude) * 0.325),
        altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 1,
        timestamp: Date(timeIntervalSince1970: observedAt))
      let notices = output.commands.filter { $0.identity.anchorID == "JOURNEY_STATUS" }.count
      await model.consumeForegroundNavigationLocations([location], receivedAt: Date(timeIntervalSince1970: 30))
      if accepted {
        XCTAssertEqual(model.liveLocationState, .available)
        XCTAssertEqual(model.positionState, .surfacePreview)
        XCTAssertTrue(model.hasCurrentGuidancePosition)
        XCTAssertEqual(model.progressFraction, 0.325, accuracy: 0.02)
      } else {
        XCTAssertEqual(model.liveLocationState, .degraded)
        XCTAssertFalse(model.hasCurrentGuidancePosition)
        XCTAssertEqual(model.progressFraction, 0)
      }
      XCTAssertEqual(
        output.commands.filter { $0.identity.anchorID == "JOURNEY_STATUS" }.count, notices)
      // The accepted fix sits in the second step, so its instruction is spoken.
      XCTAssertEqual(
        output.commands.filter { $0.identity.anchorID == "PROVIDER_SURFACE_STEP" }.count,
        accepted ? 2 : 1)
      model.reset()
    }
  }

  func testRejectedRampAdmissionKeepsTheSurfacePositionAvailable() async throws {
    let output = SpeechRecoveryAppOutput()
    output.autoFinish = true
    let model = try await speechRecoveryModel(output: output, resolver: SpeechRecoveryShortStepResolver())
    let route = try XCTUnwrap(model.accessRoute)
    let start = try XCTUnwrap(route.coordinates.first)
    let end = try XCTUnwrap(route.coordinates.last)
    // Inside the 80 m admission zone but outside the 60 m handoff radius,
    // every fix also goes through ramp admission. Heading the wrong way
    // cannot be admitted, but the car is still on the surface polyline.
    // The fixture's straight line is far longer than its nominal distance,
    // so measure the 70 m on the ground.
    let metersPerDegree = 111_320.0
    let northMeters = (end.latitude - start.latitude) * metersPerDegree
    let eastMeters =
      (end.longitude - start.longitude) * metersPerDegree * cos(start.latitude * .pi / 180)
    let fraction = 1 - 70 / (northMeters * northMeters + eastMeters * eastMeters).squareRoot()
    let nearEnd = ShutoCoordinate(
      latitude: start.latitude + (end.latitude - start.latitude) * fraction,
      longitude: start.longitude + (end.longitude - start.longitude) * fraction)
    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(
        id: "surface.near-end.rejected", coordinate: nearEnd, atMilliseconds: 30_000,
        courseDegrees: 270))
    XCTAssertEqual(model.phase, .surfaceAccess)
    XCTAssertEqual(model.liveLocationState, .available)
    XCTAssertNil(model.liveLocationIssueCode)
    XCTAssertEqual(model.positionState, .surfacePreview)
    XCTAssertTrue(model.hasCurrentGuidancePosition)
    XCTAssertTrue(output.commands.filter { $0.identity.anchorID == "JOURNEY_STATUS" }.isEmpty)
    model.reset()
  }

  func testRampReachedBeforeTheSurfaceLegEndsJoinsWithoutRerouting() async throws {
    // The provider's leg ends 670 m from where the ramp really is, as an
    // entrance coordinate can: the car reaches the ramp while the leg still
    // has distance to run.
    let resolver = CountingSurfaceRouteResolver(endOffsetDegreesNorth: 0.006)
    let output = SpeechRecoveryAppOutput()
    output.autoFinish = true
    let model = try await speechRecoveryModel(output: output, resolver: resolver)
    let route = try XCTUnwrap(model.selectedRoute)
    let accessEnd = try XCTUnwrap(model.accessRoute?.coordinates.last)
    XCTAssertGreaterThan(
      CLLocation(latitude: accessEnd.latitude, longitude: accessEnd.longitude)
        .distance(
          from: CLLocation(
            latitude: route.coordinates[0].latitude,
            longitude: route.coordinates[0].longitude)),
      WholeShutoProductModel.surfaceEntryTransitionRadiusMeters * 5)
    let requestsBeforeRamp = await resolver.requestCount

    var timestamp = 1_000
    drive: for index in route.edges.indices {
      let start = route.coordinates[index]
      let end = route.coordinates[index + 1]
      for fraction in [0.25, 0.75] {
        timestamp += 1_000
        await model.consumeLiveObservationForTesting(
          Self.liveLocationEnvelope(
            id: "early-ramp.\(timestamp)",
            coordinate: ShutoCoordinate(
              latitude: start.latitude + (end.latitude - start.latitude) * fraction,
              longitude: start.longitude + (end.longitude - start.longitude) * fraction),
            atMilliseconds: timestamp, courseDegrees: Self.bearing(from: start, to: end),
            speedMetersPerSecond: 18))
        XCTAssertFalse(model.isReroutingSurfaceRoute)
        if model.phase == .expressway { break drive }
      }
    }
    XCTAssertEqual(model.phase, .expressway)
    XCTAssertEqual(model.runtimeJourneyPhase, .strictRoute)
    let requestsAfterJoin = await resolver.requestCount
    XCTAssertEqual(requestsAfterJoin, requestsBeforeRamp)
    model.reset()
  }

  func testStreetGoingStraightPastTheEntranceKeepsSurfaceGuidance() async throws {
    let output = SpeechRecoveryAppOutput()
    output.autoFinish = true
    let model = try await speechRecoveryModel(output: output)
    let route = try XCTUnwrap(model.selectedRoute)
    let release = try ShutoCircuitProductReleaseBuilder.buildPlannedRouteRelease(
      context: try ShutoPlannedRouteRuntimeCompiler.NetworkContext(database: model.database),
      route: route)
    let corridorEdges = Dictionary(
      uniqueKeysWithValues: release.navigation.bundle.matcherCorridor.edges.map { ($0.id, $0) })
    let approachEdgeID = try XCTUnwrap(
      release.navigation.bundle.runtimePolicy.entryTransition.directedEdgeIDs.first)
    let approach = try XCTUnwrap(corridorEdges[approachEdgeID]?.coordinates)
    let start = ShutoCoordinate(latitude: approach[0].latitude, longitude: approach[0].longitude)
    let course = Self.bearing(
      from: start,
      to: ShutoCoordinate(latitude: approach[1].latitude, longitude: approach[1].longitude))
    // The straight continuation of the reviewed approach: the street under
    // or beside the ramp, never the ramp itself.
    let metersPerDegree = 111_320.0
    for step in 0..<80 {
      let meters = Double(step) * 15
      let coordinate = ShutoCoordinate(
        latitude: start.latitude + meters * cos(course * .pi / 180) / metersPerDegree,
        longitude: start.longitude
          + meters * sin(course * .pi / 180)
          / (metersPerDegree * cos(start.latitude * .pi / 180)))
      await model.consumeLiveObservationForTesting(
        Self.liveLocationEnvelope(
          id: "straight-street.\(step)", coordinate: coordinate,
          atMilliseconds: 2_000 + step * 1_000, courseDegrees: course,
          speedMetersPerSecond: 15))
      XCTAssertNotEqual(model.phase, .expressway, "step \(step)")
      XCTAssertNotEqual(model.runtimeJourneyPhase, .strictRoute, "step \(step)")
    }
    // Where the approach road and the ramp coincide the drive hands over to
    // the entrance; once the street has left every corridor road the
    // ordinary-road leg is back, rerouted to the entrance ahead.
    for _ in 0..<100 where model.isReroutingSurfaceRoute {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertEqual(model.phase, .surfaceAccess)
    XCTAssertNil(model.runtimeOccurrenceID)
    XCTAssertEqual(model.activeSurfaceInstruction, "Continue on local road")
    model.reset()
  }

  func testPositionLossNoticeStaysSilentInsideTheCooldown() async throws {
    let output = SpeechRecoveryAppOutput()
    output.autoFinish = true
    let model = try await speechRecoveryModel(output: output)
    let route = try XCTUnwrap(model.accessRoute)
    let start = try XCTUnwrap(route.coordinates.first)
    func count(_ fragment: String) -> Int {
      output.commands.filter { $0.identity.promptID.contains(fragment) }.count
    }

    model.evaluateLiveLocationFreshness(atMilliseconds: 100_000)
    XCTAssertEqual(model.liveLocationState, .stale)
    XCTAssertEqual(count("positionLost"), 1)

    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(id: "loss.recovered.0", coordinate: start, atMilliseconds: 101_000))
    XCTAssertEqual(model.liveLocationState, .available)
    XCTAssertEqual(count("positionRecovered"), 1)

    // A second loss 20 s after the first is a flapping signal, not news.
    model.evaluateLiveLocationFreshness(atMilliseconds: 120_000)
    XCTAssertEqual(model.liveLocationState, .stale)
    XCTAssertEqual(count("positionLost"), 1)

    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(id: "loss.recovered.1", coordinate: start, atMilliseconds: 121_000))
    XCTAssertEqual(model.liveLocationState, .available)
    XCTAssertEqual(count("positionRecovered"), 1)

    model.evaluateLiveLocationFreshness(atMilliseconds: 170_000)
    XCTAssertEqual(model.liveLocationState, .stale)
    XCTAssertEqual(count("positionLost"), 2)
    model.reset()
  }

  func testCoarseFixLetsTheSpokenJunctionCueFinish() async throws {
    let output = SpeechRecoveryAppOutput()
    let model = try await speechRecoveryModel(output: output)
    let route = try XCTUnwrap(model.selectedRoute)
    func isJunctionCue(_ identity: GuidanceSpeechIdentity?) -> Bool {
      guard let identity else { return false }
      return identity.anchorID != "PROVIDER_SURFACE_STEP"
        && identity.anchorID != "JOURNEY_STATUS"
    }
    var position = try await driveSpeechRecoveryRoute(model) {
      isJunctionCue(output.active)
    }
    let cue = try XCTUnwrap(output.active)
    let movementID = try XCTUnwrap(model.presentationProjection?.iPhone.nextMovementOccurrenceID)
    let movementIndex = try XCTUnwrap(route.routePlan.occurrence(id: movementID)?.index)
    let stops = output.stopCount

    // Under an elevated road: the same place at 50 m accuracy. Progress is
    // unresolved, not contradicted, so the cue keeps speaking.
    position.timestamp += 1_000
    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(
        id: "coarse-cue.coarse", coordinate: position.coordinate,
        atMilliseconds: position.timestamp, courseDegrees: position.course,
        speedMetersPerSecond: 18, horizontalAccuracyMeters: 50))
    XCTAssertEqual(model.matcherConfidence, .low)
    XCTAssertEqual(output.active, cue)
    XCTAssertEqual(output.stopCount, stops)

    // Once the car is past the junction the cue describes nothing ahead.
    for index in position.edgeIndex...min(movementIndex + 1, route.edges.count - 1) {
      let start = route.coordinates[index]
      let end = route.coordinates[index + 1]
      for fraction in [0.25, 0.75] {
        position.timestamp += 1_000
        await model.consumeLiveObservationForTesting(
          Self.liveLocationEnvelope(
            id: "coarse-cue.past.\(position.timestamp)",
            coordinate: ShutoCoordinate(
              latitude: start.latitude + (end.latitude - start.latitude) * fraction,
              longitude: start.longitude + (end.longitude - start.longitude) * fraction),
            atMilliseconds: position.timestamp,
            courseDegrees: Self.bearing(from: start, to: end), speedMetersPerSecond: 18))
      }
    }
    XCTAssertNotEqual(output.active, cue)
    model.reset()
  }

  func testMutedNoticesAreDroppedRatherThanSpokenOnUnmute() async throws {
    let suiteName = UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    func positionLostCount(_ output: SpeechRecoveryAppOutput) -> Int {
      output.commands.filter { $0.identity.promptID.contains("positionLost") }.count
    }

    // A notice raised while muted is not queued for later.
    let output = SpeechRecoveryAppOutput()
    output.autoFinish = true
    let model = try await speechRecoveryModel(output: output, defaults: defaults)
    var position = try await driveSpeechRecoveryRoute(model) { model.phase == .expressway }
    model.setSpeechMode(.muted)
    model.evaluateLiveLocationFreshness(atMilliseconds: position.timestamp + 10_000)
    XCTAssertEqual(model.liveLocationState, .stale)
    model.setSpeechMode(.full)
    position.timestamp += 11_000
    // A coarse fix flushes pending notices without announcing a recovery.
    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(
        id: "muted-notice.coarse", coordinate: position.coordinate,
        atMilliseconds: position.timestamp, courseDegrees: position.course,
        speedMetersPerSecond: 18, horizontalAccuracyMeters: 50))
    XCTAssertEqual(positionLostCount(output), 0)
    model.reset()

    // A notice already waiting when the driver mutes is dropped with it.
    let interrupted = SpeechRecoveryAppOutput()
    interrupted.autoFinish = true
    let second = try await speechRecoveryModel(output: interrupted, defaults: defaults)
    position = try await driveSpeechRecoveryRoute(second) { second.phase == .expressway }
    interrupted.eventHandler?(.interruptionBegan)
    second.evaluateLiveLocationFreshness(atMilliseconds: position.timestamp + 10_000)
    XCTAssertEqual(positionLostCount(interrupted), 0)
    second.setSpeechMode(.muted)
    interrupted.eventHandler?(.interruptionEnded)
    second.setSpeechMode(.full)
    position.timestamp += 11_000
    await second.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(
        id: "muted-notice.pending", coordinate: position.coordinate,
        atMilliseconds: position.timestamp, courseDegrees: position.course,
        speedMetersPerSecond: 18, horizontalAccuracyMeters: 50))
    XCTAssertEqual(positionLostCount(interrupted), 0)
    second.reset()
  }

  func testSiriUnmuteRestoresTheDriversVoiceMode() async throws {
    let suiteName = UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let output = SpeechRecoveryAppOutput()
    output.autoFinish = true
    let model = try await speechRecoveryModel(output: output, defaults: defaults)
    ActiveDriveControl.model = model
    defer { ActiveDriveControl.model = nil }
    model.setSpeechMode(.concise)
    _ = try await DriveControlIntent(action: .mute).perform()
    XCTAssertEqual(model.speechMode, .muted)
    _ = try await DriveControlIntent(action: .unmute).perform()
    XCTAssertEqual(model.speechMode, .concise)
    model.reset()
  }

  func testLapSwapKeepsThePositionLossCooldown() async throws {
    var nowMilliseconds = 1_000
    let suiteName = UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let output = SpeechRecoveryAppOutput()
    output.autoFinish = true
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil,
      liveLocationSource: WholeShutoBackgroundNavigationLocationSource(),
      speechOutput: output,
      nowMillisecondsProvider: { nowMilliseconds },
      driveRecordPreferenceStore: defaults
    )
    model.selectCurrentOrigin(ShutoCoordinate(latitude: 35.6777, longitude: 139.7708))
    model.selectCircuit(.c1Outer)
    await waitForCircuitPairing(model)
    XCTAssertTrue(model.startCircuitJourney())
    for _ in 0..<1_200
    where model.isPreparingLiveNavigation || model.isUpdatingSurfaceRoute
      || !model.canStartLiveNavigation
    {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }
    let started = await model.startLiveJourney()
    XCTAssertTrue(started, model.failureCode ?? "no failure code")
    let route = try XCTUnwrap(model.selectedRoute)
    if let accessEnd = model.accessRoute?.coordinates.last {
      await model.consumeLiveObservationForTesting(
        Self.liveLocationEnvelope(
          id: "lap-cooldown.access-end", coordinate: accessEnd, atMilliseconds: nowMilliseconds,
          courseDegrees: Self.bearing(from: route.coordinates[0], to: route.coordinates[1])))
    }
    var index = 0
    while model.phase != .expressway, index < 40 {
      let start = route.coordinates[index]
      let end = route.coordinates[index + 1]
      for fraction in [0.25, 0.75] {
        nowMilliseconds += 1_000
        await model.consumeLiveObservationForTesting(
          Self.liveLocationEnvelope(
            id: "lap-cooldown.\(nowMilliseconds)",
            coordinate: ShutoCoordinate(
              latitude: start.latitude + (end.latitude - start.latitude) * fraction,
              longitude: start.longitude + (end.longitude - start.longitude) * fraction),
            atMilliseconds: nowMilliseconds, courseDegrees: Self.bearing(from: start, to: end),
            speedMetersPerSecond: 18))
      }
      index += 1
    }
    XCTAssertEqual(model.phase, .expressway)
    func positionLostCount() -> Int {
      output.commands.filter { $0.identity.promptID.contains("positionLost") }.count
    }

    model.evaluateLiveLocationFreshness(atMilliseconds: nowMilliseconds + 10_000)
    XCTAssertEqual(positionLostCount(), 1)
    let added = await model.addOneLap()
    XCTAssertTrue(added, model.failureCode ?? "no failure code")
    // Still the same loss, twenty seconds later: the new plan is not news.
    model.evaluateLiveLocationFreshness(atMilliseconds: nowMilliseconds + 20_000)
    XCTAssertEqual(model.liveLocationState, .stale)
    XCTAssertEqual(positionLostCount(), 1)

    // The fix comes back and the drive moves onto the new plan, which
    // reconfigures speech. Losing it again inside the minute is still quiet.
    nowMilliseconds += 20_000
    while model.isChangingLaps, index < 80 {
      let start = route.coordinates[index]
      let end = route.coordinates[index + 1]
      for fraction in [0.25, 0.75] where model.isChangingLaps {
        nowMilliseconds += 1_000
        await model.consumeLiveObservationForTesting(
          Self.liveLocationEnvelope(
            id: "lap-cooldown.\(nowMilliseconds)",
            coordinate: ShutoCoordinate(
              latitude: start.latitude + (end.latitude - start.latitude) * fraction,
              longitude: start.longitude + (end.longitude - start.longitude) * fraction),
            atMilliseconds: nowMilliseconds, courseDegrees: Self.bearing(from: start, to: end),
            speedMetersPerSecond: 18))
      }
      index += 1
    }
    XCTAssertFalse(model.isChangingLaps)
    XCTAssertNotEqual(model.selectedRoute?.routePlan, route.routePlan)
    model.evaluateLiveLocationFreshness(atMilliseconds: nowMilliseconds + 10_000)
    XCTAssertEqual(model.liveLocationState, .stale)
    XCTAssertEqual(positionLostCount(), 1)
    model.reset()
  }

  private struct LiveDrivePosition {
    var timestamp: Int
    var edgeIndex: Int
    var coordinate: ShutoCoordinate
    var course: Double
  }

  /// Feeds accurate on-route fixes from the access end, two per plan edge,
  /// until `isDone` holds.
  private func driveSpeechRecoveryRoute(
    _ model: WholeShutoProductModel,
    speedMetersPerSecond: Double = 18,
    until isDone: () -> Bool
  ) async throws -> LiveDrivePosition {
    let route = try XCTUnwrap(model.selectedRoute)
    var position = LiveDrivePosition(
      timestamp: 1_000, edgeIndex: 0,
      coordinate: try XCTUnwrap(model.accessRoute?.coordinates.last),
      course: Self.bearing(from: route.coordinates[0], to: route.coordinates[1]))
    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(
        id: "drive.entry", coordinate: position.coordinate,
        atMilliseconds: position.timestamp, courseDegrees: position.course))
    for index in route.edges.indices {
      let start = route.coordinates[index]
      let end = route.coordinates[index + 1]
      position.edgeIndex = index
      position.course = Self.bearing(from: start, to: end)
      for fraction in [0.25, 0.75] {
        position.timestamp += 1_000
        position.coordinate = ShutoCoordinate(
          latitude: start.latitude + (end.latitude - start.latitude) * fraction,
          longitude: start.longitude + (end.longitude - start.longitude) * fraction)
        await model.consumeLiveObservationForTesting(
          Self.liveLocationEnvelope(
            id: "drive.\(position.timestamp)", coordinate: position.coordinate,
            atMilliseconds: position.timestamp, courseDegrees: position.course,
            speedMetersPerSecond: speedMetersPerSecond))
        if isDone() { return position }
      }
    }
    XCTFail("The route ended before the drive reached the expected state")
    return position
  }

  private func speechRecoveryModel(
    output: SpeechRecoveryAppOutput,
    resolver: any WholeShutoSurfaceRouteResolving = WholeShutoInstructionSurfaceRouteResolver(),
    guidanceLocale: KaidoReleaseLocale = .english,
    defaults: UserDefaults = .standard
  ) async throws -> WholeShutoProductModel {
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: resolver, checkpointStore: nil,
      liveLocationSource: WholeShutoBackgroundNavigationLocationSource(),
      speechOutput: output, nowMillisecondsProvider: { 1_000 },
      languageSelectionProvider: {
        NavigationLanguageSelection(interfaceLocale: .english, guidanceVoiceLocale: guidanceLocale)
      }, driveRecordPreferenceStore: defaults)
    model.selectCurrentOrigin(ShutoCoordinate(latitude: 35.6812, longitude: 139.7671))
    model.prepareCustomRouteDraft()
    model.selectCustomEntry(facilityID: "shuto.ic.b.urayasu")
    model.selectCustomExit(facilityID: "shuto.ic.9.fukudumi")
    XCTAssertTrue(model.applyCustomRoute())
    for _ in 0..<300 where model.isPreparingLiveNavigation || model.isUpdatingSurfaceRoute {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }
    let started = await model.startLiveJourney()
    XCTAssertTrue(started)
    return model
  }

  func testIdleTimerStaysDisabledOnlyDuringLiveJourney() {
    XCTAssertTrue(
      WholeShutoIdleTimerPolicy.disablesIdleTimer(
        isLiveDrive: true,
        phase: .expressway
      )
    )
    XCTAssertFalse(
      WholeShutoIdleTimerPolicy.disablesIdleTimer(
        isLiveDrive: true,
        phase: .completed
      )
    )
    XCTAssertFalse(
      WholeShutoIdleTimerPolicy.disablesIdleTimer(
        isLiveDrive: false,
        phase: .expressway
      )
    )
  }

  func testPlanningAndResetUseTheNetworkDiagram() {
    let model = WholeShutoProductModel(checkpointStore: nil)

    XCTAssertEqual(model.phase, .planning)
    XCTAssertEqual(model.mapMode, .network)

    model.preparePreviewJourney()
    model.mapMode = .geographic
    model.reset()

    XCTAssertEqual(model.phase, .planning)
    XCTAssertEqual(model.mapMode, .network)
  }

  func testMajorRoadPreferenceChoosesSimplerAlternativeWithinDetourBudget() {
    func route(
      distanceMeters: Double,
      travelTimeSeconds: Double,
      instructionCount: Int
    ) -> WholeShutoSurfaceRoute {
      let instructions = (0..<instructionCount).map { "Step \($0)" }
      return WholeShutoSurfaceRoute(
        coordinates: [
          ShutoCoordinate(latitude: 35.68, longitude: 139.76),
          ShutoCoordinate(latitude: 35.69, longitude: 139.77),
        ],
        distanceMeters: distanceMeters,
        expectedTravelTimeSeconds: travelTimeSeconds,
        instructions: instructions
      )
    }

    let fastest = route(
      distanceMeters: 4_000,
      travelTimeSeconds: 600,
      instructionCount: 8
    )
    let simpler = route(
      distanceMeters: 5_500,
      travelTimeSeconds: 660,
      instructionCount: 3
    )

    XCTAssertEqual(
      WholeShutoMapKitSurfaceRouteResolver.selectRoute(from: [fastest, simpler]),
      simpler
    )
  }

  func testMajorRoadPreferenceDoesNotTakeAnUnboundedDetour() {
    func route(
      travelTimeSeconds: Double,
      instructionCount: Int
    ) -> WholeShutoSurfaceRoute {
      WholeShutoSurfaceRoute(
        coordinates: [
          ShutoCoordinate(latitude: 35.68, longitude: 139.76),
          ShutoCoordinate(latitude: 35.69, longitude: 139.77),
        ],
        distanceMeters: travelTimeSeconds * 8,
        expectedTravelTimeSeconds: travelTimeSeconds,
        instructions: (0..<instructionCount).map { "Step \($0)" }
      )
    }

    let shortFastRoute = route(travelTimeSeconds: 600, instructionCount: 8)
    let overPercentageLimit = route(
      travelTimeSeconds: 700,
      instructionCount: 2
    )

    XCTAssertEqual(
      WholeShutoMapKitSurfaceRouteResolver.selectRoute(
        from: [overPercentageLimit, shortFastRoute]
      ),
      shortFastRoute
    )

    let longFastRoute = route(
      travelTimeSeconds: 7_200,
      instructionCount: 8
    )
    let overAbsoluteLimit = route(
      travelTimeSeconds: 7_700,
      instructionCount: 2
    )
    XCTAssertEqual(
      WholeShutoMapKitSurfaceRouteResolver.selectRoute(
        from: [overAbsoluteLimit, longFastRoute]
      ),
      longFastRoute
    )
  }

  func testSurfaceRoutePreferenceDefaultsPersistsAndLeavesConnectingLegsAlone()
    async
  {
    let suiteName = "app.kaidoroutes.tests.surface-route-preference"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let resolver = WholeShutoCountingSurfaceRouteResolver()
    let model = WholeShutoProductModel(
      locationProvider: WholeShutoUnexpectedLocationProvider(),
      surfaceRouteResolver: resolver,
      checkpointStore: nil,
      driveRecordPreferenceStore: defaults
    )

    XCTAssertEqual(model.surfaceRoutePreference, .preferHighways)
    model.selectCurrentOrigin(
      WholeShutoProductModel.previewOrigin.coordinate
    )
    model.selectDestinationPreview(
      WholeShutoProductModel.previewDestination
    )
    model.planJourney()
    for _ in 0..<1_000 where model.isPlanning || model.isUpdatingSurfaceRoute {
      await Task.yield()
    }
    XCTAssertEqual(model.phase, .review)
    let plannedRequests = await resolver.requestCount()
    XCTAssertGreaterThan(plannedRequests, 0)

    // Connecting legs are ordinary roads under either setting, so changing
    // it in review has nothing to re-request.
    model.setSurfaceRoutePreference(.avoidHighways)
    for _ in 0..<1_000 where model.isUpdatingSurfaceRoute {
      await Task.yield()
    }
    let requestsAfterChange = await resolver.requestCount()
    XCTAssertEqual(requestsAfterChange, plannedRequests)
    XCTAssertEqual(
      WholeShutoProductModel(
        surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
        checkpointStore: nil,
        driveRecordPreferenceStore: defaults
      ).surfaceRoutePreference,
      .avoidHighways
    )

    model.setSurfaceRoutePreference(.preferHighways)
    let reopened = WholeShutoProductModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil,
      driveRecordPreferenceStore: defaults
    )
    XCTAssertEqual(reopened.surfaceRoutePreference, .preferHighways)
  }

  func testConnectingLegsRequestAndChooseOrdinaryRoads() {
    let origin = WholeShutoProductModel.previewOrigin.coordinate
    let destination = WholeShutoProductModel.previewDestination.coordinate
    let request = WholeShutoMapKitSurfaceRouteResolver.request(
      from: origin, to: destination
    )
    XCTAssertEqual(request.highwayPreference, .avoid)
    XCTAssertEqual(request.tollPreference, .avoid)
    func route(seconds: Double, highway: Bool) -> WholeShutoSurfaceRoute {
      WholeShutoSurfaceRoute(
        coordinates: [origin, destination], distanceMeters: 8_000,
        expectedTravelTimeSeconds: seconds, instructions: [],
        hasHighways: highway, hasTolls: highway
      )
    }
    let ordinary = route(seconds: 600, highway: false)
    let fasterHighway = route(seconds: 500, highway: true)
    let slowerOrdinary = route(seconds: 900, highway: false)
    XCTAssertEqual(WholeShutoMapKitSurfaceRouteResolver.selectRoute(
      from: [fasterHighway, ordinary]
    ), ordinary)
    XCTAssertEqual(WholeShutoMapKitSurfaceRouteResolver.selectRoute(
      from: [fasterHighway, slowerOrdinary]
    ), slowerOrdinary)
    XCTAssertEqual(WholeShutoMapKitSurfaceRouteResolver.selectRoute(
      from: [fasterHighway]
    ), fasterHighway)
  }

  func testTourHighwayPreferenceRecomputesNearbyConnectingEntrance() async throws {
    let suiteName = UUID().uuidString
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil, driveRecordPreferenceStore: defaults
    )
    let harumi = try XCTUnwrap(model.database.directionalFacilities.first {
      $0.facilityID == "shuto.ic.10.harumi"
    })
    model.selectCurrentOrigin(harumi.coordinate)
    model.selectCircuit(.wanganDaikokuRun)
    await waitForCircuitPairing(model)
    XCTAssertEqual(model.circuitEntryFacilityID, harumi.facilityID)
    model.setSurfaceRoutePreference(.avoidHighways)
    XCTAssertFalse(model.canStartCircuitJourney)
    await waitForCircuitPairing(model)
    XCTAssertEqual(model.circuitEntranceCandidates.first?.routeID, "B")
    XCTAssertFalse(model.circuitEntranceCandidates.contains { $0.facilityID == harumi.facilityID })
    model.setSurfaceRoutePreference(.preferHighways)
    await waitForCircuitPairing(model)
    XCTAssertEqual(model.circuitEntryFacilityID, harumi.facilityID)
    XCTAssertTrue(model.startCircuitJourney())
    await waitForLiveNavigationPreparation(model)
    XCTAssertTrue(model.canStartLiveNavigation)
    XCTAssertTrue(model.selectedRoute?.routePlan.occurrences.contains {
      $0.kind == .paVisit && $0.parkingAreaID == "shuto.pa.daikoku"
    } == true)
  }

  func testRouteJoinIsNeitherOfferedNorDeclarableOutsideALiveEntry() async {
    let model = WholeShutoProductModel(checkpointStore: nil)

    // The offer belongs to a live drive stalled in ENTRY_TRANSITION. A parked
    // model must never present it, and the declaration must refuse even if a
    // caller reaches for it anyway.
    XCTAssertEqual(model.routeJoinState, .unavailable)
    let declared = await model.declareAlreadyOnRoute()
    XCTAssertFalse(declared)
    XCTAssertEqual(model.routeJoinState, .unavailable)

    model.preparePreviewJourney()
    XCTAssertEqual(model.routeJoinState, .unavailable)
    let declaredInPreview = await model.declareAlreadyOnRoute()
    XCTAssertFalse(declaredInPreview)
    XCTAssertEqual(model.routeJoinState, .unavailable)
  }

  func testLiveDriveFailsClosedWithoutValidatedNavigationRelease() async {
    let model = WholeShutoProductModel(checkpointStore: nil)
    model.preparePreviewJourney()
    XCTAssertEqual(model.phase, .review)
    XCTAssertTrue(model.isJourneyReadyForPreview)

    XCTAssertFalse(model.canStartLiveNavigation)
    XCTAssertEqual(
      model.liveNavigationBlockerCode,
      "WHOLE_SHUTO_NAVIGATION_RELEASE_REQUIRED"
    )
    let startedLiveJourney = await model.startLiveJourney()
    XCTAssertFalse(startedLiveJourney)
    XCTAssertFalse(model.isLiveDrive)
    XCTAssertFalse(model.isPlaying)
    XCTAssertEqual(model.phase, .review)
    XCTAssertEqual(model.liveLocationState, .inactive)
    XCTAssertEqual(
      model.failureCode,
      "WHOLE_SHUTO_NAVIGATION_RELEASE_REQUIRED"
    )

    model.startNavigationSimulation()
    XCTAssertFalse(model.isLiveDrive)
    XCTAssertTrue(model.isPlaying)
    XCTAssertNil(model.failureCode)
  }

  func testExactC1CircuitAdmitsBundledForegroundNavigation() async throws {
    let database = try WholeShutoNetworkCatalog.bundled()
    let entry = try XCTUnwrap(
      BundledProductReleaseCatalogLoader.bundledForeground()
        .foregroundNavigationEntries.first
    )
    let route = try ShutoCircuitProductReleaseBuilder.plannedRoute(
      database: database
    )
    let core = try KaidoLiveJourneyAdmission(
      release: entry.release,
      selectedRoutePlan: route.routePlan,
      journeyPlan: JourneyPlanCompiler.expresswayOnly(
        release: entry.release
      )
    )
    let model = WholeShutoProductModel(
      database: database,
      locationProvider: WholeShutoUnexpectedLocationProvider(),
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil,
      liveJourneyAdmissions: [
        try WholeShutoLiveJourneyAdmission(core: core)
      ]
    )

    let releasedEntrance = try XCTUnwrap(
      database.directionalFacilities.first {
        $0.facilityID == ShutoCircuitProductReleaseBuilder.entryFacilityID
      }
    )
    model.selectCurrentOrigin(releasedEntrance.coordinate)
    model.selectCircuit(.c1Inner)
    await waitForCircuitPairing(model)

    XCTAssertEqual(
      model.circuitEntryFacilityID,
      ShutoCircuitProductReleaseBuilder.entryFacilityID
    )
    XCTAssertEqual(
      model.circuitExitFacilityID,
      ShutoCircuitProductReleaseBuilder.exitFacilityID
    )
    XCTAssertTrue(model.startCircuitJourney())
    await waitForLiveNavigationPreparation(model)
    XCTAssertEqual(model.selectedRoute?.routePlan, route.routePlan)
    XCTAssertTrue(model.canStartLiveNavigation)
    XCTAssertNil(model.liveNavigationBlockerCode)
  }

  func testC1OuterCircuitBuildsForegroundNavigationOnDemand() async throws {
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6777, longitude: 139.7708)
    )
    model.selectCircuit(.c1Outer)
    await waitForCircuitPairing(model)

    XCTAssertNotNil(model.circuitEntryFacilityID)
    XCTAssertNotNil(model.circuitExitFacilityID)
    XCTAssertEqual(
      model.circuitEntryFacilityID,
      "shuto.ic.c1.kyoubashi"
    )
    XCTAssertTrue(model.startCircuitJourney())
    await model.awaitLiveNavigationPreparationForTesting()

    XCTAssertEqual(model.phase, .review)
    XCTAssertEqual(
      model.selectedRoute?.routePlan.id.hasPrefix(
        "shuto.circuit.c1-outer."
      ),
      true
    )
    XCTAssertTrue(model.canStartLiveNavigation)
    XCTAssertNil(model.liveNavigationBlockerCode)
  }

  func testLapCountChangesFromBehindTheWheel() async throws {
    var nowMilliseconds = 1_000
    let locationSource = WholeShutoBackgroundNavigationLocationSource()
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil,
      liveLocationSource: locationSource,
      speechOutput: WholeShutoRecordingSpeechOutput(),
      nowMillisecondsProvider: { nowMilliseconds }
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6777, longitude: 139.7708)
    )
    model.selectCircuit(.c1Outer)
    await waitForCircuitPairing(model)
    model.selectCircuitLaps(3)
    XCTAssertEqual(model.circuitLaps, 3)
    XCTAssertTrue(model.startCircuitJourney())
    // Three laps of C1 outer is a large release to compile on demand.
    for _ in 0..<1_200
    where model.isPreparingLiveNavigation || model.isUpdatingSurfaceRoute
      || !model.canStartLiveNavigation
    {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }
    XCTAssertTrue(
      model.canStartLiveNavigation,
      model.liveNavigationBlockerCode ?? "no blocker code"
    )
    XCTAssertEqual(model.phase, .review)

    let threeLapRoute = try XCTUnwrap(model.selectedRoute)
    // Three laps carry four boundary marks: one per lap start plus the end
    // of the last, which is where the exit tail begins.
    XCTAssertEqual(threeLapRoute.lapBoundaryOccurrenceIndices.count, 4)

    let started = await model.startLiveJourney()
    XCTAssertTrue(started, model.failureCode ?? "no failure code")

    // Nothing can be changed until the drive is actually on the expressway.
    let droppedBeforeExpressway = await model.dropOneLap()
    XCTAssertFalse(droppedBeforeExpressway)
    let addedBeforeExpressway = await model.addOneLap()
    XCTAssertFalse(addedBeforeExpressway)

    // Drive onto the route for real: the entry admission is what puts the
    // session on the expressway, and there is no test door around it.
    if let accessEnd = model.accessRoute?.coordinates.last {
      await model.consumeLiveObservationForTesting(
        Self.liveLocationEnvelope(
          id: "lap.access-end",
          coordinate: accessEnd,
          atMilliseconds: nowMilliseconds,
          courseDegrees: Self.bearing(
            from: threeLapRoute.coordinates[0],
            to: threeLapRoute.coordinates[1]
          )
        )
      )
    }
    var observationIndex = 0
    let lapLength =
      threeLapRoute.lapBoundaryOccurrenceIndices[1]
      - threeLapRoute.lapBoundaryOccurrenceIndices[0]
    // Deep enough into the first lap that the engine's own occurrence — not
    // just the App's projection — is inside it, with two whole laps still
    // ahead. A lap can only be dropped from inside a lap.
    let targetEdgeIndex =
      threeLapRoute.lapBoundaryOccurrenceIndices[1] - 40
    for edgeIndex in threeLapRoute.edges.indices
    where edgeIndex <= targetEdgeIndex {
      let start = threeLapRoute.coordinates[edgeIndex]
      let end = threeLapRoute.coordinates[edgeIndex + 1]
      let course = Self.bearing(from: start, to: end)
      for fraction in [0.25, 0.75] {
        observationIndex += 1
        nowMilliseconds += 1_000
        await model.consumeLiveObservationForTesting(
          Self.liveLocationEnvelope(
            id: "lap.route.\(observationIndex)",
            coordinate: ShutoCoordinate(
              latitude: start.latitude
                + (end.latitude - start.latitude) * fraction,
              longitude: start.longitude
                + (end.longitude - start.longitude) * fraction
            ),
            atMilliseconds: nowMilliseconds,
            courseDegrees: course,
            speedMetersPerSecond: 18
          )
        )
      }
    }

    XCTAssertEqual(model.phase, .expressway)
    // Ramp entry vouches for the planned entrance.
    XCTAssertFalse(model.entryIsUnconfirmed)
    XCTAssertEqual(
      model.driveEntryFacility?.facilityID,
      threeLapRoute.entryFacility.facilityID
    )
    for _ in 0..<200 where model.remainingWholeLapsAhead == 0 {
      try? await Task.sleep(nanoseconds: 25_000_000)
    }
    // Partway through lap one, two whole laps are still ahead to drop.
    XCTAssertEqual(model.remainingWholeLapsAhead, 2)

    let occurrenceBeforeDrop = try XCTUnwrap(model.runtimeOccurrenceID)
    let progressBeforeDrop = model.progressFraction
    let dropped = await model.dropOneLap()
    XCTAssertTrue(dropped)
    let planAfterDrop = try XCTUnwrap(model.selectedRoute).routePlan
    let indexBefore = try XCTUnwrap(
      planAfterDrop.occurrence(id: occurrenceBeforeDrop)?.index
    )
    let indexAfter = try XCTUnwrap(
      model.runtimeOccurrenceID.flatMap {
        planAfterDrop.occurrence(id: $0)?.index
      }
    )
    XCTAssertEqual(indexAfter - indexBefore, lapLength)
    let skippedDistance = threeLapRoute.edges[indexBefore..<indexAfter].reduce(0) { $0 + $1.lengthMeters }
    XCTAssertEqual(model.progressFraction, progressBeforeDrop + skippedDistance / threeLapRoute.distanceMeters, accuracy: 0.000_001)
    XCTAssertEqual(model.remainingWholeLapsAhead, 1)
    // The plan itself never changed: dropping a lap moves inside it.
    XCTAssertEqual(planAfterDrop, threeLapRoute.routePlan)
    XCTAssertEqual(model.circuitLaps, 3)

    let coordinateBeforeFinish = model.currentCoordinate
    let progressBeforeFinish = model.progressFraction
    let recordedLaps = model.driveRecord.completedLaps
    let destinationBeforeFinish = model.destination
    ActiveDriveControl.model = model
    defer { ActiveDriveControl.model = nil }
    _ = try await DriveControlIntent(action: .finishLap).perform()
    XCTAssertEqual(model.remainingWholeLapsAhead, 0)
    XCTAssertEqual(model.currentCoordinate, coordinateBeforeFinish)
    XCTAssertEqual(model.destination?.coordinate, destinationBeforeFinish?.coordinate)
    XCTAssertEqual(model.driveRecord.completedLaps, recordedLaps)
    XCTAssertEqual(model.selectedRoute?.routePlan, threeLapRoute.routePlan)
    XCTAssertNil(model.presentationProjection)
    let finishedIndex = try XCTUnwrap(model.runtimeOccurrenceID.flatMap { threeLapRoute.routePlan.occurrence(id: $0)?.index })
    XCTAssertEqual(finishedIndex - indexAfter, lapLength)
    let remainingLapDistance = threeLapRoute.edges[indexAfter..<finishedIndex].reduce(0) { $0 + $1.lengthMeters }
    XCTAssertEqual(model.progressFraction, progressBeforeFinish + remainingLapDistance / threeLapRoute.distanceMeters, accuracy: 0.000_001)

    // Adding one cannot move inside the plan, so it replans the loop with a
    // fourth lap. That plan is the same road up to where the car is, so the
    // drive carries over there on the strict route — but only once the new
    // session has placed the car itself. Until then the current drive keeps
    // taking every fix.
    let added = await model.addOneLap()
    XCTAssertTrue(added, model.failureCode ?? "no failure code")
    XCTAssertTrue(model.isChangingLaps)
    XCTAssertEqual(model.circuitLaps, 3)
    XCTAssertEqual(model.selectedRoute?.routePlan, threeLapRoute.routePlan)
    XCTAssertEqual(model.phase, .expressway)
    XCTAssertNotEqual(model.routeJoinState, .resolving)

    var drivenIndex = finishedIndex
    var fixesBeforeSwap = 0
    var edgeIndex = targetEdgeIndex + 1
    while model.isChangingLaps,
      edgeIndex < threeLapRoute.lapBoundaryOccurrenceIndices[1]
    {
      let start = threeLapRoute.coordinates[edgeIndex]
      let end = threeLapRoute.coordinates[edgeIndex + 1]
      for fraction in [0.25, 0.75] where model.isChangingLaps {
        observationIndex += 1
        nowMilliseconds += 1_000
        let coordinateBeforeFix = model.currentCoordinate
        await model.consumeLiveObservationForTesting(
          Self.liveLocationEnvelope(
            id: "lap.route.\(observationIndex)",
            coordinate: ShutoCoordinate(
              latitude: start.latitude
                + (end.latitude - start.latitude) * fraction,
              longitude: start.longitude
                + (end.longitude - start.longitude) * fraction
            ),
            atMilliseconds: nowMilliseconds,
            courseDegrees: Self.bearing(from: start, to: end),
            speedMetersPerSecond: 18
          )
        )
        if model.isChangingLaps {
          // The current drive took the fix: its plan, its marker.
          fixesBeforeSwap += 1
          XCTAssertNotEqual(model.currentCoordinate, coordinateBeforeFix)
          XCTAssertEqual(model.selectedRoute?.routePlan, threeLapRoute.routePlan)
          let index = try XCTUnwrap(
            model.runtimeOccurrenceID.flatMap {
              threeLapRoute.routePlan.occurrence(id: $0)?.index
            }
          )
          XCTAssertGreaterThanOrEqual(index, drivenIndex)
          drivenIndex = index
        }
      }
      edgeIndex += 1
    }
    XCTAssertFalse(model.isChangingLaps)
    XCTAssertNil(model.failureCode)
    // The new session needs fixes of its own to place the car; the current
    // drive kept guiding on each of them.
    XCTAssertGreaterThan(fixesBeforeSwap, 0)

    XCTAssertEqual(model.circuitLaps, 4)
    let fourLapRoute = try XCTUnwrap(model.selectedRoute)
    XCTAssertNotEqual(fourLapRoute.routePlan, threeLapRoute.routePlan)
    XCTAssertEqual(fourLapRoute.lapBoundaryOccurrenceIndices.count, 5)
    XCTAssertTrue(model.isLiveDrive)
    XCTAssertEqual(model.phase, .expressway)
    XCTAssertEqual(model.runtimeJourneyPhase, .strictRoute)
    XCTAssertNotEqual(model.routeJoinState, .resolving)
    // Still on lap three, where the car is, now with a fourth lap ahead.
    let swappedIndex = try XCTUnwrap(
      model.runtimeOccurrenceID.flatMap {
        fourLapRoute.routePlan.occurrence(id: $0)?.index
      }
    )
    XCTAssertGreaterThanOrEqual(swappedIndex, drivenIndex)
    XCTAssertLessThan(swappedIndex, fourLapRoute.lapBoundaryOccurrenceIndices[3])
    XCTAssertEqual(model.remainingWholeLapsAhead, 1)

    model.reset()
  }

  func testJoinRouteIntentDeclaresOnlyWhereTheJoinIsOffered() async throws {
    var nowMilliseconds = 1_000
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil,
      liveLocationSource: WholeShutoBackgroundNavigationLocationSource(),
      speechOutput: WholeShutoRecordingSpeechOutput(),
      nowMillisecondsProvider: { nowMilliseconds }
    )
    model.selectCurrentOrigin(ShutoCoordinate(latitude: 35.6777, longitude: 139.7708))
    model.selectCircuit(.c1Outer)
    await waitForCircuitPairing(model)
    XCTAssertTrue(model.startCircuitJourney())
    await model.awaitLiveNavigationPreparationForTesting()
    let route = try XCTUnwrap(model.selectedRoute)
    let started = await model.startLiveJourney()
    XCTAssertTrue(started, model.failureCode ?? "no failure code")
    ActiveDriveControl.model = model
    defer { ActiveDriveControl.model = nil }

    // Nothing offered yet: Siri cannot declare what the in-app control
    // would not show.
    _ = try await DriveControlIntent(action: .joinRoute).perform()
    XCTAssertEqual(model.phase, .surfaceAccess)
    XCTAssertEqual(model.routeJoinState, .unavailable)

    let deepEdgeIndex = route.edges.count / 2
    for step in 0..<12 where model.routeJoinState != .offered {
      let index = deepEdgeIndex + step / 2
      let start = route.coordinates[index]
      let end = route.coordinates[index + 1]
      let fraction = step % 2 == 0 ? 0.25 : 0.75
      nowMilliseconds += 1_000
      await model.consumeLiveObservationForTesting(
        Self.liveLocationEnvelope(
          id: "join-intent.\(step)",
          coordinate: ShutoCoordinate(
            latitude: start.latitude + (end.latitude - start.latitude) * fraction,
            longitude: start.longitude + (end.longitude - start.longitude) * fraction),
          atMilliseconds: nowMilliseconds, courseDegrees: Self.bearing(from: start, to: end),
          speedMetersPerSecond: 18))
    }
    XCTAssertEqual(model.routeJoinState, .offered)

    _ = try await DriveControlIntent(action: .joinRoute).perform()
    XCTAssertEqual(model.phase, .entryTransition)
    XCTAssertEqual(model.routeJoinState, .resolving)
    model.reset()
  }

  func testALapThatIsNotAddedAfterAllIsSpokenOnce() async throws {
    var nowMilliseconds = 1_000
    let output = SpeechRecoveryAppOutput()
    output.autoFinish = true
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil,
      liveLocationSource: WholeShutoBackgroundNavigationLocationSource(),
      speechOutput: output,
      nowMillisecondsProvider: { nowMilliseconds },
      languageSelectionProvider: {
        NavigationLanguageSelection(interfaceLocale: .english, guidanceVoiceLocale: .english)
      }
    )
    model.selectCurrentOrigin(ShutoCoordinate(latitude: 35.6777, longitude: 139.7708))
    model.selectCircuit(.c1Outer)
    await waitForCircuitPairing(model)
    model.selectCircuitLaps(2)
    XCTAssertTrue(model.startCircuitJourney())
    for _ in 0..<1_200
    where model.isPreparingLiveNavigation || model.isUpdatingSurfaceRoute
      || !model.canStartLiveNavigation
    {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }
    let started = await model.startLiveJourney()
    XCTAssertTrue(started, model.failureCode ?? "no failure code")
    let route = try XCTUnwrap(model.selectedRoute)
    let occurrences = route.routePlan.occurrences
    let boundaries = route.lapBoundaryOccurrenceIndices
    let lapLength = boundaries[1] - boundaries[0]
    // Where the exit tail leaves the loop. A plan with one more lap drives
    // on around instead, so the two plans are the same road only up to here.
    let parting = try XCTUnwrap(
      occurrences.indices.first {
        $0 >= boundaries[2] && occurrences[$0].entityID != occurrences[$0 - lapLength].entityID
      }
    )
    func drive(_ index: Int, at fraction: Double) async {
      let start = route.coordinates[index]
      let end = route.coordinates[index + 1]
      nowMilliseconds += 1_000
      await model.consumeLiveObservationForTesting(
        Self.liveLocationEnvelope(
          id: "lap-drop.\(nowMilliseconds)",
          coordinate: ShutoCoordinate(
            latitude: start.latitude + (end.latitude - start.latitude) * fraction,
            longitude: start.longitude + (end.longitude - start.longitude) * fraction),
          atMilliseconds: nowMilliseconds, courseDegrees: Self.bearing(from: start, to: end),
          speedMetersPerSecond: 18))
    }
    func engineIndex() -> Int? {
      model.runtimeOccurrenceID.flatMap { route.routePlan.occurrence(id: $0)?.index }
    }
    if let accessEnd = model.accessRoute?.coordinates.last {
      await model.consumeLiveObservationForTesting(
        Self.liveLocationEnvelope(
          id: "lap-drop.access-end", coordinate: accessEnd, atMilliseconds: nowMilliseconds,
          courseDegrees: Self.bearing(from: route.coordinates[0], to: route.coordinates[1])))
    }
    for index in 0..<60 {
      await drive(index, at: 0.25)
      await drive(index, at: 0.75)
    }
    XCTAssertEqual(model.phase, .expressway)
    for _ in 0..<200 where model.remainingWholeLapsAhead == 0 {
      try? await Task.sleep(nanoseconds: 25_000_000)
    }
    // Into the last lap, so the exit tail is close.
    let finished = await model.finishCurrentLap()
    XCTAssertTrue(finished)
    let lastLapIndex = try XCTUnwrap(engineIndex())
    for index in (lastLapIndex + 1)..<(parting - 1) {
      await drive(index, at: 0.25)
      await drive(index, at: 0.75)
    }
    await drive(parting - 1, at: 0.25)
    XCTAssertLessThan(try XCTUnwrap(engineIndex()), parting)

    let added = await model.addOneLap()
    XCTAssertTrue(added, model.failureCode ?? "no failure code")
    func lapNotAddedCount() -> Int {
      output.commands.filter { $0.identity.promptID.contains("lapNotAdded") }.count
    }
    // The car takes the exit before the new session has placed it.
    var index = parting
    while model.isChangingLaps, index < parting + 10 {
      await drive(index, at: 0.5)
      index += 1
    }
    XCTAssertFalse(model.isChangingLaps)
    XCTAssertEqual(model.circuitLaps, 2)
    XCTAssertEqual(model.selectedRoute?.routePlan, route.routePlan)
    XCTAssertEqual(model.failureCode, WholeShutoProductModel.lapChangeUnavailableCode)
    XCTAssertEqual(lapNotAddedCount(), 1)
    XCTAssertEqual(
      output.commands.last { $0.identity.promptID.contains("lapNotAdded") }?.spokenText,
      "The lap could not be added."
    )
    // Once.
    await drive(index, at: 0.5)
    await drive(index + 1, at: 0.5)
    XCTAssertEqual(lapNotAddedCount(), 1)
    model.reset()
  }

  func testLeavingTheRouteWithALapPendingSpeaksOnlyTheRouteNotice() async throws {
    var nowMilliseconds = 1_000
    let output = SpeechRecoveryAppOutput()
    output.autoFinish = true
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil,
      liveLocationSource: WholeShutoBackgroundNavigationLocationSource(),
      speechOutput: output,
      nowMillisecondsProvider: { nowMilliseconds },
      languageSelectionProvider: {
        NavigationLanguageSelection(interfaceLocale: .english, guidanceVoiceLocale: .english)
      }
    )
    model.selectCurrentOrigin(ShutoCoordinate(latitude: 35.6777, longitude: 139.7708))
    model.selectCircuit(.c1Outer)
    await waitForCircuitPairing(model)
    model.selectCircuitLaps(2)
    XCTAssertTrue(model.startCircuitJourney())
    for _ in 0..<1_200
    where model.isPreparingLiveNavigation || model.isUpdatingSurfaceRoute
      || !model.canStartLiveNavigation
    {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }
    let started = await model.startLiveJourney()
    XCTAssertTrue(started, model.failureCode ?? "no failure code")
    let route = try XCTUnwrap(model.selectedRoute)
    let release = try ShutoCircuitProductReleaseBuilder.buildPlannedRouteRelease(
      context: try ShutoPlannedRouteRuntimeCompiler.NetworkContext(database: model.database),
      route: route
    )
    let firstLap = route.lapBoundaryOccurrenceIndices[0]..<route.lapBoundaryOccurrenceIndices[1]
    // A released detour off the first lap, so the drive enters recovery
    // with a rejoin to announce.
    let recovery = try XCTUnwrap(
      release.navigation.bundle.runtimePolicy.recoveryCandidates.first {
        guard let index = route.routePlan.occurrence(id: $0.divergenceOccurrenceID)?.index
        else { return false }
        return firstLap.contains(index) && index > firstLap.lowerBound + 20
      }
    )
    let divergence = try XCTUnwrap(route.routePlan.occurrence(id: recovery.divergenceOccurrenceID))
    let corridorEdges = Dictionary(
      uniqueKeysWithValues: release.navigation.bundle.matcherCorridor.edges.map { ($0.id, $0) }
    )
    func drive(_ edgeID: String, label: String) async throws {
      let edge = try XCTUnwrap(corridorEdges[edgeID])
      let start = try XCTUnwrap(edge.coordinates.first)
      let end = try XCTUnwrap(edge.coordinates.last)
      let startCoordinate = ShutoCoordinate(latitude: start.latitude, longitude: start.longitude)
      let endCoordinate = ShutoCoordinate(latitude: end.latitude, longitude: end.longitude)
      for fraction in Self.oneHertzFractions(from: startCoordinate, to: endCoordinate) {
        nowMilliseconds += 1_000
        await model.consumeLiveObservationForTesting(
          Self.liveLocationEnvelope(
            id: "lap-recovery.\(label).\(fraction)",
            coordinate: Self.interpolate(from: startCoordinate, to: endCoordinate, fraction: fraction),
            atMilliseconds: nowMilliseconds,
            courseDegrees: Self.bearing(from: startCoordinate, to: endCoordinate)))
      }
    }
    if let accessEnd = model.accessRoute?.coordinates.last {
      await model.consumeLiveObservationForTesting(
        Self.liveLocationEnvelope(
          id: "lap-recovery.access-end", coordinate: accessEnd, atMilliseconds: nowMilliseconds,
          courseDegrees: Self.bearing(from: route.coordinates[0], to: route.coordinates[1])))
    }
    for occurrence in release.navigation.bundle.matcherCorridor.occurrences.sorted(by: { $0.index < $1.index })
    where occurrence.index < divergence.index {
      try await drive(occurrence.directedEdgeID, label: "route.\(occurrence.index)")
    }
    XCTAssertEqual(model.phase, .expressway)
    XCTAssertEqual(model.runtimeJourneyPhase, .strictRoute)

    let added = await model.addOneLap()
    XCTAssertTrue(added, model.failureCode ?? "no failure code")
    XCTAssertTrue(model.isChangingLaps)
    for edgeID in recovery.recoveryOccurrenceIDs where model.runtimeRecoveryStatus != .active {
      try await drive(edgeID, label: "detour.\(edgeID)")
    }
    XCTAssertEqual(model.runtimeRecoveryStatus, .active)
    XCTAssertFalse(model.isChangingLaps)
    XCTAssertEqual(model.circuitLaps, 2)
    XCTAssertEqual(model.selectedRoute?.routePlan, route.routePlan)
    // The screen still says the lap was not added; the voice says only
    // what the drive is doing about the route.
    XCTAssertEqual(model.failureCode, WholeShutoProductModel.lapChangeUnavailableCode)
    XCTAssertEqual(
      output.commands.filter { $0.identity.promptID.hasPrefix("journey.rerouting.") }.map(\.spokenText),
      ["Rechecking the route."]
    )
    XCTAssertFalse(output.commands.contains { $0.identity.promptID.contains("lapNotAdded") })
    model.reset()
  }

  func testRouteJoinIsOfferedOnlyWhereTheMatcherHoldsTheRoute() async throws {
    var nowMilliseconds = 1_000
    let history = MemoryDriveHistoryStore()
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil,
      liveLocationSource: WholeShutoBackgroundNavigationLocationSource(),
      speechOutput: WholeShutoRecordingSpeechOutput(),
      nowMillisecondsProvider: { nowMilliseconds },
      driveHistoryStore: history
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6777, longitude: 139.7708)
    )
    model.selectCircuit(.c1Outer)
    await waitForCircuitPairing(model)
    XCTAssertTrue(model.startCircuitJourney())
    for _ in 0..<1_200
    where model.isPreparingLiveNavigation || model.isUpdatingSurfaceRoute
      || !model.canStartLiveNavigation
    {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }
    XCTAssertTrue(
      model.canStartLiveNavigation,
      model.liveNavigationBlockerCode ?? "no blocker code"
    )
    let route = try XCTUnwrap(model.selectedRoute)
    let started = await model.startLiveJourney()
    XCTAssertTrue(started, model.failureCode ?? "no failure code")
    XCTAssertEqual(model.phase, .surfaceAccess)
    XCTAssertEqual(model.routeJoinState, .unavailable)

    // On the ordinary-road approach nothing is offered: the car is where
    // the surface leg expects it.
    let origin = try XCTUnwrap(model.origin?.coordinate)
    for index in 0..<4 {
      nowMilliseconds += 1_000
      await model.consumeLiveObservationForTesting(
        Self.liveLocationEnvelope(
          id: "join.surface.\(index)",
          coordinate: origin,
          atMilliseconds: nowMilliseconds,
          speedMetersPerSecond: 8
        )
      )
    }
    XCTAssertEqual(model.phase, .surfaceAccess)
    XCTAssertEqual(model.routeJoinState, .unavailable)

    // Deep inside the loop, far from the planned ramp, consecutive fixes on
    // one plan edge make the declaration plausible — and only then is it
    // offered, while the phase stays where the surface leg left it.
    var observationIndex = 0
    func driveOnRoute(from edgeIndex: Int, count: Int) async -> Int? {
      var offeredAfter: Int?
      for step in 0..<count {
        let index = edgeIndex + step / 2
        let start = route.coordinates[index]
        let end = route.coordinates[index + 1]
        let fraction = step % 2 == 0 ? 0.25 : 0.75
        observationIndex += 1
        nowMilliseconds += 1_000
        await model.consumeLiveObservationForTesting(
          Self.liveLocationEnvelope(
            id: "join.route.\(observationIndex)",
            coordinate: ShutoCoordinate(
              latitude: start.latitude
                + (end.latitude - start.latitude) * fraction,
              longitude: start.longitude
                + (end.longitude - start.longitude) * fraction
            ),
            atMilliseconds: nowMilliseconds,
            courseDegrees: Self.bearing(from: start, to: end),
            speedMetersPerSecond: 18
          )
        )
        if offeredAfter == nil, model.routeJoinState == .offered {
          offeredAfter = step + 1
        }
      }
      return offeredAfter
    }
    let deepEdgeIndex = route.edges.count / 2
    let offeredAfter = await driveOnRoute(from: deepEdgeIndex, count: 8)
    XCTAssertEqual(model.routeJoinState, .offered)
    XCTAssertGreaterThanOrEqual(
      try XCTUnwrap(offeredAfter),
      RouteJoinOffer.minimumObservationCount
    )
    XCTAssertEqual(model.phase, .surfaceAccess)

    // A fix the matcher cannot place, past the offer's grace, withdraws it.
    nowMilliseconds += RouteJoinOffer.withdrawalGraceMilliseconds + 1_000
    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(
        id: "join.away",
        coordinate: ShutoCoordinate(latitude: 35.75, longitude: 139.90),
        atMilliseconds: nowMilliseconds,
        speedMetersPerSecond: 18
      )
    )
    XCTAssertEqual(model.routeJoinState, .unavailable)

    _ = await driveOnRoute(from: deepEdgeIndex + 4, count: 8)
    XCTAssertEqual(model.routeJoinState, .offered)

    // Declaring from the surface leg ends it; the join then needs the
    // matcher's own run before the drive is on the expressway.
    let declared = await model.declareAlreadyOnRoute()
    XCTAssertTrue(declared)
    XCTAssertEqual(model.phase, .entryTransition)
    XCTAssertEqual(model.routeJoinState, .resolving)
    XCTAssertNil(model.runtimeOccurrenceID)

    var joinEdgeIndex = deepEdgeIndex + 8
    for _ in 0..<5 where model.phase != .expressway {
      _ = await driveOnRoute(from: joinEdgeIndex, count: 6)
      joinEdgeIndex += 3
    }
    XCTAssertEqual(model.phase, .expressway)
    XCTAssertEqual(model.routeJoinState, .unavailable)
    let joinedOccurrenceID = try XCTUnwrap(model.runtimeOccurrenceID)
    let joinedIndex = try XCTUnwrap(
      route.routePlan.occurrence(id: joinedOccurrenceID)?.index
    )
    XCTAssertGreaterThan(joinedIndex, 0)
    XCTAssertGreaterThan(model.progressFraction, 0)

    // The join proves where the car is, not where it entered: no entrance,
    // no band, only the cap — until the driver names one of the entrances
    // whose ramp lands on the plan ahead of the join.
    XCTAssertTrue(model.entryIsUnconfirmed)
    XCTAssertNil(model.driveEntryFacility)
    XCTAssertNil(model.selectedTariffBand)
    let candidates = model.declarableEntryCandidates
    XCTAssertFalse(candidates.isEmpty)
    let upstreamEdgeIDs = Set(route.edges.prefix(joinedIndex).map(\.edgeID))
    for candidate in candidates {
      XCTAssertTrue(candidate.canEnter)
      XCTAssertTrue(
        candidate.entryEdgeCandidates.contains {
          upstreamEdgeIDs.contains($0.edgeID)
        },
        candidate.facilityID
      )
    }
    XCTAssertTrue(
      candidates.contains { $0.facilityID == route.entryFacility.facilityID }
    )
    let offCourse = try XCTUnwrap(
      model.database.directionalFacilities.first {
        $0.canEnter && $0.routeID == "K1"
      }
    )
    model.declareEntry(facilityID: offCourse.facilityID)
    XCTAssertTrue(model.entryIsUnconfirmed)

    // The band follows the declaration. A declarable entrance's ramp lies
    // on the plan. 銀座, the exit's own IC, was offered here only while it
    // was also bound to 京橋's entrance ramp, where this drive starts; none
    // of the entrances offered now shares the exit's toll point.
    let exit = try XCTUnwrap(route.exitFacility)
    XCTAssertFalse(
      candidates.contains { ShutoRoutePlanner.sharesTollPoint($0, exit) }
    )

    let namedEntry = try XCTUnwrap(
      candidates.first { !ShutoRoutePlanner.sharesTollPoint($0, exit) }
    )
    model.declareEntry(facilityID: namedEntry.facilityID)
    XCTAssertFalse(model.entryIsUnconfirmed)
    XCTAssertEqual(model.driveEntryFacility?.facilityID, namedEntry.facilityID)
    XCTAssertNotNil(model.selectedTariffBand)
    XCTAssertEqual(
      model.selectedTariffBand,
      try model.planner.tariffBand(
        entryFacilityID: namedEntry.facilityID,
        exitFacilityID: exit.facilityID,
        evidence: model.activeTariffEvidence
      )
    )

    model.reset()
    let record = try XCTUnwrap(history.load().first)
    XCTAssertTrue(record.routeName.contains(namedEntry.nameJA + " → "))
    XCTAssertFalse(record.routeName.contains("入口未確認"))
  }

  func testDeclaredJoinLeavesTheEntranceUnconfirmedInTheDriveRecord() async throws {
    var nowMilliseconds = 1_000
    let history = MemoryDriveHistoryStore()
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil,
      liveLocationSource: WholeShutoBackgroundNavigationLocationSource(),
      speechOutput: WholeShutoRecordingSpeechOutput(),
      nowMillisecondsProvider: { nowMilliseconds },
      driveHistoryStore: history
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6777, longitude: 139.7708)
    )
    model.selectCircuit(.c1Outer)
    await waitForCircuitPairing(model)
    XCTAssertTrue(model.startCircuitJourney())
    for _ in 0..<1_200
    where model.isPreparingLiveNavigation || model.isUpdatingSurfaceRoute
      || !model.canStartLiveNavigation
    {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }
    let route = try XCTUnwrap(model.selectedRoute)
    let started = await model.startLiveJourney()
    XCTAssertTrue(started, model.failureCode ?? "no failure code")

    var observationIndex = 0
    func driveOnRoute(from edgeIndex: Int, count: Int) async {
      for step in 0..<count {
        let index = edgeIndex + step / 2
        let start = route.coordinates[index]
        let end = route.coordinates[index + 1]
        let fraction = step % 2 == 0 ? 0.25 : 0.75
        observationIndex += 1
        nowMilliseconds += 1_000
        await model.consumeLiveObservationForTesting(
          Self.liveLocationEnvelope(
            id: "unconfirmed.\(observationIndex)",
            coordinate: ShutoCoordinate(
              latitude: start.latitude
                + (end.latitude - start.latitude) * fraction,
              longitude: start.longitude
                + (end.longitude - start.longitude) * fraction
            ),
            atMilliseconds: nowMilliseconds,
            courseDegrees: Self.bearing(from: start, to: end),
            speedMetersPerSecond: 18
          )
        )
      }
    }
    var edgeIndex = route.edges.count / 2
    for _ in 0..<6 where model.routeJoinState != .offered {
      await driveOnRoute(from: edgeIndex, count: 4)
      edgeIndex += 2
    }
    let declared = await model.declareAlreadyOnRoute()
    XCTAssertTrue(declared)
    for _ in 0..<6 where model.phase != .expressway {
      await driveOnRoute(from: edgeIndex, count: 6)
      edgeIndex += 3
    }
    XCTAssertEqual(model.phase, .expressway)
    XCTAssertTrue(model.entryIsUnconfirmed)

    // Ending the drive without naming the entrance records it as unknown
    // rather than as the planned entrance the car never used.
    model.reset()
    let record = try XCTUnwrap(history.load().first)
    XCTAssertTrue(record.routeName.contains("入口未確認 → "))
    XCTAssertFalse(record.routeName.contains(route.entryFacility.nameJA + " → "))
  }

  func testLongSurfaceAccessCanReachReleasedCircuitNavigation() async throws {
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6979, longitude: 139.4139)
    )
    model.selectCircuit(.c1Outer)
    await waitForCircuitPairing(model)

    let distance = try XCTUnwrap(model.circuitEntranceDistanceMeters)
    XCTAssertEqual(
      ShutoEntranceAccessTier.classify(distanceMeters: distance),
      .extended
    )
    XCTAssertNotNil(model.circuitEntryFacilityID)
    XCTAssertNotNil(model.circuitExitFacilityID)
    XCTAssertTrue(model.startCircuitJourney())
    await model.awaitLiveNavigationPreparationForTesting()

    XCTAssertEqual(model.phase, .review)
    XCTAssertNotNil(model.accessRoute)
    XCTAssertNotNil(model.egressRoute)
    XCTAssertTrue(model.canStartLiveNavigation)
    XCTAssertNil(model.liveNavigationBlockerCode)
  }

  func testWanganDaikokuRunAdmitsBundledForegroundNavigation() async throws {
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    let expected = try ShutoCircuitProductReleaseBuilder.plannedWanganRoute(
      database: model.database
    )

    let releasedEntrance = try XCTUnwrap(
      model.database.directionalFacilities.first {
        $0.facilityID
          == ShutoCircuitProductReleaseBuilder.wanganEntryFacilityID
      }
    )
    model.selectCurrentOrigin(releasedEntrance.coordinate)
    model.selectCircuit(.wanganDaikokuRun)
    await waitForCircuitPairing(model)

    XCTAssertEqual(
      model.circuitEntryFacilityID,
      ShutoCircuitProductReleaseBuilder.wanganEntryFacilityID
    )
    XCTAssertEqual(
      model.circuitExitFacilityID,
      nil
    )
    XCTAssertTrue(model.startCircuitJourney())
    await waitForLiveNavigationPreparation(model)
    XCTAssertEqual(model.selectedRoute?.routePlan, expected.routePlan)
    XCTAssertTrue(model.canStartLiveNavigation)
    XCTAssertNil(model.liveNavigationBlockerCode)
  }

  /// A C1 outer loop that returns to its origin, driven until the car takes
  /// an exit the plan does not. Returns the model on the expressway road just
  /// before that exit, with the exit's own road and a way off it.
  private func driveC1OuterToAnUnplannedExit(
    ending: WholeShutoJourneyEnding,
    exitFartherThanMeters minimumExitMeters: Double = 0,
    store: WholeShutoMemoryCheckpointStore,
    output: SpeechRecoveryAppOutput,
    history: MemoryDriveHistoryStore,
    clock: @escaping () -> Int,
    advance: @escaping () -> Void
  ) async throws -> (
    model: WholeShutoProductModel,
    drive: (ShutoCoordinate, ShutoCoordinate) async -> Void,
    rampEnd: ShutoCoordinate,
    heading: Double
  ) {
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: store,
      liveLocationSource: WholeShutoBackgroundNavigationLocationSource(),
      speechOutput: output,
      nowMillisecondsProvider: clock,
      languageSelectionProvider: {
        NavigationLanguageSelection(interfaceLocale: .english, guidanceVoiceLocale: .english)
      },
      driveHistoryStore: history
    )
    model.selectCurrentOrigin(ShutoCoordinate(latitude: 35.6777, longitude: 139.7708))
    model.selectCircuit(.c1Outer)
    await waitForCircuitPairing(model)
    XCTAssertTrue(model.startCircuitJourney())
    await waitForLiveNavigationPreparation(model)
    if ending == .exit {
      model.selectJourneyEnding(.exit)
      await waitForLiveNavigationPreparation(model)
    }
    let route = try XCTUnwrap(model.selectedRoute)
    let database = model.database
    let edges = Dictionary(uniqueKeysWithValues: database.edges.map { ($0.edgeID, $0) })
    let outgoing = Dictionary(grouping: database.edges, by: \.fromNodeID)
    let nodes = Dictionary(uniqueKeysWithValues: database.nodes.map { ($0.nodeID, $0.coordinate) })
    let exitEdges = Set(
      database.directionalFacilities.filter(\.canExit).flatMap { $0.exitEdgeCandidates.map(\.edgeID) }
    )
    // The last choice of road before the plan's end whose other road leads,
    // without a further choice, to an exit the plan does not take.
    func exitPath(from edge: ShutoNetworkDatabase.Edge) -> [ShutoNetworkDatabase.Edge]? {
      var path = [edge]
      while path.count < 60 {
        if exitEdges.contains(path[path.count - 1].edgeID) { return path }
        let next = (outgoing[path[path.count - 1].toNodeID] ?? []).filter {
          $0.toNodeID != path[path.count - 1].fromNodeID
        }
        guard next.count == 1 else { return nil }
        path.append(next[0])
      }
      return nil
    }
    let plannedEnd = route.destinationCoordinate
    var found: (index: Int, path: [ShutoNetworkDatabase.Edge])?
    for index in stride(from: route.edges.count - 2, through: 40, by: -1) where found == nil {
      for alternative in (outgoing[route.edges[index].toNodeID] ?? [])
      where alternative.edgeID != route.edges[index + 1].edgeID
        && alternative.toNodeID != route.edges[index].fromNodeID
      {
        if let path = exitPath(from: alternative),
          let end = nodes[path[path.count - 1].toNodeID],
          Self.meters(end, plannedEnd) > minimumExitMeters
        {
          found = (index, path)
          break
        }
      }
    }
    let (divergence, exitRoad) = try XCTUnwrap(found)

    let started = await model.startLiveJourney()
    XCTAssertTrue(started, model.failureCode ?? "no failure code")
    var observationIndex = 0
    func drive(from start: ShutoCoordinate, to end: ShutoCoordinate) async {
      for fraction in Self.oneHertzFractions(from: start, to: end)
      where model.phase != .completed {
        observationIndex += 1
        advance()
        await model.consumeLiveObservationForTesting(
          Self.liveLocationEnvelope(
            id: "unplanned-exit.\(observationIndex)",
            coordinate: Self.interpolate(from: start, to: end, fraction: fraction),
            atMilliseconds: clock(),
            courseDegrees: Self.bearing(from: start, to: end),
            speedMetersPerSecond: 15
          )
        )
      }
    }
    // Join the loop a little before the exit, then take it.
    for edge in route.edges[(divergence - 30)...divergence] {
      await drive(from: nodes[edge.fromNodeID]!, to: nodes[edge.toNodeID]!)
      if model.phase == .surfaceAccess, model.routeJoinState == .offered {
        let declared = await model.declareAlreadyOnRoute()
        XCTAssertTrue(declared)
      }
    }
    XCTAssertEqual(model.phase, .expressway)
    for edge in exitRoad {
      await drive(from: nodes[edge.fromNodeID]!, to: nodes[edge.toNodeID]!)
    }
    let last = exitRoad[exitRoad.count - 1]
    let rampEnd = nodes[last.toNodeID]!
    return (
      model, { await drive(from: $0, to: $1) }, rampEnd,
      Self.bearing(from: nodes[last.fromNodeID]!, to: rampEnd) * .pi / 180
    )
  }

  private static func meters(_ a: ShutoCoordinate, _ b: ShutoCoordinate) -> Double {
    let metersPerDegree = 6_371_000.0 * .pi / 180
    return hypot(
      (a.longitude - b.longitude) * metersPerDegree * cos(a.latitude * .pi / 180),
      (a.latitude - b.latitude) * metersPerDegree
    )
  }

  /// Off the end of the exit ramp, straight on 100 m and then turned away
  /// from the plan, until the session hands over or `meters` run out.
  private func driveAwayFromThePlan(
    _ model: WholeShutoProductModel,
    from rampEnd: ShutoCoordinate,
    heading: Double,
    meters: Double,
    drive: (ShutoCoordinate, ShutoCoordinate) async -> Void
  ) async {
    let metersPerDegree = 6_371_000.0 * .pi / 180
    let scale = cos(rampEnd.latitude * .pi / 180)
    func offset(_ from: ShutoCoordinate, _ bearing: Double, _ distance: Double) -> ShutoCoordinate {
      ShutoCoordinate(
        latitude: from.latitude + cos(bearing) * distance / metersPerDegree,
        longitude: from.longitude + sin(bearing) * distance / (metersPerDegree * scale)
      )
    }
    let straight = offset(rampEnd, heading, 100)
    let candidates = [heading + .pi / 2, heading - .pi / 2].map { offset(straight, $0, meters) }
    let plan = model.selectedRoute?.coordinates ?? []
    func nearest(_ point: ShutoCoordinate) -> Double {
      plan.map { Self.meters($0, point) }.min() ?? .infinity
    }
    let away = candidates.max { nearest($0) < nearest($1) }!
    await drive(rampEnd, straight)
    await drive(straight, away)
  }

  func testLeavingTheExpresswayHandsOverToOrdinaryRoadsAndArrives() async throws {
    var nowMilliseconds = 1_000
    let output = SpeechRecoveryAppOutput()
    output.autoFinish = true
    let history = MemoryDriveHistoryStore()
    let store = WholeShutoMemoryCheckpointStore()
    let (model, drive, rampEnd, heading) = try await driveC1OuterToAnUnplannedExit(
      ending: .returnToOrigin, store: store, output: output, history: history,
      clock: { nowMilliseconds }, advance: { nowMilliseconds += 1_000 }
    )
    XCTAssertTrue(model.requiresSurfaceEgress)
    await driveAwayFromThePlan(model, from: rampEnd, heading: heading, meters: 600, drive: drive)
    XCTAssertTrue(model.leftRouteAtUnplannedExit)
    XCTAssertEqual(model.phase, .surfaceEgress)
    let leftRoute = output.commands.filter { $0.identity.promptID.contains("leftRouteRerouting") }
    XCTAssertEqual(leftRoute.map(\.spokenText), ["You've left the route. Rerouting."])
    for _ in 0..<200 where model.egressRoute == nil {
      try? await Task.sleep(nanoseconds: 25_000_000)
    }
    let egress = try XCTUnwrap(model.egressRoute)
    XCTAssertEqual(
      try XCTUnwrap(egress.coordinates.last),
      try XCTUnwrap(model.destination?.coordinate)
    )

    // Relaunched here, the drive comes back on its ordinary-road leg with
    // the expressway session ended.
    await model.handleScenePhase(.background)
    let restoredOutput = SpeechRecoveryAppOutput()
    restoredOutput.autoFinish = true
    let restored = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: store,
      liveLocationSource: WholeShutoBackgroundNavigationLocationSource(),
      speechOutput: restoredOutput,
      nowMillisecondsProvider: { nowMilliseconds },
      languageSelectionProvider: {
        NavigationLanguageSelection(interfaceLocale: .english, guidanceVoiceLocale: .english)
      },
      driveHistoryStore: history
    )
    model.reset()
    XCTAssertTrue(restored.restoredFromCheckpoint)
    XCTAssertEqual(restored.phase, .surfaceEgress)
    XCTAssertTrue(restored.leftRouteAtUnplannedExit)
    await waitForLiveNavigationPreparation(restored)
    let resumed = await restored.resumeLiveJourney()
    XCTAssertTrue(resumed, restored.failureCode ?? "no failure code")
    var observationIndex = 0
    for (start, end) in zip(egress.coordinates, egress.coordinates.dropFirst())
    where restored.phase != .completed {
      for fraction in Self.oneHertzFractions(from: start, to: end) where restored.phase != .completed {
        observationIndex += 1
        nowMilliseconds += 1_000
        await restored.consumeLiveObservationForTesting(
          Self.liveLocationEnvelope(
            id: "unplanned-exit.surface.\(observationIndex)",
            coordinate: Self.interpolate(from: start, to: end, fraction: fraction),
            atMilliseconds: nowMilliseconds,
            courseDegrees: Self.bearing(from: start, to: end),
            speedMetersPerSecond: 10
          )
        )
      }
    }
    // At the destination itself.
    if restored.phase != .completed, let end = egress.coordinates.last {
      nowMilliseconds += 1_000
      await restored.consumeLiveObservationForTesting(
        Self.liveLocationEnvelope(
          id: "unplanned-exit.surface.arrival",
          coordinate: end,
          atMilliseconds: nowMilliseconds,
          speedMetersPerSecond: 2
        )
      )
    }
    XCTAssertEqual(restored.phase, .completed)
    XCTAssertFalse(restored.endedOffRoute)
    XCTAssertFalse(restored.endedNearDestination)
    XCTAssertFalse(restoredOutput.commands.contains { $0.identity.promptID.contains("leftRoute") })
    restored.reset()
    let record = try XCTUnwrap(history.load().first)
    XCTAssertTrue(record.arrived)
  }

  func testLeavingAnExitOnlyDriveFarFromItsExitEndsGuidance() async throws {
    var nowMilliseconds = 1_000
    let output = SpeechRecoveryAppOutput()
    output.autoFinish = true
    let history = MemoryDriveHistoryStore()
    let (model, drive, rampEnd, heading) = try await driveC1OuterToAnUnplannedExit(
      ending: .exit, exitFartherThanMeters: 1_500,
      store: WholeShutoMemoryCheckpointStore(), output: output, history: history,
      clock: { nowMilliseconds }, advance: { nowMilliseconds += 1_000 }
    )
    XCTAssertFalse(model.requiresSurfaceEgress)
    await driveAwayFromThePlan(model, from: rampEnd, heading: heading, meters: 600, drive: drive)
    XCTAssertEqual(model.phase, .completed)
    XCTAssertTrue(model.endedOffRoute)
    XCTAssertFalse(model.endedNearDestination)
    let ended = output.commands.filter { $0.identity.promptID.contains("leftRouteEnded") }
    XCTAssertEqual(ended.map(\.spokenText), ["You've left the route. Guidance has ended."])
    model.reset()
    let record = try XCTUnwrap(history.load().first)
    XCTAssertFalse(record.arrived)
  }

  // Finish is offered within 150 m of the route end on admitted progress,
  // which can still be short of the terminal occurrence; pressing it there
  // must still let the drive complete, with or without a surface leg.
  func testFinishPressedShortOfTheTerminalOccurrenceCompletesTheDrive() async throws {
    for ending in [WholeShutoJourneyEnding.exit, .returnToOrigin] {
      var nowMilliseconds = 1_000
      let output = SpeechRecoveryAppOutput()
      output.autoFinish = true
      let model = WholeShutoForegroundReleaseFactory.makeModel(
        surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
        checkpointStore: WholeShutoMemoryCheckpointStore(),
        liveLocationSource: WholeShutoBackgroundNavigationLocationSource(),
        speechOutput: output,
        nowMillisecondsProvider: { nowMilliseconds },
        languageSelectionProvider: {
          NavigationLanguageSelection(interfaceLocale: .english, guidanceVoiceLocale: .english)
        },
        driveHistoryStore: MemoryDriveHistoryStore()
      )
      model.selectCurrentOrigin(ShutoCoordinate(latitude: 35.6777, longitude: 139.7708))
      model.selectCircuit(.c1Outer)
      await waitForCircuitPairing(model)
      XCTAssertTrue(model.startCircuitJourney())
      await waitForLiveNavigationPreparation(model)
      if ending == .exit {
        model.selectJourneyEnding(.exit)
        await waitForLiveNavigationPreparation(model)
      }
      let route = try XCTUnwrap(model.selectedRoute)
      let nodes = Dictionary(uniqueKeysWithValues: model.database.nodes.map { ($0.nodeID, $0.coordinate) })
      let terminalEdgeID = try XCTUnwrap(route.edges.last?.edgeID)
      let started = await model.startLiveJourney()
      XCTAssertTrue(started, model.failureCode ?? "no failure code")
      var index = 0
      var pressed = false
      var lastPosition: ShutoCoordinate?
      var heading = 0.0
      edges: for edge in route.edges[(route.edges.count - 40)...] {
        let start = nodes[edge.fromNodeID]!, end = nodes[edge.toNodeID]!
        for fraction in Self.oneHertzFractions(from: start, to: end) {
          index += 1
          nowMilliseconds += 1_000
          let coordinate = Self.interpolate(from: start, to: end, fraction: fraction)
          heading = Self.bearing(from: start, to: end)
          lastPosition = coordinate
          await model.consumeLiveObservationForTesting(
            Self.liveLocationEnvelope(
              id: "finish.\(index)", coordinate: coordinate, atMilliseconds: nowMilliseconds,
              courseDegrees: heading, speedMetersPerSecond: 15
            )
          )
          if model.phase == .surfaceAccess, model.routeJoinState == .offered {
            _ = await model.declareAlreadyOnRoute()
          }
          let onTerminal = model.runtimeOccurrenceID?.hasSuffix(terminalEdgeID) == true
          if model.canFinishLiveExpressway, !onTerminal {
            let finished = await model.finishLiveExpressway()
            XCTAssertTrue(finished, "\(ending): \(model.failureCode ?? "no failure code")")
            pressed = true
            break edges
          }
        }
      }
      XCTAssertTrue(pressed, "Finish never offered short of the terminal occurrence (\(ending))")
      guard pressed, let from = lastPosition else { continue }
      // Keep driving along the same heading, off the end of the route.
      let metersPerDegree = 6_371_000.0 * .pi / 180
      for step in 1...5 where model.phase != .completed {
        nowMilliseconds += 1_000
        let distance = Double(step) * 15
        let coordinate = ShutoCoordinate(
          latitude: from.latitude + cos(heading * .pi / 180) * distance / metersPerDegree,
          longitude: from.longitude + sin(heading * .pi / 180) * distance / (metersPerDegree * cos(from.latitude * .pi / 180))
        )
        await model.consumeLiveObservationForTesting(
          Self.liveLocationEnvelope(
            id: "finish.after.\(step)", coordinate: coordinate, atMilliseconds: nowMilliseconds,
            courseDegrees: heading, speedMetersPerSecond: 15
          )
        )
      }
      if ending == .returnToOrigin {
        XCTAssertEqual(model.phase, .surfaceEgress)
        let egress = try XCTUnwrap(model.egressRoute)
        var surface = 0
        for (start, end) in zip(egress.coordinates, egress.coordinates.dropFirst()) where model.phase == .surfaceEgress {
          for fraction in Self.oneHertzFractions(from: start, to: end) where model.phase == .surfaceEgress {
            surface += 1
            nowMilliseconds += 1_000
            await model.consumeLiveObservationForTesting(
              Self.liveLocationEnvelope(
                id: "finish.surface.\(surface)", coordinate: Self.interpolate(from: start, to: end, fraction: fraction),
                atMilliseconds: nowMilliseconds, courseDegrees: Self.bearing(from: start, to: end), speedMetersPerSecond: 10
              )
            )
          }
        }
        for step in 1...3 where model.phase != .completed {
          nowMilliseconds += 1_000
          await model.consumeLiveObservationForTesting(
            Self.liveLocationEnvelope(
              id: "finish.arrived.\(step)", coordinate: egress.coordinates.last!,
              atMilliseconds: nowMilliseconds, speedMetersPerSecond: 2
            )
          )
        }
      }
      XCTAssertEqual(model.phase, .completed, "\(ending)")
      XCTAssertEqual(model.runtimeJourneyPhase, .completed, "\(ending)")
      XCTAssertNil(model.failureCode, "\(ending)")
      model.reset()
    }
  }

  func testPassingDaikokuPAEndsTheDriveNearTheDestination() async throws {
    var nowMilliseconds = 1_000
    let output = SpeechRecoveryAppOutput()
    output.autoFinish = true
    let history = MemoryDriveHistoryStore()
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil,
      liveLocationSource: WholeShutoBackgroundNavigationLocationSource(),
      speechOutput: output,
      nowMillisecondsProvider: { nowMilliseconds },
      languageSelectionProvider: {
        NavigationLanguageSelection(interfaceLocale: .english, guidanceVoiceLocale: .english)
      },
      driveHistoryStore: history
    )
    let entrance = try XCTUnwrap(
      model.database.directionalFacilities.first {
        $0.facilityID
          == ShutoCircuitProductReleaseBuilder.wanganEntryFacilityID
      }
    )
    model.selectCurrentOrigin(entrance.coordinate)
    model.selectCircuit(.wanganDaikokuRun)
    await waitForCircuitPairing(model)
    XCTAssertTrue(model.startCircuitJourney())
    await waitForLiveNavigationPreparation(model)
    let route = try XCTUnwrap(model.selectedRoute)

    // The plan's last choice before the PA: where its ramp leaves the road
    // to the Daikoku-futou exit.
    let edges = Dictionary(
      uniqueKeysWithValues: model.database.edges.map { ($0.edgeID, $0) }
    )
    let outgoing = Dictionary(grouping: model.database.edges, by: \.fromNodeID)
    func waysOn(_ edge: ShutoNetworkDatabase.Edge) -> [ShutoNetworkDatabase.Edge] {
      (outgoing[edge.toNodeID] ?? []).filter { $0.toNodeID != edge.fromNodeID }
    }
    let visitStart = try XCTUnwrap(
      route.routePlan.occurrences.firstIndex { $0.kind == .paVisit }
    )
    let divergence = try XCTUnwrap(
      (0..<(visitStart - 1)).last { index in
        waysOn(route.edges[index]).contains { $0.edgeID != route.edges[index + 1].edgeID }
      }
    )
    var passing = waysOn(route.edges[divergence]).filter {
      $0.edgeID != route.edges[divergence + 1].edgeID
    }
    XCTAssertEqual(passing.count, 1)
    while passing.count < 26, let next = waysOn(passing[passing.count - 1]).only {
      passing.append(next)
    }

    let started = await model.startLiveJourney()
    XCTAssertTrue(started, model.failureCode ?? "no failure code")
    let nodes = Dictionary(
      uniqueKeysWithValues: model.database.nodes.map { ($0.nodeID, $0.coordinate) }
    )
    var sawUnavailableRecovery = false
    var observationIndex = 0
    func drive(_ edgeID: String) async throws {
      let edge = try XCTUnwrap(edges[edgeID])
      let start = try XCTUnwrap(nodes[edge.fromNodeID])
      let end = try XCTUnwrap(nodes[edge.toNodeID])
      for fraction in Self.oneHertzFractions(from: start, to: end) {
        observationIndex += 1
        nowMilliseconds += 1_000
        await model.consumeLiveObservationForTesting(
          Self.liveLocationEnvelope(
            id: "past-pa.\(observationIndex)",
            coordinate: Self.interpolate(from: start, to: end, fraction: fraction),
            atMilliseconds: nowMilliseconds,
            courseDegrees: Self.bearing(from: start, to: end),
            speedMetersPerSecond: 20
          )
        )
        if model.runtimeRecoveryStatus == .unavailable { sawUnavailableRecovery = true }
      }
    }
    // Join the run a little before Daikoku, then stay on the road past the
    // PA's entry ramp.
    for edge in route.edges[(divergence - 40)...divergence] {
      try await drive(edge.edgeID)
      if model.phase == .surfaceAccess, model.routeJoinState == .offered {
        let declared = await model.declareAlreadyOnRoute()
        XCTAssertTrue(declared)
      }
    }
    XCTAssertEqual(model.phase, .expressway)
    XCTAssertEqual(model.runtimeJourneyPhase, .strictRoute)
    for edge in passing where model.phase != .completed {
      try await drive(edge.edgeID)
    }
    // Fixes after the end change nothing.
    try await drive(passing[passing.count - 1].edgeID)

    XCTAssertEqual(model.phase, .completed)
    XCTAssertTrue(model.endedNearDestination)
    XCTAssertFalse(sawUnavailableRecovery)
    let nearDestination = output.commands.filter {
      $0.identity.promptID.contains("nearDestination")
    }
    XCTAssertEqual(
      nearDestination.map(\.spokenText),
      ["You're near your destination. Guidance has ended."]
    )
    XCTAssertFalse(output.commands.contains { $0.identity.promptID.contains("arrived") })
    model.reset()
    let record = try XCTUnwrap(history.load().first)
    XCTAssertFalse(record.arrived)
    XCTAssertEqual(record.endedNearDestination, true)
  }

  func testC2InnerCircuitAdmitsBundledForegroundNavigation() async throws {
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    let expected = try ShutoCircuitProductReleaseBuilder.plannedC2Route(
      database: model.database
    )

    let releasedEntrance = try XCTUnwrap(
      model.database.directionalFacilities.first {
        $0.facilityID == ShutoCircuitProductReleaseBuilder.c2EntryFacilityID
      }
    )
    model.selectCurrentOrigin(releasedEntrance.coordinate)
    model.selectCircuit(.c2InnerWithBayshore)
    await waitForCircuitPairing(model)
    // The bundled release is a fixed product route, not a promise about the
    // default recommendation: from its own ramp the return trip now
    // recommends 滝野川, nearer the minimum band. Choosing its entrance
    // derives exactly its pairing.
    model.selectCircuitEntrance(
      facilityID: ShutoCircuitProductReleaseBuilder.c2EntryFacilityID
    )
    await waitForCircuitPairing(model)

    XCTAssertEqual(
      model.circuitEntryFacilityID,
      ShutoCircuitProductReleaseBuilder.c2EntryFacilityID
    )
    XCTAssertEqual(
      model.circuitExitFacilityID,
      ShutoCircuitProductReleaseBuilder.c2ExitFacilityID
    )
    XCTAssertTrue(model.startCircuitJourney())
    await waitForLiveNavigationPreparation(model)
    XCTAssertEqual(model.selectedRoute?.routePlan, expected.routePlan)
    XCTAssertTrue(model.canStartLiveNavigation)
    XCTAssertNil(model.liveNavigationBlockerCode)
  }

  func testDaikokuYokohamaCircuitAdmitsBundledForegroundNavigation()
    async throws
  {
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    let expected =
      try ShutoCircuitProductReleaseBuilder
      .plannedDaikokuRoute(database: model.database)

    // Wangan-Kanpachi was no candidate while the graph still turned the
    // Daishi exit back onto the expressway across Daishi-dori; with that
    // chain cut, the release's own entrance is the recommendation.
    model.selectCurrentOrigin(expected.entryFacility.coordinate)
    model.selectCircuit(.daikokuYokohamaLoop)
    await waitForCircuitPairing(model)

    XCTAssertEqual(
      model.circuitEntryFacilityID,
      ShutoCircuitProductReleaseBuilder.daikokuEntryFacilityID
    )
    XCTAssertNil(model.circuitExitFacilityID)
    XCTAssertTrue(model.startCircuitJourney())
    await waitForLiveNavigationPreparation(model)
    XCTAssertEqual(model.selectedRoute?.routePlan, expected.routePlan)
    XCTAssertTrue(model.canStartLiveNavigation)
    XCTAssertNil(model.liveNavigationBlockerCode)
  }

  func testScenicGrandTourAdmitsBundledForegroundNavigation()
    async throws
  {
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    let expected =
      try ShutoCircuitProductReleaseBuilder
      .plannedScenicRoute(database: model.database)

    model.selectCurrentOrigin(expected.entryFacility.coordinate)
    model.selectCircuit(.scenicGrandTour)
    await waitForCircuitPairing(model)

    XCTAssertEqual(
      model.circuitEntryFacilityID,
      ShutoCircuitProductReleaseBuilder.scenicEntryFacilityID
    )
    XCTAssertEqual(
      model.circuitExitFacilityID,
      nil
    )
    XCTAssertTrue(model.startCircuitJourney())
    await waitForLiveNavigationPreparation(model)
    XCTAssertEqual(model.selectedRoute?.routePlan, expected.routePlan)
    XCTAssertTrue(model.canStartLiveNavigation)
    XCTAssertNil(model.liveNavigationBlockerCode)
  }

  func testExactCustomRouteWithCompleteGuidanceAdmitsOnDeviceNavigation()
    async throws
  {
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6812, longitude: 139.7671)
    )
    model.prepareCustomRouteDraft()
    model.selectCustomEntry(facilityID: "shuto.ic.b.urayasu")
    model.selectCustomExit(facilityID: "shuto.ic.9.fukudumi")

    XCTAssertTrue(model.applyCustomRoute())
    for _ in 0..<300
    where model.isPreparingLiveNavigation || model.isUpdatingSurfaceRoute {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }

    XCTAssertEqual(
      model.selectedRoute?.routePlan.entryFacilityID,
      "shuto.ic.b.urayasu"
    )
    XCTAssertEqual(
      model.selectedRoute?.routePlan.exitFacilityID,
      "shuto.ic.9.fukudumi"
    )
    XCTAssertFalse(model.isPreparingLiveNavigation)
    XCTAssertTrue(model.canStartLiveNavigation)
    XCTAssertNil(model.liveNavigationBlockerCode)
  }

  func testShibuyaToGinzaCustomRouteAdmitsOnDeviceNavigation()
    async throws
  {
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6580, longitude: 139.7016)
    )
    model.prepareCustomRouteDraft()
    model.selectCustomEntry(facilityID: "shuto.ic.3.shibuya")
    model.selectCustomExit(facilityID: "shuto.ic.c1.ginza")

    XCTAssertTrue(model.applyCustomRoute())
    for _ in 0..<300
    where model.isPreparingLiveNavigation || model.isUpdatingSurfaceRoute {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }

    XCTAssertEqual(
      model.selectedRoute?.routePlan.entryFacilityID,
      "shuto.ic.3.shibuya"
    )
    XCTAssertEqual(
      model.selectedRoute?.routePlan.exitFacilityID,
      "shuto.ic.c1.ginza"
    )
    XCTAssertFalse(model.isPreparingLiveNavigation)
    XCTAssertTrue(model.canStartLiveNavigation)
    XCTAssertNil(model.liveNavigationBlockerCode)
  }

  func testRoute2And5RadialPairsAdmitOnDeviceNavigation()
    async throws
  {
    let pairs = [
      ("shuto.ic.2.meguro", "shuto.ic.c1.ginza"),
      ("shuto.ic.2.tengenji", "shuto.ic.c1.ginza"),
      ("shuto.ic.c1.ginza", "shuto.ic.2.meguro"),
      ("shuto.ic.5.higashiikebukuro", "shuto.ic.c1.ginza"),
      ("shuto.ic.c1.ginza", "shuto.ic.5.higashiikebukuro"),
    ]

    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    for (entryFacilityID, exitFacilityID) in pairs {
      model.reset()
      model.selectCurrentOrigin(
        ShutoCoordinate(latitude: 35.6812, longitude: 139.7671)
      )
      model.prepareCustomRouteDraft()
      model.selectCustomEntry(facilityID: entryFacilityID)
      model.selectCustomExit(facilityID: exitFacilityID)

      XCTAssertTrue(model.applyCustomRoute())
      for _ in 0..<300
      where model.isPreparingLiveNavigation
        || model.isUpdatingSurfaceRoute
      {
        try? await Task.sleep(nanoseconds: 50_000_000)
      }

      XCTAssertEqual(
        model.selectedRoute?.routePlan.entryFacilityID,
        entryFacilityID
      )
      XCTAssertEqual(
        model.selectedRoute?.routePlan.exitFacilityID,
        exitFacilityID
      )
      XCTAssertFalse(model.isPreparingLiveNavigation)
      XCTAssertTrue(
        model.canStartLiveNavigation,
        "Expected live admission for \(entryFacilityID) -> \(exitFacilityID), blocker: \(model.liveNavigationBlockerCode ?? "none")"
      )
      XCTAssertNil(model.liveNavigationBlockerCode)
    }
  }

  func testLiveStartWaitsForSurfaceRouteRequestsToFinish() async throws {
    let resolver = WholeShutoGatedSurfaceRouteResolver()
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: resolver, checkpointStore: nil,
      liveLocationSource: WholeShutoBackgroundNavigationLocationSource(),
      speechOutput: WholeShutoRecordingSpeechOutput())
    model.selectCurrentOrigin(ShutoCoordinate(latitude: 35.6812, longitude: 139.7671))
    model.prepareCustomRouteDraft()
    model.selectCustomEntry(facilityID: "shuto.ic.b.urayasu")
    model.selectCustomExit(facilityID: "shuto.ic.9.fukudumi")
    XCTAssertTrue(model.applyCustomRoute())
    for _ in 0..<300 where model.isPreparingLiveNavigation {
      try await Task.sleep(for: .milliseconds(25))
    }
    XCTAssertFalse(model.isPreparingLiveNavigation)
    XCTAssertTrue(model.isUpdatingSurfaceRoute)
    XCTAssertFalse(model.canStartLiveNavigation)
    XCTAssertEqual(model.liveNavigationBlockerCode, "SURFACE_ROUTE_PREPARING")
    let prematureStart = await model.startLiveJourney()
    XCTAssertFalse(prematureStart)
    XCTAssertEqual(model.phase, .review)
    await resolver.release()
    for _ in 0..<300 where model.isUpdatingSurfaceRoute {
      try await Task.sleep(for: .milliseconds(25))
    }
    XCTAssertTrue(model.canStartLiveNavigation)
    let started = await model.startLiveJourney()
    XCTAssertTrue(started)
    XCTAssertEqual(model.phase, .surfaceAccess)
    model.reset()
  }

  func testLiveJourneyStartsAtCurrentPositionWithSurfaceInstruction()
    async throws
  {
    let output = WholeShutoRecordingSpeechOutput()
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoInstructionSurfaceRouteResolver(),
      checkpointStore: nil,
      liveLocationSource: WholeShutoBackgroundNavigationLocationSource(),
      speechOutput: output,
      languageSelectionProvider: {
        NavigationLanguageSelection(interfaceLocale: .english, guidanceVoiceLocale: .english)
      }
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6812, longitude: 139.7671)
    )
    model.prepareCustomRouteDraft()
    model.selectCustomEntry(facilityID: "shuto.ic.b.urayasu")
    model.selectCustomExit(facilityID: "shuto.ic.9.fukudumi")
    XCTAssertTrue(model.applyCustomRoute())
    for _ in 0..<300
    where model.isPreparingLiveNavigation || model.isUpdatingSurfaceRoute {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }

    let started = await model.startLiveJourney()
    XCTAssertTrue(started)
    XCTAssertTrue(model.isLiveDrive)
    XCTAssertEqual(model.phase, .surfaceAccess)
    XCTAssertEqual(model.activeSurfaceInstruction, "Continue on local road")
    XCTAssertEqual(
      try XCTUnwrap(model.activeSurfaceInstructionRemainingMeters),
      1_200,
      accuracy: 0.01
    )
    let command = try XCTUnwrap(output.commands.only)
    XCTAssertEqual(command.routePlanID, model.selectedRoute?.routePlan.id)
    XCTAssertEqual(command.languageCode, "en-US")
    XCTAssertEqual(command.spokenText, "Continue on local road")
    XCTAssertTrue(command.identity.promptID.hasPrefix("provider.surface."))
    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(
        id: "surface.course", coordinate: try XCTUnwrap(model.origin?.coordinate),
        courseDegrees: 180, courseAccuracyDegrees: 2
      )
    )
    XCTAssertEqual(model.vehicleHeadingDegrees, 180)
    XCTAssertEqual(model.navigationHeadingDegrees, 180)
    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(
        id: "surface.stationary", coordinate: try XCTUnwrap(model.origin?.coordinate),
        atMilliseconds: 2_000, courseDegrees: 180, courseAccuracyDegrees: 2,
        speedMetersPerSecond: 0
      )
    )
    XCTAssertNil(model.vehicleHeadingDegrees)
    XCTAssertNil(model.navigationHeadingDegrees)
    model.reset()
  }

  func testLiveSurfaceSpeechPreannouncesNextStepExactlyOnce()
    async throws
  {
    let output = WholeShutoRecordingSpeechOutput()
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoMultiStepSurfaceRouteResolver(),
      checkpointStore: nil,
      liveLocationSource: WholeShutoBackgroundNavigationLocationSource(),
      speechOutput: output,
      languageSelectionProvider: {
        NavigationLanguageSelection(interfaceLocale: .english, guidanceVoiceLocale: .english)
      }
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6812, longitude: 139.7671)
    )
    model.prepareCustomRouteDraft()
    model.selectCustomEntry(facilityID: "shuto.ic.b.urayasu")
    model.selectCustomExit(facilityID: "shuto.ic.9.fukudumi")
    XCTAssertTrue(model.applyCustomRoute())
    for _ in 0..<300
    where model.isPreparingLiveNavigation || model.isUpdatingSurfaceRoute {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }

    let started = await model.startLiveJourney()
    XCTAssertTrue(started)
    XCTAssertEqual(output.commands.map(\.spokenText), ["Continue straight"])
    let route = try XCTUnwrap(model.accessRoute)
    let start = try XCTUnwrap(route.coordinates.first)
    let end = try XCTUnwrap(route.coordinates.last)
    let midpoint = ShutoCoordinate(
      latitude: (start.latitude + end.latitude) / 2,
      longitude: (start.longitude + end.longitude) / 2
    )
    let envelope = Self.liveLocationEnvelope(
      id: "surface.preannounce",
      coordinate: midpoint
    )
    await model.consumeLiveObservationForTesting(envelope)
    await model.consumeLiveObservationForTesting(envelope)

    XCTAssertEqual(
      output.commands.map(\.spokenText),
      ["Continue straight", "Turn left"]
    )
    XCTAssertTrue(model.canRepeatGuidance)
    XCTAssertTrue(model.repeatGuidance())
    XCTAssertEqual(output.commands.last?.spokenText, "Continue straight")
    XCTAssertEqual(output.commands.count, 3)
    model.setSpeechMode(.muted)
    XCTAssertTrue(model.isPlaying)
    XCTAssertFalse(model.canRepeatGuidance)
    XCTAssertFalse(model.repeatGuidance())
    XCTAssertEqual(output.commands.count, 3)
    model.setSpeechMode(.full)
    model.reset()
  }

  func testDriveRecordCollectsSpeedFromTheDriveAndCanBeSwitchedOff() async throws
  {
    let defaults = try XCTUnwrap(
      UserDefaults(suiteName: "app.kaidoroutes.tests.drive-record")
    )
    defaults.removePersistentDomain(
      forName: "app.kaidoroutes.tests.drive-record"
    )
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let history = FileDriveHistoryStore(directory: directory)
    let locationSource = WholeShutoBackgroundNavigationLocationSource()
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoInstructionSurfaceRouteResolver(),
      checkpointStore: nil,
      liveLocationSource: locationSource,
      speechOutput: WholeShutoRecordingSpeechOutput(),
      driveRecordPreferenceStore: defaults,
      driveHistoryStore: history
    )
    // Shown unless the driver has said otherwise.
    XCTAssertTrue(model.showsDriveRecord)

    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6812, longitude: 139.7671)
    )
    model.prepareCustomRouteDraft()
    model.selectCustomEntry(facilityID: "shuto.ic.b.urayasu")
    model.selectCustomExit(facilityID: "shuto.ic.9.fukudumi")
    XCTAssertTrue(model.applyCustomRoute())
    for _ in 0..<300
    where model.isPreparingLiveNavigation || model.isUpdatingSurfaceRoute {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }
    let started = await model.startLiveJourney()
    XCTAssertTrue(started)
    // A fresh journey starts from an empty record.
    XCTAssertFalse(model.driveRecord.hasSpeedRecord)

    let route = try XCTUnwrap(model.accessRoute)
    let midpoint = try XCTUnwrap(route.coordinates.first)
    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(
        id: "record.0",
        coordinate: midpoint,
        atMilliseconds: 1_000,
        speedMetersPerSecond: 20
      )
    )
    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(
        id: "record.1",
        coordinate: midpoint,
        atMilliseconds: 6_000,
        speedMetersPerSecond: 10
      )
    )

    XCTAssertEqual(model.driveRecord.maximumSpeedMetersPerSecond, 20)
    XCTAssertEqual(model.driveRecord.minimumSpeedMetersPerSecond, 10)
    XCTAssertEqual(
      try XCTUnwrap(model.driveRecord.averageSpeedMetersPerSecond),
      15,
      accuracy: 0.001
    )

    ActiveDriveControl.model = model
    defer { ActiveDriveControl.model = nil }
    _ = try await DriveControlIntent(action: .mute).perform()
    XCTAssertEqual(model.speechMode, .muted)
    XCTAssertTrue(model.isPlaying)
    _ = try await DriveControlIntent(action: .unmute).perform()
    XCTAssertEqual(model.speechMode, .full)
    // A break is taken parked. The stop comes after a gap longer than the
    // record's sample window, so it adds no recorded interval.
    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(
        id: "record.parked",
        coordinate: midpoint,
        atMilliseconds: 6_000 + WholeShutoDriveRecord.maximumSampleGapMilliseconds + 1,
        speedMetersPerSecond: 0
      )
    )
    _ = try await DriveControlIntent(action: .rest).perform()
    XCTAssertFalse(model.isPlaying)
    let historyWhileResting = try await history.load()
    XCTAssertTrue(historyWhileResting.isEmpty)
    _ = try await DriveControlIntent(action: .resume).perform()
    XCTAssertTrue(model.isPlaying)
    let selectedPlan = try XCTUnwrap(model.selectedRoute?.routePlan)
    let savedRoute = Self.savedRouteRecord(
      selectedPlan,
      templateParameters: model.savedRouteTemplateParameters
    )
    XCTAssertTrue(model.openSavedRoute(savedRoute, origin: midpoint))
    XCTAssertEqual(model.phase, .review)
    XCTAssertFalse(model.isLiveDrive)
    XCTAssertEqual(model.selectedRoute?.routePlan, selectedPlan)
    XCTAssertEqual(model.origin?.coordinate, midpoint)
    let savedHistory = try await history.load()
    let saved = try XCTUnwrap(savedHistory.first)
    XCTAssertEqual(saved.recordedDistanceMeters, 75, accuracy: 0.001)
    XCTAssertEqual(saved.recordedDurationMilliseconds, 5_000)
    XCTAssertEqual(saved.averageSpeedMetersPerSecond, 15)
    XCTAssertFalse(saved.arrived)

    // Switching it off is the driver's, and it survives a new model.
    model.setShowsDriveRecord(false)
    XCTAssertFalse(model.showsDriveRecord)
    let reopened = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoInstructionSurfaceRouteResolver(),
      checkpointStore: nil,
      speechOutput: WholeShutoRecordingSpeechOutput(),
      driveRecordPreferenceStore: defaults
    )
    XCTAssertFalse(reopened.showsDriveRecord)

    // The record is the journey's, not the app's: resetting clears it.
    model.reset()
    XCTAssertFalse(model.driveRecord.hasSpeedRecord)
    defaults.removePersistentDomain(
      forName: "app.kaidoroutes.tests.drive-record"
    )
  }

  func testRestingALiveDriveKeepsItsSessionAndResumesInPlace() async throws {
    let locationSource = WholeShutoBackgroundNavigationLocationSource()
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoInstructionSurfaceRouteResolver(),
      checkpointStore: nil,
      liveLocationSource: locationSource,
      speechOutput: WholeShutoRecordingSpeechOutput()
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6812, longitude: 139.7671)
    )
    model.prepareCustomRouteDraft()
    model.selectCustomEntry(facilityID: "shuto.ic.b.urayasu")
    model.selectCustomExit(facilityID: "shuto.ic.9.fukudumi")
    XCTAssertTrue(model.applyCustomRoute())
    for _ in 0..<300
    where model.isPreparingLiveNavigation || model.isUpdatingSurfaceRoute {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }

    let started = await model.startLiveJourney()
    XCTAssertTrue(started)
    let route = try XCTUnwrap(model.accessRoute)
    let start = try XCTUnwrap(route.coordinates.first)
    let end = try XCTUnwrap(route.coordinates.last)
    let midpoint = ShutoCoordinate(
      latitude: (start.latitude + end.latitude) / 2,
      longitude: (start.longitude + end.longitude) / 2
    )
    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(
        id: "rest.midpoint", coordinate: midpoint, speedMetersPerSecond: 0
      )
    )
    XCTAssertEqual(model.liveLocationState, .available)
    let restedProgress = model.progressFraction
    let restedPhase = model.phase

    let rested = await model.restLiveJourney()
    XCTAssertTrue(rested)
    XCTAssertEqual(model.liveLocationState, .resting)
    // A chosen stop is not a fault: the position reads as resting rather than
    // degraded, and the map keeps no stale bearing to rotate to.
    XCTAssertEqual(model.positionState, .resting)
    XCTAssertNil(model.navigationHeadingDegrees)
    XCTAssertFalse(model.isPlaying)
    XCTAssertFalse(model.canConsumeForegroundNavigationLocations)
    XCTAssertTrue(model.isLiveDrive)
    XCTAssertEqual(model.phase, restedPhase)
    XCTAssertEqual(model.progressFraction, restedProgress, accuracy: 0.0001)

    // Resting twice is not a second stop.
    let restedAgain = await model.restLiveJourney()
    XCTAssertFalse(restedAgain)

    let resumed = await model.resumeLiveJourney()
    XCTAssertTrue(resumed)
    XCTAssertTrue(model.isPlaying)
    XCTAssertNotEqual(model.liveLocationState, .resting)
    XCTAssertEqual(model.phase, restedPhase)
    XCTAssertEqual(model.progressFraction, restedProgress, accuracy: 0.0001)

    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(id: "rest.after", coordinate: midpoint)
    )
    XCTAssertEqual(model.liveLocationState, .available)
    model.reset()
  }

  func testRestRefusesOutsideALiveDrive() async {
    let model = WholeShutoProductModel(checkpointStore: nil)
    let restedWhileParked = await model.restLiveJourney()
    XCTAssertFalse(restedWhileParked)

    model.preparePreviewJourney()
    let restedInPreview = await model.restLiveJourney()
    XCTAssertFalse(restedInPreview)
    XCTAssertNotEqual(model.liveLocationState, .resting)
  }

  func testRestIsRefusedOnlyWhileAFreshFixShowsMovement() async throws {
    let output = SpeechRecoveryAppOutput()
    output.autoFinish = true
    let model = try await speechRecoveryModel(output: output)
    let route = try XCTUnwrap(model.accessRoute)
    let start = try XCTUnwrap(route.coordinates.first)
    let end = try XCTUnwrap(route.coordinates.last)
    let midpoint = ShutoCoordinate(
      latitude: (start.latitude + end.latitude) / 2,
      longitude: (start.longitude + end.longitude) / 2
    )
    ActiveDriveControl.model = model
    defer { ActiveDriveControl.model = nil }
    func fix(_ id: String, at milliseconds: Int, speed: Double) async {
      await model.consumeLiveObservationForTesting(
        Self.liveLocationEnvelope(
          id: id, coordinate: midpoint, atMilliseconds: milliseconds,
          speedMetersPerSecond: speed))
    }

    await fix("rest.moving", at: 2_000, speed: 12)
    XCTAssertFalse(model.canRestLiveJourney)
    let restedWhileMoving = await model.restLiveJourney()
    XCTAssertFalse(restedWhileMoving)
    _ = try await DriveControlIntent(action: .rest).perform()
    XCTAssertTrue(model.isPlaying)
    XCTAssertNotEqual(model.liveLocationState, .resting)

    // Parked under a PA roof Core Location often cannot measure speed; its
    // negative "unknown" value is not evidence of movement.
    await fix("rest.unknown-speed", at: 3_000, speed: -1)
    XCTAssertTrue(model.canRestLiveJourney)

    // Nor is a moving fix that has gone stale.
    await fix("rest.moving-again", at: 4_000, speed: 12)
    XCTAssertFalse(model.canRestLiveJourney)
    model.evaluateLiveLocationFreshness(atMilliseconds: 4_000 + 10_000)
    XCTAssertEqual(model.liveLocationState, .stale)
    XCTAssertTrue(model.canRestLiveJourney)

    await fix("rest.stopped", at: 15_000, speed: 0.3)
    XCTAssertTrue(model.canRestLiveJourney)
    await fix("rest.unknown-at-pa", at: 16_000, speed: -1)
    _ = try await DriveControlIntent(action: .rest).perform()
    XCTAssertEqual(model.liveLocationState, .resting)
    XCTAssertFalse(model.isPlaying)
    model.reset()
  }

  func testAFixInFlightCannotUndoARestOrAnEndedDrive() async throws {
    let output = SpeechRecoveryAppOutput()
    output.autoFinish = true
    let model = try await speechRecoveryModel(output: output)
    let position = try await driveSpeechRecoveryRoute(model) { model.phase == .expressway }
    func stationaryFix(
      _ model: WholeShutoProductModel, _ id: String, at stop: LiveDrivePosition,
      plus milliseconds: Int
    ) async {
      await model.consumeLiveObservationForTesting(
        Self.liveLocationEnvelope(
          id: id, coordinate: stop.coordinate, atMilliseconds: stop.timestamp + milliseconds,
          courseDegrees: stop.course, speedMetersPerSecond: 0))
    }
    await stationaryFix(model, "late.stopped", at: position, plus: 1_000)

    // The fix is already inside the navigation actor when the driver rests.
    let lateBeforeRest = Task { await stationaryFix(model, "late.rest", at: position, plus: 2_000) }
    await Task.yield()
    let rested = await model.restLiveJourney()
    await lateBeforeRest.value
    XCTAssertTrue(rested)
    XCTAssertEqual(model.liveLocationState, .resting)
    XCTAssertFalse(model.isPlaying)
    model.reset()

    let ended = try await speechRecoveryModel(output: SpeechRecoveryAppOutput())
    let endPosition = try await driveSpeechRecoveryRoute(ended) { ended.phase == .expressway }
    let lateBeforeEnd = Task { await stationaryFix(ended, "late.end", at: endPosition, plus: 1_000) }
    await Task.yield()
    ended.reset()
    await lateBeforeEnd.value
    XCTAssertFalse(ended.isLiveDrive)
    XCTAssertEqual(ended.liveLocationState, .inactive)
    XCTAssertNil(ended.matcherConfidence)
    XCTAssertNil(ended.presentationProjection)
  }

  func testSiriResumeReportsAPausedDriveWhenTheAppIsNotInFront() async throws {
    let output = SpeechRecoveryAppOutput()
    output.autoFinish = true
    let model = try await speechRecoveryModel(output: output)
    let start = try XCTUnwrap(model.accessRoute?.coordinates.first)
    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(
        id: "resume.parked", coordinate: start, atMilliseconds: 2_000,
        speedMetersPerSecond: 0))
    let rested = await model.restLiveJourney()
    XCTAssertTrue(rested)

    // Siri runs the intent before the scene is active: location cannot start.
    await model.handleScenePhase(.background)
    let resumedBehind = await model.resumeLiveJourney()
    XCTAssertFalse(resumedBehind)
    XCTAssertFalse(model.isPlaying)
    XCTAssertEqual(model.liveLocationState, .resumeRequired)

    await model.handleScenePhase(.active)
    let resumedInFront = await model.resumeLiveJourney()
    XCTAssertTrue(resumedInFront)
    XCTAssertTrue(model.isPlaying)
    model.reset()
  }

  func testDriveFailuresReadAsOneDrivingLine() {
    for locale in KaidoReleaseLocale.allCases {
      let lap = WholeShutoDrivingFailure.message(for: "LAP_CHANGE_UNAVAILABLE", locale: locale)
      XCTAssertNotNil(lap)
      XCTAssertEqual(
        WholeShutoDrivingFailure.message(
          for: WholeShutoProductModel.lapChangeUnavailableCode, locale: locale),
        lap)
      let messages = [
        lap,
        WholeShutoDrivingFailure.message(
          for: "WHOLE_SHUTO_EXIT_HANDOFF_UNCONFIRMED", locale: locale),
        WholeShutoDrivingFailure.message(
          for: WholeShutoProductModel.liveNavigationRuntimeInvalidCode, locale: locale),
        WholeShutoDrivingFailure.message(
          for: "WHOLE_SHUTO_CHECKPOINT_RUNTIME_INVALID", locale: locale),
      ]
      XCTAssertEqual(Set(messages.compactMap { $0 }).count, 4)
      for message in messages.compactMap({ $0 }) {
        XCTAssertFalse(message.contains("\n"))
        XCTAssertFalse(message.contains("首都高"))
      }
      // A failed fix is the position line's to report, not a banner.
      XCTAssertNil(
        WholeShutoDrivingFailure.message(
          for: "WHOLE_SHUTO_OBSERVATION_PIPELINE_FAILED", locale: locale))
    }
    XCTAssertEqual(
      WholeShutoDrivingFailure.message(for: "LAP_CHANGE_UNAVAILABLE", locale: .english),
      "Lap change unavailable")
  }

  func testLiveSurfaceAccessReroutesAfterTwoConsecutiveOffRouteFixes()
    async throws
  {
    let locationSource = WholeShutoBackgroundNavigationLocationSource()
    let resolver = WholeShutoRecoverableSurfaceRouteResolver()
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: resolver,
      checkpointStore: nil,
      liveLocationSource: locationSource,
      speechOutput: WholeShutoRecordingSpeechOutput()
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6812, longitude: 139.7671)
    )
    model.prepareCustomRouteDraft()
    model.selectCustomEntry(facilityID: "shuto.ic.b.urayasu")
    model.selectCustomExit(facilityID: "shuto.ic.9.fukudumi")
    XCTAssertTrue(model.applyCustomRoute())
    model.selectJourneyEnding(.returnToOrigin)
    for _ in 0..<300
    where model.isPreparingLiveNavigation || model.isUpdatingSurfaceRoute {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }

    let started = await model.startLiveJourney()
    XCTAssertTrue(started)
    let routePlan = try XCTUnwrap(model.selectedRoute?.routePlan)
    let route = try XCTUnwrap(model.accessRoute)
    let originalEgressRoute = try XCTUnwrap(model.egressRoute)
    let start = try XCTUnwrap(route.coordinates.first)
    let end = try XCTUnwrap(route.coordinates.last)
    let midpoint = ShutoCoordinate(
      latitude: (start.latitude + end.latitude) / 2,
      longitude: (start.longitude + end.longitude) / 2
    )
    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(id: "surface.midpoint", coordinate: midpoint)
    )

    XCTAssertEqual(model.phase, .surfaceAccess)
    XCTAssertEqual(model.liveLocationState, .available)
    XCTAssertEqual(model.progressFraction, 0.5, accuracy: 0.02)
    XCTAssertEqual(
      try XCTUnwrap(model.activeSurfaceInstructionRemainingMeters),
      600,
      accuracy: 25
    )

    let acceptedProgress = model.progressFraction
    let offRoute = ShutoCoordinate(
      latitude: midpoint.latitude + 0.01,
      longitude: midpoint.longitude
    )
    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(id: "surface.off-route.0", coordinate: offRoute)
    )

    // One fix off the line is a mismeasurement, not a lost route: the header
    // keeps the current step and the position stays the car's.
    XCTAssertEqual(model.phase, .surfaceAccess)
    XCTAssertEqual(model.liveLocationState, .available)
    XCTAssertNil(model.liveLocationIssueCode)
    XCTAssertEqual(model.positionState, .surfacePreview)
    XCTAssertEqual(model.progressFraction, acceptedProgress, accuracy: 0.001)
    XCTAssertEqual(model.accessRoute, route)
    XCTAssertFalse(model.isReroutingSurfaceRoute)

    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(id: "surface.off-route.1", coordinate: offRoute)
    )
    for _ in 0..<100
    where model.accessRoute?.coordinates.first != offRoute {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }

    XCTAssertEqual(model.phase, .surfaceAccess)
    XCTAssertEqual(model.selectedRoute?.routePlan, routePlan)
    XCTAssertEqual(model.accessRoute?.coordinates.first, offRoute)
    XCTAssertEqual(model.accessRoute?.coordinates.last, route.coordinates.last)
    XCTAssertEqual(model.egressRoute, originalEgressRoute)
    XCTAssertEqual(model.activeSurfaceInstruction, "Continue on local road")
    XCTAssertEqual(model.progressFraction, 0, accuracy: 0.001)
    XCTAssertEqual(model.liveLocationState, .available)
    XCTAssertNil(model.liveLocationIssueCode)
    XCTAssertEqual(model.positionState, .surfacePreview)
    XCTAssertFalse(model.isReroutingSurfaceRoute)
    let retainedRoute = model.accessRoute
    let nextOffRoute = ShutoCoordinate(
      latitude: offRoute.latitude + 0.01,
      longitude: offRoute.longitude
    )
    await resolver.setUnavailable(true)
    for timestamp in [20_000, 21_000] {
      await model.consumeLiveObservationForTesting(
        Self.liveLocationEnvelope(
          id: "surface.offline.\(timestamp)", coordinate: nextOffRoute,
          atMilliseconds: timestamp
        )
      )
    }
    for _ in 0..<100 where model.isReroutingSurfaceRoute {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertTrue(model.isPlaying)
    XCTAssertEqual(model.accessRoute, retainedRoute)
    XCTAssertEqual(model.selectedRoute?.routePlan, routePlan)
    XCTAssertEqual(model.liveLocationIssueCode, "SURFACE_ROUTE_REROUTE_UNAVAILABLE")
    // The label the single stray fix no longer earns is still reached once
    // the route is genuinely lost and no replacement can be built.
    XCTAssertEqual(model.positionState, .surfaceRoutePending)

    await resolver.setUnavailable(false)
    for timestamp in [37_000, 38_000] {
      await model.consumeLiveObservationForTesting(
        Self.liveLocationEnvelope(
          id: "surface.online.\(timestamp)", coordinate: nextOffRoute,
          atMilliseconds: timestamp
        )
      )
    }
    for _ in 0..<100 where model.isReroutingSurfaceRoute {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertTrue(model.isPlaying)
    XCTAssertEqual(model.accessRoute?.coordinates.first, nextOffRoute)
    XCTAssertEqual(model.selectedRoute?.routePlan, routePlan)
    XCTAssertEqual(model.egressRoute, originalEgressRoute)
    XCTAssertEqual(model.liveLocationState, .available)
    model.reset()
  }

  func testReleasedLiveRecoveryKeepsConsumingLocationUntilRouteRejoin()
    async throws
  {
    var nowMilliseconds = 1_000
    let locationSource = WholeShutoBackgroundNavigationLocationSource()
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil,
      liveLocationSource: locationSource,
      speechOutput: WholeShutoRecordingSpeechOutput(),
      nowMillisecondsProvider: { nowMilliseconds }
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6763, longitude: 139.7720)
    )
    model.prepareCustomRouteDraft()
    // The released detour must leave the plan by more than GPS error; the
    // Rinkai-fukutoshin run's only one is a slip road within 14 m of it.
    model.selectCustomEntry(facilityID: "shuto.ic.b.shinkiba")
    model.selectCustomExit(facilityID: "shuto.ic.b.ooi")
    XCTAssertTrue(model.applyCustomRoute())
    for _ in 0..<300
    where model.isPreparingLiveNavigation || model.isUpdatingSurfaceRoute
      || !model.canStartLiveNavigation
    {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }

    let route = try XCTUnwrap(model.selectedRoute)
    let context = try ShutoPlannedRouteRuntimeCompiler.NetworkContext(
      database: model.database
    )
    let release =
      try ShutoCircuitProductReleaseBuilder
      .buildPlannedRouteRelease(context: context, route: route)
    let recovery = try XCTUnwrap(
      release.navigation.bundle.runtimePolicy.recoveryCandidates.first
    )
    let divergence = try XCTUnwrap(
      route.routePlan.occurrence(id: recovery.divergenceOccurrenceID)
    )
    let target = try XCTUnwrap(
      route.routePlan.occurrence(id: recovery.targetOccurrenceID)
    )
    XCTAssertLessThan(divergence.index, target.index)
    XCTAssertFalse(recovery.recoveryOccurrenceIDs.isEmpty)

    let started = await model.startLiveJourney()
    XCTAssertTrue(started)
    let corridorEdges = Dictionary(
      uniqueKeysWithValues: release.navigation.bundle.matcherCorridor.edges
        .map { ($0.id, $0) }
    )
    let corridorOccurrences = release.navigation.bundle.matcherCorridor
      .occurrences.sorted { $0.index < $1.index }
    let accessEnd = try XCTUnwrap(model.accessRoute?.coordinates.last)
    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(
        id: "recovery.access-end",
        coordinate: accessEnd,
        atMilliseconds: nowMilliseconds,
        courseDegrees: Self.bearing(
          from: route.coordinates[0],
          to: route.coordinates[1]
        )
      )
    )

    for occurrence in corridorOccurrences
    where occurrence.index < divergence.index {
      let edge = try XCTUnwrap(corridorEdges[occurrence.directedEdgeID])
      let start = try XCTUnwrap(edge.coordinates.first)
      let end = try XCTUnwrap(edge.coordinates.last)
      let startCoordinate = ShutoCoordinate(
        latitude: start.latitude,
        longitude: start.longitude
      )
      let endCoordinate = ShutoCoordinate(
        latitude: end.latitude,
        longitude: end.longitude
      )
      for fraction in Self.oneHertzFractions(
        from: startCoordinate,
        to: endCoordinate
      ) {
        nowMilliseconds += 1_000
        await model.consumeLiveObservationForTesting(
          Self.liveLocationEnvelope(
            id: "recovery.route.\(occurrence.index).\(fraction)",
            coordinate: Self.interpolate(
              from: startCoordinate,
              to: endCoordinate,
              fraction: fraction
            ),
            atMilliseconds: nowMilliseconds,
            courseDegrees: Self.bearing(
              from: startCoordinate,
              to: endCoordinate
            )
          )
        )
      }
    }
    XCTAssertEqual(model.phase, .expressway)
    XCTAssertEqual(model.runtimeJourneyPhase, .strictRoute)
    XCTAssertLessThanOrEqual(
      try XCTUnwrap(
        route.routePlan.occurrence(
          id: try XCTUnwrap(model.runtimeOccurrenceID)
        )
      ).index,
      divergence.index
    )
    let preRecoveryCoordinate = try XCTUnwrap(model.currentCoordinate)

    var observedActiveRecovery = false
    for edgeID in recovery.recoveryOccurrenceIDs {
      let edge = try XCTUnwrap(corridorEdges[edgeID])
      let start = try XCTUnwrap(edge.coordinates.first)
      let end = try XCTUnwrap(edge.coordinates.last)
      let startCoordinate = ShutoCoordinate(
        latitude: start.latitude,
        longitude: start.longitude
      )
      let endCoordinate = ShutoCoordinate(
        latitude: end.latitude,
        longitude: end.longitude
      )
      for fraction in Self.oneHertzFractions(
        from: startCoordinate,
        to: endCoordinate
      ) {
        nowMilliseconds += 1_000
        await model.consumeLiveObservationForTesting(
          Self.liveLocationEnvelope(
            id: "recovery.path.\(edgeID).\(fraction)",
            coordinate: Self.interpolate(
              from: startCoordinate,
              to: endCoordinate,
              fraction: fraction
            ),
            atMilliseconds: nowMilliseconds,
            courseDegrees: Self.bearing(
              from: startCoordinate,
              to: endCoordinate
            )
          )
        )
        if model.runtimeRecoveryStatus == .active {
          observedActiveRecovery = true
          XCTAssertTrue(model.isPlaying)
          XCTAssertTrue(model.canConsumeForegroundNavigationLocations)
          XCTAssertEqual(
            model.runtimeRecoveryTargetOccurrenceID,
            recovery.targetOccurrenceID
          )
          XCTAssertFalse(model.activeRecoveryRouteCoordinates.isEmpty)
          XCTAssertNotEqual(model.currentCoordinate, preRecoveryCoordinate)
        }
      }
    }
    XCTAssertTrue(observedActiveRecovery)

    // Where the detour merges back it still runs within GPS error of the
    // plan, so the rejoin is admitted once the car is clear of it.
    for occurrence in corridorOccurrences
    where occurrence.index >= target.index
      && occurrence.index < target.index + 8
    {
      let edge = try XCTUnwrap(corridorEdges[occurrence.directedEdgeID])
      let start = try XCTUnwrap(edge.coordinates.first)
      let end = try XCTUnwrap(edge.coordinates.last)
      let startCoordinate = ShutoCoordinate(
        latitude: start.latitude,
        longitude: start.longitude
      )
      let endCoordinate = ShutoCoordinate(
        latitude: end.latitude,
        longitude: end.longitude
      )
      for fraction in Self.oneHertzFractions(
        from: startCoordinate,
        to: endCoordinate
      ) {
        nowMilliseconds += 1_000
        await model.consumeLiveObservationForTesting(
          Self.liveLocationEnvelope(
            id: "recovery.rejoin.\(occurrence.index).\(fraction)",
            coordinate: Self.interpolate(
              from: startCoordinate,
              to: endCoordinate,
              fraction: fraction
            ),
            atMilliseconds: nowMilliseconds,
            courseDegrees: Self.bearing(
              from: startCoordinate,
              to: endCoordinate
            )
          )
        )
      }
    }

    XCTAssertEqual(model.runtimeJourneyPhase, .strictRoute)
    XCTAssertEqual(model.runtimeRecoveryStatus, .inactive)
    XCTAssertNil(model.runtimeRecoveryTargetOccurrenceID)
    XCTAssertNil(model.runtimeRecoveryDirectedEdgeID)
    XCTAssertTrue(model.activeRecoveryRouteCoordinates.isEmpty)
    XCTAssertTrue(model.isPlaying)
    XCTAssertGreaterThanOrEqual(
      try XCTUnwrap(
        route.routePlan.occurrence(id: try XCTUnwrap(model.runtimeOccurrenceID))
      ).index,
      target.index
    )
    model.reset()
  }

  func testUnadmittedFreshFixesHoldTheMarkerWithoutWeakTextOrVoice()
    async throws
  {
    let clock = LiveTestClock()
    let output = WholeShutoRecordingSpeechOutput()
    let drive = try await bayshoreLiveDrive(clock: clock, output: output)
    let model = drive.model
    var points = Self.corridorFixPoints(release: drive.release)[...]
    func feed(accuracy: Double) async throws {
      let point = try XCTUnwrap(points.popFirst())
      clock.milliseconds += 1_000
      await model.consumeLiveObservationForTesting(
        Self.liveLocationEnvelope(
          id: "holding.\(clock.milliseconds)",
          coordinate: point.coordinate,
          atMilliseconds: clock.milliseconds,
          courseDegrees: point.courseDegrees,
          horizontalAccuracyMeters: accuracy
        )
      )
    }
    func notices() -> Int {
      output.commands.filter { $0.identity.anchorID == "JOURNEY_STATUS" }.count
    }

    for _ in 0..<200
    where model.phase != .expressway || model.matcherConfidence != .high {
      try await feed(accuracy: 5)
    }
    XCTAssertEqual(model.matcherConfidence, .high)
    XCTAssertFalse(model.isHoldingLivePosition)
    let positionState = model.positionState
    let noticeCount = notices()

    // Coarse on-route fixes are fresh and usable but never admitted.
    for second in 1...5 {
      try await feed(accuracy: 40)
      XCTAssertNotEqual(model.matcherConfidence, .high)
      XCTAssertEqual(model.isHoldingLivePosition, second >= 5, "second \(second)")
    }
    XCTAssertEqual(model.liveLocationState, .available)
    XCTAssertNil(model.liveLocationIssueCode)
    XCTAssertEqual(model.positionState, positionState)
    XCTAssertTrue(model.hasCurrentGuidancePosition)
    XCTAssertEqual(notices(), noticeCount)

    for _ in 0..<30 where model.matcherConfidence != .high {
      try await feed(accuracy: 5)
    }
    XCTAssertEqual(model.matcherConfidence, .high)
    XCTAssertFalse(model.isHoldingLivePosition)
    XCTAssertEqual(notices(), noticeCount)
    model.reset()
  }

  func testRouteRecoveryOffTheCorridorKeepsFreshFixesUsable()
    async throws
  {
    let clock = LiveTestClock()
    let output = WholeShutoRecordingSpeechOutput()
    // A released detour that leaves the plan by more than GPS error.
    let drive = try await bayshoreLiveDrive(
      clock: clock,
      output: output,
      entryFacilityID: "shuto.ic.b.shinkiba",
      exitFacilityID: "shuto.ic.b.ooi"
    )
    let model = drive.model
    let recovery = try XCTUnwrap(
      drive.release.navigation.bundle.runtimePolicy.recoveryCandidates.first
    )
    let divergence = try XCTUnwrap(
      drive.route.routePlan.occurrence(id: recovery.divergenceOccurrenceID)
    )
    let corridorEdges = Dictionary(
      uniqueKeysWithValues: drive.release.navigation.bundle.matcherCorridor
        .edges.map { ($0.id, $0) }
    )
    let points =
      Self.corridorFixPoints(release: drive.release) {
        $0.index < divergence.index
      }
      + recovery.recoveryOccurrenceIDs.compactMap { corridorEdges[$0] }
      .flatMap(Self.edgeFixPoints)
    var reachedRecovery = false
    for point in points {
      clock.milliseconds += 1_000
      await model.consumeLiveObservationForTesting(
        Self.liveLocationEnvelope(
          id: "recovery-lost.\(clock.milliseconds)",
          coordinate: point.coordinate,
          atMilliseconds: clock.milliseconds,
          courseDegrees: point.courseDegrees
        )
      )
      if model.runtimeJourneyPhase == .routeRecovery {
        reachedRecovery = true
        break
      }
    }
    XCTAssertTrue(reachedRecovery)
    let last = try XCTUnwrap(points.last?.coordinate)
    func notices(_ fragment: String) -> Int {
      output.commands.filter { $0.identity.promptID.contains(fragment) }.count
    }

    // On another expressway about two kilometres from every corridor road:
    // the matcher is lost, but the fixes are fresh, so the drive is off the
    // plan, not out of position, and not off the expressway either.
    let north = ShutoCoordinate(
      latitude: last.latitude + 0.018,
      longitude: last.longitude
    )
    let away = try XCTUnwrap(
      model.database.nodes.map(\.coordinate).min {
        Self.meters($0, north) < Self.meters($1, north)
      }
    )
    for _ in 0..<15 {
      clock.milliseconds += 1_000
      await model.consumeLiveObservationForTesting(
        Self.liveLocationEnvelope(
          id: "recovery-lost.away.\(clock.milliseconds)",
          coordinate: away,
          atMilliseconds: clock.milliseconds
        )
      )
    }
    XCTAssertEqual(model.runtimeJourneyPhase, .routeRecovery)
    XCTAssertEqual(model.liveLocationState, .available)
    model.evaluateLiveLocationFreshness(atMilliseconds: clock.milliseconds)
    XCTAssertEqual(model.liveLocationState, .available)
    XCTAssertEqual(notices("positionLost"), 0)

    // Without any fix, the drive still goes stale.
    model.evaluateLiveLocationFreshness(
      atMilliseconds: clock.milliseconds + 11_000
    )
    XCTAssertEqual(model.liveLocationState, .stale)
    model.reset()
  }

  /// A started live Bayshore drive (Rinkai-fukutoshin to Daikoku-futou unless
  /// told otherwise), with the
  /// release it runs, so a test can place fixes on exact corridor edges.
  /// Past the exit at Senju-Shinbashi the street runs beside C2, where a car
  /// that missed the exit would be: near the exit the drive shows it is
  /// confirming the exit, not interrupted, and says nothing; past 500 m it
  /// shows the interruption as before.
  func testRecoveryBesideThePlannedExitConfirmsTheExitThenInterrupts()
    async throws
  {
    let clock = LiveTestClock()
    let output = WholeShutoRecordingSpeechOutput()
    let drive = try await bayshoreLiveDrive(
      clock: clock,
      output: output,
      entryFacilityID: "shuto.ic.6-misato.kahei",
      exitFacilityID: "shuto.ic.c2.senjushinbashi"
    )
    let model = drive.model
    let corridor = drive.release.navigation.bundle.matcherCorridor
    let corridorEdges = Dictionary(uniqueKeysWithValues: corridor.edges.map { ($0.id, $0) })
    let plan = corridor.occurrences.sorted { $0.index < $1.index }
      .compactMap { corridorEdges[$0.directedEdgeID] }
    let planIDs = Set(plan.map(\.id))
    // The road the plan leaves at its last choice, followed on past the exit.
    let lastChoice = try XCTUnwrap(
      plan.indices.dropFirst().last { index in
        plan[index - 1].successorEdgeIDs.contains { $0 != plan[index].id }
      }
    )
    // Past the corridor the network carries the road on.
    let nodes = Dictionary(uniqueKeysWithValues: model.database.nodes.map { ($0.nodeID, $0.coordinate) })
    let networkEdges = Dictionary(uniqueKeysWithValues: model.database.edges.map { ($0.edgeID, $0) })
    let outgoing = Dictionary(grouping: model.database.edges, by: \.fromNodeID)
    var road: [ShutoNetworkDatabase.Edge] = []
    var next = plan[lastChoice - 1].successorEdgeIDs.sorted().first { $0 != plan[lastChoice].id }
      .flatMap { networkEdges[$0] }
    while let edge = next, !planIDs.contains(edge.edgeID), road.count < 60 {
      road.append(edge)
      next = (outgoing[edge.toNodeID] ?? []).filter { $0.kind == edge.kind }.min { $0.edgeID < $1.edgeID }
    }
    let roadPoints = road.compactMap { edge -> RouteMatcherDirectedEdge? in
      guard let from = nodes[edge.fromNodeID], let to = nodes[edge.toNodeID] else { return nil }
      return RouteMatcherDirectedEdge(
        id: edge.edgeID,
        coordinates: [
          MatcherCoordinate(latitude: from.latitude, longitude: from.longitude),
          MatcherCoordinate(latitude: to.latitude, longitude: to.longitude),
        ]
      )
    }
    let exitEnd = try XCTUnwrap(plan.last?.coordinates.last)
    let points =
      plan[..<lastChoice].flatMap(Self.edgeFixPoints)
      + roadPoints.flatMap(Self.edgeFixPoints)
    func notices() -> Int {
      output.commands.filter {
        $0.identity.promptID.contains("rerouting") || $0.identity.promptID.contains("leftRoute")
      }.count
    }
    var states: [(meters: Double, state: WholeShutoPositionState)] = []
    for (index, point) in points.enumerated() {
      clock.milliseconds += 1_000
      await model.consumeLiveObservationForTesting(
        Self.liveLocationEnvelope(
          id: "confirming-exit.\(index)",
          coordinate: point.coordinate,
          atMilliseconds: clock.milliseconds,
          courseDegrees: point.courseDegrees,
          speedMetersPerSecond: 20
        )
      )
      if model.runtimeJourneyPhase == .routeRecovery {
        let meters = Self.meters(
          point.coordinate, ShutoCoordinate(latitude: exitEnd.latitude, longitude: exitEnd.longitude)
        )
        states.append((meters, model.positionState))
      }
    }
    let confirming = states.filter { $0.state == .confirmingExit }
    XCTAssertFalse(confirming.isEmpty)
    XCTAssertTrue(confirming.allSatisfy { $0.meters <= 600 })
    XCTAssertTrue(
      states.contains { $0.state == .routeInterrupted && $0.meters > 500 },
      states.map { "\(Int($0.meters)):\($0.state.rawValue)" }.joined(separator: " ")
        + " road=\(road.count) last=\(model.runtimeJourneyPhase.map { "\($0)" } ?? "-")"
    )
    XCTAssertEqual(states.first?.state, .confirmingExit)
    XCTAssertEqual(notices(), 0)
    model.reset()
  }

  /// From Toyosu the route runs straight on from the ramp for 1.1 km, so
  /// entry waits past the Shinonome JCT fork. The fork shows on the banner
  /// once the car has been followed along the route head, and is not
  /// spoken before entry is confirmed.
  /// Coming to the Toyosu entrance, the plan names the Shinonome JCT fork
  /// the car reaches before entry can be confirmed, once; driving on along
  /// the ramp to the fork adds nothing more.
  func testStraightEntranceAnnouncesTheFirstFork() async throws {
    let clock = LiveTestClock()
    let output = WholeShutoRecordingSpeechOutput()
    let drive = try await bayshoreLiveDrive(
      clock: clock,
      output: output,
      entryFacilityID: "shuto.ic.10.toyosu",
      exitFacilityID: "shuto.ic.b.ooi"
    )
    let model = drive.model
    XCTAssertEqual(model.phase, .entryTransition)
    let announcements = output.commands.filter { $0.identity.promptID.hasPrefix("journey.entrance.") }
    XCTAssertEqual(announcements.count, 1)
    XCTAssertEqual(announcements.first?.spokenText, "豊洲入口です。その先、東雲JCTで横浜方面です")
    let corridor = drive.release.navigation.bundle.matcherCorridor
    let edges = Dictionary(uniqueKeysWithValues: corridor.edges.map { ($0.id, $0) })
    let points = corridor.occurrences.sorted { $0.index < $1.index }.prefix(8)
      .compactMap { edges[$0.directedEdgeID] }.flatMap(Self.edgeFixPoints)
    let spokenBefore = output.commands.count
    for (index, point) in points.enumerated() {
      clock.milliseconds += 1_000
      await model.consumeLiveObservationForTesting(
        Self.liveLocationEnvelope(
          id: "straight-entrance.\(index)", coordinate: point.coordinate,
          atMilliseconds: clock.milliseconds, courseDegrees: point.courseDegrees,
          speedMetersPerSecond: 20
        )
      )
    }
    XCTAssertEqual(output.commands.count, spokenBefore)
    model.reset()
  }

  /// A car that drives on past the ramp hears the plan's statement at the
  /// entrance and nothing positional after it.
  func testDrivingOnPastAStraightEntranceHearsOnlyTheAnnouncement() async throws {
    let clock = LiveTestClock()
    let output = WholeShutoRecordingSpeechOutput()
    let drive = try await bayshoreLiveDrive(
      clock: clock,
      output: output,
      entryFacilityID: "shuto.ic.10.toyosu",
      exitFacilityID: "shuto.ic.b.ooi"
    )
    let model = drive.model
    let transition = drive.release.navigation.bundle.runtimePolicy.entryTransition
    let corridor = drive.release.navigation.bundle.matcherCorridor
    let ramp = try XCTUnwrap(
      corridor.edges.first { $0.id == transition.directedEdgeIDs.first }?.coordinates
    )
    let start = ShutoCoordinate(latitude: ramp[0].latitude, longitude: ramp[0].longitude)
    let toward = ShutoCoordinate(latitude: ramp[1].latitude, longitude: ramp[1].longitude)
    let bearing = Self.bearing(from: start, to: toward)
    let length = Self.meters(start, toward)
    let spokenBefore = output.commands.count
    for step in 1...60 {
      clock.milliseconds += 1_000
      let along = Double(step) * 25
      let point = Self.interpolate(
        from: start, to: toward, fraction: along / max(length, 1)
      )
      await model.consumeLiveObservationForTesting(
        Self.liveLocationEnvelope(
          id: "drove-past.\(step)", coordinate: point,
          atMilliseconds: clock.milliseconds, courseDegrees: bearing,
          speedMetersPerSecond: 10
        )
      )
    }
    XCTAssertEqual(output.commands.filter { $0.identity.promptID.hasPrefix("journey.entrance.") }.count, 1)
    XCTAssertTrue(
      output.commands.dropFirst(spokenBefore).allSatisfy { $0.identity.anchorID == "JOURNEY_STATUS" },
      output.commands.dropFirst(spokenBefore).map(\.identity.promptID).joined(separator: " ")
    )
    model.reset()
  }

  func testEntranceAnnouncementCopyChainsTheDecisionInEachLanguage() throws {
    let guidance = ReleasedGuidanceDefinition(
      anchor: GuidanceAnchorDefinition(occurrenceID: "o4", anchorID: "COMMIT", promptID: "p"),
      triggerDistanceMeters: 300,
      frameTemplate: GuidanceFrameTemplate(
        movementOccurrenceID: "o5", decisionZoneID: "z", stage: .commit,
        decisionPointNameJapanese: "東雲JCT",
        localizedDecisionPointNames: [.japanese: "東雲JCT", .simplifiedChinese: "东云 JCT", .english: "Shinonome JCT"],
        maneuver: .branchRight, lanePreparation: .none,
        presentationSource: GuidancePresentationSource(
          routeShields: ["B"], japaneseSignText: "横浜",
          localizedContent: [
            .japanese: LocalizedGuidanceContent(
              displayText: "右方向へ分岐し、湾岸線 横浜方面へ",
              spokenText: "東雲JCTでは右方向へ分岐し、湾岸線 横浜方面へ進んでください",
              spokenForms: ["湾岸線": "わんがんせん"], preservedJapaneseSignText: "横浜"),
            .simplifiedChinese: LocalizedGuidanceContent(
              displayText: "向右分岔，驶往 湾岸线横滨方向",
              spokenText: "在东云 JCT向右分岔，驶往 湾岸线横滨方向",
              spokenForms: ["湾岸线": "湾岸线"], preservedJapaneseSignText: "横浜"),
            .english: LocalizedGuidanceContent(
              displayText: "Branch Right for the Bayshore Route toward Yokohama",
              spokenText: "At Shinonome JCT, branch right for the Bayshore Route toward Yokohama",
              spokenForms: ["Bayshore Route": "Bayshore Route"], preservedJapaneseSignText: "横浜"),
          ]
        )
      )
    )
    XCTAssertEqual(
      WholeShutoProductModel.entranceAnnouncementText(guidance, entranceNameJA: "豊洲", locale: .japanese),
      "豊洲入口です。その先、東雲JCTで横浜方面です"
    )
    XCTAssertEqual(
      WholeShutoProductModel.entranceAnnouncementText(guidance, entranceNameJA: "豊洲", locale: .simplifiedChinese),
      "豊洲 入口。随后在东云 JCT向右分岔，驶往 湾岸线横滨方向"
    )
    XCTAssertEqual(
      WholeShutoProductModel.entranceAnnouncementText(guidance, entranceNameJA: "豊洲", locale: .english),
      "Expressway entrance. Then at Shinonome JCT, branch right for the Bayshore Route toward Yokohama"
    )
  }

  func testFirstForkPastAStraightEntryIsShownNotSpoken() async throws {
    let clock = LiveTestClock()
    let output = WholeShutoRecordingSpeechOutput()
    let drive = try await bayshoreLiveDrive(
      clock: clock,
      output: output,
      entryFacilityID: "shuto.ic.10.toyosu",
      exitFacilityID: "shuto.ic.b.ooi"
    )
    let model = drive.model
    let corridor = drive.release.navigation.bundle.matcherCorridor
    let edges = Dictionary(uniqueKeysWithValues: corridor.edges.map { ($0.id, $0) })
    let fork = try XCTUnwrap(
      drive.release.navigation.bundle.releasedGuidance.first { $0.frameTemplate.decisionPointNameJapanese == "東雲JCT" }
    )
    let forkIndex = try XCTUnwrap(drive.route.routePlan.occurrence(id: fork.frameTemplate.movementOccurrenceID)?.index)
    let points = corridor.occurrences.sorted { $0.index < $1.index }
      .prefix(forkIndex)
      .compactMap { edges[$0.directedEdgeID] }
      .flatMap(Self.edgeFixPoints)
    let spokenBefore = output.commands.count
    var shown: WholeShutoJunctionPrompt?
    for (index, point) in points.enumerated() {
      clock.milliseconds += 1_000
      await model.consumeLiveObservationForTesting(
        Self.liveLocationEnvelope(
          id: "straight-entry.\(index)",
          coordinate: point.coordinate,
          atMilliseconds: clock.milliseconds,
          courseDegrees: point.courseDegrees,
          speedMetersPerSecond: 20
        )
      )
      XCTAssertEqual(model.phase, .entryTransition)
      shown = shown ?? model.entryStretchJunctionPrompt
    }
    XCTAssertEqual(shown?.nameJA, "東雲JCT")
    XCTAssertEqual(output.commands.count, spokenBefore)
    model.reset()
  }

  private func bayshoreLiveDrive(
    clock: LiveTestClock,
    output: any GuidanceSpeechOutput,
    entryFacilityID: String = "shuto.ic.b.rinkaihukutoshin",
    exitFacilityID: String = "shuto.ic.b.daikokufutou"
  ) async throws -> (
    model: WholeShutoProductModel,
    route: ShutoPlannedRoute,
    release: KaidoProductRelease
  ) {
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil,
      liveLocationSource: WholeShutoBackgroundNavigationLocationSource(),
      speechOutput: output,
      nowMillisecondsProvider: { clock.milliseconds }
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6763, longitude: 139.7720)
    )
    model.prepareCustomRouteDraft()
    model.selectCustomEntry(facilityID: entryFacilityID)
    model.selectCustomExit(facilityID: exitFacilityID)
    XCTAssertTrue(model.applyCustomRoute())
    await model.awaitLiveNavigationPreparationForTesting()
    XCTAssertTrue(
      model.canStartLiveNavigation,
      model.liveNavigationBlockerCode ?? "no blocker code"
    )
    let route = try XCTUnwrap(model.selectedRoute)
    let release =
      try ShutoCircuitProductReleaseBuilder
      .buildPlannedRouteRelease(
        context: try ShutoPlannedRouteRuntimeCompiler.NetworkContext(
          database: model.database
        ),
        route: route
      )
    let started = await model.startLiveJourney()
    XCTAssertTrue(started)
    let accessEnd = try XCTUnwrap(model.accessRoute?.coordinates.last)
    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(
        id: "bayshore.access-end",
        coordinate: accessEnd,
        atMilliseconds: clock.milliseconds,
        courseDegrees: Self.bearing(
          from: route.coordinates[0],
          to: route.coordinates[1]
        )
      )
    )
    return (model, route, release)
  }

  /// Two fixes per RoutePlan occurrence, a quarter and three quarters along.
  private static func corridorFixPoints(
    release: KaidoProductRelease,
    where includes: (RouteMatcherOccurrence) -> Bool = { _ in true }
  ) -> [(coordinate: ShutoCoordinate, courseDegrees: Double)] {
    let corridor = release.navigation.bundle.matcherCorridor
    let edges = Dictionary(
      uniqueKeysWithValues: corridor.edges.map { ($0.id, $0) }
    )
    return corridor.occurrences.sorted { $0.index < $1.index }
      .filter(includes)
      .compactMap { edges[$0.directedEdgeID] }
      .flatMap(edgeFixPoints)
  }

  private static func edgeFixPoints(
    _ edge: RouteMatcherDirectedEdge
  ) -> [(coordinate: ShutoCoordinate, courseDegrees: Double)] {
    guard let first = edge.coordinates.first, let last = edge.coordinates.last
    else { return [] }
    let start = ShutoCoordinate(latitude: first.latitude, longitude: first.longitude)
    let end = ShutoCoordinate(latitude: last.latitude, longitude: last.longitude)
    return [0.25, 0.75].map {
      (interpolate(from: start, to: end, fraction: $0), bearing(from: start, to: end))
    }
  }

  func testLiveTunnelGapCoastsPresentationWithoutAdvancingAuthority()
    async throws
  {
    var nowMilliseconds = 1_000
    let output = WholeShutoRecordingSpeechOutput()
    let locationSource = WholeShutoBackgroundNavigationLocationSource()
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil,
      liveLocationSource: locationSource,
      speechOutput: output,
      nowMillisecondsProvider: { nowMilliseconds }
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6275, longitude: 139.7730)
    )
    model.prepareCustomRouteDraft()
    model.selectCustomEntry(
      facilityID: "shuto.ic.b.rinkaihukutoshin"
    )
    model.selectCustomExit(
      facilityID: "shuto.ic.c2.hatsudaiminami"
    )
    XCTAssertTrue(model.applyCustomRoute())
    for _ in 0..<300
    where model.isPreparingLiveNavigation || model.isUpdatingSurfaceRoute
      || !model.canStartLiveNavigation
    {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }
    XCTAssertTrue(
      model.canStartLiveNavigation,
      model.liveNavigationBlockerCode ?? "no blocker code"
    )
    let started = await model.startLiveJourney()
    XCTAssertTrue(started)

    let route = try XCTUnwrap(model.selectedRoute)
    let accessEnd = try XCTUnwrap(model.accessRoute?.coordinates.last)
    let initialCourse = Self.bearing(
      from: route.coordinates[0],
      to: route.coordinates[1]
    )
    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(
        id: "tunnel.access-end",
        coordinate: accessEnd,
        atMilliseconds: nowMilliseconds,
        courseDegrees: initialCourse
      )
    )

    var observationIndex = 0
    for edgeIndex in route.edges.indices {
      let start = route.coordinates[edgeIndex]
      let end = route.coordinates[edgeIndex + 1]
      let course = Self.bearing(from: start, to: end)
      for fraction in [0.25, 0.75] {
        observationIndex += 1
        nowMilliseconds += 1_000
        let coordinate = ShutoCoordinate(
          latitude: start.latitude
            + (end.latitude - start.latitude) * fraction,
          longitude: start.longitude
            + (end.longitude - start.longitude) * fraction
        )
        await model.consumeLiveObservationForTesting(
          Self.liveLocationEnvelope(
            id: "tunnel.route.\(observationIndex)",
            coordinate: coordinate,
            atMilliseconds: nowMilliseconds,
            courseDegrees: course,
            speedMetersPerSecond: 18
          )
        )
        if model.phase == .expressway,
          model.liveLocationState == .available,
          model.positionState == .tunnelEstimated,
          model.runtimeOccurrenceID != nil
        {
          break
        }
      }
      if model.phase == .expressway,
        model.liveLocationState == .available,
        model.positionState == .tunnelEstimated,
        model.runtimeOccurrenceID != nil
      {
        break
      }
    }

    XCTAssertEqual(model.phase, .expressway)
    XCTAssertEqual(model.liveLocationState, .available)
    XCTAssertEqual(model.positionState, .tunnelEstimated)
    let authoritativeOccurrence = try XCTUnwrap(model.runtimeOccurrenceID)
    let authoritativeProgress = model.progressFraction
    let authoritativeCoordinate = try XCTUnwrap(model.currentCoordinate)
    let spokenPromptCount = output.commands.filter { $0.identity.anchorID != "JOURNEY_STATUS" }
      .count

    nowMilliseconds += WholeShutoProductModel.liveLocationStaleAfterMilliseconds
    model.evaluateLiveLocationFreshness(
      atMilliseconds: nowMilliseconds
    )

    XCTAssertEqual(model.liveLocationState, .stale)
    XCTAssertEqual(model.positionState, .tunnelEstimated)
    XCTAssertEqual(model.runtimeOccurrenceID, authoritativeOccurrence)
    XCTAssertEqual(model.progressFraction, authoritativeProgress)
    XCTAssertGreaterThan(
      try XCTUnwrap(model.tunnelEstimatedProgressFraction),
      authoritativeProgress
    )
    XCTAssertGreaterThan(
      try XCTUnwrap(model.tunnelEstimateUncertaintyMeters),
      TunnelPositionEstimator.minimumUncertaintyRadiusMeters
    )
    XCTAssertNotEqual(model.currentCoordinate, authoritativeCoordinate)
    XCTAssertEqual(
      output.commands.filter { $0.identity.anchorID != "JOURNEY_STATUS" }.count, spokenPromptCount)
    XCTAssertEqual(
      output.commands.filter { $0.identity.promptID.contains("positionLost") }.count, 1)

    nowMilliseconds += 1_000
    let unrelatedRawCoordinate = ShutoCoordinate(
      latitude: 35.0,
      longitude: 140.0
    )
    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(
        id: "tunnel.weak-unrelated-fix",
        coordinate: unrelatedRawCoordinate,
        atMilliseconds: nowMilliseconds,
        courseDegrees: 0,
        speedMetersPerSecond: 18
      )
    )

    XCTAssertNotEqual(model.currentCoordinate, unrelatedRawCoordinate)
    XCTAssertEqual(model.runtimeOccurrenceID, authoritativeOccurrence)
    XCTAssertEqual(model.progressFraction, authoritativeProgress)
    XCTAssertEqual(
      output.commands.filter { $0.identity.anchorID != "JOURNEY_STATUS" }.count, spokenPromptCount)
    let resumeIndex = try XCTUnwrap(
      route.routePlan.occurrence(id: authoritativeOccurrence)
    ).index
    // Resume the real live-observation path after a multi-minute outage.
    nowMilliseconds += 180_000
    for edgeIndex in resumeIndex..<route.edges.count {
      let start = route.coordinates[edgeIndex]
      let end = route.coordinates[edgeIndex + 1]
      nowMilliseconds += 1_000
      await model.consumeLiveObservationForTesting(
        Self.liveLocationEnvelope(
          id: "tunnel.return.\(edgeIndex)",
          coordinate: ShutoCoordinate(
            latitude: (start.latitude + end.latitude) / 2,
            longitude: (start.longitude + end.longitude) / 2
          ),
          atMilliseconds: nowMilliseconds,
          courseDegrees: Self.bearing(from: start, to: end),
          speedMetersPerSecond: 18
        )
      )
      if model.liveLocationState == .available,
        model.progressFraction > authoritativeProgress + 0.01
      {
        break
      }
    }
    XCTAssertTrue(model.isPlaying)
    XCTAssertEqual(model.liveLocationState, .available)
    XCTAssertGreaterThan(model.progressFraction, authoritativeProgress + 0.01)
    model.reset()
  }

  func testLiveJourneyContinuesWhenScreenLocksAndStopsWhenEnded()
    async throws
  {
    let locationSource = WholeShutoBackgroundNavigationLocationSource()
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoInstructionSurfaceRouteResolver(),
      checkpointStore: nil,
      liveLocationSource: locationSource,
      speechOutput: WholeShutoRecordingSpeechOutput()
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6812, longitude: 139.7671)
    )
    model.prepareCustomRouteDraft()
    model.selectCustomEntry(facilityID: "shuto.ic.b.urayasu")
    model.selectCustomExit(facilityID: "shuto.ic.9.fukudumi")
    XCTAssertTrue(model.applyCustomRoute())
    for _ in 0..<300
    where model.isPreparingLiveNavigation || model.isUpdatingSurfaceRoute {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }

    let started = await model.startLiveJourney()
    XCTAssertTrue(started)
    XCTAssertTrue(model.isPlaying)
    XCTAssertEqual(locationSource.startCount, 1)
    XCTAssertTrue(locationSource.backgroundNavigationEnabled)

    await model.handleScenePhase(.inactive)
    await model.handleScenePhase(.background)

    XCTAssertTrue(model.isLiveDrive)
    XCTAssertTrue(model.isPlaying)
    XCTAssertNotEqual(model.liveLocationState, .resumeRequired)
    XCTAssertNotEqual(model.liveLocationIssueCode, "LIVE_RESUME_REQUIRED")
    XCTAssertEqual(locationSource.startCount, 1)
    XCTAssertEqual(locationSource.stopCount, 0)
    XCTAssertTrue(locationSource.backgroundNavigationEnabled)

    await model.handleScenePhase(.active)
    XCTAssertTrue(model.isPlaying)
    XCTAssertEqual(locationSource.startCount, 1)

    locationSource.delegate?.foregroundNavigationLocationSource(
      locationSource, didFailWithCode: "CORE_LOCATION_FAILURE", isTransient: false
    )
    XCTAssertFalse(model.isPlaying)
    XCTAssertEqual(model.liveLocationState, .failed)
    XCTAssertEqual(locationSource.stopCount, 1)
    let resumed = await model.resumeLiveJourney()
    XCTAssertTrue(resumed)
    XCTAssertTrue(model.isPlaying)
    XCTAssertEqual(locationSource.startCount, 2)
    XCTAssertTrue(locationSource.backgroundNavigationEnabled)

    model.reset()
    for _ in 0..<100 where locationSource.stopCount == 1 {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertEqual(locationSource.stopCount, 2)
    XCTAssertFalse(locationSource.backgroundNavigationEnabled)
  }

  func testFirstLocationPermissionRoundTripStartsTheSameLiveJourney()
    async throws
  {
    let locationSource = WholeShutoBackgroundNavigationLocationSource(
      authorizationStatus: .notDetermined
    )
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoInstructionSurfaceRouteResolver(),
      checkpointStore: nil,
      liveLocationSource: locationSource,
      speechOutput: WholeShutoRecordingSpeechOutput()
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6812, longitude: 139.7671)
    )
    model.prepareCustomRouteDraft()
    model.selectCustomEntry(facilityID: "shuto.ic.b.urayasu")
    model.selectCustomExit(facilityID: "shuto.ic.9.fukudumi")
    XCTAssertTrue(model.applyCustomRoute())
    for _ in 0..<300
    where model.isPreparingLiveNavigation || model.isUpdatingSurfaceRoute {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }

    let started = await model.startLiveJourney()
    XCTAssertTrue(started)
    XCTAssertTrue(model.isPlaying)
    XCTAssertEqual(model.liveLocationState, .awaitingAuthorization)
    XCTAssertEqual(locationSource.authorizationRequestCount, 1)
    XCTAssertEqual(locationSource.startCount, 0)

    await model.handleScenePhase(.inactive)
    locationSource.deliverAuthorization(.authorizedWhenInUse)
    await model.handleScenePhase(.active)

    XCTAssertTrue(model.isPlaying)
    XCTAssertEqual(model.liveLocationState, .acquiring)
    XCTAssertEqual(locationSource.startCount, 1)
    XCTAssertTrue(locationSource.backgroundNavigationEnabled)
    model.reset()
  }

  func testOnDeviceRouteAuthorityAdmitsYokohamaRouteAfterCompleteReview()
    throws
  {
    let database = try WholeShutoNetworkCatalog.bundled()
    let route = try ShutoRoutePlanner(database: database).plan(
      entryFacilityID: "shuto.ic.k1.yokohamakouen",
      exitFacilityID: "shuto.ic.k7-yokohama-hokusei.yokohamaaoba"
    )
    let authority = try WholeShutoRouteReleaseAuthority(database: database)

    switch authority.resolve(route: route) {
    case .available(let admission):
      XCTAssertEqual(admission.core.selectedRoutePlan, route.routePlan)
    case .unavailable(let code):
      XCTFail("Expected live admission after complete review, got \(code)")
    }
  }

  func testCancelledRouteAuthorityResolutionAdmitsNothing() async throws {
    let database = try WholeShutoNetworkCatalog.bundled()
    let route = try ShutoRoutePlanner(database: database).plan(
      entryFacilityID: "shuto.ic.k1.yokohamakouen",
      exitFacilityID: "shuto.ic.k7-yokohama-hokusei.yokohamaaoba"
    )
    let authority = try WholeShutoRouteReleaseAuthority(database: database)

    let resolution = await Task.detached {
      withUnsafeCurrentTask { $0?.cancel() }
      return authority.resolve(route: route)
    }.value

    guard case .unavailable = resolution else {
      return XCTFail("A replaced route must not finish building its release")
    }
  }

  func testReplacedRouteStopsItsLivePreparationAndNeverPublishes()
    async throws
  {
    let hold = ReplacedRouteAdmissionHold()
    let model = WholeShutoProductModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil,
      liveJourneyAdmissionResolver: { hold.resolve($0) }
    )
    model.preparePreviewJourney()
    XCTAssertGreaterThan(model.recommendations.count, 1)
    let firstRoute = try XCTUnwrap(model.selectedRoute)
    hold.holdRoute(planID: firstRoute.routePlan.id)

    model.selectRecommendation(at: 1)
    XCTAssertNotEqual(model.selectedRoute, firstRoute)
    for _ in 0..<200
    where model.isPreparingLiveNavigation || model.isUpdatingSurfaceRoute
      || !hold.heldFinished
    {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }

    XCTAssertTrue(hold.heldFinished)
    XCTAssertTrue(hold.heldSawCancellation)
    XCTAssertEqual(
      model.liveNavigationBlockerCode,
      ReplacedRouteAdmissionHold.laterRouteCode
    )
  }

  func testOnDeviceRouteAuthorityAdmitsRinkaiToHatsudaiWithoutPredecessor()
    throws
  {
    let database = try WholeShutoNetworkCatalog.bundled()
    let route = try ShutoRoutePlanner(database: database).plan(
      entryFacilityID: "shuto.ic.b.rinkaihukutoshin",
      exitFacilityID: "shuto.ic.c2.hatsudaiminami"
    )
    let reconstructed = try ShutoRoutePlanner(database: database)
      .restore(routePlan: route.routePlan)
    XCTAssertEqual(reconstructed, route)
    let artifact =
      try ShutoCircuitProductReleaseBuilder
      .buildPlannedRouteArtifact(
        database: database,
        route: reconstructed
      )
    let release = try KaidoProductRelease(artifact: artifact)
    XCTAssertEqual(
      release.navigation.bundle.runtimePolicy.entryTransition
        .directedEdgeIDs,
      Array(route.edges.prefix(2).map(\.edgeID))
    )
    XCTAssertEqual(
      release.navigation.bundle.runtimePolicy.entryTransition
        .firstRouteOccurrenceID,
      route.routePlan.occurrences.first?.id
    )
    let core = try KaidoLiveJourneyAdmission(
      release: release,
      selectedRoutePlan: route.routePlan,
      journeyPlan: JourneyPlanCompiler.expresswayOnly(release: release)
    )
    XCTAssertEqual(core.selectedRoutePlan, route.routePlan)
    let authority = try WholeShutoRouteReleaseAuthority(database: database)

    switch authority.resolve(route: route) {
    case .available(let admission):
      XCTAssertEqual(admission.core.selectedRoutePlan, route.routePlan)
    case .unavailable(let code):
      XCTFail("Expected live admission, got \(code)")
    }
  }

  func testFirstLaunchInterfaceLanguageFollowsTheDevice() {
    XCTAssertEqual(
      KaidoReleaseLocale.matchingPreferredLanguage(["ja-JP", "en-US"]),
      .japanese
    )
    XCTAssertEqual(
      KaidoReleaseLocale.matchingPreferredLanguage(["zh-Hans-CN"]),
      .simplifiedChinese
    )
    // Traditional Chinese is not authored: English beats a script mismatch.
    XCTAssertEqual(
      KaidoReleaseLocale.matchingPreferredLanguage(["zh-Hant-TW"]),
      .english
    )
    XCTAssertEqual(
      KaidoReleaseLocale.matchingPreferredLanguage(["de-DE", "ja-JP"]),
      .japanese
    )
    XCTAssertEqual(
      KaidoReleaseLocale.matchingPreferredLanguage(["ko-KR"]),
      .english
    )
  }

  func testCustomRouteFromTheHomeCatalogEndsAtItsExit() {
    let model = WholeShutoProductModel(checkpointStore: nil)
    // Tokyo Tower: the nearest enterable facility seeds the draft.
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6586, longitude: 139.7454)
    )
    model.prepareCustomRouteDraft()

    XCTAssertNotNil(model.customEntryFacilityID)
    XCTAssertNotNil(model.customExitFacilityID)
    XCTAssertNotNil(model.customDraftRoute)

    XCTAssertTrue(model.applyCustomRoute())
    XCTAssertEqual(model.phase, .review)
    XCTAssertTrue(model.isCustomRouteSelected)
    XCTAssertEqual(
      model.destination?.coordinate,
      model.selectedRoute?.coordinates.last
    )
  }

  func testHomeCustomRouteOffersOriginRankedEntryAndExitCandidatesBeforeApply() {
    let model = WholeShutoProductModel(checkpointStore: nil)
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6586, longitude: 139.7454)
    )

    model.prepareCustomRouteDraft()

    XCTAssertNil(model.destination)
    XCTAssertGreaterThan(model.customEntryCandidates.count, 8)
    XCTAssertGreaterThan(model.customExitCandidates.count, 8)
    XCTAssertEqual(
      model.customEntryCandidates.first?.facilityID,
      model.customEntryFacilityID
    )
    XCTAssertEqual(
      model.customExitCandidates.first?.facilityID,
      model.customExitFacilityID
    )
  }

  func testSelectedOriginCoordinateIsReusedWithoutAnotherPlaceLookup() async {
    let resolver = WholeShutoRecordingPlaceResolver()
    let model = WholeShutoProductModel(
      placeResolver: resolver,
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    let selectedOrigin = WholeShutoPlace(
      title: "東京駅丸の内口",
      coordinate: ShutoCoordinate(
        latitude: 35.6812,
        longitude: 139.7649
      )
    )
    model.selectOriginPreview(selectedOrigin)
    model.destinationQuery = "横浜中華街"

    model.planJourney()
    for _ in 0..<1_000 where model.isPlanning {
      await Task.yield()
    }

    XCTAssertEqual(resolver.queries, ["横浜中華街"])
    XCTAssertEqual(model.origin, selectedOrigin)
    XCTAssertEqual(model.phase, .review)
  }

  func testTypedManualOriginCanOpenTheCustomRouteFlow() async {
    let resolver = WholeShutoRecordingPlaceResolver()
    let model = WholeShutoProductModel(
      placeResolver: resolver,
      checkpointStore: nil
    )
    model.originQuery = "東京駅"

    let resolved = await model.resolveTypedOriginPreview()
    XCTAssertTrue(resolved)
    model.prepareCustomRouteDraft()

    XCTAssertEqual(resolver.queries, ["東京駅"])
    XCTAssertTrue(model.hasSelectedOriginPreview)
    XCTAssertFalse(model.customEntryCandidates.isEmpty)
    XCTAssertFalse(model.customExitCandidates.isEmpty)
  }

  func testRecommendedAndCustomRoutesExposeCurrentTariffBand() throws {
    let model = WholeShutoProductModel(checkpointStore: nil)
    model.preparePreviewJourney()
    let recommendedBand = try XCTUnwrap(model.selectedTariffBand)
    XCTAssertGreaterThan(recommendedBand.quotedYen, 0)
    XCTAssertEqual(
      model.savedRouteTemplateParameters,
      [
        "source": "RECOMMENDATION",
        "preference": model.selectedRoute?.preference.rawValue ?? "",
      ]
    )

    let customModel = WholeShutoProductModel(checkpointStore: nil)
    customModel.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6586, longitude: 139.7454)
    )
    customModel.prepareCustomRouteDraft()
    XCTAssertTrue(customModel.applyCustomRoute())
    let customBand = try XCTUnwrap(customModel.selectedTariffBand)
    XCTAssertGreaterThan(customBand.quotedYen, 0)
    XCTAssertEqual(
      customModel.savedRouteTemplateParameters["source"],
      "CUSTOM"
    )
  }

  func testTariffReviewCheckpointDoesNotRestoreStaleOrigin() throws {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: store)
    model.preparePreviewJourney()
    _ = try XCTUnwrap(model.selectedTariffBand)

    let restored = WholeShutoProductModel(
      database: model.database,
      checkpointStore: store
    )

    XCTAssertEqual(restored.phase, .planning)
    XCTAssertNil(restored.selectedTariffBand)
    XCTAssertNil(restored.checkpointIssueCode)
  }

  func testFreshlySavedRecommendedRouteReopensOnCurrentSnapshot()
    throws
  {
    let source = WholeShutoProductModel(checkpointStore: nil)
    source.preparePreviewJourney()
    let route = try XCTUnwrap(source.selectedRoute)
    XCTAssertEqual(
      route.routePlan.id,
      "shuto.shuto.ic.c1.ginza.shuto.ic.k1.yokohamakouen.recommended"
    )
    // 789 before the 2026-10-12 facility review: 銀座 and 横浜公園 now start
    // and end on their own ramps.
    XCTAssertEqual(route.routePlan.occurrences.count, 706)
    XCTAssertEqual(
      source.savedRouteTemplateParameters,
      [
        "source": "RECOMMENDATION",
        "preference": "RECOMMENDED",
      ]
    )
    let restoredRoute = try source.planner.restore(
      routePlan: route.routePlan,
      preference: route.preference
    )
    XCTAssertEqual(restoredRoute.routePlan, route.routePlan)
    XCTAssertNoThrow(
      try ShutoPlannedRouteRuntimeCompiler.compile(
        database: source.database,
        route: restoredRoute
      )
    )

    let libraryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "kaido-saved-recommended-\(UUID().uuidString)",
        isDirectory: true
      )
    defer {
      try? FileManager.default.removeItem(at: libraryDirectory)
    }
    let libraryStore = try FileSavedRouteLibraryStore(
      directoryURL: libraryDirectory
    )
    let library = SavedRouteLibraryModel(
      store: libraryStore,
      foregroundEntries: [],
      recordIDProvider: { "saved-route.recommended-preview" },
      savedAtProvider: { "2026-08-12T12:00:00Z" }
    )
    library.save(
      routePlan: route.routePlan,
      displayName: "Tokyo Yokohama Snapshot",
      evidenceState: .communityCandidate,
      templateParameters: source.savedRouteTemplateParameters
    )
    XCTAssertNil(library.lastErrorCode)

    let reloadedStore = try FileSavedRouteLibraryStore(
      directoryURL: libraryDirectory
    )
    let reloadedLibrary = SavedRouteLibraryModel(
      store: reloadedStore,
      foregroundEntries: []
    )
    let record = try XCTUnwrap(reloadedLibrary.records.first)
    XCTAssertEqual(record.document.routePlan, route.routePlan)
    XCTAssertEqual(
      record.document.templateParameters,
      source.savedRouteTemplateParameters
    )

    let reopened = WholeShutoProductModel(
      database: source.database,
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    XCTAssertEqual(
      reopened.savedRouteAvailability(record),
      .currentSnapshot(source.database.networkSnapshotID)
    )
    XCTAssertTrue(
      reopened.openSavedRoute(
        record,
        origin: source.origin?.coordinate
      )
    )
    XCTAssertEqual(reopened.phase, .review)
    XCTAssertEqual(reopened.selectedRoute?.routePlan, route.routePlan)
    XCTAssertFalse(reopened.isCircuitRouteSelected)
    XCTAssertFalse(reopened.isCustomRouteSelected)
    XCTAssertEqual(
      reopened.savedRouteTemplateParameters,
      source.savedRouteTemplateParameters
    )
  }

  func testSavedCircuitRouteOpensExactRepeatedPlanOnCurrentSnapshot()
    async throws
  {
    let source = WholeShutoProductModel(checkpointStore: nil)
    let circuitRoute = try source.planner.planCircuit(
      circuit: .c2InnerWithBayshore,
      entryFacilityID: "shuto.ic.c2.hatsudaiminami",
      exitFacilityID: "shuto.ic.c2.tomigaya",
      laps: 2
    )
    let templateParameters = [
      "source": "CIRCUIT",
      "preference": circuitRoute.preference.rawValue,
      "circuit_id": ShutoCircuitDefinition.c2InnerWithBayshore.circuitID,
      "laps": "2",
    ]
    let record = Self.savedRouteRecord(
      circuitRoute.routePlan,
      templateParameters: templateParameters
    )
    let model = WholeShutoProductModel(
      database: source.database,
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )

    XCTAssertEqual(
      model.savedRouteAvailability(record),
      .currentSnapshot(source.database.networkSnapshotID)
    )
    let origin = ShutoCoordinate(
      latitude: 35.6798,
      longitude: 139.6862
    )
    XCTAssertTrue(model.openSavedRoute(record, origin: origin))
    for _ in 0..<1_000 where model.isUpdatingSurfaceRoute {
      await Task.yield()
    }

    XCTAssertEqual(model.phase, .review)
    XCTAssertTrue(model.isCircuitRouteSelected)
    XCTAssertFalse(model.isCustomRouteSelected)
    XCTAssertEqual(
      model.selectedCircuit,
      .c2InnerWithBayshore
    )
    XCTAssertEqual(model.circuitLaps, 2)
    XCTAssertEqual(model.savedRouteTemplateParameters, templateParameters)
    XCTAssertEqual(model.selectedRoute?.routePlan, circuitRoute.routePlan)
    XCTAssertEqual(model.origin?.coordinate, origin)
    XCTAssertEqual(
      model.destination?.coordinate,
      origin
    )
    XCTAssertEqual(
      model.destination?.title,
      model.origin?.title
    )
    XCTAssertNotNil(model.accessRoute)
    XCTAssertNotNil(model.egressRoute)
    XCTAssertNotNil(model.selectedTariffBand)
    let edgeIDs = try XCTUnwrap(model.selectedRoute?.edges.map(\.edgeID))
    XCTAssertLessThan(Set(edgeIDs).count, edgeIDs.count)
    XCTAssertFalse(model.canStartLiveNavigation)
  }

  func testSavedCircuitRouteResavePreservesTemplateProvenance()
    throws
  {
    let source = WholeShutoProductModel(checkpointStore: nil)
    let circuitRoute = try source.planner.planCircuit(
      circuit: .c2InnerWithBayshore,
      entryFacilityID: "shuto.ic.c2.hatsudaiminami",
      exitFacilityID: "shuto.ic.c2.tomigaya",
      laps: 2
    )
    let templateParameters = [
      "source": "CIRCUIT",
      "preference": circuitRoute.preference.rawValue,
      "circuit_id": ShutoCircuitDefinition.c2InnerWithBayshore.circuitID,
      "laps": "2",
      "variant": "NIGHT",
    ]
    let record = Self.savedRouteRecord(
      circuitRoute.routePlan,
      templateParameters: templateParameters
    )
    let model = WholeShutoProductModel(
      database: source.database,
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )

    XCTAssertTrue(
      model.openSavedRoute(
        record,
        origin: ShutoCoordinate(latitude: 35.68, longitude: 139.69)
      )
    )

    let libraryStore = WholeShutoMemorySavedRouteLibraryStore()
    let library = SavedRouteLibraryModel(
      store: libraryStore,
      foregroundEntries: [],
      recordIDProvider: { "saved-route.resaved-circuit" },
      savedAtProvider: { "2026-08-12T12:00:00Z" }
    )
    library.save(
      routePlan: model.selectedRoute?.routePlan,
      displayName: "Resaved circuit",
      evidenceState: .communityCandidate,
      templateParameters: model.savedRouteTemplateParameters
    )

    let resaved = try XCTUnwrap(library.records.first)
    XCTAssertEqual(resaved.document.routePlan, circuitRoute.routePlan)
    XCTAssertEqual(
      resaved.document.templateParameters,
      templateParameters
    )
    XCTAssertNil(library.lastErrorCode)
  }

  func testSavedCircuitMetadataMustMatchTheExactCircuitPlan() throws {
    let source = WholeShutoProductModel(checkpointStore: nil)
    let circuit = ShutoCircuitDefinition.c2InnerWithBayshore
    let circuitRoute = try source.planner.planCircuit(
      circuit: circuit,
      entryFacilityID: "shuto.ic.c2.hatsudaiminami",
      exitFacilityID: "shuto.ic.c2.tomigaya",
      laps: 2
    )
    let preference = circuitRoute.preference.rawValue
    let invalidParameters = [
      [
        "source": "UNKNOWN",
        "preference": preference,
      ],
      [
        "source": "CIRCUIT",
        "preference": preference,
        "circuit_id": circuit.circuitID,
      ],
      [
        "source": "CIRCUIT",
        "preference": preference,
        "circuit_id": "shuto.circuit.unknown",
        "laps": "2",
      ],
      [
        "source": "CIRCUIT",
        "preference": preference,
        "circuit_id": circuit.circuitID,
        "laps": "invalid",
      ],
      [
        "source": "CIRCUIT",
        "preference": preference,
        "circuit_id": circuit.circuitID,
        "laps": "1",
      ],
      [
        "source": "CUSTOM",
        "preference": preference,
        "circuit_id": circuit.circuitID,
        "laps": "2",
      ],
    ]

    for parameters in invalidParameters {
      let record = Self.savedRouteRecord(
        circuitRoute.routePlan,
        templateParameters: parameters
      )
      let model = WholeShutoProductModel(
        database: source.database,
        checkpointStore: nil
      )

      XCTAssertEqual(
        model.savedRouteAvailability(record),
        .invalid("SAVED_ROUTE_CURRENT_SNAPSHOT_INVALID")
      )
      XCTAssertFalse(
        model.openSavedRoute(
          record,
          origin: ShutoCoordinate(latitude: 35.68, longitude: 139.69)
        )
      )
      XCTAssertEqual(model.phase, .planning)
      XCTAssertNil(model.selectedRoute)
      XCTAssertEqual(
        model.failureCode,
        "SAVED_ROUTE_CURRENT_SNAPSHOT_INVALID"
      )
    }
  }

  func testSavedRouteSnapshotMismatchCannotOpen() throws {
    let source = WholeShutoProductModel(checkpointStore: nil)
    source.preparePreviewJourney()
    let plan = try XCTUnwrap(source.selectedRoute?.routePlan)
    let driftedPlan = RoutePlan(
      id: plan.id,
      networkSnapshotID: "shuto.future-snapshot",
      entryFacilityID: plan.entryFacilityID,
      exitFacilityID: plan.exitFacilityID,
      recoveryPolicy: plan.recoveryPolicy,
      actualDistanceKM: plan.actualDistanceKM,
      occurrences: plan.occurrences
    )
    let record = Self.savedRouteRecord(driftedPlan)
    let model = WholeShutoProductModel(
      database: source.database,
      checkpointStore: nil
    )

    XCTAssertEqual(model.savedRouteAvailability(record), .unavailable)
    XCTAssertFalse(
      model.openSavedRoute(
        record,
        origin: ShutoCoordinate(latitude: 35.68, longitude: 139.76)
      )
    )
    XCTAssertEqual(model.phase, .planning)
    XCTAssertEqual(
      model.failureCode,
      "SAVED_ROUTE_NETWORK_SNAPSHOT_MISMATCH"
    )
  }

  func testSavedRepeatedRouteSimulationRestoresExactProgress()
    async throws
  {
    let store = WholeShutoMemoryCheckpointStore()
    let source = WholeShutoProductModel(checkpointStore: nil)
    let circuitRoute = try source.planner.planCircuit(
      circuit: .c2InnerWithBayshore,
      entryFacilityID: "shuto.ic.c2.hatsudaiminami",
      exitFacilityID: "shuto.ic.c2.tomigaya",
      laps: 2
    )
    let record = Self.savedRouteRecord(
      circuitRoute.routePlan,
      templateParameters: [
        "source": "CIRCUIT",
        "preference": circuitRoute.preference.rawValue,
        "circuit_id": ShutoCircuitDefinition.c2InnerWithBayshore.circuitID,
        "laps": "2",
      ]
    )
    let model = WholeShutoProductModel(
      database: source.database,
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: store
    )
    XCTAssertTrue(
      model.openSavedRoute(
        record,
        origin: ShutoCoordinate(latitude: 35.68, longitude: 139.69)
      )
    )
    for _ in 0..<1_000 where model.isUpdatingSurfaceRoute {
      await Task.yield()
    }
    model.startNavigationSimulation()
    _ = await model.pausePlayback()
    await advance(
      model,
      until: {
        $0.phase == .expressway && $0.progressFraction > 0.02
      },
      maximumTicks: 1_000
    )
    let expectedProgress = model.progressFraction
    let expectedOccurrenceID = try XCTUnwrap(model.runtimeOccurrenceID)
    XCTAssertEqual(model.selectedRoute?.routePlan, circuitRoute.routePlan)
    await model.handleScenePhase(.background)

    let restored = WholeShutoProductModel(
      database: source.database,
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: store
    )

    XCTAssertEqual(restored.phase, .expressway)
    XCTAssertEqual(restored.selectedRoute?.routePlan, circuitRoute.routePlan)
    XCTAssertEqual(restored.runtimeOccurrenceID, expectedOccurrenceID)
    XCTAssertEqual(restored.progressFraction, expectedProgress)
    XCTAssertFalse(restored.isCustomRouteSelected)
    XCTAssertTrue(restored.isCircuitRouteSelected)
    XCTAssertEqual(restored.selectedCircuit, .c2InnerWithBayshore)
    XCTAssertEqual(restored.circuitLaps, 2)
    XCTAssertTrue(restored.restoredFromCheckpoint)
    XCTAssertNil(restored.failureCode)
  }

  func testCircuitSelectionDerivesThePairingFromOrigin() async {
    let suiteName = UUID().uuidString
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let model = WholeShutoProductModel(checkpointStore: nil, driveRecordPreferenceStore: defaults)
    // Near Hatsudai, west side of the C2 loop.
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6798, longitude: 139.6862)
    )

    model.selectCircuit(.c2InnerWithBayshore)
    await waitForCircuitPairing(model)

    XCTAssertEqual(
      model.selectedCircuit?.circuitID,
      "shuto.circuit.c2-inner-bayshore"
    )
    XCTAssertEqual(model.circuitLaps, 1)
    // The nearest legal start is the loop's own Hatsudai-minami ramp; the
    // exit is derived too — the driver never assembles a pairing. The
    // Hatsudai radial entrance serves only Route 4 down and cannot reach
    // the loop; it qualified only while Hatagaya's up ramp was bound to it.
    XCTAssertEqual(
      model.circuitEntryFacilityID,
      "shuto.ic.c2.hatsudaiminami"
    )
    XCTAssertNotNil(model.circuitExitFacilityID)
    XCTAssertEqual(model.circuitPairingBand?.quotedYen, 300)
    // Radial entrances that legally join the loop are first-class
    // candidates alongside the loop's own inner ramps.
    XCTAssertTrue(
      model.circuitEntranceCandidates.allSatisfy { $0.canEnter }
    )
  }

  func testReleasedC1CatalogRecommendsTheNearbyRoute4RampFromHatsudai() async {
    let suiteName = UUID().uuidString
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil,
      driveRecordPreferenceStore: defaults
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6798, longitude: 139.6862)
    )

    model.selectCircuit(.c1Inner)
    await waitForCircuitPairing(model)

    // Yoyogi, 0.7 km away, joins C1 after 5.3 km of Route 4. Hatsudai-minami
    // is nearer but reaches C1 only after 8.9 km of C2 and Route 4, and its
    // minimum-band exit back at Tomigaya sat 40 km past the lap. The Route 4
    // Hatsudai entrance serves only the down carriageway, away from C1.
    XCTAssertEqual(
      model.circuitEntryFacilityID,
      "shuto.ic.4.yoyogi"
    )
    XCTAssertNotEqual(
      model.circuitEntryFacilityID,
      ShutoCircuitProductReleaseBuilder.entryFacilityID
    )
    // The loop returns to Hatsudai: the final lap ends where Route 4 down
    // branches off at Miyakezaka and leaves at Gaien, the way it came, at
    // the minimum band instead of Kasumigaseki on the course.
    XCTAssertEqual(model.circuitExitFacilityID, "shuto.ic.4.gaien")
    XCTAssertEqual(model.circuitPairingBand, .minimum(yen: 300))
    XCTAssertTrue(model.startCircuitJourney())
    await waitForLiveNavigationPreparation(model)
    XCTAssertEqual(model.phase, .review)
    XCTAssertTrue(model.canStartLiveNavigation)
    XCTAssertNil(model.liveNavigationBlockerCode)
  }

  private func waitForCircuitPairing(
    _ model: WholeShutoProductModel
  ) async {
    // A circuit that ends inside a PA never resolves an exit.
    for _ in 0..<200
    where model.isResolvingCircuitPairing
      || (model.circuitExitFacilityID == nil
        && model.selectedCircuit?.defaultDestinationParkingAreaID == nil)
    {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }
  }

  private func waitForLiveNavigationPreparation(
    _ model: WholeShutoProductModel
  ) async {
    for _ in 0..<1_000
    where model.isPreparingLiveNavigation
      || !model.canStartLiveNavigation
    {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }
  }

  func testCircuitLapControlFollowsPlannerRange() {
    let model = WholeShutoProductModel(checkpointStore: nil)
    let range = ShutoCircuitDefinition.loopLapRange

    model.selectCircuit(.c2InnerWithBayshore)
    XCTAssertEqual(model.circuitLaps, range.lowerBound)

    model.selectCircuitLaps(range.lowerBound - 1)
    XCTAssertEqual(model.circuitLaps, range.lowerBound)

    model.selectCircuitLaps(range.upperBound)
    XCTAssertEqual(model.circuitLaps, range.upperBound)

    model.selectCircuitLaps(range.upperBound + 1)
    XCTAssertEqual(model.circuitLaps, range.upperBound)

    model.selectCircuit(.scenicGrandTour)
    XCTAssertEqual(model.circuitLaps, 1)
    model.selectCircuitLaps(2)
    XCTAssertEqual(model.circuitLaps, 1)
  }

  func testCircuitSelectionWaitsForOriginBeforeRankingEntrances() async {
    let model = WholeShutoProductModel(checkpointStore: nil)

    model.selectCircuit(.c1Inner)
    await Task.yield()

    XCTAssertTrue(model.circuitEntranceCandidates.isEmpty)
    XCTAssertNil(model.circuitEntryFacilityID)
    XCTAssertNil(model.circuitExitFacilityID)
    XCTAssertFalse(model.isResolvingCircuitPairing)

    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6586, longitude: 139.7454)
    )
    model.refreshCircuitEntrances()
    await waitForCircuitPairing(model)

    XCTAssertFalse(model.circuitEntranceCandidates.isEmpty)
    XCTAssertNotNil(model.circuitEntryFacilityID)
    XCTAssertNotNil(model.circuitExitFacilityID)
  }

  func testCircuitTapWithAKnownLocationResolvesThePairingOnce() async {
    let suiteName = UUID().uuidString
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let model = WholeShutoProductModel(
      checkpointStore: nil,
      driveRecordPreferenceStore: defaults
    )
    let hatsudai = ShutoCoordinate(latitude: 35.6798, longitude: 139.6862)
    model.selectCurrentOrigin(hatsudai)
    var resolutionsStarted = 0
    let subscription = model.$isResolvingCircuitPairing.dropFirst().sink {
      if $0 { resolutionsStarted += 1 }
    }
    defer { subscription.cancel() }

    // What a circuit card does when the planning location is measured.
    model.selectCircuit(.c1Inner)
    model.selectCurrentOrigin(hatsudai)
    model.refreshCircuitEntrances()
    await waitForCircuitPairing(model)

    XCTAssertEqual(resolutionsStarted, 1)
    XCTAssertEqual(model.circuitEntryFacilityID, "shuto.ic.4.yoyogi")
  }

  func testAMovedOriginRestartsAResolvingPairing() async {
    let suiteName = UUID().uuidString
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let model = WholeShutoProductModel(
      checkpointStore: nil,
      driveRecordPreferenceStore: defaults
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6798, longitude: 139.6862)
    )
    var resolutionsStarted = 0
    let subscription = model.$isResolvingCircuitPairing.dropFirst().sink {
      if $0 { resolutionsStarted += 1 }
    }
    defer { subscription.cancel() }

    model.selectCircuit(.c1Inner)
    XCTAssertTrue(model.isResolvingCircuitPairing)
    // Tokyo Tower, about 6 km away: the in-flight pairing no longer applies.
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6586, longitude: 139.7454)
    )
    model.refreshCircuitEntrances()
    await waitForCircuitPairing(model)

    XCTAssertEqual(resolutionsStarted, 2)
    XCTAssertNotEqual(model.circuitEntryFacilityID, "shuto.ic.4.yoyogi")
  }

  func testCircuitEntranceTariffBandsResolveFromDatedEvidence() async {
    let model = WholeShutoProductModel(checkpointStore: nil)
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6798, longitude: 139.6862)
    )

    model.selectCircuit(.c2InnerWithBayshore)
    for _ in 0..<200 where model.circuitTariffBandsByFacilityID.isEmpty {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }

    // The Hatsudai-minami pairing exits at Tomigaya just ahead, so the
    // tariff distance stays in the minimum band regardless of laps.
    XCTAssertEqual(
      model.circuitTariffBandsByFacilityID["shuto.ic.c2.hatsudaiminami"],
      .minimum(yen: 300)
    )
  }

  func testCircuitExitIsTheDriversToFixAsWellAsTheEntrance() async throws {
    let model = WholeShutoProductModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6798, longitude: 139.6862)
    )
    model.selectCircuit(.c1Inner)
    await waitForCircuitPairing(model)

    let entryID = try XCTUnwrap(model.circuitEntryFacilityID)
    let recommendedExitID = try XCTUnwrap(model.circuitExitFacilityID)
    XCTAssertEqual(model.circuitRecommendedExitFacilityID, recommendedExitID)
    XCTAssertFalse(model.circuitExitWasOverridden)
    let expectedExits = try model.planner.circuitExitCandidates(
      for: .c1Inner,
      afterEntering: entryID
    ).map(\.facilityID)
    XCTAssertEqual(model.circuitExitCandidates.map(\.facilityID), expectedExits)
    XCTAssertEqual(
      Set(model.circuitTariffBandsByExitFacilityID.keys),
      Set(expectedExits)
    )
    XCTAssertEqual(
      model.circuitTariffBandsByExitFacilityID[recommendedExitID],
      model.circuitPairingBand
    )

    // Fixing a far exit prices that pairing, for the entrance and for each
    // ranked alternative, and keeps the recommendation known.
    let chosen = try XCTUnwrap(
      model.circuitExitCandidates.last { $0.facilityID != recommendedExitID }
    )
    model.selectCircuitExit(facilityID: chosen.facilityID)
    await waitForCircuitPairing(model)
    XCTAssertEqual(model.circuitExitFacilityID, chosen.facilityID)
    XCTAssertTrue(model.circuitExitWasOverridden)
    XCTAssertEqual(model.circuitEntryFacilityID, entryID)
    XCTAssertEqual(model.circuitRecommendedExitFacilityID, recommendedExitID)
    XCTAssertEqual(
      model.circuitPairingBand,
      try model.planner.tariffBand(
        entryFacilityID: entryID,
        exitFacilityID: chosen.facilityID,
        evidence: model.activeTariffEvidence
      )
    )
    XCTAssertFalse(model.circuitTariffBandsByFacilityID.isEmpty)
    for (facilityID, band) in model.circuitTariffBandsByFacilityID {
      XCTAssertEqual(
        band,
        try model.planner.tariffBand(
          entryFacilityID: facilityID,
          exitFacilityID: chosen.facilityID,
          evidence: model.activeTariffEvidence
        ),
        facilityID
      )
    }

    // Choosing the recommendation again returns to the derived pairing.
    model.selectCircuitExit(facilityID: recommendedExitID)
    await waitForCircuitPairing(model)
    XCTAssertFalse(model.circuitExitWasOverridden)
    XCTAssertEqual(model.circuitExitFacilityID, recommendedExitID)

    // A fixed exit survives an entrance change and starts the journey.
    model.selectCircuitExit(facilityID: chosen.facilityID)
    await waitForCircuitPairing(model)
    let otherEntrance = try XCTUnwrap(
      model.circuitEntranceCandidates.first { $0.facilityID != entryID }
    )
    model.selectCircuitEntrance(facilityID: otherEntrance.facilityID)
    await waitForCircuitPairing(model)
    XCTAssertEqual(model.circuitEntryFacilityID, otherEntrance.facilityID)
    XCTAssertEqual(model.circuitExitFacilityID, chosen.facilityID)
    XCTAssertTrue(model.circuitExitWasOverridden)
    XCTAssertTrue(model.startCircuitJourney())
    XCTAssertEqual(
      model.selectedRoute?.exitFacility?.facilityID,
      chosen.facilityID
    )
  }

  func testCircuitJourneyIsARoundTripThroughTheReviewGate() async {
    let suiteName = UUID().uuidString
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let model = WholeShutoProductModel(
      locationProvider: WholeShutoUnexpectedLocationProvider(),
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil,
      driveRecordPreferenceStore: defaults
    )
    let origin = ShutoCoordinate(latitude: 35.6798, longitude: 139.6862)
    model.selectCurrentOrigin(origin)
    model.selectCircuit(.c2InnerWithBayshore)
    model.selectCircuitLaps(2)
    await waitForCircuitPairing(model)

    XCTAssertTrue(model.startCircuitJourney())
    for _ in 0..<1_000 where model.isUpdatingSurfaceRoute {
      await Task.yield()
    }

    XCTAssertEqual(model.phase, .review)
    XCTAssertTrue(model.isCircuitRouteSelected)
    XCTAssertNil(model.failureCode)
    // Round trip: the origin doubles as the destination.
    XCTAssertEqual(model.destination?.coordinate, origin)
    XCTAssertNotNil(model.accessRoute)
    XCTAssertNotNil(model.egressRoute)
    guard let route = model.selectedRoute else {
      return XCTFail("Circuit journey selected no route")
    }
    // Two laps of the ~56 km circuit.
    XCTAssertGreaterThan(route.distanceMeters, 100_000)
    XCTAssertEqual(
      route.routePlan.entryFacilityID,
      "shuto.ic.c2.hatsudaiminami"
    )
    XCTAssertEqual(
      Set(route.routePlan.occurrences.map(\.id)).count,
      route.routePlan.occurrences.count
    )
    XCTAssertTrue(model.isJourneyReadyForPreview)
    XCTAssertEqual(
      model.savedRouteTemplateParameters,
      [
        "source": "CIRCUIT",
        "preference": route.preference.rawValue,
        "circuit_id": "shuto.circuit.c2-inner-bayshore",
        "laps": "2",
      ]
    )
  }

  func testCircuitReviewEditorOffersOnlyExitsTheExperienceReachesAfterTheEntrance()
    async throws
  {
    let model = WholeShutoProductModel(
      locationProvider: WholeShutoUnexpectedLocationProvider(),
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6798, longitude: 139.6862)
    )
    model.selectCircuit(.c2InnerWithBayshore)
    await waitForCircuitPairing(model)
    XCTAssertTrue(model.startCircuitJourney())
    for _ in 0..<1_000 where model.isUpdatingSurfaceRoute {
      await Task.yield()
    }

    model.prepareCustomRouteDraft()

    XCTAssertTrue(model.editsSelectedCircuit)
    let entryID = try XCTUnwrap(model.customEntryFacilityID)
    let exitNameJA = try XCTUnwrap(model.customExitFacility?.nameJA)
    XCTAssertEqual(model.customEntryCandidates.first?.facilityID, entryID)
    XCTAssertEqual(
      Set(model.customEntryCandidates.map(\.facilityID)),
      Set(
        model.circuitEntranceCandidates.filter { $0.nameJA != exitNameJA }
          .map(\.facilityID)
      )
    )
    let exits = model.customExitCandidates
    let reachable = Set(
      try model.planner.circuitExitCandidates(
        for: .c2InnerWithBayshore,
        afterEntering: entryID
      ).map(\.facilityID)
    )
    XCTAssertFalse(exits.isEmpty)
    XCTAssertEqual(Set(exits.map(\.facilityID)), reachable)
    XCTAssertEqual(exits.first?.facilityID, model.customExitFacilityID)
    // The experience runs C2 inner; an outer-loop exit is geodesically near
    // the course but not on it, and the editor no longer lists it.
    XCTAssertLessThan(
      exits.count,
      model.database.directionalFacilities.filter(\.canExit).count
    )
    let offCourse = try XCTUnwrap(
      model.database.directionalFacilities.first {
        $0.canExit && $0.routeID == "C2" && $0.exitDirections == ["外回り"]
      }
    )
    XCTAssertFalse(exits.contains { $0.facilityID == offCourse.facilityID })
    model.selectCustomExit(facilityID: offCourse.facilityID)
    XCTAssertNotEqual(model.customExitFacilityID, offCourse.facilityID)
  }

  func testParkingAreaEndedExperienceEditsAsAnExplicitRoute() async throws {
    let model = WholeShutoProductModel(
      locationProvider: WholeShutoUnexpectedLocationProvider(),
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    // Odaiba: the Bayshore run starts at a westbound Bayshore entrance and
    // ends inside Daikoku PA, so it has no exit to keep.
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6270, longitude: 139.7750)
    )
    model.selectCircuit(.wanganDaikokuRun)
    await waitForCircuitPairing(model)
    XCTAssertTrue(model.startCircuitJourney())
    for _ in 0..<1_000 where model.isUpdatingSurfaceRoute {
      await Task.yield()
    }
    XCTAssertNotNil(model.selectedRoute?.destinationParkingArea)

    model.prepareCustomRouteDraft()

    // Choosing an exit leaves the PA ending, so this is the explicit
    // entrance/exit editor: every offered exit is reachable from the entry.
    XCTAssertFalse(model.editsSelectedCircuit)
    XCTAssertNil(model.customExitFacilityID)
    XCTAssertNil(model.customDraftRoute)
    let entryID = try XCTUnwrap(model.customEntryFacilityID)
    let reachable = Set(
      model.planner.exitCandidates(
        model.database.directionalFacilities,
        reachableAfterEntering: entryID
      ).map(\.facilityID)
    )
    XCTAssertFalse(model.customExitCandidates.isEmpty)
    XCTAssertEqual(Set(model.customExitCandidates.map(\.facilityID)), reachable)

    model.selectCustomExit(facilityID: "shuto.ic.b.daikokufutou")
    let draft = try XCTUnwrap(model.customDraftRoute)
    XCTAssertEqual(draft.exitFacility?.facilityID, "shuto.ic.b.daikokufutou")
    XCTAssertNil(draft.destinationParkingArea)
    XCTAssertTrue(model.applyCustomRoute())
    XCTAssertTrue(model.isCustomRouteSelected)
    XCTAssertFalse(model.isCircuitRouteSelected)
    XCTAssertEqual(model.selectedRoute?.routePlan, draft.routePlan)
  }

  func testCircuitReviewEditorKeepsTheCircuitAndLapsWhenApplied() async throws {
    let model = WholeShutoProductModel(
      locationProvider: WholeShutoUnexpectedLocationProvider(),
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6798, longitude: 139.6862)
    )
    model.selectCircuit(.c2InnerWithBayshore)
    model.selectCircuitLaps(2)
    await waitForCircuitPairing(model)
    XCTAssertTrue(model.startCircuitJourney())
    for _ in 0..<1_000 where model.isUpdatingSurfaceRoute {
      await Task.yield()
    }
    let plannedExitID = try XCTUnwrap(model.circuitExitFacilityID)

    model.prepareCustomRouteDraft()
    let otherExit = try XCTUnwrap(
      model.customExitCandidates.first { $0.facilityID != plannedExitID }
    )
    model.selectCustomExit(facilityID: otherExit.facilityID)

    let draft = try XCTUnwrap(model.customDraftRoute)
    XCTAssertEqual(draft.exitFacility?.facilityID, otherExit.facilityID)
    // The draft is still two laps of the experience, not a shortest path.
    XCTAssertGreaterThan(draft.distanceMeters, 100_000)
    XCTAssertTrue(model.applyCustomRoute())

    XCTAssertTrue(model.isCircuitRouteSelected)
    XCTAssertFalse(model.isCustomRouteSelected)
    XCTAssertEqual(
      model.selectedCircuit?.circuitID,
      ShutoCircuitDefinition.c2InnerWithBayshore.circuitID
    )
    XCTAssertEqual(model.selectedRoute?.routePlan, draft.routePlan)
    XCTAssertEqual(model.circuitExitFacilityID, otherExit.facilityID)
    XCTAssertNotNil(model.circuitPairingBand)
    XCTAssertEqual(model.savedRouteTemplateParameters["source"], "CIRCUIT")
    XCTAssertEqual(model.savedRouteTemplateParameters["laps"], "2")
    for _ in 0..<1_000 where model.isUpdatingSurfaceRoute {
      await Task.yield()
    }
    XCTAssertEqual(
      model.egressRoute?.coordinates.first,
      draft.coordinates.last
    )
  }

  func testCircuitReviewEditorEntranceChangeRefreshesTheExits() async throws {
    let model = WholeShutoProductModel(
      locationProvider: WholeShutoUnexpectedLocationProvider(),
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6798, longitude: 139.6862)
    )
    model.selectCircuit(.c1Inner)
    await waitForCircuitPairing(model)
    XCTAssertTrue(model.startCircuitJourney())
    for _ in 0..<1_000 where model.isUpdatingSurfaceRoute {
      await Task.yield()
    }

    model.prepareCustomRouteDraft()
    let otherEntrance = try XCTUnwrap(
      model.customEntryCandidates.first {
        $0.facilityID != model.customEntryFacilityID
      }
    )
    model.selectCustomEntry(facilityID: otherEntrance.facilityID)

    XCTAssertEqual(model.customEntryFacilityID, otherEntrance.facilityID)
    let exitID = try XCTUnwrap(model.customExitFacilityID)
    XCTAssertTrue(
      model.customExitCandidates.contains { $0.facilityID == exitID }
    )
    XCTAssertEqual(
      Set(model.customExitCandidates.map(\.facilityID)),
      Set(
        try model.planner.circuitExitCandidates(
          for: .c1Inner,
          afterEntering: otherEntrance.facilityID
        ).map(\.facilityID)
      )
    )
    let draft = try XCTUnwrap(model.customDraftRoute)
    XCTAssertEqual(draft.entryFacility.facilityID, otherEntrance.facilityID)
    XCTAssertEqual(draft.exitFacility?.facilityID, exitID)
  }

  func testCircuitReviewCheckpointDoesNotRestoreStaleOrigin() async {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(
      locationProvider: WholeShutoUnexpectedLocationProvider(),
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: store
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6798, longitude: 139.6862)
    )
    model.selectCircuit(.c2InnerWithBayshore)
    model.selectCircuitLaps(2)
    await waitForCircuitPairing(model)
    XCTAssertTrue(model.startCircuitJourney())
    for _ in 0..<1_000 where model.isUpdatingSurfaceRoute {
      await Task.yield()
    }
    XCTAssertNotNil(model.selectedRoute?.routePlan.id)

    let restored = WholeShutoProductModel(
      locationProvider: WholeShutoUnexpectedLocationProvider(),
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: store
    )

    XCTAssertFalse(restored.restoredFromCheckpoint)
    XCTAssertEqual(restored.phase, .planning)
    XCTAssertNil(restored.selectedRoute)
    XCTAssertNil(restored.checkpointIssueCode)
    XCTAssertNil(store.checkpoint)
  }

  func testResolvedDestinationPreviewIsExplicitAndResettable() {
    let model = WholeShutoProductModel(checkpointStore: nil)
    let destination = WholeShutoPlace(
      title: "东京塔",
      coordinate: ShutoCoordinate(
        latitude: 35.658581,
        longitude: 139.745433
      )
    )

    model.selectDestinationPreview(destination)

    XCTAssertEqual(model.destinationQuery, "东京塔")
    XCTAssertEqual(model.destination, destination)
    XCTAssertTrue(model.hasSelectedDestinationPreview)

    model.clearDestinationPreview()

    XCTAssertEqual(model.destinationQuery, "东京塔")
    XCTAssertNil(model.destination)
    XCTAssertFalse(model.hasSelectedDestinationPreview)
  }

  func testMeasuredCurrentOriginPlansWithoutASecondLocationRequest() async {
    let locationProvider = WholeShutoUnexpectedLocationProvider()
    let model = WholeShutoProductModel(
      locationProvider: locationProvider,
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    model.selectCurrentOrigin(
      WholeShutoProductModel.previewOrigin.coordinate
    )
    model.selectDestinationPreview(
      WholeShutoProductModel.previewDestination
    )

    model.planJourney()
    for _ in 0..<100 where model.isPlanning {
      await Task.yield()
    }

    XCTAssertFalse(model.isPlanning)
    XCTAssertEqual(model.phase, .review)
    XCTAssertEqual(
      model.origin?.coordinate,
      WholeShutoProductModel.previewOrigin.coordinate
    )
    XCTAssertEqual(locationProvider.requestCount, 0)
    XCTAssertNil(model.failureCode)
  }

  func testComparableSurfaceRoutesRefineChoiceWithoutChangingExactPlans()
    async throws
  {
    let baseline = WholeShutoProductModel(checkpointStore: nil)
    baseline.preparePreviewJourney()
    let originalRecommendations = baseline.recommendations
    let preferredRoute = try XCTUnwrap(
      originalRecommendations.last?.route
    )
    let resolver = WholeShutoRankingSurfaceRouteResolver(
      preferredEntry: try XCTUnwrap(preferredRoute.coordinates.first),
      preferredExit: try XCTUnwrap(preferredRoute.coordinates.last)
    )
    let model = WholeShutoProductModel(
      database: baseline.database,
      locationProvider: WholeShutoUnexpectedLocationProvider(),
      surfaceRouteResolver: resolver,
      checkpointStore: nil
    )
    model.selectCurrentOrigin(
      WholeShutoProductModel.previewOrigin.coordinate
    )
    model.selectDestinationPreview(
      WholeShutoProductModel.previewDestination
    )

    model.planJourney()
    for _ in 0..<1_000 where model.isPlanning {
      await Task.yield()
    }

    XCTAssertFalse(model.isPlanning)
    XCTAssertFalse(model.isUpdatingSurfaceRoute)
    XCTAssertEqual(model.phase, .review)
    XCTAssertEqual(
      model.recommendations.first?.route.routePlan.id,
      preferredRoute.routePlan.id
    )
    XCTAssertEqual(
      Set(model.recommendations.map(\.route.routePlan.id)),
      Set(originalRecommendations.map(\.route.routePlan.id))
    )
    let originalPlans = Dictionary(
      uniqueKeysWithValues: originalRecommendations.map {
        ($0.route.routePlan.id, $0.route.routePlan)
      }
    )
    for recommendation in model.recommendations {
      XCTAssertEqual(
        recommendation.route.routePlan,
        originalPlans[recommendation.route.routePlan.id]
      )
      XCTAssertNotNil(
        model.routeChoiceMetricsByRoutePlanID[
          recommendation.route.routePlan.id
        ]
      )
    }
    XCTAssertEqual(
      model.accessRoute?.coordinates.last,
      preferredRoute.coordinates.first
    )
    XCTAssertEqual(
      model.egressRoute?.coordinates.first,
      preferredRoute.coordinates.last
    )
    XCTAssertTrue(model.isJourneyReadyForPreview)
    XCTAssertNil(model.failureCode)
  }

  func testIncompleteSurfaceComparisonKeepsDeterministicKaidoOrder()
    async throws
  {
    let model = WholeShutoProductModel(checkpointStore: nil)
    model.preparePreviewJourney()
    let originalRecommendations = model.recommendations
    let unavailableEntry = try XCTUnwrap(
      originalRecommendations.last?.route.coordinates.first
    )
    let evaluator = WholeShutoSurfaceRouteChoiceEvaluator(
      resolver: WholeShutoPartiallyUnavailableChoiceResolver(
        unavailableEntry: unavailableEntry
      )
    )

    let evaluation = await evaluator.evaluate(
      recommendations: originalRecommendations,
      origin: WholeShutoProductModel.previewOrigin.coordinate,
      destination: WholeShutoProductModel.previewDestination.coordinate
    )

    XCTAssertFalse(evaluation.usesComparableProviderMetrics)
    XCTAssertEqual(
      evaluation.recommendations.map(\.route.routePlan.id),
      originalRecommendations.map(\.route.routePlan.id)
    )
    XCTAssertLessThan(
      evaluation.surfaceRoutesByRoutePlanID.count,
      originalRecommendations.count
    )
  }

  func testCompletedJourneyPreviewKeepsTheArrivalSummaryUntilDone()
    throws
  {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: store)

    model.prepareCompletedJourneyPreview()

    XCTAssertEqual(model.phase, .completed)
    XCTAssertEqual(model.positionState, .completed)
    XCTAssertEqual(model.currentCoordinate, model.destination?.coordinate)
    XCTAssertEqual(model.remainingJourneyDistanceMeters, 0)
    XCTAssertGreaterThan(
      try XCTUnwrap(model.plannedJourneyDistanceMeters),
      try XCTUnwrap(model.selectedRoute?.distanceMeters)
    )
    XCTAssertFalse(model.isPlaying)
    XCTAssertNil(store.checkpoint)

    model.reset()

    XCTAssertEqual(model.phase, .planning)
    XCTAssertNil(model.selectedRoute)
    XCTAssertNil(model.destination)
  }

  func testJourneyReviewCombinesSurfaceAndExactShutoTiming() throws {
    let model = WholeShutoProductModel(checkpointStore: nil)

    model.preparePreviewJourney()

    let route = try XCTUnwrap(model.selectedRoute)
    let access = try XCTUnwrap(model.accessRoute)
    let egress = try XCTUnwrap(model.egressRoute)
    let expectedDuration =
      access.expectedTravelTimeSeconds
      + route.distanceMeters
      / WholeShutoProductModel.simulationReferenceSpeedMetersPerSecond
      + egress.expectedTravelTimeSeconds

    XCTAssertTrue(model.isJourneyReadyForPreview)
    XCTAssertEqual(
      try XCTUnwrap(model.plannedPreviewDurationSeconds),
      expectedDuration,
      accuracy: 0.001
    )
    XCTAssertEqual(
      try XCTUnwrap(model.plannedJourneyDistanceMeters),
      access.distanceMeters + route.distanceMeters + egress.distanceMeters,
      accuracy: 0.001
    )
    XCTAssertEqual(
      try XCTUnwrap(model.remainingPreviewDurationSeconds),
      expectedDuration,
      accuracy: 0.001
    )
    XCTAssertEqual(model.journeyProgressFraction, 0, accuracy: 0.001)
  }

  func testJourneyProgressIncludesSurfaceAndExpresswayLegs() async throws {
    let model = WholeShutoProductModel(checkpointStore: nil)
    model.preparePreviewJourney()

    let plannedDistance = try XCTUnwrap(model.plannedJourneyDistanceMeters)
    let plannedDuration = try XCTUnwrap(model.plannedPreviewDurationSeconds)

    model.startNavigationSimulation()
    _ = await model.pausePlayback()
    await model.advanceSimulationForTesting()

    XCTAssertEqual(model.phase, .surfaceAccess)
    XCTAssertEqual(model.progressFraction, 0.04, accuracy: 0.001)
    XCTAssertGreaterThan(model.journeyProgressFraction, 0)
    XCTAssertLessThan(model.journeyProgressFraction, 1)
    XCTAssertLessThan(
      try XCTUnwrap(model.remainingJourneyDistanceMeters),
      plannedDistance
    )
    XCTAssertLessThan(
      try XCTUnwrap(model.remainingPreviewDurationSeconds),
      plannedDuration
    )

    model.prepareCompletedJourneyPreview()

    XCTAssertEqual(model.journeyProgressFraction, 1, accuracy: 0.001)
    XCTAssertEqual(model.remainingPreviewDurationSeconds, 0)
  }

  func testPauseReturnsOnlyAfterPlaybackIsStable() async throws {
    let model = WholeShutoProductModel(checkpointStore: nil)
    model.preparePreviewJourney()
    model.startNavigationSimulation()

    try await Task.sleep(nanoseconds: 500_000_000)
    let pausedActivePlayback = await model.pausePlayback()
    XCTAssertTrue(pausedActivePlayback)
    let pausedPhase = model.phase
    let pausedProgress = model.progressFraction
    let pausedOccurrenceID = model.runtimeOccurrenceID

    try await Task.sleep(nanoseconds: 650_000_000)
    XCTAssertFalse(model.isPlaying)
    XCTAssertEqual(model.phase, pausedPhase)
    XCTAssertEqual(model.progressFraction, pausedProgress)
    XCTAssertEqual(model.runtimeOccurrenceID, pausedOccurrenceID)
    let pausedAgain = await model.pausePlayback()
    XCTAssertFalse(pausedAgain)

    model.resumePlayback()
    XCTAssertTrue(model.isPlaying)
    _ = await model.pausePlayback()
  }

  func testUnavailableSurfaceLegsBlockPreviewUntilRetrySucceeds() async {
    let resolver = WholeShutoRecoveringSurfaceRouteResolver()
    let model = WholeShutoProductModel(
      surfaceRouteResolver: resolver,
      checkpointStore: nil
    )
    model.originQuery = "現在地"
    model.selectCurrentOrigin(
      WholeShutoProductModel.previewOrigin.coordinate
    )
    model.selectDestinationPreview(
      WholeShutoProductModel.previewDestination
    )

    model.planJourney()
    for _ in 0..<100 where model.isPlanning || model.isUpdatingSurfaceRoute {
      await Task.yield()
    }

    XCTAssertEqual(model.phase, .review)
    XCTAssertFalse(model.isJourneyReadyForPreview)
    XCTAssertEqual(model.failureCode, "SURFACE_ROUTE_UNAVAILABLE")

    model.startNavigationSimulation()

    XCTAssertEqual(model.phase, .review)
    XCTAssertFalse(model.isPlaying)

    await resolver.setAvailable(true)
    model.retrySurfaceRoutes()
    for _ in 0..<100 where model.isUpdatingSurfaceRoute {
      await Task.yield()
    }

    XCTAssertTrue(model.isJourneyReadyForPreview)
    XCTAssertNil(model.failureCode)
    XCTAssertNotNil(model.accessRoute)
    XCTAssertNotNil(model.egressRoute)
  }

  func testLatestRouteSelectionOwnsSurfacePreviewAfterOutOfOrderResponses()
    async
  {
    let resolver = WholeShutoOutOfOrderSurfaceRouteResolver()
    let model = WholeShutoProductModel(
      surfaceRouteResolver: resolver,
      checkpointStore: nil
    )
    model.preparePreviewJourney()
    XCTAssertGreaterThanOrEqual(model.recommendations.count, 3)

    let slowRoute = model.recommendations[1].route
    let latestRoute = model.recommendations[2].route
    await resolver.configure(
      slowEntry: slowRoute.coordinates.first
        ?? slowRoute.entryFacility.coordinate,
      slowExit: slowRoute.coordinates.last
        ?? slowRoute.destinationCoordinate
    )

    model.selectRecommendation(at: 1)
    XCTAssertTrue(model.isUpdatingSurfaceRoute)
    XCTAssertNil(model.accessRoute)
    XCTAssertNil(model.egressRoute)

    model.selectRecommendation(at: 2)
    try? await Task.sleep(nanoseconds: 80_000_000)

    XCTAssertEqual(model.selectedRecommendationIndex, 2)
    XCTAssertFalse(model.isUpdatingSurfaceRoute)
    // Surface legs land on the plan's own directional ramp mouths, not
    // the IC representative points.
    XCTAssertEqual(
      model.accessRoute?.coordinates.last,
      latestRoute.coordinates.first
    )
    XCTAssertEqual(
      model.egressRoute?.coordinates.first,
      latestRoute.coordinates.last
    )

    try? await Task.sleep(nanoseconds: 180_000_000)

    XCTAssertEqual(
      model.accessRoute?.coordinates.last,
      latestRoute.coordinates.first
    )
    XCTAssertEqual(
      model.egressRoute?.coordinates.first,
      latestRoute.coordinates.last
    )
  }

  func testCustomRoutePinsExactDirectionalEntryAndExit() async throws {
    let model = WholeShutoProductModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    model.preparePreviewJourney()
    model.prepareCustomRouteDraft()

    let entryID = "shuto.ic.c1.takaracho"
    let exitID = "shuto.ic.k1.yokohamakouen"
    XCTAssertTrue(
      model.customEntryCandidates.contains {
        $0.facilityID == entryID
      }
    )
    XCTAssertTrue(
      model.customExitCandidates.contains {
        $0.facilityID == exitID
      }
    )

    model.selectCustomEntry(facilityID: entryID)
    model.selectCustomExit(facilityID: exitID)
    model.selectCustomPreference(.fewerJunctions)

    let draft = try XCTUnwrap(model.customDraftRoute)
    XCTAssertEqual(draft.entryFacility.facilityID, entryID)
    XCTAssertEqual(draft.exitFacility?.facilityID, exitID)
    XCTAssertEqual(draft.preference, .fewerJunctions)
    XCTAssertTrue(model.canApplyCustomRoute)
    XCTAssertTrue(model.applyCustomRoute())

    XCTAssertTrue(model.isCustomRouteSelected)
    XCTAssertEqual(model.selectedRoute?.routePlan, draft.routePlan)
    XCTAssertEqual(model.selectedRoute?.entryFacility.facilityID, entryID)
    XCTAssertEqual(model.selectedRoute?.exitFacility?.facilityID, exitID)

    for _ in 0..<100 where model.isUpdatingSurfaceRoute {
      await Task.yield()
    }
    XCTAssertFalse(model.isUpdatingSurfaceRoute)
    // Surface legs land on the draft's own directional ramp mouths.
    XCTAssertEqual(
      model.accessRoute?.coordinates.last,
      draft.coordinates.first
    )
    XCTAssertEqual(
      model.egressRoute?.coordinates.first,
      draft.coordinates.last
    )

    model.selectRecommendation(at: 0)

    XCTAssertFalse(model.isCustomRouteSelected)
    XCTAssertNotEqual(model.selectedRoute?.routePlan, draft.routePlan)
  }

  func testCustomExitCandidatesFollowTheChosenEntry() throws {
    let model = WholeShutoProductModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    model.preparePreviewJourney()
    model.prepareCustomRouteDraft()
    XCTAssertFalse(model.editsSelectedCircuit)

    let entryID = "shuto.ic.c1.takaracho"
    model.selectCustomEntry(facilityID: entryID)

    let allExits = model.database.directionalFacilities.filter(\.canExit)
    let reachable = Set(
      model.planner.exitCandidates(
        allExits,
        reachableAfterEntering: entryID
      ).map(\.facilityID)
    )
    XCTAssertFalse(reachable.isEmpty)
    XCTAssertEqual(Set(model.customExitCandidates.map(\.facilityID)), reachable)
    XCTAssertEqual(
      model.customExitCandidates.first?.facilityID,
      model.customExitFacilityID
    )
    let unreachable = model.customExitCandidatesNotReachableFromEntry
    XCTAssertEqual(
      Set(unreachable.map(\.facilityID)),
      Set(allExits.map(\.facilityID)).subtracting(reachable)
    )
    // An exit no directed path reaches from this entry is still choosable
    // from a search; it clears the entry instead of drafting a refused pair.
    let chosen = try XCTUnwrap(unreachable.first)
    model.selectCustomExit(facilityID: chosen.facilityID)
    XCTAssertEqual(model.customExitFacilityID, chosen.facilityID)
    XCTAssertNil(model.customEntryFacilityID)
    XCTAssertNil(model.customDraftRoute)
    XCTAssertFalse(model.canApplyCustomRoute)
    let allEntrances = model.database.directionalFacilities.filter(\.canEnter)
    XCTAssertEqual(
      Set(model.customEntryCandidates.map(\.facilityID)),
      Set(
        model.planner.entryCandidates(
          allEntrances,
          reaching: chosen.facilityID
        ).map(\.facilityID)
      )
    )
  }

  func testCustomEntryCandidatesFollowTheChosenExit() throws {
    let model = WholeShutoProductModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    model.preparePreviewJourney()
    model.prepareCustomRouteDraft()
    XCTAssertFalse(model.editsSelectedCircuit)
    model.selectCustomEntry(facilityID: "shuto.ic.c1.takaracho")

    let exitID = "shuto.ic.k1.yokohamakouen"
    model.selectCustomExit(facilityID: exitID)
    XCTAssertEqual(model.customExitFacilityID, exitID)
    XCTAssertEqual(model.customEntryFacilityID, "shuto.ic.c1.takaracho")

    let allEntrances = model.database.directionalFacilities.filter(\.canEnter)
    let reaching = Set(
      model.planner.entryCandidates(allEntrances, reaching: exitID)
        .map(\.facilityID)
    )
    XCTAssertFalse(reaching.isEmpty)
    XCTAssertEqual(Set(model.customEntryCandidates.map(\.facilityID)), reaching)
    XCTAssertEqual(
      model.customEntryCandidates.first?.facilityID,
      model.customEntryFacilityID
    )
    let notReaching = model.customEntryCandidatesNotReachingExit
    XCTAssertEqual(
      Set(notReaching.map(\.facilityID)),
      Set(allEntrances.map(\.facilityID)).subtracting(reaching)
    )

    // Fixing an entrance the exit rules out clears that exit, and the exit
    // list then follows the new entrance.
    let chosen = try XCTUnwrap(notReaching.first)
    model.selectCustomEntry(facilityID: chosen.facilityID)
    XCTAssertEqual(model.customEntryFacilityID, chosen.facilityID)
    XCTAssertNil(model.customExitFacilityID)
    XCTAssertNil(model.customDraftRoute)
    XCTAssertFalse(model.canApplyCustomRoute)
    XCTAssertTrue(model.customEntryCandidatesNotReachingExit.isEmpty)
    let allExits = model.database.directionalFacilities.filter(\.canExit)
    let reachable = Set(
      model.planner.exitCandidates(
        allExits,
        reachableAfterEntering: chosen.facilityID
      ).map(\.facilityID)
    )
    XCTAssertEqual(Set(model.customExitCandidates.map(\.facilityID)), reachable)
    let exit = try XCTUnwrap(model.customExitCandidates.first)
    model.selectCustomExit(facilityID: exit.facilityID)
    XCTAssertEqual(model.customEntryFacilityID, chosen.facilityID)
    XCTAssertNotNil(model.customDraftRoute)
    XCTAssertTrue(model.canApplyCustomRoute)
  }

  func testCustomEditorNeverDraftsAPairSharingOneTollPoint() throws {
    let model = WholeShutoProductModel(checkpointStore: nil)
    // Beside the Harumi ramps: on a round trip the driver's own IC is the
    // exit nearest the origin.
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6544, longitude: 139.7827)
    )
    model.prepareCustomRouteDraft()
    XCTAssertFalse(model.editsSelectedCircuit)
    XCTAssertEqual(model.customEntryFacilityID, "shuto.ic.10.harumi")
    XCTAssertNotNil(model.customDraftRoute)
    XCTAssertFalse(model.customExitCandidates.isEmpty)
    XCTAssertFalse(model.customExitCandidates.contains { $0.nameJA == "晴海" })
    XCTAssertEqual(
      model.customExitCandidatesNotReachableFromEntry
        .filter { $0.nameJA == "晴海" }.map(\.facilityID),
      ["shuto.ic.10.harumi"]
    )

    // Chosen from a search anyway, the entrance's own IC clears the
    // entrance instead of drafting the pair.
    model.selectCustomExit(facilityID: "shuto.ic.10.harumi")
    XCTAssertEqual(model.customExitFacilityID, "shuto.ic.10.harumi")
    XCTAssertNil(model.customEntryFacilityID)
    XCTAssertNil(model.customDraftRoute)
    XCTAssertFalse(model.canApplyCustomRoute)
    XCTAssertFalse(model.customEntryCandidates.contains { $0.nameJA == "晴海" })

    // Differently identified ramps of one toll point are no more plannable
    // as a pair, from either end.
    model.selectCustomEntry(facilityID: "shuto.ic.k1.daishi")
    XCTAssertEqual(model.customEntryFacilityID, "shuto.ic.k1.daishi")
    XCTAssertFalse(model.customExitCandidates.contains { $0.nameJA == "大師" })
    model.selectCustomExit(facilityID: "shuto.ic.k6.daishi")
    XCTAssertEqual(model.customExitFacilityID, "shuto.ic.k6.daishi")
    XCTAssertNil(model.customEntryFacilityID)
    XCTAssertNil(model.customDraftRoute)
    XCTAssertTrue(
      model.customEntryCandidatesNotReachingExit.contains {
        $0.facilityID == "shuto.ic.k1.daishi"
      }
    )
    model.selectCustomEntry(facilityID: "shuto.ic.k1.daishi")
    XCTAssertEqual(model.customEntryFacilityID, "shuto.ic.k1.daishi")
    XCTAssertNil(model.customExitFacilityID)
    XCTAssertNil(model.customDraftRoute)
    XCTAssertFalse(model.canApplyCustomRoute)
  }

  func testCircuitReviewEditorRulesOutEntrancesSharingTheExitTollPoint()
    async throws
  {
    let model = WholeShutoProductModel(
      locationProvider: WholeShutoUnexpectedLocationProvider(),
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6798, longitude: 139.6862)
    )
    model.selectCircuit(.c1Inner)
    model.selectCircuitLaps(2)
    await waitForCircuitPairing(model)
    let pairedEntry = try XCTUnwrap(
      model.circuitEntranceCandidates.first {
        $0.facilityID == model.circuitEntryFacilityID
      }
    )
    XCTAssertFalse(model.circuitExitCandidates.isEmpty)
    XCTAssertFalse(
      model.circuitExitCandidates.contains { $0.nameJA == pairedEntry.nameJA }
    )
    XCTAssertTrue(model.startCircuitJourney())
    for _ in 0..<1_000 where model.isUpdatingSurfaceRoute {
      await Task.yield()
    }

    model.prepareCustomRouteDraft()
    XCTAssertTrue(model.editsSelectedCircuit)
    let entry = try XCTUnwrap(model.customEntryFacility)
    XCTAssertFalse(model.customExitCandidates.isEmpty)
    XCTAssertFalse(
      model.customExitCandidates.contains { $0.nameJA == entry.nameJA }
    )

    // Fix an exit that another entrance of the experience shares a toll
    // point with: that entrance is ruled out the way an unreachable one is.
    let entrances = model.circuitEntranceCandidates
    let exit = try XCTUnwrap(
      model.customExitCandidates.first { exit in
        entrances.contains { $0.nameJA == exit.nameJA }
      }
    )
    model.selectCustomExit(facilityID: exit.facilityID)
    XCTAssertEqual(model.customExitFacilityID, exit.facilityID)
    XCTAssertEqual(model.customEntryFacilityID, entry.facilityID)
    let sharing = Set(
      entrances.filter { $0.nameJA == exit.nameJA }.map(\.facilityID)
    )
    XCTAssertEqual(
      Set(model.customEntryCandidatesNotReachingExit.map(\.facilityID)),
      sharing
    )
    XCTAssertEqual(
      Set(model.customEntryCandidates.map(\.facilityID)),
      Set(entrances.map(\.facilityID)).subtracting(sharing)
    )

    // Choosing it clears the exit; the exits then follow the new entrance.
    let chosen = try XCTUnwrap(model.customEntryCandidatesNotReachingExit.first)
    model.selectCustomEntry(facilityID: chosen.facilityID)
    XCTAssertEqual(model.customEntryFacilityID, chosen.facilityID)
    XCTAssertNil(model.customExitFacilityID)
    XCTAssertNil(model.customDraftRoute)
    XCTAssertFalse(model.canApplyCustomRoute)
    model.selectCustomExit(facilityID: exit.facilityID)
    XCTAssertNil(model.customExitFacilityID)
    XCTAssertFalse(
      model.customExitCandidates.contains { $0.nameJA == chosen.nameJA }
    )
    let next = try XCTUnwrap(model.customExitCandidates.first)
    model.selectCustomExit(facilityID: next.facilityID)
    let draft = try XCTUnwrap(model.customDraftRoute)
    XCTAssertEqual(draft.entryFacility.facilityID, chosen.facilityID)
    XCTAssertEqual(draft.exitFacility?.facilityID, next.facilityID)
    XCTAssertEqual(draft.lapBoundaryOccurrenceIndices.count, 3)
    XCTAssertTrue(model.applyCustomRoute())
    XCTAssertTrue(model.isCircuitRouteSelected)
    XCTAssertEqual(model.selectedRoute?.routePlan, draft.routePlan)
  }

  func testDirectionalTourEditorNeverOffersTheEntranceTollPointAsExit()
    async throws
  {
    let model = WholeShutoProductModel(
      locationProvider: WholeShutoUnexpectedLocationProvider(),
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    // Shinkiba: the westbound Bayshore run passes its own Shinkiba exit.
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6471, longitude: 139.8306)
    )
    model.selectCircuit(.wanganDaikokuRun)
    await waitForCircuitPairing(model)
    XCTAssertTrue(model.startCircuitJourney())
    await waitForEndingRoutes(model)
    XCTAssertNotNil(model.selectedRoute?.destinationParkingArea)

    // Leaving the PA ending for an exit keeps the tour, so the editor
    // refines the experience rather than an explicit route.
    let exits = try await model.journeyExitCandidates()
    let entry = try XCTUnwrap(model.selectedRoute?.entryFacility)
    XCTAssertFalse(exits.isEmpty)
    XCTAssertFalse(exits.contains { $0.nameJA == entry.nameJA })
    try await model.selectJourneyExit(try XCTUnwrap(exits.first).facilityID)
    await waitForEndingRoutes(model)
    model.prepareCustomRouteDraft()
    XCTAssertTrue(model.editsSelectedCircuit)

    model.selectCustomEntry(facilityID: "shuto.ic.b.shinkiba")
    XCTAssertEqual(model.customEntryFacilityID, "shuto.ic.b.shinkiba")
    XCTAssertFalse(model.customExitCandidates.isEmpty)
    XCTAssertFalse(model.customExitCandidates.contains { $0.nameJA == "新木場" })
    model.selectCustomExit(facilityID: "shuto.ic.b.shinkiba")
    XCTAssertNotEqual(model.customExitFacilityID, "shuto.ic.b.shinkiba")
    let exit = try XCTUnwrap(model.customExitCandidates.first)
    model.selectCustomExit(facilityID: exit.facilityID)
    let draft = try XCTUnwrap(model.customDraftRoute)
    XCTAssertEqual(draft.entryFacility.facilityID, "shuto.ic.b.shinkiba")
    XCTAssertEqual(draft.exitFacility?.facilityID, exit.facilityID)
  }

  func testCustomRouteReviewCheckpointDoesNotRestoreStaleOrigin() async throws {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: store
    )
    model.preparePreviewJourney()
    model.prepareCustomRouteDraft()
    model.selectCustomEntry(facilityID: "shuto.ic.c1.takaracho")
    model.selectCustomExit(facilityID: "shuto.ic.k1.yokohamakouen")
    model.selectCustomPreference(.fewerJunctions)
    XCTAssertTrue(model.applyCustomRoute())

    for _ in 0..<100 where model.isUpdatingSurfaceRoute {
      await Task.yield()
    }
    _ = try XCTUnwrap(model.selectedRoute?.routePlan)
    XCTAssertEqual(store.checkpoint?.routeSelectionSource, .custom)

    let restored = WholeShutoProductModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: store
    )

    XCTAssertEqual(restored.phase, .planning)
    XCTAssertFalse(restored.restoredFromCheckpoint)
    XCTAssertNil(restored.selectedRoute)
    XCTAssertNil(restored.checkpointIssueCode)
    XCTAssertNil(store.checkpoint)
  }

  func testJunctionPromptsRequireAnExactReviewedMovement() {
    let model = WholeShutoProductModel(checkpointStore: nil)

    model.preparePreviewJourney()

    // The preview journey now crosses reviewed junctions, and every prompt
    // it carries must still come from an exact reviewed movement definition;
    // a prompt is never synthesized from route geometry alone.
    XCTAssertTrue(
      model.junctionPrompts.allSatisfy { prompt in
        ShutoJunctionMovementCatalog.released.contains {
          $0.id == prompt.movementID
        }
      }
    )

    model.prepareJunctionPreview()

    let prompt = model.junctionPrompts.first {
      $0.movementID == "shuto.jct.oi.b-westbound-to-c2-outer"
    }
    XCTAssertNotNil(prompt)
    XCTAssertEqual(prompt?.nameJA, "大井JCT")
    XCTAssertEqual(prompt?.incomingRouteID, "B")
    XCTAssertEqual(prompt?.outgoingRouteID, "C2")
    XCTAssertEqual(prompt?.outgoingDirectionJA, "外回り")
    XCTAssertEqual(prompt?.branchSide, .left)
    XCTAssertEqual(prompt?.japaneseSignText, "東名・中央道")
    XCTAssertEqual(prompt?.routeShields, ["C2", "3", "E1", "E20"])
    XCTAssertEqual(prompt?.laneGuidanceState, .notReleased)
    XCTAssertEqual(prompt?.localizedJunctionNames[.japanese], "大井JCT")
    XCTAssertEqual(
      prompt?.localizedJunctionNames[.simplifiedChinese],
      "大井 JCT"
    )
    XCTAssertEqual(prompt?.localizedJunctionNames[.english], "Oi JCT")
    XCTAssertEqual(
      prompt?.localizedContent[.japanese]?.displayText,
      "左方向へ分岐し、C2 外回りへ"
    )
    XCTAssertEqual(
      prompt?.localizedContent[.simplifiedChinese]?.displayText,
      "向左分岔，驶入 C2 外环"
    )
    XCTAssertEqual(
      prompt?.localizedContent[.english]?.displayText,
      "Branch left for the C2 Outer Loop"
    )
    XCTAssertTrue(
      prompt?.localizedContent.values.allSatisfy {
        $0.preservedJapaneseSignText == "東名・中央道"
      } == true
    )
    XCTAssertEqual(prompt?.checkedAt, "2026-07-29")
    XCTAssertEqual(model.activeJunctionPrompt, prompt)
    XCTAssertNil(model.failureCode)
  }

  func testKasaiJunctionPromptRequiresTheExactReviewedMovement() {
    let model = WholeShutoProductModel(checkpointStore: nil)

    model.prepareKasaiJunctionPreview()

    let prompt = try? XCTUnwrap(model.junctionPrompts.only)
    XCTAssertEqual(
      prompt?.movementID,
      "shuto.jct.kasai.b-westbound-to-c2-inner"
    )
    XCTAssertEqual(prompt?.nameJA, "葛西JCT")
    XCTAssertEqual(prompt?.incomingRouteID, "B")
    XCTAssertEqual(prompt?.outgoingRouteID, "C2")
    XCTAssertEqual(prompt?.outgoingDirectionJA, "内回り")
    XCTAssertEqual(prompt?.branchSide, .left)
    XCTAssertEqual(prompt?.japaneseSignText, "東北道・常磐道")
    XCTAssertEqual(prompt?.routeShields, ["C2", "E4", "E6", "6"])
    XCTAssertEqual(prompt?.laneGuidanceState, .notReleased)
    XCTAssertEqual(
      prompt?.localizedContent[.japanese]?.displayText,
      "左方向へ分岐し、C2 内回りへ"
    )
    XCTAssertEqual(
      prompt?.localizedContent[.simplifiedChinese]?.displayText,
      "向左分岔，驶入 C2 内环"
    )
    XCTAssertEqual(
      prompt?.localizedContent[.english]?.displayText,
      "Branch left for the C2 Inner Loop"
    )
    XCTAssertEqual(prompt?.checkedAt, "2026-07-30")
    XCTAssertEqual(model.activeJunctionPrompt, prompt)
    XCTAssertNil(model.failureCode)
  }

  func testTatsumiJunctionPromptsPreserveEachApproachSign() {
    let cases:
      [(
        isEastbound: Bool,
        movementID: String,
        signText: String,
        routeShields: [String]
      )] = [
        (
          true,
          "shuto.jct.tatsumi.b-eastbound-to-9-inbound",
          "箱崎",
          ["9", "6"]
        ),
        (
          false,
          "shuto.jct.tatsumi.b-westbound-to-9-inbound",
          "箱崎・銀座",
          ["9", "C1"]
        ),
      ]

    for testCase in cases {
      let model = WholeShutoProductModel(checkpointStore: nil)
      if testCase.isEastbound {
        model.prepareTatsumiEastboundJunctionPreview()
      } else {
        model.prepareTatsumiWestboundJunctionPreview()
      }

      // The Bayshore continuations are reviewed too, so select the
      // movement under test rather than assuming it is the only prompt.
      let prompt = model.junctionPrompts.first {
        $0.movementID == testCase.movementID
      }
      XCTAssertNotNil(prompt)
      XCTAssertEqual(prompt?.nameJA, "辰巳JCT")
      XCTAssertEqual(prompt?.outgoingRouteID, "9")
      XCTAssertEqual(prompt?.outgoingDirectionJA, "上り")
      XCTAssertEqual(prompt?.branchSide, .left)
      XCTAssertEqual(prompt?.japaneseSignText, testCase.signText)
      XCTAssertEqual(prompt?.routeShields, testCase.routeShields)
      XCTAssertEqual(prompt?.laneGuidanceState, .notReleased)
      XCTAssertEqual(
        prompt?.localizedContent[.japanese]?.displayText,
        "左方向へ分岐し、9号深川線 上りへ"
      )
      XCTAssertEqual(
        prompt?.localizedContent[.simplifiedChinese]?.displayText,
        "向左分岔，驶入 9 号深川线上行方向"
      )
      XCTAssertEqual(
        prompt?.localizedContent[.english]?.displayText,
        "Branch left for Route 9 inbound"
      )
      XCTAssertTrue(
        prompt?.localizedContent.values.allSatisfy {
          $0.preservedJapaneseSignText == testCase.signText
        } == true
      )
      XCTAssertEqual(prompt?.checkedAt, "2026-07-30")
      XCTAssertEqual(model.activeJunctionPrompt, prompt)
      XCTAssertNil(model.failureCode)
    }
  }

  func testShinonomeJunctionPromptsPreserveEachApproachBranchAndSign() {
    let cases:
      [(
        isEastbound: Bool,
        movementID: String,
        isLeftBranch: Bool,
        signText: String,
        localizedInstruction: String
      )] = [
        (
          true,
          "shuto.jct.shinonome.b-eastbound-to-10-inbound",
          true,
          "豊洲",
          "向左分岔，驶入 10 号晴海线上行方向"
        ),
        (
          false,
          "shuto.jct.shinonome.b-westbound-to-10-inbound",
          false,
          "晴海",
          "向右分岔，驶入 10 号晴海线上行方向"
        ),
      ]

    for testCase in cases {
      let model = WholeShutoProductModel(checkpointStore: nil)
      if testCase.isEastbound {
        model.prepareShinonomeEastboundJunctionPreview()
      } else {
        model.prepareShinonomeWestboundJunctionPreview()
      }

      // The westbound approach now also passes a reviewed Tatsumi
      // continuation, so select the movement under test.
      let prompt = model.junctionPrompts.first {
        $0.movementID == testCase.movementID
      }
      XCTAssertNotNil(prompt)
      XCTAssertEqual(prompt?.nameJA, "東雲JCT")
      XCTAssertEqual(prompt?.outgoingRouteID, "10")
      XCTAssertEqual(prompt?.outgoingDirectionJA, "上り")
      XCTAssertEqual(
        prompt?.branchSide,
        testCase.isLeftBranch ? .left : .right
      )
      XCTAssertEqual(prompt?.japaneseSignText, testCase.signText)
      XCTAssertEqual(prompt?.routeShields, ["10"])
      XCTAssertEqual(prompt?.laneGuidanceState, .notReleased)
      XCTAssertEqual(
        prompt?.localizedContent[.simplifiedChinese]?.displayText,
        testCase.localizedInstruction
      )
      XCTAssertTrue(
        prompt?.localizedContent.values.allSatisfy {
          $0.preservedJapaneseSignText == testCase.signText
        } == true
      )
      XCTAssertEqual(prompt?.checkedAt, "2026-07-30")
      XCTAssertEqual(model.activeJunctionPrompt, prompt)
      XCTAssertNil(model.failureCode)
    }
  }

  func testActiveJourneyRestoresPausedOnTheSameNetworkSnapshot()
    async throws
  {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: store)
    model.preparePreviewJourney()
    let originalRoute = try XCTUnwrap(model.selectedRoute)

    model.startNavigationSimulation()
    _ = await model.pausePlayback()
    await advance(model, until: { $0.phase == .expressway })
    for _ in 0..<3 {
      await model.advanceSimulationForTesting()
    }
    let savedProgress = model.progressFraction
    let savedCoordinate = model.currentCoordinate
    await model.handleScenePhase(.background)

    let restored = WholeShutoProductModel(
      database: model.database,
      checkpointStore: store
    )

    XCTAssertEqual(restored.phase, .expressway)
    XCTAssertEqual(restored.progressFraction, savedProgress)
    XCTAssertEqual(
      restored.runtimeOccurrenceID,
      model.runtimeOccurrenceID
    )
    XCTAssertEqual(
      restored.selectedRoute?.entryFacility.facilityID,
      originalRoute.entryFacility.facilityID
    )
    XCTAssertEqual(
      restored.selectedRoute?.exitFacility?.facilityID,
      originalRoute.exitFacility?.facilityID
    )
    XCTAssertTrue(restored.restoredFromCheckpoint)
    XCTAssertFalse(restored.isPlaying)

    await restored.advanceSimulationForTesting()
    XCTAssertGreaterThanOrEqual(
      restored.progressFraction,
      savedProgress
    )
    XCTAssertEqual(restored.currentCoordinate, savedCoordinate)
  }

  func testEntryCheckpointBeforeFirstObservationRestoresRuntime()
    async
  {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: store)
    model.preparePreviewJourney()
    model.startNavigationSimulation()
    _ = await model.pausePlayback()
    await advance(model, until: { $0.phase == .entryTransition })

    XCTAssertEqual(model.progressFraction, 0)
    XCTAssertNil(model.runtimeOccurrenceID)

    let restored = WholeShutoProductModel(
      database: model.database,
      checkpointStore: store
    )

    XCTAssertEqual(restored.phase, .entryTransition)
    XCTAssertTrue(restored.restoredFromCheckpoint)
    XCTAssertNil(restored.failureCode)

    await advance(restored, until: { $0.matcherConfidence == .high })

    XCTAssertEqual(restored.matcherConfidence, .high)
    XCTAssertEqual(restored.phase, .entryTransition)
    XCTAssertNil(restored.runtimeOccurrenceID)

    await advance(restored, until: { $0.phase == .expressway })

    XCTAssertNotNil(restored.runtimeOccurrenceID)
    XCTAssertGreaterThan(restored.progressFraction, 0)
  }

  func testLiveCheckpointWithoutActorStateIsRejected() {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: store)
    model.preparePreviewJourney()
    model.startNavigationSimulation()

    let checkpoint = try? XCTUnwrap(store.checkpoint)
    XCTAssertNotNil(checkpoint)
    store.checkpoint = checkpoint?.replacingDriveMode(
      .live,
      progressFraction: 0.72
    )

    let restored = WholeShutoProductModel(
      database: model.database,
      checkpointStore: store
    )

    XCTAssertFalse(restored.restoredFromCheckpoint)
    XCTAssertEqual(restored.phase, .planning)
    XCTAssertEqual(restored.progressFraction, 0)
    XCTAssertFalse(restored.isLiveDrive)
    XCTAssertFalse(restored.isPlaying)
    XCTAssertNil(restored.runtimeOccurrenceID)
    XCTAssertNil(restored.checkpointIssueCode)
    XCTAssertNil(restored.selectedRoute)
    XCTAssertNil(store.checkpoint)
  }

  func testLiveJourneyResumesAfterProcessRestart() async throws {
    let store = WholeShutoMemoryCheckpointStore()
    let firstSource = WholeShutoBackgroundNavigationLocationSource()
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoInstructionSurfaceRouteResolver(),
      checkpointStore: store,
      liveLocationSource: firstSource,
      speechOutput: WholeShutoRecordingSpeechOutput()
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6812, longitude: 139.7671)
    )
    model.prepareCustomRouteDraft()
    model.selectCustomEntry(facilityID: "shuto.ic.b.urayasu")
    model.selectCustomExit(facilityID: "shuto.ic.9.fukudumi")
    XCTAssertTrue(model.applyCustomRoute())
    await waitForLiveNavigationPreparation(model)
    let started = await model.startLiveJourney()
    XCTAssertTrue(started)

    let access = try XCTUnwrap(model.accessRoute)
    let midpoint = ShutoCoordinate(
      latitude: (access.coordinates[0].latitude + access.coordinates[1].latitude) / 2,
      longitude: (access.coordinates[0].longitude + access.coordinates[1].longitude) / 2
    )
    await model.consumeLiveObservationForTesting(
      Self.liveLocationEnvelope(id: "restart.surface.midpoint", coordinate: midpoint)
    )
    await model.handleScenePhase(.background)
    let savedPhase = try XCTUnwrap(store.checkpoint?.phase)
    let savedProgress = try XCTUnwrap(store.checkpoint?.progressFraction)
    XCTAssertNotNil(store.checkpoint?.liveNavigationCheckpoint)

    let resumedSource = WholeShutoBackgroundNavigationLocationSource()
    let restored = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoInstructionSurfaceRouteResolver(),
      checkpointStore: store,
      liveLocationSource: resumedSource,
      speechOutput: WholeShutoRecordingSpeechOutput()
    )
    XCTAssertTrue(restored.restoredFromCheckpoint)
    XCTAssertTrue(restored.isLiveDrive)
    XCTAssertFalse(restored.isPlaying)
    XCTAssertEqual(restored.phase, savedPhase)
    XCTAssertEqual(restored.progressFraction, savedProgress, accuracy: 0.001)
    XCTAssertEqual(restored.liveLocationState, .resumeRequired)

    await waitForLiveNavigationPreparation(restored)
    let resumed = await restored.resumeLiveJourney()
    XCTAssertTrue(resumed)
    XCTAssertTrue(restored.isPlaying)
    XCTAssertEqual(restored.phase, savedPhase)
    XCTAssertEqual(resumedSource.startCount, 1)
    restored.reset()
    model.reset()
  }

  func testSimulationCheckpointRejectsRuntimeAssetIdentityDrift()
    async throws
  {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: store)
    model.preparePreviewJourney()
    model.startNavigationSimulation()
    _ = await model.pausePlayback()
    await advance(model, until: { $0.phase == .entryTransition })

    let checkpoint = try XCTUnwrap(store.checkpoint)
    XCTAssertNotNil(checkpoint.runtimeAssetIdentity)
    let otherRoute = try model.planner.plan(
      entryFacilityID: "shuto.ic.b.urayasu",
      exitFacilityID: "shuto.ic.9.fukudumi"
    )
    let otherIdentity = try ShutoPlannedRouteRuntimeCompiler.compile(
      database: model.database,
      route: otherRoute
    ).runtimeAssetIdentity
    XCTAssertNotEqual(checkpoint.runtimeAssetIdentity, otherIdentity)
    store.checkpoint = checkpoint.replacingRuntimeAssetIdentity(
      otherIdentity
    )

    let restored = WholeShutoProductModel(
      database: model.database,
      checkpointStore: store
    )

    XCTAssertTrue(restored.restoredFromCheckpoint)
    XCTAssertEqual(restored.phase, .review)
    XCTAssertFalse(restored.isPlaying)
    XCTAssertNil(restored.runtimeOccurrenceID)
    XCTAssertNil(restored.failureCode)
  }

  func testCheckpointRoutePlanDriftDoesNotRestore() async throws {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: store)
    model.preparePreviewJourney()
    model.startNavigationSimulation()
    _ = await model.pausePlayback()

    let checkpoint = try XCTUnwrap(store.checkpoint)
    let originalPlan = checkpoint.routePlan
    var occurrences = originalPlan.occurrences
    let first = try XCTUnwrap(occurrences.first)
    occurrences[0] = RouteOccurrence(
      id: first.id,
      index: first.index,
      kind: first.kind,
      entityID: "\(first.entityID).drifted",
      parkingAreaID: first.parkingAreaID,
      tollDomainID: first.tollDomainID,
      isOptional: first.isOptional
    )
    store.checkpoint = checkpoint.replacingRoutePlan(
      RoutePlan(
        id: originalPlan.id,
        networkSnapshotID: originalPlan.networkSnapshotID,
        entryFacilityID: originalPlan.entryFacilityID,
        exitFacilityID: originalPlan.exitFacilityID,
        recoveryPolicy: originalPlan.recoveryPolicy,
        actualDistanceKM: originalPlan.actualDistanceKM,
        occurrences: occurrences
      )
    )

    let restored = WholeShutoProductModel(
      database: model.database,
      checkpointStore: store
    )

    XCTAssertEqual(restored.phase, .planning)
    XCTAssertNil(restored.selectedRoute)
    XCTAssertFalse(restored.restoredFromCheckpoint)
    XCTAssertNil(restored.checkpointIssueCode)
    XCTAssertNil(store.checkpoint)
  }

  func testLargestCatalogCheckpointRoundTripsThroughItsFile()
    async throws
  {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("checkpoint.json")
    let laps = ShutoCircuitDefinition.loopLapRange.upperBound
    let source = WholeShutoProductModel(checkpointStore: nil)
    let circuitRoute = try source.planner.planCircuit(
      circuit: .c2InnerWithBayshore,
      entryFacilityID: "shuto.ic.c2.hatsudaiminami",
      exitFacilityID: "shuto.ic.c2.tomigaya",
      laps: laps
    )
    let record = Self.savedRouteRecord(
      circuitRoute.routePlan,
      templateParameters: [
        "source": "CIRCUIT",
        "preference": circuitRoute.preference.rawValue,
        "circuit_id": ShutoCircuitDefinition.c2InnerWithBayshore.circuitID,
        "laps": String(laps),
      ]
    )
    let model = WholeShutoProductModel(
      database: source.database,
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: WholeShutoFileCheckpointStore(fileURL: fileURL)
    )
    XCTAssertTrue(
      model.openSavedRoute(
        record,
        origin: ShutoCoordinate(latitude: 35.68, longitude: 139.69)
      )
    )
    for _ in 0..<1_000 where model.isUpdatingSurfaceRoute {
      await Task.yield()
    }
    model.startNavigationSimulation()
    _ = await model.pausePlayback()
    await advance(
      model,
      until: { $0.phase == .expressway && $0.progressFraction > 0 },
      maximumTicks: 1_000
    )
    await model.handleScenePhase(.background)
    let storedBytes = try Data(contentsOf: fileURL).count
    print(
      "Whole-Shuto checkpoint for \(laps) C2 laps: \(storedBytes) bytes"
    )

    let restored = WholeShutoProductModel(
      database: source.database,
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: WholeShutoFileCheckpointStore(fileURL: fileURL)
    )

    XCTAssertTrue(restored.restoredFromCheckpoint)
    XCTAssertEqual(restored.phase, .expressway)
    XCTAssertEqual(restored.selectedRoute?.routePlan, circuitRoute.routePlan)
    XCTAssertEqual(restored.circuitLaps, laps)
    XCTAssertEqual(restored.runtimeOccurrenceID, model.runtimeOccurrenceID)
    XCTAssertEqual(restored.progressFraction, model.progressFraction)
    XCTAssertNil(restored.checkpointIssueCode)

    restored.reset()
    XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    restored.reset()
    XCTAssertNil(restored.checkpointIssueCode)
  }

  func testReplayStepsLeaveTheCheckpointToPauseAndBackground()
    async throws
  {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: store)
    model.preparePreviewJourney()
    model.startNavigationSimulation()
    _ = await model.pausePlayback()
    await advance(model, until: { $0.phase == .expressway })
    await model.handleScenePhase(.background)
    let savesBeforeSteps = store.saveCount

    for _ in 0..<3 {
      await model.advanceSimulationForTesting()
    }
    XCTAssertEqual(model.phase, .expressway)
    XCTAssertEqual(store.saveCount, savesBeforeSteps)

    await model.handleScenePhase(.background)
    XCTAssertEqual(store.saveCount, savesBeforeSteps + 1)
    XCTAssertEqual(
      store.checkpoint?.progressFraction,
      model.progressFraction
    )
    XCTAssertEqual(
      store.checkpoint?.runtimeOccurrenceID,
      model.runtimeOccurrenceID
    )
  }

  func testCheckpointLoadFailureIsSilentlyInvalidated() {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: store)
    model.preparePreviewJourney()
    XCTAssertNotNil(store.checkpoint)

    store.loadError = .loadFailed
    let restored = WholeShutoProductModel(
      database: model.database,
      checkpointStore: store
    )

    XCTAssertEqual(restored.phase, .planning)
    XCTAssertNil(restored.selectedRoute)
    XCTAssertFalse(restored.restoredFromCheckpoint)
    XCTAssertNil(restored.checkpointIssueCode)
    XCTAssertNil(store.checkpoint)
    XCTAssertEqual(store.removeCount, 1)

    store.loadError = nil
    let nextLaunch = WholeShutoProductModel(
      database: model.database,
      checkpointStore: store
    )
    XCTAssertNil(nextLaunch.checkpointIssueCode)
    XCTAssertEqual(nextLaunch.phase, .planning)
  }

  func testCheckpointSchemaDriftIsSilentlyRemoved() throws {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: store)
    model.preparePreviewJourney()
    store.checkpoint = try XCTUnwrap(store.checkpoint)
      .replacingSchemaVersion("1.0")

    let restored = WholeShutoProductModel(
      database: model.database,
      checkpointStore: store
    )

    XCTAssertEqual(restored.phase, .planning)
    XCTAssertNil(restored.selectedRoute)
    XCTAssertFalse(restored.restoredFromCheckpoint)
    XCTAssertNil(restored.checkpointIssueCode)
    XCTAssertNil(store.checkpoint)
  }

  func testCheckpointSaveFailureInvalidatesTheOlderCheckpoint() async {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: store)
    model.preparePreviewJourney()
    XCTAssertNotNil(store.checkpoint)

    store.saveError = .saveFailed
    await model.handleScenePhase(.background)

    XCTAssertEqual(model.phase, .review)
    XCTAssertNotNil(model.selectedRoute)
    XCTAssertEqual(
      model.checkpointIssueCode,
      "WHOLE_SHUTO_CHECKPOINT_SAVE_FAILED"
    )
    XCTAssertNil(store.checkpoint)
    XCTAssertEqual(store.removeCount, 1)

    store.saveError = nil
    await model.handleScenePhase(.background)
    XCTAssertNil(model.checkpointIssueCode)
    XCTAssertNotNil(store.checkpoint)

    let restored = WholeShutoProductModel(
      database: model.database,
      checkpointStore: store
    )
    XCTAssertEqual(restored.phase, .planning)
    XCTAssertFalse(restored.restoredFromCheckpoint)
    XCTAssertNil(restored.checkpointIssueCode)
    XCTAssertNil(store.checkpoint)
  }

  func testFileCheckpointStoreAppliesWritesInTheOrderTheyWereAsked()
    async throws
  {
    let memory = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: memory)
    model.preparePreviewJourney()
    let older = try XCTUnwrap(memory.checkpoint)
    let newer = older.replacingSchemaVersion("newer")
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
      .appendingPathComponent("whole-shuto-journey-checkpoint.json")
    defer {
      try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }
    let store = WholeShutoFileCheckpointStore(fileURL: fileURL)

    // A background save asked for first is written first, so a later
    // synchronous save or remove is what the file ends with.
    let backgroundSave = Task { @MainActor in try await store.saveInBackground(older) }
    await Task.yield()
    try store.save(newer)
    try await backgroundSave.value
    XCTAssertEqual(try store.load(), newer)

    let supersededSave = Task { @MainActor in try await store.saveInBackground(older) }
    await Task.yield()
    try store.remove()
    try await supersededSave.value
    XCTAssertNil(try store.load())

    let saves = (0..<8).map { index in
      Task { @MainActor in
        try await store.saveInBackground(index == 7 ? newer : older)
      }
    }
    for save in saves { try await save.value }
    XCTAssertEqual(try store.load(), newer)
  }

  func testSupersededLiveCheckpointFailureLeavesTheNewerStateAlone()
    async throws
  {
    let store = WholeShutoGatedCheckpointStore()
    let model = WholeShutoForegroundReleaseFactory.makeModel(
      surfaceRouteResolver: WholeShutoInstructionSurfaceRouteResolver(),
      checkpointStore: store,
      liveLocationSource: WholeShutoBackgroundNavigationLocationSource(),
      speechOutput: WholeShutoRecordingSpeechOutput()
    )
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6812, longitude: 139.7671)
    )
    model.prepareCustomRouteDraft()
    model.selectCustomEntry(facilityID: "shuto.ic.b.urayasu")
    model.selectCustomExit(facilityID: "shuto.ic.9.fukudumi")
    XCTAssertTrue(model.applyCustomRoute())
    await waitForLiveNavigationPreparation(model)
    let started = await model.startLiveJourney()
    XCTAssertTrue(started)
    let removalsBefore = store.removeCount

    // The live checkpoint's background save is in flight when the driver
    // ends the journey, and then fails.
    store.holdsBackgroundSaves = true
    store.backgroundSaveError = .saveFailed
    let background = Task { @MainActor in await model.handleScenePhase(.background) }
    for _ in 0..<1_000 where store.pendingBackgroundSaves == 0 {
      await Task.yield()
    }
    XCTAssertEqual(store.pendingBackgroundSaves, 1)
    model.reset()
    XCTAssertEqual(store.removeCount, removalsBefore + 1)
    store.releaseBackgroundSave()
    await background.value

    XCTAssertNil(model.checkpointIssueCode)
    XCTAssertNil(store.checkpoint)
    XCTAssertEqual(store.removeCount, removalsBefore + 1)
  }

  func testCheckpointRemoveFailureIsVisibleAndRetryable() {
    let store = WholeShutoMemoryCheckpointStore()
    let model = WholeShutoProductModel(checkpointStore: store)
    model.preparePreviewJourney()
    XCTAssertNotNil(store.checkpoint)

    store.removeError = .removeFailed
    model.reset()

    XCTAssertEqual(model.phase, .planning)
    XCTAssertEqual(
      model.checkpointIssueCode,
      "WHOLE_SHUTO_CHECKPOINT_REMOVE_FAILED"
    )
    XCTAssertNotNil(store.checkpoint)

    store.removeError = nil
    model.reset()
    XCTAssertNil(model.checkpointIssueCode)
    XCTAssertNil(store.checkpoint)
  }

  func testExpresswayPreviewExplicitlyReportsTunnelEstimation() async {
    let model = WholeShutoProductModel(checkpointStore: nil)
    model.preparePreviewJourney()
    model.startNavigationSimulation()
    _ = await model.pausePlayback()

    await advance(
      model,
      until: {
        $0.phase == .expressway
          && $0.positionState == .tunnelEstimated
      },
      maximumTicks: 180
    )

    XCTAssertEqual(model.positionState, .tunnelEstimated)
    XCTAssertNil(model.navigationHeadingDegrees)
  }

  func testSimulationStartsOnTheGeographicMapWithRouteProgressTelemetry()
    async throws
  {
    let model = WholeShutoProductModel(checkpointStore: nil)
    model.prepareKasaiJunctionPreview(startsNavigation: true)
    _ = await model.pausePlayback()

    let initialRemaining = try XCTUnwrap(
      model.remainingJourneyDistanceMeters
    )
    XCTAssertEqual(model.mapMode, .geographic)
    XCTAssertGreaterThan(initialRemaining, 0)
    XCTAssertNotNil(model.nextReviewedJunctionPrompt)
    XCTAssertNotNil(model.distanceToNextReviewedJunctionMeters)

    await advance(
      model,
      until: {
        $0.phase == .expressway
          && $0.positionState == .networkPreview
          && $0.progressFraction > 0
      },
      maximumTicks: 1_000
    )

    let geometry = try XCTUnwrap(model.routeProgressGeometry)
    let current = try XCTUnwrap(model.currentCoordinate)
    XCTAssertGreaterThan(geometry.traveledCoordinates.count, 1)
    XCTAssertGreaterThan(geometry.remainingCoordinates.count, 1)
    XCTAssertEqual(geometry.traveledCoordinates.last, current)
    XCTAssertEqual(geometry.remainingCoordinates.first, current)
    XCTAssertNotNil(model.navigationHeadingDegrees)
    XCTAssertLessThan(
      try XCTUnwrap(model.remainingJourneyDistanceMeters),
      initialRemaining
    )
  }

  func testEntryTransitionRequiresOrderedObservationsBeforeExpressway()
    async
  {
    let model = WholeShutoProductModel(checkpointStore: nil)
    model.preparePreviewJourney()
    model.startNavigationSimulation()
    _ = await model.pausePlayback()

    await advance(model, until: { $0.phase == .entryTransition })

    XCTAssertEqual(model.progressFraction, 0)
    XCTAssertNil(model.runtimeOccurrenceID)
    XCTAssertEqual(model.positionState, .boundaryTransition)

    // The ramp mouth begins with micro-edges the matcher reports at
    // reduced confidence; HIGH must still arrive while the phase remains
    // entryTransition and before any occurrence is admitted.
    await advance(model, until: { $0.matcherConfidence == .high })

    XCTAssertEqual(model.matcherConfidence, .high)
    XCTAssertEqual(model.phase, .entryTransition)
    XCTAssertNil(model.runtimeOccurrenceID)

    await advance(
      model,
      until: { $0.phase == .expressway },
      maximumTicks: 1_000
    )

    XCTAssertEqual(model.phase, .expressway)
    XCTAssertNotNil(model.runtimeOccurrenceID)
    XCTAssertGreaterThan(model.progressFraction, 0)
  }

  func testReviewedJunctionSpeechIsActorOwnedAndNotRepeatedAfterRestore()
    async throws
  {
    let store = WholeShutoMemoryCheckpointStore()
    let initialOutput = WholeShutoRecordingSpeechOutput()
    let model = WholeShutoProductModel(
      checkpointStore: store,
      speechOutput: initialOutput,
      languageSelectionProvider: Self.testLanguages
    )
    model.prepareJunctionPreview(startsNavigation: true)

    let didReachJunction = await model.advanceSimulationToJunctionPreview()
    XCTAssertTrue(didReachJunction)

    let command = try XCTUnwrap(initialOutput.commands.only)
    XCTAssertEqual(command.languageCode, "ja-JP")
    XCTAssertTrue(command.spokenText.contains("大井ジャンクション"))
    XCTAssertTrue(command.synthesisText.contains("シーツー"))
    XCTAssertEqual(
      model.presentationProjection?.iPhone.maneuver,
      .branchLeft
    )
    XCTAssertEqual(
      model.presentationProjection?.iPhone.lanePreparation,
      GuidanceLanePreparation.none
    )
    XCTAssertEqual(
      model.activeJunctionPrompt?.movementID,
      "shuto.jct.oi.b-westbound-to-c2-outer"
    )

    await model.handleScenePhase(.background)

    let restoredOutput = WholeShutoRecordingSpeechOutput()
    let restored = WholeShutoProductModel(
      database: model.database,
      checkpointStore: store,
      speechOutput: restoredOutput,
      languageSelectionProvider: Self.testLanguages
    )
    XCTAssertEqual(restored.phase, .expressway)

    await advance(
      restored,
      until: {
        $0.speechStatus == .suppressed(.duplicate)
      },
      maximumTicks: 80
    )

    XCTAssertTrue(restoredOutput.commands.isEmpty)
    XCTAssertEqual(restored.speechStatus, .suppressed(.duplicate))
  }

  func testKasaiJunctionSpeechIsActorOwned() async throws {
    let output = WholeShutoRecordingSpeechOutput()
    let model = WholeShutoProductModel(
      checkpointStore: nil,
      speechOutput: output,
      languageSelectionProvider: Self.testLanguages
    )
    model.prepareKasaiJunctionPreview(startsNavigation: true)

    let didReachJunction = await model.advanceSimulationToJunctionPreview()
    XCTAssertTrue(didReachJunction)

    let command = try XCTUnwrap(output.commands.only)
    XCTAssertEqual(command.languageCode, "ja-JP")
    XCTAssertTrue(command.spokenText.contains("葛西ジャンクション"))
    XCTAssertTrue(command.synthesisText.contains("シーツー"))
    XCTAssertEqual(
      model.presentationProjection?.iPhone.maneuver,
      .branchLeft
    )
    XCTAssertEqual(
      model.presentationProjection?.iPhone.lanePreparation,
      GuidanceLanePreparation.none
    )
    XCTAssertEqual(
      model.presentationProjection?.iPhone.japaneseSignText,
      "東北道・常磐道"
    )
    XCTAssertEqual(
      model.activeJunctionPrompt?.movementID,
      "shuto.jct.kasai.b-westbound-to-c2-inner"
    )
  }

  func testTatsumiJunctionSpeechIsActorOwned() async throws {
    let output = WholeShutoRecordingSpeechOutput()
    let model = WholeShutoProductModel(
      checkpointStore: nil,
      speechOutput: output,
      languageSelectionProvider: Self.testLanguages
    )
    model.prepareTatsumiEastboundJunctionPreview(
      startsNavigation: true
    )

    let didReachJunction = await model.advanceSimulationToJunctionPreview()
    XCTAssertTrue(didReachJunction)

    let command = try XCTUnwrap(
      output.commands.last { $0.spokenText.contains("辰巳ジャンクション") }
    )
    XCTAssertEqual(command.languageCode, "ja-JP")
    // Each reviewed movement is spoken exactly once by the actor.
    XCTAssertEqual(
      output.commands.filter {
        $0.spokenText.contains("辰巳ジャンクション")
      }.count,
      1
    )
    XCTAssertTrue(
      command.synthesisText.contains("きゅうごうふかがわせん")
    )
    XCTAssertEqual(
      model.presentationProjection?.iPhone.maneuver,
      .branchLeft
    )
    XCTAssertEqual(
      model.presentationProjection?.iPhone.lanePreparation,
      GuidanceLanePreparation.none
    )
    XCTAssertEqual(
      model.presentationProjection?.iPhone.japaneseSignText,
      "箱崎"
    )
    XCTAssertEqual(
      model.activeJunctionPrompt?.movementID,
      "shuto.jct.tatsumi.b-eastbound-to-9-inbound"
    )
  }

  func testShinonomeRightBranchSpeechIsActorOwned() async throws {
    let output = WholeShutoRecordingSpeechOutput()
    let model = WholeShutoProductModel(
      checkpointStore: nil,
      speechOutput: output,
      languageSelectionProvider: Self.testLanguages
    )
    model.prepareShinonomeWestboundJunctionPreview(
      startsNavigation: true
    )

    let didReachJunction = await model.advanceSimulationToJunctionPreview()
    XCTAssertTrue(didReachJunction)

    let command = try XCTUnwrap(
      output.commands.last { $0.spokenText.contains("東雲ジャンクション") }
    )
    XCTAssertEqual(command.languageCode, "ja-JP")
    // Each reviewed movement is spoken exactly once by the actor.
    XCTAssertEqual(
      output.commands.filter {
        $0.spokenText.contains("東雲ジャンクション")
      }.count,
      1
    )
    XCTAssertTrue(
      command.synthesisText.contains("じゅうごうはるみせん")
    )
    XCTAssertEqual(
      model.presentationProjection?.iPhone.maneuver,
      .branchRight
    )
    XCTAssertEqual(
      model.presentationProjection?.iPhone.lanePreparation,
      GuidanceLanePreparation.none
    )
    XCTAssertEqual(
      model.presentationProjection?.iPhone.japaneseSignText,
      "晴海"
    )
    XCTAssertEqual(
      model.activeJunctionPrompt?.movementID,
      "shuto.jct.shinonome.b-westbound-to-10-inbound"
    )
  }

  func testReviewedJunctionKeepsInterfaceAndVoiceLanguagesIndependent()
    async throws
  {
    let output = WholeShutoRecordingSpeechOutput()
    let languages = NavigationLanguageSelection(
      interfaceLocale: .english,
      guidanceVoiceLocale: .simplifiedChinese
    )
    let model = WholeShutoProductModel(
      checkpointStore: nil,
      speechOutput: output,
      languageSelectionProvider: { languages }
    )
    model.prepareJunctionPreview(startsNavigation: true)

    let didReachJunction = await model.advanceSimulationToJunctionPreview()
    XCTAssertTrue(didReachJunction)

    // Oi's long approach edge now carries a 900 m preparation cue, so the
    // first cue the preview reaches is the preparation.
    let projection = try XCTUnwrap(model.presentationProjection)
    let command = try XCTUnwrap(output.commands.only)
    XCTAssertEqual(projection.interfaceLocale, .english)
    XCTAssertEqual(projection.iPhone.localizedDecisionPointName, "Oi JCT")
    XCTAssertEqual(
      projection.iPhone.localizedDisplayText,
      "Ahead: Branch left for the C2 Outer Loop"
    )
    XCTAssertEqual(projection.iPhone.japaneseSignText, "東名・中央道")
    XCTAssertEqual(projection.carPlay.japaneseSignText, "東名・中央道")
    XCTAssertEqual(projection.voice.locale, .simplifiedChinese)
    XCTAssertEqual(
      projection.voice.spokenText,
      "前方，在大井枢纽向左分岔，驶入 C2 外环"
    )
    XCTAssertEqual(command.languageCode, "zh-CN")
    XCTAssertEqual(command.spokenText, projection.voice.spokenText)
    XCTAssertTrue(command.synthesisText.contains("C 二"))
  }

  private func advance(
    _ model: WholeShutoProductModel,
    until predicate: (WholeShutoProductModel) -> Bool,
    maximumTicks: Int = 80,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    for _ in 0..<maximumTicks {
      if predicate(model) {
        return
      }
      await model.advanceSimulationForTesting()
    }
    XCTFail(
      "Whole-Shuto simulation did not reach the expected state",
      file: file,
      line: line
    )
  }

  private static func testLanguages() -> NavigationLanguageSelection {
    NavigationLanguageSelection(
      interfaceLocale: .simplifiedChinese,
      guidanceVoiceLocale: .japanese
    )
  }

  private static func liveLocationEnvelope(
    id: String,
    coordinate: ShutoCoordinate,
    atMilliseconds: Int = 1_000,
    courseDegrees: Double = 90,
    courseAccuracyDegrees: Double? = nil,
    speedMetersPerSecond: Double = 10,
    horizontalAccuracyMeters: Double = 5
  ) -> CoreLocationObservationEnvelope {
    CoreLocationObservationEnvelope(
      observation: RouteMatcherObservation(
        id: id,
        observedAtMilliseconds: atMilliseconds,
        receivedAtMilliseconds: atMilliseconds,
        coordinate: MatcherCoordinate(
          latitude: coordinate.latitude,
          longitude: coordinate.longitude
        ),
        horizontalAccuracyMeters: horizontalAccuracyMeters,
        courseDegrees: courseDegrees,
        courseAccuracyDegrees: courseAccuracyDegrees,
        speedMetersPerSecond: speedMetersPerSecond,
        speedAccuracyMetersPerSecond: 1,
        source: .phone
      ),
      provenance: CoreLocationObservationProvenance(
        deliverySource: .deviceOrUndisclosed,
        sourceInformationAvailable: true,
        isSimulatedBySoftware: false,
        carPlayConnectionContext: .disconnected,
        matcherCalibrationCohort: .phone,
        courseAccuracyDegrees: 2,
        speedAccuracyMetersPerSecond: 1,
        observationAgeMilliseconds: 0
      )
    )
  }

  private static func bearing(
    from start: ShutoCoordinate,
    to end: ShutoCoordinate
  ) -> Double {
    let startLatitude = start.latitude * .pi / 180
    let endLatitude = end.latitude * .pi / 180
    let longitudeDelta = (end.longitude - start.longitude) * .pi / 180
    let y = sin(longitudeDelta) * cos(endLatitude)
    let x =
      cos(startLatitude) * sin(endLatitude)
      - sin(startLatitude) * cos(endLatitude) * cos(longitudeDelta)
    let degrees = atan2(y, x) * 180 / .pi
    return degrees >= 0 ? degrees : degrees + 360
  }

  /// Fractions along an edge at which a car at highway speed reports a
  /// 1 Hz fix: never more than 25 m apart, so a long edge is not crossed in
  /// one second.
  private static func oneHertzFractions(
    from start: ShutoCoordinate,
    to end: ShutoCoordinate
  ) -> [Double] {
    let metersPerDegree = 6_371_000.0 * .pi / 180
    let meters = hypot(
      (end.latitude - start.latitude) * metersPerDegree,
      (end.longitude - start.longitude) * metersPerDegree
        * cos(start.latitude * .pi / 180)
    )
    let count = max(2, Int((meters / 25).rounded(.up)))
    return (0..<count).map { (Double($0) + 0.5) / Double(count) }
  }

  private static func interpolate(
    from start: ShutoCoordinate,
    to end: ShutoCoordinate,
    fraction: Double
  ) -> ShutoCoordinate {
    ShutoCoordinate(
      latitude: start.latitude
        + (end.latitude - start.latitude) * fraction,
      longitude: start.longitude
        + (end.longitude - start.longitude) * fraction
    )
  }

  private static func savedRouteRecord(
    _ routePlan: RoutePlan,
    templateParameters: [String: String] = [:]
  ) -> SavedRouteRecord {
    SavedRouteRecord(
      id: "saved-route.test",
      displayName: "Test route",
      savedAt: "2026-08-11T12:00:00Z",
      origin: .authoredHere,
      document: SharedRouteDocument(
        evidenceState: .communityCandidate,
        templateParameters: templateParameters,
        routePlan: routePlan
      )
    )
  }
}

extension Collection {
  fileprivate var only: Element? {
    count == 1 ? first : nil
  }
}

@MainActor
private final class WholeShutoMemoryCheckpointStore:
  WholeShutoJourneyCheckpointStoring
{
  var checkpoint: WholeShutoJourneyCheckpoint?
  var loadError: WholeShutoTestCheckpointStoreError?
  var saveError: WholeShutoTestCheckpointStoreError?
  var removeError: WholeShutoTestCheckpointStoreError?
  private(set) var loadCount = 0
  private(set) var saveCount = 0
  private(set) var removeCount = 0

  func load() throws -> WholeShutoJourneyCheckpoint? {
    loadCount += 1
    if let loadError { throw loadError }
    return checkpoint
  }

  func save(_ checkpoint: WholeShutoJourneyCheckpoint) throws {
    saveCount += 1
    if let saveError { throw saveError }
    self.checkpoint = checkpoint
  }

  func remove() throws {
    removeCount += 1
    if let removeError { throw removeError }
    checkpoint = nil
  }
}

/// Once `holdsBackgroundSaves` is set, holds each background save until the
/// test releases it.
@MainActor
private final class WholeShutoGatedCheckpointStore:
  WholeShutoJourneyCheckpointStoring
{
  var checkpoint: WholeShutoJourneyCheckpoint?
  var holdsBackgroundSaves = false
  var backgroundSaveError: WholeShutoTestCheckpointStoreError?
  private(set) var removeCount = 0
  private(set) var pendingBackgroundSaves = 0
  private var gate: CheckedContinuation<Void, Never>?

  func load() throws -> WholeShutoJourneyCheckpoint? { checkpoint }

  func save(_ checkpoint: WholeShutoJourneyCheckpoint) throws {
    self.checkpoint = checkpoint
  }

  func saveInBackground(_ checkpoint: WholeShutoJourneyCheckpoint) async throws {
    if holdsBackgroundSaves {
      pendingBackgroundSaves += 1
      await withCheckedContinuation { gate = $0 }
      pendingBackgroundSaves -= 1
      if let backgroundSaveError { throw backgroundSaveError }
    }
    self.checkpoint = checkpoint
  }

  func releaseBackgroundSave() {
    gate?.resume()
    gate = nil
  }

  func remove() throws {
    removeCount += 1
    checkpoint = nil
  }
}

private enum WholeShutoTestCheckpointStoreError: Error {
  case loadFailed
  case saveFailed
  case removeFailed
}

@MainActor
private final class WholeShutoMemorySavedRouteLibraryStore:
  SavedRouteLibraryStoring
{
  var library: SavedRouteLibraryDocument?

  func load() throws -> SavedRouteLibraryDocument? {
    library
  }

  func save(_ library: SavedRouteLibraryDocument) throws {
    self.library = library
  }
}

private actor WholeShutoOutOfOrderSurfaceRouteResolver:
  WholeShutoSurfaceRouteResolving
{
  private var slowEntry: ShutoCoordinate?
  private var slowExit: ShutoCoordinate?

  func configure(
    slowEntry: ShutoCoordinate,
    slowExit: ShutoCoordinate
  ) {
    self.slowEntry = slowEntry
    self.slowExit = slowExit
  }

  func route(
    from origin: ShutoCoordinate,
    to destination: ShutoCoordinate
  ) async -> WholeShutoSurfaceRoute? {
    let isSlow = destination == slowEntry || origin == slowExit
    let delay: UInt64 = isSlow ? 180_000_000 : 20_000_000
    let route = WholeShutoSurfaceRoute(
      coordinates: [origin, destination],
      distanceMeters: Double(delay),
      expectedTravelTimeSeconds: 1,
      instructions: []
    )
    return await Task.detached {
      try? await Task.sleep(nanoseconds: delay)
      return route
    }.value
  }
}

private actor WholeShutoRecoveringSurfaceRouteResolver:
  WholeShutoSurfaceRouteResolving
{
  private var isAvailable = false

  func setAvailable(_ isAvailable: Bool) {
    self.isAvailable = isAvailable
  }

  func route(
    from origin: ShutoCoordinate,
    to destination: ShutoCoordinate
  ) async -> WholeShutoSurfaceRoute? {
    guard isAvailable else { return nil }
    return WholeShutoSurfaceRoute(
      coordinates: [origin, destination],
      distanceMeters: 1_200,
      expectedTravelTimeSeconds: 180,
      instructions: []
    )
  }
}

private actor WholeShutoRecoverableSurfaceRouteResolver: WholeShutoSurfaceRouteResolving {
  private var unavailable = false

  func setUnavailable(_ value: Bool) {
    unavailable = value
  }

  func route(
    from origin: ShutoCoordinate,
    to destination: ShutoCoordinate
  ) async -> WholeShutoSurfaceRoute? {
    guard !unavailable else { return nil }
    return await WholeShutoInstructionSurfaceRouteResolver().route(
      from: origin, to: destination
    )
  }
}

private struct WholeShutoInstructionSurfaceRouteResolver:
  WholeShutoSurfaceRouteResolving
{
  func route(
    from origin: ShutoCoordinate,
    to destination: ShutoCoordinate
  ) async -> WholeShutoSurfaceRoute? {
    WholeShutoSurfaceRoute(
      coordinates: [origin, destination],
      distanceMeters: 1_200,
      expectedTravelTimeSeconds: 180,
      instructions: ["Continue on local road"],
      steps: [
        WholeShutoSurfaceRouteStep(
          instruction: "Continue on local road",
          distanceMeters: 1_200
        )
      ],
      guidanceLanguageCode: "en-US"
    )
  }
}

private struct WholeShutoMultiStepSurfaceRouteResolver:
  WholeShutoSurfaceRouteResolving
{
  func route(
    from origin: ShutoCoordinate,
    to destination: ShutoCoordinate
  ) async -> WholeShutoSurfaceRoute? {
    WholeShutoSurfaceRoute(
      coordinates: [origin, destination],
      distanceMeters: 1_200,
      expectedTravelTimeSeconds: 180,
      instructions: ["Continue straight", "Turn left"],
      steps: [
        WholeShutoSurfaceRouteStep(
          instruction: "Continue straight",
          distanceMeters: 700
        ),
        WholeShutoSurfaceRouteStep(
          instruction: "Turn left",
          distanceMeters: 500
        ),
      ],
      guidanceLanguageCode: "en-US"
    )
  }
}

private actor WholeShutoRankingSurfaceRouteResolver:
  WholeShutoSurfaceRouteResolving
{
  private let preferredEntry: ShutoCoordinate
  private let preferredExit: ShutoCoordinate

  init(
    preferredEntry: ShutoCoordinate,
    preferredExit: ShutoCoordinate
  ) {
    self.preferredEntry = preferredEntry
    self.preferredExit = preferredExit
  }

  func route(
    from origin: ShutoCoordinate,
    to destination: ShutoCoordinate
  ) async -> WholeShutoSurfaceRoute? {
    let isPreferredLeg =
      destination == preferredEntry || origin == preferredExit
    let distanceMeters = isPreferredLeg ? 200.0 : 50_000.0
    let expectedTravelTimeSeconds =
      isPreferredLeg ? 20.0 : 20_000.0
    return WholeShutoSurfaceRoute(
      coordinates: [origin, destination],
      distanceMeters: distanceMeters,
      expectedTravelTimeSeconds: expectedTravelTimeSeconds,
      instructions: []
    )
  }
}

@MainActor
private final class WholeShutoBackgroundNavigationLocationSource:
  ForegroundNavigationLocationSource
{
  weak var delegate: (any ForegroundNavigationLocationSourceDelegate)?
  private(set) var authorizationStatus: CLAuthorizationStatus
  let accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
  let supportsBackgroundNavigation = true
  private(set) var authorizationRequestCount = 0
  private(set) var startCount = 0
  private(set) var stopCount = 0
  private(set) var backgroundNavigationEnabled = false

  init(
    authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
  ) {
    self.authorizationStatus = authorizationStatus
  }

  func requestWhenInUseAuthorization() {
    authorizationRequestCount += 1
  }

  func setBackgroundNavigationEnabled(_ enabled: Bool) {
    backgroundNavigationEnabled = enabled
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
}

private actor WholeShutoPartiallyUnavailableChoiceResolver:
  WholeShutoSurfaceRouteResolving
{
  private let unavailableEntry: ShutoCoordinate

  init(unavailableEntry: ShutoCoordinate) {
    self.unavailableEntry = unavailableEntry
  }

  func route(
    from origin: ShutoCoordinate,
    to destination: ShutoCoordinate
  ) async -> WholeShutoSurfaceRoute? {
    guard destination != unavailableEntry else {
      return nil
    }
    return WholeShutoSurfaceRoute(
      coordinates: [origin, destination],
      distanceMeters: 1_000,
      expectedTravelTimeSeconds: 120,
      instructions: []
    )
  }
}

private actor WholeShutoCountingSurfaceRouteResolver:
  WholeShutoSurfaceRouteResolving
{
  private var requests = 0

  func route(
    from origin: ShutoCoordinate,
    to destination: ShutoCoordinate
  ) async -> WholeShutoSurfaceRoute? {
    requests += 1
    return WholeShutoSurfaceRoute(
      coordinates: [origin, destination],
      distanceMeters: 1_000,
      expectedTravelTimeSeconds: 120,
      instructions: ["Continue"]
    )
  }

  func requestCount() -> Int { requests }
}

@MainActor
private final class WholeShutoUnexpectedLocationProvider:
  C2NavigationCurrentLocationProviding
{
  private(set) var requestCount = 0

  func currentCoordinate() async throws -> SurfaceCoordinate {
    requestCount += 1
    throw C2NavigationDemoError.locationUnavailable
  }
}

extension WholeShutoJourneyCheckpoint {
  fileprivate func replacingSchemaVersion(_ schemaVersion: String) -> Self {
    WholeShutoJourneyCheckpoint(
      schemaVersion: schemaVersion,
      networkSnapshotID: networkSnapshotID,
      originQuery: originQuery,
      destinationQuery: destinationQuery,
      origin: origin,
      destination: destination,
      entryFacilityID: entryFacilityID,
      exitFacilityID: exitFacilityID,
      routePlan: routePlan,
      preference: preference,
      routeSelectionSource: routeSelectionSource,
      driveMode: driveMode,
      phase: phase,
      progressFraction: progressFraction,
      runtimeOccurrenceID: runtimeOccurrenceID,
      runtimeFractionAlongOccurrence: runtimeFractionAlongOccurrence,
      consumedGuidancePromptIDs: consumedGuidancePromptIDs,
      mapMode: mapMode,
      accessRoute: accessRoute,
      egressRoute: egressRoute,
      circuitID: circuitID,
      circuitLaps: circuitLaps,
      runtimeAssetIdentity: runtimeAssetIdentity,
      liveNavigationCheckpoint: liveNavigationCheckpoint
    )
  }

  fileprivate func replacingRoutePlan(_ routePlan: RoutePlan) -> Self {
    WholeShutoJourneyCheckpoint(
      schemaVersion: schemaVersion,
      networkSnapshotID: networkSnapshotID,
      originQuery: originQuery,
      destinationQuery: destinationQuery,
      origin: origin,
      destination: destination,
      entryFacilityID: entryFacilityID,
      exitFacilityID: exitFacilityID,
      routePlan: routePlan,
      preference: preference,
      routeSelectionSource: routeSelectionSource,
      driveMode: driveMode,
      phase: phase,
      progressFraction: progressFraction,
      runtimeOccurrenceID: runtimeOccurrenceID,
      runtimeFractionAlongOccurrence: runtimeFractionAlongOccurrence,
      consumedGuidancePromptIDs: consumedGuidancePromptIDs,
      mapMode: mapMode,
      accessRoute: accessRoute,
      egressRoute: egressRoute,
      circuitID: circuitID,
      circuitLaps: circuitLaps,
      runtimeAssetIdentity: runtimeAssetIdentity,
      liveNavigationCheckpoint: liveNavigationCheckpoint
    )
  }

  fileprivate func replacingDriveMode(
    _ driveMode: WholeShutoDriveMode,
    progressFraction: Double
  ) -> Self {
    WholeShutoJourneyCheckpoint(
      schemaVersion: schemaVersion,
      networkSnapshotID: networkSnapshotID,
      originQuery: originQuery,
      destinationQuery: destinationQuery,
      origin: origin,
      destination: destination,
      entryFacilityID: entryFacilityID,
      exitFacilityID: exitFacilityID,
      routePlan: routePlan,
      preference: preference,
      routeSelectionSource: routeSelectionSource,
      driveMode: driveMode,
      phase: phase,
      progressFraction: progressFraction,
      runtimeOccurrenceID: runtimeOccurrenceID,
      runtimeFractionAlongOccurrence: runtimeFractionAlongOccurrence,
      consumedGuidancePromptIDs: consumedGuidancePromptIDs,
      mapMode: mapMode,
      accessRoute: accessRoute,
      egressRoute: egressRoute,
      circuitID: circuitID,
      circuitLaps: circuitLaps,
      runtimeAssetIdentity: runtimeAssetIdentity,
      liveNavigationCheckpoint: liveNavigationCheckpoint
    )
  }

  fileprivate func replacingRuntimeAssetIdentity(
    _ runtimeAssetIdentity: ShutoRuntimeAssetIdentity?
  ) -> Self {
    WholeShutoJourneyCheckpoint(
      schemaVersion: schemaVersion,
      networkSnapshotID: networkSnapshotID,
      originQuery: originQuery,
      destinationQuery: destinationQuery,
      origin: origin,
      destination: destination,
      entryFacilityID: entryFacilityID,
      exitFacilityID: exitFacilityID,
      routePlan: routePlan,
      preference: preference,
      routeSelectionSource: routeSelectionSource,
      driveMode: driveMode,
      phase: phase,
      progressFraction: progressFraction,
      runtimeOccurrenceID: runtimeOccurrenceID,
      runtimeFractionAlongOccurrence: runtimeFractionAlongOccurrence,
      consumedGuidancePromptIDs: consumedGuidancePromptIDs,
      mapMode: mapMode,
      accessRoute: accessRoute,
      egressRoute: egressRoute,
      circuitID: circuitID,
      circuitLaps: circuitLaps,
      runtimeAssetIdentity: runtimeAssetIdentity,
      liveNavigationCheckpoint: liveNavigationCheckpoint
    )
  }
}

@MainActor
private final class WholeShutoRecordingPlaceResolver:
  C2NavigationPlaceResolving
{
  private(set) var queries: [String] = []

  func resolve(
    query: String,
    near _: SurfaceCoordinate?
  ) async throws -> C2NavigationResolvedPlace {
    queries.append(query)
    return C2NavigationResolvedPlace(
      title: query,
      coordinate: SurfaceCoordinate(
        latitude: 35.4437,
        longitude: 139.6468
      )
    )
  }
}

@MainActor

private final class SpeechRecoveryAppOutput: GuidanceSpeechOutput {
  var eventHandler: ((GuidanceSpeechOutputEvent) -> Void)?
  var autoFinish = false
  var active: GuidanceSpeechIdentity?
  var commands: [GuidanceSpeechCommand] = []
  var stopCount = 0
  var failNextReleased = false
  var failedCommand: GuidanceSpeechCommand?
  func speak(_ command: GuidanceSpeechCommand) throws {
    if failNextReleased, command.identity.anchorID != "PROVIDER_SURFACE_STEP",
      command.identity.anchorID != "JOURNEY_STATUS"
    {
      failNextReleased = false
      failedCommand = command
      throw GuidanceSpeechOutputError.audioSessionActivationFailed
    }
    commands.append(command)
    active = command.identity
    eventHandler?(.didStart(command.identity))
    if autoFinish {
      active = nil
      eventHandler?(.didFinish(command.identity))
    }
  }
  func finishActive() {
    guard let identity = active else { return }
    active = nil
    eventHandler?(.didFinish(identity))
  }
  func stop() {
    stopCount += 1
    active = nil
  }
}
/// The instruction resolver's leg, ending `endOffsetDegreesNorth` away from
/// the requested destination, counting every request it answers.
private actor CountingSurfaceRouteResolver: WholeShutoSurfaceRouteResolving {
  private let endOffsetDegreesNorth: Double
  private(set) var requestCount = 0

  init(endOffsetDegreesNorth: Double) {
    self.endOffsetDegreesNorth = endOffsetDegreesNorth
  }

  func route(
    from origin: ShutoCoordinate, to destination: ShutoCoordinate
  ) async -> WholeShutoSurfaceRoute? {
    requestCount += 1
    return await WholeShutoInstructionSurfaceRouteResolver().route(
      from: origin,
      to: ShutoCoordinate(
        latitude: destination.latitude + endOffsetDegreesNorth,
        longitude: destination.longitude))
  }
}

private struct SpeechRecoveryShortStepResolver: WholeShutoSurfaceRouteResolving {
  func route(
    from origin: ShutoCoordinate, to destination: ShutoCoordinate
  ) async -> WholeShutoSurfaceRoute? {
    WholeShutoSurfaceRoute(
      coordinates: [origin, destination], distanceMeters: 1_200,
      expectedTravelTimeSeconds: 180,
      instructions: ["Continue straight", "Turn left at A", "Turn right at B"],
      steps: [
        .init(instruction: "Continue straight", distanceMeters: 350),
        .init(instruction: "Turn left at A", distanceMeters: 100),
        .init(instruction: "Turn right at B", distanceMeters: 750),
      ], guidanceLanguageCode: "en-US")
  }
}

@MainActor

private final class LiveTestClock: @unchecked Sendable {
  var milliseconds = 1_000
}

private final class WholeShutoRecordingSpeechOutput:
  GuidanceSpeechOutput
{
  var eventHandler: ((GuidanceSpeechOutputEvent) -> Void)?
  var selectedVoiceProfile: GuidanceSpeechVoiceProfile?
  private(set) var commands: [GuidanceSpeechCommand] = []

  func speak(_ command: GuidanceSpeechCommand) {
    commands.append(command)
    eventHandler?(.didStart(command.identity))
    eventHandler?(.didFinish(command.identity))
  }

  func stop() {}
}

private actor WholeShutoGatedSurfaceRouteResolver: WholeShutoSurfaceRouteResolving {
  private var isReleased = false
  private var pending: [CheckedContinuation<Void, Never>] = []

  func release() {
    isReleased = true
    let requests = pending
    pending.removeAll()
    for request in requests { request.resume() }
  }

  func route(from origin: ShutoCoordinate, to destination: ShutoCoordinate) async
    -> WholeShutoSurfaceRoute?
  {
    if !isReleased { await withCheckedContinuation { pending.append($0) } }
    return await WholeShutoPreviewSurfaceRouteResolver().route(from: origin, to: destination)
  }
}

/// Holds the first route's admission until the model cancels it, and answers
/// every later route at once.
/// Holds the resolver call for the route the test replaces until that
/// resolution is cancelled. Each route's resolver runs in its own detached
/// task, so calls arrive in no fixed order: the held route is named by its
/// plan, not by which call comes first.
private final class ReplacedRouteAdmissionHold: Sendable {
  static let heldRouteCode = "TEST_HELD_ROUTE"
  static let laterRouteCode = "TEST_LATER_ROUTE"
  private struct State {
    var heldRoutePlanID: String?
    var heldFinished = false
    var heldSawCancellation = false
  }
  private let state = Mutex(State())

  var heldFinished: Bool { state.withLock { $0.heldFinished } }
  var heldSawCancellation: Bool { state.withLock { $0.heldSawCancellation } }

  func holdRoute(planID: String) {
    state.withLock { $0.heldRoutePlanID = planID }
  }

  func resolve(
    _ route: ShutoPlannedRoute
  ) -> WholeShutoLiveJourneyAdmissionResolution {
    let deadline = Date().addingTimeInterval(10)
    // The held route's own resolution can start before the test names it.
    var heldID = state.withLock { $0.heldRoutePlanID }
    while heldID == nil, Date() < deadline {
      Thread.sleep(forTimeInterval: 0.005)
      heldID = state.withLock { $0.heldRoutePlanID }
    }
    guard route.routePlan.id == heldID else {
      return .unavailable(Self.laterRouteCode)
    }
    while !Task.isCancelled, Date() < deadline {
      Thread.sleep(forTimeInterval: 0.005)
    }
    let cancelled = Task.isCancelled
    state.withLock { state in
      state.heldFinished = true
      state.heldSawCancellation = cancelled
    }
    return .unavailable(Self.heldRouteCode)
  }
}
