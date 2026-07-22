import Foundation
import KaidoNavigation

@main
struct KaidoMatcherReplayCLI {
  static func main() {
    do {
      let arguments = Array(CommandLine.arguments.dropFirst())
      guard arguments.count == 1 else {
        throw CLIError.usage
      }
      let fixtureURLs = try fixtureURLs(at: URL(fileURLWithPath: arguments[0]))
      guard !fixtureURLs.isEmpty else { throw CLIError.noFixtures(arguments[0]) }

      let decoder = JSONDecoder()
      let runner = NearestEdgeNegativeControl()
      var failedFixtureIDs: [String] = []
      var totalObservations = 0
      for fixtureURL in fixtureURLs {
        let fixture = try decoder.decode(
          MatcherReplayFixture.self,
          from: Data(contentsOf: fixtureURL)
        )
        let firstReport = try runner.run(fixture: fixture)
        let secondReport = try runner.run(fixture: fixture)
        let deterministic = firstReport == secondReport
        totalObservations += firstReport.metrics.observationCount
        let passed = deterministic && firstReport.expectationMatched == true
        if !passed { failedFixtureIDs.append(fixture.fixtureID) }
        let status = passed ? "PASS" : "FAIL"
        let failures = firstReport.safetyFailures.map(\.rawValue).joined(separator: ",")
        print(
          "\(status) \(fixture.fixtureID) — observations=\(firstReport.metrics.observationCount) "
            + "edge_top1=\(firstReport.metrics.edgeTop1CorrectCount) "
            + "expected_negative_control_failures=[\(failures)] deterministic=\(deterministic)"
        )
      }

      guard failedFixtureIDs.isEmpty else {
        throw CLIError.fixtureFailures(failedFixtureIDs)
      }
      print(
        "PASS: replayed \(fixtureURLs.count) matcher fixtures and \(totalObservations) observations"
      )
    } catch {
      FileHandle.standardError.write(Data("ERROR: \(error)\n".utf8))
      Foundation.exit(EXIT_FAILURE)
    }
  }

  private static func fixtureURLs(at url: URL) throws -> [URL] {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      throw CLIError.notFound(url.path)
    }
    if !isDirectory.boolValue { return [url] }
    guard
      let enumerator = FileManager.default.enumerator(
        at: url,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
    else {
      throw CLIError.notFound(url.path)
    }
    return enumerator.compactMap { item in
      guard let itemURL = item as? URL, itemURL.pathExtension == "json" else { return nil }
      return itemURL
    }.sorted { $0.path < $1.path }
  }
}

private enum CLIError: Error, CustomStringConvertible {
  case usage
  case notFound(String)
  case noFixtures(String)
  case fixtureFailures([String])

  var description: String {
    switch self {
    case .usage:
      "usage: kaido-matcher-replay <fixture.json|fixture-directory>"
    case .notFound(let path):
      "fixture path does not exist: \(path)"
    case .noFixtures(let path):
      "fixture directory contains no JSON files: \(path)"
    case .fixtureFailures(let fixtureIDs):
      "matcher replay expectation mismatch: \(fixtureIDs.joined(separator: ", "))"
    }
  }
}
