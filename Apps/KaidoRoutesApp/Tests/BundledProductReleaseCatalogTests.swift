import Foundation
import KaidoDomain
import KaidoNavigation
import XCTest

@testable import KaidoRoutesApp

final class BundledProductReleaseCatalogTests: XCTestCase {
  func testBundledManifestLoadsOnlyOneHashBoundDemoRelease() throws {
    let catalog = try BundledProductReleaseCatalogLoader.bundledPreview()
    let entry = try XCTUnwrap(catalog.demoEntries.first)

    XCTAssertEqual(catalog.entries.count, 1)
    XCTAssertEqual(catalog.demoEntries.count, 1)
    XCTAssertTrue(catalog.foregroundNavigationEntries.isEmpty)
    XCTAssertEqual(
      entry.release.releaseID,
      "preview.synthetic.product-release.v1"
    )
    XCTAssertEqual(entry.descriptor.role, .demoOnly)
    XCTAssertGreaterThan(entry.encodedByteCount, 0)
    XCTAssertNil(entry.release.foregroundLiveInputAuthority)
  }

  func testContentMutationFailsAtManifestHashBeforeCodecAdmission() throws {
    let data = try bundledPreviewData()
    var mutated = data
    mutated.append(0x20)

    XCTAssertThrowsError(
      try load(
        descriptor: .syntheticPreview,
        data: mutated
      )
    ) {
      XCTAssertEqual(
        $0 as? BundledProductReleaseCatalogError,
        .resourceHashMismatch(
          "synthetic-product-runtime-preview.json"
        )
      )
    }
  }

  func testManifestRoleCannotPromoteSyntheticRelease() throws {
    let data = try bundledPreviewData()
    let descriptor = BundledProductReleaseDescriptor(
      resourceName: "synthetic-product-runtime-preview",
      resourceExtension: "json",
      expectedSHA256:
        BundledProductReleaseCatalogLoader.sha256Hex(data),
      expectedReleaseID: "preview.synthetic.product-release.v1",
      role: .foregroundNavigation
    )

    XCTAssertThrowsError(
      try load(descriptor: descriptor, data: data)
    ) {
      XCTAssertEqual(
        $0 as? BundledProductReleaseCatalogError,
        .releaseRoleMismatch(
          "synthetic-product-runtime-preview.json"
        )
      )
    }
  }

  func testReleasedRoadRoleRequiresCodecMintedForegroundAuthority() throws {
    let data = try releasedRoadData()
    let descriptor = BundledProductReleaseDescriptor(
      resourceName: "released-road-product",
      resourceExtension: "json",
      expectedSHA256:
        BundledProductReleaseCatalogLoader.sha256Hex(data),
      expectedReleaseID: "test.released-road.product",
      role: .foregroundNavigation
    )

    let catalog = try load(descriptor: descriptor, data: data)
    let entry = try XCTUnwrap(
      catalog.foregroundNavigationEntries.first
    )

    XCTAssertEqual(catalog.demoEntries.count, 0)
    XCTAssertEqual(entry.release.runtimeUse.evidenceScope, .releasedRoad)
    XCTAssertEqual(
      entry.release.runtimeUse.liveInputPolicy,
      .foregroundWhenInUse
    )
    XCTAssertNotNil(entry.release.foregroundLiveInputAuthority)
  }

  func testNavigationSelectionRequiresWholeRoutePlanEquality() throws {
    let data = try releasedRoadData()
    let descriptor = BundledProductReleaseDescriptor(
      resourceName: "released-road-product",
      resourceExtension: "json",
      expectedSHA256:
        BundledProductReleaseCatalogLoader.sha256Hex(data),
      expectedReleaseID: "test.released-road.product",
      role: .foregroundNavigation
    )
    let catalog = try load(descriptor: descriptor, data: data)
    let releasedRoutePlan = try XCTUnwrap(
      catalog.foregroundNavigationEntries.first
    ).release.navigation.bundle.routePlan

    guard
      case .selected(let selected) =
        catalog.selectForegroundNavigationRelease(
          matching: releasedRoutePlan
        )
    else {
      return XCTFail("Expected exact released RoutePlan selection")
    }
    XCTAssertEqual(selected.release.releaseID, "test.released-road.product")

    let driftedRoutePlan = RoutePlan(
      id: releasedRoutePlan.id,
      networkSnapshotID: "\(releasedRoutePlan.networkSnapshotID).drift",
      entryFacilityID: releasedRoutePlan.entryFacilityID,
      exitFacilityID: releasedRoutePlan.exitFacilityID,
      recoveryPolicy: releasedRoutePlan.recoveryPolicy,
      actualDistanceKM: releasedRoutePlan.actualDistanceKM,
      occurrences: releasedRoutePlan.occurrences
    )
    XCTAssertEqual(
      catalog.selectForegroundNavigationRelease(
        matching: driftedRoutePlan
      ),
      .unavailable
    )
  }

  func testNavigationSelectionFailsClosedWhenExactRouteHasMultipleReleases()
    throws
  {
    let firstData = try releasedRoadData(
      releaseID: "test.released-road.first"
    )
    let secondData = try releasedRoadData(
      releaseID: "test.released-road.second"
    )
    let descriptors = [
      releasedRoadDescriptor(
        resourceName: "released-road-first",
        releaseID: "test.released-road.first",
        data: firstData
      ),
      releasedRoadDescriptor(
        resourceName: "released-road-second",
        releaseID: "test.released-road.second",
        data: secondData
      ),
    ]
    let catalog = try BundledProductReleaseCatalogLoader.load(
      descriptors: descriptors
    ) { descriptor in
      switch descriptor.resourceName {
      case "released-road-first":
        firstData
      case "released-road-second":
        secondData
      default:
        nil
      }
    }
    let routePlan = try XCTUnwrap(
      catalog.foregroundNavigationEntries.first
    ).release.navigation.bundle.routePlan

    XCTAssertEqual(
      catalog.selectForegroundNavigationRelease(matching: routePlan),
      .ambiguous([
        "test.released-road.first",
        "test.released-road.second",
      ])
    )
  }

  func testDuplicateResourceAndReleaseIdentityFailClosed() throws {
    let data = try bundledPreviewData()
    let descriptor = BundledProductReleaseDescriptor.syntheticPreview

    XCTAssertThrowsError(
      try BundledProductReleaseCatalogLoader.load(
        descriptors: [descriptor, descriptor]
      ) { _ in data }
    ) {
      XCTAssertEqual(
        $0 as? BundledProductReleaseCatalogError,
        .duplicateResource(
          "synthetic-product-runtime-preview.json"
        )
      )
    }

    let duplicateIdentityDescriptor = BundledProductReleaseDescriptor(
      resourceName: "second-synthetic-resource",
      resourceExtension: "json",
      expectedSHA256:
        BundledProductReleaseCatalogLoader.sha256Hex(data),
      expectedReleaseID: descriptor.expectedReleaseID,
      role: .demoOnly
    )
    XCTAssertThrowsError(
      try BundledProductReleaseCatalogLoader.load(
        descriptors: [descriptor, duplicateIdentityDescriptor]
      ) { _ in data }
    ) {
      XCTAssertEqual(
        $0 as? BundledProductReleaseCatalogError,
        .duplicateReleaseID(descriptor.expectedReleaseID)
      )
    }
  }

  func testMissingCorruptAndInvalidDescriptorHaveStableFailures() throws {
    let descriptor = BundledProductReleaseDescriptor.syntheticPreview

    XCTAssertThrowsError(
      try BundledProductReleaseCatalogLoader.load(
        descriptors: [descriptor]
      ) { _ in nil }
    ) {
      XCTAssertEqual(
        $0 as? BundledProductReleaseCatalogError,
        .missingResource(descriptor.resourceFilename)
      )
    }

    let corruptData = Data("not-json".utf8)
    let corruptDescriptor = BundledProductReleaseDescriptor(
      resourceName: "corrupt-product-release",
      resourceExtension: "json",
      expectedSHA256:
        BundledProductReleaseCatalogLoader.sha256Hex(corruptData),
      expectedReleaseID: "test.corrupt.release",
      role: .demoOnly
    )
    XCTAssertThrowsError(
      try load(
        descriptor: corruptDescriptor,
        data: corruptData
      )
    ) {
      XCTAssertEqual(
        $0 as? BundledProductReleaseCatalogError,
        .invalidProductRelease(
          corruptDescriptor.resourceFilename
        )
      )
    }

    let invalidDescriptor = BundledProductReleaseDescriptor(
      resourceName: "../outside-bundle",
      resourceExtension: "json",
      expectedSHA256: String(repeating: "0", count: 64),
      expectedReleaseID: "test.invalid.descriptor",
      role: .demoOnly
    )
    XCTAssertThrowsError(
      try BundledProductReleaseCatalogLoader.load(
        descriptors: [invalidDescriptor]
      ) { _ in Data() }
    ) {
      XCTAssertEqual(
        $0 as? BundledProductReleaseCatalogError,
        .invalidDescriptor(invalidDescriptor.resourceFilename)
      )
    }
  }

  func testEmptyManifestAndReleaseIdentityDriftHaveStableFailures()
    throws
  {
    XCTAssertThrowsError(
      try BundledProductReleaseCatalogLoader.load(
        descriptors: []
      ) { _ in nil }
    ) {
      XCTAssertEqual(
        $0 as? BundledProductReleaseCatalogError,
        .emptyManifest
      )
    }

    let data = try bundledPreviewData()
    let driftedDescriptor = BundledProductReleaseDescriptor(
      resourceName: "identity-drift",
      resourceExtension: "json",
      expectedSHA256:
        BundledProductReleaseCatalogLoader.sha256Hex(data),
      expectedReleaseID: "preview.synthetic.product-release.drift",
      role: .demoOnly
    )
    XCTAssertThrowsError(
      try load(descriptor: driftedDescriptor, data: data)
    ) {
      XCTAssertEqual(
        $0 as? BundledProductReleaseCatalogError,
        .releaseIdentityMismatch(
          driftedDescriptor.resourceFilename
        )
      )
    }
  }

  private func load(
    descriptor: BundledProductReleaseDescriptor,
    data: Data
  ) throws -> BundledProductReleaseCatalog {
    try BundledProductReleaseCatalogLoader.load(
      descriptors: [descriptor]
    ) { _ in data }
  }

  private func bundledPreviewData() throws -> Data {
    let url = try XCTUnwrap(
      Bundle.main.url(
        forResource: SyntheticProductRuntimeFixture.resourceName,
        withExtension: "json"
      )
    )
    return try Data(contentsOf: url)
  }

  private func releasedRoadDescriptor(
    resourceName: String,
    releaseID: String,
    data: Data
  ) -> BundledProductReleaseDescriptor {
    BundledProductReleaseDescriptor(
      resourceName: resourceName,
      resourceExtension: "json",
      expectedSHA256:
        BundledProductReleaseCatalogLoader.sha256Hex(data),
      expectedReleaseID: releaseID,
      role: .foregroundNavigation
    )
  }

  private func releasedRoadData(
    releaseID: String = "test.released-road.product"
  ) throws -> Data {
    var root = try XCTUnwrap(
      JSONSerialization.jsonObject(with: bundledPreviewData())
        as? [String: Any]
    )
    root["release_id"] = releaseID
    root["runtime_use"] = [
      "evidence_scope": "RELEASED_ROAD",
      "live_input_policy": "FOREGROUND_WHEN_IN_USE",
    ]
    for releaseKey in ["navigation_release", "route_atlas_release"] {
      var nestedRelease = try XCTUnwrap(
        root[releaseKey] as? [String: Any]
      )
      var registry = try XCTUnwrap(
        nestedRelease["source_registry"] as? [String: Any]
      )
      var references = try XCTUnwrap(
        registry["references"] as? [[String: Any]]
      )
      for index in references.indices {
        references[index]["licence_identifier"] =
          "TEST_REVIEWED_ROAD_ONLY"
      }
      registry["references"] = references
      nestedRelease["source_registry"] = registry
      root[releaseKey] = nestedRelease
    }
    return try JSONSerialization.data(withJSONObject: root)
  }
}
