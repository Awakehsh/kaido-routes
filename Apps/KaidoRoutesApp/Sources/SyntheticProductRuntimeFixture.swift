import Foundation
import KaidoNavigation

enum SyntheticProductRuntimeFixtureError: Error, Equatable {
  case missingResource(String)
  case unexpectedReleaseIdentity
  case unexpectedRuntimeUse
  case nonSyntheticSource
}

/// A complete joint release used only to prove the app composition boundary.
///
/// Every nested asset still passes the production release gates, but its source
/// registries are explicitly synthetic and therefore confer no real-road
/// navigation authority.
struct SyntheticProductRuntimeFixture: Sendable {
  static let resourceName = "synthetic-product-runtime-preview"
  static let expectedProductReleaseID = "preview.synthetic.product-release.v1"

  let release: KaidoProductRelease
  let encodedByteCount: Int

  static func bundled(in bundle: Bundle = .main) throws
    -> SyntheticProductRuntimeFixture
  {
    guard
      let url = bundle.url(
        forResource: resourceName,
        withExtension: "json"
      )
    else {
      throw SyntheticProductRuntimeFixtureError.missingResource(
        "\(resourceName).json"
      )
    }
    return try decode(Data(contentsOf: url))
  }

  static func decode(_ data: Data) throws -> SyntheticProductRuntimeFixture {
    let artifact = try JSONDecoder().decode(
      KaidoProductReleaseArtifact.self,
      from: data
    )
    guard
      artifact.releaseID == expectedProductReleaseID,
      artifact.navigationRelease.releaseID
        == "test.navigation-release.release-bundle.v1"
    else {
      throw SyntheticProductRuntimeFixtureError.unexpectedReleaseIdentity
    }
    guard artifact.runtimeUse == .syntheticTestOnlyDisabled else {
      throw SyntheticProductRuntimeFixtureError.unexpectedRuntimeUse
    }

    let navigationSources = artifact.navigationRelease.sourceRegistry.references
    let atlasSources = artifact.routeAtlasRelease.sourceRegistry.references
    guard
      !navigationSources.isEmpty,
      !atlasSources.isEmpty,
      navigationSources.allSatisfy(Self.isSyntheticSource),
      atlasSources.allSatisfy(Self.isSyntheticSource)
    else {
      throw SyntheticProductRuntimeFixtureError.nonSyntheticSource
    }

    let release = try KaidoProductReleaseArtifactCodec.decode(data)
    guard
      release.releaseID == expectedProductReleaseID,
      release.runtimeUse == .syntheticTestOnlyDisabled,
      release.foregroundLiveInputAuthority == nil
    else {
      throw SyntheticProductRuntimeFixtureError.unexpectedReleaseIdentity
    }
    return SyntheticProductRuntimeFixture(
      release: release,
      encodedByteCount: data.count
    )
  }

  private static func isSyntheticSource(
    _ source: NavigationReleaseSourceReference
  ) -> Bool {
    source.licenceIdentifier == "SYNTHETIC_TEST_ONLY"
      && source.authorityName.localizedCaseInsensitiveContains("synthetic")
      && URL(string: source.sourceURL)?.host == "example.com"
  }

  private static func isSyntheticSource(
    _ source: RouteAtlasSourceReference
  ) -> Bool {
    source.licenceIdentifier == "SYNTHETIC_TEST_ONLY"
      && source.authorityName.localizedCaseInsensitiveContains("synthetic")
      && URL(string: source.sourceURL)?.host == "example.com"
  }
}
