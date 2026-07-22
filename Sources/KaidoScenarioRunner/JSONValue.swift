import Foundation

public indirect enum JSONValue: Equatable, Sendable, Codable, CustomStringConvertible {
  case null
  case bool(Bool)
  case integer(Int)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int.self) {
      self = .integer(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Unsupported JSON value"
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null:
      try container.encodeNil()
    case .bool(let value):
      try container.encode(value)
    case .integer(let value):
      try container.encode(value)
    case .number(let value):
      try container.encode(value)
    case .string(let value):
      try container.encode(value)
    case .array(let value):
      try container.encode(value)
    case .object(let value):
      try container.encode(value)
    }
  }

  public var stringValue: String? {
    guard case .string(let value) = self else { return nil }
    return value
  }

  public var boolValue: Bool? {
    guard case .bool(let value) = self else { return nil }
    return value
  }

  public var intValue: Int? {
    switch self {
    case .integer(let value): value
    case .number(let value) where value.rounded() == value: Int(value)
    default: nil
    }
  }

  public var doubleValue: Double? {
    switch self {
    case .integer(let value): Double(value)
    case .number(let value): value
    default: nil
    }
  }

  public var arrayValue: [JSONValue]? {
    guard case .array(let value) = self else { return nil }
    return value
  }

  public var objectValue: [String: JSONValue]? {
    guard case .object(let value) = self else { return nil }
    return value
  }

  public var description: String {
    switch self {
    case .null: "null"
    case .bool(let value): String(value)
    case .integer(let value): String(value)
    case .number(let value): String(value)
    case .string(let value): "\"\(value)\""
    case .array(let values): "[\(values.map(\.description).joined(separator: ", "))]"
    case .object(let values):
      "{\(values.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: ", "))}"
    }
  }

  public func semanticallyEquals(_ other: JSONValue) -> Bool {
    if let lhs = doubleValue, let rhs = other.doubleValue {
      return lhs == rhs
    }
    return self == other
  }
}

extension Dictionary where Key == String, Value == JSONValue {
  func required(_ key: String) throws -> JSONValue {
    guard let value = self[key] else {
      throw ScenarioExecutionError.missingInput(key)
    }
    return value
  }

  func requiredString(_ key: String) throws -> String {
    guard let value = try required(key).stringValue else {
      throw ScenarioExecutionError.invalidInput(key)
    }
    return value
  }

  func string(_ key: String) -> String? { self[key]?.stringValue }
  func bool(_ key: String) -> Bool? { self[key]?.boolValue }
  func int(_ key: String) -> Int? { self[key]?.intValue }
  func double(_ key: String) -> Double? { self[key]?.doubleValue }
  func array(_ key: String) -> [JSONValue]? { self[key]?.arrayValue }
  func object(_ key: String) -> [String: JSONValue]? { self[key]?.objectValue }
}
