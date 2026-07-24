import CoreLocation
import Foundation
import KaidoAppleAdapters
import KaidoDomain
import KaidoNavigation
import XCTest

@testable import KaidoRoutesApp

final class SyntheticProductRuntimeTests: XCTestCase {
  func testBundledArtifactBuildsOnlySyntheticJointReleaseRuntime() throws {
    let fixture = try SyntheticProductRuntimeFixture.bundled()
    let runtime = try KaidoProductNavigationRuntime(release: fixture.release)

    XCTAssertEqual(
      fixture.release.releaseID,
      SyntheticProductRuntimeFixture.expectedProductReleaseID
    )
    XCTAssertEqual(
      runtime.navigationReleaseID,
      "test.navigation-release.release-bundle.v1"
    )
    XCTAssertEqual(
      runtime.routePlanID,
      fixture.release.routeAtlas.routePlan.id
    )
    XCTAssertEqual(
      runtime.networkSnapshotID,
      fixture.release.routeAtlas.networkSnapshot.id
    )
    XCTAssertGreaterThan(fixture.encodedByteCount, 0)
    XCTAssertTrue(
      fixture.release.navigation.sourceRegistry.references.allSatisfy {
        $0.licenceIdentifier == "SYNTHETIC_TEST_ONLY"
      }
    )
    XCTAssertTrue(
      fixture.release.routeAtlas.sourceRegistry.references.allSatisfy {
        $0.licenceIdentifier == "SYNTHETIC_TEST_ONLY"
      }
    )
  }

  func testFixtureRejectsAProductIdentityMutationBeforeRuntimeAdmission() throws {
    let url = try XCTUnwrap(
      Bundle.main.url(
        forResource: SyntheticProductRuntimeFixture.resourceName,
        withExtension: "json"
      )
    )
    let artifact = try JSONDecoder().decode(
      KaidoProductReleaseArtifact.self,
      from: Data(contentsOf: url)
    )
    let mutated = KaidoProductReleaseArtifact(
      releaseID: "release-without-synthetic-preview-identity",
      releasedAt: artifact.releasedAt,
      navigationRelease: artifact.navigationRelease,
      routeAtlasRelease: artifact.routeAtlasRelease
    )
    let data = try JSONEncoder().encode(mutated)

    XCTAssertThrowsError(try SyntheticProductRuntimeFixture.decode(data)) {
      XCTAssertEqual(
        $0 as? SyntheticProductRuntimeFixtureError,
        .unexpectedReleaseIdentity
      )
    }
  }

  func testFixtureRejectsASourceThatLosesSyntheticClassification() throws {
    let url = try XCTUnwrap(
      Bundle.main.url(
        forResource: SyntheticProductRuntimeFixture.resourceName,
        withExtension: "json"
      )
    )
    var root = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: url))
        as? [String: Any]
    )
    var navigationRelease = try XCTUnwrap(
      root["navigation_release"] as? [String: Any]
    )
    var sourceRegistry = try XCTUnwrap(
      navigationRelease["source_registry"] as? [String: Any]
    )
    var references = try XCTUnwrap(
      sourceRegistry["references"] as? [[String: Any]]
    )
    references[0]["licence_identifier"] = "UNCLASSIFIED"
    sourceRegistry["references"] = references
    navigationRelease["source_registry"] = sourceRegistry
    root["navigation_release"] = navigationRelease
    let data = try JSONSerialization.data(withJSONObject: root)

    XCTAssertThrowsError(try SyntheticProductRuntimeFixture.decode(data)) {
      XCTAssertEqual(
        $0 as? SyntheticProductRuntimeFixtureError,
        .nonSyntheticSource
      )
    }
  }

  @MainActor
  func testForegroundPipelinePublishesActorSnapshotsAtomically() async throws {
    let model = try SyntheticProductRuntimeModel(
      fixture: SyntheticProductRuntimeFixture.bundled(),
      sourceEvidenceProvider: FixedSourceEvidenceProvider(isSimulated: false)
    )
    await model.activate()

    XCTAssertEqual(model.activation, .ready)
    XCTAssertEqual(model.snapshot?.journeyPhase, .planning)
    XCTAssertFalse(try XCTUnwrap(model.snapshot).strictRouteAutoCommitAllowed)
    XCTAssertFalse(model.isRealRoadAuthority)

    await model.process(
      [makeLocation(longitude: 139.75925, timestamp: 1_000)],
      receivedAt: Date(timeIntervalSince1970: 1_000)
    )
    XCTAssertEqual(model.snapshot?.journeyPhase, .entryTransition)
    XCTAssertEqual(
      model.inputState,
      .entryUpdated(status: .observing, rejection: nil)
    )

    await model.process(
      [makeLocation(longitude: 139.75975, timestamp: 1_001)],
      receivedAt: Date(timeIntervalSince1970: 1_001)
    )
    XCTAssertEqual(model.snapshot?.journeyPhase, .strictRoute)
    XCTAssertTrue(try XCTUnwrap(model.snapshot).strictRouteAutoCommitAllowed)
    XCTAssertEqual(
      model.inputState,
      .entryUpdated(status: .strictRouteEntered, rejection: nil)
    )

    await model.process(
      [makeLocation(longitude: 139.76025, timestamp: 1_002)],
      receivedAt: Date(timeIntervalSince1970: 1_002)
    )
    guard case .matcherUpdated(let confidence, _) = model.inputState else {
      XCTFail("Expected an atomic matcher update, got \(model.inputState)")
      return
    }
    XCTAssertEqual(confidence, .high)
    XCTAssertEqual(model.snapshot?.journeyPhase, .strictRoute)
  }

  @MainActor
  func testSoftwareSimulationIsRejectedBeforeEntryAdmission() async throws {
    let model = try SyntheticProductRuntimeModel(
      fixture: SyntheticProductRuntimeFixture.bundled(),
      sourceEvidenceProvider: FixedSourceEvidenceProvider(isSimulated: true)
    )
    await model.activate()

    await model.process(
      [makeLocation(longitude: 139.75925, timestamp: 1_000)],
      receivedAt: Date(timeIntervalSince1970: 1_000)
    )

    XCTAssertEqual(
      model.inputState,
      .adapterRejected(
        CoreLocationObservationRejectionReason.simulatedLocationRejected.rawValue
      )
    )
    XCTAssertEqual(model.snapshot?.journeyPhase, .planning)
    XCTAssertFalse(try XCTUnwrap(model.snapshot).strictRouteAutoCommitAllowed)
  }

  private func makeLocation(
    longitude: Double,
    timestamp: TimeInterval
  ) -> CLLocation {
    CLLocation(
      coordinate: CLLocationCoordinate2D(
        latitude: 35.68,
        longitude: longitude
      ),
      altitude: 0,
      horizontalAccuracy: 5,
      verticalAccuracy: 5,
      course: 90,
      courseAccuracy: 2,
      speed: 10,
      speedAccuracy: 1,
      timestamp: Date(timeIntervalSince1970: timestamp)
    )
  }

  private struct FixedSourceEvidenceProvider:
    CoreLocationSourceEvidenceProviding
  {
    let isSimulated: Bool

    func evidence(for _: CLLocation) -> CoreLocationSourceEvidence {
      CoreLocationSourceEvidence(
        deliverySource: .deviceOrUndisclosed,
        sourceInformationAvailable: true,
        isSimulatedBySoftware: isSimulated
      )
    }
  }
}
