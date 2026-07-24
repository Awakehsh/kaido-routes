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
  #expect(results.count == 59)
  #expect(results.reduce(0) { $0 + $1.assertionCount } == 405)

  for result in results {
    let details = result.failures.map(\.description).joined(separator: "\n")
    #expect(result.passed, "\(result.scenarioID): \(details)")
  }
}

@Test("Portable pre-drive review blocks an unauthorized positive live state")
func portablePreDriveReviewBlocksUnauthorizedRealtimePassage() throws {
  let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let path =
    repositoryRoot
    .appendingPathComponent("e2e", isDirectory: true)
    .appendingPathComponent("scenarios", isDirectory: true)
    .appendingPathComponent("kr-u04-pre-drive-review.json")
  var root = try #require(
    JSONSerialization.jsonObject(with: Data(contentsOf: path))
      as? [String: Any]
  )
  var given = try #require(root["given"] as? [String: Any])
  var inputs = try #require(given["inputs"] as? [String: Any])
  var evidence = try #require(
    inputs["pre_drive_evidence"] as? [String: Any]
  )
  evidence["passage_evidence"] = "REALTIME_CONFIRMED_PASSABLE"
  inputs["pre_drive_evidence"] = evidence
  given["inputs"] = inputs
  root["given"] = given

  let scenario = try JSONDecoder().decode(
    PortableScenario.self,
    from: JSONSerialization.data(withJSONObject: root)
  )
  let result = try ScenarioRunner().run(scenario)
  let statusFailure = try #require(
    result.failures.first(where: {
      $0.subject == "pre_drive.evidence.status"
    })
  )

  #expect(!result.passed)
  #expect(statusFailure.actual == .string("BLOCKED"))
}
