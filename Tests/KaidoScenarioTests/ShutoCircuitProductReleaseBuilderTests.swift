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
    let artifact =
      try ShutoCircuitProductReleaseBuilder
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
    let artifact =
      try ShutoCircuitProductReleaseBuilder
      .buildC2Artifact(database: database)
    let release = try KaidoProductRelease(artifact: artifact)
    let route = try ShutoCircuitProductReleaseBuilder.plannedC2Route(
      database: database
    )

    #expect(release.foregroundLiveInputAuthority != nil)
    #expect(release.navigation.bundle.routePlan == route.routePlan)
    #expect(release.navigation.bundle.releasedGuidance.count == 24)
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
          == "東北道・常磐道"
      }
    )
    #expect(
      release.navigation.bundle.releasedGuidance.contains {
        $0.frameTemplate.presentationSource.japaneseSignText
          == "中央道・東名"
      }
    )
  }

  @Test("Daikoku Yokohama circuit builds foreground authority")
  func buildsDaikokuForegroundRelease() throws {
    let database = try loadDatabase()
    let artifact =
      try ShutoCircuitProductReleaseBuilder
      .buildDaikokuArtifact(database: database)
    let release = try KaidoProductRelease(artifact: artifact)
    let route =
      try ShutoCircuitProductReleaseBuilder
      .plannedDaikokuRoute(database: database)

    #expect(release.foregroundLiveInputAuthority != nil)
    #expect(release.navigation.bundle.routePlan == route.routePlan)
    #expect(release.navigation.bundle.releasedGuidance.count == 8)
    #expect(
      try ShutoPlannedRouteRuntimeCompiler.compile(
        database: database,
        route: route
      ).liveReleaseCoverage.missingGuidanceDecisionCount == 0
    )
  }

  @Test("Yokohama scenic tour builds foreground authority")
  func buildsScenicForegroundRelease() throws {
    let database = try loadDatabase()
    let artifact =
      try ShutoCircuitProductReleaseBuilder
      .buildScenicArtifact(database: database)
    let release = try KaidoProductRelease(artifact: artifact)
    let route =
      try ShutoCircuitProductReleaseBuilder
      .plannedScenicRoute(database: database)

    #expect(release.foregroundLiveInputAuthority != nil)
    #expect(release.navigation.bundle.routePlan == route.routePlan)
    #expect(release.navigation.bundle.releasedGuidance.count == 10)
    #expect(
      try ShutoPlannedRouteRuntimeCompiler.compile(
        database: database,
        route: route
      ).liveReleaseCoverage.missingGuidanceDecisionCount == 0
    )
  }

  @Test("an exact custom route with complete guidance builds on demand")
  func buildsExactCustomForegroundRelease() throws {
    let database = try loadDatabase()
    let route = try ShutoRoutePlanner(database: database).plan(
      entryFacilityID: "shuto.ic.b.urayasu",
      exitFacilityID: "shuto.ic.9.fukudumi"
    )
    let artifact =
      try ShutoCircuitProductReleaseBuilder
      .buildPlannedRouteArtifact(database: database, route: route)
    let release = try KaidoProductRelease(artifact: artifact)

    #expect(release.foregroundLiveInputAuthority != nil)
    #expect(release.navigation.bundle.routePlan == route.routePlan)
    #expect(release.releaseID.hasPrefix("shutoko.product.route-"))
    #expect(
      try ShutoPlannedRouteRuntimeCompiler.compile(
        database: database,
        route: route
      ).liveReleaseCoverage.missingGuidanceDecisionCount == 0
    )
  }

  @Test("exact C1 outer circuit builds on demand")
  func buildsC1OuterForegroundReleaseOnDemand() throws {
    let database = try loadDatabase()
    let route = try ShutoRoutePlanner(database: database).planCircuit(
      circuit: .c1Outer,
      entryFacilityID: "shuto.ic.c1.kyoubashi",
      exitFacilityID: "shuto.ic.c1.shintomicho",
      laps: 1
    )
    let artifact =
      try ShutoCircuitProductReleaseBuilder
      .buildPlannedRouteArtifact(database: database, route: route)
    let release = try KaidoProductRelease(artifact: artifact)

    #expect(release.foregroundLiveInputAuthority != nil)
    #expect(release.navigation.bundle.routePlan == route.routePlan)
    #expect(release.navigation.bundle.releasedGuidance.count == 6)
    #expect(
      try ShutoPlannedRouteRuntimeCompiler.compile(
        database: database,
        route: route
      ).liveReleaseCoverage.missingGuidanceDecisionCount == 0
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
