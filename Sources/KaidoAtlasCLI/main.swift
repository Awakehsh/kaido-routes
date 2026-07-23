import Foundation
import KaidoNavigation

private enum CLIError: Error, CustomStringConvertible {
  case usage
  case readFailed(String, Error)
  case decodeFailed(String, Error)
  case invalid([RouteAtlasContextIssue])

  var description: String {
    switch self {
    case .usage:
      """
      Usage:
        kaido-atlas validate --source <source.json> --context <context.json>
        kaido-atlas validate-release --artifact <release-artifact.json>
      """
    case .readFailed(let path, let error):
      "Cannot read \(path): \(error)"
    case .decodeFailed(let path, let error):
      "Cannot decode \(path): \(error)"
    case .invalid(let issues):
      "Route Atlas context is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    }
  }
}

private enum Command {
  case validateContext(sourcePath: String, contextPath: String)
  case validateRelease(artifactPath: String)
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
    let artifact = try decode(
      RouteAtlasReleaseArtifact.self,
      path: artifactPath
    )
    do {
      let release = try RouteAtlasRelease(artifact: artifact)
      print(
        "PASS: \(release.definition.id) resolves "
          + "\(release.sourceRegistry.references.count) evidence sources and "
          + "\(release.topologySlice.edges.count) directed topology edges for "
          + "\(release.routePlan.occurrences.count) RoutePlan occurrences"
      )
    } catch RouteAtlasReleaseError.invalid(let issues) {
      writeError(
        "Route Atlas release is blocked:\n"
          + issues.map { "  \($0.code)" }.joined(separator: "\n")
      )
      exit(1)
    }
  }
} catch {
  writeError(String(describing: error))
  exit(1)
}
