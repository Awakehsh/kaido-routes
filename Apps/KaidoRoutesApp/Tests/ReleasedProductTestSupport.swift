import Foundation
import KaidoAppleAdapters
import KaidoDomain
import KaidoNavigation
import KaidoPresentation

@testable import KaidoRoutesApp

enum ReleasedProductTestSupportError: Error {
  case missingResource
  case invalidFixture
}

func makeReleasedProductTestEntry(
  releaseID: String = "test.released-road.product",
  includePreDriveEvidence: Bool = false,
  preDriveEvidencePaymentMethods: [ShutoPaymentMethod] = [.etc],
  preDriveEvidenceUpdateTrustKeys:
    [PreDriveEvidenceUpdateTrustKey]? = nil,
  preDriveEvidenceUpdateEndpoint:
    PreDriveEvidenceUpdateEndpoint? = nil
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
  let release = try KaidoProductReleaseArtifactCodec.decode(data)
  let preDriveEvidenceData: Data? =
    if includePreDriveEvidence {
      try makeBundledPreDriveEvidenceData(
        for: release,
        paymentMethods: preDriveEvidencePaymentMethods
      )
    } else {
      nil
    }
  let descriptor = BundledProductReleaseDescriptor(
    resourceName: "released-road-product",
    resourceExtension: "json",
    expectedSHA256:
      BundledProductReleaseCatalogLoader.sha256Hex(data),
    expectedReleaseID: releaseID,
    role: .foregroundNavigation,
    preDriveEvidence: preDriveEvidenceData.map {
      BundledPreDriveEvidenceDescriptor(
        manifestResourceName: "released-pre-drive-evidence",
        expectedManifestSHA256:
          BundledProductReleaseCatalogLoader.sha256Hex($0),
        expectedReleaseID: "test.pre-drive-evidence.app.v1"
      )
    },
    preDriveEvidenceUpdateTrustKeys:
      preDriveEvidenceUpdateTrustKeys,
    preDriveEvidenceUpdateEndpoint:
      preDriveEvidenceUpdateEndpoint
  )
  let catalog = try BundledProductReleaseCatalogLoader.load(
    descriptors: [descriptor],
    preDriveEvidenceDataProvider: { _ in preDriveEvidenceData },
    dataProvider: { _ in data }
  )
  guard let entry = catalog.foregroundNavigationEntries.first else {
    throw ReleasedProductTestSupportError.invalidFixture
  }
  return entry
}

private func makeBundledPreDriveEvidenceData(
  for release: KaidoProductRelease,
  paymentMethods: [ShutoPaymentMethod]
) throws -> Data {
  let routePlan = release.navigation.bundle.routePlan
  let manifest = PreDriveEvidenceBundleManifest(
    releaseID: "test.pre-drive-evidence.app.v1",
    releasedAt: "2026-07-25T12:15:00+09:00",
    evidenceScope: .releasedRoad,
    productReleaseID: release.releaseID,
    navigationReleaseID: release.navigation.releaseID,
    networkSnapshotID: routePlan.networkSnapshotID,
    routePlanID: routePlan.id,
    sourceRegistry: [
      PreDriveEvidenceSourceReference(
        id: "test.pre-drive-source.tariff",
        roles: [.tariffQuery],
        authorityName: "Test tariff authority",
        sourceURL: "https://search.shutoko.jp/",
        contentSHA256: String(repeating: "a", count: 64),
        checkedAt: "2026-07-25T11:30:00+09:00",
        reviewerID: "test.reviewer.tariff",
        reviewedAt: "2026-07-25T12:10:00+09:00"
      ),
      PreDriveEvidenceSourceReference(
        id: "test.pre-drive-source.passage",
        roles: [.passageReview],
        authorityName: "Test passage authority",
        sourceURL: "https://www.shutoko.jp/",
        contentSHA256: String(repeating: "b", count: 64),
        checkedAt: "2026-07-25T11:35:00+09:00",
        reviewerID: "test.reviewer.passage",
        reviewedAt: "2026-07-25T12:10:00+09:00"
      ),
    ],
    records: paymentMethods.map { paymentMethod in
      PreDriveEvidenceRecord(
        id:
          "test.pre-drive-record.standard-\(paymentMethod.rawValue.lowercased())",
        validFrom: "2026-07-25T12:00:00+09:00",
        expiresAt: "2026-07-26T00:00:00+09:00",
        sourceReferenceIDs: [
          "test.pre-drive-source.tariff",
          "test.pre-drive-source.passage",
        ],
        evidence: PreDriveReviewEvidence(
          evaluatedAt: "2026-07-25T12:00:00+09:00",
          networkSnapshotID: routePlan.networkSnapshotID,
          routePlanID: routePlan.id,
          vehicleClass: .standard,
          paymentMethod: paymentMethod,
          passageEvidence: .noKnownConflictRealtimeUnconfirmed,
          tariffQuotes: [
            TariffQuote(
              id:
                "test.released-road.tariff.\(paymentMethod.rawValue.lowercased()).active",
              entryFacilityID: routePlan.entryFacilityID,
              exitFacilityID: routePlan.exitFacilityID,
              vehicleClass: .standard,
              paymentMethod: paymentMethod,
              tariffVersionID: "test.released-road.tariff.v1",
              tariffVersionStatus: .active,
              tariffDistanceKM: 24.8,
              estimatedAmountYen:
                paymentMethod == .etc ? 1_320 : 1_400,
              evidenceStatus: .estimated,
              checkedAt: "2026-07-25T11:30:00+09:00",
              officialQueryReference: "https://search.shutoko.jp/"
            )
          ]
        )
      )
    }
  )
  return try PreDriveEvidenceBundleCodec.encode(
    manifest,
    context: PreDriveEvidenceBundleContext(
      productReleaseID: release.releaseID,
      productReleasedAt: release.releasedAt,
      navigationReleaseID: release.navigation.releaseID,
      routePlan: routePlan,
      evidenceScope: .releasedRoad
    )
  )
}

func makeReleasedPreDriveEvidence(
  for entry: BundledProductReleaseEntry,
  routePlanID: String? = nil,
  networkSnapshotID: String? = nil,
  vehicleClass: ShutoVehicleClass = .standard,
  quoteVehicleClass: ShutoVehicleClass? = nil,
  paymentMethod: ShutoPaymentMethod = .etc,
  quotePaymentMethod: ShutoPaymentMethod? = nil
) -> PreDriveReviewEvidence {
  let routePlan = entry.release.navigation.bundle.routePlan
  return PreDriveReviewEvidence(
    evaluatedAt: "2026-07-25T12:00:00+09:00",
    networkSnapshotID: networkSnapshotID ?? routePlan.networkSnapshotID,
    routePlanID: routePlanID ?? routePlan.id,
    vehicleClass: vehicleClass,
    paymentMethod: paymentMethod,
    passageEvidence: .noKnownConflictRealtimeUnconfirmed,
    tariffQuotes: [
      TariffQuote(
        id: "test.released-road.tariff.active",
        entryFacilityID: routePlan.entryFacilityID,
        exitFacilityID: routePlan.exitFacilityID,
        vehicleClass: quoteVehicleClass ?? vehicleClass,
        paymentMethod: quotePaymentMethod ?? paymentMethod,
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
  entry: BundledProductReleaseEntry,
  vehicleClass: ShutoVehicleClass? = .standard,
  paymentMethod: ShutoPaymentMethod? = .etc
) {
  model.selectRelease(entry.release.releaseID)
  while let step = model.currentStep {
    model.selectReleasedChoice(step.choiceID)
  }
  model.compile()
  if let vehicleClass {
    model.selectVehicleClass(vehicleClass)
  }
  if let paymentMethod {
    model.selectPaymentMethod(paymentMethod)
  }
}
