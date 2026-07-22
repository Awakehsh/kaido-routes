import Foundation
import KaidoScenarioRunner

@main
enum KaidoScenariosCLI {
  static func main() throws {
    let path = CommandLine.arguments.dropFirst().first ?? "e2e/scenarios"
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    let results = try ScenarioRunner().run(directory: directory)

    var assertionCount = 0
    var failureCount = 0

    for result in results {
      assertionCount += result.assertionCount
      if result.passed {
        print("PASS \(result.scenarioID) — \(result.title)")
      } else {
        failureCount += result.failures.count
        print("FAIL \(result.scenarioID) — \(result.title)")
        for failure in result.failures {
          print("  \(failure)")
        }
      }
    }

    guard failureCount == 0 else {
      throw CLIError.scenarioFailures(failureCount)
    }
    print("PASS: executed \(results.count) scenarios and \(assertionCount) assertions")
  }
}

private enum CLIError: Error, CustomStringConvertible {
  case scenarioFailures(Int)

  var description: String {
    switch self {
    case .scenarioFailures(let count):
      "Portable scenario execution failed with \(count) assertion failure(s)"
    }
  }
}
