import Foundation
import KaidoNavigation

private enum CLIError: Error, CustomStringConvertible {
  case usage
  case readFailed(String, Error)
  case invalid([NavigationReleaseIssue])

  var description: String {
    switch self {
    case .usage:
      "Usage: kaido-release validate-navigation --artifact <release-artifact.json>"
    case .readFailed(let path, let error):
      "Cannot read \(path): \(error)"
    case .invalid(let issues):
      "Navigation release is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    }
  }
}

private struct Arguments {
  let artifactPath: String

  init(_ values: [String]) throws {
    guard values.count == 3,
      values[0] == "validate-navigation",
      values[1] == "--artifact"
    else {
      throw CLIError.usage
    }
    artifactPath = values[2]
  }
}

private func read(path: String) throws -> Data {
  do {
    return try Data(contentsOf: URL(fileURLWithPath: path))
  } catch {
    throw CLIError.readFailed(path, error)
  }
}

private func writeError(_ value: String) {
  FileHandle.standardError.write(Data((value + "\n").utf8))
}

do {
  let arguments = try Arguments(Array(CommandLine.arguments.dropFirst()))
  let data = try read(path: arguments.artifactPath)
  do {
    let release = try NavigationReleaseArtifactCodec.decode(data)
    print(
      "PASS: \(release.releaseID) resolves "
        + "\(release.sourceRegistry.references.count) evidence sources and "
        + "\(release.assetEvidence.count) released asset records for "
        + "\(release.bundle.routePlan.occurrences.count) RoutePlan occurrences"
    )
  } catch NavigationReleaseError.invalid(let issues) {
    throw CLIError.invalid(issues)
  }
} catch {
  writeError(String(describing: error))
  exit(1)
}
