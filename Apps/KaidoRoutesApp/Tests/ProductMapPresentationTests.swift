import CoreLocation
import KaidoAppleAdapters
import KaidoDomain
import KaidoNavigation
import KaidoPresentation
import XCTest

@testable import KaidoRoutesApp

@MainActor
final class ProductMapPresentationTests: XCTestCase {
  func testProjectionPreferencePersistsAcrossPresentationModels() {
    let store = MemoryProductMapProjectionPreferenceStore()
    let first = ProductMapPresentationModel(store: store)

    XCTAssertEqual(first.projection, .geographic)

    first.select(.geographic)

    XCTAssertEqual(first.projection, .geographic)
    XCTAssertEqual(
      ProductMapPresentationModel(store: store).projection,
      .geographic
    )
  }

  func testGeographicPresentationUsesEveryReleasedRouteOccurrence()
    throws
  {
    let entry = try makeReleasedProductTestEntry()
    let corridor = entry.release.navigation.bundle.matcherCorridor

    let presentation = try XCTUnwrap(
      ProductGeographicMapPresentation.make(
        corridor: corridor,
        evidence: nil
      )
    )

    XCTAssertEqual(presentation.routePlanID, corridor.routePlanID)
    XCTAssertEqual(
      presentation.paths.map(\.id),
      corridor.occurrences.sorted { $0.index < $1.index }.map(\.id)
    )
    XCTAssertEqual(
      presentation.coordinateCount,
      corridor.occurrences.reduce(0) { count, occurrence in
        count
          + (corridor.edges.first {
            $0.id == occurrence.directedEdgeID
          }?.coordinates.count ?? 0)
      }
    )
    XCTAssertNotNil(presentation.startCoordinate)
    XCTAssertNotNil(presentation.finishCoordinate)
    XCTAssertNil(presentation.marker)
  }

  func testExactHighProgressPlacesTheMarkerOnTheGeographicRoute()
    throws
  {
    let fixture = try positionFixture(confidence: .high)
    let corridor = fixture.entry.release.navigation.bundle.matcherCorridor
    let estimate = MatcherEstimate(
      observationID: "test.position.geographic",
      estimatedAtMilliseconds: 1_000,
      directedEdgeID: fixture.occurrence.entityID,
      occurrenceID: fixture.occurrence.id,
      candidateEdgeIDs: [fixture.occurrence.entityID],
      confidence: .high,
      distanceMeters: 2,
      fractionAlongEdge: 0.5
    )
    let evidence = try XCTUnwrap(
      ProductTopologyPositionEvidence.admitted(
        estimate: estimate,
        snapshot: fixture.snapshot,
        routePlan: fixture.routePlan
      )
    )

    let presentation = try XCTUnwrap(
      ProductGeographicMapPresentation.make(
        corridor: corridor,
        evidence: evidence
      )
    )
    let marker = try XCTUnwrap(presentation.marker)

    XCTAssertEqual(marker.occurrenceID, fixture.occurrence.id)
    XCTAssertTrue((-90...90).contains(marker.coordinate.latitude))
    XCTAssertTrue((-180...180).contains(marker.coordinate.longitude))
  }

  func testTopologyPresentationPreservesReleasedOccurrenceOrderAndRepeats()
    throws
  {
    let entry = try makeReleasedProductTestEntry()
    let routePlan = entry.release.navigation.bundle.routePlan
    let projection = try RouteAtlasJourneyProjector.project(
      release: entry.release.routeAtlas
    )

    let presentation = ProductTopologyMapPresentation.make(
      projection: projection,
      evidence: nil,
      snapshot: nil
    )

    XCTAssertEqual(
      presentation.orderedOccurrences.map(\.occurrenceID),
      routePlan.occurrences.map(\.id)
    )
    XCTAssertEqual(
      presentation.orderedOccurrences.map(\.occurrenceIndex),
      Array(routePlan.occurrences.indices)
    )
    XCTAssertGreaterThan(presentation.repeatedOccurrenceCount, 0)
    XCTAssertTrue(
      presentation.orderedOccurrences.contains {
        $0.repeatOrdinal > 1 && $0.repeatCount > 1
      }
    )
  }

  func testTopologyGeometryPreservesEndpointsAndUsesOnlyOctilinearSegments() {
    let source = [
      RouteAtlasPoint(x: 0.1, y: 0.2),
      RouteAtlasPoint(x: 0.8, y: 0.5),
      RouteAtlasPoint(x: 0.7, y: 0.95),
    ]

    let result = ProductTopologyGeometry.octilinear(source)

    XCTAssertEqual(result.first, source.first)
    XCTAssertEqual(result.last, source.last)
    XCTAssertGreaterThan(result.count, source.count)
    for (start, end) in zip(result, result.dropFirst()) {
      let deltaX = abs(end.x - start.x)
      let deltaY = abs(end.y - start.y)
      XCTAssertTrue(
        deltaX < 0.000_001
          || deltaY < 0.000_001
          || abs(deltaX - deltaY) < 0.000_001
      )
    }
  }

  func testExactHighOccurrenceProgressProducesMeasuredTopologyMarker()
    throws
  {
    let fixture = try positionFixture(confidence: .high)
    let estimate = MatcherEstimate(
      observationID: "test.position.high",
      estimatedAtMilliseconds: 1_000,
      directedEdgeID: fixture.occurrence.entityID,
      occurrenceID: fixture.occurrence.id,
      candidateEdgeIDs: [fixture.occurrence.entityID],
      confidence: .high,
      distanceMeters: 2,
      fractionAlongEdge: 0.5
    )

    let evidence = ProductTopologyPositionEvidence.admitted(
      estimate: estimate,
      snapshot: fixture.snapshot,
      routePlan: fixture.routePlan
    )
    let presentation = ProductTopologyMapPresentation.make(
      projection: fixture.projection,
      evidence: evidence,
      snapshot: fixture.snapshot
    )

    let marker = try XCTUnwrap(evidence)
    XCTAssertEqual(marker.occurrenceID, fixture.occurrence.id)
    guard case .measured(let topologyMarker) = presentation.position else {
      return XCTFail("Expected exact HIGH evidence to produce a marker")
    }
    XCTAssertEqual(topologyMarker.occurrenceID, fixture.occurrence.id)
    XCTAssertEqual(topologyMarker.occurrenceIndex, fixture.occurrence.index)
  }

  func testLowLostAndIdentityDriftCannotProduceMeasuredMarker() throws {
    var low = try positionFixture(confidence: .low)
    let lowEstimate = MatcherEstimate(
      observationID: "test.position.low",
      estimatedAtMilliseconds: 1_000,
      directedEdgeID: low.occurrence.entityID,
      occurrenceID: low.occurrence.id,
      candidateEdgeIDs: [low.occurrence.entityID],
      confidence: .low,
      distanceMeters: 2,
      fractionAlongEdge: 0.5
    )

    XCTAssertNil(
      ProductTopologyPositionEvidence.admitted(
        estimate: lowEstimate,
        snapshot: low.snapshot,
        routePlan: low.routePlan
      )
    )
    XCTAssertEqual(
      ProductTopologyMapPresentation.make(
        projection: low.projection,
        evidence: nil,
        snapshot: low.snapshot
      ).position,
      .estimated(occurrenceID: low.occurrence.id)
    )

    low.snapshot.locationConfidence = .lost
    XCTAssertEqual(
      ProductTopologyMapPresentation.make(
        projection: low.projection,
        evidence: nil,
        snapshot: low.snapshot
      ).position,
      .unavailable
    )

    var high = try positionFixture(confidence: .high)
    high.snapshot.currentOccurrenceIndex = high.occurrence.index + 1
    let driftedEstimate = MatcherEstimate(
      observationID: "test.position.drift",
      estimatedAtMilliseconds: 1_000,
      directedEdgeID: high.occurrence.entityID,
      occurrenceID: high.occurrence.id,
      candidateEdgeIDs: [high.occurrence.entityID],
      confidence: .high,
      distanceMeters: 2,
      fractionAlongEdge: 0.5
    )
    XCTAssertNil(
      ProductTopologyPositionEvidence.admitted(
        estimate: driftedEstimate,
        snapshot: high.snapshot,
        routePlan: high.routePlan
      )
    )
  }

  func testProjectionChangeDoesNotMutateRouteOrRuntimeProgress()
    async throws
  {
    let store = MemoryProductMapProjectionPreferenceStore()
    let mapModel = ProductMapPresentationModel(store: store)
    let runtime = try ProductNavigationRuntimeModel(
      sourceEvidenceProvider: FixedProductMapSourceEvidenceProvider(),
      speechOutput: SilentProductMapSpeechOutput()
    )
    await runtime.activate()
    let routePlanID = runtime.routePlanID
    let before = try XCTUnwrap(runtime.snapshot)

    mapModel.select(.geographic)
    mapModel.select(.topology)

    XCTAssertEqual(runtime.routePlanID, routePlanID)
    XCTAssertEqual(runtime.snapshot, before)
  }

  private func positionFixture(
    confidence: LocationConfidence
  ) throws -> PositionFixture {
    let entry = try makeReleasedProductTestEntry()
    let routePlan = entry.release.navigation.bundle.routePlan
    let occurrence = try XCTUnwrap(
      routePlan.occurrences.first { $0.kind == .edge }
    )
    let projection = try RouteAtlasJourneyProjector.project(
      release: entry.release.routeAtlas
    )
    var snapshot = NavigationSnapshot(
      journeyPhase: .strictRoute,
      activeRoutePlanID: routePlan.id,
      currentOccurrenceID: occurrence.id,
      locationConfidence: confidence
    )
    snapshot.currentOccurrenceIndex = occurrence.index
    snapshot.routeCandidateResolution = .resolved
    snapshot.markerStyle = "MEASURED"
    return PositionFixture(
      entry: entry,
      routePlan: routePlan,
      occurrence: occurrence,
      projection: projection,
      snapshot: snapshot
    )
  }
}

@MainActor
private final class MemoryProductMapProjectionPreferenceStore:
  ProductMapProjectionPreferenceStoring
{
  private var value: ProductMapProjection?

  func projection() -> ProductMapProjection? {
    value
  }

  func setProjection(_ projection: ProductMapProjection) {
    value = projection
  }
}

private struct PositionFixture {
  let entry: BundledProductReleaseEntry
  let routePlan: RoutePlan
  let occurrence: RouteOccurrence
  let projection: RouteAtlasJourneyProjection
  var snapshot: NavigationSnapshot
}

private struct FixedProductMapSourceEvidenceProvider:
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

@MainActor
private final class SilentProductMapSpeechOutput: GuidanceSpeechOutput {
  var eventHandler: ((GuidanceSpeechOutputEvent) -> Void)?
  var selectedVoiceProfile: GuidanceSpeechVoiceProfile?

  func speak(_ command: GuidanceSpeechCommand) throws {
    eventHandler?(.didStart(command.identity))
  }

  func stop() {}
}
