import CryptoKit
import Foundation
import KaidoAppleAdapters
import KaidoDomain
import KaidoNavigation
import KaidoPresentation

typealias BundledProductReleaseRole = AppBundleProductReleaseRole
typealias BundledProductReleaseDescriptor =
  AppBundleProductReleaseDescriptor
typealias BundledGuidanceAudioReleaseDescriptor =
  AppBundleGuidanceAudioReleaseDescriptor
typealias BundledPreDriveEvidenceDescriptor =
  AppBundlePreDriveEvidenceDescriptor

extension AppBundleProductReleaseDescriptor {
  static var syntheticPreview: AppBundleProductReleaseDescriptor {
    AppBundleProductReleaseDescriptor(
      resourceName: "synthetic-product-runtime-preview",
      resourceExtension: "json",
      expectedSHA256:
        "53792af35b9712a1a5fadd7be9cbc3c868df09e99a5d99c3c92f7c318f7dca1e",
      expectedReleaseID: "preview.synthetic.product-release.v1",
      role: .demoOnly
    )
  }
}

struct BundledProductReleaseEntry: Equatable, Sendable {
  let descriptor: BundledProductReleaseDescriptor
  let release: KaidoProductRelease
  let guidanceAudioRelease: GuidanceAudioRelease?
  let preDriveEvidenceBundle: PreDriveEvidenceBundle?
  let preDriveEvidenceUpdateTrustKeys: [PreDriveEvidenceUpdateTrustKey]
  let preDriveEvidenceUpdateEndpoint: PreDriveEvidenceUpdateEndpoint?
  let encodedByteCount: Int

  fileprivate init(
    descriptor: BundledProductReleaseDescriptor,
    release: KaidoProductRelease,
    guidanceAudioRelease: GuidanceAudioRelease?,
    preDriveEvidenceBundle: PreDriveEvidenceBundle?,
    preDriveEvidenceUpdateTrustKeys:
      [PreDriveEvidenceUpdateTrustKey],
    preDriveEvidenceUpdateEndpoint:
      PreDriveEvidenceUpdateEndpoint?,
    encodedByteCount: Int
  ) {
    self.descriptor = descriptor
    self.release = release
    self.guidanceAudioRelease = guidanceAudioRelease
    self.preDriveEvidenceBundle = preDriveEvidenceBundle
    self.preDriveEvidenceUpdateTrustKeys =
      preDriveEvidenceUpdateTrustKeys
    self.preDriveEvidenceUpdateEndpoint =
      preDriveEvidenceUpdateEndpoint
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
  case invalidGuidanceAudioDescriptor(String)
  case missingGuidanceAudioManifest(String)
  case unreadableGuidanceAudioResource(String)
  case guidanceAudioManifestHashMismatch(String)
  case invalidGuidanceAudioRelease(String)
  case guidanceAudioReleaseIdentityMismatch(String)
  case invalidPreDriveEvidenceDescriptor(String)
  case missingPreDriveEvidenceManifest(String)
  case unreadablePreDriveEvidenceResource(String)
  case preDriveEvidenceManifestHashMismatch(String)
  case invalidPreDriveEvidenceBundle(String)
  case preDriveEvidenceReleaseIdentityMismatch(String)
  case invalidPreDriveEvidenceUpdateTrust(String)
  case preDriveEvidenceUpdateTrustRoleMismatch(String)
  case invalidPreDriveEvidenceUpdateEndpoint(String)
  case preDriveEvidenceUpdateEndpointTrustMismatch(String)
  case preDriveEvidenceUpdateEndpointRoleMismatch(String)

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
    case .invalidGuidanceAudioDescriptor:
      "GUIDANCE_AUDIO_DESCRIPTOR_INVALID"
    case .missingGuidanceAudioManifest:
      "GUIDANCE_AUDIO_MANIFEST_MISSING"
    case .unreadableGuidanceAudioResource:
      "GUIDANCE_AUDIO_RESOURCE_UNREADABLE"
    case .guidanceAudioManifestHashMismatch:
      "GUIDANCE_AUDIO_MANIFEST_HASH_MISMATCH"
    case .invalidGuidanceAudioRelease:
      "GUIDANCE_AUDIO_RELEASE_INVALID"
    case .guidanceAudioReleaseIdentityMismatch:
      "GUIDANCE_AUDIO_RELEASE_IDENTITY_MISMATCH"
    case .invalidPreDriveEvidenceDescriptor:
      "PRE_DRIVE_EVIDENCE_DESCRIPTOR_INVALID"
    case .missingPreDriveEvidenceManifest:
      "PRE_DRIVE_EVIDENCE_MANIFEST_MISSING"
    case .unreadablePreDriveEvidenceResource:
      "PRE_DRIVE_EVIDENCE_RESOURCE_UNREADABLE"
    case .preDriveEvidenceManifestHashMismatch:
      "PRE_DRIVE_EVIDENCE_MANIFEST_HASH_MISMATCH"
    case .invalidPreDriveEvidenceBundle:
      "PRE_DRIVE_EVIDENCE_BUNDLE_INVALID"
    case .preDriveEvidenceReleaseIdentityMismatch:
      "PRE_DRIVE_EVIDENCE_RELEASE_IDENTITY_MISMATCH"
    case .invalidPreDriveEvidenceUpdateTrust:
      "PRE_DRIVE_EVIDENCE_UPDATE_TRUST_INVALID"
    case .preDriveEvidenceUpdateTrustRoleMismatch:
      "PRE_DRIVE_EVIDENCE_UPDATE_TRUST_ROLE_MISMATCH"
    case .invalidPreDriveEvidenceUpdateEndpoint:
      "PRE_DRIVE_EVIDENCE_UPDATE_ENDPOINT_INVALID"
    case .preDriveEvidenceUpdateEndpointTrustMismatch:
      "PRE_DRIVE_EVIDENCE_UPDATE_ENDPOINT_TRUST_MISMATCH"
    case .preDriveEvidenceUpdateEndpointRoleMismatch:
      "PRE_DRIVE_EVIDENCE_UPDATE_ENDPOINT_ROLE_MISMATCH"
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
    try load(
      descriptors: previewManifest,
      guidanceAudioReleaseProvider: { descriptor, productRelease in
        try loadGuidanceAudioRelease(
          descriptor: descriptor,
          productRelease: productRelease,
          bundle: bundle
        )
      },
      preDriveEvidenceDataProvider: { descriptor in
        guard let evidence = descriptor.preDriveEvidence else {
          return nil
        }
        guard
          let manifestURL = bundle.url(
            forResource: evidence.manifestResourceName,
            withExtension: "json"
          )
        else {
          return nil
        }
        do {
          return try Data(contentsOf: manifestURL)
        } catch {
          throw
            BundledProductReleaseCatalogError
            .unreadablePreDriveEvidenceResource(
              evidence.manifestFilename
            )
        }
      },
      dataProvider: { descriptor in
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
    )
  }

  static func load(
    descriptors: [BundledProductReleaseDescriptor],
    guidanceAudioReleaseProvider: (
      BundledProductReleaseDescriptor,
      KaidoProductRelease
    ) throws -> GuidanceAudioRelease? = { _, _ in nil },
    preDriveEvidenceDataProvider:
      (BundledProductReleaseDescriptor) throws -> Data? = { _ in nil },
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
      if let guidanceAudio = descriptor.guidanceAudio {
        try validate(guidanceAudio)
      }
      if let preDriveEvidence = descriptor.preDriveEvidence {
        try validate(preDriveEvidence)
      }
      if let trustKeys = descriptor.preDriveEvidenceUpdateTrustKeys {
        guard !trustKeys.isEmpty else {
          throw
            BundledProductReleaseCatalogError
            .invalidPreDriveEvidenceUpdateTrust(
              descriptor.resourceFilename
            )
        }
        do {
          try PreDriveEvidenceUpdateCodec.validateTrustedKeys(trustKeys)
        } catch {
          throw
            BundledProductReleaseCatalogError
            .invalidPreDriveEvidenceUpdateTrust(
              descriptor.resourceFilename
            )
        }
      }
      if let endpoint = descriptor.preDriveEvidenceUpdateEndpoint {
        guard endpoint.validatedURL != nil else {
          throw
            BundledProductReleaseCatalogError
            .invalidPreDriveEvidenceUpdateEndpoint(
              descriptor.resourceFilename
            )
        }
        guard descriptor.preDriveEvidenceUpdateTrustKeys != nil else {
          throw
            BundledProductReleaseCatalogError
            .preDriveEvidenceUpdateEndpointTrustMismatch(
              descriptor.resourceFilename
            )
        }
      }
      guard resourceFilenames.insert(descriptor.resourceFilename).inserted else {
        throw BundledProductReleaseCatalogError.duplicateResource(
          descriptor.resourceFilename
        )
      }
      let auxiliaryManifestFilenames = [
        descriptor.guidanceAudio?.manifestFilename,
        descriptor.preDriveEvidence?.manifestFilename,
      ].compactMap { $0 }
      for filename in auxiliaryManifestFilenames {
        guard resourceFilenames.insert(filename).inserted else {
          throw BundledProductReleaseCatalogError.duplicateResource(
            filename
          )
        }
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
      if descriptor.preDriveEvidenceUpdateEndpoint != nil,
        descriptor.role != .foregroundNavigation
      {
        throw
          BundledProductReleaseCatalogError
          .preDriveEvidenceUpdateEndpointRoleMismatch(
            descriptor.resourceFilename
          )
      }
      if descriptor.preDriveEvidenceUpdateTrustKeys != nil,
        descriptor.role != .foregroundNavigation
      {
        throw
          BundledProductReleaseCatalogError
          .preDriveEvidenceUpdateTrustRoleMismatch(
            descriptor.resourceFilename
          )
      }
      guard releaseIDs.insert(release.releaseID).inserted else {
        throw BundledProductReleaseCatalogError.duplicateReleaseID(
          release.releaseID
        )
      }
      let guidanceAudioRelease = try guidanceAudioReleaseProvider(
        descriptor,
        release
      )
      if descriptor.guidanceAudio == nil, guidanceAudioRelease != nil {
        throw
          BundledProductReleaseCatalogError
          .invalidGuidanceAudioRelease(descriptor.resourceFilename)
      }
      if let guidanceAudio = descriptor.guidanceAudio {
        guard let guidanceAudioRelease else {
          throw
            BundledProductReleaseCatalogError
            .missingGuidanceAudioManifest(
              guidanceAudio.manifestFilename
            )
        }
        let audioManifest = guidanceAudioRelease.manifest
        guard
          audioManifest.productReleaseID == release.releaseID,
          audioManifest.navigationReleaseID == release.navigation.releaseID,
          audioManifest.networkSnapshotID
            == release.navigation.bundle.networkSnapshot.id,
          audioManifest.routePlanID
            == release.navigation.bundle.routePlan.id
        else {
          throw
            BundledProductReleaseCatalogError
            .invalidGuidanceAudioRelease(
              guidanceAudio.manifestFilename
            )
        }
        guard
          audioManifest.releaseID == guidanceAudio.expectedReleaseID
        else {
          throw
            BundledProductReleaseCatalogError
            .guidanceAudioReleaseIdentityMismatch(
              guidanceAudio.manifestFilename
            )
        }
      }
      var preDriveEvidenceBundle: PreDriveEvidenceBundle?
      if let preDriveEvidence = descriptor.preDriveEvidence {
        guard let evidenceData = try preDriveEvidenceDataProvider(descriptor)
        else {
          throw
            BundledProductReleaseCatalogError
            .missingPreDriveEvidenceManifest(
              preDriveEvidence.manifestFilename
            )
        }
        guard
          sha256Hex(evidenceData)
            == preDriveEvidence.expectedManifestSHA256.lowercased()
        else {
          throw
            BundledProductReleaseCatalogError
            .preDriveEvidenceManifestHashMismatch(
              preDriveEvidence.manifestFilename
            )
        }
        do {
          preDriveEvidenceBundle = try PreDriveEvidenceBundleCodec.decode(
            evidenceData,
            context: PreDriveEvidenceBundleContext(
              productReleaseID: release.releaseID,
              productReleasedAt: release.releasedAt,
              navigationReleaseID: release.navigation.releaseID,
              routePlan: release.navigation.bundle.routePlan,
              evidenceScope: .releasedRoad
            )
          )
        } catch {
          throw
            BundledProductReleaseCatalogError
            .invalidPreDriveEvidenceBundle(
              preDriveEvidence.manifestFilename
            )
        }
        guard let preDriveEvidenceBundle else {
          throw
            BundledProductReleaseCatalogError
            .invalidPreDriveEvidenceBundle(
              preDriveEvidence.manifestFilename
            )
        }
        let evidenceManifest = preDriveEvidenceBundle.manifest
        guard
          evidenceManifest.productReleaseID == release.releaseID,
          evidenceManifest.navigationReleaseID
            == release.navigation.releaseID,
          evidenceManifest.networkSnapshotID
            == release.navigation.bundle.networkSnapshot.id,
          evidenceManifest.routePlanID
            == release.navigation.bundle.routePlan.id,
          evidenceManifest.evidenceScope == .releasedRoad
        else {
          throw
            BundledProductReleaseCatalogError
            .invalidPreDriveEvidenceBundle(
              preDriveEvidence.manifestFilename
            )
        }
        guard
          evidenceManifest.releaseID == preDriveEvidence.expectedReleaseID
        else {
          throw
            BundledProductReleaseCatalogError
            .preDriveEvidenceReleaseIdentityMismatch(
              preDriveEvidence.manifestFilename
            )
        }
      }
      entries.append(
        BundledProductReleaseEntry(
          descriptor: descriptor,
          release: release,
          guidanceAudioRelease: guidanceAudioRelease,
          preDriveEvidenceBundle: preDriveEvidenceBundle,
          preDriveEvidenceUpdateTrustKeys:
            descriptor.preDriveEvidenceUpdateTrustKeys ?? [],
          preDriveEvidenceUpdateEndpoint:
            descriptor.preDriveEvidenceUpdateEndpoint,
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

  private static func validate(
    _ descriptor: BundledPreDriveEvidenceDescriptor
  ) throws {
    let resourceName = descriptor.manifestResourceName
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let releaseID = descriptor.expectedReleaseID
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let digest = descriptor.expectedManifestSHA256.lowercased()
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
      resourceName == descriptor.manifestResourceName,
      !releaseID.isEmpty,
      releaseID == descriptor.expectedReleaseID,
      isHexDigest
    else {
      throw
        BundledProductReleaseCatalogError
        .invalidPreDriveEvidenceDescriptor(descriptor.manifestFilename)
    }
  }

  private static func validate(
    _ descriptor: BundledGuidanceAudioReleaseDescriptor
  ) throws {
    let resourceName = descriptor.manifestResourceName
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let releaseID = descriptor.expectedReleaseID
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let digest = descriptor.expectedManifestSHA256.lowercased()
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
      resourceName == descriptor.manifestResourceName,
      !releaseID.isEmpty,
      releaseID == descriptor.expectedReleaseID,
      isHexDigest
    else {
      throw
        BundledProductReleaseCatalogError
        .invalidGuidanceAudioDescriptor(descriptor.manifestFilename)
    }
  }

  private static func loadGuidanceAudioRelease(
    descriptor: BundledProductReleaseDescriptor,
    productRelease: KaidoProductRelease,
    bundle: Bundle
  ) throws -> GuidanceAudioRelease? {
    guard let guidanceAudio = descriptor.guidanceAudio else {
      return nil
    }
    guard
      let manifestURL = bundle.url(
        forResource: guidanceAudio.manifestResourceName,
        withExtension: "json"
      )
    else {
      throw
        BundledProductReleaseCatalogError
        .missingGuidanceAudioManifest(guidanceAudio.manifestFilename)
    }
    let manifestData: Data
    do {
      manifestData = try Data(contentsOf: manifestURL)
    } catch {
      throw
        BundledProductReleaseCatalogError
        .unreadableGuidanceAudioResource(
          guidanceAudio.manifestFilename
        )
    }
    guard
      sha256Hex(manifestData)
        == guidanceAudio.expectedManifestSHA256.lowercased()
    else {
      throw
        BundledProductReleaseCatalogError
        .guidanceAudioManifestHashMismatch(
          guidanceAudio.manifestFilename
        )
    }

    do {
      let release = try GuidanceAudioReleaseManifestCodec.decode(
        manifestData,
        productRelease: productRelease
      ) { filename in
        let resourceURL = bundle.url(
          forResource: (filename as NSString).deletingPathExtension,
          withExtension: (filename as NSString).pathExtension
        )
        guard let resourceURL else { return nil }
        return GuidanceAudioResource(
          url: resourceURL,
          data: try Data(contentsOf: resourceURL)
        )
      }
      guard release.manifest.releaseID == guidanceAudio.expectedReleaseID
      else {
        throw
          BundledProductReleaseCatalogError
          .guidanceAudioReleaseIdentityMismatch(
            guidanceAudio.manifestFilename
          )
      }
      return release
    } catch let error as BundledProductReleaseCatalogError {
      throw error
    } catch {
      throw
        BundledProductReleaseCatalogError
        .invalidGuidanceAudioRelease(
          guidanceAudio.manifestFilename
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
