import CoreLocation
import Foundation
import KaidoAppleAdapters
import KaidoNavigation
import XCTest

@testable import KaidoRoutesApp

final class InternalLocationCalibrationTests: XCTestCase {
  func testBundledCandidateBuildsExactReviewOnlyMatcherCorridor() throws {
    let fixture = try InternalLocationCalibrationFixture.bundled()

    XCTAssertEqual(
      fixture.corridor.networkSnapshotID,
      "shutoko.candidate.osm-geofabrik-kanto-260721.k7-northwest"
    )
    XCTAssertEqual(
      fixture.corridor.routePlanID,
      "shutoko.plan.k7-northwest.aoba-up-to-kohoku-up.osm-directed-candidate"
    )
    XCTAssertEqual(fixture.corridor.occurrences.count, 13)
    XCTAssertEqual(fixture.corridor.edges.count, 15)
    XCTAssertEqual(
      fixture.corridor.occurrences.first?.id,
      fixture.initialOccurrenceID
    )
    XCTAssertEqual(fixture.evidenceState, "CANDIDATE")
    XCTAssertEqual(fixture.licence, "ODbL-1.0")
    XCTAssertEqual(
      fixture.licenceURL.absoluteString,
      "https://opendatacommons.org/licenses/odbl/1-0/"
    )
    XCTAssertEqual(fixture.attribution, "© OpenStreetMap contributors")
    XCTAssertEqual(
      fixture.attributionURL.absoluteString,
      "https://www.openstreetmap.org/copyright"
    )
    XCTAssertFalse(fixture.navigationAuthority)
    XCTAssertTrue(fixture.corridor.validationIssues.isEmpty)

    let firstDivergence = try XCTUnwrap(
      fixture.corridor.edges.first {
        $0.id == "shutoko.edge.osm-way.692798735.forward"
      }
    )
    XCTAssertEqual(
      firstDivergence.successorEdgeIDs,
      [
        "shutoko.edge.osm-way.686983570.forward",
        "shutoko.edge.osm-way.686983567.forward",
      ]
    )
  }

  func testCandidateWithNavigationAuthorityFailsClosed() throws {
    let databaseURL = try XCTUnwrap(
      Bundle.main.url(
        forResource: InternalLocationCalibrationFixture.databaseResourceName,
        withExtension: "json"
      )
    )
    let candidateURL = try XCTUnwrap(
      Bundle.main.url(
        forResource: InternalLocationCalibrationFixture.candidateResourceName,
        withExtension: "json"
      )
    )
    var database = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: databaseURL))
        as? [String: Any]
    )
    database["navigation_authority"] = true
    let mutatedDatabase = try JSONSerialization.data(withJSONObject: database)

    XCTAssertThrowsError(
      try InternalLocationCalibrationFixture.decode(
        databaseData: mutatedDatabase,
        candidateData: Data(contentsOf: candidateURL)
      )
    ) { error in
      guard
        case .invalidCandidate(let issues) =
          error as? InternalLocationCalibrationFixtureError
      else {
        XCTFail("Expected invalid-candidate error, got \(error)")
        return
      }
      XCTAssertTrue(
        issues.contains("candidate database unexpectedly has navigation authority")
      )
    }
  }

  func testCalibrationRunProducesCoordinateFreeNonReleaseReport() throws {
    let fixture = try InternalLocationCalibrationFixture.bundled()
    let adapter = try CoreLocationObservationAdapter(
      sessionID: "app-test",
      sourceEvidenceProvider: FixedSourceEvidenceProvider()
    )
    let matcherSession = try RouteAwareSwiftMatcher().makeSession(
      corridor: fixture.corridor,
      initialOccurrenceID: fixture.initialOccurrenceID
    )
    let context = MatcherPrivateTraceContext(
      traceID: "private-app-test-trace",
      scope: MatcherCalibrationScope(
        networkSnapshotID: fixture.corridor.networkSnapshotID,
        matcherAlgorithmID: RouteAwareSwiftMatcher.algorithmID,
        matcherConfigurationID: "route-aware-swift-hmm-defaults-v1",
        deviceConfigurationID: "opaque-test-device",
        fieldTransportContext: .phoneOnly
      ),
      routePlanID: fixture.corridor.routePlanID,
      deviceModel: "private-device-model",
      operatingSystemVersion: "private-os-version",
      appBuild: "private-app-build",
      mountDescription: "private-mount",
      collectionMethod: .automatedLogger,
      startedAtMilliseconds: 1_000
    )
    let session = try CoreLocationMatcherCalibrationSession(
      observationAdapter: adapter,
      matcherSession: matcherSession,
      traceRecorder: CoreLocationPrivateTraceRecorder(context: context)
    )
    var run = InternalLocationCalibrationRun(session: session)
    let coordinate = try XCTUnwrap(fixture.corridor.edges.first?.coordinates.first)
    let receivedAt = Date(timeIntervalSince1970: 1_002)

    try run.process(
      [
        CLLocation(
          coordinate: CLLocationCoordinate2D(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
          ),
          altitude: 0,
          horizontalAccuracy: 5,
          verticalAccuracy: 5,
          course: 45,
          courseAccuracy: 2,
          speed: 10,
          speedAccuracy: 1,
          timestamp: Date(timeIntervalSince1970: 1_001)
        )
      ],
      receivedAt: receivedAt
    )

    let report = try XCTUnwrap(
      run.makeCoordinateFreeReport(reportID: "coordinate-free-app-test")
    )
    let reportJSON = String(
      decoding: try JSONEncoder().encode(report),
      as: UTF8.self
    )

    XCTAssertEqual(run.summary.entryCount, 1)
    XCTAssertEqual(run.summary.matchedCount, 1)
    XCTAssertEqual(report.gateStatus, .insufficientHeldOutEvidence)
    XCTAssertFalse(reportJSON.contains("latitude"))
    XCTAssertFalse(reportJSON.contains("longitude"))
    XCTAssertFalse(reportJSON.contains("private-app-test-trace"))
    XCTAssertFalse(reportJSON.contains(fixture.corridor.routePlanID))
    XCTAssertFalse(reportJSON.contains("private-device-model"))
    XCTAssertFalse(reportJSON.contains("private-mount"))
  }

  func testTransportModesKeepConnectionAndFieldDeclarationSeparate() {
    XCTAssertEqual(
      InternalCalibrationTransportMode.connectedUnknown.connectionContext,
      .connectedTransportUnknown
    )
    XCTAssertEqual(
      InternalCalibrationTransportMode.connectedUnknown.fieldTransportContext,
      .carPlayConnectedTransportUnknown
    )
    XCTAssertEqual(
      InternalCalibrationTransportMode.fieldDeclaredWired.connectionContext,
      .fieldDeclaredWired
    )
    XCTAssertEqual(
      InternalCalibrationTransportMode.fieldDeclaredWireless.fieldTransportContext,
      .fieldDeclaredWirelessCarPlay
    )
  }

  @MainActor
  func testCaptureRequiresExplicitDeviceAndMountMetadata() throws {
    let model = InternalLocationCalibrationModel(
      fixture: try InternalLocationCalibrationFixture.bundled()
    )

    XCTAssertFalse(model.canStart)
    model.deviceConfigurationID = "opaque-device-configuration"
    XCTAssertFalse(model.canStart)
    model.mountDescription = "private fixed mount"
    XCTAssertTrue(model.canStart)
  }

  private struct FixedSourceEvidenceProvider:
    CoreLocationSourceEvidenceProviding
  {
    func evidence(for _: CLLocation) -> CoreLocationSourceEvidence {
      CoreLocationSourceEvidence(
        deliverySource: .deviceOrUndisclosed,
        sourceInformationAvailable: true,
        isSimulatedBySoftware: false
      )
    }
  }
}
