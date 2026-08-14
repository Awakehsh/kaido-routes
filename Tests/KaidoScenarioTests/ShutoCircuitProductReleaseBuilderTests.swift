import Foundation
import KaidoNavigation
import KaidoRouting
import Testing

@Suite("Whole-Shuto foreground product releases")
struct ShutoCircuitProductReleaseBuilderTests {
  @Test("exact C1 circuit builds one foreground navigation authority")
  func buildsExactForegroundRelease() throws {
    let database = try loadDatabase()
    let artifact = try ShutoCircuitProductReleaseBuilder.buildArtifact(
      database: database
    )
    let release = try KaidoProductRelease(artifact: artifact)
    let route = try ShutoCircuitProductReleaseBuilder.plannedRoute(
      database: database
    )

    #expect(release.foregroundLiveInputAuthority != nil)
    #expect(release.navigation.bundle.routePlan == route.routePlan)
    #expect(
      release.navigation.bundle.routePlan.occurrences.count
        == route.edges.count
    )
    #expect(release.navigation.bundle.releasedGuidance.count == 5)
    #expect(release.navigation.bundle.runtimePolicy.recoveryCandidates.count == 1)
    #expect(
      release.navigation.bundle.runtimePolicy.recoveryCandidates[0]
        .triggerDirectedEdgeID == "osm.44804643.0.forward"
    )
    #expect(
      release.navigation.bundle.matcherCorridor.edges.contains {
        $0.id == "osm.44804643.0.forward"
      }
    )
  }

  @Test("Bayshore westbound route builds a second foreground authority")
  func buildsWanganForegroundRelease() throws {
    let database = try loadDatabase()
    let artifact = try ShutoCircuitProductReleaseBuilder
      .buildWanganArtifact(database: database)
    let release = try KaidoProductRelease(artifact: artifact)
    let route = try ShutoCircuitProductReleaseBuilder.plannedWanganRoute(
      database: database
    )

    #expect(release.foregroundLiveInputAuthority != nil)
    #expect(release.navigation.bundle.routePlan == route.routePlan)
    #expect(release.navigation.bundle.releasedGuidance.count == 8)
    #expect(
      release.navigation.bundle.runtimePolicy.recoveryCandidates.count == 1
    )
    #expect(
      release.navigation.bundle.releasedGuidance.contains {
        $0.frameTemplate.presentationSource.japaneseSignText
          == "空港中央・大黒ふ頭"
      }
    )
    let approachID =
      "shutoko.entry.shuto.ic.b.chidoricho.approach.2026-08-15"
    #expect(
      release.navigation.bundle.runtimePolicy.entryTransition
        .directedEdgeIDs.first == approachID
    )
    #expect(
      release.navigation.bundle.matcherCorridor.edges.contains {
        $0.id == approachID
      }
    )
    #expect(
      try ShutoPlannedRouteRuntimeCompiler.compile(
        database: database,
        route: route
      ).liveReleaseCoverage.missingGuidanceDecisionCount == 0
    )
  }

  @Test("C2 Inner and Bayshore circuit builds one exact foreground authority")
  func buildsC2ForegroundRelease() throws {
    let database = try loadDatabase()
    let artifact = try ShutoCircuitProductReleaseBuilder
      .buildC2Artifact(database: database)
    let release = try KaidoProductRelease(artifact: artifact)
    let route = try ShutoCircuitProductReleaseBuilder.plannedC2Route(
      database: database
    )

    #expect(release.foregroundLiveInputAuthority != nil)
    #expect(release.navigation.bundle.routePlan == route.routePlan)
    #expect(release.navigation.bundle.releasedGuidance.count == 22)
    #expect(
      release.navigation.bundle.runtimePolicy.recoveryCandidates.count == 1
    )
    #expect(
      try ShutoPlannedRouteRuntimeCompiler.compile(
        database: database,
        route: route
      ).liveReleaseCoverage.missingGuidanceDecisionCount == 0
    )
    #expect(
      release.navigation.bundle.releasedGuidance.contains {
        $0.frameTemplate.presentationSource.japaneseSignText
          == "東北道・大宮"
      }
    )
    #expect(
      release.navigation.bundle.releasedGuidance.contains {
        $0.frameTemplate.presentationSource.japaneseSignText
          == "中央道・東名"
      }
    )
  }

  private func loadDatabase() throws -> ShutoNetworkDatabase {
    let databaseURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("data")
      .appendingPathComponent("route-atlas")
      .appendingPathComponent("osm-derived")
      .appendingPathComponent("shuto-whole-network-20260804.json")
    return try JSONDecoder().decode(
      ShutoNetworkDatabase.self,
      from: Data(contentsOf: databaseURL)
    )
  }
}
