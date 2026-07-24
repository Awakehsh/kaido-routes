import CryptoKit
import Foundation
import KaidoNavigation
import KaidoPresentation

public enum AppBundleProductReleaseRole: String, Codable, Equatable, Sendable {
  case demoOnly = "DEMO_ONLY"
  case foregroundNavigation = "FOREGROUND_NAVIGATION"
}

public struct AppBundleGuidanceAudioReleaseDescriptor:
  Codable, Equatable, Sendable
{
  public let manifestResourceName: String
  public let expectedManifestSHA256: String
  public let expectedReleaseID: String

  public init(
    manifestResourceName: String,
    expectedManifestSHA256: String,
    expectedReleaseID: String
  ) {
    self.manifestResourceName = manifestResourceName
    self.expectedManifestSHA256 = expectedManifestSHA256
    self.expectedReleaseID = expectedReleaseID
  }

  public var manifestFilename: String {
    "\(manifestResourceName).json"
  }

  private enum CodingKeys: String, CodingKey {
    case manifestResourceName = "manifest_resource_name"
    case expectedManifestSHA256 = "expected_manifest_sha256"
    case expectedReleaseID = "expected_release_id"
  }
}

public struct AppBundlePreDriveEvidenceDescriptor:
  Codable, Equatable, Sendable
{
  public let manifestResourceName: String
  public let expectedManifestSHA256: String
  public let expectedReleaseID: String

  public init(
    manifestResourceName: String,
    expectedManifestSHA256: String,
    expectedReleaseID: String
  ) {
    self.manifestResourceName = manifestResourceName
    self.expectedManifestSHA256 = expectedManifestSHA256
    self.expectedReleaseID = expectedReleaseID
  }

  public var manifestFilename: String {
    "\(manifestResourceName).json"
  }

  private enum CodingKeys: String, CodingKey {
    case manifestResourceName = "manifest_resource_name"
    case expectedManifestSHA256 = "expected_manifest_sha256"
    case expectedReleaseID = "expected_release_id"
  }
}

public struct AppBundleProductReleaseDescriptor:
  Codable, Equatable, Sendable
{
  public let resourceName: String
  public let resourceExtension: String
  public let expectedSHA256: String
  public let expectedReleaseID: String
  public let role: AppBundleProductReleaseRole
  public let guidanceAudio: AppBundleGuidanceAudioReleaseDescriptor?
  public let preDriveEvidence: AppBundlePreDriveEvidenceDescriptor?
  public let preDriveEvidenceUpdateTrustKeys: [PreDriveEvidenceUpdateTrustKey]?
  public let preDriveEvidenceUpdateEndpoint: PreDriveEvidenceUpdateEndpoint?

  public init(
    resourceName: String,
    resourceExtension: String,
    expectedSHA256: String,
    expectedReleaseID: String,
    role: AppBundleProductReleaseRole,
    guidanceAudio: AppBundleGuidanceAudioReleaseDescriptor? = nil,
    preDriveEvidence: AppBundlePreDriveEvidenceDescriptor? = nil,
    preDriveEvidenceUpdateTrustKeys:
      [PreDriveEvidenceUpdateTrustKey]? = nil,
    preDriveEvidenceUpdateEndpoint:
      PreDriveEvidenceUpdateEndpoint? = nil
  ) {
    self.resourceName = resourceName
    self.resourceExtension = resourceExtension
    self.expectedSHA256 = expectedSHA256
    self.expectedReleaseID = expectedReleaseID
    self.role = role
    self.guidanceAudio = guidanceAudio
    self.preDriveEvidence = preDriveEvidence
    self.preDriveEvidenceUpdateTrustKeys =
      preDriveEvidenceUpdateTrustKeys
    self.preDriveEvidenceUpdateEndpoint =
      preDriveEvidenceUpdateEndpoint
  }

  public var resourceFilename: String {
    "\(resourceName).\(resourceExtension)"
  }

  private enum CodingKeys: String, CodingKey {
    case resourceName = "resource_name"
    case resourceExtension = "resource_extension"
    case expectedSHA256 = "expected_sha256"
    case expectedReleaseID = "expected_release_id"
    case role
    case guidanceAudio = "guidance_audio"
    case preDriveEvidence = "pre_drive_evidence"
    case preDriveEvidenceUpdateTrustKeys =
      "pre_drive_evidence_update_trust_keys"
    case preDriveEvidenceUpdateEndpoint =
      "pre_drive_evidence_update_endpoint"
  }
}

public struct AppBundleReleaseStagingConfiguration:
  Codable, Equatable, Sendable
{
  public static let currentSchemaVersion = "1.2"

  public let schemaVersion: String
  public let descriptorSymbol: String
  public let productResourceName: String
  public let guidanceAudioManifestResourceName: String?
  public let preDriveEvidenceManifestResourceName: String?
  public let preDriveEvidenceUpdateTrustKeys: [PreDriveEvidenceUpdateTrustKey]?
  public let preDriveEvidenceUpdateEndpoint: PreDriveEvidenceUpdateEndpoint?

  public init(
    schemaVersion: String =
      AppBundleReleaseStagingConfiguration.currentSchemaVersion,
    descriptorSymbol: String,
    productResourceName: String,
    guidanceAudioManifestResourceName: String? = nil,
    preDriveEvidenceManifestResourceName: String? = nil,
    preDriveEvidenceUpdateTrustKeys:
      [PreDriveEvidenceUpdateTrustKey]? = nil,
    preDriveEvidenceUpdateEndpoint:
      PreDriveEvidenceUpdateEndpoint? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.descriptorSymbol = descriptorSymbol
    self.productResourceName = productResourceName
    self.guidanceAudioManifestResourceName =
      guidanceAudioManifestResourceName
    self.preDriveEvidenceManifestResourceName =
      preDriveEvidenceManifestResourceName
    self.preDriveEvidenceUpdateTrustKeys =
      preDriveEvidenceUpdateTrustKeys
    self.preDriveEvidenceUpdateEndpoint =
      preDriveEvidenceUpdateEndpoint
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case descriptorSymbol = "descriptor_symbol"
    case productResourceName = "product_resource_name"
    case guidanceAudioManifestResourceName =
      "guidance_audio_manifest_resource_name"
    case preDriveEvidenceManifestResourceName =
      "pre_drive_evidence_manifest_resource_name"
    case preDriveEvidenceUpdateTrustKeys =
      "pre_drive_evidence_update_trust_keys"
    case preDriveEvidenceUpdateEndpoint =
      "pre_drive_evidence_update_endpoint"
  }
}

public enum AppBundleReleaseStagingConfigurationIssue:
  Equatable, Sendable
{
  case invalidSchemaVersion
  case invalidDescriptorSymbol
  case invalidProductResourceName
  case invalidGuidanceAudioManifestResourceName
  case invalidPreDriveEvidenceManifestResourceName
  case invalidPreDriveEvidenceUpdateTrustKeys
  case invalidPreDriveEvidenceUpdateEndpoint
  case incompletePreDriveEvidenceUpdateConfiguration
  case duplicateManifestResourceName

  public var code: String {
    switch self {
    case .invalidSchemaVersion:
      "INVALID_APP_BUNDLE_STAGING_SCHEMA_VERSION"
    case .invalidDescriptorSymbol:
      "INVALID_APP_BUNDLE_DESCRIPTOR_SYMBOL"
    case .invalidProductResourceName:
      "INVALID_APP_BUNDLE_PRODUCT_RESOURCE_NAME"
    case .invalidGuidanceAudioManifestResourceName:
      "INVALID_APP_BUNDLE_AUDIO_MANIFEST_RESOURCE_NAME"
    case .invalidPreDriveEvidenceManifestResourceName:
      "INVALID_APP_BUNDLE_PRE_DRIVE_EVIDENCE_RESOURCE_NAME"
    case .invalidPreDriveEvidenceUpdateTrustKeys:
      "INVALID_APP_BUNDLE_PRE_DRIVE_EVIDENCE_UPDATE_TRUST_KEYS"
    case .invalidPreDriveEvidenceUpdateEndpoint:
      "INVALID_APP_BUNDLE_PRE_DRIVE_EVIDENCE_UPDATE_ENDPOINT"
    case .incompletePreDriveEvidenceUpdateConfiguration:
      "INCOMPLETE_APP_BUNDLE_PRE_DRIVE_EVIDENCE_UPDATE_CONFIGURATION"
    case .duplicateManifestResourceName:
      "DUPLICATE_APP_BUNDLE_MANIFEST_RESOURCE_NAME"
    }
  }
}

public enum AppBundleReleaseStagingError: Error, Equatable, Sendable {
  case invalidConfiguration([AppBundleReleaseStagingConfigurationIssue])
  case invalidProductArtifact
  case invalidProductRelease([KaidoProductReleaseIssue])
  case foregroundProductRequired
  case guidanceAudioInputMismatch
  case invalidGuidanceAudioArtifact
  case invalidGuidanceAudioRelease([GuidanceAudioReleaseIssue])
  case preDriveEvidenceInputMismatch
  case invalidPreDriveEvidenceArtifact
  case invalidPreDriveEvidenceBundle([PreDriveEvidenceBundleIssue])
  case duplicateResourceFilename(String)
}

public enum AppBundleStagedResourceKind:
  String, Codable, Equatable, Sendable
{
  case productRelease = "PRODUCT_RELEASE"
  case guidanceAudioManifest = "GUIDANCE_AUDIO_MANIFEST"
  case guidanceAudioWave = "GUIDANCE_AUDIO_WAVE"
  case preDriveEvidenceManifest = "PRE_DRIVE_EVIDENCE_MANIFEST"
}

public struct AppBundleStagedResourceRecord:
  Codable, Equatable, Sendable
{
  public let relativePath: String
  public let kind: AppBundleStagedResourceKind
  public let sha256: String
  public let byteCount: Int

  public init(
    relativePath: String,
    kind: AppBundleStagedResourceKind,
    sha256: String,
    byteCount: Int
  ) {
    self.relativePath = relativePath
    self.kind = kind
    self.sha256 = sha256
    self.byteCount = byteCount
  }

  private enum CodingKeys: String, CodingKey {
    case relativePath = "relative_path"
    case kind
    case sha256
    case byteCount = "byte_count"
  }
}

public struct AppBundleReleaseStagingManifest:
  Codable, Equatable, Sendable
{
  public static let currentSchemaVersion = "1.2"

  public let schemaVersion: String
  public let descriptorSymbol: String
  public let descriptor: AppBundleProductReleaseDescriptor
  public let resources: [AppBundleStagedResourceRecord]

  public init(
    schemaVersion: String =
      AppBundleReleaseStagingManifest.currentSchemaVersion,
    descriptorSymbol: String,
    descriptor: AppBundleProductReleaseDescriptor,
    resources: [AppBundleStagedResourceRecord]
  ) {
    self.schemaVersion = schemaVersion
    self.descriptorSymbol = descriptorSymbol
    self.descriptor = descriptor
    self.resources = resources
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case descriptorSymbol = "descriptor_symbol"
    case descriptor
    case resources
  }
}

public struct AppBundleStagedFile: Equatable, Sendable {
  public let relativePath: String
  public let data: Data

  public init(relativePath: String, data: Data) {
    self.relativePath = relativePath
    self.data = data
  }
}

public struct AppBundleReleaseStagingPackage: Equatable, Sendable {
  public let manifest: AppBundleReleaseStagingManifest
  public let files: [AppBundleStagedFile]

  public init(
    manifest: AppBundleReleaseStagingManifest,
    files: [AppBundleStagedFile]
  ) {
    self.manifest = manifest
    self.files = files
  }
}

/// Prepares one exact foreground product release for deliberate App inclusion.
///
/// The author does not modify an App target or discover arbitrary resources. It
/// validates the production product codec and optional complete audio release,
/// then returns exact resource bytes plus a compile-time descriptor snippet.
public enum AppBundleReleaseStagingAuthor {
  public static func prepare(
    configuration: AppBundleReleaseStagingConfiguration,
    productArtifactData: Data,
    guidanceAudioManifestData: Data? = nil,
    guidanceAudioResourceProvider: (
      (String) throws -> GuidanceAudioResource?
    )? = nil,
    preDriveEvidenceManifestData: Data? = nil
  ) throws -> AppBundleReleaseStagingPackage {
    let configurationIssues = validationIssues(configuration)
    guard configurationIssues.isEmpty else {
      throw AppBundleReleaseStagingError.invalidConfiguration(
        configurationIssues
      )
    }

    let productRelease: KaidoProductRelease
    do {
      productRelease = try KaidoProductReleaseArtifactCodec.decode(
        productArtifactData
      )
    } catch KaidoProductReleaseError.invalid(let issues) {
      throw AppBundleReleaseStagingError.invalidProductRelease(issues)
    } catch {
      throw AppBundleReleaseStagingError.invalidProductArtifact
    }
    guard
      productRelease.runtimeUse.evidenceScope == .releasedRoad,
      productRelease.runtimeUse.liveInputPolicy == .foregroundWhenInUse,
      productRelease.foregroundLiveInputAuthority != nil
    else {
      throw AppBundleReleaseStagingError.foregroundProductRequired
    }

    let hasAudioResourceName =
      configuration.guidanceAudioManifestResourceName != nil
    let hasAudioManifest = guidanceAudioManifestData != nil
    let hasAudioProvider = guidanceAudioResourceProvider != nil
    guard
      hasAudioResourceName == hasAudioManifest,
      hasAudioManifest == hasAudioProvider
    else {
      throw AppBundleReleaseStagingError.guidanceAudioInputMismatch
    }

    var stagedFiles: [AppBundleStagedFile] = [
      AppBundleStagedFile(
        relativePath:
          "Resources/\(configuration.productResourceName).json",
        data: productArtifactData
      )
    ]
    var audioDescriptor: AppBundleGuidanceAudioReleaseDescriptor?
    var preDriveEvidenceDescriptor: AppBundlePreDriveEvidenceDescriptor?

    if let audioResourceName =
      configuration.guidanceAudioManifestResourceName,
      let audioManifestData = guidanceAudioManifestData,
      let audioProvider = guidanceAudioResourceProvider
    {
      var resourceCache: [String: GuidanceAudioResource] = [:]
      let audioRelease: GuidanceAudioRelease
      do {
        audioRelease = try GuidanceAudioReleaseManifestCodec.decode(
          audioManifestData,
          productRelease: productRelease,
          resourceProvider: { filename in
            if let cached = resourceCache[filename] {
              return cached
            }
            guard let resource = try audioProvider(filename) else {
              return nil
            }
            resourceCache[filename] = resource
            return resource
          }
        )
      } catch GuidanceAudioReleaseError.invalid(let issues) {
        throw AppBundleReleaseStagingError.invalidGuidanceAudioRelease(
          issues
        )
      } catch {
        throw AppBundleReleaseStagingError.invalidGuidanceAudioArtifact
      }

      stagedFiles.append(
        AppBundleStagedFile(
          relativePath: "Resources/\(audioResourceName).json",
          data: audioManifestData
        )
      )
      let audioFilenames = Set(
        audioRelease.assets.map(\.record.resourceFilename)
      ).sorted()
      for filename in audioFilenames {
        guard let resource = resourceCache[filename] else {
          throw AppBundleReleaseStagingError.invalidGuidanceAudioArtifact
        }
        stagedFiles.append(
          AppBundleStagedFile(
            relativePath: "Resources/\(filename)",
            data: resource.data
          )
        )
      }
      audioDescriptor = AppBundleGuidanceAudioReleaseDescriptor(
        manifestResourceName: audioResourceName,
        expectedManifestSHA256: sha256Hex(audioManifestData),
        expectedReleaseID: audioRelease.manifest.releaseID
      )
    }

    let hasPreDriveEvidenceResourceName =
      configuration.preDriveEvidenceManifestResourceName != nil
    let hasPreDriveEvidenceManifest =
      preDriveEvidenceManifestData != nil
    guard
      hasPreDriveEvidenceResourceName == hasPreDriveEvidenceManifest
    else {
      throw AppBundleReleaseStagingError.preDriveEvidenceInputMismatch
    }
    if let preDriveEvidenceResourceName =
      configuration.preDriveEvidenceManifestResourceName,
      let preDriveEvidenceManifestData
    {
      let bundle: PreDriveEvidenceBundle
      do {
        bundle = try PreDriveEvidenceBundleCodec.decode(
          preDriveEvidenceManifestData,
          context: PreDriveEvidenceBundleContext(
            productReleaseID: productRelease.releaseID,
            productReleasedAt: productRelease.releasedAt,
            navigationReleaseID: productRelease.navigation.releaseID,
            routePlan: productRelease.navigation.bundle.routePlan,
            evidenceScope: .releasedRoad
          )
        )
      } catch PreDriveEvidenceBundleError.invalid(let issues) {
        throw AppBundleReleaseStagingError.invalidPreDriveEvidenceBundle(
          issues
        )
      } catch {
        throw AppBundleReleaseStagingError.invalidPreDriveEvidenceArtifact
      }
      stagedFiles.append(
        AppBundleStagedFile(
          relativePath:
            "Resources/\(preDriveEvidenceResourceName).json",
          data: preDriveEvidenceManifestData
        )
      )
      preDriveEvidenceDescriptor = AppBundlePreDriveEvidenceDescriptor(
        manifestResourceName: preDriveEvidenceResourceName,
        expectedManifestSHA256: sha256Hex(preDriveEvidenceManifestData),
        expectedReleaseID: bundle.manifest.releaseID
      )
    }

    let duplicateResource = Dictionary(grouping: stagedFiles) {
      $0.relativePath
    }.first { $0.value.count > 1 }?.key
    if let duplicateResource {
      throw AppBundleReleaseStagingError.duplicateResourceFilename(
        String(duplicateResource.dropFirst("Resources/".count))
      )
    }

    let descriptor = AppBundleProductReleaseDescriptor(
      resourceName: configuration.productResourceName,
      resourceExtension: "json",
      expectedSHA256: sha256Hex(productArtifactData),
      expectedReleaseID: productRelease.releaseID,
      role: .foregroundNavigation,
      guidanceAudio: audioDescriptor,
      preDriveEvidence: preDriveEvidenceDescriptor,
      preDriveEvidenceUpdateTrustKeys:
        configuration.preDriveEvidenceUpdateTrustKeys,
      preDriveEvidenceUpdateEndpoint:
        configuration.preDriveEvidenceUpdateEndpoint
    )
    let resourceRecords = stagedFiles.map { file in
      AppBundleStagedResourceRecord(
        relativePath: file.relativePath,
        kind: resourceKind(
          relativePath: file.relativePath,
          productResourceName: configuration.productResourceName,
          audioManifestResourceName:
            configuration.guidanceAudioManifestResourceName,
          preDriveEvidenceManifestResourceName:
            configuration.preDriveEvidenceManifestResourceName
        ),
        sha256: sha256Hex(file.data),
        byteCount: file.data.count
      )
    }.sorted { $0.relativePath < $1.relativePath }
    let manifest = AppBundleReleaseStagingManifest(
      descriptorSymbol: configuration.descriptorSymbol,
      descriptor: descriptor,
      resources: resourceRecords
    )

    let sourcePath =
      "Sources/BundledProductReleaseDescriptor+"
      + "\(configuration.descriptorSymbol).swift"
    stagedFiles.append(
      AppBundleStagedFile(
        relativePath: sourcePath,
        data: Data(
          swiftSource(
            descriptor: descriptor,
            symbol: configuration.descriptorSymbol
          ).utf8
        )
      )
    )
    stagedFiles.append(
      AppBundleStagedFile(
        relativePath: "app-bundle-staging-manifest.json",
        data: try AppBundleReleaseStagingManifestCodec.encode(manifest)
      )
    )

    return AppBundleReleaseStagingPackage(
      manifest: manifest,
      files: stagedFiles.sorted { $0.relativePath < $1.relativePath }
    )
  }

  private static func validationIssues(
    _ configuration: AppBundleReleaseStagingConfiguration
  ) -> [AppBundleReleaseStagingConfigurationIssue] {
    var issues: [AppBundleReleaseStagingConfigurationIssue] = []
    if configuration.schemaVersion
      != AppBundleReleaseStagingConfiguration.currentSchemaVersion
    {
      issues.append(.invalidSchemaVersion)
    }
    if !isSwiftIdentifier(configuration.descriptorSymbol) {
      issues.append(.invalidDescriptorSymbol)
    }
    if !isSafeResourceName(configuration.productResourceName) {
      issues.append(.invalidProductResourceName)
    }
    if let audioResourceName =
      configuration.guidanceAudioManifestResourceName,
      !isSafeResourceName(audioResourceName)
    {
      issues.append(.invalidGuidanceAudioManifestResourceName)
    }
    if let preDriveEvidenceResourceName =
      configuration.preDriveEvidenceManifestResourceName,
      !isSafeResourceName(preDriveEvidenceResourceName)
    {
      issues.append(.invalidPreDriveEvidenceManifestResourceName)
    }
    if let trustKeys = configuration.preDriveEvidenceUpdateTrustKeys {
      if trustKeys.isEmpty
        || (try? PreDriveEvidenceUpdateCodec.validateTrustedKeys(
          trustKeys
        )) == nil
      {
        issues.append(.invalidPreDriveEvidenceUpdateTrustKeys)
      }
    }
    if let endpoint = configuration.preDriveEvidenceUpdateEndpoint {
      if endpoint.validatedURL == nil {
        issues.append(.invalidPreDriveEvidenceUpdateEndpoint)
      }
      if configuration.preDriveEvidenceUpdateTrustKeys == nil {
        issues.append(
          .incompletePreDriveEvidenceUpdateConfiguration
        )
      }
    }
    let resourceNames = [
      configuration.productResourceName,
      configuration.guidanceAudioManifestResourceName,
      configuration.preDriveEvidenceManifestResourceName,
    ].compactMap { $0 }
    if Set(resourceNames).count != resourceNames.count {
      issues.append(.duplicateManifestResourceName)
    }
    return issues
  }

  private static func resourceKind(
    relativePath: String,
    productResourceName: String,
    audioManifestResourceName: String?,
    preDriveEvidenceManifestResourceName: String?
  ) -> AppBundleStagedResourceKind {
    if relativePath == "Resources/\(productResourceName).json" {
      return .productRelease
    }
    if let audioManifestResourceName,
      relativePath == "Resources/\(audioManifestResourceName).json"
    {
      return .guidanceAudioManifest
    }
    if let preDriveEvidenceManifestResourceName,
      relativePath
        == "Resources/\(preDriveEvidenceManifestResourceName).json"
    {
      return .preDriveEvidenceManifest
    }
    return .guidanceAudioWave
  }

  private static func isSafeResourceName(_ value: String) -> Bool {
    !value.isEmpty
      && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
      && value.allSatisfy {
        $0.isASCII
          && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_")
      }
  }

  private static func isSwiftIdentifier(_ value: String) -> Bool {
    guard
      let first = value.first,
      first.isASCII && (first.isLetter || first == "_"),
      value.allSatisfy({
        $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_")
      })
    else {
      return false
    }
    return !swiftKeywords.contains(value)
  }

  private static let swiftKeywords: Set<String> = [
    "associatedtype", "class", "deinit", "enum", "extension", "fileprivate",
    "func", "import", "init", "inout", "internal", "let", "open", "operator",
    "private", "precedencegroup", "protocol", "public", "rethrows", "static",
    "struct", "subscript", "typealias", "var", "break", "case", "catch",
    "continue", "default", "defer", "do", "else", "fallthrough", "for",
    "guard", "if", "in", "repeat", "return", "throw", "switch", "where",
    "while", "as", "Any", "false", "is", "nil", "self", "Self", "super",
    "throws", "true", "try",
  ]

  private static func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map {
      String(format: "%02x", $0)
    }.joined()
  }

  private static func swiftSource(
    descriptor: AppBundleProductReleaseDescriptor,
    symbol: String
  ) -> String {
    let audioSource: String
    if let audio = descriptor.guidanceAudio {
      audioSource =
        """
        AppBundleGuidanceAudioReleaseDescriptor(
              manifestResourceName: \(swiftString(audio.manifestResourceName)),
              expectedManifestSHA256: \(swiftString(audio.expectedManifestSHA256)),
              expectedReleaseID: \(swiftString(audio.expectedReleaseID))
            )
        """
    } else {
      audioSource = "nil"
    }
    let preDriveEvidenceSource: String
    if let evidence = descriptor.preDriveEvidence {
      preDriveEvidenceSource =
        """
        AppBundlePreDriveEvidenceDescriptor(
              manifestResourceName: \(swiftString(evidence.manifestResourceName)),
              expectedManifestSHA256: \(swiftString(evidence.expectedManifestSHA256)),
              expectedReleaseID: \(swiftString(evidence.expectedReleaseID))
            )
        """
    } else {
      preDriveEvidenceSource = "nil"
    }
    let preDriveEvidenceUpdateTrustSource: String
    if let trustKeys = descriptor.preDriveEvidenceUpdateTrustKeys {
      preDriveEvidenceUpdateTrustSource =
        "[\n"
        + trustKeys.map { trustKey in
          """
              PreDriveEvidenceUpdateTrustKey(
                keyID: \(swiftString(trustKey.keyID)),
                algorithm: .ed25519,
                publicKeyBase64: \(swiftString(trustKey.publicKeyBase64))
              )
          """
        }.joined(separator: ",\n")
        + "\n          ]"
    } else {
      preDriveEvidenceUpdateTrustSource = "nil"
    }
    let preDriveEvidenceUpdateEndpointSource: String
    if let endpoint = descriptor.preDriveEvidenceUpdateEndpoint {
      preDriveEvidenceUpdateEndpointSource =
        """
        PreDriveEvidenceUpdateEndpoint(
              url: \(swiftString(endpoint.url))
            )
        """
    } else {
      preDriveEvidenceUpdateEndpointSource = "nil"
    }
    return
      """
      // Generated by kaido-release prepare-app-bundle.
      // Review this file and add .\(symbol) to the App's
      // BundledProductReleaseCatalogLoader.previewManifest deliberately.
      import KaidoAppleAdapters

      extension AppBundleProductReleaseDescriptor {
        static let \(symbol) = AppBundleProductReleaseDescriptor(
          resourceName: \(swiftString(descriptor.resourceName)),
          resourceExtension: \(swiftString(descriptor.resourceExtension)),
          expectedSHA256: \(swiftString(descriptor.expectedSHA256)),
          expectedReleaseID: \(swiftString(descriptor.expectedReleaseID)),
          role: .foregroundNavigation,
          guidanceAudio: \(audioSource),
          preDriveEvidence: \(preDriveEvidenceSource),
          preDriveEvidenceUpdateTrustKeys: \(preDriveEvidenceUpdateTrustSource),
          preDriveEvidenceUpdateEndpoint: \(preDriveEvidenceUpdateEndpointSource)
        )
      }

      """
  }

  private static func swiftString(_ value: String) -> String {
    var result = "\""
    for scalar in value.unicodeScalars {
      switch scalar {
      case "\\":
        result += "\\\\"
      case "\"":
        result += "\\\""
      case "\n":
        result += "\\n"
      case "\r":
        result += "\\r"
      case "\t":
        result += "\\t"
      default:
        result.unicodeScalars.append(scalar)
      }
    }
    result += "\""
    return result
  }
}

public enum AppBundleReleaseStagingConfigurationCodec {
  public static func encode(
    _ configuration: AppBundleReleaseStagingConfiguration
  ) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(configuration)
  }

  public static func decode(
    _ data: Data
  ) throws -> AppBundleReleaseStagingConfiguration {
    try JSONDecoder().decode(
      AppBundleReleaseStagingConfiguration.self,
      from: data
    )
  }
}

public enum AppBundleReleaseStagingManifestCodec {
  public static func encode(
    _ manifest: AppBundleReleaseStagingManifest
  ) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(manifest)
  }

  public static func decode(
    _ data: Data
  ) throws -> AppBundleReleaseStagingManifest {
    try JSONDecoder().decode(
      AppBundleReleaseStagingManifest.self,
      from: data
    )
  }
}
