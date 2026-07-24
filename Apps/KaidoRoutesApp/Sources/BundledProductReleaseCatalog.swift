import CryptoKit
import Foundation
import KaidoDomain
import KaidoNavigation

enum BundledProductReleaseRole: String, Equatable, Sendable {
  case demoOnly = "DEMO_ONLY"
  case foregroundNavigation = "FOREGROUND_NAVIGATION"
}

struct BundledProductReleaseDescriptor: Equatable, Sendable {
  let resourceName: String
  let resourceExtension: String
  let expectedSHA256: String
  let expectedReleaseID: String
  let role: BundledProductReleaseRole

  static let syntheticPreview = BundledProductReleaseDescriptor(
    resourceName: "synthetic-product-runtime-preview",
    resourceExtension: "json",
    expectedSHA256:
      "f728e936b6276d8dc7599f103b41f00a7d479e82acd2312956af0eabea4198d6",
    expectedReleaseID: "preview.synthetic.product-release.v1",
    role: .demoOnly
  )

  var resourceFilename: String {
    "\(resourceName).\(resourceExtension)"
  }
}

struct BundledProductReleaseEntry: Equatable, Sendable {
  let descriptor: BundledProductReleaseDescriptor
  let release: KaidoProductRelease
  let encodedByteCount: Int

  fileprivate init(
    descriptor: BundledProductReleaseDescriptor,
    release: KaidoProductRelease,
    encodedByteCount: Int
  ) {
    self.descriptor = descriptor
    self.release = release
    self.encodedByteCount = encodedByteCount
  }
}

enum BundledProductReleaseSelection: Equatable, Sendable {
  case unavailable
  case selected(BundledProductReleaseEntry)
  case ambiguous([String])
}

struct BundledProductReleaseCatalog: Equatable, Sendable {
  let entries: [BundledProductReleaseEntry]

  var demoEntries: [BundledProductReleaseEntry] {
    entries.filter { $0.descriptor.role == .demoOnly }
  }

  var foregroundNavigationEntries: [BundledProductReleaseEntry] {
    entries.filter {
      $0.descriptor.role == .foregroundNavigation
    }
  }

  func selectForegroundNavigationRelease(
    matching routePlan: RoutePlan
  ) -> BundledProductReleaseSelection {
    let matches = foregroundNavigationEntries.filter {
      $0.release.navigation.bundle.routePlan == routePlan
    }
    switch matches.count {
    case 0:
      return .unavailable
    case 1:
      return .selected(matches[0])
    default:
      return .ambiguous(matches.map(\.release.releaseID).sorted())
    }
  }
}

enum BundledProductReleaseCatalogError: Error, Equatable, Sendable {
  case emptyManifest
  case invalidDescriptor(String)
  case duplicateResource(String)
  case missingResource(String)
  case unreadableResource(String)
  case resourceHashMismatch(String)
  case invalidProductRelease(String)
  case releaseIdentityMismatch(String)
  case releaseRoleMismatch(String)
  case duplicateReleaseID(String)

  var code: String {
    switch self {
    case .emptyManifest:
      "PRODUCT_RELEASE_CATALOG_EMPTY"
    case .invalidDescriptor:
      "PRODUCT_RELEASE_DESCRIPTOR_INVALID"
    case .duplicateResource:
      "PRODUCT_RELEASE_RESOURCE_DUPLICATE"
    case .missingResource:
      "PRODUCT_RELEASE_RESOURCE_MISSING"
    case .unreadableResource:
      "PRODUCT_RELEASE_RESOURCE_UNREADABLE"
    case .resourceHashMismatch:
      "PRODUCT_RELEASE_RESOURCE_HASH_MISMATCH"
    case .invalidProductRelease:
      "PRODUCT_RELEASE_ARTIFACT_INVALID"
    case .releaseIdentityMismatch:
      "PRODUCT_RELEASE_IDENTITY_MISMATCH"
    case .releaseRoleMismatch:
      "PRODUCT_RELEASE_ROLE_MISMATCH"
    case .duplicateReleaseID:
      "PRODUCT_RELEASE_ID_DUPLICATE"
    }
  }
}

enum BundledProductReleaseCatalogLoader {
  static let previewManifest: [BundledProductReleaseDescriptor] = [
    .syntheticPreview
  ]

  static func bundledPreview(
    in bundle: Bundle = .main
  ) throws -> BundledProductReleaseCatalog {
    try load(descriptors: previewManifest) { descriptor in
      guard
        let url = bundle.url(
          forResource: descriptor.resourceName,
          withExtension: descriptor.resourceExtension
        )
      else {
        return nil
      }
      do {
        return try Data(contentsOf: url)
      } catch {
        throw BundledProductReleaseCatalogError.unreadableResource(
          descriptor.resourceFilename
        )
      }
    }
  }

  static func load(
    descriptors: [BundledProductReleaseDescriptor],
    dataProvider: (BundledProductReleaseDescriptor) throws -> Data?
  ) throws -> BundledProductReleaseCatalog {
    guard !descriptors.isEmpty else {
      throw BundledProductReleaseCatalogError.emptyManifest
    }

    var resourceFilenames: Set<String> = []
    var releaseIDs: Set<String> = []
    var entries: [BundledProductReleaseEntry] = []

    for descriptor in descriptors {
      try validate(descriptor)
      guard resourceFilenames.insert(descriptor.resourceFilename).inserted else {
        throw BundledProductReleaseCatalogError.duplicateResource(
          descriptor.resourceFilename
        )
      }
      guard let data = try dataProvider(descriptor) else {
        throw BundledProductReleaseCatalogError.missingResource(
          descriptor.resourceFilename
        )
      }
      guard sha256Hex(data) == descriptor.expectedSHA256.lowercased() else {
        throw BundledProductReleaseCatalogError.resourceHashMismatch(
          descriptor.resourceFilename
        )
      }

      let release: KaidoProductRelease
      do {
        release = try KaidoProductReleaseArtifactCodec.decode(data)
      } catch {
        throw BundledProductReleaseCatalogError.invalidProductRelease(
          descriptor.resourceFilename
        )
      }
      guard release.releaseID == descriptor.expectedReleaseID else {
        throw BundledProductReleaseCatalogError.releaseIdentityMismatch(
          descriptor.resourceFilename
        )
      }
      guard roleMatches(descriptor.role, release: release) else {
        throw BundledProductReleaseCatalogError.releaseRoleMismatch(
          descriptor.resourceFilename
        )
      }
      guard releaseIDs.insert(release.releaseID).inserted else {
        throw BundledProductReleaseCatalogError.duplicateReleaseID(
          release.releaseID
        )
      }
      entries.append(
        BundledProductReleaseEntry(
          descriptor: descriptor,
          release: release,
          encodedByteCount: data.count
        )
      )
    }

    return BundledProductReleaseCatalog(
      entries: entries.sorted {
        if $0.descriptor.role != $1.descriptor.role {
          return $0.descriptor.role.rawValue
            < $1.descriptor.role.rawValue
        }
        return $0.release.releaseID < $1.release.releaseID
      }
    )
  }

  static func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map {
      String(format: "%02x", $0)
    }.joined()
  }

  private static func validate(
    _ descriptor: BundledProductReleaseDescriptor
  ) throws {
    let resourceName = descriptor.resourceName.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    let resourceExtension =
      descriptor.resourceExtension.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
    let releaseID = descriptor.expectedReleaseID.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    let digest = descriptor.expectedSHA256.lowercased()
    let isHexDigest =
      digest.count == 64
      && digest.allSatisfy {
        ("0"..."9").contains($0) || ("a"..."f").contains($0)
      }
    let isSafeResourceName =
      !resourceName.isEmpty
      && resourceName.allSatisfy {
        $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_"
      }
    guard
      isSafeResourceName,
      resourceName == descriptor.resourceName,
      !resourceExtension.isEmpty,
      resourceExtension == descriptor.resourceExtension,
      resourceExtension.allSatisfy(\.isLetter),
      !releaseID.isEmpty,
      releaseID == descriptor.expectedReleaseID,
      isHexDigest
    else {
      throw BundledProductReleaseCatalogError.invalidDescriptor(
        descriptor.resourceFilename
      )
    }
  }

  private static func roleMatches(
    _ role: BundledProductReleaseRole,
    release: KaidoProductRelease
  ) -> Bool {
    switch role {
    case .demoOnly:
      release.runtimeUse == .syntheticTestOnlyDisabled
        && release.foregroundLiveInputAuthority == nil
    case .foregroundNavigation:
      release.runtimeUse.evidenceScope == .releasedRoad
        && release.runtimeUse.liveInputPolicy == .foregroundWhenInUse
        && release.foregroundLiveInputAuthority != nil
    }
  }
}
