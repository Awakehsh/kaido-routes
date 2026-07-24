import Foundation
import KaidoAppleAdapters
import KaidoNavigation

private enum CLIError: Error, CustomStringConvertible {
  case usage
  case readFailed(String, Error)
  case writeFailed(String, Error)
  case outputExists(String)
  case invalidNavigation([NavigationReleaseIssue])
  case invalidProduct([KaidoProductReleaseIssue])
  case invalidGuidanceAudio([GuidanceAudioReleaseIssue])
  case guidanceAudioAuthoring(GuidanceAudioAuthoringError)

  var description: String {
    switch self {
    case .usage:
      """
      Usage:
        kaido-release validate-navigation --artifact <navigation-release.json>
        kaido-release validate-product --artifact <product-release.json>
        kaido-release export-guidance-audio-worklist \
          --product-artifact <product-release.json> --output <worklist.json>
        kaido-release build-guidance-audio \
          --product-artifact <product-release.json> \
          --config <authoring-config.json> --resources <wav-directory> \
          --output <guidance-audio-release.json>
        kaido-release validate-guidance-audio \
          --product-artifact <product-release.json> \
          --manifest <guidance-audio-release.json> \
          --resources <wav-directory>
      """
    case .readFailed(let path, let error):
      "Cannot read \(path): \(error)"
    case .writeFailed(let path, let error):
      "Cannot write \(path): \(error)"
    case .outputExists(let path):
      "Refusing to overwrite existing output: \(path)"
    case .invalidNavigation(let issues):
      "Navigation release is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    case .invalidProduct(let issues):
      "Product release is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    case .invalidGuidanceAudio(let issues):
      "Guidance audio release is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    case .guidanceAudioAuthoring(let error):
      Self.authoringDescription(error)
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
}

private enum Command {
  case validateNavigation(artifact: String)
  case validateProduct(artifact: String)
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
    case "validate-product":
      try flags.require(exactly: ["--artifact"])
      command = .validateProduct(
        artifact: try flags.value("--artifact")
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
  }
} catch {
  writeError(String(describing: error))
  exit(1)
}
