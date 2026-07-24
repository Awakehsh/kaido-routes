import Combine
import KaidoDomain
import KaidoPresentation
import KaidoRouting

struct ReleasedProductRouteOptionPresentation: Equatable, Identifiable, Sendable {
  let id: String
  let productReleaseID: String
  let navigationReleaseID: String
  let entranceTitle: String
  let finalChoiceTitle: String
  let decisionCount: Int
  let actualDistanceKM: Double
  let hasGuidanceAudio: Bool
}

enum ReleasedProductRouteAuthoringError: String, Error, Equatable, Sendable {
  case releaseUnavailable = "RELEASED_ROUTE_UNAVAILABLE"
  case routeIdentityMismatch = "RELEASED_ROUTE_IDENTITY_MISMATCH"
  case editorUnavailable = "RELEASED_ROUTE_EDITOR_UNAVAILABLE"
  case choiceRejected = "RELEASED_ROUTE_CHOICE_REJECTED"
  case routeIncomplete = "RELEASED_ROUTE_INCOMPLETE"
  case vehicleClassRequired = "RELEASED_PRE_DRIVE_VEHICLE_CLASS_REQUIRED"
  case paymentMethodRequired = "RELEASED_PRE_DRIVE_PAYMENT_METHOD_REQUIRED"
  case preDriveEvidenceUnavailable =
    "RELEASED_PRE_DRIVE_EVIDENCE_UNAVAILABLE"
  case preDriveEvidenceRejected = "RELEASED_PRE_DRIVE_EVIDENCE_REJECTED"
}

/// Release-owned authoring and pre-drive admission for foreground navigation.
///
/// Every visible label comes from the selected product release. The user still
/// submits each stable recipe choice explicitly, while the adapter retains all
/// release-owned occurrence identities. A compiled route becomes review-ready
/// only after the user explicitly selects a canonical Shuto vehicle class and
/// payment method, and separately supplied session evidence evaluates against
/// that exact product release, RoutePlan, and tariff profile.
@MainActor
final class ReleasedProductRouteAuthoringModel: ObservableObject {
  typealias EvidenceProvider =
    (BundledProductReleaseEntry, PreDriveReviewSession)
    -> PreDriveReviewEvidence?

  @Published private(set) var locale: KaidoReleaseLocale
  @Published private(set) var options: [ReleasedProductRouteOptionPresentation]
  @Published private(set) var selectedReleaseID: String?
  @Published private(set) var snapshot: ExpertRouteEditorSnapshot?
  @Published private(set) var currentStep: ReleasedRouteEditorStepPresentation?
  @Published private(set) var compiledRoutePlan: RoutePlan?
  @Published private(set) var selectedVehicleClass: ShutoVehicleClass?
  @Published private(set) var selectedPaymentMethod: ShutoPaymentMethod?
  @Published private(set) var preDriveReviewSnapshot: PreDriveReviewSnapshot?
  @Published private(set) var lastErrorCode: String?

  private let entriesByReleaseID: [String: BundledProductReleaseEntry]
  private let evidenceProvider: EvidenceProvider
  private var adapter: ReleasedRouteEditorAdapter?
  private var completedStepCount = 0

  init(
    entries: [BundledProductReleaseEntry],
    locale: KaidoReleaseLocale,
    evidenceProvider: @escaping EvidenceProvider = { _, _ in nil }
  ) throws {
    let releaseIDs = entries.map(\.release.releaseID)
    guard !entries.isEmpty,
      Set(releaseIDs).count == releaseIDs.count,
      entries.allSatisfy({
        $0.descriptor.role == .foregroundNavigation
          && $0.release.navigation.bundle.routePlan.actualDistanceKM != nil
      })
    else {
      throw ReleasedProductRouteAuthoringError.releaseUnavailable
    }
    entriesByReleaseID = Dictionary(
      uniqueKeysWithValues: entries.map { ($0.release.releaseID, $0) }
    )
    self.locale = locale
    self.evidenceProvider = evidenceProvider
    options = try Self.makeOptions(entries: entries, locale: locale)
  }

  var hasSelection: Bool {
    selectedReleaseID != nil
  }

  var canCompile: Bool {
    adapter != nil && currentStep == nil && compiledRoutePlan == nil
  }

  var reviewReady: Bool {
    compiledRoutePlan != nil && selectedVehicleClass != nil
      && selectedPaymentMethod != nil
      && preDriveReviewSnapshot != nil
  }

  var availableVehicleClasses: [ShutoVehicleClass] {
    ShutoVehicleClass.allCases
  }

  var availablePaymentMethods: [ShutoPaymentMethod] {
    ShutoPaymentMethod.allCases
  }

  var selectedEntry: BundledProductReleaseEntry? {
    guard let selectedReleaseID else { return nil }
    return entriesByReleaseID[selectedReleaseID]
  }

  func selectRelease(_ releaseID: String) {
    guard let entry = entriesByReleaseID[releaseID] else {
      fail(.releaseUnavailable)
      return
    }
    do {
      let adapter = try ReleasedRouteEditorAdapter(
        productRelease: entry.release,
        locale: locale
      )
      selectedReleaseID = releaseID
      self.adapter = adapter
      completedStepCount = 0
      snapshot = adapter.snapshot
      currentStep = adapter.nextStep
      compiledRoutePlan = nil
      selectedVehicleClass = nil
      selectedPaymentMethod = nil
      preDriveReviewSnapshot = nil
      lastErrorCode = nil
    } catch {
      resetSelection()
      fail(.editorUnavailable)
    }
  }

  func clearSelection() {
    resetSelection()
    lastErrorCode = nil
  }

  func selectReleasedChoice(_ choiceID: String) {
    guard var adapter else {
      fail(.editorUnavailable)
      return
    }
    do {
      try adapter.selectReleasedChoice(choiceID)
      self.adapter = adapter
      completedStepCount += 1
      snapshot = adapter.snapshot
      currentStep = adapter.nextStep
      compiledRoutePlan = nil
      selectedVehicleClass = nil
      selectedPaymentMethod = nil
      preDriveReviewSnapshot = nil
      lastErrorCode = nil
    } catch {
      fail(.choiceRejected)
    }
  }

  func compile() {
    guard
      let entry = selectedEntry,
      let adapter,
      adapter.nextStep == nil
    else {
      fail(.routeIncomplete)
      return
    }
    do {
      let routePlan = try adapter.compileReleasedRoute()
      guard routePlan == entry.release.navigation.bundle.routePlan else {
        fail(.routeIdentityMismatch)
        return
      }
      compiledRoutePlan = routePlan
      selectedVehicleClass = nil
      selectedPaymentMethod = nil
      preDriveReviewSnapshot = nil
      refreshPreDriveReview()
    } catch {
      compiledRoutePlan = nil
      preDriveReviewSnapshot = nil
      fail(.routeIncomplete)
    }
  }

  func selectVehicleClass(_ vehicleClass: ShutoVehicleClass) {
    guard compiledRoutePlan != nil else {
      fail(.routeIncomplete)
      return
    }
    selectedVehicleClass = vehicleClass
    preDriveReviewSnapshot = nil
    refreshPreDriveReview()
  }

  func selectPaymentMethod(_ paymentMethod: ShutoPaymentMethod) {
    guard compiledRoutePlan != nil else {
      fail(.routeIncomplete)
      return
    }
    selectedPaymentMethod = paymentMethod
    preDriveReviewSnapshot = nil
    refreshPreDriveReview()
  }

  func refreshPreDriveReview() {
    guard
      let entry = selectedEntry,
      let routePlan = compiledRoutePlan,
      routePlan == entry.release.navigation.bundle.routePlan
    else {
      preDriveReviewSnapshot = nil
      fail(.routeIdentityMismatch)
      return
    }
    guard let selectedVehicleClass else {
      preDriveReviewSnapshot = nil
      fail(.vehicleClassRequired)
      return
    }
    guard let selectedPaymentMethod else {
      preDriveReviewSnapshot = nil
      fail(.paymentMethodRequired)
      return
    }
    let session = PreDriveReviewSession(
      networkSnapshotID: routePlan.networkSnapshotID,
      routePlanID: routePlan.id,
      vehicleClass: selectedVehicleClass,
      paymentMethod: selectedPaymentMethod
    )
    guard let evidence = evidenceProvider(entry, session) else {
      preDriveReviewSnapshot = nil
      fail(.preDriveEvidenceUnavailable)
      return
    }
    do {
      let adapter = try ReleasedPreDriveReviewAdapter(
        productRelease: entry.release,
        session: session,
        evidence: evidence
      )
      guard
        adapter.productReleaseID == entry.release.releaseID,
        adapter.navigationReleaseID == entry.release.navigation.releaseID,
        adapter.routePlanID == routePlan.id,
        adapter.session == session
      else {
        preDriveReviewSnapshot = nil
        fail(.routeIdentityMismatch)
        return
      }
      preDriveReviewSnapshot = PreDriveReviewSnapshot(
        routePlan: routePlan,
        evaluation: adapter.evaluation
      )
      lastErrorCode = nil
    } catch let error as PreDriveReviewEvaluationError {
      preDriveReviewSnapshot = nil
      lastErrorCode = error.code
    } catch {
      preDriveReviewSnapshot = nil
      fail(.preDriveEvidenceRejected)
    }
  }

  func updateLocale(_ locale: KaidoReleaseLocale) {
    guard locale != self.locale else { return }
    do {
      let entries = entriesByReleaseID.values.sorted {
        $0.release.releaseID < $1.release.releaseID
      }
      let options = try Self.makeOptions(entries: entries, locale: locale)
      var rebuiltAdapter: ReleasedRouteEditorAdapter?
      if let entry = selectedEntry {
        var candidate = try ReleasedRouteEditorAdapter(
          productRelease: entry.release,
          locale: locale
        )
        for step in candidate.steps.prefix(completedStepCount) {
          try candidate.selectReleasedChoice(step.choiceID)
        }
        rebuiltAdapter = candidate
      }
      self.locale = locale
      self.options = options
      if let rebuiltAdapter {
        adapter = rebuiltAdapter
        snapshot = rebuiltAdapter.snapshot
        currentStep = rebuiltAdapter.nextStep
      }
      if compiledRoutePlan == nil {
        lastErrorCode = nil
      } else {
        refreshPreDriveReview()
      }
    } catch {
      fail(.editorUnavailable)
    }
  }

  private func resetSelection() {
    selectedReleaseID = nil
    adapter = nil
    completedStepCount = 0
    snapshot = nil
    currentStep = nil
    compiledRoutePlan = nil
    selectedVehicleClass = nil
    selectedPaymentMethod = nil
    preDriveReviewSnapshot = nil
  }

  private func fail(_ error: ReleasedProductRouteAuthoringError) {
    lastErrorCode = error.rawValue
  }

  private static func makeOptions(
    entries: [BundledProductReleaseEntry],
    locale: KaidoReleaseLocale
  ) throws -> [ReleasedProductRouteOptionPresentation] {
    try entries.map { entry in
      let adapter = try ReleasedRouteEditorAdapter(
        productRelease: entry.release,
        locale: locale
      )
      guard
        let finalChoiceTitle = adapter.steps.last?.choiceTitle,
        let actualDistanceKM =
          entry.release.navigation.bundle.routePlan.actualDistanceKM
      else {
        throw ReleasedProductRouteAuthoringError.editorUnavailable
      }
      return ReleasedProductRouteOptionPresentation(
        id: entry.release.releaseID,
        productReleaseID: entry.release.releaseID,
        navigationReleaseID: entry.release.navigation.releaseID,
        entranceTitle: adapter.entranceTitle,
        finalChoiceTitle: finalChoiceTitle,
        decisionCount: adapter.steps.count,
        actualDistanceKM: actualDistanceKM,
        hasGuidanceAudio: entry.guidanceAudioRelease != nil
      )
    }
    .sorted {
      if $0.entranceTitle != $1.entranceTitle {
        return $0.entranceTitle.localizedStandardCompare($1.entranceTitle)
          == .orderedAscending
      }
      return $0.productReleaseID < $1.productReleaseID
    }
  }
}
