import KaidoDomain
import XCTest

@testable import KaidoRoutesApp

@MainActor
final class DriveHistoryStoreTests: XCTestCase {
  func testHistorySurvivesReopeningAndDeletionTargetsOneRecord() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = try entry(start: 1_000)
    let second = try entry(start: 10_000)
    let store = FileDriveHistoryStore(directory: directory)
    try store.save(first)
    try store.save(second)
    let reopened = FileDriveHistoryStore(directory: directory)
    XCTAssertEqual(try reopened.load().map(\.id), [second.id, first.id])
    try reopened.remove(id: second.id)
    XCTAssertEqual(try reopened.load(), [first])
  }

  func testHistoryRejectsARecordWhoseFileIdentityDoesNotMatch() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONEncoder().encode(entry(start: 1_000))
      .write(to: directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json"))
    XCTAssertThrowsError(try FileDriveHistoryStore(directory: directory).load())
  }

  private func entry(start: Int) throws -> DriveHistoryEntry {
    var record = WholeShutoDriveRecord(startedAtMilliseconds: start)
    record.observe(speedMetersPerSecond: 10, atMilliseconds: start)
    record.observe(speedMetersPerSecond: 10, atMilliseconds: start + 1_000)
    record.finish(atMilliseconds: start + 1_000)
    let plan = RoutePlan(
      id: "test.history.plan", networkSnapshotID: "test.history.network",
      entryFacilityID: "test.entry", exitFacilityID: "test.exit", recoveryPolicy: .strict,
      occurrences: [RouteOccurrence(id: "test.edge.0", index: 0, kind: .edge, entityID: "test.edge")]
    )
    return try XCTUnwrap(DriveHistoryEntry(record: record, routePlan: plan,
      routeName: "Test route", templateParameters: [:], arrived: false))
  }
}
