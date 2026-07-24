import Foundation

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
