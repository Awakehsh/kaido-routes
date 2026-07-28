import Foundation
import KaidoDomain
import KaidoPresentation
import XCTest

@testable import KaidoRoutesApp

@MainActor
final class ReleasedProductRouteAuthoringModelTests: XCTestCase {
  func testReleaseOwnedChoicesCompileExactRouteAndAdmitExactEvidence()
    throws
  {
    let entry = try makeReleasedProductTestEntry()
    let model = try ReleasedProductRouteAuthoringModel(
      entries: [entry],
      locale: .simplifiedChinese,
      evidenceProvider: { entry, session in
        makeReleasedPreDriveEvidence(
          for: entry,
          vehicleClass: session.vehicleClass,
          paymentMethod: session.paymentMethod
        )
      }
    )

    XCTAssertEqual(model.options.count, 1)
    XCTAssertFalse(model.options[0].entranceTitle.isEmpty)
    XCTAssertFalse(model.options[0].finalChoiceTitle.isEmpty)
    XCTAssertNil(model.compiledRoutePlan)

    authorReleasedRoute(model, entry: entry)

    XCTAssertEqual(
      model.compiledRoutePlan,
      entry.release.navigation.bundle.routePlan
    )
    XCTAssertTrue(model.reviewReady)
    XCTAssertEqual(
      model.preDriveReviewSnapshot?.routePlanID,
      entry.release.navigation.bundle.routePlan.id
    )
    XCTAssertNil(model.lastErrorCode)
  }

  func testMissingPreDriveInformationDoesNotBlockCompiledRelease() throws {
    let entry = try makeReleasedProductTestEntry()
    let model = try ReleasedProductRouteAuthoringModel(
      entries: [entry],
      locale: .japanese
    )

    authorReleasedRoute(model, entry: entry)

    XCTAssertEqual(
      model.compiledRoutePlan,
      entry.release.navigation.bundle.routePlan
    )
    XCTAssertTrue(model.reviewReady)
    XCTAssertNil(model.preDriveReviewSnapshot)
    XCTAssertEqual(
      model.lastErrorCode,
      ReleasedProductRouteAuthoringError.preDriveEvidenceUnavailable.rawValue
    )
  }

  func testBundledPreDriveEvidenceIsTheDefaultFreshnessCheckedProvider()
    throws
  {
    let entry = try makeReleasedProductTestEntry(
      includePreDriveEvidence: true
    )
    var now = try XCTUnwrap(
      ISO8601DateFormatter().date(
        from: "2026-07-25T12:30:00+09:00"
      )
    )
    let model = try ReleasedProductRouteAuthoringModel(
      entries: [entry],
      locale: .english,
      currentDateProvider: { now }
    )

    authorReleasedRoute(model, entry: entry)

    XCTAssertTrue(model.reviewReady)
    XCTAssertEqual(
      model.preDriveReviewSnapshot?.routePlanID,
      entry.release.navigation.bundle.routePlan.id
    )
    XCTAssertNil(model.lastErrorCode)

    now = try XCTUnwrap(
      ISO8601DateFormatter().date(
        from: "2026-07-26T00:00:00+09:00"
      )
    )
    model.refreshPreDriveReview()

    XCTAssertTrue(model.reviewReady)
    XCTAssertNil(model.preDriveReviewSnapshot)
    XCTAssertEqual(
      model.referencePreDriveInformation?.expiresAt,
      "2026-07-26T00:00:00+09:00"
    )
    XCTAssertEqual(
      model.referencePreDriveInformation?.snapshot.presentation
        .estimatedAmountYen,
      1_320
    )
    XCTAssertTrue(model.hasExpiredReferencePreDriveInformation)
    XCTAssertEqual(
      model.lastErrorCode,
      PreDriveEvidenceResolutionError.expired.code
    )
  }

  func testDriftedPreDriveInformationIsNotPresentedAsCurrent() throws {
    let entry = try makeReleasedProductTestEntry()
    let model = try ReleasedProductRouteAuthoringModel(
      entries: [entry],
      locale: .english,
      evidenceProvider: { entry, session in
        makeReleasedPreDriveEvidence(
          for: entry,
          routePlanID: "test.route-plan.drift",
          vehicleClass: session.vehicleClass,
          paymentMethod: session.paymentMethod
        )
      }
    )

    authorReleasedRoute(model, entry: entry)

    XCTAssertTrue(model.reviewReady)
    XCTAssertNil(model.preDriveReviewSnapshot)
    XCTAssertEqual(
      model.lastErrorCode,
      PreDriveReviewEvaluationError.routeIdentityMismatch.code
    )
  }

  func testVehicleClassDriftedInformationIsNotPresentedAsCurrent()
    throws
  {
    let entry = try makeReleasedProductTestEntry()
    let model = try ReleasedProductRouteAuthoringModel(
      entries: [entry],
      locale: .english,
      evidenceProvider: { entry, session in
        makeReleasedPreDriveEvidence(
          for: entry,
          vehicleClass: session.vehicleClass,
          quoteVehicleClass: .lightMotorcycle,
          paymentMethod: session.paymentMethod
        )
      }
    )

    authorReleasedRoute(model, entry: entry)

    XCTAssertTrue(model.reviewReady)
    XCTAssertNil(model.preDriveReviewSnapshot)
    XCTAssertEqual(
      model.lastErrorCode,
      PreDriveReviewEvaluationError.tariffVehicleClassMismatch.code
    )
  }

  func testCompiledRouteRequiresExplicitVehicleClassBeforeEvidenceRequest()
    throws
  {
    let entry = try makeReleasedProductTestEntry()
    var requestCount = 0
    let model = try ReleasedProductRouteAuthoringModel(
      entries: [entry],
      locale: .english,
      evidenceProvider: { _, _ in
        requestCount += 1
        return nil
      }
    )

    authorReleasedRoute(
      model,
      entry: entry,
      vehicleClass: nil,
      paymentMethod: nil
    )

    XCTAssertEqual(
      model.compiledRoutePlan,
      entry.release.navigation.bundle.routePlan
    )
    XCTAssertNil(model.selectedVehicleClass)
    XCTAssertNil(model.selectedPaymentMethod)
    XCTAssertTrue(model.reviewReady)
    XCTAssertEqual(requestCount, 0)
    XCTAssertEqual(
      model.lastErrorCode,
      ReleasedProductRouteAuthoringError.vehicleClassRequired.rawValue
    )
  }

  func testEvidenceProviderReceivesExactSelectedSession() throws {
    let entry = try makeReleasedProductTestEntry()
    var requestedSession: PreDriveReviewSession?
    let model = try ReleasedProductRouteAuthoringModel(
      entries: [entry],
      locale: .english,
      evidenceProvider: { entry, session in
        requestedSession = session
        return makeReleasedPreDriveEvidence(
          for: entry,
          vehicleClass: session.vehicleClass,
          paymentMethod: session.paymentMethod
        )
      }
    )

    authorReleasedRoute(
      model,
      entry: entry,
      vehicleClass: .lightMotorcycle
    )

    let routePlan = entry.release.navigation.bundle.routePlan
    XCTAssertEqual(
      requestedSession,
      PreDriveReviewSession(
        networkSnapshotID: routePlan.networkSnapshotID,
        routePlanID: routePlan.id,
        vehicleClass: .lightMotorcycle,
        paymentMethod: .etc
      )
    )
    XCTAssertEqual(model.selectedVehicleClass, .lightMotorcycle)
    XCTAssertEqual(model.selectedPaymentMethod, .etc)
    XCTAssertEqual(
      model.preDriveReviewSnapshot?.vehicleClass,
      .lightMotorcycle
    )
    XCTAssertEqual(model.preDriveReviewSnapshot?.paymentMethod, .etc)
    XCTAssertTrue(model.reviewReady)
  }

  func testVehicleClassAloneCannotRequestEvidenceWithoutPaymentMethod()
    throws
  {
    let entry = try makeReleasedProductTestEntry()
    var requestCount = 0
    let model = try ReleasedProductRouteAuthoringModel(
      entries: [entry],
      locale: .english,
      evidenceProvider: { _, _ in
        requestCount += 1
        return nil
      }
    )

    authorReleasedRoute(
      model,
      entry: entry,
      vehicleClass: .standard,
      paymentMethod: nil
    )

    XCTAssertEqual(model.selectedVehicleClass, .standard)
    XCTAssertNil(model.selectedPaymentMethod)
    XCTAssertEqual(requestCount, 0)
    XCTAssertEqual(
      model.lastErrorCode,
      ReleasedProductRouteAuthoringError.paymentMethodRequired.rawValue
    )
  }

  func testProviderCannotDriftEvidenceAndQuotesTogetherFromSession() throws {
    let entry = try makeReleasedProductTestEntry()
    let model = try ReleasedProductRouteAuthoringModel(
      entries: [entry],
      locale: .english,
      evidenceProvider: { entry, _ in
        makeReleasedPreDriveEvidence(
          for: entry,
          vehicleClass: .lightMotorcycle
        )
      }
    )

    authorReleasedRoute(model, entry: entry, vehicleClass: .standard)

    XCTAssertTrue(model.reviewReady)
    XCTAssertNil(model.preDriveReviewSnapshot)
    XCTAssertEqual(
      model.lastErrorCode,
      PreDriveReviewEvaluationError.sessionVehicleClassMismatch.code
    )
  }

  func testProviderCannotDriftPaymentAndQuotesTogetherFromSession() throws {
    let entry = try makeReleasedProductTestEntry()
    let model = try ReleasedProductRouteAuthoringModel(
      entries: [entry],
      locale: .english,
      evidenceProvider: { entry, session in
        makeReleasedPreDriveEvidence(
          for: entry,
          vehicleClass: session.vehicleClass,
          paymentMethod: .cash
        )
      }
    )

    authorReleasedRoute(
      model,
      entry: entry,
      vehicleClass: .standard,
      paymentMethod: .etc
    )

    XCTAssertTrue(model.reviewReady)
    XCTAssertNil(model.preDriveReviewSnapshot)
    XCTAssertEqual(
      model.lastErrorCode,
      PreDriveReviewEvaluationError.sessionPaymentMethodMismatch.code
    )
  }

  func testChangingTariffProfileRequeriesAndReplacesReview() throws {
    let entry = try makeReleasedProductTestEntry()
    var requestedSessions: [PreDriveReviewSession] = []
    let model = try ReleasedProductRouteAuthoringModel(
      entries: [entry],
      locale: .english,
      evidenceProvider: { entry, session in
        requestedSessions.append(session)
        return makeReleasedPreDriveEvidence(
          for: entry,
          vehicleClass: session.vehicleClass,
          paymentMethod: session.paymentMethod
        )
      }
    )

    authorReleasedRoute(model, entry: entry, vehicleClass: .standard)
    XCTAssertEqual(model.preDriveReviewSnapshot?.vehicleClass, .standard)
    XCTAssertEqual(model.preDriveReviewSnapshot?.paymentMethod, .etc)

    model.selectVehicleClass(.large)
    model.selectPaymentMethod(.cash)

    XCTAssertEqual(
      requestedSessions.map {
        "\($0.vehicleClass.rawValue):\($0.paymentMethod.rawValue)"
      },
      [
        "STANDARD:ETC",
        "LARGE:ETC",
        "LARGE:CASH",
      ]
    )
    XCTAssertEqual(model.selectedVehicleClass, .large)
    XCTAssertEqual(model.selectedPaymentMethod, .cash)
    XCTAssertEqual(model.preDriveReviewSnapshot?.vehicleClass, .large)
    XCTAssertEqual(model.preDriveReviewSnapshot?.paymentMethod, .cash)
    XCTAssertTrue(model.reviewReady)
    XCTAssertNil(model.lastErrorCode)
  }

  func testWrongReleasedChoiceDoesNotMutateEditor() throws {
    let entry = try makeReleasedProductTestEntry()
    let model = try ReleasedProductRouteAuthoringModel(
      entries: [entry],
      locale: .english
    )
    model.selectRelease(entry.release.releaseID)
    let original = try XCTUnwrap(model.snapshot)

    model.selectReleasedChoice("test.choice.not-in-recipe")

    XCTAssertEqual(model.snapshot, original)
    XCTAssertNil(model.compiledRoutePlan)
    XCTAssertEqual(
      model.lastErrorCode,
      ReleasedProductRouteAuthoringError.choiceRejected.rawValue
    )
  }

  func testLocaleChangeRebuildsPresentationWithoutChangingProgress()
    throws
  {
    let entry = try makeReleasedProductTestEntry()
    let model = try ReleasedProductRouteAuthoringModel(
      entries: [entry],
      locale: .simplifiedChinese
    )
    model.selectRelease(entry.release.releaseID)
    let firstStep = try XCTUnwrap(model.currentStep)
    model.selectReleasedChoice(firstStep.choiceID)
    let occurrenceIDs = try XCTUnwrap(model.snapshot).occurrences.map(\.id)
    let nextChoiceID = try XCTUnwrap(model.currentStep).choiceID

    model.updateLocale(.english)

    XCTAssertEqual(model.locale, .english)
    XCTAssertEqual(model.snapshot?.occurrences.map(\.id), occurrenceIDs)
    XCTAssertEqual(model.currentStep?.choiceID, nextChoiceID)
    XCTAssertFalse(try XCTUnwrap(model.currentStep).choiceTitle.isEmpty)
    XCTAssertNil(model.lastErrorCode)
  }

  func testLocaleChangeReevaluatesCompiledRouteEvidence() throws {
    let entry = try makeReleasedProductTestEntry()
    var evidenceAvailable = true
    let model = try ReleasedProductRouteAuthoringModel(
      entries: [entry],
      locale: .japanese,
      evidenceProvider: { entry, session in
        evidenceAvailable
          ? makeReleasedPreDriveEvidence(
            for: entry,
            vehicleClass: session.vehicleClass,
            paymentMethod: session.paymentMethod
          )
          : nil
      }
    )
    authorReleasedRoute(model, entry: entry)
    XCTAssertTrue(model.reviewReady)

    evidenceAvailable = false
    model.updateLocale(.english)

    XCTAssertEqual(model.locale, .english)
    XCTAssertEqual(
      model.compiledRoutePlan,
      entry.release.navigation.bundle.routePlan
    )
    XCTAssertTrue(model.reviewReady)
    XCTAssertEqual(
      model.lastErrorCode,
      ReleasedProductRouteAuthoringError.preDriveEvidenceUnavailable.rawValue
    )
  }
}
