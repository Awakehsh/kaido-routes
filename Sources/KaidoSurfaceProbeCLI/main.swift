#if canImport(MapKit)
  import Foundation
  import KaidoAppleAdapters
  import KaidoSurfaceRouting

  @main
  struct KaidoSurfaceProbeCommand {
    static func main() async {
      do {
        if CommandLine.arguments.contains("--compare-summary") {
          let comparison = try SummaryComparisonArguments.parse(CommandLine.arguments)
          let summaries: [SurfaceProbeStabilitySummary] = try comparison.summaryPaths.map {
            try decodeJSON(at: $0)
          }
          try writeJSON(
            SurfaceProbeStabilitySummarizer.summarizeWindows(summaries),
            pretty: comparison.pretty
          )
          return
        }
        guard let arguments = try LiveProbeArguments.parse(CommandLine.arguments) else {
          writeStandardOutput(usage)
          return
        }

        let fixture: EntranceProbeFixture = try decodeJSON(at: arguments.fixturePath)
        let graph: SurfaceRoadGraphSnapshot = try decodeJSON(at: arguments.graphPath)
        let results: [SurfaceProbeResult]
        switch arguments.provider {
        case .mapKit:
          results = try await runProbes(
            provider: MapKitSurfaceRouteProvider(),
            fixture: fixture,
            graph: graph,
            arguments: arguments,
            environment: ["mode": "local-live-mapkit"]
          )

        case .valhalla:
          guard #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *) else {
            throw LiveProbeCommandError.unsupportedURLSessionPlatform
          }
          let manifest: SurfaceRoutingBuildManifest = try decodeJSON(
            at: try arguments.required(arguments.manifestPath, flag: "--manifest")
          )
          let baseURLValue = try arguments.required(arguments.baseURL, flag: "--base-url")
          guard let baseURL = URL(string: baseURLValue) else {
            throw LiveProbeCommandError.invalidBaseURL(baseURLValue)
          }
          let binding = try makeValhallaBinding(fixture: fixture, graph: graph)
          let transport = try URLSessionValhallaHTTPTransport(baseURL: baseURL)
          let provider = try ValhallaSurfaceRouteProvider(
            graph: graph,
            manifest: manifest,
            configuration: ValhallaSurfaceProviderConfiguration(
              candidateProviderID: arguments.valhallaProviderID,
              adapterVersion: "live-probe.1",
              narrativeLanguage: .japanese,
              dataReviewStatus: .reviewRequired,
              manifestValidationProfile: .structural,
              approachBindings: [binding]
            ),
            transport: transport
          )
          results = try await runProbes(
            provider: provider,
            fixture: fixture,
            graph: graph,
            arguments: arguments,
            environment: [
              "mode": "local-live-valhalla",
              "manifest_id": manifest.id,
              "provider_dataset_id": manifest.providerDatasetID,
              "service_origin": baseURL.originDescription,
            ]
          )
        }

        if arguments.repeatCount == 1 {
          try writeJSON(results[0], pretty: arguments.pretty)
        } else {
          try writeJSON(
            SurfaceProbeStabilitySummarizer.summarize(results),
            pretty: arguments.pretty
          )
        }
      } catch {
        writeStandardError("kaido-surface-probe: \(error)\n\n\(usage)")
        Foundation.exit(EXIT_FAILURE)
      }
    }
  }

  private enum LiveProbeProvider: String {
    case mapKit
    case valhalla
  }

  private struct SummaryComparisonArguments {
    let summaryPaths: [String]
    let pretty: Bool

    static func parse(_ commandLine: [String]) throws -> SummaryComparisonArguments {
      var summaryPaths: [String] = []
      var pretty = false
      var index = 1
      while index < commandLine.count {
        switch commandLine[index] {
        case "--compare-summary":
          summaryPaths.append(try LiveProbeArguments.value(after: &index, in: commandLine))
        case "--pretty":
          pretty = true
        default:
          throw LiveProbeCommandError.unknownArgument(commandLine[index])
        }
        index += 1
      }
      guard summaryPaths.count >= 2 else {
        throw LiveProbeCommandError.atLeastTwoSummariesRequired
      }
      return SummaryComparisonArguments(summaryPaths: summaryPaths, pretty: pretty)
    }
  }

  private struct LiveProbeArguments {
    let fixturePath: String
    let graphPath: String
    let originID: String
    let provider: LiveProbeProvider
    let manifestPath: String?
    let baseURL: String?
    let valhallaProviderID: String
    let repeatCount: Int
    let pretty: Bool

    static func parse(_ commandLine: [String]) throws -> LiveProbeArguments? {
      var fixturePath: String?
      var graphPath: String?
      var originID: String?
      var provider: LiveProbeProvider?
      var manifestPath: String?
      var baseURL: String?
      var valhallaProviderID = "valhalla.local"
      var valhallaProviderIDWasSet = false
      var repeatCount = 1
      var pretty = false
      var index = 1

      while index < commandLine.count {
        switch commandLine[index] {
        case "--help", "-h":
          return nil
        case "--fixture":
          fixturePath = try value(after: &index, in: commandLine)
        case "--graph":
          graphPath = try value(after: &index, in: commandLine)
        case "--origin":
          originID = try value(after: &index, in: commandLine)
        case "--manifest":
          manifestPath = try value(after: &index, in: commandLine)
        case "--base-url":
          baseURL = try value(after: &index, in: commandLine)
        case "--provider-id":
          valhallaProviderID = try value(after: &index, in: commandLine)
          valhallaProviderIDWasSet = true
        case "--repeat":
          let rawValue = try value(after: &index, in: commandLine)
          guard let count = Int(rawValue), (1...20).contains(count) else {
            throw LiveProbeCommandError.invalidRepeatCount(rawValue)
          }
          repeatCount = count
        case "--pretty":
          pretty = true
        case "--allow-live-mapkit":
          provider = try select(.mapKit, current: provider)
        case "--allow-live-valhalla":
          provider = try select(.valhalla, current: provider)
        default:
          throw LiveProbeCommandError.unknownArgument(commandLine[index])
        }
        index += 1
      }

      guard let provider else {
        throw LiveProbeCommandError.liveProviderNotAcknowledged
      }
      guard let fixturePath, let graphPath, let originID else {
        throw LiveProbeCommandError.missingRequiredArgument
      }
      if provider == .valhalla {
        guard manifestPath != nil, baseURL != nil, !valhallaProviderID.isEmpty else {
          throw LiveProbeCommandError.missingValhallaArgument
        }
      } else if manifestPath != nil || baseURL != nil || valhallaProviderIDWasSet {
        throw LiveProbeCommandError.valhallaArgumentWithMapKit
      }
      return LiveProbeArguments(
        fixturePath: fixturePath,
        graphPath: graphPath,
        originID: originID,
        provider: provider,
        manifestPath: manifestPath,
        baseURL: baseURL,
        valhallaProviderID: valhallaProviderID,
        repeatCount: repeatCount,
        pretty: pretty
      )
    }

    func required(_ value: String?, flag: String) throws -> String {
      guard let value else { throw LiveProbeCommandError.missingValue(flag) }
      return value
    }

    fileprivate static func value(
      after index: inout Int,
      in arguments: [String]
    ) throws -> String {
      index += 1
      guard index < arguments.count else {
        throw LiveProbeCommandError.missingValue(arguments[index - 1])
      }
      return arguments[index]
    }

    private static func select(
      _ candidate: LiveProbeProvider,
      current: LiveProbeProvider?
    ) throws -> LiveProbeProvider {
      guard current == nil || current == candidate else {
        throw LiveProbeCommandError.multipleLiveProviders
      }
      return candidate
    }
  }

  private enum LiveProbeCommandError: Error, CustomStringConvertible {
    case unknownArgument(String)
    case missingValue(String)
    case missingRequiredArgument
    case missingValhallaArgument
    case valhallaArgumentWithMapKit
    case liveProviderNotAcknowledged
    case multipleLiveProviders
    case invalidRepeatCount(String)
    case invalidBaseURL(String)
    case invalidApproachEdge(String)
    case unsupportedURLSessionPlatform
    case atLeastTwoSummariesRequired

    var description: String {
      switch self {
      case .unknownArgument(let argument):
        "unknown argument: \(argument)"
      case .missingValue(let argument):
        "missing value for \(argument)"
      case .missingRequiredArgument:
        "--fixture, --graph, and --origin are required"
      case .missingValhallaArgument:
        "--manifest and --base-url are required for a live Valhalla probe"
      case .valhallaArgumentWithMapKit:
        "--manifest, --base-url, and --provider-id are not valid for a MapKit probe"
      case .liveProviderNotAcknowledged:
        "one of --allow-live-mapkit or --allow-live-valhalla is required"
      case .multipleLiveProviders:
        "choose exactly one live provider"
      case .invalidRepeatCount(let value):
        "--repeat must be an integer from 1 through 20, received: \(value)"
      case .invalidBaseURL(let value):
        "--base-url is invalid: \(value)"
      case .invalidApproachEdge(let edgeID):
        "approach edge does not end at a retained OSM node: \(edgeID)"
      case .unsupportedURLSessionPlatform:
        "the live Valhalla transport requires URLSession async support"
      case .atLeastTwoSummariesRequired:
        "at least two --compare-summary files are required"
      }
    }
  }

  private func runProbes<Provider: SurfaceRouteProvider>(
    provider: Provider,
    fixture: EntranceProbeFixture,
    graph: SurfaceRoadGraphSnapshot,
    arguments: LiveProbeArguments,
    environment: [String: String]
  ) async throws -> [SurfaceProbeResult] {
    let runner = SurfaceProbeRunner(
      provider: provider,
      inspector: DirectedRoadGraphInspector(graph: graph)
    )
    var results: [SurfaceProbeResult] = []
    for repetition in 1...arguments.repeatCount {
      var runEnvironment = environment
      runEnvironment["operating_system"] = ProcessInfo.processInfo.operatingSystemVersionString
      runEnvironment["output"] =
        arguments.repeatCount == 1 ? "stdout" : "scalar-summary-only"
      runEnvironment["repetition"] = "\(repetition)-of-\(arguments.repeatCount)"
      results.append(
        try await runner.run(
          fixture: fixture,
          originID: arguments.originID,
          context: SurfaceProbeRunContext(
            runID: "local.\(arguments.provider.rawValue).\(UUID().uuidString.lowercased())",
            requestedAt: ISO8601DateFormatter().string(from: Date()),
            environment: runEnvironment,
            retentionClassification: .rawLocalOnly
          )
        )
      )
    }
    return results
  }

  private func makeValhallaBinding(
    fixture: EntranceProbeFixture,
    graph: SurfaceRoadGraphSnapshot
  ) throws -> ValhallaApproachIdentityBinding {
    let edgeID = fixture.approachAnchor.directedSurfaceEdgeID
    guard let edge = graph.edges.first(where: { $0.id == edgeID }),
      edge.toNodeID.hasPrefix("osm.node."),
      let terminalOSMNodeID = Int64(edge.toNodeID.dropFirst("osm.node.".count)),
      terminalOSMNodeID > 0
    else {
      throw LiveProbeCommandError.invalidApproachEdge(edgeID)
    }
    return ValhallaApproachIdentityBinding(
      anchorID: fixture.approachAnchor.id,
      directedSurfaceEdgeID: edgeID,
      terminalOSMNodeID: terminalOSMNodeID
    )
  }

  private let usage = """
    Usage:
      kaido-surface-probe \\
        --fixture <entrance-fixture.json> \\
        --graph <directed-road-graph.json> \\
        --origin <origin-id> \\
        --allow-live-mapkit [--repeat <1...20>] [--pretty]

      kaido-surface-probe \\
        --fixture <entrance-fixture.json> \\
        --graph <directed-road-graph.json> \\
        --origin <origin-id> \\
        --manifest <surface-routing-build-manifest.json> \\
        --base-url <self-hosted-valhalla-origin> \\
        --allow-live-valhalla [--provider-id <id>] \\
        [--repeat <1...20>] [--pretty]

    One request writes a normalized raw-local result. Repeated requests write a
    scalar-only stability summary without coordinates, instructions, edge IDs,
    path hashes, or candidate IDs. Provider data review remains REVIEW_REQUIRED;
    do not commit either output without review.

    Compare scalar summaries from separate windows without a provider call:
      kaido-surface-probe \\
        --compare-summary <summary-a.json> \\
        --compare-summary <summary-b.json> [--pretty]
    """

  private func decodeJSON<Value: Decodable>(at path: String) throws -> Value {
    try JSONDecoder().decode(
      Value.self,
      from: Data(contentsOf: URL(fileURLWithPath: path))
    )
  }

  private func writeStandardOutput(_ value: String) {
    FileHandle.standardOutput.write(Data("\(value)\n".utf8))
  }

  private func writeJSON<Value: Encodable>(_ value: Value, pretty: Bool) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
    writeStandardOutput(String(decoding: try encoder.encode(value), as: UTF8.self))
  }

  private func writeStandardError(_ value: String) {
    FileHandle.standardError.write(Data("\(value)\n".utf8))
  }

  extension URL {
    fileprivate var originDescription: String {
      guard let scheme, let host else { return absoluteString }
      if let port {
        return "\(scheme)://\(host):\(port)"
      }
      return "\(scheme)://\(host)"
    }
  }
#else
  import Foundation

  @main
  struct KaidoSurfaceProbeCommand {
    static func main() {
      FileHandle.standardError.write(
        Data("kaido-surface-probe requires an Apple platform with MapKit.\n".utf8)
      )
      Foundation.exit(EXIT_FAILURE)
    }
  }
#endif
