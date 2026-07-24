import Foundation
import KaidoDomain
import KaidoPresentation

@testable import KaidoRoutesApp

enum ReleasedProductTestSupportError: Error {
  case missingResource
  case invalidFixture
}

func makeReleasedProductTestEntry(
  releaseID: String = "test.released-road.product"
) throws -> BundledProductReleaseEntry {
  guard
    let url = Bundle.main.url(
      forResource: SyntheticProductRuntimeFixture.resourceName,
      withExtension: "json"
    )
  else {
    throw ReleasedProductTestSupportError.missingResource
  }
  guard
    var root = try JSONSerialization.jsonObject(
      with: Data(contentsOf: url)
    ) as? [String: Any]
  else {
    throw ReleasedProductTestSupportError.invalidFixture
  }
  root["release_id"] = releaseID
  root["runtime_use"] = [
    "evidence_scope": "RELEASED_ROAD",
    "live_input_policy": "FOREGROUND_WHEN_IN_USE",
  ]
  for releaseKey in ["navigation_release", "route_atlas_release"] {
    guard
      var nestedRelease = root[releaseKey] as? [String: Any],
      var registry = nestedRelease["source_registry"] as? [String: Any],
      var references = registry["references"] as? [[String: Any]]
    else {
      throw ReleasedProductTestSupportError.invalidFixture
    }
    for index in references.indices {
      references[index]["licence_identifier"] =
        "TEST_REVIEWED_ROAD_ONLY"
    }
    registry["references"] = references
    nestedRelease["source_registry"] = registry
    root[releaseKey] = nestedRelease
  }
  let data = try JSONSerialization.data(withJSONObject: root)
  let descriptor = BundledProductReleaseDescriptor(
    resourceName: "released-road-product",
    resourceExtension: "json",
    expectedSHA256:
      BundledProductReleaseCatalogLoader.sha256Hex(data),
    expectedReleaseID: releaseID,
    role: .foregroundNavigation
  )
  let catalog = try BundledProductReleaseCatalogLoader.load(
    descriptors: [descriptor]
  ) { _ in
    data
  }
  guard let entry = catalog.foregroundNavigationEntries.first else {
    throw ReleasedProductTestSupportError.invalidFixture
  }
  return entry
}

func makeReleasedPreDriveEvidence(
  for entry: BundledProductReleaseEntry,
  routePlanID: String? = nil,
  networkSnapshotID: String? = nil,
  vehicleClass: String = "STANDARD",
  quoteVehicleClass: String? = nil
) -> PreDriveReviewEvidence {
  let routePlan = entry.release.navigation.bundle.routePlan
  return PreDriveReviewEvidence(
    evaluatedAt: "2026-07-25T12:00:00+09:00",
    networkSnapshotID: networkSnapshotID ?? routePlan.networkSnapshotID,
    routePlanID: routePlanID ?? routePlan.id,
    vehicleClass: vehicleClass,
    passageEvidence: .noKnownConflictRealtimeUnconfirmed,
    tariffQuotes: [
      TariffQuote(
        id: "test.released-road.tariff.active",
        entryFacilityID: routePlan.entryFacilityID,
        exitFacilityID: routePlan.exitFacilityID,
        vehicleClass: quoteVehicleClass ?? vehicleClass,
        tariffVersionID: "test.released-road.tariff.v1",
        tariffVersionStatus: .active,
        tariffDistanceKM: 24.8,
        estimatedAmountYen: 1_320,
        evidenceStatus: .estimated,
        checkedAt: "2026-07-25T11:30:00+09:00",
        officialQueryReference: "https://search.shutoko.jp/"
      )
    ]
  )
}

@MainActor
func authorReleasedRoute(
  _ model: ReleasedProductRouteAuthoringModel,
  entry: BundledProductReleaseEntry
) {
  model.selectRelease(entry.release.releaseID)
  while let step = model.currentStep {
    model.selectReleasedChoice(step.choiceID)
  }
  model.compile()
}
