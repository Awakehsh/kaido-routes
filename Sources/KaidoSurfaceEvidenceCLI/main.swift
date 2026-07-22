import Foundation
import KaidoSurfaceRouting

@main
enum KaidoSurfaceEvidenceCLI {
  static func main() async {
    do {
      let arguments = try Arguments.parse(CommandLine.arguments)
      switch arguments.command {
      case .translate:
        let graph: SurfaceRoadGraphSnapshot = try decodeJSON(at: arguments.graphPath)
        let request: OSMSelectedPathTranslationRequest = try decodeJSON(
          at: try arguments.requiredPath(arguments.requestPath, flag: "--request")
        )
        try writeJSON(
          OSMSelectedPathTranslator(graph: graph).translate(request),
          pretty: arguments.pretty
        )
      case .evaluate:
        let graph: SurfaceRoadGraphSnapshot = try decodeJSON(at: arguments.graphPath)
        let fixture: EntranceProbeFixture = try decodeJSON(
          at: try arguments.requiredPath(arguments.fixturePath, flag: "--fixture")
        )
        let originID = try arguments.requiredPath(arguments.originID, flag: "--origin")
        let candidate: SurfaceRouteCandidate = try decodeJSON(
          at: try arguments.requiredPath(arguments.candidatePath, flag: "--candidate")
        )
        let expectedProviderID = try arguments.requiredPath(
          arguments.expectedProviderID,
          flag: "--expected-provider-id"
        )
        let request = try fixture.makeRequest(originID: originID)
        let startedAt = Date()
        let inspection = await DirectedRoadGraphInspector(graph: graph).inspect(
          candidate: candidate,
          request: request,
          fixture: fixture
        )
        let milliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
        try writeJSON(
          SurfaceHardGateEvaluator.evaluate(
            candidate: candidate,
            request: request,
            fixture: fixture,
            inspection: inspection,
            expectedProviderID: expectedProviderID,
            inspectionLatencyMilliseconds: max(0, milliseconds)
          ),
          pretty: arguments.pretty
        )
      case .validateManifest:
        let graph: SurfaceRoadGraphSnapshot = try decodeJSON(at: arguments.graphPath)
        let manifest: SurfaceRoutingBuildManifest = try decodeJSON(
          at: try arguments.requiredPath(arguments.manifestPath, flag: "--manifest")
        )
        let report = SurfaceRoutingBuildManifestValidator.validate(
          manifest,
          graph: graph,
          profile: try arguments.validationProfile()
        )
        try writeJSON(report, pretty: arguments.pretty)
        if !report.isValid {
          Foundation.exit(EXIT_FAILURE)
        }
      case .normalizeValhalla:
        let graph: SurfaceRoadGraphSnapshot = try decodeJSON(at: arguments.graphPath)
        let routePath = try arguments.requiredPath(
          arguments.routeResponsePath,
          flag: "--route-response"
        )
        let tracePath = try arguments.requiredPath(
          arguments.traceResponsePath,
          flag: "--trace-response"
        )
        let normalizer = ValhallaSurfaceRouteNormalizer(
          providerID: try arguments.requiredPath(arguments.providerID, flag: "--provider-id"),
          expectedProviderDatasetID: try arguments.requiredPath(
            arguments.providerDatasetID,
            flag: "--provider-dataset-id"
          )
        )
        let normalized = try normalizer.normalize(
          routeResponseData: try Data(contentsOf: URL(fileURLWithPath: routePath)),
          traceAttributesResponseData: try Data(contentsOf: URL(fileURLWithPath: tracePath)),
          candidateID: try arguments.requiredPath(arguments.candidateID, flag: "--candidate-id"),
          terminalOSMNodeID: try arguments.requiredInt64(
            arguments.terminalOSMNodeID,
            flag: "--terminal-osm-node-id"
          )
        )
        try writeJSON(
          normalized.translatedCandidate(graph: graph),
          pretty: arguments.pretty
        )
      }
    } catch {
      writeStandardError("kaido-surface-evidence: \(error)\n\n\(usage)")
      Foundation.exit(EXIT_FAILURE)
    }
  }
}

private struct Arguments {
  enum Command: String {
    case translate
    case evaluate
    case validateManifest = "validate-manifest"
    case normalizeValhalla = "normalize-valhalla"
  }

  let command: Command
  let graphPath: String
  let requestPath: String?
  let fixturePath: String?
  let originID: String?
  let candidatePath: String?
  let expectedProviderID: String?
  let manifestPath: String?
  let profile: String?
  let routeResponsePath: String?
  let traceResponsePath: String?
  let candidateID: String?
  let providerID: String?
  let providerDatasetID: String?
  let terminalOSMNodeID: String?
  let pretty: Bool

  static func parse(_ commandLine: [String]) throws -> Arguments {
    guard commandLine.count >= 2, let command = Command(rawValue: commandLine[1]) else {
      throw CLIError.missingCommand
    }
    var values: [String: String] = [:]
    var pretty = false
    var index = 2
    while index < commandLine.count {
      let argument = commandLine[index]
      if argument == "--pretty" {
        pretty = true
      } else {
        guard argument.hasPrefix("--"), index + 1 < commandLine.count else {
          throw CLIError.missingValue(argument)
        }
        index += 1
        values[argument] = commandLine[index]
      }
      index += 1
    }
    guard let graphPath = values["--graph"] else {
      throw CLIError.missingValue("--graph")
    }
    return Arguments(
      command: command,
      graphPath: graphPath,
      requestPath: values["--request"],
      fixturePath: values["--fixture"],
      originID: values["--origin"],
      candidatePath: values["--candidate"],
      expectedProviderID: values["--expected-provider-id"],
      manifestPath: values["--manifest"],
      profile: values["--profile"],
      routeResponsePath: values["--route-response"],
      traceResponsePath: values["--trace-response"],
      candidateID: values["--candidate-id"],
      providerID: values["--provider-id"],
      providerDatasetID: values["--provider-dataset-id"],
      terminalOSMNodeID: values["--terminal-osm-node-id"],
      pretty: pretty
    )
  }

  func requiredPath(_ value: String?, flag: String) throws -> String {
    guard let value else { throw CLIError.missingValue(flag) }
    return value
  }

  func validationProfile() throws -> SurfaceRoutingManifestValidationProfile {
    let value = try requiredPath(profile, flag: "--profile").uppercased()
    guard let profile = SurfaceRoutingManifestValidationProfile(rawValue: value) else {
      throw CLIError.invalidValue("--profile", value)
    }
    return profile
  }

  func requiredInt64(_ value: String?, flag: String) throws -> Int64 {
    let value = try requiredPath(value, flag: flag)
    guard let parsed = Int64(value), parsed > 0 else {
      throw CLIError.invalidValue(flag, value)
    }
    return parsed
  }
}

private enum CLIError: Error, CustomStringConvertible {
  case missingCommand
  case missingValue(String)
  case invalidValue(String, String)

  var description: String {
    switch self {
    case .missingCommand:
      "expected translate, evaluate, validate-manifest, or normalize-valhalla"
    case .missingValue(let flag):
      "missing value for \(flag)"
    case .invalidValue(let flag, let value):
      "invalid value \(value) for \(flag)"
    }
  }
}

private let usage = """
  Usage:
    kaido-surface-evidence translate \\
      --graph <directed-road-graph.json> \\
      --request <osm-path-translation-request.json> [--pretty]

    kaido-surface-evidence evaluate \\
      --graph <directed-road-graph.json> \\
      --fixture <entrance-fixture.json> \\
      --origin <origin-id> \\
      --candidate <surface-route-candidate.json> \\
      --expected-provider-id <provider-id> [--pretty]

    kaido-surface-evidence validate-manifest \\
      --graph <directed-road-graph.json> \\
      --manifest <surface-routing-build-manifest.json> \\
      --profile <STRUCTURAL|RELEASE_CANDIDATE> [--pretty]

    kaido-surface-evidence normalize-valhalla \\
      --graph <directed-road-graph.json> \\
      --route-response <route-response.json> \\
      --trace-response <trace-attributes-response.json> \\
      --candidate-id <candidate-id> \\
      --provider-id <provider-id> \\
      --provider-dataset-id <dataset-id> \\
      --terminal-osm-node-id <osm-node-id> [--pretty]
  """

private func decodeJSON<Value: Decodable>(at path: String) throws -> Value {
  try JSONDecoder().decode(
    Value.self,
    from: Data(contentsOf: URL(fileURLWithPath: path))
  )
}

private func writeJSON<Value: Encodable>(_ value: Value, pretty: Bool) throws {
  let encoder = JSONEncoder()
  encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
  FileHandle.standardOutput.write(try encoder.encode(value))
  FileHandle.standardOutput.write(Data("\n".utf8))
}

private func writeStandardError(_ value: String) {
  FileHandle.standardError.write(Data("\(value)\n".utf8))
}
