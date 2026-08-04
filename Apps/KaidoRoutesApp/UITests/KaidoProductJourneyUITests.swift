import XCTest

@MainActor
final class KaidoProductJourneyUITests: XCTestCase {
  func testDefaultLaunchMakesWholeShutoMapTheProduct() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-RESET-NAVIGATION-CHECKPOINT",
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
    ]
    app.launch()

    XCTAssertTrue(
      element("whole-shuto-product", in: app)
        .waitForExistence(timeout: 5)
    )
    XCTAssertEqual(
      element("whole-shuto-product", in: app).value as? String,
      "PLANNING"
    )
    XCTAssertTrue(
      element("whole-shuto-geographic-map", in: app).exists
    )
    XCTAssertTrue(element("whole-shuto-current-location", in: app).exists)
    // Route first: circuit experiences lead the planning dock and the
    // destination search remains available as an optional continuation.
    XCTAssertTrue(
      element("whole-shuto-circuit-experiences", in: app).exists
    )
    XCTAssertTrue(
      element(
        "whole-shuto-circuit-option-shuto.circuit.c2-inner-bayshore",
        in: app
      ).exists
    )
    XCTAssertTrue(
      element(
        "whole-shuto-circuit-option-shuto.circuit.c1-inner",
        in: app
      ).exists
    )
    // The destination composer stays collapsed until the driver opts in.
    XCTAssertFalse(
      element("whole-shuto-destination-search", in: app).exists
    )
    let destinationToggle = element(
      "whole-shuto-destination-toggle",
      in: app
    )
    XCTAssertTrue(destinationToggle.exists)
    destinationToggle.tap()
    XCTAssertTrue(
      element("whole-shuto-destination-search", in: app)
        .waitForExistence(timeout: 3)
    )
    XCTAssertTrue(element("whole-shuto-plan-route", in: app).exists)
    destinationToggle.tap()
    assertMapFirstPlanningLayout(in: app)

    let homeScreenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    homeScreenshot.name = "Whole Shuto route-first home"
    homeScreenshot.lifetime = .keepAlways
    add(homeScreenshot)
  }

  func testTrackMapPresentsWholeCircuitInOneFrame() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-RESET-NAVIGATION-CHECKPOINT",
      "-WHOLE-SHUTO-TRACK-MAP-PREVIEW",
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
    ]
    app.launch()

    // The circuit review opens on the whole-route track map: one frame,
    // no zoom, replacing the semantic-zoom network diagram.
    XCTAssertTrue(
      element("whole-shuto-track-map", in: app)
        .waitForExistence(timeout: 8)
    )
    XCTAssertTrue(
      element("whole-shuto-review-journey", in: app)
        .waitForExistence(timeout: 8)
    )

    let trackMapScreenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    trackMapScreenshot.name = "Whole-route track map"
    trackMapScreenshot.lifetime = .keepAlways
    add(trackMapScreenshot)
  }

  func testCircuitSelectionOffersEntrancesAndLaps() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-RESET-NAVIGATION-CHECKPOINT",
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
    ]
    app.launch()

    let circuitCard = element(
      "whole-shuto-circuit-option-shuto.circuit.c2-inner-bayshore",
      in: app
    )
    XCTAssertTrue(circuitCard.waitForExistence(timeout: 5))
    circuitCard.tap()

    // The panel derives the pairing (entrance → exit plus tariff band)
    // asynchronously, keeps a lap control for loops, and offers one start
    // action; a lap change is reflected before any journey starts.
    let lapsValue = element("whole-shuto-circuit-laps", in: app)
    XCTAssertTrue(lapsValue.waitForExistence(timeout: 5))
    XCTAssertTrue(
      element("whole-shuto-start-circuit", in: app).exists
    )
    XCTAssertTrue(
      element("whole-shuto-circuit-pairing", in: app)
        .waitForExistence(timeout: 15)
    )
    XCTAssertTrue(
      element("whole-shuto-circuit-pairing-tariff", in: app)
        .waitForExistence(timeout: 10)
    )
    // Ranked entrance alternatives stay one disclosure away.
    element("whole-shuto-circuit-alternatives", in: app).tap()
    XCTAssertTrue(
      app.descendants(matching: .any).matching(
        NSPredicate(
          format: "identifier BEGINSWITH %@",
          "whole-shuto-circuit-entrance-"
        )
      ).firstMatch.waitForExistence(timeout: 5)
    )

    element("whole-shuto-circuit-laps-increase", in: app).tap()
    let lapsUpdated = expectation(
      for: NSPredicate(format: "value == %@", "2"),
      evaluatedWith: lapsValue
    )
    wait(for: [lapsUpdated], timeout: 5)

    // Dismissing the draft returns to the circuit cards.
    element("whole-shuto-circuit-close", in: app).tap()
    XCTAssertTrue(circuitCard.waitForExistence(timeout: 5))
  }

  func testDestinationSearchSelectsOneResolvedPlace() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-RESET-NAVIGATION-CHECKPOINT",
      "-WHOLE-SHUTO-SEARCH-PREVIEW",
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
    ]
    app.launch()

    // The destination composer is a collapsed optional continuation.
    let destinationToggle = element(
      "whole-shuto-destination-toggle",
      in: app
    )
    XCTAssertTrue(destinationToggle.waitForExistence(timeout: 5))
    destinationToggle.tap()
    let destination = app.textFields[
      "whole-shuto-destination-search"
    ]
    XCTAssertTrue(destination.waitForExistence(timeout: 5))
    destination.tap()
    destination.typeText("东京")

    let suggestion = app.buttons[
      "whole-shuto-place-suggestion-preview.tokyo-tower"
    ]
    XCTAssertTrue(suggestion.waitForExistence(timeout: 5))

    let suggestionsScreenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    suggestionsScreenshot.name = "Whole Shuto destination suggestions"
    suggestionsScreenshot.lifetime = .keepAlways
    add(suggestionsScreenshot)

    suggestion.tap()

    XCTAssertTrue(
      element("whole-shuto-selected-destination", in: app)
        .waitForExistence(timeout: 5)
    )
    XCTAssertEqual(destination.value as? String, "东京塔")
    XCTAssertTrue(app.buttons["whole-shuto-plan-route"].isEnabled)

    let selectedDestinationScreenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    selectedDestinationScreenshot.name = "Whole Shuto selected destination"
    selectedDestinationScreenshot.lifetime = .keepAlways
    add(selectedDestinationScreenshot)

    app.buttons["whole-shuto-plan-route"].tap()
    XCTAssertTrue(
      element("whole-shuto-route-selection", in: app)
        .waitForExistence(timeout: 5)
    )
    XCTAssertEqual(
      element("whole-shuto-product", in: app).value as? String,
      "REVIEW"
    )
    XCTAssertTrue(
      element("whole-shuto-route-option-0", in: app).isSelected
    )
    let recommendedRouteValue =
      element("whole-shuto-route-option-0", in: app).value as? String
    XCTAssertTrue(recommendedRouteValue?.contains("全程约") == true)
    XCTAssertTrue(recommendedRouteValue?.contains("分钟") == true)
    let reviewJourney = app.buttons["whole-shuto-review-journey"]
    XCTAssertTrue(reviewJourney.isEnabled)

    let plannedRoutesScreenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    plannedRoutesScreenshot.name = "Whole Shuto planned destination routes"
    plannedRoutesScreenshot.lifetime = .keepAlways
    add(plannedRoutesScreenshot)

    reviewJourney.tap()
    XCTAssertTrue(
      element("whole-shuto-journey-review", in: app)
        .waitForExistence(timeout: 3)
    )
    XCTAssertTrue(
      element("whole-shuto-journey-total-distance", in: app).exists
    )
    XCTAssertTrue(
      element("whole-shuto-journey-estimated-duration", in: app).exists
    )
    XCTAssertTrue(element("whole-shuto-access-leg", in: app).exists)
    XCTAssertTrue(element("whole-shuto-expressway-leg", in: app).exists)
    XCTAssertTrue(element("whole-shuto-egress-leg", in: app).exists)
    XCTAssertEqual(
      element("whole-shuto-passage-status", in: app).value as? String,
      "REALTIME_UNCONFIRMED"
    )
    XCTAssertEqual(
      element("whole-shuto-toll-status", in: app).value as? String,
      "UNAVAILABLE"
    )
    XCTAssertEqual(
      element("whole-shuto-guidance-language", in: app).value as? String,
      "ja-JP"
    )
    XCTAssertTrue(
      app.buttons["whole-shuto-start-simulation"].isEnabled
    )

    let reviewScreenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    reviewScreenshot.name = "Whole Shuto pre-drive journey review"
    reviewScreenshot.lifetime = .keepAlways
    add(reviewScreenshot)
  }

  func testDeniedLocationRequiresAManualOriginBeforeRouteSearch() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-WHOLE-SHUTO-LOCATION-DENIED-PREVIEW",
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
    ]
    app.launch()

    let destinationToggle = element(
      "whole-shuto-destination-toggle",
      in: app
    )
    XCTAssertTrue(destinationToggle.waitForExistence(timeout: 5))
    destinationToggle.tap()
    let origin = app.textFields["whole-shuto-manual-origin"]
    let destination = app.textFields[
      "whole-shuto-destination-search"
    ]
    let planRoute = app.buttons["whole-shuto-plan-route"]
    XCTAssertTrue(origin.waitForExistence(timeout: 5))
    XCTAssertTrue(destination.exists)
    XCTAssertFalse(planRoute.isEnabled)

    destination.tap()
    destination.typeText("东京塔")
    XCTAssertFalse(planRoute.isEnabled)

    origin.tap()
    origin.typeText("东京站")
    XCTAssertTrue(planRoute.isEnabled)

    let manualOriginScreenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    manualOriginScreenshot.name = "Whole Shuto manual origin required"
    manualOriginScreenshot.lifetime = .keepAlways
    add(manualOriginScreenshot)
  }

  func testUnavailableSurfaceLegsKeepJourneyReviewBlocked() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-WHOLE-SHUTO-SURFACE-FAILURE-PREVIEW",
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
    ]
    app.launch()

    let surfaceStatus = element(
      "whole-shuto-surface-route-status",
      in: app
    )
    XCTAssertTrue(surfaceStatus.waitForExistence(timeout: 5))
    let unavailable = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", "UNAVAILABLE"),
      object: surfaceStatus
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [unavailable], timeout: 3),
      .completed
    )
    XCTAssertTrue(
      app.buttons["whole-shuto-retry-surface-route"].exists
    )
    XCTAssertFalse(
      app.buttons["whole-shuto-review-journey"].exists
    )
    XCTAssertFalse(
      app.buttons["whole-shuto-start-simulation"].exists
    )

    let screenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    screenshot.name = "Whole Shuto unavailable surface legs"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  func testWholeShutoArrivalHasOneClearFinishAction() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-WHOLE-SHUTO-ARRIVAL-PREVIEW",
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
    ]
    app.launch()

    let product = element("whole-shuto-product", in: app)
    XCTAssertTrue(product.waitForExistence(timeout: 5))
    XCTAssertEqual(product.value as? String, "COMPLETED")
    XCTAssertTrue(
      element("whole-shuto-arrival-dock", in: app)
        .waitForExistence(timeout: 5)
    )
    XCTAssertTrue(
      element("whole-shuto-arrival-destination", in: app)
        .label.contains("横浜中華街")
    )
    XCTAssertTrue(
      element("whole-shuto-arrival-distance", in: app).exists
    )
    XCTAssertFalse(
      app.buttons["whole-shuto-preview-step"].exists
    )
    XCTAssertFalse(
      app.buttons["whole-shuto-preview-playback"].exists
    )

    let arrivalScreenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    arrivalScreenshot.name = "Whole Shuto completed journey"
    arrivalScreenshot.lifetime = .keepAlways
    add(arrivalScreenshot)

    app.buttons["whole-shuto-finish-journey"].tap()
    XCTAssertTrue(
      element("whole-shuto-planning-dock", in: app)
        .waitForExistence(timeout: 5)
    )
    XCTAssertEqual(product.value as? String, "PLANNING")
    XCTAssertFalse(
      element("whole-shuto-arrival-dock", in: app).exists
    )
  }

  func testWholeShutoActivePreviewRequiresConfirmationToEnd() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-WHOLE-SHUTO-NAVIGATION-PREVIEW",
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
    ]
    app.launch()

    let product = element("whole-shuto-product", in: app)
    let playback = app.buttons["whole-shuto-preview-playback"]
    XCTAssertTrue(product.waitForExistence(timeout: 5))
    XCTAssertTrue(playback.waitForExistence(timeout: 5))
    XCTAssertEqual(playback.value as? String, "PLAYING")

    let phaseBeforeEndRequest = product.value as? String
    app.buttons["whole-shuto-end-journey"].tap()
    let endAlert = app.alerts["结束本次预演？"]
    XCTAssertTrue(endAlert.waitForExistence(timeout: 3))
    XCTAssertEqual(product.value as? String, phaseBeforeEndRequest)
    XCTAssertEqual(playback.value as? String, "PAUSED")

    endAlert.buttons["继续预演"].tap()
    XCTAssertFalse(endAlert.exists)
    XCTAssertEqual(playback.value as? String, "PLAYING")

    app.buttons["whole-shuto-end-journey"].tap()
    XCTAssertTrue(endAlert.waitForExistence(timeout: 3))
    endAlert.buttons["结束预演"].tap()
    XCTAssertTrue(
      element("whole-shuto-planning-dock", in: app)
        .waitForExistence(timeout: 5)
    )
    XCTAssertEqual(product.value as? String, "PLANNING")
  }

  func testWholeShutoRouteAndJunctionPreviewAreMapFirst() {
    continueAfterFailure = false
    let routeApp = XCUIApplication()
    routeApp.launchArguments = [
      "-WHOLE-SHUTO-ROUTE-PREVIEW",
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
    ]
    routeApp.launch()

    let product = element("whole-shuto-product", in: routeApp)
    XCTAssertTrue(product.waitForExistence(timeout: 5))
    XCTAssertEqual(product.value as? String, "REVIEW")
    XCTAssertTrue(element("whole-shuto-geographic-map", in: routeApp).exists)
    XCTAssertTrue(element("whole-shuto-route-selection", in: routeApp).exists)
    XCTAssertTrue(element("whole-shuto-route-option-0", in: routeApp).exists)
    let customizeRoute = element(
      "whole-shuto-customize-route",
      in: routeApp
    )
    XCTAssertTrue(customizeRoute.exists)
    let routeSelectionScreenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    routeSelectionScreenshot.name = "Whole Shuto route selection"
    routeSelectionScreenshot.lifetime = .keepAlways
    add(routeSelectionScreenshot)

    let recommendedRoute = element(
      "whole-shuto-route-option-0",
      in: routeApp
    )
    let alternativeRoute = element(
      "whole-shuto-route-option-1",
      in: routeApp
    )
    let recommendedValue = recommendedRoute.value as? String ?? ""
    let alternativeValue = alternativeRoute.value as? String ?? ""
    for value in [recommendedValue, alternativeValue] {
      XCTAssertTrue(value.contains("入口"))
      XCTAssertTrue(value.contains("出口"))
      XCTAssertTrue(value.contains("首都高"))
    }
    XCTAssertTrue(recommendedRoute.isSelected)
    alternativeRoute.tap()
    XCTAssertTrue(alternativeRoute.isSelected)
    XCTAssertFalse(recommendedRoute.isSelected)
    let routeUpdateCompleted = XCTNSPredicateExpectation(
      predicate: NSPredicate(
        format: "NOT (value CONTAINS %@)",
        "正在确认路线"
      ),
      object: alternativeRoute
    )
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [routeUpdateCompleted],
        timeout: 2
      ),
      .completed
    )

    let alternativeScreenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    alternativeScreenshot.name = "Whole Shuto selected alternative"
    alternativeScreenshot.lifetime = .keepAlways
    add(alternativeScreenshot)

    customizeRoute.tap()
    XCTAssertTrue(
      element("whole-shuto-route-customization", in: routeApp)
        .waitForExistence(timeout: 3)
    )
    let customEntry = routeApp.buttons[
      "whole-shuto-custom-entry-shuto.ic.c1.takaracho"
    ]
    let customExit = routeApp.buttons[
      "whole-shuto-custom-exit-shuto.ic.k1.yokohamakouen"
    ]
    XCTAssertTrue(customEntry.waitForExistence(timeout: 3))
    XCTAssertTrue(customExit.waitForExistence(timeout: 3))
    customEntry.tap()
    customExit.tap()
    let fewerJunctions = routeApp.buttons[
      "whole-shuto-custom-preference-fewer_junctions"
    ]
    XCTAssertTrue(fewerJunctions.exists)
    fewerJunctions.tap()
    XCTAssertEqual(
      element("whole-shuto-custom-route-preview", in: routeApp).value
        as? String,
      "AVAILABLE"
    )

    let customRouteScreenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    customRouteScreenshot.name = "Whole Shuto exact custom route"
    customRouteScreenshot.lifetime = .keepAlways
    add(customRouteScreenshot)

    let applyCustomRoute = routeApp.buttons[
      "whole-shuto-apply-custom-route"
    ]
    XCTAssertTrue(applyCustomRoute.isEnabled)
    applyCustomRoute.tap()
    XCTAssertFalse(
      element("whole-shuto-route-customization", in: routeApp)
        .waitForExistence(timeout: 1)
    )
    XCTAssertTrue(customizeRoute.isSelected)
    let customRouteValue = customizeRoute.value as? String ?? ""
    XCTAssertTrue(customRouteValue.contains("入口"))
    XCTAssertTrue(customRouteValue.contains("出口"))
    XCTAssertTrue(customRouteValue.contains("全程约"))
    XCTAssertTrue(customRouteValue.contains("分钟"))
    let reviewCustomRoute = routeApp.buttons[
      "whole-shuto-review-journey"
    ]
    XCTAssertTrue(reviewCustomRoute.exists)
    let customSurfaceRouteResolved = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "enabled == YES"),
      object: reviewCustomRoute
    )
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [customSurfaceRouteResolved],
        timeout: 2
      ),
      .completed
    )
    reviewCustomRoute.tap()
    XCTAssertTrue(
      element("whole-shuto-journey-review", in: routeApp)
        .waitForExistence(timeout: 3)
    )
    XCTAssertTrue(
      (element("whole-shuto-expressway-leg", in: routeApp).value
        as? String)?.contains("C1") == true
    )
    XCTAssertTrue(
      routeApp.buttons["whole-shuto-start-simulation"].isEnabled
    )

    let appliedCustomScreenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    appliedCustomScreenshot.name = "Whole Shuto selected custom route"
    appliedCustomScreenshot.lifetime = .keepAlways
    add(appliedCustomScreenshot)
    routeApp.terminate()

    let junctionApp = XCUIApplication()
    junctionApp.launchArguments = [
      "-WHOLE-SHUTO-JUNCTION-PREVIEW",
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
    ]
    junctionApp.launch()
    XCTAssertTrue(
      element("whole-shuto-geographic-map", in: junctionApp)
        .waitForExistence(timeout: 5)
    )
    let junctionInset = element(
      "whole-shuto-junction-inset",
      in: junctionApp
    )
    XCTAssertTrue(junctionInset.waitForExistence(timeout: 5))
    XCTAssertTrue(junctionInset.label.contains("大井 JCT"))
    XCTAssertTrue(junctionInset.label.contains("左分岔"))
    XCTAssertTrue(junctionInset.label.contains("東名・中央道"))
    XCTAssertTrue(junctionInset.label.contains("车道编号尚未发布"))
    XCTAssertTrue(
      element("whole-shuto-guidance-instruction", in: junctionApp)
        .label.contains("向左分岔")
    )
    XCTAssertEqual(
      element("whole-shuto-guidance-speech", in: junctionApp).value
        as? String,
      "等待已审核提示"
    )
    junctionApp.terminate()

    let navigationApp = XCUIApplication()
    navigationApp.launchArguments = [
      "-WHOLE-SHUTO-JUNCTION-NAVIGATION-PREVIEW",
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
    ]
    navigationApp.launch()
    XCTAssertTrue(
      element("whole-shuto-geographic-map", in: navigationApp)
        .waitForExistence(timeout: 5)
    )
    XCTAssertTrue(
      element("whole-shuto-journey-remaining", in: navigationApp)
        .waitForExistence(timeout: 5)
    )
    XCTAssertTrue(
      element("whole-shuto-next-junction", in: navigationApp)
        .waitForExistence(timeout: 5)
    )
    XCTAssertTrue(
      element("whole-shuto-guidance-card", in: navigationApp).exists
    )
    XCTAssertFalse(
      element("whole-shuto-guidance-distance", in: navigationApp)
        .label.isEmpty
    )
    XCTAssertFalse(
      element("whole-shuto-guidance-instruction", in: navigationApp)
        .label.isEmpty
    )
    XCTAssertTrue(
      element("whole-shuto-journey-remaining-time", in: navigationApp)
        .exists
    )
    let journeyProgress = element(
      "whole-shuto-journey-progress",
      in: navigationApp
    )
    XCTAssertTrue(journeyProgress.exists)
    XCTAssertTrue(
      (journeyProgress.value as? String)?.hasSuffix("%") == true
    )
    let positionState = element(
      "whole-shuto-position-state",
      in: navigationApp
    )
    XCTAssertTrue(positionState.waitForExistence(timeout: 5))
    XCTAssertTrue(
      positionState.label.contains("模拟 54 km/h · 20×")
    )
    let actorJunctionInset = element(
      "whole-shuto-junction-inset",
      in: navigationApp
    )
    XCTAssertTrue(actorJunctionInset.waitForExistence(timeout: 10))
    XCTAssertTrue(actorJunctionInset.label.contains("大井 JCT"))
    let speech = element(
      "whole-shuto-guidance-speech",
      in: navigationApp
    )
    XCTAssertTrue(speech.exists)
    XCTAssertTrue(
      ["已安排", "播报中", "已播报"].contains(
        speech.value as? String ?? ""
      )
    )
    let navigationScreenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    navigationScreenshot.name = "Whole Shuto route-following simulation"
    navigationScreenshot.lifetime = .keepAlways
    add(navigationScreenshot)

    let followingControl = element(
      "whole-shuto-route-following-control",
      in: navigationApp
    )
    XCTAssertTrue(followingControl.waitForExistence(timeout: 3))
    XCTAssertEqual(followingControl.value as? String, "FOLLOWING")
    followingControl.tap()
    XCTAssertEqual(followingControl.value as? String, "FREE")
    element("whole-shuto-geographic-map", in: navigationApp).swipeLeft()
    followingControl.tap()
    XCTAssertEqual(followingControl.value as? String, "FOLLOWING")
  }

  func testWholeShutoKasaiGuidanceIsActorDriven() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-WHOLE-SHUTO-KASAI-JUNCTION-NAVIGATION-PREVIEW",
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
    ]
    app.launch()

    let junctionInset = element(
      "whole-shuto-junction-inset",
      in: app
    )
    XCTAssertTrue(junctionInset.waitForExistence(timeout: 10))
    XCTAssertTrue(junctionInset.label.contains("葛西 JCT"))
    XCTAssertTrue(junctionInset.label.contains("左分岔"))
    XCTAssertTrue(junctionInset.label.contains("東北道・常磐道"))
    XCTAssertTrue(junctionInset.label.contains("车道编号尚未发布"))
    let speech = element(
      "whole-shuto-guidance-speech",
      in: app
    )
    XCTAssertTrue(speech.exists)
    XCTAssertTrue(
      ["已安排", "播报中", "已播报"].contains(
        speech.value as? String ?? ""
      )
    )

    let screenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    screenshot.name = "Whole Shuto actor-driven Kasai left branch"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  func testWholeShutoTatsumiGuidanceIsActorDriven() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-WHOLE-SHUTO-TATSUMI-EASTBOUND-JUNCTION-NAVIGATION-PREVIEW",
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
    ]
    app.launch()

    let junctionInset = element(
      "whole-shuto-junction-inset",
      in: app
    )
    XCTAssertTrue(junctionInset.waitForExistence(timeout: 10))
    XCTAssertTrue(junctionInset.label.contains("辰巳 JCT"))
    XCTAssertTrue(junctionInset.label.contains("左分岔"))
    XCTAssertTrue(junctionInset.label.contains("箱崎"))
    XCTAssertTrue(junctionInset.label.contains("车道编号尚未发布"))
    let speech = element(
      "whole-shuto-guidance-speech",
      in: app
    )
    XCTAssertTrue(speech.exists)
    XCTAssertTrue(
      ["已安排", "播报中", "已播报"].contains(
        speech.value as? String ?? ""
      )
    )

    let screenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    screenshot.name = "Whole Shuto actor-driven Tatsumi left branch"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  func testWholeShutoShinonomeRightBranchGuidanceIsActorDriven() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-WHOLE-SHUTO-SHINONOME-WESTBOUND-JUNCTION-NAVIGATION-PREVIEW",
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
    ]
    app.launch()

    let junctionInset = element(
      "whole-shuto-junction-inset",
      in: app
    )
    XCTAssertTrue(junctionInset.waitForExistence(timeout: 10))
    XCTAssertTrue(junctionInset.label.contains("东云 JCT"))
    XCTAssertTrue(junctionInset.label.contains("右分岔"))
    XCTAssertTrue(junctionInset.label.contains("晴海"))
    XCTAssertTrue(junctionInset.label.contains("车道编号尚未发布"))
    let speech = element(
      "whole-shuto-guidance-speech",
      in: app
    )
    XCTAssertTrue(speech.exists)
    XCTAssertTrue(
      ["已安排", "播报中", "已播报"].contains(
        speech.value as? String ?? ""
      )
    )

    let screenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    screenshot.name = "Whole Shuto actor-driven Shinonome right branch"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  func testWholeShutoInterfaceAndVoiceLanguagesRemainIndependent() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-RESET-NAVIGATION-CHECKPOINT",
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
    ]
    app.launch()

    let settings = element("whole-shuto-language-settings", in: app)
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    settings.tap()

    let englishInterface = element(
      "whole-shuto-interface-language-en",
      in: app
    )
    XCTAssertTrue(englishInterface.waitForExistence(timeout: 3))
    englishInterface.tap()

    let chineseVoice = element(
      "whole-shuto-guidance-voice-language-zh-Hans",
      in: app
    )
    XCTAssertTrue(chineseVoice.waitForExistence(timeout: 3))
    chineseVoice.tap()

    XCTAssertTrue(englishInterface.isSelected)
    XCTAssertTrue(chineseVoice.isSelected)

    let done = app.buttons["whole-shuto-language-settings-done"]
    done.tap()
    XCTAssertTrue(done.waitForNonExistence(timeout: 3))
    waitForLayoutSettlement()
    XCTAssertTrue(
      app.staticTexts["WHOLE SHUTO"]
        .waitForExistence(timeout: 3)
    )
    assertMapFirstPlanningLayout(in: app)

    let englishScreenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    englishScreenshot.name = "Whole Shuto English interface"
    englishScreenshot.lifetime = .keepAlways
    add(englishScreenshot)

    settings.tap()
    let japaneseInterface = element(
      "whole-shuto-interface-language-ja-JP",
      in: app
    )
    XCTAssertTrue(japaneseInterface.waitForExistence(timeout: 3))
    japaneseInterface.tap()
    XCTAssertTrue(japaneseInterface.isSelected)
    XCTAssertTrue(chineseVoice.isSelected)
    done.tap()
    XCTAssertTrue(done.waitForNonExistence(timeout: 3))
    waitForLayoutSettlement()

    XCTAssertTrue(
      app.staticTexts["首都高全体"]
        .waitForExistence(timeout: 3)
    )
    assertMapFirstPlanningLayout(in: app)
    let japaneseScreenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    japaneseScreenshot.name = "Whole Shuto Japanese interface"
    japaneseScreenshot.lifetime = .keepAlways
    add(japaneseScreenshot)
  }

  func testReleasedK7RouteAutomaticallySimulatesAcrossTheMap() {
    continueAfterFailure = false
    let app = launchProduct()
    let releaseID = "shutoko.product.k7-aoba-to-kohoku.2026-07-27"

    reveal("product-route-option-\(releaseID)", in: app).tap()
    XCTAssertTrue(
      element("product-geographic-map", in: app)
        .waitForExistence(timeout: 5)
    )

    reveal(
      "released-route-choice-shutoko.choice.kohoku.k7-up-to-shared-exit-corridor",
      in: app
    ).tap()
    reveal(
      "released-route-choice-shutoko.choice.kohoku.shared-corridor-to-exit",
      in: app
    ).tap()
    reveal("released-route-compile", in: app).tap()

    let journeyAction = element(
      "product-journey-primary-action",
      in: app
    )
    XCTAssertTrue(journeyAction.isEnabled)
    journeyAction.tap()
    XCTAssertEqual(
      element("product-journey-stage", in: app).value as? String,
      "REVIEW"
    )
    XCTAssertTrue(journeyAction.isEnabled)
    journeyAction.tap()

    XCTAssertTrue(
      element("product-drive-surface", in: app)
        .waitForExistence(timeout: 5)
    )
    XCTAssertEqual(
      element("product-map-drive", in: app).value as? String,
      "geographic"
    )

    let simulation = reveal("product-drive-simulation", in: app)
    let start = reveal("product-drive-start-simulation", in: app)
    XCTAssertTrue(start.isEnabled)
    start.tap()

    let junctionInset = element("product-junction-inset", in: app)
    XCTAssertTrue(
      junctionInset.waitForExistence(timeout: 12),
      "The K7 DecisionZone did not present a junction inset"
    )
    XCTAssertTrue(
      (junctionInset.value as? String)?.contains(
        "shutoko.decision-zone.kohoku.k7-up-shared-branch.v1"
      ) == true
    )
    waitForJunctionInsetAnimation()

    let junctionScreenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    junctionScreenshot.name = "Released K7 transient junction inset"
    junctionScreenshot.lifetime = .keepAlways
    add(junctionScreenshot)

    XCTAssertTrue(
      element("product-geographic-position-marker", in: app)
        .waitForExistence(timeout: 8)
    )
    XCTAssertTrue(
      waitForValuePrefix(
        "COMPLETED",
        on: simulation,
        timeout: 25
      )
    )
    XCTAssertEqual(
      element("product-drive-progress", in: app).value as? String,
      "5 of 5"
    )

    let screenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    screenshot.name = "Released K7 MapKit route simulation"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  func testHomeContinuesRestoredC2JourneyOnlyAfterExplicitResume() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-PRODUCT-JOURNEY-C2-RESTORE-PREVIEW",
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
    ]
    app.launch()

    let route = reveal("product-route-option-c2-complete", in: app)
    XCTAssertEqual(route.value as? String, "RESTORABLE")
    route.tap()

    let navigation = element("c2-full-navigation", in: app)
    XCTAssertTrue(navigation.waitForExistence(timeout: 5))
    XCTAssertEqual(navigation.value as? String, "EXPRESSWAY")
    XCTAssertEqual(
      element("c2-navigation-suspended", in: app).value as? String,
      "APP_INACTIVE"
    )

    app.buttons["c2-navigation-play-pause"].tap()

    XCTAssertFalse(
      element("c2-navigation-suspended", in: app).exists
    )
  }

  func testSettingsKeepInterfaceAndGuidanceVoiceIndependent() {
    continueAfterFailure = false
    let app = launchProduct()

    element("product-journey-settings", in: app).tap()
    XCTAssertTrue(
      element("product-settings", in: app)
        .waitForExistence(timeout: 3)
    )

    let japaneseVoice = element(
      "product-settings-guidance-voice-ja-JP",
      in: app
    )
    XCTAssertTrue(japaneseVoice.isSelected)

    let englishInterface = element(
      "product-journey-interface-language-en",
      in: app
    )
    englishInterface.tap()

    XCTAssertTrue(englishInterface.isSelected)
    XCTAssertTrue(japaneseVoice.isSelected)
  }

  private func launchProduct() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = [
      "-LEGACY-PRODUCT-JOURNEY",
      "-RESET-NAVIGATION-CHECKPOINT",
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
      "-app.kaidoroutes.map-projection.v2",
      "geographic",
    ]
    app.launch()
    return app
  }

  private func element(
    _ identifier: String,
    in app: XCUIApplication
  ) -> XCUIElement {
    app.descendants(matching: .any)[identifier]
  }

  private func reveal(
    _ identifier: String,
    in app: XCUIApplication
  ) -> XCUIElement {
    let target = element(identifier, in: app)
    XCTAssertTrue(
      target.waitForExistence(timeout: 3),
      "\(identifier) did not exist"
    )
    for _ in 0..<12 where !target.isHittable {
      app.swipeUp()
    }
    XCTAssertTrue(target.isHittable, "\(identifier) did not become visible")
    return target
  }

  private func waitForValuePrefix(
    _ prefix: String,
    on element: XCUIElement,
    timeout: TimeInterval
  ) -> Bool {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(
        format: "value BEGINSWITH %@",
        prefix
      ),
      object: element
    )
    return XCTWaiter.wait(
      for: [expectation],
      timeout: timeout
    ) == .completed
  }

  private func waitForJunctionInsetAnimation() {
    let expectation = XCTestExpectation(
      description: "Junction inset animation settled"
    )
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
      expectation.fulfill()
    }
    XCTAssertEqual(
      XCTWaiter.wait(for: [expectation], timeout: 1),
      .completed
    )
  }

  private func waitForLayoutSettlement() {
    let expectation = XCTestExpectation(
      description: "Localized product layout settled"
    )
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      expectation.fulfill()
    }
    XCTAssertEqual(
      XCTWaiter.wait(for: [expectation], timeout: 1),
      .completed
    )
  }

  private func assertMapFirstPlanningLayout(
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let dock = element("whole-shuto-planning-dock", in: app)
    XCTAssertTrue(dock.exists, file: file, line: line)
    XCTAssertGreaterThanOrEqual(
      dock.frame.minY,
      app.frame.midY,
      "The planning dock must leave at least half of the screen for the network map.",
      file: file,
      line: line
    )
  }
}
