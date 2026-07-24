import Foundation
import KaidoNavigation

private enum CLIError: Error, CustomStringConvertible {
  case usage
  case readFailed(String, Error)
  case invalidNavigation([NavigationReleaseIssue])
  case invalidProduct([KaidoProductReleaseIssue])

  var description: String {
    switch self {
    case .usage:
      """
      Usage:
        kaido-release validate-navigation --artifact <navigation-release.json>
        kaido-release validate-product --artifact <product-release.json>
      """
    case .readFailed(let path, let error):
      "Cannot read \(path): \(error)"
    case .invalidNavigation(let issues):
      "Navigation release is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    case .invalidProduct(let issues):
      "Product release is blocked:\n"
        + issues.map { "  \($0.code)" }.joined(separator: "\n")
    }
  }
}

private enum Command {
  case validateNavigation(String)
  case validateProduct(String)
}

private struct Arguments {
  let command: Command

  init(_ values: [String]) throws {
    guard values.count == 3,
      values[1] == "--artifact"
    else {
      throw CLIError.usage
    }
    switch values[0] {
    case "validate-navigation":
      command = .validateNavigation(values[2])
    case "validate-product":
      command = .validateProduct(values[2])
    default:
      throw CLIError.usage
    }
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
  switch arguments.command {
  case .validateNavigation(let path):
    do {
      let release = try NavigationReleaseArtifactCodec.decode(read(path: path))
      print(
        "PASS: \(release.releaseID) resolves "
          + "\(release.sourceRegistry.references.count) evidence sources and "
          + "\(release.assetEvidence.count) released asset records for "
          + "\(release.bundle.routePlan.occurrences.count) RoutePlan occurrences"
      )
    } catch NavigationReleaseError.invalid(let issues) {
      throw CLIError.invalidNavigation(issues)
    }
  case .validateProduct(let path):
    do {
      let release = try KaidoProductReleaseArtifactCodec.decode(read(path: path))
      print(
        "PASS: \(release.releaseID) binds navigation release "
          + "\(release.navigation.releaseID) to Route Atlas "
          + "\(release.routeAtlas.definition.id) for "
          + "\(release.navigation.bundle.routePlan.occurrences.count) "
          + "RoutePlan occurrences; runtime use "
          + "\(release.runtimeUse.evidenceScope.rawValue)/"
          + "\(release.runtimeUse.liveInputPolicy.rawValue); foreground "
          + "authority "
          + (release.foregroundLiveInputAuthority == nil ? "DISABLED" : "ADMITTED")
      )
    } catch KaidoProductReleaseError.invalid(let issues) {
      throw CLIError.invalidProduct(issues)
    }
  }
} catch {
  writeError(String(describing: error))
  exit(1)
}
