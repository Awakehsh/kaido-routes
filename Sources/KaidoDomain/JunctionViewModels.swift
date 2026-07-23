import Foundation

public enum JunctionViewEvidenceState: String, Codable, Sendable {
  case officialChecked = "OFFICIAL_CHECKED"
  case fieldChecked = "FIELD_CHECKED"
  case released = "RELEASED"
}

public struct JunctionViewEvidence: Equatable, Sendable {
  public let state: JunctionViewEvidenceState
  public let checkedAt: String
  public let sourceReferenceIDs: [String]

  public init(
    state: JunctionViewEvidenceState,
    checkedAt: String,
    sourceReferenceIDs: [String]
  ) {
    self.state = state
    self.checkedAt = checkedAt
    self.sourceReferenceIDs = sourceReferenceIDs
  }
}

public enum JunctionViewPathRole: String, Codable, Sendable {
  case approach = "APPROACH"
  case selected = "SELECTED"
  case alternative = "ALTERNATIVE"
}

/// A renderer-neutral point in a normalized 0...1 junction-view coordinate space.
public struct JunctionViewPoint: Equatable, Sendable {
  public let x: Double
  public let y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

public struct JunctionViewPath: Equatable, Sendable {
  public let id: String
  public let role: JunctionViewPathRole
  public let points: [JunctionViewPoint]

  public init(id: String, role: JunctionViewPathRole, points: [JunctionViewPoint]) {
    self.id = id
    self.role = role
    self.points = points
  }
}

/// Lane indices are zero-based from the left in the driver's direction of travel.
public struct JunctionViewLaneLayout: Equatable, Sendable {
  public let laneCount: Int
  public let allowedLaneIndices: [Int]
  public let preferredLaneIndices: [Int]

  public init(
    laneCount: Int,
    allowedLaneIndices: [Int],
    preferredLaneIndices: [Int]
  ) {
    self.laneCount = laneCount
    self.allowedLaneIndices = allowedLaneIndices
    self.preferredLaneIndices = preferredLaneIndices
  }
}

/// A reviewed, snapshot- and occurrence-bound source for an independently rendered junction inset.
public struct JunctionViewDefinition: Equatable, Sendable {
  public let id: String
  public let networkSnapshotID: String
  public let movementOccurrenceID: String
  public let paths: [JunctionViewPath]
  public let laneLayout: JunctionViewLaneLayout
  public let japaneseSignText: String
  public let routeShields: [String]
  public let evidence: JunctionViewEvidence

  public init(
    id: String,
    networkSnapshotID: String,
    movementOccurrenceID: String,
    paths: [JunctionViewPath],
    laneLayout: JunctionViewLaneLayout,
    japaneseSignText: String,
    routeShields: [String],
    evidence: JunctionViewEvidence
  ) {
    self.id = id
    self.networkSnapshotID = networkSnapshotID
    self.movementOccurrenceID = movementOccurrenceID
    self.paths = paths
    self.laneLayout = laneLayout
    self.japaneseSignText = japaneseSignText
    self.routeShields = routeShields
    self.evidence = evidence
  }
}

public enum JunctionViewValidationError: Error, Equatable, Sendable {
  case missingID
  case missingNetworkSnapshotID
  case missingMovementOccurrenceID
  case unreleasedEvidence
  case invalidCheckedDate
  case missingSourceReference
  case duplicatePathID
  case invalidPathGeometry(String)
  case invalidPathRoles
  case disconnectedPathGeometry(String)
  case invalidLaneCount
  case duplicateLaneIndex
  case laneIndexOutOfRange
  case preferredLaneNotAllowed
  case missingJapaneseSignText
  case missingRouteShield
}

public enum JunctionViewValidator {
  public static func validate(_ definition: JunctionViewDefinition) throws {
    guard !normalized(definition.id).isEmpty else {
      throw JunctionViewValidationError.missingID
    }
    guard !normalized(definition.networkSnapshotID).isEmpty else {
      throw JunctionViewValidationError.missingNetworkSnapshotID
    }
    guard !normalized(definition.movementOccurrenceID).isEmpty else {
      throw JunctionViewValidationError.missingMovementOccurrenceID
    }
    guard definition.evidence.state == .released else {
      throw JunctionViewValidationError.unreleasedEvidence
    }
    guard isISODate(definition.evidence.checkedAt) else {
      throw JunctionViewValidationError.invalidCheckedDate
    }
    guard !definition.evidence.sourceReferenceIDs.isEmpty,
      definition.evidence.sourceReferenceIDs.allSatisfy({ !normalized($0).isEmpty })
    else {
      throw JunctionViewValidationError.missingSourceReference
    }

    guard Set(definition.paths.map(\.id)).count == definition.paths.count else {
      throw JunctionViewValidationError.duplicatePathID
    }
    for path in definition.paths {
      guard !normalized(path.id).isEmpty,
        path.points.count >= 2,
        path.points.allSatisfy({ point in
          point.x.isFinite && point.y.isFinite
            && (0...1).contains(point.x) && (0...1).contains(point.y)
        })
      else {
        throw JunctionViewValidationError.invalidPathGeometry(path.id)
      }
    }
    guard definition.paths.count(where: { $0.role == .approach }) == 1,
      definition.paths.count(where: { $0.role == .selected }) == 1,
      definition.paths.contains(where: { $0.role == .alternative })
    else {
      throw JunctionViewValidationError.invalidPathRoles
    }
    guard let approach = definition.paths.first(where: { $0.role == .approach }),
      let branchPoint = approach.points.last
    else {
      throw JunctionViewValidationError.invalidPathRoles
    }
    for path in definition.paths where path.role != .approach {
      guard path.points.first == branchPoint else {
        throw JunctionViewValidationError.disconnectedPathGeometry(path.id)
      }
    }

    let layout = definition.laneLayout
    guard layout.laneCount > 0, !layout.allowedLaneIndices.isEmpty else {
      throw JunctionViewValidationError.invalidLaneCount
    }
    let allLaneIndices = layout.allowedLaneIndices + layout.preferredLaneIndices
    guard Set(layout.allowedLaneIndices).count == layout.allowedLaneIndices.count,
      Set(layout.preferredLaneIndices).count == layout.preferredLaneIndices.count
    else {
      throw JunctionViewValidationError.duplicateLaneIndex
    }
    guard allLaneIndices.allSatisfy({ (0..<layout.laneCount).contains($0) }) else {
      throw JunctionViewValidationError.laneIndexOutOfRange
    }
    guard Set(layout.preferredLaneIndices).isSubset(of: Set(layout.allowedLaneIndices)) else {
      throw JunctionViewValidationError.preferredLaneNotAllowed
    }
    guard !normalized(definition.japaneseSignText).isEmpty else {
      throw JunctionViewValidationError.missingJapaneseSignText
    }
    guard !definition.routeShields.isEmpty,
      definition.routeShields.allSatisfy({ !normalized($0).isEmpty })
    else {
      throw JunctionViewValidationError.missingRouteShield
    }
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func isISODate(_ value: String) -> Bool {
    let parts = value.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3,
      parts[0].count == 4,
      parts[1].count == 2,
      parts[2].count == 2,
      let year = Int(parts[0]),
      let month = Int(parts[1]),
      let day = Int(parts[2])
    else { return false }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    components.year = year
    components.month = month
    components.day = day
    guard let date = components.date else { return false }
    let resolved = calendar.dateComponents([.year, .month, .day], from: date)
    return resolved.year == year && resolved.month == month && resolved.day == day
  }
}
