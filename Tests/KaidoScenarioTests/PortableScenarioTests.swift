import Foundation
import KaidoScenarioRunner
import Testing

@Test("Portable E2E scenarios execute against the Swift core")
func portableScenariosExecute() throws {
  let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let directory =
    repositoryRoot
    .appendingPathComponent("e2e", isDirectory: true)
    .appendingPathComponent("scenarios", isDirectory: true)

  let results = try ScenarioRunner().run(directory: directory)
  #expect(results.count == 25)

  for result in results {
    let details = result.failures.map(\.description).joined(separator: "\n")
    #expect(result.passed, "\(result.scenarioID): \(details)")
  }
}
