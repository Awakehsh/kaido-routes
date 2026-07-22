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
        var results: [SurfaceProbeResult] = []
        for repetition in 1...arguments.repeatCount {
          let timestamp = ISO8601DateFormatter().string(from: Date())
          results.append(
            try await runner.run(
              fixture: fixture,
              originID: arguments.originID,
              context: SurfaceProbeRunContext(
                runID: "local.mapkit.\(UUID().uuidString.lowercased())",
                requestedAt: timestamp,
                environment: [
                  "mode": "local-live-mapkit",
                  "operating_system": ProcessInfo.processInfo.operatingSystemVersionString,
                  "output": arguments.repeatCount == 1 ? "stdout" : "scalar-summary-only",
                  "repetition": "\(repetition)-of-\(arguments.repeatCount)",
                ],
                retentionClassification: .rawLocalOnly
              )
            )
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

  private struct LiveProbeArguments {
    let fixturePath: String
    let graphPath: String
    let originID: String
    let repeatCount: Int
    let pretty: Bool

    static func parse(_ commandLine: [String]) throws -> LiveProbeArguments? {
      var fixturePath: String?
      var graphPath: String?
      var originID: String?
      var repeatCount = 1
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
        case "--repeat":
          let rawValue = try value(after: &index, in: commandLine)
          guard let count = Int(rawValue), (1...20).contains(count) else {
            throw LiveProbeCommandError.invalidRepeatCount(rawValue)
          }
          repeatCount = count
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
        repeatCount: repeatCount,
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
    case invalidRepeatCount(String)

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
      case .invalidRepeatCount(let value):
        "--repeat must be an integer from 1 through 20, received: \(value)"
      }
    }
  }

  private let usage = """
    Usage:
      kaido-surface-probe \\
        --fixture <entrance-fixture.json> \\
        --graph <directed-road-graph.json> \\
        --origin <origin-id> \\
        --allow-live-mapkit [--repeat <1...20>] [--pretty]

    One request writes a normalized raw-local result. Repeated requests write a
    scalar-only stability summary without coordinates, instructions, edge IDs,
    path hashes, or candidate IDs. Provider data review remains REVIEW_REQUIRED;
    do not commit either output without review.
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
