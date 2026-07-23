import Foundation
import KaidoNavigation
import Testing

@Test("Route Atlas context accepts only coherent source-bound non-navigation geometry")
func routeAtlasContextAcceptsCoherentContextOnlyGeometry() throws {
  let fixture = routeAtlasContextFixture()
  let bundle = try RouteAtlasContextBundle(
    source: fixture.source,
    definition: fixture.definition
  )

  #expect(bundle.definition.navigationRole == .contextOnly)
  #expect(bundle.definition.coverage.pathCount == 1)

  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  let encoded = try encoder.encode(bundle.definition)
  let decoded = try JSONDecoder().decode(
    RouteAtlasContextDefinition.self,
    from: encoded
  )
  #expect(decoded == fixture.definition)
}

@Test("Route Atlas context rejects promotion to navigation authority")
func routeAtlasContextRejectsNavigationAuthority() {
  let fixture = routeAtlasContextFixture(navigationRole: .navigationAuthority)

  do {
    _ = try RouteAtlasContextBundle(
      source: fixture.source,
      definition: fixture.definition
    )
    Issue.record("Expected navigation authority to block context release")
  } catch RouteAtlasContextError.invalid(let issues) {
    #expect(issues.contains(.contextRoleMismatch))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Route Atlas context rejects untraceable source evidence")
func routeAtlasContextRejectsSourceEvidenceDrift() {
  let fixture = routeAtlasContextFixture(
    archiveSHA256: "not-the-reviewed-archive",
    licenceIdentifier: "UNKNOWN"
  )

  do {
    _ = try RouteAtlasContextBundle(
      source: fixture.source,
      definition: fixture.definition
    )
    Issue.record("Expected source evidence drift to block context release")
  } catch RouteAtlasContextError.invalid(let issues) {
    #expect(issues.contains(.invalidSourceArchiveChecksum))
    #expect(issues.contains(.unsupportedSourceLicence))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Route Atlas context rejects geometry and declared coverage drift")
func routeAtlasContextRejectsGeometryAndCoverageDrift() {
  let fixture = routeAtlasContextFixture(
    coverage: RouteAtlasContextCoverage(
      sourceFeatureCount: 1,
      pathCount: 2,
      vertexCount: 3,
      routeNameCount: 1
    ),
    points: [
      RouteAtlasContextPoint(x: 0.2, y: 0.8),
      RouteAtlasContextPoint(x: 1.2, y: 0.2),
    ]
  )

  do {
    _ = try RouteAtlasContextBundle(
      source: fixture.source,
      definition: fixture.definition
    )
    Issue.record("Expected context geometry and coverage drift to block release")
  } catch RouteAtlasContextError.invalid(let issues) {
    #expect(issues.contains(.invalidContextPoint("test.context-path.001.0")))
    #expect(issues.contains(.pathCountMismatch))
    #expect(issues.contains(.vertexCountMismatch))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test("Route Atlas context rejects source and projection CRS drift")
func routeAtlasContextRejectsCRSDrift() {
  let fixture = routeAtlasContextFixture(
    sourceCRS: .jgd2011,
    projectionCRS: .wgs84
  )

  do {
    _ = try RouteAtlasContextBundle(
      source: fixture.source,
      definition: fixture.definition
    )
    Issue.record("Expected source and projection CRS drift to block release")
  } catch RouteAtlasContextError.invalid(let issues) {
    #expect(issues.contains(.sourceCRSMismatch))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

private struct RouteAtlasContextFixture {
  let source: RouteAtlasContextSource
  let definition: RouteAtlasContextDefinition
}

private func routeAtlasContextFixture(
  navigationRole: RouteAtlasContextNavigationRole = .contextOnly,
  archiveSHA256: String =
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  licenceIdentifier: String = "CC-BY-4.0",
  sourceCRS: RouteAtlasContextSourceCRS = .wgs84,
  projectionCRS: RouteAtlasContextSourceCRS? = nil,
  coverage: RouteAtlasContextCoverage? = nil,
  points: [RouteAtlasContextPoint] = [
    RouteAtlasContextPoint(x: 0.2, y: 0.8),
    RouteAtlasContextPoint(x: 0.8, y: 0.2),
  ]
) -> RouteAtlasContextFixture {
  let source = RouteAtlasContextSource(
    sourceReferenceID: "test.source.route-atlas-context",
    authorityName: "Synthetic transport authority",
    sourcePageURL: "https://example.test/context-source",
    downloadURL: "https://example.test/context-source.zip",
    archiveSHA256: archiveSHA256,
    sourceCRS: sourceCRS,
    datasetReferenceDate: "2026-07-23",
    retrievedAt: "2026-07-23",
    checkedAt: "2026-07-23",
    licenceIdentifier: licenceIdentifier,
    usageScope: .currentStateOnly,
    attribution: "Synthetic transport authority data",
    transformationDisclosure:
      "Filtered to current synthetic expressway geometry and projected north-up."
  )
  let path = RouteAtlasContextPath(
    id: "test.context-path.001.0",
    sourceFeatureID: "test.source-feature.001",
    sourceRecordID: "test.source-record.001",
    sourcePartIndex: 0,
    routeNameJA: "テスト高速道路",
    useStatus: .complete,
    points: points
  )
  let definition = RouteAtlasContextDefinition(
    schemaVersion: "1.0",
    id: "test.route-atlas-context",
    navigationRole: navigationRole,
    sourceReferenceID: source.sourceReferenceID,
    projection: RouteAtlasContextProjection(
      kind: .localEquirectangular,
      northUp: true,
      sourceCRS: projectionCRS ?? sourceCRS,
      coordinateSpace: .normalizedUnitSquare,
      minimumLongitude: 139.70,
      maximumLongitude: 139.80,
      minimumLatitude: 35.60,
      maximumLatitude: 35.70
    ),
    coverage: coverage
      ?? RouteAtlasContextCoverage(
        sourceFeatureCount: 1,
        pathCount: 1,
        vertexCount: points.count,
        routeNameCount: 1
      ),
    paths: [path]
  )
  return RouteAtlasContextFixture(source: source, definition: definition)
}
