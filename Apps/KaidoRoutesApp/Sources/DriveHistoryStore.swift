import Foundation
import KaidoDomain

struct DriveHistoryEntry: Codable, Equatable, Identifiable {
  let id: UUID
  let routePlan: RoutePlan
  let routeName: String
  let templateParameters: [String: String]
  let startedAtMilliseconds: Int
  let endedAtMilliseconds: Int
  let arrived: Bool
  let recordedDistanceMeters: Double
  let recordedDurationMilliseconds: Int
  let averageSpeedMetersPerSecond: Double?
  let minimumSpeedMetersPerSecond: Double?
  let maximumSpeedMetersPerSecond: Double?
  let laps: [WholeShutoDriveRecord.LapSplit]

  var hasValidMeasurements: Bool {
    startedAtMilliseconds >= 0 && endedAtMilliseconds >= startedAtMilliseconds
      && recordedDurationMilliseconds >= 0
      && recordedDistanceMeters.isFinite && recordedDistanceMeters >= 0
      && [averageSpeedMetersPerSecond, minimumSpeedMetersPerSecond, maximumSpeedMetersPerSecond]
        .compactMap { $0 }.allSatisfy { $0.isFinite && $0 >= 0 }
      && laps.allSatisfy { $0.lapNumber > 0 && $0.durationMilliseconds >= 0 }
      && Set(laps.map(\.lapNumber)).count == laps.count
  }

  init?(record: WholeShutoDriveRecord, routePlan: RoutePlan, routeName: String,
    templateParameters: [String: String], arrived: Bool)
  {
    guard record.hasRecordedIntervals,
      let start = record.startedAtMilliseconds, let end = record.endedAtMilliseconds
    else { return nil }
    id = record.id
    self.routePlan = routePlan
    self.routeName = routeName
    self.templateParameters = templateParameters
    startedAtMilliseconds = start
    endedAtMilliseconds = end
    self.arrived = arrived
    recordedDistanceMeters = record.recordedDistanceMeters
    recordedDurationMilliseconds = record.recordedDurationMilliseconds
    averageSpeedMetersPerSecond = record.averageSpeedMetersPerSecond
    minimumSpeedMetersPerSecond = record.minimumSpeedMetersPerSecond
    maximumSpeedMetersPerSecond = record.maximumSpeedMetersPerSecond
    laps = record.completedLaps
  }
}

@MainActor
protocol DriveHistoryStoring {
  func load() throws -> [DriveHistoryEntry]
  func save(_ entry: DriveHistoryEntry) throws
  func remove(id: UUID) throws
}

@MainActor
final class FileDriveHistoryStore: DriveHistoryStoring {
  enum StoreError: Error { case invalidRecord }
  private let directory: URL

  init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("DriveHistory", isDirectory: true)) {
    self.directory = directory
  }

  func load() throws -> [DriveHistoryEntry] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "json" }
      .map { url in
        let entry = try JSONDecoder().decode(DriveHistoryEntry.self, from: Data(contentsOf: url))
        guard entry.hasValidMeasurements,
          url.deletingPathExtension().lastPathComponent == entry.id.uuidString
        else { throw StoreError.invalidRecord }
        return entry
      }
      .sorted { $0.startedAtMilliseconds > $1.startedAtMilliseconds }
  }

  func save(_ entry: DriveHistoryEntry) throws {
    guard entry.hasValidMeasurements else { throw StoreError.invalidRecord }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONEncoder().encode(entry).write(to: url(for: entry.id), options: .atomic)
  }

  func remove(id: UUID) throws { try FileManager.default.removeItem(at: url(for: id)) }

  private func url(for id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension("json") }

  static func defaultStore() -> any DriveHistoryStoring {
    #if DEBUG
      if NSClassFromString("XCTestCase") != nil { return MemoryDriveHistoryStore() }
    #endif
    return FileDriveHistoryStore()
  }
}

@MainActor
final class MemoryDriveHistoryStore: DriveHistoryStoring {
  private var entries: [UUID: DriveHistoryEntry] = [:]
  func load() -> [DriveHistoryEntry] { entries.values.sorted { $0.startedAtMilliseconds > $1.startedAtMilliseconds } }
  func save(_ entry: DriveHistoryEntry) { entries[entry.id] = entry }
  func remove(id: UUID) { entries[id] = nil }
}
