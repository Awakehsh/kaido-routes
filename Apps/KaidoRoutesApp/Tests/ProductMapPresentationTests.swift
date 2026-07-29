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

  func testReleasedK7TopologyFacilitiesAreBoundToExactAtlasPoints()
    throws
  {
    let catalog = try BundledProductReleaseCatalogLoader.bundledPreview()
    let entry = try XCTUnwrap(
      catalog.foregroundNavigationEntries.first
    )
    let facilities = try XCTUnwrap(
      ProductTopologyFacilityPresentation.make(
        release: entry.release
      )
    )

    XCTAssertEqual(facilities.routeShields, ["K7"])
    XCTAssertEqual(facilities.routeSections.count, 1)
    XCTAssertEqual(facilities.routeSections.first?.routeShield, "K7")
    XCTAssertEqual(facilities.routeSections.first?.style, .primary)
    XCTAssertEqual(
      facilities.routeSections.first?.occurrenceIDs,
      Set(entry.release.navigation.bundle.routePlan.occurrences.map(\.id))
    )
    XCTAssertEqual(facilities.entranceCount, 1)
    XCTAssertEqual(facilities.interchangeCount, 0)
    XCTAssertEqual(facilities.junctionCount, 2)
    XCTAssertEqual(facilities.parkingAreaCount, 0)
    XCTAssertEqual(facilities.exitCount, 1)
    XCTAssertEqual(
      facilities.landmarks.map(\.kind),
      [.entrance, .junction, .junction, .exit]
    )
    XCTAssertEqual(
      facilities.landmarks.map(\.id),
      [
        "shutoko.entrance.yokohama-aoba.k7-northwest.up",
        "shutoko.occurrence.k7-navigation.aoba-to-kohoku.shared-branch.1",
        "shutoko.occurrence.k7-navigation.aoba-to-kohoku.exit-branch.3",
        "shutoko.exit.yokohama-kohoku.k7-northwest.up",
      ]
    )
    XCTAssertEqual(
      facilities.landmarks.map(\.point),
      [
        RouteAtlasPoint(x: 0.12, y: 0.3),
        RouteAtlasPoint(x: 0.68, y: 0.6),
        RouteAtlasPoint(x: 0.7, y: 0.78),
        RouteAtlasPoint(x: 0.78, y: 0.84),
      ]
    )
    XCTAssertEqual(
      facilities.landmarks.compactMap {
        $0.title.value(for: .simplifiedChinese)
      },
      [
        "横滨青叶入口（K7 上行）",
        "横滨港北 JCT 第三京滨・出口分岔",
        "横滨港北出口分岔",
        "驶向横滨港北出口",
      ]
    )
  }

  func testTopologyFacilitiesPreserveRepeatedDecisionOccurrences()
    throws
  {
    let entry = try makeReleasedProductTestEntry()
    let facilities = try XCTUnwrap(
      ProductTopologyFacilityPresentation.make(
        release: entry.release
      )
    )

    XCTAssertEqual(facilities.junctionCount, 3)
    XCTAssertEqual(
      facilities.landmarks.map(\.id),
      [
        "test.entrance",
        "test.occurrence.loop-movement-1",
        "test.occurrence.loop-movement-2",
        "test.occurrence.exit-movement",
        "test.exit",
      ]
    )
    XCTAssertEqual(
      facilities.landmarks.filter { $0.kind == .junction }
        .map(\.occurrenceIndex),
      [1, 3, 5]
    )
  }

  func testC2CompletedRouteDemoShowsTheC2AndBComposition() throws {
    let presentation = C2CompletedRouteDemoView.previewPresentation
    let facilities = try XCTUnwrap(presentation.facilities)

    XCTAssertEqual(facilities.routeShields, ["C2", "B"])
    XCTAssertEqual(
      facilities.routeSections.map(\.style),
      [.primary, .connector]
    )
    XCTAssertEqual(facilities.entranceCount, 1)
    XCTAssertEqual(facilities.interchangeCount, 20)
    XCTAssertEqual(facilities.junctionCount, 13)
    XCTAssertEqual(facilities.parkingAreaCount, 1)
    XCTAssertEqual(facilities.exitCount, 1)
    XCTAssertEqual(
      facilities.landmarks.map(\.kind).filter {
        $0 == .parkingArea
      }.count,
      1
    )
    XCTAssertEqual(
      facilities.landmarks
        .first { $0.kind == .parkingArea }?
        .title.value(for: .simplifiedChinese),
      "大井 PA（西行 · 本路线不进入）"
    )
    XCTAssertEqual(
      facilities.landmarks.filter { $0.kind == .interchange }.count,
      20
    )
    XCTAssertEqual(
      facilities.landmarks
        .filter { $0.kind == .junction }
        .map(\.id),
      [
        "demo.c2.junction.nishi-shinjuku",
        "demo.c2.junction.kumanocho",
        "demo.c2.junction.itabashi",
        "demo.c2.junction.kohoku",
        "demo.c2.junction.kosuge",
        "demo.c2.junction.horikiri",
        "demo.c2.junction.komatsugawa",
        "demo.c2.junction.kasai",
        "demo.c2.junction.tatsumi",
        "demo.c2.junction.shinonome",
        "demo.c2.junction.ariake",
        "demo.c2.junction.oi",
        "demo.c2.junction.ohashi",
      ]
    )
    XCTAssertEqual(
      facilities.landmarks
        .filter { $0.kind == .interchange }
        .compactMap { $0.title.value(for: .simplifiedChinese) },
      [
        "中野長者橋 IC · 入口",
        "西池袋 IC · 出口",
        "高松 IC · 入口",
        "新板橋 IC · 出口",
        "王子南 IC · 出口",
        "王子北 IC · 入口",
        "扇大橋 IC · 出入口",
        "千住新橋 IC · 出入口",
        "小菅 IC · 入口",
        "四つ木 IC · 出入口",
        "平井大橋 IC · 出口",
        "船堀橋 IC · 入口",
        "清新町 IC · 出口",
        "葛西 IC · 出入口",
        "新木場 IC · 出入口",
        "有明 IC · 出口",
        "临海副都心 IC · 入口",
        "大井 IC · 出口",
        "中環大井南 IC · 入口",
        "五反田 IC · 入口",
      ]
    )

    let junctionInset = C2CompletedRouteDemoView.previewJunctionInset
    XCTAssertEqual(junctionInset.selectedBranch, .right)
    XCTAssertNil(junctionInset.distanceMeters)
    XCTAssertEqual(junctionInset.routeShield, "B")
    XCTAssertEqual(junctionInset.japaneseSignText, "9  横浜")

    XCTAssertEqual(presentation.orderedOccurrences.count, 16)
    XCTAssertEqual(
      facilities.routeSections
        .first { $0.routeShield == "B" }?
        .occurrenceIDs,
      Set((9...12).map { "demo.c2.occurrence.\($0)" })
    )
    XCTAssertEqual(
      facilities.landmarks
        .first { $0.id == "demo.c2.junction.oi" }?
        .occurrenceIndex,
      13
    )

    let sectionOccurrenceIDs = Set(
      facilities.routeSections.flatMap(\.occurrenceIDs)
    )
    XCTAssertEqual(
      sectionOccurrenceIDs,
      Set(presentation.orderedOccurrences.map(\.occurrenceID))
    )
    XCTAssertEqual(
      presentation.orderedOccurrences
        .filter(\.isRepeatedTraversal)
        .map(\.repeatOrdinal),
      [1, 2]
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

  func testReleasedK7SimulationProjectsTwoTransientLeftJunctionInsets()
    async throws
  {
    let catalog = try BundledProductReleaseCatalogLoader.bundledPreview()
    let entry = try XCTUnwrap(
      catalog.foregroundNavigationEntries.first
    )
    let runtime = try ProductNavigationRuntimeModel(
      releasedEntry: entry,
      speechOutput: SilentProductMapSpeechOutput(),
      languageSelectionProvider: {
        NavigationLanguageSelection(
          interfaceLocale: .simplifiedChinese,
          guidanceVoiceLocale: .japanese
        )
      }
    )
    await runtime.activate()

    var insetsByDecisionZone: [String: ProductJunctionInsetPresentation] = [:]
    XCTAssertNil(
      runtime.presentationProjection.flatMap {
        ProductJunctionInsetPresentation(
          $0.iPhone,
          navigationSnapshot: runtime.snapshot
        )
      }
    )
    while runtime.simulationStatus?.state != .completed {
      await runtime.stepNavigationSimulation()
      if let surface = runtime.presentationProjection?.iPhone,
        let inset = ProductJunctionInsetPresentation(
          surface,
          navigationSnapshot: runtime.snapshot
        )
      {
        insetsByDecisionZone[inset.decisionZoneID] = inset
      }
    }

    XCTAssertEqual(
      Set(insetsByDecisionZone.keys),
      [
        "shutoko.decision-zone.kohoku.k7-up-shared-branch.v1",
        "shutoko.decision-zone.kohoku.exit-left-branch.v1",
      ]
    )
    XCTAssertEqual(
      Set(insetsByDecisionZone.values.map(\.selectedBranch)),
      [.left]
    )
    XCTAssertEqual(
      Set(insetsByDecisionZone.values.map(\.japaneseSignText)),
      ["第三京浜・出口へ", "出口へ"]
    )
    XCTAssertLessThanOrEqual(
      try XCTUnwrap(
        XCTUnwrap(
          insetsByDecisionZone[
            "shutoko.decision-zone.kohoku.k7-up-shared-branch.v1"
          ]
        ).distanceMeters
      ),
      400
    )
    XCTAssertLessThanOrEqual(
      try XCTUnwrap(
        XCTUnwrap(
          insetsByDecisionZone[
            "shutoko.decision-zone.kohoku.exit-left-branch.v1"
          ]
        ).distanceMeters
      ),
      250
    )
    XCTAssertNil(runtime.presentationProjection)
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
