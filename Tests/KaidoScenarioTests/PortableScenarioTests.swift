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
  #expect(results.count == 69)
  #expect(results.reduce(0) { $0 + $1.assertionCount } == 488)

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

@Test("Portable pre-drive review blocks tariff evidence for another vehicle class")
func portablePreDriveReviewBlocksVehicleClassDrift() throws {
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
  var tariffQuotes = try #require(given["tariff_quotes"] as? [[String: Any]])
  tariffQuotes[0]["vehicle_class"] = "LIGHT_MOTORCYCLE"
  given["tariff_quotes"] = tariffQuotes
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

@Test("Portable pre-drive review blocks provider drift from session vehicle class")
func portablePreDriveReviewBlocksProviderVehicleClassDrift() throws {
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
  evidence["vehicle_class"] = "LIGHT_MOTORCYCLE"
  inputs["pre_drive_evidence"] = evidence
  given["inputs"] = inputs
  var tariffQuotes = try #require(given["tariff_quotes"] as? [[String: Any]])
  for index in tariffQuotes.indices {
    tariffQuotes[index]["vehicle_class"] = "LIGHT_MOTORCYCLE"
  }
  given["tariff_quotes"] = tariffQuotes
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

@Test("Portable pre-drive review blocks provider drift from session payment method")
func portablePreDriveReviewBlocksProviderPaymentMethodDrift() throws {
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
  evidence["payment_method"] = "CASH"
  inputs["pre_drive_evidence"] = evidence
  given["inputs"] = inputs
  var tariffQuotes = try #require(given["tariff_quotes"] as? [[String: Any]])
  for index in tariffQuotes.indices {
    tariffQuotes[index]["payment_method"] = "CASH"
  }
  given["tariff_quotes"] = tariffQuotes
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
