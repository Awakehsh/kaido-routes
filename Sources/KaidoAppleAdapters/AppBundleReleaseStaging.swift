import CryptoKit
import Foundation
import KaidoNavigation
import KaidoPresentation

public enum AppBundleProductReleaseRole: String, Codable, Equatable, Sendable {
  case demoOnly = "DEMO_ONLY"
  case foregroundNavigation = "FOREGROUND_NAVIGATION"
}

public struct AppBundleGuidanceAudioDisplayName:
  Codable, Equatable, Sendable
{
  public let japanese: String
  public let simplifiedChinese: String
  public let english: String

  public init(
    japanese: String,
    simplifiedChinese: String,
    english: String
  ) {
    self.japanese = japanese
    self.simplifiedChinese = simplifiedChinese
    self.english = english
  }

  private enum CodingKeys: String, CodingKey {
    case japanese
    case simplifiedChinese = "simplified_chinese"
    case english
  }
}

public struct AppBundleGuidanceAudioReleaseDescriptor:
  Codable, Equatable, Sendable
{
  public let selectionID: String
  public let displayName: AppBundleGuidanceAudioDisplayName
  public let manifestResourceName: String
  public let expectedManifestSHA256: String
  public let expectedReleaseID: String

  public init(
    selectionID: String,
    displayName: AppBundleGuidanceAudioDisplayName,
    manifestResourceName: String,
    expectedManifestSHA256: String,
    expectedReleaseID: String
  ) {
    self.selectionID = selectionID
    self.displayName = displayName
    self.manifestResourceName = manifestResourceName
    self.expectedManifestSHA256 = expectedManifestSHA256
    self.expectedReleaseID = expectedReleaseID
  }

  public var manifestFilename: String {
    "\(manifestResourceName).json"
  }

  private enum CodingKeys: String, CodingKey {
    case selectionID = "selection_id"
    case displayName = "display_name"
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
  public let guidanceAudioChoices: [AppBundleGuidanceAudioReleaseDescriptor]
  public let preDriveEvidence: AppBundlePreDriveEvidenceDescriptor?
  public let preDriveEvidenceUpdateTrustKeys: [PreDriveEvidenceUpdateTrustKey]?
  public let preDriveEvidenceUpdateEndpoint: PreDriveEvidenceUpdateEndpoint?

  public init(
    resourceName: String,
    resourceExtension: String,
    expectedSHA256: String,
    expectedReleaseID: String,
    role: AppBundleProductReleaseRole,
    guidanceAudioChoices:
      [AppBundleGuidanceAudioReleaseDescriptor] = [],
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
    self.guidanceAudioChoices = guidanceAudioChoices
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
    case guidanceAudioChoices = "guidance_audio_choices"
    case preDriveEvidence = "pre_drive_evidence"
    case preDriveEvidenceUpdateTrustKeys =
      "pre_drive_evidence_update_trust_keys"
    case preDriveEvidenceUpdateEndpoint =
      "pre_drive_evidence_update_endpoint"
  }
}

public struct AppBundleGuidanceAudioStagingOption:
  Codable, Equatable, Sendable
{
  public let selectionID: String
  public let displayName: AppBundleGuidanceAudioDisplayName
  public let manifestResourceName: String

  public init(
    selectionID: String,
    displayName: AppBundleGuidanceAudioDisplayName,
    manifestResourceName: String
  ) {
    self.selectionID = selectionID
    self.displayName = displayName
    self.manifestResourceName = manifestResourceName
  }

  private enum CodingKeys: String, CodingKey {
    case selectionID = "selection_id"
    case displayName = "display_name"
    case manifestResourceName = "manifest_resource_name"
  }
}

public struct AppBundleReleaseStagingConfiguration:
  Codable, Equatable, Sendable
{
  public static let currentSchemaVersion = "2.0"

  public let schemaVersion: String
  public let descriptorSymbol: String
  public let productResourceName: String
  public let guidanceAudioOptions: [AppBundleGuidanceAudioStagingOption]
  public let preDriveEvidenceManifestResourceName: String?
  public let preDriveEvidenceUpdateTrustKeys: [PreDriveEvidenceUpdateTrustKey]?
  public let preDriveEvidenceUpdateEndpoint: PreDriveEvidenceUpdateEndpoint?

  public init(
    schemaVersion: String =
      AppBundleReleaseStagingConfiguration.currentSchemaVersion,
    descriptorSymbol: String,
    productResourceName: String,
    guidanceAudioOptions:
      [AppBundleGuidanceAudioStagingOption] = [],
    preDriveEvidenceManifestResourceName: String? = nil,
    preDriveEvidenceUpdateTrustKeys:
      [PreDriveEvidenceUpdateTrustKey]? = nil,
    preDriveEvidenceUpdateEndpoint:
      PreDriveEvidenceUpdateEndpoint? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.descriptorSymbol = descriptorSymbol
    self.productResourceName = productResourceName
    self.guidanceAudioOptions = guidanceAudioOptions
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
    case guidanceAudioOptions = "guidance_audio_options"
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
  case invalidGuidanceAudioOption
  case duplicateGuidanceAudioSelectionID
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
    case .invalidGuidanceAudioOption:
      "INVALID_APP_BUNDLE_AUDIO_OPTION"
    case .duplicateGuidanceAudioSelectionID:
      "DUPLICATE_APP_BUNDLE_AUDIO_SELECTION_ID"
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
  case duplicateGuidanceAudioReleaseID(String)
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
  public static let currentSchemaVersion = "2.0"

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
    guidanceAudioManifestDataProvider: (
      (String) throws -> Data?
    )? = nil,
    guidanceAudioResourceProvider: (
      (String, String) throws -> GuidanceAudioResource?
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

    let hasAudioOptions = !configuration.guidanceAudioOptions.isEmpty
    let hasAudioManifestProvider =
      guidanceAudioManifestDataProvider != nil
    let hasAudioProvider = guidanceAudioResourceProvider != nil
    guard
      hasAudioOptions == hasAudioManifestProvider,
      hasAudioManifestProvider == hasAudioProvider
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
    var audioDescriptors: [AppBundleGuidanceAudioReleaseDescriptor] = []
    var preDriveEvidenceDescriptor: AppBundlePreDriveEvidenceDescriptor?

    if let audioManifestProvider = guidanceAudioManifestDataProvider,
      let audioProvider = guidanceAudioResourceProvider
    {
      for option in configuration.guidanceAudioOptions {
        guard
          let audioManifestData = try audioManifestProvider(
            option.manifestResourceName
          )
        else {
          throw AppBundleReleaseStagingError.invalidGuidanceAudioArtifact
        }
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
              guard
                let resource = try audioProvider(
                  option.selectionID,
                  filename
                )
              else {
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
            relativePath:
              "Resources/\(option.manifestResourceName).json",
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
              relativePath:
                "Resources/"
                + stagedGuidanceAudioFilename(
                  selectionID: option.selectionID,
                  logicalFilename: filename
                ),
              data: resource.data
            )
          )
        }
        audioDescriptors.append(
          AppBundleGuidanceAudioReleaseDescriptor(
            selectionID: option.selectionID,
            displayName: option.displayName,
            manifestResourceName: option.manifestResourceName,
            expectedManifestSHA256: sha256Hex(audioManifestData),
            expectedReleaseID: audioRelease.manifest.releaseID
          )
        )
      }
    }
    var audioReleaseIDs: Set<String> = []
    for descriptor in audioDescriptors {
      guard audioReleaseIDs.insert(descriptor.expectedReleaseID).inserted
      else {
        throw
          AppBundleReleaseStagingError.duplicateGuidanceAudioReleaseID(
            descriptor.expectedReleaseID
          )
      }
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
      guidanceAudioChoices: audioDescriptors,
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
          audioManifestResourceNames: Set(
            configuration.guidanceAudioOptions.map(
              \.manifestResourceName
            )
          ),
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
    var audioSelectionIDs: Set<String> = []
    for option in configuration.guidanceAudioOptions {
      if !isValidGuidanceAudioOption(option) {
        issues.append(.invalidGuidanceAudioOption)
      }
      if !audioSelectionIDs.insert(option.selectionID).inserted {
        issues.append(.duplicateGuidanceAudioSelectionID)
      }
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
    let resourceNames =
      [
        configuration.productResourceName,
        configuration.preDriveEvidenceManifestResourceName,
      ].compactMap { $0 }
      + configuration.guidanceAudioOptions.map(
        \.manifestResourceName
      )
    if Set(resourceNames).count != resourceNames.count {
      issues.append(.duplicateManifestResourceName)
    }
    return issues
  }

  private static func resourceKind(
    relativePath: String,
    productResourceName: String,
    audioManifestResourceNames: Set<String>,
    preDriveEvidenceManifestResourceName: String?
  ) -> AppBundleStagedResourceKind {
    if relativePath == "Resources/\(productResourceName).json" {
      return .productRelease
    }
    if relativePath.hasPrefix("Resources/"),
      relativePath.hasSuffix(".json")
    {
      let resourceName = String(
        relativePath
          .dropFirst("Resources/".count)
          .dropLast(".json".count)
      )
      if audioManifestResourceNames.contains(resourceName) {
        return .guidanceAudioManifest
      }
    }
    if let preDriveEvidenceManifestResourceName,
      relativePath
        == "Resources/\(preDriveEvidenceManifestResourceName).json"
    {
      return .preDriveEvidenceManifest
    }
    return .guidanceAudioWave
  }

  private static func isValidGuidanceAudioOption(
    _ option: AppBundleGuidanceAudioStagingOption
  ) -> Bool {
    let names = [
      option.displayName.japanese,
      option.displayName.simplifiedChinese,
      option.displayName.english,
    ]
    return
      isSafeSelectionID(option.selectionID)
      && isSafeResourceName(option.manifestResourceName)
      && names.allSatisfy {
        !$0.isEmpty
          && $0
            == $0.trimmingCharacters(
              in: .whitespacesAndNewlines
            )
      }
  }

  public static func stagedGuidanceAudioFilename(
    selectionID: String,
    logicalFilename: String
  ) -> String {
    "\(selectionID)--\(logicalFilename)"
  }

  private static func isSafeSelectionID(_ value: String) -> Bool {
    !value.isEmpty
      && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
      && value.allSatisfy {
        $0.isASCII
          && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_"
            || $0 == ".")
      }
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
    let audioSource =
      descriptor.guidanceAudioChoices.isEmpty
      ? "[]"
      : "[\n"
        + descriptor.guidanceAudioChoices.map { audio in
          """
              AppBundleGuidanceAudioReleaseDescriptor(
                selectionID: \(swiftString(audio.selectionID)),
                displayName: AppBundleGuidanceAudioDisplayName(
                  japanese: \(swiftString(audio.displayName.japanese)),
                  simplifiedChinese: \(swiftString(audio.displayName.simplifiedChinese)),
                  english: \(swiftString(audio.displayName.english))
                ),
                manifestResourceName: \(swiftString(audio.manifestResourceName)),
                expectedManifestSHA256: \(swiftString(audio.expectedManifestSHA256)),
                expectedReleaseID: \(swiftString(audio.expectedReleaseID))
              )
          """
        }.joined(separator: ",\n")
        + "\n          ]"
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
          guidanceAudioChoices: \(audioSource),
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
