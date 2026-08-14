import Foundation
import KaidoNavigation
import KaidoRouting
import Testing

@Suite("C1 foreground product release")
struct ShutoCircuitProductReleaseBuilderTests {
  @Test("exact C1 circuit builds one foreground navigation authority")
  func buildsExactForegroundRelease() throws {
    let databaseURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("data")
      .appendingPathComponent("route-atlas")
      .appendingPathComponent("osm-derived")
      .appendingPathComponent("shuto-whole-network-20260804.json")
    let database = try JSONDecoder().decode(
      ShutoNetworkDatabase.self,
      from: Data(contentsOf: databaseURL)
    )
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
}
