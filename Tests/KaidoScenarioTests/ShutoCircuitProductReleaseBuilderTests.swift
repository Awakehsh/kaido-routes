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
    #expect(release.navigation.bundle.releasedGuidance.count == 10)
    // The Edobashi detour leaves through the Hakozaki rotary, a movement no
    // released binding covers, so C1 releases no recovery: a wrong turn
    // there is the unavailable-recovery state, never an unreviewed detour.
    #expect(release.navigation.bundle.runtimePolicy.recoveryCandidates.isEmpty)
    let assets = try ShutoPlannedRouteRuntimeCompiler.compile(
      database: database,
      route: route
    )
    let edobashi = try #require(
      assets.recoveryCandidates.first {
        $0.triggerDirectedEdgeID == "osm.44804643.0.forward"
      }
    )
    #expect(
      ShutoPlannedRouteRuntimeCompiler.coveredRecoveryCandidates(
        [edobashi],
        route: route,
        database: database
      ).isEmpty
    )
  }

  @Test("every released recovery crosses only released junction movements")
  func releasedRecoveriesAreCovered() throws {
    let database = try loadDatabase()
    typealias Builder = ShutoCircuitProductReleaseBuilder
    let products = [
      (try Builder.plannedRoute(database: database), try Builder.buildArtifact(database: database)),
      (
        try Builder.plannedWanganRoute(database: database),
        try Builder.buildWanganArtifact(database: database)
      ),
      (try Builder.plannedC2Route(database: database), try Builder.buildC2Artifact(database: database)),
      (
        try Builder.plannedDaikokuRoute(database: database),
        try Builder.buildDaikokuArtifact(database: database)
      ),
      (
        try Builder.plannedScenicRoute(database: database),
        try Builder.buildScenicArtifact(database: database)
      ),
    ]
    for (route, artifact) in products {
      let release = try KaidoProductRelease(artifact: artifact)
      let released = release.navigation.bundle.runtimePolicy.recoveryCandidates
      #expect(
        ShutoPlannedRouteRuntimeCompiler.coveredRecoveryCandidates(
          released,
          route: route,
          database: database
        ) == released,
        "\(route.routePlan.id)"
      )
    }
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
    // Arrival in the PA has no return-junction or exit cue.
    #expect(release.navigation.bundle.releasedGuidance.count == 16)
    // The parking area is driven, and driving it is recorded as such.
    #expect(
      release.navigation.bundle.routePlan.occurrences.contains {
        $0.kind == .paVisit && $0.parkingAreaID == "shuto.pa.daikoku"
      }
    )
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
      "shutoko.entry.shuto.ic.b.chidoricho.approach.2026-09-07"
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
    #expect(release.navigation.bundle.releasedGuidance.count == 26)
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
    #expect(release.navigation.bundle.releasedGuidance.count == 17)
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
    #expect(release.navigation.bundle.releasedGuidance.count == 20)
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

  @Test("on-demand product build returns its exact compiled runtime assets")
  func buildsProductAndRuntimeAssetsTogether() throws {
    let database = try loadDatabase()
    let route = try ShutoRoutePlanner(database: database).plan(
      entryFacilityID: "shuto.ic.b.urayasu",
      exitFacilityID: "shuto.ic.9.fukudumi"
    )
    let context = try ShutoPlannedRouteRuntimeCompiler.NetworkContext(
      database: database
    )

    let product =
      try ShutoCircuitProductReleaseBuilder
      .buildPlannedRouteProduct(context: context, route: route)

    #expect(product.release.navigation.bundle.routePlan == route.routePlan)
    #expect(product.runtimeAssets.routePlan == route.routePlan)
    let runtimeEdgeIDs = Set(
      product.runtimeAssets.matcherCorridor.edges.map(\.id)
    )
    let releasedEdgeIDs = Set(
      product.release.navigation.bundle.matcherCorridor.edges.map(\.id)
    )
    #expect(runtimeEdgeIDs.isSubset(of: releasedEdgeIDs))
    #expect(
      product.runtimeAssets.matcherCorridor.occurrences
        == product.release.navigation.bundle.matcherCorridor.occurrences
    )
    #expect(
      product.runtimeAssets.decisionZones
        == product.release.navigation.bundle.decisionZones
    )
  }

  /// The Oi JCT Bayshore-eastbound movements were reviewed on 2026-09-08,
  /// after the bundled releases' date. A route through them is authored on
  /// the device, so its release is dated by that evidence; before, it was
  /// refused as evidence after release and the route lost live navigation.
  @Test("an on-device release through later evidence is dated by it")
  func datesOnDeviceReleaseByItsNewestEvidence() throws {
    let database = try loadDatabase()
    let planner = try ShutoRoutePlanner(database: database)
    let context = try ShutoPlannedRouteRuntimeCompiler.NetworkContext(
      database: database
    )
    let facilities = database.directionalFacilities.sorted {
      $0.facilityID < $1.facilityID
    }
    let route = try #require(
      facilities.filter(\.canEnter).lazy.flatMap { entry in
        facilities.filter(\.canExit).lazy.compactMap { exit in
          try? planner.plan(
            entryFacilityID: entry.facilityID,
            exitFacilityID: exit.facilityID
          )
        }
      }.first { route in
        route.edges.contains { $0.edgeID == "osm.1059139534.2.forward" }
      }
    )

    let release =
      try ShutoCircuitProductReleaseBuilder
      .buildPlannedRouteRelease(context: context, route: route)

    #expect(release.releasedAt == "2026-09-08T00:00:00+09:00")
    #expect(release.navigation.releasedAt == "2026-09-08T00:00:00+09:00")
    #expect(release.releaseID.hasSuffix(".2026-09-07"))
    #expect(release.foregroundLiveInputAuthority != nil)
    let bundled = try KaidoProductRelease(
      artifact: ShutoCircuitProductReleaseBuilder.buildWanganArtifact(
        database: database
      )
    )
    #expect(bundled.releasedAt == ShutoCircuitProductReleaseBuilder.releasedAt)
  }

  @Test("a direct route without a later safe rejoin still builds honestly")
  func buildsDirectRouteWithoutInventingRecovery() throws {
    let database = try loadDatabase()
    let planner = try ShutoRoutePlanner(database: database)
    let context = try ShutoPlannedRouteRuntimeCompiler.NetworkContext(
      database: database
    )
    let entries = database.directionalFacilities.filter(\.canEnter).sorted {
      $0.facilityID < $1.facilityID
    }
    let exits = database.directionalFacilities.filter(\.canExit).sorted {
      $0.facilityID < $1.facilityID
    }

    for entry in entries {
      for exit in exits where exit.facilityID != entry.facilityID {
        for preference in ShutoRoutePreference.allCases {
          guard
            let route = try? planner.plan(
              entryFacilityID: entry.facilityID,
              exitFacilityID: exit.facilityID,
              preference: preference
            ),
            try context.compile(route: route).recoveryCandidates.isEmpty
          else { continue }
          let release =
            try ShutoCircuitProductReleaseBuilder
            .buildPlannedRouteRelease(context: context, route: route)

          #expect(release.foregroundLiveInputAuthority != nil)
          #expect(release.navigation.bundle.routePlan == route.routePlan)
          #expect(
            release.navigation.bundle.runtimePolicy.recoveryCandidates.isEmpty
          )
          return
        }
      }
    }
    Issue.record("Expected at least one direct route without a safe rejoin")
  }

  @Test("exact C1 outer circuit builds on demand")
  func buildsC1OuterForegroundReleaseOnDemand() throws {
    let database = try loadDatabase()
    let route = try ShutoRoutePlanner(database: database).planCircuit(
      circuit: .c1Outer,
      entryFacilityID: "shuto.ic.c1.kyoubashi",
      exitFacilityID: "shuto.ic.c1.ginza",
      laps: 1
    )
    let artifact =
      try ShutoCircuitProductReleaseBuilder
      .buildPlannedRouteArtifact(database: database, route: route)
    let release = try KaidoProductRelease(artifact: artifact)

    #expect(release.foregroundLiveInputAuthority != nil)
    #expect(release.navigation.bundle.routePlan == route.routePlan)
    #expect(release.navigation.bundle.releasedGuidance.filter { $0.frameTemplate.stage == .commit }.count == 6)
    #expect(release.navigation.bundle.releasedGuidance.contains { $0.frameTemplate.stage == .prepare })
    #expect(
      try ShutoPlannedRouteRuntimeCompiler.compile(
        database: database,
        route: route
      ).liveReleaseCoverage.missingGuidanceDecisionCount == 0
    )
  }

  @Test("tracked foreground releases reproduce the current builders")
  func trackedForegroundReleasesAreCurrent() throws {
    let database = try loadDatabase()
    let releases = [
      (
        appResource: "c1-inner-shibakoen-shiodome-product-release.json",
        trackedResource:
          "c1-inner-shibakoen-to-shiodome-product-release.json",
        artifact: try ShutoCircuitProductReleaseBuilder.buildArtifact(
          database: database
        )
      ),
      (
        appResource:
          "wangan-westbound-chidoricho-daikoku-pa-product-release.json",
        trackedResource:
          "wangan-westbound-chidoricho-daikoku-pa-product-release.json",
        artifact:
          try ShutoCircuitProductReleaseBuilder.buildWanganArtifact(
            database: database
          )
      ),
      (
        appResource:
          "c2-inner-oujiminami-itabashihoncho-product-release.json",
        trackedResource:
          "c2-inner-oujiminami-itabashihoncho-product-release.json",
        artifact: try ShutoCircuitProductReleaseBuilder.buildC2Artifact(
          database: database
        )
      ),
      (
        appResource:
          "daikoku-yokohama-wangankanpachi-daikoku-pa-product-release.json",
        trackedResource:
          "daikoku-yokohama-wangankanpachi-daikoku-pa-product-release.json",
        artifact:
          try ShutoCircuitProductReleaseBuilder.buildDaikokuArtifact(
            database: database
          )
      ),
      (
        appResource:
          "scenic-harumi-daikoku-pa-product-release.json",
        trackedResource:
          "scenic-harumi-daikoku-pa-product-release.json",
        artifact:
          try ShutoCircuitProductReleaseBuilder.buildScenicArtifact(
            database: database
          )
      ),
    ]
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()

    for release in releases {
      let encoded = try KaidoProductReleaseArtifactCodec.encode(
        release.artifact
      )
      let tracked = try Data(
        contentsOf:
          repositoryRoot
          .appendingPathComponent("data/product/releases")
          .appendingPathComponent(release.trackedResource)
      )
      let bundled = try Data(
        contentsOf:
          repositoryRoot
          .appendingPathComponent("Apps/KaidoRoutesApp/Resources")
          .appendingPathComponent(release.appResource)
      )

      #expect(tracked == encoded)
      #expect(bundled == encoded)
    }
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
