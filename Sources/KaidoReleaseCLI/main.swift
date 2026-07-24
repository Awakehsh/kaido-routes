import Foundation
import KaidoAppleAdapters
import KaidoNavigation
import KaidoPresentation

private enum CLIError: Error, CustomStringConvertible {
  case usage
  case readFailed(String, Error)
  case writeFailed(String, Error)
  case outputExists(String)
  case decodeFailed(String, Error)
  case invalidNavigation([NavigationReleaseIssue])
  case navigationAuthoring(NavigationReleaseAuthoringError)
  case invalidProduct([KaidoProductReleaseIssue])
  case productAuthoring(KaidoProductReleaseAuthoringError)
  case invalidGuidanceAudio([GuidanceAudioReleaseIssue])
  case invalidPreDriveEvidence([PreDriveEvidenceBundleIssue])
  case preDriveEvidenceAuthoring(PreDriveEvidenceAuthoringError)
  case guidanceAudioAuthoring(GuidanceAudioAuthoringError)
  case appBundleStaging(AppBundleReleaseStagingError)

  var description: String {
    switch self {
    case .usage:
      """
      Usage:
        kaido-release validate-navigation --artifact <navigation-release.json>
        kaido-release build-navigation \\
          --draft <navigation-release-draft.json> \\
          --config <navigation-release-authoring.json> \\
          --output <navigation-release.json>
        kaido-release validate-product --artifact <product-release.json>
        kaido-release build-product \\
          --navigation-artifact <navigation-release.json> \\
          --atlas-artifact <route-atlas-release.json> \\
          --config <product-release-authoring.json> \\
          --output <product-release.json>
        kaido-release export-guidance-audio-worklist \\
          --product-artifact <product-release.json> --output <worklist.json>
        kaido-release build-guidance-audio \\
          --product-artifact <product-release.json> \\
          --config <authoring-config.json> --resources <wav-directory> \\
          --output <guidance-audio-release.json>
        kaido-release validate-guidance-audio \\
          --product-artifact <product-release.json> \\
          --manifest <guidance-audio-release.json> \\
          --resources <wav-directory>
        kaido-release validate-pre-drive-evidence \\
          --product-artifact <product-release.json> \\
          --manifest <pre-drive-evidence.json>
        kaido-release build-pre-drive-evidence \\
          --product-artifact <product-release.json> \\
          --draft <pre-drive-evidence-draft.json> \\
          --config <pre-drive-evidence-authoring.json> \\
          --output <pre-drive-evidence.json>
        kaido-release prepare-app-bundle \\
          --product-artifact <product-release.json> \\
          --config <app-bundle-staging.json> \\
          [--guidance-audio-manifest <guidance-audio-release.json> \\
           --guidance-audio-resources <wav-directory>] \\
          [--pre-drive-evidence-manifest <pre-drive-evidence.json>] \\
          --output <new-staging-directory>
      """
    case .readFailed(let path, let error):
      "Cannot read \(path): \(error)"
    case .writeFailed(let path, let error):
      "Cannot write \(path): \(error)"
    case .outputExists(let path):
      "Refusing to overwrite existing output: \(path)"
    case .decodeFailed(let path, let error):
      "Cannot decode \(path): \(error)"
    case .invalidNavigation(let issues):
      "Navigation release is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    case .navigationAuthoring(let error):
      Self.navigationAuthoringDescription(error)
    case .invalidProduct(let issues):
      "Product release is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    case .productAuthoring(let error):
      Self.productAuthoringDescription(error)
    case .invalidGuidanceAudio(let issues):
      "Guidance audio release is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    case .invalidPreDriveEvidence(let issues):
      "Pre-drive evidence bundle is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    case .preDriveEvidenceAuthoring(let error):
      Self.preDriveEvidenceAuthoringDescription(error)
    case .guidanceAudioAuthoring(let error):
      Self.authoringDescription(error)
    case .appBundleStaging(let error):
      Self.appBundleStagingDescription(error)
    }
  }

  private static func productAuthoringDescription(
    _ error: KaidoProductReleaseAuthoringError
  ) -> String {
    switch error {
    case .invalidConfiguration(let issues):
      "Product release authoring configuration is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    case .invalidNavigationRelease(let issues):
      "Product release authoring navigation input is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    case .invalidRouteAtlasRelease(let issues):
      "Product release authoring Route Atlas input is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    case .invalidProductRelease(let issues):
      "Product release authoring joint gate is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    }
  }

  private static func navigationAuthoringDescription(
    _ error: NavigationReleaseAuthoringError
  ) -> String {
    switch error {
    case .invalidDraft(let issues):
      "Navigation release draft is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    case .invalidConfiguration(let issues):
      "Navigation release authoring configuration is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    case .invalidRelease(let issues):
      "Navigation release authoring whole gate is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    }
  }

  private static func authoringDescription(
    _ error: GuidanceAudioAuthoringError
  ) -> String {
    switch error {
    case .invalidProductGuidance:
      "Guidance audio authoring is blocked: product guidance is invalid"
    case .worklistDrift:
      "Guidance audio authoring is blocked: worklist drift"
    case .invalidConfiguration(let issues):
      "Guidance audio authoring configuration is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    case .resourceMissing(let filename):
      "Guidance audio resource is missing: \(filename)"
    case .resourceUnreadable(let filename):
      "Guidance audio resource is unreadable: \(filename)"
    case .invalidWaveAudio(let filename):
      "Guidance audio resource is not valid PCM16 WAV: \(filename)"
    case .invalidRelease(let issues):
      "Guidance audio release is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    }
  }

  private static func preDriveEvidenceAuthoringDescription(
    _ error: PreDriveEvidenceAuthoringError
  ) -> String {
    switch error {
    case .foregroundProductRequired:
      "Pre-drive evidence authoring requires a released-road foreground product"
    case .invalidDraft(let issues):
      "Pre-drive evidence draft is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    case .invalidConfiguration(let issues):
      "Pre-drive evidence authoring configuration is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    case .invalidBundle(let issues):
      "Pre-drive evidence authoring whole gate is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    }
  }

  private static func appBundleStagingDescription(
    _ error: AppBundleReleaseStagingError
  ) -> String {
    switch error {
    case .invalidConfiguration(let issues):
      "App bundle staging configuration is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    case .invalidProductArtifact:
      "App bundle staging product artifact cannot be decoded"
    case .invalidProductRelease(let issues):
      "App bundle staging product release is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    case .foregroundProductRequired:
      "App bundle staging requires a released-road foreground product"
    case .guidanceAudioInputMismatch:
      "App bundle staging audio configuration and inputs do not agree"
    case .invalidGuidanceAudioArtifact:
      "App bundle staging guidance audio artifact cannot be decoded"
    case .invalidGuidanceAudioRelease(let issues):
      "App bundle staging guidance audio release is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    case .preDriveEvidenceInputMismatch:
      "App bundle staging pre-drive evidence configuration and input do not agree"
    case .invalidPreDriveEvidenceArtifact:
      "App bundle staging pre-drive evidence artifact cannot be decoded"
    case .invalidPreDriveEvidenceBundle(let issues):
      "App bundle staging pre-drive evidence is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    case .duplicateResourceFilename(let filename):
      "App bundle staging resource filename is duplicated: \(filename)"
    }
  }
}

private enum Command {
  case validateNavigation(artifact: String)
  case buildNavigation(
    draft: String,
    configuration: String,
    output: String
  )
  case validateProduct(artifact: String)
  case buildProduct(
    navigationArtifact: String,
    routeAtlasArtifact: String,
    configuration: String,
    output: String
  )
  case exportGuidanceAudioWorklist(
    productArtifact: String,
    output: String
  )
  case buildGuidanceAudio(
    productArtifact: String,
    configuration: String,
    resources: String,
    output: String
  )
  case validateGuidanceAudio(
    productArtifact: String,
    manifest: String,
    resources: String
  )
  case validatePreDriveEvidence(
    productArtifact: String,
    manifest: String
  )
  case buildPreDriveEvidence(
    productArtifact: String,
    draft: String,
    configuration: String,
    output: String
  )
  case prepareAppBundle(
    productArtifact: String,
    configuration: String,
    guidanceAudioManifest: String?,
    guidanceAudioResources: String?,
    preDriveEvidenceManifest: String?,
    output: String
  )
}

private struct Arguments {
  let command: Command

  init(_ values: [String]) throws {
    guard let commandName = values.first else {
      throw CLIError.usage
    }
    let flags = try FlagValues(Array(values.dropFirst()))
    switch commandName {
    case "validate-navigation":
      try flags.require(exactly: ["--artifact"])
      command = .validateNavigation(
        artifact: try flags.value("--artifact")
      )
    case "build-navigation":
      try flags.require(
        exactly: ["--draft", "--config", "--output"]
      )
      command = .buildNavigation(
        draft: try flags.value("--draft"),
        configuration: try flags.value("--config"),
        output: try flags.value("--output")
      )
    case "validate-product":
      try flags.require(exactly: ["--artifact"])
      command = .validateProduct(
        artifact: try flags.value("--artifact")
      )
    case "build-product":
      try flags.require(
        exactly: [
          "--navigation-artifact",
          "--atlas-artifact",
          "--config",
          "--output",
        ]
      )
      command = .buildProduct(
        navigationArtifact: try flags.value("--navigation-artifact"),
        routeAtlasArtifact: try flags.value("--atlas-artifact"),
        configuration: try flags.value("--config"),
        output: try flags.value("--output")
      )
    case "export-guidance-audio-worklist":
      try flags.require(
        exactly: ["--product-artifact", "--output"]
      )
      command = .exportGuidanceAudioWorklist(
        productArtifact: try flags.value("--product-artifact"),
        output: try flags.value("--output")
      )
    case "build-guidance-audio":
      try flags.require(
        exactly: [
          "--product-artifact",
          "--config",
          "--resources",
          "--output",
        ]
      )
      command = .buildGuidanceAudio(
        productArtifact: try flags.value("--product-artifact"),
        configuration: try flags.value("--config"),
        resources: try flags.value("--resources"),
        output: try flags.value("--output")
      )
    case "validate-guidance-audio":
      try flags.require(
        exactly: [
          "--product-artifact",
          "--manifest",
          "--resources",
        ]
      )
      command = .validateGuidanceAudio(
        productArtifact: try flags.value("--product-artifact"),
        manifest: try flags.value("--manifest"),
        resources: try flags.value("--resources")
      )
    case "validate-pre-drive-evidence":
      try flags.require(
        exactly: ["--product-artifact", "--manifest"]
      )
      command = .validatePreDriveEvidence(
        productArtifact: try flags.value("--product-artifact"),
        manifest: try flags.value("--manifest")
      )
    case "build-pre-drive-evidence":
      try flags.require(
        exactly: [
          "--product-artifact",
          "--draft",
          "--config",
          "--output",
        ]
      )
      command = .buildPreDriveEvidence(
        productArtifact: try flags.value("--product-artifact"),
        draft: try flags.value("--draft"),
        configuration: try flags.value("--config"),
        output: try flags.value("--output")
      )
    case "prepare-app-bundle":
      let baseFlags: Set<String> = [
        "--product-artifact",
        "--config",
        "--output",
      ]
      let audioFlags = baseFlags.union([
        "--guidance-audio-manifest",
        "--guidance-audio-resources",
      ])
      let evidenceFlags = baseFlags.union([
        "--pre-drive-evidence-manifest"
      ])
      let completeFlags = audioFlags.union([
        "--pre-drive-evidence-manifest"
      ])
      let guidanceAudioManifest: String?
      let guidanceAudioResources: String?
      let preDriveEvidenceManifest: String?
      if flags.matches(exactly: baseFlags) {
        guidanceAudioManifest = nil
        guidanceAudioResources = nil
        preDriveEvidenceManifest = nil
      } else if flags.matches(exactly: audioFlags) {
        guidanceAudioManifest = try flags.value(
          "--guidance-audio-manifest"
        )
        guidanceAudioResources = try flags.value(
          "--guidance-audio-resources"
        )
        preDriveEvidenceManifest = nil
      } else if flags.matches(exactly: evidenceFlags) {
        guidanceAudioManifest = nil
        guidanceAudioResources = nil
        preDriveEvidenceManifest = try flags.value(
          "--pre-drive-evidence-manifest"
        )
      } else {
        try flags.require(exactly: completeFlags)
        guidanceAudioManifest = try flags.value(
          "--guidance-audio-manifest"
        )
        guidanceAudioResources = try flags.value(
          "--guidance-audio-resources"
        )
        preDriveEvidenceManifest = try flags.value(
          "--pre-drive-evidence-manifest"
        )
      }
      command = .prepareAppBundle(
        productArtifact: try flags.value("--product-artifact"),
        configuration: try flags.value("--config"),
        guidanceAudioManifest: guidanceAudioManifest,
        guidanceAudioResources: guidanceAudioResources,
        preDriveEvidenceManifest: preDriveEvidenceManifest,
        output: try flags.value("--output")
      )
    default:
      throw CLIError.usage
    }
  }
}

private struct FlagValues {
  private let values: [String: String]

  init(_ arguments: [String]) throws {
    guard arguments.count.isMultiple(of: 2) else {
      throw CLIError.usage
    }
    var result: [String: String] = [:]
    var index = 0
    while index < arguments.count {
      let flag = arguments[index]
      let value = arguments[index + 1]
      guard
        flag.hasPrefix("--"),
        flag.count > 2,
        result[flag] == nil,
        !value.isEmpty
      else {
        throw CLIError.usage
      }
      result[flag] = value
      index += 2
    }
    values = result
  }

  func require(exactly required: Set<String>) throws {
    guard Set(values.keys) == required else {
      throw CLIError.usage
    }
  }

  func matches(exactly required: Set<String>) -> Bool {
    Set(values.keys) == required
  }

  func value(_ flag: String) throws -> String {
    guard let value = values[flag] else {
      throw CLIError.usage
    }
    return value
  }
}

private func read(path: String) throws -> Data {
  do {
    return try Data(contentsOf: URL(fileURLWithPath: path))
  } catch {
    throw CLIError.readFailed(path, error)
  }
}

private func writeNew(_ data: Data, path: String) throws {
  let url = URL(fileURLWithPath: path)
  guard !FileManager.default.fileExists(atPath: url.path) else {
    throw CLIError.outputExists(path)
  }
  let temporaryURL = url.deletingLastPathComponent()
    .appendingPathComponent(
      ".kaido-release-\(UUID().uuidString).tmp",
      isDirectory: false
    )
  defer {
    try? FileManager.default.removeItem(at: temporaryURL)
  }
  do {
    try data.write(to: temporaryURL, options: .atomic)
    try FileManager.default.moveItem(at: temporaryURL, to: url)
  } catch {
    if FileManager.default.fileExists(atPath: url.path) {
      throw CLIError.outputExists(path)
    }
    throw CLIError.writeFailed(path, error)
  }
}

private func writeNewDirectory(
  _ package: AppBundleReleaseStagingPackage,
  path: String
) throws {
  let outputURL = URL(fileURLWithPath: path, isDirectory: true)
    .standardizedFileURL
  guard !FileManager.default.fileExists(atPath: outputURL.path) else {
    throw CLIError.outputExists(path)
  }
  let parentURL = outputURL.deletingLastPathComponent()
  let temporaryURL = parentURL.appendingPathComponent(
    ".kaido-app-bundle-\(UUID().uuidString).tmp",
    isDirectory: true
  )
  defer {
    try? FileManager.default.removeItem(at: temporaryURL)
  }
  do {
    try FileManager.default.createDirectory(
      at: temporaryURL,
      withIntermediateDirectories: false
    )
    for file in package.files {
      let fileURL = temporaryURL.appendingPathComponent(
        file.relativePath,
        isDirectory: false
      ).standardizedFileURL
      guard
        fileURL.path.hasPrefix(temporaryURL.path + "/")
      else {
        throw CLIError.writeFailed(
          path,
          CocoaError(.fileWriteInvalidFileName)
        )
      }
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try file.data.write(to: fileURL, options: .atomic)
    }
    try FileManager.default.moveItem(
      at: temporaryURL,
      to: outputURL
    )
  } catch let error as CLIError {
    throw error
  } catch {
    if FileManager.default.fileExists(atPath: outputURL.path) {
      throw CLIError.outputExists(path)
    }
    throw CLIError.writeFailed(path, error)
  }
}

private func decodeProductRelease(
  path: String
) throws -> KaidoProductRelease {
  do {
    return try KaidoProductReleaseArtifactCodec.decode(
      read(path: path)
    )
  } catch KaidoProductReleaseError.invalid(let issues) {
    throw CLIError.invalidProduct(issues)
  }
}

private func decode<T: Decodable>(
  _ type: T.Type,
  path: String
) throws -> T {
  do {
    return try JSONDecoder().decode(type, from: read(path: path))
  } catch let error as CLIError {
    throw error
  } catch {
    throw CLIError.decodeFailed(path, error)
  }
}

private func guidanceAudioResource(
  filename: String,
  directoryPath: String
) throws -> GuidanceAudioResource? {
  guard isSafeWaveFilename(filename) else { return nil }
  let directoryURL = URL(
    fileURLWithPath: directoryPath,
    isDirectory: true
  ).standardizedFileURL.resolvingSymlinksInPath()
  let candidateURL =
    directoryURL
    .appendingPathComponent(filename, isDirectory: false)
    .standardizedFileURL
    .resolvingSymlinksInPath()
  guard
    candidateURL.deletingLastPathComponent() == directoryURL
  else {
    return nil
  }
  guard FileManager.default.fileExists(atPath: candidateURL.path) else {
    return nil
  }
  do {
    return GuidanceAudioResource(
      url: candidateURL,
      data: try Data(contentsOf: candidateURL)
    )
  } catch {
    throw CLIError.readFailed(candidateURL.path, error)
  }
}

private func isSafeWaveFilename(_ value: String) -> Bool {
  let parts = value.split(
    separator: ".",
    omittingEmptySubsequences: false
  )
  guard parts.count == 2, parts[1].lowercased() == "wav" else {
    return false
  }
  return !parts[0].isEmpty
    && parts[0].allSatisfy {
      $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_"
    }
}

private func writeError(_ value: String) {
  FileHandle.standardError.write(Data((value + "\n").utf8))
}

do {
  let arguments = try Arguments(Array(CommandLine.arguments.dropFirst()))
  switch arguments.command {
  case .validateNavigation(let artifact):
    do {
      let release = try NavigationReleaseArtifactCodec.decode(
        read(path: artifact)
      )
      print(
        "PASS: \(release.releaseID) resolves "
          + "\(release.sourceRegistry.references.count) evidence sources and "
          + "\(release.assetEvidence.count) released asset records for "
          + "\(release.bundle.routePlan.occurrences.count) RoutePlan occurrences"
      )
    } catch NavigationReleaseError.invalid(let issues) {
      throw CLIError.invalidNavigation(issues)
    }
  case .buildNavigation(
    let draftPath,
    let configurationPath,
    let output
  ):
    let draft = try decode(
      NavigationReleaseDraft.self,
      path: draftPath
    )
    let configuration = try decode(
      NavigationReleaseAuthoringConfiguration.self,
      path: configurationPath
    )
    let artifact: NavigationReleaseArtifact
    do {
      artifact = try NavigationReleaseAuthor.buildArtifact(
        draft: draft,
        configuration: configuration
      )
    } catch let error as NavigationReleaseAuthoringError {
      throw CLIError.navigationAuthoring(error)
    }
    let encoded: Data
    do {
      encoded = try NavigationReleaseArtifactCodec.encode(artifact)
    } catch NavigationReleaseError.invalid(let issues) {
      throw CLIError.invalidNavigation(issues)
    }
    let release = try NavigationReleaseArtifactCodec.decode(encoded)
    try writeNew(encoded, path: output)
    print(
      "PASS: wrote navigation release \(release.releaseID) with "
        + "\(release.assetEvidence.count) released asset records for "
        + "\(release.bundle.routePlan.occurrences.count) RoutePlan "
        + "occurrences; output \(output)"
    )
  case .validateProduct(let artifact):
    let release = try decodeProductRelease(path: artifact)
    print(
      "PASS: \(release.releaseID) binds navigation release "
        + "\(release.navigation.releaseID) to Route Atlas "
        + "\(release.routeAtlas.definition.id) for "
        + "\(release.navigation.bundle.routePlan.occurrences.count) "
        + "RoutePlan occurrences; runtime use "
        + "\(release.runtimeUse.evidenceScope.rawValue)/"
        + "\(release.runtimeUse.liveInputPolicy.rawValue); foreground "
        + "authority "
        + (release.foregroundLiveInputAuthority == nil
          ? "DISABLED" : "ADMITTED")
    )
  case .buildProduct(
    let navigationArtifactPath,
    let routeAtlasArtifactPath,
    let configurationPath,
    let output
  ):
    let navigationArtifact = try decode(
      NavigationReleaseArtifact.self,
      path: navigationArtifactPath
    )
    let routeAtlasArtifact = try decode(
      RouteAtlasReleaseArtifact.self,
      path: routeAtlasArtifactPath
    )
    let configuration = try decode(
      KaidoProductReleaseAuthoringConfiguration.self,
      path: configurationPath
    )
    let artifact: KaidoProductReleaseArtifact
    do {
      artifact = try KaidoProductReleaseAuthor.buildArtifact(
        navigationRelease: navigationArtifact,
        routeAtlasRelease: routeAtlasArtifact,
        configuration: configuration
      )
    } catch let error as KaidoProductReleaseAuthoringError {
      throw CLIError.productAuthoring(error)
    }
    let encoded: Data
    do {
      encoded = try KaidoProductReleaseArtifactCodec.encode(artifact)
    } catch KaidoProductReleaseError.invalid(let issues) {
      throw CLIError.invalidProduct(issues)
    }
    try writeNew(encoded, path: output)
    let release = try KaidoProductReleaseArtifactCodec.decode(encoded)
    print(
      "PASS: wrote released-road product \(release.releaseID) binding "
        + "navigation release \(release.navigation.releaseID) to Route Atlas "
        + "\(release.routeAtlas.definition.id); foreground authority ADMITTED; "
        + "output \(output)"
    )
  case .exportGuidanceAudioWorklist(
    let productArtifact,
    let output
  ):
    let release = try decodeProductRelease(path: productArtifact)
    let encoded = try GuidanceAudioRecordingWorklistCodec.encode(
      productRelease: release
    )
    try writeNew(encoded, path: output)
    let worklist = try GuidanceAudioRecordingWorklistCodec.decode(
      encoded,
      productRelease: release
    )
    print(
      "PASS: wrote \(worklist.items.count) guidance audio work items "
        + "for \(release.releaseID) to \(output)"
    )
  case .buildGuidanceAudio(
    let productArtifact,
    let configurationPath,
    let resources,
    let output
  ):
    let release = try decodeProductRelease(path: productArtifact)
    let configuration =
      try GuidanceAudioAuthoringConfigurationCodec.decode(
        read(path: configurationPath)
      )
    let manifest: GuidanceAudioReleaseManifest
    do {
      manifest = try GuidanceAudioReleaseAuthor.buildManifest(
        productRelease: release,
        configuration: configuration,
        resourceProvider: {
          try guidanceAudioResource(
            filename: $0,
            directoryPath: resources
          )
        }
      )
    } catch let error as GuidanceAudioAuthoringError {
      throw CLIError.guidanceAudioAuthoring(error)
    }
    let encoded: Data
    do {
      encoded = try GuidanceAudioReleaseManifestCodec.encode(
        manifest,
        productRelease: release,
        resourceProvider: {
          try guidanceAudioResource(
            filename: $0,
            directoryPath: resources
          )
        }
      )
    } catch GuidanceAudioReleaseError.invalid(let issues) {
      throw CLIError.invalidGuidanceAudio(issues)
    }
    try writeNew(encoded, path: output)
    print(
      "PASS: wrote guidance audio release \(manifest.releaseID) with "
        + "\(manifest.assets.count) assets to \(output)"
    )
  case .validateGuidanceAudio(
    let productArtifact,
    let manifestPath,
    let resources
  ):
    let release = try decodeProductRelease(path: productArtifact)
    do {
      let audioRelease = try GuidanceAudioReleaseManifestCodec.decode(
        read(path: manifestPath),
        productRelease: release,
        resourceProvider: {
          try guidanceAudioResource(
            filename: $0,
            directoryPath: resources
          )
        }
      )
      print(
        "PASS: \(audioRelease.manifest.releaseID) validates "
          + "\(audioRelease.assets.count) offline guidance assets for "
          + "\(release.releaseID)"
      )
    } catch GuidanceAudioReleaseError.invalid(let issues) {
      throw CLIError.invalidGuidanceAudio(issues)
    }
  case .validatePreDriveEvidence(
    let productArtifact,
    let manifestPath
  ):
    let release = try decodeProductRelease(path: productArtifact)
    do {
      let bundle = try PreDriveEvidenceBundleCodec.decode(
        read(path: manifestPath),
        context: PreDriveEvidenceBundleContext(
          productReleaseID: release.releaseID,
          productReleasedAt: release.releasedAt,
          navigationReleaseID: release.navigation.releaseID,
          routePlan: release.navigation.bundle.routePlan,
          evidenceScope: .releasedRoad
        )
      )
      print(
        "PASS: \(bundle.manifest.releaseID) validates "
          + "\(bundle.manifest.records.count) pre-drive evidence records for "
          + "\(release.releaseID)"
      )
    } catch PreDriveEvidenceBundleError.invalid(let issues) {
      throw CLIError.invalidPreDriveEvidence(issues)
    }
  case .buildPreDriveEvidence(
    let productArtifact,
    let draftPath,
    let configurationPath,
    let output
  ):
    let release = try decodeProductRelease(path: productArtifact)
    let draft = try decode(
      PreDriveEvidenceBundleDraft.self,
      path: draftPath
    )
    let configuration = try decode(
      PreDriveEvidenceAuthoringConfiguration.self,
      path: configurationPath
    )
    let manifest: PreDriveEvidenceBundleManifest
    do {
      manifest = try PreDriveEvidenceBundleAuthor.buildManifest(
        productRelease: release,
        draft: draft,
        configuration: configuration
      )
    } catch let error as PreDriveEvidenceAuthoringError {
      throw CLIError.preDriveEvidenceAuthoring(error)
    }
    let context = PreDriveEvidenceBundleContext(
      productReleaseID: release.releaseID,
      productReleasedAt: release.releasedAt,
      navigationReleaseID: release.navigation.releaseID,
      routePlan: release.navigation.bundle.routePlan,
      evidenceScope: .releasedRoad
    )
    let encoded: Data
    do {
      encoded = try PreDriveEvidenceBundleCodec.encode(
        manifest,
        context: context
      )
    } catch PreDriveEvidenceBundleError.invalid(let issues) {
      throw CLIError.invalidPreDriveEvidence(issues)
    }
    let bundle = try PreDriveEvidenceBundleCodec.decode(
      encoded,
      context: context
    )
    try writeNew(encoded, path: output)
    print(
      "PASS: wrote pre-drive evidence \(bundle.manifest.releaseID) with "
        + "\(bundle.manifest.records.count) exact tariff profiles for "
        + "\(release.releaseID); output \(output)"
    )
  case .prepareAppBundle(
    let productArtifactPath,
    let configurationPath,
    let guidanceAudioManifestPath,
    let guidanceAudioResources,
    let preDriveEvidenceManifestPath,
    let output
  ):
    let productArtifactData = try read(path: productArtifactPath)
    let configuration =
      try AppBundleReleaseStagingConfigurationCodec.decode(
        read(path: configurationPath)
      )
    let guidanceAudioManifestData = try guidanceAudioManifestPath.map {
      try read(path: $0)
    }
    let preDriveEvidenceManifestData =
      try preDriveEvidenceManifestPath.map {
        try read(path: $0)
      }
    let package: AppBundleReleaseStagingPackage
    do {
      package = try AppBundleReleaseStagingAuthor.prepare(
        configuration: configuration,
        productArtifactData: productArtifactData,
        guidanceAudioManifestData: guidanceAudioManifestData,
        guidanceAudioResourceProvider: guidanceAudioResources.map {
          resources in
          {
            try guidanceAudioResource(
              filename: $0,
              directoryPath: resources
            )
          }
        },
        preDriveEvidenceManifestData: preDriveEvidenceManifestData
      )
    } catch let error as AppBundleReleaseStagingError {
      throw CLIError.appBundleStaging(error)
    }
    try writeNewDirectory(package, path: output)
    print(
      "PASS: staged foreground product "
        + "\(package.manifest.descriptor.expectedReleaseID) with "
        + "\(package.manifest.resources.count) hash-bound resources and "
        + "compile-time descriptor ."
        + "\(package.manifest.descriptorSymbol) at \(output)"
    )
  }
} catch {
  writeError(String(describing: error))
  exit(1)
}
