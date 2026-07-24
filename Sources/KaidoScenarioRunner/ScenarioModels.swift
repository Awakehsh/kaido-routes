import Foundation
import KaidoDomain

public struct PortableScenario: Decodable, Sendable {
  public let schemaVersion: String
  public let id: String
  public let title: String
  public let layer: String
  public let given: ScenarioGiven
  public let events: [ScenarioEvent]
  public let assertions: [ScenarioAssertion]

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case id
    case title
    case layer
    case given
    case events = "when"
    case assertions = "then"
  }
}

public struct ScenarioGiven: Decodable, Sendable {
  public let networkSnapshot: NetworkSnapshot
  public let routePlan: RoutePlan?
  public let tariffQuotes: [ScenarioTariffQuote]
  public let inputs: [String: JSONValue]
  public let systemState: [String: JSONValue]

  private enum CodingKeys: String, CodingKey {
    case networkSnapshot = "network_snapshot"
    case routePlan = "route_plan"
    case tariffQuotes = "tariff_quotes"
    case inputs
    case systemState = "system_state"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    networkSnapshot = try container.decode(NetworkSnapshot.self, forKey: .networkSnapshot)
    routePlan = try container.decodeIfPresent(RoutePlan.self, forKey: .routePlan)
    tariffQuotes =
      try container.decodeIfPresent([ScenarioTariffQuote].self, forKey: .tariffQuotes) ?? []
    inputs = try container.decode([String: JSONValue].self, forKey: .inputs)
    systemState = try container.decode([String: JSONValue].self, forKey: .systemState)
  }
}

public struct ScenarioTariffQuote: Decodable, Equatable, Sendable {
  public let id: String
  public let entryFacilityID: String
  public let exitFacilityID: String
  public let status: String
  public let vehicleClass: ShutoVehicleClass
  public let paymentMethod: ShutoPaymentMethod
  public let tariffVersionID: String
  public let tariffVersionStatus: TariffVersionStatus
  public let tariffDistanceKM: Double?
  public let estimatedAmountYen: Int?
  public let checkedAt: String
  public let officialQueryReference: String

  private enum CodingKeys: String, CodingKey {
    case id = "quote_id"
    case entryFacilityID = "entry_facility_id"
    case exitFacilityID = "exit_facility_id"
    case status
    case vehicleClass = "vehicle_class"
    case paymentMethod = "payment_method"
    case tariffVersionID = "tariff_version_id"
    case tariffVersionStatus = "tariff_version_status"
    case tariffDistanceKM = "tariff_distance_km"
    case estimatedAmountYen = "estimated_amount_yen"
    case checkedAt = "checked_at"
    case officialQueryReference = "official_query_reference"
  }

  public func tariffQuote() throws -> TariffQuote {
    guard let evidenceStatus = TollEvidenceStatus(rawValue: status) else {
      throw ScenarioExecutionError.invalidInput("tariff_quotes.status")
    }
    return TariffQuote(
      id: id,
      entryFacilityID: entryFacilityID,
      exitFacilityID: exitFacilityID,
      vehicleClass: vehicleClass,
      paymentMethod: paymentMethod,
      tariffVersionID: tariffVersionID,
      tariffVersionStatus: tariffVersionStatus,
      tariffDistanceKM: tariffDistanceKM,
      estimatedAmountYen: estimatedAmountYen,
      evidenceStatus: evidenceStatus,
      checkedAt: checkedAt,
      officialQueryReference: officialQueryReference
    )
  }
}

public struct ScenarioEvent: Decodable, Equatable, Sendable {
  public let id: String
  public let atMilliseconds: Int
  public let type: String
  public let payload: [String: JSONValue]

  private enum CodingKeys: String, CodingKey {
    case id
    case atMilliseconds = "at_ms"
    case type
    case payload
  }
}

public struct ScenarioAssertion: Decodable, Equatable, Sendable {
  public let id: String
  public let after: String
  public let category: String
  public let subject: String
  public let matcher: String
  public let expected: JSONValue?
  public let rationale: String
}

public enum ScenarioExecutionError: Error, CustomStringConvertible, Sendable {
  case missingInput(String)
  case invalidInput(String)
  case unsupportedEvent(String)
  case unsupportedCompileShape
  case missingEventSnapshot(String)

  public var description: String {
    switch self {
    case .missingInput(let key): "Missing scenario input: \(key)"
    case .invalidInput(let key): "Invalid scenario input: \(key)"
    case .unsupportedEvent(let type): "Unsupported scenario event: \(type)"
    case .unsupportedCompileShape: "Unsupported route compile input shape"
    case .missingEventSnapshot(let id): "No observation snapshot after event: \(id)"
    }
  }
}

public struct ScenarioFailure: Equatable, Sendable, CustomStringConvertible {
  public let assertionID: String
  public let eventID: String
  public let subject: String
  public let matcher: String
  public let expected: JSONValue?
  public let actual: JSONValue?
  public let rationale: String

  public var description: String {
    "\(assertionID) after \(eventID): \(subject) \(matcher) expected \(expected?.description ?? "<none>"), actual \(actual?.description ?? "<absent>") — \(rationale)"
  }
}

public struct ScenarioResult: Equatable, Sendable {
  public let scenarioID: String
  public let title: String
  public let assertionCount: Int
  public let failures: [ScenarioFailure]

  public var passed: Bool { failures.isEmpty }
}

public enum ScenarioLoader {
  public static func load(directory: URL) throws -> [PortableScenario] {
    let paths = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "json" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

    let decoder = JSONDecoder()
    return try paths.map { path in
      try decoder.decode(PortableScenario.self, from: Data(contentsOf: path))
    }
  }
}
