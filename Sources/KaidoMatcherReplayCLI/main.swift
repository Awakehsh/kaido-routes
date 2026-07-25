import Foundation
import KaidoAppleAdapters
import KaidoNavigation
import KaidoSurfaceRouting

@main
struct KaidoMatcherReplayCLI {
  static func main() async {
    do {
      let arguments = Array(CommandLine.arguments.dropFirst())
      if arguments.first == "build-surface-egress-calibration-artifact" {
        try runSurfaceEgressCalibrationBuild(arguments: arguments)
      } else if arguments.first
        == "validate-surface-egress-calibration-artifact"
      {
        try runSurfaceEgressCalibrationValidation(arguments: arguments)
      } else if arguments.contains("--allow-live-valhalla") {
        try await runLiveValhalla(arguments: arguments)
      } else if arguments.first == "--swift-hmm" {
        try runSwiftHMM(arguments: arguments)
      } else {
        try runNegativeControl(arguments: arguments)
      }
    } catch {
      FileHandle.standardError.write(Data("ERROR: \(error)\n\n\(usage)\n".utf8))
      Foundation.exit(EXIT_FAILURE)
    }
  }

  private static func runNegativeControl(arguments: [String]) throws {
    guard arguments.count == 1 else { throw CLIError.usage }
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
  }

  private static func runSwiftHMM(arguments: [String]) throws {
    guard (2...3).contains(arguments.count),
      arguments.dropFirst(2).allSatisfy({ $0 == "--raw-local" })
    else { throw CLIError.usage }
    let rawLocal = arguments.contains("--raw-local")
    let fixtureURLs = try fixtureURLs(at: URL(fileURLWithPath: arguments[1]))
    guard !fixtureURLs.isEmpty else { throw CLIError.noFixtures(arguments[1]) }

    let decoder = JSONDecoder()
    let matcher = try RouteAwareSwiftMatcher()
    var failedFixtureIDs: [String] = []
    var totalObservations = 0
    var totalEdgeCorrect = 0
    var totalOccurrenceTruth = 0
    var totalOccurrenceCorrect = 0
    var reports: [MatcherReplayReport] = []
    for fixtureURL in fixtureURLs {
      let fixture = try decoder.decode(
        MatcherReplayFixture.self,
        from: Data(contentsOf: fixtureURL)
      )
      let firstReport = try matcher.run(fixture: fixture)
      let secondReport = try matcher.run(fixture: fixture)
      let deterministic = firstReport == secondReport
      let passed = deterministic && firstReport.safetyFailures.isEmpty
      reports.append(firstReport)
      if !passed { failedFixtureIDs.append(fixture.fixtureID) }
      totalObservations += firstReport.metrics.observationCount
      totalEdgeCorrect += firstReport.metrics.edgeTop1CorrectCount
      totalOccurrenceTruth += firstReport.metrics.occurrenceTruthCount
      totalOccurrenceCorrect += firstReport.metrics.occurrenceCorrectCount
      if !rawLocal {
        let status = passed ? "PASS" : "FAIL"
        let failures = firstReport.safetyFailures.map(\.rawValue).joined(separator: ",")
        print(
          "\(status) \(fixture.fixtureID) — observations=\(firstReport.metrics.observationCount) "
            + "edge_top1=\(firstReport.metrics.edgeTop1CorrectCount) "
            + "occurrence=\(firstReport.metrics.occurrenceCorrectCount)/"
            + "\(firstReport.metrics.occurrenceTruthCount) "
            + "safety_failures=[\(failures)] deterministic=\(deterministic)"
        )
      }
    }
    guard failedFixtureIDs.isEmpty else {
      throw CLIError.matcherSafetyFailures(failedFixtureIDs)
    }
    if rawLocal {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      print(String(decoding: try encoder.encode(reports), as: UTF8.self))
    } else {
      print(
        "PASS: Swift HMM replayed \(fixtureURLs.count) fixtures; "
          + "edge_top1=\(totalEdgeCorrect)/\(totalObservations) "
          + "occurrence=\(totalOccurrenceCorrect)/\(totalOccurrenceTruth)"
      )
    }
  }

  private static func runLiveValhalla(arguments: [String]) async throws {
    let arguments = try LiveValhallaArguments.parse(arguments)
    let decoder = JSONDecoder()
    let fixture: MatcherReplayFixture = try decodeJSON(
      at: arguments.fixturePath,
      decoder: decoder
    )
    let graph: SurfaceRoadGraphSnapshot = try decodeJSON(
      at: arguments.graphPath,
      decoder: decoder
    )
    let manifest: SurfaceRoutingBuildManifest = try decodeJSON(
      at: arguments.manifestPath,
      decoder: decoder
    )
    guard let baseURL = URL(string: arguments.baseURL) else {
      throw CLIError.invalidBaseURL(arguments.baseURL)
    }
    guard #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *) else {
      throw CLIError.unsupportedURLSessionPlatform
    }
    let transport = try URLSessionValhallaHTTPTransport(baseURL: baseURL)
    let oracle = try ValhallaMatcherReplayOracle(
      graph: graph,
      manifest: manifest,
      transport: transport
    )
    var reports: [MatcherReplayReport] = []
    for _ in 0..<arguments.repeatCount {
      reports.append(try await oracle.run(fixture: fixture))
    }
    let firstReport = reports[0]
    let summary = LiveValhallaWindowSummary(
      fixtureID: fixture.fixtureID,
      networkSnapshotID: fixture.networkSnapshotID,
      manifestID: manifest.id,
      providerDatasetID: manifest.providerDatasetID,
      algorithmID: firstReport.algorithmID,
      repeatCount: reports.count,
      reportsIdentical: reports.dropFirst().allSatisfy { $0 == firstReport },
      observationCount: firstReport.metrics.observationCount,
      edgeTop1CorrectCount: firstReport.metrics.edgeTop1CorrectCount,
      edgeTop1Accuracy: firstReport.metrics.observationCount == 0
        ? 0
        : Double(firstReport.metrics.edgeTop1CorrectCount)
          / Double(firstReport.metrics.observationCount),
      occurrenceTruthCount: firstReport.metrics.occurrenceTruthCount,
      occurrenceCorrectCount: firstReport.metrics.occurrenceCorrectCount,
      safetyFailures: Array(Set(reports.flatMap(\.safetyFailures))).sorted {
        $0.rawValue < $1.rawValue
      }
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = arguments.pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
    if arguments.rawLocal {
      print(
        String(
          decoding: try encoder.encode(
            LiveValhallaRawLocalOutput(summary: summary, reports: reports)
          ),
          as: UTF8.self
        )
      )
    } else {
      print(String(decoding: try encoder.encode(summary), as: UTF8.self))
    }
  }

  private static func runSurfaceEgressCalibrationBuild(
    arguments: [String]
  ) throws {
    let arguments = try SurfaceCalibrationCLIArguments.parse(arguments)
    guard
      arguments.mode == .build,
      let configurationPath = arguments.configurationPath,
      let outputPath = arguments.outputPath
    else {
      throw CLIError.usage
    }
    let privateTraceData = try arguments.tracePaths.map(readPrivateData)
    let annotationData = try readPrivateData(
      at: arguments.annotationPath
    )
    let configurationData = try readPublicData(
      at: configurationPath
    )
    let configuration: SurfaceEgressMatcherCalibrationAuthoringConfiguration
    do {
      configuration =
        try SurfaceEgressMatcherCalibrationAuthoringConfigurationCodec
        .decode(configurationData)
    } catch {
      throw CLIError.invalidSurfaceCalibrationConfiguration
    }
    let artifact: SurfaceEgressMatcherCalibrationArtifact
    do {
      artifact =
        try SurfaceEgressMatcherCalibrationArtifactAuthor
        .build(
          privateTraceData: privateTraceData,
          privateAnnotationSetData: annotationData,
          configuration: configuration
        )
    } catch let error as SurfaceEgressMatcherCalibrationAuthoringError {
      throw CLIError.surfaceCalibration(error.redactedCodes)
    }
    try writeNew(
      SurfaceEgressMatcherCalibrationArtifactCodec.encode(artifact),
      path: outputPath
    )
    print(surfaceCalibrationSummary("BUILT", artifact: artifact))
  }

  private static func runSurfaceEgressCalibrationValidation(
    arguments: [String]
  ) throws {
    let arguments = try SurfaceCalibrationCLIArguments.parse(arguments)
    guard
      arguments.mode == .validate,
      let artifactPath = arguments.artifactPath
    else {
      throw CLIError.usage
    }
    let privateTraceData = try arguments.tracePaths.map(readPrivateData)
    let annotationData = try readPrivateData(
      at: arguments.annotationPath
    )
    let artifactData = try readPublicData(at: artifactPath)
    let artifact: SurfaceEgressMatcherCalibrationArtifact
    do {
      artifact =
        try SurfaceEgressMatcherCalibrationArtifactAuthor
        .validate(
          artifactData: artifactData,
          privateTraceData: privateTraceData,
          privateAnnotationSetData: annotationData
        )
    } catch let error as SurfaceEgressMatcherCalibrationAuthoringError {
      throw CLIError.surfaceCalibration(error.redactedCodes)
    }
    print(surfaceCalibrationSummary("VALID", artifact: artifact))
  }

  private static func surfaceCalibrationSummary(
    _ status: String,
    artifact: SurfaceEgressMatcherCalibrationArtifact
  ) -> String {
    "\(status) surface-egress calibration report "
      + "\(artifact.report.reportID) "
      + "gate=\(artifact.report.gateStatus.rawValue) "
      + "traces=\(artifact.report.traceCount) "
      + "entries=\(artifact.report.entryCount) "
      + "navigation_authority=false release_approval=false"
  }

  private static func readPrivateData(at path: String) throws -> Data {
    do {
      return try Data(contentsOf: URL(fileURLWithPath: path))
    } catch {
      throw CLIError.privateInputReadFailed
    }
  }

  private static func readPublicData(at path: String) throws -> Data {
    do {
      return try Data(contentsOf: URL(fileURLWithPath: path))
    } catch {
      throw CLIError.notFound(path)
    }
  }

  private static func writeNew(_ data: Data, path: String) throws {
    let outputURL = URL(fileURLWithPath: path)
    guard !FileManager.default.fileExists(atPath: outputURL.path) else {
      throw CLIError.outputExists(path)
    }
    let temporaryURL = outputURL.deletingLastPathComponent()
      .appendingPathComponent(
        ".kaido-surface-calibration-\(UUID().uuidString).tmp"
      )
    defer {
      try? FileManager.default.removeItem(at: temporaryURL)
    }
    do {
      try data.write(to: temporaryURL, options: .atomic)
      try FileManager.default.moveItem(
        at: temporaryURL,
        to: outputURL
      )
    } catch {
      if FileManager.default.fileExists(atPath: outputURL.path) {
        throw CLIError.outputExists(path)
      }
      throw CLIError.writeFailed(path)
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

  private static func decodeJSON<Value: Decodable>(
    at path: String,
    decoder: JSONDecoder
  ) throws -> Value {
    try decoder.decode(Value.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
  }
}

private enum CLIError: Error, CustomStringConvertible {
  case usage
  case notFound(String)
  case noFixtures(String)
  case fixtureFailures([String])
  case matcherSafetyFailures([String])
  case missingArgument(String)
  case unknownArgument(String)
  case invalidRepeatCount(String)
  case invalidBaseURL(String)
  case unsupportedURLSessionPlatform
  case duplicateArgument(String)
  case privateInputReadFailed
  case invalidSurfaceCalibrationConfiguration
  case surfaceCalibration([String])
  case outputExists(String)
  case writeFailed(String)

  var description: String {
    switch self {
    case .usage:
      "invalid command"
    case .notFound(let path):
      "fixture path does not exist: \(path)"
    case .noFixtures(let path):
      "fixture directory contains no JSON files: \(path)"
    case .fixtureFailures(let fixtureIDs):
      "matcher replay expectation mismatch: \(fixtureIDs.joined(separator: ", "))"
    case .matcherSafetyFailures(let fixtureIDs):
      "Swift HMM replay safety failure: \(fixtureIDs.joined(separator: ", "))"
    case .missingArgument(let flag):
      "missing required argument: \(flag)"
    case .unknownArgument(let argument):
      "unknown argument: \(argument)"
    case .invalidRepeatCount(let value):
      "repeat count must be an integer from 1 through 20: \(value)"
    case .invalidBaseURL(let value):
      "invalid Valhalla base URL: \(value)"
    case .unsupportedURLSessionPlatform:
      "live Valhalla replay requires URLSession on a supported Apple platform"
    case .duplicateArgument(let flag):
      "argument may be supplied only once: \(flag)"
    case .privateInputReadFailed:
      "private calibration input could not be read"
    case .invalidSurfaceCalibrationConfiguration:
      "surface-egress calibration authoring configuration could not be decoded"
    case .surfaceCalibration(let codes):
      "surface-egress calibration is blocked:\n"
        + codes.map { "  \($0)" }.joined(separator: "\n")
    case .outputExists(let path):
      "output already exists: \(path)"
    case .writeFailed(let path):
      "output could not be written: \(path)"
    }
  }
}

private struct SurfaceCalibrationCLIArguments {
  enum Mode: Equatable {
    case build
    case validate
  }

  let mode: Mode
  let tracePaths: [String]
  let annotationPath: String
  let configurationPath: String?
  let artifactPath: String?
  let outputPath: String?

  static func parse(
    _ arguments: [String]
  ) throws -> SurfaceCalibrationCLIArguments {
    guard let command = arguments.first else {
      throw CLIError.usage
    }
    let mode: Mode
    switch command {
    case "build-surface-egress-calibration-artifact":
      mode = .build
    case "validate-surface-egress-calibration-artifact":
      mode = .validate
    default:
      throw CLIError.usage
    }
    var tracePaths: [String] = []
    var annotationPath: String?
    var configurationPath: String?
    var artifactPath: String?
    var outputPath: String?
    var index = 1
    while index < arguments.count {
      let flag = arguments[index]
      switch flag {
      case "--trace":
        tracePaths.append(
          try value(after: &index, in: arguments)
        )
      case "--annotations":
        try assignOnce(
          &annotationPath,
          value: value(after: &index, in: arguments),
          flag: flag
        )
      case "--config":
        try assignOnce(
          &configurationPath,
          value: value(after: &index, in: arguments),
          flag: flag
        )
      case "--artifact":
        try assignOnce(
          &artifactPath,
          value: value(after: &index, in: arguments),
          flag: flag
        )
      case "--output":
        try assignOnce(
          &outputPath,
          value: value(after: &index, in: arguments),
          flag: flag
        )
      default:
        throw CLIError.unknownArgument(flag)
      }
      index += 1
    }
    guard !tracePaths.isEmpty else {
      throw CLIError.missingArgument("--trace")
    }
    guard let annotationPath else {
      throw CLIError.missingArgument("--annotations")
    }
    switch mode {
    case .build:
      guard
        configurationPath != nil,
        artifactPath == nil,
        outputPath != nil
      else {
        throw CLIError.usage
      }
    case .validate:
      guard
        configurationPath == nil,
        artifactPath != nil,
        outputPath == nil
      else {
        throw CLIError.usage
      }
    }
    return SurfaceCalibrationCLIArguments(
      mode: mode,
      tracePaths: tracePaths,
      annotationPath: annotationPath,
      configurationPath: configurationPath,
      artifactPath: artifactPath,
      outputPath: outputPath
    )
  }

  private static func value(
    after index: inout Int,
    in arguments: [String]
  ) throws -> String {
    index += 1
    guard
      arguments.indices.contains(index),
      !arguments[index].hasPrefix("--")
    else {
      throw CLIError.missingArgument(arguments[index - 1])
    }
    return arguments[index]
  }

  private static func assignOnce(
    _ target: inout String?,
    value: @autoclosure () throws -> String,
    flag: String
  ) throws {
    guard target == nil else {
      throw CLIError.duplicateArgument(flag)
    }
    target = try value()
  }
}

private struct LiveValhallaArguments {
  let fixturePath: String
  let graphPath: String
  let manifestPath: String
  let baseURL: String
  let repeatCount: Int
  let pretty: Bool
  let rawLocal: Bool

  static func parse(_ arguments: [String]) throws -> LiveValhallaArguments {
    var fixturePath: String?
    var graphPath: String?
    var manifestPath: String?
    var baseURL: String?
    var repeatCount = 1
    var pretty = false
    var rawLocal = false
    var index = 0
    while index < arguments.count {
      switch arguments[index] {
      case "--allow-live-valhalla":
        break
      case "--fixture":
        fixturePath = try value(after: &index, in: arguments)
      case "--graph":
        graphPath = try value(after: &index, in: arguments)
      case "--manifest":
        manifestPath = try value(after: &index, in: arguments)
      case "--base-url":
        baseURL = try value(after: &index, in: arguments)
      case "--repeat":
        let rawValue = try value(after: &index, in: arguments)
        guard let value = Int(rawValue), (1...20).contains(value) else {
          throw CLIError.invalidRepeatCount(rawValue)
        }
        repeatCount = value
      case "--pretty":
        pretty = true
      case "--raw-local":
        rawLocal = true
      default:
        throw CLIError.unknownArgument(arguments[index])
      }
      index += 1
    }
    guard let fixturePath else { throw CLIError.missingArgument("--fixture") }
    guard let graphPath else { throw CLIError.missingArgument("--graph") }
    guard let manifestPath else { throw CLIError.missingArgument("--manifest") }
    guard let baseURL else { throw CLIError.missingArgument("--base-url") }
    return LiveValhallaArguments(
      fixturePath: fixturePath,
      graphPath: graphPath,
      manifestPath: manifestPath,
      baseURL: baseURL,
      repeatCount: repeatCount,
      pretty: pretty,
      rawLocal: rawLocal
    )
  }

  private static func value(after index: inout Int, in arguments: [String]) throws -> String {
    index += 1
    guard arguments.indices.contains(index), !arguments[index].hasPrefix("--") else {
      throw CLIError.missingArgument(arguments[index - 1])
    }
    return arguments[index]
  }
}

private struct LiveValhallaWindowSummary: Encodable {
  let evidenceClassification = "SCALAR_LOCAL_ONLY"
  let fixtureID: String
  let networkSnapshotID: String
  let manifestID: String
  let providerDatasetID: String
  let algorithmID: String
  let repeatCount: Int
  let reportsIdentical: Bool
  let observationCount: Int
  let edgeTop1CorrectCount: Int
  let edgeTop1Accuracy: Double
  let occurrenceTruthCount: Int
  let occurrenceCorrectCount: Int
  let safetyFailures: [MatcherSafetyFailure]

  private enum CodingKeys: String, CodingKey {
    case evidenceClassification = "evidence_classification"
    case fixtureID = "fixture_id"
    case networkSnapshotID = "network_snapshot_id"
    case manifestID = "manifest_id"
    case providerDatasetID = "provider_dataset_id"
    case algorithmID = "algorithm_id"
    case repeatCount = "repeat_count"
    case reportsIdentical = "reports_identical"
    case observationCount = "observation_count"
    case edgeTop1CorrectCount = "edge_top1_correct_count"
    case edgeTop1Accuracy = "edge_top1_accuracy"
    case occurrenceTruthCount = "occurrence_truth_count"
    case occurrenceCorrectCount = "occurrence_correct_count"
    case safetyFailures = "safety_failures"
  }
}

private struct LiveValhallaRawLocalOutput: Encodable {
  let evidenceClassification = "RAW_LOCAL_ONLY"
  let summary: LiveValhallaWindowSummary
  let reports: [MatcherReplayReport]

  private enum CodingKeys: String, CodingKey {
    case evidenceClassification = "evidence_classification"
    case summary
    case reports
  }
}

private let usage = """
  Usage:
    kaido-matcher-replay <fixture.json|fixture-directory>

    kaido-matcher-replay --swift-hmm <fixture.json|fixture-directory> [--raw-local]

    kaido-matcher-replay build-surface-egress-calibration-artifact \\
      --trace <private-trace.json> [--trace <private-trace.json> ...] \\
      --annotations <private-ground-truth.json> \\
      --config <authoring-config.json> \\
      --output <coordinate-free-artifact.json>

    kaido-matcher-replay validate-surface-egress-calibration-artifact \\
      --artifact <coordinate-free-artifact.json> \\
      --trace <private-trace.json> [--trace <private-trace.json> ...] \\
      --annotations <private-ground-truth.json>

    kaido-matcher-replay \\
      --fixture <matcher-fixture.json> \\
      --graph <directed-road-graph.json> \\
      --manifest <surface-routing-build-manifest.json> \\
      --base-url <self-hosted-valhalla-origin> \\
      --allow-live-valhalla [--repeat <1...20>] [--pretty] [--raw-local]

  The default mode executes the deterministic nearest-edge negative control.
  `--swift-hmm` runs the route-aware prototype against the same evaluator and
  fails for nondeterminism or any named safety failure. Live mode is opt-in and
  writes a scalar-only local summary. Keep raw traces,
  provider responses, private graph-derived fixtures, and explicit `--raw-local`
  output outside Git. Surface-egress authoring reads private trace and annotation
  bytes without printing them, binds their SHA-256 values into a coordinate-free
  artifact, refuses overwrite, and requires the same private inputs to validate.
  """
