import XCTest

@MainActor
final class KaidoProductJourneyUITests: XCTestCase {
  func testDefaultLaunchMakesWholeShutoMapTheProduct() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-RESET-NAVIGATION-CHECKPOINT",
      "-RESET-SAVED-ROUTES",
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
    // Diagram-first home: the self-drawn network map is the default canvas
    // and the geographic map stays one toggle away.
    XCTAssertTrue(
      element("whole-shuto-network-map", in: app).exists
    )
    XCTAssertEqual(
      element("whole-shuto-network-map", in: app).label,
      "首都高全网线路图"
    )
    XCTAssertFalse(
      element("whole-shuto-geographic-map", in: app).exists
    )
    element("whole-shuto-map-geographic", in: app).tap()
    XCTAssertTrue(
      element("whole-shuto-geographic-map", in: app)
        .waitForExistence(timeout: 3)
    )
    element("whole-shuto-map-network", in: app).tap()
    XCTAssertTrue(
      element("whole-shuto-network-map", in: app)
        .waitForExistence(timeout: 3)
    )
    let networkMap = element("whole-shuto-network-map", in: app)
    let browseValue = networkMap.value as? String ?? ""
    XCTAssertFalse(
      browseValue.contains("C1"),
      "Browse must keep the network receded until a catalog card is chosen"
    )
    XCTAssertTrue(element("whole-shuto-current-location", in: app).exists)
    XCTAssertTrue(
      element("route-atlas-attribution-strip", in: app).exists
    )
    XCTAssertTrue(
      element("route-atlas-attribution-source", in: app).exists
    )
    XCTAssertTrue(
      element("route-atlas-attribution-licence", in: app).exists
    )
    XCTAssertTrue(element("whole-shuto-settings", in: app).exists)
    XCTAssertFalse(element("whole-shuto-language-settings", in: app).exists)
    XCTAssertFalse(
      element("whole-shuto-network-information", in: app).exists
    )
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
    XCTAssertTrue(
      element(
        "whole-shuto-circuit-option-shuto.circuit.c1-outer",
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

    element(
      "whole-shuto-circuit-option-shuto.circuit.c1-inner",
      in: app
    ).tap()
    let litC1 = XCTNSPredicateExpectation(
      predicate: NSPredicate(
        format: "value CONTAINS %@",
        "C1"
      ),
      object: networkMap
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [litC1], timeout: 3),
      .completed,
      "Selecting C1 Inner must light only that member on the network map"
    )

    let homeScreenshot = XCTAttachment(
      screenshot: XCUIScreen.main.screenshot()
    )
    homeScreenshot.name = "Whole Shuto route-first home"
    homeScreenshot.lifetime = .keepAlways
    add(homeScreenshot)
  }

  func testWholeShutoInformationExposesPrivacyPolicyAndBuildVersion() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-app.kaidoroutes.language.interface",
      "en",
    ]
    app.launch()
    returnWholeShutoToPlanning(in: app)

    let settings = element("whole-shuto-settings", in: app)
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    settings.tap()
    XCTAssertTrue(
      element("whole-shuto-settings-form", in: app)
        .waitForExistence(timeout: 3)
    )

    _ = revealInformationRow("whole-shuto-location-privacy", in: app)
    _ = revealInformationRow("whole-shuto-privacy-policy", in: app)
    let sourceLicense = revealInformationRow(
      "whole-shuto-source-license",
      in: app
    )
    sourceLicense.tap()
    let licenseDocument = element(
      "whole-shuto-source-license-document",
      in: app
    )
    XCTAssertTrue(licenseDocument.waitForExistence(timeout: 3))
    XCTAssertTrue(licenseDocument.label.contains("Apache License"))
    let back = app.navigationBars.buttons.firstMatch
    XCTAssertTrue(back.waitForExistence(timeout: 2))
    back.tap()
    let mapDataLicense = revealInformationRow(
      "whole-shuto-map-data-license",
      in: app
    )
    mapDataLicense.tap()
    let mapDataLicenseDocument = element(
      "whole-shuto-map-data-license-document",
      in: app
    )
    XCTAssertTrue(mapDataLicenseDocument.waitForExistence(timeout: 3))
    XCTAssertTrue(
      mapDataLicenseDocument.label.contains("Open Database License")
    )
    XCTAssertTrue(
      mapDataLicenseDocument.label.contains("OpenStreetMap contributors")
    )
    XCTAssertTrue(back.waitForExistence(timeout: 2))
    back.tap()
    let version = revealInformationRow("whole-shuto-app-version", in: app)
    let versionValue = try? XCTUnwrap(version.value as? String)
    XCTAssertNotNil(
      versionValue?.range(
        of: #"^[0-9]+\.[0-9]+\.[0-9]+ \([1-9][0-9]*\)$"#,
        options: .regularExpression
      )
    )
  }

  func testCorruptWholeShutoCheckpointStaysParkedAndClearsResumeData() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-RESET-NAVIGATION-CHECKPOINT",
      "-WHOLE-SHUTO-CORRUPT-CHECKPOINT",
      "-app.kaidoroutes.language.interface",
      "en",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
    ]
    app.launch()

    let product = element("whole-shuto-product", in: app)
    XCTAssertTrue(product.waitForExistence(timeout: 5))
    XCTAssertEqual(product.value as? String, "PLANNING")
    let issue = element("whole-shuto-checkpoint-issue", in: app)
    XCTAssertTrue(issue.waitForExistence(timeout: 5))
    XCTAssertEqual(
      issue.value as? String,
      "WHOLE_SHUTO_CHECKPOINT_LOAD_FAILED"
    )
    XCTAssertTrue(
      issue.label.contains("The previous route could not be read")
    )
    app.terminate()

    let nextLaunch = XCUIApplication()
    nextLaunch.launchArguments = [
      "-app.kaidoroutes.language.interface",
      "en",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
    ]
    nextLaunch.launch()
    XCTAssertTrue(
      element("whole-shuto-planning-dock", in: nextLaunch)
        .waitForExistence(timeout: 5)
    )
    XCTAssertFalse(
      element("whole-shuto-checkpoint-issue", in: nextLaunch).exists
    )
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
      element("whole-shuto-track-map", in: app).label
        .hasSuffix("个设施的全路线轨迹图")
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

  func testCustomRouteEntryLivesAtTheCatalogFoot() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-RESET-NAVIGATION-CHECKPOINT",
      "-WHOLE-SHUTO-CUSTOM-ROUTE-PREVIEW",
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
    ]
    app.launch()

    let customEntry = element("whole-shuto-custom-from-home", in: app)
    XCTAssertTrue(customEntry.waitForExistence(timeout: 8))
    customEntry.tap()
    XCTAssertTrue(
      element("whole-shuto-custom-route-preview", in: app)
        .waitForExistence(timeout: 8)
    )
    let apply = element("whole-shuto-apply-custom-route", in: app)
    XCTAssertTrue(apply.waitForExistence(timeout: 8))
    // The apply action stays disabled until the current-location origin
    // resolves for the round trip.
    let enabled = NSPredicate(format: "isEnabled == true")
    let enabledExpectation = XCTNSPredicateExpectation(
      predicate: enabled, object: apply
    )
    XCTAssertEqual(
      XCTWaiter().wait(for: [enabledExpectation], timeout: 20),
      .completed
    )
    apply.tap()
    // Applying from the home catalog opens review as a round trip.
    let product = element("whole-shuto-product", in: app)
    XCTAssertTrue(product.waitForExistence(timeout: 8))
    XCTAssertEqual(product.value as? String, "REVIEW")
    XCTAssertTrue(
      element("whole-shuto-route-selection", in: app)
        .waitForExistence(timeout: 8)
    )
  }

  func testExactCustomRouteWithReviewedGuidanceStartsLiveNavigation() {
    assertExactCustomRouteStartsLiveNavigation(
      previewArgument: "-WHOLE-SHUTO-DYNAMIC-CUSTOM-ROUTE-PREVIEW"
    )
  }

  func testShibuyaToGinzaCustomRouteStartsLiveNavigation() {
    assertExactCustomRouteStartsLiveNavigation(
      previewArgument:
        "-WHOLE-SHUTO-SHIBUYA-GINZA-LIVE-ROUTE-PREVIEW"
    )
  }

  func testRoute2ToGinzaCustomRouteStartsLiveNavigation() {
    assertExactCustomRouteStartsLiveNavigation(
      previewArgument:
        "-WHOLE-SHUTO-ROUTE-2-LIVE-ROUTE-PREVIEW"
    )
  }

  func testMeguroToGinzaCustomRouteStartsLiveNavigation() {
    assertExactCustomRouteStartsLiveNavigation(
      previewArgument:
        "-WHOLE-SHUTO-MEGURO-LIVE-ROUTE-PREVIEW"
    )
  }

  func testShibaParkToShinjukuCustomRouteStartsLiveNavigation() {
    assertExactCustomRouteStartsLiveNavigation(
      previewArgument:
        "-WHOLE-SHUTO-C1-ROUTE-4-LIVE-ROUTE-PREVIEW"
    )
  }

  private func assertExactCustomRouteStartsLiveNavigation(
    previewArgument: String
  ) {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-RESET-NAVIGATION-CHECKPOINT",
      previewArgument,
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
    ]
    app.launch()

    let product = element("whole-shuto-product", in: app)
    XCTAssertTrue(product.waitForExistence(timeout: 8))
    XCTAssertEqual(product.value as? String, "REVIEW")
    let reviewJourney = app.buttons["whole-shuto-review-journey"]
    XCTAssertTrue(reviewJourney.waitForExistence(timeout: 8))
    let reviewReady = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "isEnabled == true"),
      object: reviewJourney
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [reviewReady], timeout: 8),
      .completed
    )
    reviewJourney.tap()

    let startLiveDrive = app.buttons["whole-shuto-start-live-drive"]
    XCTAssertTrue(startLiveDrive.waitForExistence(timeout: 8))
    let liveReady = XCTNSPredicateExpectation(
      predicate: NSPredicate(
        format: "isEnabled == true AND value == %@",
        "AVAILABLE"
      ),
      object: startLiveDrive
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [liveReady], timeout: 12),
      .completed
    )
    XCTAssertFalse(
      element("whole-shuto-live-drive-blocker", in: app).exists
    )
    startLiveDrive.tap()
    let liveEntry = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", "SURFACE_ACCESS"),
      object: product
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [liveEntry], timeout: 8),
      .completed
    )
    XCTAssertTrue(
      element("whole-shuto-position-state", in: app)
        .waitForExistence(timeout: 5)
    )
    let livePosition = element("whole-shuto-current-position", in: app)
    XCTAssertTrue(livePosition.waitForExistence(timeout: 5))
    XCTAssertEqual(livePosition.label, "当前位置")
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
    XCTAssertTrue(
      [
        "ACTIVE_MINIMUM_BAND · 2026-08-03",
        "ACTIVE_ESTIMATED · 2026-08-03",
        "ACTIVE_MAXIMUM · 2026-08-03",
      ].contains(
        element("whole-shuto-toll-status", in: app).value as? String
          ?? ""
      )
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

  func testWholeShutoSavedRoutePersistsAndReopensInCurrentSnapshot() {
    continueAfterFailure = false
    let savedRouteName = "Tokyo Yokohama Snapshot"

    let authoringApp = XCUIApplication()
    authoringApp.launchArguments = [
      "-RESET-NAVIGATION-CHECKPOINT",
      "-RESET-SAVED-ROUTES",
      "-WHOLE-SHUTO-ROUTE-PREVIEW",
      "-app.kaidoroutes.language.interface",
      "en",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
    ]
    authoringApp.launch()

    let product = element("whole-shuto-product", in: authoringApp)
    XCTAssertTrue(product.waitForExistence(timeout: 5))
    XCTAssertEqual(product.value as? String, "REVIEW")
    let selectedRoute = element(
      "whole-shuto-route-option-0",
      in: authoringApp
    )
    XCTAssertTrue(selectedRoute.waitForExistence(timeout: 5))
    XCTAssertTrue(selectedRoute.isSelected)
    let selectedRouteValue = selectedRoute.value as? String ?? ""
    XCTAssertTrue(selectedRouteValue.contains("銀座 entry"))
    XCTAssertTrue(selectedRouteValue.contains("横浜公園 exit"))

    let reviewJourney = authoringApp.buttons[
      "whole-shuto-review-journey"
    ]
    XCTAssertTrue(reviewJourney.waitForExistence(timeout: 5))
    let reviewReady = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "isEnabled == true"),
      object: reviewJourney
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [reviewReady], timeout: 5),
      .completed
    )
    reviewJourney.tap()
    XCTAssertTrue(
      element("whole-shuto-journey-review", in: authoringApp)
        .waitForExistence(timeout: 5)
    )

    let nameField = reveal("saved-route-name", in: authoringApp)
    nameField.tap()
    nameField.typeText(savedRouteName)
    let keyboardReturn = authoringApp.keyboards.buttons["return"]
    XCTAssertTrue(keyboardReturn.waitForExistence(timeout: 2))
    keyboardReturn.tap()
    reveal("saved-route-save", in: authoringApp).tap()
    XCTAssertTrue(
      element("saved-route-save-success", in: authoringApp)
        .waitForExistence(timeout: 5)
    )
    authoringApp.terminate()

    let reopeningApp = XCUIApplication()
    reopeningApp.launchArguments = [
      "-RESET-NAVIGATION-CHECKPOINT",
      "-WHOLE-SHUTO-CUSTOM-ROUTE-PREVIEW",
      "-app.kaidoroutes.language.interface",
      "en",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
    ]
    reopeningApp.launch()

    let savedRoutes = element(
      "whole-shuto-saved-routes",
      in: reopeningApp
    )
    XCTAssertTrue(savedRoutes.waitForExistence(timeout: 5))
    XCTAssertEqual(savedRoutes.value as? String, "1")
    savedRoutes.tap()
    let savedRouteSheet = element(
      "whole-shuto-saved-route-sheet",
      in: reopeningApp
    )
    XCTAssertTrue(savedRouteSheet.waitForExistence(timeout: 5))
    XCTAssertTrue(
      reopeningApp.staticTexts[savedRouteName]
        .waitForExistence(timeout: 5)
    )
    XCTAssertTrue(
      reopeningApp.staticTexts["CURRENT SNAPSHOT"]
        .waitForExistence(timeout: 5)
    )

    let openSavedRoute = reopeningApp.buttons.matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@",
        "saved-route-open-"
      )
    ).firstMatch
    XCTAssertTrue(openSavedRoute.waitForExistence(timeout: 5))
    XCTAssertEqual(openSavedRoute.value as? String, "CURRENT SNAPSHOT")
    openSavedRoute.tap()
    XCTAssertTrue(savedRouteSheet.waitForNonExistence(timeout: 5))

    let reopenedProduct = element(
      "whole-shuto-product",
      in: reopeningApp
    )
    let reopenedReview = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", "REVIEW"),
      object: reopenedProduct
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [reopenedReview], timeout: 5),
      .completed
    )
    XCTAssertTrue(
      element("whole-shuto-route-selection", in: reopeningApp)
        .waitForExistence(timeout: 5)
    )
    let reopenedRoute = element(
      "whole-shuto-route-option-0",
      in: reopeningApp
    )
    XCTAssertTrue(reopenedRoute.waitForExistence(timeout: 5))
    XCTAssertTrue(reopenedRoute.isSelected)
    XCTAssertFalse(
      element("whole-shuto-customize-route", in: reopeningApp).isSelected
    )
    let reopenedRouteValue = reopenedRoute.value as? String ?? ""
    XCTAssertTrue(reopenedRouteValue.contains("銀座 entry"))
    XCTAssertTrue(reopenedRouteValue.contains("横浜公園 exit"))
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

    app.buttons["whole-shuto-end-journey"].tap()
    let endAlert = app.alerts["结束本次预演？"]
    XCTAssertTrue(endAlert.waitForExistence(timeout: 3))
    XCTAssertEqual(playback.value as? String, "PAUSED")
    let pausedPhase = product.value as? String
    XCTAssertNotNil(pausedPhase)
    let phaseChanged = XCTNSPredicateExpectation(
      predicate: NSPredicate { object, _ in
        (object as? XCUIElement)?.value as? String != pausedPhase
      },
      object: product
    )
    phaseChanged.isInverted = true
    wait(for: [phaseChanged], timeout: 1)

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
    // Review opens on the self-drawn presentation (track map when the
    // layout resolves, network diagram otherwise).
    XCTAssertTrue(
      element("whole-shuto-track-map", in: routeApp).exists
        || element("whole-shuto-network-map", in: routeApp).exists
    )
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
    // Expressway navigation now opens on the track map; once it appears,
    // switch to the geographic presentation to exercise its follow/free
    // camera.
    XCTAssertTrue(
      element("whole-shuto-track-map", in: navigationApp)
        .waitForExistence(timeout: 15)
    )
    element("whole-shuto-map-geographic", in: navigationApp).tap()
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

  func testWholeShutoForegroundLocationStartsAndStopsThroughCoreLocation() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.resetAuthorizationStatus(for: .location)
    app.launchArguments = [
      "-RESET-NAVIGATION-CHECKPOINT",
      "-WHOLE-SHUTO-PLANNING-LOCATION-QUALIFICATION",
      "-app.kaidoroutes.language.interface",
      "en",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
    ]
    app.launch()

    let locationState = element(
      "whole-shuto-planning-location-state",
      in: app
    )
    XCTAssertTrue(locationState.waitForExistence(timeout: 5))
    let currentLocation = element("whole-shuto-current-location", in: app)
    XCTAssertTrue(currentLocation.waitForExistence(timeout: 5))
    currentLocation.tap()
    allowLocationWhenInUseIfRequested()
    let measured = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", "MEASURED"),
      object: locationState
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [measured], timeout: 8),
      .completed
    )

    let circuit = element(
      "whole-shuto-circuit-option-shuto.circuit.c1-inner",
      in: app
    )
    XCTAssertTrue(circuit.waitForExistence(timeout: 5))
    circuit.tap()
    let startCircuit = element("whole-shuto-start-circuit", in: app)
    XCTAssertTrue(startCircuit.waitForExistence(timeout: 5))
    let circuitReady = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "isEnabled == true"),
      object: startCircuit
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [circuitReady], timeout: 15),
      .completed
    )
    startCircuit.tap()

    let product = element("whole-shuto-product", in: app)
    let review = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", "REVIEW"),
      object: product
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [review], timeout: 5),
      .completed
    )
    let reviewJourney = app.buttons["whole-shuto-review-journey"]
    XCTAssertTrue(reviewJourney.waitForExistence(timeout: 5))
    let reviewReady = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "isEnabled == true"),
      object: reviewJourney
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [reviewReady], timeout: 5),
      .completed
    )
    reviewJourney.tap()

    let startLiveDrive = app.buttons["whole-shuto-start-live-drive"]
    XCTAssertTrue(startLiveDrive.waitForExistence(timeout: 3))
    XCTAssertTrue(startLiveDrive.isEnabled)
    XCTAssertEqual(
      startLiveDrive.value as? String,
      "AVAILABLE"
    )
    XCTAssertFalse(
      element("whole-shuto-live-drive-blocker", in: app).exists
    )
    startLiveDrive.tap()
    let liveEntry = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", "SURFACE_ACCESS"),
      object: product
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [liveEntry], timeout: 5),
      .completed
    )
    XCTAssertTrue(
      element("whole-shuto-position-state", in: app)
        .waitForExistence(timeout: 5)
    )
    let stopped = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", "STOPPED"),
      object: locationState
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [stopped], timeout: 5),
      .completed
    )

    let liveLocationState = element(
      "whole-shuto-position-state",
      in: app
    )
    let liveLocationStarted = XCTNSPredicateExpectation(
      predicate: NSPredicate(
        format: "value != %@ AND value != %@ AND value != %@",
        "INACTIVE",
        "RESUME_REQUIRED",
        "FAILED"
      ),
      object: liveLocationState
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [liveLocationStarted], timeout: 5),
      .completed
    )

    XCUIDevice.shared.press(.home)
    let backgrounded = XCTNSPredicateExpectation(
      predicate: NSPredicate { object, _ in
        (object as? XCUIApplication)?.state != .runningForeground
      },
      object: app
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [backgrounded], timeout: 5),
      .completed
    )
    app.activate()
    let foregrounded = XCTNSPredicateExpectation(
      predicate: NSPredicate { object, _ in
        (object as? XCUIApplication)?.state == .runningForeground
      },
      object: app
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [foregrounded], timeout: 5),
      .completed
    )
    XCTAssertEqual(product.value as? String, "SURFACE_ACCESS")
    XCTAssertNotEqual(liveLocationState.value as? String, "RESUME_REQUIRED")
    XCTAssertNotEqual(liveLocationState.value as? String, "FAILED")
  }

  func testWholeShutoC2RecommendedRouteExposesLiveNavigation() {
    assertWholeShutoRecommendedRouteExposesLiveNavigation(
      circuitID: "shuto.circuit.c2-inner-bayshore"
    )
  }

  func testWholeShutoLongSurfaceAccessExposesLiveNavigation() {
    assertWholeShutoRecommendedRouteExposesLiveNavigation(
      circuitID: "shuto.circuit.c1-outer",
      previewArgument: "-WHOLE-SHUTO-LONG-ACCESS-LIVE-ROUTE-PREVIEW",
      expectedAccessIdentifier: "whole-shuto-circuit-entrance-extended"
    )
  }

  func testWholeShutoC1OuterRecommendedRouteExposesLiveNavigation() {
    assertWholeShutoRecommendedRouteExposesLiveNavigation(
      circuitID: "shuto.circuit.c1-outer"
    )
  }

  func testWholeShutoDaikokuRecommendedRouteExposesLiveNavigation() {
    assertWholeShutoRecommendedRouteExposesLiveNavigation(
      circuitID: "shuto.circuit.daikoku-yokohama-loop"
    )
  }

  func testWholeShutoScenicRecommendedRouteExposesLiveNavigation() {
    assertWholeShutoRecommendedRouteExposesLiveNavigation(
      circuitID: "shuto.circuit.scenic-grand-tour"
    )
  }

  private func assertWholeShutoRecommendedRouteExposesLiveNavigation(
    circuitID: String,
    previewArgument: String =
      "-WHOLE-SHUTO-RECOMMENDED-LIVE-ROUTE-PREVIEW",
    expectedAccessIdentifier: String? = nil
  ) {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-RESET-NAVIGATION-CHECKPOINT",
      previewArgument,
      "-app.kaidoroutes.language.interface",
      "en",
    ]
    app.launch()

    let circuit = element(
      "whole-shuto-circuit-option-\(circuitID)",
      in: app
    )
    XCTAssertTrue(circuit.waitForExistence(timeout: 5))
    circuit.tap()
    let startCircuit = element("whole-shuto-start-circuit", in: app)
    XCTAssertTrue(startCircuit.waitForExistence(timeout: 5))
    let circuitReady = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "isEnabled == true"),
      object: startCircuit
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [circuitReady], timeout: 15),
      .completed
    )
    if let expectedAccessIdentifier {
      XCTAssertTrue(
        element(expectedAccessIdentifier, in: app)
          .waitForExistence(timeout: 3)
      )
    }
    startCircuit.tap()

    let product = element("whole-shuto-product", in: app)
    let review = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", "REVIEW"),
      object: product
    )
    XCTAssertEqual(XCTWaiter.wait(for: [review], timeout: 8), .completed)
    let reviewJourney = app.buttons["whole-shuto-review-journey"]
    XCTAssertTrue(reviewJourney.waitForExistence(timeout: 5))
    let reviewReady = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "isEnabled == true"),
      object: reviewJourney
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [reviewReady], timeout: 8),
      .completed
    )
    reviewJourney.tap()

    let startLiveDrive = app.buttons["whole-shuto-start-live-drive"]
    XCTAssertTrue(startLiveDrive.waitForExistence(timeout: 5))
    let liveReady = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "isEnabled == true"),
      object: startLiveDrive
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [liveReady], timeout: 15),
      .completed
    )
    XCTAssertEqual(startLiveDrive.value as? String, "AVAILABLE")
    XCTAssertFalse(
      element("whole-shuto-live-drive-blocker", in: app).exists
    )
  }

  func testWholeShutoInterfaceAndVoiceLanguagesRemainIndependent() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-RESET-NAVIGATION-CHECKPOINT",
      "-RESET-SAVED-ROUTES",
      "-app.kaidoroutes.language.interface",
      "zh-Hans",
      "-app.kaidoroutes.language.guidance-voice",
      "ja-JP",
    ]
    app.launch()

    XCTAssertTrue(
      app.staticTexts["都心环状线 内环"]
        .waitForExistence(timeout: 5)
    )

    let settings = element("whole-shuto-settings", in: app)
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    settings.tap()
    XCTAssertTrue(
      element("whole-shuto-settings-form", in: app)
        .waitForExistence(timeout: 3)
    )

    element("whole-shuto-interface-language", in: app).tap()
    let englishInterface = element(
      "whole-shuto-interface-language-en",
      in: app
    )
    XCTAssertTrue(englishInterface.waitForExistence(timeout: 3))
    englishInterface.tap()

    let voiceLanguage = element(
      "whole-shuto-guidance-voice-language",
      in: app
    )
    XCTAssertTrue(voiceLanguage.waitForExistence(timeout: 3))
    voiceLanguage.tap()
    let chineseVoice = element(
      "whole-shuto-guidance-voice-language-zh-Hans",
      in: app
    )
    XCTAssertTrue(chineseVoice.waitForExistence(timeout: 3))
    chineseVoice.tap()

    let done = app.buttons["whole-shuto-settings-done"]
    XCTAssertTrue(done.waitForExistence(timeout: 3))
    done.tap()
    XCTAssertTrue(done.waitForNonExistence(timeout: 3))
    waitForLayoutSettlement()
    XCTAssertTrue(
      app.staticTexts["WHOLE SHUTO"]
        .waitForExistence(timeout: 3)
    )
    XCTAssertTrue(
      app.staticTexts["C1 Inner Circuit"]
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
    XCTAssertTrue(
      element("whole-shuto-settings-form", in: app)
        .waitForExistence(timeout: 3)
    )
    element("whole-shuto-interface-language", in: app).tap()
    let japaneseInterface = element(
      "whole-shuto-interface-language-ja-JP",
      in: app
    )
    XCTAssertTrue(japaneseInterface.waitForExistence(timeout: 3))
    japaneseInterface.tap()
    XCTAssertTrue(voiceLanguage.waitForExistence(timeout: 3))
    voiceLanguage.tap()
    XCTAssertTrue(chineseVoice.waitForExistence(timeout: 3))
    XCTAssertTrue(chineseVoice.isSelected)
    chineseVoice.tap()
    XCTAssertTrue(done.waitForExistence(timeout: 3))
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

    let firstReleasedChoice = reveal(
      "released-route-choice-shutoko.choice.kohoku.k7-up-to-shared-exit-corridor",
      in: app
    )
    firstReleasedChoice.tap()
    let secondChoiceIdentifier =
      "released-route-choice-shutoko.choice.kohoku.shared-corridor-to-exit"
    XCTAssertTrue(
      element(secondChoiceIdentifier, in: app)
        .waitForExistence(timeout: 3),
      "The released editor did not advance after the first choice"
    )
    let secondReleasedChoice = reveal(
      secondChoiceIdentifier,
      in: app
    )
    secondReleasedChoice.tap()
    XCTAssertTrue(
      element("released-route-compile", in: app)
        .waitForExistence(timeout: 3),
      "The released editor did not complete after the second choice"
    )
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
    for _ in 0..<12 {
      let center = CGPoint(
        x: target.frame.midX,
        y: target.frame.midY
      )
      let requiresOnScreenCenter = target.elementType == .button
      if target.isHittable,
        !requiresOnScreenCenter || app.frame.contains(center)
      {
        break
      }
      let driveSurface = element("product-drive-surface", in: app)
      let parkedScroll = app.scrollViews["product-journey-scroll"]
      if driveSurface.exists {
        let progress = element("product-drive-progress", in: app)
        if progress.exists {
          progress.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
          ).press(
            forDuration: 0.05,
            thenDragTo: app.coordinate(
              withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)
            )
          )
        } else {
          app.swipeUp()
        }
      } else if parkedScroll.exists {
        parkedScroll.swipeUp()
      } else {
        app.swipeUp()
      }
    }
    XCTAssertTrue(target.isHittable, "\(identifier) did not become visible")
    if target.elementType == .button {
      let center = CGPoint(
        x: target.frame.midX,
        y: target.frame.midY
      )
      XCTAssertTrue(
        app.frame.contains(center),
        "\(identifier) did not expose an on-screen tap target"
      )
    }
    return target
  }

  private func revealInformationRow(
    _ identifier: String,
    in app: XCUIApplication
  ) -> XCUIElement {
    let target = element(identifier, in: app)
    for _ in 0..<8 where !target.exists || !target.isHittable {
      app.swipeUp()
    }
    XCTAssertTrue(target.exists, "\(identifier) did not exist")
    XCTAssertTrue(target.isHittable, "\(identifier) did not become visible")
    return target
  }

  private func returnWholeShutoToPlanning(in app: XCUIApplication) {
    let product = element("whole-shuto-product", in: app)
    XCTAssertTrue(product.waitForExistence(timeout: 5))
    switch product.value as? String {
    case "PLANNING":
      return
    case "REVIEW":
      reveal("whole-shuto-back-to-planning", in: app).tap()
    case "COMPLETED":
      reveal("whole-shuto-finish-journey", in: app).tap()
    case "SURFACE_ACCESS", "ENTRY_TRANSITION", "EXPRESSWAY",
      "EXIT_TRANSITION", "SURFACE_EGRESS":
      reveal("whole-shuto-end-journey", in: app).tap()
      let alert = app.alerts.firstMatch
      XCTAssertTrue(alert.waitForExistence(timeout: 3))
      let endPreview = alert.buttons["End preview"]
      XCTAssertTrue(endPreview.waitForExistence(timeout: 2))
      endPreview.tap()
    default:
      XCTFail("Whole-Shuto Release smoke started in an unknown phase")
      return
    }
    let planning = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", "PLANNING"),
      object: product
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [planning], timeout: 5),
      .completed,
      "Whole-Shuto Release smoke could not return to planning"
    )
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

  private func allowLocationWhenInUseIfRequested() {
    let springboard = XCUIApplication(
      bundleIdentifier: "com.apple.springboard"
    )
    let alert = springboard.alerts.firstMatch
    guard alert.waitForExistence(timeout: 3) else { return }
    let whenInUse = alert.buttons.matching(
      NSPredicate(
        format:
          "label CONTAINS[c] 'While Using' "
          + "OR label CONTAINS '使用中' "
          + "OR label CONTAINS '使用 App 时' "
          + "OR label CONTAINS '使用App时' "
          + "OR label CONTAINS '使用 App 期間'"
      )
    ).firstMatch
    XCTAssertTrue(
      whenInUse.waitForExistence(timeout: 2),
      "The system location prompt did not expose a When In Use action"
    )
    whenInUse.tap()
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
