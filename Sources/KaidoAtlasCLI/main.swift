import Foundation
import KaidoNavigation

private enum CLIError: Error, CustomStringConvertible {
  case usage
  case readFailed(String, Error)
  case decodeFailed(String, Error)
  case outputExists(String)
  case writeFailed(String, Error)
  case invalid([RouteAtlasContextIssue])
  case invalidRelease([RouteAtlasReleaseIssue])
  case releaseAuthoring(RouteAtlasReleaseAuthoringError)

  var description: String {
    switch self {
    case .usage:
      """
      Usage:
        kaido-atlas validate --source <source.json> --context <context.json>
        kaido-atlas validate-release --artifact <release-artifact.json>
        kaido-atlas build-release \
          --draft <release-draft.json> \
          --config <release-authoring.json> \
          --output <release-artifact.json>
      """
    case .readFailed(let path, let error):
      "Cannot read \(path): \(error)"
    case .decodeFailed(let path, let error):
      "Cannot decode \(path): \(error)"
    case .outputExists(let path):
      "Refusing to overwrite existing output: \(path)"
    case .writeFailed(let path, let error):
      "Cannot write \(path): \(error)"
    case .invalid(let issues):
      "Route Atlas context is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    case .invalidRelease(let issues):
      "Route Atlas release is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    case .releaseAuthoring(let error):
      Self.releaseAuthoringDescription(error)
    }
  }

  private static func releaseAuthoringDescription(
    _ error: RouteAtlasReleaseAuthoringError
  ) -> String {
    switch error {
    case .invalidDraft(let issues):
      "Route Atlas release draft is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    case .invalidConfiguration(let issues):
      "Route Atlas release authoring configuration is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    case .invalidRelease(let issues):
      "Route Atlas release authoring whole gate is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    }
  }
}

private enum Command {
  case validateContext(sourcePath: String, contextPath: String)
  case validateRelease(artifactPath: String)
  case buildRelease(
    draftPath: String,
    configurationPath: String,
    outputPath: String
  )
}

private struct Arguments {
  let command: Command

  init(_ values: [String]) throws {
    guard let operation = values.first else {
      throw CLIError.usage
    }
    if operation == "validate-release" {
      guard values.count == 3, values[1] == "--artifact" else {
        throw CLIError.usage
      }
      command = .validateRelease(artifactPath: values[2])
      return
    }
    if operation == "build-release" {
      var draftPath: String?
      var configurationPath: String?
      var outputPath: String?
      var index = 1
      while index < values.count {
        guard index + 1 < values.count else {
          throw CLIError.usage
        }
        switch values[index] {
        case "--draft":
          guard draftPath == nil else { throw CLIError.usage }
          draftPath = values[index + 1]
        case "--config":
          guard configurationPath == nil else {
            throw CLIError.usage
          }
          configurationPath = values[index + 1]
        case "--output":
          guard outputPath == nil else { throw CLIError.usage }
          outputPath = values[index + 1]
        default:
          throw CLIError.usage
        }
        index += 2
      }
      guard let draftPath, let configurationPath, let outputPath else {
        throw CLIError.usage
      }
      command = .buildRelease(
        draftPath: draftPath,
        configurationPath: configurationPath,
        outputPath: outputPath
      )
      return
    }
    guard operation == "validate" else {
      throw CLIError.usage
    }
    var sourcePath: String?
    var contextPath: String?
    var index = 1
    while index < values.count {
      guard index + 1 < values.count else {
        throw CLIError.usage
      }
      switch values[index] {
      case "--source":
        guard sourcePath == nil else { throw CLIError.usage }
        sourcePath = values[index + 1]
      case "--context":
        guard contextPath == nil else { throw CLIError.usage }
        contextPath = values[index + 1]
      default:
        throw CLIError.usage
      }
      index += 2
    }
    guard let sourcePath, let contextPath else {
      throw CLIError.usage
    }
    command = .validateContext(
      sourcePath: sourcePath,
      contextPath: contextPath
    )
  }
}

private func decode<Value: Decodable>(
  _ type: Value.Type,
  path: String
) throws -> Value {
  let data: Data
  do {
    data = try Data(contentsOf: URL(fileURLWithPath: path))
  } catch {
    throw CLIError.readFailed(path, error)
  }
  do {
    return try JSONDecoder().decode(type, from: data)
  } catch {
    throw CLIError.decodeFailed(path, error)
  }
}

private func writeError(_ value: String) {
  FileHandle.standardError.write(Data((value + "\n").utf8))
}

private func writeNew(_ data: Data, path: String) throws {
  let url = URL(fileURLWithPath: path)
  guard !FileManager.default.fileExists(atPath: url.path) else {
    throw CLIError.outputExists(path)
  }
  let temporaryURL = url.deletingLastPathComponent()
    .appendingPathComponent(
      ".kaido-atlas-\(UUID().uuidString).tmp",
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

do {
  let arguments = try Arguments(Array(CommandLine.arguments.dropFirst()))
  switch arguments.command {
  case .validateContext(let sourcePath, let contextPath):
    let source = try decode(
      RouteAtlasContextSource.self,
      path: sourcePath
    )
    let context = try decode(
      RouteAtlasContextDefinition.self,
      path: contextPath
    )
    do {
      let bundle = try RouteAtlasContextBundle(
        source: source,
        definition: context
      )
      print(
        "PASS: \(bundle.definition.id) is CONTEXT_ONLY with "
          + "\(bundle.definition.coverage.sourceFeatureCount) source features, "
          + "\(bundle.definition.coverage.pathCount) paths, "
          + "\(bundle.definition.coverage.vertexCount) vertices, and "
          + "\(bundle.definition.coverage.routeNameCount) route names"
      )
    } catch RouteAtlasContextError.invalid(let issues) {
      throw CLIError.invalid(issues)
    }
  case .validateRelease(let artifactPath):
    do {
      let artifact = try decode(
        RouteAtlasReleaseArtifact.self,
        path: artifactPath
      )
      let encoded = try JSONEncoder().encode(artifact)
      let release = try RouteAtlasReleaseArtifactCodec.decode(encoded)
      print(
        "PASS: \(release.definition.id) resolves "
          + "\(release.sourceRegistry.references.count) evidence sources and "
          + "\(release.topologySlice.edges.count) directed topology edges for "
          + "\(release.routePlan.occurrences.count) RoutePlan occurrences"
      )
    } catch RouteAtlasReleaseError.invalid(let issues) {
      throw CLIError.invalidRelease(issues)
    }
  case .buildRelease(
    let draftPath,
    let configurationPath,
    let outputPath
  ):
    let draft = try decode(
      RouteAtlasReleaseDraft.self,
      path: draftPath
    )
    let configuration = try decode(
      RouteAtlasReleaseAuthoringConfiguration.self,
      path: configurationPath
    )
    let artifact: RouteAtlasReleaseArtifact
    do {
      artifact = try RouteAtlasReleaseAuthor.buildArtifact(
        draft: draft,
        configuration: configuration
      )
    } catch let error as RouteAtlasReleaseAuthoringError {
      throw CLIError.releaseAuthoring(error)
    }
    let encoded = try RouteAtlasReleaseArtifactCodec.encode(artifact)
    let release = try RouteAtlasReleaseArtifactCodec.decode(encoded)
    try writeNew(encoded, path: outputPath)
    print(
      "PASS: wrote Route Atlas release \(release.definition.id) with "
        + "\(release.sourceRegistry.references.count) evidence sources and "
        + "\(release.topologySlice.edges.count) directed topology edges for "
        + "\(release.routePlan.occurrences.count) RoutePlan occurrences; "
        + "output \(outputPath)"
    )
  }
} catch {
  writeError(String(describing: error))
  exit(1)
}
