import KaidoSurfaceRouting
import XCTest

@testable import KaidoRoutesApp

@MainActor
final class C2NavigationDemoModelTests: XCTestCase {
  func testCompleteNavigationRunsFromSurfaceOriginThroughC2ToDestination()
    async
  {
    let model = C2NavigationDemoModel.preview()

    await model.startNavigation()
    model.pause()

    XCTAssertEqual(model.phase, .surfaceAccess)
    XCTAssertEqual(model.origin?.title, "東京都庁")
    XCTAssertEqual(model.destination?.title, "東京駅")
    XCTAssertEqual(model.accessRoute?.providerID, "preview.c2.surface")
    XCTAssertEqual(model.egressRoute?.providerID, "preview.c2.surface")

    advance(
      model,
      until: {
        $0.phase == .expressway
          && $0.expresswayOccurrenceIndex == 9
      })
    XCTAssertEqual(model.highwayInstruction, .kasaiRight)
    XCTAssertEqual(model.junctionInset?.selectedBranch, .right)
    XCTAssertNil(model.junctionInset?.distanceMeters)
    XCTAssertEqual(model.junctionInset?.routeShield, "B")

    advance(
      model,
      until: {
        $0.phase == .expressway
          && $0.expresswayOccurrenceIndex == 13
      })
    XCTAssertEqual(model.highwayInstruction, .oiLeft)
    XCTAssertEqual(model.junctionInset?.selectedBranch, .left)
    XCTAssertEqual(model.junctionInset?.distanceMeters, 500)
    XCTAssertEqual(model.junctionInset?.routeShield, "C2")
    XCTAssertTrue(model.isTunnelPositionEstimated)

    advance(model, until: { $0.phase == .completed })
    XCTAssertEqual(model.journeyProgressFraction, 1)
    XCTAssertEqual(
      model.currentSurfaceStep?.instruction,
      "目的地在前方"
    )
  }

  func testOfficialC2SurfaceBoundaryCoordinatesRemainExact() {
    XCTAssertEqual(
      C2NavigationDemoModel.tomigayaEntranceCoordinate.latitude,
      35.66378171,
      accuracy: 0.000000001
    )
    XCTAssertEqual(
      C2NavigationDemoModel.tomigayaEntranceCoordinate.longitude,
      139.6877503,
      accuracy: 0.000000001
    )
    XCTAssertEqual(
      C2NavigationDemoModel.hatsudaiMinamiExitCoordinate.latitude,
      35.67511257,
      accuracy: 0.000000001
    )
    XCTAssertEqual(
      C2NavigationDemoModel.hatsudaiMinamiExitCoordinate.longitude,
      139.6878147,
      accuracy: 0.000000001
    )
  }

  func testNavigationPresentationPreservesOrderedOccurrenceProgress() {
    let presentation = C2CompletedRouteDemo.navigationPresentation(
      currentOccurrenceIndex: 9,
      fraction: 0.5,
      positionIsEstimated: false
    )

    XCTAssertEqual(presentation.orderedOccurrences.count, 16)
    XCTAssertEqual(
      presentation.orderedOccurrences.prefix(9).map(\.state),
      Array(repeating: .passed, count: 9)
    )
    XCTAssertEqual(
      presentation.orderedOccurrences[9].state,
      .current
    )
    XCTAssertEqual(
      presentation.orderedOccurrences[10].state,
      .future
    )
    guard case .measured(let marker) = presentation.position else {
      return XCTFail("Expected measured navigation marker")
    }
    XCTAssertEqual(marker.occurrenceIndex, 9)
  }

  func testSurfaceLegCannotFallBackToAnExplicitHighwayCandidate() async {
    let model = C2NavigationDemoModel(
      originQuery: "任意出发地",
      destinationQuery: "任意目的地",
      locationProvider: C2TestLocationProvider(),
      placeResolver: C2TestPlaceResolver(),
      surfaceProvider: C2ExplicitHighwayProvider()
    )

    await model.startNavigation()

    XCTAssertEqual(model.phase, .failed)
    XCTAssertEqual(model.failureCode, "SURFACE_ROUTE_UNAVAILABLE")
    XCTAssertNil(model.accessRoute)
    XCTAssertNil(model.egressRoute)
  }

  private func advance(
    _ model: C2NavigationDemoModel,
    until predicate: (C2NavigationDemoModel) -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    for _ in 0..<240 {
      if predicate(model) {
        return
      }
      model.advanceOneTickForTesting()
    }
    XCTFail(
      "Simulation did not reach the expected state from \(model.phase)",
      file: file,
      line: line
    )
  }
}

@MainActor
private final class C2TestLocationProvider:
  C2NavigationCurrentLocationProviding
{
  func currentCoordinate() async throws -> SurfaceCoordinate {
    SurfaceCoordinate(latitude: 35.68, longitude: 139.70)
  }
}

@MainActor
private final class C2TestPlaceResolver: C2NavigationPlaceResolving {
  func resolve(
    query: String,
    near _: SurfaceCoordinate?
  ) async throws -> C2NavigationResolvedPlace {
    C2NavigationResolvedPlace(
      title: query,
      coordinate: SurfaceCoordinate(latitude: 35.69, longitude: 139.76)
    )
  }
}

private struct C2ExplicitHighwayProvider: SurfaceRouteProvider {
  let metadata = SurfaceRouteProviderMetadata(
    id: "test.explicit-highway",
    adapterVersion: "1.0.0",
    providerVersion: "test",
    dataReviewStatus: .derivedFixtureReviewed
  )

  func routes(
    for request: SurfaceRouteRequest
  ) async -> SurfaceProviderResponse {
    .success([
      SurfaceRouteCandidate(
        id: "\(request.id).unsafe",
        providerID: metadata.id,
        coordinates: [
          request.origin,
          request.destinationAnchor.coordinate,
        ],
        steps: [],
        distanceMeters: 1_000,
        expectedTravelTimeSeconds: 120,
        hasHighways: true,
        hasTolls: false
      )
    ])
  }
}
