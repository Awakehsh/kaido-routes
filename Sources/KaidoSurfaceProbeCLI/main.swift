#if canImport(MapKit)
  import Foundation
  import KaidoAppleAdapters
  import KaidoSurfaceRouting

  @main
  struct KaidoSurfaceProbeCommand {
    static func main() async {
      do {
        guard let arguments = try LiveProbeArguments.parse(CommandLine.arguments) else {
          writeStandardOutput(usage)
          return
        }

        let fixture: EntranceProbeFixture = try decodeJSON(at: arguments.fixturePath)
        let graph: SurfaceRoadGraphSnapshot = try decodeJSON(at: arguments.graphPath)
        let runner = SurfaceProbeRunner(
          provider: MapKitSurfaceRouteProvider(),
          inspector: DirectedRoadGraphInspector(graph: graph)
        )
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let result = try await runner.run(
          fixture: fixture,
          originID: arguments.originID,
          context: SurfaceProbeRunContext(
            runID: "local.mapkit.\(UUID().uuidString.lowercased())",
            requestedAt: timestamp,
            environment: [
              "mode": "local-live-mapkit",
              "operating_system": ProcessInfo.processInfo.operatingSystemVersionString,
              "output": "stdout",
            ],
            retentionClassification: .rawLocalOnly
          )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting =
          arguments.pretty
          ? [.prettyPrinted, .sortedKeys]
          : [.sortedKeys]
        writeStandardOutput(String(decoding: try encoder.encode(result), as: UTF8.self))
      } catch {
        writeStandardError("kaido-surface-probe: \(error)\n\n\(usage)")
        Foundation.exit(EXIT_FAILURE)
      }
    }
  }

  private struct LiveProbeArguments {
    let fixturePath: String
    let graphPath: String
    let originID: String
    let pretty: Bool

    static func parse(_ commandLine: [String]) throws -> LiveProbeArguments? {
      var fixturePath: String?
      var graphPath: String?
      var originID: String?
      var pretty = false
      var acknowledgedLiveProvider = false
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
        case "--pretty":
          pretty = true
        case "--allow-live-mapkit":
          acknowledgedLiveProvider = true
        default:
          throw LiveProbeCommandError.unknownArgument(commandLine[index])
        }
        index += 1
      }

      guard acknowledgedLiveProvider else {
        throw LiveProbeCommandError.liveProviderNotAcknowledged
      }
      guard let fixturePath, let graphPath, let originID else {
        throw LiveProbeCommandError.missingRequiredArgument
      }
      return LiveProbeArguments(
        fixturePath: fixturePath,
        graphPath: graphPath,
        originID: originID,
        pretty: pretty
      )
    }

    private static func value(after index: inout Int, in arguments: [String]) throws -> String {
      index += 1
      guard index < arguments.count else {
        throw LiveProbeCommandError.missingValue(arguments[index - 1])
      }
      return arguments[index]
    }
  }

  private enum LiveProbeCommandError: Error, CustomStringConvertible {
    case unknownArgument(String)
    case missingValue(String)
    case missingRequiredArgument
    case liveProviderNotAcknowledged

    var description: String {
      switch self {
      case .unknownArgument(let argument):
        "unknown argument: \(argument)"
      case .missingValue(let argument):
        "missing value for \(argument)"
      case .missingRequiredArgument:
        "--fixture, --graph, and --origin are required"
      case .liveProviderNotAcknowledged:
        "--allow-live-mapkit is required because this command performs a live provider request"
      }
    }
  }

  private let usage = """
    Usage:
      kaido-surface-probe \\
        --fixture <entrance-fixture.json> \\
        --graph <directed-road-graph.json> \\
        --origin <origin-id> \\
        --allow-live-mapkit [--pretty]

    The command performs a live MapKit request and writes one normalized JSON
    result to stdout. Redirect output only to the gitignored
    benchmarks/surface-routing/runs/ directory. Provider data review remains
    REVIEW_REQUIRED; do not commit the output.
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

  private func writeStandardError(_ value: String) {
    FileHandle.standardError.write(Data("\(value)\n".utf8))
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
